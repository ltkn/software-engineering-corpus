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
- Version-verification rule: version-sensitive claims checked against current releases before writing; preview APIs carry JEP/RFC number, preview status, and flag notes; open disputes recorded with sources rather than silently resolved.
- Time-hygiene rule: avoid facts that rot (current office-holders, live version numbers outside pinned baselines, "recently announced"); prefer stable knowledge, and date-stamp the rest.

---

## Scope: 01-instruction-following.txt

Purpose: protect constraint compliance under Q4 — the first thing quantization breaks. Single-turn, strict instructions; no repo work (05), no failure diagnosis (02), no math traces (03).

Content, 7 kinds:

1. Multi-constraint tasks — "do X under constraints A+B+C", all visibly satisfied.
2. Schema compliance — exact JSON/YAML/CSV/header shapes, enums, length and format limits.
3. Tool-call format — function name plus args in exact syntax, no prose leakage.
4. Negative constraints — "don't do X", scope boundaries, refusals with a safe alternative named.
5. Precedence — system over user, explicit conflict resolution, distraction resistance.
6. Long-context adherence — constraints stated early and tested late in the same brief (buried requirements, needle-in-spec); the response must satisfy constraints pages apart, not just adjacent ones.
7. Adversarial instruction handling — injection in source code, in SQL comments, in README, in commit messages, in tool output, in fetched external content. Each quoted as data, legitimate task completed, injected directive refused.

Shape per block: instruction, then compliant response. About 20% violation→correction pairs labeled exactly `Draft:` / `Correction:`.

Budget: dense. Recorded actual ~5.8k tokens, 88 blocks (incl. three long-context adherence briefs).

Boundaries: repo exploration is 05; failure diagnosis is 02; derivations are 03; general QA is 04. If a block needs more than one turn to verify, it belongs in 02.

---

## Scope: 02-repair-loops.txt

Purpose: the full failure transcript shape — raw error → diagnosis → fix → verification output. The highest-signal agent calibration: models lose multi-step error recovery before they lose syntax.

Content, 7 kinds, all on current baselines:

1. Compiler errors — `javac` 25 (sealed exhaustiveness, record constructors), `tsc` 7 (strict plus removed flags as hard errors), Volar template checking.
2. Failing tests — Boot slice/integration failures, Testcontainers startup, Query v5 flakes, pytest markers.
3. Database errors — PG 18 deadlocks (40P01), RLS denials (42501), OFFSET→keyset repair with EXPLAIN evidence, Flyway rebase faults, SECURITY DEFINER hazards.
4. Kafka errors — KRaft quorum loss, rebalance eviction, EOS fencing, poison→DLQ, schema incompatibility, SASL/TLS handshake failures, lag-as-capacity-gap.
5. Flaky and concurrency failures — virtual-thread pinning, shared-fixture isolation bugs, wall-clock assertions, optimistic-locking conflicts.
6. Ops failures — Docker layer cache, Nginx 502/TLS/WebSocket/SSE, K8s probes and OOM, CI flakes, CORS, pool exhaustion, WAL volume.
7. Silent regressions — latency or throughput decay with no error anywhere: flame-graph/JFR bisection between known-good and current, config and data-volume diffing, single-variable reverts to identify the change.

Shape per block: `Failure:` (unedited tool output, secrets redacted) → `Diagnosis:` (root cause, one paragraph) → `Fix:` → `Verify:` (command plus expected output). Regression-bisection blocks substitute before/after profiles for the failure transcript.

PG slow-pagination repairs use keyset on `(tenant_id, created_at, id)` — the failure half of 01's pagination block.

Budget: dense, transcripts are token-heavy by nature. Recorded actual ~4.5k tokens, 52 loops (incl. three silent-regression bisections).

Boundaries: single-turn compliance is 01; abstract derivations are 03; multi-file change ownership is 05. If the fix needs architecture discussion, two sentences max — full ADRs live in 19.

---

## Scope: 03-math-logic-cot.txt

Purpose: the derivation shape — stepwise reasoning with the answer earned, not stated. Protects CoT and quantitative judgment: what Q4 hollows out when it preserves tokens but breaks chains.

Content, 7 kinds:

1. Logic — implication family (converse/inverse/contrapositive equivalence), quantifier order (forall-exists vs exists-forall), induction with explicit base and non-circular step.
2. Discrete plus stats core — sets, combinatorics, distributions, Z/t selection by n, p-values, confidence intervals, Bonferroni, regression readouts with the causation caveat.
3. Linear algebra essentials — eigenvectors as pure stretch directions, rank and collinearity, at intuition level for ML-adjacent reasoning.
4. Complexity plus DS&A — Big-O with the constant-factor caveat, keyset O(log n + k) vs OFFSET O(d + k) with the tiebreak requirement, hash vs tree under adversarial input, DP overlap diagnosis, BFS/DFS selection, quorums (R+W>N), Little's law, Bloom one-sided error.
5. CoT traces — `Q:` → numbered `Step` lines (each checkable) → `Answer:`. ASCII/Unicode notation (`μ`, `σ`, `O(n log n)`), no LaTeX. Pseudocode at most 5 lines, only when the algorithm is the point.
6. Information-theoretic intuition — entropy as expected surprise, compression limits, KL divergence as extra-cost-of-wrong-model at intuition level with one quantization-relevant example (fewer bits where the distribution is peaky). Math kept honest, depth capped.
7. Self-corrections — wrong path taken, error caught mid-trace, backtrack, fixed answer. One in five blocks, labeled `Correction:`.

Rigor rule (binding): no point estimates as conclusions. n=40 cannot support a p95 (~2 tail observations); paired claims need paired repeats with a CI on the differences — worked reference t = −5.63, df = 11, CI (−90.4, −39.6)ms. p is P(data|H0), never P(effect|data). Fit is not causation; check leakage first. Post-hoc power is circular.

Budget: largest thinking file; traces are long by design. Recorded actual ~5.7k tokens, 51 derivations (incl. information-theoretic intuition with the quantization example).

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

Shape per block: either a 50–200-word prose paragraph, or Q with a 1–3-sentence answer. No `Step` chains (those are 03), no constraint drills (01), no transcripts (02).

Budget: lightest file by design. Recorded actual ~3k tokens, 51 blocks. Breadth regularizes; volume lives in the stack files.

Boundaries: derivations are 03; stack specifics are their domain files — any mention of Spring, PG, Kafka, or Vue moves the block out; finance is 23; instruction-format drills are 01. If a QA needs more than 3 sentences, split it: length belongs to passages, not answers. Time-sensitive facts obey the global time-hygiene rule; passage lengths vary (50–200 words) so the file never learns one shape.

---

## Scope: 05-agentic-coding.txt

Purpose: the multi-step feature shape — explore → plan → implement → verify across files. Where 02 closes one defect, 05 ships one change set. Calibrated on the harness mix (Claude Code, Codex, Pi, OpenCode) with a harness-agnostic core, so tool discipline transfers instead of one tool's syntax.

