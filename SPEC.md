# Corpus spec

Agreed scope per calibration file. Implementation must match this file; change the spec first, then the source.

## Global conventions

- Format: UTF-8, LF, plain blocks separated by blank-line `---` blank-line. No frontmatter, no `#` headings, no code fences in `.txt`. Code raw.
- Files ordered by criticality (thinking → security → stack → supporting → fenced). Filenames are stable IDs; `manifest.json` bundle order defines the build.
- Baselines, state of the art: Java 25 LTS, Spring Boot 4.1 / Framework 7, TS 7 with 6-compat (configs must pass both compilers until the editor moves to 7.1), Postgres 18, Kafka 4.3 KRaft-only, Vue 3 + TanStack Query v5. Version-sensitive claims verified before writing.
- Modern, elegant idioms where code appears (records, sealed types, pattern matching, constructor injection, composition API, parameterized SQL).
- No secrets, no employer code, no StackOverflow copies, no GPL text. Fake domains (`.test`) only.
- Weighting (default bundle ~200–250k tokens): ~65–70% stack, ~20% thinking (01–05), ~10% finance + anchor. `eval/` never in bundle.
- `21-linux-infra` spans Linux, Docker, Nginx, CI/CD, K8s (full-stack ops).

---

## Scope: 01-instruction-following.txt

Purpose: protect constraint compliance under Q4 — the first thing quantization breaks. Single-turn, strict instructions; no repo work (05), no failure diagnosis (02), no math traces (03).

Content, 6 kinds:

1. Multi-constraint tasks — "do X under constraints A+B+C", all visibly satisfied.
2. Schema compliance — exact JSON/YAML/CSV/header shapes, enums, length and format limits.
3. Tool-call format — function name plus args in exact syntax, no prose leakage.
4. Negative constraints — "don't do X", scope boundaries, refusals with a safe alternative named.
5. Precedence — system over user, explicit conflict resolution, distraction resistance.
6. Adversarial instruction handling — injection in source code, in SQL comments, in README, in commit messages, in tool output, in fetched external content. Each quoted as data, legitimate task completed, injected directive refused.

Shape per block: instruction, then compliant response. About 20% violation→correction pairs labeled exactly `Draft:` / `Correction:`.

Budget: dense. Recorded actual ~5.3k tokens, 85 blocks.

Boundaries: repo exploration is 05; failure diagnosis is 02; derivations are 03; general QA is 04. If a block needs more than one turn to verify, it belongs in 02.

---

## Scope: 02-repair-loops.txt

Purpose: the full failure transcript shape — raw error → diagnosis → fix → verification output. The highest-signal agent calibration: models lose multi-step error recovery before they lose syntax.

Content, 6 kinds, all on current baselines:

1. Compiler errors — `javac` 25 (sealed exhaustiveness, record constructors), `tsc` 7 (strict plus removed flags as hard errors), Volar template checking.
2. Failing tests — Boot slice/integration failures, Testcontainers startup, Query v5 flakes, pytest markers.
3. Database errors — PG 18 deadlocks (40P01), RLS denials (42501), OFFSET→keyset repair with EXPLAIN evidence, Flyway rebase faults, SECURITY DEFINER hazards.
4. Kafka errors — KRaft quorum loss, rebalance eviction, EOS fencing, poison→DLQ, schema incompatibility, SASL/TLS handshake failures, lag-as-capacity-gap.
5. Flaky and concurrency failures — virtual-thread pinning, shared-fixture isolation bugs, wall-clock assertions, optimistic-locking conflicts.
6. Ops failures — Docker layer cache, Nginx 502/TLS/WebSocket/SSE, K8s probes and OOM, CI flakes, CORS, pool exhaustion, WAL volume.

Shape per block: `Failure:` (unedited tool output, secrets redacted) → `Diagnosis:` (root cause, one paragraph) → `Fix:` → `Verify:` (command plus expected output).

