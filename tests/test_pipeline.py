"""Lightweight checks for the promptmesh pipeline (stdlib unittest)."""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from promptmesh import compile_spec, generate, write_obj  # noqa: E402
from promptmesh.geometry import parse_color  # noqa: E402


def _read_obj(path):
    verts, faces = 0, []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            tok = line.split()
            if not tok:
                continue
            if tok[0] == "v":
                verts += 1
            elif tok[0] == "f":
                faces.append([int(p.split("/")[0]) for p in tok[1:]])
    return verts, faces


class ColorTests(unittest.TestCase):
    def test_formats(self):
        self.assertEqual(parse_color("#ff0000"), (255, 0, 0))
        self.assertEqual(parse_color("#fff"), (255, 255, 255))
        self.assertEqual(parse_color([10, 20, 30]), (10, 20, 30))
        self.assertEqual(parse_color("red"), (196, 40, 28))

    def test_bad(self):
        with self.assertRaises(ValueError):
            parse_color("not-a-colour")


class CompileTests(unittest.TestCase):
    def test_each_shape_is_valid(self):
        for shape in ("box", "sphere", "cylinder", "cone", "wedge"):
            spec = {"parts": [{"shape": shape, "size": [2, 2, 2], "color": "#888"}]}
            mesh = compile_spec(spec)
            self.assertGreater(len(mesh.verts), 3)
            self.assertGreater(mesh.triangle_count, 0)
            n = len(mesh.verts)
            for grp in mesh.groups.values():
                for tri in grp:
                    self.assertEqual(len(tri), 3)
                    for i in tri:
                        self.assertTrue(0 <= i < n, f"{shape}: index {i} out of range")

    def test_grounded_and_centered(self):
        spec = {"parts": [{"shape": "box", "size": [4, 4, 4],
                           "position": [10, 10, 10], "color": "#888"}]}
        mesh = compile_spec(spec)
        ys = [v[1] for v in mesh.verts]
        xs = [v[0] for v in mesh.verts]
        self.assertAlmostEqual(min(ys), 0.0, places=5)        # rests on ground
        self.assertAlmostEqual((min(xs) + max(xs)) / 2, 0.0, places=5)  # centred

    def test_rejects_bad_spec(self):
        with self.assertRaises(ValueError):
            compile_spec({"parts": []})
        with self.assertRaises(ValueError):
            compile_spec({"parts": [{"shape": "box"}]})  # no size


class PipelineTests(unittest.TestCase):
    def test_prompt_to_obj(self):
        spec = generate("big red car")
        self.assertTrue(spec["parts"])
        mesh = compile_spec(spec)
        with tempfile.TemporaryDirectory() as d:
            path, tris = write_obj(mesh, d, spec["name"])
            self.assertTrue(os.path.exists(path))
            self.assertTrue(os.path.exists(path[:-4] + ".mtl"))
            verts, faces = _read_obj(path)
            self.assertEqual(tris, len(faces))
            for tri in faces:
                self.assertEqual(len(tri), 3)
                for i in tri:
                    self.assertTrue(1 <= i <= verts)

    def test_unknown_prompt_falls_back(self):
        spec = generate("zzqq nonsense thing")
        self.assertFalse(spec["_recognised"])
        self.assertTrue(spec["parts"])

    def test_examples_compile(self):
        ex_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "examples")
        for fn in os.listdir(ex_dir):
            if fn.endswith(".json"):
                with open(os.path.join(ex_dir, fn), encoding="utf-8") as f:
                    spec = json.load(f)
                mesh = compile_spec(spec)
                self.assertGreater(mesh.triangle_count, 0, fn)


if __name__ == "__main__":
    unittest.main()
