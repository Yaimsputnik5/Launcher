import SwiftUI

struct StatusBadge: View {
    let state: ServerPresentationState

    private var label: String {
        switch state {
        case .unknown: return "Unknown"
        case .refreshing: return "Refreshing"
        case .online: return "Online"
        case .locked: return "Locked"
        case .offline: return "Offline"
        case .unsupported: return "Unsupported"
        case .error: return "Error"
        }
    }

    private var color: Color {
        switch state {
        case .unknown, .refreshing: return .yellow
        case .online: return .green
        case .locked, .offline, .error: return .red
        case .unsupported: return .orange
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("Server status: \(label)")
    }
}

struct NoticeOverlay: View {
    let notices: [AppNotice]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(notices) { notice in
                HStack(spacing: 8) {
                    Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    Text(notice.message)
                        .font(.footnote)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(notice.isError ? Color.red.opacity(0.5) : Color.secondary.opacity(0.25))
                }
            }
        }
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct ServerRow: View {
    @ObservedObject var runtime: ServerRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(runtime.info.name)
                    .font(.headline)
                Spacer()
                StatusBadge(state: runtime.presentationState)
            }
            Text(runtime.info.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !runtime.statusText.isEmpty {
                Text(runtime.statusText)
                    .font(.caption2)
                    .foregroundStyle(runtime.presentationState == .error ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct InsecureEndpointWarning: View {
    var body: some View {
        Label(
            "This endpoint does not use HTTPS. Your username and password are not encrypted in transit.",
            systemImage: "exclamationmark.shield"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
    }
}

/// The C# launcher warns for any API scheme that is not HTTPS.
func isInsecureEndpoint(_ value: String) -> Bool {
    guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased() else {
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return scheme != "https"
}
