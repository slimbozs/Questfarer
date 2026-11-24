-- Questfarer - Adapt: find where the character is in the guides from quest state and level

local _, ns = ...
local QF = ns.QF

local QUEST_TYPES = { accept = true, turnin = true, complete = true }

-- highest gray quest level, Classic rules (Forever uses them)
function QF:GrayLevel(level)
    level = level or UnitLevel("player")
    if level <= 5 then return 0 end
    if level <= 39 then return level - 5 - math.floor(level / 10) end
    return level - 1 - math.floor(level / 5)
end

function QF:IsTrivialQuestLevel(qlevel)
    return qlevel ~= nil and qlevel > 0 and qlevel <= self:GrayLevel()
end

local function prereqMet(self, list, planned, any)
    for _, q in ipairs(list) do
        local ok = planned[q] or self:IsTurnedIn(q)
        if any and ok then return true end
        if not any and not ok then return false end
    end
    return not any
end

-- planned: questID -> true if in the log or the route will still take it
function QF:IsObsolete(step, planned)
    local t = step.type
    if t == "accept" then
        local q = step.qid
        if self:IsTurnedIn(q, step.qtitle) then return false end
        if self:FindInLog(q, step.qtitle) then
            if q then planned[q] = true end
            return false
        end
        if self:IsTrivialQuestLevel(step.qlevel) then return true end
        if step.pre and not prereqMet(self, step.pre, planned, true) then return true end
        if step.preall and not prereqMet(self, step.preall, planned, false) then return true end
        if q then planned[q] = true end
        return false
    elseif t == "turnin" then
        local q = step.qid
        if not q or self:IsTurnedIn(q, step.qtitle) or self:FindInLog(q, step.qtitle) then return false end
        return not planned[q]
    elseif t == "complete" then
        for _, cq in ipairs(step.quests or {}) do
            if not cq.id or planned[cq.id] or self:FindInLog(cq.id, cq.title) or self:IsTurnedIn(cq.id, cq.title) then
                return false
            end
        end
        return true
    end
    return false
end

function QF:ApplicableGuides()
    local list = {}
    for _, name in ipairs(self.guideOrder) do
        local g = self.guides[name]
        if not g.side and self:GuideApplies(g) then -- class quests aren't part of the route
            local steps = {}
            for _, step in ipairs(g.steps) do
                if self:StepApplies(step) then
                    self:PrepareStep(step, g)
                    self:ResolveTrainer(step)
                    table.insert(steps, step)
                end
            end
            table.insert(list, { guide = g, steps = steps })
        end
    end
    return list
end

-- obsolete steps count as done
function QF:PlanRoute()
    local planned, count = {}, 0
    -- read the quest log once instead of once per title
    self.logTitles = self:ReadLogTitles()
    local ok, err = pcall(function()
        for _, entry in ipairs(self:ApplicableGuides()) do
            for _, step in ipairs(entry.steps) do
                step.obsolete = self:IsObsolete(step, planned) or nil
                if step.obsolete then count = count + 1 end
            end
        end
    end)
    self.logTitles = nil
    if not ok then error(err, 0) end
    return count
end

function QF:StepProgressed(step)
    local t = step.type
    if t == "accept" then
        return self:IsTurnedIn(step.qid, step.qtitle) or self:FindInLog(step.qid, step.qtitle) ~= nil
    elseif t == "turnin" then
        return self:IsTurnedIn(step.qid, step.qtitle)
    elseif t == "complete" then
        for _, q in ipairs(step.quests) do
            if not self:IsQuestObjectivesDone(q.id, q.title) then return false end
        end
        return true
    end
    return false
end

-- returns guideName, stepIndex, guideOrderIndex, or nil if no guide covers the level.
-- only: look in that guide alone, whatever the level
function QF:FindStart(only)
    self:PlanRoute()
    local level = UnitLevel("player")
    local behind = self.guide ~= nil and not self.guide.side -- guides before the one you're in
    for gi, entry in ipairs(self:ApplicableGuides()) do
        local g, steps = entry.guide, entry.steps
        if self.guide and g.name == self.guide.name then behind = false end
        local fits = not g.maxLevel or level < g.maxLevel
        if (only and g.name == only) or (not only and fits) then
            -- non-quest steps only count after the last quest step with progress
            local lastProgress = 0
            for i, s in ipairs(steps) do
                if QUEST_TYPES[s.type] and not s.obsolete and self:StepProgressed(s) then lastProgress = i end
            end
            for i, s in ipairs(steps) do
                if not s.obsolete and not self:IsStepDone(s) then
                    -- an elite quest you didn't take doesn't hold you back once you're past it
                    local skippable = s.type == "accept" and s.optional and (behind or i < lastProgress)
                    if not skippable and (QUEST_TYPES[s.type] or i > lastProgress) then
                        return g.name, i, gi
                    end
                end
            end
        end
    end
    return nil
