import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

/// Entrada manual: o `App` do SwiftUI criava uma janela extra (o "quadradão")
/// mesmo com só uma cena de Settings vazia. Aqui o app vive só no notch e no ícone da barra de menu.
@main
enum MyNotchMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var aba: Aba = .player
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = NotchModel()
    let music = MusicClient()
    let notes = NotesStore()
    let tray = TrayStore()
    let nova = NovaStore()
    let ditado = Ditado()

    private var panel: NotchPanel?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NotchPanel()
        panel.contentView = NSHostingView(rootView: NotchView(
            model: model, music: music, notes: notes, tray: tray, nova: nova, ditado: ditado
        ))
        panel.posicionar()
        panel.orderFrontRegardless()
        self.panel = panel

        // Se monitores forem ligados ou desligados, a janela volta para o notch do Mac.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.panel?.posicionar() }
            .store(in: &cancellables)

        // onHover do SwiftUI não recebe a saída quando a janela muda de tamanho
        // sob o cursor, então o mouse é checado direto contra a área do painel.
        acompanharMouse = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.atualizarHover() }
        }

        criarMenuDaBarra()
        registrarAtalho()
    }

    private var acompanharMouse: Timer?

    /// Escondido pelo atalho ou pelo menu da barra: a janela sai da tela e o hover para de abrir o painel.
    private var notchVisivel = true
    private var itemMostrar: NSMenuItem?
    private var itemLogin: NSMenuItem?
    private var itemSair: NSMenuItem?
    private var atalho: EventHotKeyRef?
    private var atalhoLigado: Atalho?

    /// ⌥⌘N mostra/esconde o notch de qualquer app. O ícone da barra de menu some quando
    /// o menu do app aberto é comprido, então o atalho é o caminho garantido.
    /// Hot key do Carbon não pede permissão de Acessibilidade.
    private func registrarAtalho() {
        var tipo = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, dados in
            guard let dados else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(dados).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.alternarNotch() }
            return noErr
        }, 1, &tipo, Unmanaged.passUnretained(self).toOpaque(), nil)
        ligarAtalho()
        // Atalho trocado nos Ajustes: registra o novo. Gravando um atalho: o global sai do ar.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in Atalho.ler(Config.atalhoNotch, .notchPadrao) }
            .receive(on: RunLoop.main)
            .sink { [weak self] novo in
                if novo != self?.atalhoLigado { self?.ligarAtalho() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .gravandoAtalho)
            .sink { [weak self] aviso in
                if aviso.object as? Bool == true { self?.desligarAtalho() } else { self?.ligarAtalho() }
            }
            .store(in: &cancellables)
    }

    private func ligarAtalho() {
        desligarAtalho()
        let combinacao = Atalho.ler(Config.atalhoNotch, .notchPadrao)
        atalhoLigado = combinacao
        let id = EventHotKeyID(signature: OSType(0x6D4E6F74), id: 1) // "mNot"
        RegisterEventHotKey(UInt32(combinacao.codigo), combinacao.carbon, id, GetApplicationEventTarget(), 0, &atalho)
    }

    private func desligarAtalho() {
        if let atalho { UnregisterEventHotKey(atalho) }
        atalho = nil
        atalhoLigado = nil
    }

    /// O menu mostra o atalho e o "abrir ao iniciar" atuais (podem ter mudado nos Ajustes).
    func menuWillOpen(_ menu: NSMenu) {
        let combinacao = Atalho.ler(Config.atalhoNotch, .notchPadrao)
        itemMostrar?.keyEquivalent = combinacao.letra
        itemMostrar?.keyEquivalentModifierMask = combinacao.modificadores
        itemLogin?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        // O idioma pode ter mudado nos Ajustes.
        itemMostrar?.title = tr("Mostrar notch", "Show notch")
        itemLogin?.title = tr("Abrir ao iniciar o Mac", "Open at login")
        itemSair?.title = tr("Sair do myNotch", "Quit myNotch")
    }

    private func atualizarHover() {
        guard let panel, notchVisivel else { return }
        // Histerese: recolhido, abre ao entrar na área pequena; expandido, só fecha ao sair da grande.
        let area = model.expanded
            ? panel.areaDoNotch(expandido: true, aba: model.aba).insetBy(dx: -8, dy: -8)
            : panel.areaDeAbrir()
        var dentro = area.contains(NSEvent.mouseLocation)
        // Ditando (inclusive no pedido de permissão do microfone), o painel fica aberto:
        // fechar destruiria o editor que está recebendo o texto.
        if model.expanded && ditado.ativo { dentro = true }
        // Menu de clique direito ou popup aberto a partir do notch (ex.: ferramentas de escrita
        // sobre o texto selecionado): levar o mouse até ele não fecha o painel.
        if model.expanded && !dentro, let janela = janelaSobOMouse(fora: panel.windowNumber) {
            if janela.pid == ProcessInfo.processInfo.processIdentifier {
                dentro = true
            } else if janela.numero != ultimaJanelaRegistrada {
                // Diagnóstico: qual app é dono da janela para onde o mouse foi quando o painel fechou.
                ultimaJanelaRegistrada = janela.numero
                registrarDebug("fechou: mouse sobre \(janela.dono) pid=\(janela.pid) camada=\(janela.camada)")
            }
        }
        panel.ignoresMouseEvents = !(model.expanded ? dentro : false)
        guard dentro != model.expanded else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            model.expanded = dentro
        }
        panel.ignoresMouseEvents = !dentro
    }

    private var ultimaJanelaRegistrada = 0

    /// A janela mais à frente debaixo do mouse, tirando o próprio painel (que é transparente).
    /// A lista do Window Server dá dono e posição sem pedir permissão de gravação de tela.
    private func janelaSobOMouse(fora painel: Int) -> (numero: Int, pid: Int32, dono: String, camada: Int)? {
        guard let principal = NSScreen.screens.first,
              let lista = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        // O Window Server mede a partir do canto de cima da tela principal; o AppKit, do canto de baixo.
        let mouse = NSEvent.mouseLocation
        let ponto = CGPoint(x: mouse.x, y: principal.frame.maxY - mouse.y)
        for janela in lista {
            guard let numero = janela[kCGWindowNumber as String] as? Int, numero != painel,
                  let limites = janela[kCGWindowBounds as String] as? NSDictionary,
                  let retangulo = CGRect(dictionaryRepresentation: limites), retangulo.contains(ponto),
                  (janela[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { continue }
            return (numero,
                    janela[kCGWindowOwnerPID as String] as? Int32 ?? 0,
                    janela[kCGWindowOwnerName as String] as? String ?? "?",
                    janela[kCGWindowLayer as String] as? Int ?? 0)
        }
        return nil
    }

    private func criarMenuDaBarra() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "myNotch")

        let menu = NSMenu()
        let mostrar = NSMenuItem(title: "Mostrar notch", action: #selector(alternarNotch), keyEquivalent: "n")
        mostrar.keyEquivalentModifierMask = [.command, .option]
        mostrar.target = self
        mostrar.state = .on
        menu.addItem(mostrar)
        itemMostrar = mostrar
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Abrir ao iniciar o Mac", action: #selector(alternarLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        itemLogin = login
        menu.addItem(.separator())
        let sair = NSMenuItem(title: "Sair do myNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(sair)
        itemSair = sair
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc fileprivate func alternarNotch() {
        notchVisivel.toggle()
        if notchVisivel {
            panel?.orderFrontRegardless()
        } else {
            model.expanded = false
            panel?.ignoresMouseEvents = true
            panel?.orderOut(nil)
        }
        itemMostrar?.state = notchVisivel ? .on : .off
    }

    @objc private func alternarLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("myNotch: não consegui alterar o item de login: \(error)")
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
