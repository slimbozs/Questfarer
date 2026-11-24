-- Questfarer - ClassQuests: side guides, afterwards back to the route step you left

local _, ns = ...
local QF = ns.QF

local CQ = {}
QF.ClassQuests = CQ

local function lastQuest(guide)
    for i = #guide.steps, 1, -1 do
        local s = guide.steps[i]
        if s.turnin and QF:StepApplies(s) then return s.turnin end
    end
end

-- by quest ID only, chain quests often share a title
local function finished(guide)
    local q = lastQuest(guide)
    return q ~= nil and QF:IsTurnedIn(q)
end

function CQ:Available()
    local list = {}
    local level = UnitLevel("player")
    for _, name in ipairs(QF.guideOrder) do
        local g = QF.guides[name]
        if g.side and QF:GuideApplies(g) and level >= (g.minLevel or 1)
            and not QF.char.sideHidden[name] and not finished(g) then
            table.insert(list, g)
        end
    end
    table.sort(list, function(a, b)
        if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
        return a.name < b.name
    end)
    return list
end

function CQ:Start(name)
    local g = QF.guides[name]
    if not g then return end
    local cur = QF.guide
    if cur and not cur.side then
        QF.char.sideReturn = { guide = cur.name, step = QF.char.step }
    end
    QF:Print(("Class quest: |cffffd100%s|r. |cffffd100/qf class stop|r takes you back to the route."):format(g.ability or g.name))
    QF:LoadGuide(name, 1)
end

function CQ:Stop()
    local back = QF.char.sideReturn
    QF.char.sideReturn = nil
    if back and QF.guides[back.guide] then
        QF:LoadGuide(back.guide, back.step)
    else
        QF:Resync(true, true)
    end
    C_Timer.After(0.5, function() QF:Resync(false, true) end)
end

function CQ:OnFinished()
    QF:Print(("|cff00ff00Class quest done:|r %s. Back to the route."):format(QF.guide.ability or QF.guide.name))
    self:Stop()
end

function CQ:BarText()
    if QF.guide and QF.guide.side then
        return "|cffffffffBack to the route|r"
    end
    local g = self:Available()[1]
    return g and ("|cffffffffClass quest:|r |cffffd100" .. (g.ability or g.name) .. "|r") or nil
end

function CQ:OnBarClick(button)
    if QF.guide and QF.guide.side then
        self:Stop()
        return
    end
    local g = self:Available()[1]
    if not g then return end
    if button == "RightButton" then
        QF.char.sideHidden[g.name] = true
        QF:Print(("Hidden: %s. |cffffd100/qf class|r still lists it."):format(g.ability or g.name))
        QF:RequestUpdate()
    else
        self:Start(g.name)
    end
end

function CQ:AddTooltip(tip)
    if QF.guide and QF.guide.side then
        tip:AddLine("Class quest", 1, 1, 1)
        tip:AddLine("Click: stop here and go back to the route.", 0.6, 0.8, 1)
        return
    end
    local g = self:Available()[1]
    if not g then return end
    tip:AddLine("Class quest", 1, 1, 1)
    tip:AddLine("Teaches: " .. (g.ability or g.name), 1, 0.82, 0)
    tip:AddLine("A short side trip. The guide comes back to this step afterwards.", 0.85, 0.85, 0.87, true)
    tip:AddLine("Click: start.  Right-click: hide.", 0.6, 0.8, 1)
end

-- hidden ones too, order matches /qf class <nr>
function CQ:All()
    local all = {}
    for _, name in ipairs(QF.guideOrder) do
        local g = QF.guides[name]
        if g.side and QF:GuideApplies(g) and not finished(g) then table.insert(all, g) end
    end
    table.sort(all, function(a, b)
        local la, lb = a.minLevel or 1, b.minLevel or 1
        if la ~= lb then return la < lb end
        return a.name < b.name
    end)
    return all
end

function CQ:IsReady(guide)
    return UnitLevel("player") >= (guide.minLevel or 1)
end

function CQ:Pick(guide)
    QF.char.sideHidden[guide.name] = nil
    self:Start(guide.name)
end

function CQ:SetHidden(guide, hidden)
    QF.char.sideHidden[guide.name] = hidden and true or nil
    QF:RequestUpdate()
end

function CQ:Lines()
    local all = self:All()
    if #all == 0 then return { "No class quests left for your character." } end
    local lines = { "Class quests (|cffffd100/qf class <nr>|r starts one):" }
    for i, g in ipairs(all) do
        local state = self:IsReady(g) and "|cff00ff00ready|r" or ("|cff999999level " .. g.minLevel .. "|r")
        table.insert(lines, ("%d. %s  %s"):format(i, g.ability or g.name, state))
    end
    return lines
end

function CQ:Command(arg)
    arg = (arg or ""):lower()
    if arg == "stop" then
        if QF.guide and QF.guide.side then self:Stop() else QF:Print("You are on the route already.") end
        return
    end
    local n = tonumber(arg)
    if n then
        local g = self:All()[n]
        if not g then
            QF:Print("No class quest with that number.")
        elseif not self:IsReady(g) then
            QF:Print(("%s needs level %d."):format(g.ability or g.name, g.minLevel))
        else
            self:Pick(g)
        end
        return
    end
    QF:PrintLines(self:Lines())
end

local function announce()
    for _, g in ipairs(CQ:Available()) do
        if not QF.char.sideNotified[g.name] then
            QF.char.sideNotified[g.name] = true
            QF:Print(("New class quest: |cffffd100%s|r. Click the bar in the guide window to start it."):format(g.ability or g.name))
        end
    end
    if QF.UI then QF.UI:Refresh() end
end

QF:On("PLAYER_LEVEL_UP", function() C_Timer.After(1, announce) end)
QF:On("PLAYER_LOGIN", function() C_Timer.After(5, announce) end)
