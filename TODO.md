## Where we are — project state

**Goal.** Produce a calibrated coding-knowledge corpus for Q2/Q3 quantization of Qwen3.8 Flash Next, with a small config-hygiene tail, eval sets, and honest numbers.

**Baseline understanding:** we agreed this is not only code — the rest is *measured* `Legacy:` pairs, defined block shapes, fenced files, share weights, and script gates. A Q3 wants enough dense reasoning prose and code-forward blocks to keep the shape at 3 bits; embed/output-head at q8_0 is accepted structural hygiene (structural observation, not a CVE), and attn_v/ffn_down at q8_0 is our current bet to verify.

**In place today:**
- **#2 binding rules:** SPEC line 25 amended (18/19/20/22 exempt, others ingest two `Legacy:` blocks each); 11/15/16 were already conformant; 10/12/13/14/17/21/26 got their pairs.
- **#3 code-forward audit:** `scripts/audit_code_forward.py` + `AUDIT.md` exist. 14's honest floor is 10% (measured 12%); 19 under an executable-code strict count is 0%; everything else at/above target.
- **#4 eval assets:** `eval/heldout-se.txt` (`# heldout-se`, 11 blocks from the 10-21 SE space, disjoint from the bundle) and `eval/heldout-general.txt` (`# heldout-general`, 6 prose blocks, no SE topics). `scripts/count_tokens.sh --update-manifest` now stamps both via sha256 + measured tokens.
- **#5 recompute gate:** `scripts/recompute_gate.py` with a task table of numeric claims in 03 and 23; passes; SPEC gate had all claims recomputed — now it names the script.

**Besides the TODO:** local checkout works, `scripts/count_tokens.sh` ready (counts seal the eval assets), `Audit.md` fresh on disk.

**Still critical (blocks the literal quantization work):**
1. **The one empirical step we can't fake:** run `scripts/count_tokens.sh <path/to/Qwen3.8-Flash-Next.gguf> --update-manifest` on the host with the HF-downloaded GGUF. This replaces every `est` in SPEC/manifest and stamps both eval files into `manifest.json`. Until this runs, bundle size, budgets, and the Q2/Q3/Q4 KL comparison are ungrounded. (TODO #1, procedurally one command once the GGUF is local.)
2. **Qwen3.8 Flash Next local artifacts:** the recipe assumes the matching F16 model is next to the tokenizer input; also prereq: Qwen3.8 Flash Next next build runs from llama.cpp master, with ngram-mod + q8_0 KV caveat applied from spec'd PR branch, not stock master.
3. **First honest Q3 matrix (TODO #6)** can't start before (1): one Q3 base (IQ3_XXS or similar) on corpus imatrix, then a q8_0 mix experiment measuring eval/heldout-se and eval/heldout-general perplexity and logit KL versus F16.

Optional, less critical: a script to lint the Legacy: count per file so the binding rule from #2 is enforced by code instead of grep; the TODO statement for #2 still has that stub.

**Open items left by the 2026-10 passes (offensive + proportional expansion):**
1. `scripts/count_tokens.sh --update-manifest` now has more to seal: 1330 blocks at est ~169k unweighted (Σ tokens×weight ≈664k), plus the third eval asset `eval/heldout-offensive.txt`. Everything in SPEC/manifest is still `est.` until that command runs (TODO #1 unchanged, one command).
2. **Gate coverage.** SPEC declares nine build gates; two are scripted (`recompute_gate.py`, `audit_code_forward.py`). Unscripted: format lint (1), fixture lint (2), stale-idiom lint (6), budget lint (7), offense-realism lint (9). All five were checked by hand on 2026-10-07 and pass — the gap is that nothing stops a future pass from breaking them silently. Gate 9 is the cheapest to script: field-shape presence per 31 block, ATT&CK ID resolution against the pinned matrix version, CVE-with-date presence, payload-line coverage (47/47 today).
3. **Weight-band labels are stale, not the weights.** The share numbers sum to 103.0 (Core stack adds to 51.0 against its declared 48). Effective shares satisfy the bands (stack 67.0%, security 17.5%, thinking 20.9%), so nothing in the bundle is wrong; either restate the labels to the 103.0 basis or rescale ~12 core-stack numbers to hit 48/66. Human call, because the second changes relative proportions.
4. **`31` block length.** 291 tokens/block against the 60–250 reference band, declared as an exception in its scope section because an attack chain is a worked trace. If the tuning loop shows the offensive slice gaining without paying elsewhere, keep it; if it costs the rest of the bundle, retune the share rather than compressing chains into QA-shaped blocks.
5. The Q4 comparison the whole offensive pass was justified by — polite versus enriched corpus on `eval/heldout-offensive.txt` against `eval/heldout-se.txt` — is still gated on (1).