PG slow-pagination repairs use keyset on `(tenant_id, created_at, id)` — the failure half of 01's pagination block.

Budget: dense, transcripts are token-heavy by nature. Recorded actual ~4.1k tokens, 49 loops.

Boundaries: single-turn compliance is 01; abstract derivations are 03; multi-file change ownership is 05. If the fix needs architecture discussion, two sentences max — full ADRs live in 19.

---

## Scope: 03-math-logic-cot.txt

Purpose: the derivation shape — stepwise reasoning with the answer earned, not stated. Protects CoT and quantitative judgment: what Q4 hollows out when it preserves tokens but breaks chains.

Content, 6 kinds:

1. Logic — implication family (converse/inverse/contrapositive equivalence), quantifier order (forall-exists vs exists-forall), induction with explicit base and non-circular step.
2. Discrete plus stats core — sets, combinatorics, distributions, Z/t selection by n, p-values, confidence intervals, Bonferroni, regression readouts with the causation caveat.
3. Linear algebra essentials — eigenvectors as pure stretch directions, rank and collinearity, at intuition level for ML-adjacent reasoning.
4. Complexity plus DS&A — Big-O with the constant-factor caveat, keyset O(log n + k) vs OFFSET O(d + k) with the tiebreak requirement, hash vs tree under adversarial input, DP overlap diagnosis, BFS/DFS selection, quorums (R+W>N), Little's law, Bloom one-sided error.
5. CoT traces — `Q:` → numbered `Step` lines (each checkable) → `Answer:`. ASCII/Unicode notation (`μ`, `σ`, `O(n log n)`), no LaTeX. Pseudocode at most 5 lines, only when the algorithm is the point.
6. Self-corrections — wrong path taken, error caught mid-trace, backtrack, fixed answer. One in five blocks, labeled `Correction:`.

Rigor rule (binding): no point estimates as conclusions. n=40 cannot support a p95 (~2 tail observations); paired claims need paired repeats with a CI on the differences — worked reference t = −5.63, df = 11, CI (−90.4, −39.6)ms. p is P(data|H0), never P(effect|data). Fit is not causation; check leakage first. Post-hoc power is circular.

Budget: largest thinking file; traces are long by design. Recorded actual ~5.3k tokens, 48 derivations.

Boundaries: instruction compliance is 01; failure transcripts are 02; general QA is 04; greeks, GEX, and backtests are 23, which consumes this file's stats and never re-teaches them. If a trace needs domain context beyond one sentence, it belongs in the domain file.

---

## Scope: 04-general-reasoning.txt

Purpose: the fluency anchor. Wiki-like prose plus broad QA that keeps general language, factual recall, and everyday reasoning intact while 01–03 and the stack files pull toward code. Overfit insurance, not a knowledge dump.

Content, 6 kinds:

1. Reference prose — history, science, geography, culture in neutral expository paragraphs. Diverse vocabulary, long sentences, discourse flow. The WikiText role.
2. Broad QA — factual recall across domains (units, biology, physics, geography), short one-answer pairs.
3. Reading comprehension — short passage, then 2–3 questions answerable from the passage, including simple local inference but no multi-step derivation. Each inference closed with an explicit "This infers X from stated Y" so it stays auditable.
4. Commonsense reasoning — everyday causal, temporal, spatial, and social reasoning with the mechanism in 2–3 sentences. Distinct from retrieval (not QA) and from derivation (not 03).
5. Compression — summarize a paragraph in one sentence; paraphrase without meaning shift. Tests meaning preservation, the inverse of padding.
6. Everyday estimation — Fermi quantities, unit conversions, calendar and arithmetic sanity, time zones and meeting overlap. Informal number sense; formal stats live in 03.

Shape per block: either a 100–150-word prose paragraph, or Q with a 1–3-sentence answer. No `Step` chains (those are 03), no constraint drills (01), no transcripts (02).

Budget: lightest file by design. Recorded actual ~3k tokens, 51 blocks. Breadth regularizes; volume lives in the stack files.

