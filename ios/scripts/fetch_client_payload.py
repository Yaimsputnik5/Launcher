#!/usr/bin/env python3
"""Download and verify the original Free Realms client payload for iOS bundling.

Files are placed in ios/Launcher/Resources/ClientAssets, preserving the paths
from clientmanifest.xml. Existing files are verified with XXH64 and skipped when
current. Verification is performed before an atomic replace, so an interrupted
download never produces a partially installed asset.

Environment:
  IOS_CLIENT_MANIFEST_URL   manifest URL (default OSFR manifest)
  IOS_CLIENT_BASE_URL       asset base URL (default OSFR client CDN)
  IOS_CLIENT_DEST           destination directory
  IOS_CLIENT_WORKERS        concurrent downloads (default 8)
  IOS_CLIENT_LIMIT          download only the first N files (testing)
  IOS_CLIENT_FILTER         download only paths starting with this prefix
  IOS_CLIENT_LOCAL_DIR      optional full local client tree; files not present
                            in the remote manifest are staged and indexed too
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

MASK = 0xFFFFFFFFFFFFFFFF
P1 = 11400714785074694791
P2 = 14029467366897019727
P3 = 1609587929392839161
P4 = 9650029242287828579
P5 = 2870177450012600261

DEFAULT_MANIFEST = "https://opensourcefreerealms.com/clientmanifest.xml"
DEFAULT_BASE = "https://opensourcefreerealms.com/client"


def mask(value: int) -> int:
    return value & MASK


def rotl(value: int, amount: int) -> int:
    value = mask(value)
    return mask((value << amount) | (value >> (64 - amount)))


def round_acc(acc: int, value: int) -> int:
    return mask(rotl(mask(acc + mask(value * P2)), 31) * P1)


def merge_round(acc: int, value: int) -> int:
    return mask(mask((acc ^ round_acc(0, value)) * P1) + P4)


def read_u64(chunk: bytes, offset: int) -> int:
    return int.from_bytes(chunk[offset : offset + 8], "little", signed=False)


def read_u32(chunk: bytes, offset: int) -> int:
    return int.from_bytes(chunk[offset : offset + 4], "little", signed=False)


class XXH64:
    """Streaming XXH64 with the same seed semantics as the Swift launcher."""

    def __init__(self, seed: int = 0) -> None:
        self.seed = seed & MASK
        self.total = 0
        self.mem = bytearray()
        self.v1 = mask(self.seed + P1 + P2)
        self.v2 = mask(self.seed + P2)
        self.v3 = self.seed
        self.v4 = mask(self.seed - P1)

    def update(self, data: bytes) -> None:
        if not data:
            return
        self.total += len(data)
        self.mem.extend(data)

        if len(self.mem) >= 32:
            block_count = len(self.mem) // 32
            for index in range(block_count):
                offset = index * 32
                self.v1 = round_acc(self.v1, read_u64(self.mem, offset))
                self.v2 = round_acc(self.v2, read_u64(self.mem, offset + 8))
                self.v3 = round_acc(self.v3, read_u64(self.mem, offset + 16))
                self.v4 = round_acc(self.v4, read_u64(self.mem, offset + 24))
            del self.mem[: block_count * 32]

    def digest(self) -> int:
        if self.total >= 32:
            h = mask(
                rotl(self.v1, 1)
                + rotl(self.v2, 7)
                + rotl(self.v3, 12)
                + rotl(self.v4, 18)
            )
            h = merge_round(h, self.v1)
            h = merge_round(h, self.v2)
            h = merge_round(h, self.v3)
            h = merge_round(h, self.v4)
        else:
            h = mask(self.seed + P5)

        h = mask(h + self.total)
        index = 0
        tail = bytes(self.mem)

        while index + 8 <= len(tail):
            value = round_acc(0, read_u64(tail, index))
            h = mask(h ^ value)
            h = mask(mask(rotl(h, 27) * P1) + P4)
            index += 8

        if index + 4 <= len(tail):
            h = mask(h ^ mask(read_u32(tail, index) * P1))
            h = mask(mask(rotl(h, 23) * P2) + P3)
            index += 4

        while index < len(tail):
            h = mask(h ^ mask(tail[index] * P5))
            h = mask(rotl(h, 11) * P1)
            index += 1

        h ^= h >> 33
        h = mask(h * P2)
        h ^= h >> 29
        h = mask(h * P3)
        h ^= h >> 32
        return mask(h)


@dataclass(frozen=True)
class AssetFile:
    path: str
    size: int
    hash: int

    def destination(self, root: Path) -> Path:
        parts = Path(self.path).parts
        if not parts or any(part in ("", ".", "..") for part in parts):
            raise ValueError(f"unsafe manifest path: {self.path!r}")
        if any(chr(92) in part or ":" in part for part in parts):
            raise ValueError(f"unsafe manifest path: {self.path!r}")
        return root.joinpath(*parts)


def parse_manifest(data: bytes) -> list[AssetFile]:
    root = ET.fromstring(data)
    if root.tag != "ClientManifest" or root.attrib.get("version") != "1":
        raise ValueError("unsupported client manifest")

    files: list[AssetFile] = []

    def walk(node: ET.Element, components: tuple[str, ...]) -> None:
        for child in node:
            name = child.attrib.get("name")
            path_components = components + ((name,) if name else ())
            if child.tag == "File":
                if not name:
                    raise ValueError("file without name")
                size_raw = child.attrib.get("size")
                hash_raw = child.attrib.get("hash")
                if size_raw is None or hash_raw is None:
                    raise ValueError(f"missing size/hash for {name}")
                # Manifest paths never start with a leading folder name, but the
                # C# downloader prepends the CDN root. Keep relative paths here.
                files.append(
                    AssetFile(
                        path="/".join(path_components),
                        size=int(size_raw),
                        hash=int(hash_raw, 0) if hash_raw.lower().startswith("0x") else int(hash_raw),
                    )
                )
            elif child.tag == "Folder":
                walk(child, path_components)

    walk(root, ())
    return files


def verify_file(path: Path, expected: AssetFile) -> bool:
    if not path.is_file() or path.stat().st_size != expected.size:
        return False
    hasher = XXH64()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.digest() == expected.hash


def remote_url(base: str, path: str) -> str:
    quoted = "/".join(
        urllib.parse.quote(part, safe="")
        for part in path.split("/")
        if part
    )
    return f"{base.rstrip('/')}/{quoted}"


def local_extra_files(local_dir: Path, manifest_paths: set[str]) -> list[AssetFile]:
    """Index local client files absent from the downloadable manifest."""

    reserved = {
        ".gitkeep",
        "client-assets-index.json",
        "clientmanifest.xml",
    }
    files: list[AssetFile] = []
    for source in local_dir.rglob("*"):
        if source.is_symlink() or not source.is_file():
            continue
        relative = source.relative_to(local_dir).as_posix()
        if relative in reserved or relative in manifest_paths:
            continue
        if relative == "Logs" or relative.startswith("Logs/"):
            continue
        parts = Path(relative).parts
        if any(part in ("", ".", "..") or chr(92) in part or ":" in part for part in parts):
            raise ValueError(f"unsafe local client path: {relative!r}")
        hasher = XXH64()
        with source.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                hasher.update(chunk)
        files.append(AssetFile(relative, source.stat().st_size, hasher.digest()))
    return sorted(files, key=lambda asset: asset.path)


def stage_local_file(asset: AssetFile, source_root: Path, destination_root: Path) -> str:
    """Copy a verified local file into the staged payload atomically."""

    source = asset.destination(source_root)
    destination = asset.destination(destination_root)
    if verify_file(destination, asset):
        return "cached"
    if not source.is_file():
        raise FileNotFoundError(source)

    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.with_name(
        f".{destination.name}.{os.getpid()}.{time.time_ns()}.local.part"
    )
    hasher = XXH64()
    copied = 0
    try:
        with source.open("rb") as input_handle, temp.open("wb") as output_handle:
            while True:
                chunk = input_handle.read(1024 * 1024)
                if not chunk:
                    break
                output_handle.write(chunk)
                hasher.update(chunk)
                copied += len(chunk)
            output_handle.flush()
            os.fsync(output_handle.fileno())
        if copied != asset.size or hasher.digest() != asset.hash:
            raise ValueError(f"local source changed while staging {asset.path}")
        os.replace(temp, destination)
        return "staged"
    finally:
        temp.unlink(missing_ok=True)


def download_one(asset: AssetFile, root: Path, base: str, retries: int = 3) -> str:
    destination = asset.destination(root)
    if verify_file(destination, asset):
        return "cached"

    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.with_name(
        f".{destination.name}.{os.getpid()}.{time.time_ns()}.part"
    )
    url = remote_url(base, asset.path)
    last_error: Exception | None = None

    try:
        for attempt in range(1, retries + 1):
            hasher = XXH64()
            received = 0
            try:
                request = urllib.request.Request(
                    url,
                    headers={
                        "User-Agent": "OSFR iOS asset bundler",
                        "Accept": "*/*",
                        # The CDN rewrites at least one HTML asset unless an
                        # explicit identity encoding is requested.
                        "Accept-Encoding": "identity",
                    },
                )
                with urllib.request.urlopen(request, timeout=120) as response:
                    with temp.open("wb") as output:
                        while True:
                            chunk = response.read(1024 * 1024)
                            if not chunk:
                                break
                            output.write(chunk)
                            hasher.update(chunk)
                            received += len(chunk)
                        output.flush()
                        os.fsync(output.fileno())
                if received != asset.size:
                    raise ValueError(
                        f"size mismatch for {asset.path}: {received} != {asset.size}"
                    )
                actual = hasher.digest()
                if actual != asset.hash:
                    raise ValueError(
                        f"hash mismatch for {asset.path}: {actual} != {asset.hash}"
                    )
                os.replace(temp, destination)
                return "downloaded"
            except Exception as error:  # noqa: BLE001 - retry all transport/verify errors
                last_error = error
                temp.unlink(missing_ok=True)
                if attempt < retries:
                    time.sleep(min(2 ** attempt, 8))
        raise RuntimeError(f"failed {asset.path} after {retries} attempts: {last_error}")
    finally:
        temp.unlink(missing_ok=True)


def main(argv: Iterable[str] | None = None) -> int:
    args = list(argv if argv is not None else sys.argv[1:])
    if args and args[0] in ("-h", "--help"):
        print(__doc__)
        return 0

    manifest_url = os.environ.get("IOS_CLIENT_MANIFEST_URL", DEFAULT_MANIFEST)
    base_url = os.environ.get("IOS_CLIENT_BASE_URL", DEFAULT_BASE)
    root = Path(
        os.environ.get(
            "IOS_CLIENT_DEST",
            Path(__file__).resolve().parents[1]
            / "Launcher"
            / "Resources"
            / "ClientAssets",
        )
    )
    workers = max(1, int(os.environ.get("IOS_CLIENT_WORKERS", "8")))
    limit_raw = os.environ.get("IOS_CLIENT_LIMIT")
    limit = int(limit_raw) if limit_raw else None
    prefix = os.environ.get("IOS_CLIENT_FILTER", "")
    local_root_raw = os.environ.get("IOS_CLIENT_LOCAL_DIR")
    local_root = Path(local_root_raw).expanduser().resolve() if local_root_raw else None
    if local_root is not None and not local_root.is_dir():
        print(f"IOS_CLIENT_LOCAL_DIR is not a directory: {local_root}", file=sys.stderr)
        return 1

    root.mkdir(parents=True, exist_ok=True)
    print(f"Fetching {manifest_url}")
    manifest_request = urllib.request.Request(
        manifest_url,
        headers={
            "User-Agent": "OSFR iOS asset bundler",
            "Accept": "application/xml, text/xml",
            "Accept-Encoding": "identity",
        },
    )
    with urllib.request.urlopen(manifest_request, timeout=60) as response:
        manifest_bytes = response.read()
    (root / "clientmanifest.xml").write_bytes(manifest_bytes)

    all_assets = parse_manifest(manifest_bytes)
    assets = all_assets
    if prefix:
        assets = [asset for asset in assets if asset.path.startswith(prefix)]
    if limit is not None:
        assets = assets[:limit]

    extras: list[AssetFile] = []
    if local_root is not None:
        extras = local_extra_files(local_root, {asset.path for asset in all_assets})
        print(
            f"Local source: {len(extras)} supplemental file(s), "
            f"{sum(asset.size for asset in extras) / 1024 ** 2:.1f} MiB"
        )

    total_size = sum(asset.size for asset in assets + extras)
    print(f"Manifest: {len(assets)} files, {total_size / 1024 ** 2:.1f} MiB selected")

    downloaded = 0
    cached = 0
    failed: list[str] = []
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(download_one, asset, root, base_url): asset
            for asset in assets
        }
        for future in as_completed(futures):
            asset = futures[future]
            try:
                result = future.result()
                if result == "cached":
                    cached += 1
                else:
                    downloaded += 1
                done = downloaded + cached + len(failed)
                if done % 25 == 0 or done == len(assets):
                    print(
                        f"  {done}/{len(assets)} "
                        f"({downloaded} downloaded, {cached} cached, {len(failed)} failed)",
                        flush=True,
                    )
            except Exception as error:  # noqa: BLE001
                failed.append(asset.path)
                print(f"ERROR {asset.path}: {error}", file=sys.stderr)

    staged_local = 0
    cached_local = 0
    for asset in extras:
        try:
            result = stage_local_file(asset, local_root, root)
            if result == "cached":
                cached_local += 1
            else:
                staged_local += 1
        except Exception as error:  # noqa: BLE001
            failed.append(asset.path)
            print(f"ERROR local {asset.path}: {error}", file=sys.stderr)

    index = {
        "manifestUrl": manifest_url,
        "baseUrl": base_url,
        "localSource": str(local_root) if local_root is not None else None,
        "fileCount": len(assets) + len(extras),
        "totalBytes": total_size,
        "files": [
            {"path": asset.path, "size": asset.size, "hash": asset.hash}
            for asset in assets + extras
        ],
    }
    (root / "client-assets-index.json").write_text(
        json.dumps(index, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    print(
        f"Done: {downloaded} downloaded, {cached} cached, "
        f"{staged_local} local staged, {cached_local} local cached, "
        f"{len(failed)} failed"
    )
    if failed:
        print("Failed files:", ", ".join(failed[:20]), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
