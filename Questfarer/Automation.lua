-- Questfarer - Automation, guide quests only, Shift pauses it

local _, ns = ...
local QF = ns.QF

local TAXI_ICON, TRAINER_ICON = 132057, 132058

local function paused()
    return IsShiftKeyDown()
end

-- Gossip

local function selectGossipOptionByIcon(icon, pattern)
    if not (C_GossipInfo and C_GossipInfo.GetOptions) then return false end
    local options = C_GossipInfo.GetOptions() or {}
    for i, opt in ipairs(options) do
        local name = (opt.name or ""):lower()
        if opt.icon == icon or (pattern and name:find(pattern)) then
            if opt.gossipOptionID then
                C_GossipInfo.SelectOption(opt.gossipOptionID, "", true)
            elseif opt.orderIndex and C_GossipInfo.SelectOptionByIndex then
                C_GossipInfo.SelectOptionByIndex(opt.orderIndex, "", true)
            else
                return false
            end
            return true
        end
    end
    return false
end

QF:On("GOSSIP_SHOW", function(self)
    if paused() then return end

    if self.db.autoTurnin and C_GossipInfo.GetActiveQuests then
        for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if q.isComplete and self:WantsTurnin(q.questID, q.title) then
                self:Debug("Gossip: turning in", q.questID, q.title)
                C_GossipInfo.SelectActiveQuest(q.questID)
                return
            end
        end
    end

    if self.db.autoAccept and C_GossipInfo.GetAvailableQuests then
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if self:WantsAccept(q.questID, q.title) then
                self:Debug("Gossip: accepting", q.questID, q.title)
                C_GossipInfo.SelectAvailableQuest(q.questID)
                return
            end
        end
    end

    if not self.db.autoGossip then return end
    local step = self:CurrentStep()
    if not step then return end
    if step.type == "fly" or step.type == "getfp" then
        selectGossipOptionByIcon(TAXI_ICON, "fly")
    elseif step.type == "train" then
        selectGossipOptionByIcon(TRAINER_ICON, "train")
    end
end)

-- Quest greeting (older NPC window with a quest list)

QF:On("QUEST_GREETING", function(self)
    if paused() then return end
    if self.db.autoTurnin then
        for i = 1, GetNumActiveQuests() do
            local title, isComplete = GetActiveTitle(i)
            local id = GetActiveQuestID and GetActiveQuestID(i)
            if isComplete and self:WantsTurnin(id, title) then
                SelectActiveQuest(i)
                return
            end
        end
    end
    if self.db.autoAccept then
        for i = 1, GetNumAvailableQuests() do
            local title = GetAvailableTitle(i)
            local id
            if GetAvailableQuestInfo then
                id = select(5, GetAvailableQuestInfo(i))
            end
            if self:WantsAccept(id, title) then
                SelectAvailableQuest(i)
                return
            end
        end
    end
end)

-- Quest window

QF:On("QUEST_DETAIL", function(self)
    local id, title = GetQuestID(), GetTitleText()
    if self.db.debug then
        local map = C_Map.GetBestMapForUnit("player")
        local pos = map and C_Map.GetPlayerMapPosition(map, "player")
        local x, y = 0, 0
        if pos then x, y = pos:GetXY() end
        self:Print(("[debug] Quest %s \"%s\" from %s  map=%s x=%.1f y=%.1f"):format(
            tostring(id), tostring(title), tostring(UnitName("npc")), tostring(map), x * 100, y * 100))
    end
    if paused() or not self.db.autoAccept then return end
    if self:WantsAccept(id, title) then
        AcceptQuest()
    end
end)

QF:On("QUEST_ACCEPT_CONFIRM", function(self, _, _, questTitle)
    -- escort quests started by someone else
    if paused() or not self.db.autoAccept then return end
    if self:WantsAccept(nil, questTitle) then
        ConfirmAcceptQuest()
    end
end)

QF:On("QUEST_PROGRESS", function(self)
    if paused() or not self.db.autoTurnin then return end
    local id, title = GetQuestID(), GetTitleText()
    if self:WantsTurnin(id, title) and IsQuestCompletable() then
        CompleteQuest()
    end
end)

QF:On("QUEST_COMPLETE", function(self)
    local id, title = GetQuestID(), GetTitleText()
    self.lastCompleteTitle = title
    if id and title then self.titleCache[id] = title end
    if paused() or not self.db.autoTurnin then return end
    if not self:WantsTurnin(id, title) then return end
    local choices = GetNumQuestChoices()
    if choices <= 1 then
        GetQuestReward(1)
    else
        self:Print("|cffffff00Choose your reward|r for |cffffd100" .. tostring(title) .. "|r (" .. choices .. " choices).")
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
    end
end)

