#!/usr/bin/env python3
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os, threading

ROOT = Path(__file__).resolve().parents[2] / 'build' / 'web'
HOST = os.environ.get('HOST', '0.0.0.0')
PORTS = [int(p) for p in os.environ.get('PORTS', '3000,3001').split(',') if p.strip()]

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_HEAD(self):
        path = self.translate_path(self.path.split('?',1)[0])
        if os.path.isdir(path):
            index = os.path.join(path, 'index.html')
            if os.path.exists(index):
                base = self.path.split('?',1)[0].rstrip('/')
                qs = ''
                if '?' in self.path:
                    qs = '?' + self.path.split('?',1)[1]
                self.path = base + '/index.html' + qs
        return SimpleHTTPRequestHandler.do_HEAD(self)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

    def log_message(self, fmt, *args):
        print("[%s] %s" % (self.log_date_time_string(), fmt % args), flush=True)

def serve(port):
    httpd = ThreadingHTTPServer((HOST, port), Handler)
    print(f'Serving {ROOT} at http://{HOST}:{port}/', flush=True)
    httpd.serve_forever()

if __name__ == '__main__':
    if not ROOT.exists():
        raise SystemExit(f'missing build output: {ROOT}')
    threads=[]
    for port in PORTS:
        t=threading.Thread(target=serve, args=(port,), daemon=True)
        t.start(); threads.append(t)
    for t in threads:
        t.join()
