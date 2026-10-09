-- ReplicatedStorage.Shared.Modules.CameraShaker
--
-- Small camera shaker with the CameraShaker API the ODM movement uses:
--
--   local shaker = CameraShaker.new(renderPriority, function(shakeCFrame)
--   	camera.CFrame *= shakeCFrame
--   end)
--   shaker:Start()
--   shaker:ShakeOnce(magnitude, roughness, fadeInTime, fadeOutTime)
--
-- Each shake is Perlin noise scaled by magnitude, faded in then out. Rotation
-- is in degrees; position influence is 0.15 per axis, rotation influence 1.

local RunService = game:GetService("RunService")

local POS_INFLUENCE = Vector3.new(0.15, 0.15, 0.15)
local ROT_INFLUENCE = Vector3.new(1, 1, 1)

local CameraShaker = {}
CameraShaker.__index = CameraShaker

local nextId = 0

type Shake = {
	Magnitude: number,
	Roughness: number,
	FadeIn: number,
	FadeOut: number,
	Elapsed: number,
	Tick: number,
}

function CameraShaker.new(renderPriority: number, callback: (CFrame) -> ())
	nextId += 1
	local self = setmetatable({}, CameraShaker)
	self._priority = renderPriority
	self._callback = callback
	self._name = "CameraShaker" .. nextId
	self._shakes = {} :: { Shake }
	self._running = false
	return self
end

function CameraShaker:Start()
	if self._running then
		return
	end
	self._running = true
	RunService:BindToRenderStep(self._name, self._priority, function(dt)
		self:_update(dt)
	end)
end

function CameraShaker:Stop()
	if not self._running then
		return
	end
	self._running = false
	RunService:UnbindFromRenderStep(self._name)
	table.clear(self._shakes)
end

function CameraShaker:ShakeOnce(magnitude: number, roughness: number, fadeInTime: number?, fadeOutTime: number?)
	table.insert(self._shakes, {
		Magnitude = magnitude,
		Roughness = roughness,
		FadeIn = fadeInTime or 0.1,
		FadeOut = fadeOutTime or 0.75,
		Elapsed = 0,
		Tick = math.random() * 100,
	})
end

function CameraShaker:_update(dt: number)
	local position = Vector3.zero
	local rotation = Vector3.zero

	for i = #self._shakes, 1, -1 do
		local shake = self._shakes[i]
		shake.Elapsed += dt

		local fade
		if shake.Elapsed < shake.FadeIn then
			fade = if shake.FadeIn > 0 then shake.Elapsed / shake.FadeIn else 1
		else
			local out = shake.Elapsed - shake.FadeIn
			if out >= shake.FadeOut then
				table.remove(self._shakes, i)
				continue
			end
			fade = 1 - out / math.max(shake.FadeOut, 1e-3)
		end

		shake.Tick += dt * shake.Roughness * fade
		local t = shake.Tick
		local noise = Vector3.new(math.noise(t, 0), math.noise(0, t), math.noise(t, t)) * shake.Magnitude * fade
		position += noise * POS_INFLUENCE
		rotation += noise * ROT_INFLUENCE
	end

	if position == Vector3.zero and rotation == Vector3.zero then
		return
	end

	self._callback(
		CFrame.new(position)
			* CFrame.fromOrientation(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	)
end

return CameraShaker
