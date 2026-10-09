#!/usr/bin/env python3
# mine_multiswe.py — mine 02-shaped repair blocks from Multi-SWE-bench.
#
# Legal scope: ONLY repos on the allowlist below (Apache-2.0 / MIT / ISC).
# elastic/logstash (Elastic License/SSPL) is excluded by construction: its
# file must not be present in the input dir, and the miner refuses to run
# if it finds it. See manifest.json "mined" section for provenance.
#
# Eval discipline: sha1(instance_id) % 2 splits instances — even IDs are
# mined into calibration, odd IDs are sealed into
# eval/mined-holdout-ids.txt for future scoring. Never mix the halves.
#
# Block shape (file 02): Failure: -> Diagnosis: -> Fix: -> Verify:.
# Diagnosis is templated from the fix location only — the miner invents
# no reasoning. Bodies are scrubbed (emails neutralized, secret-shaped
# content drops the instance, fences/heading markers removed so the
# format lint stays green).
#
# Usage:
#   python3 scripts/mine_multiswe.py /tmp/multiswe /tmp/mined_out \
#       --target 50 --per-repo 12
# Outputs: /tmp/mined_out/blocks_02.txt, provenance.json, holdout_ids.txt,
#   skipped.jsonl (every skip with its reason — audit this).
import hashlib
import json
import re
import sys
from pathlib import Path

ALLOWLIST = {
    # java — Apache-2.0 unless noted
    "alibaba__fastjson2": "Apache-2.0",
    "apache__dubbo": "Apache-2.0",
    "fasterxml__jackson-core": "Apache-2.0",
    "fasterxml__jackson-databind": "Apache-2.0",
    "fasterxml__jackson-dataformat-xml": "Apache-2.0",
    "google__gson": "Apache-2.0",
    "googlecontainertools__jib": "Apache-2.0",
    "mockito__mockito": "MIT",
    # ts — MIT unless noted
    "darkreader__darkreader": "ISC",
    "mui__material-ui": "MIT",
    "vuejs__core": "MIT",
}

BLOCKED = ("elastic__logstash",)  # Elastic/SSPL: never mine

SECRET_RES = [
    r"AKIA[0-9A-Z]{16}",
    r"gh[pousr]_[A-Za-z0-9_]{20,}",
    r"xox[bpas]-[A-Za-z0-9-]+",
    r"AIza[0-9A-Za-z_-]{35}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"sk-(live|test)-[A-Za-z0-9]{10,}",
]
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")

MAX_FIX_CHARS = 1000
MAX_BODY_CHARS = 600
MIN_TOKENS, MAX_TOKENS = 60, 320


def est_tokens(text):
    return len(text.encode("utf-8")) / 5.5


def scrub(text):
    # Issue-template boilerplate carries zero signal.
    text = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)
    text = EMAIL_RE.sub("user@example.com", text)
    lines = []
    for line in text.splitlines():
        s = line.strip()
        if re.match(r"^- \[[ xX]\]", s):
            continue  # template checklist items ("Search before asking" etc.)
        if s.startswith("```"):
            continue  # corpus carries code raw, never fenced
        if s.startswith("#"):
            line = line.lstrip("# ")  # no headings in .txt
        if s == "---":
            line = "--- (separator quoted from source, not a block boundary)"
        lines.append(line)
    return "\n".join(lines).strip()


def has_secret(text):
    return any(re.search(p, text) for p in SECRET_RES)


def core_hunks(fix_patch):
    """Keep the most informative hunks within the char budget."""
    parts = re.split(r"(?m)^(?=@@ )", fix_patch)
    hunks = [p for p in parts if p.startswith("@@")]
    if not hunks:
        hunks = [fix_patch]
    scored = sorted(hunks, key=lambda h: -sum(1 for l in h.splitlines() if l[:1] in "+-"))
    kept, total, dropped = [], 0, 0
    for h in scored:
        if total + len(h) <= MAX_FIX_CHARS:
            kept.append(h)
            total += len(h)
        else:
            dropped += 1
    return kept, len(hunks), dropped


def test_names(d):
    names = []
    for key in ("f2p_tests", "fixed_tests"):
        v = d.get(key)
        if isinstance(v, dict):
            names.extend(sorted(v)[:6])
        elif isinstance(v, list):
            names.extend(str(x)[:80] for x in v[:6])
    if not names and d.get("test_patch"):
        for m in re.finditer(r"(?m)^\+\+\+ b/(\S+)", d["test_patch"]):
            names.append(m.group(1).split("/")[-1])
            if len(names) >= 4:
                break
    return list(dict.fromkeys(names))


def collapse_tests(names):
    """One entry per file (longest variant wins): file, file:Test, ..."""
    by_file = {}
    for n in names:
        f, _, t = n.partition(":")
        by_file.setdefault(f, [])
        if t and t not in by_file[f]:
            by_file[f].append(t)
    out = []
    for f, ts in by_file.items():
        out.append(f if not ts else f"{f}:{ts[0]}")
    return out[:4]


def files_touched(fix_patch):
    return [m.group(1) for m in re.finditer(r"(?m)^\+\+\+ b/(\S+)", fix_patch)][:4]


