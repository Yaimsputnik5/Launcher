# OSFR Launcher for iOS (SwiftUI)

This is a native iOS rewrite of the launcher. It is a **separate app** under `ios/`; the existing Avalonia/.NET launcher under `src/` is unchanged.

## Scope

Supported:

- Ships with the original launcher's single default server, `https://opensourcefreerealms.com`, refreshed from `servermanifest.xml` (v1 and v2).
- Add/delete servers from `servermanifest.xml` (v1 and v2).
- Refresh server status over the original UDP status protocol (port 20042).
- Fetch `clientmanifest.xml`, verify existing files with XXH64, download missing or changed files, and verify every download before replacing the local copy.
- Sign in/register against the server web API and complete a native Sanctuary `LoginUdp_6` game-session handshake.
- Remember usernames and passwords using the iOS Keychain.
- Persist settings and server metadata as JSON in the app sandbox.
- Add non-loopback HTTP servers only after an explicit warning and confirmation;
  account credentials are accepted and stored only for HTTPS or loopback servers.

In progress toward full parity:

- The app shell now has **Launcher**, **Play Offline**, **World**, **Join Server**, **Downloads**, and **Diagnostics** sections.
- Sanctuary server data is staged into `Launcher.app/SanctuaryResources` at build time.
- The original client payload can be staged into `Launcher.app/ClientAssets` at build time and verified with XXH64.
- The original Launcher and Sanctuary C# projects were compiled on Linux and their managed assemblies inspected with REA; see `sanctuary-audit/05-compiled-binaries-and-rea.md`.
- The **World** tab is gated on a real active session: it does nothing until an Offline game is started or a gateway join succeeds. A WebAPI login, cached manifest, or embedded client payload never unlocks it. This prevents a fake or preloaded world instance.
- Offline host settings are persisted and actually consumed by the simulation: starting zone, profile name, player name, unlock-all-profiles, unlock-all-titles, unlock-all-tiles, coins, station cash and locale. `unlockAllTiles` changes walkability, not just a HUD label. Profile/title unlock lists are derived from bundled Sanctuary data. NPC coordinates are explicitly marked as inferred because `Npcs.json` ships no spawn positions.
- The **World** tab is backed by Sanctuary zone, collection-spawn, quest and NPC data. It runs 10 Hz/1 Hz simulation ticks, gathers exact collection nodes, advances quest goals, persists per-goal progress, grants items and persists a local character.
- A native in-process engine (`OSFREngine`) owns fixed-step advancement, input, an entity registry, an orthographic camera and a layered scene graph. `MetalWorldView` renders engine frames with a Metal pipeline; no Windows executable, Wine, DirectX, or process execution is used.
- Native TGA/DDS decoders read the original client textures from `.tga`, `.dds`, `.pack` and `.rcc` sources, and the engine asset pipeline caches decoded textures by manifest-relative path.
- Native Login UDP authentication performs the complete WebAPI → session → character select → character login flow, and a native gateway UDP transport opens the real `CGAPI_527` connection with the server-supplied ticket, GUID and AES-CCM session. Gateway reliable IDs start at zero, matching `UdpReliableChannel.ReliableIncomingId`; earlier builds acknowledged but never delivered `PacketLogin` and timed out during Join World. The documented client hello sends locale through `PacketTunneledClientWorldPacket` and initialization/finished/ready through `PacketTunneledClientPacket`, matching Sanctuary's handler routing. Continuous gameplay/world packets beyond that hello are not yet simulated.
- Foundation-only protocol, resource, container, image, gateway, world-simulation, local-session and engine layers have Linux XCTest coverage (261 tests, 1 skipped).

Not supported on iOS:

- Launching `FreeRealms.exe`, Wine, or DirectX 9. The game logic and rendering must be native/in-process; no Windows executable is ever run.
- Discord Rich Presence (the vendored Discord Game SDK has no iOS binary in this repository).
- Velopack self-updates, Windows/macOS/Linux installers, and desktop setting migration.

## Requirements

- macOS with Xcode 15 or later (iOS 17 SDK).
- An iOS 17+ device.
- AltStore or SideStore to install the IPA.

## Build and side-load

1. Open `ios/Launcher.xcodeproj` in Xcode and inspect the signing settings.
   - The bundle identifier is `dev.opensourcefreerealms.launcher` in
     `Launcher.xcodeproj/project.pbxproj`.
   - Change it before first install if you want a different identity. The iOS
     Keychain is scoped to this bundle ID, so changing it later loses remembered
     passwords.