end

local function guideIndex(self, name)
    local gi = 0
    for _, entry in ipairs(self:ApplicableGuides()) do
        gi = gi + 1
        if entry.guide.name == name then return gi end
    end
    return nil
end

-- force: also allow moving backwards
function QF:Resync(force, quiet)
    if self.guide and self.guide.side then
        if not force then return false end
        self.char.sideReturn = nil -- leave the class quest
    end
    -- a guide the player picked keeps them until it runs out
    local picked = self.char.picked
    if picked and self.guides[picked] then
        local name, step = self:FindStart(picked)
        if name then
            local same = self.guide and self.guide.name == name
            if force or not same or step > (self.char.step or 1) then
                local moved = not (same and self.char.step == step)
                self:LoadGuide(name, step)
                if moved and not quiet then
                    self:Print(("Picked up where you are in |cffffd100%s|r: step %d."):format(name, step))
                end
                return moved
            end
            self:RequestUpdate()
            return false
        end
        self.char.picked = nil
    end
    local name, step, gi = self:FindStart()
    self.noGuideForLevel = nil
    if not name then
        if not quiet then
            self:Print("No guide covers level " .. UnitLevel("player") .. " yet - the route continues in a later version.")
        end
        -- don't leave an outleveled guide up as if it were right
        local g = self.guide
        if g and g.maxLevel and UnitLevel("player") >= g.maxLevel then
            self.noGuideForLevel = true
            self.char.step = #self.steps + 1
            if self.UI then self.UI:Refresh() end
        end
        return false, true
    end
    local cur = self.guide and guideIndex(self, self.guide.name)
    local ahead = not cur or gi > cur or (gi == cur and step > (self.char.step or 1))
    if force or ahead then
        local moved = not (self.guide and self.guide.name == name and self.char.step == step)
        self:LoadGuide(name, step)
        if moved and not quiet then
            self:Print(("Picked up where you are: |cffffd100%s|r, step %d. Quests you've done or that are gray are skipped.")
                :format(name, step))
        end
        return moved
    end
    self:RequestUpdate()
    return false
end

-- quest completion data can arrive a bit after PLAYER_LOGIN
QF:On("PLAYER_LOGIN", function(self)
    C_Timer.After(3, function()
        self:CacheQuestLog()
        self:Resync(false, false)
    end)
end)

-- gray levels change on level-up, abandons change what the route takes
QF:On("PLAYER_LEVEL_UP", function(self)
    C_Timer.After(0.5, function()
        self:PlanRoute()
        self:RequestUpdate()
    end)
end)

QF:On("QUEST_REMOVED", function(self, _, questID)
    C_Timer.After(0.5, function()
        self:PlanRoute()
        self:RequestUpdate()
    end)
    -- failed quest abandoned, go back to the step that takes it
    if questID and self.failedQuests[questID] then
        self.failedQuests[questID] = nil
        C_Timer.After(0.8, function()
            if self:SkippedFor(self:CurrentStep()) then self:FixSkipped() end
        end)
    end
end)

-- Skipped steps: a later step can need a quest you clicked Next past, /qf fix goes back to it

local MAX_FIX_DEPTH = 5

-- real quest state, ignoring Next clicks
local function doneByState(self, step)
    local manual = step.manualDone
    step.manualDone = nil
    local done = self:IsStepDone(step)
    step.manualDone = manual
    return done
end

local function stepQuests(step)
    if step.type == "accept" or step.type == "turnin" then
        return { step.qid }
    elseif step.type == "complete" then
        local ids = {}
        for _, q in ipairs(step.quests or {}) do
            if q.id then table.insert(ids, q.id) end
        end
        return ids
    end
    return {}
end

-- elite quests and their follow-ups can be skipped on purpose
function QF:IsOptional(step, qid)
    for _, q in ipairs(step.optional or {}) do
        if q == qid then return true end
    end
    return false
end

local function untouched(self, qid)
    return not self:IsTurnedIn(qid) and not self:FindInLog(qid)
