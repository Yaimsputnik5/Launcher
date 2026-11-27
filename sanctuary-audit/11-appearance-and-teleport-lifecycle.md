# Player appearance and teleport lifecycle parity

This note records the source-backed reconstruction of the remaining
server-to-client entity lifecycle packets and the exact teleport handshake.
Authority: `/tmp/opencode/sanctuary/src` at commit
`f5240b7554f2a80d6b815cb7ead7ffee12499565`. Line numbers below refer to that
tree. The Swift implementation is in
`ios/Launcher/Services/GatewayProtocol.swift`,
`ios/Launcher/AppState.swift` and
`ios/Launcher/Views/GamePlayerView.swift`.

## Opcode 35 sub-opcode inventory

`Sanctuary.Packet/BasePlayerUpdatePacket.cs:5-31` writes `int16 35` followed by
`int16 subOpCode`. Canonical names are in
`Sanctuary.Packet.Common/Extensions/PacketReaderExtensions.cs:208-279`. There
are 71 declared sub-opcodes, but C# only ships serializers for a subset. The
native client port must not invent layouts for name-only entries. Implemented
in Swift before this pass: 1, 2, 3, 13, 20, 37. Added by this pass: 6, 7, 14,
15, 31, 61. Sub-opcodes 33 and 34 are client-to-server only; the rest either
remain unparsed or have no authoritative wire layout in the audited source.

## Equipment / appearance

`CharacterAttachmentData`
(`Sanctuary.Packet.Common/CharacterAttachmentData.cs:5-22`) is three Int32-prefixed
UTF-8 strings followed by `int32 TintId`, `int32 CompositeEffectId` and
`int32 Slot`.

| Sub | Packet | Exact payload after `35, sub` |
|---:|---|---|
| 6 | `PlayerUpdatePacketEquipItemChange.cs:6-45` | `u64 Guid`, `int32 Id`, attachment, `int32 ProfileId`, `int32 ItemClassId`, `int32 WieldType` |
| 7 | `PlayerUpdatePacketEquippedItemsChange.cs:8-35` | `u64 Guid`, `int32 count`, `count × attachment`, `int32 Unknown` |
| 14 | `PlayerUpdatePacketUpdateTemporaryAppearance.cs:5-28` | `int32 TemporaryAppearance`, `u64 Guid` (int deliberately precedes GUID) |
| 15 | `PlayerUpdatePacketRemoveTemporaryAppearance.cs:5-28` | `u64 Guid`, `int32 Unused` |
| 31 | `PlayerUpdatePacketSlotCompositeEffectOverride.cs:5-30` | `u64 Guid`, `int32 Slot`, `int32 CompositeEffect` |
| 61 | `PlayerUpdatePacketUpdateActiveWieldType.cs:5-27` | `u64 Guid`, `int32 WieldType` |

Server emission sites confirm these are server-only S→C updates:

- Equip/unequip:
  `Sanctuary.Gateway/Handlers/BaseInventoryPacket/InventoryPacketEquipByGuidHandler.cs:170-184`,
  `InventoryPacketEquipByItemRecordHandler.cs:167-181`,
  `InventoryPacketEquippedRemoveHandler.cs:132-145`.
- Pet attachments: `Sanctuary.Game/Helpers/PetHelper.cs:353-377`.
- Profile switch:
  `Sanctuary.Gateway/Handlers/BaseCommandPacket/CommandPacketSetProfileHandler.cs:62-68`.
- Temporary appearance: `Sanctuary.Game/Entities/Player.cs:1375-1397`,
  `1482-1494`, `1544-1551`, `460-465`, `797-798`.
- Weapon flair: `Sanctuary.Game/Entities/Player.cs:43-44`, `1231-1257`.
- Wield stance: `Sanctuary.Game/Entities/Player.cs:1201-1229` and
  `Sanctuary.Gateway/Helpers/OutfitGestureHelper.cs:73-89`.

Swift now stores equipment keyed by GUID and slot. Empty model-name attachments
clear that slot (the unequip case), sub 7 replaces the full list, sub 14/15
override/restore temporary appearance, sub 31 sets or clears a slot flair, and
sub 61 records the active stance. None of these packets fabricates a spawn,
name, or position for an entity the client has not already seen.

Standalone opcode 38 self-confirmations (`38/5`, `38/6`, `38/21`) are also
server-only and remain outside the remote marker view because they describe the
local player's inventory/profile rather than another entity's marker.

## Teleport handshake

There is no literal TeleportBegin/Confirm/Complete packet in Sanctuary. The
wire phases are:

1. `PacketClientBeginZoning` (opcode 31),
   `Sanctuary.Packet/PacketClientBeginZoning.cs:7-61`: `string Name`,
   `int32 Type`, full `Vector4 Position`, full `Quaternion Rotation`,
   `string Sky`, `bool Tutorial`, `u8 TeleportSequence`, `int32 Id`,
   `float UpdateRadius`, `int32 GeometryId`,
   `bool OverrideUpdateRadius`, `bool WaitForZoneReadyPacket`.
2. `ClientUpdatePacketUpdateLocation` (38/12),
   `Sanctuary.Packet/BaseClientUpdatePacket/ClientUpdatePacketUpdateLocation.cs:7-34`:
   full position (16 bytes), full rotation (16 bytes), `bool Teleport`,
   `u8 TeleportSequence`.
3. The client confirms by sending the same sequence in opcode 125
   (`PlayerUpdatePacketUpdatePosition.cs:8-67`) or 164
   (`PlayerUpdatePacketJump.cs:8-74`). Both are 36/40 bytes with the sequence
   at the end.
4. `PacketClientIsReady` (13) and `PacketClientFinishedLoading` (10) complete
   the zone-load handshake; the server answers 14 and 38/26.

`Sanctuary.Game/Entities/Player.cs:52-54` defines `TeleportSequenceCount = 4`.
`BeginTeleport()` at lines 841-855 increments modulo 4 (1, 2, 3, 0, …).
`TryAcceptTeleportSequence(byte)` at lines 857-870 drops mismatched movement,
consumes the matching packet as confirmation without relaying it, and restores
normal sequence 0 afterward. Inbound handlers
`PlayerUpdatePacketUpdatePositionHandler.cs:26-48` and
`PlayerUpdatePacketJumpHandler.cs:22-42` call it before applying movement.

Swift applies opcodes 31 and 38/12 to the known self position only, records the
expected sequence in `GatewayWorldObservation.ownTeleportSequence`, and the
movement/jump UI sends that sequence. `AppState.consumeTeleportSequence()` is
called only after the packet is queued successfully, so the next movement
returns to sequence 0 exactly once.

Client-origin teleport requests remain source-backed but are not synthesized by
the app: 90 (`PacketZoneTeleportRequest`, `int32 Id`), 122
(`PacketZoneSafeTeleportRequest`, opcode only — the declared `Id` is never
read), and 58 (`PacketWorldTeleportRequest`, `u64 FriendGuid`).

## Verification

`ios/Tests/OSFRCoreTests/GatewayAppearanceTeleportTests.swift` builds every
fixture from `PacketWriter` in the audited field order and covers:

- single-slot equip and empty-model unequip;
- whole-list replacement;
- sub 14's unusual int-before-GUID order and sub 15 removal;
- sub 31 flair set/clear and sub 61 wield stance;
- opcode 31 begin-zoning field order and expected sequence;
- opcode 38/12 teleport snap, stale-scale clearing, and no fabricated entity.

Linux core result after this pass: 193 tests, 1 skipped, 0 failures. SwiftUI,
UIKit, Metal, and UDP socket paths are still compiled only by the iOS target.
