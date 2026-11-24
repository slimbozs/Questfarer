-- The travel journal: days on the road, titles, seals, a few lines per important event and travel numbers.

local _, ns = ...
local QF = ns.QF

local J = {}
QF.Journal = J

local MAX_ENTRIES = 300
local SAMPLE = 1          -- seconds between position samples
local MAX_STEP = 40       -- yards per second, more than that is a teleport or a boat
local YARDS_PER_MILE = 1760

local TITLES = {
    { 1, "Greenhorn" },
    { 5, "Wanderer" },
    { 10, "Pathfinder" },
    { 20, "Wayfarer" },
    { 30, "Seasoned Traveller" },
    { 40, "Roadwarden" },
    { 50, "Veteran of the Road" },
    { 60, "Legend of the Road" },
}

-- stat: which number counts, at: how much it takes
local SEALS = {
    { id = "errand", name = "First Errand", text = "Hand in your first quest.", stat = "quests", at = 1, icon = "INV_Misc_Note_01" },
    { id = "grave", name = "Back from the Grave", text = "Die, and get up again.", stat = "deaths", at = 1, icon = "Spell_Holy_Resurrection" },
    { id = "ten", name = "Ten Summers", text = "Reach level 10.", stat = "level", at = 10, icon = "INV_Sword_04" },
    { id = "wings", name = "Wings of the Road", text = "Take your first flight.", stat = "flights", at = 1, icon = "Spell_Nature_Swiftness" },
    { id = "deep", name = "Into the Deep", text = "Enter your first dungeon.", stat = "dungeons", at = 1, icon = "INV_Misc_Key_03" },
    { id = "roads", name = "Many Roads", text = "Set foot in 10 lands.", stat = "zones", at = 10, icon = "INV_Misc_Map_01" },
    { id = "journeyman", name = "Journeyman", text = "Reach level 20.", stat = "level", at = 20, icon = "INV_Shield_06" },
    { id = "week", name = "A Week on the Road", text = "Travel on 7 different days.", stat = "days", at = 7, icon = "INV_Misc_PocketWatch_01" },
    { id = "hundred", name = "A Hundred Errands", text = "Hand in 100 quests.", stat = "quests", at = 100, icon = "INV_Scroll_03" },
    { id = "seasoned", name = "Seasoned", text = "Reach level 30.", stat = "level", at = 30, icon = "INV_Helmet_08" },
    { id = "miles", name = "A Hundred Miles", text = "Walk or ride 100 miles.", stat = "miles", at = 100, icon = "INV_Boots_01" },
    { id = "roosts", name = "Known at Every Roost", text = "Know 15 flight paths.", stat = "flightPaths", at = 15, icon = "Ability_Hunter_EagleEye" },
    { id = "saddle", name = "Saddle and Stirrup", text = "Reach level 40, old enough for a mount.", stat = "level", at = 40, icon = "Ability_Mount_RidingHorse" },
    { id = "veteran", name = "Veteran", text = "Reach level 50.", stat = "level", at = 50, icon = "INV_Misc_Head_Dragon_01" },
    { id = "errands", name = "Five Hundred Errands", text = "Hand in 500 quests.", stat = "quests", at = 500, icon = "INV_Misc_Book_11" },
    { id = "end", name = "End of the Road", text = "Reach level 60.", stat = "level", at = 60, icon = "INV_Crown_01" },
}
J.SEALS = SEALS

