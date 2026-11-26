-- Questfarer - Gear: rough upgrade hints from one stat weighting per class

local _, ns = ...
local QF = ns.QF

local G = {}
QF.Gear = G

local MIN_GAIN = 0.03  -- upgrade must be this share better...
local MIN_SCORE = 0.5  -- ...and this many points

local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local getItemStats = (C_Item and C_Item.GetItemStats) or GetItemStats
local equipByName = (C_Item and C_Item.EquipItemByName) or EquipItemByName

-- points per stat. dps: melee weapon dps, ranged: ranged weapon dps
local WEIGHTS = {
    WARRIOR = { str = 2, agi = 1, sta = 1, armor = 0.02, ap = 0.8, dps = 7, ranged = 0.5 },
    PALADIN = { str = 2, agi = 0.8, sta = 1, int = 0.7, spi = 0.3, armor = 0.02, ap = 0.8, sp = 0.6, dps = 7 },
    HUNTER = { agi = 2, sta = 1, int = 0.6, spi = 0.3, armor = 0.015, ap = 0.8, dps = 0.8, ranged = 8 },
    ROGUE = { agi = 2, str = 1, sta = 1, armor = 0.015, ap = 0.8, dps = 7, ranged = 0.3 },
    SHAMAN = { str = 1.6, agi = 1, sta = 1, int = 1, spi = 0.4, armor = 0.015, ap = 0.7, sp = 0.8, dps = 6 },
    DRUID = { str = 1.6, agi = 1.4, sta = 1, int = 0.8, spi = 0.5, armor = 0.02, ap = 0.8, sp = 0.6, dps = 1 },
    MAGE = { int = 1.6, spi = 1, sta = 1, armor = 0.005, sp = 1.4, dps = 0.2, ranged = 3 },
    PRIEST = { int = 1.3, spi = 1.5, sta = 1, armor = 0.005, sp = 1.4, dps = 0.2, ranged = 4 },
    WARLOCK = { int = 1.2, spi = 0.8, sta = 1.5, armor = 0.005, sp = 1.4, dps = 0.2, ranged = 3 },
}

local STATS = {
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", RESISTANCE0_NAME = "armor",
    ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_SPELL_POWER_SHORT = "sp",
}

-- armor subclass (0 misc, 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield) = level the class learns it
local ARMOR = {
    WARRIOR = { [0] = 1, 1, 1, 1, 40, [6] = 1 }, PALADIN = { [0] = 1, 1, 1, 1, 40, [6] = 1 },
    HUNTER = { [0] = 1, 1, 1, 40 }, SHAMAN = { [0] = 1, 1, 1, 40, [6] = 1 },
    ROGUE = { [0] = 1, 1, 1 }, DRUID = { [0] = 1, 1, 1 },
    MAGE = { [0] = 1, 1 }, PRIEST = { [0] = 1, 1 }, WARLOCK = { [0] = 1, 1 },
}

-- weapon subclasses: 0 axe, 1 2H axe, 2 bow, 3 gun, 4 mace, 5 2H mace, 6 polearm, 7 sword,
-- 8 2H sword, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand.
local function set(...)
    local s = {}
    for _, v in ipairs({ ... }) do s[v] = true end
    return s
end
local WEAPONS = {
    WARRIOR = set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18), PALADIN = set(0, 1, 4, 5, 6, 7, 8),
    HUNTER = set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18), ROGUE = set(2, 3, 4, 7, 13, 15, 16, 18),
    SHAMAN = set(0, 1, 4, 5, 10, 13, 15), DRUID = set(4, 5, 10, 13, 15),
    MAGE = set(7, 10, 15, 19), PRIEST = set(4, 10, 15, 19), WARLOCK = set(7, 10, 15, 19),
}
local MELEE = { ROGUE = true, WARRIOR = true, HUNTER = true } -- off hand gets a weapon, not a holdable

