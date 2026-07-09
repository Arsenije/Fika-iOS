import Foundation

/// Where the Fika sidecar lives on your LAN. Persisted in UserDefaults; you
/// type the Mac's IP + port in the Settings tab.
@Observable
final class ServerSettings {
    var host: String {
        didSet { defaults.set(host, forKey: "fika.host") }
    }
    var port: Int {
        didSet { defaults.set(port, forKey: "fika.port") }
    }
    /// Optional shared secret — must match FIKA_TOKEN on the server if set there.
    var token: String {
        didSet { defaults.set(token, forKey: "fika.token") }
    }

    private let defaults = UserDefaults.standard

    init() {
        self.host = defaults.string(forKey: "fika.host") ?? ""
        let p = defaults.integer(forKey: "fika.port")
        self.port = p == 0 ? 8765 : p
        self.token = defaults.string(forKey: "fika.token") ?? ""
    }

    var isConfigured: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty }

    var baseURL: URL? {
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { return nil }
        return URL(string: "http://\(h):\(port)")
    }
}
