import AppKit
import SwiftUI

/// Preto de ponta a ponta, com só as pontas de baixo arredondadas, para parecer
/// que o próprio notch cresceu.
struct NotchView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var music: MusicClient
    @ObservedObject var notes: NotesStore
    @ObservedObject var tray: TrayStore
    @ObservedObject var nova: NovaStore
    let ditado: Ditado

    private var tamanho: CGSize {
        model.expanded
            ? CGSize(width: NotchPanel.larguraExpandida(para: model.aba), height: NotchPanel.alturaExpandida(para: model.aba))
            : CGSize(width: NotchPanel.larguraRecolhida, height: NotchPanel.alturaRecolhida)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            if model.expanded {
                // Faixa dos ícones fica sempre no topo; o conteúdo abaixo dela não a empurra.
                VStack(spacing: 0) {
                    AbasView(aba: $model.aba)
                    ExpandedView(model: model, music: music, notes: notes, tray: tray, nova: nova, ditado: ditado)
                }
                .transition(.opacity)
            }
        }
        .frame(width: tamanho.width, height: tamanho.height)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 18,
            bottomTrailingRadius: 18, topTrailingRadius: 0
        ))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Anima também ao trocar de aba, porque notas e Nova têm outro tamanho.
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tamanho)
        .preferredColorScheme(.dark)
    }
}

enum Aba: CaseIterable {
    case player
    case prints
    case notas
    case nova
    case ajustes

    /// Abas da asa esquerda; Ajustes fica sozinha na asa direita (cinco ícones não cabem num lado).
    /// A Nova só aparece com a integração ligada nos Ajustes.
    static func esquerda(nova: Bool) -> [Aba] { nova ? [.player, .prints, .notas, .nova] : [.player, .prints, .notas] }

    var icone: String {
        switch self {
        case .player: return "music.note"
        case .prints: return "tray.fill"
        case .notas: return "pencil"
        case .nova: return "doc.text"
        case .ajustes: return "gearshape.fill"
        }
    }
}

/// Ícones das abas, fixos na asa esquerda do notch: centralizados entre a borda
/// do container e a borda esquerda do notch. Passar o mouse troca a aba.
/// A aba Nova é mais larga; os ícones ficam colados ao notch na mesma posição de sempre,
/// senão andariam para baixo do mouse ao trocar de aba.
struct AbasView: View {
    @Binding var aba: Aba
    @AppStorage(Config.novaNotes) private var novaLigada = true

    private var asa: CGFloat { (NotchPanel.larguraExpandida(para: .player) - NotchPanel.larguraNotch) / 2 }
    private var asaAtual: CGFloat { (NotchPanel.larguraExpandida(para: aba) - NotchPanel.larguraNotch) / 2 }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                ForEach(Aba.esquerda(nova: novaLigada), id: \.self) { icone($0) }
            }
            .frame(width: asa, height: NotchPanel.alturaBanda)
            .frame(width: asaAtual, alignment: .trailing)
            Color.clear.frame(width: NotchPanel.larguraNotch)
            // Espelho da asa esquerda: a engrenagem fica no mesmo lugar em qualquer tamanho de aba.
            icone(.ajustes)
                .frame(width: asa, height: NotchPanel.alturaBanda)
                .frame(width: asaAtual, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(height: NotchPanel.alturaBanda)
    }

    private func icone(_ item: Aba) -> some View {
        Image(systemName: item.icone)
            // doc.text vinha sempre branco: força o desenho de uma cor só, que respeita o cinza
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(aba == item ? Color.white : Color.secondary)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
            .onHover { dentro in
                if dentro {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { aba = item }
                }
            }
    }
}

struct ExpandedView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var music: MusicClient
    @ObservedObject var notes: NotesStore
    @ObservedObject var tray: TrayStore
    @ObservedObject var nova: NovaStore
    let ditado: Ditado

    var body: some View {
        VStack(spacing: 12) {
            Group {
                switch model.aba {
                case .player: PlayerView(music: music)
                case .prints: TrayView(tray: tray)
                case .notas: NotesView(notes: notes, ditado: ditado)
                case .nova: NovaView(nova: nova)
                case .ajustes: AjustesView(nova: nova)
                }
            }
            // Cada aba entra deslizando e com fade; a troca é animada pelo AbasView.
            .id(model.aba)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 18)
        // Altura travada: o conteúdo não empurra a faixa de ícones para cima.
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: NotchPanel.alturaExpandida(para: model.aba) - NotchPanel.alturaBanda, alignment: .top)
        .clipped()
    }
}

