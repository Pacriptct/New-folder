--

local CameraConfig = {}

CameraConfig.ShiftLock = {
	Enabled = true,

	GuiName = "OdysseyShiftLockCursorGui",
	GuiDisplayOrder = 1000,

	Offset = Vector3.new(2.25, 0.35, 0),
	RotationSpeed = 18,
	HideRobloxMouseIcon = true,
}

CameraConfig.ODM = {
	Enabled = true,

	BaseFOV = 70,
	MaxFOV = 87,

	SpeedForMaxFOV = 220,
	FOVLerp = 0.12,

	BoostFOVBonus = 8,
	BoostShakeStrength = 0.22,
	SpeedShakeStrength = 0.08,

	ShakeSpeed = 18,
	ShakeLerp = 0.2,

	TiltMaxAngle = 6,
	TiltLerp = 0.045,

	OrbitTiltAngle = 12,

	ResetLerp = 0.03,
}

return CameraConfig