-- Questfarer - Small shim so the spell data files in Data/Spells/ can load.
-- They expect a table with currentClass, FactionFilter, RaceFilter and AddOverriddenSpells.

local _, ns = ...

local WT = {}
ns.WT = WT

WT.currentClass = select(2, UnitClass("player"))

local function filter(spellsByLevel, keep)
    local out = {}
    for level, spells in pairs(spellsByLevel) do
        out[level] = {}
        for _, spell in ipairs(spells) do
            if keep(spell) then
                table.insert(out[level], spell)
            end
        end
    end
    return out
end

function WT.FactionFilter(spellsByLevel)
    local faction = UnitFactionGroup("player")
    return filter(spellsByLevel, function(spell)
        return spell.faction == nil or spell.faction == faction
    end)
end

function WT.RaceFilter(spellsByLevel)
    local raceID = select(3, UnitRace("player"))
    return filter(spellsByLevel, function(spell)
        if spell.race == nil and spell.races == nil then return true end
        if spell.races == nil then return spell.race == raceID end
        for _, r in ipairs(spell.races) do
            if r == raceID then return true end
        end
        return false
    end)
end

-- Each argument is a list of spell IDs ordered by rank, where a higher rank
-- replaces the lower one in the spellbook (most warrior/rogue abilities).
function WT:AddOverriddenSpells(...)
    local map = {}
    for _, ranks in ipairs({ ... }) do
        for i, id in ipairs(ranks) do
            map[id] = { ranks = ranks, index = i }
        end
    end
    self.overriddenSpellsMap = map
end
