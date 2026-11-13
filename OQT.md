# oQ-T quants: how to build them

oQ-T ("teacher-matched") is a better way to choose a quant's weights. Instead of rounding each weight on its own, it measures what each layer outputs on real text and picks the weights that keep that output closest to the original model. The files are normal oMLX quants, so serving is unchanged.

**One command does everything:** your local model answers the corpus prompts, those answers become the calibration text, and the oQ-T quant is built from them.

Supported: **Qwen3.8-Flash-Next** and fine-tunes of it (see Models and variants). The scripts stop on any other checkpoint.

## Step by step on the 128 GB Mac

The paths below are the ones on that Mac: oMLX in `~/dev/omlx`, this repo in `~/dev/software-engineering-corpus`, work files in `~/oqup`, quants in `~/models-out`, and the quant that writes the answers is `~/models-out/Qwen3.8-Flash-Next-oQ6e-coder-q8-ngram-mtp`. Do the one-time setup below first if it's a new machine.

**1. Update both repos** (only when no run is going: a run uses the scripts while it works).

```bash
cd ~/dev/omlx && git pull && make install          # make install picks up new dependencies
cd ~/dev/software-engineering-corpus && git pull
```

**2. Prepare the Mac.**

```bash
mkdir -p ~/oqup
# stop your own oMLX server (menu bar app or the terminal it runs in): the pipeline runs its own
colima start                                       # Docker for the agent sessions
```

**3. Start the run.** Choose the level (`4` here) and a run name (`v2` here; a new name for each new quant).

```bash
cd ~/dev/software-engineering-corpus
GENERATOR=~/models-out/Qwen3.8-Flash-Next-oQ6e-coder-q8-ngram-mtp \
caffeinate -dimsu nohup scripts/oqt_pipeline.sh 4 v2 > ~/oqup/oqt-v2.out 2>&1 &
```

The default budget (1,000,000 generated tokens) takes about half a day: agent sessions (1–2 h), answers (~5–6 h; the log prints an estimate after ~20 answers), then the build (~6 h) and the score. For a quick check of a change first, add `BUDGET_TOKENS=100000` and use a pilot name; its answers are reused by the full run.

**4. Watch it.**

```bash
scripts/oqt_pipeline.sh status v2                  # stage, time so far, last lines, saved settings
tail -f ~/oqup/runs/v2/pipeline.log
```

The first lines of `pipeline.log` show `model:`, `source:`, `answers by:` and `template:`: check them once.

**5. When `status` shows `build running`, stop Docker** (the build needs its memory; the agent sessions are done):

```bash
colima stop
```

**6. If it stops** (an error, a kill, a reboot): fix the cause if the log names one, then run `scripts/oqt_pipeline.sh 4 v2` again (no settings needed: they are saved with the run). It continues where it was; finished stages, answers and built layers are kept. Run `colima start` first if the agent stage isn't done yet.

**7. When it's done**, the end of `pipeline.log` shows the M3 score and the comparison with the previous run of the same level. Then:

```bash
scripts/oqt_pipeline.sh results                    # every quant side by side

colima start                                       # optional, ~1 h: does the quant still solve the agent tasks?
OQT_AGENT_EVAL=1 scripts/oqt_pipeline.sh 4 v2
colima stop

ln -s ~/models-out/Qwen3.8-Flash-Next-oQ4t-v2 ~/.omlx/models/      # serve it
rm -rf ~/oqup/oqt-cache-Qwen3.8-Flash-Next-oQ4-v2                  # once you keep it: frees the layer cache
```

**Another level from the same answers** (for example a 5-bit): same generator, new run name. Agent sessions and answers come from the cache (the server still loads the generator once, a few minutes), then render, build and score run (~6 h):

```bash
GENERATOR=~/models-out/Qwen3.8-Flash-Next-oQ6e-coder-q8-ngram-mtp \
caffeinate -dimsu nohup scripts/oqt_pipeline.sh 5 v2-q5 > ~/oqup/oqt-v2-q5.out 2>&1 &
```

**A run started with older scripts** (v1 was): let it finish on the scripts it started with, then update (step 1). If you want to run something more on that finished run, add `OQT_KEEP_BUILD=1` so the updated scripts keep its quant instead of rebuilding it (it checks the quant was built from the same calibration text):

```bash
colima start
OQT_KEEP_BUILD=1 OQT_AGENT_EVAL=1 scripts/oqt_pipeline.sh 4 v1
```

