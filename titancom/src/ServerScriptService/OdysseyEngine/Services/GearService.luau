local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Networker = require(ReplicatedStorage.Packages.Networker)
local GearRegistry = require(ReplicatedStorage.Shared.Gear.GearRegistry)
local AudioGroups = require(ReplicatedStorage.Shared.Modules.AudioGroups)

local GearService = {}

GearService.Name = "GearService"

GearService._states = {}
GearService.networker = nil

GearService._gearInstances = {}

GearService._activeSwingConnections = {}
GearService._hitThisSwing = {}

GearService._pendingTitanHitReports = {}

GearService._wearAccumulators = {}
GearService._repairSessions = {}

GearService.Config = {
	DefaultPreset = "Gen1Gear",
	BladeDropLifetime = 8,

	WearSecondsPerPoint = 90,
	WearFloor = 5, 
	WearTickInterval = 5, 

	OneShotSpeed = 220,

	MinimumHitSpeed = 8,
	MaximumHitSpeed = 280,
	DamagePerSpeed = 0.4,
	MinimumDamage = 4,
	MaximumDamage = 130,

	NapeDamageMultiplier = 1.35,
	ArmoredDamageMultiplier = 0.5,

	DeadHitboxColor = Color3.fromRGB(255, 0, 0),
	AliveHitboxColor = Color3.fromRGB(180, 120, 60),

	TitanRespawnCooldown = 5,
	DefaultNapeHealth = 250,
	DefaultHitboxHealth = 150,

	HitSoundVolume = 0.55,
	HitSoundMinDistance = 10,
	HitSoundMaxDistance = 90,

	MaxBladeDurability = 5,
	MaxBladeReserves = 4,

	MaxGasLeft = 100,
	MaxGasRight = 100,

	HookShotGasCost = 0.25,
	BoostGasCostPerSecond = 7,
	VDashGasCost = 18,
	GasCrossfeedPerSecond = 4,

	BladeDamagePerTitanHit = 1,

	CritDamageMultiplier = 1.5,
	NapeSeekerOneShotMultiplier = 0.9,
	BladeConservationChance = 0.25,

	DebugSwordHits = false,
}

function GearService:init()
	self.networker = Networker.server.new("GearService", self, {
		self.clientEquipGear,
		self.clientUnequipGear,
		self.clientToggleHandles,
		self.clientSetBladesOut,
		self.clientDropBlades,

		self.clientBeginBladeSwing,
		self.clientReleaseBladeSwing,
		self.clientEndBladeSwing,

		self.clientConsumeGas,
		self.clientCrossfeedGas,
		self.clientRefillGas,
		self.clientRefillBlades,

		self.requestEquipODM,
	})

	Players.PlayerRemoving:Connect(function(player)
		self:_clearSwingConnections(player)
		self:_destroyGearInstance(player)

		self._states[player] = nil
		self._hitThisSwing[player] = nil
		self._pendingTitanHitReports[player] = nil
		self._wearAccumulators[player] = nil

		for sessionId, session in pairs(self._repairSessions) do
			if session.Player == player then
				self._repairSessions[sessionId] = nil
			end
		end

		player:SetAttribute("IsBladeSwinging", false)
	end)


	-- Auto-equip gear on character spawn
	local function onCharacterAdded(player, _character)
		task.wait(1)
		if player.Parent then
			self:forceEquipClient(player, self.Config.DefaultPreset)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end)

	for _, player in Players:GetPlayers() do
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
end

------------------------------------------------------------
-- Tuning helpers
------------------------------------------------------------

function GearService:_getEquippedStats(_player)
	return {}
end

function GearService:_effectiveMaxGasLeft(player)
	local stats = self:_getEquippedStats(player)
	local mult = tonumber(stats and stats.GasCapacityMultiplier) or 1
	return self.Config.MaxGasLeft * mult
end

function GearService:_effectiveMaxGasRight(player)
	local stats = self:_getEquippedStats(player)
	local mult = tonumber(stats and stats.GasCapacityMultiplier) or 1
	return self.Config.MaxGasRight * mult
end

function GearService:_effectiveMaxBladeReserves(player)
	local stats = self:_getEquippedStats(player)
	local mult = tonumber(stats and stats.BladeCapacityMultiplier) or 1
	return math.max(1, math.floor(self.Config.MaxBladeReserves * mult + 0.5))
end

function GearService:_effectiveWearSecondsPerPoint(player)
	local stats = self:_getEquippedStats(player)
	local mult = tonumber(stats and stats.WearRateMultiplier) or 1
	if mult <= 0 then
		mult = 1
	end
	return self.Config.WearSecondsPerPoint / mult
end

------------------------------------------------------------
-- Gear Wear
------------------------------------------------------------

function GearService:_tickGearWear(_dt)
end

------------------------------------------------------------
-- Repair QTE
------------------------------------------------------------

function GearService:BeginRepair(_player)
	return false
end

function GearService:finishRepairQTE(_player, _sessionId, _score, _totalCircles)
end

