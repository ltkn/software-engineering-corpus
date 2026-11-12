# Prep script plan — calibration data for oQ-T

Status: plan only, no code yet. Written 2026-11-11.

## 1. Goal

One command turns this repo into **on-policy, chat-formatted calibration and heldout data** for a target model. The text is the model's own answers and real agent sessions, not hand-written blocks. Its output feeds oQ-T steps 0–3 (teacher pass, error-feedback quantization, routing-aware allocation, expert tiers). Corpus blocks stop being calibration text and become **prompts**.

Must hold:
- **One command, resumable.** Every result is content-addressed (hash of source block + settings + model build), so a rerun only redoes what changed.
- **Model-agnostic storage.** Conversations are stored as plain message turns and rendered into each model's chat template only when oQ-T consumes them.
- **Prompts shared, answers per model.** The prompt bank is built once. Answers and agent sessions are regenerated per target model (Qwen first, DeepSeek later).
- **Heldouts sealed.** No heldout prompt, task or repo ever reaches the calibration output, and that is checked mechanically.

## 2. Inputs (prompt sources)

| Source | What it is | How prompts are made |
|---|---|---|
| **A. Corpus, rule-extractable** | 01, 02, 03, 04 (`Q:` blocks), 05, 08, 11, 12, 13, 15, 16, 17, 18, 19, 20, 21, 22, 26, 27, 28, plus the new files in §3 | Per-file rule: everything before the answer label is the prompt (e.g. 01 `Instruction` → cut at `Response`; 02 `Failure` → cut at `Diagnosis`; 05 `Goal`+`Context` → cut at `Investigation`). `Legacy:` blocks become "migrate this to the modern form". |
| **B. Corpus, knowledge cards** | 06, 07, 09, 10, 14, 23, 24, 25, 31 | The model writes the question the card answers. Prompts that copy the card's code or solution are rejected (n-gram overlap check). |
| **C. 04 passages** | 15 passage blocks | Used as plain text in the broad slice, or prompted as "summarize / answer questions about this". |
| **D. Generic seed list** | ~50 task types outside the profile (debug a test, design review, proof, SQL, translation, other languages…) | The model writes prompts from each seed. This is the corpus-free arm. |
| **E. Agent tasks** | Mined Multi-SWE-bench instances plus small tasks on repos from the stack and the new domains | Run as real agent sessions in a sandbox (§5). |
| **F. Broad slice** | General chat, reasoning, multilingual, tool-calling | Seed-generated only: a second seed list (~30 broad task types) answered by the model. The vendored Jundot slices are **not** used for oQ-T (they stay in `vendor/` for the legacy oQe scripts only). |
| **Heldouts** | `eval/heldout-*.txt`, `eval/mined-holdout-ids.txt`, plus held-out tasks for each new domain | Same pipeline, written to a separate output. |

Files 29 and 30 stay unweighted (share 0) and are skipped unless enabled.

## 3. New and expanded corpus domains

Goal of the corpus: **opinionated but broad software engineering, end to end.** New files are authored as **task-first blocks** (the "problem header" kind), so prompt extraction is rule-based from day one. A reference solution is optional: it's used only for the leakage check and sanity review, not as calibration text. That makes authoring much cheaper than the current full blocks.

Block shape for new files: `Goal:` / `Context:` (versions, board or engine, constraints) / `Acceptance:` (how a correct answer is checked) / optional `Reference:`.

