#!/usr/bin/env python3
"""prep_calibration.py — turn the corpus into oQ-T calibration prompts.

Implements step 1 of PREP_PLAN.md (§2, §4 stages 1-3):

  extract   Split calibration/*.txt into blocks, classify every block with the
            per-file rule table below, and write the rule-made prompts.
            Exits non-zero if any block is unaccounted for.
  derive    For knowledge-card blocks (no question in them), ask the served
            model, thinking off, to write the request a developer would send.
            Each answer passes a leakage check; rejected drafts are retried.
  generate  Have the served model answer the prompts (thinking on, generic
            effort levels), sampled by manifest share up to a token budget.
            Every request is cached, so a rerun resumes exactly.
  render    Write the kept conversations in the source model's chat template
            (thinking included) into one calibration text file, and check
            that every special token survives as a single token. Needs
            `transformers`: run it with the oMLX venv python.
  all       extract, then derive.

Outputs go to <out>/ (default ~/oqup/prep/<run>/):
  blocks.jsonl    every block: id, file, index, sha, mode, text
  prompts.jsonl   one prompt per block that has one (rule-made or derived)
  cache/derive/   one JSON per derive request, keyed by content hash, so a
                  rerun only asks for what changed
  report-step1.md per-file accounting and derive results

Standard library only; Python 3.11+.

Examples:
  python3 scripts/prep_calibration.py extract --run pilot
  python3 scripts/prep_calibration.py derive --run pilot \\
      --model Qwen3.8-Flash-Next-oQ5e --server http://127.0.0.1:8000
  python3 scripts/prep_calibration.py all --run pilot --model ... --dry-run
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

REPO = Path(__file__).resolve().parent.parent
CALIB_DIR = REPO / "calibration"
MANIFEST = REPO / "manifest.json"

# Bump when the derive instructions change, so cached derives are not reused.
DERIVE_VERSION = "derive-v1"


# ---------------------------------------------------------------------------
# Block parsing
# ---------------------------------------------------------------------------


def split_blocks(text: str) -> list[str]:
    """Same split as scripts/lint_format.py: blocks separated by a '---' line."""
    out = []
    for raw in text.split("\n---\n"):
        lines = raw.strip("\n").splitlines()
        # Files 29/30 open with '#' comment lines describing their shape.
        while lines and lines[0].startswith("#"):
            lines.pop(0)
        block = "\n".join(lines).strip()
        if block:
            out.append(block)
    return out


def label_re(labels: tuple[str, ...]) -> re.Pattern:
    """Match a field label at line start, with an optional '(qualifier)'.

    Longest labels first, so 'SQL pattern' wins over 'SQL'.
    """
    alts = "|".join(re.escape(x) for x in sorted(labels, key=len, reverse=True))
    return re.compile(
        rf"^(?P<label>{alts})(?:\s*\((?P<qual>[^)\n]*)\))?:[ \t]*", re.MULTILINE
    )


def cut(block: str, cut_labels: tuple[str, ...], cut_extra: str | None):
    """Split a block at its first answer label. Returns (prompt_raw, answer_raw) or None."""
    positions = []
    if cut_labels:
        m = label_re(cut_labels).search(block)
        if m:
            positions.append(m.start())
    if cut_extra:
        m = re.compile(cut_extra, re.MULTILINE).search(block)
        if m:
            positions.append(m.start())
    if not positions:
        return None
    pos = min(positions)
    if pos == 0:
        return None
    return block[:pos].strip(), block[pos:].strip()


@dataclass
class Field:
    qual: str | None
    value: str


def fields(prompt_raw: str, labels: tuple[str, ...]) -> dict[str, Field]:
    """Parse the prompt part into known fields; unknown labels stay inside values."""
    out: dict[str, Field] = {}
    matches = list(label_re(labels).finditer(prompt_raw)) if labels else []
    if matches and matches[0].start() > 0:
        out["_pre"] = Field(None, prompt_raw[: matches[0].start()].strip())
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(prompt_raw)
        out[m.group("label")] = Field(m.group("qual"), prompt_raw[m.end() : end].strip())
    if not matches:
        out["_pre"] = Field(None, prompt_raw.strip())
    return out


# ---------------------------------------------------------------------------
# Renderers: fields -> chat messages
# ---------------------------------------------------------------------------

Messages = list[dict]
Renderer = Callable[[dict[str, Field], str, "Spec"], Messages]


def user(text: str) -> Messages:
    return [{"role": "user", "content": text.strip()}]


def with_stack(text: str, spec: "Spec") -> str:
    return f"{text.strip()}\n\nStack: {spec.ctx}." if spec.ctx else text.strip()


def r_instruction(f: dict[str, Field], raw: str, spec: "Spec") -> Messages:
    ins = f.get("Instruction")
    draft = f.get("Draft")
    if ins and ins.qual and "system" in ins.qual.lower():
        # 'Instruction (system, always in force): <rule> User: "<request>"'
        sys_part, sep, user_part = ins.value.partition(" User:")
        if sep:
            return [
                {"role": "system", "content": sys_part.strip()},
                {"role": "user", "content": user_part.strip().strip('"').strip()},
            ]
    if draft and ins:
        return user(f"Draft:\n{draft.value}\n\n{ins.value}")
    return user(ins.value if ins else raw)


def r_failure(f: dict[str, Field], raw: str, spec: "Spec") -> Messages:
    return user(f"{raw}\n\nFind the root cause and fix it.")


def r_question(f: dict[str, Field], raw: str, spec: "Spec") -> Messages:
    q = f.get("Q")
    passage = f.get("Passage")
    if q is None:
        # Instruction-style labels ('Summarize in one sentence: ...') are the
        # request themselves, so the raw text is already the prompt.
        return user(raw)
    if passage:
        return user(f"{passage.value}\n\n{q.value}")
    return user(q.value)


def r_goal(f: dict[str, Field], raw: str, spec: "Spec") -> Messages:
    goal = f.get("Goal") or f.get("Task")
    text = goal.value if goal else raw
    ctx = f.get("Context")
    if ctx:
        text = f"{text}\n\nContext: {ctx.value}"
    return user(with_stack(text, spec))


def r_probe(f: dict[str, Field], raw: str, spec: "Spec") -> Messages:
    t, p = f.get("Target"), f.get("Preconditions")
    text = "Authorized security assessment of our own service.\n"
    text += f"Target: {t.value if t else raw}\n"
    if p:
        text += f"What we have: {p.value}\n"
    text += "\nHow would you test this, what is the pass bar, and what would failing evidence look like?"
    return user(text)


def r_test(f: dict[str, Field], raw: str, spec: "Spec") -> Messages:
    w = f.get("What to test")
    return user(with_stack(
        f"How should we test this, and at which level? {w.value if w else raw}", spec))


def r_decision(f: dict[str, Field], raw: str, spec: "Spec") -> Messages:
    d, o = f.get("Decision context"), f.get("Options")
    text = f"Situation: {d.value}" if d else raw
    c = f.get("Context")
    if c:
        text += f"\n\nContext: {c.value}"
    if o:
        text += f"\n\nOptions: {o.value}"
    text += "\n\nWhat do you recommend, under which conditions, and how reversible is it?"
    return user(with_stack(text, spec))


def r_signal(f: dict[str, Field], raw: str, spec: "Spec") -> Messages:
    s = f.get("Signal needed")
    return user(with_stack(
        f"We need this observability signal: {s.value if s else raw}\n\n"
        "Design the telemetry for it and say how it would be used during an incident.", spec))


def r_fixture(f: dict[str, Field], raw: str, spec: "Spec") -> Messages:
    t, x = f.get("Target"), f.get("Fixture")
    # Drop corpus cross-references like 'Java 25 (10)' — file numbers mean nothing to the model.
    target = re.sub(r" \(\d{2}\)", "", t.value) if t else raw
    text = f"Review this for a weakness.\nTarget: {target}\n"
    if x:
        text += f"Fixture: {x.value}\n"
    text += "\nHow does it fail, what is the pass bar, and what evidence would show the failure?"
    return user(text)


def r_task(f: dict[str, Field], raw: str, spec: "Spec") -> Messages:
    """Task-first blocks (files 32+): Goal / Context / Acceptance."""
    g, c, a = f.get("Goal"), f.get("Context"), f.get("Acceptance")
    text = g.value if g else raw
    if c:
        text += f"\n\nContext: {c.value}"
    if a:
        text += f"\n\nDone when: {a.value}"
    return user(text)


def r_legacy(f: dict[str, Field], raw: str, spec: "Spec") -> Messages:
    leg = f.get("Legacy")
    return user(with_stack(
        f"This is legacy:\n{leg.value if leg else raw}\n\n"
        "Migrate it to the current form and explain what changes and why.", spec))


# ---------------------------------------------------------------------------
# Rule table (PREP_PLAN.md §2)
# ---------------------------------------------------------------------------


@dataclass
class Spec:
    mode: str                       # "rule" | "derive" | "mixed-passage"
    cut: tuple[str, ...] = ()       # first of these labels starts the answer
    fields: tuple[str, ...] = ()    # labels parsed out of the prompt part
    render: Renderer | None = None
    ctx: str | None = None          # stack named in the prompt / derive hint
    cut_extra: str | None = None    # extra answer-start regex (e.g. 'Step 1.')
    starts: tuple[str, ...] = ()    # mixed-passage: labels that open a prompt block
    hint: str | None = None         # extra framing for derive
    cut_optional: bool = False      # no answer label = the whole block is the prompt


GOAL_CUT = ("Wiring", "Snippet", "Pattern", "Why", "Fix", "Config fragment", "Config")

SPECS: dict[str, Spec] = {
    "01-instruction-following": Spec("rule", ("Response", "Correction"), ("Instruction", "Draft"), r_instruction),
    "02-repair-loops": Spec("rule", ("Diagnosis",), ("Failure",), r_failure),
    "03-math-logic-cot": Spec("rule", ("Answer", "Correction"), ("Q",), r_question, cut_extra=r"^Step \d+[.:]"),
    "04-general-reasoning": Spec(
        "mixed-passage", ("Answer", "A", "Summary", "Paraphrase"), ("Q", "Passage"), r_question,
        starts=("Q", "Passage", "Summarize in one sentence", "Compress to one sentence",
                "Paraphrase without meaning shift"),
    ),
    "05-agentic-coding": Spec("rule", ("Investigation", "Findings", "Plan", "Decisions"), ("Goal", "Context"), r_goal),
    "06-security": Spec("derive", ctx="application security for a Java/Spring + Vue + Postgres + Kafka estate"),
    "07-auth-oidc-oauth": Spec("derive", ctx="OAuth 2 / OIDC for an SPA and Spring APIs"),
    "08-api-pentest": Spec("rule", ("Probes", "Pass bar"), ("Target", "Preconditions"), r_probe),
    "09-opsec": Spec("derive", ctx="operational security and secrets handling for a software team"),
    "10-java": Spec("derive", ctx="Java 25"),
    "11-spring": Spec("rule", GOAL_CUT, ("Goal", "Context"), r_goal, ctx="Spring Boot 4.1 (Spring Framework 7, Java 25)"),
    "12-postgresql": Spec("rule", ("SQL pattern", "SQL", "Reading"), ("Task",), r_goal, ctx="PostgreSQL 18"),
    "13-kafka": Spec("rule", GOAL_CUT, ("Goal", "Context"), r_goal, ctx="Apache Kafka 4.3 (KRaft)"),
    "14-http-api": Spec("derive", ctx="HTTP API design"),
    "15-typescript": Spec("rule", GOAL_CUT, ("Goal", "Context"), r_goal, ctx="TypeScript 7 with TypeScript 6.0 compatibility"),
    "16-vue": Spec("rule", GOAL_CUT, ("Goal", "Context"), r_goal, ctx="Vue 3 (script setup, TypeScript)"),
    "17-tanstack": Spec("rule", GOAL_CUT, ("Goal", "Context"), r_goal, ctx="TanStack Query v5 with Vue 3"),
    "18-testing": Spec("rule", ("Minimal example", "Example", "Why this level", "Why this technique"),
                       ("What to test",), r_test, ctx="Java/Spring backend and TypeScript/Vue frontend"),
    "19-architecture": Spec("rule", ("Recommendation with conditions", "Recommendation", "Decision"),
                            ("Decision context", "Context", "Options"), r_decision),
    "20-observability": Spec("rule", ("Schema or config fragment", "Schema", "Config fragment"),
                             ("Signal needed",), r_signal),
    "21-linux-infra": Spec("rule", GOAL_CUT, ("Goal", "Context"), r_goal,
                           ctx="Linux infrastructure (systemd, Docker, Nginx, CI/CD, Kubernetes)"),
    "22-python": Spec("rule", GOAL_CUT, ("Goal", "Context"), r_goal, ctx="Python 3.14"),
    "23-finance-quant": Spec("derive", ctx="finance and quantitative engineering"),
    "24-react": Spec("derive", ctx="React, explained to a Vue developer"),
    "25-privacy-gdpr": Spec("derive", ctx="privacy and GDPR engineering"),
    "26-ecommerce": Spec("rule", GOAL_CUT, ("Goal", "Context"), r_goal, ctx="e-commerce platform engineering"),
    "27-adversarial-walking-patterns": Spec("rule", ("How it fails",), ("Target", "Fixture"), r_fixture),
    "28-invariant-exploitation": Spec("rule", ("Recommendation with conditions", "Recommendation"),
                                      ("Decision context", "Options"), r_decision),
    "29-llm-integration": Spec("rule", ("Recommendation with conditions", "Recommendation"),
                               ("Decision context", "Options"), r_decision),
    "30-experimentation-and-flagging": Spec("rule", ("Minimal example", "Example"), ("What to test",), r_test),
    # Task-first files (PREP_PLAN.md §3, §14): everything before Reference is the prompt.
    "37-git-code-review": Spec("rule", ("Reference",), ("Goal", "Context", "Acceptance"), r_task, cut_optional=True),
    "38-shell-cli": Spec("rule", ("Reference",), ("Goal", "Context", "Acceptance"), r_task, cut_optional=True),
    "39-cicd-iac": Spec("rule", ("Reference",), ("Goal", "Context", "Acceptance"), r_task, cut_optional=True),
    "31-offensive-security": Spec(
        "derive", ctx="offensive security",
        hint="The developer is running an authorized penetration test of their own organisation's staging estate.",
    ),
}

LEGACY = Spec("rule", ("Replacement",), ("Legacy",), r_legacy)


# ---------------------------------------------------------------------------
# extract
# ---------------------------------------------------------------------------


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load_shares() -> dict[str, float]:
    try:
        m = json.loads(MANIFEST.read_text(encoding="utf-8"))
        return {f["id"]: float(f.get("share") or 0) for f in m.get("files", [])}
    except (OSError, ValueError, KeyError):
        return {}


def classify(stem: str, block: str, spec: Spec):
    """Return (mode, messages-or-None, reason). mode: rule | derive | passage | unaccounted."""
    if block.startswith("Legacy:"):
        spec_ = Spec(LEGACY.mode, LEGACY.cut, LEGACY.fields, LEGACY.render, ctx=spec.ctx)
        return _rule(block, spec_, "legacy")

    if spec.mode == "derive":
        return "derive", None, "knowledge card"

    if spec.mode == "mixed-passage":
        if not label_re(spec.starts).match(block):
            return "passage", None, "unlabelled passage"
        return _rule(block, spec, "rule")

    return _rule(block, spec, "rule")


def _rule(block: str, spec: Spec, reason: str):
    parts = cut(block, spec.cut, spec.cut_extra)
    if parts is None and spec.cut_optional:
        parts = (block, "")
    if parts is None:
        return "unaccounted", None, f"no answer label among {list(spec.cut)}"
    prompt_raw, _answer = parts
    f = fields(prompt_raw, spec.fields)
    msgs = spec.render(f, prompt_raw, spec)
    if not msgs or not msgs[-1]["content"].strip():
        return "unaccounted", None, "empty prompt after render"
    return "rule", msgs, reason


def do_extract(out: Path, only: set[str] | None) -> int:
    out.mkdir(parents=True, exist_ok=True)
    shares = load_shares()
    files = sorted(CALIB_DIR.glob("*.txt"))
    rows, prompts, problems = [], [], []
    table = []
    for path in files:
        stem = path.stem
        if only and stem not in only:
            continue
        spec = SPECS.get(stem)
        if spec is None:
            problems.append(f"{stem}: no rule-table entry (add one to SPECS)")
            continue
        counts = {"rule": 0, "derive": 0, "passage": 0, "unaccounted": 0}
        for i, block in enumerate(split_blocks(path.read_text(encoding="utf-8"))):
            bid = f"{stem}#{i:03d}"
            bsha = sha(block)
            mode, msgs, reason = classify(stem, block, spec)
            counts[mode] += 1
            rows.append({"id": bid, "file": stem, "index": i, "sha": bsha,
                         "mode": mode, "reason": reason, "text": block})
            if mode == "unaccounted":
                problems.append(f"{bid}: {reason} — starts {block[:70]!r}")
            if mode == "rule":
                prompts.append({"id": bid, "file": stem, "sha": bsha, "source": "corpus-rule",
                                "reason": reason, "share": shares.get(stem, 0.0), "messages": msgs})
        table.append((stem, sum(counts.values()), counts, shares.get(stem, 0.0)))

    write_jsonl(out / "blocks.jsonl", rows)
    # Keep derived prompts from an earlier derive run; they are merged back in.
    derived = [p for p in read_jsonl(out / "prompts.jsonl") if p.get("source") == "corpus-derived"]
    live = {r["sha"] for r in rows if r["mode"] == "derive"}
    derived = [p for p in derived if p["sha"] in live]
    write_jsonl(out / "prompts.jsonl", prompts + derived)

    print(f"{'file':40s} {'blocks':>6} {'rule':>5} {'derive':>6} {'passage':>7} {'unacc.':>6} {'share':>5}")
    for stem, n, c, s in table:
        print(f"{stem:40s} {n:6d} {c['rule']:5d} {c['derive']:6d} {c['passage']:7d} {c['unaccounted']:6d} {s:5.1f}")
    tot = {k: sum(c[k] for _, _, c, _ in table) for k in ("rule", "derive", "passage", "unaccounted")}
    print(f"{'TOTAL':40s} {sum(n for _, n, _, _ in table):6d} {tot['rule']:5d} {tot['derive']:6d} "
          f"{tot['passage']:7d} {tot['unaccounted']:6d}")
    write_report(out, table, problems, None)
    if problems:
        print("\nUNACCOUNTED — fix the rule table or the block:", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        return 1
    print(f"\nall blocks accounted for -> {out}")
    return 0


# ---------------------------------------------------------------------------
# derive
# ---------------------------------------------------------------------------

DERIVE_SYSTEM = (
    "You turn reference notes into the request a developer would send to an AI coding "
    "assistant. Write only that request, in the developer's own voice, in one to four "
    "sentences. It must ask for what the notes answer. It must not reveal the answer, the "
    "fix, the conclusion, or any code or configuration from the notes. Mention the stack "
    "or situation the way a real developer would. No preamble, no quotes, no headings."
)

# Per-family request settings. 'thinking_off' is merged into chat_template_kwargs.
# Unknown families fail loudly instead of guessing (PREP_PLAN.md §4a).
FAMILIES = {
    "qwen": {
        "thinking_off": {"enable_thinking": False},
        "thinking_on": {"enable_thinking": True},
        # Generic level -> the model's own name (Qwen3.8-Flash-Next card:
        # low / medium / xhigh; xhigh is its single top level).
        "effort": {"low": "low", "medium": "medium", "max": "xhigh"},
        "sampling": {"temperature": 1.0, "top_p": 0.95, "top_k": 20},
        "render_kwargs": {"enable_thinking": True, "preserve_thinking": True},
    },
}


def family_of(model: str, override: str | None) -> str:
    if override:
        fam = override
    else:
        low = model.lower()
        fam = "qwen" if "qwen" in low else ""
    if fam not in FAMILIES:
        raise SystemExit(
            f"unknown model family for {model!r}; pass --family one of {sorted(FAMILIES)} "
            "or add the family's thinking-off settings to FAMILIES")
    return fam


def words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9_]+", text.lower())


def ngrams(ws: list[str], n: int) -> set[tuple[str, ...]]:
    return {tuple(ws[i : i + n]) for i in range(len(ws) - n + 1)}


def leakage(prompt: str, block: str) -> tuple[bool, str]:
    """Reject prompts that copy the card's body (everything after its first line)."""
    body = "\n".join(block.splitlines()[1:])
    p = prompt.strip()
    if not p:
        return False, "empty"
    if len(p) > 1200:
        return False, "too long"
    if re.search(r"(?i)\b(the|these|those) notes\b|reference notes", p):
        return False, "mentions the notes"
    for line in block.splitlines()[1:]:
        line = line.strip()
        if len(line) >= 25 and line in p:
            return False, "copies a line from the card"
    pw = words(p)
    grams = ngrams(pw, 6)
    if grams:
        overlap = len(grams & ngrams(words(body), 6)) / len(grams)
        if overlap > 0.25:
            return False, f"6-gram overlap {overlap:.0%}"
    return True, "ok"


