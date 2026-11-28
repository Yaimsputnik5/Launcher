# Starting-zone loader and callback semantics

This note completes the read-only REA of `ClientStartingZoneLoader` and the
single configured callback. Both local copies of `FreeRealms.exe` match SHA-256
`26cc1c522a45e71fb57882da515f65bac45c8c8b8c8b7e740c0cea81c52a733351`.

The shipped REA providers timed out and the Ghidra provider rejected the
installed Ghidra `12.2`, so the evidence was produced with Ghidra headless in
`-readOnly -noanalysis` mode using instruction-level dumps. Ghidra emitted
decompiler headers but no C bodies for these targets. No Windows binary was
executed, and no account credential was used or stored.

## Startup chain and object fields

| Address | Evidence |
|---|---|
| `0x00916a52`, `0x00916a94` | push `Resources/` literal from `0x017ed7d8` |
| `0x00916a84` | construct loader with `0x009ce0d0` |
| `0x00916aa1` | call row parser `0x009cdcd0` |
| `0x009cdd3e` | format `%sStartingZoneLoad.txt` from `0x01810194` |
| `0x009ce103` | install vtable `0x018101b0` |
| `0x009ce180` | destructor |

The loader object fields are:

| Offset | Meaning |
|---|---|
| `+0x08` | selected row pointer |
| `+0x0c` | row-list control block |
| `+0x1c` | selector state (`1`, `2`, or `3`) |
| `+0x20` | foreground/state-1 asset queue |
| `+0x2ba80` | background/state-2 asset queue |

## Lua C API callees

| Address | Resolved API | Instruction-level basis |
|---|---|---|
| `0x00e3ab60` | `lua_pushcclosure` | allocates `CClosure`, writes function pointer at `+0x10`, copies upvalues, sets type `6`, increments top |
| `0x00e3aec0` | `lua_setfield`; `lua_setglobal` with `LUA_GLOBALSINDEX` | calls settable helper `0x00e3f6d0`, then decrements top by `0x10` |
| `0x00e3aca0` | `lua_getfield`; `lua_getglobal` with `LUA_GLOBALSINDEX` | calls gettable helper `0x00e3f5e0`, then increments top |
| `0x00e3a820` | `lua_tolstring`; `lua_tostring` when length is `NULL` | string fast path at `tsvalue+0x10`, slower path `0x00e3f390` |
| `0x00e3a580` | `lua_type` | `index2addr`, type tag at `+8`, `-1` for sentinel `0x01853f50` |
| `0x00e3a3a0` | `lua_settop` | adjusts top by `idx * 0x10` |
| `0x00e3a3f0` | `lua_remove` | copies stack slots down, decrements top |
| `0x00e3a550` | `lua_pushvalue` | copies one `TValue` to top |
| `0x00e3aa90` | `lua_pushstring` | interns/copies via `0x00e420b0`, pushes type `4` |
| `0x00e3ac70` | `lua_gettable` | resolves index, calls `0x00e3f5e0` |
| `0x00e3b1a0` | `lua_pcall` | builds protected-call frame, enters `0x00e3e000` |
| `0x00e3a180` | internal `index2addr` | `TValue` stride `0x10`, negative indices from top |

Correction to note 28: `0x00e3aec0` is **not** `lua_getglobal`; it is
`lua_setfield`/`lua_setglobal`. `FUN_00976010` pairs it with
`lua_pushcfunction` to register globals (`lua_register`), starting with `print`
at `0x0180b1b8`. Command records are 8 bytes from `0x0180b1d0`, function
pointers at `+4`. `FUN_009797a0` uses `0x00e3aca0` as `lua_getglobal`.

## `FUN_009797a0` callback path

1. Copy the callback path into a local buffer.
2. Scan for `:` and `.`: `:` sets method flag `1` at `0x0097991f`; `.` sets
   static-field flag `0` at `0x00979926`.
3. `lua_getglobal(L, firstSegment)` at `0x00979884` / `0x00979944`.
4. No separator: require `lua_type == 6` (`LUA_TFUNCTION`).
5. Separator: require `lua_type == 5` (`LUA_TTABLE`), push the method name with
   `lua_pushstring`, read it with `lua_gettable`, require type `6`.
6. `:` calls do `lua_pushvalue(L, -2)` then `lua_remove(L, -3)` to pass the
   table as `self`; `.` calls only `lua_remove(L, -2)`.
7. Arguments are marshalled by `0x00977890`.
8. `lua_pcall(L, nargs, 1, 0)` at `0x009798da`.
9. Errors are read with `lua_tostring(L, -1)` and written to `LuaErrors.log`
   (`0x0180b26c`) via `0x006faad0` at `0x009798fc`.
10. Success updates timing globals through `0x007027f0` and marshals the single
    result through `0x00979590` / `0x00713b70`.

