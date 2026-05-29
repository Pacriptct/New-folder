local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local GearConfig = require(script.Parent.Parent.Configs.GearConfig)

local ManeuverModule = {}
ManeuverModule.__index = ManeuverModule

export type Side = "Left" | "Right"

type HookData = {
	Fired: boolean,
	Traveling: boolean,
	Attached: boolean,

	Hook: Part?,
	Rope: Beam?,
	Attachment: Attachment?,

	Direction: Vector3,
	LastPosition: Vector3,
	TravelDistance: number,

	HitPart: BasePart?,
	HitLocalPosition: Vector3?,

	PhysicalRope: RopeConstraint?,
}

local function numberOr(value: any, fallback: number): number
	return if type(value) == "number" then value else fallback
end

local function vectorOr(value: any, fallback: Vector3): Vector3
	return if typeof(value) == "Vector3" then value else fallback
end

local function safeMultiplier(value: any): number
	if type(value) ~= "number" then
		return 1
	end

	if value <= 0 then
		return 1
	end

	return value
end

function ManeuverModule.new(character: Model, gearPreset: string?, cameraService: any?)
	local self = setmetatable({}, ManeuverModule)

	self.Config = GearConfig.GetPreset(gearPreset)
	self.CameraService = cameraService

	self.StatMultipliers = {
		ODMStats = 1,
		HookSpeed = 1,
		HookRange = 1,
		BladeDamage = 1,
		GasConsumption = 1,
	}

	local CFG = self.Config

	self.Character = character
	self.Humanoid = character:WaitForChild("Humanoid") :: Humanoid
	self.HRP = character:WaitForChild("HumanoidRootPart") :: BasePart

	self.RootAttachment = self.HRP:FindFirstChild("RootAttachment")
	if not self.RootAttachment or not self.RootAttachment:IsA("Attachment") then
		self.RootAttachment = Instance.new("Attachment")
		self.RootAttachment.Name = "RootAttachment"
		self.RootAttachment.Parent = self.HRP
	end

	self.OriginalWalkSpeed = self.Humanoid.WalkSpeed
	self.OriginalJumpPower = self.Humanoid.JumpPower
	self.OriginalJumpHeight = self.Humanoid.JumpHeight

	self.Momentum = numberOr(CFG.MinMomentum, 0.25)
	self.IsBoosting = false

	self.BoostAllowed = true

	self.OutOfGasSwinging = false
	self.OrbitSide = nil :: Side?
	self.LastMoveVelocity = Vector3.zero
	self.ReleaseCarryUntil = 0
	self.ReleaseCarryVelocity = Vector3.zero

	self.VDashing = false
	self.VDashHeld = false
	self.VDashCooldownUntil = 0
	self.VDashStartedAt = 0
	self.VDashDirection = Vector3.zero
	self.VDashTargetPosition = Vector3.zero

	self.GroundSliding = false
	self.GroundSlideVelocity = Vector3.zero
	self.GroundSlideStartedAt = 0

	self.OrbitLeftHeld = false
	self.OrbitRightHeld = false
	self.OrbitStartedAt = 0
	self._orbitEntrySnapPending = false
	self.LastOrbitSide = nil :: Side?

	self.LeftHook = {
		Fired = false,
		Traveling = false,
		Attached = false,
		Hook = nil,
		Rope = nil,
		Attachment = nil,
		Direction = Vector3.zero,
		LastPosition = Vector3.zero,
		TravelDistance = 0,
		HitPart = nil,
		HitLocalPosition = nil,
		PhysicalRope = nil,
	} :: HookData

	self.RightHook = {
		Fired = false,
		Traveling = false,
		Attached = false,
		Hook = nil,
		Rope = nil,
		Attachment = nil,
		Direction = Vector3.zero,
		LastPosition = Vector3.zero,
		TravelDistance = 0,
		HitPart = nil,
		HitLocalPosition = nil,
		PhysicalRope = nil,
	} :: HookData

	self.LeftOrigin = self:_findGearAttachment("Left")
	self.RightOrigin = self:_findGearAttachment("Right")

	self.BodyVelocity = Instance.new("BodyVelocity")
	self.BodyVelocity.Name = "ODMBodyVelocity"
	self.BodyVelocity.MaxForce = Vector3.zero
	self.BodyVelocity.P = 400
	self.BodyVelocity.Velocity = Vector3.zero
	self.BodyVelocity.Parent = self.HRP

	self.BodyGyro = Instance.new("BodyGyro")
	self.BodyGyro.Name = "ODMBodyGyro"
	self.BodyGyro.MaxTorque = Vector3.zero
	self.BodyGyro.P = 1800
	self.BodyGyro.D = 120
	self.BodyGyro.CFrame = self.HRP.CFrame
	self.BodyGyro.Parent = self.HRP

	self._connections = {}

	table.insert(
		self._connections,
		RunService.RenderStepped:Connect(function(dt)
			self:_updateMovers(dt)
		end)
	)

	return self
end

---------------------------------------------------------------
-- Stat multipliers
---------------------------------------------------------------

function ManeuverModule:SetStatMultipliers(multipliers)
	self.StatMultipliers = {
		ODMStats = 1,
		HookSpeed = 1,
		HookRange = 1,
		BladeDamage = 1,
		GasConsumption = 1,
	}

	if type(multipliers) ~= "table" then
		return
	end

	for key, value in pairs(multipliers) do
		if type(key) == "string" and type(value) == "number" then
			self.StatMultipliers[key] = safeMultiplier(value)
		end
	end
end

function ManeuverModule:_getStatMultiplier(statName: string): number
	if type(self.StatMultipliers) ~= "table" then
		return 1
	end

	return safeMultiplier(self.StatMultipliers[statName])
end

function ManeuverModule:_getODMMultiplier(): number
	return self:_getStatMultiplier("ODMStats")
end

function ManeuverModule:_getHookSpeedMultiplier(): number
	return self:_getStatMultiplier("HookSpeed") * self:_getODMMultiplier()
end

function ManeuverModule:_getHookRangeMultiplier(): number
	return self:_getStatMultiplier("HookRange") * self:_getODMMultiplier()
end

function ManeuverModule:_getSpeedMultiplier(): number
	return self:_getODMMultiplier()
end

---------------------------------------------------------------
-- Camera
---------------------------------------------------------------

function ManeuverModule:_setCameraEnabled(enabled: boolean)
	if self.CameraService then
		self.CameraService:SetODMEnabled(enabled, self.Character)
	end
end

function ManeuverModule:_setCameraBoosting(boosting: boolean)
	if self.CameraService then
		self.CameraService:SetODMBoosting(boosting)
	end
end

function ManeuverModule:_setCameraOrbit(side: Side?)
	if self.CameraService then
		self.CameraService:SetODMOrbit(side)
	end
end

function ManeuverModule:_cameraImpulse(strength: number?)
	if self.CameraService then
		self.CameraService:ODMImpulse(strength)
	end
end

function ManeuverModule:_cameraBoostShake(strength: number?)
	if self.CameraService and self.CameraService.ODMBoostShake then
		self.CameraService:ODMBoostShake(strength or 1)
		return
	end

	self:_cameraImpulse(strength or 1.5)
