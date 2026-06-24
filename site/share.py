#!/usr/bin/env python3
"""
Birdwatchers Pasta & Stuff — share it with family anywhere.

This starts the website AND opens a temporary public link (via Cloudflare)
so people NOT on your Wi-Fi can visit. Your photos never leave your Mac —
they're streamed live from this computer while the link is open.

Run:   python3 share.py

You'll get a public link like  https://something.trycloudflare.com
plus a QR code you can text to family. The link works as long as this
stays running. Press Ctrl+C to close it down.

One-time setup (installs the free tunnel tool):
    brew install cloudflared
"""

import http.server
import socketserver
import threading
import subprocess
import sys
import os
import re
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "vendor"))
os.chdir(HERE)

import pyqrcode  # noqa: E402

PORT = int(os.environ.get("PORT", "8000"))
URL_RE = re.compile(r"https://[-a-z0-9]+\.trycloudflare\.com")


def start_local_server():
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("127.0.0.1", PORT), QuietHandler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def announce(url):
    line = "=" * 58
    print("\n" + line)
    print("  🐦  Your site is LIVE on the internet!")
    print(line)
    print("\n  Share this link with family back home:\n")
    print("      " + url + "\n")
    print("  Or have them scan this with their phone camera:\n")
    try:
        qr = pyqrcode.create(url, error="M")
        print(qr.terminal(module_color="black", background="white", quiet_zone=2))
    except Exception as e:
        print("  (couldn't draw QR: {})".format(e))
    print("  This link stays up while this window is open.")
    print("  Press Ctrl+C here to take the site offline.\n" + line + "\n")


def install_hint():
    print("\n  ⚠  'cloudflared' isn't installed yet — it's the free tool that")
    print("     creates the public link. Install it once with:\n")
    print("        brew install cloudflared\n")
    print("  Don't have Homebrew? Install it first from https://brew.sh, then")
    print("  run the command above. After that, run:  python3 share.py\n")


def main():
    if not shutil.which("cloudflared"):
        install_hint()
        return

    start_local_server()
    print("\n  Starting the website and opening a public link...")
    print("  (this can take 5–15 seconds)\n")

    proc = subprocess.Popen(
        ["cloudflared", "tunnel", "--url", "http://localhost:{}".format(PORT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    public_url = None
    try:
        for line in proc.stdout:
            if public_url is None:
                m = URL_RE.search(line)
                if m:
                    public_url = m.group(0)
                    announce(public_url)
        # tunnel process ended on its own
        if public_url is None:
            print("\n  Couldn't open the public link. Check your internet and")
            print("  try again. (Run 'cloudflared --version' to confirm install.)\n")
    except KeyboardInterrupt:
        print("\n  Closing the public link. Thanks for sharing! 🐦\n")
    finally:
        proc.terminate()


if __name__ == "__main__":
    main()
