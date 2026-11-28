# Compiled client inventory and the remaining 1:1 boundary

This note continues the request to reconstruct the shipped client with REA. It
adds a complete structural inventory of the native client and records exactly
what that inventory does **not** prove. It does not claim the iOS app is a
finished 1:1 port.

## Target identity

| Property | Value |
|---|---|
| File | `ios/Launcher/Resources/ClientAssets/FreeRealms.exe` (build-time staged payload) |
| SHA-256 | `26cc1c522a45e71fb57882da515f65bac45c8c8b8c7e740c0cea81c52a733351` |
| Size | 25,067,520 bytes |
| Container | PE32 / `pei-i386`, image base `0x00400000` |
| PDB path embedded in the image | `C:\\Dev\\FreeRealms\\Live\\Code\\Output\\Win32\\Release\\PlayClient\\FreeRealms.pdb` |

The PDB itself is not present; symbol names in the Ghidra database come from
imports, exception/thunk generation and the binary's RTTI, not from that PDB.

## REA observations used here

`open_binary` bound this target to the Hopper provider (launcher SHA-256
`0294ced141cc373468ee22d8343e7dac41980cb05a937994ca81c9f09afe7ded`) with the
derived loader `-l WinPE --intel-32`, but Hopper never reached bridge readiness
through MCP, including after `REA_HOPPER_STARTUP_TIMEOUT_MS=600000`. The
extended CLI attempt was terminated after the Hopper child exited while the
adapter was still waiting. `rea doctor --provider hopper --json` nevertheless
reports the Hopper launcher, version and private-display runtime as healthy.
No Hopper-derived procedure list is claimed here.

REA's non-Hopper `inspect_with_objdump` path succeeded on the exact artifact:

| REA operation | Evidence ID | Result |
|---|---|---|
| `inspect_with_objdump file_headers` | `ev_2402cedea0a344191caae70074770fa6b4c25c92632dea64527c87ab4437a794` | `pei-i386`, `start address 0x00d83687` |
| `inspect_with_objdump symbols` | `ev_e5b94ea328a70c2aefb206cf9316f1501e258576f6ae4f99b533c2053c47a3d0` | no COFF symbol table |
| `inspect_with_objdump relocations` | `ev_6a3e98879aa2da3a84e72689c61b71bdb016e9bc162fe10194ef462e708466a3` | no relocation rows returned by GNU objdump for this PE |
| `execute-rizin-command pd 8 @ 0xd83687` | `ev_4a0ef83ec51842a5719f090c8020aec307ac84898599267b7831a71608d79886` | `call 0xd95820` followed by `jmp 0xd834a7` |

These are independent confirmations of the entry address already observed in
`05-compiled-binaries-and-rea.md`. Rizin's tail jump agrees with the Ghidra
decompilation's second call: the decompiler renders the tail transfer as a
call followed by `return`.

## Full Ghidra function and call-graph export

A read-only Ghidra 12.2 headless post-script exported every analyzed
`Function` and every known call edge from the completed analysis database
(previously recorded as the 768-second run with 153,421 functions). Script:
`/tmp/opencode/rea-build/ghidra-scripts/ExportFullFunctionInventory.java`.
Project: `/tmp/opencode/rea-build/ghidra-freerealms-proj7/FreeRealms`.
Log: `/tmp/opencode/rea-build/ghidra-function-inventory.log`.

The export ran with `-noanalysis -readonly`, so no analysis result was changed:

| Property | Observation |
|---|---:|
| Functions | 153,421 |
| Call edges | 273,001 |
| Functions with non-generated names | 54,052 |
| Thunks | 876 |
| External functions inside the program | 0 |
| `entry @ 0x00d83687` | 10 bytes, 2 callees, 0 callers |

The entry's exported edges are exactly:

```text
00d83687  00d95820
00d83687  00d834a7
```

The inventory resolves those addresses to `___security_init_cookie` and
`___tmainCRTStartup`, agreeing with the earlier decompilation of the CRT entry
path. The application body is reached from `___tmainCRTStartup`; the export
shows it has 23 callees.

