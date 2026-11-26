import Foundation
#if canImport(FoundationXML) && !canImport(UIKit)
import FoundationXML
#endif

private func trimmedText(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Server manifest

final class ServerManifestParser: NSObject, XMLParserDelegate {
    private var version: Int?
    private var values: [String: String] = [:]
    private var currentElement = ""
    private var text = ""
    private var parseError: Error?

    func parse(_ data: Data) throws -> ServerManifest {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), parseError == nil else {
            throw parseError ?? parser.parserError ?? LauncherError.malformedManifest("XML parser failed")
        }
        guard let version else {
            throw LauncherError.malformedManifest("Missing version attribute")
        }

        switch version {
        case 1:
            let loginAPI = try value("LoginApiUrl")
            return ServerManifest(
                version: version,
                name: try value("Name"),
                descriptionText: try value("Description"),
                webAPIURL: try URLHelper.apiBaseFromV1(loginAPI).absoluteString,
                loginServer: try value("LoginServer")
            )
        case 2:
            return ServerManifest(
                version: version,
                name: try value("Name"),
                descriptionText: try value("Description"),
                webAPIURL: try URLHelper.baseURL(value("WebApiUrl")).absoluteString,
                loginServer: try value("LoginServer")
            )
        case let other:
            throw other < 1
                ? LauncherError.invalidManifestVersion(other)
                : LauncherError.unsupportedManifestVersion(other)
        }
    }

    private func value(_ name: String) throws -> String {
        guard let match = values.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame }),
              !match.value.isEmpty
        else {
            throw LauncherError.malformedManifest("Missing \(name)")
        }
        return match.value
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if let rawVersion = attributeDict["version"] {
            version = Int(rawVersion)
        }
        currentElement = elementName
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        values[elementName] = trimmedText(text)
        currentElement = ""
        text = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if self.parseError == nil { self.parseError = parseError }
    }
}

// MARK: - Client manifest

final class ClientManifestParser: NSObject, XMLParserDelegate {
    private final class FolderFrame {
        let name: String
        var files: [ClientFile] = []
        var folders: [ClientFolder] = []
        var pendingFile: ClientFile?

        init(name: String) {
            self.name = name
        }
    }

    private var version: Int?
    private var languages: [GameLocale] = []
    private var stack: [FolderFrame] = []
    private var rootFolder: ClientFolder?
    private var parseError: Error?

    func parse(_ data: Data) throws -> ClientManifest {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), parseError == nil else {
            throw parseError ?? parser.parserError ?? LauncherError.malformedManifest("XML parser failed")
        }
        guard let version else {
            throw LauncherError.malformedManifest("Missing version attribute")
        }
        guard version == 1 else {
            throw version < 1
                ? LauncherError.invalidManifestVersion(version)
                : LauncherError.unsupportedManifestVersion(version)
        }
        guard let rootFolder else {
            throw LauncherError.malformedManifest("Missing root folder")
        }
        return ClientManifest(version: version, languages: languages, rootFolder: rootFolder)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "ClientManifest":
            if let rawVersion = attributeDict["version"] {
                version = Int(rawVersion)
            }
            let rawLanguages = attributeDict["languages"] ?? ""
            languages = rawLanguages
                .split(separator: ",")
                .compactMap { GameLocale.fromManifest(String($0)) }

        case "Folder":
            // The published OSFR manifest starts with an unnamed root <Folder>.
            // Sanctuary's downloader also treats a missing name as "no path
            // component", so preserve that behavior here.
            let rawName = (attributeDict["name"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let leaf = rawName.isEmpty ? "" : try SafePath.validatedLeaf(rawName)
                stack.append(FolderFrame(name: leaf))
            } catch {
                fail(error, parser: parser)
            }

        case "File":
            guard let frame = stack.last else {
                fail(LauncherError.malformedManifest("File outside folder"), parser: parser)
                return
            }
            do {
                guard let rawName = attributeDict["name"],
                      let rawSize = attributeDict["size"],
                      let size = UInt64(rawSize),
                      let rawHash = attributeDict["hash"],
                      let hash = UInt64(rawHash)
                else {
                    fail(LauncherError.malformedManifest("Invalid file attributes"), parser: parser)
                    return
                }
                frame.pendingFile = ClientFile(
                    name: try SafePath.validatedLeaf(rawName),
                    size: size,
                    hash: hash
                )
            } catch {
                fail(error, parser: parser)
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "File":
            guard let frame = stack.last, let file = frame.pendingFile else { return }
            frame.files.append(file)
            frame.pendingFile = nil

        case "Folder":
            guard let frame = stack.popLast() else { return }
            let folder = ClientFolder(name: frame.name, files: frame.files, folders: frame.folders)
            if let parent = stack.last {
                parent.folders.append(folder)
            } else if rootFolder == nil {
                rootFolder = folder
            } else {
                fail(LauncherError.malformedManifest("Multiple root folders"), parser: parser)
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if self.parseError == nil { self.parseError = parseError }
    }

    private func fail(_ error: Error, parser: XMLParser) {
        if parseError == nil { parseError = error }
        parser.abortParsing()
    }
}
