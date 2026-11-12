#!/usr/bin/env python3
"""agent_harness.py — run the served model as a coding agent on a task repo.

Used by prep_calibration.py's ``agent`` stage (PREP_PLAN.md §5). A session:

  1. copies the task's repo into a fresh work directory
  2. starts a sandbox (Docker by default: --network none, the work dir
     mounted at /work, the task's toolchain image)
  3. loops: the model (thinking on, native tool calls) reads, searches,
     edits and runs commands through a small tool set until it calls
     ``finish``, answers without a tool call, or hits the step/context cap
  4. runs the task's ``check`` command to record whether it really worked
  5. returns the whole transcript (thinking, tool calls, tool output)

Standard library only. The model never touches the host: file tools are
confined to the work directory and commands run inside the sandbox.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
import uuid
from pathlib import Path

TOOLS = [
    {"type": "function", "function": {
        "name": "list_files", "description": "List files under a directory of the repository (depth 3).",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "description": "Directory relative to the repository root", "default": "."}}}}},
    {"type": "function", "function": {
        "name": "read_file", "description": "Read a text file with line numbers.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"},
            "start_line": {"type": "integer", "description": "First line (1-based)"},
            "end_line": {"type": "integer", "description": "Last line (inclusive)"}},
            "required": ["path"]}}},
    {"type": "function", "function": {
        "name": "search", "description": "Search file contents for a regular expression.",
        "parameters": {"type": "object", "properties": {
            "pattern": {"type": "string"}, "path": {"type": "string", "default": "."}},
            "required": ["pattern"]}}},
    {"type": "function", "function": {
        "name": "write_file", "description": "Create or overwrite a file with the given content.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}}},
    {"type": "function", "function": {
        "name": "edit_file", "description": "Replace exactly one occurrence of old_text with new_text in a file.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "old_text": {"type": "string"}, "new_text": {"type": "string"}},
            "required": ["path", "old_text", "new_text"]}}},
    {"type": "function", "function": {
        "name": "run", "description": "Run a shell command in the repository (no network). Returns exit code and output.",
        "parameters": {"type": "object", "properties": {"command": {"type": "string"}},
                       "required": ["command"]}}},
    {"type": "function", "function": {
        "name": "finish", "description": "Finish the task with a short summary of what was done and verified.",
        "parameters": {"type": "object", "properties": {"summary": {"type": "string"}},
                       "required": ["summary"]}}},
]

SYSTEM = (
    "You are a coding agent working in a repository at /work. Use the tools to explore the code, "
    "make focused changes, and run the tests to verify them. The sandbox has no network access: "
    "everything you need is already installed. When the task is done and verified, call finish "
    "with a short summary."
)

MAX_OUTPUT = 6000


def _clip(text: str, limit: int = MAX_OUTPUT) -> str:
    if len(text) <= limit:
        return text
    head, tail = text[: limit // 2], text[-limit // 2 :]
    return f"{head}\n... [{len(text) - limit} characters omitted] ...\n{tail}"


class LocalSandbox:
    """Runs commands directly on the host in the work dir. Tests only."""

    def __init__(self, workdir: Path, image: str | None = None):
        self.workdir = workdir

    def start(self):
        return self

    def run(self, command: str, timeout: int = 120) -> tuple[int, str]:
        try:
            p = subprocess.run(["sh", "-c", command], cwd=self.workdir, capture_output=True,
                               text=True, timeout=timeout)
            return p.returncode, (p.stdout + p.stderr)
        except subprocess.TimeoutExpired as e:
            return 124, f"{(e.stdout or '')}{(e.stderr or '')}\n[timed out after {timeout}s]"

    def stop(self):
        pass


class DockerSandbox:
    """One container per session: --network none, work dir mounted at /work."""

    def __init__(self, workdir: Path, image: str):
        self.workdir = workdir
        self.image = image
        self.name = f"oqt-agent-{uuid.uuid4().hex[:12]}"

    def start(self):
        subprocess.run(["docker", "run", "-d", "--rm", "--name", self.name, "--network", "none",
                        "--memory", "2g", "--cpus", "2", "-v", f"{self.workdir}:/work", "-w", "/work",
                        self.image, "sleep", "infinity"], check=True, capture_output=True, text=True)
        return self

    def run(self, command: str, timeout: int = 120) -> tuple[int, str]:
        try:
            p = subprocess.run(["docker", "exec", self.name, "sh", "-c", command],
                               capture_output=True, text=True, timeout=timeout)
            return p.returncode, (p.stdout + p.stderr)
        except subprocess.TimeoutExpired as e:
            subprocess.run(["docker", "exec", self.name, "sh", "-c", "pkill -9 -f . || true"],
                           capture_output=True)
            return 124, f"{(e.stdout or '')}{(e.stderr or '')}\n[timed out after {timeout}s]"

    def stop(self):
        subprocess.run(["docker", "rm", "-f", self.name], capture_output=True)


SANDBOXES = {"docker": DockerSandbox, "local": LocalSandbox}


def load_task(task_dir: Path) -> dict:
    task = json.loads((task_dir / "task.json").read_text(encoding="utf-8"))
    task["dir"] = str(task_dir)
    files = sorted(p for p in (task_dir / "repo").rglob("*") if p.is_file())
    h = __import__("hashlib").sha256(json.dumps(
        {k: v for k, v in task.items() if k != "dir"}, sort_keys=True).encode())
    for p in files:
        h.update(str(p.relative_to(task_dir)).encode())
        h.update(p.read_bytes())
    task["hash"] = h.hexdigest()
    return task


class Tools:
    def __init__(self, workdir: Path, sandbox, command_timeout: int = 120):
        self.root = workdir.resolve()
        self.sandbox = sandbox
        self.command_timeout = command_timeout
        self.finished = None

    def _path(self, rel: str) -> Path:
        p = (self.root / (rel or ".")).resolve()
        if p != self.root and self.root not in p.parents:
            raise ValueError(f"path outside the repository: {rel}")
        return p

    def call(self, name: str, args: dict) -> str:
        try:
            if name == "list_files":
                base = self._path(args.get("path", "."))
                out = []
                for p in sorted(base.rglob("*")):
                    rel = p.relative_to(self.root)
                    if any(part.startswith(".git") for part in rel.parts) or len(rel.parts) > 3 + len(
                            base.relative_to(self.root).parts):
                        continue
                    out.append(str(rel) + ("/" if p.is_dir() else ""))
                return _clip("\n".join(out) or "(empty)")
            if name == "read_file":
                lines = self._path(args["path"]).read_text(encoding="utf-8", errors="replace").splitlines()
                a = max(1, int(args.get("start_line") or 1))
                b = min(len(lines), int(args.get("end_line") or a + 399))
                return _clip("\n".join(f"{i:5d}  {lines[i - 1]}" for i in range(a, b + 1)) or "(empty file)")
            if name == "search":
                import re
                rx = re.compile(args["pattern"])
                base = self._path(args.get("path", "."))
                hits = []
                for p in sorted(base.rglob("*") if base.is_dir() else [base]):
                    if not p.is_file() or ".git" in p.parts:
                        continue
                    for i, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                        if rx.search(line):
                            hits.append(f"{p.relative_to(self.root)}:{i}: {line}")
                            if len(hits) >= 100:
                                break
                return _clip("\n".join(hits) or "no matches")
            if name == "write_file":
                p = self._path(args["path"])
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(args["content"], encoding="utf-8")
                return f"wrote {args['path']} ({len(args['content'])} characters)"
            if name == "edit_file":
                p = self._path(args["path"])
                text = p.read_text(encoding="utf-8")
                n = text.count(args["old_text"])
                if n != 1:
                    return f"error: old_text found {n} times in {args['path']} (must be exactly once)"
                p.write_text(text.replace(args["old_text"], args["new_text"]), encoding="utf-8")
                return f"edited {args['path']}"
            if name == "run":
                code, out = self.sandbox.run(args["command"], timeout=self.command_timeout)
                return _clip(f"exit code {code}\n{out}")
            if name == "finish":
                self.finished = args.get("summary", "")
                return "finished"
            return f"error: unknown tool {name}"
        except (KeyError, ValueError, OSError) as e:
            return f"error: {e}"


def run_session(task: dict, chat_fn, payload_base: dict, *, work_root: Path, sandbox_kind: str = "docker",
                max_steps: int = 30, max_context_chars: int = 400_000) -> dict:
    """Run one agent session. ``chat_fn(payload) -> response body`` talks to the server."""
    work = work_root / f"{task['id']}-{uuid.uuid4().hex[:8]}"
    shutil.copytree(Path(task["dir"]) / "repo", work)
    sandbox = SANDBOXES[sandbox_kind](work, task.get("image"))
    messages = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": task["prompt"]}]
    steps = tokens = 0
    stop_reason = "max steps"
    calls_seen: list[str] = []
    t0 = time.time()
    try:
        sandbox.start()
        for cmd in task.get("setup", []):
            sandbox.run(cmd, timeout=300)
        # Firmware builds (ESP-IDF, Arduino) need longer than the default per command.
        tools = Tools(work, sandbox, int(task.get("command_timeout", 120)))
        while steps < max_steps:
            steps += 1
            body = chat_fn({**payload_base, "messages": messages, "tools": TOOLS})
            choice = body["choices"][0]
            msg = choice.get("message") or {}
            tokens += int((body.get("usage") or {}).get("completion_tokens") or 0)
            assistant = {"role": "assistant", "content": msg.get("content") or ""}
            if msg.get("reasoning_content"):
                assistant["reasoning_content"] = msg["reasoning_content"]
            tool_calls = msg.get("tool_calls") or []
            if tool_calls:
                assistant["tool_calls"] = tool_calls
            messages.append(assistant)
            if not tool_calls:
                stop_reason = "answered"
                break
            for tc in tool_calls:
                fn = tc.get("function") or {}
                raw = fn.get("arguments") or "{}"
                try:
                    args = json.loads(raw) if isinstance(raw, str) else dict(raw)
                except ValueError:
                    args, result = None, "error: arguments are not valid JSON"
                if args is not None:
                    result = tools.call(fn.get("name", ""), args)
                calls_seen.append(f"{fn.get('name')}:{raw}")
                messages.append({"role": "tool", "tool_call_id": tc.get("id", ""),
                                 "name": fn.get("name", ""), "content": result})
            if tools.finished is not None:
                stop_reason = "finished"
                break
            if len(calls_seen) >= 4 and len(set(calls_seen[-4:])) == 1:
                stop_reason = "loop"
                break
            if sum(len(json.dumps(m)) for m in messages) > max_context_chars:
                stop_reason = "context limit"
                break
        check = task.get("check")
        passed = None
        if check:
            code, _ = sandbox.run(check, timeout=300)
            passed = code == 0
    finally:
        sandbox.stop()
        shutil.rmtree(work, ignore_errors=True)
    n_calls = sum(len(m.get("tool_calls") or []) for m in messages if m["role"] == "assistant")
    keep, why = True, "ok"
    if stop_reason == "loop":
        keep, why = False, "repeated tool call loop"
    elif n_calls == 0:
        keep, why = False, "no tool calls"
    return {"task": task["id"], "domain": task.get("domain"), "messages": messages, "tools": TOOLS,
            "steps": steps, "tool_calls": n_calls, "stop_reason": stop_reason, "check_passed": passed,
            "tokens": tokens, "seconds": round(time.time() - t0, 1), "keep": keep, "why": why}
