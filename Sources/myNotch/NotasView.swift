import AppKit
import SwiftUI

/// Liga a barra de formatação ao NSTextView da aba Notas. As ações valem para a
/// seleção; sem seleção, valem para a digitação seguinte.
@MainActor
final class EditorNotas {
    weak var textView: NSTextView?
    var aoMudar: (() -> Void)?
    /// Tamanho da fonte dos Ajustes ÷ 13 (o título e a digitação acompanham).
    var escala: CGFloat = 1

    func negrito() { alternarTraco(.bold) }
    func italico() { alternarTraco(.italic) }
    func sublinhado() { alternarAtributo(.underlineStyle, valor: NSUnderlineStyle.single.rawValue) }
    func riscado() { alternarAtributo(.strikethroughStyle, valor: NSUnderlineStyle.single.rawValue) }

    /* Ditado: o texto falado entra no cursor e vai sendo trocado enquanto o reconhecedor corrige. */
    private var inicioDitado: Int?
    private var tamanhoDitado = 0

    func comecarDitado() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
        let selecao = tv.selectedRange()
        inicioDitado = NSMaxRange(selecao)
        tamanhoDitado = 0
    }

    func atualizarDitado(_ texto: String) {
        guard let tv = textView, let armazenamento = tv.textStorage, let inicio = inicioDitado else { return }
        let alvo = NSRange(location: inicio, length: tamanhoDitado)
        guard NSMaxRange(alvo) <= armazenamento.length else { return }
        // Separa do que vem antes com um espaço, a não ser no começo da linha.
        let antes = inicio > 0 ? (armazenamento.string as NSString).substring(with: NSRange(location: inicio - 1, length: 1)) : "\n"
        let novo = (antes == " " || antes == "\n" || texto.isEmpty ? "" : " ") + texto
        armazenamento.replaceCharacters(in: alvo, with: NSAttributedString(string: novo, attributes: tv.typingAttributes))
        tamanhoDitado = (novo as NSString).length
        tv.setSelectedRange(NSRange(location: inicio + tamanhoDitado, length: 0))
    }

    func terminarDitado() {
        inicioDitado = nil
        aoMudar?()
    }

    func titulo() {
        guard let tv = textView, let armazenamento = tv.textStorage else { return }
        let fonte = NSFont.systemFont(ofSize: 20 * escala, weight: .bold)
        let paragrafo = (tv.string as NSString).paragraphRange(for: tv.selectedRange())
        if paragrafo.length == 0 {
            tv.typingAttributes[.font] = fonte
            return
        }
        armazenamento.addAttribute(.font, value: fonte, range: paragrafo)
        aoMudar?()
    }

    func checkbox() { inserirNoInicio("☐ ") }
    func lista() { inserirNoInicio("• ") }

    private func inserirNoInicio(_ prefixo: String) {
        guard let tv = textView, let armazenamento = tv.textStorage else { return }
        let inicio = (tv.string as NSString).paragraphRange(for: tv.selectedRange()).location
        armazenamento.replaceCharacters(in: NSRange(location: inicio, length: 0), with: prefixo)
        aoMudar?()
    }

    private func alternarTraco(_ traco: NSFontDescriptor.SymbolicTraits) {
        guard let tv = textView, let armazenamento = tv.textStorage else { return }
        let intervalo = tv.selectedRange()
        if intervalo.length == 0 {
            let atual = (tv.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 13 * escala)
            tv.typingAttributes[.font] = trocarTraco(atual, traco)
            return
        }
        var pedacos: [(NSRange, NSFont)] = []
        armazenamento.enumerateAttribute(.font, in: intervalo) { valor, sub, _ in
            pedacos.append((sub, (valor as? NSFont) ?? NSFont.systemFont(ofSize: 13)))
        }
        armazenamento.beginEditing()
        for (sub, fonte) in pedacos {
            armazenamento.addAttribute(.font, value: trocarTraco(fonte, traco), range: sub)
        }
        armazenamento.endEditing()
        aoMudar?()
    }

    private func trocarTraco(_ fonte: NSFont, _ traco: NSFontDescriptor.SymbolicTraits) -> NSFont {
        var tracos = fonte.fontDescriptor.symbolicTraits
        if tracos.contains(traco) { tracos.remove(traco) } else { tracos.insert(traco) }
        return NSFont(descriptor: fonte.fontDescriptor.withSymbolicTraits(tracos), size: fonte.pointSize) ?? fonte
    }

    private func alternarAtributo(_ chave: NSAttributedString.Key, valor: Any) {
        guard let tv = textView, let armazenamento = tv.textStorage else { return }
        let intervalo = tv.selectedRange()
        if intervalo.length == 0 {
            let ativo = tv.typingAttributes[chave] != nil
            let novo: Any? = ativo ? nil : valor
            tv.typingAttributes[chave] = novo
            return
        }
        let jaTem = armazenamento.attribute(chave, at: intervalo.location, effectiveRange: nil) != nil
        armazenamento.beginEditing()
        if jaTem {
            armazenamento.removeAttribute(chave, range: intervalo)
        } else {
            armazenamento.addAttribute(chave, value: valor, range: intervalo)
        }
        armazenamento.endEditing()
        aoMudar?()
    }
}

