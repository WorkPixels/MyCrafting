-- Compat.lua: Cross-version API compatibility layer for WoW Forever, Classic Era, TBC, Wrath, and Modern clients.
local ADDON_NAME, NS = ...
local C = {}
NS.Compat = C

-- ---------------------------------------------------------------------------
-- Safe call helper
-- ---------------------------------------------------------------------------
local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g end
    return nil
end

-- ---------------------------------------------------------------------------
-- Container API Polyfills
-- ---------------------------------------------------------------------------
local CC = _G.C_Container

function C.GetNumBagSlots(bag)
    if CC and CC.GetContainerNumSlots then
        return CC.GetContainerNumSlots(bag) or 0
    elseif _G.GetContainerNumSlots then
        return _G.GetContainerNumSlots(bag) or 0
    end
    return 0
end

function C.GetContainerItemInfo(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local t = CC.GetContainerItemInfo(bag, slot)
        if not t then return nil end
        return {
            icon = t.iconFileID,
            count = t.stackCount or 1,
            locked = t.isLocked,
            quality = t.quality,
            link = t.hyperlink,
            itemID = t.itemID,
        }
    elseif _G.GetContainerItemInfo then
        local icon, count, locked, quality, readable, lootable, link, filtered, noValue, itemID = _G.GetContainerItemInfo(bag, slot)
        if not icon and not itemID then return nil end
        return {
            icon = icon,
            count = count or 1,
            locked = locked,
            quality = quality,
            link = link,
            itemID = itemID,
        }
    end
    return nil
end

function C.GetContainerItemID(bag, slot)
    if CC and CC.GetContainerItemID then
        return CC.GetContainerItemID(bag, slot)
    elseif _G.GetContainerItemID then
        return _G.GetContainerItemID(bag, slot)
    end
    local info = C.GetContainerItemInfo(bag, slot)
    return info and info.itemID
end

-- ---------------------------------------------------------------------------
-- Item API Polyfills
-- ---------------------------------------------------------------------------
local CI = _G.C_Item

function C.GetItemInfo(item)
    if not item then return nil end
    if CI and CI.GetItemInfo then
        local a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p = SafeCall(CI.GetItemInfo, item)
        if a ~= nil then return a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p end
    end
    if _G.GetItemInfo then
        local a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p = SafeCall(_G.GetItemInfo, item)
        if a ~= nil then return a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p end
    end
    return nil
end

function C.GetItemCount(item, includeBank)
    if not item then return 0 end
    if CI and CI.GetItemCount then
        local count = SafeCall(CI.GetItemCount, item, includeBank)
        if count ~= nil then return count end
    end
    if _G.GetItemCount then
        local count = SafeCall(_G.GetItemCount, item, includeBank)
        if count ~= nil then return count end
    end
    return 0
end

function C.GetItemIcon(item)
    if not item then return nil end
    if CI and CI.GetItemIconByID then
        local icon = SafeCall(CI.GetItemIconByID, item)
        if icon then return icon end
    end
    if CI and CI.GetItemIcon then
        local icon = SafeCall(CI.GetItemIcon, item)
        if icon then return icon end
    end
    if _G.GetItemIcon then
        local icon = SafeCall(_G.GetItemIcon, item)
        if icon then return icon end
    end
    return nil
end

function C.GetItemQualityColor(quality)
    if not quality then return 1, 1, 1, "ffffffff" end
    if CI and CI.GetItemQualityColor then
        local r, g, b, hex = SafeCall(CI.GetItemQualityColor, quality)
        if r then return r, g, b, hex end
    end
    if _G.GetItemQualityColor then
        local r, g, b, hex = SafeCall(_G.GetItemQualityColor, quality)
        if r then return r, g, b, hex end
    end
    return 1, 1, 1, "ffffffff"
end

-- ---------------------------------------------------------------------------
-- Money formatting
-- ---------------------------------------------------------------------------
function C.FormatMoney(copper)
    if not copper or copper <= 0 then return "0c" end
    if _G.C_CurrencyInfo and _G.C_CurrencyInfo.GetCoinTextureString then
        local s = SafeCall(_G.C_CurrencyInfo.GetCoinTextureString, copper)
        if s and s ~= "" then return s end
    end
    if _G.GetCoinTextureString then
        local s = SafeCall(_G.GetCoinTextureString, copper)
        if s and s ~= "" then return s end
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        return string.format("|cffffd700%dg|r |cffc7c7cf%ds|r |cffeda55f%dc|r", g, s, c)
    elseif s > 0 then
        return string.format("|cffc7c7cf%ds|r |cffeda55f%dc|r", s, c)
    else
        return string.format("|cffeda55f%dc|r", c)
    end
end

-- ---------------------------------------------------------------------------
-- Sound FX
-- ---------------------------------------------------------------------------
function C.PlaySound(soundKitID, fallbackSound)
    if soundKitID and _G.PlaySound then
        local ok = pcall(_G.PlaySound, soundKitID)
        if ok then return end
    end
    if fallbackSound and _G.PlaySoundFile then
        pcall(_G.PlaySoundFile, fallbackSound)
    end
end

-- ---------------------------------------------------------------------------
-- TradeSkill / Craft Inspection & Execution Abstraction
-- ---------------------------------------------------------------------------
local CTS = _G.C_TradeSkillUI

function C.HasModernTradeSkillUI()
    return CTS ~= nil and CTS.GetAllRecipeIDs ~= nil and CTS.GetRecipeInfo ~= nil
end

-- Returns: professionName, rank, maxRank, icon
function C.GetProfessionInfo()
    if C.HasModernTradeSkillUI() then
        -- 1. Try to get profession info from the first recipe ID
        local recipeIDs = SafeCall(CTS.GetAllRecipeIDs)
        if recipeIDs and recipeIDs[1] and CTS.GetProfessionInfoByRecipeID then
            local info = SafeCall(CTS.GetProfessionInfoByRecipeID, recipeIDs[1])
            if type(info) == "table" then
                return info.professionName or info.parentProfessionName or "Profession",
                       info.skillLevel or 0,
                       info.maxSkillLevel or 0,
                       info.icon
            end
        end

        -- 2. Try GetTradeSkillDisplayName
        if CTS.GetTradeSkillDisplayName then
            local name = SafeCall(CTS.GetTradeSkillDisplayName)
            if name and name ~= "" then
                return name, 0, 0, nil
            end
        end
    end

    if _G.GetTradeSkillLine then
        local name, rank, maxRank = SafeCall(_G.GetTradeSkillLine)
        if name and name ~= "" then
            return name, rank or 0, maxRank or 0, nil
        end
    end

    if _G.GetCraftSkillLine then
        local name, rank, maxRank = SafeCall(_G.GetCraftSkillLine, 1)
        if name and name ~= "" then
            return name, rank or 0, maxRank or 0, nil
        end
    end

    return "Professions", 0, 0, nil
end

function C.GetSpellName(spellID)
    if not spellID then return nil end
    if _G.C_Spell and _G.C_Spell.GetSpellInfo then
        local info = SafeCall(_G.C_Spell.GetSpellInfo, spellID)
        if type(info) == "table" and info.name then
            return info.name
        elseif type(info) == "string" then
            return info
        end
    end
    if _G.GetSpellInfo then
        local name = SafeCall(_G.GetSpellInfo, spellID)
        if name then return name end
    end
    return nil
end

-- Returns the 4 skill thresholds for a recipe: orange, yellow, green, gray
function C.GetRecipeDifficultyThresholds(recipeID, curSkill, diffLevel)
    if not recipeID then return nil end
    local info = CTS and CTS.GetRecipeInfo and SafeCall(CTS.GetRecipeInfo, recipeID)

    local orange = (info and (info.unlockedRecipeLevel or info.recipeLevel)) or nil
    local yellow = (info and info.trivialSkillLow) or nil
    local gray = (info and (info.trivialSkillHigh or info.maxTrivialLevel)) or nil

    if gray and gray > 1 then
        if not orange or orange <= 1 then
            orange = math.max(1, gray - 45)
            if curSkill and diffLevel == 4 and orange > curSkill then
                orange = curSkill
            end
        end
        if not yellow or yellow <= orange or yellow >= gray then
            local span = gray - orange
            yellow = orange + math.floor(span * 0.35)
        end
        -- Ensure consistency with actual recipe difficulty color if Orange
        if curSkill and diffLevel == 4 and yellow <= curSkill and curSkill < gray then
            yellow = math.min(gray - 2, curSkill + math.max(1, math.floor((gray - curSkill) * 0.35)))
        end
        local green = math.floor((yellow + gray) / 2)
        return orange, yellow, green, gray
    end

    orange = orange or 1
    local fallbackYellow = orange + 20
    local fallbackGreen = orange + 40
    local fallbackGray = orange + 60
    return orange, fallbackYellow, fallbackGreen, fallbackGray
end

-- Extracts itemID from an item link
function C.GetItemIDFromLink(link)
    if not link then return nil end
    local itemID = link:match("item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

-- Map difficulty string or number to normalized difficulty:
-- 4 = orange (optimal), 3 = yellow (medium), 2 = green (easy), 1 = grey (trivial)
local function NormalizeDifficulty(diff)
    if type(diff) == "number" then
        if diff == 0 then return 4, "optimal"
        elseif diff == 1 then return 3, "medium"
        elseif diff == 2 then return 2, "easy"
        else return 1, "trivial" end
    elseif type(diff) == "string" then
        local lower = diff:lower()
        if lower == "optimal" or lower == "orange" then return 4, "optimal"
        elseif lower == "medium" or lower == "yellow" then return 3, "medium"
        elseif lower == "easy" or lower == "green" then return 2, "easy"
        else return 1, "trivial" end
    end
    return 1, "trivial"
end

-- Scan recipes and return a unified list of recipe objects
function C.GetAllRecipes()
    local recipes = {}
    local knownRecipeNames = {}

    -- 1. Modern C_TradeSkillUI path
    if C.HasModernTradeSkillUI() then
        local recipeIDs = SafeCall(CTS.GetAllRecipeIDs) or {}
        for _, recipeID in ipairs(recipeIDs) do
            local info = SafeCall(CTS.GetRecipeInfo, recipeID)
            if info and info.learned ~= false then
                local diffLevel, diffType = NormalizeDifficulty(info.relativeDifficulty or info.difficulty)
                local schematic = CTS.GetRecipeSchematic and SafeCall(CTS.GetRecipeSchematic, recipeID, false)
                local reagents = {}
                local craftableCount = 9999

                if schematic and schematic.reagentSlotSchematics then
                    for _, slot in ipairs(schematic.reagentSlotSchematics) do
                        if slot.reagents and slot.reagents[1] then
                            local rItem = slot.reagents[1]
                            local rID = rItem.itemID
                            local rName, rLink, rQual, _, _, _, _, _, _, rIcon = C.GetItemInfo(rID)
                            local reqCount = slot.quantityRequired or 1
                            local haveCount = C.GetItemCount(rID, false)
                            table.insert(reagents, {
                                itemID = rID,
                                name = rName or ("Item " .. rID),
                                icon = rIcon or (rItem.iconFileID or 134400),
                                count = reqCount,
                                have = haveCount,
                                link = rLink,
                                quality = rQual or 1,
                            })
                            local possible = math.floor(haveCount / math.max(1, reqCount))
                            if possible < craftableCount then
                                craftableCount = possible
                            end
                        end
                    end
                end
                if craftableCount == 9999 then craftableCount = 0 end

                local outputItemID = schematic and schematic.outputItemID
                local itemLink = outputItemID and select(2, C.GetItemInfo(outputItemID)) or (CTS.GetRecipeItemLink and SafeCall(CTS.GetRecipeItemLink, recipeID))

                local entry = {
                    id = recipeID,
                    index = recipeID,
                    name = info.name or "Unknown Recipe",
                    icon = info.icon or (outputItemID and C.GetItemIcon(outputItemID)) or 134400,
                    diffLevel = diffLevel,
                    difficulty = diffType,
                    craftable = craftableCount,
                    numMade = { min = schematic and schematic.quantityMin or 1, max = schematic and schematic.quantityMax or 1 },
                    reagents = reagents,
                    itemLink = itemLink,
                    outputItemID = outputItemID,
                    cooldown = (CTS.GetRecipeCooldown and SafeCall(CTS.GetRecipeCooldown, recipeID)) or 0,
                    source = "modern",
                    isHeader = false,
                }
                table.insert(recipes, entry)
                knownRecipeNames[entry.name:lower()] = entry
            end
        end
        if #recipes > 0 then
            return recipes, knownRecipeNames
        end
    end

    -- 2. Classic Era / TBC TradeSkill path
    if _G.GetNumTradeSkills and _G.GetNumTradeSkills() > 0 then
        local numTradeSkills = _G.GetNumTradeSkills()
        for i = 1, numTradeSkills do
            local skillName, skillType, numAvailable, isExpanded, altVerb, numSkillUps = _G.GetTradeSkillInfo(i)
            if skillName then
                if skillType == "header" then
                    table.insert(recipes, {
                        id = i,
                        index = i,
                        name = skillName,
                        isHeader = true,
                        isExpanded = isExpanded,
                        source = "tradeskill",
                    })
                else
                    local diffLevel, diffType = NormalizeDifficulty(skillType)
                    local icon = _G.GetTradeSkillIcon and _G.GetTradeSkillIcon(i)
                    local minMade, maxMade = 1, 1
                    if _G.GetTradeSkillNumMade then
                        minMade, maxMade = _G.GetTradeSkillNumMade(i)
                    end
                    local itemLink = _G.GetTradeSkillItemLink and _G.GetTradeSkillItemLink(i)
                    local recipeLink = _G.GetTradeSkillRecipeLink and _G.GetTradeSkillRecipeLink(i)
                    local outputItemID = C.GetItemIDFromLink(itemLink)
                    local cooldown = _G.GetTradeSkillCooldown and _G.GetTradeSkillCooldown(i) or 0

                    local numReagents = _G.GetTradeSkillNumReagents and _G.GetTradeSkillNumReagents(i) or 0
                    local reagents = {}
                    for r = 1, numReagents do
                        local rName, rTexture, rCount, playerReagentCount = _G.GetTradeSkillReagentInfo(i, r)
                        local rLink = _G.GetTradeSkillReagentItemLink and _G.GetTradeSkillReagentItemLink(i, r)
                        local rID = C.GetItemIDFromLink(rLink)
                        local _, _, rQual = C.GetItemInfo(rID or rName)
                        table.insert(reagents, {
                            itemID = rID,
                            name = rName or "Reagent",
                            icon = rTexture or 134400,
                            count = rCount or 1,
                            have = playerReagentCount or 0,
                            link = rLink,
                            quality = rQual or 1,
                        })
                    end

                    local entry = {
                        id = i,
                        index = i,
                        name = skillName,
                        icon = icon or 134400,
                        diffLevel = diffLevel,
                        difficulty = diffType,
                        craftable = numAvailable or 0,
                        numMade = { min = minMade or 1, max = maxMade or 1 },
                        reagents = reagents,
                        itemLink = itemLink,
                        recipeLink = recipeLink,
                        outputItemID = outputItemID,
                        cooldown = cooldown,
                        source = "tradeskill",
                        isHeader = false,
                    }
                    table.insert(recipes, entry)
                    knownRecipeNames[entry.name:lower()] = entry
                end
            end
        end
        return recipes, knownRecipeNames
    end

    -- 3. Classic Era / TBC Craft (Enchanting) path
    if _G.GetNumCrafts and _G.GetNumCrafts() > 0 then
        local numCrafts = _G.GetNumCrafts()
        for i = 1, numCrafts do
            local craftName, craftSubSpellName, craftType, numAvailable, isExpanded = _G.GetCraftInfo(i)
            if craftName then
                if craftType == "header" then
                    table.insert(recipes, {
                        id = i,
                        index = i,
                        name = craftName,
                        isHeader = true,
                        isExpanded = isExpanded,
                        source = "craft",
                    })
                else
                    local diffLevel, diffType = NormalizeDifficulty(craftType)
                    local icon = _G.GetCraftIcon and _G.GetCraftIcon(i)
                    local itemLink = _G.GetCraftItemLink and _G.GetCraftItemLink(i)
                    local outputItemID = C.GetItemIDFromLink(itemLink)
                    local numReagents = _G.GetCraftNumReagents and _G.GetCraftNumReagents(i) or 0
                    local reagents = {}
                    for r = 1, numReagents do
                        local rName, rTexture, rCount, playerReagentCount = _G.GetCraftReagentInfo(i, r)
                        local rLink = _G.GetCraftReagentItemLink and _G.GetCraftReagentItemLink(i, r)
                        local rID = C.GetItemIDFromLink(rLink)
                        local _, _, rQual = C.GetItemInfo(rID or rName)
                        table.insert(reagents, {
                            itemID = rID,
                            name = rName or "Reagent",
                            icon = rTexture or 134400,
                            count = rCount or 1,
                            have = playerReagentCount or 0,
                            link = rLink,
                            quality = rQual or 1,
                        })
                    end

                    local entry = {
                        id = i,
                        index = i,
                        name = craftName,
                        icon = icon or 134400,
                        diffLevel = diffLevel,
                        difficulty = diffType,
                        craftable = numAvailable or 0,
                        numMade = { min = 1, max = 1 },
                        reagents = reagents,
                        itemLink = itemLink,
                        outputItemID = outputItemID,
                        cooldown = 0,
                        source = "craft",
                        isHeader = false,
                    }
                    table.insert(recipes, entry)
                    knownRecipeNames[entry.name:lower()] = entry
                end
            end
        end
        return recipes, knownRecipeNames
    end

    return recipes, knownRecipeNames
end

-- Perform craft action for a given recipe
function C.Craft(recipe, count)
    if not recipe then return false end
    count = count or 1

    if recipe.source == "modern" then
        if CTS and CTS.CraftRecipe then
            local ok = pcall(CTS.CraftRecipe, recipe.id, count)
            return ok
        end
    elseif recipe.source == "tradeskill" then
        if _G.DoTradeSkill then
            local ok = pcall(_G.DoTradeSkill, recipe.index, count)
            return ok
        end
    elseif recipe.source == "craft" then
        if _G.DoCraft then
            local ok = pcall(_G.DoCraft, recipe.index)
            return ok
        end
    end
    return false
end

-- Get currently selected recipe from ProfessionsFrame, TradeSkillFrame or CraftFrame
function C.GetSelectedRecipe()
    local allRecipes, known = C.GetAllRecipes()

    -- 1. Modern ProfessionsFrame (Dragonflight / TWW / Forever)
    local pf = _G.ProfessionsFrame
    if pf and pf.CraftingPage then
        local cp = pf.CraftingPage
        local rID = nil
        if cp.GetSelectedRecipeID then
            rID = SafeCall(cp.GetSelectedRecipeID, cp)
        end
        if not rID and cp.GetCurrentRecipeInfo then
            local info = SafeCall(cp.GetCurrentRecipeInfo, cp)
            if type(info) == "table" then rID = info.recipeID end
        end
        if not rID and cp.SchematicForm then
            if cp.SchematicForm.GetRecipeInfo then
                local info = SafeCall(cp.SchematicForm.GetRecipeInfo, cp.SchematicForm)
                if type(info) == "table" then rID = info.recipeID end
            end
            if not rID and cp.SchematicForm.transaction and cp.SchematicForm.transaction.GetRecipeID then
                rID = SafeCall(cp.SchematicForm.transaction.GetRecipeID, cp.SchematicForm.transaction)
            end
            if not rID and cp.SchematicForm.currentRecipeInfo then
                rID = cp.SchematicForm.currentRecipeInfo.recipeID
            end
            if not rID and cp.SchematicForm.recipeSchematic then
                rID = cp.SchematicForm.recipeSchematic.recipeID
            end
        end
        if not rID and cp.RecipeList then
            if cp.RecipeList.GetSelectedRecipeID then
                rID = SafeCall(cp.RecipeList.GetSelectedRecipeID, cp.RecipeList)
            end
            if not rID and cp.RecipeList.selectionBehavior and cp.RecipeList.selectionBehavior.GetFirstSelectedElementData then
                local elem = SafeCall(cp.RecipeList.selectionBehavior.GetFirstSelectedElementData, cp.RecipeList.selectionBehavior)
                if type(elem) == "table" and elem.data and elem.data.recipeInfo then
                    rID = elem.data.recipeInfo.recipeID
                end
            end
        end
        if not rID and NS.lastSelectedRecipeID then
            rID = NS.lastSelectedRecipeID
        end
        if not rID and cp.Schematic then
            if cp.Schematic.GetRecipeID then
                rID = SafeCall(cp.Schematic.GetRecipeID, cp.Schematic)
            elseif cp.Schematic.recipeID then
                rID = cp.Schematic.recipeID
            elseif cp.Schematic.currentRecipeInfo then
                rID = cp.Schematic.currentRecipeInfo.recipeID
            end
        end

        if rID then
            for _, r in ipairs(allRecipes) do
                if r.id == rID then return r end
            end
            -- Build fallback on the fly if not yet cached
            local info = SafeCall(CTS.GetRecipeInfo, rID)
            if info then
                local schematic = CTS.GetRecipeSchematic and SafeCall(CTS.GetRecipeSchematic, rID, false)
                local reagents = {}
                if schematic and schematic.reagentSlotSchematics then
                    for _, slot in ipairs(schematic.reagentSlotSchematics) do
                        if slot.reagents and slot.reagents[1] then
                            local rItem = slot.reagents[1]
                            local rID_reag = rItem.itemID
                            local rName, rLink, rQual, _, _, _, _, _, _, rIcon = C.GetItemInfo(rID_reag)
                            local reqCount = slot.quantityRequired or 1
                            table.insert(reagents, {
                                itemID = rID_reag,
                                name = rName or ("Item " .. rID_reag),
                                icon = rIcon or (rItem.iconFileID or 134400),
                                count = reqCount,
                                have = C.GetItemCount(rID_reag, false),
                                link = rLink,
                                quality = rQual or 1,
                            })
                        end
                    end
                end
                local outputItemID = schematic and schematic.outputItemID
                local itemLink = outputItemID and select(2, C.GetItemInfo(outputItemID)) or (CTS.GetRecipeItemLink and SafeCall(CTS.GetRecipeItemLink, rID))
                return {
                    id = rID,
                    index = rID,
                    name = info.name or "Recipe",
                    icon = info.icon or (outputItemID and C.GetItemIcon(outputItemID)) or 134400,
                    diffLevel = 3,
                    craftable = (CTS.GetCraftableCount and SafeCall(CTS.GetCraftableCount, rID)) or 0,
                    numMade = { min = schematic and schematic.quantityMin or 1, max = schematic and schematic.quantityMax or 1 },
                    reagents = reagents,
                    itemLink = itemLink,
                    outputItemID = outputItemID,
                    source = "modern",
                    isHeader = false,
                }
            end
        end
    end

    -- 2. Modern TradeSkillFrame DetailsFrame selected recipe
    local ts = _G.TradeSkillFrame
    if ts and ts.DetailsFrame then
        local rID = ts.DetailsFrame.selectedRecipeID
        if rID then
            for _, r in ipairs(allRecipes) do
                if r.id == rID then return r end
            end
        end
    end

    -- 3. Modern RecipeList selection
    if ts and ts.RecipeList and ts.RecipeList.GetSelectedRecipeID then
        local ok, rID = pcall(ts.RecipeList.GetSelectedRecipeID, ts.RecipeList)
        if ok and rID then
            for _, r in ipairs(allRecipes) do
                if r.id == rID then return r end
            end
        end
    end

    -- 4. Legacy GetTradeSkillSelectionIndex
    if _G.GetTradeSkillSelectionIndex then
        local idx = SafeCall(_G.GetTradeSkillSelectionIndex)
        if idx and idx > 0 then
            for _, r in ipairs(allRecipes) do
                if r.index == idx and not r.isHeader then return r end
            end
        end
    end

    -- 5. Legacy GetCraftSelectionIndex
    if _G.GetCraftSelectionIndex then
        local idx = SafeCall(_G.GetCraftSelectionIndex)
        if idx and idx > 0 then
            for _, r in ipairs(allRecipes) do
                if r.index == idx and not r.isHeader then return r end
            end
        end
    end

    -- 6. Fallback: first craftable or first valid recipe
    for _, r in ipairs(allRecipes) do
        if not r.isHeader then return r end
    end

    return nil
end

-- Get quantity currently entered in default UI's edit box / spinner
function C.GetSelectedCount()
    local function ReadBox(box)
        if not box then return nil end
        if box.GetValue then
            local n = SafeCall(box.GetValue, box)
            if type(n) == "number" and n > 0 then return n end
        end
        if box.GetNumber then
            local n = SafeCall(box.GetNumber, box)
            if type(n) == "number" and n > 0 then return n end
        end
        if box.InputBox and box.InputBox.GetNumber then
            local n = SafeCall(box.InputBox.GetNumber, box.InputBox)
            if type(n) == "number" and n > 0 then return n end
        end
        return nil
    end

    local pf = _G.ProfessionsFrame
    if pf and pf.CraftingPage and pf.CraftingPage.CreateMultipleInputBox then
        local n = ReadBox(pf.CraftingPage.CreateMultipleInputBox)
        if n then return n end
    end
    if _G.TradeSkillInputBox then
        local n = ReadBox(_G.TradeSkillInputBox)
        if n then return n end
    end
    local ts = _G.TradeSkillFrame
    if ts and ts.DetailsFrame and ts.DetailsFrame.CreateMultipleInputBox then
        local n = ReadBox(ts.DetailsFrame.CreateMultipleInputBox)
        if n then return n end
    end
    return 1
end

-- Select/navigate to a recipe in the default UI
function C.SelectRecipe(recipe)
    if not recipe then return end
    local pf = _G.ProfessionsFrame
    if pf and pf.CraftingPage and pf.CraftingPage.SelectRecipe then
        pcall(pf.CraftingPage.SelectRecipe, pf.CraftingPage, recipe.id)
    end
    if recipe.source == "modern" then
        if CTS and CTS.OpenRecipe then
            pcall(CTS.OpenRecipe, recipe.id)
        end
    elseif recipe.source == "tradeskill" then
        if _G.SelectTradeSkill then
            pcall(_G.SelectTradeSkill, recipe.index)
        end
    elseif recipe.source == "craft" then
        if _G.SelectCraft then
            pcall(_G.SelectCraft, recipe.index)
        end
    end
end

-- Close TradeSkill / Craft window safely
function C.CloseTradeSkill()
    if CTS and CTS.CloseTradeSkill then
        pcall(CTS.CloseTradeSkill)
    elseif _G.CloseTradeSkill then
        pcall(_G.CloseTradeSkill)
    end
    if _G.CloseCraft then
        pcall(_G.CloseCraft)
    end
end
