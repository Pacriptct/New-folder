-- ServerScriptService.OdysseyEngine.Services.ODMWireService
--
-- Server half of the ODM movement (client: ODMMovementClient).
--
--   attachHook   -- builds the hook point on the target, ties the Wire
--                   (RopeConstraint from the RootAttachment) to it and flies a
--                   wiggling beam out over the hook's travel time. Once it
--                   lands, a sagging FauxRope is drawn from the launcher.
--   retractHook  -- unties the wire and flies the beam back to the launcher.
--   setWiring    -- boosting on/off. While boosting, every out wire is reeled
--                   in each step; otherwise wires only ever shorten as the
--                   player closes in (so swings tighten, never loosen).
--   effect       -- one-shot sounds, looping sounds and emitter toggles on the
--                   player's own gear, so everyone sees them.
--   splat        -- impact ragdoll for 5 + timeout seconds.
--
-- Each launcher's FirePoint gets a Wire, FauxRope and FauxWire (made here if
-- the gear model doesn't come with them). The movers on the HumanoidRootPart
-- are built on equip (onEquip / onUnequip, called by GearService).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Networker = require(ReplicatedStorage.Packages.Networker)
local ODMGearParts = require(ReplicatedStorage.Shared.Gear.ODMGearParts)
local ODMMovementConfig = require(ReplicatedStorage.Shared.Configs.Gear.ODMMovementConfig)

local WIRE = ODMMovementConfig.Wire
local SIDES = { "Left", "Right" }

local ODMWireService = {}
ODMWireService.networker = nil

type Wires = {
	FirePoint: Attachment,
	Wire: RopeConstraint,
	FauxRope: RopeConstraint,
	FauxWire: Beam,
	Token: number,
}

type State = {
	Character: Model,
	Root: BasePart,
	GlobalWiring: boolean,
	WasWiring: boolean,
	Hooking: boolean,
	Splatting: boolean,
	Out: { [string]: boolean },
	Wires: { [string]: Wires },
}

local states: { [Player]: State } = {}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function distance(a: Vector3, b: Vector3): number
	return (b - a).Magnitude
end

