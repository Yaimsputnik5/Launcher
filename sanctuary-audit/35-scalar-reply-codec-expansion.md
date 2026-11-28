# Scalar reply codec expansion

This note adds 29 server-to-client codecs whose Sanctuary
`Serialize()` implementations contain only scalar fields, verified nested
primitives, or bounded loops of verified primitives. Evidence is from the
authoritative source tree at commit
`f5240b7554f2a80d6b815cb7ead7ffee12499565`. No live session, credential, or
offline value was used to fill a field.

## Exact layouts added

| Base/sub | Sanctuary class | Verified body order |
|---|---|---|
| 15/3 | `ChatPacketDebugChat` | string `Message`, bool `PrintToChat` |
| 15/5 | `TellEchoPacket` | `NameData Name`, string `Message` |
| 26/4 | `CommandPacketEndDialog` | header only |
| 26/16 | `CommandPacketConfirmFriendRequest` | UInt64 `Guid`, `NameData Name`, bool `Unknown` |
| 35/16 | `PlayerUpdatePacketPlayCompositeEffect` | UInt64 `Guid`, UInt64 `Unknown2`, Int32 `CompositeEffectId`, Int32 `Unknown4`, Int32 `EffectDelay`, Vector4 `Position`, bool `Clear` |
| 35/19 | `PlayerUpdatePacketRenamePlayer` | UInt64 `Guid`, `NameData Name` |
| 35/63 | `PlayerUpdatePacketSetSynchronizedAnimations` | Int32 count, then UInt64 `Guid` + Int32 `AnimationId` pairs |
| 38/9 | `ClientUpdatePacketCollectionRemove` | Int32 `CollectionId` |
| 38/10 | `ClientUpdatePacketCollectionAddEntry` | seven Int32 fields, then bool `Collected` |
| 38/11 | `ClientUpdatePacketCollectionRemoveEntry` | Int32 `CollectionId`, Int32 `EntryId` |
| 53/10 | `PetSetNamePacket` | UInt64 `PetGuid`, string `Name`, bool `Accepted` |
| 53/11 | `PetEquipPacket` | bool `Unequip`, Int32 `Slot`, Int32 `ItemGuid` |
| 53/16 | `PetUtilityPacket` | bool `Unequip`, Int32 `PetId`, Int32 `Slot`, Int32 `ItemGuid` |
| 67/3 | `QuickChatSendChatToChannelPacket` | base `QuickChatSendChatPacketBase` (`Id`, UInt64 `Guid`, `NameData Name`), Int16 `ChatChannel`, Int32 `AreaNameId`, UInt64 `GuildGuid` |
| 74/8 | `FriendMessagePacket` | byte `FriendMessageType`, UInt64 `Guid`, `NameData Name`, `NameData NewName` |
| 112/3 | `IgnoreRemovePacket` | UInt64 `Guid` |
| 127/44 | `HousingPacketUpdateHouseInfo` | bool `InEditMode`, private Int32 `Unused`, bool `IsLocked`, bool `IsFloraAllowed`, bool `PetAutospawn`, Int32 `CurFixtureCount`, Int32 `CurLandmarkCount`, Int32 `FurnitureScore` |
| 129/17 | `GuildMemberStatusUpdatePacket` | UInt64 `GuildGuid`, UInt64 `MemberGuid`, `NameData Name`, Int32 `Role`, bool `Online`, six following Int32 fields |
| 129/18 | `GuildNameUpdatePacket` | UInt64 `Guid`, string `Name` |
| 129/23 | `GuildErrorPacket` | string `MessageName` |
| 129/27 | `GuildInviteAcceptNotificationPacket` | `NameData Name` |
| 129/28 | `GuildInviteDeclineNotificationPacket` | `NameData Name`, bool `TimedOut` |
| 129/30 | `GuildPaidRenameCheckReplyPacket` | UInt64 `Guid`, string `Name`, Int32 `Result` |
| 129/31 | `GuildPlayerStatusUpdatePacket` | UInt64 `PlayerGuid`, UInt64 `GuildGuid`, bool `IsInGuild` |
| 129/32 | `GuildCanCreateGuildPacket` | bool `CanCreateGuild` |
| 129/33 | `GuildCreateGuildPacket` | bool `CreateGuild` |
| 192/2 | `CheckNameResponsePacket` | `NameData Name`, Int32 `CheckNameResponse`, Int32 `NameChangeType`, UInt64 `Guid` |
| 192/4 | `NameChangeResponsePacket` | Int32 `NameChangeType`, UInt64 `Guid`, `NameData Name`, Int32 `ChangeNameResponse` |
| 209/2 | `AdventurersJournalQuestUpdatePacket` | Int32 count of `Dictionary<int,int>` key/value pairs |

`NameData`, Vector4, and all enum widths were checked against their C# source:
`NameData` is three Int32 IDs plus two strings, `Vector4` is four floats,
`ChatChannel` is Int16, `FriendMessageType` is byte, and the name-change enums
default to Int32. Collection and dictionary counts are bounded, duplicate
dictionary keys are rejected, trailing bytes are rejected, and malformed bools
or strings remain errors rather than observation state.

## Swift changes

- Added the 29 structs to `GatewaySimplePackets.swift` with byte-exact header
  widths (Int16 for 15/26/35/38/67/127/129/192, UInt8 for 53/74/112, Int32 for
  209) and exact C# field order.
- Added `GatewayWorldPacket` cases, dispatch, and observation fields. The
  existing opcode-35 branch (`case GatewayEntityAddition.opcode`) now carries the
  35/16, 35/19, and 35/63 cases; a second top-level opcode-35 case would be
  shadowed by that earlier branch. A fixture test caught this and now verifies
  the folded routing.
- Replaced an old test that used 127/44 as an intentionally unknown fallback:
  127/44 is now decoded exactly, and the fallback case uses 127/43 instead.
- Added three fixture tests covering all 29 packets and their observation
  fields. No script is executed, no guild or trade UI is synthesized, and no
  offline data is mixed into remote state.

## Kept raw / unresolved

These remain raw-preserving `.mapped` packets because their nested C# codecs or
conditional fields are not verified in Swift:

- `38/2` item add, `38/8` collection start, `38/21` activate profile,
  `38/25` action bar slots.
- `35/10`, `35/11` notification info; `35/39`, `35/65` customization data.
- `127/28` `PlayerHousingInstanceData`, `127/43` fixture/definition lists.
- `74/1` friend list, `74/5` positions, `74/9` friend status.
- `165/1` coin-store item definitions, `93` welcome-screen content,
  `193/2` announcements, `44/*` reference data, `102/2` lobby definitions,
  `156/3` player image data, `129/22` full guild data, and `211` check-name reply.
- Login-link packets are outside the Gateway tunnel scope of this batch.

## Limits

- This is wire-format coverage, not gameplay, UI, or Lua parity.
- The published IPA remains stale; no fresh build was produced by this change.
- Foundation-only tests after the change: **259 tests, 1 skipped, 0 failures**,
  via `TMPDIR=/tmp/opencode swift test --package-path ios
  --scratch-path /tmp/opencode/osfr-swift-test-chunks`.
- No account credential was provided, requested, captured, or stored.
