-- Questfarer - Guide arrow, since Blizzard's super-track arrow doesn't show on Forever

local _, ns = ...
local QF = ns.QF
local W = QF.W
local C = W.colors

local Arrow = {}
QF.Arrow = Arrow

local SIZE = 52
local ARRIVED = 12 -- yards

-- map size in yards { width, height }, cached per map
local mapSize = {}
local function yardsOf(mapID)
    local s = mapSize[mapID]
    if s ~= nil then return s end
    s = false
    if C_Map.GetWorldPosFromMapPos then
        local c0, w0 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local c1, w1 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
        local c2, w2 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
        if w0 and w1 and w2 and c0 == c1 and c0 == c2 then
            local wd = math.sqrt((w1.x - w0.x) ^ 2 + (w1.y - w0.y) ^ 2)
            local ht = math.sqrt((w2.x - w0.x) ^ 2 + (w2.y - w0.y) ^ 2)
            if wd > 0 and ht > 0 then s = { wd, ht } end
        end
    end
    mapSize[mapID] = s
    return s
end
QF.MapYards = yardsOf

-- fallback when the target's map can't place the player: world positions, X points north, Y west
local function worldVector(mapID, x, y)
    local here = C_Map.GetBestMapForUnit("player")
    local pos = here and C_Map.GetPlayerMapPosition(here, "player")
    if not (pos and C_Map.GetWorldPosFromMapPos) then return nil end
    local c1, w1 = C_Map.GetWorldPosFromMapPos(here, pos)
    local c2, w2 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x / 100, y / 100))
    if not (w1 and w2) or c1 ~= c2 then return nil end
    return -(w2.y - w1.y), w2.x - w1.x
end

local function vectorTo(mapID, x, y)
    local east, north
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    local px, py
    if pos then px, py = pos:GetXY() end
    local size = yardsOf(mapID)
    if px and not (px == 0 and py == 0) and size then
        east = (x / 100 - px) * size[1]
        north = (py - y / 100) * size[2]
    else
        east, north = worldVector(mapID, x, y)
        if not east then return nil end
    end
    local dist = math.sqrt(east * east + north * north)
    local bearing = math.atan2(-east, north)
    return dist, bearing
end

function Arrow:Create()
    if self.frame then return end
    local f = CreateFrame("Frame", "QuestfarerArrow", UIParent)
    self.frame = f
    f:SetSize(140, SIZE + 34)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame)
        if not QF.db.locked then frame:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relPoint, px, py = frame:GetPoint()
        QF.db.arrowPoint = { point, relPoint, px, py }
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and QF.Options then QF.Options:Open() end
    end)
    f:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Questfarer arrow", 1, 1, 1)
        GameTooltip:AddLine("Points to the current step. Drag to move, right-click for settings.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetSize(SIZE, SIZE)
    tex:SetPoint("TOP")
    tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    self.tex = tex

    -- over the game world, so light text with a shadow, not the panel ink
    self.dist = W.Text(f, "GameFontHighlight", { 0.96, 0.93, 0.85 }, 14)
    self.dist:SetShadowOffset(1, -1)
    self.dist:SetPoint("TOP", tex, "BOTTOM", 0, -2)
    self.dist:SetJustifyH("CENTER")
    self.dist:SetWordWrap(false)
    self.label = W.Text(f, "GameFontHighlightSmall", { 0.85, 0.80, 0.70 })
    self.label:SetShadowOffset(1, -1)
    self.label:SetPoint("TOP", self.dist, "BOTTOM", 0, -2)
    self.label:SetWidth(200)
    self.label:SetJustifyH("CENTER")
    self.label:SetWordWrap(false)

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.04 then return end
        elapsed = 0
        Arrow:Update()
    end)
    self:ApplySettings()
end

function Arrow:ApplySettings()
    local f = self.frame
    if not f then return end
    local scale = QF.db.scale or 1
    -- saved position is in the arrow's scale, keep it in place when the scale changes
    local p = QF.db.arrowPoint
    if p and self.appliedScale and self.appliedScale ~= scale then
        p[3], p[4] = p[3] * self.appliedScale / scale, p[4] * self.appliedScale / scale
    end
    self.appliedScale = scale
    f:SetScale(scale)
    f:ClearAllPoints()
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
    f:SetShown(QF.db.arrow and true or false)
end

local function shortLabel(step)
    if step.npc then return step.npc end
    local t = QF:StepText(step):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return t
end

-- invisible arrow must not catch clicks meant for the game world
function Arrow:SetClickable(on)
    if self.clickable == on then return end
    self.clickable = on
    self.frame:EnableMouse(on)
    if not on and GameTooltip:IsOwned(self.frame) then GameTooltip:Hide() end
end

function Arrow:Update()
    local step = QF:CurrentStep()
    local tex = self.tex
    if not (step and step.x and step.y and step.map) or QF.noGuideForLevel then
        tex:SetAlpha(0)
        self.dist:SetText("")
        self.label:SetText("")
        self:SetClickable(false)
        return
    end
    self:SetClickable(true)
    local dist, bearing
    -- checkpoint on the way comes first
    local cc, cx, cy, cpLabel
    if QF.Paths then cc, cx, cy, cpLabel = QF.Paths:Next(step) end
    if cc then
        local pc, px, py = QF.Paths:PlayerWorld()
        if pc == cc then
            local east, north = -(cy - py), cx - px
            dist = math.sqrt(east * east + north * north)
            bearing = math.atan2(-east, north)
        else
            cc = nil
        end
    end
    if cc then
        self.label:SetText(cpLabel)
        tex:SetAlpha(1)
        local facing = GetPlayerFacing and GetPlayerFacing()
        if facing then tex:SetRotation(bearing - facing) end
        tex:SetVertexColor(0.45, 0.8, 1) -- blue = checkpoint
        self.dist:SetText(("%d yd"):format(dist))
        return
    end
    dist, bearing = vectorTo(step.map, step.x, step.y)
    self.label:SetText(shortLabel(step))
    if not dist then
        -- not on this continent (or no map data): no direction
        tex:SetAlpha(0.25)
        tex:SetRotation(0)
        local info = C_Map.GetMapInfo(step.map)
        self.dist:SetText("Go to " .. (info and info.name or "the next zone"))
        return
    end
    tex:SetAlpha(1)
    if dist <= ARRIVED then
        tex:SetRotation(0)
        tex:SetVertexColor(0.3, 1, 0.3)
        self.dist:SetText("You're there")
        return
    end
    local facing = GetPlayerFacing and GetPlayerFacing()
    if facing then
        tex:SetRotation(bearing - facing)
    end
    -- gold far away, turning green as you get close
    local k = math.max(0, math.min(1, (dist - ARRIVED) / 150))
    tex:SetVertexColor(0.3 + 0.7 * k, 1 - 0.18 * k, 0.3 - 0.3 * k)
    self.dist:SetText(("%d yd"):format(dist))
end

QF:On("PLAYER_LOGIN", function()
    Arrow:Create()
end)
