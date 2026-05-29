local Players = game:GetService("Players")
local player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage.Remotes

local ANIMATIONS = script.Animations

task.spawn(function()
	ContentProvider:PreloadAsync(ANIMATIONS:GetChildren())
end)

local TitanClient = {
	list = {}
}

-- Returns the neck Motor6D from a titan model (R15: Neck is in Head)
local function GetNeck(model)
	local head = model:FindFirstChild("Head")
	if not head then return nil end
	return head:FindFirstChild("Neck")
end

-- Given the titan's UpperTorso CFrame and a world target position,
-- returns the neck C0 using the exact same formula as BodyClient.
local function ComputeNeckC0(model, targetPosition)
	local upperTorso = model:FindFirstChild("UpperTorso")
	local head = model:FindFirstChild("Head")
	if not upperTorso or not head then return nil end

	-- Direction from head to target in world space
	local headPos = head.Position
	local toTarget = (targetPosition - headPos)
	if toTarget.Magnitude < 0.01 then return nil end
	toTarget = toTarget.Unit

	-- Convert to UpperTorso local space so pitch/yaw are body-relative
	local torsoSpaceDir = upperTorso.CFrame:VectorToObjectSpace(toTarget)

	local yOffset = head:GetAttribute("Offset")

	-- Exact same formula BodyClient uses for the player neck
	if model:GetAttribute("Grabbed") or model:GetAttribute("Blinded") then
		return CFrame.new(0, yOffset, 0)
	else
		return CFrame.new(0, yOffset, 0)
			* CFrame.Angles(0, -math.asin(math.clamp(torsoSpaceDir.X, -1, 1)), 0)
			* CFrame.Angles(math.asin(math.clamp(torsoSpaceDir.Y, -1, 1)), 0, 0)
	end
end

function TitanClient:SetupCollision(model)
	local UpperTorso = model:WaitForChild("UpperTorso")
	local LowerTorso = model:WaitForChild("LowerTorso")
	local Head = model:WaitForChild("Head")
	
	model:WaitForChild("FriendlyCollision").CanCollide = false
	model:WaitForChild("FriendlyCollision").CanQuery = false

	local combinedHeight = UpperTorso.Size.Y + LowerTorso.Size.Y
	local midPosition = UpperTorso.Position + UpperTorso.CFrame.UpVector * (-LowerTorso.Size.Y / 2)
	local combinedSize = Vector3.new(UpperTorso.Size.X, combinedHeight, UpperTorso.Size.Z) * 0.8

	local newCollision = Instance.new("Part")
	newCollision.Parent = model
	newCollision.Name = "ClientCollision"
	newCollision.Anchored = false
	newCollision.Size = combinedSize
	newCollision.Transparency = 1
	newCollision.CanCollide = true
	newCollision.Massless = true
	newCollision.CFrame = CFrame.new(midPosition)
	newCollision.CustomPhysicalProperties = PhysicalProperties.new(100, 0, 0, 100, 100)
	newCollision.CollisionGroup = "ClientCollision"

	local a0 = Instance.new("Attachment")
	a0.Parent = newCollision

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Parent = newCollision
	alignPosition.ApplyAtCenterOfMass = true
	alignPosition.ReactionForceEnabled = true
	alignPosition.Attachment0 = a0
	alignPosition.Position = UpperTorso.Position
	alignPosition.MaxVelocity = 50000000000
	alignPosition.MaxForce = 500000000000
	alignPosition.Responsiveness = 1000

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Parent = newCollision
	alignOrientation.ReactionTorqueEnabled = true
	alignOrientation.Attachment0 = a0
	alignOrientation.MaxTorque = 500000000000
	alignOrientation.MaxAngularVelocity = 50000000000
	alignOrientation.Responsiveness = 1000

	-- head part
	local headCollision = Instance.new("Part")
	headCollision.Parent = model
	headCollision.Name = "ClientCollisionHead"
	headCollision.Anchored = false
	headCollision.Size = Head.Size * 1.2
	headCollision.Transparency = 1
	headCollision.CanCollide = true
	headCollision.Massless = true
	headCollision.CFrame = Head.CFrame
		--newCollision.CFrame * CFrame.new(0, combinedHeight / 2 + Head.Size.Y / 2, 0)
	headCollision.CustomPhysicalProperties = PhysicalProperties.new(100, 0, 0, 100, 100)
	headCollision.CollisionGroup = "ClientCollision"
	headCollision.Shape = Enum.PartType.Ball

	local weld = Instance.new("WeldConstraint")
	weld.Parent = headCollision
	weld.Part0 = headCollision
	weld.Part1 = Head
