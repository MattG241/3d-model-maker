#!/usr/bin/env python3
"""promptmesh web UI — run a local app to generate 3D models for Roblox.

    python3 app.py            # opens http://localhost:8000 in your browser

Two modes in the UI:
  * Offline preview  — instant primitive-composite model (free, no key).
  * AI mesh          — real organic mesh from Meshy/Tripo (free API key),
                       downloadable as GLB/FBX/OBJ to import into Roblox.

Pure standard library: a threaded HTTP server that serves the page and proxies
the AI provider calls (so there are no browser CORS issues and your key stays
on your machine).
"""

from __future__ import annotations

import json
import os
import sys
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from promptmesh import compile_spec, build_obj_mtl, generate, parse_color, color_hex
from promptmesh import ai_providers

HERE = os.path.dirname(os.path.abspath(__file__))
INDEX = os.path.join(HERE, "webui", "index.html")


class Handler(BaseHTTPRequestHandler):
    server_version = "promptmesh/1.0"

    # -- helpers -----------------------------------------------------------
    def _send(self, code, body, ctype="application/json", extra=None):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        if not length:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def log_message(self, *args):  # quieter console
        pass

    # -- routes ------------------------------------------------------------
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path in ("/", "/index.html"):
            try:
                with open(INDEX, "rb") as f:
                    self._send(200, f.read(), "text/html; charset=utf-8")
            except OSError:
                self._send(500, {"error": "index.html missing"})
        elif path == "/api/objects":
            from promptmesh import supported_objects
            self._send(200, {"objects": supported_objects()})
        elif path == "/api/fetch":
            self._proxy_fetch()
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        try:
            if path == "/api/local":
                self._local()
            elif path == "/api/ai/create":
                self._ai_create()
            elif path == "/api/ai/refine":
                self._ai_refine()
            elif path == "/api/ai/status":
                self._ai_status()
            else:
                self._send(404, {"error": "not found"})
        except ai_providers.ProviderError as exc:
            self._send(502, {"error": str(exc)})
        except Exception as exc:  # noqa: BLE001  surface any bug to the UI
            self._send(400, {"error": "%s: %s" % (type(exc).__name__, exc)})

    # -- offline pipeline --------------------------------------------------
    def _local(self):
        data = self._read_json()
        prompt = (data.get("prompt") or "").strip()
        detail = int(data.get("detail", 24))
        if not prompt:
            return self._send(400, {"error": "empty prompt"})
        spec = generate(prompt, detail=detail)
        recognised = spec.pop("_recognised", True)
        mesh = compile_spec(spec)
        obj_text, mtl_text, tris = build_obj_mtl(mesh, spec["name"])
        # normalise colours to hex so the browser preview is exact
        for part in spec["parts"]:
            part["color"] = "#" + color_hex(parse_color(part.get("color", "#cccccc")))
        self._send(200, {
            "name": spec["name"],
            "recognised": recognised,
            "spec": spec,
            "obj": obj_text,
            "mtl": mtl_text,
            "triangles": tris,
            "vertices": len(mesh.verts),
        })

    # -- AI provider proxy -------------------------------------------------
    def _ai_create(self):
        data = self._read_json()
        provider = data.get("provider", "meshy")
        key = data.get("apiKey", "").strip()
        prompt = (data.get("prompt") or "").strip()
        if not key:
            return self._send(400, {"error": "API key required for AI mode"})
        if not prompt:
            return self._send(400, {"error": "empty prompt"})
        creator = ai_providers.CREATE.get(provider)
        if not creator:
            return self._send(400, {"error": "unknown provider %r" % provider})
        opts = {
            "model_type": data.get("modelType", "standard"),
            "target_polycount": int(data.get("polycount", 20000)),
        }
        task_id = creator(key, prompt, opts)
        self._send(200, {"taskId": task_id})

    def _ai_refine(self):
        data = self._read_json()
        key = data.get("apiKey", "").strip()
        preview_id = data.get("previewTaskId", "")
        task_id = ai_providers.meshy_create_refine(
            key, preview_id, enable_pbr=bool(data.get("enablePbr", True)))
        self._send(200, {"taskId": task_id})

    def _ai_status(self):
        data = self._read_json()
        provider = data.get("provider", "meshy")
        key = data.get("apiKey", "").strip()
        task_id = data.get("taskId", "")
        status_fn = ai_providers.STATUS.get(provider)
        if not status_fn:
            return self._send(400, {"error": "unknown provider %r" % provider})
        self._send(200, status_fn(key, task_id))

    def _proxy_fetch(self):
        """Stream a finished model file through the local server (avoids CORS)."""
        qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        url = (qs.get("url") or [""])[0]
        if not url.startswith(("http://", "https://")):
            return self._send(400, {"error": "bad url"})
        try:
            blob = ai_providers.fetch_model(url)
        except ai_providers.ProviderError as exc:
            return self._send(502, {"error": str(exc)})
        ext = urllib.parse.urlparse(url).path.rsplit(".", 1)[-1].lower()
        ctypes = {"glb": "model/gltf-binary", "fbx": "application/octet-stream",
                  "obj": "text/plain", "gltf": "model/gltf+json"}
        self._send(200, blob, ctypes.get(ext, "application/octet-stream"),
                   extra={"Content-Disposition": "attachment; filename=model.%s" % ext})


def main():
    port = int(os.environ.get("PORT", "8000"))
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            pass
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    url = "http://localhost:%d" % port
    print("promptmesh UI running at %s  (Ctrl+C to stop)" % url)
    try:
        webbrowser.open(url)
    except Exception:
        pass
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")
        server.shutdown()


if __name__ == "__main__":
    main()
