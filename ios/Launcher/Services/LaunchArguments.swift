import Foundation

/// The WebAPI `LaunchArguments` string that the C# launcher appends after
/// `Server=`, `SessionId=` and `Internationalization:Locale=`.
///
/// The native client cannot start a Windows process, so it applies recognized
/// keys to the in-process login/gateway handshake instead of dropping them.
struct LaunchArguments: Equatable {
    let raw: [String]

    private let values: [String: String]

    init(_ string: String?) {
        var parsed: [String: String] = [:]
        for argument in Self.tokenize(string) {
            // `Internationalization:Locale=en_US` contains both separators; the
            // equals sign always terminates the key in the original client.
            let separator = argument.firstIndex(of: "=") ?? argument.firstIndex(of: ":")
            guard let separator else { continue }
            let key = String(argument[..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = String(argument[argument.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty {
                parsed[key] = value
            }
        }
        raw = Self.tokenize(string)
        values = parsed
    }

    /// Host and UDP port supplied by the server, if any.
    var server: String? { value(for: "server") }

    /// The login/game session ticket supplied by the server, if any.
    var sessionID: String? { value(for: "sessionid", "session") }

    /// Locale override supplied by the server, if it is one the app supports.
    var locale: GameLocale? {
        guard let raw = value(for: "internationalization:locale", "locale") else { return nil }
        return GameLocale.fromManifest(raw)
    }

    func value(for keys: String...) -> String? {
        for key in keys {
            if let value = values[key.lowercased()] { return value }
        }
        return nil
    }

    private static func tokenize(_ string: String?) -> [String] {
        guard let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        for character in string {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                } else {
                    current.append(character)
                }
            } else if character.isWhitespace && quote == nil {
                if !current.isEmpty {
                    arguments.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { arguments.append(current) }
        return arguments
    }
}
