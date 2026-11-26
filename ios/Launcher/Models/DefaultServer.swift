import Foundation

/// The single server preset the original desktop launcher ships with.
///
/// The C# launcher only stores a bootstrap URL and derives everything else from
/// `servermanifest.xml`. Keeping the live values here as a *fallback* means the
/// public server is visible on first launch even when that fetch fails; the
/// runtime refreshes the record from the manifest as soon as it can.
enum DefaultServer {
    static let url = "https://opensourcefreerealms.com"
    static let manifestName = "servermanifest.xml"
    static let name = "OSFR Public Server"
    static let description = "Welcome to the official Open Source Free Realms public server!"
    static let webAPIURL = "https://api.opensourcefreerealms.com/"
    static let loginServer = "play.opensourcefreerealms.com:20042"

    /// Stable identity so Keychain credentials survive settings regeneration.
    static let id = UUID(uuidString: "5E1F4C2A-9B7D-4E63-8A10-2D6C4F8B0A91")!

    static func info() -> ServerInfo {
        ServerInfo(
            id: id,
            url: url,
            name: name,
            descriptionText: description,
            webAPIURL: webAPIURL,
            loginServer: loginServer,
            savePath: SafePath.sanitizedLeaf(name),
            username: "",
            rememberUsername: false,
            rememberPassword: false,
            locale: .en_US
        )
    }
}
