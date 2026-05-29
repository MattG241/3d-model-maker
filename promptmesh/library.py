"""Offline Stage 1: turn a text prompt into a JSON model spec.

This is a free, no-network fallback so the pipeline works out of the box. It
recognises a set of common objects plus colour / material / size modifiers,
exactly like the in-Studio plugin. For arbitrary detailed objects, generate the
JSON with an AI instead (see MODEL_SCHEMA.md for a ready-to-paste prompt).
"""

from __future__ import annotations

import re

from .geometry import NAMED_COLORS

SIZE_WORDS = {
    "tiny": 0.45, "mini": 0.5, "small": 0.7, "little": 0.7,
    "big": 1.5, "large": 1.5, "huge": 2.2, "giant": 3.0,
    "gigantic": 3.0, "massive": 3.0, "enormous": 3.0,
}

MATERIAL_WORDS = {
    "wood": "Wood", "wooden": "Wood", "metal": "Metal", "metallic": "Metal",
    "steel": "Metal", "gold": "Metal", "neon": "Neon", "glowing": "Neon",
    "glass": "Glass", "stone": "Slate", "brick": "Brick", "plastic": "Plastic",
    "ice": "Ice", "sand": "Sand", "marble": "Marble",
}


# Each template returns a list of part dicts. Parts flagged "primary" get
# recoloured when the prompt names a colour; others keep their own colour.
def _p(shape, size, position, color, rotation=None, primary=True, segments=None):
    part = {"shape": shape, "size": size, "position": list(position), "color": color}
    if rotation:
        part["rotation"] = list(rotation)
    if segments:
        part["segments"] = segments
    if primary:
        part["_primary"] = True
    return part


def _box():
    return [_p("box", [4, 4, 4], [0, 0, 0], "#6699e8")]


def _ball():
    return [_p("sphere", [4, 4, 4], [0, 0, 0], "#e85858", segments=32)]


def _cylinder():
    return [_p("cylinder", [3, 5, 3], [0, 0, 0], "#9b6be8", segments=32)]


def _cone():
    return [_p("cone", [4, 5, 4], [0, 0, 0], "#e8a23c", segments=32)]


def _tree():
    return [
        _p("cylinder", [1.4, 6, 1.4], [0, 0, 0], "#684528", primary=False, segments=16),
        _p("sphere", [6, 6, 6], [0, 4.5, 0], "#4b974b", segments=28),
        _p("sphere", [4.5, 4.5, 4.5], [2.2, 6.2, 0], "#4b974b", segments=24),
        _p("sphere", [4.5, 4.5, 4.5], [-2.2, 6.0, 1], "#4b974b", segments=24),
    ]


def _house():
    return [
        _p("box", [8, 5, 8], [0, 0, 0], "#d6c49e"),
        _p("cone", [11, 4, 11], [0, 4.5, 0], "#784327", primary=False, segments=4),
        _p("box", [2, 3, 0.4], [0, -1, 4.05], "#5a371e", primary=False),
        _p("box", [1.6, 1.6, 0.3], [-2.6, 0.4, 4.05], "#96d2e6", primary=False),
        _p("box", [1.6, 1.6, 0.3], [2.6, 0.4, 4.05], "#96d2e6", primary=False),
    ]


def _sword():
    return [
        _p("box", [0.4, 6, 1.1], [0, 2, 0], "#c8c8d2", primary=False),
        _p("box", [0.5, 0.8, 3.2], [0, -1.3, 0], "#e1b43c", primary=False),
        _p("cylinder", [0.7, 2, 0.7], [0, -2.4, 0], "#5a371e", primary=False, segments=16),
        _p("sphere", [1, 1, 1], [0, -3.5, 0], "#e1b43c", primary=False, segments=16),
    ]


