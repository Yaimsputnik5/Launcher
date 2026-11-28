# `ClientStartingZoneLoader` RTTI and virtual table

This note narrows the compiled-client gap left by note 19. It verifies the
class hierarchy and the exact virtual table of `ClientStartingZoneLoader` from
MSVC RTTI records. It does **not** recover C++ method names or a runtime call
site, and it does not claim the parsed `StartingZoneLoad.txt` rows have a
recovered consumer.

All observations use the exact artifact
`ios/Launcher/Resources/ClientAssets/FreeRealms.exe`, SHA-256
`26cc1c522a45e71fb57882da515f65bac45c8c8b8c7e740c0cea81c52a733351`. The
Ghidra call-graph digests are those recorded in note 14.

## RTTI identity

| Evidence | Observation |
|---|---|
| `ev_d27a89a0148c82ef9ba4b74a395b7e6d91ecb463b218724e6108476b0653db6a` | `px 96 @ 0x01b48428` shows the MSVC type descriptor: pVFTable at `0x01844cec`, spare `0`, and name `.?AVClientStartingZoneLoader@@`. |
| `ev_f1e3bc821c6afa84b1d900baaaf6327ed2d8ea4f4a52095d752d5217cc223e20` | `px 96 @ 0x019383a0` shows a 20-byte complete-object-locator shape at `0x019383a8`: pTypeDescriptor `0x01b48428`, pClassDescriptor `0x019383bc`. |
| `ev_f1e3bc821c6afa84b1d900baaaf6327ed2d8ea4f4a52095d752d5217cc223e20` | The class hierarchy descriptor at `0x019383bc` has `numBaseClasses = 2`; its base array at `0x019383cc` contains `0x019383d8` (the class itself) and `0x01934e60`. |
| `ev_4cf6f5c6e787e347766656278e9d8f5f7eb48f5b47ec3b66b950836f6f20f871` | `px 96 @ 0x019383cc` confirms the self-descriptor has attributes `0x40000000` and points back to class descriptor `0x019383bc`. |
| `ev_ec9020ab4fcfb30af60db7248b07b92ccfe5ab430e8a7398d1c4016f0c248e6b` | The second base descriptor at `0x01934e60` points to type descriptor `0x01b45448`. |
| `ev_8832232712e1e840248ffa89da25f5f97d96ebf850c8b4b26711e7fd42f7f173` | `px 96 @ 0x01b45448` reads that type descriptor as `.?AVStatusHandler@DelayedAssetLoader@@`. |

The verified inheritance is therefore
`ClientStartingZoneLoader : StatusHandler<DelayedAssetLoader>`. Note 19 had
already established that the parser is called with `Resources/` from broad
startup code; this note adds only the class identity and virtual layout.

## Exact virtual table

| Evidence | Observation |
|---|---|
| `ev_3f58103089e20729ea1fd9d2b497707b65b6ae9e72a788d5eb8d8bc8a558c1c7` | `px 96 @ 0x01810190` shows the RTTI locator pointer `0x019383a8` at `0x018101ac`, immediately before the virtual table at `0x018101b0`. |
| `ev_3f58103089e20729ea1fd9d2b497707b65b6ae9e72a788d5eb8d8bc8a558c1c7` | The table has exactly two function pointers: slot 0 `0x009cdf80`, slot 1 `0x009cd7f0`. The following dwords decode as IEEE-754 float constants, not more virtual functions. |
| `ev_5ab820f279889ad2293f2da05b862fee370c00184524ecb294bb90d600b99784` | `pd 12 @ 0x009cd7f0` is only `ret 0x10` followed by padding; slot 1 is a no-op with four stack arguments. |
| `ev_998026191f96349c567e6e091375988253c9abccda2233926a3ab72db6f98e77` | `pd 80 @ 0x009cdf80` shows a non-empty method with `ret 0x08`. It reads a row object from `[esi+8]`, uses its `[+0x20]` count, calls `0x9797a0`, `0x70b4e0`, and `0x401c00`, unlinks the row through `0x9cdee0(ecx = this+0x0c)`, clears `[esi+8]`, then calls `0x9cda80(ecx = this)`. |

The two callees that finish the slot-0 operation are also bounded:

| Evidence | Observation |
|---|---|
| `ev_f9f25c3c8cd3e081736a9b69a065f30aaef246de0827285ec6f0ebfd6c4efc0c` | `0x009cdee0` unlinks one node from a doubly linked list, decrements `[edi+0x0c]`, and dispatches through `[edx+0x0c]`; `ret 0x04`. |
| `ev_2d148d4106410ca9d6e0749f79c577cf1d98c2ac5b3e9c41d309fe08f89dd733` | `0x009cda80` scans `[esi+0x10]`, selects the node with the largest `[ecx]` value, formats a string into either `[esi+0x2ba80]` or `[esi+0x20]`, and writes status `2`, `1`, or `3` to `[esi+0x1c]`. |

These observations are consistent with slot 0 processing one parsed row and
then updating a loader status message, but the exact C++ method name and call
contract are not recovered. Slot 1 is verified only as a four-argument no-op.

## Call-site limit

The exported Ghidra call graph has no static caller edges to either
`0x009cdf80` or `0x009cd7f0`; that is expected for virtual dispatch and does
not identify the caller. A raw byte scan of the PE found the addresses of both
functions only inside the two virtual-table slots at `0x018101b0` and
`0x018101b4`, and found no absolute reference to the virtual-table address
itself. The dispatch site therefore remains unresolved. This is why note 19's
statement about the parsed row-list consumer is narrowed, not upgraded.

## Boundaries

- No account credential was provided, requested, captured, or stored.
- No runtime effect of either virtual slot is claimed beyond the observed
  instructions and callees.
- The parsed row fields still come from the `StartingZoneLoad.txt` header; the
  row consumer and any asset-list semantics remain unverified.
- This is not a full 1:1 port claim. Lua/gameplay semantics, live-session
  parity, other nested packet codecs, and engine material/tile fidelity remain
  open.
