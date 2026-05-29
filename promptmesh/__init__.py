"""promptmesh — prompt -> JSON spec -> detailed OBJ mesh for Roblox.

Two stages:
  1. library.generate(prompt)  ->  JSON spec  (offline; or author it yourself / with an AI)
  2. geometry.compile_spec(spec) + exporter.write_obj(...)  ->  .obj / .mtl
"""

from .geometry import compile_spec, parse_color, Mesh
from .exporter import write_obj
from .library import generate, supported_objects

__all__ = [
    "compile_spec",
    "parse_color",
    "Mesh",
    "write_obj",
    "generate",
    "supported_objects",
]
