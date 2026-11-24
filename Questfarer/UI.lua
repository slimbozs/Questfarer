-- Guide window, written like a travel journal. Anchored by its top edge, so resizing only moves the bottom.

local _, ns = ...
local QF = ns.QF
local W = QF.W
local C = W.colors

local UI = {}
QF.UI = UI

local PAD = 8
local HEADER = 28
local CHAPTER = 20     -- guide name and page under the header
local BAR = 22
local BAR_GAP = 3
local CARD_PAD = 8
local RIBBON = 3       -- step colour down the left edge of the card
local ICON = 20
local LOCATION = 14
local BOX = 11         -- objective check box
local ROW = 17         -- "then ..." line
local ROW_ICON = 12
local GAP = 6          -- between the card and the "then ..." lines
local FOOTER = 42      -- buttons
local BUTTON = 24
local LINE = 24        -- collapsed mode
local MAX_UPCOMING = 5

local TOP = HEADER + 3
local ICON_X = RIBBON + CARD_PAD
local TEXT_X = ICON_X + ICON + 8

-- journal wording: the step's own text with a verb in front
local VERB = {
    accept = "Take up ", turnin = "Hand in ", complete = "Finish ", train = "Train ", fly = "Fly ",
    sethearth = "Set your hearth ", hearth = "Hearth ", go = "Travel ",
}

local function width()
    return QF.db.width or 340
end

