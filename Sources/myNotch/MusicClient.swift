import Foundation

/// Campos de /api/v1/song-info do YouTube Music (plugin api-server do pear-desktop).
struct SongInfo: Decodable {
    let title: String?
    let artist: String?
    let imageSrc: String?
    let isPaused: Bool?
    let elapsedSeconds: Double?
    let songDuration: Double?
}

/// Resposta de /api/v1/like-state.
struct CurtidaEstado: Decodable {
    let state: String?
}

/// Lê o estado e manda comandos para o YouTube Music pela API local (127.0.0.1:26538).
/// Com o app pausado ou fechado, usa o vídeo do YouTube que estiver tocando no Chrome.
@MainActor
final class MusicClient: ObservableObject {
    @Published private(set) var song: SongInfo?
    @Published private(set) var online = false
    /// "LIKE", "DISLIKE" ou "INDIFFERENT" para a música atual.
    @Published private(set) var curtida: String?

    private let base = URL(string: "http://127.0.0.1:26538/api/v1/")!
    private var timer: Timer?
    private let chrome = ChromeYouTube()
    /// A música mostrada veio do Chrome: os comandos vão para a aba, não para a API.
    private var noChrome = false
    /// O timer é de 1 s e o Chrome pode demorar a responder; leituras não se acumulam.
    private var atualizando = false

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard !atualizando else { return }
        atualizando = true
        defer { atualizando = false }

        var app: (SongInfo, String?)?
        do {
            let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("song-info"))
            let musica = try JSONDecoder().decode(SongInfo.self, from: data)
            let (estado, _) = try await URLSession.shared.data(from: base.appendingPathComponent("like-state"))
            app = (musica, (try? JSONDecoder().decode(CurtidaEstado.self, from: estado))?.state)
        } catch {
            app = nil
        }

        // O app tem prioridade; o Chrome entra quando o app está pausado ou fechado e o vídeo está tocando.
        var escolhido = app
        noChrome = false
        if app?.0.isPaused != false, let aba = await chrome.ler(), aba.0.isPaused == false || app == nil {
            escolhido = aba
            noChrome = true
        }
        song = escolhido?.0
        curtida = escolhido?.1
        online = escolhido != nil
    }

    /// Alterna a curtida da música atual no YouTube Music.
    func curtir() {
        send("like")
    }

    /// Move a reprodução para `segundos` dentro da música atual.
    func buscar(segundos: Double) {
        if noChrome {
            chrome.buscar(segundos: segundos)
            Task { await refresh() }
            return
        }
        var request = URLRequest(url: base.appendingPathComponent("seek-to"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["seconds": Int(segundos)])
        Task {
            _ = try? await URLSession.shared.data(for: request)
            await refresh()
        }
    }

    /// Comandos do plugin: "toggle-play", "next", "previous", "volume" etc.
    func send(_ path: String) {
        if noChrome {
            chrome.comando(path)
            Task { await refresh() }
            return
        }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        Task {
            _ = try? await URLSession.shared.data(for: request)
            await refresh()
        }
    }
}
