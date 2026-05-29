# Model spec — JSON schema & AI prompt

The pipeline is two stages:

1. **Prompt → JSON spec** (this file) — a structured description of the model.
2. **JSON → detailed mesh** — `make_model.py` compiles the spec into an
   `.obj` you import into Roblox.

You can produce the JSON three ways: let the offline generator do it
(`python make_model.py "tree"`), **write it by hand**, or **generate it with an
AI** (paste the prompt at the bottom of this file into Claude / ChatGPT). All of
them feed the same compiler.

---

## Schema

```jsonc
{
  "name": "Treasure Chest",     // string, used for the output filename
  "detail": 24,                  // optional int: default segments for curved shapes (8–64)
  "parts": [                     // one or more parts; the model is their union
    {
      "shape": "box",            // box | sphere | cylinder | cone | wedge
      "size": [6, 3, 4],         // [x, y, z] bounding size in studs (required)
      "position": [0, 1.5, 0],   // [x, y, z] centre, studs (default [0,0,0])
      "rotation": [0, 0, 0],     // [x, y, z] Euler degrees (optional)
      "color": "#8B5A2B",        // "#rrggbb", [r,g,b] 0-255, or a colour name (optional)
      "material": "Wood",        // label only; groups colours in the .mtl (optional)
      "segments": 24             // optional per-part smoothness override
    }
  ]
}
```

### Shapes

| `shape` | Geometry | Notes |
| --- | --- | --- |
| `box` | rectangular block | `size` = full extents |
| `sphere` | ellipsoid | unequal `size` axes squash it; `segments` controls smoothness |
| `cylinder` | round column, **axis along Y** | `size` = `[diameterX, height, diameterZ]`; rotate to lay it down |
| `cone` | cone/pyramid, apex up, **axis Y** | use `segments: 4` for a pyramid, `segments: 6` for a gem facet, high for smooth |
| `wedge` | right-triangular prism (ramp) | tall side on −Z, slopes down toward +Z |

### Conventions

- **Units are studs**, **Y is up**. A Roblox character is ~5 studs tall.
- Build parts around the origin — the compiler automatically centres the model
  on X/Z and rests it on the ground (`y = 0`), so you don't have to.
- Rotation is applied as `Rz * Ry * Rx` (degrees).
- The whole model becomes **one MeshPart** when imported.

### Tips for good models

- Use **8–15 parts**; combine primitives (a cylinder body + a cone roof + boxes
  for doors) rather than one blob.
- Curves cost triangles. Keep `detail`/`segments` around **24** for props; only
  go higher (32–48) for hero pieces. Keep total triangles **well under ~10k**.
- Give parts distinct, sensible colours; pick a `material` label so related
  parts share a colour group in the `.mtl`.

---

## Compile a spec

```bash
python make_model.py --json my_model.json -o out
# -> out/my_model.obj  + out/my_model.mtl
```

See [`examples/`](examples) for complete specs (`treasure_chest.json`,
`spaceship.json`).

---

## AI prompt (copy–paste)

Paste this into any capable AI, replace the last line, and feed the JSON it
returns to `make_model.py --json`:

> You are a 3D model generator. Output **only** a single JSON object (no prose,
> no markdown fences) describing a 3D model as a union of primitive parts, using
> exactly this schema:
>
> ```
> {
>   "name": string,
>   "detail": integer (8-48, default 24),
>   "parts": [
>     {
>       "shape": "box" | "sphere" | "cylinder" | "cone" | "wedge",
>       "size": [x, y, z],            // full extents in studs, Y is up
>       "position": [x, y, z],        // centre in studs (build around origin)
>       "rotation": [x, y, z],        // Euler degrees, optional
>       "color": "#rrggbb",           // hex string
>       "material": string,           // e.g. "Wood", "Metal", "Neon"
>       "segments": integer           // optional, smoothness for curved shapes
>     }
>   ]
> }
> ```
>
> Rules: cylinders and cones have their axis along Y (rotate to reposition).
> Use 8–15 parts for good detail. Keep curved-shape segments around 24 so the
> total stays under ~10,000 triangles. Make it colourful and recognisable.
> Build it around the origin; it will be auto-centred and grounded.
>
> Now generate the model for: **a detailed wooden windmill with a red roof**
