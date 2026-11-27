-- Questfarer - Settings window

local _, ns = ...
local QF = ns.QF
local W = QF.W
local C = W.colors

local Options = {}
QF.Options = Options

local WIDTH, HEIGHT = 760, 540
local TITLE_H = 32
local RAIL_W = 164
local RAIL_ROW = 38
local HEAD_H = 50       -- page title and subtitle
local MARGIN = 18
local BAR_ROOM = 20     -- room for the scrollbar
local CONTENT_W = WIDTH - RAIL_W - 1 - MARGIN - BAR_ROOM
local REFRESH_EVERY = 5 -- seconds

-- falls back to a note when the game can't answer yet
local function safeLines(fn, ...)
    local ok, lines = pcall(fn, ...)
    if ok and type(lines) == "table" then return lines end
    QF:Debug("Settings window:", lines)
    return { "|cffff6666Not available right now.|r" }
end

local Page = {}
Page.__index = Page

local function newPage(def)
    local frame = CreateFrame("Frame", nil, Options.scroll.child)
    frame:SetPoint("TOPLEFT")
    frame:SetSize(CONTENT_W, 1)
    frame:Hide()
    return setmetatable({ def = def, frame = frame, items = {}, height = 1 }, Page)
end

-- gap: space below the widget
function Page:Add(widget, gap)
    table.insert(self.items, { widget = widget, gap = gap or 1 })
    return widget
end

function Page:Section(title)
    local last = self.items[#self.items]
    if last then last.gap = 14 end
    return self:Add(W.Section(self.frame, title), 3)
end

function Page:Toggle(key, label, desc)
    return self:Add(W.Switch(self.frame, CONTENT_W, label, desc,
        function() return QF.db[key] end,
        function(v)
            QF.db[key] = v
            QF:SettingsChanged()
        end))
end

function Page:Slider(key, label, lo, hi, step, fmt, default)
    return self:Add(W.Slider(self.frame, label, lo, hi, step,
        function() return QF.db[key] or default end,
        function(v)
            QF.db[key] = v
            QF:SettingsChanged()
        end, fmt))
end

function Page:Note(text)
    local block = W.TextBlock(self.frame, CONTENT_W)
    block:SetLines({ text })
    return self:Add(block)
end

-- heavy: not refreshed on every guide update
function Page:Block(fn, heavy, leftColumn)
    local block = W.TextBlock(self.frame, CONTENT_W, leftColumn)
    block.heavy = heavy
    function block:Update() self:SetLines(safeLines(fn)) end
    block:Update()
    return self:Add(block)
end

function Page:Row(label, desc)
    return self:Add(W.ActionRow(self.frame, CONTENT_W, label, desc))
end

function Page:Refresh(light)
    for _, item in ipairs(self.items) do
        local w = item.widget
        if w.Update and not (light and w.heavy) then
            local ok, err = pcall(w.Update, w)
            if not ok then QF:Debug("Settings window:", err) end
        end
    end
    self:Layout()
end

function Page:Layout()
    local y = 0
    for _, item in ipairs(self.items) do
        local w = item.widget
        if w:IsShown() then
            if w.Measure then w:Measure() end
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, y)
            w:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, y)
            y = y - w:GetHeight() - item.gap
        end
    end
    self.height = -y + 12
    self.frame:SetHeight(self.height)
    if Options.current == self then
        Options.scroll.child:SetHeight(self.height)
        Options.scroll:Sync()
    end
end

