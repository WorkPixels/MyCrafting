-- Core.lua: Addon lifecycle, events, bank caching, merchant integration, and slash commands.
local ADDON_NAME, NS = ...

local C = NS.Compat
local V = NS.VendorDB
local Q = NS.Queue
local UI = NS.UI

-- Default database settings
local DEFAULT_DB = {
    favorites = {},
    queue = {},
    bankInventory = {},
    options = {
        sidePanelOpen = true,
        autoBuyVendor = false,
        showSkillBar = true,
        showGatheringTooltips = true,
        showReagentTooltips = true,
        showBankCounts = true,
        playQueueSound = true,
    },
}

-- Event listener frame
local eventFrame = CreateFrame("Frame", "MyCraftingEventFrame")

-- ---------------------------------------------------------------------------
-- Bank Scanning & Cache
-- ---------------------------------------------------------------------------
local function ScanBankInventory()
    if not _G.MyCraftingDB then return end
    local bankDB = _G.MyCraftingDB.bankInventory or {}
    wipe(bankDB)

    -- Bank container IDs:
    -- -1: Main bank container
    -- Bank bag slots in Classic / Forever: 5, 6, 7, 8, 9, 10, 11 (or BANK_CONTAINER)
    local bankBags = { -1, 5, 6, 7, 8, 9, 10, 11 }
    for _, bagID in ipairs(bankBags) do
        local numSlots = C.GetNumBagSlots(bagID)
        for slot = 1, numSlots do
            local itemInfo = C.GetContainerItemInfo(bagID, slot)
            if itemInfo and itemInfo.itemID then
                local id = itemInfo.itemID
                local count = itemInfo.count or 1
                bankDB[id] = (bankDB[id] or 0) + count
            end
        end
    end

    _G.MyCraftingDB.bankInventory = bankDB
end

-- ---------------------------------------------------------------------------
-- Merchant Auto-Buy Check
-- ---------------------------------------------------------------------------
local function CheckMerchantAutoBuy()
    if not _G.MyCraftingDB or not _G.MyCraftingDB.options or not _G.MyCraftingDB.options.autoBuyVendor then
        return
    end

    local shoppingList = Q.GetShoppingList()
    local matches, totalCost = V.ScanMerchantForShoppingList(shoppingList)
    if #matches > 0 then
        local count = V.BuyItems(matches)
        if count > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99MyCrafting:|r Auto-purchased %d shopping list reagent(s) for %s.", count, C.FormatMoney(totalCost)))
            if UI.Elements.mainFrame and UI.Elements.mainFrame:IsShown() then
                UI.UpdateRightPanel()
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Safe Event Registration (wraps in pcall for cross-version compatibility)
-- ---------------------------------------------------------------------------
local function SafeRegisterEvent(frame, eventName)
    pcall(frame.RegisterEvent, frame, eventName)
end

local function SafeRegisterUnitEvent(frame, eventName, unit)
    if frame.RegisterUnitEvent then
        local ok = pcall(frame.RegisterUnitEvent, frame, eventName, unit)
        if ok then return end
    end
    SafeRegisterEvent(frame, eventName)
end

local EVENTS_TO_REGISTER = {
    "ADDON_LOADED",
    "TRADE_SKILL_SHOW",
    "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "TRADE_SKILL_CLOSE",
    "CRAFT_SHOW",
    "CRAFT_CLOSE",
    "BANKFRAME_OPENED",
    "MERCHANT_SHOW",
    "BAG_UPDATE_DELAYED",
    "BAG_UPDATE",
    "TRADE_SKILL_DETAILS_UPDATE",
}

for _, evt in ipairs(EVENTS_TO_REGISTER) do
    SafeRegisterEvent(eventFrame, evt)
end

SafeRegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
SafeRegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_FAILED", "player")
SafeRegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_INTERRUPTED", "player")

local function HookFrameOnShow(frame)
    if not frame or frame.MyCraftingShowHooked then return end
    frame.MyCraftingShowHooked = true

    UI.MakeFrameMovable(frame)

    frame:HookScript("OnShow", function(self)
        UI.AttachToDefaultFrame(self)
    end)
    frame:HookScript("OnHide", function()
        if not Q.IsRunning() then
            UI.HideSidePanel()
        end
    end)

    if frame:IsShown() then
        UI.AttachToDefaultFrame(frame)
    end
end

