import AVFoundation
import CoreAudio
import ServiceManagement
import SwiftUI

/// Aba Ajustes (a engrenagem na asa direita). Uma coluna rolável, uma seção por assunto.
struct AjustesView: View {
    @ObservedObject var nova: NovaStore

    @AppStorage(Ditado.chaveMicrofone) private var microfone = ""
    @AppStorage(Config.idiomaDitado) private var idioma = "pt-BR"
    @AppStorage(Config.pararNoSilencio) private var pararNoSilencio = false
    @AppStorage(Config.limiteBandeja) private var limiteBandeja = 6
    @AppStorage(Config.bandejaTextos) private var bandejaTextos = true
    @AppStorage(Config.bandejaImagens) private var bandejaImagens = true
    @AppStorage(Config.fonteNota) private var fonte = Config.fontePadrao
    @AppStorage(Config.atalhoNotch) private var atalhoNotch = Atalho.notchPadrao
    @AppStorage(Config.atalhoDitado) private var atalhoDitado = Atalho.ditadoPadrao

    @State private var microfones: [AVCaptureDevice] = []
    @State private var abrirAoIniciar = SMAppService.mainApp.status == .enabled
    @AppStorage(Config.novaNotes) private var novaLigada = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                secao("Geral") {
                    linha("Abrir ao iniciar o Mac") {
                        Toggle("", isOn: Binding(get: { abrirAoIniciar }, set: alternarLogin))
                            .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                    linha("Integração com o Nova Notes") {
                        Toggle("", isOn: $novaLigada).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                }

                if novaLigada {
                    secao("Conta do Nova Notes") {
                        if nova.logado {
                            linha(nova.email.map { "Conectado como \($0)" } ?? "Conectado") {
                                botao("Sair") { nova.sair() }
                            }
                        } else {
                            linha("Não conectado. Entre pela aba Nova.") { EmptyView() }
                        }
                    }
                }

                secao("Bandeja") {
                    linha("Quantos itens guardar") {
                        contador($limiteBandeja, de: 3, ate: 20)
                    }
                    linha("Guardar textos copiados") {
                        Toggle("", isOn: $bandejaTextos).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                    linha("Guardar imagens e prints") {
                        Toggle("", isOn: $bandejaImagens).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                }

                secao("Ditado") {
                    VStack(spacing: 2) {
                        ForEach(microfones, id: \.uniqueID) { linhaMicrofone($0) }
                    }
                    linha("Idioma") {
                        HStack(spacing: 2) {
                            ForEach(Ditado.idiomas, id: \.codigo) { opcao in
                                pilula(opcao.nome, ativa: idioma == opcao.codigo) { idioma = opcao.codigo }
                            }
                        }
                    }
                    linha("Parar sozinho após 3 s de silêncio") {
                        Toggle("", isOn: $pararNoSilencio).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                }

                secao("Nota rápida") {
                    linha("Tamanho da fonte") {
                        contador(Binding(get: { Int(fonte) }, set: { fonte = Double($0) }), de: 10, ate: 22)
                    }
                }

                secao("Atalhos") {
                    linha("Mostrar e esconder o notch") { GravadorDeAtalho(atalho: $atalhoNotch) }
                    linha("Ditar na nota rápida") { GravadorDeAtalho(atalho: $atalhoDitado) }
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Lista de novo a cada abertura: AirPods e iPhone entram e saem; o login pode ter mudado pelo menu.
        .onAppear {
            microfones = Ditado.microfones()
            abrirAoIniciar = SMAppService.mainApp.status == .enabled
        }
    }

    /* ---------------- peças ---------------- */

    private func secao<C: View>(_ titulo: String, @ViewBuilder _ conteudo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            conteudo()
        }
    }

    private func linha<C: View>(_ texto: String, @ViewBuilder _ controle: () -> C) -> some View {
        HStack(spacing: 10) {
            Text(texto).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 0)
            controle()
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }

    private func botao(_ titulo: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(titulo)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func pilula(_ titulo: String, ativa: Bool, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(titulo)
                .font(.system(size: 12, weight: ativa ? .semibold : .regular))
                .foregroundStyle(ativa ? Color.white : Color.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(ativa ? 0.16 : 0.04)))
        }
        .buttonStyle(.plain)
    }

    /// − número + (sem o Stepper do sistema, que destoa no fundo preto).
    private func contador(_ valor: Binding<Int>, de minimo: Int, ate maximo: Int) -> some View {
        HStack(spacing: 4) {
            botaoContador("minus", ativo: valor.wrappedValue > minimo) { valor.wrappedValue -= 1 }
            Text("\(valor.wrappedValue)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 24)
            botaoContador("plus", ativo: valor.wrappedValue < maximo) { valor.wrappedValue += 1 }
        }
    }

    private func botaoContador(_ icone: String, ativo: Bool, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(!ativo)
        .opacity(ativo ? 1 : 0.35)
    }

    private func linhaMicrofone(_ mic: AVCaptureDevice) -> some View {
        let ativo = mic.uniqueID == Ditado.microfoneEscolhido()?.uniqueID
        return Button {
            microfone = mic.uniqueID
        } label: {
            HStack(spacing: 10) {
                Image(systemName: Self.icone(mic))
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(mic.localizedName)
                    .font(.system(size: 13, weight: ativo ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if ativo {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(ativo ? Color.white : Color.white.opacity(0.75))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(ativo ? 0.12 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func icone(_ mic: AVCaptureDevice) -> String {
        if mic.transportType == Int32(bitPattern: kAudioDeviceTransportTypeBuiltIn) { return "laptopcomputer" }
        if mic.localizedName.localizedCaseInsensitiveContains("airpods") { return "airpods" }
        if mic.localizedName.localizedCaseInsensitiveContains("iphone") { return "iphone" }
        return "mic"
    }

    private func alternarLogin(_ ligar: Bool) {
        do {
            if ligar { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            registrarDebug("ajustes: não consegui alterar o item de login: \(error.localizedDescription)")
        }
        abrirAoIniciar = SMAppService.mainApp.status == .enabled
    }
}

/// Botão que mostra o atalho e, clicado, grava o próximo que for apertado (Esc cancela).
/// Precisa de ⌘, ⌥ ou ⌃ junto, para não roubar uma letra da digitação.
struct GravadorDeAtalho: View {
    @Binding var atalho: Atalho
    @State private var gravando = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            gravando ? parar() : comecar()
        } label: {
            Text(gravando ? "Aperte o atalho…" : atalho.texto)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(gravando ? Color.accentColor : Color.white)
                .padding(.horizontal, 10)
                .frame(minWidth: 70)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(gravando ? 0.16 : 0.1)))
        }
        .buttonStyle(.plain)
        .onDisappear(perform: parar)
    }

    private func comecar() {
        gravando = true
        // O painel não ativa o app; sem virar a janela principal, as teclas iriam para o app da frente.
        NSApp.windows.first { $0 is NotchPanel }?.makeKey()
        NotificationCenter.default.post(name: .gravandoAtalho, object: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { evento in
            if evento.keyCode == 53 { parar(); return nil } // Esc
            let mods = evento.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.intersection([.command, .option, .control]).isEmpty,
                  let letra = evento.charactersIgnoringModifiers?.lowercased(), letra.count == 1,
                  letra.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).contains($0) })
            else { return nil }
            atalho = Atalho(codigo: evento.keyCode, letra: letra, modificadores: mods)
            parar()
            return nil
        }
    }

    private func parar() {
        guard gravando else { return }
        gravando = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.post(name: .gravandoAtalho, object: false)
    }
}
