import SwiftUI

/// App-wide state: the server address, the API client, and a lightweight
/// connection status shown in Settings and gating the tabs.
@Observable
@MainActor
final class AppState {
    let settings: ServerSettings
    var api: APIClient

    enum Connection: Equatable {
        case unknown, connecting, ok(hasKey: Bool), failed(String)
    }
    var connection: Connection = .unknown

    init() {
        let s = ServerSettings()
        self.settings = s
        self.api = APIClient(settings: s)
    }

    var isConfigured: Bool { settings.isConfigured }

    func checkHealth() async {
        guard settings.isConfigured else { connection = .unknown; return }
        connection = .connecting
        do {
            let h = try await api.health()
            connection = .ok(hasKey: h.has_openai_key ?? false)
        } catch {
            connection = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
