import SwiftUI

struct AddPersonView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case basics, details }
    @State private var phase: Phase = .basics

    @State private var name = ""
    @State private var relationship = ""

    // Two fixed anchors + LLM-tailored questions in between (from /intake).
    private let anchors = ["What lights them up?", "How did you two meet?"]
    @State private var questions: [String] = []
    @State private var answers: [String: String] = [:]
    @State private var threeWords = ""

    @State private var loading = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                switch phase {
                case .basics:
                    Section("Who is this?") {
                        TextField("Name", text: $name)
                        TextField("How you know them (e.g. old friend, sister)", text: $relationship)
                    }
                    Section {
                        Button { Task { await toDetails() } } label: {
                            HStack { Text("Continue"); if loading { Spacer(); ProgressView() } }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                    }
                case .details:
                    ForEach(allQuestions, id: \.self) { q in
                        Section(q) {
                            HStack(alignment: .top) {
                                TextField("In your own words…", text: binding(for: q), axis: .vertical)
                                    .lineLimit(1...5)
                                VoiceButton(text: binding(for: q))
                            }
                        }
                    }
                    Section("Three words that capture them") {
                        TextField("kind, funny, stubborn", text: $threeWords)
                    }
                }
            }
            .navigationTitle("Add a person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if phase == .details {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .disabled(saving)
                    }
                }
            }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var allQuestions: [String] { anchors + questions }

    private func binding(for q: String) -> Binding<String> {
        Binding(get: { answers[q] ?? "" }, set: { answers[q] = $0 })
    }

    private func toDetails() async {
        loading = true; defer { loading = false }
        // Intake questions are a nicety; if the call fails we still proceed with anchors.
        questions = (try? await app.api.intakeQuestions(name: name, relationship: relationship)) ?? []
        phase = .details
    }

    private func save() async {
        saving = true; defer { saving = false }
        var parts: [String] = []
        for q in allQuestions {
            let a = (answers[q] ?? "").trimmingCharacters(in: .whitespaces)
            if !a.isEmpty { parts.append("\(q)\n\(a)") }
        }
        let words = threeWords.trimmingCharacters(in: .whitespaces)
        if !words.isEmpty { parts.append("In three words: \(words)") }
        let profile = parts.joined(separator: "\n\n")

        let tags = words.split(whereSeparator: { $0 == "," || $0 == " " }).map { String($0) }.filter { !$0.isEmpty }
        do {
            _ = try await app.api.createPerson(name: name, relationship: relationship, profile: profile, tags: tags)
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
