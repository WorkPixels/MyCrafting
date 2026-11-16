-- VendorDB.lua: Database of vendor-sold crafting reagents with prices and merchant automation.
local ADDON_NAME, NS = ...
local V = {}
NS.VendorDB = V

local C = NS.Compat

-- Known standard vendor-purchased crafting reagents (ItemID -> { name = ..., cost = copper })
local VENDOR_REAGENTS = {
    -- Vials (Alchemy)
    [75]    = { name = "Empty Vial", cost = 40 },
    [3371]  = { name = "Leaded Vial", cost = 300 },
    [8925]  = { name = "Crystal Vial", cost = 4000 },
    [18256] = { name = "Imbued Vial", cost = 16000 },

    -- Thread & Dyes (Tailoring / Leatherworking)
    [2320]  = { name = "Coarse Thread", cost = 10 },
    [2321]  = { name = "Fine Thread", cost = 100 },
    [4291]  = { name = "Silken Thread", cost = 500 },
    [8343]  = { name = "Heavy Silken Thread", cost = 2000 },
    [14341] = { name = "Rune Thread", cost = 5000 },
    [2604]  = { name = "Gray Dye", cost = 50 },
    [2605]  = { name = "Yellow Dye", cost = 50 },
    [2678]  = { name = "Red Dye", cost = 100 },
    [2603]  = { name = "Blue Dye", cost = 100 },
    [4340]  = { name = "Green Dye", cost = 200 },
    [4341]  = { name = "Purple Dye", cost = 250 },
    [4342]  = { name = "Bleach", cost = 25 },
    [4343]  = { name = "Pink Dye", cost = 500 },
    [4344]  = { name = "Black Dye", cost = 1000 },
    [9210]  = { name = "Ghost Dye", cost = 1500 },

    -- Flux, Coal & Stones (Blacksmithing / Engineering)
    [2880]  = { name = "Weak Flux", cost = 100 },
    [3466]  = { name = "Strong Flux", cost = 2000 },
    [3857]  = { name = "Coal", cost = 500 },
    [4361]  = { name = "Heavy Stock", cost = 2000 },
    [4362]  = { name = "Wooden Stock", cost = 200 },
    [2901]  = { name = "Mining Pick", cost = 82 },
    [5956]  = { name = "Blacksmith Hammer", cost = 18 },
    [10648] = { name = "Blank Parchment", cost = 500 },

    -- Leatherworking
    [4289]  = { name = "Salt", cost = 12 },
    [7005]  = { name = "Skinning Knife", cost = 83 },

    -- Spices & Food Ingredients (Cooking)
    [159]   = { name = "Refreshing Spring Water", cost = 25 },
    [2672]  = { name = "Mild Spices", cost = 10 },
    [2673]  = { name = "Hot Spices", cost = 20 },
    [3713]  = { name = "Soothing Spices", cost = 160 },
    [3081]  = { name = "Simple Flour", cost = 25 },
    [17194] = { name = "Holiday Spices", cost = 10 },

    -- Enchanting
    [4470]  = { name = "Simple Wood", cost = 38 },
    [11291] = { name = "Star Wood", cost = 500 },
    [6218]  = { name = "Copper Rod", cost = 124 },

    -- Rogue Poisons & Supplies
    [5173]  = { name = "Dust of Decay", cost = 80 },
    [5174]  = { name = "Essence of Pain", cost = 150 },
    [5175]  = { name = "Deathweed", cost = 300 },
    [8923]  = { name = "Dust of Deterioration", cost = 600 },
    [5140]  = { name = "Flash Powder", cost = 100 },
    [4471]  = { name = "Flint and Tinder", cost = 50 },
}

-- Build lowercase name lookup
local VENDOR_NAMES = {}
for id, data in pairs(VENDOR_REAGENTS) do
    VENDOR_NAMES[data.name:lower()] = { id = id, cost = data.cost }
end

