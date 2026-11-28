# Packet catalog and compiled-client configuration xrefs

This note records the next concrete mapping step after
`14-compiled-client-inventory-and-1to1-boundaries.md`. It adds a source-backed
packet routing catalog to the iOS core and documents the first REA-confirmed
configuration/zone/Lua xrefs in the shipped client. It does **not** claim that
the iOS app implements the decoded semantics, and it does **not** change the
"partial compiled-client verification" status.

## Sanctuary packet inventory

Source root: `/tmp/opencode/rea-build/sanctuary/src/Sanctuary.Packet`.
Machine-readable inventory: `/tmp/opencode/sanctuary-packet-inventory.json`;
human summary: `/tmp/opencode/sanctuary-packet-inventory.md`.

| Property | Count |
|---|---:|
| Distinct top-level opcode values | 77 |
| Distinct typed opcodes (`byte`/`short`) | 89 |
| Packet classes/structs | 352 |
| Classes declaring their own opcode | 341 |
| Nested opcode declarations | 93 |
| Classes with nested/sub-opcodes | 263 |
| Nested opcode families | 34 |
| Independent typed-opcode collisions | 0 |
| Opcode values reused by `byte` and `short` protocols | 12 |
| Exact class-name matches in FreeRealms.exe RTTI | 73 |

The same numeric opcode can belong to the login (`byte`) and gateway (`short`)
protocol spaces; the inventory preserves the wire type. Nested `new const
OpCode`/`SubOpCode` values are sub-opcodes inside a family, not independent
global opcodes (for example `FriendListPacket` is gateway `74/1`, not `1`).

### Swift integration

Two Foundation-only sources were added to `OSFRCore`:

- `ios/Launcher/Services/PacketCatalog.swift` — effective opcode → Sanctuary
  class names, independent RTTI-verified name set, and lookup helpers.
- `ios/Launcher/Services/SanctuaryPacketInventory.swift` — compact JSON-derived
  metadata for all 352 classes: wire type, effective opcode, sub-opcode,
  direction hint, declared field names/types and RTTI verification flag.

`GatewayWorldPacket` gained a `mapped(Int16, Int16?, [String], Data)` case.
When a known opcode/sub-opcode has no hand-written decoder, the raw payload is
retained verbatim and the observation records a per-class count plus the last
raw payload. No simulated or cached value is inferred from these packets. A
family with any known sub-opcode is only matched as a sub-opcode, so payload
bytes are never misread as a routing value. Unknown opcodes remain
`.unknown(Int16, Data)`.

`ios/Tests/OSFRCoreTests/PacketCatalogTests.swift` verifies top-level and
sub-opcode preservation, unknown-opcode fallback, inventory counts and the
`FriendListPacket` metadata (`short`, `74/1`, `Friends` field, RTTI-verified).
Linux verification after the change:

```text
TMPDIR=/tmp/opencode swift test --package-path ios \
  --scratch-path /tmp/opencode/osfr-swift-test-chunks
Test Suite 'All tests' passed
Executed 216 tests, with 1 test skipped and 0 failures
```

## REA-confirmed configuration consumers in `FreeRealms.exe`

All observations below use the exact artifact SHA-256
`26cc1c522a45e71fb57882da515f65bac45c8c8b8c8c8b7e740c0cea81c52a733351`.
Rizin required `aaa` before `axt`; bare `axt <address>` is rejected by this
provider version.

### Launch configuration files and keys in `main`

| Evidence ID | Observation |
|---|---|
| `ev_46aba0216df602f1b27a634bc8225cd5c7d40c76d4534d62eccaa5d5f9feb948` | `aa` + `axt` finds `main` pushes for `SessionId` (`0x4036bd`), `CasSessionId` (`0x403675`), `Ticket` (`0x40362d`), `UserOptions` (`0x403557`), `UserOptions.ini` (`0x403552`), `ClientConfigOverride.ini` (`0x4034ca`) and `ClientConfig.ini` (`0x403402`). |
| `ev_eaf13b0dae248572711ee3178da0ff9263ded5e22dd5c0cb6d6bcf42d6bec141` | `main` loads `Inifile`, reports `Failed to load the config file "%s".  Please specify a valid ini file.\n` on failure, then calls config-load helpers with `ClientConfigOverride`/`ClientConfigOverride.ini` and `UserOptions`/`UserOptions.ini` (buffer size `0x100`). |
| `ev_0a39a400e6161facbfea8eb722ad635c0b00174043b913263adeb9acbe6d1c3d` | `main` reads `Server` (`0x403609`), `Ticket` (`0x40362d`), `Key` (`0x403651`, string at `0x175b350`), `CasSessionId` (`0x403675`), `Guid` (`0x403699`) and `SessionId` (`0x4036bd`) from the default config section; missing required fields fall through to `WebResources`/`GameCrashUrl`. |

