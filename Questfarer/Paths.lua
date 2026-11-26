-- Questfarer - Paths: arrow checkpoints, learned ones saved in QuestfarerDB.paths (all characters)

local _, ns = ...
local QF = ns.QF

local Paths = {}
QF.Paths = Paths

local PASS = 30            -- yards: checkpoint reached this close
local ROUTE_EVERY = 1.0    -- seconds
local DETOUR_MAX = 2.0     -- zone route at most this many times the straight line...
local DETOUR_ADD = 300     -- ...plus yards, so a missing crossing can't send you around the world
local SAMPLE_EVERY = 1.0   -- seconds
local SAMPLE_MOVE = 20     -- yards moved before a new sample
local TELEPORT = 120       -- yards between samples: a teleport, not running
local LEARN_MIN = 150      -- yards: shortest straight line worth learning a path for
local LEARN_RATIO = 1.35   -- path must be this much longer than the straight line
local LEARN_SLOW = 3       -- skip paths that took this many times the run time
local RUN_SPEED = 7        -- yards per second
local MAX_SPEED = 16       -- yards per second, faster than any mount
local SIMPLIFY = 40        -- yards: path simplification tolerance
local START_NEAR = 250     -- yards: use a learned path when starting this close to its start
local MERGE = 150          -- yards: crossings this close are the same one
local CONFIRMED = 2        -- crossings there before a learned one beats the estimate
local PROGRESS = 0.8       -- passed when this much closer to the next point than the checkpoint is
local NEAR_TARGET = 80     -- yards: ignore checkpoints this close to the step

-- { zoneA, zoneB, map of x/y, x, y, name }. Estimates from spawn data, not checked in-game.
Paths.SEED = {
    -- Eastern Kingdoms
    { 1429, 1453, 1429, 32.4, 49.5, "Stormwind gate" },
    { 1429, 1436, 1429, 19.3, 79.4, "Elwynn Forest - Westfall" },
    { 1429, 1431, 1431, 73.6, 13.4, "Elwynn Forest - Duskwood road" },
    { 1429, 1433, 1429, 94.7, 72.9, "Elwynn Forest - Redridge road" },
    { 1436, 1431, 1431, 11.3, 75.7, "Westfall - Duskwood road" },
    { 1431, 1434, 1434, 37.7, 2.3, "Duskwood - Stranglethorn road" },
    { 1426, 1455, 1426, 53.5, 35.3, "Ironforge gate" },
    { 1426, 1432, 1426, 88.8, 48.5, "Dun Morogh - Loch Modan tunnel" },
    { 1432, 1437, 1437, 57.2, 85.6, "Dun Algaz" },
    { 1418, 1432, 1432, 37.1, 89.6, "Loch Modan - Badlands pass" },
    { 1437, 1417, 1437, 51.4, 7.8, "Thandol Span" },
    { 1420, 1422, 1420, 84.3, 70.8, "The Bulwark" },
    { 1420, 1421, 1420, 54.9, 77.4, "Tirisfal Glades - Silverpine road" },
    { 1420, 1458, 1420, 60.8, 69.3, "Undercity entrance" },
    { 1424, 1421, 1424, 13.5, 46.8, "Silverpine - Hillsbrad road" },
    { 2548, 1433, 1433, 44.7, 13.7, "Redridge - Riverglades road" },
    { 2548, 1428, 1428, 96.7, 33.2, "Burning Steppes - Riverglades road" },
    -- Kalimdor
    { 1438, 1457, 1438, 35.8, 54.7, "Darnassus gate" },
    { 1440, 1413, 1413, 47.3, 4.1, "Mor'shan Rampart" },
    { 1440, 1448, 1448, 54.7, 92.5, "Ashenvale - Felwood road" },
    { 1448, 1452, 1452, 27.7, 34.1, "Timbermaw Hold tunnel" },
    { 1452, 2482, 1452, 50.2, 82.9, "Darkwhisper Gorge (to Mount Hyjal)" },
    { 1413, 1445, 1445, 29.0, 48.5, "Barrens - Dustwallow road" },
    { 1413, 1441, 1441, 32.1, 20.3, "The Great Lift" },
    { 1413, 1412, 1412, 65.0, 62.5, "Mulgore - Barrens road" },
    { 1441, 1444, 1444, 90.1, 45.2, "Feralas - Thousand Needles road" },
    { 1443, 1444, 1443, 41.6, 96.7, "Desolace - Feralas road" },
    { 1411, 1454, 1411, 46.0, 12.2, "Orgrimmar gate" },
}

local ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

-- secret values on Forever: treat as unknown
local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- sub-zones and caves climb up to their zone
local zoneCache = {}
function Paths:ZoneOf(mapID)
    if not mapID then return nil end
    local z = zoneCache[mapID]
    if z ~= nil then return z or nil end
    local m, guard = mapID, 0
    z = false
    while m and guard < 10 do
        local info = C_Map.GetMapInfo(m)
        if not info then break end
        if info.mapType == ZONE then z = m break end
        if info.mapType <= CONTINENT then break end
        m = info.parentMapID
        guard = guard + 1
    end
    zoneCache[mapID] = z
    return z or nil
end

-- x, y in percent; returns continent, X (north), Y (west)
local worldCache = {}
function Paths:World(mapID, x, y)
    local key = mapID .. ":" .. x .. ":" .. y
    local w = worldCache[key]
    if w == nil then
        w = false
        if C_Map.GetWorldPosFromMapPos then
            local c, v = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x / 100, y / 100))
            if c and v then w = { c, v.x, v.y } end
        end
        worldCache[key] = w
    end
    if not w then return nil end
    return w[1], w[2], w[3]
end

-- returns continent, X, Y, zone
function Paths:PlayerWorld()
    local here = C_Map.GetBestMapForUnit("player")
    if not here or not C_Map.GetWorldPosFromMapPos then return nil end
    local pos = C_Map.GetPlayerMapPosition(here, "player")
    if not pos then return nil end
    local px, py = pos:GetXY()
    if not px or (px == 0 and py == 0) then return nil end
    local c, v = C_Map.GetWorldPosFromMapPos(here, pos)
    if not (c and v) then return nil end
    return c, v.x, v.y, self:ZoneOf(here)
end

local function db()
    local d = QF.db and QF.db.paths
    if not d then return nil end
    d.crossings = d.crossings or {}
    d.learned = d.learned or {}
    return d
end

local function pairKey(a, b)
    if a > b then a, b = b, a end
    return a .. "-" .. b
end

-- Zone route

-- a learned crossing replaces the estimate after CONFIRMED uses, before that only counts where there's none
function Paths:Crossings()
    if self.crossings then return self.crossings end
    local list, learnedPairs, seeded = {}, {}, {}
    for _, s in ipairs(self.SEED) do seeded[pairKey(s[1], s[2])] = true end
    local d = db()
    if d then
        for key, pts in pairs(d.crossings) do
            local a, b = key:match("^(%d+)-(%d+)$")
            a, b = tonumber(a), tonumber(b)
            if a and b then
                local confirmed = false
                for _, p in ipairs(pts) do
                    if (p[4] or 1) >= CONFIRMED then confirmed = true end
                end
                if confirmed then learnedPairs[key] = true end
                for _, p in ipairs(pts) do
                    if (p[4] or 1) >= CONFIRMED or not seeded[key] then
                        table.insert(list, { a = a, b = b, c = p[1], x = p[2], y = p[3], name = "where you crossed before" })
                    end
                end
            end
        end
    end
    for _, s in ipairs(self.SEED) do
        if not learnedPairs[pairKey(s[1], s[2])] then
            local c, x, y = self:World(s[3], s[4], s[5])
            if c then
                table.insert(list, { a = s[1], b = s[2], c = c, x = x, y = y, name = s[6] })
            end
        end
    end
    self.crossings = list
    self.skipCross = nil
    return list
end

