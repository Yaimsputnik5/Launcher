# Raw payload packet boundaries

This note adds three exact wire boundaries whose C# payloads are intentionally
not interpreted. Evidence is from the authoritative Sanctuary source at commit
`f5240b7554f2a80d6b815cb7ead7ffee12499565`; no live session or credential was
used.

## Wire evidence

| C# source | Opcode | Verified body order |
|---|---:|---|
| `PacketPointOfInterestDefinitionReply.cs` | 57 | `short 57`, `WritePayload(Payload)` |
| `BaseInspectPacket.cs` / `StartInspectPacket.cs` | 149/1 | `short 149`, `byte 1`, UInt64 `Guid`, bool `ShowPedestal`, `WritePayload(Payload)` |
| `BasePlayerTitlePacket.cs` / `PlayerTitleUpdateAllPacket.cs` | 152/3 | `short 152`, Int32 `3`, `WritePayload(Payload)` |

`PacketWriter.WritePayload` writes an Int32 byte count followed by the bytes.
These bodies are exact enough to decode the framing, but the payloads themselves
use fixture dictionaries/TODOs or unresolved definition formats in Sanctuary.
The Swift decoders therefore keep them verbatim instead of inventing content.

## Swift changes

- Added `GatewayPOIDefinitionReply`, `GatewayStartInspect`, and
  `GatewayPlayerTitleUpdateAll` with exact opcode/sub-opcode widths, payload
  length framing, negative-length/truncation rejection, and trailing-byte
  rejection.
- Added single dispatch cases for 57, 149/1, and 152/3. Unknown 149 and 152
  sub-opcodes remain raw-preserving mapped packets; there was no existing
  decoded 57 case to shadow.
- Added observation state `lastPOIDefinitionReply`, `lastStartInspect`, and
  `lastPlayerTitleUpdateAll`. The UI records only the GUID, pedestal flag, and
  raw byte counts; no inspect content, POI definition, or title is synthesized.
- `GatewaySimplePacketTests.testRawPayloadPacketsKeepPayloadBytesWithoutInterpretingThem`
  writes independent buffers, checks the preserved bytes, and verifies the new
  observation fields without invoking script or gameplay paths.

## Limits

- These are framing decoders only. They do not implement POI definition parsing,
  inspect payload content, or title semantics.
- No IPA was rebuilt. The published release remains stale relative to this
  source change, and no full 1:1 port claim is made.
- Foundation-only tests after the change: 256 tests, 1 skipped, 0 failures.
- No account credential was provided, requested, captured, or stored.
