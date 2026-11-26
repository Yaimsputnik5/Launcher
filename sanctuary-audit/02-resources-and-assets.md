# Sanctuary audit — resources and assets

Scope: `src/Resources` (89 files, 75,332,460 bytes), `src/Scripts` (11 files, 407,618 bytes), `images` (2 files), and all references to game data from C#/Lua.

## Bottom line

All data here is **server-authoritative metadata**: item IDs, names by ID, spawn rules, quests, rewards, stores, zone grids, navmesh. There are **no renderable client assets** — no `.adr` models, textures, sounds, UI atlases, shaders, or string tables. `.adr` names in `Models.txt`/`Npcs.json` refer to the external client asset service at `http://osfr.editz.dev/assets`.

`images/logo.png` and `images/screenshot.jpg` are README-only. `Resources/Maps/FabledRealms.map` has no loader anywhere in the repo and is orphaned.

## Inventory summary

### Top-level Resources (34 files)

Largest:

| File | Bytes | Records |
|---|---:|---:|
| `ClientItemDefinitions.json` | 33,753,727 | 63,196 items |
| `CoinStoreItems.json` | 1,598,036 | 14,045 |
| `CollectionNodePools.json` | 151,238 | 46 |
| `Collections.json` | 214,604 | 165 collections / 1,010 entries |
| `CombatAbilities.json` | 6,237 | 18 |
| `CombatJobs.json` | 5,698 | 6 |
| `Consumables.json` | 32,914 | 6 arrays / 144 entries |
| `Houses.json` | 8,460 | 31 |
| `Models.txt` | 427,835 | 3,743 |
| `Mounts.json` | 20,833 | 96 |
| `NpcAmbient.json` | 11,295 | 51 |
| `NpcMovements.json` | 31,750 | 57 |
| `Npcs.json` | 858,924 | 4,562 |
| `Pets.json` | 223,431 | 160 |
| `PlayerTitles.json` | 6,840 | 90 |
| `PointOfInterests.json` | 52,391 | 150 |
| `Profiles.json` | 35,567 | 18 |
| `Quests.json` | 59,621 | 68 quests / 157 goals |
| `QuickChats.json` | 330,127 | 2,470 |
| `Rewards.json` | 17,708 | 15 tables / 79 drops |
| `StoreBundleCategories.json` | 32,824 | 187 |
| `StoreBundleCategoryGroups.json` | 18,288 | 188 |
| `StoreBundleGroups.json` | 9,078 | 8 groups / 122 entries |
| `StoreBundles.json` | 3,465,755 | 3,403 |
| `Stores.json` | 162 | 1 |
| `UnlistedClientItemDefinitions.json` | 1,853,190 | 4,135 (never loaded) |

Smaller delimited files: `CharacterCreate/*.txt` (5 files), `EquipmentSlotDefinitions.txt`, `ItemCategories.txt`, `ItemCategoryGroups.txt`, `ItemClasses.txt`, `TintGroupMappings.txt`, `NameFilter.txt` (0 bytes but required).

### Subdirectories

- `CharacterCreate/`: 5 mapping files.
- `CollectionNodeSpawns/1/`: 46 JSON files, 955 spawn records, all zone 1.
- `Maps/FabledRealms.map`: 74,796 bytes, orphaned.
- `NavMeshes/FabledRealms.navmesh`: 31,839,576 bytes.
- `Zones/FabledRealms.json`: zone 1 definition with 12 area definitions.
- `Zones/Environments/FabledRealms.json`: 15 environment names, 96×80 = 7,680 cells.

### Scripts (11 files)

- `Npc/`: `fallaway.lua`, `frostpetal.lua`, `nikki.lua`, `stormcloud.lua`, `welcomer.lua`
- `Shared/`: `BlockStanding.lua`, `EventSchedule.lua`, `GreetOnApproach.lua`
- `Zone/`: `BruceConcert.lua`, `FabledRealms.lua` (381,989 bytes; 5,282 NPC spawn calls), `HalloweenDanceOff.lua`

