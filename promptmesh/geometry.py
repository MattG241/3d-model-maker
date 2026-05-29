"""Turn a JSON model spec into a detailed triangle mesh.

A spec is a dict like::

    {
        "name": "Treasure Chest",
        "detail": 24,                 # default segments for curved shapes
        "parts": [
            {
                "shape": "box",       # box | sphere | cylinder | cone | wedge
                "size": [6, 3, 4],    # bounding size in studs (x, y, z)
                "position": [0, 1.5, 0],
                "rotation": [0, 0, 0],# Euler degrees (optional)
                "color": "#8B5A2B",   # hex, [r,g,b] 0-255, or a colour name
                "material": "Wood",   # label only (optional)
                "segments": 24        # per-part override for curved shapes (optional)
            }
        ]
    }

The compiler produces a single mesh: a flat list of vertices plus faces grouped
by material, ready for the OBJ exporter.
"""

from __future__ import annotations

import math
from collections import OrderedDict

# --- Colours ---------------------------------------------------------------
NAMED_COLORS = {
    "red": (196, 40, 28), "crimson": (150, 30, 30), "scarlet": (200, 35, 35),
    "orange": (218, 133, 65), "yellow": (245, 205, 48), "gold": (240, 200, 60),
    "green": (75, 151, 75), "lime": (160, 215, 60), "teal": (40, 150, 150),
    "blue": (45, 100, 220), "navy": (25, 45, 110), "cyan": (120, 210, 235),
    "purple": (130, 70, 200), "violet": (150, 90, 220), "magenta": (210, 50, 170),
    "pink": (235, 130, 180), "brown": (120, 75, 45), "tan": (214, 196, 158),
    "black": (30, 30, 30), "white": (245, 245, 245),
    "gray": (140, 140, 145), "grey": (140, 140, 145), "silver": (190, 190, 195),
    "maroon": (110, 30, 30),
}


def parse_color(value):
    """Accept '#rrggbb', [r,g,b] (0-255), or a colour name -> (r, g, b)."""
    if value is None:
        return (204, 204, 204)
    if isinstance(value, str):
        v = value.strip().lower()
        if v in NAMED_COLORS:
            return NAMED_COLORS[v]
        if v.startswith("#"):
            v = v[1:]
        if len(v) == 3:
            v = "".join(c * 2 for c in v)
        if len(v) == 6:
            try:
                return tuple(int(v[i:i + 2], 16) for i in (0, 2, 4))
            except ValueError:
                pass
        raise ValueError(f"Unrecognised colour: {value!r}")
    if isinstance(value, (list, tuple)) and len(value) == 3:
        return tuple(max(0, min(255, int(round(c)))) for c in value)
    raise ValueError(f"Unrecognised colour: {value!r}")


def color_hex(rgb):
    return "%02X%02X%02X" % rgb


# --- Vector helpers --------------------------------------------------------
def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _length(a):
    return math.sqrt(_dot(a, a))


def _rotation_matrix(rx, ry, rz):
    """Euler degrees -> 3x3 matrix applied as v' = Rz * Ry * Rx * v."""
    rx, ry, rz = map(math.radians, (rx, ry, rz))
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)
    # Combined Rz*Ry*Rx
    return (
        (cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx),
        (sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx),
        (-sy,      cy * sx,                cy * cx),
    )


def _apply(mat, v):
    return (
        mat[0][0] * v[0] + mat[0][1] * v[1] + mat[0][2] * v[2],
        mat[1][0] * v[0] + mat[1][1] * v[1] + mat[1][2] * v[2],
        mat[2][0] * v[0] + mat[2][1] * v[1] + mat[2][2] * v[2],
    )


