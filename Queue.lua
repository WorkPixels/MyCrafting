-- Queue.lua: Crafting queue management, shopping list calculation, and automated execution engine.
local ADDON_NAME, NS = ...
local Q = {}
NS.Queue = Q

local C = NS.Compat
local V = NS.VendorDB

-- Internal queue storage (references MyCraftingDB.queue)
local queueList = {}
local isRunning = false
local isPaused = false
local currentCraftTarget = nil
local lastCraftTime = 0

-- Callbacks
local listeners = {}
function Q.RegisterListener(fn)
    table.insert(listeners, fn)
end

local function NotifyListeners(event)
    for _, fn in ipairs(listeners) do
        pcall(fn, event)
    end
end

function Q.Init(savedQueue)
    if savedQueue and type(savedQueue) == "table" then
        queueList = savedQueue
    else
        queueList = {}
    end
    return queueList
end

function Q.GetList()
    return queueList
end

function Q.GetCount()
    return #queueList
end

-- Add item to queue
function Q.Add(recipe, count)
    if not recipe or not recipe.name then return end
    count = math.max(1, tonumber(count) or 1)

    -- Check if identical recipe already exists in queue, if so append count
    for _, item in ipairs(queueList) do
        if item.name == recipe.name then
            item.count = item.count + count
            NotifyListeners("QUEUE_UPDATED")
            return
        end
    end

    local entry = {
        id = recipe.id,
        index = recipe.index,
        name = recipe.name,
        icon = recipe.icon,
        count = count,
        reagents = recipe.reagents or {},
        source = recipe.source,
        itemLink = recipe.itemLink,
        outputItemID = recipe.outputItemID,
    }
    table.insert(queueList, entry)
    NotifyListeners("QUEUE_UPDATED")
end

-- Remove item by index
function Q.Remove(index)
    if queueList[index] then
        table.remove(queueList, index)
        NotifyListeners("QUEUE_UPDATED")
    end
end

-- Clear all items
function Q.Clear()
    wipe(queueList)
    if isRunning then
        Q.Stop()
    end
    NotifyListeners("QUEUE_UPDATED")
end

-- Modify count
function Q.SetCount(index, count)
    if queueList[index] then
        if count <= 0 then
            Q.Remove(index)
        else
            queueList[index].count = count
            NotifyListeners("QUEUE_UPDATED")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Shopping List Calculation
-- ---------------------------------------------------------------------------
-- Calculates materials required across the entire queue (or a single recipe if passed)
function Q.GetShoppingList(customRecipe, customCount)
    local list = {}
    local reqMap = {} -- [key] = { itemID, name, icon, required, link }

    local itemsToProcess = {}
    if customRecipe then
        itemsToProcess = { { recipe = customRecipe, count = customCount or 1 } }
    else
        for _, qItem in ipairs(queueList) do
            table.insert(itemsToProcess, { recipe = qItem, count = qItem.count })
        end
    end

    for _, entry in ipairs(itemsToProcess) do
        local mult = entry.count
        for _, r in ipairs(entry.recipe.reagents or {}) do
            local key = r.itemID or r.name:lower()
            if not reqMap[key] then
                reqMap[key] = {
                    itemID = r.itemID,
                    name = r.name,
                    icon = r.icon,
                    link = r.link,
                    required = 0,
                }
            end
            reqMap[key].required = reqMap[key].required + (r.count * mult)
        end
    end

    local bankDB = _G.MyCraftingDB and _G.MyCraftingDB.bankInventory or {}

    for key, data in pairs(reqMap) do
        local bagCount = C.GetItemCount(data.itemID or data.name, false)
        local bankCount = 0

        if data.itemID and bankDB[data.itemID] then
            bankCount = bankDB[data.itemID]
        else
            local totalWithBank = C.GetItemCount(data.itemID or data.name, true)
            bankCount = math.max(0, totalWithBank - bagCount)
        end

        local needed = math.max(0, data.required - bagCount)
        local isVendor, singleCost = V.IsVendorReagent(data.itemID, data.name)
        local totalVendorCost = isVendor and (singleCost * needed) or 0

        table.insert(list, {
            itemID = data.itemID,
            name = data.name,
            icon = data.icon,
            link = data.link,
            required = data.required,
            have = bagCount,
            bank = bankCount,
            need = needed,
            isVendor = isVendor,
            vendorCost = totalVendorCost,
        })
    end

    -- Sort: Missing items first, then vendor items, then alphabetically
    table.sort(list, function(a, b)
        if (a.need > 0) ~= (b.need > 0) then
            return a.need > 0
        end
        if a.isVendor ~= b.isVendor then
            return a.isVendor
        end
        return a.name < b.name
    end)

    return list
end

-- Export shopping list to chat
function Q.ShareToChat(channel, target)
    local list = Q.GetShoppingList()
    if #list == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Shopping list is empty.")
        return
    end

    local lines = {}
    table.insert(lines, "[MyCrafting Shopping List]:")

    local missingFound = false
    for _, item in ipairs(list) do
        if item.need > 0 then
            missingFound = true
            local itemStr = item.link or item.name
            local vendorNote = item.isVendor and " (Vendor)" or ""
            table.insert(lines, string.format(" - %dx %s%s [Have: %d]", item.need, itemStr, vendorNote, item.have))
        end
    end

    if not missingFound then
        table.insert(lines, " All materials currently in bags!")
    end

    if not channel or channel == "SELF" then
        for _, l in ipairs(lines) do
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. l .. "|r")
        end
    else
        for _, l in ipairs(lines) do
            _G.SendChatMessage(l, channel, nil, target)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Automated Queue Execution Engine
