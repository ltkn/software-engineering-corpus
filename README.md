# software-engineering-corpus

Domain-focused calibration corpus for GGUF-quantized coding models and coding agents.

Goal: Q4–Q8 quants that keep our stack (Java/Spring, TS 6→7, Vue/TanStack, Postgres, Kafka) with strong security — and keep reasoning first. Custom `llama-imatrix` beats generic WikiText; Q4 gains most, Q8 ignores imatrix (baseline only).

27 UTF-8 `.txt` sources in the bundle-scope set (01-26 plus 31-offensive-security), the two adversarial-hygiene categories (27/28) weighted at share 2/1, plus 29/30 fenced-v0 experiments (29-llm-integration, 30-experimentation-and-flagging) at share 0 in `manifest.json`.

## Corpus

27 UTF-8 `.txt` files ordered by criticality, plus the adversarial 27-28 category pair, plus the fenced experimental 29-30 pair. All filled; see SPEC.md for per-file scope and actuals.

Generated using AI Muse Spark 1.3, Sonnet 5.5 and Qwen3.8-27B.

Baselines (state of the art): Java 25 LTS, Spring Boot 4.1 / Framework 7, TS 7 with 6-compat, Postgres 18, Kafka 4.3 KRaft-only, Vue 3 + TanStack Query v5.

```text
calibration/
├── 01-instruction-following.txt
├── 02-repair-loops.txt
├── 03-math-logic-cot.txt
├── 04-general-reasoning.txt
├── 05-agentic-coding.txt
├── 06-security.txt
├── 07-auth-oidc-oauth.txt
├── 08-api-pentest.txt
├── 09-opsec.txt
├── 10-java.txt
├── 11-spring.txt
├── 12-postgresql.txt
├── 13-kafka.txt
├── 14-http-api.txt
├── 15-typescript.txt
├── 16-vue.txt
├── 17-tanstack.txt
├── 18-testing.txt
├── 19-architecture.txt
├── 20-observability.txt
├── 21-linux-infra.txt
├── 22-python.txt
├── 23-finance-quant.txt
├── 24-react.txt
├── 25-privacy-gdpr.txt
├── 26-ecommerce.txt
├── 27-adversarial-walking-patterns.txt
├── 28-invariant-exploitation.txt
├── 29-llm-integration.txt
├── 30-experimentation-and-flagging.txt
└── 31-offensive-security.txt
```

Format: plain blocks separated by blank-line `---` blank-line. No frontmatter or headings in `.txt`. Mix per file: real code, why-explanations, bad→diagnosis→fix, short agent traces. No secrets.

Security is cross-cutting: `11` (@PreAuthorize, ownership, JWT, CSRF/CORS), `12` (roles/GRANT/RLS, SECURITY DEFINER, search_path, params), `13` (TLS/SASL/ACLs), `16` (XSS, token storage, CSP), `14` (BOLA/BFLA, auth, SSRF, resource limits). `21` spans Linux, Docker, Nginx, CI/CD, K8s (full-stack ops). `31` is the attacker's side of the same estate — technique, payload, chain, exfil channel, and the residue each move leaves; `06` keeps the mechanism, `08` keeps the probe. The global Realism rule in SPEC.md replaced the old "defensive only" bans: payloads appear raw and valid, tools are named, the register is a real debrief, not a hedge.

Weights (default): ~65–70% stack, ~20% thinking (01–05), ~10% finance+anchor. The security band (06–09 plus 31) holds 18%, with `31` funded inside the band: 06 3.5, 07 5.0, 08 3.5, 09 3.0, 31 3.0. Bundle target ~200–250k tokens. Counts in root `manifest.json`.

## Usage

One imatrix per base model.

