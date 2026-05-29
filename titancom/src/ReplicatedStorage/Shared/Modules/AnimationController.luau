local ContentProvider = game:GetService("ContentProvider")

local AnimationController = {}

AnimationController._tracks = {}
AnimationController._layers = {}

local function fullKey(layer, key)
	if string.sub(key, 1, #layer + 1) == layer .. "." then
		return key
	end

	return layer .. "." .. key
end

local function gatherAnimations(folder, path, result)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Animation") then
			result[path and (path .. "." .. child.Name) or child.Name] = child
		elseif child:IsA("Folder") then
			gatherAnimations(child, path and (path .. "." .. child.Name) or child.Name, result)
		end
	end
end

function AnimationController:LoadLayer(layer, animator, animationsFolder, groupResolver)
	self:UnloadLayer(layer, 0)

	local found = {}
	gatherAnimations(animationsFolder, nil, found)

	local assets = {}

	for _, anim in pairs(found) do
		table.insert(assets, anim)
	end

	if #assets > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
	end

	self._layers[layer] = self._layers[layer] or {}

	for key, anim in pairs(found) do
		local success, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)

		if success and track then
			local name = fullKey(layer, key)

			self._tracks[name] = {
				Track = track,
				Layer = layer,
				Group = groupResolver and groupResolver(key) or nil,
				Key = key,
			}

			self._layers[layer][name] = true
		else
			warn("[AnimationController] Failed to load:", layer, key, anim.AnimationId)
		end
	end
end

function AnimationController:GetTrack(layerOrName, key)
	local name = key and fullKey(layerOrName, key) or layerOrName
	local record = self._tracks[name]

	return record and record.Track or nil
end

function AnimationController:IsPlaying(layerOrName, key)
	local track = self:GetTrack(layerOrName, key)
	return track ~= nil and track.IsPlaying
end

function AnimationController:Play(layer, key, options)
	options = options or {}

	local name = fullKey(layer, key)
	local record = self._tracks[name]

	if not record then
		warn("[AnimationController] Missing track:", name)
		return nil
	end

	if options.StopGroup then
		self:StopGroup(layer, options.StopGroup, options.FadeTime)
	end

	local track = record.Track
	local fadeTime = options.FadeTime or 0.15
	local weight = options.Weight or 1
	local speed = options.Speed or 1

	if options.Priority then
		track.Priority = options.Priority
	end

	if options.Looped ~= nil then
		track.Looped = options.Looped
	end

	if options.Restart and track.IsPlaying then
		track:Stop(0)
	end

	if not track.IsPlaying then
		track:Play(fadeTime, weight, speed)
	else
		track:AdjustWeight(math.max(weight, 0.0001), fadeTime)
		track:AdjustSpeed(speed)
	end

	return track
end

function AnimationController:Stop(layerOrName, keyOrFadeTime, fadeTime)
	local name
	local fade

	if typeof(keyOrFadeTime) == "string" then
		name = fullKey(layerOrName, keyOrFadeTime)
		fade = fadeTime or 0.15
	else
		name = layerOrName
		fade = keyOrFadeTime or 0.15
	end

	local record = self._tracks[name]

	if record and record.Track.IsPlaying then
		record.Track:Stop(fade)
	end
end

function AnimationController:StopLayer(layer, fadeTime)
	local layerTracks = self._layers[layer]

	if not layerTracks then
		return
	end

	for name in pairs(layerTracks) do
		local record = self._tracks[name]

		if record and record.Track.IsPlaying then
			record.Track:Stop(fadeTime or 0.15)
		end
	end
end

function AnimationController:StopGroup(layer, group, fadeTime)
	local layerTracks = self._layers[layer]

	if not layerTracks then
		return
	end

	for name in pairs(layerTracks) do
		local record = self._tracks[name]

		if record and record.Group == group and record.Track.IsPlaying then
			record.Track:Stop(fadeTime or 0.15)
		end
	end
end

function AnimationController:StopExcept(layer, keepKeys, fadeTime)
	local keep = {}

	for _, key in ipairs(keepKeys) do
		keep[fullKey(layer, key)] = true
	end

	local layerTracks = self._layers[layer]

	if not layerTracks then
		return
	end

	for name in pairs(layerTracks) do
		if not keep[name] then
			local record = self._tracks[name]

			if record and record.Track.IsPlaying then
				record.Track:Stop(fadeTime or 0.15)
			end
		end
	end
end

function AnimationController:SetWeight(layer, key, weight, fadeTime)
	local track = self:GetTrack(layer, key)

	if track then
		track:AdjustWeight(math.max(weight, 0.0001), fadeTime or 0.15)
	end
end

function AnimationController:SetSpeed(layer, key, speed)
	local track = self:GetTrack(layer, key)

	if track then
		track:AdjustSpeed(speed)
	end
end

function AnimationController:UnloadLayer(layer, fadeTime)
	local layerTracks = self._layers[layer]

	if not layerTracks then
		return
	end

	for name in pairs(layerTracks) do
		local record = self._tracks[name]

		if record then
			if record.Track.IsPlaying then
				record.Track:Stop(fadeTime or 0)
			end

			pcall(function()
				record.Track:Destroy()
			end)

			self._tracks[name] = nil
		end
	end

	self._layers[layer] = nil
end

function AnimationController:UnloadCharacter(fadeTime)
	for layer in pairs(self._layers) do
		self:UnloadLayer(layer, fadeTime or 0)
	end
end

function AnimationController:DebugLayer(layer)
	local layerTracks = self._layers[layer]

	if not layerTracks then
		warn("[AnimationController] No layer:", layer)
		return
	end

	for name in pairs(layerTracks) do
		print("[AnimationController]", name)
	end
end

return AnimationController