-- UI.lua: Side panel dock, Skillet-style difficulty bar, and controls for ProfessionsFrame & TradeSkillFrame.
local ADDON_NAME, NS = ...
local UI = {}
NS.UI = UI

local C = NS.Compat
local V = NS.VendorDB
local Q = NS.Queue

local PANEL_WIDTH = 280
local NUM_ROWS = 14
local ROW_HEIGHT = 26

local sidePanel = nil
local activeTab = "queue" -- "queue" or "shopping"
local currentParent = nil
local skillBar = nil

-- ---------------------------------------------------------------------------
-- Safe Backdrop Helper
-- ---------------------------------------------------------------------------
local function SetDialogBackdrop(frame)
    if not frame.SetBackdrop then
        if _G.BackdropTemplateMixin and _G.Mixin then
            _G.Mixin(frame, _G.BackdropTemplateMixin)
        end
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

-- ---------------------------------------------------------------------------
-- Make Default Frames Movable (ProfessionsFrame / TradeSkillFrame)
-- ---------------------------------------------------------------------------
function UI.MakeFrameMovable(frame)
    if not frame or frame.MyCraftingMovable then return end
    frame.MyCraftingMovable = true

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    local titleContainer = frame.TitleContainer or frame
    titleContainer:EnableMouse(true)
    titleContainer:RegisterForDrag("LeftButton")

    titleContainer:HookScript("OnDragStart", function()
        frame:StartMoving()
    end)
    titleContainer:HookScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        -- Re-check side panel clamping after moving
        if sidePanel and sidePanel:IsShown() and not sidePanel.userDragged then
            UI.PositionSidePanel(frame)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Smart Side Panel Positioning
-- ---------------------------------------------------------------------------
function UI.PositionSidePanel(parent)
    if not sidePanel or not parent then return end

    -- If user moved the side panel, respect their saved coordinates
    if _G.MyCraftingDB and _G.MyCraftingDB.sidePanelPos and sidePanel.userDragged then
        local p = _G.MyCraftingDB.sidePanelPos
        sidePanel:ClearAllPoints()
        sidePanel:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
        return
    end

    local screenWidth = (UIParent and UIParent:GetWidth()) or GetScreenWidth() or 1920
    local parentRight = parent:GetRight() or 0

    sidePanel:ClearAllPoints()

    -- If docking to the right would go off-screen, dock to the LEFT of the window
    if (parentRight + PANEL_WIDTH + 50) > screenWidth then
        sidePanel:SetPoint("TOPRIGHT", parent, "TOPLEFT", -8, -10)
    else
        local isProfFrame = (_G.ProfessionsFrame and parent == _G.ProfessionsFrame)
        local offsetX = isProfFrame and 44 or 4
        sidePanel:SetPoint("TOPLEFT", parent, "TOPRIGHT", offsetX, -10)
    end
end

