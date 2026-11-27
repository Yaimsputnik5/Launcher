# Compiled binaries and REA/Ghidra verification

This report records the requested binary-side verification of the two upstream
C# projects and the stock client. It supplements the source audits in
`00-overview.md` through `04-game-logic-and-scripts.md`; it does not replace
them.

Sources:

- Launcher: <https://github.com/Open-Source-Free-Realms/Launcher>
- Sanctuary: <https://github.com/Open-Source-Free-Realms/Sanctuary>, audited at
  `f5240b7554f2a80d6b815cb7ead7ffee12499565`
- Local Launcher source: `src/` in this repository
- Local Sanctuary source: `/tmp/opencode/sanctuary`
- Stock client: `ios/Launcher/Resources/ClientAssets/FreeRealms.exe` (build-time
  staged payload, not committed)

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
|---:|---|---|---|
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

## REA observations: managed assemblies

REA inspected the managed PE/CIL assemblies statically. Evidence IDs:

- Launcher.dll: `ev_17c8a0cdc45641ad08a2be7306dabed33cb7058e27aec2b041b68db23600c028`
- Published Launcher.dll: `ev_50271e3c511e3b53603a55cfd6db4d00968ff7d5209d1e23ee535ba4725ae5b2`
- Published Launcher.dll, second inspection: `ev_7473e05b0f7b02899619b164ba5c272f241601d08796449f28fc74a5de53b6fa`
- Downloader.dll: `ev_9903045d8fb5606648c3e81e7eb1d4ce6509fa6465308911d5250dd33730b27f`
- Published Downloader.dll: `ev_fe769fb5ed478396c0ed938734b7790727daf337c7a66d010f1e43f64abc83b9`
- Downloader type inventory: `ev_f2f1de4c221339ab352afe8a51cd30912fbe5181bb610c689ffc315715976a87`
- Async state machines: `ev_bcf9c3f370be49e0d39a53d00952ab8efe8bbe1c154a765b97dfbde29a4be3c3`
- Retry/progress IL: `ev_874e44f3adda7ec614d9083bfdfaeae4af06e0243665a2281eb04e8cb3dcb812`
- Progress plumbing: `ev_f6524af91bd5986ca58627cc77b492ff181e5339b6834fefbeb0ff5071796ae1`
- Configuration defaults: `ev_bf4859c1263103e489947ad1f7c6805d4de487266f062407986a1fc85b84281a`
- Sanctuary.Packet member inventory: `ev_087cc06c4c73501acae15d1273d5e66d18d26b9a18cd318bb17755f1a8a64958`

The compiled constants match the source: `MaxTryAgainOnFailure = 5`,
`ChunkCount = 1`, `ParallelDownload = false`, and a custom HTTP client factory.
Downloader's `BufferBlockSize` default is 1024 bytes and is not overridden by
the Launcher; `MinimumSizeOfChunking` is 512 bytes; `BlockTimeout` is 1000 ms.
`MaxTryAgainOnFailure = 5` permits the first attempt plus five retries.

### Apphost vs managed payload

REA `inspect_managed_artifact` classified the published `.exe` files as native
PE32+ apphosts with no CLI directory; the application logic is in the sibling
`.dll` files. The eight managed assemblies were also inspected statically;
their SHA-256s, MVIDs, member counts, exact packet fields, CIL anchors, native
boundaries and explicit inference labels are recorded in
`06-managed-dll-evidence.md`. Apphost evidence IDs:

| Apphost | Evidence ID |
|---|---|
| `launcher/Launcher.exe` | `ev_72d3474b6a145e7dfe4e514a3236bfe10313e4d1e448e08880a6d23364384af1` |
| `sanctuary-gateway/Sanctuary.Gateway.exe` | `ev_7b0ae928f7aa58cae1c77826e3967ffb0a5f97f87f829907857e9f643b91c6d6` |
| `sanctuary-webapi/Sanctuary.WebAPI.exe` | `ev_de9a80a4d77d260ba891ad280ea93902ff4cf79477539a01b9435d05aa8f59b9` |
| `sanctuary-login/Sanctuary.Login.exe` | `ev_9193fa63b6cca5107546a2440e9a931ba8dd880097dfac0ebafa4d46fd61756a` |

