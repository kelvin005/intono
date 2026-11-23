#!/usr/bin/env python3
"""Intake of a public corpus (ADR 0006 runbook step 0): checksum, safe extraction, structure and count checks, manifest.

  intake.py CORPUS (--archive FILE | --dir DIR) [--out testdata/public] [--allow-count-mismatch]
  CORPUS: librispeech | nsynth | speechocean762 | musan

Fails loudly and fixes nothing silently. The directory layouts below are ASSUMED from the published documentation and are
verified on arrival; if a layout differs the tool stops with a message, and the parser is changed with the evidence in hand.
No audio is copied anywhere except by extracting the archive you give it into its own directory under --out.
"""
import argparse
import os
import sys
import tarfile
import zipfile

import soundfile as sf

from common import DEFAULT_PUBLIC, read_json, sha256_file, write_json

CORPORA = {
    "librispeech": dict(url="https://www.openslr.org/12", licence="CC BY 4.0", sr=16000,
                        expect={"speakers": 40, "utterances": 2620}),
    "nsynth": dict(url="https://magenta.tensorflow.org/datasets/nsynth", licence="CC BY 4.0", sr=16000,
                   expect={"nsynth-test": 4096, "nsynth-valid": 12678}),
    "speechocean762": dict(url="https://www.openslr.org/101", licence="CC BY 4.0 (OpenSLR statement)", sr=16000,
                           expect={"speakers": 250, "utterances": 5000, "children": 125, "adults": 125}),
    "musan": dict(url="https://www.openslr.org/17", licence="CC BY 4.0 overall; per-file LICENSE entries", sr=16000, expect={}),
}
CHILD_MAX_AGE = 17   # speechocean762: age < 18 is a child; the 125 / 125 split is checked, not assumed


def safe_extract(archive, dest):
    os.makedirs(dest, exist_ok=False)          # its own new, empty directory
    base = os.path.realpath(dest)
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as z:
            for n in z.namelist():
                if not os.path.realpath(os.path.join(dest, n)).startswith(base + os.sep) and n.rstrip("/"):
                    sys.exit(f"unsafe path in archive: {n}")
            z.extractall(dest)
        return
    with tarfile.open(archive) as t:
        for m in t.getmembers():
            if m.issym() or m.islnk() or m.isdev() or not os.path.realpath(os.path.join(dest, m.name)).startswith(base + os.sep) and m.name not in (".", "./"):
                sys.exit(f"unsafe member in archive: {m.name}")
        t.extractall(dest)


def walk(root, exts):
    for d, _, fs in os.walk(root):
        for f in sorted(fs):
            if f.lower().endswith(exts):
                yield os.path.join(d, f)


def audio_info(path):
    i = sf.info(path)
    return dict(sr=i.samplerate, ch=i.channels, sec=i.frames / float(i.samplerate))


def find_file(root, name):
    for d, _, fs in os.walk(root):
        if name in fs:
            return os.path.join(d, name)
    return None


def do_librispeech(root):
    tc = None
    for d, ds, _ in os.walk(root):
        if os.path.basename(d) == "test-clean":
            tc = d
            break
    if not tc:
        sys.exit("librispeech: no 'test-clean' directory found")
    spk = find_file(root, "SPEAKERS.TXT")
    if not spk:
        sys.exit("librispeech: SPEAKERS.TXT not found (needed for the female / male strata)")
    sex = {}
    for line in open(spk, errors="replace"):
        if line.startswith(";") or "|" not in line:
            continue
        p = [q.strip() for q in line.split("|")]
        if len(p) >= 3 and p[2] == "test-clean":
            sex[p[0]] = p[1].upper()
    items = []
    for f in walk(tc, (".flac", ".wav")):
        s = os.path.basename(f).split("-")[0]
        if s not in sex:
            sys.exit(f"librispeech: speaker {s} has no entry for test-clean in SPEAKERS.TXT")
        items.append(dict(path=os.path.relpath(f, root), id=os.path.basename(f), speaker=f"ls:{s}", stratum=f"ls:{'female' if sex[s] == 'F' else 'male'}"))
    return items, {"speakers": len({i["speaker"] for i in items}), "utterances": len(items)}


def do_nsynth(root):
    items, counts = [], {}
    for d, _, fs in os.walk(root):
        if "examples.json" in fs and os.path.isdir(os.path.join(d, "audio")):
            split = os.path.basename(d)
            ex = read_json(os.path.join(d, "examples.json"))
            counts[split] = len(ex)
            for ns, e in sorted(ex.items()):
                p = os.path.join(d, "audio", ns + ".wav")
                if not os.path.exists(p):
                    sys.exit(f"nsynth: {p} listed in examples.json but missing")
                fam, src = e["instrument_family_str"], e["instrument_source_str"]
                stratum = "ns:string_acoustic" if (fam == "string" and src == "acoustic") else "ns:vocal_acoustic" if (fam == "vocal" and src == "acoustic") else "ns:other"
                items.append(dict(path=os.path.relpath(p, root), id=ns, speaker=f"ns:{e['instrument_str']}", stratum=stratum, split=split,
                                  pitch=e["pitch"], velocity=e["velocity"], qualities=e.get("qualities_str", []), family=fam, source=src))
    if not counts:
        sys.exit("nsynth: no directory with examples.json and an audio/ folder found")
    return items, counts


def parse_kv(path):
    d = {}
    for line in open(path, errors="replace"):
        p = line.split()
        if len(p) >= 2:
            d["".join(c for c in p[0] if c.isdigit())] = p[1]
    return d


