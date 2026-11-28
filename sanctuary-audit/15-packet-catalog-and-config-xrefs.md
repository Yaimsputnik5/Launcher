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
| `%sStartingZoneLoad.txt` | `ev_7413fb40ae8aaf7e343ccc579596fe89ccd4332e8d127f72da35fdbc49a51712`; `fcn.009cdcd0` (`0x9cdd3e`) | `BaseClient.virtual_80` caller formats a zone-specific `StartingZoneLoad.txt` filename, opens it, then parses `^`-delimited rows into 1024/0x400-byte and 0x8000-byte buffers. The row schema is now mapped to the resource header's four columns; see "StartingZoneLoad row schema" below. |
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
| `ev_6b7ec6c62e75c043152933de7831df53dbcf210bc5473b0b1fc71768638edeaa` | The `%sStartingZoneLoad.txt` parser at `0x9cdd3e` uses `fcn.00402fd0` to open the file, sets delimiter `'^'` (`0x5e`), skips rows beginning with `'#'`, requires at least 3 non-empty fields, reads into a `0x8000`-byte row buffer, then splits into 0x400-byte fields. The row fields map to the resource header's four named columns; the binary does not expose C++ field names. |
| `ev_91a9527c4e24c835c8c57054ebc6c27ba1df7a2dbb7ceaa6f3b55cb965083e91`, `ev_b204e9f19f8621296fbc2401f379cb01123bb5e3e592084f03e20260519e9639`, `ev_90c855125b2f6921456b5a2d2edf2cf26382e1dc30f9cae97fb8252f324a9e3c` | String inventory confirms `SetUserOptionsValue` / `GetUserOptionsValue` (`0x182ca30`, `0x182ca44`), `Coins` (`0x1809994`) and `StationCash` (`0x18211d0`) exist in the shipped image. Direct `aaa; axt` requests for the three setter/getter/string addresses returned no references (`ev_484b9bc8c99f1bfb41e334e0e5af19e45d1fc5ca20455ad1f3dfc2c8c58654c4`, `ev_c0e6499c0eff9c49b2cec8f57a8f04f476141db50d02e66efd913989112aec5b`, `ev_34b793ed06af2e9588607fe189777dbd13518ed27bd3eff9cbc4987913820e03`), so no currency-setting semantics are claimed. |
| `ev_76c6615f7283558233890cf607ebca9755c097e7d82e99e0b48cee840d5dd210` | The second `fcn.0090e8a0` call site (`0x947c07`) is in the same `BaseClient.virtual_108` zone-transition path. Immediately after it the client writes `[esi+0x785]`, loads `sky.xml` (or a caller-provided sky object), logs `RECEIVED=Begin Zoning ZONE=%s LOCATION=%0.2f, %0.2f, %0.2f`, and rechecks zone IDs `0x1a` / `0x01`. This strengthens the case that `StartingZone` participates in a full zoning transition, not a launch-time label. |
| `ev_c9ff45abcafbe7b9494a03cd4cff8369ea4054494a69c5c736451c60ce8b2f94` | `fcn.009046e0` has three xrefs (`0x90e8f2` in `fcn.0090e8a0`, `0x938396` in `fcn.00936d00`, `0x93d42c` in `fcn.0093d180`). It builds the `HUD:SetIsInStartingZone` command, sets variant type `5`, stores the incoming boolean at the variant payload byte, and calls the 759-xref command parser `fcn.009797a0`. The earlier "switch dispatch" observation is therefore a command construction path, not an unrelated UI feature. |
| `ev_e350e8063d91c8df18d33d7d64f071dcfedda28cbbd9f7f42ca90a4b44fde2ee` | `fcn.0097c090` is now disassembled: it constructs an object at `[this+0x20]`, checks a virtual flag at vtable slot `0xcc`, optionally calls slot `0xd0` with the spawn argument, otherwise iterates an argument array through `fcn.0097b960` and calls `fcn.0097bca0` with two arguments. The result is a spawn builder, but the meaning of `arg_4h`/`arg_8h` and the transform remain unnamed. |
| `ev_e576f20572779178be29eff2d1502621ef6faf33c6c02098e941db2f3deadce3` | The `%sStartingZoneLoad.txt` parser continues past row acceptance: it allocates an object via `fcn.009cdbe0`, splits the row into 0x400-byte fields, constructs strings at object offsets `+0x08` and `+0x18`, and passes the remaining tail to `fcn.00726440`. The first caret field is parsed as an integer into `+0x00` and the tail becomes a boolean byte at `+0x04`; the four positions match the resource header. |
| `ev_45d99719f1323601f6a350579dba9e0326c23186a80743728b524dd8dd1ba89c` | The row loop at `0x9cdd80` reads a `0x8000`-byte row, skips rows whose first byte is `'#'`, counts row bytes until NUL and requires at least 3, allocates a row object with `fcn.009cdbe0`, then uses `fcn.007065d0` and two `fcn.006fb560` calls with delimiter `'^'` and `0x400`-byte fields. The first caret field is parsed as an integer into `object+0x00` by `fcn.007065d0`; the second is copied into `+0x08` and the third into `+0x18` via `fcn.00402ce0`; the remaining tail goes to `fcn.00726440` with `object+0x04`. |
| `ev_ee5de12820bfa7ff184ac273ed9f11a8ff3567fea09f240a789ad6708bc25b43` | The same loop advances to the next row via `fcn.00fbe130`, ends the row list at `0x9cde63`, and destructs the row buffer with `fcn.00fbdae0`; `0x9cde7e` then performs a reference-count release. This is a concrete row-allocation/lifecycle path, not just a string xref. |
| `ev_821e8f49a30afce572f893e35c13a00ada2003345091968dafb5c763c0001d6d` | `fcn.009cdbe0` calls a virtual allocator at vtable slot `+0x08`, stores the caller's collection pointer at `object+0x2c`, clears `object+0x28`, links the object into a doubly linked list through `collection+0x04`/`+0x08`, and increments a count at `collection+0x0c`. It is a generic list-node constructor; the field names still come from the resource file header, not from binary symbols. |
| `ev_6f1f58d3cb2e55e7f825954a1d0fa15b0cfc984cb9ce70b204aa3c63706c73b0` | Full row-loop disassembly at `0x9cdd80`: `fcn.00fbe250` copies the line into a `0x8000`-byte buffer, `'#'` lines are skipped, at least three caret separators are required, `fcn.009cdbe0` allocates the node, `fcn.007065d0` parses the first field, two `fcn.006fb560` + `fcn.00402ce0` pairs copy the next two fields, and `fcn.00726440` parses the tail. |
| `ev_1b41e2e6a9449a1f5301fdeac1993a575a7cf3af5133d65c2977d919b4c95ce4` | `fcn.007065d0` extracts one `^`-delimited token into a `0x800`-byte buffer, supports base-16 when a flag is set and the token begins `0x`, otherwise uses base 10, writes the parsed `int32_t` through its output pointer, and returns the remainder pointer. The row loop does not explicitly set the hex flag. |
| `ev_26a34c699b14813c2b011519bc3954ded958319265b193aedcc17a6bc1e7a39e` | `fcn.00726440` extracts one `^`-delimited token into a `0x800`-byte buffer, calls `fcn.00d869bd`, applies `setnz` to the result, and stores one boolean byte at the caller's output pointer. |
| `ev_aacd002845c8fbbaee5e5d53d98cafd97676bccfa561f5d00c796438f80d5be3` | `fcn.00d86997` calls `fcn.00d8690e` with base `10` and a null end pointer; `fcn.00d869bd` is a tail jump to it. This is the decimal integer conversion used by the tail parser. |
| `ev_1f0876be1b29e6f536a6ed583e4955cd6216eeceb4449d108f7268b1e08b18cb` | `fcn.00402ce0` is a `std::string`-style assign helper: it writes the supplied C string into the object at `ecx`, growing/reusing its buffer through `fcn.00401df0` and `fcn.00d826f0`. |
| `ev_9bac6fe8ef99235601c7f2c02b2bca3094f53d389e3e9d35c925a5170d548260` | `fcn.006fb560` is a quoted-string-aware delimiter token extractor: it takes a source pointer, destination buffer, capacity, delimiter, leading-whitespace flag and newline flag, and returns the source pointer after the delimiter. |
| `ev_d088ca0c2ca0e106935b68abd58b7ba9676be721c79ea9043d70afca13928ca0` | `fcn.00fbe250` copies up to `0x8000` bytes from a caller-provided source into the row buffer and NUL-terminates it; this is the line reader used at the top of the row loop. |

