
local myname, ns = ...

local accepted, currentcompletes, oldcompletes, currentquests, oldquests, currentboards, oldboards, titles, firstscan, abandoning, db = {}, {}, {}, {}, {}, {}, {}, {}, true
local qids = setmetatable({}, {
	__index = function(t,i)
		local v = tonumber(i:match("|Hquest:(%d+):"))
		t[i] = v
		return v
	end,
})


local function Debug(msg) ChatFrame6:AddMessage(tostring(msg)) end

local f = CreateFrame("frame")
f:SetScript("OnEvent", function(self, event, ...) if self[event] then return self[event](self, event, ...) end end)
f:RegisterEvent("ADDON_LOADED")


function f:ADDON_LOADED(event, addon)
	if addon ~= "TourGuide_Recorder" then return end

	TourGuide_RecorderDB = TourGuide_RecorderDB or ""

	self:UnregisterEvent("ADDON_LOADED")
	self.ADDON_LOADED = nil

	self:RegisterEvent("QUEST_LOG_UPDATE")
	self:RegisterEvent("PLAYER_LEVEL_UP")
	self:RegisterEvent("QUEST_AUTOCOMPLETE")
end


local function Save(val)
	TourGuide_RecorderDB = TourGuide_RecorderDB..val
	Debug(val:gsub("|", "||"):gsub("\n", ""))
end

local function coords()
	local x, y = GetPlayerMapPosition("player")
	return x * 100, y * 100
end

local function SaveCoords()
	local x, y = GetPlayerMapPosition("player")
	Save(string.format(" |Z|%s| |M|%.1f, %.1f|; %s", GetZoneText(), x * 100, y * 100, GetSubZoneText()))
end

function f:PLAYER_LEVEL_UP(event, level)
	Save("\n- Level up! ".. level)
end

local lastautocomplete
function f:QUEST_AUTOCOMPLETE(event, qid)
	lastautocomplete = qid
end

function f:QUEST_LOG_UPDATE()
--~ 	Debug("QUEST_LOG_UPDATE")
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

			for j=1,GetNumQuestLeaderBoards(i) do
				local text, objtype, finished = GetQuestLogLeaderBoard(j, i)
				if finished then
					currentboards[qid.."."..j] = text
				end
			end
		end
	end

	if firstscan then
	 	for qid in pairs(currentquests) do accepted[qid] = true end
		firstscan = nil
		return
	end

	for qidboard,text in pairs(currentboards) do
		if not oldboards[qidboard] and accepted[qidboard] then
			Save(string.format("\nC %s |QID|%s| |QO|%s|", title[qidboard], qidboard, text))
			SaveCoords()
		end
	end

	for qidcomplete,title in pairs(currentcompletes) do
		if not oldcompletes[qidcomplete] and accepted[qidcomplete] then
			Save(string.format("\nC %s |QID|%s|", title, qidcomplete))
			SaveCoords()
		end
	end

	for qid in pairs(oldquests) do
		if not currentquests[qid] then
			local action = abandoning and "Abandoned quest" or "Turned in quest"
			if not abandoning then Save(string.format("\nT %s |QID|%s|", titles[qid], qid)) end
			SaveCoords()
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
			Save(string.format("\nA %s |QID|%s|", titles[qid], qid))
			SaveCoords()
			return
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
		Save("\n; |U|".. link .. "|")
		SaveCoords()
	end
end)


local panel = ns.tekPanelAuction(nil, "TourGuide Recorder log")

SLASH_TGR1 = "/tgr"
function SlashCmdList.TGR(msg)
	if msg:trim() == "" then ShowUIPanel(panel)
	else
		Save("\n; Usernote: ".. (msg or "No note"))
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
	editbox:SetText(TourGuide_RecorderDB:trim():gsub("|cff......|H(item:%d+):[%d:-]+|h([^|]+)|h|r", "%1 %2"):gsub("|", "||"))
	editbox:HighlightText()
end
editbox:SetScript("OnShow", function(self)
	self:SetFocus()
	SetEditbox()
end)
editbox:SetScript("OnEscapePressed", function() HideUIPanel(panel) end)
editbox:SetScript("OnTextChanged", function(self, user) if user then SetEditbox() end end)


local function doscroll(v)
	offset = math.max(math.min(v, 0), maxoffset)
	scroll:SetVerticalScroll(-offset)
	editbox:SetPoint("TOP", 0, offset)
end

editbox:SetScript("OnCursorChanged", function(self, x, y, width, height)
	LINEHEIGHT = height
	if offset < y then
		doscroll(y)
	elseif math.floor(offset - HEIGHT + height*2) > y then
		local v = y + HEIGHT - height*2
		maxoffset = math.min(maxoffset, v)
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
	OnAccept = function() TourGuide_RecorderDB = ""; SetEditbox() end,
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