-- ---------------------------------------------------------------------------
local executionFrame = CreateFrame("Frame", "MyCraftingExecutionFrame")
local ticker = 0
local TICK_INTERVAL = 0.25

function Q.IsRunning()
    return isRunning
end

function Q.IsPaused()
    return isPaused
end

function Q.Start()
    if #queueList == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Crafting queue is empty.")
        return
    end
    isRunning = true
    isPaused = false
    currentCraftTarget = nil
    executionFrame:Show()
    NotifyListeners("QUEUE_STATE_CHANGED")
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Queue execution started.")
    Q.ProcessNext()
end

function Q.Pause()
    if isRunning then
        isPaused = true
        executionFrame:Hide()
        NotifyListeners("QUEUE_STATE_CHANGED")
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Queue execution paused.")
    end
end

function Q.Resume()
    if isRunning and isPaused then
        isPaused = false
        executionFrame:Show()
        NotifyListeners("QUEUE_STATE_CHANGED")
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Queue execution resumed.")
        Q.ProcessNext()
    end
end

function Q.Stop()
    isRunning = false
    isPaused = false
    currentCraftTarget = nil
    executionFrame:Hide()
    NotifyListeners("QUEUE_STATE_CHANGED")
end

-- Check if player can craft the specified item (has reagents) and return max craftable
local function CanCraftItem(item)
    if not item or not item.reagents then return false, nil, 0 end
    local maxCraft = item.count or 1
    for _, r in ipairs(item.reagents) do
        local req = math.max(1, r.count or 1)
        local count = C.GetItemCount(r.itemID or r.name, false)
        if count < req then
            return false, r.name, 0
        end
        maxCraft = math.min(maxCraft, math.floor(count / req))
    end
    return true, nil, math.max(1, maxCraft)
end

function Q.ProcessNext()
    if not isRunning or isPaused then return end

    if #queueList == 0 then
        Q.Stop()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r All queued crafts finished!")
        C.PlaySound(SOUNDKIT and SOUNDKIT.LEVELUPSOUND or 618)
        return
    end

    if _G.UnitIsDeadOrGhost("player") then
        Q.Pause()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Player is dead. Queue paused.")
        return
    end

    if _G.InCombatLockdown and _G.InCombatLockdown() then
        Q.Pause()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Player entered combat. Queue paused.")
        return
    end

    local topItem = queueList[1]
    local canCraft, missingReagent, maxCraft = CanCraftItem(topItem)
    if not canCraft then
        Q.Pause()
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99MyCrafting:|r Insufficient reagents for %s (Missing: %s). Queue paused.", topItem.name, missingReagent or "reagents"))
        return
    end

    local craftCount = math.min(topItem.count or 1, maxCraft)
    currentCraftTarget = topItem
    lastCraftTime = GetTime()

    -- Craft the full batch on this hardware click (avoids ADDON_ACTION_BLOCKED on timers)
    local ok = C.Craft(topItem, craftCount)
    if not ok then
        local allRecipes, known = C.GetAllRecipes()
        local found = known[topItem.name:lower()]
        if found then
            topItem.id = found.id
            topItem.index = found.index
            topItem.source = found.source
            C.Craft(topItem, craftCount)
        else
            Q.Pause()
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99MyCrafting:|r Could not cast %s. Is the profession window open?", topItem.name))
        end
    end
end

-- On craft completed event
function Q.OnCraftSucceeded(spellName)
    if not isRunning or isPaused then return end
    if not currentCraftTarget then return end

    -- Decrement count as each item in the batch finishes
    currentCraftTarget.count = currentCraftTarget.count - 1
    if currentCraftTarget.count <= 0 then
        table.remove(queueList, 1)
        currentCraftTarget = nil
        NotifyListeners("QUEUE_UPDATED")

        if #queueList == 0 then
            Q.Stop()
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r All queued crafts finished!")
            if not (_G.MyCraftingDB and _G.MyCraftingDB.options and _G.MyCraftingDB.options.playQueueSound == false) then
                C.PlaySound(SOUNDKIT and SOUNDKIT.LEVELUPSOUND or 618)
            end
        else
            -- Modern clients require a hardware click to start a different recipe
            isPaused = true
            NotifyListeners("QUEUE_STATE_CHANGED")
            local nextItem = queueList[1]
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99MyCrafting:|r Ready for next item: |cffffd100%dx %s|r. Click |cff00ff00Resume|r to craft.", nextItem.count, nextItem.name))
        end
    else
        NotifyListeners("QUEUE_UPDATED")
    end
end

-- Watch for failures or interruptions
function Q.OnCraftFailed()
    if isRunning and currentCraftTarget then
        currentCraftTarget = nil
        Q.Pause()
    end
end

executionFrame:Hide()
