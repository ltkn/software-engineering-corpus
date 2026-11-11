#!/usr/bin/env python3
"""test_agent_harness.py — the agent stage end to end with a scripted stand-in
model: local sandbox always, Docker sandbox when Docker is available.

    python3 scripts/testing/test_agent_harness.py
"""
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
PREP = REPO / "scripts" / "prep_calibration.py"


def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close(); return port


def make_task(root: Path, image: str):
    t = root / "tasks" / "answer-42"
    (t / "repo").mkdir(parents=True)
    (t / "repo" / "README.md").write_text("Write the answer to answer.txt.\n")
    (t / "task.json").write_text(json.dumps({
        "id": "answer-42", "domain": "test", "image": image,
        "prompt": "Write 42 into answer.txt and verify it.", "check": "grep -qx 42 answer.txt"}))
    return root / "tasks"


def run(sandbox: str, image: str, tmp: Path):
    port = free_port()
    counter = tmp / f"counter-{sandbox}.json"
    srv = subprocess.Popen([sys.executable, "-I", str(HERE / "stub_omlx.py"), str(port), str(counter)])
    try:
        time.sleep(0.8)
        tasks = make_task(tmp / sandbox, image)
        out = tmp / f"out-{sandbox}"
        cmd = [sys.executable, str(PREP), "agent", "--out", str(out), "--model", "Qwen-test",
               "--server", f"http://127.0.0.1:{port}", "--agent-tasks", str(tasks),
               "--agent-samples", "2", "--sandbox", sandbox, "--cache-root", str(tmp / "cache")]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        assert r.returncode == 0, r.stdout + r.stderr
        summary = json.loads((out / "answers" / "Qwen-test" / "agent.json").read_text())
        assert summary["kept"] == 2 and summary["solved"] == 2, summary
        sessions = [json.loads(l) for l in (out / "answers" / "Qwen-test" / "agent-sessions.jsonl").open()]
        roles = [m["role"] for m in sessions[0]["messages"]]
        assert roles[:2] == ["system", "user"] and roles.count("tool") == 4, roles
        tool_out = [m["content"] for m in sessions[0]["messages"] if m["role"] == "tool"]
        assert any("42" in c for c in tool_out), tool_out          # the run tool really executed
        # Rerun: every session comes from the cache, no new model calls.
        before = json.loads(counter.read_text())["agent"]
        r2 = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        assert r2.returncode == 0 and json.loads(counter.read_text())["agent"] == before
        print(f"ok   agent stage with {sandbox} sandbox: 2/2 sessions kept and solved, rerun fully cached")
    finally:
        srv.terminate()


def main():
    tmp = Path(tempfile.mkdtemp(dir=Path.home(), prefix=".oqt-agent-test."))  # colima mounts $HOME
    try:
        run("local", "unused", tmp)
        if shutil.which("docker") and subprocess.run(["docker", "info"], capture_output=True).returncode == 0:
            if subprocess.run(["docker", "image", "inspect", "alpine:latest"], capture_output=True).returncode != 0:
                subprocess.run(["docker", "pull", "-q", "alpine:latest"], check=True)
            run("docker", "alpine:latest", tmp)
            left = subprocess.run(["docker", "ps", "-aq", "--filter", "name=oqt-agent-"],
                                  capture_output=True, text=True).stdout.strip()
            assert not left, f"containers left behind: {left}"
            print("ok   no sandbox containers left behind")
        else:
            print("skip docker sandbox (Docker not available)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("all agent harness checks passed")


if __name__ == "__main__":
    main()