local function guideSummary(parent)
    local f = CreateFrame("Frame", nil, parent)
    W.Color(W.Box(f, 6, true), C.surface)
    W.BorderColor(f, C.border)
    local mark = W.Marker(f, 8)
    mark:SetPoint("CENTER", f, "TOPLEFT", 8, -48)
    local name = W.Text(f, "GameFontNormal", C.gold)
    W.FontSize(name, 15)
    name:SetPoint("TOPLEFT", 14, -10)
    name:SetWidth(CONTENT_W - 130)
    name:SetWordWrap(false)
    local count = W.Text(f, "GameFontHighlightSmall", C.muted)
    count:SetPoint("TOPRIGHT", -12, -11)
    count:SetJustifyH("RIGHT")
    local track = f:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPLEFT", 14, -30)
    track:SetPoint("TOPRIGHT", -12, -30)
    track:SetHeight(4)
    W.Color(track, C.off, 0.7)
    local fill = f:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", track, "TOPLEFT")
    fill:SetHeight(4)
    W.Color(fill, C.accent)
    local kind = W.Text(f, "GameFontNormalSmall", C.muted, 11)
    kind:SetPoint("TOPLEFT", 14, -42)
    kind:SetWordWrap(false)
    local text = W.Text(f, "GameFontHighlight", C.text)
    text:SetPoint("TOPLEFT", 14, -56)
    text:SetWidth(CONTENT_W - 26)

    function f:Update()
        local steps, idx = QF.steps, QF.char.step
        local step = steps[idx]
        local style = W.StepStyle(step and step.type)
        mark:Style(style.color)
        kind:SetTextColor(style.color[1], style.color[2], style.color[3])
        name:SetText(QF.guide and QF.guide.name or "No guide loaded")
        count:SetText(QF.guide and ("Step %d of %d"):format(math.min(idx, #steps), #steps) or "")
        local frac = #steps > 0 and math.min(1, (idx - 1) / #steps) or 0
        fill:SetWidth(math.max(1, frac * (CONTENT_W - 26)))
        fill:SetShown(frac > 0)
        kind:SetText(step and style.label or "")
        text:SetText(step and QF:StepBody(step) or "No step to show: pick a guide below.")
    end
    function f:Measure()
        self:SetHeight(56 + W.TextHeight(text) + 10)
    end
    f:Update()
    return f
end

local function usableGuides(query)
    local list = {}
    for _, name in ipairs(QF.guideOrder) do
        local g = QF.guides[name]
        if not g.side and QF:GuideApplies(g) and (query == "" or name:lower():find(query, 1, true)) then
            table.insert(list, g)
        end
    end
    return list
end

local function createGuideRow(row)
    row.load = W.ConfirmButton(row, "Load", 70, 20, function()
        if row.guide then QF:PickGuide(row.guide.name) end
    end, "Confirm")
    row.load.tooltip = "Switch to this guide at the step your quests have reached. It stays until it ends. Click twice."
    row.load:SetPoint("RIGHT", -2, 0)
    row.active = W.Text(row, "GameFontHighlightSmall", C.good)
    row.active:SetPoint("RIGHT", -14, 0)
    row.active:SetText("Active")
    row.levels = W.Text(row, "GameFontHighlightSmall", C.muted)
    row.levels:SetPoint("RIGHT", -82, 0)
    row.levels:SetJustifyH("RIGHT")
    row.levels:SetWordWrap(false)
    row.name = W.Text(row, "GameFontHighlight", C.text)
    row.name:SetPoint("LEFT", 12, 0)
    row.name:SetPoint("RIGHT", row.levels, "LEFT", -8, 0)
    row.name:SetWordWrap(false)
end

local function fillGuideRow(row, guide)
    if row.guide ~= guide then
        row.load:Disarm()
        row.guide = guide
    end
    local active = QF.guide == guide
    row.name:SetText(guide.name)
    row.levels:SetText(("Level %d-%d"):format(guide.minLevel or 1, guide.maxLevel or 60))
    row.load:SetShown(not active)
    row.active:SetShown(active)
end

local function buildGuidePage(page)
    page:Add(guideSummary(page.frame), 6)

    local nav = page:Add(W.ButtonRow(page.frame))
    local back = nav:AddButton(W.Button(nav, "< Previous step", 127, 24, function() QF:Back() end))
    back.tooltip = "Go back one step (/qf back)."
    local nxt = nav:AddButton(W.Button(nav, "Next step >", 127, 24, function() QF:Skip() end, "primary"))
    nxt.tooltip = "Skip to the next step (/qf skip)."
    nav:AddButton(W.Button(nav, "Find my step", 127, 24, function() QF:FindMyStep() end)).tooltip =
        "Jump to the right step from your quests. A guide you loaded yourself is kept (/qf resync)."
    nav:AddButton(W.Button(nav, "Fix skipped step", 127, 24, function() QF:FixSkipped() end)).tooltip =
        "Go back to a skipped step the current step needs (/qf fix)."
    function nav:Update()
        back:SetActive(QF.char.step > 1)
        nxt:SetActive(QF:CurrentStep() ~= nil)
    end

    local restart = page:Row("Restart guide", "Start the current guide again from its first step (/qf reset).")
    restart:AddButton(W.ConfirmButton(restart, "Restart", 96, 24, function() QF:RestartGuide() end))

    page:Section("Guides for this character")
    local query = ""
    local list
    local search = W.Input(page.frame, CONTENT_W, 26, "Search guides...", function(text)
        query = text:lower()
        if list then
            list.offset = 0
            list:Update()
        end
    end)
    page:Add(search, 3)
    list = W.List(page.frame, CONTENT_W, 26, 8, createGuideRow, fillGuideRow, {
        fixed = true,
        empty = "No guide matches.",
        onLimit = function(delta) Options.scroll:Wheel(delta) end,
    })
    function list:Update() self:SetItems(usableGuides(query)) end
    list:Update()
    page:Add(list)
end

local function buildAutomationPage(page)
    page:Note("Hold |cffffd100Shift|r while talking to an NPC or opening a vendor to pause all of this for that NPC. " ..
        "Only quests that are in your guides are accepted and turned in.")
    page:Section("Quests")
    page:Toggle("autoAccept", "Accept quests", "Accepts quests that are in the guide (/qf accept).")
    page:Toggle("autoTurnin", "Turn in quests", "Turns in guide quests. When there are several rewards, you choose (/qf turnin).")
    page:Toggle("autoGossip", "Pick dialogue options", "Picks the flight master or trainer option when the step needs it (/qf gossip).")
    page:Section("Travel and training")
    page:Toggle("autoFlight", "Take flights", "On 'fly' steps, picks the right destination at the flight master (/qf flight).")
    page:Toggle("autoTrain", "Train all automatically",
        "Spends your money on every spell you can afford as soon as the trainer window opens (/qf train).")
    page:Section("Vendors")
    page:Toggle("autoSell", "Sell gray items", "Sells gray items when you open a vendor. The addon never buys anything for you.")
    page:Toggle("autoRepair", "Repair at vendors", "Repairs your gear when you open a vendor that can repair.")
end

local function buildNavigationPage(page)
    page:Section("Showing the way")
    page:Toggle("arrow", "Guide arrow",
        "On-screen arrow that points to the current step, with the distance. Drag it to move it (/qf arrow).")
    page:Toggle("checkpoints", "Arrow checkpoints",
        "The arrow goes via zone crossings (roads, passes, tunnels) and checkpoints instead of straight through " ..
        "mountains. Learns the way from your own runs (/qf checkpoints).")
    page:Toggle("mapSteps", "Step numbers on the map",
        "Numbered circles on the world map for the current step and the next five, joined by a line. " ..
        "Point at one to see its steps (/qf mapsteps).")
    page:Toggle("waypoint", "Blizzard map pin", "Puts Blizzard's map pin on the current step, on the world map and minimap (/qf waypoint).")
    page:Toggle("mapAreas", "Objective areas on the map",
        "Orange dots on the world map and minimap where the current step's mobs, items and objects are.")
    local skip = page:Row("Skip current checkpoint", "The arrow moves on to the next point for this step (/qf cp).")
    skip:AddButton(W.Button(skip, "Skip", 96, 24, function() QF.Paths:SkipCheckpoint() end))

    page:Section("Learned paths")
    page:Block(function() return QF.Paths:StatsLines() end, true)
    local reset = page:Row("Reset learned paths", "Forgets every zone crossing and path learned from your runs, on all characters (/qf paths reset).")
    reset:AddButton(W.ConfirmButton(reset, "Reset", 96, 24, function()
        QF.Paths:Reset()
        Options:Update()
    end))
end

-- opening the key bindings differs between clients, so fall back to a hint
local function openKeyBindings()
    local fallback = "Open Options > Keybindings > AddOns > Questfarer in the game menu."
    if InCombatLockdown() then
        QF:Print("Key bindings can't be opened in combat. " .. fallback)
        return
    end
    if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
        local ok, opened = pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID)
        if ok and opened ~= false then
            Options.frame:Hide()
            return
        end
    end
    QF:Print(fallback)
end

local function buildHelpersPage(page)
    page:Section("Buttons")
    page:Toggle("itemButton", "Quest item button", "A button that uses the current step's quest item.")
    page:Toggle("targetButton", "Target button", "A button that targets the current step's NPC or mob and puts a star over it.")
    local keys = page:Row("Key bindings", "")
    keys:AddButton(W.Button(keys, "Key bindings...", 110, 24, openKeyBindings))
    function keys:Update()
        local B = QF.Buttons
        self.desc:SetText(("Quest item: |cffffd100%s|r     Target: |cffffd100%s|r"):format(
            B:KeyText(B.ITEM_BINDING) or "not set", B:KeyText(B.TARGET_BINDING) or "not set"))
    end
    keys:Update()

    page:Section("Warnings")
    page:Toggle("fullWarning", "Full bags and quest log", "Warns in the guide window when your bags or quest log are nearly full.")
    page:Toggle("trainReminder", "Trainer reminder", "Shows a bar when you have new spells to train (/qf reminder).")

    page:Section("Suggestions")
    page:Toggle("rewardHint", "Best reward to sell",
        "Marks the quest reward that sells to a vendor for the most. You still pick it yourself (/qf reward).")
    page:Toggle("talentHint", "Talent suggestions", "Shows where your next talent point could go. You spend it yourself.")
    page:Toggle("gearHint", "Gear upgrades", "Marks the best quest reward for your class and offers upgrades from your bags. A rough estimate.")
    local ignored = page:Row("Ignored gear", "")
    ignored:AddButton(W.ConfirmButton(ignored, "Clear", 96, 24, function()
        QF.Gear:ClearIgnored()
        Options:Update()
    end))
    function ignored:Update()
        local n = QF.Gear:IgnoredCount()
        self.desc:SetText(n == 1 and "1 item you right-clicked on the upgrade bar is ignored." or
            (n .. " items you right-clicked on the upgrade bar are ignored."))
    end
    ignored:Update()
end

local function percent(v) return ("%d%%"):format(v * 100 + 0.5) end

local function positionRow(page, label, desc, which)
    local row = page:Row(label, desc)
    row:AddButton(W.ConfirmButton(row, "Reset", 96, 24, function() QF:ResetPosition(which) end))
end

local function buildAppearancePage(page)
    page:Section("Theme")
    page:Add(W.Switch(page.frame, CONTENT_W, "Light theme",
        "Parchment and brown ink instead of dark leather. Shows after a reload.",
        function() return QF.db.theme == "light" end,
        function(v) QF.db.theme = v and "light" or "dark" end))
    local reload = page:Row("Reload interface", "Puts a theme change into effect.")
    reload:AddButton(W.Button(reload, "Reload", 96, 24, function() ReloadUI() end))

    page:Section("Guide window")
    page:Add(W.Switch(page.frame, CONTENT_W, "Show guide window", "Same as typing /qf.",
        function() return QF.db.shown end,
        function(v) if v ~= QF.db.shown then QF.UI:Toggle() end end))
    page:Toggle("locked", "Lock positions", "Stops the guide window, the arrow and the buttons from being dragged (/qf lock).")
    page:Toggle("collapsed", "Collapsed", "Shows only the title bar and the current step on one line. The - button does the same.")

    page:Section("Size")
    page:Slider("scale", "Size", 0.5, 2, 0.05, percent, 1)
    page:Slider("width", "Width", 280, 480, 10, function(v) return v .. " px" end, 340)
    page:Slider("alpha", "Background opacity", 0.3, 1, 0.05, percent, 0.92)
    page:Slider("upcoming", "Upcoming steps shown", 0, 5, 1, nil, 2)

    page:Section("Positions")
    positionRow(page, "Guide window", "Moves the guide window back to its default place.", "guide")
    positionRow(page, "Guide arrow", "Moves the arrow back to the top of the screen.", "arrow")
    positionRow(page, "Item and target buttons", "Moves the buttons back above the action bars. Waits until a fight is over.", "buttons")
end

local function createClassRow(row)
    row.action = W.Button(row, "Start", 62, 20, function()
        local g = row.guide
        if not g then return end
        if QF.guide == g then QF.ClassQuests:Stop() else QF.ClassQuests:Pick(g) end
        Options:Update()
    end)
    row.action:SetPoint("RIGHT", -2, 0)
    row.hide = W.Button(row, "Hide", 62, 20, function()
        local g = row.guide
        if not g then return end
        QF.ClassQuests:SetHidden(g, not QF.char.sideHidden[g.name])
        Options:Update()
    end)
    row.hide:SetPoint("RIGHT", row.action, "LEFT", -4, 0)
    row.hide.tooltip = "Hide it from the bar in the guide window, or show it there again."
    row.state = W.Text(row, "GameFontHighlightSmall", C.muted)
    row.state:SetPoint("RIGHT", row.hide, "LEFT", -8, 0)
    row.state:SetJustifyH("RIGHT")
    row.state:SetWordWrap(false)
    row.name = W.Text(row, "GameFontHighlight", C.text)
    row.name:SetPoint("LEFT", 12, 0)
    row.name:SetPoint("RIGHT", row.state, "LEFT", -8, 0)
    row.name:SetWordWrap(false)
end

local function fillClassRow(row, guide)
    row.guide = guide
    local active = QF.guide == guide
    local ready = QF.ClassQuests:IsReady(guide)
    local hidden = QF.char.sideHidden[guide.name]
    row.name:SetText(guide.ability or guide.name)
    if active then
        row.state:SetText("|cff55dd55in progress|r")
    elseif not ready then
        row.state:SetText("level " .. (guide.minLevel or 1))
    elseif hidden then
        row.state:SetText("hidden")
    else
        row.state:SetText("|cff55dd55ready|r")
    end
    row.action:SetText(active and "Stop" or "Start")
    row.action:SetShown(active or ready)
    row.hide:SetText(hidden and "Show" or "Hide")
    row.hide:SetShown(not active)
end

local function buildCharacterPage(page)
    page:Section("Level times")
    page:Block(function() return QF.Timer:Lines() end, true)

    page:Section("Class quests")
    local list = W.List(page.frame, CONTENT_W, 28, 6, createClassRow, fillClassRow, {
        empty = "No class quests left for your character.",
        onLimit = function(delta) Options.scroll:Wheel(delta) end,
    })
    function list:Update() self:SetItems(QF.ClassQuests:All()) end
    list:Update()
    page:Add(list)

    page:Section("Talent plan")
    page:Block(function() return QF.Talents:Lines() end, true)

    page:Section("Trainable spells")
    page:Block(function() return QF:TrainableLines() end, true)
end

local function buildDataPage(page)
    page:Section("Recording")
    page:Toggle("record", "Recorder",
        "Saves what really happens on Forever (quest givers, objective spots, trainers, flight paths) so the guides " ..
        "can be checked and fixed (/qf record).")
    page:Toggle("debug", "Debug messages", "Prints quest ID, title, NPC and position in chat when you open a quest (/qf debug).")
    page:Block(function() return QF.Recorder:StatsLines() end, true)

    page:Section("Combat log")
    page:Toggle("combatLog", "Start the combat log at login",
        "Turns on the game's combat log (with advanced logging) every time you log in, so your real kill and level " ..
        "times can be compared with the guide's time model. Turning this off also stops a log the addon started " ..
        "(/qf combatlog).")
    page:Block(function() return QF.Recorder:CombatLogLines() end, true)

    page:Section("Share your data")
    page:Note("Questfarer is in beta, and real play data is the best way to fix the route and its time estimates. " ..
        "If you like, the addon counts your fights, downtime, kills and XP per level. Nothing is sent by itself: " ..
        "you make an export text here and send it to the person who gave you Questfarer, or post it in the " ..
        "Questfarer Discord or on GitHub.")
    page:Toggle("contribute", "Collect data to share",
        "Counts fights, downtime between fights, kills, quest and kill XP, and deaths per level, for every character " ..
        "on this account. No names are saved (/qf share).")
    page:Block(function() return QF.Contribute:SummaryLines() end, true)
    local share = page:Row("Export",
        "Makes the text to send, to a friend or the Questfarer Discord or GitHub (/qf export).")
    share:AddButton(W.Button(share, "Make export text", 130, 24, function() QF.Contribute:ShowExport() end, "primary"))
    local forget = page:Row("Delete collected data",
        "Forgets the counted fights and XP. Level times and the recorder's data are kept.")
    forget:AddButton(W.ConfirmButton(forget, "Delete", 80, 24, function()
        QF.Contribute:Clear()
        page:Refresh()
    end))

    page:Section("Position and map bounds")
    local output = { "The result is shown here and in chat." }
    local result
    local function show(lines)
        output = lines
        QF:PrintLines(lines)
        result:Update()
        page:Layout()
    end
    local where = page:Row("Your position", "Map ID and coordinates, for writing guides (/qf where).")
    where:AddButton(W.Button(where, "Show position", 110, 24, function() show(safeLines(QF.WhereLines, QF)) end))

    local bounds = page:Row("Map bounds", "World bounds for the route tools. Leave the box empty for the map you are on (/qf bounds).")
    local input
    local function measure() show(safeLines(QF.BoundsLines, QF, input:GetText())) end
    bounds:AddButton(W.Button(bounds, "Measure", 80, 24, measure))
    input = W.Input(bounds, 130, 24, "Map IDs", nil, measure)
    bounds:AddButton(input)
    result = page:Block(function() return output end)

    page:Section("Reset")
    local reset = page:Row("Reset all settings",
        "Every setting and window position goes back to its default. Learned paths, recorded data, level times and " ..
        "your guide progress are kept.")
    reset:AddButton(W.ConfirmButton(reset, "Reset all", 96, 24, function()
        QF:ResetSettings()
        Options:ApplyPoint()
        QF.db.optionsTab = page.def.id
    end))
end

local function commandRows()
    local rows = {}
    for _, c in ipairs(QF:CommandList()) do
        table.insert(rows, { "|cffffd100" .. c[1] .. "|r", c[2] })
    end
    return rows
end

local function buildAboutPage(page)
    page:Section("Questfarer " .. (QF.version or ""))
    page:Note("A step-by-step 1-60 leveling guide for WoW Forever. It shows one step at a time and moves on by itself " ..
        "when the step is done. It can accept and turn in guide quests, take flights, sell gray items and repair " ..
        "your gear. An arrow points the way, and bars remind you about trainers, talents and gear upgrades. " ..
        "It never buys items for you.")

    page:Section("Beta")
    page:Note("This is a beta. The Alliance route has been checked against quest data and simulated, but not fully " ..
        "played through yet. The Horde guides are experimental. If a step is wrong, report it in the Questfarer " ..
        "Discord or on GitHub, with the step text and where you were (/qf where). You can also share your play data " ..
        "(Data page).")
    for _, link in ipairs(QF.Contribute:Links()) do
        local where = link[1]:match("^(%a+)")
        local row = page:Row(where, "Click the box and press Ctrl+C, then open the link in your browser.")
        local box = QF.Contribute.CopyBox(row, 300)
        box:SetFixedText(link[2])
        row:AddButton(box)
    end

    page:Section("Chat commands")
    page:Block(commandRows, false, 150).heavy = true

    page:Section("Credits")
    page:Note("Quest, NPC, object and item data: |cffffd100QuestieDB|r, used under the GNU GPL v3.")
    page:Note("Class spell lists: |cffffd100WhatsTraining|r (What's Training?) by Sveng, used under the MIT License.")

    page:Section("Licence")
    page:Note("Questfarer is free software under the GNU General Public License v3. You may share and change it, " ..
        "but copies and changed versions must stay under the GPL v3 and keep their source open. See LICENSE.md.")
end

local function buildJournalPage(page)
    page:Toggle("rpPopups", "Journal notes",
        "A small note above the guide window when you reach a new land, earn a title or a seal. Click it to read the page.")
    page:Section("The road so far")
    page:Note("Only the days that matter are written down: new lands and dungeons, new titles and seals.")
    page:Block(function() return QF.Journal:EntryLines() end, false, 10)
end

local SEAL_COLS, SEAL_ROW = 2, 46

-- earned seals in colour, the rest greyed out
local function sealGrid(parent)
    local f = CreateFrame("Frame", nil, parent)
    local cellW = CONTENT_W / SEAL_COLS
    f.cells = {}
    for i, seal in ipairs(QF.Journal.SEALS) do
        local cell = CreateFrame("Frame", nil, f)
        cell:SetSize(cellW - 6, SEAL_ROW - 6)
        cell:SetPoint("TOPLEFT", ((i - 1) % SEAL_COLS) * cellW, -math.floor((i - 1) / SEAL_COLS) * SEAL_ROW)
        cell.mark = W.IconFrame(cell, 30)
        cell.mark:SetPoint("LEFT", 2, 0)
        cell.mark:SetIcon("Interface\\Icons\\" .. seal.icon)
        cell.name = W.Text(cell, "GameFontHighlight", C.text)
        W.FontSize(cell.name, 14)
        cell.name:SetPoint("TOPLEFT", 40, -4)
        cell.name:SetWordWrap(false)
        cell.text = W.Text(cell, "GameFontHighlightSmall", C.muted)
        cell.text:SetPoint("TOPLEFT", cell.name, "BOTTOMLEFT", 0, -2)
        cell.text:SetWidth(cellW - 50)
        cell.text:SetWordWrap(false)
        cell.name:SetText(seal.name)
        cell.text:SetText(seal.text)
        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(c)
            local got = QF.Journal:Data().seals[seal.id]
            GameTooltip:SetOwner(c, "ANCHOR_RIGHT")
            GameTooltip:AddLine(seal.name, 1, 0.82, 0)
            GameTooltip:AddLine(seal.text, 0.9, 0.9, 0.9, true)
            if got then
                GameTooltip:AddLine(("Earned on day %d, %s."):format(got.day, date("%d %b %Y", got.time)), 0.5, 0.9, 0.5)
            else
                GameTooltip:AddLine("Not earned yet.", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cell.seal = seal
        f.cells[i] = cell
    end
    f:SetHeight(math.ceil(#f.cells / SEAL_COLS) * SEAL_ROW)
    function f:Update()
        local got = QF.Journal:Data().seals
        for _, cell in ipairs(self.cells) do
            local on = got[cell.seal.id] ~= nil
            cell.mark:SetLit(on)
            local c = on and C.text or C.muted
            cell.name:SetTextColor(c[1], c[2], c[3])
        end
    end
    f:Update()
    return f
end

local function buildTravelsPage(page)
    page:Section("The road so far")
    page:Block(function() return QF.Journal:StatLines() end, false, 170)
    page:Section("Seals")
    page:Add(sealGrid(page.frame))
end

-- The window

local PAGES = {
    { id = "guide", label = "Guide", build = buildGuidePage,
        sub = "Your place in the route, and every guide this character can use." },
    { id = "automation", label = "Automation", build = buildAutomationPage,
        sub = "What the addon does for you at NPCs, flight masters and vendors." },
    { id = "navigation", label = "Navigation", build = buildNavigationPage,
        sub = "The arrow, checkpoints, map pin and objective areas." },
    { id = "helpers", label = "Helpers", build = buildHelpersPage,
        sub = "Buttons, warnings and suggestions while you play." },
    { id = "appearance", label = "Appearance", build = buildAppearancePage,
        sub = "How the guide window looks and where things are." },
    { id = "character", label = "Character", build = buildCharacterPage,
        sub = "Level times, class quests, talents and spells for this character." },
    { id = "journal", label = "Journal", build = buildJournalPage,
        sub = "The important days of this character's road, newest first." },
    { id = "travels", label = "Travels", build = buildTravelsPage,
        sub = "Days, miles, flights and quests, and the seals earned on the way." },
    { id = "data", label = "Data", build = buildDataPage,
        sub = "Recording, positions and map bounds, and resetting the settings." },
    { id = "about", label = "About", build = buildAboutPage,
        sub = "What Questfarer is, its commands, credits and licence." },
}

local function pageDef(id)
    for _, def in ipairs(PAGES) do
        if def.id == id then return def end
    end
    return PAGES[1]
end

local function createRailButton(rail, def, index)
    local b = CreateFrame("Button", nil, rail)
    b:SetSize(RAIL_W - 12, RAIL_ROW - 2)
    b:SetPoint("TOPLEFT", 6, -8 - (index - 1) * RAIL_ROW)
    b.bg = W.Box(b, 8)
    W.Color(b.bg, C.selected, 0)
    b.mark = W.Marker(b, 6)
    b.mark:SetPoint("CENTER", b, "LEFT", 6, 0)
    b.mark:Style(C.accent)
    -- white pictograms from Media, tinted to match the label
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 15, 0)
    icon:SetTexture(W.MEDIA .. "menu_" .. def.id .. ".tga")
    local function tint(c)
        icon:SetVertexColor(c[1], c[2], c[3])
    end
    b.label = W.Text(b, "GameFontHighlight", C.muted)
    b.label:SetPoint("LEFT", icon, "RIGHT", 11, 0)
    b.label:SetWordWrap(false)
    b.label:SetText(def.label)
    function b:SetSelected(on)
        self.selected = on
        self.mark:SetShown(on)
        W.Color(self.bg, C.selected, on and 1 or 0)
        local c = on and C.text or C.muted
        self.label:SetTextColor(c[1], c[2], c[3])
        tint(on and C.accent or C.muted)
    end
    b:SetScript("OnClick", function() Options:ShowPage(def.id) end)
    b:SetScript("OnEnter", function(self)
        if not self.selected then
            W.Color(self.bg, C.surfaceHover, 1)
            tint(C.text)
        end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.selected then
            W.Color(self.bg, C.selected, 0)
            tint(C.muted)
        end
    end)
    b:SetSelected(false)
    return b
end

function Options:ApplyPoint()
    local f = self.frame
    if not f then return end
    f:ClearAllPoints()
    local p = QF.db.optionsPoint
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER")
    end
end

local function fitToScreen(f)
    local w, h = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    local scale = 1
    if w > 0 and h > 0 then scale = math.min(1, (w - 20) / WIDTH, (h - 20) / HEIGHT) end
    f:SetScale(scale)
end

function Options:Create()
    if self.frame then return end
    local f = CreateFrame("Frame", "QuestfarerOptionsFrame", UIParent)
    self.frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    W.Panel(f)
    table.insert(UISpecialFrames, "QuestfarerOptionsFrame") -- Escape closes it
    f.onMoved = function(frame)
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then QF.db.optionsPoint = { "TOPLEFT", "BOTTOMLEFT", left, top } end
    end
    self:ApplyPoint()

    local h = W.Header(f, TITLE_H, "Interface\\Icons\\INV_Misc_Map_01")
    h.title:SetText("Questfarer  |cffccb387Settings|r")
    local close = W.IconButton(h, 24, nil, "x", "Close", function() f:Hide() end)
    close:SetPoint("RIGHT", -4, 0)
    local ver = W.Text(h, "GameFontHighlightSmall", C.leatherMuted)
    ver:SetPoint("RIGHT", close, "LEFT", -8, 0)
    ver:SetText("v" .. (QF.version or ""))

    local rail = CreateFrame("Frame", nil, f)
    rail:SetPoint("TOPLEFT", 1, -(TITLE_H + 1))
    rail:SetPoint("BOTTOMLEFT", 1, 1)
    rail:SetWidth(RAIL_W)
    local railLine = rail:CreateTexture(nil, "BORDER")
    railLine:SetPoint("TOPRIGHT", 0, -8)
    railLine:SetPoint("BOTTOMRIGHT", 0, 8)
    railLine:SetWidth(1)
    W.Color(railLine, C.border)
    self.railButtons = {}
    for i, def in ipairs(PAGES) do self.railButtons[def.id] = createRailButton(rail, def, i) end
    local foot = W.Text(rail, "GameFontHighlightSmall", C.muted)
    foot:SetPoint("BOTTOMLEFT", 14, 10)
    foot:SetWidth(RAIL_W - 24)
    foot:SetText("Chat commands still work: |cffffd100/qf help|r")

    local left = RAIL_W + 1 + MARGIN
    self.pageTitle = W.Text(f, "GameFontNormalLarge", C.text)
    self.pageTitle:SetPoint("TOPLEFT", left, -(TITLE_H + 12))
    self.pageTitle:SetWordWrap(false)
    self.pageSub = W.Text(f, "GameFontHighlightSmall", C.muted)
    self.pageSub:SetPoint("TOPLEFT", self.pageTitle, "BOTTOMLEFT", 0, -3)
    self.pageSub:SetWidth(CONTENT_W)
    self.pageSub:SetWordWrap(false)

    local scroll = W.ScrollArea(f)
    self.scroll = scroll
    scroll:SetPoint("TOPLEFT", left, -(TITLE_H + 1 + HEAD_H + 8))
    scroll:SetPoint("BOTTOMRIGHT", -BAR_ROOM, 10)
    scroll.child:SetWidth(CONTENT_W)
    scroll.bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 7, 0)
    scroll.bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 7, 0)

    self.pages = {}
    f:SetScript("OnShow", function()
        fitToScreen(f)
        Options:ApplyPoint() -- Reset all may have cleared the saved position
        Options:ShowPage(QF.db.optionsTab)
    end)
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= REFRESH_EVERY then
            elapsed = 0
            Options:Update()
        end
    end)
end

function Options:ShowPage(id)
    local def = pageDef(id)
    QF.db.optionsTab = def.id
    if self.current then self.current.frame:Hide() end
    for pageId, b in pairs(self.railButtons) do b:SetSelected(pageId == def.id) end
    self.pageTitle:SetText(def.label)
    self.pageSub:SetText(def.sub)

    local page = self.pages[def.id]
    self.current = nil
    if not page then
        page = newPage(def)
        self.pages[def.id] = page
        page.frame:Show()
        local ok, err = pcall(def.build, page)
        if not ok then QF:Print("|cffff4444The " .. def.label .. " page failed to open:|r " .. tostring(err)) end
    end
    self.current = page
    page.frame:Show()
    self.scroll:SetVerticalScroll(0)
    page:Refresh()
    -- new text measures wrong until drawn once
    C_Timer.After(0, function()
        if self.current == page then page:Layout() end
    end)
end

function Options:Update()
    if not (self.frame and self.frame:IsShown() and self.current) then return end
    self.current:Refresh()
end

-- called on every guide update: debounced, skips the heavy blocks
function Options:RequestRefresh()
    if self.refreshPending or not (self.frame and self.frame:IsShown()) then return end
    self.refreshPending = true
    C_Timer.After(0.25, function()
        self.refreshPending = false
        if self.frame:IsShown() and self.current then self.current:Refresh(true) end
    end)
end

-- these only exist after login
local function ready()
    return QF.db and QF.char and QF.player
end

function Options:Toggle()
    if not ready() then return end
    self:Create()
    self.frame:SetShown(not self.frame:IsShown())
end

function Options:Open()
    if not ready() then return end
    self:Create()
    self.frame:Show()
    self.frame:Raise()
end

function Options:OpenPage(id)
    if not ready() then return end
    QF.db.optionsTab = id
    self:Open()
    self:ShowPage(id)
end

-- stub page under Options > AddOns that opens our window
local function registerBlizzardPage()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local page = CreateFrame("Frame")
    local title = W.Text(page, "GameFontNormalHuge", C.gold)
    W.FontSize(title, 22)
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText("Questfarer")
    local desc = W.Text(page, "GameFontHighlight", C.text)
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    desc:SetWidth(520)
    desc:SetText("Step-by-step leveling guide for WoW Forever. All settings are in the Questfarer settings " ..
        "window - open it with the button below, the gear icon on the guide window, or /qf options.")
    local open = W.Button(page, "Open settings", 160, 26, function()
        if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
        Options:Open()
    end)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, page, "Questfarer")
    if ok and category then
        pcall(Settings.RegisterAddOnCategory, category)
    end
end

QF:On("PLAYER_LOGIN", function()
    registerBlizzardPage()
    hooksecurefunc(QF, "Update", function() Options:RequestRefresh() end)
end)

-- these change the page without the guide moving
for _, event in ipairs({ "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "SPELLS_CHANGED",
    "UPDATE_BINDINGS", "QUEST_TURNED_IN" }) do
    QF:On(event, function() C_Timer.After(0.5, function() Options:Update() end) end)
end