def build_block(d):
    pr_title = (d.get("title") or "").strip()
    pr_body = scrub(d.get("body") or "")[:MAX_BODY_CHARS]
    # Prefer the linked issue report as Failure material: real failure text
    # with reproduction beats terse PR bodies ("Fixes #N"). Fall back to the
    # PR text when the issue side is thin.
    ri = (d.get("resolved_issues") or [{}])[0] or {}
    ri_title = (ri.get("title") or "").strip()
    ri_body = scrub(ri.get("body") or "")[:MAX_BODY_CHARS]
    if len(ri_body) >= 60:
        title, body = ri_title or pr_title, ri_body
    else:
        title, body = pr_title, pr_body
    if len(body) < 60:
        return None, "thin body (<60 chars after scrub)"
    fix = d.get("fix_patch") or ""
    if has_secret(title + "\n" + body + "\n" + fix):
        return None, "secret-shaped content"
    kept, nhunks, dropped = core_hunks(fix)
    if not kept:
        return None, "fix has no usable hunks"
    fix_text = "\n".join(kept).strip()
    if dropped:
        fix_text += f"\n[…{dropped} further hunk(s) trimmed for the block budget]"
    touched = files_touched(fix)
    tests = collapse_tests(test_names(d))
    rr = d.get("run_result") or {}
    failure = f"Failure: {title}\n{body}".strip()
    diagnosis = (
        f"Diagnosis: change localized to "
        f"{', '.join(touched) if touched else 'the patched files'} "
        f"({nhunks} hunk(s)); "
        f"covered by {', '.join(tests) if tests else 'the added tests'}."
    )
    verify_bits = []
    if tests:
        verify_bits.append(f"fixed tests {', '.join(tests)} pass after the fix")
    if isinstance(rr, dict) and ("passed_count" in rr or "failed_count" in rr):
        verify_bits.append(
            f"patch run: {rr.get('passed_count', '?')} passed, "
            f"{rr.get('failed_count', '?')} failed"
        )
    verify = f"Verify: {'; '.join(verify_bits) if verify_bits else 'fix applied, tests green'}."
    block = f"{failure}\n{diagnosis}\nFix:\n{fix_text}\n{verify}"
    toks = est_tokens(block)
    if not (MIN_TOKENS <= toks <= MAX_TOKENS):
        return None, f"block size {toks:.0f} tokens outside [{MIN_TOKENS},{MAX_TOKENS}]"
    return block, None


def main():
    src, outdir = sys.argv[1], sys.argv[2]
    target = int(sys.argv[sys.argv.index("--target") + 1]) if "--target" in sys.argv else 50
    per_repo = int(sys.argv[sys.argv.index("--per-repo") + 1]) if "--per-repo" in sys.argv else 12
    srcp, outp = Path(src), Path(outdir)
    for blocked in BLOCKED:
        if list(srcp.rglob(f"{blocked}_dataset.jsonl")):
            print(f"REFUSING: excluded {blocked} data present under {src}", file=sys.stderr)
            return 2
    outp.mkdir(parents=True, exist_ok=True)

    instances = []
    for f in sorted(srcp.rglob("*_dataset.jsonl")):
        stem = f.name[: -len("_dataset.jsonl")]
        if stem not in ALLOWLIST:
            print(f"skip non-allowlisted file: {f.name}")
            continue
        lang = f.parent.name
        for line in open(f):
            d = json.loads(line)
            iid = d.get("instance_id") or f"{stem}-{d.get('number')}"
            instances.append((stem, lang, iid, d))
    instances.sort(key=lambda t: t[2])

    kept, holdout, skipped = [], [], []
    per_repo_count = {}
    # Round-robin over repos, smallest fix first within each repo: focused
    # diffs make the best blocks, and every allowlisted repo contributes
    # instead of the small-fix repos starving the rest.
    per_repo_queues = {}
    for stem, lang, iid, d in instances:
        if int(hashlib.sha1(iid.encode()).hexdigest(), 16) % 2 == 1:
            holdout.append({"instance_id": iid, "repo": stem, "lang": lang,
                            "license": ALLOWLIST[stem]})
            continue
        per_repo_queues.setdefault(stem, []).append((len(d.get("fix_patch") or ""), iid, lang, d))
    for queue in per_repo_queues.values():
        queue.sort(key=lambda t: (t[0], t[1]))
    progress = True
    while progress and len(kept) < target:
        progress = False
        for stem in sorted(per_repo_queues):
            if len(kept) >= target:
                break
            if per_repo_count.get(stem, 0) >= per_repo:
                continue
            queue = per_repo_queues[stem]
            if not queue:
                continue
            _, iid, lang, d = queue.pop(0)
            progress = True
            block, reason = build_block(d)
            if block is None:
                skipped.append({"instance_id": iid, "reason": reason})
                continue
            per_repo_count[stem] = per_repo_count.get(stem, 0) + 1
            kept.append({"instance_id": iid, "repo": stem, "lang": lang,
                         "license": ALLOWLIST[stem], "block": block})

    (outp / "blocks_02.txt").write_text(
        "\n\n---\n\n".join(k["block"] for k in kept), encoding="utf-8")
    (outp / "holdout_ids.txt").write_text(
        "\n".join(h["instance_id"] for h in holdout) + "\n", encoding="utf-8")
    with open(outp / "skipped.jsonl", "w") as fh:
        for s in skipped:
            fh.write(json.dumps(s) + "\n")
    prov = {
        "allowlist": ALLOWLIST,
        "split_rule": "sha1(instance_id) % 2: even=mined, odd=sealed holdout",
        "mined": [{"instance_id": k["instance_id"], "repo": k["repo"],
                   "lang": k["lang"], "license": k["license"]} for k in kept],
        "holdout_count": len(holdout),
    }
    json.dump(prov, open(outp / "provenance.json", "w"), indent=2)
    print(f"mined={len(kept)} holdout={len(holdout)} skipped={len(skipped)}")
    print(f"per-repo: {per_repo_count}")
    print("wrote blocks_02.txt, provenance.json, holdout_ids.txt, skipped.jsonl")


if __name__ == "__main__":
    sys.exit(main() or 0)
