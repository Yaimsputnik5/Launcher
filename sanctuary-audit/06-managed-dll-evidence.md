# Managed DLL findings — OSFR Launcher / Sanctuary iOS-port evidence

Report scope: eight compiled managed PE/CLI DLLs under `/tmp/opencode/rea-build/publish-win-x64/`, plus source-tree corroboration from `/tmp/opencode/sanctuary/src/`. No repository files were edited.

Label legend used throughout:

- **A — compiled artifact observation**: confidence `observed`, authority `shipped-artifact`. Derived from REA static PE/CLI metadata and file-backed CIL inspection.
- **S — source corroboration**: confidence `observed in source checkout`, authority `source-tree corroboration`. This is *not* a compiled-artifact observation and is kept separate from **A**.
- **I — inference**: confidence `inferred`, authority `analyst-inference`. Clearly marked when a name, call edge, or constant suggests behavior but does not prove control flow.

REA did **not** load/execute any assembly, resolve dependencies through the CLR, run ReadyToRun code, or decompile C#. Type/method/field tokens are build-local coordinates and are meaningful only with the artifact SHA-256 and MVID in the identity table.

---

## Scope & method

### Method

1. `inspect_managed_artifact(detail:"summary")` was run first on all eight DLLs to establish PE/CLI identity, MVID, framework, classification, metadata status, and coverage.
2. `inspect_managed_members` was used with `detail:"complete"` for full inventories where transport permitted, and with exact `type_names` for targeted extraction in large assemblies.
3. For `Launcher.dll`, `Sanctuary.Game.dll`, and `Sanctuary.Gateway.dll`, complete member calls were too large for a single result but were retained; type pages were obtained with `inspect_analysis_view(kind:"managed-members", collection:"types")`, then exact types were inspected with targeted member calls.
4. `inspect_managed_native_boundaries` was run on all eight DLLs.
5. Source-tree checks were read only after artifact observations, and are labeled **S**.

### Member inventory counts (A)

| Artifact | Types | Fields | Methods | MemberRefs | Call edges | Field accesses | User strings |
|---|---:|---:|---:|---:|---:|---:|---:|
| `Launcher.dll` | 132 | 598 | 775 | 1127 | 7271 | 2963 | 448 |
| `Sanctuary.Packet.dll` | 363 | 1303 | 797 | 346 | 3267 | 1359 | 41 |
| `Sanctuary.Packet.Common.dll` | 145 | 1343 | 745 | 163 | 2170 | 1734 | 1052 |
| `Sanctuary.Game.dll` | 436 | 2023 | 3410 | 3155 | 14049 | 8340 | 594 |
| `Sanctuary.Core.dll` | 37 | 82 | 220 | 289 | 519 | 294 | 22 |
| `Sanctuary.WebAPI.dll` | 16 | 69 | 49 | 197 | 347 | 335 | 47 |
| `Sanctuary.Login.dll` | 45 | 108 | 141 | 508 | 1259 | 599 | 88 |
| `Sanctuary.Gateway.dll` | 273 | 628 | 866 | 2147 | 8173 | 4425 | 450 |

All metadata was reported `complete` with no issues. All eight are managed PE/CLI assemblies.

### Native boundary summary (A)

All eight DLLs reported:

- `module_ref_count: 0`
- `pinvoke_import_count: 0`
- `native_implementation_count: 0`

Only `Launcher.dll` was `ready_to_run:true`, `il_only:false`, with `managed_native_header_rva:89016` and `managed_native_header_size:196`; REA classified it `cil-and-ready-to-run`. The other seven were `il_only:true`, `ready_to_run:false`. The ReadyToRun header in `Launcher.dll` proves precompiled native code for that managed assembly, not a separate native iOS/macOS framework, and no P/Invoke declarations were observed.

---

## Artifact identity table

| Artifact | SHA-256 | Bytes | PE / managed form | Framework | MVID | Artifact evidence | Native-boundary evidence |
|---|---|---:|---|---|---|---|---|
| `/tmp/opencode/rea-build/publish-win-x64/launcher/Launcher.dll` | `ab87db3490c9d4d7d2cd369dbacacc3b80cf597af48281b114293541747e4dc8` | 1,282,048 | PE x86_64; `cil-and-ready-to-run` | `.NETCoreApp,Version=v10.0` | `6f9d7929-d1a0-4283-b918-559e3819b28e` | `ev_7473e05b0f7b02899619b164ba5c272f241601d08796449f28fc74a5de53b6fa` | `ev_ff363f4a6990328c53b641b427798cc7054307d8e272bf1f40ffc1038dc1b989` |
| `/tmp/opencode/rea-build/publish-win-x64/sanctuary-gateway/Sanctuary.Packet.dll` | `38a88f49ee89e83ce187b90208fad4944c05a271fee89da6c24478daa0baae38` | 111,104 | PE x86; anycpu; `il-only` | `.NETCoreApp,Version=v9.0` | `8e35b11a-eec4-436f-9444-28607b7d9b1d` | `ev_416972200ac0a91b30313dcaec38f72959abda7f8b5045d1f975ca3b8d5da7ac` | `ev_d7570a64d00d5748d54252aea7d9f67fd27e2e25e2ee1d6eeb526b368cf09ace` |
| `/tmp/opencode/rea-build/publish-win-x64/sanctuary-gateway/Sanctuary.Packet.Common.dll` | `af9561c4b276343f382284ec5c76084afd11a107d184872733f86445dd2b9079` | 168,448 | PE x86; anycpu; `il-only` | `.NETCoreApp,Version=v9.0` | `cbdd5323-38a5-4ac3-9721-88caa4515042` | `ev_0d1b6aaaeea37dfb75e61ac44b7b67b74c26c65990ab6862305f757c79ccf9fe` | `ev_4a721a99c82a66e4770a09ee7d1e2795feefd328d88ffbaf9b896745eaf38cc8` |
| `/tmp/opencode/rea-build/publish-win-x64/sanctuary-gateway/Sanctuary.Game.dll` | `32eea5ddd50724f555979890e3f004b7a5a321e4751642c52d0e7a7ede4d87ae` | 561,152 | PE x86; anycpu; `il-only` | `.NETCoreApp,Version=v9.0` | `8c61e6af-11c0-433a-87c1-50095974cb34` | `ev_f4c4f5be8f937a33bf5e285f42bb1db06fb4b03c943a6784c8d2c5102d05d80a` | `ev_28acbbbfa76a05057b5b8083dee34d1afac91cc5a1a0569ca10fb8600236cbc5` |
| `/tmp/opencode/rea-build/publish-win-x64/sanctuary-gateway/Sanctuary.Core.dll` | `55f5eb740fe220a7d5cd2d05660cb278ec9564e698035f82f0dab781372adc8c` | 35,840 | PE x86; anycpu; `il-only` | `.NETCoreApp,Version=v9.0` | `039e445c-e47b-4a92-8ff8-578438087476` | `ev_3ec696f58fc2b2947a5913e7da63bb0f8d89ca0154a65df3713e547c37e4e54d` | `ev_10209759f9a48067d83c88c9ab3f1746978b641ab5471fc510c97f3f71656bda` |
| `/tmp/opencode/rea-build/publish-win-x64/sanctuary-webapi/Sanctuary.WebAPI.dll` | `9ce627773db29e5140fba808fcb74fffae3c8ee860b917bcbea0f85b01245e18` | 27,648 | PE x86_64; `il-only` | `.NETCoreApp,Version=v9.0` | `6769fbe6-2d5e-4ec8-bc6e-1b470cb96fc0` | `ev_583e217721f7ea88d391a64eeab135fccea7c5a9fc8bf04135bfb8c680c586e6` | `ev_904803233d459f6e7ceddf5b39748eed0bd1a2049d54b08b33fa7bd1de073690` |
| `/tmp/opencode/rea-build/publish-win-x64/sanctuary-login/Sanctuary.Login.dll` | `889874464f75eb0f5c93a3274eda1de6f69fbd3661d869c97224714a342eed37` | 53,248 | PE x86_64; `il-only` | `.NETCoreApp,Version=v9.0` | `b32a77d6-2f85-46b1-9bdf-9984ef5e90f0` | `ev_57d3a3a806224ba43656cd3be80ff0e1fde830922bd046f479259c64a72431b1` | `ev_e5781e6efcf266997b20940f62d79357ad6520e174c2e2c860dbdcfa724772f8` |
| `/tmp/opencode/rea-build/publish-win-x64/sanctuary-gateway/Sanctuary.Gateway.dll` | `0e813e9dadbafc98e9d2b8ba687e1728897f22cc4a8be0dd6e8385bf1fa77e9b` | 259,072 | PE x86_64; `il-only` | `.NETCoreApp,Version=v9.0` | `ccd22479-2e4a-4654-8e4d-2cdf64c6ec52` | `ev_b34faea40c9382cf35716bdad344cc8149e269bac8fef4d03f9acb0c498eefb5` | `ev_1a5a347e3a9522660bf645ce7512db346c39fb8d0d4e1d07d6b36cdaffe049ea` |