## One-time setup on the 128 GB Mac

```bash
cd ~/dev/omlx
git fetch && git checkout feat/oqt && make install
source .venv-3.12/bin/activate
python -m pytest tests/test_oqt.py tests/test_oqt_streaming.py -q     # expect "43 passed"

cd ~/dev/software-engineering-corpus
git pull
scripts/testing/test_oqt_pipeline.sh                                  # expect "all pipeline checks passed" (a few minutes)
python3 scripts/testing/test_model_profile.py                         # expect "all model profile checks passed"
```

You need three things already on the Mac:
- the original **Qwen3.8-Flash-Next** weights in the Hugging Face cache (`huggingface-cli download Qwen/Qwen3.8-Flash-Next`);
- a **quant of it that you can serve** (yours: `~/models-out/Qwen3.8-Flash-Next-oQ6e-coder-q8-ngram-mtp`). It writes the answers.
- **Docker** for the agent sessions: colima or OrbStack (not Docker Desktop). Set it up once:

  ```bash
  brew install colima docker
  colima start --cpu 4 --memory 8 --disk 120   # the disk can only grow later, so size it now
  # or instead: brew install --cask orbstack && open -a OrbStack
  agent_tasks/build_images.sh                  # eleven images: about an hour, needs internet once
  agent_tasks/verify_tasks.sh                  # expect 28 "ok" lines, about 15 minutes
  ```

  The images take about 25 GB (ESP-IDF ~13 GB, Arduino ~4.5 GB). The pipeline checks Docker before it starts: it stops if Docker has under 3 GB of memory or too little disk (40 GB while images are still to build, 10 GB after), and warns under 8 GB of memory or 4 CPUs, printing the command that fixes it. After a reboot, run `colima start` again (or `brew services start colima` once). Toolchains are pinned to the latest stable releases (JDK 27, Spring Boot 4.1, PostgreSQL 18, Node 26 with TypeScript 7, Python 3.15, Go 1.27, Rust 1.99, Godot 4.7, ESP-IDF 6.1, Arduino ESP32 core 3.3, Debian 13); bump them on purpose, not by floating tags, so runs stay comparable. No boards are needed: embedded tasks run host tests and build real firmware for the ESP32-C6.

## Build a quant

The step by step above is the usual path. This section explains the choices behind it.

Before you start: **stop your oMLX server** (the pipeline starts its own, then needs all the memory for the build), and `mkdir -p ~/oqup` once (the log files go there).

The source model (the original BF16 weights the quant is matched to) is found by itself: the newest complete, unquantized snapshot of the model profile's official repo (`Qwen/Qwen3.8-Flash-Next`) in the Hugging Face cache. Fine-tunes are ignored unless you name them (example 2). The preflight also renders one thinking, tool-calling conversation through the source's chat template, so a template that doesn't fit stops the run in seconds instead of after the generation.

### Example 1: the official Qwen3.8-Flash-Next

**Pilot first**, a small run that checks everything works and measures how long the real run will take:

```bash
cd ~/dev/software-engineering-corpus
GENERATOR=~/models-out/Qwen3.8-Flash-Next-oQ6e-coder-q8-ngram-mtp \
BUDGET_TOKENS=100000 \
nohup scripts/oqt_pipeline.sh 4 pilot > ~/oqup/oqt-pilot.out 2>&1 &
```

