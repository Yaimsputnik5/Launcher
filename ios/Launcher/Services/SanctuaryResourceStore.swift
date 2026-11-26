import Foundation

struct SanctuaryResourceEntry: Codable, Equatable {
    let path: String
    let size: Int64
    let sha256: String
}

struct SanctuaryResourceManifest: Codable, Equatable {
    let sourceCommit: String
    let license: String
    let fileCount: Int
    let totalBytes: Int64
    let files: [SanctuaryResourceEntry]
}

/// Locates the Sanctuary server data copied into the app bundle.
///
/// This store is intentionally read-only. Persisted character state lives in
/// the engine's database layer, not in the bundled catalog.
final class SanctuaryResourceStore {
    static let shared = SanctuaryResourceStore()

    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default

    var root: URL? { AppPaths.bundledSanctuaryResources }

    func manifest() -> SanctuaryResourceManifest? {
        guard let root,
              let data = try? Data(contentsOf: root.appendingPathComponent("sanctuary-resources-manifest.json"))
        else { return nil }
        return try? decoder.decode(SanctuaryResourceManifest.self, from: data)
    }

    func readiness() -> AssetReadiness {
        let manifest = manifest()
        return AssetReadiness(
            bundledClientFileCount: 0,
            bundledClientTotalBytes: 0,
            sanctuaryFileCount: manifest?.fileCount ?? 0,
            sanctuaryTotalBytes: manifest?.totalBytes ?? 0,
            hasClientManifest: false,
            hasSanctuaryManifest: manifest != nil
        )
    }

    func url(for relativePath: String) -> URL? {
        guard let root,
              let url = try? Self.containedURL(relativePath, in: root),
              fileManager.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    func data(for relativePath: String) -> Data? {
        guard let url = url(for: relativePath) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    func exists(_ relativePath: String) -> Bool {
        url(for: relativePath) != nil
    }

    /// Size-only check against the generated manifest. Full SHA-256 verification
    /// is performed by `scripts/sync_sanctuary_resources.sh` at sync time.
    func verifySizes() -> AssetVerificationReport {
        guard let manifest = manifest() else {
            return AssetVerificationReport(missing: ["sanctuary-resources-manifest.json"])
        }
        var report = AssetVerificationReport(checked: manifest.files.count)
        for entry in manifest.files {
            guard let url = url(for: entry.path),
                  let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.int64Value
            else {
                report.missing.append(entry.path)
                continue
            }
            if size == entry.size {
                report.verified += 1
            } else {
                report.mismatched.append(entry.path)
            }
        }
        return report
    }

    private static func containedURL(_ relativePath: String, in base: URL) throws -> URL {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else { throw LauncherError.unsafePath(relativePath) }
        return try SafePath.contained(base: base, components: components)
    }
}
