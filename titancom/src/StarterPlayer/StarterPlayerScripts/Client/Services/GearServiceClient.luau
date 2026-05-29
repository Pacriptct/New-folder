local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Networker = require(ReplicatedStorage.Packages.Networker)
local GearRegistry = require(ReplicatedStorage.Shared.Gear.GearRegistry)
local General = require(ReplicatedStorage.Shared.Modules.General)
local ManeuverModule = require(ReplicatedStorage.Shared.Modules.ManeuverModule)
local AnimationController = require(ReplicatedStorage.Shared.Modules.AnimationController)
local InputServiceClient = require(script.Parent.InputServiceClient)
local CameraServiceClient = require(script.Parent.CameraServiceClient)
local StateMachine = require(ReplicatedStorage.Shared.StateMachine)
local AudioGroups = require(ReplicatedStorage.Shared.Modules.AudioGroups)

local Remotes = ReplicatedStorage.Remotes

local GearServiceClient = {} :: any

local LocalPlayer = Players.LocalPlayer
local networker = Networker.client.new("GearService", GearServiceClient)
GearServiceClient._networker = networker

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local ODM_LAYER = "ODM"

local ANIMS = {
	GearIdle = "HandlesIdle",
	HookIdle = "HookIdle",
	LeftHookStart = "LHookStart",
	RightHookStart = "RHookStart",
	LeftHookIdle = "LHIdle",
	RightHookIdle = "RHIdle",
	DoubleHookStart = "DoubleHookStart",
	DoubleHookIdle = "DoubleHookIdle",
	LeftOrbitStart = "LOrbitStart",
	RightOrbitStart = "ROrbitStart",
	LeftOrbitIdle = "LOrbitIdle",
	RightOrbitIdle = "ROrbitIdle",
	GroundDrag = "Sliding",
	LeftWallRun = "WallRunLeft",
	RightWallRun = "WallRunRight",
	LeftGasCheck = "LeftGasCheck",
	RightGasCheck = "RightGasCheck",
	LeftSlice = "LeftSlice",
	RightSlice = "RightSlice",
	VerticalSlice = "VerticleSlice",
	HookFlip = "HookFlip",
	UnsheatheBlades = "UnsheatheBlades",
	SheatheBlades = "SheatheBlades",
}

local SLICE_ANIMS = { ANIMS.LeftSlice, ANIMS.RightSlice, ANIMS.VerticalSlice }

local ODM_ACTIVE_STATES = {
	"ODMHooking",
	"ODMOrbiting",
	"ODMGroundSliding",
	"ODMVDashing",
	"ODMWallRunning",
}

local CONFIG = {
	DefaultGearPreset = "Gen1Gear",

	GrappleDebounceTime = 0.25,
	AttackDebounceTime = 0.35,
	HeavyAttackDebounceTime = 0.65,
	GasCheckCooldown = 0.15,
	GearIdleMoveSpeedThreshold = 1.5,
	OrbitStartHoldTime = 0.18,
	RightBladeSheatheDelay = 0.12,
	HookAttachWaitTime = 0.35,
	ReloadHoldTime = 0.28,
	BladeDropLifetime = 8,

	WallRunCheckDistance = 5.5,
	WallRunMinSpeed = 24,
	WallRunGroundGraceTime = 0.18,
	WallRunLostWallGraceTime = 0.16,

	HookShotGasCost = 0.25,
	MinimumBoostGas = 1,
	BoostGasCostPerSecond = 7,
	GasDrainTick = 0.15,
	GasCrossfeedTick = 0.5,
	VDashGasCost = 18,
	VDashAttachGraceTime = 0.2,

	SoundCooldowns = {
		Shot = 0.08,
		Retract = 0.1,
		GasBurst = 0.06,
		Dash = 0.12,
		Orbit = 0.12,
		OrbitBurst = 0.12,
		Holster = 0.14,
		HolsterOut = 0.14,
		Unsheathe = 0.14,
		Sheathe = 0.14,
		Tap = 0.035,
	},
}

------------------------------------------------------------
-- State
------------------------------------------------------------

-- Gear lifecycle
GearServiceClient._initialized = false
GearServiceClient._gearInstance = nil
GearServiceClient._maneuver = nil
GearServiceClient._character = nil :: Model?
GearServiceClient._rootPart = nil :: BasePart?
GearServiceClient._equipped = false
GearServiceClient._handlesOut = false
GearServiceClient._bladesOut = false
GearServiceClient._loadoutPreset = nil
GearServiceClient._runtimeConnection = nil :: RBXScriptConnection?
GearServiceClient._characterConnection = nil

-- Resources (kept in sync with server broadcasts)
GearServiceClient.Resources = {
	GasLeft = 100,
	GasRight = 100,
	MaxGasLeft = 100,
	MaxGasRight = 100,
	BladeReserves = 4,
	MaxBladeReserves = 4,
	LeftBladeDurability = 0,
	RightBladeDurability = 0,
	MaxBladeDurability = 5,
	HasActiveBladePair = false,
	ActiveBladePairIndex = nil,
}

-- Gear condition / talent multipliers
GearServiceClient.ConditionMultipliers = {
	MaxSpeedMultiplier = 1,
	AccelerationMultiplier = 1,
	GasEfficiency = 1,
	HookRangeMultiplier = 1,
	DamageMultiplier = 1,
}
GearServiceClient.Modifiers = { Flat = {}, Percent = {}, Passive = {}, Conditional = {}, Stack = {}, Counter = {} }
GearServiceClient.StatMultipliers = {
	GasConsumption = 1,
	HookSpeed = 1,
	HookRange = 1,
	ODMStats = 1,
	BladeDamage = 1,
	TitanDamage = 1,
	Damage = 1,
	CritChance = 1,
	MoveSpeed = 1,
	StaminaRegen = 1,
	MaxHP = 1,
}
GearServiceClient._gearCondition = nil
GearServiceClient._talentModifierUnsub = nil

-- Input state
GearServiceClient._hookLeftHeld = false
GearServiceClient._hookRightHeld = false
GearServiceClient._orbitLeftHeld = false
GearServiceClient._orbitRightHeld = false
GearServiceClient._boostHeld = false
GearServiceClient._executeHeld = false
GearServiceClient._executePressedAt = 0
GearServiceClient._vDashAttemptId = 0
GearServiceClient._reloadHeld = false
GearServiceClient._reloadPressTime = 0
GearServiceClient._grappleDebounce = { Left = false, Right = false }
GearServiceClient._attackDebounce = false
GearServiceClient._heavyAttackDebounce = false
GearServiceClient._isSwinging = false
GearServiceClient._attackHeld = false
GearServiceClient._heldAttackTrack = nil
GearServiceClient._heldAttackRelease = nil
GearServiceClient._disconnectors = {}

-- Animation / sound / VFX
GearServiceClient._currentLoopAnimation = nil :: string?
GearServiceClient._gasCheckDebounce = false
GearServiceClient._gasCheckSequenceId = 0
GearServiceClient._lastSliceName = nil :: string?
GearServiceClient._orbitStartPlayingUntil = 0
GearServiceClient._gasDrainAccumulator = 0
GearServiceClient._gasCrossfeedAccumulator = 0
GearServiceClient._slashSoundIndex = 0
GearServiceClient._gearSounds = {}
GearServiceClient._lastSoundPlayedAt = {}

-- Wall run
GearServiceClient._wallRunSide = nil
GearServiceClient._odmWallRunActive = false
GearServiceClient._lastWallRunWallTime = 0
GearServiceClient._lastWallRunAirTime = 0

-- Speed lines
GearServiceClient._speedLinesGui = nil :: ScreenGui?
GearServiceClient._speedLinesFrame = nil :: Frame?
GearServiceClient._speedLineTemplate = nil :: Frame?
GearServiceClient._speedLineCooldown = false

------------------------------------------------------------
-- Talent / Modifier Helpers
------------------------------------------------------------

function GearServiceClient:_applyConditionMultipliers()
	local c = self.ConditionMultipliers
	self.StatMultipliers.ODMStats *= c.MaxSpeedMultiplier or 1
	self.StatMultipliers.HookSpeed *= c.AccelerationMultiplier or 1
	self.StatMultipliers.HookRange *= c.HookRangeMultiplier or 1
	self.StatMultipliers.GasConsumption *= 1 / math.max(c.GasEfficiency or 1, 0.01)
	self.StatMultipliers.BladeDamage *= c.DamageMultiplier or 1
	self.StatMultipliers.Damage *= c.DamageMultiplier or 1
end

function GearServiceClient:_resetStatMultipliers()
	self.StatMultipliers = {
		GasConsumption = 1,
		HookSpeed = 1,
		HookRange = 1,
		ODMStats = 1,
		BladeDamage = 1,
		TitanDamage = 1,
		Damage = 1,
		CritChance = 1,
		MoveSpeed = 1,
		StaminaRegen = 1,
		MaxHP = 1,
	}
	self:_applyConditionMultipliers()
end

function GearServiceClient:_normalizeTalentModifiers(modifiers)
	if type(modifiers) ~= "table" then
		return { Flat = {}, Percent = {}, Passive = {}, Conditional = {}, Stack = {}, Counter = {} }
	end
	for _, key in { "Flat", "Percent", "Passive", "Conditional", "Stack", "Counter" } do
		if type(modifiers[key]) ~= "table" then
			modifiers[key] = {}
		end
	end
	return modifiers
end

function GearServiceClient:_rebuildStatMultipliers()
	self:_resetStatMultipliers()
	local modifiers = self:_normalizeTalentModifiers(self.Modifiers)
	self.Modifiers = modifiers
	for target, value in pairs(modifiers.Percent) do
		if type(target) == "string" and type(value) == "number" then
			local current = self.StatMultipliers[target]
			if type(current) == "number" then
				self.StatMultipliers[target] = current * (1 + value)
			end
		end
	end
