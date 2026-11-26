-- Questfarer - Widgets. No Blizzard templates, they differ between clients.

local addonName, ns = ...
local QF = ns.QF

local W = {}
QF.W = W

-- dark is worn leather with a bronze rim, light is parchment with brown ink. Both seal in red wax.
local THEMES = {}
THEMES.dark = {
    bg = { 0.105, 0.085, 0.065 },
    header = { 0.075, 0.06, 0.045 },
    surface = { 0.15, 0.12, 0.09 },
    surfaceHover = { 0.20, 0.16, 0.12 },
    selected = { 0.25, 0.19, 0.13 },
    border = { 0.33, 0.26, 0.18 },
    frame = { 0.45, 0.35, 0.22 },
    accent = { 0.80, 0.32, 0.20 },
    accentHover = { 0.90, 0.40, 0.26 },
    gold = { 0.93, 0.76, 0.42 },
    text = { 0.92, 0.87, 0.77 },
    muted = { 0.65, 0.58, 0.47 },
    button = { 0.18, 0.145, 0.11 },
    buttonHover = { 0.26, 0.20, 0.15 },
    off = { 0.30, 0.25, 0.19 },
    purple = { 0.62, 0.46, 0.82 },
    purpleHover = { 0.70, 0.55, 0.88 },
    danger = { 0.72, 0.24, 0.16 },
    dangerHover = { 0.84, 0.32, 0.22 },
    good = { 0.48, 0.74, 0.36 },
    leather = { 0.055, 0.045, 0.035 },
    leatherHover = { 0.17, 0.13, 0.10 },
    leatherText = { 0.95, 0.88, 0.72 },
    leatherMuted = { 0.68, 0.59, 0.45 },
    -- the header runs from wine red to a dark teal
    headerFrom = { 0.24, 0.12, 0.08 },
    headerTo = { 0.07, 0.09, 0.09 },
    highlight = { 1, 0.94, 0.80 },
    rim = { 0.36, 0.27, 0.16 },
    inner = { 0.50, 0.38, 0.22 },
    shade = { 0, 0, 0 },
}
THEMES.light = {
    bg = { 0.914, 0.863, 0.737 },
    header = { 0.87, 0.81, 0.66 },
    surface = { 0.94, 0.90, 0.80 },
    surfaceHover = { 0.89, 0.83, 0.69 },
    selected = { 0.84, 0.76, 0.58 },
    border = { 0.72, 0.62, 0.45 },
    frame = { 0.43, 0.33, 0.196 },
    accent = { 0.54, 0.165, 0.11 },
    accentHover = { 0.66, 0.22, 0.15 },
    gold = { 0.30, 0.20, 0.09 },
    text = { 0.227, 0.165, 0.086 },
    muted = { 0.43, 0.33, 0.196 },
    button = { 0.90, 0.84, 0.70 },
    buttonHover = { 0.85, 0.77, 0.60 },
    off = { 0.80, 0.72, 0.56 },
    purple = { 0.36, 0.22, 0.48 },
    purpleHover = { 0.46, 0.30, 0.58 },
    danger = { 0.62, 0.18, 0.12 },
    dangerHover = { 0.74, 0.25, 0.17 },
    good = { 0.25, 0.45, 0.20 },
    -- the dark leather band the headers sit on
    leather = { 0.27, 0.18, 0.10 },
    leatherHover = { 0.38, 0.26, 0.15 },
    leatherText = { 0.96, 0.91, 0.79 },
    leatherMuted = { 0.80, 0.70, 0.53 },
    headerFrom = { 0.40, 0.17, 0.10 },
    headerTo = { 0.24, 0.18, 0.11 },
    highlight = { 1, 0.98, 0.90 },
    rim = { 0.27, 0.18, 0.10 },
    inner = { 1, 0.98, 0.90 },
    shade = { 0.43, 0.33, 0.196 },
}

-- filled by W.SetTheme, modules keep a reference to this table
W.colors = {}
local C = W.colors
local inked

-- colour codes written for dark chat, swapped for ink colours that read on parchment
local INK = {
    ffd100 = "7a3b12", ffd700 = "8a6212", ffff00 = "8a6212", ffcc66 = "8a6212",
    ffffff = "2a1d0e", cccccc = "5a4630",
    ["999999"] = "7a6a55", ["888888"] = "7a6a55", ["9aa0aa"] = "7a6a55", c7c7cf = "6a6a70",
    ["00ff00"] = "3f6b1f", ["33ff33"] = "3f6b1f", ["55dd55"] = "3f6b1f", ["66ff77"] = "3f6b1f",
    ff6666 = "9b2418", ff4444 = "9b2418", ff9933 = "a5541a", eda55f = "8a4a20",
    ["66ccff"] = "2f5f7a", ["99ccff"] = "2f5f7a", ["33ccff"] = "2f5f7a", ["66ffcc"] = "2f6e5e",
    cc77ff = "5e3a7e", d8c8ff = "5e3a7e",
}

function W.Ink(s)
    if not inked or type(s) ~= "string" then return s end
    return (s:gsub("|c[fF][fF](%x%x%x%x%x%x)", function(h)
        local ink = INK[h:lower()]
        return ink and ("|cff" .. ink) or nil
    end))
end

