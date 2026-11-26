# OSFR all-in-one iOS architecture

This document is the working design for turning the launcher into a native,
offline-capable Free Realms app. It supersedes the launcher-only scope in `README.md`.

## Decisions

- Bundle the original Free Realms client payload instead of substituting native art.
- Target full client and server parity: offline single-player **and** joining remote
  Sanctuary-compatible servers.
- Keep the existing C# launcher untouched. iOS work stays under `ios/`.
- Use no external SwiftPM dependencies in the app target. Port logic into
  Foundation-only Swift modules that can be tested on Linux, and keep SwiftUI in
  the Xcode target.
- Treat all bundled third-party content as untrusted data. Parse it with bounds
  checks; never execute Windows binaries on iOS.

Full parity is a large port, not a single build. This repository records the
target architecture and implements it in verifiable layers. A layer is not
called complete until it has Linux unit tests and a macOS runner build.

## Bundle layout

```text
Launcher.app/
├── Launcher                         SwiftUI app + engine
├── SanctuaryResources/              server data copied from Sanctuary
│   ├── ClientItemDefinitions.json
│   ├── Models.txt
│   ├── Npcs.json
│   ├── Quests.json
│   ├── Zones/
│   ├── CollectionNodeSpawns/
│   ├── NavMeshes/
│   └── Scripts/
└── ClientAssets/                    original Free Realms payload (optional at build time)
    ├── clientmanifest.xml
    ├── Assets_000.pack
    ├── tcg/cards.rcc
    └── ...
```

`SanctuaryResources` is copied from the Sanctuary fork by
`ios/sync_sanctuary_resources.sh`. It is open-source server data under AGPL-3.0
and must keep its license notices.

`ClientAssets` is populated by `ios/fetch_client_payload.sh`. The script verifies
size and XXH64 against `clientmanifest.xml` before copying each file. The
repository stores only a `.gitkeep`; the payload is deliberately not committed.
Xcode copies the whole folder as a folder reference when present, so a build
with no payload remains small and a build with `IOS_EMBED_CLIENT=1` is fully
offline.

## Layers

### 1. OSFRCore — Foundation-only, Linux-testable

Already present or planned:

- `URLHelper`: safe URL/path composition.
- `SafePath`: single-component and contained-path validation.
- `XXHash64`: manifest verification.
- `ServerManifestParser` / `ClientManifestParser`.
- `PacketWriter` / `PacketReader`: little-endian Sanctuary wire primitives.
- `CRC32`: normal and `EncryptCode`-seeded CRC.
- `RC4`: fixed-key login cipher.
- `GuidHelper`: player/NPC GUID layout.
- Resource catalog loaders for zones, NPCs, quests, items, and environment grids.

### 2. OSFREngine — in-process server/game simulation

Planned modules:

- `LocalDatabase`: SQLite-compatible store matching the final 15-table schema.
- `AccountService`: registration, bcrypt-compatible password handling, sessions.
- `LoginService`: `LoginUdp_6` behavior, character select, character login.
- `GatewayService`: `CGAPI_527` behavior, AES-CCM, tunneled packets.
- `GatewayRegistry` / `CharacterLoginCoordinator`: replace internal UDP link with
  actor state while preserving externally visible statuses and timings.
- `ZoneManager` / `BaseZone`: 10 Hz and 1 Hz loops, tiles, visibility.
- `Entity`, `Player`, `Npc`, `Mount`, `CollectionNode`, `PlayerPet`.
- `RoutineManager` and all routine types.
- `QuestManager`, `RewardManager`, `InteractionManager`, `ChatCommandManager`.
- `ScriptRuntime`: Lua-compatible behavior for the 11 shipped scripts, or a
  generated spawn table plus native implementations of the three event scripts.
- `Pathfinder`: DotRecast-compatible SNAV reader or precomputed waypoint graph.

### 3. OSFRRender — native client

Planned modules:

- `ClientAssetStore`: resolves manifest-relative paths from `ClientAssets` or the
  app sandbox with containment checks.
- `PackReader` / `RccReader`: parsers for the proprietary containers. Format work
  is tracked separately; no Windows executable is executed.
