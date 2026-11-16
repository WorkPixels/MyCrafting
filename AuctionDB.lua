-- AuctionDB.lua: Caches Auction House prices, integrates Auctionator/TSM if present,
-- and calculates per-craft reagent cost and vendor/AH profit.
local ADDON_NAME, NS = ...
local A = {}
NS.AuctionDB = A

local C = NS.Compat
local V = NS.VendorDB

local scanActive = false
local scanTimeoutTimer = nil
local scanRetryTimer = nil
local scanQueue = {}
local scanIndex = 0
local scanButton = nil
local stepScanFn = nil

local function GetAHTable()
    if not _G.MyCraftingDB then return nil end
    _G.MyCraftingDB.ahPrices = _G.MyCraftingDB.ahPrices or {}
    return _G.MyCraftingDB.ahPrices
end

function A.RecordPrice(itemID, priceCopper)
    if not itemID or not priceCopper or priceCopper <= 0 then return end
    local db = GetAHTable()
    if not db then return end
    db[itemID] = {
        price = math.floor(priceCopper),
        seen = _G.time and _G.time() or 0,
    }
end

function A.GetPriceCount()
    local db = GetAHTable()
    if not db then return 0 end
    local n = 0
    for _ in pairs(db) do
        n = n + 1
    end
    return n
end

-- Returns unitPrice (copper), sourceName, timestamp
function A.GetPrice(itemID)
    if not itemID then return nil, nil, nil end

    -- 1. MyCrafting local AH cache
    local db = GetAHTable()
    local entry = db and db[itemID]
    if entry and entry.price and entry.price > 0 then
        return entry.price, "AH Cache", entry.seen
    end

    -- 2. Auctionator API fallback (if installed)
    if _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1 and _G.Auctionator.API.v1.GetAuctionPriceByItemID then
        local ok, price = pcall(_G.Auctionator.API.v1.GetAuctionPriceByItemID, "MyCrafting", itemID)
        if ok and price and price > 0 then
            return price, "Auctionator", nil
        end
    end

    -- 3. TSM API fallback (if installed)
    if _G.TSM_API and _G.TSM_API.GetCustomPriceValue then
        local ok, price = pcall(_G.TSM_API.GetCustomPriceValue, "DBMinBuyout", "i:" .. tostring(itemID))
        if ok and price and price > 0 then
            return price, "TSM", nil
        end
    end

    -- 4. MyAHSniperDB fallback (if installed)
    if _G.MyAHSniperDB and _G.MyAHSniperDB.realmPrices then
        local realm = _G.GetRealmName and _G.GetRealmName() or ""
        for k, tbl in pairs(_G.MyAHSniperDB.realmPrices) do
            if type(tbl) == "table" and (realm == "" or tostring(k):find(realm, 1, true)) then
                local price = tbl[itemID]
                if price and price > 0 then
                    return price, "MyAHSniper", nil
                end
            end
        end
    end

    return nil, nil, nil
end

-- Returns best unit cost (copper) and source ("Vendor", "AH Cache", "Auctionator", "TSM", or nil)
function A.GetReagentCost(itemID, itemName)
    local isVendor, vendorPrice = V.IsVendorReagent(itemID, itemName)
    local ahPrice, ahSource = A.GetPrice(itemID)

    if isVendor and vendorPrice and vendorPrice > 0 then
        if ahPrice and ahPrice > 0 and ahPrice < vendorPrice then
            return ahPrice, ahSource
        end
        return vendorPrice, "Vendor"
    end

    if ahPrice and ahPrice > 0 then
        return ahPrice, ahSource
    end

    return nil, nil
end

function A.GetVendorSellPrice(itemID)
    if not itemID then return nil end
    if _G.C_Item and _G.C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, sellPrice = pcall(_G.C_Item.GetItemInfo, itemID)
        if ok and sellPrice and sellPrice > 0 then
            return sellPrice
        end
    end
    if _G.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, sellPrice = pcall(_G.GetItemInfo, itemID)
        if ok and sellPrice and sellPrice > 0 then
            return sellPrice
        end
    end
    return nil
end

