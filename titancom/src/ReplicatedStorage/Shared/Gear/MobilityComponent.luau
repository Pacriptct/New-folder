local GearConfig = require(script.Parent.Parent.Configs.GearConfig)

local MobilityComponent = {}
MobilityComponent.__index = MobilityComponent

local MAX_GAS_DEFAULT = 100

export type HookState = {
	active: boolean,
	target: Vector3?,
	attachPart: BasePart?,
}

export type GasState = {
	Left: number,
	Right: number,
	MaxLeft: number,
	MaxRight: number,
}

export type MobilityConfig = {
	presetName: string,
	gasLeft: number?,
	gasRight: number?,
	maxGasLeft: number?,
	maxGasRight: number?,
}

function MobilityComponent.new(config: MobilityConfig)
	local self = setmetatable({}, MobilityComponent)

	self._presetName = config.presetName or "Gen1Gear"
	self._preset = GearConfig.GetPreset(self._presetName)
	self._gear = nil

	local maxLeft = config.maxGasLeft or MAX_GAS_DEFAULT
	local maxRight = config.maxGasRight or MAX_GAS_DEFAULT

	self._gas = {
		Left = math.min(config.gasLeft or maxLeft, maxLeft),
		Right = math.min(config.gasRight or maxRight, maxRight),
		MaxLeft = maxLeft,
		MaxRight = maxRight,
	} :: GasState

	self._hooks = {
		Left = { active = false, target = nil, attachPart = nil } :: HookState,
		Right = { active = false, target = nil, attachPart = nil } :: HookState,
	}

	self._momentum = self._preset.MinMomentum or 0.18
	self._isBoosting = false
	self._isOrbiting = false

	return self
end

------------------------------------------------------------
-- Component lifecycle
------------------------------------------------------------

function MobilityComponent:init(gear)
	self._gear = gear
end

-- equip() is intentionally left as a no-op stub. The client physics layer
-- (GearServiceClient / ManeuverModule) performs actual constraint setup; this component just holds state.
function MobilityComponent:equip() end

function MobilityComponent:unequip()
	self:releaseHook("Left")
	self:releaseHook("Right")
	self._isBoosting = false
	self._isOrbiting = false
end

-- Called each frame on the client to decay momentum when no hooks are active.
-- The server does not call this; it only reads the stored momentum value.
function MobilityComponent:update(dt: number)
	if not self:isAnyHookActive() then
		self:_decayMomentum(dt)
	end
end

function MobilityComponent:destroy()
	self:unequip()
	self._gear = nil
end

------------------------------------------------------------
-- Hook API
------------------------------------------------------------

function MobilityComponent:fireHook(side: "Left" | "Right", target: Vector3, attachPart: BasePart?)
	local hook = self._hooks[side]
	if not hook then
		return
	end
	hook.active = true
	hook.target = target
	hook.attachPart = attachPart or nil
end

function MobilityComponent:releaseHook(side: "Left" | "Right")
	local hook = self._hooks[side]
	if not hook then
		return
	end
	hook.active = false
	hook.target = nil
	hook.attachPart = nil
end

function MobilityComponent:isHookActive(side: "Left" | "Right"): boolean
	local hook = self._hooks[side]
	return hook ~= nil and hook.active == true
end

function MobilityComponent:isAnyHookActive(): boolean
	return self:isHookActive("Left") or self:isHookActive("Right")
end

function MobilityComponent:getHookState(side: "Left" | "Right"): HookState?
	return self._hooks[side]
end

------------------------------------------------------------
-- Gas API
------------------------------------------------------------

-- Returns false (and does NOT deduct) if the requested tank is empty.
-- Callers should treat a false return as a denied action.
function MobilityComponent:consumeGas(amount: number, tank: "Left" | "Right" | "Both"): boolean
	amount = math.max(0, tonumber(amount) or 0)
	if amount == 0 then
		return true
	end

	if tank == "Left" then
		if self._gas.Left < amount then
			return false
		end
		self._gas.Left = math.max(0, self._gas.Left - amount)

	elseif tank == "Right" then
		if self._gas.Right < amount then
			return false
		end
		self._gas.Right = math.max(0, self._gas.Right - amount)

	else
		local half = amount / 2
		if self._gas.Left < half or self._gas.Right < half then
			return false
		end
		self._gas.Left = math.max(0, self._gas.Left - half)
		self._gas.Right = math.max(0, self._gas.Right - half)
	end

	return true
end

function MobilityComponent:refillGas(leftAmount: number?, rightAmount: number?)
	local g = self._gas
	g.Left = math.min(g.MaxLeft, g.Left + (leftAmount or g.MaxLeft))
	g.Right = math.min(g.MaxRight, g.Right + (rightAmount or g.MaxRight))
end

-- Used by GearService to push authoritative server state to this component.
function MobilityComponent:setGas(left: number, right: number)
	local g = self._gas
	g.Left = math.clamp(left, 0, g.MaxLeft)
	g.Right = math.clamp(right, 0, g.MaxRight)
end

function MobilityComponent:getGas(): GasState
	return self._gas
end

function MobilityComponent:isOutOfGas(): boolean
	return self._gas.Left <= 0 and self._gas.Right <= 0
end

------------------------------------------------------------
-- Boost API
------------------------------------------------------------

-- Returns false when out of gas so callers can gate the action.
function MobilityComponent:boost(): boolean
	if self:isOutOfGas() then
		return false
	end
	self._isBoosting = true
	return true
end

function MobilityComponent:stopBoost()
	self._isBoosting = false
end

function MobilityComponent:isBoosting(): boolean
	return self._isBoosting
end

------------------------------------------------------------
-- Orbit API
------------------------------------------------------------

function MobilityComponent:startOrbit()
	self._isOrbiting = true
end

function MobilityComponent:stopOrbit()
	self._isOrbiting = false
end

function MobilityComponent:isOrbiting(): boolean
	return self._isOrbiting
end

------------------------------------------------------------
-- Momentum API
------------------------------------------------------------

function MobilityComponent:getMomentum(): number
	return self._momentum
end

function MobilityComponent:setMomentum(value: number)
	local preset = self._preset
	local min = preset.MinMomentum or 0.18
	local max = preset.MaxMomentum or 1.35
	self._momentum = math.clamp(value, min, max)
end

function MobilityComponent:gainMomentum(amount: number)
	self:setMomentum(self._momentum + amount)
end

------------------------------------------------------------
-- Preset switching (e.g. talent upgrade mid-session)
------------------------------------------------------------

function MobilityComponent:setPreset(presetName: string)
	self._presetName = presetName
	self._preset = GearConfig.GetPreset(presetName)
end

function MobilityComponent:getPreset()
	return self._preset
end

function MobilityComponent:getPresetName(): string
	return self._presetName
end

------------------------------------------------------------
-- Private
------------------------------------------------------------

function MobilityComponent:_decayMomentum(dt: number)
	local preset = self._preset
	if not preset then
		return
	end
	local loss = (preset.MomentumLoss or 0.000055) * dt
	self:setMomentum(self._momentum - loss)
end

return MobilityComponent
