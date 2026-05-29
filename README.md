# promptmesh — prompt → JSON → 3D model for Roblox

A **free, offline** pipeline that builds detailed 3D models you can import
straight into Roblox. It works in **two stages**:

1. **Prompt → JSON spec.** Describe a model as structured JSON (a list of
   shapes with sizes, positions, colours and materials). Generate it with the
   built-in offline library, **write it by hand**, or **have an AI write it**.
2. **JSON → detailed mesh.** The compiler turns that spec into a smooth,
   triangulated **`.obj` + `.mtl`** that you import into Roblox Studio.

No API keys, no internet, no dependencies — **pure Python 3 standard library**.

```
"big red car"  ──►  Big_red_car.json  ──►  Big_red_car.obj (+ .mtl)  ──►  Roblox
   prompt            (editable spec)        detailed mesh                import
```

---

## Quick start

```bash
# Prompt → JSON → OBJ (writes both the spec and the mesh into ./out)
python3 make_model.py "big red car" -o out

# Smoother curves
python3 make_model.py "giant blue ball" -o out --detail 32

# Compile a spec you wrote or an AI generated
python3 make_model.py --json examples/treasure_chest.json -o out

# Just produce the JSON (Stage 1 only)
python3 make_model.py "wooden house" --json-only -o out

# See the built-in offline objects
python3 make_model.py --list
```

Each run prints the output paths and the triangle/vertex count.

---

## The two stages in detail

### Stage 1 — get a JSON spec

A spec looks like this (full schema in **[MODEL_SCHEMA.md](MODEL_SCHEMA.md)**):

```json
{
  "name": "Treasure Chest",
  "detail": 24,
  "parts": [
    { "shape": "box",      "size": [6, 3, 4], "position": [0, 1.5, 0], "color": "#8B5A2B", "material": "Wood" },
    { "shape": "cylinder", "size": [4, 6, 4], "position": [0, 3.4, 0], "rotation": [0, 0, 90], "color": "#8B5A2B" },
    { "shape": "box",      "size": [6.2, 0.4, 4.2], "position": [0, 3, 0], "color": "#D4A017", "material": "Metal" }
  ]
}
```

Three ways to get one:

- **Offline library** — `make_model.py "tree"` recognises ~18 objects plus
  colour / size / material words. Great for instant results.
- **By hand** — copy an example from [`examples/`](examples) and tweak numbers.
- **With an AI** — paste the prompt at the bottom of
  [MODEL_SCHEMA.md](MODEL_SCHEMA.md) into Claude/ChatGPT, change the last line to
  your object, and save the JSON it returns. This is how you get *arbitrary*
  detailed models — the AI writes the spec, the compiler builds the mesh.

### Stage 2 — compile to a mesh

`make_model.py --json your_spec.json` runs the compiler, which:

- builds a smooth triangle mesh for each shape (`box`, `sphere`, `cylinder`,
  `cone`, `wedge`) at the requested detail,
- applies rotation + position, fixes face winding so nothing is inside-out,
- centres the model on X/Z and rests it on the ground,
- writes a single-mesh **`.obj`** with a matching **`.mtl`** (one material per
  colour).

---

## Importing into Roblox Studio

1. **View → Asset Manager → Bulk Import** (or use the **3D Importer**).
2. Select the `.obj` (and the `.mtl` / texture if prompted).
3. It imports as a **MeshPart** you can drag into the world.

**About colours:** the `.mtl` carries a colour per material so the model looks
right in Blender and other tools. Roblox's OBJ import may bring the mesh in as a
single colour — if so, set the MeshPart's **Color**, or split by material, or
add a **SurfaceAppearance** for full PBR. See **[AI_MODELS.md](AI_MODELS.md)**
for texturing and for higher-fidelity AI mesh options.

**Keep it light:** stay **well under ~10k triangles** per mesh (lower `--detail`
or use fewer parts). Set `CollisionFidelity` to `Box`/`Hull` and **anchor**
static props.

---

## Project layout

```
make_model.py            # CLI entry point
promptmesh/
  geometry.py            # spec -> triangle mesh (primitives, transforms, compiler)
  exporter.py            # mesh -> .obj / .mtl
  library.py             # offline prompt -> spec
examples/                # hand-authored example specs
MODEL_SCHEMA.md          # JSON schema + copy-paste AI prompt
AI_MODELS.md             # using Roblox Cube 3D / Meshy / Tripo for AI meshes
PLUGIN.md                # the original in-Studio, Part-based plugin
```

## Also included: the in-Studio Parts plugin

The original **Part-based Studio plugin** (140+ objects, builds inside Studio
with no import step) still lives here — see **[PLUGIN.md](PLUGIN.md)**. Use the
plugin for instant blocky props inside Studio; use this pipeline when you want
detailed mesh files.

## License

MIT — see [LICENSE](LICENSE).
