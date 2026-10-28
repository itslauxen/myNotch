@preconcurrency import AVFoundation
import CoreAudio
import Speech

/// Volume da voz (0 a 1) enquanto o ditado ouve. Separado do `Ditado` para só o orb redesenhar
/// a cada pedaço de áudio, e não a aba inteira.
@MainActor
final class NivelDeVoz: ObservableObject {
    @Published var valor: Float = 0
    /// Maior volume do ditado, para o log dizer se o microfone captou alguma coisa.
    var pico: Float = 0
    /// Última vez que o volume passou de fala (para parar sozinho depois de um silêncio).
    var ultimaVoz = Date()
}

/// Ditado da aba Notas: ouve o microfone e transcreve em português com o reconhecimento de fala
/// do macOS (no próprio Mac quando ele suporta). O texto chega aos pedaços enquanto a pessoa fala.
@MainActor
final class Ditado: ObservableObject {
    @Published private(set) var ouvindo = false
    /// Do clique até a última palavra chegar, incluindo o pedido de permissão.
    @Published private(set) var ativo = false
    @Published private(set) var erro: String?
    let nivel = NivelDeVoz()

    /// Idiomas oferecidos nos Ajustes.
    static var idiomas: [(codigo: String, nome: String)] {
        [("pt-BR", tr("Português", "Portuguese")), ("en-US", tr("Inglês", "English")), ("es-ES", tr("Espanhol", "Spanish"))]
    }
    /// Silêncio, em segundos, para o ditado parar sozinho (quando ligado nos Ajustes).
    static let silencioParaParar: TimeInterval = 3
    private var vigia: Timer?
    /// Captura pelo AVCaptureSession, que deixa escolher o microfone. O AVAudioEngine sempre nasce
    /// no microfone padrão do sistema e recusava trocar depois (erro -10868, formato não suportado).
    private var captura: AVCaptureSession?
    private var receptor: ReceptorDeAudio?
    private let filaAudio = DispatchQueue(label: "dev.lauxen.mynotch.ditado")
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarefa: SFSpeechRecognitionTask?