function W.Color(tex, c, a)
    tex:SetColorTexture(c[1], c[2], c[3], a or 1)
end

-- "rrggbb" for |cff codes
function W.Hex(c)
    return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

function W.Border(f, c, a)
    c = c or C.border
    local edges = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "BORDER")
        W.Color(t, c, a or 1)
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    f.borderEdges = edges
    return edges
end

function W.BorderColor(f, c, a)
    for _, t in ipairs(f.borderEdges or {}) do W.Color(t, c, a or 1) end
end

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
W.MEDIA = MEDIA

-- Rounded boxes. The textures come from Tools/make_corners.py: a 32 unit tile where
-- a 12 unit corner piece holds a 3 unit margin, a 6 unit radius and a 2 unit border.
-- Shapes, icons and the compass come from Tools/make_shapes.py.
local ROUND = MEDIA .. "round_"
local PIECE, MARGIN, CUT = 12, 3, 12 / 32

-- from and to are colours, a1 and a2 their alpha. Plain colour where the client lacks SetGradient.
local function gradient(tex, orientation, from, to, a1, a2)
    a1 = a1 or 1
    if CreateColor and tex.SetGradient then
        local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(from[1], from[2], from[3], a1),
            CreateColor(to[1], to[2], to[3], a2 or a1))
        if ok then return end
    end
    tex:SetVertexColor(from[1], from[2], from[3], a1)
end
W.Gradient = gradient

-- textures that W.Color, SetAlpha and SetShown treat as one
local Box = {}
Box.__index = Box
function Box:SetColorTexture(r, g, b, a)
    for _, t in ipairs(self) do t:SetVertexColor(r, g, b, a or 1) end
end
function Box:SetAlpha(a)
    for _, t in ipairs(self) do t:SetAlpha(a) end
end
function Box:SetShown(on)
    for _, t in ipairs(self) do t:SetShown(on) end
end
-- vertical only, the pieces of a box don't share one horizontal span
function Box:SetGradient(bottom, top, a1, a2)
    for _, t in ipairs(self) do gradient(t, "VERTICAL", bottom, top, a1, a2) end
end

-- a pill: two half circles and a stretched middle. Caps are half the frame's height,
-- so give the frame its size first. kind: circle or ring
function W.Pill(f, kind, layer, sub)
    local file = MEDIA .. (kind == "ring" and "shape_ring" or "shape_circle") .. ".tga"
    local p = setmetatable({}, Box)
    for i = 1, 3 do
        local t = f:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
        t:SetTexture(file)
        p[i] = t
    end
    local cap = f:GetHeight() / 2
    p[1]:SetTexCoord(0, 0.5, 0, 1)
    p[2]:SetTexCoord(0.5, 0.5, 0, 1)
    p[3]:SetTexCoord(0.5, 1, 0, 1)
    p[1]:SetPoint("TOPLEFT"); p[1]:SetPoint("BOTTOMLEFT"); p[1]:SetWidth(cap)
    p[3]:SetPoint("TOPRIGHT"); p[3]:SetPoint("BOTTOMRIGHT"); p[3]:SetWidth(cap)
    p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT"); p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT")
    return p
end

-- colour running left to right over a pill
function W.PillAcross(p, from, to, a)
    p[1]:SetVertexColor(from[1], from[2], from[3], a or 1)
    gradient(p[2], "HORIZONTAL", from, to, a)
    p[3]:SetVertexColor(to[1], to[2], to[3], a or 1)
end

-- kind: solid, fill, ring, inner, shadow or shade. corner scales it all, 12 is the window.
function W.Round(f, kind, corner, layer, sub)
    corner = corner or PIECE
    local m = corner * MARGIN / PIECE
    local cuts = { 0, CUT, 1 - CUT, 1 }
    local p = setmetatable({}, Box)
    for i = 1, 9 do
        local t = f:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
        t:SetTexture(ROUND .. kind .. ".tga")
        local row, col = math.floor((i - 1) / 3) + 1, (i - 1) % 3 + 1
        t:SetTexCoord(cuts[col], cuts[col + 1], cuts[row], cuts[row + 1])
        p[i] = t
    end
    -- 1 2 3 / 4 5 6 / 7 8 9: the corners keep their size, the rest stretches
    for _, i in ipairs({ 1, 3, 7, 9 }) do p[i]:SetSize(corner, corner) end
    p[1]:SetPoint("TOPLEFT", -m, m)
    p[3]:SetPoint("TOPRIGHT", m, m)
    p[7]:SetPoint("BOTTOMLEFT", -m, -m)
    p[9]:SetPoint("BOTTOMRIGHT", m, -m)
    p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT"); p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT")
    p[8]:SetPoint("TOPLEFT", p[7], "TOPRIGHT"); p[8]:SetPoint("BOTTOMRIGHT", p[9], "BOTTOMLEFT")
    p[4]:SetPoint("TOPLEFT", p[1], "BOTTOMLEFT"); p[4]:SetPoint("BOTTOMRIGHT", p[7], "TOPRIGHT")
    p[6]:SetPoint("TOPLEFT", p[3], "BOTTOMLEFT"); p[6]:SetPoint("BOTTOMRIGHT", p[9], "TOPRIGHT")
    p[5]:SetPoint("TOPLEFT", p[1], "BOTTOMRIGHT"); p[5]:SetPoint("BOTTOMRIGHT", p[9], "TOPLEFT")
    return p
