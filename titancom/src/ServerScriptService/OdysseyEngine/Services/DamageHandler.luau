local DamageHandler = {}

function DamageHandler:Damage(character, amount)
	if not character or character.Parent == nil then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	humanoid.Health = math.max(0, humanoid.Health - amount)
end

function DamageHandler:Kill(character)
	if not character or character.Parent == nil then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	humanoid.Health = 0
end

function DamageHandler:Ragdoll(player, time)
	if not player then return end
	player:SetAttribute("RagdollTime", time or 2)
	player:SetAttribute("RagdollToken", (player:GetAttribute("RagdollToken") or 0) + 1)
end

function DamageHandler:Knockback(player, force, direction, time)
	if not player then return end
	if player:GetAttribute("Grabbed") then return end
	player:SetAttribute("RagdollPushForce", force)
	player:SetAttribute("RagdollPushDirection", direction)
	player:SetAttribute("RagdollTime", time or 2)
	player:SetAttribute("RagdollToken", (player:GetAttribute("RagdollToken") or 0) + 1)
end

return DamageHandler