---

## Login/WebAPI

### `Sanctuary.WebAPI.dll` bootstrap (A)

Evidence: WebAPI complete/targeted/async member receipts listed under “Evidence IDs & limitations”.

- `Program.<Main>$` — IL `231`, `76` instructions, `41` anchors. Call edges include `WebApplication.CreateBuilder`, `UseUrls`, configuration/bind, `Sanctuary.Core.Extensions.DatabaseExtensions.AddDatabase`, NLog setup, `Sanctuary.WebAPI.Endpoints.AuthEndpoints.MapAuthEndpoints`, `Sanctuary.WebAPI.Endpoints.PortraitEndpoints.MapPortraitEndpoints`, and `Run`.
- User strings include `ForwardedHeadersOptions`, `Database`, `WebAPI`, `NLog.config`, `NLog.Development.config`, `/login`, `/register`, and `/image`.
- `Sanctuary.WebAPI.Options.WebAPIOptions` fields: `Section` (`string`, literal), `<LaunchArguments>k__BackingField` (`string`), `<MemberByDefault>k__BackingField` (`bool`).
- `Sanctuary.WebAPI.Models.LoginRequestModel`: `<Username>k__BackingField`, `<Password>k__BackingField` (both `string`).
- `Sanctuary.WebAPI.Models.LoginResponseModel`: `<SessionId>k__BackingField`, `<LaunchArguments>k__BackingField` (both `string`).
- `Sanctuary.WebAPI.Models.RegisterRequestModel`: `<Username>k__BackingField`, `<Password>k__BackingField` (both `string`).

### Auth endpoints (A)

- `Sanctuary.WebAPI.Endpoints.AuthEndpoints.MapAuthEndpoints` — IL `107`, `35` instructions, `19` anchors; user strings `/login`, `/register`.
- `LoginHandlerAsync` and `RegisterHandlerAsync` wrappers — IL `79`, `26` instructions, `20` anchors each.
- Async bodies:
  - `Sanctuary.WebAPI.Endpoints.<LoginHandlerAsync>d__2.MoveNext` — IL `951`, `192` anchors.
  - `Sanctuary.WebAPI.Endpoints.<RegisterHandlerAsync>d__3.MoveNext` — IL `975`, `204` anchors.
- Call edges include `MiniValidation.MiniValidator.TryValidate`, `Results.ValidationProblem`, `IDbContextFactory.CreateDbContextAsync`, EF `FirstOrDefaultAsync`/`AnyAsync`, `BCrypt.Net.BCrypt.Verify`, `GenerateSalt`, `HashPassword`, `Guid.NewGuid().ToString`, `SaveChangesAsync`, `Results.Unauthorized`, `Results.Conflict`, `Results.InternalServerError`, and `Results.Ok`.
- This proves the shipped server exposes login/registration HTTP handlers backed by BCrypt and EF Core. It does not expose plaintext passwords or live credentials.

### Portrait endpoints (A)

- `Sanctuary.WebAPI.Endpoints.PortraitEndpoints.MapPortraitEndpoints` — IL `73`, `23` instructions, `13` anchors; call edge `DisableAntiforgery`; user string `/image`.
- Fields: `ThumbnailWidth`, `ThumbnailHeight`, `PortraitWidth`, `PortraitHeight` (`i4`, literal), `UploadDecoderOptions` (`class:233`), `_logger`, `_fileLocks`.
- User strings include `multipart/form-data; boundary=AaBb432101234bBaA`, `portrait`, `image/png`, `thumbnailFile`, `imageFile`, `headshot.png`, `portrait.png`, `portrait.crc`.
- `Sanctuary.WebAPI.Endpoints.<ImageHandlerAsync>d__8.MoveNext` — IL `2096`, `406` anchors; calls include `PortraitStorage.GetCharacterDirectory`, `PortraitStorage.GetPortraitCrc`, ImageSharp decoding/saving, `SemaphoreSlim`, and `File.WriteAllBytesAsync`.
- `Sanctuary.WebAPI.Endpoints.<TryDecodePngAsync>d__9.MoveNext` — IL `210`, `43` anchors.
- `ImageHandlerAsync` wrapper — IL `88`, `29` instructions, `23` anchors.
- The hardcoded multipart boundary/form names/file names are strong evidence that the endpoint was written to match an existing game client upload contract.

### WebAPI source corroboration (S — source-only, not compiled evidence)