The published `Launcher.dll` is `managed` / `modern-dotnet` /
`cil-and-ready-to-run` with managed architecture `x86_64`, assembly name
`Launcher`, version `1.0.0.0`, 39 references, 4 resources and 1149 attributes;
REA coverage was complete. Static inspection did not load the assembly, resolve
dependencies through a CLR, decompile C#, or execute native ReadyToRun code.

The compiled managed assemblies confirm the launcher's launch and client flow:
`Server=`, `SessionId=` and `Internationalization:Locale=` are user strings in
`Launcher.dll`; `Process.Start` is called from `<LaunchClientAsync>d__18.MoveNext`;
`clientmanifest.xml`, `ServerManifestV1.xsd` and `ServerManifest.xsd` are present
in bootstrap methods. `Sanctuary.WebAPI.dll` exposes `/login`, `/register` and
`/image`, with BCrypt verification and EF Core calls in the async login body.
`Sanctuary.Packet.dll` field metadata confirms `PacketLogin` contains `Ticket`,
`Guid`, `Version` and `Unknown`; both tunnel types contain `OpCode`, `Reliable`
and `Payload`; `PacketSetLocale.TryDeserialize` has the CIL constant `88`.
`Sanctuary.Core.dll` shows AES-CCM (`AesCcm`, constants `13` and `16`) and RC4
(code) plumbing, plus `StartingCoins`, `StartingStationCash`, `UnlockAllTitles`
and `UnlockAllProfiles` fields in `LoginServerOptions`. `Sanctuary.Gateway.dll`
confirms `OnHandlePacket` dispatches to `PacketLoginHandler`,
`PacketTunneledClientPacketHandler` and
`PacketTunneledClientWorldPacketHandler`. These are compiled-artifact
observations, not decompiled control-flow proof. Fields named `Unknown*` and
the `PacketLogin.OpCode` literal remain explicitly inferred/source-only; see
`06-managed-dll-evidence.md`.

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

## REA observations: stock client

`FreeRealms.exe` was staged with the original client payload and opened in REA:

| Property | Observation |
|---|---|
| SHA-256 | `26cc1c522a45e71fb57882da515f65bac45c8c8b8c7e740c0cea81c52a733351` |
| Size | 25,067,520 bytes |
| REA format / architecture | `pe` / `x86` |
| Rizin evidence ID | `ev_c88548799601ca0f845a19c935b41fce1aec0ebb5f14f608c3c13f22914703df` |
| PE timestamp | `Thu Mar 13 10:09:18 2014 UTC-8` |
| PDB path | `C:\Dev\FreeRealms\Live\Code\Output\Win32\Release\PlayClient\FreeRealms.pdb` |

Rizin strings observed relevant launch/session and settings names include
`StartingZone` (file offset `0x1404d68`),
`HUD:SetIsInStartingZone` (`0x14046f0`),
`%sStartingZoneLoad.txt` (`0x1410194`),
`ClientStartingZoneLoader` (`0x1748430`),
`Internationalization` (`0x14053d8`), `ProfileName` (`0x1411604`),
`ProfileId` (`0x14115f8`), `PlayerName` (`0x140b584`), `Coins`
(`0x1409994`), `StationCash` (`0x14211d0`), `Locale` (`0x14067ac`),
`SessionId` (`0x135b32c`) and `Server` (`0x135b35c`). For this PE the
Ghidra virtual addresses are the listed file offsets plus `0x400000`. These
observations confirm the identifiers exist in the shipped client. They do
**not** by themselves prove exact semantics; the iOS port uses source-backed
Sanctuary behavior for semantics and labels inferred fields explicitly.

A manual Ghidra 12.2 headless analysis was launched over the same binary with
`DumpFreeRealmsEvidence.java`; its target addresses are recorded below. Results
are incorporated only if the run completes and emits evidence; an incomplete
run is not treated as proof.

| Target | Address |
|---|---:|
| `StartingZone` | `0x01804d68` |
| `HUD:SetIsInStartingZone` | `0x018046f0` |
| `ProfileName` | `0x01811604` |
| `ProfileId` | `0x018115f8` |
| `PlayerName` | `0x0180b584` |
| `Coins` | `0x01809994` |
| `StationCash` | `0x018211d0` |
| `Locale` | `0x018067ac` |
| `SessionId` | `0x0175b32c` |
| `Server` | `0x0175b35c` |
| `IndirectServerAddress` | `0x01806740` |
| `ClientStartingZoneLoader` | `0x01b48430` |
| `ZoneIdLocation` | `0x0187eac8` |
| `TileLngLat` | `0x018084a8` |

