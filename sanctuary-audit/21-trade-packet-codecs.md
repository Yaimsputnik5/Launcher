# Trade packet codecs from exact Sanctuary serializers

This note adds five `BaseTradePacket` (opcode 59) decoders and one scalar-only
nested codec. It is **source-verified only**: the layouts come from the
Sanctuary commit that also supplied the embedded server resources, and no
offline value is used to fill a decoded field.

## Source identity

- Repository: `Open-Source-Free-Realms/Sanctuary`
- Commit: `f5240b7554f2a80d6b815cb7ead7ffee12499565`
- This is the same commit used for the embedded Sanctuary resources.
- Client REA target remains `FreeRealms.exe` SHA-256
  `26cc1c522a45e71fb57882da515f65bac45c8c8b8c8b7e740c0cea81c52a733351`; no
  new compiled-client claim is made here.

## Newly decoded wire layouts

`BaseTradePacket` writes the short opcode 59 followed by a one-byte sub-opcode.
The following derived classes then write only scalars:

| Sub-opcode | C# class | Fields in wire order |
|---:|---|---|
| 5 | `TradeEndSessionPacket` | `SessionId: int` |
| 12 | `TradeUpdateAddItemPacket` | `SessionId: int`, `Revision: int`, `IsMine: bool`, `ItemInstance.Serialize(writer)` |
| 13 | `TradeUpdateItemCountPacket` | `SessionId: int`, `Revision: int`, `IsMine: bool`, `ItemInstanceId: int`, `OfferedTotal: int` |
| 17 | `TradeUpdateLockPacket` | `SessionId: int`, `Locked: bool` |
| 18 | `TradeConfirmPacket` | `SessionId: int` |

`TradeUpdateAddItemPacket` does not call `Serialize()` directly on its `Item`
field; it constructs an exact `ItemInstance` and calls its scalar serializer.
That codec is now implemented as `GatewayTradeItemInstance`:

| Source | Fields in wire order |
|---|---|
| `ItemRecord.Serialize` | `Definition: int`, `Tint: int` |
| `ItemInstance.Serialize` | `Id: int`, `Count: int`, `ConsumedCount: int`, `LastCastTime: int`, hard-coded `false` rental placeholder, `AbilityCount: int` |

The Swift name `rentalPlaceholder` marks the hard-coded `false` write; it is
not a claim that the C# source names that field.

The app now sets these observation values only from decoded packets:
`lastEndedTradeSessionID`, `lastTradeAddItem`, `lastTradeItemCount`,
`lastTradeLock`, and `confirmedTradeSessionIDs`. No offline inventory, cache,
default profile, or simulated trade state feeds them.

## Excluded layout

`PacketInGamePurchaseStoreBundleBase` (66/5) declares only `StoreId: int`, but
its `Write` method also writes an `int SubOpCode` and its only concrete derived
class calls `StoreDefinition.Serialize(writer)`. It remains raw-preserving
`.mapped`/`.unknown` until a `StoreDefinition` codec exists. This follows the
same nested-serializer boundary used in note 18.

`TradeUpdateAddItemPacket` would also have remained raw-preserving without the
new scalar `ItemInstance` codec.

## Verification

- `TMPDIR=/tmp/opencode swift test --package-path ios --scratch-path /tmp/opencode/osfr-swift-test-chunks`
- Result: `247 tests, 1 skipped, 0 failures`; `grep -c 'error:'` returned `0`.
- New fixture: `GatewaySimplePacketTests.testAdditionalTradePacketsUseExactCSharpFieldOrder`
  writes each packet from the C# field order and verifies decoded fields and
  packet-only observation state.
- The GitHub Actions workflow still has no run for these source commits, and
  the published `ios-ipa` asset predates them. No compiled iOS verification is claimed.

## Boundaries

- Remote worlds remain packet-only; decoded trade state does not seed or mutate
  offline play.
- No account credential was provided, requested, captured, or stored.
- No full 1:1 claim is made. Nested packet codecs beyond `ItemInstance`, live
  session parity, engine material/tile fidelity, and compiled-client semantics
  stay open as recorded in notes 14–20.
