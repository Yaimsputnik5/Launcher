# Starting-zone options reload and row-list producer

This note records a concrete correction to the `StartingZone` mapping in
`15-packet-catalog-and-config-xrefs.md`. It also narrows the producer of the
`StartingZoneLoad.txt` row list. It is still **partial compiled-client
verification**, not a 1:1 gameplay reconstruction.

All Rizin observations below use the exact artifact
`ios/Launcher/Resources/ClientAssets/FreeRealms.exe`, SHA-256
`26cc1c522a45e71fb57882da515f65bac45c8c8b8c8b7e740c0cea81c52a733351`.
The Ghidra call graph is the already-exported `functions.tsv` and
`call-edges.tsv` whose digests are recorded in note 14. Rizin `pd` was used
because `pdc`/`pdf` retained no stdout on this target.

## `StartingZone` selects a resource prefix, not a transform

The earlier note correctly identified the `StartingZone` string xrefs in
`fcn.0090e8a0`, but left the argument to `0x8a9010` unnamed. The full
disassembly now resolves that argument:

| Evidence | Observation |
|---|---|
| `ev_e8a12e82f84b42f883391d97b81bfdeaa867ba0971b58473e1d806e63c714aad` | `pd 70 @ 0x0090e8a0`: after comparing stored zone `[esi+0x788]` with the incoming zone in `edi`, the client pushes one of two pointers and calls `0x8a9010`. If either the stored zone or the incoming zone is `3`, it pushes the literal `StartingZone` (`0x01804d68`); otherwise it pushes the empty string at `0x0175b400`. It then stores the incoming zone at `[esi+0x788]` and calls `HUD:SetIsInStartingZone` through `0x009046e0`. |
| `ev_19f1363c42fe06b89f4ac81aa920b4f81709d89f6ba12d42f5c1d99efe1eb8cb` | `px 48 @ 0x0175b400` shows four NUL bytes at `0x0175b400`; `Inifile` begins at `0x0175b404` and `ClientConfig.ini` at `0x0175b408`. The fallback argument is therefore an empty C string, not a zone integer or a config filename. |
| `ev_2360f5838cd51dfbe43156fab07cd29dca7d559da41b4479747ba450684d023f` | `pd 90 @ 0x008a9010`: the function frees the old options object at `[esi+0x668]`, allocates a `0x38`-byte replacement, constructs it with the client object, calls `0x00a4e450` with the pushed string, and logs `Failed to reload options manager [prefix=%s].` on failure. Its `ret 0x04` consumes exactly that one pointer argument. No position, rotation or spawn transform is computed here. |

This corrects the remaining "zone argument transform" uncertainty from note
15: `0x8a9010` receives a **resource prefix** selected from the zone transition.
The numeric zone is stored separately and converted into the HUD boolean.

## What the options reload actually loads

| Evidence | Observation |
|---|---|
| `ev_2550884a8e444cbd0b21f6ca3032baf7d5af0d78bf447d6f2c041c7956a4413f` | `pd 110 @ 0x00a4e450`: if byte `[esi+0x34]` is already set, it returns false without reloading. Otherwise it formats `Resources/%s` with the prefix through `0x00402fd0`, passes the opened resource plus `this` to `0x00a4e1f0`, then calls `0x00a4e2b0` and `0x00a4e380`, sets `[esi+0x34] = 1`, and returns true. |
| `ev_539548ee627fd6283f875a1c9511009cc95d87fd6e96753dc3469370ecc64998` | `pd` at `0x00a4e1f0`, `0x00a4e2b0` and `0x00a4e380` shows three format strings: `%sOptionElements.txt`, `%sControllerElements.txt` and `%sHelpCreditsElements.txt`. Each uses `0x00402fd0` and passes the resulting resource to `0x00a4dd70` with a destination pointer at offset `0x00`, `0x10` or `0x20` respectively. |

The prefix therefore selects real files present in the embedded client payload:

| Empty prefix | `StartingZone` prefix |
|---|---|
| `Resources/OptionElements.txt` | `Resources/StartingZoneOptionElements.txt` |
| `Resources/ControllerElements.txt` | `Resources/StartingZoneControllerElements.txt` |
| `Resources/HelpCreditsElements.txt` | `Resources/StartingZoneHelpCreditsElements.txt` |

Direct text diffs of the embedded files show the StartingZone variants are not
just copies:

- `StartingZoneOptionElements.txt` hoists the auto-refuse toggles into the main
  gameplay menu, comments out the key-bindings button, and omits the
  teletype-speed slider and the nameplate submenu present in the default file.
- `StartingZoneHelpCreditsElements.txt` removes the `options` tree button and
  comments out `teleportToSafety` and `credits`.
- `StartingZoneControllerElements.txt` enables the `dockpets` binding that is
  commented out in the default file and assigns inventory to `d6` instead of
  `d5`.

These are resource-text differences observed on disk. They do not by themselves
prove Lua dispatch semantics, and the iOS app does not yet reproduce this
zone-3 options reload.

## Producer of the `StartingZoneLoad.txt` row list

The Ghidra call graph gives `0x009cdcd0` exactly one caller, `0x009162f0`.
Rizin locates the call in that large startup function:

| Evidence | Observation |
|---|---|
| `ev_30feaaf61abd5f439012e85acc75cb08b73a17cb38f5ee8f30ffc895513a3be3` | Filtering `pd 900 @ 0x009162f0` finds one call to `0x009cdcd0`, at `0x00916aa1`. |
| `ev_cecf365f47931f3ffefbd151046f9affe734e959945c67bae1f66fdaccd9d5d3` | Context at `0x00916a40` shows `0x00916a94` pushes `0x017ed7d8`, `0x00916a9b` stores the returned object at `[esi+0x214]`, and `0x00916aa1` calls `0x009cdcd0`. |
| `ev_e776e0eb45d68086db5ffef9701de4c6c1ac404b6290e09ffe5426ef910569b4` | `px 64 @ 0x017ed7d8` reads `Resources/` followed by `Unknown`, `High`, `Medium` and `Low`. The pushed argument is the `Resources/` directory prefix. |
| `ev_fde07a9446831d2cef80acc8451b6331d57cc41b128deae29a0479659e1a8f7c` | `aaa; s 0x009162f0; pdf` completed with no retained stdout; it adds no semantics. |
| `ev_c0229246b02a4da3f0ba6ae4496b68fde4aa27e47f3a70eb5202e8d0f583845b` | `pd 220 @ 0x009162f0` shows this is a broad startup/initialization routine with many unrelated subsystem calls. |
| `ev_12e9b50a9b520b193a918392dafd3ae2e6f3999b05eafaa684af2c37ac097024` | A second `px` read confirms the same `Resources/` bytes at `0x017ed7d8`. |

Within `0x009162f0`, `[esi+0x214]` is only written at `0x00916a9b`; no later
read of that slot appears in the retained disassembly. The row-list consumer is
therefore still unresolved. What is now established is narrower: the parser is
called from startup with `Resources/`, and its returned object is stored in a
single client member.

## Boundaries

- No credential value was provided, requested, captured or stored.
- `0x0097bca0` remains localized-text expansion, not transform math.
- `BindCommandToLua` still has no direct xref under `aaa`; Lua registration and
  dispatch are unresolved.
- The four `StartingZoneLoad.txt` field names still come from the resource
  header, not from C++ symbols; no runtime effect of the parsed row object is
  claimed.
- No full 1:1 claim is made. The remaining 352-class packet catalog, nested
  packet codecs, engine material/tile fidelity and live-session parity remain
  open as recorded in notes 14–18.
