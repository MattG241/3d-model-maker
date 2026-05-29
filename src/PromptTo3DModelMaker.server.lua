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

-- A cylinder standing on its end (axis along Y). `length` is the height.
local function cylY(dia, length, pos, color, opts)
	opts = opts or {}
	opts.shape = "cylinder"
	opts.rot = V(0, 0, 90)
	return part(V(length, dia, dia), pos, color, opts)
end

-- A flat disk facing the camera (axis along Z). `thick` is the thickness.
local function cylZ(dia, thick, pos, color, opts)
	opts = opts or {}
	opts.shape = "cylinder"
	opts.rot = V(0, 90, 0)
	return part(V(thick, dia, dia), pos, color, opts)
end

-- Appends four legs (one per corner) to a spec list. Handy for furniture/animals.
local function legs4(specs, legSize, halfX, halfZ, yCenter, color, opts)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			table.insert(specs, part(legSize, V(sx * halfX, yCenter, sz * halfZ), color, opts))
		end
	end
end

-- Appends `count` specs arranged in a circle, calling makeSpec(x, z, angleDeg, i).
local function ring(specs, count, radius, makeSpec)
	for i = 0, count - 1 do
		local deg = i * 360 / count
		local rad = math.rad(deg)
		table.insert(specs, makeSpec(math.cos(rad) * radius, math.sin(rad) * radius, deg, i))
	end
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
	local trim = C(150, 110, 80)
	return {
		part(V(9, 0.8, 9), V(0, 0.4, 0), C(120, 120, 125), { role = "accent", mat = Enum.Material.Slate }), -- foundation
		part(V(8, 5, 8), V(0, 2.9, 0), wall, { mat = Enum.Material.Brick }),
		-- stepped roof (reliable, no wedge-orientation guesswork)
		part(V(9, 1.4, 9), V(0, 6.1, 0), roof, { role = "accent", mat = Enum.Material.WoodPlanks }),
		part(V(6, 1.4, 6), V(0, 7.4, 0), roof, { role = "accent", mat = Enum.Material.WoodPlanks }),
		part(V(3, 1.4, 3), V(0, 8.7, 0), roof, { role = "accent", mat = Enum.Material.WoodPlanks }),
		part(V(1.2, 3, 1.2), V(-2.6, 7.5, -2.6), C(110, 60, 50), { role = "accent", mat = Enum.Material.Brick }), -- chimney
		part(V(2, 3.2, 0.4), V(0, 2, 4.05), door, { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.3, 0.3, 0.3), V(0.7, 2, 4.3), C(230, 200, 60), { role = "accent", shape = "ball", mat = Enum.Material.Metal }), -- door knob
		part(V(1.6, 1.6, 0.3), V(-2.6, 3.4, 4.05), glass, { role = "accent", mat = Enum.Material.Glass }),
		part(V(1.6, 1.6, 0.3), V(2.6, 3.4, 4.05), glass, { role = "accent", mat = Enum.Material.Glass }),
		part(V(1.9, 0.3, 0.45), V(-2.6, 3.4, 4.1), trim, { role = "accent", mat = Enum.Material.Wood }), -- window sills
		part(V(1.9, 0.3, 0.45), V(2.6, 3.4, 4.1), trim, { role = "accent", mat = Enum.Material.Wood }),
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
	local hub = C(190, 190, 195)
	local glass = C(150, 210, 230)
	local specs = {
		part(V(10, 2, 5), V(0, 2, 0), body, { mat = Enum.Material.Metal }),
		part(V(5, 2, 4.6), V(-0.4, 4, 0), body, { mat = Enum.Material.Metal }),
		part(V(3, 1.6, 4.7), V(-0.4, 4, 0), glass, { role = "accent", mat = Enum.Material.Glass }),
		part(V(1.2, 1.4, 5.2), V(5, 1.4, 0), C(70, 70, 72), { role = "accent", mat = Enum.Material.Metal }), -- front bumper
		part(V(1.2, 1.4, 5.2), V(-5, 1.4, 0), C(70, 70, 72), { role = "accent", mat = Enum.Material.Metal }), -- rear bumper
		part(V(0.4, 0.8, 0.8), V(5.1, 2.2, 1.6), C(255, 245, 180), { role = "accent", shape = "ball", mat = Enum.Material.Neon }), -- headlights
		part(V(0.4, 0.8, 0.8), V(5.1, 2.2, -1.6), C(255, 245, 180), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(0.4, 0.6, 0.6), V(-5.1, 2.2, 1.6), C(220, 60, 60), { role = "accent", shape = "ball", mat = Enum.Material.Neon }), -- tail lights
		part(V(0.4, 0.6, 0.6), V(-5.1, 2.2, -1.6), C(220, 60, 60), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
	}
	for _, x in ipairs({ 3, -3 }) do
		for _, z in ipairs({ 2.6, -2.6 }) do
			table.insert(specs, part(V(1, 2, 2), V(x, 1, z), tyre, { role = "accent", shape = "cylinder", rot = V(0, 90, 0) }))
			table.insert(specs, part(V(1.1, 0.9, 0.9), V(x, 1, z), hub, { role = "accent", shape = "cylinder", rot = V(0, 90, 0), mat = Enum.Material.Metal }))
		end
	end
	return specs
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

--===========================================================================
-- NATURE
--===========================================================================
BUILDERS.cactus = function()
	local g = C(70, 150, 80)
	return {
		cylY(2.4, 8, V(0, 4, 0), g, { mat = Enum.Material.Grass }),
		part(V(2.2, 1.4, 1.4), V(-1.7, 4.8, 0), g, { role = "accent", shape = "cylinder" }),
		cylY(1.4, 2.6, V(-2.6, 6, 0), g, { role = "accent" }),
		part(V(2.2, 1.4, 1.4), V(1.7, 4.2, 0), g, { role = "accent", shape = "cylinder" }),
		cylY(1.4, 2.8, V(2.6, 5.4, 0), g, { role = "accent" }),
		part(V(0.4, 0.6, 0.4), V(0, 8.2, 0), C(235, 120, 160), { role = "accent", shape = "ball", mat = Enum.Material.Neon }), -- flower
	}
end

BUILDERS.palm = function()
	local trunk = C(150, 110, 70)
	local leaf = C(70, 160, 90)
	local specs = {
		part(V(10, 1.6, 1.6), V(0, 5, 0), trunk, { shape = "cylinder", rot = V(0, 0, 78), mat = Enum.Material.Wood }),
		part(V(1.4, 1.4, 1.4), V(1.5, 10, 0), C(120, 90, 55), { role = "accent", shape = "ball" }),
	}
	ring(specs, 6, 2.6, function(x, z, deg)
		return part(V(5, 0.5, 2), V(1.5 + x, 10, z), leaf, { role = "accent", shape = "ball", rot = V(0, -deg, 12), mat = Enum.Material.Grass })
	end)
	for i = 0, 2 do
		table.insert(specs, part(V(0.7, 0.7, 0.7), V(1.5, 9.2 - i * 0.3, 0.4 - i * 0.3), C(150, 110, 60), { role = "accent", shape = "ball" })) -- coconuts
	end
	return specs
end

BUILDERS.rock = function()
	local s = C(120, 120, 125)
	return {
		part(V(5, 3.5, 4.5), V(0, 1.6, 0), s, { rot = V(8, 20, 6), mat = Enum.Material.Slate }),
		part(V(2.6, 2, 2.2), V(2, 1.2, 1.4), s, { role = "accent", rot = V(0, 40, 10), mat = Enum.Material.Slate }),
		part(V(2, 1.6, 1.8), V(-1.8, 1, -1), s, { role = "accent", rot = V(0, -30, 8), mat = Enum.Material.Slate }),
	}
end

BUILDERS.pond = function()
	local water = C(60, 130, 200)
	local edge = C(110, 150, 90)
	return {
		cylY(11, 0.6, V(0, 0.2, 0), edge, { role = "accent", mat = Enum.Material.Grass }),
		cylY(10, 0.6, V(0, 0.45, 0), water, { mat = Enum.Material.Glass }),
		part(V(1.6, 0.3, 1.6), V(2, 0.8, 1.5), C(90, 170, 90), { role = "accent", shape = "ball" }),
		part(V(1.2, 0.3, 1.2), V(-2, 0.8, -1), C(90, 170, 90), { role = "accent", shape = "ball" }),
	}
end

BUILDERS.cloud = function()
	local w = C(245, 245, 250)
	return {
		part(V(5, 3.5, 4), V(0, 3, 0), w, { shape = "ball" }),
		part(V(4, 3, 3.5), V(-3, 2.6, 0), w, { shape = "ball" }),
		part(V(4, 3, 3.5), V(3, 2.6, 0), w, { shape = "ball" }),
		part(V(3.4, 2.6, 3), V(0.6, 3.4, -1.4), w, { shape = "ball" }),
	}
end

BUILDERS.log = function()
	local b = C(120, 80, 45)
	local r = C(180, 140, 95)
	return {
		part(V(8, 2.4, 2.4), V(0, 1.4, 0), b, { shape = "cylinder", mat = Enum.Material.Wood }),
		part(V(0.3, 2.5, 2.5), V(4, 1.4, 0), r, { role = "accent", shape = "cylinder", mat = Enum.Material.Wood }),
		part(V(0.3, 2.5, 2.5), V(-4, 1.4, 0), r, { role = "accent", shape = "cylinder", mat = Enum.Material.Wood }),
	}
end

BUILDERS.pumpkin = function()
	local o = C(225, 120, 35)
	return {
		part(V(5, 4, 5), V(0, 2.2, 0), o, { shape = "ball" }),
		part(V(4, 4.2, 4), V(0, 2.2, 0), o, { role = "accent", shape = "ball" }),
		part(V(3, 4.3, 3), V(0, 2.2, 0), o, { role = "accent", shape = "ball" }),
		part(V(0.8, 1.4, 0.8), V(0, 4.6, 0), C(110, 90, 50), { role = "accent", mat = Enum.Material.Wood }),
	}
end

BUILDERS.sunflower = function()
	local y = C(245, 205, 50)
	local center = C(110, 70, 40)
	local stem = C(70, 150, 70)
	local specs = {
		part(V(0.5, 7, 0.5), V(0, 3.5, 0), stem, { role = "accent", mat = Enum.Material.Grass }),
		part(V(1.2, 3, 0.3), V(0.7, 4.5, 0), stem, { role = "accent", mat = Enum.Material.Grass, rot = V(0, 0, 40) }),
		cylZ(2.4, 0.8, V(0, 7.4, 0), center, { role = "accent" }),
	}
	ring(specs, 10, 2.2, function(x, z, deg)
		return part(V(0.8, 1.8, 0.4), V(x, 7.4 + z, 0.2), y, { rot = V(0, 0, -deg) })
	end)
	return specs
end

BUILDERS.coral = function()
	local c = C(235, 110, 120)
	return {
		cylY(1.4, 4, V(0, 2, 0), c),
		part(V(3, 1.1, 1.1), V(-1.2, 3.4, 0), c, { role = "accent", shape = "cylinder", rot = V(0, 0, 55) }),
		part(V(3, 1.1, 1.1), V(1.2, 3.4, 0), c, { role = "accent", shape = "cylinder", rot = V(0, 0, -55) }),
		part(V(2.4, 1, 1), V(0, 4.4, 1), c, { role = "accent", shape = "cylinder", rot = V(40, 0, 0) }),
		part(V(0.9, 0.9, 0.9), V(-2.4, 4.6, 0), c, { role = "accent", shape = "ball" }),
		part(V(0.9, 0.9, 0.9), V(2.4, 4.6, 0), c, { role = "accent", shape = "ball" }),
	}
end

BUILDERS.iceberg = function()
	local ice = C(190, 225, 240)
	return {
		part(V(7, 5, 6), V(0, 2.4, 0), ice, { rot = V(0, 20, 0), mat = Enum.Material.Ice }),
		part(V(3, 4, 3), V(2.4, 3.4, 1), ice, { role = "accent", rot = V(8, 40, 6), mat = Enum.Material.Ice }),
		part(V(2.6, 3, 2.6), V(-2.4, 2.6, -1), ice, { role = "accent", rot = V(0, -30, 0), mat = Enum.Material.Ice }),
	}
end

BUILDERS.volcano = function()
	local rock = C(90, 70, 65)
	local lava = C(240, 90, 30)
	local specs = {}
	for i = 0, 4 do
		local w = 12 - i * 2
		table.insert(specs, cylY(w, 2, V(0, 1 + i * 2, 0), rock, { mat = Enum.Material.Slate }))
	end
	table.insert(specs, cylY(3, 1, V(0, 10.2, 0), lava, { shape = "cylinder", mat = Enum.Material.Neon }))
	return specs
end

BUILDERS.island = function()
	local sand = C(225, 205, 140)
	local water = C(60, 140, 205)
	local trunk = C(150, 110, 70)
	local leaf = C(70, 160, 90)
	local specs = {
		cylY(16, 0.6, V(0, 0.3, 0), water, { mat = Enum.Material.Glass }),
		cylY(10, 1.6, V(0, 0.8, 0), sand, { mat = Enum.Material.Sand }),
		part(V(6, 1.2, 1.2), V(1, 4, 0), trunk, { role = "accent", shape = "cylinder", rot = V(0, 0, 70), mat = Enum.Material.Wood }),
	}
	ring(specs, 4, 0, function(_, _, deg)
		return part(V(4, 0.5, 2), V(2.6, 7, 0), leaf, { role = "accent", shape = "ball", rot = V(0, deg, 10), mat = Enum.Material.Grass })
	end)
	return specs
end

--===========================================================================
-- ANIMALS
--===========================================================================
BUILDERS.dog = function()
	local f = C(165, 120, 75)
	local d = C(95, 65, 40)
	local specs = {
		part(V(5, 2.4, 2.2), V(0, 2.4, 0), f),
		part(V(2.2, 2.2, 2), V(3, 3, 0), f),
		part(V(1.2, 1, 1), V(4.2, 2.6, 0), d, { role = "accent" }),
		part(V(0.4, 0.4, 0.4), V(4.9, 2.8, 0), C(30, 30, 30), { role = "accent", shape = "ball" }),
		part(V(0.6, 1.1, 0.7), V(2.5, 4.2, 0.7), d, { role = "accent" }),
		part(V(0.6, 1.1, 0.7), V(2.5, 4.2, -0.7), d, { role = "accent" }),
		part(V(2, 0.6, 0.6), V(-3, 3, 0), f, { role = "accent", rot = V(0, 0, 35) }),
	}
	legs4(specs, V(0.7, 1.8, 0.7), 1.8, 0.8, 1.1, d, { role = "accent" })
	return specs
end

BUILDERS.cat = function()
	local f = C(120, 120, 125)
	local specs = {
		part(V(4.2, 2, 2), V(0, 2.2, 0), f),
		part(V(1.9, 1.9, 1.8), V(2.6, 2.9, 0), f),
		part(V(0.6, 0.9, 0.3), V(2.4, 4.1, 0.6), f, { role = "accent" }),
		part(V(0.6, 0.9, 0.3), V(2.4, 4.1, -0.6), f, { role = "accent" }),
		part(V(0.35, 0.35, 0.35), V(3.5, 3, 0.5), C(110, 200, 120), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(0.35, 0.35, 0.35), V(3.5, 3, -0.5), C(110, 200, 120), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(2.4, 0.5, 0.5), V(-2.6, 3.2, 0), f, { role = "accent", rot = V(0, 0, 55) }),
	}
	legs4(specs, V(0.6, 1.6, 0.6), 1.4, 0.7, 1, f, { role = "accent" })
	return specs
end

BUILDERS.fish = function()
	local b = C(235, 140, 60)
	return {
		part(V(4, 2.6, 2), V(0, 2.5, 0), b, { shape = "ball" }),
		part(V(1.6, 2, 0.4), V(-2.4, 2.5, 0), b, { role = "accent", rot = V(0, 0, 0) }),
		part(V(1.2, 1.4, 0.3), V(0, 4, 0), b, { role = "accent" }),
		part(V(0.4, 0.4, 0.4), V(1.6, 3, 0.9), C(30, 30, 30), { role = "accent", shape = "ball" }),
		part(V(0.4, 0.4, 0.4), V(1.6, 3, -0.9), C(30, 30, 30), { role = "accent", shape = "ball" }),
	}
end

BUILDERS.bird = function()
	local b = C(90, 150, 220)
	return {
		part(V(2.6, 2.4, 2.2), V(0, 2.6, 0), b, { shape = "ball" }),
		part(V(1.8, 1.8, 1.8), V(1.2, 3.8, 0), b, { role = "accent", shape = "ball" }),
		part(V(0.8, 0.6, 0.6), V(2.1, 3.7, 0), C(240, 170, 40), { role = "accent" }),
		part(V(0.3, 0.3, 0.3), V(1.8, 4.1, 0.5), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(0.3, 0.3, 0.3), V(1.8, 4.1, -0.5), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(1.6, 0.4, 1.4), V(-0.4, 2.8, 1.3), b, { role = "accent", rot = V(20, 0, 0) }),
		part(V(1.6, 0.4, 1.4), V(-0.4, 2.8, -1.3), b, { role = "accent", rot = V(-20, 0, 0) }),
		part(V(1.4, 0.4, 1), V(-1.6, 2.4, 0), b, { role = "accent" }),
	}
end

BUILDERS.duck = function()
	local y = C(245, 215, 70)
	return {
		part(V(3.4, 2.4, 2.2), V(0, 2.4, 0), y, { shape = "ball" }),
		part(V(1.6, 1.8, 1.6), V(1.6, 3.8, 0), y, { role = "accent", shape = "ball" }),
		part(V(1, 0.5, 0.9), V(2.6, 3.6, 0), C(235, 140, 40), { role = "accent" }),
		part(V(0.3, 0.3, 0.3), V(2, 4.2, 0.5), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(0.3, 0.3, 0.3), V(2, 4.2, -0.5), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(1.4, 1, 0.4), V(-1.8, 2.6, 0), y, { role = "accent", rot = V(0, 0, 30) }),
	}
end

BUILDERS.penguin = function()
	local blk = C(35, 35, 40)
	local wht = C(245, 245, 245)
	return {
		part(V(3, 4.4, 2.6), V(0, 3, 0), blk, { shape = "ball" }),
		part(V(2.2, 3.6, 1.6), V(0.9, 2.8, 0), wht, { role = "accent", shape = "ball" }),
		part(V(2, 2, 2), V(0, 5.6, 0), blk, { shape = "ball" }),
		part(V(0.9, 0.5, 0.8), V(1.2, 5.4, 0), C(240, 150, 40), { role = "accent" }),
		part(V(0.3, 0.3, 0.3), V(0.9, 6, 0.5), wht, { role = "accent", shape = "ball" }),
		part(V(0.3, 0.3, 0.3), V(0.9, 6, -0.5), wht, { role = "accent", shape = "ball" }),
		part(V(0.6, 2.4, 0.4), V(-1.4, 3, 1.1), blk, { role = "accent", rot = V(0, 0, 10) }),
		part(V(0.6, 2.4, 0.4), V(-1.4, 3, -1.1), blk, { role = "accent", rot = V(0, 0, 10) }),
		part(V(1, 0.4, 0.8), V(0.6, 0.7, 0.7), C(240, 150, 40), { role = "accent" }),
		part(V(1, 0.4, 0.8), V(0.6, 0.7, -0.7), C(240, 150, 40), { role = "accent" }),
	}
end

BUILDERS.bee = function()
	local y = C(245, 205, 40)
	local blk = C(30, 30, 30)
	return {
		part(V(4, 2.4, 2.4), V(0, 3, 0), y, { shape = "ball" }),
		part(V(0.8, 2.5, 2.5), V(0.6, 3, 0), blk, { role = "accent", shape = "cylinder", rot = V(0, 0, 90) }),
		part(V(0.8, 2.5, 2.5), V(-0.8, 3, 0), blk, { role = "accent", shape = "cylinder", rot = V(0, 0, 90) }),
		part(V(0.3, 0.3, 0.3), V(2.2, 3.4, 0.4), blk, { role = "accent", shape = "ball" }),
		part(V(0.3, 0.3, 0.3), V(2.2, 3.4, -0.4), blk, { role = "accent", shape = "ball" }),
		part(V(2, 0.3, 1.4), V(-0.4, 4.4, 0.9), C(230, 240, 255), { role = "accent", shape = "ball", mat = Enum.Material.Glass }),
		part(V(2, 0.3, 1.4), V(-0.4, 4.4, -0.9), C(230, 240, 255), { role = "accent", shape = "ball", mat = Enum.Material.Glass }),
	}
end

BUILDERS.butterfly = function()
	local body = C(60, 50, 70)
	local w = C(235, 110, 170)
	return {
		part(V(0.7, 0.7, 4), V(0, 3, 0), body, { shape = "cylinder", rot = V(90, 0, 0) }),
		part(V(2.6, 0.3, 2.4), V(0, 3.4, 1.6), w, { role = "primary", shape = "ball" }),
		part(V(2.6, 0.3, 2.4), V(0, 3.4, -1.6), w, { role = "primary", shape = "ball" }),
		part(V(2, 0.3, 2), V(0, 2.4, 2.2), w, { role = "primary", shape = "ball" }),
		part(V(2, 0.3, 2), V(0, 2.4, -2.2), w, { role = "primary", shape = "ball" }),
		part(V(0.3, 1, 0.3), V(0.3, 3.9, 0.4), body, { role = "accent", rot = V(20, 0, 20) }),
		part(V(0.3, 1, 0.3), V(0.3, 3.9, -0.4), body, { role = "accent", rot = V(-20, 0, 20) }),
	}
end

BUILDERS.frog = function()
	local g = C(90, 175, 80)
	return {
		part(V(3.4, 2, 3), V(0, 1.8, 0), g, { shape = "ball" }),
		part(V(1, 1, 1), V(1, 3, 1), g, { role = "accent", shape = "ball" }),
		part(V(1, 1, 1), V(1, 3, -1), g, { role = "accent", shape = "ball" }),
		part(V(0.5, 0.5, 0.5), V(1.3, 3.2, 1), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(0.5, 0.5, 0.5), V(1.3, 3.2, -1), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(1.4, 0.7, 0.8), V(-1.4, 1, 1.4), g, { role = "accent", rot = V(0, 25, 0) }),
		part(V(1.4, 0.7, 0.8), V(-1.4, 1, -1.4), g, { role = "accent", rot = V(0, -25, 0) }),
	}
end

BUILDERS.pig = function()
	local p = C(235, 160, 180)
	local specs = {
		part(V(5, 3, 3), V(0, 3, 0), p, { shape = "ball" }),
		part(V(2.4, 2.4, 2.4), V(3, 3, 0), p, { shape = "ball" }),
		part(V(0.9, 0.9, 0.7), V(4.2, 2.8, 0), C(225, 140, 160), { role = "accent", shape = "cylinder" }),
		part(V(0.7, 0.9, 0.4), V(2.8, 4.4, 0.7), p, { role = "accent" }),
		part(V(0.7, 0.9, 0.4), V(2.8, 4.4, -0.7), p, { role = "accent" }),
		part(V(0.4, 0.4, 0.4), V(-2.6, 3.4, 0), C(225, 140, 160), { role = "accent", shape = "ball" }),
	}
	legs4(specs, V(0.8, 1.8, 0.8), 1.8, 1, 1.2, C(225, 140, 160), { role = "accent" })
	return specs
end

BUILDERS.cow = function()
	local w = C(245, 245, 245)
	local blk = C(40, 40, 40)
	local specs = {
		part(V(6, 3, 3), V(0, 3.4, 0), w),
		part(V(2.2, 2.2, 2.2), V(3.6, 3.4, 0), w),
		part(V(1, 0.9, 1.4), V(4.6, 3, 0), C(235, 170, 190), { role = "accent" }),
		part(V(0.5, 0.9, 0.5), V(3.8, 4.8, 0.7), C(230, 220, 200), { role = "accent" }),
		part(V(0.5, 0.9, 0.5), V(3.8, 4.8, -0.7), C(230, 220, 200), { role = "accent" }),
		part(V(1.4, 1, 1.6), V(0.6, 3.7, 1.2), blk, { role = "accent", shape = "ball" }),
		part(V(1.2, 1, 1.4), V(-1.4, 3.5, -1.2), blk, { role = "accent", shape = "ball" }),
		part(V(0.8, 0.8, 1.2), V(-3, 2.4, 0), C(235, 170, 190), { role = "accent" }),
	}
	legs4(specs, V(0.9, 2.2, 0.9), 2.2, 1.1, 1.2, w, { role = "accent" })
	return specs
end

BUILDERS.sheep = function()
	local wool = C(238, 238, 238)
	local f = C(60, 55, 60)
	local specs = {
		part(V(5, 4, 4), V(0, 3.6, 0), wool, { shape = "ball" }),
		part(V(2, 2, 1.8), V(3, 3.4, 0), f),
		part(V(0.6, 1, 0.4), V(2.8, 4.5, 0.7), f, { role = "accent" }),
		part(V(0.6, 1, 0.4), V(2.8, 4.5, -0.7), f, { role = "accent" }),
	}
	legs4(specs, V(0.7, 2, 0.7), 1.6, 1, 1, f, { role = "accent" })
	return specs
end

BUILDERS.chicken = function()
	local w = C(245, 245, 245)
	local specs = {
		part(V(2.8, 3, 2.4), V(0, 3, 0), w, { shape = "ball" }),
		part(V(1.6, 1.6, 1.6), V(0.6, 4.8, 0), w, { shape = "ball" }),
		part(V(0.7, 0.6, 0.5), V(1.4, 4.8, 0), C(240, 170, 40), { role = "accent" }),
		part(V(0.6, 0.8, 0.5), V(0.6, 5.7, 0), C(220, 60, 50), { role = "accent" }),
		part(V(0.4, 0.5, 0.6), V(0.7, 4.3, 0), C(220, 60, 50), { role = "accent" }),
		part(V(0.3, 0.3, 0.3), V(1.1, 5, 0.5), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(0.3, 0.3, 0.3), V(1.1, 5, -0.5), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(1.6, 1.6, 0.3), V(-1.3, 3.4, 0), w, { role = "accent" }),
		part(V(0.4, 1, 0.4), V(0.4, 1, 0.6), C(240, 170, 40), { role = "accent" }),
		part(V(0.4, 1, 0.4), V(0.4, 1, -0.6), C(240, 170, 40), { role = "accent" }),
	}
	return specs
end

BUILDERS.rabbit = function()
	local w = C(238, 235, 235)
	return {
		part(V(2.8, 3, 2.4), V(0, 2.6, 0), w, { shape = "ball" }),
		part(V(1.8, 1.8, 1.8), V(1, 4.2, 0), w, { shape = "ball" }),
		part(V(0.6, 2.4, 0.4), V(0.7, 6, 0.5), w, { role = "accent", rot = V(0, 0, -8) }),
		part(V(0.6, 2.4, 0.4), V(0.7, 6, -0.5), w, { role = "accent", rot = V(0, 0, 8) }),
		part(V(0.35, 0.35, 0.35), V(1.7, 4.4, 0.5), C(220, 120, 140), { role = "accent", shape = "ball" }),
		part(V(0.35, 0.35, 0.35), V(1.7, 4.4, -0.5), C(220, 120, 140), { role = "accent", shape = "ball" }),
		part(V(0.8, 0.8, 0.8), V(-1.6, 2.4, 0), w, { role = "accent", shape = "ball" }),
		part(V(0.7, 1, 1.6), V(0.4, 0.6, 0), w, { role = "accent" }),
	}
end

BUILDERS.turtle = function()
	local sh = C(80, 140, 70)
	local sk = C(150, 190, 120)
	local specs = {
		part(V(5, 2.6, 4.5), V(0, 2.2, 0), sh, { shape = "ball" }),
		part(V(5.4, 0.8, 5), V(0, 1.2, 0), C(180, 150, 90), { role = "accent" }),
		part(V(1.8, 1.6, 1.6), V(3, 1.6, 0), sk, { role = "accent", shape = "ball" }),
		part(V(0.3, 0.3, 0.3), V(3.7, 1.9, 0.5), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(0.3, 0.3, 0.3), V(3.7, 1.9, -0.5), C(20, 20, 20), { role = "accent", shape = "ball" }),
	}
	legs4(specs, V(1.2, 0.8, 0.9), 1.8, 2, 0.9, sk, { role = "accent" })
	return specs
end

BUILDERS.dragon = function()
	local g = C(80, 150, 90)
	local belly = C(210, 200, 120)
	local specs = {
		part(V(6, 3, 3), V(0, 3.4, 0), g),
		part(V(2.6, 2.6, 2.4), V(4, 4.2, 0), g),
		part(V(1.4, 1, 1.2), V(5.4, 3.8, 0), g, { role = "accent" }),
		part(V(0.4, 0.4, 0.4), V(4.6, 5, 0.7), C(240, 60, 40), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(0.4, 0.4, 0.4), V(4.6, 5, -0.7), C(240, 60, 40), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(0.6, 1, 0.3), V(3.4, 5.6, 0.5), C(220, 200, 120), { role = "accent", rot = V(0, 0, -20) }),
		part(V(0.6, 1, 0.3), V(3.4, 5.6, -0.5), C(220, 200, 120), { role = "accent", rot = V(0, 0, -20) }),
		part(V(3, 0.4, 3.4), V(-0.5, 5, 1.6), g, { role = "accent", rot = V(30, 0, 0) }),
		part(V(3, 0.4, 3.4), V(-0.5, 5, -1.6), g, { role = "accent", rot = V(-30, 0, 0) }),
		part(V(3, 1.4, 1.4), V(-4, 3, 0), g, { role = "accent", shape = "cylinder", rot = V(0, 20, 0) }),
		part(V(2, 0.8, 0.8), V(-5.6, 2.6, 0.7), g, { role = "accent", shape = "cylinder", rot = V(0, 50, 0) }),
	}
	legs4(specs, V(0.9, 2, 0.9), 2, 1.2, 1.4, g, { role = "accent" })
	return specs
end

BUILDERS.shark = function()
	local b = C(110, 130, 150)
	local belly = C(225, 225, 225)
	return {
		part(V(7, 3, 3), V(0, 3, 0), b, { shape = "ball" }),
		part(V(3, 1.4, 2.6), V(3.4, 2.6, 0), b, { role = "primary", shape = "ball" }),
		part(V(4, 2, 2.4), V(0, 2.2, 0), belly, { role = "accent", shape = "ball" }),
		part(V(2, 2.4, 0.4), V(-3.4, 4, 0), b, { role = "accent", rot = V(0, 0, -20) }),
		part(V(1.6, 1, 0.4), V(-3.6, 3.4, 0), b, { role = "accent" }),
		part(V(1.8, 2, 0.3), V(0, 4.6, 0), b, { role = "accent" }),
		part(V(0.3, 0.3, 0.3), V(2.6, 3.4, 1), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(0.3, 0.3, 0.3), V(2.6, 3.4, -1), C(20, 20, 20), { role = "accent", shape = "ball" }),
	}
end

BUILDERS.whale = function()
	local b = C(70, 110, 170)
	return {
		part(V(9, 4.5, 4.5), V(0, 4, 0), b, { shape = "ball" }),
		part(V(3.6, 2.6, 2.6), V(0, 2.8, 0), C(220, 225, 230), { role = "accent", shape = "ball" }),
		part(V(2, 2.6, 0.5), V(-4.4, 5, 0), b, { role = "accent", rot = V(0, 0, 35) }),
		part(V(2, 2.6, 0.5), V(-4.4, 5, 0), b, { role = "accent", rot = V(0, 0, -35) }),
		part(V(0.4, 0.4, 0.4), V(3.6, 4.6, 1.6), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(0.4, 0.4, 0.4), V(3.6, 4.6, -1.6), C(20, 20, 20), { role = "accent", shape = "ball" }),
		cylY(0.8, 2, V(1, 7, 0), C(170, 210, 240), { role = "accent", mat = Enum.Material.Glass }),
	}
end

BUILDERS.spider = function()
	local blk = C(40, 35, 45)
	local specs = {
		part(V(3, 2.4, 2.8), V(0, 2.2, 0), blk, { shape = "ball" }),
		part(V(2, 1.8, 2), V(2, 2.2, 0), blk, { role = "primary", shape = "ball" }),
		part(V(0.4, 0.4, 0.4), V(2.8, 2.7, 0.5), C(220, 40, 40), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(0.4, 0.4, 0.4), V(2.8, 2.7, -0.5), C(220, 40, 40), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
	}
	for i = 0, 3 do
		local z = 1.2 + i * 0.1
		local x = -1 + i * 0.7
		table.insert(specs, part(V(0.3, 0.3, 3.2), V(x, 2, z), blk, { role = "accent", rot = V(50, 0, 0) }))
		table.insert(specs, part(V(0.3, 0.3, 3.2), V(x, 2, -z), blk, { role = "accent", rot = V(-50, 0, 0) }))
	end
	return specs
end

BUILDERS.snake = function()
	local g = C(90, 170, 80)
	local specs = {}
	for i = 0, 6 do
		local x = -5 + i * 1.5
		local z = math.sin(i * 0.9) * 1.6
		table.insert(specs, part(V(1.8 - i * 0.05, 1.5, 1.5), V(x, 1.4, z), g, { role = (i == 6) and "primary" or "accent", shape = "ball" }))
	end
	table.insert(specs, part(V(0.3, 0.3, 0.3), V(4.6, 1.7, math.sin(6 * 0.9) * 1.6 + 0.4), C(20, 20, 20), { role = "accent", shape = "ball" }))
	table.insert(specs, part(V(0.3, 0.3, 0.3), V(4.6, 1.7, math.sin(6 * 0.9) * 1.6 - 0.4), C(20, 20, 20), { role = "accent", shape = "ball" }))
	table.insert(specs, part(V(0.8, 0.1, 0.3), V(5.2, 1.3, math.sin(6 * 0.9) * 1.6), C(220, 60, 60), { role = "accent" }))
	return specs
end

--===========================================================================
-- BUILDINGS & STRUCTURES
--===========================================================================
BUILDERS.windmill = function()
	local body = C(225, 220, 205)
	local blade = C(150, 100, 60)
	local specs = {
		cylY(5, 12, V(0, 6, 0), body, { mat = Enum.Material.Concrete }),
		cylY(6.5, 2, V(0, 12.4, 0), C(140, 60, 50), { role = "accent", mat = Enum.Material.Brick }),
		part(V(1, 1, 1), V(0, 9, 2.6), C(80, 80, 85), { role = "accent", shape = "cylinder", rot = V(90, 0, 0), mat = Enum.Material.Metal }),
	}
	ring(specs, 4, 2.6, function(_, _, deg)
		return part(V(1, 5, 0.3), V(0, 9 + math.cos(math.rad(deg)) * 2.6, 2.8), blade, { role = "accent", rot = V(0, 0, -deg) })
	end)
	return specs
end

BUILDERS.lighthouse = function()
	local specs = {}
	for i = 0, 4 do
		local col = (i % 2 == 0) and C(230, 230, 230) or C(210, 60, 50)
		table.insert(specs, cylY(5 - i * 0.5, 3, V(0, 1.6 + i * 3, 0), col, { role = "accent", mat = Enum.Material.Concrete }))
	end
	table.insert(specs, cylY(3.6, 2.2, V(0, 17.5, 0), C(255, 240, 150), { mat = Enum.Material.Neon }))
	table.insert(specs, cylY(4, 1.4, V(0, 19.2, 0), C(60, 60, 65), { role = "accent", mat = Enum.Material.Metal }))
	return specs
end

BUILDERS.barn = function()
	local red = C(170, 50, 45)
	local wht = C(235, 235, 235)
	return {
		part(V(10, 6, 8), V(0, 3, 0), red, { mat = Enum.Material.WoodPlanks }),
		part(V(11, 1, 8.4), V(0, 6.4, 0), C(110, 35, 32), { role = "accent", mat = Enum.Material.WoodPlanks }),
		part(V(0.4, 6.5, 8), V(-3.6, 9, 0), C(110, 35, 32), { role = "accent", rot = V(0, 0, -55) }),
		part(V(0.4, 6.5, 8), V(3.6, 9, 0), C(110, 35, 32), { role = "accent", rot = V(0, 0, 55) }),
		part(V(3.6, 4.4, 0.4), V(0, 2.2, 4.05), C(120, 35, 32), { role = "accent", mat = Enum.Material.Wood }),
		part(V(3.8, 0.4, 0.5), V(0, 3, 4.1), wht, { role = "accent" }),
		part(V(0.4, 4.4, 0.5), V(0, 2.2, 4.1), wht, { role = "accent" }),
	}
end

BUILDERS.tent = function()
	local fab = C(70, 150, 110)
	return {
		part(V(0.4, 8, 8), V(0, 3.5, 0), fab, { rot = V(0, 0, -58), mat = Enum.Material.Fabric }),
		part(V(0.4, 8, 8), V(0, 3.5, 0), fab, { rot = V(0, 0, 58), mat = Enum.Material.Fabric }),
		part(V(0.5, 8, 0.5), V(0, 3.6, -3.9), C(120, 90, 60), { role = "accent", mat = Enum.Material.Wood }),
		part(V(2, 4, 0.2), V(0, 2, 3.9), C(50, 110, 80), { role = "accent", mat = Enum.Material.Fabric }),
	}
end

BUILDERS.igloo = function()
	local s = C(225, 235, 245)
	local specs = {
		part(V(9, 5, 9), V(0, 1, 0), s, { shape = "ball", mat = Enum.Material.SmoothPlastic }),
		part(V(3, 3, 4), V(4, 1, 0), s, { role = "accent", shape = "ball", mat = Enum.Material.SmoothPlastic }),
		part(V(1.6, 1.8, 1.6), V(5.4, 0.9, 0), C(20, 30, 50), { role = "accent" }),
	}
	return specs
end

BUILDERS.bridge = function()
	local wood = C(140, 95, 55)
	local specs = {
		part(V(14, 0.8, 5), V(0, 3, 0), wood, { mat = Enum.Material.WoodPlanks }),
		part(V(0.5, 4, 0.5), V(-6.5, 2.4, 2.4), wood, { role = "accent" }),
		part(V(0.5, 4, 0.5), V(6.5, 2.4, 2.4), wood, { role = "accent" }),
		part(V(0.5, 4, 0.5), V(-6.5, 2.4, -2.4), wood, { role = "accent" }),
		part(V(0.5, 4, 0.5), V(6.5, 2.4, -2.4), wood, { role = "accent" }),
		part(V(13, 0.4, 0.4), V(0, 4.4, 2.4), wood, { role = "accent" }),
		part(V(13, 0.4, 0.4), V(0, 4.4, -2.4), wood, { role = "accent" }),
		part(V(0.6, 5, 5.2), V(0, 1, 0), C(120, 120, 125), { role = "accent", shape = "cylinder", mat = Enum.Material.Slate }),
	}
	return specs
end

BUILDERS.wall = function()
	local s = C(150, 150, 155)
	local specs = {
		part(V(12, 6, 2), V(0, 3, 0), s, { mat = Enum.Material.Cobblestone }),
	}
	for i = 0, 5 do
		table.insert(specs, part(V(1.4, 1.4, 2), V(-5 + i * 2, 6.7, 0), s, { role = "accent", mat = Enum.Material.Cobblestone }))
	end
	return specs
end

BUILDERS.well = function()
	local s = C(150, 150, 155)
	local wood = C(130, 90, 55)
	return {
		cylY(5, 3, V(0, 1.5, 0), s, { mat = Enum.Material.Cobblestone }),
		cylY(4, 0.6, V(0, 3.4, 0), s, { role = "accent", mat = Enum.Material.Slate }),
		part(V(0.6, 5, 0.6), V(-1.8, 5.5, 0), wood, { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.6, 5, 0.6), V(1.8, 5.5, 0), wood, { role = "accent", mat = Enum.Material.Wood }),
		part(V(5, 0.6, 4), V(0, 8.2, 0), C(110, 35, 32), { role = "accent", rot = V(0, 0, 0), mat = Enum.Material.WoodPlanks }),
		part(V(0.4, 1.2, 1.2), V(0, 6.4, 0), wood, { role = "accent" }),
		part(V(2.4, 0.6, 0.6), V(0, 4, 0), C(80, 80, 85), { role = "accent", shape = "cylinder", mat = Enum.Material.Metal }),
	}
end

BUILDERS.mailbox = function()
	local m = C(60, 90, 170)
	return {
		part(V(0.5, 5, 0.5), V(0, 2.5, 0), C(120, 90, 55), { role = "accent", mat = Enum.Material.Wood }),
		part(V(2.4, 1.8, 3.4), V(0, 5.6, 0), m, { mat = Enum.Material.Metal }),
		cylY(2.4, 0.1, V(0, 6.5, 0), m, { shape = "cylinder", mat = Enum.Material.Metal }),
		part(V(0.2, 1.2, 0.2), V(1.3, 6.4, 0), C(220, 50, 50), { role = "accent" }),
		part(V(0.2, 0.5, 0.8), V(1.3, 7, 0), C(220, 50, 50), { role = "accent" }),
	}
end

BUILDERS.birdhouse = function()
	local wood = C(160, 110, 70)
	return {
		part(V(0.4, 6, 0.4), V(0, 3, 0), C(120, 90, 55), { role = "accent", mat = Enum.Material.Wood }),
		part(V(3, 3, 3), V(0, 7.5, 0), wood, { mat = Enum.Material.WoodPlanks }),
		part(V(0.4, 2.6, 3.4), V(0, 9.4, 0), C(110, 70, 45), { role = "accent", rot = V(0, 0, -50) }),
		part(V(0.4, 2.6, 3.4), V(0, 9.4, 0), C(110, 70, 45), { role = "accent", rot = V(0, 0, 50) }),
		cylZ(1, 0.4, V(0, 7.5, 1.5), C(40, 30, 25), { role = "accent" }),
		cylZ(0.4, 0.6, V(0, 6.8, 1.6), C(120, 90, 55), { role = "accent" }),
	}
end

BUILDERS.gazebo = function()
	local wood = C(235, 235, 230)
	local specs = {
		cylY(8, 0.6, V(0, 0.3, 0), C(150, 110, 70), { role = "accent", mat = Enum.Material.WoodPlanks }),
	}
	ring(specs, 6, 3.4, function(x, z)
		return part(V(0.5, 6, 0.5), V(x, 3.5, z), wood, { role = "accent", mat = Enum.Material.Wood })
	end)
	table.insert(specs, cylY(9, 2.5, V(0, 8, 0), C(150, 60, 55), { mat = Enum.Material.WoodPlanks }))
	return specs
end

BUILDERS.fountain = function()
	local s = C(190, 190, 195)
	local water = C(90, 170, 230)
	return {
		cylY(10, 1.5, V(0, 0.75, 0), s, { mat = Enum.Material.Marble }),
		cylY(9, 0.6, V(0, 1.6, 0), water, { role = "accent", mat = Enum.Material.Glass }),
		cylY(2, 3, V(0, 2.5, 0), s, { mat = Enum.Material.Marble }),
		cylY(5, 1, V(0, 4, 0), s, { mat = Enum.Material.Marble }),
		cylY(4.5, 0.5, V(0, 4.7, 0), water, { role = "accent", mat = Enum.Material.Glass }),
		cylY(1.4, 2.4, V(0, 5.5, 0), s, { mat = Enum.Material.Marble }),
		part(V(1, 1.4, 1), V(0, 7, 0), water, { role = "accent", shape = "ball", mat = Enum.Material.Glass }),
	}
end

BUILDERS.staircase = function()
	local s = C(180, 175, 170)
	local specs = {}
	for i = 0, 5 do
		table.insert(specs, part(V(4, 1, 1.6 * (6 - i)), V(0, 0.5 + i, -0.8 * i), s, { mat = Enum.Material.Concrete }))
	end
	return specs
end

BUILDERS.ladder = function()
	local w = C(160, 115, 70)
	local specs = {
		part(V(0.4, 8, 0.4), V(-1.3, 4, 0), w, { mat = Enum.Material.Wood }),
		part(V(0.4, 8, 0.4), V(1.3, 4, 0), w, { mat = Enum.Material.Wood }),
	}
	for i = 0, 4 do
		table.insert(specs, part(V(2.8, 0.4, 0.4), V(0, 1 + i * 1.6, 0), w, { role = "accent", mat = Enum.Material.Wood }))
	end
	return specs
end

BUILDERS.skyscraper = function()
	local glass = C(110, 150, 180)
	local specs = {
		part(V(8, 24, 8), V(0, 12, 0), glass, { mat = Enum.Material.Glass }),
		part(V(8.4, 1, 8.4), V(0, 0.5, 0), C(80, 80, 85), { role = "accent", mat = Enum.Material.Concrete }),
		part(V(5, 4, 5), V(0, 26, 0), C(120, 120, 125), { role = "accent", mat = Enum.Material.Concrete }),
		part(V(0.6, 4, 0.6), V(0, 30, 0), C(200, 50, 50), { role = "accent", mat = Enum.Material.Metal }),
	}
	for i = 1, 7 do
		table.insert(specs, part(V(8.2, 0.4, 8.2), V(0, i * 3, 0), C(60, 70, 80), { role = "accent" }))
	end
	return specs
end

BUILDERS.temple = function()
	local s = C(225, 215, 190)
	local specs = {
		part(V(12, 1.5, 8), V(0, 0.75, 0), s, { mat = Enum.Material.Marble }),
		part(V(13, 2, 9), V(0, 9, 0), s, { role = "accent", mat = Enum.Material.Marble }),
		part(V(0.4, 4, 9), V(-5, 11.5, 0), C(210, 60, 55), { role = "accent", rot = V(0, 0, -55) }),
		part(V(0.4, 4, 9), V(5, 11.5, 0), C(210, 60, 55), { role = "accent", rot = V(0, 0, 55) }),
	}
	for _, x in ipairs({ -4.5, -2.2, 0, 2.2, 4.5 }) do
		table.insert(specs, cylY(1.4, 6.5, V(x, 4.75, 3), s, { role = "accent", mat = Enum.Material.Marble }))
		table.insert(specs, cylY(1.4, 6.5, V(x, 4.75, -3), s, { role = "accent", mat = Enum.Material.Marble }))
	end
	return specs
end

--===========================================================================
-- VEHICLES
--===========================================================================
BUILDERS.airplane = function()
	local body = C(225, 225, 230)
	local accent = C(60, 110, 200)
	return {
		part(V(12, 2.4, 2.4), V(0, 3, 0), body, { shape = "cylinder", mat = Enum.Material.Metal }),
		part(V(2.4, 2, 2.2), V(5.6, 3, 0), C(120, 180, 220), { role = "accent", shape = "ball", mat = Enum.Material.Glass }),
		part(V(4, 0.5, 14), V(-0.5, 3, 0), body, { role = "primary", mat = Enum.Material.Metal }),
		part(V(2.4, 0.4, 5), V(-5, 3.4, 0), body, { role = "accent" }),
		part(V(1.4, 2.6, 0.4), V(-5.6, 4, 0), accent, { role = "accent" }),
		cylZ(2.6, 0.4, V(6, 3, 0), C(60, 60, 65), { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.4, 4, 0.6), V(6.2, 3, 0), C(80, 80, 85), { role = "accent" }),
		part(V(0.4, 0.6, 4), V(6.2, 3, 0), C(80, 80, 85), { role = "accent" }),
	}
end

BUILDERS.helicopter = function()
	local body = C(60, 130, 90)
	return {
		part(V(5, 3, 3), V(0, 3, 0), body, { shape = "ball" }),
		part(V(2.6, 2, 2.2), V(2.4, 3, 0), C(150, 200, 230), { role = "accent", shape = "ball", mat = Enum.Material.Glass }),
		part(V(6, 1, 1), V(-4, 3.6, 0), body, { role = "accent", shape = "cylinder" }),
		part(V(0.6, 2, 1.4), V(-6.6, 4, 0), body, { role = "accent" }),
		cylY(0.6, 1.6, V(0, 5, 0), C(60, 60, 65), { role = "accent", mat = Enum.Material.Metal }),
		part(V(11, 0.3, 0.8), V(0, 5.8, 0), C(40, 40, 45), { role = "accent" }),
		part(V(0.8, 0.3, 11), V(0, 5.8, 0), C(40, 40, 45), { role = "accent" }),
		part(V(0.3, 3, 0.8), V(-6.6, 4, 0.6), C(40, 40, 45), { role = "accent", rot = V(0, 0, 0) }),
		part(V(4, 0.4, 0.4), V(-1, 1.4, 1.4), C(60, 60, 65), { role = "accent" }),
		part(V(4, 0.4, 0.4), V(-1, 1.4, -1.4), C(60, 60, 65), { role = "accent" }),
	}
end

BUILDERS.train = function()
	local body = C(60, 70, 90)
	local red = C(170, 50, 45)
	local specs = {
		part(V(10, 3, 4), V(0, 3, 0), body, { mat = Enum.Material.Metal }),
		part(V(3.5, 3, 4), V(-3, 6, 0), body, { role = "primary", mat = Enum.Material.Metal }),
		cylY(2, 2.5, V(3.5, 5.2, 0), C(40, 40, 45), { role = "accent", mat = Enum.Material.Metal }),
		cylY(2.6, 0.6, V(3.5, 6.6, 0), C(40, 40, 45), { role = "accent" }),
		part(V(5, 0.6, 4.2), V(0, 0.8, 0), red, { role = "accent" }),
		cylZ(1, 0.5, V(4.6, 2.4, 1.7), C(255, 240, 150), { role = "accent", mat = Enum.Material.Neon }),
	}
	for _, x in ipairs({ -3, 0, 3 }) do
		table.insert(specs, cylZ(2, 0.6, V(x, 1.2, 2.1), C(30, 30, 30), { role = "accent" }))
		table.insert(specs, cylZ(2, 0.6, V(x, 1.2, -2.1), C(30, 30, 30), { role = "accent" }))
	end
	return specs
end

BUILDERS.tank = function()
	local g = C(90, 100, 70)
	local specs = {
		part(V(9, 2, 5), V(0, 2.4, 0), g, { mat = Enum.Material.Metal }),
		part(V(5, 2, 4), V(0, 4.4, 0), g, { mat = Enum.Material.Metal }),
		part(V(7, 1.2, 1.2), V(4, 4.6, 0), C(70, 80, 55), { role = "accent", shape = "cylinder", mat = Enum.Material.Metal }),
		part(V(9.6, 2.4, 1.6), V(0, 1.6, 2.4), C(45, 45, 45), { role = "accent" }),
		part(V(9.6, 2.4, 1.6), V(0, 1.6, -2.4), C(45, 45, 45), { role = "accent" }),
	}
	return specs
end

BUILDERS.submarine = function()
	local y = C(225, 195, 50)
	return {
		part(V(11, 3.2, 3.2), V(0, 3, 0), y, { shape = "cylinder", mat = Enum.Material.Metal }),
		part(V(2.4, 2.4, 2.4), V(0, 5, 0), y, { role = "accent" }),
		part(V(0.4, 2.4, 0.4), V(0, 7, 0), C(60, 60, 65), { role = "accent" }),
		cylZ(1.2, 0.3, V(2.8, 3, 1.7), C(40, 40, 45), { role = "accent" }),
		cylZ(1.2, 0.3, V(0, 3, 1.7), C(40, 40, 45), { role = "accent" }),
		cylZ(1.2, 0.3, V(-2.8, 3, 1.7), C(40, 40, 45), { role = "accent" }),
		part(V(2, 2.4, 0.5), V(-5.4, 3.6, 0), y, { role = "accent", rot = V(0, 0, 30) }),
	}
end

BUILDERS.bicycle = function()
	local m = C(40, 120, 180)
	return {
		cylZ(3.5, 0.4, V(-2.4, 1.8, 0), C(30, 30, 30), { role = "accent" }),
		cylZ(3.5, 0.4, V(2.4, 1.8, 0), C(30, 30, 30), { role = "accent" }),
		part(V(3, 0.3, 0.3), V(0, 2.4, 0), m, { mat = Enum.Material.Metal }),
		part(V(3, 0.3, 0.3), V(-1.2, 1.9, 0), m, { rot = V(0, 0, 35), mat = Enum.Material.Metal }),
		part(V(3, 0.3, 0.3), V(1.2, 2, 0), m, { rot = V(0, 0, -55), mat = Enum.Material.Metal }),
		part(V(0.3, 1.6, 0.3), V(2.4, 3, 0), m, { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.3, 0.3, 1.8), V(2.4, 3.7, 0), C(30, 30, 30), { role = "accent" }),
		part(V(1.4, 0.4, 0.8), V(-1.6, 3.2, 0), C(30, 30, 30), { role = "accent" }),
	}
end

BUILDERS.motorcycle = function()
	local m = C(30, 30, 35)
	local red = C(200, 50, 45)
	return {
		cylZ(3.2, 0.8, V(-2.6, 1.6, 0), m, { role = "accent" }),
		cylZ(3.2, 0.8, V(2.6, 1.6, 0), m, { role = "accent" }),
		part(V(4, 1.6, 1.6), V(0, 2.6, 0), red, { mat = Enum.Material.Metal }),
		part(V(2, 0.8, 1.4), V(-1.4, 3.4, 0), m, { role = "accent" }),
		part(V(0.3, 1.4, 0.3), V(2.4, 3.2, 0), m, { role = "accent", rot = V(0, 0, -30) }),
		part(V(0.3, 0.3, 1.6), V(2.7, 3.6, 0), m, { role = "accent" }),
		cylZ(1.2, 0.4, V(3, 2.8, 0), C(255, 240, 150), { role = "accent", mat = Enum.Material.Neon }),
	}
end

BUILDERS.bus = function()
	local y = C(235, 190, 40)
	local specs = {
		part(V(14, 5, 5), V(0, 3.5, 0), y, { mat = Enum.Material.Metal }),
		part(V(13, 1.6, 5.1), V(0.4, 4.6, 0), C(150, 200, 230), { role = "accent", mat = Enum.Material.Glass }),
		part(V(0.3, 3, 5.1), V(7, 3, 0), C(150, 200, 230), { role = "accent", mat = Enum.Material.Glass }),
	}
	for _, x in ipairs({ 5, -5 }) do
		table.insert(specs, cylZ(2.4, 0.6, V(x, 1, 2.6), C(30, 30, 30), { role = "accent" }))
		table.insert(specs, cylZ(2.4, 0.6, V(x, 1, -2.6), C(30, 30, 30), { role = "accent" }))
	end
	return specs
end

BUILDERS.ufo = function()
	local m = C(150, 160, 175)
	local glow = C(120, 240, 160)
	local specs = {
		cylY(10, 1.4, V(0, 3, 0), m, { mat = Enum.Material.Metal }),
		part(V(5, 3, 5), V(0, 4.4, 0), C(150, 230, 240), { role = "accent", shape = "ball", mat = Enum.Material.Glass }),
		cylY(11.5, 0.5, V(0, 2.6, 0), C(80, 80, 90), { role = "accent", mat = Enum.Material.Metal }),
	}
	ring(specs, 8, 4.4, function(x, z)
		return part(V(0.7, 0.7, 0.7), V(x, 2.4, z), glow, { role = "accent", shape = "ball", mat = Enum.Material.Neon })
	end)
	return specs
end

BUILDERS.balloon = function()
	local b = C(220, 60, 60)
	local stripe = C(235, 235, 235)
	return {
		part(V(8, 9, 8), V(0, 11, 0), b, { shape = "ball" }),
		part(V(8.2, 9, 2.5), V(0, 11, 0), stripe, { role = "accent", shape = "ball" }),
		part(V(2.5, 9, 8.2), V(0, 11, 0), stripe, { role = "accent", shape = "ball" }),
		part(V(3, 2.5, 3), V(0, 4, 0), C(150, 110, 70), { role = "accent", mat = Enum.Material.WoodPlanks }),
		part(V(0.2, 4, 0.2), V(1.3, 7, 1.3), C(80, 70, 60), { role = "accent" }),
		part(V(0.2, 4, 0.2), V(-1.3, 7, 1.3), C(80, 70, 60), { role = "accent" }),
		part(V(0.2, 4, 0.2), V(1.3, 7, -1.3), C(80, 70, 60), { role = "accent" }),
		part(V(0.2, 4, 0.2), V(-1.3, 7, -1.3), C(80, 70, 60), { role = "accent" }),
	}
end

BUILDERS.wagon = function()
	local red = C(190, 60, 50)
	local specs = {
		part(V(7, 2, 4), V(0, 2.2, 0), red, { mat = Enum.Material.Metal }),
		part(V(7, 1.2, 0.4), V(0, 3, 2), red, { role = "accent" }),
		part(V(7, 1.2, 0.4), V(0, 3, -2), red, { role = "accent" }),
		part(V(0.4, 1.2, 4), V(3.5, 3, 0), red, { role = "accent" }),
		part(V(0.4, 1.2, 4), V(-3.5, 3, 0), red, { role = "accent" }),
		part(V(3, 0.3, 0.3), V(4.6, 1.8, 0), C(40, 40, 45), { role = "accent", rot = V(0, 0, 25) }),
	}
	for _, x in ipairs({ 2.4, -2.4 }) do
		table.insert(specs, cylZ(2, 0.5, V(x, 1, 2.1), C(30, 30, 30), { role = "accent" }))
		table.insert(specs, cylZ(2, 0.5, V(x, 1, -2.1), C(30, 30, 30), { role = "accent" }))
	end
	return specs
end

BUILDERS.sled = function()
	local wood = C(150, 100, 60)
	local red = C(200, 60, 55)
	return {
		part(V(7, 0.6, 3.4), V(0, 1.6, 0), wood, { mat = Enum.Material.WoodPlanks }),
		part(V(7, 0.4, 0.4), V(0, 0.8, 1.4), red, { role = "accent", mat = Enum.Material.Metal }),
		part(V(7, 0.4, 0.4), V(0, 0.8, -1.4), red, { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.4, 1.2, 0.4), V(3, 1.2, 1.4), red, { role = "accent" }),
		part(V(0.4, 1.2, 0.4), V(3, 1.2, -1.4), red, { role = "accent" }),
		part(V(1.4, 1.4, 3.4), V(3.4, 1.6, 0), wood, { role = "accent", rot = V(0, 0, 40) }),
	}
end

--===========================================================================
-- FURNITURE & HOUSEHOLD
--===========================================================================
BUILDERS.bed = function()
	local frame = C(120, 80, 50)
	local sheet = C(90, 150, 210)
	local specs = {
		part(V(6, 1, 9), V(0, 1.5, 0), frame, { mat = Enum.Material.Wood }),
		part(V(5.6, 0.8, 8.6), V(0, 2.4, 0), sheet, { mat = Enum.Material.Fabric }),
		part(V(5.6, 1.2, 2), V(0, 2.8, -2.6), C(245, 245, 245), { role = "accent", mat = Enum.Material.Fabric }),
		part(V(6, 3, 0.6), V(0, 3, -4.4), frame, { role = "accent", mat = Enum.Material.Wood }),
		part(V(6, 1.6, 0.6), V(0, 2, 4.4), frame, { role = "accent", mat = Enum.Material.Wood }),
	}
	legs4(specs, V(0.7, 1.2, 0.7), 2.6, 4, 0.6, frame, { role = "accent", mat = Enum.Material.Wood })
	return specs
end

BUILDERS.sofa = function()
	local f = C(150, 70, 80)
	return {
		part(V(8, 1.5, 3.5), V(0, 1.5, 0), f, { mat = Enum.Material.Fabric }),
		part(V(8, 2.5, 1), V(0, 3, -1.6), f, { mat = Enum.Material.Fabric }),
		part(V(1, 2.5, 3.5), V(-3.7, 3, 0), f, { role = "accent", mat = Enum.Material.Fabric }),
		part(V(1, 2.5, 3.5), V(3.7, 3, 0), f, { role = "accent", mat = Enum.Material.Fabric }),
		part(V(3.2, 1, 3), V(-1.8, 2.7, 0.2), C(170, 90, 100), { role = "accent", mat = Enum.Material.Fabric }),
		part(V(3.2, 1, 3), V(1.8, 2.7, 0.2), C(170, 90, 100), { role = "accent", mat = Enum.Material.Fabric }),
	}
end

BUILDERS.bookshelf = function()
	local wood = C(120, 80, 50)
	local specs = {
		part(V(6, 9, 0.6), V(0, 4.5, -1.2), wood, { mat = Enum.Material.Wood }),
		part(V(0.6, 9, 3), V(-3, 4.5, 0), wood, { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.6, 9, 3), V(3, 4.5, 0), wood, { role = "accent", mat = Enum.Material.Wood }),
	}
	local cols = { C(200, 60, 60), C(60, 120, 200), C(70, 170, 90), C(220, 190, 60), C(150, 90, 200) }
	for s = 0, 3 do
		table.insert(specs, part(V(6, 0.5, 3), V(0, 1 + s * 2.6, 0), wood, { role = "accent", mat = Enum.Material.Wood }))
		for b = 0, 4 do
			table.insert(specs, part(V(0.7, 2, 2.2), V(-2.4 + b * 1, 2.3 + s * 2.6, 0), cols[(b % 5) + 1], { role = "accent" }))
		end
	end
	return specs
end

BUILDERS.tv = function()
	return {
		part(V(8, 5, 0.6), V(0, 5, 0), C(25, 25, 28), { mat = Enum.Material.Metal }),
		part(V(7.4, 4.4, 0.3), V(0, 5, 0.4), C(90, 140, 190), { role = "accent", mat = Enum.Material.Glass }),
		part(V(0.6, 2, 0.6), V(0, 2.5, 0), C(40, 40, 45), { role = "accent" }),
		part(V(4, 0.4, 1.6), V(0, 1.5, 0), C(40, 40, 45), { role = "accent" }),
	}
end

BUILDERS.computer = function()
	return {
		part(V(6, 4, 0.5), V(0, 5, -1), C(30, 30, 35), { mat = Enum.Material.Metal }),
		part(V(5.4, 3.4, 0.3), V(0, 5, -0.7), C(80, 160, 200), { role = "accent", mat = Enum.Material.Glass }),
		part(V(0.5, 2, 0.5), V(0, 2.8, -1), C(40, 40, 45), { role = "accent" }),
		part(V(2.4, 0.3, 1.4), V(0, 1.7, -1), C(40, 40, 45), { role = "accent" }),
		part(V(5, 0.4, 2.2), V(0, 1.6, 1.4), C(60, 60, 65), { role = "accent" }),
		part(V(2.2, 4, 4.5), V(4.5, 2.5, 0), C(45, 45, 50), { role = "accent", mat = Enum.Material.Metal }),
	}
end

BUILDERS.fridge = function()
	local m = C(220, 220, 225)
	return {
		part(V(5, 9, 4.5), V(0, 4.5, 0), m, { mat = Enum.Material.Metal }),
		part(V(0.3, 5.6, 4.6), V(2.4, 6, 0), C(195, 195, 200), { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.3, 2.8, 4.6), V(2.4, 1.8, 0), C(195, 195, 200), { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.5, 1.6, 0.4), V(2.7, 6, 1.6), C(120, 120, 125), { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.5, 1.4, 0.4), V(2.7, 2.6, 1.6), C(120, 120, 125), { role = "accent", mat = Enum.Material.Metal }),
	}
end

BUILDERS.stove = function()
	local m = C(80, 80, 85)
	local specs = {
		part(V(5, 5, 5), V(0, 2.5, 0), m, { mat = Enum.Material.Metal }),
		part(V(5.2, 0.4, 5.2), V(0, 5, 0), C(40, 40, 45), { role = "accent", mat = Enum.Material.Metal }),
		part(V(3.6, 3, 0.3), V(0, 2.4, 2.5), C(40, 40, 45), { role = "accent", mat = Enum.Material.Glass }),
		part(V(3, 0.4, 0.4), V(0, 4.2, 2.6), C(180, 180, 185), { role = "accent", mat = Enum.Material.Metal }),
	}
	for _, x in ipairs({ -1.2, 1.2 }) do
		for _, z in ipairs({ -1.2, 1.2 }) do
			table.insert(specs, cylY(1.6, 0.3, V(x, 5.2, z), C(30, 30, 30), { role = "accent" }))
		end
	end
	return specs
end

BUILDERS.bathtub = function()
	local w = C(240, 240, 245)
	return {
		part(V(8, 3, 4.5), V(0, 2, 0), w, { mat = Enum.Material.SmoothPlastic }),
		part(V(7, 1.6, 3.5), V(0, 2.6, 0), C(120, 190, 230), { role = "accent", mat = Enum.Material.Glass }),
		part(V(0.4, 1.4, 0.4), V(3.4, 3.8, 0), C(190, 190, 195), { role = "accent", mat = Enum.Material.Metal }),
		part(V(1, 0.4, 0.4), V(3, 4.4, 0), C(190, 190, 195), { role = "accent", mat = Enum.Material.Metal }),
	}
end

BUILDERS.clock = function()
	return {
		cylZ(6, 0.8, V(0, 3.5, 0), C(235, 235, 230), { mat = Enum.Material.SmoothPlastic }),
		cylZ(5, 0.4, V(0, 3.5, 0.4), C(250, 250, 245), { role = "accent" }),
		part(V(0.3, 2, 0.2), V(0, 4.1, 0.7), C(30, 30, 30), { role = "accent" }),
		part(V(1.6, 0.3, 0.2), V(0.6, 3.5, 0.7), C(30, 30, 30), { role = "accent" }),
		part(V(0.4, 0.4, 0.4), V(0, 3.5, 0.7), C(30, 30, 30), { role = "accent", shape = "ball" }),
	}
end

BUILDERS.wardrobe = function()
	local wood = C(120, 80, 50)
	return {
		part(V(6, 10, 3.5), V(0, 5, 0), wood, { mat = Enum.Material.Wood }),
		part(V(0.3, 9, 3.6), V(0, 5, 0), C(90, 60, 38), { role = "accent" }),
		part(V(0.4, 1.4, 0.4), V(-0.6, 5, 1.8), C(220, 200, 90), { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.4, 1.4, 0.4), V(0.6, 5, 1.8), C(220, 200, 90), { role = "accent", mat = Enum.Material.Metal }),
		part(V(6.4, 0.6, 3.8), V(0, 10, 0), C(90, 60, 38), { role = "accent" }),
	}
end

BUILDERS.bench = function()
	local w = C(150, 100, 60)
	local specs = {
		part(V(7, 0.5, 2.4), V(0, 2.5, 0), w, { mat = Enum.Material.Wood }),
		part(V(7, 2, 0.5), V(0, 3.7, -1), w, { mat = Enum.Material.Wood }),
	}
	legs4(specs, V(0.5, 2.5, 0.5), 3, 0.9, 1.25, C(90, 60, 38), { role = "accent", mat = Enum.Material.Wood })
	return specs
end

BUILDERS.swing = function()
	local frame = C(80, 90, 100)
	return {
		part(V(0.5, 8, 0.5), V(-3, 4, 2.5), frame, { rot = V(25, 0, 0), mat = Enum.Material.Metal }),
		part(V(0.5, 8, 0.5), V(-3, 4, -2.5), frame, { rot = V(-25, 0, 0), mat = Enum.Material.Metal }),
		part(V(0.5, 8, 0.5), V(3, 4, 2.5), frame, { rot = V(25, 0, 0), mat = Enum.Material.Metal }),
		part(V(0.5, 8, 0.5), V(3, 4, -2.5), frame, { rot = V(-25, 0, 0), mat = Enum.Material.Metal }),
		part(V(7, 0.5, 0.5), V(0, 7.6, 0), frame, { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.2, 3, 0.2), V(0, 5.5, 0.8), C(40, 40, 40), { role = "accent" }),
		part(V(0.2, 3, 0.2), V(0, 5.5, -0.8), C(40, 40, 40), { role = "accent" }),
		part(V(2, 0.3, 1.6), V(0, 4, 0), C(200, 120, 60), { role = "accent" }),
	}
end

BUILDERS.slide = function()
	local specs = {
		part(V(0.4, 5, 0.4), V(-3, 2.5, 1), C(60, 120, 200), { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.4, 5, 0.4), V(-3, 2.5, -1), C(60, 120, 200), { role = "accent", mat = Enum.Material.Metal }),
		part(V(2.4, 0.4, 2.4), V(-3, 5, 0), C(220, 190, 60), { role = "accent" }),
		part(V(8, 0.4, 2), V(0.5, 2.6, 0), C(220, 60, 60), { rot = V(0, 0, 35) }),
		part(V(8, 0.6, 0.4), V(0.5, 3, 1), C(180, 40, 40), { role = "accent", rot = V(0, 0, 35) }),
		part(V(8, 0.6, 0.4), V(0.5, 3, -1), C(180, 40, 40), { role = "accent", rot = V(0, 0, 35) }),
	}
	for i = 0, 3 do
		table.insert(specs, part(V(2.4, 0.3, 0.3), V(-3, 1 + i * 1.2, 0), C(40, 40, 45), { role = "accent" }))
	end
	return specs
end

BUILDERS.trampoline = function()
	local frame = C(60, 60, 70)
	local mat = C(40, 40, 50)
	local specs = {
		cylY(10, 0.6, V(0, 3, 0), frame, { mat = Enum.Material.Metal }),
		cylY(8.6, 0.4, V(0, 3.1, 0), mat, { role = "accent" }),
	}
	ring(specs, 6, 4, function(x, z)
		return part(V(0.4, 3, 0.4), V(x, 1.5, z), frame, { role = "accent", mat = Enum.Material.Metal })
	end)
	return specs
end

BUILDERS.vase = function()
	local v = C(80, 150, 170)
	return {
		cylY(4, 1, V(0, 0.5, 0), v, { mat = Enum.Material.Marble }),
		cylY(2.6, 4, V(0, 3, 0), v, { mat = Enum.Material.Marble }),
		cylY(4, 2, V(0, 6, 0), v, { mat = Enum.Material.Marble }),
		cylY(3, 0.8, V(0, 7.2, 0), v, { role = "accent", mat = Enum.Material.Marble }),
		part(V(0.3, 4, 0.3), V(0.6, 9, 0), C(70, 150, 70), { role = "accent" }),
		part(V(1, 1, 1), V(0.6, 11, 0), C(235, 90, 140), { role = "accent", shape = "ball" }),
	}
end

BUILDERS.candle = function()
	return {
		cylY(2.4, 0.6, V(0, 0.3, 0), C(190, 150, 60), { role = "accent", mat = Enum.Material.Metal }),
		cylY(1.4, 5, V(0, 3, 0), C(240, 235, 215), { mat = Enum.Material.SmoothPlastic }),
		part(V(0.2, 0.6, 0.2), V(0, 5.7, 0), C(40, 40, 40), { role = "accent" }),
		part(V(0.6, 1.2, 0.6), V(0, 6.4, 0), C(255, 160, 50), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
	}
end

--===========================================================================
-- FOOD
--===========================================================================
BUILDERS.cake = function()
	local sponge = C(235, 200, 150)
	local frost = C(245, 245, 245)
	return {
		cylY(8, 2.5, V(0, 1.25, 0), sponge, { mat = Enum.Material.SmoothPlastic }),
		cylY(8.4, 0.6, V(0, 2.6, 0), frost, { role = "accent" }),
		cylY(6, 2.5, V(0, 4, 0), sponge),
		cylY(6.4, 0.6, V(0, 5.4, 0), frost, { role = "accent" }),
		cylY(0.4, 2, V(0, 6.5, 0), C(120, 80, 50), { role = "accent" }),
		part(V(1, 1, 1), V(0, 7.4, 0), C(220, 50, 60), { role = "accent", shape = "ball" }),
	}
end

BUILDERS.pizza = function()
	local crust = C(225, 185, 120)
	local cheese = C(240, 205, 90)
	local specs = {
		cylY(9, 0.6, V(0, 0.3, 0), crust),
		cylY(8, 0.3, V(0, 0.75, 0), cheese, { role = "accent" }),
	}
	ring(specs, 7, 2.8, function(x, z)
		return part(V(1, 0.3, 1), V(x, 0.95, z), C(180, 50, 45), { role = "accent", shape = "cylinder", rot = V(0, 0, 90) })
	end)
	return specs
end

BUILDERS.burger = function()
	return {
		cylY(5, 1.6, V(0, 0.8, 0), C(215, 160, 90)),
		cylY(5.2, 0.5, V(0, 1.9, 0), C(90, 170, 80), { role = "accent" }),
		cylY(4.8, 0.8, V(0, 2.5, 0), C(110, 70, 50), { role = "accent" }),
		cylY(5, 0.4, V(0, 3.1, 0), C(240, 200, 70), { role = "accent" }),
		cylY(5, 2.2, V(0, 4.4, 0), C(225, 170, 95)),
		part(V(0.3, 0.3, 0.3), V(1, 5.4, 0.6), C(245, 245, 245), { role = "accent", shape = "ball" }),
		part(V(0.3, 0.3, 0.3), V(-0.8, 5.4, -0.4), C(245, 245, 245), { role = "accent", shape = "ball" }),
	}
end

BUILDERS.donut = function()
	local d = C(180, 120, 70)
	local ice = C(235, 110, 170)
	local specs = {}
	ring(specs, 10, 2.4, function(x, z)
		return part(V(1.8, 1.8, 1.8), V(x, 1.5, z), d, { shape = "ball" })
	end)
	ring(specs, 10, 2.4, function(x, z)
		return part(V(1.6, 1, 1.6), V(x, 2.1, z), ice, { role = "accent", shape = "ball" })
	end)
	local cols = { C(220, 60, 60), C(60, 120, 220), C(70, 180, 90), C(240, 220, 60) }
	for i = 0, 5 do
		local a = math.rad(i * 60)
		table.insert(specs, part(V(0.3, 0.3, 0.3), V(math.cos(a) * 2.4, 2.6, math.sin(a) * 2.4), cols[(i % 4) + 1], { role = "accent" }))
	end
	return specs
end

BUILDERS.icecream = function()
	return {
		part(V(0.4, 4, 0.4), V(0, 2, 0), C(210, 170, 110), { role = "accent", rot = V(180, 0, 0) }),
		cylY(3, 0.5, V(0, 4, 0), C(210, 170, 110)),
		part(V(3, 3, 3), V(0, 5.4, 0), C(245, 235, 220), { role = "primary", shape = "ball" }),
		part(V(2.6, 2.6, 2.6), V(0.4, 7, 0.3), C(235, 150, 170), { role = "accent", shape = "ball" }),
		part(V(2.2, 2.2, 2.2), V(-0.2, 8.4, -0.2), C(150, 90, 60), { role = "accent", shape = "ball" }),
		part(V(0.6, 0.7, 0.6), V(0, 9.6, 0), C(220, 50, 60), { role = "accent", shape = "ball" }),
	}
end

BUILDERS.apple = function()
	local r = C(210, 50, 45)
	return {
		part(V(4, 4, 4), V(0, 2.2, 0), r, { shape = "ball" }),
		part(V(3.4, 4, 3.4), V(0, 2.2, 0), r, { role = "accent", shape = "ball" }),
		part(V(0.4, 1.2, 0.4), V(0, 4.4, 0), C(110, 80, 50), { role = "accent", mat = Enum.Material.Wood }),
		part(V(1.4, 0.3, 0.8), V(0.8, 4.5, 0), C(80, 160, 80), { role = "accent", rot = V(0, 0, 20) }),
	}
end

BUILDERS.banana = function()
	local y = C(235, 215, 60)
	local specs = {}
	for i = 0, 4 do
		local a = math.rad(-40 + i * 22)
		table.insert(specs, part(V(1.4, 1.2, 1.2), V(math.sin(a) * 3, 2.5 + math.cos(a) * 3 - 3, 0), y, { role = (i == 2) and "primary" or "accent", shape = "ball" }))
	end
	table.insert(specs, part(V(0.6, 0.8, 0.6), V(math.sin(math.rad(-40)) * 3, 2.5 + math.cos(math.rad(-40)) * 3 - 3 + 0.6, 0), C(110, 90, 50), { role = "accent" }))
	return specs
end

BUILDERS.mug = function()
	local m = C(220, 235, 245)
	return {
		cylY(3.5, 4, V(0, 2, 0), m, { mat = Enum.Material.SmoothPlastic }),
		cylY(2.8, 3.4, V(0, 2.4, 0), C(110, 70, 45), { role = "accent" }),
		part(V(0.5, 2.4, 0.5), V(2.2, 2.2, 0), m, { role = "accent" }),
		part(V(0.5, 0.5, 0.5), V(2.6, 3.2, 0), m, { role = "accent" }),
		part(V(0.5, 0.5, 0.5), V(2.6, 1.2, 0), m, { role = "accent" }),
	}
end

BUILDERS.bottle = function()
	local g = C(80, 170, 120)
	return {
		cylY(3, 5, V(0, 2.5, 0), g, { mat = Enum.Material.Glass }),
		cylY(2.4, 1.4, V(0, 5.4, 0), g, { role = "primary", mat = Enum.Material.Glass }),
		cylY(1.2, 2, V(0, 6.6, 0), g, { mat = Enum.Material.Glass }),
		cylY(1.4, 0.8, V(0, 7.8, 0), C(120, 90, 50), { role = "accent" }),
		part(V(2.4, 1.6, 0.1), V(0, 2.6, 1.5), C(235, 235, 235), { role = "accent" }),
	}
end

BUILDERS.cookie = function()
	local d = C(195, 150, 95)
	local specs = {
		cylY(5, 1, V(0, 0.5, 0), d, { mat = Enum.Material.SmoothPlastic }),
	}
	local chips = { V(1.2, 0, 0.6), V(-1, 0, 1), V(0.2, 0, -1.4), V(-1.4, 0, -0.6), V(1.6, 0, -0.4) }
	for _, c in ipairs(chips) do
		table.insert(specs, part(V(0.7, 0.7, 0.7), V(c.X, 1.1, c.Z), C(80, 50, 35), { role = "accent", shape = "ball" }))
	end
	return specs
end

BUILDERS.cupcake = function()
	return {
		cylY(4, 1, V(0, 0.5, 0), C(210, 150, 100), { mat = Enum.Material.SmoothPlastic }),
		cylY(3, 2.5, V(0, 2, 0), C(225, 170, 110)),
		part(V(3.4, 2, 3.4), V(0, 4, 0), C(235, 120, 160), { role = "primary", shape = "ball" }),
		part(V(2.6, 1.8, 2.6), V(0, 5.3, 0), C(235, 120, 160), { role = "primary", shape = "ball" }),
		part(V(0.7, 0.8, 0.7), V(0, 6.4, 0), C(220, 50, 60), { role = "accent", shape = "ball" }),
	}
end

BUILDERS.hotdog = function()
	local bun = C(225, 175, 100)
	local saus = C(190, 90, 70)
	return {
		part(V(8, 1.6, 2.6), V(0, 1.2, 0), bun, { mat = Enum.Material.SmoothPlastic }),
		part(V(8.5, 1.6, 1.6), V(0, 2.2, 0), saus, { role = "accent", shape = "cylinder" }),
		part(V(8, 0.3, 0.4), V(0, 3, 0.2), C(230, 200, 60), { role = "accent", rot = V(0, 20, 0) }),
		part(V(8, 0.3, 0.4), V(0, 3, -0.2), C(200, 50, 50), { role = "accent", rot = V(0, -20, 0) }),
	}
end

--===========================================================================
-- WEAPONS & TOOLS
--===========================================================================
BUILDERS.shield = function()
	local m = C(150, 160, 175)
	local trim = C(220, 190, 60)
	return {
		part(V(5, 6, 0.8), V(0, 4, 0), m, { mat = Enum.Material.Metal }),
		part(V(3, 2.6, 0.8), V(0, 1.6, 0), m, { role = "primary", mat = Enum.Material.Metal, rot = V(0, 0, 45) }),
		part(V(4.4, 5.4, 0.4), V(0, 4, 0.4), trim, { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.8, 3.6, 0.5), V(0, 4, 0.7), C(200, 50, 50), { role = "accent" }),
		part(V(3.6, 0.8, 0.5), V(0, 4.6, 0.7), C(200, 50, 50), { role = "accent" }),
	}
end

BUILDERS.axe = function()
	local handle = C(120, 80, 50)
	local head = C(170, 175, 185)
	return {
		part(V(0.6, 8, 0.6), V(0, 4, 0), handle, { mat = Enum.Material.Wood }),
		part(V(2, 3, 0.6), V(1.2, 7, 0), head, { role = "accent", mat = Enum.Material.Metal }),
		part(V(1.5, 3.6, 0.5), V(2, 7, 0), head, { role = "accent", shape = "wedge", rot = V(0, -90, 0), mat = Enum.Material.Metal }),
	}
end

BUILDERS.hammer = function()
	local handle = C(120, 80, 50)
	local head = C(90, 90, 95)
	return {
		part(V(0.7, 8, 0.7), V(0, 4, 0), handle, { mat = Enum.Material.Wood }),
		part(V(1.6, 1.6, 4), V(0, 7.6, 0), head, { role = "accent", shape = "cylinder", rot = V(90, 0, 0), mat = Enum.Material.Metal }),
	}
end

BUILDERS.bow = function()
	local w = C(140, 95, 55)
	local specs = {
		part(V(0.6, 8, 0.6), V(-1.5, 4, 0), w, { mat = Enum.Material.Wood, rot = V(0, 0, 20) }),
		part(V(0.6, 8, 0.6), V(-1.5, 4, 0), w, { role = "primary", mat = Enum.Material.Wood, rot = V(0, 0, -20) }),
		part(V(0.1, 8, 0.1), V(-0.5, 4, 0), C(230, 230, 230), { role = "accent" }),
		part(V(6, 0.3, 0.3), V(1, 4, 0), C(120, 80, 50), { role = "accent" }),
		part(V(0.8, 0.6, 0.6), V(4, 4, 0), C(170, 175, 185), { role = "accent", shape = "wedge", rot = V(0, 90, 0), mat = Enum.Material.Metal }),
	}
	return specs
end

BUILDERS.spear = function()
	return {
		part(V(0.4, 11, 0.4), V(0, 5.5, 0), C(120, 80, 50), { mat = Enum.Material.Wood }),
		part(V(0.8, 2.4, 0.8), V(0, 11.4, 0), C(170, 175, 185), { role = "accent", shape = "wedge", rot = V(0, 0, 0), mat = Enum.Material.Metal }),
		part(V(0.6, 1, 0.6), V(0, 10.4, 0), C(220, 190, 60), { role = "accent", mat = Enum.Material.Metal }),
	}
end

BUILDERS.cannon = function()
	local m = C(50, 50, 55)
	return {
		part(V(7, 2.4, 2.4), V(0, 3, 0), m, { shape = "cylinder", mat = Enum.Material.Metal }),
		cylZ(2.8, 0.4, V(-3.5, 3, 0), C(30, 30, 30), { role = "accent" }),
		part(V(5, 1.5, 3.5), V(-0.5, 1.5, 0), C(110, 75, 45), { role = "accent", mat = Enum.Material.Wood }),
		cylZ(3, 0.6, V(-1.5, 1, 1.8), C(80, 55, 35), { role = "accent", mat = Enum.Material.Wood }),
		cylZ(3, 0.6, V(-1.5, 1, -1.8), C(80, 55, 35), { role = "accent", mat = Enum.Material.Wood }),
		part(V(1.6, 1.6, 1.6), V(4, 3.4, 0), C(25, 25, 25), { role = "accent", shape = "ball" }),
	}
end

BUILDERS.bomb = function()
	return {
		part(V(4, 4, 4), V(0, 2.4, 0), C(35, 35, 40), { shape = "ball", mat = Enum.Material.Metal }),
		cylY(1, 1.2, V(0, 4.6, 0), C(80, 80, 85), { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.3, 2, 0.3), V(0.5, 5.6, 0), C(120, 90, 60), { role = "accent", rot = V(0, 0, 30) }),
		part(V(0.6, 0.8, 0.6), V(1, 6.4, 0), C(255, 160, 50), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
	}
end

BUILDERS.torch = function()
	return {
		cylY(0.7, 5, V(0, 2.5, 0), C(110, 75, 45), { mat = Enum.Material.Wood }),
		cylY(1.6, 1.4, V(0, 5.2, 0), C(60, 50, 40), { role = "accent", mat = Enum.Material.Wood }),
		part(V(1.6, 2.4, 1.6), V(0, 6.4, 0), C(255, 150, 40), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(1, 1.6, 1), V(0, 7, 0), C(255, 220, 80), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
	}
end

--===========================================================================
-- FANTASY & SCI-FI
--===========================================================================
BUILDERS.crown = function()
	local g = C(235, 200, 60)
	local specs = {
		cylY(5, 2, V(0, 1, 0), g, { mat = Enum.Material.Metal }),
	}
	ring(specs, 6, 2.4, function(x, z, deg)
		return part(V(0.8, 2, 0.8), V(x, 2.6, z), g, { role = "primary", mat = Enum.Material.Metal, rot = V(0, -deg, 0) })
	end)
	ring(specs, 6, 2.4, function(x, z)
		return part(V(0.6, 0.6, 0.6), V(x, 3.4, z), C(220, 50, 80), { role = "accent", shape = "ball", mat = Enum.Material.Neon })
	end)
	return specs
end

BUILDERS.wand = function()
	return {
		cylY(0.5, 7, V(0, 3.5, 0), C(40, 30, 50), { mat = Enum.Material.Wood }),
		cylY(0.7, 1, V(0, 0.5, 0), C(230, 230, 235), { role = "accent" }),
		part(V(1.4, 1.4, 0.4), V(0, 7.6, 0), C(255, 240, 120), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(0.4, 0.4, 0.4), V(1, 7, 0), C(255, 240, 120), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(0.4, 0.4, 0.4), V(-0.8, 8.2, 0), C(255, 240, 120), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
	}
end

BUILDERS.potion = function()
	local liq = C(150, 70, 210)
	return {
		part(V(3.5, 3.5, 3.5), V(0, 2.5, 0), C(225, 235, 245), { shape = "ball", mat = Enum.Material.Glass }),
		part(V(2.8, 2.4, 2.8), V(0, 2.2, 0), liq, { role = "primary", shape = "ball", mat = Enum.Material.Neon }),
		cylY(1.4, 2, V(0, 5, 0), C(225, 235, 245), { mat = Enum.Material.Glass }),
		cylY(1.6, 0.8, V(0, 6, 0), C(120, 90, 50), { role = "accent", mat = Enum.Material.Wood }),
	}
end

BUILDERS.gem = function()
	local c = C(90, 220, 200)
	return {
		part(V(3.5, 2, 3.5), V(0, 3.2, 0), c, { rot = V(0, 45, 0), mat = Enum.Material.Glass }),
		part(V(2.8, 2.6, 2.8), V(0, 1.6, 0), c, { role = "primary", rot = V(0, 45, 0), mat = Enum.Material.Glass }),
		part(V(1.8, 1.6, 1.8), V(0, 0.5, 0), c, { role = "primary", rot = V(0, 45, 0), mat = Enum.Material.Glass }),
	}
end

BUILDERS.treasurechest = function()
	local wood = C(130, 85, 50)
	local g = C(230, 195, 60)
	return {
		part(V(6, 3, 4), V(0, 1.5, 0), wood, { mat = Enum.Material.WoodPlanks }),
		part(V(6, 2.4, 4), V(0, 3.6, 0), wood, { role = "primary", shape = "cylinder", rot = V(90, 0, 0), mat = Enum.Material.WoodPlanks }),
		part(V(6.2, 0.4, 4.2), V(0, 3, 0), g, { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.5, 0.4, 4.2), V(2, 3, 0), g, { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.5, 0.4, 4.2), V(-2, 3, 0), g, { role = "accent", mat = Enum.Material.Metal }),
		part(V(1, 1, 0.6), V(0, 2.6, 2), g, { role = "accent", mat = Enum.Material.Metal }),
		part(V(4, 0.6, 3), V(0, 3.1, 0), g, { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
	}
end

BUILDERS.tombstone = function()
	local s = C(140, 140, 145)
	return {
		part(V(6, 1, 4), V(0, 0.5, 0), C(110, 110, 115), { role = "accent", mat = Enum.Material.Slate }),
		part(V(4, 5, 1.2), V(0, 3.5, 0), s, { mat = Enum.Material.Concrete }),
		cylZ(4, 1.2, V(0, 6, 0), s, { mat = Enum.Material.Concrete }),
		part(V(0.6, 2, 0.4), V(0, 5, 0.7), C(90, 90, 95), { role = "accent" }),
		part(V(2, 0.6, 0.4), V(0, 5.6, 0.7), C(90, 90, 95), { role = "accent" }),
	}
end

BUILDERS.skull = function()
	local w = C(235, 230, 215)
	return {
		part(V(4, 4, 3.8), V(0, 4, 0), w, { shape = "ball" }),
		part(V(3, 2, 3), V(0, 2.2, 0.4), w, { role = "primary" }),
		part(V(1.2, 1.4, 1.2), V(-1, 4.2, 1.6), C(30, 30, 30), { role = "accent", shape = "ball" }),
		part(V(1.2, 1.4, 1.2), V(1, 4.2, 1.6), C(30, 30, 30), { role = "accent", shape = "ball" }),
		part(V(0.6, 0.8, 0.6), V(0, 3.2, 1.8), C(30, 30, 30), { role = "accent" }),
		part(V(0.3, 1, 0.3), V(-0.7, 1.6, 1.7), C(60, 60, 60), { role = "accent" }),
		part(V(0.3, 1, 0.3), V(0, 1.6, 1.7), C(60, 60, 60), { role = "accent" }),
		part(V(0.3, 1, 0.3), V(0.7, 1.6, 1.7), C(60, 60, 60), { role = "accent" }),
	}
end

BUILDERS.ghost = function()
	local w = C(235, 240, 250)
	local specs = {
		part(V(4, 4, 4), V(0, 5, 0), w, { shape = "ball", mat = Enum.Material.ForceField }),
		part(V(4, 3, 4), V(0, 3.5, 0), w, { mat = Enum.Material.ForceField }),
		part(V(0.6, 1, 0.6), V(-0.9, 5.4, 1.7), C(40, 40, 60), { role = "accent", shape = "ball" }),
		part(V(0.6, 1, 0.6), V(0.9, 5.4, 1.7), C(40, 40, 60), { role = "accent", shape = "ball" }),
	}
	for i = 0, 3 do
		table.insert(specs, part(V(0.9, 1.6, 0.9), V(-1.5 + i, 2, 0), w, { role = "primary", shape = "ball", mat = Enum.Material.ForceField }))
	end
	return specs
end

BUILDERS.satellite = function()
	local m = C(190, 190, 195)
	return {
		part(V(3, 3, 3), V(0, 4, 0), C(200, 180, 60), { mat = Enum.Material.Foil }),
		part(V(0.4, 2, 5), V(-4, 4, 0), C(40, 60, 130), { role = "accent", mat = Enum.Material.Glass }),
		part(V(0.4, 2, 5), V(4, 4, 0), C(40, 60, 130), { role = "accent", mat = Enum.Material.Glass }),
		part(V(2, 0.4, 0.4), V(-2.2, 4, 0), m, { role = "accent", mat = Enum.Material.Metal }),
		part(V(2, 0.4, 0.4), V(2.2, 4, 0), m, { role = "accent", mat = Enum.Material.Metal }),
		part(V(3.5, 0.6, 3.5), V(0, 6.5, 0), m, { role = "accent", shape = "ball", mat = Enum.Material.Metal }),
		part(V(0.3, 1.5, 0.3), V(0, 7.4, 0), C(80, 80, 85), { role = "accent" }),
	}
end

BUILDERS.alien = function()
	local g = C(120, 210, 110)
	return {
		part(V(3.5, 3, 3), V(0, 6, 0), g, { shape = "ball" }),
		part(V(2.4, 3.5, 2), V(0, 3.4, 0), g),
		part(V(1.4, 1.8, 0.5), V(-0.9, 6.2, 1.4), C(20, 20, 20), { role = "accent", shape = "ball", rot = V(0, 0, 20) }),
		part(V(1.4, 1.8, 0.5), V(0.9, 6.2, 1.4), C(20, 20, 20), { role = "accent", shape = "ball", rot = V(0, 0, -20) }),
		part(V(0.2, 1.6, 0.2), V(-0.7, 8.4, 0), g, { role = "accent", rot = V(0, 0, 15) }),
		part(V(0.2, 1.6, 0.2), V(0.7, 8.4, 0), g, { role = "accent", rot = V(0, 0, -15) }),
		part(V(0.4, 0.4, 0.4), V(-0.9, 9.3, 0), C(120, 240, 120), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(0.4, 0.4, 0.4), V(0.9, 9.3, 0), C(120, 240, 120), { role = "accent", shape = "ball", mat = Enum.Material.Neon }),
		part(V(0.6, 2.5, 0.6), V(-1.5, 3, 0), g, { role = "accent" }),
		part(V(0.6, 2.5, 0.6), V(1.5, 3, 0), g, { role = "accent" }),
	}
end

BUILDERS.present = function()
	local box = C(200, 60, 70)
	local rib = C(240, 220, 90)
	return {
		part(V(5, 5, 5), V(0, 2.5, 0), box, { mat = Enum.Material.SmoothPlastic }),
		part(V(5.2, 5.2, 1), V(0, 2.5, 0), rib, { role = "accent" }),
		part(V(1, 5.2, 5.2), V(0, 2.5, 0), rib, { role = "accent" }),
		part(V(1.4, 1.4, 0.5), V(-0.8, 5.4, 0), rib, { role = "accent", shape = "ball" }),
		part(V(1.4, 1.4, 0.5), V(0.8, 5.4, 0), rib, { role = "accent", shape = "ball" }),
		part(V(0.6, 0.6, 0.6), V(0, 5.4, 0), rib, { role = "accent", shape = "ball" }),
	}
end

BUILDERS.star = function()
	local y = C(250, 220, 70)
	local specs = {
		part(V(2.4, 2.4, 1), V(0, 4, 0), y, { mat = Enum.Material.Neon }),
	}
	ring(specs, 5, 2, function(x, z, deg)
		return part(V(1.4, 3, 0.8), V(x, 4 + z, 0), y, { role = "primary", mat = Enum.Material.Neon, rot = V(0, 0, -deg) })
	end)
	return specs
end

--===========================================================================
-- TOYS, SPORTS & MISC
--===========================================================================
BUILDERS.soccerball = function()
	local w = C(245, 245, 245)
	local specs = {
		part(V(4, 4, 4), V(0, 2.2, 0), w, { shape = "ball" }),
	}
	local spots = { V(0, 2, 0), V(1.6, 0, 0.6), V(-1.4, 0.4, 1), V(0.4, 1.6, -1.4), V(-0.8, -1.4, 0.8), V(1, -1, -1) }
	for _, s in ipairs(spots) do
		table.insert(specs, part(V(1, 1, 1), V(s.X, 2.2 + s.Y, s.Z), C(30, 30, 30), { role = "accent", shape = "ball" }))
	end
	return specs
end

BUILDERS.dice = function()
	local w = C(245, 245, 245)
	local specs = {
		part(V(4, 4, 4), V(0, 2.2, 0), w, { mat = Enum.Material.SmoothPlastic }),
	}
	local function pip(x, y, z)
		table.insert(specs, part(V(0.6, 0.6, 0.6), V(x, 2.2 + y, z), C(30, 30, 30), { role = "accent", shape = "ball" }))
	end
	pip(0, 2.05, 0) -- top: 1
	pip(2.05, 1, 1); pip(2.05, 0, 0); pip(2.05, -1, -1) -- right: 3
	pip(-1, 1, 2.05); pip(1, 1, 2.05); pip(-1, -1, 2.05); pip(1, -1, 2.05) -- front: 4 (+2 center)
	pip(-1, 1, -2.05); pip(1, -1, -2.05) -- back: 2
	return specs
end

BUILDERS.kite = function()
	local d = C(220, 70, 90)
	local specs = {
		part(V(4, 4, 0.3), V(0, 6, 0), d, { rot = V(0, 0, 45) }),
		part(V(0.3, 5.5, 0.4), V(0, 6, 0.1), C(120, 90, 60), { role = "accent" }),
		part(V(5.5, 0.3, 0.4), V(0, 6, 0.1), C(120, 90, 60), { role = "accent" }),
	}
	for i = 0, 4 do
		local y = 3.5 - i * 0.8
		table.insert(specs, part(V(0.8, 0.4, 0.2), V(math.sin(i) * 0.6, y, 0), C(70, 140, 200), { role = "accent", rot = V(0, 0, 45) }))
	end
	return specs
end

BUILDERS.teddybear = function()
	local b = C(170, 120, 80)
	local specs = {
		part(V(3.5, 4, 3), V(0, 4, 0), b, { shape = "ball", mat = Enum.Material.Fabric }),
		part(V(3, 3, 3), V(0, 7, 0), b, { shape = "ball", mat = Enum.Material.Fabric }),
		part(V(1, 1, 0.8), V(-1.1, 8.2, 0), b, { role = "accent", shape = "ball", mat = Enum.Material.Fabric }),
		part(V(1, 1, 0.8), V(1.1, 8.2, 0), b, { role = "accent", shape = "ball", mat = Enum.Material.Fabric }),
		part(V(0.9, 0.8, 0.6), V(0, 6.5, 1.4), C(90, 65, 45), { role = "accent", shape = "ball" }),
		part(V(0.35, 0.35, 0.35), V(-0.7, 7.3, 1.4), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(0.35, 0.35, 0.35), V(0.7, 7.3, 1.4), C(20, 20, 20), { role = "accent", shape = "ball" }),
		part(V(1.4, 1.4, 1.2), V(-2.2, 4.5, 0), b, { role = "accent", shape = "ball", mat = Enum.Material.Fabric }),
		part(V(1.4, 1.4, 1.2), V(2.2, 4.5, 0), b, { role = "accent", shape = "ball", mat = Enum.Material.Fabric }),
	}
	legs4(specs, V(1.4, 1.6, 1.4), 1, 0, 1.4, b, { role = "accent", shape = "ball", mat = Enum.Material.Fabric })
	return specs
end

BUILDERS.guitar = function()
	local wood = C(180, 90, 50)
	return {
		part(V(5, 5.5, 1.4), V(0, 3, 0), wood, { shape = "ball", mat = Enum.Material.Wood }),
		part(V(3.4, 3.8, 1.5), V(0, 5.5, 0), wood, { role = "primary", shape = "ball", mat = Enum.Material.Wood }),
		cylZ(2, 0.3, V(0, 4, 0.7), C(30, 30, 30), { role = "accent" }),
		part(V(1.2, 8, 1), V(0, 9.5, 0), C(80, 50, 35), { role = "accent", mat = Enum.Material.Wood }),
		part(V(1.6, 2, 1), V(0, 13.6, 0), C(40, 30, 25), { role = "accent", mat = Enum.Material.Wood }),
		part(V(0.08, 8, 0.4), V(0, 7, 0.8), C(220, 220, 220), { role = "accent" }),
	}
end

BUILDERS.drum = function()
	local specs = {
		cylY(5, 4, V(0, 2.5, 0), C(200, 50, 50), { mat = Enum.Material.SmoothPlastic }),
		cylY(5.2, 0.4, V(0, 4.6, 0), C(235, 235, 235), { role = "accent" }),
		cylY(5.2, 0.4, V(0, 0.4, 0), C(235, 235, 235), { role = "accent" }),
		part(V(0.3, 5, 0.3), V(0.8, 7, 0), C(150, 110, 70), { role = "accent", mat = Enum.Material.Wood, rot = V(20, 0, 0) }),
		part(V(0.3, 5, 0.3), V(-0.8, 7, 0), C(150, 110, 70), { role = "accent", mat = Enum.Material.Wood, rot = V(-20, 0, 0) }),
	}
	return specs
end

BUILDERS.key = function()
	local g = C(225, 190, 60)
	return {
		cylZ(3, 0.5, V(-2.5, 3, 0), g, { mat = Enum.Material.Metal }),
		cylZ(1.4, 0.6, V(-2.5, 3, 0), C(46, 46, 48), { role = "accent" }),
		part(V(5, 0.8, 0.5), V(0.5, 3, 0), g, { mat = Enum.Material.Metal }),
		part(V(0.6, 1.6, 0.5), V(2.4, 2.4, 0), g, { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.6, 1.2, 0.5), V(1.4, 2.5, 0), g, { role = "accent", mat = Enum.Material.Metal }),
	}
end

BUILDERS.anvil = function()
	local m = C(60, 60, 65)
	return {
		part(V(6, 1.5, 3), V(0, 4.2, 0), m, { mat = Enum.Material.Metal }),
		part(V(2.6, 1.6, 2.6), V(0, 2.8, 0), m, { role = "primary", mat = Enum.Material.Metal }),
		part(V(4.5, 1.8, 3), V(0, 0.9, 0), m, { role = "primary", mat = Enum.Material.Metal }),
		part(V(2.4, 1.4, 2), V(4, 4.3, 0), m, { role = "accent", shape = "wedge", rot = V(0, -90, 0), mat = Enum.Material.Metal }),
	}
end

BUILDERS.bucket = function()
	local m = C(120, 130, 140)
	return {
		cylY(4, 4, V(0, 2, 0), m, { mat = Enum.Material.Metal }),
		cylY(3.4, 3.6, V(0, 2.1, 0), C(70, 130, 190), { role = "accent", mat = Enum.Material.Glass }),
		cylY(4.4, 0.4, V(0, 4, 0), m, { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.3, 4, 0.3), V(2, 4, 0), C(80, 80, 85), { role = "accent", rot = V(0, 0, 90) }),
		part(V(0.3, 3, 0.3), V(2, 3, 0), C(80, 80, 85), { role = "accent", rot = V(0, 0, 40) }),
		part(V(0.3, 3, 0.3), V(-2, 3, 0), C(80, 80, 85), { role = "accent", rot = V(0, 0, -40) }),
	}
end

BUILDERS.trophy = function()
	local g = C(235, 200, 60)
	return {
		part(V(4, 2, 4), V(0, 1, 0), C(90, 60, 40), { role = "accent", mat = Enum.Material.Wood }),
		cylY(2, 2, V(0, 3, 0), g, { mat = Enum.Material.Metal }),
		part(V(4, 3.5, 4), V(0, 5.5, 0), g, { shape = "ball", mat = Enum.Material.Metal }),
		part(V(0.5, 2.5, 1), V(-2.4, 6, 0), g, { role = "accent", mat = Enum.Material.Metal, rot = V(0, 0, 30) }),
		part(V(0.5, 2.5, 1), V(2.4, 6, 0), g, { role = "accent", mat = Enum.Material.Metal, rot = V(0, 0, -30) }),
		part(V(0.4, 1.6, 0.4), V(-2.6, 5, 0), g, { role = "accent", mat = Enum.Material.Metal }),
		part(V(0.4, 1.6, 0.4), V(2.6, 5, 0), g, { role = "accent", mat = Enum.Material.Metal }),
	}
end

BUILDERS.trafficcone = function()
	local o = C(230, 100, 30)
	local specs = {
		part(V(5, 0.6, 5), V(0, 0.3, 0), o, { mat = Enum.Material.SmoothPlastic }),
	}
	for i = 0, 4 do
		local w = 3.4 - i * 0.6
		table.insert(specs, cylY(w, 1.2, V(0, 1 + i * 1.1, 0), o, { mat = Enum.Material.SmoothPlastic }))
	end
	table.insert(specs, cylY(3.1, 0.6, V(0, 2.6, 0), C(245, 245, 245), { role = "accent" }))
	return specs
end

BUILDERS.sign = function()
	local wood = C(150, 105, 60)
	return {
		part(V(0.6, 6, 0.6), V(0, 3, 0), wood, { mat = Enum.Material.Wood }),
		part(V(5, 3, 0.4), V(0, 5.5, 0), C(190, 145, 90), { mat = Enum.Material.WoodPlanks }),
		part(V(5.2, 0.4, 0.5), V(0, 7, 0), C(110, 75, 45), { role = "accent", mat = Enum.Material.Wood }),
		part(V(5.2, 0.4, 0.5), V(0, 4, 0), C(110, 75, 45), { role = "accent", mat = Enum.Material.Wood }),
		part(V(3, 0.3, 0.5), V(0, 5.8, 0.3), C(60, 45, 30), { role = "accent" }),
		part(V(3.4, 0.3, 0.5), V(0, 5.1, 0.3), C(60, 45, 30), { role = "accent" }),
	}
end

BUILDERS.heart = function()
	local r = C(220, 40, 70)
	return {
		part(V(2.6, 2.6, 2.4), V(-1.1, 5, 0), r, { shape = "ball", mat = Enum.Material.Neon }),
		part(V(2.6, 2.6, 2.4), V(1.1, 5, 0), r, { role = "primary", shape = "ball", mat = Enum.Material.Neon }),
		part(V(3.6, 3.6, 2.4), V(0, 3, 0), r, { rot = V(0, 0, 45), mat = Enum.Material.Neon }),
	}
end

BUILDERS.moon = function()
	local g = C(210, 210, 220)
	return {
		part(V(6, 6, 6), V(0, 4, 0), g, { shape = "ball" }),
		part(V(1.4, 0.6, 1.4), V(1.5, 5.5, 1.6), C(170, 170, 180), { role = "accent", shape = "ball" }),
		part(V(1, 0.5, 1), V(-1.6, 4.4, 1.5), C(170, 170, 180), { role = "accent", shape = "ball" }),
		part(V(0.8, 0.4, 0.8), V(0.4, 6.2, -1.8), C(170, 170, 180), { role = "accent", shape = "ball" }),
	}
end

BUILDERS.firehydrant = function()
	local r = C(210, 50, 45)
	return {
		cylY(3, 5, V(0, 2.5, 0), r, { mat = Enum.Material.Metal }),
		part(V(3.6, 3.6, 3.6), V(0, 5, 0), r, { shape = "ball", mat = Enum.Material.Metal }),
		cylY(1, 1, V(0, 6.6, 0), r, { role = "accent", mat = Enum.Material.Metal }),
		part(V(1.6, 1.6, 1.6), V(0, 6.8, 0), C(220, 190, 60), { role = "accent", shape = "ball", mat = Enum.Material.Metal }),
		part(V(2, 1.4, 1.4), V(2, 3.6, 0), r, { role = "accent", shape = "cylinder", rot = V(0, 0, 90) }),
		part(V(2, 1.4, 1.4), V(-2, 3.6, 0), r, { role = "accent", shape = "cylinder", rot = V(0, 0, 90) }),
		cylY(3.6, 0.8, V(0, 0.4, 0), C(60, 60, 65), { role = "accent", mat = Enum.Material.Metal }),
	}
end

BUILDERS.dumpster = function()
	local g = C(60, 110, 70)
	return {
		part(V(8, 5, 4.5), V(0, 3, 0), g, { mat = Enum.Material.Metal }),
		part(V(8.2, 0.6, 5), V(0, 5.6, 0), C(40, 80, 50), { role = "accent", mat = Enum.Material.Metal }),
		part(V(3.6, 0.4, 5), V(-2, 5.9, 0), C(45, 90, 55), { role = "accent", rot = V(8, 0, 0) }),
		part(V(3.6, 0.4, 5), V(2, 5.9, 0), C(45, 90, 55), { role = "accent", rot = V(8, 0, 0) }),
		cylZ(1.4, 0.6, V(2.6, 0.7, 2.4), C(30, 30, 30), { role = "accent" }),
		cylZ(1.4, 0.6, V(-2.6, 0.7, 2.4), C(30, 30, 30), { role = "accent" }),
		cylZ(1.4, 0.6, V(2.6, 0.7, -2.4), C(30, 30, 30), { role = "accent" }),
		cylZ(1.4, 0.6, V(-2.6, 0.7, -2.4), C(30, 30, 30), { role = "accent" }),
	}
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
	-- Original set
	house = "house", home = "house", cabin = "house", cottage = "house", hut = "house", shack = "house", building = "house",
	tree = "tree", oak = "tree", pine = "tree", bush = "tree",
	car = "car", vehicle = "car", automobile = "car", racecar = "car", jeep = "car", sedan = "car",
	sword = "sword", blade = "sword", katana = "sword", dagger = "sword", excalibur = "sword",
	chair = "chair", seat = "chair", stool = "chair", throne = "chair",
	table = "table", desk = "table",
	castle = "castle", tower = "castle", fortress = "castle", keep = "castle", turret = "castle",
	rocket = "rocket", spaceship = "rocket", missile = "rocket", spacecraft = "rocket",
	robot = "robot", bot = "robot", mech = "robot", android = "robot", droid = "robot",
	snowman = "snowman",
	flower = "flower", rose = "flower", tulip = "flower", daisy = "flower",
	mushroom = "mushroom", toadstool = "mushroom", shroom = "mushroom",
	crate = "crate", box = "crate", cargo = "crate",
	lamp = "lamp", lantern = "lamp", streetlight = "lamp", lamppost = "lamp", light = "lamp",
	boat = "boat", ship = "boat", canoe = "boat", sailboat = "boat", raft = "boat",
	campfire = "campfire", bonfire = "campfire", fire = "campfire", fireplace = "campfire",
	coin = "coin", token = "coin", medallion = "coin",
	pyramid = "pyramid", tomb = "pyramid",
	fence = "fence", railing = "fence",
	-- Nature
	cactus = "cactus",
	palm = "palm", palmtree = "palm",
	rock = "rock", boulder = "rock", stone = "rock",
	pond = "pond", lake = "pond", puddle = "pond",
	cloud = "cloud",
	log = "log",
	pumpkin = "pumpkin", jackolantern = "pumpkin",
	sunflower = "sunflower",
	coral = "coral",
	iceberg = "iceberg",
	volcano = "volcano",
	island = "island",
	-- Animals
	dog = "dog", puppy = "dog", doggo = "dog",
	cat = "cat", kitten = "cat", kitty = "cat",
	fish = "fish",
	bird = "bird", robin = "bird", sparrow = "bird",
	duck = "duck", duckling = "duck",
	penguin = "penguin",
	bee = "bee", bumblebee = "bee",
	butterfly = "butterfly",
	frog = "frog", toad = "frog",
	pig = "pig", piglet = "pig",
	cow = "cow", cattle = "cow",
	sheep = "sheep", lamb = "sheep",
	chicken = "chicken", hen = "chicken", chick = "chicken",
	rabbit = "rabbit", bunny = "rabbit", hare = "rabbit",
	turtle = "turtle", tortoise = "turtle",
	dragon = "dragon",
	shark = "shark",
	whale = "whale",
	spider = "spider",
	snake = "snake", serpent = "snake",
	-- Buildings & structures
	windmill = "windmill",
	lighthouse = "lighthouse",
	barn = "barn",
	tent = "tent",
	igloo = "igloo",
	bridge = "bridge",
	wall = "wall", rampart = "wall",
	well = "well", wishingwell = "well",
	mailbox = "mailbox", postbox = "mailbox",
	birdhouse = "birdhouse",
	gazebo = "gazebo", pavilion = "gazebo",
	fountain = "fountain",
	staircase = "staircase", stairs = "staircase", steps = "staircase",
	ladder = "ladder",
	skyscraper = "skyscraper", tower2 = "skyscraper", highrise = "skyscraper",
	temple = "temple", shrine = "temple",
	-- Vehicles
	airplane = "airplane", plane = "airplane", aeroplane = "airplane", jet = "airplane",
	helicopter = "helicopter", chopper = "helicopter", heli = "helicopter",
	train = "train", locomotive = "train",
	tank = "tank",
	submarine = "submarine", sub = "submarine",
	bicycle = "bicycle", bike = "bicycle", cycle = "bicycle",
	motorcycle = "motorcycle", motorbike = "motorcycle", moped = "motorcycle",
	bus = "bus", coach = "bus",
	ufo = "ufo", saucer = "ufo", flyingsaucer = "ufo",
	balloon = "balloon", hotairballoon = "balloon", airballoon = "balloon",
	wagon = "wagon", cart = "wagon",
	sled = "sled", sleigh = "sled", sledge = "sled",
	truck = "wagon", -- a flatbed wagon reads closer than the sports car
	-- Furniture & household
	bed = "bed",
	sofa = "sofa", couch = "sofa", settee = "sofa",
	bookshelf = "bookshelf", bookcase = "bookshelf", shelf = "bookshelf",
	tv = "tv", television = "tv", telly = "tv",
	computer = "computer", pc = "computer", monitor = "computer", desktop = "computer",
	fridge = "fridge", refrigerator = "fridge", freezer = "fridge",
	stove = "stove", oven = "stove", cooker = "stove",
	bathtub = "bathtub", bath = "bathtub", tub = "bathtub",
	clock = "clock",
	wardrobe = "wardrobe", closet = "wardrobe", cupboard = "wardrobe",
	bench = "bench",
	swing = "swing",
	slide = "slide",
	trampoline = "trampoline",
	vase = "vase", pot = "vase",
	candle = "candle",
	-- Food
	cake = "cake", birthdaycake = "cake",
	pizza = "pizza",
	burger = "burger", hamburger = "burger", cheeseburger = "burger",
	donut = "donut", doughnut = "donut",
	icecream = "icecream", cream = "icecream", sundae = "icecream", gelato = "icecream",
	apple = "apple",
	banana = "banana",
	mug = "mug", cup = "mug", coffee = "mug",
	bottle = "bottle",
	cookie = "cookie", biscuit = "cookie",
	cupcake = "cupcake", muffin = "cupcake",
	hotdog = "hotdog", hammerdog = "hotdog",
	-- Weapons & tools
	shield = "shield",
	axe = "axe", hatchet = "axe",
	hammer = "hammer", mallet = "hammer",
	bow = "bow",
	spear = "spear", lance = "spear", javelin = "spear",
	cannon = "cannon",
	bomb = "bomb", tnt = "bomb",
	torch = "torch", flashlight = "torch",
	-- Fantasy & sci-fi
	crown = "crown", tiara = "crown",
	wand = "wand", staff = "wand",
	potion = "potion", elixir = "potion",
	gem = "gem", diamond = "gem", jewel = "gem", crystal = "gem", ruby = "gem", emerald = "gem",
	treasurechest = "treasurechest", treasure = "treasurechest", chest = "treasurechest", loot = "treasurechest",
	tombstone = "tombstone", gravestone = "tombstone", grave = "tombstone",
	skull = "skull",
	ghost = "ghost", spirit = "ghost",
	satellite = "satellite",
	alien = "alien", martian = "alien", extraterrestrial = "alien",
	present = "present", gift = "present",
	star = "star",
	-- Toys, sports & misc
	soccerball = "soccerball", football = "soccerball", ball = "soccerball",
	dice = "dice", die = "dice",
	kite = "kite",
	teddybear = "teddybear", teddy = "teddybear", bear = "teddybear", plushie = "teddybear",
	guitar = "guitar",
	drum = "drum",
	key = "key",
	anvil = "anvil",
	bucket = "bucket", pail = "bucket",
	trophy = "trophy", cup2 = "trophy", award = "trophy",
	trafficcone = "trafficcone", cone = "trafficcone",
	sign = "sign", signpost = "sign", billboard = "sign",
	heart = "heart",
	moon = "moon",
	firehydrant = "firehydrant", hydrant = "firehydrant",
	dumpster = "dumpster", trashcan = "dumpster", bin = "dumpster", garbage = "dumpster",
}

-- A short representative sample for the panel's help text.
local SUPPORTED_SAMPLE = {
	"house", "tree", "dog", "dragon", "car", "airplane", "castle", "rocket",
	"robot", "cake", "sword", "crown", "guitar", "ufo", "fountain",
}

local EXAMPLE_PROMPTS = {
	"big red car", "wooden cabin", "glowing blue castle", "giant tree",
	"golden sword", "neon robot", "purple rocket", "happy snowman",
	"green dragon", "tiny mushroom", "stone lighthouse", "metal tank",
	"pink flower", "yellow submarine", "gold coin", "chocolate cake",
	"fluffy sheep", "red bicycle", "glowing crystal", "wooden treasurechest",
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
		do
			-- The object word usually comes last ("big red car"), so the last
			-- match wins. This also lets "fire hydrant" beat "fire" → campfire.
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
	help.Text = "140+ objects: " .. table.concat(SUPPORTED_SAMPLE, ", ")
		.. "… (animals, buildings, vehicles, furniture, food, weapons & more — see README)."
		.. "\nAdd colours (red, blue, gold…), materials (wood, metal, neon, glass…) and sizes (tiny, big, giant)."
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
		ui.status.Text = "Didn't recognise an object, so I made a placeholder crystal. Try a word like: dog, dragon, castle, airplane, cake, guitar…"
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
