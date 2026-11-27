import Foundation

enum URLHelper {
    static func baseURL(_ string: String) throws -> URL {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil
        else {
            throw LauncherError.invalidURL(string)
        }
        guard components.user == nil, components.password == nil else {
            throw LauncherError.invalidURL("URLs must not contain embedded credentials")
        }

        components.query = nil
        components.fragment = nil
        if components.path.isEmpty {
            components.path = "/"
        } else if !components.path.hasSuffix("/") {
            components.path += "/"
        }
        guard let url = components.url else {
            throw LauncherError.invalidURL(string)
        }
        return url
    }

    /// Credentials are only sent over HTTPS, or over HTTP when the target is a
    /// loopback server on the device itself. The desktop launcher warns about
    /// plaintext credentials but still sends them; iOS refuses that known risk.
    static func credentialsAllowed(for url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return false
        }
        if scheme == "https" { return true }
        return scheme == "http" && isLoopbackHost(host)
    }

    /// Plain HTTP is still accepted for user-supplied manifests and client
    /// downloads because the C# launcher allows it. It is never accepted for
    /// credentials (`credentialsAllowed`), and the UI warns once when a server
    /// is added with a non-loopback HTTP base URL.
    static func requiresInsecureTransportWarning(for url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host else { return false }
        return scheme == "http" && !isLoopbackHost(host)
    }

    static func isLoopbackHost(_ host: String) -> Bool {
        let value = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "localhost" || value == "::1" { return true }
        guard value.hasPrefix("127.") else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return false
        }
        return parts[0] == "127"
    }

    /// Converts the v1 `LoginApiUrl` endpoint into a v2-style API base.
    static func apiBaseFromV1(_ string: String) throws -> URL {
        let base = try baseURL(string)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var path = components.path

        if !path.hasSuffix("/") {
            let nsPath = path as NSString
            path = nsPath.deletingLastPathComponent
            if path.isEmpty { path = "/" }
            if !path.hasSuffix("/") { path += "/" }
        }
        components.path = path
        guard let url = components.url else {
            throw LauncherError.invalidURL(string)
        }
        return url
    }

    /// Appends path components without dropping the trailing component of the
    /// base URL (the C# launcher's `new Uri(base, "login")` bug).
    static func joining(_ base: URL, _ path: String) -> URL {
        let encoded = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        var string = base.absoluteString
        if !string.hasSuffix("/") { string += "/" }
        return URL(string: string + encoded) ?? base
    }
}