function A.CalculateRecipeProfit(recipe)
    if not recipe then return nil end

    local totalCost = 0
    local missingCount = 0
    local breakdown = {}

    for _, r in ipairs(recipe.reagents or {}) do
        local rID = r.itemID or r.id or C.GetItemIDFromLink(r.link)
        local need = r.count or r.need or 1
        local unitCost, source = A.GetReagentCost(rID, r.name)
        local lineCost = unitCost and (unitCost * need) or nil
        if lineCost then
            totalCost = totalCost + lineCost
        else
            missingCount = missingCount + 1
        end
        table.insert(breakdown, {
            id = rID,
            name = r.name or ("Item #" .. tostring(rID or "?")),
            need = need,
            unitCost = unitCost,
            lineCost = lineCost,
            source = source,
        })
    end

    local numMade = 1
    if type(recipe.numMade) == "table" then
        numMade = recipe.numMade.min or recipe.numMade.max or 1
    elseif type(recipe.numMade) == "number" and recipe.numMade > 0 then
        numMade = recipe.numMade
    end

    local outputItemID = recipe.outputItemID or recipe.itemID or C.GetItemIDFromLink(recipe.itemLink)
    local unitSell = A.GetVendorSellPrice(outputItemID)
    local vendorValue = unitSell and (unitSell * numMade) or nil
    local vendorProfit = vendorValue and (vendorValue - totalCost) or nil

    local unitAH, ahSource = A.GetPrice(outputItemID)
    local ahValue = unitAH and (unitAH * numMade) or nil
    local ahProfit = ahValue and (ahValue - totalCost) or nil

    return {
        totalCost = totalCost,
        missingCount = missingCount,
        numMade = numMade,
        unitSell = unitSell,
        vendorValue = vendorValue,
        vendorProfit = vendorProfit,
        unitAH = unitAH,
        ahSource = ahSource,
        ahValue = ahValue,
        ahProfit = ahProfit,
        breakdown = breakdown,
    }
end

-- ---------------------------------------------------------------------------
-- Known Reagent Tracking (populated whenever a profession window is opened)
-- ---------------------------------------------------------------------------
function A.CacheProfessionReagents()
    if not _G.MyCraftingDB then return end
    _G.MyCraftingDB.knownReagents = _G.MyCraftingDB.knownReagents or {}
    local reagentsDB = _G.MyCraftingDB.knownReagents

    local recipes = C.GetAllRecipes()
    for _, recipe in ipairs(recipes) do
        for _, r in ipairs(recipe.reagents or {}) do
            local rID = r.itemID or r.id or C.GetItemIDFromLink(r.link)
            if rID and r.name and r.name ~= "" and not r.name:match("^Item %d+$") then
                -- Skip NPC-only vendor items so AH scans focus on AH materials
                local isVendor = V.IsVendorReagent(rID, r.name)
                if not isVendor then
                    reagentsDB[rID] = r.name
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Passive Auction House Result Capture
-- ---------------------------------------------------------------------------
function A.CaptureBrowseResults()
    if not (_G.C_AuctionHouse and _G.C_AuctionHouse.GetBrowseResults) then return 0 end
    local ok, results = pcall(_G.C_AuctionHouse.GetBrowseResults)
    if not ok or type(results) ~= "table" then return 0 end

    local minByID = {}
    for _, res in ipairs(results) do
        local itemID = res.itemKey and res.itemKey.itemID
        local price = res.minPrice
        if itemID and price and price > 0 then
            if not minByID[itemID] or price < minByID[itemID] then
                minByID[itemID] = price
            end
        end
    end

    local count = 0
    for itemID, price in pairs(minByID) do
        A.RecordPrice(itemID, price)
        count = count + 1
    end
    return count
end

function A.CaptureCommodityResults(itemID)
    if not itemID or not (_G.C_AuctionHouse and _G.C_AuctionHouse.GetNumCommoditySearchResults) then return end
    local okNum, num = pcall(_G.C_AuctionHouse.GetNumCommoditySearchResults, itemID)
    if not okNum or not num or num <= 0 then return end

    local okInfo, info = pcall(_G.C_AuctionHouse.GetCommoditySearchResultInfo, itemID, 1)
    if okInfo and info and info.unitPrice and info.unitPrice > 0 then
        A.RecordPrice(itemID, info.unitPrice)
    end
end