2. Stage server data and optionally embed the original client payload:

   ```bash
   # Sanctuary server data (AGPL-3.0 code/data); set SANCTUARY_DIR if it is elsewhere.
   SANCTUARY_DIR=/path/to/Sanctuary ios/scripts/sync_sanctuary_resources.sh

   # Original client payload; only do this if you have the right to redistribute it.
   IOS_EMBED_CLIENT=1 ios/build_ipa.sh
   ```

   The iOS GitHub Actions workflow (`Build iOS IPA`) performs both staging steps
   on a free macOS runner and can publish the result to the `ios-ipa` release.
3. Build an unsigned IPA:

   ```bash
   cd ios
   ./build_ipa.sh
   ```

   The script uses `CODE_SIGNING_ALLOWED=NO`, builds `Launcher.ipa`, and leaves
   signing to AltStore/SideStore.
4. Open AltStore or SideStore, choose **Install IPA**, and select
   `ios/Launcher.ipa`. The store app applies your Apple ID signature.
5. Trust the developer certificate on the device if prompted.

If you prefer signing directly from Xcode, set your own Team in the target
signing settings and use **Product → Archive** instead of the script.

### CI build settings

`.github/workflows/ios-build.yml` runs on `workflow_dispatch` and on every push
to `ios-build`. For push-triggered runs the settings come from files in the
repository, so no repository-dispatch credentials are needed:

| File | Meaning |
|---|---|
| `ios/ci-config/embed-client.txt` | `1` embeds the 0.83 GiB original client payload; `0` builds without it |
| `ios/ci-config/publish-release.txt` | `1` publishes the IPA to the `ios-ipa` release and skips the 500 MB artifact upload |

`workflow_dispatch` inputs override those files. Only enable publishing if you
hold the rights to redistribute the embedded third-party game content. Every run
also publishes its build log to the `ios-build-log` release, which is the
quickest way to diagnose a failed macOS build.

## Where data lives

| Data | Location |
|---|---|
| Settings/server list | `Application Support/OSFRLauncher/settings.json` |
| Downloaded client files | `Application Support/OSFRLauncher/Servers/<server>/Client/...` |
| Embedded client payload | `Launcher.app/ClientAssets/...` (build-time only, ignored by git) |
| Embedded Sanctuary data | `Launcher.app/SanctuaryResources/...` (build-time only, ignored by git) |
| Remembered passwords | iOS Keychain, service `<bundle-id>.passwords`, account = server UUID |
| Logs | `Application Support/OSFRLauncher/Logs/` (rotating, 2 MiB × 4 files) |

Files are shared through the Files app because `UIFileSharingEnabled` is set.

## How the port maps to the C# launcher

| C# | Swift |
|---|---|
| `Launcher.csproj` / Avalonia | `Launcher.xcodeproj` / SwiftUI |
| `Settings.Instance` XML | `AppState` + `AppSettings` JSON |
| `CredentialHelper` + Data Protection | `CredentialStore` + Keychain |
| `HttpHelper.GetServerManifestAsync` | `HTTPClient.serverManifest` |
| `HttpHelper.GetClientManifestAsync` | `HTTPClient.clientManifest` |
| `XmlHelper` + embedded XSDs | `ServerManifestParser` / `ClientManifestParser` |
| `HashDepot.XXHash.Hash64` | `XXHash64.hash` |
| `Downloader.DownloadService` | `HTTPClient.downloadFile` with `URLSession.AsyncBytes` |
| `ServerStatusHelper` | `ServerStatusClient` (Network.framework UDP) |
| `ViewModels/*` + `Views/*` | `AppState` / `ServerRuntime` + SwiftUI views |
| Sanctuary `UdpLibrary` / `LoginUdp_6` | `ProtocolPrimitives`, `LoginProtocol` and `LoginUDPSession` (session + character flow) |
| Sanctuary gateway `CGAPI_527` | `GatewayProtocol` codecs and `GatewayUDPSession` UDP transport |
| Sanctuary `Resources/*` | `ResourceCatalog` typed loaders |
| Sanctuary `BaseZone` / `CollectionNode` / `QuestManager` | `WorldSimulation` and `CollectionSpawnCatalog` |
| Sanctuary starting zone / profile and title unlock data | `LocalHostConfiguration` + `ResourceCatalog` + `WorldPlayOptions` |
| Sanctuary world database | `LocalSession` offline JSON store (first layer) |
| Native game loop / scene / input / texture cache | `OSFREngine`, `EngineSceneGraph`, `EngineAssetPipeline` |
| Client render surface | `MetalWorldView` (MetalKit, no desktop executable) |
| Free Realms `.pack` / `.rcc` | `AssetContainers` verified readers |
| Free Realms `.tga` / `.dds` textures | `ImageCodecs` RGBA8 decoders |
| `DiscordService`, `WineHelper`, `Dx9Helper` | Intentionally omitted; no iOS equivalent in this repo |

