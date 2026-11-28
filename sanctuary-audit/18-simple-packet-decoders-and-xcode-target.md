# Scalar packet decoders and the Xcode target gap

This note records two concrete corrections made after the last verified IPA.
Neither is a 1:1 completeness claim.

## 1. Scalar server-to-client packets

Three small `Sanctuary.Packet` classes had exact `Serialize()` layouts in the
compiled C# source but were still falling through the Swift codec as raw
packets. They are now decoded from packet bytes only.

| Packet | Source | Wire layout from C# | Swift decoder | Observation fields |
|---|---|---|---|---|
| `ClientUpdatePacketHitpoints` | `BaseClientUpdatePacket/ClientUpdatePacketHitpoints.cs` | `short 38`, `short 1`, `int CurrentHitpoints`, `int MaxHitpoints` | `GatewayHitpointsUpdate` in `ios/Launcher/Services/GatewaySimplePackets.swift` | `GatewayWorldObservation.hitpointsCurrent`, `.hitpointsMax` |
| `PacketSetClientArea` | `PacketSetClientArea.cs` | `short 89`, `int AreaId`, `bool Enabled`, `int ElapsedMilliseconds` | `GatewayClientAreaUpdate` | `.activeClientAreaID`, `.clientAreaEnabled`, `.clientAreaElapsedMilliseconds` |
| `PacketMOTD` | `PacketMOTD.cs` | `short 87`, string `Unknown`, string `Unknown2` (both `Int32` byte count + UTF-8) | `GatewayMessageOfTheDay` | `.messageOfTheDay`, `.messageOfTheDaySecondary` |

The Swift initializers require an exact opcode/sub-opcode, reject trailing
bytes, and are dispatched from `GatewayWorldCodec.decodeAny` before the generic
raw-preserving catalog fallback. A wrong sub-opcode such as `38/99` is still
`.unknown(38, raw bytes)`; it is never interpreted as hitpoints and never sets
observation state. The new `GatewaySimplePacketTests` fixtures are built in the
same field order as the C# `PacketWriter` calls, including the one-byte `bool`
and both length-prefixed strings.

These fields remain packet-backed. They are not seeded from offline simulation,
cache, defaults or the engine. This preserves the remote-session rule that
local simulation must not be presented as server state.

## 2. Missing Swift files in the Xcode project

`ios/Package.swift` listed `GatewayProtocol.swift`, `PacketCatalog.swift` and
`SanctuaryPacketInventory.swift`, but `ios/Launcher.xcodeproj/project.pbxproj`
did not. A CI build of the then-current `ios-build` source would have failed to
compile references to those types even though the SwiftPM/Linux test target
succeeded. The Xcode project now contains file references, source entries and
build-phase entries for:

- `Services/SanctuaryPacketInventory.swift`
- `Services/PacketCatalog.swift`
- `Services/GatewaySimplePackets.swift`

A consistency check reports no duplicate object IDs, no Swift file present on
disk but missing from the project, and no Swift build file missing from the
sources phase. This is a build-integrity fix, not evidence that the IPA has
been rebuilt: GitHub still reported zero Actions runs and zero check runs for
the newer `ios-build` commits at the time of this note.

## Verification

Local Foundation-only suite after these changes:

```
TMPDIR=/tmp/opencode swift test --package-path ios --scratch-path /tmp/opencode/osfr-swift-test-chunks
```

Result: 226 tests, 1 skipped, 0 failures. SwiftUI/UIKit/Network/Metal and
actual IPA compilation still require macOS GitHub Actions; no local iOS SDK is
available from this Linux host.

## Still open

- The remaining 352-class catalog is routing/layout metadata, not 226 decoded
  gameplay codecs.
- Lua command registration, zone-load row names, spawn transforms, engine
  material/tile fidelity and live-session parity remain unresolved.
- The verified release IPA predates this source; do not treat it as containing
  these decoders or the Xcode project correction.
