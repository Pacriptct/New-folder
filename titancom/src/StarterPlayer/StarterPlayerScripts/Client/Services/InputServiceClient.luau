--

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type InputState = "Began" | "Ended" | "Changed"

type InputAction = {
	Context: string,
	Priority: number,
	CanHold: boolean?,
	Exclusive: boolean?,
	AllowGameProcessed: boolean?,
}

type ProfileKeybinds = {
	[string]: string | { string },
}

type ActionCallback = (actionName: string, state: InputState, inputObject: InputObject) -> ()

local InputConfig = require(ReplicatedStorage.Shared.Input.InputConfig) :: {
	DefaultEnabledContexts: { [string]: boolean },
	Actions: { [string]: InputAction },
}

local InputServiceClient = {} :: any

------------------------------------------------------------
-- Internal State
------------------------------------------------------------

InputServiceClient._initialized = false
InputServiceClient._inputBlocked = false
InputServiceClient._keybindsApplied = false

InputServiceClient._actions = {} :: { [string]: InputAction }
InputServiceClient._callbacks = {} :: { [string]: { ActionCallback } }
InputServiceClient._keyToActions = {} :: { [Enum.KeyCode | Enum.UserInputType]: { string } }
InputServiceClient._enabledContexts = {} :: { [string]: boolean }
InputServiceClient._heldActions = {} :: { [string]: boolean }

------------------------------------------------------------
-- Utility
------------------------------------------------------------

local function countDictionary(dictionary: { [any]: any }): number
	local count = 0

	for _ in dictionary do
		count += 1
	end

	return count
end

local function enumFromName<T>(enumType: T, inputName: string): EnumItem?
	local success, result = pcall(function()
		return (enumType :: any):FromName(inputName)
	end)

	if success and typeof(result) == "EnumItem" then
		return result
	end

	return nil
end

local function resolveInputName(inputName: string): Enum.KeyCode | Enum.UserInputType?
	local keyCode = enumFromName(Enum.KeyCode, inputName)

	if keyCode and keyCode.EnumType == Enum.KeyCode then
		return keyCode :: Enum.KeyCode
	end

	local userInputType = enumFromName(Enum.UserInputType, inputName)

	if userInputType and userInputType.EnumType == Enum.UserInputType then
		return userInputType :: Enum.UserInputType
	end

	return nil
end

------------------------------------------------------------
-- Config Loading
------------------------------------------------------------

function InputServiceClient:_loadConfig()
	table.clear(self._enabledContexts)
	table.clear(self._actions)

	for contextName: string, enabled: boolean in InputConfig.DefaultEnabledContexts do
		self._enabledContexts[contextName] = enabled
	end

	for actionName: string, actionData: InputAction in InputConfig.Actions do
		self._actions[actionName] = actionData
	end
end

------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------

function InputServiceClient:init()
	if self._initialized then
		return
	end

	self._initialized = true

	table.clear(self._callbacks)
	table.clear(self._keyToActions)
	table.clear(self._heldActions)

	self:_loadConfig()

	UserInputService.InputBegan:Connect(function(inputObject, gameProcessed)
		self:_handleInput("Began", inputObject, gameProcessed)
	end)

	UserInputService.InputEnded:Connect(function(inputObject, gameProcessed)
		self:_handleInput("Ended", inputObject, gameProcessed)
	end)

	UserInputService.InputChanged:Connect(function(inputObject, gameProcessed)
		self:_handleInput("Changed", inputObject, gameProcessed)
	end)
end

function InputServiceClient:Init()
	self:init()
end

------------------------------------------------------------
-- Keybind Loading
------------------------------------------------------------

function InputServiceClient:RefreshKeybindsFromProfile(keybinds: ProfileKeybinds?)
	if not keybinds then
		return
	end

	if countDictionary(self._actions) <= 0 then
		self:_loadConfig()
	end

	if countDictionary(self._actions) <= 0 then
		warn("[InputServiceClient] Cannot apply keybinds because no actions were loaded from InputConfig.")
		return
	end

	self:ApplyKeybinds(keybinds)
	self._keybindsApplied = true
end

function InputServiceClient:ApplyKeybinds(keybinds: ProfileKeybinds)
	table.clear(self._keyToActions)
	table.clear(self._heldActions)

	for actionName: string, keyData: string | { string } in keybinds do
		local action = self._actions[actionName]

		if not action then
			warn(`[InputServiceClient] Profile has keybind for unknown action "{actionName}".`)
			continue
		end

		local keyNames = {} :: { string }

		if typeof(keyData) == "table" then
			for _, keyName: string in keyData do
				table.insert(keyNames, keyName)
			end
		else
			table.insert(keyNames, keyData)
		end

		for _, keyName in keyNames do
			local input = self:_stringToInput(keyName)

			if not input then
				warn(`[InputServiceClient] Invalid keybind "{keyName}" for action "{actionName}".`)
				continue
			end

			if not self._keyToActions[input] then
				self._keyToActions[input] = {}
			end

			table.insert(self._keyToActions[input], actionName)
		end
	end