def do_speechocean(root):
    age_f, gen_f = find_file(root, "spk2age"), find_file(root, "spk2gender")
    if not age_f or not gen_f:
        sys.exit("speechocean762: spk2age / spk2gender not found anywhere under the corpus. They are needed to separate children from "
                 "adults; send the speaker age and gender metadata that ships with the corpus (do not guess).")
    age, gen = parse_kv(age_f), parse_kv(gen_f)
    items = []
    for f in walk(root, (".wav",)):
        parts = f.replace("\\", "/").split("/")
        sp = next((p for p in parts if p.upper().startswith("SPEAKER")), None)
        if sp is None:
            continue
        sid = "".join(c for c in sp if c.isdigit())
        if sid not in age or sid not in gen:
            sys.exit(f"speechocean762: speaker {sid} missing in spk2age/spk2gender")
        a = int(float(age[sid]))
        grp = "child" if a <= CHILD_MAX_AGE else "adult"
        items.append(dict(path=os.path.relpath(f, root), id=os.path.basename(f), speaker=f"so:{sid}", age=a, gender=gen[sid].upper()[:1],
                          stratum=f"so:{grp}:{gen[sid].upper()[:1]}", group=grp))
    spk = {i["speaker"]: i["group"] for i in items}
    return items, {"speakers": len(spk), "utterances": len(items), "children": sum(g == "child" for g in spk.values()), "adults": sum(g == "adult" for g in spk.values())}


def do_musan(root):
    noise = None
    for d, ds, _ in os.walk(root):
        if os.path.basename(d) == "noise":
            noise = d
            break
    if not noise:
        sys.exit("musan: no 'noise' directory found")
    items, unlicensed = [], 0
    for sub in sorted(os.listdir(noise)):
        sd = os.path.join(noise, sub)
        lic = os.path.join(sd, "LICENSE")
        if not os.path.isdir(sd):
            continue
        text = open(lic, errors="replace").read() if os.path.exists(lic) else ""
        for f in walk(sd, (".wav",)):
            ok = bool(text) and os.path.basename(f) in text
            unlicensed += (not ok)
            items.append(dict(path=os.path.relpath(f, root), id=os.path.basename(f), speaker=f"mu:{sub}", stratum="mu:noise", licence_entry_found=ok,
                              licence_dir=sub))
    if not items:
        sys.exit("musan: no noise wavs found")
    return items, {"noise_files": len(items), "without_licence_entry": unlicensed}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", choices=list(CORPORA))
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--archive")
    g.add_argument("--dir")
    ap.add_argument("--out", default=DEFAULT_PUBLIC)
    ap.add_argument("--allow-count-mismatch", action="store_true", help="self-test only")
    a = ap.parse_args()
    meta = CORPORA[a.corpus]
    dest = os.path.join(a.out, a.corpus)
    arch_sha = None
    if a.archive:
        arch_sha = sha256_file(a.archive)
        print(f"{a.corpus}: archive sha256 {arch_sha} (compare with the publisher's checksum where one is published)")
        root = os.path.join(dest, "data")
        os.makedirs(dest, exist_ok=True)
        safe_extract(a.archive, root)
    else:
        root = os.path.abspath(a.dir)
        os.makedirs(dest, exist_ok=True)
    items, counts = {"librispeech": do_librispeech, "nsynth": do_nsynth, "speechocean762": do_speechocean, "musan": do_musan}[a.corpus](root)
    total, bad_fmt = 0.0, []
    srs = set()
    for it in items:
        ai = audio_info(os.path.join(root, it["path"]))
        total += ai["sec"]
        it["sec"] = round(ai["sec"], 4)
        srs.add(ai["sr"])
        if ai["sr"] != meta["sr"] or ai["ch"] != 1:
            bad_fmt.append((it["path"], ai["sr"], ai["ch"]))
    checks = []
    for k, v in meta["expect"].items():
        checks.append(dict(name=k, expected=v, found=counts.get(k), ok=counts.get(k) == v))
    checks.append(dict(name="all files mono at %d Hz" % meta["sr"], ok=not bad_fmt, found=len(bad_fmt)))
    lic_path = None
    for n in ("LICENSE", "LICENSE.txt", "license.txt", "LICENCE"):
        p = os.path.join(root, n)
        if os.path.exists(p):
            lic_path = p
    man = dict(corpus=a.corpus, source_url=meta["url"], licence_stated=meta["licence"], licence_text_in_archive=bool(lic_path), archive_sha256=arch_sha,
               data_root=root, n_files=len(items), total_seconds=round(total, 2), sample_rates=sorted(srs), counts=counts, checks=checks, items=items)
    write_json(os.path.join(dest, "manifest.json"), man)
    if lic_path:
        open(os.path.join(dest, "LICENSE.txt"), "w").write(open(lic_path, errors="replace").read())
    print(f"{a.corpus}: {len(items)} files, {total / 3600:.2f} h, counts {counts}")
    for c in checks:
        print(f"  {'OK  ' if c['ok'] else 'FAIL'} {c['name']}: expected {c.get('expected', '-')} found {c.get('found')}")
    if a.corpus == "musan" and counts["without_licence_entry"]:
        print(f"  NOTE: {counts['without_licence_entry']} files have no LICENSE entry; they are excluded from use (licence_entry_found = false)")
    if not lic_path:
        print("  NOTE: no licence text file in the archive; the stated licence is in the manifest; copy the licence text beside it by hand")
    if any(not c["ok"] for c in checks) and not a.allow_count_mismatch:
        sys.exit("intake FAILED: counts or formats differ from the corpus description; nothing is silently fixed")


if __name__ == "__main__":
    main()
