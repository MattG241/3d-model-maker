"""Real text-to-3D via free-tier AI services (Meshy, Tripo).

These produce genuine organic meshes (not primitive composites). They run on the
provider's servers, so you need a free API key. Calls are made from the local
app with the standard library only (urllib) — no SDK to install.

All functions raise ``ProviderError`` with a readable message on failure.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request


class ProviderError(Exception):
    pass


def _request(method, url, api_key, body=None, timeout=60):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {"Authorization": "Bearer %s" % api_key}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise ProviderError("HTTP %s from %s: %s" % (exc.code, url, detail[:400]))
    except urllib.error.URLError as exc:
        raise ProviderError("Network error calling %s: %s" % (url, exc.reason))
    try:
        return json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        raise ProviderError("Unexpected non-JSON response from %s" % url)


# --- Meshy (https://docs.meshy.ai/en/api/text-to-3d) -----------------------
_MESHY = "https://api.meshy.ai/openapi/v2/text-to-3d"


def meshy_create_preview(api_key, prompt, model_type="standard",
                         target_polycount=20000, ai_model="latest"):
    body = {
        "mode": "preview",
        "prompt": prompt[:600],
        "ai_model": ai_model,
        "model_type": model_type,            # standard | lowpoly
        "should_remesh": True,
        "topology": "triangle",
        "target_polycount": int(target_polycount),
    }
    res = _request("POST", _MESHY, api_key, body)
    task_id = res.get("result") or res.get("id")
    if not task_id:
        raise ProviderError("Meshy did not return a task id: %s" % res)
    return task_id


def meshy_create_refine(api_key, preview_task_id, enable_pbr=True, hd_texture=False):
    body = {
        "mode": "refine",
        "preview_task_id": preview_task_id,
        "enable_pbr": bool(enable_pbr),
        "hd_texture": bool(hd_texture),
    }
    res = _request("POST", _MESHY, api_key, body)
    task_id = res.get("result") or res.get("id")
    if not task_id:
        raise ProviderError("Meshy refine did not return a task id: %s" % res)
    return task_id


def meshy_status(api_key, task_id):
    res = _request("GET", "%s/%s" % (_MESHY, task_id), api_key)
    return {
        "status": res.get("status", "UNKNOWN"),
        "progress": res.get("progress", 0),
        "model_urls": res.get("model_urls", {}) or {},
        "task_error": (res.get("task_error") or {}).get("message", ""),
    }


# --- Tripo (https://platform.tripo3d.ai) -----------------------------------
_TRIPO = "https://api.tripo3d.ai/v2/openapi/task"


def tripo_create(api_key, prompt):
    body = {"type": "text_to_model", "prompt": prompt[:600]}
    res = _request("POST", _TRIPO, api_key, body)
    data = res.get("data") or {}
    task_id = data.get("task_id")
    if not task_id:
        raise ProviderError("Tripo did not return a task id: %s" % res)
    return task_id


def tripo_status(api_key, task_id):
    res = _request("GET", "%s/%s" % (_TRIPO, task_id), api_key)
    data = res.get("data") or {}
    output = data.get("output") or {}
    status_map = {"success": "SUCCEEDED", "failed": "FAILED",
                  "running": "IN_PROGRESS", "queued": "PENDING"}
    model = output.get("pbr_model") or output.get("model") or ""
    return {
        "status": status_map.get(data.get("status"), str(data.get("status", "UNKNOWN")).upper()),
        "progress": data.get("progress", 0),
        "model_urls": {"glb": model} if model else {},
        "task_error": data.get("message", ""),
    }


def fetch_model(url, timeout=180):
    """Download a finished model (signed public URL, no auth needed) -> bytes."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return resp.read()
    except urllib.error.URLError as exc:
        raise ProviderError("Could not download model: %s" % exc)


# Dispatch tables used by the web app.
CREATE = {
    "meshy": lambda key, prompt, opts: meshy_create_preview(
        key, prompt, opts.get("model_type", "standard"),
        opts.get("target_polycount", 20000)),
    "tripo": lambda key, prompt, opts: tripo_create(key, prompt),
}
STATUS = {"meshy": meshy_status, "tripo": tripo_status}
