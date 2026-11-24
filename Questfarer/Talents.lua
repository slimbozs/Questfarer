-- Suggests the next talent point. Plan talents this client doesn't have are skipped.

local _, ns = ...
local QF = ns.QF

local T = {}
QF.Talents = T

local PLANS = {
    WARRIOR = { -- Arms, then Fury
        { "Improved Heroic Strike", 3 }, { "Improved Rend", 3 }, { "Tactical Mastery", 5 }, { "Anger Management", 1 },
        { "Deep Wounds", 3 }, { "Two-Handed Weapon Specialization", 5 }, { "Sweeping Strikes", 1 },
        { "Axe Specialization", 5 }, { "Impale", 2 }, { "Improved Overpower", 2 }, { "Mortal Strike", 1 },
        { "Cruelty", 5 }, { "Unbridled Wrath", 5 }, { "Improved Battle Shout", 5 }, { "Enrage", 5 },
    },
    PALADIN = { -- Retribution, then Holy
        { "Improved Blessing of Might", 5 }, { "Benediction", 5 }, { "Improved Judgement", 2 }, { "Deflection", 3 },
        { "Conviction", 5 }, { "Seal of Command", 1 }, { "Pursuit of Justice", 2 }, { "Vindication", 3 },
        { "Two-Handed Weapon Specialization", 3 }, { "Sanctity Aura", 1 }, { "Vengeance", 5 }, { "Repentance", 1 },
        { "Divine Strength", 5 }, { "Divine Intellect", 5 }, { "Improved Seal of Righteousness", 5 },
    },
    HUNTER = { -- Beast Mastery, then Marksmanship
        { "Improved Aspect of the Hawk", 5 }, { "Endurance Training", 5 }, { "Thick Hide", 3 },
        { "Unleashed Fury", 5 }, { "Bestial Swiftness", 1 }, { "Ferocity", 5 }, { "Intimidation", 1 },
        { "Bestial Discipline", 2 }, { "Spirit Bond", 2 }, { "Frenzy", 5 }, { "Bestial Wrath", 1 },
        { "Efficiency", 5 }, { "Lethal Shots", 5 }, { "Aimed Shot", 1 }, { "Improved Hunter's Mark", 5 },
    },
    MAGE = { -- Frost, then Arcane
        { "Improved Frostbolt", 5 }, { "Elemental Precision", 3 }, { "Ice Shards", 5 }, { "Frostbite", 3 },
        { "Improved Blizzard", 3 }, { "Piercing Ice", 3 }, { "Cold Snap", 1 }, { "Frost Channeling", 3 },
        { "Improved Frost Nova", 2 }, { "Shatter", 5 }, { "Ice Block", 1 }, { "Improved Cone of Cold", 3 },
        { "Ice Barrier", 1 }, { "Winter's Chill", 5 }, { "Arcane Focus", 5 }, { "Improved Arcane Missiles", 5 },
    },
    PRIEST = { -- Shadow, then Discipline
        { "Spirit Tap", 5 }, { "Improved Shadow Word: Pain", 2 }, { "Shadow Focus", 3 }, { "Improved Mind Blast", 5 },
        { "Mind Flay", 1 }, { "Shadow Reach", 3 }, { "Shadow Weaving", 5 }, { "Vampiric Embrace", 1 },
        { "Improved Vampiric Embrace", 2 }, { "Darkness", 5 }, { "Shadowform", 1 }, { "Unbreakable Will", 5 },
        { "Wand Specialization", 5 }, { "Improved Power Word: Shield", 3 }, { "Improved Power Word: Fortitude", 2 },
        { "Meditation", 3 }, { "Inner Focus", 1 },
    },
    ROGUE = { -- Combat, then Assassination
        { "Improved Sinister Strike", 2 }, { "Lightning Reflexes", 3 }, { "Precision", 5 }, { "Deflection", 5 },
        { "Dual Wield Specialization", 5 }, { "Blade Flurry", 1 }, { "Sword Specialization", 5 }, { "Weapon Expertise", 2 },
        { "Aggression", 3 }, { "Adrenaline Rush", 1 }, { "Riposte", 1 }, { "Malice", 5 }, { "Ruthlessness", 3 },
        { "Improved Eviscerate", 3 }, { "Murder", 2 }, { "Relentless Strikes", 1 }, { "Remorseless Attacks", 2 }, { "Lethality", 5 },
    },
    SHAMAN = { -- Enhancement, then Restoration
        { "Ancestral Knowledge", 5 }, { "Thundering Strikes", 5 }, { "Improved Ghost Wolf", 2 }, { "Two-Handed Axes and Maces", 1 },
        { "Anticipation", 5 }, { "Toughness", 5 }, { "Flurry", 5 }, { "Parry", 1 }, { "Elemental Weapons", 3 },
        { "Weapon Mastery", 5 }, { "Stormstrike", 1 }, { "Improved Healing Wave", 5 }, { "Tidal Focus", 5 },
        { "Ancestral Healing", 3 },
    },
    WARLOCK = { -- Affliction, then Demonology
        { "Improved Corruption", 5 }, { "Suppression", 5 }, { "Improved Drain Life", 5 }, { "Fel Concentration", 5 },
        { "Nightfall", 2 }, { "Grim Reach", 2 }, { "Improved Curse of Agony", 3 }, { "Siphon Life", 1 }, { "Amplify Curse", 1 },
        { "Shadow Mastery", 5 }, { "Dark Pact", 1 }, { "Demonic Embrace", 5 }, { "Improved Voidwalker", 3 },
        { "Fel Intellect", 3 }, { "Fel Stamina", 5 }, { "Fel Domination", 1 },
    },
    DRUID = { -- Feral, then Restoration
        { "Ferocity", 5 }, { "Feral Instinct", 5 }, { "Thick Hide", 3 }, { "Feline Swiftness", 2 }, { "Sharpened Claws", 3 },
        { "Predatory Strikes", 3 }, { "Blood Frenzy", 2 }, { "Primal Fury", 2 }, { "Feral Charge", 1 }, { "Savage Fury", 2 },
        { "Faerie Fire (Feral)", 1 }, { "Heart of the Wild", 5 }, { "Leader of the Pack", 1 },
        { "Furor", 5 }, { "Improved Mark of the Wild", 5 }, { "Improved Enrage", 2 }, { "Nature's Focus", 5 },
    },
}

