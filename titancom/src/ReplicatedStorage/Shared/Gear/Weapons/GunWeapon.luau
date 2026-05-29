local WeaponBase = require(script.Parent.WeaponBase)

local GunWeapon = setmetatable({}, { __index = WeaponBase })
GunWeapon.__index = GunWeapon

local DEFAULT_MAX_AMMO = 4
local DEFAULT_RELOAD_TIME = 2.5
local DEFAULT_DAMAGE = 30
local DEFAULT_RANGE = 500

export type GunConfig = {
	maxAmmo: number?,
	reloadTime: number?,
	cooldown: number?,
	damage: number?,
	range: number?,
}

export type GunState = {
	ammo: number,
	maxAmmo: number,
	isReloading: boolean,
	reloadProgress: number,
}

function GunWeapon.new(config: GunConfig)
	local self = WeaponBase.new(config) :: any
	setmetatable(self, GunWeapon)

	self._maxAmmo = config.maxAmmo or DEFAULT_MAX_AMMO
	self._ammo = self._maxAmmo
	self._reloadTime = config.reloadTime or DEFAULT_RELOAD_TIME
	self._reloadRemaining = 0
	self._isReloading = false

	self._damage = config.damage or DEFAULT_DAMAGE
	self._range = config.range or DEFAULT_RANGE

	return self
end

------------------------------------------------------------
-- Lifecycle overrides
------------------------------------------------------------

function GunWeapon:update(dt: number)
	if not self._isReloading then
		return
	end
	self._reloadRemaining = math.max(0, self._reloadRemaining - dt)
	if self._reloadRemaining <= 0 then
		self:_finishReload()
	end
end

function GunWeapon:unequip()
	WeaponBase.unequip(self)
end

------------------------------------------------------------
-- Attack / Fire API
------------------------------------------------------------

function GunWeapon:attack(_context: any?): boolean
	if self._isReloading then
		return false
	end
	if not WeaponBase.canAttack(self) then
		return false
	end
	if self._ammo <= 0 then
		self:reload()
		return false
	end

	self._ammo -= 1
	self._lastAttack = os.clock()
	return true
end

function GunWeapon:canAttack(): boolean
	return WeaponBase.canAttack(self) and not self._isReloading and self._ammo > 0
end

------------------------------------------------------------
-- Reload API
------------------------------------------------------------

function GunWeapon:reload()
	if self._isReloading or self._ammo >= self._maxAmmo then
		return
	end
	self._isReloading = true
	self._reloadRemaining = self._reloadTime
end

function GunWeapon:cancelReload()
	self._isReloading = false
	self._reloadRemaining = 0
end

function GunWeapon:isReloading(): boolean
	return self._isReloading
end

-- [0, 1] progress where 1 = fully reloaded.
function GunWeapon:getReloadProgress(): number
	if not self._isReloading then
		return 1
	end
	return 1 - (self._reloadRemaining / self._reloadTime)
end

------------------------------------------------------------
-- State helpers
------------------------------------------------------------

function GunWeapon:getAmmo(): number
	return self._ammo
end

function GunWeapon:getMaxAmmo(): number
	return self._maxAmmo
end

function GunWeapon:getDamage(): number
	return self._damage
end

function GunWeapon:getRange(): number
	return self._range
end

function GunWeapon:refillAmmo()
	self._ammo = self._maxAmmo
	self._isReloading = false
	self._reloadRemaining = 0
end

function GunWeapon:getState(): GunState
	return {
		ammo = self._ammo,
		maxAmmo = self._maxAmmo,
		isReloading = self._isReloading,
		reloadProgress = self:getReloadProgress(),
	}
end

function GunWeapon:applyState(state: GunState)
	self._ammo = state.ammo or 0
	self._isReloading = state.isReloading == true
	if self._isReloading then
		self._reloadRemaining = self._reloadTime * (1 - (state.reloadProgress or 0))
	end
end

------------------------------------------------------------
-- Private
------------------------------------------------------------

function GunWeapon:_finishReload()
	self._isReloading = false
	self._reloadRemaining = 0
	self._ammo = self._maxAmmo
end

return GunWeapon
