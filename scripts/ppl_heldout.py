#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Teacher-forced perplexity on the corpus heldout files, inside the oMLX venv.

Loads the quant through oMLX's own loader (same code path the server uses,
including the custom oQ / n-gram quantization), then scores a text file by
summing token log-probs in non-overlapping chunks. Run it once per model —
one process per quant, the 125B loads don't co-reside:

    ~/dev/omlx/.venv-3.12/bin/python scripts/ppl_heldout.py \
        --model ~/models-out/Qwen3.8-Flash-Next-oQ5e-stock \
        --files eval/heldout-se.txt eval/heldout-general.txt

    ~/dev/omlx/.venv-3.12/bin/python scripts/ppl_heldout.py \
        --model ~/models-out/Qwen3.8-Flash-Next-oQ5e-coder-q8-ngram-mtp \
        --files eval/heldout-se.txt eval/heldout-general.txt

The script only needs the oMLX venv (`omlx.models` + `mlx.core`); it should
run from this corpus checkout with the quant host's `~/dev/omlx` venv python
(the editable install there resolves `omlx` from `~/dev/omlx`). Only PPL
deltas between runs matter: same chunking for both models, and the first pair
should use the same files. Per-chunk NLL lines let you spot WHICH heldout
region diverges, not just the average. `heldout-se.txt` is the domain-relevant
comparison; `heldout-general.txt` is where stock shouldn't be sacrificed.
"""

import argparse
import math
import sys
import time
from pathlib import Path

import mlx.core as mx

DEFAULT_CHUNK = 512  # tokens; matches the build's imatrix seq_length


def forward_logits(model, ids: list[int]):
    """Run one token chunk through the model; return logits [T, vocab] (float32)."""
    arr = mx.array(ids)
    out = None
    try:
        out = model(arr)
    except Exception:
        pass
    if isinstance(out, tuple):
        out = out[0]
    if out is None:
        try:
            out = model.forward(arr)
        except Exception as exc:
            raise RuntimeError(f"could not run the model's forward pass: {exc}") from exc
    import mlx.nn as nn

    return nn.log_softmax(out.reshape(-1, out.shape[-1]).astype(mx.float32), axis=-1)


def score_file(model, tokenizer, path: Path, chunk: int) -> tuple[float, int]:
    """Return (total_nll, total_scored_tokens) for a text file."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print(f"cannot read {path}: {exc}", file=sys.stderr)
        return 0.0, 0

    ids = tokenizer.encode(text)
    if chunk < 2:
        chunk = DEFAULT_CHUNK
    nll_sum = 0.0
    scored = 0
    t0 = time.time()
    for start in range(0, max(len(ids) - 1, 0), chunk):
        window = ids[start : start + chunk]
        if len(window) < 2:
            break
        logp = forward_logits(model, window[:-1])
        targets = mx.array(window[1:])
        tok_nll = -logp[mx.arange(targets.shape[0]), targets]
        s = float(mx.sum(tok_nll).item())
        nll_sum += s
        scored += targets.shape[0]
        if scored % (chunk * 8) < chunk:
            n, s = scored, max(time.time() - t0, 1e-9)
            print(f"  {path.name}: {n} tokens scored ({n / s:.0f} tok/s), running PPL {math.exp(nll_sum / n):.3f}", file=sys.stderr)
    if scored:
        print(
            f"  {path.name}: {scored} tokens in {time.time() - t0:.1f}s -> "
            f"NLL/token {nll_sum / scored:.4f} | PPL {math.exp(nll_sum / scored):.4f} | "
            f"bits/token {(nll_sum / scored) / math.log(2):.4f}",
            file=sys.stderr,
        )
    return nll_sum, scored


def main() -> int:
    ap = argparse.ArgumentParser(description="Heldout perplexity for an oMLX-loaded quant.")
    ap.add_argument("--model", required=True, help="quant dir (config.json + safetensors) or HF id")
    ap.add_argument("--files", required=True, nargs="+", help="heldout text files to score, one by one")
    ap.add_argument("--chunk", type=int, default=DEFAULT_CHUNK, help="tokens per scoring window (default 512)")
    args = ap.parse_args()

    for f in args.files:
        if not Path(f).is_file():
            print(f"missing file: {f}", file=sys.stderr)
            return 2

    print(f"loading {args.model} ...", file=sys.stderr, flush=True)
    from omlx.models import MLXLanguageModel

    mlm = MLXLanguageModel(args.model)
    mlm.load()
    assert mlm.model is not None and mlm.tokenizer is not None

    print(f"{'file':<28} {'tokens':>10} {'NLL/token':>10} {'PPL':>10} {'bits/tok':>9}")
    total: dict[str, float] = {}
    grand_nll = grand_toks = 0
    for path in args.files:
        nll_sum, scored = score_file(mlm.model, mlm.tokenizer, Path(path), args.chunk)
        if not scored:
            continue
        ppl = math.exp(nll_sum / scored)
        total[path] = ppl
        grand_nll += nll_sum
        grand_toks += scored
        print(f"{Path(path).name:<28} {scored:>10} {nll_sum / scored:>10.4f} {ppl:>10.4f} "
              f"{(nll_sum / scored) / math.log(2):>9.4f}")
    if grand_toks:
        pooled = math.exp(grand_nll / grand_toks)
        print(f"{'POOLED':<28} {grand_toks:>10} {grand_nll / grand_toks:>10.4f} {pooled:>10.4f} "
              f"{(grand_nll / grand_toks) / math.log(2):>9.4f}")
        print(f"\nrun summary: PPL @ {args.model.split('/')[-1]}")
        for k, v in total.items():
            print(f"  {Path(k).name:<28} {v:.4f}")
        print(f"  {'POOLED':<28} {pooled:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