def strip_think(text: str) -> str:
    return re.sub(r"(?s)<think>.*?</think>", "", text or "").strip()


def chat_raw(server: str, api_key: str | None, payload: dict, timeout: float) -> dict:
    req = urllib.request.Request(
        server.rstrip("/") + "/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json",
                 **({"Authorization": f"Bearer {api_key}"} if api_key else {})},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def chat(server: str, api_key: str | None, payload: dict, timeout: float) -> str:
    req = urllib.request.Request(
        server.rstrip("/") + "/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json",
                 **({"Authorization": f"Bearer {api_key}"} if api_key else {})},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = json.loads(resp.read().decode("utf-8"))
    return strip_think(body["choices"][0]["message"].get("content") or "")


def derive_one(row: dict, spec: Spec, args, fam: str, cache_dir: Path) -> dict:
    hint = f"Topic: {spec.ctx}." if spec.ctx else ""
    if spec.hint:
        hint += f" {spec.hint}"
    attempts = []
    for attempt in range(args.max_attempts):
        temp = args.temperature if attempt == 0 else min(1.0, args.temperature + 0.3 * attempt)
        payload = {
            "model": args.model,
            "messages": [
                {"role": "system", "content": DERIVE_SYSTEM},
                {"role": "user", "content": f"{hint}\n\nReference notes:\n\n{row['text']}".strip()},
            ],
            "temperature": temp,
            "max_tokens": 400,
            "chat_template_kwargs": FAMILIES[fam]["thinking_off"],
        }
        key = sha(json.dumps([DERIVE_VERSION, row["sha"], payload], sort_keys=True))
        cpath = cache_dir / f"{key}.json"
        if cpath.exists():
            rec = json.loads(cpath.read_text(encoding="utf-8"))
        else:
            if args.dry_run:
                return {"id": row["id"], "status": "dry-run", "payload": payload}
            try:
                text = chat(args.server, args.api_key, payload, args.timeout)
            except (urllib.error.URLError, TimeoutError, KeyError, ValueError) as e:
                attempts.append({"attempt": attempt, "error": str(e)})
                time.sleep(min(10, 2 ** attempt))
                continue
            ok, why = leakage(text, row["text"])
            rec = {"key": key, "id": row["id"], "sha": row["sha"], "attempt": attempt,
                   "temperature": temp, "model": args.model, "prompt": text,
                   "accepted": ok, "why": why, "version": DERIVE_VERSION}
            tmp = cpath.with_suffix(".tmp")
            tmp.write_text(json.dumps(rec, ensure_ascii=False, indent=1), encoding="utf-8")
            os.replace(tmp, cpath)
        attempts.append({"attempt": attempt, "accepted": rec["accepted"], "why": rec["why"]})
        if rec["accepted"]:
            return {"id": row["id"], "status": "accepted", "prompt": rec["prompt"],
                    "attempts": attempts, "model": rec["model"]}
    return {"id": row["id"], "status": "rejected", "attempts": attempts}