/// Caixinhas de tarefa da nota rápida. No texto (e no arquivo salvo) continuam sendo ☐ e ☑;
/// o caractere fica invisível e no lugar dele é desenhado um squircle: vazio com contorno, ou
/// cheio na cor de destaque com um ✓.
final class LayoutDasCaixas: NSLayoutManager {
    static let vazia: Character = "☐"
    static let marcada: Character = "☑"
    var escala: CGFloat = 1

    /// Deixa ☐/☑ transparentes e com uma fonte que reserva o espaço da caixinha maior.
    static func estilizar(_ s: NSTextStorage, _ escala: CGFloat) {
        let texto = s.string as NSString
        let fonte = NSFont(name: "Apple Symbols", size: 19 * escala) ?? NSFont.systemFont(ofSize: 17 * escala)
        var i = 0
        while i < texto.length {
            let c = texto.character(at: i)
            if c == 0x2610 || c == 0x2611 {
                s.addAttributes([.foregroundColor: NSColor.clear, .font: fonte], range: NSRange(location: i, length: 1))
            }
            i += 1
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let texto = textStorage?.string as NSString? else { return }
        let caracteres = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let lado = 15 * escala
        let altura = NSFont.systemFont(ofSize: 13 * escala).capHeight
        for i in caracteres.location..<NSMaxRange(caracteres) {
            let c = texto.character(at: i)
            guard c == 0x2610 || c == 0x2611 else { continue }
            let glifo = glyphIndexForCharacter(at: i)
            let linha = lineFragmentRect(forGlyphAt: glifo, effectiveRange: nil)
            let ponto = location(forGlyphAt: glifo)
            let largura = boundingRect(forGlyphRange: NSRange(location: glifo, length: 1), in: textContainers[0]).width
            // Centro: no meio do espaço do caractere e na altura do meio das letras da linha.
            let centro = NSPoint(x: origin.x + linha.minX + ponto.x + largura / 2,
                                 y: origin.y + linha.minY + ponto.y - altura / 2)
            Self.desenharCaixa(em: NSRect(x: centro.x - lado / 2, y: centro.y - lado / 2, width: lado, height: lado),
                               marcada: c == 0x2611)
        }
    }

    /// Squircle (superelipse de grau 4): cantos mais suaves que um retângulo arredondado.
    static func squircle(_ r: NSRect) -> NSBezierPath {
        let caminho = NSBezierPath()
        let passos = 64
        for k in 0...passos {
            let t = Double(k) / Double(passos) * 2 * .pi
            let cx = cos(t), cy = sin(t)
            let x = r.midX + r.width / 2 * CGFloat(copysign(pow(abs(cx), 0.5), cx))
            let y = r.midY + r.height / 2 * CGFloat(copysign(pow(abs(cy), 0.5), cy))
            k == 0 ? caminho.move(to: NSPoint(x: x, y: y)) : caminho.line(to: NSPoint(x: x, y: y))
        }
        caminho.close()
        return caminho
    }

    static func desenharCaixa(em r: NSRect, marcada: Bool) {
        if marcada {
            NSColor.controlAccentColor.setFill()
            squircle(r).fill()
            // ✓ branco (a tela do editor é "flipped": y cresce para baixo).
            let check = NSBezierPath()
            check.move(to: NSPoint(x: r.minX + r.width * 0.27, y: r.minY + r.height * 0.52))
            check.line(to: NSPoint(x: r.minX + r.width * 0.44, y: r.minY + r.height * 0.69))
            check.line(to: NSPoint(x: r.minX + r.width * 0.74, y: r.minY + r.height * 0.33))
            check.lineWidth = max(1.6, r.width * 0.13)
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            let caminho = squircle(r.insetBy(dx: 0.75, dy: 0.75))
            caminho.lineWidth = 1.5
            NSColor.white.withAlphaComponent(0.55).setStroke()
            caminho.stroke()
        }
    }
}

/// Clicar numa caixinha marca ou desmarca (troca ☐ por ☑ no texto, com desfazer).
final class TextoDaNota: NSTextView {
    override func mouseDown(with event: NSEvent) {
        let ponto = convert(event.locationInWindow, from: nil)
        if let lm = layoutManager, let tc = textContainer, let s = textStorage, s.length > 0 {
            let p = NSPoint(x: ponto.x - textContainerOrigin.x, y: ponto.y - textContainerOrigin.y)
            var fracao: CGFloat = 0
            let glifo = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: &fracao)
            let i = lm.characterIndexForGlyph(at: glifo)
            // Folga de alguns pontos em volta: a caixinha desenhada é um pouco maior que o caractere.
            let area = lm.boundingRect(forGlyphRange: NSRange(location: glifo, length: 1), in: tc).insetBy(dx: -3, dy: -2)
            let c = i < s.length ? (s.string as NSString).character(at: i) : 0
            if area.contains(p), c == 0x2610 || c == 0x2611 {
                let novo = c == 0x2610 ? "☑" : "☐"
                let alvo = NSRange(location: i, length: 1)
                if shouldChangeText(in: alvo, replacementString: novo) {
                    s.replaceCharacters(in: alvo, with: novo)
                    didChangeText()
                }
                return
            }
        }
        super.mouseDown(with: event)
    }
}

