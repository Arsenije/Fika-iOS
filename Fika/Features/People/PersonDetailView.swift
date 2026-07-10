import SwiftUI
import PhotosUI

struct PersonDetailView: View {
    @Environment(AppState.self) private var app
    let personID: String

    @State private var detail: PersonDetail?
    @State private var curio: [DeckItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var photo: PhotosPickerItem?
    @State private var showAddMoment = false
    @State private var showReminder = false
    @State private var reminderText = ""

    var body: some View {
        List {
            if let d = detail {
                header(d)
                if !d.profile.isEmpty { Section("Profile") { Text(d.profile) } }
                remindersSection(d)
                curiousSection(d)
                actionsSection(d)
                timelineSection(d)
                interestsSection(d)
                relatedSection(d)
            }
        }
        .navigationTitle(detail?.name ?? "Person")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .overlay { if loading && detail == nil { ProgressView() } }
        .onChange(of: photo) { _, item in Task { await upload(item) } }
        .sheet(isPresented: $showAddMoment, onDismiss: { Task { await load() } }) {
            NoteComposer(people: detail.map { [$0.name] } ?? [])
        }
        .alert("Remind me…", isPresented: $showReminder) {
            TextField("e.g. ask about her studio", text: $reminderText)
            Button("Cancel", role: .cancel) { reminderText = "" }
            Button("Add") { Task { await addReminder() } }
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    // MARK: sections

    @ViewBuilder private func header(_ d: PersonDetail) -> some View {
        Section {
            HStack(spacing: 14) {
                AvatarImage(personID: d.id, name: d.name, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    if !d.relationship.isEmpty {
                        Text(d.relationship).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("Last moment \(RelativeTime.phrase(days: d.days_since))")
                        .font(.caption).foregroundStyle(.secondary)
                    PhotosPicker(selection: $photo, matching: .images) {
                        Text(d.has_avatar ? "Change photo" : "Add photo").font(.caption)
                    }
                }
                Spacer()
            }
            if !d.tags.isEmpty { Chips(items: d.tags) }
        }
    }

    @ViewBuilder private func curiousSection(_ d: PersonDetail) -> some View {
        Section("Fika's curious") {
            if curio.isEmpty {
                Text("Thinking of what to ask…").font(.callout).foregroundStyle(.secondary)
            } else {
                CardPile(items: $curio, emptyText: "Nothing else comes to mind yet.") { item, text in
                    await saveMoment(text: text, prompt: item.question)
                }
                .listRowInsets(EdgeInsets())
            }
        }
    }

    @ViewBuilder private func actionsSection(_ d: PersonDetail) -> some View {
        Section {
            Button { showAddMoment = true } label: { Label("Log a moment", systemImage: "square.and.pencil") }
            Button { showReminder = true } label: { Label("Remind me…", systemImage: "bell") }
        }
    }

    @ViewBuilder private func interestsSection(_ d: PersonDetail) -> some View {
        if !d.interests.isEmpty || !d.places.isEmpty || !d.organizations.isEmpty || !d.events.isEmpty {
            Section("What matters to them") {
                if !d.interests.isEmpty { Chips(items: d.interests, systemImage: "heart") }
                if !d.places.isEmpty { Chips(items: d.places, systemImage: "mappin") }
                if !d.organizations.isEmpty { Chips(items: d.organizations, systemImage: "building.2") }
                if !d.events.isEmpty { Chips(items: d.events, systemImage: "calendar") }
            }
        }
    }

    @ViewBuilder private func relatedSection(_ d: PersonDetail) -> some View {
        if !d.related_people.isEmpty {
            Section("Connected people") {
                ForEach(d.related_people) { rp in
                    NavigationLink(value: rp.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rp.name)
                            if !rp.shared.isEmpty {
                                Text("shares \(rp.shared.joined(separator: ", "))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func remindersSection(_ d: PersonDetail) -> some View {
        if !d.reminders.isEmpty {
            Section("Reminders") {
                ForEach(d.reminders) { r in
                    HStack {
                        Text(r.text)
                        Spacer()
                        Button { Task { await complete(r) } } label: { Image(systemName: "checkmark.circle") }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    @ViewBuilder private func timelineSection(_ d: PersonDetail) -> some View {
        if !d.timeline.isEmpty {
            Section("Moments") {
                ForEach(d.timeline) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        if let p = note.prompt, !p.isEmpty {
                            Text(p).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(note.text)
                        Text(RelativeTime.shortDate(note.occurred_at)).font(.caption2).foregroundStyle(.tertiary)
                    }.padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: actions

    private func load() async {
        loading = true; defer { loading = false }
        do {
            detail = try await app.api.person(personID)
            if curio.isEmpty, let qs = try? await app.api.enrichQuestions(personID: personID) {
                curio = qs.map { DeckItem(question: $0, personName: detail?.name ?? "", personID: personID) }
            }
        } catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }
    private func saveMoment(text: String, prompt: String) async {
        do {
            _ = try await app.api.createNote(text: text, people: detail.map { [$0.name] } ?? [], prompt: prompt)
            await load()
        } catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }
    private func addReminder() async {
        let text = reminderText.trimmingCharacters(in: .whitespaces)
        reminderText = ""
        guard !text.isEmpty, let d = detail else { return }
        _ = try? await app.api.createReminder(text: text, personID: d.id, personName: d.name)
        await load()
    }
    private func complete(_ r: Reminder) async {
        try? await app.api.completeReminder(r.id)
        await load()
    }
    private func upload(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        do { try await app.api.uploadAvatar(personID: personID, imageData: data); await load() }
        catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }
}
