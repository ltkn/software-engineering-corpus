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
        if kw.get("enable_thinking") is False:
            n = bump("derive")
            notes = body["messages"][-1]["content"].split("Reference notes:\n\n", 1)[-1]
            topic = notes.splitlines()[0][:50].lower()
            msg = {"role": "assistant", "content": f"how should i approach {topic} in my project, and how do i check it works?"}
            return self._send({"choices": [{"message": msg, "finish_reason": "stop"}], "usage": {"completion_tokens": 20}})
        n = bump("generate"); time.sleep(DELAY)
        effort = kw.get("reasoning_effort")
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