- `/tmp/opencode/sanctuary/src/Sanctuary.WebAPI/Endpoints/AuthEndpoints.cs:33-34` maps `POST /login` and `POST /register`; lines 57, 64, 74-78 show `BC.Verify`, session GUID creation, and `SessionId`/`LaunchArguments` response.
- `/tmp/opencode/sanctuary/src/Sanctuary.WebAPI/Endpoints/PortraitEndpoints.cs:40` maps `POST /image`; lines 51, 59, 89, 97, 107 check the compiled-artifact-observed boundary, `imageType`, PNG content type, form names, and file names.
- `/tmp/opencode/sanctuary/src/Sanctuary.DevClient/GameClient.cs:72,79` posts `/login` and `/register`; line 27 shows the default `Portrait:UploadUrl=http://127.0.0.1:20040/image`.

---

## Gateway/Login packets

### Packet shapes and opcode anchors (A)

Evidence: targeted `Sanctuary.Packet.dll` member receipt `ev_9de6140d1f01c2f2cafdabc5335221c4edd99994725db89750b2359eae02e5a0`.

Exact fields observed:

| Type | Fields (exact names and REA signature types) |
|---|---|
| `Sanctuary.Packet.PacketLogin` | `OpCode:i2`, `Ticket:string`, `Guid:u8`, `Version:string`, `Unknown:string` |
| `Sanctuary.Packet.PacketLoginReply` | `OpCode:i2`, `Success:bool` |
| `Sanctuary.Packet.PacketTunneledClientPacket` | `OpCode:i2`, `Reliable:bool`, `Payload:u1[]` |
| `Sanctuary.Packet.PacketTunneledClientWorldPacket` | `OpCode:i2`, `Reliable:bool`, `Payload:u1[]` |
| `Sanctuary.Packet.LoginRequest` | `OpCode:u1`, `Session:string`, `Fingerprint:string` |
| `Sanctuary.Packet.LoginReply` | `OpCode:u1`, `LoggedIn:bool`, `Status:i4`, `IsMember:bool`, `Payload:u1[]` |
| `Sanctuary.Packet.CharacterLoginRequest` | `OpCode:u1`, `EntityKey:u8`, `ServerId:i4`, `Payload:u1[]` |
| `Sanctuary.Packet.CharacterLoginReply` | `OpCode:u1`, `EntityKey:u8`, `ServerId:i4`, `Status:i4`, `Payload:u1[]` |
| `Sanctuary.Packet.GatewayLoginRequest` | `OpCode:u1`, `Challenge:string`, `Data:class:333`, `ServerAddress:string` |
| `Sanctuary.Packet.GatewayLoginReply` | `OpCode:u1`, `Success:bool` |
| `Sanctuary.Packet.GatewayCharacterLogin` | `OpCode:u1`, `Id:u8`, `Session:u8` |
| `Sanctuary.Packet.CharacterSelectInfoReply` | `OpCode:u1`, `Status:i4`, `CanBypassServerLock:bool`, `Entities:class:65<class:337>` |
| `Sanctuary.Packet.ServerListReply` | `OpCode:u1`, `Servers:class:65<class:341>` |
| `Sanctuary.Packet.TunnelAppPacketClientToServer` | `OpCode:u1`, `ServerId:i4`, `Payload:u1[]` |
| `Sanctuary.Packet.TunnelAppPacketServerToClient` | `OpCode:u1`, `ServerId:i4`, `Payload:u1[]` |
| `Sanctuary.Packet.PacketSetLocale` | `OpCode:i2`, `Locale:string` |

Method anchors found in `Serialize`/`TryDeserialize` bodies (A):

- `PacketLogin.TryDeserialize` — IL `115`, `52` instructions, `26` anchors; field anchors load `Ticket`, `Guid`, `Version`, `Unknown`.
- `PacketTunneledClientPacket.TryDeserialize` — IL `124`, `55` instructions, `29` anchors; `PacketTunneledClientWorldPacket.TryDeserialize` has the same IL/instruction/anchor counts.
- `GatewayLoginRequest.Serialize` — IL `81`, `30` instructions, `15` anchors; constants include `100` and `2147483647`. `TryDeserialize` — IL `98`, `44` instructions, `23` anchors, constant `100`.
- `GatewayLoginReply.Serialize`/`TryDeserialize` — constants `101`; IL `47`/`62`.
- `GatewayCharacterLogin.Serialize`/`TryDeserialize` — constants `102`; IL `59`/`78`.
- `CharacterSelectInfoReply.Serialize` — constant `12`; IL `71`.
- `ServerListReply.Serialize` — constant `14`; IL `47`.
- `TunnelAppPacketClientToServer.Serialize`/`TryDeserialize` — constant `16`; IL `59`/`125`.
- `TunnelAppPacketServerToClient.Serialize` — constant `17`; IL `59`.
- `PacketSetLocale.TryDeserialize` — constant `88`; IL `62`.

`PacketLogin.OpCode` is a `const i2` field in metadata; REA did not surface its literal value in a CIL anchor. The value `1` is source-only corroboration (S): `/tmp/opencode/sanctuary/src/Sanctuary.Packet/ClientGateway/PacketLogin.cs:9`, with the read order at lines 22-37: `short` opcode, `string Ticket`, `ulong Guid`, `string Version`, `string Unknown`, then `RemainingLength == 0`.

### Login service and handler flow (A)

Evidence: `Sanctuary.Login.dll` complete member receipt `ev_bafd1845adc3c6ed6384d0b30c6aa718c47e2d03cd20369588e6cc7bb51a69a2` and targeted receipt `ev_e0012e7f3a23cdcd0344d7c7d763126469eb133f308d0ee9d464f531f10db691`.

Observed types include `Sanctuary.Login.GatewayConnection`, `GatewayServer`, `LoginConnection`, `LoginServer`, `LoginServerConnection`, `LoginService`, `PendingCharacterLogin`, and handlers `LoginRequestHandler`, `CharacterLoginRequestHandler`, `CharacterSelectInfoRequestHandler`, `ServerListRequestHandler`, `TunnelAppPacketClientToServerHandler`, `GatewayLoginRequestHandler`, `GatewayCharacterLoginHandler`.

Connection/crypto:

- `Sanctuary.Login.LoginConnection` fields include `_cipher:class:201`, `_useEncryption:bool`, `UserId:u8`.
- `LoginConnection.OnRoutePacket` call edges: `ICipher.Decrypt`, `PacketUtils.UnwrapPacket`, then `OnHandlePacket`.
- `LoginConnection.OnHandlePacket` — IL `243`, `41` anchors; dispatches to `LoginRequestHandler.HandlePacket`, `CharacterCreateRequestHandler.HandlePacket`, `CharacterLoginRequestHandler.HandlePacket`, `CharacterDeleteRequestHandler.HandlePacket`, `CharacterSelectInfoRequestHandler.HandlePacket`, `ServerListRequestHandler.HandlePacket`, and `TunnelAppPacketClientToServerHandler.HandlePacket`.
- `LoginConnection.DecryptUserSupplied` — IL `76`, `16` anchors; `EncryptUserSupplied` — IL `112`, `25` anchors; `InternalSendSecure` — IL `103`, `22` anchors. Call edges include `ServerOptions.get_UseCompression`, `UdpConnection.DecryptUserSupplied`/`EncryptUserSupplied`, `ICipher.Encrypt`, and `PacketUtils.WrapPacket`.
- User strings include `F70IaxuU8C/w7FPXY1ibXw==`, `LoginGateway`, `LoginUdp_6`, `database.json`, `login.json`, `NLog.config`, `NLog.Development.config`, invalid/expired session warnings, gateway challenge/address warnings, and held character-login messages.

