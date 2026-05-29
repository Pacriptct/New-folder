local Players = game:GetService("Players")
local RunService = game:GetService("RunService")


local player = Players.LocalPlayer
local gui = script.Parent
local speedLabel = gui:FindFirstChild("speedLabel")



RunService.RenderStepped:Connect(function()
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local velocity = hrp.AssemblyLinearVelocity
	local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local totalSpeed = velocity.Magnitude

	speedLabel.Text = string.format(
		"Speed: %.1f | Total: %.1f",
		flatSpeed,
		totalSpeed
	)
end)