end

function GearServiceClient:talentModifiersUpdated(modifiers: any)
	self.Modifiers = self:_normalizeTalentModifiers(modifiers)
	self:_rebuildStatMultipliers()
	if self._maneuver and self._maneuver.SetStatMultipliers then
		self._maneuver:SetStatMultipliers(self:getODMMultipliers())
	end
end

function GearServiceClient:getTalentModifiers()
	return self.Modifiers
end

function GearServiceClient:getStatMultiplier(target: string): number
	local value = self.StatMultipliers[type(target) == "string" and target or ""]
	return type(value) == "number" and value or 1
end

function GearServiceClient:getFlatModifier(target: string): number
	local value = self:_normalizeTalentModifiers(self.Modifiers).Flat[target]
	return type(value) == "number" and value or 0
end

function GearServiceClient:hasPassive(name: string): boolean
	return self:_normalizeTalentModifiers(self.Modifiers).Passive[name] == true
end

function GearServiceClient:getGasCost(baseCost: number): number
	baseCost = tonumber(baseCost) or 0
	if baseCost <= 0 or self:hasPassive("UnlimitedGas") then
		return 0
	end
	return baseCost * self:getStatMultiplier("GasConsumption")
end

function GearServiceClient:getODMMultipliers()
	return {
		ODMStats = self:getStatMultiplier("ODMStats"),
		HookSpeed = self:getStatMultiplier("HookSpeed"),
		HookRange = self:getStatMultiplier("HookRange"),
		BladeDamage = self:getStatMultiplier("BladeDamage"),
		GasConsumption = self:getStatMultiplier("GasConsumption"),
	}
end

function GearServiceClient:applyBladeDamageMultiplier(baseDamage: number): number
	return (tonumber(baseDamage) or 0) * self:getStatMultiplier("BladeDamage")
end

function GearServiceClient:RefreshGearModifiers()
	if self._maneuver and self._maneuver.SetStatMultipliers then
		self._maneuver:SetStatMultipliers(self:getODMMultipliers())
	end
end

function GearServiceClient:_bindTalentServiceClient()
	local module = script.Parent:FindFirstChild("TalentServiceClient")
	if not module or not module:IsA("ModuleScript") then
		return
	end
	local ok, svc = pcall(require, module)
	if not ok or type(svc) ~= "table" then
		return
	end

	if svc.GetModifiers then
		local m = svc:GetModifiers()
		if type(m) == "table" then
			self:talentModifiersUpdated(m)
		end
	end

	if svc.onModifiersUpdated then
		if self._talentModifierUnsub then
			self._talentModifierUnsub()
		end
		self._talentModifierUnsub = svc:onModifiersUpdated(function(m)
			self:talentModifiersUpdated(m)
		end)
	end
end

------------------------------------------------------------
-- Resource API
------------------------------------------------------------

function GearServiceClient:hasGas(amount: number, tank: string): boolean
	local r = self.Resources
	amount = tonumber(amount) or 0
	if amount <= 0 then
		return true
	end
	if tank == "Left" then
		return r.GasLeft >= amount
	end
	if tank == "Right" then
		return r.GasRight >= amount
	end
	return r.GasLeft >= amount / 2 and r.GasRight >= amount / 2
end

function GearServiceClient:hasBoostGas(amount: number?): boolean
	return self:hasGas(amount or 1, "Both")
end

function GearServiceClient:isOutOfGas(): boolean
	return (self.Resources.GasLeft or 0) <= 0 and (self.Resources.GasRight or 0) <= 0
end

function GearServiceClient:hasBladeReserve(): boolean
	return self.Resources.HasActiveBladePair == true or self.Resources.BladeReserves > 0
end

function GearServiceClient:hasUsableBlade(): boolean
	return self.Resources.HasActiveBladePair == true
		and (self.Resources.LeftBladeDurability > 0 or self.Resources.RightBladeDurability > 0)
end

function GearServiceClient:getResources()
	return self.Resources
end

------------------------------------------------------------
-- Gear Instance
------------------------------------------------------------

function GearServiceClient:_createGearInstance(presetName: string)
	if self._gearInstance then
		self._gearInstance:destroy()
		self._gearInstance = nil
	end
	local r = self.Resources
	local ok, gear = pcall(GearRegistry.create, presetName or "Gen1Gear", LocalPlayer, {
		gasLeft = r.GasLeft,
		gasRight = r.GasRight,
		bladeReserves = r.BladeReserves,
		leftBladeDurability = r.LeftBladeDurability,
		rightBladeDurability = r.RightBladeDurability,
		hasActivePair = r.HasActiveBladePair,
		activePairIndex = r.ActiveBladePairIndex,
	})
	if ok then
		gear:equip()
		self._gearInstance = gear
	else
		warn("[GearServiceClient] Failed to create gear instance:", gear)
	end
end

function GearServiceClient:getGearInstance()
	return self._gearInstance
end

------------------------------------------------------------
-- Physics (ManeuverModule)
------------------------------------------------------------

function GearServiceClient:_createManeuver(character: Model, presetName: string)
	if self._maneuver then
		self._maneuver:Destroy()
		self._maneuver = nil
	end
	self._maneuver = ManeuverModule.new(character, presetName, CameraServiceClient)
	self:RefreshGearModifiers()
end

function GearServiceClient:SetGearPreset(name: string)
	self._loadoutPreset = name
	if self._maneuver then
		self._maneuver:ApplyPreset(name)
		self:RefreshGearModifiers()
	end
	if self._gearInstance and self._gearInstance.Mobility then
		self._gearInstance.Mobility:setPreset(name)
	end
	if self._equipped then
		networker:fire("clientEquipGear", name)
	end
end

function GearServiceClient:GetGearPreset(): string
	return self._loadoutPreset or CONFIG.DefaultGearPreset
end

function GearServiceClient:GetManeuver()
	return self._maneuver
end

function GearServiceClient:IsEquipped(): boolean
	return self._equipped == true
end

function GearServiceClient:IsActivelyUsingODM(): boolean
	return StateMachine.GetState(LocalPlayer, "ODMActive") == true
end

------------------------------------------------------------
-- Animation
------------------------------------------------------------

local function _getODMAnimationsFolder(): Folder?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local animations = assets and assets:FindFirstChild("Animations")
	local odm = animations and animations:FindFirstChild("ODM")
	return odm and odm:IsA("Folder") and odm or nil
end

local function _odmGroupResolver(key: string): string
	if key == ANIMS.GearIdle then
		return "Idle"
	end
	if
		key == ANIMS.HookIdle
		or key == ANIMS.LeftHookIdle
		or key == ANIMS.RightHookIdle
		or key == ANIMS.DoubleHookIdle
		or key == ANIMS.LeftOrbitIdle
		or key == ANIMS.RightOrbitIdle
		or key == ANIMS.GroundDrag
		or key == ANIMS.LeftWallRun
		or key == ANIMS.RightWallRun
	then
		return "Loop"
	end
	if
		key == ANIMS.LeftSlice
		or key == ANIMS.RightSlice
		or key == ANIMS.VerticalSlice
		or key == ANIMS.LeftGasCheck
		or key == ANIMS.RightGasCheck
		or key == ANIMS.UnsheatheBlades
		or key == ANIMS.SheatheBlades
	then
		return "Action"
	end
	return "OneShot"
end

function GearServiceClient:_loadODMAnimations()
	local character = self._character or LocalPlayer.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local folder = _getODMAnimationsFolder()
	if not folder then
		warn("[GearServiceClient] Missing ReplicatedStorage.Assets.Animations.ODM")
		return
	end
	AnimationController:LoadLayer(ODM_LAYER, animator, folder, _odmGroupResolver)
end

function GearServiceClient:_playAnimation(name: string, options: any?)
	local track = AnimationController:GetTrack(ODM_LAYER, name)
	if not track then
		self:_loadODMAnimations()
		track = AnimationController:GetTrack(ODM_LAYER, name)
	end
	if not track then
		warn("[GearServiceClient] Missing ODM animation:", name)
		return nil
	end
	return AnimationController:Play(ODM_LAYER, name, options or {})
end

function GearServiceClient:_stopAnimation(name: string, fadeTime: number?)
	AnimationController:Stop(ODM_LAYER, name, fadeTime or 0.15)
end

function GearServiceClient:_playOneShot(name: string)
	local track = self:_playAnimation(name, {
		Restart = true,
		FadeTime = 0.04,
		Weight = 1,
		Speed = 1,
		Priority = Enum.AnimationPriority.Action,
	})
	if track then
		track.Looped = false
	end
	return track
end

function GearServiceClient:_stopAllODMAnimations()
	AnimationController:StopLayer(ODM_LAYER, 0.1)
	self._currentLoopAnimation = nil
end

function GearServiceClient:_setLoopAnimation(name: string?)
	local fadeTime = 0.18
	if self._currentLoopAnimation == name then
		return name and AnimationController:GetTrack(ODM_LAYER, name) or nil
	end

	local previous = self._currentLoopAnimation
	self._currentLoopAnimation = name
	if previous then
		AnimationController:Stop(ODM_LAYER, previous, fadeTime)
	end
	if not name then
		return nil
	end

	local priority = Enum.AnimationPriority.Action
	local weight = 1
	if name == ANIMS.GearIdle then
		priority, weight = Enum.AnimationPriority.Idle, 0.35
	elseif name == ANIMS.DoubleHookIdle or name == ANIMS.LeftOrbitIdle or name == ANIMS.RightOrbitIdle then
		priority = Enum.AnimationPriority.Action2
	elseif name == ANIMS.GroundDrag or name == ANIMS.LeftWallRun or name == ANIMS.RightWallRun then
		priority = Enum.AnimationPriority.Action3
	end

	local track = self:_playAnimation(name, {
		Restart = false,
		FadeTime = fadeTime,
		Weight = weight,
		Speed = 1,
		Priority = priority,
	})
	if track then
		track.Looped = true
	end
	return track
