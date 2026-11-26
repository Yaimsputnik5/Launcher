# Sanctuary audit — overview

Source: <https://github.com/Open-Source-Free-Realms/Sanctuary>
Local checkout: `/tmp/opencode/sanctuary`
Audited commit: `f5240b7554f2a80d6b815cb7ead7ffee12499565`
Fork: <https://github.com/YaimSputnik5/Sanctuary> (already present, `main` at the same commit)

## Repository shape

- 560 commits, no tags, 4 local remote-tracking branches, 1,215 tracked files.
- 1,057 C# files, 88 JSON files, 17 projects.
- 68 MB repository / 150 MB working tree.
- License: AGPL-3.0 for Sanctuary’s own code. Free Realms content is not owned by the project.
- No git submodules.

## Important early finding

Sanctuary is a **server emulator**, not a game client. Its largest files are server-side data:

| Path | Bytes |
|---|---:|
| `src/Resources/ClientItemDefinitions.json` | 33,753,727 |
| `src/Resources/NavMeshes/FabledRealms.navmesh` | 31,839,576 |
| `src/Resources/StoreBundles.json` | 3,465,575 |
| `src/Resources/UnlistedClientItemDefinitions.json` | 1,853,190 |
| `src/Resources/CoinStoreItems.json` | 1,598,036 |
| `src/Resources/Npcs.json` | 858,924 |
| `src/Resources/Models.txt` | 427,835 |
| `src/Scripts/Zone/FabledRealms.lua` | 381,989 |
| `src/Resources/QuickChats.json` | 330,127 |
| `src/Resources/Pets.json` | 223,431 |
| `src/Resources/Collections.json` | 214,604 |
| `src/Resources/CollectionNodePools.json` | 151,238 |
| `src/Resources/Maps/FabledRealms.map` | 74,796 |
| `src/Resources/Quests.json` | 59,621 |
| `src/Resources/PointOfInterests.json` | 52,391 |

Across all history, the only image/map/navmesh-like files ever committed are
`images/logo.png`, `images/screenshot.jpg`, `src/Resources/Maps/FabledRealms.map`,
and `src/Resources/NavMeshes/FabledRealms.navmesh`. There are **no client art,
audio, fonts, SWF, texture, or model assets** in this repository. Those are
downloaded by `Sanctuary.DevClient` from the external asset service and are
copyrighted Free Realms content.

Consequence: a 1:1 visual offline client cannot be built from this repository
alone. The server logic and data can be ported, but client visuals require a
separate decision about embedding the downloaded proprietary client payload.

The external client manifest at `https://opensourcefreerealms.com/clientmanifest.xml`
currently lists 1,788 files totaling 893,405,496 bytes (~0.83 GiB). The bulk is
11 `.pack` files (529.5 MiB), 6 `.rcc` files (73 MiB), 29 Windows `.dll` files
(70.5 MiB), and 2 `.exe` files (24.3 MiB). The `.pack`/`.rcc` containers hold
the actual models, textures, sounds, and string tables in proprietary formats;
they are not usable directly by a native iOS renderer without a parser and the
right to redistribute them. Embedding the whole client in an IPA is therefore a
major product/legal decision, not a trivial build step.

## Local compiler

`swift --version` reports Swift 6.4.3 for `x86_64-unknown-linux-gnu` (swift-bin/AUR).
`xcrun` and the iOS SDK are absent, so Linux can validate Foundation-only core
logic and unit tests, but SwiftUI/iOS builds still require the existing macOS
GitHub Actions runner.

The existing XXHash64 implementation compiles and passes its vectors locally:

- empty → `EF46DB3751D8E999`
- `abc` → `44BC2CF5AD770999`

A Foundation-only SwiftPM target in `ios/Package.swift` now runs 8 unit tests on
Linux covering XXH64, URL/path helpers, manifest parsing, and path traversal
rejection. SwiftUI/iOS builds still use the macOS GitHub Actions runner.

## Completed audit reports

- `01-client-bootstrap-and-ci.md`
- `02-resources-and-assets.md`
- `03-protocol-and-servers.md`
- `04-game-logic-and-scripts.md`

## User decisions for the iOS port

- Asset strategy: **embed the original client payload** rather than using native-art fallback.
- Milestone: **full client and server parity**, with offline single-player and the ability to connect to remote Sanctuary-compatible servers.

Both decisions increase scope substantially. Full parity requires a native interpreter/renderer for the proprietary `.pack`/`.rcc` client assets, all Login/Gateway protocols, the 15-table database model, zone/entity/quest/collection logic, Lua script behavior, and the resource catalog. This repository can contain the tooling and sources, but embedding third-party Free Realms assets requires the user to provide or authorize that payload; the asset license is not granted by Sanctuary.
