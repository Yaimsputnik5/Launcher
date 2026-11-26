# OSFR Launcher for iOS (SwiftUI)

This is a native iOS rewrite of the launcher. It is a **separate app** under `ios/`; the existing Avalonia/.NET launcher under `src/` is unchanged.

## Scope

Supported:

- Add/delete servers from `servermanifest.xml` (v1 and v2).
- Refresh server status over the original UDP status protocol (port 20042).
- Fetch `clientmanifest.xml`, verify existing files with XXH64, download missing or changed files, and verify every download before replacing the local copy.
- Sign in/register against the server web API.
- Remember usernames and passwords using the iOS Keychain.
- Persist settings and server metadata as JSON in the app sandbox.
- Allow custom HTTP servers via App Transport Security (HTTPS is still recommended).

In progress toward full parity:

- The app shell now has **Launcher**, **Play Offline**, **Join Server**, **Downloads**, and **Diagnostics** sections.
- Sanctuary server data is staged into `Launcher.app/SanctuaryResources` at build time.
- The original client payload can be staged into `Launcher.app/ClientAssets` at build time and verified with XXH64.
- Foundation-only protocol, resource, container, and local-session layers are being added with Linux XCTest coverage.

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
| Logs | No file logging yet; use Xcode console/Console.app |

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
| Sanctuary `UdpLibrary` / `LoginUdp_6` | `ProtocolPrimitives` + `LoginProtocol` messages |
| Sanctuary `Resources/*` | `ResourceCatalog` typed loaders |
| Sanctuary world database | `LocalSession` offline JSON store (first layer) |
| Free Realms `.pack` / `.rcc` | `AssetContainers` verified readers |
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

- Workflow run: <https://github.com/YaimSputnik5/Launcher/actions/runs/45827062087>
- Release: <https://github.com/YaimSputnik5/Launcher/releases/tag/ios-ipa>
- Local artifact: `ios/Launcher.ipa` (374,293,953 bytes)
- SHA-256: `c9bee49449b0b2f50031882ba13f351e883f5fb59b6c9349f199bc5d01046a7e`

The archive contains an arm64 `Mach-O` executable and an `Info.plist` with
bundle ID `dev.opensourcefreerealms.launcher`, display name `OSFR Launcher`,
version `1.0.0` (`1`), and `MinimumOSVersion` `17.0`. It embeds 1,788 client
files (893,405,496 bytes) and 101 Sanctuary files (75,740,078 bytes from commit
`f5240b7554f2a80d6b815cb7ead7ffee12499565`). It was built with
`CODE_SIGNING_ALLOWED=NO`, so AltStore/SideStore must apply your signature.
The app has not been launched on a physical device from this Linux host; that
final runtime check requires your iOS device and side-loading app.

Foundation-only logic is verified locally:

```bash
swift test --package-path ios
```

The 55 tests cover XXH64, URL/path safety, manifest v1/v2, packet primitives,
CRC32, RC4, GUID layout, login framing/messages, `.pack`/`.rcc` parsing,
Sanctuary resource schemas, and offline account/character persistence. SwiftUI
and iOS framework code can only be compiled by the macOS workflow.