-- ---------------------------------------------------------------------------
-- Skillet-Style Recipe Difficulty Progression Bar
-- ---------------------------------------------------------------------------
function UI.CreateOrUpdateSkillBar(parent)
    if _G.MyCraftingDB and _G.MyCraftingDB.options and _G.MyCraftingDB.options.showSkillBar == false then
        if skillBar then skillBar:Hide() end
        return
    end
    local recipe = C.GetSelectedRecipe()
    if not recipe then
        if skillBar then skillBar:Hide() end
        return
    end

    local cp = parent.CraftingPage
    local schematicFrame = cp and (cp.SchematicForm or cp.Schematic)
    local anchorTo = (schematicFrame and (schematicFrame.Name or schematicFrame.RecipeName or schematicFrame.OutputIcon)) or _G.TradeSkillSkillName

    if not skillBar then
        skillBar = CreateFrame("Frame", "MyCraftingSkillBar", schematicFrame or parent, "BackdropTemplate")
        skillBar:SetSize(240, 28)

        -- Subtle border around the bar
        local barBorder = CreateFrame("Frame", nil, skillBar, "BackdropTemplate")
        barBorder:SetSize(242, 14)
        barBorder:SetPoint("TOPLEFT", skillBar, "TOPLEFT", -1, 1)
        if not barBorder.SetBackdrop and _G.BackdropTemplateMixin and _G.Mixin then
            _G.Mixin(barBorder, _G.BackdropTemplateMixin)
        end
        if barBorder.SetBackdrop then
            barBorder:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8,
            })
            barBorder:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
        end

        -- Background bar
        local bg = skillBar:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(240, 12)
        bg:SetPoint("TOPLEFT", skillBar, "TOPLEFT", 0, 0)
        bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)
        skillBar.bg = bg

        -- 4 Colored Difficulty Segments: Orange, Yellow, Green, Gray
        local segOrange = skillBar:CreateTexture(nil, "ARTWORK")
        segOrange:SetHeight(12)
        segOrange:SetPoint("LEFT", bg, "LEFT", 0, 0)
        segOrange:SetColorTexture(0.95, 0.45, 0.10, 0.9)
        skillBar.segOrange = segOrange

        local segYellow = skillBar:CreateTexture(nil, "ARTWORK")
        segYellow:SetHeight(12)
        segYellow:SetPoint("LEFT", segOrange, "RIGHT", 0, 0)
        segYellow:SetColorTexture(0.95, 0.85, 0.10, 0.9)
        skillBar.segYellow = segYellow

        local segGreen = skillBar:CreateTexture(nil, "ARTWORK")
        segGreen:SetHeight(12)
        segGreen:SetPoint("LEFT", segYellow, "RIGHT", 0, 0)
        segGreen:SetColorTexture(0.20, 0.80, 0.20, 0.9)
        skillBar.segGreen = segGreen

        local segGray = skillBar:CreateTexture(nil, "ARTWORK")
        segGray:SetHeight(12)
        segGray:SetPoint("LEFT", segGreen, "RIGHT", 0, 0)
        segGray:SetColorTexture(0.45, 0.45, 0.45, 0.9)
        skillBar.segGray = segGray

        -- Numbers overlaid on the bar with dark shadow for crisp readability
        local barText = skillBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        barText:SetPoint("CENTER", bg, "CENTER", 0, 0)
        barText:SetShadowOffset(1, -1)
        barText:SetShadowColor(0, 0, 0, 1)
        skillBar.barText = barText

        -- Status Line below the bar (e.g. "Orange (100%) - Turns Gray at 185")
        local statusText = skillBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statusText:SetPoint("TOPLEFT", bg, "BOTTOMLEFT", 0, -2)
        skillBar.statusText = statusText

        -- Current Skill Needle / Pip (crisp texture instead of Unicode glyph)
        local cursor = skillBar:CreateTexture(nil, "OVERLAY")
        cursor:SetSize(2, 16)
        cursor:SetColorTexture(1, 1, 1, 1)
        skillBar.cursor = cursor

        -- Tooltip on hover
        skillBar:EnableMouse(true)
        skillBar:SetScript("OnEnter", function(self)
            if self.data then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.data.name .. " — Skill Difficulty", 1, 1, 1)
                GameTooltip:AddLine(string.format("|cffff8040Orange:|r  %d - %d  (100%% Skill-Up)", self.data.orange, math.max(self.data.orange, self.data.yellow - 1)))
                GameTooltip:AddLine(string.format("|cffffff00Yellow:|r  %d - %d  (High Chance)", self.data.yellow, math.max(self.data.yellow, self.data.green - 1)))
                GameTooltip:AddLine(string.format("|cff40c040Green:|r   %d - %d  (Low Chance)", self.data.green, math.max(self.data.green, self.data.gray - 1)))
                GameTooltip:AddLine(string.format("|cff808080Gray:|r    %d+  (0%% Chance — Obsolete)", self.data.gray))
                GameTooltip:AddLine(" ")
                local profName, curSkill, maxSkill = C.GetProfessionInfo()
                GameTooltip:AddLine(string.format("Your %s: |cffffffff%d / %d|r", profName, curSkill, maxSkill), 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end
        end)
        skillBar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Position cleanly to the right of the circular icon, under Name/Requires
    skillBar:ClearAllPoints()
    if schematicFrame then
        skillBar:SetPoint("TOPLEFT", schematicFrame, "TOPLEFT", 82, -62)
    elseif anchorTo then
        skillBar:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -18)
    else
        skillBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 440, -100)
    end

    local profName, curSkill = C.GetProfessionInfo()
    curSkill = curSkill or 0

    -- Calculate threshold numbers
    local orange, yellow, green, gray = C.GetRecipeDifficultyThresholds(recipe.id, curSkill, recipe.diffLevel)
    if not orange or not gray or gray <= orange then
        skillBar:Hide()
        return
    end

    local TOTAL_WIDTH = 240
    local GRAY_CAP = 28
    local activeWidth = TOTAL_WIDTH - GRAY_CAP
    local totalSpan = math.max(1, gray - orange)

    local orangeWidth = math.max(18, math.floor(((yellow - orange) / totalSpan) * activeWidth))
    local yellowWidth = math.max(18, math.floor(((green - yellow) / totalSpan) * activeWidth))
    local greenWidth = math.max(18, activeWidth - orangeWidth - yellowWidth)
    local grayWidth = TOTAL_WIDTH - (orangeWidth + yellowWidth + greenWidth)

    skillBar.segOrange:SetWidth(orangeWidth)
    skillBar.segYellow:SetWidth(yellowWidth)
    skillBar.segGreen:SetWidth(greenWidth)
    skillBar.segGray:SetWidth(grayWidth)

    -- Overlaid numbers
    skillBar.barText:SetText(string.format("%d      %d      %d      %d", orange, yellow, green, gray))

    -- Status label using actual recipe difficulty so it always matches the list
    local diff = recipe.diffLevel
    local stateMsg = ""
    if diff == 4 or (not diff and curSkill < yellow) then
        stateMsg = string.format("|cffff8040Orange (100%% Skill-Up)|r — Turns Gray at |cffffffff%d|r", gray)
    elseif diff == 3 or (not diff and curSkill < green) then
        stateMsg = string.format("|cffffff00Yellow (High Chance)|r — Turns Gray at |cffffffff%d|r", gray)
    elseif diff == 2 or (not diff and curSkill < gray) then
        stateMsg = string.format("|cff40c040Green (Low Chance)|r — Turns Gray at |cffffffff%d|r", gray)
    else
        stateMsg = string.format("|cff808080Gray (0%% Skill-Up — Obsolete at %d)|r", gray)
    end
    skillBar.statusText:SetText(stateMsg)

    -- Cursor position for current skill
    local ratio = math.min(1, math.max(0, (curSkill - orange) / totalSpan))
    local cursorX = math.floor(ratio * activeWidth)
    skillBar.cursor:ClearAllPoints()
    skillBar.cursor:SetPoint("CENTER", skillBar.bg, "LEFT", cursorX, 0)

    skillBar.data = {
        name = recipe.name,
        orange = orange,
        yellow = yellow,
        green = green,
        gray = gray,
    }

    skillBar:Show()
