import SwiftUI

private struct Turn: Identifiable {
    let id = UUID()
    let query: String
    let response: SearchResponse
}

struct SearchView: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var turns: [Turn] = []
    @State private var busy = false
    @State private var error: String?
    @State private var addPrompt: PromptSeed?

    var body: some View {
        NavigationStack {
            Group {
                if !app.isConfigured {
                    NotConfiguredView()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if turns.isEmpty {
                                Text("Ask about your people — “who's into running?”, “when did I last see Maya?”, or “remind me to call Theo.”")
                                    .font(.callout).foregroundStyle(.secondary).padding()
                            }
                            ForEach(turns) { turn in TurnView(turn: turn, addPrompt: $addPrompt) }
                        }
                        .padding(.horizontal)
                    }
                    .navigationDestination(for: String.self) { id in PersonDetailView(personID: id) }
                }
            }
            .navigationTitle("Ask")
            .safeAreaInset(edge: .bottom) { inputBar }
            .sheet(item: $addPrompt, onDismiss: { addPrompt = nil }) { seed in
                NoteComposer(prompt: seed.prompt, people: seed.people)
            }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask Fika…", text: $query, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { Task { await ask() } }
            VoiceButton(text: $query)
            Button { Task { await ask() } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || busy)
        }
        .padding(8)
        .background(.bar)
    }

    private func ask() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        busy = true; defer { busy = false }
        query = ""
        let history: [SearchTurn] = turns.suffix(4).compactMap { turn in
            guard let a = turn.response.answer else { return nil }
            return SearchTurn(q: turn.query, answer: a.answer, people: a.people)
        }
        do {
            let resp = try await app.api.search(q, history: history)
            turns.append(Turn(query: q, response: resp))
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct TurnView: View {
    let turn: Turn
    @Binding var addPrompt: PromptSeed?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.query)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if let answer = turn.response.answer {
                AnswerCard(answer: answer)
            }
            if let card = turn.response.question_card {
                QuestionCardView(card: card) {
                    addPrompt = PromptSeed(prompt: card.question, people: card.people)
                }
            }
            if let reminder = turn.response.reminder {
                Label(reminder.text, systemImage: "bell.fill")
                    .font(.callout)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            if !turn.response.people.isEmpty {
                ForEach(turn.response.people) { p in
                    NavigationLink(value: p.id) { PersonRow(person: p) }
                }
            }
            if !turn.response.notes.isEmpty {
                ForEach(turn.response.notes) { note in
                    Text(note.text).font(.callout).foregroundStyle(.secondary)
                        .padding(8).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct AnswerCard: View {
    let answer: Answer
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(answer.answer)
            if !answer.people.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(answer.people) { p in
                        NavigationLink(value: p.id) {
                            Text(p.name).font(.caption).padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
            if !answer.sources.isEmpty {
                Text("Sources: \(answer.sources.joined(separator: " · "))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct QuestionCardView: View {
    let card: QuestionCard
    let onTeach: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(card.title.isEmpty ? "Teach Fika this" : card.title, systemImage: "lightbulb")
                .font(.headline)
            if !card.hint.isEmpty { Text(card.hint).font(.callout).foregroundStyle(.secondary) }
            Button("Add what you know", action: onTeach)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PromptSeed: Identifiable {
    let id = UUID()
    let prompt: String
    let people: [String]
}