end

-- rounded background. ringed adds a border that W.BorderColor tints.
function W.Box(f, corner, ringed)
    if not ringed then return W.Round(f, "solid", corner) end
    f.borderEdges = { W.Round(f, "ring", corner, "BORDER") }
    return W.Round(f, "fill", corner)
end

-- returns bg, its alpha is the window opacity. flat: square and plain (small buttons)
function W.Panel(f, flat)
    if flat then
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        W.Color(bg, C.bg, 1)
        W.Border(f, C.frame, 0.85)
        return bg
    end
    local bg = W.Round(f, "fill")
    W.Color(bg, C.bg)
    W.Color(W.Round(f, "shadow", nil, "BACKGROUND", -8), { 0, 0, 0 }, 0.5)
    -- darker towards the edges, like old paper
    W.Color(W.Round(f, "shade", nil, "BACKGROUND", 1), C.shade, 0.2)
    W.Color(W.Round(f, "ring", nil, "BORDER"), C.rim)
    W.Color(W.Round(f, "inner", nil, "BORDER"), C.inner, 0.55)
    return bg
end

local DOT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- round trail marker, hollow ones are a ring
function W.Marker(parent, size)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(size, size)
    local dot = m:CreateTexture(nil, "ARTWORK")
    dot:SetAllPoints()
    dot:SetTexture(DOT)
    local hole = m:CreateTexture(nil, "OVERLAY")
    hole:SetPoint("TOPLEFT", 1.5, -1.5)
    hole:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    hole:SetTexture(DOT)
    hole:SetVertexColor(C.bg[1], C.bg[2], C.bg[3])
    function m:Style(c, hollow)
        dot:SetVertexColor(c[1], c[2], c[3])
        hole:SetShown(hollow and true or false)
    end
    return m
end

local NOTE_ICON = "Interface\\Icons\\INV_Misc_Note_01"

-- an icon in a thin dark frame. SetIcon falls back to a note when the client lacks the file.
function W.IconFrame(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local back = f:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    W.Color(back, C.leather)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.tex = tex
    function f:SetIcon(path)
        if tex:SetTexture(path) == false then tex:SetTexture(NOTE_ICON) end
    end
    -- unearned: grey and faded
    function f:SetLit(on)
        tex:SetDesaturated(not on)
        tex:SetAlpha(on and 1 or 0.45)
        back:SetAlpha(on and 1 or 0.5)
    end
    return f
end

function W.Text(parent, template, c, size)
    local s = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    s:SetJustifyH("LEFT")
    s:SetJustifyV("TOP")
    s:SetWordWrap(true)
    s:SetShadowOffset(0, 0)
    s:SetTextColor(unpack(c or C.text))
    if size then
        local font, _, flags = s:GetFont()
        if font then s:SetFont(font, size, flags) end
    end
    local setText = s.SetText
    function s:SetText(t) setText(self, W.Ink(t)) end
    return s
end

function W.FontSize(s, size)
    local font, _, flags = s:GetFont()
    if font then s:SetFont(font, size, flags) end
end

-- GetStringHeight can be 0 before the string is drawn once
function W.TextHeight(s)
    return math.max(s:GetStringHeight() or 0, 12)
end

-- the header is dark leather in both themes, so its trim is always this gold
local HEADER_GOLD = { 0.93, 0.76, 0.42 }

-- dragging the header moves f. Children check h.dark to pick light colours.
function W.Header(f, height, icon)
    local h = CreateFrame("Frame", nil, f)
    h:SetPoint("TOPLEFT", 2, -2)
    h:SetPoint("TOPRIGHT", -2, -2)
    h:SetHeight(height)
    h.dark = true

    -- the window's own rounded top, cut off where the header ends
    local p = W.Round(f, "fill", nil, "BACKGROUND", 2)
    for i = 7, 9 do p[i]:Hide() end
    local inset = PIECE - MARGIN - 2
    p[4]:ClearAllPoints()
    p[4]:SetPoint("TOPLEFT", p[1], "BOTTOMLEFT")
    p[4]:SetPoint("BOTTOMRIGHT", h, "BOTTOMLEFT", inset, 0)
    p[6]:ClearAllPoints()
    p[6]:SetPoint("TOPRIGHT", p[3], "BOTTOMRIGHT")
    p[6]:SetPoint("BOTTOMLEFT", h, "BOTTOMRIGHT", -inset, 0)
    p[5]:ClearAllPoints()
    p[5]:SetPoint("TOPLEFT", p[1], "BOTTOMRIGHT")
    p[5]:SetPoint("BOTTOMRIGHT", p[6], "BOTTOMLEFT")
    for _, i in ipairs({ 1, 4 }) do p[i]:SetVertexColor(unpack(C.headerFrom)) end
    for _, i in ipairs({ 3, 6 }) do p[i]:SetVertexColor(unpack(C.headerTo)) end
    for _, i in ipairs({ 2, 5 }) do gradient(p[i], "HORIZONTAL", C.headerFrom, C.headerTo) end
    h.bg = setmetatable({ p[1], p[2], p[3], p[4], p[5], p[6] }, Box)

    local band = h:CreateTexture(nil, "BORDER")
    band:SetPoint("BOTTOMLEFT"); band:SetPoint("BOTTOMRIGHT"); band:SetHeight(2)
    band:SetColorTexture(1, 1, 1)
    gradient(band, "HORIZONTAL", C.accent, HEADER_GOLD, 1, 0.35)
    local shade = f:CreateTexture(nil, "BORDER")
    shade:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, 0)
    shade:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", 0, 0)
    shade:SetHeight(4)
    shade:SetColorTexture(1, 1, 1)
    gradient(shade, "VERTICAL", C.shade, C.shade, 0, 0.3)

    local left
    if icon then
        local ic = h:CreateTexture(nil, "ARTWORK")
        ic:SetSize(height - 10, height - 10)
        ic:SetPoint("LEFT", 8, 0)
        ic:SetTexture(icon)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if ic.SetMask then pcall(ic.SetMask, ic, DOT) end
        local ring = h:CreateTexture(nil, "OVERLAY")
        ring:SetPoint("TOPLEFT", ic, -2, 2)
        ring:SetPoint("BOTTOMRIGHT", ic, 2, -2)
        ring:SetTexture(MEDIA .. "shape_ring.tga")
        ring:SetVertexColor(unpack(HEADER_GOLD))
        h.icon = ic
        left = height + 2
    else
        -- a small gem where the icon would be
        local gem = h:CreateTexture(nil, "ARTWORK")
        gem:SetSize(14, 14)
        gem:SetPoint("LEFT", 9, 0)
        gem:SetTexture(MEDIA .. "shape_diamond.tga")
        gem:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        local dot = h:CreateTexture(nil, "OVERLAY")
        dot:SetSize(5, 5)
        dot:SetPoint("CENTER", gem)
        dot:SetTexture(MEDIA .. "shape_circle.tga")
        dot:SetVertexColor(unpack(HEADER_GOLD))
        left = 30
    end
    h.title = W.Text(h, "GameFontNormal", C.leatherText, 13)
    h.title:SetPoint("LEFT", left, 1)
    h.title:SetWordWrap(false)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function()
        if f:IsMovable() and not (f.isLocked and f.isLocked()) then f:StartMoving() end
    end)
    h:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if f.onMoved then f.onMoved(f) end
    end)
    return h
