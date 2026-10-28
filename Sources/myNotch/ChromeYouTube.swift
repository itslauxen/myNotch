import AppKit
import Excecoes
import ScriptingBridge

/// Lê e controla o vídeo do YouTube aberto no Chrome por Apple Events (`execute javascript`).
/// Precisa de "Ver > Desenvolvedor > Permitir JavaScript de Eventos Apple" ligado no Chrome.
/// O MediaRemote (o "Tocando agora" do sistema) já vê o Chrome, mas desde o macOS 15.4
/// só responde a apps da Apple, por isso o caminho é pelo próprio Chrome.
/// `@unchecked Sendable`: o estado (`aba`) só é lido e escrito dentro de `fila`.
final class ChromeYouTube: @unchecked Sendable {
    /// Apple Events são síncronos: tudo roda fora da main thread, um de cada vez.
    private let fila = DispatchQueue(label: "dev.lauxen.mynotch.chrome")
    /// Aba da última leitura, para os comandos irem para o mesmo vídeo.
    private var aba: SBObject?

    /// Player principal do YouTube (`#movie_player`, que continua no miniplayer) ou do YouTube Music.
    /// Os campos batem com `SongInfo`, e `state` com `CurtidaEstado`.
    private static let lerJS = """
    (() => {
      const v = document.querySelector('#movie_player video') || (location.host.startsWith('music.') ? document.querySelector('video') : null);
      if (!v || !v.duration) return '';
      const m = navigator.mediaSession.metadata;
      const capa = m && m.artwork && m.artwork.length ? m.artwork[m.artwork.length - 1].src : '';
      const like = document.querySelector('like-button-view-model button, #button-shape-like button');
      return JSON.stringify({
        title: m && m.title ? m.title : document.title.replace(/ - YouTube( Music)?$/, ''),
        artist: m ? m.artist : '',
        imageSrc: capa,
        isPaused: v.paused,
        elapsedSeconds: v.currentTime,
        songDuration: v.duration,
        state: like && like.getAttribute('aria-pressed') === 'true' ? 'LIKE' : 'INDIFFERENT'
      });
    })()
    """

    /// Vídeo do YouTube no Chrome, preferindo o que está tocando. `nil` sem Chrome ou sem vídeo.
    func ler() async -> (SongInfo, String?)? {
        await withCheckedContinuation { continuacao in
            fila.async { continuacao.resume(returning: self.lerAgora()) }
        }
    }

    /// Mesmos nomes de comando da API do YouTube Music: "toggle-play", "next", "previous", "like".
    func comando(_ path: String) {
        let js: String
        switch path {
        case "toggle-play": js = "v.paused ? v.play() : v.pause()"
        case "next": js = "(document.querySelector('.ytp-next-button') || document.querySelector('.next-button'))?.click()"
        case "previous": js = "const b = document.querySelector('.ytp-prev-button:not([style*=\"none\"]), .previous-button'); b ? b.click() : v.currentTime = 0"
        case "like": js = "document.querySelector('like-button-view-model button, #button-shape-like button')?.click()"
        default: return
        }
        executarNoVideo(js)
    }

    func buscar(segundos: Double) {
        executarNoVideo("v.currentTime = \(segundos)")
    }

    private func executarNoVideo(_ js: String) {
        fila.async {
            guard let aba = self.aba else { return }
            _ = Self.executar("""
            (() => { const v = document.querySelector('#movie_player video') || document.querySelector('video'); if (!v) return; \(js) })()
            """, em: aba)
        }
    }

    private func lerAgora() -> (SongInfo, String?)? {
        var achados: [(aba: SBObject, song: SongInfo, curtida: String?)] = []
        // Pode haver vários Chromes (os de automação também); cada processo é consultado pelo PID.
        // Pelo bundle id o ScriptingBridge escolheria um qualquer, ou abriria o Chrome se estivesse fechado.
        // Um Chrome de automação sem AppleScript, ou uma janela fechando no meio da leitura, lança
        // exceção do Objective-C; capturada, a leitura só falha desta vez em vez de fechar o app.
        if let excecao = capturarExcecao({
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome") {
                guard let chrome = SBApplication(processIdentifier: app.processIdentifier),
                      let janelas = chrome.value(forKey: "windows") as? SBElementArray else { continue }
                for case let janela as SBObject in janelas {
                    guard let abas = janela.value(forKey: "tabs") as? SBElementArray,
                          let urls = abas.array(byApplying: NSSelectorFromString("URL")) as? [String] else { continue }
                    for (i, url) in urls.enumerated() where url.contains("youtube.com") {
                        guard let aba = abas.object(at: i) as? SBObject,
                              let json = Self.executar(Self.lerJS, em: aba)?.data(using: .utf8),
                              let song = try? JSONDecoder().decode(SongInfo.self, from: json) else { continue }
                        achados.append((aba, song, (try? JSONDecoder().decode(CurtidaEstado.self, from: json))?.state))
                    }
                }
            }
        }) {
            registrarDebug("chrome: leitura falhou: \(excecao.name.rawValue) \(excecao.reason ?? "")")
        }
        let escolhido = achados.first { $0.song.isPaused == false } ?? achados.first
        aba = escolhido?.aba
        return escolhido.map { ($0.song, $0.curtida) }
    }

    private static func executar(_ js: String, em aba: SBObject) -> String? {
        var resultado: String?
        if let excecao = capturarExcecao({
            resultado = aba.perform(NSSelectorFromString("executeJavascript:"), with: js)?.takeUnretainedValue() as? String
        }) {
            registrarDebug("chrome: javascript falhou: \(excecao.name.rawValue) \(excecao.reason ?? "")")
        }
        return resultado
    }
}