`HUD.StartingZoneLoaded` receives no arguments from C++ because the row supplies
only the path string.

## Row layout and selector states

The embedded file is:

```text
#LOAD_ORDER^ASSET_LIST^CALLBACK^IS_BACKGROUND_LOAD^
1^UiAssets.txt^^0^
10^HighRoadAssets.txt^HUD.StartingZoneLoaded^0^
20^MinigameAssets.txt^^1^
100^FilteredCommonAssets.txt^^1^
```

| Row offset | Field | Evidence |
|---|---|---|
| `+0x00` | `LOAD_ORDER` integer | `0x007065d0` writes parsed numeric token at `0x0070664f` |
| `+0x04` | `IS_BACKGROUND_LOAD` byte | `0x00726440` writes parsed flag at `0x00726499` |
| `+0x08` | `ASSET_LIST` string object | char pointer at `+0x0c` |
| `+0x18` | `CALLBACK` string object | char pointer at `+0x1c`, length at `+0x20` |
| `+0x28` | next row | selector and `0x009cdbe0` |
| `+0x2c` | previous row | `0x009cdbe0` |

`FUN_009cda80` starts at `this+0x10`, follows `row+0x28`, picks the smallest
`LOAD_ORDER` into `this+0x08`, then queues the asset-list name into `+0x20` with
state `1` or `+0x2ba80` with state `2`. No remaining row writes state `3`.
`FUN_009cdf80` checks callback length at `row+0x20`, invokes
`FUN_009797a0` with `row+0x1c`, removes the selected row, clears `this+0x08`,
and reselects. The confirmed order is therefore:

1. `UiAssets.txt`, foreground, no callback.
2. `HighRoadAssets.txt`, foreground, callback `HUD.StartingZoneLoaded`.
3. `MinigameAssets.txt`, background, no callback.
4. `FilteredCommonAssets.txt`, background, no callback.

Only `HighRoadAssets.txt` carries a callback.

## `HUD.StartingZoneLoaded`

`ScriptsBase.bin` parses completely: header `1b4c756a 51 00 04 04 04 08 00`,
216 root protos, 5,057 functions, all 2,897,335 bytes consumed. Standard
`luac5.1` rejects the header because this build uses 32-bit `size_t`.
In `hud.lua` table constructor `main/88`, constant `155` is
`StartingZoneLoaded`, instruction `0152` is `CLOSURE Bx=32`, and instruction
`0153` is `SETTABLE B=411 C=1`; the callback is child proto `main/88/32`, source
lines 1147–1162.

Reconstructed bytecode behavior:

```lua
function HUD.StartingZoneLoaded()
    MinigameTitleBar:ShowForInstance(Ui.GetString("StartingZoneName"))

    if FirstTimeEvent.ShowDownloadCompleteMessage == true then
        FirstTimeEvent.ShowDownloadCompleteMessage = nil
        Ui.SetUserOptionsValue("fteOptions", "downloadComplete", 1)
        Ui.TriggerFirstTimeEvent("FtesDownloadComplete")
    else
        FirstTimeEvent.DownloadCompleteButFirstPanelNOTClosedYet = true
    end

    HUD:EverythingComplete()
end
```

Instruction `0007` is `EQ ... true`; the fallthrough at `0008` is the “show
download complete” branch, while the `JMP` target `0024` is the deferred /
first-panel-not-closed branch. This corrects the earlier working-note wording.

## Native representation added

`ResourceCatalog.swift` now contains `StartingZoneLoadRow` and
`StartingZoneLoadPlan`. The parser skips comments and malformed rows, rejects
unusable numeric/boolean fields instead of inventing values, and returns rows
ordered by `LOAD_ORDER` with stable tie handling. It recognizes the exact
`HUD.StartingZoneLoaded` path as a named callback and exposes foreground and
background rows separately.

This is a **descriptor only**. It does not execute Lua, load the listed asset
files, synthesize first-time-event state, or claim native renderer parity.

## Residual unknowns

- Exact semantics of `0x00977890`, `0x00979590`, `0x00713b70`, `0x00709860`,
  `0x007027f0`, `0x006faad0`, `0x0070b4e0`, and formatter `0x0097c090`.
- No evidence that the callback's marshalled return affects loader success;
  `FUN_009cdf80` invokes it, then removes the row and reselects regardless.
- State `1`/`2` consumers beyond the two queues were not dynamically traced.
- All binary conclusions are instruction-level; Ghidra produced no C bodies.

## Limits

- Foundation-only tests after the change: **261 tests, 1 skipped, 0 failures**.
- No fresh IPA was built; the published asset remains stale.
- No full compiled-client, Lua, or gameplay 1:1 parity is claimed.
- No account credential was provided, requested, captured, or stored.