local function plain(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function lowerFirst(s)
    return (s:gsub("^%u", string.lower))
end

local function entryText(step)
    local body = QF:StepBody(step)
    local verb = VERB[step.type]
    -- custom step text is already a full sentence
    if verb and not (step.text and step.type ~= "complete") then
        return verb .. lowerFirst(body)
    end
    return body
end

-- nil when Forever keeps it secret or the call fails
local function safeNumber(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or (issecretvalue and issecretvalue(v)) or type(v) ~= "number" then return nil end
    return v
end

function UI:CreateHeader(f)
    local h = W.Header(f, HEADER)
    self.header = h
    self.closeBtn = W.IconButton(h, 20, nil, "x", "Hide the guide (/qf shows it again)", function() UI:Toggle() end)
    self.closeBtn:SetPoint("RIGHT", -3, 0)
    self.optBtn = W.IconButton(h, 20, "Interface\\Icons\\INV_Misc_Gear_01", nil, "Settings", function()
        if QF.Options then QF.Options:Toggle() end
    end)
    self.optBtn:SetPoint("RIGHT", self.closeBtn, "LEFT", -2, 0)
    self.collapseBtn = W.IconButton(h, 20, nil, "-", "Collapse / expand", function()
        QF.db.collapsed = not QF.db.collapsed
        QF:SettingsChanged()
    end)
    self.collapseBtn:SetPoint("RIGHT", self.optBtn, "LEFT", -2, 0)
    -- "Day 23", hover for the road so far, click for the journal
    local day = CreateFrame("Button", nil, h)
    day:SetSize(54, HEADER - 4)
    day:SetPoint("RIGHT", self.collapseBtn, "LEFT", -4, 0)
    self.day = W.Text(day, "GameFontHighlightSmall", C.leatherMuted, 12)
    self.day:SetPoint("RIGHT", -2, 0)
    self.day:SetJustifyH("RIGHT")
    self.day:SetWordWrap(false)
    day:SetScript("OnClick", function() QF.Options:OpenPage("journal") end)
    day:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(QF.Journal:Name(), 1, 0.82, 0)
        for i, line in ipairs(QF.Journal:StatLines()) do
            if i > 1 and i <= 6 then GameTooltip:AddDoubleLine(line[1], line[2], 0.8, 0.8, 0.8, 1, 1, 1) end
        end
        GameTooltip:AddLine("Click to open the journal.", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    day:SetScript("OnLeave", function() GameTooltip:Hide() end)
    h.title:SetPoint("RIGHT", day, "LEFT", -6, 0)
end

function UI:CreateChapter(body)
    self.chapter = W.Text(body, "GameFontHighlightSmall", C.gold)
    self.chapter:SetPoint("TOPLEFT", PAD, -(TOP + 5))
    self.chapter:SetWordWrap(false)
    self.page = W.Text(body, "GameFontHighlightSmall", C.muted)
    self.page:SetPoint("TOPRIGHT", -PAD, -(TOP + 5))
    self.page:SetJustifyH("RIGHT")
    self.page:SetWordWrap(false)
    self.chapter:SetPoint("RIGHT", self.page, "LEFT", -6, 0)
end

function UI:CreateCard(body)
    local card = CreateFrame("Frame", nil, body)
    self.card = card
    W.Color(W.Box(card, 6, true), C.surface)
    W.BorderColor(card, C.border)
    card.ribbon = card:CreateTexture(nil, "ARTWORK")
    card.ribbon:SetPoint("TOPLEFT", 1, -3)
    card.ribbon:SetPoint("BOTTOMLEFT", 1, 3)
    card.ribbon:SetWidth(RIBBON)
    local frame = W.IconFrame(card, ICON + 2)
    frame:SetPoint("TOPLEFT", ICON_X - 1, -CARD_PAD + 1)
    card.icon = frame.tex
    card.text = W.Text(card, "GameFontNormal", C.text, 14)
    card.text:SetPoint("TOPLEFT", TEXT_X, -CARD_PAD - 2)
    card.text:SetSpacing(2)
    card.dist = W.Text(card, "GameFontHighlightSmall", C.accent)
    card.dist:SetJustifyH("RIGHT")
    card.dist:SetWordWrap(false)
    card.loc = W.Text(card, "GameFontHighlightSmall", C.muted)
    card.loc:SetWordWrap(false)
    card.rows = {}
end

function UI:CardRow(i)
    local row = self.card.rows[i]
    if row then return row end
    row = { box = W.CheckBox(self.card, BOX), text = W.Text(self.card, "GameFontHighlightSmall", C.text) }
    row.text:SetSpacing(1)
    self.card.rows[i] = row
    return row
end

function UI:CreateUpcoming(body)
    self.rows = {}
    for i = 1, MAX_UPCOMING do
        local icon = body:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ROW_ICON, ROW_ICON)
        local t = W.Text(body, "GameFontHighlightSmall", C.muted)
        t:SetWordWrap(false)
        t:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        t.icon = icon
        self.rows[i] = t
    end
end

function UI:CreateFooter(body)
    self.nextBtn = W.Button(body, "Onward", 90, BUTTON, function() QF:Skip() end, "primary")
    self.nextBtn:SetPoint("BOTTOMRIGHT", -PAD, 8)
    self.backBtn = W.Button(body, "Back", 54, BUTTON, function() QF:Back() end)
    self.backBtn:SetPoint("RIGHT", self.nextBtn, "LEFT", -6, 0)
    self.trainBtn = W.Button(body, "Train all", 76, BUTTON, function() QF:TrainAll() end, "train")
    self.trainBtn:SetPoint("RIGHT", self.backBtn, "LEFT", -6, 0)
    self.xpText = W.Text(body, "GameFontHighlightSmall", C.muted)
    self.xpText:SetPoint("BOTTOMLEFT", PAD, 15)
    self.xpText:SetWordWrap(false)
    local rule = body:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT", PAD, FOOTER - 2)
    rule:SetPoint("BOTTOMRIGHT", -PAD, FOOTER - 2)
    rule:SetHeight(1)
    W.Color(rule, C.border, 0.7)
end

-- collapsed mode: the step on one line
function UI:CreateLine(f)
    local line = CreateFrame("Frame", nil, f)
    self.line = line
    line:SetPoint("TOPLEFT", 1, -TOP)
    line:SetPoint("TOPRIGHT", -1, -TOP)
    line:SetHeight(LINE)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(14, 14)
    line.icon:SetPoint("LEFT", PAD, 0)
    line.dist = W.Text(line, "GameFontHighlightSmall", C.accent)
    line.dist:SetPoint("RIGHT", -PAD, 0)
    line.dist:SetJustifyH("RIGHT")
    line.dist:SetWordWrap(false)
    line.text = W.Text(line, "GameFontHighlightSmall", C.text)
    line.text:SetPoint("LEFT", PAD + 20, 0)
    line.text:SetPoint("RIGHT", line.dist, "LEFT", -6, 0)
    line.text:SetWordWrap(false)
    line:Hide()
end

-- other modules add their bars with QF:AddBar
local function builtInBars()
    local trainer = {
        icon = "Interface\\Icons\\INV_Misc_Book_09",
        color = W.StepStyle("train").color,
        text = function()
            local step = QF:CurrentStep()
            if not (QF.db.trainReminder and QF:NeedsTraining()) or (step and step.type == "train") then return nil end
            local t = UI:NearestTrainer()
            local where = t and ("  |cffd8c8ff" .. t.npc .. "|r") or ""
            local list = QF:NewTrainableSpells()
            local what = list and #list > 0 and QF:TrainingSummary(list) or "New spells to train!"
            return "|cffffffff" .. what .. "|r" .. where
        end,
        onClick = function() UI:PointToTrainer() end,
        tooltip = function(tip)
            tip:AddLine("Class trainer", 1, 1, 1)
            QF:AddTrainingTooltip(tip)
            tip:AddLine("Click: waypoint to the nearest trainer.", 0.6, 0.8, 1)
        end,
    }
    local classQuest = {
        icon = "Interface\\Icons\\INV_Scroll_03",
        color = C.accent,
        text = function() return QF.ClassQuests:BarText() end,
        onClick = function(button) QF.ClassQuests:OnBarClick(button) end,
        tooltip = function(tip) QF.ClassQuests:AddTooltip(tip) end,
    }
    return { trainer, classQuest }
end

function UI:Create()
    if self.frame then return end
    local f = CreateFrame("Frame", "QuestfarerFrame", UIParent)
    self.frame = f
    f:SetSize(width(), 120)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f.isLocked = function() return QF.db.locked end
    f.onMoved = function(frame)
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then QF.db.point = { "TOPLEFT", "BOTTOMLEFT", left, top } end
        self:ApplyPoint()
    end
    self.bg = W.Panel(f)
    self:CreateHeader(f)
    self:CreateLine(f)

    -- everything collapsed mode hides
    local body = CreateFrame("Frame", nil, f)
    self.body = body
    body:SetAllPoints(f)
    body:Hide()
    self:CreateChapter(body)
    self:CreateCard(body)
    self:CreateUpcoming(body)
    self:CreateFooter(body)

    self.ownBars = builtInBars()
    self.barFrames = {}
    self:ApplySettings()
end

-- older versions saved other anchors, convert them to TOPLEFT
function UI:ApplyPoint()
    local f = self.frame
    f:ClearAllPoints()
    local p = QF.db.point
    if not p then
        f:SetPoint("TOPRIGHT", UIParent, "RIGHT", -60, 260)
        return
    end
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    if p[1] ~= "TOPLEFT" or p[2] ~= "BOTTOMLEFT" then
        local left, top = f:GetLeft(), f:GetTop()
        if left and top then
            QF.db.point = { "TOPLEFT", "BOTTOMLEFT", left, top }
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end
end

function UI:ApplySettings()
    local f = self.frame
    if not f then return end
    local scale = QF.db.scale or 1
    -- saved position is in the window's own scale, keep the corner in place
    local p = QF.db.point
    if p and self.appliedScale and self.appliedScale ~= scale and p[2] == "BOTTOMLEFT" then
        p[3], p[4] = p[3] * self.appliedScale / scale, p[4] * self.appliedScale / scale
    end
    self.appliedScale = scale
    f:SetScale(scale)
    f:SetWidth(width())
    local alpha = QF.db.alpha or 0.92
    self.bg:SetAlpha(alpha)
    self.header.bg:SetAlpha(alpha)
    self:ApplyPoint()
    f:SetShown(QF.db.shown)
    if QF.db.shown and QF.guide then self:Refresh() end -- not at login, the guide loads later
end

function UI:Toggle()
    QF.db.shown = not QF.db.shown
    QF:SettingsChanged()
end

function UI:NearestTrainer()
    local list = QF.trainers and QF.trainers[QF.player.class]
    if not list then return nil end
    local best, bestD
    for area, t in pairs(list) do
        local d = QF:DistanceTo(t)
        if d and (not bestD or d < bestD) then
            best, bestD = t, d
            best.area = area
        end
    end
    return best, bestD
end

function UI:PointToTrainer()
    local t = self:NearestTrainer()
    if t and QF.db.waypoint then
        QF:SetWaypointForStep(t)
        QF:Print("Waypoint set to " .. t.npc .. " (" .. (t.area or "") .. ")")
    elseif t then
        QF:Print("Nearest trainer: " .. t.npc .. " (" .. (t.area or "") .. "). Turn on Map pin in the settings to get a marker.")
    else
        QF:Print("No known trainer location for your class nearby.")
    end
end

function UI:RefreshHeader(steps, idx)
    self.header.title:SetText(QF.Journal:Name())
    self.day:SetText("Day " .. QF.Journal:Day())
    self.chapter:SetText(QF.guide and QF.guide.name or "")
    self.page:SetText(#steps > 0 and ("page %d of %d"):format(math.min(idx, #steps), #steps) or "")
    self.collapseBtn.label:SetText(QF.db.collapsed and "+" or "-")
end

function UI:RefreshXP()
    local level = safeNumber(UnitLevel, "player")
    local xp, max = safeNumber(UnitXP, "player"), safeNumber(UnitXPMax, "player")
    if level and xp and max and max > 0 then
        self.xpText:SetText(("%d%% to %d"):format(math.floor(xp / max * 100), level + 1))
    else
        self.xpText:SetText(level and ("Level " .. level) or "")
    end
end

-- returns the y under the bars
function UI:LayoutBars(y)
    local function place(def)
        local ok, text = pcall(def.text)
        local bar = self.barFrames[def]
        if not (ok and text) then
            if bar then bar:Hide() end
            return
        end
        if not bar then
            bar = W.ActionBar(self.body, def, BAR)
            self.barFrames[def] = bar
        end
        bar.text:SetText(text)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", PAD, y)
        bar:SetPoint("TOPRIGHT", -PAD, y)
        bar:Show()
        y = y - BAR - BAR_GAP
    end
    for _, def in ipairs(self.ownBars) do place(def) end
    for _, def in ipairs(QF.bars) do place(def) end
    return y
end

local function noStepText()
    if QF.noGuideForLevel then
        local level = safeNumber(UnitLevel, "player")
        return "No guide for " .. (level and ("level " .. level) or "your level") ..
            " yet. The road continues in a later version."
    end
    return "This chapter is done. Pick the next guide in the settings (gear icon)."
end

-- returns the y under the entry
function UI:LayoutCard(step, y)
    local card = self.card
    local cardW = width() - 2 * PAD
    local left = TEXT_X
    local right = cardW - CARD_PAD

    local style = W.StepStyle(step and step.type)
    W.Color(card.ribbon, style.color)
    W.SetStepIcon(card.icon, step and step.type)
    card.text:SetWidth(right - TEXT_X)
    card.text:SetText(step and entryText(step) or noStepText())
    local cy = -CARD_PAD - math.max(ICON, W.TextHeight(card.text) + 2) - 5

    -- fixed height, so the distance can tick without moving anything
    local hasLocation = step and (step.npc or (step.x and step.y)) and true or false
    card.loc:SetShown(hasLocation)
    card.dist:SetShown(hasLocation)
    if hasLocation then
        card.dist:ClearAllPoints()
        card.dist:SetPoint("TOPRIGHT", -CARD_PAD, cy)
        card.loc:ClearAllPoints()
        card.loc:SetPoint("TOPLEFT", left, cy)
        card.loc:SetPoint("TOPRIGHT", card.dist, "TOPLEFT", -6, 0)
        cy = cy - LOCATION - 4
    end

    local rows = {}
    if step then
        local ok, result = pcall(QF.StepRows, QF, step)
        if ok then rows = result else QF:Debug("Step rows:", result) end
    end
    for i, r in ipairs(rows) do
        local row = self:CardRow(i)
        local x = left + (r.indent or 0) * 10
        local check = r.done ~= nil
        row.box:SetShown(check)
        if check then
            row.box:SetChecked(r.done)
            row.box:ClearAllPoints()
            row.box:SetPoint("TOPLEFT", x, cy)
            x = x + BOX + 5
            local c = r.done and C.good or C.text
            row.text:SetTextColor(c[1], c[2], c[3])
        else
            row.text:SetTextColor(C.text[1], C.text[2], C.text[3])
        end
        row.text:SetWidth(right - x)
        row.text:SetText(r.text)
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", x, cy)
        row.text:Show()
        cy = cy - W.TextHeight(row.text) - 4
    end
    for i = #rows + 1, #card.rows do
        card.rows[i].box:Hide()
        card.rows[i].text:Hide()
    end

    local height = -cy + CARD_PAD - 4
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", PAD, y)
    card:SetPoint("TOPRIGHT", -PAD, y)
    card:SetHeight(height)
    return y - height
end

-- returns the y under the "then ..." lines
function UI:LayoutUpcoming(step, idx, y)
    local upcoming = {}
    if step then
        local n = math.min(QF.db.upcoming or 2, MAX_UPCOMING)
        local i = idx + 1
        while QF.steps[i] and #upcoming < n do
            if not QF.steps[i].obsolete then table.insert(upcoming, QF.steps[i]) end
            i = i + 1
        end
    end
    local hasNext = #upcoming > 0
    if hasNext then y = y - GAP end
    for i, t in ipairs(self.rows) do
        local s = upcoming[i]
        t:SetShown(s ~= nil)
        t.icon:SetShown(s ~= nil)
        if s then
            W.SetStepIcon(t.icon, s.type)
            t.icon:ClearAllPoints()
            t.icon:SetPoint("TOPLEFT", PAD + RIBBON + 2, y - 1)
            t:SetWidth(width() - 2 * PAD - RIBBON - ROW_ICON - 8)
            t:SetText("then " .. lowerFirst(plain(entryText(s))))
            local a = i == 1 and 1 or 0.7
            t:SetAlpha(a)
            t.icon:SetAlpha(a)
            y = y - ROW
        end
    end
    return hasNext and y - 2 or y
end

function UI:LayoutFooter(step, idx)
    local train = QF.trainerOpen and true or false
    self.trainBtn:SetShown(train)
    -- cut the XP text short rather than run under the buttons
    self.xpText:SetPoint("RIGHT", train and self.trainBtn or self.backBtn, "LEFT", -6, 0)
    local manual = step and (step.type == "note" or step.type == "getfp" or step.type == "hearth")
    self.nextBtn:SetText(manual and "Done" or "Onward")
    self.nextBtn:SetActive(step ~= nil)
    self.backBtn:SetActive(idx > 1)
end

function UI:RefreshCollapsed(step)
    local line = self.line
    W.SetStepIcon(line.icon, step and step.type)
    line.text:SetText(step and plain(entryText(step)) or noStepText())
    line.dist:SetText("")
    self:RefreshDistance()
end

function UI:Refresh()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local idx = QF.char.step
    local step = QF.steps[idx]
    self:RefreshHeader(QF.steps, idx)

    local collapsed = QF.db.collapsed and true or false
    self.body:SetShown(not collapsed)
    self.line:SetShown(collapsed)
    if collapsed then
        self:RefreshCollapsed(step)
        f:SetHeight(TOP + LINE + 1)
        return
    end

    self:RefreshXP()
    local y = self:LayoutBars(-(TOP + CHAPTER + 2))
    y = self:LayoutCard(step, y)
    y = self:LayoutUpcoming(step, idx, y)
    self:LayoutFooter(step, idx)
    self:RefreshDistance()
    f:SetHeight(-y + FOOTER)
end

-- runs twice a second, only changes text so nothing resizes
function UI:RefreshDistance()
    local step = QF:CurrentStep()
    if not (self.frame and step) then return end
    local coords, yards = QF:StepLocation(step)
    local away = yards and ("%d yd"):format(math.floor(yards + 0.5)) or ""
    if QF.db.collapsed then
        self.line.dist:SetText(away)
        return
    end
    local parts = {}
    if step.npc then table.insert(parts, step.npc) end
    if coords then table.insert(parts, coords) end
    self.card.loc:SetText(table.concat(parts, "   "))
    self.card.dist:SetText(away)
end
