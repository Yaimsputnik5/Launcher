# Compiled binaries and REA/Ghidra verification

This report records the requested binary-side verification of the two upstream
C# projects. It supplements the source audits in `00-overview.md` through
`04-game-logic-and-scripts.md`; it does not replace them.

Sources:

- Launcher: <https://github.com/Open-Source-Free-Realms/Launcher>
- Sanctuary: <https://github.com/Open-Source-Free-Realms/Sanctuary>, audited at
  `f5240b7554f2a80d6b815cb7ead7ffee12499565`
- Local Launcher source: `src/` in this repository
- Local Sanctuary source: `/tmp/opencode/sanctuary`

All build and analysis output was kept in `/tmp/opencode/rea-build`; no upstream
source, repository file, or credential was modified.

## Builds

Environment: .NET SDK `10.0.114`, Ghidra `12.2`.

### Launcher

```sh
dotnet build /tmp/opencode/rea-build/launcher/Launcher/Launcher.csproj -c Release -v minimal
dotnet publish /tmp/opencode/rea-build/launcher/Launcher/Launcher.csproj \
  -c Release -r win-x64 --self-contained false \
  -o /tmp/opencode/rea-build/publish-win-x64/launcher
```

Result: success, 10 warnings (NuGet advisories for
`System.Security.Cryptography.Pkcs`/`Xml` 10.0.10), 0 errors. TFM `net10.0`;
`OutputType=WinExe`; `PublishReadyToRun=true`; Avalonia 12.0.4, Downloader 5.8.0,
HashDepot 3.2.0. Client XSDs are embedded resources.

| Artifact | SHA-256 |
|---|---|
| `bin/Release/net10.0/Launcher.dll` | `0327df5ff0fb84ea51b5d844d3079ac80cd7f32e515d625b0297999e9142244e` |
| `bin/Release/net10.0/Launcher` | `8186d860341310c7bd64a535010bdfe1b367601cd7a2d10b7e265a8057479486` |
| `publish-win-x64/launcher/Launcher.exe` | `e84d728af6805136f779768e9c370baa7ee1db71861f6765aefe69f663ebe3ef` |
| `publish-win-x64/launcher/Launcher.dll` | `ab87db3490c9d4d7d2cd369dbacacc3b80cf597af48281b114293541747e4dc8` |
| `publish-win-x64/launcher/Downloader.dll` | `522493b6528e793f2cc23b55c3de943aa633d2ec838b7d477e18695d737a4655` |
| `bin/Release/net10.0/Downloader.dll` | `6dd29e94a3075c3a02e9ab73eb5d209eba2775dbd506fa84d14de13cc288e84d` |

The two `Downloader.dll` files have different bytes but the same REA MVID
`db98074d-606a-4914-979f-e698affc5e41`, consistent with ReadyToRun publishing.

### Sanctuary

Sanctuary's README requires the .NET 10 SDK to build while the projects target
.NET 9. The `Directory.Packages.props` target was used explicitly:

```sh
dotnet build /tmp/opencode/rea-build/sanctuary/src/Sanctuary.slnx \
  -p:TargetFramework=net9.0 -c Release -v minimal
dotnet publish /tmp/opencode/rea-build/sanctuary/src/Sanctuary.Gateway/Sanctuary.Gateway.csproj \
  -c Release -r win-x64 --self-contained false -p:TargetFramework=net9.0 \
  -o /tmp/opencode/rea-build/publish-win-x64/sanctuary-gateway
dotnet publish /tmp/opencode/rea-build/sanctuary/src/Sanctuary.WebAPI/Sanctuary.WebAPI.csproj \
  -c Release -r win-x64 --self-contained false -p:TargetFramework=net9.0 \
  -o /tmp/opencode/rea-build/publish-win-x64/sanctuary-webapi
dotnet publish /tmp/opencode/rea-build/sanctuary/src/Sanctuary.Login/Sanctuary.Login.csproj \
  -c Release -r win-x64 --self-contained false -p:TargetFramework=net9.0 \
  -o /tmp/opencode/rea-build/publish-win-x64/sanctuary-login
```

Result: success, 2 warnings (`NU1903`, `MSB3026`), 0 errors. `Docker.sln` only
contains `Docker.dcproj` and is effectively a no-op.

| Artifact | SHA-256 |
|---|---|
| `sanctuary-gateway/Sanctuary.Gateway.exe` | `590b00cce08f7759b266c53b371e72dc3b541e6cd1d290374f86508af4ec40dc` |
| `sanctuary-gateway/Sanctuary.Gateway.dll` | `0e813e9dadbafc98e9d2b8ba687e1728897f22cc4a8be0dd6e8385bf1fa77e9b` |
| `sanctuary-webapi/Sanctuary.WebAPI.exe` | `2ded18a2ee7ec52f26ec91e50f6454013858355ed7ace31c11219900f3ebeb14` |
| `sanctuary-webapi/Sanctuary.WebAPI.dll` | `9ce627773db29e5140fba808fcb74fffae3c8ee860b917bcbea0f85b01245e18` |
| `sanctuary-login/Sanctuary.Login.exe` | `33fec7172d8367daa88c0cd886299eb5a8f42eb64c072eb9bbc419107c773982` |
| `sanctuary-login/Sanctuary.Login.dll` | `889874464f75eb0f5c93a3274eda1de6f69fbd3661d869c97224714a342eed37` |

## Service topology (Sanctuary README)

The README confirms the four ports used by the iOS launcher:

