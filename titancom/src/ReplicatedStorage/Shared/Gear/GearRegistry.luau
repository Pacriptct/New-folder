-- GearRegistry: Single lookup table that maps preset names to gear factories.
--
-- Both GearService (server) and GearServiceClient (client) call
-- GearRegistry.create() to build a fully-initialised gear instance without
-- importing any specific preset module. Adding a new gear type means registering
-- one entry here — no changes to either service are required.
--
-- Usage:
--   local gear = GearRegistry.create("Gen1Gear", player, savedState)
--   gear:equip()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ODMGear = require(ReplicatedStorage.Shared.Gear.Presets.ODMGear)
local AntiPersonnelGear = require(ReplicatedStorage.Shared.Gear.Presets.AntiPersonnelGear)

local GearRegistry = {}

-- factory(owner, presetName, savedState) → GearBase
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

-- Creates, inits, and returns a gear instance.
-- savedState is optional and is passed straight through to the factory.
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
