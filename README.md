# Prompt → 3D Model Maker

A **free, offline Roblox Studio plugin** that turns a text prompt into a 3D
model, right inside your place. Type something like `big red car`,
`green dragon`, or `glowing blue castle`, click **Generate**, and the plugin
builds a matching model out of Parts, drops it in front of your camera, selects
it, and adds it to the undo history.

It ships with a library of **140+ objects** across nature, animals, buildings,
vehicles, furniture, food, weapons, fantasy/sci-fi and toys.

No API keys. No internet connection. No cost. Everything runs locally in Studio,
so it's safe to use in any game project.

```
┌─ Prompt → 3D ───────────────┐
│ Prompt → 3D Model Maker      │
│ Describe something & Generate│
│ ┌──────────────────────────┐ │
│ │ wooden house             │ │
│ └──────────────────────────┘ │
│ [    Generate model       ]  │
│ [    🎲 Surprise me       ]  │
│ Built 'Wooden house' (7 …)   │
└──────────────────────────────┘
```

---

## Why a plugin (and not an AI text-to-3D site)?

This is a **procedural** model maker: it reads keywords from your prompt and
assembles a model from a library of hand-built shapes. That makes it instant,
100% free, and fully native to Roblox — the output is real `Part`s you can move,
recolour, weld, and script like anything else you build by hand. It does **not**
generate arbitrary meshes from any sentence the way a paid AI service would.

---

## Install

You only need to do this once. Pick whichever method suits you.

### Method A — Save as a Local Plugin (easiest, no extra tools)

1. Open **Roblox Studio** and any place.
2. In the **Explorer**, hover over `ServerScriptService`, click the **+**, and
   insert a **Script**.
3. Open [`src/PromptTo3DModelMaker.server.lua`](src/PromptTo3DModelMaker.server.lua),
   copy **all** of it, and paste it into the new Script (replace the default
   `print("Hello world!")`).
4. **Right-click the Script** in the Explorer → **Save as Local Plugin…**
5. Keep the suggested name and save. The plugin is now installed.
6. **Delete the Script** from `ServerScriptService` — it was only there so you
   could save it. (The plugin keeps running from the Plugins folder.)

> To update later, repeat the steps and overwrite the saved plugin.

### Method B — Build with [Rojo](https://rojo.space) (for developers)

This repo is a ready-to-build Rojo project.

```bash
# Build a plugin model file
rojo build -o PromptTo3DModelMaker.rbxmx
```

Then in Studio: drag `PromptTo3DModelMaker.rbxmx` into the viewport, right-click
the resulting Script → **Save as Local Plugin…**, and delete the temporary
instance. Or drop the `.rbxmx` straight into your local Plugins folder
(**Plugins → Plugins Folder** in Studio).

---

## Using it

1. Click the **Prompt → 3D** button on the **Plugins** tab to open the panel.
2. Type a prompt, e.g. `giant purple rocket`.
3. Click **Generate model** (or **🎲 Surprise me** for a random example).

The new model appears on the baseplate in front of your camera and is selected
in the Explorer. Press **Ctrl/Cmd + Z** to undo.

### Prompt format

A prompt is just `[size] [colour] [material] <object>` — every part except the
object is optional, and order is flexible.

| Prompt | Result |
| --- | --- |
| `house` | A default tan brick house |
| `big red car` | A larger, red car |
| `glowing blue castle` | A neon-material, blue stone tower |
| `tiny wooden sword` | A small, wood-textured sword |
| `gold coin` | A standing gold coin |

### Supported objects (140+)

**Buildings & scenery:** house · castle · tower · skyscraper · barn · windmill ·
lighthouse · temple · gazebo · fountain · well · bridge · wall · fence · tent ·
igloo · birdhouse · mailbox · staircase · ladder · sign · pyramid

**Nature:** tree · palm · cactus · flower · sunflower · mushroom · pumpkin ·
bush · rock · log · pond · cloud · coral · iceberg · volcano · island

