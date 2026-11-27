# Desktop launcher divergences and iOS substitutions

This note records the places where the native iOS launcher intentionally does
**not** reproduce the Windows/macOS/Linux Avalonia launcher. The C# source and
the compiled managed assemblies remain the authority for desktop behavior; the
substitutions below follow iOS sandbox and distribution constraints. They are
supportable ports, not claims of literal 1:1 parity.

## Source authority

- `src/Launcher/Program.cs` — NLog setup and Velopack initialization.
- `src/Launcher/App.axaml.cs` — `GitHubRepoUrl`, `UpdateManager`,
  `CheckForUpdatesAsync`.
- `src/Launcher/ViewModels/Main.cs` — `CheckForUpdates`, `OpenLogsAsync`.
- `src/Launcher/Services/DiscordService.cs` — Discord Rich Presence.
- `src/Launcher/Resources/Texts.axaml` — exact close-guard message.
- `src/Launcher/ViewModels/Server.cs` — download/verify flow.
- `ios/Launcher/Services/LaunchLog.swift`, `ios/Launcher/Services/HTTPClient.swift`,
  `ios/Launcher/AppState.swift`, `ios/Launcher/LauncherApp.swift`,
  `ios/Launcher/Views/DiagnosticsView.swift` — iOS counterparts.

## Divergences

| Desktop behavior | iOS behavior | Why it diverges |
|---|---|---|
| Velopack self-update targets `https://github.com/Open-Source-Free-Realms/Launcher` (`App.axaml.cs:29-30`, `Program.cs:41`). `CheckForUpdatesAsync` downloads and calls `ApplyUpdatesAndRestart` (`App.axaml.cs:65-99`). | No in-app update manager. IPA is built and published by `.github/workflows/ios-build.yml`; installation and replacement happen through AltStore/SideStore. | iOS sandbox does not permit an arbitrary desktop-style updater to replace the running app bundle. The signed/unsigned IPA pipeline is the supported distribution path. |
| Discord Rich Presence uses client ID `1223728876199608410`, `CreateFlags.NoRequireDiscord`, and a 60 Hz callback loop (`DiscordService.cs:19,39,49,83`). | No Discord SDK dependency and no Rich Presence state. | Adding an external native SDK would violate the Foundation-only core/no-external-app-dependencies constraint and would not be testable on Linux. |
| NLog writes `logs/Launcher.log` through a `FileTarget` with `DeleteOldFileOnStartup = true` and no size-based rotation (`Program.cs:65-78`). | `LaunchLog` writes timestamped, level-tagged single-line entries to the sandbox logs directory, rotating at 2 MiB and retaining four files. Lines are flattened and callers never pass credentials or request bodies. | Preserves useful diagnostics while bounding long-lived iOS storage. |
| `OpenLogsAsync` asks the desktop shell to open the logs directory (`Main.cs:126-147`). | Diagnostics shows the current log inline and exposes current plus rotated files through `ShareLink`. | A sandboxed iOS app cannot open an arbitrary directory in Finder/Explorer. Sharing the files is the closest available action. |
| Avalonia `OnClosing` can refuse to close during a download and shows exactly `Cannot close the launcher while downloading.` | The same exact string is emitted as a persistent notice when the app backgrounds with active downloads. UIKit also requests background time and keeps the screen on; stable `.part` files are detected on next launch and resumed by Prepare. | iOS cannot cancel the OS home gesture or app termination. The notice, background task, and resumable partial file replace the impossible close veto. |
| The desktop downloader calls `File.Create` on a destination and does not verify after copy; an interrupted copy can leave a truncated final file. | Downloads write `<destination>.part`, use HTTP `Range` when a valid partial exists, verify size and XXH64 before atomic replacement, and restart cleanly if the server ignores or contradicts the range. | Avoids reproducing the known desktop corruption path while keeping already-downloaded bytes reusable. |
| Desktop UI code updates `StatusMessage` from parallel download workers. | All observable state writes are marshalled to `@MainActor`; HTTP and hashing work stays off the main actor. | SwiftUI concurrency safety; this deliberately does not copy the C# data race. |
| Desktop can launch `FreeRealms.exe` via `Process.Start`. | The app never executes files. Embedded `FreeRealms.exe` is data for verification/audit only; gameplay is native/in-process. | iOS forbids process execution and Windows PE loading. |

## What was preserved

- HTTPS-or-loopback restriction for credentials, Keychain storage, JSON settings,
  manifest v1/v2 parsing, XXH64 verification, UDP status, and download progress
  follow the C# behavior documented in audits `01`–`04`.
- The close-guard string is byte-for-byte the C# resource string, even though
  the mechanism differs.
- Native engine, protocol, and asset parsing consume the same staged client and
  Sanctuary resources; no Windows executable is run.

## Verification and limits

- Foundation-only Linux suite: `swift test --package-path ios --scratch-path
  /tmp/opencode/osfr-swift-test-chunks` — 206 tests, 1 skipped, 0 failures.
- iOS/SwiftUI/UIKit compile and IPA creation are verified by GitHub Actions on
  `macos-15-intel`, not on this Linux host.
- This note does not claim feature parity for Discord, in-app updates, or exact
  desktop lifecycle behavior. Those gaps remain explicit known divergences.
