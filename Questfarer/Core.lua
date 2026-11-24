-- Questfarer - Core
-- License: GNU GPL v3 (see LICENSE.md). Quest data from QuestieDB, see README credits.

local ADDON, ns = ...
local QF = {}
ns.QF = QF
_G.Questfarer = QF

QF.version = "0.9.0-beta"
QF.guides = {}
QF.guideOrder = {}
QF.steps = {}         -- current guide's steps, filtered for this character

-- Classic map IDs on Forever, not retail
QF.MAP = {
    ELWYNN = 1429,
    STORMWIND = 1453,
    WESTFALL = 1436,
    REDRIDGE = 1433,
    DUSKWOOD = 1431,
    LOCHMODAN = 1432,
    DUNMOROGH = 1426,
    IRONFORGE = 1455,
}

local DEFAULTS = {
    autoAccept = true,
    autoTurnin = true,
    autoFlight = true,
    autoGossip = true,
    waypoint = true,
    arrow = true,
    autoTrain = false,
    trainReminder = true,
    rewardHint = true,
    checkpoints = true,
    itemButton = true,
    targetButton = true,
    mapAreas = true,
    autoSell = true,
    autoRepair = true,
    fullWarning = true,
    talentHint = true,
    gearHint = true,
    paths = {},
    record = true,
    combatLog = false,
    contribute = false,    -- opt-in
    contribution = {},     -- per character, random IDs, no names
    debug = false,
    locked = false,
    shown = true,
    scale = 1,
    width = 340,
    alpha = 0.92,
    theme = "dark",        -- or "light"
    upcoming = 2,          -- steps listed under the current one
    rpPopups = true,       -- journal notes above the guide window
    collapsed = false,
    optionsTab = "guide",
    -- saved positions { point, relativePoint, x, y }, nil = default place
    point = nil,           -- guide window
    arrowPoint = nil,
    buttonsPoint = nil,
    optionsPoint = nil,
}

local CHAR_DEFAULTS = {
    guide = nil,
    step = 1,
    lastTrainLevel = 0,
    doneIds = {},     -- questID -> true, seen via turn-in event
    doneTitles = {},  -- lower(title) -> true
    sideReturn = nil,    -- { guide, step } to go back to after a class quest
    sideHidden = {},
    sideNotified = {},
    levelTime = {},      -- level -> seconds played
    guideTime = {},      -- guide name -> seconds played
    gearIgnored = {},
    contribId = nil,
}

local function copyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                copyDefaults(dst[k], v)
            else
                dst[k] = v
            end
        end
    end
    return dst
end

function QF:Print(...)
    print("|cff33ccffQuestfarer:|r", ...)
end

function QF:Debug(...)
    if self.db and self.db.debug then
        print("|cff888888QF debug:|r", ...)
    end
end

-- first line as headline, rest indented
function QF:PrintLines(lines)
    for i, line in ipairs(lines) do
        if i == 1 then self:Print(line) else print("  " .. line) end
    end
end

-- Guide registration

-- guide = { name=, faction=, races={...}, minLevel=, maxLevel=, next=, steps={...} }
-- bar def = { icon =, color = {r, g, b}, text = function() -> string or nil, onClick = function(button), tooltip = function(tip) }
QF.bars = {}
function QF:AddBar(def)
    table.insert(self.bars, def)
end

function QF:RegisterGuide(guide)
    assert(type(guide) == "table" and guide.name and guide.steps, "Questfarer: invalid guide")
    if not self.guides[guide.name] then
        table.insert(self.guideOrder, guide.name)
    end
    self.guides[guide.name] = guide
end

local function listHas(list, value)
    if not list then return true end
    if type(list) == "string" then return list == value end
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

function QF:StepApplies(step)
    if step.class and not listHas(step.class, self.player.class) then return false end
    if step.race and not listHas(step.race, self.player.race) then return false end
    if step.notclass and listHas(step.notclass, self.player.class) then return false end
    return true
