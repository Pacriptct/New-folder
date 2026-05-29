local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local lastRagdoll = -math.huge
local lastRagdollToken = 0
local lastBounced = -math.huge

local RagdollClient = {}

player:GetAttributeChangedSignal("RagdollPushDirection"):Connect(function()
	if player:GetAttribute("Grabbed") then return end
	if os.clock() - lastBounced <= 0.4 then return end
	lastBounced = os.clock()
	local character = player.Character
	local root = character and character.PrimaryPart
	if not root then return end
	local direction = player:GetAttribute("RagdollPushDirection")
	local force = player:GetAttribute("RagdollPushForce")
	if not direction or not force then return end
	root:ApplyImpulse(direction.Unit * math.clamp(force * root.AssemblyMass, 0, 6000))
end)

RunService.RenderStepped:Connect(function()
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local isRagdolled = player:GetAttribute("Ragdolled")
	local ragdollTime = player:GetAttribute("RagdollTime")
	local ragdollActive = isRagdolled and ragdollTime and os.clock() - lastRagdoll <= ragdollTime

	for _, v in pairs(character:GetChildren()) do
		if v:IsA("BasePart") and not string.find(v.Name, "Hook") then
			if v.Name ~= "HumanoidRootPart" and v.Name ~= "Torso" and v.Name ~= "Head" then
				v.CanCollide = isRagdolled == true
			end
		end
	end

	for _, v in pairs(character:GetChildren()) do
		if v:IsA("BasePart") then
			v.CustomPhysicalProperties = isRagdolled
				and PhysicalProperties.new(1, .2, 0, 100, 100)
				or PhysicalProperties.new(1, 0, 0, 100, 100)
		end
	end

	if isRagdolled then
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	else
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)

	if player:GetAttribute("RagdollToken") ~= lastRagdollToken then
		lastRagdollToken = player:GetAttribute("RagdollToken")
		if isRagdolled then
			lastRagdoll = os.clock()
		end
	end
end)

return RagdollClient