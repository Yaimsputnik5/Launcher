# `ClientStartingZoneLoader` construction, parsing, and dispatch sites

This note extends note 24 with directly observed call sites and virtual-table
slots for `ClientStartingZoneLoader` in the shipped `FreeRealms.exe`
(SHA-256 `26cc1c522a45e71fb57882da515f65bac45c8c8b8c8b7e740c0cea81c52a733351`).
It is static REA evidence only: no target execution, no runtime observation, and
no claim that the iOS port reproduces this startup pipeline. Note 36 later
confirms the row-field mapping, Lua C API callees, and callback semantics.

## Identity and vtables

| Observation | Evidence |
|---|---|
| Type descriptor at `0x01b48428`; name at `0x01b48430` is `.?AVClientStartingZoneLoader@@`. | `ev_649a55efb97132bfd702f9b024ad7b5bf7b7d4351effce9234af8177f913840b` (`px 64 @ 0x01b48420`) |
| Data at `0x018101ac` is `0x019383a8` (the COL pointer); derived vtable slots at `0x018101b0`/`0x018101b4` are `0x009cdf80`/`0x009cd7f0`. | `ev_faf22545ec457c405696d8985eaaca5f276664a475405c4018462c887c8ddb27` (`px 96 @ 0x01810180`) |
| Base-like vtable area beginning at `0x01810184` contains `0x009ce090`, `0x009cd820`, `0x009cd8e0`, `0x009cd920`. | Same `px` evidence above |
| Class-hierarchy/RTTI-linked data is present at `0x01938350`–`0x019383a8`. | `ev_97d40e6b2711f863300a992f3ac1cd2fb10e69f5eabf01e4d389e05ddc02915c` (`px 96 @ 0x01938350`) |

The exact slot count reported by Ghidra is unchanged from note 24: `009cdf80`
has 190 bytes and five callees; `009cd7f0` has 3 bytes and no callees
(`/tmp/opencode/rea-build/ghidra-exports/functions.tsv`).

## Construction call site

At `0x00916a64` startup allocates a `0x574e0`-byte object, stores the pointer,
and at `0x00916a81` calls the constructor `0x009ce0d0` with the enclosing
startup object as its explicit argument.

| Observation | Evidence |
|---|---|
| Constructor `0x009ce0d0` writes derived vtable `0x018101b0` to `[this]`, stores the argument at `[this+4]`, writes `0x01810184` to `[this+0xc]`, zeroes several fields, and initializes subobjects at `[this+0x20]` and `[this+0x2ba80]`. | `ev_bc1e4e799acc165f5834a2a4cd7b8057740e82414e772e5ce5535a345d81d80d` (`pd 180 @ 0x009ce0d0`) |
| Call site `0x00916a4b`–`0x00916aa1` allocates the object, constructs it, then immediately calls the row reader with `ecx` set to that object. | `ev_c723b869c350d9b9ec4d62dc213d5ccb9851dda379c235abfa944fbaa5600b2b` (`pd 80 @ 0x00916a40`) and `ev_52bc169b4ba5213f21675371074512a993f8a72c3eb9348c354c8d47f1c03b3b` (`pd 70 @ 0x00916a90`) |
| The explicit argument pushed before the row reader is `0x017ed7d8`; raw bytes there are ASCII `Resources/`. | `ev_ac97bf65016e3af02965397e58ad53f9e92e294720c6ed707bed47eb8b239bb5` (`px 64 @ 0x017ed7d0`) |

`ps` output for these literals was mojibake because Rizin applied a
non-ASCII decoding; the conclusion uses the raw `px` bytes, not that string
render. The call sequence is `allocate(0x574e0)` → `ClientStartingZoneLoader`
constructor → row reader with literal `Resources/`.

## Row reader

The single discovered caller is the startup site above. Ghidra records
`009162f0 → 009cdcd0` and a 521-byte function body
(`/tmp/opencode/rea-build/ghidra-exports/call-edges.tsv` and `functions.tsv`).

