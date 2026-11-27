import Foundation

/// One shipped minimap DDS whose world rectangle is recorded by
/// `FabledRealms_TileInfo.txt`. Coordinates are the upper-left corner from the
/// client table; the centre is derived from the verified width and height.
struct ClientMinimapTile: Equatable, Sendable {
    let name: String
    let archiveName: String
    let texturePath: String
    let originX: Double
    let originZ: Double
    let width: Double
    let height: Double

    var centerX: Double { originX + width / 2 }
    var centerZ: Double { originZ + height / 2 }
}

/// Reads the original client's minimap index and intersects it with the DDS
/// entries actually present in the embedded `.pack` directories.
///
/// The table has 1,920 rows, but this client payload contains only a subset of
/// the referenced DDS files. Missing tiles are deliberately omitted instead of
/// being approximated with invented art.
struct ClientMinimapAtlas: Equatable, Sendable {
    static let tileInfoPath = "Assets_002.pack#FabledRealms_TileInfo.txt"
    static let archives = (0...9).map { String(format: "Assets_%03d.pack", $0) }

    let tiles: [ClientMinimapTile]
    let rowCount: Int
    let status: String

    init(dataLoader: ClientAssetDataLoader = ClientAssetDataLoader()) {
        var available: [String: String] = [:]
        for archive in Self.archives {
            guard let names = try? dataLoader.packEntryNames(archivePath: archive) else { continue }
            for name in names where name.hasPrefix("FabledRealms_Tile_") && name.hasSuffix(".dds") {
                available[name] = archive
            }
        }

        guard !available.isEmpty else {
            tiles = []
            rowCount = 0
            status = "No shipped minimap DDS entries were found in the embedded client packs."
            return
        }

        guard let data = try? dataLoader.data(relativePath: Self.tileInfoPath),
              let text = String(data: data, encoding: .utf8)
        else {
            tiles = []
            rowCount = 0
            status = "FabledRealms_TileInfo.txt is unavailable in Assets_002.pack."
            return
        }

        var parsedRows = 0
        var resolved: [ClientMinimapTile] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 6 else { continue }
            parsedRows += 1
            let name = String(fields[0])
            guard let archive = available[name],
                  let originX = Double(fields[1]),
                  let originZ = Double(fields[3]),
                  let width = Double(fields[4]),
                  let height = Double(fields[5]),
                  width.isFinite, height.isFinite,
                  originX.isFinite, originZ.isFinite,
                  width > 0, height > 0
            else { continue }
            resolved.append(ClientMinimapTile(
                name: name,
                archiveName: archive,
                texturePath: "\(archive)#\(name)",
                originX: originX,
                originZ: originZ,
                width: width,
                height: height
            ))
        }

        tiles = resolved.sorted { $0.name < $1.name }
        rowCount = parsedRows
        status = "\(tiles.count)/\(available.count) shipped minimap DDS files placed from \(parsedRows) TileInfo rows."
    }
}
