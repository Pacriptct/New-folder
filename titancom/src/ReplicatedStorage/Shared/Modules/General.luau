local General = {}

local RS = game:GetService("ReplicatedStorage")

local function WeldParts(P0, C0, P1, C1, Name, Parent)
	local Weld = Instance.new("Weld")
	Weld.Part0 = P0
	Weld.C0 = C0
	Weld.Part1 = P1
	Weld.C1 = C1
	Weld.Name = Name
	Weld.Parent = Parent or P0
end

function General:GetSideWallHit(character, rootPart, distance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local origin = rootPart.Position
	local right = rootPart.CFrame.RightVector
	local forward = rootPart.CFrame.LookVector

	local checks = {
		{ Side = "Left", Direction = -right },
		{ Side = "Left", Direction = (-right + forward * 0.45).Unit },
		{ Side = "Left", Direction = (-right - forward * 0.25).Unit },

		{ Side = "Right", Direction = right },
		{ Side = "Right", Direction = (right + forward * 0.45).Unit },
		{ Side = "Right", Direction = (right - forward * 0.25).Unit },
	}

	for _, check in checks do
		local hit = workspace:Raycast(origin, check.Direction * distance, params)

		if hit and hit.Instance and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide then
			return check.Side, hit
		end
	end

	return nil, nil
end

function General:SetModelTransparency(model, transparency)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Name == "SwordHB" then
				descendant.Transparency = 1
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = true
				descendant.CastShadow = false
			else
				descendant.Transparency = transparency
			end
		end
	end
end

function General:GetHandCFrame(armCF)
	local handOffset = Vector3.new(0.05, -1.2, 0)
	return ((armCF * CFrame.new(handOffset)) * CFrame.Angles(0, math.rad(90), 135)):Inverse()
end

function General:EquipODM(Player: Player)
	local Character = Player.Character
	if not Character then
		return
	end

	task.spawn(function()
		local GearFolder = RS.Assets.Gear.Model

		local Torso = Character:FindFirstChild("Torso")
		local RightArm = Character:FindFirstChild("Right Arm")
		local LeftArm = Character:FindFirstChild("Left Arm")

		if not Torso or not RightArm or not LeftArm then
			warn("[General] ODM equip requires R6 character parts.")
			return
		end

		local Gear = GearFolder:FindFirstChild("Gear"):Clone()
		Gear.Parent = Character
		Gear.PrimaryPart.CFrame = Torso.CFrame

		WeldParts(Torso, Torso.CFrame:Inverse(), Gear.PrimaryPart, Gear.PrimaryPart.CFrame:Inverse(), "GearWeld", Gear)

		local RSword = GearFolder:FindFirstChild("Sword"):Clone()
		RSword.Name = "RightSword"
		RSword.Parent = Character
		General:SetModelTransparency(RSword, 1)

		Gear.HookShooters.CordRight.Attachment1 = RSword.Handle.CordEnd1

		RSword.PrimaryPart.CFrame = RightArm.CFrame
		WeldParts(
			RightArm,
			General:GetHandCFrame(RightArm.CFrame),
			RSword.PrimaryPart,
			RSword.PrimaryPart.CFrame:Inverse(),
			"RSwordWeld",
			RSword
		)

		local LSword = GearFolder:FindFirstChild("Sword"):Clone()
		LSword.Name = "LeftSword"
		LSword.Parent = Character
		General:SetModelTransparency(LSword, 1)

		Gear.HookShooters.CordLeft.Attachment1 = LSword.Handle.CordEnd1

		LSword.PrimaryPart.CFrame = LeftArm.CFrame
		WeldParts(
			LeftArm,
			General:GetHandCFrame(LeftArm.CFrame),
			LSword.PrimaryPart,
			LSword.PrimaryPart.CFrame:Inverse(),
			"LSwordWeld",
			LSword
		)

		local RSwordHolstered = GearFolder:FindFirstChild("HolsteredSword"):Clone()
		RSwordHolstered.Name = "RightSwordHolstered"
		RSwordHolstered.Parent = Character
		RSwordHolstered.PrimaryPart.CFrame = Torso.CFrame

		local RTorsoOffset = Vector3.new((Torso.Size.X / 2) + 0.05, 0, 0)
		local RSwordCFrame = ((CFrame.new() * CFrame.new(RTorsoOffset)) * CFrame.Angles(
			math.rad(-180),
			math.rad(90),
			math.rad(25)
		)):Inverse()
		local RTorsoCFrame = CFrame.new() * CFrame.Angles(0, math.rad(180), 0)

		WeldParts(
			Torso,
			RTorsoCFrame,
			RSwordHolstered.PrimaryPart,
			RSwordCFrame,
			"RightSwordHolsterWeld",
			RSwordHolstered
		)

		local LSwordHolstered = GearFolder:FindFirstChild("HolsteredSword"):Clone()
		LSwordHolstered.Name = "LeftSwordHolstered"
		LSwordHolstered.Parent = Character
		LSwordHolstered.PrimaryPart.CFrame = Torso.CFrame

		local LTorsoOffset = Vector3.new((-Torso.Size.X / 2) + 0.05, 0, 0)
		local LSwordCFrame = ((CFrame.new() * CFrame.new(LTorsoOffset)) * CFrame.Angles(
			math.rad(-180),
			math.rad(90),
			math.rad(25)
		)):Inverse()
		local LTorsoCFrame = CFrame.new() * CFrame.Angles(0, math.rad(180), 0)

		WeldParts(
			Torso,
			LTorsoCFrame,
			LSwordHolstered.PrimaryPart,
			LSwordCFrame,
			"LeftSwordHolsterWeld",
			LSwordHolstered
		)

		General:SetModelTransparency(RSword, 1)
		General:SetModelTransparency(LSword, 1)

		General:SetModelTransparency(RSwordHolstered, 0)
		General:SetModelTransparency(LSwordHolstered, 0)
	end)
end

return General
