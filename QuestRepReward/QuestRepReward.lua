-- QuestRepReward: shows reputation gains next to the other quest rewards.
--
-- Data sources, in order:
--   1. Any reputation-reward API the client exposes for the quest.
--   2. What the addon has seen you (or your alts) actually earn when turning
--      that quest in. Learned values are saved account-wide.

local ADDON = ...
local CAPTURE_WINDOW = 1.5 -- seconds around a turn-in that rep gains count

QuestRepRewardDB = QuestRepRewardDB or {}

local debug = { hookCalls = 0 } -- state shown by /qrr

QuestRepRewardDB._scale = nil -- no longer used; the API is in hundredths

-- Questie's quest database, if Questie is installed.
local function GetQuestieDB()
    if not QuestieLoader or not QuestieLoader.ImportModule then return nil end
    local ok, db = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    if ok and type(db) == "table" and type(db.QueryQuestSingle) == "function" then return db end
    return nil
end

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

local function GetLearned(questID)
    local list = {}
    local learned = questID and QuestRepRewardDB[questID]
    if type(learned) == "table" then
        for name, amount in pairs(learned) do
            if type(amount) == "number" and name:sub(1, 1) ~= "_" then
                list[#list + 1] = { name = name, amount = amount }
            end
        end
        table.sort(list, function(a, b) return a.name < b.name end)
    end
    return list
end

local function GetRepRewards(questID, isLog)
    local list = GetLearned(questID)
    if #list > 0 then return list, true end

    if isLog and C_QuestLog and C_QuestLog.GetQuestLogMajorFactionReputationRewards then
        AddApiRewards(list, C_QuestLog.GetQuestLogMajorFactionReputationRewards(questID))
    elseif not isLog and C_QuestOffer and C_QuestOffer.GetQuestOfferMajorFactionReputationRewards then
        AddApiRewards(list, C_QuestOffer.GetQuestOfferMajorFactionReputationRewards())
    end

    -- Older-style API (Forever has this): works on the selected quest-log quest
    -- and returns factionID plus the amount in hundredths.
    local inLog = questID and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
    if #list == 0 and inLog and GetNumQuestLogRewardFactions and GetQuestLogRewardFactionInfo then
        local selected = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
        local swap = selected ~= questID and C_QuestLog.SetSelectedQuest
        if swap then C_QuestLog.SetSelectedQuest(questID) end
        if ProcessQuestLogRewardFactions then ProcessQuestLogRewardFactions() end
        for i = 1, (GetNumQuestLogRewardFactions() or 0) do
            local factionID, amount = GetQuestLogRewardFactionInfo(i)
            local name = factionID and FactionName(factionID)
            if name and amount and amount ~= 0 then
                list[#list + 1] = { name = name, amount = math.floor(amount / 100 + 0.5) }
            end
        end
        if swap and selected and selected ~= 0 then C_QuestLog.SetSelectedQuest(selected) end
    end

    -- Questie's database: also covers quests that aren't in your log yet.
    if #list == 0 and questID then
        local db = GetQuestieDB()
        local ok, rep = false, nil
        if db then ok, rep = pcall(db.QueryQuestSingle, questID, "reputationReward") end
        if ok and type(rep) == "table" then
            for _, r in ipairs(rep) do
                local factionID, amount = type(r) == "table" and r[1], type(r) == "table" and r[2]
                local name = type(factionID) == "number" and FactionName(factionID)
                if name and type(amount) == "number" and amount ~= 0 then
                    list[#list + 1] = { name = name, amount = amount }
                end
            end
        end
    end

    return list, false
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local containers = {}

local function GetContainer(rewardsFrame)
    local c = containers[rewardsFrame]
    if c then return c end

    c = CreateFrame("Frame", nil, rewardsFrame)
    local small = (rewardsFrame == MapQuestInfoRewardsFrame)
    c.small = small
    -- Header copies the "You will receive:" line; the rewards are plain white text.
    c.header = c:CreateFontString(nil, "ARTWORK", small and "GameFontNormalSmall" or "QuestFont")
    c.header:SetPoint("TOPLEFT")
    c.header:SetJustifyH("LEFT")
    c.header:SetText(REPUTATION and (REPUTATION .. ":") or "Reputation:")
    local ref = rewardsFrame.ItemReceiveText
    if ref then
        c.header:SetFontObject(ref:GetFontObject())
        c.header:SetTextColor(ref:GetTextColor())
    end
    c.text = c:CreateFontString(nil, "ARTWORK", small and "GameFontHighlightSmall" or "GameFontHighlight")
    c.text:SetPoint("TOPLEFT", c.header, "BOTTOMLEFT", 0, -4)
    c.text:SetJustifyH("LEFT")
    c.text:SetWordWrap(true)
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

local function Update(rewardsFrame, questID, isLog)
    if containers[rewardsFrame] then containers[rewardsFrame]:Hide() end
    debug.lastRewardsFrame = rewardsFrame:GetName() or "unnamed"
    if not questID or questID == 0 then return end

    local rewards, learned = GetRepRewards(questID, isLog)
    debug.lastQuest, debug.lastIsLog, debug.lastCount = questID, isLog, #rewards
    if #rewards == 0 then return end

    local c = GetContainer(rewardsFrame)

    local startY = ContentBottomOffset(rewardsFrame, c) or rewardsFrame:GetHeight()
    local leftX = c.small and 8 or 0
    if rewardsFrame.ItemReceiveText then
        local l1, l2 = rewardsFrame.ItemReceiveText:GetLeft(), rewardsFrame:GetLeft()
        if l1 and l2 then leftX = l1 - l2 end
    end

    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", rewardsFrame, "TOPLEFT", leftX, -(startY + 8))
    local width = rewardsFrame:GetWidth() - leftX - 8
    c:SetWidth(width)
    c.text:SetWidth(width)

    local parts = {}
    for _, r in ipairs(rewards) do
        parts[#parts + 1] = ("%+d %s"):format(r.amount, r.name)
    end
    c.text:SetText(table.concat(parts, ", "))

    local height = c.header:GetStringHeight() + 4 + c.text:GetStringHeight()
    c:SetHeight(height)
    c:Show()
    local oldH = rewardsFrame:GetHeight()
    local newH = math.max(oldH, startY + 8 + height)
    rewardsFrame:SetHeight(newH)

    -- The map panel sizes a holder frame to fit the rewards; grow it too, or
    -- our rows end up clipped below it.
    local parent = rewardsFrame:GetParent()
    if newH > oldH and parent and parent ~= UIParent and math.abs(parent:GetHeight() - oldH) < 2 then
        parent:SetHeight(newH)
    end
end

-- Which quest a visible rewards frame belongs to.
local function QuestFor(rewardsFrame)
    local npc = QuestFrame and QuestFrame:IsShown() and rewardsFrame == QuestInfoRewardsFrame
    if npc then
        return GetQuestID and GetQuestID(), false
    end
    return C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest(), true
end

-- Forever doesn't route its quest panels through one hookable function, so we
-- simply watch the reward frames and refresh whenever what they show changes.
local state = {}
local function Check()
    for _, name in ipairs({ "MapQuestInfoRewardsFrame", "QuestInfoRewardsFrame" }) do
        local rf = _G[name]
        if rf and rf:IsVisible() then
            local questID, isLog = QuestFor(rf)
            local sig = tostring(questID) .. ":" .. math.floor(rf:GetHeight() + 0.5)
            if state[rf] ~= sig then
                debug.hookCalls = debug.hookCalls + 1
                local ok, err = pcall(Update, rf, questID, isLog)
                if not ok then
                    debug.lastError = err
                    geterrorhandler()(err)
                end
                state[rf] = tostring(questID) .. ":" .. math.floor(rf:GetHeight() + 0.5)
            end
        elseif rf then
            state[rf] = nil
        end
    end
end

-- Run inside Blizzard's own layout when it goes through QuestInfo_Display, so
-- the panels size themselves around our rows. The watcher above catches the rest.
if QuestInfo_Display then
    hooksecurefunc("QuestInfo_Display", function(template)
        local rf = QuestInfoFrame and QuestInfoFrame.rewardsFrame
        if not rf or not rf:IsShown() then return end
        local questID, isLog = QuestFor(rf)
        if template and template.questLog ~= nil and rf ~= MapQuestInfoRewardsFrame then
            isLog = template.questLog
            if isLog then
                questID = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
            else
                questID = GetQuestID and GetQuestID()
            end
        end
        debug.hookCalls = debug.hookCalls + 1
        local ok, err = pcall(Update, rf, questID, isLog)
        if not ok then
            debug.lastError = err
            geterrorhandler()(err)
        end
        state[rf] = tostring(questID) .. ":" .. math.floor(rf:GetHeight() + 0.5)
    end)
end

local watcher = CreateFrame("Frame")
local elapsed = 0
watcher:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= 0.1 then
        elapsed = 0
        Check()
    end
end)

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
    print(("|cffffd200QuestRepReward:|r learned %+d %s for quest %d"):format(amount, name, questID))
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
    debug.lastRepMsg = arg1
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

---------------------------------------------------------------------------
-- /qrr: diagnostics
---------------------------------------------------------------------------

local function P(...) print("|cffffd200QRR:|r", ...) end

SLASH_QUESTREPREWARD1 = "/qrr"
SlashCmdList.QUESTREPREWARD = function()
    local _, _, _, toc = GetBuildInfo()
    P("client interface", tostring(toc), "| updates:", debug.hookCalls,
      "| frames: map", MapQuestInfoRewardsFrame and tostring(MapQuestInfoRewardsFrame:IsVisible()) or "missing",
      "npc/log", QuestInfoRewardsFrame and tostring(QuestInfoRewardsFrame:IsVisible()) or "missing")
    P("rewards frame:", tostring(debug.lastRewardsFrame), "| last quest:", tostring(debug.lastQuest),
      "log:", tostring(debug.lastIsLog), "| rep rewards found:", tostring(debug.lastCount))
    if debug.lastError then P("|cffff4040last error:|r", tostring(debug.lastError)) end

    local n = 0
    for qid, entry in pairs(QuestRepRewardDB) do
        if type(qid) == "number" and type(entry) == "table" then
            n = n + 1
            for fname, amt in pairs(entry) do
                if type(amt) == "number" and fname:sub(1, 1) ~= "_" then P("  learned quest", qid, fname, amt) end
            end
        end
    end
    P("learned quests:", n, "| Questie DB:", GetQuestieDB() and "found" or "not found",
      "| last rep chat message:", tostring(debug.lastRepMsg))
    P("rep patterns:", #patterns, "| FACTION_STANDING_INCREASED =", tostring(FACTION_STANDING_INCREASED))

    -- Any quest/reputation reward functions this client exposes.
    local found = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "function" and k:find("Reward") and (k:find("Faction") or k:find("Reput")) then
            found[#found + 1] = k
        elseif type(k) == "string" and k:sub(1, 2) == "C_" and type(v) == "table" then
            for fk, fv in pairs(v) do
                if type(fk) == "string" and type(fv) == "function" and (fk:find("Reput") or fk:find("Faction")) and (fk:find("Reward") or fk:find("Quest")) then
                    found[#found + 1] = k .. "." .. fk
                end
            end
        end
    end
    table.sort(found)
    P("rep reward APIs:", #found > 0 and table.concat(found, ", ") or "none")

    local qid = C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    local db = qid and qid ~= 0 and GetQuestieDB()
    if db then
        local ok, rep = pcall(db.QueryQuestSingle, qid, "reputationReward")
        local parts = {}
        if ok and type(rep) == "table" then
            for _, r in ipairs(rep) do
                if type(r) == "table" then parts[#parts + 1] = tostring(r[1]) .. "=" .. tostring(r[2]) end
            end
        end
        P("Questie rep for", qid, ok and (#parts > 0 and table.concat(parts, ", ") or "none") or ("error: " .. tostring(rep)))
    end
    if qid and qid ~= 0 and GetNumQuestLogRewardFactions then
        P("selected quest", qid, "GetNumQuestLogRewardFactions =", tostring(GetNumQuestLogRewardFactions()))
        for i = 1, (GetNumQuestLogRewardFactions() or 0) do
            local fid, amt = GetQuestLogRewardFactionInfo(i)
            P("  faction reward", i, tostring(fid), FactionName(fid or 0) or "?", tostring(amt))
        end
    end
end