function A.CaptureItemResults(itemKey)
    if not itemKey or not itemKey.itemID or not (_G.C_AuctionHouse and _G.C_AuctionHouse.GetNumItemSearchResults) then return end
    local okNum, num = pcall(_G.C_AuctionHouse.GetNumItemSearchResults, itemKey)
    if not okNum or not num or num <= 0 then return end

    local bestUnit = nil
    for i = 1, math.min(num, 20) do
        local okInfo, info = pcall(_G.C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
        if okInfo and info and info.buyoutAmount and info.buyoutAmount > 0 then
            local qty = (info.quantity and info.quantity > 0) and info.quantity or 1
            local unit = math.floor(info.buyoutAmount / qty)
            if unit > 0 and (not bestUnit or unit < bestUnit) then
                bestUnit = unit
            end
        end
    end

    if bestUnit then
        A.RecordPrice(itemKey.itemID, bestUnit)
    end
end

function A.CaptureLegacyList()
    if not (_G.GetNumAuctionItems and _G.GetAuctionItemInfo and _G.GetAuctionItemLink) then return 0 end
    local okNum, numShown = pcall(_G.GetNumAuctionItems, "list")
    if not okNum or not numShown or numShown <= 0 then return 0 end

    local minByID = {}
    for i = 1, numShown do
        local link = _G.GetAuctionItemLink("list", i)
        local itemID = C.GetItemIDFromLink(link)
        if itemID then
            local _, _, count, _, _, _, _, _, _, buyoutPrice = _G.GetAuctionItemInfo("list", i)
            if buyoutPrice and buyoutPrice > 0 then
                local qty = (count and count > 0) and count or 1
                local unit = math.floor(buyoutPrice / qty)
                if unit > 0 and (not minByID[itemID] or unit < minByID[itemID]) then
                    minByID[itemID] = unit
                end
            end
        end
    end

    local count = 0
    for itemID, price in pairs(minByID) do
        A.RecordPrice(itemID, price)
        count = count + 1
    end
    return count
end

-- ---------------------------------------------------------------------------
-- Active Reagent Scan at the Auction House
-- ---------------------------------------------------------------------------
local function IsAHOpen()
    return (_G.AuctionHouseFrame and _G.AuctionHouseFrame:IsShown())
        or (_G.AuctionFrame and _G.AuctionFrame:IsShown())
end

function A.StopScan()
    scanActive = false
    if scanTimeoutTimer then
        scanTimeoutTimer:Cancel()
        scanTimeoutTimer = nil
    end
    if scanRetryTimer then
        scanRetryTimer:Cancel()
        scanRetryTimer = nil
    end
    scanQueue = {}
    scanIndex = 0
    stepScanFn = nil
    if scanButton then
        scanButton:SetText("Scan AH Mats")
    end
end

function A.OnBrowseUpdated()
    local count = A.CaptureBrowseResults()
    if count > 0 and NS.UI and NS.UI.CreateOrUpdateSkillBar then
        local parent = _G.ProfessionsFrame or _G.TradeSkillFrame or _G.CraftFrame
        if parent and parent:IsShown() then
            NS.UI.CreateOrUpdateSkillBar(parent)
        end
    end

    if scanActive and stepScanFn then
        if scanTimeoutTimer then
            scanTimeoutTimer:Cancel()
            scanTimeoutTimer = nil
        end
        if scanRetryTimer then
            scanRetryTimer:Cancel()
            scanRetryTimer = nil
        end
        if _G.C_Timer and _G.C_Timer.NewTimer then
            scanRetryTimer = _G.C_Timer.NewTimer(0.25, stepScanFn)
        end
    end
end

function A.ScanReagents(force)
    if not IsAHOpen() then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Open the Auction House first to scan reagent prices.")
        return
    end

    if scanActive then
        A.StopScan()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r AH reagent scan stopped.")
        return
    end

    local db = GetAHTable() or {}
    local now = _G.time and _G.time() or 0
    local MAX_AGE = 300 -- skip items scanned in the last 5 minutes unless forced

    local targets = {}
    local seenIDs = {}

    -- Prioritize reagents from the current crafting queue first
    if NS.Queue and NS.Queue.GetShoppingList then
        for _, sItem in ipairs(NS.Queue.GetShoppingList()) do
            if sItem.id and sItem.name and not sItem.isVendor and not seenIDs[sItem.id] then
                seenIDs[sItem.id] = true
                local existing = db[sItem.id]
                if force or not existing or (now - (existing.seen or 0)) > MAX_AGE then
                    table.insert(targets, { id = sItem.id, name = sItem.name })
                end
            end
        end
    end

    -- Then add cached reagents from opened professions
    local knownReagents = (_G.MyCraftingDB and _G.MyCraftingDB.knownReagents) or {}
    for itemID, itemName in pairs(knownReagents) do
        if not seenIDs[itemID] and itemName and itemName ~= "" then
            seenIDs[itemID] = true
            local existing = db[itemID]
            if force or not existing or (now - (existing.seen or 0)) > MAX_AGE then
                table.insert(targets, { id = itemID, name = itemName })
            end
        end
    end

    if #targets == 0 then
        if force then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r No crafting reagents cached yet. Open a profession window first!")
        end
        return
    end

    scanQueue = targets
    scanIndex = 0
    scanActive = true
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99MyCrafting:|r Scanning %d reagent(s) on the AH...", #scanQueue))

    local function StepScan()
        if not scanActive or not IsAHOpen() then
            A.StopScan()
            return
        end

        if _G.C_AuctionHouse and _G.C_AuctionHouse.IsThrottledMessageSystemReady then
            local okReady, ready = pcall(_G.C_AuctionHouse.IsThrottledMessageSystemReady)
            if okReady and ready == false then
                if _G.C_Timer and _G.C_Timer.NewTimer then
                    scanRetryTimer = _G.C_Timer.NewTimer(0.5, StepScan)
                end
                return
            end
        end

        scanIndex = scanIndex + 1
        local entry = scanQueue[scanIndex]
        if not entry then
            local total = #scanQueue
            A.StopScan()
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99MyCrafting:|r Finished scanning %d reagent(s). (%d prices cached)", total, A.GetPriceCount()))
            if NS.UI and NS.UI.CreateOrUpdateSkillBar then
                local parent = _G.ProfessionsFrame or _G.TradeSkillFrame or _G.CraftFrame
                if parent and parent:IsShown() then
                    NS.UI.CreateOrUpdateSkillBar(parent)
                end
            end
            return
        end

        if scanButton then
            scanButton:SetText(string.format("Scan %d/%d", scanIndex, #scanQueue))
        end

        -- Safety timeout in case a reagent has 0 auctions or doesn't fire browse update
        if _G.C_Timer and _G.C_Timer.NewTimer then
            if scanTimeoutTimer then scanTimeoutTimer:Cancel() end
            scanTimeoutTimer = _G.C_Timer.NewTimer(2.0, StepScan)
        end

        if _G.C_AuctionHouse and _G.C_AuctionHouse.SendBrowseQuery then
            pcall(_G.C_AuctionHouse.SendBrowseQuery, {
                searchString = entry.name,
                minLevel = 0,
                maxLevel = 0,
                sorts = {},
                filters = {},
            })
        elseif _G.QueryAuctionItems and _G.CanSendAuctionQuery and _G.CanSendAuctionQuery() then
            pcall(_G.QueryAuctionItems, entry.name, nil, nil, 0, nil, nil, false, false, nil)
        end
    end

    stepScanFn = StepScan
    StepScan()
end

function A.InjectScanButton()
    local ahFrame = _G.AuctionHouseFrame or _G.AuctionFrame
    if not ahFrame or scanButton then return end

    local btn = CreateFrame("Button", "MyCraftingAHScanBtn", ahFrame, "UIPanelButtonTemplate")
    btn:SetSize(110, 22)
    if ahFrame.CloseButton then
        btn:SetPoint("RIGHT", ahFrame.CloseButton, "LEFT", -6, 0)
    else
        btn:SetPoint("TOPRIGHT", ahFrame, "TOPRIGHT", -32, -6)
    end
    btn:SetFrameLevel(ahFrame:GetFrameLevel() + 10)
    btn:SetText("Scan AH Mats")
    btn:SetScript("OnClick", function()
        A.ScanReagents(true)
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("MyCrafting AH Price Scanner")
        GameTooltip:AddLine(string.format("Cached prices: |cffffffff%d|r items", A.GetPriceCount()), 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Click to scan AH prices for your known crafting reagents.", 0.2, 1, 0.5)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    scanButton = btn
end