Content, 9 kinds:

1. Repository exploration — map an unfamiliar system: entry points, dependency direction, relevant symbols and files, trust boundaries, what to read first vs skip.
2. Implementation planning — decompose into ordered changes; affected files, contracts, migrations, dependencies, risks, non-goals, verification points. Declining to estimate without answers is a valid outcome.
3. Multi-step implementation — vertical slices across layers (migration → backend → contract → frontend → tests), preserving cross-layer consistency, verifying after meaningful steps.
4. Refactoring — safe structural changes (extract, rename, codemod, store migration) with behavior-preservation checks; shims point forward (old API over new implementation), never backward.
5. Git workflow — inspect status and diff first; focused commits (fix plus its regression test ships together); never commit secrets or noise; concise what/why/tested PR bodies, rollback stated first on auth changes.
6. Code review — correctness, security, performance, maintainability, compatibility, missing tests; concrete findings with severity and rationale; bot PRs held to the human bar.
7. Tool discipline, harness-portable — read-before-edit, smallest sufficient change, preserve surrounding conventions, verify affected behavior, report what was checked. Generic verbs throughout; ~4 blocks in real harness syntax (primary harness TBD), never enough to overfit one tool.
8. Plan-repair — revert-vs-fix-forward decisions, shim pull-forward, requirement changes mid-flight (replan with the new information, never silent scope growth), pre-committed rollback criteria (rollback on active failures, never on slow migration). Change-set management, not defect-fixing: raw logs stay in 02.
9. Session handoff — compact continuation notes for multi-session work (decisions made, state of the change set, next step, open questions), so a fresh context resumes without re-deriving everything.

Shape per block: Goal → context → investigation → plan (≤6 steps) → decisions → verification → outcome. Every block exposes at least one meaningful engineering decision or check.

Realism rule (binding): mix resolved and unresolved outcomes — deferred, blocked, regression-found, needs-clarification, evidence-decided tradeoffs. Shrinking a change set and refusing to build are valid agent moves.

Security quota (binding): at least 1 in 4 blocks carries an explicit security, compatibility, or rollback check (ownership on new routes, migration reversibility, contract versioning, redaction tests).

Boundary test: if the block's hardest sentence is a design tradeoff it belongs in 19; if it is sequencing or verification it belongs here.

Budget: ~30 blocks, dense. Recorded actual ~5.8k tokens, 37 blocks (incl. requirement-change replan and session-handoff note).

Boundaries: single-turn compliance is 01; isolated failure→fix is 02 (05 references 02-style loops as one plan step, never replays them); derivations are 03. If a block needs no repo context, it belongs in 01–04.

---

## Scope: 06-security.txt

Purpose: the vulnerability-class reference — what each flaw is, why it happens, how it is mitigated and prevented from returning. Principle-first with one stack-anchored illustration per category; stack-specific depth lives in the domain files.

Content, 8 kinds:

1. Threat modeling — assets, trust boundaries, STRIDE-per-boundary, abuse cases, attack surfaces, trust assumptions, security invariants stated before mechanisms.
2. OWASP Top 10 web (2025 revision) plus API Security Top 10 (2023 revision) — both explicitly dated and verified current as of 2026-10; refresh numbering via `manifest.json`. Each relevant category: definition, canonical example, root cause, primary mitigation. BOLA/BFLA mechanism lives here; assessment depth lives in 08/14.
3. Injection family — SQLi, command injection, XSS (stored/reflected/DOM), CSRF, SSRF (incl. redirect and DNS-rebinding facets), path traversal, deserialization (Java `readObject` and prototype pollution facets), request smuggling: mechanism → vulnerable pattern → mitigation.
4. Auth-adjacent boundaries — session and cookie flags, CORS as access boundary, JWT validation pitfalls, mass assignment (mechanism home; testing home is 08), confused-deputy issues. Protocol mechanics belong in 07.
5. Cryptographic usage — current baselines named with explicit as-of stamps (TLS 1.2+ floor, argon2id, random 96-bit GCM nonces), never timeless-vague. Broken custom designs (MD5 storage, hand-rolled JWT checks, fixed IVs) shown only as forbidden patterns with standard-primitive replacements. Designing new crypto is out of scope, full stop.
6. Supply chain — lockfiles with frozen enforcement, provenance and signatures, digest pinning, dependency confusion with scoped registries, SBOMs, severity-SLA patching.
7. Detection and response — security logging with redaction by default, alerting on symptoms with runbooks, containment (freeze before eradicate), evidence preservation, recovery, post-incident regression controls (one test, one detection improvement, one hardening change per incident).
8. Agent-system security — coding agents as privileged insiders: tool-grant scoping (read vs write vs execute vs network per task), output trust tiers (agent-proposed vs human-approved vs auto-applied), human-in-the-loop gates for irreversible actions (prod writes, key rotation, mass deletes). Threat-model the harness itself, not just the code it writes.

Wording rule (binding): never describe OWASP placement as incident-frequency ranking; it reflects blended risk mapping (prevalence, impact, exploitability).

Trust-boundary rule (binding): the three invariants stated as named violations with enforcement — tenant context cannot be supplied by the client (gateway plus RLS), authorization is checked at the resource boundary (service layer, annotations as outer ring), untrusted API responses never become trusted domain objects (verify, strict DTOs, explicit mapping) — with one test per invariant on every build.

Shape per block: Concept (2–3 sentences) → vulnerable pattern → why it fails → remediation (with stack anchor) → regression control.
Defensive only; no weaponized exploit instructions, payloads, or offensive tooling.

Budget: ~40 blocks. Recorded actual ~5.1k tokens, 44 blocks (incl. agent-system security: tool-grant scoping, output trust tiers, transcript minimization).

Boundaries: identity and authentication protocols are 07; security assessment and testing are 08; hygiene practice is 09; framework, database, message-bus, and frontend implementations are their stack files; failure transcripts are 02.

---

## Scope: 07-auth-oidc-oauth.txt

Purpose: the protocol reference — how OAuth 2.x and OIDC 1.0 work message by message, what each participant must validate, which invariants hold. Security baseline: RFC 9700 (BCP, Jan 2025, verified). OAuth 2.1 cited only as Internet-Draft draft-ietf-oauth-v2-1-16 (Sep 2026, IESG milestone Dec 2026) — never normative; posture stated as "RFC 9700 aligned, 2.1-ready".

Content, 9 kinds:

1. Framework plus metadata (RFC 6749 roles, RFC 8414 discovery) — trust from the configured issuer over TLS, never from request input; metadata is unsigned JSON.
2. Authorization code plus PKCE S256 — MUST for public clients, RECOMMENDED for confidential; code redemption bound to the verifier, state/nonce bound to the client transaction (independent mechanisms).
3. Mix-up and transaction defenses — state, nonce, exact redirect matching, issuer identification on the authorization response (iss parameter/JARM/trusted context pre-redemption; ID-token iss only post-exchange).
4. Grants: client credentials per workload, token exchange (RFC 8693) for delegation chains with audience narrowing at each hop, private_key_jwt (jti replay as recommended deployment policy, not RFC MUST — verified against RFC 7523 text), implicit/ROPC forbidden.
5. Advanced tier, fenced small and marked exotic — PAR (client MUST single-use, server SHOULD one-time; DPoP composition separate and optional), JAR, RAR (semantic authorization equivalence, details passed to the RS; never byte-identity).
6. Sender constraint — DPoP with jti replay as core proof property, mTLS thumbprint comparison (chain per deployment), audience restriction with explicit resource-to-aud mapping and distinct JWT/introspection checkpoints.
7. Lifecycle — rotation with reuse detection (RFC-mandated baseline for public clients; grace-plus-family-revoke is deployment policy), revocation propagation limits with a documented residue window, incident response assuming live tokens until exp.
8. OIDC 1.0 — discovery, full ID-token checklist, access-vs-ID rule, UserInfo as hints, pairwise subs, auth_time/amr/acr step-up, logout as best-effort broadcast.
9. Authorization models — RBAC/ABAC/claims/scopes discipline, tenant isolation by verified claim plus enforcement, IdP brokering behind one internal contract, JWKS rotation with the 24h-zero-rate rule, browser session binding and skew bounds as labeled deployment policies (bounded skew, e.g. 60s — never a universal constant).

Normative-language rule (binding): every requirement resolves to RFC MUST/SHOULD or explicitly labeled deployment policy. Verified accuracies baked in: PKCE requirement levels, iss-parameter timing, PAR asymmetry, RAR equivalence, DPoP jti, mTLS comparison semantics, 7523 jti optionality (checked against RFC text).

Shape per block: Concept (with spec cite and 2026-10 review stamp) → participants/preconditions → message sequence → invariant → validation checklist → canonical failure → remediation → regression test. Exact parameter and claim names kept; no ASCII state diagrams.

Refresh policy: per-block spec/version/date stamps; finalized standards preferred; active drafts labeled, re-verified on publication via manifest reminder.

Budget: ~40 blocks. Recorded actual ~7.3k tokens, 41 blocks (incl. RFC 8693 exchange and delegation semantics).

Boundaries: vulnerability classes are 06; assessment technique is 08; hygiene is 09; Spring wiring is 11; stack patterns are their files. No RFC text reproduced — durable rules and failure modes only.

---

## Scope: 08-api-pentest.txt

Purpose: defensive assessment technique — how to systematically test API security properties, recognize failure evidence, and map findings to remediation. Technique-first; OWASP cited only where a technique maps to current risk, never as the organizing principle. Modern boundaries weighted heaviest.

Content, 9 kinds:

1. Inventory plus attack surface — routes from OpenAPI/gateway/code/traffic, versions and shadow APIs, per-route auth matrix, webhook and callback surface, GraphQL operations with depth-and-cost analysis and introspection discipline where present (REST-first; gRPC explicitly out of scope).
2. Authentication plus session testing — anonymous/invalid/expired baselines with distributional timing equality (never single-pair assertions), throttling under NAT, enumeration oracles, fixation, logout completeness, PKCE/OIDC negatives. Protocol details defer to 07.
3. Object plus tenant authorization — horizontal/vertical sweeps, ownership matrices across five principals, tenant-boundary battery (omit/empty/foreign/array), UUIDs treated as identifiers only.
4. Function plus property authorization — role/action matrices, method handling per route (preflight OPTIONS tested as negotiation surface, not a verb), privileged-route discovery via client artifacts, mass-assignment sweeps, response-field diffing.
5. Token, protocol, and browser boundaries — nine-fixture JWT battery plus JOSE edge battery (key-type confusion, x5c smuggling, duplicate params, cty ambiguity, federated kid), PKCE downgrade/replay, audience-confusion matrix, CORS origin battery, CSRF with token-or-non-ambient plus SameSite as defense-in-depth, cookie behavior, DPoP/mTLS proof-less replay (severity per deployment policy), webhook five-case battery (mechanism per integration: signature, mTLS, or IP controls).
6. Server-side fetch plus integration — six-case SSRF battery with resolve → canonicalize → validate → connect-without-rebinding, third-party consumption review (timeouts, hostile fixtures, secret hygiene).
7. Abuse plus robustness — rate/quote/cap probing, replay across codes/proofs/tokens/deliveries, business-flow abuse loops, malformed inputs with parser differentials, contract fuzzing with crash-to-test triage, timeout/cancellation behavior. Pass bars de-absoluted (no unexpected 5xx rather than no 500s).
8. Findings to remediation to regression — safe repro, minimal evidence, named boundary/asset/principal, versioned severity rubric (referenced by version, never a universal formula), remediation mapping, regression control per finding.
9. Authorization under concurrency and state transition — approve→revoke races, delete→read races, downgrade mid-request, payload-changed idempotency reuse, cap races under load. Pass bar: correct state evaluated at commit time. The state-of-the-art category distinguishing this file from static checklists.

Shape per block: Target → preconditions → probes in order → pass bar → failing evidence → impact → remediation pointer → regression test. Deterministic fixtures and matrices; bounded non-destructive probes; no exploit payloads or offensive tooling.

Budget: ~40 blocks. Recorded actual ~5.7k tokens, 42 blocks (incl. GraphQL operation analysis and subscription boundaries).

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
6. Production-access hygiene — least privilege, just-in-time elevation with approver and expiry, phishing-resistant MFA for human access, audited recorded sessions, separate human/service identities, controlled prod shells. Own category, distinct from keeping secrets out of Git and CI.
7. Exposure plus containment, tiered by blast radius (binding) — tier one (production/customer-bearing): assume compromise with full revoke-scope-evidence-review path; tier two (dev/test-only, proven isolation): rotate, verify, log, move on. Tiering keeps response proportional so the rule stays followed.

Wording rules (binding): history controls are detection, never prevention — the rule is never placing secrets in commands; environment variables are a transport with documented leak paths, not a store; signing proves authorship while branch protection authorizes merges; canaries are non-sensitive by design; clipboard and cache posture assessed per environment; rotation covers credentials, with non-derivable artifacts assessed and contained instead. Production data follows classification plus approved path plus automatic expiry and audit. Eighth habit: hunt secrets across aggregating systems (APM attributes, traces, CI artifacts, image layers, manifests, caches, bundles) with scheduled scans routed by tier.

Shape per block: Rule (one sentence) → realistic redacted violation → correct practice → automated or detective control → recovery action where relevant.

Budget: ~25–30 compact blocks. Recorded actual ~3k tokens, 29 blocks (incl. phishing-resistant MFA rule).