end

function TitanClient:SetupGrabs(model)
	for _, v in pairs(model:WaitForChild("TouchBox"):GetChildren()) do
		if not v:GetAttribute("Setup") then
			v.Touched:Connect(function(hit)
				local character = player.Character
				if not character then return end
				if character ~= hit.Parent then return end
				local AnimationController : AnimationController = model:FindFirstChild("AnimationController")
				if not AnimationController or not AnimationController:FindFirstChild("Animator") then
					return
				end
				
				local grabAnimationPlaying = false
				local side = nil
				for j, k in pairs(AnimationController.Animator:GetPlayingAnimationTracks()) do
					for m, n in pairs(script.Animations:GetChildren()) do
						if n.AnimationId == k.Animation.AnimationId then
							if string.find(n.Name, "Grab") then
								grabAnimationPlaying = true
								if string.find(n.Name, "Left") then
									side = "Left"
								else
									side = "Right"
								end
								break
							end
						end
						if grabAnimationPlaying then
							break
						end
					end
					if grabAnimationPlaying then
						break
					end
				end

				if not grabAnimationPlaying or side ~= v.Name then return end
				
				Remotes.Titan.GrabMe:FireServer(model.Name, v.Name)
			end)
			v:SetAttribute("Setup", true)
		end
	end
end

function TitanClient:Add(model)
	TitanClient:SetupGrabs(model)
	TitanClient:SetupCollision(model)
	table.insert(TitanClient.list, model)
end

function TitanClient:Remove(model)
	if model:FindFirstChild("ClientCollision") then
		model.ClientCollision:Destroy()
	end
	if model:FindFirstChild("ClientCollisionHead") then
		model.ClientCollisionHead:Destroy()
	end
	table.remove(TitanClient.list, table.find(TitanClient.list, model))
end

function TitanClient:UpdateAll()
	for i, model in pairs(TitanClient.list) do
		-- Update collision position
		local collision = model:FindFirstChild("ClientCollision")
		if collision then
			local UpperTorso = model:FindFirstChild("UpperTorso")
			local LowerTorso = model:FindFirstChild("LowerTorso")
			if UpperTorso and LowerTorso then
				local combinedHeight = UpperTorso.Size.Y + LowerTorso.Size.Y
				local midPosition = UpperTorso.Position + UpperTorso.CFrame.UpVector * (-LowerTorso.Size.Y / 2)
				collision.AlignPosition.Position = midPosition
				collision.AlignOrientation.CFrame = UpperTorso.CFrame
			end
		end

		-- Update neck look-at
		local lookPositionValue = model:FindFirstChild("LookPosition")
		if lookPositionValue and lookPositionValue:IsA("Vector3Value") then
			local neck = GetNeck(model)
			if neck then
				local targetC0 = ComputeNeckC0(model, lookPositionValue.Value)
				if targetC0 then
					neck.C0 = neck.C0:Lerp(targetC0, 0.15)
				end
			end
		end
	end
end

for i, v in pairs(workspace.Titans.Alive:GetChildren()) do
	TitanClient:Add(v)
end
workspace.Titans.Alive.ChildAdded:Connect(function(v)
	TitanClient:Add(v)
end)
workspace.Titans.Alive.ChildRemoved:Connect(function(v)
	TitanClient:Remove(v)
end)

local UPDATE_RATE = 1/30
local lastUpdate = -math.huge
RunService.RenderStepped:Connect(function()
	if os.clock() - lastUpdate >= UPDATE_RATE then
		lastUpdate = os.clock()
		TitanClient:UpdateAll()
	end
end)

return TitanClient