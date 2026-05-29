-- AudioGroups
--
-- Centralised SoundGroup wiring so the volume sliders in the settings menu
-- actually do something. Sounds in the project used to be parented to ad-hoc
-- parts with no SoundGroup, which meant moving the SFX / Music / Ambient
-- sliders had no effect.
--
-- The structure created under SoundService is:
--
--   Master  (SoundGroup)            <- root, master volume
--     SFX        (SoundGroup)
--     Music      (SoundGroup)
--     Ambient    (SoundGroup)
--
-- Roblox compounds nested SoundGroup volumes, so the effective volume of a
-- sound assigned to e.g. SFX is `Master.Volume * SFX.Volume * Sound.Volume`.
-- That lets a single master slider affect every category at once while still
-- letting each category be tuned independently.

local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Chat = game:GetService("Chat")
local StarterGui = game:GetService("StarterGui")

local AudioGroups = {}

export type Category = "Master" | "SFX" | "Music" | "Ambient"

local CATEGORIES: { Category } = { "SFX", "Music", "Ambient" }

local DEFAULT_VOLUMES = {
	Master = 0.8,
	SFX = 1.0,
	Music = 0.5,
	Ambient = 0.6,
}

local _ensured = false

local IS_CLIENT = RunService:IsClient()

-- On the server we own the SoundGroup hierarchy: create groups outright. On
-- the client we want to use whatever the server already replicated to avoid
-- having two parallel "Master" groups (one locally created, one replicated)
-- where the settings slider drives one and our Sounds are routed into the
-- other. So clients always WaitForChild the server's groups; only as a last
-- resort (e.g. running in a place without the server bootstrap) does the
-- client fall back to creating its own.
local CLIENT_WAIT_TIMEOUT = 5

local function getOrCreateGroup(name: string, parent: Instance, defaultVolume: number): SoundGroup
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end

	if IS_CLIENT then
		local waited = parent:WaitForChild(name, CLIENT_WAIT_TIMEOUT)
		if waited and waited:IsA("SoundGroup") then
			return waited
		end
	end

	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Volume = defaultVolume
	group.Parent = parent
	return group
end

function AudioGroups.ensure(): { [Category]: SoundGroup }
	local master = getOrCreateGroup("Master", SoundService, DEFAULT_VOLUMES.Master)

	local groups: { [Category]: SoundGroup } = {
		Master = master,
	}

	for _, name in ipairs(CATEGORIES) do
		groups[name] = getOrCreateGroup(name, master, DEFAULT_VOLUMES[name])
	end

	_ensured = true
	return groups
end