def _car():
    parts = [
        _p("box", [10, 2, 5], [0, 0, 0], "#c42820"),
        _p("box", [5, 2, 4.6], [-0.4, 2, 0], "#c42820"),
    ]
    for x in (3, -3):
        for z in (2.6, -2.6):
            parts.append(_p("cylinder", [2, 1, 2], [x, -1, z], "#1b1b1b",
                            rotation=[0, 0, 90], primary=False, segments=20))
    return parts


def _rocket():
    return [
        _p("cylinder", [3, 10, 3], [0, 0, 0], "#ebebeb", segments=32),
        _p("cone", [3.4, 3, 3.4], [0, 6.5, 0], "#c83232", primary=False, segments=32),
        _p("sphere", [1.4, 1.4, 1.4], [0, 1, 1.6], "#78c8eb", primary=False, segments=20),
    ]


def _snowman():
    return [
        _p("sphere", [5, 5, 5], [0, 0, 0], "#f5f5fa", segments=28),
        _p("sphere", [3.6, 3.6, 3.6], [0, 3.9, 0], "#f5f5fa", segments=24),
        _p("sphere", [2.6, 2.6, 2.6], [0, 6.9, 0], "#f5f5fa", segments=24),
        _p("cone", [0.6, 1.6, 0.6], [0, 6.9, 1.4], "#eb8c28", primary=False,
           rotation=[90, 0, 0], segments=12),
    ]


def _mushroom():
    return [
        _p("cylinder", [1.6, 3, 1.6], [0, 0, 0], "#ebe1cd", primary=False, segments=20),
        _p("sphere", [5, 3, 5], [0, 1.9, 0], "#c8372d", segments=28),
    ]


def _table():
    parts = [_p("box", [6, 0.5, 4], [0, 0, 0], "#966432")]
    for x in (-2.5, 2.5):
        for z in (1.5, -1.5):
            parts.append(_p("box", [0.5, 3, 0.5], [x, -1.5, z], "#966432", primary=False))
    return parts


def _chair():
    parts = [
        _p("box", [3, 0.5, 3], [0, 0, 0], "#966432"),
        _p("box", [3, 3, 0.5], [0, 1.75, -1.25], "#966432"),
    ]
    for x in (-1.1, 1.1):
        for z in (1.1, -1.1):
            parts.append(_p("box", [0.5, 2, 0.5], [x, -1, z], "#966432", primary=False))
    return parts


def _star():
    return [_p("sphere", [4, 4, 1], [0, 0, 0], "#fadc46", segments=24)]


def _gem():
    return [
        _p("cone", [3.5, 2.5, 3.5], [0, 1.2, 0], "#5adcc8", segments=6),
        _p("cone", [3.5, 2, 3.5], [0, -0.5, 0], "#5adcc8", rotation=[180, 0, 0], segments=6),
    ]


def _tower():
    parts = [_p("cylinder", [8, 12, 8], [0, 0, 0], "#969699", segments=32)]
    parts.append(_p("cone", [9, 4, 9], [0, 8, 0], "#963232", primary=False, segments=32))
    return parts


def _robot():
    return [
        _p("box", [4, 4, 2], [0, 0, 0], "#8c96a0"),
        _p("box", [2.4, 2.4, 2.4], [0, 3.2, 0], "#8c96a0"),
        _p("sphere", [0.6, 0.6, 0.6], [-0.6, 3.5, 1.2], "#5ac8ff", primary=False, segments=12),
        _p("sphere", [0.6, 0.6, 0.6], [0.6, 3.5, 1.2], "#5ac8ff", primary=False, segments=12),
        _p("cylinder", [1, 4, 1], [-3, 0, 0], "#8c96a0", segments=14),
        _p("cylinder", [1, 4, 1], [3, 0, 0], "#8c96a0", segments=14),
        _p("box", [1.4, 3, 1.4], [-1.1, -3.5, 0], "#8c96a0"),
        _p("box", [1.4, 3, 1.4], [1.1, -3.5, 0], "#8c96a0"),
    ]