| File | Scope | Version baselines to pin when authoring | Sandbox validator |
|---|---|---|---|
| **20-observability (expanded)** | Opinionated stack: OpenTelemetry (SDKs, Java agent, Collector pipelines and processors), Micrometer in Spring Boot 4, Prometheus (PromQL, recording and alerting rules, native histograms), Alertmanager routing, Grafana dashboards as code, Loki (LogQL), Tempo (TraceQL), continuous profiling (Pyroscope), eBPF auto-instrumentation, SLOs with multi-window burn-rate alerts, Kubernetes monitoring (kube-state-metrics, node-exporter), synthetic checks (blackbox exporter), frontend error tracking. **Splunk**: SPL searches and stats, HTTP Event Collector ingestion, the Splunk distribution of the OTel Collector, Universal Forwarder, props/transforms field extraction, saved searches, alerts and dashboards. Adds task-first blocks to the existing file | Current OTel spec and Collector, Prometheus 3.x, Grafana stack, current Splunk Enterprise | `promtool check rules` and `promtool test rules`, `otelcol validate`, `amtool check-config`, a local LGTM stack in Docker for agent tasks, the `splunk/splunk` image with a dev license for SPL and HEC tasks (amd64 image: runs under Rosetta emulation in OrbStack/colima, slower) |
| **32-godot** | GDScript 4.x (about 90%) plus GDShader: scenes and nodes, signals, physics, input, UI, resources, animation, tilemaps, save systems, export presets, performance. C# is out of scope | Current Godot 4.x stable | `godot --headless` script check and run, GUT or gdUnit4 tests |
| **33-arduino** | Arduino C++ on AVR, RP2040 and the **Arduino-ESP32 core**: GPIO, interrupts, timers, PWM, I2C/SPI/UART drivers, non-blocking state machines, low power, memory limits, libraries | Current Arduino AVR, RP2040 and ESP32 (3.x, ESP-IDF 5.x based) cores | `arduino-cli compile` per board (FQBN matrix), host-side unit tests of pure logic, Espressif QEMU for ESP32/S3/C3 |
| **34-rust** | Ownership and borrowing, traits and generics, error handling, async (tokio), unsafe boundaries, FFI, cargo workspaces, testing, clippy-clean idioms | Current stable Rust and edition | `cargo build`, `cargo test`, `cargo clippy -D warnings` |
| **35-rust-embedded** | `no_std`, embedded-hal 1.0 traits, PAC/HAL layers, embassy async, RTIC, interrupts and critical sections, DMA, defmt logging, memory layout, **probe-rs** (flashing, `probe-rs run` as cargo runner, RTT, debugging), and the **Espressif Rust stack**: `esp-hal` (no_std), the ESP Wi-Fi/BLE crates, embassy on ESP, `esp-idf-hal`/`esp-idf-svc` (std on top of ESP-IDF), `espup` toolchains (Xtensa) vs upstream RISC-V targets, `espflash` | Current embedded-hal, embassy, RTIC, probe-rs and esp-hal releases (crate names in the ESP Rust stack have moved recently; verify at authoring) | `cargo build` for `thumbv7em-none-eabihf`, `riscv32imc/imac-unknown-none-elf` and the Xtensa targets; QEMU Cortex-M (lm3s6965) and Espressif QEMU runs; probe-rs is covered as knowledge only (no hardware) |
| **36-esp-idf** | ESP-IDF in C: project and component layout, `idf.py`, menuconfig/Kconfig, FreeRTOS tasks and queues, event loop, Wi-Fi, BLE (NimBLE), Thread/Zigbee (802.15.4), MQTT/HTTP clients, NVS, partition tables, OTA with rollback, **secure boot v2, flash encryption, NVS encryption**, power management and deep sleep, ULP, logging and core dumps | Current ESP-IDF 6.x stable (5.x for unmigrated projects) | `idf.py build` per target in the `espressif/idf` Docker image, Espressif QEMU for ESP32/S3/C3, host-side unit tests |

**Espressif board coverage** (applies to 33, 35, 36, 47 and 48). **Weight tasks toward the newest chips and their official dev kits** (ESP32-C5, ESP32-C6, ESP32-P4, ESP32-S3, plus the newest additions to the lineup at authoring time, such as the C61 and H-series successors). The classic ESP32 appears mainly in migration tasks ("port this ESP32 project to the C6"). No real boards are available, so every task must be checkable by build, emulation (Espressif QEMU covers ESP32/S3/C3; newer chips are build-only) or host-side tests:

| Chip | Core | Notable for |
|---|---|---|
| ESP32 | Xtensa LX6 dual-core | Classic Wi-Fi + BT Classic + BLE; largest legacy base |
| ESP32-S2 | Xtensa LX7 single-core | USB OTG, no BLE |
| ESP32-S3 | Xtensa LX7 dual-core | USB OTG, vector instructions for ML/DSP, cameras and displays |
| ESP32-C2 | RISC-V | Low-cost Wi-Fi + BLE |
| ESP32-C3 | RISC-V | Low-cost Wi-Fi + BLE, built-in USB-JTAG (probe-rs friendly) |
| ESP32-C5 | RISC-V | Dual-band Wi-Fi 6 |
| ESP32-C6 | RISC-V | Wi-Fi 6, BLE, Thread/Zigbee (802.15.4), LP core |
| ESP32-H2 | RISC-V | Thread/Zigbee + BLE, no Wi-Fi |
| ESP32-P4 | RISC-V high-performance | No radio, MIPI camera/display, pairs with a C6 for connectivity |

Verify the chip list and capabilities against Espressif's current product pages when authoring, following the version-verification rule.

Each new file also gets:
- an **agentic task set** (§5) built on small real projects: an instrumented Spring service with a local LGTM stack, a Godot demo game, an Arduino sketch library, a Rust crate, an embassy firmware, an `esp-hal` firmware, an ESP-IDF sensor-node project;
- **held-out tasks** sealed in `eval/`;
- a **manifest share**, starting around 2.5–3 each, to be tuned by measurement like the rest.

Existing gates (fact checks, texture, code-forward ratio) are not extended to these files. Only `lint_format` (block separators and labels) applies.

## 4. Pipeline stages

Each stage reads the previous stage's cached output and writes its own, keyed by content hash.

1. **Split.** Read `calibration/*.txt` into blocks with file, index and sha. Skip `#` header lines.
2. **Classify.** Apply the per-file rule table from §2. Unknown shapes go to the model-derived path and are listed in the report, never silently dropped.
3. **Derive prompts** (source B and seeds D). Model with thinking off, low temperature. Apply the leakage check against the block's own text.
3b. **Vary** (§4b). Rewrite each prompt into other voices, so the bank looks like real user traffic rather than one clean author.
4. **Sample.** Choose how many answers each prompt gets, using the manifest shares as sampling weights (this finally makes the weights do something). Default is two or three samples per prompt.
5. **Generate answers.** Model with thinking on, at the model's recommended thinking-mode sampling (Qwen: temperature 1.0, top_p 0.95, top_k 20). Reasoning effort follows §4a. Requests are sent several at once through the oMLX server's OpenAI-compatible API.
6. **Chain long sessions.** Group related prompts (same file or topic) into multi-turn conversations of 16–32k tokens, where each turn sees the earlier answers.
7. **Agent sessions** (§5).
8. **Filter** (§7).
9. **Mix** to the target budget (§6).
10. **Seal and check heldouts** (§8).
11. **Write outputs and the report** (§9).

## 4a. Reasoning effort — generic levels

The script uses three generic levels and maps them to each model's own names, so nothing model-specific leaks into the prompts or the mix:

| Generic level | Meaning | Qwen3.8-Flash-Next | DeepSeek V4.1 |
|---|---|---|---|
| `low` | The model's lowest thinking level (thinking still on) | `low` | Lowest value of its numeric effort scale |
| `medium` | The middle level | `medium` | Middle value |
| `max` | **Exactly one** level: the model's highest, whatever it's called (`max`, `xhigh` or `high`) | `xhigh` | Highest value |

- The mapping lives in a small per-model table, read from the model's chat template or encoding reference when possible. An unknown model fails with a clear message instead of guessing.
- Default mix: **~70% `max`** (your normal setting), ~15% `medium`, ~15% `low`. The per-level split is in the report, so it can be tuned.
- Thinking off is used only for prompt derivation (stage 3), never for calibration answers.

