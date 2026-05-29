local WeaponBase = require(script.Parent.WeaponBase)

local BladeWeapon = setmetatable({}, { __index = WeaponBase })
BladeWeapon.__index = BladeWeapon

local DEFAULT_MAX_DURABILITY = 5
local DEFAULT_RESERVES = 4

export type BladeConfig = {
	maxDurability: number?,
	reserves: number?,
	cooldown: number?,
	damagePerSpeed: number?,
	minDamage: number?,
	maxDamage: number?,
	oneShotSpeed: number?,
}

export type BladeState = {
	leftDurability: number,
	rightDurability: number,
	reserves: number,
	hasActivePair: boolean,
	activePairIndex: number?,
}

function BladeWeapon.new(config: BladeConfig)
	local self = WeaponBase.new(config) :: any
	setmetatable(self, BladeWeapon)

	self._maxDurability = config.maxDurability or DEFAULT_MAX_DURABILITY
	self._maxReserves = config.reserves or DEFAULT_RESERVES
	self._reserves = self._maxReserves

	self._leftDurability = 0
	self._rightDurability = 0
	self._hasActivePair = false
	self._activePairIndex = nil

	self._damagePerSpeed = config.damagePerSpeed or 0.4
	self._minDamage = config.minDamage or 4
	self._maxDamage = config.maxDamage or 130
	self._oneShotSpeed = config.oneShotSpeed or 220

	self._isSwinging = false

	return self
end

------------------------------------------------------------
-- Lifecycle overrides
------------------------------------------------------------

function BladeWeapon:equip()
	WeaponBase.equip(self)
	if not self._hasActivePair and self._reserves > 0 then
		self:_drawNewPair()
	end
end

function BladeWeapon:unequip()
	WeaponBase.unequip(self)
	self._isSwinging = false
end

------------------------------------------------------------
-- Swing API
------------------------------------------------------------

function BladeWeapon:beginSwing(): boolean
	if not self:hasUsableBlade() then
		return false
	end
	if not WeaponBase.canAttack(self) then
		return false
	end
	self._isSwinging = true
	self._lastAttack = os.clock()
	return true
end

-- Called mid-swing on the server to evaluate a reported hit.
-- context: { hitPart: BasePart, speed: number, side: "Left"|"Right" }
function BladeWeapon:releaseSwing(context: any?): boolean
	if not self._isSwinging then
		return false
	end
	if context and context.side then
		local dur = context.side == "Left" and self._leftDurability or self._rightDurability
		if dur <= 0 then
			return false
		end
	end
	return true
end

function BladeWeapon:endSwing()
	self._isSwinging = false
end

function BladeWeapon:isSwinging(): boolean
	return self._isSwinging
end

------------------------------------------------------------
-- Damage calculation (server-side only)
------------------------------------------------------------

function BladeWeapon:calculateDamage(speed: number): number
	speed = tonumber(speed) or 0
	local damage = speed * self._damagePerSpeed
	return math.clamp(damage, self._minDamage, self._maxDamage)
end

function BladeWeapon:isOneShot(speed: number): boolean
	return (tonumber(speed) or 0) >= self._oneShotSpeed
end

------------------------------------------------------------
-- Durability API
------------------------------------------------------------

-- Chip one use from the specified side (or whichever has durability).
-- Returns true when the pair is spent so the caller knows to drop blades.
function BladeWeapon:consumeDurability(side: ("Left" | "Right")?, amount: number?): boolean
	amount = math.max(1, tonumber(amount) or 1)

	if side == "Left" then
		self._leftDurability = math.max(0, self._leftDurability - amount)
	elseif side == "Right" then
		self._rightDurability = math.max(0, self._rightDurability - amount)
	else
		-- No side specified: chip left first, then right.
		if self._leftDurability > 0 then
			self._leftDurability = math.max(0, self._leftDurability - amount)
		elseif self._rightDurability > 0 then
			self._rightDurability = math.max(0, self._rightDurability - amount)
		end
	end

	local spent = self._leftDurability <= 0 and self._rightDurability <= 0
	if spent then
		self:_clearActivePair()
	end
	return spent
end

function BladeWeapon:hasUsableBlade(): boolean
	return self._hasActivePair
		and (self._leftDurability > 0 or self._rightDurability > 0)
end

function BladeWeapon:hasReserve(): boolean
	return self._reserves > 0 or self._hasActivePair
end

-- Manually draw the next reserve pair. Returns false when out of reserves.
function BladeWeapon:drawNewPair(): boolean
	if self._reserves <= 0 then
		return false
	end
	return self:_drawNewPair()
end

function BladeWeapon:drop()
	self:_clearActivePair()
end

function BladeWeapon:refill(reserves: number?, durability: number?)
	self._reserves = reserves or self._maxReserves
	if durability and durability > 0 then
		self._leftDurability = durability
		self._rightDurability = durability
		self._hasActivePair = true
		self._activePairIndex = self._reserves + 1
	end
end

-- Snapshot used by GearService._broadcastResources()
function BladeWeapon:getState(): BladeState
	return {
		leftDurability = self._leftDurability,
		rightDurability = self._rightDurability,
		reserves = self._reserves,
		hasActivePair = self._hasActivePair,
		activePairIndex = self._activePairIndex,
	}
end

-- Restore state from a server-broadcast snapshot (client-side).
function BladeWeapon:applyState(state: BladeState)
	self._leftDurability = state.leftDurability or 0
	self._rightDurability = state.rightDurability or 0
	self._reserves = state.reserves or 0
	self._hasActivePair = state.hasActivePair == true
	self._activePairIndex = state.activePairIndex or nil
end

------------------------------------------------------------
-- Private
------------------------------------------------------------

function BladeWeapon:_drawNewPair(): boolean
	self._activePairIndex = self._reserves
	self._reserves = math.max(0, self._reserves - 1)
	self._leftDurability = self._maxDurability
	self._rightDurability = self._maxDurability
	self._hasActivePair = true
	return true
end

function BladeWeapon:_clearActivePair()
	self._hasActivePair = false
	self._activePairIndex = nil
	self._leftDurability = 0
	self._rightDurability = 0
	self._isSwinging = false
end

return BladeWeapon