Handlers:

- `LoginRequestHandler.HandlePacket` — IL `714`, `137` anchors; call edges: `LoginRequest.TryDeserialize`, `LoginReply..ctor`, `DbUser.get_SessionCreated`, `DateTimeOffset.UtcNow`, `set_Session`, `set_SessionCreated`, `set_LastLogin`, `SaveChanges`, `LoginServerOptions.get_IsLocked`, `AccountInfo..ctor`, `get_MaxCharacters`, `AccountInfo.Serialize`, and `LoginConnection.Send`.
- `CharacterLoginRequestHandler.HandlePacket` — IL `653`, `133` anchors; `ProcessPendingLogins` — IL `376`, `72`; `Admit` — IL `497`, `95`; `CompleteRelease` — IL `117`, `20`; `IsBusy` — IL `52`, `10`.
- `CharacterLoginRequestHandler` fields: `CrashIdleMilliseconds:u4`, `ReleaseRetryMilliseconds:i8`, `HandoffMilliseconds:i8`, `_logger:class:149`, `_gatewayServer:class:16`, `_options:class:137`, `_dbContextFactory:class:245<class:249>`, `_nextReleaseRequestId:u4`, `_pendingLogins:class:317<class:132>`, `_handoffs:class:157<u8,i8>`. Evidence: `ev_b5a472b40c666b0c740f1ec27c7b4a3bf876704a4b9a9bae212d292a974b2f78`.
- `PendingCharacterLogin` fields: `Connection`, `Gateway`, `CharacterId`, `LastRequestAt`, `RequestId`.
- `Admit` calls `Guid.NewGuid`, `Guid.ToString`, `ClientCharacterData..ctor`, `GatewayConnection.get_ServerAddress`, `GuidHelper.GetPlayerGuid`, `ClientCharacterData.Serialize`, and `LoginConnection.Send`.
- `CharacterSelectInfoRequestHandler.HandlePacket` — IL `963`, `217` anchors; builds `AccountInfoCharacterDetails`, `EntityDetails`, `CharacterAttachmentData`, and reads DB character appearance/profile/item fields.
- `ServerListRequestHandler.HandlePacket` — IL `121`, `22` anchors; builds `ServerListReply`/`ClientGameServerData` from `GatewayServer.get_Gateways`.
- `GatewayLoginRequestHandler.HandlePacket` — IL `481`, `89` anchors; calls `GatewayLoginRequest.TryDeserialize`, reads `LoginServerOptions.get_LoginGatewayChallenge`, sends `GatewayLoginReply`, sets server data/address, and may disconnect.
- `GatewayCharacterLoginHandler.HandlePacket` — IL `99`, `17` anchors; calls `GatewayCharacterLogin.TryDeserialize` and `GatewayConnection.MarkOnline`.
- `TunnelAppPacketClientToServerHandler.HandlePacket` — IL `177`, `34` anchors; calls `TryDeserialize`, then `PacketReader.TryRead` and `PacketCheckNameRequestHandler.HandlePacket`.
- `LoginService.ExecuteAsync` — IL `409`, `86` anchors; calls `IDbContextFactory.CreateDbContext`, `Database.Migrate`, `ServiceCollectionExtensions.ConfigurePacketHandlers`, reads `ServerOptions.Port` and `LoginServerOptions.LoginGatewayPort`, periodically calls `CharacterLoginRequestHandler.ProcessPendingLogins`.

### Packet.Common shapes (A)

Evidence: `ev_8a80e7ddbfb7ac22f91b731a0a882b327b4024394a074f6406a2aa01aee1b779`.

- `ClientLoginData`: `Locale:string`, `LocaleId:i4`, `Unknown:bool`, `Unknown2:u1`, `Unknown3:i8`; `TryDeserialize` IL `116`, `51` instructions, `25` anchors.
- `AccountInfo`: `IsMember:bool`, `MaxCharacters:i4`, `IsAdminAccount:bool`; `Serialize` IL `63`.
- `AccountInfoCharacterData`: `Guid:u8`, `Name:string`, `Model:i4`, `Head:string`, `Hair:string`, `ModelCustomization:string`, `FacePaint:string`, `SkinTone:string`, `EyeTint:i4`, `HairTint:i4`, `CharacterAttachments:class:101<class:64>`.
- `ClientCharacterData`: `ServerAddress:string`, `ServerTicket:string`, `CryptoKey:string`, `Guid:u8`, plus `Unknown:i8`, `Unknown2/3/4:string`; `Serialize` IL `153`, `51` instructions, `27` anchors.
- `ClientPcData` is large: `LaunchTicket:u8`, `Guid:u8`, `Position`, `Rotation`, `Name`, `Coins:i4`, `Birthday`, `Age:i4`, `PlayTime:i4`, `IsUnderage:bool`, `IsOpenChatEnabled:bool`, `MembershipStatus:i4`, `Profiles`, `Items`, `QuestData`, `Pets`, `Mounts`, `ActionBars`, `Stats`, `Titles`, `VipRank:r4`, etc. Its `.ctor` is IL `1647`, `521` instructions, `376` anchors; `Serialize` is IL `848`, `291` instructions, `145` anchors.
- `GameServerData`: `Id:i4`, `State:valuetype:564`, `Name:string`, `NameId:i4`, `Description:string`, `DescriptionId:i4`, `RequiredFeatureId:i4`, `ApplicationData:string`, `PopulationLevel:i4`, `PopulationOobData:string`.

Source corroboration (S): `/tmp/opencode/sanctuary/src/Sanctuary.Packet.Common/Login/AccountInfoCharacterDetails.cs:4-20` places `AccountInfoCharacterDetails` in namespace `Sanctuary.Game.Packet.Common` and serializes `HeadshotUrl` then `AccountInfoCharacterData`; this matches the Login handler call edge `Sanctuary.Game.Packet.Common.AccountInfoCharacterDetails..ctor`.

---

## Game logic

### Core packet IO and crypto plumbing (A)

Evidence: `ev_3d36d3c2f2afb4127344124cb93037478f9a032a85e021716ea1a72e107d1397`.

