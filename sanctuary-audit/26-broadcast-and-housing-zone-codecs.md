# Broadcast-zone and housing-zone codecs

This note adds two server-to-client decoders whose nested fields are fully
verified in Sanctuary commit `f5240b7554f2a80d6b815cb7ead7ffee12499565`. It is
a decoder-accuracy record, not a gameplay or live-session parity claim.

## `BroadcastPacketZone` (77/2)

| Evidence | Observation |
|---|---|
| `Sanctuary.Packet/BaseBroadcastPacket.cs:5-20` | Base writes `short 77`, `short 2`. |
| `Sanctuary.Packet/BaseBroadcastPacket/BroadcastPacketZone.cs:6-31` | Body is `NameData`, `string Message`, `int MessageId`. |
| `Sanctuary.Packet.Common/NameData.cs:5-26` | `NameData.Serialize` writes three Int32 name IDs, then `FirstName` and `LastName` as Int32 byte-count-prefixed UTF-8. |
| `SanctuaryPacketInventory.swift` | Direction for `BroadcastPacketZone` is `server->client`. |

The decoder reuses the existing `GatewayName` codec and rejects trailing bytes.

## `HousingPacketZoneData` (127/45)

| Evidence | Observation |
|---|---|
| `Sanctuary.Packet/BaseHousingPacket.cs:5-20` | Base writes `short 127`, `short 45`. |
| `Sanctuary.Packet/BaseHousingPacket/HousingPacketZoneData.cs:6-35` | Body is `bool IsPreview`, `bool Unused`, `int HeadSize`, then `PlayerHousingInstanceInfo.Serialize`. |
| `Sanctuary.Packet.Common/Housing/PlayerHousingInstanceInfo.cs:7-74` | Nested write order is two UInt64 GUIDs, `int NameId`, `HouseName`, `OwnerName`, three ints, `DateTimeOffset LastVisited`, three bools, three strings, `float Rating`, `int Votes`, two bools, `int FactoryPlotId`, `DateTimeOffset WhenCreated`. |
| `Sanctuary.Core/IO/PacketWriter.cs:86-94` | `DateTimeOffset` is written as Int64 seconds since the Unix epoch. |

`HouseName` is decoded before `OwnerName` because that is the `Serialize()`
order, even though the C# fields are declared in the opposite order. Both
timestamps are decoded as Int64 and retained as raw epoch seconds rather than
converted into local time.

## Verification and boundaries

- Unknown `127` sub-opcodes, including `127/44`, remain raw/mapped because the
  inventory marks them `client->server` and they are not inbound responses.
- A wrong `127` sub-opcode stays mapped; the test asserts that no housing state
  is inferred from it.
- `GatewaySimplePacketTests.testServerBroadcastAndHousingZoneDataUseExactCSharpFieldOrder`
  builds the fixture from the exact write order and checks observation state.
- Local Foundation-only result:
  `TMPDIR=/tmp/opencode swift test --package-path ios --scratch-path /tmp/opencode/osfr-swift-test-chunks`
  passed 251 tests, 1 skipped, 0 failures.
- No account credential was provided, requested, captured, or stored.
- This is not a full 1:1 port claim. Other nested codecs, Lua/gameplay
  semantics, engine fidelity, and live-session parity remain open.