### Later probe ledger

These retained records complete the evidence IDs that were pending from the
same exact `FreeRealms.exe` target. They are listed with the limits of what was
observed; no unnamed function is promoted to a decoded semantic routine.

| Evidence ID | Observation |
|---|---|
| `ev_4325d1a317f7f221674d996af55dc0bfe92aef5afbf9963078dbb02407ee9e15` | `aaa; s 0x0097c090; pdc` completed with no retained stdout. It adds no spawn-transform semantics. |
| `ev_f857dcce73efc58091046d3f87af81e692ab7364f52a2ff59997d3d22e85cec6` | `aaa; s 0x008a9010; pdc` completed with no retained stdout. It adds no zone-transition semantics. |
| `ev_00621355c7152e8abfaacaf3c842939552fdb5d69dfedc5f46e5583b424e295e` | `izz~BindCommandToLua` finds only the `.rdata` string `BindCommandToLua` at VA `0x0180b17c`. |
| `ev_17847849fa85331c4043c4ccd135f462a4abfc140b858838b2214a49f92e9b74` | `aaa; s 0x0180b17c; axt` returns no code/data references. Lua command registration is still unmapped. |
| `ev_15a8fe55382e71c56e5e5fe179134314f0782bb874fc8b85792d62d8d03669f6` | `izz~UserOptions` finds `UserOptions` (`0x0175b364`), `UserOptions.ini` (`0x0175b370`), `SaveUserOptions` (`0x0182c908`), `SetUserOptionsValue` (`0x0182ca30`) and `GetUserOptionsValue` (`0x0182ca44`). |
| `ev_742ceb6bab6676693f217a6a341e426dc773e3969f4f84482e0c5d1703178d28` | `izz~SaveUserOptions` finds the string at VA `0x0182c908`; no call semantics were recovered. |
| `ev_7c6eb6fd49f79444bfb45549f08f9b074c37b098580e39d6f75e1365638d6b72` | `aaa; s 0x0175b370; axt` finds `UserOptions.ini` referenced by `main` at `0x403552` and by `fcn.008ed640` at `0x8ed648`. |
| `ev_71be071eae2c18fc32e3e3c699d4d795c520d00ed0fe3813d93a8ebbbff16b57` | `pd 90 @ 0x008ed640` confirms `fcn.008ed640` defaults an empty argument to `UserOptions.ini` and jumps to `fcn.00402ce0`; the call xref is from `main` at `0x40383d`. The remaining disassembly shown belongs to following functions and is not attributed here. |
| `ev_cbc9c1dcb942c3487421952192a70583b4559850ba5bea9898e97e8edfe43389` | `aaa; s 0x01811604; axt` finds `ProfileName` referenced by `fcn.009fad80` at `0x9fb006`. |
| `ev_0358024728c08fe864b09e577b8c00363334e20537524b69c902156e294007ab` | `pd 70 @ 0x009fafd0` shows `fcn.009fad80` reading `LocationHeading`, `ProfileName`, `ProfileId`, `MiniGameId` and related values through option-getter calls into an analytics/social payload. Field meanings beyond the literal key names are not inferred. |
| `ev_3583df71f9b483d9382fc0829ba886a3a4bc64bd0b6a3f3b282795afc63d85da` | `aaa; s 0x0180b584; axt` finds `PlayerName` at `0x97c2d3` in `fcn.0097c280`, at `0x9fae9f` in `fcn.009fad80`, and at five unnamed addresses (`0xa7c824`, `0xc4e7a8`, `0xc653c8`, `0x126ac78`, `0x126af7d`). |
| `ev_c0d4fd331034ece9324589c20d329eb9fda8f35cbbb548b482411e57330f201a` | `aaa; s 0x01804d68; axt` finds the two already-documented `StartingZone` references in `fcn.0090e8a0` at `0x90e8c5` and `0x90e8d1`. |
| `ev_77514fc62e763b7a158654dc2e062d9fd9b07e2b5879738622facd018674c233` | `pd 120 @ 0x008a9010` confirms a call xref from `fcn.0090e8a0` at `0x90e8de`; the function reads `[esi+0x668]`, allocates/reloads an options object, logs `Failed to reload options manager [prefix=%s].` on failure, stores the result back to `[esi+0x668]`, and reaches a call through `[ecx+0x280]` near the displayed tail. The zone argument transform is still unnamed. |
| `ev_f3767c1059fbe9b17f723a4d49794edc514d0870dd68b24dfc14363857562ae0` | `pd 110 @ 0x0097b960` confirms call xrefs from `fcn.0097bf40` and `fcn.0097c090`; it queries named keys `speaker`, `listener` and `target` through helper calls. This is a token/argument lookup path, not a recovered spawn transform. |
| `ev_9ca348284267d533438458de6584fae5a6ddd81a0550a72cda321c6e364e6bf5` | `pd 80 @ 0x0097c260` shows that this 65-xref wrapper forwards five arguments to `fcn.0097c090` with the caller's argument array pointer appended; it does not rename or decode those arguments. |