end

function GearServiceClient:_refreshODMAnimations()
	if not self._equipped or not self._handlesOut then
		self:_setLoopAnimation(nil)
		self:_setActiveODMState(nil)
		return
	end

	self:_syncPassiveODMStates()

	if
		StateMachine.GetState(LocalPlayer, "ODMHolstering") == true
		or StateMachine.GetState(LocalPlayer, "ODMUnholstering") == true
	then
		return
	end

	local m = self._maneuver
	local isHooking = m and m:IsHooking()
	local isDoubleHooking = m and m:IsDoubleHooking()
	local isGroundSliding = m and m.IsGroundSliding and m:IsGroundSliding()
	local isVDashing = m and m.IsVDashing and m:IsVDashing()

	if self._odmWallRunActive and self._wallRunSide then
		self:_setActiveODMState("ODMWallRunning")
		self:_setLoopAnimation(self._wallRunSide == "Left" and ANIMS.LeftWallRun or ANIMS.RightWallRun)
		return
	end

	if isVDashing then
		self:_setActiveODMState("ODMVDashing")
		self:_setLoopAnimation(if self._bladesOut then nil else ANIMS.DoubleHookIdle)
		return
	end

	if isGroundSliding then
		self:_setActiveODMState("ODMGroundSliding")
		self:_setLoopAnimation(ANIMS.GroundDrag)
		return
	end

	if isHooking then
		local activeState = (self._orbitLeftHeld or self._orbitRightHeld) and "ODMOrbiting" or "ODMHooking"
		self:_setActiveODMState(activeState)

		if os.clock() < self._orbitStartPlayingUntil then
			return
		end
		if m and m.IsSlidingOnGround and m:IsSlidingOnGround() then
			self:_setLoopAnimation(ANIMS.GroundDrag)
			return
		end
		if self._orbitLeftHeld then
			self:_setLoopAnimation(ANIMS.LeftOrbitIdle)
			return
		end
		if self._orbitRightHeld then
			self:_setLoopAnimation(ANIMS.RightOrbitIdle)
			return
		end
		if isDoubleHooking then
			self:_setLoopAnimation(ANIMS.DoubleHookIdle)
			return
		end
		if self._hookLeftHeld then
			self:_setLoopAnimation(ANIMS.LeftHookIdle)
			return
		end
		if self._hookRightHeld then
			self:_setLoopAnimation(ANIMS.RightHookIdle)
			return
		end
		self:_setLoopAnimation(ANIMS.HookIdle)
		return
	end

	self:_setActiveODMState(nil)
	local track = self:_setLoopAnimation(ANIMS.GearIdle)
	if track then
		track:AdjustWeight(0.35, 0.15)
	end
end