local function supported()
    return GetNumTalentTabs and GetNumTalents and GetTalentInfo
end

local function unspent()
    if UnitCharacterPoints then return UnitCharacterPoints("player") or 0 end
    if GetUnspentTalentPoints then return GetUnspentTalentPoints() or 0 end
    return 0
end

-- returns name -> { tab, index, tier, rank, max }, points spent per tree
local function readTree()
    local byName, spent = {}, {}
    for tab = 1, GetNumTalentTabs() do
        spent[tab] = 0
        for i = 1, GetNumTalents(tab) do
            local name, _, tier, _, rank, max = GetTalentInfo(tab, i)
            if name then
                byName[name] = { tab = tab, index = i, tier = tier or 1, rank = rank or 0, max = max or 1 }
                spent[tab] = spent[tab] + (rank or 0)
            end
        end
    end
    return byName, spent
end

local function canTake(t, spent)
    if spent[t.tab] < (t.tier - 1) * 5 then return false end
    if GetTalentPrereqs then
        local _, _, learnable = GetTalentPrereqs(t.tab, t.index)
        if learnable == false then return false end
    end
    return true
end

-- returns up to count { name, rank, max, tree }
function T:Next(count)
    local plan = PLANS[QF.player.class]
    if not (plan and supported()) then return {} end
    local byName, spent = readTree()
    local out = {}
    for _, entry in ipairs(plan) do
        local t = byName[entry[1]]
        if t and t.rank < math.min(entry[2], t.max) and canTake(t, spent) then
            table.insert(out, { name = entry[1], rank = t.rank + 1, max = math.min(entry[2], t.max),
                tree = GetTalentTabInfo(t.tab) })
            if #out >= count then break end
        end
    end
    return out
end

function T:Refresh()
    self.next = nil
    if unspent() > 0 then
        local ok, list = pcall(self.Next, self, 3)
        if ok then self.next = list end
    end
    QF:RequestUpdate()
end

local function openTalents()
    if InCombatLockdown() then return end
    if ToggleTalentFrame then
        ToggleTalentFrame()
    elseif PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then
        PlayerSpellsUtil.ToggleClassTalentFrame()
    else
        QF:Print("Open your talents from the game menu.")
    end
end

QF:AddBar({
    icon = "Interface\\Icons\\INV_Misc_Book_11",
    color = { 0.16, 0.5, 0.3 },
    text = function()
        local t = QF.db.talentHint and T.next and T.next[1]
        return t and ("|cffffffffTalent:|r |cffffd100%s|r  %d/%d"):format(t.name, t.rank, t.max) or nil
    end,
    onClick = openTalents,
    tooltip = function(tip)
        tip:AddLine("Your next talent points", 1, 1, 1)
        for _, t in ipairs(T.next or {}) do
            tip:AddDoubleLine(t.name, ("%d/%d  %s"):format(t.rank, t.max, t.tree or ""), 1, 0.82, 0, 0.85, 0.85, 0.87)
        end
        tip:AddLine("Click: open your talents. You spend the point yourself.", 0.6, 0.8, 1, true)
    end,
})

-- /qf talents, also shown in the settings window
function T:Lines()
    local plan = PLANS[QF.player.class]
    if not (plan and supported()) then
        return { "There are no talent suggestions for your character on this client." }
    end
    local ok, byName = pcall(readTree)
    if not ok then return { "Your talents can't be read right now." } end
    local lines = { ("Talent plan (%d unspent):"):format(unspent()) }
    local missing = 0
    for _, entry in ipairs(plan) do
        local t = byName[entry[1]]
        if t then
            local want = math.min(entry[2], t.max)
            table.insert(lines, ("%s%s  %d/%d|r"):format(t.rank >= want and "|cff55dd55" or "|cffffffff", entry[1], t.rank, want))
        else
            missing = missing + 1
        end
    end
    if missing > 0 then
        table.insert(lines, ("%d talent%s in the plan don't exist here and are skipped."):format(missing, missing == 1 and "" or "s"))
    end
    return lines
end

function T:Print()
    QF:PrintLines(self:Lines())
end

QF:On("PLAYER_LOGIN", function() C_Timer.After(2, function() T:Refresh() end) end)
QF:On("PLAYER_LEVEL_UP", function() C_Timer.After(1, function() T:Refresh() end) end)
QF:On("CHARACTER_POINTS_CHANGED", function() T:Refresh() end)
QF:On("PLAYER_TALENT_UPDATE", function() T:Refresh() end)
