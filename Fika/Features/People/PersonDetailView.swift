import SwiftUI
import PhotosUI

struct PersonDetailView: View {
    @Environment(AppState.self) private var app
    let personID: String

    @State private var detail: PersonDetail?
    @State private var loading = false
    @State private var error: String?
    @State private var photo: PhotosPickerItem?
    @State private var showAddMoment = false
    @State private var enrichQuestions: [String] = []
    @State private var activePrompt: String?

    var body: some View {
        List {
            if let detail {
                header(detail)
                if !detail.profile.isEmpty {
                    Section("Profile") { Text(detail.profile) }
                }
                interestsSection(detail)
                relatedSection(detail)
                remindersSection(detail)
                enrichSection(detail)
                timelineSection(detail)
            }
        }
        .navigationTitle(detail?.name ?? "Person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddMoment = true } label: { Image(systemName: "square.and.pencil") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .overlay { if loading && detail == nil { ProgressView() } }
        .onChange(of: photo) { _, item in Task { await upload(item) } }
        .sheet(isPresented: $showAddMoment, onDismiss: { Task { await load() } }) {
            NoteComposer(people: detail.map { [$0.name] } ?? [])
        }
        .sheet(item: Binding(get: { activePrompt.map(PromptWrapper.init) },
                             set: { activePrompt = $0?.text })) { wrapped in
            NoteComposer(prompt: wrapped.text, people: detail.map { [$0.name] } ?? [],
                         onSaved: { Task { await load() } })
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
                    Text("Last seen \(RelativeTime.phrase(days: d.days_since))")
                        .font(.caption).foregroundStyle(.secondary)
                    PhotosPicker(selection: $photo, matching: .images) {
                        Text(d.has_avatar ? "Change photo" : "Add photo").font(.caption)
                    }
                }
                Spacer()
            }
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
            Section("Might connect with") {
                ForEach(d.related_people) { rp in
                    NavigationLink(value: rp.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rp.name)
                            if !rp.shared.isEmpty {
                                Text("both: \(rp.shared.joined(separator: ", "))")
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
                        Button { Task { await complete(r) } } label: {
                            Image(systemName: "checkmark.circle")
                        }.buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    @ViewBuilder private func enrichSection(_ d: PersonDetail) -> some View {
        Section("Tell Fika more") {
            if enrichQuestions.isEmpty {
                Button("Suggest questions") { Task { await loadEnrich() } }
            } else {
                ForEach(enrichQuestions, id: \.self) { q in
                    Button { activePrompt = q } label: {
                        HStack { Text(q); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
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
        do { detail = try await app.api.person(personID) }
        catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }
    private func loadEnrich() async {
        do { enrichQuestions = try await app.api.enrichQuestions(personID: personID) }
        catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }
    private func complete(_ r: Reminder) async {
        try? await app.api.completeReminder(r.id)
        await load()
    }
    private func upload(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        do {
            try await app.api.uploadAvatar(personID: personID, imageData: data)
            await load()
        } catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }
}

/// Identifiable wrapper so a String prompt can drive a `.sheet(item:)`.
private struct PromptWrapper: Identifiable {
    let text: String
    var id: String { text }
}
