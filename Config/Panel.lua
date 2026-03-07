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
local ResetConfigSelection = ST._ResetConfigSelection
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local COLUMN_PADDING = ST._COLUMN_PADDING
local TryReceiveCursorDrop = ST._TryReceiveCursorDrop
local BuildAutocompleteCache = ST._BuildAutocompleteCache
local RefreshColumn1 = ST._RefreshColumn1
local RefreshColumn2 = ST._RefreshColumn2
local RefreshColumn3 = ST._RefreshColumn3
local RefreshColumn4 = ST._RefreshColumn4
local RefreshProfileBar = ST._RefreshProfileBar
local SetConfigPrimaryMode = ST._SetConfigPrimaryMode

local function SetPrimaryMode(mode, opts)
    if SetConfigPrimaryMode then
        return SetConfigPrimaryMode(mode, opts)
    end
    CS.resourceBarPanelActive = (mode == "bars")
    if not (opts and opts.skipRefresh) then
        CooldownCompanion:RefreshConfigPanel()
    end
    return true
end

local function GetClassColoredText(text)
    local safeText = tostring(text or "")
    local classColor = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    if classColor then
        if classColor.WrapTextInColorCode then
            return classColor:WrapTextInColorCode(safeText)
        end
        local r = math.floor(((classColor.r or 1) * 255) + 0.5)
        local g = math.floor(((classColor.g or 1) * 255) + 0.5)
        local b = math.floor(((classColor.b or 1) * 255) + 0.5)
        return string.format("|cff%02x%02x%02x%s|r", r, g, b, safeText)
    end
    return safeText
end

local function GetCustomAuraBarsColumnTitle()
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if not specIdx then
        return "Custom Aura Bars"
    end
    local _, specName = C_SpecializationInfo.GetSpecializationInfo(specIdx)
    if not specName or specName == "" then
        return "Custom Aura Bars"
    end
    return "Custom Aura Bars: " .. GetClassColoredText(specName)
end

-- Shared reset for profile change/copy/reset callbacks
local function ResetConfigForProfileChange()
    ResetConfigSelection(true)
    wipe(CS.collapsedFolders)
    wipe(CS.customAuraBarSubTabs)
    SetPrimaryMode("buttons", { skipRefresh = true })
    if ST._CancelAutoAddFlow then
        ST._CancelAutoAddFlow()
    end
    CooldownCompanion:StopCastBarPreview()
    CooldownCompanion:StopResourceBarPreview()