Exported artifacts (kept outside the app bundle and outside the IPA):

| File | SHA-256 |
|---|---|
| `ghidra-exports/functions.tsv` | `dea4e7469c6342125e549178c54d11b294fb2befec460bfc0e9f28b84f6a5566` |
| `ghidra-exports/functions.tsv.gz` | `701bf93c777f5c977dce699cca8a103b4ce4158158cb163fb24054e434c209f7` |
| `ghidra-exports/call-edges.tsv` | `4cb56e014b786762981b266b8d105c4134f97c2a57dab0049854681a35c5ae51` |
| `ghidra-exports/call-edges.tsv.gz` | `990905afd63fd36f2317fb05620ced6f9e9005e4a7ad348908fe0f2f1927eece` |

The TSV columns are `address`, `name`, `size`, `isThunk`, `isExternal`,
`calleeCount`, `callerCount`; the edge file is `caller<TAB>callee`. This is a
complete address/name/topology inventory, **not** 153,421 decompiled function
bodies. Most names remain generated (`FUN_00403340`, `FUN_0090e8a0`,
`FUN_009fad80`, `FUN_00cbfd20`), including the functions previously observed
reading `StartingZone`, `ProfileName`, `PlayerName`, `Coins`, `StationCash`,
`SessionId` and `Server`.

## RTTI class and packet vocabulary

A targeted `strings -a -n 6` pass over the same SHA-256, filtered to MSVC RTTI
names beginning `.?AV` or `.?A7`, produced 4,918 unique class names. Extract:
`/tmp/opencode/rea-build/freerealms-rtti.txt`. The largest namespaces are
`SoeUtil` (405 suffix occurrences), `DeepParticle` (17), `Uram` (16),
`Requirements` (14), `UdpLibrary` (13), `UI` (11), `std` (11),
`GameCommerce` (11), `GraphicsDriver` (10), `GameUtil` (7) and `Crypto` (6).

Examples relevant to the iOS port include `PlayClient`, `BaseClient`,
`ClientGatewayHandler`, `ClientLoginHandler`, `UdpConnection`,
`GroupLogicalPacket`, `FixedLogicalPacket`, `ClientStartingZoneLoader`,
`Tile`/`GameRuntimeTerrain`, `ClientLuaParam`, `LuaCallDetails` and the
native packet classes. There are 198 non-template class names ending in
`Packet`; 69 of them match a `Sanctuary.Packet/*.cs` file name exactly, for
example `FriendListPacket`, `QuestObjectiveUpdatePacket`,
`PlayerUpdatePacketSetSynchronizedAnimations`, `RewardBundlePacket` and
`CommandPacketInteractionList`. That overlap confirms a shared packet
vocabulary, but it does not map opcodes or field layouts by itself.

## What remains before a 1:1 claim can be made

1. Decompile and verify the bodies of the still-unnamed functions that consume
   launch arguments, settings, zone loading, Lua dispatch and packet handlers.
   The current evidence proves addresses, strings, xrefs and call topology,
   not semantics.
2. Map every native packet RTTI class and opcode to a Sanctuary packet and then
   to a Swift codec; the current app implements only the bootstrap,
   lifecycle, movement, chat, time, jump and teleport subset needed by the
   verified sessions.
3. Reconstruct the Lua/gameplay script behavior and server-driven content from
   the shipped asset packs; no client script execution is implemented on iOS.
4. Close the engine fidelity gaps recorded in
   `13-engine-material-and-tile-fidelity.md` (environment-ID → GZNE material
   mapping, unparsed material-table bytes, absent `AssetsW_*.pack`,
   `.rcc`/Granny/FXO/DXT coverage).
5. Verify a live remote session end-to-end against these decoded structures on
   an iOS device; device-side parity is still unverified.
6. Keep the explicit iOS substitutions in `12-launcher-divergences.md`: no
   Discord SDK, no Velopack, no process execution, and bounded logging.

Until those items are closed, the correct description is "source-backed native
port with partial compiled-client verification", not "full 1:1 port".