-- Client safeguard: if we somehow ended up with a duplicate "Master" group
-- (we created one before the server's replicated, or vice versa), reroute
-- every Sound on the local Sound graph that points into a stale group.
local function reconcileDuplicateMasters()
	if not IS_CLIENT then
		return
	end

	local masters = {}
	for _, child in ipairs(SoundService:GetChildren()) do
		if child:IsA("SoundGroup") and child.Name == "Master" then
			table.insert(masters, child)
		end
	end

	if #masters <= 1 then
		return
	end

	-- Keep the first one (replicated from the server is usually first since it
	-- replicates during InitialReplication before our local ensure runs).
	-- AudioGroups.get / setVolume / assign all resolve through
	-- SoundService:FindFirstChild("Master") which returns the survivor.
	for i = 2, #masters do
		masters[i].Parent = nil
	end
end

function AudioGroups.get(category: Category): SoundGroup?
	if not _ensured then
		AudioGroups.ensure()
	end

	if category == "Master" then
		return SoundService:FindFirstChild("Master") :: SoundGroup?
	end

	local master = SoundService:FindFirstChild("Master")
	if not master then
		return nil
	end

	local group = master:FindFirstChild(category)
	if group and group:IsA("SoundGroup") then
		return group
	end

	return nil
end

-- Routes a Sound (or a freshly-cloned Sound) into the named category.
-- Safe to call from any side; the groups will be lazily ensured if missing.
function AudioGroups.assign(sound: Sound, category: Category)
	if typeof(sound) ~= "Instance" or not sound:IsA("Sound") then
		return
	end

	if category == "Master" then
		category = "SFX"
	end

	local group = AudioGroups.get(category)
	if group then
		sound.SoundGroup = group
	end
end

function AudioGroups.setVolume(category: Category, volume: number)
	local group = AudioGroups.get(category)
	if group then
		group.Volume = math.clamp(volume, 0, 2)
	end
end

-- ── Auto-routing ──────────────────────────────────────────────────────────────
--
-- Lots of Sound instances exist in the game without a SoundGroup set: built-in
-- character footstep sounds (Running, Climbing, etc.), pre-authored sounds in
-- map models, sounds parented to tools at design time, and so on. Without a
-- SoundGroup they bypass Master/SFX/Music/Ambient entirely, which is why
-- "set master to 0 and you can still hear stuff" happens.
--
-- startAutoRoute walks every Sound that already exists in the relevant
-- container hierarchies and assigns any unassigned ones to a sensible default
-- (SFX). It also hooks DescendantAdded so newly-streamed-in / newly-cloned
-- sounds get routed the moment they appear.
--
-- Names that look like music or ambient loops are routed into those groups
-- instead so the per-category sliders still apply meaningfully.

local _autoRouteStarted = false
local _autoRouteConnections: { RBXScriptConnection } = {}

local AMBIENT_NAME_HINTS = {
	"ambient",
	"wind",
	"rain",
	"snow",
	"thunder",
	"weather",
	"loop",
	"outdoors",
	"forest",
	"ocean",
	"river",
	"stream",
	"crickets",
	"birds",
	"fire",
	"torch",
}

local MUSIC_NAME_HINTS = {
	"music",
	"ost",
	"score",
	"theme",
	"menu",
	"background",
	"soundtrack",
	"bgm",
}

local function nameMatches(name: string, hints: { string }): boolean
	local lower = string.lower(name)
	for _, hint in ipairs(hints) do
		if string.find(lower, hint, 1, true) then
			return true
		end
	end
	return false
end

local function classify(sound: Sound): Category
	local name = sound.Name or ""

	if nameMatches(name, MUSIC_NAME_HINTS) then
		return "Music"
	end

	if nameMatches(name, AMBIENT_NAME_HINTS) then
		return "Ambient"
	end

	-- Looped non-positional sounds tend to be music or ambience. Looped 3D
	-- sounds (footsteps, fire crackle) are still SFX so we leave them alone
	-- unless the name hint above said otherwise.
	if sound.Looped and sound.RollOffMaxDistance >= 1000 then
		return "Music"
	end

	return "SFX"
end

-- Returns true if `group` is our Master group or a descendant of it.
local function isManagedGroup(group: SoundGroup?): boolean
	if not group then
		return false
	end

	local master = SoundService:FindFirstChild("Master")
	if not master then
		return false
	end

	if group == master then
		return true
	end

	return group:IsDescendantOf(master)
end

local _guarded: { [Sound]: true } = setmetatable({}, { __mode = "k" }) :: any

-- Forward declarations: routeIfUnassigned and attachSoundGroupGuard call
-- each other.
local routeIfUnassigned
local attachSoundGroupGuard

function attachSoundGroupGuard(sound: Sound)
	-- Re-route if some other code clears or overrides SoundGroup later.
	local conn
	conn = sound:GetPropertyChangedSignal("SoundGroup"):Connect(function()
		if not sound.Parent then
			if conn then
				conn:Disconnect()
			end
			return
		end
		if not isManagedGroup(sound.SoundGroup) and not sound:FindFirstAncestorWhichIsA("SoundGroup") then
			AudioGroups.assign(sound, classify(sound))
		end
	end)
end

function routeIfUnassigned(sound: Sound)
	-- Skip sounds that themselves live inside a SoundGroup; setting SoundGroup
	-- on those changes nothing (the parent group already routes them).
	-- Rain/Snow's looped weather Sounds are an example.
	if sound:FindFirstAncestorWhichIsA("SoundGroup") then
		return
	end

	-- Already routed into our hierarchy? Leave it alone — explicit code
	-- (e.g. _cacheGearSounds, HorseService) decided where it should live.
	-- Otherwise (nil OR a legacy/unmanaged group), override so the master /
	-- per-category sliders actually affect this sound.
	if not isManagedGroup(sound.SoundGroup) then
		AudioGroups.assign(sound, classify(sound))
	end

	if not _guarded[sound] then
		_guarded[sound] = true
		attachSoundGroupGuard(sound)
	end
end

local function sweepContainer(container: Instance)
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("Sound") then
			routeIfUnassigned(descendant)
		end
	end
end

local function watchContainer(container: Instance)
	table.insert(
		_autoRouteConnections,
		container.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("Sound") then
				-- Route immediately. Sounds in this project are created at runtime
				-- via Instance.new / template:Clone and frequently :Play()ed in
				-- the same frame they're parented, so deferring even a single
				-- frame means the first hit lands at full volume before our
				-- SoundGroup assignment lands.
				routeIfUnassigned(descendant)
			end
		end)
	)
end

function AudioGroups.startAutoRoute()
	if _autoRouteStarted then
		return
	end
	_autoRouteStarted = true

	AudioGroups.ensure()
	reconcileDuplicateMasters()

	local containers: { Instance } = { Workspace, ReplicatedStorage, SoundService, StarterGui, Players }

	-- Chat is missing on some place templates; pcall in case it's stripped.
	pcall(function()
		table.insert(containers, Chat)
	end)

	for _, container in ipairs(containers) do
		sweepContainer(container)
		watchContainer(container)
	end

	-- Player characters arrive after the player joins; sweep + watch each one
	-- so footstep / jump / climbing sounds get routed too.
	local function bindPlayer(player: Player)
		local function bindCharacter(character: Model)
			sweepContainer(character)
			watchContainer(character)
		end

		if player.Character then
			bindCharacter(player.Character)
		end

		table.insert(_autoRouteConnections, player.CharacterAdded:Connect(bindCharacter))
	end

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end

	table.insert(_autoRouteConnections, Players.PlayerAdded:Connect(bindPlayer))
end

return AudioGroups