- `AssetPipeline`: converts parsed textures/models/audio into Metal-ready data.
- `SceneGraph`, `Camera`, `TileRenderer`, `EntityRenderer`, `CharacterController`,
  `UIRenderer`, `AudioEngine`.
- Localization and string-table reader.

### 4. SwiftUI shell

The current launcher UI becomes one section of the app:

- **Launcher**: server list, manifests, downloads, account settings.
- **Play Offline**: local host session, character select, in-process world.
- **World**: native atlas/world player over the bundled FabledRealms grid, with destinations, tile movement, and a persisted character.
- **Join Server**: remote host, account/session handshake, world connection.
- **Downloads**: embedded payload status and optional repair download.
- **Diagnostics**: engine logs, packet traces, asset verification.

## Runtime flows

### Offline play

1. Verify `SanctuaryResources` checksums/manifest.
2. Open local database; create default offline user/character on first run.
3. Start `GatewayRegistry`, `ZoneManager`, and zone 1 in-process.
4. Load embedded `ClientAssets` through `ClientAssetStore`.
5. Present character select, then enter the world with no network access.
6. Persist character state back to the app sandbox.

### Remote join

1. Resolve server manifest (v1/v2) as today.
2. Register/login through WebAPI to obtain a single-use session.
3. Perform Login UDP handshake and character select/login.
4. Hand the world ticket to `GatewayService` and connect to the remote world.
5. Use the same renderer and local input state as offline play.

Offline and remote modes share the renderer, resource catalog, and packet
models. Only the transport and authority boundary differ.

## Security fixes carried forward

- Manifest path traversal rejected.
- Downloads written to `.part`, verified, then atomically replaced.
- No embedded credentials in URLs.
- No shelling out to `FreeRealms.exe`, `dotnet`, or Wine on iOS.
- Fixed Sanctuary defaults (`test`/`testtest`, shared challenge) must not be used
  for remote/public connections.
- Plain HTTP is tolerated only for local/offline endpoints; remote HTTPS is preferred.

## Legal boundary

Sanctuary code is AGPL-3.0; a Swift port must preserve notices and provide
corresponding source. Free Realms artwork, audio, fonts, and client binaries are
third-party copyrighted material and are not licensed by Sanctuary. Embedding
the payload requires the user to have the right to distribute it. The tooling
does not claim such a license.

## Current status

- Launcher functionality and a real unsigned IPA already exist.
- All five Sanctuary audits are complete under `sanctuary-audit/`.
- Foundation-only core tests run on Linux via `swift test --package-path ios`.
- Sanctuary resources (101 files, 75,740,078 bytes) and the full original client
  payload (1,788 files, 893,405,496 bytes) are staged and XXH64-verified. Neither
  payload is committed; CI regenerates both.
- The full unsigned IPA was built and verified at
  <https://github.com/YaimSputnik5/Launcher/actions/runs/45827062087>; see
  `ios/README.md` for its SHA-256 and embedded contents. Physical-device launch
  still needs to be done by the person side-loading it.
- Packet primitives, login message framing, `.pack`/`.rcc` readers, resource
  catalog loaders, a world-map loader, and a local account/character store are
  implemented as Foundation-only modules with 62 passing Linux tests.
- Engine actors, renderer, gateway AES-CCM, and full remote world transport are
  not yet complete;
  see the phase checklist below.

## Phase checklist

- [x] Audit C# launcher and Sanctuary server.
- [x] Build and verify unsigned iOS launcher IPA.
- [x] Foundation-only core test target on Linux.
- [x] Bundle Sanctuary resources and script files.
- [x] Stage and verify embedded original client payload.
- [x] Port wire primitives and crypto with vectors.
- [x] Port resource catalog loaders with fixture tests.
- [x] Implement in-process local account/character/session flow.
- [x] Add default OSFR public server preset with manifest refresh.
- [x] Add native atlas/world player backed by the zone grid and POIs.
- [ ] Implement zone/entity/quest/collection core.
- [x] Parse `.rcc` and `.pack` enough to load a usable asset subset.
- [ ] Build a playable native renderer for the FabledRealms zone.
- [ ] Implement remote Login/Gateway compatibility (login messages done; gateway pending).
- [x] Build and verify a full all-in-one IPA with embedded client data.
- [ ] Side-load that IPA on a physical iOS device (requires the user's device).