-- returns the crossings in order and the total length, or nil
function Paths:ZoneRoute(pc, px, py, from, tc, tx, ty, to)
    local cross = self:Crossings()
    -- Dijkstra over (crossing, zone you are in after it).
    local best, prev, done = {}, {}, {}
    local function key(i, z) return i .. ":" .. z end
    local nodes = {}
    local skip = self.skipCross or {}
    for i, cr in ipairs(cross) do
        if cr.c == pc and not skip[cr] and (cr.a == from or cr.b == from) then
            local z = (cr.a == from) and cr.b or cr.a
            local k = key(i, z)
            best[k] = dist(px, py, cr.x, cr.y)
            nodes[k] = { i = i, z = z }
        end
    end
    local goal, goalLen = nil, math.huge
    while true do
        local k, kd = nil, math.huge
        for nk, d in pairs(best) do
            if not done[nk] and d < kd then k, kd = nk, d end
        end
        if not k or kd >= goalLen then break end
        done[k] = true
        local n = nodes[k]
        local cr = cross[n.i]
        if n.z == to then
            local total = kd + dist(cr.x, cr.y, tx, ty)
            if total < goalLen then goal, goalLen = k, total end
        else
            for j, cj in ipairs(cross) do
                if j ~= n.i and cj.c == pc and not skip[cj] and (cj.a == n.z or cj.b == n.z) then
                    local z = (cj.a == n.z) and cj.b or cj.a
                    local nk = key(j, z)
                    local nd = kd + dist(cr.x, cr.y, cj.x, cj.y)
                    if not done[nk] and nd < (best[nk] or math.huge) then
                        best[nk], prev[nk], nodes[nk] = nd, k, { i = j, z = z }
                    end
                end
            end
        end
    end
    if not goal then return nil end
    local route, k = {}, goal
    while k do
        table.insert(route, 1, cross[nodes[k].i])
        k = prev[k]
    end
    return route, goalLen
end

-- Arrow target

local function targetKey(step)
    return ("%d:%.1f:%.1f"):format(step.map or 0, step.x or 0, step.y or 0)
end

-- the guide's via points or a learned path, minus the ones right at the step
function Paths:StepCheckpoints(step, pc, px, py)
    local list = self:RawCheckpoints(step, pc, px, py)
    local tc, tx, ty = self:World(step.map, step.x, step.y)
    if not tc then return list end
    local out = {}
    for _, cp in ipairs(list) do
        if cp.c ~= tc or dist(cp.x, cp.y, tx, ty) > NEAR_TARGET then table.insert(out, cp) end
    end
    return out
end

function Paths:RawCheckpoints(step, pc, px, py)
    local list = {}
    if step.via then
        for _, v in ipairs(step.via) do
            local c, x, y = self:World(v[3] or step.map, v[1], v[2])
            if c then table.insert(list, { c = c, x = x, y = y }) end
        end
        return list
    end
    local d = db()
    local learned = d and d.learned[targetKey(step)]
    if learned and pc then
        -- use the path that started near you
        for _, path in ipairs(learned) do
            if path.start[1] == pc and dist(px, py, path.start[2], path.start[3]) <= START_NEAR then
                for _, p in ipairs(path.via) do
                    table.insert(list, { c = p[1], x = p[2], y = p[3] })
                end
                return list
            end
        end
    end
    return list
end

