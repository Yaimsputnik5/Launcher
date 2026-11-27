# Sanctuary audit — client bootstrap, hosting, build, CI

Scope: `Sanctuary.DevClient`, `src/Docker`, `.github`, `.vscode`, root docs, all solution/project/build files, runtime configs, WebAPI/Login/Gateway entry points.

## DevClient flow

Defaults: address `localhost`, account `test`, client count 1, client path from
`SANCTUARY_CLIENT_PATH`, repo root found by walking up to `src/Sanctuary.slnx`.

Options: `-a address[:port]`, `-l account`, `-g characterId`, `-n clients`,
`--client path`, `--no-servers`. `-g` cannot be combined with `-n > 1`.

Startup order:

1. Parse options.
2. Find repository root.
3. Create `ServerHost`.
4. Register exit/Ctrl+C handlers that stop hosted servers.
5. Resolve/download/copy client folders **before** starting servers.
6. If address is exactly `localhost`, either start servers or wait for them;
   any other address (including `127.0.0.1`) skips server management.
7. Launch clients sequentially with a 3-second delay between clients 2..N.
8. Wait for clients to exit, then stop servers.

Additional clients use account names `account`, `account2`, `account3`, … and
full copied client folders `client-2`, `client-3`, … because clients cannot
share a folder.

## Client acquisition

Constants:

- `ClientManifestUrl = https://opensourcefreerealms.com/clientmanifest.xml`
- `ClientCdnUrl = https://opensourcefreerealms.com/client`
- client executable `FreeRealms.exe`
- staging directory `.client.download`
- 16 parallel workers, 1 MiB chunks, 30-minute timeout

Resolution order:

1. `--client <path>` if it contains `FreeRealms.exe`
2. `<repo>/client`
3. `<LocalApplicationData>/OSFRLauncher/Servers/OSFR Public Server/Client`
4. Download into `<repo>/client`

Downloader walks `Folder`/`File` elements, checks for rooted paths and `..`,
streams files to staging, verifies size only, then moves staging into place.
There are **no hashes or signatures**. A `text/html` response with at least the
expected byte count is accepted as valid, apparently as a CDN workaround.

Launch arguments for character-select flow, in order:

1. `Internationalization:Locale=8`
2. `Server=<address>:<port-or-20042>`
3. `SessionId=<sessionId>`
4. server-provided launch arguments, e.g.
   `AssetDelivery:IndirectServerAddress=http://osfr.editz.dev/assets`,
   `Portrait:UploadUrl=http://127.0.0.1:20040/image`,
   `Logging:Level=6` in Development

Direct-world flow uses `Server=<host>:20260`, `GUID=<(characterId << 4) + 1>`,
`Ticket=<32 hex chars>`, and default asset/portrait arguments; no WebAPI session.

On Windows it executes `FreeRealms.exe` directly; on Linux/macOS it executes
`wine` with the exe path as the first argument. iOS cannot do either.

## Account/session contract

Login and registration are fixed to `http://<address>:20040` regardless of the
`-a` port. DevClient retries for 2 minutes with 1-second backoff and a 5-second
request timeout.

`POST /register` body: `{ "username": "...", "password": "..." }`.
Validation: username 3–50 chars `[A-Za-z0-9_.]`; password 6–100 ASCII chars.
Duplicate returns 409. Passwords are bcrypt-hashed. New accounts are members
by default.

`POST /login` returns `{ "sessionId": "<32 hex>", "launchArguments": "..." }`.
Sessions expire after 5 minutes and are single-use in non-DEBUG builds;
DEBUG builds compile those checks out. No default admin exists; admin/mod is
granted by changing `IsAdmin`/`IsMod` in the database.

Portrait upload is `POST /image`, unauthenticated, with a hardcoded multipart
boundary `AaBb432101234bBaA`, over plain HTTP.

## Server hosting

Three child programs, started Login → Gateway → WebAPI:

| Program | Protocol | Port | Working directory |
|---|---|---:|---|
| Login | UDP | 20042 | `<repo>/src` |
| Gateway | UDP | 20260 | `<repo>/src` |
| WebAPI | TCP | 20040 | `<repo>/src/Sanctuary.WebAPI` |

Internal Login↔Gateway UDP port: 20041.

Environment applied with `TryAdd` (pre-existing values win):