end

function QF:GuideApplies(guide)
    if guide.faction and guide.faction ~= self.player.faction then return false end
    if guide.races and not listHas(guide.races, self.player.race) then return false end
    if guide.class and not listHas(guide.class, self.player.class) then return false end
    return true
end

function QF:DefaultGuide()
    local level = UnitLevel("player")
    for _, name in ipairs(self.guideOrder) do
        local g = self.guides[name]
        if not g.side and self:GuideApplies(g) and (not g.maxLevel or level < g.maxLevel) then
            return name
        end
    end
    return self.guideOrder[1]
end

function QF:LoadGuide(name, stepIndex)
    local guide = self.guides[name]
    if not guide then
        self:Print("No guide found named: " .. tostring(name))
        return
    end
    local sideChanged = guide.side or (self.guide and self.guide.side)
    self.guide = guide
    if sideChanged then self:BuildWhitelist() end
    self.holdStep = nil
    self.noGuideForLevel = nil
    wipe(self.steps)
    for _, step in ipairs(guide.steps) do
        step.manualDone = nil
        if self:StepApplies(step) then
            self:PrepareStep(step, guide)
            self:ResolveTrainer(step)
            table.insert(self.steps, step)
        end
    end
    -- class quests come back to a picked guide, anything else ends the pick
    if not guide.side and self.char.picked ~= name then self.char.picked = nil end
    self.char.guide = name
    self.char.step = math.max(1, math.min(stepIndex or 1, #self.steps + 1))
    self.lastShownStep = nil
    self:RequestUpdate()
end

-- Whitelist for auto-accept/turn-in

-- titles several quests share go by quest ID only, else one turn-in marks every later part done
function QF:BuildSharedTitles()
    local firstId, shared = {}, {}
    local function note(id, title)
        if type(id) ~= "number" or type(title) ~= "string" then return end
        local key = title:lower()
        if firstId[key] and firstId[key] ~= id then shared[key] = true end
        firstId[key] = firstId[key] or id
    end
    for _, name in ipairs(self.guideOrder) do
        local g = self.guides[name]
        if self:GuideApplies(g) then
            for _, step in ipairs(g.steps) do
                if self:StepApplies(step) then
                    note(step.accept, step.title)
                    note(step.turnin, step.title)
                    if type(step.complete) == "table" then
                        for i, id in ipairs(step.complete) do note(id, step.titles and step.titles[i]) end
                    else
                        note(step.complete, step.title)
                    end
                end
            end
        end
    end
    self.sharedTitles = shared
end

function QF:TitleIsShared(title)
    if not title or not self.player then return false end
    if not self.sharedTitles then self:BuildSharedTitles() end
    return self.sharedTitles[title:lower()] == true
end

function QF:BuildWhitelist()
    self.acceptIds, self.acceptTitles = {}, {}
    self.turninIds, self.turninTitles = {}, {}
    self.acceptAnyTitle, self.turninAnyTitle = {}, {} -- for events that give no quest ID
    self.acceptStep = {} -- questID -> accept step
    for _, name in ipairs(self.guideOrder) do
        local g = self.guides[name]
        -- class quests only while active, so talking to the trainer doesn't start one
        if self:GuideApplies(g) and (not g.side or g == self.guide) then
            for _, step in ipairs(g.steps) do
                if self:StepApplies(step) then
                    self:PrepareStep(step, g)
                    if step.type == "accept" then
                        if step.qid then
                            self.acceptIds[step.qid] = true
                            self.acceptStep[step.qid] = step
                        end
                        if step.qtitle then self.acceptTitles[step.qtitle:lower()] = true end
                        if step.title then self.acceptAnyTitle[step.title:lower()] = true end
                    elseif step.type == "turnin" then
                        if step.qid then self.turninIds[step.qid] = true end
                        if step.qtitle then self.turninTitles[step.qtitle:lower()] = true end
                        if step.title then self.turninAnyTitle[step.title:lower()] = true end
                    end
                end
            end
        end
    end
end

function QF:WantsAccept(questID, title)
    -- skipped by the route, don't auto-accept
    local s = questID and self.acceptStep and self.acceptStep[questID]
    if s and (s.obsolete or (s.optional and s.manualDone)) then return false end
    if questID and self.acceptIds[questID] then return true end
    if title and self.acceptTitles[title:lower()] then return true end
    if title and (not questID or questID == 0) and self.acceptAnyTitle[title:lower()] then return true end
    return false
end

function QF:WantsTurnin(questID, title)
    if questID and self.turninIds[questID] then return true end
    if title and self.turninTitles[title:lower()] then return true end
    if title and (not questID or questID == 0) and self.turninAnyTitle[title:lower()] then return true end
    return false
end

-- Quest helpers

QF.titleCache = {}

function QF:CacheQuestLog()
    local n = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.title then
            self.titleCache[info.questID] = info.title
        end
    end
end

-- lower-case title -> quest ID
function QF:ReadLogTitles()
    local titles = {}
    local n = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.title then
            local lt = info.title:lower()
            titles[lt] = titles[lt] or info.questID
        end
    end
    return titles
end

function QF:FindInLog(questID, title)
    if questID and C_QuestLog.GetLogIndexForQuestID(questID) then
        return questID
    end
    if title then
        local lt = title:lower()
        if self.logTitles then return self.logTitles[lt] end -- set while planning the route
        local n = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, n do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.title and info.title:lower() == lt then
                return info.questID
            end
        end
    end
    return nil
end

function QF:IsTurnedIn(questID, title)
    if questID then
        if C_QuestLog.IsQuestFlaggedCompleted(questID) then return true end
        if self.char.doneIds[questID] then return true end
    end
    if title and self.char.doneTitles[title:lower()] then return true end
    return false
end

function QF:IsQuestObjectivesDone(questID, title)
    if self:IsTurnedIn(questID, title) then return true end
    local id = self:FindInLog(questID, title)
    if not id then return false end
    if C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) then return true end
    -- Forever's complete flag can lag behind or miss finished objectives
    local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
    if objs and #objs > 0 then
        for _, o in ipairs(objs) do
            if not o.finished then return false end
        end
        return true
    end
    local idx = C_QuestLog.GetLogIndexForQuestID(id)
    if idx and GetQuestLogTitle then
        local isComplete = select(6, GetQuestLogTitle(idx)) -- 1 = complete, -1 = failed
        if isComplete == 1 or isComplete == true then return true end
    end
    return false
end

-- failed quests stay in the log until abandoned
function QF:QuestFailed(questID, title)
    local id = self:FindInLog(questID, title)
    if not id then return false end
    if C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) then return true end
    local idx = C_QuestLog.GetLogIndexForQuestID(id)
    if idx and GetQuestLogTitle then
        return select(6, GetQuestLogTitle(idx)) == -1
    end
    return false
