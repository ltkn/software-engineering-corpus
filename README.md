# software-engineering-corpus

Domain-focused calibration corpus for GGUF-quantized coding models and coding agents.

Goal: Q4–Q8 quants that keep our stack (Java/Spring, TS 6→7, Vue/TanStack, Postgres, Kafka) with strong security — and keep reasoning first. Custom `llama-imatrix` beats generic WikiText; Q4 gains most, Q8 ignores imatrix (baseline only).

26 UTF-8 `.txt` sources in the bundle-scope set (01-26), the two adversarial-hygiene categories (27/28) weighted at share 2/1, plus 29/30 fenced-v0 experiments (29-llm-integration, 30-experimentation-and-flagging) at share 0 in `manifest.json`.

## Corpus

26 UTF-8 `.txt` files ordered by criticality, plus the adversarial 27-28 category pair, plus the fenced experimental 29-30 pair. All filled; see SPEC.md for per-file scope and actuals.

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
└── 30-experimentation-and-flagging.txt
```

Format: plain blocks separated by blank-line `---` blank-line. No frontmatter or headings in `.txt`. Mix per file: real code, why-explanations, bad→diagnosis→fix, short agent traces. No secrets.

Security is cross-cutting: `11` (@PreAuthorize, ownership, JWT, CSRF/CORS), `12` (roles/GRANT/RLS, SECURITY DEFINER, search_path, params), `13` (TLS/SASL/ACLs), `16` (XSS, token storage, CSP), `14` (BOLA/BFLA, auth, SSRF, resource limits). `21` spans Linux, Docker, Nginx, CI/CD, K8s (full-stack ops).

Weights (default): ~65–70% stack, ~20% thinking (01–05), ~10% finance+anchor. Bundle target ~200–250k tokens. Counts in root `manifest.json`.

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
6. Evaluate. `./llama-perplexity` on `eval/heldout-se.txt` and `eval/heldout-general.txt`, plus the perplexity-vs-F16 logit KL per file. Never ship a Q3/Q4 without this.
7. Tune. Move manifest weights at most ±25% per iteration, log the reason, and rerun 2–6. The recompute gate is `scripts/recompute_gate.py` and should be part of the corpus edit chain; any new claim in 03/23 goes in its task table.

## Layout

```text
.
├── calibration/   # 26 sources
├── eval/          # heldout-se.txt, heldout-general.txt
├── manifest.json  # tokens, weights, license (next)
├── SPEC.md        # agreed scope per file
├── TODO.md        # next high-level steps
├── AUDIT.md       # per-file code-forward audit
├── scripts/       # count_tokens.sh, audit_code_forward.py, recompute_gate.py
├── README.md
└── .gitignore
```

License: TBD, must be permissive before first release.
