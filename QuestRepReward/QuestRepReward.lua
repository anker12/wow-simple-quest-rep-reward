-- QuestRepReward: shows reputation gains next to the other quest rewards.
--
-- Data sources, in order:
--   1. Any reputation-reward API the client exposes for the quest.
--   2. What the addon has seen you (or your alts) actually earn when turning
--      that quest in. Learned values are saved account-wide.

local ADDON = ...
local ICON = "Interface\\Icons\\Achievement_Reputation_01"
local CAPTURE_WINDOW = 1.5 -- seconds around a turn-in that rep gains count

QuestRepRewardDB = QuestRepRewardDB or {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function FactionName(factionID)
    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local data = C_MajorFactions.GetMajorFactionData(factionID)
        if data and data.name then return data.name end
    end
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local data = C_Reputation.GetFactionDataByID(factionID)
        if data and data.name then return data.name end
    end
    if GetFactionInfoByID then
        local name = GetFactionInfoByID(factionID)
        if name then return name end
    end
    return nil
end

local function AddApiRewards(list, rewards)
    if type(rewards) ~= "table" then return end
    for _, r in ipairs(rewards) do
        local name = r.factionID and FactionName(r.factionID)
        if name and r.rewardAmount and r.rewardAmount ~= 0 then
            list[#list + 1] = { name = name, amount = r.rewardAmount }
        end
    end
end

local function GetRepRewards(questID, isLog)
    local list = {}

    if isLog and C_QuestLog and C_QuestLog.GetQuestLogMajorFactionReputationRewards then
        AddApiRewards(list, C_QuestLog.GetQuestLogMajorFactionReputationRewards(questID))
    elseif not isLog and C_QuestOffer and C_QuestOffer.GetQuestOfferMajorFactionReputationRewards then
        AddApiRewards(list, C_QuestOffer.GetQuestOfferMajorFactionReputationRewards())
    end

    if #list == 0 and questID then
        local learned = QuestRepRewardDB[questID]
        if learned then
            for name, amount in pairs(learned) do
                if type(amount) == "number" and name:sub(1, 1) ~= "_" then
                    list[#list + 1] = { name = name, amount = amount }
                end
            end
            table.sort(list, function(a, b) return a.name < b.name end)
        end
    end

    return list
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local containers = {}

local function CreateRewardButton(parent, small)
    local template = small and "SmallItemButtonTemplate" or "LargeItemButtonTemplate"
    local ok, b = pcall(CreateFrame, "Button", nil, parent, template)
    if not ok or not b or not b.Icon or not b.Name then
        -- Fallback: build the classic quest reward look by hand.
        local size = small and 26 or 39
        b = CreateFrame("Button", nil, parent)
        b:SetSize(small and 140 or 147, size + 2)
        b.Icon = b:CreateTexture(nil, "ARTWORK")
        b.Icon:SetSize(size, size)
        b.Icon:SetPoint("TOPLEFT")
        b.NameFrame = b:CreateTexture(nil, "BACKGROUND")
        b.NameFrame:SetTexture("Interface\\QuestFrame\\UI-QuestItemNameFrame")
        b.NameFrame:SetSize(small and 100 or 128, small and 40 or 64)
        b.NameFrame:SetPoint("LEFT", b.Icon, "RIGHT", -10, 0)
        b.Name = b:CreateFontString(nil, "ARTWORK", small and "GameFontHighlightSmall" or "GameFontHighlight")
        b.Name:SetSize(small and 90 or 90, size)
        b.Name:SetPoint("LEFT", b.NameFrame, "LEFT", 15, 0)
        b.Name:SetJustifyH("LEFT")
    end
    if b.Count then b.Count:Hide() end
    b.Icon:SetTexture(ICON)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.factionName or "", 1, 1, 1)
        GameTooltip:AddLine(("%+d reputation"):format(self.amount or 0), 0, 1, 0)
        if self.learned then
            GameTooltip:AddLine("Learned from a previous turn-in.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", nil)
    return b
end

local function GetContainer(rewardsFrame)
    local c = containers[rewardsFrame]
    if c then return c end

    c = CreateFrame("Frame", nil, rewardsFrame)
    c.small = (rewardsFrame == MapQuestInfoRewardsFrame)
    c.buttons = {}
    c.header = c:CreateFontString(nil, "ARTWORK", c.small and "GameFontNormalSmall" or "QuestFont")
    c.header:SetPoint("TOPLEFT")
    c.header:SetText(REPUTATION and (REPUTATION .. ":") or "Reputation:")
    local ref = rewardsFrame.ItemReceiveText
    if ref then
        c.header:SetFontObject(ref:GetFontObject())
        c.header:SetTextColor(ref:GetTextColor())
    end
    containers[rewardsFrame] = c
    return c
end

-- Lowest visible point of the rewards frame's content, as a distance from its top.
local function ContentBottomOffset(rewardsFrame, ignore)
    local top = rewardsFrame:GetTop()
    if not top then return nil end
    local lowest = 0
    local function consider(obj)
        if obj ~= ignore and obj:IsShown() then
            local bottom = obj:GetBottom()
            if bottom then lowest = math.max(lowest, top - bottom) end
        end
    end
    for _, child in ipairs({ rewardsFrame:GetChildren() }) do consider(child) end
    for _, region in ipairs({ rewardsFrame:GetRegions() }) do
        if region:GetObjectType() == "FontString" then consider(region) end
    end
    return lowest
end

local function Update(template)
    for _, c in pairs(containers) do c:Hide() end

    local rewardsFrame = QuestInfoFrame and QuestInfoFrame.rewardsFrame
    if not rewardsFrame or not rewardsFrame:IsShown() then return end

    local isLog = template and template.questLog
    local questID
    if isLog then
        questID = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    else
        questID = GetQuestID and GetQuestID()
    end
    if not questID or questID == 0 then return end

    local rewards = GetRepRewards(questID, isLog)
    if #rewards == 0 then return end

    local c = GetContainer(rewardsFrame)
    local learned = QuestRepRewardDB[questID] ~= nil

    local startY = ContentBottomOffset(rewardsFrame, c) or rewardsFrame:GetHeight()
    local leftX = c.small and 8 or 0
    if rewardsFrame.ItemReceiveText then
        local l1, l2 = rewardsFrame.ItemReceiveText:GetLeft(), rewardsFrame:GetLeft()
        if l1 and l2 then leftX = l1 - l2 end
    end

    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", rewardsFrame, "TOPLEFT", leftX, -(startY + 8))
    c:SetWidth(rewardsFrame:GetWidth() - leftX)

    local headerH = c.header:GetStringHeight() + 6
    local colW = math.floor((rewardsFrame:GetWidth() - leftX) / 2)
    local rowH
    for i, r in ipairs(rewards) do
        local b = c.buttons[i] or CreateRewardButton(c, c.small)
        c.buttons[i] = b
        b.factionName, b.amount, b.learned = r.name, r.amount, learned
        local sign = r.amount > 0 and "|cff00ff00+" or "|cffff2020"
        b.Name:SetText(r.name .. "\n" .. sign .. r.amount .. "|r")
        rowH = rowH or (b:GetHeight() + 4)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", c, "TOPLEFT", col * colW, -(headerH + row * rowH))
        b:Show()
    end
    for i = #rewards + 1, #c.buttons do c.buttons[i]:Hide() end

    local height = headerH + math.ceil(#rewards / 2) * rowH
    c:SetHeight(height)
    c:Show()
    rewardsFrame:SetHeight(math.max(rewardsFrame:GetHeight(), startY + 8 + height))
end

if QuestInfo_Display then
    hooksecurefunc("QuestInfo_Display", function(template)
        local ok, err = pcall(Update, template)
        if not ok then geterrorhandler()(err) end
    end)
end

---------------------------------------------------------------------------
-- Learning rep gains from turn-ins
---------------------------------------------------------------------------

local patterns = {}
local function AddPattern(fmt)
    if type(fmt) ~= "string" then return end
    -- Turn a format string like "Reputation with %s increased by %d." into a
    -- Lua pattern that captures the faction name and the amount.
    local p = fmt:gsub("%%%d*%$?([sdf])", "\001%1")          -- mark specifiers
    p = p:gsub("%%[%d%.]+f", "\001f")
    p = p:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")          -- escape the rest
    p = p:gsub("\001s", "(.-)"):gsub("\001d", "([%%d,%%.]+)"):gsub("\001f", "[%%d%%.,]+")
    patterns[#patterns + 1] = "^" .. p .. "$"
end
AddPattern(FACTION_STANDING_INCREASED_ACH_BONUS)
AddPattern(FACTION_STANDING_INCREASED_BONUS)
AddPattern(FACTION_STANDING_INCREASED_DOUBLE_BONUS)
AddPattern(FACTION_STANDING_INCREASED)
local decreasePatterns = {}
do
    local before = #patterns
    AddPattern(FACTION_STANDING_DECREASED)
    for i = before + 1, #patterns do
        decreasePatterns[patterns[i]] = true
    end
end

local recentGains = {}   -- { time, name, amount }
local pendingQuest, pendingTime

local function Record(questID, name, amount)
    local entry = QuestRepRewardDB[questID]
    if not entry or entry._time ~= pendingTime then
        entry = { _time = pendingTime }
        QuestRepRewardDB[questID] = entry
    end
    entry[name] = (entry[name] or 0) + amount
end

local function Finish()
    local entry = pendingQuest and QuestRepRewardDB[pendingQuest]
    if entry then entry._time = nil end
    pendingQuest, pendingTime = nil, nil
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
f:RegisterEvent("QUEST_TURNED_IN")
f:SetScript("OnEvent", function(_, event, arg1)
    local now = GetTime()
    if event == "QUEST_TURNED_IN" then
        if pendingQuest then Finish() end
        pendingQuest, pendingTime = arg1, now
        -- Rep messages can arrive just before the turn-in event.
        for _, g in ipairs(recentGains) do
            if now - g.time <= CAPTURE_WINDOW then Record(pendingQuest, g.name, g.amount) end
        end
        wipe(recentGains)
        C_Timer.After(CAPTURE_WINDOW, function()
            if pendingTime == now then Finish() end
        end)
        return
    end

    -- CHAT_MSG_COMBAT_FACTION_CHANGE
    if issecretvalue and issecretvalue(arg1) then return end
    if type(arg1) ~= "string" then return end
    for _, p in ipairs(patterns) do
        local ok, name, amount = pcall(string.match, arg1, p)
        if ok and name and amount then
            amount = tonumber((amount:gsub("[,%.]", "")))
            if decreasePatterns[p] then amount = -amount end
            if pendingQuest and now - pendingTime <= CAPTURE_WINDOW then
                Record(pendingQuest, name, amount)
            else
                recentGains[#recentGains + 1] = { time = now, name = name, amount = amount }
                while #recentGains > 10 do table.remove(recentGains, 1) end
            end
            return
        end
    end
end)
