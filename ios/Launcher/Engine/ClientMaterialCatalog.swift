import Foundation

/// Verified `.pack` entries for ground-material textures referenced by
/// `FabledRealms.gzne`.
///
/// Every path below was found by walking the shipped big-endian `.pack`
/// directory blocks and matching the texture names in the real GZNE material
/// table. The list is intentionally limited to entries that were observed; a
/// missing entry means the renderer falls back rather than inventing a texture.
enum ClientMaterialCatalog {
    /// Manifest-relative path for a ground texture name from a GZNE record.
    static func texturePath(forTextureName textureName: String) -> String? {
        let normalized = textureName.lowercased()
        guard let entry = entries.first(where: { $0.textureName.lowercased() == normalized }) else {
            return nil
        }
        return "\(entry.archive)#\(entry.entryName)"
    }

    /// All verified ground-texture entries, in stable archive/name order.
    static let entries: [(archive: String, entryName: String, textureName: String)] = [
        ("Assets_008.pack", "black.dds", "black.dds"),
        ("Assets_007.pack", "ss_cobblestone.dds", "ss_cobblestone.dds"),
        ("Assets_008.pack", "sg_cobblestone.dds", "sg_cobblestone.dds"),
        ("Assets_008.pack", "sg_dirt.dds", "sg_dirt.dds"),
        ("Assets_004.pack", "sg_grass.dds", "sg_grass.dds"),
        ("Assets_001.pack", "sg_grass_dark.dds", "sg_grass_dark.dds"),
        ("Assets_001.pack", "sg_stone.dds", "sg_stone.dds"),
        ("Assets_005.pack", "sh_snow.dds", "sh_snow.dds")
    ]
}