Boundaries: derivations are 03; stack specifics are their domain files — any mention of Spring, PG, Kafka, or Vue moves the block out; finance is 23; instruction-format drills are 01. If a QA needs more than 3 sentences, split it: length belongs to passages, not answers.

---

## Scope: 05-agentic-coding.txt

Purpose: the multi-step feature shape — explore → plan → implement → verify across files. Where 02 closes one defect, 05 ships one change set. Calibrated on the harness mix (Claude Code, Codex, Pi, OpenCode) with a harness-agnostic core, so tool discipline transfers instead of one tool's syntax.

Content, 8 kinds:

1. Repository exploration — map an unfamiliar system: entry points, dependency direction, relevant symbols and files, trust boundaries, what to read first vs skip.
2. Implementation planning — decompose into ordered changes; affected files, contracts, migrations, dependencies, risks, non-goals, verification points. Declining to estimate without answers is a valid outcome.
3. Multi-step implementation — vertical slices across layers (migration → backend → contract → frontend → tests), preserving cross-layer consistency, verifying after meaningful steps.
4. Refactoring — safe structural changes (extract, rename, codemod, store migration) with behavior-preservation checks; shims point forward (old API over new implementation), never backward.
5. Git workflow — inspect status and diff first; focused commits (fix plus its regression test ships together); never commit secrets or noise; concise what/why/tested PR bodies, rollback stated first on auth changes.
6. Code review — correctness, security, performance, maintainability, compatibility, missing tests; concrete findings with severity and rationale; bot PRs held to the human bar.
7. Tool discipline, harness-portable — read-before-edit, smallest sufficient change, preserve surrounding conventions, verify affected behavior, report what was checked. Generic verbs throughout; ~4 blocks in real harness syntax (primary harness TBD), never enough to overfit one tool.
8. Plan-repair — revert-vs-fix-forward decisions, shim pull-forward, pre-committed rollback criteria (rollback on active failures, never on slow migration). Change-set management, not defect-fixing: raw logs stay in 02.

Shape per block: Goal → context → investigation → plan (≤6 steps) → decisions → verification → outcome. Every block exposes at least one meaningful engineering decision or check.

Realism rule (binding): mix resolved and unresolved outcomes — deferred, blocked, regression-found, needs-clarification, evidence-decided tradeoffs. Shrinking a change set and refusing to build are valid agent moves.

Security quota (binding): at least 1 in 4 blocks carries an explicit security, compatibility, or rollback check (ownership on new routes, migration reversibility, contract versioning, redaction tests).

Boundary test: if the block's hardest sentence is a design tradeoff it belongs in 19; if it is sequencing or verification it belongs here.

Budget: ~30 blocks, dense. Recorded actual ~5.5k tokens, 35 blocks.

Boundaries: single-turn compliance is 01; isolated failure→fix is 02 (05 references 02-style loops as one plan step, never replays them); derivations are 03. If a block needs no repo context, it belongs in 01–04.

---

## Scope: 06-security.txt

Purpose: the vulnerability-class reference — what each flaw is, why it happens, how it is mitigated and prevented from returning. Principle-first with one stack-anchored illustration per category; stack-specific depth lives in the domain files.

Content, 7 kinds:

