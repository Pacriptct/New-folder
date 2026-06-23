#!/usr/bin/env python3
"""
Birdwatchers Pasta & Stuff — local server + QR code.

Just run:   python3 serve.py

It will:
  1. Serve this website on your local network.
  2. Print the address (and a scannable QR code) so phones on the same
     Wi-Fi can open it.
  3. Open a /qr page you can show on screen for people to scan.

Zero installation needed — the QR library is bundled in ./vendor.
"""

import http.server
import socket
import socketserver
import sys
import os
import io

# --- make the bundled pyqrcode importable (no pip install required) ---
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "vendor"))
os.chdir(HERE)  # serve files relative to this folder

import pyqrcode  # noqa: E402

PORT = int(os.environ.get("PORT", "8000"))


def get_lan_ip():
    """Best-effort local network IP (so phones on the same Wi-Fi can reach us)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))  # no packets actually sent
        ip = s.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
    finally:
        s.close()
    return ip


def terminal_qr(url):
    """Return a QR code drawn with block characters for the terminal."""
    qr = pyqrcode.create(url, error="M")
    return qr.terminal(module_color="black", background="white", quiet_zone=2)


def qr_svg(url):
    """Return an SVG string of the QR code for the /qr web page."""
    qr = pyqrcode.create(url, error="M")
    buf = io.BytesIO()
    qr.svg(buf, scale=8, module_color="#241810", background="#f6ead7", quiet_zone=3)
    return buf.getvalue().decode("utf-8")


class Handler(http.server.SimpleHTTPRequestHandler):
    # set by main()
    site_url = ""

    def do_GET(self):
        if self.path.rstrip("/") == "/qr":
            self.send_qr_page()
            return
        super().do_GET()

    def send_qr_page(self):
        svg = qr_svg(self.site_url)
        html = """<!DOCTYPE html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Scan to visit · Birdwatchers</title>
<style>
  body{{margin:0;min-height:100vh;display:grid;place-items:center;
       background:#120c08;color:#f6ead7;
       font-family:system-ui,sans-serif;text-align:center;padding:24px}}
  .card{{background:#241810;border:1px solid rgba(224,166,78,.25);
         border-radius:28px;padding:40px clamp(24px,6vw,56px);
         box-shadow:0 24px 60px rgba(0,0,0,.5)}}
  h1{{font-size:1.6rem;margin:0 0 6px}}
  p{{color:#c7b59a;margin:0 0 26px}}
  .qr{{background:#f6ead7;padding:18px;border-radius:18px;display:inline-block;width:min(74vw,340px)}}
  .qr svg{{width:100%;height:auto;display:block}}
  .url{{margin-top:22px;color:#f2c97a;font-size:1rem;word-break:break-all}}
</style></head><body>
  <div class="card">
    <h1>🐦 Birdwatchers Pasta &amp; Stuff</h1>
    <p>Point your camera here to open the menu</p>
    <div class="qr">{svg}</div>
    <div class="url">{url}</div>
  </div>
</body></html>""".format(svg=svg, url=self.site_url)
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # keep the console clean


def main():
    ip = get_lan_ip()
    site_url = "http://{}:{}/".format(ip, PORT)
    qr_url = "http://{}:{}/qr".format(ip, PORT)
    Handler.site_url = site_url

    line = "=" * 54
    print("\n" + line)
    print("  🐦  Birdwatchers Pasta & Stuff is LIVE")
    print(line)
    print("\n  On this computer : http://localhost:{}/".format(PORT))
    print("  On your phone    : {}".format(site_url))
    print("  Big QR to show   : {}\n".format(qr_url))
    print("  Scan this with a phone camera (same Wi-Fi):\n")
    try:
        print(terminal_qr(site_url))
    except Exception as e:
        print("  (couldn't draw QR in terminal: {})".format(e))
    print("  Tip: open the 'Big QR to show' link on screen for guests.")
    print("  Press Ctrl+C to stop.\n" + line + "\n")

    socketserver.TCPServer.allow_reuse_address = True
    try:
        with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n  Closing up. Thanks for dining! 🐦\n")
    except OSError as e:
        print("\n  Couldn't start on port {} ({}).".format(PORT, e))
        print("  Try a different port:  PORT=8080 python3 serve.py\n")


if __name__ == "__main__":
    main()