end

------------------------------------------------------------
-- Action Binding
------------------------------------------------------------

function InputServiceClient:BindAction(actionName: string, callback: ActionCallback): () -> ()
	if not self._actions[actionName] then
		warn(`[InputServiceClient] Binding to unknown action "{actionName}".`)
	end

	if not self._callbacks[actionName] then
		self._callbacks[actionName] = {}
	end

	table.insert(self._callbacks[actionName], callback)

	local disconnected = false

	return function()
		if disconnected then
			return
		end

		disconnected = true

		local callbacks = self._callbacks[actionName]

		if not callbacks then
			return
		end

		for index = #callbacks, 1, -1 do
			if callbacks[index] == callback then
				table.remove(callbacks, index)
				break
			end
		end
	end
end

------------------------------------------------------------
-- Contexts
------------------------------------------------------------

function InputServiceClient:SetContextEnabled(contextName: string, enabled: boolean)
	self._enabledContexts[contextName] = enabled

	if not enabled then
		for actionName, action in self._actions do
			if action.Context == contextName then
				self._heldActions[actionName] = false
			end
		end
	end
end

function InputServiceClient:IsContextEnabled(contextName: string): boolean
	return self._enabledContexts[contextName] == true
end

function InputServiceClient:GetActiveContexts(): { [string]: boolean }
	return table.clone(self._enabledContexts)
end

------------------------------------------------------------
-- Blocking / Held State
------------------------------------------------------------

function InputServiceClient:SetInputBlocked(blocked: boolean)
	self._inputBlocked = blocked

	if blocked then
		table.clear(self._heldActions)
	end
end

function InputServiceClient:IsInputBlocked(): boolean
	return self._inputBlocked
end

function InputServiceClient:IsActionHeld(actionName: string): boolean
	return self._heldActions[actionName] == true
end

------------------------------------------------------------
-- Debug Helpers
------------------------------------------------------------

function InputServiceClient:GetKeybind(actionName: string): (Enum.KeyCode | Enum.UserInputType)?
	for input, actions in self._keyToActions do
		for _, name in actions do
			if name == actionName then
				return input
			end
		end
	end

	return nil
end

function InputServiceClient:GetBoundActionsForInput(inputName: string): { string }
	local input = self:_stringToInput(inputName)

	if not input then
		return {}
	end

	local actions = self._keyToActions[input]

	if not actions then
		return {}
	end

	return table.clone(actions)
end

------------------------------------------------------------
-- Input Handling
------------------------------------------------------------

function InputServiceClient:_handleInput(state: InputState, inputObject: InputObject, gameProcessed: boolean)
	if self._inputBlocked then
		return
	end

	local inputKey = self:_getInputKey(inputObject)

	if not inputKey then
		return
	end

	local possibleActions = self._keyToActions[inputKey]

	if not possibleActions then
		return
	end

	local resolvedActions = self:_resolveActions(possibleActions, gameProcessed)

	for _, actionName in resolvedActions do
		if state == "Began" then
			self._heldActions[actionName] = true
		elseif state == "Ended" then
			self._heldActions[actionName] = false
		end

		self:_fireAction(actionName, state, inputObject)
	end
end

function InputServiceClient:_resolveActions(actionNames: { string }, gameProcessed: boolean): { string }
	local valid = {} :: { string }

	for _, actionName in actionNames do
		local action = self._actions[actionName]

		if not action then
			continue
		end

		if self._enabledContexts[action.Context] ~= true then
			continue
		end

		if gameProcessed and action.AllowGameProcessed ~= true then
			continue
		end

		table.insert(valid, actionName)
	end

	table.sort(valid, function(a, b)
		local actionA = self._actions[a]
		local actionB = self._actions[b]

		local priorityA = actionA.Priority or 0
		local priorityB = actionB.Priority or 0

		return priorityA > priorityB
	end)

	local resolved = {} :: { string }

	for _, actionName in valid do
		local action = self._actions[actionName]

		table.insert(resolved, actionName)

		if action.Exclusive ~= false then
			break
		end
	end

	return resolved
end

function InputServiceClient:_fireAction(actionName: string, state: InputState, inputObject: InputObject)
	local callbacks = self._callbacks[actionName]

	if not callbacks then
		return
	end

	for _, callback in callbacks do
		task.spawn(callback, actionName, state, inputObject)
	end
end

------------------------------------------------------------
-- Input Conversion
------------------------------------------------------------

function InputServiceClient:_getInputKey(inputObject: InputObject): Enum.KeyCode | Enum.UserInputType?
	if inputObject.UserInputType == Enum.UserInputType.Keyboard then
		return inputObject.KeyCode
	end

	return inputObject.UserInputType
end

function InputServiceClient:_stringToInput(inputName: string): Enum.KeyCode | Enum.UserInputType?
	return resolveInputName(inputName)
end

return InputServiceClient