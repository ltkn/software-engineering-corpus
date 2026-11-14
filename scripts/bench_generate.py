#!/usr/bin/env python3
"""bench_generate.py — how fast the generator writes, and which MTP setting is fastest.

The generate stage is one request at a time, so its speed is the model's decode
speed. oMLX can speed decoding up with MTP (the model's own multi-token
prediction head drafts tokens that the model then checks): same answers, fewer
steps. Whether it pays, and how many tokens to draft, depends on the model and
the Mac, so this measures it.

  bench     time the same requests under each MTP setting, print a table, restore
            the model's own setting, and recommend one
  show      print the model's MTP setting on the server (one line)
  apply     set it: off, auto (oMLX picks the draft depth) or a fixed depth 1-8

  python3 scripts/bench_generate.py bench --server http://127.0.0.1:8765 --model <id>

Uses the oMLX admin API with the main API key (OMLX_API_KEY) when the server
requires one. Changing the setting makes oMLX reload the model (a minute or two
for a large one). Standard library only.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Coding requests of the kind the pipeline generates, answered with thinking on.
PROMPTS = [
    "Write a Python function that merges overlapping time intervals given as (start, end) "
    "tuples, explain the edge cases, and add pytest tests.",
    "Our Spring Boot service returns 500 when a JPA entity is not found. Show how to map "
    "that to a 404 with RFC 9457 problem details, with a test.",
    "In Rust, implement a fixed-capacity ring buffer with push, pop and iteration without "
    "unsafe code, and explain the ownership choices.",
]


class AdminError(RuntimeError):
    pass


def request(server: str, key: str | None, method: str, path: str, body=None, timeout=3600):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(server.rstrip("/") + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:300]
        if e.code in (401, 403) and path.startswith("/admin"):
            raise AdminError(f"the oMLX admin API refused the request ({e.code}): set OMLX_API_KEY "
                             "to the server's main API key") from None
        raise AdminError(f"{method} {path}: HTTP {e.code}: {detail}") from None


def model_entry(server, key, model) -> dict:
    data = request(server, key, "GET", "/admin/api/models", timeout=60)
    models = data.get("models", data) if isinstance(data, dict) else data
    for m in models or []:
        if m.get("id") == model:
            return m
    raise AdminError(f"the server does not list a model named {model}")


def current(server, key, model) -> dict:
    m = model_entry(server, key, model)
    s = m.get("settings") or {}
    return {"compatible": bool(m.get("mtp_compatible")), "reason": m.get("mtp_compatibility_reason"),
            "mtp_enabled": bool(s.get("mtp_enabled")), "mtp_fixed_depth": s.get("mtp_fixed_depth"),
            "mtp_adaptive_max_depth": s.get("mtp_adaptive_max_depth")}


def describe(c: dict) -> str:
    if not c.get("mtp_enabled"):
        return "off"
    if c.get("mtp_fixed_depth"):
        return str(c["mtp_fixed_depth"])
    return "auto"


def setting_for(name: str) -> dict:
    if name == "off":
        return {"mtp_enabled": False}
    if name == "auto":
        return {"mtp_enabled": True, "mtp_fixed_depth": None}
    depth = int(name)
    if not 1 <= depth <= 8:
        raise ValueError("an MTP depth is 1 to 8")
    return {"mtp_enabled": True, "mtp_fixed_depth": depth}


def apply(server, key, model, name: str) -> None:
    request(server, key, "PUT", f"/admin/api/models/{urllib.parse.quote(model, safe='')}/settings",
            setting_for(name), timeout=600)


def profile_requests(model: str, model_profile: str | None) -> dict:
    sys.path.insert(0, str(HERE))
    import prep_calibration as prep
    return prep.model_profile(model, model_profile)


def one(server, key, model, prof, prompt, max_tokens, seed) -> tuple[int, float]:
    payload = {"model": model, "messages": [{"role": "user", "content": prompt}],
               **prof["sampling"], "max_tokens": max_tokens, "seed": seed,
               "chat_template_kwargs": {**prof["thinking_on"], "reasoning_effort": prof["effort"]["medium"]}}
    t0 = time.time()
    body = request(server, key, "POST", "/v1/chat/completions", payload)
    secs = time.time() - t0
    tokens = int((body.get("usage") or {}).get("completion_tokens") or 0)
    return tokens, secs


def cmd_bench(a, key) -> int:
    prof = profile_requests(a.model, a.model_profile)
    before = current(a.server, key, a.model)
    names = [n.strip() for n in a.settings.split(",") if n.strip()]
    if not before["compatible"]:
        print(f"MTP is not available for {a.model}: {before['reason'] or 'no MTP head'}; "
              "measuring the plain speed only")
        names = ["off"]
    print(f"model {a.model}; its setting now: MTP {describe(before)}")
    print(f"{len(PROMPTS)} coding requests x up to {a.max_tokens} tokens, thinking on, per setting "
          "(the first setting also loads the model)\n")
    rows = []
    try:
        for name in names:
            apply(a.server, key, a.model, name)
            one(a.server, key, a.model, prof, "Say ok.", 8, 1)          # (re)load, not timed
            tok = secs = 0
            for i, p in enumerate(PROMPTS):
                t, s = one(a.server, key, a.model, prof, p, a.max_tokens, 1000 + i)
                tok, secs = tok + t, secs + s
            rate = tok / secs if secs else 0.0
            rows.append({"setting": name, "tokens": tok, "seconds": round(secs, 1), "tokens_per_second": round(rate, 2)})
            print(f"  MTP {name:5s}: {rate:6.1f} tokens/s  ({tok} tokens in {secs:.0f} s)", flush=True)
    finally:
        if before["compatible"]:
            try:   # exactly as it was, adaptive depth limit included
                request(a.server, key, "PUT", f"/admin/api/models/{urllib.parse.quote(a.model, safe='')}/settings",
                        {k: before[k] for k in ("mtp_enabled", "mtp_fixed_depth", "mtp_adaptive_max_depth")},
                        timeout=600)
            except AdminError as e:
                print(f"WARNING: could not restore MTP {describe(before)}: {e}", file=sys.stderr)
    if not rows:
        return 1
    base = next((r for r in rows if r["setting"] == "off"), rows[0])
    best = max(rows, key=lambda r: r["tokens_per_second"])
    print(f"\n{'MTP':6s} {'tokens/s':>9s} {'vs off':>7s}")
    for r in rows:
        x = r["tokens_per_second"] / base["tokens_per_second"] if base["tokens_per_second"] else 0
        print(f"{r['setting']:6s} {r['tokens_per_second']:9.1f} {x:6.2f}x" + ("   <- fastest" if r is best else ""))
    gain = best["tokens_per_second"] / base["tokens_per_second"] if base["tokens_per_second"] else 1
    if best["setting"] == describe(before):
        print(f"\nThe model's current setting (MTP {describe(before)}) is already the fastest: nothing to change.")
    elif gain < 1.05 and best["setting"] != "off":
        print(f"\nMTP gains under 5% here: keep it as it is (MTP {describe(before)}).")
    else:
        print(f"\nFastest: MTP {best['setting']}. Use it for a run with OQT_MTP={best['setting']} "
              f"(about {gain:.2f}x the speed without MTP). Answers are the same either way: MTP only "
              "changes how many tokens each step produces.")
    print(f"(restored the model's own setting: MTP {describe(before)})")
    if a.json:
        Path(a.json).write_text(json.dumps({"model": a.model, "before": describe(before), "rows": rows,
                                            "fastest": best["setting"]}, indent=1))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["bench", "show", "apply"])
    ap.add_argument("value", nargs="?", help="apply: off, auto or a depth 1-8")
    ap.add_argument("--server", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--model-profile")
    ap.add_argument("--settings", default="off,auto,2,3,4", help="bench: MTP settings to compare")
    ap.add_argument("--max-tokens", type=int, default=1024)
    ap.add_argument("--json")
    a = ap.parse_args(argv)
    key = os.environ.get("OMLX_API_KEY")
    try:
        if a.cmd == "show":
            c = current(a.server, key, a.model)
            print(f"MTP {describe(c)}" + ("" if c["compatible"] else f" (not available: {c['reason'] or 'no MTP head'})"))
            return 0
        if a.cmd == "apply":
            if not a.value:
                ap.error("apply needs off, auto or a depth")
            setting_for(a.value)
            apply(a.server, key, a.model, a.value)
            print(f"MTP {a.value}")
            return 0
        return cmd_bench(a, key)
    except (AdminError, ValueError, urllib.error.URLError) as e:
        print(f"bench: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
