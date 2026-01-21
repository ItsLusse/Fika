Fika = CreateFrame("frame")
Fika.Import = CreateFrame("Frame","FI",UIParent)
Fika.Export = CreateFrame("Frame","FE",UIParent)
Fika.Roster = CreateFrame("Frame","FR",UIParent)
Fika.Invite = CreateFrame("Frame","FINV",UIParent)
Fika.WantsInvite = CreateFrame("Frame","FWINV",UIParent)
Fika.Options = CreateFrame("Frame","FO",UIParent)

tinsert(UISpecialFrames, "FI")
tinsert(UISpecialFrames, "FE")
tinsert(UISpecialFrames, "FR")
tinsert(UISpecialFrames, "FINV")
--tinsert(UISpecialFrames, "RWINV")
tinsert(UISpecialFrames, "FO")

-- Version from .toc file 
FIKA_VERSION = GetAddOnMetadata("Fika", "Version") -- Grab version from .toc

Fika:RegisterEvent("ADDON_LOADED")
Fika:RegisterEvent("RAID_ROSTER_UPDATE")
Fika:RegisterEvent("CHAT_MSG_SYSTEM")
Fika:RegisterEvent("CHAT_MSG_GUILD")
Fika:RegisterEvent("CHAT_MSG_WHISPER")

-- Timer
local timerFrame = CreateFrame("Frame")
local startTime = nil
local lastTick = 0
local delay = 1
local isEventActive = false

local pingdelay = GetTime()


local inviteTimerFrame = nil
local inviteTimerRunning = false

-- Tables
FIKA_Roster = FIKA_Roster or {}
FIKA_Assist = FIKA_Assist or {}
FIKA_Preraid = FIKA_Preraid or {}

FIKA_NotInRoster = {}

FIKA_Settings = FIKA_Settings or {}

local function Default()
    if FIKA_Roster == nil then
        FIKA_Roster = {}
    end

	if FIKA_Assist == nil then
        FIKA_Assist = {}
    end

	if FIKA_Preraid == nil then
        FIKA_Preraid = {}
    end

	if FIKA_Settings == nil then
        FIKA_Settings = {}
    end
end

local function print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffF.|cffffff00I.K.|cff00ccffA|r: "..msg)
end

local function GetClassColorForName(class)
	if class == "Warrior" then return "|cffC79C6E"
	elseif class == "Hunter" then return "|cffABD473"
	elseif class == "Mage" then return "|cff69CCFF"
	elseif class == "Rogue" then return "|cffFFF569"
	elseif class == "Warlock" then return "|cff9482C9"
	elseif class == "Druid" then return "|cffFF7D0A"
	elseif class == "Shaman" then return "|cff0070DD"
	elseif class == "Priest" then return "|cffFFFFFF"
	elseif class == "Paladin" then return "|cffF58CBA"
	end
end

local function strSplit(str, delimiter)
    if not str then return nil end
    delimiter = delimiter or ":"
    local fields = {}
    local pattern = string.format("([^%s]+)", delimiter)

    string.gsub(str, pattern, function(c)
        local noSpaces = string.gsub(c, " ", "")
        table.insert(fields, noSpaces)
    end)

    return fields
end

local function ClearRoster()
	FIKA_Roster = {}
    print("|cffffff00The roster has been cleared|r.")
	
	if not Fika.Roster.GroupMembers then Fika.Roster.GroupMembers = {} end

	for group = 1, 8 do
		for i = 1, 5 do
			Fika.Roster.GroupMembers[group][i]:SetText("|cffff0000---|r")
		end
	end
end

local function TruncateColoredText(text, maxVisible)
	if not text or text == "" then
		return ""
	end

	local i = 1
	local visible = 0
	local output = {}
	local colorStack = {}
	local truncated = false

	while i <= string.len(text) do
		local c = string.sub(text, i, i)

		if c == "|" then
			local next2 = string.sub(text, i, i + 1)
			if next2 == "|c" then
				local colorCode = string.sub(text, i, i + 9)
				table.insert(output, colorCode)
				table.insert(colorStack, "|r")
				i = i + 10
			elseif next2 == "|r" then
				table.insert(output, "|r")
				if table.getn(colorStack) > 0 then
					table.remove(colorStack)
				end
				i = i + 2
			else
				table.insert(output, c)
				visible = visible + 1
				i = i + 1
			end
		else
			table.insert(output, c)
			visible = visible + 1
			i = i + 1
		end

		if visible >= maxVisible then
			truncated = (i < string.len(text))
			break
		end
	end

	-- Only add truncation marker if actually longer
	if truncated then
		table.insert(output, "..")
	end

	-- Properly close all open color tags
	for j = 1, table.getn(colorStack) do
		table.insert(output, "|r")
	end

	return table.concat(output)
end

local function UpdateRoster()
    local raidMembers = {}
    local numRaidMembers = GetNumRaidMembers()

    local subgroupPlayers = {}
    for g = 1, 8 do
        subgroupPlayers[g] = {}
    end

    for i = 1, numRaidMembers do
        local name, _, subgroup, _, class, _, _, online, isDead = GetRaidRosterInfo(i)
        if name and class then
            raidMembers[name] = {
                class = class,
                online = online,
                group = subgroup,
				dead = isDead,
            }
            if subgroup and subgroup >= 1 and subgroup <= 8 then
                table.insert(subgroupPlayers[subgroup], name)
            end
        end
    end

    local groupsWithFreeSlot = {}
    local plannedCounts = {}

    for g = 1, 8 do
        local count = 0
        local roster = FIKA_Roster[g] or {}
        for i = 1, 5 do
            if roster[i] then
                count = count + 1
            end
        end
        plannedCounts[g] = count
        if count < 5 then
            table.insert(groupsWithFreeSlot, g)
        end
    end

    for g = 1, 8 do
        local roster = FIKA_Roster[g] or {}

        local actualCount = 0
        for _, name in ipairs(subgroupPlayers[g]) do
            actualCount = actualCount + 1
        end
        local plannedcount = plannedCounts[g]

        if actualCount > plannedcount then

            if plannedcount >= 5 then

                for _, playerName in ipairs(subgroupPlayers[g]) do
                    local isPlanned = false
                    for i = 1, 5 do
                        if roster[i] == playerName then
                            isPlanned = true
                            break
                        end
                    end
                    if not isPlanned then

                        if table.getn(groupsWithFreeSlot) > 0 then
                            local targetGroup = groupsWithFreeSlot[1]

                            local idx = nil

                            for i = 1, numRaidMembers do
                                local nm, _, _, _, _, _, _, _ = GetRaidRosterInfo(i)
                                if nm == playerName then
                                    idx = i
                                    break
                                end
                            end
                            if idx then
                                SetRaidSubgroup(idx, targetGroup)

                                local removeIndex = nil
                                for ii, nm in ipairs(subgroupPlayers[g]) do
                                    if nm == playerName then
                                        removeIndex = ii
                                        break
                                    end
                                end
                                if removeIndex then
                                    table.remove(subgroupPlayers[g], removeIndex)
                                end

                                table.insert(subgroupPlayers[targetGroup], playerName)

                                plannedCounts[targetGroup] = plannedCounts[targetGroup]

                                if plannedCounts[targetGroup] + 1 >= 5 then

                                    for ii, gv in ipairs(groupsWithFreeSlot) do
                                        if gv == targetGroup then
                                            table.remove(groupsWithFreeSlot, ii)
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for group = 1, 8 do
        local plannedRoster = FIKA_Roster[group] or {}
        local fontStrings = Fika.Roster.GroupMembers[group]
        local actualPlayers = subgroupPlayers[group] or {}

        local unplannedPlayers = {}
        for _, pname in ipairs(actualPlayers) do
            local found = false
            for _, plannedName in ipairs(plannedRoster) do
                if pname == plannedName then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(unplannedPlayers, pname)
            end
        end

        local plannedCount = 0
        for i = 1, 5 do
            if plannedRoster[i] then
                plannedCount = plannedCount + 1
            end
        end

        local freeSlots = 5 - plannedCount
        local unplannedIndex = 1
        local plannedUnplannedPairs = {}

        local function isPlannedNameInRaid(name)
            return raidMembers[name] ~= nil
        end

        if plannedCount + table.getn(unplannedPlayers) > 5 then
            local extraCount = (plannedCount + table.getn(unplannedPlayers)) - 5
            for i = 1, plannedCount do
                local pnm = plannedRoster[i]
                if not isPlannedNameInRaid(pnm) then
                    if unplannedIndex <= table.getn(unplannedPlayers) and extraCount > 0 then
                        plannedUnplannedPairs[i] = unplannedPlayers[unplannedIndex]
                        unplannedIndex = unplannedIndex + 1
                        extraCount = extraCount - 1
                    end
                end
            end
        end

        for i = 1, 5 do
            local fontString = fontStrings[i]
            if fontString then
                local pnm = plannedRoster[i]
                local txt
                if pnm then
                    local info = raidMembers[pnm]
                    local ccol = info and GetClassColorForName(info.class) or "|cff888888"
                    txt = ccol..pnm.."|r"
                    if info then
                        if not info.online then
                            txt = txt.." - |cffff0000Off|r"
                        end
                        if info.group ~= group then
                            txt = "|cffffff00("..info.group..")|r - "..txt
                        end
						if info.dead then
                            txt = txt.." - |cffff0000Dead|r"
                        end
                    end
                    if plannedUnplannedPairs[i] then
                        local un = plannedUnplannedPairs[i]
                        local uinfo = raidMembers[un]
                        local ucol = uinfo and GetClassColorForName(uinfo.class) or "|cff888888"
                        local utext = ucol..un.."|r"
                        if uinfo then
                            if not uinfo.online then
                                utext = utext.." - |cffff0000Off|r"
                            end
                            if uinfo.group ~= group then
                                utext = "|cffffff00("..uinfo.group..")|r - "..utext
                            end
							if uinfo.dead then
                            	utext = utext.." - |cffff0000Dead|r"
                        	end
                        end
                        txt = txt.." |cffffff00| |r"..utext
                    end
                else

                    if unplannedIndex <= table.getn(unplannedPlayers) and freeSlots > 0 then
                        local un = unplannedPlayers[unplannedIndex]
                        unplannedIndex = unplannedIndex + 1
                        freeSlots = freeSlots - 1
                        local uinfo = raidMembers[un]
                        local ucol = uinfo and GetClassColorForName(uinfo.class) or "|cff888888"
                        txt = "|cffff0000---|r "..ucol..un.."|r"
                        if uinfo then
                            if not uinfo.online then
                                txt = txt.." - |cffff0000Off|r"
                            end
                            if uinfo.group ~= group then
                                txt = "|cffffff00("..uinfo.group..")|r - "..txt
                            end
							if uinfo.dead then
                                txt = "|cffffff00("..uinfo.group..")|r - "..txt
                            end
                        end
                    else
                        txt = "|cffff0000---|r"
                    end
                end

                if fontString:GetText() ~= txt then
					fontString:SetText(TruncateColoredText(txt, 19))
                end
            end

			-- Button
			local btn = Fika.Roster.GroupButtons[group] and Fika.Roster.GroupButtons[group][i]
			if btn then
				if plannedRoster[i] then
					btn:Show()
				else
					btn:Hide()
				end
			end
        end
    end
