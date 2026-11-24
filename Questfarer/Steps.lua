-- step: { <type> = value, title, npc, x, y, map, text, tip, class/race/notclass }, complete can take a list of quests

local _, ns = ...
local QF = ns.QF

QF.failedQuests = {} -- questID -> true once the player was told

local TYPE_ORDER = { "accept", "turnin", "complete", "train", "getfp", "fly", "sethearth", "hearth", "level", "go", "note" }

local TYPE_LABEL = {
    accept    = "|cffffd100Accept|r",
    complete  = "|cffff9933Complete|r",
    turnin    = "|cff33ff33Turn in|r",
    train     = "|cffcc77ffTrain|r",
    getfp     = "|cff66ccffFlight path|r",
    fly       = "|cff66ccffFly|r",
    sethearth = "|cff66ffccSet hearth|r",
    hearth    = "|cff66ffccHearth|r",
    level     = "|cffffffffLevel|r",
    go        = "|cffffffffGo|r",
    note      = "|cffffffffInfo|r",
}
QF.TYPE_LABEL = TYPE_LABEL

local function Q(title)
    return "|cffffd100" .. tostring(title) .. "|r"
end

function QF:PrepareStep(step, guide)
    if step.prepared then return end
    step.prepared = true
    for _, t in ipairs(TYPE_ORDER) do
        if step[t] ~= nil then
            step.type = t
            break
        end
    end
    step.type = step.type or "note"
    if not step.map and guide and guide.map then
        step.map = guide.map
    end
    local t = step.type
    if t == "accept" or t == "turnin" then
        local v = step[t]
        if type(v) == "number" then
            step.qid = v
            step.qtitle = step.title
        else
            step.qtitle = v
        end
    elseif t == "complete" then
        local v = step.complete
        step.quests = {}
        if type(v) == "table" then
            for i, q in ipairs(v) do
                local titles = step.titles or {}
                table.insert(step.quests, { id = type(q) == "number" and q or nil, title = type(q) == "string" and q or titles[i] })
            end
        else
            table.insert(step.quests, { id = type(v) == "number" and v or nil, title = type(v) == "string" and v or step.title })
        end
    end
    -- repeated titles in a chain go by ID only, others keep the title in case the server ID differs
    local side = guide and guide.side
    if step.qid and (side or self:TitleIsShared(step.qtitle)) then
        self.titleCache[step.qid] = self.titleCache[step.qid] or step.qtitle
        step.qtitle = nil
    end
    for _, q in ipairs(step.quests or {}) do
        if q.id and (side or self:TitleIsShared(q.title)) then
            self.titleCache[q.id] = self.titleCache[q.id] or q.title
            q.title = nil
        end
    end
end

function QF:ResolveTrainer(step)
    if step.type ~= "train" or type(step.train) ~= "string" then return end
    if step.resolvedFor == self.player.class then return end
    local byClass = self.trainers and self.trainers[self.player.class]
    local t = byClass and byClass[step.train]
    if t then
        step.npc, step.x, step.y, step.map = t.npc, t.x, t.y, t.map
        step.trainerNote = t.note
    else
        step.npc, step.x, step.y = nil, nil, nil
    end
    step.resolvedFor = self.player.class
end

function QF:IsStepDone(step)
    -- obsolete: gray quest or missed prerequisite
    if step.manualDone or step.obsolete then return true end
    local t = step.type
    if t == "accept" then
        return self:IsTurnedIn(step.qid, step.qtitle) or self:FindInLog(step.qid, step.qtitle) ~= nil
            or self:PassedOptional(step, step.qid, step.qtitle)
    elseif t == "turnin" then
        return self:IsTurnedIn(step.qid, step.qtitle) or self:PassedOptional(step, step.qid, step.qtitle)
    elseif t == "complete" then
        for _, q in ipairs(step.quests) do
            if not self:PassedOptional(step, q.id, q.title) and not self:IsQuestObjectivesDone(q.id, q.title) then
                return false
            end
        end
        return true
    elseif t == "train" then
        return not self:NeedsTraining()
    elseif t == "fly" then
        return UnitOnTaxi("player") and true or false
    elseif t == "sethearth" then
        local bind = GetBindLocation()
        return bind and bind:lower() == tostring(step.sethearth):lower() or false
    elseif t == "level" then
        return UnitLevel("player") >= step.level
    elseif t == "go" then
        local d = self:DistanceTo(step)
        return d ~= nil and d <= (step.radius or 15)
    end
    -- getfp, hearth, note: done via events or by hand
    return false
end

function QF:StepText(step)
    local t = step.type
    local label = TYPE_LABEL[t] or ""
    if step.text and t ~= "complete" and t ~= "level" and t ~= "go" then
        -- custom text replaces the default, except where it describes the objective
        return label .. " " .. step.text
    end
    if t == "accept" then
        return label .. " " .. Q(self:QuestTitle(step.qid, step.qtitle)) .. (step.npc and (" from " .. step.npc) or "")
    elseif t == "turnin" then
        return label .. " " .. Q(self:QuestTitle(step.qid, step.qtitle)) .. (step.npc and (" at " .. step.npc) or "")
    elseif t == "complete" then
        local names = {}
        for _, q in ipairs(step.quests) do
            table.insert(names, Q(self:QuestTitle(q.id, q.title)))
        end
        return label .. " " .. table.concat(names, " + ")
    elseif t == "train" then
        if step.npc then
            return label .. " new spells at " .. step.npc
        end
        return label .. " new spells at your class trainer"
    elseif t == "getfp" then
        return label .. ": get the flight path in " .. Q(step.getfp) .. (step.npc and (" (" .. step.npc .. ")") or "")
    elseif t == "fly" then
        return label .. " to " .. Q(step.fly)
    elseif t == "sethearth" then
        return label .. " in " .. Q(step.sethearth) .. (step.npc and (" at " .. step.npc) or "")
    elseif t == "hearth" then
        return label .. " to " .. Q(step.hearth)
    elseif t == "level" then
        return label .. ": reach level " .. step.level .. (step.text and (" — " .. step.text) or "")
    elseif t == "go" then
        return label .. " " .. (step.text or "to the marker")
    elseif t == "note" then
        return label .. " " .. tostring(step.note)
    end
    return tostring(step.text or "?")
