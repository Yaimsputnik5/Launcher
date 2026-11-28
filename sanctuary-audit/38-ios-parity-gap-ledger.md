# iOS parity gap ledger

This note records the read-only gap audit requested for the full-client
reconstruction effort. It is not a completion claim. It uses the target client
tree at `/home/deadptr/.local/share/OSFRLauncher/Servers/OSFR Public
Server/Client` and the current working tree under `ios/`.

## Verdict

The app is a native Swift launcher with partial source-backed offline world and
gateway codec support. It is **not** a full native Swift 1:1 port. The
repository's own `ios/ARCHITECTURE.md`, `ios/README.md`, and audit notes 13 and
14 already state the parity boundary.

## Current app state

| Measure | Value |
|---|---:|
| App Swift files | 52 |
| SwiftPM core sources | 35 explicit sources |
| Engine sources | 10 |
| Service sources | 25 |
| Views | 11 |
| Renderer files | 1 |
| Test files | 29 |
| Foundation-only tests executed | 261, 1 skipped, 0 failures |

`Package.swift` excludes `Views/`, `Render/`, `AppState.swift`,
`LauncherApp.swift`, Keychain, HTTP, live UDP session, and server-status code
from the Linux test target. Those paths compile only in the Xcode workflow. The
Xcode project has one app target and no test target, so UI/network/Metal code is
not “green by omission” in SwiftPM.

A source grep finds 266 `func test` declarations, but the actual Linux runner
executes 261. Five declarations are conditional or helper paths in this
environment; the documented count remains 261.

## Target client state

Excluding `Logs/`, the target client has 1,797 files / 1,229,239,830 bytes.
Including `Logs/`, the earlier full inventory counted 1,819 files /
1,229,484,889 bytes.

Major areas:

| Area | Files | Bytes |
|---|---:|---:|
| root | 77 | 896,825,221 |
| `tcg/` | 190 | 159,831,738 |
| `assets/` | 2 | 64,615,474 |
| `locale/` | 8 | 44,132,954 |
| `UI/` | 425 | 22,161,520 |
| `Resources/` | 340 | 15,289,396 |
| `Shaders/` | 715 | 12,655,044 |
| `custom/` | 26 | 11,478,973 |

Notable structures include 267 `wnd*.xml` UI modules, 715 `.fxo` shaders, 134
`.cln` TCG collections, and eight locale `.dat`/`.dir` pairs.

## Payload gap

The staged iOS payload has 1,791 files / 893,775,772 bytes versus 1,797 /
1,229,239,830 in the target tree. Nine target files are missing:

| Path | Bytes |
|---|---:|
| `AssetsW_000.pack` | 199,999,814 |
| `AssetsW_001.pack` | 126,326,866 |
| `Assets_manifest.txt` | 9,479,368 |
| `Resources/Images/heads/92481.png` | 9,533 |
| `ThemeParseLog.txt` | 17,529 |
| `UserOptions.ini` | 1,202 |
| `SaveSettings` | 22 |
| `ActivityUserData.ini` | 0 |
| `SavedClientTimers.txt` | 0 |

A read-only directory parse found 2,566 entries in `AssetsW_000.pack` and 2,385
entries in `AssetsW_001.pack`. Dominant entry types are `.dds`, `.dme`, `.gr2`,
`.mp3`, `.cdt`, and `.gcnk`. The staged `assets/assetpack000W_000.pack` is a
different legacy archive with 2,128 mostly-PNG entries.

The current index and manifest reference only the legacy asset pack. No Swift
index exists for `Assets_manifest.txt`, whose 162,652 lines include 152,929
`.z` records and 14,381 `img*.dds.z` records. No generic `.z` loader is wired
into texture loading.

A HEAD request confirmed that the public CDN does not serve
`AssetsW_000.pack`, `AssetsW_001.pack`, or `Assets_manifest.txt`; all return
404. CI cannot obtain those files from the current manifest. This is a concrete
release blocker for “everything included.”

## Explicit placeholders and approximations

- `ClientMinimapAtlas.swift`: only a subset of the 1,920 TileInfo DDS files is
  available; missing tiles are omitted, not invented.