local function getOrCreate(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local function buildWires(character: Model, side: string): Wires?
	local firePoint = ODMGearParts.getFirePoint(character, side)
	if not firePoint then
		return nil
	end

	local wire = getOrCreate(firePoint, "Wire", "RopeConstraint") :: RopeConstraint
	wire.Visible = false
	wire.Length = 0

	local fauxRope = getOrCreate(firePoint, "FauxRope", "RopeConstraint") :: RopeConstraint
	fauxRope.Attachment0 = firePoint
	fauxRope.Visible = true
	fauxRope.Thickness = WIRE.Thickness
	fauxRope.Color = BrickColor.new(WIRE.Color)
	fauxRope.Length = 0

	local fauxWire = getOrCreate(firePoint, "FauxWire", "Beam") :: Beam
	fauxWire.Attachment0 = firePoint
	fauxWire.Width0 = WIRE.BeamWidth
	fauxWire.Width1 = WIRE.BeamWidth
	fauxWire.Segments = WIRE.BeamSegments
	fauxWire.Color = ColorSequence.new(WIRE.Color)
	fauxWire.FaceCamera = true
	fauxWire.LightInfluence = 1
	fauxWire.Enabled = false

	return { FirePoint = firePoint, Wire = wire, FauxRope = fauxRope, FauxWire = fauxWire, Token = 0 }
end

local function wiggle(fauxWire: Beam)
	task.spawn(function()
		local counter = WIRE.WiggleTime
		repeat
			local range = math.floor(counter * 10)
			TweenService:Create(fauxWire, TweenInfo.new(0.02), { CurveSize0 = math.random(-range, range) }):Play()
			TweenService:Create(fauxWire, TweenInfo.new(0.02), { CurveSize1 = math.random(-range, range) }):Play()
			counter -= 0.02
			task.wait(0.02)
		until counter <= 0
	end)
end

-- Not boosting: the wire only ever shortens as the player closes in.
local function sustainWireDraw(state: State, side: string)
	if state.Hooking then
		return
	end
	local wires = state.Wires[side]
	if not wires then
		return
	end
	task.spawn(function()
		repeat
			local hookPoint = wires.Wire.Attachment1
			if not hookPoint or not state.Root.Parent or not state.Out[side] then
				return
			end
			local dist = distance(hookPoint.WorldPosition, state.Root.Position)
			local fauxDist = distance(hookPoint.WorldPosition, wires.FirePoint.WorldPosition)
			if dist <= wires.Wire.Length then
				wires.Wire.Length = dist - WIRE.SustainPerStep
				wires.FauxRope.Length = fauxDist * 1.001
			end
			task.wait()
		until state.GlobalWiring or state.Hooking
	end)
end

-- Hooks on anything that moves on its own (an unanchored assembly: a titan, a
-- spinning dummy) aren't tied to the part itself. The rope would couple the
-- player to whatever drives that part, and a motor or a server-owned titan
-- flings them. Instead the rope goes to an anchored, invisible stand-in that
-- follows the hit point every frame, so the hook still moves with the part
-- but no force passes between the two.
local proxyFolder: Folder? = nil

local function isStatic(part: BasePart): boolean
	if part.Anchored then
		return true
	end
	local root = part.AssemblyRootPart
	return root ~= nil and root.Anchored
end

local function hookAnchor(target: BasePart, point: Vector3, owner: BasePart): BasePart
	if isStatic(target) then
		return target
	end
	if not proxyFolder or not proxyFolder.Parent then
		proxyFolder = Instance.new("Folder")
		proxyFolder.Name = "ODMHookAnchors"
		proxyFolder.Parent = workspace
	end
	local offset = target.CFrame:ToObjectSpace(CFrame.new(point))
	local proxy = Instance.new("Part")
	proxy.Name = "HookAnchor"
	proxy.Anchored = true
	proxy.CanCollide = false
	proxy.CanQuery = false
	proxy.CanTouch = false
	proxy.Transparency = 1
	proxy.Size = Vector3.new(0.2, 0.2, 0.2)
	proxy.CFrame = target.CFrame * offset
	proxy.Parent = proxyFolder

	local follow
	follow = RunService.Heartbeat:Connect(function()
		if not proxy.Parent or not target:IsDescendantOf(workspace) or not owner:IsDescendantOf(workspace) then
			follow:Disconnect()
			proxy:Destroy()
			return
		end
		proxy.CFrame = target.CFrame * offset
	end)
	-- The hook point lives on the stand-in; when the hook is let go (its
	-- attachment destroyed) or the player's character is gone, the stand-in
	-- goes with it.
	proxy.ChildRemoved:Connect(function()
		if #proxy:GetChildren() == 0 then
			follow:Disconnect()
			proxy:Destroy()
		end
	end)
	return proxy
end

local function getState(player: Player): State?
	local state = states[player]
	if state and state.Character == player.Character and state.Root.Parent then
		return state
	end
	return nil
end

local function isSide(side: any): boolean
	return side == "Left" or side == "Right"
end

------------------------------------------------------------
-- Equip
------------------------------------------------------------

function ODMWireService:onEquip(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		return
	end
	-- Equip runs again when the client confirms; keep what's already built.
	local existing = states[player]
	if existing and existing.Character == character and root:FindFirstChild("BoostForce") then
		return
	end

	ODMGearParts.buildForces(character)

	local state: State = {
		Character = character,
		Root = root,
		GlobalWiring = false,
		WasWiring = false,
		Hooking = false,
		Splatting = false,
		Out = { Left = false, Right = false },
		Wires = {},
	}
	for _, side in SIDES do
		state.Wires[side] = buildWires(character, side) :: any
	end
	states[player] = state
end

function ODMWireService:onUnequip(player: Player)
	local state = states[player]
	states[player] = nil
	if state then
		for _, wires in state.Wires do
			local hookPoint = wires.Wire.Attachment1
			if hookPoint then
				hookPoint:Destroy()
			end
			wires.Wire.Length = 0
			wires.FauxRope.Length = 0
			wires.FauxWire.Enabled = false
		end
		if state.Character.Parent then
			ODMGearParts.removeForces(state.Character)
		end
	end
end

------------------------------------------------------------
-- Client -> server
------------------------------------------------------------

function ODMWireService:attachHook(player: Player, side: string, point: Vector3, travelTime: number, target: Instance)
	local state = getState(player)
	if not state or not isSide(side) or typeof(point) ~= "Vector3" or type(travelTime) ~= "number" then
		return
	end
	if typeof(target) ~= "Instance" or not target:IsA("BasePart") or not target:IsDescendantOf(workspace) then
		return
	end
	if target:IsDescendantOf(state.Character) then
		return
	end
	local wires = state.Wires[side]
	if not wires then
		return
	end
	if distance(point, state.Root.Position) > ODMMovementConfig.MaxHookDistance + 50 then
		return
	end
	travelTime = math.clamp(travelTime, 0, 1)

	state.Hooking = true
	wires.Token += 1

	local old = wires.Wire.Attachment1
	if old then
		old:Destroy()
	end

	local anchor = hookAnchor(target, point, state.Root)
	local hookPoint = Instance.new("Attachment")
	hookPoint.Name = "HookAttachPoint"
	hookPoint.Parent = anchor
	hookPoint.WorldPosition = wires.FirePoint.WorldPosition

	local dist = distance(point, state.Root.Position)
	local fauxDist = distance(point, wires.FirePoint.WorldPosition)
	local rootAttachment = state.Root:FindFirstChild("RootAttachment") :: Attachment?

	wires.Wire.Length = dist
	wires.FauxWire.Attachment1 = hookPoint
	wires.Wire.Attachment0 = rootAttachment
	wires.Wire.Attachment1 = hookPoint
	wires.FauxRope.Length = fauxDist
	wires.FauxWire.Enabled = true
	wires.FauxRope.Attachment1 = hookPoint

	wiggle(wires.FauxWire)
	wires.FauxRope.Visible = false
	-- Tweened in the anchor's own space so the hook lands on the spot it was
	-- aimed at even if that part moves while it flies.
	local landing = anchor.CFrame:PointToObjectSpace(point)
	TweenService:Create(hookPoint, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), { Position = landing }):Play()
	task.wait(travelTime)

	if wires.Wire.Attachment1 ~= hookPoint then
		return
	end
	wires.FauxRope.Length = fauxDist
	wires.FauxRope.Visible = true
	wires.FauxWire.Enabled = false
	state.Hooking = false
	state.Out[side] = true
	sustainWireDraw(state, side)
end

function ODMWireService:retractHook(player: Player, side: string, auto: boolean, travelTime: number)
	local state = getState(player)
	if not state or not isSide(side) then
		return
	end
	local wires = state.Wires[side]
	if not wires then
		return
	end
	state.Out[side] = false
	travelTime = math.clamp(tonumber(travelTime) or 0, 0, 1)

	if auto then
		repeat
			task.wait()
		until not state.Hooking
		state.Hooking = true
		local hookPoint = wires.Wire.Attachment1
		if hookPoint then
			hookPoint:Destroy()
		end
		state.Hooking = false
		wires.FauxRope.Visible = true
		wires.FauxWire.Enabled = false
		return
	end

	local hookPoint = wires.FauxRope.Attachment1
	if not hookPoint then
		return
	end
	state.Hooking = true
	wires.Token += 1
	local token = wires.Token

	-- The beam flies back from where the hook was to the launcher.
	local returnPoint = Instance.new("Attachment")
	returnPoint.Name = "FauxRopeAttachPoint"
	returnPoint.Parent = workspace.Terrain
	returnPoint.WorldPosition = hookPoint.WorldPosition

	wiggle(wires.FauxWire)
	wires.FauxWire.Attachment1 = returnPoint
	wires.FauxWire.Enabled = true
	wires.FauxRope.Visible = false
	hookPoint:Destroy()

	TweenService:Create(returnPoint, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
		WorldPosition = wires.FirePoint.WorldPosition,
	}):Play()
	task.wait(travelTime)
	returnPoint:Destroy()

	if wires.Token ~= token then
		return
	end
	wires.Wire.Length = 0
	wires.FauxRope.Length = 0
	state.Hooking = false
	wires.FauxWire.Enabled = false
	wires.FauxRope.Visible = true