-- what the character really learned, not just what the class can use
local KNOWN = (IsPlayerSpell or IsSpellKnown)
local ARMOR_SPELL = { [3] = 8737, [4] = 750, [6] = 9116 }
local WEAPON_SPELL = { [0] = 196, [1] = 197, [2] = 264, [3] = 266, [4] = 198, [5] = 199, [6] = 200, [7] = 201, [8] = 202,
    [10] = 227, [13] = 15590, [15] = 1180, [16] = 2567, [18] = 5011, [19] = 5009 }
local DUAL_WIELD_SPELL = 674

local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_SHIELD = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

local function usable(class, classID, subID, equipLoc, minLevel, level)
    if (minLevel or 0) > level then return false end
    if equipLoc == "INVTYPE_WEAPONOFFHAND" and not KNOWN(DUAL_WIELD_SPELL) then return false end
    if equipLoc == "INVTYPE_HOLDABLE" and MELEE[class] then return false end
    if classID == 4 then
        local from = ARMOR[class][subID]
        if from == nil or level < from then return false end
        return ARMOR_SPELL[subID] == nil or KNOWN(ARMOR_SPELL[subID])
    elseif classID == 2 then
        return WEAPONS[class][subID] == true and WEAPON_SPELL[subID] ~= nil and KNOWN(WEAPON_SPELL[subID])
    end
    return false
end

local scores = {}

-- nil: not loaded yet, or not wearable
local function score(link)
    local cached = scores[link]
    if cached then return cached end
    local _, _, _, _, _, _, _, _, equipLoc = getItemInfo(link)
    if not equipLoc or not SLOTS[equipLoc] then return nil end
    local stats = getItemStats(link) or {}
    local w, total = WEIGHTS[QF.player.class], 0
    for key, value in pairs(stats) do
        local name = STATS[key]
        if name and w[name] then total = total + value * w[name] end
    end
    local dps = stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
    if dps then total = total + dps * ((RANGED[equipLoc] and w.ranged or w.dps) or 0) end
    scores[link] = total
    return total
end

-- 0 when empty, nil while item data loads
local function worn(slot)
    local link = GetInventoryItemLink("player", slot)
    if not link then return 0 end
    return score(link)
end

-- percent of everything worn, an empty old item would give silly numbers
local function wornTotal()
    local total = 0
    for s = 1, 18 do
        if s ~= 4 then -- shirt
            local v = worn(s)
            if v == nil then return nil end
            total = total + v
        end
    end
    return total
end

local OFF_HAND = { INVTYPE_SHIELD = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true }

local function wieldsTwoHander()
    local link = GetInventoryItemLink("player", 16)
    return link and select(9, getItemInfo(link)) == "INVTYPE_2HWEAPON"
end

-- returns gain (points), share, slot, or nil when no upgrade
function G:Upgrade(link)
    local class, level = QF.player.class, UnitLevel("player")
    local _, _, _, _, minLevel, _, _, _, equipLoc, _, _, classID, subID = getItemInfo(link)
    if not equipLoc or not usable(class, classID, subID, equipLoc, minLevel, level) then return nil end
    if OFF_HAND[equipLoc] and wieldsTwoHander() then return nil end -- it would take your two-hander off
    local new = score(link)
    if not new or new <= 0 then return nil end
    local old, slot
    for _, s in ipairs(SLOTS[equipLoc]) do
        local v = worn(s)
        if v == nil then return nil end
        if not old or v < old then old, slot = v, s end
    end
    if equipLoc == "INVTYPE_2HWEAPON" then
        local off = worn(17)
        if off == nil then return nil end
        old = old + off
    end
    local gain = new - old
    if gain < MIN_SCORE or new < old * (1 + MIN_GAIN) then return nil end
    local total = wornTotal()
    if total == nil then return nil end
    return gain, total > 0 and gain / total or nil, slot
end

local function gainText(share)
    return share and ("+%d%%"):format(share * 100 + 0.5) or "empty slot"
end

