local States = {}

States.idle = {
	onEnter = function(titan)
		titan:StopMove()
	end,
	onUpdate = function(titan)
		titan:PlayAnimation("Idle")
		
		if titan.target then
			titan:SetState("chase")
		end
	end,
	onExit = function(titan)
		titan:StopAnimation("Idle")
	end,
}

States.chase = {
	onEnter = function(titan) end,
	onUpdate = function(titan)
		if titan:StateLocked() then
			return
		end
		
		if not titan.target then
			titan:SetState("idle")
			return
		end
		
		titan:PlayAnimation("Walk", false, 0, 1.2)
		
		local dist = (titan.target.Position - titan.rootPart.Position).Magnitude
		titan:Look(titan.target.Position)
		titan:Move(titan.target.Position, titan.stats.walkSpeed)
	end,
	onExit = function(titan)
		titan:StopAnimation("Walk")
	end,
}

States.dead = {
	onEnter = function(titan) end,
	onUpdate = function(titan)
		
	end,
	onExit = function(titan) end,
}

return States