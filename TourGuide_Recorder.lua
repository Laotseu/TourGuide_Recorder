local myname, ns = ...

local _G 								= getfenv(0)

local geterrorhandler				= _G.geterrorhandler
local hooksecurefunc					= _G.hooksecurefunc
local next								= _G.next
local pairs								= _G.pairs
local setmetatable					= _G.setmetatable
local time								= _G.time
local tonumber							= _G.tonumber
local tostring							= _G.tostring
local tostringall						= _G.tostringall
local min								= _G.min
local max								= _G.max
local floor								= _G.floor

local AbandonQuest					= _G.AbandonQuest
local CreateFrame						= _G.CreateFrame
local GetAutoQuestPopUp				= _G.GetAutoQuestPopUp
local GetContainerItemLink			= _G.GetContainerItemLink
local GetNumAutoQuestPopUps		= _G.GetNumAutoQuestPopUps
local GetNumQuestLeaderBoards		= _G.GetNumQuestLeaderBoards
local GetNumQuestLogEntries		= _G.GetNumQuestLogEntries
local GetPlayerMapPosition			= _G.GetPlayerMapPosition
local GetQuestID						= _G.GetQuestID
local GetQuestLink					= _G.GetQuestLink
local GetQuestLogLeaderBoard		= _G.GetQuestLogLeaderBoard
local GetQuestLogSpecialItemInfo	= _G.GetQuestLogSpecialItemInfo
local GetQuestLogTitle				= _G.GetQuestLogTitle
local GetSubZoneText					= _G.GetSubZoneText
local GetZoneText						= _G.GetZoneText
local HideUIPanel						= _G.HideUIPanel
local IsConsumableItem				= _G.IsConsumableItem
local IsUsableItem					= _G.IsUsableItem
local ShowUIPanel						= _G.ShowUIPanel
local SlashCmdList					= _G.SlashCmdList
local StaticPopupDialogs			= _G.StaticPopupDialogs
local StaticPopup_Show				= _G.StaticPopup_Show
local UnitName							= _G.UnitName
local UnitOnTaxi						= _G.UnitOnTaxi

local ERR_DEATHBIND_SUCCESS_S		= _G.ERR_DEATHBIND_SUCCESS_S
local ERR_QUEST_COMPLETE_S			= _G.ERR_QUEST_COMPLETE_S
local GameFontDisable				= _G.GameFontDisable
local GameFontHighlight				= _G.GameFontHighlight
local GameFontHighlightSmall		= _G.GameFontHighlightSmall
local GameFontNormal					= _G.GameFontNormal
local MerchantFrame					= _G.MerchantFrame

local function err(msg,...) geterrorhandler()(msg:format(tostringall(...)) .. " - " .. time()) end

local accepted, currentcompletes, oldcompletes, currentquests, oldquests, currentboards, oldboards, titles, firstscan, abandoning, db = {}, {}, {}, {}, {}, {}, {}, {}, true

local qids = setmetatable({}, {
	__index = function(t,i)
		local v = tonumber(i:match("|Hquest:(%d+):"))
		t[i] = v
		return v
	end,
})
local itemids = setmetatable({}, {
	__index = function(t,k)
		local v = tonumber(k:match("item:(%d+)"))
		t[k] = v
		return v
	end,
})

-- For debug
--Eric = Eric or {}
--Eric.qids, Eric.itemids = qids, itemids
--Eric.accepted, Eric.currentcompletes, Eric.oldcompletes, Eric.currentquests, Eric.oldquests, Eric.currentboards, Eric.oldboards, Eric.titles
--	= accepted, currentcompletes, oldcompletes, currentquests, oldquests, currentboards, oldboards, titles

local f = CreateFrame("frame")
f:SetScript("OnEvent", function(self, event, ...) if self[event] then return self[event](self, event, ...) end end)
f:RegisterEvent("ADDON_LOADED")


function f:ADDON_LOADED(event, addon)
	if addon ~= "TourGuide_Recorder" then return end

	_G.TourGuide_RecorderDB = _G.TourGuide_RecorderDB or ""

	self:RegisterEvent("QUEST_LOG_UPDATE")
	self:RegisterEvent("PLAYER_LEVEL_UP")
	self:RegisterEvent("QUEST_AUTOCOMPLETE")
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("TAXIMAP_OPENED")

	self:UnregisterEvent("ADDON_LOADED")
	self.ADDON_LOADED = nil
end


local function Save(val)
	_G.TourGuide_RecorderDB = _G.TourGuide_RecorderDB..val
end

local function coords()
	local x, y = GetPlayerMapPosition("player")
	return x * 100, y * 100
end

local function SaveCoords()
	local x, y = GetPlayerMapPosition("player")
	Save(("M|%.1f,%.1f|Z|%s|; %s"):format(x * 100, y * 100, GetZoneText(), GetSubZoneText()))
end

