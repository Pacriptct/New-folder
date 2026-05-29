local WeaponBase = {}
WeaponBase.__index = WeaponBase

export type WeaponConfig = {
	cooldown: number?,
	[string]: any,
}

function WeaponBase.new(config: WeaponConfig)
	local self = setmetatable({}, WeaponBase)

	self._config = config or {}
	self._gear = nil
	self._equipped = false
	self._cooldown = config.cooldown or 0
	self._lastAttack = -math.huge

	return self
end

------------------------------------------------------------
-- Component lifecycle
------------------------------------------------------------

function WeaponBase:init(gear)
	self._gear = gear
end

function WeaponBase:equip()
	self._equipped = true
end

function WeaponBase:unequip()
	self._equipped = false
end

function WeaponBase:update(_dt: number) end

function WeaponBase:destroy()
	self:unequip()
	self._gear = nil
end

------------------------------------------------------------
-- Attack gate
------------------------------------------------------------

-- Base attack: enforces cooldown and equipped state.
-- Subclasses should call this first, then add their own validation:
--
--   function BladeWeapon:attack(ctx)
--       if not WeaponBase.attack(self, ctx) then return false end
--       -- blade-specific logic ...
--       return true
--   end
function WeaponBase:attack(_context: any?): boolean
	if not self:canAttack() then
		return false
	end
	self._lastAttack = os.clock()
	return true
end

function WeaponBase:canAttack(): boolean
	if not self._equipped then
		return false
	end
	return os.clock() - self._lastAttack >= self._cooldown
end

function WeaponBase:getAttackCooldownRemaining(): number
	return math.max(0, self._cooldown - (os.clock() - self._lastAttack))
end

return WeaponBase