end

local function ImportRoster(str)
	local names = strSplit(str, ",")

	local count = 0
	local totalcount = 0
	local duplicates = 0

	for _, name in ipairs(names) do
		local group = tonumber(string.sub(name, 1, 1))
		local playerName = string.sub(name, 2)
		playerName = string.lower(playerName)
		playerName = string.gsub(playerName, "^%l", string.upper)

		if group and playerName ~= "" then
			if not FIKA_Roster[group] then
				FIKA_Roster[group] = {}
			end

			local existingGroup = nil

			for groupNum = 1, 8 do
				local groupTable = FIKA_Roster[groupNum]
				if groupTable then
					for index, existingName in ipairs(groupTable) do
						if existingName == playerName then
							existingGroup = groupNum

							if groupNum ~= group then
								table.remove(groupTable, index)
							end

							break
						end
					end
				end
			end

			if existingGroup == group then
				duplicates = duplicates + 1
			else

				local groupSize = 0
				for _ in ipairs(FIKA_Roster[group]) do
					groupSize = groupSize + 1
				end

				if groupSize < 5 then
					table.insert(FIKA_Roster[group], playerName)
					count = count + 1
				else
					print("|cffff0000Import failed|r: Group "..group.." is full. Skipping "..playerName..".")
				end
			end
		end
	end

	if count == 0 then
		if duplicates > 0 then
			print("|cffff0000Import failed|r: "..duplicates.." duplicate name(s) found.")
		else
			print("|cffff0000Imported|r: 0 player.")
		end
	elseif count == 1 then
		print("|cff00ff00Added|r: 1 player.")
	else
		print("|cff00ff00Added|r: "..count.." players.")
	end

	for group, players in pairs(FIKA_Roster) do
		for _ in ipairs(players) do
			totalcount = totalcount + 1
		end
	end

	print("|cff00ccffTotal players in the roster|r: "..totalcount)

	UpdateRoster()
end

local function ImportFromRaid()
	ClearRoster()

	local count = 0
	local totalcount = 0

	for i = 1, GetNumRaidMembers() do
		local name, _, group, _, _, _, _, _, _, _, _ = GetRaidRosterInfo(i)
		if name and group then
			if not FIKA_Roster[group] then
				FIKA_Roster[group] = {}
			end

			local alreadyExists = false
			for _, existingName in ipairs(FIKA_Roster[group]) do
				if existingName == name then
					alreadyExists = true
					break
				end
			end

			if not alreadyExists then
				table.insert(FIKA_Roster[group], name)
				count = count + 1
			end
		end
	end

	for _, group in pairs(FIKA_Roster) do
		for _ in ipairs(group) do
			totalcount = totalcount + 1
		end
	end

	if count == 0 then
		print("|cffff0000Imported|r: 0 players from the raid.")
	elseif count == 1 then
		print("|cff00ff00Added|r: 1 player from the raid.")
	else
		print("|cff00ff00Added|r: "..count.." players from the raid.")
	end

	print("|cff00ccffTotal players in the roster|r: "..totalcount)

	UpdateRoster()
end

local function RemoveFromRoster(str)
	local names = strSplit(str, ",")
	local removed = 0
	local notFound = 0
	local totalcount = 0

	for _, name in ipairs(names) do
		local group = tonumber(string.sub(name, 1, 1))
		local playerName

		if group then
			playerName = string.sub(name, 2)
		else
			playerName = name
		end

		playerName = string.lower(playerName)
		playerName = string.gsub(playerName, "^%l", string.upper)

		if playerName ~= "" then
			local found = false

			for groupNum = 1, 8 do
				local groupTable = FIKA_Roster[groupNum]
				if groupTable then
					local newGroup = {}

					for i, existingName in ipairs(groupTable) do
						if existingName ~= playerName then
							table.insert(newGroup, existingName)
						else
							found = true
							removed = removed + 1
						end
					end
					FIKA_Roster[groupNum] = newGroup
				end
			end

			if not found then
				notFound = notFound + 1
			end
		end
	end

	if removed == 1 then
		print("|cffff0000Removed|r: "..removed.." player.")
	elseif removed > 1 then
		print("|cffff0000Removed|r: "..removed.." players.")
	else
		print("|cffff0000Removed|r: 0 players.")
	end

	if notFound == 1 then
		print("|cffffff00Not found|r: "..notFound.." player.")
	elseif notFound > 1 then
		print("|cffffff00Not found|r: "..notFound.." player(s).")
	end

	for group, players in pairs(FIKA_Roster) do
		for _ in ipairs(players) do
			totalcount = totalcount + 1
		end
	end

	print("|cff00ccffTotal players in the roster|r: "..totalcount)

	UpdateRoster()
end

local function RaidInfo()

	local locationMessage = GetZoneText().."."
	if GetSubZoneText() ~= "" then
		locationMessage = GetZoneText().." - "..GetSubZoneText().."."
	end

	local raidSize = GetNumRaidMembers()

	local message = "Raid Info: "..raidSize.." players in the raidgroup.\nCurrent location: "..locationMessage

	return message
end


local function GetGuildRankName()
	local AssistRankName = "Undefined"
	local PreraidRankName = "Undefined"

	GuildRoster()
	if FIKA_Settings["assistrank"] == nil then
		FIKA_Settings["assistrank"] = "1"
		AssistRankName = GuildControlGetRankName(FIKA_Settings["assistrank"])
	else
		AssistRankName = GuildControlGetRankName(FIKA_Settings["assistrank"])
	end

	if FIKA_Settings["preraidrank"] == nil then
		FIKA_Settings["preraidrank"] = "1"
		PreraidRankName = GuildControlGetRankName(FIKA_Settings["preraidrank"])
	else
		PreraidRankName = GuildControlGetRankName(FIKA_Settings["preraidrank"])
	end

	return tostring(PreraidRankName), tostring(AssistRankName)
end

local function Plus(arg1, arg2, from)
    if FIKA_Settings["inv"] == true then
        local msg = arg1
        local sender = arg2

        if msg == FIKA_Settings["keyword"] then
            local raidMembers = {}
			local raidCount = 0

            for i = 1, GetNumRaidMembers() do
                local name = GetRaidRosterInfo(i)
                if name then
                    raidMembers[name] = true
					raidCount = raidCount + 1
                end
            end

			local isRosterEmpty = true
			for _, _ in pairs(FIKA_Roster) do
				isRosterEmpty = false
				break
			end

			if isRosterEmpty then
				if raidCount < 40 then
					InviteByName(sender)
					SendChatMessage("Inviting.", "WHISPER", nil, sender)
				else
					if from == "Guild" then
						SendChatMessage("Raidgroup is currently full.", "GUILD")
					elseif from == "Whisper" then
						SendChatMessage("Raidgroup is currently full.", "WHISPER", nil, sender)
					end
				end
				return
			end

            local rosterLookup = {}
            for group, players in pairs(FIKA_Roster) do
                for _, playerName in ipairs(players) do
                    rosterLookup[playerName] = true
                end
            end

            if not raidMembers[sender] then
                if rosterLookup[sender] then
					if raidCount < 40 then
						InviteByName(sender)
						SendChatMessage("Inviting.", "WHISPER", nil, sender)
					else
						table.insert(FIKA_NotInRoster, sender)
						Fika.WantsInvite:UpdateScrollList()
						Fika.WantsInvite:Show()

						if from == "Guild" then
							SendChatMessage("Raidgroup is currently full.", "GUILD")
						elseif from == "Whisper" then
							SendChatMessage("Raidgroup is currently full.", "WHISPER", nil, sender)
						end
					end
                else
					if raidCount > 39 then
						if from == "Guild" then
							SendChatMessage("Raidgroup is currently full.", "GUILD")
						elseif from == "Whisper" then
							SendChatMessage("Raidgroup is currently full.", "WHISPER", nil, sender)
						end
					end
					local found = false
					for _, plannedName in ipairs(FIKA_NotInRoster) do
						if sender == plannedName then
							found = true
							break
						end
					end
					if not found then
						SendChatMessage("You are not on the roster, adding you to the waitlist.", "WHISPER", nil, sender)
						table.insert(FIKA_NotInRoster, sender)
						Fika.WantsInvite:UpdateScrollList()
						Fika.WantsInvite:Show()
					end
                end
            end
        end
    end
end

local function OfficerRoster()
    local Officers = {}
    local Classleaders = {}
 
    if not FIKA_Roster then
        return Officers, Classleaders
    end

    local nameSet = {}
    for group, nameList in pairs(FIKA_Roster) do
        for _, name in ipairs(nameList) do
            nameSet[name] = true
        end
    end

	GuildRoster()
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and nameSet[name] then
            if rankIndex < tonumber(FIKA_Settings["assistrank"]) then
                table.insert(Officers, name)
            end
            if rankIndex < tonumber(FIKA_Settings["preraidrank"]) then
                table.insert(Classleaders, name)
            end
        end
    end

    return Officers, Classleaders
end

