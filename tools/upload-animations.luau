--[[
	Publishes animation saves (KeyframeSequences) to Roblox through Open Cloud
	and builds a folder of Animation instances pointing at the new IDs.

	Run with Lune (https://github.com/lune-org/lune):

		lune run tools/upload-animations <saves.rbxm> [output.rbxm] [all] [dry-run]

	  saves.rbxm   a model file exported from Studio holding the saves
	               (right-click RBX_ANIMSAVES > Rig > Save to File)
	  output.rbxm  where to write the folder of Animations (default ODMG.rbxm)
	  all          upload every save, not just the ones the movement code uses
	  dry-run      skip uploading; the Animations get placeholder IDs

	Environment:
	  ROBLOX_API_KEY   Open Cloud key with the Assets API (read + write)
	  ROBLOX_USER_ID   your user ID, or
	  ROBLOX_GROUP_ID  a group ID to upload under instead

	Drag the output file into ReplicatedStorage.Assets.Animations in Studio.
	The IDs are also written next to it as <output>.txt.
]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Instance = roblox.Instance

-- Saves the ODM movement code looks for (see ODMMovementConfig).
local USED = {
	"FastFlips", "SlowFlip", "GroundSlide", "Burst", "Falling", "GasFlip",
	"HookedBurstStart", "HookedBurstIdle",
	"ForwardODM", "ForwardODM1", "ForwardODM2", "ForwardODM3", "ForwardODM4", "ForwardODM5",
}

local ASSETS_URL = "https://apis.roblox.com/assets/v1/assets"
local OPERATIONS_URL = "https://apis.roblox.com/assets/v1/"

local function fail(message: string): never
	print("error: " .. message)
	process.exit(1)
	error(message)
end

------------------------------------------------------------
-- Arguments
------------------------------------------------------------

local inputPath, outputPath
local uploadAll, dryRun = false, false
for _, arg in process.args do
	if arg == "all" or arg == "--all" then
		uploadAll = true
	elseif arg == "dry-run" or arg == "--dry-run" then
		dryRun = true
	elseif not inputPath then
		inputPath = arg
	elseif not outputPath then
		outputPath = arg
	end
end
if not inputPath then
	fail("usage: lune run tools/upload-animations <saves.rbxm> [output.rbxm] [all] [dry-run]")
end
outputPath = outputPath or "ODMG.rbxm"

local apiKey = process.env.ROBLOX_API_KEY
local userId = process.env.ROBLOX_USER_ID
local groupId = process.env.ROBLOX_GROUP_ID
if not dryRun then
	if not apiKey or apiKey == "" then
		fail("set ROBLOX_API_KEY to your Open Cloud key")
	end
	if (not userId or userId == "") and (not groupId or groupId == "") then
		fail("set ROBLOX_USER_ID (or ROBLOX_GROUP_ID)")
	end
end

------------------------------------------------------------
-- Find the saves
------------------------------------------------------------

if not fs.isFile(inputPath) then
	fail("can't find " .. inputPath)
end
local contents = fs.readFile(inputPath)
local roots = roblox.deserializeModel(contents)

local saves = {}
local function collect(instance)
	if instance:IsA("KeyframeSequence") then
		if saves[instance.Name] then
			print(("note: more than one save named %q, using the first"):format(instance.Name))
		else
			saves[instance.Name] = instance
		end
	end
	for _, child in instance:GetChildren() do
		collect(child)
	end
end
for _, root in roots do
	collect(root)
end

local names = {}
if uploadAll then
	for name in saves do
		table.insert(names, name)
	end
	table.sort(names)
else
	for _, name in USED do
		if saves[name] then
			table.insert(names, name)
		else
			print(("skip: no save named %q in the file"):format(name))
		end
	end
end
if #names == 0 then
	fail("no animation saves found in " .. inputPath)
end

------------------------------------------------------------
-- Upload
------------------------------------------------------------

local function multipart(fields: { { name: string, filename: string?, contentType: string, body: string } })
	local boundary = "----upload" .. tostring(math.random(100000, 999999)) .. tostring(math.random(100000, 999999))
	local parts = {}
	for _, field in fields do
		local disposition = ('form-data; name="%s"'):format(field.name)
		if field.filename then
			disposition ..= ('; filename="%s"'):format(field.filename)
		end
		table.insert(parts, ("--%s\r\nContent-Disposition: %s\r\nContent-Type: %s\r\n\r\n%s\r\n"):format(
			boundary, disposition, field.contentType, field.body
		))
	end
	table.insert(parts, "--" .. boundary .. "--\r\n")
	return table.concat(parts), "multipart/form-data; boundary=" .. boundary
end

local function request(options)
	for attempt = 1, 5 do
		local ok, response = pcall(net.request, options)
		if ok and response.statusCode ~= 429 and response.statusCode < 500 then
			return response
		end
		local reason = if ok then "HTTP " .. response.statusCode else tostring(response)
		print(("  retrying (%s)"):format(reason))
		task.wait(2 ^ attempt)
	end
	fail("Roblox kept refusing the request, try again later")
end

local function upload(name: string, sequence): string
	local file = roblox.serializeModel({ sequence:Clone() })
	local creator = if groupId and groupId ~= "" then { groupId = groupId } else { userId = userId }
	local body, contentType = multipart({
		{
			name = "request",
			contentType = "application/json",
			body = serde.encode("json", {
				assetType = "Animation",
				displayName = string.sub(name, 1, 50),
				description = "ODM animation",
				creationContext = { creator = creator },
			}),
		},
		{ name = "fileContent", filename = name .. ".rbxm", contentType = "model/x-rbxm", body = file },
	})

	local response = request({
		url = ASSETS_URL,
		method = "POST",
		headers = { ["x-api-key"] = apiKey, ["content-type"] = contentType },
		body = body,
	})
	if not response.ok then
		fail(("%s: upload failed (HTTP %d) %s"):format(name, response.statusCode, response.body))
	end

	-- The upload runs as an operation; poll it until it has the asset ID.
	local operation = serde.decode("json", response.body)
	for _ = 1, 30 do
		if operation.done then
			local result = operation.response
			if result and result.assetId then
				return tostring(result.assetId)
			end
			fail(("%s: upload finished without an asset ID: %s"):format(name, serde.encode("json", operation)))
		end
		task.wait(1)
		local poll = request({
			url = OPERATIONS_URL .. operation.path,
			method = "GET",
			headers = { ["x-api-key"] = apiKey },
		})
		if not poll.ok then
			fail(("%s: checking the upload failed (HTTP %d) %s"):format(name, poll.statusCode, poll.body))
		end
		operation = serde.decode("json", poll.body)
	end
	fail(name .. ": upload is taking too long, check the Creator Dashboard")
end

------------------------------------------------------------
-- Build the folder
------------------------------------------------------------

local folder = Instance.new("Folder")
folder.Name = "ODMG"
local lines = {}

for _, name in names do
	local id = if dryRun then "0" else upload(name, saves[name])
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = "rbxassetid://" .. id
	animation.Parent = folder
	table.insert(lines, name .. " = " .. id)
	print(("%s -> rbxassetid://%s"):format(name, id))
end

fs.writeFile(outputPath, roblox.serializeModel({ folder }))
fs.writeFile(outputPath .. ".txt", table.concat(lines, "\n") .. "\n")
print(("\nWrote %d animations to %s (IDs in %s.txt)"):format(#names, outputPath, outputPath))
print("Drag it into ReplicatedStorage.Assets.Animations in Studio.")