| Program | Port | Protocol | Role |
|---|---:|---|---|
| `Sanctuary.WebAPI` | 20040 | HTTP | Accounts, login sessions, character portraits |
| `Sanctuary.Login` | 20042 | UDP | Character select / creation, public client login |
| `Sanctuary.Login` | 20041 | UDP | Internal Gateway connection |
| `Sanctuary.Gateway` | 20260 | UDP | Game world |

The README also documents `POST /login` returning a session ID and the exact
launch arguments passed to `FreeRealms.exe`, including
`Internationalization:Locale=8`, `Server=host:20042`, `SessionId=<id>`,
asset URL and portrait URL. This matches the native WebAPI → Login UDP flow
already implemented in `ios/Launcher/Services/HTTPClient.swift` and
`ios/Launcher/Services/LoginUDPSession.swift`.

## REA observations

REA inspected the managed PE/CIL assemblies statically. Evidence IDs:

- Launcher.dll: `ev_17c8a0cdc45641ad08a2be7306dabed33cb7058e27aec2b041b68db23600c028`
- Published Launcher.dll: `ev_50271e3c511e3b53603a55cfd6db4d00968ff7d5209d1e23ee535ba4725ae5b2`
- Downloader.dll: `ev_9903045d8fb5606648c3e81e7eb1d4ce6509fa6465308911d5250dd33730b27f`
- Published Downloader.dll: `ev_fe769fb5ed478396c0ed938734b7790727daf337c7a66d010f1e43f64abc83b9`
- Downloader type inventory: `ev_f2f1de4c221339ab352afe8a51cd30912fbe5181bb610c689ffc315715976a87`
- Async state machines: `ev_bcf9c3f370be49e0d39a53d00952ab8efe8bbe1c154a765b97dfbde29a4be3c3`
- Retry/progress IL: `ev_874e44f3adda7ec614d9083bfdfaeae4af06e0243665a2281eb04e8cb3dcb812`
- Progress plumbing: `ev_f6524af91bd5986ca58627cc77b492ff181e5339b6834fefbeb0ff5071796ae1`
- Configuration defaults: `ev_bf4859c1263103e489947ad1f7c6805d4de487266f062407986a1fc85b84281a`

The compiled constants match the source: `MaxTryAgainOnFailure = 5`,
`ChunkCount = 1`, `ParallelDownload = false`, and a custom HTTP client factory.
Downloader's `BufferBlockSize` default is 1024 bytes and is not overridden by
the Launcher; `MinimumSizeOfChunking` is 512 bytes; `BlockTimeout` is 1000 ms.
`MaxTryAgainOnFailure = 5` permits the first attempt plus five retries.

### Client file verification and download order

Source-backed call order in `ViewModels/Server.cs`:

1. Obtain the client manifest (`clientmanifest.xml`, lowercase).
2. `VerifyClientFilesAsync()` — download/verify all files.
3. Check locale support.
4. Check `IsOnline`.
5. Open the login UI.

For each existing file, the C# code compares size, then computes XXH64 on a
thread-pool task. A file is skipped only when both match; missing or mismatched
files are queued. There is no post-download size/hash verification in the
Launcher, and `File.Create` truncates an existing file before copying, so an
interrupted copy can leave a partial file. Downloads use one chunk per file and
`Parallel.ForEachAsync` with `Math.Max(2, DownloadThreads)` workers.

## Ghidra observations

The Windows `Launcher.exe` is a standard .NET apphost, not the application
logic. Ghidra headless with `-noanalysis` reported x86-64, image base
`0x140000000`, 200 mostly import-thunk functions and 160 strings including
`Launcher.dll`, `KERNEL32.dll`, `USER32.dll`, version metadata and the Windows
manifest. Log: `/tmp/opencode/rea-build/ghidra-launcher-apphost.log`; script:
`/tmp/opencode/rea-build/ghidra-scripts/DumpApphostInfo.java`. REA
`open_binary` on the same file agreed it is a PE executable with matching SHA.
No useful native pseudocode exists for launcher behavior; managed CIL is the
correct source of truth.

## Consequences for the iOS port

These are source/binary observations followed by iOS design decisions, not
claims that the original has the same bug on Windows:

- The observed C# UI updates `StatusMessage` from parallel workers. On iOS all
  progress/state writes are marshalled to `@MainActor`.
- The C# code has no post-copy verification; the Swift `HTTPClient` verifies
  size and XXH64 before replacing the destination and uses a `.part` temporary
  file plus atomic replacement.
- C# verification hashes existing files on the thread pool. The Swift scan is
  performed in a detached task and skips files whose bundled index entry
  already matches the live manifest.
- C# uses N parallel services with a 10-minute pooled connection lifetime and
  infinite download timeout. Swift uses `URLSession` with a 20-second request
  timeout and a bounded task group.
- URL/local paths in C# are `client`/`Client` and rely partly on Windows path
  behavior. Swift validates every relative path component through `SafePath`.

## Limitations

- Static analysis only. No Windows assembly or server was executed, and no
  native crash was reproduced on this host.
- Sanctuary's `.exe`/`.dll` outputs were built and hashed but not deeply
  REA-inspected; the existing `03-protocol-and-servers.md` remains the protocol
  authority.
- Ghidra ran with `-noanalysis`; the apphost was not decompiled beyond basic
  imports and strings.
- Exact jitter bounds in Downloader's exponential backoff were not resolved.
- A complete 1:1 visual game port still requires the proprietary client asset
  formats (`.pack`, `.rcc`, FXO, Granny, DXT variants), Lua behavior and a
  native renderer. The current app embeds and parses client data but does not
  implement those renderers.