end

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
    frame:SetWidth(1384)
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

    -- Custom resize grip — expand freely, shrink horizontally up to 30% (min 993px)
    content:SetResizable(true)
    content:SetResizeBounds(993, 400)

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
        -- If talent picker is open when panel closes, clean up its raw frames
        -- (RefreshConfigPanel inside CloseTalentPicker is guarded by IsShown, so it's safe)
        if CS.talentPickerMode then
            CooldownCompanion:CloseTalentPicker()
        end
        CooldownCompanion:ClearAllProcGlowPreviews()
        CooldownCompanion:ClearAllAuraGlowPreviews()
        CooldownCompanion:ClearAllPandemicPreviews()
        CooldownCompanion:StopCastBarPreview()
        CloseDropDownMenus()
        CS.HideAutocomplete()
        if ST._CancelAutoAddFlow then
            ST._CancelAutoAddFlow()
        end
    end)

    -- ESC to close support (keyboard handler — more reliable than UISpecialFrames)
    content:EnableKeyboard(true)
    content:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            -- Talent picker open: close picker instead of panel
            if CS.talentPickerMode then
                if not InCombatLockdown() then
                    self:SetPropagateKeyboardInput(false)
                end
                CooldownCompanion:CloseTalentPicker()
                return
            end
            if CooldownCompanion.db.profile.escClosesConfig then
                if not InCombatLockdown() then
                    self:SetPropagateKeyboardInput(false)
                end
                self:Hide()
            elseif not InCombatLockdown() then
                self:SetPropagateKeyboardInput(true)
            end
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

    -- Bottom text-based mode status row (Currently viewing: <mode button>)
    local MODE_VIEW_BUTTONS_COLOR = {1.0, 0.82, 0.0}
    local MODE_VIEW_BARS_COLOR = {0.30, 0.62, 1.0}
    local MODE_MIN_BUTTON_WIDTH = 90
    local MODE_BUTTON_TEXT_PADDING = 28
    local MODE_BUTTON_GROW_STEP = 8
    local MODE_BUTTON_GROW_MAX = 900

    local modeStatusRow
    local modeToggleButton
    local modeValueText
    local modeToggleTooltipText = "Switch settings mode"

    local function RGBToHex(r, g, b)
        local function clamp(v)
            if v < 0 then return 0 end
            if v > 1 then return 1 end
            return v
        end
        local ri = math.floor((clamp(r or 1) * 255) + 0.5)
        local gi = math.floor((clamp(g or 1) * 255) + 0.5)
        local bi = math.floor((clamp(b or 1) * 255) + 0.5)
        return string.format("%02x%02x%02x", ri, gi, bi)
    end

    local function UpdateModeRowLayout()
        if not modeStatusRow or not modeValueText or not modeToggleButton then return end

        local valueW = math.ceil(modeValueText:GetStringWidth() or 0)
        local buttonW = math.max(MODE_MIN_BUTTON_WIDTH, valueW + MODE_BUTTON_TEXT_PADDING)
        local buttonH = (modeToggleButton.frame and modeToggleButton.frame:GetHeight()) or 22
        local rowH = math.max(16, math.ceil(modeValueText:GetStringHeight() or 0), buttonH)

        modeToggleButton.frame:ClearAllPoints()
        modeToggleButton.frame:SetPoint("LEFT", modeStatusRow, "LEFT", 0, 0)
        modeToggleButton:SetWidth(buttonW)
        if modeValueText.IsTruncated and modeValueText:IsTruncated() then
            local guard = 0
            while modeValueText:IsTruncated() and buttonW < MODE_BUTTON_GROW_MAX do
                buttonW = buttonW + MODE_BUTTON_GROW_STEP
                modeToggleButton:SetWidth(buttonW)
                guard = guard + 1
                if guard > 128 then break end
            end
        end

        modeStatusRow:SetSize(buttonW, rowH + 2)
    end

    local function UpdateModeNavigationUI()
        if not modeValueText or not modeToggleButton then return end

        local classColor = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
        local prefixR, prefixG, prefixB = 1, 0.82, 0
        if classColor then
            prefixR, prefixG, prefixB = classColor.r, classColor.g, classColor.b
        end

        local isBars = CS.resourceBarPanelActive == true
        local modeLabel, modeR, modeG, modeB
        if isBars then
            modeLabel = "Bars & Frames"
            modeR, modeG, modeB = MODE_VIEW_BARS_COLOR[1], MODE_VIEW_BARS_COLOR[2], MODE_VIEW_BARS_COLOR[3]
            modeToggleTooltipText = "Switch to Buttons settings"
        else
            modeLabel = "Buttons"
            modeR, modeG, modeB = MODE_VIEW_BUTTONS_COLOR[1], MODE_VIEW_BUTTONS_COLOR[2], MODE_VIEW_BUTTONS_COLOR[3]
            modeToggleTooltipText = "Switch to Bars & Frames settings"
        end

        local prefixHex = RGBToHex(prefixR, prefixG, prefixB)
        local modeHex = RGBToHex(modeR, modeG, modeB)
        modeToggleButton:SetText("|cff" .. prefixHex .. "Currently Viewing:|r |cff" .. modeHex .. modeLabel .. "|r")

        UpdateModeRowLayout()
    end

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

    -- CDM Display toggle button — left of CDM button
    local cdmDisplayBtn = CreateFrame("Button", nil, content)
    cdmDisplayBtn:SetSize(20, 20)
    local cdmDisplayIcon = cdmDisplayBtn:CreateTexture(nil, "ARTWORK")
    cdmDisplayIcon:SetAllPoints()

    local function UpdateCdmDisplayIcon()
        if CooldownCompanion.db.profile.cdmHidden then
            cdmDisplayIcon:SetAtlas("GM-icon-visibleDis-pressed", false)
            cdmDisplayBtn:SetHighlightAtlas("GM-icon-visibleDis-pressed")
        else
            cdmDisplayIcon:SetAtlas("GM-icon-visible", false)
            cdmDisplayBtn:SetHighlightAtlas("GM-icon-visible")
        end
        cdmDisplayBtn:GetHighlightTexture():SetAlpha(0.3)
    end
    UpdateCdmDisplayIcon()
    CS.UpdateCdmDisplayIcon = UpdateCdmDisplayIcon

    cdmDisplayBtn:SetScript("OnClick", function()
        CooldownCompanion.db.profile.cdmHidden = not CooldownCompanion.db.profile.cdmHidden
        CooldownCompanion:ApplyCdmAlpha()
        UpdateCdmDisplayIcon()
    end)
    cdmDisplayBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Toggle CDM Display")
        GameTooltip:AddLine("This only toggles the visibility of the Cooldown Manager on your screen. Aura tracking will continue to work regardless.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    cdmDisplayBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Gear button — left of CDM Display
    local gearBtn = CreateFrame("Button", nil, content)
    gearBtn:SetSize(20, 20)
    gearBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -4, 0)
    cdmBtn:SetPoint("RIGHT", gearBtn, "LEFT", -4, 0)
    cdmDisplayBtn:SetPoint("RIGHT", cdmBtn, "LEFT", -4, 0)
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

    local function SyncModeToggleWithProfileBar()
        if not modeStatusRow then return end
        modeStatusRow:SetShown(not profileBar:IsShown())
    end

    profileGear:SetScript("OnClick", function()
        if profileBar:IsShown() then
            profileBar:Hide()
        else
            RefreshProfileBar(profileBar)
            profileBar:Show()
        end
        SyncModeToggleWithProfileBar()
    end)
    profileBar:HookScript("OnShow", SyncModeToggleWithProfileBar)
    profileBar:HookScript("OnHide", SyncModeToggleWithProfileBar)

    -- Bottom text-based mode row
    modeStatusRow = CreateFrame("Frame", nil, content)
    modeStatusRow:SetPoint("BOTTOM", content, "BOTTOM", 0, 21)
    modeStatusRow:SetSize(200, 18)
    SyncModeToggleWithProfileBar()

    modeToggleButton = AceGUI:Create("Button")
    modeToggleButton:SetText("Currently Viewing: Buttons")
    modeToggleButton:SetWidth(MODE_MIN_BUTTON_WIDTH)
    modeToggleButton:SetHeight(22)
    modeToggleButton:SetCallback("OnClick", function()
        if CS.resourceBarPanelActive then
            SetPrimaryMode("buttons")
        else
            SetPrimaryMode("bars")
        end
    end)
    modeToggleButton.frame:SetParent(modeStatusRow)
    modeToggleButton.frame:ClearAllPoints()
    modeToggleButton.frame:SetPoint("LEFT", modeStatusRow, "LEFT", 0, 0)
    modeToggleButton.frame:Show()

    modeValueText = modeToggleButton.text

    modeToggleButton.frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Switch Settings Mode")
        GameTooltip:AddLine(modeToggleTooltipText, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    modeToggleButton.frame:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    -- Keep button row vertically centered in the status row.
    modeToggleButton.frame:HookScript("OnShow", function(self)
        self:ClearAllPoints()
        self:SetPoint("LEFT", modeStatusRow, "LEFT", 0, 0)
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
        GameTooltip:AddLine("Shift+Left-click group to set spec filter.", 1, 1, 1, true)
        GameTooltip:AddLine("Shift+Left-click folder to set folder-wide filters.", 1, 1, 1, true)
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
        GameTooltip:AddLine("Drag spells/items from your spellbook or inventory into this column to add it.", 1, 1, 1, true)
        GameTooltip:AddLine("Use PICK CDM in Button Settings to add CDM auras.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-click the Add button to toggle the spellbook.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    col2._infoBtn = infoBtn

    -- Column 3: Button Settings
    local col3 = AceGUI:Create("InlineGroup")
    col3:SetTitle("Button Settings")
    col3:SetLayout("None")
    col3.frame:SetParent(colParent)
    col3.frame:Show()

    -- Info button next to Button Settings title
    local bsInfoBtn = CreateFrame("Button", nil, col3.frame)
    bsInfoBtn:SetSize(16, 16)
    bsInfoBtn:SetPoint("LEFT", col3.titletext, "RIGHT", -2, 0)
    local bsInfoIcon = bsInfoBtn:CreateTexture(nil, "OVERLAY")
    bsInfoIcon:SetSize(12, 12)
    bsInfoIcon:SetPoint("CENTER")
    bsInfoIcon:SetAtlas("QuestRepeatableTurnin")
    bsInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if CS.resourceBarPanelActive then
            GameTooltip:AddLine("Custom Aura Bars")
            GameTooltip:AddLine("Configure per-spec custom aura bar tracking slots.", 1, 1, 1, true)
        elseif CS.autoAddFlowActive then
            GameTooltip:AddLine("Auto Add")
            GameTooltip:AddLine("Guided import flow for Action Bars, Spellbook, and CDM Auras.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Button Settings")
            GameTooltip:AddLine("These settings apply to the selected spell or item.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    bsInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Column 4: Group Settings (AceGUI InlineGroup)
    local col4 = AceGUI:Create("InlineGroup")
    col4:SetTitle("Group Settings")
    col4:SetLayout("None")
    col4.frame:SetParent(colParent)
    col4.frame:Show()

    -- Info button next to Group Settings title
    local settingsInfoBtn = CreateFrame("Button", nil, col4.frame)
    settingsInfoBtn:SetSize(16, 16)
    settingsInfoBtn:SetPoint("LEFT", col4.titletext, "RIGHT", -2, 0)
    local settingsInfoIcon = settingsInfoBtn:CreateTexture(nil, "OVERLAY")
    settingsInfoIcon:SetSize(12, 12)
    settingsInfoIcon:SetPoint("CENTER")
    settingsInfoIcon:SetAtlas("QuestRepeatableTurnin")
    settingsInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if CS.resourceBarPanelActive then
            GameTooltip:AddLine("Custom Aura Bars")
            GameTooltip:AddLine("Track any buff or bar aura from the Cooldown Manager as a resource-style bar.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Tracking Modes", 1, 0.82, 0)
            GameTooltip:AddLine("Stack Count: fills the bar based on the aura's current stack count (e.g. 3/5 stacks = 60%).", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Active: shows a full bar when the aura is present, draining as the aura expires.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Both modes support optional duration and stack text overlays.", 1, 1, 1, true)
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

    -- Button Settings TabGroup (Settings + Sound Alerts + Overrides tabs)
    local bsTabGroup = AceGUI:Create("TabGroup")
    bsTabGroup:SetTabs({
        { value = "settings",  text = "Settings" },
        { value = "soundalerts", text = "Sound Alerts" },
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
        elseif tab == "soundalerts" then
            ST._BuildSpellSoundAlertsTab(scroll, buttonData, CS.buttonSettingsInfoButtons)
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

    bsTabGroup.frame:SetParent(col3.content)
    bsTabGroup.frame:ClearAllPoints()
    bsTabGroup.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
    bsTabGroup.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
    bsTabGroup.frame:Hide()
    col3.bsTabGroup = bsTabGroup

    -- Placeholder label shown when no button is selected
    local bsPlaceholderLabel = col3.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bsPlaceholderLabel:SetPoint("TOPLEFT", col3.content, "TOPLEFT", -1, 0)
    bsPlaceholderLabel:SetText("Select a spell or item to configure")
    bsPlaceholderLabel:Show()
    col3.bsPlaceholder = bsPlaceholderLabel

    -- Initialize with a placeholder scroll (will be replaced on tab select)
    local bsScroll = AceGUI:Create("ScrollFrame")
    bsScroll:SetLayout("List")
    bsTabGroup:AddChild(bsScroll)
    buttonSettingsScroll = bsScroll
    CS.buttonSettingsScroll = bsScroll

    -- Drop hint overlay for column 2
    local dropOverlay = CreateFrame("Frame", nil, col2.frame, "BackdropTemplate")
    dropOverlay:SetAllPoints(col2.frame)
    dropOverlay:SetFrameLevel(col2.frame:GetFrameLevel() + 20)
    dropOverlay:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    dropOverlay:SetBackdropColor(0.15, 0.55, 0.85, 0.25)
    dropOverlay:EnableMouse(true)
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
    dropText:SetText("|cffAADDFFDrop spell or item here to track|r")

    local function IsCursorDropPayload(cursorType)
        return cursorType == "spell" or cursorType == "item" or cursorType == "petaction"
    end

    local function UpdateDropOverlayVisibility()
        local cursorType = GetCursorInfo()
        if IsCursorDropPayload(cursorType)
            and CS.selectedGroup
            and col2.frame:IsShown() then
            dropOverlay:Show()
        else
            dropOverlay:Hide()
        end
    end

    local function TryReceiveAnyDrop()
        local added = TryReceiveCursorDrop()
        UpdateDropOverlayVisibility()
        return added
    end

    -- Accept spell/item drops anywhere on the column 2 scroll area
    scroll2.frame:EnableMouse(true)
    scroll2.frame:SetScript("OnReceiveDrag", TryReceiveAnyDrop)
    scroll2.content:EnableMouse(true)
    scroll2.content:SetScript("OnReceiveDrag", TryReceiveAnyDrop)

    dropOverlay:SetScript("OnReceiveDrag", TryReceiveAnyDrop)
    dropOverlay:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and GetCursorInfo() then
            TryReceiveAnyDrop()
        end
    end)

    dropOverlay:RegisterEvent("CURSOR_CHANGED")
    dropOverlay:SetScript("OnEvent", function()
        UpdateDropOverlayVisibility()
    end)

    -- Column 4 content area (use InlineGroup's content directly)
    CS.col4Container = col4.content

    local function PositionPrimaryAxisUI()
        local contentCenterX = select(1, content:GetCenter())
        local col2Right = select(1, col2.frame:GetRight())
        local col3Left = select(1, col3.frame:GetLeft())
        local contentBottom = content:GetBottom()
        local versionBottom = versionText and versionText:GetBottom()
        local versionTop = versionText and versionText:GetTop()

        local xOffset = 0
        if contentCenterX and col2Right and col3Left then
            xOffset = ((col2Right + col3Left) * 0.5) - contentCenterX
        end

        local yCenterOffset = 0
        if contentBottom and versionBottom and versionTop then
            yCenterOffset = math.floor((((versionBottom + versionTop) * 0.5) - contentBottom) + 0.5)
        else
            yCenterOffset = 40
        end

        if modeStatusRow then
            modeStatusRow:ClearAllPoints()
            modeStatusRow:SetPoint("CENTER", content, "BOTTOM", xOffset, yCenterOffset)
        end

        if frame.titlebg then
            frame.titlebg:ClearAllPoints()
            frame.titlebg:SetPoint("TOP", content, "TOP", xOffset, 12)
        end
    end

    -- Layout columns on size change
    local function LayoutColumns()
        local w = colParent:GetWidth()
        local h = colParent:GetHeight()
        local pad = COLUMN_PADDING

        local baseW = w - (pad * 3)
        local oldSmall = math.floor(baseW / 4.2)
        local oldRemaining = baseW - (oldSmall * 2)
        local groupReferenceWidth = oldRemaining - math.floor(oldRemaining / 2)
        local equalColWidth = math.min(groupReferenceWidth, math.floor(baseW / 4))

        -- Talent picker mode: 2 wide columns (col1 + col3), col2/col4 hidden
        if CS.talentPickerMode then
            local wideColWidth = equalColWidth * 2 + pad
            local usedWidth = (wideColWidth * 2) + pad
            local leftInset = math.floor((w - usedWidth) * 0.5)

            col1.frame:ClearAllPoints()
            col1.frame:SetPoint("TOPLEFT", colParent, "TOPLEFT", leftInset, 0)
            col1.frame:SetSize(wideColWidth, h)

            col3.frame:ClearAllPoints()
            col3.frame:SetPoint("TOPLEFT", col1.frame, "TOPRIGHT", pad, 0)
            col3.frame:SetSize(wideColWidth, h)
            return
        end

        local usedWidth = (equalColWidth * 4) + (pad * 3)
        local leftInset = math.floor((w - usedWidth) * 0.5)

        local col1Width = equalColWidth
        local col2Width = equalColWidth
        local col3Width = equalColWidth
        local col4Width = equalColWidth

        col1.frame:ClearAllPoints()
        col1.frame:SetPoint("TOPLEFT", colParent, "TOPLEFT", leftInset, 0)
        col1.frame:SetSize(col1Width, h)

        col2.frame:ClearAllPoints()
        col2.frame:SetPoint("TOPLEFT", col1.frame, "TOPRIGHT", pad, 0)
        col2.frame:SetSize(col2Width, h)

        col3.frame:ClearAllPoints()
        col3.frame:SetPoint("TOPLEFT", col2.frame, "TOPRIGHT", pad, 0)
        col3.frame:SetSize(col3Width, h)

        col4.frame:ClearAllPoints()
        col4.frame:SetPoint("TOPLEFT", col3.frame, "TOPRIGHT", pad, 0)
        col4.frame:SetSize(col4Width, h)

        PositionPrimaryAxisUI()
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
    frame.modeStatusRow = modeStatusRow
    frame.profileGear = profileGear
    frame.col1 = col1
    frame.col2 = col2
    frame.col3 = col3
    frame.col4 = col4
    frame.colParent = colParent
    frame.LayoutColumns = LayoutColumns
    frame.UpdateModeNavigationUI = UpdateModeNavigationUI
    UpdateModeNavigationUI()

    CS.configFrame = frame
    return frame
end

------------------------------------------------------------------------
-- Refresh entire panel
------------------------------------------------------------------------
function CooldownCompanion:RefreshConfigPanel()
    if not CS.configFrame then return end
    if not CS.configFrame.frame:IsShown() then return end
    if CS.talentPickerMode then return end

    -- Save AceGUI scroll state before any column rebuilds.
    local function saveScroll(widget)
        if not widget then return nil end
        local s = widget.status or widget.localstatus
        if s then
            local offset = tonumber(s.offset) or 0
            local scrollvalue = tonumber(s.scrollvalue) or 0
            if offset > 0 or scrollvalue > 0 then
                return { offset = s.offset, scrollvalue = s.scrollvalue }
            end
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
    local function clearScroll(widget)
        if not widget then return end
        local s = widget.status or widget.localstatus
        if s then
            s.offset = nil
            s.scrollvalue = nil
        end
    end
    local function getAutoAddScrollKey()
        local state = CS.autoAddFlowState
        if not (CS.autoAddFlowActive and state) then return nil end
        return table.concat({
            tostring(tonumber(state.serial) or 0),
            tostring(state.groupID or ""),
            tostring(state.source or ""),
            tostring(tonumber(state.step) or 0),
        }, ":")
    end
    local function getBarsStylingScrollKey()
        if not CS.resourceBarPanelActive then return nil end
        local barTab = tostring(CS.barPanelTab or "")
        if barTab == "resource_anchoring" then
            local styleTab = tostring(CS.resourceStylingTab or "bar_text")
            return barTab .. ":" .. styleTab
        end
        return barTab
    end
    local function getBarsStylingScrollWidget(col2)
        if not col2 then return nil end
        if CS.resourceBarPanelActive and CS.barPanelTab == "resource_anchoring" then
            return col2._resourceStylingSubScroll
        end
        return col2._barsStylingScroll
    end
    local function getCustomAuraScrollKey()
        if not CS.resourceBarPanelActive then return nil end
        local barTab = tostring(CS.customAuraBarTab or "bar_1")
        local slotIdx = tonumber(barTab:match("^bar_(%d+)$")) or 1
        local subTab = CS.customAuraBarSubTabs and CS.customAuraBarSubTabs[slotIdx] or "settings"
        return barTab .. ":" .. tostring(subTab)
    end
    local function getCustomAuraScrollWidget(col3)
        if not col3 then return nil end
        return col3._customAuraSubScroll or col3._customAuraScroll
    end

    local saved1   = saveScroll(CS.col1Scroll)
    local saved2   = saveScroll(CS.col2Scroll)
    local col2Before = CS.configFrame and CS.configFrame.col2
    local savedBarsStyling = saveScroll(getBarsStylingScrollWidget(col2Before))
    local savedBarsStylingKey = getBarsStylingScrollKey()
    local col3Before = CS.configFrame and CS.configFrame.col3
    local savedCab = saveScroll(getCustomAuraScrollWidget(col3Before))
    local savedCabKey = getCustomAuraScrollKey()
    local savedAaf = col3Before and col3Before._autoAddScroll and saveScroll(col3Before._autoAddScroll)
    local savedAafKey = getAutoAddScrollKey()
    local savedBtn = saveScroll(buttonSettingsScroll)

    if CS.configFrame.profileBar:IsShown() then
        RefreshProfileBar(CS.configFrame.profileBar)
    end
    CS.configFrame.versionText:SetText("v1.7  |  " .. (self.db:GetCurrentProfile() or "Default"))
    if CS.configFrame.UpdateModeNavigationUI then
        CS.configFrame.UpdateModeNavigationUI()
    end
    if CS.resourceBarPanelActive then
        CS.configFrame.col1:SetTitle("Bars & Frames")
        CS.configFrame.col2:SetTitle("Styling")
        CS.configFrame.col3:SetTitle(GetCustomAuraBarsColumnTitle())
        CS.configFrame.col4:SetTitle("Layout & Order")
    else
        CS.configFrame.col1:SetTitle("Groups")
        CS.configFrame.col2:SetTitle("Spells / Items")
        if CS.autoAddFlowActive then
            CS.configFrame.col3:SetTitle("Auto Add")
        else
            CS.configFrame.col3:SetTitle("Button Settings")
        end
        CS.configFrame.col4:SetTitle("Group Settings")
    end
    RefreshColumn1()
    RefreshColumn2()
    RefreshColumn3()
    RefreshColumn4(CS.col4Container)

    -- Recompute Column 3 title after RefreshColumn3(), since it may cancel Auto Add.
    if CS.resourceBarPanelActive then
        CS.configFrame.col3:SetTitle(GetCustomAuraBarsColumnTitle())
    elseif CS.autoAddFlowActive then
        CS.configFrame.col3:SetTitle("Auto Add")
    else
        CS.configFrame.col3:SetTitle("Button Settings")
    end

    -- Restore AceGUI scroll state.
    restoreScroll(CS.col1Scroll, saved1)
    restoreScroll(CS.col2Scroll, saved2)
    local col2After = CS.configFrame and CS.configFrame.col2
    local barsStylingAfter = getBarsStylingScrollWidget(col2After)
    if barsStylingAfter then
        local currentBarsKey = getBarsStylingScrollKey()
        if savedBarsStyling and savedBarsStylingKey and currentBarsKey and savedBarsStylingKey == currentBarsKey then
            restoreScroll(barsStylingAfter, savedBarsStyling)
        else
            clearScroll(barsStylingAfter)
        end
    end
    local col3After = CS.configFrame and CS.configFrame.col3
    local customAuraAfter = getCustomAuraScrollWidget(col3After)
    if customAuraAfter then
        local currentCabKey = getCustomAuraScrollKey()
        if savedCab and savedCabKey and currentCabKey and savedCabKey == currentCabKey then
            restoreScroll(customAuraAfter, savedCab)
        else
            clearScroll(customAuraAfter)
        end
    end
    if col3After and col3After._autoAddScroll then
        local currentAafKey = getAutoAddScrollKey()
        if savedAaf and savedAafKey and currentAafKey and savedAafKey == currentAafKey then
            restoreScroll(col3After._autoAddScroll, savedAaf)
        else
            clearScroll(col3After._autoAddScroll)
        end
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
        SetPrimaryMode("buttons", { skipRefresh = true })
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
        SetPrimaryMode("buttons", { skipRefresh = true })
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
        ResetConfigForProfileChange()
        CooldownCompanion:RunAllMigrations()

        if CS.configFrame and CS.configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
    self.db.RegisterCallback(self, "OnProfileCopied", function()
        ResetConfigForProfileChange()

        -- Re-stamp character-scoped groups and folders for copies (Duplicate).
        -- Suppressed during Rename (preserve ownership, not claiming groups).
        local suppress = CooldownCompanion._suppressOwnershipRestamp
        CooldownCompanion._suppressOwnershipRestamp = nil
        if not suppress then
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
        end

        CooldownCompanion:RunAllMigrations()

        if CS.configFrame and CS.configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
    self.db.RegisterCallback(self, "OnProfileReset", function()
        ResetConfigForProfileChange()
        CooldownCompanion:RunAllMigrations()

        if CS.configFrame and CS.configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
    self.db.RegisterCallback(self, "OnProfileDeleted", function()
        if CS.configFrame and CS.configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
    end)
end