local function SquadMember(squadName, listTable, name)
    if not name or name == "" then
		local lines = {}

		if listTable then
			GuildRoster()
			for _, n in ipairs(listTable) do
				local found = false
				for i = 1, GetNumGuildMembers() do
					local Charname, _, _, _, Charclass = GetGuildRosterInfo(i)
					if Charname == n then
						local Coloredname = GetClassColorForName(Charclass)..Charname.."|r"
						table.insert(lines, Coloredname)
						found = true
						break
					end
				end
				if not found then
					table.insert(lines, n) -- just plain name
				end
			end
		end

		local names = table.concat(lines, ", ")
		if names == "" then
			print("|cffffff00"..squadName.." Squad|r - |cffff0000Empty|r")
		else
			print("|cffffff00"..squadName.." Squad|r - "..names)
		end
		return
	end

    if not listTable then
        listTable = {}
        if squadName == "Preraid" then
            FIKA_Preraid = listTable
        elseif squadName == "Assist" then
            FIKA_Assist = listTable
        end
    end

    for index, existingName in ipairs(listTable) do
        if existingName == name then
			print("|cffff0000Removed from "..squadName.."|r: "..name)
			table.remove(listTable, index)
            return
        end
    end

	name = string.lower(name)
    name = string.gsub(name, "^%l", string.upper)

	table.insert(listTable, name)
    table.sort(listTable, function(a, b)
        return a < b
    end)
	print("|cff00ff00Added to "..squadName.."|r: "..name)
end

local function InviteRoster()
	if UnitName("party1") then
		if not GetRaidRosterInfo(1) then
			ConvertToRaid()
		end
	end

	local roster = FIKA_Roster
    if IsShiftKeyDown() and FIKA_Preraid then
        roster = FIKA_Preraid
    end

	local normalizedRoster = {}

    if type(roster[1]) == "string" then
        normalizedRoster[1] = roster
    else
        normalizedRoster = roster
    end

	for group, players in pairs(normalizedRoster) do
		for _, playerName in ipairs(players) do
			if playerName ~= UnitName("player") then
				local inRaid = false

				for i = 1, GetNumRaidMembers() do
					local raidName = GetRaidRosterInfo(i)
					if raidName == playerName then
						inRaid = true
						break
					end
				end

				if not inRaid then
					InviteByName(playerName)
				end
			end
		end
	end
end

local function StartTimer()
	if isEventActive then return end

	local totalDuration = 10 -- 10 sec
	startTime = GetTime()
	lastTick = startTime
	isEventActive = true

	Fika.Invite.TimerText:Show()
	Fika.Invite.TimerText:SetText(totalDuration)

	timerFrame:SetScript("OnUpdate", function()
    local now = GetTime()

		if now - lastTick >= delay then
			local elapsed = math.floor(now - startTime)
			local remaining = math.max(totalDuration - elapsed, 0)

			Fika.Invite.TimerText:SetText(tostring(remaining))

			lastTick = now

			if remaining <= 0 then
				Fika.Invite.StartTimerButton:SetText("Invite in 10 sec")
				Fika.Invite.TimerText:SetText("")
				Fika.Invite.TimerText:Hide()
				timerFrame:SetScript("OnUpdate", nil)
				isEventActive = false
			end
		end
	end)
end

local function StopTimer()
	timerFrame:SetScript("OnUpdate", nil)
	startTime = nil
	lastTick = 0
	isEventActive = false
	Fika.Invite.TimerText:SetText("")
	Fika.Invite.TimerText:Hide()
end

local function InviteTimer_OnClick()
	if inviteTimerRunning then
		StopTimer()
		inviteTimerFrame:SetScript("OnUpdate", nil)
		inviteTimerFrame = nil
		inviteTimerRunning = false
		Fika.Invite.StartTimerButton:SetText("Invite in 10 sec")
	else
		StartTimer()
		inviteTimerFrame = CreateFrame("Frame")
		inviteTimerFrame.elapsed = 0
		inviteTimerFrame.period = 1
		inviteTimerFrame.step = 0
		inviteTimerRunning = true
		Fika.Invite.StartTimerButton:SetText("Cancel invites")

		inviteTimerFrame:SetScript("OnUpdate", function()
			local arg1 = arg1 or 0
			inviteTimerFrame.elapsed = inviteTimerFrame.elapsed + arg1

			if inviteTimerFrame.elapsed >= inviteTimerFrame.period or inviteTimerFrame.step == 0 then
				local step = inviteTimerFrame.step

				if step == 0 then
					if FIKA_Settings["guild"] == true then
						SendChatMessage("Raid invites in 10 seconds!", "GUILD")
					end
				elseif step == 8 then
					if UnitName("party1") then
						if not GetRaidRosterInfo(1) then
							ConvertToRaid()
							print("|cffffff00Converted to Raidgroup.|r")
						end
					end

				elseif step > 10 then
					InviteRoster()
					FIKA_Settings["inv"] = true
					Fika.Roster.InvCheckbox:SetChecked(FIKA_Settings["inv"])
					Fika.WantsInvite:Show()

					inviteTimerFrame:SetScript("OnUpdate", nil)
					inviteTimerFrame = nil
					inviteTimerRunning = false
					return
				end

				inviteTimerFrame.step = step + 1
				inviteTimerFrame.elapsed = 0
			end
		end)
	end
end

local function SortGroups()
    local raidLookup = {}
    local listedPlayers = {}

    for raidIndex = 1, GetNumRaidMembers() do
        local name, _, subgroup = GetRaidRosterInfo(raidIndex)
        if name then
            raidLookup[name] = {
                index = raidIndex,
                currentGroup = subgroup
            }
        end
    end

    local groupCounts = {}
    for targetGroup = 1, 8 do
        groupCounts[targetGroup] = 0
        local group = FIKA_Roster[targetGroup] or {}

        local plannedCount = 0
        for i = 1, 5 do
            if group[i] then
                plannedCount = plannedCount + 1
            end
        end

        for i = 1, plannedCount do
            local name = group[i]
            listedPlayers[name] = true
            local info = raidLookup[name]
            if info and info.currentGroup ~= targetGroup then
                SetRaidSubgroup(info.index, targetGroup)
            end
            groupCounts[targetGroup] = groupCounts[targetGroup] + 1
        end
    end

    for _, info in pairs(raidLookup) do
        groupCounts[info.currentGroup] = (groupCounts[info.currentGroup] or 0) + 1
    end

    for name, info in pairs(raidLookup) do
        if not listedPlayers[name] then
            local currentGroup = info.currentGroup
            local plannedGroup = FIKA_Roster[currentGroup] or {}

            local plannedCount = 0
            for i = 1, 5 do
                if plannedGroup[i] then
                    plannedCount = plannedCount + 1
                end
            end

            if plannedCount > 0 then
                for targetGroup = 1, 8 do
                    local targetPlannedGroup = FIKA_Roster[targetGroup] or {}

                    local targetPlannedCount = 0
                    for i = 1, 5 do
                        if targetPlannedGroup[i] then
                            targetPlannedCount = targetPlannedCount + 1
                        end
                    end

                    local targetGroupCount = groupCounts[targetGroup] or 0

                    if targetPlannedCount < 5 and targetGroupCount < 5 then
                        if info.currentGroup ~= targetGroup then
                            SetRaidSubgroup(info.index, targetGroup)
                            groupCounts[targetGroup] = groupCounts[targetGroup] + 1
                            groupCounts[currentGroup] = groupCounts[currentGroup] - 1
                        end
                        break
                    end
                end
            end
        end
    end

    for name, info in pairs(raidLookup) do
        if not listedPlayers[name] then
            local currentGroupCount = groupCounts[info.currentGroup] or 0
            if currentGroupCount > 5 then
                for targetGroup = 1, 8 do
                    local targetGroupCount = groupCounts[targetGroup] or 0
                    if targetGroupCount < 5 then
                        if info.currentGroup ~= targetGroup then
                            SetRaidSubgroup(info.index, targetGroup)
                            groupCounts[targetGroup] = groupCounts[targetGroup] + 1
                            groupCounts[info.currentGroup] = groupCounts[info.currentGroup] - 1
                        end
                        break
                    end
                end
            end
        end
    end
end

local function CheckMissing()
    local raidMembers = {}

	local missingFound = false
	local rosterEmpty = true

	local showOffline = IsShiftKeyDown()
	local showDead = IsAltKeyDown()

    for i = 1, GetNumRaidMembers() do
        local name, _, _, _, _, _, _, online, isDead = GetRaidRosterInfo(i)
        if name then
            raidMembers[name] = {
                online = online,
				isDead = isDead
            }
        end

		if not online then
			if showOffline then
                SendChatMessage("|cffff0000Offline|r: "..name, "RAID")
                missingFound = true
            end
		end

		if isDead then
			if showDead then
				SendChatMessage("|cffff0000Dead|r: "..name, "RAID")
				missingFound = true
			end
		end
    end

    for groupNum = 1, 8 do
        local group = FIKA_Roster[groupNum]
        if group then
            rosterEmpty = false
            for _, name in ipairs(group) do
                local memberInfo = raidMembers[name]
                if not memberInfo then
					if not showOffline and not showDead then
						SendChatMessage("|cffffff00Missing|r: "..name.." (expected in group "..groupNum..")", "RAID")
						missingFound = true
					end
                end
            end
		end
    end

	if not showOffline and not showDead then
		local count = 0
		for i = 1, GetNumRaidMembers() do
			local name = GetRaidRosterInfo(i)
			if name then
				count = count +1
			end
		end

		if count > 0 and count < 40 then
			SendChatMessage("We are currently "..count.." players in the raidgroup.", "RAID")
		elseif count > 39 then
			SendChatMessage("Raidgroup is currently full.", "RAID")
		end
	end

    if not missingFound then
		if showDead then
			SendChatMessage("Everyone is |cff00ff00alive|r.", "RAID")
		elseif showOffline then
        	SendChatMessage("No players |cff00ff00offline|r.", "RAID")
		else
			SendChatMessage("No players |cff00ff00missing|r.", "RAID")
		end
		return
    end

	--if rosterEmpty then
    --    print("|cffffff00Roster is empty, none missing.|r")
    --end
end

local function CreateButton(parent, name, label, loc, x, y, width, height)
	local btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
	btn:SetPoint(loc, x, y)
	btn:SetWidth(width or 80)
	btn:SetHeight(height or 20)
	btn:SetFrameStrata("DIALOG")
	btn:SetText(label)

	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return btn 
end

