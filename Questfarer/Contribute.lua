-- Questfarer - Contribute: opt-in play stats the player can export, never with names

local _, ns = ...
local QF = ns.QF

local C = {}
QF.Contribute = C

-- set these when publishing, nil links are left out
C.DISCORD = nil
C.URL = nil     -- GitHub issue form, template=data_contribution.yml

-- { label, link }, Discord first
function C:Links()
    local links = {}
    if self.DISCORD then
        table.insert(links, { "Discord: post it in the #data-contributions channel.", self.DISCORD })
    end
    if self.URL then
        table.insert(links, { "GitHub: the \"Data contribution\" form.", self.URL })
    end
    return links
end

local PREFIX = "FGDATA1"   -- bump the number if the format changes
local PART_SIZE = 60000    -- chars, a GitHub issue holds about 65000
local MAX_GAP = 180        -- seconds, longer gaps are travel or a break, not downtime
local KILL_WINDOW = 2      -- seconds after a fight its XP still counts
local QUEST_WINDOW = 1     -- seconds, XP this close to a turn-in is quest XP

local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function randomID()
    return ("%08x"):format(math.random(0, 0x7fffffff))
end

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

-- Storage, account-wide so one export covers every character

function C:Store()
    local db = QF.db.contribution
    db.id = db.id or randomID()
    db.chars = db.chars or {}
    return db
end

-- keyed by a random ID, not the character name
function C:CharData()
    local char = QF.char
    char.contribId = char.contribId or randomID()
    local chars = self:Store().chars
    local d = chars[char.contribId]
    if not d then
        d = { levels = {} }
        chars[char.contribId] = d
    end
    d.class, d.race, d.faction = QF.player.class, QF.player.race, QF.player.faction
    return d
end

local function levelData(level)
    local levels = C:CharData().levels
    local key = tostring(level)
    local l = levels[key]
    if not l then
        l = { f = 0, fs = 0, k = 0, kx = 0, qx = 0, q = 0, g = 0, gs = 0, d = 0, diff = {} }
        levels[key] = l
    end
    return l
end

local function collecting()
    return QF.db and QF.db.contribute and QF.char and QF.player
end

local function playerLevel()
    return plain(UnitLevel("player"))
end

-- Counting fights, downtime and XP

local fight          -- { start =, level =, diff = } while in combat
local lastFightEnd   -- GetTime()
local lastFightLevel
local lastTurnin = -100
local lastXP, lastMax, lastLevel

QF:On("PLAYER_REGEN_DISABLED", function()
    if not collecting() then return end
    local level = playerLevel()
    if not level then return end
    local now = GetTime()
    local diff
    pcall(function() -- target values can be secret on this client
        if UnitExists("target") and UnitCanAttack("player", "target") then
            local tl = plain(UnitLevel("target"))
            if tl and tl > 0 then diff = math.max(-5, math.min(5, tl - level)) end
        end
    end)
    if lastFightEnd and now - lastFightEnd <= MAX_GAP then
        local l = levelData(level)
        l.g = l.g + 1
        l.gs = round1(l.gs + now - lastFightEnd)
    end
    fight = { start = now, level = level, diff = diff }
end)

QF:On("PLAYER_REGEN_ENABLED", function()
    if not (fight and collecting()) then
        fight = nil
        return
    end
    local now = GetTime()
    local seconds = now - fight.start
    local l = levelData(fight.level)
    l.f = l.f + 1
    l.fs = round1(l.fs + seconds)
    if fight.diff then
        local key = tostring(fight.diff)
        local dd = l.diff[key] or { f = 0, fs = 0 }
        dd.f = dd.f + 1
        dd.fs = round1(dd.fs + seconds)
        l.diff[key] = dd
    end
    lastFightEnd, lastFightLevel = now, fight.level
    fight = nil
end)

QF:On("QUEST_TURNED_IN", function(_, _, _, xp)
    lastTurnin = GetTime()
    if not collecting() then return end
    local level = playerLevel()
    xp = plain(xp)
    if not level then return end
    local l = levelData(level)
    l.q = l.q + 1
    if type(xp) == "number" and xp > 0 then l.qx = l.qx + xp end
end)

local function onXPGain(gain)
    local now = GetTime()
    if now - lastTurnin <= QUEST_WINDOW then return end
    local level
    if fight then
        level = fight.level
    elseif lastFightEnd and now - lastFightEnd <= KILL_WINDOW then
        level = lastFightLevel
    end
    if not level then return end -- not fight XP
    local l = levelData(level)
    l.k = l.k + 1
    l.kx = l.kx + gain
end

QF:On("PLAYER_XP_UPDATE", function()
    local xp, max, level = plain(UnitXP("player")), plain(UnitXPMax("player")), playerLevel()
    if not (xp and max and level) then return end
    if lastXP and collecting() then
        local gain
        if level == lastLevel and xp >= lastXP then
            gain = xp - lastXP
        elseif level >= lastLevel then
            gain = (lastMax - lastXP) + xp -- leveled up in between
        end
        if gain and gain > 0 then onXPGain(gain) end
    end
    lastXP, lastMax, lastLevel = xp, max, level
end)