1. Threat modeling — assets, trust boundaries, STRIDE-per-boundary, abuse cases, attack surfaces, trust assumptions, security invariants stated before mechanisms.
2. OWASP Top 10 web (2025 revision) plus API Security Top 10 (2023 revision) — both explicitly dated and verified current as of 2026-10; refresh numbering via `manifest.json`. Each relevant category: definition, canonical example, root cause, primary mitigation. BOLA/BFLA mechanism lives here; assessment depth lives in 08/14.
3. Injection family — SQLi, command injection, XSS (stored/reflected/DOM), CSRF, SSRF (incl. redirect and DNS-rebinding facets), path traversal, deserialization (Java `readObject` and prototype pollution facets), request smuggling: mechanism → vulnerable pattern → mitigation.
4. Auth-adjacent boundaries — session and cookie flags, CORS as access boundary, JWT validation pitfalls, mass assignment (mechanism home; testing home is 08), confused-deputy issues. Protocol mechanics belong in 07.
5. Cryptographic usage — current baselines named with explicit as-of stamps (TLS 1.2+ floor, argon2id, random 96-bit GCM nonces), never timeless-vague. Broken custom designs (MD5 storage, hand-rolled JWT checks, fixed IVs) shown only as forbidden patterns with standard-primitive replacements. Designing new crypto is out of scope, full stop.
6. Supply chain — lockfiles with frozen enforcement, provenance and signatures, digest pinning, dependency confusion with scoped registries, SBOMs, severity-SLA patching.
7. Detection and response — security logging with redaction by default, alerting on symptoms with runbooks, containment (freeze before eradicate), evidence preservation, recovery, post-incident regression controls (one test, one detection improvement, one hardening change per incident).

Wording rule (binding): never describe OWASP placement as incident-frequency ranking; it reflects blended risk mapping (prevalence, impact, exploitability).

Trust-boundary rule (binding): the three invariants stated as named violations with enforcement — tenant context cannot be supplied by the client (gateway plus RLS), authorization is checked at the resource boundary (service layer, annotations as outer ring), untrusted API responses never become trusted domain objects (verify, strict DTOs, explicit mapping) — with one test per invariant on every build.

Shape per block: Concept (2–3 sentences) → vulnerable pattern → why it fails → remediation (with stack anchor) → regression control.
Defensive only; no weaponized exploit instructions, payloads, or offensive tooling.

Budget: ~40 blocks. Recorded actual ~4.6k tokens, 41 blocks.

Boundaries: identity and authentication protocols are 07; security assessment and testing are 08; hygiene practice is 09; framework, database, message-bus, and frontend implementations are their stack files; failure transcripts are 02.

---

## Scope: 07-auth-oidc-oauth.txt

Purpose: the protocol reference — how OAuth 2.x and OIDC 1.0 work message by message, what each participant must validate, which invariants hold. Security baseline: RFC 9700 (BCP, Jan 2025, verified). OAuth 2.1 cited only as Internet-Draft draft-ietf-oauth-v2-1-16 (Sep 2026, IESG milestone Dec 2026) — never normative; posture stated as "RFC 9700 aligned, 2.1-ready".

Content, 9 kinds:

1. Framework plus metadata (RFC 6749 roles, RFC 8414 discovery) — trust from the configured issuer over TLS, never from request input; metadata is unsigned JSON.
2. Authorization code plus PKCE S256 — MUST for public clients, RECOMMENDED for confidential; code redemption bound to the verifier, state/nonce bound to the client transaction (independent mechanisms).
3. Mix-up and transaction defenses — state, nonce, exact redirect matching, issuer identification on the authorization response (iss parameter/JARM/trusted context pre-redemption; ID-token iss only post-exchange).
4. Grants: client credentials per workload, private_key_jwt (jti replay as recommended deployment policy, not RFC MUST — verified against RFC 7523 text), implicit/ROPC forbidden.
5. Advanced tier, fenced small and marked exotic — PAR (client MUST single-use, server SHOULD one-time; DPoP composition separate and optional), JAR, RAR (semantic authorization equivalence, details passed to the RS; never byte-identity).
6. Sender constraint — DPoP with jti replay as core proof property, mTLS thumbprint comparison (chain per deployment), audience restriction with explicit resource-to-aud mapping and distinct JWT/introspection checkpoints.
7. Lifecycle — rotation with reuse detection (RFC-mandated baseline for public clients; grace-plus-family-revoke is deployment policy), revocation propagation limits with a documented residue window, incident response assuming live tokens until exp.
8. OIDC 1.0 — discovery, full ID-token checklist, access-vs-ID rule, UserInfo as hints, pairwise subs, auth_time/amr/acr step-up, logout as best-effort broadcast.
9. Authorization models — RBAC/ABAC/claims/scopes discipline, tenant isolation by verified claim plus enforcement, IdP brokering behind one internal contract, JWKS rotation with the 24h-zero-rate rule, browser session binding and skew bounds as labeled deployment policies (bounded skew, e.g. 60s — never a universal constant).