def _flower():
    parts = [
        _p("cylinder", [0.4, 5, 0.4], [0, 0, 0], "#469646", primary=False, segments=10),
        _p("sphere", [1.6, 1.2, 1.6], [0, 2.7, 0], "#f5cd3c", primary=False, segments=16),
    ]
    import math
    for i in range(6):
        a = math.radians(i * 60)
        parts.append(_p("sphere", [1.6, 0.7, 1.2],
                        [math.cos(a) * 1.6, 2.7, math.sin(a) * 1.6], "#e65a8c", segments=14))
    return parts


TEMPLATES = {
    "box": _box, "cube": _box, "block": _box,
    "ball": _ball, "sphere": _ball, "orb": _ball,
    "cylinder": _cylinder, "tube": _cylinder, "pillar": _cylinder,
    "cone": _cone,
    "tree": _tree, "oak": _tree, "pine": _tree,
    "house": _house, "home": _house, "cabin": _house, "cottage": _house,
    "sword": _sword, "blade": _sword, "katana": _sword,
    "car": _car, "vehicle": _car, "racecar": _car,
    "rocket": _rocket, "spaceship": _rocket, "missile": _rocket,
    "snowman": _snowman,
    "mushroom": _mushroom, "toadstool": _mushroom,
    "table": _table, "desk": _table,
    "chair": _chair, "seat": _chair, "throne": _chair,
    "star": _star,
    "gem": _gem, "diamond": _gem, "crystal": _gem, "jewel": _gem,
    "tower": _tower, "castle": _tower, "turret": _tower,
    "robot": _robot, "bot": _robot, "mech": _robot, "android": _robot,
    "flower": _flower, "rose": _flower, "tulip": _flower,
}


def supported_objects():
    """A sorted, de-duplicated list of the template object names."""
    seen = {}
    for key, fn in TEMPLATES.items():
        seen.setdefault(fn, key)
    return sorted(seen.values())


def generate(prompt, detail=24):
    """Parse a prompt into a finished spec dict (colour/size/material resolved)."""
    lower = prompt.lower()
    words = re.findall(r"[a-z]+", lower)

    color = None
    material = None
    scale = 1.0
    obj_type = None
    obj_key = None

    for w in words:
        if w in NAMED_COLORS and color is None:
            color = "#" + "%02X%02X%02X" % NAMED_COLORS[w]
        if w in MATERIAL_WORDS and material is None:
            material = MATERIAL_WORDS[w]
        if w in SIZE_WORDS:
            scale = SIZE_WORDS[w]
        # last matching object word wins ("big red car" -> car)
        key = w if w in TEMPLATES else (w[:-1] if w.endswith("s") and w[:-1] in TEMPLATES else None)
        if key:
            obj_type, obj_key = TEMPLATES[key], key

    recognised = obj_type is not None
    parts_raw = obj_type() if recognised else _fallback()

    parts = []
    for part in parts_raw:
        is_primary = part.pop("_primary", False)
        if color and is_primary:
            part["color"] = color
        if material:
            part["material"] = material
        if scale != 1.0:
            part["size"] = [round(s * scale, 4) for s in part["size"]]
            part["position"] = [round(p * scale, 4) for p in part["position"]]
        parts.append(part)

    name = prompt.strip() or (obj_key or "model")
    name = name[:1].upper() + name[1:]
    return {
        "name": name,
        "detail": detail,
        "_recognised": recognised,
        "parts": parts,
    }


def _fallback():
    # A faceted crystal placeholder when the object isn't in the library.
    return [
        _p("cone", [3, 4, 3], [0, 2, 0], "#7860dc", segments=6),
        _p("cone", [3, 3, 3], [0, -0.5, 0], "#7860dc", rotation=[180, 0, 0], segments=6),
        _p("box", [4, 0.6, 4], [0, -2, 0], "#5a5a5f", primary=False),
    ]