local function CheckAndHookAllFrames()
    if _G.ProfessionsFrame then HookFrameOnShow(_G.ProfessionsFrame) end
    if _G.TradeSkillFrame then HookFrameOnShow(_G.TradeSkillFrame) end
    if _G.CraftFrame then HookFrameOnShow(_G.CraftFrame) end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            -- Init DB
            if not _G.MyCraftingDB then
                _G.MyCraftingDB = CopyTable(DEFAULT_DB)
            else
                for k, v in pairs(DEFAULT_DB) do
                    if _G.MyCraftingDB[k] == nil then
                        _G.MyCraftingDB[k] = type(v) == "table" and CopyTable(v) or v
                    end
                end
                for optKey, optVal in pairs(DEFAULT_DB.options) do
                    if _G.MyCraftingDB.options[optKey] == nil then
                        _G.MyCraftingDB.options[optKey] = optVal
                    end
                end
            end

            Q.Init(_G.MyCraftingDB.queue)
            CheckAndHookAllFrames()
            if NS.GatheringDB and NS.GatheringDB.HookTooltip then
                NS.GatheringDB.HookTooltip()
            end
            if NS.Options and NS.Options.RegisterBlizzardPanel then
                NS.Options.RegisterBlizzardPanel()
            end

            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting v1.0.0|r loaded. Enhancing default crafting interface.")
        elseif name == "Blizzard_Professions" or name == "Blizzard_TradeSkillUI" or name == "Blizzard_CraftUI" then
            CheckAndHookAllFrames()
        end

    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" or event == "CRAFT_SHOW" then
        CheckAndHookAllFrames()
        local parent = _G.ProfessionsFrame or _G.TradeSkillFrame or _G.CraftFrame
        if parent and parent:IsShown() then
            UI.AttachToDefaultFrame(parent)
        end

    elseif event == "TRADE_SKILL_DETAILS_UPDATE" then
        local parent = _G.ProfessionsFrame or _G.TradeSkillFrame or _G.CraftFrame
        if parent and parent:IsShown() then
            UI.CreateOrUpdateSkillBar(parent)
        end

    elseif event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
        if not Q.IsRunning() then
            UI.HideSidePanel()
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellID = ...
        if unit == "player" then
            local spellName = C.GetSpellName(spellID)
            Q.OnCraftSucceeded(spellName)
            UI.Refresh()
        end

    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit = ...
        if unit == "player" then
            Q.OnCraftFailed()
        end

    elseif event == "BANKFRAME_OPENED" then
        ScanBankInventory()

    elseif event == "MERCHANT_SHOW" then
        CheckMerchantAutoBuy()

    elseif event == "BAG_UPDATE_DELAYED" then
        UI.Refresh()
    end
end)

-- ---------------------------------------------------------------------------
-- Slash Commands
-- ---------------------------------------------------------------------------
_G.SLASH_MYCRAFTING1 = "/mycrafting"
_G.SLASH_MYCRAFTING2 = "/mc"

local function PrintHelp()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting Commands:|r")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/mc|r - Toggle MyCrafting side panel on the profession window")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/mc config|r - Open the graphical Options window")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/mc queue|r - Show current queue status")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/mc shop|r - Print shopping list to chat")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/mc clear|r - Clear crafting queue")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/mc autobuy [on|off]|r - Toggle auto-buy vendor reagents at merchants")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/mc reset|r - Reset window and side panel positions")
end

_G.SlashCmdList["MYCRAFTING"] = function(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    arg = (arg or ""):lower()

    if cmd == "" then
        UI.Toggle()
    elseif cmd == "config" or cmd == "options" or cmd == "opt" then
        if NS.Options and NS.Options.Toggle then
            NS.Options.Toggle()
        end
    elseif cmd == "queue" then
        local qList = Q.GetList()
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99MyCrafting Queue:|r %d item(s) queued.", #qList))
        for i, item in ipairs(qList) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  [%d] %dx %s", i, item.count, item.name))
        end
    elseif cmd == "shop" then
        Q.ShareToChat("SELF")
    elseif cmd == "clear" then
        Q.Clear()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Crafting queue cleared.")
    elseif cmd == "autobuy" then
        if arg == "on" then
            _G.MyCraftingDB.options.autoBuyVendor = true
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Vendor auto-buy enabled.")
        elseif arg == "off" then
            _G.MyCraftingDB.options.autoBuyVendor = false
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Vendor auto-buy disabled.")
        else
            local curr = _G.MyCraftingDB.options.autoBuyVendor
            _G.MyCraftingDB.options.autoBuyVendor = not curr
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99MyCrafting:|r Vendor auto-buy is now %s.", _G.MyCraftingDB.options.autoBuyVendor and "|cff00ff00ON|r" or "|cffff2020OFF|r"))
        end
    elseif cmd == "autoopen" then
        if arg == "on" then
            _G.MyCraftingDB.options.autoOpen = true
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Auto-open enabled.")
        elseif arg == "off" then
            _G.MyCraftingDB.options.autoOpen = false
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Auto-open disabled.")
        else
            local curr = _G.MyCraftingDB.options.autoOpen
            _G.MyCraftingDB.options.autoOpen = not curr
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99MyCrafting:|r Auto-open is now %s.", _G.MyCraftingDB.options.autoOpen and "|cff00ff00ON|r" or "|cffff2020OFF|r"))
        end
    elseif cmd == "reset" then
        if _G.MyCraftingDB then
            _G.MyCraftingDB.sidePanelPos = nil
            _G.MyCraftingDB.options.sidePanelOpen = true
        end
        local parent = _G.ProfessionsFrame or _G.TradeSkillFrame or _G.CraftFrame
        if parent then
            parent:ClearAllPoints()
            parent:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            UI.PositionSidePanel(parent)
            local panel = UI.GetSidePanel(parent)
            panel:Show()
            UI.Refresh()
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Window and side panel position reset.")
    else
        PrintHelp()
    end
end