function f:PLAYER_LEVEL_UP(event, level)
	Save("\n; Level up! ".. level)
end

local lastautocomplete
function f:QUEST_AUTOCOMPLETE(event, qid)
	lastautocomplete = qid
end

function f:QUEST_LOG_UPDATE()
	currentquests, oldquests = oldquests, currentquests
	currentboards, oldboards = oldboards, currentboards
	currentcompletes, oldcompletes = oldcompletes, currentcompletes
	for i in pairs(currentquests) do currentquests[i] = nil end
	for i in pairs(currentboards) do currentboards[i] = nil end
	for i in pairs(currentcompletes) do currentcompletes[i] = nil end

	for i=1,GetNumQuestLogEntries() do
		local link = GetQuestLink(i)
		local qid = link and qids[link]
		if qid then
			currentquests[qid] = true
			local title, _, _, _, _, _, complete = GetQuestLogTitle(i)
			titles[qid] = title
			currentcompletes[qid] = complete == 1 and title or nil

			if GetNumQuestLeaderBoards(i) > 1 then
				for j=1,GetNumQuestLeaderBoards(i) do
					local text, objtype, finished = GetQuestLogLeaderBoard(j, i)
					if finished then
						currentboards[qid.."."..j] = text
					end
				end
			end
		end
	end

	if firstscan and next(currentquests) then
	 	for qid in pairs(currentquests) do accepted[qid] = true end
		firstscan = nil
		return
	end

	for qidboard,text in pairs(currentboards) do
		local qid = tonumber(qidboard:match("(%d+)[.]"))
		if not oldboards[qidboard] and accepted[qid] then
			Save(("\nC %s |QID|%s|QO|%s|"):format(titles[qid], qid, text))
			SaveCoords()
		end
	end

	for qidcomplete,title in pairs(currentcompletes) do
		if not oldcompletes[qidcomplete] and accepted[qidcomplete] then
			Save(("\nC %s |QID|%s|"):format(title, qidcomplete))
			SaveCoords()
		end
	end

	for qid in pairs(oldquests) do
		if not currentquests[qid] then
			local action = abandoning and "Abandoned quest" or "Turned in quest"
			if not abandoning then
				local note = UnitName("target") and ("N|To %s|"):format(UnitName("target")) or ""
				Save(("\nT %s |QID|%s|%s"):format(titles[qid], qid, note))
				SaveCoords()
			end
			if lastautocomplete == qid then Save("\n; Field turnin") end
			accepted[qid] = nil
			abandoning = nil
			return
		end
	end

	for qid in pairs(currentquests) do
		if not oldquests[qid] then
			accepted[qid] = true
			for i=1,GetNumAutoQuestPopUps() do
				local questID, popUpType = GetAutoQuestPopUp(i)
				if questID == qid and popUpType == "OFFER" then
					Save("\n; Auto quest:")
				end
			end
			local note = UnitName("target") and ("N|From %s|"):format(UnitName("target")) or ""
			Save(("\nA %s |QID|%s|%s"):format(titles[qid], qid, note))
			SaveCoords()
			return
		end
	end
end

-- Auto-Complete: Set hearth and quests that complete without any effect on the quest log --
local HOME_MSG = '^' .. ERR_DEATHBIND_SUCCESS_S:format('(.*)') .. '$' -- Build localized: "^(.*) is now your home.$"
local QUEST_MSG = '^' .. ERR_QUEST_COMPLETE_S:format('(.+)') .. '$'   -- Build localized: "^(.+) completed.$"
function f:CHAT_MSG_SYSTEM(event, msg, ...)
	local quest = msg:match(QUEST_MSG)
	if quest then
		local qid = GetQuestID()
		if qid and not titles[qid] then
			Save(("\nA %s |QID|%s|N|Auto-accept|"):format(titles[qid], qid))
			SaveCoords()
		end
	else
		local loc = msg:match(HOME_MSG)
		if loc then
			-- The user has set his Hearth to a new location
			local note = UnitName("target") and ("N|Talk to %s|"):format(UnitName("target")) or ""
			Save(("\nh %s |%s"):format(loc, note))
			SaveCoords()
		end
	end
end


local orig = AbandonQuest
function AbandonQuest(...)
	abandoning = true
	return orig(...)
end


local used = {}
hooksecurefunc("UseContainerItem", function(bag, slot, ...)
	if MerchantFrame:IsVisible() then return end
	local link = GetContainerItemLink(bag, slot)
	if link and not used[link] and (IsUsableItem(link) or IsConsumableItem(link)) then
		used[link] = true
		Save(("\n; |U|%s|N|%s|"):format(itemids[link], link))
		SaveCoords()
	end
end)
hooksecurefunc("UseQuestLogSpecialItem", function(questIndex)
	local link, item = GetQuestLogSpecialItemInfo(questIndex)
	if item then
		used[link] = true
		Save(("\n; |U|%s|N|%s|"):format(item, link))
		SaveCoords()
	end
end)