------------------------------------------------------------
-- Talent / Modifier Helpers
------------------------------------------------------------

function GearService:_getPlayerData(player)
	local playerServiceModule = script.Parent:FindFirstChild("PlayerService")
	if not playerServiceModule or not playerServiceModule:IsA("ModuleScript") then
		return nil
	end

	local success, playerService = pcall(require, playerServiceModule)
	if not success or type(playerService) ~= "table" then
		return nil
	end

	if playerService.Get then
		return playerService:Get(player)
	end

	if playerService.getData then
		return playerService:getData(player)
	end

	if playerService.GetData then
		return playerService:GetData(player)
	end

	return nil
end

function GearService:_getTalentModifiers(player)
	local data = self:_getPlayerData(player)
	if type(data) ~= "table" then
		return nil
	end

	if type(data.TalentModifiers) == "table" then
		return data.TalentModifiers
	end

	return nil
end

function GearService:_getTalentPercent(player, target)
	local modifiers = self:_getTalentModifiers(player)
	if type(modifiers) ~= "table" or type(modifiers.Percent) ~= "table" then
		return 0
	end

	local value = modifiers.Percent[target]
	return if type(value) == "number" then value else 0
end

function GearService:_getTalentFlat(player, target)
	local modifiers = self:_getTalentModifiers(player)
	if type(modifiers) ~= "table" or type(modifiers.Flat) ~= "table" then
		return 0
	end

	local value = modifiers.Flat[target]
	return if type(value) == "number" then value else 0
end

function GearService:_hasTalentPassive(player, passiveName)
	local modifiers = self:_getTalentModifiers(player)
	if type(modifiers) ~= "table" or type(modifiers.Passive) ~= "table" then
		return false
	end

	return modifiers.Passive[passiveName] == true
end

function GearService:_applyTalentModifier(player, target, baseValue, context)
	context = context or {}

	local value = tonumber(baseValue) or 0
	local flat = self:_getTalentFlat(player, target)
	local percent = self:_getTalentPercent(player, target)

	local modifiers = self:_getTalentModifiers(player)
	if type(modifiers) == "table" and type(modifiers.Conditional) == "table" then
		for _, effect in ipairs(modifiers.Conditional) do
			if type(effect) == "table" and context[effect.Condition] == true then
				local inner = effect.Effect

				if type(inner) == "table" and inner.Target == target then
					if inner.Type == "Flat" then
						flat += inner.Value or 0
					elseif inner.Type == "Percent" then
						percent += inner.Value or 0
					end
				end
			end
		end
	end

	return (value + flat) * (1 + percent)
end

function GearService:_getDamageContext(player, hitbox)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	local hitboxKind = self:_getHitboxKind(hitbox)
	local isNape = hitboxKind == "Nape" or hitbox.Name == "NHIT"

	local isAirborne = false
	if humanoid then
		isAirborne = humanoid.FloorMaterial == Enum.Material.Air
	end

	local speed = 0
	if root and root:IsA("BasePart") then
		speed = root.AssemblyLinearVelocity.Magnitude
	end

	return {
		UsingODMBlades = true,
		HitNape = isNape,
		IsNape = isNape,
		IsAirborne = isAirborne,
		Speed = speed,
	}
end

------------------------------------------------------------
-- State / Resource Helpers
------------------------------------------------------------

function GearService:_getDefaultState()
	return {
		Equipped = false,
		HandlesOut = false,
		BladesOut = false,
		Preset = self.Config.DefaultPreset,

		GasLeft = self.Config.MaxGasLeft,
		GasRight = self.Config.MaxGasRight,

		BladeReserves = self.Config.MaxBladeReserves,

		LeftBladeDurability = 0,
		RightBladeDurability = 0,

		HasActiveBladePair = false,
		ActiveBladePairIndex = nil,
	}
end

function GearService:getState(player)
	local state = self._states[player]

	if not state then
		state = self:_getDefaultState()
		self._states[player] = state
	end

	return state
end

function GearService:GetState(player)
	return self:getState(player)
end

function GearService:_broadcastState(player)
	if not self.networker then
		return
	end

	local state = self:getState(player)

	self.networker:fireAll("gearState", player, {
		Equipped = state.Equipped,
		HandlesOut = state.HandlesOut,
		BladesOut = state.BladesOut,
		Preset = state.Preset,
	})
end