Script: `/tmp/opencode/rea-build/ghidra-scripts/DumpFreeRealmsEvidence.java`.
Logs: `/tmp/opencode/rea-build/ghidra-freerealms-6g.log` (10-minute run,
terminated before its post-script), `/tmp/opencode/rea-build/ghidra-freerealms-8g.log`
(project-directory failure), `/tmp/opencode/rea-build/ghidra-freerealms-5m.log`
(300-second analysis timeout) and
`/tmp/opencode/rea-build/ghidra-freerealms-evidence.log` (post-script output).

The completed Ghidra post-script emitted real program facts:

| Property | Ghidra observation |
|---|---|
| Program | `FreeRealms.exe` |
| Language / compiler | x86 32-bit PE / `windows` |
| Image base | `0x00400000` |
| Discovered functions | 134,650 |
| `.text` | `0x00401000`–`0x0174ffff`, R-X |
| `.rdata` | `0x01751000`–`0x01af1fff`, R-- |
| `.data` | `0x01af2000`–`0x01cc0fff`, RW- |

The first evidence-script compile failed on `MemoryBlock.getPermissions()`, which
does not exist in Ghidra 12.2; it was corrected to explicit read/write/execute
checks. The rerun emitted all target addresses but `TARGET_REF_COUNT` was `0`
for every string because auto-analysis timed out at 300 seconds before reference
creation finished. These runs therefore establish binary layout, function
discovery and string addresses, but they are **not** proof of xref semantics or
decompiled behavior. The `StartingZone`, `ProfileName`, `PlayerName`, `Coins`,
`StationCash`, `Locale`, `SessionId` and `Server` identifiers remain observed
strings; their exact use in the shipped client remains unresolved.

A second targeted `strings -a -n 6` pass over the same SHA-256 confirmed that
the native client links its own `UdpLibrary` implementation. Relevant diagnostic
and RTTI strings include `ReliablePing=%dms  ZonePing=%dms`,
`DisconnectReasonReliableOverflow`, `NoCastRecastTimer`,
`reliableOutgoingId=%lld`, `reliableOutgoingPendingId=%lld`,
`.?AVUdpConnection@UdpLibrary@@` and
`.?AVGroupLogicalPacket@UdpLibrary@@`. These corroborate that the shipped client
tracks separate current/pending outbound reliable IDs and group logical packets,
matching the field names in Sanctuary's C# `UdpReliableChannel`. They are string
observations only; the exact native control flow was not recovered because
auto-analysis timed out before references were created.

## Ghidra observations: Launcher apphost

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
- Native REA evidence for the apphosts confirms that inspecting the `.exe`
  alone cannot explain launcher or Sanctuary behavior; the managed `.dll`
  members and the C# source are the authority for those layers.
- Stock-client string/xref evidence for `StartingZone`, `ProfileName`,
  `PlayerName`, `Coins`, `StationCash`, `Locale`, `SessionId` and `Server`
  supports the settings consumed by `LocalHostConfiguration` and
  `WorldSimulation`; inferred positions and unknown packet fields remain
  labeled as such.

## Limitations

- Static analysis only. No Windows assembly or server was executed, and no
  native crash was reproduced on this host.
- REA managed inspection inventories metadata, signatures and CIL anchors. It
  does not load assemblies through a CLR, resolve dependencies, decompile C#,
  or execute ReadyToRun native code.
- REA's Ghidra provider is unavailable with the installed Ghidra `12.2`
  (accepted line: `12.1.x`, verified `12.1.4`), and the Hopper provider timed
  out during binary readiness. The stock-client Ghidra evidence, if any, comes
  from a separate manual headless run, not the REA provider.
- Ghidra's Launcher apphost run used `-noanalysis`; the apphost was not
  decompiled beyond basic imports and strings.
- Exact jitter bounds in Downloader's exponential backoff were not resolved.
- A complete 1:1 visual game port still requires the proprietary client asset
  formats (`.pack`, `.rcc`, FXO, Granny, DXT variants), Lua behavior, navmesh
  routines and a full native 3D renderer. The current app embeds and parses
  client data and renders an engine-frame 2D scene; it does not implement the
  desktop 3D renderer.