end

---------------------------------------------------------------
-- Helpers
---------------------------------------------------------------
function ManeuverModule:_findGearAttachment(side: Side): Attachment?
	local launcherName = if side == "Left" then "LeftLauncher" else "RightLauncher"

	local launcher = self.Character:FindFirstChild(launcherName, true)
	if not launcher then
		return nil
	end

	local firePoint = launcher:FindFirstChild("FirePoint", true)
	if not firePoint or not firePoint:IsA("Attachment") then
		return nil
	end

	return firePoint
end

function ManeuverModule:_getHook(side: Side): HookData
	return if side == "Left" then self.LeftHook else self.RightHook
end

function ManeuverModule:_getOrigin(side: Side): Attachment?
	local cached = if side == "Left" then self.LeftOrigin else self.RightOrigin

	if cached and cached.Parent then
		return cached
	end

	local found = self:_findGearAttachment(side)
	if found then
		if side == "Left" then
			self.LeftOrigin = found
		else
			self.RightOrigin = found
		end
	end

	return found
end

function ManeuverModule:IsHooking(): boolean
	return self.LeftHook.Attached or self.RightHook.Attached
end

function ManeuverModule:IsDoubleHooking(): boolean
	return self.LeftHook.Attached and self.RightHook.Attached
end

function ManeuverModule:IsHookAttached(side: Side): boolean
	local hook = self:_getHook(side)
	return hook.Attached == true
end

function ManeuverModule:IsOtherHookAttached(side: Side): boolean
	if side == "Left" then
		return self.RightHook.Attached
	end

	return self.LeftHook.Attached
end

function ManeuverModule:_isDisabled(): boolean
	local player = Players:GetPlayerFromCharacter(self.Character)
	return player ~= nil and (player:GetAttribute("Grabbed") == true or player:GetAttribute("Ragdolled") == true)
end

function ManeuverModule:IsGroundSliding(): boolean
	return self.GroundSliding == true
end

function ManeuverModule:IsVDashing(): boolean
	return self.VDashing == true
end

function ManeuverModule:IsOutOfGasSwinging(): boolean
	return self.OutOfGasSwinging == true
end

function ManeuverModule:_flat(velocity: Vector3): Vector3
	return Vector3.new(velocity.X, 0, velocity.Z)
end

function ManeuverModule:_makeRayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.Character }
	params.IgnoreWater = true
	return params
end

function ManeuverModule:_raycast(origin: Vector3, direction: Vector3): RaycastResult?
	if direction.Magnitude <= 0 then
		return nil
	end

	return Workspace:Raycast(origin, direction, self:_makeRayParams())
end

function ManeuverModule:_isOnGround(): boolean
	if not self.HRP then
		return false
	end

	if self.Humanoid and self.Humanoid.FloorMaterial ~= Enum.Material.Air then
		return true
	end

	local result = Workspace:Raycast(self.HRP.Position, Vector3.new(0, -3.5, 0), self:_makeRayParams())
	return result ~= nil
end

function ManeuverModule:IsSlidingOnGround(): boolean
	local origin = self.HRP.Position
	local result = Workspace:Raycast(origin, Vector3.new(0, -3.5, 0), self:_makeRayParams())
	return result ~= nil
end

function ManeuverModule:_isOwnCharacter(): boolean
	return self.Character == Players.LocalPlayer.Character
end

function ManeuverModule:_canPlayOwnVFX(): boolean
	return true
end

---------------------------------------------------------------
-- Physical rope fallback
---------------------------------------------------------------

function ManeuverModule:_destroyPhysicalRope(side: Side)
	local hook = self:_getHook(side)

	if hook.PhysicalRope then
		hook.PhysicalRope:Destroy()
		hook.PhysicalRope = nil
	end
end

function ManeuverModule:_destroyAllPhysicalRopes()
	self:_destroyPhysicalRope("Left")
	self:_destroyPhysicalRope("Right")
end

function ManeuverModule:_createPhysicalRopeForHook(side: Side)
	local hook = self:_getHook(side)

	if not hook.Attached or not hook.Hook or not hook.Attachment then
		self:_destroyPhysicalRope(side)
		return
	end

	if hook.PhysicalRope and hook.PhysicalRope.Parent then
		return
	end

	local currentDistance = (hook.Hook.Position - self.HRP.Position).Magnitude
	local slack = numberOr(self.Config.OutOfGasRopeSlack, 1.25)

	local rope = Instance.new("RopeConstraint")
	rope.Name = "ODMPhysicalSwingRope_" .. side
	rope.Attachment0 = self.RootAttachment
	rope.Attachment1 = hook.Attachment
	rope.Length = math.max(currentDistance + slack, 6)
	rope.Restitution = numberOr(self.Config.OutOfGasRopeRestitution, 0)
	rope.Visible = self.Config.OutOfGasRopeVisible == true
	rope.Enabled = true
	rope.Parent = self.HRP

	hook.PhysicalRope = rope
end

function ManeuverModule:_createPhysicalSwingRopes()
	if self.LeftHook.Attached then
		self:_createPhysicalRopeForHook("Left")
	end

	if self.RightHook.Attached then
		self:_createPhysicalRopeForHook("Right")
	end
end

function ManeuverModule:_restoreHumanoidFromRopeMode()
	self.BodyVelocity.MaxForce = Vector3.zero
	self.BodyVelocity.Velocity = Vector3.zero
	self.BodyGyro.MaxTorque = Vector3.zero

	self.Humanoid.PlatformStand = false
	self.Humanoid.AutoRotate = true

	if self.Humanoid.Health > 0 then
		self.Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	local velocity = self.HRP.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)

	if flatVelocity.Magnitude > 2 then
		local look = flatVelocity.Unit
		self.HRP.CFrame = CFrame.lookAt(self.HRP.Position, self.HRP.Position + look)
		return
	end

	local look = self.HRP.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)

	if look.Magnitude > 0.01 then
		self.HRP.CFrame = CFrame.lookAt(self.HRP.Position, self.HRP.Position + look.Unit)
	end
end

function ManeuverModule:SetBoostAllowed(canBoost: boolean)
	self.BoostAllowed = canBoost == true

	if not self.BoostAllowed then
		self.IsBoosting = false
		self:_setCameraBoosting(false)
		self:_setBoostVFX(false)
	end
end

function ManeuverModule:SetOutOfGasSwinging(enabled: boolean)
	local finalEnabled = enabled == true and self:IsHooking() and self.Config.OutOfGasSwingEnabled ~= false

	if self.OutOfGasSwinging == finalEnabled then
		if finalEnabled then
			self:_createPhysicalSwingRopes()
		end

		return
	end

	self.OutOfGasSwinging = finalEnabled

	if finalEnabled then
		self.IsBoosting = false

		self.ReleaseCarryUntil = 0
		self.ReleaseCarryVelocity = Vector3.zero
		self.GroundSliding = false
		self.GroundSlideVelocity = Vector3.zero

		self:_setCameraBoosting(false)
		self:_setBoostVFX(false)
		self:_setHookAttachedGasVFX(false)
		self:_setCameraEnabled(true)

		self:_createPhysicalSwingRopes()

		self.BodyVelocity.MaxForce = Vector3.zero
		self.BodyVelocity.Velocity = Vector3.zero
		self.BodyGyro.MaxTorque = Vector3.zero

		self.Humanoid.AutoRotate = false
		self.Humanoid.PlatformStand = true
		self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)

		return
	end

	self:_destroyAllPhysicalRopes()
	self:_restoreHumanoidFromRopeMode()

	if self:IsHooking() and self.BoostAllowed then
		self.BodyVelocity.MaxForce = vectorOr(self.Config.MaxForce, Vector3.new(50000, 50000, 50000))
		self.BodyVelocity.P = 400
	end
