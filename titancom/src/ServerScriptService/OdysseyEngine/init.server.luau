local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioGroups = require(ReplicatedStorage.Shared.Modules.AudioGroups)
AudioGroups.ensure()
AudioGroups.startAutoRoute()


game:GetService("Players").CharacterAutoLoads = true

local GearService = require(script.Services.GearService)
GearService:init()