function V.ScanMerchantPrices()
    if not V.IsMerchantOpen() or not _G.MyCraftingDB then return 0 end
    _G.MyCraftingDB.vendorPrices = _G.MyCraftingDB.vendorPrices or {}
    local vdb = _G.MyCraftingDB.vendorPrices
    local numItems = _G.GetMerchantNumItems()
    local updated = 0

    for i = 1, numItems do
        local name, _, price, quantity, numAvailable, isPurchasable, _, extendedCost = _G.GetMerchantItemInfo(i)
        local link = _G.GetMerchantItemLink(i)
        local itemID = link and C.GetItemIDFromLink(link)
        -- Cache unlimited-stock gold/silver/copper vendor items (ignore limited-stock/token items)
        if itemID and price and price > 0 and not extendedCost and numAvailable == -1 then
            local unitPrice = math.floor(price / math.max(1, quantity or 1))
            if unitPrice > 0 then
                vdb[itemID] = {
                    name = name,
                    cost = unitPrice,
                }
                updated = updated + 1
            end
        end
    end

    return updated
end

function V.IsVendorReagent(itemID, name)
    local cached = _G.MyCraftingDB and _G.MyCraftingDB.vendorPrices
    if cached and itemID and cached[itemID] and cached[itemID].cost then
        return true, cached[itemID].cost
    end
    if itemID and VENDOR_REAGENTS[itemID] then
        return true, VENDOR_REAGENTS[itemID].cost
    end
    if name then
        local lower = name:lower()
        if cached then
            for _, entry in pairs(cached) do
                if entry.name and entry.name:lower() == lower and entry.cost then
                    return true, entry.cost
                end
            end
        end
        local entry = VENDOR_NAMES[lower]
        if entry then
            return true, entry.cost
        end
    end
    return false, 0
end

function V.GetVendorCost(itemID, name)
    local isVendor, cost = V.IsVendorReagent(itemID, name)
    return isVendor and cost or 0
end

-- Checks if a merchant is currently open and has items
function V.IsMerchantOpen()
    return _G.MerchantFrame and _G.MerchantFrame:IsShown() and (_G.GetMerchantNumItems and _G.GetMerchantNumItems() > 0)
end

-- Scans the currently open merchant against a shopping list of required reagents.
-- Returns: matches = { { merchantIndex = i, itemID = id, name = name, needCount = count, price = price, maxStack = stack } }, totalCost
function V.ScanMerchantForShoppingList(shoppingList)
    local matches = {}
    local totalCost = 0
    if not V.IsMerchantOpen() or not shoppingList then
        return matches, totalCost
    end

    local numItems = _G.GetMerchantNumItems()
    for _, needItem in ipairs(shoppingList) do
        if needItem.need and needItem.need > 0 then
            local targetID = needItem.itemID
            local targetName = needItem.name and needItem.name:lower()

            for i = 1, numItems do
                local name, texture, price, quantity, numAvailable, isPurchasable = _G.GetMerchantItemInfo(i)
                local link = _G.GetMerchantItemLink(i)
                local itemID = link and C.GetItemIDFromLink(link)

                local isMatch = false
                if targetID and itemID and targetID == itemID then
                    isMatch = true
                elseif targetName and name and targetName == name:lower() then
                    isMatch = true
                end

                if isMatch and (numAvailable == -1 or numAvailable >= needItem.need) then
                    local singlePrice = (price or 0) / math.max(1, quantity or 1)
                    local cost = singlePrice * needItem.need
                    table.insert(matches, {
                        merchantIndex = i,
                        itemID = targetID or itemID,
                        name = name,
                        needCount = needItem.need,
                        price = singlePrice,
                        cost = cost,
                        texture = texture,
                    })
                    totalCost = totalCost + cost
                    break
                end
            end
        end
    end

    return matches, totalCost
end

-- Buys items matched at the current merchant
function V.BuyItems(matches)
    if not V.IsMerchantOpen() or not matches then return 0 end
    local totalBought = 0

    for _, match in ipairs(matches) do
        local remaining = match.needCount
        local index = match.merchantIndex
        local _, _, _, stackCount, numAvail = _G.GetMerchantItemInfo(index)
        stackCount = stackCount or 1

        -- Buy in batches respecting stack limits
        while remaining > 0 do
            local buyAmount = math.min(remaining, 200)
            if numAvail and numAvail > 0 then
                buyAmount = math.min(buyAmount, numAvail)
            end
            if buyAmount <= 0 then break end

            if _G.BuyMerchantItem then
                _G.BuyMerchantItem(index, buyAmount)
                totalBought = totalBought + buyAmount
                remaining = remaining - buyAmount
            else
                break
            end
        end
    end

    return totalBought
end
