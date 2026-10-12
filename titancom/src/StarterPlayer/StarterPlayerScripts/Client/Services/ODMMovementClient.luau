-- StarterPlayerScripts.Client.Services.ODMMovementClient
--
-- ODM movement, a straight port of the reference gear's LocalGear script.
-- GearServiceClient creates one per equip (ODMMovementClient.new) and
-- destroys it on unequip; blades, attacks and handles stay in
-- GearServiceClient.
--
-- Keys (raw, like the reference):
--   Q / E          fire a hook at the mouse (hold), release to retract
--   A / D          strafe around the hook(s)            (hooked, airborne)
--   W / S          thrust up / down                     (hooked, airborne)
--   Space          boost towards the hook(s); on the ground, a gas flip
--   LeftShift      hold, release to burst towards the mouse (airborne)
--   V              burst towards the hook(s)            (hooked, airborne)
--   LeftControl    brake (unhooked) / repel (hooked)
--
-- Physics: everything is forces on the HumanoidRootPart (built by the server
-- on equip, see ODMGearParts.buildForces) while the Humanoid PlatformStands.
-- The server ties a RopeConstraint to each hook (ODMWireService) and reels it
-- in while boosting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Networker = require(ReplicatedStorage.Packages.Networker)
local CameraShaker = require(ReplicatedStorage.Shared.Modules.CameraShaker)
local ODMGearParts = require(ReplicatedStorage.Shared.Gear.ODMGearParts)
local ODMMovementConfig = require(ReplicatedStorage.Shared.Configs.Gear.ODMMovementConfig)

local LocalPlayer = Players.LocalPlayer
local CFG = ODMMovementConfig
local GAS = CFG.Gas
local UI = CFG.UI

local ODMMovementClient = {}

-- Server -> client events go to the live controller.
local active = nil
local handlers = {}
function handlers.splatEnded()
	if active then
		active:_onSplatEnded()
	end
end
local networker = Networker.client.new("ODMWireService", handlers)

------------------------------------------------------------
-- Animations
------------------------------------------------------------

local function newDummyTrack()
	local noop = function() end
	return {
		IsPlaying = false,
		TimePosition = 0,
		Play = noop,
		Stop = noop,
		AdjustWeight = noop,
		Dummy = true,
	}
end

local function findAnimation(name: string): Animation?
	local names = { name }
	for _, fallback in CFG.AnimationFallbacks[name] or {} do
		table.insert(names, fallback)
	end
	for _, candidate in names do
		for _, path in CFG.AnimationFolders do
			local node: Instance? = ReplicatedStorage
			for _, part in path do
				node = node and node:FindFirstChild(part)
			end
			local animation = node and node:FindFirstChild(candidate)
			if animation and animation:IsA("Animation") then
				return animation
			end
		end
	end
	return nil
end

local function loadTrack(animator: Animator, name: string): any
	local animation = findAnimation(name)
	if not animation then
		return newDummyTrack()
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return newDummyTrack()
	end
	local priority = CFG.AnimationPriorities[name]
	if priority then
		track.Priority = priority
	end
	return track
end

-- Starts a looping track without restarting it every step.
local function play(track)
	if not track.IsPlaying then
		track:Play()
	end
end

------------------------------------------------------------
-- UI
------------------------------------------------------------

-- An ImageLabel that draws `bars` (offset rects) when it has no image, with
-- the bars following the label's ImageColor3 / ImageTransparency.
local function shapeLabel(name: string, image: string, size: UDim2, bars: { { number } }): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = size
	label.Image = image
	if image == "" then
		local parts = {}
		for _, bar in bars do
			local frame = Instance.new("Frame")
			frame.BorderSizePixel = 0
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.new(0.5, bar[1], 0.5, bar[2])
			frame.Size = UDim2.fromOffset(bar[3], bar[4])
			frame.Parent = label
			table.insert(parts, frame)
		end
		local function sync()
			for _, frame in parts do
				frame.BackgroundColor3 = label.ImageColor3
				frame.BackgroundTransparency = label.ImageTransparency
			end
		end
		label:GetPropertyChangedSignal("ImageColor3"):Connect(sync)
		label:GetPropertyChangedSignal("ImageTransparency"):Connect(sync)
		sync()
	end
	return label
end

local function buildCursorFollow(parent: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CursorFollow"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50

	local block = Instance.new("Frame")
	block.Name = "Block"
	block.BackgroundTransparency = 1
	block.Size = UDim2.fromOffset(1, 1)
	block.AnchorPoint = Vector2.new(0.5, 0.5)
	block.Parent = gui

	local crosshair = shapeLabel("CROSSHAIR", UI.CrosshairImage, UDim2.fromOffset(26, 26), {
		{ 0, -8, 2, 8 },
		{ 0, 8, 2, 8 },
		{ -8, 0, 8, 2 },
		{ 8, 0, 8, 2 },
	})
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.ImageColor3 = UI.CrosshairColor
	crosshair.Parent = block

	for _, name in { "LT_BEAM", "LB_BEAM", "RT_BEAM", "RB_BEAM" } do
		local beam = shapeLabel(name, UI.BeamImage, UDim2.fromOffset(30, 30), { { 0, 0, 2, 14 } })
		beam.Position = UDim2.new(0, 0, 0, 0)
		beam.Rotation = 180
		beam.ImageTransparency = 1
		beam.ImageColor3 = UI.CrosshairColor
		beam.Parent = block
	end

	gui.Parent = parent
	return gui
end

local function buildGasTank(parent: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "GASTANK"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -24, 1, -24)
	holder.Size = UDim2.fromOffset(44, 120)
	holder.Parent = gui

	for i, side in { "Left", "Right" } do
		local tank = Instance.new("Frame")
		tank.Name = side .. "Tank"
		tank.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		tank.BackgroundTransparency = 0.4
		tank.BorderSizePixel = 0
		tank.Position = UDim2.new((i - 1) * 0.55, 0, 0, 0)
		tank.Size = UDim2.fromScale(0.45, 1)
		tank.Parent = holder

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = tank

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(200, 200, 200)
		stroke.Transparency = 0.5
		stroke.Parent = tank

		local fill = Instance.new("Frame")
		fill.Name = "Tank"
		fill.BackgroundColor3 = Color3.fromRGB(225, 225, 225)
		fill.BorderSizePixel = 0
		fill.AnchorPoint = Vector2.new(0, 1)
		fill.Position = UDim2.fromScale(0, 1)
		fill.Size = UDim2.fromScale(1, 0)
		fill.Parent = tank

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 4)
		fillCorner.Parent = fill
	end

	gui.Parent = parent
	return gui
end