## Strict runtime load order

`ResourceManager.Load()` loads files in a fixed order and aborts startup on failure:

1. `NameFilter.txt`
2–6. `CharacterCreate/*.txt`
7. `Models.txt`
8. `ClientItemDefinitions.json`
9–13. collections, coins, node types, node pools, all `CollectionNodeSpawns/**/*.json`
14. cross-validation
15–17. rewards, combat abilities, combat jobs, validation
18–23. coin store items, item classes, equipment slots, categories, category groups, tint mappings
24–27. stores, bundles, bundle groups, bundle categories, category groups
28–30. zone environments, zones, pool→zone validation
31–42. houses, pets, mounts, profiles, quick chats, titles, POIs, consumables, NPCs, movements, ambient, quests, final collection validation

`ResourceManager.LoadNavMeshes()` is separate: `Resources/NavMeshes/*.navmesh`, keyed by filename.

Lua: `Scripts/Zone/<ZoneName>.lua`, `Scripts/Npc/<name>.lua`, and `require()` → `Scripts/Shared/<Name>.lua`.

No runtime loader exists for `FabledRealms.map`, `UnlistedClientItemDefinitions.json`, or `images/*`.

## Important schemas

- **Quest goals** are polymorphic by `Type`: `0` TalkToNpc (144), `1` ReachLocation (3), `2` Collect (10).
- **Rewards** are polymorphic by `RewardType`: `Item` or `Currency`, with weights and tints.
- **Consumables** is an object with 6 arrays: Boomboxes 21, Cakes 12, RandomTransformFoods 2, FoodEffects 22, Transformations 79, PartyFavors 8.
- **Zone environment** is a compact 96×80 integer grid.
- **Navmesh** is ASCII `SNAV`, `UInt32 version = 1`, then zlib-compressed DotRecast `DtMeshSet`.

## Cross-reference integrity

Clean:

- 46 collection pools ↔ 955 spawn records ↔ node types ↔ zone 1.
- 121/121 collection coins.
- Combat jobs, rewards, quests, Lua script references, and 5,282 NPC spawns all resolve.

Known dangling links to tolerate in a port:

| File | Detail |
|---|---|
| `Npcs.json` | 4 missing `ModelId`, 5 missing `ModelFileName` |
| `PointOfInterests.json` | 17 `BreadcrumbQuestId` absent from quests |
| `StoreBundleGroups.json` | 93 `StoreBundleId` absent from bundles |
| `StoreBundleCategoryGroups.json` | 5 category IDs absent |
| `CoinStoreItems.json` | 1 record with `TintGroupId = 0` |
| `QuickChats.json` | 2 invalid `ParentId` values |
| `Houses.json` | 31 houses reference zones other than the only defined zone 1 |

## iOS bundling recommendation

Bundle all 89 resource files except `Maps/FabledRealms.map`, plus all 11 scripts. Optionally include `UnlistedClientItemDefinitions.json` for a complete 67,331-item browser.

Approximate size: **73.4 MB core resources**, **75.3 MB with unlisted items**, plus 0.4 MB scripts. Navmesh decompression adds tens of MB at runtime.

Porting risks:

1. 33.75 MB item JSON will be slow as a full `Codable` graph; convert to a compact indexed binary/SQLite store at build time.
2. 31.84 MB navmesh requires a Swift DotRecast-compatible reader or precomputed waypoint graph.
3. `StoreBundles.json` and `UnlistedClientItemDefinitions.json` have UTF-8 BOMs.
4. `FabledRealms.lua` should be transpiled into a compact spawn table rather than shipping a Lua interpreter for 5,282 static calls.
5. The 3,743 model records point to missing `.adr` assets, so a native renderer needs its own asset pack or fallback art.
6. C# fails hard on missing files and some validation errors; decide whether Swift should match that strictness or tolerate the known dangling links.
