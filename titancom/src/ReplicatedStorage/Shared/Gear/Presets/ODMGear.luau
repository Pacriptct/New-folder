-- ODMGear: Factory for Gen1 and Gen4 standard ODM gear.
--
-- Composes: MobilityComponent (ODM physics state) + BladeWeapon (left slot)
--           + BladeWeapon (right slot).
--
-- Gen1 vs Gen4 differences come entirely from GearConfig presets; the factory
-- only passes the presetName through. Per-weapon tuning can be overridden here
-- if a future preset requires different blade stats (e.g. a fragile Gen1 blade).
--
-- savedState is an optional table from PlayerData / ProfileService so gas and
-- reserve counts survive respawn without a full refill.

local GearBase = require(script.Parent.Parent.GearBase)
local MobilityComponent = require(script.Parent.Parent.MobilityComponent)
local BladeWeapon = require(script.Parent.Parent.Weapons.BladeWeapon)

local ODMGear = {}

-- Blade tuning per ODM variant. Add more presets here as new gear types ship.
local BLADE_CONFIGS = {
	Gen4Gear = {
		maxDurability = 5,
		reserves = 4,
		cooldown = 0.3,
		damagePerSpeed = 0.4,
		minDamage = 4,
		maxDamage = 130,
		oneShotSpeed = 220,
	},
	Gen1Gear = {
		maxDurability = 5,
		reserves = 4,
		cooldown = 0.25,
		damagePerSpeed = 0.4,
		minDamage = 4,
		maxDamage = 130,
		oneShotSpeed = 220,
	},
}

local DEFAULT_BLADE_CONFIG = BLADE_CONFIGS.Gen1Gear

export type ODMSavedState = {
	gasLeft: number?,
	gasRight: number?,
	bladeReserves: number?,
	leftBladeDurability: number?,
	rightBladeDurability: number?,
	hasActivePair: boolean?,
	activePairIndex: number?,
}

function ODMGear.new(owner: Player, presetName: string, savedState: ODMSavedState?)
	presetName = presetName or "Gen1Gear"
	savedState = savedState or {}

	local bladeConfig = BLADE_CONFIGS[presetName] or DEFAULT_BLADE_CONFIG

	local leftBlade = BladeWeapon.new(bladeConfig)
	local rightBlade = BladeWeapon.new(bladeConfig)

	-- Restore per-blade durability from saved state when provided.
	if savedState.hasActivePair then
		leftBlade:refill(nil, savedState.leftBladeDurability)
		rightBlade:refill(nil, savedState.rightBladeDurability)
	end
	if savedState.bladeReserves then
		leftBlade:refill(savedState.bladeReserves, nil)
		rightBlade:refill(savedState.bladeReserves, nil)
	end

	local gear = GearBase.new(owner, {
		PresetName = presetName,
		Mobility = MobilityComponent.new({
			presetName = presetName,
			gasLeft = savedState.gasLeft,
			gasRight = savedState.gasRight,
		}),
		Weapons = {
			Left = leftBlade,
			Right = rightBlade,
		},
	})

	return gear
end

return ODMGear