- `Database__Provider=Sqlite`
- `Database__ConnectionString=Data Source=<repo>/sanctuary.db`
- `DOTNET_ENVIRONMENT=Development` for Login/Gateway
- `ASPNETCORE_ENVIRONMENT=Development` for WebAPI

Login runs EF `Database.Migrate()` at startup. Gateway waits up to 30 s for DB
connectivity. Readiness is polled every 250 ms for up to 3 minutes. Logs are
redirected to `<repo>/logs/{Login,Gateway,WebAPI}.log`, overwritten each run.
Shutdown kills tracked process trees. Foreign servers already listening are
not tracked or killed.

iOS implication: this entire path depends on `dotnet` child processes and a
filesystem layout; none of it can run on iOS. A native app must either embed a
Swift reimplementation of the server/game logic or provide a compatible
in-process engine.

## Configuration defaults

`login.json`: port 20042, gateway port 20041, challenge
`OSFR-EDITz@2024`, unlocked, default title 0, default profile 1,
999,999,999 starting coins and station cash, all titles/profiles unlocked.

`gateway.json`: port 20260, compression true, environment `live`, client
version `1.910.1.530630`, server address `127.0.0.1:20260`, login gateway
address `localhost:20041`, same challenge, no member nag.

`appsettings.json`: launch arguments for assets/portraits,
`MemberByDefault=true`, `Urls=http://127.0.0.1:20040`. Development appends
`Logging:Level=6`.

## Docker

Four services: MariaDB 10.5, WebAPI, Gateway, Login. Ports: 3306 TCP, 20040 TCP,
20260/udp, 20041/udp, 20042/udp. Common mounts map `logs`, `src/Resources`,
and `src/Scripts` into `/app`. MariaDB defaults are weak
(`root`/`sanctuary`/`sanctuary`) and published on all interfaces. Compose uses
`localhost:20260` as the advertised game address, which must be changed for LAN
or public play.

## Build and CI

- SDK pinned to 10.0.100; target framework `net9.0`.
- 17 projects; dependency chain ends at Game → Core/Database/Scripting/Packet/UdpLibrary.
- `AllowUnsafeBlocks` in Core and UdpLibrary.
- CI: `ubuntu-latest`, MariaDB 11.6 service, `dotnet restore/build/test` from `src`.
- Four MSTest projects; DB tests need MariaDB locally.
- Visual Studio `slnLaunch` profiles: Play, Servers, Servers + WebAPI,
  Servers + WebAPI + Client.
- VS Code has equivalent launch configurations and build tasks.

### iOS download lifecycle parity

C# `src/Launcher/Views/Main.axaml.cs:25-36` cancels window closing while any
server `IsDownloading` and shows `Text.Downloading.OnClose`
("Cannot close the launcher while downloading." from
`src/Launcher/Resources/Texts.axaml:76`). iOS cannot refuse the home gesture or
app termination, so `ios/Launcher/LauncherApp.swift` applies the closest
platform-equivalent guard: `AppState.hasActiveDownloads` keeps the idle timer
disabled, requests a named `UIBackgroundTaskIdentifier` when the app backgrounds
mid-download, ends that task when downloads stop or expire, and posts the same
message. `AppState.deleteServer` already refuses to delete a downloading
server, matching `ViewModels/Main.cs:149-163`. This is a documented platform
limit, not a claim that iOS can cancel OS-level termination.

## External services

- `https://opensourcefreerealms.com/clientmanifest.xml`
- `https://opensourcefreerealms.com/client/<escaped path>`
- `http://osfr.editz.dev/assets`
- `http://127.0.0.1:20040/image`
- container images from Microsoft and Docker Hub

## Security and licensing notes

- DevClient hardcodes `test` / `testtest`.
- Default public-server settings are intentionally unsafe for production.
- Shared hard-coded LoginGatewayChallenge.
- WebAPI has five NuGet advisory suppressions with no justification.
- Client downloads verify size only; HTML error pages can pass.
- AGPL-3.0 applies to Sanctuary code; porting it into the iOS app requires
  source availability and notice preservation. Free Realms client assets are
  third-party copyrighted content with no license grant here.
- Upstream `CONTRIBUTING.md` says AI-generated PRs will be closed; do not
  submit this port upstream without discussing it first.