local function ShowTooltip(owner, header, click, shift, alt)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(header, 1, 1, 1)
	GameTooltip:AddLine(click, 0.8, 0.8, 0.8)
	GameTooltip:AddLine(shift, 0.4, 1, 0.4)
	GameTooltip:AddLine(alt, 0.4, 1, 0.4)
	GameTooltip:Show()
end

function Fika:OnEvent()
	if event == "ADDON_LOADED" and arg1 == "Fika" then
		print("|cff00ff00Loaded!|r")
		print("'/fika |cffffff00help|r' - Show available commands")
        Default()
		Fika.Import:Gui()
		Fika.Export:Gui()
		Fika.Roster:Gui()
		Fika.Invite:Gui()
		Fika.WantsInvite:Gui()

		if FIKA_Settings["inv"] == true then
			Fika.WantsInvite:Show()
		end

		if FIKA_Settings["guild"] == true then
			Fika.Roster.GuildFrame:Show()
		end

		if FIKA_Settings["keyword"] == nil then
			FIKA_Settings["keyword"] = "+"
		end

	elseif event == "RAID_ROSTER_UPDATE" then
		UpdateRoster()
		
	elseif event == "CHAT_MSG_SYSTEM" then
		UpdateRoster()

		if string.find(arg1,"has come online") then
			GuildRoster()
		end

		if string.find(arg1,"You leave the group.") then
			FIKA_Settings["inv"] = false
			Fika.WantsInvite:Hide()
			Fika.Roster.InvCheckbox:SetChecked(FIKA_Settings["inv"])
		end

	elseif event == "CHAT_MSG_GUILD" then
		if arg2 ~= UnitName("player") then
			Plus(arg1,arg2,"Guild")
		end
	elseif event == "CHAT_MSG_WHISPER" then
		arg1 = string.lower(arg1)

		if arg2 ~= UnitName("player") then
			if string.find(arg1,FIKA_Settings["keyword"]) then
				Plus(arg1,arg2,"Whisper")
			elseif string.find(arg1,"raidinfo") then
				local count = 0
				for i = 1, GetNumRaidMembers() do
					local name = GetRaidRosterInfo(i)
					if name then
						count = count +1
					end
				end

				if count > 0 then
					SendChatMessage(RaidInfo(), "WHISPER", nil, arg2)
				end
			end
		end
	end
end

function Fika.Import:Gui()
	local backdrop = {
			edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
			bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
			tile="false",
			tileSize="32",
			edgeSize="32",
			insets={
				left="11",
				right="11",
				top="11",
				bottom="11"
			}
	}
	
	self:SetFrameStrata("BACKGROUND")
	self:SetWidth(320)
	self:SetHeight(110)
	self:SetPoint("CENTER",0,250)
	self:SetMovable(1)
	self:EnableMouse(1)
	self:RegisterForDrag("LeftButton")
	self:SetBackdrop(backdrop)
	self:SetBackdropColor(0,0,0,1)
	
	self.ImportHeader = self:CreateFontString(nil,"DIALOG")
	self.ImportHeader:SetPoint("TOP",0,-20)
	self.ImportHeader:SetFont("Fonts\\FRIZQT__.TTF", 12)
	self.ImportHeader:SetTextColor(1, 1, 1, 1)
	self.ImportHeader:SetShadowOffset(2,-2)
	self.ImportHeader:SetText("Import")
	
	-- ImportEditBox
	self.ImportEditBox = CreateFrame("EditBox","ImportEditBox",self,"InputBoxTemplate")
	self.ImportEditBox:SetFontObject("GameFontHighlight")
	self.ImportEditBox:SetFrameStrata("DIALOG")
	self.ImportEditBox:SetPoint("CENTER",0,5)
	self.ImportEditBox:SetWidth(220)
	self.ImportEditBox:SetHeight(30)
	self.ImportEditBox:SetAutoFocus(false)

	-- Add placeholder text with matching style
    local placeholderText = ImportEditBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    placeholderText:SetPoint("LEFT", ImportEditBox, "LEFT", 0, 0)  -- Adjusted left position for larger insets
    placeholderText:SetText("Example: 1Name, 5Name, 8Name…")
    placeholderText:SetTextColor(0.5, 0.5, 0.5, 0.7)

	self.ImportEditBox:SetScript("OnEnterPressed", function()
		self.ImportEditBox:ClearFocus()
		if ImportEditBox:GetText() ~= "" then
            placeholderText:Hide()
		else
			placeholderText:Show()
        end
	end)
	self.ImportEditBox:SetScript("OnChar", function()
		if ImportEditBox:GetText() ~= "" then
            placeholderText:Hide()
		else
			placeholderText:Show()
        end
    end)

	-- ClearButton
	self.ClearButton = CreateButton(self, "ClearButton", "Clear", "BOTTOM", -100, 15, 80)
	self.ClearButton:SetScript("OnEnter", function()
		ShowTooltip(self.ClearButton, "Clear Roster", "Click: Empty the roster", "Shift+Click: Import roster from current raid", "Alt+Click: Export current roster")
	end)
	self.ClearButton:SetScript("OnClick", function()
			if IsShiftKeyDown() then
				ImportFromRaid()

			elseif IsAltKeyDown() then
				if Fika.Export:IsVisible() then
					Fika.Export:Hide()
				else
					Fika.Export:Show()
					Fika.Import:Hide()
					Fika.Invite:Hide()

					local lines = {}

					for group = 1, 8 do
						if FIKA_Roster[group] then
							for _, name in ipairs(FIKA_Roster[group]) do
								table.insert(lines, name)
							end
						end
					end

					table.sort(lines, function(a, b)
						return a < b
					end)

					local exportText = table.concat(lines, "\n")
					Fika.Export.ExportEditBox:SetText(exportText)
				end
			else
				ClearRoster()
				UpdateRoster()
			end
		end)
	
	-- AddButton
	self.AddButton = CreateButton(self, "AddButton", "Add", "BOTTOM", 0, 15, 80)
	self.AddButton:SetScript("OnClick", function()
		local input = self.ImportEditBox:GetText()
		input = string.gsub(input, " ", "")
		input = string.gsub(input, "[^a-zA-Z1-8,]", "")

		if input == "" then
			print("|cffff0000Import failed|r: You must enter a group number (1–8) along with a character name.\nSeparate multiple entries with commas (,)\nExample: 1 Cliffholger, 1 Azzco, 4 Nochin")
			return
		end
		
		if not string.find(input, "^%d") then
			print("|cffff0000Import failed|r: Player 1 has not been assigned to a group.")
			return
		end
		if string.find(input, "%d%d+") then
			print("|cffff0000Import failed|r: One or more players are assigned to multiple groups.")
			return
		end
		if string.find(input, ",") then
			if not string.find(input, ",%d") then
				print("|cffff0000Import failed|r: All players must be assigned to a group.")
				return
			end
		end
		ImportRoster(input)
		self.ImportEditBox:ClearFocus()
	end)

	-- RemoveButton
	self.RemoveButton = CreateButton(self, "RemoveButton", "Remove", "BOTTOM", 100, 15, 80)
	self.RemoveButton:SetScript("OnClick", function()
		local input = self.ImportEditBox:GetText()
		input = string.gsub(input, " ", "")
		input = string.gsub(input, "[^a-zA-Z1-8,]", "")

		if input == "" then
			print("|cffff0000Import failed|r: You must enter a character name to remove.\nSeparate multiple entries with commas (,)\nExample: Cliffholger, Azzco,Nochin")
			return
		end
		RemoveFromRoster(input)
		self.ImportEditBox:ClearFocus()
	end)

	-- button close
	self.CloseButton = CreateFrame("Button","CloseRosterButton",self,"UIPanelCloseButton")
	self.CloseButton:SetPoint("TOPRIGHT",-6,-6)
	self.CloseButton:SetFrameStrata("LOW")
	self.CloseButton:SetWidth(32)
	self.CloseButton:SetHeight(32)
	self:Hide()
end

function Fika.Export:Gui()
	
	local backdrop = {
			edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
			bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
			tile="false",
			tileSize="32",
			edgeSize="32",
			insets={
				left="11",
				right="11",
				top="11",
				bottom="11"
			}
	}
	
	self:SetFrameStrata("BACKGROUND")
	self:SetWidth(180)
	self:SetHeight(560)
	self:SetPoint("CENTER",0,25)
	self:SetMovable(1)
	self:EnableMouse(1)
	self:RegisterForDrag("LeftButton")
	self:SetBackdrop(backdrop)
	self:SetBackdropColor(0,0,0,1)
	
	self.ExportHeader = self:CreateFontString(nil,"DIALOG")
	self.ExportHeader:SetPoint("TOP",0,-20)
	self.ExportHeader:SetFont("Fonts\\FRIZQT__.TTF", 12)
	self.ExportHeader:SetTextColor(1, 1, 1, 1)
	self.ExportHeader:SetShadowOffset(2,-2)
	self.ExportHeader:SetText("Export\nRaid Attendance")
	
	-- ExportEditBox
	self.ExportEditBox = CreateFrame("EditBox","ExportEditBox",self,"InputBoxTemplate")
	self.ExportEditBox:SetFontObject("GameFontHighlight")
	self.ExportEditBox:SetFrameStrata("DIALOG")
	ExportEditBoxLeft:Hide()
	ExportEditBoxMiddle:Hide()
	ExportEditBoxRight:Hide()
	self.ExportEditBox:SetPoint("TOPLEFT",self,"TOPLEFT",25,-50)
	self.ExportEditBox:SetPoint("BOTTOMRIGHT",self,"BOTTOMRIGHT", -25, 25)
	self.ExportEditBox:SetWidth(60)
	self.ExportEditBox:SetHeight(110)
	self.ExportEditBox:SetAutoFocus(false)
	self.ExportEditBox:SetMultiLine(true)
	self.ExportEditBox:SetScript("OnEnterPressed", function()
		self.ExportEditBox:ClearFocus()
	end)

	-- button close
	self.CloseButton = CreateFrame("Button","CloseExportButton",self,"UIPanelCloseButton")
	self.CloseButton:SetPoint("TOPRIGHT",-6,-6)
	self.CloseButton:SetFrameStrata("LOW")
	self.CloseButton:SetWidth(32)
	self.CloseButton:SetHeight(32)
	self:Hide()
end

