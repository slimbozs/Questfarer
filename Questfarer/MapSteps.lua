-- Questfarer - MapSteps: numbered circles on the world map for the current step and the next few

local _, ns = ...
local QF = ns.QF
local W = QF.W

local S = {}
QF.MapSteps = S

local AHEAD = 5           -- steps after the current one
local LOOK = 40           -- steps to look through for those
local SAME_SPOT = 1.2     -- map %, steps this close share a circle
local SIZE = 26           -- on screen, however big or zoomed the map is
local NEXT_SIZE = 22

local function place(step)
    return step and step.x and step.y and step.map and not step.obsolete
end

-- { step index, step } for the current step and the next ones with a place, done ones left out
local function upcoming()
    local list = {}
    local first = QF.char and QF.char.step
    if not (first and QF.steps) then return list end
    local cur = QF.steps[first]
    if place(cur) then table.insert(list, { first, cur }) end
    local ahead = 0
    for i = first + 1, first + LOOK do
        local s = QF.steps[i]
        if not s or ahead >= AHEAD then break end
        if place(s) and not QF:IsStepDone(s) then
            table.insert(list, { i, s })
            ahead = ahead + 1
        end
    end
    return list
end

-- steps at the same spot share one circle, numbered by the first
local function group(list, mapID)
    local pins = {}
    for _, e in ipairs(list) do
        local s = e[2]
        if s.map == mapID then
            local pin
            for _, p in ipairs(pins) do
                if math.abs(p.x - s.x) <= SAME_SPOT and math.abs(p.y - s.y) <= SAME_SPOT then pin = p break end
            end
            if pin then
                table.insert(pin.steps, e)
            else
                table.insert(pins, { x = s.x, y = s.y, steps = { e }, current = e[1] == QF.char.step })
            end
        end
    end
    return pins
end

local function showTip(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Questfarer", 0.93, 0.76, 0.42)
    for _, e in ipairs(pin.steps or {}) do
        GameTooltip:AddLine(("%d  %s"):format(e[1], QF:StepText(e[2])), 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function newPin(parent)
    local pin = CreateFrame("Button", nil, parent)
    pin.disc = pin:CreateTexture(nil, "BACKGROUND")
    pin.disc:SetAllPoints()
    pin.disc:SetTexture(W.MEDIA .. "shape_circle.tga")
    pin.ring = pin:CreateTexture(nil, "BORDER")
    pin.ring:SetAllPoints()
    pin.ring:SetTexture(W.MEDIA .. "shape_ring.tga")
    pin.num = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pin.num:SetPoint("CENTER", 0, 0)
    pin:SetScript("OnEnter", showTip)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return pin
end

local function paint(pin, p, size)
    local C = W.colors
    local first = p.steps[1]
    local style = W.StepStyle(first[2].type)
    pin.steps = p.steps
    pin:SetSize(size, size)
    if p.current then
        pin.disc:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        pin.ring:SetVertexColor(0.93, 0.76, 0.42)
    else
        pin.disc:SetVertexColor(0.055, 0.045, 0.035, 0.9)
        pin.ring:SetVertexColor(style.color[1], style.color[2], style.color[3])
    end
    pin.num:SetText(first[1])
    W.FontSize(pin.num, size * (first[1] >= 100 and 0.42 or 0.52))
end

function S:Refresh()
    local map = _G.WorldMapFrame
    local canvas = map and map.ScrollContainer and map.ScrollContainer.Child
    if not canvas or not map:IsShown() then return end
    if not self.frame then
        self.frame = CreateFrame("Frame", nil, canvas)
        self.frame:SetAllPoints(canvas)
        self.pins, self.lines = {}, {}
    end
    W.AboveMap(self.frame, canvas, 2)
    local pins = QF.db.mapSteps and group(upcoming(), map:GetMapID()) or {}
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = canvas:GetEffectiveScale() / UIParent:GetEffectiveScale()
    for i, p in ipairs(pins) do
        local pin = self.pins[i] or newPin(self.frame)
        self.pins[i] = pin
        paint(pin, p, (p.current and SIZE or NEXT_SIZE) / scale)
        pin:SetFrameLevel(self.frame:GetFrameLevel() + 20 - i)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", self.frame, "TOPLEFT", p.x / 100 * w, -p.y / 100 * h)
        pin:Show()
    end
    for i = #pins + 1, #self.pins do self.pins[i]:Hide() end

    -- a faint line from each circle to the next, under the circles
    for i = 1, #pins - 1 do
        local line = self.lines[i]
        if not line and self.frame.CreateLine then
            line = self.frame:CreateLine(nil, "ARTWORK")
            self.lines[i] = line
        end
        if line then
            line:SetThickness(2 / scale)
            line:SetColorTexture(0.93, 0.76, 0.42, 0.45)
            line:SetStartPoint("TOPLEFT", self.frame, pins[i].x / 100 * w, -pins[i].y / 100 * h)
            line:SetEndPoint("TOPLEFT", self.frame, pins[i + 1].x / 100 * w, -pins[i + 1].y / 100 * h)
            line:Show()
        end
    end
    for i = math.max(1, #pins), #self.lines do self.lines[i]:Hide() end
end

local function refresh()
    local ok, err = pcall(S.Refresh, S)
    if not ok then QF:Debug("Map steps:", err) end
end

QF:On("PLAYER_LOGIN", function()
    local map = _G.WorldMapFrame
    if map then
        map:HookScript("OnShow", refresh)
        if map.OnMapChanged then hooksecurefunc(map, "OnMapChanged", refresh) end
        if map.OnCanvasScaleChanged then hooksecurefunc(map, "OnCanvasScaleChanged", refresh) end
    end
    hooksecurefunc(QF, "Update", refresh)
end)
