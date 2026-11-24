-- Questfarer - MapAreas: dots where a step's mobs and items are

local _, ns = ...
local QF = ns.QF

local M = {}
QF.MapAreas = M

local COLOR = { 1, 0.55, 0.1 }
local DOT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local WORLD_ALPHA, MINI_ALPHA = 0.55, 0.8
local WORLD_SIZE = 0.016  -- share of the map's width
local MINI_SIZE = 8
local MINI_TICK = 0.25

-- Minimap radius in yards at each zoom level (0-5).
local OUTDOOR = { [0] = 233.3, 200, 166.7, 133.3, 100, 66.7 }
local INDOOR = { [0] = 150, 120, 90, 60, 40, 25 }

local function currentArea()
    if not QF.db.mapAreas then return nil end
    local step = QF:CurrentStep()
    if step and step.area and #step.area >= 4 then return step.area, step.map end
    return nil
end

local function dotPool(parent, pool, n, alpha)
    for i = #pool + 1, n do
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetTexture(DOT)
        t:SetVertexColor(COLOR[1], COLOR[2], COLOR[3], alpha)
        pool[i] = t
    end
    return pool
end

function M:RefreshWorldMap()
    local map = _G.WorldMapFrame
    local canvas = map and map.ScrollContainer and map.ScrollContainer.Child
    if not canvas or not map:IsShown() then return end
    if not self.world then
        self.world = CreateFrame("Frame", nil, canvas)
        self.world:SetAllPoints(canvas)
        self.world:SetFrameLevel(canvas:GetFrameLevel() + 500)
        self.worldDots = {}
    end
    local area, mapID = currentArea()
    local n = (area and map:GetMapID() == mapID) and #area / 2 or 0
    dotPool(self.world, self.worldDots, n, WORLD_ALPHA)
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local size = w * WORLD_SIZE
    for i, dot in ipairs(self.worldDots) do
        if i <= n then
            dot:SetSize(size, size)
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", self.world, "TOPLEFT", area[i * 2 - 1] / 100 * w, -area[i * 2] / 100 * h)
            dot:Show()
        else
            dot:Hide()
        end
    end
end

local function hideMini()
    for _, dot in ipairs(M.miniDots or {}) do dot:Hide() end
end

local function drawMinimap()
    local area, mapID = currentArea()
    local pos = area and C_Map.GetPlayerMapPosition(mapID, "player")
    local size = pos and QF.MapYards(mapID)
    if not size then
        hideMini()
        return
    end
    local px, py = pos:GetXY()
    if not px or (px == 0 and py == 0) then
        hideMini()
        return
    end
    local radius = (IsIndoors() and INDOOR or OUTDOOR)[Minimap:GetZoom()] or 133.3
    local scale = Minimap:GetWidth() / 2 / radius
    local sin, cos = 0, 1
    if GetCVar("rotateMinimap") == "1" then
        local facing = GetPlayerFacing()
        if not facing or (issecretvalue and issecretvalue(facing)) then
            hideMini()
            return
        end
        sin, cos = math.sin(facing), math.cos(facing)
    end
    local n = #area / 2
    dotPool(M.mini, M.miniDots, n, MINI_ALPHA)
    for i, dot in ipairs(M.miniDots) do
        local shown = false
        if i <= n then
            local east = (area[i * 2 - 1] / 100 - px) * size[1]
            local north = (py - area[i * 2] / 100) * size[2]
            if east * east + north * north < (radius * 0.94) ^ 2 then
                dot:SetSize(MINI_SIZE, MINI_SIZE)
                dot:ClearAllPoints()
                dot:SetPoint("CENTER", M.mini, "CENTER", (east * cos + north * sin) * scale, (north * cos - east * sin) * scale)
                shown = true
            end
        end
        dot:SetShown(shown)
    end
end

function M:StartMinimap()
    self.mini = CreateFrame("Frame", nil, Minimap)
    self.mini:SetAllPoints(Minimap)
    self.mini:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    self.miniDots = {}
    local ticker
    ticker = C_Timer.NewTicker(MINI_TICK, function()
        local ok, err = pcall(drawMinimap)
        if not ok then -- client can't do minimap dots, keep only the world map
            ticker:Cancel()
            hideMini()
            QF:Debug("Minimap dots stopped:", err)
        end
    end)
end

QF:On("PLAYER_LOGIN", function()
    M:StartMinimap()
    local map = _G.WorldMapFrame
    if map then
        map:HookScript("OnShow", function() M:RefreshWorldMap() end)
        if map.OnMapChanged then hooksecurefunc(map, "OnMapChanged", function() M:RefreshWorldMap() end) end
    end
    hooksecurefunc(QF, "Update", function() M:RefreshWorldMap() end)
end)
