-- ReplicatedStorage.Shared.Gear.ODMGearParts
--
-- Finds the pieces of a character's ODM gear the movement needs (launchers,
-- effects, sounds) and builds the movers on the HumanoidRootPart.
--
-- Effects and sounds are looked up by the reference gear's names first
-- (GearNexus.MainBoost, GearNexus.GasHiss, ...). When the gear model doesn't
-- have them, the Odyssey gear equivalents are used (GasPart's GAS emitters,
-- bootLeft / bootRight trails, ...). Missing pieces resolve to nothing, so a
-- trimmed gear model just plays fewer effects.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ODMMovementConfig = require(ReplicatedStorage.Shared.Configs.Gear.ODMMovementConfig)

local ODMGearParts = {}

ODMGearParts.EffectKeys = {
	LeftBoost = true,
	RightBoost = true,
	UpBoost = true,
	DownBoost = true,
	MainBoost = true,
	BoostTrail = true,
	Gas = true,
	LeftSlideDirt = true,
	RightSlideDirt = true,
	LeftSlideSparks = true,
	RightSlideSparks = true,
}

ODMGearParts.SoundKeys = {
	Shot = true,
	Retract = true,
	GasBurst = true,
	GasHiss = true,
	Snap = true,
}

ODMGearParts.ForceNames = {
	"BoostForce",
	"ReelVelocity",
	"BoostGyro",
	"BodyGyro",
	"HookForce",
	"StrafeForce",
	"DragForce",
	"FlipForce",
	"VerticalForce",
}

local function isEffect(instance: Instance): boolean
	return instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail")
end

local function collectNamed(root: Instance?, names: { string }, out: { Instance })
	if not root then
		return
	end
	for _, descendant in root:GetDescendants() do
		if isEffect(descendant) and table.find(names, descendant.Name) then
			table.insert(out, descendant)
		end
	end
end

function ODMGearParts.getGear(character: Model?): Instance?
	if not character then
		return nil
	end
	return character:FindFirstChild("Gear") or character:FindFirstChild("ODMGFolder")
end

-- The part effects and sounds hang off: the reference GearNexus, or Odyssey's
-- GasPart.
function ODMGearParts.getNexus(character: Model?): Instance?
	local gear = ODMGearParts.getGear(character)
	if not gear then
		return nil
	end
	return gear:FindFirstChild("GearNexus", true) or gear:FindFirstChild("GasPart", true)
end

function ODMGearParts.getLauncher(character: Model?, side: string): Instance?
	if not character then
		return nil
	end
	return character:FindFirstChild(side .. "Launcher", true)
end

function ODMGearParts.getFirePoint(character: Model?, side: string): Attachment?
	local launcher = ODMGearParts.getLauncher(character, side)
	local firePoint = launcher and launcher:FindFirstChild("FirePoint", true)
	if firePoint and firePoint:IsA("Attachment") then
		return firePoint
	end
	return nil
end

function ODMGearParts.getScabbard(character: Model?, side: string): Instance?
	local gear = ODMGearParts.getGear(character)
	return gear and gear:FindFirstChild(side .. "Scabbard", true) or nil
end

-- Every effect instance behind one of the EffectKeys.
function ODMGearParts.getEffects(character: Model?, key: string): { Instance }
	local found = {}
	local nexus = ODMGearParts.getNexus(character)

	local slideSide, slideKind = string.match(key, "^(%a-)Slide(%a+)$")
	if slideSide and slideKind then
		local scabbard = ODMGearParts.getScabbard(character, slideSide)
		local slide = scabbard and scabbard:FindFirstChild("SlideAttachment", true)
		collectNamed(slide, { slideKind }, found)
		return found
	end

	if nexus then
		local direct = nexus:FindFirstChild(key)
		if direct then
			if isEffect(direct) then
				table.insert(found, direct)
			else
				for _, descendant in direct:GetDescendants() do
					if isEffect(descendant) then
						table.insert(found, descendant)
					end
				end
			end
			if #found > 0 then
				return found
			end
		end
	end

	-- Odyssey gear equivalents. Strafing left is pushed by the right-hand jet
	-- (and the other way round), as the Odyssey orbit trails do.
	if key == "LeftBoost" then
		collectNamed(nexus, { "bootRight" }, found)
	elseif key == "RightBoost" then
		collectNamed(nexus, { "bootLeft" }, found)
	elseif key == "MainBoost" then
		collectNamed(nexus, { "GAS" }, found)
	elseif key == "BoostTrail" then
		collectNamed(nexus, { "Trail" }, found)
	elseif key == "Gas" then
		collectNamed(nexus, { "Smoke" }, found)
	end
	return found