end

local function hoverable(b, bg, hover)
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then W.Color(bg, self.hoverColor or hover, bg.alpha or 1) end
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        W.Color(bg, self.normalColor or C.button, bg.alpha or 1)
        GameTooltip:Hide()
    end)
end

-- kind: nil, "primary" or "train"
function W.Button(parent, text, width, height, onClick, kind)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 22)
    local bg = W.Pill(b, "circle")
    W.Color(bg, C.button)
    b.borderEdges = { W.Pill(b, "ring", "BORDER") }
    W.BorderColor(b, C.border)
    -- light from above
    local gloss = W.Pill(b, "circle", "BACKGROUND", 1)
    gloss:SetGradient({ 1, 1, 1 }, { 1, 1, 1 }, 0, kind == "primary" and 0.22 or 0.08)
    b.bg = bg
    b.label = W.Text(b, "GameFontHighlightSmall", C.text)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetWordWrap(false)
    b.label:SetText(text)
    function b:SetText(t) self.label:SetText(t) end
    function b:SetColor(c, a, hover)
        self.normalColor = c
        self.hoverColor = hover
        bg.alpha = a or 1
        W.Color(bg, c, bg.alpha)
    end
    function b:SetActive(on)
        self:SetEnabled(on and true or false)
        self:SetAlpha(on and 1 or 0.45)
    end
    hoverable(b, bg, C.buttonHover)
    b:SetScript("OnMouseDown", function() b.label:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function() b.label:SetPoint("CENTER") end)
    b:SetScript("OnClick", onClick)
    if kind == "primary" then
        b:SetColor(C.accent, 1, C.accentHover)
        W.BorderColor(b, C.accentHover)
        b.label:SetTextColor(C.leatherText[1], C.leatherText[2], C.leatherText[3])
    elseif kind == "train" then
        local c = W.StepStyle("train").color
        W.BorderColor(b, c, 0.8)
        b.label:SetTextColor(c[1], c[2], c[3])
    end
    return b
end

local CONFIRM_TIME = 4 -- seconds

-- first click arms it, a second click within CONFIRM_TIME does it
function W.ConfirmButton(parent, text, width, height, onConfirm, confirmText)
    local b
    local armedAt = 0
    local function disarm()
        armedAt = armedAt + 1
        b.armed = false
        b:SetText(text)
        b:SetColor(C.button)
    end
    b = W.Button(parent, text, width, height, function()
        if b.armed then
            disarm()
            onConfirm()
            return
        end
        b.armed = true
        armedAt = armedAt + 1
        local mine = armedAt
        b:SetText(confirmText or "Click again")
        b:SetColor(C.danger, 1, C.dangerHover)
        C_Timer.After(CONFIRM_TIME, function()
            if mine == armedAt and b.armed then disarm() end
        end)
    end)
    b.Disarm = disarm
    b:SetScript("OnHide", disarm)
    return b
end

local GLYPH = { x = "icon_close", ["-"] = "icon_minus", ["+"] = "icon_plus", gear = "icon_gear" }