end

function ManeuverModule:_updatePhysicalRopeSwing(_dt: number): boolean
	if not self.OutOfGasSwinging then
		return false
	end

	if not self:IsHooking() then
		self:SetOutOfGasSwinging(false)
		return false
	end

	self:_createPhysicalSwingRopes()

	self.BodyVelocity.MaxForce = Vector3.zero
	self.BodyVelocity.Velocity = Vector3.zero

	local CFG = self.Config
	local velocity = self.HRP.AssemblyLinearVelocity
	local flatVelocity = self:_flat(velocity)

	if CFG.OutOfGasUseGyro ~= false and flatVelocity.Magnitude > 2 then
		self.BodyGyro.MaxTorque =
			vectorOr(CFG.MaxTorque, Vector3.new(400000, 400000, 400000))
			* numberOr(CFG.OutOfGasGyroTorqueMultiplier, 0.25)

		self.BodyGyro.CFrame = CFrame.lookAt(self.HRP.Position, self.HRP.Position + flatVelocity.Unit)
	else
		self.BodyGyro.MaxTorque = Vector3.zero
	end

	local drag = numberOr(CFG.OutOfGasVelocityDrag, 1)

	if drag < 1 then
		self.HRP.AssemblyLinearVelocity *= math.clamp(drag, 0.95, 1)
	end

	self.Humanoid.AutoRotate = false
	self.Humanoid.PlatformStand = true
	self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	self.LastMoveVelocity = self.HRP.AssemblyLinearVelocity

	self:_setCameraEnabled(true)
	self:_setCameraBoosting(false)
	self:_setBoostVFX(false)
	self:_setHookAttachedGasVFX(false)

	return true
end

---------------------------------------------------------------
-- VFX
---------------------------------------------------------------

function ManeuverModule:_emitParticle(particle: ParticleEmitter, emitCount: number?)
	if not self:_canPlayOwnVFX() then
		return
	end

	local attr = particle:GetAttribute("EmitCount")

	if typeof(attr) == "number" then
		particle:Emit(attr)
	else
		particle:Emit(emitCount or 10)
	end
end

function ManeuverModule:_setVFXEnabled(instance: Instance, enabled: boolean)
	if enabled and not self:_canPlayOwnVFX() then
		return
	end

	if instance:IsA("ParticleEmitter") then
		instance.Enabled = enabled
		return
	end

	if instance:IsA("Trail") then
		instance.Enabled = enabled
		return
	end

	if instance:IsA("Beam") then
		instance.Enabled = enabled
	end
end

function ManeuverModule:_emitLauncherVFX(side: Side)
	local launcherName = if side == "Left" then "LeftLauncher" else "RightLauncher"

	local launcher = self.Character:FindFirstChild(launcherName, true)
	if not launcher then
		warn("[ODM] Missing launcher:", launcherName)
		return
	end

	for _, descendant in launcher:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			if descendant.Name == "Core" or descendant.Name == "CoreMiniSparks" then
				self:_emitParticle(descendant, 10)
			end
		end
	end
end

function ManeuverModule:_setHookAttachedGasVFX(enabled: boolean)
	local gear = self.Character:FindFirstChild("Gear", true)
	if not gear then
		return
	end

	local gasPart = gear:FindFirstChild("GasPart", true)
	if not gasPart then
		return
	end

	for _, descendant in gasPart:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			if descendant.Name == "GAS" then
				self:_setVFXEnabled(descendant, enabled)
			end
		elseif descendant:IsA("Trail") then
			if descendant.Name == "Trail" then
				self:_setVFXEnabled(descendant, enabled)
			end
		end
	end
end

function ManeuverModule:_setTrailEnabled(trailName: string, enabled: boolean)
	local gear = self.Character:FindFirstChild("Gear", true)
	if not gear then
		return
	end

	local gasPart = gear:FindFirstChild("GasPart", true)
	if not gasPart then
		return
	end

	local trail = gasPart:FindFirstChild(trailName, true)

	if trail and trail:IsA("Trail") then
		self:_setVFXEnabled(trail, enabled)
	end
end

function ManeuverModule:_setSideTrails(leftEnabled: boolean, rightEnabled: boolean)
	self:_setTrailEnabled("bootLeft", leftEnabled)
	self:_setTrailEnabled("bootRight", rightEnabled)
end

function ManeuverModule:_updateSideTrails()
	local leftEnabled = false
	local rightEnabled = false

	if self:IsHooking() and not self.OutOfGasSwinging then
		if self.OrbitSide == "Left" or self.OrbitLeftHeld then
			rightEnabled = true
		elseif self.OrbitSide == "Right" or self.OrbitRightHeld then
			leftEnabled = true
		end
	end

	self:_setSideTrails(leftEnabled, rightEnabled)
end

function ManeuverModule:_setBoostVFX(enabled: boolean)
	local gear = self.Character:FindFirstChild("Gear", true)
	if not gear then
		return
	end

	local gasPart = gear:FindFirstChild("GasPart", true)
	if not gasPart then
		return
	end

	for _, descendant in gasPart:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			if descendant.Name == "Jet" or descendant.Name == "Jet2" then
				if enabled == true then
					self:_emitParticle(descendant, 2)
				end
			end

			if descendant.Name == "Smoke" then
				self:_setVFXEnabled(descendant, enabled)
			end
		end
	end
end

function ManeuverModule:_setGroundSlideVFX(enabled: boolean)
	local gear = self.Character:FindFirstChild("Gear", true)
	if not gear then
		return
	end

	for _, scabbardName in { "LeftScabbard", "RightScabbard" } do
		local scabbard = gear:FindFirstChild(scabbardName, true)

		if scabbard then
			local slideAttachment = scabbard:FindFirstChild("SlideAttachment", true)

			if slideAttachment then
				for _, descendant in slideAttachment:GetDescendants() do
					if descendant:IsA("ParticleEmitter") then
						if descendant.Name == "Dirt" or descendant.Name == "Sparks" then
							self:_setVFXEnabled(descendant, enabled)
						end
					end
				end
			end
		end
	end
end