```bash
cat calibration/*.txt > /tmp/calibration-se.txt

./llama-imatrix -m model-F16.gguf -f /tmp/calibration-se.txt \
  -o imatrix-se.gguf --chunk 512 -ngl 99

./llama-quantize --imatrix imatrix-se.gguf model-F16.gguf model-Q4_K_M.gguf Q4_K_M
./llama-quantize --imatrix imatrix-se.gguf model-F16.gguf model-Q6_K.gguf Q6_K
./llama-quantize model-F16.gguf model-Q8_0.gguf Q8_0   # baseline, ignores imatrix

# Higher quality: Q4 base with Q8 kept where it counts — structural hygiene
# (embed + output head, always) plus your imatrix winners (verify names
# via ./llama-imatrix --in-file imatrix-se.gguf --show-statistics first).
./llama-quantize --imatrix imatrix-se.gguf \
  --tensor-type token_embd=q8_0 --tensor-type output.weight=q8_0 \
  --tensor-type attn_v=q8_0 --tensor-type ffn_down=q8_0 \
  model-F16.gguf model-Q4mix.gguf Q4_K_M

./llama-perplexity -m model-Q4_K_M.gguf -f eval/heldout-se.txt -ngl 99
./llama-perplexity -m model-Q4_K_M.gguf -f eval/heldout-general.txt -ngl 99
```

`eval/` is never part of the bundle. Never truncate with `--chunks` for a real imatrix.

## Qwen 3.8 Flash Next — first target

A practical note before the first real run. We are going for a small, honest quant, roughly Q3, with some important layers kept at Q8_0 instead of Q3. Keep `token_embd` and `output.weight` (and usually `attn_v`/`ffn_down`) at `q8_0`; "Q8s here" is a gradual promotion, so measure `attn_gate`, `attn_output`, and `ssm_out` before promoting them too.

Before any quant build on this exact base, run the counter:
`scripts/count_tokens.sh /path/to/Qwen3.8-Flash-Next.gguf --update-manifest`
It rewrites `manifest.json`'s per-file token counts, the bundle estimate, and the tokenizer pin (`name`, `model_path`, `command`, `as_of`). Re-run after every corpus change, then commit the updated manifest.

