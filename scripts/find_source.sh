# find_source.sh: pick the original BF16 Qwen3.8-Flash-Next checkpoint from the
# Hugging Face cache. Sourced by oqt_pipeline.sh and omlx_oqt.sh.
#
#   find_bf16_source <hub dir>   prints the snapshot dir, or explains on stderr and returns 1
#
# Only the official repo (models--Qwen--Qwen3.8-Flash-Next) is considered: fine-tunes
# from other organizations (an "Uncensored" variant, for example) are a different model
# and must never be the reference the quant is matched to. Pass SRC=<dir> to use one
# on purpose. Within the repo, the newest snapshot that is complete and unquantized
# wins: no quantization_config, and every shard named in the index is present.

OFFICIAL_SOURCE_REPO="models--Qwen--Qwen3.8-Flash-Next"

# <snapshot dir>: exit 0 when it is a complete, unquantized qwen4_exp checkpoint.
_source_is_complete_bf16() {
    python3 - "$1" <<'PY'
import json, os, sys
d = sys.argv[1]
try:
    cfg = json.load(open(os.path.join(d, "config.json")))
except (OSError, ValueError):
    sys.exit(1)
text = cfg.get("text_config") or cfg
if "qwen4_exp" not in (cfg.get("model_type"), text.get("model_type")):
    sys.exit(1)
if cfg.get("quantization_config") or cfg.get("quantization") or text.get("quantization_config"):
    sys.exit(1)
index = os.path.join(d, "model.safetensors.index.json")
if os.path.exists(index):
    shards = set(json.load(open(index))["weight_map"].values())
else:
    shards = {"model.safetensors"}
# os.path.exists follows the cache's symlinks, so a missing blob counts as missing.
sys.exit(0 if shards and all(os.path.exists(os.path.join(d, s)) for s in shards) else 1)
PY
}

find_bf16_source() {
    local hub="$1" repo="$1/$OFFICIAL_SOURCE_REPO" snap best="" other
    if [ -d "$repo/snapshots" ]; then
        for snap in "$repo"/snapshots/*/; do
            snap="${snap%/}"
            _source_is_complete_bf16 "$snap" || continue
            if [ -z "$best" ] || [ "$snap" -nt "$best" ]; then best="$snap"; fi
        done
    fi
    if [ -n "$best" ]; then
        printf '%s\n' "$best"
        return 0
    fi
    {
        if [ -d "$repo/snapshots" ]; then
            echo "$OFFICIAL_SOURCE_REPO is in $hub but no snapshot is complete and unquantized"
            echo "(a download may have stopped: run huggingface-cli download Qwen/Qwen3.8-Flash-Next)."
        else
            echo "no $OFFICIAL_SOURCE_REPO in $hub."
        fi
        for other in "$hub"/models--*; do
            [ "$other" = "$repo" ] && continue
            grep -qs 'qwen4_exp' "$other"/snapshots/*/config.json \
                && echo "not used automatically (not the official model): ${other##*/}"
        done
        echo "Pass SRC=<snapshot dir> to choose a checkpoint yourself."
    } >&2
    return 1
}