local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function level()
    return plain(UnitLevel("player")) or 1
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local ROMAN = { { 50, "L" }, { 40, "XL" }, { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }
function J.Roman(n)
    local s = ""
    for _, r in ipairs(ROMAN) do
        while n >= r[1] do
            s = s .. r[2]
            n = n - r[1]
        end
    end
    return s
end

function J:Data()
    local c = QF.char
    local j = c.journal
    if not j then
        j = {}
        c.journal = j
    end
    j.entries = j.entries or {}
    j.seals = j.seals or {}
    j.zones = j.zones or {}
    j.dungeons = j.dungeons or {}
    j.flightPaths = j.flightPaths or {}
    j.yards = j.yards or 0
    j.flights = j.flights or 0
    j.hearths = j.hearths or 0
    j.deaths = j.deaths or 0
    j.quests = j.quests or count(c.doneIds) -- quests from before the journal
    return j
end

-- each calendar day the character is played counts as a day of the road
function J:Day()
    local c = QF.char
    local today = date("%Y-%m-%d")
    if c.lastRoadDay ~= today then
        c.lastRoadDay = today
        c.roadDays = (c.roadDays or 0) + 1
        if self.started then self:CheckSeals() end
    end
    return c.roadDays
end

function J:Title(lvl)
    lvl = lvl or level()
    local title = TITLES[1][2]
    for _, t in ipairs(TITLES) do
        if lvl >= t[1] then title = t[2] end
    end
    return title
end

function J:Name()
    return (UnitName("player") or "?") .. ", " .. self:Title()
end

function J:Stat(key)
    local j = self:Data()
    if key == "level" then return level() end
    if key == "days" then return QF.char.roadDays or 1 end
    if key == "miles" then return j.yards / YARDS_PER_MILE end
    if key == "zones" then return count(j.zones) end
    if key == "dungeons" then return count(j.dungeons) end
    if key == "flightPaths" then return count(j.flightPaths) end
    return j[key] or 0
end

function J:Write(text)
    local entries = self:Data().entries
    table.insert(entries, { day = self:Day(), time = time(), text = text })
    while #entries > MAX_ENTRIES do table.remove(entries, 1) end
    if QF.Options then QF.Options:RequestRefresh() end
end

-- quiet: earned at the first login with the journal, no pop-ups
function J:CheckSeals(quiet)
    local j = self:Data()
    for _, s in ipairs(SEALS) do
        if not j.seals[s.id] and self:Stat(s.stat) >= s.at then
            j.seals[s.id] = { day = self:Day(), time = time() }
            if not quiet then
                self:Write("Earned the seal |cffffd100" .. s.name .. "|r. " .. s.text)
                if QF.Popup then QF.Popup:Seal(s) end
            end
        end
    end
end

local function zoneOf(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    while info and info.mapType and info.mapType > 3 and info.parentMapID and info.parentMapID > 0 do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return info
end

function J:Arrived()
    -- lands seen from a flight don't count, the landing does
    if UnitOnTaxi and plain(UnitOnTaxi("player")) then return end
    local j = self:Data()
    local inInstance, kind = IsInInstance()
    if inInstance then
        if kind ~= "party" and kind ~= "raid" then return end
        local name = GetInstanceInfo()
        if name and not j.dungeons[name] then
            j.dungeons[name] = self:Day()
            self:Write("Went down into |cffffd100" .. name .. "|r.")
            self:CheckSeals()
        end
        return
    end
    local info = zoneOf(C_Map.GetBestMapForUnit("player"))
    local name = info and info.mapType == 3 and info.name
    if not name or j.zones[name] then return end
    j.zones[name] = self:Day()
    local chapter = count(j.zones)
    j.chapter = chapter
    self:Write(("Chapter %s: arrived in |cffffd100%s|r at level %d."):format(J.Roman(chapter), name, level()))
    if QF.Popup then QF.Popup:Chapter(chapter, name, level()) end
    self:CheckSeals()
end

function J:LevelUp(newLevel)
    local before = self:Title(newLevel - 1)
    local title = self:Title(newLevel)
    if title ~= before then
        self:Write(("Reached level %d and became known as |cffffd100%s|r."):format(newLevel, title))
        if QF.Popup then QF.Popup:Title(title, newLevel) end
    end
    self:CheckSeals()
    if QF.UI then QF.UI:Refresh() end
end

-- walked and ridden yards, and flights from when the taxi starts
function J:Sample()
    local j = self:Data()
    local onTaxi = UnitOnTaxi and plain(UnitOnTaxi("player"))
    if onTaxi and not self.onTaxi then
        j.flights = j.flights + 1
        self:CheckSeals()
    elseif self.onTaxi and not onTaxi then
        C_Timer.After(1, function() J:Arrived() end)
    end
    self.onTaxi = onTaxi
    if not QF.Paths then return end
    local c, x, y = QF.Paths:PlayerWorld()
    local last = self.last
    self.last = (c and not onTaxi) and { c = c, x = x, y = y } or nil
    if not (self.last and last and last.c == c) then return end
    local moved = math.sqrt((x - last.x) ^ 2 + (y - last.y) ^ 2)
    if moved < MAX_STEP * SAMPLE then
        local before = j.yards
        j.yards = j.yards + moved
        -- check the seal once per mile, not every second
        if math.floor(j.yards / YARDS_PER_MILE) > math.floor(before / YARDS_PER_MILE) then self:CheckSeals() end
    end
end

local function learnFlightPaths()
    local fps = J:Data().flightPaths
    local before = count(fps)
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
        local unreachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable
        local mapID = GetTaxiMapID()
        for _, n in ipairs((mapID and C_TaxiMap.GetAllTaxiNodes(mapID)) or {}) do
            if n.name and n.state ~= unreachable then fps[n.name] = true end
        end
    elseif NumTaxiNodes then
        for i = 1, NumTaxiNodes() do
            local typ = TaxiNodeGetType and TaxiNodeGetType(i)
            if typ ~= "NONE" and typ ~= "DISTANT" then fps[TaxiNodeName(i)] = true end
        end
    end
    if count(fps) > before then J:CheckSeals() end
end

-- travels page in the settings
function J:StatLines()
    local j = self:Data()
    local hours = 0
    for _, s in pairs(QF.char.levelTime or {}) do hours = hours + s end
    hours = hours / 3600
    return {
        { "Traveller", self:Name() },
        { "Days on the road", tostring(self:Stat("days")) },
        { "Time on the road", hours >= 1 and ("%.1f hours"):format(hours) or "under an hour" },
        { "Walked and ridden", ("%.1f miles"):format(self:Stat("miles")) },
        { "Flights taken", tostring(j.flights) },
        { "Flight paths known", tostring(self:Stat("flightPaths")) },
        { "Hearthstones used", tostring(j.hearths) },
        { "Quests handed in", tostring(j.quests) },
        { "Lands visited", tostring(self:Stat("zones")) },
        { "Dungeons entered", tostring(self:Stat("dungeons")) },
        { "Times fallen", tostring(j.deaths) },
        { "Seals earned", ("%d of %d"):format(count(j.seals), #SEALS) },
    }
end

-- newest first, a day heading before each day's lines
function J:EntryLines()
    local entries = self:Data().entries
    local lines, day = {}, nil
    for i = #entries, 1, -1 do
        local e = entries[i]
        if e.day ~= day then
            day = e.day
            table.insert(lines, ("|cffffd100Day %d|r   |cff999999%s|r"):format(day, date("%d %b %Y", e.time)))
        end
        table.insert(lines, { "", e.text })
    end
    if #lines == 0 then lines[1] = "The pages are still empty." end
    return lines
end

function J:Start()
    local fresh = QF.char.journal == nil
    self:Data()
    self:Day()
    if fresh then
        local where = zoneOf(C_Map.GetBestMapForUnit("player"))
        self:Write(("%s opened a travel journal%s, at level %d."):format(UnitName("player") or "?",
            where and where.name and (" in |cffffd100" .. where.name .. "|r") or "", level()))
        -- a character that has already travelled gets its earned seals without a pile of pop-ups
        self:CheckSeals(true)
        -- a new character gets chapter I as a pop-up, an old one just starts counting here
        if where and where.name and level() > 1 then
            self:Data().zones[where.name] = self:Day()
        end
    end
    self.started = true
    C_Timer.NewTicker(SAMPLE, function() J:Sample() end)
    C_Timer.After(2, function() J:Arrived() end)
end

QF:On("PLAYER_LOGIN", function() J:Start() end)

QF:On("PLAYER_LEVEL_UP", function(_, _, newLevel)
    if newLevel then C_Timer.After(0.5, function() J:LevelUp(newLevel) end) end
end)

QF:On("ZONE_CHANGED_NEW_AREA", function()
    if J.started then C_Timer.After(1, function() J:Arrived() end) end
end)

QF:On("PLAYER_ENTERING_WORLD", function()
    if J.started then C_Timer.After(2, function() J:Arrived() end) end
end)

QF:On("QUEST_TURNED_IN", function()
    if not J.started then return end
    local j = J:Data()
    j.quests = j.quests + 1
    J:CheckSeals()
end)

QF:On("PLAYER_DEAD", function()
    if not J.started then return end
    local j = J:Data()
    j.deaths = j.deaths + 1
    J:CheckSeals()
end)

QF:On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, _, spellID)
    if unit ~= "player" or not J.started then return end
    if spellID == 8690 or spellID == 6948 then
        local j = J:Data()
        j.hearths = j.hearths + 1
    end
end)

QF:On("TAXIMAP_OPENED", function()
    if J.started then learnFlightPaths() end
end)
