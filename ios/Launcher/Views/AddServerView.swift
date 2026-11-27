import SwiftUI

struct AddServerView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var urlString = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var pendingInsecureURL: String?
    @State private var confirmedInsecureURL: String?

    private var normalizedURL: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var needsInsecureConfirmation: Bool {
        guard let url = URL(string: normalizedURL) else { return false }
        return URLHelper.requiresInsecureTransportWarning(for: url)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://server.example.com", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server URL")
                } footer: {
                    Text("The launcher fetches servermanifest.xml from this address.")
                }

                if needsInsecureConfirmation {
                    Section {
                        Label(
                            "This server uses plain HTTP. Manifest and download traffic will not be encrypted. Passwords are still refused unless the Web API uses HTTPS or loopback.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .alert(
                "Add a plain HTTP server?",
                isPresented: Binding(
                    get: { pendingInsecureURL != nil },
                    set: { if !$0 { pendingInsecureURL = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { pendingInsecureURL = nil }
                Button("Add Anyway", role: .destructive) {
                    confirmedInsecureURL = pendingInsecureURL
                    pendingInsecureURL = nil
                    Task { await performAdd() }
                }
            } message: {
                Text("Manifest and client downloads for \(pendingInsecureURL ?? "") will be sent over unencrypted HTTP. Login credentials remain restricted to HTTPS or loopback.")
            }
            .navigationTitle("Add Server")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        Task { await add() }
                    }
                    .disabled(busy || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if busy {
                    ProgressView("Fetching manifest…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func add() async {
        if needsInsecureConfirmation, confirmedInsecureURL != normalizedURL {
            pendingInsecureURL = normalizedURL
            return
        }
        await performAdd()
    }

    private func performAdd() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await state.addServer(urlString: normalizedURL)
            confirmedInsecureURL = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
