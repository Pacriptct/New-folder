local InputServiceClient = require(script.Services.InputServiceClient)
local CameraServiceClient = require(script.Services.CameraServiceClient)
local GearServiceClient = require(script.Services.GearServiceClient)
local RagdollClient = require(script.Services.RagdollClient)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TitanClient = require(ReplicatedStorage.Shared.Modules.TitanClient)

local DEFAULT_KEYBINDS = {
	-- ODM
	HookLeft        = "Q",
	HookRight       = "E",
	OrbitLeft       = "A",
	OrbitRight      = "D",
	GearBoost       = "Space",
	GearBlock       = "P",
	ReloadBlades    = "R",
	GearHandles     = "H",
	HeavyAttack     = "T",
	CheckGas        = "G",
	-- General / shared
	Attack          = "MouseButton1",
	Sprint          = "LeftShift",
	CrouchSlide     = "LeftControl",
	JumpVault       = "Space",
	ShiftLock       = "LeftAlt",
	Interaction     = "F",
}

InputServiceClient:init()
InputServiceClient:RefreshKeybindsFromProfile(DEFAULT_KEYBINDS)
InputServiceClient:SetContextEnabled("ODM", true)

CameraServiceClient:init()
GearServiceClient:init()
--RagdollClient --self init