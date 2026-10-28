import Foundation

/// Uma página do Nova Notes (tabela `notes` do Supabase do app web). O conteúdo é Markdown.
struct NovaNota: Codable, Identifiable, Equatable {
    let id: String
    var title: String?
    var emoji: String?
    var content: String?
    var isGoal: Bool?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, emoji, content
        case isGoal = "is_goal"
        case updatedAt = "updated_at"
    }

    var titulo: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Sem título" : t
    }
    var icone: String { emoji.flatMap { $0.isEmpty ? nil : $0 } ?? "📄" }
}

/// Aba Nova: lê e edita as notas do Nova Notes direto pela API REST do Supabase,
/// entrando com a conta do usuário (as regras de RLS deixam ver só as notas dele).
@MainActor
final class NovaStore: ObservableObject {
    // Mesmo projeto e chave pública do app web (a chave anon vai no bundle da web de qualquer jeito).
    private static let url = "https://uwocmpreccxamsrdolxm.supabase.co"
    private static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV3b2NtcHJlY2N4YW1zcmRvbHhtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4OTU1MjIsImV4cCI6MjA5NjQ3MTUyMn0.SBwAL5FwNd11B_fjvgozoFJd81ZHKG5h8E-mLg6nwLc"

    enum Estado: Equatable { case ocioso, salvando, salvo, erro(String) }

    @Published private(set) var notas: [NovaNota] = []
    @Published private(set) var logado: Bool
    @Published var selecionada: String?
    @Published private(set) var estado: Estado = .ocioso
    @Published private(set) var carregando = false

    private struct Sessao: Codable {
        var accessToken: String
        var refreshToken: String
        var userId: String
        var email: String?
    }

    /// Conta conectada, para os Ajustes (sessões antigas não guardavam o e-mail).
    var email: String? { sessao?.email }

    /// Só o token de renovação fica salvo (nunca a senha), num arquivo legível só pelo usuário.
    private let arquivoSessao = AppPaths.dir.appendingPathComponent("nova-sessao.json")
    private var sessao: Sessao? {
        didSet {
            logado = sessao != nil
            if let sessao, let dados = try? JSONEncoder().encode(sessao) {
                try? dados.write(to: arquivoSessao, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: arquivoSessao.path)
            } else {
                try? FileManager.default.removeItem(at: arquivoSessao)
            }
        }
    }

    /// Mudanças ainda não enviadas, por nota. Digitar só agenda; o envio sai 0,7 s depois da última tecla.
    private var pendentes: [String: [String: Any]] = [:]
    private var envio: Task<Void, Never>?

    init() {
        let salva = (try? Data(contentsOf: arquivoSessao)).flatMap { try? JSONDecoder().decode(Sessao.self, from: $0) }
        sessao = salva
        logado = salva != nil
    }

    var nota: NovaNota? { notas.first { $0.id == selecionada } }

    /* ---------------- conta ---------------- */

    func entrar(email: String, senha: String) async throws {
        let dados = try await pedir("POST", "/auth/v1/token?grant_type=password",
                                    corpo: ["email": email, "password": senha], autenticado: false)
        sessao = try Self.lerSessao(dados)
        await carregar()
    }

    func sair() {
        sessao = nil
        notas = []
        selecionada = nil
        pendentes = [:]
    }

    private func renovar() async throws {
        guard let sessao else { throw NovaErro("Entre de novo na sua conta") }
        do {
            let dados = try await pedir("POST", "/auth/v1/token?grant_type=refresh_token",
                                        corpo: ["refresh_token": sessao.refreshToken], autenticado: false)
            self.sessao = try Self.lerSessao(dados)
        } catch {
            sair()
            throw NovaErro("Sessão expirada, entre de novo")
        }
    }