end

-- The burst / flip puff: GearNexus.Impulse's emitters, or Odyssey's Jet / Jet2.
function ODMGearParts.getImpulseEmitters(character: Model?): { Instance }
	local found = {}
	local nexus = ODMGearParts.getNexus(character)
	if not nexus then
		return found
	end
	local impulse = nexus:FindFirstChild("Impulse")
	if impulse then
		for _, child in impulse:GetChildren() do
			if child:IsA("ParticleEmitter") then
				table.insert(found, child)
			end
		end
		return found
	end
	collectNamed(nexus, { "Jet", "Jet2" }, found)
	return found
end

function ODMGearParts.getScabbardTrail(character: Model?, side: string): Trail?
	local scabbard = ODMGearParts.getScabbard(character, side)
	local trail = scabbard and scabbard:FindFirstChild("Trail")
	if trail and trail:IsA("Trail") then
		return trail
	end
	return nil
end

function ODMGearParts.getSound(character: Model?, key: string): Sound?
	local nexus = ODMGearParts.getNexus(character)
	local sound = nexus and nexus:FindFirstChild(key, true)
	if sound and sound:IsA("Sound") then
		return sound
	end
	return nil
end

------------------------------------------------------------
-- Movers (server, when the gear is equipped)
------------------------------------------------------------

local function vectorForce(root: BasePart, attachment: Attachment, name: string, force: Vector3, enabled: boolean)
	local mover = Instance.new("VectorForce")
	mover.ApplyAtCenterOfMass = true
	mover.Attachment0 = attachment
	mover.Force = force
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.Name = name
	mover.Enabled = enabled
	mover.Parent = root
	return mover
end

function ODMGearParts.buildForces(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local attachment = root and root:FindFirstChild("RootAttachment") :: Attachment?
	if not root or not attachment then
		return
	end
	ODMGearParts.removeForces(character)

	local cfg = ODMMovementConfig.Forces

	local boostForce = Instance.new("LinearVelocity")
	boostForce.Attachment0 = attachment
	boostForce.Enabled = false
	boostForce.RelativeTo = Enum.ActuatorRelativeTo.World
	boostForce.MaxForce = cfg.BoostMaxForce
	boostForce.Name = "BoostForce"
	boostForce.Parent = root

	-- Odyssey-style pull while Space is held (ODMMovementClient sets its
	-- velocity each step; off otherwise).
	local reelVelocity = Instance.new("LinearVelocity")
	reelVelocity.Attachment0 = attachment
	reelVelocity.Enabled = false
	reelVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	reelVelocity.MaxForce = ODMMovementConfig.Odyssey.MaxForce
	reelVelocity.Name = "ReelVelocity"
	reelVelocity.Parent = root

	local boostGyro = Instance.new("BodyGyro")
	boostGyro.MaxTorque = Vector3.zero
	boostGyro.P = 0
	boostGyro.D = cfg.BoostGyroD
	boostGyro.Name = "BoostGyro"
	boostGyro.Parent = root

	local bodyGyro = Instance.new("AlignOrientation")
	bodyGyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
	bodyGyro.Attachment0 = attachment
	bodyGyro.Responsiveness = cfg.BodyGyroResponsiveness
	bodyGyro.MaxTorque = cfg.BodyGyroMaxTorque
	bodyGyro.Enabled = false
	bodyGyro.Name = "BodyGyro"
	bodyGyro.Parent = root

	vectorForce(root, attachment, "HookForce", Vector3.zero, true)
	vectorForce(root, attachment, "StrafeForce", Vector3.zero, true)
	vectorForce(root, attachment, "DragForce", Vector3.zero, true)
	vectorForce(root, attachment, "FlipForce", cfg.FlipForce, false)
	vectorForce(root, attachment, "VerticalForce", Vector3.zero, false)
end

function ODMGearParts.removeForces(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, name in ODMGearParts.ForceNames do
		local existing = root:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
end

return ODMGearParts