/// Estica o NSTextView até a altura visível. Sem isso ele só tem a altura do texto, e um
/// clique abaixo da última linha cai no fundo da rolagem, sem dar foco ao campo.
final class RolagemDoEditor: NSScrollView {
    override func tile() {
        super.tile()
        guard let tv = documentView as? NSTextView, tv.minSize.height != contentSize.height else { return }
        tv.minSize = NSSize(width: 0, height: contentSize.height)
        tv.sizeToFit()
    }
}

/// NSTextView com formatação rica. O conteúdo é salvo como RTF a cada mudança.
struct EditorRico: NSViewRepresentable {
    let controle: EditorNotas
    let documento: NSAttributedString
    /// Tamanho da fonte dos Ajustes ÷ 13. A nota é salva sempre no tamanho original; só a tela muda.
    let escala: CGFloat
    let aoMudar: (NSAttributedString) -> Void

    func makeCoordinator() -> Coordinator {
        let escala = escala
        let salvar = aoMudar
        return Coordinator { salvar(Self.escalar($0, 1 / escala)) }
    }

    /// Multiplica o tamanho de todas as fontes (arredondado em meio ponto, para ir e voltar igual).
    static func escalar(_ texto: NSAttributedString, _ fator: CGFloat) -> NSAttributedString {
        guard abs(fator - 1) > 0.001 else { return texto }
        let m = NSMutableAttributedString(attributedString: texto)
        m.enumerateAttribute(.font, in: NSRange(location: 0, length: m.length)) { valor, r, _ in
            let fonte = (valor as? NSFont) ?? NSFont.systemFont(ofSize: 13)
            let tamanho = (fonte.pointSize * fator * 2).rounded() / 2
            m.addAttribute(.font, value: NSFontManager.shared.convert(fonte, toSize: tamanho), range: r)
        }
        return m
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = RolagemDoEditor()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // Sistema de texto montado à mão para usar o LayoutDasCaixas (desenha as caixinhas).
        let armazenamentoTexto = NSTextStorage()
        let layout = LayoutDasCaixas()
        layout.escala = escala
        armazenamentoTexto.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        let tv = TextoDaNota(frame: .zero, textContainer: container)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        scroll.documentView = tv

        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.appearance = NSAppearance(named: .darkAqua)
        tv.textContainerInset = NSSize(width: 12, height: 18)
        tv.textColor = .white
        tv.insertionPointColor = .white
        tv.font = NSFont.systemFont(ofSize: 13 * escala)
        tv.typingAttributes = [.font: NSFont.systemFont(ofSize: 13 * escala), .foregroundColor: NSColor.white]
        controle.escala = escala

        // Texto salvo pode ter sido escrito com outra cor; no escuro ele precisa ficar branco.
        let carregado = NSMutableAttributedString(attributedString: Self.escalar(documento, escala))
        carregado.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: carregado.length))
        tv.textStorage?.setAttributedString(carregado)
        if let armazenamento = tv.textStorage { LayoutDasCaixas.estilizar(armazenamento, escala) }

        let salvar = aoMudar
        let fator = 1 / escala
        let escalaAtual = escala
        controle.textView = tv
        controle.aoMudar = { [weak tv] in
            guard let tv else { return }
            if let armazenamento = tv.textStorage { LayoutDasCaixas.estilizar(armazenamento, escalaAtual) }
            salvar(Self.escalar(tv.attributedString(), fator))
        }
        context.coordinator.escala = escala
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    final class Coordinator: NSObject, NSTextViewDelegate {
        let aoMudar: (NSAttributedString) -> Void

        init(aoMudar: @escaping (NSAttributedString) -> Void) {
            self.aoMudar = aoMudar
        }

        var escala: CGFloat = 1

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, let armazenamento = tv.textStorage else { return }
            // Nota sempre em branco: o que for digitado ou colado recebe a cor do tema escuro.
            armazenamento.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: armazenamento.length))
            LayoutDasCaixas.estilizar(armazenamento, escala)
            aoMudar(tv.attributedString())
        }
    }
}