function GearService:_broadcastResources(player)
	if not self.networker then
		return
	end

	local state = self:getState(player)

	player:SetAttribute("GasLeft", state.GasLeft)
	player:SetAttribute("GasRight", state.GasRight)
	player:SetAttribute("BladeReserves", state.BladeReserves)
	player:SetAttribute("LeftBladeDurability", state.LeftBladeDurability)
	player:SetAttribute("RightBladeDurability", state.RightBladeDurability)
	player:SetAttribute("HasActiveBladePair", state.HasActiveBladePair == true)

	if state.ActiveBladePairIndex then
		player:SetAttribute("ActiveBladePairIndex", state.ActiveBladePairIndex)
	else
		player:SetAttribute("ActiveBladePairIndex", nil)
	end

	self.networker:fire(player, "gearResources", {
		GasLeft = state.GasLeft,
		GasRight = state.GasRight,
		MaxGasLeft = self:_effectiveMaxGasLeft(player),
		MaxGasRight = self:_effectiveMaxGasRight(player),

		BladeReserves = state.BladeReserves,
		MaxBladeReserves = self:_effectiveMaxBladeReserves(player),

		LeftBladeDurability = state.LeftBladeDurability,
		RightBladeDurability = state.RightBladeDurability,
		MaxBladeDurability = self.Config.MaxBladeDurability,

		HasActiveBladePair = state.HasActiveBladePair == true,
		ActiveBladePairIndex = state.ActiveBladePairIndex,

		GearStats = {},
	})
end

function GearService:_drainGas(player, amount, tank)
	local state = self:getState(player)

	amount = tonumber(amount) or 0
	tank = tank or "Both"

	if amount <= 0 then
		return true
	end

	if tank == "Left" then
		if state.GasLeft < amount then
			self:_broadcastResources(player)
			return false
		end

		state.GasLeft = math.max(0, state.GasLeft - amount)
	elseif tank == "Right" then
		if state.GasRight < amount then
			self:_broadcastResources(player)
			return false
		end

		state.GasRight = math.max(0, state.GasRight - amount)
	else
		local half = amount / 2

		if state.GasLeft < half or state.GasRight < half then
			self:_broadcastResources(player)
			return false
		end

		state.GasLeft = math.max(0, state.GasLeft - half)
		state.GasRight = math.max(0, state.GasRight - half)
	end

	self:_broadcastResources(player)
	return true
end

function GearService:_crossfeedGas(player, dt)
	local state = self:getState(player)

	dt = tonumber(dt) or 0
	dt = math.clamp(dt, 0, 1)

	local rate = self.Config.GasCrossfeedPerSecond * dt

	if rate <= 0 then
		return
	end

	if state.GasLeft == state.GasRight then
		return
	end

	local maxLeft = self:_effectiveMaxGasLeft(player)
	local maxRight = self:_effectiveMaxGasRight(player)
	if state.GasLeft > state.GasRight then
		local move = math.min(rate, (state.GasLeft - state.GasRight) / 2)
		state.GasLeft = math.max(0, state.GasLeft - move)
		state.GasRight = math.min(maxRight, state.GasRight + move)
	else
		local move = math.min(rate, (state.GasRight - state.GasLeft) / 2)
		state.GasRight = math.max(0, state.GasRight - move)
		state.GasLeft = math.min(maxLeft, state.GasLeft + move)
	end

	self:_broadcastResources(player)
end

function GearService:_getCharacter(player)
	local character = player.Character
	if not character then
		return nil
	end

	if not character:FindFirstChild("HumanoidRootPart") then
		return nil
	end

	return character
end

------------------------------------------------------------
-- Blade Helpers
------------------------------------------------------------

function GearService:_isBladePart(part)
	return part:IsA("BasePart") and string.match(part.Name, "^SwordB%d+$") ~= nil
end

function GearService:_getBladeSideFromPart(bladePart)
	if bladePart:FindFirstAncestor("LeftSword") then
		return "Left"
	end

	if bladePart:FindFirstAncestor("RightSword") then
		return "Right"
	end

	return nil
end

function GearService:_hasUsableBlade(player, side)
	local state = self:getState(player)

	if side == "Left" then
		return state.LeftBladeDurability > 0
	end

	if side == "Right" then
		return state.RightBladeDurability > 0
	end

	return state.LeftBladeDurability > 0 or state.RightBladeDurability > 0
end

function GearService:_getReserveBladePart(character, side, index)
	if not character then
		return nil
	end

	local gear = character:FindFirstChild("Gear", true)
	if not gear then
		return nil
	end

	local bladeName = if side == "Left" then "LB" .. tostring(index) else "RB" .. tostring(index)
	local found = gear:FindFirstChild(bladeName, true)

	if found and found:IsA("BasePart") then
		return found
	end

	return nil
end

function GearService:_setReserveBladePairVisible(character, index, visible)
	local left = self:_getReserveBladePart(character, "Left", index)
	local right = self:_getReserveBladePart(character, "Right", index)

	for _, part in { left, right } do
		if part then
			part.Transparency = if visible then 0 else 1
			part.LocalTransparencyModifier = if visible then 0 else 1
			part.CanCollide = false
			part.CanQuery = visible
			part.CanTouch = false
			part.CastShadow = false
		end
	end
end

function GearService:_applyReserveBladeVisuals(player)
	local character = player.Character
	if not character then
		return
	end

	local state = self:getState(player)
	local maxPairs = self:_effectiveMaxBladeReserves(player)

	for index = 1, maxPairs do
		local visible = index <= state.BladeReserves

		if state.HasActiveBladePair == true and state.ActiveBladePairIndex == index then
			visible = state.BladesOut ~= true
		end

		self:_setReserveBladePairVisible(character, index, visible)
	end
