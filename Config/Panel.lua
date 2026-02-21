--[[
    CooldownCompanion - Config/Panel
    Panel creation + lifecycle (CreateConfigPanel, RefreshConfigPanel, ToggleConfig, GetConfigFrame, SetupConfig).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

-- Imports from earlier Config/ files
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local COLUMN_PADDING = ST._COLUMN_PADDING
local TryReceiveCursorDrop = ST._TryReceiveCursorDrop
local BuildAutocompleteCache = ST._BuildAutocompleteCache
local RefreshColumn1 = ST._RefreshColumn1
local RefreshColumn2 = ST._RefreshColumn2
local RefreshColumn3 = ST._RefreshColumn3
local RefreshProfileBar = ST._RefreshProfileBar

-- File-local aliases for buttonSettingsScroll (only needed within this file)
local buttonSettingsScroll

------------------------------------------------------------------------
-- Main Panel Creation
------------------------------------------------------------------------
local function CreateConfigPanel()
    if CS.configFrame then return CS.configFrame end

    -- Main AceGUI Frame
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Cooldown Companion")
    frame:SetStatusText("")
    frame:SetWidth(1304)
    frame:SetHeight(700)
    frame:SetLayout(nil) -- manual positioning

    -- Store the raw frame for raw child parenting
    local content = frame.frame
    -- Get the content area (below the title bar)
    local contentFrame = frame.content

    -- Hide AceGUI's default sizer grips (replaced by custom resize grip below)
    if frame.sizer_se then
        frame.sizer_se:Hide()
    end
    if frame.sizer_s then
        frame.sizer_s:Hide()
    end
    if frame.sizer_e then
        frame.sizer_e:Hide()
    end

    -- Custom resize grip — expand freely, shrink horizontally up to 30% (min 913px)
    content:SetResizable(true)
    content:SetResizeBounds(913, 400)

    local resizeGrip = CreateFrame("Button", nil, content)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -1, 1)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    resizeGrip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            content:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeGrip:SetScript("OnMouseUp", function(self)
        content:StopMovingOrSizing()
    end)

    -- Hide the AceGUI status bar and add version text at bottom-right
    if frame.statustext then
        local statusbg = frame.statustext:GetParent()
        if statusbg then statusbg:Hide() end
    end
    local versionText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 20, 25)
    versionText:SetText("v1.7  |  " .. (CooldownCompanion.db:GetCurrentProfile() or "Default"))
    versionText:SetTextColor(1, 0.82, 0)

    -- Prevent AceGUI from releasing on close - just hide
    frame:SetCallback("OnClose", function(widget)
        widget.frame:Hide()
    end)

    -- Cleanup on hide (covers ESC, X button, OnClose, ToggleConfig)
    -- isCollapsing flag prevents cleanup when collapsing (vs truly closing)
    local isCollapsing = false
    content:HookScript("OnHide", function()
        if isCollapsing then return end
        CooldownCompanion:ClearAllProcGlowPreviews()
        CooldownCompanion:ClearAllAuraGlowPreviews()
        CooldownCompanion:ClearAllPandemicPreviews()
        CooldownCompanion:StopCastBarPreview()
        CloseDropDownMenus()
        CS.HideAutocomplete()
    end)

    -- ESC to close support (keyboard handler — more reliable than UISpecialFrames)
    content:EnableKeyboard(true)
    content:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and CooldownCompanion.db.profile.escClosesConfig then
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(false)
            end
            self:Hide()
        elseif not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- Permanently hide the AceGUI bottom close button
    for _, child in ipairs({content:GetChildren()}) do
        if child:GetObjectType() == "Button" and child:GetText() == CLOSE then
            child:Hide()
            child:SetScript("OnShow", child.Hide)
            break
        end
    end

    local isMinimized = false
    local fullHeight = 700
    local savedFrameRight, savedFrameTop
    local savedOffsetRight, savedOffsetTop

    -- Title bar buttons: [Gear] [Collapse] [X] at top-right

    -- X (close) button — rightmost
    local closeBtn = CreateFrame("Button", nil, content)
    closeBtn:SetSize(19, 19)
    closeBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -5)
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetAtlas("common-icon-redx")
    closeIcon:SetAllPoints()
    closeBtn:SetHighlightAtlas("common-icon-redx")
    closeBtn:GetHighlightTexture():SetAlpha(0.3)
    closeBtn:SetScript("OnClick", function()
        content:Hide()
    end)

    -- Collapse button — left of X
    local collapseBtn = CreateFrame("Button", nil, content)
    collapseBtn:SetSize(15, 15)
    collapseBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    local collapseIcon = collapseBtn:CreateTexture(nil, "ARTWORK")
    collapseIcon:SetAtlas("common-icon-minus")
    collapseIcon:SetAllPoints()
    collapseBtn:SetHighlightAtlas("common-icon-minus")
    collapseBtn:GetHighlightTexture():SetAlpha(0.3)

    -- Frame Anchoring button — leftmost in cluster
    local frameAnchoringBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    frameAnchoringBtn:SetSize(16, 16)
    local frameAnchoringIcon = frameAnchoringBtn:CreateTexture(nil, "ARTWORK")
    frameAnchoringIcon:SetAtlas("squad_size_duos")
    frameAnchoringIcon:SetAllPoints()
    frameAnchoringBtn:SetHighlightAtlas("squad_size_duos")
    frameAnchoringBtn:GetHighlightTexture():SetAlpha(0.3)

    -- Resource Bar button — left of Cast Bar button
    local resourceBarBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    resourceBarBtn:SetSize(16, 16)
    local resourceBarIcon = resourceBarBtn:CreateTexture(nil, "ARTWORK")
    resourceBarIcon:SetAtlas("UF-Essence-Icon-Active")
    resourceBarIcon:SetAllPoints()
    resourceBarBtn:SetHighlightAtlas("UF-Essence-Icon-Active")
    resourceBarBtn:GetHighlightTexture():SetAlpha(0.3)

    -- Cast Bar button — left of Gear
    local castBarBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    castBarBtn:SetSize(16, 16)
    local castBarIcon = castBarBtn:CreateTexture(nil, "ARTWORK")
    castBarIcon:SetAtlas("icons_16x16_magic")
    castBarIcon:SetAllPoints()
    castBarBtn:SetHighlightAtlas("icons_16x16_magic")
    castBarBtn:GetHighlightTexture():SetAlpha(0.3)

    -- Highlight functions (defined after all buttons exist so closures can capture all)
    local frameAnchoringBtnBorder = nil
    local resourceBarBtnBorder = nil
    local castBarBtnBorder = nil

    local function UpdateFrameAnchoringBtnHighlight()
        if CS.frameAnchoringPanelActive then
            if not frameAnchoringBtnBorder then
                frameAnchoringBtnBorder = frameAnchoringBtn:CreateTexture(nil, "OVERLAY")
                frameAnchoringBtnBorder:SetPoint("TOPLEFT", -1, 1)
                frameAnchoringBtnBorder:SetPoint("BOTTOMRIGHT", 1, -1)
                frameAnchoringBtnBorder:SetColorTexture(0.85, 0.65, 0.0, 0.6)
            end
            frameAnchoringBtnBorder:Show()
        else
            if frameAnchoringBtnBorder then
                frameAnchoringBtnBorder:Hide()
            end
        end
    end

    local function UpdateResourceBarBtnHighlight()
        if CS.resourceBarPanelActive then
            if not resourceBarBtnBorder then
                resourceBarBtnBorder = resourceBarBtn:CreateTexture(nil, "OVERLAY")
                resourceBarBtnBorder:SetPoint("TOPLEFT", -1, 1)
                resourceBarBtnBorder:SetPoint("BOTTOMRIGHT", 1, -1)
                resourceBarBtnBorder:SetColorTexture(0.85, 0.65, 0.0, 0.6)
            end
            resourceBarBtnBorder:Show()
        else
            if resourceBarBtnBorder then
                resourceBarBtnBorder:Hide()
            end
        end
    end

    local function UpdateCastBarBtnHighlight()
        if CS.castBarPanelActive then
            if not castBarBtnBorder then
                castBarBtnBorder = castBarBtn:CreateTexture(nil, "OVERLAY")
                castBarBtnBorder:SetPoint("TOPLEFT", -1, 1)
                castBarBtnBorder:SetPoint("BOTTOMRIGHT", 1, -1)
                castBarBtnBorder:SetColorTexture(0.85, 0.65, 0.0, 0.6)
            end
            castBarBtnBorder:Show()
        else
            if castBarBtnBorder then
                castBarBtnBorder:Hide()
            end
        end
    end

    -- OnClick handlers (all highlight functions in scope)
    frameAnchoringBtn:SetScript("OnClick", function()
        if CS.frameAnchoringPanelActive then
            CS.frameAnchoringPanelActive = false
        else
            CS.frameAnchoringPanelActive = true
            CS.castBarPanelActive = false
            CS.resourceBarPanelActive = false
            CooldownCompanion:StopCastBarPreview()
            CooldownCompanion:StopResourceBarPreview()
            CS.selectedGroup = nil
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            wipe(CS.selectedGroups)
        end
        UpdateFrameAnchoringBtnHighlight()
        UpdateResourceBarBtnHighlight()
        UpdateCastBarBtnHighlight()
        CooldownCompanion:RefreshConfigPanel()
    end)
    frameAnchoringBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Frame Anchoring")
        GameTooltip:AddLine("Anchor player and target unit frames to icon groups", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frameAnchoringBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    resourceBarBtn:SetScript("OnClick", function()
        if CS.resourceBarPanelActive then
            CS.resourceBarPanelActive = false
            CooldownCompanion:StopResourceBarPreview()
        else
            CS.resourceBarPanelActive = true
            CS.castBarPanelActive = false
            CS.frameAnchoringPanelActive = false
            CooldownCompanion:StopCastBarPreview()
            CS.selectedGroup = nil
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            wipe(CS.selectedGroups)
        end
        UpdateFrameAnchoringBtnHighlight()
        UpdateResourceBarBtnHighlight()
        UpdateCastBarBtnHighlight()
        CooldownCompanion:RefreshConfigPanel()
    end)
    resourceBarBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Resource Bars")
        GameTooltip:AddLine("Display class resource bars anchored to icon groups", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resourceBarBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    castBarBtn:SetScript("OnClick", function()
        if CS.castBarPanelActive then
            CS.castBarPanelActive = false
            CooldownCompanion:StopCastBarPreview()
        else
            CS.castBarPanelActive = true
            CS.resourceBarPanelActive = false
            CS.frameAnchoringPanelActive = false
            CooldownCompanion:StopResourceBarPreview()
            CS.selectedGroup = nil
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            wipe(CS.selectedGroups)
        end
        UpdateFrameAnchoringBtnHighlight()
        UpdateCastBarBtnHighlight()
        UpdateResourceBarBtnHighlight()
        CooldownCompanion:RefreshConfigPanel()
    end)
    castBarBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Cast Bar")
        GameTooltip:AddLine("Attach and customize the player cast bar", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    castBarBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Cooldown Manager button — left of Collapse
    local cdmBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    cdmBtn:SetSize(16, 16)
    local cdmIcon = cdmBtn:CreateTexture(nil, "ARTWORK")
    cdmIcon:SetAtlas("icon_cooldownmanager", false)
    cdmIcon:SetAllPoints()
    cdmBtn:SetHighlightAtlas("icon_cooldownmanager")
    cdmBtn:GetHighlightTexture():SetAlpha(0.3)

    local cdmBtnBorder = nil
    local function UpdateCdmBtnHighlight()
        if CooldownViewerSettings and CooldownViewerSettings:IsShown() then
            if not cdmBtnBorder then
                cdmBtnBorder = cdmBtn:CreateTexture(nil, "OVERLAY")
                cdmBtnBorder:SetPoint("TOPLEFT", -1, 1)
                cdmBtnBorder:SetPoint("BOTTOMRIGHT", 1, -1)
                cdmBtnBorder:SetColorTexture(0.85, 0.65, 0.0, 0.6)
            end
            cdmBtnBorder:Show()
        else
            if cdmBtnBorder then
                cdmBtnBorder:Hide()
            end
        end
    end

    cdmBtn:SetScript("OnClick", function()
        if CooldownViewerSettings then
            CooldownViewerSettings:TogglePanel()
            UpdateCdmBtnHighlight()
        end
    end)
    cdmBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Cooldown Manager")
        GameTooltip:AddLine("Open the Blizzard Cooldown Manager settings panel", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    cdmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if CooldownViewerSettings then
        hooksecurefunc(CooldownViewerSettings, "Hide", function()
            UpdateCdmBtnHighlight()
        end)
    end

    -- Gear button — left of CDM
    local gearBtn = CreateFrame("Button", nil, content)
    gearBtn:SetSize(20, 20)
    gearBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -4, 0)
    cdmBtn:SetPoint("RIGHT", gearBtn, "LEFT", -4, 0)
    resourceBarBtn:SetPoint("RIGHT", cdmBtn, "LEFT", -4, 0)
    castBarBtn:SetPoint("RIGHT", resourceBarBtn, "LEFT", -4, 0)
    frameAnchoringBtn:SetPoint("RIGHT", castBarBtn, "LEFT", -4, 0)
    local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
    gearIcon:SetTexture("Interface\\WorldMap\\GEAR_64GREY")
    gearIcon:SetAllPoints()
    gearBtn:SetHighlightTexture("Interface\\WorldMap\\GEAR_64GREY")
    gearBtn:GetHighlightTexture():SetAlpha(0.3)

    -- Gear dropdown menu
    gearBtn:SetScript("OnClick", function()
        if not CS.gearDropdownFrame then
            CS.gearDropdownFrame = CreateFrame("Frame", "CDCGearDropdown", UIParent, "UIDropDownMenuTemplate")
        end
        UIDropDownMenu_Initialize(CS.gearDropdownFrame, function(self, level)
            local info = UIDropDownMenu_CreateInfo()
            info.text = "  Hide CDC Tooltips"
            info.checked = function() return CooldownCompanion.db.profile.hideInfoButtons end
            info.isNotRadio = true
            info.keepShownOnClick = true
            info.func = function()
                local val = not CooldownCompanion.db.profile.hideInfoButtons
                CooldownCompanion.db.profile.hideInfoButtons = val
                for _, btn in ipairs(CS.columnInfoButtons) do
                    if val then btn:Hide() else btn:Show() end
                end
                for _, btn in ipairs(CS.tabInfoButtons) do
                    if val then btn:Hide() else btn:Show() end
                end
                for _, btn in ipairs(CS.buttonSettingsInfoButtons) do
                    if val then btn:Hide() else btn:Show() end
                end
            end
            UIDropDownMenu_AddButton(info, level)

            local info2 = UIDropDownMenu_CreateInfo()
            info2.text = "  Close on ESC"
            info2.checked = function() return CooldownCompanion.db.profile.escClosesConfig end
            info2.isNotRadio = true
            info2.keepShownOnClick = true
            info2.func = function()
                CooldownCompanion.db.profile.escClosesConfig = not CooldownCompanion.db.profile.escClosesConfig
            end
            UIDropDownMenu_AddButton(info2, level)

            local info3 = UIDropDownMenu_CreateInfo()
            info3.text = "  Generate Bug Report"
            info3.notCheckable = true
            info3.func = function()
                CloseDropDownMenus()
                ShowPopupAboveConfig("CDC_DIAGNOSTIC_EXPORT")
            end
            UIDropDownMenu_AddButton(info3, level)
        end, "MENU")
        CS.gearDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ToggleDropDownMenu(1, nil, CS.gearDropdownFrame, gearBtn, 0, 0)
    end)

    -- Mini frame for collapsed state
    local miniFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    miniFrame:SetSize(58, 52)
    miniFrame:SetMovable(true)
    miniFrame:EnableMouse(true)
    miniFrame:RegisterForDrag("LeftButton")
    local miniWasDragged = false
    miniFrame:SetScript("OnDragStart", miniFrame.StartMoving)
    miniFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        miniWasDragged = true
    end)
    miniFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    miniFrame:SetToplevel(true)
    miniFrame:Hide()

    -- Copy backdrop from the main AceGUI frame so skin addons are respected
    local function ApplyMiniFrameBackdrop()
        local backdrop = content.GetBackdrop and content:GetBackdrop()
        if backdrop then
            local copy = {}
            for k, v in pairs(backdrop) do
                if type(v) == "table" then
                    copy[k] = {}
                    for k2, v2 in pairs(v) do copy[k][k2] = v2 end
                else
                    copy[k] = v
                end
            end
            -- Cap edge size so borders don't overlap on the small frame
            local maxEdge = math.min(miniFrame:GetWidth(), miniFrame:GetHeight()) / 2
            if copy.edgeSize and copy.edgeSize > maxEdge then
                copy.edgeSize = maxEdge
            end
            miniFrame:SetBackdrop(copy)
            miniFrame:SetBackdropColor(content:GetBackdropColor())
            miniFrame:SetBackdropBorderColor(content:GetBackdropBorderColor())
        else
            miniFrame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            miniFrame:SetBackdropColor(0, 0, 0, 0.9)
        end
    end

    -- Reset collapse state whenever mini frame is hidden (ESC, /cdc toggle, expand)
    miniFrame:SetScript("OnHide", function()
        isMinimized = false
        collapseIcon:SetAtlas("common-icon-minus")
        collapseBtn:SetParent(content)
        collapseBtn:ClearAllPoints()
        collapseBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    end)

    -- ESC handler for mini frame
    miniFrame:EnableKeyboard(true)
    miniFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and CooldownCompanion.db.profile.escClosesConfig then
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(false)
            end
            self:Hide()
        elseif not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
    end)

    frame._miniFrame = miniFrame

    -- Collapse button callback
    collapseBtn:SetScript("OnClick", function()
        if isMinimized then
            local expandRight, expandTop
            if miniWasDragged then
                -- User dragged mini frame — apply saved offset to new mini frame position
                expandRight = miniFrame:GetLeft() + savedOffsetRight
                expandTop = miniFrame:GetTop() + savedOffsetTop
            else
                -- No drag — restore exact saved position
                expandRight = savedFrameRight
                expandTop = savedFrameTop
            end
            miniFrame:Hide() -- OnHide resets state and reparents collapse button
            miniWasDragged = false

            content:ClearAllPoints()
            content:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", expandRight, expandTop)
            content:SetHeight(fullHeight)
            content:SetWidth(1150)
            content:Show()
            CooldownCompanion:RefreshConfigPanel()
        else
            -- Collapse: save main frame position, then show mini frame at collapse button position
            CloseDropDownMenus()

            savedFrameRight = content:GetRight()
            savedFrameTop = content:GetTop()

            local btnLeft = collapseBtn:GetLeft()
            local btnBottom = collapseBtn:GetBottom()

            isCollapsing = true
            content:Hide()
            isCollapsing = false

            ApplyMiniFrameBackdrop()
            miniFrame:ClearAllPoints()
            miniFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", btnLeft - 18, btnBottom - 17)
            miniFrame:Show()

            -- Save offset between main frame TOPRIGHT and mini frame position (for drag expand)
            savedOffsetRight = savedFrameRight - miniFrame:GetLeft()
            savedOffsetTop = savedFrameTop - miniFrame:GetTop()

            -- Reparent collapse button to mini frame
            collapseBtn:SetParent(miniFrame)
            collapseBtn:ClearAllPoints()
            collapseBtn:SetPoint("CENTER")

            collapseIcon:SetAtlas("common-icon-plus")
            isMinimized = true
        end
    end)

    -- Profile gear icon next to version/profile text at bottom-left
    local profileGear = CreateFrame("Button", nil, content)
    profileGear:SetSize(16, 16)
    profileGear:SetPoint("LEFT", versionText, "RIGHT", 6, 0)
    local profileGearIcon = profileGear:CreateTexture(nil, "ARTWORK")
    profileGearIcon:SetTexture("Interface\\WorldMap\\GEAR_64GREY")
    profileGearIcon:SetVertexColor(1, 0.9, 0.5)
    profileGearIcon:SetAllPoints()
    profileGear:SetHighlightTexture("Interface\\WorldMap\\GEAR_64GREY")
    profileGear:GetHighlightTexture():SetAlpha(0.3)

    -- Profile bar (expands to the right of gear in bottom dead space)
    local profileBar = CreateFrame("Frame", nil, content)
    profileBar:SetHeight(30)
    profileBar:SetPoint("LEFT", profileGear, "RIGHT", 8, 0)
    profileBar:SetPoint("RIGHT", content, "RIGHT", -20, 0)
    profileBar:Hide()

    profileGear:SetScript("OnClick", function()
        if profileBar:IsShown() then
            profileBar:Hide()
        else
            RefreshProfileBar(profileBar)
            profileBar:Show()
        end
    end)

    -- Column containers fill the content area
    local colParent = CreateFrame("Frame", nil, contentFrame)
    colParent:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -11)
    colParent:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 11)

    -- Column 1: Groups (AceGUI InlineGroup)
    local col1 = AceGUI:Create("InlineGroup")
    col1:SetTitle("Groups")
    col1:SetLayout("None")
    col1.frame:SetParent(colParent)
    col1.frame:Show()

    -- Info button next to Groups title
    local groupInfoBtn = CreateFrame("Button", nil, col1.frame)
    groupInfoBtn:SetSize(16, 16)
    groupInfoBtn:SetPoint("LEFT", col1.titletext, "RIGHT", -2, 0)
    local groupInfoIcon = groupInfoBtn:CreateTexture(nil, "OVERLAY")
    groupInfoIcon:SetSize(12, 12)
    groupInfoIcon:SetPoint("CENTER")
    groupInfoIcon:SetAtlas("QuestRepeatableTurnin")
    groupInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Groups")
        GameTooltip:AddLine("Left-click to select/deselect.", 1, 1, 1, true)
        GameTooltip:AddLine("Ctrl+Left-click to multi-select.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-click for options.", 1, 1, 1, true)
        GameTooltip:AddLine("Middle-click to toggle lock/unlock.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Shift+Left-click to set spec filter.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click folder to expand/collapse.", 1, 1, 1, true)
        GameTooltip:AddLine("Middle-click folder to lock/unlock all children.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Hold left-click and move to reorder.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    groupInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Column 2: Spells/Items (AceGUI InlineGroup)
    local col2 = AceGUI:Create("InlineGroup")
    col2:SetTitle("Spells / Items")
    col2:SetLayout("None")
    col2.frame:SetParent(colParent)
    col2.frame:Show()

    -- Info button next to Spells / Items title
    local infoBtn = CreateFrame("Button", nil, col2.frame)
    infoBtn:SetSize(16, 16)
    infoBtn:SetPoint("LEFT", col2.titletext, "RIGHT", -2, 0)
    local infoIcon = infoBtn:CreateTexture(nil, "OVERLAY")
    infoIcon:SetSize(12, 12)
    infoIcon:SetPoint("CENTER")
    infoIcon:SetAtlas("QuestRepeatableTurnin")
    infoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Spells / Items")
        GameTooltip:AddLine("Left-click to select/deselect.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-click for options.", 1, 1, 1, true)
        GameTooltip:AddLine("Middle-click to move to another group.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Ctrl+Left-click to multi-select.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Hold left-click and move to reorder.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag a spell or item from your spellbook or inventory into this column to add it.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-click the Add button to toggle the spellbook.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    col2._infoBtn = infoBtn

    -- Button Settings column (between Spells/Items and Group Settings)
    local buttonSettingsCol = AceGUI:Create("InlineGroup")
    buttonSettingsCol:SetTitle("Button Settings")
    buttonSettingsCol:SetLayout("None")
    buttonSettingsCol.frame:SetParent(colParent)
    buttonSettingsCol.frame:Show()

    -- Info button next to Button Settings title
    local bsInfoBtn = CreateFrame("Button", nil, buttonSettingsCol.frame)
    bsInfoBtn:SetSize(16, 16)
    bsInfoBtn:SetPoint("LEFT", buttonSettingsCol.titletext, "RIGHT", -2, 0)
    local bsInfoIcon = bsInfoBtn:CreateTexture(nil, "OVERLAY")
    bsInfoIcon:SetSize(12, 12)
    bsInfoIcon:SetPoint("CENTER")
    bsInfoIcon:SetAtlas("QuestRepeatableTurnin")
    bsInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if CS.castBarPanelActive then
            GameTooltip:AddLine("Cast Bar Anchoring / FX")
            GameTooltip:AddLine("Anchoring, positioning, and visual effects for the cast bar.", 1, 1, 1, true)
        elseif CS.resourceBarPanelActive then
            GameTooltip:AddLine("Resource Styling")
            GameTooltip:AddLine("Appearance settings for class resource bars.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Button Settings")
            GameTooltip:AddLine("These settings apply to the selected spell or item.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    bsInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Column 3: Settings (AceGUI InlineGroup)
    local col3 = AceGUI:Create("InlineGroup")
    col3:SetTitle("Group Settings")
    col3:SetLayout("None")
    col3.frame:SetParent(colParent)
    col3.frame:Show()

    -- Info button next to Group Settings title
    local settingsInfoBtn = CreateFrame("Button", nil, col3.frame)
    settingsInfoBtn:SetSize(16, 16)
    settingsInfoBtn:SetPoint("LEFT", col3.titletext, "RIGHT", -2, 0)
    local settingsInfoIcon = settingsInfoBtn:CreateTexture(nil, "OVERLAY")
    settingsInfoIcon:SetSize(12, 12)
    settingsInfoIcon:SetPoint("CENTER")
    settingsInfoIcon:SetAtlas("QuestRepeatableTurnin")
    settingsInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if CS.castBarPanelActive then
            GameTooltip:AddLine("Cast Bar Styling")
            GameTooltip:AddLine("Appearance settings for the cast bar overlay.", 1, 1, 1, true)
        elseif CS.resourceBarPanelActive then
            GameTooltip:AddLine("Custom Aura Bars")
            GameTooltip:AddLine("Track any buff or bar aura from the Cooldown Manager as a resource-style bar. These do not track duration and have no animation -- for that, use spells and auras tracked with icon or bar groups.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Tracking Modes", 1, 0.82, 0)
            GameTooltip:AddLine("Stack Count: fills the bar based on the aura's current stack count (e.g. 3/5 stacks = 60%).", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Active: shows a full bar when the aura is present and an empty bar when it is not.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Group Settings")
            GameTooltip:AddLine("These settings apply to all icons in the selected group.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    settingsInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Store column header (?) buttons for toggling via "Hide CDC Tooltips"
    wipe(CS.columnInfoButtons)
    CS.columnInfoButtons[1] = groupInfoBtn
    CS.columnInfoButtons[2] = infoBtn
    CS.columnInfoButtons[3] = bsInfoBtn
    CS.columnInfoButtons[4] = settingsInfoBtn
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(CS.columnInfoButtons) do
            btn:Hide()
        end
    end

    -- Static button bar at bottom of column 1 (New Icon/Bar Group + New Folder)
    local btnBar = CreateFrame("Frame", nil, col1.content)
    btnBar:SetPoint("BOTTOMLEFT", col1.content, "BOTTOMLEFT", 0, 0)
    btnBar:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 0)
    btnBar:SetHeight(60)
    CS.col1ButtonBar = btnBar

    -- AceGUI ScrollFrames in columns 1 and 2
    local scroll1 = AceGUI:Create("ScrollFrame")
    scroll1:SetLayout("List")
    scroll1.frame:SetParent(col1.content)
    scroll1.frame:ClearAllPoints()
    scroll1.frame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, 0)
    scroll1.frame:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 60)
    scroll1.frame:Show()
    CS.col1Scroll = scroll1

    local scroll2 = AceGUI:Create("ScrollFrame")
    scroll2:SetLayout("List")
    scroll2.frame:SetParent(col2.content)
    scroll2.frame:ClearAllPoints()
    scroll2.frame:SetPoint("TOPLEFT", col2.content, "TOPLEFT", 0, 0)
    scroll2.frame:SetPoint("BOTTOMRIGHT", col2.content, "BOTTOMRIGHT", 0, 0)
    scroll2.frame:Show()
    CS.col2Scroll = scroll2

    -- Button Settings TabGroup (Settings + Overrides tabs)
    local bsTabGroup = AceGUI:Create("TabGroup")
    bsTabGroup:SetTabs({
        { value = "settings",  text = "Settings" },
        { value = "overrides", text = "Overrides" },
    })
    bsTabGroup:SetLayout("Fill")

    bsTabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
        CS.buttonSettingsTab = tab
        -- Clean up info/collapse buttons before releasing
        for _, btn in ipairs(CS.buttonSettingsInfoButtons) do
            btn:ClearAllPoints()
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(CS.buttonSettingsInfoButtons)

        CooldownCompanion:ClearAllProcGlowPreviews()
        CooldownCompanion:ClearAllAuraGlowPreviews()
        CooldownCompanion:ClearAllPandemicPreviews()
        widget:ReleaseChildren()

        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        widget:AddChild(scroll)
        buttonSettingsScroll = scroll
        CS.buttonSettingsScroll = scroll

        local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
        if not group then return end

        local buttonData = CS.selectedButton and group.buttons[CS.selectedButton]
        if not buttonData then return end

        if tab == "settings" then
            if buttonData.type == "spell" then
                ST._BuildSpellSettings(scroll, buttonData, CS.buttonSettingsInfoButtons)
            elseif buttonData.type == "item" and not CooldownCompanion.IsItemEquippable(buttonData) then
                ST._BuildItemSettings(scroll, buttonData, CS.buttonSettingsInfoButtons)
            elseif buttonData.type == "item" and CooldownCompanion.IsItemEquippable(buttonData) then
                ST._BuildEquipItemSettings(scroll, buttonData, CS.buttonSettingsInfoButtons)
            end
            ST._BuildVisibilitySettings(scroll, buttonData, CS.buttonSettingsInfoButtons)
            ST._BuildCustomNameSection(scroll, buttonData)
        elseif tab == "overrides" then
            ST._BuildOverridesTab(scroll, buttonData, CS.buttonSettingsInfoButtons)
        end

        -- Apply hideInfoButtons setting
        if CooldownCompanion.db.profile.hideInfoButtons then
            for _, btn in ipairs(CS.buttonSettingsInfoButtons) do
                btn:Hide()
            end
        end
    end)

    bsTabGroup.frame:SetParent(buttonSettingsCol.content)
    bsTabGroup.frame:ClearAllPoints()
    bsTabGroup.frame:SetPoint("TOPLEFT", buttonSettingsCol.content, "TOPLEFT", 0, 0)
    bsTabGroup.frame:SetPoint("BOTTOMRIGHT", buttonSettingsCol.content, "BOTTOMRIGHT", 0, 0)
    bsTabGroup.frame:Hide()
    buttonSettingsCol.bsTabGroup = bsTabGroup

    -- Placeholder label shown when no button is selected
    local bsPlaceholderLabel = buttonSettingsCol.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bsPlaceholderLabel:SetPoint("TOPLEFT", buttonSettingsCol.content, "TOPLEFT", -1, 0)
    bsPlaceholderLabel:SetText("Select a spell or item to configure")
    bsPlaceholderLabel:Show()
    buttonSettingsCol.bsPlaceholder = bsPlaceholderLabel

    -- Initialize with a placeholder scroll (will be replaced on tab select)
    local bsScroll = AceGUI:Create("ScrollFrame")
    bsScroll:SetLayout("List")
    bsTabGroup:AddChild(bsScroll)
    buttonSettingsScroll = bsScroll
    CS.buttonSettingsScroll = bsScroll

    -- Accept spell/item drops anywhere on the column 2 scroll area
    scroll2.frame:EnableMouse(true)
    scroll2.frame:SetScript("OnReceiveDrag", TryReceiveCursorDrop)
    scroll2.content:EnableMouse(true)
    scroll2.content:SetScript("OnReceiveDrag", TryReceiveCursorDrop)

    -- Drop hint overlay for column 2
    local dropOverlay = CreateFrame("Frame", nil, col2.frame, "BackdropTemplate")
    dropOverlay:SetAllPoints(col2.frame)
    dropOverlay:SetFrameLevel(col2.frame:GetFrameLevel() + 20)
    dropOverlay:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    dropOverlay:SetBackdropColor(0.15, 0.55, 0.85, 0.25)
    dropOverlay:EnableMouse(true)
    dropOverlay:SetScript("OnReceiveDrag", TryReceiveCursorDrop)
    dropOverlay:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and GetCursorInfo() then
            TryReceiveCursorDrop()
        end
    end)
    dropOverlay:Hide()

    local dropBorder = dropOverlay:CreateTexture(nil, "BORDER")
    dropBorder:SetAllPoints()
    dropBorder:SetColorTexture(0.3, 0.7, 1.0, 0.35)

    local dropInner = dropOverlay:CreateTexture(nil, "ARTWORK")
    dropInner:SetPoint("TOPLEFT", 2, -2)
    dropInner:SetPoint("BOTTOMRIGHT", -2, 2)
    dropInner:SetColorTexture(0.05, 0.15, 0.25, 0.6)

    local dropText = dropOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dropText:SetPoint("CENTER", 0, 0)
    dropText:SetText("|cffAADDFFDrop here to track|r")

    dropOverlay:RegisterEvent("CURSOR_CHANGED")
    dropOverlay:SetScript("OnEvent", function(self)
        local cursorType = GetCursorInfo()
        if (cursorType == "spell" or cursorType == "item" or cursorType == "petaction") and CS.selectedGroup and col2.frame:IsShown() then
            self:Show()
        else
            self:Hide()
        end
    end)

    -- Column 3 content area (use InlineGroup's content directly)
    CS.col3Container = col3.content

    -- Layout columns on size change
    local function LayoutColumns()
        local w = colParent:GetWidth()
        local h = colParent:GetHeight()
        local pad = COLUMN_PADDING

        local baseW = w - (pad * 3)
        local smallCol = math.floor(baseW / 4.2)
        local col1Width = smallCol
        local col2Width = smallCol
        local remaining = baseW - (smallCol * 2)
        local bsWidth   = math.floor(remaining / 2)
        local col3Width  = remaining - bsWidth

        col1.frame:ClearAllPoints()
        col1.frame:SetPoint("TOPLEFT", colParent, "TOPLEFT", 0, 0)
        col1.frame:SetSize(col1Width, h)

        col2.frame:ClearAllPoints()
        col2.frame:SetPoint("TOPLEFT", col1.frame, "TOPRIGHT", pad, 0)
        col2.frame:SetSize(col2Width, h)

        buttonSettingsCol.frame:ClearAllPoints()
        buttonSettingsCol.frame:SetPoint("TOPLEFT", col2.frame, "TOPRIGHT", pad, 0)
        buttonSettingsCol.frame:SetSize(bsWidth, h)

        col3.frame:ClearAllPoints()
        col3.frame:SetPoint("TOPLEFT", buttonSettingsCol.frame, "TOPRIGHT", pad, 0)
        col3.frame:SetSize(col3Width, h)
    end

    colParent:SetScript("OnSizeChanged", function()
        LayoutColumns()
    end)

    -- Do initial layout next frame (after frame sizes are established)
    C_Timer.After(0, function()
        LayoutColumns()
    end)

    -- Autocomplete cache invalidation
    local autocompleteCacheFrame = CreateFrame("Frame")
    autocompleteCacheFrame:RegisterEvent("SPELLS_CHANGED")
    autocompleteCacheFrame:RegisterEvent("BAG_UPDATE")
    autocompleteCacheFrame:RegisterEvent("PET_STABLE_UPDATE")
    autocompleteCacheFrame:RegisterEvent("UNIT_PET")
    autocompleteCacheFrame:SetScript("OnEvent", function()
        CS.autocompleteCache = nil
    end)

    -- Store references
    frame.profileBar = profileBar
    frame.versionText = versionText
    frame.col1 = col1
    frame.col2 = col2
    frame.buttonSettingsCol = buttonSettingsCol
    frame.col3 = col3
    frame.colParent = colParent
    frame.LayoutColumns = LayoutColumns
    frame.UpdateCastBarBtnHighlight = UpdateCastBarBtnHighlight
    frame.UpdateResourceBarBtnHighlight = UpdateResourceBarBtnHighlight
    frame.UpdateFrameAnchoringBtnHighlight = UpdateFrameAnchoringBtnHighlight

    CS.configFrame = frame
    return frame
end

------------------------------------------------------------------------
-- Refresh entire panel
------------------------------------------------------------------------
function CooldownCompanion:RefreshConfigPanel()
    if not CS.configFrame then return end
    if not CS.configFrame.frame:IsShown() then return end

    -- Save AceGUI scroll state before any column rebuilds.
    local function saveScroll(widget)
        if not widget then return nil end
        local s = widget.status or widget.localstatus
        if s and s.offset and s.offset > 0 then
            return { offset = s.offset, scrollvalue = s.scrollvalue }
        end
    end
    local function restoreScroll(widget, saved)
        if not saved or not widget then return end
        local s = widget.status or widget.localstatus
        if s then
            s.offset = saved.offset
            s.scrollvalue = saved.scrollvalue
        end
    end

    local saved1   = saveScroll(CS.col1Scroll)
    local saved2   = saveScroll(CS.col2Scroll)
    local savedCab = CS.col3Container and CS.col3Container.customAuraScroll and saveScroll(CS.col3Container.customAuraScroll)
    local savedBtn = saveScroll(buttonSettingsScroll)

    if CS.configFrame.profileBar:IsShown() then
        RefreshProfileBar(CS.configFrame.profileBar)
    end
    CS.configFrame.versionText:SetText("v1.7  |  " .. (self.db:GetCurrentProfile() or "Default"))
    if CS.configFrame.UpdateCastBarBtnHighlight then
        CS.configFrame.UpdateCastBarBtnHighlight()
    end
    if CS.configFrame.UpdateResourceBarBtnHighlight then
        CS.configFrame.UpdateResourceBarBtnHighlight()
    end
    if CS.configFrame.UpdateFrameAnchoringBtnHighlight then
        CS.configFrame.UpdateFrameAnchoringBtnHighlight()
    end
    if CS.castBarPanelActive then
        CS.configFrame.col2:SetTitle("Spells / Items")
        CS.configFrame.buttonSettingsCol:SetTitle("Cast Bar Anchoring / FX")
        CS.configFrame.col3:SetTitle("Cast Bar Styling")
    elseif CS.resourceBarPanelActive then
        CS.configFrame.col2:SetTitle("Resource Anchoring")
        CS.configFrame.buttonSettingsCol:SetTitle("Resource Styling")
        CS.configFrame.col3:SetTitle("Custom Aura Bars")
    elseif CS.frameAnchoringPanelActive then
        CS.configFrame.col2:SetTitle("Spells / Items")
        CS.configFrame.buttonSettingsCol:SetTitle("Player Frame")
        CS.configFrame.col3:SetTitle("Target Frame")
    else
        CS.configFrame.col2:SetTitle("Spells / Items")
        CS.configFrame.buttonSettingsCol:SetTitle("Button Settings")
        CS.configFrame.col3:SetTitle("Group Settings")
    end
    RefreshColumn1()
    RefreshColumn2()
    ST._RefreshButtonSettingsColumn()
    RefreshColumn3(CS.col3Container)

    -- Restore AceGUI scroll state.
    restoreScroll(CS.col1Scroll, saved1)
    restoreScroll(CS.col2Scroll, saved2)
    if CS.col3Container and CS.col3Container.customAuraScroll then
        restoreScroll(CS.col3Container.customAuraScroll, savedCab)
    end
    restoreScroll(buttonSettingsScroll, savedBtn)

end

------------------------------------------------------------------------
-- Toggle config panel open/closed
------------------------------------------------------------------------
function CooldownCompanion:ToggleConfig()
    if InCombatLockdown() then
        self._configWasOpen = true
        self:Print("Config will open after combat ends.")
        return
    end

    if not CS.configFrame then
        CreateConfigPanel()
        -- Defer first refresh until after column layout is computed (next frame)
        C_Timer.After(0, function()
            CooldownCompanion:RefreshConfigPanel()
        end)
        return -- AceGUI Frame is already shown on creation
    end

    -- If minimized, close everything and reset state
    if CS.configFrame._miniFrame and CS.configFrame._miniFrame:IsShown() then
        CS.configFrame._miniFrame:Hide()
        return
    end

    if CS.configFrame.frame:IsShown() then
        CS.configFrame.frame:Hide()
    else
        CS.configFrame.frame:Show()
        self:RefreshConfigPanel()
    end
end

function CooldownCompanion:GetConfigFrame()
    return CS.configFrame
end

------------------------------------------------------------------------
-- SetupConfig: Minimal AceConfig registration for Blizzard Settings
------------------------------------------------------------------------
function CooldownCompanion:SetupConfig()
    -- Register a minimal options table so the addon shows in Blizzard's addon list
    local options = {
        name = "Cooldown Companion",
        type = "group",
        args = {
            openConfig = {
                name = "Open Cooldown Companion",
                desc = "Click to open the configuration panel",
                type = "execute",
                order = 1,
                func = function()
                    -- Close Blizzard settings first
                    if Settings and Settings.CloseUI then
                        Settings.CloseUI()
                    elseif InterfaceOptionsFrame then
                        InterfaceOptionsFrame:Hide()
                    end
                    C_Timer.After(0.1, function()
                        CooldownCompanion:ToggleConfig()
                    end)
                end,
            },
        },
    }

    AceConfig:RegisterOptionsTable(ADDON_NAME, options)
    AceConfigDialog:AddToBlizOptions(ADDON_NAME, "Cooldown Companion")

    -- Profile callbacks to refresh on profile change
    self.db.RegisterCallback(self, "OnProfileChanged", function()
        CS.selectedGroup = nil
        CS.selectedButton = nil
        wipe(CS.selectedButtons)
        wipe(CS.selectedGroups)
        wipe(CS.collapsedFolders)
        CS.castBarPanelActive = false
        CS.resourceBarPanelActive = false
        CS.frameAnchoringPanelActive = false
        CooldownCompanion:StopCastBarPreview()
        CooldownCompanion:StopResourceBarPreview()

        CooldownCompanion:MigrateOrphanedGroups()

        if CS.configFrame and CS.configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
    self.db.RegisterCallback(self, "OnProfileCopied", function()
        CS.selectedGroup = nil
        CS.selectedButton = nil
        wipe(CS.selectedButtons)
        wipe(CS.selectedGroups)
        wipe(CS.collapsedFolders)
        CS.castBarPanelActive = false
        CS.resourceBarPanelActive = false
        CS.frameAnchoringPanelActive = false
        CooldownCompanion:StopCastBarPreview()
        CooldownCompanion:StopResourceBarPreview()

        -- Re-stamp character-scoped groups and folders after profile copy (matches import flow)
        local charKey = CooldownCompanion.db.keys.char
        if CooldownCompanion.db.profile.groups then
            for _, group in pairs(CooldownCompanion.db.profile.groups) do
                if not group.isGlobal then
                    group.createdBy = charKey
                end
            end
        end
        if CooldownCompanion.db.profile.folders then
            for _, folder in pairs(CooldownCompanion.db.profile.folders) do
                if folder.section == "char" then
                    folder.createdBy = charKey
                end
            end
        end

        if CS.configFrame and CS.configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
    self.db.RegisterCallback(self, "OnProfileReset", function()
        CS.selectedGroup = nil
        CS.selectedButton = nil
        wipe(CS.selectedButtons)
        wipe(CS.selectedGroups)
        wipe(CS.collapsedFolders)
        CS.castBarPanelActive = false
        CS.resourceBarPanelActive = false
        CS.frameAnchoringPanelActive = false
        CooldownCompanion:StopCastBarPreview()
        CooldownCompanion:StopResourceBarPreview()

        if CS.configFrame and CS.configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
end
