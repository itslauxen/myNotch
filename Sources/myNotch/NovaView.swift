import AppKit
import SwiftUI

/// Aba Nova: notas do Nova Notes. Lista com busca à esquerda, título e Markdown à direita.
struct NovaView: View {
    @ObservedObject var nova: NovaStore
    @State private var busca = ""
    /// Leitura: tudo formatado e links abrem no clique. Edição: dá para digitar.
    @AppStorage("novaEditando") private var editando = false

    var body: some View {
        Group {
            if nova.logado { conteudo } else { NovaLoginView(nova: nova) }
        }
        // Toda vez que a aba aparece, puxa as notas de novo (podem ter mudado na web ou no iPhone).
        .task { await nova.carregar() }
    }

    private var conteudo: some View {
        HStack(alignment: .top, spacing: 10) {
            lista.frame(width: 200)
            if let nota = nova.nota {
                editor(nota)
            } else {
                Text(nova.carregando ? tr("Carregando…", "Loading…") : tr("Nenhuma nota ainda", "No notes yet"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var filtradas: [NovaNota] {
        let q = busca.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nova.notas }
        return nova.notas.filter {
            ($0.title ?? "").localizedStandardContains(q) || ($0.content ?? "").localizedStandardContains(q)
        }
    }

    private var lista: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField(tr("Buscar", "Search"), text: $busca)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))

                Button { Task { await nova.criar() } } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(tr("Nova nota", "New note"))
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(filtradas) { nota in
                        LinhaNova(nota: nota, ativa: nota.id == nova.selecionada) {
                            withAnimation(.easeInOut(duration: 0.15)) { nova.selecionada = nota.id }
                        }
                    }
                }
            }
            // As notas somem aos poucos no pé da lista, como na bandeja.
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .contextMenu {
            Button(tr("Atualizar", "Refresh")) { Task { await nova.carregar() } }
            Button(tr("Sair do Nova Notes", "Sign out of Nova Notes")) { nova.sair() }
        }
    }

    private func editor(_ nota: NovaNota) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(nota.icone).font(.system(size: 16))
                TextField(tr("Sem título", "Untitled"), text: Binding(
                    get: { nota.title ?? "" },
                    set: { nova.editarTitulo(nota.id, $0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold))
                status
                modo
                Button {
                    if let url = URL(string: "https://novanotes.lauxen.dev/note/\(nota.id)") { NSWorkspace.shared.open(url) }
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(tr("Abrir no Nova Notes", "Open in Nova Notes"))
            }
            .frame(height: 28)

            EditorMarkdown(notaId: nota.id, texto: nota.content ?? "", editavel: editando) { id, texto in
                nova.editarConteudo(id, texto)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Alterna leitura e edição: os dois ícones lado a lado, o ativo com fundo.
    private var modo: some View {
        HStack(spacing: 2) {
            botaoModo("book", tr("Leitura: links abrem no clique", "Reading: links open on click"), ativo: !editando) { editando = false }
            botaoModo("pencil", tr("Edição", "Editing"), ativo: editando) { editando = true }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
    }

    private func botaoModo(_ icone: String, _ ajuda: String, ativo: Bool, _ acao: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { acao() }
        } label: {
            Image(systemName: icone)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ativo ? Color.white : Color.secondary)
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(ativo ? 0.16 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ajuda)
    }

    @ViewBuilder private var status: some View {
        switch nova.estado {
        case .salvando:
            Text(tr("Salvando…", "Saving…")).font(.system(size: 11)).foregroundStyle(.secondary)
        case .salvo:
            Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .help(tr("Salvo", "Saved"))
        case .erro(let msg):
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.yellow)
                .help(msg)
        case .ocioso:
            EmptyView()
        }
    }
}

private struct LinhaNova: View {
    let nota: NovaNota
    let ativa: Bool
    let aoEscolher: () -> Void
    @State private var sobre = false

    var body: some View {
        Button(action: aoEscolher) {
            HStack(spacing: 8) {
                Text(nota.icone).font(.system(size: 12))
                Text(nota.titulo)
                    .font(.system(size: 12, weight: ativa ? .semibold : .regular))
                    .foregroundStyle(ativa ? Color.white : Color.white.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(ativa ? 0.12 : sobre ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
    }
}

/// Primeiro uso: entra com a conta do Nova Notes. A senha não é guardada, só a sessão.
struct NovaLoginView: View {
    @ObservedObject var nova: NovaStore
    @State private var email = ""
    @State private var senha = ""
    @State private var erro: String?
    @State private var entrando = false

    var body: some View {
        VStack(spacing: 10) {
            Text(tr("Entre com sua conta do Nova Notes", "Sign in with your Nova Notes account"))
                .font(.system(size: 13, weight: .semibold))
            campo { TextField(tr("E-mail", "Email"), text: $email) }
            campo { SecureField(tr("Senha", "Password"), text: $senha).onSubmit(entrar) }
            Button(action: entrar) {
                Group {
                    if entrando { ProgressView().controlSize(.small) } else { Text(tr("Entrar", "Sign in")) }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
            }
            .buttonStyle(.plain)
            .disabled(entrando || email.isEmpty || senha.isEmpty)
            .opacity(email.isEmpty || senha.isEmpty ? 0.5 : 1)
            Text(erro ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(.red)
        }
        .frame(width: 280)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func campo<C: View>(@ViewBuilder _ conteudo: () -> C) -> some View {
        conteudo()
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
    }

    private func entrar() {
        guard !entrando, !email.isEmpty, !senha.isEmpty else { return }
        entrando = true
        erro = nil
        Task {
            do { try await nova.entrar(email: email.trimmingCharacters(in: .whitespaces), senha: senha); senha = "" }
            catch { erro = error.localizedDescription }
            entrando = false
        }
    }
}

/// Editor do Markdown da nota. O texto continua sendo o Markdown que a web salva, mas aparece
/// formatado: os símbolos (`#`, `**`, `[ ](url)`, crases) somem e só voltam na linha onde está o
/// cursor, para dar para editar.
struct EditorMarkdown: NSViewRepresentable {
    let notaId: String
    let texto: String
    let editavel: Bool
    let aoMudar: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = RolagemDoEditor()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let tv = TextoMarkdown()
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        scroll.documentView = tv

        tv.delegate = context.coordinator
        tv.layoutManager?.delegate = context.coordinator.glifos
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.appearance = NSAppearance(named: .darkAqua)
        tv.textContainerInset = NSSize(width: 12, height: 14)
        tv.insertionPointColor = .white
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor, .cursor: NSCursor.pointingHand]
        tv.typingAttributes = Markdown.base
        tv.isEditable = editavel
        carregar(tv, context.coordinator)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.aoMudar = aoMudar
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.isEditable != editavel {
            tv.isEditable = editavel
            // Entrando na edição o cursor vai para o texto; saindo, tudo volta formatado.
            if editavel { tv.window?.makeFirstResponder(tv) } else { tv.setSelectedRange(NSRange(location: tv.selectedRange().location, length: 0)) }
            context.coordinator.linhaAtiva = context.coordinator.linha(tv)
            Markdown.estilizar(tv, ativa: context.coordinator.linhaAtiva)
        }
        guard context.coordinator.notaId != notaId else { return }
        carregar(tv, context.coordinator)
    }

    /// Troca de nota: texto novo, histórico de desfazer zerado e rolagem no topo.
    private func carregar(_ tv: NSTextView, _ coordenador: Coordinator) {
        coordenador.notaId = notaId
        coordenador.aoMudar = aoMudar
        tv.string = texto
        coordenador.linhaAtiva = nil
        Markdown.estilizar(tv, ativa: nil)
        tv.undoManager?.removeAllActions()
        tv.scroll(.zero)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var notaId = ""
        var aoMudar: (String, String) -> Void = { _, _ in }
        let glifos = SimbolosOcultos()
        /// Linha (parágrafo) onde está o cursor: nela o Markdown aparece cru.
        var linhaAtiva: NSRange?

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            linhaAtiva = linha(tv)
            Markdown.estilizar(tv, ativa: linhaAtiva)
            tv.typingAttributes = Markdown.base
            aoMudar(notaId, tv.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let nova = linha(tv)
            guard nova != linhaAtiva else { return }
            linhaAtiva = nova
            Markdown.estilizar(tv, ativa: nova)
        }

        func linha(_ tv: NSTextView) -> NSRange? {
            guard tv.isEditable, tv.window?.firstResponder === tv else { return nil }
            return (tv.string as NSString).paragraphRange(for: tv.selectedRange())
        }
    }
}

/// Clicar na caixinha de uma tarefa marca ou desmarca, como na web, nos dois modos. Link abre
/// no clique na leitura e com ⌘-clique na edição (lá o clique só põe o cursor).
final class TextoMarkdown: NSTextView {
    /// O painel quase nunca é a janela ativa; sem isto o primeiro clique só a ativava e o link
    /// (ou a caixinha) não reagia.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Link do caractere exatamente debaixo do ponto (não o mais perto, como faz a inserção).
    func link(em ponto: NSPoint) -> URL? {
        guard let lm = layoutManager, let tc = textContainer, let s = textStorage, s.length > 0 else { return nil }
        let p = NSPoint(x: ponto.x - textContainerOrigin.x, y: ponto.y - textContainerOrigin.y)
        var fracao: CGFloat = 0
        let glifo = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: &fracao)
        guard lm.boundingRect(forGlyphRange: NSRange(location: glifo, length: 1), in: tc).contains(p) else { return nil }
        let c = lm.characterIndexForGlyph(at: glifo)
        guard c < s.length else { return nil }
        return s.attribute(.link, at: c, effectiveRange: nil) as? URL
    }

    override func mouseDown(with event: NSEvent) {
        let ponto = convert(event.locationInWindow, from: nil)
        // Abre antes de mexer na seleção: ela redesenha a linha com os símbolos e o clique se perdia.
        if !isEditable || event.modifierFlags.contains(.command), let url = link(em: ponto) {
            registrarDebug("nova: clique abriu \(url.absoluteString)")
            NSWorkspace.shared.open(url)
            return
        }
        if !isEditable { registrarDebug("nova: clique na leitura sem link (caractere \(characterIndexForInsertion(at: ponto)))") }
        let indice = characterIndexForInsertion(at: ponto)
        let texto = string as NSString
        if texto.length > 0, indice <= texto.length {
            let linha = texto.lineRange(for: NSRange(location: min(indice, texto.length - 1), length: 0))
            if let m = Markdown.tarefa.firstMatch(in: string, range: linha) {
                let caixa = m.range(at: 2) // o caractere entre os colchetes
                if indice >= m.range.location, indice <= caixa.location + 2 {
                    let marcado = texto.substring(with: caixa) != " "
                    if !isEditable {
                        // Na leitura o NSTextView recusa mudanças; troca direto e avisa o delegate para salvar.
                        textStorage?.replaceCharacters(in: caixa, with: marcado ? " " : "x")
                        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
                    } else if shouldChangeText(in: caixa, replacementString: marcado ? " " : "x") {
                        textStorage?.replaceCharacters(in: caixa, with: marcado ? " " : "x")
                        didChangeText()
                    }
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}

/// Some com os símbolos marcados pelo `Markdown` (glifo nulo, sem largura) e troca o `-` da
/// lista pela bolinha e o `[ ]` pela caixinha, sem mexer no texto.
final class SimbolosOcultos: NSObject, NSLayoutManagerDelegate {
    func layoutManager(_ lm: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard let s = lm.textStorage else { return 0 }
        var novosGlifos = Array(UnsafeBufferPointer(start: glyphs, count: range.length))
        var novasProps = Array(UnsafeBufferPointer(start: props, count: range.length))
        var mudou = false
        for i in 0..<range.length {
            let c = characterIndexes[i]
            guard c < s.length else { continue }
            if s.attribute(Markdown.ocultar, at: c, effectiveRange: nil) != nil {
                novasProps[i] = .null
                mudou = true
            } else if let troca = s.attribute(Markdown.trocarPor, at: c, effectiveRange: nil) as? String {
                var u = Array(troca.utf16)
                var g = [CGGlyph](repeating: 0, count: u.count)
                if CTFontGetGlyphsForCharacters(font as CTFont, &u, &g, u.count) {
                    novosGlifos[i] = g[0]
                    mudou = true
                }
            }
        }
        guard mudou else { return 0 }
        lm.setGlyphs(novosGlifos, properties: novasProps, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
        return range.length
    }
}

/// Aparência do Markdown no editor: fonte, cor e o que esconder, por trecho, sem tocar no texto.
enum Markdown {
    static let tamanho: CGFloat = 13
    static let ocultar = NSAttributedString.Key("novaOcultar")
    static let trocarPor = NSAttributedString.Key("novaTrocarPor")

    private static let paragrafo: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2
        p.paragraphSpacing = 5
        return p
    }()
    static let base: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: tamanho), .foregroundColor: NSColor.white, .paragraphStyle: paragrafo,
    ]
    private static let simbolo = NSColor.white.withAlphaComponent(0.28)
    private static let apagado = NSColor.white.withAlphaComponent(0.45)
    /// Fonte com ☐ e ☑ (a do sistema não tem).
    private static let fonteCaixa = NSFont(name: "Apple Symbols", size: 17) ?? NSFont.systemFont(ofSize: 15)

    private static func re(_ padrao: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: padrao, options: [.anchorsMatchLines])
    }
    static let tarefa = re(#"^(\s*[-*+] \[)([ xX])(\]) ?"#)
    private static let titulo = re(#"^(#{1,3} ).*$"#)
    private static let item = re(#"^\s*([-*+]) (?!\[[ xX]\])"#)
    private static let numerado = re(#"^\s*(\d+\.) "#)
    private static let citacao = re(#"^(> ?).*$"#)
    private static let html = re(#"^\s*<(/?[a-zA-Z]|!--).*$"#)
    private static let cerca = re(#"^```.*$"#)
    private static let negrito = re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italico = re(#"(?<![*\w])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![*\w])"#)
    private static let riscado = re(#"(~~)(.+?)~~"#)
    private static let codigo = re(#"(`)([^`\n]+)`"#)
    private static let link = re(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
    private static let autolink = re(#"<(https?://[^>\s]+)>|(?<![(<])(https?://[^\s)>]+)"#)

    static func estilizar(_ tv: NSTextView, ativa: NSRange?) {
        guard let s = tv.textStorage else { return }
        estilizar(s, ativa: ativa)
        tv.layoutManager?.invalidateGlyphs(forCharacterRange: NSRange(location: 0, length: s.length), changeInLength: 0, actualCharacterRange: nil)
    }

    static func estilizar(_ s: NSTextStorage, ativa: NSRange?) {
        let texto = s.string
        let ns = texto as NSString
        let tudo = NSRange(location: 0, length: ns.length)
        s.beginEditing()
        s.setAttributes(base, range: tudo)

        /// Some com os símbolos, menos na linha do cursor (lá ficam visíveis, só apagados).
        func esconder(_ r: NSRange) {
            guard r.length > 0, r.location != NSNotFound else { return }
            if let ativa, NSIntersectionRange(ativa, r).length > 0 || (r.location >= ativa.location && r.location < NSMaxRange(ativa)) {
                s.addAttribute(.foregroundColor, value: simbolo, range: r)
            } else {
                s.addAttribute(ocultar, value: true, range: r)
            }
        }
        func naLinhaAtiva(_ r: NSRange) -> Bool {
            guard let ativa else { return false }
            return NSIntersectionRange(ativa, r).length > 0
        }

        // Trechos onde o Markdown não vale: blocos de código e HTML dos blocos da web.
        var literal: [NSRange] = []
        var cercasEscondidas: [NSRange] = []
        var aberta: NSRange?
        for m in cerca.matches(in: texto, range: tudo) {
            if let inicio = aberta {
                literal.append(NSRange(location: inicio.location, length: NSMaxRange(m.range) - inicio.location))
                aberta = nil
            } else {
                aberta = m.range
            }
            // A linha da cerca (```) vira quase nada fora da linha do cursor.
            if !naLinhaAtiva(m.range) {
                let linha = ns.lineRange(for: m.range)
                s.addAttribute(.font, value: NSFont.systemFont(ofSize: 4), range: linha)
                esconder(m.range)
                cercasEscondidas.append(linha)
            }
        }
        if let inicio = aberta { literal.append(NSRange(location: inicio.location, length: ns.length - inicio.location)) }
        for r in literal {
            s.enumerateAttribute(.font, in: r) { valor, sub, _ in
                if (valor as? NSFont)?.pointSize != 4 {
                    s.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: sub)
                }
            }
            s.addAttributes([.foregroundColor: NSColor.white.withAlphaComponent(0.85),
                             .backgroundColor: NSColor.white.withAlphaComponent(0.06)], range: r)
        }
        // Sem fundo na linha encolhida da cerca: ele vazava como uma faixa ao lado da linha de cima.
        for r in cercasEscondidas { s.removeAttribute(.backgroundColor, range: r) }
        for m in html.matches(in: texto, range: tudo) {
            s.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: apagado], range: m.range)
            literal.append(m.range)
        }
        func livre(_ r: NSRange) -> Bool { !literal.contains { NSIntersectionRange($0, r).length > 0 } }

        for m in titulo.matches(in: texto, range: tudo) where livre(m.range) {
            let nivel = m.range(at: 1).length - 1
            let fonte = NSFont.systemFont(ofSize: [0, 22, 17, 15][nivel], weight: nivel == 3 ? .semibold : .bold)
            s.addAttribute(.font, value: fonte, range: m.range)
            esconder(m.range(at: 1))
        }
        for m in item.matches(in: texto, range: tudo) where livre(m.range) {
            if naLinhaAtiva(m.range) {
                s.addAttribute(.foregroundColor, value: apagado, range: m.range(at: 1))
            } else {
                s.addAttributes([trocarPor: "•", .foregroundColor: apagado], range: m.range(at: 1))
            }
        }
        for m in numerado.matches(in: texto, range: tudo) where livre(m.range) {
            s.addAttribute(.foregroundColor, value: apagado, range: m.range(at: 1))
        }
        for m in tarefa.matches(in: texto, range: tudo) where livre(m.range) {
            let feita = ns.substring(with: m.range(at: 2)) != " "
            if naLinhaAtiva(m.range) {
                s.addAttributes([.foregroundColor: NSColor.controlAccentColor,
                                 .font: NSFont.monospacedSystemFont(ofSize: tamanho, weight: .bold)],
                                range: NSRange(location: NSMaxRange(m.range(at: 1)) - 1, length: 3))
            } else {
                // "- [" e "]" somem; o caractere do meio vira a caixinha.
                esconder(m.range(at: 1))
                esconder(m.range(at: 3))
                s.addAttributes([trocarPor: feita ? "☑" : "☐", .font: fonteCaixa,
                                 .foregroundColor: feita ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.6)],
                                range: m.range(at: 2))
            }
            if feita {
                let linha = ns.lineRange(for: m.range)
                let resto = NSRange(location: NSMaxRange(m.range), length: NSMaxRange(linha) - NSMaxRange(m.range))
                s.addAttributes([.foregroundColor: apagado, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: resto)
            }
        }
        for m in citacao.matches(in: texto, range: tudo) where livre(m.range) {
            s.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.7), range: m.range)
            trocar(s, m.range, .italicFontMask)
            esconder(m.range(at: 1))
        }

        for m in negrito.matches(in: texto, range: tudo) where livre(m.range) {
            trocar(s, m.range(at: 2), .boldFontMask)
            esconderEmVolta(m.range, m.range(at: 2), esconder)
        }
        for m in italico.matches(in: texto, range: tudo) where livre(m.range) {
            trocar(s, m.range(at: 2), .italicFontMask)
            esconderEmVolta(m.range, m.range(at: 2), esconder)
        }
        for m in riscado.matches(in: texto, range: tudo) where livre(m.range) {
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 2))
            esconderEmVolta(m.range, m.range(at: 2), esconder)
        }
        for m in codigo.matches(in: texto, range: tudo) where livre(m.range) {
            s.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                             .backgroundColor: NSColor.white.withAlphaComponent(0.1)], range: m.range(at: 2))
            esconderEmVolta(m.range, m.range(at: 2), esconder)
        }
        for m in link.matches(in: texto, range: tudo) where livre(m.range) {
            if let url = URL(string: ns.substring(with: m.range(at: 2))) { s.addAttribute(.link, value: url, range: m.range(at: 1)) }
            esconderEmVolta(m.range, m.range(at: 1), esconder)
        }
        for m in autolink.matches(in: texto, range: tudo) where livre(m.range) {
            let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            if let url = URL(string: ns.substring(with: r)) { s.addAttribute(.link, value: url, range: r) }
            if m.range(at: 1).location != NSNotFound { esconderEmVolta(m.range, r, esconder) }
        }
        s.endEditing()
    }

    /// Esconde os símbolos em volta do miolo (`**`, `_`, `[`, `](url)`, `<`, `>`).
    private static func esconderEmVolta(_ todo: NSRange, _ miolo: NSRange, _ esconder: (NSRange) -> Void) {
        esconder(NSRange(location: todo.location, length: miolo.location - todo.location))
        esconder(NSRange(location: NSMaxRange(miolo), length: NSMaxRange(todo) - NSMaxRange(miolo)))
    }

    /// Soma negrito ou itálico à fonte que já está no trecho (um título em negrito continua grande).
    private static func trocar(_ s: NSTextStorage, _ r: NSRange, _ traco: NSFontTraitMask) {
        s.enumerateAttribute(.font, in: r) { valor, sub, _ in
            let fonte = (valor as? NSFont) ?? NSFont.systemFont(ofSize: tamanho)
            s.addAttribute(.font, value: NSFontManager.shared.convert(fonte, toHaveTrait: traco), range: sub)
        }
    }
}