| Observation | Evidence |
|---|---|
| `0x009cdd3e` pushes `0x01810194`, whose raw bytes are `%sStartingZoneLoad.txt`, then calls `0x402fd0` with the supplied prefix. | `ev_6ed7fec713cb94fa6b411518775e06e41dd5595865fbb2c2cfb1152b90064300` (`pd 120 @ 0x009cdcd0`) and `ev_ac43e01ee053166d0d87b697f847f981bb9d3235216e6854f8c4d056ec59d7bc` (`ps @ 0x01810194`, corroborated by `ev_faf225...` raw bytes) |
| A delimiter object is constructed with `0x5e` (`^`) at `0x009cdd50`. | `ev_6ed7fec7...` |
| Lines whose first byte is `0x23` (`#`) are skipped at `0x009cdd9c`. | `ev_c17233acc809562d6bffbd233859a546c97a34568db29a100bd45fe49cca2472` (`pd 120 @ 0x009cdd20`) |
| Before insertion, the reader scans to the terminator and requires at least three `^` bytes (`cmp eax, 3; jb skip`). | `ev_c17233ac...` |
| Surviving lines are split with `0x7065d0`, `0x6fb560`, `0x402ce0`, and `0x726440`, and the resulting node is linked into the loader list. | `ev_c17233ac...` |
| Helper `0x009cdbe0` calls virtual slot `+8` on the subobject at `[loader+0xc]`, then links the returned node via offsets `0x28`/`0x2c`. | `ev_622e9e5a6d5dc832cb03a9dd8358659f3e566df3e218bb45104b5b2be75f2019` (`pd 80 @ 0x009cdbe0`) |

This establishes that the shipped client reads a `StartingZoneLoad.txt` path
formed from the literal prefix `Resources/`, uses `^` as the row delimiter,
skips `#` comment rows, and enforces a minimum of three delimiters before
building a linked-list entry. It does **not** establish the semantic mapping of
each parsed field to the embedded header's column names, nor that a callback
string is invoked as Lua or C++ code.

## Destruction and derived virtual slots

| Slot / helper | Observation | Evidence |
|---|---|---|
| Destructor `0x009ce180` | Restores derived vtable, clears both subobjects with `0xae3740`, walks the linked list through `0x9cdee0`, then writes base-like vtable `0x01810184`. | `ev_d261d873100bc63cbc08a026f36caee1d6fb0b238f3b2017779481623035633f` (`pd 140 @ 0x009ce180`) |
| Slot 0 `0x009cdf80` | Reads selected node from `[this+8]`, loops `count = [node+0x20]` times through `0x9797a0`/`0x70b4e0`/`0x401c00`, then deletes the node with `0x9cdee0` and selects the next via `0x9cda80`. | `ev_55cb44ca075f7754be4c66db724d7c443d4fface7d64acf930e1d7afd4b4169a` (`pd 70 @ 0x009cdf80`) |
| Slot 1 `0x009cd7f0` | Exactly `ret 0x10`; a no-op override with 16 bytes of stack cleanup. | `ev_03bd10b7be0749cac738071170c4c83f962a980d0944cc0fe13361ad2a814aa2` (`pd 20 @ 0x009cd7f0`) |
| Selector `0x009cda80` | Scans the list at `[this+0x10]`, compares dwords at node offset `0`, chooses the smallest candidate, then branches on byte `[node+4]` into either the `[this+0x20]` or `[this+0x2ba80]` subobject and writes state `1`, `2`, or `3` to `[this+0x1c]`. | `ev_730f252bdcba7a5295ee89a93886ebcf4e53c67e1a9494bd7de2351a8141dc44` (`pd 70 @ 0x009cda80`) |

Ghidra call edges corroborate these links: `009ce180 → 009cdee0`,
`009cdf80 → {009cdee0, 009797a0, 0070b4e0, 00401c00, 009cda80}`, and
`009cda80 → {00ae3750, 00ae79b0, 00769710}`. The callees `0x9797a0`,
`0x70b4e0`, and `0x726440` are **not** named here; their roles require further
verification.

## Limits

- Every finding is static disassembly/data inspection of the shipped artifact.
  No Windows executable was run on this host and no iOS runtime was involved.
- Rizin emitted `bin_file_strings: search interval size ... exceeds max region
  size` warnings during these reads; they do not alter the `pd`/`px` bytes cited
  above, but they limit confidence in any broad string-search conclusion.
- `0x009cd7f0` is a no-op instruction sequence, not a call to a loader routine.
- No account credential was provided, requested, captured, or stored.
- This note does not change Swift sources, does not claim full 1:1 port status,
  and does not claim live-session, Lua/gameplay, or engine-fidelity parity.