end

function GearService:_consumeNewBladePair(player)
	local state = self:getState(player)

	if state.BladeReserves <= 0 then
		return false
	end

	state.ActiveBladePairIndex = state.BladeReserves
	state.BladeReserves -= 1
	state.HasActiveBladePair = true

	state.LeftBladeDurability = self.Config.MaxBladeDurability
	state.RightBladeDurability = self.Config.MaxBladeDurability

	return true
end

function GearService:_clearActiveBladePair(player)
	local state = self:getState(player)

	state.HasActiveBladePair = false
	state.ActiveBladePairIndex = nil
	state.LeftBladeDurability = 0
	state.RightBladeDurability = 0
	state.BladesOut = false
end

function GearService:_setBladeVisualDurability(character, side, durability)
	local swordName = if side == "Left" then "LeftSword" else "RightSword"
	local sword = character:FindFirstChild(swordName, true)

	if not sword then
		return
	end

	for _, descendant in sword:GetDescendants() do
		if descendant:IsA("BasePart") and self:_isBladePart(descendant) then
			local index = tonumber(string.match(descendant.Name, "%d+")) or 0
			local visible = index <= durability and durability > 0

			descendant.Transparency = if visible then 0 else 1
			descendant.LocalTransparencyModifier = descendant.Transparency
			descendant.CanTouch = visible
			descendant.CanQuery = false
			descendant.CanCollide = false
		end
	end
end

function GearService:_applyBladeDurabilityVisuals(player)
	local character = player.Character
	if not character then
		return
	end

	local state = self:getState(player)

	self:_setBladeVisualDurability(character, "Left", state.LeftBladeDurability)
	self:_setBladeVisualDurability(character, "Right", state.RightBladeDurability)
end

function GearService:_chipBlade(player, side, amount)
	local state = self:getState(player)

	amount = tonumber(amount) or 1
	amount = math.max(1, amount)

	if self:_hasTalentPassive(player, "BladeConservation") then
		if math.random() < self.Config.BladeConservationChance then
			amount = 0
		end
	end

	if amount <= 0 then
		self:_broadcastResources(player)
		return
	end

	if side == "Left" then
		state.LeftBladeDurability = math.max(0, state.LeftBladeDurability - amount)
	elseif side == "Right" then
		state.RightBladeDurability = math.max(0, state.RightBladeDurability - amount)
	end

	if state.LeftBladeDurability <= 0 and state.RightBladeDurability <= 0 then
		self:_clearActiveBladePair(player)
		self:endBladeSwing(player)
	end

	self:_applyBladeDurabilityVisuals(player)
	self:_applyServerGearVisibility(player)
	self:_broadcastResources(player)
	self:_broadcastState(player)
end

------------------------------------------------------------
-- Gear Visibility Helpers
------------------------------------------------------------

function GearService:_findCordAttachment(model, preferredNames)
	if not model then
		return nil
	end

	for _, name in preferredNames do
		local found = model:FindFirstChild(name, true)

		if found and found:IsA("Attachment") then
			return found
		end
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Attachment") then
			local lowerName = string.lower(descendant.Name)

			if string.find(lowerName, "cord") or string.find(lowerName, "wire") or string.find(lowerName, "attach") then
				return descendant
			end
		end
	end

	return nil
end

function GearService:_getActiveBladeParts(character)
	local bladeParts = {}

	for _, sword in { character:FindFirstChild("LeftSword"), character:FindFirstChild("RightSword") } do
		if sword then
			for _, descendant in sword:GetDescendants() do
				if descendant:IsA("BasePart") then
					if self:_isBladePart(descendant) and descendant.Transparency < 1 then
						descendant.CanTouch = true
						descendant.CanQuery = false
						descendant.CanCollide = false
						descendant.CastShadow = false

						table.insert(bladeParts, descendant)
					elseif descendant.Name == "SwordHB" then
						descendant.Transparency = 1
						descendant.CanTouch = false
						descendant.CanQuery = false
						descendant.CanCollide = false
						descendant.CastShadow = false
					end
				end
			end
		end
	end

	return bladeParts
end

function GearService:_setServerSwordModelVisible(model, handlesVisible, bladesVisible)
	if not model then
		return
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CastShadow = false

			if self:_isBladePart(descendant) then
				descendant.Transparency = if bladesVisible then 0 else 1
				descendant.CanQuery = false
				descendant.CanTouch = bladesVisible
				continue
			end

			if descendant.Name == "SwordHB" then
				descendant.Transparency = 1
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				continue
			end

			descendant.Transparency = if handlesVisible then 0 else 1
			descendant.CanQuery = handlesVisible
			descendant.CanTouch = false
		end
	end
end