-- glyph is x, -, + or gear, drawn from Media. SetGlyph swaps it later.
function W.IconButton(parent, size, texture, glyph, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local dark = parent.dark
    local idle, hot, hover = C.muted, C.accent, C.buttonHover
    if dark then idle, hot, hover = C.leatherMuted, C.highlight, C.leatherHover end
    local bg = W.Pill(b, "circle")
    W.Color(bg, hover, 0)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", 3, -3)
    t:SetPoint("BOTTOMRIGHT", -3, 3)
    b.icon = t
    function b:SetGlyph(g)
        t:SetTexture(MEDIA .. (GLYPH[g] or GLYPH.x) .. ".tga")
    end
    if texture then t:SetTexture(texture) else b:SetGlyph(glyph) end
    local function tint(c)
        t:SetVertexColor(c[1], c[2], c[3])
    end
    tint(idle)
    b.tooltip = tooltip
    b:SetScript("OnEnter", function(self)
        W.Color(bg, hover, 1)
        tint(hot)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        W.Color(bg, hover, 0)
        tint(idle)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

local function surface(f)
    local bg = W.Box(f, 8)
    W.Color(bg, C.surface)
    return bg
end

function W.Switch(parent, width, label, desc, get, set)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(42)
    local bg = surface(row)
    local pill = CreateFrame("Frame", nil, row)
    pill:SetSize(30, 14)
    pill:SetPoint("RIGHT", -12, 0)
    local track = W.Box(pill, 9)
    local knob = pill:CreateTexture(nil, "OVERLAY")
    knob:SetSize(10, 10)
    knob:SetTexture(DOT)
    row.text = W.Text(row, "GameFontHighlight", C.text)
    row.text:SetPoint("TOPLEFT", 12, -8)
    row.text:SetWidth(width - 66)
    row.text:SetWordWrap(false)
    row.text:SetText(label)
    row.desc = W.Text(row, "GameFontHighlightSmall", C.muted)
    row.desc:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -3)
    row.desc:SetWidth(width - 66)
    row.desc:SetText(desc or "")
    function row:Measure()
        local h = 8 + W.TextHeight(self.text)
        if desc then h = h + 3 + W.TextHeight(self.desc) end
        self:SetHeight(math.max(34, h + 8))
    end
    function row:Update()
        local on = get() and true or false
        W.Color(track, on and C.accent or C.off)
        knob:ClearAllPoints()
        knob:SetPoint("CENTER", pill, on and "RIGHT" or "LEFT", on and -7 or 7, 0)
        self.text:SetTextColor(on and C.text[1] or C.muted[1], on and C.text[2] or C.muted[2],
            on and C.text[3] or C.muted[3])
    end
    row:SetScript("OnClick", function(self)
        set(not get())
        self:Update()
    end)
    row:SetScript("OnEnter", function() W.Color(bg, C.surfaceHover) end)
    row:SetScript("OnLeave", function() W.Color(bg, C.surface) end)
    row:Update()
    return row
end

-- no mouse wheel on purpose: it scrolls the page instead
function W.Slider(parent, label, minV, maxV, step, get, set, fmtValue)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(50)
    surface(row)
    row.text = W.Text(row, "GameFontHighlight", C.text)
    row.text:SetPoint("TOPLEFT", 12, -8)
    row.text:SetText(label)
    row.value = W.Text(row, "GameFontHighlightSmall", C.accent)
    row.value:SetPoint("TOPRIGHT", -12, -9)
    row.value:SetJustifyH("RIGHT")

    local s = CreateFrame("Slider", nil, row)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("BOTTOMLEFT", 12, 7)
    s:SetPoint("BOTTOMRIGHT", -12, 7)
    s:SetHeight(14)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:EnableMouse(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    W.Color(track, C.off)
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT")
    fill:SetHeight(4)
    W.Color(fill, C.accent)
    s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = s:GetThumbTexture()
    if thumb then
        thumb:SetSize(8, 14)
        thumb:SetVertexColor(1, 1, 1)
        thumb:SetDrawLayer("OVERLAY")
    end
    local function show(v)
        row.value:SetText(fmtValue and fmtValue(v) or tostring(v))
        local w = s:GetWidth()
        if w and w > 0 then
            fill:SetWidth(math.max(1, (v - minV) / (maxV - minV) * w))
        end
    end
    s:SetScript("OnValueChanged", function(_, v, userInput)
        v = math.floor(v / step + 0.5) * step
        show(v)
        if userInput then set(v) end
    end)
    s:SetScript("OnSizeChanged", function() show(s:GetValue()) end)
    function row:Update()
        local v = get()
        s:SetValue(v)
        show(v)
    end
    row.slider = s
    row:Update()
    return row
end

function W.Section(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(22)
    local t = W.Text(f, "GameFontNormalSmall", C.accent)
    t:SetPoint("LEFT", 0, 0)
    t:SetWordWrap(false)
    t:SetText(text)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("LEFT", t, "RIGHT", 8, 0)
    line:SetPoint("RIGHT")
    line:SetHeight(1)
    W.Color(line, C.border)
    return f
end

function W.ActionRow(parent, width, label, desc)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(42)
    surface(row)
    row.text = W.Text(row, "GameFontHighlight", C.text)
    row.text:SetPoint("TOPLEFT", 12, -8)
    row.text:SetWordWrap(false)
    row.text:SetText(label)
    row.desc = W.Text(row, "GameFontHighlightSmall", C.muted)
    row.desc:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -3)
    row.desc:SetText(desc or "")
    local room = 0
    function row:AddButton(b)
        b:SetPoint("RIGHT", self, "RIGHT", -12 - room, 0)
        room = room + b:GetWidth() + 6
        return b
    end
    function row:Measure()
        local w = width - 24 - room
        self.text:SetWidth(w)
        self.desc:SetWidth(w)
        local h = 8 + W.TextHeight(self.text)
        if (self.desc:GetText() or "") ~= "" then h = h + 3 + W.TextHeight(self.desc) end
        self:SetHeight(math.max(38, h + 8))
    end
    return row
end

function W.ButtonRow(parent, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height or 38)
    surface(row)
    local x = 12
    function row:AddButton(b)
        b:SetPoint("LEFT", self, "LEFT", x, 0)
        x = x + b:GetWidth() + 6
        return b
    end
    return row
end

-- a line is a string, or { left, right } for two columns
function W.TextBlock(parent, width, leftColumn)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(20)
    surface(f)
    local left, right = {}, {}
    local PAD_X, PAD_Y, GAP = 12, 8, 3
    f.lines = {}
    function f:SetLines(lines)
        self.lines = lines
        for i, line in ipairs(lines) do
            left[i] = left[i] or W.Text(self, "GameFontHighlightSmall", C.text)
            right[i] = right[i] or W.Text(self, "GameFontHighlightSmall", C.muted)
            local two = type(line) == "table"
            left[i]:SetWidth(two and (leftColumn or 150) or (width - 2 * PAD_X))
            left[i]:SetText(two and line[1] or line)
            left[i]:Show()
            right[i]:SetShown(two)
            if two then
                right[i]:SetWidth(width - 2 * PAD_X - (leftColumn or 150) - 8)
                right[i]:SetText(line[2])
            end
        end
        for i = #lines + 1, #left do
            left[i]:Hide()
            right[i]:Hide()
        end
        self:Measure()
    end
    function f:Measure()
        local y = -PAD_Y
        for i, line in ipairs(self.lines) do
            left[i]:ClearAllPoints()
            left[i]:SetPoint("TOPLEFT", PAD_X, y)
            local h = W.TextHeight(left[i])
            if type(line) == "table" then
                right[i]:ClearAllPoints()
                right[i]:SetPoint("TOPLEFT", PAD_X + (leftColumn or 150) + 8, y)
                h = math.max(h, W.TextHeight(right[i]))
            end
            y = y - h - GAP
        end
        self:SetHeight(-y + PAD_Y - GAP)
    end
    return f
end

function W.Input(parent, width, height, placeholder, onChange, onEnter)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetAutoFocus(false)
    box:SetSize(width, height or 24)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetTextColor(C.text[1], C.text[2], C.text[3])
    box:SetShadowOffset(0, 0)
    box:SetTextInsets(8, 8, 0, 0)
    box:SetMaxLetters(80)
    W.Color(W.Box(box, 6, true), C.header)
    W.BorderColor(box, C.border)
    local hint = W.Text(box, "GameFontHighlightSmall", C.muted)
    hint:SetPoint("LEFT", 8, 0)
    hint:SetWordWrap(false)
    hint:SetText(placeholder or "")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onEnter then onEnter(self:GetText()) end
    end)
    box:SetScript("OnEditFocusGained", function(self) W.BorderColor(self, C.accent) end)
    box:SetScript("OnEditFocusLost", function(self) W.BorderColor(self, C.border) end)
    box:SetScript("OnHide", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        hint:SetShown(text == "")
        if onChange then onChange(text) end
    end)
    return box
end

-- Scrolling

local function slimBar(parent, onChange)
    local bar = CreateFrame("Button", nil, parent)
    bar:SetWidth(6)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    W.Color(track, C.header)
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(6)
    local tex = thumb:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    W.Color(tex, C.off)
    local value, maxValue, share = 0, 0, 1

    local function thumbHeight()
        return math.max(18, (bar:GetHeight() or 0) * share)
    end
    local function place()
        local room = (bar:GetHeight() or 0) - thumbHeight()
        thumb:SetHeight(thumbHeight())
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, maxValue > 0 and -room * value / maxValue or 0)
    end
    -- viewShare: how much of the content fits (0-1)
    function bar:SetState(v, m, viewShare)
        value, maxValue, share = v, m, math.min(1, viewShare or 1)
        self:SetShown(m > 0)
        place()
    end
    bar:SetScript("OnSizeChanged", place)

    local dragY, dragValue
    local function stopDrag()
        dragY = nil
        thumb:SetScript("OnUpdate", nil)
        W.Color(tex, C.off)
    end
    thumb:SetScript("OnEnter", function() W.Color(tex, C.muted) end)
    thumb:SetScript("OnLeave", function() if not dragY then W.Color(tex, C.off) end end)
    thumb:SetScript("OnMouseDown", function()
        local _, y = GetCursorPosition()
        dragY, dragValue = y / bar:GetEffectiveScale(), value
        thumb:SetScript("OnUpdate", function()
            local _, now = GetCursorPosition()
            local room = (bar:GetHeight() or 0) - thumbHeight()
            if room > 0 then onChange(dragValue + (dragY - now / bar:GetEffectiveScale()) * maxValue / room) end
        end)
    end)
    thumb:SetScript("OnMouseUp", stopDrag)
    thumb:SetScript("OnHide", stopDrag)
    bar:SetScript("OnClick", function()
        local _, y = GetCursorPosition()
        local top = bar:GetTop()
        local room = (bar:GetHeight() or 0) - thumbHeight()
        if top and room > 0 then
            onChange((top - y / bar:GetEffectiveScale() - thumbHeight() / 2) * maxValue / room)
        end
    end)
    return bar