struct PlayerView: View {
    @ObservedObject var music: MusicClient

    var body: some View {
        if !music.online {
            Text("Abra o YouTube Music para controlar daqui")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 18) {
                Button {
                    // Abre o YouTube Music na frente, como clicar na capa num player normal.
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/YouTube Music.app"))
                } label: {
                    ArtView(url: music.song?.imageSrc, tamanho: 150)
                }
                .buttonStyle(.plain)
                .help("Abrir YouTube Music")
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(music.song?.title ?? "Nada tocando")
                            .font(.system(size: 18, weight: .semibold))
                            .lineLimit(2)
                        Text(music.song?.artist ?? "")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    BarraDeProgresso(progresso: progresso) { fracao in
                        guard let total = music.song?.songDuration else { return }
                        music.buscar(segundos: fracao * total)
                    }
                    HStack(spacing: 22) {
                        botao("backward.fill") { music.send("previous") }
                        botao(music.song?.isPaused == false ? "pause.fill" : "play.fill", tamanho: 22) {
                            music.send("toggle-play")
                        }
                        botao("forward.fill") { music.send("next") }
                        Spacer(minLength: 0)
                        Button { music.curtir() } label: {
                            Image(systemName: music.curtida == "LIKE" ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(music.curtida == "LIKE" ? Color.red : Color.white)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Curtir música")
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var progresso: Double {
        guard let atual = music.song?.elapsedSeconds, let total = music.song?.songDuration, total > 0 else { return 0 }
        return min(max(atual / total, 0), 1)
    }

    private func botao(_ simbolo: String, tamanho: CGFloat = 14, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: simbolo)
                .font(.system(size: tamanho, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Trilha da música: clicar ou arrastar em qualquer ponto move a reprodução.
struct BarraDeProgresso: View {
    let progresso: Double
    let aoBuscar: (Double) -> Void

    @State private var arrastando: Double?

    var body: some View {
        GeometryReader { geo in
            let fracao = arrastando ?? progresso
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 6)
                Capsule()
                    .fill(Color.white)
                    .frame(width: geo.size.width * fracao, height: 6)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { valor in
                        arrastando = min(max(valor.location.x / geo.size.width, 0), 1)
                    }
                    .onEnded { valor in
                        let destino = min(max(valor.location.x / geo.size.width, 0), 1)
                        arrastando = nil
                        aoBuscar(destino)
                    }
            )
        }
        .frame(height: 14)
    }
}

struct ArtView: View {
    let url: String?
    let tamanho: CGFloat

    var body: some View {
        Group {
            if let url, let destino = URL(string: url) {
                AsyncImage(url: destino) { imagem in
                    imagem.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.08)
                }
            } else {
                Color.white.opacity(0.08)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
        }
        .frame(width: tamanho, height: tamanho)
        .clipShape(RoundedRectangle(cornerRadius: tamanho * 0.18))
    }
}

struct TrayView: View {
    @ObservedObject var tray: TrayStore
    @State private var sobre = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if tray.files.isEmpty {
                    Text("O que você copiar aparece aqui")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 320)
                        .frame(maxHeight: .infinity)
                }
                ForEach(tray.files, id: \.self) { url in
                    MiniaturaView(url: url, tray: tray)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        // Altura exata do espaço da aba (200 - faixa de ícones - margens): não estoura para baixo.
        .frame(height: 144)
        // Os itens somem aos poucos nas laterais, como se rolassem para baixo delas.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(sombraLateral)
        // Borda por cima da sombra, para o pontilhado continuar visível nas laterais.
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(sobre ? Color.white : Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5]))
                .allowsHitTesting(false)
        )
        .onDrop(of: [.fileURL, .image], isTargeted: $sobre) { providers in
            for provider in providers { receber(provider) }
            return true
        }
    }

    /// Sombra interna nas laterais, reforçando que o conteúdo continua além da borda.
    private var sombraLateral: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [Color.black.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 22)
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, Color.black.opacity(0.85)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 22)
        }
        .allowsHitTesting(false)
    }

    /// Arquivos arrastados entram na bandeja como cópia.
    private func receber(_ provider: NSItemProvider) {
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in tray.importar(url) }
            }
        } else if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { imagem, _ in
                guard let imagem = imagem as? NSImage else { return }
                Task { @MainActor in tray.importar(imagem: imagem) }
            }
        }
    }
}

