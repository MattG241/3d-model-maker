#!/usr/bin/env python3
"""promptmesh CLI — prompt or JSON spec -> detailed OBJ mesh for Roblox.

Examples
--------
    # Prompt -> JSON -> OBJ (also writes the spec next to it)
    python make_model.py "big red car" -o out

    # Compile an existing JSON spec (hand-written or AI-generated)
    python make_model.py --json examples/treasure_chest.json -o out

    # Just emit the JSON spec for a prompt (Stage 1 only)
    python make_model.py "wooden house" --json-only -o out

    # List the built-in offline objects
    python make_model.py --list
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from promptmesh import compile_spec, write_obj, generate, supported_objects


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Generate a JSON model spec and compile it into a Roblox-ready OBJ mesh.",
    )
    parser.add_argument("prompt", nargs="?", help="text prompt, e.g. \"big red car\"")
    parser.add_argument("--json", metavar="FILE", help="compile this JSON spec instead of a prompt")
    parser.add_argument("-o", "--out", default="out", help="output directory (default: out)")
    parser.add_argument("--detail", type=int, default=24,
                        help="segments for curved shapes; higher = smoother (default: 24)")
    parser.add_argument("--json-only", action="store_true",
                        help="only write the JSON spec, don't compile the mesh")
    parser.add_argument("--no-json", action="store_true",
                        help="don't write the JSON spec alongside the mesh")
    parser.add_argument("--list", action="store_true",
                        help="list the built-in offline objects and exit")
    args = parser.parse_args(argv)

    if args.list:
        objects = supported_objects()
        print("Built-in offline objects (%d):" % len(objects))
        print("  " + ", ".join(objects))
        print("\nFor anything else, generate the JSON with an AI — see MODEL_SCHEMA.md.")
        return 0

    # --- Stage 1: obtain the spec ---
    if args.json:
        try:
            with open(args.json, "r", encoding="utf-8") as f:
                spec = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            print("error: could not read JSON spec: %s" % exc, file=sys.stderr)
            return 1
        name = spec.get("name", os.path.splitext(os.path.basename(args.json))[0])
        recognised = True
    elif args.prompt:
        spec = generate(args.prompt, detail=args.detail)
        recognised = spec.pop("_recognised", True)
        name = spec.get("name", "model")
        if not recognised:
            print("note: '%s' isn't in the offline library — made a placeholder crystal."
                  % args.prompt)
            print("      For this object, generate JSON with an AI (see MODEL_SCHEMA.md).")
    else:
        parser.error("provide a prompt or --json FILE (or use --list)")
        return 2

    os.makedirs(args.out, exist_ok=True)

    # --- write the spec (Stage 1 output) ---
    if args.json_only or not args.no_json:
        spec_to_write = {k: v for k, v in spec.items() if not k.startswith("_")}
        spec_path = os.path.join(args.out, _safe(name) + ".json")
        with open(spec_path, "w", encoding="utf-8") as f:
            json.dump(spec_to_write, f, indent=2)
        print("spec : %s  (%d parts)" % (spec_path, len(spec.get("parts", []))))

    if args.json_only:
        return 0

    # --- Stage 2: compile the mesh ---
    try:
        mesh = compile_spec(spec)
    except ValueError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 1

    obj_path, tris = write_obj(mesh, args.out, name)
    print("model: %s  (%d triangles, %d vertices)" % (obj_path, tris, len(mesh.verts)))
    print("       + %s.mtl" % os.path.splitext(obj_path)[0])
    print("\nImport into Roblox Studio via Asset Manager -> Bulk Import (see README).")
    return 0


def _safe(name):
    safe = "".join(c if (c.isalnum() or c in " -_") else "_" for c in name).strip()
    return safe.replace(" ", "_") or "model"


if __name__ == "__main__":
    raise SystemExit(main())