**Animals:** dog · cat · fish · bird · duck · penguin · bee · butterfly · frog ·
pig · cow · sheep · chicken · rabbit · turtle · dragon · shark · whale · spider ·
snake

**Vehicles:** car · bus · train · airplane · helicopter · tank · submarine ·
boat · rocket · ufo · bicycle · motorcycle · wagon · sled · balloon

**Furniture & household:** chair · table · bench · bed · sofa · bookshelf ·
wardrobe · fridge · stove · bathtub · tv · computer · clock · lamp · vase ·
candle · crate · swing · slide · trampoline

**Food:** cake · cupcake · cookie · donut · icecream · pizza · burger · hotdog ·
apple · banana · mug · bottle

**Weapons & tools:** sword · axe · hammer · spear · bow · shield · cannon ·
bomb · torch · anvil · bucket · key

**Fantasy & sci-fi:** crown · wand · potion · gem · treasurechest · tombstone ·
skull · ghost · star · satellite · alien · robot

**Toys, sports & misc:** snowman · teddybear · soccerball · dice · kite ·
guitar · drum · trophy · coin · present · heart · moon · trafficcone ·
firehydrant · dumpster · campfire

Many synonyms work too (`cabin`→house, `katana`→sword, `spaceship`→rocket,
`bunny`→rabbit, `plane`→airplane, `couch`→sofa, `diamond`→gem, `chest`→treasure
chest, …). Multi-word prompts use the **last** recognised object word, so
`fire hydrant` builds a hydrant (not a fire) and `ice cream` builds ice cream.
If no object is recognised, the plugin builds a placeholder crystal and tells
you in the status line.

### Modifiers

- **Colours:** red, crimson, orange, yellow, gold, green, lime, teal, blue,
  navy, cyan, purple, violet, magenta, pink, brown, tan, black, white, gray,
  silver, maroon. Colour is applied to the model's main parts; accents (like
  tree leaves or car tyres) keep their own colour.
- **Materials:** wood, metal, neon, glass, grass, brick, stone, concrete,
  marble, granite, sand, ice, plastic, fabric, foil, diamond.
- **Sizes:** tiny, small, little, mini, big, large, huge, giant, gigantic,
  massive, enormous, colossal.

---

## Customising / adding your own objects

Open [`src/PromptTo3DModelMaker.server.lua`](src/PromptTo3DModelMaker.server.lua).
Each object is a small builder in the `BUILDERS` table that returns a list of
part specs. To add a new one, e.g. a `bench`:

```lua
BUILDERS.bench = function()
    local w = C(150, 100, 60)
    return {
        part(V(6, 0.5, 2), V(0, 2, 0), w, { mat = Enum.Material.Wood }),     -- seat
        part(V(0.5, 2, 0.5), V(-2.5, 1, 0.7), w, { role = "accent" }),        -- legs…
        part(V(0.5, 2, 0.5), V(2.5, 1, 0.7), w, { role = "accent" }),
    }
end
```

Then register the keyword so prompts can find it:

```lua
BUILDER_KEYWORDS.bench = "bench"
```

Helpers available to builders:

- `part(size, pos, color, opts)` — `size`/`pos` are `Vector3`s (studs, Y is up),
  `color` is a `Color3`. `opts` can set `shape` (`"block"`, `"ball"`,
  `"cylinder"`, `"wedge"`), `mat` (an `Enum.Material`), `rot` (a `Vector3` of
  degrees), and `role` (`"primary"` recolours with the prompt, `"accent"` keeps
  its colour).
- `C(r, g, b)` — shorthand for `Color3.fromRGB`.
- `V(x, y, z)` — shorthand for `Vector3.new`.

Parts are centred around the origin; the plugin automatically scales them and
sets the whole model down on the ground for you.

---

## License

MIT — see [LICENSE](LICENSE). Free to use and modify in your own games.