QF:On("PLAYER_DEAD", function()
    if not collecting() then return end
    local level = playerLevel()
    if level then
        local l = levelData(level)
        l.d = l.d + 1
    end
end)

QF:On("PLAYER_LOGIN", function()
    lastXP, lastMax, lastLevel = plain(UnitXP("player")), plain(UnitXPMax("player")), playerLevel()
end)

-- Summary for the settings window

function C:SummaryLines()
    local fights, kills, chars, lo, hi = 0, 0, 0, nil, nil
    for _, d in pairs(self:Store().chars) do
        chars = chars + 1
        for key, l in pairs(d.levels or {}) do
            local level = tonumber(key)
            fights, kills = fights + (l.f or 0), kills + (l.k or 0)
            if level then
                lo, hi = math.min(lo or level, level), math.max(hi or level, level)
            end
        end
    end
    local lines = {}
    if QF.db.contribute then
        table.insert(lines, "Collecting is |cff00ff00on|r.")
    else
        table.insert(lines, "Collecting is |cffff4444off|r. Turn it on above to count fights and XP while you play.")
    end
    if fights > 0 then
        table.insert(lines, ("Collected so far: %d fights and %d kills on %d character(s), levels %d-%d.")
            :format(fights, kills, chars, lo or 0, hi or 0))
    end
    table.insert(lines, "The export also holds your level and guide times and the recorder's quest and NPC data. " ..
        "It never holds character, realm or player names.")
    return lines
end

function C:Clear()
    local db = QF.db.contribution
    db.chars = {}
    db.id = randomID() -- new contributor from here on
    QF:Print("Collected share data deleted.")
end

-- Export

-- CBOR-safe copy: string keys, no functions or secret values
local function plainCopy(v, depth)
    if type(v) == "table" then
        if depth > 8 then return nil end
        local out = {}
        for k, x in pairs(v) do
            local c = plainCopy(x, depth + 1)
            if c ~= nil and (type(k) == "string" or type(k) == "number") then out[tostring(k)] = c end
        end
        return out
    end
    if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
        return plain(v)
    end
    return nil
end

-- who you talked to can be a player (shared quest), so only NPC and object names stay
local KEEP_KIND = { Creature = true, GameObject = true, Vehicle = true }

local function scrubNames(t, depth)
    if type(t) ~= "table" or depth > 8 then return end
    -- no kind: the game hid who it was, can't trust it's an NPC
    if (t.kind ~= nil and not KEEP_KIND[t.kind]) or (t.kind == nil and t.npc ~= nil) then
        t.npc, t.npcId, t.name = nil, nil, nil
    end
    for _, v in pairs(t) do scrubNames(v, depth + 1) end
end

function C:BuildData()
    local times = {}
    for _, t in pairs(QF.db.times or {}) do -- keyed by name-realm, leave the key out
        table.insert(times, plainCopy({ class = t.class, race = t.race, levels = t.levels, guides = t.guides }, 0))
    end
    local rec = QF.Recorder and QF.Recorder:DB() or {}
    local recorder = plainCopy({ quests = rec.quests, npcs = rec.npcs, trainers = rec.trainers, taxi = rec.taxi }, 0)
    scrubNames(recorder, 0)
    return {
        format = 1,
        addon = QF.version,
        id = self:Store().id,
        made = time(),
        chars = plainCopy(self:Store().chars, 0),
        times = times,
        recorder = recorder,
    }
end

