--

export type InputState = "Began" | "Ended" | "Changed"

export type InputContext = "General" | "Movement" | "ODM" | "Combat" | "Weapon" | "UI" | "Menu" | "Admin"

export type InputAction = {
	Context: InputContext,
	Priority: number,

	CanHold: boolean?,
	Exclusive: boolean?,

	-- If true, this action can still run even when Roblox marks the input as processed.
	-- Useful for menus, custom chat, admin panels, etc.
	AllowGameProcessed: boolean?,
}

export type ProfileKeybinds = {
	[string]: string | { string },
}

export type ActionCallback = (actionName: string, inputState: InputState, inputObject: InputObject) -> ()

return {}
