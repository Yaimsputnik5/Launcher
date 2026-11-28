# World asset pipeline and full-client evidence

This note folds the completed full-client evidence passes into concrete native
code and tests. It does **not** claim full 1:1 parity. It records what was
implemented, what was verified against the real local client, and what remains
unresolved.

## Full-client inventory

Read-only inventory of
`/home/deadptr/.local/share/OSFRLauncher/Servers/OSFR Public Server/Client`:

| Measure | Value |
|---|---:|
| Regular files | 1,819 |
| Directories | 39 |
| Total bytes | 1,229,484,889 |
| Unique SHA-256 digests | 1,673 |
| Duplicate groups | 18 |
| Redundant files | 146 |

A complete per-file TSV is preserved at
`sanctuary-audit/39-full-client-files.tsv` with relative path, size, SHA-256,
extension, and signature. The 22 `Logs/`
files (245,059 bytes) are runtime artifacts and are excluded from the
payload-only totals below.

Payload-only tree: 1,797 files / 1,229,239,830 bytes.

### File classes

| Signature / area | Count |
|---|---:|
| `.fxo` compiled shaders | 715 |
| text or ASCII | 412 |
| UTF-8 BOM text | 202 |
| other binary | 169 |
| TGA type 2 | 119 |
| DDS | 51 |
| PE/MZ | 40 |
| Windows cursor | 38 |
| PNG | 29 |
| TrueType/OpenType | 14 |
| GCK2 | 9 |
| GCNK | 9 |
| Qt RCC | 6 |
| Scaleform CFX | 2 |
| Lua bytecode | 1 |
| GZNE | 1 |

Top-level areas: `tcg/` 190 files / 159,831,738 bytes, `assets/` 2 /
64,615,474, `locale/` 8 / 44,132,954, `UI/` 425 / 22,161,520, `Resources/`
340 / 15,289,396, `Shaders/` 715 / 12,655,044, `custom/` 26 / 11,478,973.

`UI/UiModules/Main/` contains 267 `wnd*.xml` screens. `Shaders/NoLight/`
contains 269 `.fxo` files. The 715 `.fxo` files start with `01 09 FF FE` plus
an unresolved `u32`; zlib decompression of the tail failed. Their bytecode
meaning remains unresolved.

### Manifests, packs, and locale tables

Three comma-delimited manifests use `name,crc32,size`:

| Manifest | Rows | Declared size sum |
|---|---:|---:|
| `Assets_manifest.txt` | 162,652 | 4,099,796,755 |
| `assets/assetpack000_manifest.txt` | 9,756 | 489,469,125 |
| `tcg/AssetsTcg_manifest.txt` | 58 | 87,193,879 |

A direct crosswalk against all 13 pack indexes:

| Manifest | Rows | Exact names | Exact CRC | Exact size | After stripping `.z` | CRC after stripping | Size after stripping |
|---|---:|---:|---:|---:|---:|---:|---:|
| `Assets_manifest.txt` | 162,652 | 1,498 | 1,498 | 1,498 | 66,649 | 66,647 | 1,498 |
| `assets/assetpack000_manifest.txt` | 9,756 | 1,835 | 1,835 | 1,835 | 2,128 | 2,128 | 1,835 |
| `tcg/AssetsTcg_manifest.txt` | 58 | 0 | 0 | 0 | 0 | 0 | 0 |

Exact non-`.z` names match perfectly: 3,333 / 3,333 rows agree with pack CRC
and size. After stripping `.z`, the manifest `size` field no longer matches
the stored payload, confirming it records the delivered compressed size. CRC
agrees for 66,647 / 66,649 main rows and 2,128 / 2,128 assetpack rows. The two
exceptions are:

| Pack entry | Pack | Pack bytes | Pack CRC | Manifest row | Manifest CRC | Manifest size |
|---|---|---:|---:|---|---:|---:|
| `FabledRealmsAreas.xml` | `Assets_000.pack` | 563,796 | 1,790,632,247 | `FabledRealmsAreas.xml.z` | 1,689,797,938 | 32,468 |
| `ActorSoundEmitterDefinitions.xml` | `Assets_003.pack` | 2,608,086 | 3,854,020,472 | `ActorSoundEmitterDefinitions.xml.z` | 1,405,558,202 | 126,778 |

Both also have loose copies under `custom/`. The manifest CRC is likely over
the compressed `.z` bytes for those two rows, but that is an inference, not
observed decompression evidence.

All 13 `.pack` files were indexed: 68,777 unique names, 0 CRC-32 mismatches,
877,633,987 payload bytes, 3,863,778 bytes of directory overhead. The two
world packs now available locally contain:

| Pack | Entries | Payload bytes |
|---|---:|---:|
| `AssetsW_000.pack` | 2,566 | 199,876,934 |
| `AssetsW_001.pack` | 2,385 | 126,203,986 |

Dominant world-pack extensions are `.dds`, `.dme`, `.gr2`, `.mp3`, `.cdt`, and
`.gcnk`. The older `assets/assetpack000W_000.pack` is a different legacy
archive with 2,128 mostly-PNG entries.

Locale indexes use `.dir` rows `cid<TAB>length<TAB>offset<TAB>type` and `.dat`
rows `cid<TAB>type<TAB>text`. The en_US table declares 113,286 rows.

### Scripts and XML

`UI/ScriptsBase.bin` is a Lua 5.1 bytecode container with 216 root protos,
5,057 functions, 4,818 reconstructed names, and the previously decoded
`HUD.StartingZoneLoaded` callback. The four verified `StartingZoneLoad.txt`
rows remain the same; only row 10 has a callback. The three non-stub asset
lists referenced by that table are absent from the local tree.

