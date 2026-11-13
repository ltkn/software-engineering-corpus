# software-engineering-corpus

Domain-focused calibration corpus for oQ-T (MLX, oMLX) quants of coding models and coding agents.

Goal: low-bit quants that keep our stack (Java/Spring, TS 6→7, Vue/TanStack, Postgres, Kafka) with strong security — and keep reasoning first. The corpus is mostly prompts: the model being quantized answers them, and its own answers (thinking, tool calls, agent sessions) become the calibration text.

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

Weights (default): ~65–70% stack, ~20% thinking (01–05), ~10% finance+anchor. The security band (06–09 plus 31) holds 18%, with `31` funded inside the band: 06 3.5, 07 5.0, 08 3.5, 09 3.0, 31 3.0. Under oQ-T a weight scales how many answers a file's prompts get; the generation budget sets the volume. Block counts and weights in root `manifest.json`.

## oQ-T quants — one command

`scripts/oqt_pipeline.sh 4 v1` runs everything on the 128 GB Mac: your local model answers the corpus prompts, the answers become the calibration text, and an oQ-T quant of Qwen3.8-Flash-Next (or a fine-tune of it) is built from them (streamed, idempotent, resumable). Step-by-step instructions for the 128 GB Mac, setup, options and troubleshooting: **[OQT.md](OQT.md)**. Models are described by profiles in `models/`; a fine-tune is a variant (`OQT_VARIANT=uncensored`). `scripts/oqt_pipeline.sh results` compares every quant.

## Layout

```text
.
├── calibration/   # corpus sources (mostly prompts the model answers)
├── seeds/         # generic.txt, broad.txt: seed lists the model writes prompts from (oQ-T)
├── agent_tasks/   # coding-agent tasks and their Docker sandbox images (oQ-T)
├── eval/          # heldout-written-se.txt: independent written SE text for M3 and PPL (the other
│                  # heldouts are the model's own held-out answers, made per run)
├── models/        # one profile per model: architecture, official repo, request and template settings
├── manifest.json  # blocks and sampling shares per corpus file
├── OQT.md         # oQ-T pipeline: setup, run, options, troubleshooting
├── PREP_PLAN.md   # design of the oQ-T calibration data
├── SPEC.md        # agreed scope per file
├── TODO.md        # next high-level steps
├── scripts/       # oqt_pipeline.sh, omlx_oqt.sh, prep_calibration.py, agent_harness.py,
│                  # model_profile.py, score_vs_bf16.py, ppl_heldout.py, results.py;
│                  # corpus lints (lint_format, lint_duplicates, recompute_gate); testing/
├── README.md
└── .gitignore
```

License: TBD, must be permissive before first release.
