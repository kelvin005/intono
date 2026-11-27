#!/usr/bin/env python3
"""Tests for golden.py (the bit-identity check against a stored manifest of phase1-complete outputs).

  INTONO_CLI=build/intono-cli python tools/accuracy/test_golden.py

Uses the real CLI on a small subset (one seed, two phrases) so it runs in seconds.
"""
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.join(HERE, "golden.py")
CLI = os.environ.get("INTONO_CLI", os.path.join(HERE, "..", "..", "build", "intono-cli"))


def golden(*args):
    return subprocess.run([sys.executable, GOLDEN, *args], capture_output=True, text=True)


class GoldenTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.path.exists(CLI):
            raise unittest.SkipTest(f"no CLI at {CLI} (set INTONO_CLI)")
        cls.td = tempfile.TemporaryDirectory()
        cls.manifest = os.path.join(cls.td.name, "g.json")
        r = golden("make", "--cli", CLI, "--out", cls.manifest, "--seeds", "21", "--limit", "2", "--source", "test")
        assert r.returncode == 0, r.stdout + r.stderr
        with open(cls.manifest) as f:
            cls.m = json.load(f)

    @classmethod
    def tearDownClass(cls):
        cls.td.cleanup()

    def write(self, m):
        p = os.path.join(self.td.name, "t.json")
        with open(p, "w") as f:
            json.dump(m, f)
        return p

    def test_manifest_shape(self):
        # 2 phrases x (unpadded, padded); frames and notes per case; inputs hashed
        self.assertEqual(len(self.m["cases"]), 4)
        for c in self.m["cases"]:
            self.assertEqual(len(c["input_sha256"]), 64)
            self.assertEqual(set(c["out"]), {"frames", "notes"})
        self.assertEqual(self.m["seeds"], [21])
        self.assertEqual(self.m["source"], "test")

    def test_same_binary_passes_inline_and_threaded(self):
        for extra in ([], ["--threaded"]):
            r = golden("check", "--cli", CLI, "--golden", self.manifest, *extra)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("0 differ", r.stdout)

    def test_changed_output_fails(self):
        m = json.loads(json.dumps(self.m))
        m["cases"][1]["out"]["notes"] = "0" * 64
        r = golden("check", "--cli", CLI, "--golden", self.write(m))
        self.assertEqual(r.returncode, 1)
        self.assertIn("DIFF", r.stdout)
        self.assertIn("notes", r.stdout)

    def test_changed_input_is_reported_as_input_drift(self):
        m = json.loads(json.dumps(self.m))
        m["cases"][0]["input_sha256"] = "f" * 64
        r = golden("check", "--cli", CLI, "--golden", self.write(m))
        self.assertEqual(r.returncode, 1)
        self.assertIn("INPUT DRIFT", r.stdout)

    def test_different_binary_fails(self):
        # a wrapper that changes one byte of the CLI's output stands in for a DSP change
        w = os.path.join(self.td.name, "cli-wrapped")
        with open(w, "w") as f:
            f.write(f'#!/bin/sh\n"{os.path.abspath(CLI)}" "$@" | sed "2s/0/1/"\n')
        os.chmod(w, os.stat(w).st_mode | stat.S_IXUSR)
        r = golden("check", "--cli", w, "--golden", self.manifest)
        self.assertEqual(r.returncode, 1)
        self.assertIn("DIFF", r.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
