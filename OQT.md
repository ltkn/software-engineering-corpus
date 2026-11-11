# oQ-T quants: how to build them

oQ-T ("teacher-matched") is a better way to choose the 4-bit (or 3-, 5-bit…) weights. Instead of rounding each weight on its own, it measures what each layer actually outputs on real text and picks the weights that keep that output closest to the original model. Files come out in the normal oMLX format, so serving is unchanged.

Supported today: **Qwen3.8-Flash-Next**. DeepSeek V4.1 is not supported yet (the script refuses it with a clear message).

## One-time setup on the 128 GB Mac

```bash
# 1. oMLX with oQ-T (branch feat/oqt)
cd ~/dev/omlx
git fetch
git checkout feat/oqt
source .venv-3.12/bin/activate
python -m pytest tests/test_oqt.py tests/test_oqt_streaming.py -q   # expect "35 passed"

# 2. this repo, up to date
cd ~/dev/software-engineering-corpus
git pull
```

The Qwen3.8-Flash-Next weights must be in the Hugging Face cache (as for the oQe scripts). The script finds them by itself.

## Build a quant

```bash
cd ~/dev/software-engineering-corpus
nohup scripts/omlx_oqt.sh 4 v1 > ~/oqup/oqt-v1.out 2>&1 &
```

- `4` is the level (`3`, `4`, `5`, `6`, `8` also work). `v1` is any name you choose.
- The result is `~/models-out/Qwen3.8-Flash-Next-oQ4t-v1`.
- Plan for an **overnight run**. Follow progress with `tail -f ~/oqup/oqt-*.log`.
- Stop the oMLX server first, so the build and the scoring have the memory to themselves.

Before a long run, you can check what it will do without starting anything:

```bash
scripts/omlx_oqt.sh 4 v1 --dry-run
```

## When it finishes

The end of `~/oqup/oqt-v1.out` shows:

```
oQ-T tensors written : …
vs oQe, same bits    : median output error x0.NN, better on NN% of tensors
```

The `x0.NN` is how much output error remains compared with a normal oQe quant at the same size, measured on the real model: lower is better. Below that come the heldout scores.

Serve it like any other quant:

```bash
ln -s ~/models-out/Qwen3.8-Flash-Next-oQ4t-v1 ~/.omlx/models/
```

## If something goes wrong

| Situation | What to do |
|---|---|
| The run stopped (crash, reboot, Ctrl-C) | Run the same command with `OQT_OVERWRITE=1` in front. Finished layers are reused, so it resumes. |
| "exists. Rerun with OQT_OVERWRITE=1" | You already have a build with that name. Pick a new name, or add `OQT_OVERWRITE=1` to replace it. |
| "found N snapshots; pass SRC=<dir>" | Several Qwen3.8-Flash-Next copies are cached. Add `SRC=<path to the snapshot>` in front of the command. |
| "this oMLX checkout has no oQ-T" | Run the setup step 1 again (`git checkout feat/oqt`). |

## Useful options

Put them in front of the command, for example `OQT_COMPARE=1 scripts/omlx_oqt.sh 4 v1`.

| Option | Effect |
|---|---|
| `OQT_COMPARE=1` | Also build a plain oQe quant from the same text, and score both, to compare directly. Adds a few hours and one more output on disk. |
| `CORPUS_FILE=<file>` | Calibrate on another text file instead of `calibration/*.txt`. |
| `OQ_SKIP_PPL=1` | Skip heldout scoring at the end. |
| `NGRAM_BITS=4` | Store the n-gram table at 4 bits instead of 8 (smaller, slightly lossier). |
| `PRESERVE_MTP=0` | Drop the MTP draft head. |

## Where things go

| What | Where |
|---|---|
| The quant | `~/models-out/<Model>-oQ<level>t-<name>/` (with `build.json` and `oqt_report.json` inside) |
| Build log | `~/oqup/oqt-<Model>-oQ<level>-<name>.log` |
| Resume cache (safe to delete once the quant is good) | `~/oqup/oqt-cache-<Model>-oQ<level>-<name>/` |
| Heldout scores | `~/oqup/ppl-<Model>-oQ<level>-<name>-oqt.log` |

## What's next (not in this version)

- Calibration on the model's own answers (the prep script, `PREP_PLAN.md`), instead of the corpus text.
- Scoring against the original model with full KL and routing flips.
- Routing-aware bit allocation, expert tiers, and DeepSeek V4.1 support.
