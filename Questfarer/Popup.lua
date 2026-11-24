-- Small notes above the guide window for a new chapter, title or seal. A click opens the whole page.

local _, ns = ...
local QF = ns.QF
local W = QF.W
local C = W.colors

local P = {}
QF.Popup = P

local SHOW_FOR = 14   -- seconds before a note fades
local FADE = 1
local NOTE_H = 40
local PAGE_W = 380
local ICONS = "Interface\\Icons\\"

local LANDS = {
    ["Elwynn Forest"] = "Green hills, quiet farms and the white walls of Stormwind on the horizon. Every road starts somewhere, and this one starts here.",
    ["Dun Morogh"] = "Snow underfoot and forge smoke in the air. The mountain keeps its secrets, but it shares its warmth with those who work.",
    ["Teldrassil"] = "Under the great tree the light falls green and slow. The forest watches every new step.",
    ["Durotar"] = "Red earth, hard sun and a wind full of dust. Here strength is earned one day at a time.",
    ["Mulgore"] = "Wide plains under an open sky. The land is patient, and so are its people.",
    ["Tirisfal Glades"] = "Grey trees, cold mist and a quiet that is not quite peace. Even the dead have to start somewhere.",
    ["Westfall"] = "Empty farms and long fields gone to seed. Someone has to stand up for the people who stayed.",
    ["Loch Modan"] = "A deep blue lake behind a great dam, with hills on every side. Good fishing, honest work and trouble in the hills.",
    ["Darkshore"] = "A long grey coast under a sky that never quite clears. The sea brings things ashore that should have stayed under.",
    ["The Barrens"] = "Dry grass as far as the eye can see, and a long walk to anywhere. Keep your water close and your eyes open.",
    ["Silverpine Forest"] = "Dark pines and a cold wind off the sea. Every shadow seems to be listening.",
    ["Redridge Mountains"] = "Red cliffs over a calm lake, and smoke rising from the hills. Lakeshire needs every sword it can get.",
    ["Duskwood"] = "The sun never quite reaches the ground here. Keep the lantern lit and do not walk the road alone.",
    ["Wetlands"] = "Rain, mud and the croak of things in the reeds. The old road runs north, if you can keep your boots dry.",
    ["Ashenvale"] = "Old trees, deep shade and a forest that remembers every axe. Tread softly.",
    ["Stonetalon Mountains"] = "Steep paths, high peaks and a valley scarred by saws. The climb is long, but the view is worth it.",
    ["Hillsbrad Foothills"] = "Green farmland between the mountains and the sea, with soldiers on every road. Peace here is only a rumour.",
    ["Alterac Mountains"] = "Snow, ruins and broken banners. Some kingdoms fall and leave only their quarrels behind.",
    ["Arathi Highlands"] = "Rolling highlands and the stones of an old kingdom. Many have fought over this ground, and they are not finished.",
    ["Thousand Needles"] = "Stone spires rising from a dry valley floor. Watch your footing, and your back.",
    ["Desolace"] = "Grey land, bones in the dust and drums in the distance. Little grows here but trouble.",
    ["Stranglethorn Vale"] = "Thick jungle, old ruins and hunters in every clearing. Here you are either the hunter or the hunted.",
    ["Dustwallow Marsh"] = "Warm fog, sucking mud and a fortress by the sea. Whatever lives in this swamp is bigger than you.",
    ["Badlands"] = "Sun-baked rock and the bones of old dragons. Nothing here wants you to stay.",
    ["Swamp of Sorrows"] = "Black water, drooping trees and a sadness that hangs in the air. Keep moving.",
    ["Feralas"] = "Rain-soaked forest and giant trees along a misty coast. The wilds here are old and proud.",
    ["Tanaris"] = "Endless dunes and a single town of traders and rogues. Water is worth more than gold.",
    ["The Hinterlands"] = "Green hills, high cliffs and the cries of gryphons. Trolls still hold the old places.",
    ["Searing Gorge"] = "Ash, slag and the heat of a world on fire. The mountain bleeds iron here.",
    ["Azshara"] = "Ruins of a vanished empire, slowly sinking into the sea. Beauty and danger in equal parts.",
    ["Blasted Lands"] = "Cracked red earth and a dark gate on the horizon. The land itself remembers the invasion.",
    ["Un'Goro Crater"] = "Steam, giant ferns and the roar of things older than history. The world was young here once, and it still is.",
    ["Felwood"] = "A poisoned forest where even the water burns. Fight for every tree.",
    ["Burning Steppes"] = "Black rock under a red sky, and dragons on the wind. Bring armour, and bring friends.",
    ["Western Plaguelands"] = "Grey fields and empty farmhouses. The plague took this land, and someone has to take it back.",
    ["Eastern Plaguelands"] = "Rot, ash and the march of the dead. Few travellers come this far, and fewer go home.",
    ["Winterspring"] = "Deep snow, quiet pines and stars close enough to touch. The road nearly ends here, and it ends in beauty.",
    ["Silithus"] = "Sand, wind and the hum of hives under the earth. Something stirs below.",
    ["Deadwind Pass"] = "A dead valley under a dark sky, and a tower that watches. Do not linger.",
    ["Moonglade"] = "A still lake ringed by peaceful hills. Here, for a moment, the road can rest.",
    ["Mount Hyjal"] = "Snow-touched slopes and ancient trees under a mountain sky. An old power sleeps here, and the road climbs toward it.",
    ["Stormwind City"] = "White walls, busy streets and the bells of the cathedral. Rest, trade and tell your stories.",
    ["Ironforge"] = "Halls carved deep into the mountain, loud with hammers. The forge never sleeps.",
    ["Darnassus"] = "Quiet halls among the branches, lit by moonwells. A city that grows rather than being built.",
    ["Orgrimmar"] = "Spikes, smoke and a city carved into a canyon. Loud, proud and never asleep.",
    ["Thunder Bluff"] = "Tall mesas joined by swaying bridges, with wind and drums. Look down only once.",
    ["Undercity"] = "Green light and echoing halls under a ruined castle. Everyone here has already died once.",
}
local NEW_LAND = "A new land and a fresh page. Nobody here knows your name yet."