**Then the real run**, with the same generator (the pilot's answers are reused, only the rest is generated):

```bash
GENERATOR=~/models-out/Qwen3.8-Flash-Next-oQ6e-coder-q8-ngram-mtp \
nohup scripts/oqt_pipeline.sh 4 v1 > ~/oqup/oqt-v1.out 2>&1 &
```

Results: `~/models-out/Qwen3.8-Flash-Next-oQ4t-pilot`, then `~/models-out/Qwen3.8-Flash-Next-oQ4t-v1`.

### Example 2: a fine-tune of the same model (a variant, e.g. your own uncensored build)

A fine-tune is quantized as a **variant**: a suffix added to the model's name. With `OQT_VARIANT=uncensored`, the pipeline works on `Qwen3.8-Flash-Next-uncensored`:

- **its source** is the BF16 folder `~/models-out/Qwen3.8-Flash-Next-uncensored` (a model you made locally), or a Hugging Face repo `<org>/Qwen3.8-Flash-Next-uncensored` in the cache. The name matches without regard to case. If both exist, it stops and asks you to pick one with `SRC=`.
- **its answers** come from a quant of that fine-tune, `~/models-out/Qwen3.8-Flash-Next-uncensored-oQ<5|6|4|8>...`, never from a quant of the official model. If you have none yet, build a plain oQ5e or oQ6e of it first, the same way you built your current quants.
- **the result** is `~/models-out/Qwen3.8-Flash-Next-uncensored-oQ4t-<name>`. Its oQ-T cache and M3 reference are kept apart from the official model's.

```bash
cd ~/dev/software-engineering-corpus
OQT_VARIANT=uncensored BUDGET_TOKENS=100000 \
nohup scripts/oqt_pipeline.sh 4 uncensored-pilot > ~/oqup/oqt-uncensored-pilot.out 2>&1 &

# then the real run
OQT_VARIANT=uncensored \
nohup scripts/oqt_pipeline.sh 4 uncensored-v1 > ~/oqup/oqt-uncensored-v1.out 2>&1 &
```

The variant is saved with the run like any setting. A fine-tune named differently works too: `SOURCE_REPO=orcarouter/Qwen3.8-Flash-Next-Uncensored` (an HF repo) or `SRC=<folder>`, then with an explicit `GENERATOR=<a quant of that fine-tune>`, because nothing else tells which quant belongs to it.

### What the parts mean

- `4` is the level of the quant to build (`3`, `5`, `6`, `8` also work).
- `pilot`, `v1`, `uncensored-v1` are names you choose. A name labels the run folder (`~/oqup/runs/<name>/`) and the result. What makes a pilot is `BUDGET_TOKENS=100000`: a tenth of the default 1,000,000 generated tokens. It runs every stage (answers, agent sessions, long windows, build, score), so problems show up in hours, not after a day, and the log estimates the full run's time. The pilot quant works, but it is calibrated on little text, so judge the method by the full run.
- `GENERATOR` is the local quant that writes the answers. It is a folder, not an API: the pipeline serves it on its own oMLX server (port 8765), with your `OMLX_API_KEY` if it is set. Use the best quant that fits; on 128 GB an oQ6e or oQ5e. For the official model you may leave it out: the pipeline then picks the only Qwen3.8-Flash-Next quant in `~/.omlx/models`, else the newest oQ5, then oQ6, oQ4, oQ8 in `~/models-out` (it would pick an oQ5e over your oQ6e, so pass it). The first lines of `~/oqup/runs/<name>/pipeline.log` show `source:` and `answers by:`; check them.
- Changing `GENERATOR` later means new answers: each cached answer belongs to the model that wrote it.
- Requests go one at a time (`CONCURRENCY=1`, the default), which keeps memory lowest with a large generator.
- It takes many hours: generating the answers, then building. After about 20 answers the log prints an estimate of the generation time.
- `SRC=<snapshot dir>` instead of `SOURCE_REPO` points at a source folder directly.

## Models and variants

What the pipeline knows about a model lives in one file, `models/<id>.json`; `scripts/model_profile.py list` shows them. With one profile there, it is used without asking; with several, pick one with `OQT_MODEL=<id>`. A profile holds:

| Field | What it is |
|---|---|
| `name`, `architecture`, `official_repo` | how the model's folders are named, the `model_type` its checkpoints must have, and the HF repo of the official source |
| `requests.thinking_off` / `thinking_on` | the chat-template switches for requests without and with thinking |
| `requests.effort` | the pipeline's `low`, `medium`, `max` mapped to the model's own `reasoning_effort` names |
| `requests.sampling` | the model card's recommended sampling |
| `render.template_kwargs` | what the calibration text is rendered with (thinking kept) |
| `render.tool_arguments` | `mapping` if the template iterates tool-call arguments as an object (Qwen), `string` if it prints the JSON string |

Editing a profile's request settings reruns the request stages; answers whose requests didn't change come from the cache.

**Adding a model** = a new profile plus oMLX support for its architecture (oQ-T's block walk, routing hooks and loaders live in oMLX). Then a pilot shows the rest: the preflight checks the template, the pilot run every stage.

**Variants** need no file: `OQT_VARIANT=<suffix>` works for any profile (see example 2). The official model and each variant keep separate sources, generators, answers, caches and results.

## Watch it

```bash
scripts/oqt_pipeline.sh status v1          # which stage, how long, last lines
tail -f ~/oqup/runs/v1/pipeline.log        # one line per stage start/end
```

The stages are: `preflight` → `extract` → `derive` → `seed` → `agent` → `generate` → `render` → `build` → `score`, then `agent-eval` when asked (`OQT_AGENT_EVAL=1`).

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

**What it's measured on.** The render stage keeps 5% of the prompts and agent tasks (`OQT_HOLDOUT_SHARE`) out of the calibration: the model's answers to them are never calibrated on, and become the eval. One slice per group, so the score says where a quant loses:

| Slice | What it is |
|---|---|
| `heldout-oqt-corpus` | the model's answers (thinking included) to held-out corpus prompts: your stack |
| `heldout-oqt-generic` | answers to held-out generic software prompts |
| `heldout-oqt-broad` | answers to held-out non-coding, multilingual and tool-calling prompts |
| `heldout-oqt-agent` | whole held-out agent sessions: tool calls, tool output, long context |
| `heldout-written-se` | `eval/heldout-written-se.txt`, written SE text no prompt was derived from (the independent check) |

They are in `~/oqup/runs/<name>/heldout/`. Whole prompts and tasks are held out, never single answers, so no near-twin of an eval text is in the calibration. A slice needs at least one 2,048-token window: with a pilot-size budget some are too small to score, with the full budget each has several.

The original model's outputs are recorded once by streaming the BF16 source block by block over these files (it never has to fit in memory) and cached in `~/oqup/anchors/`. Every later quant scored on the same files reuses that reference and takes minutes, split by slice. A new run name has its own held-out files, so it records its own reference once.

Compare all your quants side by side:

```bash
~/dev/omlx/.venv-3.12/bin/python scripts/score_vs_bf16.py compare ~/oqup/m3-*.json
```

Turn it off with `OQT_M3=0`. Low KL means close to the original; it does not prove the quant solves tasks: the agent eval below checks that.

## Does the quant still solve tasks? (agent eval)

The generator already worked every agent task twice for the calibration, and each session's check says whether it solved it. The agent eval has the **quant** do the same: same tasks, same number of sessions, same effort levels, served by the pipeline's own oMLX server in the same Docker sandboxes. Then the two are compared task by task. It runs after the score, only when asked, because it needs Docker again (stopped during the build):

```bash
colima start
OQT_AGENT_EVAL=1 scripts/oqt_pipeline.sh 4 v1     # on a finished run: everything else is skipped
```

The pipeline log then shows:

```
agent eval: quant solved 49/56 (88%), generator 51/56 (91%) (28 tasks; ...)
agent eval: held-out tasks (...): quant 4/4, generator 4/4
agent eval: worse on: rust-ble-irk 2/2->1/2, ...
```

With 56 sessions, differences under about 10 points are noise; a task lost in both sessions is worth a look. The held-out tasks are the ones whose sessions were not calibrated on. Sessions are cached per build, so the rerun is instant and a rebuilt quant is evaluated afresh. Takes about as long as the agent stage did (40–90 min).

## All runs side by side

```bash
scripts/oqt_pipeline.sh results
```

prints one line per quant: size, KL and top-1 on `heldout-written-se` (the same text in every run, so comparable across runs), KL and top-1 on the run's own held-out conversations (different per run: compare those only between quants of one run), routing drift, and the agent eval if it ran. Quants you scored by hand (`~/oqup/m3-*.json`, like your oQ6e) are listed too. Each finished run writes `~/oqup/runs/<name>/result.json`, and the end of its log compares it with the previous run of the same model, variant and level, with a warning if it is worse (KL up more than 10%, top-1 down more than a point, or agent solve rate down more than 10 points).

## Does the corpus help? Build the comparison arm

The pipeline mixes three kinds of prompts: your corpus, **generic** software tasks outside your stack (`seeds/generic.txt`), and **broad** non-coding tasks including several languages and tool calling (`seeds/broad.txt`). The generic and broad prompts keep experts your domain rarely uses from being starved.

Only one quant is built per run. The comparison arm below is optional: it is a second full build (hours), so run it only when you want the answer.

To see what your corpus adds, build a second quant without it:

```bash
OQT_PROFILE=generic nohup scripts/oqt_pipeline.sh 4 v1-generic > ~/oqup/oqt-v1-generic.out 2>&1 &
```

Prompts and answers are cached in `~/oqup/prep-cache`, so this run reuses the generic and broad answers from your main run and only generates what is missing. Then compare the two quants' heldout scores: if `v1` beats `v1-generic` on the corpus slice without losing on the generic and broad slices, the corpus earns its place. Score both quants on the **same** held-out files: `score_vs_bf16.py score --reference <v1's M3 reference>` for the `v1-generic` quant (the generic arm holds out no corpus conversations of its own).

## Stop, resume, change something

- **Stop it any time:** `kill <pid>` (the pid is in `status`) or Ctrl-C. Everything stops cleanly, including the server.
- **Resume:** `scripts/oqt_pipeline.sh 4 v1` is enough, even after a reboot. A run saves its settings (`GENERATOR`, `BUDGET_TOKENS`, `EFFORT_MIX`, ...) in `~/oqup/runs/v1/settings.env` on its first start and reuses them, so a resume can't silently switch to another generator or budget. `status` shows them. Finished stages are skipped, answers already generated are reused, and the build continues from the last finished layer.
- **Changed the corpus?** Run it again: only the stages affected by the change are redone.
- **Updated this repo's scripts after a build?** A change to what shapes the quant (the build settings in `omlx_oqt.sh`, the bundle) rebuilds. If the bundle came out the same, `OQT_KEEP_BUILD=1` keeps the existing quant instead; it checks the quant was built from this exact bundle and refuses otherwise.
- **Changing a setting of an existing run** has to be on purpose: a different value stops the run with the old and new values, unless you add `OQT_CHANGE_SETTINGS=1` (for example `OQT_CHANGE_SETTINGS=1 BUDGET_TOKENS=2000000 scripts/oqt_pipeline.sh 4 v1` generates only the extra answers, then rebuilds). Or start a new run name. `CONCURRENCY` and `PORT` only change speed and can be changed freely.
- **During the build** Docker isn't needed (the agent sessions are done and cached): `colima stop` gives its memory to the build. The pipeline warns before the build if Docker is still running, or if `iogpu.wired_limit_mb` leaves macOS less than 12 GB. A build that starves macOS freezes the Mac until the kernel watchdog reboots it; the build then resumes from its last finished layer. Run long builds under `caffeinate -dimsu`.

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

Put them in front of the command, for example `BUDGET_TOKENS=500000 scripts/oqt_pipeline.sh 4 v1`. They are saved with the run on its first start and reused on resume (see Stop, resume, change something); `OQT_CHANGE_SETTINGS=1` changes them for an existing run.

| Option | Default | Effect |
|---|---|---|
| `OQT_MODEL=<id>` | the only profile in `models/` | Which model profile (see Models and variants) |
| `OQT_VARIANT=<suffix>` | none | A fine-tune named `<name>-<suffix>`, with its own source and generator (example 2) |
| `SOURCE_REPO=<org/name>` | the profile's official repo | Quantize a fine-tune from this HF repo (needs `GENERATOR`) |
| `SRC=<dir>` | found in the HF cache | The source snapshot folder, given directly |
| `GENERATOR=<quant dir>` | the only quant of the model (or variant) in `~/.omlx/models`, else the newest `<name>[-<variant>]-oQ5/6/4/8...` in `~/models-out` | Which local quant writes the answers (see Build a quant) |
| `BUDGET_TOKENS` | `1000000` | How much text to generate (thinking included). More = longer run, more calibration data |
| `EFFORT_MIX` | `max=70,medium=15,low=15` | Thinking levels. `max` is the model's top level, whatever it's called |
| `CONCURRENCY` | `1` | Parallel requests while generating. 1 uses the least memory; batching can raise total speed, so try 2 if memory allows and compare the pilot's estimate. Changing it never regenerates answers. |
| `AGENT_CONCURRENCY` | `CONCURRENCY` | Agent sessions run at the same time |
| `OQT_PROFILE` | `profile` | `profile`: your corpus plus generic and broad prompts. `generic`: no corpus (the comparison arm) |
| `OQT_MIX` | `corpus=50,generic=25,broad=25` | Share of the generated text per prompt group. `OQT_MIX=corpus=100` uses only your corpus and skips the seed stage |
| `PROMPTS_PER_SEED` | `8` | Prompts the model writes per seed in `seeds/generic.txt` and `seeds/broad.txt` |
| `OQT_AGENT=0` | on | Skip agent sessions (always skipped for the generic arm) |
| `AGENT_SAMPLES` | `2` | Agent sessions per task in `agent_tasks/tasks` |
| `OQT_LONG_SHARE` | `0.25` | Share of calibration tokens in long windows (`0` = off) |
| `OQT_LONG_LEN` | `32768` | Long window length in tokens |
| `OQT_HOLDOUT_SHARE` | `0.05` | Share of prompts and agent tasks kept out of the calibration as the M3 eval (`0` = none: then only `heldout-written-se` is scored) |
| `OQT_M3=0` | on | Skip scoring against the original model |
| `M3_SEQ`, `M3_MAX_WINDOWS` | `2048`, `64` | M3 window length and windows per heldout file |
| `OQT_AGENT_EVAL=1` | off | After the score, run the agent tasks with the quant and compare with the generator (needs Docker; not saved with the run) |
| `OQT_KEEP_BUILD=1` | off | Keep the existing quant when it was built from this exact bundle, instead of rebuilding after a script update (not saved) |
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
| "no quant found to write the answers" | No folder named `<name>[-<variant>]-oQ<5/6/4/8>...` in `~/models-out`: add `GENERATOR=<path to a quant of the model>`. |
| "no BF16 source found" | The lines above it say why: the official repo is missing or its download is incomplete (run the `huggingface-cli download` it prints), no folder or repo is named like the variant, or you meant a fine-tune from another repo (add `SOURCE_REPO=<org>/<name>`). `SRC=<snapshot dir>` always works. |
| "source is not the official ..." | Add `GENERATOR=<a quant of that same fine-tune>`, or name the fine-tune as a variant (`OQT_VARIANT`). |
| "the source's chat template does not fit profile ..." | The lines above it say what failed to render. Fix the profile's `render` settings (see Models and variants). |
| "N model profiles in models/" | Several profiles: choose one with `OQT_MODEL=<id>`. |
| "the agent eval needs Docker" | `colima start`, then rerun the same command. |
| "this oMLX checkout has no oQ-T" | Redo setup step 1 (`git checkout feat/oqt`). |
| "run 'v1' was started with other settings" | A resume gave a setting with another value than the run was started with (it lists both). Leave it out to resume as it was, add `OQT_CHANGE_SETTINGS=1` to change it, or use a new run name. |
| The Mac rebooted during the build (a `watchdog timeout` panic in `/Library/Logs/DiagnosticReports`) | Memory ran out. Stop colima and other apps, check `sysctl iogpu.wired_limit_mb` (0 or at least 16 GB below RAM), then resume: finished layers are reused. If it happens again, `OQT_CHANGE_SETTINGS=1 OQ_SAMPLES=128` halves the build's working memory (the sweep restarts). |
| An agent session ends with `invalid tool call` | The model wrote a tool call the server can't parse three times in a row at that step. The session keeps its earlier turns; nothing to do. |
| "the oMLX server exited" | See `~/oqup/runs/v1/logs/server.log` (often: not enough memory, or a model that doesn't load). |

## Where things go

| What | Where |
|---|---|
| The quant (with `build.json`, `oqt_report.json`) | `~/models-out/<Model>-oQ<level>t-<name>/` |
| Pipeline log, state, per-stage logs | `~/oqup/runs/<name>/` |
| Prompts, answers (cached per request) | `~/oqup/runs/<name>/prep/` |
| Calibration text used for the build | `~/oqup/runs/<name>/bundle.txt` |
| Scores of the run (M3, PPL, agent eval, settings) | `~/oqup/runs/<name>/result.json` |
| The quant's agent sessions | `~/oqup/runs/<name>/agent-eval/` |
| oQ-T layer cache (delete once the quant is good) | `~/oqup/oqt-cache-<Model>-oQ<level>-<name>/` |

## Limits of this version

- Resume is per request (answers), per layer (oQ-T sweep) and per output shard (file writing). One step still restarts from its own beginning if interrupted: oMLX's imatrix pass. Its duration on your Mac decides whether it's worth making resumable.
- Expert tiers (more bits for popular experts) need a change in oMLX's serving code; they will be built only if your builds show a strong tiering signal.
- The variation pass from `PREP_PLAN.md` is not in yet. Agent tasks cover 7 languages so far (no Spring/Postgres/Kafka services, Godot or embedded builds yet).
- Not yet: expert tiers (runtime). The agent eval reuses the calibration's tasks; only the held-out ones were never calibrated on.

## Lower-level: build from a text file directly

`scripts/omlx_oqt.sh 4 v1` builds an oQ-T quant straight from `calibration/*.txt` (or `CORPUS_FILE=<file>`), without generating answers. The pipeline uses it for its build stage.
