local PhysicsService = game:GetService("PhysicsService")

local groups = {
	"PlayerCharacter",
	"ClientCollision",
}

local noCollide = {
	{"ClientCollision", "ClientCollision", false},
	{"ClientCollision", "Default", false},
	-- PlayerCharacter
	{"PlayerCharacter", "PlayerCharacter", true},
	{"PlayerCharacter", "ClientCollision", true},
}

for _, group in pairs(groups) do
	PhysicsService:RegisterCollisionGroup(group)
end
for _, pair in pairs(noCollide) do
	PhysicsService:CollisionGroupSetCollidable(pair[1], pair[2], pair[3])
end