import SwiftUI

@main
struct FikaApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Color(red: 0.62, green: 0.44, blue: 0.29)) // warm Fika accent
        }
    }
}