Boundaries: vulnerability mechanisms are 06; protocol credential handling is 07; assessment technique is 08; Spring/Kafka secret wiring instances are their stack files. No protocol mechanics or vulnerability theory repeated here.

---

## Scope: 10-java.txt

Purpose: the Java 25 language, core libraries, concurrency, JVM, and performance reference — modern Java first, legacy shown only for migration or compatibility. Primary stack file: Java knowledge underpins Spring, Kafka, testing, and backend architecture. Every snippet targets JDK 25 unless explicitly version-gated.

Content, 9 kinds:

1. Modern language plus type modeling — records with compact constructors, sealed hierarchies, pattern matching (instanceof, switch, record patterns, when-guards, explicit null cases), enums with behavior, annotations (retention/target discipline), explicit null handling.
2. Generics plus collections — PECS, inference, bounded wildcards, immutable factories, SequencedCollection/Set/Map with reversed views (JDK 21+, natural 25 vocabulary), equality/hashCode contract, toList-unmodifiable vs toCollection(ArrayList::new) for guaranteed mutability (Collectors.toList guarantees neither), Optional as return-type convention (fields/params discouraged by convention with reasons, never framed as language rules).
3. Streams plus functional style — laziness and short-circuiting, downstream collectors, parallel-stream costs with associativity requirements, method refs, effectively-final capture, plain loops where imperative logic reads clearer.
4. Core APIs plus errors — checked/unchecked policy, chaining, try-with-resources (suppression semantics), NIO.2 with explicit charsets, java.time with DST-gap tests, JPMS modules (exports/opens, split-package and automatic-module migration pitfalls, jdeps gate), serialization boundaries with explicit formats.
5. Concurrency plus memory model — executor selection (newVirtualThreadPerTaskExecutor named for I/O fan-out), CompletableFuture failure-preserving composition, synchronized/Lock/StampedLock tradeoffs, atomics and concurrent collections, volatile/happens-before, safe publication, interruption protocol.
6. Virtual threads plus structured concurrency — thread-per-task model, pinning (synchronized/native) with JFR evidence, ScopedValue final in 25 as ThreadLocal replacement, StructuredTaskScope as JDK 25 preview (JEP 505 fifth preview: open() factories plus Joiner policies — allSuccessfulOrThrow/awaitAll/anySuccessfulResultOrThrow — compile and run notes), migration from reactive complexity where backpressure allows.
7. JVM plus runtime — class loading laziness, JIT tiers and escape analysis at intuition level, G1/ZGC selection as workload-dependent heuristic, JFR plus async-profiler pair, heap/thread dumps as point-in-time evidence only.
8. Performance engineering — allocation rate first (heuristic starting example, never a threshold), boxing/strings/collections suspects, contention measured before redesign, batching with explicit overflow policy, quantile-based latency description, JMH methodology (warmup, forks, Blackhole).
9. Modernization plus JDK 25 additions — anonymous-to-lambda, DTO-to-record, reactive-to-virtual, collection idiom upgrades, serialization removal, dead-API replacement with jdeps gate; plus the 25-finalized block (JEP 511 module imports, JEP 512 compact sources with instance main and java.lang IO with its non-implicit statics trap) and the preview-neighbors block (JEP 507, JEP 502 labeled preview, never final).

Epistemic-labeling rule (binding): every claim states its status — language guarantee, API guarantee, explicit non-guarantee, convention, heuristic, or implementation behavior. Performance claims never present heuristics as guarantees.

Preview rule (binding): preview APIs carry JEP number, preview status, and flag notes; constructor-form structured code from earlier previews repaired to factory form. Open dispute recorded: ScopedValue orElse(null) — file states it throws per JEP 506, JDK-8355023, and the JDK 25 javadoc null clause; a review claimed null is allowed and was rebutted with sources pending a counterexample.

Shape per block: Concept (with status label) → modern JDK 25 example → semantics/invariant → why this form → counter-pattern or migration case → verification (compilation, unit test, JFR/JMH result, or review rule). Build-tool exposure (not a main topic): Maven wrapper with .mvn config and toolchain pins, Gradle wrapper with version catalogs and configuration cache — each as calibration context where builds are invoked, detailed treatment lives in 21.

Budget: primary file, dense. Recorded actual ~5.9k tokens, 59 blocks (incl. two Lombok blocks and two JPMS migration-pitfall blocks).

Boundaries: algorithms and complexity analysis are 03; Spring usage is 11; Kafka usage is 13; failure transcripts are 02. Examples self-contained; Spring, SQL, Kafka, or Vue appear only as tiny cross-references.

---

## Scope: 11-spring.txt

Purpose: the Spring Boot 4.1 / Framework 7 reference — configuration, web, data, security wiring, and production operation the way modern Boot apps are actually built. Framework usage; plain-Java semantics stay in 10.

Content, 8 kinds:

1. Boot 4 foundations — modularized jars, JSpecify null safety, Java 17–26 range with 25 first-class, API versioning support, HTTP service clients (replacing hand-rolled RestTemplates), configuration binding with validated records, virtual-thread request handling per workload (spring.threads.virtual.enabled with eyes open — blocking I/O fan-out yes, backpressure-sensitive streams no; see 10).
2. Core container — constructor injection as default, profiles and conditional beans, AOP (transactional/caching proxies with self-invocation limits), events, Spring Modulith for enforced module boundaries inside the monolith.
3. Web layer — MVC controllers with validated DTOs, WebFlux where backpressure demands it (and not elsewhere), exception-to-ProblemDetail mapping (RFC 9457), validation groups, content negotiation, SSE endpoints.
4. Spring Security — filter chain, method security with @PreAuthorize ownership beans, OAuth2 login plus OIDC, resource-server JWT validation, CORS/CSRF policy, password and session management. Security-spine topics live here with 06-mechanism references, never re-taught.
5. Data — JdbcTemplate batch paths, JPA/Hibernate fetch planning (N+1 prevention), transaction propagation and isolation choices, optimistic locking with @Version, outbox writes inside transactions, Testcontainers-backed repository tests.
6. Batch and scheduling — chunk-oriented steps with flush/clear discipline, partitioning, scheduled jobs with distributed locking, idempotent reruns.
7. Testing — slice tests (@WebMvcTest, @DataJpaTest), MockMvc contract assertions, integration tests with containers, security test slice (ownership, roles).
8. Production — actuator exposure discipline, graceful shutdown, config externalization, observability hooks (Micrometer/OTel), startup-time checks.

Shape per block: Goal → minimal wiring (config plus code) → why this form → common misconfiguration with its symptom → verification (test slice or actuator evidence).

Budget: co-primary stack file with 10. ~50 blocks, dense.

Boundaries: language semantics are 10; protocol rules are 07 (referenced); assessment is 08; failure transcripts are 02. If a block works without Spring on the classpath, it belongs in 10.

---

## Scope: 12-postgresql.txt