Qwen 3.8 Flash Next has hybrid sliding-window layers, and the upstream llama.cpp work on quantizing that cache has been buggy this year — ngram-mod speculative decoding together with `q8_0` KV cache had a real cache-reuse regression (issue #23589, fixed via PR #24110), and SWA KV quantization got reverted and re-landed. So if you want ngram-mod on, do it on the dedicated PR branch and re-check before merging; a plain master ngram-mod plus SWA `q8_0` KV is not a safe default today.

Bundle expectation: the corpus est is ~106k tokens (~2.3k confirmed recorded), so the fixed SHA pins and eval sets matter more than raw size until measured counts come in.

## Building quants — step order

Follow in order, rerun earlier steps when later ones move. The steps assume the llama.cpp binaries (`llama-tokenize`, `llama-imatrix`, `llama-quantize`, `llama-perplexity`) are on `PATH`; set `LLAMA_BIN=` if a single binary lives elsewhere.

1. Corpus change. Edit `calibration/*.txt` and/or the SPEC; keep block delimiters clean.
2. Measure. `scripts/count_tokens.sh <path-to-model.gguf> --update-manifest` recounts every file against the pinned base tokenizer and rewrites `manifest.json` counts plus the tokenizer pin. Re-run whenever any source file changes. For the code-forward ratio lint, run `python3 scripts/audit_code_forward.py` — it rewrites `AUDIT.md` per file and is part of every corpus edit, not a once-ever step.
3. Bundle. `cat calibration/*.txt > /tmp/calibration-se.txt` (or the weighted layout once weights are chosen).
4. imatrix. `./llama-imatrix -m model-F16.gguf -f /tmp/calibration-se.txt -o imatrix-se.gguf --chunk 512 -ngl 99`.
5. Quantize. `./llama-quantize --imatrix imatrix-se.gguf model-F16.gguf model-Q*.gguf <TYPE>` — keep `token_embd`, `output.weight`, and the imatrix winners at `q8_0` via `--tensor-type`.
6. Evaluate. `./llama-perplexity` on `eval/heldout-se.txt` and `eval/heldout-general.txt`, plus the perplexity-vs-F16 logit KL per file. Never ship a Q3/Q4 without this. For closer comparisons, score `eval/heldout-se2.txt` too — a larger (23k-token) SE heldout authored fresh from the same house style; zero 12-gram shingle overlap with `calibration/`, so it stays independent of what the quantizer fit.
7. Tune. Move manifest weights at most ±25% per iteration, log the reason, and rerun 2–6. The recompute gate is `scripts/recompute_gate.py` and should be part of the corpus edit chain; any new claim in 03/23 goes in its task table.

## Building oQ quants with oMLX — step order (Apple Silicon, custom corpus + Q8 N-gram)

Same corpus, different toolchain: MLX safetensors quants (`oQ3e/oQ4e/oQ5e`) with the PLE N-gram table held at Q8, built from the `feat/custom-corpus-ngram-q8` oMLX branch. Run on the quant host (128 GB); develop on any Mac.

1. Host env. Apple Silicon, macOS 15+, full Xcode optional (quant needs no custom kernels). Python 3.11–3.13 only (3.14 will not install the pinned MLX):
```bash
brew install python@3.12
git clone <omlx-remote> ~/dev/omlx && cd ~/dev/omlx
git checkout feat/custom-corpus-ngram-q8
/opt/homebrew/opt/python@3.12/bin/python3.12 -m venv .venv-3.12
source .venv-3.12/bin/activate
pip install -e ".[dev]"
python -m pytest tests/test_oq_custom_corpus.py -q   # expect 12 passed
```
2. Corpus. `git pull` this repo on the quant host, then `scripts/count_tokens.sh <model.gguf> --update-manifest` whenever sources changed.
3. Source model. MLX safetensors dir (not GGUF): `config.json` with `model_type: qwen4_exp`, `*.safetensors`, `tokenizer.json`. Either download via the oMLX admin panel or resolve the HF cache snapshot:
```bash
ls ~/.cache/huggingface/hub/models--Qwen--Qwen3.8-Flash-Next/snapshots/
```
4. Launch. Each run first ensures the stock baseline — `<model>-oQ<level>e-stock`, oMLX's own default calibration (the built-in `oqe_code_multilingual` corpus at the tool's default sample settings, default N-gram table width, no vendor slices). It is built once per (source model, level, MTP setting); later runs reuse it, checked against the source snapshot and params recorded in `<out>/build.json`. The requested quant itself: same-name `<version>` reruns overwrite in place (previous log moves to `*.log.prev`, `build.json` re-records what went in); `stock` is a reserved name and `arm-*` comparators are protected from overwrite:
```bash
scripts/omlx_oq4e.sh Qwen/Qwen3.8-Flash-Next coder-8bit-ngram-mtp 8
scripts/omlx_oq3e.sh Qwen/Qwen3.8-Flash-Next coder-q3-ngram8 8      # Q3 trunk, Q8 table
scripts/omlx_oq5e.sh Qwen/Qwen3.8-Flash-Next coder-q5-ngram8 8      # Q5 trunk, Q8 table
scripts/omlx_oq6e.sh Qwen/Qwen3.8-Flash-Next coder-q6-ngram8 8      # Q6 trunk, Q8 table (reference tier)
```
Variants: omit the trailing `8` for the default Q8 table; `PRESERVE_NGRAM_TABLE=1` keeps the table unquantized (bench baseline); `PRESERVE_MTP=0` strips the draft head; `VENDOR_SLICES=chat,tool_calling,reasoning` drops a vendored slice for ablations, `VENDOR_SLICES=` skips the append entirely (authored-only arm). `CORPUS_FILE=<bundle.txt>` replaces the assembled bundle — that is how control arms run. Arm B, generic text through the custom pipeline (built once, then protected from overwrite):
```bash
python3 scripts/make_bundles.py ~/dev/omlx/omlx/oqe_calibration_data.json  # once → bundles/generic.txt
CORPUS_FILE=bundles/generic.txt scripts/omlx_oq4e.sh Qwen/Qwen3.8-Flash-Next arm-b-generic 8
```
`nohup ... &` for the multi-hour runs; the very first run on a fresh host builds stock first, so expect roughly twice the usual time once.
5. Verify. Each script self-checks the report (corpus used, fresh cache, entries) and the config (trunk bits, N-gram `{bits: 8, group_size: 32}`), and writes `<out>/build.json` — source snapshot, bundle sha256, corpus + oMLX commits — the record that survives an overwrite and what the stock reuse check reads. Read `~/oqup/oq<level>e-<version>.log` and the imatrix `expert_coverage` (p05 ≥ 16 is the bar).
6. Serve + evaluate. Symlink the output into `~/.omlx/models` (or `omlx serve --model-dir ~/models-out`), then score heldouts plus LiveCodeBench before calling any version good. Pair at eval time, always: `[stock, arm-b-generic, <current build>]` — current-vs-B isolates the corpus text (same pipeline, different text), current-vs-stock is the headline question (the whole custom pipeline vs out-of-the-box oMLX).

