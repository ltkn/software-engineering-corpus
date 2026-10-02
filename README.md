# software-engineering-corpus

Domain-focused calibration corpus for GGUF-quantized coding models and coding agents.

Goal: Q4–Q8 quants that keep our stack (Java/Spring, TS 6→7, Vue/TanStack, Postgres, Kafka) with strong security — and keep reasoning first. Custom `llama-imatrix` beats generic WikiText; Q4 gains most, Q8 ignores imatrix (baseline only).

## Corpus

24 UTF-8 `.txt` files ordered by criticality. `01`–`10` filled; `11`–`24` empty placeholders.

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
└── 24-react.txt
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

./llama-perplexity -m model-Q4_K_M.gguf -f eval/heldout-se.txt -ngl 99
./llama-perplexity -m model-Q4_K_M.gguf -f eval/heldout-general.txt -ngl 99
```

`eval/` is never part of the bundle. Never truncate with `--chunks` for a real imatrix.

## Layout

```text
.
├── calibration/   # 24 sources
├── eval/          # heldout-se.txt, heldout-general.txt
├── manifest.json  # tokens, weights, license (next)
├── SPEC.md        # agreed scope per file
├── README.md
└── .gitignore
```

License: TBD, must be permissive before first release.
