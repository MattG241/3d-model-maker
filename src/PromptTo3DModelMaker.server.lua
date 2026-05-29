--[[
	Prompt → 3D Model Maker
	A free, offline Roblox Studio plugin.

	Type a text prompt (e.g. "big red car", "wooden house", "glowing castle")
	into the panel and click Generate. The plugin reads keywords from your
	prompt and builds a matching model out of Parts, places it in front of your
	camera, selects it, and adds it to the undo history.

	No API keys, no internet, no cost. Everything runs locally in Studio.

	See README.md for install instructions and the full list of supported
	objects and modifiers.
]]

--// Services ----------------------------------------------------------------
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

--// Small helpers -----------------------------------------------------------
local function C(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function V(x, y, z)
	return Vector3.new(x, y, z)
end

-- A part "spec" is just a plain table. `part()` fills in sensible defaults.
-- role = "primary" parts get recoloured when the prompt names a colour;
-- role = "accent" parts keep their own colour (e.g. tree leaves, car tyres).
local function part(size, pos, color, opts)
	opts = opts or {}
	return {
		size = size,
		pos = pos,
		color = color,
		mat = opts.mat,
		shape = opts.shape or "block", -- block | ball | cylinder | wedge
		rot = opts.rot, -- Vector3 of degrees, optional
		role = opts.role or "primary",
	}
end

--// Keyword libraries -------------------------------------------------------
local PART_SHAPES = {
	block = Enum.PartType.Block,
	ball = Enum.PartType.Ball,
	cylinder = Enum.PartType.Cylinder,
}

local COLORS = {
	red = C(196, 40, 28), crimson = C(150, 30, 30), scarlet = C(200, 35, 35),
	orange = C(218, 133, 65), yellow = C(245, 205, 48), gold = C(240, 200, 60),
	green = C(75, 151, 75), lime = C(160, 215, 60), teal = C(40, 150, 150),
	blue = C(45, 100, 220), navy = C(25, 45, 110), cyan = C(120, 210, 235),
	purple = C(130, 70, 200), violet = C(150, 90, 220), magenta = C(210, 50, 170),
	pink = C(235, 130, 180), brown = C(120, 75, 45), tan = C(214, 196, 158),
	black = C(30, 30, 30), white = C(245, 245, 245),
	gray = C(140, 140, 145), grey = C(140, 140, 145), silver = C(190, 190, 195),
	maroon = C(110, 30, 30),
}

local MATERIALS = {
	wood = Enum.Material.Wood, wooden = Enum.Material.Wood,
	plank = Enum.Material.WoodPlanks, planks = Enum.Material.WoodPlanks,
	metal = Enum.Material.Metal, metallic = Enum.Material.Metal, steel = Enum.Material.Metal,
	diamond = Enum.Material.DiamondPlate,
	neon = Enum.Material.Neon, glowing = Enum.Material.Neon, glow = Enum.Material.Neon,
	glass = Enum.Material.Glass, glassy = Enum.Material.Glass,
	grass = Enum.Material.Grass, grassy = Enum.Material.Grass,
	brick = Enum.Material.Brick, stone = Enum.Material.Slate, slate = Enum.Material.Slate,
	concrete = Enum.Material.Concrete, cobblestone = Enum.Material.Cobblestone,
	marble = Enum.Material.Marble, granite = Enum.Material.Granite,
	sand = Enum.Material.Sand, sandy = Enum.Material.Sand, sandstone = Enum.Material.Sandstone,
	ice = Enum.Material.Ice, icy = Enum.Material.Ice,
	plastic = Enum.Material.Plastic, fabric = Enum.Material.Fabric, foil = Enum.Material.Foil,
}

local SIZE_WORDS = {
	tiny = 0.45, mini = 0.5, small = 0.7, little = 0.7, smol = 0.6,
	big = 1.5, large = 1.5, huge = 2.2, giant = 3, gigantic = 3,
	massive = 3, enormous = 3, colossal = 3.5,
}

--// Model builders ----------------------------------------------------------
-- Each builder returns a list of part specs centred roughly around the origin
-- (Y is up). The assembler scales them, applies colour/material overrides,
-- then drops the finished model onto the ground in front of the camera.
local BUILDERS = {}

BUILDERS.house = function()
	local wall = C(214, 196, 158)
	local roof = C(120, 67, 40)
	local door = C(90, 55, 30)
	local glass = C(150, 210, 230)
	return {
		part(V(8, 5, 8), V(0, 2.5, 0), wall, { mat = Enum.Material.Brick }),
		-- stepped roof (reliable, no wedge-orientation guesswork)
		part(V(9, 1.4, 9), V(0, 5.7, 0), roof, { role = "accent", mat = Enum.Material.WoodPlanks }),
		part(V(6, 1.4, 6), V(0, 7.0, 0), roof, { role = "accent", mat = Enum.Material.WoodPlanks }),
		part(V(3, 1.4, 3), V(0, 8.3, 0), roof, { role = "accent", mat = Enum.Material.WoodPlanks }),
		part(V(2, 3, 0.4), V(0, 1.5, 4.05), door, { role = "accent", mat = Enum.Material.Wood }),
		part(V(1.6, 1.6, 0.3), V(-2.6, 3, 4.05), glass, { role = "accent", mat = Enum.Material.Glass }),
		part(V(1.6, 1.6, 0.3), V(2.6, 3, 4.05), glass, { role = "accent", mat = Enum.Material.Glass }),
	}
end

BUILDERS.tree = function()
	local trunk = C(104, 69, 40)
	local leaf = C(75, 151, 75)
	return {
		-- leaves are "primary" so "red tree" recolours the foliage, not the trunk
		part(V(6, 6, 6), V(0, 7.5, 0), leaf, { shape = "ball", mat = Enum.Material.Grass }),
		part(V(4.5, 4.5, 4.5), V(2.2, 9.2, 0), leaf, { shape = "ball", mat = Enum.Material.Grass }),
		part(V(4.5, 4.5, 4.5), V(-2.2, 9.0, 1), leaf, { shape = "ball", mat = Enum.Material.Grass }),
		part(V(6, 1.4, 1.4), V(0, 3, 0), trunk, { role = "accent", shape = "cylinder", rot = V(0, 0, 90), mat = Enum.Material.Wood }),
	}
end

BUILDERS.car = function()
	local body = C(196, 40, 28)
	local tyre = C(27, 27, 27)
	local glass = C(150, 210, 230)
	return {
		part(V(10, 2, 5), V(0, 2, 0), body, { mat = Enum.Material.Metal }),
		part(V(5, 2, 4.6), V(-0.4, 4, 0), body, { mat = Enum.Material.Metal }),
		part(V(3, 1.6, 4.7), V(-0.4, 4, 0), glass, { role = "accent", mat = Enum.Material.Glass }),
		part(V(1, 2, 2), V(3, 1, 2.6), tyre, { role = "accent", shape = "cylinder", rot = V(0, 90, 0) }),
		part(V(1, 2, 2), V(3, 1, -2.6), tyre, { role = "accent", shape = "cylinder", rot = V(0, 90, 0) }),
		part(V(1, 2, 2), V(-3, 1, 2.6), tyre, { role = "accent", shape = "cylinder", rot = V(0, 90, 0) }),
		part(V(1, 2, 2), V(-3, 1, -2.6), tyre, { role = "accent", shape = "cylinder", rot = V(0, 90, 0) }),
	}
end

BUILDERS.sword = function()
	local blade = C(200, 200, 210)
	local gold = C(225, 180, 60)
	local grip = C(90, 55, 30)
	return {
		part(V(0.4, 6, 1.1), V(0, 5, 0), blade, { mat = Enum.Material.Metal }),
		part(V(0.5, 0.8, 3.2), V(0, 1.7, 0), gold, { role = "accent", mat = Enum.Material.Metal }),
		part(V(2, 0.7, 0.7), V(0, 0.6, 0), grip, { role = "accent", shape = "cylinder" }),
		part(V(1, 1, 1), V(0, -0.6, 0), gold, { role = "accent", shape = "ball", mat = Enum.Material.Metal }),
	}
end

BUILDERS.chair = function()
	local w = C(150, 100, 60)
	return {
		part(V(3, 0.5, 3), V(0, 2, 0), w, { mat = Enum.Material.Wood }),
		part(V(3, 3, 0.5), V(0, 3.75, -1.25), w, { mat = Enum.Material.Wood }),
		part(V(0.5, 2, 0.5), V(-1.1, 1, 1.1), w, { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.5, 2, 0.5), V(1.1, 1, 1.1), w, { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.5, 2, 0.5), V(-1.1, 1, -1.1), w, { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.5, 2, 0.5), V(1.1, 1, -1.1), w, { role = "accent", mat = Enum.Material.Wood }),
	}
end

BUILDERS.table = function()
	local w = C(150, 100, 60)
	return {
		part(V(6, 0.5, 4), V(0, 3, 0), w, { mat = Enum.Material.Wood }),
		part(V(0.5, 3, 0.5), V(-2.5, 1.5, 1.5), w, { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.5, 3, 0.5), V(2.5, 1.5, 1.5), w, { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.5, 3, 0.5), V(-2.5, 1.5, -1.5), w, { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.5, 3, 0.5), V(2.5, 1.5, -1.5), w, { role = "accent", mat = Enum.Material.Wood }),
	}
end

BUILDERS.castle = function()
	local stone = C(150, 150, 155)
	local specs = {
		part(V(12, 8, 8), V(0, 6, 0), stone, { shape = "cylinder", rot = V(0, 0, 90), mat = Enum.Material.Slate }),
	}
	for i = 0, 7 do
		local ang = math.rad(i * 45)
		table.insert(specs, part(V(1.4, 2, 1.4), V(math.cos(ang) * 3.4, 12.5, math.sin(ang) * 3.4), stone, { role = "accent", mat = Enum.Material.Slate }))
	end
	return specs
end

BUILDERS.rocket = function()
	local body = C(235, 235, 235)
	local accent = C(200, 50, 50)
	local glass = C(120, 200, 235)
	local specs = {
		part(V(10, 3, 3), V(0, 5, 0), body, { shape = "cylinder", rot = V(0, 0, 90), mat = Enum.Material.Metal }),
		part(V(3, 3, 3), V(0, 10.2, 0), accent, { role = "accent", shape = "ball", mat = Enum.Material.Metal }),
		part(V(1.4, 1.4, 1.4), V(0, 6, 1.6), glass, { role = "accent", shape = "ball", mat = Enum.Material.Glass }),
	}
	for i = 0, 2 do
		local ang = i * 120
		local rad = math.rad(ang)
		table.insert(specs, part(V(2, 3, 0.4), V(math.cos(rad) * 1.6, 1.6, math.sin(rad) * 1.6), accent, { role = "accent", shape = "wedge", rot = V(0, -ang, 0), mat = Enum.Material.Metal }))
	end
	return specs
end

BUILDERS.robot = function()
	local metal = C(140, 150, 160)
	local eye = C(90, 200, 255)
	return {
		part(V(4, 4, 2), V(0, 5, 0), metal, { mat = Enum.Material.Metal }),
		part(V(2.4, 2.4, 2.4), V(0, 8.2, 0), metal, { mat = Enum.Material.Metal }),
		part(V(0.6, 0.6, 0.6), V(-0.6, 8.5, 1.2), eye, { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(0.6, 0.6, 0.6), V(0.6, 8.5, 1.2), eye, { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(1, 4, 1), V(-3, 5, 0), metal, { mat = Enum.Material.Metal }),
		part(V(1, 4, 1), V(3, 5, 0), metal, { mat = Enum.Material.Metal }),
		part(V(1.4, 3, 1.4), V(-1.1, 1.5, 0), metal, { mat = Enum.Material.Metal }),
		part(V(1.4, 3, 1.4), V(1.1, 1.5, 0), metal, { mat = Enum.Material.Metal }),
	}
end

BUILDERS.snowman = function()
	local snow = C(245, 245, 250)
	local coal = C(30, 30, 30)
	local nose = C(235, 140, 40)
	return {
		part(V(5, 5, 5), V(0, 2.5, 0), snow, { shape = "ball" }),
		part(V(3.6, 3.6, 3.6), V(0, 6.4, 0), snow, { shape = "ball" }),
		part(V(2.6, 2.6, 2.6), V(0, 9.4, 0), snow, { shape = "ball" }),
		part(V(0.4, 0.4, 0.4), V(-0.6, 9.9, 1.2), coal, { role = "accent", shape = "ball" }),
		part(V(0.4, 0.4, 0.4), V(0.6, 9.9, 1.2), coal, { role = "accent", shape = "ball" }),
		part(V(1.4, 0.5, 0.5), V(0, 9.4, 1.4), nose, { role = "accent", shape = "cylinder", rot = V(0, 90, 0) }),
		part(V(0.5, 0.5, 0.5), V(0, 6.8, 1.8), coal, { role = "accent", shape = "ball" }),
		part(V(0.5, 0.5, 0.5), V(0, 5.8, 1.9), coal, { role = "accent", shape = "ball" }),
	}
end

BUILDERS.flower = function()
	local petal = C(230, 90, 140)
	local center = C(245, 205, 60)
	local stem = C(70, 150, 70)
	local specs = {
		part(V(0.4, 5, 0.4), V(0, 2.5, 0), stem, { role = "accent", mat = Enum.Material.Grass }),
		part(V(1.6, 0.9, 1.6), V(0, 5.2, 0), center, { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
	}
	for i = 0, 5 do
		local ang = math.rad(i * 60)
		table.insert(specs, part(V(1.6, 0.6, 1.2), V(math.cos(ang) * 1.6, 5.2, math.sin(ang) * 1.6), petal, { shape = "ball" }))
	end
	return specs
end

BUILDERS.mushroom = function()
	local cap = C(200, 55, 45)
	local stem = C(235, 225, 205)
	local spot = C(245, 245, 245)
	return {
		part(V(3, 1.6, 1.6), V(0, 1.5, 0), stem, { role = "accent", shape = "cylinder", rot = V(0, 0, 90) }),
		part(V(5, 3, 5), V(0, 3.4, 0), cap, { shape = "ball" }),
		part(V(0.9, 0.9, 0.9), V(1.5, 4.2, 0), spot, { role = "accent", shape = "ball" }),
		part(V(0.9, 0.9, 0.9), V(-1.2, 4.2, 1), spot, { role = "accent", shape = "ball" }),
		part(V(0.8, 0.8, 0.8), V(0, 4.6, -1.4), spot, { role = "accent", shape = "ball" }),
	}
end

BUILDERS.crate = function()
	local wood = C(170, 120, 70)
	local trim = C(120, 80, 45)
	return {
		part(V(4, 4, 4), V(0, 2, 0), wood, { mat = Enum.Material.WoodPlanks }),
		part(V(4.2, 0.5, 0.5), V(0, 3.8, 1.8), trim, { role = "accent", mat = Enum.Material.Wood }),
		part(V(4.2, 0.5, 0.5), V(0, 0.2, 1.8), trim, { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.5, 4.2, 0.5), V(1.8, 2, 1.8), trim, { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.5, 4.2, 0.5), V(-1.8, 2, 1.8), trim, { role = "accent", mat = Enum.Material.Wood }),
	}
end

BUILDERS.lamp = function()
	local metal = C(60, 60, 65)
	local glow = C(255, 235, 150)
	return {
		part(V(8, 0.5, 0.5), V(0, 4, 0), metal, { shape = "cylinder", rot = V(0, 0, 90), mat = Enum.Material.Metal }),
		part(V(2, 0.5, 0.5), V(1, 7.8, 0), metal, { role = "accent", shape = "cylinder", mat = Enum.Material.Metal }),
		part(V(1.4, 1, 1.4), V(2, 7.4, 0), metal, { role = "accent", mat = Enum.Material.Metal }),
		part(V(1, 1, 1), V(2, 6.8, 0), glow, { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
	}
end

BUILDERS.boat = function()
	local hull = C(120, 75, 45)
	local sail = C(245, 245, 245)
	local mast = C(90, 60, 35)
	return {
		part(V(10, 2, 4), V(0, 1, 0), hull, { mat = Enum.Material.Wood }),
		part(V(2, 2, 4), V(6, 1, 0), hull, { role = "accent", shape = "wedge", rot = V(0, 90, 0), mat = Enum.Material.Wood }),
		part(V(0.6, 8, 0.6), V(0, 5, 0), mast, { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.4, 5, 4), V(0, 5, 0), sail, { mat = Enum.Material.Fabric }),
	}
end

BUILDERS.campfire = function()
	local log = C(110, 70, 40)
	local flame = C(245, 130, 40)
	local flame2 = C(240, 210, 70)
	local specs = {}
	for i = 0, 3 do
		table.insert(specs, part(V(4, 0.8, 0.8), V(0, 0.5, 0), log, { role = "accent", shape = "cylinder", rot = V(0, i * 45, 0), mat = Enum.Material.Wood }))
	end
	table.insert(specs, part(V(2.5, 3, 2.5), V(0, 2, 0), flame, { shape = "ball", mat = Enum.Material.Neon }))
	table.insert(specs, part(V(1.4, 2, 1.4), V(0, 2.6, 0), flame2, { shape = "ball", mat = Enum.Material.Neon }))
	return specs
end

BUILDERS.coin = function()
	local gold = C(240, 200, 60)
	return {
		part(V(0.5, 4, 4), V(0, 2, 0), gold, { shape = "cylinder", rot = V(0, 90, 0), mat = Enum.Material.Metal }),
	}
end

BUILDERS.pyramid = function()
	local sand = C(225, 205, 140)
	local specs = {}
	for i = 0, 5 do
		local w = 10 - i * 1.6
		table.insert(specs, part(V(w, 1.6, w), V(0, 0.8 + i * 1.6, 0), sand, { mat = Enum.Material.Sandstone }))
	end
	return specs
end

BUILDERS.fence = function()
	local w = C(150, 100, 60)
	local specs = {}
	for i = 0, 3 do
		table.insert(specs, part(V(0.6, 4, 0.6), V(-6 + i * 4, 2, 0), w, { role = "accent", mat = Enum.Material.Wood }))
	end
	table.insert(specs, part(V(13, 0.6, 0.6), V(-1, 3, 0), w, { mat = Enum.Material.Wood }))
	table.insert(specs, part(V(13, 0.6, 0.6), V(-1, 1.4, 0), w, { mat = Enum.Material.Wood }))
	return specs
end

-- Built when the prompt doesn't match anything we know how to build.
local function fallbackBuilder()
	local crystal = C(120, 90, 220)
	return {
		part(V(2, 4, 2), V(0, 3, 0), crystal, { rot = V(0, 45, 0), mat = Enum.Material.Neon }),
		part(V(1.4, 2.6, 1.4), V(1.6, 2, 0), crystal, { role = "accent", rot = V(0, 30, 0), mat = Enum.Material.Neon }),
		part(V(1.2, 2.2, 1.2), V(-1.5, 1.8, 0.4), crystal, { role = "accent", rot = V(0, 60, 0), mat = Enum.Material.Neon }),
		part(V(4, 0.6, 4), V(0, 0.3, 0), C(90, 90, 95), { role = "accent", mat = Enum.Material.Slate }),
	}
end

-- Maps the many words a player might type to a canonical builder name.
local BUILDER_KEYWORDS = {
	house = "house", home = "house", cabin = "house", cottage = "house", hut = "house", shack = "house", building = "house",
	tree = "tree", oak = "tree", pine = "tree", bush = "tree",
	car = "car", vehicle = "car", truck = "car", automobile = "car", racecar = "car", jeep = "car",
	sword = "sword", blade = "sword", katana = "sword", dagger = "sword", excalibur = "sword",
	chair = "chair", seat = "chair", stool = "chair", throne = "chair",
	table = "table", desk = "table",
	castle = "castle", tower = "castle", fortress = "castle", keep = "castle", turret = "castle",
	rocket = "rocket", spaceship = "rocket", missile = "rocket", spacecraft = "rocket",
	robot = "robot", bot = "robot", mech = "robot", android = "robot", droid = "robot",
	snowman = "snowman",
	flower = "flower", rose = "flower", tulip = "flower", daisy = "flower",
	mushroom = "mushroom", toadstool = "mushroom", shroom = "mushroom",
	crate = "crate", box = "crate", chest = "crate", cargo = "crate", barrel = "crate",
	lamp = "lamp", lantern = "lamp", streetlight = "lamp", lamppost = "lamp", light = "lamp",
	boat = "boat", ship = "boat", canoe = "boat", sailboat = "boat", raft = "boat",
	campfire = "campfire", bonfire = "campfire", fire = "campfire", fireplace = "campfire",
	coin = "coin", token = "coin", medallion = "coin",
	pyramid = "pyramid", tomb = "pyramid",
	fence = "fence", gate = "fence", railing = "fence",
}

-- A friendly, ordered list for the help text and the "surprise me" button.
local SUPPORTED_ORDER = {
	"house", "tree", "car", "sword", "chair", "table", "castle", "rocket",
	"robot", "snowman", "flower", "mushroom", "crate", "lamp", "boat",
	"campfire", "coin", "pyramid", "fence",
}

local EXAMPLE_PROMPTS = {
	"big red car", "wooden cabin", "glowing blue castle", "giant tree",
	"golden sword", "neon robot", "purple rocket", "snowman", "tiny mushroom",
	"stone tower", "pink flower", "metal crate", "small sailboat", "gold coin",
}

--// Prompt parsing ----------------------------------------------------------
local function parsePrompt(text)
	text = text or ""
	local lower = string.lower(text)

	local words = {}
	for w in string.gmatch(lower, "%a+") do
		table.insert(words, w)
	end

	local result = {
		scale = 1,
		color = nil,
		colorName = nil,
		material = nil,
		type = nil,
		recognized = false,
	}

	for _, w in ipairs(words) do
		if not result.type then
			local t = BUILDER_KEYWORDS[w]
			-- crude singular fallback: "houses" -> "house"
			if not t and #w > 3 and string.sub(w, -1) == "s" then
				t = BUILDER_KEYWORDS[string.sub(w, 1, -2)]
			end
			if t then
				result.type = t
				result.recognized = true
			end
		end
		if not result.color and COLORS[w] then
			result.color = COLORS[w]
			result.colorName = w
		end
		if not result.material and MATERIALS[w] then
			result.material = MATERIALS[w]
		end
		if SIZE_WORDS[w] then
			result.scale = SIZE_WORDS[w]
		end
	end

	-- Build a tidy model name from the original prompt.
	local trimmed = string.gsub(text, "^%s*(.-)%s*$", "%1")
	if trimmed == "" then
		trimmed = result.type or "Model"
	end
	result.modelName = (string.upper(string.sub(trimmed, 1, 1)) .. string.sub(trimmed, 2))

	return result
end

--// Model assembly ----------------------------------------------------------
local function createPart(spec, scale)
	local className = (spec.shape == "wedge") and "WedgePart" or "Part"
	local p = Instance.new(className)
	p.Anchored = true
	p.Size = spec.size * scale
	if p:IsA("Part") then
		p.Shape = PART_SHAPES[spec.shape] or Enum.PartType.Block
	end
	local cf = CFrame.new(spec.pos * scale)
	if spec.rot then
		cf = cf * CFrame.Angles(math.rad(spec.rot.X), math.rad(spec.rot.Y), math.rad(spec.rot.Z))
	end
	p.CFrame = cf
	return p
end

local function buildModel(parsed)
	local builder = parsed.type and BUILDERS[parsed.type] or fallbackBuilder
	local specs = builder()

	local model = Instance.new("Model")
	model.Name = parsed.modelName

	local firstPrimary
	for _, spec in ipairs(specs) do
		local p = createPart(spec, parsed.scale)

		local color = spec.color
		if parsed.color and spec.role ~= "accent" then
			color = parsed.color
		end
		p.Color = color
		p.Material = parsed.material or spec.mat or Enum.Material.SmoothPlastic

		p.Parent = model
		if not firstPrimary and spec.role ~= "accent" then
			firstPrimary = p
		end
	end

	model.PrimaryPart = firstPrimary or model:FindFirstChildWhichIsA("BasePart")
	return model
end

-- Drops the model onto the baseplate in front of the current camera.
local function placeModel(model)
	model.Parent = Workspace

	local target = Vector3.new(0, 0, 0)
	local camera = Workspace.CurrentCamera
	if camera then
		local cf = camera.CFrame
		target = cf.Position + cf.LookVector * 24
	end

	local boundsCFrame, size = model:GetBoundingBox()
	local goalCenter = Vector3.new(target.X, size.Y / 2 + 0.5, target.Z)
	model:PivotTo(model:GetPivot() + (goalCenter - boundsCFrame.Position))
end

local function generate(promptText)
	local parsed = parsePrompt(promptText)

	local recording = ChangeHistoryService:TryBeginRecording("PromptTo3D_Generate", "Generate 3D model")
	local model = buildModel(parsed)
	placeModel(model)
	Selection:Set({ model })
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end

	return parsed, model
end

--// User interface ----------------------------------------------------------
local ACCENT = Color3.fromRGB(88, 130, 240)
local BG = Color3.fromRGB(46, 46, 48)
local FIELD = Color3.fromRGB(32, 32, 34)
local TEXT = Color3.fromRGB(235, 235, 235)
local MUTED = Color3.fromRGB(165, 165, 170)

local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 6)
	c.Parent = inst
	return inst
end

local function buildUI(widget)
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = BG
	root.BorderSizePixel = 0
	root.Parent = widget

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = root

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = TEXT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Prompt → 3D Model Maker"
	title.LayoutOrder = nextOrder()
	title.Parent = root

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, 0, 0, 16)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 12
	subtitle.TextColor3 = MUTED
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = "Describe something and click Generate."
	subtitle.LayoutOrder = nextOrder()
	subtitle.Parent = root

	local textBox = Instance.new("TextBox")
	textBox.Size = UDim2.new(1, 0, 0, 40)
	textBox.BackgroundColor3 = FIELD
	textBox.BorderSizePixel = 0
	textBox.Font = Enum.Font.Gotham
	textBox.TextSize = 14
	textBox.TextColor3 = TEXT
	textBox.PlaceholderText = "e.g. big red car"
	textBox.PlaceholderColor3 = MUTED
	textBox.Text = "wooden house"
	textBox.ClearTextOnFocus = false
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.TextWrapped = true
	textBox.LayoutOrder = nextOrder()
	textBox.Parent = root
	corner(textBox)
	local boxPad = Instance.new("UIPadding")
	boxPad.PaddingLeft = UDim.new(0, 8)
	boxPad.PaddingRight = UDim.new(0, 8)
	boxPad.Parent = textBox

	local generateButton = Instance.new("TextButton")
	generateButton.Size = UDim2.new(1, 0, 0, 36)
	generateButton.BackgroundColor3 = ACCENT
	generateButton.BorderSizePixel = 0
	generateButton.AutoButtonColor = true
	generateButton.Font = Enum.Font.GothamBold
	generateButton.TextSize = 15
	generateButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	generateButton.Text = "Generate model"
	generateButton.LayoutOrder = nextOrder()
	generateButton.Parent = root
	corner(generateButton)

	local surpriseButton = Instance.new("TextButton")
	surpriseButton.Size = UDim2.new(1, 0, 0, 26)
	surpriseButton.BackgroundColor3 = FIELD
	surpriseButton.BorderSizePixel = 0
	surpriseButton.AutoButtonColor = true
	surpriseButton.Font = Enum.Font.Gotham
	surpriseButton.TextSize = 13
	surpriseButton.TextColor3 = TEXT
	surpriseButton.Text = "🎲 Surprise me"
	surpriseButton.LayoutOrder = nextOrder()
	surpriseButton.Parent = root
	corner(surpriseButton)

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, 0, 0, 40)
	status.Font = Enum.Font.Gotham
	status.TextSize = 12
	status.TextColor3 = MUTED
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextYAlignment = Enum.TextYAlignment.Top
	status.TextWrapped = true
	status.Text = "Ready."
	status.LayoutOrder = nextOrder()
	status.Parent = root

	local help = Instance.new("TextLabel")
	help.BackgroundTransparency = 1
	help.Size = UDim2.new(1, 0, 0, 90)
	help.Font = Enum.Font.Gotham
	help.TextSize = 11
	help.TextColor3 = MUTED
	help.TextXAlignment = Enum.TextXAlignment.Left
	help.TextYAlignment = Enum.TextYAlignment.Top
	help.TextWrapped = true
	help.Text = "Try: " .. table.concat(SUPPORTED_ORDER, ", ")
		.. ".\nAdd colours (red, blue, gold…), materials (wood, metal, neon, glass…) and sizes (tiny, big, giant)."
	help.LayoutOrder = nextOrder()
	help.Parent = root

	return {
		textBox = textBox,
		generateButton = generateButton,
		surpriseButton = surpriseButton,
		status = status,
	}
end

--// Bootstrap ---------------------------------------------------------------
local toolbar = plugin:CreateToolbar("Prompt → 3D")
local button = toolbar:CreateButton(
	"PromptTo3D_Toggle",
	"Open the Prompt → 3D Model Maker",
	"",
	"Prompt → 3D"
)
button.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false, -- initially enabled
	false, -- override previous saved state
	300, 420, -- default size
	240, 320 -- minimum size
)
local widget = plugin:CreateDockWidgetPluginGui("PromptTo3D_Widget", widgetInfo)
widget.Title = "Prompt → 3D"

local ui = buildUI(widget)

local function setStatus(parsed, model)
	local count = #model:GetChildren()
	if parsed.recognized then
		ui.status.TextColor3 = MUTED
		ui.status.Text = string.format("Built '%s' (%d parts). It's selected in the Explorer.", model.Name, count)
	else
		ui.status.TextColor3 = Color3.fromRGB(235, 180, 90)
		ui.status.Text = "Didn't recognise an object, so I made a placeholder crystal. Try a word like: house, tree, car, sword, castle…"
	end
end

local function doGenerate()
	local promptText = ui.textBox.Text
	local ok, parsedOrErr, model = pcall(generate, promptText)
	if ok then
		setStatus(parsedOrErr, model)
	else
		ui.status.TextColor3 = Color3.fromRGB(235, 110, 110)
		ui.status.Text = "Something went wrong: " .. tostring(parsedOrErr)
	end
end

ui.generateButton.Activated:Connect(doGenerate)

ui.surpriseButton.Activated:Connect(function()
	ui.textBox.Text = EXAMPLE_PROMPTS[math.random(1, #EXAMPLE_PROMPTS)]
	doGenerate()
end)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
end)

button:SetActive(widget.Enabled)