- `Sanctuary.Core.IO.PacketReader` fields: `position:i4`, `length:i4`, `reference:u1&`. Methods include `TryReadInt16`, `TryReadUInt16`, `TryReadInt32`, `TryReadUInt32`, `TryReadInt64`, `TryReadList`, `TryRead(string&)`, and `TryReadExact`; several call `BinaryPrimitives` member refs and `Encoding.UTF8.GetString`.
- `Sanctuary.Core.IO.PacketWriter` fields: `_stream`, `_writer`; overloads `Write` for `u1`, `bool`, `i2`, `u2`, `i4`, `u4`, `i8`, `u8`, `r4`, `r8`, `string`, `u1[]`, spans, dictionaries, and serializable objects; `WritePayload`.
- `Sanctuary.Core.IO.PacketUtils.Magic` is `u4`; `WrapPacket` IL `155`, `71` instructions, `30` anchors, constant `-204167735`; `UnwrapPacket` IL `183`, `97` instructions, `41` anchors, same constant.
- `CipherCCM`: fields `_aesCcm`, `_encryptCounter:u8`, `_decryptCounter:u8`, `TagLength:i4`, `NonceLength:i4`; `Decrypt` IL `220`, `104` instructions, `49` anchors; `Encrypt` IL `199`, `79` instructions, `40` anchors; constants `13` and `16`. Calls include `AesCcm..ctor`, `RandomNumberGenerator.Fill`, `RandomNumberGenerator.GetBytes`, `AesCcm.Encrypt`, and `AesCcm.Decrypt`.
- `CipherRC4`/`RC4`: `CipherRC4.Initialize` IL `33`, `13` instructions, `5` anchors; `RC4..ctor` IL `140`, `78` instructions, `20` anchors, constants `256`/`255`; `RC4.Apply` IL `169`, `74` instructions, `26` anchors.
- Configuration types:
  - `GatewayServerOptions`: `Environment`, `ClientVersion`, `ServerAddress`, `LoginGatewayAddress`, `LoginGatewayChallenge`, `ShowMemberNagScreen`.
  - `LoginServerOptions`: `LoginGatewayPort:i4`, `LoginGatewayChallenge:string`, `IsLocked:bool`, `DefaultTitleId:i4`, `DefaultProfileId:i4`, `StartingCoins:i4`, `StartingStationCash:i4`, `UnlockAllTitles:bool`, `UnlockAllProfiles:bool`.
  - `ServerOptions`: `Section:string`, `Port:i4`, `UseCompression:bool`.
- `DatabaseExtensions.AddDatabase` IL `114`, `44` instructions, `25` anchors; calls `IConfiguration.GetSection`, `ConfigurationBinder.Get`, `DatabaseOptions.get_Provider`, `ServiceCollectionExtensions.AddMySqlDatabase`, and `AddSqliteDatabase`.

### Game assembly inventory (A)

Paged type names from retained evidence include managers (`ChatCommandManager`, `InteractionManager`, `ResourceManager`, `RewardManager`, `TradeManager`, `ZoneManager`), zone types (`BaseZone`, `CombatZone`, `HousingZone`, `WorldZone`, `ZoneTile`), routines (`RoutineManager`, `SequentialRoutine`, `ParallelRoutine`, `PeriodicRoutine`, `TimeoutRoutine`, etc.), resource collections, definitions, entities, quests, and scripting interfaces. This is a server-side game simulation assembly, not a client UI assembly.

No native boundary or P/Invoke evidence was found in `Sanctuary.Game.dll`.

### Representative game logic methods (A)

Evidence: `ev_45a1d72c8b1d991256ba177da75771bc88aeca0ef2c2cf175c08fe059b1c7dbe`.

| Type/method | IL / instructions / anchors | Notes |
|---|---:|---|
| `Sanctuary.Game.ChatCommandManager.TryHandle` | `221` / `86` / `48` | Calls `IChatCommandView.get_RequiredRole`, `Player.get_ChatCommandRole`, `IChatCommand.Handle`, `ChatHelper.SendSystemMessage`; user string `You do not have permission to use this command.` |
| `Sanctuary.Game.InteractionManager.Load` | `214` / `78` / `36` | Loads `IInteraction` implementations; string `Loaded {count} interactions.` |
| `Sanctuary.Game.ResourceManager.Load` | `2455` / `828` / `561` | Loads model/item/collection/store/zone/profile/quest/reward/ability definitions; many validation strings |
| `Sanctuary.Game.RewardManager.TryGrantItem` | `896` / `309` / `194` | Constants include `19`; strings for unknown item definition and duplicate mount/pet checks |
| `Sanctuary.Game.TradeManager.OfferItem` | `847` / `341` / `207` | Player trade offer flow with revision/session logging |
| `Sanctuary.Game.ZoneManager.TryGetOrCreateZoneInstance` | `210` / `92` / `33` | Zone instance creation by definition id and instance key |
| `Sanctuary.Game.Zones.BaseZone.OnClientIsReady` | `200` / `76` / `34` | Constants `2500`, `100`; part of client-ready synchronization |
| `Sanctuary.Game.Zones.WorldZone.SendAdventurersJournalInfo` | `4909` / `1760` / `868` | Large journal packet builder with many hard-coded numeric ids |
| `Sanctuary.Game.Resources.QuestDefinitionCollection.Load` | `662` / `240` / `139` | Strings `Quests.json`, duplicate goal/no-target validation messages |
| `Sanctuary.Game.Quests.QuestLog` | field `_quests:class:257<i4,class:608>` | Also `ActiveQuestId` and `PendingTurnInQuestId` backing fields |
| `Sanctuary.Game.Entities.Player.GetPortraitPacket` | `389` / `123` / `72` | Strings include `portrait.crc`, `headshot.png`, `portrait.png` |
| `Sanctuary.Game.Entities.Player.TeleportToZone` | `277` / `102` / `52` | Constant `214`; zone transition routine |

Resource file strings observed in `ResourceManager` include `CharacterCreate`, `HairMappings.txt`, `HeadMappings.txt`, `SkinToneMappings.txt`, `FacePaintMappings.txt`, `ModelCustomizationMappings.txt`, `Models.txt`, `ClientItemDefinitions.json`, `Collections.json`, `CollectionCoins.json`, `CollectionNodePools.json`, `CollectionNodeTypes.json`, `CollectionNodeSpawns`, `CoinStoreItems.json`, `ItemClasses.txt`, `EquipmentSlotDefinitions.txt`, `ItemCategories.txt`, `ItemCategoryGroups.txt`, `TintGroupMappings.txt`, `Stores.json`, `StoreBundles.json`, `ZoneEnvironments`, `Houses.json`, `Pets.json`, `Mounts.json`, `Profiles.json`, `QuickChats.json`, `PlayerTitles.json`, `PointOfInterests.json`, `Consumables.json`, `Npcs.json`, `NpcMovements.json`, `NpcAmbient.json`, `NameFilter.txt`, `Quests.json`, `NavMeshes`, `Rewards.json`, `CombatAbilities.json`, and `CombatJobs.json`.

### Gateway game-session handling (A)

Evidence: `ev_9b424c78fa8928ad61e64771366d2636035ce9710d974497ca0ae3bdbf415568`.

