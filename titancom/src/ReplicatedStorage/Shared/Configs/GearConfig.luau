local GearConfig = {}

GearConfig.DefaultPreset = "Gen1Gear"

GearConfig.Presets = {
	Gen1Gear = {
		DisplayName = "Gen 1 Gear",

		GrappleRange = 750,

		MaxForce = Vector3.new(90000, 90000, 90000),
		MaxTorque = Vector3.new(30000, 30000, 30000),

		Speed = 135,
		BoostMultiplier = 1.18,

		LerpSpeed = 0.06,
		OrbitLerpSpeed = 0.12,

		OrbitSpeed = 165,
		OrbitBoostMultiplier = 1.12,
		OrbitBoostDistanceMultiplier = 1.0,
		OrbitEntrySnapStrength = 1.0,
		OrbitTightenDuration = 0,
		MinOrbitDistance = 95,
		MaxOrbitDistance = 200,

		OutOfGasSwingEnabled = true,
		OutOfGasRopeSlack = 1.25,
		OutOfGasRopeRestitution = 0,
		OutOfGasRopeVisible = false,
		OutOfGasVelocityDrag = 0.99935,
		OutOfGasUseGyro = true,
		OutOfGasGyroTorqueMultiplier = 0.25,

		VDashEnabled = true,
		VDashRequiresDoubleHook = true,
		VDashSpeed = 225,
		VDashRange = 120,
		VDashMaxHoldTime = 5,
		VDashCooldown = 1.25,
		VDashEndSpeedRetention = 1.35,
		VDashMinTargetDistance = 10,
		VDashAttachGraceTime = 0.2,

		MomentumGain = 0.014,
		MomentumLoss = 0.000055,
		MinMomentum = 0.18,
		MaxMomentum = 1.35,

		SpeedRetentionMultiplier = 0.98,
		ReleaseForwardBoost = 1.02,
		MaxReleaseSpeed = 250,
		ReleaseVerticalPreserve = 0.9,
		MaxUpwardReleaseSpeed = 70,
		ReleaseCarryTime = 0.6,

		RehookMomentumFromSpeed = 0.55,
		MinRetainedMomentum = 0.35,

		SpeedLineMinSpeed = 115,

		GroundSlideHookedStartSpeed = 40,
		GroundSlideReleaseStartSpeed = 28,
		GroundSlideStopSpeed = 7,

		GroundSlideDragMultiplier = 2.2,
		GroundSlideHighSpeedThreshold = 145,
		GroundSlideHighSpeedDragMultiplier = 1.25,

		GroundSlideVFXMinSpeed = 55,
		GroundSlideVFXMaxSpeed = 135,

		GroundSlideDirtMinSpeed = 55,
		GroundSlideDirtMinRate = 0,
		GroundSlideDirtMaxRate = 28,

		GroundSlideSparksMinSpeed = 105,
		GroundSlideSparksMinRate = 0,
		GroundSlideSparksMaxRate = 22,

		HookTravelSpeed = 850,
		HookTravelMaxDistance = 750,
		HookVisualSize = Vector3.new(0.25, 0.25, 0.25),

		HookClipEnabled = true,
		HookClipMinDistance = 2,

		RopeWidth = 0.08,
		RopeTweenOutWidth = 0.15,
		RopeSegments = 50,

		RopeCurveOut0 = 12,
		RopeCurveOut1 = -12,
		RopeCurveIn0 = 0,
		RopeCurveIn1 = 0,

		RopeTweenOutTime = 0.16,
		RopeTweenHoldTime = 0.1,
		RopeTweenInTime = 0.22,

		RopeRetractTweenTime = 0.16,
		RopeRetractCurve0 = -4,
		RopeRetractCurve1 = 8,

		GroundHookWalkSpeed = 0,
	},

	Gen4Gear = {
		DisplayName = "Gen 4 Gear",
		BasedOn = "Gen1Gear",

		GrappleRange = 750,

		Speed = 120,
		BoostMultiplier = 1.42,

		LerpSpeed = 0.055,
		OrbitLerpSpeed = 0.14,

		OrbitSpeed = 195,
		OrbitBoostMultiplier = 1.22,
		OrbitBoostDistanceMultiplier = 1.0,
		OrbitEntrySnapStrength = 1.0,
		OrbitTightenDuration = 0,
		MinOrbitDistance = 85,
		MaxOrbitDistance = 220,

		OutOfGasRopeSlack = 1.25,
		OutOfGasRopeRestitution = 0,
		OutOfGasVelocityDrag = 0.9995,
		OutOfGasUseGyro = true,
		OutOfGasGyroTorqueMultiplier = 0.35,

		MomentumGain = 0.014,
		MomentumLoss = 0.000055,
		MinMomentum = 0.18,
		MaxMomentum = 1.35,

		SpeedRetentionMultiplier = 0.92,
		ReleaseForwardBoost = 1.02,
		MaxReleaseSpeed = 205,
		ReleaseVerticalPreserve = 0.9,
		MaxUpwardReleaseSpeed = 70,
		ReleaseCarryTime = 0.6,

		RehookMomentumFromSpeed = 0.78,
		MinRetainedMomentum = 0.55,

		SpeedLineMinSpeed = 95,

		GroundSlideHookedStartSpeed = 60,
		GroundSlideReleaseStartSpeed = 45,
		GroundSlideStopSpeed = 16,

		GroundSlideDragMultiplier = 1.65,
		GroundSlideHighSpeedThreshold = 190,
		GroundSlideHighSpeedDragMultiplier = 1.15,

		GroundSlideVFXMinSpeed = 65,
		GroundSlideVFXMaxSpeed = 180,

		GroundSlideDirtMinSpeed = 70,
		GroundSlideDirtMaxRate = 38,

		GroundSlideSparksMinSpeed = 125,
		GroundSlideSparksMaxRate = 35,

		HookTravelSpeed = 850,
		HookTravelMaxDistance = 250,

		RopeTweenOutTime = 0.12,
		RopeTweenHoldTime = 0.12,
		RopeTweenInTime = 0.18,

		RopeRetractTweenTime = 0.12,
	},
}

