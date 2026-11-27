# Engine material and tile fidelity (current state)

This note separates **verified client data** from **presentation heuristics** in
the native engine. It updates audit `08` with the current implementation and
records what is still unresolved. No literal 1:1 engine claim is made here.

## Verified client data

- `FabledRealms.gzne` is in `Assets_004.pack` (offset `43,904,494`, size
  `29,181`, CRC `1489795130`). Header: magic `GZNE`, version `3`, tile resolution
  `128`, tile world size `64.0`, flags `8`, bounds longitude `-32..96`, latitude
  `-48..80`, checksum `0x00165C59`, material count `55`.
- The GZNE material table begins at offset `56` and ends at offset `3,321`.
  Parsing all 55 records leaves **25,860 bytes** after the table. No verified
  source or format rule for that tail is available; it is not interpreted.
- `FabledRealms_TileInfo.txt` is in `Assets_002.pack` (offset `37,169,475`, size
  `173,096`, CRC `1507830647`). It contains 1,920 tab-separated rows with no
  header. Sample row:
  `FabledRealms_Tile_-32_-48_0_0.dds\t-3072.000000\t0.000000\t-2048.000000\t128.000000\t128.000000`.
- For all 1,920 TileInfo rows the verified placement formula is:
  `worldX = latitude * 64 + tileX * 128`,
  `worldZ = longitude * 64 + tileZ * 128`,
  `width = height = 128`.
- A targeted scan of the embedded `.pack` directories found **16** exact
  `FabledRealms_Tile_*.dds` entries (32,896 bytes each) in `Assets_000.pack`
  through `Assets_008.pack`, plus the TileInfo text file itself.
- The current embedded index exposes `Assets_000.pack` … `Assets_009.pack`.
  Earlier audit notes that `AssetsW_000.pack`/`AssetsW_001.pack` are required
  for the real world; those files are not present in the local embedded payload,
  so no data from them is invented.

## Current native implementation

- `ClientZoneManifest.swift` parses GZNE v2/v3 headers, material records, and
  flora records with bounded reads and explicit errors.
- `ClientMaterialCatalog.swift` maps only GZNE texture names that were actually
  observed as `.pack` entries.
- `ClientTerrainPalette.swift` decodes verified ground DDS files, samples at most
  4,096 pixels per image, and colors each Sanctuary environment ID. The
  environment-ID → GZNE material rule is **index match, then two-character name
  prefix, then deterministic fallback**. This is a presentation heuristic; the
  original engine's lookup is unresolved.
- `ClientMinimapAtlas.swift` reads TileInfo rows, scans `Assets_000.pack` …
  `Assets_009.pack`, and intersects the table with DDS entries that actually
  exist. Missing tiles are omitted rather than synthesized. Rows with
  non-finite or non-positive coordinates are rejected.
- `OSFREngine.swift` decodes those tiles through the existing `TextureLoader`,
  caches images in the render frame, and draws textured quads at the TileInfo
  world rectangles transformed through `WorldMap.unitPosition`. Tile drawables
  are labeled with the exact client filename.
- Minimap atlas rendering is **offline-only**. Remote sessions remain
  packet-only: zone selection comes from `PacketSendZoneDetails`, and entity
  markers require decoded position/spawn packets. Static client map art is not
  injected into a remote world view. `GamePlayerView.attachRemote` now waits for
  a server zone packet instead of defaulting to a local zone name; the packet
  map does not attach until the server zone resolves through the Sanctuary zone
  catalog. The projected world grid still uses the real Sanctuary zone resource
  selected by that packet; no offline player, NPC, collection node or texture
  path is carried into the remote frame.

## Known fidelity gaps

1. Only 16 of 1,920 TileInfo DDS files are present in the embedded payload. The
   textured minimap is therefore sparse, not a full original world atlas.
2. The native renderer projects the world to a 2D Metal scene. It does not
   reconstruct the original 3D camera, height field, lighting, FXO/Granny
   meshes, or shader pipeline.
3. The 25,860-byte GZNE tail after the material table is unparsed. No verified
   `GZNX` structure was found in the audited sources or assets.
4. Environment-ID → material selection remains heuristic. It must not be
   described as the original client's rule.
5. `OSFREngine.rebuildScene()` caps colored grid terrain at **4,096** of the
   navmesh's declared 7,680 tiles. It draws only the **nearest 32** decoded GCNK
   object records within 900 world units. Both are deliberate presentation
   bounds, not original-engine limits.
6. GCNK records are decoded as object placements/labels; collision, animation,
   interaction, and gameplay semantics are unresolved.
7. Terrain color is a bounded average of decoded DDS pixels, not the original
   renderer's material sampling.
8. Device-side visual and live-session parity has not been tested from this
   host. A user with an iOS device and AltStore/SideStore is required.

## Verification

- `ClientMinimapAtlasTests` covers row/DDS intersection, exact world centers,
  and empty-atlas behavior when either the table or DDS files are missing.
- `EngineTests` covers a decoded client minimap tile reaching the render frame
  with the exact texture path and world-derived drawable.
- Foundation-only Linux suite: `swift test --package-path ios --scratch-path
  /tmp/opencode/osfr-swift-test-chunks` — 206 tests, 1 skipped, 0 failures.
- iOS compile and IPA creation are verified separately by `ios-build.yml` on
  `macos-15-intel`.

Until the missing `AssetsW_*` payloads, GZNE tail, original material rule, full
GCNK semantics, and device/live rendering are resolved, this is an
evidence-backed native presentation—not a 1:1 engine reconstruction.