Purpose: the PostgreSQL 18 working reference — SQL craft, planner reasoning, concurrency behavior, and operational care. Versioned to 18 with 17-compatible fallbacks noted where they differ.

Content, 7 kinds:

1. SQL craft — joins, CTEs (incl. recursive), window functions, aggregates, set operations, JSONB operators, arrays, full-text search basics.
2. Schema and constraints — normalization judgment, PK/FK discipline, check/exclusion constraints, migrations that stay backward-compatible (expand-contract).
3. Indexing — B-tree, composite and covering indexes, partial and expression indexes, GIN for JSONB/trgm, index-only scans, write-amplification awareness.
4. Planner reasoning — EXPLAIN (ANALYZE, BUFFERS) reading, join strategies, selectivity and statistics, the keyset-vs-OFFSET decision with measured plans.
5. Concurrency and vacuuming — MVCC snapshots, isolation levels with anomalies named, locking and deadlock reading, VACUUM/autovacuum/bloat, HOT updates, advisory locks as the cross-instance mutex (scheduled jobs, backfill guards).
6. Security and roles — roles and GRANT least privilege, RLS policies with forced mode, SECURITY DEFINER plus search_path discipline, parameterized-only access, connection-string hygiene.
7. Operations — partitioning strategy, logical replication, backups with PITR rehearsal, connection pooling (transaction mode caveats), upgrade procedure, key metrics and alerts; pg_stat_statements as the slow-query discovery source; PG 18 wire-protocol 3.2 noted with a driver-compatibility check.

Shape per block: Task → SQL (parameterized, EXPLAIN-attached where performance matters) → planner or behavior reading → pitfall (the wrong-but-common form) → verification (plan output, test, or monitoring assertion).

Budget: ~45 blocks, dense. The keyset-pagination evidence pattern from 01/02 recurs here as first-class technique.

Boundaries: Java/ORM usage is 11; failure transcripts are 02; general transaction theory stays practical and Postgres-flavored (no abstract isolation essays — those resolve to lock/monitoring evidence here).

---

## Scope: 13-kafka.txt

Purpose: the Kafka 4.3 KRaft-only working reference — producing, consuming, exactly-once, schemas, streams, and operation without ZooKeeper-era material. KRaft-only throughout; ZooKeeper content forbidden except as a one-line migration historical.

Content, 7 kinds:

1. Core mechanics — topics, partitions, ordering per key, offsets, consumer groups, rebalancing causes and cooperative-sticky assignor behavior, delivery semantics ladder.
2. Producers — idempotence, batching and compression, retries with backoff, transactional writes, headers for trace and tenant propagation.
3. Consumers — poll-loop discipline, offset commit strategies, cooperative rebalancing, static membership where useful, lag interpretation (error vs capacity gap).
4. Exactly-once and failures — transactions with fencing (unique transactional.id per instance), poison messages to DLQ with cause headers, schema-incompatibility handling, replay runbooks.
5. Schemas and evolution — Avro/Protobuf/JSON Schema, compatibility modes (BACKWARD/FORWARD/FULL) with examples of legal vs breaking changes, subject naming strategies (TopicName vs RecordName chosen per domain), registry auth.
6. Streams, Connect, and Queues — Streams topologies with state stores and standby replicas, rebalance behavior, DLQ support; Connect worker config and secret handling; Queues for Kafka (KIP-932, GA) share-group semantics where they replace consumer groups.
7. Security and operations — TLS, SASL/SCRAM, ACLs with per-principal topics (DLQ ACLs mirror sources), KRaft quorum layout across AZs, controller isolation, rack awareness, tiered storage for retention economics, capacity planning, version-pinned upgrades.

Shape per block: Goal → configuration plus minimal code → why these values → canonical failure with its log signature → verification (lag, drill, or alert evidence).

Budget: ~40 blocks, dense.

Boundaries: Java client mechanics stay minimal here (language in 10); failure transcripts are 02; outbox pattern mechanism is shared with 19 (each file states its own side: relay here, pattern rationale there).

---

## Scope: 14-http-api.txt

Purpose: the HTTP API design reference — semantics, contracts, versioning, and resilience patterns for REST plus SSE/WebSockets/webhooks. Design knowledge; BOLA/BFLA assessment technique lives in 08.

Content, 7 kinds:

1. HTTP semantics — methods, status codes used precisely, headers that matter (ETag with If-Match/If-None-Match for optimistic concurrency, Cache-Control, Retry-After per RFC 9110 as the settled throttle signal, legacy X-RateLimit-* as conventions with documented reset semantics, IETF RateLimit/RateLimit-Policy only as draft-v11 alongside — not an RFC, syntax still moving), content negotiation.
2. REST and OpenAPI — resource modeling, naming, OpenAPI-first vs code-first with generation gates, error contract shape (RFC 9457 problem details), pagination (keyset default with opaque base64 cursors never parsed client-side, OFFSET only with justification), filtering/sorting safely.
3. Reliability patterns — idempotency keys with same-key-different-payload 422s, retries with backoff plus jitter, timeouts per hop, circuit breakers with tuned thresholds, hedging where appropriate.
4. Caching and consistency — ETags and conditional requests, Cache-Control tiers, read-your-write strategies, stale-while-revalidate boundaries.
5. Real-time and events — SSE with buffering discipline, WebSocket upgrade and heartbeat policy, webhook design (signed raw bytes, replay cache, retry schedule), API-to-Kafka handoff points.
6. Versioning and compatibility — additive change discipline, versioning strategy (URI/date/media-type) with sunset policy, breaking-change checklist, client migration windows.
7. API-side security mechanism — BOLA/BFLA design controls, auth-per-route matrix, rate/quote caps, SSRF-safe outbound fetching, unsafe-consumption validation. Mechanism home shared with 06; testing home is 08.

Shape per block: Design decision → contract or config fragment → why (with the failure it prevents) → versioning/compat note → verification (contract test or header assertion).

Budget: ~35 blocks, dense.

Boundaries: protocol auth mechanics are 07; testing technique is 08; Spring wiring is 11; TanStack consumption is 17. If a block's core is "how to test X", it belongs in 08.

---

## Scope: 15-typescript.txt

Purpose: the TypeScript 6-to-7 working reference — migration deltas, strict configuration, and the advanced type system used heavily in TanStack-heavy frontends. Code must pass both tsc6 and tsc7 unless the block documents a 7-only behavior.

Content, 6 kinds:

1. 6→7 migration — Go-native compiler expectations (speed, same semantics), tsc/tsc6 side-by-side, removed flags and new defaults as hard errors (strict, module bundler/esnext, stableTypeOrdering), rootDir/types surprises, editor support gap until the 7.1 API with the sanctioned interim setup.
2. Configuration — tsconfig for SPA vs library, strict family flags individually understood, moduleResolution bundler, path aliases without baseUrl, erasableSyntaxOnly for native-transpiler-safe code (no enums, namespaces, or parameter properties), verbatimModuleSyntax for import discipline, incremental and project references.
3. Type system core — unions/intersections, discriminated unions, narrowing (including custom guards), literal and template-literal types, keyof/typeof, satisfies, utility types used precisely.
4. Advanced types — generics with constraints, defaults, and const type parameters, conditional types with infer, mapped types with key remapping, variance intuition for API design, declaration files and module augmentation for libraries.
5. Runtime boundary — validation at the edge (schemas for API responses, never bare casts), unknown-first handling of third-party JSON, error narrowing, exhaustive-switch helpers for domain unions, explicit resource management with using (Symbol.dispose) for scoped cleanup.
6. Ecosystem — Node 22+ baselines, pnpm workspaces with frozen lockfiles, package exports discipline, test tooling (type-check as a CI gate), performance (isolatedModules-era habits updated for 7).

Shape per block: Goal → snippet compiling under both compilers (or marked 7-only) → why this form → legacy/counter form with its failure → verification (tsc clean both versions, or runtime test).

Budget: ~35 blocks, dense.

Boundaries: Vue and TanStack usage are 16/17 (plain TS here); failure transcripts are 02; Node backend patterns stay minimal (this is a frontend-support file, not a Node server file).

---

## Scope: 16-vue.txt

Purpose: the Vue 3 Composition-API reference — reactivity, components, state, routing, SSR — with the security spine embedded. Framework usage; TypeScript mechanics stay in 15.

Content, 7 kinds:

1. Composition core — script setup, ref/reactive/computed/watch semantics, lifecycle use, provide/inject scoping, props/emits typing (incl. defineModel for two-way bindings), slots and directives, useTemplateRef for template refs, Suspense boundaries for async setup, composable extraction rules.
2. Reactivity pitfalls — ref unwrapping in templates vs code, reactive destructuring loss, watch vs watchEffect selection, effect scope cleanup.
3. State with Pinia — store shape, getters vs computed, actions with async discipline, store testing, persistence boundaries (never secrets).
4. Routing and SSR — Vue Router guards (auth/ownership checks client-side as UX only, enforcement server-side), lazy routes, Nuxt SSR data fetching, hydration matching (dehydrate exact queries), SEO/meta handling.
5. TypeScript integration — typed props/emits, generic components, store typing, template type-checking in CI (vue-tsc), the dual-compiler note shared with 15.
6. Frontend security spine — XSS via interpolation-only rendering, v-html ban with sanitizer-exception process, token storage (memory access plus httpOnly refresh), CSP coordination, CSRF posture, untrusted-URL guards.
7. Testing and architecture — component tests, composable unit tests, E2E on critical flows, feature-folder organization, API-client layer shared with TanStack keys.

Shape per block: Goal → component/composable snippet → reactivity or design reasoning → pitfall with its symptom → verification (type-check, test, or hydration assertion).

Budget: ~35 blocks, dense.

Boundaries: TS mechanics are 15; Query/Router/Table server-state is 17; failure transcripts are 02. If a block works in plain TS without Vue, it belongs in 15.

---

## Scope: 17-tanstack.txt

Purpose: the TanStack reference with Vue Query v5 semantics — server-state architecture done right: keys, caching, mutations, and the router/table siblings. Usage patterns; reactivity internals stay in 16.

Content, 6 kinds:

1. Query foundations — query keys as factories (typed tuples, no undefined drift), query functions with AbortSignal, stale/GC time selection, cache behavior and structural sharing.
2. Mutations and optimism — mutation lifecycle, optimistic updates with rollback context, retry policy per mutation kind, cancellation coordination with in-flight queries.
3. Pagination and infinity — cursor-based infinite queries (pageParam discipline, null termination), placeholder data vs suspense boundaries, prefetching and preloading strategy.
4. SSR and persistence — dehydrate exact first-page queries, hydration matching, persister boundaries (never auth material), focus/reconnect refetch policy.
5. Router and Table — TanStack Router route trees with loaders and guards, search-param typing with schema validation (zod/valibot), Table headless patterns (sorting/filtering/pagination state owned explicitly). TanStack Virtual explicitly out of scope (separate package; windowing noted only where Table needs it).
6. TypeScript-heavy usage — end-to-end typed keys/loaders/mutations, error-type narrowing, contract drift detection (response-shape tests shared with 14).

Shape per block: Goal → key plus hook snippet → caching/behavior reasoning → misconfiguration with its symptom (stale forever, duplicate pages, lost mutations) → verification (test with fake timers/server, render-count or network assertion).

Budget: ~30 blocks, dense.

Boundaries: Vue reactivity is 16; API contract design is 14; failure transcripts are 02. Version-pinned to v5 semantics (vue-query 5.104.x verified 2026-10) with migration notes from v4 where the behavior changed (keepPreviousData → placeholderData). v6 lines exist on neighboring adapters (Svelte 6.x, Solid 6.0 pre-release) while core/react/vue remain v5; when they re-sync at v6 stable this file gets a migration pass, same posture as the TS dual-compiler rule.

---

## Scope: 18-testing.txt

Purpose: the testing strategy reference — levels, techniques, and diagnosis across the stack. Framework-agnostic strategy with Spring/Vue/PG instances; tool syntax stays minimal.

Content, 7 kinds:

1. Levels and seams — unit vs integration vs component vs contract vs E2E, what each owns, the inverted-triangle anti-patterns, seam selection (ports over mocks where behavior matters).
2. Backend testing — slice tests, Testcontainers Postgres/Kafka, repository tests with planner assertions, security tests (ownership matrices, role matrices), concurrency tests.
3. Frontend testing — component tests, composable tests, Query hook tests with fake servers, E2E on critical flows, visual/hydration assertions, snapshot tests gated to stable markup (one behavior per snapshot, updates deliberate, never blind -u).
4. Contract and API testing — OpenAPI conformance, consumer-driven contracts for internal APIs, error-contract assertions, backward-compatibility gates on contract change.
5. Property and mutation testing — property invariants (pagination concatenation equals full query), mutation score as a suite-quality signal, targeted (not blanket) mutation runs.
6. Load, performance, and chaos — k6-style load shapes, SLO-based pass bars, fault injection (slow deps, kills mid-relay), game-day drills with timed runbooks.
7. Diagnosis — red-green triage order (isolation before theory), determinism control first (fake timers, seeded RNGs, fixed ports) before any quarantine, flake quarantine process with expiry, coverage as a map (never a target), failing-suite bisection.

Shape per block: What to test → minimal example → why this level/technique → common anti-pattern with its cost → verification (the test itself, or suite-health metric).

Budget: ~30 blocks, dense.

Boundaries: failure transcripts are 02 (which shows failures; 18 shows the testing that prevents and catches them); observability of production is 20; architecture decision records are 19. Tool-version specifics stay out — techniques, not CLI flags.

---