## Deliberate safety fixes in the port

- Server identities are stable UUIDs, not URLs, so editing a URL does not lose
  remembered credentials.
- Manifest names are validated as single path components; `..`, absolute paths,
  separators, and control characters are rejected.
- Downloads go to a `.part` temp file, are size- and XXH64-verified, then
  atomically replace the destination.
- API paths are appended correctly instead of replacing the last path segment
  of the server's base URL.
- Duplicate servers are rejected.
- Embedded `user:pass@host` URLs are rejected.

## Verification status

A real unsigned IPA with the full all-in-one UI, the embedded original client
payload, and the Sanctuary server data was compiled on a free GitHub Actions
macOS runner:

- Workflow run: <https://github.com/YaimSputnik5/Launcher/actions/runs/46081101414>
- Built commit: `c39369d65865feebdbbb60674d208817408495e0`
- Release: <https://github.com/YaimSputnik5/Launcher/releases/tag/ios-ipa>
- Local artifact: `ios/Launcher.ipa` (375,200,997 bytes)
- SHA-256: `e5a48f13bab8da1daa4c9a5c26475f57855cd2e49176665cf251baed7ec21307`

Current `ios-build` source is newer than the verified IPA: the direct bundled
resource path fix begins at `f568a64430e6a36cb1fae22c2d6dd4a0225d84e4`
(`Resolve bundled resources without path containment under LiveContainer`), and
the packet catalog work is at `c43ae1efcc31b74389120c535050b6209ab11830`
(`Map Sanctuary packet catalog and preserve known raw packets`). A fresh IPA has
not been published for those commits: GitHub reported zero Actions runs and zero
check suites through `2c46b519a6a8858b318a3cb291e99d3cb2a921be`. Two 2026-11-28
control commits written through different GitHub APIs (`cf6c856` and `853754d`,
neither marked `[skip ci]`) also produced zero runs. A maintainer must trigger
`Build iOS IPA` manually on `ios-build` or restore push-event delivery for
`YaimSputnik5/Launcher`. The verified release below remains the last built
artifact and does not include these source changes. The newer source work is documented in
`sanctuary-audit/15-packet-catalog-and-config-xrefs.md`,
`sanctuary-audit/16-offline-host-settings-wiring.md`,
`sanctuary-audit/17-embedded-lua-and-gameplay-boundary.md`,
`sanctuary-audit/18-simple-packet-decoders-and-xcode-target.md`,
`sanctuary-audit/19-starting-zone-options-and-row-consumer.md`,
`sanctuary-audit/20-lua-command-table-and-name-formatting.md`,
`sanctuary-audit/21-trade-packet-codecs.md`,
`sanctuary-audit/22-store-bundle-codec.md`,
`sanctuary-audit/23-additional-store-catalog-codecs.md`,
`sanctuary-audit/24-client-starting-zone-loader-rtti.md`,
`sanctuary-audit/25-additional-commerce-response-codecs.md`,
`sanctuary-audit/26-broadcast-and-housing-zone-codecs.md`,
`sanctuary-audit/27-client-starting-zone-loader-call-sites.md`,
`sanctuary-audit/28-starting-zone-lua-dispatch.md`,
`sanctuary-audit/29-external-login-scalar-replies.md`,
`sanctuary-audit/30-trade-handshake-codecs.md`,
`sanctuary-audit/31-housing-instance-list-codec.md`,
`sanctuary-audit/32-ui-script-dispatch-codecs.md`,
`sanctuary-audit/33-raw-payload-packet-boundaries.md`,
`sanctuary-audit/34-ci-trigger-verification.md`,
`sanctuary-audit/35-scalar-reply-codec-expansion.md`,
`sanctuary-audit/36-starting-zone-loader-and-callback.md`,
`sanctuary-audit/37-full-client-reconstruction-charter.md` and
`sanctuary-audit/38-ios-parity-gap-ledger.md`; none of those notes claims full
compiled-client or Lua/gameplay parity. Note 37 defines the evidence rules and
acceptance conditions for the requested complete port, and note 38 records the
concrete implementation, asset, build, and device gaps still open. Note 18 records an
Xcode project omission that would have broken a build of the newer source, and
the subsequent correction of a 25-packet batch: seven packets whose C#
`Serialize()` calls nested serializers were removed, and seven exact scalar-only
`BasePlayerUpdatePacket` layouts were added instead. The removed packets still
retain their raw bytes through the catalog fallback. Note 19 resolves the
`StartingZone` argument to a resource prefix (`StartingZone` or empty) that
selects zone-specific option/controller/help files, and narrows the
`StartingZoneLoad.txt` parser to one startup call site; it does not claim the
parsed row list has a recovered consumer. Note 20 corrects `fcn.0097c090` to a
localized name/template formatter and maps the data-driven Lua command
registration table, without claiming Lua script semantics. Note 21 adds five
exact scalar trade decoders and a scalar-only nested `ItemInstance` codec;
packets with unresolved nested serializers still retain raw bytes. Note 22
decodes 66/5 store bundles through the exact nested `StoreDefinition`,
`AppStoreBundleDefinition`, `StoreBundleDefinition`, and
`MarketingBundleDefinition` `Serialize()` field order. Note 23 adds exact
decoders for 66/6 category groups, 66/7 category tree, 66/9 bundle groups,
66/11 wallet info, 66/23 subscription products, and 66/40 sale display from
their verified `Serialize()` order, including the conditional subscription
list. Note 24 verifies `ClientStartingZoneLoader` RTTI inheritance from
`StatusHandler<DelayedAssetLoader>` and its exact two-slot virtual table; notes
27 and 28 later locate the construction/parse/dispatch call sites and a
Lua-facing callee without claiming full field or script semantics. Note 25 adds
exact decoders for 66/2 preview orders, 66/4 place orders, 66/17 currency codes,
66/19 state codes, 66/21 country codes, 66/26 account info, 66/28 bundle
content responses, and 66/39 item requirement updates. Note 26 adds 77/2 zone
broadcasts and 127/45 housing zone data with the verified nested
`PlayerHousingInstanceInfo` layout; all still-unresolved store sub-opcodes
retain raw bytes. Note 27 locates the compiled client's `ClientStartingZoneLoader`
constructor, destructor, `Resources/` row-reader call site, and two virtual slots:
the reader builds `%sStartingZoneLoad.txt`, skips `#` comments and rows with fewer
than three `^` separators, while slot 0 walks a per-row count before selecting the
next entry. Note 28 resolves slot 0's first callee as a Lua-facing loader/registrar
by its `LuaErrors.log` literal, typed-value pusher, and 160-byte record loop. Note
36 resolves the Lua C API callees, confirms `row+4` as `IS_BACKGROUND_LOAD` from
the parsed `0x00726440` write, reconstructs `HUD.StartingZoneLoaded` from
`ScriptsBase.bin`, and adds a native descriptor parser for the four verified
rows; it does not execute Lua or claim renderer parity. Note 29 decodes
login opcodes 4 and 6 from their exact C# `Serialize()` order and turns
`ForceDisconnect` into a terminal login failure; character creation remains
unimplemented and the live UDP failure path is not covered by Linux tests. Note
30 decodes trade invite, session-start, and rejection packets through the
verified `NameData` order while keeping unresolved trade opcodes raw; no trade
UI or outbound trade protocol is claimed. Note 31 decodes 127/39 housing
instance lists through the already verified nested housing layout with a bounded
count; 127/28 remains raw because its C# serializer is unresolved. Note 32
decodes 47/7 and 47/8 as UI method selectors and arguments without executing
them, and consolidates the 47 switch so 47/14 remains decoded. Note 33 decodes
the exact length-prefixed boundaries of 57, 149/1, and 152/3 while retaining their
payload bytes verbatim; their inner formats remain unresolved. Note 34 records
that neither bulk tree commits nor a contents-API control commit produced check
suites, so a maintainer must trigger the active workflow manually; it does not
claim that a fresh IPA exists. Note 35 adds 29 exact scalar or bounded-loop
reply codecs (chat, command, player/collection, pet, quick chat, friend/ignore,
housing, guild, name change, and journal) while keeping unresolved nested
serializers raw; it also records an opcode-35 routing shadow that the fixtures
caught and corrected. Note 36 completes the starting-zone loader REA, resolves
the Lua C API names and the exact `HUD.StartingZoneLoaded` bytecode, and adds a
native load-plan descriptor; no Lua execution or full gameplay parity is claimed.