- `ClientTerrainPalette.swift`: environment-to-material mapping is a
  presentation heuristic, not the original engine rule.
- `GameWorld.swift`: NPC positions, wandering, and drop rolls are simplified;
  quest prerequisites, rewards, and goal rules are intentionally not simulated.
- `GatewayProtocol.swift`: nested-serializer packets remain `.mapped` and keep
  raw bytes verbatim; mapped payloads never synthesize remote state.
- `StartingZoneLoadRow`: descriptor only; it does not execute Lua or load asset
  files.
- `MetalWorldView.swift`: minimal 2D Metal renderer, not the desktop 3D engine.
- No audio playback, locale `.dat`/`.dir` reader, FXO shader decoder, Granny
  mesh decoder, or TCG rules engine exists.

## Feature status summary

Implemented or implemented for stated scope:

- launcher shell, manifests, downloads/resume, server status;
- Keychain/settings persistence;
- WebAPI sign-in/register plumbing;
- login UDP framing and gateway handshake/AES-CCM/reliable IDs;
- bounded offline world simulation and native engine loop;
- container parsing for legacy packs/RCC and TGA/DDS/PNG decoding;
- 136 typed world packet cases plus raw-preserving fallback.

Partial or raw-only:

- live continuous gameplay state;
- outbound movement/chat/position diagnostics;
- world packet semantics with unresolved nested serializers;
- offline NPC drops/wandering/quest rules;
- textures/minimap and material fidelity;
- locale, UI, trade/store/guild/housing/combat/quest flows.

Missing:

- real world-pack asset index and `.z` decoder;
- audio playback;
- TCG rules/UI;
- FXO/Granny/DME/CDT reconstruction;
- 267 target UI modules;
- Lua callback execution or native equivalents;
- Xcode test target covering app UI/network/render code.

Intentional iOS substitutions:

- no Discord Rich Presence, Velopack, Wine, DirectX, Windows process launch, or
  desktop installer migration.

## Build/release blockers

- Verified release IPA remains stale: build commit
  `c39369d65865feebdbbb60674d208817408495e0`, Actions run `46081101414`,
  SHA-256 `e5a48f13bab8da1daa4c9a5c26475f57855cd2e49176665cf251baed7ec21307`.
- Recent commits have zero check suites; push-event delivery is unresolved.
- Local `ios/Launcher.ipa` is 375,201,080 bytes with SHA-256
  `e20cb582d77df157dc4338e69cea6f49342720e095b7403aacd5fad9c8bfdd1d`, so it
  does not match the verified release digest and must not be published.
- No physical iOS device is available from this host.
- No account credential was available, requested, stored, or used.

## Prioritized obligations

1. Produce a fresh IPA from current source and verify head SHA, `unzip -tq`,
   size, SHA-256, and bundle identity.
2. Add an Xcode test/build path that compiles and tests UI, network, Keychain,
   live UDP, and Metal code rather than relying only on SwiftPM core tests.
3. Make the real world packs and `Assets_manifest.txt` available to CI by an
   auditable source; the current CDN returns 404.
4. Implement and test the `Assets_manifest.txt` index plus bounded `.z` payload
   decoding, then route decoded `img*.dds.z` entries through texture loading.
5. Replace sparse minimap/material coverage with verified world-pack entries.
6. Decode representative FXO shaders and Granny/DME/CDT geometry for a native
   Metal equivalent; do not claim full renderer parity until tested visually.
7. Convert staged Lua scripts and the four verified starting-zone rows into
   native callbacks or record each as an unresolved obligation.
8. Replace simplified reward, quest, NPC, and combat behavior with
   source-backed rules and fixtures.
9. Port the 267 UI modules to named Swift views with coverage.
10. Implement locale string tables, audio, and TCG rules/UI.
11. Complete continuous remote gameplay synchronization without raw packet
    fabrication.
12. Perform device checklist validation on a freshly verified IPA.

## Limits

This ledger is based on static source/artifact inspection and the Linux test
runner. No Windows executable was run, no live account was used, and no iOS
device was available. It does not establish full 1:1 parity.