- `Sanctuary.Gateway.GatewayConnection` fields include `_loginClient`, `_loginSession:u8`, `_zoneManager`, `_options`, `_resourceManager`, `_dbContextFactory`, `_cipher`, `_useEncryption:bool`, `Player`, `Locale`, `OnReleased`.
- `GatewayConnection.OnRoutePacket` IL `105`, `42` instructions, `21` anchors; calls `ICipher.Decrypt`, `PacketUtils.UnwrapPacket`, then `OnHandlePacket`.
- `GatewayConnection.OnHandlePacket` IL `128`, `63` instructions, `26` anchors; dispatches to `PacketLoginHandler.HandlePacket`, `PacketTunneledClientPacketHandler.HandlePacket`, and `PacketTunneledClientWorldPacketHandler.HandlePacket`.
- `GatewayConnection.CreatePlayerFromDatabase` IL `4228`, `1265` instructions, `994` anchors; reads DB character appearance, position, profiles, items, quests, collections, mounts, pets, action bars, titles, friends, ignores, guild, and station cash, then constructs `Sanctuary.Game.Entities.Player`.
- `GatewayConnection.SavePlayerToDatabase` IL `1032`, `298` instructions, `218` anchors; writes position/rotation, active profile/title, play time, chat bubble settings, pets, and calls `DbContext.SaveChanges`.
- `GatewayConnection.SendSelfToClient` calls `CollectionDefinitionCollection.CreateClientCollections`, `IQuestManager.GetClientQuestData`, `PacketSendSelfToClient..ctor`, `ClientPcData.Serialize`, and `SendTunneled`.
- `GatewayServer.TryReleaseIdleCharacter` IL `416`, `156` instructions, `85` anchors; uses `MillisecondsSinceLastReceive` and `OnReleased`.
- `GatewayService.ExecuteAsync` IL `685`, `220` instructions, `132` anchors; strings include `Cannot start {server}, failed to connect to database.`, `GatewayServer`, `LoginClient`, and `started and is listening on port`.
- `Sanctuary.Gateway.LoginConnection.OnRoutePacket` has constants `101` and `104`, matching the gateway/login reply and app-packet opcodes observed in packet anchors.
- `PacketPortraitDataRequestHandler.HandlePacket` IL `145`, `61` instructions, `27` anchors; strings `PacketPortraitDataRequestHandler` and `PacketPortraitDataRequest`.
- `En/US` locale string `en_US` appears in gateway observed strings.

---

## Launcher client bootstrap

Launcher artifact is the only R2R assembly. Evidence: `ev_4a168c54c04b2a331f2a7fd6771d910a897fee10ab736b2bbfd87c11f1518b58` (summary), `ev_e9b94e5fc5266d82645da86b17b7a3e74beb02da7bbed7707dbbb6d926b0c558` (targeted types), `ev_44f87ecf410ba13feda3ae08df20f445fbc52a769a1de3193c786785e7bcdbfe` (async state machines).

### Bootstrap and UI (A)

- `Launcher.Program.Main` — IL `78`, `23` instructions, `15` anchors; calls `SetupNLog`, `CurrentDomain_UnhandledException`, `ViewModels.Settings.get_Instance`, `Services.DiscordService.Start`, and `BuildAvaloniaApp`.
- `Launcher.Program.SetupNLog` — IL `104`, `31` instructions, `19` anchors; calls `Directory.GetCurrentDirectory`, `Directory.Exists`, `Directory.CreateDirectory`, `NLog.Targets.FileTarget..ctor`, and `set_FileName`.
- `Launcher.App.OnFrameworkInitializationCompleted` — IL `61`, `24` instructions, `10` anchors; constructs `Launcher.Views.Main`.
- `Launcher.App` fields include `GitHubRepoUrl:string`; user string `https://github.com/Open-Source-Free-Realms/Launcher`.
- User strings include `avares://Launcher/App.axaml`, `logs`, `Launcher.log`, `OSFRLauncher`, ` v`, `https://opensourcefreerealms.com`, and `Text.Server.SecureApiWarning`.
- Call edges include `Velopack.UpdateManager.get_CurrentVersion` and `Velopack.SemanticVersion..ctor` for `App.get_CurrentVersion`.

### Settings/server manifest/bootstrap (A)

- `Launcher.ViewModels.Main.OnLoad` — IL `138`, `52` instructions, `28` anchors; calls `Settings.get_Instance`, `Settings.get_ServerInfoList`, `Server..ctor`, `AddServer.TryAddServerAsync`, and `UpdateDiscordActivity`.
- `Launcher.Models.ServerInfo` fields include `<Url>`, `<WebApiUrl>`, `<LoginServer>`, `<RememberPassword>`, `<LegacyPassword>`, plus username backing fields.
- `Launcher.Models.ServerManifest` fields include `ManifestVersion:i4`, `FileName:string`, `<WebApiUrl>`, `<LoginServer>`, `<Version:i4>`.
- `Launcher.Helpers.Constants` fields: `LogFile`, `SettingsFile`, `SaveDirectory`, `ServersDirectory`, `ClientExecutableName`, `DirectXDownloadUrl`, `DefaultServerUrls:string[]`, `LogsDirectory`. Its `.cctor` calls `AppContext.get_BaseDirectory`.
- User strings include `No servers found in settings. Adding default servers.`, `Launcher.xml`, `servermanifest.xml`, `ServerManifestV1.xsd`, `ServerManifest.xsd`, `text/xml`, `application/xml`, and `Server manifest is unsupported.`
- `<TryAddServerAsync>d__5.MoveNext` — IL `432`, `150` instructions, `89` anchors; calls `HttpHelper.GetServerManifestAsync`, reads `ServerManifest.Name`, `Description`, `WebApiUrl`, `LoginServer`, creates `ServerInfo`, and saves settings.
- `<GetServerManifestAsync>d__13.MoveNext` — IL `909`, `322` instructions, `225` anchors; calls `UriHelper.JoinUriPaths`, `HttpClient.GetAsync`, checks content type, reads stream, `XmlHelper.TryDeserialize`, and `ServerManifestV1.ToServerManifest`.

### Web login/register and client launch (A)