-- returns parts, or nil and a reason
function C:BuildExport()
    local E = C_EncodingUtil
    if not (E and E.SerializeCBOR and E.CompressString and E.EncodeBase64) then
        return nil, "This game client can't make the export text."
    end
    local ok, text = pcall(function()
        local packed = E.CompressString(E.SerializeCBOR(self:BuildData()), 0) -- 0 = Deflate
        return E.EncodeBase64(packed)
    end)
    if not ok or type(text) ~= "string" then
        return nil, "Making the export text failed: " .. tostring(text)
    end
    local id = ("%06x"):format(math.random(0, 0xffffff))
    local n = math.max(1, math.ceil(#text / PART_SIZE))
    local parts = {}
    for i = 1, n do
        parts[i] = ("%s:%s:%d/%d:%s"):format(PREFIX, id, i, n, text:sub((i - 1) * PART_SIZE + 1, i * PART_SIZE))
    end
    return parts
end

-- Export window

local WIDTH, HEIGHT = 540, 316

-- read-only box to copy text from
local function copyBox(parent, width)
    local W = QF.W
    local box = W.Input(parent, width, 26, "")
    box:SetMaxLetters(0)
    box:SetScript("OnEditFocusGained", function(self)
        W.BorderColor(self, W.colors.accent)
        self:HighlightText()
    end)
    box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self.fixedText and self:GetText() ~= self.fixedText then
            self:SetText(self.fixedText)
            self:HighlightText()
        end
    end)
    function box:SetFixedText(t)
        self.fixedText = t
        self:SetText(t)
        self:SetCursorPosition(0)
    end
    return box
end
C.CopyBox = copyBox

function C:CreateWindow()
    if self.frame then return end
    local W, Col = QF.W, QF.W.colors
    local f = CreateFrame("Frame", "QuestfarerExportFrame", UIParent)
    self.frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    W.Panel(f)
    table.insert(UISpecialFrames, "QuestfarerExportFrame") -- Escape closes it

    local header = W.Header(f, 28, "Interface\\Icons\\INV_Letter_15")
    header.title:SetText("Share your data")
    local close = W.Button(header, "Close", 60, 20, function() f:Hide() end)
    close:SetPoint("RIGHT", -4, 0)

    local help = W.Text(f, "GameFontHighlightSmall", Col.text)
    help:SetPoint("TOPLEFT", 14, -40)
    help:SetWidth(WIDTH - 28)
    help:SetText("1. Click in the box below, then press Ctrl+C to copy the text.\n" ..
        "2. Paste it with Ctrl+V in a message to the person who gave you Questfarer, or at one of the places " ..
        "below. Discord turns long text into a file by itself. On GitHub, put part 1 in the form and any other " ..
        "parts in comments.\n" ..
        "|cff999999The text holds counts, times and quest data. No character, realm or player names.|r")
    self.help = help

    local box = copyBox(f, WIDTH - 28)
    box:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -10)
    self.box = box

    local partText = W.Text(f, "GameFontHighlightSmall", Col.muted)
    partText:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)
    self.partText = partText

    local nextB = W.Button(f, "Next part", 90, 22, function() C:ShowPart(C.part + 1) end)
    nextB:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -6)
    local prevB = W.Button(f, "Previous part", 100, 22, function() C:ShowPart(C.part - 1) end)
    prevB:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    self.nextB, self.prevB = nextB, prevB

    -- up to two links, slot 1 is the lower one
    self.linkSlots = {}
    for i = 1, 2 do
        local y = 14 + (i - 1) * 58
        local label = W.Text(f, "GameFontHighlightSmall", Col.muted)
        label:SetPoint("BOTTOMLEFT", 14, y + 30)
        label:SetWidth(WIDTH - 28)
        label:SetWordWrap(false)
        local link = copyBox(f, WIDTH - 28)
        link:SetPoint("BOTTOMLEFT", 14, y)
        self.linkSlots[i] = { label = label, box = link }
    end
end

function C:ShowPart(i)
    local parts = self.parts
    if not parts or not parts[i] then return end
    self.part = i
    self.box:SetFixedText(parts[i])
    local n = #parts
    self.partText:SetText(n > 1 and ("Part %d of %d (%d characters)"):format(i, n, #parts[i])
        or ("%d characters"):format(#parts[i]))
    self.prevB:SetShown(n > 1)
    self.nextB:SetShown(n > 1)
    self.prevB:SetActive(i > 1)
    self.nextB:SetActive(i < n)
    self.box:SetFocus()
    self.box:HighlightText()
end

function C:ShowExport()
    local parts, err = self:BuildExport()
    if not parts then
        QF:Print("|cffff6666" .. err .. "|r")
        return
    end
    self:CreateWindow()
    self.parts = parts
    local links = self:Links()
    for i, slot in ipairs(self.linkSlots) do
        -- first link in the upper slot when there are two
        local link = links[#links - i + 1]
        slot.label:SetShown(link ~= nil or i == 1)
        slot.box:SetShown(link ~= nil)
        if link then
            slot.label:SetText(link[1])
            slot.box:SetFixedText(link[2])
        elseif i == 1 then
            slot.label:SetText("Send it to the person who gave you Questfarer (a Discord message is fine).")
        end
    end
    self.frame:Show()
    self:ShowPart(1)
end

-- Beta notice and the one-time question about sharing

StaticPopupDialogs.QUESTFARER_SHARE = {
    text = "Questfarer is in beta. Do you want it to count your fights, kills and XP per level, so you can " ..
        "share them later and help fix the route?\n\nNothing is sent by itself and no names are saved. " ..
        "You can change this in the settings (Data page) or with /qf share.",
    button1 = "Yes, collect",
    button2 = "No thanks",
    OnAccept = function()
        QF.db.contribute = true
        QF:Print("Collecting data to share is |cff00ff00on|r. Use /qf export when you want to send it.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

QF:On("PLAYER_LOGIN", function(self)
    C_Timer.After(5, function()
        if not self.db.contribute and not self.db.shareAsked then
            self.db.shareAsked = true
            StaticPopup_Show("QUESTFARER_SHARE")
        end
        if self.db.betaNotice == self.version then return end
        self.db.betaNotice = self.version
        self:Print(("|cffff9933Beta %s|r: the route is new and not fully tested in game yet. Report problems, and " ..
            "share your data if you like (/qf export)."):format(self.version))
        if self.player and self.player.faction == "Horde" then
            self:Print("|cffff9933The Horde guides are the newest|r: they have not been checked as closely as " ..
                "the Alliance guides yet.")
        end
    end)
end)
