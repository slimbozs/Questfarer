-- Records quests, NPCs, trainers, flight paths and a route log while you play (/qf record).

local _, ns = ...
local QF = ns.QF

local R = {}
QF.Recorder = R

local MAX_POINTS = 25      -- per objective
local MAX_LOG = 5000
local MIN_SPREAD = 1.5     -- map %, closer points are skipped

local ZONE_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

local function enabled()
    return QF.db and QF.db.record
end

function R:DB()
    QuestfarerRecorderDB = QuestfarerRecorderDB or {}
    local db = QuestfarerRecorderDB
    db.version = 1
    db.quests = db.quests or {}
    db.npcs = db.npcs or {}
    db.trainers = db.trainers or {}
    db.taxi = db.taxi or {}
    db.log = db.log or {}
    return db
end

-- caves/mines are mapped up to their zone
function R:Position()
    local best = C_Map.GetBestMapForUnit("player")
    if not best then return nil end
    local zone, info = best, C_Map.GetMapInfo(best)
    while info and info.mapType and info.mapType > ZONE_TYPE and info.parentMapID and info.parentMapID > 0 do
        zone = info.parentMapID
        info = C_Map.GetMapInfo(zone)
    end
    local pos = C_Map.GetPlayerMapPosition(zone, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x then return nil end
    local p = { map = zone, x = round1(x * 100), y = round1(y * 100) }
    if best ~= zone then p.sub = best end
    local sub = plain(GetSubZoneText())
    if sub and sub ~= "" then p.area = sub end
    return p
end

-- returns { name, id, kind }
function R:Target(unit)
    unit = unit or "npc"
    local guid = plain(UnitGUID(unit))
    local name = plain(UnitName(unit))
    if not guid then
        return name and { name = name } or nil
    end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return { name = name, id = tonumber(id), kind = kind }
end

local function playerInfo()
    return {
        level = UnitLevel("player"),
        class = QF.player and QF.player.class,
        race = QF.player and QF.player.race,
    }
end

function R:Log(kind, data)
    local log = self:DB().log
    if #log >= MAX_LOG then table.remove(log, 1) end
    data = data or {}
    data.e = kind
    data.t = time()
    data.lvl = UnitLevel("player")
    data.char = QF.charKey
    local p = self:Position()
    if p then data.map, data.x, data.y = p.map, p.x, p.y end
    table.insert(log, data)
end

function R:NoteNPC(target, role)
    if not (target and target.id and target.kind == "Creature") then return end
    local npcs = self:DB().npcs
    local n = npcs[target.id] or {}
    n.name = target.name or n.name
    local p = self:Position()
    if p then n.map, n.x, n.y, n.area = p.map, p.x, p.y, p.area end
    if role then
        n.roles = n.roles or {}
        n.roles[role] = true
    end
    npcs[target.id] = n
end

-- Quests

local function questEntry(id)
    local quests = R:DB().quests
    quests[id] = quests[id] or {}
    return quests[id]
end

R.pendingGiver = {}  -- questID -> where, until QUEST_ACCEPTED
R.pendingTurnin = {} -- questID -> { where, choices }, until QUEST_TURNED_IN

local function where(target)
    local w = R:Position() or {}
    if target then
        w.npc = target.name
        w.npcId = target.id
        w.kind = target.kind
    end
    return w
end

QF:On("QUEST_DETAIL", function(self)
    if not enabled() then return end
    local id = GetQuestID()
    if not id or id == 0 then return end
    local q = questEntry(id)
    q.title = GetTitleText()
    q.objText = GetObjectiveText()
    q.xp = GetRewardXP and GetRewardXP() or q.xp
    q.money = GetRewardMoney and GetRewardMoney() or q.money
    local target = R:Target("npc")
    if not target then
        q.startsFromItem = true
    end
    -- keyed by quest: with auto-accept the next quest window opens before the first is confirmed
    R.pendingGiver[id] = where(target)
end)

QF:On("QUEST_ACCEPTED", function(self, _, questID)
    if not enabled() or not questID then return end
    local q = questEntry(questID)
    q.title = q.title or C_QuestLog.GetTitleForQuestID(questID)
    if not q.accept then
        if R.pendingGiver[questID] then
            q.accept = R.pendingGiver[questID]
            R.pendingGiver[questID] = nil
        else
            q.accept = where(R.lastGossip)
        end
        local pi = playerInfo()
        q.accept.level, q.accept.class, q.accept.race = pi.level, pi.class, pi.race
    end
    local idx = C_QuestLog.GetLogIndexForQuestID(questID)
    local info = idx and C_QuestLog.GetInfo(idx)
    if info then
        q.level = info.level
        q.suggestedGroup = (info.suggestedGroup and info.suggestedGroup > 0) and info.suggestedGroup or nil
    end
    local objs = C_QuestLog.GetQuestObjectives(questID)
    if objs and #objs > 0 then
        q.objectives = {}
        for i, o in ipairs(objs) do
            q.objectives[i] = { text = o.text, type = o.type, need = o.numRequired }
        end
    end
    R.progress[questID] = nil
    R:Log("accept", { q = questID })
end)

QF:On("QUEST_COMPLETE", function(self)
    if not enabled() then return end
    local id = GetQuestID()
    if not id or id == 0 then return end
    R.pendingTurnin[id] = { where = where(R:Target("npc")), choices = GetNumQuestChoices() }
end)

QF:On("QUEST_TURNED_IN", function(self, _, questID, xp, money)
    if not enabled() or not questID then return end
    local q = questEntry(questID)
    if not q.turnin then
        local pend = R.pendingTurnin[questID]
        if pend then
            q.turnin = pend.where
            q.choices = pend.choices
            R.pendingTurnin[questID] = nil
        else
            q.turnin = where(nil)
        end
        q.turnin.level = UnitLevel("player")
    end
    q.xp = xp or q.xp
    q.money = money or q.money
    R:Log("turnin", { q = questID, xp = xp })
end)

-- remember where objective counters go up
R.progress = {} -- questID -> { [i] = numFulfilled }

local function nearExisting(points, p)
    for _, e in ipairs(points) do
        if e.map == p.map and math.abs(e.x - p.x) < MIN_SPREAD and math.abs(e.y - p.y) < MIN_SPREAD then
            return true
        end
    end
    return false
end

function R:ScanObjectives()
    if not enabled() then return end
    local n = C_QuestLog.GetNumQuestLogEntries()
    local pos
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local id = info.questID
            local objs = C_QuestLog.GetQuestObjectives(id)
            if objs then
                local prev = self.progress[id]
                local now = {}
                for k, o in ipairs(objs) do
                    now[k] = o.numFulfilled or 0
                    if prev and prev[k] and now[k] > prev[k] then
                        pos = pos or self:Position()
                        if pos then
                            local q = questEntry(id)
                            q.points = q.points or {}
                            q.points[k] = q.points[k] or {}
                            local list = q.points[k]
                            if #list < MAX_POINTS and not nearExisting(list, pos) then
                                table.insert(list, { map = pos.map, x = pos.x, y = pos.y })
                            end
                        end
                    end
                end
                self.progress[id] = now
            end
        end
    end
end

QF:On("QUEST_LOG_UPDATE", function() R:ScanObjectives() end)
QF:On("UNIT_QUEST_LOG_CHANGED", function(_, _, unit)
    if unit == "player" then R:ScanObjectives() end
end)

-- NPCs

local ROLE_BY_ICON = {
    [132057] = "flightmaster",
    [132058] = "trainer",
    [132052] = "innkeeper",
    [136458] = "innkeeper",
    [132060] = "vendor",
}

QF:On("GOSSIP_SHOW", function(self)
    local target = R:Target("npc")
    R.lastGossip = target
    if not enabled() or not target then return end
    local roles = {}
    if C_GossipInfo and C_GossipInfo.GetOptions then
        for _, opt in ipairs(C_GossipInfo.GetOptions() or {}) do
            local role = ROLE_BY_ICON[opt.icon]
            if role then roles[role] = true end
        end
    end
    local any = false
    for role in pairs(roles) do
        R:NoteNPC(target, role)
        any = true
    end
    if not any then R:NoteNPC(target, nil) end
end)

QF:On("MERCHANT_SHOW", function(self)
    if not enabled() then return end
    local target = R:Target("npc")
    R:NoteNPC(target, (CanMerchantRepair and CanMerchantRepair()) and "repair" or "vendor")
end)

QF:On("HEARTHSTONE_BOUND", function(self)
    if not enabled() then return end
    R:NoteNPC(R.lastGossip, "innkeeper")
    R:Log("bind", { place = GetBindLocation() })
end)

-- Trainers

local function serviceInfo(i)
    local name, a, b, _, e = GetTrainerServiceInfo(i)
    if type(b) == "number" then
        return name, a, e   -- new API: name, category, icon, ?, rank
    end
    return name, b, a       -- old API: name, rank, category
end

function R:RecordTrainer()
    if not enabled() or not GetNumTrainerServices then return end
    local target = R:Target("npc")
    if not (target and target.id) then return end
    local tradeskill = IsTradeskillTrainer and IsTradeskillTrainer()
    R:NoteNPC(target, tradeskill and "professiontrainer" or "trainer")
    local trainers = R:DB().trainers
    local t = trainers[target.id] or { name = target.name, services = {} }
    t.class = (not tradeskill) and QF.player.class or nil
    t.tradeskill = tradeskill or nil
    for i = 1, GetNumTrainerServices() or 0 do
        local name, category, rank = serviceInfo(i)
        if name and category ~= "header" then
            local key = name .. (rank and rank ~= "" and (" (" .. rank .. ")") or "")
            local s = t.services[key] or {}
            s.name, s.rank = name, rank
            s.level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or s.level
            s.cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or s.cost
            t.services[key] = s
        end
    end
    trainers[target.id] = t
end

QF:On("TRAINER_SHOW", function(self)
    C_Timer.After(0.5, function() R:RecordTrainer() end)
    if enabled() then R:Log("train", { npc = R.lastGossip and R.lastGossip.name }) end
end)

QF:On("TRAINER_UPDATE", function(self)
    C_Timer.After(0.2, function() R:RecordTrainer() end)
end)

-- Flight paths

QF:On("TAXIMAP_OPENED", function(self)
    if not enabled() then return end
    local target = R:Target("npc") or R.lastGossip
    R:NoteNPC(target, "flightmaster")
    local taxi = R:DB().taxi
    local here
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
        local mapID = GetTaxiMapID()
        for _, n in ipairs((mapID and C_TaxiMap.GetAllTaxiNodes(mapID)) or {}) do
            if n.nodeID then
                local e = taxi[n.nodeID] or {}
                e.name = n.name
                e.taxiMap = mapID
                if n.position then
                    e.tx, e.ty = round1(n.position.x * 100), round1(n.position.y * 100)
                end
                if Enum and Enum.FlightPathState and n.state == Enum.FlightPathState.Current then
                    here = n
                    e.npc = target and target.name
                    e.npcId = target and target.id
                    local p = R:Position()
                    if p then e.map, e.x, e.y = p.map, p.x, p.y end
                end
                taxi[n.nodeID] = e
            end
        end
    end
    R:Log("taxi", { node = here and here.name })
end)

-- Level-ups

QF:On("PLAYER_LEVEL_UP", function(self, _, level)
    if not enabled() then return end
    R:Log("level", { to = level })
end)

QF:On("PLAYER_LOGIN", function(self)
    local name, realm = UnitFullName("player")
    QF.charKey = (name or "?") .. "-" .. (realm or GetRealmName() or "?")
    R:DB()
    C_Timer.After(2, function() R:ApplyCombatLog(true) end)
end)

-- Combat log

-- advanced logging adds level, health and position to the log lines
local function ensureAdvancedLogging()
    if not (GetCVar and SetCVar) or GetCVar("advancedCombatLogging") == "1" then return end
    if InCombatLockdown() then return end
    pcall(SetCVar, "advancedCombatLogging", "1")
end

local startedLog = false -- addon turned the log on this session

-- after login only a change of this setting acts, so a manual /combatlog off stays off
function R:ApplyCombatLog(login)
    if not LoggingCombat or not QF.db then return end
    local want = QF.db.combatLog and true or false
    if not login and want == self.combatLogSetting then return end
    self.combatLogSetting = want
    if want then
        ensureAdvancedLogging()
        if not LoggingCombat() then
            LoggingCombat(true)
            startedLog = true
            QF:Print("Combat log |cff00ff00on|r (saved in the game's Logs folder). Turn this off in the settings, Data page.")
        end
    elseif startedLog and LoggingCombat() then
        LoggingCombat(false)
        startedLog = false
        QF:Print("Combat log |cffff4444off|r.")
    end
end

function R:CombatLogLines()
    local on = LoggingCombat and LoggingCombat()
    return { "The combat log is " .. (on and "|cff00ff00on|r" or "|cffff4444off|r") ..
        " right now. It is saved in the game's Logs folder as WoWCombatLog-*.txt." }
end

-- /qf recstats, also shown in the settings window
function R:StatsLines()
    local db = self:DB()
    local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
    return {
        ("Recorder is %s. Quests: %d, NPCs: %d, trainers: %d, flight paths: %d, log entries: %d"):format(
            QF.db.record and "|cff00ff00ON|r" or "|cffff4444OFF|r",
            count(db.quests), count(db.npcs), count(db.trainers), count(db.taxi), #db.log),
        "Saved to disk when you /reload or log out.",
    }
end

function R:PrintStats()
    QF:PrintLines(self:StatsLines())
end
