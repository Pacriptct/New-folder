local Players = game:GetService("Players")

local StateMachine = {}

local states = {}
local stunTimers = {}
local stateChangedCallbacks = {}

local blockingStates = {
	Sprint = {
		"Dead",
		"Stunned",
		"NoMove",
		"Rolling",
		"Attacking",
		"HeavyAttacking",
		"Blocking",
		"Vaulting",
		"Sliding",
		"ODMHooking",
		"ODMOrbiting",
		"ODMGroundSliding",
		"ODMVDashing",
		"ODMWallRunning",
		"Mounted",
	},

	Jump = {
		"Dead",
		"Stunned",
		"NoMove",
		"Rolling",
		"Attacking",
		"HeavyAttacking",
		"Blocking",
		"Vaulting",
		"Sliding",
		"ODMHooking",
		"ODMGroundSliding",
		"ODMVDashing",
		"ODMWallRunning",
		"Mounted",
	},

	Vault = {
		"Dead",
		"Stunned",
		"NoMove",
		"Rolling",
		"Attacking",
		"HeavyAttacking",
		"Blocking",
		"Vaulting",
		"Sliding",
		"ODMHooking",
		"ODMGroundSliding",
		"ODMVDashing",
		"ODMWallRunning",
		"Mounted",
	},

	ToggleODMHandles = {
		"Dead",
		"Stunned",
		"NoMove",
		"Rolling",
		"Attacking",
		"HeavyAttacking",
		"ODMHolstering",
		"ODMUnholstering",
		"Mounted",
	},

	ODMHook = {
		"Dead",
		"Stunned",
		"NoMove",
		"Rolling",
		"Attacking",
		"HeavyAttacking",
		"ODMHolstering",
		"ODMUnholstering",
		"Mounted",
	},

	ODMAttack = {
		"Dead",
		"Stunned",
		"NoMove",
		"Rolling",
		"ODMHolstering",
		"ODMUnholstering",
		"Mounted",
	},

	Attack = {
		"Dead",
		"Stunned",
		"NoMove",
		"Rolling",
		"Vaulting",
		"Mounted",
	},

	Block = {
		"Dead",
		"Stunned",
		"NoMove",
		"Rolling",
		"Attacking",
		"HeavyAttacking",
		"Vaulting",
		"Mounted",
	},

	Slide = {
		"Dead",
		"Stunned",
		"NoMove",
		"Rolling",
		"Attacking",
		"HeavyAttacking",
		"Blocking",
		"Vaulting",
		"Sliding",
		"ODMHooking",
		"ODMGroundSliding",
		"ODMVDashing",
		"ODMWallRunning",
		"Mounted",
	},

	Crouch = {
		"Dead",
		"Stunned",
		"NoMove",
		"Rolling",
		"Attacking",
		"HeavyAttacking",
		"Blocking",
		"Vaulting",
		"Sliding",
		"Mounted",
	},

	Prone = {
		"Dead",
		"Stunned",
		"NoMove",
		"Rolling",
		"Attacking",
		"HeavyAttacking",
		"Blocking",
		"Vaulting",
		"Sliding",
		"Mounted",
	},

	UseTool = {
		"Dead",
		"Stunned",
		"NoMove",
		"Mounted",
	},

}

function StateMachine.ReturnStates(plr)
	return states[plr]
end

function StateMachine.GetState(plr, stateKey)
	if states[plr] then
		return states[plr][stateKey]
	end

	return nil
end

function StateMachine.HasState(plr, stateKey)
	return StateMachine.GetState(plr, stateKey) ~= nil and StateMachine.GetState(plr, stateKey) ~= false
end

function StateMachine.HasAnyState(plr, stateKeys)
	if not states[plr] then
		return false
	end

	for _, stateKey in ipairs(stateKeys) do
		if states[plr][stateKey] ~= nil and states[plr][stateKey] ~= false then
			return true
		end
	end

	return false
end

function StateMachine.SetState(plr, stateKey, value, duration)
	if not plr then
		return
	end

	if not states[plr] then
		states[plr] = {}
	end

	local oldValue = states[plr][stateKey]
	states[plr][stateKey] = value

	if oldValue ~= value then
		StateMachine._fireStateChanged(plr, stateKey, value, oldValue)
	end

	if duration and type(duration) == "number" then
		task.delay(duration, function()
			if states[plr] and states[plr][stateKey] == value then
				states[plr][stateKey] = nil
				StateMachine._fireStateChanged(plr, stateKey, nil, value)

				if next(states[plr]) == nil then
					states[plr] = nil
				end
			end
		end)
	end
end