function GearService:_setServerHolsteredSwordVisible(model, visible)
	if not model then
		return
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = visible
			descendant.CanTouch = false
			descendant.CastShadow = false

			if descendant.Name == "SwordHB" then
				descendant.Transparency = 1
				descendant.CanQuery = false
				descendant.CanTouch = false
			else
				descendant.Transparency = if visible then 0 else 1
			end
		end
	end
end

function GearService:_setServerCordAttachmentsHolstered(character, isHolstered)
	local gear = character:FindFirstChild("Gear", true)
	if not gear then
		return
	end

	local hookShooters = gear:FindFirstChild("HookShooters", true)
	if not hookShooters then
		warn("[GearService] Could not find HookShooters for cord attachments.")
		return
	end

	local cordLeft = hookShooters:FindFirstChild("CordLeft", true)
	local cordRight = hookShooters:FindFirstChild("CordRight", true)

	if not cordLeft or not cordLeft:IsA("RopeConstraint") then
		warn("[GearService] Missing RopeConstraint: CordLeft")
		return
	end

	if not cordRight or not cordRight:IsA("RopeConstraint") then
		warn("[GearService] Missing RopeConstraint: CordRight")
		return
	end

	local leftSword = character:FindFirstChild("LeftSword", true)
	local rightSword = character:FindFirstChild("RightSword", true)
	local leftHolstered = character:FindFirstChild("LeftSwordHolstered", true)
	local rightHolstered = character:FindFirstChild("RightSwordHolstered", true)

	local leftTarget = nil
	local rightTarget = nil

	if isHolstered then
		leftTarget = self:_findCordAttachment(leftHolstered, {
			"CordEnd2",
			"CordEnd",
			"Attachment",
		})

		rightTarget = self:_findCordAttachment(rightHolstered, {
			"CordEnd2",
			"CordEnd",
			"Attachment",
		})
	else
		leftTarget = self:_findCordAttachment(leftSword, {
			"CordEnd2",
			"CordEnd",
			"Attachment",
		})

		rightTarget = self:_findCordAttachment(rightSword, {
			"CordEnd2",
			"CordEnd",
			"Attachment",
		})
	end

	if leftTarget then
		cordLeft.Attachment1 = leftTarget
	else
		warn("[GearService] Could not find left cord target. Holstered:", isHolstered)
	end

	if rightTarget then
		cordRight.Attachment1 = rightTarget
	else
		warn("[GearService] Could not find right cord target. Holstered:", isHolstered)
	end
end

function GearService:_applyServerGearVisibility(player)
	local character = player.Character
	if not character then
		return
	end

	local state = self:getState(player)

	local equipped = state.Equipped == true
	local handlesOut = equipped and state.HandlesOut == true
	local bladesOut = handlesOut and state.BladesOut == true

	local leftSword = character:FindFirstChild("LeftSword", true)
	local rightSword = character:FindFirstChild("RightSword", true)
	local leftHolstered = character:FindFirstChild("LeftSwordHolstered", true)
	local rightHolstered = character:FindFirstChild("RightSwordHolstered", true)

	self:_setServerSwordModelVisible(leftSword, handlesOut, bladesOut)
	self:_setServerSwordModelVisible(rightSword, handlesOut, bladesOut)

	self:_setServerHolsteredSwordVisible(leftHolstered, not handlesOut)
	self:_setServerHolsteredSwordVisible(rightHolstered, not handlesOut)

	if bladesOut then
		self:_applyBladeDurabilityVisuals(player)
	end

	self:_applyReserveBladeVisuals(player)
	self:_setServerCordAttachmentsHolstered(character, not handlesOut)
end

------------------------------------------------------------
-- Equip / Unequip
------------------------------------------------------------
-- Gear Instance Management
------------------------------------------------------------

-- Creates a server-side gear instance for validation and state access.
-- savedState carries current gas/blade state so the gear instance stays in sync.
function GearService:_createGearInstance(player, presetName, savedState)
	self:_destroyGearInstance(player)

	local ok, gear = pcall(function()
		return GearRegistry.create(presetName, player, savedState)
	end)

	if not ok then
		warn("[GearService] Failed to create gear instance for", player.Name, ":", gear)
		return nil
	end

	gear:equip()
	self._gearInstances[player] = gear
	return gear
end

function GearService:_destroyGearInstance(player)
	local existing = self._gearInstances[player]
	if existing then
		existing:destroy()
		self._gearInstances[player] = nil
	end
end

-- Returns the live gear instance, or nil if the player has no gear equipped.
function GearService:getGearInstance(player)
	return self._gearInstances[player]
end

------------------------------------------------------------