end

local WHEEL_STEP = 48

-- caller places sf.bar, sizes sf.child and calls sf:Sync() when its height changes
function W.ScrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    sf.child = child
    sf.bar = slimBar(parent, function(v) sf:ScrollTo(v) end)

    local function range()
        return math.max(0, (child:GetHeight() or 0) - (sf:GetHeight() or 0))
    end
    function sf:ScrollTo(v)
        self:SetVerticalScroll(math.floor(math.max(0, math.min(range(), v)) + 0.5))
        self:Sync()
    end
    -- also clamps the scroll when the content got shorter
    function sf:Sync()
        local max = range()
        local v = self:GetVerticalScroll() or 0
        if v > max then
            v = max
            self:SetVerticalScroll(v)
        end
        local h = child:GetHeight() or 0
        self.bar:SetState(v, max, h > 0 and (self:GetHeight() or 0) / h or 1)
    end
    function sf:Wheel(delta)
        self:ScrollTo((self:GetVerticalScroll() or 0) - delta * WHEEL_STEP)
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta) self:Wheel(delta) end)
    sf:SetScript("OnSizeChanged", function(self) self:Sync() end)
    return sf
end

-- rows are reused. opts: fixed (always maxRows tall), empty (text), onLimit(delta) for the wheel past the end
function W.List(parent, width, rowHeight, maxRows, createRow, fillRow, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    surface(f)
    f.items, f.offset = {}, 0
    local rows = {}
    local bar
    local empty = W.Text(f, "GameFontHighlightSmall", C.muted)
    empty:SetPoint("TOPLEFT", 12, -8)
    empty:SetText(opts.empty or "")

    local function maxOffset() return math.max(0, #f.items - maxRows) end

    function f:Render()
        self.offset = math.max(0, math.min(self.offset, maxOffset()))
        for i = 1, maxRows do
            local item = self.items[self.offset + i]
            local row = rows[i]
            if item and not row then
                row = CreateFrame("Frame", nil, self)
                row:SetSize(width - 14, rowHeight)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
                local line = row:CreateTexture(nil, "BORDER")
                line:SetPoint("BOTTOMLEFT", 10, 0)
                line:SetPoint("BOTTOMRIGHT", -2, 0)
                line:SetHeight(1)
                W.Color(line, C.border, 0.45)
                createRow(row)
                rows[i] = row
            end
            if row then
                row:SetShown(item ~= nil)
                if item then fillRow(row, item) end
            end
        end
        empty:SetShown(#self.items == 0)
        local shown = opts.fixed and maxRows or math.max(1, math.min(maxRows, #self.items))
        self:SetHeight(shown * rowHeight)
        bar:SetState(self.offset, maxOffset(), maxRows / math.max(maxRows, #self.items))
    end
    function f:SetItems(items)
        self.items = items
        self:Render()
    end
    local function scrollTo(v)
        f.offset = math.floor(v + 0.5)
        f:Render()
    end
    bar = slimBar(f, scrollTo)
    bar:SetPoint("TOPRIGHT", -4, -2)
    bar:SetPoint("BOTTOMRIGHT", -4, 2)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        local v = math.max(0, math.min(maxOffset(), f.offset - delta))
        if v == f.offset then
            if opts.onLimit then opts.onLimit(delta) end
        else
            scrollTo(v)
        end
    end)
    f:SetHeight(rowHeight)
    return f
end

-- Guide window parts

-- def = { icon, color = {r, g, b}, onClick(button), tooltip(tip) }
function W.ActionBar(parent, def, height)
    local bar = CreateFrame("Button", nil, parent)
    bar:SetHeight(height or 22)
    bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local bg = W.Box(bar, 6, true)
    W.Color(bg, def.color, 0.12)
    W.BorderColor(bar, def.color, 0.55)
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 7, 0)
    icon:SetTexture(def.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local chevron = W.Text(bar, "GameFontHighlightSmall", C.muted)
    chevron:SetPoint("RIGHT", -6, 0)
    chevron:SetText(">")
    bar.text = W.Text(bar, "GameFontHighlightSmall", C.text)
    bar.text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    bar.text:SetPoint("RIGHT", chevron, "LEFT", -4, 0)
    bar.text:SetWordWrap(false)
    bar:SetScript("OnClick", function(_, button) def.onClick(button) end)
    bar:SetScript("OnEnter", function(self)
        W.Color(bg, def.color, 0.25)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        def.tooltip(GameTooltip)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function()
        W.Color(bg, def.color, 0.12)
        GameTooltip:Hide()
    end)
    return bar
end

-- the mark is a texture, the game font has no check mark
function W.CheckBox(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local bg = W.Box(f, 4, true)
    local mark = f:CreateTexture(nil, "OVERLAY")
    mark:SetSize(size + 6, size + 6)
    mark:SetPoint("CENTER")
    mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    mark:SetDesaturated(true)
    mark:SetVertexColor(C.good[1], C.good[2], C.good[3])
    function f:SetChecked(on)
        mark:SetShown(on)
        W.Color(bg, on and C.good or C.off, on and 0.25 or 0.4)
        W.BorderColor(self, on and C.good or C.muted, 0.8)
    end
    f:SetChecked(false)
    return f
end

-- short: used in the Up Next list. shape: the mark in front of "then ..." lines
local STEP_STYLES = {
    accept = { color = { 0.55, 0.36, 0.08 }, label = "Accept quest", short = "Accept", shape = "ring" },
    complete = { color = { 0.60, 0.27, 0.10 }, label = "Complete objectives", short = "Do", shape = "diamond" },
    turnin = { color = { 0.25, 0.42, 0.18 }, label = "Turn in", short = "Turn in", shape = "circle" },
    train = { color = { 0.36, 0.22, 0.48 }, label = "Train", short = "Train", shape = "diamond" },
    getfp = { color = { 0.18, 0.36, 0.48 }, label = "Flight path", short = "Flight path", shape = "square" },
    fly = { color = { 0.18, 0.36, 0.48 }, label = "Fly", short = "Fly", shape = "square" },
    sethearth = { color = { 0.16, 0.40, 0.36 }, label = "Set hearthstone", short = "Hearth", shape = "square" },
    hearth = { color = { 0.16, 0.40, 0.36 }, label = "Use hearthstone", short = "Hearth", shape = "square" },
    level = { color = { 0.55, 0.16, 0.20 }, label = "Level up", short = "Level", shape = "diamond" },
    go = { color = { 0.24, 0.30, 0.45 }, label = "Travel", short = "Go", shape = "square" },
    note = { color = { 0.40, 0.34, 0.26 }, label = "Note", short = "Note", shape = "ring" },
}
for _, style in pairs(STEP_STYLES) do style.base = { unpack(style.color) } end

-- set before any frame is made, a change shows after a reload
function W.SetTheme(name)
    local dark = name ~= "light"
    for k, c in pairs(THEMES[dark and "dark" or "light"]) do C[k] = c end
    inked = not dark
    -- step colours are ink on parchment, lighter on leather
    for _, style in pairs(STEP_STYLES) do
        for i = 1, 3 do
            local v = style.base[i]
            style.color[i] = dark and v + (1 - v) * 0.4 or v
        end
        style.hex = W.Hex(style.color)
    end
end
W.SetTheme("dark")

function W.StepStyle(stepType)
    return STEP_STYLES[stepType] or STEP_STYLES.note
end

-- { atlas, fallback texture }: not every client has the atlas
local TYPE_ICON = {
    accept = { "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon" },
    turnin = { "QuestTurnin", "Interface\\GossipFrame\\ActiveQuestIcon" },
    complete = { nil, "Interface\\Icons\\INV_Sword_04" },
    level = { nil, "Interface\\Icons\\INV_Sword_04" },
    train = { nil, "Interface\\Icons\\INV_Misc_Book_09" },
    getfp = { "FlightMaster", "Interface\\TaxiFrame\\UI-Taxi-Icon-Green" },
    fly = { "FlightMaster", "Interface\\TaxiFrame\\UI-Taxi-Icon-Green" },
    sethearth = { nil, "Interface\\Icons\\INV_Misc_Rune_01" },
    hearth = { nil, "Interface\\Icons\\INV_Misc_Rune_01" },
    go = { nil, "Interface\\Icons\\INV_Misc_Map_01" },
    note = { nil, "Interface\\Icons\\INV_Misc_Note_01" },
}

-- the step type's coloured mark: ring, circle, diamond or square
function W.SetShape(tex, stepType)
    local style = W.StepStyle(stepType)
    tex:SetTexture(MEDIA .. "shape_" .. style.shape .. ".tga")
    tex:SetVertexColor(style.color[1], style.color[2], style.color[3])
end

-- a thin rounded bar, SetValue takes 0-1
function W.Progress(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height)
    W.Color(W.Pill(f, "circle"), C.off, 0.6)
    local fill = CreateFrame("Frame", nil, f)
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetSize(height, height)
    W.PillAcross(W.Pill(fill, "circle", "ARTWORK"), C.accent, C.gold)
    local value = 0
    function f:SetValue(v)
        value = v
        local w = f:GetWidth() or 0
        fill:SetShown(v > 0 and w > 0)
        fill:SetWidth(math.max(height, w * math.min(1, v)))
    end
    -- the width is 0 until the window is laid out
    f:SetScript("OnSizeChanged", function() f:SetValue(value) end)
    return f
end

-- the game refuses tex coords on a masked texture, the mask hides the icon edge anyway
local function crop(tex, inset)
    if not tex.masked then tex:SetTexCoord(inset, 1 - inset, inset, 1 - inset) end
end

function W.SetStepIcon(tex, stepType)
    local e = TYPE_ICON[stepType] or TYPE_ICON.note
    local atlas = e[1]
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
        crop(tex, 0)
        return
    end
    tex:SetTexture(e[2])
    crop(tex, e[2]:find("Icons") and 0.08 or 0)
end
