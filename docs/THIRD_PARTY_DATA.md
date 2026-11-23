# Third-party data used for testing (ADR 0006)

Test data only. No audio from any of these is committed, shipped or stored in the Project store; it lives in the gitignored `testdata/public/`. If ADR 0006 is approved and implemented, a few numbers fitted on this data (weights and thresholds) ship; the audio does not. Licences are as stated by each source on 2026-11-22; they are rechecked on arrival and the licence text is stored beside each corpus. Status "not yet received" means nothing from it has been used.

| Dataset | Licence | Source | Citation | Status |
|---|---|---|---|---|
| NSynth (test and validation splits) | CC BY 4.0 | https://magenta.tensorflow.org/datasets/nsynth | Engel, J., Resnick, C., Roberts, A., Dieleman, S., Norouzi, M., Eck, D., Simonyan, K. Neural Audio Synthesis of Musical Notes with WaveNet Autoencoders. ICML 2017. | not yet received |
| LibriSpeech (test-clean) | CC BY 4.0 | https://www.openslr.org/12 | Panayotov, V., Chen, G., Povey, D., Khudanpur, S. LibriSpeech: an ASR corpus based on public domain audio books. ICASSP 2015. | not yet received |
| speechocean762 (OpenSLR SLR101) | CC BY 4.0 (OpenSLR; some Hugging Face mirrors say Apache 2.0, the OpenSLR statement is used) | https://www.openslr.org/101 | Zhang, J., Zhang, Z., Wang, Y., Yan, Z., Song, Q., Huang, Y., Li, K., Povey, D., Wang, Y. speechocean762: An Open-Source Non-native English Speech Corpus For Pronunciation Assessment. Interspeech 2021 (arXiv:2104.01378). | not yet received |
| MUSAN, noise part only | CC BY 4.0 overall; each subdirectory has a LICENSE file with the licence of every file; only files whose entry allows commercial use are used, and each used file is listed with its licence in the manifest | https://www.openslr.org/17 | Snyder, D., Chen, G., Povey, D. MUSAN: A Music, Speech, and Noise Corpus. arXiv:1510.08484, 2015. | not yet received |

Not in this list: the real-audio clips (internal testing only, never committed or shipped; clip #1 is a third-party tutorial and is a check only).