end

-- seconds until hearth is ready, nil or 0 = ready or unknown
function QF:HearthCooldown()
    local getCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not getCooldown then return nil end
    local ok, start, duration = pcall(getCooldown, 6948)
    if not ok then return nil end
    -- secret values on Forever, treat as unknown
    if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then return nil end
    if start and duration and start > 0 and duration > 2 then
        return math.max(0, start + duration - GetTime())
    end
    return 0
end

function QF:QuestTitle(questID, fallback)
    return fallback
        or (questID and (self.titleCache[questID] or C_QuestLog.GetTitleForQuestID(questID)))
        or ("Quest #" .. tostring(questID))
end

-- Update / auto-advance

function QF:CurrentStep()
    return self.steps[self.char.step]
end

function QF:RequestUpdate()
    if self.updatePending then return end
    self.updatePending = true
    C_Timer.After(0.15, function()
        self.updatePending = false
        self:Update()
    end)
end

function QF:Update()
    if not self.guide then return end
    local i = self.char.step
    local guard = 0
    -- holdStep: user went back here, stay until they click Next
    while self.steps[i] and i ~= self.holdStep and self:IsStepDone(self.steps[i]) and guard < 500 do
        i = i + 1
        guard = guard + 1
    end
    self.char.step = i

    if i > #self.steps and self.guide.side then
        self.ClassQuests:OnFinished()
        return
    end
    if i > #self.steps then
        local nextName = self.guide.next
        if nextName and self.guides[nextName] then
            self:Print("Finished |cffffd100" .. self.guide.name .. "|r! Next: |cffffd100" .. nextName .. "|r")
            self:LoadGuide(nextName, 1)
            return
        end
    end

    if self.lastShownStep ~= i then
        self.lastShownStep = i
        self:OnStepChanged()
    end
    if self.UI then self.UI:Refresh() end
