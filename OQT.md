# oQ-T quants: how to build them

oQ-T ("teacher-matched") is a better way to choose a quant's weights. Instead of rounding each weight on its own, it measures what each layer outputs on real text and picks the weights that keep that output closest to the original model. The files are normal oMLX quants, so serving is unchanged.

**One command does everything:** your local model answers the corpus prompts, those answers become the calibration text, and the oQ-T quant is built from them.

Supported today: **Qwen3.8-Flash-Next**. DeepSeek V4.1 is not supported yet (the script stops with a clear message).

## One-time setup on the 128 GB Mac

```bash
cd ~/dev/omlx
git fetch && git checkout feat/oqt
source .venv-3.12/bin/activate
python -m pytest tests/test_oqt.py tests/test_oqt_streaming.py -q     # expect "35 passed"

cd ~/dev/software-engineering-corpus
git pull
scripts/testing/test_oqt_pipeline.sh                                  # expect "all pipeline checks passed" (~1 min)
```

You need three things already on the Mac:
- the original **Qwen3.8-Flash-Next** weights in the Hugging Face cache (as for the oQe scripts);
- a **quant of it that you can serve** (the one in `~/.omlx/models`, or any oQ4/oQ5/oQ6 build in `~/models-out`). It writes the answers.
- **Docker** (colima or OrbStack running) for the agent sessions. The first run builds six small sandbox images (needs internet once); check them any time with `agent_tasks/verify_tasks.sh` (expect 12 `ok` lines).

## Build a quant

1. **Stop your oMLX server** (the pipeline starts its own, then needs all the memory for the build).
2. Run:

```bash
cd ~/dev/software-engineering-corpus
nohup scripts/oqt_pipeline.sh 4 v1 > ~/oqup/oqt-v1.out 2>&1 &
```

- `4` is the level (`3`, `5`, `6`, `8` also work). `v1` is any name you choose.
- The result is `~/models-out/Qwen3.8-Flash-Next-oQ4t-v1`.
- It takes many hours: generating the answers, then building. After about 20 answers the log prints an estimate of the generation time.

## Watch it

```bash
scripts/oqt_pipeline.sh status v1          # which stage, how long, last lines
tail -f ~/oqup/runs/v1/pipeline.log        # one line per stage start/end
```

The stages are: `extract` → `derive` → `seed` → `agent` → `generate` → `render` → `build` → `score`.

## Agent sessions and long context

Two parts of the calibration text are there specifically for agentic coding:

- **Agent sessions.** Your local model works as a coding agent on the tasks in `agent_tasks/tasks` (bug fixes and features in Python, TypeScript, Java, Rust, Go, C++ and shell), each in its own Docker container with no network. Whole sessions are recorded: thinking, tool calls, file contents, compiler and test output. The log shows how many sessions solved their task.
- **Long windows.** Agent sessions and chained conversations become 32k-token windows (25% of the calibration tokens) that start at the beginning of a document. That is where Qwen3.8-Flash-Next's sparse attention actually selects, which short windows never exercise. The build log line `calibration windows` shows the split.

To add your own task: copy a folder in `agent_tasks/tasks`, change `task.json` and `repo/`, add the fixed files under `solution/`, and run `agent_tasks/verify_tasks.sh <task-id>`.

## How close is the quant to the original? (M3)

After each build, the score stage compares the quant with the **original BF16 model**:

- **KL**: how far the quant's next-token probabilities are from the original's (lower is better; the main number)
- **top-1**: how often it picks the same most likely token
- **route / flips**: how much router probability moved to other experts, and on what share of tokens the expert set changed

The original model's outputs are recorded once by streaming the BF16 source block by block over the heldout files (it never has to fit in memory; expect one to two hours) and cached in `~/oqup/anchors/`. Every later quant is scored against the same reference in minutes, split by heldout file.

Compare all your quants side by side:

```bash
~/dev/omlx/.venv-3.12/bin/python scripts/score_vs_bf16.py compare ~/oqup/m3-*.json
```

Turn it off with `OQT_M3=0`. Low KL means close to the original; it does not prove the quant solves tasks, so keep looking at the heldout and agent results too.

## Does the corpus help? Build the comparison arm

The pipeline mixes three kinds of prompts: your corpus, **generic** software tasks outside your stack (`seeds/generic.txt`), and **broad** non-coding tasks including several languages and tool calling (`seeds/broad.txt`). The generic and broad prompts keep experts your domain rarely uses from being starved.

Only one quant is built per run. The comparison arm below is optional: it is a second full build (hours), so run it only when you want the answer.

To see what your corpus adds, build a second quant without it:

```bash
OQT_PROFILE=generic nohup scripts/oqt_pipeline.sh 4 v1-generic > ~/oqup/oqt-v1-generic.out 2>&1 &
```

Prompts and answers are cached in `~/oqup/prep-cache`, so this run reuses the generic and broad answers from your main run and only generates what is missing. Then compare the two quants' heldout scores: if `v1` beats `v1-generic` on your domain without losing on `heldout-general`, the corpus earns its place.

## Stop, resume, change something

- **Stop it any time:** `kill <pid>` (the pid is in `status`) or Ctrl-C. Everything stops cleanly, including the server.
- **Resume:** run the **same command** again. Finished stages are skipped, answers already generated are reused, and the build continues from the last finished layer.
- **Changed the corpus or a setting?** Run the same command again. Only the stages affected by the change are redone (for example, a bigger `BUDGET_TOKENS` generates only the extra answers, then rebuilds).

## When it finishes

The end of `~/oqup/runs/v1/pipeline.log` shows:

```
calibration: N conversations + 9 passages, N tokens (template)
oQ-T      : output error x0.NN vs oQe (median), better on NN% of N tensors
```

