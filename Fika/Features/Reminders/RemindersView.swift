import SwiftUI

struct RemindersView: View {
    @Environment(AppState.self) private var app
    @State private var reminders: [Reminder] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showAdd = false
    @State private var newText = ""
    @State private var newPerson = ""

    var body: some View {
        NavigationStack {
            Group {
                if !app.isConfigured {
                    NotConfiguredView()
                } else if reminders.isEmpty && !loading {
                    ContentUnavailableView("No reminders", systemImage: "bell.slash",
                                           description: Text("Add a nudge, or say “remind me to…” in Ask."))
                } else {
                    List {
                        ForEach(reminders) { r in
                            HStack(alignment: .top) {
                                Button { Task { await complete(r) } } label: {
                                    Image(systemName: "circle")
                                }.buttonStyle(.borderless)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.text)
                                    if !r.person_name.isEmpty {
                                        Text(r.person_name).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reminders")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .disabled(!app.isConfigured)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .alert("New reminder", isPresented: $showAdd) {
                TextField("Reminder", text: $newText)
                TextField("About whom (optional)", text: $newPerson)
                Button("Cancel", role: .cancel) { newText = ""; newPerson = "" }
                Button("Add") { Task { await add() } }
            }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func load() async {
        guard app.isConfigured else { return }
        loading = true; defer { loading = false }
        do { reminders = try await app.api.reminders() }
        catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }
    private func add() async {
        let text = newText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let person = newPerson.trimmingCharacters(in: .whitespaces)
        newText = ""; newPerson = ""
        do {
            _ = try await app.api.createReminder(text: text, personName: person)
            await load()
        } catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }
    private func complete(_ r: Reminder) async {
        try? await app.api.completeReminder(r.id)
        await load()
    }
}