end

function QF:OnStepChanged()
    self.flightTaken = false
    if self.Paths then self.Paths:OnStepChanged() end
    local step = self:CurrentStep()
    self:SetWaypointForStep(step)
    if step and self.db.debug then
        self:Debug("Step", self.char.step, step.type, self:StepText(step))
    end
    local skippedLine = step and self.SkippedLine and self:SkippedLine(step)
    if skippedLine then
        self:Print((skippedLine:gsub("^|cffff6666%s*", "|cffff6666")))
    end
    if step and step.type ~= "note" then
        PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_SELECT or 857)
    end
end

-- for steps that can't detect themselves (note/getfp/fly/hearth/train)
function QF:CompleteCurrent()
    local step = self:CurrentStep()
    if not step then return end
    step.manualDone = true
    self:RequestUpdate()
end

function QF:Skip()
    local step = self:CurrentStep()
    if not step then return end
    step.manualDone = true
    if step.type == "train" then
        -- stop reminding for this level
        self.char.lastTrainLevel = UnitLevel("player")
    end
    self.holdStep = nil
    self.char.step = self.char.step + 1
    self:Update()
end

function QF:Back()
    if self.char.step <= 1 then return end
    local i = self.char.step - 1
    local s = self.steps[i]
    if s then s.manualDone = nil end
    self.char.step = i
    -- only hold a step that's already done, an undone one must still advance by itself
    self.holdStep = (s and self:IsStepDone(s)) and i or nil
    self:Update()
end

-- Waypoints

function QF:SetWaypointForStep(step)
    if not self.db.waypoint then return end
    if not (C_Map and C_Map.SetUserWaypoint) then return end
    if step and step.x and step.y and step.map and C_Map.CanSetUserWaypointOnMap(step.map) then
        local point = UiMapPoint.CreateFromCoordinates(step.map, step.x / 100, step.y / 100)
        C_Map.SetUserWaypoint(point)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    elseif C_Map.ClearUserWaypoint then
        C_Map.ClearUserWaypoint()
    end
end

-- yards, nil if unknown
function QF:DistanceTo(step)
    if not (step and step.x and step.y and step.map) then return nil end
    local pos = C_Map.GetPlayerMapPosition(step.map, "player")
    if not pos then return nil end
    local px, py = pos:GetXY()
    if not px or (px == 0 and py == 0) then return nil end
    if not C_Map.GetWorldPosFromMapPos then return nil end
    local c1, w1 = C_Map.GetWorldPosFromMapPos(step.map, CreateVector2D(px, py))
    local c2, w2 = C_Map.GetWorldPosFromMapPos(step.map, CreateVector2D(step.x / 100, step.y / 100))
    if not (w1 and w2) or c1 ~= c2 then return nil end
    local dx, dy = w1.x - w2.x, w1.y - w2.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Trainer reminder

