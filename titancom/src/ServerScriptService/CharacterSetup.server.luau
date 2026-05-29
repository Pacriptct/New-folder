local titanService = require(script.Parent.OdysseyEngine.Services.TitanService)

local charFolder = Instance.new("Folder")
charFolder.Name = "Characters"
charFolder.Parent = workspace

local Players = game:GetService("Players")

local function setupCharacter(player, character)
	character.Parent = workspace.Characters

	for i, v in pairs(character:GetDescendants()) do
		if v:IsA("BasePart") then
			v.CollisionGroup = "PlayerCharacter"
		end
	end

	local humanoid = character:FindFirstChild("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	humanoid.BreakJointsOnDeath = false
	player:SetAttribute("Ragdolled", false)
	player:SetAttribute("RagdollToken", 0)

	local Token = 0
	local function UpdateRagdoll()
		local ragdolled = player:GetAttribute("Ragdolled")
		local ragdollTime = player:GetAttribute("RagdollTime") or 2
		Token += 1
		local MyToken = Token

		if not ragdolled and humanoid.Health > 0 then
			for _, v in pairs(character:GetDescendants()) do
				if v:IsA("Motor6D") and v.Parent:IsA("BasePart") then
					local ball = v.Parent:FindFirstChild(v.Name .. "_Ball")
					if ball then ball.Enabled = false end
					v.Enabled = true
				end
			end
		else
			local ignoreJoints = {"LeftWrist", "RightWrist", "LeftAnkle", "RightAnkle", "Motor6D"}
			for _, v in pairs(character:GetDescendants()) do
				if v:IsA("Motor6D") and v.Parent:IsA("BasePart")
					and v.Parent.Parent == character
					and not table.find(ignoreJoints, v.Name)
				then
					local ball = v.Parent:FindFirstChild(v.Name .. "_Ball")
					if not ball then
						ball = Instance.new("BallSocketConstraint")
						ball.Parent = v.Parent
						ball.Name = v.Name .. "_Ball"
						local a0 = Instance.new("Attachment")
						local a1 = Instance.new("Attachment")
						a0.Parent, a1.Parent = v.Part0, v.Part1
						ball.Attachment0, ball.Attachment1 = a0, a1
						a0.CFrame, a1.CFrame = v.C0, v.C1
						ball.LimitsEnabled = true
						ball.TwistLimitsEnabled = true
						ball.Enabled = false
					end
					ball.Enabled = true
					v.Enabled = false
				end
			end

			task.delay(ragdollTime, function()
				if Token == MyToken and humanoid.Health > 0 then
					player:SetAttribute("Ragdolled", false)
					player:SetAttribute("RagdollPushForce", 0)
				end
			end)
		end
	end

	player:GetAttributeChangedSignal("RagdollToken"):Connect(function()
		local token = player:GetAttribute("RagdollToken")
		if not token or token == 0 then
			player:SetAttribute("Ragdolled", false)
		else
			player:SetAttribute("Ragdolled", true)
			UpdateRagdoll()
		end
	end)

	player:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if not player:GetAttribute("Ragdolled") then
			UpdateRagdoll()
		end
	end)

	humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		if humanoid.Health == 0 then
			player:SetAttribute("RagdollTime", 3)
			player:SetAttribute("Ragdolled", true)

			local ignoreJoints = {"LeftWrist", "RightWrist", "LeftAnkle", "RightAnkle", "Motor6D"}
			for _, v in pairs(character:GetDescendants()) do
				if v:IsA("Motor6D") and v.Parent.Parent == character
					and not table.find(ignoreJoints, v.Name)
				then
					local ball = v.Parent:FindFirstChild(v.Name .. "_Ball")
					if not ball then
						ball = Instance.new("BallSocketConstraint")
						ball.Parent = v.Parent
						ball.Name = v.Name .. "_Ball"
						local a0 = Instance.new("Attachment")
						local a1 = Instance.new("Attachment")
						a0.Parent, a1.Parent = v.Part0, v.Part1
						ball.Attachment0, ball.Attachment1 = a0, a1
						a0.CFrame, a1.CFrame = v.C0, v.C1
						ball.LimitsEnabled = true
						ball.TwistLimitsEnabled = true
						ball.Enabled = false
					end
					ball.Enabled = true
					v.Enabled = false
				end
			end
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	table.insert(titanService.cachedPlayers, player)
	
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
end)
Players.PlayerRemoving:Connect(function(player)
	if table.find(titanService.cachedPlayers, player) then
		table.remove(titanService.cachedPlayers, table.find(titanService.cachedPlayers, player))
	end
end)