local InputServiceClient = require(script.Services.InputServiceClient)
local CameraServiceClient = require(script.Services.CameraServiceClient)
local GearServiceClient = require(script.Services.GearServiceClient)
local RagdollClient = require(script.Services.RagdollClient)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TitanClient = require(ReplicatedStorage.Shared.Modules.TitanClient)

local DEFAULT_KEYBINDS = {
	-- Q / E hooks, A / D / W / S strafe, Space boost, LeftShift burst,
	-- V hooked burst and LeftControl brake are read directly by
	-- ODMMovementClient.
	GearHandles  = "F",
	ReloadBlades = "R",
	Attack       = "MouseButton1",
	HeavyAttack  = "T",
	CheckGas     = "G",
	GearBlock    = "P",
	ShiftLock    = "LeftAlt",
}

InputServiceClient:init()
InputServiceClient:RefreshKeybindsFromProfile(DEFAULT_KEYBINDS)
InputServiceClient:SetContextEnabled("ODM", true)

CameraServiceClient:init()
GearServiceClient:init()
--RagdollClient --self init