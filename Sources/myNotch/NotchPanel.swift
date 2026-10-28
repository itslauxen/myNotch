import AppKit

/// Janela transparente de tamanho fixo, colada no topo da tela. O preto do notch
/// é desenhado dentro dela e muda de tamanho com a animação do SwiftUI — a janela
/// em si nunca redimensiona, então não sobra retângulo antigo na tela.
final class NotchPanel: NSPanel {
    /// Cabe o maior estado (a aba Nova) com folga.
    static let larguraJanela: CGFloat = 780
    static let alturaJanela: CGFloat = 460

    /// Largura do painel aberto. A aba Nova (lista + editor) é a única mais larga.
    static func larguraExpandida(para aba: Aba) -> CGFloat {
        aba == .nova ? 720 : 520
    }
    /// Altura do painel aberto. Player e bandeja são mais baixos; notas precisa da barra de formatação.
    static func alturaExpandida(para aba: Aba) -> CGFloat {
        switch aba {
        case .player: return 210
        case .prints: return 210
        case .notas: return 240
        case .nova: return 430
        case .ajustes: return 420
        }
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu + 1
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Recolhido, a janela transparente não pode roubar cliques da tela; expandido, aceita.
        ignoresMouseEvents = true
    }

    // Precisa virar "key" para o campo de notas receber digitação.
    override var canBecomeKey: Bool { true }

    /// ⌘V, ⌘C etc. normalmente chegam ao campo de texto pelo menu Editar, que este app
    /// não tem (vive só no notch). Sem ele, os atalhos de edição são entregues daqui.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let modificadores = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let tecla = event.charactersIgnoringModifiers?.lowercased()
        let acao: String
        switch (modificadores, tecla) {
        case ([.command], "v"): acao = "paste:"
        case ([.command], "c"): acao = "copy:"
        case ([.command], "x"): acao = "cut:"
        case ([.command], "a"): acao = "selectAll:"
        case ([.command], "z"): acao = "undo:"
        case ([.command, .shift], "z"): acao = "redo:"
        default: return false
        }
        return NSApp.sendAction(Selector(acao), to: nil, from: self)
    }

    /// Tela embutida do Mac (a que tem o notch). `NSScreen.main` é a tela com foco e
    /// troca de monitor sem aviso, por isso não serve aqui.
    static var telaDoMac: NSScreen? {
        NSScreen.screens.first { tela in
            guard let numero = tela.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(numero.uint32Value) != 0
        } ?? NSScreen.screens.first
    }

    /// Altura da faixa do topo (notch, ou 28 pt em Mac sem notch): onde ficam os ícones das abas.
    static var alturaBanda: CGFloat { max(alturaNotch, 28) }

    /// Altura do notch na tela principal (0 em Mac sem notch).
    static var alturaNotch: CGFloat {
        NotchPanel.telaDoMac?.safeAreaInsets.top ?? 0
    }

    /// Largura física do notch, medida pelas áreas laterais ao notch.
    static var larguraNotch: CGFloat {
        guard let tela = NotchPanel.telaDoMac,
              let esquerda = tela.auxiliaryTopLeftArea,
              let direita = tela.auxiliaryTopRightArea else { return 200 }
        return tela.frame.width - esquerda.width - direita.width
    }

    /// Recolhido, o preto tem só a largura do notch físico: o macOS não afasta o menu
    /// dos apps de nada além disso, e qualquer asa cobriria itens como "Window".
    static var larguraRecolhida: CGFloat { larguraNotch }
    static var alturaRecolhida: CGFloat { max(alturaNotch, 28) }

    /// Coloca a janela fixa no topo, centralizada.
    func posicionar() {
        guard let tela = NotchPanel.telaDoMac else { return }
        setFrame(NSRect(
            x: tela.frame.midX - Self.larguraJanela / 2,
            y: tela.frame.maxY - Self.alturaJanela,
            width: Self.larguraJanela,
            height: Self.alturaJanela
        ), display: true)
    }

    /// Onde o mouse precisa chegar para abrir: a metade de cima do notch, com folga para os lados
    /// e para cima. A metade de baixo fica de fora, para não abrir ao arrastar uma janela.
    /// A folga de cima importa: com o mouse colado no topo, `mouseLocation.y` é igual a `maxY`,
    /// e um retângulo que termina em `maxY` não contém esse ponto.
    func areaDeAbrir() -> NSRect {
        guard let tela = NotchPanel.telaDoMac else { return .zero }
        let folga: CGFloat = 8
        let largura = Self.larguraNotch + 2 * folga
        let altura = Self.alturaRecolhida / 2 + folga
        return NSRect(x: tela.frame.midX - largura / 2, y: tela.frame.maxY + folga - altura, width: largura, height: altura)
    }

    /// Área, em coordenadas de tela, ocupada pelo preto em cada estado.
    func areaDoNotch(expandido: Bool, aba: Aba) -> NSRect {
        guard let tela = NotchPanel.telaDoMac else { return .zero }
        let largura = expandido ? Self.larguraExpandida(para: aba) : Self.larguraRecolhida
        let altura = expandido ? Self.alturaExpandida(para: aba) : Self.alturaRecolhida
        return NSRect(x: tela.frame.midX - largura / 2, y: tela.frame.maxY - altura, width: largura, height: altura)
    }
}
