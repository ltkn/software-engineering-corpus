#!/usr/bin/env bash
# count_tokens.sh — measure the corpus with the pinned tokenizer.
#
# Usage: scripts/count_tokens.sh <path-to-model.gguf> [--update-manifest]
#
# Runs llama-tokenize over all calibration and eval files, prints a report,
# and optionally overwrites manifest.json's token fields, bundle estimate, and
# tokenizer pin. Blocks are split on the dedicated `---` delimiter.
set -euo pipefail

MODEL="${1:?usage: count_tokens.sh <model.gguf> [--update-manifest]}"
UPDATE_MANIFEST="${2:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

LLAMA_BIN="${LLAMA_BIN:-llama-tokenize}"
if ! command -v "$LLAMA_BIN" >/dev/null 2>&1; then
    echo "llama-tokenize not found on PATH; set LLAMA_BIN=/path/to/llama-tokenize" >&2
    exit 1
fi

count_tokens() {
    # llama-tokenize -m MODEL --ids prints the id list on stdout
    "$LLAMA_BIN" -m "$MODEL" --ids "$1" 2>/dev/null | wc -w
}

printf "%-40s %8s %10s\n" "file" "blocks" "tokens"
total=0
for f in "$ROOT"/calibration/*.txt; do
    base="$(basename "$f")"
    blocks=$(grep -c '^---$' "$f" || true); blocks=$((blocks + 1))
    tok=$(count_tokens "$f")
    total=$((total + tok))
    printf "%-40s %8d %10d\n" "$base" "$blocks" "$tok"
done
echo "----------------------------------------"
printf "%-40s %8s %10d\n" "TOTAL" "" "$total"

eval_total=0
for f in "$ROOT"/eval/*.txt; do
    base="$(basename "$f")"
    tok=$(count_tokens "$f")
    eval_total=$((eval_total + tok))
    printf "%-40s %8s %10d\n" "eval/$base" "" "$tok"
done
echo "eval total: $eval_total"

if [ "$UPDATE_MANIFEST" = "--update-manifest" ]; then
    export MODEL LLAMA_BIN
    python3 - "$ROOT" <<'PY'
import json, os, subprocess, sys
root, model = sys.argv[1], os.environ["MODEL"]
bin_ = os.environ["LLAMA_BIN"]
path = os.path.join(root, "manifest.json")
manifest = json.load(open(path))
total = 0
for entry in manifest["files"]:
    f = os.path.join(root, "calibration", entry["id"] + ".txt")
    ids = subprocess.check_output([bin_, "-m", model, "--ids", f],
                                  stderr=subprocess.DEVNULL, text=True)
    tok = len(ids.split())
    entry["tokens"] = f"measured {tok}"
    total += tok
manifest["bundle"]["unweighted_estimate"] = f"~{round(total/1000)}k measured"
manifest["tokenizer"]["name"] = os.path.basename(model).split(".gguf")[0]
manifest["tokenizer"]["model_path"] = model
manifest["tokenizer"]["command"] = f"llama-tokenize -m {model} --ids"
manifest["tokenizer"]["as_of"] = __import__("datetime").date.today().isoformat()

# stamp eval assets: sha256 + measured tokens + filename version
import hashlib, glob, re, datetime
evals = []
for f in sorted(glob.glob(os.path.join(root, "eval", "*.txt"))):
    tok = len(__import__("subprocess").check_output(
        [bin_, "-m", model, "--ids", f], stderr=__import__("subprocess").DEVNULL, text=True).split())
    sha = hashlib.sha256(open(f, "rb").read()).hexdigest()[:16]
    first = open(f, encoding="utf-8").readline()
    m = re.match(r"#\s*(\S+)\s+v([\d-]+)", first)
    name, ver = (m.group(1), m.group(2)) if m else (os.path.basename(f), "")
    evals.append({"name": name, "version": ver, "path": os.path.relpath(f, root), "sha256_16": sha, "tokens_measured": tok})
manifest["eval"] = evals
with open(path, "w") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
print(f"manifest updated: {total} tokens, eval assets stamped: {len(evals)}")
PY
fi