    /// `aoOuvir` recebe a transcrição inteira até agora (não só o pedaço novo).
    func comecar(aoOuvir: @escaping (String) -> Void, aoTerminar: @escaping () -> Void) async {
        erro = nil
        ativo = true
        registrarDebug("ditado: começou; fala=\(SFSpeechRecognizer.authorizationStatus().rawValue) mic=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
        guard await Self.permitido() else {
            falhar(tr("Libere o microfone e o reconhecimento de fala em Ajustes do Sistema › Privacidade", "Allow the microphone and speech recognition in System Settings › Privacy"))
            return
        }
        let reconhecedor = SFSpeechRecognizer(locale: Locale(identifier: Config.texto(Config.idiomaDitado, "pt-BR")))
        guard let reconhecedor, reconhecedor.isAvailable else {
            falhar(tr("Reconhecimento de fala indisponível agora", "Speech recognition is unavailable right now"))
            return
        }
        let pedido = SFSpeechAudioBufferRecognitionRequest()
        pedido.shouldReportPartialResults = true
        if reconhecedor.supportsOnDeviceRecognition { pedido.requiresOnDeviceRecognition = true }
        self.pedido = pedido

        // O microfone escolhido nos Ajustes (padrão: o do próprio Mac), não o padrão do sistema:
        // fones Bluetooth costumam virar o padrão e nem sempre captam bem.
        guard let mic = Self.microfoneEscolhido(),
              let entrada = try? AVCaptureDeviceInput(device: mic) else {
            falhar(tr("Nenhum microfone encontrado", "No microphone found"))
            return
        }
        registrarDebug("ditado: microfone \(mic.localizedName)")
        let captura = AVCaptureSession()
        let saida = AVCaptureAudioDataOutput()
        let medidor = nivel
        medidor.pico = 0
        medidor.ultimaVoz = Date()
        let receptor = ReceptorDeAudio(pedido: pedido) { valor in
            Task { @MainActor in
                medidor.valor = valor
                medidor.pico = max(medidor.pico, valor)
                if valor > 0.3 { medidor.ultimaVoz = Date() }
            }
        }
        captura.beginConfiguration()
        guard captura.canAddInput(entrada), captura.canAddOutput(saida) else {
            captura.commitConfiguration()
            falhar(tr("Não consegui abrir o microfone", "Couldn't open the microphone"))
            return
        }
        captura.addInput(entrada)
        captura.addOutput(saida)
        saida.setSampleBufferDelegate(receptor, queue: filaAudio)
        captura.commitConfiguration()
        self.captura = captura
        self.receptor = receptor
        // startRunning bloqueia até o microfone abrir: fora da main thread.
        filaAudio.async { captura.startRunning() }
        ouvindo = true
        if Config.bool(Config.pararNoSilencio, false) {
            vigia = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.ouvindo else { return }
                    if Date().timeIntervalSince(self.nivel.ultimaVoz) > Self.silencioParaParar { self.parar() }
                }
            }
        }
        registrarDebug("ditado: ouvindo (no próprio Mac: \(pedido.requiresOnDeviceRecognition))")
        tarefa = reconhecedor.recognitionTask(with: pedido) { [weak self] resultado, falha in
            let texto = resultado?.bestTranscription.formattedString
            let fim = falha != nil || resultado?.isFinal == true
            Task { @MainActor in
                guard let self else { return }
                if let falha { registrarDebug("ditado: reconhecedor parou: \(falha.localizedDescription)") }
                if let texto { aoOuvir(texto) }
                if fim, self.ouvindo || self.tarefa != nil {
                    self.encerrar()
                    aoTerminar()
                }
            }
        }
    }

    /// Para de ouvir; o reconhecedor ainda entrega a versão final do que já foi dito.
    func parar() {
        guard ouvindo else { ativo = tarefa != nil; return }
        vigia?.invalidate()
        vigia = nil
        if let captura { filaAudio.async { captura.stopRunning() } }
        captura = nil
        receptor = nil
        registrarDebug("ditado: parou; maior volume \(String(format: "%.2f", nivel.pico)) (0 = silêncio)")
        pedido?.endAudio()
        ouvindo = false
        nivel.valor = 0
    }

    private func encerrar() {
        if ouvindo { parar() }
        tarefa = nil
        pedido = nil
        ativo = false
    }

    private func falhar(_ mensagem: String) {
        erro = mensagem
        ativo = false
        registrarDebug("ditado: \(mensagem)")
    }

    /// Chave do microfone escolhido na aba Ajustes (o `uniqueID`; vazio = o do Mac).
    static let chaveMicrofone = "ditadoMicrofone"

    /// Todos os microfones ligados agora (do Mac, AirPods, iPhone por Continuidade, USB).
    static func microfones() -> [AVCaptureDevice] {
        let tipos: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) { tipos = [.microphone] } else { tipos = [.builtInMicrophone, .externalUnknown] }
        return AVCaptureDevice.DiscoverySession(deviceTypes: tipos, mediaType: .audio, position: .unspecified).devices
    }

    /// O microfone embutido do Mac ("Microfone do MacBook").
    static func microfoneDoMac() -> AVCaptureDevice? {
        microfones().first { $0.transportType == Int32(bitPattern: kAudioDeviceTransportTypeBuiltIn) }
    }

    /// O escolhido nos Ajustes; se ele não estiver ligado, o do Mac.
    static func microfoneEscolhido() -> AVCaptureDevice? {
        let id = UserDefaults.standard.string(forKey: chaveMicrofone) ?? ""
        return microfones().first { $0.uniqueID == id } ?? microfoneDoMac() ?? AVCaptureDevice.default(for: .audio)
    }

    private static func permitido() async -> Bool {
        let fala = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard fala else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}

/// Recebe o áudio do microfone (fora da main thread): manda para o reconhecedor e mede o volume.
final class ReceptorDeAudio: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let pedido: SFSpeechAudioBufferRecognitionRequest
    private let aoMedir: (Float) -> Void

    init(pedido: SFSpeechAudioBufferRecognitionRequest, aoMedir: @escaping (Float) -> Void) {
        self.pedido = pedido
        self.aoMedir = aoMedir
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput amostra: CMSampleBuffer, from conexao: AVCaptureConnection) {
        pedido.appendAudioSampleBuffer(amostra)
        // Volume em dB, de -50 (silêncio) a -10 (voz alta), virando 0 a 1 para o orb.
        if let canal = conexao.audioChannels.first {
            aoMedir(min(max((canal.averagePowerLevel + 50) / 40, 0), 1))
        }
    }
}