## 4b. Variation pass

**Why:** the corpus prompts are clean, complete and written in one house style. Real requests are terse, messy, partial, pasted, or not in English. Calibration data benefits more from that variety than from polish, and rewriting the corpus by hand would make it *less* varied (one author). So the corpus stays as written and the variety is generated.

**How:**
- For each prompt (rule-made or derived), the model writes **one or two variants**, thinking off, each in a voice drawn from this list:

| Voice | What it looks like |
|---|---|
| `terse` | One line, no pleasantries: "keyset pagination for users, pg18, offset is too slow" |
| `paste-first` | The error, log or code pasted first, the question last and short |
| `rambling` | Partial context, a guess at the cause, extra detail that isn't needed |
| `junior` | Unsure wording, asks for an explanation as well as the fix |
| `non-native` | Correct meaning, non-native English phrasing |
| `french` | The same request in French (the model answers in the language asked) |

- **The original is always kept.** Variants are extra rows linked to the original's ID, never replacements.
- **Weights are preserved.** A block's manifest share is split across its original and variants, so a file's total weight doesn't grow because it got varied.
- **Default split:** about half of the prompt rows are originals; voices are drawn evenly, except `french`, which is capped at about 10% of variants.
- **Checks on every variant:**
  - the same leakage check as derive (no copying the answer part of the block);
  - **task preservation:** the variant must keep the key technical terms of the original (names of APIs, tools, error codes, versions). A variant that drops most of them is rejected, because it has changed the task;
  - code, logs and error text pasted in the original must survive verbatim in `paste-first` variants.
- **Cached by content hash** like derive, with its own version tag, so changing the voice list only regenerates what changed.
- **Report:** variants per voice, rejection rate per voice and per file, and a few random samples per voice for a quick human read.

**Not varied:** the 04 passages (plain text, no prompt), and the heldout prompts. Heldouts are scored on their original wording only, so the evaluation stays comparable across runs.

## 5. Agent sessions — how agents work, in your stack

The most realistic data in the set: the model working on real tasks, with real tool results.

- **Harness:** a minimal agent loop using the target model's **native tool-call format**. Tools: list files, read file (with line numbers), grep, apply patch, run command (allowlisted), finish. Nothing else, so sessions look like real coding-agent traffic.
- **Sandbox: Docker** (via OrbStack or colima on the Mac). A throwaway working copy per task, mounted into a Linux arm64 container, with no network except package registries and a time limit per command. There are **no hardware runs**: no boards are available, so embedded and LoRa tasks are checked by building for the target, by emulation where it exists, and by host-side tests.
- **Toolchains in the sandbox images:** JDK 25 + Maven/Gradle, Node + TS 6/7, Postgres 18 and Kafka 4.3 containers, Python 3.14, the OTel Collector + Prometheus + Grafana/Loki/Tempo stack, Rust stable + embedded targets + `espup` Xtensa toolchain + `espflash` + probe-rs, QEMU (Cortex-M and Espressif fork), Godot 4 headless (Linux arm64), arduino-cli with the AVR, RP2040 and ESP32 cores, the `espressif/idf` image for ESP-IDF, plus the §14 validators (shellcheck, bats, actionlint, Jenkins, Terraform/OpenTofu, Helm, kind, CMake + clang tooling, Valkey, Garage, Toxiproxy, k6, Playwright, Mermaid CLI, syft/grype/cosign) and the `splunk/splunk` image. Split into a few images by domain rather than one huge image.
- **Task sources:** mined Multi-SWE-bench instances (holdout IDs excluded), plus 10–20 small tasks per domain on the demo projects from §3.
- **Recorded:** the whole session (system prompt, tool definitions, every call and result, thinking), plus the outcome (tests pass, fail, or gave up) and the token count.
- **Kept:** finished sessions, including honest failures. Dropped: loops, broken tool calls, sandbox crashes.

## 6. Mix and budget

Starting mix, to be tuned against KL to the BF16 teacher and routing flips:

