import SwiftUI

/// Log a "moment". Optionally pre-tagged to people and framed by a prompt
/// (e.g. an enrichment/curio question shown above the answer on a profile).
struct NoteComposer: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var prompt: String = ""
    var people: [String] = []
    var heading: String = "New moment"
    var onSaved: () -> Void = {}

    @State private var text = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if !prompt.isEmpty {
                    Section { Text(prompt).font(.callout).foregroundStyle(.secondary) }
                }
                Section {
                    HStack(alignment: .top) {
                        TextEditor(text: $text).frame(minHeight: 140)
                        VoiceButton(text: $text)
                    }
                } header: {
                    Text(people.isEmpty ? "What happened?" : "About \(people.joined(separator: ", "))")
                }
            }
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        do {
            _ = try await app.api.createNote(text: text, people: people, prompt: prompt)
            onSaved()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
