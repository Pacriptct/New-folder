-- AntiPersonnelGear: Factory for Anti-Personnel ODM gear.
--
-- Composes: MobilityComponent (reuses Gen4 mobility stats — AP gear is fast)
--           + GunWeapon (left slot) + GunWeapon (right slot).
--
-- Keeping this as a separate factory (rather than a flag on ODMGear) means
-- the weapon slots carry a completely different type. GearService can call
-- gear:getWeapon("Left"):attack() and get the right behaviour without any
-- type-checking switch statement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GearBase = require(ReplicatedStorage.Shared.Gear.GearBase)
local MobilityComponent = require(ReplicatedStorage.Shared.Gear.MobilityComponent)
local GunWeapon = require(ReplicatedStorage.Shared.Gear.Weapons.GunWeapon)

local AntiPersonnelGear = {}

-- AP gear borrows Gen4 mobility stats; the faster preset fits the assault role.
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
