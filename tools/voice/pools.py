#!/usr/bin/env python3
"""ADR 0006 runbook step 1: deterministic dev / sealed pools of speakers and NSynth instruments.

  pools.py [--public testdata/public] [--out testdata/voice/pools.json]

Within each stratum the ids are ranked by sha256("intono-voice-1:" + id); the lowest 25 % (rounded, at least 1 when the stratum has
2 or more ids) are SEALED. The output holds ids only, plus its own sha256 in pools.json.sha256. The sealed pool is not opened again
until the sealed run.
"""
import argparse
import os

from common import DEFAULT_PUBLIC, SEALED_FRACTION, ROOT, SALT, rank_key, read_json, sha256_file, write_json

CORPUS_FILES = ["librispeech", "nsynth", "speechocean762", "musan"]


def build(manifests):
    strata = {}
    for man in manifests:
        for it in man["items"]:
            if it.get("licence_entry_found") is False:
                continue
            strata.setdefault(it["stratum"], set()).add(it["speaker"])
    groups = {}
    for st, ids in sorted(strata.items()):
        ranked = sorted(ids, key=rank_key)
        n = len(ranked)
        ns = int(round(SEALED_FRACTION * n))
        if n >= 2:
            ns = max(1, ns)
        groups[st] = dict(sealed=sorted(ranked[:ns]), dev=sorted(ranked[ns:]))
    return groups


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--public", default=DEFAULT_PUBLIC)
    ap.add_argument("--out", default=os.path.join(ROOT, "testdata", "voice", "pools.json"))
    a = ap.parse_args()
    mans = []
    for c in CORPUS_FILES:
        p = os.path.join(a.public, c, "manifest.json")
        if os.path.exists(p):
            mans.append(read_json(p))
    if not mans:
        raise SystemExit("no manifests found; run intake.py first")
    groups = build(mans)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    write_json(a.out, dict(salt=SALT, sealed_fraction=SEALED_FRACTION, rule="sha256(salt:id) ascending; lowest round(0.25 n) (min 1 if n>=2) sealed", groups=groups))
    sha = sha256_file(a.out)
    open(a.out + ".sha256", "w").write(sha + "\n")
    print(f"pools written to {a.out}\nsha256 {sha}\n")
    for st, g in groups.items():
        print(f"  {st:28s} dev {len(g['dev']):4d}   sealed {len(g['sealed']):4d}")


if __name__ == "__main__":
    main()
