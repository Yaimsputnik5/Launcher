# Packet-backed world view and navgraph evidence

This note records two evidence-backed steps that keep the native renderer tied
to shipped client data and received gateway packets.

## Gateway world packets in the remote World tab

`GatewaySession` already decoded two world payloads:

- `WorldPositionUpdate` (opcode 125): GUID, position, rotation, state, teleport
  sequence.
- `GatewayChatMessage` (opcode 15, sub-opcode 1): channel, sender/recipient
  GUIDs and names, message, position, guild GUID, language, and optional area ID.

`GatewayUDPSession` now exposes decoded world packets through a callback.
`AppState` folds them into `GatewayWorldObservation`, which is empty until the
server sends a packet. The remote World tab passes that observation to a remote
`OSFREngine` presentation mode. In that mode:

- The zone grid still comes from bundled Sanctuary JSON resources.
- Markers appear only for GUIDs seen in position packets.
- Chat rows appear only for decoded chat packets.
- No local player, NPC, collection node, destination, or inferred spawn is
  drawn. Those values remain offline-only.

Foundation tests cover the observation accumulator and prove that removing all
observations removes every packet-backed marker from the remote frame.

## Entity spawn and self-packet decoding

Two more tunneled world payloads are now decoded from the authoritative
Sanctuary packet classes:

- `BasePlayerUpdatePacket` opcode `35`, sub-opcode `1` (`PlayerUpdatePacketAddPc`)
  or `2` (`PlayerUpdatePacketAddNpc`). The decoder reads only the verified
  prefix through the full four-float `Vector4` position and `Quaternion`
  rotation; later appearance fields are intentionally left untouched. PC names
  come from `NameData` (three Int32 IDs, first name, last name). NPC names in the
  view are derived from the real `NameId` field as `NPC <id>` because the full
  localized name table is not decoded here.
- `PacketSendSelfToClient` opcode `12`: a length-prefixed nested world packet.
  The session emits the wrapper event and recursively decodes the nested packet
  up to a depth of four, so self-spawn and self-position data are still
  packet-backed rather than synthesized.

Spawn names are stored per GUID in the observation. Position-only updates never
create a name, so the remote view falls back to the GUID when no spawn packet
has supplied a label.

Sources:
`/tmp/opencode/sanctuary/src/Sanctuary.Packet/BasePlayerUpdatePacket/PlayerUpdatePacketAddPc.cs`,
`.../PlayerUpdatePacketAddNpc.cs`, `.../BasePlayerUpdatePacket.cs`, and
`/tmp/opencode/sanctuary/src/Sanctuary.Packet/PacketSendSelfToClient.cs`.

## `FabledRealms.map` decoded structure

`FabledRealms.map` is stored in `Assets_002.pack` at absolute offset 37,348,187
with size 74,796. It begins with node ID `2018`, not a file count. Iterating the
following variable-length records consumes the file exactly:

| Field | Type | Meaning |
| --- | --- | --- |
| node ID | `u32` | Sequential value in `0...2018` |
| position | `f32 x3` | World-space coordinates |
| neighbor count | `u32` | Number of following edge records |
| neighbors | `u32 id`, `f32 distance` repeated | Adjacent nodes and distance |

Observed totals:

- 2,019 nodes, with every ID `0...2018` present exactly once.
- 4,302 directed entries; every entry has a matching reverse edge with the same
  distance within `0.01`.
- Position ranges: X `-2551.12...1015.77`, Y `-103.21...144.91`,
  Z `-1538.25...2867.47`.
- Neighbor counts: 1 (134 nodes), 2 (1,518), 3 (338), 4 (27), 5 (2).
- First node: `2018`, position `(232.851837, 106.894730, 748.490601)`, edges to
  `2001` at `18.559731` and `2017` at `20.362385`.

The X/Z ranges overlap the live `FabledRealms` world coordinates logged by the
client, and the edge distances match the Euclidean distances between the
stored positions. This is a decoded graph from the shipped client; the original
engine's exact use of it has not been reconstructed from compiled code yet.

## Related chunk evidence

Each `FabledRealms_<longitude>_<latitude>.gcnk` begins `GCNK` version 6. After
two header fields, a zlib stream starts at offset `0x10`. Decompressed streams
contain `.adr`/`.agr` object names and float records, for example
`sh_corral_piece_02.adr` and `sg_tree_giant_03.adr`. This is evidence for
future object placement work, not yet a reconstructed chunk schema.

## Verification

- Linux foundation tests: `swift test --package-path ios` — 138 tests, 0 failures.
- iOS compilation and IPA replacement remain gated on the `ios-build.yml`
  workflow; no release asset is considered updated until that run is green.
