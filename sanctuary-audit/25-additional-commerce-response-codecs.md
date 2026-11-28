# Additional `66` commerce response codecs

This note records eight more exact `PacketBaseInGamePurchase` response
decoders. Every field order is taken from the authoritative Sanctuary commit
`f5240b7554f2a80d6b815cb7ead7ffee12499565`, not from the compiled client. It
is a decoder-accuracy record only; it does not claim live-session or gameplay
parity.

## Wire frame

`Sanctuary.Packet/PacketBaseInGamePurchase.cs:5-20` writes `short 66` followed
by a `short` sub-opcode. `Sanctuary.Core/IO/PacketWriter.cs:164-184` writes
`IDictionary<int,T>` and `IDictionary<uint,T>` as an `int32` count followed by
each raw key and serialized value. Lists are written as an `int32` count
followed by each serialized element. Strings are an `int32` UTF-8 byte count
followed by bytes; bools are one byte.

## Exact decoders added

| Sub | C# class and source | Wire order decoded |
|---|---|---|
| 2 | `PacketInGamePurchasePreviewOrderResponse.cs:5-38` | `int OrderTrackingId`, `int Result`, `int Discount`, `int Total` |
| 4 | `PacketInGamePurchasePlaceOrderResponse.cs:6-44` | `int OrderTrackingId`, `int Result` cast from `InGamePurchaseOrderResult`, `string OrderId`, `int Discount`, `int Total` |
| 17 | `PacketInGamePurchaseCurrencyCodesResponse.cs:8-36` + `CurrencyCodeData.cs:5-28` | `int ErrorCode`, `string Locale`, then only when `ErrorCode == 1`, `int` count and `uint` key / `CurrencyCodeData` pairs: four strings, `int MinorUnit`, `int Decimals`, `bool Unknown` |
| 19 | `PacketInGamePurchaseStateCodesResponse.cs:8-32` + `StateCode.cs:5-14` | `int ErrorCode`, then only when `ErrorCode == 1`, `int` count and `StateCode` pairs of two strings. There is no locale field in this response. |
| 21 | `PacketInGamePurchaseCountryCodesResponse.cs:8-36` + `CountryCode.cs:5-18` | `int ErrorCode`, `string Locale`, then only when `ErrorCode == 1`, `int` count and `CountryCode` records of four strings |
| 26 | `PacketInGamePurchaseAccountInfoResponse.cs:5-34` | `int ErrorCode`, `string DefaultCountryCode`, `string DefaultCurrencyCode`, `bool IsParentalPasswordEnabled` |
| 28 | `PacketInGamePurchaseStoreBundleContentResponse.cs:7-38` | `int` count, then `ResponseData` records of two ints (`StoreId`, `BundleId`) |
| 39 | `InGamePurchaseUpdateItemRequirementsReply.cs:7-40` | `int` count, then `UpdateData` records of `int BundleId`, `bool CanPurchase` |

The sub-opcode names are cross-checked with
`Sanctuary.Packet.Common/Extensions/PacketReaderExtensions.cs:595-614`. The
`uint` currency key is decoded as `UInt32`; the decoded result enum in `66/4`
is retained as `Int32` because C# explicitly writes `(int)Result`.

## Safety and verification

- Collection counts use the existing decoder-only limit of 65,536. This is a
  local malformed-input guard, not a claimed C# server limit.
- A negative count or count above that guard throws. No partial collection is
  stored in `GatewayWorldObservation`.
- Conditional lists are empty when the error code is not `1`, matching the
  absence of list bytes in `Serialize()`.
- `66/17`, `66/19`, and `66/21` reject trailing bytes, so a wrong conditional
  branch cannot be silently accepted.
- `GatewaySimplePacketTests.testAdditionalCommerceResponsesUseExactCSharpFieldOrder`
  builds each fixture from the field order above, checks successful routing
  and observation state, and checks malformed counts.
- Local Foundation-only result:
  `TMPDIR=/tmp/opencode swift test --package-path ios --scratch-path /tmp/opencode/osfr-swift-test-chunks`
  passed 250 tests, 1 skipped, 0 failures.

## Boundaries

- Requests (`66/1`, `66/3`, `66/16`, `66/18`, `66/20`, `66/22`, `66/25`,
  `66/27`, `66/38`) are outbound shapes and were not added as inbound decoders.
- `66/2` and `66/4` are decoded as raw scalar results; the marketplace error
  meaning of specific result integers is not inferred beyond the C# comments.
- Remaining unresolved `66` sub-opcodes stay raw/mapped. No local simulation
  value is seeded from a packet whose codec has not been verified.
- No account credential was provided, requested, captured, or stored.
- This is not a full 1:1 port claim. Live-session parity, Lua/gameplay
  semantics, engine material/tile fidelity, and other nested codecs remain
  open.
