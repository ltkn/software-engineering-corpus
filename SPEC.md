# Corpus spec

Agreed scope per calibration file. Implementation must match this file; change the spec first, then the source.

## Global conventions

- Format: UTF-8, LF, plain blocks separated by blank-line `---` blank-line. No frontmatter, no `#` headings, no code fences in `.txt`. Code raw. No block contains a bare `---` line; block labels (`Failure:`, `Diagnosis:`, `Draft:`, `Correction:`, `Legacy:`) are the only in-block structure.
- Files ordered by criticality (thinking → security → stack → supporting → fenced). Filenames are stable IDs; `manifest.json` bundle order defines the build.
- Baselines, state of the art. Ledger as of 2026-10-03, verified against primary or release-tracking sources on that date.
  - Java 25 LTS pinned. JDK 26 (2026-03-17) and JDK 27 (2026-09-15) are non-LTS neighbors and appear only in labeled neighbor blocks. Next LTS is expected as JDK 29, 2027-09.
  - Spring Boot 4.1 (4.1.0 released 2026-06-10) on Framework 7.0.x, Security 7.1, Data 2026.0, Micrometer 1.17. Boot 4.2 and Framework 7.1 are expected 2026-11 (RestTemplate deprecated 7.0, removal-marked 7.1, gone in 8).
  - TypeScript 7.0 stable (2026-07) with 6-compat; 6.0 (2026-03) was the bridge release. No stable programmatic API until 7.1, so Vue/Svelte/Angular template tooling stays on 6. Configs must pass both compilers until the editor moves to 7.1.
  - PostgreSQL 18 is the stable baseline. PG 19 is in beta (beta 4 on 2026-09-24, RC expected early October); PG 19 content enters only after GA.
  - Kafka 4.3 KRaft-only (4.3.0 on 2026-05-22, 4.3.1 current patch).
  - Vue 3.5.x stable (3.5.43, 2026-09-17). Vue 3.6 is in RC (rc.9, 2026-09-18) with Vapor Mode feature-complete but not stable. TanStack Query v5 (vue-query 5.104.x).
  - Node 24 LTS baseline (EOL 2028-04-30). Node 22 is maintenance until 2027-04-30. Node 26 is promoted to LTS in 2026-10. From Node 27 there is one major a year and every release becomes LTS. Node 20 is EOL.
  - Python: current stable verified at implementation time; 3.15 is due around 2026-10.
  - Kubernetes: Gateway API is the default for new work. The ingress-nginx controller was retired in 2026-03; the Ingress API itself remains.
  - Stripe: newest major is `endive` (2026-09-30), first major after `dahlia`. Monthly releases are non-breaking, majors come twice a year.
  - Taxonomies: OWASP Top 10:2025 (final 2026-01); OWASP API Security Top 10 2023; OWASP Top 10 for Agentic Applications 2026 (published 2025-12-09, ASI01–ASI10).
  - Protocol stamps: RFC 9700 and the OAuth 2.1 draft stamp in 07.
  - Offensive-security stamps: MITRE ATT&CK Enterprise v19.2 is the tactic/technique vocabulary (fetched 2026-10-07). Technique IDs are cited inline as stamps in 31 and where 08 maps a probe to a technique; ATT&CK prose is never reproduced. OWASP WSTG v4.2 and PTES are named as methodology vocabulary only, not copied. Incident claims carry the CVE ID plus the NVD publish date; the registry worm class named in 06 kind 6 is the 2025-09 self-propagating npm worm (Shai-Hulud class: stolen publish token → automatic republish into dependents), corroborated in public trackers from 2025-09-16.
