-- Options.lua: Graphical configuration window and Blizzard AddOns settings registration.
local ADDON_NAME, NS = ...
local Opt = {}
NS.Options = Opt

local UI = NS.UI
local Q = NS.Queue

local configFrame = nil
local checkboxes = {}

local OPTION_DEFS = {
    {
        key = "sidePanelOpen",
        label = "Auto-open Queue & Shopping side panel",
        tip = "Automatically show the MyCrafting side panel when you open a profession window.",
    },
    {
        key = "showSkillBar",
        label = "Show Skillet skill difficulty bar",
        tip = "Display the Orange / Yellow / Green / Gray skill progression bar on recipes.",
    },
    {
        key = "showGatheringTooltips",
        label = "Show Mining & Herbalism node tooltips",
        tip = "Show skill requirements and when nodes turn gray when hovering over herbs or veins.",
    },
    {
        key = "showReagentTooltips",
        label = "Show Bag / Bank / Vendor info on reagents",
        tip = "Append bag counts, cached bank counts, and NPC vendor prices to reagent tooltips.",
    },
    {
        key = "autoBuyVendor",
        label = "Auto-buy missing vendor reagents",
        tip = "Automatically purchase missing shopping list reagents when opening a merchant.",
    },
    {
        key = "playQueueSound",
        label = "Play sound when queue finishes",
        tip = "Play a completion sound when all queued crafts are done.",
    },
}

local function ApplyBackdrop(frame)
    if not frame.SetBackdrop and _G.BackdropTemplateMixin and _G.Mixin then
        _G.Mixin(frame, _G.BackdropTemplateMixin)
    end
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 20,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        })
        if frame.SetBackdropColor then
            frame:SetBackdropColor(0.04, 0.04, 0.06, 0.96)
        end
    end
end

local function SyncCheckboxes()
    local opts = _G.MyCraftingDB and _G.MyCraftingDB.options
    if not opts then return end
    for key, cb in pairs(checkboxes) do
        cb:SetChecked(opts[key] == true)
    end
end

function Opt.CreateFrame()
    if configFrame then return configFrame end

    configFrame = CreateFrame("Frame", "MyCraftingOptionsFrame", UIParent, "BackdropTemplate")
    configFrame:SetSize(350, 310)
    configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    configFrame:SetFrameStrata("DIALOG")
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:SetClampedToScreen(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", configFrame.StartMoving)
    configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
    ApplyBackdrop(configFrame)
    configFrame:Hide()

    if _G.UISpecialFrames then
        table.insert(_G.UISpecialFrames, "MyCraftingOptionsFrame")
    end

    -- Title
    local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 16, -14)
    title:SetText("|cff33ff99MyCrafting|r Options")

    local closeBtn = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -4, -4)

    -- Checkboxes
    local yOffset = -46
    for i, def in ipairs(OPTION_DEFS) do
        local cb = CreateFrame("CheckButton", "MyCraftingOptCB_" .. def.key, configFrame, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 16, yOffset)

        local label = cb.text or _G[cb:GetName() .. "Text"]
        if not label then
            label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        end
        label:SetText(def.label)

        cb:SetScript("OnClick", function(self)
            local checked = self:GetChecked() and true or false
            if _G.MyCraftingDB and _G.MyCraftingDB.options then
                _G.MyCraftingDB.options[def.key] = checked
            end

            -- Apply live UI updates
            if def.key == "showSkillBar" then
                local parent = _G.ProfessionsFrame or _G.TradeSkillFrame or _G.CraftFrame
                if parent and parent:IsShown() then
                    UI.CreateOrUpdateSkillBar(parent)
                end
            elseif def.key == "sidePanelOpen" then
                local parent = _G.ProfessionsFrame or _G.TradeSkillFrame or _G.CraftFrame
                if parent and parent:IsShown() then
                    local panel = UI.GetSidePanel(parent)
                    if checked then
                        UI.PositionSidePanel(parent)
                        panel:Show()
                        UI.Refresh()
                    else
                        panel:Hide()
                    end
                end
            end
        end)

        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(def.label, 1, 1, 1)
            GameTooltip:AddLine(def.tip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

        checkboxes[def.key] = cb
        yOffset = yOffset - 32
    end

    -- Bottom Action Buttons
    local btnReset = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    btnReset:SetSize(110, 24)
    btnReset:SetPoint("BOTTOMLEFT", configFrame, "BOTTOMLEFT", 16, 16)
    btnReset:SetText("Reset Positions")
    btnReset:SetScript("OnClick", function()
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
        SyncCheckboxes()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Window and side panel positions reset.")
    end)

    local btnClear = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    btnClear:SetSize(96, 24)
    btnClear:SetPoint("LEFT", btnReset, "RIGHT", 6, 0)
    btnClear:SetText("Clear Queue")
    btnClear:SetScript("OnClick", function()
        Q.Clear()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Crafting queue cleared.")
    end)

    local btnDone = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    btnDone:SetSize(80, 24)
    btnDone:SetPoint("BOTTOMRIGHT", configFrame, "BOTTOMRIGHT", -16, 16)
    btnDone:SetText("Close")
    btnDone:SetScript("OnClick", function()
        configFrame:Hide()
    end)

    configFrame:SetScript("OnShow", SyncCheckboxes)
    return configFrame
end

function Opt.Toggle()
    local frame = Opt.CreateFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        SyncCheckboxes()
        frame:Show()
    end
end

-- Register inside Blizzard's Esc -> Options -> AddOns panel
function Opt.RegisterBlizzardPanel()
    local panel = CreateFrame("Frame", "MyCraftingBlizzOptionsPanel")
    panel.name = "MyCrafting"

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cff33ff99MyCrafting|r")

    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Enhances the default crafting UI with a Queue, Shopping List, Skillet Skill Bar, and Gathering Tooltips.")

    local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openBtn:SetSize(180, 26)
    openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    openBtn:SetText("Open MyCrafting Options")
    openBtn:SetScript("OnClick", function()
        Opt.Toggle()
    end)

    if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
        local category = _G.Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        _G.Settings.RegisterAddOnCategory(category)
    elseif _G.InterfaceOptions_AddCategory then
        _G.InterfaceOptions_AddCategory(panel)
    end
end
