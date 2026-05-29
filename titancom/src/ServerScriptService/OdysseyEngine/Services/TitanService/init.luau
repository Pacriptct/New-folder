local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Registry = require(script.Registry)
local States = require(script.States)
local TitanStats = require(script.TitanStats)

local HitboxServer = require(script.HitboxServer)
local DamageHandler = require(script.Parent.DamageHandler)

local TITAN_MODEL = script.Model
local ANIMATIONS = ReplicatedStorage.Shared.Modules.TitanClient.Animations

local Remotes = ReplicatedStorage.Remotes.Titan

local titanFolder = Instance.new("Folder")
titanFolder.Name = "Titans"
titanFolder.Parent = workspace
local aliveFolder = Instance.new("Folder")
aliveFolder.Name = "Alive"
aliveFolder.Parent = titanFolder
local deadFolder = Instance.new("Folder")
deadFolder.Name = "Dead"
deadFolder.Parent = titanFolder

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = {workspace.Titans}

local core = {
	cachedPlayers = {},

	DECAY_TIME = 10,
	SKIN_COLOR = Color3.fromRGB(177, 134, 103),

	bv_MaxForce = Vector3.new(2000000, 0, 2000000),
	bg_MaxTorque = Vector3.new(20000, 20000, 20000),

	nameToken = 0,
}
core.__index = core

