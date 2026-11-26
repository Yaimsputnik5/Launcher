import SwiftUI

struct StatusBadge: View {
    let status: ServerStatus?

    private var label: String {
        guard let status else { return "Unknown" }
        if !status.online { return "Offline" }
        return status.joining ? "Joining" : "Online"
    }

    private var color: Color {
        guard let status else { return .gray }
        if !status.online { return .red }
        return status.joining ? .orange : .green
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
        .allowsHitTesting(false)
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
                StatusBadge(status: runtime.status)
            }
            Text(runtime.info.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !runtime.statusMessage.isEmpty {
                Text(runtime.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(runtime.lastError == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct InsecureEndpointWarning: View {
    var body: some View {
        Label(
            "This server uses HTTP. Your username and password are not encrypted in transit.",
            systemImage: "exclamationmark.shield"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
    }
}