Normative-language rule (binding): every requirement resolves to RFC MUST/SHOULD or explicitly labeled deployment policy. Verified accuracies baked in: PKCE requirement levels, iss-parameter timing, PAR asymmetry, RAR equivalence, DPoP jti, mTLS comparison semantics, 7523 jti optionality (checked against RFC text).

Shape per block: Concept (with spec cite and 2026-10 review stamp) → participants/preconditions → message sequence → invariant → validation checklist → canonical failure → remediation → regression test. Exact parameter and claim names kept; no ASCII state diagrams.

Refresh policy: per-block spec/version/date stamps; finalized standards preferred; active drafts labeled, re-verified on publication via manifest reminder.

Budget: ~40 blocks. Recorded actual ~5.3k+ tokens, 39 blocks.

Boundaries: vulnerability classes are 06; assessment technique is 08; hygiene is 09; Spring wiring is 11; stack patterns are their files. No RFC text reproduced — durable rules and failure modes only.

---

## Scope: 08-api-pentest.txt

Purpose: defensive assessment technique — how to systematically test API security properties, recognize failure evidence, and map findings to remediation. Technique-first; OWASP cited only where a technique maps to current risk, never as the organizing principle. Modern boundaries weighted heaviest.

Content, 8 kinds plus the concurrency category:

1. Inventory plus attack surface — routes from OpenAPI/gateway/code/traffic, versions and shadow APIs, per-route auth matrix, webhook and callback surface.
2. Authentication plus session testing — anonymous/invalid/expired baselines with distributional timing equality (never single-pair assertions), throttling under NAT, enumeration oracles, fixation, logout completeness, PKCE/OIDC negatives. Protocol details defer to 07.
3. Object plus tenant authorization — horizontal/vertical sweeps, ownership matrices across five principals, tenant-boundary battery (omit/empty/foreign/array), UUIDs treated as identifiers only.
4. Function plus property authorization — role/action matrices, method handling per route (preflight OPTIONS tested as negotiation surface, not a verb), privileged-route discovery via client artifacts, mass-assignment sweeps, response-field diffing.
5. Token, protocol, and browser boundaries — nine-fixture JWT battery plus JOSE edge battery (key-type confusion, x5c smuggling, duplicate params, cty ambiguity, federated kid), PKCE downgrade/replay, audience-confusion matrix, CORS origin battery, CSRF with token-or-non-ambient plus SameSite as defense-in-depth, cookie behavior, DPoP/mTLS proof-less replay (severity per deployment policy), webhook five-case battery (mechanism per integration: signature, mTLS, or IP controls).
6. Server-side fetch plus integration — six-case SSRF battery with resolve → canonicalize → validate → connect-without-rebinding, third-party consumption review (timeouts, hostile fixtures, secret hygiene).
7. Abuse plus robustness — rate/quote/cap probing, replay across codes/proofs/tokens/deliveries, business-flow abuse loops, malformed inputs with parser differentials, contract fuzzing with crash-to-test triage, timeout/cancellation behavior. Pass bars de-absoluted (no unexpected 5xx rather than no 500s).
8. Findings to remediation to regression — safe repro, minimal evidence, named boundary/asset/principal, versioned severity rubric (referenced by version, never a universal formula), remediation mapping, regression control per finding.
9. Authorization under concurrency and state transition — approve→revoke races, delete→read races, downgrade mid-request, payload-changed idempotency reuse, cap races under load. Pass bar: correct state evaluated at commit time. The state-of-the-art category distinguishing this file from static checklists.