| Slice | Share |
|---|---|
| Agent sessions (stack + new domains) | ~40% |
| Corpus prompts answered single-turn or chained | ~20% |
| Generic seed prompts | ~20% |
| Broad slice | ~20% |

- **Budget:** ~1M tokens total for oQ-T steps 0–3. That means roughly 25–40 agent sessions of 10–16k tokens each, plus the rest. QAT would need much more and is out of scope.
- **Two output profiles** from the same run, so the corpus question is testable:
  - `generic`: D + F only;
  - `profile`: the full mix.

## 7. Filters

- Truncated output (hit the token limit) or empty answer.
- Repetition loops (repeated n-grams beyond a threshold).
- Broken tool calls: invalid JSON, or a tool or arguments that don't exist.
- Refusals and hedged non-answers. These are expected mostly on 31 and 08. Prompts there are framed as the authorized engagement they describe, and remaining refusals are dropped and counted.
- Length outliers on both ends.
- The report shows the drop rate per source and per file. A file with a high drop rate is a signal to fix its prompts, not to loosen the filter.

## 8. Heldout sealing

- Heldout prompts, tasks and demo-project tasks are processed into a separate `heldout` output.
- **Checks that fail the run:**
  - any heldout prompt or task ID in the calibration output;
  - 12-gram overlap between a heldout prompt and any calibration prompt or answer above a small threshold.
- Agent heldouts run on separate tasks, never on a different sample of the same task.

## 9. Outputs

Written outside the repo (large), under `~/oqup/prep/<run>/`. The prompt bank (`blocks.jsonl`, `prompts.jsonl`, the derive cache) is shared by every target model; answers and sessions go into a per-model folder under the same run:
- `calibration-profile.jsonl` and `calibration-generic.jsonl`: one conversation per line, plain turns (system, user, assistant with thinking, tool calls and results), plus metadata: source, file, block sha, sample seed, model build, settings, token count, filter verdict.
- `heldout.jsonl`: same format.
- `report.md`: counts and tokens per source, file and domain, filter drop rates, agent outcome rates, leakage-check results, the model build used, and the oMLX and corpus commits.
- `prep.json`: what went in (similar to `build.json`), used by oQ-T to confirm which prep it is consuming.

The report summary (no data) can be committed to the repo for history.

## 10. Command shape

One command with the target model, the oMLX server address, and the run name. Optional switches:
- choose the stages to run (default all);
- choose the profile(s) to write;
- turn agent sessions off for a quick pilot;
- override the token budget and samples per prompt;
- dry run, which prints the plan, counts and estimated time without generating anything.

## 11. Running it on the 128 GB Mac

- **Generator:** the best Qwen build that fits (oQ5/oQ6 trunk with the n-gram table offloaded to SSD if oMLX supports it for Qwen; otherwise oQ4e).
- **Pilot first:** about 50 prompts plus 3 agent sessions, to measure real throughput and drop rates before the full run.
- **Expected time:** prompt derivation is short. Answers and agent sessions take hours to overnight; the pilot gives the real number.
- **Practicalities:** keep the laptop plugged in and ventilated, keep the oMLX server dedicated to the run, and make every stage resumable after an interruption.

## 12. Build order

