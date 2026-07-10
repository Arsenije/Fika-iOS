import SwiftUI

/// One screen in the add-a-person conversation.
private struct FlowScreen: Identifiable {
    let key: String
    let question: String
    var sub: String = ""
    var placeholder: String = ""
    var multiline: Bool = true
    var required: Bool = false
    /// How this answer reads in the composed profile (nil = not written).
    var line: ((String) -> String)? = nil
    var id: String { key }
}

/// Full-screen, voice-first conversational flow: name → relationship → tailored
/// questions (bracketed by two anchors) → three words. Mirrors the desktop
/// `startPersonFlow`. Every answer stays in the user's own words.
struct AddPersonView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    // Fixed screens; the tailored middle is spliced in after the relationship.
    private let nameScreen = FlowScreen(key: "name", question: "Who are we adding?",
        sub: "Their name — first, full, or whatever you call them.", placeholder: "Maya Lindqvist",
        multiline: false, required: true)
    private let relScreen = FlowScreen(key: "relationship", question: "What are they to you?",
        sub: "brother · childhood friend · the coworker you actually like", placeholder: "my younger brother",
        multiline: false)
    private let passions = FlowScreen(key: "passions", question: "What lights them up?",
        sub: "What could they talk about for hours?",
        placeholder: "rock climbing · natural wine · Studio Ghibli",
        line: { "Could talk for hours about: \($0)" })
    private let howMet = FlowScreen(key: "how_met", question: "How did your paths first cross?",
        sub: "The origin story, however small.",
        placeholder: "We sat next to each other on a delayed flight and never stopped talking.",
        line: { "How we met: \($0)" })
    private let words = FlowScreen(key: "words", question: "Three words that capture them",
        sub: "They become little tags on their card. Optional, but fun.",
        placeholder: "warm, stubborn, hilarious", multiline: false)

    private let fallback: [FlowScreen] = [
        FlowScreen(key: "places", question: "Where do they feel most themselves?",
            sub: "A city, a corner, a kind of place.", placeholder: "Lisbon · their grandmother's kitchen",
            line: { "Feels most at home: \($0)" }),
        FlowScreen(key: "pursuits", question: "What are they chasing right now?",
            sub: "A goal, a project, a season of life.", placeholder: "opening her ceramics studio",
            line: { "Lately, they're chasing: \($0)" }),
        FlowScreen(key: "detail", question: "What's a small thing that's so them?",
            sub: "A quirk, a tell, a ritual.", placeholder: "always replies in voice notes",
            line: { "So them: \($0)" }),
    ]

    @State private var screens: [FlowScreen] = []
    @State private var built = false
    @State private var index = 0
    @State private var answers: [String: String] = [:]
    @State private var current = ""
    @State private var generating = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ProgressView(value: progress).tint(.accentColor).padding()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(history) { pair in
                            bubble(pair.q, ask: true)
                            if !pair.a.isEmpty { bubble(pair.a, ask: false) }
                        }
                        if generating {
                            bubble("Let me think of a few good questions about your \(answers["relationship"] ?? "friend")…", ask: true)
                        } else if let s = active {
                            bubble(s.question + (s.sub.isEmpty ? "" : "\n\(s.sub)"), ask: true)
                        }
                    }
                    .padding(.horizontal)
                }

                if let s = active, !generating {
                    Divider()
                    VStack(spacing: 10) {
                        HStack(alignment: .top, spacing: 6) {
                            if s.multiline {
                                TextField(s.placeholder, text: $current, axis: .vertical)
                                    .textFieldStyle(.roundedBorder).lineLimit(1...5)
                            } else {
                                TextField(s.placeholder, text: $current)
                                    .textFieldStyle(.roundedBorder)
                            }
                            if s.key != "name" { VoiceButton(text: $current) }
                        }
                        HStack {
                            if index > 0 { Button("↑ Back") { back() }.buttonStyle(.borderless) }
                            Spacer()
                            Button(isLast ? "Add \(answers["name"] ?? "them")" : "Next") { Task { await advance() } }
                                .buttonStyle(.borderedProminent)
                                .disabled(saving)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Add a person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .onAppear { if screens.isEmpty { screens = [nameScreen, relScreen] } }
        }
    }

    // MARK: derived

    private var active: FlowScreen? { screens.indices.contains(index) ? screens[index] : nil }
    private var isLast: Bool { built && index == screens.count - 1 }
    private var progress: Double {
        let total = built ? Double(screens.count) : 8
        return min(1, Double(index) / max(1, total - 1))
    }
    private struct QA: Identifiable { let id = UUID(); let q: String; let a: String }
    private var history: [QA] {
        screens.prefix(index).map { QA(q: $0.question, a: answers[$0.key] ?? "") }
    }

    @ViewBuilder private func bubble(_ text: String, ask: Bool) -> some View {
        Text(text)
            .font(ask ? .headline : .body)
            .padding(12)
            .background(ask ? Color.secondary.opacity(0.10) : Color.accentColor.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: .infinity, alignment: ask ? .leading : .trailing)
    }

    // MARK: steps

    private func back() {
        capture()
        index = max(0, index - 1)
        current = answers[active?.key ?? ""] ?? ""
    }

    private func capture() {
        if let key = active?.key { answers[key] = current.trimmingCharacters(in: .whitespaces) }
    }

    private func advance() async {
        capture()
        guard let s = active else { return }
        if s.required && (answers[s.key] ?? "").isEmpty { error = "A name, at least."; return }

        // After the relationship, fetch the tailored middle questions.
        if s.key == "relationship" && !built {
            await generateThenContinue()
            return
        }
        if index < screens.count - 1 {
            index += 1
            current = answers[active?.key ?? ""] ?? ""
        } else {
            await submit()
        }
    }

    private func generateThenContinue() async {
        generating = true
        var middle = fallback
        if let qs = try? await app.api.intakeQuestions(name: answers["name"] ?? "",
                                                        relationship: answers["relationship"] ?? ""), !qs.isEmpty {
            middle = qs.map { q in
                FlowScreen(key: q.key, question: q.q, sub: q.sub, placeholder: q.ph,
                           line: { "\(q.label.isEmpty ? "Note" : q.label): \($0)" })
            }
        }
        screens = [nameScreen, relScreen, passions, howMet] + middle + [words]
        built = true
        generating = false
        index = 2
        current = ""
    }

    private func composeProfile() -> String {
        var lines: [String] = []
        let name = answers["name"] ?? ""
        if let rel = answers["relationship"], !rel.isEmpty { lines.append("\(name) — \(rel).") }
        for s in screens {
            guard let make = s.line, let v = answers[s.key], !v.isEmpty else { continue }
            lines.append(make(v))
        }
        return lines.joined(separator: "\n")
    }

    private func submit() async {
        saving = true; defer { saving = false }
        let name = answers["name"] ?? ""
        let tags = (answers["words"] ?? "")
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(5)
        do {
            _ = try await app.api.createPerson(name: name, relationship: answers["relationship"] ?? "",
                                               profile: composeProfile(), tags: Array(tags))
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
