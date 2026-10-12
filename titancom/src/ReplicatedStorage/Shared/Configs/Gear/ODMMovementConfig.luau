-- ReplicatedStorage.Shared.Configs.Gear.ODMMovementConfig
--
-- Tuning for the ODM movement (ODMMovementClient + ODMWireService). The
-- values are the reference gear's constants; rates are per second unless
-- noted as "per tick" (the reference drains gas once per physics step,
-- written as amount / 60 or amount / 120).

local ODMMovementConfig = {}

------------------------------------------------------------
-- Core constants
------------------------------------------------------------

ODMMovementConfig.MaxHookDistance = 500
ODMMovementConfig.StrafePower = 1750
ODMMovementConfig.VerticalPower = 0
ODMMovementConfig.ReelSpeed = 4.5
ODMMovementConfig.HookSpeed = 2000
ODMMovementConfig.GasDrainSpeed = 2
ODMMovementConfig.GasCrossfeedSpeed = 0.5

-- Tank capacity, and how much each tank holds on spawn. A refill tops both
-- tanks up to their max.
ODMMovementConfig.MaxGasInLeftTank = 1000
ODMMovementConfig.MaxGasInRightTank = 1000
ODMMovementConfig.StartGasInLeftTank = 100
ODMMovementConfig.StartGasInRightTank = 100

------------------------------------------------------------
-- Gas costs (taken from the tank(s) noted)
------------------------------------------------------------

ODMMovementConfig.Gas = {
	HookFire = 0.15 / 120, -- that side's tank
	HookRetract = 0.15 / 120, -- left tank (either hook)
	BoostStart = 0.25 / 180, -- both, when Space is pressed while hooked
	BoostTick = 0.15 / 120, -- both, per tick while boosting
	LeftStrafeTick = 0.25 / 120, -- right tank
	RightStrafeTick = 0.25 / 120, -- left tank
	UpStrafeTick = 0.75 / 120, -- both
	DownStrafeTick = 0.15 / 120, -- both
	Burst = 10, -- both (LeftShift)
	HookedBurst = 24, -- both (V)
}

------------------------------------------------------------
-- Bursts
------------------------------------------------------------

ODMMovementConfig.BurstSpeed = 250 -- LeftShift; keeps current speed if faster
ODMMovementConfig.BurstDuration = 0.15
ODMMovementConfig.BurstGyroP = 20000
ODMMovementConfig.HookedBurstSpeed = 250 -- V, towards the mean hook point
ODMMovementConfig.HookedBurstGyroP = 10000
ODMMovementConfig.BurstCooldown = 4

------------------------------------------------------------
-- Ground / air
------------------------------------------------------------

ODMMovementConfig.FloorCastDistance = 3.5
ODMMovementConfig.BurstCastDistance = 20
ODMMovementConfig.GroundSlideHookedSpeed = 60
ODMMovementConfig.GroundSlideUnhookedSpeed = 45
ODMMovementConfig.JumpPower = 40 -- while not hooked / sliding (0 otherwise)
ODMMovementConfig.TrailSpeed = 250 -- scabbard trails on at or above this speed
ODMMovementConfig.FastFlipAngularSpeed = 15
ODMMovementConfig.SlowFlipAngularSpeed = 8
ODMMovementConfig.ForwardBlendStartSpeed = 100
ODMMovementConfig.ForwardBlendRange = 240

-- A speed change of at least this much in one tick while PlatformStanding
-- (and not bursting) splats the player.
ODMMovementConfig.SplatVelocityDelta = 200

------------------------------------------------------------
-- Forces (built on the HumanoidRootPart when the gear is equipped)
------------------------------------------------------------

ODMMovementConfig.Forces = {
	BoostMaxForce = 10000000,
	BoostGyroD = 300,
	BodyGyroResponsiveness = 20,
	BodyGyroMaxTorque = 100000,
	FlipForce = Vector3.new(0, 5000, 0),
}

------------------------------------------------------------
-- Wires (server)
------------------------------------------------------------

ODMMovementConfig.Wire = {
	Thickness = 0.08,
	Color = Color3.fromRGB(40, 40, 40),
	BeamWidth = 0.08,
	BeamSegments = 50,
	-- Rope slack while boosting is reeled in by this much per step.
	ReelPerStep = 2 / 60,
	-- When not boosting, the rope only ever shortens, trailing the player
	-- by this much.
	SustainPerStep = 6 / 60,
	WiggleTime = 0.5,
}

------------------------------------------------------------
-- UI / screen
------------------------------------------------------------

ODMMovementConfig.UI = {
	-- Image ids for the crosshair, its four beams and the splat overlay. Left
	-- empty, simple shapes are drawn instead.
	CrosshairImage = "",
	BeamImage = "",
	VignetteImage = "",
	VisorImage = "",
	GlassImage = "",

	CrosshairColor = Color3.new(1, 1, 1),
	CooldownColor = Color3.new(1, 0.615686, 0),
	OutOfRangeColor = Color3.new(0.741176, 0, 0),
}

ODMMovementConfig.FlipFieldOfView = 150

------------------------------------------------------------
-- Animations
------------------------------------------------------------

-- Folders searched (in order) for the reference animation names below. Put
-- the reference ODMG animations in any of them to use them as-is.
ODMMovementConfig.AnimationFolders = {
	{ "src", "animations", "gear", "ODMG" },
	{ "Assets", "Animations", "ODMG" },
	{ "Assets", "Animations", "ODM" },
}

-- Reference animation -> Odyssey animations to fall back on when the
-- reference one isn't in the place.
ODMMovementConfig.AnimationFallbacks = {
	FastFlip = { "FastFlips", "HookFlip" },
	SlowFlip = { "HookFlip" },
	GroundSlide = { "Sliding" },
	RHIdle = { "RHIdle" },
	LHIdle = { "LHIdle" },
	EHookShoot = { "RHookStart" },
	QHookShoot = { "LHookStart" },
	BaseHookShot = { "DoubleHookStart" },
	Boost = { "Burst", "HookFlip" },
	Falling = {},
	HookedBoost = { "HookedBurstStart", "DoubleHookStart" },
	HookedBoostIdle = { "HookedBurstIdle", "DoubleHookIdle" },
	ForwardHooking = { "ForwardODM", "HookIdle" },
	GasFlip = { "HookFlip" },
	ForwardODM1 = { "DoubleHookIdle" },
	ForwardODM2 = {},
	ForwardODM3 = {},
	ForwardODM4 = {},
	ForwardODM5 = {},
}

return ODMMovementConfig
