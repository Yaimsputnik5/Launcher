import Foundation

/// Small, explicit registry of verified original-client texture entries.
///
/// These paths were read from the shipped `.pack` directory blocks, not guessed
/// from file names. They are deliberately narrow: a platform port should put a
/// real client image on screen before claiming broader material or mesh parity.
enum ClientTextureCatalog {
    /// Manifest-relative texture reference for a zone's first visible minimap
    /// tile. The entry is a 256x256 DXT1 DDS in `Assets_000.pack`.
    static func texturePath(forZoneName zoneName: String) -> String? {
        switch zoneName.lowercased() {
        case "fabledrealms":
            return "Assets_000.pack#FabledRealms_Tile_000_-08_0_0.dds"
        default:
            return nil
        }
    }
}
