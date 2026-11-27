# GZNE materials and native terrain (evidence-backed presentation)

This note records the first native-engine terrain step that uses the shipped
client zone definition instead of a synthetic color palette.

## Source evidence

- `FabledRealms.gzne` is stored in `Assets_004.pack` and begins
  `47 5a 4e 45 03 00 00 00` (`GZNE`, version 3).
- Header fields observed at file offset 0:
  - `u32 version = 3`
  - `u32 field_04 = 0`
  - `u32 field_08 = 0x00000200` (512)
  - `u32 tileResolution = 128`
  - `f32 tileWorldSize = 64.0`
  - `u32 flags = 8`
  - `i32 minChunkX = -32`, `i32 minChunkY = -48`
  - `i32 maxChunkX = 96`, `i32 maxChunkY = 80`
  - `u32 checksum = 0x00165C59`
  - `u32 materialCount = 55`
- The material table at offset 56 contains 55 records with this layout:
  null-terminated material name, null-terminated texture name, `u32 flags`,
  `u32 floraCount`, `floraCount` flora records of three `f32`, one `u8`
  channel byte and a null-terminated flora name, then a `u32` material index.
- The zone bounds match the Sanctuary grid in
  `Resources/Zones/FabledRealms.json`: longitude `-32..96`, latitude
  `-48..80`, `TileSize = 64`.
- A targeted scan of the shipped big-endian `.pack` directory blocks found
  eight of the 41 GZNE ground-texture names as exact entries. Those entries
  are listed in `ios/Launcher/Engine/ClientMaterialCatalog.swift` and are
  verified by `RealZoneSmokeTests`.

## Native change

- `ClientZoneManifest.swift` parses the GZNE header, material table and flora
  records, and exposes zone data through `ClientAssetDataLoader`.
- `ClientMaterialCatalog.swift` maps GZNE texture names only to `.pack`
  entries that were actually observed; unknown textures are not invented.
- `ClientTerrainPalette.swift` decodes those verified DDS entries through the
  existing portable image pipeline, averages a bounded pixel sample, and
  presents a color per Sanctuary environment ID.
- `OSFREngine.rebuildScene()` now colors terrain tiles from that palette and
  labels tiles with both the environment and the mapped client material.
- `GamePlayerView` shows the zone/material status alongside the existing
  texture status.

The environment-ID-to-material lookup is a **presentation mapping** (index,
name prefix, then deterministic fallback). The original client rule that
selects a ground material for a tile is still unresolved. This change does
not claim that the original engine used this mapping.

## Verification

- Linux: `swift test --package-path ios --scratch-path /tmp/opencode/osfr-swift-test-zone4`
  — 124 tests, 0 failures.
- New tests cover the GZNE fixture, the real `FabledRealms.gzne`, verified
  `.pack` paths, and engine tiles colored from decoded client textures.
- The iOS build is verified separately by the `ios-build.yml` workflow on
  `macos-15-intel`; the release asset is only replaced after a green build.

## Minimap tile evidence

`FabledRealms_TileInfo.txt` is in `Assets_002.pack` at absolute offset
37,169,475, size 173,096. It has 1,920 tab-separated rows and no header.
Every filename matches
`FabledRealms_Tile_<longitude>_<latitude>_<tileZ>_<tileX>.dds`, and every row
satisfies this exact formula for all 1,920 entries:

- `worldX = latitude * 64 + tileX * 128`
- `worldZ = longitude * 64 + tileZ * 128`
- `width = height = 128`

The observed chunk origins are longitude `-32..56` and latitude `-48..24`, in
steps of 8 (12 × 10 chunks, each 4 × 4 tiles). This is a verified mapping for
minimap tile placement; it is not a reconstruction of terrain height or
collision. The native atlas implementation, its 16 available DDS entries, and
its remaining limits are recorded in `13-engine-material-and-tile-fidelity.md`.

## Remaining unknowns

- The remaining 33 GZNE ground-texture names are not present as exact loose
  names in the scanned `.pack` directories; they may use packed aliases or a
  different case/derivation.
- `.map` is now decoded as a 2,019-node weighted graph; see
  `sanctuary-audit/09-packet-backed-world-view-and-navgraph.md`. The original
  engine's use of that graph is still unresolved.
- `.gcnk` object records are decoded in
  `sanctuary-audit/10-gcnk-objects-and-udp-parity.md`, but exact original
  rendering, collision, and gameplay semantics remain unresolved.
- The material mapping is visual only; physics, height, flora placement and
  gameplay behavior are not derived from GZNE yet.
