local PhysicsService = game:GetService("PhysicsService")

local groups = {
	"PlayerCharacter",
	"TitanBody",
	"TitanRoot",
	"TitanCollision",
	"ClientCollision",
	"TitanHitbox",
	"DeadTitanLimb",
	"DeadTitanTorso",
}

local noCollide = {
	{"TitanRoot", "TitanCollision", false},
	{"TitanCollision", "TitanCollision", true},
	{"TitanBody", "TitanCollision", false},
	{"ClientCollision", "ClientCollision", false},
	{"ClientCollision", "TitanRoot", false},
	{"ClientCollision", "TitanCollision", false},
	{"ClientCollision", "TitanBody", false},
	{"ClientCollision", "Default", false},
	{"TitanRoot", "TitanRoot", false},
	-- PlayerCharacter
	{"PlayerCharacter", "PlayerCharacter", true},
	{"PlayerCharacter", "TitanBody", true},
	{"PlayerCharacter", "TitanRoot", false},
	{"PlayerCharacter", "TitanCollision", false},
	{"PlayerCharacter", "TitanHitbox", false},
	{"PlayerCharacter", "ClientCollision", true},
	{"PlayerCharacter", "DeadTitanLimb", false},
	{"PlayerCharacter", "DeadTitanTorso", false},
	-- DeadTitanLimb
	{"DeadTitanLimb", "DeadTitanLimb", false},
	{"DeadTitanLimb", "DeadTitanTorso", true},
	{"DeadTitanLimb", "TitanCollision", false},
	{"DeadTitanLimb", "TitanBody", false},
	{"DeadTitanLimb", "TitanRoot", false},
	-- DeadTitanTorso
	{"DeadTitanTorso", "DeadTitanTorso", true},
	{"DeadTitanTorso", "TitanCollision", false},
	{"DeadTitanTorso", "TitanBody", false},
	{"DeadTitanTorso", "TitanRoot", false},
}

for _, group in pairs(groups) do
	PhysicsService:RegisterCollisionGroup(group)
end
for _, pair in pairs(noCollide) do
	PhysicsService:CollisionGroupSetCollidable(pair[1], pair[2], pair[3])
end