function GearService:equipGear(player, preset)
	local character = self:_getCharacter(player)
	if not character then
		return
	end

	local state = self:getState(player)
	local resolvedPreset = preset or self.Config.DefaultPreset

	state.Equipped = true
	state.HandlesOut = false
	state.BladesOut = false
	state.Preset = resolvedPreset

	-- Build the server-side gear instance. Pass current gas/blade state so the
	-- instance stays in sync with the flat _states table.
	local savedState = {
		gasLeft = state.GasLeft,
		gasRight = state.GasRight,
		bladeReserves = state.BladeReserves,
		leftBladeDurability = state.LeftBladeDurability,
		rightBladeDurability = state.RightBladeDurability,
		hasActivePair = state.HasActiveBladePair,
		activePairIndex = state.ActiveBladePairIndex,
	}
	self:_createGearInstance(player, resolvedPreset, savedState)

	self:endBladeSwing(player)
	self:_applyServerGearVisibility(player)
	self:_broadcastState(player)
	self:_broadcastResources(player)
end

function GearService:unequipGear(player)
	local state = self:getState(player)

	state.Equipped = false
	state.HandlesOut = false
	state.BladesOut = false

	self:_destroyGearInstance(player)
	self:endBladeSwing(player)
	self:_applyServerGearVisibility(player)
	self:_broadcastState(player)
	self:_broadcastResources(player)
end

function GearService:toggleHandles(player)
	local state = self:getState(player)

	if not state.Equipped then
		return
	end

	state.HandlesOut = not state.HandlesOut

	if not state.HandlesOut then
		state.BladesOut = false
		self:endBladeSwing(player)
	end

	self:_applyServerGearVisibility(player)
	self:_broadcastState(player)
	self:_broadcastResources(player)
end

function GearService:setBladesOut(player, bladesOut)
	local state = self:getState(player)

	if not state.Equipped or not state.HandlesOut then
		return
	end

	if bladesOut == true then
		if not state.HasActiveBladePair then
			local consumed = self:_consumeNewBladePair(player)

			if not consumed then
				self:_broadcastResources(player)
				self:_applyReserveBladeVisuals(player)
				return
			end
		end

		if state.LeftBladeDurability <= 0 and state.RightBladeDurability <= 0 then
			self:_clearActiveBladePair(player)
			self:_applyServerGearVisibility(player)
			self:_broadcastResources(player)
			self:_broadcastState(player)
			return
		end

		state.BladesOut = true
	else
		state.BladesOut = false
		self:endBladeSwing(player)
	end

	self:_applyServerGearVisibility(player)
	self:_applyBladeDurabilityVisuals(player)
	self:_broadcastResources(player)
	self:_broadcastState(player)
end

function GearService:dropBlades(player)
	local character = self:_getCharacter(player)
	if not character then
		return
	end

	local state = self:getState(player)

	if not state.Equipped or not state.HandlesOut or not state.BladesOut then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local rootPart = if root and root:IsA("BasePart") then root else nil

	for _, sword in { character:FindFirstChild("LeftSword"), character:FindFirstChild("RightSword") } do
		if sword then
			self:_spawnDroppedBlade(sword, rootPart)
		end
	end

	self:_clearActiveBladePair(player)

	self:endBladeSwing(player)
	self:_applyServerGearVisibility(player)

	if self.networker then
		self.networker:fireAll("gearBladeDrop", player)
	end

	self:_broadcastState(player)
	self:_broadcastResources(player)
end

------------------------------------------------------------
-- Titan Hitbox / Damage
------------------------------------------------------------

function GearService:_getHitboxDamageMultiplier(hitbox)
	local multiplier = hitbox:GetAttribute("DamageMultiplier")
	if typeof(multiplier) == "number" then
		return multiplier
	end

	local kind = string.lower(self:_getHitboxKind(hitbox))

	if kind == "nape" then
		return self.Config.NapeDamageMultiplier
	end

	if hitbox:GetAttribute("Armored") == true then
		return self.Config.ArmoredDamageMultiplier
	end

	return 1
end

function GearService:_getBladeHitKey(bladePart)
	local swordModel = bladePart:FindFirstAncestor("LeftSword") or bladePart:FindFirstAncestor("RightSword")

	if swordModel then
		return swordModel.Name
	end

	return "UnknownSword"
end


function GearService:_getBladeHitSpeed(player, _bladePart)
	local character = player.Character
	if not character then
		return 0
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return 0
	end

	return root.AssemblyLinearVelocity.Magnitude
end

function GearService:_calculateBladeDamage(player, bladePart, hitbox)
	local config = self.Config
	local speed = self:_getBladeHitSpeed(player, bladePart)

	if speed < config.MinimumHitSpeed then
		return 0, speed
	end

	local context = self:_getDamageContext(player, hitbox)

	local clampedSpeed = math.clamp(speed, config.MinimumHitSpeed, config.MaximumHitSpeed)
	local damage = clampedSpeed * config.DamagePerSpeed

	damage = math.clamp(damage, config.MinimumDamage, config.MaximumDamage)
	damage *= self:_getHitboxDamageMultiplier(hitbox)

	local bladeMultiplier = bladePart:GetAttribute("DamageMultiplier")
	if typeof(bladeMultiplier) == "number" then
		damage *= bladeMultiplier
	end

	damage = self:_applyTalentModifier(player, "Damage", damage, context)
	damage = self:_applyTalentModifier(player, "BladeDamage", damage, context)
	damage = self:_applyTalentModifier(player, "TitanDamage", damage, context)

	if context.HitNape then
		damage = self:_applyTalentModifier(player, "NapeDamage", damage, context)
	end

	if context.IsAirborne then
		damage = self:_applyTalentModifier(player, "AirborneDamage", damage, context)
	end

	local critChance = self:_getTalentPercent(player, "CritChance")
	if critChance > 0 and math.random() < critChance then
		damage *= self.Config.CritDamageMultiplier
		hitbox:SetAttribute("LastCrit", true)
	else
		hitbox:SetAttribute("LastCrit", false)
	end

	return damage, speed