The compiled client reads credential-like keys from its launch config. This
audit records only the key names and addresses; no credential value was
provided, requested, captured or stored.

### Setting consumers

| Setting | Evidence ID / address | Observation |
|---|---|---|
| `StartingZone` | `ev_899aca2b893427f6b1978c7c2f860270f73799edc576ffc51127e4ff338bc6dc`; `fcn.0090e8a0` (`0x90e8c5`, `0x90e8d1`) | The function compares stored zone state (`[this+0x788]`, guard at `[this+0x668]`) with an argument zone ID. Either side being zone `3` selects the string `StartingZone` instead of the empty string; it calls `0x8a9010`, stores the new zone at `[this+0x788]`, and calls `0x9046e0` with `(newZone == 3)`. |
| `PlayerName` | `ev_899aca2b893427f6b1978c7c2f860270f73799edc576ffc51127e4ff338bc6dc`, `ev_607383fe657b0b463b9b146158a9fce667a5227c943fca38ead64ffee4c064a8`; `fcn.0097c280` (`0x97c2d3`) | A lazy getter caches `PlayerName` into global `0x1be5240`. The cached string is then passed as the name of a `"player"` spawn object via `fcn.0097c260`. This is direct evidence that the name setting affects the local player object, not only a UI label. |
| `ProfileName` | `ev_899aca2b893427f6b1978c7c2f860270f73799edc576ffc51127e4ff338bc6dc`, `ev_2c8d18eee100d421e769b1bddc73c8f871b07c0231c4365d236e7cb442e24fb9`; `fcn.009fad80` (`0x9fb006`) | `ProfileName` is written into an analytics/social payload beside `ProfileId`, `MiniGameId`, `MiniGameType`, `MiniGameCompleted` and `MiniGameResult`. |
| `%sStartingZoneLoad.txt` | `ev_7413fb40ae8aaf7e343ccc579596fe89ccd4332e8d127f72da35fdbc49a51712`; `fcn.009cdcd0` (`0x9cdd3e`) | `BaseClient.virtual_80` caller formats a zone-specific `StartingZoneLoad.txt` filename, opens it, then parses `^`-delimited rows into 1024/0x400-byte and 0x8000-byte buffers. The exact row schema remains undecoded. |
| `LuaCall` | `ev_899aca2b893427f6b1978c7c2f860270f73799edc576ffc51127e4ff338bc6dc`, `ev_b64e8d9db293291b765fd8fb6ad5cdfe5dd88a477618c1fa21a65fb6b23f387b`, `ev_aa254f63b431114f61ec39b920e05a3aae0c19e31371e219af6e7a5d4eb728ef` | The two xrefs are virtual field-name getters: `0xa3e1f0` belongs to `WhatsNewDataSource.virtual_4` and `0xa414fc` to `NudgeDataSource.virtual_4`; each simply returns `"LuaCall"` beside fields such as `TitleStringId`, `StringParam1` and `Param1`. They expose a server-provided Lua callback field, not a generic Lua dispatcher. `BindCommandToLua` has no direct xref under `aaa`; no Lua dispatch semantics are claimed. |

The string `Lua Spawn and automount: id %d` is a log message in a mount routine
at `0xbff7ff` (`ev_7569299b1d27716c710eb682869433e88c907c6ebada27930a190e5fc23c190c`),
written through `ClientMountLog.txt`; it does not by itself prove a Lua script
call.

`fcn.009fad80` also writes `PlayerName`, `PlayerId`, `Race`, `Gender`,
`LocationX` and other fields into the same payload
(`ev_7f230195fee4737a83a88caee1b02f080c96a757ab2af35b6b258bc972c54f3e`).
`fcn.0090e8a0` was disassembled in full in
`ev_7c56375ea88e387e5f50714933fb27325d6d9b86e4cac50899472ae40d0b2b24`;
`fcn.0097c280` in `ev_607383fe657b0b463b9b146158a9fce667a5227c943fca38ead64ffee4c064a8`.

