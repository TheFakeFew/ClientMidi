local owner = owner or script:FindFirstAncestorOfClass("Player") or game:GetService("Players"):GetPlayerFromCharacter(script:FindFirstAncestorOfClass("Model"))

local function Decode(str)
	local StringLength = #str

	-- Base64 decoding
	do
		local decoder = {}
		for b64code, char in pairs(('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/='):split('')) do
			decoder[char:byte()] = b64code-1
		end
		local n = StringLength
		local t,k = table.create(math.floor(n/4)+1),1
		local padding = str:sub(-2) == '==' and 2 or str:sub(-1) == '=' and 1 or 0
		for i = 1, padding > 0 and n-4 or n, 4 do
			local a, b, c, d = str:byte(i,i+3)
			local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40 + decoder[d]
			t[k] = string.char(bit32.extract(v,16,8),bit32.extract(v,8,8),bit32.extract(v,0,8))
			k = k + 1
		end
		if padding == 1 then
			local a, b, c = str:byte(n-3,n-1)
			local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40
			t[k] = string.char(bit32.extract(v,16,8),bit32.extract(v,8,8))
		elseif padding == 2 then
			local a, b = str:byte(n-3,n-2)
			local v = decoder[a]*0x40000 + decoder[b]*0x1000
			t[k] = string.char(bit32.extract(v,16,8))
		end
		str = table.concat(t)
	end

	local Position = 1
	local function Parse(fmt)
		local Values = {string.unpack(fmt,str,Position)}
		Position = table.remove(Values)
		return table.unpack(Values)
	end

	local Settings = Parse('B')
	local Flags = Parse('B')
	Flags = {
		--[[ValueIndexByteLength]] bit32.extract(Flags,6,2)+1,
		--[[InstanceIndexByteLength]] bit32.extract(Flags,4,2)+1,
		--[[ConnectionsIndexByteLength]] bit32.extract(Flags,2,2)+1,
		--[[MaxPropertiesLengthByteLength]] bit32.extract(Flags,0,2)+1,
		--[[Use Double instead of Float]] bit32.band(Settings,0b1) > 0
	}

	local ValueFMT = ('I'..Flags[1])
	local InstanceFMT = ('I'..Flags[2])
	local ConnectionFMT = ('I'..Flags[3])
	local PropertyLengthFMT = ('I'..Flags[4])

	local ValuesLength = Parse(ValueFMT)
	local Values = table.create(ValuesLength)
	local CFrameIndexes = {}

	local ValueDecoders = {
		--!!Start
		[1] = function(Modifier)
			return Parse('s'..Modifier)
		end,
		--!!Split
		[2] = function(Modifier)
			return Modifier ~= 0
		end,
		--!!Split
		[3] = function()
			return Parse('d')
		end,
		--!!Split
		[4] = function(_,Index)
			table.insert(CFrameIndexes,{Index,Parse(('I'..Flags[1]):rep(3))})
		end,
		--!!Split
		[5] = {CFrame.new,Flags[5] and 'dddddddddddd' or 'ffffffffffff'},
		--!!Split
		[6] = {Color3.fromRGB,'BBB'},
		--!!Split
		[7] = {BrickColor.new,'I2'},
		--!!Split
		[8] = function(Modifier)
			local len = Parse('I'..Modifier)
			local kpts = table.create(len)
			for i = 1,len do
				kpts[i] = ColorSequenceKeypoint.new(Parse('f'),Color3.fromRGB(Parse('BBB')))
			end
			return ColorSequence.new(kpts)
		end,
		--!!Split
		[9] = function(Modifier)
			local len = Parse('I'..Modifier)
			local kpts = table.create(len)
			for i = 1,len do
				kpts[i] = NumberSequenceKeypoint.new(Parse(Flags[5] and 'ddd' or 'fff'))
			end
			return NumberSequence.new(kpts)
		end,
		--!!Split
		[10] = {Vector3.new,Flags[5] and 'ddd' or 'fff'},
		--!!Split
		[11] = {Vector2.new,Flags[5] and 'dd' or 'ff'},
		--!!Split
		[12] = {UDim2.new,Flags[5] and 'di2di2' or 'fi2fi2'},
		--!!Split
		[13] = {Rect.new,Flags[5] and 'dddd' or 'ffff'},
		--!!Split
		[14] = function()
			local flags = Parse('B')
			local ids = {"Top","Bottom","Left","Right","Front","Back"}
			local t = {}
			for i = 0,5 do
				if bit32.extract(flags,i,1)==1 then
					table.insert(t,Enum.NormalId[ids[i+1]])
				end
			end
			return Axes.new(unpack(t))
		end,
		--!!Split
		[15] = function()
			local flags = Parse('B')
			local ids = {"Top","Bottom","Left","Right","Front","Back"}
			local t = {}
			for i = 0,5 do
				if bit32.extract(flags,i,1)==1 then
					table.insert(t,Enum.NormalId[ids[i+1]])
				end
			end
			return Faces.new(unpack(t))
		end,
		--!!Split
		[16] = {PhysicalProperties.new,Flags[5] and 'ddddd' or 'fffff'},
		--!!Split
		[17] = {NumberRange.new,Flags[5] and 'dd' or 'ff'},
		--!!Split
		[18] = {UDim.new,Flags[5] and 'di2' or 'fi2'},
		--!!Split
		[19] = function()
			return Ray.new(Vector3.new(Parse(Flags[5] and 'ddd' or 'fff')),Vector3.new(Parse(Flags[5] and 'ddd' or 'fff')))
		end
		--!!End
	}

	for i = 1,ValuesLength do
		local TypeAndModifier = Parse('B')
		local Type = bit32.band(TypeAndModifier,0b11111)
		local Modifier = (TypeAndModifier - Type) / 0b100000
		local Decoder = ValueDecoders[Type]
		if type(Decoder)=='function' then
			Values[i] = Decoder(Modifier,i)
		else
			Values[i] = Decoder[1](Parse(Decoder[2]))
		end
	end

	for i,t in pairs(CFrameIndexes) do
		Values[t[1]] = CFrame.fromMatrix(Values[t[2]],Values[t[3]],Values[t[4]])
	end

	local InstancesLength = Parse(InstanceFMT)
	local Instances = {}
	local NoParent = {}

	for i = 1,InstancesLength do
		local ClassName = Values[Parse(ValueFMT)]
		local obj
		local MeshPartMesh,MeshPartScale
		if ClassName == "UnionOperation" then
			obj = DecodeUnion(Values,Flags,Parse)
			obj.UsePartColor = true
		elseif ClassName:find("Script") then
			obj = Instance.new("Folder")
			Script(obj,ClassName=='ModuleScript')
		elseif ClassName == "MeshPart" then
			obj = Instance.new("Part")
			MeshPartMesh = Instance.new("SpecialMesh")
			MeshPartMesh.MeshType = Enum.MeshType.FileMesh
			MeshPartMesh.Parent = obj
		else
			obj = Instance.new(ClassName)
		end
		local Parent = Instances[Parse(InstanceFMT)]
		local PropertiesLength = Parse(PropertyLengthFMT)
		local AttributesLength = Parse(PropertyLengthFMT)
		Instances[i] = obj
		for i = 1,PropertiesLength do
			local Prop,Value = Values[Parse(ValueFMT)],Values[Parse(ValueFMT)]

			-- ok this looks awful
			if MeshPartMesh then
				if Prop == "MeshId" then
					MeshPartMesh.MeshId = Value
					continue
				elseif Prop == "TextureID" then
					MeshPartMesh.TextureId = Value
					continue
				elseif Prop == "Size" then
					if not MeshPartScale then
						MeshPartScale = Value
					else
						MeshPartMesh.Scale = Value / MeshPartScale
					end
				elseif Prop == "MeshSize" then
					if not MeshPartScale then
						MeshPartScale = Value
						MeshPartMesh.Scale = obj.Size / Value
					else
						MeshPartMesh.Scale = MeshPartScale / Value
					end
					continue
				end
			end

			obj[Prop] = Value
		end
		if MeshPartMesh then
			if MeshPartMesh.MeshId=='' then
				if MeshPartMesh.TextureId=='' then
					MeshPartMesh.TextureId = 'rbxasset://textures/meshPartFallback.png'
				end
				MeshPartMesh.Scale = obj.Size
			end
		end
		for i = 1,AttributesLength do
			obj:SetAttribute(Values[Parse(ValueFMT)],Values[Parse(ValueFMT)])
		end
		if not Parent then
			table.insert(NoParent,obj)
		else
			obj.Parent = Parent
		end
	end

	local ConnectionsLength = Parse(ConnectionFMT)
	for i = 1,ConnectionsLength do
		local a,b,c = Parse(InstanceFMT),Parse(ValueFMT),Parse(InstanceFMT)
		Instances[a][Values[b]] = Instances[c]
	end

	return NoParent
