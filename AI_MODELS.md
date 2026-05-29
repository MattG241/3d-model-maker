# Making real AI-generated 3D models for your Roblox game

The plugin in this repo builds models out of **Parts** — instant and 100% free,
but blocky. This guide is the upgrade path: how to create **actual AI-generated
meshes** (with textures) and get them into your game, using the **best free
tools available**.

There's no single "best" tool — there's a best **workflow** depending on what
you want:

| You want… | Use | Cost |
| --- | --- | --- |
| Instant, native, zero setup | **Roblox Cube 3D** (Studio Assistant) | Free (beta) |
| The best-looking free meshes | **Meshy.ai** → import | Free credits |
| A second opinion / more credits | **Tripo3D** → import | Free credits |
| Unlimited & fully open-source | **Hunyuan3D / TRELLIS** (local GPU) | Free |

> **Reality check:** "Free" SaaS tools (Meshy, Tripo, Rodin) give you a monthly
> pool of credits, not infinite generations. Roblox Cube 3D is free in beta but
> lower-detail. Truly unlimited + free means running an open-source model on
> your own GPU.

---

## Path A — Roblox Cube 3D (recommended starting point)

Roblox built its own text-to-3D model, **Cube 3D**. It generates a **textured
MeshPart from a text prompt**, right inside Studio, and saves it to your
inventory so you can reuse it. Free during beta. **This is the easiest way to
get real meshes into your game with zero import steps.**

### Generate a mesh (no code)

1. In Studio, open the **Assistant** panel (toolbar, or **View → Assistant**).
2. Type a generate command, for example:
   - `/generate a wooden treasure chest`
   - `/generate an orange traffic cone`
   - `/generate a low-poly sports car`
3. Wait a few seconds. The textured mesh is created and added to your
   **Toolbox → Inventory → My Creations**.
4. Drag it into your place. It's a normal `MeshPart` — move, scale, anchor, and
   script it like anything else.

### Tips for better Cube 3D results

- Keep prompts **concrete and single-object**: "a red mushroom with white
  spots" beats "a magical forest scene". Cube 3D makes **one object at a time**.
- Add a **style** word: `low-poly`, `cartoon`, `stylized`, `realistic`.
- It launched with prompt "schemas" — e.g. a 5-part **car** (body + 4 wheels)
  and a generic **single-mesh** object. Pick the closest to your subject.

### Generating in-game at runtime (players make meshes live)

If you want **players** to generate meshes inside a running experience, Roblox
exposes a Luau API (**`GenerationService`**):

- Enable it first: **File → Game Settings → Security → allow the Editable
  Mesh / Editable Image APIs**.
- Free in beta, **rate-limited (~5 generations / minute per experience)**.
- It runs **at runtime and needs a `Player`** — it is *not* meant to be called
  from an edit-mode plugin, and meshes made this way **don't persist outside
  that experience**. So use it for *gameplay* (a "build anything" feature),
  **not** for authoring reusable assets — for that, use the Assistant flow
  above.

> The exact method signature changes during beta. Check the Creator Hub
> "GenerationService" / "Mesh Generation" docs for the current `...Async`
> call before writing runtime code, or ask and I'll wire up a working script.

---

## Path B — Meshy.ai (best quality that's still free)

When Cube 3D isn't detailed enough, **Meshy** is the best free option. It does
**text-to-3D** and **image-to-3D** with proper PBR textures.

1. Sign up at **meshy.ai** (free tier includes monthly credits).
2. **Text to 3D** → enter a prompt (or **Image to 3D** → upload a reference
   picture, which usually gives better, more controllable results).
3. Pick a result, then **Download**. Choose **FBX** or **OBJ** if offered
   (Roblox can't import `.glb` directly — see conversion below).
4. Import into Studio (see **Importing into Roblox** section).

**Alternatives that work the same way:** **Tripo3D** (tripo3d.ai) and
**Rodin / Hyper3D** (hyper3d.ai) — all have free credit tiers and export
game-ready meshes. Try the same prompt in two of them and keep the better mesh.

---

## Path C — Fully free & unlimited (open-source, your own GPU)

If you have a decent GPU (or use a free Google Colab), you can run open-source
generators with no credit limits:

- **Hunyuan3D 2.x** (Tencent) — strong text/image-to-3D, textured.
- **TRELLIS** (Microsoft) — excellent image-to-3D.
- **TripoSR** — very fast image-to-3D, light on hardware.

These output `.glb`/`.obj`. Convert to `.fbx`/`.obj` for Roblox (below). This is
the most setup but the only path that's both **free and unlimited**.

---

## Converting `.glb` → `.fbx` (free, with Blender)

Roblox's importer takes **`.fbx`** and **`.obj`**, not `.glb`. If your tool only
gives `.glb`:

1. Install **Blender** (free, blender.org).
2. **File → Import → glTF 2.0 (.glb/.gltf)** and pick your file.
3. **File → Export → FBX (.fbx)**. Under export options, enable **"Path Mode:
   Copy"** and the **embed textures** button so textures travel with the file.
4. Use that `.fbx` in the import step below.

While you're in Blender you can also **decimate** a heavy mesh (see Optimizing).

---

## Importing into Roblox Studio

1. **Asset Manager** (View → Asset Manager) → **Bulk Import** (or use the
   **3D Importer** for a preview with scale/material options).
2. Select your `.fbx` / `.obj` (plus texture images if they're separate files).
3. Confirm. The mesh appears in your Asset Manager and as a `MeshPart` you can
   drag into the world.

### Applying textures (PBR)

- A single color/diffuse texture imports onto the MeshPart automatically.
- For full PBR (normal/metalness/roughness), add a **`SurfaceAppearance`** child
  to the MeshPart and set **ColorMap / NormalMap / MetalnessMap / RoughnessMap**
  to the uploaded texture images.
- **Note:** mesh *geometry* uploads are free and instant; **texture image
  uploads go through moderation** and can take a little time.

---

## Optimizing for Roblox (important!)

AI meshes are often far too dense for a game. Keep them light:

- **Triangle budget:** aim for **well under ~10k triangles** per mesh; Roblox
  rejects extremely high-poly meshes. Decimate in Blender
  (**Modifier → Decimate**, ratio ~0.1–0.5) until it looks right.
- **One material per mesh** where possible; bake multiple textures into one.
- Set **`RenderFidelity = Automatic`** and choose an appropriate
  **`CollisionFidelity`** (`Box` or `Hull` is much cheaper than `PreciseConvexDecomposition`).
- **Anchor** static props so physics doesn't simulate them.
- Reuse the same MeshPart asset many times instead of generating duplicates.

---

## Which should *I* use? (quick recommendation)

1. **Start with Cube 3D in the Assistant** (`/generate …`). Free, native, no
   import — great for props, items, and prototyping.
2. **When you need it to look better, use Meshy's free tier** (image-to-3D for
   the most control) and import the FBX.
3. **If you'll generate a lot**, set up an open-source model locally so you're
   not limited by credits.

All three are free to start, and all produce real meshes you can place, script,
and ship in your game.

---

## Sources

- Roblox Cube announcement — https://about.roblox.com/newsroom/2025/03/introducing-roblox-cube
- Cube 3D generation tools & APIs (Beta) — https://devforum.roblox.com/t/beta-cube-3d-generation-tools-and-apis-for-creators/3558947
- Roblox/cube (open-source model) — https://github.com/Roblox/cube
- Accelerating creation with Cube (2026) — https://about.roblox.com/newsroom/2026/02/accelerating-creation-powered-roblox-cube-foundation-model
