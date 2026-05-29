import base64
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent.parent
DASHBOARD_FILE = ROOT / "dashboard" / "index.html"
IRIS_BASE = os.getenv("CARDIOFLOW_IRIS_BASE", "http://localhost:52773")
IRIS_USER = os.getenv("CARDIOFLOW_IRIS_USER", "cardioapi")
IRIS_PASSWORD = os.getenv("CARDIOFLOW_IRIS_PASSWORD", "Cardio123!")
HOST = os.getenv("CARDIOFLOW_PROXY_HOST", "127.0.0.1")
PORT = int(os.getenv("CARDIOFLOW_PROXY_PORT", "8787"))


def build_auth_header() -> str:
    token = base64.b64encode(f"{IRIS_USER}:{IRIS_PASSWORD}".encode("utf-8")).decode("ascii")
    return f"Basic {token}"


class CardioFlowProxyHandler(BaseHTTPRequestHandler):
    server_version = "CardioFlowProxy/1.0"

    def do_GET(self):
        if self.path == "/" or self.path.startswith("/index.html"):
            self.serve_dashboard()
            return
        if self.path.startswith("/api/cardio/"):
            self.proxy_to_iris()
            return
        self.send_error(404, "Not found")

    def do_HEAD(self):
        if self.path == "/" or self.path.startswith("/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            return
        if self.path.startswith("/api/cardio/"):
            self.proxy_to_iris(head_only=True)
            return
        self.send_error(404, "Not found")

    def log_message(self, format, *args):
        return

    def serve_dashboard(self):
        if not DASHBOARD_FILE.exists():
            self.send_error(500, "Dashboard file not found")
            return
        payload = DASHBOARD_FILE.read_text(encoding="utf-8").encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def proxy_to_iris(self, head_only: bool = False):
        target = f"{IRIS_BASE}{self.path}"
        request = Request(target, method="GET")
        request.add_header("Authorization", build_auth_header())
        try:
            with urlopen(request, timeout=30) as response:
                body = response.read()
                self.send_response(response.status)
                for header, value in response.getheaders():
                    if header.lower() in {"transfer-encoding", "connection", "content-length", "content-encoding"}:
                        continue
                    self.send_header(header, value)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                if not head_only:
                    self.wfile.write(body)
        except HTTPError as error:
            body = error.read()
            self.send_response(error.code)
            self.send_header("Content-Type", error.headers.get("Content-Type", "application/json; charset=utf-8"))
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if not head_only:
                self.wfile.write(body)
        except URLError as error:
            payload = f'{{"error":"IRIS upstream unavailable","detail":"{error.reason}"}}'.encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            if not head_only:
                self.wfile.write(payload)


def main():
    server = ThreadingHTTPServer((HOST, PORT), CardioFlowProxyHandler)
    print(f"CardioFlow proxy running on http://{HOST}:{PORT}")
    print(f"Proxying IRIS API from {IRIS_BASE}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
