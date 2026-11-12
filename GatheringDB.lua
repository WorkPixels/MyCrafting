-- GatheringDB.lua: Mining & Herbalism node skill level thresholds and world tooltip enhancement.
local ADDON_NAME, NS = ...
local G = {}
NS.GatheringDB = G

-- Node database: [lowercase node name] = { prof, req, yellow, green, gray }
local NODES = {
    -- Mining Veins & Deposits (Classic / Forever)
    ["copper vein"]                     = { prof = "Mining", req = 1,   yellow = 25,  green = 50,  gray = 100 },
    ["tin vein"]                        = { prof = "Mining", req = 65,  yellow = 90,  green = 115, gray = 165 },
    ["incendicite mineral vein"]        = { prof = "Mining", req = 65,  yellow = 90,  green = 115, gray = 165 },
    ["silver vein"]                     = { prof = "Mining", req = 75,  yellow = 100, green = 125, gray = 175 },
    ["lesser bloodstone deposit"]       = { prof = "Mining", req = 75,  yellow = 100, green = 125, gray = 175 },
    ["iron deposit"]                    = { prof = "Mining", req = 125, yellow = 150, green = 175, gray = 225 },
    ["indurium mineral vein"]           = { prof = "Mining", req = 150, yellow = 175, green = 200, gray = 250 },
    ["gold vein"]                       = { prof = "Mining", req = 155, yellow = 180, green = 205, gray = 255 },
    ["mithril deposit"]                 = { prof = "Mining", req = 175, yellow = 200, green = 225, gray = 275 },
    ["ooze covered mithril deposit"]    = { prof = "Mining", req = 175, yellow = 200, green = 225, gray = 275 },
    ["truesilver deposit"]              = { prof = "Mining", req = 230, yellow = 255, green = 280, gray = 330 },
    ["ooze covered truesilver deposit"] = { prof = "Mining", req = 230, yellow = 255, green = 280, gray = 330 },
    ["dark iron deposit"]               = { prof = "Mining", req = 230, yellow = 255, green = 280, gray = 330 },
    ["small thorium vein"]              = { prof = "Mining", req = 245, yellow = 270, green = 295, gray = 345 },
    ["ooze covered thorium vein"]       = { prof = "Mining", req = 245, yellow = 270, green = 295, gray = 345 },
    ["rich thorium vein"]               = { prof = "Mining", req = 275, yellow = 300, green = 325, gray = 350 },
    ["ooze covered rich thorium vein"]  = { prof = "Mining", req = 275, yellow = 300, green = 325, gray = 350 },
    ["small obsidian chunk"]            = { prof = "Mining", req = 305, yellow = 305, green = 305, gray = 350 },
    ["large obsidian chunk"]            = { prof = "Mining", req = 305, yellow = 305, green = 305, gray = 350 },

    -- Herbalism Nodes (Classic / Forever)
    ["peacebloom"]                      = { prof = "Herbalism", req = 1,   yellow = 25,  green = 50,  gray = 100 },
    ["silverleaf"]                      = { prof = "Herbalism", req = 1,   yellow = 25,  green = 50,  gray = 100 },
    ["earthroot"]                       = { prof = "Herbalism", req = 15,  yellow = 40,  green = 65,  gray = 115 },
    ["mageroyal"]                       = { prof = "Herbalism", req = 50,  yellow = 75,  green = 100, gray = 150 },
    ["briarthorn"]                      = { prof = "Herbalism", req = 70,  yellow = 95,  green = 120, gray = 170 },
    ["stranglekelp"]                    = { prof = "Herbalism", req = 85,  yellow = 110, green = 135, gray = 185 },
    ["bruiseweed"]                      = { prof = "Herbalism", req = 100, yellow = 125, green = 150, gray = 200 },
    ["wild steelbloom"]                 = { prof = "Herbalism", req = 115, yellow = 140, green = 165, gray = 215 },
    ["grave moss"]                      = { prof = "Herbalism", req = 120, yellow = 145, green = 170, gray = 220 },
    ["kingsblood"]                      = { prof = "Herbalism", req = 125, yellow = 150, green = 175, gray = 225 },
    ["liferoot"]                        = { prof = "Herbalism", req = 150, yellow = 175, green = 200, gray = 250 },
    ["fadeleaf"]                        = { prof = "Herbalism", req = 160, yellow = 185, green = 210, gray = 260 },
    ["goldthorn"]                       = { prof = "Herbalism", req = 170, yellow = 195, green = 220, gray = 270 },
    ["khadgar's whisker"]               = { prof = "Herbalism", req = 185, yellow = 210, green = 235, gray = 285 },
    ["wintersbite"]                     = { prof = "Herbalism", req = 195, yellow = 220, green = 245, gray = 295 },
    ["firebloom"]                       = { prof = "Herbalism", req = 205, yellow = 230, green = 255, gray = 305 },
    ["purple lotus"]                    = { prof = "Herbalism", req = 210, yellow = 235, green = 260, gray = 310 },
    ["arthas' tears"]                   = { prof = "Herbalism", req = 220, yellow = 245, green = 270, gray = 320 },
    ["sungrass"]                        = { prof = "Herbalism", req = 230, yellow = 255, green = 280, gray = 330 },
    ["blindweed"]                       = { prof = "Herbalism", req = 235, yellow = 260, green = 285, gray = 335 },
    ["ghost mushroom"]                  = { prof = "Herbalism", req = 245, yellow = 270, green = 295, gray = 345 },
    ["gromsblood"]                      = { prof = "Herbalism", req = 250, yellow = 275, green = 300, gray = 350 },
    ["golden sansam"]                   = { prof = "Herbalism", req = 260, yellow = 285, green = 310, gray = 360 },
    ["dreamfoil"]                       = { prof = "Herbalism", req = 270, yellow = 295, green = 320, gray = 370 },
    ["mountain silversage"]             = { prof = "Herbalism", req = 280, yellow = 305, green = 330, gray = 380 },
    ["plaguebloom"]                     = { prof = "Herbalism", req = 285, yellow = 310, green = 335, gray = 385 },
    ["icecap"]                          = { prof = "Herbalism", req = 290, yellow = 315, green = 340, gray = 390 },
    ["black lotus"]                     = { prof = "Herbalism", req = 300, yellow = 325, green = 350, gray = 400 },
}