function ManeuverModule:_setGroundSlideVFXFromSpeed(speed: number)
	local CFG = self.Config

	local minSpeed = numberOr(CFG.GroundSlideVFXMinSpeed, 80)
	local maxSpeed = numberOr(CFG.GroundSlideVFXMaxSpeed, 220)

	local enabled = speed >= minSpeed
	local alpha = math.clamp((speed - minSpeed) / math.max(maxSpeed - minSpeed, 1), 0, 1)

	local dirtRate = math.lerp(numberOr(CFG.GroundSlideDirtMinRate, 0), numberOr(CFG.GroundSlideDirtMaxRate, 45), alpha)
	local sparksRate = numberOr(CFG.GroundSlideSparksMinRate, 0) + (numberOr(CFG.GroundSlideSparksMaxRate, 45) * alpha)

	local gear = self.Character:FindFirstChild("Gear", true)
	if not gear then
		return
	end

	for _, scabbardName in { "LeftScabbard", "RightScabbard" } do
		local scabbard = gear:FindFirstChild(scabbardName, true)

		if scabbard then
			local slideAttachment = scabbard:FindFirstChild("SlideAttachment", true)

			if slideAttachment then
				for _, descendant in slideAttachment:GetDescendants() do
					if descendant:IsA("ParticleEmitter") then
						if descendant.Name == "Dirt" then
							descendant.Enabled = enabled and speed >= numberOr(CFG.GroundSlideDirtMinSpeed, 95)
							descendant.Rate = dirtRate
						elseif descendant.Name == "Sparks" then
							descendant.Enabled = enabled and speed >= numberOr(CFG.GroundSlideSparksMinSpeed, 150)
							descendant.Rate = sparksRate
						end
					end
				end
			end
		end
	end
end

function ManeuverModule:_clearAllGearVFX()
	self:_setHookAttachedGasVFX(false)
	self:_setSideTrails(false, false)
	self:_setBoostVFX(false)
	self:_setGroundSlideVFX(false)
end

---------------------------------------------------------------
-- Rope / hooks
---------------------------------------------------------------

function ManeuverModule:_makeHookPart(side: Side, position: Vector3): (Part, Attachment)
	local CFG = self.Config

	local part = Instance.new("Part")
	part.Name = side .. "Hook"
	part.Size = vectorOr(CFG.HookVisualSize, Vector3.new(0.25, 0.25, 0.25))
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CFrame = CFrame.new(position)
	part.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Name = "A1"
	attachment.Parent = part

	return part, attachment
end

function ManeuverModule:_makeRope(origin: Attachment, target: Attachment): Beam
	local CFG = self.Config

	local finalWidth = numberOr(CFG.RopeWidth, 0.08)
	local outWidth = numberOr(CFG.RopeTweenOutWidth, 0.15)

	local beam = Instance.new("Beam")
	beam.Name = "ODMRope"
	beam.Attachment0 = origin
	beam.Attachment1 = target
	beam.FaceCamera = true
	beam.LightInfluence = 0
	beam.Segments = numberOr(CFG.RopeSegments, 50)
	beam.Color = ColorSequence.new(CFG.RopeColor or Color3.fromRGB(45, 35, 25))
	beam.Transparency = NumberSequence.new(0)

	beam.Width0 = 0.01
	beam.Width1 = 0.01
	beam.CurveSize0 = 0
	beam.CurveSize1 = 0

	beam.Parent = self.HRP

	local outTween = TweenService:Create(
		beam,
		TweenInfo.new(numberOr(CFG.RopeTweenOutTime, 0.12), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Width0 = outWidth,
			Width1 = outWidth,
			CurveSize0 = numberOr(CFG.RopeCurveOut0, 8),
			CurveSize1 = numberOr(CFG.RopeCurveOut1, -4),
		}
	)

	outTween:Play()

	task.delay(numberOr(CFG.RopeTweenHoldTime, 0.12), function()
		if not beam.Parent then
			return
		end

		TweenService:Create(
			beam,
			TweenInfo.new(numberOr(CFG.RopeTweenInTime, 0.18), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Width0 = finalWidth,
				Width1 = finalWidth,
				CurveSize0 = numberOr(CFG.RopeCurveIn0, 0),
				CurveSize1 = numberOr(CFG.RopeCurveIn1, 0),
			}
		):Play()
	end)

	return beam
end

function ManeuverModule:_retractRope(rope: Beam?, hookPart: Part?)
	if not rope then
		if hookPart then
			hookPart:Destroy()
		end
		return
	end

	local CFG = self.Config

	local tween = TweenService:Create(
		rope,
		TweenInfo.new(numberOr(CFG.RopeRetractTweenTime, 0.12), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{
			Width0 = 0.01,
			Width1 = 0.01,
			CurveSize0 = numberOr(CFG.RopeRetractCurve0, -4),
			CurveSize1 = numberOr(CFG.RopeRetractCurve1, 8),
		}
	)

	tween:Play()

	tween.Completed:Once(function()
		if rope.Parent then
			rope:Destroy()
		end

		if hookPart and hookPart.Parent then
			hookPart:Destroy()
		end
	end)
end

function ManeuverModule:_lockGroundControl()
	self.Humanoid.WalkSpeed = numberOr(self.Config.GroundHookWalkSpeed, 0)
end

function ManeuverModule:_restoreGroundControl()
	self.Humanoid.WalkSpeed = self.OriginalWalkSpeed

	if self.Humanoid.UseJumpPower then
		self.Humanoid.JumpPower = self.OriginalJumpPower
	else
		self.Humanoid.JumpHeight = self.OriginalJumpHeight
	end
end

function ManeuverModule:_rebuildMomentumFromVelocity()
	local CFG = self.Config
	local speed = self:_flat(self.HRP.AssemblyLinearVelocity).Magnitude

	if speed <= 0 then
		return
	end

	local effectiveSpeed = numberOr(CFG.Speed, 220) * self:_getSpeedMultiplier()
	local rebuilt = (speed / effectiveSpeed) * numberOr(CFG.RehookMomentumFromSpeed, 1)

	self.Momentum = math.clamp(
		math.max(self.Momentum, rebuilt),
		numberOr(CFG.MinRetainedMomentum, 0.35),
		numberOr(CFG.MaxMomentum, 1.8)
	)
end

function ManeuverModule:_onHookAttached()
	self:_updateOrbitFromHeldKeys()
	self:_setCameraEnabled(true)
	self:_cameraImpulse(1.2)
end

function ManeuverModule:_attachHookToHit(hook: HookData, hitResult: RaycastResult)
	local CFG = self.Config
	local wasOutOfGasSwinging = self.OutOfGasSwinging == true

	hook.Traveling = false
	hook.Attached = true
	hook.Fired = true

	hook.HitPart = hitResult.Instance
	hook.HitLocalPosition = hitResult.Instance.CFrame:PointToObjectSpace(hitResult.Position)

	if hook.Hook then
		hook.Hook.CFrame = CFrame.new(hitResult.Position)
		hook.Hook.Anchored = true
	end

	if wasOutOfGasSwinging then
		self.OutOfGasSwinging = true
		self:_createPhysicalSwingRopes()

		self.BodyVelocity.MaxForce = Vector3.zero
		self.BodyVelocity.Velocity = Vector3.zero
		self.BodyGyro.MaxTorque = Vector3.zero

		self.Humanoid.AutoRotate = false
		self.Humanoid.PlatformStand = true
		self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)

		self:_setHookAttachedGasVFX(false)
		self:_setBoostVFX(false)
		self:_setCameraBoosting(false)
		self:_setCameraEnabled(true)

		return
	end

	self.BodyVelocity.MaxForce = vectorOr(CFG.MaxForce, Vector3.new(50000, 50000, 50000))
	self.BodyGyro.MaxTorque = vectorOr(CFG.MaxTorque, Vector3.new(400000, 400000, 400000))

	if self:_isOnGround() then
		self.Humanoid:ChangeState(Enum.HumanoidStateType.Running)
	else
		self.Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	self:_setHookAttachedGasVFX(true)

	self:_rebuildMomentumFromVelocity()
	self:_onHookAttached()