# --- Primitive builders (centred on the local origin) ----------------------
def _box(hx, hy, hz):
    verts = [
        (-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
        (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz),
    ]
    faces = [
        (4, 5, 6), (4, 6, 7), (1, 0, 3), (1, 3, 2),
        (5, 1, 2), (5, 2, 6), (0, 4, 7), (0, 7, 3),
        (7, 6, 2), (7, 2, 3), (0, 1, 5), (0, 5, 4),
    ]
    return verts, faces


def _sphere(hx, hy, hz, segments, rings):
    verts = []
    stride = segments + 1
    for i in range(rings + 1):
        phi = math.pi * i / rings
        y, r = math.cos(phi), math.sin(phi)
        for j in range(segments + 1):
            theta = 2 * math.pi * j / segments
            verts.append((r * math.cos(theta) * hx, y * hy, r * math.sin(theta) * hz))
    faces = []
    for i in range(rings):
        for j in range(segments):
            a = i * stride + j
            faces.append((a, a + 1, a + stride + 1))
            faces.append((a, a + stride + 1, a + stride))
    return verts, faces


def _cylinder(hx, h, hz, segments):
    hy = h / 2
    verts = []
    for j in range(segments + 1):
        th = 2 * math.pi * j / segments
        x, z = math.cos(th), math.sin(th)
        verts.append((x * hx, -hy, z * hz))
        verts.append((x * hx, hy, z * hz))
    faces = []
    for j in range(segments):
        b0, t0, b1, t1 = 2 * j, 2 * j + 1, 2 * (j + 1), 2 * (j + 1) + 1
        faces.append((b0, b1, t1))
        faces.append((b0, t1, t0))
    bc = len(verts); verts.append((0, -hy, 0))
    tc = len(verts); verts.append((0, hy, 0))
    for j in range(segments):
        faces.append((bc, 2 * j, 2 * (j + 1)))
        faces.append((tc, 2 * (j + 1) + 1, 2 * j + 1))
    return verts, faces


def _cone(hx, h, hz, segments):
    hy = h / 2
    verts = []
    for j in range(segments + 1):
        th = 2 * math.pi * j / segments
        verts.append((math.cos(th) * hx, -hy, math.sin(th) * hz))
    apex = len(verts); verts.append((0, hy, 0))
    bc = len(verts); verts.append((0, -hy, 0))
    faces = []
    for j in range(segments):
        faces.append((j, j + 1, apex))
        faces.append((bc, j + 1, j))
    return verts, faces


def _wedge(hx, hy, hz):
    verts = [
        (-hx, -hy, -hz), (hx, -hy, -hz), (-hx, hy, -hz),
        (hx, hy, -hz), (-hx, -hy, hz), (hx, -hy, hz),
    ]
    faces = [
        (0, 1, 3), (0, 3, 2),   # back (tall) face
        (0, 4, 5), (0, 5, 1),   # bottom
        (2, 3, 5), (2, 5, 4),   # slope
        (0, 2, 4),              # left end
        (1, 5, 3),              # right end
    ]
    return verts, faces


def _make_primitive(shape, size, segments):
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    if shape in ("box", "block", "cube", "wedge2"):
        return _box(hx, hy, hz)
    if shape in ("sphere", "ball", "ellipsoid"):
        return _sphere(hx, hy, hz, segments, max(4, segments // 2))
    if shape in ("cylinder", "cyl", "tube"):
        return _cylinder(hx, size[1], hz, segments)
    if shape in ("cone", "pyramid"):
        return _cone(hx, size[1], hz, segments)
    if shape in ("wedge", "ramp", "slope"):
        return _wedge(hx, hy, hz)
    raise ValueError(f"Unknown shape: {shape!r}")


def _orient_outward(verts, faces, center=(0.0, 0.0, 0.0)):
    """Flip faces so normals point away from `center`; drop degenerate tris."""
    out = []
    for (a, b, c) in faces:
        p0, p1, p2 = verts[a], verts[b], verts[c]
        n = _cross(_sub(p1, p0), _sub(p2, p0))
        if _length(n) < 1e-9:
            continue
        centroid = ((p0[0] + p1[0] + p2[0]) / 3.0,
                    (p0[1] + p1[1] + p2[1]) / 3.0,
                    (p0[2] + p1[2] + p2[2]) / 3.0)
        out.append((a, c, b) if _dot(n, _sub(centroid, center)) < 0 else (a, b, c))
    return out


# --- Spec compiler ---------------------------------------------------------
class Mesh:
    """A compiled mesh: vertices + faces grouped by material."""

    def __init__(self):
        self.verts = []                 # list[(x, y, z)]
        self.groups = OrderedDict()     # material_key -> list[(i, j, k)] 0-based
        self.materials = OrderedDict()  # material_key -> (r, g, b)

    @property
    def triangle_count(self):
        return sum(len(f) for f in self.groups.values())


def compile_spec(spec):
    """Compile a spec dict into a Mesh. Raises ValueError on bad input."""
    if not isinstance(spec, dict) or "parts" not in spec:
        raise ValueError("Spec must be an object with a 'parts' list.")
    parts = spec["parts"]
    if not isinstance(parts, list) or not parts:
        raise ValueError("Spec 'parts' must be a non-empty list.")

    detail = int(spec.get("detail", 24))
    mesh = Mesh()

    for idx, part in enumerate(parts):
        shape = str(part.get("shape", "box")).lower()
        size = part.get("size")
        if not (isinstance(size, (list, tuple)) and len(size) == 3):
            raise ValueError(f"part[{idx}] needs a 'size' of three numbers.")
        size = [float(s) for s in size]
        pos = part.get("position", [0, 0, 0])
        rot = part.get("rotation", [0, 0, 0])
        segments = max(3, int(part.get("segments", detail)))
        rgb = parse_color(part.get("color", "#cccccc"))
        label = str(part.get("material", "Plastic"))

        verts, faces = _make_primitive(shape, size, segments)
        faces = _orient_outward(verts, faces)

        mat = _rotation_matrix(float(rot[0]), float(rot[1]), float(rot[2]))
        verts = [
            (
                _apply(mat, v)[0] + float(pos[0]),
                _apply(mat, v)[1] + float(pos[1]),
                _apply(mat, v)[2] + float(pos[2]),
            )
            for v in verts
        ]

        base = len(mesh.verts)
        mesh.verts.extend(verts)
        key = "%s_%s" % (_sanitize(label), color_hex(rgb))
        mesh.materials[key] = rgb
        mesh.groups.setdefault(key, []).extend(
            (a + base, b + base, c + base) for (a, b, c) in faces
        )

    _ground_align(mesh)
    return mesh


def _sanitize(name):
    return "".join(c if (c.isalnum() or c == "_") else "_" for c in name) or "mat"


def _ground_align(mesh):
    """Centre the model on X/Z and rest its lowest point on y=0."""
    if not mesh.verts:
        return
    xs = [v[0] for v in mesh.verts]
    ys = [v[1] for v in mesh.verts]
    zs = [v[2] for v in mesh.verts]
    cx = (min(xs) + max(xs)) / 2.0
    cz = (min(zs) + max(zs)) / 2.0
    my = min(ys)
    mesh.verts = [(v[0] - cx, v[1] - my, v[2] - cz) for v in mesh.verts]
