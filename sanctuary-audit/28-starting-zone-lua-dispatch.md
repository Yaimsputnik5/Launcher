# Starting-zone dispatch reaches a Lua-facing loader

This note resolves two callees left unnamed in note 27. It remains static REA
evidence from the shipped `FreeRealms.exe` and does not claim that the iOS port
executes this pipeline or that Lua/gameplay semantics were reproduced.

## `0x9797a0` is Lua-facing

`ClientStartingZoneLoader` slot 0 (`0x009cdf80`) reads `count` from `[row+0x20]`
and the record array from `[row+0x1c]`, then calls `0x9797a0` once per count
with that array and an out parameter (`ev_55cb44ca...`, note 27).

| Observation | Evidence |
|---|---|
| `0x9797a0` disassembly pushes literal `LuaErrors.log` at `0x0180b26c` before `0x6faad0` and a virtual write call. | `ev_c6b5f7d1ce5cd56c7d242c4f548bd10e28daa8a9d85fc5e8056bda6a6f3ec548` (`pd 260 @ 0x009797a0`) |
| Raw bytes at `0x0180b26c` are `LuaErrors.log`, followed by `{function}`, `{table}`, `nil`, and `Error.%`. | `ev_cca7bc399507b556874027b6686aa7c71f0f26b3ab4ee907e007b68032cb11f8` (`px 64 @ 0x0180b260`) |
| `0x9797a0` iterates 160-byte (`0xa0`) records from the supplied array, calling `0x977890` once per record, then calls a Lua-like registry/table helper. | `ev_c6b5f7d1...` |
| `0x977890` switches on a type tag and pushes strings, doubles, booleans, nil, and recursively built tables through the same `0xe3a*`/`0xe3b*` call family. | `ev_f05fc7bad2bffa4fe0190ba97582a902a7270f842deb0a0fe77da424570e6052` (`pd 120 @ 0x00977890`) |
| Ghidra records 20 callees for `0x009797a0` and 20 callees for `0x00977890`, including the `0xe3a*` family and `0x00977890` itself. | `/tmp/opencode/rea-build/ghidra-exports/call-edges.tsv` and `functions.tsv` |

The combination of a dedicated `LuaErrors.log`, the `{function}`/`{table}`/`nil`
literals, the type-tag switch, and the repeated `0xa0`-stride records supports
calling `0x9797a0` a **Lua-facing loader/registrar**. The individual addresses
`0xe3a820`, `0xe3aa90`, `0xe3b1a0`, etc. are **not** assigned exact Lua C API
names here; that would require separate verification.

## Supporting slot-0 callees

| Callee | Observation | Evidence |
|---|---|---|
| `0x0070b4e0` | Walks a vector of 160-byte elements, calls a virtual destructor on elements whose tag allows it, zeros each element, and sets the count to zero. | `ev_b40d06d850b8bffbb35d177f8884025922342a70cea922c42f20dcc00d82af9e` (`pd 40 @ 0x0070b4e0`) |
| `0x00401c00` | Sized deallocation path through the allocator singleton and a virtual delete slot. | `ev_b4f41b9d81d489315f85b55c4bbf7b6e06a75183aeeea3fc1d73829cc62b595d` (`pd 20 @ 0x00401c00`) |
| `0x00726440` | Parses one `^`-delimited token into a byte (boolean) at its destination. In the row reader the destination is `row+4`. | `ev_d6a5b84549bcf0368060d0cc80d96fc7e7df46a5a2008bffe81a7e118e4e25be` (`pd 50 @ 0x00726440`) and `ev_c17233acc809562d6bffbd233859a546c97a34568db29a100bd45fe49cca2472` (`pd 120 @ 0x009cdd20`) |

The selector `0x009cda80` branches on byte `row+4` to choose between the
`[loader+0x20]` and `[loader+0x2ba80]` subobjects and writes state `1`, `2`, or
`3` to `[loader+0x1c]` (`ev_730f252b...`, note 27). Because the embedded header
is `LOAD_ORDER^ASSET_LIST^CALLBACK^IS_BACKGROUND_LOAD`, the parsed boolean at
`row+4` is **consistent with** the `IS_BACKGROUND_LOAD` column. This is an
inference from field order and use, not a recovered symbol or a verified
mapping of all four columns.

## Limits

- Static analysis only; no Windows executable was executed and no runtime
  Lua state was observed.
- `0x9797a0` is widely called (753 discovered callers), so its behavior is
  likely general-purpose. The slot-0 call site is what ties it to this loader;
  the tie does not make the loader-specific semantics unique.
- No claim is made that `CALLBACK` is executed as a Lua chunk, that the typed
  records are asset names, or that the iOS app ports this behavior.
- No source or test changed; the last Foundation-only run remained 251 tests,
  1 skipped, 0 failures.
- No account credential was provided, requested, captured, or stored.
