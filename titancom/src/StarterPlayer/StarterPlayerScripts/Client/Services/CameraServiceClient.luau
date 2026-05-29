local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local BASE_FOV = 70
local MAX_FOV = 90
local BOOST_FOV_BONUS = 8
local FOV_LERP = 0.12
local TILT_LERP = 0.1
local SHAKE_LERP = 0.3
local SHAKE_SPEED = 3
local SPEED_SHAKE_STRENGTH = 0.04
local BOOST_SHAKE_STRENGTH = 0.12
local ORBIT_TILT_ANGLE = 5
local TILT_MAX_ANGLE = 8
local SPEED_FOR_MAX_FOV = 80
local RELEASE_FOV_LERP = 0.018
local RELEASE_TILT_LERP = 0.018
local RELEASE_SHAKE_LERP = 0.045

local ODM_OFFSET_MIN = Vector3.new(1.25, 0.35, 0)
local ODM_OFFSET_MAX = Vector3.new(2.5, 0.6, 0)
local ODM_BOOST_OFFSET_BONUS = Vector3.new(0.6, 0.15, 0)
local CAMERA_OFFSET_LERP = 5
local CAMERA_OFFSET_RELEASE_LERP = 1.75

local CameraServiceClient = {} :: any

CameraServiceClient._initialized = false
CameraServiceClient._odmEnabled = false
CameraServiceClient._odmBoosting = false
CameraServiceClient._odmOrbitSide = nil
CameraServiceClient._odmCharacter = nil
CameraServiceClient._odmRootPart = nil
CameraServiceClient._odmCurrentFOV = BASE_FOV
CameraServiceClient._odmCurrentTilt = 0
CameraServiceClient._odmShakeTime = 0
CameraServiceClient._odmShakeOffset = Vector3.zero
CameraServiceClient._currentCameraOffset = Vector3.zero

function CameraServiceClient:init()
	if self._initialized then return end
	self._initialized = true

	LocalPlayer.CharacterAdded:Connect(function()
		self:SetODMEnabled(false)
		self._currentCameraOffset = Vector3.zero
	end)

	RunService.RenderStepped:Connect(function(dt)
		self:_update(dt)
	end)
end

function CameraServiceClient:SetODMEnabled(enabled: boolean, character: Model?)
	self._odmEnabled = enabled
	if character then
		self._odmCharacter = character
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			self._odmRootPart = root
		end
	end
	if not enabled then
		self._odmBoosting = false
		self._odmOrbitSide = nil
	end
end

function CameraServiceClient:SetODMBoosting(boosting: boolean)
	self._odmBoosting = boosting
end

function CameraServiceClient:SetODMOrbit(side: ("Left" | "Right")?)
	self._odmOrbitSide = side
end

function CameraServiceClient:ODMImpulse(strength: number?)
	strength = strength or 1
	self._odmShakeOffset += Vector3.new(
		(math.random() - 0.5) * 0.35 * strength,
		(math.random() - 0.5) * 0.35 * strength,
		0
	)
end

function CameraServiceClient:ODMBoostShake(strength: number?)
	local s = strength or 1
	self:ODMImpulse(2.25 * s)
	task.delay(0.25, function()
		if self._odmEnabled then
			self:ODMImpulse(1.65 * s)
		end
	end)
end

function CameraServiceClient:IsShiftLockEnabled(): boolean
	return false
end

function CameraServiceClient:_getRootPart(): BasePart?
	if self._odmRootPart and self._odmRootPart.Parent then
		return self._odmRootPart
	end
	local char = self._odmCharacter or LocalPlayer.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			self._odmRootPart = root
			return root
		end
	end
	return nil
end

function CameraServiceClient:_getHumanoid(): Humanoid?
	local char = LocalPlayer.Character
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

