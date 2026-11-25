-- Questfarer - Buttons: secure, so changes wait out combat and they get their own holder

local _, ns = ...
local QF = ns.QF
local W = QF.W
local C = W.colors

local B = {}
QF.Buttons = B

BINDING_HEADER_QUESTFARER = "Questfarer"
_G["BINDING_NAME_CLICK QuestfarerItemButton:LeftButton"] = "Use the step's quest item"
_G["BINDING_NAME_CLICK QuestfarerTargetButton:LeftButton"] = "Target the step's NPC or mob"

local SIZE = 40
local GAP = 6
local HANDLE = 8

local getItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local getItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local getItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local getItemCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown

local function makeButton(name, holder)
    local b = CreateFrame("Button", name, holder, "SecureActionButtonTemplate")
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("AnyUp", "AnyDown")
    W.Panel(b, true)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    b.key = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    b.key:SetPoint("TOPRIGHT", -3, -3)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

function B:Create()
    if self.holder then return end
    local h = CreateFrame("Frame", "QuestfarerButtons", UIParent)
    self.holder = h
    h:SetSize(SIZE * 2 + GAP, SIZE + HANDLE)
    h:SetMovable(true)
    h:SetClampedToScreen(true)
    h:SetFrameStrata("MEDIUM")
    self:ApplyPosition()

    local grip = CreateFrame("Frame", nil, h)
    grip:SetPoint("TOPLEFT")
    grip:SetPoint("TOPRIGHT")
    grip:SetHeight(HANDLE - 2)
    grip:EnableMouse(true)
    local tex = grip:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    W.Color(tex, C.accent, 0.35)
    grip:SetScript("OnMouseDown", function()
        if not InCombatLockdown() and not QF.db.locked then
            h:StartMoving()
            B.moving = true
        end
    end)
    grip:SetScript("OnMouseUp", function() B:StopMoving() end)
    grip:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_TOP")
        GameTooltip:AddLine("Questfarer buttons", 1, 1, 1)
        GameTooltip:AddLine("Drag to move. Set keys under Options > Keybindings > AddOns.", 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.item = makeButton("QuestfarerItemButton", h)
    self.item:SetAttribute("type", "item")
    self.item:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_TOP")
        if B.itemID then GameTooltip:SetItemByID(B.itemID) end
        GameTooltip:Show()
    end)

    self.target = makeButton("QuestfarerTargetButton", h)
    self.target:SetAttribute("type", "macro")
    self.target.icon:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot")
    self.target:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_TOP")
        GameTooltip:AddLine("Target", 1, 1, 1)
        for _, name in ipairs(B.names or {}) do GameTooltip:AddLine(name, 1, 0.82, 0) end
        GameTooltip:Show()
    end)
    h:Hide()
end

-- waits until combat ends
function B:ApplyPosition()
    local h = self.holder
    if not h then return end -- Create reads the saved position
    if InCombatLockdown() then
        self.positionPending = true
        return
    end
    self.positionPending = false
    h:ClearAllPoints()
    local p = QF.db.buttonsPoint
    if p then
        h:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        h:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230)
    end
end

B.ITEM_BINDING = "CLICK QuestfarerItemButton:LeftButton"
B.TARGET_BINDING = "CLICK QuestfarerTargetButton:LeftButton"

function B:KeyText(binding)
    local key = GetBindingKey(binding)
    if not key then return nil end
    return GetBindingText and GetBindingText(key) or key
end

function B:StopMoving()
    if not self.moving or InCombatLockdown() then return end
    self.moving = false
    self.holder:StopMovingOrSizing()
    local point, _, rel, x, y = self.holder:GetPoint()
    QF.db.buttonsPoint = { point, rel, x, y }
end

