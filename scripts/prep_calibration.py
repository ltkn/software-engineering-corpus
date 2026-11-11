#!/usr/bin/env python3
"""prep_calibration.py — turn the corpus into oQ-T calibration prompts.

Implements step 1 of PREP_PLAN.md (§2, §4 stages 1-3):

  extract   Split calibration/*.txt into blocks, classify every block with the
            per-file rule table below, and write the rule-made prompts.
            Exits non-zero if any block is unaccounted for.
  derive    For knowledge-card blocks (no question in them), ask the served
            model, thinking off, to write the request a developer would send.
            Each answer passes a leakage check; rejected drafts are retried.
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
    "qwen": {"thinking_off": {"enable_thinking": False}},
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
            cpath.write_text(json.dumps(rec, ensure_ascii=False, indent=1), encoding="utf-8")
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
    ap.add_argument("stage", choices=["extract", "derive", "all"])
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
    return rc


if __name__ == "__main__":
    sys.exit(main())
