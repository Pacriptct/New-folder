-- src/shared/Gear/GearTuning.luau
-- Shared definitions for per-part gear tuning. The player picks a value 1..5
-- per part at the final assembly table; 3 is neutral. Each step away from 3
-- moves the part's primary stat by STEP and its trade-off stat by STEP in
-- the opposite direction (or the same direction, when both stats are linked).

local GearTuning = {}

GearTuning.MIN_VALUE = 1
GearTuning.MAX_VALUE = 5
GearTuning.DEFAULT_VALUE = 3
GearTuning.STEP = 0.075 -- 7.5% per increment, so the extreme positions are ±15%

GearTuning.PART_ORDER = {
	"Launchers", "Reels", "GasCanisters", "Nozzles", "Scabbards", "Blades", "Handles",
}

-- Direction = 1  -> tuning value up (towards 5) raises the multiplier
-- Direction = -1 -> tuning value up lowers the multiplier
GearTuning.PART_DEFINITIONS = {
	Launchers = {
		Primary  = { Stat = "HookRangeMultiplier", Direction = 1, Label = "Hook Range" },
		Tradeoff = { Stat = "GasEfficiency",       Direction = -1, Label = "Gas Efficiency" },
		Description = "Up: longer hooks, more gas burn.\nDown: shorter hooks, less gas burn.",
	},
	Reels = {
		Primary  = { Stat = "MaxSpeedMultiplier", Direction = 1, Label = "Top Speed" },
		Tradeoff = { Stat = "GasEfficiency",      Direction = -1, Label = "Gas Efficiency" },
		Description = "Up: higher top speed, more gas burn.\nDown: lower top speed, less gas burn.",
	},
	GasCanisters = {
		Primary  = { Stat = "GasCapacityMultiplier", Direction = 1, Label = "Gas Capacity" },
		Tradeoff = { Stat = "MaxSpeedMultiplier",    Direction = -1, Label = "Top Speed" },
		Description = "Up: bigger tank, slower top speed (heavier).\nDown: smaller tank, faster top speed.",
	},
	Nozzles = {
		Primary  = { Stat = "AccelerationMultiplier", Direction = 1, Label = "Acceleration" },
		Tradeoff = { Stat = "GasEfficiency",          Direction = -1, Label = "Gas Efficiency" },
		Description = "Up: snappier acceleration, more gas burn.\nDown: lazier acceleration, less gas burn.",
	},
	Scabbards = {
		Primary  = { Stat = "BladeCapacityMultiplier", Direction = 1, Label = "Blade Capacity" },
		Tradeoff = { Stat = "MaxSpeedMultiplier",      Direction = -1, Label = "Top Speed" },
		Description = "Up: carry more spare blades, slower top speed.\nDown: carry fewer blades, faster top speed.",
	},
	Blades = {
		Primary  = { Stat = "DamageMultiplier",   Direction = 1, Label = "Damage" },
		Tradeoff = { Stat = "WearRateMultiplier", Direction = 1, Label = "Wear Rate" },
		Description = "Up: more damage per hit, gear wears faster.\nDown: less damage, gear wears slower.",
	},
	Handles = {
		Primary  = { Stat = "GasEfficiency",      Direction = 1, Label = "Gas Efficiency" },
		Tradeoff = { Stat = "MaxSpeedMultiplier", Direction = -1, Label = "Top Speed" },
		Description = "Up: smoother control saves gas, top speed dips.\nDown: lower gas efficiency, higher top speed.",
	},
}

local function clampValue(v)
	v = tonumber(v)
	if v == nil then return GearTuning.DEFAULT_VALUE end
	v = math.floor(v + 0.5)
	if v < GearTuning.MIN_VALUE then return GearTuning.MIN_VALUE end
	if v > GearTuning.MAX_VALUE then return GearTuning.MAX_VALUE end
	return v
end

GearTuning.ClampValue = clampValue

function GearTuning.IsValidPartType(partType)
	return GearTuning.PART_DEFINITIONS[partType] ~= nil
end

function GearTuning.DefaultTuning()
	local out = {}
	for _, part in ipairs(GearTuning.PART_ORDER) do
		out[part] = GearTuning.DEFAULT_VALUE
	end
	return out
end

function GearTuning.NormalizeTuning(tuning)
	local out = GearTuning.DefaultTuning()
	if type(tuning) == "table" then
		for part, value in pairs(tuning) do
			if GearTuning.PART_DEFINITIONS[part] then
				out[part] = clampValue(value)
			end
		end
	end
	return out
end

-- Returns the multiplier this single (partType, value) pair contributes to a stat.
local function contribution(definition, role, value)
	local entry = definition[role]
	if not entry then return 1 end
	local delta = (value - GearTuning.DEFAULT_VALUE) * GearTuning.STEP * entry.Direction
	return 1 + delta
end

-- Aggregate every part's tuning into per-stat multipliers. Stats not affected
-- by any part default to 1.
function GearTuning.ComputeMultipliers(tuning)
	tuning = GearTuning.NormalizeTuning(tuning)
	local stats = {
		MaxSpeedMultiplier = 1,
		AccelerationMultiplier = 1,
		GasEfficiency = 1,
		HookRangeMultiplier = 1,
		DamageMultiplier = 1,
		GasCapacityMultiplier = 1,
		BladeCapacityMultiplier = 1,
		WearRateMultiplier = 1,
	}
	for partType, def in pairs(GearTuning.PART_DEFINITIONS) do
		local value = tuning[partType] or GearTuning.DEFAULT_VALUE
		local primaryMult = contribution(def, "Primary", value)
		local tradeoffMult = contribution(def, "Tradeoff", value)
		stats[def.Primary.Stat] = (stats[def.Primary.Stat] or 1) * primaryMult
		stats[def.Tradeoff.Stat] = (stats[def.Tradeoff.Stat] or 1) * tradeoffMult
	end
	return stats
end

-- For UI tooltips: returns { Primary = {Label, Delta}, Tradeoff = {Label, Delta} }
-- where Delta is a percentage like "+15%" or "-7.5%" relative to neutral.
function GearTuning.PreviewForPart(partType, value)
	local def = GearTuning.PART_DEFINITIONS[partType]
	if not def then return nil end
	value = clampValue(value)
	local function pct(role)
		local entry = def[role]
		local delta = (value - GearTuning.DEFAULT_VALUE) * GearTuning.STEP * entry.Direction
		local sign = delta >= 0 and "+" or ""
		return string.format("%s%.1f%%", sign, delta * 100)
	end
	return {
		Primary  = { Label = def.Primary.Label,  Delta = pct("Primary"),  Stat = def.Primary.Stat },
		Tradeoff = { Label = def.Tradeoff.Label, Delta = pct("Tradeoff"), Stat = def.Tradeoff.Stat },
		Description = def.Description,
	}
end

return GearTuning