function CameraServiceClient:_getSpeedAlpha(): number
	local root = self:_getRootPart()
	if not root then return 0 end
	return math.clamp(root.AssemblyLinearVelocity.Magnitude / SPEED_FOR_MAX_FOV, 0, 1)
end

function CameraServiceClient:_update(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then return end

	-- Camera offset
	local humanoid = self:_getHumanoid()
	if humanoid then
		local odmOffset = Vector3.zero
		if self._odmEnabled then
			local alpha = self:_getSpeedAlpha()
			odmOffset = ODM_OFFSET_MIN:Lerp(ODM_OFFSET_MAX, alpha)
			if self._odmBoosting then odmOffset += ODM_BOOST_OFFSET_BONUS end
			if self._odmOrbitSide == "Left" then
				odmOffset = Vector3.new(-math.abs(odmOffset.X), odmOffset.Y, odmOffset.Z)
			elseif self._odmOrbitSide == "Right" then
				odmOffset = Vector3.new(math.abs(odmOffset.X), odmOffset.Y, odmOffset.Z)
			end
		end
		local speed = if self._odmEnabled then CAMERA_OFFSET_LERP else CAMERA_OFFSET_RELEASE_LERP
		local a = 1 - math.exp(-speed * dt)
		self._currentCameraOffset = self._currentCameraOffset:Lerp(odmOffset, a)
		humanoid.CameraOffset = self._currentCameraOffset
	end

	if not self._odmEnabled then
		-- Release lerps
		self._odmCurrentFOV += (BASE_FOV - self._odmCurrentFOV) * RELEASE_FOV_LERP
		camera.FieldOfView = self._odmCurrentFOV
		self._odmCurrentTilt += (0 - self._odmCurrentTilt) * RELEASE_TILT_LERP
		self._odmShakeOffset = self._odmShakeOffset:Lerp(Vector3.zero, RELEASE_SHAKE_LERP)
		camera.CFrame = camera.CFrame * CFrame.new(self._odmShakeOffset) * CFrame.Angles(0, 0, math.rad(self._odmCurrentTilt))
		return
	end

	local speedAlpha = self:_getSpeedAlpha()

	-- FOV
	local targetFOV = BASE_FOV + (MAX_FOV - BASE_FOV) * speedAlpha
	if self._odmBoosting then targetFOV += BOOST_FOV_BONUS end
	self._odmCurrentFOV += (targetFOV - self._odmCurrentFOV) * FOV_LERP
	camera.FieldOfView = self._odmCurrentFOV

	-- Tilt
	local targetTilt = 0
	local root = self:_getRootPart()
	if self._odmOrbitSide == "Left" then
		targetTilt = ORBIT_TILT_ANGLE
	elseif self._odmOrbitSide == "Right" then
		targetTilt = -ORBIT_TILT_ANGLE
	elseif root then
		local vel = root.AssemblyLinearVelocity
		if vel.Magnitude > 10 then
			local rightDot = root.CFrame.RightVector:Dot(vel.Unit)
			targetTilt = math.clamp(-rightDot * TILT_MAX_ANGLE, -TILT_MAX_ANGLE, TILT_MAX_ANGLE)
		end
	end
	self._odmCurrentTilt += (targetTilt - self._odmCurrentTilt) * TILT_LERP

	-- Shake
	self._odmShakeTime += dt * SHAKE_SPEED
	local strength = SPEED_SHAKE_STRENGTH * speedAlpha
	if self._odmBoosting then strength += BOOST_SHAKE_STRENGTH end
	local targetShake = Vector3.new(
		math.noise(self._odmShakeTime, 0, 0) * strength,
		math.noise(0, self._odmShakeTime, 0) * strength,
		0
	)
	self._odmShakeOffset = self._odmShakeOffset:Lerp(targetShake, SHAKE_LERP)

	camera.CFrame = camera.CFrame * CFrame.new(self._odmShakeOffset) * CFrame.Angles(0, 0, math.rad(self._odmCurrentTilt))
end

return CameraServiceClient