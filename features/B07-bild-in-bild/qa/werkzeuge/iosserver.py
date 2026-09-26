#!/usr/bin/env python3
"""B07-QA: lokaler Stream-Mock für die iOS-Simulator-Läufe (nur 127.0.0.1, Medien ohne Tonspur).

/list.m3u                      M3U mit vier Sendern (Live-HLS, zweiter Live-HLS, VOD-HLS, roher TS)
/livehls/<id>/index.m3u8       Live-HLS mit gleitendem Fenster (2-s-Segmente aus qa-media/hls)
/livehls/<id>/segNNNNN.ts      Segment
/hls/...                       VOD-HLS statisch
/stream.ts                     roher MPEG-TS (360 s), statisch
Jede Anfrage wird mit Zeit, Client-Port und Pfad in logs/iosserver.log geschrieben.
"""
import http.server, socketserver, os, sys, time, datetime, re, threading

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18917
ROOT = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(ROOT, "qa-media")
LOG = open(os.path.join(ROOT, "logs", "iosserver.log"), "a", buffering=1)
START = time.time()
SEGS = sorted(f for f in os.listdir(os.path.join(MEDIA, "hls")) if f.endswith(".ts"))
LOCK = threading.Lock()


def log(line):
    with LOCK:
        LOG.write(datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3] + " " + line + "\n")


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def send(self, code, ctype, body, extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        log(f"{self.client_address[1]} {self.command} {self.path} ua={self.headers.get('User-Agent','')[:60]}")
        base = f"http://127.0.0.1:{PORT}"
        if path == "/list.m3u":
            body = ("#EXTM3U\n"
                    f"#EXTINF:-1 tvg-id=\"qa.live\" group-title=\"QA\",QA HLS Live\n{base}/livehls/ios1/index.m3u8\n"
                    f"#EXTINF:-1 tvg-id=\"qa.zwei\" group-title=\"QA\",QA HLS Zwei\n{base}/livehls/ios2/index.m3u8\n"
                    f"#EXTINF:-1 tvg-id=\"qa.vod\" group-title=\"QA\",QA HLS VOD\n{base}/hls/vod.m3u8\n"
                    f"#EXTINF:-1 tvg-id=\"qa.ts\" group-title=\"QA\",QA TS\n{base}/stream.ts\n"
                    f"#EXTINF:-1 tvg-id=\"qa.geheim\" group-title=\"QA\",QA Geheimsender\n{base}/live/qa-user/qa-pass-123/401.m3u8\n").encode()
            return self.send(200, "audio/x-mpegurl", body)
        m = re.match(r"^/livehls/([^/]+)/(.+)$", path) or re.match(r"^/live/[^/]+/([^/]+)/(.+)$", path)
        if m:
            last = m.group(2)
            if last.endswith(".m3u8") or last.endswith(".m3u"):
                seq = int((time.time() - START) / 2.0)
                lines = ["#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-TARGETDURATION:2", f"#EXT-X-MEDIA-SEQUENCE:{seq}"]
                for i in range(seq, seq + 6):
                    lines += ["#EXTINF:2.000000,", "seg%05d.ts" % i]
                return self.send(200, "application/vnd.apple.mpegurl", ("\n".join(lines) + "\n").encode(), {"Cache-Control": "no-cache"})
            n = re.search(r"\d+", last)
            if n:
                with open(os.path.join(MEDIA, "hls", SEGS[int(n.group(0)) % len(SEGS)]), "rb") as f:
                    return self.send(200, "video/mp2t", f.read())
        if path.startswith("/hls/") or path == "/stream.ts":
            fp = os.path.join(MEDIA, path.lstrip("/"))
            if os.path.isfile(fp):
                ctype = "application/vnd.apple.mpegurl" if fp.endswith(".m3u8") else "video/mp2t"
                with open(fp, "rb") as f:
                    return self.send(200, ctype, f.read())
        self.send(404, "text/html", b"<h1>404</h1>")


class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    log(f"start port={PORT}")
    S(("127.0.0.1", PORT), H).serve_forever()
