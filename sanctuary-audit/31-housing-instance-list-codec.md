# Exact housing instance list codec

This note adds Sanctuary housing packet 127/39. Evidence is from the
authoritative Sanctuary source at commit
`f5240b7554f2a80d6b815cb7ead7ffee12499565`; no live session or credential was
used.

## Wire evidence

| C# source | Wire order |
|---|---|
| `src/Sanctuary.Packet/BaseHousingPacket.cs` | `short 127`, `short SubOpCode` |
| `src/Sanctuary.Packet/BaseHousingPacket/HousingPacketInstanceList.cs` | Int32 `Instances.Count`, each `PlayerHousingInstanceInfo.Serialize`, then `ulong PlayerGuid` |
| `src/Sanctuary.Packet.Common/Housing/PlayerHousingInstanceInfo.cs` | owner GUID, instance GUID, name ID, house name, owner name, icon ID, fixture count, furniture score, last visited Int64, three booleans, three strings, float rating, votes, two booleans, factory plot ID, creation Int64 |

The nested `PlayerHousingInstanceInfo` layout was already verified for 127/45 in
note 26; this packet reuses that exact reader rather than inventing a new
interpretation.

## Swift changes

- Added `GatewayHousingInstanceList` for 127/39 and 127/39 dispatch in
  `GatewayWorldCodec.decodeAny`.
- The instance count is bounded to 65,536 as a decoder safety limit; negatives,
  oversized counts, truncated rows, and trailing bytes throw before any state is
  applied.
- Added packet-backed observation state `housingInstanceList` and an event label
  that reports the decoded count and player GUID.
- `GatewaySimplePacketTests.testHousingInstanceListUsesVerifiedNestedOrderAndBoundedCount`
  writes an independent byte buffer, checks nested fields and observation state,
  and rejects a negative count. Unknown 127 sub-opcodes still fall back to
  raw-preserving mapped packets.

## Limits

- The iOS launcher has no housing UI and does not send housing requests; this is
  server-reply classification only.
- `PlayerHousingInstanceData` for 127/28 remains unresolved because its C#
  `Serialize()` includes a TODO factory field and fixture dictionaries.
- No IPA was rebuilt. The published release remains stale relative to this
  source change, and no full 1:1 port claim is made.
- Foundation-only tests after the change: 254 tests, 1 skipped, 0 failures.
- No account credential was provided, requested, captured, or stored.