end

------------------------------------------------------------
-- Swing Handling
------------------------------------------------------------

function GearService:_clearSwingConnections(player)
	local connections = self._activeSwingConnections[player]

	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end

	self._activeSwingConnections[player] = nil
end


function GearService:startBladeSwing(player)
	local config = self.Config

	local character = self:_getCharacter(player)
	if not character then
		return
	end

	local state = self:getState(player)
	if not state.Equipped or not state.HandlesOut or not state.BladesOut then
		return
	end

	if state.LeftBladeDurability <= 0 and state.RightBladeDurability <= 0 then
		return
	end

	self:_clearSwingConnections(player)
	self._hitThisSwing[player] = {}

	local bladeParts = self:_getActiveBladeParts(character)
	if #bladeParts == 0 then
		warn("[GearService] No SwordB blade parts found for", player.Name)
		return
	end

	self._activeSwingConnections[player] = {}
	player:SetAttribute("IsBladeSwinging", true)

	for _, bladePart in bladeParts do
		bladePart.CanTouch = true
		bladePart.CanQuery = false
		bladePart.CanCollide = false
	end
end

function GearService:releaseBladeSwing(player)
	self:endBladeSwing(player)
end

function GearService:endBladeSwing(player)
	self:_clearSwingConnections(player)
	self._hitThisSwing[player] = nil
	player:SetAttribute("IsBladeSwinging", false)

	if self.Config.DebugSwordHits then
		print("[GearService] Swing ended for", player.Name)
	end
end

------------------------------------------------------------
-- Client-force ODM activation through Networker
------------------------------------------------------------

function GearService:forceEquipClient(player, preset)
	if not player then
		return
	end

	local finalPreset = preset

	if typeof(finalPreset) ~= "string" or finalPreset == "" then
		finalPreset = self.Config.DefaultPreset or "Gen1Gear"
	end

	local character = player.Character
	if not character then
		return
	end

	if not character:FindFirstChild("Gear") then
		local General = require(ReplicatedStorage.Shared.Modules.General)
		General:EquipODM(player)
		task.wait(0.15)
	end

	self:equipGear(player, finalPreset)

	if self.networker then
		self.networker:fire(player, "forceEquipODM", finalPreset)
	end

	print("[GearService] Force equipped ODM for", player.Name, "Preset:", finalPreset)
end

function GearService:forceUnequipClient(player)
	self:unequipGear(player)

	if not self.networker then
		return
	end

	self.networker:fire(player, "forceUnequipODM")
end

function GearService:requestEquipODM(player, preset)
	self:forceEquipClient(player, preset or self.Config.DefaultPreset)
end

------------------------------------------------------------
-- Refill API
------------------------------------------------------------

function GearService:RefillGasSideFromSource(player, side, requestedAmount)
	local state = self:getState(player)

	requestedAmount = tonumber(requestedAmount) or 0
	if requestedAmount <= 0 then
		return 0
	end

	local stateKey, maxKey
	if side == "Right" then
		stateKey = "GasRight"
		maxKey = "MaxGasRight"
	else
		stateKey = "GasLeft"
		maxKey = "MaxGasLeft"
	end

	local missing = math.max(0, self.Config[maxKey] - state[stateKey])
	if missing <= 0 then
		self:_broadcastResources(player)
		return 0
	end

	local used = math.min(requestedAmount, missing)
	state[stateKey] = math.min(self.Config[maxKey], state[stateKey] + used)

	self:_broadcastResources(player)

	return used
end

function GearService:RefillGasFromSource(player, requestedAmount)
	local state = self:getState(player)

	requestedAmount = tonumber(requestedAmount) or 0
	if requestedAmount <= 0 then
		return 0
	end

	local maxLeft = self:_effectiveMaxGasLeft(player)
	local maxRight = self:_effectiveMaxGasRight(player)
	local leftMissing = math.max(0, maxLeft - state.GasLeft)
	local rightMissing = math.max(0, maxRight - state.GasRight)
	local totalMissing = leftMissing + rightMissing

	if totalMissing <= 0 then
		self:_broadcastResources(player)
		return 0
	end

	local amountToUse = math.min(requestedAmount, totalMissing)

	local leftAdd = math.min(leftMissing, amountToUse / 2)
	local rightAdd = math.min(rightMissing, amountToUse / 2)

	local remaining = amountToUse - leftAdd - rightAdd

	if remaining > 0 and leftMissing - leftAdd > 0 then
		local extra = math.min(leftMissing - leftAdd, remaining)
		leftAdd += extra
		remaining -= extra
	end

	if remaining > 0 and rightMissing - rightAdd > 0 then
		local extra = math.min(rightMissing - rightAdd, remaining)
		rightAdd += extra
		remaining -= extra
	end

	local used = leftAdd + rightAdd

	if used <= 0 then
		self:_broadcastResources(player)
		return 0
	end

	state.GasLeft = math.min(maxLeft, state.GasLeft + leftAdd)
	state.GasRight = math.min(maxRight, state.GasRight + rightAdd)

	self:_broadcastResources(player)

	return used
