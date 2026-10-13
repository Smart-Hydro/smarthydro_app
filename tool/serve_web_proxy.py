#!/usr/bin/env python3
"""Servidor local de la build web con proxy same-origin hacia la API.

La API (api.smarthydro.app) emite cabeceras CORS para los orígenes
productivos (app.smarthydro.app, ikolu.smarthydro.app) y, para desarrollo,
para ``http://localhost:3000``. Servir la build desde otro puerto hace que
el preflight CORS falle y el login muestre "No fue posible conectar".

Este servidor deja la preview lista para probar con login real:

  1. Escucha en el puerto 3000, el origen local que la API ya autoriza.
  2. Sirve los estáticos de ``build/web`` (con fallback SPA a index.html).
  3. Reenvía ``/api/*`` a la API real como respaldo: una build compilada
     con ``--dart-define=SMART_HYDRO_API_BASE_URL=`` (base vacía = rutas
     relativas al mismo origen) opera sin CORS desde cualquier puerto.

Importante: abrir la preview como ``http://localhost:3000`` (no
``127.0.0.1``): la lista blanca de la API es por nombre de host.

Uso:

  flutter build web
  python3 tool/serve_web_proxy.py            # http://localhost:3000

Variables de entorno:

  PORT                    Puerto de escucha (3000 por defecto).
  SMART_HYDRO_PROXY_TARGET  Origen de la API destino
                            (https://api.smarthydro.app por defecto).
"""

from __future__ import annotations

import http.client
import mimetypes
import os
import posixpath
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "build" / "web"
TARGET = urllib.parse.urlparse(
    os.environ.get("SMART_HYDRO_PROXY_TARGET", "https://api.smarthydro.app")
)
PORT = int(os.environ.get("PORT", "3000"))

# Cabeceras de salto que no deben reenviarse entre extremos.
_HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length",
    "origin",
    "referer",
    "accept-encoding",
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "SmartHydroPreview/1.0"

    # ---------- API proxy ----------

    def _proxy(self) -> None:
        target = urllib.parse.urljoin(TARGET.geturl(), self.path)
        parsed = urllib.parse.urlparse(target)
        body = None
        length = self.headers.get("Content-Length")
        if length:
            body = self.rfile.read(int(length))

        headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in _HOP_BY_HOP
        }
        # El backend valida Origin/Referer contra su lista blanca.
        headers["Origin"] = f"{parsed.scheme}://{parsed.netloc}"
        headers["Referer"] = f"{parsed.scheme}://{parsed.netloc}/"

        connection = http.client.HTTPSConnection(parsed.netloc, timeout=30)
        path = parsed.path or "/"
        if parsed.query:
            path = f"{path}?{parsed.query}"
        try:
            connection.request(self.command, path, body=body, headers=headers)
            upstream = connection.getresponse()
            payload = upstream.read()
        except OSError:
            self.send_error(502, "API no alcanzable")
            return
        finally:
            connection.close()

        self.send_response(upstream.status)
        for key, value in upstream.getheaders():
            if key.lower() in _HOP_BY_HOP or key.lower() in (
                "access-control-allow-origin",
                "access-control-allow-credentials",
                "access-control-expose-headers",
                "access-control-allow-headers",
                "access-control-allow-methods",
                "access-control-max-age",
                "content-security-policy",
                "strict-transport-security",
                "x-frame-options",
                "content-length",
            ):
                continue
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)

    # ---------- Estáticos ----------

    def _serve_static(self) -> None:
        path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path)
        path = posixpath.normpath(path).lstrip("/")
        candidate = (ROOT / path).resolve()
        if ROOT not in candidate.parents and candidate != ROOT:
            self.send_error(403)
            return
        if not candidate.is_file():
            # Fallback SPA: cualquier ruta de la app vuelve a index.html.
            candidate = ROOT / "index.html"
        data = candidate.read_bytes()
        content_type, _ = mimetypes.guess_type(candidate.name)
        if candidate.name == "index.html":
            content_type = "text/html; charset=utf-8"
        self.send_response(200)
        self.send_header("Content-Type", content_type or "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        # La build ya versiona por hash; evitar caché agresiva en previews.
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    # ---------- Enrutado ----------

    def _dispatch(self) -> None:
        if self.path.startswith("/api/"):
            self._proxy()
        else:
            self._serve_static()

    do_GET = _dispatch
    do_HEAD = _dispatch
    do_POST = _dispatch
    do_PUT = _dispatch
    do_PATCH = _dispatch
    do_DELETE = _dispatch
    do_OPTIONS = _dispatch

    def log_message(self, fmt: str, *args: object) -> None:
        if not self.path.startswith("/api/"):
            return
        print("%s -> %s" % (self.address_string(), fmt % args))


def main() -> None:
    if not (ROOT / "index.html").is_file():
        raise SystemExit(
            f"No existe {ROOT}/index.html. Compila primero: "
            "flutter build web --dart-define=SMART_HYDRO_API_BASE_URL="
        )
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Preview en http://localhost:{PORT}  (API -> {TARGET.geturl()})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
