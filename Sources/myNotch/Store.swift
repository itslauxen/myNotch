import AppKit
import SwiftUI
import Foundation

/// Pasta própria do myNotch: notas e cópias dos prints ficam aqui.
enum AppPaths {
    static var dir: URL {
        // MYNOTCH_DIR troca a pasta: o gerador do GIF do README usa uma de exemplo, sem tocar na real.
        let base = ProcessInfo.processInfo.environment["MYNOTCH_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("myNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var prints: URL {
        let url = dir.appendingPathComponent("prints", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Linha de diagnóstico em ~/Library/Application Support/myNotch/debug.log.
func registrarDebug(_ linha: String) {
    let arquivo = AppPaths.dir.appendingPathComponent("debug.log")
    let texto = "[\(Date())] \(linha)\n"
    if let saida = try? FileHandle(forWritingTo: arquivo) {
        saida.seekToEndOfFile()
        saida.write(Data(texto.utf8))
        try? saida.close()
    } else {
        try? Data(texto.utf8).write(to: arquivo)
    }
}

/// Documento único da aba Notas, em RTF (mantém negrito, título etc.). Salvo a cada mudança.
@MainActor
final class NotesStore: ObservableObject {
    private let file = AppPaths.dir.appendingPathComponent("notas.rtf")
    private(set) var documento: NSAttributedString

    init() {
        if let dados = try? Data(contentsOf: file),
           let salvo = NSAttributedString(rtf: dados, documentAttributes: nil) {
            documento = salvo
        } else {
            documento = NSAttributedString()
        }
    }

    func atualizar(_ novo: NSAttributedString) {
        documento = novo
        let intervalo = NSRange(location: 0, length: novo.length)
        guard let dados = try? novo.data(from: intervalo, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else { return }
        try? dados.write(to: file, options: .atomic)
    }
}

/// Bandeja: guarda sozinha o que for copiado (prints e textos) e deixa arrastar para fora.
@MainActor
final class TrayStore: ObservableObject {
    @Published private(set) var files: [URL] = []

    private var ultimaContagem = NSPasteboard.general.changeCount
    private var observador: Timer?
    /// Quantos itens guardar (Ajustes). Diminuir não apaga nada na hora: vale a partir da próxima cópia.
    private var limite: Int { Config.int(Config.limiteBandeja, 6) }
    /// Nomes dos itens na ordem escolhida pelo usuário; itens novos entram no começo.
    private var ordem: [String] = []
    /// Item que está sendo arrastado dentro da bandeja (para reordenar).
    @Published var arrastando: String?

    private var ordemURL: URL { AppPaths.dir.appendingPathComponent("ordem.json") }

    init() {
        if let dados = try? Data(contentsOf: ordemURL),
           let salva = try? JSONDecoder().decode([String].self, from: dados) {
            ordem = salva
        }
        reload()
        observador = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.verificarAreaDeTransferencia() }
        }
        // Soltar o mouse fora de um item encerra o arraste (dentro ou fora do app).
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] evento in
            Task { @MainActor in self?.agendarFimDoArraste() }
            return evento
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in self?.agendarFimDoArraste() }
        }
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: AppPaths.prints,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let posicao = Dictionary(uniqueKeysWithValues: ordem.enumerated().map { ($0.element, $0.offset) })
        files = urls.sorted { a, b in
            switch (posicao[a.lastPathComponent], posicao[b.lastPathComponent]) {
            case let (x?, y?): return x < y
            case (nil, _?): return true
            case (_?, nil): return false
            case (nil, nil): return dataDe(a) > dataDe(b)
            }
        }
        ordem = files.map(\.lastPathComponent)
        salvarOrdem()
    }

    private func dataDe(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func salvarOrdem() {
        try? JSONEncoder().encode(ordem).write(to: ordemURL)
    }

    private func verificarAreaDeTransferencia() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != ultimaContagem else { return }
        ultimaContagem = pasteboard.changeCount

        // Senhas e outros itens marcados como ocultos pelos gerenciadores de senha ficam de fora.
        let ocultos = (pasteboard.types ?? []).contains {
            $0.rawValue.hasPrefix("org.nspasteboard.ConcealedType") || $0.rawValue.hasPrefix("org.nspasteboard.TransientType")
        }
        guard !ocultos else { return }

        let agora = Int(Date().timeIntervalSince1970 * 1000)
        let imagens = Config.bool(Config.bandejaImagens, true)
        let textos = Config.bool(Config.bandejaTextos, true)
        if imagens, let png = imagemPNG(pasteboard) {
            try? png.write(to: AppPaths.prints.appendingPathComponent("\(agora)-print.png"))
        } else if textos, let texto = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !texto.isEmpty {
            try? Data(texto.utf8).write(to: AppPaths.prints.appendingPathComponent("\(agora)-texto.txt"))
        } else {
            return
        }
        reload()
        podar()
    }

    private func imagemPNG(_ pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Copia um arquivo arrastado para a bandeja. O original não é tocado.
    func importar(_ origem: URL) {
        let destino = AppPaths.prints.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-\(origem.lastPathComponent)")
        try? FileManager.default.copyItem(at: origem, to: destino)
        // copyItem mantém a data do original; a bandeja ordena pela data de entrada.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destino.path)
        reload()
        podar()
    }

    /// Salva uma imagem arrastada (ex.: do Preview) como PNG.
    func importar(imagem: NSImage) {
        guard let tiff = imagem.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: AppPaths.prints.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-print.png"))
        reload()
        podar()
    }

    /// Mantém só os itens mais recentes: apaga o mais antigo por data de entrada.
    private func podar() {
        guard files.count > limite else { return }
        let antigos = files.sorted { dataDe($0) < dataDe($1) }.prefix(files.count - limite)
        for url in antigos { try? FileManager.default.removeItem(at: url) }
        reload()
    }

    /// Põe o item arrastado no lugar do alvo.
    func mover(_ origem: String, para destino: String) {
        var nomes = ordem
        guard let i = nomes.firstIndex(of: origem), let j = nomes.firstIndex(of: destino), i != j else { return }
        nomes.remove(at: i)
        nomes.insert(origem, at: j)
        ordem = nomes
        salvarOrdem()
        reload()
    }

    /// Mostra a nova ordem enquanto o item arrastado está sobre outro. Só salva ao soltar.
    func preverMover(_ origem: String, para destino: String) {
        var nomes = ordem
        guard let i = nomes.firstIndex(of: origem), let j = nomes.firstIndex(of: destino), i != j else { return }
        nomes.remove(at: i)
        nomes.insert(origem, at: j)
        let porNome = Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, $0) })
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            files = nomes.compactMap { porNome[$0] }
        }
    }

    /// Arraste que terminou fora de um item (ou fora da bandeja) volta à ordem salva.
    private func encerrarArraste() {
        guard arrastando != nil else { return }
        arrastando = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { reload() }
    }

    private func agendarFimDoArraste() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            encerrarArraste()
        }
    }

    /// Copia um texto da bandeja de volta para a área de transferência.
    func copiar(_ url: URL) {
        guard let texto = try? String(contentsOf: url, encoding: .utf8) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(texto, forType: .string)
        // Não deixa a própria cópia virar um item novo da bandeja.
        ultimaContagem = pasteboard.changeCount
    }

    /// Remove só a cópia dentro da bandeja.
    func remover(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        reload()
    }
}
