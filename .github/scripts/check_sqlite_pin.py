#!/usr/bin/env python3
"""Checks the SQLite pin (ADR 0015 Note 1) after `flutter pub get`.

package:sqlite3's build hook downloads prebuilt SQLite binaries from the package's GitHub release and verifies each against sha256
hashes compiled into the package. This script makes that pin ours: the package pub resolved and fetched must be exactly the one in
app/tool/sqlite3_pin.json (version, archive hash, release tag, URL pattern, every binary hash we use), and nothing may redirect the hook
(no hook user_defines for sqlite3 in pubspec.yaml).

usage: check_sqlite_pin.py [--app app] [--pub-cache DIR]   (default: $PUB_CACHE, else ~/.pub-cache)
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path


def fail(msg):
    print(f"::error::SQLite pin (ADR 0015 Note 1): {msg}")
    sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", default="app")
    ap.add_argument("--pub-cache", default=os.environ.get("PUB_CACHE") or str(Path.home() / ".pub-cache"))
    a = ap.parse_args()
    app = Path(a.app)
    pin = json.loads((app / "tool" / "sqlite3_pin.json").read_text())

    lock = (app / "pubspec.lock").read_text()
    m = re.search(r'\n  sqlite3:\n(?:    .*\n|      .*\n)*?    version: "([^"]+)"', lock)
    blk = re.search(r'\n  sqlite3:\n((?:    .*\n)+)', lock)
    if not m or not blk:
        fail("sqlite3 is not in pubspec.lock")
    sha = re.search(r'sha256: "([0-9a-f]{64})"', blk.group(1))
    if m.group(1) != pin["version"]:
        fail(f"pubspec.lock has sqlite3 {m.group(1)}, the pin is {pin['version']}")
    if not sha or sha.group(1) != pin["package_sha256"]:
        fail(f"pubspec.lock's sqlite3 archive hash {sha.group(1) if sha else None} is not the pinned {pin['package_sha256']}")

    spec = (app / "pubspec.yaml").read_text()
    if re.search(r"^hooks:\s*$", spec, re.M) or "user_defines" in spec:
        fail("pubspec.yaml sets hook user_defines; the SQLite source must stay the pinned release")

    pkg = Path(a.pub_cache) / "hosted" / "pub.dev" / f"sqlite3-{pin['version']}"
    hashes = pkg / "lib" / "src" / "hook" / "asset_hashes.dart"
    desc = pkg / "lib" / "src" / "hook" / "compile" / "description.dart"
    if not hashes.is_file() or not desc.is_file():
        fail(f"the fetched package is not where pub puts it ({pkg}); run after flutter pub get")
    h = hashes.read_text()
    tag = re.search(r"releaseTag = '([^']+)'", h)
    if not tag or tag.group(1) != pin["release_tag"]:
        fail(f"the package downloads from release {tag.group(1) if tag else None}, the pin is {pin['release_tag']}")
    for name, want in pin["assets"].items():
        got = re.search(re.escape(f"'{name}': '") + r"([0-9a-f]{64})'", h)
        if not got or got.group(1) != want:
            fail(f"{name}: the package expects {got.group(1) if got else None}, the pin is {want}")
    url = re.search(r"defaultUrlPattern =\s*r'([^']+)'", desc.read_text())
    if not url or url.group(1) != pin["url_pattern"]:
        fail(f"the package downloads from {url.group(1) if url else None}, the pin is {pin['url_pattern']}")
    print(f"SQLite pin OK: sqlite3 {pin['version']} ({pin['package_sha256'][:12]}...), release {pin['release_tag']}, "
          f"{len(pin['assets'])} binaries pinned by sha256")


if __name__ == "__main__":
    main()
