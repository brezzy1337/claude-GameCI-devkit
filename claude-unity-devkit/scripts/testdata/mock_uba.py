"""Mock of the UBA v2 endpoints uba-build.sh uses (for scripts/test-uba-build.sh). argv: PORT SCENARIO (ok|fail|limit|auth)."""
import base64, json, re, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT, SCENARIO = int(sys.argv[1]), sys.argv[2]
state = {"posts": 0, "polls": 0}
TP = r"^/v2/orgs/ORG/projects/PROJ/buildtargets/win"


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body=None, headers=None, raw=None):
        self.send_response(code)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else b"")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authed(self):
        want = "Basic " + base64.b64encode(b"KEY:SECRET").decode()
        return self.headers.get("Authorization") == want

    def do_GET(self):
        p = self.path
        if p.startswith("/signed/"):
            return self.send(200, raw=(b"log line\n" * 5 + b"error CS0103: boom\n") if "log" in p else b"ZIPDATA")
        if not self.authed():
            return self.send(401, {"detail": "no auth"})
        if p == "/v2/orgs/ORG/free-tier-status":
            if SCENARIO == "auth":
                return self.send(403, {"title": "Forbidden"})
            return self.send(200, {"freeTierLimitReached": SCENARIO == "limit"})
        if re.match(TP + r"/builds/7/log$", p):
            return self.send(307, headers={"Location": f"http://127.0.0.1:{PORT}/signed/log"})
        if re.match(TP + r"/builds/7/artifacts$", p):
            return self.send(200, [{"key": "primary", "primary": True, "files": [{"filename": "win/Game build.zip"}]}])
        if re.match(TP + r"/builds/7/download/", p):
            assert "Game%20build.zip" in p, p
            return self.send(303, {"url": f"http://127.0.0.1:{PORT}/signed/file"})
        if re.match(TP + r"/builds/7(\?.*)?$", p):
            state["polls"] += 1
            final = "success" if SCENARIO == "ok" else "failure"
            status = ["queued", "started", final][min(state["polls"] - 1, 2)]
            body = {"build": 7, "buildStatus": status, "queuedReason": "waitingForBuildAgent" if status == "queued" else None}
            if "include=" in p:
                body.update({"scmBranch": "stable", "lastBuiltRevision": "abcdef1234567890", "billableTimeInSeconds": 754,
                             "testResults": {"unit_test_editmode": {"passed": 12, "failed": 0},
                                             "unit_test_playmode": {"passed": 3, "failed": 0 if SCENARIO == "ok" else 1}},
                             "failureDetails": [] if SCENARIO == "ok" else [{"label": "Tests", "message": "1 PlayMode test failed"}]})
            return self.send(200, body)
        self.send(404, {"detail": "not mocked: " + p})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        if not self.authed():
            return self.send(401, {})
        if re.match(TP + r"/builds$", self.path):
            state["posts"] += 1
            assert body["clean"] is False and body["branch"] == "feature/x" and body["commit"] == "c0ffee", body
            if state["posts"] == 1:
                return self.send(409, {"detail": "pending"})
            return self.send(202, [{"build": 7, "buildStatus": "created"}])
        self.send(404, {})


HTTPServer(("127.0.0.1", PORT), H).serve_forever()
