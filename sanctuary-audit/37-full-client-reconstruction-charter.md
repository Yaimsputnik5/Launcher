# Full-client reconstruction charter

This note records the scope and evidence rules for the requested complete native
Swift port. It does **not** claim that the port is complete. It defines what must
be true before a 1:1 claim is allowed.

## Target inventory

Read-only inventory of
`/home/deadptr/.local/share/OSFRLauncher/Servers/OSFR Public Server/Client`:

| Measure | Value |
|---|---:|
| Regular files | 1,819 |
| Directories | 38 |
| Total bytes | 1,229,484,889 |

The target now includes the full world packs that were absent from earlier
staging:

- `AssetsW_000.pack` — 190.73 MiB
- `AssetsW_001.pack` — 120.47 MiB
- `assets/assetpack000W_000.pack` — 61.13 MiB

Other large inputs include `Assets_000.pack` through `Assets_009.pack`,
`tcg/cards.rcc`, `locale/*_data.dat`, `UI/ScriptsBase.bin`, 715 `.fxo` shaders,
381 `.xml` files, 150 `.txt` files, 134 `.cln` files, 120 `.tga` files, and
29 DLLs.

`FreeRealms.exe` remains PE32 x86, 25,067,520 bytes, SHA-256
`26cc1c522a45e71fb57882da515f65bac45c8c8b8c8b7e740c0cea81c52a733351`.

## REA provider state

The REA session confirms the executable identity and reports these relevant
provider conditions:

- Hopper is available and selected for the PE x86 target, but bridge startup
  timed out with empty stdout and loader/launcher diagnostics; no new Hopper
  procedure result was accepted from that attempt.
- Ghidra is target-compatible but unavailable in REA because the installed
  version is 12.2 while the provider accepts 12.1.x.
- The existing read-only Ghidra export remains the practical source for the
  large function/call inventory; direct headless instruction dumps are used as
  a fallback when the provider cannot run.
- No Windows executable was run. No Wine, DirectX, `dotnet`, or iOS process
  execution was used. No account credential was requested, accepted, stored, or
  repeated.

The user's Sony authorization statement is treated only as project context. It
is not presented here as independently verified public evidence.

## Reconstruction rule

“Nothing excluded” means every target element is classified into exactly one
visible outcome:

1. **Implemented natively** — behavior has artifact evidence and Swift tests.
2. **Native substitute** — Windows-only capability is replaced with an
   equivalent that works in iOS sandbox constraints; the rationale is recorded.
3. **Raw-preserving** — bytes are retained and bounded, but inner semantics are
   unresolved and the packet is not presented as decoded content.
4. **Deferred obligation** — the element is understood well enough to describe
   but not yet implemented; it remains in the backlog with an owner test.
5. **Not applicable on iOS** — only when the reason is concrete, for example
   loading a Windows kernel driver or executing the Windows PE. Hiding a feature
   under this label is not allowed.

A file, function, packet, script, or feature may not silently disappear between
these categories.

## Active evidence passes

Four read-only passes were started:

- full client-tree inventory and manifest/pack schema map;
- executable entry-point, import, RTTI, vtable, and call-graph map;
- `ScriptsBase.bin`, asset-list, pack-index, locale-index, and XML schema
  recovery;
- iOS implementation gap ledger against the full target tree.

Their outputs will be folded into code, tests, and later audit notes. Until then,
this note is a charter, not a completion claim.

## Acceptance conditions before any 1:1 claim

- Every file in the client tree is classified and counted.
- Every recovered packet format is exact-decoded or explicitly raw-preserving;
  no guessed nested serializer is interpreted.
- Every recovered script path is either represented natively or recorded as an
  unresolved obligation; no Lua execution is claimed.
- Every setting demonstrably changes behavior.
- Remote sessions remain packet-only; offline simulation never leaks into them.
- The Foundation-only suite passes, and SwiftUI/Metal/Network code is compiled
  by a successful macOS Actions run.
- A fresh IPA is verified by head SHA, `unzip -tq`, size, and SHA-256 before any
  release claim.
- A physical device retest confirms runtime behavior; this host has no iOS
  device.

## Current limits

The published `ios-ipa` asset remains stale. No fresh IPA has been verified from
the current source. Broad live-session parity, full engine/material fidelity,
all Lua/gameplay semantics, and complete compiled-client reconstruction remain
unresolved. This charter does not change those facts.
