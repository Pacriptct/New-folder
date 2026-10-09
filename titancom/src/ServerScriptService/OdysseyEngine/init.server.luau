local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioGroups = require(ReplicatedStorage.Shared.Modules.AudioGroups)
AudioGroups.ensure()
AudioGroups.startAutoRoute()


game:GetService("Players").CharacterAutoLoads = true

local ODMWireService = require(script.Services.ODMWireService)
ODMWireService:init()

local GearService = require(script.Services.GearService)
GearService:init()