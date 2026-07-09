import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "sparkles") }
            PeopleView()
                .tabItem { Label("People", systemImage: "person.2") }
            SearchView()
                .tabItem { Label("Ask", systemImage: "magnifyingglass") }
            RemindersView()
                .tabItem { Label("Reminders", systemImage: "bell") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { await app.checkHealth() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await app.checkHealth() } }
        }
    }
}