- `<ProcessAsync>d__14.MoveNext` (login) — IL `807`, `269` instructions, `173` anchors, constant `401`; builds `Launcher.Models.LoginRequest.Username/Password`, reads `ServerInfo.WebApiUrl`, calls `HttpClientJsonExtensions.PostAsJsonAsync`, checks `HttpStatusCode`, reads `LoginResponse` via `ReadFromJsonAsync`, reads `SessionId` and `LaunchArguments`, saves remembered credentials, then calls `LaunchClientAsync`.
- `<ProcessAsync>d__9.MoveNext` (register) — IL `541`, `178` instructions, `115` anchors, constant `409`; builds `RegisterRequest`, posts to the Web API, and handles conflict/success.
- User strings include `login`, `register`, `Text.Login.Unauthorized`, `Login failed for server: '{Name}'. API returned {StatusCode}: {Reason}.`, `Invalid login API response from server: '{Name}'. Response body was null or SessionId was missing.`, `Text.Register.Conflict`, and `Text.Register.Success`.
- `<LaunchClientAsync>d__18.MoveNext` — IL `802`, `243` instructions, `179` anchors; checks `Dx9Helper.IsInstalled`, reads `ServerInfo.LoginServer`, `Settings.Locale`, `ServerInfo.SavePath`, uses `WineHelper.GetPath` on non-Windows, creates `Process`/`ProcessStartInfo`, sets `WorkingDirectory`, `FileName`, `Arguments`, `UseShellExecute`, adds `Exited`, and starts the process.
- Launch argument/user strings: `Server=`, `SessionId=`, `Internationalization:Locale=`, `Client`, `FreeRealms.exe`, `Unable to launch the game, wine is not installed.`, `Unable to launch the game, your operating system is not supported.`, and `Failed to start the client process for server: {Name}.`
- `<VerifyClientFilesAsync>d__25.MoveNext` — IL `1373`, `464` instructions, `294` anchors; uses `Downloader.DownloadService`, `Parallel.ForEachAsync`, settings `ParallelDownload`/`DownloadThreads`, verifies hashes, and downloads missing files.
- `<DownloadFileAsync>d__27.MoveNext` — IL `1065`, `392` instructions, `229` anchors; calls `UriHelper.JoinUriPaths`, `Directory.CreateDirectory`, `DownloadFileTaskAsync`, and `File.Create`.
- `<GetClientManifestAsync>d__24.MoveNext` — IL `343`, `120` instructions, `78` anchors; calls `HttpHelper.GetClientManifestAsync`.
- `HttpHelper.CreateHttpClient`/`CreateDownloadHttpClient` use `SocketsHttpHandler`, custom `HappyEyeballsConnectAsync`, `HttpLoggingHandler`, user agent `OSFRLauncher` plus version, and settings-driven download thread limits.

### Launcher source corroboration (S — source-only)

`/tmp/opencode/sanctuary/src/` does not contain the shipped `Launcher.dll` project, but it contains an independent dev client whose behavior matches the compiled launch flow:

- `Sanctuary.DevClient/GameClient.cs:15` uses `FreeRealms.exe`; line 17 uses `Internationalization:Locale=8`; lines 26-28 include `AssetDelivery:IndirectServerAddress=...` and `Portrait:UploadUrl=.../image`; lines 53, 72, and 79 pass `SessionId=...` and post `/login`/`/register`; lines 95-111 create `ProcessStartInfo` with `wine` on non-Windows and add `Server={address}:{port}`.
- `Sanctuary.DevClient/ClientInstaller.cs:14-19` uses `https://opensourcefreerealms.com/client`, `clientmanifest.xml`, `FreeRealms.exe`, and `OSFRLauncher` paths.

These source facts corroborate the compiled launcher strings and launch arguments but are not themselves evidence from `Launcher.dll`.

---

## Inferred/unknown fields

Explicitly unknown or unresolved from compiled metadata (A):

- `Sanctuary.Packet.PacketLogin.Unknown:string` — name and read position are observed; semantic meaning is unknown.
- `Sanctuary.Packet.Common.ClientLoginData.Unknown:bool`, `Unknown2:u1`, `Unknown3:i8` — observed names/types; semantics unknown.
- `Sanctuary.Packet.Common.ClientCharacterData.Unknown:i8`, `Unknown2:string`, `Unknown3:string`, `Unknown4:string` — observed names/types; semantics unknown.
- `Sanctuary.Packet.Common.ClientQuest.Unknown2:bool`, `ClientQuestData.Unknown:bool` — observed; semantics unknown.
- `Sanctuary.Packet.GatewayLoginRequest.Data:class:333` — a build-local signature token, not a resolved type name in the retained CIL; do not rename it without source/type-resolution evidence.
- Fields such as `_cipher:class:201`, `_options:class:137`, `_dbContextFactory:class:245<class:249>`, `_pendingLogins:class:317<class:132>`, `_handoffs:class:157<u8,i8>`, `Entities:class:65<class:337>`, and `Servers:class:65<class:341>` are only partially decoded generic/token signatures; exact generic arguments require source or full type-spec resolution.
- `PacketLogin.OpCode` literal value is not in the CIL anchor set. Value `1` is **S**, not **A**.
- `PacketUtils.Magic` constant `-204167735` is observed in `WrapPacket`/`UnwrapPacket`, but its byte order/protocol role is **I** unless corroborated by source or packet capture.
- `WebAPIOptions.MemberByDefault` is observed as a `bool` property; that it controls new-account membership is **I** from the name and source context, not proven by the retained CIL alone.
- Launch argument mapping (`Server=`, `SessionId=`, `Internationalization:Locale=`) is directly observed as user strings and process argument assembly; which exact client build consumes each argument is **I**.
- Call-edge sequences (for example `OnRoutePacket` → `ICipher.Decrypt` → `PacketUtils.UnwrapPacket` → handler dispatch) are observed call references, not a decompiled control-flow proof. Branch conditions and error paths remain **I** where not described by source.
- The presence of `ReadyToRun` in `Launcher.dll` proves a native header/precompiled code form for that .NET assembly. It does **not** by itself prove iOS native code, an iOS app binary, or execution of native code during this analysis.

---

## Evidence IDs & limitations

### Artifact identity evidence (A)

- Launcher: `ev_7473e05b0f7b02899619b164ba5c272f241601d08796449f28fc74a5de53b6fa`
- Packet: `ev_416972200ac0a91b30313dcaec38f72959abda7f8b5045d1f975ca3b8d5da7ac`
- Packet.Common: `ev_0d1b6aaaeea37dfb75e61ac44b7b67b74c26c65990ab6862305f757c79ccf9fe`
- Game: `ev_f4c4f5be8f937a33bf5e285f42bb1db06fb4b03c943a6784c8d2c5102d05d80a`
- Core: `ev_3ec696f58fc2b2947a5913e7da63bb0f8d89ca0154a65df3713e547c37e4e54d`
- WebAPI: `ev_583e217721f7ea88d391a64eeab135fccea7c5a9fc8bf04135bfb8c680c586e6`
- WebAPI complete artifact call: `ev_ebf4ed20be0ec1b80a76f75000f92736b2c44bf93456c22e6c193fa87d064aa0`
- Login: `ev_57d3a3a806224ba43656cd3be80ff0e1fde830922bd046f479259c64a72431b1`
- Gateway: `ev_b34faea40c9382cf35716bdad344cc8149e269bac8fef4d03f9acb0c498eefb5`

### Member inventory / retained parent evidence (A)