### StartingZoneLoad row schema

The embedded `StartingZoneLoad.txt` header explicitly names the columns
`LOAD_ORDER^ASSET_LIST^CALLBACK^IS_BACKGROUND_LOAD`. The disassembly now maps
all four positions to a row object, in header order:

| Header column | Parser | Row offset | Wire type |
|---|---|---|---|
| `LOAD_ORDER` | `fcn.007065d0` | `+0x00` | `int32_t`, decimal in this call site; helper also supports `0x` hex when its flag is set |
| `ASSET_LIST` | `fcn.006fb560` → `fcn.00402ce0` | `+0x08` | NUL-terminated string, `0x400`-byte field buffer |
| `CALLBACK` | `fcn.006fb560` → `fcn.00402ce0` | `+0x18` | NUL-terminated string, `0x400`-byte field buffer |
| `IS_BACKGROUND_LOAD` | `fcn.00726440` → `fcn.00d869bd` → base-10 integer, `setnz` | `+0x04` | one boolean byte |

This confirms the earlier structural observation and corrects it: the first
field is an integer, not the first string. The binary does not expose these
names as C++ symbols; the names come from the resource header. No runtime
effect of `LOAD_ORDER`, `ASSET_LIST`, `CALLBACK` or `IS_BACKGROUND_LOAD` beyond
this parse into the linked row list has been recovered.

The packet catalog was also extended with metadata-backed routes that preserve
the `byte` (login) vs `short` (gateway) wire type and the source direction hint
for each of the 352 classes. Direction is a source-derived hint, not proof of
runtime direction; it is not used to fabricate or discard live packets.

## Still unresolved

1. `0x8a9010`, the `fcn.0097c090` spawn transform and the Lua dispatch targets
   are not decompiled to semantics; only their string xrefs, call sites and
   (where shown) dispatch payloads are verified here. The `0x9cdcd0` row loop and
   its tail parser `fcn.00726440` are now mapped to the resource file's four
   named columns, but what the client does with the resulting row list is still
   unresolved.
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