def do_derive(out: Path, args, only: set[str] | None) -> int:
    rows = [r for r in read_jsonl(out / "blocks.jsonl") if r["mode"] == "derive"]
    if only:
        rows = [r for r in rows if r["file"] in only]
    if args.limit:
        rows = rows[: args.limit]
    if not rows:
        print("nothing to derive (run extract first?)")
        return 0
    fam = family_of(args.model, args.family)
    cache_dir = out / "cache" / "derive"
    cache_dir.mkdir(parents=True, exist_ok=True)
    shares = load_shares()

    if args.dry_run:
        r = derive_one(rows[0], SPECS[rows[0]["file"]], args, fam, cache_dir)
        print(f"dry run: {len(rows)} derive requests to {args.server} as {args.model} ({fam})")
        print(json.dumps(r.get("payload", r), ensure_ascii=False, indent=1)[:2500])
        return 0

    results = []
    t0 = time.time()
    with cf.ThreadPoolExecutor(max_workers=args.concurrency) as ex:
        futs = {ex.submit(derive_one, r, SPECS[r["file"]], args, fam, cache_dir): r for r in rows}
        for i, fut in enumerate(cf.as_completed(futs), 1):
            res = fut.result()
            res["row"] = futs[fut]
            results.append(res)
            if i % 20 == 0 or i == len(rows):
                ok = sum(1 for x in results if x["status"] == "accepted")
                print(f"  {i}/{len(rows)} done, {ok} accepted, {time.time() - t0:.0f}s", flush=True)

    keep = [p for p in read_jsonl(out / "prompts.jsonl") if p.get("source") != "corpus-derived"]
    derived_ids = set()
    for res in sorted(results, key=lambda x: x["id"]):
        if res["status"] != "accepted":
            continue
        row = res["row"]
        derived_ids.add(row["id"])
        keep.append({"id": row["id"], "file": row["file"], "sha": row["sha"],
                     "source": "corpus-derived", "reason": "knowledge card",
                     "share": shares.get(row["file"], 0.0), "derive_model": res["model"],
                     "messages": user(res["prompt"])})
    # Earlier derived prompts for blocks not re-run this time stay in place.
    for p in read_jsonl(out / "prompts.jsonl"):
        if p.get("source") == "corpus-derived" and p["id"] not in derived_ids and \
                p["id"] not in {r["id"] for r in rows}:
            keep.append(p)
    write_jsonl(out / "prompts.jsonl", keep)

    rejected = [r for r in results if r["status"] != "accepted"]
    write_report(out, None, [], results)
    print(f"derive: {len(results) - len(rejected)} accepted, {len(rejected)} rejected -> {out}")
    for r in rejected[:20]:
        print(f"  rejected {r['id']}: {r['attempts']}", file=sys.stderr)
    return 0


