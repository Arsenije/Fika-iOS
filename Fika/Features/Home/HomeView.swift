import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app

    @State private var items: [DeckItem] = []
    @State private var people: [Person] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showAddPerson = false
    @State private var quickNote: NoteSeed?

    var body: some View {
        NavigationStack {
            Group {
                if !app.isConfigured {
                    NotConfiguredView()
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            pile
                            peopleStrip
                        }
                        .padding(.vertical, 12)
                    }
                    .navigationDestination(for: String.self) { id in PersonDetailView(personID: id) }
                }
            }
            .navigationTitle("Fika")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { quickNote = NoteSeed() } label: { Image(systemName: "square.and.pencil") }
                        .disabled(!app.isConfigured)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .overlay { if loading && items.isEmpty { ProgressView() } }
            .sheet(isPresented: $showAddPerson, onDismiss: { Task { await load() } }) { AddPersonView() }
            .sheet(item: $quickNote, onDismiss: { quickNote = nil }) { seed in
                NoteComposer(prompt: seed.prompt, people: seed.people, heading: seed.heading)
            }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var pile: some View {
        VStack(spacing: 8) {
            CardPile(
                items: $items,
                emptyText: people.isEmpty
                    ? "Add people and log a few moments — ideas will pile up here."
                    : "That's the pile, for now.",
                onSave: saveAnswer,
                onReminderDone: markReminderDone,
                onLogLearned: { item in
                    quickNote = NoteSeed(people: item.personName.isEmpty ? [] : [item.personName],
                                         heading: "Log what you learned", prompt: "What did you find out?")
                }
            )
            HStack(spacing: 22) {
                Button { quickNote = NoteSeed() } label: {
                    Image(systemName: "pencil.line").font(.title2)
                }
                Button { shuffle() } label: {
                    Image(systemName: "shuffle.circle").font(.title2)
                }
                .disabled(items.count < 2)
            }
            .foregroundStyle(.tint)
            .padding(.top, 2)
        }
    }

    private var peopleStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(people) { p in
                    NavigationLink(value: p.id) {
                        VStack(spacing: 5) {
                            AvatarImage(personID: p.id, name: p.name, size: 54)
                            Text(firstName(p.name)).font(.caption2).lineLimit(1)
                        }.frame(width: 68)
                    }.buttonStyle(.plain)
                }
                Button { showAddPerson = true } label: {
                    VStack(spacing: 5) {
                        Circle().strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                            .frame(width: 54, height: 54)
                        Text("Add").font(.caption2).foregroundStyle(.secondary)
                    }.frame(width: 68)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }

    // MARK: data

    private func load() async {
        guard app.isConfigured else { return }
        loading = true; defer { loading = false }
        do {
            async let peopleR = app.api.people()
            async let serR = app.api.serendipity()
            async let memR = try? app.api.memory()
            async let remR = try? app.api.reminders()

            let ppl = try await peopleR
            let ser = try await serR
            let mem = await memR ?? MemoryState()
            let rem = await remR ?? []
            people = ppl

            var deck: [DeckItem] = []
            deck += rem.map { r in
                DeckItem(question: r.text, who: r.person_name, personName: r.person_name,
                         personID: r.person_id.isEmpty ? nil : r.person_id, kind: .reminder, reminderID: r.id)
            }
            deck += mem.gaps.map { DeckItem(question: $0.q, who: "you wondered", kind: .gap, gapID: $0.id) }
            deck += fastDeck(ser)
            items = deck

            await loadEnrichment(people: ppl, counts: mem.counts)
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Instant, no-LLM cards straight from /serendipity (matches desktop fastDeck).
    private func fastDeck(_ ser: Serendipity) -> [DeckItem] {
        var out: [DeckItem] = []
        for p in ser.reconnect.prefix(4) {
            let gap = gapPhrase(p.days_since)
            let q = gap.isEmpty
                ? "What's something you'd love to remember about \(firstName(p.name))?"
                : "It's been \(gap) since you and \(firstName(p.name)) — what have they been up to?"
            out.append(DeckItem(question: q, who: p.name, personName: p.name, personID: p.id))
        }
        for c in ser.connections.prefix(2) {
            let names = c.people.map(\.name)
            if c.you == true, let first = names.first {
                out.append(DeckItem(question: "You and \(firstName(first)) both love \(c.label).",
                                    who: "you · \(first)", personName: first, personID: c.people.first?.id))
            } else if names.count >= 2 {
                out.append(DeckItem(question: "\(names[0]) and \(names[1]) both love \(c.label). Worth introducing them?",
                                    who: names.joined(separator: " · "), personName: names[0], personID: c.people.first?.id))
            }
        }
        return out
    }

    /// Serendipitous questions across many people, streamed in and appended,
    /// biased toward people you look up most (matches desktop loadEnrichment).
    private func loadEnrichment(people: [Person], counts: [String: Int]) async {
        let picks = people.sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }.prefix(12)
        for p in picks {
            guard let qs = try? await app.api.enrichQuestions(personID: p.id) else { continue }
            let new = qs.map { DeckItem(question: $0, who: p.name, personName: p.name, personID: p.id) }
            items.append(contentsOf: new)
        }
    }

    private func shuffle() {
        guard items.count > 1 else { return }
        let top = items.removeFirst()
        items.shuffle()
        items.append(top)   // send current top to the back, surface a random next
    }

    private func saveAnswer(_ item: DeckItem, _ text: String) async {
        do {
            _ = try await app.api.createNote(text: text,
                                             people: item.personName.isEmpty ? [] : [item.personName],
                                             prompt: item.question)
            if let gid = item.gapID { try? await app.api.closeGap(gid) }
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func markReminderDone(_ item: DeckItem) async {
        if let rid = item.reminderID { try? await app.api.completeReminder(rid) }
    }
}

/// Seed for the quick-note / log sheet.
struct NoteSeed: Identifiable {
    let id = UUID()
    var people: [String] = []
    var heading: String = "Quick note"
    var prompt: String = ""
}

// MARK: shared helpers

func firstName(_ name: String) -> String {
    name.split(separator: " ").first.map(String.init) ?? name
}

/// Days-since as a bare phrase for "It's been X since…" (no trailing "ago").
func gapPhrase(_ days: Int?) -> String {
    guard let days else { return "" }
    switch days {
    case ..<1: return ""
    case 1: return "a day"
    case ..<14: return "\(days) days"
    case ..<60: return "\(max(2, Int((Double(days) / 7).rounded()))) weeks"
    case ..<365: return "\(max(2, Int((Double(days) / 30).rounded()))) months"
    default: return "over a year"
    }
}