## Scope: 19-architecture.txt

Purpose: the system-design reference — styles, patterns, tradeoffs, and decision records for the modular-monolith-to-event-driven range this stack lives in. Judgment with reasons; the ADRs home per the 05 boundary test.

Content, 7 kinds:

1. Styles and structure — SOLID applied at module scale, DDD bounded contexts with ubiquitous language, hexagonal ports/adapters, modular monolith with enforced boundaries, microservice extraction criteria (and non-criteria).
2. Events and consistency — event-driven topology, CQRS where read/write asymmetries justify it, sagas with compensations, outbox pattern (pattern rationale here, relay mechanics in 13), idempotency as architectural property.
3. Resilience — retries/backoff/jitter, circuit breakers, bulkheads, timeouts, backpressure with explicit overflow policy, graceful degradation tiers.
4. Data architecture — per-service data ownership, cross-service query strategies (composition vs replication vs request), migration safety (expand-contract), RLS-aware service design.
5. Caching strategy — layers (HTTP, application, read models), invalidation ownership, stampede protection, cache-vs-source-of-truth discipline.
6. Evolution — versioning, backward compatibility budgets, deprecation and sunset process, strangler patterns for legacy replacement, decision reversibility ratings, fitness functions guarding architectural invariants in CI.
7. ADRs — decision record shape (context, options with tradeoffs, decision, consequences, revisit triggers), worked records for this stack's real decisions (polling vs Debezium with tripwire, saga vs 2PC, virtual threads vs reactive).

Shape per block: Decision context → options with honest tradeoffs → recommendation with conditions → reversibility note → verification (metric, review gate, or revisit trigger).

Budget: ~35 blocks, dense.

Boundaries: hardest-sentence test with 05 (tradeoff here, sequencing there); mechanism details live in stack files (13 relay, 12 RLS, 14 contracts); math foundations stay in 03. No ivory-tower patterns without a stack instantiation.

---

## Scope: 20-observability.txt

Purpose: the production-visibility reference — logs, metrics, traces, and alerts that make incidents diagnosable without leaking secrets. Practice with schemas; theory stays minimal.

Content, 6 kinds:

1. Structured logging — one JSON schema (ts, level, service, route, tenant, ms, requestId), context propagation via interceptors, allow-listed fields with redaction tests.
2. Metrics — RED per service, USE per resource, histogram discipline (no averaged latencies), cardinality budgets with label allow-lists.
3. Tracing with OTel — traceparent propagation, span naming, sampling strategy (head rules plus tail-based retention of errors and slow traces), trace-to-log joining on one key, exemplars linking metrics to traces.
4. SLOs and alerting — SLI selection, error-budget policy with deploy gating, symptom-based alerts with runbooks, page-vs-ticket routing tuned from drills.
5. Profiling and diagnostics — continuous JFR in production, flame-graph reading, heap/thread dump pairing, overhead budgets.
6. Security-aware telemetry — secret-shaped value scanning, PII minimization, tenant-scoped access to telemetry, audit of who viewed what.

Shape per block: Signal needed → schema or config fragment → how it reads during an incident → leak or noise anti-pattern → verification (drill, scan, or dashboard assertion).

Budget: ~25 blocks, dense.

Boundaries: testing is 18 (which verifies behavior pre-prod); Java tooling mechanics are 10; incident containment is 06/09. If a block debugs code rather than production, it belongs in 02.

---

## Scope: 21-linux-infra.txt

Purpose: the full-stack ops reference — Linux, Docker, Nginx, CI/CD, and Kubernetes for running the stack above. Commands and configs that work on current stable releases; full-stack coverage per the agreed span.

Content, 7 kinds:

1. Linux core — processes and signals, filesystems and permissions, systemd units with hardening, journald, networking (DNS resolution order, sockets, TLS verification), SSH discipline (keys, bastion, agent forwarding bans).
2. Docker — multi-stage builds with layer-cache ordering, distroless or minimal base images with non-root users, frozen lockfiles in images, secret mounts (never COPY of keys), image scanning and digest pinning, compose networking and DNS, resource limits.
3. Nginx — reverse proxy with forwarding headers, TLS 1.2+ with modern ciphers and HSTS (legacy isolated), WebSocket upgrade with long timeouts, SSE buffering off, gzip/caching tiers, rate limiting and connection caps, ambiguous-framing rejection.
4. CI/CD — GitHub Actions workflows (pinned actions by hash, secretless fork jobs, OIDC-to-cloud credentialless deploys per 09, environment protection for prod), build matrices, cache keys with lockfile hashes, artifact provenance, build-tool exposure: Maven/Gradle wrapper enforcement (no unwrapped builds), Gradle configuration cache and version catalogs, Maven toolchain and .mvn discipline, daemon/parallel settings as CI performance levers — exposure-level, not a build manual.
5. Kubernetes — deployments with probes (liveness vs readiness vs startup separated), resource requests/limits with OOM behavior understood, PodDisruptionBudgets for voluntary-disruption safety, secrets from the manager (never literals), network policies, HPA on sane signals, rollout strategy with rollback.
6. WireGuard and private networking — mesh basics, key rotation, peer allow-listing, DNS inside the mesh.
7. Deploy operations — blue-green and rolling strategies, migration-aware sequencing (migrations before code, expand-contract), smoke checks post-deploy, rollback decision criteria shared with 05's pre-committed rules.

Shape per block: Goal → config or command fragment → why these values → canonical failure with its log signature → verification (probe, scan, or drill evidence).

Budget: ~30 blocks, dense.

Boundaries: failure transcripts are 02 (which replays failures; 21 states the correct configuration); app wiring is 11; secrets lifecycle theory is 09. Version-sensitive flags verified before writing.

---

## Scope: 22-python.txt

Purpose: the Python support-file reference — modern typing, async, pytest, packaging, and CLI/data tooling for the calibration scripts, backtest harnesses, and glue code around the Java stack. Supporting role; depth stays proportional.

Content, 6 kinds:

1. Modern Python — current-stable idioms (version verified at implementation time), type hints with strict checking (mypy/pyright), dataclasses vs attrs vs Pydantic boundaries, pattern matching where it clarifies.
2. Async — asyncio task groups, cancellation and timeouts, async generators for streams, sync/async boundary discipline.
3. Pytest — fixtures and factories, markers (including async configuration), parameterized boundary tests, property-based testing with Hypothesis.
4. Packaging and CLI — pyproject discipline, uv for env/lock/install, ruff for lint/format, Typer/argparse CLIs with typed options, script entry points for corpus tooling.
5. Data and quant tooling — pandas/polars frames for strategy analysis, notebook-to-script discipline, reproducible seeds, CSV/Parquet interchange hygiene.
6. Interop notes — calling Python from JVM pipelines (and vice versa) safely, contract schemas at the boundary, error propagation across runtimes.

Shape per block: Goal → snippet → why this form → pitfall → verification (type-check, test, or repro evidence).

