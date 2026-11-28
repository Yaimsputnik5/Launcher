# Scalar packet decoders and the Xcode target gap

This note records two concrete corrections made after the last verified IPA.
Neither is a 1:1 completeness claim.

## 1. Scalar server-to-client packets

Twenty-five small `Sanctuary.Packet` classes had exact `Serialize()` layouts in
the compiled C# source but were still falling through the Swift codec as raw
packets. They are now decoded from packet bytes only.

| Packet | Source | Wire layout from C# | Swift decoder | Observation fields |
|---|---|---|---|---|
| `ClientUpdatePacketHitpoints` | `BaseClientUpdatePacket/ClientUpdatePacketHitpoints.cs` | `short 38`, `short 1`, `int CurrentHitpoints`, `int MaxHitpoints` | `GatewayHitpointsUpdate` in `ios/Launcher/Services/GatewaySimplePackets.swift` | `GatewayWorldObservation.hitpointsCurrent`, `.hitpointsMax` |
| `PacketSetClientArea` | `PacketSetClientArea.cs` | `short 89`, `int AreaId`, `bool Enabled`, `int ElapsedMilliseconds` | `GatewayClientAreaUpdate` | `.activeClientAreaID`, `.clientAreaEnabled`, `.clientAreaElapsedMilliseconds` |
| `PacketMOTD` | `PacketMOTD.cs` | `short 87`, string `Unknown`, string `Unknown2` (both `Int32` byte count + UTF-8) | `GatewayMessageOfTheDay` | `.messageOfTheDay`, `.messageOfTheDaySecondary` |
| `ClientUpdatePacketMana` | `BaseClientUpdatePacket/ClientUpdatePacketMana.cs` | `short 38`, `short 13`, `int CurrentMana`, `int MaxMana`, `bool ShowOverHead` | `GatewayManaUpdate` | `.manaCurrent`, `.manaMax`, `.showManaOverHead` |
| `ClientUpdatePacketRemoveEffectTag` | `BaseClientUpdatePacket/ClientUpdatePacketRemoveEffectTag.cs` | `short 38`, `short 17`, `int TagId` | `GatewayEffectTagRemoval` | `.lastRemovedEffectTagID` |
| `QuestCompletePacket` | `BaseQuestPacket/QuestCompletePacket.cs` | `short 49`, **int** `4`, `int QuestId` | `GatewayQuestComplete` | `.completedQuestIDs` |
| `QuestFailedPacket` | `BaseQuestPacket/QuestFailedPacket.cs` | `short 49`, **int** `5`, `int QuestId` | `GatewayQuestFailed` | `.failedQuestIDs` |
| `CompletedQuestCountUpdatePacket` | `BaseQuestPacket/CompletedQuestCountUpdatePacket.cs` | `short 49`, **int** `12`, `int Count` | `GatewayCompletedQuestCount` | `.completedQuestCount` |
| `PetStatusPacket` | `PetBasePacket/PetStatusPacket.cs` | `short 53`, **byte** `3`, `int PetId`, four `float` values | `GatewayPetStatus` | `.lastPetStatus` |
| `PetActivePacket` | `PetBasePacket/PetActivePacket.cs` | `short 53`, **byte** `9`, `int PetId`, `ulong PetGuid` | `GatewayPetActive` | `.activePetGUIDs` |
| `TradeUpdateCoinCountPacket` | `BaseTradePacket/TradeUpdateCoinCountPacket.cs` | `short 59`, **byte** `11`, `int SessionId`, `int Revision`, `bool IsMine`, `int OfferedCoins` | `GatewayTradeCoinCount` | `.tradeCoinCounts` |
| `TradeMessagePacket` | `BaseTradePacket/TradeMessagePacket.cs` | `short 59`, **byte** `15`, byte `PartnerDisconnected`, byte `Completed`, byte `MessageCode` | `GatewayTradeMessage` | `.lastTradeMessage` |
| `PacketMembershipSubscriptionInfo` | `PacketMembershipSubscriptionInfo.cs` | `short 189`, `bool IsMember`, `bool IsReferee` | `GatewayMembershipInfo` | `.membershipInfo` |
| `PlayerUpdatePacketSetLookAt` | `BasePlayerUpdatePacket/PlayerUpdatePacketSetLookAt.cs` | `short 35`, `short 17`, `ulong Guid`, `ulong TargetGuid` | `GatewayLookAtTarget` | `.lookTargets` |
| `PlayerUpdatePacketExpectedSpeed` | `BasePlayerUpdatePacket/PlayerUpdatePacketExpectedSpeed.cs` | `short 35`, `short 23`, `ulong Guid`, `float ExpectedSpeed` | `GatewayExpectedSpeed` | `.expectedSpeeds` |
| `PlayerUpdatePacketThoughtBubble` | `BasePlayerUpdatePacket/PlayerUpdatePacketThoughtBubble.cs` | `short 35`, `short 27`, `ulong Guid`, `int IconId`, `int DurationSeconds`, `bool Clear` | `GatewayThoughtBubble` | `.thoughtBubbles` |
| `PlayerUpdatePacketSetCollidable` | `BasePlayerUpdatePacket/PlayerUpdatePacketSetCollidable.cs` | `short 35`, `short 50`, `ulong Guid`, `bool Collidable` | `GatewayCollidableUpdate` | `.collidableByGUID` |
| `FriendOnlinePacket` | `BaseFriendPacket/FriendOnlinePacket.cs` | `short 74`, **byte** `2`, string `Name`, `ulong Guid`, `bool IsLocal` | `GatewayFriendOnline` | `.friendPresence` |
| `PacketMountResponse` | `MountBasePacket/PacketMountResponse.cs` | `short 168`, **byte** `2`, `ulong RiderGuid`, `ulong MountGuid`, `int Seat`, `int QueuePosition`, `int Unknown`, `int CompositeEffectId`, `float NameVerticalOffset` | `GatewayMountState` | `.mountStates` |
| `PacketDismountResponse` | `MountBasePacket/PacketDismountResponse.cs` | `short 168`, **byte** `4`, `ulong RiderGuid`, `int CompositeEffectId` | `GatewayDismount` | `.lastDismount`, clears `.mountStates` |
| `QuestObjectiveActivatedPacket` | `BaseQuestPacket/QuestObjectiveActivatedPacket.cs` | `short 49`, **int** `8`, `int QuestId`, `int ObjectiveId`, `int RequiredCount`, `bool Unknown2` | `GatewayQuestObjectiveActivated` | `.questObjectiveRequirements` |
| `QuestObjectiveUpdatePacket` | `BaseQuestPacket/QuestObjectiveUpdatePacket.cs` | `short 49`, **int** `9`, `int QuestId`, `int ObjectiveId`, `int CurrentCount`, `float CompletedPercentage`, `bool Silent`, `int Unknown6` | `GatewayQuestObjectiveUpdate` | `.questObjectiveProgress` |
| `QuestObjectiveCompletePacket` | `BaseQuestPacket/QuestObjectiveCompletePacket.cs` | `short 49`, **int** `10`, `int QuestId`, `int ObjectiveId`, `float Percent`, `int CompositeEffectId`, `bool Silent` | `GatewayQuestObjectiveComplete` | `.completedQuestObjectiveIDs` |
| `QuestObjectiveFailedPacket` | `BaseQuestPacket/QuestObjectiveFailedPacket.cs` | `short 49`, **int** `11`, `int QuestId`, `int ObjectiveId` | `GatewayQuestObjectiveFailed` | `.failedQuestObjectiveIDs` |
| `PetTrickNotifyPacket` | `PetBasePacket/PetTrickNotifyPacket.cs` | `short 53`, **byte** `15`, five `int` fields (`PetId`, `NotificationType`, `TrickId`, `NameId`, `Unknown5`) | `GatewayPetTrickNotification` | `.lastPetTrickNotification` |

The quest family uses a 4-byte `int` sub-opcode, while `PetBasePacket`,
`BaseTradePacket`, `BaseFriendPacket` and `MountBasePacket` use one-byte
sub-opcodes; `BasePlayerUpdatePacket` uses a 2-byte `short`. The tests assert
all four layouts explicitly. Hitpoints, mana, client area, completed-quest
count, pet, trade, membership, friend, mount and quest-objective state are shown
in the remote `Gateway packet view` only when the corresponding packet has been
decoded. Fields named `Unknown`/`Unknown2`/`Unknown5`/`Unknown6` in the C#
source are kept verbatim rather than assigned invented meanings.

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

Result: 238 tests, 1 skipped, 0 failures. SwiftUI/UIKit/Network/Metal and
actual IPA compilation still require macOS GitHub Actions; no local iOS SDK is
available from this Linux host.

## Still open

- The remaining 352-class catalog is routing/layout metadata, not 226 decoded
  gameplay codecs.
- Lua command registration, zone-load row names, spawn transforms, engine
  material/tile fidelity and live-session parity remain unresolved.
- The verified release IPA predates this source; do not treat it as containing
  these decoders or the Xcode project correction.
