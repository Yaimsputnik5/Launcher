# Embedded Lua VM and the gameplay reconstruction boundary

This note records the compiled-client evidence for the shipped Lua integration
and states precisely why the iOS app cannot yet claim Lua/gameplay 1:1 parity.
Target: `ios/Launcher/Resources/ClientAssets/FreeRealms.exe`, SHA-256
`26cc1c522a45e71fb57882da515f65bac45c8c8b8c8b8c7e740c0cea81c52a733351`.

## REA evidence

| Evidence ID | Observation |
|---|---|
| `ev_95fc9bcf0afdd4cac47ee32a549ced32f48d6dfb51a54f5eb500d8f2b0ca1023` | The image embeds a Lua 5.1.4 runtime: `$Lua: Lua 5.1.4 Copyright (C) 1994-2008 Lua.org, PUC-Rio`, `LuaErrors.log`, `BindCommandToLua`, `LuaCall`, `LuaUtil`, `luaopen_%s`, `LUA_CPATH`, `LUA_PATH`, `Lua function expected`, `Lua Quit() called`, `Lua Spawn and automount: id %d`, `Lua Despawn`, `Lua Dismount` and `LuaCallbackBuyButtonHasBeenClicked` / `LuaCallbackNudgeHasBeenShown`. A frame-profiling string includes `LuaGarbageCollect`, showing the VM runs inside the client frame loop. |
| `ev_ce01bb733b21ec544d867e3c4ef7026179984dd2f223ded94b7ddf11387bc440` | No `luaL_*` import names are visible in this stripped image; VM calls are internal or thunked. |
| `ev_b1c6ff087cdd2393508add6b0581140d0ada7c7d4edc88a02e0da1b9898de747` | `ii~lua` reports no Lua import symbols, consistent with a statically linked Lua 5.1.4. |
| `ev_94432c2d71a21e8a809c02f1acc99ce30566d178a3433ff4bbc84ca22bb1ad9c` | RTTI contains `SoeUtil::List<LuaCallDetails>`, so Lua callbacks are represented as typed data in the client. |
| `ev_128ee6a999e37aa6e49704be3b499457b5a7df586c471b9f2ce36a8fd8dec134`, `ev_00621355c7152e8abfaacaf3c842939552fdb5d69dfedc5f46e5583b424e295e` | `LuaCall` (`0x1813f88`) and `BindCommandToLua` (`0x180b17c`) are present. The two `LuaCall` xrefs resolved so far are field-name getters on `WhatsNewDataSource.virtual_4` (`0xa3e1f0`) and `NudgeDataSource.virtual_4` (`0xa414fc`), not a generic dispatcher. |
| `ev_17847849fa85331c4043c4ccd135f462a4abfc140b858838b2214a49f92e9b74`, `ev_c43f2f6f850e0c27bbae6eeae15a1a8e58c3dbc4f8d265d2d5168a9ecf95b1c6` | `aaa; axt` finds no direct code xref to `BindCommandToLua` at either virtual or file address; registration is likely data-driven through config or script metadata. No registration mechanism is claimed. |
| `ev_130369091d17e3a2fa36b1d431d38c2f365e66976314b70c64d280b796ccf72d` | `LuaErrors.log` is pushed by `fcn.00976e90` (`BaseClient.virtual_56` caller), an unnamed function at `0x976e19`, and `fcn.009797a0`; the latter has 759 xrefs and parses a colon/dot-delimited command string into a fixed buffer. This is evidence of a real client-side Lua command/error path. |
| `ev_1edb009ff6c622b28b3e423899c92f661b562defb18a212773bf18771b15ab52` | `fcn.00976e90` calls `0xe396a0`, `0xe3b1a0` and `0xe3a820` around the Lua error-log write, then reads client config through `0x769710`. The exact VM calls remain unnamed. |
| `ev_e09502760e045b9ab1591f31dbf363c49f4fe136d4e1ac950daf5ea5fbee568f` | `fcn.009797a0` copies a caller string into a local buffer and splits it on `':'` and `'.'`, consistent with a Lua command namespace/function path. The command table itself is not reconstructed. |
| `ev_21d691e641f31a357944b76aafdf5a936d5b871020abd3db9fe8da7bb7a5c5bd` | `Lua Quit() called` has one xref at `0xc17457`, proving at least one exported Lua command reached native client code. |
| `ev_a7e4597960aedb3ef24e054be7646e9a085fee93440dd9e0c6ef8d2f1c7f92cb`, `ev_4588f720c8e8ee45a3244eedf141edb37a5cde46d403de7d20e8f802b67c0081` | Disassembly of the two field-name getters confirms exact returned strings. `WhatsNewDataSource.virtual_4` returns `LuaCall`, `StringParam1`, `Param1`, `Param2`, `Param3`, `StringParam2`; `NudgeDataSource.virtual_4` returns those plus `TrackingType1`, `TrackingType1Param1`, `TrackingType2`, `TrackingType2Param1`. These are server-provided data fields, not Lua VM entry points. |

## iOS position

The native app has no Lua interpreter and no decoded Lua script payload. The
iOS engine implements only the Foundation-only simulation, packet presentation
and Metal rendering paths already covered by tests. It must not claim that
`LuaCall`, `BindCommandToLua`, card/game rules, zone scripts or callback
semantics are reproduced.

A new test in `PacketCatalogTests` asserts that raw mapped/unknown packets only
update diagnostic counts in `GatewayWorldObservation` and never fabricate
players, zone, time or chat. This preserves the packet-only rule for remote
sessions while the Lua and gameplay gaps remain open.

## What would close this gap

1. Recover the Lua 5.1.4 function table / `luaopen_*` registrations and the
   `BindCommandToLua` data-driven command names with exact call sites.
2. Decode the embedded Lua scripts from the packaged client assets (not merely
   string references in `FreeRealms.exe`) and map their state transitions.
3. Reproduce those transitions in a native interpreter or a source-backed
   equivalent, with opcode/snapshot tests against live capture.
4. Verify on a real iOS device in both offline and remote sessions.

Until those steps are complete, the app is a source-backed native port with
partial compiled-client verification, not a 1:1 gameplay port.