function QF:NeedsTraining()
    if self.NewTrainableSpells and self:HasSpellData() then
        local list = self:NewTrainableSpells()
        return list ~= nil and #list > 0
    end
    -- no spell data: assume new spells every even level
    local level = UnitLevel("player")
    if level < 2 then return false end
    local trainLevel = level - (level % 2)
    return (self.char.lastTrainLevel or 0) < trainLevel
end

-- Events

local frame = CreateFrame("Frame")
QF.eventFrame = frame
QF.handlers = {}

function QF:On(event, fn)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
        return -- event doesn't exist on this client
    end
    self.handlers[event] = self.handlers[event] or {}
    table.insert(self.handlers[event], fn)
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then
        print("|cff33ccffQuestfarer:|r could not register event " .. event)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = QF.handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, QF, event, ...)
        if not ok then
            QF:Print("|cffff4444Error in " .. event .. ":|r " .. tostring(err))
        end
    end
end)

QF:On("ADDON_LOADED", function(self, _, name)
    if name ~= ADDON then return end
    QuestfarerDB = copyDefaults(QuestfarerDB or {}, DEFAULTS)
    QuestfarerCharDB = copyDefaults(QuestfarerCharDB or {}, CHAR_DEFAULTS)
    self.db = QuestfarerDB
    self.char = QuestfarerCharDB
    self.W.SetTheme(self.db.theme)
end)

QF:On("PLAYER_LOGIN", function(self)
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    self.player = {
        class = class,
        race = race,
        faction = UnitFactionGroup("player"),
    }
    self.waypointApplied = self.db.waypoint
    self:BuildWhitelist()
    self:CacheQuestLog()
    if self.UI then self.UI:Create() end

    local name = self.char.guide
    if not (name and self.guides[name]) then
        name = self:DefaultGuide()
    end
    if name then
        self:LoadGuide(name, self.char.step)
        self:Print("Loaded |cffffd100" .. name .. "|r. Type |cffffd100/qf help|r for commands.")
    else
        self:Print("No guide fits your character yet.")
    end
    C_Timer.NewTicker(0.5, function() self:Tick() end)
end)

function QF:Tick()
    local step = self:CurrentStep()
    if not step then return end
    if step.type == "hearth" or ((step.type == "go" or step.type == "fly") and self:IsStepDone(step)) then
        self:RequestUpdate()
    end
    if self.UI then self.UI:RefreshDistance() end
end

QF:On("QUEST_LOG_UPDATE", function(self)
    self:CacheQuestLog()
    self:RequestUpdate()
end)

QF:On("QUEST_ACCEPTED", function(self, _, questID)
    if questID then
        local title = C_QuestLog.GetTitleForQuestID(questID)
        if title then self.titleCache[questID] = title end
        self:Debug("Accepted:", questID, title)
    end
    self:RequestUpdate()
end)

QF:On("QUEST_TURNED_IN", function(self, _, questID)
    if questID then
        self.char.doneIds[questID] = true
        local title = self.titleCache[questID] or self.lastCompleteTitle
        if title then self.char.doneTitles[title:lower()] = true end
        self:Debug("Turned in:", questID, title)
    end
    self:RequestUpdate()
end)

QF:On("QUEST_REMOVED", function(self) self:RequestUpdate() end)
QF:On("UNIT_QUEST_LOG_CHANGED", function(self) self:RequestUpdate() end)

QF:On("PLAYER_LEVEL_UP", function(self, _, level)
    self:RequestUpdate()
    -- with spell data the exact list gets printed instead
    local hasData = self.HasSpellData and self:HasSpellData()
    if not hasData and self.db.trainReminder and level and level >= 2 and level % 2 == 0 then
        self:Print("Level " .. level .. "! |cff00ff00New spells are available at your class trainer.|r")
    end
end)

QF:On("PLAYER_XP_UPDATE", function(self)
    local ui = self.UI
    if not (ui and self.char) then return end
    local step = self:CurrentStep()
    if step and step.type == "level" then
        ui:Refresh() -- level step shows XP
    elseif ui.frame and ui.frame:IsShown() and not self.db.collapsed then
        ui:RefreshXP()
    end
end)

