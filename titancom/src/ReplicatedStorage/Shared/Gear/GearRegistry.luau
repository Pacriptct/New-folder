

local ODMGear = require(script.Parent.Presets.ODMGear)
local AntiPersonnelGear = require(script.Parent.Presets.AntiPersonnelGear)

local GearRegistry = {}


local FACTORIES: { [string]: (owner: Player, presetName: string, savedState: any?) -> any } = {
	Gen1Gear = function(owner, presetName, savedState)
		return ODMGear.new(owner, presetName, savedState)
	end,
	Gen4Gear = function(owner, presetName, savedState)
		return ODMGear.new(owner, presetName, savedState)
	end,
	AntiPersonnel = function(owner, _presetName, savedState)
		return AntiPersonnelGear.new(owner, savedState)
	end,
}

local FALLBACK_PRESET = "Gen1Gear"

function GearRegistry.create(presetName: string, owner: Player, savedState: any?)
	local factory = FACTORIES[presetName]
	if not factory then
		warn("[GearRegistry] Unknown preset '" .. tostring(presetName) .. "', falling back to " .. FALLBACK_PRESET)
		presetName = FALLBACK_PRESET
		factory = FACTORIES[FALLBACK_PRESET]
	end

	local gear = factory(owner, presetName, savedState)
	gear:init()
	return gear
end

function GearRegistry.isValid(presetName: string): boolean
	return FACTORIES[presetName] ~= nil
end

function GearRegistry.getPresetNames(): { string }
	local names = {}
	for name in pairs(FACTORIES) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return GearRegistry
