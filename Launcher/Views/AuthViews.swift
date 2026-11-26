import SwiftUI

struct LoginView: View {
    @ObservedObject var runtime: ServerRuntime
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var username: String
    @State private var password: String
    @State private var rememberUsername: Bool
    @State private var rememberPassword: Bool
    @State private var showingRegister = false
    @State private var busy = false
    @State private var errorMessage: String?

    init(runtime: ServerRuntime) {
        self.runtime = runtime
        _username = State(initialValue: runtime.info.username)
        _password = State(initialValue: CredentialStore.shared.password(for: runtime.info.id) ?? "")
        _rememberUsername = State(initialValue: runtime.info.rememberUsername)
        _rememberPassword = State(initialValue: runtime.info.rememberPassword)
    }

    var body: some View {
        NavigationStack {
            Form {
                if runtime.info.webAPIURL.lowercased().hasPrefix("http://") {
                    Section { InsecureEndpointWarning() }
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    Toggle("Remember Username", isOn: $rememberUsername)
                    Toggle("Remember Password", isOn: $rememberPassword)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Create an Account") { showingRegister = true }
                }
            }
            .navigationTitle("Sign In")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign In") {
                        Task { await login() }
                    }
                    .disabled(busy || username.trimmed.isEmpty || password.isEmpty)
                }
            }
            .overlay {
                if busy { ProgressView("Signing in…").padding() }
            }
            .sheet(isPresented: $showingRegister) {
                RegisterView(runtime: runtime)
            }
        }
    }

    private func login() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let api = try URLHelper.baseURL(runtime.info.webAPIURL)
            let response = try await HTTPClient.shared.login(
                webAPI: api,
                username: username.trimmed,
                password: password
            )
            _ = response.sessionId // Confirms the response; never stored in the keychain.

            var info = runtime.info
            info.username = rememberUsername ? username.trimmed : ""
            info.rememberUsername = rememberUsername
            info.rememberPassword = rememberPassword
            runtime.info = info
            state.update(info)

            if rememberPassword {
                guard CredentialStore.shared.save(password, for: info.id) else {
                    throw LauncherError.keychain(-1)
                }
            } else {
                CredentialStore.shared.delete(for: info.id)
            }

            state.notify("Signed in. iOS can manage files but cannot launch the desktop game.")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            if case LauncherError.unauthorized = error {
                password = ""
            }
        }
    }
}

struct RegisterView: View {
    @ObservedObject var runtime: ServerRuntime
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var busy = false
    @State private var errorMessage: String?

    private var passwordsMatch: Bool { password == confirmPassword }
    private var isValid: Bool {
        let name = username.trimmed
        return name.count >= 3 && name.count <= 50 && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
            && password.count >= 6 && password.count <= 100 && password.allSatisfy(\.isASCII)
            && passwordsMatch
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New Account") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    SecureField("Confirm Password", text: $confirmPassword)
                    if !confirmPassword.isEmpty && !passwordsMatch {
                        Text("Passwords do not match.").foregroundStyle(.red)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Register")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Register") {
                        Task { await register() }
                    }
                    .disabled(busy || !isValid)
                }
            }
            .overlay {
                if busy { ProgressView("Creating account…").padding() }
            }
        }
    }

    private func register() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let api = try URLHelper.baseURL(runtime.info.webAPIURL)
            try await HTTPClient.shared.register(
                webAPI: api,
                username: username.trimmed,
                password: password
            )
            state.notify("Account created. You can now sign in.")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
