

local GearBase = require(script.Parent.Parent.GearBase)
local MobilityComponent = require(script.Parent.Parent.MobilityComponent)
local GunWeapon = require(script.Parent.Parent.Weapons.GunWeapon)

local AntiPersonnelGear = {}


local AP_MOBILITY_PRESET = "Gen4Gear"

local GUN_CONFIG = {
	maxAmmo = 4,
	reloadTime = 2.5,
	cooldown = 0.5,
	damage = 30,
	range = 500,
}

export type APSavedState = {
	gasLeft: number?,
	gasRight: number?,
	leftAmmo: number?,
	rightAmmo: number?,
}

function AntiPersonnelGear.new(owner: Player, savedState: APSavedState?)
	savedState = savedState or {}

	local leftGun = GunWeapon.new(GUN_CONFIG)
	local rightGun = GunWeapon.new(GUN_CONFIG)

	if savedState.leftAmmo then
		leftGun._ammo = math.clamp(savedState.leftAmmo, 0, GUN_CONFIG.maxAmmo)
	end
	if savedState.rightAmmo then
		rightGun._ammo = math.clamp(savedState.rightAmmo, 0, GUN_CONFIG.maxAmmo)
	end

	local gear = GearBase.new(owner, {
		PresetName = "AntiPersonnel",
		Mobility = MobilityComponent.new({
			presetName = AP_MOBILITY_PRESET,
			gasLeft = savedState.gasLeft,
			gasRight = savedState.gasRight,
		}),
		Weapons = {
			Left = leftGun,
			Right = rightGun,
		},
	})

	return gear
end

return AntiPersonnelGear