function core.new(position: Vector3, class: string)
	local self = setmetatable({}, core)
	self.stats = TitanStats[class or "Mindless"]

	local model = TITAN_MODEL:Clone()
	model:SetAttribute("IsTitan", true)
	model.Parent = workspace.Titans.Alive
	model.PrimaryPart:SetNetworkOwner(nil)
	model.PrimaryPart.CFrame = CFrame.new(position)
	self.model = model

	core.nameToken += 1
	self.model.Name = tostring(core.nameToken)

	self.hitboxes = self.model:FindFirstChild("Hitboxes")

	self.rootPart = self.model.PrimaryPart
	self.bv = self.rootPart.BodyVelocity
	self.bg = self.rootPart.BodyGyro
	self.bv.MaxForce = core.bv_MaxForce
	self.bg.MaxTorque = core.bg_MaxTorque

	self.target = nil
	self.state = "chase"

	self.loadedAnimations = {}
	for _, v in pairs(ANIMATIONS:GetChildren()) do
		self.loadedAnimations[v.Name] = self.model.AnimationController.Animator:LoadAnimation(v)
		if string.find(v.Name, "Grab") then
			self.loadedAnimations[v.Name].Priority = Enum.AnimationPriority.Action3
		else
			if v.Name == "Walk" then
				self.loadedAnimations[v.Name].Priority = Enum.AnimationPriority.Movement
			elseif string.find(v.Name, "Kick") then
				self.loadedAnimations[v.Name].Priority = Enum.AnimationPriority.Action2
			elseif string.find(v.Name, "Stomp") then
				self.loadedAnimations[v.Name].Priority = Enum.AnimationPriority.Action2
			elseif string.find(v.Name, "Eating") then
				self.loadedAnimations[v.Name].Priority = Enum.AnimationPriority.Action3
				self.loadedAnimations[v.Name].Looped = false
			elseif string.find(v.Name, "Swat") then
				self.loadedAnimations[v.Name].Priority = Enum.AnimationPriority.Action3
			else
				if string.find(v.Name, "BlindIdle") then
					self.loadedAnimations[v.Name].Priority = Enum.AnimationPriority.Action3
				elseif string.find(v.Name, "Blind") then
					self.loadedAnimations[v.Name].Priority = Enum.AnimationPriority.Action4
				else
					if string.find(v.Name, "Leg") then
						if string.find(v.Name, "Idle") then
							self.loadedAnimations[v.Name].Priority = Enum.AnimationPriority.Action
						elseif string.find(v.Name, "After") then
							self.loadedAnimations[v.Name].Priority = Enum.AnimationPriority.Action3
						else
							self.loadedAnimations[v.Name].Priority = Enum.AnimationPriority.Action2
						end
					else
						self.loadedAnimations[v.Name].Priority = Enum.AnimationPriority.Action2
					end
				end
			end
		end
	end
	self.loadedAnimations["Walk"] = self.model.AnimationController.Animator:LoadAnimation(
		ANIMATIONS.Parent.Presets.Walk:GetChildren()[math.random(1, #ANIMATIONS.Parent.Presets.Walk:GetChildren())]
	)
	self.loadedAnimations["Idle"] = self.model.AnimationController.Animator:LoadAnimation(
		ANIMATIONS.Parent.Presets.Idle:GetChildren()[math.random(1, #ANIMATIONS.Parent.Presets.Idle:GetChildren())]
	)
	self.loadedAnimations["Idle"].Priority = Enum.AnimationPriority.Action

	self.overlays = {}

	self.grabSwinging = { Left = false, Right = false }
	self.lastGrabSwing = -math.huge
	self.lastNapeGrabSwing = -math.huge
	self.grabbed = { Left = nil, Right = nil }

	self.lastFeet = -math.huge
	
	self.blinded = false
	self.blindedEyes = { Left = false, Right = false }
	self.blindTokens = { Left = nil, Right = nil }
	self.lastBlindStopped = -math.huge
	self.disabledLimbs = {}
	
	self.limbHealth = {
		LeftArm = self.stats.limbHealth or 100,
		RightArm = self.stats.limbHealth or 100,
		LeftLeg = self.stats.limbHealth or 100,
		RightLeg = self.stats.limbHealth or 100,
	}
	
	self.events = {}
	
	--local hairColours = {
	--	Color3.fromRGB(255, 255, 255),
	--	Color3.fromRGB(144, 92, 19),
	--	Color3.fromRGB(65, 42, 30),
	--	Color3.fromRGB(177, 134, 103),
	--	Color3.fromRGB(255, 207, 138),
	--	Color3.fromRGB(217, 84, 84),
	--}

	--local randomHair = script.Hair:GetChildren()[math.random(1, #script.Hair:GetChildren())]:Clone()
	--randomHair.Parent = self.model
	--randomHair.Handle.Anchored = true
	--randomHair.Handle.CanCollide = false
	--randomHair.Handle.CanQuery = false
	--randomHair.Handle.CanTouch = false
	--randomHair.Handle.Color = hairColours[math.random(1, #hairColours)]

	self.scaleFactor = 1
	self.model:ScaleTo(self.scaleFactor * math.random(8, 15))
	self.model.Head:SetAttribute("Offset", self.model.Head.Neck.C0.Y)

	for i, v in pairs(self.loadedAnimations) do
		if string.find(i, "Grab") then
			v.Ended:Connect(function()
				local animSide = string.find(i, "Left") and "Left" or "Right"
				self.grabSwinging[animSide] = false
			end)
		elseif string.find(i, "Walk") then
			table.insert(self.events, v:GetMarkerReachedSignal("Footstep"):Connect(function()
				if self.dead then return end
				self:QueueFoostep()
			end))
		elseif string.find(i, "Eating") then
			table.insert(self.events, v:GetMarkerReachedSignal("Bite"):Connect(function()
				if self.dead then return end
				local side = string.gsub(i, "Eating", "")
				local character = self.grabbed[side]
				self:StopGrab(side)
				if character and character.Parent ~= nil then
					local rootPart = character:FindFirstChild("HumanoidRootPart")
					local player = Players:GetPlayerFromCharacter(character)
					if player and rootPart then
						DamageHandler:Knockback(player, 140, Vector3.new(0, 1, 0), 2)
						local humanoid = character:FindFirstChild("Humanoid")
						if humanoid then
							DamageHandler:Kill(character)
						end
					end
				end
			end))
		elseif string.find(i, "Swat") then
			table.insert(self.events, v:GetMarkerReachedSignal("Grab"):Connect(function()
				if self.dead then return end
				local side = i == "LeftSwat" and "Left" or "Right"
				HitboxServer.Create(
					self.model.SwatBox[side].CFrame,
					self.model.SwatBox[side].Size * 1.2,
					params,
					function(model)
						local player = Players:GetPlayerFromCharacter(model)
						if player then
							local hrp = model:FindFirstChild("HumanoidRootPart")
							if hrp then
								self.model.SwatBox[side]["Hit"..tostring(math.random(1, 2))]:Play()
								local direction = (hrp.Position - self.rootPart.Position + Vector3.new(0, 0.4, 0)).Unit
								DamageHandler:Knockback(player, 1500, direction, 2)
								DamageHandler:Damage(model, 20)
							end
						end
					end
				)
			end))
		elseif string.find(i, "Kick") then
			table.insert(self.events, v:GetMarkerReachedSignal("Hit"):Connect(function()
				if self.dead then return end
				local side = i == "LeftKick" and "Left" or "Right"
				HitboxServer.Create(
					self.model.KickBox[side].CFrame * CFrame.new(0, -4 * self.scaleFactor, 7 * self.scaleFactor),
					self.model.KickBox[side].Size * Vector3.new(2, 2, 1.5) * self.scaleFactor,
					params,
					function(model)
						local player = Players:GetPlayerFromCharacter(model)
						if player and not player:GetAttribute("Grabbed") then
							local toPlayer = CFrame.lookAt(self.model.KickBox[side].CFrame.Position, model.HumanoidRootPart.Position).LookVector
							local titanForward = self.rootPart.CFrame.LookVector
							local direction = (toPlayer + Vector3.new(0, 2, 0) + titanForward * 0.3).Unit
							DamageHandler:Knockback(player, 1700, direction, 3)
							self.model.KickBox[side]["Hit"..tostring(math.random(1, 2))]:Play()
							local humanoid = model:FindFirstChild("Humanoid")
							if humanoid then
								DamageHandler:Damage(model, 40)
							end
						end
					end
				)
			end))
		elseif string.find(i, "Stomp") then
			table.insert(self.events, v:GetMarkerReachedSignal("Hit"):Connect(function()
				if self.dead then return end
				local side = i == "LeftStomp" and "Left" or "Right"
				self.model.StompBox[side]["Impact"..tostring(math.random(1, 2))]:Play()
				
				HitboxServer.Create(
					CFrame.new(self.model[side.."Foot"].Position),
					self.model.StompBox[side].Size * 1.3,
					params,
					function(model)
						local player = Players:GetPlayerFromCharacter(model)
						if player and not player:GetAttribute("Grabbed") then
							local direction = CFrame.lookAt(self.model.StompBox[side].CFrame.Position, model.HumanoidRootPart.Position).LookVector
							DamageHandler:Knockback(player, 900, direction, 2.6)
							self.model.StompBox[side]["Hit"..tostring(math.random(1, 2))]:Play()
							local humanoid = model:FindFirstChild("Humanoid")
							if humanoid then
								DamageHandler:Damage(model, 40)
							end
						end
					end
				)
			end))
		end
	end

	self.lastPlayingFootstep = nil

	self:SetupGrabs()
	self:SetupFeet()

	self:SetState("idle")
	Registry:Add(self)
	self:Start()

	return self
end

function core:Look(position)
	self.bg.MaxTorque = core.bg_MaxTorque
	self.bg.D = 600
	self.bg.P = 2300

	self.bg.CFrame =
		CFrame.lookAt(
			self.rootPart.Position,
			Vector3.new(position.X, self.rootPart.Position.Y, position.Z)
		)
end
function core:StopLook()
	self.bg.CFrame =
		CFrame.lookAt(
			self.rootPart.Position,
			self.rootPart.Position + self.rootPart.CFrame.LookVector
		)
end
function core:StopMove()
	self.bv.Velocity = Vector3.zero
end
function core:Move(position, newSpeed)
	self.bv.Velocity =
		CFrame.lookAt(
			self.rootPart.Position,
			Vector3.new(position.X, self.rootPart.Position.Y, position.Z)
		).LookVector * newSpeed
end

function core:GrabSwing(name)
	if self.dead then return end

	local side = string.find(name, "Left") and "Left" or "Right"

	if self.grabSwinging[side] then return end
	if self.disabledLimbs[side .. "Arm"] then return end
	if self.blindedEyes[side] then return end
	if self.disabledLimbs["LeftLeg"] and self.disabledLimbs["RightLeg"] then return end
	if self.loadedAnimations["LeftSwat"] and self.loadedAnimations["LeftSwat"].IsPlaying then return end
	if self.loadedAnimations["RightSwat"] and self.loadedAnimations["RightSwat"].IsPlaying then return end

	local isNape = string.find(name, "Nape") ~= nil
	if isNape then
		if os.clock() - self.lastNapeGrabSwing <= self.stats.napeGrabSwingCooldown then return end
		self.lastNapeGrabSwing = os.clock()
	else
		if os.clock() - self.lastGrabSwing <= self.stats.grabSwingCooldown then return end
		self.lastGrabSwing = os.clock()
	end

	if not isNape and math.random() < (self.stats.swatChance or 0) then
		self:Swat(side)
		return
	end

	self.grabSwinging[side] = true
	local timePassed = math.clamp(os.clock() - self.lastBlindStopped, 0, 1)
	local delta = 1 - timePassed

	self:PlayAnimation(name, true, delta)
end

function core:PlayRandomScream()
	self.rootPart.Screams:GetChildren()[math.random(1, #self.rootPart.Screams:GetChildren())]:Play()
end

function core:Swat(side)
	if self.dead then return end
	if self.grabbed["Left"] or self.grabbed["Right"] then return end
	if self.blinded then return end
	if self.disabledLimbs[side.."Arm"] then return end
	if self.disabledLimbs["LeftLeg"] and self.disabledLimbs["RightLeg"] then return end

	local track = self.loadedAnimations[side.."Swat"]
	if not track then return end

	track.Priority = Enum.AnimationPriority.Action4
	track:Play(0.1)
end

function core:Grab(character, side)
	if self.blindedEyes[side] then return end
	if self.disabledLimbs[side .. "Arm"] then return end

	-- check if this side already has someone
	if self.grabbed[side] then
		if self.grabbed[side].Parent == nil then
			self.grabbed[side] = nil
		else
			return
		end
	end

	if self.blinded then return end

	if side ~= "Left" and side ~= "Right" then
		warn("Side is incorrect format : "..tostring(side))
	end

	if not character or character.Parent == nil then return end
	if character.Parent ~= workspace.Characters then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	self.model[side.."Hand"]["Hand"..tostring(math.random(1, 5))]:Play()

	humanoid.EvaluateStateMachine = false
	player:SetAttribute("Grabbed", true)
	Remotes.GrabState:FireClient(player, true)
	self.grabbed[side] = character

	local GrabMotors = self.model.GrabMotors
	GrabMotors[side].Part0 = rootPart

	local function startEating()
		if self.dead or self.grabbed[side] ~= character then return end
		if self.disabledLimbs[side.."Arm"] then
			self:StopGrab(side)
			return
		end
		self:StopGrabAnimations(side)

		-- queue eating: wait until no eating anim is playing
		task.spawn(function()
			while self.grabbed[side] == character and not self.dead do
				local otherSide = side == "Left" and "Right" or "Left"
				local otherEatingAnim = "Eating" .. otherSide
				if not self.loadedAnimations[otherEatingAnim] or not self.loadedAnimations[otherEatingAnim].IsPlaying then
					break
				end
				task.wait(0.1)
			end
			if self.dead or self.grabbed[side] ~= character then return end

			self:AddOverlay("grabbed_" .. side, {
				onEnter = function(titan) end,
				onUpdate = function(titan)
					titan:StopLook()
					if not titan.blinded then
						titan:PlayAnimation("Eating"..side, false, 0.5)
					end
					titan.model:SetAttribute("Grabbed", true)
					titan:PlayAnimation("Idle")
					titan:StopGrabAnimations(side)
					titan:StopAnimation("Walk", 0.3)
					titan:StopMove()
				end,
				onExit = function(titan)
					local otherSide = side == "Left" and "Right" or "Left"
					if not titan.grabbed[otherSide] then
						titan.model:SetAttribute("Grabbed", false)
					end
					titan:StopAnimation("Eating"..side)
					titan:StopAnimation("Idle")
				end,
			})
		end)
	end

	local playingGrabAnim = nil
	for animName, track in pairs(self.loadedAnimations) do
		if track.IsPlaying and string.find(animName, "Grab") and string.find(animName, side) then
			playingGrabAnim = track
			break
		end
	end

	if playingGrabAnim then
		local conn
		conn = playingGrabAnim.Stopped:Connect(function()
			conn:Disconnect()
			startEating()
		end)
	else
		startEating()
	end
end

function core:StopGrab(side)
	if not side then
		-- stop both
		self:StopGrab("Left")
		self:StopGrab("Right")
		return
	end

	if not self.grabbed[side] then return end

	local GrabMotors = self.model.GrabMotors
	GrabMotors[side].Part0 = nil

	if self.grabbed[side].Parent ~= nil then
		local humanoid = self.grabbed[side]:FindFirstChild("Humanoid")
		local player = Players:GetPlayerFromCharacter(self.grabbed[side])
		if humanoid then
			humanoid.EvaluateStateMachine = true
		end
		if player then
			player:SetAttribute("Grabbed", false)
			Remotes.GrabState:FireClient(player, false)
		end
	end

	self.grabbed[side] = nil
	self:RemoveOverlay("grabbed_" .. side)
end

function core:StopGrabAnimations(side)
	for i, v in pairs(self.model.GrabBox:GetChildren()) do
		if side then
			if string.find(v.Name, side) then
				self:StopAnimation(v.Name)
			end
		else
			self:StopAnimation(v.Name)
		end
	end
end

function core:SetupGrabs()
	for _, v in pairs(self.model.GrabBox:GetChildren()) do
		v.Transparency = 1
		table.insert(self.events, v.Touched:Connect(function(hit)
			if not hit.Parent then return end
			if hit.Parent.Parent ~= workspace.Characters then return end
			if hit.Parent:FindFirstChild("Humanoid") and hit.Parent.Humanoid.Health <= 0 then return end
			self:GrabSwing(v.Name)
		end))
	end
	for _, v in pairs(self.model.SwatBox:GetChildren()) do
		v.Transparency = 1
	end
	for _, v in pairs(self.model.TouchBox:GetChildren()) do
		v.Transparency = 1
	end
end

function core:CanUseFeet()
	if self.blinded then return false end
	if os.clock() - self.lastFeet <= self.stats.feetCooldown then return false end
	if self.loadedAnimations.LeftKick.IsPlaying then return false end
	if self.loadedAnimations.RightKick.IsPlaying then return false end
	if self.loadedAnimations.LeftStomp.IsPlaying then return false end
	if self.loadedAnimations.RightStomp.IsPlaying then return false end
	if self.disabledLimbs["LeftLeg"] or self.disabledLimbs["RightLeg"] then return false end
	return true
end

function core:StopAllFeet()
	self:StopAnimation("LeftKick")
	self:StopAnimation("RightKick")
	self:StopAnimation("LeftStomp")
	self:StopAnimation("RightStomp")
end

function core:Kick(side)
	if not self:CanUseFeet() then return end
	if self.model:GetAttribute("Dead") == true then return end
	if self.loadedAnimations["LeftSwat"].IsPlaying or self.loadedAnimations["RightSwat"].IsPlaying then return end
	self:PlayAnimation(side.."Kick")
	self.lastFeet = os.clock()
end

function core:Stomp(side)
	if not self:CanUseFeet() then return end
	if self.model:GetAttribute("Dead") == true then return end
	if self.loadedAnimations["LeftSwat"].IsPlaying or self.loadedAnimations["RightSwat"].IsPlaying then return end
	self:PlayAnimation(side.."Stomp")
	self.lastFeet = os.clock()
end

function core:SetupFeet()
	for _, v in pairs(self.model.KickBox:GetChildren()) do
		v.Transparency = 1
		table.insert(self.events, v.Touched:Connect(function(hit)
			if not hit.Parent then return end
			if hit.Parent.Parent ~= workspace.Characters then return end
			if hit.Parent:FindFirstChild("Humanoid") and hit.Parent.Humanoid.Health <= 0 then return end
			self:Kick(v.Name)
		end))
	end
	for _, v in pairs(self.model.StompBox:GetChildren()) do
		v.Transparency = 1
		table.insert(self.events, v.Touched:Connect(function(hit)
			if not hit.Parent then return end
			if hit.Parent.Parent ~= workspace.Characters then return end
			if hit.Parent:FindFirstChild("Humanoid") and hit.Parent.Humanoid.Health <= 0 then return end
			self:Stomp(v.Name)
		end))
	end
end

function core:QueueFoostep()
	self.lastPlayingFootstep = self.rootPart:FindFirstChild("Footstep")
	self.lastPlayingFootstep:Play()
end

function core:DamageNape(damage, damagerCharacter)
	if (self.grabbed["Left"] and self.grabbed["Left"] == damagerCharacter)
		or (self.grabbed["Right"] and self.grabbed["Right"] == damagerCharacter) then return end
	if self.dead then return end
	
	--self:PlayRandomScream()
	
	self:Kill(damage)
end

function core:PlaySound(name: string, override: boolean?)
	local sound = self.rootPart:FindFirstChild(name, true)
	if not sound or not sound:IsA("Sound") then
		warn("[Titan] Sound not found:", name)
		return
	end
	if sound.IsPlaying and not override then return end
	sound:Stop()
	sound:Play()
end

function core:StopSound(name: string)
	local sound = self.rootPart:FindFirstChild(name, true)
	if not sound or not sound:IsA("Sound") then return end
	sound:Stop()
end

function core:DamageLimb(side, limbType, damage, damagerCharacter)
	if (self.grabbed["Left"] and self.grabbed["Left"] == damagerCharacter)
		or (self.grabbed["Right"] and self.grabbed["Right"] == damagerCharacter) then return end
	if self.dead then return end
	if self.disabledLimbs[side .. limbType] then return end

	local key = side .. limbType
	local hitboxes = self.model:FindFirstChild("Hitboxes")
	if hitboxes then
		local hb = hitboxes:FindFirstChild(key)
		if hb then
			core:PlayRandomHitboxSlash(hb)
			local slashBlood = hb:FindFirstChild("SlashBlood")
			if slashBlood then
				for _, v in pairs(slashBlood:GetChildren()) do
					if v:IsA("ParticleEmitter") then v:Emit(15) end
				end
			end
		end
	end

	--self:PlayRandomScream()

	self.limbHealth[key] -= damage
	if self.limbHealth[key] > 0 then return end  -- not severed yet

	self.disabledLimbs[key] = true
	self:_SeverLimb(side, limbType)
end

function core:DamageEyes(side, damagerCharacter)
	if (self.grabbed["Left"] and self.grabbed["Left"] == damagerCharacter)
		or (self.grabbed["Right"] and self.grabbed["Right"] == damagerCharacter) then return end
	if self.dead then return end
	if self.blindedEyes[side] then return end

	self.blindedEyes[side] = true
	
	if self.grabbed[side] then
		self:StopGrab(side)
	end

	local eyes = self.model:FindFirstChild("Hitboxes") and self.model.Hitboxes:FindFirstChild(side .. "Eye")
	if eyes then
		core:PlayRandomHitboxSlash(eyes)
		local slashBlood = eyes:FindFirstChild("SlashBlood")
		if slashBlood then
			for _, v in pairs(slashBlood:GetChildren()) do
				if v:IsA("ParticleEmitter") then v:Emit(8) end
			end
		end
	end

	local bothBlinded = self.blindedEyes["Left"] and self.blindedEyes["Right"]
	self.blinded = bothBlinded

	local overlayKey = side .. "EyeBlind"
	local blindToken = {}
	self.blindTokens[side] = blindToken
	local blindedSpeed = math.random(8, 12) / 10

	self:AddOverlay(overlayKey, {
		onEnter = function(titan)
			if bothBlinded then
				titan:PlaySound("Blinded", true)
				titan:StopGrabAnimations("Left")
				titan:StopGrabAnimations("Right")
				titan:StopAnimation("LeftEyeBlind")
				titan:StopAnimation("RightEyeBlind")
				titan:StopAnimation("LeftBlindIdle")
				titan:StopAnimation("RightBlindIdle")
				titan.model:SetAttribute("Blinded", true)

				local swatToken = {}
				titan._blindSwatToken = swatToken

				task.delay(1, function()
					task.spawn(function()
						for i = 1, 10 do
							if titan._blindSwatToken ~= swatToken or not titan.blinded or titan.dead then return end
							local sides = {"Left", "Right"}
							local side = sides[math.random(1, 2)]
							HitboxServer.Create(
								titan.model.SwatBox[side].CFrame,
								titan.model.SwatBox[side].Size * 1.8,
								params,
								function(model)
									local player = Players:GetPlayerFromCharacter(model)
									if player then
										self.model.SwatBox[side]["Hit"..tostring(math.random(1, 2))]:Play()
										local hrp = model:FindFirstChild("HumanoidRootPart")
										if hrp then
											local direction = (hrp.Position - titan.rootPart.Position + Vector3.new(0, 0.4, 0)).Unit
											DamageHandler:Knockback(player, 1200, direction, 2)
											DamageHandler:Damage(model, 15)
										end
									end
								end
							)
							task.wait(.1)
						end
					end)
				end)
			else
				titan:StopGrabAnimations(side)
				titan:PlayAnimation(side .. "EyeBlind", true, 0)
			end
		end,
		onUpdate = function(titan)
			local isDoubleBlind = titan.blindedEyes["Left"] and titan.blindedEyes["Right"]

			if isDoubleBlind then
				if overlayKey ~= "LeftEyeBlind" then return end

				titan:StopGrabAnimations("Left")
				titan:StopGrabAnimations("Right")

				if not titan.loadedAnimations["DoubleBlind"].IsPlaying and not titan.loadedAnimations["DoubleBlindIdle"].IsPlaying then
					titan:PlayAnimation("DoubleBlind", false, 0, blindedSpeed)
					titan.loadedAnimations["DoubleBlind"].Stopped:Once(function()
						if titan.blindedEyes["Left"] and titan.blindedEyes["Right"] then
							titan:PlayAnimation("DoubleBlindIdle", true, 0.2)
						end
					end)
				end

				titan.target = nil
			else
				titan:StopGrabAnimations(side)
				if not titan.loadedAnimations[side .. "EyeBlind"].IsPlaying
					and not titan.loadedAnimations[side .. "BlindIdle"].IsPlaying then
					titan:PlayAnimation(side .. "BlindIdle", true, 0.2)
				end
			end
		end,
		onExit = function(titan)
			titan.blindedEyes[side] = false
			titan.blinded = titan.blindedEyes["Left"] and titan.blindedEyes["Right"]
			titan:StopAnimation(side .. "EyeBlind")
			titan:StopAnimation(side .. "BlindIdle")
			titan:StopAnimation("DoubleBlind")
			titan:StopAnimation("DoubleBlindIdle")
			if not titan.blinded then
				titan.model:SetAttribute("Blinded", false)
				titan.lastBlindStopped = os.clock()
				titan:SetState("chase")
			end
		end,
		canMove = true,
	})

	local duration = 7.4 / blindedSpeed
	task.delay(duration, function()
		if self.blindTokens[side] ~= blindToken then return end
		self:RemoveOverlay(overlayKey)
	end)
end

function core:_SeverLimb(side, limbType)
	local hitboxKey = side .. limbType
	local hitboxes = self.model:FindFirstChild("Hitboxes")
	if hitboxes then
		local hb = hitboxes:FindFirstChild(hitboxKey)
		if hb then
			local slashBlood = hb:FindFirstChild("SlashBlood")
			if slashBlood then
				for _, v in pairs(slashBlood:GetChildren()) do
					if v:IsA("ParticleEmitter") then v:Emit(15) end
				end
			end
			core:PlayRandomHitboxSlash(hb)
		end
	end

	self:AddOverlay(hitboxKey, {
		onEnter = function(titan)
			if limbType == "Arm" then
				local lowerArmName = side == "Left" and "LeftLowerArm" or "RightLowerArm"
				local handName = side == "Left" and "LeftHand" or "RightHand"

				local lowerArmPart = titan.model:FindFirstChild(lowerArmName)
				local handPart = titan.model:FindFirstChild(handName)

				local clones = {}

				for _, part in pairs({lowerArmPart, handPart}) do
					if part then
						local clone = part:Clone()
						clone.CollisionGroup = "DeadTitanLimb"
						clone.CanCollide = true
						clone.Anchored = false
						clone.CFrame = part.CFrame
						clone.CustomPhysicalProperties = PhysicalProperties.new(1, 0.5, 0, 0, 0)
						clone.Parent = workspace.Titans.Dead

						for _, joint in clone:GetDescendants() do
							if joint:IsA("Motor6D") or joint:IsA("Weld") or joint:IsA("WeldConstraint") then
								joint:Destroy()
							end
						end

						part.Transparency = 1
						part.CanCollide = false

						table.insert(clones, clone)

						task.delay(8, function()
							if clone and clone.Parent then
								clone:Destroy()
							end
						end)
					end
				end

				-- weld the hand clone to the lower arm clone
				if clones[1] and clones[2] then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = clones[1]
					weld.Part1 = clones[2]
					weld.Parent = clones[1]
				end

				-- apply velocity after welding so they move together
				if clones[1] then
					clones[1].AssemblyLinearVelocity = Vector3.new(
						math.random(-5, 5),
						math.random(3, 8),
						math.random(-5, 5)
					)
				end

				if self.grabbed[side] then
					self:StopGrab(side)
				end
				self:StopGrabAnimations(side)
			end
		end,
		onUpdate = function(titan)
			if limbType == "Arm" then
				self:StopGrabAnimations(side)
				if self.grabbed[side] then
					self:StopGrab(side)
				end
				self:PlayAnimation(hitboxKey.."Disabled")
			elseif limbType == "Leg" then
				self:StopAllFeet()
				self:StopMove()
				self:StopLook()
				self:StopAnimation("Walk")
				self:PlayAnimation(side.."LegInjury", false, 0.5)
			end
		end,
		onExit = function(titan)
			self.limbHealth[hitboxKey] = self.stats.limbHealth or 100
			if limbType == "Arm" then
				self:StopAnimation(hitboxKey.."Disabled")
				self.disabledLimbs[hitboxKey] = nil

				local lowerArmName = side == "Left" and "LeftLowerArm" or "RightLowerArm"
				local handName = side == "Left" and "LeftHand" or "RightHand"

				for _, name in pairs({lowerArmName, handName}) do
					local part = titan.model:FindFirstChild(name)
					if part then
						part.Transparency = 0
						part.CanCollide = true
					end
				end
			elseif limbType == "Leg" then
				self:StopAnimation(side.."LegInjury", 0.1)
				self.disabledLimbs[hitboxKey] = nil
				if not self.dead then
					self:SetState("chase")
				end
			end
		end,
		canMove = limbType ~= "Leg",
	})
	
	task.delay(self.stats.legRegenTime, function()
		if self.dead then return end
		self:RemoveOverlay(hitboxKey)
	end)
end

function core:Start()
	local state = States[self.state]
	if state and state.onEnter then
		state.onEnter(self)
	end

	task.spawn(function()
		while not self.dead do
			self:FindTarget()
			self:UpdateState()
			if self.rootPart.Position.Y < -100 then
				self:Destroy()
			end

			local DEFAULT_LOOK_POSITION = self.model.Head.Position + self.model.UpperTorso.CFrame.LookVector
			local TARGET_LOOK_POSITION = self.target and self.target.Position or Vector3.zero
			if self.target and not self.blinded then
				self.model.LookPosition.Value = TARGET_LOOK_POSITION
			else
				self.model.LookPosition.Value = DEFAULT_LOOK_POSITION
			end

			for key, hp in pairs(self.limbHealth) do
				if not self.disabledLimbs[key] then  -- only regen if not severed
					self.limbHealth[key] = math.min(
						hp + (self.stats.limbRegen / 5),
						self.stats.limbHealth
					)
				end
			end

			self.model.PrimaryPart:SetNetworkOwner(nil)

			task.wait(0.2)
		end
	end)
end

function core:StateLocked()
	if
		self.loadedAnimations["LeftKick"].IsPlaying
		or self.loadedAnimations["RightKick"].IsPlaying
		or self.loadedAnimations["LeftStomp"].IsPlaying
		or self.loadedAnimations["RightStomp"].IsPlaying
	then
		self:StopMove()
		self:StopLook()
		return true
	end

	if self.blinded then
		return true
	end

	local count = 0
	for i, v in pairs(self.overlays) do
		if not v.canMove then
			count += 1
		end
	end
	return count > 0
end

function core:AddOverlay(name, overlay)
	if self.dead then return end
	if self.overlays[name] then return end
	self.overlays[name] = overlay
	if self.overlays[name].onEnter then
		self.overlays[name].onEnter(self)
	end
end

function core:RemoveOverlay(name)
	if self.dead then return end
	if not self.overlays[name] then return end
	if self.overlays[name].onExit then
		self.overlays[name].onExit(self)
	end
	self.overlays[name] = nil
end

function core:SetState(stateName)
	if self.state == stateName then return end
	if self:StateLocked() and stateName ~= "dead" then return end

	local new = States[stateName]
	local current = States[self.state]

	if current and current.onExit then
		current.onExit(self)
	end

	self.state = stateName

	if new and new.onEnter then
		new.onEnter(self)
	end
end

function core:UpdateState()
	local current = States[self.state]
	if current and current.onUpdate then
		current.onUpdate(self)
	end
	for name, overlay in pairs(self.overlays) do
		if overlay.onUpdate then
			overlay.onUpdate(self)
		end
	end
end

function core:FindTarget()
	local nearest, nearestDist = nil, math.huge
	for _, player in pairs(core.cachedPlayers) do
		local character = player.Character
		if character and not player:GetAttribute("Grabbed") then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChild("Humanoid")
			if hrp and humanoid and humanoid.Health > 0 then
				local dist = (hrp.Position - self.rootPart.Position).Magnitude
				if dist < nearestDist then
					nearest = hrp
					nearestDist = dist
				end
			end
		end
	end
	self.target = nearest
end

function core:PlayAnimation(track, override, fade, speed)
	local track: AnimationTrack = self.loadedAnimations[track]
	if not track then return end
	if not track.IsPlaying or override then
		track:Play(fade, nil, speed)
		return track
	end
end

function core:StopAnimation(track, fade)
	local track: AnimationTrack = self.loadedAnimations[track]
	if not track then return end
	track:Stop(fade)
end

function core:PlayRandomHitboxSlash(hitbox)
	hitbox:FindFirstChild("Hit"):Play()
end

function core:Ragdoll()
	for _, joint in pairs(self.model:GetDescendants()) do
		if joint:IsA("Motor6D") and joint.Parent.Name ~= "LowerTorso" then
			local socket = Instance.new("BallSocketConstraint")
			local a1 = Instance.new("Attachment")
			local a2 = Instance.new("Attachment")
			a1.Parent = joint.Part0
			a2.Parent = joint.Part1
			socket.Parent = joint.Parent
			socket.Name = "RagdollSocket"
			socket.Attachment0 = a1
			socket.Attachment1 = a2
			a1.CFrame = joint.C0
			a2.CFrame = joint.C1
			a1.Name = "RagdollA1"
			a2.Name = "RagdollA2"
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			joint.Enabled = false
		end
	end
end

function core:UnRagdoll()
	for _, joint in pairs(self.model:GetDescendants()) do
		if joint:IsA("Motor6D") then
			joint.Enabled = true
		end
	end
	for _, v in pairs(self.model:GetDescendants()) do
		if v.Name == "RagdollSocket" or v.Name == "RagdollA1" or v.Name == "RagdollA2" then
			v:Destroy()
		end
	end
end

function core:Kill(damage)
	if self.dead then return end
	self.dead = true
	self._blindSwatToken = nil
	local napeHitbox = self.model.Hitboxes.Nape
	self.model:SetAttribute("Dead", true)

	if damage >= 200 then
		napeHitbox.Perfect:Play()
	else
		napeHitbox.NotPerfect:Play()
	end
	for _, v in pairs(napeHitbox.Slash:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			v:Emit(20)
		end
	end

	self.model.FriendlyCollision.CanCollide = false
	self.model.Parent = workspace.Titans.Dead

	for name, track in pairs(self.loadedAnimations) do
		if track.IsPlaying then track:Stop() end
	end
	self:SetState("dead")
	self.bv.MaxForce = Vector3.zero
	self.bg.MaxTorque = Vector3.zero
	self:StopGrab()
	
	self:PlaySound("TitanDeath", true)

	for i, v in pairs(self.model:GetChildren()) do
		if v:IsA("BasePart") then
			if v.Name ~= "HumanoidRootPart" and v.Name ~= "FriendlyCollision" then
				if v.Name == "UpperTorso" or v.Name == "LowerTorso" then
					v.CollisionGroup = "DeadTitanTorso"
				else
					v.CollisionGroup = "DeadTitanLimb"
				end
				v.CanCollide = true
				v.CustomPhysicalProperties = PhysicalProperties.new(100, .5, 0, 20, 100)
			end
		end
	end

	local deathAnim = "Death"..tostring(math.random(1, 6))
	local fade = 0.5

	self.model.HumanoidRootPart.Anchored = true

	local deathTrack = self:PlayAnimation(deathAnim, true, fade)
	deathTrack:GetMarkerReachedSignal("Ground"):Once(function()
		self:PlaySound("FellSound", true)
	end)

	task.delay(3, function()
		for i, v in pairs(self.model.UpperTorso.TitanVapor:GetChildren()) do
			if v:IsA("ParticleEmitter") then
				v.Enabled = true
			end
		end
		
		self.rootPart.DeadSteamSound:Play()
		for i, v in pairs(self.model:GetChildren()) do
			if v:IsA("BasePart") then
				if v.Name ~= "HumanoidRootPart" and v.Name ~= "FriendlyCollision" then
					TweenService:Create(v.SurfaceAppearance, TweenInfo.new(core.DECAY_TIME - 4, Enum.EasingStyle.Linear), {
						Color = Color3.fromRGB(8, 8, 8),
					}):Play()
				end
			end
		end
	end)

	task.delay(core.DECAY_TIME, function()
		self:Destroy()
	end)
end

function core:Destroy()
	for name, track in pairs(self.loadedAnimations) do
		if track.IsPlaying then
			track:Stop()
		end
	end

	self.dead = true

	for i, v in pairs(self.events) do
		v:Disconnect()
		self.events[i] = nil
	end
	self.events = nil

	Registry:Remove(self)
	self.model:Destroy()
end

Remotes.DamageNape.OnServerEvent:Connect(function(player, part, model, speed)
	if not model or not speed or not part then return end
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return end
	if type(speed) ~= "number" then return end
	if model.Parent ~= workspace.Titans.Alive then return end
	if part.Name ~= "Nape" then return end
	if part.Parent == nil or part.Parent.Parent ~= model then return end
	local character = player.Character
	if not character then
		return
	end
	if player:GetAttribute("Grabbed") or player:GetAttribute("Ragdolled") then
		return
	end
	local titan = Registry:GetByModel(model)
	if not titan then return end

	local damage = math.clamp(speed, 10, 9999)
	print(damage)
	if damage < 150 then return end
	titan:DamageNape(damage, character)
end)

Remotes.DamageLimb.OnServerEvent:Connect(function(player, part, model, speed, limbSide, limbType)
	if not model or not speed or not part then return end
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return end
	if type(speed) ~= "number" then return end
	if type(limbSide) ~= "string" then return end
	if type(limbType) ~= "string" then return end
	if model.Parent ~= workspace.Titans.Alive then return end
	if part.Parent == nil or part.Parent.Parent ~= model then return end
	local character = player.Character
	if not character then return end
	if player:GetAttribute("Grabbed") or player:GetAttribute("Ragdolled") then
		return
	end
	local validSides = {Left = true, Right = true}
	local validTypes = {Arm = true, Leg = true}
	if not validSides[limbSide] or not validTypes[limbType] then return end

	local titan = Registry:GetByModel(model)
	if not titan then return end

	local damage = math.clamp(speed, 10, 9999)
	if damage < 50 then return end
	
	local limbKey = limbSide .. limbType
	local wasDisabled = titan.disabledLimbs[limbKey] ~= nil
	titan:DamageLimb(limbSide, limbType, damage, character)
end)

Remotes.DamageEyes.OnServerEvent:Connect(function(player, part, model, speed, eyeSide)
	if not model or not speed or not part then return end
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return end
	if type(speed) ~= "number" then return end
	if type(eyeSide) ~= "string" then return end
	if eyeSide ~= "Left" and eyeSide ~= "Right" then return end
	if model.Parent ~= workspace.Titans.Alive then return end
	if part.Parent == nil or part.Parent.Parent ~= model then return end
	local character = player.Character
	if not character then return end
	if player:GetAttribute("Grabbed") or player:GetAttribute("Ragdolled") then return end
	local titan = Registry:GetByModel(model)
	if not titan then return end

	titan:DamageEyes(eyeSide, character)
end)
Remotes.GrabMe.OnServerEvent:Connect(function(player, titanName, side)
	local character = player.Character
	if not character or character.Parent ~= workspace.Characters then return end
	if type(side) ~= "string" then return end
	if type(titanName) ~= "string" then return end

	if player:GetAttribute("Grabbed") or player:GetAttribute("Ragdolled") then
		return
	end

	local titanModel = workspace.Titans.Alive:FindFirstChild(titanName)
	if not titanModel then return end
	local titanObject = Registry:GetByModel(titanModel)
	if not titanObject then return end

	titanObject:Grab(character, side)
end)

return core