1. Rule table and the split, classify and derive stages, checked against the current 31 files (every block accounted for). **Done 2026-11-11:** `scripts/prep_calibration.py` (`extract`, `derive`, `all`). All 1,564 blocks are accounted for: 1,124 rule-made prompts, 431 knowledge cards for the model to derive, and 9 passages from 04 for the broad slice. Derive was tested against a stub server (leak rejection, retry, cache, merge); its first real run against oQ5 is still to do.
2. Variation pass (§4b), then answer generation, filters, and the report, run as the pilot. **Agent sessions and long context done 2026-11-11:** `scripts/agent_harness.py` (tool set, Docker sandbox with no network, step and context caps, check command), the `agent` stage, 12 authored tasks across Python, TypeScript, Java, Rust, Go, C++ and shell with reference solutions and `agent_tasks/verify_tasks.sh` (**2026-11-12:** images bumped to the latest stable toolchains, pinned; Rust checks now require `cargo fmt` and `clippy -D warnings` with typed errors; five Spring Boot 4.1 tasks on JDK 27 with PostgreSQL 18 and Flyway: a NOT NULL column with backfill, virtual threads with concurrent downstream calls, ThreadLocal to ScopedValue, a JPA N+1 with a missing foreign-key index, and RFC 9457 problem details; 17 tasks); render emits whole long documents (sessions and chained conversations) and the oQ-T sweep calibrates on 25% of tokens in 32k windows that start at document boundaries. **Partly done 2026-11-11:** `generate` (generic effort levels, share-weighted sampling, per-request cache, pilot time estimate, filters) and `render` (chat template with thinking, special-token check) exist, and `scripts/oqt_pipeline.sh` chains extract → derive → generate → render → oQ-T build → score, idempotent and resumable (see OQT.md). The variation pass is still to do. **Seeds and profiles done 2026-11-11:** `seeds/generic.txt` (50 software seeds outside the stack) and `seeds/broad.txt` (32 non-coding seeds, including multilingual and tool-calling ones) feed the `seed` stage; `generate` and `render` take `--profile profile|generic` and `--mix` (default corpus 50 / generic 25 / broad 25 until agent sessions exist), carry tool definitions and tool calls through to the chat template, and share request caches across runs (`--cache-root`, `~/oqup/prep-cache` in the pipeline).
3. Author 32–48 and the 20 expansion as task-first blocks, about 30–50 each to start, plus their held-out tasks. Do the most agent-relevant first: 37 (git), 38 (shell), 39 (CI/CD), then the rest.
4. Agent harness and Docker sandbox images, starting with the Rust and Java tasks (the simplest toolchains), then git/shell/CI, observability, C/C++, Godot, Arduino, embedded Rust and ESP-IDF, then the remaining domains.
5. Mixing, both profiles, and heldout sealing.
6. Full run, then hand off to oQ-T step 0.

## 13. Decisions

