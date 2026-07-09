import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var usage: Usage?
    @State private var me = Me()
    @State private var memory = MemoryState()
    @State private var meLoaded = false

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            Form {
                Section("Your Mac") {
                    TextField("IP address (e.g. 192.168.1.4)", text: $settings.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Port", value: $settings.port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    TextField("Token (optional)", text: $settings.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Test connection") { Task { await app.checkHealth() } }
                    connectionRow
                }

                if let usage {
                    Section("OpenAI usage") {
                        LabeledContent("Estimated cost", value: String(format: "$%.4f", usage.cost_usd))
                        LabeledContent("People", value: "\(usage.people)")
                        LabeledContent("Moments", value: "\(usage.notes)")
                    }
                }

                Section("You") {
                    TextEditor(text: $me.profile)
                        .frame(minHeight: 90)
                    if !me.interests.isEmpty { Chips(items: me.interests, systemImage: "heart") }
                    Button("Save profile") { Task { await saveMe() } }
                        .disabled(me.profile.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Your own note about yourself powers “you both love X” connections.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Memory") {
                    Toggle("Remember my questions", isOn: Binding(
                        get: { memory.enabled },
                        set: { v in Task { await setMemory(v) } }
                    ))
                    if !memory.gaps.isEmpty {
                        ForEach(memory.gaps) { gap in Text(gap.q).font(.callout) }
                        Button("Clear", role: .destructive) { Task { await clearMemory() } }
                    }
                }

                Section {
                    Link("Fika on GitHub", destination: URL(string: "https://github.com/Arsenije/Fika")!)
                }
            }
            .navigationTitle("Settings")
            .task { await loadAll() }
            .refreshable { await loadAll() }
        }
    }

    @ViewBuilder private var connectionRow: some View {
        switch app.connection {
        case .unknown:
            Label("Not tested", systemImage: "circle").foregroundStyle(.secondary)
        case .connecting:
            HStack { ProgressView(); Text("Connecting…") }
        case .ok(let hasKey):
            VStack(alignment: .leading, spacing: 2) {
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                if !hasKey {
                    Text("No OpenAI key on the server — add it in the desktop app.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(.red).font(.callout)
        }
    }

    private func loadAll() async {
        await app.checkHealth()
        guard app.isConfigured else { return }
        usage = try? await app.api.usage()
        memory = (try? await app.api.memory()) ?? memory
        if !meLoaded, let loaded = try? await app.api.me() { me = loaded; meLoaded = true }
    }

    private func saveMe() async {
        try? await app.api.setMe(profile: me.profile)
        if let loaded = try? await app.api.me() { me = loaded }
    }
    private func setMemory(_ v: Bool) async {
        try? await app.api.setMemoryEnabled(v)
        memory = (try? await app.api.memory()) ?? memory
    }
    private func clearMemory() async {
        try? await app.api.clearMemory()
        memory = (try? await app.api.memory()) ?? memory
    }
}