QF:On("HEARTHSTONE_BOUND", function(self) self:RequestUpdate() end)

QF:On("UNIT_SPELLCAST_SUCCEEDED", function(self, _, unit, _, spellID)
    if unit ~= "player" then return end
    local step = self:CurrentStep()
    if step and step.type == "hearth" and (spellID == 8690 or spellID == 6948) then
        self:CompleteCurrent()
    end
end)

QF:On("PLAYER_CONTROL_LOST", function(self)
    C_Timer.After(0.5, function() self:RequestUpdate() end)
end)

QF:On("ZONE_CHANGED_NEW_AREA", function(self) self:RequestUpdate() end)

-- Settings

function QF:ApplyWaypointSetting()
    if self.db.waypoint == self.waypointApplied then return end
    self.waypointApplied = self.db.waypoint
    if self.db.waypoint then
        self:SetWaypointForStep(self:CurrentStep())
    elseif C_Map and C_Map.ClearUserWaypoint then
        C_Map.ClearUserWaypoint()
    end
end

function QF:SettingsChanged()
    if self.UI then self.UI:ApplySettings() end
    if self.Arrow then self.Arrow:ApplySettings() end
    if self.Buttons then self.Buttons:Update() end
    if self.MapAreas then self.MapAreas:RefreshWorldMap() end
    if self.char then self:ApplyWaypointSetting() end
    if self.Rewards and not self.db.rewardHint then self.Rewards:Clear() end
    if self.Gear and not self.db.gearHint then self.Gear:ClearRewards() end
    if self.Recorder then self.Recorder:ApplyCombatLog() end
    if self.Options then self.Options:Update() end
    self:RequestUpdate()
end

-- which: "guide", "arrow", "buttons", or nil for all
function QF:ResetPosition(which)
    if not which or which == "guide" then self.db.point = nil end
    if not which or which == "arrow" then self.db.arrowPoint = nil end
    if not which or which == "buttons" then
        self.db.buttonsPoint = nil
        if self.Buttons then self.Buttons:ApplyPosition() end
    end
    self:SettingsChanged()
end

