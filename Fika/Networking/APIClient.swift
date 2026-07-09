import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case badStatus(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Set your Mac's address in Settings first."
        case .badStatus(let code, let body):
            if code == 401 { return "Unauthorized — check the token in Settings." }
            if code == 400 && body.contains("OpenAI") { return "Add your OpenAI key in the desktop app's Settings." }
            return "Server error \(code): \(body)"
        case .decoding(let m): return "Couldn't read the response: \(m)"
        case .transport(let m): return "Can't reach Fika: \(m)"
        }
    }
}

/// Thin async client over the sidecar's FastAPI. One instance per app, reading
/// its address from ServerSettings each call so edits take effect immediately.
struct APIClient {
    let settings: ServerSettings

    private var session: URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }

    // MARK: request plumbing

    private func makeRequest(_ path: String, method: String = "GET", query: [String: String] = [:]) throws -> URLRequest {
        guard let base = settings.baseURL else { throw APIError.notConfigured }
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        let tok = settings.token.trimmingCharacters(in: .whitespaces)
        if !tok.isEmpty { req.setValue(tok, forHTTPHeaderField: "X-Fika-Token") }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw APIError.badStatus(code, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding("\(error)")
        }
    }

    private func getJSON<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T {
        try await send(try makeRequest(path, query: query), as: type)
    }

    private func postJSON<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        var req = try makeRequest(path, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return try await send(req, as: type)
    }

    // MARK: meta

    func health() async throws -> Health { try await getJSON("/health", as: Health.self) }
    func usage() async throws -> Usage { try await getJSON("/usage", as: Usage.self) }

    // MARK: people

    func people() async throws -> [Person] {
        struct Wrap: Codable { let people: [Person] }
        return try await getJSON("/people", as: Wrap.self).people
    }

    func person(_ id: String) async throws -> PersonDetail {
        try await getJSON("/people/\(id)", as: PersonDetail.self)
    }

    func createPerson(name: String, relationship: String, profile: String, tags: [String]) async throws -> CreatedID {
        struct Body: Codable { let name: String; let relationship: String; let profile: String; let tags: [String] }
        return try await postJSON("/people", body: Body(name: name, relationship: relationship, profile: profile, tags: tags), as: CreatedID.self)
    }

    func intakeQuestions(name: String, relationship: String) async throws -> [String] {
        try await getJSON("/intake", query: ["name": name, "relationship": relationship], as: Questions.self).questions
    }

    func enrichQuestions(personID: String) async throws -> [String] {
        try await getJSON("/people/\(personID)/enrich", as: Questions.self).questions
    }

    // MARK: notes

    func createNote(text: String, people: [String] = [], occurredAt: String? = nil, prompt: String = "") async throws -> CreatedID {
        struct Body: Codable { let text: String; let people: [String]; let occurred_at: String?; let prompt: String }
        return try await postJSON("/notes", body: Body(text: text, people: people, occurred_at: occurredAt, prompt: prompt), as: CreatedID.self)
    }

    // MARK: search

    func search(_ q: String, limit: Int = 30, history: [SearchTurn] = []) async throws -> SearchResponse {
        struct Body: Codable { let q: String; let limit: Int; let history: [SearchTurn] }
        return try await postJSON("/search", body: Body(q: q, limit: limit, history: history), as: SearchResponse.self)
    }

    // MARK: serendipity

    func serendipity() async throws -> Serendipity { try await getJSON("/serendipity", as: Serendipity.self) }

    // MARK: me

    func me() async throws -> Me { try await getJSON("/me", as: Me.self) }
    func setMe(profile: String) async throws {
        struct Body: Codable { let profile: String }
        _ = try await postJSON("/me", body: Body(profile: profile), as: CreatedID.self)
    }

    // MARK: reminders

    func reminders(personID: String? = nil) async throws -> [Reminder] {
        struct Wrap: Codable { let reminders: [Reminder] }
        let q = personID.map { ["person_id": $0] } ?? [:]
        return try await getJSON("/reminders", query: q, as: Wrap.self).reminders
    }

    func createReminder(text: String, personID: String = "", personName: String = "", dueAt: String? = nil) async throws -> Reminder {
        struct Body: Codable { let text: String; let person_id: String; let person_name: String; let due_at: String? }
        return try await postJSON("/reminders", body: Body(text: text, person_id: personID, person_name: personName, due_at: dueAt), as: Reminder.self)
    }

    func completeReminder(_ id: String) async throws {
        struct Empty: Codable {}
        _ = try await send(try makeRequest("/reminders/\(id)/done", method: "POST"), as: OKResponse.self)
    }

    // MARK: memory

    func memory() async throws -> MemoryState { try await getJSON("/memory", as: MemoryState.self) }
    func setMemoryEnabled(_ enabled: Bool) async throws {
        struct Body: Codable { let enabled: Bool }
        _ = try await postJSON("/memory/settings", body: Body(enabled: enabled), as: MemoryState.self)
    }
    func clearMemory() async throws {
        _ = try await send(try makeRequest("/memory/clear", method: "POST"), as: OKResponse.self)
    }
    func closeGap(_ id: String) async throws {
        _ = try await send(try makeRequest("/memory/gaps/\(id)/close", method: "POST"), as: OKResponse.self)
    }

    // MARK: multipart (transcribe + avatar)

    func transcribe(_ audio: Data, filename: String = "speech.m4a", contentType: String = "audio/m4a") async throws -> String {
        let (req, body) = try multipart(path: "/transcribe", field: "file", filename: filename, contentType: contentType, data: audio)
        var r = req; r.httpBody = body
        return try await send(r, as: Transcription.self).text
    }

    func uploadAvatar(personID: String, imageData: Data, filename: String = "avatar.jpg", contentType: String = "image/jpeg") async throws {
        let (req, body) = try multipart(path: "/people/\(personID)/avatar", field: "file", filename: filename, contentType: contentType, data: imageData)
        var r = req; r.httpBody = body
        _ = try await send(r, as: OKResponse.self)
    }

    /// URL to display a person's avatar (nil if none / not configured).
    func avatarURL(personID: String) -> URL? {
        guard let base = settings.baseURL else { return nil }
        return base.appendingPathComponent("/avatar/\(personID)")
    }

    private func multipart(path: String, field: String, filename: String, contentType: String, data: Data) throws -> (URLRequest, Data) {
        var req = try makeRequest(path, method: "POST")
        let boundary = "FikaBoundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        return (req, body)
    }
}

struct OKResponse: Codable {
    var ok: Bool?
    var status: String?
}
