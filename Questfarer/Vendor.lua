-- Sells grays and repairs at vendors (Shift skips), warns when bags or quest log are nearly full.

local _, ns = ...
local QF = ns.QF

local V = {}
QF.Vendor = V

local BAG_WARN = 2      -- free slots left
local LOG_WARN = 1      -- free quest log slots left
local SELL_DELAY = 0.2  -- seconds, so the server keeps up
local QUEST_ITEM_CLASS = 12

local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function junkInBags()
    local list, total = {}, 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == 0 and not info.hasNoValue and not info.isLocked then
                local price = select(11, getItemInfo(info.itemID))
                local classID = select(12, getItemInfo(info.itemID))
                if price and price > 0 and classID ~= QUEST_ITEM_CLASS then
                    table.insert(list, { bag = bag, slot = slot, id = info.itemID })
                    total = total + price * (info.stackCount or 1)
                end
            end
        end
    end
    return list, total
end

-- onDone runs after the last sale so repairs can use the money
function V:SellJunk(onDone)
    local list, total = junkInBags()
    if #list == 0 then
        onDone()
        return
    end
    self.selling = true
    local i = 0
    local function nextSale()
        if not self.selling or not (MerchantFrame and MerchantFrame:IsShown()) then return end
        i = i + 1
        local item = list[i]
        if not item then
            self.selling = false
            QF:Print(("Sold %d gray item%s for %s."):format(#list, #list == 1 and "" or "s", QF:FormatMoney(total)))
            C_Timer.After(0.5, onDone) -- the money arrives a moment after the last sale
            return
        end
        local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
        if info and info.itemID == item.id then C_Container.UseContainerItem(item.bag, item.slot) end
        C_Timer.After(SELL_DELAY, nextSale)
    end
    nextSale()
end

function V:Repair()
    if not (CanMerchantRepair and CanMerchantRepair()) then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end
    if GetMoney() < cost then
        QF:Print(("Repairs cost %s, and you don't have that much."):format(QF:FormatMoney(cost)))
        return
    end
    RepairAllItems()
    QF:Print("Repaired everything for " .. QF:FormatMoney(cost) .. ".")
end

QF:On("MERCHANT_SHOW", function(self)
    if IsShiftKeyDown() then return end
    local function repair()
        if self.db.autoRepair and MerchantFrame and MerchantFrame:IsShown() then V:Repair() end
    end
    if self.db.autoSell then V:SellJunk(repair) else repair() end
end)

QF:On("MERCHANT_CLOSED", function() V.selling = false end)

local function freeBagSlots()
    local free = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n, family = C_Container.GetContainerNumFreeSlots(bag)
        if family == 0 then free = free + (n or 0) end
    end
    return free
end

local function questLogCount()
    local n = 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden then n = n + 1 end
    end
    local max = (C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or MAX_QUESTLOG_QUESTS or 20
    return n, max
end

function V:Check()
    self.bagsFree = freeBagSlots()
    self.logCount, self.logMax = questLogCount()
    QF:RequestUpdate()
end

local function bagsFull() return V.bagsFree and V.bagsFree <= BAG_WARN end
local function logFull() return V.logCount and V.logMax - V.logCount <= LOG_WARN end

QF:AddBar({
    icon = "Interface\\Icons\\INV_Misc_Bag_08",
    color = { 0.72, 0.36, 0.16 },
    text = function()
        if not QF.db.fullWarning then return nil end
        local parts = {}
        if bagsFull() then
            table.insert(parts, V.bagsFree == 0 and "Your bags are full" or ("Bags: " .. V.bagsFree .. " free"))
        end
        if logFull() then table.insert(parts, ("Quest log: %d/%d"):format(V.logCount, V.logMax)) end
        return #parts > 0 and ("|cffffffff" .. table.concat(parts, "   ") .. "|r") or nil
    end,
    onClick = function()
        if logFull() and not bagsFull() then ToggleQuestLog() else ToggleAllBags() end
    end,
    tooltip = function(tip)
        tip:AddLine("Running out of room", 1, 1, 1)
        if bagsFull() then tip:AddLine("Sell or destroy something so you can loot quest items.", 0.85, 0.85, 0.87, true) end
        if logFull() then tip:AddLine("A full quest log stops the guide from accepting quests.", 0.85, 0.85, 0.87, true) end
    end,
})

QF:On("PLAYER_LOGIN", function() C_Timer.After(2, function() V:Check() end) end)
QF:On("BAG_UPDATE_DELAYED", function() V:Check() end)
QF:On("QUEST_LOG_UPDATE", function()
    if V.checkQueued then return end
    V.checkQueued = true
    C_Timer.After(1, function()
        V.checkQueued = false
        V:Check()
    end)
end)
