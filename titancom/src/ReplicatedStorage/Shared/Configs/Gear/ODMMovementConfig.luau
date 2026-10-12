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

-- Tank capacity, and how much each tank holds when the gear is put on. A
-- refill tops both tanks up to their max.
ODMMovementConfig.MaxGasInLeftTank = 1000
ODMMovementConfig.MaxGasInRightTank = 1000
ODMMovementConfig.StartGasInLeftTank = ODMMovementConfig.MaxGasInLeftTank
ODMMovementConfig.StartGasInRightTank = ODMMovementConfig.MaxGasInRightTank

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
	SlowReelTick = 0.15 / 120, -- both, per tick while slow reeling (C)
}

------------------------------------------------------------
-- Swing and reel
------------------------------------------------------------

-- Not holding Space you swing freely on the rope (a real pendulum: gravity,
-- momentum, the rope only ever shortens). Holding Space reels you in
-- Odyssey-style: your velocity is steered towards the hook(s) and the reel
-- builds momentum the longer you hold it. Letting go hands your exact
-- velocity back to the swing, at the now shorter rope length.
ODMMovementConfig.Reel = {
	-- What holding Space does while hooked:
	--   "Odyssey"   Odyssey's gear movement (see ODMMovementConfig.Odyssey)
	--   "Hybrid"    a softer steering reel (the settings below)
	--   "Reference" the original force-based reel
	Style = "Odyssey",

	Speed = 145, -- reel speed at momentum 1
	MinMomentum = 0.35, -- reel momentum floor when you start reeling slowly
	MaxMomentum = 1.35, -- top reel speed = Speed * MaxMomentum
	MomentumGain = 0.6, -- momentum gained per second of reeling

	-- How hard velocity is steered towards the reel direction (per second).
	-- Higher snaps onto the hook line faster; lower keeps more of your swing.
	Responsiveness = 4,
	MaxAcceleration = 650, -- cap on that steering, studs/s^2
	BlendTime = 0.15, -- the reel fades in over this long when Space goes down

	-- Within this distance of the hook the reel eases off so you don't
	-- overshoot and jitter around it.
	ArriveDistance = 15,

	-- A/D while reeling curve the reel to that side instead of stopping it,
	-- so you spiral in. 1 aims 45 degrees off the hook line; 0.5 about 27.
	StrafeCurve = 0.8,
	-- How long the curve takes to fade in or out, so letting go of A/D
	-- doesn't snap you back onto the hook line.
	StrafeCurveBlendTime = 0.3,
}

-- Rope control on top of the Space reel, both on the real rope so the swing
-- carries on: hold SlowReelKey to shorten the wire(s) slowly (a tighter,
-- faster swing), hold ReleaseKey while hooked to pay the wire out for slack
-- (you drop and swing wider; let go and the rope holds at the new length).
-- LeftControl while not hooked still brakes.
ODMMovementConfig.Rope = {
	SlowReelKey = Enum.KeyCode.C,
	ReleaseKey = Enum.KeyCode.LeftControl,
	SlowReelSpeed = 18, -- studs of wire taken in per second
	ReleaseSpeed = 35, -- studs of wire paid out per second
	MinLength = 6, -- slow reel never takes the wire shorter than this
}

-- A/D while hooked orbit around the hook(s): somewhere between the
-- reference strafe and Odyssey's orbit. A sideways push around the hook
-- builds you up to orbit speed and eases off once you're there; gravity and
-- the rope stay in charge of everything else, so it still swings like a
-- pendulum instead of floating. With Space held, A/D curve the reel instead
-- (see Reel.StrafeCurve). Uses the strafe
-- gas costs (A drains the right tank, D the left).
ODMMovementConfig.Orbit = {
	Enabled = true, -- false goes back to the reference strafe
	Speed = 150, -- sideways speed the push builds you up to
	Responsiveness = 2.5, -- how quickly it closes the gap to that speed (per second)
	MaxAcceleration = 160, -- the push never accelerates you harder than this, studs/s^2
	MinAcceleration = 40, -- always at least this much push while below target
}

-- Odyssey's movement, used while Space is held when Reel.Style is "Odyssey".
-- Values are Odyssey's Gen 1 gear. Each step your velocity moves LerpSpeed of
-- the way (at 60 fps) towards the hook direction at
-- Speed * Momentum * BoostMultiplier. Momentum builds while you pull and
-- fades while you don't; starting a pull at speed rebuilds it from that speed.
ODMMovementConfig.Odyssey = {
	Speed = 145,
	BoostMultiplier = 1.18,
	LerpSpeed = 0.06,
	MaxForce = 99000,

	MomentumGain = 0.014, -- per step (60 fps) while pulling
	MomentumLoss = 0.00055, -- per step while not
	MinMomentum = 0.18,
	MaxMomentum = 1.35,
	RehookMomentumFromSpeed = 0.55,
	MinRetainedMomentum = 0.35,

	-- A/D while pulling: "Curve" bends the pull to that side (see
	-- Reel.StrafeCurve) so you spiral in; "Orbit" is Odyssey's orbit.
	SpaceStrafe = "Curve",
	OrbitSpeed = 210,
	OrbitBoostMultiplier = 1.25,
	OrbitLerpSpeed = 0.028,
	OrbitEntrySnapStrength = 1,
	MinOrbitDistance = 25,
	MaxOrbitDistance = 200,
}

-- The swing while Space isn't held. "Odyssey" is Odyssey's rope swing: the
-- rope locks at your distance plus RopeSlack and never takes itself in (use
-- the slow reel for that), with a very light drag on your whole velocity.
-- "Reference" is this gear's: the rope keeps taking in slack as you close in,
-- with horizontal air drag.
ODMMovementConfig.Swing = {
	Style = "Odyssey",
	RopeSlack = 1.25,
	VelocityDrag = 0.99935, -- velocity kept per step (60 fps), Odyssey style
}

-- Horizontal air drag, as a multiple of speed (the reference used 4). Swing
-- drag is while hooked on the "Reference" swing; air drag is while flying
-- unhooked.
ODMMovementConfig.SwingDrag = 2
ODMMovementConfig.AirDrag = 2

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

-- Losing at least this much speed in one tick while airborne or sliding (and
-- not bursting) splats the player: slamming into a wall or the ground.
ODMMovementConfig.SplatVelocityDelta = 120

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

-- Priority each movement animation plays at. Poses sit above the default
-- walk/fall animations and the gear idle; one-shots sit above the poses.
local P = Enum.AnimationPriority
ODMMovementConfig.AnimationPriorities = {
	Falling = P.Movement,
	GroundSlide = P.Movement,
	ForwardHooking = P.Movement,
	HookedBoostIdle = P.Movement,
	ForwardODM1 = P.Movement,
	ForwardODM2 = P.Movement,
	ForwardODM3 = P.Movement,
	ForwardODM4 = P.Movement,
	ForwardODM5 = P.Movement,
	EHookShoot = P.Action,
	QHookShoot = P.Action,
	FastFlip = P.Action2,
	SlowFlip = P.Action2,
	Boost = P.Action2,
	GasFlip = P.Action2,
	HookedBoost = P.Action2,
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