## DeepSeek V4.1 Flash-1017 — oQ2.5e/oQ3e/oQ4e

DeepSeek V4.1 uses the same corpus and control-arm philosophy, but a separate builder because the source, report layout, Engram widths and calibration behavior differ from Qwen4-Exp. The source must be the **original** `deepseek-ai/DeepSeek-V4.1-Flash-1017` checkpoint (FP4/FP8 projections), not an oMLX-converted or MLX-quantized copy. The scripts resolve the newest cached snapshot, or take `--src`:

```bash
scripts/omlx_deepseek_v41_oq25e.sh deepseek-ai/DeepSeek-V4.1-Flash-1017 se-q25-ngram8 8
scripts/omlx_deepseek_v41_oq3e.sh  deepseek-ai/DeepSeek-V4.1-Flash-1017 se-q3-ngram8 8
scripts/omlx_deepseek_v41_oq4e.sh  deepseek-ai/DeepSeek-V4.1-Flash-1017 se-q4-ngram8 8
```

The trailing width is the Engram table: `2 3 4 6 8`, default `8`. There is no 5-bit width. oQ4e keeps the source FP4/FP8 projection precision and does no imatrix or sensitivity pass, so the corpus cannot change its projection bits — it is a source-precision export with an 8-bit table, useful as the high-quality anchor. oQ2.5e and oQ3e do the calibrated mixed-bit allocation; they stream one decoder block at a time from the source shards by default, so the ~307 GB non-Engram source is never resident. `STREAM_CALIBRATION=0` restores the resident path (and warns), `STREAM_CALIBRATION=1` forces streaming. Both passes use this repo's bundle for `calib_dataset` and `sensitivity_calib_dataset`.

DeepSeek outputs are hundreds of GB, so the stock baseline is **not** built by default here (`OQ_SKIP_STOCK=1`). Build it once with `OQ_SKIP_STOCK=0`; it uses oMLX's default calibration corpus and the default 4-bit Engram width. Same-name `<version>` reruns overwrite in place, `arm-*` versions are protected, and `build.json` records the source snapshot, bundle sha256, corpus/omLX commits, Engram width, MTP setting and streaming mode. Control arm B works exactly as for Qwen:

```bash
CORPUS_FILE=bundles/generic.txt scripts/omlx_deepseek_v41_oq3e.sh \
  deepseek-ai/DeepSeek-V4.1-Flash-1017 arm-b-generic 8
```

Heldout PPL runs after a completed build through the V4.1 loader (Engram SSD offload, default routed-expert resident fraction `0.25`; override with `OQ_PPL_EXPERT_FRACTION`). Keep the oMLX server stopped during scoring. `OQ_SKIP_PPL=1` skips it.

## Layout

```text
.
├── calibration/   # 27 sources
├── eval/          # heldout-se.txt, heldout-general.txt, heldout-se2.txt (~23k token larger heldout)
├── bundles/       # control-arm calibration bundles (build input only)
├── manifest.json  # tokens, weights, license (next)
├── SPEC.md        # agreed scope per file
├── TODO.md        # next high-level steps
├── AUDIT.md       # per-file code-forward audit
├── scripts/       # count_tokens.sh, audit_code_forward.py, recompute_gate.py
├── README.md
└── .gitignore
```

License: TBD, must be permissive before first release.