end

-- an optional quest you passed by: not taken, or the quest before it was never taken
function QF:PassedOptional(step, qid, title)
    if not self:IsOptional(step, qid) or self:IsTurnedIn(qid, title) or self:FindInLog(qid, title) then return false end
    if step.type ~= "accept" then return true end
    if step.pre then
        local all = true
        for _, p in ipairs(step.pre) do
            if not untouched(self, p) then all = false break end
        end
        if all then return true end
    end
    for _, p in ipairs(step.preall or {}) do
        if untouched(self, p) then return true end
    end
    return false
end

function QF:MissingQuestsFor(step)
    local missing = {}
    local t = step.type
    if step.qid and self:IsOptional(step, step.qid) and (t == "turnin" or self:PassedOptional(step, step.qid, step.qtitle)) then
        return missing
    end
    if t == "accept" then
        if self:IsTurnedIn(step.qid, step.qtitle) or self:FindInLog(step.qid, step.qtitle) then return missing end
        if step.pre then
            local any = false
            for _, p in ipairs(step.pre) do
                if self:IsTurnedIn(p) then any = true break end
            end
            if not any then
                for _, p in ipairs(step.pre) do table.insert(missing, p) end
            end
        end
        for _, p in ipairs(step.preall or {}) do
            if not self:IsTurnedIn(p) then table.insert(missing, p) end
        end
    elseif t == "turnin" then
        if step.qid and not self:IsTurnedIn(step.qid, step.qtitle) and not self:FindInLog(step.qid, step.qtitle) then
            table.insert(missing, step.qid)
        end
    elseif t == "complete" then
        for _, q in ipairs(step.quests or {}) do
            if q.id and not self:IsOptional(step, q.id) and not self:IsTurnedIn(q.id, q.title)
                and not self:FindInLog(q.id, q.title) then
                table.insert(missing, q.id)
            end
        end
    end
    return missing
end

local function findEarlierStep(self, qids, before)
    local want = {}
    for _, q in ipairs(qids) do want[q] = true end
    for i = 1, before - 1 do
        local s = self.steps[i]
        if s and not s.obsolete then
            for _, q in ipairs(stepQuests(s)) do
                if want[q] and not doneByState(self, s) then return i, q end
            end
        end
    end
    return nil
end

-- returns index, title; nil, title if the quest isn't in this guide; nil if nothing is missing
function QF:SkippedFor(step, index)
    if not step or step.obsolete then return nil end
    local missing = self:MissingQuestsFor(step)
    if #missing == 0 then return nil end
    local i, q = findEarlierStep(self, missing, index or self.char.step)
    if i then
        local s = self.steps[i]
        return i, self:QuestTitle(q, s.qtitle or nil)
    end
    return nil, self:QuestTitle(missing[1])
end

function QF:SkippedLine(step)
    local i, title = self:SkippedFor(step)
    if i then
        return ("|cffff6666  You skipped %s (step %d), which this step needs. Type /qf fix to go back to it, or click Next.|r")
            :format("\"" .. title .. "\"", i)
    elseif title then
        return ("|cffff6666  This needs %s, which you haven't done. Click Next to skip it.|r"):format("\"" .. title .. "\"")
    end
    return nil
end

function QF:FixSkipped()
    local cur = self.char.step
    local step = self:CurrentStep()
    local first = self:SkippedFor(step)
    if not first then
        local _, title = self:SkippedFor(step)
        if title then
            self:Print(("\"%s\" isn't in this guide - use /qf resync to find where you are."):format(title))
        else
            self:Print("Nothing skipped that this step needs.")
        end
        return
    end
    -- follow prereqs back a few levels, a skipped accept can itself need a skipped quest
    local want = {}
    for _, q in ipairs(self:MissingQuestsFor(step)) do want[q] = true end
    for _ = 1, MAX_FIX_DEPTH do
        local added = false
        for i = 1, cur - 1 do
            local s = self.steps[i]
            for _, q in ipairs(stepQuests(s)) do
                if want[q] and not doneByState(self, s) then
                    if s.manualDone then s.manualDone = nil end
                    if i < first then first = i end
                    for _, p in ipairs(self:MissingQuestsFor(s)) do
                        if not want[p] then want[p] = true; added = true end
                    end
                end
            end
        end
        if not added then break end
    end
    self.holdStep = nil
    self.char.step = first
    self:Print(("Back to step %d - the guide continues from there."):format(first))
    self:Update()
end
