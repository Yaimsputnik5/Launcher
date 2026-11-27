import Foundation

/// Terrain presentation derived from the original client's GZNE data.
///
/// The zone bounds and material records are read from `FabledRealms.gzne`; the
/// flat colors are averages of decoded, verified ground-texture DDS files from
/// the shipped `.pack` archives. The exact original rule that selects a ground
/// material for a grid tile is still unresolved, so environment IDs are mapped
/// to material records by index when possible, then by name prefix, then by a
/// stable deterministic fallback. This is a presentation mapping, not a claim
/// about the original engine's tile-material lookup.
struct ClientTerrainPalette {
    let zone: ClientZoneManifest?
    let boundsMatchSanctuaryGrid: Bool
    let colorsByEnvironmentID: [Int: EngineColor]
    let materialsByEnvironmentID: [Int: String]
    let status: String

    init(zone: ClientZoneManifest?, worldMap: WorldMap, assetPipeline: EngineAssetPipeline) {
        self.zone = zone

        let matches = zone.map { manifest in
            manifest.minChunkX == worldMap.zone.startLongitude
                && manifest.maxChunkX == worldMap.zone.endLongitude
                && manifest.minChunkY == worldMap.zone.startLatitude
                && manifest.maxChunkY == worldMap.zone.endLatitude
        } ?? false
        self.boundsMatchSanctuaryGrid = matches

        var textureColors: [String: EngineColor] = [:]
        if let zone {
            for material in zone.materials {
                guard let path = ClientMaterialCatalog.texturePath(forTextureName: material.textureName),
                      let image = try? assetPipeline.image(relativePath: path),
                      let color = image.averageColor()
                else { continue }
                textureColors[material.textureName.lowercased()] = color
            }
        }

        let usableMaterials = zone?.materials.filter {
            textureColors[$0.textureName.lowercased()] != nil
        } ?? []
        var colors: [Int: EngineColor] = [:]
        var names: [Int: String] = [:]
        if !usableMaterials.isEmpty {
            for row in worldMap.environment.rows {
                for environmentID in row where environmentID != -1 {
                    guard colors[environmentID] == nil else { continue }
                    guard let material = Self.material(
                        forEnvironmentID: environmentID,
                        environmentName: worldMap.environmentName(id: environmentID),
                        in: usableMaterials
                    ) else { continue }
                    colors[environmentID] = textureColors[material.textureName.lowercased()]
                    names[environmentID] = material.name
                }
            }
        }

        self.colorsByEnvironmentID = colors
        self.materialsByEnvironmentID = names

        if let zone {
            let matchText = matches ? "confirmed" : "mismatch"
            self.status = "GZNE v\(zone.version) bounds \(matchText) · \(zone.materials.count) materials · "
                + "\(textureColors.count) decoded client textures · \(colors.count) environment IDs mapped"
        } else {
            self.status = "Client zone definition unavailable; terrain uses a neutral fallback."
        }
    }

    func color(environmentID: Int) -> EngineColor {
        colorsByEnvironmentID[environmentID]
            ?? EngineColor(r: 0.18, g: 0.18, b: 0.20, a: 1)
    }

    func label(environmentID: Int, worldMap: WorldMap) -> String {
        let environment = worldMap.environmentName(id: environmentID)
        guard let material = materialsByEnvironmentID[environmentID] else { return environment }
        return "\(environment) · \(material)"
    }

    private static func material(
        forEnvironmentID environmentID: Int,
        environmentName: String,
        in candidates: [ZoneMaterialDefinition]
    ) -> ZoneMaterialDefinition? {
        if let indexed = candidates.first(where: { $0.index == UInt32(environmentID) }) {
            return indexed
        }

        let prefix = environmentName.lowercased().prefix(2)
        if !prefix.isEmpty,
           let named = candidates.first(where: {
               $0.name.lowercased().hasPrefix(prefix) || $0.textureName.lowercased().hasPrefix(prefix)
           }) {
            return named
        }

        let seed = UInt64(truncatingIfNeeded: environmentID) &* 0x9E37_79B9_7F4A_7C15
        return candidates[Int(seed % UInt64(candidates.count))]
    }
}

private extension DecodedImage {
    /// Samples at most 4,096 pixels, so loading a set of 256x256 client
    /// textures never dominates engine startup time.
    func averageColor() -> EngineColor? {
        guard width > 0, height > 0 else { return nil }
        let pixelCount = width * height
        guard pixels.count >= pixelCount * 4 else { return nil }
        let bytes = [UInt8](pixels)
        let step = max(1, pixelCount / 4_096)
        var red: UInt64 = 0
        var green: UInt64 = 0
        var blue: UInt64 = 0
        var sampled: UInt64 = 0
        var offset = 0
        while offset < pixelCount {
            let base = offset * 4
            red += UInt64(bytes[base])
            green += UInt64(bytes[base + 1])
            blue += UInt64(bytes[base + 2])
            sampled += 1
            offset += step
        }
        guard sampled > 0 else { return nil }
        return EngineColor(
            r: Double(red) / Double(sampled) / 255,
            g: Double(green) / Double(sampled) / 255,
            b: Double(blue) / Double(sampled) / 255,
            a: 1
        )
    }
}
