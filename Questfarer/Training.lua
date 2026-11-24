-- What you can train right now, from the Classic spell list (Forever uses the same one).

local _, ns = ...
local QF = ns.QF
local WT = ns.WT

local cache -- { level, list }, cleared when spells or level change

local function knows(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then return true end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end

-- known, or a higher rank of it is
local function knowsOrBetter(id)
    if knows(id) then return true end
    local o = WT.overriddenSpellsMap and WT.overriddenSpellsMap[id]
    if o then
        for i = o.index + 1, #o.ranks do
            if knows(o.ranks[i]) then return true end
        end
    end
    return false
end

function QF:HasSpellData()
    return WT.SpellsByLevel ~= nil
end

-- spellID -> "waiting" or "answered", each spell is requested once
local spellRequests = {}

local function spellName(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if not name and GetSpellInfo then name = GetSpellInfo(id) end
    if not name and not spellRequests[id] and C_Spell and C_Spell.RequestLoadSpellData then
        spellRequests[id] = "waiting"
        C_Spell.RequestLoadSpellData(id)
    end
    local rank = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
    if rank == "" then rank = nil end
    return name or ("Spell #" .. id), rank
end

-- ignores level
local function trainable(spell)
    if WT.PetAbilityIds and WT.PetAbilityIds[spell.id] then return false end
    if knowsOrBetter(spell.id) then return false end
    if spell.requiredTalentId and not knows(spell.requiredTalentId) then return false end
    if spell.requiredIds then
        for _, req in ipairs(spell.requiredIds) do
            if not knowsOrBetter(req) then return false end
        end
    end
    return true
end

-- sorted by level, entries { id, level, cost, name, rank }
function QF:GetTrainableSpells()
    if not self:HasSpellData() then return nil end
    local level = UnitLevel("player")
    if cache and cache.level == level then return cache.list end
    local list = {}
    for lvl, spells in pairs(WT.SpellsByLevel) do
        if lvl <= level then
            for _, spell in ipairs(spells) do
                if trainable(spell) then
                    local name, rank = spellName(spell.id)
                    table.insert(list, { id = spell.id, level = lvl, cost = spell.cost or 0, name = name, rank = rank })
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.name < b.name
    end)
    cache = { level = level, list = list }
    return list
end

-- spells from the next level that has any
function QF:GetUpcomingSpells()
    if not self:HasSpellData() then return nil end
    local level = UnitLevel("player")
    for lvl = level + 1, 60 do
        local spells = WT.SpellsByLevel[lvl]
        if spells and #spells > 0 then
            local list = {}
            for _, spell in ipairs(spells) do
                if not (WT.PetAbilityIds and WT.PetAbilityIds[spell.id]) and not spell.requiredTalentId then
                    local name, rank = spellName(spell.id)
                    table.insert(list, { id = spell.id, level = lvl, cost = spell.cost or 0, name = name, rank = rank })
                end
            end
            if #list > 0 then return list, lvl end
        end
    end
    return nil
end

-- new since the player last trained or skipped training
function QF:NewTrainableSpells()
    local list = self:GetTrainableSpells()
    if not list then return nil end
    local since = self.char.lastTrainLevel or 0
    local out = {}
    for _, s in ipairs(list) do
        if s.level > since then table.insert(out, s) end
    end
    return out
end

function QF:FormatMoney(copper)
    copper = math.floor(copper or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, "|cffffd700" .. g .. "g|r") end
    if s > 0 then table.insert(parts, "|cffc7c7cf" .. s .. "s|r") end
    if c > 0 or #parts == 0 then table.insert(parts, "|cffeda55f" .. c .. "c|r") end
    return table.concat(parts, " ")
end

function QF:SpellLine(s)
    local rank = s.rank and (" |cff999999(" .. s.rank .. ")|r") or ""
    return s.name .. rank
end

function QF:TrainingSummary(list)
    local total = 0
    for _, s in ipairs(list) do total = total + s.cost end
    local word = #list == 1 and "spell" or "spells"
    return ("%d new %s (%s)"):format(#list, word, self:FormatMoney(total)), total
end

function QF:AddTrainingTooltip(tooltip)
    local list = self:GetTrainableSpells()
    if not list then
        tooltip:AddLine("No spell data for your class.", 1, 1, 1)
        return
    end
    if #list == 0 then
        tooltip:AddLine("Nothing to train right now.", 0.7, 0.7, 0.7)
    else
        local summary, total = self:TrainingSummary(list)
        tooltip:AddLine("Trainable now: " .. summary, 1, 1, 1)
        for _, s in ipairs(list) do
            tooltip:AddDoubleLine(self:SpellLine(s), self:FormatMoney(s.cost), 1, 0.82, 0, 1, 1, 1)
        end
        local money = GetMoney()
        if money < total then
            tooltip:AddLine("You have " .. self:FormatMoney(money) .. " - not enough for everything.", 1, 0.4, 0.4)
        end
    end
    local upcoming, lvl = self:GetUpcomingSpells()
    if upcoming then
        local names = {}
        for _, s in ipairs(upcoming) do table.insert(names, s.name) end
        tooltip:AddLine(" ")
        tooltip:AddLine("Level " .. lvl .. ": " .. table.concat(names, ", "), 0.6, 0.8, 1, true)
    end
    tooltip:AddLine(" ")
    tooltip:AddLine("Costs are Classic prices and may differ slightly on Forever.", 0.5, 0.5, 0.5, true)
end

-- /qf spells, also shown in the settings window
function QF:TrainableLines()
    local list = self:GetTrainableSpells()
    if not list then return { "No spell data for your class." } end
    local lines = {}
    if #list == 0 then
        table.insert(lines, "Nothing to train right now.")
    else
        table.insert(lines, "Trainable now: " .. self:TrainingSummary(list))
        for _, s in ipairs(list) do
            table.insert(lines, ("lvl %d  %s  %s"):format(s.level, self:SpellLine(s), self:FormatMoney(s.cost)))
        end
    end
    local upcoming, lvl = self:GetUpcomingSpells()
    if upcoming then
        local names = {}
        for _, s in ipairs(upcoming) do table.insert(names, s.name) end
        table.insert(lines, "Next at level " .. lvl .. ": " .. table.concat(names, ", "))
    end
    return lines
end

function QF:PrintTrainable()
    self:PrintLines(self:TrainableLines())
end

local function invalidate()
    cache = nil
    QF:RequestUpdate()
end

QF:On("SPELLS_CHANGED", invalidate)
QF:On("LEARNED_SPELL_IN_SKILL_LINE", invalidate)
QF:On("SPELL_DATA_LOAD_RESULT", function(_, _, spellID, success) -- names that weren't loaded yet
    if spellRequests[spellID] ~= "waiting" then return end
    spellRequests[spellID] = "answered"
    if success then invalidate() end
end)
QF:On("PLAYER_LEVEL_UP", function(self, _, level)
    cache = nil
    -- UnitLevel can lag one level behind during the event
    C_Timer.After(0.5, function()
        cache = nil
        local list = self:NewTrainableSpells()
        if self.db.trainReminder and list and #list > 0 then
            local names = {}
            for _, s in ipairs(list) do table.insert(names, s.name) end
            self:Print(("Level %d: |cff00ff00%s|r at your class trainer: %s"):format(
                UnitLevel("player"), self:TrainingSummary(list), table.concat(names, ", ")))
        end
        self:RequestUpdate()
    end)
end)