function Fika.Invite:Gui()
	
	local backdrop = {
			edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
			bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
			tile="false",
			tileSize="32",
			edgeSize="32",
			insets={
				left="11",
				right="11",
				top="11",
				bottom="11"
			}
	}
	
	self:SetFrameStrata("BACKGROUND")
	self:SetWidth(320)
	self:SetHeight(110)
	self:SetPoint("CENTER",0,250)
	self:SetMovable(1)
	self:EnableMouse(1)
	self:RegisterForDrag("LeftButton")
	self:SetBackdrop(backdrop)
	self:SetBackdropColor(0,0,0,1)
	
	self.InviteHeader = self:CreateFontString(nil,"DIALOG")
	self.InviteHeader:SetPoint("TOP",0,-20)
	self.InviteHeader:SetFont("Fonts\\FRIZQT__.TTF", 12)
	self.InviteHeader:SetTextColor(1, 1, 1, 1)
	self.InviteHeader:SetShadowOffset(2,-2)
	self.InviteHeader:SetText("Start Raid Invites?")

	-- InviteButton
	self.StartTimerButton = CreateButton(self, "StartTimerButton", "Invite in 10 sec", "BOTTOM", -60, 25, 140)
	self.StartTimerButton:SetScript("OnEnter", function()
		ShowTooltip(self.StartTimerButton, "Invite Timer", "Click: Invites the current roster after a 10-second countdown", "", "")
	end)
	self.StartTimerButton:SetScript("OnClick", function()
			local rosterEmpty = true
			for _, _ in pairs(FIKA_Roster) do
				rosterEmpty = false
			end

			if rosterEmpty == false then
				InviteTimer_OnClick()
			else
				print("|cffffff00Roster is empty.|r")
			end
		end)
	self:Hide()

	-- Timer
	self.TimerText = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	self.TimerText:SetPoint("CENTER", StartTimerButton, "CENTER", 0, 25)
	self.TimerText:SetFont("Fonts\\FRIZQT__.TTF", 15)
	self.TimerText:SetTextColor(1, 1, 1, 1)
	self.TimerText:Show()

	-- InviteButton
	self.InviteButton = CreateButton(self, "InviteButton", "Invite now", "BOTTOM", 60, 25, 100)
	self.InviteButton:SetScript("OnEnter", function()
		ShowTooltip(self.InviteButton, "Invite now", "Click: Invite current roster", "", "")
	end)
	self.InviteButton:SetScript("OnClick", function()
			local rosterEmpty = true
			for _, _ in pairs(FIKA_Roster) do
        		rosterEmpty = false
    		end

			if rosterEmpty == false then
				if not IsShiftKeyDown() then
					InviteRoster()
					FIKA_Settings["inv"] = true
					Fika.Roster.InvCheckbox:SetChecked(FIKA_Settings["inv"])
					Fika.WantsInvite:Show()

					if inviteTimerRunning then
						InviteTimer_OnClick() -- stop timer
					end
				end
			else
				print("|cffffff00Roster is empty.|r")
			end
		end)
	self:Hide()

	-- button close
	self.CloseButton = CreateFrame("Button","CloseInviteButton",self,"UIPanelCloseButton")
	self.CloseButton:SetPoint("TOPRIGHT",-6,-6)
	self.CloseButton:SetFrameStrata("LOW")
	self.CloseButton:SetWidth(32)
	self.CloseButton:SetHeight(32)
	self:Hide()
end

function Fika.WantsInvite:Gui()
	
	Fika.WantsInvite.Drag = { }
	function Fika.WantsInvite.Drag:StartMoving()
		this:StartMoving()
	end
	
	function Fika.WantsInvite.Drag:StopMovingOrSizing()
		this:StopMovingOrSizing()
	end

	local backdrop = {
			edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
			bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
			tile="false",
			tileSize="32",
			edgeSize="32",
			insets={
				left="11",
				right="11",
				top="11",
				bottom="11"
			}
	}

	self:SetFrameStrata("BACKGROUND")
	self:SetWidth(180)
	self:SetHeight(250)
	self:SetPoint("CENTER",0,0)
	self:SetMovable(1)
	self:EnableMouse(1)
	self:RegisterForDrag("LeftButton")
	self:SetScript("OnDragStart", Fika.WantsInvite.Drag.StartMoving)
	self:SetScript("OnDragStop", Fika.WantsInvite.Drag.StopMovingOrSizing)
	self:SetBackdrop(backdrop)
	self:SetBackdropColor(0,0,0,1);
	
	self.InviteHeader = self:CreateFontString(nil,"DIALOG")
	self.InviteHeader:SetPoint("TOP",0,-20)
	self.InviteHeader:SetFont("Fonts\\FRIZQT__.TTF", 12)
	self.InviteHeader:SetTextColor(1, 1, 1, 1)
	self.InviteHeader:SetShadowOffset(2,-2)
	self.InviteHeader:SetText("|cff00ff00Invite?|r")

	-- scrollframe
	self.ScrollFrame = CreateFrame("ScrollFrame","InviteScrollFrame",self,"UIPanelScrollFrameTemplate")
	self.ScrollFrame:SetPoint("TOPLEFT",self,"TOPLEFT",12,-40)
	self.ScrollFrame:SetPoint("BOTTOMRIGHT",self,"BOTTOMRIGHT", -12, 15)
	self.ScrollFrame:SetFrameStrata("HIGH")
	
	self.child = CreateFrame("Frame","MyScrollChild",self.ScrollFrame)
	self.child:SetWidth(190)
	self.child:SetHeight(300)
	
	--self.child.bg = self.child:CreateTexture(nil,"BACKGROUND")
	--self.child.bg:SetAllPoints(true)
	--self.child.bg:SetTexture(0.2, 0.6, 0, 0.8)
	
	self.ScrollFrame:SetScrollChild(self.child)

	self.ScrollFrame.ScrollBar = getglobal("InviteScrollFrameScrollBar")
	self.ScrollFrame.ScrollBar:ClearAllPoints()
	self.ScrollFrame.ScrollBar:SetPoint("TOPRIGHT", self.ScrollFrame, "TOPRIGHT", 0, -15)
	self.ScrollFrame.ScrollBar:SetPoint("BOTTOMRIGHT", self.ScrollFrame, "BOTTOMRIGHT", 0, 17)
	self:Hide()

    function self:UpdateScrollList()
		-- Clear old buttons if they exist
		if self.ScrollItems then
			for _, button in ipairs(self.ScrollItems) do
				button:Hide()
				button:SetParent(nil)
			end
		end

		self.ScrollItems = {}

		local offsetY = -5
		local buttonHeight = 20
		local buttonWidth = 145

		for i, name in ipairs(FIKA_NotInRoster or {}) do
			local btn = CreateFrame("Button", nil, self.child, "UIPanelButtonTemplate")
			btn:SetWidth(buttonWidth)
			btn:SetHeight(buttonHeight)
			btn:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, offsetY)
			btn:SetScript("OnEnter", function()
				ShowTooltip(btn, "Invite", "Click: |cff00ff00Invite|r player to the raid", "Shift+Click: |cffff0000Remove|r player from the list", "")
			end)

			btn:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)

			local rawName = name
			GuildRoster()
			for i = 1, GetNumGuildMembers() do
				local CharName, _, _, _, Charclass = GetGuildRosterInfo(i);
				if rawName == CharName then
					name = GetClassColorForName(Charclass)..rawName.."|r"
				end
			end

			btn:SetText(name)
			btn:SetScript("OnClick", function()
				for index, storedName in ipairs(FIKA_NotInRoster) do
					if storedName == rawName then
						if IsShiftKeyDown() then
							table.remove(FIKA_NotInRoster, index)
						else
							InviteByName(rawName)
							table.remove(FIKA_NotInRoster, index)
							break
						end
					end
				end
				self:UpdateScrollList()
			end)

			table.insert(self.ScrollItems, btn)

			offsetY = offsetY - (buttonHeight)
		end
		self.child:SetHeight(math.abs(offsetY))
	end
end