end

function ODMWireService:setWiring(player: Player, wiring: boolean)
	local state = getState(player)
	if state then
		state.GlobalWiring = wiring == true
	end
end

function ODMWireService:effect(player: Player, action: string, key: string, enabled: boolean?)
	local character = player.Character
	if not character or type(key) ~= "string" then
		return
	end

	if action == "ImpulseSound" then
		if not ODMGearParts.SoundKeys[key] then
			return
		end
		local reference = ODMGearParts.getSound(character, key)
		if reference then
			local sound = reference:Clone()
			sound.Looped = false
			sound.Parent = reference.Parent
			sound:Play()
			Debris:AddItem(sound, 10)
		end
	elseif action == "ToggleSound" then
		if not ODMGearParts.SoundKeys[key] then
			return
		end
		local sound = ODMGearParts.getSound(character, key)
		if sound then
			if enabled then
				sound.Looped = true
			end
			sound.Playing = enabled == true
		end
	elseif action == "ToggleEffect" then
		if not ODMGearParts.EffectKeys[key] then
			return
		end
		for _, effect in ODMGearParts.getEffects(character, key) do
			(effect :: any).Enabled = enabled == true
		end
	end
end

function ODMWireService:splat(player: Player, timeout: number)
	local state = getState(player)
	if not state or state.Splatting then
		return
	end
	timeout = math.clamp(tonumber(timeout) or 0, 0, 20)
	state.Splatting = true

	player:SetAttribute("RagdollTime", 5 + timeout)
	player:SetAttribute("RagdollToken", (player:GetAttribute("RagdollToken") or 0) + 1)
	task.wait(5 + timeout)
	state.Splatting = false
	if player.Parent then
		self.networker:fire(player, "splatEnded")
	end