do -- Closure

	local tf, THROTTLE_TIME, throt, is_on_taxi = CreateFrame("frame"), 0.1

	tf:Hide()
	tf:SetScript("OnShow", function(self)
		is_on_taxi = nil
		throt = THROTTLE_TIME
	end)
	tf:SetScript("OnUpdate", function(self, elapsed)
		throt = throt - elapsed
		if throt < 0 then
			if not is_on_taxi and UnitOnTaxi("player") then
				-- Player just got on the taxi
				Save("\nN Took a taxi |")
				SaveCoords()

				is_on_taxi = true
			elseif is_on_taxi and not UnitOnTaxi("player") then
				-- Player just got off the taxi
				Save(("\nf %s |N|Fly to %s, %s|"):format(GetSubZoneText(), GetSubZoneText(), GetZoneText()))
				SaveCoords()

				tf:Hide()
				return
			end
			throt = throt + THROTTLE_TIME
		end
	end)
	tf:SetScript("OnHide", function(self)
		is_on_taxi = nil
	end)

	function f:TAXIMAP_OPENED()
		tf:Hide()
		tf:Show()
	end

end -- Closure

local panel = ns.tekPanelAuction(nil, "TourGuide Recorder log")

_G.SLASH_TGR1 = "/tgr"
function SlashCmdList.TGR(msg)
	if msg:trim() == "" then ShowUIPanel(panel)
	else
		Save("\n; Usernote: " .. (msg or "No note") .. "|")
		SaveCoords()
	end
end


local LINEHEIGHT, maxoffset, offset = 12, 0, 0


local scroll = CreateFrame("ScrollFrame", nil, panel)
scroll:SetPoint("TOPLEFT", 21, -73)
scroll:SetPoint("BOTTOMRIGHT", -10, 38)
local HEIGHT = scroll:GetHeight()


local editbox = CreateFrame("EditBox", nil, scroll)
scroll:SetScrollChild(editbox)
editbox:SetPoint("TOP")
editbox:SetPoint("LEFT")
editbox:SetPoint("RIGHT")
editbox:SetHeight(1000)
editbox:SetFontObject(GameFontHighlightSmall)
editbox:SetTextInsets(2,2,2,2)
editbox:SetMultiLine(true)
editbox:SetAutoFocus(false)
local function SetEditbox()
	editbox:SetText(_G.TourGuide_RecorderDB:trim():gsub("|cff......|H(item:%d+):[%d:-]+|h([^|]+)|h|r", "%1 %2"):gsub("|", "||"))
	editbox:HighlightText()
end
editbox:SetScript("OnShow", function(self)
	self:SetFocus()
	SetEditbox()
end)
editbox:SetScript("OnEscapePressed", function() HideUIPanel(panel) end)
editbox:SetScript("OnTextChanged", function(self, user) if user then SetEditbox() end end)


local function doscroll(v)
	offset = max(min(v, 0), maxoffset)
	scroll:SetVerticalScroll(-offset)
	editbox:SetPoint("TOP", 0, offset)
end

editbox:SetScript("OnCursorChanged", function(self, x, y, width, height)
	LINEHEIGHT = height
	if offset < y then
		doscroll(y)
	elseif floor(offset - HEIGHT + height*2) > y then
		local v = y + HEIGHT - height*2
		maxoffset = min(maxoffset, v)
		doscroll(v)
	end
end)

scroll:UpdateScrollChildRect()
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(self, val) doscroll(offset + val*LINEHEIGHT*3) end)


StaticPopupDialogs["TOURGUIDE_RECORDER_RESET"] = {
	text = "Really erase TourGuide Recorder's log?",
	button1 = "Yes",
	button2 = "No",
	OnAccept = function() _G.TourGuide_RecorderDB = ""; SetEditbox() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local b = CreateFrame("Button", nil, panel)
b:SetPoint("TOPRIGHT", scroll, "BOTTOMRIGHT", 3, -1)
b:SetWidth(80) b:SetHeight(22)

-- Fonts --
b:SetDisabledFontObject(GameFontDisable)
b:SetHighlightFontObject(GameFontHighlight)
b:SetNormalFontObject(GameFontNormal)

-- Textures --
b:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
b:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
b:SetDisabledTexture("Interface\\Buttons\\UI-Panel-Button-Disabled")
b:GetNormalTexture():SetTexCoord(0, 0.625, 0, 0.6875)
b:GetPushedTexture():SetTexCoord(0, 0.625, 0, 0.6875)
b:GetHighlightTexture():SetTexCoord(0, 0.625, 0, 0.6875)
b:GetDisabledTexture():SetTexCoord(0, 0.625, 0, 0.6875)
b:GetHighlightTexture():SetBlendMode("ADD")

b:SetText("Clear")
b:SetScript("OnCLick", function() StaticPopup_Show("TOURGUIDE_RECORDER_RESET") end)