function Fika.Roster:Gui()

	Fika.Roster.Drag = { }
	function Fika.Roster.Drag:StartMoving()
		this:StartMoving()
	end
	
	function Fika.Roster.Drag:StopMovingOrSizing()
		this:StopMovingOrSizing()
	end

	backdrop = {
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
	}
	self:SetFrameStrata("BACKGROUND")
	self:SetWidth(340)
	self:SetHeight(425)
	self:SetPoint("CENTER",0,0)
	self:SetMovable(1)
	self:EnableMouse(1)
	self:RegisterForDrag("LeftButton")
	self:SetScript("OnDragStart", Fika.Roster.Drag.StartMoving)
	self:SetScript("OnDragStop", Fika.Roster.Drag.StopMovingOrSizing)
	self:SetBackdropColor(0,0,0,1);
	
	self.Background = {}
    for _, position in ipairs({"Topleft", "Topright", "Bottomleft", "Bottomright"}) do
        self.Background[position] = CreateFrame("Frame", nil, self)
    end

	for i = 1, 2 do
        self.Background["Tab"..i.."buttonbg"] = CreateFrame("Frame", nil, self)
        self.Background["Tab"..i] = CreateFrame("Frame", nil, self)
        self.Background["Button"..i] = CreateFrame("Button", nil, self)
    end

	self.Icon = self:CreateTexture(nil, 'ARTWORK')
	self.Icon:SetTexture("Interface\\AddOns\\Fika\\media\\fika")
	self.Icon:SetWidth(58)
	self.Icon:SetHeight(58)
	self.Icon:SetPoint("TOPLEFT",-1,6)

	self.CloseButton = CreateFrame("Button","CloseListButton",self,"UIPanelCloseButton")
	self.CloseButton:SetPoint("TOPRIGHT",4,4)
	self.CloseButton:SetFrameStrata("LOW")
	self.CloseButton:SetWidth(32)
	self.CloseButton:SetHeight(32)
	self:Hide()

	self.Header = self.Background.Topleft:CreateFontString(nil,"OVERLAY", "GameFontNormal")
	self.Header:SetPoint("TOP",55,-17)
	self.Header:SetFont("Fonts\\FRIZQT__.TTF", 12)
	self.Header:SetTextColor(1, 1, 1, 1)
	self.Header:SetShadowOffset(2,-2)
	self.Header:SetText("|cff00ccffF.|cffffff00I.K.|cff00ccffA|r")

	local backdropFiles = {
        Topleft = "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft",
        Topright = "Interface\\PaperDollInfoFrame\\UI-Character-General-TopRight",
        Bottomleft = "Interface\\PaperDollInfoFrame\\UI-Character-General-BottomLeft",
        Bottomright = "Interface\\PaperDollInfoFrame\\UI-Character-General-BottomRight",
    }
    
    local framePositions = {
        Topleft = {-10, 13, 256, 256},
        Topright = {246, 13, 128, 256},
        Bottomleft = {-10, -243, 256, 256},
        Bottomright = {246, -243, 128, 256},
    }
    
    for position, backdropFile in pairs(backdropFiles) do
        local frame = self.Background[position]
        local positionData = framePositions[position]
        
        frame:SetFrameStrata("BACKGROUND")
        frame:SetWidth(positionData[3])
        frame:SetHeight(positionData[4])
        frame:SetBackdrop({bgFile = backdropFile})
        frame:SetPoint("TOPLEFT", positionData[1], positionData[2])
    end

    -- Set spacing between tabs and buttons (adjust the distance as needed)
    local backdrop = {bgFile = "Interface\\SPELLBOOK\\SpellBook-SkillLineTab"}
    local spacing = -50  -- Base distance between each tab and button (adjust as needed)

    -- Create tab backgrounds with spacing
    for i = 1, 2 do
        local tab = self.Background["Tab"..i.."buttonbg"]
        tab:SetFrameStrata("LOW")
        tab:SetWidth(64)
        tab:SetHeight(64)
        tab:SetBackdrop(backdrop)
        tab:SetPoint("TOPRIGHT", 61, spacing * i)  -- Apply spacing for tabs
    end

	-- Define the CreateTabButton function
    local function CreateTabButton(tab, button, glow, glowHide, tooltipText, buttonSpacing, texture)
        -- Tab frame setup
        tab:SetFrameStrata("LOW")
        tab:SetWidth(315)
        tab:SetHeight(350)
        tab:SetPoint("TOPLEFT", self, "TOPLEFT", 15, -65)

        button:SetBackdrop({bgFile = texture})
        button:SetFrameStrata("MEDIUM")
        button:SetPoint("TOPRIGHT", 31, -12 + buttonSpacing)
        button:SetWidth(30)
        button:SetHeight(30)
        
        button:SetScript("OnClick", function()
			UpdateRoster()
            for i = 1, 2 do
                self.Background["Tab"..i]:Hide()
            end
            tab:Show()

            for i = 1, 2 do
                self["Glow"..i]:Hide()
            end
            glow:Show()

			local PreraidSquad, AssistSquad = GetGuildRankName()
			self.PreraidplaceholderText:SetText(PreraidSquad)
			self.AssistplaceholderText:SetText(AssistSquad)

			if FIKA_Settings["keyword"] == nil then
				FIKA_Settings["keyword"] = "+"
			end
			
			self.KeywordplaceholderText:SetText(FIKA_Settings["keyword"])

			self.InvCheckbox:SetChecked(FIKA_Settings["inv"])

        end)

        button:SetScript("OnEnter", function()
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
			GameTooltip:SetText(tooltipText, 1, 1, 1)
			--GameTooltip:AddLine("Click: Open the invite window", 0.8, 0.8, 0.8)
			--GameTooltip:AddLine("Shift+Click: Invite Preraid squad", 0.4, 1, 0.4)
			--GameTooltip:AddLine("Alt+Click: Print Preraid squad, should be invited first", 0.4, 1, 0.4)
			GameTooltip:Show()
            glowHide:Show()
        end)

        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
            glowHide:Hide()
        end)

        glow:SetTexture("Interface\\BUTTONS\\ButtonHilight-Square")
		glow:SetBlendMode("ADD")
        glow:SetWidth(32)
        glow:SetHeight(32)
        glow:SetPoint("CENTER", 0, 0)
        glow:Hide()

        glowHide:SetTexture("Interface\\BUTTONS\\ButtonHilight-Square")
		glowHide:SetBlendMode("ADD")
        glowHide:SetWidth(32)
        glowHide:SetHeight(32)
        glowHide:SetPoint("CENTER", 0, 0)
        glowHide:Hide()
    end

    local tooltipTexts = {
        "Roster",
        "Options"
    }

    local buttonTextures = {
        "Interface/icons/INV_Misc_Head_Dragon_Black", -- Button 1
        "Interface/ICONS/INV_Gizmo_02" -- Button 2
    }

    for i = 1, 2 do
        self["Glow"..i] = self.Background["Button"..i]:CreateTexture(nil, 'ARTWORK')
        self["Glow"..i.."1"] = self.Background["Button"..i]:CreateTexture(nil, 'ARTWORK')

        local buttonSpacing = spacing * i

        CreateTabButton(self.Background["Tab"..i], self.Background["Button"..i], self["Glow"..i], self["Glow"..i.."1"], tooltipTexts[i], buttonSpacing, buttonTextures[i])
    end

	for i = 1, 2 do
		self.Background["Tab"..i]:Hide()
		self["Glow"..i]:Hide()
	end

	self.Background["Tab1"]:Show()
	self["Glow1"]:Show()

	--TAB1--
	-- RosterInviteButton
	self.RosterInviteButton = CreateButton(self.Background.Tab1, "RosterInviteButton", "Invite", "TOP", -75, 35, 60)
	self.RosterInviteButton:SetScript("OnEnter", function()
		ShowTooltip(self.RosterInviteButton, "Invite", "Click: Open the invite window", "Shift+Click: Invite Preraid squad", "Alt+Click: Print Preraid squad, should be invited first")
	end)
	self.RosterInviteButton:SetScript("OnClick", function()
		if IsShiftKeyDown() then
			local rosterEmpty = true
			for _, _ in pairs(FIKA_Roster) do
        		rosterEmpty = false
    		end

			if rosterEmpty == false then
				InviteRoster()
			else
				print("|cffffff00Roster is empty.|r")
			end

		elseif IsAltKeyDown() then
			SquadMember("Preraid",FIKA_Preraid, "")

		else
			if Fika.Invite:IsVisible() then
				Fika.Invite:Hide()
			else
				Fika.Import:Hide()
				Fika.Export:Hide()
				Fika.Invite:Show()
			end
		end
	end)
	
	-- RosterSortButton
	self.RosterSortButton = CreateButton(self.Background.Tab1, "RosterSortButton", "Sort", "TOP", -10, 35, 60)
	self.RosterSortButton:SetScript("OnEnter", function()
		ShowTooltip(self.RosterSortButton, "Sort groups", "Click: Sort players into their assigned groups", "Shift+Click: Give assist to assist squad", "Alt+Click: Print Assist squad list")
	end)
	self.RosterSortButton:SetScript("OnClick", function()
		if IsShiftKeyDown() then
			local raidLookup = {}
			for i = 1, GetNumRaidMembers() do
				local name, _, _, _, _, _, _, _, isAssist = GetRaidRosterInfo(i)
				if name then
					raidLookup[name] = { index = i, isAssist = isAssist }
				end
			end

			for _, assistName in ipairs(FIKA_Assist) do
				local info = raidLookup[assistName]
				if info and not info.isAssist then
					PromoteToAssistant(assistName)
				end
			end

		elseif IsAltKeyDown() then
			SquadMember("Assist",FIKA_Assist, "")

		else
			if (pingdelay == nil or GetTime()-pingdelay > 2) then 
				pingdelay = GetTime()
				SortGroups()
			else
				print("|cffff0000You are sorting too fast.|r")
			end
		end
	end)

	-- RosterMissingButton
	self.RosterMissingButton = CreateButton(self.Background.Tab1, "RosterMissingButton", "Miss?", "TOP", 55, 35, 60)
	self.RosterMissingButton:SetScript("OnEnter", function()
		ShowTooltip(self.RosterMissingButton, "Missing Check", "Click: Report |cffffff00missing|r players in raid chat", "|cff66ff66Shift+Click: Report|r |cffff0000offline|r |cff66ff66players in raid chat|r", "|cff66ff66Alt+Click: Report|r |cffff0000dead|r |cff66ff66players in raid chat|r")
	end)
	self.RosterMissingButton:SetScript("OnClick", function()
		CheckMissing()
	end)

	-- RosterImportButton
	self.RosterImportButton = CreateButton(self.Background.Tab1, "RosterImportButton", "Import", "TOP", 120, 35, 60)
	self.RosterImportButton:SetScript("OnEnter", function()
		ShowTooltip(self.RosterImportButton, "Import Roster", "Click: Open manual import", "Shift+Click: Import Preraid squad", "Alt+Click: Import Assist squad")
	end)
	self.RosterImportButton:SetScript("OnClick", function()
		local function MakeSet(list)
			local set = {}
			for _, name in ipairs(list) do
				set[name] = true
			end
			return set
		end

		local function SyncSquad(squadName, targetList, sourceList)
			local sourceSet = MakeSet(sourceList)
			local targetSet = MakeSet(targetList)
			local changed = false

			for _, name in ipairs(sourceList) do
				if not targetSet[name] then
					SquadMember(squadName, targetList, name)
					changed = true
				end
			end

			if changed then
				print("|cffffff00"..squadName.." squad synced.|r")
			else
				print("|cffffff00"..squadName.." squad already up to date.|r")
			end
		end

		if IsShiftKeyDown() then
			if FIKA_Settings["guild"] == true then
				local Officers, Classleaders = OfficerRoster()
				SyncSquad("Preraid", FIKA_Preraid, Classleaders)
			else
				print("|cffffff00You need to Toggle Roster guild check for this..|r")
			end

		elseif IsAltKeyDown() then
			if FIKA_Settings["guild"] == true then
				local Officers, Classleaders = OfficerRoster()
				SyncSquad("Assist", FIKA_Assist, Officers)
			else
				print("|cffffff00You need to Toggle Roster guild check for this..|r")
			end

		else
			if Fika.Import:IsVisible() then
				Fika.Import:Hide()
			else
				Fika.Export:Hide()
				Fika.Invite:Hide()
				Fika.Import:Show()
			end
		end
	end)

	local groupsPerRow = 2
	local spacingX = 170
	local spacingY = 87
	local playerSpacingY = 15

	local startX = 20
	local startY = -65

	if not self.GroupMembers then self.GroupMembers = {} end
	if not self.GroupBackgrounds then self.GroupBackgrounds = {} end

	for group = 1, 8 do

		if not self.GroupMembers[group] then self.GroupMembers[group] = {} end

		local row = math.floor((group - 1) / groupsPerRow)
		local col = group - row * groupsPerRow - 1

		local groupX = startX + (col * spacingX)
		local groupY = startY - (row * spacingY)

		local groupBackground = CreateFrame("Frame", nil, self.Background.Tab1)
		groupBackground:SetFrameStrata("BACKGROUND")
		groupBackground:SetWidth(140)
		groupBackground:SetHeight(90)
		groupBackground:SetPoint("TOPLEFT", self, "TOPLEFT", groupX - 6, groupY)
		groupBackground:SetBackdrop({
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 }
		})

		self.GroupBackgrounds[group] = groupBackground

		self.groupTitle = self.Background.Tab1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		self.groupTitle:SetPoint("TOPLEFT", self, "TOPLEFT", groupX, groupY - 2)
		self.groupTitle:SetText("Group "..group)

		self.GroupMembers[group] = {}

		self.GroupButtons = self.GroupButtons or {}
		self.GroupButtons[group] = self.GroupButtons[group] or {}

		for i = 1, 5 do
			local member = self.Background.Tab1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			member:SetPoint("TOPLEFT", self, "TOPLEFT", groupX + 12, groupY - (i * playerSpacingY))
			member:SetText("|cffff0000---|r")
			self.GroupMembers[group][i] = member

			-- - Button
			local btn = CreateFrame("Button", nil, self.Background.Tab1, "UIPanelButtonTemplate")
			btn:SetWidth(12)
			btn:SetHeight(12)
			btn:SetPoint("TOPLEFT", self, "TOPLEFT", groupX, groupY - (i * playerSpacingY))
			btn:SetText("|cffff0000-|r")

			self.GroupButtons[group][i] = btn

			-- capture values
			local g = group
			local idx = i

			btn:SetScript("OnClick", function()
				local name = FIKA_Roster[g] and FIKA_Roster[g][idx]
				if name then
					RemoveFromRoster(name)
				end
			end)
		end
	end

	--TAB2--
	-- InvCheckbox
	self.InvCheckbox = CreateFrame("CheckButton", "InvCheckbox", self.Background.Tab2, "UICheckButtonTemplate")
	self.InvCheckbox:SetPoint("LEFT",10,150)
	self.InvCheckbox:SetWidth(35)
	self.InvCheckbox:SetHeight(35)
	self.InvCheckbox:SetFrameStrata("MEDIUM")
	self.InvCheckbox:SetScript("OnClick", function ()
		if self.InvCheckbox:GetChecked() == nil then 
			FIKA_Settings["inv"] = false
			Fika.WantsInvite:Hide()

		elseif self.InvCheckbox:GetChecked() == 1 then
			FIKA_Settings["inv"] = true
			Fika.WantsInvite:Show()
		end
	end)
	
	self.InvCheckbox:SetScript("OnEnter", function()
		ShowTooltip(self.InvCheckbox, "Toggle invites", "", "", "")
	end)
	self.InvCheckbox:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	self.InvCheckbox:SetChecked(FIKA_Settings["inv"])

	self.textInv = self.InvCheckbox:CreateFontString(nil, "OVERLAY")
    self.textInv:SetPoint("LEFT", 35, 0)
    self.textInv:SetFont("Fonts\\FRIZQT__.TTF", 12)
	self.textInv:SetTextColor(255,255,0, 1)
	self.textInv:SetShadowOffset(2,-2)
    self.textInv:SetText("Raid invites with keyword (guild / whisper)")

	self.KeywordEditBox = CreateFrame("EditBox","KeywordEditBox",self.Background.Tab2,"InputBoxTemplate")
	self.KeywordEditBox:SetFontObject("GameFontHighlight")
	self.KeywordEditBox:SetFrameStrata("DIALOG")
	self.KeywordEditBox:SetPoint("CENTER",0,115)
	self.KeywordEditBox:SetWidth(150)
	self.KeywordEditBox:SetHeight(30)
	self.KeywordEditBox:SetAutoFocus(false)
	self.KeywordEditBox:SetJustifyH("CENTER")

	self.KeywordplaceholderText = KeywordEditBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.KeywordplaceholderText:SetPoint("CENTER", KeywordEditBox, "CENTER", 0, 0)
	self.KeywordplaceholderText:SetText(FIKA_Settings["keyword"])
	self.KeywordplaceholderText:SetTextColor(0.5, 0.5, 0.5, 0.7)

	self.KeywordEditBox:SetScript("OnEscapePressed", function()
		self.KeywordEditBox:ClearFocus()
		self.KeywordEditBox:SetText("")
		self.KeywordplaceholderText:Show()
	end)

	self.KeywordEditBox:SetScript("OnEnterPressed", function()
		self.KeywordEditBox:ClearFocus()
		if self.KeywordEditBox:GetText() == "" then
			self.KeywordplaceholderText:Show()
			return
		end
		FIKA_Settings["keyword"] = self.KeywordEditBox:GetText()
		self.KeywordplaceholderText:SetText(FIKA_Settings["keyword"])
		self.KeywordEditBox:SetText("")
		self.KeywordplaceholderText:Show()
	end)

	self.KeywordEditBox:SetScript("OnChar", function()
		self.KeywordplaceholderText:Hide()
	end)

	--keywordText
	local keywordText = self.KeywordEditBox:CreateFontString(nil, "OVERLAY")
    keywordText:SetPoint("TOP",0,10)
    keywordText:SetFont("Fonts\\FRIZQT__.TTF", 12)
	keywordText:SetTextColor(255, 255, 0, 1)
	keywordText:SetShadowOffset(2,-2)
    keywordText:SetText("Keyword")

	-- toggle guild
	self.GuildCheckbox = CreateFrame("CheckButton", "GuildCheckbox", self.Background.Tab2, "UICheckButtonTemplate")
	self.GuildCheckbox:SetPoint("LEFT",10,80)
	self.GuildCheckbox:SetWidth(35)
	self.GuildCheckbox:SetHeight(35)
	self.GuildCheckbox:SetFrameStrata("MEDIUM") 
	self.GuildCheckbox:SetScript("OnClick", function ()
		if not IsInGuild() then
			print("|cffff0000You are not in a guild..")
			FIKA_Settings["guild"] = false
			self.GuildCheckbox:SetChecked(false)
			self.GuildFrame:Hide()
			return
		end

		if self.GuildCheckbox:GetChecked() == nil then 
			FIKA_Settings["guild"] = false
			self.GuildFrame:Hide()
		elseif self.GuildCheckbox:GetChecked() == 1 then
			FIKA_Settings["guild"] = true
			self.GuildFrame:Show()
		end
	end)
	
	self.GuildCheckbox:SetScript("OnEnter", function()
		ShowTooltip(self.GuildCheckbox, "Toggle roster guild check", "", "", "")
	end)
	self.GuildCheckbox:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	self.GuildCheckbox:SetChecked(FIKA_Settings["guild"])


	self.textGuild = self.GuildCheckbox:CreateFontString(nil, "OVERLAY")
    self.textGuild:SetPoint("LEFT", 35, 0)
    self.textGuild:SetFont("Fonts\\FRIZQT__.TTF", 12)
	self.textGuild:SetTextColor(255,255,0, 1)
	self.textGuild:SetShadowOffset(2,-2)
    self.textGuild:SetText("Roster guild check\nPreraid & Assist squad")

	--test
	local backdrop1 = {
		edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
		bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
		tile="false",
		tileSize="32",
		edgeSize="32",
		insets={
			left="11",
			right="11",
			top="11",
			bottom="11"
		}
	}

	self.GuildFrame = CreateFrame("Frame",nil,self.Background.Tab2)
	self.GuildFrame:SetPoint("CENTER",0, 5)
	self.GuildFrame:SetFrameStrata("HIGH")
	self.GuildFrame:SetBackdrop(backdrop1)
	self.GuildFrame:SetBackdropColor(0,0,0,1)
	self.GuildFrame:SetWidth(290)
	self.GuildFrame:SetHeight(100)
	self.GuildFrame:Hide()

	--self.GuildFrame.bg = self.GuildFrame:CreateTexture(nil,"BACKGROUND")
	--self.GuildFrame.bg:SetAllPoints(true)
	--self.GuildFrame.bg:SetTexture(0.2, 0.6, 0, 0.8)

	self.PreraidRankEditBox = CreateFrame("EditBox","PreraidRankEditBox",self.GuildFrame,"InputBoxTemplate")
	self.PreraidRankEditBox:SetFontObject("GameFontHighlight")
	self.PreraidRankEditBox:SetFrameStrata("DIALOG")
	self.PreraidRankEditBox:SetPoint("TOP",-65,-45)
	self.PreraidRankEditBox:SetWidth(120)
	self.PreraidRankEditBox:SetHeight(30)
	self.PreraidRankEditBox:SetAutoFocus(false)

	self.PreraidplaceholderText = PreraidRankEditBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.PreraidplaceholderText:SetPoint("CENTER", PreraidRankEditBox, "CENTER", 0, 0)

	self.PreraidplaceholderText:SetTextColor(0.5, 0.5, 0.5, 0.7)

	self.PreraidRankEditBox:SetScript("OnEnter", function() 

	end)

	self.PreraidRankEditBox:SetScript("OnLeave", function()

	end)

	self.PreraidRankEditBox:SetScript("OnEscapePressed", function()
		self.PreraidRankEditBox:ClearFocus()
		self.PreraidRankEditBox:SetText("")
		self.PreraidplaceholderText:Show()
	end)

	self.PreraidRankEditBox:SetScript("OnEnterPressed", function()
		self.PreraidRankEditBox:ClearFocus()
		if self.PreraidRankEditBox:GetText() == "" then
			self.PreraidRankEditBox:SetText("1")
		end
		FIKA_Settings["preraidrank"] = self.PreraidRankEditBox:GetText()
		self.PreraidplaceholderText:SetText(GuildControlGetRankName(FIKA_Settings["preraidrank"]))
		self.PreraidplaceholderText:Show()
		self.PreraidRankEditBox:SetText("")
	end)

	self.PreraidRankEditBox:SetScript("OnChar", function()
		self.PreraidplaceholderText:Hide()
		local text = self.PreraidRankEditBox:GetText()

		local filtered = string.gsub(text, "[^1-9]", "")

		if filtered == "" then
			self.PreraidRankEditBox:SetText("")
			return
		end

		if string.len(filtered) > 1 then
			filtered = string.sub(filtered, -1)
		end

		if filtered ~= text then
			self.PreraidRankEditBox:SetText(filtered)
		end
	end)

	--preraidText
	local preraidText = self.PreraidRankEditBox:CreateFontString(nil, "OVERLAY")
    preraidText:SetPoint("TOP",0,25)
    preraidText:SetFont("Fonts\\FRIZQT__.TTF", 12)
	preraidText:SetTextColor(255, 255, 0, 1)
	preraidText:SetShadowOffset(2,-2)
    preraidText:SetText("Preraid\nrank index")

	self.AssistRankEditBox = CreateFrame("EditBox","AssistRankEditBox",self.GuildFrame,"InputBoxTemplate")
	self.AssistRankEditBox:SetFontObject("GameFontHighlight")
	self.AssistRankEditBox:SetFrameStrata("DIALOG")
	self.AssistRankEditBox:SetPoint("TOP",65,-45)
	self.AssistRankEditBox:SetWidth(120)
	self.AssistRankEditBox:SetHeight(30)
	self.AssistRankEditBox:SetAutoFocus(false)

	self.AssistplaceholderText = AssistRankEditBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.AssistplaceholderText:SetPoint("CENTER", AssistRankEditBox, "CENTER", 0, 0)

	self.AssistplaceholderText:SetTextColor(0.5, 0.5, 0.5, 0.7)

	self.AssistRankEditBox:SetScript("OnEnter", function() 

	end)

	self.AssistRankEditBox:SetScript("OnLeave", function()

	end)

	self.AssistRankEditBox:SetScript("OnEscapePressed", function()
		self.AssistRankEditBox:ClearFocus()
		self.AssistRankEditBox:SetText("")
		self.AssistplaceholderText:Show()
	end)

	self.AssistRankEditBox:SetScript("OnEnterPressed", function()
		self.AssistRankEditBox:ClearFocus()
		if self.AssistRankEditBox:GetText() == "" then
			self.AssistRankEditBox:SetText("1")
		end
		FIKA_Settings["assistrank"] = self.AssistRankEditBox:GetText()
		self.AssistplaceholderText:SetText(GuildControlGetRankName(FIKA_Settings["assistrank"]))
		self.AssistplaceholderText:Show()
		self.AssistRankEditBox:SetText("")
	end)

	self.AssistRankEditBox:SetScript("OnChar", function()
		self.AssistplaceholderText:Hide()
		local text = self.AssistRankEditBox:GetText()

		local filtered = string.gsub(text, "[^1-9]", "")

		if filtered == "" then
			self.AssistRankEditBox:SetText("")
			return
		end

		if string.len(filtered) > 1 then
			filtered = string.sub(filtered, -1)
		end

		if filtered ~= text then
			self.AssistRankEditBox:SetText(filtered)
		end
	end)

	--assistText
	local assistText = self.AssistRankEditBox:CreateFontString(nil, "OVERLAY")
    assistText:SetPoint("TOP",0,25)
    assistText:SetFont("Fonts\\FRIZQT__.TTF", 12)
	assistText:SetTextColor(255, 255, 0, 1)
	assistText:SetShadowOffset(2,-2)
    assistText:SetText("Assist\nrank index")

	self.SquadEditBox = CreateFrame("EditBox","SquadEditBox",self.Background.Tab2,"InputBoxTemplate")
	self.SquadEditBox:SetFontObject("GameFontHighlight")
	self.SquadEditBox:SetFrameStrata("DIALOG")
	self.SquadEditBox:SetPoint("BOTTOM",0,80)
	self.SquadEditBox:SetWidth(150)
	self.SquadEditBox:SetHeight(30)
	self.SquadEditBox:SetAutoFocus(false)
	self.SquadEditBox:SetJustifyH("CENTER")

	self.SquadplaceholderText = SquadEditBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.SquadplaceholderText:SetPoint("CENTER", SquadEditBox, "CENTER", 0, 0)
	self.SquadplaceholderText:SetText("Ex: Taengil")
	self.SquadplaceholderText:SetTextColor(0.5, 0.5, 0.5, 0.7)

	self.SquadEditBox:SetScript("OnEscapePressed", function()
		self.SquadEditBox:ClearFocus()
		self.SquadEditBox:SetText("")
		self.SquadplaceholderText:Show()
	end)

	self.SquadEditBox:SetScript("OnEnterPressed", function()
		self.SquadEditBox:ClearFocus()
		if self.SquadEditBox:GetText() == "" then
			self.SquadplaceholderText:Show()
			return
		end
	end)

	self.SquadEditBox:SetScript("OnChar", function()
		self.SquadplaceholderText:Hide()
		local text = self.SquadEditBox:GetText()
		text = string.gsub(text, " ", "")
		text = string.gsub(text, "[^a-zA-Z]", "")
		text = string.lower(text)
		text = string.gsub(text, "^%l", string.upper)
		self.SquadEditBox:SetText(text)
	end)

	-- AddPreraidButton
	self.AddPreraidButton = CreateButton(self.Background.Tab2, "AddPreraidButton", "Add / Remove", "BOTTOM", -80, 40, 120)
	self.AddPreraidButton:SetScript("OnEnter", function()
		ShowTooltip(self.AddPreraidButton, "Add or Remove", "Click: Add / Remove name from list", "", "")
	end)
	self.AddPreraidButton:SetScript("OnClick", function()
		self.SquadEditBox:ClearFocus()
		SquadMember("Preraid", FIKA_Preraid, self.SquadEditBox:GetText())
	end)

	self.textGuild = self.AddPreraidButton:CreateFontString(nil, "OVERLAY")
    self.textGuild:SetPoint("TOP", 0, 15)
    self.textGuild:SetFont("Fonts\\FRIZQT__.TTF", 12)
	self.textGuild:SetTextColor(255,255,0, 1)
	self.textGuild:SetShadowOffset(2,-2)
    self.textGuild:SetText("Preraid")

	-- PrintPreraidButton
	self.PrintPreraidButton = CreateButton(self.AddPreraidButton, "PrintPreraidButton", "Show", "TOP", -35, -30, 70)
	self.PrintPreraidButton:SetScript("OnEnter", function()
		ShowTooltip(self.PrintPreraidButton, "Print Preraid squad", "Click: List squad", "", "")
	end)
	self.PrintPreraidButton:SetScript("OnClick", function()
		self.SquadEditBox:ClearFocus()
		SquadMember("Preraid",FIKA_Preraid, "")
	end)

	-- ClearPreraidButton
	self.ClearPreraidButton = CreateButton(self.AddPreraidButton, "ClearPreraidButton", "Clear", "TOP", 35, -30, 70)
	self.ClearPreraidButton:SetScript("OnEnter", function()
		ShowTooltip(self.ClearPreraidButton, "Clear Preraid squad", "Click: Empty the squad", "", "")
	end)
	self.ClearPreraidButton:SetScript("OnClick", function()
		self.SquadEditBox:ClearFocus()
		FIKA_Preraid = {}
		print("|cffffff00The Preraid Squad has been cleared|r.")
	end)

	-- AddAssistButton
	self.AddAssistButton = CreateButton(self.Background.Tab2, "AddAssistButton", "Add / Remove ", "BOTTOM", 80, 40, 120)
	self.AddAssistButton:SetScript("OnEnter", function()
		ShowTooltip(self.AddAssistButton, "Add or Remove", "Click: Add / Remove name from list", "", "")
	end)
	self.AddAssistButton:SetScript("OnClick", function()
		self.SquadEditBox:ClearFocus()
		SquadMember("Assist", FIKA_Assist, self.SquadEditBox:GetText())
	end)

	self.textGuild = self.AddAssistButton:CreateFontString(nil, "OVERLAY")
    self.textGuild:SetPoint("TOP", 0, 15)
    self.textGuild:SetFont("Fonts\\FRIZQT__.TTF", 12)
	self.textGuild:SetTextColor(255,255,0, 1)
	self.textGuild:SetShadowOffset(2,-2)
    self.textGuild:SetText("Assist")

	-- PrintAssistButton
	self.PrintAssistButton = CreateButton(self.AddAssistButton, "PrintAssistButton", "Show", "TOP", -35, -30, 70)
	self.PrintAssistButton:SetScript("OnEnter", function()
		ShowTooltip(self.PrintAssistButton, "Print Assist squad", "Click: List squad", "", "")
	end)
	self.PrintAssistButton:SetScript("OnClick", function()
		self.SquadEditBox:ClearFocus()
		SquadMember("Assist",FIKA_Assist, "")
	end)

	-- ClearAssistButton
	self.ClearAssistButton = CreateButton(self.AddAssistButton, "ClearAssistButton", "Clear", "TOP", 35, -30, 70)
	self.ClearAssistButton:SetScript("OnEnter", function()
		ShowTooltip(self.ClearAssistButton, "Clear Assist squad", "Click: Empty the squad", "", "")
	end)
	self.ClearAssistButton:SetScript("OnClick", function()
		self.SquadEditBox:ClearFocus()
		FIKA_Assist = {}
		print("|cffffff00The Assist Squad has been cleared|r.")
	end)

	self:Hide()
end

Fika:SetScript("OnEvent", Fika.OnEvent)

function Fika.slash(arg1)

	if arg1 == "help" then
		print("|cff00ccffFast |cffffff00Invite Komp |cff00ccffAssigner|r")
		print("|cff00ff00Version:|r "..FIKA_VERSION)
		print("|cff3399ffCommands:|r")
		print("'/fika' - Toggle roster frame")
        return
    end

	if arg1 == nil or arg1 == "" then
		if Fika.Roster:IsVisible() then
			Fika.Roster:Hide()
		else
			UpdateRoster()
			Fika.Roster:Show()
		end
		return
	end
end

SlashCmdList["FIKA_SLASH"] = Fika.slash
SLASH_FIKA_SLASH1 = "/fika"