end

-- step text without the type word
function QF:StepBody(step)
    local text = self:StepText(step)
    local label = TYPE_LABEL[step.type]
    if label and text:sub(1, #label) == label then
        text = text:sub(#label + 1):gsub("^[:%s]+", "")
    end
    return (text:gsub("^%l", string.upper))
end

-- list of { text, done, indent }, done is nil for lines that aren't objectives
function QF:StepRows(step)
    local rows = {}
    local function add(text, done, indent)
        table.insert(rows, { text = text, done = done, indent = indent or 0 })
    end
    local t = step.type
    local skipped = self.SkippedLine and self:SkippedLine(step)
    if skipped then add((skipped:gsub("^(|c%x%x%x%x%x%x%x%x)%s+", "%1"))) end
    if t == "complete" then
        if step.text then add(step.text) end
        for _, q in ipairs(step.quests) do
            local id = self:FindInLog(q.id, q.title)
            if id and self:QuestFailed(id) then
                if not self.failedQuests[id] then
                    self.failedQuests[id] = true
                    self:Print(("|cffff6666\"%s\" failed.|r Abandon it in your quest log and the guide goes back to where you take it again.")
                        :format(self:QuestTitle(id, q.title)))
                end
                add("|cffff6666This quest failed. Abandon it in your quest log (L): the guide then goes back to where you take it again.|r")
            elseif id then
                local objs = C_QuestLog.GetQuestObjectives(id)
                if objs then
                    for _, o in ipairs(objs) do
                        if o.text and o.text ~= "" then add(o.text, o.finished and true or false) end
                    end
                end
            elseif not skipped and not self:IsTurnedIn(q.id, q.title) and not self:PassedOptional(step, q.id, q.title) then
                add("|cffff6666Quest is not in your quest log - accept it first (or click Next).|r")
            end
        end
    elseif t == "level" then
        local cur, max = UnitXP("player"), UnitXPMax("player")
        local hidden = issecretvalue and (issecretvalue(cur) or issecretvalue(max))
        if not hidden and max and max > 0 then
            add(("|cffccccccXP: %d / %d (%d%%)|r"):format(cur, max, cur / max * 100))
        end
    elseif t == "train" then
        if not step.npc then
            add("|cffccccccNo trainer location for your class here - find the nearest class trainer.|r")
        end
        if step.trainerNote then add("|cffcccccc" .. step.trainerNote .. "|r") end
        local list = self.NewTrainableSpells and self:HasSpellData() and self:NewTrainableSpells()
        if list and #list > 0 then
            add("|cffffffff" .. self:TrainingSummary(list) .. ":|r")
            local maxShown = 6
            for i, s in ipairs(list) do
                if i > maxShown then
                    add(("|cff999999...and %d more (/qf spells)|r"):format(#list - maxShown), nil, 1)
                    break
                end
                add("|cffffd100" .. self:SpellLine(s) .. "|r  " .. self:FormatMoney(s.cost), nil, 1)
            end
        end
        if self.trainerOpen then
            add("|cff00ff00Trainer open - click \"Train all\".|r")
        end
    elseif t == "fly" then
        add("|cffccccccTalk to the flight master, the flight is picked automatically.|r")
    elseif t == "getfp" then
        add("|cffccccccTalk to the flight master to learn the flight path.|r")
    elseif t == "hearth" then
        local left = self:HearthCooldown()
        if left and left > 0 then
            add(("|cffffcc66Your hearthstone is ready in %d min. Wait for it, or click Next and travel another way.|r")
                :format(math.ceil(left / 60)))
        end
    end
    if step.elite and t == "accept" then
        add("|cffffcc66Elite: skip this if you can't solo it or find a group (click Next).|r")
    elseif step.elite and t == "complete" then
        local names = {}
        if #step.quests > #step.optional then
            for _, q in ipairs(step.quests) do
                if self:IsOptional(step, q.id) then table.insert(names, "\"" .. self:QuestTitle(q.id, q.title) .. "\"") end
            end
        end
        local what = #names > 0 and table.concat(names, ", ") or "this"
        add(("|cffffcc66Elite: if you can't solo %s or find a group, abandon it and the guide moves on.|r"):format(what))
    end
    if step.tip then
        add("|cff99ccffTip: " .. step.tip .. "|r")
    end
    return rows
end

-- returns coords text, yards (when known)
function QF:StepLocation(step)
    if not (step.x and step.y) then return nil end
    local coords = ("%.1f, %.1f"):format(step.x, step.y)
    local ok, yards = pcall(self.DistanceTo, self, step)
    if not ok or (issecretvalue and issecretvalue(yards)) then return coords end
    return coords, yards
end