Budget: ~25 blocks, compact. Supporting file; breadth over depth.

Boundaries: Java equivalents stay in 10 (no language comparisons beyond one line); failure transcripts are 02; finance math is 23 (which may show Python snippets only as worked calculations, never as tooling advice).

---

## Scope: 23-finance-quant.txt

Purpose: the fenced finance slice — equities, options, greeks with GEX, volatility, and quant statistics for the user's occasional algo work. Small and explicitly fenced so its weight tunes independently; pure math foundations stay in 03.

Content, 6 kinds:

1. Market basics — order types, American vs European exercise styles, OHLCV semantics, splits/dividends adjustments, microstructure intuition (spread, depth, impact).
2. Options foundations — calls/puts, moneyness, expiry/exercise/assignment, payoff diagrams in words.
3. Pricing — Black-Scholes assumptions and limits, binomial intuition, funding and carry in pricing intuition, implied vs historical volatility, smile/skew/term structure reading.
4. Greeks and gamma positioning — delta/gamma/theta/vega/rho plus second-order (vomma/vanna/charm/veta), GEX/DEX construction, positive/negative gamma regimes, pinning mechanics.
5. Quant statistics — log returns, volatility estimators, Sharpe/Sortino with their gaming modes, max drawdown, Z-scores and hypothesis tests (applied here, taught in 03), regression readouts for factor exposure.
6. Backtest hygiene — lookahead prevention, survivorship, transaction costs and slippage, overfitting and multiple-testing correction, paper-vs-live divergence checklist.

Shape per block: Concept → worked micro-example with numbers → assumption stated → common misuse with its cost → verification (recomputed figure or checklist assertion).

Budget: ~20 blocks, compact and fenced. Weight tunes via manifest without touching SE files.

Boundaries: pure statistics and derivations are 03 (23 applies, never re-teaches); no proprietary strategies, no live signals, no account-specific content — textbook mechanics only.

---

## Scope: 24-react.txt

Purpose: retention-only React coverage — enough hooks, rendering, and composition knowledge for migration literacy and Vue comparison. Smallest file by design; React is not a target stack.

Content, 4 kinds:

1. Core model — JSX, components, props/state discipline, hooks rules (useState/useEffect/useMemo/useCallback/useRef), React 19 use() and actions noted for recognition only, context scoping.
2. Rendering — reconciliation intuition, controlled vs uncontrolled inputs, composition patterns (children, render props legacy, custom hooks).
3. Comparison with Vue — reactivity vs re-render models, refs vs signals-adjacent patterns, effect cleanup parallels, ecosystem mapping (Router, Query, state).
4. Migration notes — reading React code during porting, common translation shapes (useEffect to watch, context to provide/inject plus Pinia), pitfalls translators introduce.

Shape per block: Concept → short snippet → Vue parallel where one exists → translator pitfall → check.

Budget: ~15 blocks, compact. Retention weight only.

Boundaries: depth lives in 16/17 (Vue/Query); no React ecosystem depth (no Next.js, no React Server Components beyond a boundary note). If a block has no Vue parallel or migration value, it does not belong here.

---

## Scope: 25-privacy-gdpr.txt

Purpose: the GDPR compliance reference — rights, retention tensions, assessments, and breach discipline for backends holding personal data. Standalone file (not grouped with ecommerce) so its weight tunes independently; retention-vs-erasure tension with backups, telemetry, and logs made explicit.

Content, 6 kinds:

1. Lawful basis per purpose — contract, consent (granular, withdrawable), legitimate interest with balancing test, legal obligation; purpose registry per flow.
2. Data-subject rights — access (complete multi-system compilation on time), erasure via a deletion map (all stores registered, crypto-shredding where rewrite is infeasible), portability in structured formats with a dictionary.
3. Retention vs erasure — legal schedules overriding narrowly, exempt-copy deletion at expiry, backup strategy chosen with erasure in mind (shredding keys or bounded retention with re-deletion on restore, proven by drill).
4. DPIA and design duties — trigger checklist, mitigations as launch blockers, privacy-by-design (minimization, purpose limitation, private defaults), special-category prohibitions.
5. Breach discipline — 72-hour clock from awareness, phased notification, runbook with hour-0/24/48 milestones, tabletop drills timed against the bound.
6. Transfers and vendors — adequacy/SCCs derogations per flow with impact assessments, Article-28 terms, sub-processor register, procurement gated on mechanism entries.

Shape per block: Concept → rule → practice → verification (drill, matrix review, or audit evidence).

Budget: ~12 blocks, compact and fenced. Recorded actual ~1.2k tokens, 12 blocks.

Boundaries: vulnerability classes are 06; hygiene habits are 09; telemetry specifics are 20; backup mechanics are 12. No jurisdiction-specific legal advice beyond GDPR mechanics — counsel owns interpretation.

---

## Scope: 26-ecommerce.txt

Purpose: the state-of-the-art ecommerce backend reference — catalog to peak-season readiness at a bar above off-the-shelf platforms, with explicit why-it's-better reasoning per pattern (single truth with overlays, state machines over flags, reservation over races). Backend only; no storefront styling.

Content, 7 kinds:

1. Catalog and variants — PIM truth with channel overlays, SKU discipline per purchasable combination, bundles as explicit containers.
2. Pricing and promotions — precedence-ordered rule engine with replayable itemization, versioned promotion definitions with caps and kill switches.
3. Cart and checkout — snapshot carts with expiry, checkout as an enumerated state machine (no boolean-flag states), idempotent transitions.
4. Inventory and fulfillment — reservation with TTL against oversell, multi-node sourcing decisions, split-shipment communication, tracking aggregation.
5. Payments on current Stripe API (dahlia line, 2026-08 verified) — one PaymentIntent per order/session with reuse across retries, automatic 3DS via the SCA engine with exemption strategy, version-pinned webhooks verified on raw bytes driving fulfillment (never client callbacks), refunds/disputes as first-class flows, subscriptions with test clocks, tax by jurisdiction.
6. Discovery and demand — faceted search with relevance test sets, graceful recommendations with cold-start fallbacks, marketplace seller gating with ledger discipline and holdbacks.
7. Operations — returns/RMA as a designed loop, preference-respecting notifications with sender separation, versioned analytics events, peak-season drills with third-party limit confirmations.

Shape per block: Goal → pattern → why (with the better-than-platform reasoning where it matters) → pitfall with its cost → verification (test, drill, or audit).

Budget: ~25 blocks, dense but fenced. Recorded actual ~2.3k tokens, 23 blocks.

Boundaries: webhook/idempotency mechanics defer to 07/14 (referenced); GDPR constrains this file via 25 (erasure vs order history, marketing consent); finance math stays in 23. No real account data, no live keys — textbook mechanics only.

---

## Status

All 26 files scoped and implemented. SPEC holds per-file scope and actuals.