    private static func lerSessao(_ dados: Data) throws -> Sessao {
        guard let json = try JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any], let id = user["id"] as? String
        else { throw NovaErro("Resposta inesperada do login") }
        return Sessao(accessToken: access, refreshToken: refresh, userId: id, email: user["email"] as? String)
    }

    /* ---------------- notas ---------------- */

    func carregar() async {
        guard logado, Config.novaLigada else { return }
        carregando = true
        defer { carregando = false }
        do {
            let dados = try await pedir("GET", "/rest/v1/notes?select=id,title,emoji,content,is_goal,updated_at&is_agent=eq.false&order=updated_at.desc")
            var novas = try JSONDecoder().decode([NovaNota].self, from: dados)
            // O que ainda não foi enviado vale mais que o que veio do banco.
            for i in novas.indices {
                guard let campos = pendentes[novas[i].id] else { continue }
                if let c = campos["content"] as? String { novas[i].content = c }
                if let t = campos["title"] as? String { novas[i].title = t }
            }
            notas = novas
            if selecionada == nil || !notas.contains(where: { $0.id == selecionada }) { selecionada = notas.first?.id }
            if case .erro = estado { estado = .ocioso }
        } catch {
            estado = .erro(error.localizedDescription)
        }
    }

    func criar() async {
        guard let sessao else { return }
        do {
            let linha: [String: Any] = [
                "user_id": sessao.userId, "title": "", "emoji": "📄", "content": "", "tags": [String](),
                "is_goal": false, "is_agent": false, "progress": 0, "done": false, "position": 0,
            ]
            let dados = try await pedir("POST", "/rest/v1/notes?select=id,title,emoji,content,is_goal,updated_at",
                                        corpo: linha, prefer: "return=representation")
            guard let nova = try JSONDecoder().decode([NovaNota].self, from: dados).first else { return }
            notas.insert(nova, at: 0)
            selecionada = nova.id
        } catch {
            estado = .erro(error.localizedDescription)
        }
    }

    func editarTitulo(_ id: String, _ titulo: String) {
        guard let i = notas.firstIndex(where: { $0.id == id }), notas[i].title != titulo else { return }
        notas[i].title = titulo
        agendar(id, ["title": titulo])
    }

    func editarConteudo(_ id: String, _ texto: String) {
        guard let i = notas.firstIndex(where: { $0.id == id }), notas[i].content != texto else { return }
        notas[i].content = texto
        var campos: [String: Any] = ["content": texto]
        // Nota de objetivo: o progresso segue as tarefas marcadas, com a mesma regra da web.
        if notas[i].isGoal == true {
            let (total, feitas) = Self.contarTarefas(texto)
            if total > 0 {
                let p = Int((Double(feitas) / Double(total) * 100).rounded())
                campos["progress"] = p
                campos["done"] = p == 100
            }
        }
        agendar(id, campos)
    }

    private func agendar(_ id: String, _ campos: [String: Any]) {
        pendentes[id, default: [:]].merge(campos) { $1 }
        estado = .salvando
        envio?.cancel()
        envio = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.enviarPendentes()
        }
    }

    private func enviarPendentes() async {
        let lote = pendentes
        pendentes = [:]
        do {
            for (id, campos) in lote {
                var corpo = campos
                corpo["updated_at"] = ISO8601DateFormatter().string(from: Date())
                _ = try await pedir("PATCH", "/rest/v1/notes?id=eq.\(id)", corpo: corpo, prefer: "return=minimal")
            }
            if pendentes.isEmpty { estado = .salvo }
        } catch {
            // Não perde a edição: volta para a fila e tenta junto com a próxima mudança.
            for (id, campos) in lote { pendentes[id, default: [:]].merge(campos) { atual, _ in atual } }
            estado = .erro(error.localizedDescription)
        }
    }

    /// Checkboxes `- [ ]`/`- [x]` e dias dos marcadores de progresso (`data-count`/`data-done`).
    static func contarTarefas(_ md: String) -> (total: Int, feitas: Int) {
        var total = 0, feitas = 0
        for linha in md.components(separatedBy: "\n") {
            if let m = linha.firstMatch(of: #/^\s*[-*+]\s+\[( |x|X)\]/#) {
                total += 1
                if m.1 != " " { feitas += 1 }
            }
        }
        for m in md.matches(of: #/data-count="(\d+)"\s+data-done="([01]*)"/#) {
            total += Int(m.1) ?? 0
            feitas += m.2.filter { $0 == "1" }.count
        }
        return (total, feitas)
    }

    /* ---------------- HTTP ---------------- */

    private func pedir(_ metodo: String, _ caminho: String, corpo: Any? = nil, prefer: String? = nil,
                       autenticado: Bool = true, tentarDeNovo: Bool = true) async throws -> Data {
        var req = URLRequest(url: URL(string: Self.url + caminho)!)
        req.httpMethod = metodo
        req.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(autenticado ? sessao?.accessToken ?? Self.anonKey : Self.anonKey)", forHTTPHeaderField: "Authorization")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let corpo {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: corpo)
        }
        let (dados, resposta) = try await URLSession.shared.data(for: req)
        let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        // Token de acesso dura 1 h: venceu, renova e tenta uma vez de novo.
        if status == 401, autenticado, tentarDeNovo {
            try await renovar()
            return try await pedir(metodo, caminho, corpo: corpo, prefer: prefer, tentarDeNovo: false)
        }
        guard (200..<300).contains(status) else {
            let json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any]
            let msg = (json?["error_description"] ?? json?["msg"] ?? json?["message"]) as? String
            if status == 400, caminho.contains("grant_type=password") { throw NovaErro("E-mail ou senha incorretos") }
            throw NovaErro(msg ?? "Erro \(status) no Nova Notes")
        }
        return dados
    }
}

struct NovaErro: LocalizedError {
    let mensagem: String
    init(_ mensagem: String) { self.mensagem = mensagem }
    var errorDescription: String? { mensagem }
}