local function deepCopy(original)
	local copy = {}

	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = deepCopy(value)
		else
			copy[key] = value
		end
	end

	return copy
end

local function mergeInto(base, overrides)
	for key, value in pairs(overrides) do
		if key ~= "BasedOn" then
			if type(value) == "table" and type(base[key]) == "table" then
				mergeInto(base[key], value)
			else
				base[key] = value
			end
		end
	end

	return base
end

function GearConfig.GetPreset(presetName: any)
	local selectedName = presetName or GearConfig.DefaultPreset
	local selected = GearConfig.Presets[selectedName]

	if not selected then
		warn(`[GearConfig] Missing preset "{selectedName}", falling back to "{GearConfig.DefaultPreset}"`)
		selectedName = GearConfig.DefaultPreset
		selected = GearConfig.Presets[selectedName]
	end

	if not selected then
		error("[GearConfig] DefaultPreset is missing.")
	end

	if selected.BasedOn then
		local basePreset = GearConfig.Presets[selected.BasedOn]

		if not basePreset then
			error(`[GearConfig] Preset "{selectedName}" is based on missing preset "{selected.BasedOn}".`)
		end

		local merged = deepCopy(basePreset)
		mergeInto(merged, selected)
		merged.PresetName = selectedName

		return merged
	end

	local copied = deepCopy(selected)
	copied.PresetName = selectedName

	return copied
end

function GearConfig.GetPresetNames(): { string }
	local names = {}

	for name in pairs(GearConfig.Presets) do
		table.insert(names, name)
	end

	table.sort(names)

	return names
end

function GearConfig.HasPreset(presetName: string): boolean
	return GearConfig.Presets[presetName] ~= nil
end

return GearConfig