Shape per block: Target → preconditions → probes in order → pass bar → failing evidence → impact → remediation pointer → regression test. Deterministic fixtures and matrices; bounded non-destructive probes; no exploit payloads or offensive tooling.

Budget: ~40 blocks. Recorded actual ~5.3k tokens, 40 blocks.

Boundaries: mechanisms are 06 (referenced, never re-taught); protocol semantics are 07; hygiene is 09; Spring/PG/Vue test implementations are their stack files; single-defect transcripts are 02. If the core question is "how do I determine whether X is vulnerable?", it belongs here.

---

## Scope: 09-opsec.txt

Purpose: the operational hygiene discipline — how secrets, credentials, logs, repositories, CI/CD, workstations, and production access stay clean in daily engineering. Practice, not vulnerability theory: 06 explains why a failure matters; 09 defines habits and controls that prevent it.

Content, 7 kinds:

1. Secret lifecycle — generate, store, inject, rotate, revoke, scope, expire; manager vs environment vs file with explicit rules. Short-lived workload-bound credentials preferred; OIDC workload identity in CI, static keys only with justification and expiry. Never pass secrets as process arguments.
2. Data minimization plus redaction — logs, traces, metrics, dumps, errors, URLs, headers, history, screenshots, bundles; redact by default with tests proving sensitive patterns never cross telemetry boundaries.
3. Git plus repository hygiene — layered hooks and CI scanners plus scheduled history scans, `.gitignore` coverage, history remediation as remove-plus-rotate-plus-assess, signed commits, protected branches, canary tokens.
4. CI/CD plus supply-chain hygiene — forked PRs as untrusted without secrets, least-privilege ephemeral runners, protected environments gating prod, cache and artifact poisoning controls, provenance where deployed.
5. Workstation plus debugging discipline — shell/history hygiene, temp-file lifecycle, editor/swap/dump controls, clipboard and local-cache suspicion, production-data minimization with sanitized fixtures.
6. Production-access hygiene — least privilege, just-in-time elevation with approver and expiry, audited recorded sessions, separate human/service identities, controlled prod shells. Own category, distinct from keeping secrets out of Git and CI.
7. Exposure plus containment, tiered by blast radius (binding) — tier one (production/customer-bearing): assume compromise with full revoke-scope-evidence-review path; tier two (dev/test-only, proven isolation): rotate, verify, log, move on. Tiering keeps response proportional so the rule stays followed.

Wording rules (binding): history controls are detection, never prevention — the rule is never placing secrets in commands; environment variables are a transport with documented leak paths, not a store; signing proves authorship while branch protection authorizes merges; canaries are non-sensitive by design; clipboard and cache posture assessed per environment; rotation covers credentials, with non-derivable artifacts assessed and contained instead. Production data follows classification plus approved path plus automatic expiry and audit. Eighth habit: hunt secrets across aggregating systems (APM attributes, traces, CI artifacts, image layers, manifests, caches, bundles) with scheduled scans routed by tier.

Shape per block: Rule (one sentence) → realistic redacted violation → correct practice → automated or detective control → recovery action where relevant.

Budget: ~25–30 compact blocks. Recorded actual ~2.4k tokens, 26 blocks. Memorable rules and concrete workflows over explanation.

Boundaries: vulnerability mechanisms are 06; protocol credential handling is 07; assessment technique is 08; Spring/Kafka secret wiring instances are their stack files. No protocol mechanics or vulnerability theory repeated here.

---

## Scope: 10-java.txt

Purpose: the Java 25 language, core libraries, concurrency, JVM, and performance reference — modern Java first, legacy shown only for migration or compatibility. Primary stack file: Java knowledge underpins Spring, Kafka, testing, and backend architecture. Every snippet targets JDK 25 unless explicitly version-gated.

Content, 9 kinds:

1. Modern language plus type modeling — records with compact constructors, sealed hierarchies, pattern matching (instanceof, switch, record patterns, when-guards, explicit null cases), enums with behavior, annotations (retention/target discipline), explicit null handling.
2. Generics plus collections — PECS, inference, bounded wildcards, immutable factories, SequencedCollection/Set/Map with reversed views (JDK 21+, natural 25 vocabulary), equality/hashCode contract, toList-unmodifiable vs toCollection(ArrayList::new) for guaranteed mutability (Collectors.toList guarantees neither), Optional as return-type convention (fields/params discouraged by convention with reasons, never framed as language rules).
3. Streams plus functional style — laziness and short-circuiting, downstream collectors, parallel-stream costs with associativity requirements, method refs, effectively-final capture, plain loops where imperative logic reads clearer.
4. Core APIs plus errors — checked/unchecked policy, chaining, try-with-resources (suppression semantics), NIO.2 with explicit charsets, java.time with DST-gap tests, JPMS modules (exports/opens, jdeps gate), serialization boundaries with explicit formats.
5. Concurrency plus memory model — executor selection (newVirtualThreadPerTaskExecutor named for I/O fan-out), CompletableFuture failure-preserving composition, synchronized/Lock/StampedLock tradeoffs, atomics and concurrent collections, volatile/happens-before, safe publication, interruption protocol.
6. Virtual threads plus structured concurrency — thread-per-task model, pinning (synchronized/native) with JFR evidence, ScopedValue final in 25 as ThreadLocal replacement, StructuredTaskScope as JDK 25 preview (JEP 505 fifth preview: open() factories plus Joiner policies — allSuccessfulOrThrow/awaitAll/anySuccessfulResultOrThrow — compile and run notes), migration from reactive complexity where backpressure allows.
7. JVM plus runtime — class loading laziness, JIT tiers and escape analysis at intuition level, G1/ZGC selection as workload-dependent heuristic, JFR plus async-profiler pair, heap/thread dumps as point-in-time evidence only.
8. Performance engineering — allocation rate first (heuristic starting example, never a threshold), boxing/strings/collections suspects, contention measured before redesign, batching with explicit overflow policy, quantile-based latency description, JMH methodology (warmup, forks, Blackhole).
9. Modernization plus JDK 25 additions — anonymous-to-lambda, DTO-to-record, reactive-to-virtual, collection idiom upgrades, serialization removal, dead-API replacement with jdeps gate; plus the 25-finalized block (JEP 511 module imports, JEP 512 compact sources with instance main and java.lang IO with its non-implicit statics trap) and the preview-neighbors block (JEP 507, JEP 502 labeled preview, never final).

Epistemic-labeling rule (binding): every claim states its status — language guarantee, API guarantee, explicit non-guarantee, convention, heuristic, or implementation behavior. Performance claims never present heuristics as guarantees.

Preview rule (binding): preview APIs carry JEP number, preview status, and flag notes; constructor-form structured code from earlier previews repaired to factory form. Open dispute recorded: ScopedValue orElse(null) — file states it throws per JEP 506, JDK-8355023, and the JDK 25 javadoc null clause; a review claimed null is allowed and was rebutted with sources pending a counterexample.

Shape per block: Concept (with status label) → modern JDK 25 example → semantics/invariant → why this form → counter-pattern or migration case → verification (compilation, unit test, JFR/JMH result, or review rule).

Budget: primary file, dense. Recorded actual ~5.7k tokens, 57 blocks (incl. two Lombok blocks: immutables-migrate-to-records with builder/entity/logging exceptions, and legitimate-remaining-Lombok as read-and-maintain).

Boundaries: algorithms and complexity analysis are 03; Spring usage is 11; Kafka usage is 13; failure transcripts are 02. Examples self-contained; Spring, SQL, Kafka, or Vue appear only as tiny cross-references.

---

## Files pending scope

11-spring, 12-postgresql, 13-kafka, 14-http-api, 15-typescript, 16-vue, 17-tanstack, 18-testing, 19-architecture, 20-observability, 21-linux-infra, 22-python, 23-finance-quant, 24-react. Scope one at a time before implementation.