# ---------------------------------------------------------------------------
# generate (PREP_PLAN.md §4 stages 4-5, §4a)
# ---------------------------------------------------------------------------

GENERATE_VERSION = "generate-v1"
EFFORT_LEVELS = ("max", "medium", "low")


def parse_effort_mix(text: str) -> list[tuple[str, float]]:
    """'max=70,medium=15,low=15' -> cumulative thresholds."""
    parts = []
    for item in text.split(","):
        name, _, val = item.partition("=")
        name = name.strip()
        if name not in EFFORT_LEVELS:
            raise SystemExit(f"--effort-mix: unknown level {name!r} (use {', '.join(EFFORT_LEVELS)})")
        parts.append((name, float(val)))
    total = sum(v for _, v in parts)
    if total <= 0:
        raise SystemExit("--effort-mix must have a positive total")
    acc, out = 0.0, []
    for name, v in parts:
        acc += v / total
        out.append((name, acc))
    return out


def _unit(*parts) -> float:
    """Deterministic number in [0, 1) from the given parts."""
    h = hashlib.sha256("|".join(str(p) for p in parts).encode()).digest()
    return int.from_bytes(h[:8], "big") / 2**64


def plan_requests(prompts: list[dict], args) -> list[dict]:
    """Samples per prompt from the file's manifest share, deterministic order."""
    mix = parse_effort_mix(args.effort_mix)
    by_file: dict[str, float] = {}
    for p in prompts:
        by_file[p["file"]] = float(p.get("share") or 0.0)
    live = [v for v in by_file.values() if v > 0]
    mean_share = sum(live) / len(live) if live else 1.0
    items = []
    for p in prompts:
        share = float(p.get("share") or 0.0)
        if share <= 0:
            continue                      # unweighted files (29/30) are skipped
        spp = max(1, min(args.max_samples, round(args.samples_per_prompt * share / mean_share)))
        for k in range(spp):
            u = _unit(args.seed, "effort", p["id"], p["sha"], k)
            effort = next(name for name, cut in mix if u < cut)
            items.append({"prompt": p, "sample": k, "effort": effort,
                          "order": _unit(args.seed, "order", p["id"], p["sha"], k)})
    items.sort(key=lambda it: it["order"])
    return items


