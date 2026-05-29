local HitboxServer = {}

local dbg = true
function HitboxServer.Create(cframe: CFrame, size: Vector3, params: OverlapParams, onHit: (Model) -> ())
	if dbg then
		local part = Instance.new("Part")
		part.CFrame = cframe
		part.Size = size
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 0.5
		part.Color = Color3.fromRGB(255, 0, 0)
		part.Material = Enum.Material.Neon
		part.Parent = workspace
		game:GetService("Debris"):AddItem(part, 0.1)
	end

	local parts = workspace:GetPartBoundsInBox(cframe, size, params)
	local checked = {}
	for _, part in pairs(parts) do
		local model = part:FindFirstAncestorWhichIsA("Model")
		if not model then continue end
		if model:FindFirstChild("Humanoid") and model:FindFirstChild("Humanoid").Health <= 0 then continue end
		if table.find(checked, model) then continue end
		table.insert(checked, model)
		onHit(model)
	end
end

return HitboxServer