end

function ManeuverModule:_updateTravelingHook(hook: HookData, dt: number)
	local CFG = self.Config

	if not hook.Traveling or not hook.Hook then
		return
	end

	local travelStep = numberOr(CFG.HookTravelSpeed, 2000) * self:_getHookSpeedMultiplier() * dt
	local oldPosition = hook.LastPosition
	local newPosition = oldPosition + hook.Direction * travelStep

	local travelHit = self:_raycast(oldPosition, newPosition - oldPosition)

	if travelHit then
		self:_attachHookToHit(hook, travelHit)
		return
	end

	hook.Hook.CFrame = CFrame.new(newPosition)
	hook.LastPosition = newPosition
	hook.TravelDistance += travelStep

	local originPosition = self.HRP.Position
	local toHook = newPosition - originPosition

	if toHook.Magnitude > 1 then
		local clipHit = self:_raycast(originPosition, toHook)

		if clipHit then
			if clipHit.Instance ~= hook.Hook then
				self:_attachHookToHit(hook, clipHit)
				return
			end
		end
	end

	local maxDistance = numberOr(CFG.HookTravelMaxDistance, numberOr(CFG.GrappleRange, 2000))
	maxDistance *= self:_getHookRangeMultiplier()

	if hook.TravelDistance >= maxDistance then
		if hook == self.LeftHook then
			self:EndGrapple("Left")
		else
			self:EndGrapple("Right")
		end
	end
end

function ManeuverModule:_updateTravelingHooks(dt: number)
	self:_updateTravelingHook(self.LeftHook, dt)
	self:_updateTravelingHook(self.RightHook, dt)
end

function ManeuverModule:_updateAttachedHookTarget(hook: HookData, side: Side)
	if not hook.Attached then
		return
	end

	if not hook.Hook then
		return
	end

	if not hook.HitPart or not hook.HitPart.Parent or not hook.HitLocalPosition then
		self:EndGrapple(side)
		return
	end

	local worldPosition = hook.HitPart.CFrame:PointToWorldSpace(hook.HitLocalPosition)

	hook.Hook.CFrame = CFrame.new(worldPosition)
	hook.LastPosition = worldPosition
end

function ManeuverModule:_updateAttachedHookTargets()
	self:_updateAttachedHookTarget(self.LeftHook, "Left")
	self:_updateAttachedHookTarget(self.RightHook, "Right")
end

function ManeuverModule:_getTargetPosition(): Vector3?
	if self:IsDoubleHooking() then
		if self.LeftHook.Hook and self.RightHook.Hook then
			return (self.LeftHook.Hook.Position + self.RightHook.Hook.Position) / 2
		end
	end

	if self.LeftHook.Attached and self.LeftHook.Hook then
		return self.LeftHook.Hook.Position
	end

	if self.RightHook.Attached and self.RightHook.Hook then
		return self.RightHook.Hook.Position
	end

	return nil
end

function ManeuverModule:_getLookData(targetPosition: Vector3)
	local offset = targetPosition - self.HRP.Position

	if offset.Magnitude <= 0.1 then
		return nil
	end

	local lookVector = offset.Unit
	local distance = offset.Magnitude

	local rightVector = lookVector:Cross(Vector3.new(0, 1, 0))

	if rightVector.Magnitude <= 0.01 then
		rightVector = self.HRP.CFrame.RightVector
	end

	rightVector = rightVector.Unit

	local upVector = rightVector:Cross(lookVector)
	local location = CFrame.fromMatrix(self.HRP.Position, rightVector, upVector)

	return lookVector, distance, rightVector, upVector, location
end

function ManeuverModule:_getOrbitDistance(distance: number): number
	return math.clamp(distance, numberOr(self.Config.MinOrbitDistance, 20), numberOr(self.Config.MaxOrbitDistance, 120))
end

function ManeuverModule:_updateMomentum(hasTarget: boolean)
	local CFG = self.Config

	local minMomentum = numberOr(CFG.MinMomentum, 0.25)
	local maxMomentum = numberOr(CFG.MaxMomentum, 1.8)

	if hasTarget then
		self.Momentum = math.clamp(self.Momentum + numberOr(CFG.MomentumGain, 0.006), minMomentum, maxMomentum)
	else
		self.Momentum = math.clamp(self.Momentum - numberOr(CFG.MomentumLoss, 0.004), minMomentum, maxMomentum)
	end
end

---------------------------------------------------------------
-- V dash
---------------------------------------------------------------

function ManeuverModule:GetDoubleHookTargetPosition(): Vector3?
	if not self:IsDoubleHooking() then
		return nil
	end

	local leftPosition: Vector3? = nil
	local rightPosition: Vector3? = nil

	if self.LeftHook.Hook and self.LeftHook.Hook.Parent then
		leftPosition = self.LeftHook.Hook.Position
	elseif self.LeftHook.HitPart and self.LeftHook.HitLocalPosition then
		leftPosition = self.LeftHook.HitPart.CFrame:PointToWorldSpace(self.LeftHook.HitLocalPosition)
	end

	if self.RightHook.Hook and self.RightHook.Hook.Parent then
		rightPosition = self.RightHook.Hook.Position
	elseif self.RightHook.HitPart and self.RightHook.HitLocalPosition then
		rightPosition = self.RightHook.HitPart.CFrame:PointToWorldSpace(self.RightHook.HitLocalPosition)
	end

	if not leftPosition or not rightPosition then
		return nil
	end

	return leftPosition:Lerp(rightPosition, 0.5)
end

function ManeuverModule:CanVDash(): boolean
	local CFG = self.Config

	if CFG.VDashEnabled == false then
		return false
	end

	if self.VDashing then
		return false
	end

	if os.clock() < self.VDashCooldownUntil then
		return false
	end

	if not self.Character or not self.HRP or not self.Humanoid then
		return false
	end

	if self.Humanoid.Health <= 0 then
		return false
	end

	if CFG.VDashRequiresDoubleHook ~= false and not self:IsDoubleHooking() then
		return false
	end

	if not self.BoostAllowed then
		return false
	end

	return true
end

function ManeuverModule:VDashToPosition(targetPosition: Vector3): boolean
	if self:_isDisabled() then return false end
	
	if not self:CanVDash() then
		return false
	end

	local CFG = self.Config

	local origin = self.HRP.Position
	local offset = targetPosition - origin
	local distance = offset.Magnitude

	local minDistance = numberOr(CFG.VDashMinTargetDistance, 10)
	if distance < minDistance then
		return false
	end

	local direction = offset.Unit

	self.VDashing = true
	self.VDashHeld = true
	self.VDashStartedAt = os.clock()
	self.VDashDirection = direction
	self.VDashTargetPosition = targetPosition

	self:SetOutOfGasSwinging(false)

	self.GroundSliding = false
	self.GroundSlideVelocity = Vector3.zero

	self.BodyVelocity.MaxForce = vectorOr(CFG.MaxForce, Vector3.new(90000, 90000, 90000))
	self.BodyGyro.MaxTorque = vectorOr(CFG.MaxTorque, Vector3.new(30000, 30000, 30000))

	self.Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	self:_setCameraEnabled(true)
	self:_cameraBoostShake(1)
	self:_setCameraBoosting(true)
	self:_setBoostVFX(true)

	return true
