-- Questfarer - marks the quest reward that sells for the most

local _, ns = ...
local QF = ns.QF

local Rewards = {}
QF.Rewards = Rewards

local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- { {index, link, price, count} }, or nil while item data loads
local function choiceValues()
    local n = GetNumQuestChoices() or 0
    local out = {}
    for i = 1, n do
        local link = GetQuestItemLink("choice", i)
        if not link then return nil end
        local sell = select(11, getItemInfo(link))
        if sell == nil then return nil end
        local count = select(3, GetQuestItemInfo("choice", i)) or 1
        table.insert(out, { index = i, link = link, price = sell * math.max(1, count), count = count })
    end
    return out
end

-- reward buttons can be named, pooled or anonymous depending on the client
local function choiceButton(index)
    local frame = _G.QuestInfoRewardsFrame
    local candidates = {}
    if frame and frame.RewardButtons then
        for _, b in ipairs(frame.RewardButtons) do table.insert(candidates, b) end
    end
    if frame and frame.GetChildren then
        for _, b in ipairs({ frame:GetChildren() }) do table.insert(candidates, b) end
    end
    for _, b in ipairs(candidates) do
        if b.type == "choice" and b.GetID and b:GetID() == index and b:IsShown() then return b end
    end
    -- older layout: choices are the first numbered item buttons
    local b = _G["QuestInfoRewardsFrameQuestInfoItem" .. index]
    if b and b:IsShown() then return b end
    return nil
end

Rewards.ChoiceButton = choiceButton

local function marker(btn)
    if btn.fgBestMarker then return btn.fgBestMarker end
    local m = CreateFrame("Frame", nil, btn)
    m:SetFrameLevel(btn:GetFrameLevel() + 5)
    local anchor = btn.Icon or btn.icon or _G[(btn:GetName() or "") .. "IconTexture"] or btn
    m:SetAllPoints(anchor)
    local coin = m:CreateTexture(nil, "OVERLAY")
    coin:SetSize(16, 16)
    coin:SetPoint("TOPRIGHT", 5, 5)
    coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    local glow = m:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", 2, -2)
    glow:SetColorTexture(1, 0.82, 0, 0.25)
    btn:HookScript("OnEnter", function()
        if m:IsShown() and m.price then
            GameTooltip:AddLine("Questfarer: sells for the most (" .. QF:FormatMoney(m.price) .. ")", 1, 0.82, 0)
            GameTooltip:Show()
        end
    end)
    btn.fgBestMarker = m
    return m
end

function Rewards:Clear()
    for _, m in ipairs(self.shown or {}) do m:Hide() end
    self.shown = {}
end

function Rewards:Mark(tries)
    self:Clear()
    if not QF.db.rewardHint then return end
    if (GetNumQuestChoices() or 0) < 2 then return end
    local values = choiceValues()
    if not values then
        -- item data not cached yet
        if (tries or 0) < 10 then
            C_Timer.After(0.25, function() Rewards:Mark((tries or 0) + 1) end)
        end
        return
    end
    local best
    for _, v in ipairs(values) do
        if v.price > 0 and (not best or v.price > best.price) then best = v end
    end
    if not best then
        QF:Print("None of the reward choices can be sold to a vendor - pick the one you can use.")
        return
    end
    local btn = choiceButton(best.index)
    if btn then
        local m = marker(btn)
        m.price = best.price
        m:Show()
        table.insert(self.shown, m)
    end
    local each = best.count > 1 and (" for " .. best.count) or ""
    QF:Print(("Best vendor price: %s - %s%s. Pick it unless another reward is an upgrade for you.")
        :format(best.link, QF:FormatMoney(best.price), each))
end

QF:On("QUEST_COMPLETE", function()
    -- wait for the reward buttons to exist
    C_Timer.After(0.1, function() Rewards:Mark(0) end)
end)

QF:On("QUEST_FINISHED", function()
    Rewards:Clear()
end)
