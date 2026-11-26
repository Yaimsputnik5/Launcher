# Sanctuary audit — game logic, zones, entities, and scripts

Scope: `Sanctuary.Game` (194 files / 21,607 C# lines), `Sanctuary.Scripting` (11 files / 816 C# lines), `Sanctuary.Game.Tests` (18 files / 2,807 C# lines), `Sanctuary.Scripting.Tests` (5 files / 253 C# lines), and `src/Scripts` (11 Lua files / 6,140 lines). Audited at commit `f5240b7554f2a80d6b815cb7ead7ffee12499565`; no files were modified.

## Domain model

Root services:

- `ZoneManager` / `IZoneManager`: zone lifecycle and player transfers.
- `ResourceManager` / `IResourceManager`: all static data plus hot reload.
- `RewardManager`, `ChatCommandManager`, `InteractionManager`, `TradeManager`, `TradeSettlement`, `QuestManager`.

Zones:

- `BaseZone`: 10 Hz and 1 Hz loops, tile generation, visibility, NPC/player lifecycle, reference-data packets.
- `WorldZone`: areas, points of interest, seasonal client areas, adventurer's journal blob.
- `CombatZone`: empty `BaseZone` subclass.
- `HousingZone`: `BaseZone` plus shop data; entry is broken because `PlayerOwnsHouse` throws `NotImplementedException`.
- `ZoneTile`: `(Longitude, Latitude, EnvironmentId)` with Morton hash and `VisibleTileRadius = 2`.

Entities:

- `Player` is the central 1,829-line aggregate: connection, routines, zone/tile, visible sets, portrait, POI, teleport, admin/mod/mute, profiles, mounts, pets, friends, ignores, guild, quests, chat channels, collections, cooldowns, effects, equipment, toolbar, and delayed packet heaps.
- `Npc` includes identity, appearance, interactions, routine manager, Lua bridge, movement/ambient controllers, path following, throttled position updates, effects, say/animation/collidable/speed/heading/remove.
- `PlayerPet` is a 1,587-line state machine for follow, roam, idle, notice, investigate, treasure, dig, groom, feed, trick, dance, shake, rest, and care.
- `Mount`, `CollectionNode`, `CollectionCoin`, `PetTreasureChest`, `PlayerEffect`, `OneTimeNotification`, `PetTrait`, `RelayedPosition`, `NpcAmbientController`, and `NpcMovementController`.

Routines: `Routine`, `RoutineManager`, `SequentialRoutine`, `ParallelRoutine`, `RepeatRoutine`, `PeriodicRoutine`, `DelayedRoutine`, `DelegateRoutine`, `InstantRoutine`, `TimeoutRoutine`, `WaitRoutine`.

Pathing: SNAV v1 zlib loader, `Pathfinder`, `PathFollower`, `NavPath`, `ChaseSettings`, Recast helpers.

Resource collections and definition POCOs cover every JSON/TXT file in `src/Resources`; see `02-resources-and-assets.md`.

Helpers cover boomboxes, chat, effects, entities, game time, interaction menus, item definitions, pets, positions, profiles, projectiles, resource validation, trade rules, and welcome screens.

Interactions include add/remove friend, ignore/unignore, guild invite, inspect, merchant, atlas, snowball, and trade. Static IDs are assigned in type initialization order; merchant is 17 and snowball is 33.

## Zone lifecycle and visibility

`ZoneManager.Load()` creates only starting zone definition 1. Zones are keyed by `(definitionId, ownerId)`. `TryGetOrCreateZoneInstance` calls `OnStart()` once per instance.

`BaseZone.OnStart()` starts two long-running tasks with `PeriodicTimer`:

- 10 Hz tick: collection-node refills → routines → every entity's `UpdateEveryTick`.
- 1 Hz tick: every entity's `UpdateEverySecond` → virtual update → Lua `"second"`.

`OnStart` also fires Lua `"start"` and activates collection-node pools. `Dispose` cancels both loops, waits for tasks, cancels routines, disposes NPCs, clears players, and deletes the script context.

Tiles cover the zone's longitude/latitude range. `VisibleTileRadius = 2`; `AddEntityToZoneTiles` and `RemoveEntityFromZoneTiles` maintain symmetric `VisibleNpcs` / `VisiblePlayers` sets, with mount suppression.

`WorldZone` area lookup order: tile map → circle/rectangle/polygon shapes → environment plus X range. Client areas (base + active seasonal + script-enabled) are re-sent to every player every 3 seconds.

## Player, combat, movement, and inventory

Server does **not** simulate damage. On client ready it sends hardcoded `Hitpoints 2500/2500`, `Mana 100/100`, and a `CharacterStat` table including weapon range 5, mana regen 4, melee interval 2000 ms, and in-combat regen 6/4. Equipment in slot 7 resolves basic/special abilities through `JobKitDefinition`; energy emits mana updates. Snowball is the only server-driven ability, using a temporary NPC ability, target validation, projectile timing, and failure string 3079.

NPC movement speed is 6.25; position updates are throttled at 4 Hz, followers at 2 Hz. `NpcMovementController` supports wander, patrol, and flee. `NpcAmbientController` drives animation, conversation groups (radius 6), idle animations, and look-at. `Player.Teleport` uses a 4-step sequence with a 3-second wait; POI changes settle after 1.5 seconds.

Inventory is client-authoritative `ClientPcData`; the server validates IDs and tints, resolves equipped items and attachments, and grants default/special profile items through `ProfileHelper`.

## Quests, collections, and rewards

`QuestManager` implements offer (750 ms delay), accept, talk/collect/reach goals, dialogue choices, scenes, turn-in (30 s pending timeout), rewards, persistence, journal restore, and notification/objective updates. Goal types: `TalkToNpcGoal`, `CollectGoal`, `ReachLocationGoal`.

Collection pools reconcile active counts and spawn selection. Completed nodes enqueue refills due after `RespawnSeconds`; refills are processed on the 10 Hz tick. Collection coins are reserved per player and hidden after collection.

`RewardManager` rolls weighted item/currency drops, skips already-owned rewards, picks tints, writes DB items, sends item/mount/pet/currency packets, and shows reward toasts. Station Cash is not granted.

## Trade, chat, and social

`TradeManager` has a 60-second invitation lifetime and a revision-token state machine for invite, reply, lock, accept, offers, review, settle, and publish. `TradeSettlement` retries transactions with fresh contexts, orders character rows by ID to avoid deadlocks, merges stacks, preserves/allocates item IDs, and reloads clients after commit.

17 chat commands: `help`, `whereami`, `zone`, `navnpcto`, `reward`, `teleport`, `mod`, `admin`, `quest`, `collection`, `scale`, `fx`, `mount`, `npc`, `script`, `oob`, plus internal aliases. Roles: Player=0, Mod=1, Admin=2. Failed permission checks return “You do not have permission to use this command.”

Friend/ignore/guild interactions, inspect, merchant, atlas, and snowball are implemented against DB state and packets.

## Timers and transitions

- Zone tick: 100 ms; second tick: 1 s.
- Client areas refreshed every 3 s.
- Quest offer delay 750 ms; abandon blocked for 3 s after accept; pending turn-in timeout 30 s; scene line delay 10 s after a 2 s start delay.
- Trade invitation 60 s; maintenance sweep 1 Hz.
- NPC position throttle 250 ms; followers 500 ms; chase settings include 0.5 m range, 1.5 m lose range, π/2 arc, 0.2 s cadence, 2 Hz updates.
- Pet timings include feed 6 s, grooming 25 s, roam 3.8–5.3 s then 2–4 s, idle 30–60 s, stay 15–40 s, treasure 15–50 s, dig 4 s, chest cooldown 8 h, chest lifetime 60 s, notice 45–90 s, and care updates 1.5 s.
- Bruce concert: 2 h cycle with Gathering (5 min), Playing (181 s), and Gone phases.
- Halloween dance-off: 30 min interval, 2 min kickoff, seasonal gate, six rounds with 12 NPCs and timed banter/walk/dance/stop/return phases.

## Lua integration

`ScriptRuntime` creates one `LuaState` per zone, with standard libraries, a shared module loader, and a semaphore. Zones and NPCs get separate `ScriptContext`s exposing `print`, `registerCallback`, and `unregisterCallback`.

Zone userdata API: `id`, `name`, `spawnNpc`, `spawnFixedNpc`, `setClientAreaEnabled`, `broadcast`, `broadcastNear`, `isSeasonActive`.

NPC userdata API: `guid`, `name`, `zone`, `position`, `isMoving`, `say`, `sayLocalized`, `moveTo`, `getNearbyPlayers`, `getPlayersOnTop`, `playAnimation`, `setCollidable`, `setBaseAnimation`, `addEffectTag`, `removeEffectTag`, `playEffect`, `setHeading`, `setSpeed`, `remove`.

`FabledRealms.lua` contains one static spawn function with 5,282 `spawnNpc`/`spawnFixedNpc` calls. Event scripts implement Bruce concert and Halloween dance-off. Five NPC scripts implement standing-block and greet-on-approach behavior via shared Lua modules.

Callbacks are fire-and-forget; exceptions are logged, not propagated. `!script reload` reloads all scripts.

## Executable specification

The 108 tests in `Sanctuary.Game.Tests` and `Sanctuary.Scripting.Tests` are the behavioral specification for a Swift port. They lock down:

- Geometry helpers and collection/node/coin rules.
- Weighted drop selection boundaries and pool spawn selection/exclusion/fallback.
- Cross-resource validation and watcher-aware reload.
- Quest log/progress/conversation/definition/goal semantics.
- Complete trade wire layout and settlement isolation.
- Every zone and NPC Lua script's API surface.

Preserve method names, JSON layouts, packet field order, and timing thresholds when porting.

## Gaps and quirks

- `PlayerOwnsHouse` throws; housing cannot be entered.
- Unknown `ZoneAreaShape` throws.
- Combat is client-authoritative; no server damage exists.
- `Npc.TeleportToZone` returns true without moving; only `Mount` overrides it.
- Script callbacks are fire-and-forget.
- `EffectsChatCommand` class name does not match `FxChatCommand.cs`.
- `CollectionChatCommand` usage says `!admin collection` although keyword is `!collection`.
