# Additional store catalog codecs from exact Sanctuary serializers

This note extends note 22 with five more server-to-client `66` sub-opcodes. Like
note 22, every decoded field comes from direct scalar, string, list, or
dictionary writes in Sanctuary `Serialize()` methods. No offline store, wallet,
membership, sale, or item value is used to fill a remote packet field.

## Source identity

- Repository: `Open-Source-Free-Realms/Sanctuary`
- Commit: `f5240b7554f2a80d6b815cb7ead7ffee12499565`
- Same source commit as the embedded Sanctuary resources and notes 21–22.
- Sub-opcode names were cross-checked against
  `Sanctuary.Packet.Common/Extensions/PacketReaderExtensions.cs`.
- Client REA target remains `FreeRealms.exe` SHA-256
  `26cc1c522a45e71fb57882da515f65bac45c8c8b8c8b7e740c0cea81c52a733351`; no
  compiled-client claim is made here.

## Verified wire layouts

`PacketBaseInGamePurchase.Write` writes `short 66`, then the `short`
sub-opcode. All tables below begin after that two-short header.

| Packet | Fields in `Serialize()` order |
|---|---|
| `PacketInGamePurchaseStoreBundleCategoryGroups` (66/6) | `Dictionary<int, StoreBundleCategoryGroupDefinition>`: `int` count, then repeated `int` key and group value |
| `PacketInGamePurchaseStoreBundleCategories` (66/7) | `StoreBundleCategoryTree.Serialize`: `Dictionary<int, StoreBundleCategoryNode>`, then `bool Sorted` |
| `PacketInGamePurchaseStoreBundleGroups` (66/9) | `Dictionary<int, StoreBundleGroupDefinition>`: `int` count, then repeated `int` key and group value |
| `PacketInGamePurchaseWalletInfoResponse` (66/11) | `int ErrorCode`, then `WalletInfo.Serialize` |
| `PacketInGamePurchaseSubscriptionProductsResponse` (66/23) | `int ErrorCode`, `string Locale`, and only when `ErrorCode == 1`, `List<MembershipSkuData>` |
| `InGamePurchaseUpdateSaleDisplay` (66/40) | `List<SaleDisplayInfo>`: `int` count, then sale entries |

Nested value layouts:

| Source type | Fields in wire order |
|---|---|
| `StoreBundleCategoryGroupDefinition` | `Id: int`, `CategoryIds: int count + int values` |
| `StoreBundleCategoryDefinition` | `Id: int`, `NameId: int`, `Image: ImageDataDefinition` |
| `StoreBundleCategoryNode` | inherited category fields, `ParentId: int`, `Count: int`, `DisplayOrder: int` |
| `StoreBundleCategoryTree` | `Categories: int count + (int key, StoreBundleCategoryNode) pairs`, `Sorted: bool` |
| `StoreBundleGroupDefinition.Entry` | `StoreBundleId: int`, `DisplayOrder: int` |
| `StoreBundleGroupDefinition` | `Id: int`, `NameId: int`, `DescriptionId: int`, `Image`, `IsExclusive: bool`, `Status: int`, `Entries: int count + (int key, Entry) pairs` |
| `WalletInfo` | `Unknown: bool`, `StationCash: int`, `CreditCardId: int`, `CurrencyCode: string`, `Unknown5: string`, `International: bool` |
| `MembershipSkuData` | `Sku`, `Name`, `Description`, `PreviewLegalText`, `MarketingDescription`, `ProductLegalText` strings, `PriceLocalCurrency: int`, `PriceStationCash: int`, `Unknown9: int`, `IsVatTaxable: bool` |
| `SaleDisplayInfo` | `Id`, `IconId`, `TintId`, `TitleId`, `BodyId`, `SecondsLeft`, `Unknown` ints, `IsMembership: bool` |
| `ImageDataDefinition` | `Image: string`, `Tint: string` |

Two source-order details matter:

1. `StoreBundleGroupDefinition` declares `Status` before `Image` and
   `IsExclusive`, but `Serialize()` writes `Image`, `IsExclusive`, then
   `Status`. The decoder follows `Serialize()`.
2. `MembershipSkuData` is written only when `ErrorCode == 1`. Other error codes
   leave no list bytes; the decoder does not invent an empty list payload or
   continue reading past the string.

`WalletInfo.Serialize` passes a maximum string length of 8 to
`PacketWriter.Write(string?, int)`, but the wire representation is still the
ordinary `int` UTF-8 byte count followed by bytes. The decoder preserves the
decoded string and does not infer a longer fixed-width field.

As in note 22, collection counts are bounded to 65,536 entries before
allocation. That is a Swift decoder safety limit, not a claimed C# server
limit. Negative, excessive, or truncated counts throw and set no observation
state.

## Swift integration

- `GatewayStoreCategoryGroupsPacket`, `GatewayStoreCategoriesPacket`,
  `GatewayStoreBundleGroupsPacket`, `GatewayStoreWalletInfoResponse`,
  `GatewaySubscriptionProductsResponse`, and `GatewaySaleDisplayUpdate` decode
  the packets above.
- `GatewayWorldCodec.decodeAny` routes each exact `66` sub-opcode; unknown `66`
  sub-opcodes keep the raw/mapped fallback and no decoded state.
- `GatewayWorldPacket` adds one case per decoder, and
  `GatewayWorldObservation` stores only packet-derived values in
  `storeCategoryGroups`, `storeCategoryTree`, `storeBundleGroups`,
  `storeWalletInfo`, `subscriptionProducts`, and `saleDisplays`.
- Remote observation remains presentation-only. These values never seed
  offline play, inventories, currency, characters, or server responses.

## Verification

- `TMPDIR=/tmp/opencode swift test --package-path ios --scratch-path /tmp/opencode/osfr-swift-test-chunks`
- Result: `249 tests, 1 skipped, 0 failures`.
- New fixture:
  `GatewaySimplePacketTests.testAdditionalStorePacketsUseExactCSharpFieldOrder`
  writes all five successful packets in C# field order, checks nested values,
  checks the conditional subscription list on both success and error codes,
  applies every packet to packet-only observation state, and rejects a negative
  collection count.
- No macOS/iOS toolchain is available on this host. GitHub Actions has no run
  for the newer source commits and the published `ios-ipa` asset predates these
  decoders; no compiled iOS verification is claimed.

## Boundaries

- Other `66` sub-opcodes, including bundles, content responses, account info,
  currency/state/country codes, merchant packets, IOTD, BOTD, and client
  statistics, remain raw/mapped unless their exact source layout is added.
- Several of those packets contain nested codecs not verified here; they are
  deliberately not guessed from declaration order.
- No account credential was provided, requested, captured, or stored.
- This is not a full 1:1 port claim. Lua/gameplay semantics, live-session
  parity, other nested packet codecs, and engine material/tile fidelity remain
  open.