end

function GearService:RefillBladesFromSource(player, requestedAmount)
	local state = self:getState(player)

	requestedAmount = tonumber(requestedAmount) or 0
	requestedAmount = math.max(0, math.floor(requestedAmount))

	if requestedAmount <= 0 then
		return 0
	end

	local missing = math.max(0, self:_effectiveMaxBladeReserves(player) - state.BladeReserves)

	if missing <= 0 then
		self:_broadcastResources(player)
		return 0
	end

	local used = math.min(requestedAmount, missing)

	state.BladeReserves += used

	self:_applyReserveBladeVisuals(player)
	self:_broadcastResources(player)
	self:_broadcastState(player)

	return used
end

------------------------------------------------------------
-- Networked Client Methods
------------------------------------------------------------

function GearService:clientEquipGear(player, preset)
	self:equipGear(player, preset)
end

function GearService:clientUnequipGear(player)
	self:unequipGear(player)
end

function GearService:clientToggleHandles(player)
	self:toggleHandles(player)
end

function GearService:clientSetBladesOut(player, bladesOut)
	self:setBladesOut(player, bladesOut)
end

function GearService:clientDropBlades(player)
	self:dropBlades(player)
end

function GearService:clientBeginBladeSwing(player)
	self:startBladeSwing(player)
end

function GearService:clientReleaseBladeSwing(player)
	self:releaseBladeSwing(player)
end

function GearService:clientEndBladeSwing(player)
	self:endBladeSwing(player)
end

function GearService:clientConsumeGas(player, amount, tank)
	return self:_drainGas(player, amount, tank)
end

function GearService:clientCrossfeedGas(player, dt)
	self:_crossfeedGas(player, dt)
end

function GearService:clientRefillGas(player)
	local state = self:getState(player)

	state.GasLeft = self:_effectiveMaxGasLeft(player)
	state.GasRight = self:_effectiveMaxGasRight(player)

	self:_broadcastResources(player)
end

function GearService:clientRefillBlades(player)
	local state = self:getState(player)

	state.BladeReserves = self:_effectiveMaxBladeReserves(player)
	state.HasActiveBladePair = false
	state.ActiveBladePairIndex = nil
	state.LeftBladeDurability = 0
	state.RightBladeDurability = 0
	state.BladesOut = false

	self:_applyServerGearVisibility(player)
	self:_broadcastResources(player)
	self:_broadcastState(player)
end

------------------------------------------------------------
-- Dropped Blades
------------------------------------------------------------

function GearService:_spawnDroppedBlade(sword, root)
	local config = self.Config

	local droppedModel = Instance.new("Model")
	droppedModel.Name = sword.Name .. "_DroppedBlade"
	droppedModel.Parent = workspace

	local bladeRoot = nil
	local clonedParts = {}

	for _, part in sword:GetDescendants() do
		if part:IsA("BasePart") and self:_isBladePart(part) and part.Transparency < 1 then
			local clone = part:Clone()

			for _, child in clone:GetDescendants() do
				if
					child:IsA("Weld")
					or child:IsA("WeldConstraint")
					or child:IsA("Motor6D")
					or child:IsA("ManualWeld")
					or child:IsA("Snap")
				then
					child:Destroy()
				end
			end

			clone.Anchored = false
			clone.CanCollide = true
			clone.CanTouch = false
			clone.CanQuery = false
			clone.Massless = false
			clone.Transparency = 0
			clone.LocalTransparencyModifier = 0
			clone.CFrame = part.CFrame
			clone.Parent = droppedModel

			table.insert(clonedParts, clone)

			if not bladeRoot then
				bladeRoot = clone
				droppedModel.PrimaryPart = clone
			end
		end
	end

	if not bladeRoot then
		droppedModel:Destroy()
		return
	end

	for _, clone in clonedParts do
		if clone ~= bladeRoot then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = bladeRoot
			weld.Part1 = clone
			weld.Parent = bladeRoot
		end
	end

	local rootVelocity = if root then root.AssemblyLinearVelocity else Vector3.zero

	bladeRoot.AssemblyLinearVelocity = rootVelocity + Vector3.new(math.random(-4, 4), 8, math.random(-4, 4))
	bladeRoot.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))

	Debris:AddItem(droppedModel, config.BladeDropLifetime)
end

return GearService
