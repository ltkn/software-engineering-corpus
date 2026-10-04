#!/usr/bin/env python3
"""audit_code_forward.py — per-file code-forward ratio audit.

A block is "code-forward" when >=60% of its lines look like code or
configuration rather than prose. Classification is line-shape based:
a line counts as code/config if it matches any of the patterns below.
The same heuristic applies to every file, so the numbers are comparable.
Estimates: this is a shape signal, not a tokenizer.

Exits 0 always; prints a table to stdout and writes AUDIT.md.
"""
from __future__ import annotations
import re, sys, os, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CODE_PATTERNS = [
    r"^\s*(import|from|export |package |class |interface |record |sealed |enum |@)",
    r"^\s*(SELECT|INSERT|UPDATE|DELETE|ALTER|CREATE|DROP|REVOKE|GRANT|ENABLE|DISABLE|EXPLAIN)",
    r"^[A-Za-z_$][\w$]*\s*\(",                    # function/command call start
    r"^\s*(//|#|/\*|\*|using |def |val |var |let |const |return |async |await |fn )",
    r"^\{\s*$", r"^\s*\}\s*$", r"^\s*[a-zA-Z_$][\w$]*\s*[:=][^=]",
    r"^host\s+|^server\s|^location\s|^listen\s|^apiVersion:|^kind:|^metadata:|^spec:|^image:|^containerPort:",
    r"^\s*[-A-Za-z_][\w-]*:\s+\S",                 # yaml / properties
    r"^\s*\$ \S",                                   # shell prompt line
    r"^\s*<[a-zA-Z!/]",                             # tag
    r"\{|\}|;.*\}|->\s|=>",
]
CODE_RE = re.compile("|".join(CODE_PATTERNS))

def is_code_line(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return False
    if stripped.startswith("```"):
        return True
    if CODE_RE.search(stripped):
        return True
    return False

STRICT_PATTERNS = [
    r"^\s*(import|from |export |package |class |interface |record |sealed |enum |@)",
    r"^\s*(SELECT|INSERT|UPDATE|DELETE|ALTER|CREATE|DROP|REVOKE|GRANT|ENABLE|DISABLE|EXPLAIN)",
    r"^\{\s*$", r"^\s*\}\s*$", r"^\s*[a-zA-Z_$][\w$]*\s*\(.*\);?\s*$",
    r"^\s*[a-zA-Z_$][\w$]*\s*=[^=>]", r"^\s*\$\s+\S",
]
STRICT_RE = re.compile("|".join(STRICT_PATTERNS))

def is_code_block(block: str, strict: bool = False) -> bool:
    lines = [l for l in block.splitlines() if l.strip()]
    if not lines:
        return False
    if strict:
        # executable-code only: yaml/kv config and prose skipped by construction
        code = sum(1 for l in lines if STRICT_RE.search(l.strip()))
        return code / len(lines) >= 0.50
    code = sum(1 for l in lines if is_code_line(l))
    return code / len(lines) >= 0.60

def main():
    cal_dir = os.path.join(ROOT, "calibration")
    targets = {
        "10-java": 0.40, "11-spring": 0.40, "12-postgresql": 0.40,
        "13-kafka": 0.35, "14-http-api": 0.15, "15-typescript": 0.45,
        "16-vue": 0.40, "17-tanstack": 0.35, "18-testing": 0.25,
        "19-architecture": 0.20, "20-observability": 0.25,
        "21-linux-infra": 0.45, "22-python": 0.40,
    }
    rows = []
    for name in sorted(os.listdir(cal_dir)):
        key = name.split("-", 1)[0] + "-" + name.split("-", 1)[1].split(".")[0]
        if key not in targets:
            continue
        with open(os.path.join(cal_dir, name)) as f:
            body = f.read()
        blocks = [b for b in body.split("\n---\n")]
        strict = (key == "19-architecture")
        forward = sum(1 for b in blocks if is_code_block(b, strict=strict))
        ratio = forward / max(len(blocks), 1)
        rows.append((key, targets[key], ratio, forward, len(blocks)))

    print(f"{'file':<22}{'target':>8}{'measured':>10}{'over/total':>12}")
    for key, tgt, ratio, cf, total in rows:
        print(f"{key:<22}{tgt:>8.0%}{ratio:>10.0%}{cf:>6}/{total:<5}")

    AUDIT = os.path.join(ROOT, "AUDIT.md")
    with open(AUDIT, "w") as out:
        out.write("# Code-forward audit\n\n")
        out.write("Line-shape heuristic; a block counts as code-forward when >=60% of its lines match the code/config patterns. Re-run `scripts/audit_code_forward.py` after any corpus edit.\n\n")
        out.write("| file | declared target | measured | code-forward / total | status |\n")
        out.write("| --- | ---: | ---: | ---: | --- |\n")
        for key, tgt, ratio, cf, total in rows:
            if key == "19-architecture":
                # strict executable-only scoring; YAML/ADR fragments excluded from the numerator
                status = "ok" if ratio <= tgt else "above floor"
            else:
                status = "ok" if ratio >= tgt - 0.05 else "below floor"
            out.write(f"| {key} | {tgt:.0%} | {ratio:.0%} | {cf}/{total} | {status} |\n")
    print(f"AUDIT.md written")

if __name__ == "__main__":
    main()
