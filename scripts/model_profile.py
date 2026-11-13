#!/usr/bin/env python3
"""model_profile.py — the models oQ-T knows, and where their checkpoints are.

Each model is one file in models/<id>.json: its architecture, official Hugging
Face repo, request settings (thinking on/off, effort names, sampling) and chat
template quirks. Adding a model = adding that file (plus oMLX support for its
architecture).

A variant is a fine-tune of the same model, named <name>-<suffix>: with
--variant uncensored, Qwen3.8-Flash-Next becomes Qwen3.8-Flash-Next-uncensored.
The suffix selects its BF16 source (a local folder or a Hugging Face repo of
that name) and the quant that writes its answers (<name>-<suffix>-oQ...), so
the official model and its variants never mix.

  model_profile.py list
  model_profile.py info [--model ID]                     shell assignments: MODEL_ID MODEL_NAME ...
  model_profile.py source [--model ID] [--variant V] [--repo ORG/NAME] [--hub DIR] [--search DIR ...]
  model_profile.py generator [--model ID] [--variant V] [--search DIR ...] [--candidates DIR ...]
  model_profile.py check-source|check-quant [--model ID] DIR

'source' and 'generator' print a folder, or explain on stderr and exit 1.
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MODELS_DIR = REPO / "models"
REQUIRED = {"id", "name", "architecture", "official_repo", "requests", "render"}
REQUESTS = {"thinking_off", "thinking_on", "effort", "sampling"}
EFFORT_LEVELS = {"low", "medium", "max"}
# Generator preference when several quants of the model exist: the closest to
# the source first. oQ-T outputs (…-oQ4t-…) and comparison builds are never used.
GENERATOR_LEVELS = ("5", "6", "4", "8")


class ProfileError(SystemExit):
    pass


def profile_paths() -> list[Path]:
    return sorted(MODELS_DIR.glob("*.json"))


def load(model: str | None = None) -> dict:
    """A profile by id or path; with none given, the only profile there is."""
    if model and (model.endswith(".json") or "/" in model):
        path = Path(model).expanduser()
    elif model:
        path = MODELS_DIR / f"{model}.json"
    else:
        paths = profile_paths()
        if len(paths) != 1:
            raise ProfileError(f"{len(paths)} model profiles in {MODELS_DIR}; choose one with "
                               f"OQT_MODEL=<id> ({', '.join(p.stem for p in paths)})")
        path = paths[0]
    if not path.exists():
        known = ", ".join(p.stem for p in profile_paths()) or "none"
        raise ProfileError(f"no model profile {path} (known: {known})")
    prof = json.loads(path.read_text(encoding="utf-8"))
    missing = REQUIRED - prof.keys()
    if missing:
        raise ProfileError(f"{path}: missing {sorted(missing)}")
    missing = REQUESTS - prof["requests"].keys()
    if missing:
        raise ProfileError(f"{path}: requests is missing {sorted(missing)}")
    if set(prof["requests"]["effort"]) != EFFORT_LEVELS:
        raise ProfileError(f"{path}: requests.effort must map exactly {sorted(EFFORT_LEVELS)} "
                           "to the model's own reasoning_effort names")
    if prof["render"].get("tool_arguments", "mapping") not in ("mapping", "string"):
        raise ProfileError(f"{path}: render.tool_arguments must be 'mapping' or 'string'")
    prof["path"] = str(path)
    return prof


def variant_name(prof: dict, variant: str | None) -> str:
    return f"{prof['name']}-{variant}" if variant else prof["name"]


def _config(d: Path) -> dict | None:
    try:
        return json.loads((d / "config.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _arch_of(cfg: dict) -> set[str]:
    text = cfg.get("text_config") or {}
    return {str(cfg.get("model_type") or ""), str(text.get("model_type") or "")}


def _quantized(cfg: dict) -> bool:
    text = cfg.get("text_config") or {}
    return bool(cfg.get("quantization_config") or cfg.get("quantization") or text.get("quantization_config"))


def source_problem(prof: dict, d: Path) -> str | None:
    """Why d is not a complete, unquantized checkpoint of this model (None when it is)."""
    cfg = _config(d)
    if cfg is None:
        return "no readable config.json"
    if prof["architecture"] not in _arch_of(cfg):
        return f"not a {prof['architecture']} checkpoint"
    if _quantized(cfg):
        return "quantized, not the BF16 source"
    index = d / "model.safetensors.index.json"
    try:
        shards = set(json.loads(index.read_text())["weight_map"].values()) if index.exists() else {"model.safetensors"}
    except (OSError, ValueError, KeyError):
        return "unreadable model.safetensors.index.json"
    # exists() follows the HF cache's symlinks, so a missing blob counts as missing.
    missing = [s for s in shards if not (d / s).exists()]
    return f"{len(missing)} weight shards missing (incomplete download?)" if missing or not shards else None


def quant_problem(prof: dict, d: Path) -> str | None:
    cfg = _config(d)
    if cfg is None:
        return "no readable config.json"
    if prof["architecture"] not in _arch_of(cfg):
        return f"not a {prof['architecture']} model"
    if not _quantized(cfg):
        return "not quantized"
    return None


def _hub_snapshots(hub: Path, repo_dir: str) -> list[Path]:
    snaps = hub / repo_dir / "snapshots"
    return sorted((p for p in snaps.iterdir() if p.is_dir()), key=lambda p: p.stat().st_mtime,
                  reverse=True) if snaps.is_dir() else []


def find_source(prof: dict, hub: Path, variant: str | None = None, repo: str | None = None,
                search: list[Path] = ()) -> tuple[Path | None, list[str]]:
    """The BF16 checkpoint: newest complete snapshot of the repo, or for a variant
    the one folder or repo named <name>-<variant>. Returns (dir, explanation)."""
    why: list[str] = []
    if repo:
        repos = [f"models--{repo.replace('/', '--')}"]
    elif variant:
        want = variant_name(prof, variant).lower()
        repos = sorted(p.name for p in hub.glob("models--*") if p.name.split("--")[-1].lower() == want) \
            if hub.is_dir() else []
    else:
        repos = [f"models--{prof['official_repo'].replace('/', '--')}"]
    found: list[Path] = []
    for rd in repos:
        snaps = _hub_snapshots(hub, rd)
        if not snaps:
            why.append(f"no {rd} in {hub}")
            continue
        good = [s for s in snaps if source_problem(prof, s) is None]
        if good:
            found.append(good[0])
        else:
            why.append(f"{rd}: no snapshot is complete and unquantized "
                       f"({source_problem(prof, snaps[0])}); a download may have stopped")
    if variant and not repo:
        want = variant_name(prof, variant).lower()
        for base in search:
            if not base.is_dir():
                continue
            for d in sorted(base.iterdir()):
                if d.is_dir() and d.name.lower() == want:
                    p = source_problem(prof, d)
                    (why.append(f"{d}: {p}") if p else found.append(d))
    if len(found) == 1:
        return found[0], why
    if len(found) > 1:
        return None, [f"several sources named {variant_name(prof, variant)}: "
                      + ", ".join(map(str, found)) + "; choose one with SRC=<dir>"]
    if variant and not repo:
        why.append(f"variant '{variant}' needs a BF16 folder named {variant_name(prof, variant)} in "
                   + ", ".join(map(str, search)) + f", or a Hugging Face repo <org>/{variant_name(prof, variant)} in {hub}")
    elif not repo:
        why.append(f"download it: huggingface-cli download {prof['official_repo']}")
        others = [p.name for p in hub.glob("models--*") if p.name != repos[0]
                  and any(source_problem(prof, s) is None for s in _hub_snapshots(hub, p.name))] if hub.is_dir() else []
        for o in others:
            why.append(f"not used automatically: {o} (a fine-tune: choose it with OQT_VARIANT=<suffix> "
                       "or SOURCE_REPO=<org>/<name>)")
    why.append("Pass SRC=<dir> to choose a checkpoint yourself.")
    return None, why


def _generator_level(name: str, prefix: str) -> str | None:
    """'5' for <prefix>oQ5e-…, <prefix>oQ5-…; None for oQ-T outputs and comparisons."""
    rest = name[len(prefix):]
    if not rest[:1].isdigit() or name.endswith("-cmp"):
        return None
    level, kind = rest[0], rest[1:2]
    return level if kind in ("e", "-", "") else None


def find_generator(prof: dict, variant: str | None, search: list[Path],
                   candidates: list[Path] = ()) -> tuple[Path | None, list[str]]:
    """The quant that writes the answers: a quant of this exact model (variant
    included), named <name>[-<variant>]-oQ<level>…. When exactly one such quant
    is among `candidates` (the models oMLX serves), that one; otherwise the
    newest oQ5, oQ6, oQ4 then oQ8 in `search`."""
    prefix = (variant_name(prof, variant) + "-oq").lower()

    def matches(d: Path) -> str | None:
        return _generator_level(d.name.lower(), prefix) if d.name.lower().startswith(prefix) \
            and quant_problem(prof, d) is None else None

    served = {d.resolve() for d in candidates if d.exists() and matches(d.resolve())}
    if len(served) == 1:
        return served.pop(), []
    pool = [d for base in search if base.is_dir() for d in base.iterdir() if d.is_dir() and matches(d)]
    for level in GENERATOR_LEVELS:
        hits = sorted((d for d in pool if matches(d) == level), key=lambda d: d.stat().st_mtime, reverse=True)
        if hits:
            return hits[0], []
    return None, [f"no quant of {variant_name(prof, variant)} to write the answers: looked for "
                  f"{variant_name(prof, variant)}-oQ<5|6|4|8>... in " + ", ".join(map(str, search))
                  + "; pass GENERATOR=<quant dir>"]


def generator_warning(prof: dict, source_tag: str, generator: Path) -> str | None:
    """A generator whose name says it is a quant of another model."""
    if generator.name.lower().startswith((source_tag + "-oq").lower()):
        return None
    return (f"GENERATOR {generator.name} is not named like a quant of {source_tag} "
            f"({source_tag}-oQ...): make sure it is a quant of the model being quantized")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["list", "info", "source", "generator", "check-source", "check-quant"])
    ap.add_argument("dir", nargs="?")
    ap.add_argument("--model", default=os.environ.get("OQT_MODEL") or None)
    ap.add_argument("--variant", default=os.environ.get("OQT_VARIANT") or None)
    ap.add_argument("--repo", help="source: this Hugging Face repo instead")
    ap.add_argument("--hub", default=os.environ.get("HF_HUB_CACHE", str(Path.home() / ".cache/huggingface/hub")))
    ap.add_argument("--search", nargs="*", default=[], help="folders holding local checkpoints and quants")
    ap.add_argument("--candidates", nargs="*", default=[], help="generator: the models oMLX serves")
    a = ap.parse_args(argv)
    if a.cmd == "list":
        for p in profile_paths():
            prof = load(str(p))
            print(f"{prof['id']:28s} {prof['name']:28s} {prof['architecture']:12s} {prof['official_repo']}")
        return 0
    prof = load(a.model)
    search = [Path(s).expanduser() for s in a.search]
    if a.cmd == "info":
        for k, v in (("MODEL_ID", prof["id"]), ("MODEL_NAME", prof["name"]),
                     ("MODEL_ARCH", prof["architecture"]), ("MODEL_REPO", prof["official_repo"]),
                     ("MODEL_PROFILE", prof["path"]),
                     ("MODEL_VARIANT_NAME", variant_name(prof, a.variant))):
            print(f"{k}={shlex.quote(v)}")
        return 0
    if a.cmd in ("check-source", "check-quant"):
        if not a.dir:
            ap.error(f"{a.cmd} needs a folder")
        p = (source_problem if a.cmd == "check-source" else quant_problem)(prof, Path(a.dir).expanduser())
        if p:
            print(f"{a.dir}: {p}", file=sys.stderr)
            return 1
        return 0
    if a.cmd == "source":
        d, why = find_source(prof, Path(a.hub).expanduser(), a.variant, a.repo, search)
    else:
        d, why = find_generator(prof, a.variant, search, [Path(c).expanduser() for c in a.candidates])
    for line in why:
        print(line, file=sys.stderr)
    if d is None:
        return 1
    print(d)
    return 0


if __name__ == "__main__":
    sys.exit(main())
