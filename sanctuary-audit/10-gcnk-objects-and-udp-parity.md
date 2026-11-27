# GCNK object placements and UDP parity fixes

## GCNK v6 object records

A targeted scan of the embedded big-endian `.pack` directory chains found 145
`FabledRealms_*.gcnk` entries across `Assets_000.pack`…`Assets_009.pack`. Every
one begins with:

| Offset | Type | Observed meaning |
| --- | --- | --- |
| `0x00` | `char[4]` | `GCNK` |
| `0x04` | `u32 LE` | version `6` |
| `0x08` | `u32 LE` | decompressed byte length |
| `0x0C` | `u32 LE` | compressed byte length |
| `0x10` | bytes | RFC 1950 zlib stream |

Decompressing all 145 streams reproduced each declared length exactly. Scanning
the decompressed bytes for null-terminated `.adr`, `.agr`, and `.cln` asset
names and validating the following fields produced **906 object records with no
rejected candidates**:

- one null terminator after the name, then one observed zero separator byte;
- nine little-endian `f32` fields (`x`, `y`, `z`, scale, three rotation values,
  and two additional fields);
- `u32 0x00FF0000` at `nameEnd + 3` (where `nameEnd` is the index after the
  separator byte);
- finite coordinates inside the zone's practical bounds.

Examples:

- `FabledRealms_0_-8.gcnk`: 321 objects, X `-533.93…-233.63`, Z
  `-51.89…271.88`. First record is `sh_corral_piece_02.adr` at
  `(-448.996, 37.093, 35.793)`.
- `FabledRealms_4_-12.gcnk`: 246 objects, X `-762.26…-488.08`, Z
  `257.29…656.96`. First record is `sg_bird_01.adr` at
  `(-762.264, 118.556, 265.955)`.

The first object's position sits beside `HighroadJunction_sparkles_06` and
`_07` area definitions near `(-446, -12)` and `(-425, 26)` in
`FabledRealmsAreas.xml`, which supports reading these coordinates as world
coordinates rather than chunk-local offsets.

`ClientChunkCatalog.swift` now decodes these records from the embedded packs.
The offline native view draws the 32 nearest decoded objects within 900 world
units of the player and labels each with its exact shipped asset name. Remote
sessions deliberately skip this catalog: their markers still come only from
gateway position packets.

This is evidence-backed placement presentation, not a reconstruction of the
original renderer's meshes, materials, collision, or gameplay behavior.

## UdpLibrary parity fixes from authoritative Sanctuary source

The authoritative source is `/tmp/opencode/sanctuary/src` at commit
`f5240b7554f2a80d6b815cb7ead7ffee12499565`.

- `UdpConnection.cs:1675-1684` treats packet types `1`, `2`, `29`, `30`, `31`,
  and `32` as non-encrypted. The Swift map previously used `1`, `2`, `27`,
  `28`, `29`, `30`. It now follows C#.
- `UdpConnection.cs:988-1013` processes every Multi slice, including a
  zero-length slice, before advancing. Swift previously stopped decoding the
  container at the first empty entry; it now advances and continues.
- `UdpConnection.cs:827-868` reads the 21-byte confirm layout but treats the
  trailing protocol version as optional. Swift now accepts the mandatory
  17-byte form and the live 21-byte form.
- `UdpConnection.cs:1328-1348` sends `[0, KeepAlive]` after `KeepAliveDelay`
  and routes it through the same negotiated flag/CRC passes. The gateway now
  sends a keepalive every 10 s after authentication, matching Sanctuary's
  external-client `UdpParams` default and staying below the gateway's 30 s
  no-data timeout.
- `Internal/UdpReliableChannel.cs:155-257` advances the incoming head as soon
  as an expected packet is processed, buffers later ids until the gap is filled,
  suppresses duplicates, and sends AckAll through `head - 1` whenever the head
  advanced. Swift now has a four-channel ordered inbound queue with wrap-safe
  16-bit ids and the same Ack/AckAll decision for both login and gateway.

## Remaining protocol gaps

The "not implemented" list below is historical; it described an earlier
transport. The current `ios/Launcher/Services/UdpLibraryTransport.swift` has
per-channel reliable state with congestion/RTT tracking, CRC widths 0–4, five
encryption methods, 64-bit ID reconstruction, a fragmenter, Group codec and
coalescer, shared Multi buffering, cooking/crypto and inflate. These remain
unresolved:

- Live timing, congestion behavior and long-session stability against the real
  server have not been verified from this host.
- Full opcode/sub-opcode serializer coverage is incomplete; unknown fields are
  not invented.
- GCNK decoding provides object records and labels, not reconstructed collision,
  animation, interaction or gameplay semantics.

## Verification

- Linux foundation tests: `swift test --package-path ios` — 206 tests, 1 skipped.
- New tests cover the GCNK record layout, bad magic/version rejection,
  zero-length Multi entries, the non-encrypted type map, the optional
  17-byte confirm form, the negotiated keepalive frame, AckAll numbering, and
  wrap-aware ordered delivery with duplicate suppression on independent channels.
- iOS compile and IPA publication remain gated on `ios-build.yml`; no release
  asset is considered updated until that workflow is green.