-- returns continent, X, Y, label, or nil to point at the step itself
function Paths:Next(step)
    if not (QF.db and QF.db.checkpoints) or not (step and step.x and step.y and step.map) then return nil end
    if UnitOnTaxi and UnitOnTaxi("player") then return nil end
    local pc, px, py, zone = self:PlayerWorld()
    if not pc then return nil end
    local tc, tx, ty = self:World(step.map, step.x, step.y)
    if not tc or tc ~= pc then return nil end

    if self.step ~= step then
        self.step = step
        self.checkpoints = self:StepCheckpoints(step, pc, px, py)
        self.cpIndex = 1
        self.routeAt = nil
        self.skipCross = nil
    end

    -- passed when at it, or clearly closer to the point after it
    local cps = self.checkpoints
    if dist(px, py, tx, ty) <= NEAR_TARGET then
        self.cpIndex = #cps + 1
    end
    for i = #cps, self.cpIndex, -1 do
        local c = cps[i]
        local passed
        if cps[i + 1] then
            passed = dist(px, py, c.x, c.y) <= PASS
                or dist(px, py, cps[i + 1].x, cps[i + 1].y) < dist(c.x, c.y, cps[i + 1].x, cps[i + 1].y) * PROGRESS
        elseif step.via then
            -- the guide's last point is the way in, being close to the step as the crow flies says nothing
            passed = dist(px, py, c.x, c.y) <= PASS * 2
        else
            passed = dist(px, py, c.x, c.y) <= PASS or dist(px, py, tx, ty) < dist(c.x, c.y, tx, ty) * PROGRESS
        end
        if c.c == pc and passed then
            self.cpIndex = i + 1
            break
        end
    end
    local cp = cps[self.cpIndex]
    if cp and cp.c == pc then
        return pc, cp.x, cp.y, ("Checkpoint %d/%d"):format(self.cpIndex, #cps)
    end

    local to = self:ZoneOf(step.map)
    if not (zone and to) or zone == to then return nil end
    local now = GetTime()
    if not self.routeAt or now - self.routeAt >= ROUTE_EVERY or self.routeZone ~= zone then
        self.routeAt, self.routeZone = now, zone
        local route, len = self:ZoneRoute(pc, px, py, zone, tc, tx, ty, to)
        if route and len > dist(px, py, tx, ty) * DETOUR_MAX + DETOUR_ADD then route = nil end
        self.route = route
    end
    local route = self.route
    if not route then return nil end
    local i = 1
    -- on the crossing but not across yet: next point
    if dist(px, py, route[1].x, route[1].y) <= PASS then i = 2 end
    local cr = route[i]
    self.shownCross = cr
    if not cr then return nil end
    return pc, cr.x, cr.y, "Via " .. cr.name
end

function Paths:SkipCheckpoint()
    if self.checkpoints and self.checkpoints[self.cpIndex] then
        self.cpIndex = self.cpIndex + 1
        QF:Print("Checkpoint skipped.")
    elseif self.shownCross and self.step == QF:CurrentStep() then
        self.skipCross = self.skipCross or {}
        self.skipCross[self.shownCross] = true
        self.shownCross, self.routeAt = nil, nil
        QF:Print("Zone crossing skipped for this step.")
    else
        QF:Print("No checkpoint to skip.")
    end
end

-- Learning

-- Douglas-Peucker
local function simplify(pts, tol)
    if #pts <= 2 then return pts end
    local keep = { [1] = true, [#pts] = true }
    local function rec(i, j)
        local ax, ay, bx, by = pts[i][2], pts[i][3], pts[j][2], pts[j][3]
        local len = dist(ax, ay, bx, by)
        local far, fi = 0, nil
        for k = i + 1, j - 1 do
            local d
            if len == 0 then
                d = dist(pts[k][2], pts[k][3], ax, ay)
            else
                d = math.abs((bx - ax) * (ay - pts[k][3]) - (ax - pts[k][2]) * (by - ay)) / len
            end
            if d > far then far, fi = d, k end
        end
        if fi and far > tol then
            keep[fi] = true
            rec(i, fi)
            rec(fi, j)
        end
    end
    rec(1, #pts)
    local out = {}
    for k = 1, #pts do
        if keep[k] then table.insert(out, pts[k]) end
    end
    return out
end

local LEARN_TYPES = { accept = true, turnin = true, getfp = true, fly = true, sethearth = true, go = true, train = true }

-- keep the path if you ran to the old step the long way around
function Paths:FinishTrack(step)
    local track = self.track
    self.track = nil
    if not (track and step and track.step == step and LEARN_TYPES[step.type] and step.x and step.map) then return end
    local d = db()
    if not d or #track.pts < 3 then return end
    local tc, tx, ty = self:World(step.map, step.x, step.y)
    local last = track.pts[#track.pts]
    if not tc or last[1] ~= tc or dist(last[2], last[3], tx, ty) > 40 then return end -- didn't end at the step
    local first = track.pts[1]
    local straight = dist(first[2], first[3], tx, ty)
    if straight < LEARN_MIN then return end
    local walked = 0
    for i = 2, #track.pts do
        walked = walked + dist(track.pts[i - 1][2], track.pts[i - 1][3], track.pts[i][2], track.pts[i][3])
    end
    if walked < straight * LEARN_RATIO then return end
    if GetTime() - track.t0 > walked / RUN_SPEED * LEARN_SLOW + 30 then return end
    local simple = simplify(track.pts, SIMPLIFY)
    local via = {}
    for i = 2, #simple - 1 do
        local p = simple[i]
        table.insert(via, { p[1], math.floor(p[2] + 0.5), math.floor(p[3] + 0.5) })
    end
    if #via == 0 then return end
    local key = targetKey(step)
    local list = d.learned[key] or {}
    -- replace a path that started near the same place
    for i = #list, 1, -1 do
        local s = list[i].start
        if s[1] == first[1] and dist(s[2], s[3], first[2], first[3]) <= START_NEAR then table.remove(list, i) end
    end
    table.insert(list, { start = { first[1], math.floor(first[2] + 0.5), math.floor(first[3] + 0.5) }, via = via })
    d.learned[key] = list
    QF:Debug("Learned a path with", #via, "checkpoints to", key)
end

function Paths:LearnCrossing(a, b, c, x, y)
    local d = db()
    if not d then return end
    local key = pairKey(a, b)
    local list = d.crossings[key] or {}
    for _, p in ipairs(list) do
        if p[1] == c and dist(p[2], p[3], x, y) <= MERGE then
            local n = (p[4] or 1) + 1
            p[2] = math.floor((p[2] * (n - 1) + x) / n + 0.5)
            p[3] = math.floor((p[3] * (n - 1) + y) / n + 0.5)
            p[4] = n
            self.crossings = nil
            return
        end
    end
    table.insert(list, { c, math.floor(x + 0.5), math.floor(y + 0.5), 1 })
    d.crossings[key] = list
    self.crossings = nil
    self.routeAt = nil
    QF:Debug("Learned a crossing", key)
end

-- tracks paths to the step and zone crossings on foot
function Paths:Sample()
    if not (QF.db and QF.db.checkpoints) then return end
    local pc, px, py, zone = self:PlayerWorld()
    local onTaxi = UnitOnTaxi and plain(UnitOnTaxi("player"))
    local dead = UnitIsDeadOrGhost and plain(UnitIsDeadOrGhost("player"))
    if not pc or onTaxi or dead then
        self.last, self.track = nil, nil
        return
    end
    local now = GetTime()
    local last = self.last
    -- jumped: teleport or transport, guessed from distance (GetUnitSpeed is secret on Forever)
    local jumped = false
    if last then
        local moved = dist(px, py, last.x, last.y)
        local dt = math.max(0.1, now - last.t)
        local moving = IsPlayerMoving and plain(IsPlayerMoving())
        jumped = last.c ~= pc or moved > TELEPORT * math.max(1, dt) or moved > MAX_SPEED * dt * 1.25 + 10
            or (moving == false and moved > 8)
    end
    if last and not jumped and zone and last.zone and zone ~= last.zone then
        self:LearnCrossing(last.zone, zone, pc, (px + last.x) / 2, (py + last.y) / 2)
        self.routeAt = nil
    end
    self.last = { c = pc, x = px, y = py, zone = zone, t = now }

    local step = QF:CurrentStep()
    if jumped or not step then
        self.track = nil
        return
    end
    local track = self.track
    if not track or track.step ~= step then
        self.track = { step = step, t0 = now, pts = { { pc, px, py } } }
        return
    end
    local lp = track.pts[#track.pts]
    if dist(px, py, lp[2], lp[3]) >= SAMPLE_MOVE then
        table.insert(track.pts, { pc, px, py })
        if #track.pts > 400 then table.remove(track.pts, 2) end
    end
end

-- the track to the old step ends where you are now
function Paths:OnStepChanged()
    local track = self.track
    if track then
        local pc, px, py = self:PlayerWorld()
        if pc then table.insert(track.pts, { pc, px, py }) end
        self:FinishTrack(track.step)
    end
    self.track = nil
end

function Paths:StatsLines()
    local d = db()
    local nc, nl = 0, 0
    if d then
        for _, l in pairs(d.crossings) do nc = nc + #l end
        for _, l in pairs(d.learned) do nl = nl + #l end
    end
    return { ("Checkpoints: %d zone crossings estimated, %d learned crossings, %d learned paths. %s"):format(
        #self.SEED, nc, nl, QF.db.checkpoints and "On." or "Off (/qf checkpoints).") }
end

function Paths:PrintStats()
    QF:PrintLines(self:StatsLines())
end

function Paths:Reset()
    local d = db()
    if d then
        wipe(d.crossings)
        wipe(d.learned)
    end
    self.crossings, self.route, self.routeAt, self.step = nil, nil, nil, nil
    QF:Print("Learned checkpoints cleared.")
end

QF:On("PLAYER_LOGIN", function()
    local elapsed = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < SAMPLE_EVERY then return end
        elapsed = 0
        -- on an error, stop learning for this session
        if Paths.broken then return end
        local ok, err = pcall(Paths.Sample, Paths)
        if not ok then
            Paths.broken = true
            QF:Print("Checkpoint learning stopped for this session after an error: " .. tostring(err))
        end
    end)
end)