end

-- ---------------------------------------------------------------------------
-- Create or Retrieve the Side Panel Dock
-- ---------------------------------------------------------------------------
function UI.GetSidePanel(parent)
    if sidePanel then
        if parent and sidePanel:GetParent() ~= parent then
            sidePanel:SetParent(parent)
            currentParent = parent
            UI.PositionSidePanel(parent)
            local h = (parent.GetHeight and parent:GetHeight()) or 490
            if h > 200 then
                sidePanel:SetHeight(h - 10)
            end
        end
        return sidePanel
    end

    parent = parent or _G.ProfessionsFrame or _G.TradeSkillFrame or _G.CraftFrame or UIParent
    currentParent = parent

    sidePanel = CreateFrame("Frame", "MyCraftingSidePanel", parent, "BackdropTemplate")
    sidePanel:SetWidth(PANEL_WIDTH)
    local initialHeight = (parent.GetHeight and parent:GetHeight()) or 490
    if initialHeight < 200 then initialHeight = 490 end
    sidePanel:SetHeight(initialHeight - 10)

    UI.PositionSidePanel(parent)
    SetDialogBackdrop(sidePanel)
    sidePanel:SetFrameStrata("DIALOG")
    sidePanel:EnableMouse(true)
    sidePanel:SetMovable(true)
    sidePanel:SetClampedToScreen(true)

    -- Drag Header Bar
    local dragBar = CreateFrame("Frame", nil, sidePanel)
    dragBar:SetSize(PANEL_WIDTH - 30, 24)
    dragBar:SetPoint("TOPLEFT", sidePanel, "TOPLEFT", 4, -4)
    dragBar:EnableMouse(true)
    dragBar:RegisterForDrag("LeftButton")
    dragBar:SetScript("OnDragStart", function()
        sidePanel:StartMoving()
    end)
    dragBar:SetScript("OnDragStop", function()
        sidePanel:StopMovingOrSizing()
        sidePanel.userDragged = true
        local point, _, relPoint, x, y = sidePanel:GetPoint()
        _G.MyCraftingDB = _G.MyCraftingDB or {}
        _G.MyCraftingDB.sidePanelPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    -- Header / Title
    local title = dragBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", dragBar, "LEFT", 8, 0)
    title:SetText("|cff33ff99MyCrafting|r")
    sidePanel.title = title

    local dragHint = dragBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dragHint:SetPoint("LEFT", title, "RIGHT", 6, 0)
    dragHint:SetText("(drag)")

    -- Close (collapse) side panel button
    local closeBtn = CreateFrame("Button", nil, sidePanel, "UIPanelCloseButton")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", sidePanel, "TOPRIGHT", -4, -6)
    closeBtn:SetScript("OnClick", function()
        sidePanel:Hide()
        if _G.MyCraftingDB and _G.MyCraftingDB.options then
            _G.MyCraftingDB.options.sidePanelOpen = false
        end
        if currentParent and currentParent.MyCraftingSideTab then
            currentParent.MyCraftingSideTab:SetText("Queue >>")
        end
    end)
    sidePanel.closeBtn = closeBtn

    -- Config button
    local configBtn = CreateFrame("Button", nil, sidePanel, "UIPanelButtonTemplate")
    configBtn:SetSize(48, 18)
    configBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    configBtn:SetText("Config")
    configBtn:SetScript("OnClick", function()
        if NS.Options and NS.Options.Toggle then
            NS.Options.Toggle()
        end
    end)
    sidePanel.configBtn = configBtn

    -- Tabs: [Queue (N)] / [Shopping]
    local tabQueue = CreateFrame("Button", nil, sidePanel, "UIPanelButtonTemplate")
    tabQueue:SetSize(126, 22)
    tabQueue:SetPoint("TOPLEFT", dragBar, "BOTTOMLEFT", 4, -6)
    tabQueue:SetText("Craft Queue")
    tabQueue:SetScript("OnClick", function()
        activeTab = "queue"
        UI.Refresh()
    end)
    sidePanel.tabQueue = tabQueue

    local tabShopping = CreateFrame("Button", nil, sidePanel, "UIPanelButtonTemplate")
    tabShopping:SetSize(126, 22)
    tabShopping:SetPoint("LEFT", tabQueue, "RIGHT", 4, 0)
    tabShopping:SetText("Shopping List")
    tabShopping:SetScript("OnClick", function()
        activeTab = "shopping"
        UI.Refresh()
    end)
    sidePanel.tabShopping = tabShopping

    -- Scroll Area
    local scrollFrame = CreateFrame("ScrollFrame", "MyCraftingSideScroll", sidePanel, "FauxScrollFrameTemplate")
    scrollFrame:SetSize(236, 370)
    scrollFrame:SetPoint("TOPLEFT", tabQueue, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UI.Refresh)
    end)
    sidePanel.scrollFrame = scrollFrame

    -- Rows
    sidePanel.rows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Frame", nil, sidePanel)
        row:SetSize(248, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", tabQueue, "BOTTOMLEFT", 0, -6 - (i - 1) * ROW_HEIGHT)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.icon = icon

        local iconBtn = CreateFrame("Button", nil, row)
        iconBtn:SetAllPoints(icon)
        row.iconBtn = iconBtn

        local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        text:SetPoint("RIGHT", row, "RIGHT", -54, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        row.text = text

        -- Plus button (for queue)
        local btnPlus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnPlus:SetSize(16, 16)
        btnPlus:SetPoint("RIGHT", row, "RIGHT", -34, 0)
        btnPlus:SetText("+")
        btnPlus:SetScript("OnClick", function()
            if row.queueIndex then
                local list = Q.GetList()
                local item = list[row.queueIndex]
                if item then
                    local delta = _G.IsShiftKeyDown() and 5 or 1
                    Q.SetCount(row.queueIndex, item.count + delta)
                end
            end
        end)
        row.btnPlus = btnPlus

        -- Minus button (for queue)
        local btnMinus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnMinus:SetSize(16, 16)
        btnMinus:SetPoint("RIGHT", row, "RIGHT", -18, 0)
        btnMinus:SetText("-")
        btnMinus:SetScript("OnClick", function()
            if row.queueIndex then
                local list = Q.GetList()
                local item = list[row.queueIndex]
                if item then
                    local delta = _G.IsShiftKeyDown() and 5 or 1
                    Q.SetCount(row.queueIndex, item.count - delta)
                end
            end
        end)
        row.btnMinus = btnMinus

        -- Remove button (for queue)
        local btnRemove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        btnRemove:SetSize(18, 18)
        btnRemove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        btnRemove:SetScript("OnClick", function()
            if row.queueIndex then
                Q.Remove(row.queueIndex)
            end
        end)
        row.btnRemove = btnRemove

        row:Hide()
        table.insert(sidePanel.rows, row)
    end

    -- Bottom Queue Controls
    local queueControls = CreateFrame("Frame", nil, sidePanel)
    queueControls:SetSize(256, 36)
    queueControls:SetPoint("BOTTOMLEFT", sidePanel, "BOTTOMLEFT", 12, 10)
    sidePanel.queueControls = queueControls

    local btnRunQueue = CreateFrame("Button", nil, queueControls, "UIPanelButtonTemplate")
    btnRunQueue:SetSize(116, 26)
    btnRunQueue:SetPoint("LEFT", queueControls, "LEFT", 0, 0)
    btnRunQueue:SetText("|cff00ff00Craft Queue|r")
    btnRunQueue:SetScript("OnClick", function()
        if Q.IsRunning() then
            if Q.IsPaused() then
                Q.Resume()
            else
                Q.Pause()
            end
        else
            Q.Start()
        end
        UI.UpdateQueueButtons()
    end)
    sidePanel.btnRunQueue = btnRunQueue

    local btnClearQueue = CreateFrame("Button", nil, queueControls, "UIPanelButtonTemplate")
    btnClearQueue:SetSize(60, 26)
    btnClearQueue:SetPoint("LEFT", btnRunQueue, "RIGHT", 6, 0)
    btnClearQueue:SetText("Clear")
    btnClearQueue:SetScript("OnClick", function()
        Q.Clear()
    end)
    sidePanel.btnClearQueue = btnClearQueue

    -- Bottom Shopping Controls
    local shopControls = CreateFrame("Frame", nil, sidePanel)
    shopControls:SetSize(256, 36)
    shopControls:SetPoint("BOTTOMLEFT", sidePanel, "BOTTOMLEFT", 12, 10)
    shopControls:Hide()
    sidePanel.shopControls = shopControls

    local btnShareChat = CreateFrame("Button", nil, shopControls, "UIPanelButtonTemplate")
    btnShareChat:SetSize(110, 26)
    btnShareChat:SetPoint("LEFT", shopControls, "LEFT", 0, 0)
    btnShareChat:SetText("Share Chat")
    btnShareChat:SetScript("OnClick", function()
        local channel = "SELF"
        if _G.IsInRaid and _G.IsInRaid() then channel = "RAID"
        elseif _G.IsInGroup and _G.IsInGroup() then channel = "PARTY"
        end
        Q.ShareToChat(channel)
    end)

    local btnBuyVendor = CreateFrame("Button", nil, shopControls, "UIPanelButtonTemplate")
    btnBuyVendor:SetSize(110, 26)
    btnBuyVendor:SetPoint("LEFT", btnShareChat, "RIGHT", 6, 0)
    btnBuyVendor:SetText("Buy Vendor")
    btnBuyVendor:SetScript("OnClick", function()
        local sList = Q.GetShoppingList()
        local matches, totalCost = V.ScanMerchantForShoppingList(sList)
        if #matches == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Merchant does not sell any needed shopping list reagents (or merchant window not open).")
        else
            local count = V.BuyItems(matches)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99MyCrafting:|r Purchased %d reagent(s) for %s.", count, C.FormatMoney(totalCost)))
            UI.Refresh()
        end
    end)

    Q.RegisterListener(function(event)
        UI.Refresh()
        UI.UpdateQueueButtons()
    end)

    return sidePanel
end

-- ---------------------------------------------------------------------------
-- Injected [+ Queue] Button on ProfessionsFrame & TradeSkillFrame
-- ---------------------------------------------------------------------------
function UI.InjectQueueButton(parent)
    if not parent or parent.MyCraftingQueueBtn then return end

    local cp = parent.CraftingPage
    local btnQueue = CreateFrame("Button", "MyCraftingQueueButton", cp or parent, "UIPanelButtonTemplate")
    btnQueue:SetSize(74, 22)

    -- Anchor above CreateAllButton cleanly without overlapping recipe list
    if cp and cp.CreateAllButton then
        btnQueue:SetPoint("BOTTOMLEFT", cp.CreateAllButton, "TOPLEFT", 64, 6)
    elseif _G.TradeSkillCreateAllButton then
        btnQueue:SetPoint("BOTTOMLEFT", _G.TradeSkillCreateAllButton, "TOPLEFT", 64, 6)
    else
        btnQueue:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -175, 14)
    end

    -- Dedicated Queue Quantity EditBox (works even when you have 0 mats!)
    local qtyBox = CreateFrame("EditBox", "MyCraftingQueueQtyBox", cp or parent, "InputBoxTemplate")
    qtyBox:SetSize(32, 20)
    qtyBox:SetPoint("RIGHT", btnQueue, "LEFT", -6, 0)
    qtyBox:SetAutoFocus(false)
    qtyBox:SetNumeric(true)
    qtyBox:SetNumber(1)
    qtyBox:SetJustifyH("CENTER")
    qtyBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        btnQueue:Click()
    end)
    qtyBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    parent.MyCraftingQueueQtyBox = qtyBox

    btnQueue:SetText("+ Queue")
    btnQueue:SetScript("OnClick", function()
        local recipe = C.GetSelectedRecipe()
        if not recipe then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r No craftable recipe selected.")
            return
        end
        local qBoxCount = qtyBox:GetNumber() or 1
        local blizzCount = C.GetSelectedCount() or 1
        local count = (qBoxCount > 1) and qBoxCount or blizzCount
        if count < 1 then count = 1 end

        Q.Add(recipe, count)

        local panel = UI.GetSidePanel(parent)
        panel:Show()
        activeTab = "queue"
        UI.Refresh()
        if parent.MyCraftingSideTab then
            parent.MyCraftingSideTab:SetText("<<")
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99MyCrafting:|r Queued %dx %s.", count, recipe.name))
        C.PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    end)
    btnQueue:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Add to Crafting Queue", 1, 1, 1)
        GameTooltip:AddLine("Queues the currently selected recipe and count into the MyCrafting side panel.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnQueue:SetScript("OnLeave", function() GameTooltip:Hide() end)

    parent.MyCraftingQueueBtn = btnQueue

    local closeBtn = parent.CloseButton or _G.TradeSkillFrameCloseButton or _G.CraftFrameCloseButton
    local titleLevel = (parent.TitleContainer and parent.TitleContainer:GetFrameLevel() or parent:GetFrameLevel()) + 5

    -- Config Cog Button to the left of the [X] close button
    if not parent.MyCraftingCogBtn then
        local cogBtn = CreateFrame("Button", nil, parent)
        cogBtn:SetSize(20, 20)
        cogBtn:SetFrameLevel(titleLevel)
        if closeBtn then
            cogBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
        else
            cogBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, -5)
        end
        cogBtn:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
        cogBtn:SetPushedTexture("Interface\\Buttons\\UI-OptionsButton")
        cogBtn:GetPushedTexture():SetTexCoord(0.06, 0.94, 0.06, 0.94)
        cogBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        cogBtn:SetScript("OnClick", function()
            if NS.Options and NS.Options.Toggle then
                NS.Options.Toggle()
            end
        end)
        cogBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("MyCrafting Options")
            GameTooltip:Show()
        end)
        cogBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        parent.MyCraftingCogBtn = cogBtn
    end

    -- Side Tab Button to Toggle Side Panel (to the left of the cog wheel)
    if not parent.MyCraftingSideTab then
        local sideTab = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        sideTab:SetSize(62, 20)
        sideTab:SetFrameLevel(titleLevel)
        sideTab:SetPoint("RIGHT", parent.MyCraftingCogBtn, "LEFT", -4, 0)
        sideTab:SetText("Queue >>")
        sideTab:SetScript("OnClick", function(self)
            local panel = UI.GetSidePanel(parent)
            if panel:IsShown() then
                panel:Hide()
                self:SetText("Queue >>")
                if _G.MyCraftingDB and _G.MyCraftingDB.options then
                    _G.MyCraftingDB.options.sidePanelOpen = false
                end
            else
                UI.PositionSidePanel(parent)
                panel:Show()
                self:SetText("<<")
                if _G.MyCraftingDB and _G.MyCraftingDB.options then
                    _G.MyCraftingDB.options.sidePanelOpen = true
                end
                UI.Refresh()
            end
        end)
        sideTab:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Toggle MyCrafting Queue & Shopping Panel")
            GameTooltip:Show()
        end)
        sideTab:SetScript("OnLeave", function() GameTooltip:Hide() end)
        parent.MyCraftingSideTab = sideTab
    end