function GearServiceClient:_getRandomSliceAnimation(): string
	local candidates = {}
	for _, name in SLICE_ANIMS do
		if name ~= self._lastSliceName then
			table.insert(candidates, name)
		end
	end
	if #candidates == 0 then
		candidates = SLICE_ANIMS
	end
	local selected = candidates[math.random(1, #candidates)]
	self._lastSliceName = selected
	return selected
end

------------------------------------------------------------
-- Sound
------------------------------------------------------------

function GearServiceClient:_getGasPart(): Instance?
	local character = self._character or LocalPlayer.Character
	if not character then
		return nil
	end
	local gear = character:FindFirstChild("Gear", true)
	return gear and gear:FindFirstChild("GasPart", true) or nil
end

function GearServiceClient:_cacheGearSounds()
	table.clear(self._gearSounds)
	table.clear(self._lastSoundPlayedAt)
	local gasPart = self:_getGasPart()
	if not gasPart then
		warn("[GearServiceClient] Missing GasPart for gear sounds.")
		return
	end
	for _, child in gasPart:GetChildren() do
		if child:IsA("Sound") and string.find(child.Name, "_Pool_") then
			child:Destroy()
		end
	end
	for _, child in gasPart:GetChildren() do
		if child:IsA("Sound") then
			AudioGroups.assign(child, "SFX")
			self._gearSounds[child.Name] = child
		end
	end
end

function GearServiceClient:_playGearSound(name: string, speed: number?)
	local sound = self._gearSounds[name]
	if not sound then
		return
	end
	local cooldown = CONFIG.SoundCooldowns[name]
	if cooldown then
		local now = os.clock()
		local last = self._lastSoundPlayedAt[name] or 0
		if now - last < cooldown then
			return
		end
		self._lastSoundPlayedAt[name] = now
	end
	if sound.IsPlaying then
		sound:Stop()
	end
	sound.Looped = false
	sound.PlaybackSpeed = speed or 1
	sound.TimePosition = 0
	sound:Play()
end

function GearServiceClient:_stopGearSound(name: string)
	local sound = self._gearSounds[name]
	if sound and sound.IsPlaying then
		sound:Stop()
	end
end

function GearServiceClient:_setGearLoopSound(name: string, enabled: boolean)
	local sound = self._gearSounds[name]
	if not sound then
		return
	end
	sound.Looped = true
	if enabled then
		if not sound.IsPlaying then
			sound.TimePosition = 0
			sound:Play()
		end
	else
		if sound.IsPlaying then
			sound:Stop()
		end
	end
end

function GearServiceClient:_playRandomSlashSound()
	self._slashSoundIndex = (self._slashSoundIndex % 4) + 1
	self:_playGearSound("Slash" .. tostring(self._slashSoundIndex))
end

function GearServiceClient:_getGasCheckTapPitch(): number
	local r = self.Resources
	local leftPct = (r.GasLeft or 0) / math.max(r.MaxGasLeft or 100, 1)
	local rightPct = (r.GasRight or 0) / math.max(r.MaxGasRight or 100, 1)
	return 0.72 + math.clamp((leftPct + rightPct) / 2, 0, 1) * 0.55
end

function GearServiceClient:_connectGasCheckTapSound(track, tapPitch: number)
	if not track then
		return nil
	end
	return track:GetMarkerReachedSignal("TankHit"):Connect(function()
		self:_playGearSound("Tap", tapPitch)
	end)
end

function GearServiceClient:_playGasCheckSequence(tapPitch: number)
	if self._gasCheckDebounce or not self:_canUseODM() then
		return
	end
	self._gasCheckDebounce = true
	self._gasCheckSequenceId += 1
	local sequenceId = self._gasCheckSequenceId

	task.spawn(function()
		local ok, err = pcall(function()
			self:_stopAnimation(ANIMS.RightGasCheck, 0.05)
			self:_stopAnimation(ANIMS.LeftGasCheck, 0.05)

			local rightTrack = self:_playOneShot(ANIMS.RightGasCheck)
			local rightConn = self:_connectGasCheckTapSound(rightTrack, tapPitch)
			if rightTrack then
				rightTrack.Stopped:Wait()
			else
				self:_playGearSound("Tap", tapPitch)
			end
			if rightConn then
				rightConn:Disconnect()
			end
			if sequenceId ~= self._gasCheckSequenceId or not self:_canUseODM() then
				return
			end

			local leftTrack = self:_playOneShot(ANIMS.LeftGasCheck)
			local leftConn = self:_connectGasCheckTapSound(leftTrack, tapPitch)
			if leftTrack then
				leftTrack.Stopped:Wait()
			else
				self:_playGearSound("Tap", tapPitch)
			end
			if leftConn then
				leftConn:Disconnect()
			end
		end)
		if not ok then
			warn("[GearServiceClient] Gas check sequence error:", err)
		end
		if sequenceId == self._gasCheckSequenceId then
			task.delay(CONFIG.GasCheckCooldown, function()
				if sequenceId == self._gasCheckSequenceId then
					self._gasCheckDebounce = false
				end
			end)
		end
	end)
end

------------------------------------------------------------
-- Visibility
------------------------------------------------------------

local function _isBladePart(part: Instance): boolean
	return part:IsA("BasePart") and string.match(part.Name, "^SwordB%d+$") ~= nil
end

function GearServiceClient:_getGearModels()
	local character = self._character
	if not character then
		return nil, nil, nil, nil
	end
	return character:FindFirstChild("LeftSword", true),
	character:FindFirstChild("RightSword", true),
	character:FindFirstChild("LeftSwordHolstered", true),
	character:FindFirstChild("RightSwordHolstered", true)
end

function GearServiceClient:_findCordAttachment(model: Instance?, preferred: { string }): Attachment?
	if not model then
		return nil
	end
	for _, name in preferred do
		local found = model:FindFirstChild(name, true)
		if found and found:IsA("Attachment") then
			return found
		end
	end
	for _, desc in model:GetDescendants() do
		if desc:IsA("Attachment") then
			local lower = string.lower(desc.Name)
			if string.find(lower, "cord") or string.find(lower, "wire") or string.find(lower, "attach") then
				return desc
			end
		end
	end
	return nil
end

function GearServiceClient:_setSwordModelVisible(model: Instance?, handles: boolean, blades: boolean?)
	if not model then
		return
	end
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.CastShadow = false
			if _isBladePart(desc) then
				desc.Transparency = blades and 0 or 1
				desc.LocalTransparencyModifier = blades and 0 or 1
				desc.CanQuery = true
				desc.CanTouch = true
			elseif desc.Name == "SwordHB" then
				desc.Transparency = 1
				desc.LocalTransparencyModifier = 1
				desc.CanQuery = false
				desc.CanTouch = false
			else
				desc.Transparency = handles and 0 or 1
				desc.LocalTransparencyModifier = 0
			end
		end
	end
end

function GearServiceClient:_setBladeSideVisible(side: string, visible: boolean)
	local leftSword, rightSword = self:_getGearModels()
	local sword = side == "Left" and leftSword or rightSword
	if not sword then
		return
	end
	for _, desc in sword:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.CastShadow = false
			if _isBladePart(desc) then
				desc.Transparency = visible and 0 or 1
				desc.LocalTransparencyModifier = visible and 0 or 1
				desc.CanQuery = true
				desc.CanTouch = true
			elseif desc.Name == "SwordHB" then
				desc.Transparency = 1
				desc.LocalTransparencyModifier = 1
				desc.CanQuery = false
				desc.CanTouch = false
			end
		end
	end
end

function GearServiceClient:_applyGearVisibility()
	local l, r, lh, rh = self:_getGearModels()
	local handles = self._handlesOut == true
	local blades = handles and self._bladesOut == true
	self:_setSwordModelVisible(l, handles, blades)
	self:_setSwordModelVisible(r, handles, blades)
	self:_setSwordModelVisible(lh, not handles, not handles)
	self:_setSwordModelVisible(rh, not handles, not handles)
end

function GearServiceClient:_setCordAttachmentsHolstered(isHolstered: boolean)
	local character = self._character
	if not character then
		return
	end
	local gear = character:FindFirstChild("Gear", true)
	local hookShooters = gear and gear:FindFirstChild("HookShooters", true)
	if not hookShooters then
		return
	end

	local cordLeft = hookShooters:FindFirstChild("CordLeft", true)
	local cordRight = hookShooters:FindFirstChild("CordRight", true)
	if not cordLeft or not cordLeft:IsA("RopeConstraint") then
		return
	end
	if not cordRight or not cordRight:IsA("RopeConstraint") then
		return
	end

	local l, r, lh, rh = self:_getGearModels()
	local preferred = { "CordEnd2", "CordEnd", "Attachment" }
	local leftTarget = self:_findCordAttachment(isHolstered and lh or l, preferred)
	local rightTarget = self:_findCordAttachment(isHolstered and rh or r, preferred)
	if leftTarget then
		cordLeft.Attachment1 = leftTarget
	end
	if rightTarget then
		cordRight.Attachment1 = rightTarget
	end
end

function GearServiceClient:_setScabbardVFXEnabled(side: string, enabled: boolean)
	local character = self._character
	if not character then
		return
	end
	local gear = character:FindFirstChild("Gear", true)
	if not gear then
		return
	end
	local names = {}
	if side == "Left" or side == "Both" then
		table.insert(names, "LeftScabbard")
	end
	if side == "Right" or side == "Both" then
		table.insert(names, "RightScabbard")
	end
	for _, scabbardName in names do
		local scabbard = gear:FindFirstChild(scabbardName, true)
		if scabbard then
			for _, desc in scabbard:GetDescendants() do
				if desc:IsA("ParticleEmitter") and (desc.Name == "Core" or desc.Name == "CoreMiniSparks") then
					desc.Enabled = enabled
				end
			end
		end
	end
end

-- Called for OTHER players' characters from gearState broadcasts.
local function _applyRemoteGearVisibility(character: Model, equipped: boolean, handlesOut: boolean, bladesOut: boolean)
	local function findModel(name)
		return character:FindFirstChild(name, true)
	end
	local l, r, lh, rh =
		findModel("LeftSword"),
	findModel("RightSword"),
	findModel("LeftSwordHolstered"),
	findModel("RightSwordHolstered")

	local function setModel(model, handles, blades)
		if not model then
			return
		end
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.CanCollide = false
				desc.CastShadow = false
				if _isBladePart(desc) then
					desc.Transparency = blades and 0 or 1
					desc.LocalTransparencyModifier = blades and 0 or 1
					desc.CanQuery = false
					desc.CanTouch = blades == true
				elseif desc.Name == "SwordHB" then
					desc.Transparency = 1
					desc.CanQuery = false
					desc.CanTouch = false
				else
					desc.Transparency = handles and 0 or 1
				end
			end
		end
	end

	if not equipped then
		setModel(l, false, false)
		setModel(r, false, false)
		setModel(lh, true, true)
		setModel(rh, true, true)
		return
	end
	setModel(l, handlesOut, handlesOut and bladesOut)
	setModel(r, handlesOut, handlesOut and bladesOut)
	setModel(lh, not handlesOut, not handlesOut)
	setModel(rh, not handlesOut, not handlesOut)
end

------------------------------------------------------------
-- ODM State Machine
------------------------------------------------------------

function GearServiceClient:_clearActiveODMStates()
	for _, key in ODM_ACTIVE_STATES do
		StateMachine.RemoveStates(LocalPlayer, key)
	end
	StateMachine.RemoveStates(LocalPlayer, "ODMActive")
end

function GearServiceClient:_setActiveODMState(activeKey: string?)
	self:_clearActiveODMStates()
	if activeKey then
		StateMachine.SetState(LocalPlayer, "ODMActive", true)
		StateMachine.SetState(LocalPlayer, activeKey, true)
	end
	local character = LocalPlayer.Character
	if character then
		character:SetAttribute("ODMEquipped", self._equipped == true)
		character:SetAttribute("ODMHandlesOut", self._handlesOut == true)
		character:SetAttribute("ODMBladesOut", self._bladesOut == true)
		character:SetAttribute("ODMState", activeKey or (self._handlesOut and "ODMIdle" or "Movement"))
	end
end

function GearServiceClient:_syncPassiveODMStates()
	StateMachine.SetState(LocalPlayer, "ODMEquipped", self._equipped == true)
	StateMachine.SetState(LocalPlayer, "ODMHandlesOut", self._handlesOut == true)
	StateMachine.SetState(LocalPlayer, "ODMBladesOut", self._bladesOut == true)
	local character = LocalPlayer.Character
	if character then
		character:SetAttribute("ODMEquipped", self._equipped == true)
		character:SetAttribute("ODMHandlesOut", self._handlesOut == true)
		character:SetAttribute("ODMBladesOut", self._bladesOut == true)
	end
end

------------------------------------------------------------
-- Gas Usage (per-frame drain / crossfeed)
------------------------------------------------------------

function GearServiceClient:_hasEnoughBoostGas(): boolean
	return self:hasGas(self:getGasCost(CONFIG.MinimumBoostGas), "Both")
end

function GearServiceClient:_setBoostAllowed(allowed: boolean)
	if self._maneuver and self._maneuver.SetBoostAllowed then
		self._maneuver:SetBoostAllowed(allowed)
	end
end

function GearServiceClient:_setOutOfGasSwinging(enabled: boolean)
	if self._maneuver and self._maneuver.SetOutOfGasSwinging then
		self._maneuver:SetOutOfGasSwinging(enabled)
	end
end

function GearServiceClient:_updateGasUsage(dt: number)
	if not self._equipped or not self._handlesOut or not self._maneuver then
		self:_setGearLoopSound("GasHiss", false)
		return
	end

	self._gasCrossfeedAccumulator += dt
	if self._gasCrossfeedAccumulator >= CONFIG.GasCrossfeedTick then
		networker:fire("clientCrossfeedGas", self._gasCrossfeedAccumulator)
		self._gasCrossfeedAccumulator = 0
	end

	local isHooking = self._maneuver:IsHooking()
	local isOutOfGasSwinging = self._maneuver.IsOutOfGasSwinging and self._maneuver:IsOutOfGasSwinging()
	self:_setGearLoopSound("GasHiss", isHooking == true and not isOutOfGasSwinging)

	if not isHooking then
		self:_setOutOfGasSwinging(false)
		self:_setBoostAllowed(self:_hasEnoughBoostGas())
		return
	end

	if not self._boostHeld then
		self:_setBoostAllowed(self:_hasEnoughBoostGas())
		return
	end

	self._gasDrainAccumulator += dt
	if self._gasDrainAccumulator < CONFIG.GasDrainTick then
		return
	end

	local drainAmount = self:getGasCost(CONFIG.BoostGasCostPerSecond * self._gasDrainAccumulator)
	if not self:hasGas(drainAmount, "Both") then
		self._boostHeld = false
		self:_setBoostAllowed(false)
		self._maneuver:SetBoost(false)
		self:_setOutOfGasSwinging(true)
		self:_refreshODMAnimations()
		return
	end

	networker:fire("clientConsumeGas", drainAmount, "Both")
	self._gasDrainAccumulator = 0
	local stillHasGas = self:_hasEnoughBoostGas()
	self:_setBoostAllowed(stillHasGas)
	if stillHasGas then
		self:_setOutOfGasSwinging(false)
	else
		self._boostHeld = false
		self._maneuver:SetBoost(false)
		self:_setOutOfGasSwinging(true)
	end
end

------------------------------------------------------------
-- Wall Run
------------------------------------------------------------

function GearServiceClient:_clearODMWallRun()
	self._wallRunSide = nil
	self._odmWallRunActive = false
	self._lastWallRunWallTime = 0
	self._lastWallRunAirTime = 0
	if self._currentLoopAnimation == ANIMS.LeftWallRun or self._currentLoopAnimation == ANIMS.RightWallRun then
		self:_setLoopAnimation(nil)
	end
	StateMachine.RemoveStates(LocalPlayer, "ODMWallRunning")
end

function GearServiceClient:_updateODMWallRunAnimation()
	if not self._equipped or not self._handlesOut or not self._rootPart or not self._character then
		self:_clearODMWallRun()
		return
	end
	if self._maneuver and self._maneuver.IsVDashing and self._maneuver:IsVDashing() then
		self:_clearODMWallRun()
		return
	end

	local isHooking = self._maneuver and self._maneuver:IsHooking()
	if not isHooking and not self._odmWallRunActive then
		self:_clearODMWallRun()
		return
	end

	local now = os.clock()
	local humanoid = self._character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
		self._lastWallRunAirTime = now
	end

	local recentlyAirborne = now - self._lastWallRunAirTime <= CONFIG.WallRunGroundGraceTime
	if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air and not recentlyAirborne then
		self:_clearODMWallRun()
		return
	end

	local vel = self._rootPart.AssemblyLinearVelocity
	if Vector3.new(vel.X, 0, vel.Z).Magnitude < CONFIG.WallRunMinSpeed then
		self:_clearODMWallRun()
		return
	end

	local side = General:GetSideWallHit(self._character, self._rootPart, CONFIG.WallRunCheckDistance)
	if side then
		self._lastWallRunWallTime = now
		self._wallRunSide = side
	elseif now - self._lastWallRunWallTime > CONFIG.WallRunLostWallGraceTime then
		self:_clearODMWallRun()
		return
	end

	if isHooking then
		self._odmWallRunActive = true
		StateMachine.SetState(LocalPlayer, "ODMWallRunning", true)
	end
end

------------------------------------------------------------
-- Speed Lines
------------------------------------------------------------

function GearServiceClient:_setupSpeedLinesGui()
	local gui = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("SpeedLinesGui")
	local frame = gui and gui:IsA("ScreenGui") and gui:FindFirstChild("Frame")
	local template = frame and frame:IsA("Frame") and frame:FindFirstChild("LineTemplate")
	if gui and frame and template and template:IsA("Frame") then
		self._speedLinesGui = gui
		self._speedLinesFrame = frame
		self._speedLineTemplate = template
		frame.Visible = false
		template.Visible = false
	else
		self._speedLinesGui, self._speedLinesFrame, self._speedLineTemplate = nil, nil, nil
	end
end

function GearServiceClient:_setSpeedLinesEnabled(enabled: boolean)
	if not self._speedLinesFrame then
		self:_setupSpeedLinesGui()
	end
	if self._speedLinesFrame then
		self._speedLinesFrame.Visible = enabled
	end
end

function GearServiceClient:_createScreenSpeedLine(speedAlpha: number)
	if self._speedLineCooldown then
		return
	end
	if not self._speedLinesFrame then
		self:_setupSpeedLinesGui()
	end
	if not self._speedLinesFrame or not self._speedLineTemplate then
		return
	end

	self._speedLineCooldown = true
	local line = self._speedLineTemplate:Clone()
	line.Visible = true
	line.Parent = self._speedLinesFrame
	line.BackgroundTransparency = 0.08

	local angle = math.rad(math.random(0, 359))
	local startRadius = math.random(72, 95) / 100
	local endRadius = math.random(18, 34) / 100

	line.Position = UDim2.fromScale(0.5 + math.cos(angle) * startRadius, 0.5 + math.sin(angle) * startRadius)
	line.Rotation = math.deg(angle) + 90
	line.Size = UDim2.fromOffset(math.random(2, 4), math.random(100, 180) + math.floor(speedAlpha * 80))

	local tween = TweenService:Create(line, TweenInfo.new(0.16 - 0.04 * speedAlpha, Enum.EasingStyle.Linear), {
		Position = UDim2.fromScale(0.5 + math.cos(angle) * endRadius, 0.5 + math.sin(angle) * endRadius),
		BackgroundTransparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		if line then
			line:Destroy()
		end
	end)
	task.delay(0.018 - 0.008 * speedAlpha, function()
		self._speedLineCooldown = false
	end)
end

function GearServiceClient:_updateScreenSpeedLines()
	if not self._equipped or not self._handlesOut or not self._maneuver or not self._rootPart then
		self:_setSpeedLinesEnabled(false)
		return
	end
	if not self._maneuver:IsHooking() then
		self:_setSpeedLinesEnabled(false)
		return
	end
	local speed = self._rootPart.AssemblyLinearVelocity.Magnitude
	if speed < 160 then
		self:_setSpeedLinesEnabled(false)
		return
	end
	self:_setSpeedLinesEnabled(true)
	local alpha = math.clamp((speed - 160) / 40, 0, 1)
	local count = alpha > 0.65 and 3 or alpha > 0.3 and 2 or 1
	for _ = 1, count do
		self:_createScreenSpeedLine(alpha)
	end
end

------------------------------------------------------------
-- Handle / Blade State
------------------------------------------------------------

function GearServiceClient:_canUseODM(): boolean
	return self._equipped == true and self._handlesOut == true and self._maneuver ~= nil
end

function GearServiceClient:_canAttack(): boolean
	if not self:_canUseODM() or not self._bladesOut or self._isSwinging then
		return false
	end
	if not self:hasUsableBlade() then
		return false
	end
	return not (self._character and self._character:GetAttribute("Stun"))
end

function GearServiceClient:_releaseHookState()
	self._hookLeftHeld = false
	self._hookRightHeld = false
	self._orbitLeftHeld = false
	self._orbitRightHeld = false
	self._boostHeld = false
	self:_setGearLoopSound("GasHiss", false)
	if self._maneuver then
		self._maneuver:SetBoost(false)
		self:_setOutOfGasSwinging(false)
		self._maneuver:SetOrbitHeld("Left", false)
		self._maneuver:SetOrbitHeld("Right", false)
		pcall(function()
			self._maneuver:EndGrapple("Left")
		end)
		pcall(function()
			self._maneuver:EndGrapple("Right")
		end)
	end
end

function GearServiceClient:_setHandlesOut(handlesOut: boolean, replicate: boolean?)
	if not self._equipped then
		return
	end
	if StateMachine.CanPerformAction and not StateMachine.CanPerformAction(LocalPlayer, "ToggleODMHandles") then
		return
	end
	if self._handlesOut == handlesOut then
		return
	end

	if replicate ~= false then
		networker:fire("clientToggleHandles")
	end

	if handlesOut then
		self._handlesOut = true
		self:_syncPassiveODMStates()
		self:_playGearSound("HolsterOut")
		self:_applyGearVisibility()
		self:_setCordAttachmentsHolstered(false)
		self:_setLoopAnimation(ANIMS.GearIdle)
		self:_syncHeldInputs(false)
		self:_refreshODMAnimations()
		return
	end

	self:_playGearSound("Holster")
	self._bladesOut = false
	StateMachine.SetState(LocalPlayer, "ODMBladesOut", false)
	self:_releaseHookState()
	self:_clearODMWallRun()
	self:_setLoopAnimation(nil)
	self:_setActiveODMState(nil)
	self._handlesOut = false
	self._bladesOut = false
	self:_syncPassiveODMStates()
	self:_applyGearVisibility()
	self:_setCordAttachmentsHolstered(true)
	self:_refreshODMAnimations()
end

function GearServiceClient:_setBladesOut(bladesOut: boolean, replicate: boolean?)
	if not self._equipped or not self._handlesOut then
		return
	end
	if bladesOut and not self:hasBladeReserve() then
		return
	end

	self._bladesOut = bladesOut
	StateMachine.SetState(LocalPlayer, "ODMBladesOut", bladesOut)
	if replicate ~= false then
		networker:fire("clientSetBladesOut", bladesOut)
	end

	local track = self:_playOneShot(bladesOut and ANIMS.UnsheatheBlades or ANIMS.SheatheBlades)
	self:_playGearSound(bladesOut and "Unsheathe" or "Sheathe")

	if not track then
		self:_setBladeSideVisible("Left", bladesOut)
		self:_setBladeSideVisible("Right", bladesOut)
		return
	end

	if bladesOut then
		task.delay(0.2, function()
			if self._equipped and self._handlesOut and self._bladesOut then
				self:_setScabbardVFXEnabled("Both", true)
			end
		end)
		local conn: RBXScriptConnection? = nil
		conn = track:GetMarkerReachedSignal("BladesOut"):Connect(function()
			self:_setBladeSideVisible("Left", true)
			self:_setBladeSideVisible("Right", true)
			self:_setScabbardVFXEnabled("Both", false)
			if conn then
				conn:Disconnect()
			end
		end)
		track.Stopped:Once(function()
			if conn then
				conn:Disconnect()
			end
			self:_setBladeSideVisible("Left", true)
			self:_setBladeSideVisible("Right", true)
			self:_setScabbardVFXEnabled("Both", false)
		end)
		return
	end

	local conn: RBXScriptConnection? = nil
	conn = track:GetMarkerReachedSignal("LeftBlade"):Connect(function()
		self:_setScabbardVFXEnabled("Left", true)
		self:_setBladeSideVisible("Left", false)
		task.delay(CONFIG.RightBladeSheatheDelay, function()
			if self._equipped then
				self:_setScabbardVFXEnabled("Right", true)
				self:_setBladeSideVisible("Right", false)
				task.delay(0.15, function()
					if self._equipped then
						self:_setScabbardVFXEnabled("Both", false)
					end
				end)
			end
		end)
		if conn then
			conn:Disconnect()
		end
	end)
	track.Stopped:Once(function()
		if conn then
			conn:Disconnect()
		end
		self:_setBladeSideVisible("Left", false)
		self:_setBladeSideVisible("Right", false)
		self:_setScabbardVFXEnabled("Both", false)
	end)
end

function GearServiceClient:_dropBlades()
	if not self._equipped or not self._handlesOut or not self._bladesOut then
		return
	end
	self._bladesOut = false
	StateMachine.SetState(LocalPlayer, "ODMBladesOut", false)
	self:_setBladeSideVisible("Left", false)
	self:_setBladeSideVisible("Right", false)
	self:_applyGearVisibility()
	self:_refreshODMAnimations()
	networker:fire("clientDropBlades")
	task.delay(0.1, function()
		if self._equipped and self._handlesOut and not self._bladesOut then
			self:_setBladeSideVisible("Left", false)
			self:_setBladeSideVisible("Right", false)
			self:_applyGearVisibility()
		end
	end)
end

------------------------------------------------------------
-- Input Helpers
------------------------------------------------------------

function GearServiceClient:_syncHeldInputs(playOrbitStart: boolean)
	if not self._maneuver then
		return
	end
	local boostHeld = InputServiceClient:IsActionHeld("GearBoost")
	local leftHeld = InputServiceClient:IsActionHeld("OrbitLeft") or UserInputService:IsKeyDown(Enum.KeyCode.A)
	local rightHeld = InputServiceClient:IsActionHeld("OrbitRight") or UserInputService:IsKeyDown(Enum.KeyCode.D)
	local hasGas = self:_hasEnoughBoostGas()

	self:_setBoostAllowed(hasGas)
	self._boostHeld = boostHeld and hasGas
	self._maneuver:SetBoost(self._boostHeld)

	if self._boostHeld then
		self:_setOutOfGasSwinging(false)
	elseif self._maneuver:IsHooking() and boostHeld and not hasGas then
		self:_setOutOfGasSwinging(true)
	end

	if leftHeld and not rightHeld then
		self._orbitLeftHeld, self._orbitRightHeld = true, false
		self._maneuver:SetOrbitHeld("Left", true)
		self._maneuver:SetOrbitHeld("Right", false)
		if playOrbitStart then
			self:_playOrbitStart("Left")
		end
		return
	end

	if rightHeld and not leftHeld then
		self._orbitLeftHeld, self._orbitRightHeld = false, true
		self._maneuver:SetOrbitHeld("Left", false)
		self._maneuver:SetOrbitHeld("Right", true)
		if playOrbitStart then
			self:_playOrbitStart("Right")
		end
		return
	end

	self._orbitLeftHeld, self._orbitRightHeld = false, false
	self._maneuver:SetOrbitHeld("Left", false)
	self._maneuver:SetOrbitHeld("Right", false)
end

function GearServiceClient:_playOrbitStart(side: string)
	self:_setLoopAnimation(nil)
	self._orbitStartPlayingUntil = os.clock() + CONFIG.OrbitStartHoldTime
	self:_playGearSound("Orbit")
	self:_playOneShot(side == "Left" and ANIMS.LeftOrbitStart or ANIMS.RightOrbitStart)
	task.delay(CONFIG.OrbitStartHoldTime, function()
		if self._equipped then
			self:_refreshODMAnimations()
		end
	end)
end

function GearServiceClient:_playHookStart(side: string)
	if self._hookLeftHeld and self._hookRightHeld then
		self:_playOneShot(ANIMS.DoubleHookStart)
	elseif side == "Left" then
		self:_playOneShot(ANIMS.LeftHookStart)
	else
		self:_playOneShot(ANIMS.RightHookStart)
	end
end

function GearServiceClient:_resetInputState()
	self._hookLeftHeld = false
	self._hookRightHeld = false
	self._orbitLeftHeld = false
	self._orbitRightHeld = false
	self._boostHeld = false
	self._executeHeld = false
	self._executePressedAt = 0
	self._vDashAttemptId += 1
	self._reloadHeld = false
	self._reloadPressTime = 0
	self._grappleDebounce.Left = false
	self._grappleDebounce.Right = false
	self._attackDebounce = false
	self._heavyAttackDebounce = false
	self._isSwinging = false
	self._attackHeld = false
	self._heldAttackTrack = nil
	self._heldAttackRelease = nil
end

------------------------------------------------------------
-- Input Handlers
------------------------------------------------------------

function GearServiceClient:_onHook(side: string, state: string, _inputObject: InputObject)
	if not self:_canUseODM() then
		return
	end

	if state == "Began" then
		if side == "Left" then
			self._hookLeftHeld = true
		else
			self._hookRightHeld = true
		end
		if self._grappleDebounce[side] then
			self:_refreshODMAnimations()
			return
		end

		local hookCost = self:getGasCost(CONFIG.HookShotGasCost)
		if not self:hasGas(hookCost, side) then
			self:_refreshODMAnimations()
			return
		end

		local mouse = LocalPlayer:GetMouse()
		local target = mouse and mouse.Hit.Position
		if not target or not self._maneuver then
			self:_refreshODMAnimations()
			return
		end

		self._grappleDebounce[side] = true
		networker:fire("clientConsumeGas", hookCost, side)
		self._maneuver:BeginGrapple(side, target)
		
		self:_playGearSound("Shot")
		self:_playHookStart(side)

		task.spawn(function()
			local startTime = os.clock()
			while self._equipped and self._maneuver and os.clock() - startTime < CONFIG.HookAttachWaitTime do
				if self._maneuver:IsHookAttached(side) then
					if self._maneuver:IsOtherHookAttached(side) then
						self:_playOneShot(ANIMS.DoubleHookStart)
					end
					self:_syncHeldInputs(true)
					self:_refreshODMAnimations()
					return
				end
				task.wait()
			end
			if self._equipped then
				self:_syncHeldInputs(false)
				self:_refreshODMAnimations()
			end
		end)

		task.delay(CONFIG.GrappleDebounceTime, function()
			self._grappleDebounce[side] = false
		end)
	elseif state == "Ended" then
		local wasActive = false
		if self._maneuver then
			wasActive = (self._maneuver.IsHookAttached and self._maneuver:IsHookAttached(side))
				or (side == "Left" and self._hookLeftHeld or self._hookRightHeld)
		end

		if side == "Left" then
			self._hookLeftHeld = false
		else
			self._hookRightHeld = false
		end

		if self._maneuver then
			if wasActive then
				self:_playGearSound("Retract")
			end
			pcall(function()
				self._maneuver:EndGrapple(side)
			end)
			if not self._maneuver:IsHooking() then
				self:_setOutOfGasSwinging(false)
				self:_setGearLoopSound("GasHiss", false)
			end
		end
		self:_refreshODMAnimations()
	end

	if os.clock() >= self._orbitStartPlayingUntil then
		self:_refreshODMAnimations()
	end
end

function GearServiceClient:_onOrbit(side: string, state: string)
	if not self:_canUseODM() or not self._maneuver then
		return
	end
	local opposite = side == "Left" and "Right" or "Left"

	if state == "Began" then
		self._orbitLeftHeld = side == "Left"
		self._orbitRightHeld = side == "Right"
		self._maneuver:SetOrbitHeld(side, true)
		self._maneuver:SetOrbitHeld(opposite, false)
		if self._maneuver:IsHooking() then
			self:_playOrbitStart(side)
		end
	elseif state == "Ended" then
		if side == "Left" then
			self._orbitLeftHeld = false
		else
			self._orbitRightHeld = false
		end
		self._maneuver:SetOrbitHeld(side, false)
	end

	self:_refreshODMAnimations()
end

function GearServiceClient:_tryVDash(): boolean
	if not self._executeHeld or not self:_canUseODM() or not self._maneuver then
		return false
	end
	if self._isSwinging then
		return false
	end
	if self._maneuver.IsVDashing and self._maneuver:IsVDashing() then
		return true
	end
	if not self._maneuver:IsDoubleHooking() then
		return false
	end

	local vDashCost = self:getGasCost(CONFIG.VDashGasCost)
	if not self:hasGas(vDashCost, "Both") then
		self:_setBoostAllowed(false)
		return false
	end

	local target = self._maneuver.GetDoubleHookTargetPosition and self._maneuver:GetDoubleHookTargetPosition()
	if not target then
		return false
	end

	self:_setBoostAllowed(true)
	local wasOrbiting = self._orbitLeftHeld or self._orbitRightHeld
	local didDash = self._maneuver:VDashToPosition(target)

	if didDash then
		networker:fire("clientConsumeGas", vDashCost, "Both")
		self:_setOutOfGasSwinging(false)
		self:_playGearSound(wasOrbiting and "OrbitBurst" or "Dash")
		if self._bladesOut then
			self:_playOneShot(ANIMS.VerticalSlice)
		end
	end

	return didDash == true
end

function GearServiceClient:_tryVDashWithGrace()
	if not self._executeHeld or not self._hookLeftHeld or not self._hookRightHeld then
		return
	end
	self._vDashAttemptId += 1
	local attemptId = self._vDashAttemptId
	local startTime = os.clock()
	local graceTime = CONFIG.VDashAttachGraceTime

	while self._equipped and self._executeHeld and self._maneuver and os.clock() - startTime <= graceTime do
		if attemptId ~= self._vDashAttemptId then
			return
		end
		if not self._hookLeftHeld or not self._hookRightHeld then
			return
		end
		if self:_tryVDash() then
			return
		end
		task.wait()
	end
end

function GearServiceClient:_onExecute(state: string)
	if state == "Began" then
		self._executeHeld = true
		self._executePressedAt = os.clock()
		task.spawn(function()
			self:_tryVDashWithGrace()
		end)
	elseif state == "Ended" then
		self._executeHeld = false
		self._executePressedAt = 0
		self._vDashAttemptId += 1
		if self._maneuver and self._maneuver.EndVDash then
			self._maneuver:EndVDash()
		end
		self:_refreshODMAnimations()
	end
end

function GearServiceClient:_onBoost(state: string)
	if state ~= "Began" and state ~= "Ended" then
		return
	end
	local character = self._character
	if character and character:GetAttribute("MoveState") == "Vaulting" then
		if state == "Ended" and self._maneuver then
			self._boostHeld = false
			self._maneuver:SetBoost(false)
		end
		return
	end
	if state == "Began" and not (self._maneuver and self._maneuver:IsHooking()) then
		return
	end
	if not self:_canUseODM() or not self._maneuver then
		return
	end

	if state == "Began" then
		local hasGas = self:_hasEnoughBoostGas()
		self:_setBoostAllowed(hasGas)
		if not hasGas then
			self._boostHeld = false
			self._maneuver:SetBoost(false)
			self:_setOutOfGasSwinging(true)
			self:_refreshODMAnimations()
			return
		end
		self._boostHeld = true
		self._maneuver:SetBoost(true)
		self:_playGearSound("GasBurst")
		self:_setOutOfGasSwinging(false)
	else
		self._boostHeld = false
		self._maneuver:SetBoost(false)
		self:_setBoostAllowed(self:_hasEnoughBoostGas())
	end
	self:_refreshODMAnimations()
end

function GearServiceClient:_onToggleHandles(state: string)
	if state ~= "Began" or not self._equipped then
		return
	end
	self:_setHandlesOut(not self._handlesOut, true)
end

function GearServiceClient:_playAttackAnimation(animationName: string, isHeavy: boolean)
	self._isSwinging = true
	local track = self:_playAnimation(animationName, { Restart = true, FadeTime = 0.04, Weight = 1, Speed = 1 })
	local swingDetectionStarted = false
	local swingEnded = false
	local slashPlayed = false

	-- Titan hitbox loop
	task.spawn(function()
		local hitCache = {}
		local bladeMultiplier = self:getStatMultiplier("BladeDamage")

		while self._isSwinging do
			if self._rootPart then
				local hitboxParams = OverlapParams.new()
				hitboxParams.FilterType = Enum.RaycastFilterType.Exclude
				hitboxParams.FilterDescendantsInstances = {
					self._character
				}
				hitboxParams.CollisionGroup = "ODM_Blade"

				local hitbox = workspace:GetPartBoundsInRadius(self._rootPart.Position, 2, hitboxParams)
				for i = 1, math.min(#hitbox, 10) do
					local hit = hitbox[i]
					if hit and hit.Parent and hit.Parent.Parent then
						local model = hit.Parent.Parent
						if model:GetAttribute("IsTitan") and not table.find(hitCache, hit) then
							table.insert(hitCache, hit)
							
							local damage = self._rootPart.AssemblyLinearVelocity.Magnitude * bladeMultiplier
							local hitName = hit.Name

							if hitName == "Nape" then
								for i, v in pairs(model:GetDescendants()) do
									if v:IsA("BasePart") then
										v.CanCollide = false
									end
								end
								
								Remotes.Titan.DamageNape:FireServer(hit, model, damage)
							elseif hitName == "LeftEye" then
								Remotes.Titan.DamageEyes:FireServer(hit, model, damage, "Left")
							elseif hitName == "RightEye" then
								Remotes.Titan.DamageEyes:FireServer(hit, model, damage, "Right")
							elseif hitName == "LeftArm" then
								Remotes.Titan.DamageLimb:FireServer(hit, model, damage, "Left", "Arm")
							elseif hitName == "RightArm" then
								Remotes.Titan.DamageLimb:FireServer(hit, model, damage, "Right", "Arm")
							elseif hitName == "LeftLeg" then
								Remotes.Titan.DamageLimb:FireServer(hit, model, damage, "Left", "Leg")
							elseif hitName == "RightLeg" then
								Remotes.Titan.DamageLimb:FireServer(hit, model, damage, "Right", "Leg")
							end
						end
					end
				end
			end
			task.wait()
		end
	end)

	local function playSlash()
		if slashPlayed then return end
		slashPlayed = true
		self:_playRandomSlashSound()
	end

	local function beginServerSwing()
		if swingDetectionStarted then return end
		swingDetectionStarted = true
		networker:fire("clientBeginBladeSwing")
		playSlash()
	end

	local function endServerSwing()
		if swingEnded then return end
		swingEnded = true
		if swingDetectionStarted then
			networker:fire("clientEndBladeSwing")
		end
	end

	local function finishSwing()
		endServerSwing()
		if self._heldAttackTrack == track then
			self._heldAttackTrack = nil
		end
		if self._heldAttackRelease then
			self._heldAttackRelease = nil
		end
		self._isSwinging = false
		if self._equipped then
			self:_refreshODMAnimations()
		end
	end

	if track then
		track:GetMarkerReachedSignal("Hold"):Once(function()
			if self._attackHeld and self._isSwinging then
				self._heldAttackTrack = track
				self._heldAttackRelease = function()
					if self._heldAttackTrack ~= track then return end
					beginServerSwing()
					if track.IsPlaying then
						track:AdjustSpeed(1)
					end
					self._heldAttackTrack = nil
					self._heldAttackRelease = nil
				end
				track:AdjustSpeed(0)
				return
			end
			beginServerSwing()
		end)
		track.Stopped:Once(finishSwing)
		task.delay(0.8, function()
			if track.IsPlaying or swingEnded or self._heldAttackTrack == track then return end
			if not swingDetectionStarted then
				beginServerSwing()
			end
		end)
	else
		beginServerSwing()
		task.delay(isHeavy and 0.65 or 0.35, finishSwing)
	end
end

function GearServiceClient:_onAttack(state: string)
	if state == "Began" then
		self._attackHeld = true
		if not self:_canAttack() or self._attackDebounce then
			return
		end
		self._attackDebounce = true
		self:_playAttackAnimation(self:_getRandomSliceAnimation(), false)
		self:_refreshODMAnimations()
		task.delay(CONFIG.AttackDebounceTime, function()
			self._attackDebounce = false
		end)
	elseif state == "Ended" then
		self._attackHeld = false
		if self._heldAttackRelease then
			local release = self._heldAttackRelease
			release()
			return
		end
		if self._heldAttackTrack then
			self._heldAttackTrack:AdjustSpeed(1)
			self._heldAttackTrack = nil
		end
	end
end

function GearServiceClient:_onHeavyAttack(state: string)
	if state ~= "Began" or not self:_canAttack() or self._heavyAttackDebounce then
		return
	end
	self._heavyAttackDebounce = true
	self:_playAttackAnimation(ANIMS.VerticalSlice, true)
	self:_refreshODMAnimations()
	task.delay(CONFIG.HeavyAttackDebounceTime, function()
		self._heavyAttackDebounce = false
	end)
end

function GearServiceClient:_onReloadBlades(state: string)
	if not self._equipped or not self._handlesOut then
		return
	end

	if state == "Began" then
		self._reloadHeld = true
		self._reloadPressTime = os.clock()
		if self._bladesOut then
			task.delay(CONFIG.ReloadHoldTime, function()
				if not self._reloadHeld or not self._equipped or not self._handlesOut or not self._bladesOut then
					return
				end
				self._reloadHeld = false
				self:_setBladesOut(false, true)
				self:_refreshODMAnimations()
			end)
		end
		return
	end

	if state == "Ended" then
		local heldTime = os.clock() - self._reloadPressTime
		self._reloadHeld = false
		if heldTime >= CONFIG.ReloadHoldTime then
			return
		end
		if self._bladesOut then
			self:_dropBlades()
			return
		end
		if not self:hasBladeReserve() then
			return
		end
		self:_setBladesOut(true, true)
		self:_refreshODMAnimations()
	end
end

function GearServiceClient:_onCheckGas(state: string)
	if state ~= "Began" or not self:_canUseODM() then
		return
	end
	self:_playGasCheckSequence(self:_getGasCheckTapPitch())
	self:_refreshODMAnimations()
end

function GearServiceClient:_bindInputs()
	local binds = {
		HookLeft = function(_, state, obj)
			self:_onHook("Left", state, obj)
		end,
		HookRight = function(_, state, obj)
			self:_onHook("Right", state, obj)
		end,
		GearBoost = function(_, state)
			self:_onBoost(state)
		end,
		OrbitLeft = function(_, state)
			self:_onOrbit("Left", state)
		end,
		OrbitRight = function(_, state)
			self:_onOrbit("Right", state)
		end,
		GearHandles = function(_, state)
			self:_onToggleHandles(state)
		end,
		Attack = function(_, state)
			self:_onAttack(state)
		end,
		HeavyAttack = function(_, state)
			self:_onHeavyAttack(state)
		end,
		Execute = function(_, state)
			self:_onExecute(state)
		end,
		ReloadBlades = function(_, state)
			self:_onReloadBlades(state)
		end,
		CheckGas = function(_, state)
			self:_onCheckGas(state)
		end,
	}
	for actionName, callback in binds do
		table.insert(self._disconnectors, InputServiceClient:BindAction(actionName, callback))
	end
end

------------------------------------------------------------
-- Gear Lifecycle
------------------------------------------------------------

function GearServiceClient:equip(character: Model?, presetName: string?)
	character = character or LocalPlayer.Character
	if not character then
		return
	end

	self:unequip()

	local preset = presetName or CONFIG.DefaultGearPreset
	self._character = character
	self._rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	self._loadoutPreset = preset

	self:_createGearInstance(preset)
	self:_createManeuver(character, preset)
	self:_loadODMAnimations()
	self:_cacheGearSounds()

	self._equipped = true
	self._handlesOut = false
	self._bladesOut = false
	self._gasDrainAccumulator = 0
	self._gasCrossfeedAccumulator = 0
	self._currentLoopAnimation = nil
	self._orbitStartPlayingUntil = 0

	self:_setBoostAllowed(self:_hasEnoughBoostGas())
	self:_applyGearVisibility()
	self:_setCordAttachmentsHolstered(true)
	self:_resetInputState()
	self:_setupSpeedLinesGui()

	InputServiceClient:SetContextEnabled("ODM", true)
	self:_refreshODMAnimations()

	networker:fire("clientEquipGear", preset)

	self._runtimeConnection = RunService.RenderStepped:Connect(function(dt)
		if self._equipped then
			self:_updateODMWallRunAnimation()
			self:_refreshODMAnimations()
			self:_updateScreenSpeedLines()
			self:_updateGasUsage(dt)
		end
	end)
end

function GearServiceClient:unequip()
	self:_setGearLoopSound("GasHiss", false)
	for name in self._gearSounds do
		self:_stopGearSound(name)
	end

	if self._runtimeConnection then
		self._runtimeConnection:Disconnect()
		self._runtimeConnection = nil
	end

	self:_releaseHookState()
	self:_stopAllODMAnimations()
	self._gasCheckSequenceId += 1
	self._gasCheckDebounce = false

	if self._heldAttackTrack then
		self._heldAttackTrack:AdjustSpeed(1)
		self._heldAttackTrack = nil
	end
	self._heldAttackRelease = nil

	if self._maneuver then
		self._maneuver:Destroy()
		self._maneuver = nil
	end

	if self._gearInstance then
		self._gearInstance:destroy()
		self._gearInstance = nil
	end

	if self._equipped then
		networker:fire("clientUnequipGear")
	end

	self._equipped = false
	self._handlesOut = false
	self._bladesOut = false
	self._character = nil
	self._rootPart = nil
	self._wallRunSide = nil
	self._currentLoopAnimation = nil
	self._orbitStartPlayingUntil = 0
	self._gasDrainAccumulator = 0
	self._gasCrossfeedAccumulator = 0

	for _, key in
		{
			"ODMEquipped",
			"ODMHandlesOut",
			"ODMActive",
			"ODMHooking",
			"ODMOrbiting",
			"ODMGroundSliding",
			"ODMVDashing",
			"ODMWallRunning",
			"ODMHolstering",
			"ODMUnholstering",
			"ODMBladesOut",
			"Sprinting",
			"WallRunning",
		}
	do
		StateMachine.RemoveStates(LocalPlayer, key)
	end

	self:_setScabbardVFXEnabled("Both", false)
	self:_resetInputState()
	self:_setSpeedLinesEnabled(false)
	InputServiceClient:SetContextEnabled("ODM", false)
end

------------------------------------------------------------
-- Server -> Client Networker Handlers
------------------------------------------------------------

function GearServiceClient:gearResources(resources)
	if type(resources) ~= "table" then
		return
	end
	for key, value in resources do
		self.Resources[key] = value
	end

	if type(resources.GearStats) == "table" then
		self.ConditionMultipliers = resources.GearStats
		self:_rebuildStatMultipliers()
		self:RefreshGearModifiers()
	end

	-- Keep gear instance in sync with authoritative server values.
	if self._gearInstance and self._gearInstance.Mobility then
		self._gearInstance.Mobility:setGas(
			resources.GasLeft or self.Resources.GasLeft,
			resources.GasRight or self.Resources.GasRight
		)
	end

	local character = LocalPlayer.Character
	if character then
		local r = self.Resources
		_applyRemoteGearVisibility(
			character,
			self._equipped,
			self._handlesOut,
			self._bladesOut and r.HasActiveBladePair == true
		)
	end
end

function GearServiceClient:gearState(player: Player, state: any)
	if not player or not state then
		return
	end
	local character = player.Character
	if not character then
		return
	end

	local equipped = state.Equipped == true
	local handlesOut = equipped and state.HandlesOut == true
	local bladesOut = handlesOut and state.BladesOut == true

	if player == LocalPlayer then
		-- Local state is driven by input handlers, not server broadcasts.
		-- Only update visual state for other players.
		return
	end

	_applyRemoteGearVisibility(character, equipped, handlesOut, bladesOut)
end

function GearServiceClient:gearBladeDrop(player: Player)
	if not player then
		return
	end
	local character = player.Character
	if not character then
		return
	end

	if player == LocalPlayer then
		self.Resources.HasActiveBladePair = false
		self.Resources.ActiveBladePairIndex = nil
		self.Resources.LeftBladeDurability = 0
		self.Resources.RightBladeDurability = 0
		self._bladesOut = false
	end

	_applyRemoteGearVisibility(character, true, true, false)
end

function GearServiceClient:gearConditionUpdated(condition: number, _serial: string)
	self._gearCondition = tonumber(condition)
end

function GearServiceClient:forceEquipODM(presetName: string)
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	self:equip(character, presetName or "Gen1Gear")
end

function GearServiceClient:forceUnequipODM()
	self:unequip()
end

function GearServiceClient:syncFromPlayerData(data: any)
	if type(data) ~= "table" then
		return
	end
	local settings = type(data.Settings) == "table" and data.Settings or {}
	local preset = settings.GearStyle or settings.ODMStyle or settings.GearPreset or "Gen1Gear"
	if data.HasGearEquipped == true then
		self:equip(LocalPlayer.Character, preset)
	else
		self:unequip()
	end
end

function GearServiceClient:startRepairQTE(_sessionId: string, _config: any)
	-- Forwarded to RepairQTEClient via Networker — no action needed here.
end

function GearServiceClient:repairQTEResult(_result: any) end

------------------------------------------------------------
-- Damage Counter UI
------------------------------------------------------------

function GearServiceClient:damageCounter(hitType: string, damage: number, hit: BasePart)
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui or not hit or not hit:IsA("BasePart") then
		return
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local gearAssets = assets and assets:FindFirstChild("Gear")
	if not gearAssets then
		return
	end

	local dmgTemplate = gearAssets:FindFirstChild("DMGUI")
	local dlineTemplate = gearAssets:FindFirstChild("Dline")
	if not dmgTemplate or not dlineTemplate then
		return
	end

	local ui = dmgTemplate:Clone()
	local ui2 = dlineTemplate:Clone()
	ui.Parent = playerGui
	ui2.Parent = hit

	local frame = ui:WaitForChild("Frame")
	local label = frame:WaitForChild("dmg")
	frame.Visible = true
	ui2.Enabled = true

	local isPerfect = hitType == "PerfectHit"
	local color = isPerfect and Color3.new(1, 0.878, 0.380) or Color3.new(0.902, 0, 0)
	label.TextColor3 = color
	label.Text = "- " .. tostring(math.floor((tonumber(damage) or 0) + 0.5))
	label.TextTransparency = 1
	TweenService:Create(label, TweenInfo.new(1), { TextSize = isPerfect and 36 or 29 }):Play()
	TweenService:Create(label, TweenInfo.new(1), { TextTransparency = 0 }):Play()
	label:TweenSizeAndPosition(
		UDim2.fromScale(0.204, 0.123),
		UDim2.fromScale(0.42, 0.403),
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Sine,
		1,
		true
	)

	for _, child in ui2:GetChildren() do
		local img = child:FindFirstChild("ImageLabel")
		if img and img:IsA("ImageLabel") then
			img.ImageColor3 = color
			img.ImageTransparency = 1
			TweenService:Create(img, TweenInfo.new(0.4), { ImageTransparency = 0 }):Play()
			img:TweenSizeAndPosition(
				UDim2.fromScale(1, 1),
				UDim2.fromOffset(0, 0),
				Enum.EasingDirection.Out,
				Enum.EasingStyle.Sine,
				0.4,
				true
			)
		end
	end

	task.delay(1, function()
		if not ui.Parent then
			return
		end
		TweenService:Create(label, TweenInfo.new(0.5), { TextSize = 24 }):Play()
		TweenService:Create(label, TweenInfo.new(1), { TextTransparency = 1 }):Play()
		label:TweenSizeAndPosition(
			UDim2.fromScale(0.158, 0.005),
			UDim2.fromScale(0.42, 0.403),
			Enum.EasingDirection.Out,
			Enum.EasingStyle.Sine,
			1,
			true
		)
	end)
	task.delay(2.25, function()
		if ui.Parent then
			ui:Destroy()
		end
		if ui2.Parent then
			ui2:Destroy()
		end
	end)
end

------------------------------------------------------------
-- Client -> Server API
------------------------------------------------------------

function GearServiceClient:consumeGas(amount: number, tank: string)
	networker:fire("clientConsumeGas", amount, tank or "Both")
end

function GearServiceClient:crossfeedGas(dt: number)
	networker:fire("clientCrossfeedGas", dt)
end

function GearServiceClient:refillGas()
	networker:fire("clientRefillGas")
end

function GearServiceClient:refillBlades()
	networker:fire("clientRefillBlades")
end

function GearServiceClient:equipGear(preset: string)
	networker:fire("clientEquipGear", preset)
end

function GearServiceClient:unequipGear()
	networker:fire("clientUnequipGear")
end

function GearServiceClient:toggleHandles()
	networker:fire("clientToggleHandles")
end

function GearServiceClient:setBladesOut(bladesOut: boolean)
	networker:fire("clientSetBladesOut", bladesOut)
end

function GearServiceClient:dropBlades()
	networker:fire("clientDropBlades")
end

function GearServiceClient:beginBladeSwing()
	networker:fire("clientBeginBladeSwing")
end

function GearServiceClient:releaseBladeSwing()
	networker:fire("clientReleaseBladeSwing")
end

function GearServiceClient:endBladeSwing()
	networker:fire("clientEndBladeSwing")
end

------------------------------------------------------------
-- Init
------------------------------------------------------------

local DEFAULT_KEYBINDS = {
	HookLeft     = "Q",
	HookRight    = "E",
	OrbitLeft    = "Q",
	OrbitRight   = "E",
	GearBoost    = "Space",
	GearBlock    = "LeftControl",
	ReloadBlades = "R",
	GearHandles  = "Z",
	HeavyAttack  = "G",
	SwitchODMMode = "X",
	CheckGas     = "C",
	Attack       = "MouseButton1",
	Sprint       = "LeftShift",
	CrouchSlide  = "LeftControl",
	JumpVault    = "Space",
	ShiftLock    = "LeftAlt",
	Interaction  = "F",
}

function GearServiceClient:init()
	if self._initialized then
		return
	end
	self._initialized = true

	self:_resetStatMultipliers()
	self:_bindTalentServiceClient()
	self:_bindInputs()

	-- Apply default keybinds if none have been loaded from a profile yet.
	if not InputServiceClient._keybindsApplied then
		InputServiceClient:RefreshKeybindsFromProfile(DEFAULT_KEYBINDS)
	end

	InputServiceClient:SetContextEnabled("ODM", false)

	self._characterConnection = LocalPlayer.CharacterAdded:Connect(function(character)
		task.defer(function()

			if self._loadoutPreset then
				self:equip(character, self._loadoutPreset)
			end
		end)
	end)
end

return GearServiceClient