-- same table (it's the saved variable), learned data and progress are kept
function QF:ResetSettings()
    for key, value in pairs(DEFAULTS) do
        if type(value) ~= "table" then self.db[key] = value end
    end
    self.db.optionsPoint = nil
    self:ResetPosition()
end

-- a guide chosen by hand: start where the quests say, and stay in it over the level choice
function QF:PickGuide(name)
    if not self.guides[name] then
        self:Print("No guide found named: " .. tostring(name))
        return
    end
    self:CacheQuestLog()
    local _, step = self:FindStart(name)
    self:LoadGuide(name, step or 1)
    self.char.picked = name
end

-- all: forget the picked guide and choose by level again
function QF:FindMyStep(all)
    if all then self.char.picked = nil end
    self:CacheQuestLog()
    local moved, noGuide = self:Resync(true, false)
    if not moved and not noGuide and self.guide then
        self:Print("You are already at the right step.")
    end
end

function QF:RestartGuide()
    if self.guide then self:LoadGuide(self.guide.name, 1) end
end

-- Slash commands

local function onoff(v) return v and "|cff00ff00ON|r" or "|cffff4444OFF|r" end

local TOGGLES = {
    accept = "autoAccept",
    turnin = "autoTurnin",
    flight = "autoFlight",
    gossip = "autoGossip",
    waypoint = "waypoint",
    arrow = "arrow",
    checkpoints = "checkpoints",
    train = "autoTrain",
    reminder = "trainReminder",
    reward = "rewardHint",
    record = "record",
    combatlog = "combatLog",
    share = "contribute",
    debug = "debug",
    lock = "locked",
}

local TOGGLE_HELP = {
    accept = "accept guide quests automatically",
    turnin = "turn in guide quests automatically",
    flight = "take the step's flight automatically",
    gossip = "pick flight master and trainer dialogue options",
    waypoint = "map pin on the current step",
    arrow = "the on-screen guide arrow",
    checkpoints = "arrow goes via zone crossings and checkpoints",
    train = "train all spells when the trainer window opens",
    reminder = "reminder when new spells can be trained",
    reward = "mark the quest reward that sells for the most",
    record = "record game data for checking the guides",
    combatlog = "turn the combat log on when you log in",
    share = "count fights and XP so you can share them (see /qf export)",
    debug = "debug messages in chat",
    lock = "lock the window positions",
}

local COMMANDS = {
    { "/qf", "show or hide the guide window" },
    { "/qf options", "open the settings window (also: gear icon on the guide window)" },
    { "/qf help", "list all commands" },
    { "/qf skip | back", "next / previous step" },
    { "/qf fix", "go back to a skipped step the current step needs" },
    { "/qf class [nr|stop]", "class quests: list, start one, or go back to the route" },
    { "/qf cp", "skip the arrow's current checkpoint" },
    { "/qf time", "how long your levels have taken" },
    { "/qf journal", "open the travel journal" },
    { "/qf talents", "your talent plan" },
    { "/qf paths [reset]", "learned zone crossings and paths (reset: forget them)" },
    { "/qf guides", "list guides" },
    { "/qf load <nr>", "switch to guide number <nr> and stay in it" },
    { "/qf reset", "restart the current guide" },
    { "/qf resync", "jump to the right step from your quests" },
    { "/qf resync all", "pick the guide by level again" },
    { "/qf spells", "list the spells you can train right now" },
    { "/qf recstats", "show how much game data has been recorded" },
    { "/qf export", "make the text for sharing your data with the guide makers" },
    { "/qf where", "print your position (for writing guides)" },
    { "/qf bounds [mapIDs]", "print a map's world bounds (for the route tools)" },
    { "/qf scale <0.5-2>", "window size" },
}

-- { command, description, setting key (toggles only) }
function QF:CommandList()
    local list = {}
    for _, c in ipairs(COMMANDS) do table.insert(list, c) end
    local names = {}
    for name in pairs(TOGGLES) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        table.insert(list, { "/qf " .. name, "toggle: " .. TOGGLE_HELP[name], TOGGLES[name] })
    end
    return list
end

function QF:PrintHelp()
    self:Print("Commands:")
    for _, c in ipairs(self:CommandList()) do
        local state = c[3] and (" (now " .. onoff(self.db[c[3]]) .. ")") or ""
        print(("  %-20s - %s%s"):format(c[1], c[2], state))
    end
    print("  Hold |cffffd100Shift|r while talking to an NPC to pause the automation.")
end

-- numbers match /qf load <nr>
function QF:GuideLines()
    local lines = {}
    for i, name in ipairs(self.guideOrder) do
        if not self.guides[name].side then
            local cur = (self.guide and self.guide.name == name) and " |cff00ff00(active)|r" or ""
            table.insert(lines, ("%d. %s%s"):format(i, name, cur))
        end
    end
    return lines
end

function QF:WhereLines()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return { "Unknown position." } end
    local info = C_Map.GetMapInfo(mapID)
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y = 0, 0
    if pos then x, y = pos:GetXY() end
    return {
        ("%s (map=%d)  x=%.1f, y=%.1f"):format(info and info.name or "?", mapID, x * 100, y * 100),
        ("Guide line: map=%d, x=%.1f, y=%.1f"):format(mapID, x * 100, y * 100),
    }
end

function QF:PrintWhere()
    self:PrintLines(self:WhereLines())
end

-- same order as ESTIMATED_BOUNDS in Tools/plan_zone.py: continent, left, right, top, bottom
-- Forever's new zones aren't in the tools' map data, so measure them here
function QF:BoundsLines(arg)
    if not C_Map.GetWorldPosFromMapPos then return { "Can't read map bounds in this client." } end
    local ids = {}
    for id in tostring(arg or ""):gmatch("%d+") do table.insert(ids, tonumber(id)) end
    if #ids == 0 then
        local here = C_Map.GetBestMapForUnit("player")
        if not here then return { "Can't tell which map you are on." } end
        ids[1] = here
    end
    self.db.bounds = self.db.bounds or {}
    local lines = {}
    for _, mapID in ipairs(ids) do
        local c0, p0 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local c1, p1 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
        local info = C_Map.GetMapInfo(mapID)
        if not (p0 and p1) or c0 ~= c1 then
            table.insert(lines, ("Can't read the map bounds of %s (%s)."):format(info and info.name or "?", tostring(mapID)))
        else
            local line = ("%d: (%d, %.1f, %.1f, %.1f, %.1f)"):format(mapID, c0, p0.y, p1.y, p0.x, p1.x)
            table.insert(lines, ("Map bounds of %s:"):format(info and info.name or "?"))
            table.insert(lines, line)
            self.db.bounds[mapID] = line
        end
    end
    return lines
end

function QF:PrintBounds(arg)
    self:PrintLines(self:BoundsLines(arg))
end

SLASH_QUESTFARER1 = "/qf"
SLASH_QUESTFARER2 = "/questfarer"
SLASH_QUESTFARER3 = "/fg"     -- the old name
SlashCmdList.QUESTFARER = function(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        if QF.UI then QF.UI:Toggle() end
    elseif cmd == "options" or cmd == "config" or cmd == "settings" or cmd == "o" then
        if QF.Options then QF.Options:Open() end
    elseif cmd == "help" then
        QF:PrintHelp()
    elseif cmd == "skip" or cmd == "next" then
        QF:Skip()
    elseif cmd == "back" or cmd == "prev" then
        QF:Back()
    elseif cmd == "fix" then
        QF:FixSkipped()
    elseif cmd == "cp" then
        if QF.Paths then QF.Paths:SkipCheckpoint() end
    elseif cmd == "time" then
        QF.Timer:Print()
    elseif cmd == "journal" then
        QF.Options:OpenPage("journal")
    elseif cmd == "talents" then
        QF.Talents:Print()
    elseif cmd == "class" then
        QF.ClassQuests:Command(arg)
    elseif cmd == "paths" then
        if arg == "reset" then QF.Paths:Reset() else QF.Paths:PrintStats() end
    elseif cmd == "reset" then
        QF:RestartGuide()
    elseif cmd == "resync" then
        QF:FindMyStep(arg == "all")
    elseif cmd == "where" then
        QF:PrintWhere()
    elseif cmd == "bounds" then
        QF:PrintBounds(arg)
    elseif cmd == "spells" then
        QF:PrintTrainable()
    elseif cmd == "recstats" then
        if QF.Recorder then QF.Recorder:PrintStats() end
    elseif cmd == "export" then
        if QF.Contribute then QF.Contribute:ShowExport() end
    elseif cmd == "guides" then
        for _, line in ipairs(QF:GuideLines()) do print("  " .. line) end
    elseif cmd == "load" then
        local n = tonumber(arg)
        QF:PickGuide(n and QF.guideOrder[n] or arg)
    elseif cmd == "scale" then
        local s = tonumber(arg)
        if s and s >= 0.5 and s <= 2 then
            QF.db.scale = s
            QF:SettingsChanged()
        else
            QF:Print(("Size must be between 0.5 and 2 (now %s)."):format(tostring(QF.db.scale)))
        end
    elseif TOGGLES[cmd] then
        local key = TOGGLES[cmd]
        QF.db[key] = not QF.db[key]
        QF:Print(key .. " = " .. onoff(QF.db[key]))
        QF:SettingsChanged()
    else
        QF:PrintHelp()
    end
end