## Additional compiled-client evidence (same target)

| Evidence ID | Observation |
|---|---|
| `ev_5014d618df8315a595e8576d8c214549bde0444aba317b6298da0cf1d4bf702b` | `aaa; s 0x0090e8a0; axt` finds two call sites: `0x947306` and `0x947c07`. Both sit in a `BaseClient.virtual_108` region and pass a stack argument into `fcn.0090e8a0` immediately before zone-related fields at `[esi+0x784]`/`[esi+0x785]` are written. This is a real zone-transition path, not a config-only helper. |
| `ev_2f650ee857217b35d1ec7ecb87d2a94597a834e687ff5cca90aa288b7dc4606f` | `fcn.009046e0` constructs an `SoeUtil::IString_char_` value `HUD:SetIsInStartingZone` and dispatches a variant payload (type `5`, a byte/bool value from `arg_4h`). This confirms that the zone-3 flag computed by `fcn.0090e8a0` is observable as a HUD command. |
| `ev_ae3854a93313ba66c678ca790b60b74181b7b409f9603f9431eabcc42f94a894` | `fcn.0097c260` is a thin wrapper that forwards the cached `PlayerName` global (`0x1be5240`) into `fcn.0097c090`; it has 65 xrefs. |
| `ev_09898a48dff860e7999ce8d97c45a4cefe6e07779c0735771fcc76358a36fcc4` | `fcn.0097c090` builds the spawn object (calls `fcn.00fc45f0`, `fcn.0097b960` and `fcn.0097bca0`) and is called from the `PlayerName` spawn wrapper and `0x97c243`. The exact spawn transform algorithm is still not decompiled. |
| `ev_6b7ec6c62e75c043152933de7831df53dbcf210bc5473b0b1fc71768638edeaa` | The `%sStartingZoneLoad.txt` parser at `0x9cdd3e` uses `fcn.00402fd0` to open the file, sets delimiter `'^'` (`0x5e`), skips rows beginning with `'#'`, requires at least 3 non-empty fields, reads into a `0x8000`-byte row buffer, then splits into 0x400-byte fields. The row schema remains unnamed. |
| `ev_91a9527c4e24c835c8c57054ebc6c27ba1df7a2dbb7ceaa6f3b55cb965083e91`, `ev_b204e9f19f8621296fbc2401f379cb01123bb5e3e592084f03e20260519e9639`, `ev_90c855125b2f6921456b5a2d2edf2cf26382e1dc30f9cae97fb8252f324a9e3c` | String inventory confirms `SetUserOptionsValue` / `GetUserOptionsValue` (`0x182ca30`, `0x182ca44`), `Coins` (`0x1809994`) and `StationCash` (`0x18211d0`) exist in the shipped image. Direct `aaa; axt` requests for the three setter/getter/string addresses returned no references (`ev_484b9bc8c99f1bfb41e334e0e5af19e45d1fc5ca20455ad1f3dfc2c8c58654c4`, `ev_c0e6499c0eff9c49b2cec8f57a8f04f476141db50d02e66efd913989112aec5b`, `ev_34b793ed06af2e9588607fe189777dbd13518ed27bd3eff9cbc4987913820e03`), so no currency-setting semantics are claimed. |

The packet catalog was also extended with metadata-backed routes that preserve
the `byte` (login) vs `short` (gateway) wire type and the source direction hint
for each of the 352 classes. Direction is a source-derived hint, not proof of
runtime direction; it is not used to fabricate or discard live packets.

## Still unresolved

1. `0x8a9010`, the `0x9cdcd0` row schema, `fcn.0097c090` spawn transform and the
   Lua dispatch targets are not decompiled to semantics; only their string
   xrefs, call sites and (where shown) dispatch payloads are verified here.
2. The 352-class packet inventory is a routing/layout catalog. Field codecs for
   most packets, direction-specific handling and server-side behavior are not
   implemented in Swift.
3. No evidence was found here for the iOS setting named "unlock all tiles" or
   "unlock all profile"; those remain launcher-side affordances, not verified
   client features.
4. Live-device parity, engine material/tile fidelity and Lua/gameplay script
   reconstruction remain open as recorded in notes 12–14.

This is still "source-backed native port with partial compiled-client
verification", not a full 1:1 port.