There are 381 loose `.xml` files; 294 parse as strict XML and 87 are custom or
multi-root fragments. Sample root tags include `Window` (266), `Pipeline` (8),
`MaterialInfo` (6), `RenderTargets` (3), and `Lights` (3).

## Executable entry and call graph

`FreeRealms.exe` is PE32 x86, GUI subsystem, image base `0x00400000`, 25,067,520
bytes, SHA-256
`26cc1c522a45e71fb57882da515f65bac45c8c8b8c8b7e740c0cea81c52a733351`.

The read-only entry chain is:

- `0x00d83687`: `___security_init_cookie`, then jump to `0x00d834a7`;
- `0x00d834a7`: `___tmainCRTStartup`;
- `0x00403340`: application body with 36 direct callees.

Existing read-only Ghidra exports contain 153,421 function records (876
thunks) and 273,001 call edges. BFS from the PE entry reaches 3,476 nodes at
maximum depth 26. Imports total 411 across 13 DLLs plus 4 delay imports; there
are 201 exports. RTTI classification found 4,918 names, of which 1,333 remain
unclassified.

Config anchors include `ClientConfig.ini` `0x0175b40c`,
`ClientConfigOverride.ini` `0x0175b398`, `UserOptions.ini` `0x0175b370`,
`%sStartingZoneLoad.txt` `0x01810194`, `LuaCall` `0x01813f88`, and
`BindCommandToLua` `0x0180b17c`.

REA limitations are unchanged: Hopper bridge startup timed out, and the REA
Ghidra provider rejects installed Ghidra 12.2 (it accepts 12.1.x). The
entry/call map therefore uses the existing read-only Ghidra exports and local
headless fallbacks. Static immediate references for config strings are labeled
heuristic; they are not proven reference-manager xrefs. No executable was run.

## Implemented native pipeline

1. `ios/scripts/fetch_client_payload.py` now accepts `IOS_CLIENT_LOCAL_DIR`.
   It hashes the local client tree, stages only files absent from the public
   CDN manifest, writes them atomically, verifies XXH64, and records them in
   `client-assets-index.json` with a `localSource` field. It never reads or
   executes `FreeRealms.exe` as code.
2. `ios/Launcher/Services/WorldAssetCatalog.swift` parses the three
   comma-delimited manifests with byte-level CRLF handling, bounds checks,
   unsafe-path rejection, and duplicate counting. It indexes the chained
   directories of all 13 packs with `FileHandle`, reads individual payloads by
   offset, verifies pack CRC-32 for every payload, and never loads an entire
   200 MB pack into memory. Manifest CRC-32 is also enforced when the manifest
   name exactly equals the pack name (verified 3,333 / 3,333 in the real
   crosswalk). For `.z` rows resolved to a stripped pack name, a CRC difference
   is exposed through `compressedManifestCRCDisagreement(for:)` instead of
   rejecting a valid pack payload.
3. `TextureLoader` now treats a manifest name such as
   `img10888699995024875749.dds.z` as a lookup through `WorldAssetCatalog`.
   The stored pack payload is passed to the existing DDS/TGA/PNG decoder. An
   exact-name manifest/pack CRC disagreement is an explicit error, not a
   fallback.
4. `Package.swift` and `Launcher.xcodeproj/project.pbxproj` include the new
   service so both Linux tests and the Xcode app build see the same code.

### Verification

Local staging was run against the complete local client tree:

```text
Local source: 9 supplemental file(s), 320.3 MiB
Done: 0 downloaded, 1788 cached, 9 local staged, 0 local cached, 0 failed
fileCount 1797 totalBytes 1229239830
```

The opt-in acceptance test
`WorldAssetCatalogTests.testRealClientCatalogSmoke` passed with
`OSFR_LOCAL_CLIENT_DIR` set: it parsed 162,652 manifest rows, indexed 68,777
pack records, decoded a real `FabledRealms_BlacksporeCave_Tile_*.dds.z` pack
payload to a valid DDS header, and resolved both compressed-CRC exception XML
rows with a diagnostic disagreement.

The full Foundation-only suite passes: **267 tests, 2 skipped, 0 failures**
without `OSFR_LOCAL_CLIENT_DIR`; with the local smoke source set, 267 tests,
1 skipped, 0 failures.

## Still unresolved

- The CDN returns 404 for `AssetsW_000.pack`, `AssetsW_001.pack`, and
  `Assets_manifest.txt`. CI cannot fetch a complete payload from the public
  manifest; a maintainer-controlled source or release asset is still required.
- Git ignores the payload directory, and a 200 MB file cannot be committed as
  a normal GitHub blob. The local staged payload is therefore not in the
  pushed source tree.
- Loose `.z` files not present in a pack are reported as not found. Their
  compression/runtime semantics were not exercised. The two compressed-CRC
  exception rows are resolved from their verified pack payloads, but the
  manifest CRC is only diagnosed; no `.z` decompressor is claimed.
- `StartingZoneName` resolves to string ID `427651`, but no shipped locale or
  scanned client data supplies that value.
- The three non-stub starting-zone asset lists are absent locally.
- FXO shaders, Granny/DME/CDT geometry, GCNK/GCK2 semantics, locale runtime
  use, TCG rules, audio, Lua execution, and 267 UI modules remain outside the
  implemented native surface.
- The published IPA is still stale; no fresh IPA has been verified from this
  source, and no physical device test has been performed.

This note is an evidence and implementation record, not a 1:1 completion
claim.