/// Bolinha vermelha que cresce e brilha com o volume da voz: parada, o microfone não está captando.
struct OrbDeVoz: View {
    @ObservedObject var nivel: NivelDeVoz

    var body: some View {
        let n = CGFloat(nivel.valor)
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.3))
                .frame(width: 30, height: 30)
                .scaleEffect(0.6 + n * 0.9)
                .blur(radius: 5)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.62, blue: 0.56), .red],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 12))
                .frame(width: 18, height: 18)
                .scaleEffect(0.8 + n * 0.45)
                .shadow(color: .red.opacity(0.8), radius: 3 + n * 8)
        }
        .animation(.easeOut(duration: 0.12), value: nivel.valor)
        .help("Ouvindo… clique para parar")
    }
}

/// Aba Notas: uma área de texto grande à esquerda e a barra de formatação à direita.
struct NotesView: View {
    @ObservedObject var notes: NotesStore
    @State private var editor = EditorNotas()
    /// Vive no AppDelegate: a aba é recriada a cada abertura do notch, o ditado não pode morrer junto.
    @ObservedObject var ditado: Ditado
    @AppStorage(Config.atalhoDitado) private var atalhoDitado = Atalho.ditadoPadrao
    @AppStorage(Config.fonteNota) private var fonte = Config.fontePadrao

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            EditorRico(controle: editor, documento: notes.documento, escala: fonte / Config.fontePadrao) { notes.atualizar($0) }
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    botao("bold", "Negrito (⌘B)", "b") { editor.negrito() }
                    botao("italic", "Itálico (⌘I)", "i") { editor.italico() }
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 6) {
                    botao("textformat.size", "Título (⇧⌘T)", "t", [.command, .shift]) { editor.titulo() }
                    botao("checkmark.square", "Checkbox (⇧⌘C)", "c", [.command, .shift]) { editor.checkbox() }
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 6) {
                    botao("underline", "Sublinhado (⌘U)", "u") { editor.sublinhado() }
                    botao("strikethrough", "Riscado (⇧⌘X)", "x", [.command, .shift]) { editor.riscado() }
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 6) {
                    botao("list.bullet", "Lista (⇧⌘L)", "l", [.command, .shift]) { editor.lista() }
                    botaoDitado
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 118)
            .frame(maxHeight: .infinity)
        }
    }

    /// Microfone: fala vira texto no cursor. Ouvindo, vira um orb que pulsa com a voz (clique para parar).
    private var botaoDitado: some View {
        Button {
            if ditado.ativo {
                ditado.parar()
            } else {
                editor.comecarDitado()
                Task {
                    await ditado.comecar(aoOuvir: { editor.atualizarDitado($0) }, aoTerminar: { editor.terminarDitado() })
                }
            }
        } label: {
            Group {
                if ditado.ouvindo {
                    OrbDeVoz(nivel: ditado.nivel)
                } else {
                    Image(systemName: ditado.erro == nil ? "mic" : "mic.slash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
                .frame(width: 56)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(ditado.ouvindo ? Color.red.opacity(0.18) : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        // Padrão ⇧⌘V (⌘V sozinho é o colar da nota); dá para trocar nos Ajustes.
        .keyboardShortcut(atalhoDitado.tecla, modifiers: atalhoDitado.swiftUI)
        .help(ditado.erro ?? (ditado.ouvindo ? "Parar ditado (\(atalhoDitado.texto))" : "Ditar (\(atalhoDitado.texto))"))
    }

    private func botao(
        _ icone: String,
        _ ajuda: String,
        _ tecla: KeyEquivalent,
        _ modificadores: EventModifiers = .command,
        _ acao: @escaping () -> Void
    ) -> some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(tecla, modifiers: modificadores)
        .help(ajuda)
    }
}