`x0.NN` is how much output error remains compared with a normal oQe quant of the same size, measured on the real model: lower is better. Heldout scores are in `~/oqup/runs/v1/logs/score.log`.

The build log (`~/oqup/runs/v1/logs/build.log`) also reports:

- **Routing protection.** For each MoE layer, how much router probability moved to different experts after quantization. Where it moved too much, the tensors that feed the router got a bit more precision. The summary says how many layers and tensors that was.
- **Expert usage skew.** How unevenly your text uses the experts. A **strong** tiering signal means a minority of experts carries most tokens, which is when giving popular experts more bits (expert tiers) would pay off. Send me that line after your first build.

Serve it like any other quant:

```bash
ln -s ~/models-out/Qwen3.8-Flash-Next-oQ4t-v1 ~/.omlx/models/
```

## Options

Put them in front of the command, for example `BUDGET_TOKENS=500000 scripts/oqt_pipeline.sh 4 v1`.

| Option | Default | Effect |
|---|---|---|
| `GENERATOR=<quant dir>` | the Qwen quant in `~/.omlx/models` | Which model writes the answers |
| `BUDGET_TOKENS` | `1000000` | How much text to generate (thinking included). More = longer run, more calibration data |
| `EFFORT_MIX` | `max=70,medium=15,low=15` | Thinking levels. `max` is the model's top level, whatever it's called |
| `CONCURRENCY` | `4` | Parallel requests while generating |
| `OQT_PROFILE` | `profile` | `profile`: your corpus plus generic and broad prompts. `generic`: no corpus (the comparison arm) |
| `OQT_MIX` | `corpus=50,generic=25,broad=25` | Share of the generated text per prompt group. `OQT_MIX=corpus=100` uses only your corpus and skips the seed stage |
| `PROMPTS_PER_SEED` | `8` | Prompts the model writes per seed in `seeds/generic.txt` and `seeds/broad.txt` |
| `OQT_AGENT=0` | on | Skip agent sessions (always skipped for the generic arm) |
| `AGENT_SAMPLES` | `2` | Agent sessions per task in `agent_tasks/tasks` |
| `OQT_LONG_SHARE` | `0.25` | Share of calibration tokens in long windows (`0` = off) |
| `OQT_LONG_LEN` | `32768` | Long window length in tokens |
| `OQT_M3=0` | on | Skip scoring against the original model |
| `M3_SEQ`, `M3_MAX_WINDOWS` | `2048`, `64` | M3 window length and windows per heldout file |
| `OQT_COMPARE=1` | off | Also build a plain oQe quant from the same text and score both |
| `OQT_REFINE_EXPERTS=1` | off | Also polish the routed experts' rounding (always on for the other tensors). Better, but about 8 extra hours on Qwen3.8-Flash-Next |
| `OQT_ROUTING=0` | on | Turn off routing protection |
| `OQT_ROUTING_THRESHOLD` | `0.02` | Routing shift (share of router probability) that triggers more bits |
| `OQT_ROUTING_MAX_LAYERS` | `0.25` | At most this share of layers gets the extra bits, which caps the size cost |
| `OQ_SKIP_PPL=1` | off | Skip heldout scoring |
| `NGRAM_BITS` | `8` | n-gram table bits |
| `PRESERVE_MTP=0` | keep | Drop the MTP draft head |
| `PORT` | `8765` | Port of the pipeline's own oMLX server |

## If something goes wrong

The pipeline log says which stage failed and shows the last lines of that stage's log (`~/oqup/runs/v1/logs/<stage>.log`). Fix the cause, then run the same command: it resumes.

| Message | What to do |
|---|---|
| "an oMLX server is running; stop it before the build" | Stop your oMLX server, rerun. |
| "something already answers on port 8765" | Something else uses that port: stop it, or add `PORT=8790`. |
| "no quant found to write the answers" | Add `GENERATOR=<path to a Qwen3.8-Flash-Next quant>`. |
| "found N … source snapshots" | Add `SRC=<path to the snapshot>`. |
| "this oMLX checkout has no oQ-T" | Redo setup step 1 (`git checkout feat/oqt`). |
| "the oMLX server exited" | See `~/oqup/runs/v1/logs/server.log` (often: not enough memory, or a model that doesn't load). |

## Where things go

| What | Where |
|---|---|
| The quant (with `build.json`, `oqt_report.json`) | `~/models-out/<Model>-oQ<level>t-<name>/` |
| Pipeline log, state, per-stage logs | `~/oqup/runs/<name>/` |
| Prompts, answers (cached per request) | `~/oqup/runs/<name>/prep/` |
| Calibration text used for the build | `~/oqup/runs/<name>/bundle.txt` |
| oQ-T layer cache (delete once the quant is good) | `~/oqup/oqt-cache-<Model>-oQ<level>-<name>/` |

## Limits of this version

- Resume is per request (answers), per layer (oQ-T sweep) and per output shard (file writing). One step still restarts from its own beginning if interrupted: oMLX's imatrix pass. Its duration on your Mac decides whether it's worth making resumable.
- Expert tiers (more bits for popular experts) need a change in oMLX's serving code; they will be built only if your builds show a strong tiering signal.
- The variation pass from `PREP_PLAN.md` is not in yet. Agent tasks cover 7 languages so far (no Spring/Postgres/Kafka services, Godot or embedded builds yet).
- Not yet: expert tiers (runtime), DeepSeek V4.1, sealed agent tasks for behavioral scoring.

## Lower-level: build from a text file directly

`scripts/omlx_oqt.sh 4 v1` builds an oQ-T quant straight from `calibration/*.txt` (or `CORPUS_FILE=<file>`), without generating answers. The pipeline uses it for its build stage.
