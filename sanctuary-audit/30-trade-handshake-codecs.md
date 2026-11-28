# Exact trade handshake codecs

This note adds three Sanctuary trade packets whose nested `NameData` codec was
already verified. Evidence is from the authoritative Sanctuary source at commit
`f5240b7554f2a80d6b815cb7ead7ffee12499565`; no live session or credential was
used.

## Wire evidence

| C# source | Sub-opcode | Verified body order |
|---|---:|---|
| `src/Sanctuary.Packet/BaseTradePacket.cs` | base | `short 59`, `byte SubOpCode` |
| `src/Sanctuary.Packet.Common/NameData.cs` | nested | `int FirstNameId`, `int LastNamePrefixId`, `int LastNameSuffixId`, string `FirstName`, string `LastName` |
| `BaseTradePacket/TradeInvitePacket.cs` | 2 | `NameData InviterName`, `ulong InviterGuid`, `int SessionId` |
| `BaseTradePacket/TradeStartSessionPacket.cs` | 4 | `ulong PartnerGuid`, `NameData PartnerName`, `int SessionId` |
| `BaseTradePacket/TradeRejectedPacket.cs` | 16 | `NameData RejectingPlayer` |

The asymmetry between invite and start-session is explicit in the C#
`WriteBody` methods and is preserved in Swift rather than normalized.

## Swift changes

- Added `GatewayTradeInvite`, `GatewayTradeStartSession`, and
  `GatewayTradeRejected` with exact field order and trailing-byte rejection.
- Added world-packet cases and 59/2, 59/4, 59/16 dispatch in
  `GatewayWorldCodec.decodeAny`; unknown trade sub-opcodes continue to fall back
  to raw/mapped packets.
- Added packet-backed observation state: `tradeInvites`,
  `lastTradeStartSession`, and `lastTradeRejection`. No inventory, coin, chat,
  entity, or confirmed-trade state is inferred from these packets.
- `GatewaySimplePacketTests.testTradeHandshakePacketsUseVerifiedNameDataOrder`
  writes independent byte buffers, checks decoded values and observation state,
  and verifies that unrelated trade state stays empty.

## Limits

- The iOS launcher still has no trade UI and does not send trade requests; these
  decoders only classify server replies without fabricating local gameplay.
- This does not resolve `TradeRequestPacket` or other client-to-server trade
  layouts, and no claim is made that the full trade protocol is ported.
- No IPA was rebuilt. The published release remains stale relative to this
  source change.
- Foundation-only tests after the change: 253 tests, 1 skipped, 0 failures.
- No account credential was provided, requested, captured, or stored.
