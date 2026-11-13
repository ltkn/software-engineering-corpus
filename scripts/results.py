#!/usr/bin/env python3
"""results.py — every oQ-T run's scores in one place.

  collect      write <run>/result.json at the end of a pipeline run: model,
               variant, level, size, settings, M3 per slice, PPL, agent eval,
               stage durations
  table        all runs side by side (scripts/oqt_pipeline.sh results), plus
               quants scored by hand (any ~/oqup/m3-*.json without a run)
  vs-previous  this run against the previous run of the same model, variant
               and level; flags a regression
  agent-eval   the quant's agent sessions against the generator's, task by task

What is comparable: heldout-written-se is the same text in every run, so its
KL and top-1 compare across runs and models of the same family. The
heldout-oqt-* slices are each run's own held-out conversations: they differ
from run to run, so compare them only between quants scored on the same run.

Standard library only.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
import time
from pathlib import Path

WRITTEN = "heldout-written-se"
# Regression thresholds against the previous run of the same model and level.
KL_WORSE = 0.10          # relative
TOP1_WORSE = 0.01        # absolute
AGENT_WORSE = 0.10       # absolute solve rate; about the noise of 56 sessions


def read_json(p: Path) -> dict | None:
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def read_jsonl(p: Path) -> list[dict]:
    try:
        return [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()]
    except OSError:
        return []


def dir_gb(d: Path) -> float | None:
    try:
        return round(sum(f.stat().st_size for f in d.iterdir() if f.is_file()) / 1e9, 1)
    except OSError:
        return None


# ------------------------------------------------------------------ agent eval
def solved_by_task(answers_dir: Path) -> tuple[dict, int]:
    """{task: [solved, kept sessions]} and the number of sessions that failed to run."""
    by: dict[str, list[int]] = {}
    for s in read_jsonl(answers_dir / "agent-sessions.jsonl"):
        t = by.setdefault(s["task"], [0, 0])
        t[0] += 1 if s.get("check_passed") else 0
        t[1] += 1
    summary = read_json(answers_dir / "agent.json") or {}
    return by, int(summary.get("failed_to_run") or 0)


def rate(pairs) -> tuple[int, int]:
    pairs = list(pairs)
    return sum(p[0] for p in pairs), sum(p[1] for p in pairs)


def pct(a: int, b: int) -> str:
    return f"{a}/{b} ({a / b:.0%})" if b else "-"


def cmd_agent_eval(a) -> int:
    gen, gen_failed = solved_by_task(Path(a.generator))
    q, q_failed = solved_by_task(Path(a.quant))
    if not q:
        print(f"no quant sessions in {a.quant}", file=sys.stderr)
        return 1
    render = read_json(Path(a.render)) if a.render else None
    held = set(((render or {}).get("heldout") or {}).get("agent", {}).get("units") or [])
    tasks = sorted(set(gen) | set(q))
    gs, gn = rate(gen.get(t, (0, 0)) for t in tasks)
    qs, qn = rate(q.get(t, (0, 0)) for t in tasks)
    out = {"quant": {"solved": qs, "sessions": qn, "failed_to_run": q_failed, "by_task": q},
           "generator": {"solved": gs, "sessions": gn, "failed_to_run": gen_failed, "by_task": gen},
           "heldout_tasks": sorted(held)}
    print(f"quant solved {pct(qs, qn)}, generator {pct(gs, gn)} "
          f"({len(tasks)} tasks; sessions that failed to run: quant {q_failed}, generator {gen_failed})")
    if held:
        hq, hqn = rate(q.get(t, (0, 0)) for t in held)
        hg, hgn = rate(gen.get(t, (0, 0)) for t in held)
        out["heldout"] = {"quant": [hq, hqn], "generator": [hg, hgn]}
        print(f"held-out tasks ({', '.join(sorted(held))}): quant {pct(hq, hqn)}, generator {pct(hg, hgn)}")
    lost = [t for t in tasks if t in gen and t in q and q[t][1] and gen[t][1]
            and q[t][0] / q[t][1] < gen[t][0] / gen[t][1]]
    won = [t for t in tasks if t in gen and t in q and q[t][1] and gen[t][1]
           and q[t][0] / q[t][1] > gen[t][0] / gen[t][1]]
    fmt = lambda t: f"{t} {gen[t][0]}/{gen[t][1]}->{q[t][0]}/{q[t][1]}"
    if lost:
        print("worse on: " + ", ".join(map(fmt, lost)))
    if won:
        print("better on: " + ", ".join(map(fmt, won)))
    print(f"with {qn} sessions a difference under about {AGENT_WORSE:.0%} is noise")
    if a.json:
        Path(a.json).write_text(json.dumps(out, indent=1), encoding="utf-8")
    return 0


# --------------------------------------------------------------------- collect
def m3_row(m3: dict) -> dict:
    o = m3.get("overall") or {}
    sl = m3.get("slices") or {}
    own = {k: v for k, v in sl.items() if k.startswith("heldout-oqt-")}
    tok = sum(v.get("tokens", 0) for v in own.values())
    row = {"kl": o.get("kl"), "top1": o.get("top1"),
           "route": o.get("routing_mass_shift"), "flips": o.get("routing_flip_rate"),
           "slices": sl}
    if WRITTEN in sl:
        row["written_kl"], row["written_top1"] = sl[WRITTEN]["kl"], sl[WRITTEN]["top1"]
    if own and tok:
        row["own_kl"] = sum(v["kl"] * v["tokens"] for v in own.values()) / tok
        row["own_top1"] = sum(v["top1"] * v["tokens"] for v in own.values()) / tok
    return row


def ppl_row(ppl: dict) -> dict:
    p = ppl.get("pooled") or {}
    out = {}
    if p.get("tokens"):
        out["ppl"] = math.exp(p["nll"] / p["tokens"])
    for f in ppl.get("files") or []:
        name = Path(str(f.get("file") or f.get("path") or f.get("name") or "")).stem
        if name and f.get("tokens") and f.get("nll") is not None:
            out.setdefault("files", {})[name] = math.exp(f["nll"] / f["tokens"])
    return out


def read_settings(run: Path) -> dict:
    s = {}
    try:
        for line in (run / "settings.env").read_text().splitlines():
            k, _, v = line.partition("=")
            if k:
                s[k] = v
    except OSError:
        pass
    return s


def cmd_collect(a) -> int:
    run, quant, oqup = Path(a.run), Path(a.quant), Path(a.oqup)
    stem = f"{quant.name.rsplit('-oQ', 1)[0]}-oQ{a.level}-{run.name}"
    stages = {}
    try:
        for line in (run / "state.tsv").read_text().splitlines():
            parts = line.split("\t")
            if len(parts) == 4:
                stages[parts[0]] = int(parts[3])
    except OSError:
        pass
    build = read_json(quant / "build.json") or {}
    res = {"run": run.name, "model": a.model, "variant": a.variant or "", "level": int(a.level),
           "quant": str(quant), "gb": dir_gb(quant), "created": build.get("created") or time.strftime("%Y-%m-%dT%H:%M:%S%z"),
           "settings": read_settings(run), "stage_seconds": stages}
    m3 = read_json(oqup / f"m3-{stem}-oqt.json")
    if m3:
        res["m3"] = m3_row(m3)
    ppl = read_json(oqup / f"ppl-{stem}-oqt.json")
    if ppl:
        res["ppl"] = ppl_row(ppl)
    ae = read_json(run / "agent-eval.json")
    if ae:
        res["agent_eval"] = {k: ae[k] for k in ("quant", "generator", "heldout") if k in ae}
        for side in ("quant", "generator"):
            res["agent_eval"][side] = {k: v for k, v in ae[side].items() if k != "by_task"}
    (run / "result.json").write_text(json.dumps(res, indent=1), encoding="utf-8")
    print(run / "result.json")
    return 0


# ----------------------------------------------------------------------- table
def all_results(oqup: Path) -> list[dict]:
    rows = []
    seen = set()
    for p in sorted((oqup / "runs").glob("*/result.json")):
        r = read_json(p)
        if r:
            rows.append(r)
            seen.add(Path(r["quant"]).name)
    # Quants scored outside the pipeline (or before result.json existed).
    for p in sorted(oqup.glob("m3-*.json")):
        m3 = read_json(p)
        if not m3 or "model" not in m3:
            continue
        name = Path(m3["model"]).name
        if name in seen:
            continue
        seen.add(name)
        lvl = re.search(r"-oQ(\d)", name)
        rows.append({"run": "", "model": "", "variant": "", "level": int(lvl.group(1)) if lvl else 0,
                     "quant": m3["model"], "gb": dir_gb(Path(m3["model"])),
                     "created": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(p.stat().st_mtime)),
                     "m3": m3_row(m3)})
    return rows


def fmt(v, spec: str) -> str:
    width = int(re.match(r"\d*", spec).group() or 0)
    return "-".rjust(width) if v is None else format(v, spec)


def agent_cell(r: dict) -> str:
    ae = r.get("agent_eval") or {}
    q, g = ae.get("quant"), ae.get("generator")
    if not q:
        return "-"
    return f"{q['solved']}/{q['sessions']} vs {g['solved']}/{g['sessions']}" if g else f"{q['solved']}/{q['sessions']}"


def cmd_table(a) -> int:
    rows = all_results(Path(a.oqup).expanduser())
    if not rows:
        print("no scored runs yet")
        return 0
    rows.sort(key=lambda r: (Path(r["quant"]).name.rsplit("-oQ", 1)[0], r.get("level", 0), r.get("created", "")))
    head = (f"{'quant':44s} {'GB':>5s} {'KL wse':>7s} {'top1 wse':>8s} {'KL own':>7s} {'top1 own':>8s} "
            f"{'route':>6s} {'flips':>6s} {'agent (quant vs gen)':>20s}")
    print(head)
    print("-" * len(head))
    for r in rows:
        m = r.get("m3") or {}
        print(f"{Path(r['quant']).name[:44]:44s} {fmt(r.get('gb'), '5.1f')} {fmt(m.get('written_kl'), '7.4f')} "
              f"{fmt(m.get('written_top1'), '8.1%')} {fmt(m.get('own_kl'), '7.4f')} {fmt(m.get('own_top1'), '8.1%')} "
              f"{fmt(m.get('route'), '6.3f')} {fmt(m.get('flips'), '6.1%')} {agent_cell(r):>20s}")
    print("\nwse: heldout-written-se, the same text for every run (compare freely across runs).\n"
          "own: the run's own held-out conversations (differ per run; compare quants of one run).\n"
          "KL lower is better; top1 higher is better; route/flips: routing drift vs the BF16 model.")
    return 0


def cmd_vs_previous(a) -> int:
    run = Path(a.run)
    me = read_json(run / "result.json")
    if not me or not me.get("m3"):
        return 0
    same = [r for r in all_results(Path(a.oqup)) if r.get("run") and r["run"] != me["run"]
            and r.get("model") == me["model"] and r.get("variant", "") == me.get("variant", "")
            and r.get("level") == me["level"] and r.get("created", "") < me.get("created", "")
            and (r.get("m3") or {}).get("written_kl") is not None]
    if not same:
        print("vs previous: first scored run of this model and level")
        return 0
    prev = max(same, key=lambda r: r["created"])
    m, p = me["m3"], prev["m3"]
    worse = []
    if m.get("written_kl") is not None:
        if m["written_kl"] > p["written_kl"] * (1 + KL_WORSE):
            worse.append(f"KL {p['written_kl']:.4f} -> {m['written_kl']:.4f}")
        if m["written_top1"] < p["written_top1"] - TOP1_WORSE:
            worse.append(f"top-1 {p['written_top1']:.1%} -> {m['written_top1']:.1%}")
    qa, pa = (me.get("agent_eval") or {}).get("quant"), (prev.get("agent_eval") or {}).get("quant")
    if qa and pa and qa["sessions"] and pa["sessions"] \
            and qa["solved"] / qa["sessions"] < pa["solved"] / pa["sessions"] - AGENT_WORSE:
        worse.append(f"agent {pct(pa['solved'], pa['sessions'])} -> {pct(qa['solved'], qa['sessions'])}")
    line = (f"vs {prev['run']}: KL wse {p['written_kl']:.4f} -> {m.get('written_kl', float('nan')):.4f}, "
            f"top-1 wse {p['written_top1']:.1%} -> {m.get('written_top1', float('nan')):.1%}")
    print(line)
    print(("WARNING: worse than run " + prev["run"] + ": " + "; ".join(worse)) if worse
          else "no regression against run " + prev["run"])
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("agent-eval")
    e.add_argument("--generator", required=True, help="answers dir with the generator's agent-sessions.jsonl")
    e.add_argument("--quant", required=True, help="answers dir with the quant's agent-sessions.jsonl")
    e.add_argument("--render", help="render summary JSON (for the held-out task ids)")
    e.add_argument("--json")
    c = sub.add_parser("collect")
    c.add_argument("--run", required=True)
    c.add_argument("--quant", required=True)
    c.add_argument("--level", required=True)
    c.add_argument("--model", required=True)
    c.add_argument("--variant", default="")
    c.add_argument("--oqup", required=True)
    t = sub.add_parser("table")
    t.add_argument("--oqup", default=str(Path.home() / "oqup"))
    v = sub.add_parser("vs-previous")
    v.add_argument("--oqup", required=True)
    v.add_argument("--run", required=True)
    a = ap.parse_args(argv)
    return {"agent-eval": cmd_agent_eval, "collect": cmd_collect, "table": cmd_table,
            "vs-previous": cmd_vs_previous}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
