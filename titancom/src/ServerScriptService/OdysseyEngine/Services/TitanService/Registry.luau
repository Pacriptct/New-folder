local Registry = {}
Registry.__index = Registry

local titans = {}

function Registry:Add(titan)
	table.insert(titans, titan)
end

function Registry:Remove(titan)
	local idx = table.find(titans, titan)
	if idx then table.remove(titans, idx) end
end

function Registry:GetAll()
	return titans
end

function Registry:GetByModel(model)
	for _, titan in pairs(titans) do
		if titan.model == model then
			return titan
		end
	end
	return nil
end	

function Registry:GetCount()
	return #titans
end

function Registry:GetNearest(position)
	local nearest, nearestDist = nil, math.huge
	for _, titan in pairs(titans) do
		local dist = (titan.rootPart.Position - position).Magnitude
		if dist < nearestDist then
			nearest = titan
			nearestDist = dist
		end
	end
	return nearest
end

return Registry