struct MiniaturaView: View {
    let url: URL
    @ObservedObject var tray: TrayStore
    @State private var sobre = false
    @State private var alvo = false
    @State private var copiado = false
    /// Conta os cliques em copiar; cada mudança solta uma rajada de faíscas.
    @State private var disparos = 0

    private var ehTexto: Bool { url.pathExtension == "txt" }

    var body: some View {
        Group {
            if ehTexto {
                Text((try? String(contentsOf: url, encoding: .utf8)) ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let imagem = NSImage(contentsOf: url) {
                Image(nsImage: imagem).resizable().scaledToFill()
            } else {
                Image(systemName: "doc").foregroundStyle(.secondary)
            }
        }
        .frame(width: 130, height: 110)
        .background(Color.white.opacity(0.08))
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // Área inteira do card responde ao mouse, não só os glifos do texto.
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 1.5)
                .opacity(sobre || alvo ? 1 : 0)
        )
        .animation(.easeInOut(duration: 0.2), value: sobre || alvo)
        .overlay(alignment: .bottomTrailing) {
            if ehTexto && sobre {
                Button { copiarComFeedback() } label: {
                    // Ao copiar, o ícone vira um check na cor de acento do sistema.
                    Image(systemName: copiado ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(copiado ? Color.accentColor : Color.white)
                        // Ícone novo entra crescendo no lugar do antigo.
                        .id(copiado)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                        .padding(7)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                        .overlay(FaiscasView(disparo: disparos))
                }
                .buttonStyle(.plain)
                .help("Copiar texto")
                .padding(6)
            }
        }
        .onHover { sobre = $0 }
        // O item arrastado fica esmaecido enquanto os outros abrem espaço para ele.
        .opacity(tray.arrastando == url.lastPathComponent ? 0.35 : 1)
        .onChange(of: alvo) { novo in
            if novo, let origem = tray.arrastando {
                tray.preverMover(origem, para: url.lastPathComponent)
            }
        }
        // Arrastar para fora: texto vai como texto (cai direto num campo); print vai como arquivo.
        .onDrag {
            tray.arrastando = url.lastPathComponent
            return arrastavel
        }
        // Soltar outro item em cima reordena; sem item arrastado da bandeja, a queda segue para o container.
        .onDrop(of: [.fileURL, .text, .image], isTargeted: $alvo) { _ in
            guard let origem = tray.arrastando else { return false }
            tray.mover(origem, para: url.lastPathComponent)
            tray.arrastando = nil
            return true
        }
        .contextMenu {
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Remover da bandeja") { tray.remover(url) }
        }
    }

    /// Copia e mostra o check por um instante, depois volta ao ícone de copiar.
    private func copiarComFeedback() {
        tray.copiar(url)
        disparos += 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { copiado = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { copiado = false }
        }
    }

    private var arrastavel: NSItemProvider {
        if ehTexto, let texto = try? String(contentsOf: url, encoding: .utf8) {
            return NSItemProvider(object: texto as NSString)
        }
        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
    }
}

/// Faíscas que saem do centro e somem: o "plim" do botão de copiar.
/// Em repouso ficam invisíveis; cada mudança de `disparo` reinicia a rajada.
struct FaiscasView: View {
    let disparo: Int
    @State private var progresso: CGFloat = 1

    private let quantidade = 8

    var body: some View {
        ZStack {
            ForEach(0..<quantidade, id: \.self) { i in
                let angulo = Double(i) / Double(quantidade) * 2 * .pi
                let raio = 10 + 12 * progresso
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 5)
                    // Cada risquinho aponta para fora, na direção em que voa.
                    .rotationEffect(.radians(angulo + .pi / 2))
                    .scaleEffect(1 - progresso * 0.5)
                    .offset(x: cos(angulo) * raio, y: sin(angulo) * raio)
                    .opacity(1 - progresso)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: disparo) { _ in
            // Volta ao centro sem animar e só então anima a explosão.
            var semAnimacao = Transaction()
            semAnimacao.disablesAnimations = true
            withTransaction(semAnimacao) { progresso = 0 }
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.5)) { progresso = 1 }
            }
        }
    }
}