end

function ManeuverModule:_updateVDash(_dt: number): boolean
	if not self.VDashing then
		return false
	end

	local CFG = self.Config

	if not self.BoostAllowed then
		self:EndVDash()
		return false
	end

	if CFG.VDashRequiresDoubleHook ~= false and not self:IsDoubleHooking() then
		self:EndVDash()
		return false
	end

	local maxHoldTime = numberOr(CFG.VDashMaxHoldTime, 5)
	if os.clock() - self.VDashStartedAt >= maxHoldTime then
		self:EndVDash()
		return false
	end

	if not self.VDashHeld then
		self:EndVDash()
		return false
	end

	local targetPosition = self:GetDoubleHookTargetPosition()
	if targetPosition then
		self.VDashTargetPosition = targetPosition

		local offset = targetPosition - self.HRP.Position
		if offset.Magnitude >= numberOr(CFG.VDashMinTargetDistance, 10) then
			self.VDashDirection = offset.Unit
		end
	end

	local speed = numberOr(CFG.VDashSpeed, 200) * self:_getSpeedMultiplier()
	local desiredVelocity = self.VDashDirection * speed

	self.BodyVelocity.MaxForce = vectorOr(CFG.MaxForce, Vector3.new(90000, 90000, 90000))
	self.BodyVelocity.Velocity = desiredVelocity

	if self.VDashDirection.Magnitude > 0 then
		self.BodyGyro.MaxTorque = vectorOr(CFG.MaxTorque, Vector3.new(30000, 30000, 30000))
		self.BodyGyro.CFrame = CFrame.lookAt(self.HRP.Position, self.HRP.Position + self.VDashDirection)
	end

	return true
end

function ManeuverModule:EndVDash()
	if not self.VDashing then
		self.VDashHeld = false
		return
	end

	local CFG = self.Config
	local currentVelocity = self.HRP.AssemblyLinearVelocity
	local retention = numberOr(CFG.VDashEndSpeedRetention, 0.7)

	self.HRP.AssemblyLinearVelocity = currentVelocity * retention

	self.VDashing = false
	self.VDashHeld = false
	self.VDashDirection = Vector3.zero
	self.VDashTargetPosition = Vector3.zero
	self.VDashCooldownUntil = os.clock() + numberOr(CFG.VDashCooldown, 1.25)

	self:_setBoostVFX(false)
	self:_setCameraBoosting(false)

	if self:IsHooking() then
		self:_rebuildMomentumFromVelocity()
	else
		self.BodyVelocity.MaxForce = Vector3.zero
		self.BodyVelocity.Velocity = Vector3.zero
		self.BodyGyro.MaxTorque = Vector3.zero
		self:_setCameraEnabled(false)
	end
end

---------------------------------------------------------------
-- Ground slide
---------------------------------------------------------------

function ManeuverModule:_getBestFlatVelocity(): Vector3
	local currentVelocity = self:_flat(self.HRP.AssemblyLinearVelocity)
	local bodyVelocity = self:_flat(self.BodyVelocity.Velocity)
	local lastVelocity = self:_flat(self.LastMoveVelocity)

	local bestVelocity = currentVelocity

	if bodyVelocity.Magnitude > bestVelocity.Magnitude then
		bestVelocity = bodyVelocity
	end

	if lastVelocity.Magnitude > bestVelocity.Magnitude then
		bestVelocity = lastVelocity
	end

	return bestVelocity
end

function ManeuverModule:_stopGroundSlide()
	self.GroundSliding = false
	self.GroundSlideVelocity = Vector3.zero
	self:_setGroundSlideVFX(false)

	self.BodyVelocity.MaxForce = Vector3.zero
	self.BodyVelocity.Velocity = Vector3.zero
	self.BodyGyro.MaxTorque = Vector3.zero

	self.Humanoid.PlatformStand = false
	self.Humanoid.AutoRotate = true
	self:_restoreGroundControl()
end

function ManeuverModule:_updateGroundSlide(dt: number): boolean
	local CFG = self.Config

	local onGround = self:IsSlidingOnGround()
	local isHooking = self:IsHooking()

	local bestVelocity = self:_getBestFlatVelocity()
	local speed = bestVelocity.Magnitude

	local hookedStartSpeed = numberOr(CFG.GroundSlideHookedStartSpeed, 60)
	local releaseStartSpeed = numberOr(CFG.GroundSlideReleaseStartSpeed, 45)
	local stopSpeed = numberOr(CFG.GroundSlideStopSpeed, 10)

	if not onGround then
		if self.GroundSliding then
			self:_stopGroundSlide()
		else
			self:_setGroundSlideVFX(false)
		end

		return false
	end

	local requiredSpeed = if isHooking then hookedStartSpeed else releaseStartSpeed

	if speed < requiredSpeed then
		if self.GroundSliding then
			self:_stopGroundSlide()
		else
			self:_setGroundSlideVFX(false)
		end

		return false
	end

	if not self.GroundSliding then
		self.GroundSliding = true
		self.GroundSlideVelocity = bestVelocity
		self.GroundSlideStartedAt = os.clock()
	end

	local slideVelocity = self:_flat(self.GroundSlideVelocity)
	local slideSpeed = slideVelocity.Magnitude

	self:_setGroundSlideVFXFromSpeed(slideSpeed)

	if slideSpeed <= stopSpeed then
		self:_stopGroundSlide()
		return false
	end

	local dragMultiplier = numberOr(CFG.GroundSlideDragMultiplier, 4)
	local highSpeedThreshold = numberOr(CFG.GroundSlideHighSpeedThreshold, 250)
	local highSpeedDragMultiplier = numberOr(CFG.GroundSlideHighSpeedDragMultiplier, 1.35)

	local dragAmount = slideSpeed * dragMultiplier * dt

	if slideSpeed >= highSpeedThreshold then
		dragAmount *= highSpeedDragMultiplier
	end

	local newSpeed = math.max(slideSpeed - dragAmount, 0)

	if newSpeed <= stopSpeed then
		self:_stopGroundSlide()
		return false
	end

	self.GroundSlideVelocity = slideVelocity.Unit * newSpeed

	self.BodyVelocity.MaxForce = Vector3.new(90000, 0, 90000)
	self.BodyVelocity.P = 1200
	self.BodyVelocity.Velocity = self.GroundSlideVelocity

	self.BodyGyro.MaxTorque = Vector3.zero

	self.Humanoid.PlatformStand = false
	self.Humanoid.AutoRotate = true
	self.Humanoid.WalkSpeed = 0

	self:_setGroundSlideVFX(true)

	return true
end