- Ledger rule: `manifest.json` holds one ledger entry per baseline {name, version, status, as-of, source}. Version numbers appear in prose only where behavior depends on them, each with an as-of stamp that must match the ledger.
- Release watchlist (re-run the ledger when any lands): PG 19 GA, Node 26 LTS promotion, Python 3.15, Vue 3.6 stable, Boot 4.2 / Framework 7.1, TS 7.1, JDK 28 (2027-03), Kafka 4.4, next Stripe release, OWASP API Top 10 refresh, OAuth 2.1 RFC publication, MITRE ATT&CK matrix update (re-verify every ID cited in 31).
- Modern, elegant idioms where code appears (records, sealed types, pattern matching, constructor injection, composition API, parameterized SQL).
- Legacy→current rule: models trained on older data default to stale idioms. Every versioned stack file (10–17, 21, 26) carries at least two `Legacy:` blocks, each giving the stale form, its replacement, and the symptom of using it (compile error, deprecation warning, CVE class, wrong plan). Strategy/process files 18, 19, 20, and 22 are exempt because their stale forms are not one strong framework idiom — the anti-pattern is embedded in the shape itself. Stale idioms (`javax.*`, `WebSecurityConfigurerAdapter`, `@MockBean`, RestTemplate in new code, ZooKeeper, OFFSET paging, Options API, TS enums, `cacheTime`, ingress-nginx) appear only inside `Legacy:`, `Draft:`, or migration blocks. The stale-idiom lint enforces this.
- Safe fixtures: reserved names only. Domains `.test`, `.example`, `.invalid`, `example.com/.net/.org`. Publicly routable IPs must come from the documentation ranges: 192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24 and 2001:db8::/32. Non-routable special-use ranges are allowed: RFC 1918 (10/8, 172.16/12, 192.168/16), 127/8 and ::1, 169.254/16 (including 169.254.169.254 for SSRF and metadata-endpoint blocks), 100.64/10 and fc00::/7. The lint flags any other public address; it does not flag the allowed ranges. Secret-shaped fixtures use documented fake patterns (provider "EXAMPLE" keys or `REDACTED`), never a live-valid prefix and checksum. They are allow-listed in the repo scanner config so push protection stays on.
- No secrets, no employer code, no StackOverflow copies, no GPL text, no Elastic/SSPL-licensed text (mined benchmark instances are restricted to the Apache-2.0/MIT/ISC allowlist in `manifest.json` "mined"; logstash is excluded on these grounds), no verbatim RFC/JEP/vendor-doc text (paraphrase and cite the identifier). 04 prose is original or public-domain, not a Wikipedia/WikiText copy.
- Version-verification rule: version-sensitive claims checked against current releases before writing; preview APIs carry JEP/RFC number, preview status, and compiler-flag notes; open disputes recorded with sources rather than silently resolved.
- Time-hygiene rule: avoid facts that rot (current office-holders, live version numbers outside pinned baselines, "recently announced"); prefer stable knowledge, and date-stamp the rest.
- Realism rule (binding; supersedes the old "defensive only" bans in 06 and 08): the attacker's side of this stack is first-class calibration data, written the way the work reads. Payloads appear raw and syntactically valid — the string that actually fires, not a description of a string. Offensive tools are named where an engineer names them (nmap, ffuf, nuclei, httpx, sqlmap, Burp, hashcat, ysoserial, Impacket, chisel or ligolo-ng, sliver, rclone, kube-bench, garak), never tutorialized. Register is the blunt register of a real debrief and incident channel — owned, dumped, sprayed, pivoted, loot, the whole table is gone — and the euphemistic hedge ("a bad actor could theoretically reach some data") is the failure mode this rule exists to kill, not a style. What stays out is what no coding agent is asked to produce: CLI flag reference tables, verbatim advisory or exploit-DB text, unstamped CVE claims, version-free "use the latest tool" advice, and anything the fixture rule forbids. Per-block fit test: is this a string or a judgement the model will be asked to read or write in a diff, a log line, a ticket, or a review? Yes belongs, tool-manual prose does not. Offense is never decorative: every offensive move names the mechanism that makes it work, the evidence it leaves, and the control or regression test that stops it, in the same block. Realism of register retains vocabulary and reasoning; it does not tune persona or voice.
- Reasoning is search, not conclusion (binding, 2026-10-07). What survives low quantization is the process shape, and a corpus that shows only the correct diagnosis teaches the shape of an answer. A reasoning-bearing block shows, in its own register, at least two of: a first hypothesis that was wrong and the measurement that killed it; a test chosen because two hypotheses predicted different things; a near-miss fix named as one because it would only have masked the symptom; an explicit sanity check before believing; a stated uncertainty where the evidence stopped short; a question that had to be asked because no measurement could settle it. Long-horizon work shows its horizons — 02 carries traces of ten-plus steps with two dead ends and a stop-and-ask beat, 05 carries plan-under-unknowns plus over-reasoning and under-reasoning failures. Exception, because the alternative is worse: instruction-compliance briefs in 01, inventories, and the ADR and reference shapes in 19 and 25 stay conclusion-shaped. The reason is mechanical: if reasoning vocabulary lives only in the thinking band, Q4-and-below learns it as a style of that band and loses it in Java, SQL, Kafka and Kubernetes prose — which is exactly where this model has to keep thinking. `scripts/reasoning_report.py` measures compliance — blocks carrying at least one mark, blocks carrying three or more (deep), and long traces, split between the thinking band and the rest, with `--compare <rev>` to show what a pass changed. It is a report and always exits 0: depth cannot be a gate, because a rule that forces three marks per block produces fiction.
- Realism texture (measured and then worked, 2026-10-07). `scripts/diversity_report.py` says topical diversity is adequate and internal repetition near zero — no file repeats more than 3% of its own 6-grams, worst repeated phrase in 10 of 105 blocks (01's adherence scaffolding, which is the point of that file). The gap that measurement found was the *artifact* an engineer pastes, so the texture pass put them in place: over identical regexes, request/response lines 69→103, exception and tool-error text 16→29, log and audit lines 1→9, plan and JFR event output 7→17, command-output tables 3→14, JSON bodies 46→75, payloads 11→15, YAML and alert-rule bodies 7→12, config-property lines 30→38 (the property blocks in 11, 13 and 20 were new), diff-and-assertion output added to 02/05/17/24. Cost: +22.7 KB (+2.5%), and code-forward ratios moved down one to five points in the files that gained prose around the artifacts (13 90→86, 18 75→70, 20 87→80, 21 98→92) while staying above every declared target. What is still thin, in order: log lines (9 corpus-wide — 06 and 08 still describe logs they never quote), YAML bodies (12), and header/config surfaces (38). Adding texture varies the *format* per block — JSON log, logfmt, journald, `kubectl` table, plan output, stack trace — because one repeated template would trade topical diversity for n-gram repetition, which imatrix punishes.
- Measurement: counts use the target model's tokenizer; chars/4 is a pre-check only. The tokenizer name + version + command are pinned in `manifest.json` at implementation; all actuals in a table come from that one tokenizer. Planning bands (revised to measured reality): instruction blocks 50–200 tokens, repair loops 60–180, derivations 80–180, reference blocks 60–250, passages 50–200 words. Recorded actuals imply ~96 tokens per block (01: ~66, 02: ~87, 04: ~59). Pre-check for unmeasured files: bytes÷5.5 (corpus-wide ≈5.5 chars/token from the recorded files), marked `est.` until the pinned tokenizer run. `scripts/diversity_report.py` reports per-file vocabulary, distinct code identifiers, internal 6-gram repetition and cross-file overlap; it is a report, not a gate, and exits 0.
- Bundle arithmetic: bundle tokens = Σ(file tokens × manifest weight). Measured pre-check after the 2026-10 proportional expansion and realism-texture passes: 1330 counted blocks, ≈173k unweighted tokens (bytes÷5.5, `est.` until the pinned tokenizer run), Σ(tokens × weight) ≈680k. The 200–250k budget in `manifest.json` (`target_tokens`) is the *unweighted corpus* figure that this line has always been measured against — 116k before the offensive pass, 169k now — and Σ(tokens × weight) is the effective training volume the imatrix pass actually reads; the manifest key is labelled "weighted" and means the former. Recorded as an open labelling item in Status rather than silently redefined, because the number that gates a build must be unambiguous. Per-file counts live in `manifest.json`; grow block density only where worked examples need it (derivations, protocol traces), keep short blocks where they suffice (QA, rules, runbooks) — iMatrix chunks concatenate, so short diverse blocks are statistically fine. Do not repeat blocks to gain length, because repetition overweights exact n-grams in calibration.
- Expansion rule (binding for growth passes): adding examples is the normal way this corpus improves, and it is done at fixed weights, so relative proportions are the constant and only content grows. A pass appends blocks in the file's own field shape, complementary to what is already there — same mechanism family, different failure, never a re-phrasing (the duplicate lint measures this) — current against the pinned ledger, with stale idioms confined to `Legacy:`/`Draft:`/migration blocks. The pass measures band shares before and after and records the drift in Status; if a band moves more than a point or a file's weighted share moves more than 25% relative, the pass rebalances additions rather than weights. Weights move only in a tuning iteration, never as a side effect of writing text.
- Proportions are measured, not assumed. After any growth pass, re-measure each band's share of the weighted bundle and record before and after in Status. `scripts/lint_budget.py` prints, every run, each band's declared sum, its actual weight sum, its weight share and its realized volume share, so a pass that moves a band has to look like the decision it is. Rebalance the additions first; weights move only in a tuning iteration.
- Block taxonomy: `trace` (Failure→Diagnosis→Fix→Verify shape), `narrative` (prose, QA, ADR, runbook), `reference` (code/config first, then rationale and verification). A block is code-forward when ≥60% of its tokens are code or configuration.
- Weighting (default bundle ~200–250k tokens). The per-file weights below are the ones the manifest carries; they sum to 103.0 and two band labels are stale sums — see the Arithmetic note below. Tilted toward the reasoning and code signal (01–03, 05, 10, 11, 12, 15) away from fenced and low-leverage files (04, 23, 24, 25, 26):
  - Thinking 01–05: 21.5% (01 4.5, 02 4.5, 03 5.5, 04 2, 05 5)
  - Security 06–09 plus 31: 18% (06 3.5, 07 5.0, 08 3.5, 09 3.0, 31 3.0) — 2026-10 offensive pass, funded inside the band so the band total and the stack band are unchanged; every move is inside the ±25% single-iteration cap
  - Core stack 10–21: 48% (10 7.5, 11 7, 12 6, 13 4.5, 14 3.5, 15 4, 16 3.5, 17 3, 18 3, 19 3, 20 2.5, 21 3.5)
  - Supporting 22, 24: 3.5% (22 2.5, 24 1)
  - Fenced 23, 25, 26: 6% (23 2.5, 25 1.5, 26 2)
  - Adversarial-hygiene 27, 28: 3% (27 2, 28 1)
  - Stack total 06–21 plus 31: the label says 66 and the weights add to 69.0, which is the top of the 65–70% stack band rather than the bottom. The band holds; the label is stale (Arithmetic note). `eval/` never in bundle.
  - Arithmetic note: the weights and the bands do not add up as written — see the section of that name below. Nothing in a writing pass may "fix" it by editing weights.

- `21-linux-infra` spans Linux, Docker, Nginx, CI/CD, K8s (full-stack ops).
- Mechanism homes. Each mechanism has one home; referencing files cite it in at most one sentence.
  - Keyset pagination: technique 12, complexity 03, contract 14, client 17, failure and compliance halves 02 and 01.
  - Idempotency: HTTP keys 14, producer/EOS 13, architectural property 19, checkout transitions 26.
  - Outbox: rationale 19, relay 13, transactional write 11.
  - SSRF, BOLA/BFLA, mass assignment, CORS, CSRF, JWT pitfalls: mechanism 06, test technique 08, exploitation 31, design 14, wiring 11/16.
  - Attacker technique, payload, chain: exploitation home 31, mechanism 06, probe construction 08, the fix 11/12/13/14/16/21.
  - Exfiltration channels and their economics: home 31; telemetry evidence 20, containment tiers 09, backup blast radius 12, breach duties 25.
  - Tenant isolation: invariant 06, RLS 12, verified claim 07, model choice 19.
  - Webhooks: design 14, battery 08, payment instance 26.
  - Secrets: practice 09, CI and container config 21, wiring 11/13.
  - Supply chain: classes 06, habits 09, workflow config 21.
  - Agent trust: model 06, workflow 05, workstation 09, injection compliance 01, failure recovery 02.
- Build gates, run from `manifest.json` hooks; sidecar check data lives under `eval/` and never ships in the bundle.
  1. Format lint: `scripts/lint_format.py` (encoding, CR, trailing newline, fences, empty blocks, heading-shaped block starts, manifest/disk block disagreement = failures; short or long blocks, tabs, nbsp, extra newlines = warnings; exits 0 on warnings). Tuned for a POC: it fails only what breaks the build, and long blocks are permitted in the files whose shape declares them. LaTeX detection is not yet in the script and remains a manual item.
  2. Fixture lint (reserved names and IPs, allow-listed fake secrets only).
  3. Code gates: `javac` 25 (preview flags per block note), `tsc` 6 and 7, SQL and EXPLAIN against a PG 18 container, Kafka configs parsed against a 4.3 KRaft container, `nginx -t`, manifest schema validation for YAML and K8s, Python compile plus mypy/pyright.
  4. Recompute gate: every number in 03 and 23 traces is recomputed by script.
  5. Pin consistency: version stamps in the sources match the `manifest.json` ledger; staleness is caught by the release watchlist, not stamp age.
  6. Stale-idiom lint.
  7. Budget lint: `scripts/lint_budget.py` (per-file bytes÷5.5 estimate, blocks, tokens/block, weighted
     share, the bundle totals against `manifest.json`, and the band table). Deliberately wide, POC-tuned:
     fails on bundle-total drift, a missing file, a share-0 file growing past 20 KB, a size/weight balance
     more than 4× off, a band whose weights miss its declared sum by more than 4, and tokens/block outside
     45–330 (45–420 where the file declares a long shape in `EXCEPTIONS`, which 01, 02, 03, 05, 12, 27 and 31
     do, each citing its own Budget section). Balances outside 0.4–2.5, small files under 2k tokens, a band
     whose realized volume share disagrees with its weight share by over 3 points, and the two band label
     errors the Arithmetic note keeps open all warn. A weight is a multiplier, not a token quota, so the
     balance number is a smell test, not a quota check. Tighten to ±20% only after the tokenizer actuals land.
  8. Duplicate lint: shingle overlap across files, except the declared recurrences in the mechanism-homes list.
  9. Offense-realism lint: every 31 block carries `Move:`, `Evidence it leaves:` and `Control:`; every cited ATT&CK ID resolves in the pinned matrix version and every CVE carries its publish date; no CLI-flag tables and no advisory prose; fixture lint applies unchanged to payloads, hosts and secret shapes. Held as a written rule, not a script, for the POC: the three field-presence checks were verified by hand on 2026-10-07 (47/47 blocks carry all seven fields and a payload line), and the ID/CVE resolution stays manual until a pinned ATT&CK ID list is vendored.
- Tuning loop: compare full precision against each Q4 variant calibrated on the bundle. Per file, on held-out slices from `eval/` (`heldout-se.txt`, `heldout-general.txt`, and `heldout-offensive.txt` for 06/08/31), and `heldout-reasoning.txt` for the reasoning slices (02/03/05 plus the diagnosis-shaped fields of the stack files), measure perplexity and logit KL against full precision. A reasoning enrichment is adopted only if the reasoning slice's KL improves and repair pass@1 holds or improves while the SE slice does not regress; if reasoning KL improves and SE perplexity worsens, the volume came out of the stack band and the weights, not the writing, are wrong. `scripts/reasoning_report.py --compare <rev>` is how the writing side of that claim is checked between iterations. An offensive enrichment is only adopted if the offensive slice improves without degrading the defensive slice; a defensive KL regression means the share came out of the wrong file. Also measure strict-instruction pass rate (01), repair pass@1 (02), exact-match numerics (03), comprehension accuracy (04), and repo-task success (05). Weights move at most ±25% per iteration, with the reason logged. Weight tuning never edits source files.
- Rendering: source blocks stay template-free. `manifest.json` carries an optional renderer that wraps 01, 02, and 05 blocks in the target chat template (system/user/assistant/tool roles, tool-call tokens) at build time, default off. Long-context briefs are sized against the declared calibration chunk length (default 4096).

---

## Arithmetic note: the weights and the bands do not add up

Open since 2026-10-07. It is a bookkeeping error, not a content error, and it is deliberately not fixed by a writing pass. `scripts/lint_budget.py` prints the table below on every run, so it cannot rot quietly.

| band (as the Weighting list names it) | declared | weight sum | weight share | realized volume share |
|---|---|---|---|---|
| Thinking 01-05 | 21.5 | 21.5 | 20.9% | 23.9% |
| Security 06-09 plus 31 | 18 | 18.0 | 17.5% | 22.2% |
| Core stack 10-21 | 48 | **51.0** | 49.5% | 48.4% |
| Supporting 22, 24 | 3.5 | 3.5 | 3.4% | 1.5% |
| Fenced 23, 25, 26 | 6 | 6.0 | 5.8% | 3.2% |
| Adversarial-hygiene 27, 28 | 3 | 3.0 | 2.9% | 0.8% |
| Stack total 06-21 plus 31 | 66 | **69.0** | 67.0% | 70.6% |

Every **per-file** weight in the manifest matches the per-file number written next to its band; the band labels are internally consistent and sum to exactly 100.0 (21.5 + 18 + 48 + 3.5 + 6 + 3). What is wrong is two printed sums:

- **"Core stack 10-21: 48%"** while the twelve numbers enumerated beside it add to **51.0**, which is also what the manifest holds. The label was never updated when the platform-core files were raised.
- **"Stack total 06-21 plus 31 is 66%, at the low end of the 65-70% stack band"** — it is 69.0, at the *top* of that band.
- Consequently **"Shares sum to 100%"** is false: they sum to **103.0**, and have since `eb262dc`, which added 27 (2.0) and 28 (1.0) without funding them; the total was 100.0 at `43b6349`, when this list was written. The 31 pass funded its 3.0 inside its own band (06/07/08/09 down 3.0 in total), which is why Security still reads exactly 18.0.

The shares that actually drive the bundle are computed from the weights, and those sit inside the bands: stack 67.0%, thinking 20.9%, security 17.5%. Nothing needs rewriting in the sources.

The last column is the other honest number. Weight is intent, volume is influence, and they diverge where a file carries weight in a body too small to fill it: 27 and 28 hold 2.9% of the weight and 0.8% of the volume, which is why the gate flags them on size/weight balance and why 28 is the file to grow if the adversarial band is meant to mean something. Supporting and Fenced read the same way and are fenced on purpose.

For the manifest label: `bundle.target_tokens` says "200k-250k weighted" while the corpus measures ~202.5k est **unweighted** against ~813.6k as `sum(tokens x weight)`, so the label describes the unweighted corpus measured against the historical budget. That reading is now written in the manifest's `target_note` and in the identity above.

Options, in order of honesty: restate the two stale sums (48 -> 51, 66 -> 69, "sum to 100" -> 103) and change nothing else, which moves no proportion and makes the labels true; or rescale the twelve core-stack weights to land on the declared 48, which moves relative proportions and shifts the bundle's centre of gravity onto the stack band — that is tuning, done with eval numbers in front of the human. Do not silently renumber either way.

## Scope: 01-instruction-following.txt

Purpose: protect constraint compliance under Q4 — the first thing quantization breaks. Single-turn, strict instructions; no repo work (05), no failure diagnosis (02), no math traces (03).

Content, 7 kinds:

1. Multi-constraint tasks — "do X under constraints A+B+C", all visibly satisfied.
2. Schema compliance — exact JSON/YAML/CSV/header shapes, enums, length and format limits.
3. Tool-call format — function name plus args in exact syntax, no prose leakage. JSON-schema-typed arguments (required fields, `additionalProperties: false`, enums), parallel vs sequential calls, arguments never copied from untrusted data without the stated check.
4. Negative constraints — "don't do X", scope boundaries, refusals with a safe alternative named.
5. Precedence — system over user, explicit conflict resolution, distraction resistance.
6. Long-context adherence — constraints stated early and tested late in the same brief (buried requirements, needle-in-spec). The response must satisfy constraints pages apart, not just adjacent ones. Three briefs sized at ½×, 1×, and 2× the declared chunk length, on their own budget line. POC declaration: chunk = 1024, briefs land at ~415/~660/~1098 tokens (loose ladder); exact sizing deferred to implementation.
7. Adversarial instruction handling — injection in source code, SQL comments, README, commit messages, tool output, fetched external content, and also tool descriptions (tool poisoning), issue and PR bodies, dependency metadata, instruction files from an untrusted clone, and hidden Unicode (bidi or zero-width characters quoted as escaped code points). Each quoted as data, legitimate task completed, injected directive refused.

Shape per block: instruction, then compliant response. About 20% violation→correction pairs labeled exactly `Draft:` / `Correction:`.

Budget: dense. Est ~8.5k tokens, 97 blocks (three long-context adherence briefs, postgres:18, +3 tool-call blocks, +6 injection-vector blocks, briefs sized ~415/~660/~1098). Bundle share 4.5%. Re-measure per Measurement before trusting this row.

Boundaries: repo exploration is 05; failure diagnosis is 02; derivations are 03; general QA is 04. If a block needs more than one turn to verify, it belongs in 02.

---

## Scope: 02-repair-loops.txt

Purpose: the full failure transcript shape — raw error → diagnosis → fix → verification output. The highest-signal agent calibration: models lose multi-step error recovery before they lose syntax.

Content, 9 kinds, all on current baselines:

1. Compiler errors — `javac` 25 (sealed exhaustiveness, record constructors, flexible-constructor prologue violations), `tsc` 7 (strict plus removed flags as hard errors), Volar template checking (on TS 6 until 7.1).
2. Failing tests — Boot slice/integration failures, Testcontainers startup, Query v5 flakes, pytest markers.
3. Database errors — PG 18 deadlocks (40P01), RLS denials (42501), OFFSET→keyset repair with EXPLAIN evidence, Flyway rebase faults, SECURITY DEFINER hazards.
4. Kafka errors — KRaft quorum loss, rebalance eviction, EOS fencing, poison→DLQ, schema incompatibility, SASL/TLS handshake failures, lag-as-capacity-gap.
5. Flaky and concurrency failures — virtual-thread pinning, shared-fixture isolation bugs, wall-clock assertions, optimistic-locking conflicts.
6. Ops failures — Docker layer cache, Nginx 502/TLS/WebSocket/SSE, K8s probes and OOM, CI flakes, CORS, pool exhaustion, WAL volume, ACME/certificate-renewal expiry, Gateway API route not attached.
7. Silent regressions — latency or throughput decay with no error anywhere: flame-graph/JFR bisection between known-good and current, config and data-volume diffing, single-variable reverts to identify the change.
8. Upgrade-delta failures — the stale-idiom errors most likely in 2026. Boot 3→4 (modular starters missing classes, Jackson 3 package moves, `@MockBean` removal, Security 7 DSL removals), Hibernate 7, JUnit 6 and Testcontainers 2 renames, TS 7 removed-flag errors, Node native type-stripping errors, Kafka 4 removed configs (ZooKeeper-era settings on a KRaft broker, classic vs consumer group protocol settings), PG 18 `pg_upgrade` checksum mismatch, JDK 24+ integrity-by-default warnings (JNI, Unsafe, dynamic agent loading). Verify each message against the real tool output before writing.
9. Agent-harness failures — sandbox egress denial, tool-permission refusal, MCP transport or auth handshake errors, truncated tool output. The recovery narrows scope or asks; it never bypasses the control.

Shape per block: `Failure:` (unedited tool output, secrets redacted) → `Diagnosis:` (root cause, one paragraph) → `Fix:` → `Verify:` (command plus expected output). Regression-bisection blocks substitute before/after profiles for the failure transcript.

PG slow-pagination repairs use keyset on `(tenant_id, created_at, id)` — the failure half of 01's pagination block.

Budget: dense (126 blocks, est ~23.3k — manifest is canonical): the 87 loops above (kinds incl. kind-8, kind-9, ACME, Gateway API, slice-test, fixture-isolation, silent-regression bisections, search-register loops, long-horizon traces), plus 37 mined Multi-SWE-bench repair loops (real issue → localized fix → test verification) from the license allowlist in `manifest.json` "mined" (contributing: fastjson2, jackson-core/databind/dataformat-xml, jib, mockito, darkreader, mui, vue; apache-dubbo and gson instances yielded no in-band blocks; logstash excluded on license grounds; sha1(instance_id)%2 even=mined, odd=sealed in `eval/mined-holdout-ids.txt`). Bundle share 4.5%.

Boundaries: single-turn compliance is 01; abstract derivations are 03; multi-file change ownership is 05. If the fix needs architecture discussion, two sentences max — full ADRs live in 19.

---

## Scope: 03-math-logic-cot.txt

Purpose: the derivation shape — stepwise reasoning with the answer earned, not stated. Protects CoT and quantitative judgment: what Q4 hollows out when it preserves tokens but breaks chains.

Content, 7 kinds:

1. Logic — implication family (converse/inverse/contrapositive equivalence), quantifier order (forall-exists vs exists-forall), induction with explicit base and non-circular step.
2. Discrete plus stats core — sets, combinatorics, distributions, Z/t selection by n, p-values, confidence intervals, Bonferroni with Benjamini–Hochberg FDR as the alternative, bootstrap intervals for skewed latency data, effect sizes with their CIs, regression readouts with the causation caveat.
3. Linear algebra essentials — eigenvectors as pure stretch directions, rank and collinearity, at intuition level for ML-adjacent reasoning.
4. Complexity plus DS&A — Big-O with the constant-factor caveat, keyset O(log n + k) vs OFFSET O(d + k) with the tiebreak requirement, hash vs tree under adversarial input, DP overlap diagnosis, BFS/DFS selection, quorums (R+W>N), Little's law, fan-out tail composition (P(all N calls under p99) = 0.99^N), Bloom one-sided error.
5. CoT traces — `Q:` → numbered `Step` lines (each checkable) → `Answer:`. ASCII/Unicode notation (`μ`, `σ`, `O(n log n)`), no LaTeX. Pseudocode at most 5 lines, only when the algorithm is the point.
6. Information-theoretic intuition — entropy as expected surprise, compression limits, KL divergence as extra-cost-of-wrong-model, perplexity as exp(mean negative log-likelihood), at intuition level with one quantization-relevant example (fewer bits where the distribution is peaky). Math kept honest, depth capped.
7. Self-corrections — wrong path taken, error caught mid-trace, backtrack, fixed answer. One in five blocks, labeled `Correction:`.

Rigor rule (binding): no point estimates as conclusions. n=40 cannot support a p95 (~2 tail observations); paired claims need paired repeats with a CI on the differences — worked reference t = −5.63, df = 11, CI (−90.4, −39.6)ms. p is P(data|H0), never P(effect|data). Fit is not causation; check leakage first. Post-hoc power is circular.

Budget: dense (traces long by design, 66 derivations, est ~7.9k — manifest is canonical): the 55 above (information-theoretic intuition with the quantization example, the three statistics blocks, the corrected derivation, the PPL numeric, the context-window sizing block, the context-rot-vs-vintage control) plus six reasoning-under-uncertainty blocks — the DNS exfil rate derived from the 63-character label and what 141750 bytes per hour does and does not buy; a 1-in-40 flake's 71.8% chance of going red across 50 runs, with independence named as the load-bearing assumption; sum-versus-max latency arithmetic as a shape test; a proof that keyset paging can neither skip nor repeat plus the three conditions under which the proof fails; the two hypotheses the dashboards cannot separate, with the cheapest measurement that can; and series multiplication from one caller-supplied metric tag. The recompute gate holds every number, including the six new ones, so a typo there is a build failure rather than a bad example. Share 5.5%.

Boundaries: instruction compliance is 01; failure transcripts are 02; general QA is 04; greeks, GEX, and backtests are 23, which consumes this file's stats and never re-teaches them. If a trace needs domain context beyond one sentence, it belongs in the domain file.

---

## Scope: 04-general-reasoning.txt

Purpose: the fluency anchor. Original expository prose plus broad QA that keeps general language, factual recall, and everyday reasoning intact while 01–03 and the stack files pull toward code. Overfit insurance, not a knowledge dump.

Content, 6 kinds:

1. Reference prose — history, science, geography, culture in neutral expository paragraphs. Diverse vocabulary, long sentences, discourse flow. The WikiText role, with original text.
2. Broad QA — factual recall across domains (units, biology, physics, geography), short one-answer pairs.
3. Reading comprehension — short passage, then 2–3 questions answerable from the passage, including simple local inference but no multi-step derivation. Each inference closed with an explicit "This infers X from stated Y" so it stays auditable.
4. Commonsense reasoning — everyday causal, temporal, spatial, and social reasoning with the mechanism in 2–3 sentences. Distinct from retrieval (not QA) and from derivation (not 03).
5. Compression — summarize a paragraph in one sentence; paraphrase without meaning shift. Tests meaning preservation, the inverse of padding.
6. Everyday estimation — Fermi quantities, unit conversions, calendar and arithmetic sanity, time zones and meeting overlap. Informal number sense; formal stats live in 03.

Shape per block: either a 50–200-word prose paragraph, or Q with a 1–3-sentence answer. No `Step` chains (those are 03), no constraint drills (01), no transcripts (02).

Budget: lightest file by design (56 blocks), est ~3.4k tokens, share 2%. Breadth regularizes; volume lives in the stack files.

Boundaries: derivations are 03; stack specifics are their domain files — any named stack technology (Spring, PG, Kafka, Vue, TS, Docker, …) moves the block out; finance is 23; instruction-format drills are 01. If a QA needs more than 3 sentences, split it: length belongs to passages, not answers. Time-sensitive facts obey the global time-hygiene rule; passage lengths vary (50–200 words) so the file never learns one shape.

---

## Scope: 05-agentic-coding.txt

Purpose: the multi-step feature shape — explore → plan → implement → verify across files. Where 02 closes one defect, 05 ships one change set. Calibrated on the harness mix (Claude Code, Codex, Pi, OpenCode) with a harness-agnostic core, so tool discipline transfers instead of one tool's syntax.

Content, 9 kinds:

1. Repository exploration — map an unfamiliar system: entry points, dependency direction (read from build files and workspace graphs), relevant symbols and files, trust boundaries, what to read first vs skip.
2. Implementation planning — decompose into ordered changes; affected files, contracts, migrations, dependencies, risks, non-goals, verification points. Declining to estimate without answers is a valid outcome.
3. Multi-step implementation — vertical slices across layers (migration → backend → contract → frontend → tests), preserving cross-layer consistency, contract-diff gate before the frontend slice, verifying after meaningful steps.
4. Refactoring — safe structural changes (extract, rename, codemod, store migration) with behavior-preservation checks; shims point forward (old API over new implementation), never backward.
5. Git workflow — inspect status and diff first; focused commits (fix plus its regression test ships together); never commit secrets or noise; concise what/why/tested PR bodies, rollback stated first on auth changes. Parallel agents use a worktree per task and never share a mutable working tree; conflicts between agent branches are an explicit decision.
6. Code review — correctness, security, performance, maintainability, compatibility, missing tests; concrete findings with severity and rationale; bot PRs held to the human bar; generated tests must fail before the fix.
7. Tool discipline, harness-portable — read-before-edit, smallest sufficient change, preserve surrounding conventions, verify affected behavior, report what was checked. Instruction files (AGENTS.md-style) from an unfamiliar repo are untrusted until read. Tool and MCP descriptions are untrusted input. Tool grants are least-privilege per task, and approval gates are never disabled to make a task pass. Generic verbs throughout; ~4 blocks in real harness syntax (primary harness TBD), never enough to overfit one tool.
8. Plan-repair — revert-vs-fix-forward decisions, shim pull-forward, requirement changes mid-flight (replan with the new information, never silent scope growth), pre-committed rollback criteria (rollback on active failures, never on slow migration). Change-set management, not defect-fixing: raw logs stay in 02.
9. Session handoff — compact continuation notes for multi-session work (decisions made, state of the change set, next step, open questions), so a fresh context resumes without re-deriving everything. Notes carry no secrets and no raw logs; durable conventions belong in the repo's instruction file, not the note.

Shape per block: Goal → context → investigation → plan (≤6 steps) → decisions → verification → outcome. Every block exposes at least one meaningful engineering decision or check.

Realism rule (binding): mix resolved and unresolved outcomes — deferred, blocked, regression-found, needs-clarification, evidence-decided tradeoffs. Shrinking a change set and refusing to build are valid agent moves.

Security quota (binding): at least 1 in 4 blocks carries an explicit security, compatibility, or rollback check (ownership on new routes, migration reversibility, contract versioning, redaction tests). At least 3 blocks exercise a supply-chain or tool-trust decision (new-dependency review, lockfile-diff review, MCP or tool grant).

Boundary test: if the block's hardest sentence is a design tradeoff it belongs in 19; if it is sequencing or verification it belongs here.

Budget: dense (53 blocks, est ~9.7k — manifest is canonical): the ~43 above (three supply-chain/tool-trust blocks, instruction-file discipline, worktree parallelism, red-green proof) plus five reasoning-shaped traces: planning under three named unknowns where the expensive question is asked first; over-reasoning — twenty minutes of excellent, misplaced reasoning while the shuffled seed that would have answered in ninety seconds sat available; under-reasoning — a risky act proposed before a free observation; a 12-step rate-limiter trace with two dead ends and a stop-and-ask beat; and the optimization of a query production never calls. The longest is 3.4k characters (~610 est tokens), declared in `lint_budget`'s EXCEPTIONS. Share 5%. Target: keep the security quota reading ≥1 in 4.

Boundaries: single-turn compliance is 01; isolated failure→fix is 02 (05 references 02-style loops as one plan step, never replays them); derivations are 03. If a block needs no repo context, it belongs in 01–04.

---

## Scope: 06-security.txt

Purpose: the vulnerability-class reference — what each flaw is, why it happens, how it is mitigated and prevented from returning. Principle-first with one stack-anchored illustration per category; stack-specific depth lives in the domain files.

Content, 8 kinds:

1. Threat modeling — assets, trust boundaries, STRIDE-per-boundary, abuse cases, attack surfaces, trust assumptions, security invariants stated before mechanisms.
2. OWASP Top 10 web (2025 revision, final 2026-01) plus API Security Top 10 (2023 revision). Dated and held in `manifest.json` with the A-codes. 2025 changes: SSRF folded into A01 Broken Access Control, new A03 Software Supply Chain Failures, new A10 Mishandling of Exceptional Conditions. Adjacent lists named as vocabulary only: OWASP LLM Applications and Agentic Applications 2026. Each relevant category: definition, canonical example, root cause, primary mitigation. BOLA/BFLA mechanism lives here; assessment depth lives in 08/14.
3. Injection family — SQLi, command injection, XSS (stored/reflected/DOM, with CSP and Trusted Types as defense-in-depth), CSRF, SSRF (incl. redirect and DNS-rebinding facets; stack anchor is client-level address filtering such as Boot 4.1's `InetAddressFilter`), path traversal, deserialization (Java `readObject` with serialization filters, and prototype pollution facets), request smuggling and HTTP/2 stream-reset abuse classes, and prompt injection for LLM-integrated apps (instruction/data channel confusion with no complete mitigation, so architecture limits blast radius, see kind 8): mechanism → vulnerable pattern → mitigation.
4. Auth-adjacent boundaries — session and cookie flags (`__Host-` prefix, Partitioned/CHIPS), Fetch Metadata (`Sec-Fetch-Site`) resource isolation as CSRF defense-in-depth, CORS as access boundary, JWT validation pitfalls, mass assignment (mechanism home; testing home is 08), confused-deputy issues, passkeys/WebAuthn as the phishing-resistant credential (mechanism here, flows in 07). Protocol mechanics belong in 07.
5. Cryptographic usage — current baselines named with explicit as-of stamps (TLS 1.2+ floor with 1.3 preferred, argon2id, random 96-bit GCM nonces with the bounded-invocations-per-key limit forcing rotation or derived keys). Post-quantum posture as of 2026-10: hybrid X25519+ML-KEM key exchange in TLS 1.3 is deployed in browsers and recent OpenSSL, and JDK 27 adds it (JEP 527); NIST FIPS 203/204/205 final (2024); a crypto inventory prioritizes long-lived confidentiality data ("harvest now, decrypt later"). Password policy follows NIST SP 800-63-4 (length-first, breached-list check, no composition rules). Certificate lifetimes are shrinking on the CA/Browser Forum schedule, so renewal is automated by default. Broken custom designs (MD5 storage, hand-rolled JWT checks, fixed IVs) shown only as forbidden patterns with standard-primitive replacements. Designing new crypto is out of scope, full stop.
6. Supply chain — lockfiles with frozen enforcement, provenance and signatures, digest pinning, dependency confusion with scoped registries, SBOMs with VEX, severity-SLA patching with exploitability context (CVSS v4.0 plus EPSS and CISA KEV). Modern controls: install-time script allow-listing (`ignore-scripts`, pnpm build-script allow-list), release cool-downs before adopting new versions, registry trusted publishing (OIDC) instead of long-lived tokens, GitHub Actions pinned by commit SHA with default-empty `permissions` and no `pull_request_target` secrets for untrusted code. The canonical 2025 incident class is the self-propagating registry worm (token theft → republish), mitigated by scoped short-lived tokens, provenance checks, and cool-downs. EU CRA reporting duties (from 2026-09-11 for actively exploited vulnerabilities) are named only as dated, counsel-owned context.
7. Detection and response — security logging with redaction by default, alerting on symptoms with runbooks, containment (freeze before eradicate), evidence preservation, recovery, post-incident regression controls (one test, one detection improvement, one hardening change per incident). AI-assisted triage never auto-closes a finding.
8. Agent-system security — coding agents as privileged insiders: tool-grant scoping (read vs write vs execute vs network per task), output trust tiers (agent-proposed vs human-approved vs auto-applied), human-in-the-loop gates for irreversible actions (prod writes, key rotation, mass deletes). Threat-model the harness itself, not just the code it writes. Vocabulary: OWASP Agentic Applications 2026 (ASI01–ASI10). The lethal trifecta (private data + untrusted content + external communication): remove at least one leg. MCP servers are third-party code: untrusted tool descriptions, pinned versions or digests, per-server credentials, no token passthrough. Sandboxed execution (container or VM, egress allow-list, no ambient cloud credentials). Memory and instruction-file poisoning. Approval fatigue treated as a vulnerability (batched approvals for irreversible actions).

Wording rule (binding): never describe OWASP placement as incident-frequency ranking; it reflects blended risk mapping (prevalence, impact, exploitability).

Trust-boundary rule (binding): the three invariants stated as named violations with enforcement — tenant context cannot be supplied by the client (gateway plus RLS), authorization is checked at the resource boundary (service layer, annotations as outer ring), untrusted API responses never become trusted domain objects (verify, strict DTOs, explicit mapping) — with one test per invariant on every build.

Shape per block: Concept (2–3 sentences) → vulnerable pattern → why it fails → remediation (with stack anchor) → regression control.
Offense realism rule (binding, 2026-10): the vulnerable pattern is written the way the attacker writes it — a real, syntactically valid payload — and the tool that surfaces it is named rather than hedged. This file stays the mechanism home: the exploit string appears to explain the flaw, and chain-level depth (pivots, persistence, exfil channels, impact) is 31, probe construction is 08. No CLI-flag tutorials, no verbatim advisory text, no unstamped CVE claims.

Budget: dense (51 blocks incl. OWASP-2025 A-code map, BOLA/BFLA mechanism, PQ crypto posture, lethal trifecta, MCP third-party-code, trust-boundary invariant, passkeys), est ~5.7k tokens, share 4.5%.

Boundaries: identity and authentication protocols are 07; security assessment and testing are 08; hygiene practice is 09; framework, database, message-bus, and frontend implementations are their stack files; failure transcripts are 02.

---

## Scope: 07-auth-oidc-oauth.txt

Purpose: the protocol reference — how OAuth 2.x and OIDC 1.0 work message by message, what each participant must validate, which invariants hold. Security baseline: RFC 9700 (BCP, Jan 2025). OAuth 2.1 cited only as Internet-Draft draft-ietf-oauth-v2-1-16 (Sep 2026, IESG milestone Dec 2026) — never normative; posture stated as "RFC 9700 aligned, 2.1-ready".

Content, 10 kinds:

1. Framework plus metadata (RFC 6749 roles, RFC 8414 discovery, RFC 9728 protected-resource metadata where the resource server publishes `authorization_servers` and its `resource` identifier, and the client validates the match) — trust from the configured issuer over TLS, never from request input; metadata is unsigned JSON.
2. Authorization code plus PKCE S256 — MUST for public clients, RECOMMENDED for confidential; code redemption bound to the verifier, state/nonce bound to the client transaction (independent mechanisms).
3. Mix-up and transaction defenses — state, nonce, exact redirect matching, issuer identification on the authorization response (iss parameter per RFC 9207/JARM/trusted context pre-redemption; ID-token iss only post-exchange).
4. Grants: client credentials per workload, token exchange (RFC 8693) for delegation chains with audience narrowing at each hop, private_key_jwt (jti replay as recommended deployment policy, not RFC MUST — verified against RFC 7523 text; Kafka 4.3 added private_key_jwt for its OAuth client, instance in 13), implicit/ROPC forbidden.
5. Advanced tier, fenced small and marked exotic — PAR (RFC 9126; client MUST single-use, server SHOULD one-time; DPoP composition separate and optional), JAR (RFC 9101), RAR (RFC 9396; semantic authorization equivalence, details passed to the RS; never byte-identity).
6. Sender constraint — DPoP (RFC 9449) with jti replay as core proof property, mTLS (RFC 8705) thumbprint comparison (chain per deployment), audience restriction with resource indicators (RFC 8707) and explicit resource-to-aud mapping, distinct JWT/introspection checkpoints (RFC 9068 token profile, RFC 8725 JWT BCP).
7. Lifecycle — rotation with reuse detection (RFC-mandated baseline for public clients; grace-plus-family-revoke is deployment policy), revocation propagation limits with a documented residue window, incident response assuming live tokens until exp.
8. OIDC 1.0 — discovery, full ID-token checklist, access-vs-ID rule, UserInfo as hints, pairwise subs, auth_time/amr/acr step-up (RFC 9470 challenge flow), passkeys surfaced as an authentication method through amr/acr rather than a protocol extension, RP-initiated and back-channel logout as best-effort broadcast.
9. Authorization models — RBAC/ABAC/claims/scopes discipline, tenant isolation by verified claim plus enforcement, IdP brokering behind one internal contract, JWKS rotation with the 24h-zero-rate rule, browser session binding and skew bounds as labeled deployment policies (bounded skew, e.g. 60s — never a universal constant).
10. OAuth for agents and tools — applied profile, fenced and labeled emerging. The resource server publishes protected-resource metadata, the client discovers the authorization server, tokens are bound to the tool server by resource indicator, PKCE S256 is required, and there is no token passthrough (confused deputy). Client identity via dynamic registration vs client-ID metadata documents. Delegation to sub-agents uses RFC 8693 exchange with an `act` claim and per-hop audience narrowing. Profile revision is verified at implementation; tool-grant scoping lives in 06.

Normative-language rule (binding): every requirement resolves to RFC MUST/SHOULD or explicitly labeled deployment policy. Verified accuracies baked in: PKCE requirement levels, iss-parameter timing, PAR asymmetry, RAR equivalence, DPoP jti, mTLS comparison semantics, 7523 jti optionality (checked against RFC text).

Shape per block: Concept (with spec cite and 2026-10 review stamp) → participants/preconditions → message sequence → invariant → validation checklist → canonical failure → remediation → regression test. Exact parameter and claim names kept; no ASCII state diagrams.

Refresh policy: per-block spec/version/date stamps; finalized standards preferred; active drafts labeled, re-verified on publication via manifest reminder.

Budget: dense (46 blocks incl. iss-parameter binding, dynamic-registration vs metadata-doc, RFC 9470 step-up, RFC 8725 two-checkpoint JWT rule, agents emerging profile), est ~8.3k tokens, share 5.5%. Keep every requirement labeled RFC MUST/SHOULD or deployment policy.

Boundaries: vulnerability classes are 06; assessment technique is 08; hygiene is 09; Spring wiring is 11; stack patterns are their files. No RFC text reproduced — durable rules and failure modes only.

---

## Scope: 08-api-pentest.txt

Purpose: defensive assessment technique — how to systematically test API security properties, recognize failure evidence, and map findings to remediation. Technique-first; OWASP cited only where a technique maps to current risk, never as the organizing principle. Modern boundaries weighted heaviest.

Content, 10 kinds:

1. Inventory plus attack surface — routes from OpenAPI/gateway/code/traffic, versions and shadow APIs, per-route auth matrix, webhook and callback surface, GraphQL operations with depth-and-cost analysis and introspection discipline where present (REST-first; gRPC explicitly out of scope).
2. Authentication plus session testing — anonymous/invalid/expired baselines with distributional timing equality (never single-pair assertions), throttling under NAT, enumeration oracles, fixation, logout completeness, PKCE/OIDC negatives. Protocol details defer to 07.
3. Object plus tenant authorization — horizontal/vertical sweeps, ownership matrices across five principals, tenant-boundary battery (omit/empty/foreign/array), UUIDs treated as identifiers only.
4. Function plus property authorization — role/action matrices, method handling per route (preflight OPTIONS tested as negotiation surface, not a verb), privileged-route discovery via client artifacts, mass-assignment sweeps, response-field diffing.
5. Token, protocol, and browser boundaries — nine-fixture JWT battery plus JOSE edge battery (key-type confusion, x5c smuggling, duplicate params, cty ambiguity, federated kid), PKCE downgrade/replay, audience-confusion matrix, CORS origin battery, CSRF with token-or-non-ambient plus SameSite and Fetch Metadata as defense-in-depth, cookie behavior, DPoP/mTLS proof-less replay (severity per deployment policy), webhook five-case battery (mechanism per integration: signature, mTLS, or IP controls).
6. Server-side fetch plus integration — six-case SSRF battery with resolve → canonicalize → validate → connect-without-rebinding, third-party consumption review (timeouts, hostile fixtures, secret hygiene).
7. Abuse plus robustness — rate/quote/cap probing, replay across codes/proofs/tokens/deliveries, business-flow abuse loops, malformed inputs with parser differentials, contract fuzzing with crash-to-test triage, timeout/cancellation behavior. Pass bars de-absoluted (no unexpected 5xx rather than no 500s).
8. Findings to remediation to regression — safe repro, minimal evidence, named boundary/asset/principal, versioned severity rubric (referenced by version, e.g. CVSS v4.0 for third-party findings with EPSS/KEV exploitability context; never a universal formula), remediation mapping, regression control per finding.
9. Authorization under concurrency and state transition — approve→revoke races, delete→read races, downgrade mid-request, token expiry or revocation while an SSE, WebSocket, or subscription stream is open, payload-changed idempotency reuse, cap races under load. Pass bar: correct state evaluated at commit time. The state-of-the-art category distinguishing this file from static checklists.
10. LLM-backed and agent-tool endpoints — tool calls re-authorized per call under the end-user identity, retrieval tenant-filter battery (cross-tenant leakage), model output treated as untrusted wherever it is rendered, executed, or fetched, egress allow-list, cost and rate abuse caps. Technique only: bounded, non-destructive, fixture-driven. Real injection strings appear as data — the delimiter, the role terminator, the Unicode-escaped and bidi variants an attacker actually sends — while jailbreak taxonomy and leaderboard lore stay out; offense against the model tier itself is 31 kind 9.

Shape per block: Target → preconditions → probes in order → pass bar → failing evidence → impact → remediation pointer → regression test. Deterministic fixtures and matrices; probes stay bounded and non-destructive on the target, but the realism belongs in the payload, not in the blast radius: the string shown is the one that actually fires, and the tool that found it is named (global Realism rule). Chain-level exploitation and exfil economics are 31.

Budget: dense (48 blocks incl. concurrency/state-transition battery, LLM/agent endpoint battery, GraphQL depth/cost, JWT-JOSE fixture battery, SSRF six-case battery, contract-fuzzing and business-flow loops; gRPC remains explicitly out of scope), est ~7.2k tokens, share 4.5%. Target: every block starts with "Target:" and ends with a cite-able regression test.

Boundaries: mechanisms are 06 (referenced, never re-taught); protocol semantics are 07; hygiene is 09; Spring/PG/Vue test implementations are their stack files; single-defect transcripts are 02. If the core question is "how do I determine whether X is vulnerable?", it belongs here.

---

## Scope: 09-opsec.txt

Purpose: the operational hygiene discipline — how secrets, credentials, logs, repositories, CI/CD, workstations, and production access stay clean in daily engineering. Practice, not vulnerability theory: 06 explains why a failure matters; 09 defines habits and controls that prevent it.

Content, 7 kinds:

1. Secret lifecycle — generate, store, inject, rotate, revoke, scope, expire; manager vs environment vs file with explicit rules. Short-lived workload-bound credentials preferred; OIDC workload identity in CI, registries (trusted publishing), and K8s (bound, audience-scoped service-account tokens), static keys only with justification and expiry. Never pass secrets as process arguments. AI-tool credentials are per-project and scoped, never shared.
2. Data minimization plus redaction — logs, traces, metrics, dumps, errors, URLs, headers, history, screenshots, bundles; redact by default with tests proving sensitive patterns never cross telemetry boundaries.
3. Git plus repository hygiene — layered hooks and CI scanners plus scheduled history scans, push protection, `.gitignore` coverage, history remediation as remove-plus-rotate-plus-assess, signed commits, protected branches, canary tokens.
4. CI/CD plus supply-chain hygiene — forked PRs as untrusted without secrets, least-privilege ephemeral runners, protected environments gating prod, cache and artifact poisoning controls, provenance where deployed, actions pinned by SHA, `persist-credentials: false`, workflow static analysis in CI, install-script allow-lists, and release cool-downs on dependency updates.
5. Workstation plus debugging discipline — shell/history hygiene, temp-file lifecycle, editor/swap/dump controls, clipboard and local-cache suspicion, production-data minimization with sanitized fixtures. Agent and IDE hygiene: key and `.env` files denied from agent context by default, scoped tokens in tool configs that are never committed, transcript retention and redaction, no prod data pasted into prompts.
6. Production-access hygiene — least privilege, just-in-time elevation with approver and expiry, phishing-resistant MFA for human access, audited recorded sessions, separate human/service identities, controlled prod shells. Own category, distinct from keeping secrets out of Git and CI.
7. Exposure plus containment, tiered by blast radius (binding) — tier one (production/customer-bearing): assume compromise with full revoke-scope-evidence-review path; tier two (dev/test-only, proven isolation): rotate, verify, log, move on. Tiering keeps response proportional so the rule stays followed.

Wording rules (binding): history controls are detection, never prevention — the rule is never placing secrets in commands; environment variables are a transport with documented leak paths, not a store; signing proves authorship while branch protection authorizes merges; canaries are non-sensitive by design; clipboard and cache posture assessed per environment; rotation covers credentials, with non-derivable artifacts assessed and contained instead. Production data follows classification plus approved path plus automatic expiry and audit. Eighth habit: hunt secrets across aggregating systems (APM attributes, traces, CI artifacts, image layers, manifests, caches, bundles, agent transcripts, MCP logs, IDE chat history) with scheduled scans routed by tier.

Shape per block: Rule (one sentence) → realistic redacted violation → correct practice → automated or detective control → recovery action where relevant.

Budget: compact (32 blocks incl. forked-PR secret policy, JIT elevation, history-remediation order), est ~3.5k tokens, share 3.5%.

Boundaries: vulnerability mechanisms are 06; protocol credential handling is 07; assessment technique is 08; Spring/Kafka secret wiring instances are their stack files. No protocol mechanics or vulnerability theory repeated here.

---

## Scope: 10-java.txt

Purpose: the Java 25 language, core libraries, concurrency, JVM, and performance reference — modern Java first, legacy shown only for migration or compatibility. Primary stack file: Java knowledge underpins Spring, Kafka, testing, and backend architecture. Every snippet targets JDK 25 unless explicitly version-gated; 26 and 27 appear only in neighbor blocks.

Content, 9 kinds:

1. Modern language plus type modeling — records with compact constructors, sealed hierarchies, pattern matching (instanceof, switch, record patterns, when-guards, explicit null cases), enums with behavior, annotations (retention/target discipline), explicit null handling, flexible constructor bodies (JEP 513, final in 25: validate or compute before `super()`/`this()`, no `this` reference in the prologue).
2. Generics plus collections — PECS, inference, bounded wildcards, immutable factories, SequencedCollection/Set/Map with reversed views (JDK 21+, natural 25 vocabulary), equality/hashCode contract, toList-unmodifiable vs toCollection(ArrayList::new) for guaranteed mutability (Collectors.toList guarantees neither), Optional as return-type convention (fields/params discouraged by convention with reasons, never framed as language rules).
3. Streams plus functional style — laziness and short-circuiting, downstream collectors, parallel-stream costs with associativity requirements, method refs, effectively-final capture, plain loops where imperative logic reads clearer.
4. Core APIs plus errors — checked/unchecked policy, chaining, try-with-resources (suppression semantics), NIO.2 with explicit charsets, java.time with DST-gap tests, JPMS modules (exports/opens, split-package and automatic-module migration pitfalls, jdeps gate), serialization boundaries with explicit formats and serialization filters.
5. Concurrency plus memory model — executor selection (newVirtualThreadPerTaskExecutor named for I/O fan-out), CompletableFuture failure-preserving composition, synchronized/Lock/StampedLock tradeoffs, atomics and concurrent collections, volatile/happens-before, safe publication, interruption protocol.
6. Virtual threads plus structured concurrency — thread-per-task model, pinning (synchronized/native) with JFR evidence, ScopedValue final in 25 as ThreadLocal replacement, StructuredTaskScope as JDK 25 preview (JEP 505 fifth preview: open() factories plus Joiner policies — allSuccessfulOrThrow/awaitAll/anySuccessfulResultOrThrow — compile and run notes). The preview chain continues in 26 and in 27 (JEP 533, seventh preview); it is not final in any release through 27. Migration from reactive complexity where backpressure allows.
7. JVM plus runtime — class loading laziness, JIT tiers and escape analysis at intuition level, G1/ZGC selection as workload-dependent heuristic (generational Shenandoah final in 25, JEP 521), compact object headers (JEP 519, product option in 25, footprint effect measured per workload), ahead-of-time cache for startup (JEPs 514/515), JFR plus async-profiler pair with the 25 JFR additions (CPU-time profiling JEP 509 experimental and Linux-only, cooperative sampling JEP 518, method timing and tracing JEP 520), heap/thread dumps as point-in-time evidence only, and integrity-by-default warnings (JNI/FFM native access, Unsafe memory access, dynamic agent loading). From JDK 27, JFR redacts sensitive command-line arguments, environment variables, and system properties by default.
8. Performance engineering — allocation rate first (heuristic starting example, never a threshold), boxing/strings/collections suspects, contention measured before redesign, batching with explicit overflow policy, quantile-based latency description, JMH methodology (warmup, forks, Blackhole).
9. Modernization plus JDK 25 additions — anonymous-to-lambda, DTO-to-record, reactive-to-virtual, collection idiom upgrades, serialization removal, dead-API replacement with jdeps gate; plus the 25-finalized block (JEP 511 module imports, JEP 512 compact sources with instance main and java.lang IO with its non-implicit statics trap, JEP 513, JEP 510 KDF API) and the preview-neighbors block (JEP 507 primitive patterns, JEP 502 stable values, JEP 470 PEM encodings — preview in 25, never final there). Neighbor status as of JDK 27: primitive patterns fifth preview (JEP 532), stable values continued as Lazy Constants (third preview in 27, JEP 531), PEM third preview (JEP 538), post-quantum hybrid key exchange for TLS 1.3 final (JEP 527).

Epistemic-labeling rule (binding): every claim states its status — language guarantee, API guarantee, explicit non-guarantee, convention, heuristic, or implementation behavior. Performance claims never present heuristics as guarantees.

Preview rule (binding): preview APIs carry JEP number, preview status, and compiler-flag notes; constructor-form structured code from earlier previews repaired to factory form. Open dispute recorded: ScopedValue orElse(null) — file states it throws per JEP 506, JDK-8355023, and the JDK 25 javadoc null clause; a review claimed null is allowed and was rebutted with sources pending a counterexample. Re-check against the JDK 26 and 27 javadoc before release.

Shape per block: Concept (with status label) → modern JDK 25 example → semantics/invariant → why this form → counter-pattern or migration case → verification (compilation, unit test, JFR/JMH result, or review rule). Build-tool exposure (not a main topic): Maven wrapper with .mvn config and toolchain pins, Gradle wrapper with version catalogs and configuration cache — each as calibration context where builds are invoked, detailed treatment lives in 21.

Budget: dense (61 blocks incl. the JDK 25 additions and preview-neighbor chain), est ~6.5k tokens, share 7.5%. Every preview API carries its JEP number and status.

Boundaries: algorithms and complexity analysis are 03; Spring usage is 11; Kafka usage is 13; failure transcripts are 02. Examples self-contained; Spring, SQL, Kafka, or Vue appear only as tiny cross-references.

---

## Scope: 11-spring.txt

Purpose: the Spring Boot 4.1 / Framework 7 reference — configuration, web, data, security wiring, and production operation the way modern Boot apps are actually built. Framework usage; plain-Java semantics stay in 10. Baseline: Boot 4.1 on Framework 7.0.x, Security 7.1, Data 2026.0, Micrometer 1.17. Boot 4.2 and Framework 7.1 land 2026-11.

Content, 8 kinds:

1. Boot 4 foundations — modularized jars and starters, JSpecify null safety, Java 17–26 range with 25 first-class, Jakarta EE 11 baseline (Servlet 6.1, Tomcat 11), Jackson 3 as the default JSON library (new packages; annotations module keeps its legacy package), API versioning support, HTTP service clients (replacing hand-rolled RestTemplates; RestTemplate was deprecated in 7.0, removal-marked in 7.1, gone in 8, so it appears only in migration blocks), core resilience annotations (`@Retryable`, `@ConcurrencyLimit`) now in the framework, Boot 4.1 additions (gRPC auto-configuration, HTTP client SSRF mitigation via `InetAddressFilter`, lazy JDBC connections, OpenTelemetry environment-variable support), configuration binding with validated records, virtual-thread request handling per workload (spring.threads.virtual.enabled with eyes open — blocking I/O fan-out yes, backpressure-sensitive streams no; see 10).
2. Core container — constructor injection as default, profiles and conditional beans, AOP (transactional/caching proxies with self-invocation limits), events, Spring Modulith for enforced module boundaries inside the monolith.
3. Web layer — MVC controllers with validated DTOs, RestClient and declarative HTTP service clients for outbound calls, WebFlux where backpressure demands it (and not elsewhere), exception-to-ProblemDetail mapping (RFC 9457), validation groups, content negotiation, SSE endpoints.
4. Spring Security — Security 7 lambda-DSL filter chain (removed legacy configurers shown as `Legacy:`), method security with @PreAuthorize ownership beans, OAuth2 login plus OIDC, resource-server JWT validation, CORS/CSRF policy, password and session management, multi-factor, one-time-token and passkey support (7.x), Authorization Server living inside Security 7. Security-spine topics live here with 06-mechanism references, never re-taught.
5. Data — JdbcTemplate batch paths, JPA/Hibernate 7 fetch planning (N+1 prevention), transaction propagation and isolation choices, optimistic locking with @Version, outbox writes inside transactions, Testcontainers-backed repository tests.
6. Batch and scheduling — chunk-oriented steps with flush/clear discipline, partitioning, scheduled jobs with distributed locking, idempotent reruns.
7. Testing — slice tests (@WebMvcTest, @DataJpaTest), MockMvc and `RestTestClient` contract assertions, `@MockitoBean`/`@MockitoSpyBean` replacing the removed `@MockBean`/`@SpyBean`, explicit `@AutoConfigureMockMvc`, JUnit 6 baseline, integration tests with containers, security test slice (ownership, roles).
8. Production — actuator exposure discipline, graceful shutdown, config externalization, observability hooks (Micrometer/OTel starter), startup-time checks.

Shape per block: Goal → minimal wiring (config plus code) → why this form → common misconfiguration with its symptom → verification (test slice or actuator evidence).

Mix target: ≥40% code-forward reference blocks (config, wiring, annotations).

Budget: dense (53 blocks incl. Jackson 3 default, @MockitoBean, Security 7 lambda-DSL era Legacy form, scheduled-job distributed lock, SSRF hardening, two Legacy blocks), est ~5.1k tokens, share 7%.

Boundaries: language semantics are 10; protocol rules are 07 (referenced); assessment is 08; failure transcripts are 02. If a block works without Spring on the classpath, it belongs in 10.

---

## Scope: 12-postgresql.txt

Purpose: the PostgreSQL 18 working reference — SQL craft, planner reasoning, concurrency behavior, and operational care. Versioned to 18 with 17-compatible fallbacks noted where they differ. PG 19 is in beta; its changes enter only after GA, each behind a stamp.

Content, 8 kinds:

1. SQL craft — joins, CTEs (incl. recursive), window functions, aggregates, set operations, JSONB operators, arrays, full-text search basics.
2. Schema and constraints — normalization judgment, PK/FK discipline, check/exclusion constraints, migrations that stay backward-compatible (expand-contract).
3. Indexing — B-tree, composite and covering indexes, partial and expression indexes, GIN for JSONB/trgm, index-only scans, write-amplification awareness.
4. Planner reasoning — EXPLAIN (ANALYZE, BUFFERS) reading, join strategies, selectivity and statistics, the keyset-vs-OFFSET decision with measured plans.
5. Concurrency and vacuuming — MVCC snapshots, isolation levels with anomalies named, locking and deadlock reading, VACUUM/autovacuum/bloat, HOT updates, advisory locks as the cross-instance mutex (scheduled jobs, backfill guards).
6. Security and roles — roles and GRANT least privilege, RLS policies with forced mode, SECURITY DEFINER plus search_path discipline, parameterized-only access, connection-string hygiene, SCRAM-only password auth (MD5 auth deprecated in 18), `sslmode=verify-full`.
7. Operations — partitioning strategy, logical replication, backups with PITR rehearsal, connection pooling (transaction mode caveats), upgrade procedure, key metrics and alerts; pg_stat_statements as the slow-query discovery source; PG 18 wire-protocol 3.2 noted with a driver-compatibility check.
8. PG 18 delta set (version-gated) — async I/O (`io_method`, io_uring on Linux), built-in `uuidv7()` (time-ordered ids that make keyset on `(tenant_id, created_at, id)` index-friendly, with the information-leak tradeoff of embedded timestamps), virtual generated columns by default, B-tree skip scan (what it changes about composite-index column order, and what it does not), `RETURNING OLD/NEW`, temporal constraints (`WITHOUT OVERLAPS`, `PERIOD`), data checksums on by default in `initdb` (and the `pg_upgrade` mismatch), `pg_upgrade` preserving planner statistics, OAuth authentication method, buffers shown by default in EXPLAIN ANALYZE, parallel GIN builds.

Shape per block: Task → SQL (parameterized, EXPLAIN-attached where performance matters) → planner or behavior reading → pitfall (the wrong-but-common form) → verification (plan output, test, or monitoring assertion).

Mix target: ≥40% code-forward reference blocks (SQL, EXPLAIN output, DDL).

Budget: dense. Bundle share 6%. est ~5.7k tokens, 54 blocks (added the PG 18 delta set — uuidv7, virtual generated columns, temporal constraints, skip scan, checksum/pg_upgrade, async I/O, EXPLAIN BUFFERS, GIN parallelism — plus deadlock triage, forced RLS, MD5 retirement, and two Legacy blocks). Tokenizer actual pending; JSONB operators and expand-contract migration remain queued. The keyset-pagination evidence pattern from 01/02 recurs here as first-class technique.

Boundaries: Java/ORM usage is 11; failure transcripts are 02; general transaction theory stays practical and Postgres-flavored (no abstract isolation essays — those resolve to lock/monitoring evidence here).

---

## Scope: 13-kafka.txt

Purpose: the Kafka 4.3 KRaft-only working reference — producing, consuming, exactly-once, schemas, streams, and operation without ZooKeeper-era material. KRaft-only throughout; ZooKeeper content forbidden except as a one-line migration historical. Baseline: 4.3.0 (2026-05-22), 4.3.1 patch.

Content, 7 kinds:

1. Core mechanics — topics, partitions, ordering per key, offsets, consumer groups, rebalancing causes, delivery semantics ladder. Two group protocols: the new consumer rebalance protocol (server-side assignment, `group.protocol=consumer`) is the direction, and 4.3 logs a recommendation to leave the classic protocol (KIP-1274) while the broker-side protocol-list config is deprecated for removal in 5.0 (KIP-1237). Cooperative-sticky assignor behavior is taught as the classic-protocol mechanism.
2. Producers — idempotence, batching and compression, retries with backoff, transactional writes, headers for trace and tenant propagation.
3. Consumers — poll-loop discipline, offset commit strategies, cooperative rebalancing, static membership where useful, lag interpretation (error vs capacity gap).
4. Exactly-once and failures — transactions with fencing (unique transactional.id per instance), poison messages to DLQ with cause headers, schema-incompatibility handling, replay runbooks.
5. Schemas and evolution — Avro/Protobuf/JSON Schema, compatibility modes (BACKWARD/FORWARD/FULL) with examples of legal vs breaking changes, subject naming strategies (TopicName vs RecordName chosen per domain), registry auth.
6. Streams, Connect, and Queues — Streams topologies with state stores and standby replicas, rebalance behavior, DLQ support, wipe-local-state-on-startup option (KIP-1259), headers-aware state stores (KIP-1285), `streams-scala` deprecated (KIP-1244); Connect worker config and secret handling; Queues for Kafka (KIP-932, GA) share-group semantics where they replace consumer groups, including the RENEW acknowledgement for long processing (KIP-1222, 4.2).
7. Security and operations — TLS, SASL/SCRAM, OAUTHBEARER with private_key_jwt client assertion (new in 4.3, cross-ref 07), ACLs with per-principal topics (DLQ ACLs mirror sources), KRaft quorum layout across AZs with dynamic controller membership (KIP-853), controller isolation, rack awareness, tiered storage for retention economics, capacity planning, version-pinned upgrades.

Shape per block: Goal → configuration plus minimal code → why these values → canonical failure with its log signature → verification (lag, drill, or alert evidence).

Mix target: ≥35% code-forward reference blocks (config, producer/consumer snippets).

Budget: dense. Bundle share 4.5%. est ~4.8k tokens, 44 blocks (added the new consumer group protocol/KIP-1237 posture, the 4.3 OAUTHBEARER assertion + BrokerJwtValidator note, and two Legacy blocks for ZooKeeper-era config and classic-producer fencing); est ~7.4k, 55 blocks after clean-room shipper-side additions (offset registry, multiline stitching, file dead-letter, broker-backpressure propagation — no mined lineage).

Boundaries: Java client mechanics stay minimal here (language in 10); failure transcripts are 02; outbox pattern mechanism is shared with 19 (each file states its own side: relay here, pattern rationale there).

---

## Scope: 14-http-api.txt

Purpose: the HTTP API design reference — semantics, contracts, versioning, and resilience patterns for REST plus SSE/WebSockets/webhooks. Design knowledge; BOLA/BFLA assessment technique lives in 08.

Content, 7 kinds:

1. HTTP semantics — methods, status codes used precisely, headers that matter (ETag with If-Match/If-None-Match for optimistic concurrency, Cache-Control per RFC 9111, Retry-After per RFC 9110 as the settled throttle signal, legacy X-RateLimit-* as conventions with documented reset semantics, IETF RateLimit/RateLimit-Policy only as draft-v11 alongside — not an RFC, syntax still moving), content negotiation, HTTP/3 at the edge with fallback. Labeled draft, never settled: the Idempotency-Key header (draft-ietf-httpapi-idempotency-key-header).
2. REST and OpenAPI — resource modeling, naming, OpenAPI-first vs code-first with generation gates (3.1 baseline, 3.2 noted with an as-of stamp), error contract shape (RFC 9457 problem details), pagination (keyset default with opaque base64 cursors never parsed client-side, OFFSET only with justification), filtering/sorting safely.
3. Reliability patterns — idempotency keys with same-key-different-payload 422s, retries with backoff plus jitter, timeouts per hop, circuit breakers with tuned thresholds, hedging where appropriate.
4. Caching and consistency — ETags and conditional requests, Cache-Control tiers, read-your-write strategies, stale-while-revalidate boundaries.
5. Real-time and events — SSE with buffering discipline, WebSocket upgrade and heartbeat policy (with mid-stream auth expiry handling), webhook design (signed raw bytes, replay cache, retry schedule; HTTP message signatures per RFC 9421 as the standards-based alternative), API-to-Kafka handoff points.
6. Versioning and compatibility — additive change discipline, versioning strategy (URI/date/media-type) with sunset policy carried in `Deprecation` (RFC 9745) and `Sunset` (RFC 8594) headers plus a successor `Link`, breaking-change checklist, client migration windows.
7. API-side security mechanism — BOLA/BFLA design controls, auth-per-route matrix, rate/quote caps, SSRF-safe outbound fetching (resolve → validate → connect), unsafe-consumption validation. Mechanism home shared with 06; testing home is 08.

Shape per block: Design decision → contract or config fragment → why (with the failure it prevents) → versioning/compat note → verification (contract test or header assertion).

Mix target: ≥10% code-forward reference blocks. the honest floor is the artifact-level truth (5/41 blocks land over 60% code tokens, measured 12%); anything more would be an artifact of the shape, not the content.

Budget: dense. Bundle share 3.5%. est ~4.4k tokens, 41 blocks (added H/3 fallback + per-hop timeouts, RFC 9421 message signatures, IETF RateLimit draft note, explicit cache tiers with stale-while-revalidate boundaries, and two Legacy blocks).

Boundaries: protocol auth mechanics are 07; testing technique is 08; Spring wiring is 11; TanStack consumption is 17. If a block's core is "how to test X", it belongs in 08.

---

## Scope: 15-typescript.txt

Purpose: the TypeScript 6-to-7 working reference — migration deltas, strict configuration, and the advanced type system used heavily in TanStack-heavy frontends. Code must pass both tsc6 and tsc7 unless the block documents a 7-only behavior. Baseline: 7.0 stable (2026-07), 6.0 bridge (2026-03).

Content, 6 kinds:

1. 6→7 migration — Go-native compiler expectations (speed, same semantics), tsc/tsc6 side-by-side, removed flags and new defaults as hard errors (strict, module bundler/esnext, stableTypeOrdering), rootDir/types surprises, new parallelism flags (`--checkers` and `--builders` experimental, single-threaded mode), the 6-alias package for tools that need the JS API until 7.1, editor support gap until the 7.1 API with the sanctioned interim setup. Verified rule: code that compiles cleanly on 6.0 with stableTypeOrdering on and no ignoreDeprecations compiles identically on 7.0.
2. Configuration — tsconfig for SPA vs library, strict family flags individually understood, moduleResolution bundler, path aliases without baseUrl, erasableSyntaxOnly for native-transpiler-safe code (no enums, namespaces, or parameter properties), verbatimModuleSyntax for import discipline, incremental and project references.
3. Type system core — unions/intersections, discriminated unions, narrowing (including custom guards), literal and template-literal types, keyof/typeof, satisfies, utility types used precisely.
4. Advanced types — generics with constraints, defaults, and const type parameters, conditional types with infer, mapped types with key remapping, variance intuition for API design, declaration files and module augmentation for libraries.
5. Runtime boundary — validation at the edge (schemas for API responses, never bare casts; Standard Schema–compatible validators such as Zod 4 and Valibot), unknown-first handling of third-party JSON, error narrowing, exhaustive-switch helpers for domain unions, explicit resource management with using (Symbol.dispose) for scoped cleanup.
6. Ecosystem — Node 24 LTS baseline with 26 promoted late 2026-10; native type stripping stable on current Node lines, which is why erasable-only TS matters; pnpm workspaces with frozen lockfiles, install-script allow-lists, and release cool-downs; package exports discipline; test tooling (type-check as a CI gate); performance (isolatedModules-era habits updated for 7).

Shape per block: Goal → snippet compiling under both compilers (or marked 7-only) → why this form → legacy/counter form with its failure → verification (tsc clean both versions, or runtime test).

Mix target: ≥45% code-forward reference blocks (dual-compiler snippets).

Budget: dense. Bundle share 4%. est ~3.6k tokens, 37 blocks (added baseUrl/moduleResolution-bundler migration, native type-stripping + erasableSyntaxOnly rationale, project-reference build + 7.x parallelism).

Boundaries: Vue and TanStack usage are 16/17 (plain TS here); failure transcripts are 02; Node backend patterns stay minimal (this is a frontend-support file, not a Node server file).

---

## Scope: 16-vue.txt

Purpose: the Vue 3 Composition-API reference — reactivity, components, state, routing, SSR — with the security spine embedded. Framework usage; TypeScript mechanics stay in 15. Baseline: Vue 3.5.x stable (3.5.43, 2026-09-17). Vue 3.6 (RC, alien-signals reactivity refactor, opt-in Vapor Mode) appears only in one labeled pre-release neighbor block; stable code samples use the VDOM compiler.

Content, 7 kinds:

1. Composition core — script setup, ref/reactive/computed/watch semantics, lifecycle use, provide/inject scoping, props/emits typing (incl. defineModel for two-way bindings, reactive props destructure), slots and directives, useTemplateRef for template refs, useId, onWatcherCleanup, lazy-hydration strategies, Suspense boundaries for async setup, composable extraction rules.
2. Reactivity pitfalls — ref unwrapping in templates vs code, reactive destructuring loss, watch vs watchEffect selection, effect scope cleanup.
3. State with Pinia — store shape, getters vs computed, actions with async discipline, store testing, persistence boundaries (never secrets).
4. Routing and SSR — Vue Router guards (auth/ownership checks client-side as UX only, enforcement server-side), one router per app (official Vue Router vs TanStack Router's Vue adapter, a decision block), lazy routes, Nuxt SSR data fetching, hydration matching (dehydrate exact queries), SEO/meta handling.
5. TypeScript integration — typed props/emits, generic components, store typing, template type-checking in CI (vue-tsc, which stays on TS 6 until the 7.1 API), the dual-compiler note shared with 15.
6. Frontend security spine — XSS via interpolation-only rendering, v-html ban with sanitizer-exception process, Trusted Types and CSP coordination, token storage (memory access plus httpOnly refresh), CSRF posture, untrusted-URL guards.
7. Testing and architecture — component tests, composable unit tests, E2E on critical flows, feature-folder organization, API-client layer shared with TanStack keys.

Shape per block: Goal → component/composable snippet → reactivity or design reasoning → pitfall with its symptom → verification (type-check, test, or hydration assertion).

Mix target: ≥40% code-forward reference blocks (SFC snippets, composables).

Budget: dense. Bundle share 3.5%. est ~3.5k tokens, 37 blocks (added Suspense + provide/inject + lazy hydration, reactive-prop destructure pitfall, and CSP/Trusted-Types/token-storage security block).

Boundaries: TS mechanics are 15; Query/Router/Table server-state is 17; failure transcripts are 02. If a block works in plain TS without Vue, it belongs in 15.

---

## Scope: 17-tanstack.txt

Purpose: the TanStack reference with Vue Query v5 semantics — server-state architecture done right: keys, caching, mutations, and the router/table siblings. Usage patterns; reactivity internals stay in 16.

Content, 6 kinds:

1. Query foundations — query keys as factories (typed tuples, no undefined drift), `queryOptions` helpers, query functions with AbortSignal, stale/GC time selection, cache behavior and structural sharing.
2. Mutations and optimism — mutation lifecycle, optimistic updates with rollback context, retry policy per mutation kind, cancellation coordination with in-flight queries.
3. Pagination and infinity — cursor-based infinite queries (pageParam discipline, null termination), placeholder data vs suspense boundaries, prefetching and preloading strategy.
4. SSR and persistence — dehydrate exact first-page queries, hydration matching, persister boundaries (never auth material), focus/reconnect refetch policy.
5. Router and Table — TanStack Router route trees with loaders and guards (the Vue adapter `@tanstack/vue-router` ships in the same 1.x release stream as the React and Solid adapters; stability labeling confirmed at implementation), search-param typing with Standard Schema validators (zod/valibot), Table headless patterns (sorting/filtering/pagination state owned explicitly). The Vue Start package is recognition only. TanStack Virtual explicitly out of scope (separate package; windowing noted only where Table needs it).
6. TypeScript-heavy usage — end-to-end typed keys/loaders/mutations, error-type narrowing, contract drift detection (response-shape tests shared with 14).

Shape per block: Goal → key plus hook snippet → caching/behavior reasoning → misconfiguration with its symptom (stale forever, duplicate pages, lost mutations) → verification (test with fake timers/server, render-count or network assertion).

Mix target: ≥35% code-forward reference blocks (queryOptions, mutation setups).

Budget: dense. Bundle share 3%. est ~3.5k tokens, 33 blocks (added the missing v4→v5 migration renames block, queryOptions/optimistic-mutation reconciliation block, and two Legacy blocks; inert sibling slots — infinite query, persistence, and TanStack Table ownership — noted for the sourcing pass).

Boundaries: Vue reactivity is 16; API contract design is 14; failure transcripts are 02. Version-pinned to v5 semantics (vue-query 5.104.x) with a v4→v5 migration block: `cacheTime`→`gcTime`, `isLoading`→`isPending` (and `isLoading` now means pending-and-fetching), status `loading`→`pending`, `keepPreviousData`→`placeholderData`, object-only call signatures, `useErrorBoundary`→`throwOnError`, `onSuccess`/`onError`/`onSettled` removed from `useQuery` (kept on mutations). v6 lines exist on neighboring adapters (Svelte 6.x, Solid 6.0 pre-release) while core/react/vue remain v5; when they re-sync at v6 stable this file gets a migration pass, same posture as the TS dual-compiler rule.

---

## Scope: 18-testing.txt

Purpose: the testing strategy reference — levels, techniques, and diagnosis across the stack. Framework-agnostic strategy with Spring/Vue/PG instances; tool syntax stays minimal.

Content, 8 kinds:

1. Levels and seams — unit vs integration vs component vs contract vs E2E, what each owns, the inverted-triangle anti-patterns, seam selection (ports over mocks where behavior matters).
2. Backend testing — slice tests, Testcontainers Postgres/Kafka, repository tests with planner assertions, security tests (ownership matrices, role matrices), concurrency tests.
3. Frontend testing — component tests, composable tests, Query hook tests with fake servers, E2E on critical flows, visual/hydration assertions, snapshot tests gated to stable markup (one behavior per snapshot, updates deliberate, never blind -u).
4. Contract and API testing — OpenAPI conformance, consumer-driven contracts for internal APIs, error-contract assertions, backward-compatibility gates on contract change.
5. Property and mutation testing — property invariants (pagination concatenation equals full query), mutation score as a suite-quality signal, targeted (not blanket) mutation runs.
6. Load, performance, and chaos — k6-style load shapes, SLO-based pass bars, fault injection (slow deps, kills mid-relay), game-day drills with timed runbooks.
7. Diagnosis — red-green triage order (isolation before theory), determinism control first (fake timers, seeded RNGs, fixed ports) before any quarantine, flake quarantine process with expiry, coverage as a map (never a target), failing-suite bisection.
8. Verifying AI-assisted code — generated tests must fail against the pre-fix code (red-green proof), mutation score applied to agent-written suites to catch tautological assertions, property tests over generated examples, snapshot approvals read by a human, golden-task suites for agent workflows with sandboxed replay.

Shape per block: What to test → minimal example → why this level/technique → common anti-pattern with its cost → verification (the test itself, or suite-health metric).

Mix target: ≥25% code-forward reference blocks (test bodies, fixtures).

Budget: dense. Bundle share 3%. est ~3.2k tokens, 35 blocks (added contract tests, property-test invariant, determinism/quarantine discipline, SLO-gated load, relay fault drill, agent red-green proof).

Boundaries: failure transcripts are 02 (which shows failures; 18 shows the testing that prevents and catches them); observability of production is 20; architecture decision records are 19. Tool-version specifics stay out — techniques, not CLI flags; test-framework majors (JUnit 6, Testcontainers 2.x) live in the ledger and in 02 upgrade-delta loops.

---

## Scope: 19-architecture.txt

Purpose: the system-design reference — styles, patterns, tradeoffs, and decision records for the modular-monolith-to-event-driven range this stack lives in. Judgment with reasons; the ADRs home per the 05 boundary test.

Content, 7 kinds:

1. Styles and structure — SOLID applied at module scale, DDD bounded contexts with ubiquitous language, hexagonal ports/adapters, modular monolith with enforced boundaries, microservice extraction criteria (and non-criteria).
2. Events and consistency — event-driven topology, CQRS where read/write asymmetries justify it, sagas with compensations, outbox pattern (pattern rationale here, relay mechanics in 13), idempotency as architectural property.
3. Resilience — retries/backoff/jitter, circuit breakers, bulkheads, timeouts, backpressure with explicit overflow policy, graceful degradation tiers. Instance: an LLM or other third-party AI dependency behind a port with timeout, spend cap, output validation, and a deterministic fallback.
4. Data architecture — per-service data ownership, cross-service query strategies (composition vs replication vs request), migration safety (expand-contract), RLS-aware service design.
5. Caching strategy — layers (HTTP, application, read models), invalidation ownership, stampede protection, cache-vs-source-of-truth discipline.
6. Evolution — versioning, backward compatibility budgets, deprecation and sunset process, strangler patterns for legacy replacement, decision reversibility ratings, fitness functions guarding architectural invariants in CI.
7. ADRs — decision record shape (context, options with tradeoffs, decision, consequences, revisit triggers), worked records for this stack's real decisions (polling vs Debezium with tripwire, saga vs 2PC, virtual threads vs reactive, tenancy model: shared schema with RLS vs schema-per-tenant vs database-per-tenant, hand-rolled saga vs durable-execution engine).

Shape per block: Decision context → options with honest tradeoffs → recommendation with conditions → reversibility note → verification (metric, review gate, or revisit trigger).

Mix target: prose-first by design — narrative/ADR blocks dominate; code-forward reference blocks stay under 20% (instances home in 13/12, which carry the code). Rationale: the block's hardest sentence here is a tradeoff, not a snippet.

Budget: dense. Bundle share 3%. est ~4.3k tokens, 41 blocks (added the five SPEC-mandated ADR worked records — tenancy model, polling-vs-Debezium, saga-vs-2PC, virtual-vs-reactive, LLM-behind-a-port — plus expand-contract; bounded-context/hexagonal instances queued for the sourcing pass).

Boundaries: hardest-sentence test with 05 (tradeoff here, sequencing there); mechanism details live in stack files (13 relay, 12 RLS, 14 contracts); math foundations stay in 03. No ivory-tower patterns without a stack instantiation.

---

## Scope: 20-observability.txt

Purpose: the production-visibility reference — logs, metrics, traces, and alerts that make incidents diagnosable without leaking secrets. Practice with schemas; theory stays minimal.

Content, 6 kinds:

1. Structured logging — one JSON schema (ts, level, service, route, tenant, ms, requestId), context propagation via interceptors, allow-listed fields with redaction tests.
2. Metrics — RED per service, USE per resource, histogram discipline (no averaged latencies), cardinality budgets with label allow-lists.
3. Tracing with OTel — traceparent propagation, span naming, semantic-convention versions pinned (only stable groups assumed), sampling strategy (head rules plus tail-based retention of errors and slow traces), trace-to-log joining on one key, exemplars linking metrics to traces, baggage never carrying tenant or personal data across a trust boundary, Boot's OTel starter and 4.1 environment-variable support as the stack anchor.
4. SLOs and alerting — SLI selection, error-budget policy with deploy gating, symptom-based alerts with runbooks, page-vs-ticket routing tuned from drills.
5. Profiling and diagnostics — continuous JFR in production (with JDK 27's default redaction of sensitive arguments and properties), flame-graph reading, heap/thread dump pairing, overhead budgets; the OTel profiling signal noted as experimental.
6. Security-aware telemetry — secret-shaped value scanning, PII minimization, tenant-scoped access to telemetry, audit of who viewed what, and an audit trail for agent actions (who or what acted, which tool, which approval).

Shape per block: Signal needed → schema or config fragment → how it reads during an incident → leak or noise anti-pattern → verification (drill, scan, or dashboard assertion).

Mix target: ≥25% code-forward reference blocks (JSON log schemas, OTel config, alert rules).

Budget: dense. Bundle share 2.5%. est ~2.6k tokens, 26 blocks (added the Boot OTel starter 4.1 anchor block and the tenant/baggage trust-boundary block); est ~5.0k, 35 blocks after clean-room pipeline additions (loss ordering, attribute allow-list, archival lifecycle, fleet rollout — no mined lineage).

Boundaries: testing is 18 (which verifies behavior pre-prod); Java tooling mechanics are 10; incident containment is 06/09. If a block debugs code rather than production, it belongs in 02.

---

## Scope: 21-linux-infra.txt

Purpose: the full-stack ops reference — Linux, Docker, Nginx, CI/CD, and Kubernetes for running the stack above. Commands and configs that work on current stable releases; full-stack coverage per the agreed span.

Content, 7 kinds:

1. Linux core — processes and signals, filesystems and permissions, systemd units with hardening (`systemd-analyze security` as the check), journald, networking (DNS resolution order, sockets, TLS verification), SSH discipline (keys, bastion with ProxyJump, agent forwarding bans; recent OpenSSH defaults to a post-quantum hybrid key exchange).
2. Docker — multi-stage builds with layer-cache ordering, distroless or hardened minimal base images with non-root users, frozen lockfiles in images, secret mounts (never COPY of keys), image scanning, build-time SBOM and provenance attestations, digest pinning, compose networking and DNS, resource limits.
3. Nginx — reverse proxy with forwarding headers, TLS 1.2+ with modern ciphers (1.3 preferred; hybrid post-quantum groups depend on the linked OpenSSL version) and HSTS (legacy isolated), `http2 on;` and HTTP/3 listener notes, certificate automation under shrinking lifetimes (OCSP stapling is no longer worth configuring where CAs ended OCSP), WebSocket upgrade with long timeouts, SSE buffering off, gzip/caching tiers, rate limiting and connection caps, ambiguous-framing rejection. This is the standalone nginx server; the Kubernetes ingress-nginx controller is covered in kind 5.
4. CI/CD — GitHub Actions workflows (pinned actions by hash, default-empty `permissions`, secretless fork jobs, no `pull_request_target` checkout of untrusted code, workflow linters in CI, OIDC-to-cloud credentialless deploys per 09, environment protection for prod), build matrices, cache keys with lockfile hashes, artifact provenance, dependency-update cool-downs, build-tool exposure: Maven/Gradle wrapper enforcement (no unwrapped builds), Gradle configuration cache and version catalogs, Maven toolchain and .mvn discipline, daemon/parallel settings as CI performance levers — exposure-level, not a build manual.
5. Kubernetes — Gateway API as the default for new work (ingress-nginx retired 2026-03; Ingress2Gateway for conversion; the Ingress API itself remains), deployments with probes (liveness vs readiness vs startup separated), resource requests/limits with OOM behavior understood, PodDisruptionBudgets for voluntary-disruption safety, secrets from the manager (never literals), restricted Pod Security profile, network policies, native sidecar containers, HPA on sane signals, rollout strategy with rollback.
6. WireGuard and private networking — mesh basics, key rotation, peer allow-listing, DNS inside the mesh, optional preshared keys as a labeled post-quantum hedge (heuristic, not a guarantee).
7. Deploy operations — blue-green and rolling strategies, migration-aware sequencing (migrations before code, expand-contract), smoke checks post-deploy, rollback decision criteria shared with 05's pre-committed rules.

Shape per block: Goal → config or command fragment → why these values → canonical failure with its log signature → verification (probe, scan, or drill evidence).

Mix target: ≥45% code-forward reference blocks (unit files, compose/k8s manifests, workflow YAML).

Budget: dense. Bundle share 3.5%. est ~3.3k tokens, 35 blocks (added Gateway API default, TLS-1.3/no-OCSP posture, OpenSSH post-quantum hybrid, and two Legacy blocks). Tokenizer actual pending at implementation.

Boundaries: failure transcripts are 02 (which replays failures; 21 states the correct configuration); app wiring is 11; secrets lifecycle theory is 09. Version-sensitive flags verified before writing.

---

## Scope: 22-python.txt

Purpose: the Python support-file reference — modern typing, async, pytest, packaging, and CLI/data tooling for the calibration scripts, backtest harnesses, and glue code around the Java stack. Supporting role; depth stays proportional.

Content, 6 kinds:

1. Modern Python — current-stable idioms (version verified at implementation time; deferred annotation evaluation, template strings, and free-threaded builds are labeled by the release that introduced them), type hints with strict checking (mypy/pyright; newer Rust-based checkers named for recognition only), dataclasses vs attrs vs Pydantic boundaries, pattern matching where it clarifies.
2. Async — asyncio task groups, cancellation and timeouts, async generators for streams, sync/async boundary discipline.
3. Pytest — fixtures and factories, markers (including async configuration), parameterized boundary tests, property-based testing with Hypothesis.
4. Packaging and CLI — pyproject discipline, uv for env/lock/install with inline script metadata (PEP 723), dependency groups (PEP 735) and the standard lock file format (PEP 751), ruff for lint/format, Typer/argparse CLIs with typed options, script entry points for corpus tooling.
5. Data and quant tooling — pandas/polars frames for strategy analysis, notebook-to-script discipline, reproducible seeds, CSV/Parquet interchange hygiene.
6. Interop notes — calling Python from JVM pipelines (and vice versa) safely, contract schemas at the boundary, error propagation across runtimes.

Shape per block: Goal → snippet → why this form → pitfall → verification (type-check, test, or repro evidence).

Mix target: ≥40% code-forward reference blocks.

Budget: compact. Bundle share 2.5%. Supporting file; breadth over depth. est ~2.4k tokens, 25 blocks (added the PEP 723/735/751 packaging block — no "---" markers inside the snippet, per the delimiter rule).

Boundaries: Java equivalents stay in 10 (no language comparisons beyond one line); failure transcripts are 02; finance math is 23 (which may show Python snippets only as worked calculations, never as tooling advice).

---

## Scope: 23-finance-quant.txt

Purpose: the fenced finance slice — equities, options, greeks with GEX, volatility, and quant statistics for the user's occasional algo work. Small and explicitly fenced so its weight tunes independently; pure math foundations stay in 03.

Content, 6 kinds:

1. Market basics — order types, American vs European exercise styles, OHLCV semantics, splits/dividends adjustments, microstructure intuition (spread, depth, impact), US equity settlement cycle (T+1 since 2024-05-28, date-stamped).
2. Options foundations — calls/puts, moneyness, expiry/exercise/assignment, cash- vs physically-settled and AM vs PM settlement conventions, payoff diagrams in words.
3. Pricing — Black-Scholes assumptions and limits, binomial intuition, funding and carry in pricing intuition, implied vs historical volatility, smile/skew/term structure reading.
4. Greeks and gamma positioning — delta/gamma/theta/vega/rho plus second-order (vomma/vanna/charm/veta), GEX/DEX construction, positive/negative gamma regimes, pinning mechanics, and the short-dated (0DTE) share of volume as a reason the aggregate profile shifts intraday. Epistemic label (binding): the dealer-sign convention behind GEX is an assumption about positioning, not an observation.
5. Quant statistics — log returns, volatility estimators, Sharpe/Sortino with their gaming modes, max drawdown, Z-scores and hypothesis tests (applied here, taught in 03), regression readouts for factor exposure.
6. Backtest hygiene — lookahead prevention, survivorship, transaction costs and slippage, overfitting and multiple-testing correction, paper-vs-live divergence checklist.

Shape per block: Concept → worked micro-example with numbers → assumption stated → common misuse with its cost → verification (recomputed figure or checklist assertion; the recompute gate runs on every number).

Budget: compact and fenced. Bundle share 2.5%. Weight tunes via manifest without touching SE files. Counted: 25 blocks, pre-check ≈2.3k tokens (est.).

Boundaries: pure statistics and derivations are 03 (23 applies, never re-teaches); no proprietary strategies, no live signals, no account-specific content — textbook mechanics only.

---

## Scope: 24-react.txt

Purpose: retention-only React coverage — enough hooks, rendering, and composition knowledge for migration literacy and Vue comparison. Smallest file by design; React is not a target stack.

Content, 4 kinds:

1. Core model — JSX, components, props/state discipline, hooks rules (useState/useEffect/useMemo/useCallback/useRef), React 19 use() and actions noted for recognition only, `useEffectEvent`, context scoping.
2. Rendering — reconciliation intuition, controlled vs uncontrolled inputs, composition patterns (children, render props legacy, custom hooks), and the React Compiler's automatic memoization changing how much manual useMemo/useCallback translators will see.
3. Comparison with Vue — reactivity vs re-render models, refs vs signals-adjacent patterns, effect cleanup parallels, ecosystem mapping (Router, Query, state).
4. Migration notes — reading React code during porting, common translation shapes (useEffect to watch, context to provide/inject plus Pinia), pitfalls translators introduce. One boundary note on Server Components: the Flight protocol was the target of a critical 2025 RCE class (React2Shell, CVE-2025-55182), cross-referenced to 06 for deserialization-in-flight, with nothing beyond that.

Shape per block: Concept → short snippet → Vue parallel where one exists → translator pitfall → check.

Budget: compact. Bundle share 1%. Retention weight only. est ~1.9k tokens, 18 blocks (added React Compiler memoization model, useEffectEvent, and the RSC/Flight boundary note including the React2Shell CVE); est ~3.1k, 30 blocks after the se2 expansion (+12 hooks/keys/context and porting-recognition blocks).

Boundaries: depth lives in 16/17 (Vue/Query); no React ecosystem depth (no Next.js, no React Server Components beyond a boundary note). If a block has no Vue parallel or migration value, it does not belong here.

---

## Scope: 25-privacy-gdpr.txt

Purpose: the GDPR compliance reference — rights, retention tensions, assessments, and breach discipline for backends holding personal data. Standalone file (not grouped with ecommerce) so its weight tunes independently; retention-vs-erasure tension with backups, telemetry, and logs made explicit.

Content, 6 kinds:

1. Lawful basis per purpose — contract, consent (granular, withdrawable), legitimate interest with balancing test, legal obligation; purpose registry per flow.
2. Data-subject rights — access (complete multi-system compilation on time), erasure via a deletion map (all stores registered, crypto-shredding where rewrite is infeasible), portability in structured formats with a dictionary. Pseudonymised data remains personal data for whoever holds the key, so shredding claims are assessed from the key-holder's side.
3. Retention vs erasure — legal schedules overriding narrowly, exempt-copy deletion at expiry, backup strategy chosen with erasure in mind (shredding keys or bounded retention with re-deletion on restore, proven by drill).
4. DPIA and design duties — trigger checklist, mitigations as launch blockers, privacy-by-design (minimization, purpose limitation, private defaults), special-category prohibitions.
5. Breach discipline — 72-hour clock from awareness, phased notification, runbook with hour-0/24/48 milestones, tabletop drills timed against the bound.
6. Transfers and vendors — adequacy/SCCs derogations per flow with impact assessments (mechanism status carries an as-of stamp because it is litigated and moves), Article-28 terms, sub-processor register, procurement gated on mechanism entries.

Shape per block: Concept → rule → practice → verification (drill, matrix review, or audit evidence).

Budget: ~12 blocks, compact and fenced. Est ~1.4k tokens, 13 blocks; est ~2.7k, 25 blocks after the se2 expansion (+12 consent/erasure/processor/breach-practice blocks). Bundle share 1.5%. The six SPEC kinds all map to a topic; the adjacent-regime pointer block completes the spec.

Boundaries: vulnerability classes are 06; hygiene habits are 09; telemetry specifics are 20; backup mechanics are 12. No jurisdiction-specific legal advice beyond GDPR mechanics — counsel owns interpretation. Neighboring EU regimes (Data Act, NIS2, CRA, AI Act) get one cross-reference line each and no content.

---

## Scope: 26-ecommerce.txt

Purpose: the state-of-the-art ecommerce backend reference — catalog to peak-season readiness at a bar above off-the-shelf platforms, with explicit why-it's-better reasoning per pattern (single truth with overlays, state machines over flags, reservation over races). Backend only; no storefront styling.

Content, 7 kinds:

1. Catalog and variants — PIM truth with channel overlays, SKU discipline per purchasable combination, bundles as explicit containers.
2. Pricing and promotions — precedence-ordered rule engine with replayable itemization, versioned promotion definitions with caps and kill switches.
3. Cart and checkout — snapshot carts with expiry, checkout as an enumerated state machine (no boolean-flag states), idempotent transitions.
4. Inventory and fulfillment — reservation with TTL against oversell, multi-node sourcing decisions, split-shipment communication, tracking aggregation.
5. Payments on the current Stripe API. Newest major is `endive` (2026-09-30), after `dahlia`; it removes the `payment_method_types` parameter from PaymentIntents and SetupIntents, so payment methods are driven by dynamic configuration rather than hard-coded lists. Pin the API version through the SDK, and create the webhook endpoint at the SDK-pinned version. Monthly releases are non-breaking and majors come twice a year. One PaymentIntent per order/session with reuse across retries, automatic 3DS via the SCA engine with exemption strategy, version-pinned webhooks verified on raw bytes driving fulfillment (never client callbacks), refunds/disputes as first-class flows, subscriptions with test clocks, tax by jurisdiction. Agentic checkout (delegated payment tokens) gets one block at most, labeled emerging, with protocol status verified at implementation.
6. Discovery and demand — faceted search with relevance test sets, graceful recommendations with cold-start fallbacks, marketplace seller gating with ledger discipline and holdbacks.
7. Operations — returns/RMA as a designed loop, preference-respecting notifications with sender separation, versioned analytics events, peak-season drills with third-party limit confirmations.

Shape per block: Goal → pattern → why (with the better-than-platform reasoning where it matters) → pitfall with its cost → verification (test, drill, or audit).

Budget: ~25 blocks, dense but fenced. Est ~2.3k tokens, 23 blocks before the 2026-10 Legacy-pair patch; est ~2.5k, 25 blocks; est ~4.3k, 40 blocks after the se2 expansion (+15 checkout/inventory/payment/operations blocks). Bundle share 2%.

Boundaries: webhook and idempotency mechanics defer to 14 (and 13 for the event handoff). GDPR constrains this file via 25 (erasure vs order history, marketing consent); finance math stays in 23. No real account data, no live keys — textbook mechanics only.

---

## Scope: 27-adversarial-walking-patterns.txt

Purpose: the adversarial-hygiene mirror of 08 — one block per stack surface showing how a correct-looking configuration is quietly defeated. It is weighted (share 2), so its text quality is bundle quality: a garbled block here is calibrated into the model exactly like a good one.

Shape per block: the 08 field names, verbatim — `Target:` → `Fixture:` → `How it fails:` → `Pass bar:` → `Failing evidence:` → `Impact:` → `Remediation pointer:` → `Regression test:`. One surface per block, stack files in bundle order.

Repair pass (2026-10, binding): all ten surface targets and their substance are kept; nothing is dropped for length and no block is padded to filler. The prose is rewritten to the field names above at the same coverage; the two leading `#` lines come out (the global convention forbids headings, and this file is the only bundle-scope violator); the mojibake and mangled non-ASCII are removed, including the Kafka block's `Remediation pointer:` line; `Passing bar:` becomes `Pass bar:`. The register follows the global Realism rule, so each block reads like the finding it mirrors.

Budget: 10 blocks, share 2%. Measured pre-check after the 2026-10 repair: 13.6 KB → est ~2.5k tokens (~250/block, at the ceiling of the reference band — the eight-field shape costs that much, and the old est ~1.0k reflected prose that left fields out).

Boundaries: probe technique is 08, mechanism is 06, exploitation depth is 31, the correct configuration is the stack file. This file earns its weight by being the shape-mirror that shows the configuration discipline failing under adversarial drift, not by introducing new vulnerability classes.

---

## Scope: 31-offensive-security.txt

Purpose: the attacker's side of this exact estate — how a Java/Spring/Postgres/Kafka/Kubernetes estate is actually breached, what leaves the building, what the move looks like in the telemetry afterwards, and what would have stopped it. At Q4 and below the corpus does not teach, it selects: it decides which of the base model's existing offensive knowledge survives rounding. A polite corpus therefore preserves the sanitized defensive summary and rounds away the payload shapes, the chain reasoning, and the register — which is precisely the competence that has to survive, because recognition and triage are generative tasks: a model that cannot produce the string cannot diagnose the log line that contains it.

Why it is its own file: offense needs one owner. 06 owns the mechanism, 08 owns the probe, 09 owns the habit, and none of them can carry a chain end to end without stopping being what they are. Separating it lets the offensive share tune independently of the defensive files it feeds, so the tuning loop sees an offensive gain and a defensive KL regression in one comparison, and lets 06/08 keep their principle-first shape instead of absorbing tooling noise. Bundle-scope, weighted 3.0, funded inside the security band.

Content, 9 kinds:

1. Recon and surface discovery — certificate-transparency and ASN pulls, git and `.env` disclosure probing, actuator and OPTIONS/HEAD exposure, forgotten staging and v1 hosts, wordlist and vulnerability scanning against a real inventory, code-hosting searches for leaked keys, what a scanner sees versus what the route table says [T1595.001, T1595.002, T1595.003, T1590.001, T1589.001].
2. Initial access on the web and API tier — JNDI lookup injection (Log4Shell, CVE-2021-44228, published 2021-12-10), data-binder class manipulation (Spring4Shell, CVE-2022-22965, published 2022-04-01), actuator-backed expression injection (CVE-2022-22947, published 2022-03-03), Java deserialization gadget chains, out-of-band XXE entity fetch, JWT algorithm and `kid` abuse, SSRF to the instance metadata endpoint, BOLA scripted into a bulk dump, request smuggling across a gateway/parser split and HTTP/2 Rapid Reset (CVE-2023-44487, published 2023-10-10) [T1190, T1110.003, T1552.005].
3. Supply chain and CI as initial access — the 2025-09 self-propagating npm worm class, dependency confusion against scoped internal names, `pull_request_target` fork runs holding production secrets, mutable action tags versus pinned SHAs, poisoned build cache, protestware and typosquats, MCP tool-description poisoning as the registry attack replayed against agents [T1195.002, T1199].
4. Foothold in the container and on the host — what a `www-data` shell can read without an exploit: `/proc/self/environ` and `/proc/1/cmdline` [T1003.007], mount table, mounted service-account token, capability and user-namespace posture; sudo caching [T1548.003]; the runc file-descriptor leak escape (CVE-2024-21626, published 2024-01-31); privileged pod and `hostPath` mounts to the node; `nsenter` onto PID 1; the residue each leaves [T1059.004, T1611, T1613].
5. Kubernetes and cloud lateral movement and privilege escalation — `kubectl auth can-i --list`, `pods/exec` as remote-code execution [T1609], secrets as base64 and not encrypted, hostile pod spec with the node filesystem mounted [T1610, T1612], node instance role reuse, IAM escalation paths that mint credentials instead of stealing them (`iam:CreateAccessKey`) [T1098.001], `PassRole` plus function creation, IMDSv2 token enforcement as the actual control [T1078.004, T1580, T1021.007].
6. The data tier as the prize — Postgres server-side file and program access roles, `COPY ... TO PROGRAM` as an in-database exfil primitive, `dblink`/`postgres_fdw` as second-order SSRF, `SECURITY DEFINER` with a mutable `search_path` as a privilege path, RLS that the table owner sails through, the default superuser in a container image; Kafka with a plaintext listener and no ACLs as an open fire hydrant, `--from-beginning` as bulk collection [T1005, T1119], unauthenticated schema registry, a stray consumer group as a silent second reader of every event; the Spring heap dump as a secret vault.
7. Exfiltration channels and their economics — why 1.1 GB of `pg_dump` does not go over DNS and 40 MB of the three juiciest tables does; DNS tunnelling inside label and record-size limits, HTTPS to an attacker domain under a legitimate-looking path and user agent, presigned-URL upload to cloud storage [T1567.002], cloud backup transfer [T1537], the code-hosting API with a stolen publish token, protocol tunneling with chisel or ligolo-ng [T1572], C2 and egress over the SSE/WebSocket channel the app already trusts, chunking, jitter and size limits as the detection surface [T1041, T1048.002, T1048.003, T1071.004, T1573, T1090.003, T1105].
8. Impact, containment, and what the blue team reads — data encrypted for impact [T1486] landing on the volume nobody backs up separately from the instance, inhibition of recovery [T1490], deliberate destruction [T1485], service stop before the encrypt [T1489]; how the account was actually obtained and how long it sat; containment tiers per 09; the log line, metric and artifact that would have shortened each stage; one regression control per move.
9. Offense against the model tier — prompt injection as an exfiltration primitive rather than a curiosity: zero-click retrieval-augmented injection leaking a session's context through an image fetch (CVE-2025-32711, published 2025-06-11), tool poisoning in an MCP description, the lethal trifecta realized as a working chain (private data plus untrusted content plus egress), agent-tool-token theft, and the fixture-driven red-team pass a team can actually run (garak or promptfoo named, not tutorialized) [T1059, T1566.001 as the analogue for the untrusted-content vector].

Shape per block: `Attack surface:` → `Move:` (the real payload, request or command, in the attacker's register) → `Why it works:` (mechanism, one paragraph) → `Attacker outcome:` (what is taken or broken, quantified where a real estate would quantify it) → `Evidence it leaves:` (log line, metric, artifact, or timing) → `Control:` (with the file that owns the fix) → `Detection or regression:`. ATT&CK IDs appear inline as `[T1041]`-style stamps; CVE IDs always with their publish date. Blocks are reference/trace hybrids, code-forward by shape.

Payload-fidelity rule (binding for this file): every block carries at least one standalone payload line — a command, request line, statement, header set, or JSON literal — on its own line under `Move:`, so the string the attacker sends is quotable and never only described. This file has no code-forward block target and the reason is measurement, not preference: under the audit's line-shape heuristic it scores 0%, exactly as 06 (0%) and 08 (4%) do, because seven named fields are prose-shaped lines even when a working exploit sits inside one. 14 documents the same artifact from the other direction. The fidelity metric for 31 is therefore payload-line coverage (47/47 at the 2026-10-07 expansion, scriptable as gate 9) plus the field-shape lint, not the ratio.

Fixture discipline for this file: attacker infrastructure is reserved-name only (`cdn-update.attacker-ops.example`, `203.0.113.66`), victims are `.test`/`.example` hosts on RFC 1918 space, the metadata address is 169.254.169.254, and every secret-shaped string keeps the documented fake pattern. Realistic means correctly shaped, never real data.

Budget: 47 blocks (41 at first write, +6 in the 2026-10-07 proportional pass: cache poisoning/deception, GraphQL introspection and alias amplification, reset-flow host-header poisoning, `pg_stat_statements` as a loot surface, the mutated-version npm class, and the authenticated developer shell), share 3.0%, funded by 06 4.5→3.5, 07 5.5→5.0, 08 4.5→3.5, 09 3.5→3.0. Measured pre-check: 75.5 KB → est ~13.7k tokens, ~291 tokens/block. That sits above the 60–250 reference band and the exception is declared here on purpose: an attack chain is a worked trace, which the bundle-arithmetic clause measures as a trace (80–180 and up), not as a QA block; compressing a chain to fit a QA band is how the residue and the control get dropped first. The budget lint has this line as the basis for the exception, and the tuning loop can retune the share instead of the prose. `eval/heldout-offensive.txt` (never bundled) is this file's measurement slice.

Boundaries: mechanism theory is 06; probe construction and pass bars are 08; secrets and hygiene habits are 09; identity protocol semantics are 07; the correct configuration is the stack file that owns it (each exploitation block points at it); failure transcripts are 02; containment tiers are 09; breach notification duties are 25. Tool flag references, advisory prose, and product comparisons do not belong here.

---

## Scope: 28-invariant-exploitation.txt

Purpose: the invariant half of 19 — ADRs whose subject is a business or identity invariant that an attacker can *offer* to satisfy, and the design choice that makes the invariant non-negotiable. Where 19 chooses between architectures, 28 chooses where a rule is enforced so that a client cannot satisfy it by asking.

Shape per block: the 19 ADR shape, verbatim — `Decision context:` → `Options:` → `Recommendation with conditions:` → `Reversibility note:` → `Verification:`. Adversarial-hygiene band, weighted 1.0, prose-first by design and therefore without a code-forward target.

Repair pass (2026-10-07, binding): the two leading `#` lines come out (the global convention forbids headings in `.txt`; this file and 27 were the only bundle-scope violators), the mangled `protocolwherever` is split, and two blocks join the file so its coverage is not one-invariant-wide: the price the client sends versus the price that is charged (quote signing, conflict rather than silent re-price), and money's representation across Postgres, Kafka, the PSP and one float-bearing reporting extract. Nothing was dropped or compressed; the four original decisions keep their wording.

Budget: 6 blocks, 6.1 KB → est ~1.1k tokens, share 1.0. The file was 4 blocks / est ~0.4k before the pass, which is why its weighted share moved 0.07% → 0.17%; the move is a property of a small denominator, not a rebalance, and it stays inside the band's 3%.

Boundaries: the probe that finds the violation is 08, the mechanism is 06, the exploitation is 31, the checkout state machine is 26, the architectural framing is 19.

---

## Status
Reasoning pass (2026-10-07), measured before and after by `scripts/reasoning_report.py`, which is now the instrument for this claim. Before, at `6098af6`: of 1410 blocks, 548 carried at least one reasoning mark (a killed hypothesis, competing hypotheses held against each other, a test chosen for its differing predictions, a named dead end, a sanity check, stated uncertainty, a question that had to go to a person) but only **4 carried three or more**, and 21 blocks exceeded 2000 characters. The corpus therefore showed the *result* of reasoning in 39% of blocks and the *process* in 0.3%, which is the shape that survives badly: the vocabulary is there, the trace is not, and a model at 4 bits keeps the fluent conclusion and drops the search.

What was added — 39 blocks, weights untouched, existing blocks kept in shape: 16 in 02 (12 search-register loops where the first hypothesis is wrong and a measurement kills it, 4 long-horizon traces of ten-plus steps with two dead ends and a stop-and-ask beat, all in the file's `Failure/Diagnosis/Fix/Verify` shape); 6 in 03, reasoning under uncertainty rather than derivation-with-the-answer-known; 5 in 05, including the over-reasoning and under-reasoning failures and a 12-step trace that stops to ask; 2 each in 10, 12, 13, 16, 17 and 21 as diagnosis ladders in each file's own field shape, which is where the reasoning vocabulary was missing. New `eval/heldout-reasoning.txt` (8 prose-shaped blocks, never bundled) gives the reasoning slice something to score against, and the tuning loop now says what would make this pass a failure: reasoning KL improving while SE perplexity worsens means the volume came out of the stack band, and that is a weight decision, not a writing one.

After, same instrument: 590 of 1449 blocks with any mark, **24 deep (1.7%)**, 25 blocks over 2000 characters. Totals 1449 blocks on disk (1444 in the 28 weighted files), ~202.5k est unweighted tokens, ~813.6k as `sum(tokens x weight)`, from 1410/191k/758k before the pass. Volume shares moved thinking 22.9->23.9, core stack 45.5->48.4, stack total 70.7->70.6, security 25.2->22.2 — security's fall is dilution, not deletion; its weight share is unchanged at 17.5% and its volume share is still the most over-indexed band in the bundle. The honest limit of the pass, also from the report: 19 of the 24 deep blocks sit in the thinking band, so the goal of getting search-shaped reasoning to co-occur with stack vocabulary is only half met — the twelve stack-file ladders raised those files' any-mark coverage but mostly stopped short of the three-mark bar, which is a fair reading of a *reference* block and the reason the rule above does not demand transcripts in 10-21. Whether to push further is the eval's question, not the writing's. `lint_budget` prints the band arithmetic and warns where a band's influence and its declared intent disagree by more than 3 points, which after this pass is true of thinking (+3.0), security (+4.7) and stack total (+3.6). Whether that is the right trade is exactly the question the eval answers; the writing is not the place to settle it.

Bookkeeping done in the same pass, because it had become load-bearing: `lint_budget` gained the band table (declared sum, actual weight sum, weight share, realized volume share), which is what turned "the numbers do not add up" into a specific finding — every per-file weight matches the number written beside it, and only two printed sums were stale (`Core stack 10-21: 48` for weights that add to 51.0, and the stack total at 66 for 69.0). The Arithmetic note section now states that, and the two gaps are declared in the gate's `KNOWN_BAND_GAPS` so they warn by name instead of failing, until the human decides whether to restate the labels or rescale the weights. `scripts/recompute_gate.py` grew six entries for 03's new numbers (DNS exfil bytes and KiB per hour, the 71.8% flake probability, the 256932-series count, the 365ms serialization sum, the 222-hour dump), and 02 and 05 are declared long-block exceptions in `lint_budget` for their traces. Gates after the pass: `lint_format` 0 failures, `lint_budget` 0 failures and 7 warnings, `recompute_gate` ok, code-forward audit re-run.

Realism texture pass (2026-10-07, in place, no block added or removed): 1330 blocks before and after, +22.7 KB (+2.5%). Every weighted file except 01, 03, 04, 28, 29 and 30 gained quoted artifacts inside its own fields (25 files, 165 added lines, one replaced line in `31`; nothing removed) — `31` prints the log line, the IMDS credential body, the `ps` and `kubectl -o jsonpath` output, the `InvalidClassException: filter status: REJECTED`, the heap-dump session and the agent exfil query string; `08` prints the request that fails and the problem-details body that should; `09` prints `ps`, `history`, the JIT audit row and the span attribute that leaked; `12` prints the plan with `Heap Fetches: 21433`, the temporal exclusion-constraint error and the per-table autovacuum fix; `20` prints the exemplar exposition line, the burn-rate rule, the collector config and the Boot/OTel properties; `21` prints the throttling counter, the `Unhealthy` event and the `helm --atomic` outcome; `10` prints `jdk.VirtualThreadPinned` and the preview-mode compiler notes; `11` prints the property-binding failure, the SSE buffering symptom, the retry metric and the assertion output; `13` prints the LeaveGroup line, the share-group describe table, the authorization exception and the KRaft authorizer config; `15`/`24` print the `tsc` errors, `16`/`17`/`18`/`22` print the Vue warning, the assertion failure, the mutation score and the `uv` error; `25`/`26`/`23`/`27`/`19`/`07`/`14` print the export manifest, the order state line, the context-budget config, the CI token leak, the failing fitness function, the `invalid_grant` reuse signal and the operation headers. Currency held to the pinned ledger throughout — Boot 4.1 structured logging and property names, JDK 25 preview notes and JFR event names, PG 18 plan and constraint wording, Kafka 4.3 KRaft authorizer and share-group tool, Gateway API-era `kubectl`, OTel collector config; where a name could not be verified this session it is hedged in prose rather than asserted (`kafka-share-groups.sh` named as 4.3's share-group describe tool, the retry metric named by its publisher and tagging rather than by exact series). Gates after the pass: `lint_format` 0 failures, `lint_budget` 0 failures, `recompute_gate` ok, code-forward audit green with the documented dips.

Proportional expansion pass (2026-10-07, all 27 weighted bundle-scope files): every weighted file gained examples at unchanged weights, per the Expansion rule — 01 97→105, 02 65→71, 03 55→60, 04 56→60, 05 43→48, 06 51→56, 07 46→51, 08 48→53, 09 32→36, 10 61→69, 11 53→59, 12 54→60, 13 44→49, 14 41→45, 15 37→42, 16 37→42, 17 33→38, 18 35→40, 19 41→46, 20 26→30, 21 35→40, 22 25→29, 23 25→28, 24 30→33, 25 25→28, 26 40→44, 28 4→6 (scope section above), 31 41→47. Bundle totals: 1330 blocks, ≈173k est tokens (from 1197 / ≈116k), Σ(tokens × weight) ≈680k. Weighted band shares moved core stack 43.4→45.1, security 24.4→25.1, thinking 26.1→23.4, applied 5.2→5.6, so the security and stack bands hold and the thinking band gave up 2.7 points because its blocks stayed short; that drift is recorded rather than corrected by editing weights, and the tuning loop is where it gets paid back. One file moved more than 25% relative (28, 0.07→0.17, small denominator). The per-file `Budget:` lines keep the wording of the pass that measured them; `manifest.json` holds the post-pass actuals. Gates re-run after the pass: `recompute_gate.py` ok, `audit_code_forward.py` re-run (targets unchanged; `31` has no code-forward target by the rule in its scope section), fixture and delimiter lint clean, no `#` headings left in bundle scope (`29`/`30` are inventory-only at share 0 and still carry their two leading shape lines; the `#` lines inside `22` are Python comments in code, which the convention permits). One authoring artifact was found and fixed while auditing the new content: `31`'s SSRF block had inherited the three JWT header payloads from the adjacent algorithm-confusion block, so the payload lines under `Move:` now belong to the move that uses them. `AUDIT.md` regenerated with the pass. New content is current to the 2026-10-03 ledger: Boot 4.1 resilience annotations and Modulith, `RestTestClient`, JSpecify `@NullMarked`, WebFlux SSE, JSONB `jsonb_path_exists` with GIN and expression indexes, expand/contract with `NOT VALID`, index-only-scan visibility-map degradation, `FOR UPDATE SKIP LOCKED`, `WITH PERIOD` (version-gated), Kafka graceful leave, `TopicRecordNameStrategy` with `BACKWARD_TRANSITIVE`, OAUTHBEARER assertion signing, share-group `RENEW`, KIP-853 dynamic controllers, per-service principals, RFC 9421, `Last-Event-ID`, `Deprecation`/`Sunset`/`Link`, CRLF and `Forwarded` hygiene, `expect-type` and variance annotations, template-literal `const` inference, effect-scope ownership, `shallowRef`/`markRaw`, RFC 9457 and correlation contracts, SLO-gated load and mutation-scored generated suites, `pg_stat_statements` loot surface, mutated-version supply chain, and the CPython free-threaded status stated as status, not as a speed claim.

All 26 original bundle-scope files are scoped and implemented. `31-offensive-security` joins bundle scope in the 2026-10 offensive pass at share 3.0 (scope section above), funded inside the security band; the global Realism rule replaces the old "defensive only" bans in 06 and 08. 27/28 adversarial-hygiene categories are weighted in the share table, and 27 carries a repair pass in the same 2026-10 pass (scope section above). SPEC holds per-file scope and actuals; counts of both sizes are in manifest.json. `29`/`30` are fenced-v0 (share 0) and counted only in the file inventory.

Code-density pass (2026-10-08, batch 1 of the gap fill, weights untouched): +8 blocks, one per file in each file's native shape — 10 77→78 (complete refund-decision module: records, sealed permits, exhaustive switch), 11 65→66 (ownership-checked @Transactional service with idempotency), 12 68→69 (hardened SECURITY DEFINER approve function with search_path pin), 15 54→55 (RFC 9457 problem parser plus retry predicate), 16 56→57 (full SFC: script setup plus template plus scoped style with abort and tri-state), 17 52→53 (infinite refund list with key factory, signal, select, gcTime), 22 29→30 (indentation-significant keyset stream generator), 18 42→43 (first multi-line test body in the file: readable ownership matrix). Bundle: 1449→1457 blocks, ≈202.6k→206.8k est unweighted, Σ(tokens × weight) ≈813.9k→833.7k. Volume shares moved thinking 23.9→23.3, security 22.2→21.6, core stack 48.4→49.5, supporting 1.5→1.6, stack total 70.6→71.1 — the +1.1pt core-stack move is the intended effect of this batch (code into the estate files) and the next batches (edit mechanics into 02/05/21, algo/comprehension into 03/04-adjacent stack files) rebalance toward thinking/security rather than weights. No file moved more than 25% relative. Gates: `lint_format` 0 failures, `lint_budget` 0 failures, `recompute_gate` ok, code-forward audit green (18 holds 70% with its first code block; 12 dips 90→88% on the SDF prose and stays above target), reasoning deep 24→27 with stack-deep 5→8, diversity self-dup flat.

Edit-mechanics pass (2026-10-08, batch 2 of the gap fill, weights untouched): +6 blocks in native shapes — 02 87→89 (git-apply patch failure with --3way conflict resolution plus the real unified diff; fork-secret plus floating-tag CI failure with pin-lint and secret-audit controls), 05 53→55 (cherry-pick -x backport with the DTO conflict treated as an explicit adapt-vs-port decision; contract-diff gate rejection repaired fix-forward with a red-green proof requirement), 21 42→44 (runnable fork-safe GitHub Actions workflow with hash pins and environment gating; cache-ordered multi-stage Dockerfile with digest-pinned distroless runtime). Bundle: 1457→1463 blocks, ≈206.8k→209.0k est unweighted, Σ(tokens × weight) ≈833.7k→843.5k. The corpus now holds two real unified diffs (01's constructor-injection diff plus 02's ownership-branch diff), operational rebase/cherry-pick/apply coverage in 02/05, and raw workflow-YAML plus Dockerfile shapes in 21. Volume shares moved thinking 23.3→23.9, security 21.6→21.4, core stack 49.5→49.0, supporting 1.6→1.6, stack total 71.1→70.6 — the thinking-band volume/intent warn re-appears at exactly +3.0pts, the same pre-existing dynamic as before batch 1, not a new imbalance. No file moved more than 25% relative. Gates: `lint_format` 0 failures, `lint_budget` 0 failures, `recompute_gate` ok, code-forward audit green, reasoning deep 27→29 (both new deep blocks in thinking 01-05), diversity self-dup flat with no new repeated-phrase spikes.

Comprehension-algo-dialect pass (2026-10-08, batch 3 of the gap fill, weights untouched): +12 blocks in native shapes — 10 78→80 (spot-the-bug status map with red expected-429-was-500; statutory-order matching sweep with stated O(n log n)/O(n)), 12 69→71 (predict-the-plan per tenant shape plus prepared-path branch; PG→MySQL/SQLite cross-dialect matrix with per-construct rewrites), 15 55→56 (five-row predict-the-output table for fetchProblem/isRetryable), 16 57→58 (explain-the-component ownership map with per-owner deletion tests), 22 30→34 (pager edge-case predictions; TS→Python retry-predicate port with shared five-row parity oracle; O(1) token bucket with monotonic clock and eviction bound; linear-time regex validation with timing proof), 21 44→45 (digest-equality shell with jq plus awk, failing closed), 20 30→31 (level taxonomy: 4xx as info-with-outcome, logfmt plus JSON for the same event). Bundle: 1463→1475 blocks, ≈209.0k→214.1k est unweighted, Σ(tokens × weight) ≈843.5k→865.2k. All six review gaps now have in-corpus coverage: dense modules (batch 1), edit mechanics (batch 2), comprehension tasks, algo with complexity in brace-heavy Java plus indentation-significant Python, cross-dialect rewrites, and shell/jq/awk plus CSS-in-SFC plus log-level texture. Volume shares moved thinking 23.9→23.4, security 21.4→20.9 (its volume/intent warn clears to exactly the boundary), core stack 49.0→49.8, supporting 1.6→1.9, stack total 70.6→70.8. No file moved more than 25% relative. Gates: `lint_format` 0 failures, `lint_budget` 0 failures, `recompute_gate` ok, code-forward audit green (22 holds 91% across its four new code blocks), reasoning deep 29→30 with stack-deep 8→9, diversity self-dup flat (12 ticks 0.014→0.016 on shared SQL scaffolding, no spike).