end


local Objects = Decode('AABKIQlTY3JlZW5HdWkhDlpJbmRleEJlaGF2aW9yAwAAAAAAAPA/IQlUZXh0TGFiZWwhC0FuY2hvclBvaW50CwAAAD8AAAA/IRBCYWNrZ3JvdW5kQ29sb3IzBv///yEWQmFja2dyb3VuZFRyYW5zcGFyZW5jeQMAAACgmZnpPyEMQm9yZGVyQ29sb3IzBgAAACEPQm9y'
	..'ZGVyU2l6ZVBpeGVsAwAAAAAAAAAAIQhQb3NpdGlvbgyOwGE/AACceng/AAAhBFNpemUMydVxPgAAE4BoPQAAIQRGb250AwAAAAAAgERAIQpUZXh0Q29sb3IzIQpUZXh0U2NhbGVkIiEIVGV4dFNpemUDAAAAAAAANEAhFlRleHRTdHJva2VUcmFuc3BhcmVuY3khC1Rl'
	..'eHRXcmFwcGVkIQ5UZXh0WEFsaWdubWVudCEOVGV4dFlBbGlnbm1lbnQDAAAAAAAAAEAhBUZyYW1lDEQsbD8AAGsoZD8AAAw8ux0+AAAE49A9AAAhDFVJTGlzdExheW91dCEJU29ydE9yZGVyDAAAgD8AAAAAAAAKAAMAAAAAAAAIQCEEVGV4dCEFTWlkaXMDAAAAAAAA'
	..'LkAhDlNjcm9sbGluZ0ZyYW1lIQZBY3RpdmUMAAAAAAAAfDf8PQAADAAAgD8AAL7+Yj8AACETQXV0b21hdGljQ2FudmFzU2l6ZSELQm90dG9tSW1hZ2UhL3JieGFzc2V0Oi8vdGV4dHVyZXMvdWkvU2Nyb2xsL3Njcm9sbC1taWRkbGUucG5nIQpDYW52YXNTaXplDAAA'
	..'AAAAAAAAAAAAACESU2Nyb2xsQmFyVGhpY2tuZXNzAwAAAAAAABRAIQhUb3BJbWFnZSEKVGV4dEJ1dHRvbiEETmFtZSEEVGVtcAwAAIA/AAAAAAAAFAAhB1Zpc2libGUCAwAAAAAAACxAIQhjb21tYW5kcwydg0w/AABrKGQ/AAAMNHinPQAABOPQPQAADERakD0AAAAA'
	..'AAAAAAwAAIA/AAAAAIA/AAAhBFN0b3AhB1JlZnJlc2ghB1RleHRCb3ghBlZvbHVtZSERUGxhY2Vob2xkZXJDb2xvcjMhD1BsYWNlaG9sZGVyVGV4dCEJVm9sdW1lOiAxIQAhBkxvb3BlZCEMTG9vcGVkOiB0cnVlDwEAAQACAwQBDwAFBgcICQoLDA0ODxAREhMUFQgW'
	..'FxgZGg4bFxwDHR4fAQcABQYHCAkKCwwNDg8gESEiAwEAIx4EAwwABwgJAwsMDQ4RJBMlJicVCBgoGg4bFxwDKQMMACoXBwgJAwsMDQ4PKxEsLR4uLzAxMjM0LyIGAAA1AQ4ANjcHCAkDCwwNDhE4OToTJRUIFhcYOxoOGxccAx8BCAA2PAUGBwgJAwsMDQ4PPRE+KQkM'
	..'ACoXBwgJCgsMDQ4PPxFALR4uLzAxMjM0LyIKAQAjHjUKDgA2QQcICQMLDA0OETgTJSZBFQgWFxg7Gg4bFxwDNQoOADZCBwgJAwsMDQ4ROBMlJkIVCBYXGDsaDhsXHANDChAANkQHCAkDCwwNDhE4EyVFCEZHJkgVCBYXGDsaDhsXHAM1Cg4ANkkHCAkDCwwNDhE4EyUm'
	..'ShUIFhcYOxoOGxccAwA=')
