# Lua command registration table and name-template formatter

This note resolves two items that note 15 left open. It corrects the earlier
label for `fcn.0097c090` and recovers the data-driven Lua command registration
that explains why `BindCommandToLua` has no direct code xref. It remains
**partial compiled-client verification**, not a 1:1 gameplay reconstruction.

All observations use `ios/Launcher/Resources/ClientAssets/FreeRealms.exe`,
SHA-256 `26cc1c522a45e71fb57882da515f65bac45c8c8b8c8b7e740c0cea81c52a733351`.
The Ghidra function/edge counts come from the already-exported `functions.tsv`
and `call-edges.tsv` whose digests are recorded in note 14.

## `fcn.0097c090` formats localized names, not spawn objects

Note 15 called `fcn.0097c090` a "spawn builder" and called its argument a
"spawn argument". The full disassembly does not support either label:

| Evidence | Observation |
|---|---|
| `ev_f7a4e4d16ddfe3002bd9f75566499fd642de327cc2a85e67edca8632c067a0c2` | `pd 160 @ 0x0097c090`: the function constructs a temporary at `[this+0x20]`, checks a virtual predicate at vtable slot `0xcc`, optionally calls slot `0xd0` with two forwarded arguments, otherwise iterates an argument-count/array pair through `0x97b960` and calls `0x97bca0` with two arguments. It returns the resulting boolean and uses `ret 0x10`, i.e. four stack arguments plus `this`. No position, rotation, geometry or entity-creation call appears. |
| `ev_5749133d3eece7a3b5cf2aadc9141ec32a3c37ed9cd405a74c9a820f7536025a` | `pd 160 @ 0x0097b960`: each array element is inspected by named keys `speaker`, `listener`, `npc`, `target` and `player`; the routine also formats `%s_class` and `Global.Text.%d`. This is token lookup/substitution for text, not transform math. |
| `ev_ae07e26f1f5447ea427c59623b5d738105f35d10c0fe32153f79b65e278bf820` | `pd 360 @ 0x0097c280`: the `PlayerName` getter caches `PlayerName` in global `0x1be5240`, constructs the literal `"player"`, reads entity fields at offsets `0x48`, `0x7c`, `0x80` and `0x84`, and calls `0x97c260`. The following `0x97c390` region uses `PlayerTitleFormatAlias`, `PlayerTitleFormatPrefix`, `PlayerTitleFormatSuffix`, `firstName`, `lastName`, `fullName` and `Global.Text.%d` before calling the same formatter. |
| `ev_a9ea2673f6eb015573dd5e64a9bc9f7c3a1847e2010f14969f891008886a236e` | `pd 90 @ 0x0097be40` and `pd 90 @ 0x0097bf40` show the sibling text paths: vtable slot `0xcc`/`0xd0` dispatch, `0x97b960` token walking, `0x97bca0` expansion, and the literal `<STRING %d NOT FOUND>` fallback when expansion fails. |

Ghidra records `fcn.0097c090` as 212 bytes with exactly two callers,
`0x0097c1e0` and `0x0097c260`, and five callees: `0x0097b960`, `0x0097bca0`,
`0x00fc4610`, `0x00fc45f0` and `0x00e52260`. `0x0097c260` has 65 callers and
`0x0097c280` has 24. The evidence therefore supports a widely reused
localized display-name/template formatter. It does not support the earlier
"spawn object" wording, and no transform algorithm was recovered here.

## Lua commands are registered from a null-terminated data table

The string `BindCommandToLua` is at `0x0180b17c`
(`ev_f3f505835ac90536b94113a8c2fbd5305e91c14b7270739ed5c76a3dd791bc46`).
A raw little-endian pointer search finds it once, inside an 8-byte-record
table at `0x0180b1d0`. Decoding that table with the PE section map gives:

| Index | Name pointer / name | Handler |
|---:|---|---|
| 0 | `0x0180b1b8` / `print` | `0x977e60` |
| 1 | `0x0180b1b0` / `clear` | `0x975f00` |
| 2 | `0x0180b1a0` / `createNewModule` | `0x975f80` |
| 3 | `0x0180b190` / `createNewWindow` | `0x9780e0` |
| 4 | `0x0180b17c` / `BindCommandToLua` | `0x978f80` |
| 5 | `0x0180b16c` / `setIsModalUp` | `0x975dc0` |
| 6 | `0x0180b15c` / `getIsModalUp` | `0x975bb0` |
| 7 | `0x0180b14c` / `SetModalResult` | `0x975d10` |
| 8 | `0x0180b13c` / `getModalResult` | `0x975c60` |
| 9 | `0x0180b134` / `guiEdit` | `0x975af0` |
| 10 | `0x0180b128` / `guiListen` | `0x975a50` |
| 11 | `0x0180b118` / `guiInitModule` | `0x9759a0` |
| 12 | `0x0180b10c` / `guiReset` | `0x975e70` |
| 13 | `0x0180b100` / `debugBreak` | `0x975ef0` |

The next 8-byte record at `0x0180b240` is all zeroes and terminates the table
(`ev_a80cb313f3f6dc98020b277d69aae461670e5f4ebefe3e83bf32df70ff6f85ba`).

`FUN_00976010` at `0x976010` registers every record:

| Evidence | Observation |
|---|---|
| `ev_f39215b9ccf9078ce1084a7d55f33172245841729730cfa74f40` | `pd 120 @ 0x00976000` shows the loop loading the first handler from `[0x180b1d4]`, advancing with `esi = ebx*8`, and stopping when `[esi+0x180b1d4]` is zero. Each iteration calls `0xe3ab60(context, handler, 0)` and then `0xe3aec0(context, -10000, name)`, where `name = [esi+0x180b1d0]`. The argument shapes are consistent with Lua C API `lua_pushcclosure` and `lua_setfield(LUA_REGISTRYINDEX, ...)`, but the Lua API symbols themselves are not named in this image. |
| `ev_f39215b9ccf9078ce1084a7d55f33172245841729730cfa74f40` | `0x976060` passes `[ecx+0x94]` into `0x976010`; `0x976070` calls many further binding-registration helpers with the same `[esi+0x94]`. Ghidra gives both `0x976010` and `0x976070` one caller, `0x976cb0`. |

This data-driven table explains the note 15 observation that `aaa` found no
direct code xref to the `BindCommandToLua` string: the string is reached as a
table pointer, not by an immediate in code.

`FUN_00978f80` is the `BindCommandToLua` handler:

| Evidence | Observation |
|---|---|
| `ev_4ac2ff87c48d34098ab47ccc6a32c79a494572149b7c2d143a02677bd9e86ec8` | `pd 80 @ 0x00978f80` shows it requires exactly two Lua arguments (`0xe3a390` result equals `2`), requires both to pass the `0xe3a630` predicate, creates two references through `0xe39c30`, and passes them to `0x9787a0`. Ghidra records zero direct callers for `0x978f80`, matching its table-only registration. |

## Boundaries

- No credential value was provided, requested, captured or stored.
- The command table proves registration of named C handlers, not the behavior
  of the Lua scripts those handlers later invoke.
- `LuaCall` remains a field-name getter on `WhatsNewDataSource` and
  `NudgeDataSource` (`0xa3e1f0`, `0xa414fc`); the separate
  `LuaCall.ButtonStringId`/`BodyStringId`/`TitleStringId` region was seen as
  field-name getters, not a generic dispatcher
  (`ev_a80cb313f3f6dc98020b277d69aae461670e5f4ebefe3e83bf32df70ff6f85ba`).
- `fcn.0097c090` is corrected to a name/template formatter; this note does not
  claim a recovered spawn transform.
- No full 1:1 claim is made. Nested packet codecs, live-session parity, engine
  material/tile fidelity and the remaining compiled-client semantics stay open
  as recorded in notes 14–19.