local function buildEyes(parent: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Eyes"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40

	local mask = Instance.new("Frame")
	mask.Name = "Mask"
	mask.BackgroundColor3 = Color3.new(0, 0, 0)
	mask.BackgroundTransparency = 1
	mask.BorderSizePixel = 0
	mask.Size = UDim2.fromScale(1, 1)
	mask.Parent = gui

	for _, entry in { { "Vignette", UI.VignetteImage }, { "Visor", UI.VisorImage }, { "Glass", UI.GlassImage } } do
		local image = Instance.new("ImageLabel")
		image.Name = entry[1]
		image.Image = entry[2]
		image.BackgroundTransparency = 1
		image.ImageTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Parent = gui
	end

	gui.Parent = parent
	return gui
end

------------------------------------------------------------
-- Controller
------------------------------------------------------------

export type Options = {
	IsArmed: () -> boolean,
	CameraService: any?,
}

function ODMMovementClient.new(character: Model, options: Options)
	local self = {}

	local Humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid
	local RootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart
	if not Humanoid or not RootPart then
		return nil
	end

	local BodyGyro = RootPart:WaitForChild("BodyGyro", 10) :: AlignOrientation
	local BoostForce = RootPart:WaitForChild("BoostForce", 10) :: LinearVelocity
	local BoostGyro = RootPart:WaitForChild("BoostGyro", 10) :: BodyGyro
	local HookForce = RootPart:WaitForChild("HookForce", 10) :: VectorForce
	local StrafeForce = RootPart:WaitForChild("StrafeForce", 10) :: VectorForce
	local DragForce = RootPart:WaitForChild("DragForce", 10) :: VectorForce
	local FlipForce = RootPart:WaitForChild("FlipForce", 10) :: VectorForce
	local VerticalForce = RootPart:WaitForChild("VerticalForce", 10) :: VectorForce
	if not (BodyGyro and BoostForce and BoostGyro and HookForce and StrafeForce and DragForce and FlipForce and VerticalForce) then
		warn("[ODMMovementClient] Movers missing on the HumanoidRootPart; is the gear equipped on the server?")
		return nil
	end

	local Mouse = LocalPlayer:GetMouse()
	local CurrentCamera = workspace.CurrentCamera
	local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
	local CameraService = options.CameraService

	local CursorFollow = buildCursorFollow(PlayerGui)
	local Tankgui = buildGasTank(PlayerGui)
	local Eyes = buildEyes(PlayerGui)
	local Block = CursorFollow.Block

	local connections = {}
	local destroyed = false

	-- << CONSTANTS >> --
	local MaxHookDistance = CFG.MaxHookDistance
	local StrafePower = CFG.StrafePower
	local VerticalPower = CFG.VerticalPower
	local ReelSpeed = CFG.ReelSpeed
	local HookSpeed = CFG.HookSpeed
	local GasDrainSpeed = CFG.GasDrainSpeed
	local GasCrossfeedSpeed = CFG.GasCrossfeedSpeed
	local MaxGasInLeftTank = CFG.MaxGasInLeftTank
	local MaxGasInRightTank = CFG.MaxGasInRightTank

	-- << VARIABLES >> --
	local PreviousTickVelocity = 0
	local PreviousPlatformStand = false
	local Reeling = false
	local OrbitSide: string? = nil
	local ReelCurve = 0 -- -1 (A) .. 1 (D), eased towards the held key
	local SlowReelHeld = false
	local ReleaseHeld = false
	local RopeMode: string? = nil
	local ReelStartTime = 0
	local ReelMomentum = 0
	local Splat = false
	local OnGround = true
	local Obstructed = false
	local Repel = false
	local UpStrafe = false
	local DownStrafe = false
	local LeftStrafe = false
	local RightStrafe = false
	local Boost = false
	local CanBurst = true
	local Bursting = false
	local Braking = false
	local LeftHooking = false
	local RightHooking = false
	local LeftHookAttachPoint = Vector3.zero
	local RightHookAttachPoint = Vector3.zero
	local LeftHookAttached = false
	local RightHookAttached = false
	local LeftCursorLaunch = false
	local LeftCursorStick = false
	local RightCursorLaunch = false
	local RightCursorStick = false
	local ForwardPlaying = false
	local StrafeBlock = false
	local GasInLefttank = CFG.StartGasInLeftTank
	local GasInRightTank = CFG.StartGasInRightTank
	local HookBoosting = false
	local BoostPrep = false
	local HookL = false
	local HookR = false
	local Sliding = false

	-- Moving hook targets: the hook point rides along in the target's space.
	local LeftHookTarget: BasePart? = nil
	local RightHookTarget: BasePart? = nil
	local LeftHookOffset = Vector3.zero
	local RightHookOffset = Vector3.zero

	local CurrentForwardAnim = nil

	local function boolValue(name: string): BoolValue
		local existing = character:FindFirstChild(name)
		if existing and existing:IsA("BoolValue") then
			existing.Value = false
			return existing
		end
		local value = Instance.new("BoolValue")
		value.Name = name
		value.Parent = character
		return value
	end
	local hboost = boolValue("hboost")
	local hboost2 = boolValue("hboost2")
	local Flip = boolValue("Flip")
	local SlideValue = boolValue("Sliding")

	-- << ANIMATIONS >> --
	local Animator = Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", Humanoid)
	local FastFlip = loadTrack(Animator, "FastFlip")
	local SlowFlip = loadTrack(Animator, "SlowFlip")
	local GroundSlide = loadTrack(Animator, "GroundSlide")
	local RHShot = loadTrack(Animator, "EHookShoot")
	local LHShot = loadTrack(Animator, "QHookShoot")
	local BurstFlip = loadTrack(Animator, "Boost")
	local FallingAnim = loadTrack(Animator, "Falling")
	local HookedBoost = loadTrack(Animator, "HookedBoost")
	local HookedBoostIdle = loadTrack(Animator, "HookedBoostIdle")
	local ForwardHooking = loadTrack(Animator, "ForwardHooking")
	local GasFlip = loadTrack(Animator, "GasFlip")
	local ForwardAnims = {}
	for i = 1, 5 do
		local track = loadTrack(Animator, "ForwardODM" .. i)
		if typeof(track) ~= "table" then -- real AnimationTrack, not a dummy
			table.insert(ForwardAnims, track)
		end
	end
	if #ForwardAnims == 0 then
		table.insert(ForwardAnims, newDummyTrack())
	end
	local allTracks = {
		FastFlip, SlowFlip, GroundSlide, RHShot, LHShot, BurstFlip, FallingAnim,
		HookedBoost, HookedBoostIdle, ForwardHooking, GasFlip,
	}
	for _, track in ForwardAnims do
		table.insert(allTracks, track)
	end

	-- << FUNCTIONS >> --
	UserInputService.MouseIconEnabled = false

	local BoostShakeParams = CameraShaker.new(Enum.RenderPriority.Camera.Value + 1, function(shakeCFrame)
		CurrentCamera.CFrame = CurrentCamera.CFrame * shakeCFrame
	end)

	-- Effects replicate through the server; only send when the state changes.
	local effectState = {}
	local soundState = {}
	local function setEffect(key: string, enabled: boolean)
		if effectState[key] == enabled then
			return
		end
		effectState[key] = enabled
		networker:fire("effect", "ToggleEffect", key, enabled)
	end
	local function setSound(key: string, playing: boolean)
		if soundState[key] == playing then
			return
		end
		soundState[key] = playing
		networker:fire("effect", "ToggleSound", key, playing)
	end
	local function impulseSound(key: string)
		networker:fire("effect", "ImpulseSound", key)
	end

	local function GasDrain(DrainAmt: number, Tank: string): boolean
		if Tank == "Left" then
			if (GasInLefttank - DrainAmt) >= 0 then
				GasInLefttank -= DrainAmt
				return true
			end
		end

		if Tank == "Right" then
			if (GasInRightTank - DrainAmt) >= 0 then
				GasInRightTank -= DrainAmt
				return true
			end
		end

		if Tank == "Both" then
			local LDrain = DrainAmt / 2
			local RDrain = DrainAmt / 2

			if (GasInLefttank - LDrain) >= 0 and (GasInRightTank - RDrain) >= 0 then
				GasInLefttank -= LDrain
				GasInRightTank -= RDrain
				return true
			end
		end

		return false
	end

	local function ImpulseFX(enabled: boolean)
		for _, emitter in ODMGearParts.getImpulseEmitters(character) do
			(emitter :: ParticleEmitter).Enabled = enabled
		end
	end

	local function CancelHBurst()
		task.spawn(function()
			hboost.Value = false
			hboost2.Value = false
			BoostForce.Enabled = false
			BoostForce.VectorVelocity = Vector3.zero
			BoostGyro.P = 0
			BoostGyro.MaxTorque = Vector3.zero
			task.wait(0.1)
			Bursting = false
			task.wait(CFG.BurstCooldown)
			CanBurst = true
		end)
	end

	local function GasCrossfeed()
		if GasInLefttank <= 0 and GasInRightTank <= 0 then
			return
		end
		if GasInLefttank == GasInRightTank then
			return
		end
		local CrossfeedTickPercent = GasCrossfeedSpeed / 60 * (if not Boost then 2 else 1)

		if GasInLefttank > GasInRightTank then
			GasInLefttank -= CrossfeedTickPercent
			GasInRightTank += CrossfeedTickPercent
		end

		if GasInRightTank > GasInLefttank then
			GasInRightTank -= CrossfeedTickPercent
			GasInLefttank += CrossfeedTickPercent
		end
	end

	local function GasVisualizer()
		local LeftGasPercent = GasInLefttank / MaxGasInLeftTank
		local RightGasPercent = GasInRightTank / MaxGasInRightTank
		Tankgui.Holder.LeftTank.Tank.Size = UDim2.new(1, 0, LeftGasPercent, 0)
		Tankgui.Holder.RightTank.Tank.Size = UDim2.new(1, 0, RightGasPercent, 0)
	end

	local function GasTick()
		local DrainTickPercent = GasDrainSpeed / 60

		if LeftHookAttached and Boost then
			GasDrain(DrainTickPercent, "Left")
		end
		if RightHookAttached and Boost then
			GasDrain(DrainTickPercent, "Right")
		end
	end

	local function CalculateVelocity(): Vector3
		return RootPart.AssemblyLinearVelocity
	end

	local function GetDistance(PointA: Vector3, PointB: Vector3): number
		return (PointB - PointA).Magnitude
	end

	local function GetVector3ToPoint(Origin: Vector3, Point: Vector3): Vector3
		return (Point - Origin).Unit
	end

	local function BoostShake()
		for _ = 1, 2 do
			BoostShakeParams:Start()
			BoostShakeParams:ShakeOnce(5, 10, 0, 1.5)
			task.wait(0.25)
		end
	end

	local function FlipShake()
		for _ = 1, 2 do
			BoostShakeParams:Start()
			BoostShakeParams:ShakeOnce(5, 5, 0, 1)
			task.wait(0.1)
		end
	end

	-- The camera service sets the FOV every frame, so the flip punch goes
	-- through its override.
	local function FlipTween()
		local value = Instance.new("NumberValue")
		value.Value = CurrentCamera.FieldOfView
		local function apply()
			if CameraService and CameraService.SetFOVOverride then
				CameraService:SetFOVOverride(value.Value)
			else
				CurrentCamera.FieldOfView = value.Value
			end
		end
		value.Changed:Connect(apply)
		local tween = TweenService:Create(
			value,
			TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In, 0, true, 0),
			{ Value = CFG.FlipFieldOfView }
		)
		tween.Completed:Once(function()
			if CameraService and CameraService.SetFOVOverride then
				CameraService:SetFOVOverride(nil)
			end
			value:Destroy()
		end)
		tween:Play()
	end

	local function SplatFunction(Timeout: number)
		TweenService:Create(Eyes.Mask, TweenInfo.new(0.05), { BackgroundTransparency = 0.2 }):Play()
		TweenService:Create(Eyes.Vignette, TweenInfo.new(0.05), { ImageTransparency = 0 }):Play()
		TweenService:Create(Eyes.Visor, TweenInfo.new(0.05), { ImageTransparency = 0 }):Play()
		TweenService:Create(Eyes.Glass, TweenInfo.new(0.05), { ImageTransparency = 0 }):Play()
		Splat = true
		Boost = false
		BoostPrep = false
		StrafeBlock = true
		BodyGyro.Enabled = false
		networker:fire("splat", Timeout)
		CancelHBurst()
		task.wait(2.5 + Timeout)
		if destroyed then
			return
		end
		TweenService:Create(Eyes.Mask, TweenInfo.new(2.5), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(Eyes.Vignette, TweenInfo.new(2.5), { ImageTransparency = 1 }):Play()
		TweenService:Create(Eyes.Visor, TweenInfo.new(2.5), { ImageTransparency = 1 }):Play()
		TweenService:Create(Eyes.Glass, TweenInfo.new(2.5), { ImageTransparency = 1 }):Play()
	end

	local function launchTime(side: string, point: Vector3): number
		local firePoint = ODMGearParts.getFirePoint(character, side)
		local origin = if firePoint then firePoint.WorldPosition else RootPart.Position
		return GetDistance(point, origin) / HookSpeed
	end

	local function FireHook(Side: string, Point: Vector3, Target: BasePart)
		if not options.IsArmed() then
			return
		end

		if Side == "Left" then
			task.spawn(function()
				local Success = GasDrain(GAS.HookFire, "Left")
				if not Success then
					return
				end
				if LeftHooking or LeftHookAttached then
					return
				end
				LeftHookAttachPoint = Point
				LeftHookTarget = Target
				LeftHookOffset = Target.CFrame:PointToObjectSpace(Point)
				LHShot:Play()
				local Time = launchTime("Left", Point)
				LeftHooking = true
				networker:fire("attachHook", "Left", LeftHookAttachPoint, Time, Target)
				impulseSound("Shot")
				task.wait(Time)
				LeftHookAttached = true
				LeftHooking = false
			end)
		else
			task.spawn(function()
				local Success = GasDrain(GAS.HookFire, "Right")
				if not Success then
					return
				end
				if RightHooking or RightHookAttached then
					return
				end
				RightHookAttachPoint = Point
				RightHookTarget = Target
				RightHookOffset = Target.CFrame:PointToObjectSpace(Point)
				RHShot:Play()
				local Time = launchTime("Right", Point)
				RightHooking = true
				networker:fire("attachHook", "Right", RightHookAttachPoint, Time, Target)
				impulseSound("Shot")
				task.wait(Time)
				RightHookAttached = true
				RightHooking = false
			end)
		end
	end

	local function RetractHook(Side: string, Auto: boolean?, force: boolean?)
		if not force and not options.IsArmed() then
			return
		end
		if Side == "Left" then
			GasDrain(GAS.HookRetract, "Left")
			if not (LeftHooking or LeftHookAttached) then
				return
			end
			if LeftHooking then
				repeat
					task.wait()
				until not LeftHooking
			end
			LeftHookAttached = false
			HookL = true
			local Time = launchTime("Left", LeftHookAttachPoint)
			LeftHookAttachPoint = Vector3.zero
			LeftHookTarget = nil
			networker:fire("retractHook", "Left", Auto == true, Time)
			impulseSound("Retract")
			task.wait(Time + 0.1)
			HookL = false
			LeftHooking = false
		else
			GasDrain(GAS.HookRetract, "Left")
			if not (RightHooking or RightHookAttached) then
				return
			end
			if RightHooking then
				repeat
					task.wait()
				until not RightHooking
			end
			RightHookAttached = false
			HookR = true
			local Time = launchTime("Right", RightHookAttachPoint)
			RightHookAttachPoint = Vector3.zero
			RightHookTarget = nil
			networker:fire("retractHook", "Right", Auto == true, Time)
			impulseSound("Retract")
			task.wait(Time + 0.1)
			HookR = false
			RightHooking = false
		end
	end

	local function CalculateWireResultant(Side: string): Vector3
		local Origin = RootPart.Position
		if Side == "Left" then
			return LeftHookAttachPoint - Origin
		end
		return RightHookAttachPoint - Origin
	end

	local function GetMeanHook(): Vector3
		if LeftHookAttached and RightHookAttached then
			return LeftHookAttachPoint:Lerp(RightHookAttachPoint, 0.5)
		end
		if LeftHookAttached and not RightHookAttached then
			return LeftHookAttachPoint
		end
		if RightHookAttached and not LeftHookAttached then
			return RightHookAttachPoint
		end
		return Vector3.zero
	end

	local function CalculateVerticalCompensation(): number
		local HookPoint = GetMeanHook()
		local MaxCompensation = 50
		local Force

		local Difference = RootPart.Position.Y - HookPoint.Y
		local AbsoluteDifference = math.abs(Difference)

		if AbsoluteDifference < 50 then
			Force = 0
		elseif AbsoluteDifference > 150 then
			Force = if Difference < 0 then MaxCompensation else -MaxCompensation
		else
			local Steepness = 0.05
			Force = MaxCompensation * math.log(Steepness * (AbsoluteDifference - MaxCompensation) + 1)
			Force = if Difference < 0 then Force else -Force
			Force = math.clamp(Force, -MaxCompensation, MaxCompensation)
		end

		return Force
	end

	local function CalculateBoostVelocity(ForceResultant: Vector3): Vector3
		local VelocityVector = CalculateVelocity()
		local Speed = VelocityVector.Magnitude
		local V_Unit = if Speed > 0 then VelocityVector.Unit else Vector3.zero

		local Force = ForceResultant * ReelSpeed
		local GlobalModifier = if Speed >= 250 then 0.1 else 1

		local GravityConstant = if Humanoid.PlatformStand then 1 else 1.5
		local GravityCompensation = Vector3.new(0, workspace.Gravity * RootPart.AssemblyMass, 0) * GravityConstant

		local HookConstant = 0.5
		local HookComponent = V_Unit * ReelSpeed * HookConstant

		local VerticalPush = Vector3.new(0, 1, 0) * VerticalPower

		local VerticalConstant = 1
		local VerticalCompensation = Vector3.new(0, CalculateVerticalCompensation() * VerticalConstant, 0)

		return (((Force + HookComponent) + VerticalPush) * GlobalModifier) + GravityCompensation + (VerticalCompensation * 0.25)
	end

	-- Horizontal direction round the hook point: Left goes round to the left,
	-- Right to the right. Zero when directly above or below it.
	local function orbitTangent(toHook: Vector3, Side: string): Vector3
		local flat = Vector3.new(toHook.X, 0, toHook.Z)
		if flat.Magnitude < 0.5 then
			return Vector3.zero
		end
		local tangent = flat.Unit:Cross(Vector3.yAxis)
		return if Side == "Left" then -tangent else tangent
	end

	-- Hybrid reel: steer velocity towards the hook(s) at a speed that builds
	-- with momentum, fading in over BlendTime. Gravity is cancelled while
	-- reeling so the reel line is straight.
	local function CalculateReelForce(Velocity: Vector3, dt: number): Vector3
		local R = CFG.Reel
		local now = os.clock()
		local speed = Velocity.Magnitude
		if not Reeling then
			Reeling = true
			ReelStartTime = now
			ReelMomentum = math.clamp(speed / R.Speed, R.MinMomentum, R.MaxMomentum)
		end
		ReelMomentum = math.min(R.MaxMomentum, ReelMomentum + R.MomentumGain * dt)

		local toHook = GetMeanHook() - RootPart.Position
		local distance = toHook.Magnitude
		if distance < 0.01 then
			return Vector3.new(0, workspace.Gravity * RootPart.AssemblyMass, 0)
		end
		local arrive = math.clamp(distance / R.ArriveDistance, 0.2, 1)
		-- A/D bend the reel line to that side so you spiral in.
		local direction = toHook.Unit
		if ReelCurve ~= 0 then
			local bent = direction + orbitTangent(toHook, "Right") * ReelCurve * R.StrafeCurve
			if bent.Magnitude > 0.01 then
				direction = bent.Unit
			end
		end
		local desired = direction * R.Speed * ReelMomentum * arrive

		local mass = RootPart.AssemblyMass
		local accel = (desired - Velocity) * R.Responsiveness
		if accel.Magnitude > R.MaxAcceleration then
			accel = accel.Unit * R.MaxAcceleration
		end
		local blend = math.clamp((now - ReelStartTime) / R.BlendTime, 0, 1)
		return (accel * mass + Vector3.new(0, workspace.Gravity * mass, 0)) * blend
	end

	-- Orbit: a sideways push around the hook(s) that builds you up to orbit
	-- speed and eases off once you're there. Only the sideways part of your
	-- velocity is touched; gravity and the rope handle the rest, so the orbit
	-- swings rather than floats.
	local function CalculateOrbitForce(Velocity: Vector3, Side: string): Vector3
		local O = CFG.Orbit
		local tangent = orbitTangent(GetMeanHook() - RootPart.Position, Side)
		if tangent == Vector3.zero then
			return Vector3.zero
		end

		local target = O.Speed
		local sideways = Velocity:Dot(tangent)
		local shortfall = target - sideways
		if shortfall <= 0 then
			return Vector3.zero -- already orbiting at least that fast; don't brake
		end
		local accel = math.clamp(shortfall * O.Responsiveness, O.MinAcceleration, O.MaxAcceleration)
		return tangent * accel * RootPart.AssemblyMass
	end

	local function ApplyVerticalForce()
		if (UpStrafe and DownStrafe) or (not UpStrafe and not DownStrafe) then
			VerticalForce.Force = Vector3.zero
			VerticalForce.Enabled = false
		else
			VerticalForce.Enabled = true
			if UpStrafe then
				VerticalForce.Force = Vector3.new(0, 1, 0) * StrafePower
			end
			if DownStrafe then
				VerticalForce.Force = Vector3.new(0, -1, 0) * StrafePower
			end
		end

		if StrafeBlock then
			VerticalForce.Force = Vector3.zero
		end
	end

	-- Sideways around the hook point: the horizontal direction to it, turned
	-- 90 degrees (rounded to whole degrees and hundredths, as the reference).
	local function strafeAround(Point: Vector3): Vector3
		local Origin = RootPart.CFrame.Position
		local Resultant = Point - Origin
		local Theta = math.deg(math.atan2(Resultant.Unit.Z, Resultant.Unit.X))
		Theta = math.round(Theta)
		local T = math.rad(-Theta + 90)
		local T2 = -math.deg(T)
		local C = math.cos(math.rad(T2)) * 100
		local S = math.sin(math.rad(T2)) * 100
		C = math.round(C) / 100
		S = math.round(S) / 100
		if RightStrafe and not LeftStrafe then
			C *= -1
			S *= -1
		end
		if LeftStrafe and RightStrafe then
			C = 0
			S = 0
		end
		return Vector3.new(C, 0, S) * StrafePower
	end

	local function ApplyStrafeForce()
		if CFG.Orbit.Enabled then
			-- A/D orbit instead (see CalculateOrbitForce).
			StrafeForce.Force = Vector3.zero
			return
		end
		if (LeftHookAttached and RightHookAttached) and not StrafeBlock then
			if LeftStrafe or RightStrafe then
				StrafeForce.Force = strafeAround(LeftHookAttachPoint:Lerp(RightHookAttachPoint, 0.5))
			end
		elseif (LeftHookAttached or RightHookAttached) and not StrafeBlock then
			if LeftStrafe or RightStrafe then
				StrafeForce.Force = strafeAround(if LeftHookAttached then LeftHookAttachPoint else RightHookAttachPoint)
			else
				StrafeForce.Force = Vector3.zero
			end
		else
			StrafeForce.Force = Vector3.zero
		end
	end

	local function CalculateDragForce(): Vector3
		local Velocity = CalculateVelocity()
		local Speed = Velocity.Magnitude
		local Unit = if Speed > 0 then -Velocity.Unit else Vector3.zero
		local Force = Unit

		local GlobalModifier = if Speed >= 250 then 1.35 else 1
		if not Braking then
			if not Humanoid.PlatformStand or Speed <= 30 then
				DragForce.Enabled = false
			else
				DragForce.Enabled = true
				Force = Unit * (Speed * CFG.SwingDrag)
			end
		else
			DragForce.Enabled = true
			if not Humanoid.PlatformStand or Speed <= 5 then
				Force = Unit * (Speed * 0.8)
			else
				Force = Unit * (Speed * 15)
			end
		end

		return Vector3.new(Force.X, 0, Force.Z) * GlobalModifier
	end

	local function setWiring(wiring: boolean)
		networker:fire("setWiring", wiring)
	end

	-- Slow reel / release, sent only when it changes. Space's reel takes over
	-- on the server while it's held.
	local function updateRopeMode()
		local hooked = LeftHookAttached or RightHookAttached
		local mode = nil
		if hooked and not Splat then
			if SlowReelHeld and not ReleaseHeld then
				mode = "SlowReel"
			elseif ReleaseHeld and not SlowReelHeld and not Braking then
				mode = "Release"
			end
		end
		if mode ~= RopeMode then
			RopeMode = mode
			networker:fire("setRopeMode", mode)
		end
	end

	-- << CONNECTIONS >> --
	table.insert(connections, UserInputService.InputBegan:Connect(function(Key, IsTyping)
		if IsTyping or Splat or destroyed then
			return
		end
		if not options.IsArmed() then
			return
		end

		if Key.KeyCode == CFG.Rope.SlowReelKey then
			SlowReelHeld = true
		end
		if Key.KeyCode == CFG.Rope.ReleaseKey and (LeftHookAttached or RightHookAttached) then
			ReleaseHeld = true
		end

		if Key.KeyCode == Enum.KeyCode.W and not OnGround then
			UpStrafe = true
		end

		if Key.KeyCode == Enum.KeyCode.S and not OnGround then
			DownStrafe = true
		end

		if Key.KeyCode == Enum.KeyCode.Q and GetDistance(Mouse.Hit.Position, RootPart.Position) < MaxHookDistance then
			if Mouse.Target and not HookL then
				FireHook("Left", Mouse.Hit.Position, Mouse.Target)
			end
		end

		if Key.KeyCode == Enum.KeyCode.E and GetDistance(Mouse.Hit.Position, RootPart.Position) < MaxHookDistance then
			if Mouse.Target and not HookR then
				FireHook("Right", Mouse.Hit.Position, Mouse.Target)
			end
		end

		if Key.KeyCode == Enum.KeyCode.A then
			LeftStrafe = true
		end
		if Key.KeyCode == Enum.KeyCode.D then
			RightStrafe = true
		end

		if Key.KeyCode == Enum.KeyCode.LeftControl then
			if not (LeftHookAttached or RightHookAttached) then
				Braking = true
			else
				Repel = true
			end
		end

		if Key.KeyCode == Enum.KeyCode.LeftShift then
			if CanBurst and not OnGround then
				BoostPrep = true
			end
		end

		if Key.KeyCode == Enum.KeyCode.Space then
			if LeftHookAttached or RightHookAttached then
				local Success = GasDrain(GAS.BoostStart, "Both")
				if not Success then
					BoostPrep = false
					return
				end
				if not OnGround then
					Boost = true
					ImpulseFX(false)
				elseif OnGround and not Sliding then
					GasFlip:Play()
					FlipTween()
					ImpulseFX(true)
					task.spawn(FlipShake)
					impulseSound("GasBurst")
					FlipForce.Enabled = true
					Flip.Value = true
					Boost = true
					task.wait(0.3)
					ImpulseFX(false)
					FlipForce.Enabled = false
					task.wait(0.2)
					Flip.Value = false
				end
				setWiring(Boost)
			end
		end

		if Key.KeyCode == Enum.KeyCode.V then
			if CanBurst and not OnGround and (LeftHookAttached or RightHookAttached) then
				local X = GetVector3ToPoint(RootPart.Position, GetMeanHook()) * CFG.HookedBurstSpeed
				local Success = GasDrain(GAS.HookedBurst, "Both")
				if not Success then
					BoostPrep = false
					return
				end
				CanBurst = false
				Bursting = true
				HookBoosting = true
				BoostForce.VectorVelocity = X
				BoostForce.Enabled = true
				BoostGyro.P = CFG.HookedBurstGyroP
				BoostGyro.CFrame = CFrame.lookAt(RootPart.Position, GetMeanHook())
				BoostGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
				Humanoid.PlatformStand = true
				task.spawn(BoostShake)
				ImpulseFX(true)
				GasFlip:Stop()
				HookedBoost:Play()
				HookedBoostIdle:Play()
				impulseSound("GasBurst")
				Flip.Value = false
				hboost.Value = true
				task.wait(0.4)
				ImpulseFX(false)
				if hboost.Value then
					hboost.Value = false
					hboost2.Value = true
				end
			end
		end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(Key, IsTyping)
		if IsTyping or Splat or destroyed then
			return
		end

		if Key.KeyCode == Enum.KeyCode.Q then
			if LeftHooking or LeftHookAttached and not HookL then
				RetractHook("Left")
				if HookBoosting then
					CancelHBurst()
				end
				hboost.Value = false
				hboost2.Value = false
			end
		end

		if Key.KeyCode == Enum.KeyCode.E then
			if RightHooking or RightHookAttached and not HookR then
				RetractHook("Right")
				if HookBoosting then
					CancelHBurst()
				end
				hboost.Value = false
				hboost2.Value = false
			end
		end

		if Key.KeyCode == Enum.KeyCode.A then
			LeftStrafe = false
		end

		if Key.KeyCode == Enum.KeyCode.D then
			RightStrafe = false
		end

		if Key.KeyCode == Enum.KeyCode.W then
			UpStrafe = false
		end

		if Key.KeyCode == Enum.KeyCode.S then
			DownStrafe = false
		end

		if Key.KeyCode == Enum.KeyCode.LeftShift then
			if BoostPrep then
				local Success = GasDrain(GAS.Burst, "Both")
				if not Success then
					BoostPrep = false
					return
				end
				local Speed = CalculateVelocity().Magnitude
				local SpeedTarget = if Speed > CFG.BurstSpeed then Speed else CFG.BurstSpeed
				Bursting = true
				BoostPrep = false
				CanBurst = false
				BoostForce.VectorVelocity = (Mouse.Hit.Position - RootPart.Position).Unit * SpeedTarget
				BoostForce.Enabled = true
				BoostGyro.P = CFG.BurstGyroP
				BoostGyro.CFrame = CFrame.lookAt(RootPart.Position, Mouse.Hit.Position)
				BoostGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
				Humanoid.PlatformStand = true
				GasFlip:Stop()
				BurstFlip:Play()
				impulseSound("GasBurst")
				task.wait(CFG.BurstDuration)
				Bursting = false
				BoostForce.VectorVelocity = Vector3.zero
				BoostForce.Enabled = false
				BoostGyro.P = 0
				BoostGyro.MaxTorque = Vector3.zero
				task.wait(CFG.BurstCooldown)
				CanBurst = true
			end
		end

		if Key.KeyCode == Enum.KeyCode.LeftControl then
			Braking = false
			Repel = false
		end

		if Key.KeyCode == Enum.KeyCode.Space then
			Boost = false
			setWiring(Boost)
		end

		if Key.KeyCode == CFG.Rope.SlowReelKey then
			SlowReelHeld = false
		end
		if Key.KeyCode == CFG.Rope.ReleaseKey then
			ReleaseHeld = false
		end
	end))

	-- UI runtime. Tweens only start when a target changes (the reference
	-- re-creates them every frame towards the same targets).
	local tweenTargets = {}
	local function tweenTo(object: Instance, property: string, value: any)
		local key = object.Name .. "." .. property
		if tweenTargets[key] == value then
			return
		end
		tweenTargets[key] = value
		TweenService:Create(object, TweenInfo.new(0.25), { [property] = value }):Play()
	end

	local function colorCursor(color: Color3, rotation: number)
		tweenTo(Block.CROSSHAIR, "Rotation", rotation)
		tweenTo(Block.CROSSHAIR, "ImageColor3", color)
		tweenTo(Block.LT_BEAM, "ImageColor3", color)
		tweenTo(Block.LB_BEAM, "ImageColor3", color)
		tweenTo(Block.RT_BEAM, "ImageColor3", color)
		tweenTo(Block.RB_BEAM, "ImageColor3", color)
	end

	local function beam(name: string, transparency: number?, rotation: number, position: UDim2, size: UDim2)
		local object = Block[name]
		if transparency then
			tweenTo(object, "ImageTransparency", transparency)
		end
		tweenTo(object, "Rotation", rotation)
		tweenTo(object, "Position", position)
		tweenTo(object, "Size", size)
	end

	local WIDE = UDim2.new(0, 30, 0, 30)
	local NARROW = UDim2.new(0, 20, 0, 30)

	table.insert(connections, RunService.RenderStepped:Connect(function()
		local mouseLocation = UserInputService:GetMouseLocation()
		Block.Position = UDim2.fromOffset(mouseLocation.X, mouseLocation.Y)

		if GetDistance(RootPart.Position, Mouse.Hit.Position) < MaxHookDistance then
			colorCursor(if not CanBurst then UI.CooldownColor else UI.CrosshairColor, 0)
		else
			colorCursor(if not CanBurst then UI.CooldownColor else UI.OutOfRangeColor, 45)
		end

		if BoostPrep then
			LeftCursorStick = false
			LeftCursorLaunch = false
			RightCursorStick = false
			RightCursorLaunch = false
			beam("LT_BEAM", 0, 135, UDim2.new(-15, 0, -15, 0), NARROW)
			beam("LB_BEAM", 0, 45, UDim2.new(-15, 0, 15, 0), NARROW)
			beam("RT_BEAM", 0, 45, UDim2.new(15, 0, -15, 0), NARROW)
			beam("RB_BEAM", 0, 135, UDim2.new(15, 0, 15, 0), NARROW)
		else
			if LeftHooking or LeftHookAttached then
				if LeftHooking and not LeftCursorLaunch then
					LeftCursorLaunch = true
					LeftCursorStick = false
					beam("LT_BEAM", 0, 180, UDim2.new(-35, 0, 0, 0), WIDE)
					beam("LB_BEAM", 0, 180, UDim2.new(-35, 0, 0, 0), WIDE)
				end
				if LeftHookAttached and not LeftCursorStick then
					LeftCursorLaunch = false
					LeftCursorStick = true
					beam("LT_BEAM", nil, 135, UDim2.new(-35, 0, -6.5, 0), NARROW)
					beam("LB_BEAM", nil, 45, UDim2.new(-35, 0, 6.5, 0), NARROW)
				end
			else
				LeftCursorLaunch = false
				LeftCursorStick = false
				beam("LT_BEAM", 1, 180, UDim2.new(0, 0, 0, 0), WIDE)
				beam("LB_BEAM", 1, 180, UDim2.new(0, 0, 0, 0), WIDE)
			end

			if RightHooking or RightHookAttached then
				if RightHooking and not RightCursorLaunch then
					RightCursorLaunch = true
					RightCursorStick = false
					beam("RT_BEAM", 0, 180, UDim2.new(35, 0, 0, 0), WIDE)
					beam("RB_BEAM", 0, 180, UDim2.new(35, 0, 0, 0), WIDE)
				end
				if RightHookAttached and not RightCursorStick then
					RightCursorLaunch = false
					RightCursorStick = true
					beam("RT_BEAM", nil, 45, UDim2.new(35, 0, -6.5, 0), NARROW)
					beam("RB_BEAM", nil, 135, UDim2.new(35, 0, 6.5, 0), NARROW)
				end
			else
				RightCursorLaunch = false
				RightCursorStick = false
				beam("RT_BEAM", 1, 180, UDim2.new(0, 0, 0, 0), WIDE)
				beam("RB_BEAM", 1, 180, UDim2.new(0, 0, 0, 0), WIDE)
			end
		end
	end))

	local floorParams = RaycastParams.new()
	floorParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Physics runtime
	table.insert(connections, RunService.Stepped:Connect(function(_, dt: number)
		if destroyed or not RootPart.Parent then
			return
		end

		local CurrentVelocity = CalculateVelocity().Magnitude
		local CurrentAngularVelocity = RootPart.AssemblyAngularVelocity.Magnitude
		-- Speed lost since last tick; checked against last tick's PlatformStand
		-- since landing can turn it off this tick before the check runs.
		local VelocityDifference = math.round(PreviousTickVelocity - CurrentVelocity)
		local WasPlatformStanding = PreviousPlatformStand

		PreviousTickVelocity = CurrentVelocity

		local VelocityVector: Vector3 = CalculateVelocity().Unit

		floorParams.FilterDescendantsInstances = { character }
		local FloorCast = workspace:Raycast(RootPart.Position, Vector3.new(0, -1, 0) * CFG.FloorCastDistance, floorParams)
		local BurstCast = workspace:Raycast(
			RootPart.Position,
			(RootPart.CFrame - Vector3.new(1, 0, 0)).LookVector * CFG.BurstCastDistance,
			floorParams
		)

		if FloorCast then
			OnGround = true
			BoostPrep = false
		else
			OnGround = false
		end

		if (LeftStrafe or RightStrafe or UpStrafe or DownStrafe) and ((OnGround and not Sliding) or not (LeftHookAttached or RightHookAttached)) then
			StrafeBlock = true
		else
			StrafeBlock = false
		end

		if LeftStrafe and not StrafeBlock and not Splat then
			local Success = GasDrain(GAS.LeftStrafeTick, "Right")
			if not Success then
				StrafeBlock = true
			end
		end

		if RightStrafe and not StrafeBlock and not Splat then
			local Success = GasDrain(GAS.RightStrafeTick, "Left")
			if not Success then
				RightStrafe = false
			end
		end

		if UpStrafe and not StrafeBlock and not Splat then
			local Success = GasDrain(GAS.UpStrafeTick, "Both")
			if not Success then
				UpStrafe = false
			end
		end

		if DownStrafe and not StrafeBlock and not Splat then
			local Success = GasDrain(GAS.DownStrafeTick, "Both")
			if not Success then
				DownStrafe = false
			end
		end

		setEffect("LeftBoost", LeftStrafe and not StrafeBlock and not Splat)
		setEffect("RightBoost", RightStrafe and not StrafeBlock and not Splat)
		setEffect("UpBoost", UpStrafe and not StrafeBlock and not Splat)
		setEffect("DownBoost", DownStrafe and not StrafeBlock and not Splat)

		if BurstCast then
			Obstructed = true
			if HookBoosting then
				HookBoosting = false
				RetractHook("Left", false)
				RetractHook("Right", false)
				task.wait(0.1)
				CancelHBurst()
			end
		else
			Obstructed = false
		end

		local trailsOn = CurrentVelocity >= CFG.TrailSpeed
		for _, side in { "Left", "Right" } do
			local trail = ODMGearParts.getScabbardTrail(character, side)
			if trail then
				trail.Enabled = trailsOn
			end
		end

		if (LeftHookAttached or RightHookAttached) or Sliding and not Flip.Value then
			if CurrentVelocity > 0 then
				BodyGyro.CFrame = CFrame.new(Vector3.zero, VelocityVector)
			end
			Humanoid.JumpPower = 0
		else
			Humanoid.JumpPower = CFG.JumpPower
		end

		if Boost then
			local Success = GasDrain(GAS.BoostTick, "Both")
			if not Success then
				Boost = false
			end
		end

		-- A or D (not both) while hooked and airborne: orbit.
		local NewOrbitSide = nil
		if CFG.Orbit.Enabled and (LeftHookAttached or RightHookAttached) and not OnGround
			and not StrafeBlock and not Splat and not Bursting and not Flip.Value
		then
			if LeftStrafe and not RightStrafe then
				NewOrbitSide = "Left"
			elseif RightStrafe and not LeftStrafe then
				NewOrbitSide = "Right"
			end
		end
		if NewOrbitSide ~= OrbitSide then
			OrbitSide = NewOrbitSide
			if CameraService and CameraService.SetODMOrbit then
				CameraService:SetODMOrbit(OrbitSide)
			end
		end

		-- Ease the reel's curve towards the held side.
		local curveTarget = if OrbitSide == "Left" then -1 elseif OrbitSide == "Right" then 1 else 0
		local curveStep = dt / math.max(CFG.Reel.StrafeCurveBlendTime, 0.01)
		if ReelCurve < curveTarget then
			ReelCurve = math.min(curveTarget, ReelCurve + curveStep)
		elseif ReelCurve > curveTarget then
			ReelCurve = math.max(curveTarget, ReelCurve - curveStep)
		end

		local Hooked = LeftHookAttached or RightHookAttached
		local ReelingNow = Boost and Hooked and not Flip.Value
			and CFG.Reel.Style ~= "Reference"
		if OrbitSide and not ReelingNow then
			Reeling = false
			setSound("GasHiss", true)
			setEffect("MainBoost", Boost)
			setEffect("BoostTrail", Boost)
			setEffect("Gas", Boost)
			Humanoid.PlatformStand = true
			HookForce.Enabled = true
			HookForce.Force = CalculateOrbitForce(CalculateVelocity(), OrbitSide)
		elseif Boost and Hooked and not Flip.Value then
			setSound("GasHiss", true)
			if not (LeftStrafe or RightStrafe or UpStrafe or DownStrafe) or (LeftStrafe and RightStrafe and UpStrafe and DownStrafe) then
				setEffect("MainBoost", true)
			end
			setEffect("BoostTrail", true)
			setEffect("Gas", true)

			local ForceResultant = Vector3.zero
			if LeftHookAttached or RightHookAttached then
				HookForce.Enabled = true
				if LeftHookAttached then
					ForceResultant += CalculateWireResultant("Left")
				end
				if RightHookAttached then
					ForceResultant += CalculateWireResultant("Right")
				end
			end

			if CurrentVelocity < 250 then
				if not Humanoid.PlatformStand then
					Humanoid.PlatformStand = true
				end
			end
			if CFG.Reel.Style == "Reference" then
				HookForce.Force = CalculateBoostVelocity(ForceResultant)
			else
				Humanoid.PlatformStand = true
				HookForce.Force = CalculateReelForce(CalculateVelocity(), dt)
			end
		else
			Reeling = false
			if (LeftStrafe or RightStrafe or UpStrafe or DownStrafe) and (LeftHookAttached or RightHookAttached) and Humanoid.PlatformStand then
				setSound("GasHiss", true)
			else
				setSound("GasHiss", false)
			end

			setEffect("MainBoost", false)
			setEffect("BoostTrail", false)
			setEffect("Gas", false)

			HookForce.Enabled = false
		end

		if not OnGround then
			Sliding = false
			if LeftHookAttached or RightHookAttached and not Flip.Value then
				Humanoid.PlatformStand = true
				if not Splat then
					BodyGyro.Enabled = true
					play(ForwardHooking)
					if not ForwardPlaying then
						local RandomAnim = math.random(1, #ForwardAnims)
						CurrentForwardAnim = ForwardAnims[RandomAnim]
						ForwardAnims[RandomAnim]:Play()
						ForwardPlaying = true
					end
				end
			else
				if not Splat then
					for _, v in ForwardAnims do
						v:Stop()
					end
					ForwardPlaying = false
					if CurrentForwardAnim then
						CurrentForwardAnim:Stop()
					end
					CurrentForwardAnim = nil
					ForwardHooking:Stop()
					HookedBoostIdle:Stop()
					BodyGyro.Enabled = false
				end
			end
			GroundSlide:Stop()
			play(FallingAnim)
			DragForce.Force = CalculateDragForce()
			-- The hybrid reel sets its own speed; drag would only fight it.
			if Reeling and not Braking then
				DragForce.Enabled = false
			end
		else
			FallingAnim:Stop()
			ForwardHooking:Stop()
			for _, v in ForwardAnims do
				v:Stop()
			end
			ForwardPlaying = false
			local slideSpeed = if LeftHookAttached or RightHookAttached
				then CFG.GroundSlideHookedSpeed
				else CFG.GroundSlideUnhookedSpeed
			if CurrentVelocity >= slideSpeed then
				if not Sliding then
					GroundSlide:Play()
				end
				Humanoid.PlatformStand = true
				BodyGyro.Enabled = true
				Sliding = true
			else
				Sliding = false
				Humanoid.PlatformStand = false
				GroundSlide:Stop()
				BodyGyro.Enabled = false
				DragForce.Enabled = false
			end
		end
		SlideValue.Value = Sliding

		if Sliding and FloorCast then
			local FloorMaterial = FloorCast.Material
			local dirt = FloorMaterial == Enum.Material.LeafyGrass
				or FloorMaterial == Enum.Material.Grass
				or FloorMaterial == Enum.Material.Mud
			setEffect("LeftSlideSparks", not dirt)
			setEffect("RightSlideSparks", not dirt)
			setEffect("LeftSlideDirt", dirt)
			setEffect("RightSlideDirt", dirt)
		else
			setEffect("LeftSlideSparks", false)
			setEffect("RightSlideSparks", false)
			setEffect("LeftSlideDirt", false)
			setEffect("RightSlideDirt", false)
		end

		local hooked = LeftHookAttached or RightHookAttached
		if CurrentAngularVelocity >= CFG.FastFlipAngularSpeed and not OnGround then
			if not hooked then
				play(FastFlip)
				SlowFlip:Stop()
			else
				FastFlip:Stop()
				SlowFlip:Stop()
			end
		elseif CurrentAngularVelocity < CFG.FastFlipAngularSpeed and CurrentAngularVelocity >= CFG.SlowFlipAngularSpeed and not OnGround then
			if not hooked then
				FastFlip:Stop()
				play(SlowFlip)
			else
				FastFlip:Stop()
				SlowFlip:Stop()
			end
		else
			FastFlip:Stop()
			SlowFlip:Stop()
		end

		if ForwardPlaying and CurrentForwardAnim then
			CurrentForwardAnim.TimePosition = ForwardHooking.TimePosition
			if CurrentVelocity >= CFG.ForwardBlendStartSpeed then
				local Speedlerp = (CurrentVelocity - CFG.ForwardBlendStartSpeed) / CFG.ForwardBlendRange
				CurrentForwardAnim:AdjustWeight(Speedlerp)
				ForwardHooking:AdjustWeight(1 - Speedlerp)
			else
				CurrentForwardAnim:AdjustWeight(0)
				ForwardHooking:AdjustWeight(1)
			end
		else
			ForwardHooking:Stop()
		end

		if VelocityDifference >= CFG.SplatVelocityDelta and not Bursting then
			if not Splat and WasPlatformStanding then
				local Timeout = 2.5 + (VelocityDifference / 175)
				task.spawn(SplatFunction, Timeout)
			end
		end

		if hboost.Value or hboost2.Value then
			setSound("GasHiss", true)
			setEffect("MainBoost", true)
		else
			HookedBoost:Stop()
			HookedBoostIdle:Stop()
		end

		if Humanoid.PlatformStand then
			ApplyStrafeForce()
			ApplyVerticalForce()
		end

		if LeftHookAttached and LeftHookTarget and LeftHookTarget.Parent then
			LeftHookAttachPoint = LeftHookTarget.CFrame:PointToWorldSpace(LeftHookOffset)
		end

		if RightHookAttached and RightHookTarget and RightHookTarget.Parent then
			RightHookAttachPoint = RightHookTarget.CFrame:PointToWorldSpace(RightHookOffset)
		end

		if RopeMode == "SlowReel" and not Boost then
			if not GasDrain(GAS.SlowReelTick, "Both") then
				SlowReelHeld = false
			end
		end
		updateRopeMode()

		GasTick()
		GasCrossfeed()
		GasVisualizer()
		PreviousPlatformStand = Humanoid.PlatformStand
	end))

	setWiring(false)

	------------------------------------------------------------
	-- API
	------------------------------------------------------------

	function self:_onSplatEnded()
		Splat = false
		-- Key-ups during the splat were ignored.
		SlowReelHeld = UserInputService:IsKeyDown(CFG.Rope.SlowReelKey)
		ReleaseHeld = UserInputService:IsKeyDown(CFG.Rope.ReleaseKey)
	end

	function self:IsHooking(): boolean
		return LeftHookAttached or RightHookAttached
	end

	function self:IsHookAttached(side: string): boolean
		return if side == "Left" then LeftHookAttached else RightHookAttached
	end

	function self:IsBoosting(): boolean
		return Boost
	end

	function self:IsSliding(): boolean
		return Sliding
	end

	function self:IsOnGround(): boolean
		return OnGround
	end

	function self:IsSplat(): boolean
		return Splat
	end

	function self:IsStrafing(): boolean
		return LeftStrafe or RightStrafe or UpStrafe or DownStrafe
	end

	-- The reference refuses to arm/disarm mid-strafe or with a tool out.
	function self:CanToggleArm(): boolean
		return not (self:IsStrafing() or character:FindFirstChildOfClass("Tool"))
	end

	function self:GetGas(): (number, number, number, number)
		return GasInLefttank, GasInRightTank, MaxGasInLeftTank, MaxGasInRightTank
	end

	function self:RefillGas()
		GasInLefttank = MaxGasInLeftTank
		GasInRightTank = MaxGasInRightTank
	end

	-- Holstering: drop both hooks and every held input.
	function self:Release()
		LeftStrafe, RightStrafe, UpStrafe, DownStrafe = false, false, false, false
		Braking, Repel, BoostPrep = false, false, false
		if Boost then
			Boost = false
			setWiring(false)
		end
		task.spawn(RetractHook, "Left", false, true)
		task.spawn(RetractHook, "Right", false, true)
	end

	function self:Destroy()
		if destroyed then
			return
		end
		destroyed = true
		if active == self then
			active = nil
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		BoostShakeParams:Stop()
		for _, track in allTracks do
			track:Stop()
		end
		for key, on in effectState do
			if on then
				networker:fire("effect", "ToggleEffect", key, false)
			end
		end
		if soundState.GasHiss then
			networker:fire("effect", "ToggleSound", "GasHiss", false)
		end
		if CameraService and CameraService.SetFOVOverride then
			CameraService:SetFOVOverride(nil)
		end
		if CameraService and CameraService.SetODMOrbit then
			CameraService:SetODMOrbit(nil)
		end
		setWiring(false)
		CursorFollow:Destroy()
		Tankgui:Destroy()
		Eyes:Destroy()
		UserInputService.MouseIconEnabled = true
		if Humanoid.Parent then
			Humanoid.PlatformStand = false
			Humanoid.JumpPower = CFG.JumpPower
		end
	end

	if active then
		active:Destroy()
	end
	active = self
	return self
end

return ODMMovementClient