ui = Objects[1]
ui.Parent = owner:FindFirstChildOfClass("PlayerGui")

local remfunc = Instance.new("RemoteFunction", NLS([[
local owner = game:GetService("Players").LocalPlayer
local remfunc = script:WaitForChild("Invoke")

local ui = script.Parent
ui.Parent = owner:FindFirstChild("PlayerGui")
local txt = ui.TextLabel
txt.Text = "Preloading"

function doHttpGet(link, headers)
	return remfunc:InvokeServer("HttpGet", {url = link, headers = headers})
end

function doS2T(s)
	return remfunc:InvokeServer("String2Table", s)
end

function getData(songname)
	local success, json = pcall(doHttpGet, "https://raw.githubusercontent.com/TheFakeFew/ClientMidi/main/Midis/"..songname)
	if(not success)then return nil end
	return game:GetService("HttpService"):JSONDecode(json)
end

local families = doS2T(doHttpGet("https://raw.githubusercontent.com/TheFakeFew/ClientMidi/main/Core/Families.lua"))
local threads = {}

local preload = {}
local preloadnames = {}

for i, v in next, families do
	local s = Instance.new("Sound", workspace)
	s.SoundId = v.id
	preloadnames[v.id] = i
	table.insert(preload, s)
end

local alreadypreloaded = {}
game:GetService("ContentProvider"):PreloadAsync(preload, function(content)
	if(alreadypreloaded[content])then return end
	alreadypreloaded[content] = true 
	print("preloaded "..preloadnames[content] or "?")
end)

for i, v in next, preload do
	pcall(game.Destroy, v)
end
table.clear(alreadypreloaded)
table.clear(preload)
table.clear(preloadnames)

local volume = 1
local looped = true
local currentSong = ""
local notenum = 0
local numofnotes = 0

function updateUI(note, maxnotes)
	local notesleft = (maxnotes - note)
	
	local leftratio = notesleft/maxnotes
	local doneratio = (maxnotes - notesleft)/maxnotes
	
	local mult = 30
	
	txt.Text = "Track: "..currentSong.." ; Instances: "..#ui:GetChildren()-3 .."\n"..note.."/"..maxnotes.." ["..string.rep("/", doneratio*mult)..string.rep(" ", leftratio*mult).."]"
	ui.commands.ScrollingFrame.Volume.PlaceholderText = "Volume: "..volume
	ui.commands.ScrollingFrame.Looped.Text = "Looped: "..tostring(looped)
end

function registermidis()
	local data = game:GetService("HttpService"):JSONDecode(doHttpGet("https://api.github.com/repos/TheFakeFew/ClientMidi/contents/Midis", {
		["Accept"] = "application/vnd.github+json",
		["Authorization"] = "Bearer ghu_2lFuZ53pXjtCVq3DVpMvcozAamqa8m2MjVBn",
		["X-GitHub-Api-Version"] = "2022-11-28"
	}))

	for i, v in next, data do
		local t = ui.Temp:Clone()
		t.Parent = ui.Frame.ScrollingFrame
		t.Name = v.name
		t.Text = v.name.."   "
		t.Visible = true
		t.MouseButton1Click:Connect(function()
			playsong(t.Name)
		end)
	end
end
registermidis()

function notetopitch(note, offset)
	return (440 / 32) * math.pow(2, ((note + offset) / 12)) / 440
end

function play(tracks)
	notenum = 0
	numofnotes = 0
	
	for i,v in next, tracks do
		numofnotes = numofnotes + #v.notes
	end
	
	for i,v in next, tracks do
		local id = families[v.instrument.name] or families["acoustic grand piano"]
		for i,v in next, v.notes do
			local thread = task.delay(v.time, function()
				notenum = notenum + 1
				updateUI(notenum, numofnotes)
				
				local settings = id.settings
				local snd = Instance.new("Sound")
				snd.Volume = (v.velocity + (settings["Gain"] or 0)) * volume
				snd.SoundId = id.pitches[v.midi] or id.id
				snd.Looped = not not settings["Loop"]
				snd.Pitch = notetopitch(v.midi, settings["Offset"] or 0)
				snd.Name = v.name
				snd.Parent = ui
				snd:Play()
				
				task.delay(v.duration, function()
					local tw = game:GetService("TweenService"):Create(snd, TweenInfo.new(.3), {Volume = 0})
					tw:Play()
					tw.Completed:Wait()
					
					pcall(game.Destroy, snd)
					pcall(game.Destroy, tw)
				end)
				
			end)
			table.insert(threads,thread)
		end
	end
	
	loop(tracks)
end

function loop(tracks)
	if(not looped)then return end
	
	local songtime = 0
	for i,v in next, tracks do
		for i,v in next, v.notes do
			if((v.time+v.duration) > songtime)then
				songtime = v.time+v.duration
			end
		end
	end
	
	local thread = task.delay(songtime, function()
		if(not looped)then return end
		stopall()
		
		play(tracks)
		loop(tracks)
	end)
	table.insert(threads, thread)
end

function stopall()
	for i, v in next, threads do
		pcall(task.cancel, v)
	end
	table.clear(threads)
	
	for i, v in next, ui:GetChildren() do
		if(v:IsA("Sound"))then
			pcall(game.Destroy, v)
		end
	end
end

local songcache = {}

function playsong(name)
	stopsong()
	
	local data = songcache[name] or getData(name)
	if(not data)then
		return print("Song doesnt exist.")
	end
	print("loaded "..name)
	currentSong = name
	songcache[name] = data
	
	local tracks = data.tracks
	play(tracks)	
end

function stopsong()
	stopall()
	
	notenum = 0
	numofnotes = 0
	currentSong = "None"
end

playsong("Roblox_Theme.json")

game:GetService("RunService").RenderStepped:Connect(function()
	updateUI(notenum, numofnotes)
end)

ui.commands.ScrollingFrame.Stop.MouseButton1Click:Connect(stopsong)
ui.commands.ScrollingFrame.Refresh.MouseButton1Click:Connect(function()
	for i, v in next, ui.Frame.ScrollingFrame:GetChildren() do
		if(not v:IsA("UIListLayout"))then
			pcall(game.Destroy, v)
		end
	end
	registermidis()
	table.clear(songcache)
end)
ui.commands.ScrollingFrame.Looped.MouseButton1Click:Connect(function()
	looped = not looped
end)
ui.commands.ScrollingFrame.Volume.FocusLost:Connect(function(ep)
	if(not ep)then return end
	volume = tonumber(ui.commands.ScrollingFrame.Volume.Text)
	ui.commands.ScrollingFrame.Volume.Text = ""
end)
]], ui))
remfunc.Name = "Invoke"

remfunc.OnServerInvoke = function(player, type, data)
	if(player ~= owner)then
		return
	end

	if(type == "HttpGet")then
		return game:GetService("HttpService"):GetAsync(data.url, true, data.headers)

	elseif(type == "String2Table")then
		return loadstring(data)()

	end
end

owner.Chatted:Connect(function(message)
	remfunc:InvokeClient(owner, "Message", message)
end)