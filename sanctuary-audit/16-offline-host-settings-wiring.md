# Offline host settings: wiring audit and fixes

This note records a full audit of every user-facing setting in the SwiftUI
launcher and the fixes made after that audit. It is a behavioral parity step,
not a claim of full 1:1 reconstruction.

## Audit result

User-facing controls in `ios/Launcher/Views/` were traced through `AppState`,
`AppSettings`, `LocalSession`, `WorldSimulation`, `OSFREngine` and the UDP
services. The following are genuinely wired to behavior:

- Download parallelism/thread count, XXH64 verification and `.part` resume.
- Game locale (manifest language validation, offline world, UDP/gateway hello).
- Server add/delete/restore, manifest refresh, HTTP warning, Keychain-backed
  remember flags, gateway version and login fingerprint.
- Download/close guard (best-effort on iOS; exact C# notice text preserved).
- World tab and Join World gating: no fabricated or preloaded world instance.
- In-world move, zoom, recenter, return-to-spawn, gather, talk, travel and
  remote chat/move controls.

Two newly found defects were fixed:

### 1. Non-default starting zone used zone 1's spawn

`LocalCharacter.makeDefault` and the existing-character update in
`LocalSession.bootstrapOffline` store `LocalWorldPosition.fabledRealmsSpawn`
(zone 1). `WorldSimulation` only replaced that position when
`resolvedCharacter.zoneID != zone.id`; because the explicit `zoneID` passed by
`GamePlayerView.attach` is the *same* configured zone, the condition was false
and the player loaded at zone 1 coordinates while the grid came from the chosen
zone.

`ios/Launcher/Engine/GameWorld.swift` now resets the position to the resolved
zone's real `SpawnPosition`/`SpawnRotation` when an explicit start zone is
supplied for a non-default zone whose character still carries the zone 1
spawn. This uses only `ZoneDefinition` data from the embedded Sanctuary
resources; no coordinate is invented.

### 2. Host settings did not reach a running world

`startOfflineWorld` copied the host configuration into `ActiveWorldSession`,
and `GameEngineController.attach` built the simulation only once. Editing
profile/player name, currencies, locale, unlocks or zone while already in the
world updated the JSON but not the live engine.

The new flow is:

1. `AppState.updateHostConfiguration` replaces the active offline session
   (same session ID) with the new configuration, persists the selected
   character through `LocalSession.applyHostConfigurationToSelectedCharacter`,
   and posts `Notification.Name.osfrHostConfigurationDidChange`.
2. `GamePlayerView` observes that notification for offline sessions only and
   calls `GameEngineController.applyHostConfiguration`.
3. `WorldSimulation.applyHostConfiguration` updates the live player, profile
   name and `WorldPlayOptions` in place. A changed starting zone rebuilds the
   simulation from the same real `LocalSession`, because the zone grid is
   immutable. Remote sessions never consume host settings.

The Settings caption now states that changes apply to the running world.

### Tests

Added `EngineTests.testLiveHostConfigurationUpdatesRunningSimulation`,
`EngineTests.testNonDefaultStartingZoneUsesThatZonesSpawn` and
`LocalSessionTests.testHostConfigurationAppliesToSelectedCharacterAndPersists`.
Verification:

```text
TMPDIR=/tmp/opencode swift test --package-path ios \
  --scratch-path /tmp/opencode/osfr-swift-test-chunks
Executed 219 tests, with 1 test skipped and 0 failures
```

## Remaining gaps

- `ServerInfo.locale` is decoded/persisted but unused; the global
  `settings.locale` is authoritative. It is not exposed in the UI.
- Starting coins/station cash change the HUD value but there is no economy
  simulation that spends them.
- Unlock-all profiles/titles change the offered ID list but there is no
  selection UI; unlock-all tiles genuinely changes walkability and click
  routing.
- The bundled zone catalog currently contains only `FabledRealms` (zone 1), so
  the zone picker has one valid choice even though the wiring is now correct.
- SwiftUI/UIKit files are excluded from the Linux test target. Their compiler
  verification still requires the macOS GitHub Actions runner.
- Compiled-client parity for these settings remains partial: the REA evidence
  in note 15 proves the shipped client reads `StartingZone`, `PlayerName` and
  `ProfileName`, but the exact native spawn, currency and unlock algorithms are
  not fully decompiled.

This is still a source-backed native port with partial compiled-client
verification, not a completed 1:1 port.