def verdict(content: str, reasoning: str, finish: str | None) -> tuple[bool, str]:
    import zlib

    text = f"{reasoning}\n{content}".strip()
    if not text:
        return False, "empty"
    if len(text) > 4000:
        ratio = len(zlib.compress(text.encode("utf-8"))) / len(text.encode("utf-8"))
        if ratio < 0.08:
            return False, "repetition loop"
    if len(content) < 400 and re.search(
            r"(?i)\b(i can(no|')t (help|assist)|i'm not able to help|i won't (help|provide))", content):
        return False, "refusal"
    if finish == "length":
        # Thinking that hit the token cap is still the model's own text, so it
        # stays useful for calibration; it is kept and counted separately.
        return True, "truncated (kept)"
    return True, "ok"


def generate_one(item: dict, args, fam: str, cache_dir: Path) -> dict:
    p = item["prompt"]
    f = FAMILIES[fam]
    payload = {
        "model": args.model,
        "messages": p["messages"],
        **f["sampling"],
        "max_tokens": args.max_tokens,
        "seed": int(_unit(args.seed, "seed", p["id"], item["sample"]) * 2**31),
        "chat_template_kwargs": {**f["thinking_on"], "reasoning_effort": f["effort"][item["effort"]]},
    }
    key = sha(json.dumps([GENERATE_VERSION, p["sha"], p["messages"], item["sample"], payload],
                         sort_keys=True))
    cpath = cache_dir / f"{key}.json"
    if cpath.exists():
        rec = json.loads(cpath.read_text(encoding="utf-8"))
        rec["cached"] = True
        return rec
    last_err = None
    for attempt in range(3):
        try:
            t0 = time.time()
            body = chat_raw(args.server, args.api_key, payload, args.timeout)
            choice = body["choices"][0]
            msg = choice.get("message") or {}
            content = strip_think(msg.get("content") or "")
            reasoning = (msg.get("reasoning_content") or "").strip()
            if not reasoning:
                m = re.search(r"(?s)<think>(.*?)</think>", msg.get("content") or "")
                reasoning = m.group(1).strip() if m else ""
            usage = body.get("usage") or {}
            tokens = int(usage.get("completion_tokens")
                         or (len(content) + len(reasoning)) // 4)
            ok, why = verdict(content, reasoning, choice.get("finish_reason"))
            rec = {"key": key, "id": p["id"], "file": p["file"], "sha": p["sha"],
                   "sample": item["sample"], "effort": item["effort"],
                   "model": args.model, "messages": p["messages"],
                   "reasoning": reasoning, "content": content,
                   "finish_reason": choice.get("finish_reason"), "tokens": tokens,
                   "seconds": round(time.time() - t0, 2), "keep": ok, "why": why,
                   "version": GENERATE_VERSION}
            tmp = cpath.with_suffix(".tmp")
            tmp.write_text(json.dumps(rec, ensure_ascii=False), encoding="utf-8")
            os.replace(tmp, cpath)
            rec["cached"] = False
            return rec
        except (urllib.error.URLError, TimeoutError, KeyError, ValueError, IndexError) as e:
            last_err = e
            time.sleep(min(30, 3 * 2 ** attempt))
    return {"id": p["id"], "file": p["file"], "error": str(last_err), "keep": False,
            "why": "request failed", "tokens": 0, "cached": False}


def model_tag(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", name)


def do_generate(out: Path, args) -> int:
    prompts = read_jsonl(out / "prompts.jsonl")
    if not prompts:
        print("no prompts (run extract and derive first)", file=sys.stderr)
        return 1
    fam = family_of(args.model, args.family)
    adir = out / "answers" / model_tag(args.model)
    cache_dir = adir / "cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    items = plan_requests(prompts, args)
    budget = int(args.budget_tokens)
    print(f"generate: {len(items)} planned requests over {len({i['prompt']['id'] for i in items})} "
          f"prompts; budget {budget:,} tokens; model {args.model}; concurrency {args.concurrency}",
          flush=True)

    results: list[dict] = []
    tokens_done = 0
    fresh_tokens, fresh_seconds_start = 0, None
    failures_in_row = 0
    t0 = time.time()
    it = iter(items)
    pending: dict = {}
    pilot_reported = False
    with cf.ThreadPoolExecutor(max_workers=args.concurrency) as ex:
        def submit_next():
            nonlocal fresh_seconds_start
            if tokens_done >= budget:
                return False
            nxt = next(it, None)
            if nxt is None:
                return False
            if fresh_seconds_start is None:
                fresh_seconds_start = time.time()
            pending[ex.submit(generate_one, nxt, args, fam, cache_dir)] = nxt
            return True

        for _ in range(args.concurrency):
            if not submit_next():
                break
        while pending:
            done, _ = cf.wait(list(pending), return_when=cf.FIRST_COMPLETED)
            for fut in done:
                pending.pop(fut)
                rec = fut.result()
                results.append(rec)
                tokens_done += int(rec.get("tokens") or 0)
                if not rec.get("cached"):
                    fresh_tokens += int(rec.get("tokens") or 0)
                failures_in_row = failures_in_row + 1 if rec.get("why") == "request failed" else 0
                if failures_in_row >= 10:
                    print("generate: 10 failed requests in a row; is the server up? "
                          f"last error: {rec.get('error')}", file=sys.stderr, flush=True)
                    ex.shutdown(cancel_futures=True)
                    return 2
                n = len(results)
                if not pilot_reported and fresh_tokens and n >= args.pilot:
                    rate = fresh_tokens / max(time.time() - (fresh_seconds_start or t0), 1e-6)
                    remaining = max(budget - tokens_done, 0)
                    print(f"generate: pilot {n} answers, {rate:.0f} tokens/s overall -> "
                          f"about {remaining / max(rate, 1e-6) / 3600:.1f} h for the remaining "
                          f"{remaining:,} tokens", flush=True)
                    pilot_reported = True
                if n % args.log_every == 0:
                    el = time.time() - t0
                    rate = fresh_tokens / max(time.time() - (fresh_seconds_start or t0), 1e-6)
                    eta = max(budget - tokens_done, 0) / max(rate, 1e-6) if fresh_tokens else 0
                    kept = sum(1 for r in results if r.get("keep"))
                    print(f"generate: {n} answers ({kept} kept), {tokens_done:,}/{budget:,} tokens, "
                          f"{el / 60:.0f} min elapsed, ~{eta / 60:.0f} min left", flush=True)
                submit_next()

    kept = [r for r in results if r.get("keep")]
    write_jsonl(adir / "answers.jsonl", sorted(kept, key=lambda r: (r["id"], r["sample"])))
    why_counts: dict[str, int] = {}
    effort_counts: dict[str, int] = {}
    for r in results:
        why_counts[r["why"]] = why_counts.get(r["why"], 0) + 1
        if r.get("keep"):
            effort_counts[r["effort"]] = effort_counts.get(r["effort"], 0) + 1
    by_file: dict[str, list[int]] = {}
    for r in results:
        acc = by_file.setdefault(r["file"], [0, 0, 0])
        acc[0 if r.get("keep") else 1] += 1
        acc[2] += int(r.get("tokens") or 0)
    summary = {"model": args.model, "requests": len(results), "kept": len(kept),
               "tokens": tokens_done, "budget": budget, "verdicts": why_counts,
               "kept_by_effort": effort_counts,
               "by_file": {k: {"kept": a, "dropped": b, "tokens": t} for k, (a, b, t) in sorted(by_file.items())},
               "minutes": round((time.time() - t0) / 60, 1)}
    (adir / "generate.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    print(f"generate: done — {len(kept)}/{len(results)} answers kept, {tokens_done:,} tokens, "
          f"verdicts {why_counts} -> {adir}", flush=True)
    return 0


# ---------------------------------------------------------------------------
# render (needs transformers: run with the oMLX venv python)
# ---------------------------------------------------------------------------


def do_render(out: Path, args) -> int:
    try:
        from transformers import AutoTokenizer
    except ImportError:
        print("render needs `transformers`: run it with the oMLX venv python", file=sys.stderr)
        return 1
    if not args.source:
        print("render needs --source <source model dir> (for its tokenizer and chat template)",
              file=sys.stderr)
        return 1
    adir = out / "answers" / model_tag(args.model)
    answers = read_jsonl(adir / "answers.jsonl")
    if not answers:
        print(f"no kept answers in {adir} (run generate first)", file=sys.stderr)
        return 1
    tok = AutoTokenizer.from_pretrained(args.source)
    if not getattr(tok, "chat_template", None):
        print(f"{args.source} has no chat template", file=sys.stderr)
        return 1
    fam = family_of(args.model, args.family)
    kwargs = FAMILIES[fam]["render_kwargs"]

    def render(messages):
        return tok.apply_chat_template(messages, tokenize=False, add_generation_prompt=False, **kwargs)

    mode = "template"
    texts = []
    for r in answers:
        assistant = {"role": "assistant", "content": r["content"]}
        if r.get("reasoning"):
            assistant["reasoning_content"] = r["reasoning"]
        msgs = [*r["messages"], assistant]
        if mode == "template":
            text = render(msgs)
            if r.get("reasoning") and r["reasoning"][:80] not in text:
                # This template drops reasoning_content: put the thinking in
                # the content as <think> blocks, the format the model emits.
                mode = "inline-think"
        if mode == "inline-think":
            inline = dict(assistant)
            inline.pop("reasoning_content", None)
            if r.get("reasoning"):
                inline["content"] = f"<think>\n{r['reasoning']}\n</think>\n\n{r['content']}"
            text = render([*r["messages"], inline])
        texts.append((sha(f"{args.seed}|{r['key']}"), text))

    passages = [b["text"] for b in read_jsonl(out / "blocks.jsonl") if b["mode"] == "passage"]
    texts += [(sha(f"{args.seed}|passage|{t}"), t) for t in passages]
    texts.sort(key=lambda x: x[0])
    bundle = "\n".join(t for _, t in texts) + "\n"

    specials = set(getattr(tok, "all_special_tokens", []) or [])
    for t in (getattr(tok, "added_tokens_decoder", {}) or {}).values():
        specials.add(getattr(t, "content", str(t)))
    broken = []
    for sp in sorted(specials):
        if sp and sp in bundle:
            ids = tok.encode(sp, add_special_tokens=False)
            if len(ids) != 1:
                broken.append((sp, ids))
    if broken:
        print(f"special tokens do not survive as single tokens: {broken[:5]}", file=sys.stderr)
        return 1

    path = Path(args.bundle).expanduser() if args.bundle else adir / "bundle.txt"
    tmp = path.with_suffix(".tmp")
    tmp.write_text(bundle, encoding="utf-8")
    os.replace(tmp, path)
    n_tokens = len(tok(bundle, add_special_tokens=False)["input_ids"])
    summary = {"bundle": str(path), "sha256": sha(bundle), "conversations": len(answers),
               "passages": len(passages), "tokens": n_tokens, "mode": mode,
               "special_tokens_checked": sorted(sp for sp in specials if sp and sp in bundle)}
    (adir / "render.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    print(f"render: {len(answers)} conversations + {len(passages)} passages, {n_tokens:,} tokens, "
          f"mode {mode} -> {path}", flush=True)
    return 0


# ---------------------------------------------------------------------------
# I/O and report
# ---------------------------------------------------------------------------


def read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(x) for x in path.read_text(encoding="utf-8").splitlines() if x.strip()]


def write_jsonl(path: Path, rows: list[dict]) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    os.replace(tmp, path)


def write_report(out: Path, table, problems, derive_results) -> None:
    path = out / "report-step1.md"
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    sections = dict(re.findall(r"(?ms)^## (\w+)\n(.*?)(?=^## |\Z)", old))
    if table is not None:
        lines = ["| file | blocks | rule | derive | passage | unaccounted | share |",
                 "|---|---:|---:|---:|---:|---:|---:|"]
        for stem, n, c, s in table:
            lines.append(f"| {stem} | {n} | {c['rule']} | {c['derive']} | {c['passage']} | "
                         f"{c['unaccounted']} | {s:g} |")
        if problems:
            lines += ["", "Unaccounted:", *[f"- {p}" for p in problems]]
        sections["extract"] = "\n".join(lines) + "\n\n"
    if derive_results is not None:
        by_file: dict[str, list[int]] = {}
        for r in derive_results:
            acc = by_file.setdefault(r["row"]["file"], [0, 0])
            acc[0 if r["status"] == "accepted" else 1] += 1
        lines = ["| file | accepted | rejected |", "|---|---:|---:|"]
        lines += [f"| {k} | {a} | {b} |" for k, (a, b) in sorted(by_file.items())]
        sections["derive"] = "\n".join(lines) + "\n\n"
    body = "# Prep step 1 report\n\n" + "".join(f"## {k}\n{v}" for k, v in sections.items())
    path.write_text(body, encoding="utf-8")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("stage", choices=["extract", "derive", "generate", "render", "all"])
    ap.add_argument("--run", default="default", help="run name (output folder)")
    ap.add_argument("--out", help="output folder (default ~/oqup/prep/<run>)")
    ap.add_argument("--only", help="comma-separated file stems to process")
    ap.add_argument("--model", help="served model name (derive)")
    ap.add_argument("--family", help=f"model family override: {sorted(FAMILIES)}")
    ap.add_argument("--server", default=os.environ.get("OMLX_SERVER", "http://127.0.0.1:8000"))
    ap.add_argument("--api-key", default=os.environ.get("OMLX_API_KEY"))
    ap.add_argument("--concurrency", type=int, default=4)
    ap.add_argument("--temperature", type=float, default=0.3)
    ap.add_argument("--max-attempts", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=300)
    ap.add_argument("--limit", type=int, help="derive at most N blocks (pilot)")
    ap.add_argument("--dry-run", action="store_true", help="derive: print the first request, send nothing")
    g = ap.add_argument_group("generate / render")
    g.add_argument("--budget-tokens", type=int, default=1_000_000,
                   help="stop generating once this many tokens were produced (thinking included)")
    g.add_argument("--effort-mix", default="max=70,medium=15,low=15")
    g.add_argument("--samples-per-prompt", type=float, default=1.5,
                   help="average answers per prompt, scaled by the file's manifest share")
    g.add_argument("--max-samples", type=int, default=3)
    g.add_argument("--max-tokens", type=int, default=16384, help="per answer")
    g.add_argument("--seed", type=int, default=0)
    g.add_argument("--pilot", type=int, default=20, help="answers before the time estimate")
    g.add_argument("--log-every", type=int, default=25)
    g.add_argument("--source", help="render: source model dir (tokenizer + chat template)")
    g.add_argument("--bundle", help="render: output path (default <out>/answers/<model>/bundle.txt)")
    args = ap.parse_args(argv)

    out = Path(args.out).expanduser() if args.out else Path.home() / "oqup" / "prep" / args.run
    only = {x.strip() for x in args.only.split(",")} if args.only else None

    rc = 0
    if args.stage in ("extract", "all"):
        rc = do_extract(out, only)
        if rc:
            return rc
    if args.stage in ("derive", "all"):
        if not args.model:
            ap.error("derive needs --model (the served model name)")
        rc = do_derive(out, args, only)
    if args.stage == "generate":
        if not args.model:
            ap.error("generate needs --model (the served model name)")
        if args.timeout == 300:
            args.timeout = 3600           # long thinking answers
        rc = do_generate(out, args)
    if args.stage == "render":
        if not args.model:
            ap.error("render needs --model (whose answers to render)")
        rc = do_render(out, args)
    return rc


if __name__ == "__main__":
    sys.exit(main())
