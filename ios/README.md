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

Not supported on iOS:

- Launching `FreeRealms.exe`, Wine, or DirectX 9. iOS cannot execute the desktop client, so **Play** becomes **Download / Verify Client** followed by a desktop-only notice.
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
2. Build an unsigned IPA:

   ```bash
   cd ios
   ./build_ipa.sh
   ```

   The script uses `CODE_SIGNING_ALLOWED=NO`, builds `Launcher.ipa`, and leaves
   signing to AltStore/SideStore.
3. Open AltStore or SideStore, choose **Install IPA**, and select
   `ios/Launcher.ipa`. The store app applies your Apple ID signature.
4. Trust the developer certificate on the device if prompted.

If you prefer signing directly from Xcode, set your own Team in the target
signing settings and use **Product → Archive** instead of the script.

## Where data lives

| Data | Location |
|---|---|
| Settings/server list | `Application Support/OSFRLauncher/settings.json` |
| Downloaded client files | `Application Support/OSFRLauncher/Servers/<server>/Client/...` |
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

The Swift sources were written to compile with the iOS 17 SDK, but this Linux
working environment has no Swift compiler or Xcode, so the IPA was **not**
built or run here. `ios/build_ipa.sh` is the macOS verification step.