---------------------------------------------------------------
-- Main movement
---------------------------------------------------------------

function ManeuverModule:_updateMovers(dt: number)
	local CFG = self.Config
	
	if self:_isDisabled() then
		self.BodyVelocity.MaxForce = Vector3.zero
		self.BodyVelocity.Velocity = Vector3.zero
		self.BodyGyro.MaxTorque = Vector3.zero
		if self.GroundSliding then
			self:_stopGroundSlide()
		end
		return
	end

	if not self.Character.Parent then
		return
	end

	if self.Humanoid.Health <= 0 then
		return
	end

	if self._updateVDash and self:_updateVDash(dt) then
		return
	end

	self:_updateTravelingHooks(dt)
	self:_updateAttachedHookTargets()
	self:_updateSideTrails()

	if self:_updatePhysicalRopeSwing(dt) then
		return
	end

	local targetPosition = self:_getTargetPosition()

	local canGroundSlide = self:IsHooking() or self.GroundSliding or os.clock() < self.ReleaseCarryUntil
	local isGroundSliding = false

	if canGroundSlide then
		isGroundSliding = self:_updateGroundSlide(dt)
	else
		self.GroundSliding = false
		self.GroundSlideVelocity = Vector3.zero
		self:_setGroundSlideVFX(false)
	end

	if isGroundSliding and not targetPosition then
		return
	end

	if not targetPosition then
		self:SetOutOfGasSwinging(false)
		self:_updateMomentum(false)

		if os.clock() < self.ReleaseCarryUntil then
			self.BodyVelocity.MaxForce = Vector3.new(35000, 0, 35000)
			self.BodyVelocity.P = 700
			self.BodyVelocity.Velocity = self.ReleaseCarryVelocity

			self.BodyGyro.MaxTorque = Vector3.zero

			self.Humanoid.PlatformStand = false
			self.Humanoid.AutoRotate = true
			self:_restoreGroundControl()

			self:_setCameraEnabled(false)
			self:_setCameraOrbit(nil)

			self.LastMoveVelocity = self.HRP.AssemblyLinearVelocity

			return
		end

		self.BodyVelocity.MaxForce = Vector3.zero
		self.BodyVelocity.Velocity = Vector3.zero
		self.BodyGyro.MaxTorque = Vector3.zero

		self.Humanoid.PlatformStand = false
		self.Humanoid.AutoRotate = true
		self:_restoreGroundControl()

		self:_setCameraEnabled(false)
		self:_setCameraOrbit(nil)

		self.LastMoveVelocity = self.HRP.AssemblyLinearVelocity

		return
	end

	self.ReleaseCarryUntil = 0
	self.ReleaseCarryVelocity = Vector3.zero

	self.GroundSliding = false
	self.GroundSlideVelocity = Vector3.zero

	self:_updateMomentum(true)

	self.Humanoid.AutoRotate = false
	self.Humanoid.PlatformStand = true

	self:_lockGroundControl()

	self.BodyVelocity.MaxForce = vectorOr(CFG.MaxForce, Vector3.new(50000, 50000, 50000)) * 1.1
	self.BodyGyro.MaxTorque = vectorOr(CFG.MaxTorque, Vector3.new(400000, 400000, 400000))

	local lookVector, distance, rightVector, _upVector, location = self:_getLookData(targetPosition)

	if not lookVector then
		return
	end

	self.BodyGyro.CFrame = location

	local boostMultiplier = if self.IsBoosting then numberOr(CFG.BoostMultiplier, 1.3) else 1
	local speed = numberOr(CFG.Speed, 220) * self.Momentum * boostMultiplier * self:_getSpeedMultiplier()

	local targetVelocity: Vector3

	if self.OrbitSide then
		local minOrbit = numberOr(CFG.MinOrbitDistance, 20)
		local orbitDistance = self:_getOrbitDistance(distance)


		local tightenDuration = numberOr(CFG.OrbitTightenDuration, 1.5)
		if tightenDuration > 0 then
			local heldFor = math.max(0, os.clock() - (self.OrbitStartedAt or 0))
			local tightenT = math.clamp(heldFor / tightenDuration, 0, 1)
			orbitDistance = orbitDistance + (minOrbit - orbitDistance) * tightenT
		end

		-- Boosting while orbiting pulls the arc in (lean into the swing)
		-- on top of the existing speed multiplier.
		if self.IsBoosting then
			orbitDistance *= numberOr(CFG.OrbitBoostDistanceMultiplier, 0.8)
		end

		orbitDistance = math.max(orbitDistance, minOrbit * 0.6)

		local sideOffset = if self.OrbitSide == "Left"
			then -rightVector * orbitDistance
			else rightVector * orbitDistance

		local orbitPosition = targetPosition + sideOffset
		local orbitLookVector = orbitPosition - self.HRP.Position

		if orbitLookVector.Magnitude > 0.1 then
			orbitLookVector = orbitLookVector.Unit
		else
			orbitLookVector = lookVector
		end

		local orbitMultiplier = if self.IsBoosting then numberOr(CFG.OrbitBoostMultiplier, 1.25) else 1
		targetVelocity = orbitLookVector * numberOr(CFG.OrbitSpeed, 220) * orbitMultiplier * self:_getSpeedMultiplier()

		if self._orbitEntrySnapPending then
			self._orbitEntrySnapPending = false
			local snapStrength = math.clamp(numberOr(CFG.OrbitEntrySnapStrength, 0.85), 0, 1)
			self.BodyVelocity.Velocity = self.HRP.AssemblyLinearVelocity:Lerp(targetVelocity, snapStrength)
		else
			self.BodyVelocity.Velocity =
				self.HRP.AssemblyLinearVelocity:Lerp(targetVelocity, (numberOr(CFG.OrbitLerpSpeed, 0.08) * 100) * dt)
		end
	else
		targetVelocity = lookVector * speed

		self.BodyVelocity.Velocity =
			self.HRP.AssemblyLinearVelocity:Lerp(targetVelocity, (numberOr(CFG.LerpSpeed, 0.08) * 100) * dt)
	end

	self.LastMoveVelocity = self.BodyVelocity.Velocity
end

---------------------------------------------------------------
-- Public controls
---------------------------------------------------------------

function ManeuverModule:_updateOrbitFromHeldKeys()
	if not self:IsHooking() then
		self:_setCameraOrbit(nil)
		return
	end

	if self.OutOfGasSwinging then
		self:EndOrbit()
		self:_setCameraOrbit(nil)
		return
	end

	if self.OrbitLeftHeld and not self.OrbitRightHeld then
		self:Orbit("Left")
		self:_setCameraOrbit("Left")
	elseif self.OrbitRightHeld and not self.OrbitLeftHeld then
		self:Orbit("Right")
		self:_setCameraOrbit("Right")
	elseif self.OrbitLeftHeld and self.OrbitRightHeld and self.LastOrbitSide then
		self:Orbit(self.LastOrbitSide)
		self:_setCameraOrbit(self.LastOrbitSide)
	else
		self:EndOrbit()
		self:_setCameraOrbit(nil)
	end
end

