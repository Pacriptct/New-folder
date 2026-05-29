

local GearBase = {}
GearBase.__index = GearBase

export type Component = {
	init: (self: any, gear: any) -> (),
	equip: (self: any) -> (),
	unequip: (self: any) -> (),
	update: (self: any, dt: number) -> (),
	destroy: (self: any) -> (),
}

export type GearConfig = {
	PresetName: string,
	Mobility: Component?,
	Weapons: { [string]: Component }?,
}

export type GearBase = typeof(setmetatable(
	{} :: {
		Owner: Player,
		PresetName: string,
		Mobility: Component?,
		Weapons: { [string]: Component },
		_equipped: boolean,
		_cooldowns: { [string]: number },
	},
	GearBase
))

function GearBase.new(owner: Player, config: GearConfig): GearBase
	local self = setmetatable({}, GearBase)

	self.Owner = owner
	self.PresetName = config.PresetName or "Unknown"
	self.Mobility = config.Mobility or nil
	self.Weapons = config.Weapons or {}
	self._equipped = false
	self._cooldowns = {}

	return self
end

function GearBase:init()
	if self.Mobility then
		self.Mobility:init(self)
	end
	for _, weapon in pairs(self.Weapons) do
		weapon:init(self)
	end
end

function GearBase:equip()
	if self._equipped then
		return
	end
	self._equipped = true

	if self.Mobility then
		self.Mobility:equip()
	end
	for _, weapon in pairs(self.Weapons) do
		weapon:equip()
	end
end

function GearBase:unequip()
	if not self._equipped then
		return
	end
	self._equipped = false

	if self.Mobility then
		self.Mobility:unequip()
	end
	for _, weapon in pairs(self.Weapons) do
		weapon:unequip()
	end
end

function GearBase:update(dt: number)
	if not self._equipped then
		return
	end

	if self.Mobility then
		self.Mobility:update(dt)
	end
	for _, weapon in pairs(self.Weapons) do
		weapon:update(dt)
	end
end

function GearBase:destroy()
	self:unequip()

	if self.Mobility then
		self.Mobility:destroy()
		self.Mobility = nil
	end

	for key, weapon in pairs(self.Weapons) do
		weapon:destroy()
		self.Weapons[key] = nil
	end

	self.Owner = nil :: any
end

function GearBase:isEquipped(): boolean
	return self._equipped
end

function GearBase:getWeapon(slot: string): Component?
	return self.Weapons[slot]
end

-- Cooldown helpers shared across all gear types.

function GearBase:startCooldown(name: string, duration: number)
	self._cooldowns[name] = os.clock() + duration
end

function GearBase:isCooldownReady(name: string): boolean
	local expiry = self._cooldowns[name]
	return expiry == nil or os.clock() >= expiry
end

function GearBase:getCooldownRemaining(name: string): number
	local expiry = self._cooldowns[name]
	if not expiry then
		return 0
	end
	return math.max(0, expiry - os.clock())
end

return GearBase
