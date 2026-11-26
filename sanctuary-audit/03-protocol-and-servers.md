# Sanctuary audit — servers, database, and wire protocol

Scope: Core, Database (+ MySQL/SQLite), WebAPI, Login, Gateway, UdpLibrary, Packet, Packet.Common, and their tests/configs.

## Size and shape

| Project | Files | C# |
|---|---:|---:|
| Core | 30 | 29 |
| Database | 19 | 17 |
| Database.MySql | 41 | 40 |
| Database.Sqlite | 41 | 40 |
| WebAPI | 13 | 7 |
| Login | 24 | 19 |
| Gateway | 154 | 149 |
| UdpLibrary | 34 | 33 |
| Packet | 353 | 352 |
| Packet.Common | 135 | 134 |

Gateway alone has 134 packet handler files. Packet definitions total 488 files.

## Startup topology

### WebAPI

- `WebApplication.CreateBuilder`
- binds `DatabaseOptions` and `WebAPIOptions`
- adds database provider
- maps `AuthEndpoints` and `PortraitEndpoints`
- listens on `http://127.0.0.1:20040`

### Login

Config order: `DOTNET_` env → user secrets (Development) or optional `database.json` (Production) → required `login.json` with reload → plain env.

Registers two UDP endpoints:

- `LoginUdp_6` on port 20042 for clients; CRC 2 bytes; 2000 connections; 29 s keepalive; optional compression.
- `LoginGateway` on port 20041 for Gateway↔Login; 10 s keepalive.

`LoginService.ExecuteAsync`:

1. `Database.Migrate()`; stop host on failure.
2. `ResourceManager.Load()`.
3. Configure packet handlers.
4. Loop: `GiveTime()` both servers, `ProcessPendingLogins()`, sleep 1 ms when idle.

### Gateway

Registers `LoginGateway` client and `CGAPI_527` server on port 20260; CRC 2 bytes; 30 s no-data timeout; 2000 connections; 29 s keepalive; compression enabled in checked-in config.

`GatewayService.ExecuteAsync`:

1. Wait up to 30 s for DB connectivity.
2. `ResourceManager.Load()`, `LoadNavMeshes()`.
3. `ScriptManager.Load()`, `ZoneManager.Load()`, `InteractionManager.Load()`, `ChatCommandManager.Load()`.
4. Configure handlers.
5. Establish internal connection to `localhost:20041`.
6. Loop: `GiveTime()` both endpoints, sleep when idle.

Stop broadcasts `PacketWorldShutdownNotice { ReasonId = 418992 }`.

## Configuration

`login.json`: port 20042, gateway port 20041, challenge `OSFR-EDITz@2024`, unlocked, title 0, profile 1, 999999999 coins/cash, all titles/profiles unlocked. `UseCompression` exists in options but is absent from the file, so effective default is `false`.

`gateway.json`: port 20260, compression true, environment `live`, client version `1.910.1.530630`, server address `127.0.0.1:20260`, login gateway `localhost:20041`, same challenge, no member nag.

`appsettings.json`: launch arguments for assets/portraits, `MemberByDefault=true`, `Urls=http://127.0.0.1:20040`. Development adds `Logging:Level=6`.

## Database

Final SQLite/MySQL schema has 15 tables:

`Users`, `Characters`, `Items`, `Mounts`, `Profiles`, `Titles`, `ProfileItems`, `PetItems`, `Friends`, `Ignores`, `Guilds`, `GuildMembers`, `CollectionEntries`, `CharacterQuests`, `CharacterQuestProgress`.

Defaults: `Users.MaxCharacters=10`, `IsMember=false`, `IsAdmin=false`, `IsMod=false`; character chat bubble colors `0xD4E2F0` / `0x063C67`, size 1; guild max members 100. No seed data.

11 migrations exist for each provider. Login applies them; Gateway only waits for connectivity.

## Serialization conventions

- Little-endian primitives.
- `bool` = 1 byte.
- `string` = int32 UTF-8 byte length + bytes.
- Payload = int32 length + bytes.
- Lists/dictionaries = int32 count + entries.
- `DateTime`/`DateTimeOffset` = int64 Unix seconds.
- Vectors/quaternions = 3 floats when limited, otherwise 4.
- Packet magic `0xF3D4A5C9`.

## UDP transport

Constants: protocol version 3, 2 encryption passes, 4 reliable channels, hard max raw packet size `0x2000`.

Packet types include `Connect`, `Confirm`, `Multi`, `Big`, `Terminate`, `KeepAlive`, `ClockSync`, `Reliable1..4`, `Fragment1..4`, `Ack1..4`, `AckAll1..4`, `Group`, `Ordered`, `Ordered2`, `ServerStatus`, etc.

Raw framing:

- Internal packet starts `0x00` + packet type byte.
- Application payloads beginning with `0x00` are zero-escaped.
- CRC32 with `EncryptCode` folded into initial state; 2-byte big-endian suffix.
- User-supplied compression header: `0` raw, `1` zlib; only when source ≥ 24 bytes and smaller.

Connect packet:

```text
0x00
UdpPacketType.Connect (1)
int32 ProtocolVersion = 3 (big endian)
int32 ConnectCode (big endian)
int32 MaxRawPacketSize (big endian)
ASCII protocol name + NUL
```

Confirm packet includes connect code, encrypt code, CRC bytes, two encrypt methods, max size, and protocol version.

Application crypto:

- Login uses RC4 with fixed key `F70IaxuU8C/w7FPXY1ibXw==`, always reliable channel 1 outbound.
- Gateway uses AES-CCM with the ticket string ASCII as key, 16-byte tag, 13-byte nonce (8-byte little-endian counter + 5 random bytes), and rejects non-increasing counters.

## WebAPI contract

`POST /login`: `{ "username", "password" }` → `200 { "sessionId": "<32 hex>", "launchArguments": "..." }`, 401 on bad credentials.

`POST /register`: username 3–50 `[A-Za-z0-9_.]`, password 6–100 ASCII; BCrypt hash; member by default; 409 on duplicate.

`POST /image`: exact multipart boundary `AaBb432101234bBaA`; fields `imageType=portrait`, `characterId != 0`, `thumbnailFile=headshot.png` 70×70 PNG, `imageFile=portrait.png` 180×330 PNG; writes `portrait.crc` (zlib CRC32). Antiforgery disabled.

## Login protocol

ExternalLogin opcodes 1–17 plus 210/211. Important layouts:

- `LoginRequest` (1): `string Session`, `string Fingerprint`.
- `LoginReply` (2): `bool LoggedIn`, `int Status`, `bool IsMember`, payload bytes. Success payload: `bool IsMember`, `int MaxCharacters`, `bool IsAdminAccount`.
- `CharacterLoginRequest` (7): `ulong EntityKey`, `int ServerId`, `ClientLoginData` payload.
- `CharacterLoginReply` (8): `ulong EntityKey`, `int ServerId`, `int Status`, payload. Status 1 payload includes server address, ticket, crypto key, GUID, etc.

Handlers cover login, character create/delete/select/login, server list, name check, and tunneled packets.

Character login state machine:

- Holds busy logins instead of refusing them.
- `CrashIdleMilliseconds=5000`, `ReleaseRetryMilliseconds=2000`, `HandoffMilliseconds=10000`.
- Admission creates fresh GUID ticket, sets `CryptoKey` to ticket, and uses `GuidHelper.GetPlayerGuid(characterId)`.

## Gateway↔Login internal protocol

Custom opcodes 100–105:

| Opcode | Packet |
|---:|---|
| 100 | `GatewayLoginRequest` |
| 101 | `GatewayLoginReply` |
| 102 | `GatewayCharacterLogin` |
| 103 | `GatewayCharacterLogout` |
| 104 | `GatewayCharacterReleaseRequest` |
| 105 | `GatewayCharacterReleaseReply` |

An in-process Swift port can replace these UDP messages with actor/shared state, but must preserve the externally visible timing and statuses.

## Client-facing Gateway login

Short opcodes 1, 2, 5, 6:

- `PacketLogin`: `short opcode=1`, `string Ticket`, `ulong Guid`, `string Version`, `string Unknown`.
- `PacketLoginReply`: `short opcode=2`, `bool Success`.
- `PacketTunneledClientPacket` / `WorldPacket`: `bool Reliable`, payload bytes whose first short is a gameplay opcode.

Login requires exact client version, parses the ticket as GUID, initializes AES-CCM with the ticket string, loads all related DB state, creates the player, begins a login session, sends character login to Login, then feeds initialization packets including item definitions and self state.

## Required Swift components for byte-compatible offline stack

1. SQLite store matching final schema.
2. Account service with BCrypt-compatible hashing and WebAPI semantics.
3. Session store (32-hex IDs, 5-minute expiry, one-time use).
4. Login UDP endpoint with handshake, CRC, compression, RC4, opcodes 1–17/210–211.
5. Gateway UDP endpoint with handshake, CRC, AES-CCM, opcodes 1/2/5/6, tunneled dispatch.
6. In-process gateway registry replacing port 20041.
7. Character login coordinator with the same hold/release/handoff timings.
8. Portrait endpoint if needed.

`GuidHelper`: player GUID = `(characterId << 4) | 1`; low nibble types Player=1, Npc=2, LocationTarget=3.

## Limits

Most gameplay packet files were accounted for by opcode and serializer signature, not line-by-line review. Full gameplay fidelity depends on the Game/Scripting audits and on a real client for dynamic verification. No seed data exists; an offline app must create initial account/character data.
