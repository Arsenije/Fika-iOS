import SwiftUI
import UIKit

// MARK: - Avatar (token-aware; AsyncImage can't send the X-Fika-Token header)

struct AvatarImage: View {
    @Environment(AppState.self) private var app
    let personID: String
    let name: String
    var size: CGFloat = 44

    @State private var image: UIImage?
    @State private var tried = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                InitialsCircle(name: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: personID) { await load() }
    }

    private func load() async {
        guard !tried, let url = app.api.avatarURL(personID: personID) else { return }
        tried = true
        var req = URLRequest(url: url)
        let tok = app.settings.token.trimmingCharacters(in: .whitespaces)
        if !tok.isEmpty { req.setValue(tok, forHTTPHeaderField: "X-Fika-Token") }
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let img = UIImage(data: data) {
            image = img
        }
    }
}

struct InitialsCircle: View {
    let name: String
    var size: CGFloat = 44
    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.18))
            .overlay(Text(initials).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.tint))
            .frame(width: size, height: size)
    }
}

// MARK: - Chips

struct Chips: View {
    let items: [String]
    var systemImage: String?
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    if let systemImage { Image(systemName: systemImage).font(.caption2) }
                    Text(item).font(.caption)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }
}

/// Minimal wrapping layout for chips (avoids a LazyVGrid's fixed columns).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.minX + maxWidth { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

// MARK: - Not-configured prompt

struct NotConfiguredView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Not connected", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Open Settings and enter your Mac's address (e.g. 192.168.1.4:8765) while Fika is running there.")
        }
    }
}

// MARK: - Helpers

enum RelativeTime {
    /// Mirrors the sidecar's _gap_phrase for days-since values.
    static func phrase(days: Int?) -> String {
        guard let days else { return "a while ago" }
        switch days {
        case 0: return "earlier today"
        case 1: return "yesterday"
        case ..<14: return "\(days) days ago"
        case ..<60: return "about \(max(2, Int((Double(days) / 7).rounded()))) weeks ago"
        case ..<365: return "about \(max(2, Int((Double(days) / 30).rounded()))) months ago"
        default: return "over a year ago"
        }
    }

    static func shortDate(_ iso: String?) -> String {
        guard let iso else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return String(iso.prefix(10)) }
        let out = DateFormatter()
        out.dateStyle = .medium
        return out.string(from: date)
    }
}