end

-- ---------------------------------------------------------------------------
-- Enhance Tooltips with Bag/Bank counts and Sub-Recipe Navigation
-- ---------------------------------------------------------------------------
local tooltipHooked = false
function UI.HookTooltips()
    if tooltipHooked then return end
    tooltipHooked = true

    if _G.GameTooltip and _G.GameTooltip.SetRecipeReagentItem then
        hooksecurefunc(_G.GameTooltip, "SetRecipeReagentItem", function(self, recipeID, reagentIndex)
            if _G.MyCraftingDB and _G.MyCraftingDB.options and _G.MyCraftingDB.options.showReagentTooltips == false then
                return
            end
            local allRecipes, known = C.GetAllRecipes()
            local schematic = CTS and CTS.GetRecipeSchematic and CTS.GetRecipeSchematic(recipeID, false)
            if schematic and schematic.reagentSlotSchematics and schematic.reagentSlotSchematics[reagentIndex] then
                local slot = schematic.reagentSlotSchematics[reagentIndex]
                if slot.reagents and slot.reagents[1] then
                    local rID = slot.reagents[1].itemID
                    local rName = C.GetItemInfo(rID) or ""
                    local bankDB = _G.MyCraftingDB and _G.MyCraftingDB.bankInventory or {}
                    local bankCount = rID and bankDB[rID] or 0
                    local bagCount = C.GetItemCount(rID, false)

                    self:AddLine(" ")
                    self:AddLine(string.format("In Bags: |cffffffff%d|r  |  In Bank: |cffffffff%d|r", bagCount, bankCount), 0.7, 0.7, 0.7)

                    local isVendor, vCost = V.IsVendorReagent(rID, rName)
                    if isVendor then
                        self:AddLine(string.format("|cffffd100Sold by vendors (%s each)|r", C.FormatMoney(vCost)), 1, 0.8, 0)
                    end

                    local sub = known[rName:lower()]
                    if sub then
                        self:AddLine("|cff33ff99Sub-recipe available in profession|r", 0.2, 1.0, 0.5)
                    end
                    self:Show()
                end
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Update Side Panel Display
-- ---------------------------------------------------------------------------
function UI.Refresh()
    if not sidePanel or not sidePanel:IsShown() then return end

    local qCount = Q.GetCount()
    sidePanel.tabQueue:SetText(string.format("Queue (%d)", qCount))

    if activeTab == "queue" then
        sidePanel.tabQueue:LockHighlight()
        sidePanel.tabShopping:UnlockHighlight()
        sidePanel.queueControls:Show()
        sidePanel.shopControls:Hide()

        local qList = Q.GetList()
        local numItems = #qList
        FauxScrollFrame_Update(sidePanel.scrollFrame, numItems, NUM_ROWS, ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(sidePanel.scrollFrame)

        for i = 1, NUM_ROWS do
            local rowIndex = offset + i
            local row = sidePanel.rows[i]
            if rowIndex <= numItems then
                local item = qList[rowIndex]
                row.queueIndex = rowIndex
                row.icon:SetTexture(item.icon)
                row.text:SetText(string.format("%dx %s", item.count, item.name))
                row.btnPlus:Show()
                row.btnMinus:Show()
                row.btnRemove:Show()

                row.iconBtn:SetScript("OnEnter", function(self)
                    if item.itemLink then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink(item.itemLink)
                        GameTooltip:Show()
                    end
                end)
                row.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                row:Show()
            else
                row.queueIndex = nil
                row:Hide()
            end
        end
    else
        sidePanel.tabQueue:UnlockHighlight()
        sidePanel.tabShopping:LockHighlight()
        sidePanel.queueControls:Hide()
        sidePanel.shopControls:Show()

        local sList = Q.GetShoppingList()
        local numItems = #sList
        FauxScrollFrame_Update(sidePanel.scrollFrame, numItems, NUM_ROWS, ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(sidePanel.scrollFrame)

        for i = 1, NUM_ROWS do
            local rowIndex = offset + i
            local row = sidePanel.rows[i]
            if rowIndex <= numItems then
                local sItem = sList[rowIndex]
                row.queueIndex = nil
                row.icon:SetTexture(sItem.icon)
                local note = sItem.isVendor and " |cffffd100(V)|r" or ""

                if sItem.need > 0 then
                    row.text:SetText(string.format("|cffff5050%dx|r %s%s", sItem.need, sItem.name, note))
                else
                    row.text:SetText(string.format("|cff00ff00OK:|r %s", sItem.name))
                end

                row.btnPlus:Hide()
                row.btnMinus:Hide()
                row.btnRemove:Hide()

                row.iconBtn:SetScript("OnEnter", function(self)
                    if sItem.link then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink(sItem.link)
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(string.format("In Bags: %d  |  In Bank: %d", sItem.have, sItem.bank), 0.7, 0.7, 0.7)
                        if sItem.isVendor then
                            GameTooltip:AddLine(string.format("|cffffd100Sold by vendors (%s total)|r", C.FormatMoney(sItem.vendorCost)), 1, 0.8, 0)
                        end
                        GameTooltip:Show()
                    end
                end)
                row.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                row:Show()
            else
                row:Hide()
            end
        end
    end
end

function UI.UpdateQueueButtons()
    if not sidePanel then return end
    if Q.IsRunning() then
        if Q.IsPaused() then
            sidePanel.btnRunQueue:SetText("|cffffff00Resume|r")
        else
            sidePanel.btnRunQueue:SetText("|cffff5050Pause|r")
        end
    else
        sidePanel.btnRunQueue:SetText("|cff00ff00Craft Queue|r")
    end
end

-- ---------------------------------------------------------------------------
-- Attach to Default Frame
-- ---------------------------------------------------------------------------
function UI.AttachToDefaultFrame(parent)
    if not parent then return end
    currentParent = parent

    -- 1. Make the crafting window movable!
    UI.MakeFrameMovable(parent)

    -- 2. Inject Queue Button & Side Tab
    UI.InjectQueueButton(parent)

    -- 3. Hook Tooltips
    UI.HookTooltips()

    -- 4. Create & Update Skillet-style Difficulty Bar
    UI.CreateOrUpdateSkillBar(parent)

    -- Hook schematic selection update for modern ProfessionsFrame
    local cp = parent.CraftingPage
    if cp and not cp.MyCraftingDetailsHooked then
        cp.MyCraftingDetailsHooked = true
        local sf = cp.SchematicForm or cp.Schematic
        if sf then
            if sf.HookScript then
                sf:HookScript("OnShow", function()
                    UI.CreateOrUpdateSkillBar(parent)
                end)
            end
            if sf.Init then
                hooksecurefunc(sf, "Init", function(_, recipeInfo)
                    if type(recipeInfo) == "table" and recipeInfo.recipeID then
                        NS.lastSelectedRecipeID = recipeInfo.recipeID
                    elseif type(recipeInfo) == "number" then
                        NS.lastSelectedRecipeID = recipeInfo
                    end
                    UI.CreateOrUpdateSkillBar(parent)
                end)
            end
        end
        if cp.SelectRecipe then
            hooksecurefunc(cp, "SelectRecipe", function(_, recipeInfo)
                if type(recipeInfo) == "table" and recipeInfo.recipeID then
                    NS.lastSelectedRecipeID = recipeInfo.recipeID
                elseif type(recipeInfo) == "number" then
                    NS.lastSelectedRecipeID = recipeInfo
                end
                UI.CreateOrUpdateSkillBar(parent)
            end)
        end
    end

    -- 5. Open side panel
    local panel = UI.GetSidePanel(parent)
    local shouldOpen = true
    if _G.MyCraftingDB and _G.MyCraftingDB.options and _G.MyCraftingDB.options.sidePanelOpen == false then
        shouldOpen = false
    end

    if shouldOpen then
        UI.PositionSidePanel(parent)
        panel:Show()
        UI.Refresh()
        if parent.MyCraftingSideTab then
            parent.MyCraftingSideTab:SetText("<<")
        end
    else
        panel:Hide()
        if parent.MyCraftingSideTab then
            parent.MyCraftingSideTab:SetText("Queue >>")
        end
    end
end

function UI.HideSidePanel()
    if sidePanel then
        sidePanel:Hide()
    end
end

function UI.Toggle()
    local parent = _G.ProfessionsFrame or _G.TradeSkillFrame or _G.CraftFrame
    if parent and parent:IsShown() then
        local panel = UI.GetSidePanel(parent)
        if panel:IsShown() then
            panel:Hide()
            if parent.MyCraftingSideTab then
                parent.MyCraftingSideTab:SetText("Queue >>")
            end
        else
            UI.PositionSidePanel(parent)
            panel:Show()
            UI.Refresh()
            if parent.MyCraftingSideTab then
                parent.MyCraftingSideTab:SetText("<<")
            end
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MyCrafting:|r Open your profession window first.")
    end
end
