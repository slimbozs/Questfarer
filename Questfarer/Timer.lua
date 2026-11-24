-- Time spent per level and guide, AFK time doesn't count.

local _, ns = ...
local QF = ns.QF

local T = {}
QF.Timer = T

local TICK = 5

local function clock(seconds)
    seconds = math.floor(seconds or 0)
    local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm"):format(m)
end

local function tick()
    if UnitIsAFK("player") then return end
    local char = QF.char
    local level = UnitLevel("player")
    char.levelTime[level] = (char.levelTime[level] or 0) + TICK
    local guide = QF.guide and QF.guide.name
    if guide then char.guideTime[guide] = (char.guideTime[guide] or 0) + TICK end
end

-- account-wide copy so the tools can read every character's times
local function publish()
    local name, realm = UnitFullName("player")
    QF.db.times = QF.db.times or {}
    QF.db.times[("%s-%s"):format(name or "?", realm or GetRealmName() or "?")] = {
        class = QF.player.class,
        race = QF.player.race,
        levels = QF.char.levelTime,
        guides = QF.char.guideTime,
    }
end

-- time left at this level's pace so far, nil if too early to say
local function eta(level)
    local spent, xp, max = QF.char.levelTime[level], UnitXP("player"), UnitXPMax("player")
    if issecretvalue and (issecretvalue(xp) or issecretvalue(max)) then return nil end
    if not spent or spent < 120 or not xp or xp <= 0 or not max or max <= xp then return nil end
    return (max - xp) * spent / xp
end

-- /qf time, also shown in the settings window
function T:Lines()
    local level = UnitLevel("player")
    local left = eta(level)
    local lines = { ("Level %d so far: |cffffd100%s|r%s"):format(level, clock(QF.char.levelTime[level]),
        left and (", about " .. clock(left) .. " to the next level at this pace") or "") }
    local total = 0
    for _, s in pairs(QF.char.levelTime) do total = total + s end
    local recent = {}
    for l = math.max(1, level - 6), level - 1 do
        if QF.char.levelTime[l] then table.insert(recent, ("%d: %s"):format(l, clock(QF.char.levelTime[l]))) end
    end
    if #recent > 0 then table.insert(lines, "Recent levels   " .. table.concat(recent, "   ")) end
    table.insert(lines, "Measured in all   " .. clock(total))
    return lines
end

function T:Print()
    QF:PrintLines(self:Lines())
end

QF:On("PLAYER_LOGIN", function()
    publish()
    C_Timer.NewTicker(TICK, tick)
end)

QF:On("PLAYER_LEVEL_UP", function(self, _, newLevel)
    local before = (newLevel or UnitLevel("player")) - 1
    local spent = self.char.levelTime[before]
    if spent and spent >= 60 then
        self:Print(("Level %d took |cffffd100%s|r."):format(before, clock(spent)))
    end
end)
