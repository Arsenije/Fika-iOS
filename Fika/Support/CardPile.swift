import SwiftUI

/// One card in the pile — a single question (or a reminder), matching the
/// desktop's `mountStack` items.
struct DeckItem: Identifiable, Equatable {
    let id = UUID()
    var question: String
    var who: String = ""          // subtitle ("Maya", "you · Theo", "you wondered")
    var personName: String = ""   // tag applied to the saved moment
    var personID: String?
    enum Kind: Equatable { case question, reminder, gap }
    var kind: Kind = .question
    var reminderID: String?
    var gapID: String?

    static func == (a: DeckItem, b: DeckItem) -> Bool { a.id == b.id }
}

/// A shuffleable pile of single-question paper cards. Tap the top card to answer
/// it (text + voice); swipe it aside to send it to the back. Mirrors the
/// desktop Home / "Fika's curious" stack.
struct CardPile: View {
    @Binding var items: [DeckItem]
    var emptyText: String = "That's the pile, for now."
    var onSave: (DeckItem, String) async -> Void
    var onReminderDone: (DeckItem) async -> Void = { _ in }
    var onLogLearned: (DeckItem) -> Void = { _ in }

    @State private var drag: CGSize = .zero
    @State private var expanded = false

    private let cardHeight: CGFloat = 300

    var body: some View {
        ZStack {
            if items.isEmpty {
                Text(emptyText)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ForEach(Array(visible.enumerated()).reversed(), id: \.element.id) { idx, item in
                    card(item, depth: idx)
                }
            }
        }
        .frame(height: cardHeight + 90)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: items)
    }

    private var visible: [DeckItem] { Array(items.prefix(4)) }

    @ViewBuilder
    private func card(_ item: DeckItem, depth: Int) -> some View {
        let isTop = depth == 0
        CardFace(
            item: item,
            expanded: isTop && expanded,
            height: cardHeight,
            onToggle: { if isTop { withAnimation { expanded.toggle() } } },
            onSave: { text in Task { await save(item, text) } },
            onReminderDone: { Task { await reminderDone(item) } },
            onLogLearned: { onLogLearned(item); discardTop() }
        )
        .offset(y: CGFloat(depth) * 12)
        .scaleEffect(1 - CGFloat(depth) * 0.045)
        .rotationEffect(.degrees(isTop ? Double(drag.width) * 0.03 : deterministicRotation(item)))
        .offset(x: isTop ? drag.width : 0)
        .opacity(depth >= 3 ? 0 : 1)
        .zIndex(isTop ? 100 : Double(10 - depth))
        .allowsHitTesting(isTop)
        .gesture(isTop && !expanded ? dragGesture : nil)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > 90 {
                    sendToBack(offset: value.translation.width)
                } else {
                    withAnimation(.spring) { drag = .zero }
                }
            }
    }

    private func deterministicRotation(_ item: DeckItem) -> Double {
        Double((abs(item.id.hashValue) % 7) - 3)
    }

    // MARK: mutations

    private func sendToBack(offset: CGFloat) {
        guard !items.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            drag = CGSize(width: offset > 0 ? 500 : -500, height: -20)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            let top = items.removeFirst()
            items.append(top)
            drag = .zero
        }
    }

    private func discardTop() {
        guard !items.isEmpty else { return }
        expanded = false
        withAnimation { _ = items.removeFirst() }
    }

    private func save(_ item: DeckItem, _ text: String) async {
        await onSave(item, text)
        discardTop()
    }

    private func reminderDone(_ item: DeckItem) async {
        await onReminderDone(item)
        discardTop()
    }
}

/// The visual face of a card: question, "who" line, and (when expanded) an
/// answer field + mic, or a reminder's action buttons.
private struct CardFace: View {
    let item: DeckItem
    let expanded: Bool
    let height: CGFloat
    let onToggle: () -> Void
    let onSave: (String) -> Void
    let onReminderDone: () -> Void
    let onLogLearned: () -> Void

    @State private var answer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.kind == .reminder {
                Text("REMINDER").font(.caption2.weight(.bold)).foregroundStyle(.tint).tracking(1)
            }
            Text(item.question)
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            if !item.who.isEmpty {
                Label {
                    Text(item.who).font(.caption).foregroundStyle(.secondary)
                } icon: {
                    if let pid = item.personID {
                        AvatarImage(personID: pid, name: item.personName.isEmpty ? item.who : item.personName, size: 22)
                    } else {
                        Image(systemName: "sparkle").font(.caption2).foregroundStyle(.tint)
                    }
                }
            }

            Spacer(minLength: 0)

            if expanded {
                if item.kind == .reminder {
                    HStack {
                        Button("Mark done", action: onReminderDone).buttonStyle(.borderedProminent)
                        Button("Log what you learned", action: onLogLearned).buttonStyle(.bordered)
                    }
                } else {
                    HStack(alignment: .top, spacing: 6) {
                        TextField("speak, or type…", text: $answer, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                        VoiceButton(text: $answer)
                    }
                    Button("Save") { onSave(answer) }
                        .buttonStyle(.borderedProminent)
                        .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else if item.kind != .reminder {
                Text("tap to answer").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: expanded ? height + 80 : height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemGroupedBackground)) // opaque paper base
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.accentColor.opacity(item.kind == .reminder ? 0.12 : 0))
                )
                .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.05)))
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { onToggle() } }
    }
}