-- Flight paths

local function taxiNodes()
    -- { {name=, slot=, reachable=} }
    local list = {}
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
        local mapID = GetTaxiMapID()
        local nodes = mapID and C_TaxiMap.GetAllTaxiNodes(mapID)
        if nodes and #nodes > 0 then
            for _, n in ipairs(nodes) do
                local reachable = true
                if Enum and Enum.FlightPathState and n.state ~= nil then
                    reachable = n.state == Enum.FlightPathState.Reachable
                end
                table.insert(list, { name = n.name, slot = n.slotIndex, reachable = reachable })
            end
            return list
        end
    end
    for i = 1, NumTaxiNodes() do
        local name = TaxiNodeName(i)
        local typ = TaxiNodeGetType and TaxiNodeGetType(i)
        table.insert(list, { name = name, slot = i, reachable = (typ == nil or typ == "REACHABLE") })
    end
    return list
end

QF:On("TAXIMAP_OPENED", function(self)
    local step = self:CurrentStep()
    if not step then return end

    if step.type == "getfp" then
        -- learned automatically when the map opens
        self:Print("Flight path: |cffffd100" .. tostring(step.getfp) .. "|r learned.")
        self:CompleteCurrent()
        -- keep the map open if a flight is next or Shift is held
        local nxt = self.steps[self.char.step + 1]
        if not (nxt and nxt.type == "fly") and not paused() then
            C_Timer.After(0.3, function()
                if CloseTaxiMap then CloseTaxiMap() end
            end)
        end
        return
    end

    if step.type == "fly" and self.db.autoFlight and not paused() then
        local dest = tostring(step.fly):lower()
        for _, n in ipairs(taxiNodes()) do
            if n.name and n.reachable and n.name:lower():find(dest, 1, true) then
                self:Print("Flying to |cffffd100" .. n.name .. "|r")
                TakeTaxiNode(n.slot)
                self.flightTaken = true
                return
            end
        end
        self:Print("|cffff6666No flight path matches \"" .. step.fly .. "\". Pick it yourself.|r")
    end
end)

-- Trainer

-- GetTrainerServiceInfo has an old and a new signature
local function serviceInfo(i)
    local name, a, b = GetTrainerServiceInfo(i)
    if type(b) == "number" then
        return name, a      -- new: name, category, iconID, ...
    end
    return name, b          -- old: name, rank, category
end

function QF:CountTrainable()
    if not GetNumTrainerServices then return 0 end
    local n, count = GetNumTrainerServices() or 0, 0
    for i = 1, n do
        local _, cat = serviceInfo(i)
        if cat == "available" then count = count + 1 end
    end
    return count
end

-- back to front, the list changes when you buy
function QF:TrainAll()
    if not GetNumTrainerServices then return end
    local n = GetNumTrainerServices() or 0
    local money = GetMoney()
    local bought = 0
    for i = n, 1, -1 do
        local name, cat = serviceInfo(i)
        if cat == "available" then
            local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
            if cost <= money then
                BuyTrainerService(i)
                money = money - cost
                bought = bought + 1
            end
        end
    end
    if bought > 0 then
        self:Print("Learned " .. bought .. " spell(s).")
    elseif self:CountTrainable() > 0 then
        self:Print("|cffff6666Not enough money for more spells.|r")
    else
        self:Print("No new spells to learn right now.")
    end
end

-- none left = training done for this level
function QF:CheckTrainerDone()
    if not self.trainerOpen then return end
    self.trainableLeft = self:CountTrainable()
    if self.trainableLeft == 0 then
        self.char.lastTrainLevel = UnitLevel("player")
    end
    self:RequestUpdate()
end

QF:On("TRAINER_SHOW", function(self)
    self.trainerOpen = true
    local skip = paused() -- read Shift now, not 0.3s later
    -- give the list time to fill
    C_Timer.After(0.3, function()
        if self.db.autoTrain and not skip then
            self:TrainAll()
        end
        self:CheckTrainerDone()
    end)
end)

QF:On("TRAINER_UPDATE", function(self)
    C_Timer.After(0.2, function() self:CheckTrainerDone() end)
end)

QF:On("TRAINER_CLOSED", function(self)
    self.trainerOpen = false
    self:RequestUpdate()
end)