function ManeuverModule:BeginGrapple(side: Side, target: Vector3): boolean
	local CFG = self.Config
	
	if self:_isDisabled() then return false end

	self:EndGrapple(side)
	self:_rebuildMomentumFromVelocity()

	local hook = self:_getHook(side)
	local origin = self:_getOrigin(side)

	if not origin then
		warn("[ODM] BeginGrapple aborted: launcher attachment not present yet for side " .. tostring(side))
		return false
	end

	self:_emitLauncherVFX(side)

	local startPosition = origin.WorldPosition
	local aimDirection = target - startPosition

	if aimDirection.Magnitude <= 0 then
		return false
	end

	local grappleRange = numberOr(CFG.GrappleRange, 2000) * self:_getHookRangeMultiplier()

	if aimDirection.Magnitude > grappleRange then
		aimDirection = aimDirection.Unit * grappleRange
	end

	local direction = aimDirection.Unit
	local hookPart, hookAttachment = self:_makeHookPart(side, startPosition)
	local rope = self:_makeRope(origin, hookAttachment)

	hook.Fired = true
	hook.Traveling = true
	hook.Attached = false
	hook.Hook = hookPart
	hook.Rope = rope
	hook.Attachment = hookAttachment
	hook.Direction = direction
	hook.LastPosition = startPosition
	hook.TravelDistance = 0
	hook.HitPart = nil
	hook.HitLocalPosition = nil
	hook.PhysicalRope = nil

	return true
end

function ManeuverModule:EndGrapple(side: Side)
	local hook = self:_getHook(side)
	local wasHooking = self:IsHooking()
	local wasOutOfGasSwinging = self.OutOfGasSwinging == true

	self:_destroyPhysicalRope(side)

	hook.Fired = false
	hook.Traveling = false
	hook.Attached = false
	hook.Direction = Vector3.zero
	hook.LastPosition = Vector3.zero
	hook.TravelDistance = 0
	hook.HitPart = nil
	hook.HitLocalPosition = nil
	hook.PhysicalRope = nil

	local rope = hook.Rope
	local hookPart = hook.Hook

	hook.Rope = nil
	hook.Hook = nil

	self:_retractRope(rope, hookPart)

	hook.Attachment = nil

	if side == "Left" then
		self.OrbitLeftHeld = false
	else
		self.OrbitRightHeld = false
	end

	if wasHooking and not self:IsHooking() then
		self.OutOfGasSwinging = false
		self:_destroyAllPhysicalRopes()

		if wasOutOfGasSwinging then
			self:_restoreHumanoidFromRopeMode()
		end

		local CFG = self.Config

		local currentVelocity = self.HRP.AssemblyLinearVelocity
		local bestFlat = self:_getBestFlatVelocity()

		local releaseFlat = bestFlat * numberOr(CFG.SpeedRetentionMultiplier, 1)
		releaseFlat *= numberOr(CFG.ReleaseForwardBoost, 1.08)

		local maxReleaseSpeed = numberOr(CFG.MaxReleaseSpeed, 260)
		if releaseFlat.Magnitude > maxReleaseSpeed then
			releaseFlat = releaseFlat.Unit * maxReleaseSpeed
		end

		local releaseY = currentVelocity.Y * numberOr(CFG.ReleaseVerticalPreserve, 1)
		releaseY = math.min(releaseY, numberOr(CFG.MaxUpwardReleaseSpeed, 110))

		local finalVelocity = Vector3.new(releaseFlat.X, releaseY, releaseFlat.Z)

		self.HRP.AssemblyLinearVelocity = finalVelocity
		self.LastMoveVelocity = finalVelocity

		self.ReleaseCarryUntil = os.clock() + numberOr(CFG.ReleaseCarryTime, 0.35)
		self.ReleaseCarryVelocity = releaseFlat

		if self:_isOnGround() and releaseFlat.Magnitude >= numberOr(CFG.GroundSlideReleaseStartSpeed, 45) then
			self.GroundSliding = true
			self.GroundSlideVelocity = releaseFlat
			self.GroundSlideStartedAt = os.clock()
		end

		self.BodyVelocity.MaxForce = Vector3.new(35000, 0, 35000)
		self.BodyVelocity.P = 700
		self.BodyVelocity.Velocity = self.ReleaseCarryVelocity

		self.BodyGyro.MaxTorque = Vector3.zero

		self:_setHookAttachedGasVFX(false)
		self:_setSideTrails(false, false)
		self:_setBoostVFX(false)

		self:_setCameraEnabled(false)
		self:_setCameraOrbit(nil)

		self.Humanoid.PlatformStand = false
		self.Humanoid.AutoRotate = true
		self:_restoreGroundControl()
	else
		self:_updateOrbitFromHeldKeys()
	end
end

function ManeuverModule:SetBoost(boosting: boolean)
	
	if self:_isDisabled() then return false end
	
	local wantsBoost = boosting == true

	if wantsBoost and not self.BoostAllowed then
		self.IsBoosting = false
		self:_setCameraBoosting(false)
		self:_setBoostVFX(false)

		if self:IsHooking() then
			self:SetOutOfGasSwinging(true)
		end

		return
	end

	self.IsBoosting = wantsBoost

	if self.IsBoosting then
		self:SetOutOfGasSwinging(false)
	end

	self:_setCameraBoosting(self.IsBoosting)

	local shouldPlayBoostVFX = self.IsBoosting and self:IsHooking()
	self:_setBoostVFX(shouldPlayBoostVFX)

	if shouldPlayBoostVFX then
		self:_setHookAttachedGasVFX(true)
	end
end

function ManeuverModule:SetOrbitHeld(side: Side, held: boolean)
	if self:_isDisabled() then return false end
	
	if side == "Left" then
		self.OrbitLeftHeld = held == true
	else
		self.OrbitRightHeld = held == true
	end

	self:_updateOrbitFromHeldKeys()
end

function ManeuverModule:Orbit(side: Side)
	if not self:IsHooking() then
		return
	end

	if self.OutOfGasSwinging then
		return
	end

	if self.OrbitSide ~= side then
		self.OrbitStartedAt = os.clock()
		self._orbitEntrySnapPending = true
	end

	self.OrbitSide = side
	self.LastOrbitSide = side
end

function ManeuverModule:EndOrbit()
	self.OrbitSide = nil
	self.OrbitStartedAt = 0
	self._orbitEntrySnapPending = false
end

function ManeuverModule:ApplyPreset(presetName: string)
	self.Config = GearConfig.GetPreset(presetName)
end

function ManeuverModule:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end

	table.clear(self._connections)

	self.OutOfGasSwinging = false
	self:_destroyAllPhysicalRopes()

	self:EndGrapple("Left")
	self:EndGrapple("Right")

	if self.BodyVelocity then
		self.BodyVelocity:Destroy()
	end

	if self.BodyGyro then
		self.BodyGyro:Destroy()
	end

	if self.Humanoid and self.Humanoid.Parent then
		self.Humanoid.PlatformStand = false
		self.Humanoid.AutoRotate = true
		self:_restoreGroundControl()
	end

	self:_clearAllGearVFX()

	self:_setCameraEnabled(false)
	self:_setCameraBoosting(false)
	self:_setCameraOrbit(nil)
end

return ManeuverModule