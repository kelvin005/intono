# tools/voice: ADR 0006 voice-rejection data tools

Status: written and plumbing-tested on GENERATED stand-in corpora only (`selftest.py`). They have not touched real data.
Nothing here is shipped; datasets are test-only (see docs/THIRD_PARTY_DATA.md). Never commit audio.

Order (runbook in docs/adr/0006):
1. `intake.py <corpus> --dir <extracted-archive-dir> --out testdata/public`   (librispeech, nsynth, speechocean762, musan; fails loudly on count/layout mismatch)
2. `pools.py --public testdata/public --out testdata/voice/pools.json`        (sha256 of "intono-voice-1:"+id, lowest 25 % sealed)
3. `gen_mix.py --pool dev --seeds 9401 ... --public testdata/public --pools testdata/voice/pools.json --out testdata/voice/mix/dev` (sealed seeds 44001-44004 only with --pool sealed)
4. `eval_gates.py mix --mix-dir <dir> --cli-base /tmp/frozen/intono-cli-gate4 --out reports/voice/baseline.md`   (baseline: the problem, and the bases of G3/G4/G6)
5. `features.py --mix-dir <dir> --out dev.npz`, then `fit.py --feats dev.npz --out model.json` (forward selection, operating point; prints NO FEASIBLE OPERATING POINT if option C is triggered)
6. After the DSP change (needs approval and data): `eval_gates.py mix ... --cli-new <candidate>`; sealed runs need a registered entry in SEALED, run once.
7. Real clips: `eval_gates.py real --annot annotations.json ...` (G9 carries weight only with >= 10 min playing and >= 4 min speech).

`selftest.py [--keep DIR]` runs steps 1-5 plus the compare mode on stand-ins. Its fit result says nothing about real audio.
Known gap: the option A (confidence threshold) note-level baseline is not yet implemented in eval_gates.py.