end

------------------------------------------------------------
-- Reel
------------------------------------------------------------

local function step()
	for player, state in states do
		if not state.Root.Parent then
			continue
		end

		local minimumReelDistance = 0
		local left, right = state.Wires.Left, state.Wires.Right
		if state.Out.Left and state.Out.Right and left and right then
			local a, b = left.Wire.Attachment1, right.Wire.Attachment1
			if a and b then
				minimumReelDistance = distance(a.WorldPosition, b.WorldPosition) / 2
			end
		end

		for _, side in SIDES do
			local wires = state.Wires[side]
			local hookPoint = wires and wires.Wire.Attachment1
			if not state.Out[side] or not wires or not hookPoint then
				continue
			end

			local dist = distance(hookPoint.WorldPosition, state.Root.Position)
			if state.GlobalWiring then
				wires.FauxWire.Attachment1 = wires.FauxRope.Attachment1
				if dist - WIRE.ReelPerStep <= wires.Wire.Length and dist > minimumReelDistance then
					wires.Wire.Length = dist - WIRE.ReelPerStep
					wires.FauxRope.Length = wires.Wire.Length * 1.005
				end
				wires.FauxRope.Visible = false
				wires.FauxWire.Enabled = true
			else
				wires.FauxRope.Visible = true
				if not state.Hooking then
					wires.FauxWire.Enabled = false
				end
				if state.WasWiring then
					sustainWireDraw(state, side)
				end
			end
		end

		state.WasWiring = state.GlobalWiring
	end
end

function ODMWireService:init()
	self.networker = Networker.server.new("ODMWireService", self, {
		self.attachHook,
		self.retractHook,
		self.setWiring,
		self.effect,
		self.splat,
	})

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	RunService.Stepped:Connect(step)
end

return ODMWireService