Settled 2026-11-11:
- **Sandbox:** Docker through OrbStack or colima. No hardware runs (no boards available).
- **Object storage:** Garage (Deuxfleurs) replaces MinIO as the reference S3 server.
- **Godot:** GDScript only (plus GDShader, Godot's shader language); no C#.
- **Embedded:** broad Espressif coverage (table in §3) across Arduino, ESP-IDF and Rust, newest chips first; probe-rs included as knowledge only. Non-Espressif targets: AVR, RP2040, Cortex-M through QEMU. LoRa, LilyGO and Heltec devices and Reticulum in file 47; sensors and embedded ML in file 48.
- **Broad slice:** seed-generated; no Jundot for oQ-T.
- **Reasoning effort:** generic `low` / `medium` / `max` (§4a), ~70% `max`.
- **Observability:** add Splunk alongside the OTel/Prometheus/Grafana stack.
- **Further domains:** all ten in §14, with Jenkins in 39 and Mermaid in 45, plus 47 (LoRa/Reticulum) and 48 (sensors and embedded ML).
- **Starting manifest shares** for the new files, tuned later by measurement (±25% per iteration, as for the existing files):

| File | Share | File | Share |
|---|---:|---|---:|
| 32-godot | 2.0 | 41-data-stores | 2.5 |
| 33-arduino | 2.5 | 42-distributed-systems | 2.5 |
| 34-rust | 3.0 | 43-performance | 2.0 |
| 35-rust-embedded | 2.5 | 44-frontend-platform | 2.0 |
| 36-esp-idf | 2.5 | 45-docs-writing | 2.0 |
| 37-git-code-review | 3.0 | 46-supply-chain | 2.0 |
| 38-shell-cli | 3.0 | 47-lora-reticulum | 2.0 |
| 39-cicd-iac | 3.0 | 48-sensors-edge-ml | 2.5 |
| 40-c-cpp | 2.5 | | |

The 20-observability expansion keeps its existing share. The new files add 41.5 to the existing total of 103.0, so the stack's effective share falls accordingly; that's the intended trade for breadth. The manifest is updated when each file is created, not before.

- **No hand rewrite of the existing corpus.** The blocks stay as written (reference answers kept, old oQe arms stay comparable). Variety comes from the variation pass (§4b) instead.

Still open: nothing blocking. Step 1 is built; next is the variation pass and step 2.

## 14. Further domains (agreed 2026-11-11)

Same task-first block shape as §3. Each file also gets agent tasks on a small demo project and sealed held-out tasks.

| File | Scope | Sandbox validator |
|---|---|---|
| **37-git-code-review** | Rebase and interactive history editing, conflict resolution, bisect, cherry-pick and revert, worktrees, commit messages, PR descriptions, review comments (finding bugs, asking for tests, approving with conditions), blame and log archaeology | Scripted repos in known states (conflict, bad commit to bisect); success checked with git commands and the repo's tests |
| **38-shell-cli** | Bash (strict mode, quoting, traps, arrays), POSIX sh, jq, sed/awk, find/xargs, grep/ripgrep, curl, Makefiles, small CLI tools, cron/systemd timers | `shellcheck`, `bats` tests, expected-output fixtures |
| **39-cicd-iac** | GitHub Actions (reusable workflows, matrix, caching, OIDC to cloud), **Jenkins** (declarative Jenkinsfile, shared libraries, agents, credentials binding, Jenkins Configuration as Code), GitLab CI basics, Terraform/OpenTofu (modules, state, plan review, drift), Helm and Kustomize, Kubernetes depth (probes, resources, PDBs, network policies, RBAC, HPA), progressive delivery (Argo Rollouts / Flagger) | `actionlint`, Jenkins declarative linter against a `jenkins/jenkins` container, `terraform validate` + `tflint` + plan against a local provider, `helm lint` + `helm template`, `kubeconform`, a `kind` cluster for apply tests |
| **40-c-cpp** | Modern C (C17/C23) and C++ (C++20/23): RAII, smart pointers, move semantics, templates and concepts, `std::span`/`string_view`, undefined behavior, CMake (targets, presets, FetchContent), sanitizers, clang-tidy, embedded-friendly C++ (no exceptions, no heap, `constexpr`) | CMake build + `ctest`, ASan/UBSan runs, `clang-tidy` |
| **41-data-stores** | Redis/Valkey (data structures, TTLs, caching patterns, streams, locks and their limits), SQLite (WAL, embedded use), S3-compatible object storage with **Garage** (Deuxfleurs) as the reference server (layout, zones and replication, keys and bucket permissions, presigned URLs, multipart, website hosting), schema migrations (Flyway, Liquibase; expand/contract), cache invalidation | Valkey, Garage and Postgres containers; Flyway/Liquibase migrate and rollback runs |
| **42-distributed-systems** | Idempotency keys, retries with backoff and jitter, timeouts and deadlines, circuit breakers, transactional outbox, sagas, exactly-once vs effectively-once, consistency trade-offs, clock skew, leader election, backpressure | Testcontainers integration tests with Toxiproxy fault injection (latency, drops, partitions) |
| **43-performance** | Measure-first method, profilers and flame graphs (JFR + async-profiler, perf, cargo flamegraph, browser devtools), benchmarking (JMH, criterion, pytest-benchmark), load testing with k6 (scenarios, thresholds), latency percentiles, memory and allocation analysis | k6 runs against the demo service with thresholds, JMH/criterion harnesses, perf inside a Linux container |
| **44-frontend-platform** | Semantic HTML, modern CSS (grid, container queries, cascade layers), accessibility (WCAG 2.2, ARIA, keyboard, focus), Core Web Vitals, images and fonts, Vite and build tooling, bundle analysis | Playwright + axe-core, Lighthouse CI budgets, `vite build`, stylelint |
| **45-docs-writing** | READMEs, ADRs, changelogs (Keep a Changelog, conventional commits), API docs (OpenAPI descriptions), runbooks, migration guides, **Mermaid** diagrams (flowchart, sequence, state, ER, C4-style) | `markdownlint`, link check (`lychee`), Mermaid CLI (`mmdc`) render check, OpenAPI lint |
| **46-supply-chain** | Lockfiles and reproducible builds, SBOMs (CycloneDX/SPDX), vulnerability scanning and triage, Renovate/Dependabot configuration, artifact signing and verification (Sigstore/cosign), SLSA provenance, pinning actions and base images | `syft` SBOM generation, `grype`/`osv-scanner`, `cosign` sign and verify against a local registry, Renovate config validator |

| **47-lora-reticulum** | **LoRa fundamentals**: spreading factor, bandwidth, coding rate, airtime and duty-cycle limits, regional bands (EU868, US915), link budget; radios (SX1262, SX1276, SX1280, LR1121); RadioLib on Arduino and ESP-IDF, `lora-phy` on embassy (Rust); PlatformIO projects. **LilyGO devices** on recent Espressif chips: T-Beam Supreme (ESP32-S3, SX1262, GPS, AXP2101 power management), T3-S3, T-Deck / T-Deck Plus, and the newest LilyGO LoRa boards at authoring time (pin maps verified against LilyGO's repos). **Heltec devices**: WiFi LoRa 32 V4 (ESP32-S3 + SX1262) as the primary Heltec target, plus the newest Heltec LoRa boards at authoring time (pin maps verified against Heltec's docs and repos). **Reticulum Network Stack**: identities, destinations, announces, links, transport nodes and path discovery, interface configuration (RNode, TCP, UDP, local), RNode firmware and `rnodeconf`, LXMF messaging, Sideband and NomadNet, writing Reticulum apps in Python, its security model (encryption by default, no source addresses) | `arduino-cli`/PlatformIO builds for the LilyGO targets, RNode firmware builds, host-side unit tests of airtime and packet logic, **multi-node Reticulum networks in Docker** (several RNS nodes over TCP/UDP interfaces exchanging LXMF messages). This is fully testable without radios |
| **48-sensors-edge-ml** | **Sensor engineering**: I2C/SPI/UART drivers, sampling rates, calibration, drift, filtering (median, moving average, Kalman), power budgets. **Temperature and humidity**: SHT4x, BME280, DS18B20. **Gas detection**: MQ-series analog sensors (burn-in, load resistor, calibration curves), SGP41 VOC/NOx index, SCD4x CO2, BME688 gas scanning, ENS160, electrochemical CO cells, and the limits of hobby sensors (never a substitute for certified life-safety detectors). **mmWave radar**: HLK-LD2410/LD2450 (24 GHz presence and multi-target tracking, UART protocol, zone configuration), 60 GHz modules for breathing and heart-rate sensing (e.g. Seeed MR60BHA2, Infineon BGT60). **Wi-Fi CSI presence sensing**: ESP-IDF CSI API, Espressif's `esp-csi` tools, amplitude and phase processing, motion vs presence, calibration, environmental limits. **Embedded ML**: TensorFlow Lite Micro (LiteRT for Microcontrollers), ESP-DL and ESP-NN acceleration on S3/P4, Edge Impulse workflow, int8 quantization, feature extraction, keyword spotting, anomaly detection on sensor streams, latency and memory budgets. **Integration**: ESPHome (YAML devices and custom components), MQTT, Home Assistant discovery | Firmware builds for the target chips; host-side tests that **replay recorded sensor and CSI datasets** through the processing code; a Python container that trains a tiny model, converts it to int8 and runs it through TFLite Micro on the host with size and latency checks; `esphome config` and `esphome compile` |

Every new file dilutes the others' shares. That's the intended trade for "broad", so expect each file to get a smaller weight.