Bundled resources now use validated relative components appended directly to
the trusted `Bundle.main` root; there is no path-string prefix comparison and
no symlink resolution for read-only bundle files. That avoids a LiveContainer
canonical path such as
`/private/var/mobile/Containers/Shared/AppGroup/.../LiveContainer/Applications/dev.opensourcefreerealms.launcher.app/SanctuaryResources/Npcs.json`
being rejected because it does not literally share the bundle prefix. Writable
roots still require symlink-resolution containment checks, so escape symlinks
cannot redirect a download or persisted file. Path-traversal, separator, NUL,
control-character, and dot-segment validation remain active for bundled
resources.

Both the IPA build and the release-publishing steps succeeded. The checksum above
was read from the GitHub release asset digest and verified against a fully
downloaded copy: `unzip -t` reported no errors, the executable begins with the
arm64 Mach-O magic `cffaedfe`, and `Info.plist` reports bundle ID
`dev.opensourcefreerealms.launcher`, display name `OSFR Launcher`, version
`1.0.0` (`1`), and `MinimumOSVersion` `17.0`.

The embedded payload index lists 1,788 client files (893,405,496 bytes) and the
Sanctuary manifest lists 101 files (75,740,078 bytes from commit
`f5240b7554f2a80d6b815cb7ead7ffee12499565`). It was built with
`CODE_SIGNING_ALLOWED=NO`, so AltStore/SideStore must apply your signature.
The app has not been launched on a physical device from this Linux host; that
final runtime check requires your iOS device and side-loading app.