local TITLE_TEXT = {
    ["Wanderer"] = "Nobody knows your name yet, but people have started to notice your boots on the road.",
    ["Pathfinder"] = "You no longer wait to be shown the way. The trails start to make sense, and people ask you for directions.",
    ["Wayfarer"] = "The road has become your home. Innkeepers know your face and flight masters know your coin.",
    ["Seasoned Traveller"] = "Scars, stories and a pack that never quite empties. You have seen more of the world than most will in a lifetime.",
    ["Roadwarden"] = "Old enough for a mount, and strong enough to watch over those who walk the roads after you.",
    ["Veteran of the Road"] = "There are few roads left that you have not walked. Young travellers go quiet when you pass.",
    ["Legend of the Road"] = "The end of the road, and the start of a legend. The bards will get the details wrong, but they will sing about you.",
}

local queue = {}

local function dayLine()
    return ("Day %d of the road"):format(QF.Journal:Day())
end

local function wax(s)
    return "|cff" .. W.Hex(C.accent) .. s .. "|r"
end

function P:CreatePage()
    if self.page then return end
    local f = CreateFrame("Frame", "QuestfarerJournalPage", UIParent)
    self.page = f
    f:SetWidth(PAGE_W)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    W.Panel(f)
    table.insert(UISpecialFrames, "QuestfarerJournalPage")
    f.seal = W.IconFrame(f, 26)
    f.seal:SetPoint("TOPLEFT", 14, -16)
    f.title = W.Text(f, "GameFontNormalLarge", C.gold)
    W.FontSize(f.title, 20)
    f.title:SetPoint("TOPLEFT", 48, -16)
    f.title:SetPoint("RIGHT", -40, 0)
    f.title:SetWordWrap(false)
    f.sub = W.Text(f, "GameFontHighlightSmall", C.muted)
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.body = W.Text(f, "GameFontHighlight", C.text)
    W.FontSize(f.body, 14)
    f.body:SetWidth(PAGE_W - 64)
    f.body:SetSpacing(3)
    f.body:SetPoint("TOPLEFT", 48, -62)
    local close = W.IconButton(f, 22, nil, "x", "Close", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    local journal = W.Button(f, "Open the journal", 130, 24, function()
        f:Hide()
        QF.Options:OpenPage("journal")
    end)
    journal:SetPoint("BOTTOMRIGHT", -14, 14)
end

function P:ShowPage(note)
    self:CreatePage()
    local f = self.page
    f.seal:SetIcon(ICONS .. note.icon)
    f.title:SetText(note.title)
    f.sub:SetText(note.sub or dayLine())
    f.body:SetText(note.body)
    f:SetHeight(62 + W.TextHeight(f.body) + 56)
    f:Show()
    f:Raise()
    -- measures wrong until drawn once
    C_Timer.After(0, function() f:SetHeight(62 + W.TextHeight(f.body) + 56) end)
end

function P:CreateNote()
    if self.note then return end
    local f = CreateFrame("Button", "QuestfarerJournalNote", UIParent)
    self.note = f
    f:SetHeight(NOTE_H)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:Hide()
    W.Panel(f)
    f.seal = W.IconFrame(f, 24)
    f.seal:SetPoint("LEFT", 8, 0)
    f.title = W.Text(f, "GameFontNormal", C.gold)
    W.FontSize(f.title, 14)
    f.title:SetPoint("TOPLEFT", 40, -6)
    f.title:SetPoint("RIGHT", -10, 0)
    f.title:SetWordWrap(false)
    f.hint = W.Text(f, "GameFontHighlightSmall", C.muted)
    f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
    f.hint:SetText("Click to read the page, right-click to put it away.")
    f:SetScript("OnClick", function(_, button)
        local note = f.current
        P:Next()
        if button == "LeftButton" and note then P:ShowPage(note) end
    end)
    f:SetScript("OnEnter", function() f.hold = true end)
    f:SetScript("OnLeave", function() f.hold = false end)
    f:SetScript("OnUpdate", function(_, dt)
        if f.hold then
            f.shownFor = math.min(f.shownFor, SHOW_FOR - 2)
            f:SetAlpha(1)
            return
        end
        f.shownFor = f.shownFor + dt
        if f.shownFor > SHOW_FOR + FADE then
            P:Next()
        elseif f.shownFor > SHOW_FOR then
            f:SetAlpha(1 - (f.shownFor - SHOW_FOR) / FADE)
        end
    end)
end

-- over the guide window when it is shown, else near the top of the screen
function P:PlaceNote()
    local f = self.note
    local guide = QF.UI and QF.UI.frame
    f:ClearAllPoints()
    if guide and guide:IsShown() then
        f:SetScale(guide:GetScale())
        f:SetWidth(guide:GetWidth())
        f:SetPoint("BOTTOMLEFT", guide, "TOPLEFT", 0, 4)
    else
        f:SetScale(QF.db.scale or 1)
        f:SetWidth(QF.db.width or 340)
        f:SetPoint("TOP", UIParent, "TOP", 0, -160)
    end
end

function P:Next()
    local f = self.note
    f.current = nil
    f:Hide()
    local note = table.remove(queue, 1)
    if not note then return end
    f.current = note
    f.seal:SetIcon(ICONS .. note.icon)
    f.title:SetText(note.short)
    f.shownFor = 0
    f.hold = false
    f:SetAlpha(1)
    self:PlaceNote()
    f:Show()
end

function P:Push(note)
    if not QF.db.rpPopups then return end
    self:CreateNote()
    table.insert(queue, note)
    if not self.note.current then self:Next() end
end

function P:Chapter(n, land, level)
    local numeral = QF.Journal.Roman(n)
    self:Push({
        short = wax("Chapter " .. numeral) .. "   " .. land,
        title = ("Chapter %s: %s"):format(numeral, land),
        icon = "INV_Misc_Map_01",
        body = (LANDS[land] or NEW_LAND) ..
            ("\n\nYou arrived here at level %d."):format(level),
    })
end

function P:Title(title, level)
    self:Push({
        short = wax("A new name") .. "   " .. title,
        title = title,
        icon = "INV_Misc_Book_11",
        sub = ("Level %d, %s"):format(level, dayLine():lower()),
        body = (TITLE_TEXT[title] or "") .. "\n\nFrom now on the road knows you as " ..
            (UnitName("player") or "?") .. ", " .. title .. ".",
    })
end

function P:Seal(seal)
    local earned = 0
    for _ in pairs(QF.Journal:Data().seals) do earned = earned + 1 end
    self:Push({
        short = wax("Seal earned") .. "   " .. seal.name,
        title = seal.name,
        icon = seal.icon,
        body = seal.text .. ("\n\nThat makes %d of %d seals. They are kept under Travels in the settings."):format(
            earned, #QF.Journal.SEALS),
    })
end
