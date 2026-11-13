#!/usr/bin/env python3
"""test_model_profile.py — model profiles, variants, source and generator choice,
and the results table, on fake checkpoint folders (no oMLX needed, seconds).

    python3 scripts/testing/test_model_profile.py
"""
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(REPO / "scripts"))
import model_profile as mp  # noqa: E402
import prep_calibration as prep  # noqa: E402
import results  # noqa: E402

ARCH = "qwen4_exp"


def bf16(d: Path, arch=ARCH, complete=True) -> Path:
    d.mkdir(parents=True)
    (d / "config.json").write_text(json.dumps({"model_type": arch}))
    (d / "model.safetensors.index.json").write_text(json.dumps({"weight_map": {"a": "m-1.safetensors", "b": "m-2.safetensors"}}))
    (d / "m-1.safetensors").write_text("x")
    if complete:
        (d / "m-2.safetensors").write_text("x")
    return d


def quant(d: Path, bits=5) -> Path:
    d.mkdir(parents=True)
    (d / "config.json").write_text(json.dumps({"model_type": ARCH, "quantization": {"bits": bits}}))
    return d


def main():
    tmp = Path(tempfile.mkdtemp(prefix="oqt-profile-test."))
    try:
        prof = mp.load()                                     # the only profile
        assert prof["id"] == "qwen3.8-flash-next" and prof["architecture"] == ARCH, prof
        assert mp.load("qwen3.8-flash-next")["name"] == "Qwen3.8-Flash-Next"
        for bad in ({"effort": {"low": "low"}}, ):
            p = tmp / "bad.json"
            p.write_text(json.dumps({**{k: v for k, v in prof.items() if k != "path"},
                                     "requests": {**prof["requests"], **bad}}))
            try:
                mp.load(str(p)); raise AssertionError("an incomplete effort map must be refused")
            except SystemExit as e:
                assert "effort" in str(e), e
        print("ok   profile loads and is validated")

        hub, out = tmp / "hub", tmp / "models-out"
        out.mkdir()
        official = bf16(hub / "models--Qwen--Qwen3.8-Flash-Next" / "snapshots" / "abc")
        bf16(hub / "models--Qwen--Qwen3.8-Flash-Next" / "snapshots" / "new-but-partial", complete=False)
        d, why = mp.find_source(prof, hub, search=[out])
        assert d == official, (d, why)
        # A fine-tune in the cache is never the default source, only named.
        hf_unc = bf16(hub / "models--orcarouter--Qwen3.8-Flash-Next-Uncensored" / "snapshots" / "u1")
        assert mp.find_source(prof, hub, search=[out])[0] == official
        assert mp.find_source(prof, hub, repo="orcarouter/Qwen3.8-Flash-Next-Uncensored")[0] == hf_unc
        # A variant matches its suffix case-insensitively: the HF repo, or a local folder.
        assert mp.find_source(prof, hub, variant="uncensored", search=[out])[0] == hf_unc
        local_unc = bf16(out / "Qwen3.8-Flash-Next-uncensored")
        d, why = mp.find_source(prof, hub, variant="uncensored", search=[out])
        assert d is None and any("several sources" in w for w in why), why      # both exist: ambiguous
        shutil.rmtree(hf_unc.parent.parent)
        assert mp.find_source(prof, hub, variant="uncensored", search=[out])[0] == local_unc
        d, why = mp.find_source(prof, hub, variant="abliterated", search=[out])
        assert d is None and any("Qwen3.8-Flash-Next-abliterated" in w for w in why), why
        assert mp.source_problem(prof, bf16(tmp / "other", arch="llama")) == "not a qwen4_exp checkpoint"
        print("ok   source: official by default, a variant by its suffix (folder or HF repo), ambiguity refused")

        # Generators: the official model's and the variant's quants never mix.
        quant(out / "Qwen3.8-Flash-Next-oQ6e-coder", 6)
        time.sleep(0.01)
        o5 = quant(out / "Qwen3.8-Flash-Next-oQ5e-gen", 5)
        u6 = quant(out / "Qwen3.8-Flash-Next-uncensored-oQ6e", 6)
        quant(out / "Qwen3.8-Flash-Next-oQ4t-v1", 4)              # an oQ-T output: never a generator
        quant(out / "Qwen3.8-Flash-Next-oQ5e-v1-cmp", 5)          # a comparison build: never
        assert mp.find_generator(prof, None, [out])[0] == o5        # oQ5 before oQ6
        assert mp.find_generator(prof, "uncensored", [out])[0] == u6
        assert mp.find_generator(prof, "abliterated", [out])[0] is None
        served = tmp / "omlx-models"; served.mkdir()
        (served / "gen").symlink_to(out / "Qwen3.8-Flash-Next-oQ6e-coder")
        (served / "unc").symlink_to(u6)
        assert mp.find_generator(prof, None, [out], list(served.iterdir()))[0] == (out / "Qwen3.8-Flash-Next-oQ6e-coder").resolve()
        assert mp.find_generator(prof, "uncensored", [out], list(served.iterdir()))[0] == u6.resolve()
        print("ok   generator: <name>[-<variant>]-oQ<level> only, served quant first, oQ-T outputs never")

        # CLI as the shell scripts call it.
        r = subprocess.run([sys.executable, str(REPO / "scripts/model_profile.py"), "source", "--variant", "uncensored",
                            "--hub", str(hub), "--search", str(out)], capture_output=True, text=True)
        assert r.returncode == 0 and r.stdout.strip() == str(local_unc), r
        r = subprocess.run([sys.executable, str(REPO / "scripts/model_profile.py"), "info", "--variant", "uncensored"],
                           capture_output=True, text=True)
        assert "MODEL_VARIANT_NAME=Qwen3.8-Flash-Next-uncensored" in r.stdout, r.stdout
        print("ok   CLI: source, info")

        # prep: request settings come from the profile, matched by the served name.
        p = prep.model_profile("Qwen3.8-Flash-Next-uncensored-oQ6e", None)
        assert p["effort"]["max"] == "xhigh" and p["thinking_off"] == {"enable_thinking": False}, p
        try:
            prep.model_profile("Llama-9-oQ4", None); raise AssertionError("unknown model must fail")
        except SystemExit as e:
            assert "--model-profile" in str(e)
        print("ok   prep: request settings from the profile; unknown models fail loudly")

        # results: agent comparison and the table.
        gen, qd = tmp / "gen", tmp / "q"
        for d, solved in ((gen, {"a": [1, 1], "b": [1, 0]}), (qd, {"a": [1, 0], "b": [1, 1]})):
            d.mkdir()
            rows = [{"task": t, "check_passed": bool(v)} for t, vs in solved.items() for v in vs]
            (d / "agent-sessions.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
        rj = tmp / "render.json"; rj.write_text(json.dumps({"heldout": {"agent": {"units": ["b"]}}}))
        r = subprocess.run([sys.executable, str(REPO / "scripts/results.py"), "agent-eval", "--generator", str(gen),
                            "--quant", str(qd), "--render", str(rj), "--json", str(tmp / "ae.json")],
                           capture_output=True, text=True)
        assert r.returncode == 0 and "quant solved 3/4 (75%), generator 3/4 (75%)" in r.stdout, r.stdout + r.stderr
        assert "held-out tasks (b): quant 2/2" in r.stdout and "worse on: a 2/2->1/2" in r.stdout, r.stdout
        oqup = tmp / "oqup"
        for name, kl, created in (("v1", 0.050, "2026-11-01"), ("v2", 0.070, "2026-11-02")):
            run = oqup / "runs" / name; run.mkdir(parents=True)
            res = {"run": name, "model": "qwen3.8-flash-next", "variant": "", "level": 4, "created": created,
                   "quant": str(out / f"Qwen3.8-Flash-Next-oQ4t-{name}"), "gb": 50.0,
                   "m3": {"written_kl": kl, "written_top1": 0.88, "kl": kl, "top1": 0.88}}
            (run / "result.json").write_text(json.dumps(res))
        r = subprocess.run([sys.executable, str(REPO / "scripts/results.py"), "vs-previous", "--oqup", str(oqup),
                            "--run", str(oqup / "runs" / "v2")], capture_output=True, text=True)
        assert "WARNING: worse than run v1: KL 0.0500 -> 0.0700" in r.stdout, r.stdout + r.stderr
        assert results.main(["table", "--oqup", str(oqup)]) == 0
        print("ok   results: agent eval per task, table, regression against the previous run")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("all model profile checks passed")


if __name__ == "__main__":
    main()