Foundation-only logic is verified locally:

```bash
swift test --package-path ios
```

The 261 tests (1 skipped) cover XXH64, URL/path safety, manifest v1/v2 and
case-insensitive manifest locales, embedded-payload manifest matching, packet primitives,
CRC32, RC4, GUID layout, WebAPI login response decoding, login framing/messages,
gateway AES-CCM, opcode codecs, scalar hitpoints/mana/effect-tag/quest/pet/
trade/membership/friend/mount/player-update/client-area/MOTD/animation/composite-effect,
chat/command/collection/quick-chat/ignore/housing/guild/name-change/journal
decoders and reliable-ID sequencing, the 352-class
Sanctuary packet routing catalog (including wire-type overlap and source
direction hints) and raw-payload preservation, byte/int/short sub-opcode
routing for mapped fallback, `.pack`/`.rcc`
parsing, TGA/DDS decoding, Sanctuary resource schemas, zone/collection/quest
simulation, offline account/character persistence, host setting application
(including live in-world updates and non-default starting-zone spawn), world
gating, fixed-step engine advancement, input events, camera projection, entity
registration, scene layering, and verified `StartingZoneLoad.txt` row parsing.
Packets whose C# serializer delegates to
nested codecs remain raw-preserving `.mapped` packets and set no fabricated
observation state. SwiftUI and iOS framework code can only be compiled by the
macOS workflow.

## Device-side verification checklist

No physical iOS device is available on the build host. Please test the published
IPA on your own device with AltStore or SideStore and report results with the
IPA SHA-256, iOS version, device model, and exact steps. Never send account
credentials.

1. **Launcher**: add/refresh the public server, confirm UDP status, download or
   verify the client payload, and watch progress/resume after backgrounding.
   Backgrounding during a download should show `Cannot close the launcher while
   downloading.` and the stable `.part` file should resume on next launch.
2. **Join Server**: sign in with your own account on an HTTPS server; confirm
   WebAPI → session → character select → character login → gateway join. Before
   join succeeds, **World** must do nothing. After join, **World** must show only
   decoded packet-derived state, with no offline/static art injected.
3. **Play Offline**: start an offline game, then confirm the World tab activates.
   Change starting zone, profile name, player name, unlock-all-profile,
   unlock-all-titles and unlock-all-tiles; restart and verify each setting is
   still persisted and consumed by the simulation. Confirm unlock-all-tiles
   changes walkability and click-to-move follows pathfinding waypoints.
4. **Diagnostics**: confirm logs are present and shareable, with no credentials
   or request bodies in log lines.
5. **Limits**: note any missing art, sparse minimap tiles, visual differences,
   timing stalls, disconnects or unexpected world data. These are expected gaps
   until the compiled-client and live-session reconstruction is complete; do not
   describe them as 1:1 parity.
