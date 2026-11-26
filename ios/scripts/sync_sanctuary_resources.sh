#!/usr/bin/env bash
# Copy Sanctuary's server data into the iOS app bundle.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$IOS_DIR/Launcher/Resources/SanctuaryResources"
SANCTUARY_DIR="${SANCTUARY_DIR:-/tmp/opencode/sanctuary}"

if [[ ! -d "$SANCTUARY_DIR/src/Resources" || ! -d "$SANCTUARY_DIR/src/Scripts" ]]; then
  echo "Sanctuary checkout not found at $SANCTUARY_DIR" >&2
  echo "Set SANCTUARY_DIR to a checkout of Open-Source-Free-Realms/Sanctuary." >&2
  exit 1
fi

mkdir -p "$DEST"
rm -rf "$DEST/Resources" "$DEST/Scripts"
cp -R "$SANCTUARY_DIR/src/Resources" "$DEST/Resources"
cp -R "$SANCTUARY_DIR/src/Scripts" "$DEST/Scripts"

python3 - "$DEST" "$SANCTUARY_DIR" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

dest = Path(sys.argv[1])
sanctuary = Path(sys.argv[2])
entries = []
for path in sorted(dest.rglob("*")):
    if path.is_file():
        rel = path.relative_to(dest).as_posix()
        data = path.read_bytes()
        entries.append({
            "path": rel,
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        })

manifest = {
    "sourceCommit": (
        __import__("subprocess")
        .check_output(["git", "-C", str(sanctuary), "rev-parse", "HEAD"], text=True)
        .strip()
    ),
    "license": "AGPL-3.0-or-later for Sanctuary's own code",
    "fileCount": len(entries),
    "totalBytes": sum(entry["size"] for entry in entries),
    "files": entries,
}
(dest / "sanctuary-resources-manifest.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
print(
    f"Synced {manifest['fileCount']} files "
    f"({manifest['totalBytes'] / 1024 ** 2:.1f} MiB) from {manifest['sourceCommit']}"
)
PY