function StateMachine.SetStun(plr, value, duration, stunSpeed)
	if not plr or not plr.Character or not plr.Character:FindFirstChild("Humanoid") then
		return
	end

	local humanoid = plr.Character:FindFirstChild("Humanoid")

	if not states[plr] then
		states[plr] = {}
	end

	if value then
		states[plr].Stunned = true

		if not states[plr].OriginalWalkSpeed then
			states[plr].OriginalWalkSpeed = humanoid.WalkSpeed
		end

		humanoid.WalkSpeed = stunSpeed or 0

		StateMachine._fireStateChanged(plr, "Stunned", true, false)

		local endTime = tick() + duration

		if stunTimers[plr] then
			stunTimers[plr].EndTime = math.max(stunTimers[plr].EndTime, endTime)
		else
			stunTimers[plr] = { EndTime = endTime }

			task.spawn(function()
				while stunTimers[plr] and tick() < stunTimers[plr].EndTime do
					task.wait(0.1)
				end

				if states[plr] then
					states[plr].Stunned = nil

					if plr.Character and plr.Character:FindFirstChild("Humanoid") then
						local currentHumanoid = plr.Character:FindFirstChild("Humanoid")
						currentHumanoid.WalkSpeed = states[plr].OriginalWalkSpeed or 16
					end

					StateMachine._fireStateChanged(plr, "Stunned", nil, true)

					states[plr].OriginalWalkSpeed = nil

					if next(states[plr]) == nil then
						states[plr] = nil
					end
				end

				stunTimers[plr] = nil
			end)
		end
	else
		states[plr].Stunned = nil

		if plr.Character and plr.Character:FindFirstChild("Humanoid") then
			local currentHumanoid = plr.Character:FindFirstChild("Humanoid")
			currentHumanoid.WalkSpeed = states[plr].OriginalWalkSpeed or 16
		end

		StateMachine._fireStateChanged(plr, "Stunned", nil, true)
		states[plr].OriginalWalkSpeed = nil

		if next(states[plr]) == nil then
			states[plr] = nil
		end

		if stunTimers[plr] then
			stunTimers[plr] = nil
		end
	end
end

function StateMachine.RemoveStates(plr, stateKey)
	if not states[plr] then
		return
	end

	if stateKey then
		local oldValue = states[plr][stateKey]
		states[plr][stateKey] = nil

		if oldValue ~= nil then
			StateMachine._fireStateChanged(plr, stateKey, nil, oldValue)
		end

		if next(states[plr]) == nil then
			states[plr] = nil
		end
	else
		local oldStates = states[plr]
		states[plr] = nil

		if oldStates then
			for key, oldValue in pairs(oldStates) do
				StateMachine._fireStateChanged(plr, key, nil, oldValue)
			end
		end
	end
end

function StateMachine.ClearAllStates()
	for plr in pairs(states) do
		states[plr] = nil
	end

	for plr in pairs(stunTimers) do
		stunTimers[plr] = nil
	end
end

function StateMachine.CanPerformAction(plr, action)
	if not states[plr] then
		return true
	end

	local blockers = blockingStates[action]

	if not blockers then
		return true
	end

	for _, stateKey in ipairs(blockers) do
		if states[plr][stateKey] ~= nil and states[plr][stateKey] ~= false then
			return false
		end
	end

	return true
end

function StateMachine.OnStateChanged(plr, callback)
	if not stateChangedCallbacks[plr] then
		stateChangedCallbacks[plr] = {}
	end

	table.insert(stateChangedCallbacks[plr], callback)

	return function()
		local callbacks = stateChangedCallbacks[plr]

		if callbacks then
			for i, cb in ipairs(callbacks) do
				if cb == callback then
					table.remove(callbacks, i)
					break
				end
			end
		end
	end
end

function StateMachine._fireStateChanged(plr, stateKey, newValue, oldValue)
	if stateChangedCallbacks[plr] then
		for _, callback in ipairs(stateChangedCallbacks[plr]) do
			task.spawn(callback, stateKey, newValue, oldValue)
		end
	end
end

function StateMachine.DebugBlockers(plr, action)
	local blockers = blockingStates[action]
	if not blockers then
		print("[StateMachine] No blockers for", action)
		return
	end

	print("[StateMachine] Checking blockers for", action)

	if not states[plr] then
		print("[StateMachine] No active states")
		return
	end

	for _, stateKey in ipairs(blockers) do
		if states[plr][stateKey] ~= nil and states[plr][stateKey] ~= false then
			warn("[StateMachine] BLOCKED:", action, "by", stateKey, "=", states[plr][stateKey])
		end
	end
end

Players.PlayerRemoving:Connect(function(plr)
	states[plr] = nil
	stunTimers[plr] = nil
	stateChangedCallbacks[plr] = nil
end)

return StateMachine
