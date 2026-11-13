"""Stand-in oMLX server: /health, derive (thinking off) and generate (thinking on)."""
import json, sys, threading, time, os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
PORT = int(sys.argv[1]); DELAY = float(os.environ.get("STUB_DELAY", "0"))
COUNTER = sys.argv[2]
lock = threading.Lock()
def bump(kind):
    with lock:
        d = json.load(open(COUNTER)) if os.path.exists(COUNTER) else {}
        d[kind] = d.get(kind, 0) + 1
        json.dump(d, open(COUNTER, "w"))
        return d[kind]
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, obj, code=200):
        data = json.dumps(obj).encode(); self.send_response(code)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(data)))
        self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        self._send({"status": "ok"} if self.path == "/health" else {"data": []})
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        kw = body.get("chat_template_kwargs") or {}
        system = body["messages"][0]["content"] if body["messages"][0]["role"] == "system" else ""
        if kw.get("enable_thinking") is False and "realistic requests" in system:
            bump("seed")
            topic = body["messages"][-1]["content"][:60].lower()
            items = []
            for i in range(8):
                item = {"prompt": f"request {i} about {topic}: please help me with this in detail."}
                if '"tools"' in system:
                    item["tools"] = [{"type": "function", "function": {
                        "name": f"lookup_{i}", "description": "look something up",
                        "parameters": {"type": "object", "properties": {"q": {"type": "string"}},
                                       "required": ["q"]}}}]
                items.append(item)
            msg = {"role": "assistant", "content": json.dumps(items)}
            return self._send({"choices": [{"message": msg, "finish_reason": "stop"}],
                               "usage": {"completion_tokens": 200}})
        if kw.get("enable_thinking") is False:
            n = bump("derive")
            notes = body["messages"][-1]["content"].split("Reference notes:\n\n", 1)[-1]
            topic = notes.splitlines()[0][:50].lower()
            msg = {"role": "assistant", "content": f"how should i approach {topic} in my project, and how do i check it works?"}
            return self._send({"choices": [{"message": msg, "finish_reason": "stop"}], "usage": {"completion_tokens": 20}})
        n = bump("generate"); time.sleep(DELAY)
        effort = kw.get("reasoning_effort")
        tool_names = [t["function"]["name"] for t in body.get("tools") or []]
        if "finish" in tool_names and "run" in tool_names:
            # Scripted coding agent: explore, fix, verify, finish.
            k = bump("agent")
            if os.environ.get("STUB_BAD_TOOL_CALLS") and k in (2, 3):
                # A tool call the server cannot parse: oMLX reports it in a 200 body
                # once the response has started, or as an HTTP 500 before.
                err = {"error": {"message": "Model output contains an unrecoverable tool call.",
                                 "type": "server_error", "code": "invalid_tool_call"}}
                return self._send(err, 200 if k == 2 else 500)
            done = sum(1 for m in body["messages"] if m["role"] == "tool")
            script = [("list_files", {"path": "."}),
                      ("write_file", {"path": "answer.txt", "content": "42\n"}),
                      ("run", {"command": "cat answer.txt"}),
                      ("finish", {"summary": "wrote the answer and checked it"})]
            if done >= len(script):
                msg = {"role": "assistant", "content": "done"}
            else:
                name, args = script[done]
                msg = {"role": "assistant", "content": "",
                       "reasoning_content": f"step {done}: use {name} next.",
                       "tool_calls": [{"id": f"call_{done}", "type": "function",
                                       "function": {"name": name, "arguments": json.dumps(args)}}]}
            return self._send({"choices": [{"message": msg, "finish_reason": "tool_calls"}],
                               "usage": {"completion_tokens": 25}})
        if body.get("tools"):
            name = body["tools"][0]["function"]["name"]
            msg = {"role": "assistant", "content": "",
                   "reasoning_content": "the user needs data, so call the tool with the query.",
                   "tool_calls": [{"id": "call_1", "type": "function",
                                   "function": {"name": name, "arguments": "{\"q\": \"x\"}"}}]}
            return self._send({"choices": [{"message": msg, "finish_reason": "tool_calls"}],
                               "usage": {"completion_tokens": 30}})
        if n % 11 == 0:
            reasoning, content = "loop " * 2000, "x"
        elif n % 13 == 0:
            reasoning, content = "", "i can't help with that."
        else:
            q = body["messages"][-1]["content"][:60].lower()
            reasoning = f"effort {effort}. first read the request: {q}. then check the constraints and plan the answer step by step."
            content = f"here is the answer for: {q}. use a small, tested change and verify it with a focused test."
        msg = {"role": "assistant", "content": content, "reasoning_content": reasoning}
        self._send({"choices": [{"message": msg, "finish_reason": "stop"}],
                    "usage": {"completion_tokens": (len(reasoning) + len(content)) // 4}})
ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
