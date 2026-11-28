# Exact UI script dispatch codecs

This note adds two `BaseUiPacket` (47) server-to-client replies. Evidence is from
the authoritative Sanctuary source at commit
`f5240b7554f2a80d6b815cb7ead7ffee12499565`; no live session or credential was
used.

## Wire evidence

| C# source | Sub-opcode | Verified body order |
|---|---:|---|
| `src/Sanctuary.Packet/BaseUiPacket.cs` | base | `short 47`, `byte SubOpCode` |
| `BaseUiPacket/ExecuteScriptPacket.cs` | 7 | string `Script`, Int32 `Params.Count`, then each Int32 argument |
| `BaseUiPacket/ExecuteScriptWithStringParamsPacket.cs` | 8 | string `Script`, Int32 `Params.Count`, then each length-prefixed string argument |

The source comment for 47/8 explicitly says it dispatches a named UI method with
string arguments, not Lua source. The Swift decoder therefore records the
selector and arguments only; it does not evaluate, load, or execute any script.

## Swift changes

- Added `GatewayExecuteScript` and `GatewayExecuteScriptStringParams` with exact
  field order, trailing-byte rejection, and a 65,536-argument decoder safety
  bound.
- Consolidated the single `47` switch in `GatewayWorldCodec.decodeAny`. It now
  handles 47/7, 47/8, and the previously decoded 47/14 objective target update;
  unknown 47 sub-opcodes remain raw-preserving mapped packets. This removes a
  duplicate `case 47` that would otherwise shadow 47/14 after adding the new
  codecs.
- Added packet-backed observation state `lastExecuteScript` and
  `lastExecuteScriptStringParams`. No UI method is invoked and no gameplay state
  is inferred from either packet.
- `GatewaySimplePacketTests.testExecuteScriptPacketsDecodeArgumentsWithoutRunningScripts`
  writes independent byte buffers, checks decoded values and observation state,
  and rejects a negative argument count.

## Limits

- This decodes wire replies only. It does not implement the original UI method
  dispatcher, Lua bridge, or any client-side effect.
- No IPA was rebuilt. The published release remains stale relative to this
  source change, and no full 1:1 port claim is made.
- Foundation-only tests after the change: 255 tests, 1 skipped, 0 failures.
- No account credential was provided, requested, captured, or stored.
