# Store bundle codec from exact nested Sanctuary serializers

This note closes the 66/5 raw-packet gap recorded in note 21. It adds one exact
decoder whose nested values all come from scalar, string, list, and dictionary
writes in the Sanctuary source. No offline store, profile, currency, or item
value is used to fill a decoded field.

## Source identity

- Repository: `Open-Source-Free-Realms/Sanctuary`
- Commit: `f5240b7554f2a80d6b815cb7ead7ffee12499565`
- Same source commit as the embedded Sanctuary resources and note 21.
- Client REA target remains `FreeRealms.exe` SHA-256
  `26cc1c522a45e71fb57882da515f65bac45c8c8b8c8b7e740c0cea81c52a733351`; no
  compiled-client claim is made here.

## Verified wire layout

`PacketBaseInGamePurchase.Write` writes `short 66` then `short SubOpCode`.
`PacketInGamePurchaseStoreBundleBase.Write` adds `int SubOpCode` (1 for
`PacketInGamePurchaseStoreBundles`) and `int StoreId`.
`PacketInGamePurchaseStoreBundles.Serialize` then calls
`StoreDefinition.Serialize(writer)`.

`Sanctuary.Game/Zones/BaseZone.cs` sends this packet with `SendTunneled` after
filling the store from `ResourceManager.Stores[1]`, so the decoder handles a
server-to-client world packet.

| Source | Fields in wire order |
|---|---|
| `PacketWriter.Write(DateTimeOffset)` | `long` seconds since Unix epoch |
| `PacketWriter.Write(string?)` | `int` UTF-8 byte count, then bytes; null and empty both write 0 |
| `ImageDataDefinition.Serialize` | `Image: string`, `Tint: string` |
| `MarketingBundleDefinition.Entry.Serialize` | `Quantity: int`, `GameItemId: int`, `MarketingItemId: int`, `ImageTintOverride: string` |
| `MarketingBundleDefinition.Serialize` | `Id: int`, `NameId: int`, `DescriptionId: int`, `Status: int`, `Image`, `IsTintable: bool`, `TintGroup: string`, `CurrencyType: int`, `Price: int`, `AltCurrencyPrice: int`, `AltPrice: int`, `PartnerId: int`, `LaunchTime: long`, `ExpireTime: long`, `Unknown: int`, `Unknown2: bool`, `LaunchTime: long`, `ExpireTime: long`, `Entries: int count + entries` |
| `StoreBundleDefinition.Serialize` | inherited marketing bundle fields, `StoreId: int`, `CategoryGroupId: int`, `IsVisible: bool`, `MaxPerOrder: int`, `DisplayOrder: int`, `CategoryDisplayOrder: int`, `DiscountType: int`, `SkuId: int`, `DiscountValue: int`, `Unknown3: int`, `Unknown4: int`, `TermsAndConditionsId: byte`, `New: bool`, `IsViewOnly: bool` |
| `AppStoreBundleDefinition.Serialize` | inherited store bundle fields, `MemberDiscount: int`, `LimitedSeriesId: int`, `IsMembersOnly: bool`, `VipRank: int`, `MembersOnlyPrice: int`, `SalePrice: int`, `IsMerchantOnly: bool`, `IsLimitedTime: bool`, `ForceCanPreview: int`, `PreviewAnimId: int` |
| `StoreDefinition.Serialize` | `Id: int`, `NameId: int`, `DescriptionId: int`, `Image`, `Bundles: int count + (int key, AppStoreBundleDefinition) pairs` |

Two source-order details matter:

1. `AppStoreBundleDefinition` declares `IsMerchantOnly` before `MembersOnlyPrice`,
   but `Serialize()` writes `MembersOnlyPrice`, `SalePrice`, then
   `IsMerchantOnly`. The decoder follows `Serialize()`.
2. `MarketingBundleDefinition` writes `LaunchTime` and `ExpireTime` twice. Both
   copies are decoded and kept as separate `Int64` values; no time-zone
   conversion or interpolated value is introduced.

The C# nullable strings cannot distinguish `null` from `""` on the wire. Swift
therefore stores the decoded string exactly as written and does not invent a
nil where the packet carries a zero-length field.

Collection counts are `int32` and are bounded to 65,536 entries before
allocation. That is a decoder safety limit, not a claimed C# server limit.

## Swift integration

- `GatewayInGamePurchaseStoreBundles` decodes opcode 66, short sub-opcode 5,
  internal opcode 1, `StoreId`, and the nested store definition.
- `GatewayWorldCodec.decodeAny` routes 66/5 to the new decoder; other 66
  sub-opcodes keep their existing decoders or raw-preserving fallback.
- `GatewayWorldPacket.inGamePurchaseStoreBundles` stores only packet-derived
  values in `GatewayWorldObservation.inGamePurchaseStoreBundles`.
- Malformed nested data throws a `GatewayProtocolError` and sets no decoded
  store state. Truncated packets do not fall back to observation values.

## Verification

- `TMPDIR=/tmp/opencode swift test --package-path ios --scratch-path /tmp/opencode/osfr-swift-test-chunks`
- Result: `248 tests, 1 skipped, 0 failures`.
- New fixture:
  `GatewaySimplePacketTests.testStoreBundlesDecoderMatchesNestedCSharpFieldOrder`
  writes the full nested packet in C# field order, checks scalar/string/list/
  dictionary values, checks packet-only observation state, and rejects a
  negative collection count.
- No macOS/iOS toolchain is available on this host. GitHub Actions has no run
  for the newer source commits and the published `ios-ipa` asset predates this
  decoder; no compiled iOS verification is claimed.

## Boundaries

- This does not decode the other `PacketInGamePurchaseStoreBundleBase`
  subclasses or any nested codec that was not verified from source.
- Store data is presentation-only observation state. It never seeds offline
  play, inventories, currency, characters, or server responses.
- No account credential was provided, requested, captured, or stored.
- This is not a full 1:1 port claim. Lua/gameplay semantics, other nested packet
  codecs, live-session parity, and engine material/tile fidelity remain open.