local function upMarker(btn)
    if btn.fgUpMarker then return btn.fgUpMarker end
    local m = CreateFrame("Frame", nil, btn)
    m:SetFrameLevel(btn:GetFrameLevel() + 6)
    m:SetAllPoints(btn.Icon or btn.icon or _G[(btn:GetName() or "") .. "IconTexture"] or btn)
    local glow = m:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", 2, -2)
    glow:SetColorTexture(0.2, 1, 0.3, 0.22)
    m.label = m:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    m.label:SetPoint("BOTTOMLEFT", 1, 1)
    m.label:SetTextColor(0.3, 1, 0.4)
    btn:HookScript("OnEnter", function()
        if m:IsShown() and m.note then
            GameTooltip:AddLine("Questfarer: " .. m.note, 0.3, 1, 0.4)
            GameTooltip:Show()
        end
    end)
    btn.fgUpMarker = m
    return m
end

function G:ClearRewards()
    if self.marker then self.marker:Hide() end
    self.marker = nil
end

function G:MarkReward(tries)
    self:ClearRewards()
    if not QF.db.gearHint then return end
    local best
    for i = 1, GetNumQuestChoices() or 0 do
        local link = GetQuestItemLink("choice", i)
        if not link or not getItemInfo(link) then
            if (tries or 0) < 10 then
                C_Timer.After(0.25, function() G:MarkReward((tries or 0) + 1) end)
            end
            return
        end
        local gain, share = self:Upgrade(link)
        if gain and (not best or gain > best.gain) then best = { index = i, link = link, gain = gain, share = share } end
    end
    if not best then return end
    local btn = QF.Rewards.ChoiceButton(best.index)
    if btn then
        local m = upMarker(btn)
        m.label:SetText("UP")
        m.note = "the best upgrade for you (" .. gainText(best.share) .. ")"
        m:Show()
        self.marker = m
    end
    QF:Print(("Best upgrade for you: %s (%s)."):format(best.link, gainText(best.share)))
end

QF:On("QUEST_COMPLETE", function() C_Timer.After(0.15, function() G:MarkReward(0) end) end)
QF:On("QUEST_FINISHED", function() G:ClearRewards() end)

function G:Scan()
    self.scanQueued = false
    self.best = nil
    if not QF.player then return end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not QF.char.gearIgnored[info.itemID] then
                local gain, share, target = self:Upgrade(info.hyperlink)
                if gain and (not self.best or gain > self.best.gain) then
                    self.best = { link = info.hyperlink, id = info.itemID, gain = gain, share = share, slot = target }
                end
            end
        end
    end
    QF:RequestUpdate()
end

local function queueScan()
    if G.scanQueued then return end
    G.scanQueued = true
    C_Timer.After(1, function() G:Scan() end)
end

function G:IgnoredCount()
    local n = 0
    for _ in pairs(QF.char.gearIgnored) do n = n + 1 end
    return n
end

function G:ClearIgnored()
    wipe(QF.char.gearIgnored)
    queueScan()
end

QF:AddBar({
    icon = "Interface\\Icons\\INV_Chest_Chain",
    color = { 0.2, 0.55, 0.25 },
    text = function()
        local b = QF.db.gearHint and G.best
        return b and ("|cffffffffUpgrade:|r %s  |cff66ff77%s|r"):format(b.link, gainText(b.share)) or nil
    end,
    onClick = function(button)
        local b = G.best
        if not b then return end
        if button == "RightButton" then
            QF.char.gearIgnored[b.id] = true
            queueScan()
        elseif InCombatLockdown() then
            QF:Print("You can't change gear in combat.")
        else
            equipByName(b.link, b.slot)
        end
    end,
    tooltip = function(tip)
        local b = G.best
        if not b then return end
        tip:SetHyperlink(b.link)
        tip:AddLine(" ")
        tip:AddLine("Questfarer: a rough estimate from your class's main stats.", 0.85, 0.85, 0.87, true)
        tip:AddLine("Click: equip it.  Right-click: ignore this item.", 0.6, 0.8, 1)
    end,
})

QF:On("PLAYER_LOGIN", queueScan)
QF:On("BAG_UPDATE_DELAYED", queueScan)
QF:On("PLAYER_EQUIPMENT_CHANGED", queueScan)
QF:On("PLAYER_LEVEL_UP", queueScan)
QF:On("GET_ITEM_INFO_RECEIVED", queueScan)
