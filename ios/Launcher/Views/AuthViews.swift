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
    @FocusState private var usernameFocused: Bool

    init(runtime: ServerRuntime) {
        self.runtime = runtime
        _username = State(initialValue: runtime.info.username)
        // The C# login view loads the stored password only when the user has
        // explicitly asked for it to be remembered.
        _password = State(initialValue: runtime.info.rememberPassword
            ? (CredentialStore.shared.password(for: runtime.info.id) ?? "")
            : "")
        _rememberUsername = State(initialValue: runtime.info.rememberUsername)
        _rememberPassword = State(initialValue: runtime.info.rememberPassword)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isInsecureEndpoint(runtime.info.webAPIURL) {
                    Section { InsecureEndpointWarning() }
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($usernameFocused)
                        .onSubmit { usernameFocused = false }
                    SecureField("Password", text: $password)
                        .submitLabel(.go)
                        .onSubmit { Task { await login() } }
                    Toggle("Remember Username", isOn:Binding(
                        get: { rememberUsername },
                        set: { rememberUsername = $0; applyRememberFlags() }
                    ))
                    Toggle("Remember Password", isOn: Binding(
                        get: { rememberPassword },
                        set: { rememberPassword = $0; applyRememberFlags() }
                    ))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Create an Account") { showingRegister = true }
                        .disabled(busy)
                }
            }
            .navigationTitle("Sign In")
            .task { usernameFocused = true }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(busy)
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

    private func applyRememberFlags() {
        var info = runtime.info
        info.username = rememberUsername ? username.trimmed : ""
        info.rememberUsername = rememberUsername
        info.rememberPassword = rememberPassword
        runtime.info = info
        state.update(info)
        if !rememberPassword {
            CredentialStore.shared.delete(for: info.id)
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

            // Sanctuary clients exchange the WebAPI ticket for a real game
            // session over the Login UDP listener. The desktop launcher only
            // forwards the WebAPI ticket to FreeRealms.exe; iOS performs the
            // full character-select/gateway-ticket handshake natively.
            let launch = LaunchArguments(response.launchArguments)
            let loginAddress = launch.server ?? runtime.info.loginServer
            let effectiveSessionID = launch.sessionID ?? response.sessionId
            let effectiveLocale = launch.locale ?? state.settings.locale
            let gameSession = try await LoginUDPSession.authenticateCharacter(
                address: loginAddress,
                sessionID: effectiveSessionID,
                fingerprint: runtime.info.loginFingerprint
                    ?? "\(Bundle.main.bundleIdentifier ?? "dev.opensourcefreerealms.launcher")/ios",
                locale: effectiveLocale
            )
            guard gameSession.sessionReply.loggedIn else {
                throw LauncherError.loginRejected(gameSession.sessionReply.status)
            }

            let details = try? gameSession.character.details()
            let configuration = WorldSessionConfiguration(
                mode: .remote,
                host: loginAddress,
                username: username.trimmed,
                sessionID: effectiveSessionID,
                characterID: GuidHelper.playerId(gameSession.entityKey),
                ticket: gameSession.clientData.serverTicket,
                cryptoKey: gameSession.clientData.cryptoKey,
                loginArguments: launch.raw,
                locale: effectiveLocale,
                characterName: details?.name,
                gatewayAddress: gameSession.clientData.serverAddress,
                gatewayGUID: gameSession.playerGUID,
                gatewayVersion: runtime.info.gatewayVersion ?? GatewayUDPSession.defaultClientVersion,
                serverID: gameSession.character.lastServerID > 0
                    ? gameSession.character.lastServerID : 1
            )
            state.setRemoteSession(configuration)

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

            state.notify("Signed in as \(details?.name ?? username.trimmed). Gateway ticket ready on \(runtime.info.name).")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            state.notify("Sign in failed: \(error.localizedDescription)", isError: true)
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
    @FocusState private var usernameFocused: Bool

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
                if isInsecureEndpoint(runtime.info.webAPIURL) {
                    Section { InsecureEndpointWarning() }
                }

                Section("New Account") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($usernameFocused)
                    SecureField("Password", text: $password)
                    SecureField("Confirm Password", text: $confirmPassword)
                        .submitLabel(.go)
                        .onSubmit { Task { await register() } }
                    if !confirmPassword.isEmpty && !passwordsMatch {
                        Text("Passwords do not match.").foregroundStyle(.red)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Register")
            .task { usernameFocused = true }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(busy)
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
            state.notify("Registration failed: \(error.localizedDescription)", isError: true)
            if case LauncherError.conflict = error {
                username = ""
            } else {
                username = ""
                password = ""
                confirmPassword = ""
            }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