-- Get player's current skill rank for "Mining" or "Herbalism"
function G.GetGatheringSkill(profName)
    if not profName then return nil end
    local target = profName:lower()

    -- 1. Modern GetProfessions() API
    if _G.GetProfessions and _G.GetProfessionInfo then
        local profs = { _G.GetProfessions() }
        for _, idx in ipairs(profs) do
            if idx then
                local name, _, skillLevel, maxSkillLevel = _G.GetProfessionInfo(idx)
                if name and name:lower() == target then
                    return skillLevel, maxSkillLevel
                end
            end
        end
    end

    -- 2. Classic GetSkillLineInfo() API
    if _G.GetNumSkillLines and _G.GetSkillLineInfo then
        for i = 1, _G.GetNumSkillLines() do
            local skillName, isHeader, _, skillRank, _, _, skillMaxRank = _G.GetSkillLineInfo(i)
            if not isHeader and skillName and skillName:lower() == target then
                return skillRank, skillMaxRank
            end
        end
    end

    return nil
end

function G.GetNodeInfo(nodeName)
    if not nodeName or (_G.issecretvalue and _G.issecretvalue(nodeName)) or nodeName == "" then return nil end
    local key = nodeName:match("^%s*(.-)%s*$"):lower()
    return NODES[key]
end

-- Hook GameTooltip to display gathering skill thresholds for world nodes
local hooked = false
function G.HookTooltip()
    if hooked or not _G.GameTooltip then return end
    hooked = true

    local function TryAddNodeLines(tooltip)
        if _G.MyCraftingDB and _G.MyCraftingDB.options and _G.MyCraftingDB.options.showGatheringTooltips == false then
            return
        end
        if tooltip.MyCraftingNodeAdded then return end
        local line1 = _G["GameTooltipTextLeft1"]
        if not line1 then return end

        local name = line1:GetText()
        if not name or (_G.issecretvalue and _G.issecretvalue(name)) or name == "" then return end
        if tooltip.MyCraftingCheckedText == name then return end
        tooltip.MyCraftingCheckedText = name

        local node = G.GetNodeInfo(name)
        if not node then return end

        -- Avoid showing on inventory items (only world objects / nodes without an item link)
        if tooltip.GetItem then
            local _, itemLink = tooltip:GetItem()
            if itemLink then return end
        end

        tooltip.MyCraftingNodeAdded = true
        tooltip.MyCraftingLastText = name

        local curSkill, maxSkill = G.GetGatheringSkill(node.prof)

        tooltip:AddLine(" ")
        tooltip:AddLine(string.format("|cff33ff99MyCrafting — %s|r", node.prof))
        tooltip:AddLine(string.format(
            "|cffff8040%d|r / |cffffff00%d|r / |cff40c040%d|r / |cff808080%d|r  (Turns Gray at |cffffffff%d|r)",
            node.req, node.yellow, node.green, node.gray, node.gray
        ))

        if curSkill then
            if curSkill < node.req then
                tooltip:AddLine(string.format("|cffff2020Too Low (Requires %d, You: %d)|r", node.req, curSkill))
            elseif curSkill < node.yellow then
                tooltip:AddLine(string.format("|cffff8040Orange (100%% Skill-Up) — You: %d|r", curSkill))
            elseif curSkill < node.green then
                tooltip:AddLine(string.format("|cffffff00Yellow (High Chance) — You: %d|r", curSkill))
            elseif curSkill < node.gray then
                tooltip:AddLine(string.format("|cff40c040Green (Low Chance) — You: %d|r", curSkill))
            else
                tooltip:AddLine(string.format("|cff808080Gray (0%% Skill-Up) — You: %d|r", curSkill))
            end
        end

        tooltip:Show()
        tooltip.MyCraftingExpectedLines = tooltip:NumLines()
    end

    local function ClearNodeState(tooltip)
        tooltip.MyCraftingNodeAdded = nil
        tooltip.MyCraftingCheckedText = nil
        tooltip.MyCraftingLastText = nil
        tooltip.MyCraftingExpectedLines = nil
    end

    _G.GameTooltip:HookScript("OnShow", TryAddNodeLines)
    _G.GameTooltip:HookScript("OnUpdate", function(tooltip)
        if tooltip.MyCraftingNodeAdded then
            local line1 = _G["GameTooltipTextLeft1"]
            local text = line1 and line1:GetText()
            if _G.issecretvalue and _G.issecretvalue(text) then return end
            if tooltip:NumLines() < (tooltip.MyCraftingExpectedLines or 0) or text ~= tooltip.MyCraftingLastText then
                ClearNodeState(tooltip)
                TryAddNodeLines(tooltip)
            end
        else
            TryAddNodeLines(tooltip)
        end
    end)
    _G.GameTooltip:HookScript("OnTooltipCleared", ClearNodeState)
    _G.GameTooltip:HookScript("OnHide", ClearNodeState)
end
