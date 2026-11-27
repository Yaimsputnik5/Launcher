# Client asset inventory and first native renderer step

Date: 2026-11-27

## Scope

Source of truth: `/home/deadptr/.local/share/OSFRLauncher/Servers/OSFR Public Server/Client`, including `FreeRealms.exe` (SHA-256 `26cc1c522a45e71fb57882da515f65bac45c8c8b8c8b8c8b7e740c0cea81c52a733351`).

This audit adds client-asset format evidence to the earlier compiled-binary work in `05-compiled-binaries-and-rea.md`. It does not claim complete engine parity.

## REA status

- `FreeRealms.exe` was opened through REA with the Hopper provider; the provider selected the PE32/x86 target correctly but its bridge never became ready (loader/license dialog), so no decompiled functions were obtained from that session.
- Direct REA/Ghidra selection was rejected by the local bridge: only Ghidra `12.1.x` is accepted and the installed version is `12.2`.
- Earlier manual headless Ghidra analysis remains the authoritative compiled-binary evidence: 134,650 functions, `.text 00401000-0174ffff`, `.rdata 01751000-01af1fff`, `.data 01af2000-01cc0fff`.
- No xref-level or decompiled behavioral reconstruction of the full game client is claimed.

## Verified client inventory

- 1,820 files across 39 directories; 1,226,592,206 bytes total.
- 13 `.pack` containers with 68,689 entries and 874,170,907 payload bytes, verified with the existing big-endian chained-directory parser and CRC-32 checks.
- 715 compiled D3D `.fxo` effects (`01 09 ff fe`), useful for material/semantic names but not directly reusable as Metal MSL.
- 381 XML files including `pipeline_0..3.xml`, `materials_0..3.xml`, `lights*.xml`, `rendertargets*.xml`, `Resources/ObjectTerrainData.xml`, `Resources/SKY/*.xml`, and `custom/FabledRealmsAreas.xml`.
- `UI/ScriptsBase.bin` begins `1b 4c 75 61 51 00 ... (luac)`, i.e. Lua 5.1-style bytecode.
- `tcg/cards.rcc` and `tcg/core_resources.rcc` begin `qres` with version `01 00 00 00`; this is a custom container, not a standard Qt resource file. The existing Swift error text calling it Qt is inaccurate for these artifacts.
- Client logs confirm the live zone is `FabledRealms` (`NetInfo.log`: `RECEIVED=ZoneDetails - FabledRealms`; `FreeRealms.log`: `World Ready new loc=-481.156006, -44.669899, -1278.699951`).

### First minimal-zone parse path

1. `ClientConfig.ini` — `World=NoSolo`, `Locale=8`, `IndirectServerAddress=file://./manifest`.
2. `Graphics.ini` — selects pipeline tier 3 with VS/PS 3.0.
3. `Assets_manifest.txt` plus `Assets_000..009.pack` and `AssetsW_000/001.pack`. `AssetsW_*` is required for the real world; direct-only loading causes the documented G22 world-init failure.
4. `Resources/ObjectTerrainData.xml` and `Resources/SKY/sky_wilds24.xml`.
5. `FabledRealms.gzne` (`GZNE` v3, `Assets_004.pack`) for zone bounds and material names.
6. `FabledRealms.cob`, `FabledRealms.odd`, and `FabledRealms_<long>_<lat>.gcnk`/`.gck2` chunks.
7. Referenced `.adr`, `.dme`, `.dma`, `.dsk`, `.cdt`, `.dds`, and minimap `FabledRealms_Tile_*.dds`.

## Concrete engine change

The first visible native-engine step is deliberately narrow and evidence-backed:

- `Engine/ClientTextureCatalog.swift` records a verified entry from `Assets_000.pack`:
  `Assets_000.pack#FabledRealms_Tile_000_-08_0_0.dds`.
  The entry is a 256×256 DXT1 DDS at offset 1,657,016, size 32,896, and is decoded by the existing portable `DDSDecoder` to RGBA8.
- `OSFREngine` now loads that reference through `EngineAssetPipeline`, carries decoded images in `EngineFrame.textures`, and publishes a `.clientTexture` drawable with a source label.
- `MetalWorldView` now batches colored primitives and textured quads separately, uploads decoded RGBA8 textures once per path/dimension, and samples them with a linear clamp-to-edge sampler.
- The textured panel is a real client minimap tile in a HUD-sized panel. It is not presented as a full reconstructed 3D map.

## Tests

`swift test --package-path ios`: 118 tests, 0 failures on Linux.

New coverage:

- `testClientTextureCatalogPointsAtVerifiedFabledRealmsTile`
- `testEngineLoadsDecodedClientTextureIntoRenderFrame`

## Remaining unknowns

- `.gr2`/`.dme`/`.cdt` field layouts, Granny skeleton/animation semantics, and navmesh polygon data are not decoded.
- FXO bytecode is D3D-specific; native MSL effects must be reimplemented from material semantics.
- `.rcc` layout, compressed `.z` manifest variants, Lua behavior, and continuous gateway gameplay packets remain unresolved.
- The current world simulation still uses colored tiles, inferred NPC positions, deterministic first-entry drops, and tile sliding rather than full 3D/physics/navmesh behavior.

This commit is a real-asset rendering milestone, not a claim of full client parity.