- Launcher complete/retained parent: `ev_40ac602fa6d919d79bb8616d13392a3d40a0804ec4c65013f0db92ea9376e0a6`
- Launcher summary: `ev_4a168c54c04b2a331f2a7fd6771d910a897fee10ab736b2bbfd87c11f1518b58`
- Packet complete: `ev_f37f12a7e80609f6e3a259204d6c1cbdad24548d9d63ba07859ba7cc2be8fdcb`
- Packet summary: `ev_5460a3290a568b912a8847e76df3b878c0e5190a6682d099a352be877aaceb09`
- Packet.Common complete: `ev_09fbaa3560c9777c8f850d19875d2e5e49429ea440831c54051b87456a2bdbfd`
- Packet.Common summary: `ev_1bf5c191d8ab4605531ba8960b36721cf006c7dd12cecb835c5f630c95c6a7a9`
- Game complete/retained parent: `ev_a49e0e9899fc5cc71af2725469ff57fa9d4f14986cefcdab2119600db45f2bbd`
- Game summary: `ev_bd77f2765511ad404a07d17f9ffb5e2b30ae1112b6c9206661e7a14433d48806`
- Core complete: `ev_72506743c8599a0c1de8cbe7eb29718e8da06d5aa41a849bdad3974586f1fd36`
- Core summary: `ev_55a1be167b6fe9b475b4ddb5f767462b019785e94a742789fc8a0aa3baf95e13`
- WebAPI complete: `ev_ed3805a6e3c325cade56528cc831e0b32eaa10c0dad18d9ce0ff2c81e287c5c9`
- WebAPI summary: `ev_d1e28c1c863c1893bedd8fcd8c76990644b07cf3529bc66aa22748dac5755865`
- Login complete: `ev_bafd1845adc3c6ed6384d0b30c6aa718c47e2d03cd20369588e6cc7bb51a69a2`
- Login summary: `ev_0c49c54f6f1115af84f3725315e13ff20797cc8020bb549938411326604fae3e`
- Gateway complete/retained parent: `ev_44f2dc9b1710995830b4588643f305be3561b170865addb2afacbaf45f5e2aa7`
- Gateway summary: `ev_c518b69877d667a7934486e05c46a1f5dfe0effd4a6d80c7221cf044369b7d1b`

### Targeted extraction evidence (A)

- WebAPI targeted types: `ev_85344fba1ef7702d7555347eb38a931df45b9224348d231dbdf226b92ca9dc39`
- WebAPI async state machines: `ev_9eb2add2b087423f624d19a61fc46df974484f6a5e1d89626f7880be905bec00`
- WebAPI models/options/endpoints compact extraction: `ev_31a6dd0852c96b64114f38f4bca9e5223879f56c2c4bba24dbc134e3af098007`
- Packet targeted packets: `ev_c2cc945ef587ecbd5fb3fe86b25ae2971a3892a99e9148aad62be3adf011d300`
- Packet selected anchors/fields: `ev_9de6140d1f01c2f2cafdabc5335221c4edd99994725db89750b2359eae02e5a0`
- Packet earlier selected anchors: `ev_c96087c40d1e865dd2dcee369956ddf78f46d8e385f73a7fe7d4450ca220e499`
- Packet.Common targeted shapes: `ev_8a80e7ddbfb7ac22f91b731a0a882b327b4024394a074f6406a2aa01aee1b779`
- Core targeted IO/crypto/options: `ev_3d36d3c2f2afb4127344124cb93037478f9a032a85e021716ea1a72e107d1397`
- Login targeted types: `ev_e0012e7f3a23cdcd0344d7c7d763126469eb133f308d0ee9d464f531f10db691`
- Login `CharacterLoginRequestHandler` fields: `ev_b5a472b40c666b0c740f1ec27c7b4a3bf876704a4b9a9bae212d292a974b2f78`
- Launcher targeted types: `ev_e9b94e5fc5266d82645da86b17b7a3e74beb02da7bbed7707dbbb6d926b0c558`
- Launcher async state machines: `ev_44f87ecf410ba13feda3ae08df20f445fbc52a769a1de3193c786785e7bcdbfe`
- Gateway targeted handling: `ev_9b424c78fa8928ad61e64771366d2636035ce9710d974497ca0ae3bdbf415568`
- Game targeted logic: `ev_45a1d72c8b1d991256ba177da75771bc88aeca0ef2c2cf175c08fe059b1c7dbe`

### Retained type-page evidence (A)

- Launcher types page: `ev_e5c1bc63d18ac0672a6234c066d70378c4ca8539028a738e9d43e04699dd967d`
- Game types page: `ev_059c5a060ae215a7c193aa9303e508bd5ea76589a0fbb4a24f92e0005b69c5fb`
- Gateway types page: `ev_692f4a3ce90cc26a7a51d977e92ba74351d209664bae0877599c28d055580a4c`

### Native-boundary evidence (A)

- Launcher: `ev_ff363f4a6990328c53b641b427798cc7054307d8e272bf1f40ffc1038dc1b989`
- Packet: `ev_d7570a64d00d5748d54252aea7d9f67fd27e2e25e2ee1d6eeb526b368cf09ace`
- Packet.Common: `ev_4a721a99c82a66e4770a09ee7d1e2795feefd328d88ffbaf9b896745eaf38cc8`
- Game: `ev_28acbbbfa76a05057b5b8083dee34d1afac91cc5a1a0569ca10fb8600236cbc5`
- Core: `ev_10209759f9a48067d83c88c9ab3f1746978b641ab5471fc510c97f3f71656bda`
- WebAPI: `ev_904803233d459f6e7ceddf5b39748eed0bd1a2049d54b08b33fa7bd1de073690`
- Login: `ev_e5781e6efcf266997b20940f62d79357ad6520e174c2e2c860dbdcfa724772f8`
- Gateway: `ev_1a5a347e3a9522660bf645ce7512db346c39fb8d0d4e1d07d6b36cdaffe049ea`

### Limitations

- Static inspection did not load assemblies, resolve dependencies through the CLR, decompile C# source, or execute target code.
- Tokens are build-local; they are meaningful only with the SHA-256 and MVID listed above.
- CIL anchors come from file-backed method bodies. Abstract/interface methods can have IL `0`; they still exist as metadata methods.
- `class:NNN`, `valuetype:NNN`, `mvar:0`, and similar strings are REA signature renderings, not necessarily source-level type names. Generic arguments are only resolved where REA decoded them.
- Call edges are direct CIL call references. They do not by themselves prove branch conditions, runtime dispatch through DI, or that a call is always reached.
- User strings prove literals exist in the artifact, not which execution path loads them unless an anchor in a named method body was also observed.
- P/Invoke rows, had they existed, would prove declarations only, not that a native export exists or works. Here all P/Invoke counts were zero.
- Source-tree corroboration (`/tmp/opencode/sanctuary/src/`) is a separate local checkout, not one of the eight compiled artifacts; every source-only statement is labeled **S**.
- No iOS app binary, iOS framework linkage, or native iOS UI implementation was among the eight artifacts. The evidence here is for .NET server/launcher components that support the FreeRealms-style client protocol and WebAPI contract.
