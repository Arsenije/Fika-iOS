import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var data = Serendipity()
    @State private var loading = false
    @State private var error: String?
    @State private var showNote = false

    var body: some View {
        NavigationStack {
            Group {
                if !app.isConfigured {
                    NotConfiguredView()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if let s = data.spotlight { spotlight(s) }
                            reconnect
                            connections
                        }
                        .padding()
                    }
                    .navigationDestination(for: String.self) { id in PersonDetailView(personID: id) }
                }
            }
            .navigationTitle("Fika")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNote = true } label: { Image(systemName: "square.and.pencil") }
                        .disabled(!app.isConfigured)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .overlay { if loading && data.spotlight == nil && data.reconnect.isEmpty { ProgressView() } }
            .sheet(isPresented: $showNote) { NoteComposer() }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    @ViewBuilder private func spotlight(_ p: Person) -> some View {
        NavigationLink(value: p.id) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Someone to think of today").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    AvatarImage(personID: p.id, name: p.name, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.title3.weight(.semibold))
                        Text("Last seen \(RelativeTime.phrase(days: p.days_since))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !p.interests.isEmpty { Chips(items: p.interests, systemImage: "heart") }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var reconnect: some View {
        if !data.reconnect.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reach out").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(data.reconnect) { p in
                            NavigationLink(value: p.id) {
                                VStack(spacing: 6) {
                                    AvatarImage(personID: p.id, name: p.name, size: 60)
                                    Text(p.name).font(.caption).lineLimit(1)
                                    Text(RelativeTime.phrase(days: p.days_since))
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(width: 84)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var connections: some View {
        if !data.connections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Serendipity").font(.headline)
                ForEach(data.connections) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(connectionText(c)).font(.callout)
                        HStack {
                            ForEach(c.people) { p in
                                NavigationLink(value: p.id) {
                                    Text(p.name).font(.caption)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func connectionText(_ c: Connection) -> String {
        let names = c.people.map(\.name)
        if c.you == true, let who = names.first {
            return "You and \(who) both love \(c.label)"
        }
        if names.count >= 2 {
            return "\(names.dropLast().joined(separator: ", ")) and \(names.last!) share \(c.label)"
        }
        return "\(names.first ?? "Someone") · \(c.label)"
    }

    private func load() async {
        guard app.isConfigured else { return }
        loading = true; defer { loading = false }
        do { data = try await app.api.serendipity() }
        catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }
}
