--

local InputConfig = {
	DefaultEnabledContexts = {
		General = true,
		Movement = true,
		Combat = true,

		ODM = false,
		Weapon = false,
		UI = true,
		Menu = false,
		Admin = false,
	},

	Actions = {
		Interaction = { Context = "General", Priority = 0, CanHold = false, Exclusive = true },
		CallHorse = { Context = "General", Priority = 50, CanHold = false, Exclusive = true },
		HorseGallop = { Context = "General", Priority = 60, CanHold = true, Exclusive = false },
		HorseDismount = { Context = "General", Priority = 60, CanHold = false, Exclusive = false },
		HorseRear = { Context = "General", Priority = 60, CanHold = false, Exclusive = false },
		TitanShift = { Context = "General", Priority = 60, CanHold = false, Exclusive = false },

		Sprint = { Context = "Movement", Priority = 100, CanHold = true, Exclusive = true },
		CrouchSlide = { Context = "Movement", Priority = 100, CanHold = true, Exclusive = true },
		JumpVault = { Context = "Movement", Priority = 100, CanHold = false, Exclusive = true },
		ShiftLock = { Context = "Movement", Priority = 100, CanHold = false, Exclusive = true },

		Carry = { Context = "Combat", Priority = 300, CanHold = false, Exclusive = true },
		Execute = { Context = "Combat", Priority = 300, CanHold = false, Exclusive = true },
		ToggleFistCombat = { Context = "Combat", Priority = 300, CanHold = false, Exclusive = true },

		-- Weapon actions (reload / bayonet toggle). Self-gate in ToolServiceClient
		-- to the equipped weapon, so they are harmless when no weapon is held.
		Reload = { Context = "Combat", Priority = 300, CanHold = false, Exclusive = true },
		ToggleBayonet = { Context = "Combat", Priority = 300, CanHold = false, Exclusive = true },

		HookLeft = { Context = "ODM", Priority = 500, CanHold = true, Exclusive = true },
		HookRight = { Context = "ODM", Priority = 500, CanHold = true, Exclusive = true },
		OrbitLeft = { Context = "ODM", Priority = 500, CanHold = true, Exclusive = true },
		OrbitRight = { Context = "ODM", Priority = 500, CanHold = true, Exclusive = true },

		-- Non-exclusive so JumpVault (Movement context, priority 100)
		-- still fires on the same Space press when ODM is equipped.
		-- The GearBoost handler in GearServiceClient already no-ops
		-- when the player isn't hooking, so vault/jump on the ground
		-- with gear equipped routes correctly.
		GearBoost = { Context = "ODM", Priority = 500, CanHold = true, Exclusive = false },
		GearBlock = { Context = "ODM", Priority = 500, CanHold = true, Exclusive = true },

		ReloadBlades = { Context = "ODM", Priority = 500, CanHold = true, Exclusive = true },
		Attack = { Context = "General", Priority = 500, CanHold = true, Exclusive = true },

		GearHandles = { Context = "ODM", Priority = 500, CanHold = false, Exclusive = true },
		HeavyAttack = { Context = "ODM", Priority = 500, CanHold = false, Exclusive = true },
		SwitchODMMode = { Context = "ODM", Priority = 500, CanHold = false, Exclusive = true },
		CheckGas = { Context = "ODM", Priority = 500, CanHold = false, Exclusive = true },

		Hotbar1 = { Context = "General", Priority = 80, CanHold = false, Exclusive = true, AllowGameProcessed = false },
		Hotbar2 = { Context = "General", Priority = 80, CanHold = false, Exclusive = true, AllowGameProcessed = false },
		Hotbar3 = { Context = "General", Priority = 80, CanHold = false, Exclusive = true, AllowGameProcessed = false },
		Hotbar4 = { Context = "General", Priority = 80, CanHold = false, Exclusive = true, AllowGameProcessed = false },
		Hotbar5 = { Context = "General", Priority = 80, CanHold = false, Exclusive = true, AllowGameProcessed = false },
		Hotbar6 = { Context = "General", Priority = 80, CanHold = false, Exclusive = true, AllowGameProcessed = false },
	},
}

return InputConfig
