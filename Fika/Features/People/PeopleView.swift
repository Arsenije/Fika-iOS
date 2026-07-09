import SwiftUI

struct PeopleView: View {
    @Environment(AppState.self) private var app
    @State private var people: [Person] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if !app.isConfigured {
                    NotConfiguredView()
                } else if people.isEmpty && !loading {
                    ContentUnavailableView("No people yet", systemImage: "person.crop.circle.badge.plus",
                                           description: Text("Tap + to add someone you care about."))
                } else {
                    List(people) { person in
                        NavigationLink(value: person.id) {
                            PersonRow(person: person)
                        }
                    }
                    .navigationDestination(for: String.self) { id in
                        PersonDetailView(personID: id)
                    }
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .disabled(!app.isConfigured)
                }
            }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
                AddPersonView()
            }
            .task { await load() }
            .refreshable { await load() }
            .overlay { if loading && people.isEmpty { ProgressView() } }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func load() async {
        guard app.isConfigured else { return }
        loading = true; defer { loading = false }
        do { people = try await app.api.people() }
        catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }
}

struct PersonRow: View {
    let person: Person
    var body: some View {
        HStack(spacing: 12) {
            AvatarImage(personID: person.id, name: person.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if !person.relationship.isEmpty {
                        Text(person.relationship).font(.caption).foregroundStyle(.secondary)
                    }
                    if person.days_since != nil {
                        Text("· last seen \(RelativeTime.phrase(days: person.days_since))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