local function stepItem(step)
    for _, id in ipairs(step.items or {}) do
        if getItemCount(id) > 0 and (step.type == "accept" or getItemSpell(id)) then return id end
    end
    if step.type ~= "complete" or not GetQuestLogSpecialItemInfo then return nil end
    for _, q in ipairs(step.quests or {}) do
        local index = q.id and C_QuestLog.GetLogIndexForQuestID(q.id)
        local link = index and GetQuestLogSpecialItemInfo(index)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then return id end
    end
    return nil
end

local NPC_STEPS = { accept = true, turnin = true, train = true, getfp = true, fly = true, sethearth = true }

local function stepNames(step)
    if step.targets and #step.targets > 0 then return step.targets end
    if step.npc and NPC_STEPS[step.type] then return { step.npc } end
    return nil
end

local function targetMacro(names)
    -- in combat only target when you have none, never pull you off your mob
    local lines = { "/cleartarget [nocombat]" }
    for _, name in ipairs(names) do
        table.insert(lines, "/targetexact [noexists][dead] " .. name)
    end
    -- a star over it makes it easy to spot. Marking is protected, so it must be the slash command, not /run.
    -- /tm toggles, so clear first; skipped in a group, where the marks belong to the group
    table.insert(lines, "/tm [@target,exists,nodead,nogroup] 0")
    table.insert(lines, "/tm [@target,exists,nodead,nogroup] 1")
    return table.concat(lines, "\n")
end

local function keyLabel(button, binding)
    local key = GetBindingKey(binding)
    button.key:SetText(key and key:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a") or "")
end

function B:RefreshItemState()
    if not (self.item and self.itemID) then return end
    local n = getItemCount(self.itemID)
    self.item.count:SetText(n > 1 and n or "")
    if getItemCooldown then
        local start, duration = getItemCooldown(self.itemID)
        if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then return end
        if start and duration then self.item.cooldown:SetCooldown(start, duration) end
    end
end

function B:Update()
    if not self.holder or not QF.char then return end
    if InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = false
    local step = QF:CurrentStep()
    local id = step and QF.db.itemButton and stepItem(step) or nil
    local names = step and QF.db.targetButton and stepNames(step) or nil

    if id ~= self.itemID then
        self.itemID = id
        self.item:SetAttribute("item", id and ("item:" .. id) or nil)
        if id then self.item.icon:SetTexture(getItemIcon(id)) end
    end
    local macro = names and targetMacro(names) or nil
    if macro ~= self.macro then
        self.macro, self.names = macro, names
        self.target:SetAttribute("macrotext", macro)
    end

    self.item:ClearAllPoints()
    self.target:ClearAllPoints()
    self.item:SetPoint("BOTTOMLEFT")
    self.target:SetPoint("BOTTOMLEFT", id and (SIZE + GAP) or 0, 0)
    self.item:SetShown(id ~= nil)
    self.target:SetShown(macro ~= nil)
    self.holder:SetShown(id ~= nil or macro ~= nil)
    keyLabel(self.item, self.ITEM_BINDING)
    keyLabel(self.target, self.TARGET_BINDING)
    self:RefreshItemState()
end

-- secure buttons can't be set up in combat (/reload mid-fight), wait for it to end
local function start()
    B:Create()
    hooksecurefunc(QF, "Update", function() B:Update() end)
    C_Timer.After(1, function() B:Update() end)
end

QF:On("PLAYER_LOGIN", function()
    if not InCombatLockdown() then start() end
end)

QF:On("PLAYER_REGEN_ENABLED", function()
    if not B.holder then
        start()
        return
    end
    if B.positionPending then B:ApplyPosition() end
    if B.pending then B:Update() end
end)

-- fires just before combat locks the buttons, last chance to end a drag
QF:On("PLAYER_REGEN_DISABLED", function() B:StopMoving() end)

QF:On("BAG_UPDATE_DELAYED", function() B:Update() end)
QF:On("BAG_UPDATE_COOLDOWN", function() B:RefreshItemState() end)
QF:On("UPDATE_BINDINGS", function() B:Update() end)
