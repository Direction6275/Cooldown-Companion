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
local BuildAutocompleteCache = ST._BuildAutocompleteCache
local RefreshColumn1 = ST._RefreshColumn1
local RefreshColumn2 = ST._RefreshColumn2
local RefreshColumn3 = ST._RefreshColumn3
local RefreshColumn4 = ST._RefreshColumn4
local RefreshProfileBar = ST._RefreshProfileBar
local SetConfigPrimaryMode = ST._SetConfigPrimaryMode
local UpdateCol2CursorPreview = ST._UpdateCol2CursorPreview
local ClearCol2AnimatedPreview = ST._ClearCol2AnimatedPreview
local ClearConfigShiftTooltipHover = ST._ClearConfigShiftTooltipHover

local function GetAddonVersionText()
    if ST._GetAddonVersion then
        return ST._GetAddonVersion()
    end
    return "unknown"
end

local function GetVersionFooterText()
    local version = GetAddonVersionText()
    if ST._Changelog and ST._Changelog.GetDisplayAddonVersion then
        version = ST._Changelog.GetDisplayAddonVersion()
    end
    version = tostring(version or "unknown")
    if version ~= "" and version ~= "unknown" and version ~= "dev" and not version:match("^[Vv]") then
        version = "v" .. version
    end
    return version .. "  |  " .. (CooldownCompanion.db:GetCurrentProfile() or "Default")
end

local MANUAL_COLUMN_LAYOUT = "CDC_MANUAL"

if not AceGUI:GetLayout(MANUAL_COLUMN_LAYOUT) then
    -- These columns are positioned and sized manually, so their layout should
    -- not call LayoutFinished and auto-shrink them based on child height.
    AceGUI:RegisterLayout(MANUAL_COLUMN_LAYOUT, function()
    end)
end

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

local GetClassColoredText = ST._GetClassColoredText

local function GetLayoutOrderColumnTitle()
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if not specIdx then
        return "Layout & Order"
    end
    local _, specName = C_SpecializationInfo.GetSpecializationInfo(specIdx)
    if not specName or specName == "" then
        return "Layout & Order"
    end
    return "Layout & Order: " .. GetClassColoredText(specName)
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

local function CountSelections(selectionSet)
    local count = 0
    for _ in pairs(selectionSet or {}) do
        count = count + 1
    end
    return count
end

local function GetConfigSelectionSummary()
    return {
        panelMultiCount = CountSelections(CS.selectedPanels),
        groupMultiCount = CountSelections(CS.selectedGroups),
        hasSelectedPanel = CS.selectedGroup ~= nil,
        hasSelectedGroup = CS.selectedContainer ~= nil,
    }
end

local function GetColumn3HeaderMode(selection)
    if CS.resourceBarPanelActive then
        return "custom_aura"
    end
    if selection.panelMultiCount >= 2 then
        return "panel_actions"
    end
    if CS.autoAddFlowActive then
        return "auto_add"
    end
    return "button"
end

local function GetColumn4HeaderMode(selection)
    if CS.resourceBarPanelActive then
        return "layout_order"
    end
    if selection.panelMultiCount >= 2 or selection.hasSelectedPanel then
        return "panel"
    end
    return "group"
end

local function GetColumn3HeaderTitle(selection)
    local mode = GetColumn3HeaderMode(selection)
    if mode == "custom_aura" then
        return GetCustomAuraBarsColumnTitle()
    elseif mode == "auto_add" then
        return "Auto Add"
    elseif mode == "panel_actions" then
        return "Panel Actions"
    end
    return "Button Settings"
end

local function GetColumn4HeaderTitle(selection)
    local mode = GetColumn4HeaderMode(selection)
    if mode == "layout_order" then
        return GetLayoutOrderColumnTitle()
    elseif mode == "panel" then
        return "Panel Settings"
    end
    return "Group Settings"
end

local function ApplyConfigColumnTitles(frame)
    if CS.resourceBarPanelActive then
        frame.col1:SetTitle("Bars & Frames")
    elseif CS.browseMode then
        frame.col1:SetTitle("Browse Characters")
        frame.col2:SetTitle("Preview")
    else
        frame.col1:SetTitle("Groups")
        frame.col2:SetTitle("Panels")
    end

    local selection = GetConfigSelectionSummary()
    frame.col3:SetTitle(GetColumn3HeaderTitle(selection))
    frame.col4:SetTitle(GetColumn4HeaderTitle(selection))
end

-- Shared reset for profile change/copy/reset callbacks
local function ResetConfigForProfileChange()
    ResetConfigSelection(true)
    wipe(CS.collapsedFolders)
    wipe(CS.collapsedPanels)
    wipe(CS.customAuraBarSubTabs)
    wipe(CS.resourceAuraOverlayDrafts)
    SetPrimaryMode("buttons", { skipRefresh = true })
    if ST._CancelAutoAddFlow then
        ST._CancelAutoAddFlow()
    end
    CooldownCompanion:StopCastBarPreview()
    CooldownCompanion:StopResourceBarPreview()
end

local function MaybeAutoOpenChangelog()
    local changelog = ST._Changelog
    if not changelog then
        return
    end

    local configFrame = CS.configFrame
    if not (configFrame and configFrame.OpenChangelogOverlay) then
        return
    end

    local shouldOpen, version = changelog.ShouldAutoOpen()
    if shouldOpen then
        configFrame.OpenChangelogOverlay(version, { autoOpen = true })
    end
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

    -- Track full dimensions for minimize/expand restore
    local fullHeight = 700
    local fullWidth = 1384

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
        fullWidth = content:GetWidth()
        fullHeight = content:GetHeight()
    end)

    -- Hide the AceGUI status bar and add version text at bottom-right
    if frame.statustext then
        local statusbg = frame.statustext:GetParent()
        if statusbg then statusbg:Hide() end
    end
    local versionText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 20, 25)
    versionText:SetText(GetVersionFooterText())
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
        if frame.HideChangelogOverlay then
            frame.HideChangelogOverlay()
        end
        -- If talent picker is open when panel closes, clean up its raw frames
        -- (RefreshConfigPanel inside CloseTalentPicker is guarded by IsShown, so it's safe)
        if CS.talentPickerMode then
            CooldownCompanion:CloseTalentPicker()
        end
        if CS.CancelPickAuraTexture then
            CS.CancelPickAuraTexture()
        end
        CooldownCompanion:ClearAllProcGlowPreviews()
        CooldownCompanion:ClearAllAuraGlowPreviews()
        CooldownCompanion:ClearAllPandemicPreviews()
        CooldownCompanion:ClearAllReadyGlowPreviews()
        CooldownCompanion:ClearAllKeyPressHighlightPreviews()
        CooldownCompanion:ClearAllBarAuraActivePreviews()
        CooldownCompanion:ClearAllTextureIndicatorPreviews()
        CooldownCompanion:ClearAllAuraTexturePickerPreviews()
        CooldownCompanion:StopCastBarPreview()
        if ClearConfigShiftTooltipHover then
            ClearConfigShiftTooltipHover()
        end
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

    -- Cross-character browse button — between the CDM display toggle and CDM button
    local browseBtn = CreateFrame("Button", nil, content)
    browseBtn:SetSize(16, 16)
    if browseBtn.SetMotionScriptsWhileDisabled then
        browseBtn:SetMotionScriptsWhileDisabled(true)
    end
    local browseIcon = browseBtn:CreateTexture(nil, "ARTWORK")
    browseIcon:SetAtlas("BattleBar-SwapPetIcon", false)
    browseIcon:SetAllPoints()
    browseBtn:SetHighlightAtlas("BattleBar-SwapPetIcon")
    browseBtn:GetHighlightTexture():SetAlpha(0.3)
    local browseBtnBorder = nil
    local browseBtnAvailable = false

    local function UpdateBrowseBtnHighlight()
        local shouldHighlight = browseBtnAvailable and CS.browseMode == true
        if shouldHighlight then
            if not browseBtnBorder then
                browseBtnBorder = browseBtn:CreateTexture(nil, "OVERLAY")
                browseBtnBorder:SetPoint("TOPLEFT", -1, 1)
                browseBtnBorder:SetPoint("BOTTOMRIGHT", 1, -1)
                browseBtnBorder:SetColorTexture(0.85, 0.65, 0.0, 0.6)
            end
            browseBtnBorder:Show()
        elseif browseBtnBorder then
            browseBtnBorder:Hide()
        end
    end

    local function UpdateBrowseBtnState()
        local browseChars = CooldownCompanion:EnumerateBrowseCharacters()
        browseBtnAvailable = #browseChars > 0

        if browseBtn.SetEnabled then
            browseBtn:SetEnabled(browseBtnAvailable)
        end
        if browseIcon.SetDesaturated then
            browseIcon:SetDesaturated(not browseBtnAvailable)
        end
        if browseBtnAvailable then
            browseBtn:SetAlpha(1)
            browseIcon:SetVertexColor(1, 1, 1, 1)
            if browseBtn:GetHighlightTexture() then
                browseBtn:GetHighlightTexture():SetAlpha(0.3)
            end
        else
            browseBtn:SetAlpha(0.75)
            browseIcon:SetVertexColor(0.6, 0.6, 0.6, 1)
            if browseBtn:GetHighlightTexture() then
                browseBtn:GetHighlightTexture():SetAlpha(0)
            end
        end

        UpdateBrowseBtnHighlight()
    end

    browseBtn:SetScript("OnClick", function()
        if not browseBtnAvailable then
            return
        end
        CloseDropDownMenus()
        -- Browse mode lives in the normal button-settings layout, not Bars & Frames.
        if CS.resourceBarPanelActive then
            SetPrimaryMode("buttons", { skipRefresh = true })
        end
        CS.browseMode = true
        CS.browseCharKey = nil
        CS.browseContainerId = nil
        CS.selectedContainer = nil
        CS.selectedGroup = nil
        CS.selectedButton = nil
        wipe(CS.selectedButtons)
        wipe(CS.selectedPanels)
        wipe(CS.selectedGroups)
        CooldownCompanion:RefreshConfigPanel()
    end)
    browseBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Browse Other Characters")
        if not browseBtnAvailable then
            GameTooltip:AddLine("No other characters on this profile currently have groups to browse.", 1, 1, 1, true)
        elseif CS.browseMode then
            GameTooltip:AddLine("Browse mode is active. Click to return to the character list and browse groups from other characters on this profile.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("View and copy groups from other characters on this profile.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    browseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local changelogOverlay
    local changelogBtn
    local changelogBtnBorder = nil
    local function UpdateChangelogBtnHighlight()
        if changelogOverlay and changelogOverlay:IsShown() then
            if not changelogBtnBorder then
                changelogBtnBorder = changelogBtn:CreateTexture(nil, "OVERLAY")
                changelogBtnBorder:SetPoint("TOPLEFT", -1, 1)
                changelogBtnBorder:SetPoint("BOTTOMRIGHT", 1, -1)
                changelogBtnBorder:SetColorTexture(0.85, 0.65, 0.0, 0.6)
            end
            changelogBtnBorder:Show()
        elseif changelogBtnBorder then
            changelogBtnBorder:Hide()
        end
    end

    -- Changelog button — left of Gear
    changelogBtn = CreateFrame("Button", nil, content)
    changelogBtn:SetSize(18, 18)
    local changelogIcon = changelogBtn:CreateTexture(nil, "ARTWORK")
    changelogIcon:SetAtlas("lorewalking-map-icon", false)
    changelogIcon:SetAllPoints()
    changelogBtn:SetHighlightAtlas("lorewalking-map-icon")
    changelogBtn:GetHighlightTexture():SetAlpha(0.3)
    changelogBtn:SetScript("OnClick", function()
        CloseDropDownMenus()
        if frame.ToggleChangelogOverlay then
            frame.ToggleChangelogOverlay()
        end
    end)
    changelogBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("View Changelog")
        GameTooltip:AddLine("Open the bundled release notes for the latest and older versions.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    changelogBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Gear button — left of Collapse
    local gearBtn = CreateFrame("Button", nil, content)
    gearBtn:SetSize(20, 20)
    gearBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -4, 0)
    changelogBtn:SetPoint("RIGHT", gearBtn, "LEFT", -4, 0)
    cdmBtn:SetPoint("RIGHT", changelogBtn, "LEFT", -4, 0)
    browseBtn:SetPoint("RIGHT", cdmBtn, "LEFT", -4, 0)
    cdmDisplayBtn:SetPoint("RIGHT", browseBtn, "LEFT", -4, 0)
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

            local info4 = UIDropDownMenu_CreateInfo()
            info4.text = "  Join Discord"
            info4.notCheckable = true
            info4.func = function()
                CloseDropDownMenus()
                ShowPopupAboveConfig("CDC_DISCORD_INVITE")
            end
            UIDropDownMenu_AddButton(info4, level)
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
            if frame.HideChangelogOverlay then
                frame.HideChangelogOverlay()
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
            content:SetWidth(fullWidth)
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

    -- Bundled changelog overlay (kept separate from column refreshes).
    local changelogContainer
    local changelogScroll
    local changelogVersionDrop
    local changelogFontDownBtn
    local changelogFontUpBtn
    local changelogCloseBtn
    local changelogDropdownUpdating = false
    local changelogScrollStatus = {}
    local CHANGELOG_DROPDOWN_WIDTH = 140
    local CHANGELOG_TEXT_BUTTON_WIDTH = 72
    local CHANGELOG_CLOSE_BUTTON_WIDTH = 72
    local CHANGELOG_CONTROL_ROW_INSET_Y = 12
    local CHANGELOG_CONTROL_ROW_RESERVE = 38
    local changelogContentParent
    local changelogContentTopY = -10

    local function SaveChangelogScroll()
        local status = changelogScroll and (changelogScroll.status or changelogScroll.localstatus)
        return {
            offset = tonumber(status and status.offset) or 0,
            scrollvalue = tonumber(status and status.scrollvalue) or 0,
        }
    end

    local function RestoreChangelogScroll(saved)
        if not changelogScroll then
            return
        end
        changelogScroll:SetScroll(tonumber(saved and saved.scrollvalue) or 0)
        changelogScroll:FixScroll()
    end

    local function AddChangelogSpacer(height)
        local spacer = AceGUI:Create("SimpleGroup")
        spacer:SetFullWidth(true)
        spacer:SetHeight(height)
        spacer.noAutoHeight = true
        -- Hide stale divider texture if this widget was recycled from a previous divider use
        if spacer.frame._changelogDividerTex then
            spacer.frame._changelogDividerTex:Hide()
        end
        changelogScroll:AddChild(spacer)
    end

    local function AddChangelogDivider()
        local divider = AceGUI:Create("SimpleGroup")
        divider:SetFullWidth(true)
        divider:SetHeight(1)
        divider.noAutoHeight = true
        if not divider.frame._changelogDividerTex then
            local tex = divider.frame:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", divider.frame, "TOPLEFT", 0, 0)
            tex:SetPoint("TOPRIGHT", divider.frame, "TOPRIGHT", 0, 0)
            tex:SetHeight(1)
            divider.frame._changelogDividerTex = tex
        end
        divider.frame._changelogDividerTex:SetColorTexture(0.35, 0.35, 0.35, 0.4)
        divider.frame._changelogDividerTex:Show()
        changelogScroll:AddChild(divider)
    end

    local function AddChangelogLabel(text, fontPath, fontSize, fontFlags, color)
        local label = AceGUI:Create("Label")
        label:SetText(text)
        label:SetFullWidth(true)
        label:SetJustifyH("LEFT")
        label:SetJustifyV("TOP")
        label:SetFont(fontPath, fontSize, fontFlags or "")
        if color then
            label:SetColor(color[1], color[2], color[3])
        end
        changelogScroll:AddChild(label)
    end

    local function BuildChangelogListPrefix(depth, orderedIndex, isImportant)
        local indent = string.rep("    ", math.max(0, tonumber(depth) or 0))
        if isImportant then
            return indent .. "|cffFFB347!|r  "
        end
        if orderedIndex then
            return indent .. "|cff4EC9B0" .. tostring(orderedIndex) .. ".|r  "
        end
        return indent .. "|cff4EC9B0\226\128\162|r  "
    end

    local function UpdateChangelogFontButtons()
        local changelog = ST._Changelog
        local fontSize = (changelog and changelog.GetFontSize and changelog.GetFontSize()) or 13
        local minSize, maxSize = 11, 18
        if changelog and changelog.GetFontSizeBounds then
            minSize, maxSize = changelog.GetFontSizeBounds()
        end
        if changelogFontDownBtn then
            changelogFontDownBtn:SetDisabled(fontSize <= minSize)
        end
        if changelogFontUpBtn then
            changelogFontUpBtn:SetDisabled(fontSize >= maxSize)
        end
    end

    local function UpdateChangelogVersionDropdown(selectedVersion)
        if not changelogVersionDrop then
            return
        end

        local changelog = ST._Changelog
        local orderedVersions = (changelog and changelog.GetDropdownVersions and changelog.GetDropdownVersions(selectedVersion))
            or ((changelog and changelog.GetOrderedVersions and changelog.GetOrderedVersions()) or {})
        local versionList = {}
        for _, version in ipairs(orderedVersions) do
            versionList[version] = version
        end

        changelogDropdownUpdating = true
        changelogVersionDrop:SetList(versionList, orderedVersions)
        changelogVersionDrop:SetDisabled(#orderedVersions == 0)
        if #orderedVersions > 0 then
            local value = selectedVersion
            if not value or not versionList[value] then
                value = orderedVersions[1]
            end
            changelogVersionDrop:SetValue(value)
        else
            changelogVersionDrop:SetText("No entries")
        end
        changelogDropdownUpdating = false
    end

    changelogContainer = AceGUI:Create("InlineGroup")
    changelogContainer:SetTitle("Changelog")
    changelogContainer:SetLayout("Fill")
    changelogContainer.frame:SetParent(colParent)
    changelogContainer.frame:ClearAllPoints()
    changelogContainer.frame:SetPoint("TOPLEFT", colParent, "TOPLEFT", 0, 0)
    changelogContainer.frame:SetPoint("BOTTOMRIGHT", colParent, "BOTTOMRIGHT", 0, 0)
    changelogContainer.frame:SetFrameLevel(colParent:GetFrameLevel() + 20)
    changelogContainer.frame:Hide()
    changelogOverlay = changelogContainer.frame

    local changelogHiddenFrames = {}

    changelogScroll = AceGUI:Create("ScrollFrame")
    changelogScroll:SetLayout("List")
    changelogScroll:SetStatusTable(changelogScrollStatus)
    changelogContainer:AddChild(changelogScroll)

    -- Reserve a bottom band for the control row while letting changelog content start at the normal top position.
    if changelogContainer.content then
        changelogContentParent = changelogContainer.content:GetParent()
        local _, _, _, _, origY = changelogContainer.content:GetPoint(1)
        changelogContentTopY = origY or -10
        changelogContainer.content:ClearAllPoints()
        changelogContainer.content:SetPoint("TOPLEFT", changelogContentParent, "TOPLEFT", 10, changelogContentTopY)
        changelogContainer.content:SetPoint("BOTTOMRIGHT", changelogContentParent, "BOTTOMRIGHT", -10, CHANGELOG_CONTROL_ROW_RESERVE)
    end

    changelogCloseBtn = AceGUI:Create("Button")
    changelogCloseBtn:SetText(CLOSE)
    changelogCloseBtn:SetWidth(CHANGELOG_CLOSE_BUTTON_WIDTH)
    changelogCloseBtn:SetHeight(22)
    changelogCloseBtn:SetCallback("OnClick", function()
        if frame.HideChangelogOverlay then
            frame.HideChangelogOverlay()
        end
    end)
    changelogCloseBtn.frame:SetParent(changelogOverlay)
    changelogCloseBtn.frame:ClearAllPoints()
    changelogCloseBtn.frame:SetPoint("BOTTOMRIGHT", changelogContentParent or changelogOverlay, "BOTTOMRIGHT", -10, CHANGELOG_CONTROL_ROW_INSET_Y)
    changelogCloseBtn.frame:Show()

    changelogFontUpBtn = AceGUI:Create("Button")
    changelogFontUpBtn:SetText("Text +")
    changelogFontUpBtn:SetWidth(CHANGELOG_TEXT_BUTTON_WIDTH)
    changelogFontUpBtn:SetHeight(22)
    changelogFontUpBtn:SetCallback("OnClick", function()
        local changelog = ST._Changelog
        if changelog and changelog.AdjustFontSize then
            changelog.AdjustFontSize(1)
        end
        if frame.RenderChangelogOverlay then
            frame.RenderChangelogOverlay(frame._changelogCurrentVersion, true)
        end
    end)
    changelogFontUpBtn:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Increase Text Size")
        GameTooltip:AddLine("Increase changelog text size.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    changelogFontUpBtn:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
    changelogFontUpBtn.frame:SetParent(changelogOverlay)
    changelogFontUpBtn.frame:ClearAllPoints()
    changelogFontUpBtn.frame:SetPoint("RIGHT", changelogCloseBtn.frame, "LEFT", -2, 0)
    changelogFontUpBtn.frame:Show()

    changelogFontDownBtn = AceGUI:Create("Button")
    changelogFontDownBtn:SetText("Text -")
    changelogFontDownBtn:SetWidth(CHANGELOG_TEXT_BUTTON_WIDTH)
    changelogFontDownBtn:SetHeight(22)
    changelogFontDownBtn:SetCallback("OnClick", function()
        local changelog = ST._Changelog
        if changelog and changelog.AdjustFontSize then
            changelog.AdjustFontSize(-1)
        end
        if frame.RenderChangelogOverlay then
            frame.RenderChangelogOverlay(frame._changelogCurrentVersion, true)
        end
    end)
    changelogFontDownBtn:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Decrease Text Size")
        GameTooltip:AddLine("Decrease changelog text size.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    changelogFontDownBtn:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
    changelogFontDownBtn.frame:SetParent(changelogOverlay)
    changelogFontDownBtn.frame:ClearAllPoints()
    changelogFontDownBtn.frame:SetPoint("RIGHT", changelogFontUpBtn.frame, "LEFT", -2, 0)
    changelogFontDownBtn.frame:Show()

    changelogVersionDrop = AceGUI:Create("Dropdown")
    changelogVersionDrop:SetLabel("")
    changelogVersionDrop:SetWidth(CHANGELOG_DROPDOWN_WIDTH)
    changelogVersionDrop:SetPulloutWidth(CHANGELOG_DROPDOWN_WIDTH)
    changelogVersionDrop:SetCallback("OnValueChanged", function(_, _, value)
        if changelogDropdownUpdating or type(value) ~= "string" or value == "" then
            return
        end
        if frame.RenderChangelogOverlay then
            frame.RenderChangelogOverlay(value)
        end
    end)
    changelogVersionDrop.frame:SetParent(changelogOverlay)
    changelogVersionDrop.frame:ClearAllPoints()
    changelogVersionDrop.frame:SetPoint("RIGHT", changelogFontDownBtn.frame, "LEFT", -6, 0)
    changelogVersionDrop.frame:Show()

    local function RenderChangelogOverlay(version, preserveScroll)
        local changelog = ST._Changelog
        local activeVersion = version
        if activeVersion and changelog and not changelog.HasEntry(activeVersion) then
            activeVersion = changelog.GetNewestVersion()
        end

        local savedScroll = preserveScroll and SaveChangelogScroll() or nil
        local bodyFontPath, _, bodyFontFlags = GameFontHighlightSmall:GetFont()
        local headingFontPath, _, headingFontFlags = GameFontNormal:GetFont()
        local bodySize = (changelog and changelog.GetFontSize and changelog.GetFontSize()) or 13
        local heading2Size = bodySize + 4
        local heading3Size = bodySize + 2
        local versionFontSize = heading2Size + 2
        local estimatedVersionHeight = versionFontSize + 8
        local versionBandHeight = math.max(54, versionFontSize + 26)
        local versionTopSpacer = math.max(6, math.floor((versionBandHeight - estimatedVersionHeight) * 0.5))
        local versionBottomSpacer = math.max(6, versionBandHeight - estimatedVersionHeight - versionTopSpacer)

        frame._changelogCurrentVersion = activeVersion
        frame._changelogPreviousVersion = nil
        frame._changelogNextVersion = nil

        changelogScroll:PauseLayout()
        changelogScroll:ReleaseChildren()

        if activeVersion and changelog and changelog.HasEntry(activeVersion) then
            -- Version label at the top of the content
            AddChangelogSpacer(versionTopSpacer)
            AddChangelogLabel("v" .. activeVersion, headingFontPath, versionFontSize, headingFontFlags, {1, 0.82, 0})
            AddChangelogSpacer(versionBottomSpacer)

            local pendingVersionDivider = true
            local function FlushVersionDivider(spacerAfter)
                if not pendingVersionDivider then
                    return false
                end
                AddChangelogDivider()
                if spacerAfter and spacerAfter > 0 then
                    AddChangelogSpacer(spacerAfter)
                end
                pendingVersionDivider = false
                return true
            end

            local tokens = changelog.GetRenderTokens(activeVersion) or {}
            if #tokens == 0 then
                FlushVersionDivider(10)
                AddChangelogLabel("No release notes were bundled for this version.", bodyFontPath, bodySize, bodyFontFlags, {0.92, 0.92, 0.92})
            else
                local renderedAny = false
                for _, token in ipairs(tokens) do
                    local tokenType = token.type or "paragraph"
                    local text = token.text or ""
                    if tokenType == "heading2" then
                        if FlushVersionDivider(12) then
                        elseif renderedAny then
                            AddChangelogSpacer(10)
                            AddChangelogDivider()
                            AddChangelogSpacer(12)
                        else
                            AddChangelogSpacer(10)
                        end
                        AddChangelogLabel(text, headingFontPath, heading2Size, headingFontFlags, {1, 0.82, 0})
                        AddChangelogSpacer(8)
                        renderedAny = true
                    elseif tokenType == "heading3" then
                        if FlushVersionDivider(10) then
                        elseif renderedAny then
                            AddChangelogSpacer(8)
                            AddChangelogDivider()
                            AddChangelogSpacer(10)
                        else
                            AddChangelogSpacer(10)
                        end
                        AddChangelogLabel(text, headingFontPath, heading3Size, headingFontFlags, {1, 0.92, 0.65})
                        AddChangelogSpacer(6)
                        renderedAny = true
                    elseif tokenType == "bullet" then
                        FlushVersionDivider(10)
                        local bulletColor = {0.96, 0.96, 0.96}
                        if token.important then
                            bulletColor = {1.00, 0.91, 0.67}
                        elseif (tonumber(token.depth) or 0) > 0 then
                            bulletColor = {0.70, 0.87, 0.95}
                        end
                        AddChangelogLabel(BuildChangelogListPrefix(token.depth, nil, token.important) .. text, bodyFontPath, bodySize, bodyFontFlags, bulletColor)
                        AddChangelogSpacer(5)
                        renderedAny = true
                    elseif tokenType == "ordered_bullet" then
                        FlushVersionDivider(10)
                        local orderedColor = {0.96, 0.96, 0.96}
                        if token.important then
                            orderedColor = {1.00, 0.91, 0.67}
                        elseif (tonumber(token.depth) or 0) > 0 then
                            orderedColor = {0.70, 0.87, 0.95}
                        end
                        AddChangelogLabel(BuildChangelogListPrefix(token.depth, token.index, token.important) .. text, bodyFontPath, bodySize, bodyFontFlags, orderedColor)
                        AddChangelogSpacer(5)
                        renderedAny = true
                    else
                        FlushVersionDivider(10)
                        AddChangelogLabel(text, bodyFontPath, bodySize, bodyFontFlags, {0.96, 0.96, 0.96})
                        AddChangelogSpacer(6)
                        renderedAny = true
                    end
                end
            end
        else
            AddChangelogSpacer(10)
            AddChangelogLabel("No bundled changelog entries are available for this build yet.", bodyFontPath, bodySize, bodyFontFlags, {0.92, 0.92, 0.92})
        end

        AddChangelogSpacer(4)
        changelogScroll:ResumeLayout()
        changelogScroll:DoLayout()

        UpdateChangelogVersionDropdown(activeVersion)
        UpdateChangelogFontButtons()

        if savedScroll then
            RestoreChangelogScroll(savedScroll)
        else
            changelogScroll:SetScroll(0)
            changelogScroll:FixScroll()
        end
    end

    frame.RenderChangelogOverlay = RenderChangelogOverlay
    frame.HideChangelogOverlay = function()
        if changelogVersionDrop and changelogVersionDrop.open and changelogVersionDrop.pullout then
            changelogVersionDrop.pullout:Close()
        end
        changelogOverlay:Hide()
        for child in pairs(changelogHiddenFrames) do
            child:Show()
        end
        wipe(changelogHiddenFrames)
        UpdateChangelogBtnHighlight()
    end
    frame.OpenChangelogOverlay = function(version, opts)
        local changelog = ST._Changelog
        local targetVersion = version

        if not (changelog and targetVersion and changelog.HasEntry(targetVersion)) then
            targetVersion = changelog and changelog.GetNewestVersion() or nil
        end

        wipe(changelogHiddenFrames)
        for _, child in ipairs({colParent:GetChildren()}) do
            if child ~= changelogOverlay and child:IsShown() then
                changelogHiddenFrames[child] = true
                child:Hide()
            end
        end
        changelogOverlay:Show()
        changelogOverlay:Raise()
        UpdateChangelogBtnHighlight()
        RenderChangelogOverlay(targetVersion)

        if opts and opts.autoOpen and targetVersion and changelog then
            changelog.MarkSeen(targetVersion)
        end
    end
    frame.ToggleChangelogOverlay = function()
        if changelogOverlay:IsShown() then
            frame.HideChangelogOverlay()
        else
            frame.OpenChangelogOverlay()
        end
    end

    -- Column 1: Groups (AceGUI InlineGroup)
    local col1 = AceGUI:Create("InlineGroup")
    col1:SetTitle("Groups")
    col1:SetAutoAdjustHeight(false)
    col1:SetLayout(MANUAL_COLUMN_LAYOUT)
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
        if CS.resourceBarPanelActive then
            GameTooltip:AddLine("Bars & Frames")
            GameTooltip:AddLine("Use the tabs to switch between Resources, Cast Bar, and Unit Frames.", 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Anchoring", 1, 0.82, 0)
            GameTooltip:AddLine("Bars and frames auto-anchor to the first eligible icon panel in your group list, from top to bottom.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Character groups are eligible by default. Global groups are excluded by default.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Reorder groups to control which panel is chosen. Right-click a group to include or exclude it from auto-anchoring.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Groups")
            GameTooltip:AddLine("A group contains one or more panels.", 1, 1, 1)
            GameTooltip:AddLine("Folders are optional organizers for multiple groups.", 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Right-click for options.", 1, 1, 1)
            GameTooltip:AddLine("Hold left-click and drag to reorder.", 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Group Rows", 1, 0.82, 0)
            GameTooltip:AddLine("Left-click to select/deselect.", 1, 1, 1, true)
            GameTooltip:AddLine("Ctrl+Left-click to multi-select.", 1, 1, 1, true)
            GameTooltip:AddLine("Middle-click to toggle lock/unlock.", 1, 1, 1, true)
            GameTooltip:AddLine("Shift+Left-click to set spec filter.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Folders", 1, 0.82, 0)
            GameTooltip:AddLine("Left-click to expand/collapse.", 1, 1, 1)
            GameTooltip:AddLine("Middle-click to lock/unlock all children.", 1, 1, 1, true)
            GameTooltip:AddLine("Shift+Left-click to set folder-wide filters.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    groupInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Column 2: Panels (AceGUI InlineGroup)
    local col2 = AceGUI:Create("InlineGroup")
    col2:SetTitle("Panels")
    col2:SetAutoAdjustHeight(false)
    col2:SetLayout(MANUAL_COLUMN_LAYOUT)
    col2.frame:SetParent(colParent)
    col2.frame:Show()

    -- Info button next to Panels title
    local infoBtn = CreateFrame("Button", nil, col2.frame)
    infoBtn:SetSize(16, 16)
    infoBtn:SetPoint("LEFT", col2.titletext, "RIGHT", -2, 0)
    local infoIcon = infoBtn:CreateTexture(nil, "OVERLAY")
    infoIcon:SetSize(12, 12)
    infoIcon:SetPoint("CENTER")
    infoIcon:SetAtlas("QuestRepeatableTurnin")
    infoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Panels")
        GameTooltip:AddLine("A panel controls dimensions, display mode, and layout for all entries inside it. Every entry needs a panel, even if it's just one.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click to select/deselect.", 1, 1, 1)
        GameTooltip:AddLine("Right-click for options.", 1, 1, 1)
        GameTooltip:AddLine("Hold left-click and drag to reorder.", 1, 1, 1)
        GameTooltip:AddLine("Hold Shift while hovering over an entry to see its tooltip.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Panel Headers", 1, 0.82, 0)
        GameTooltip:AddLine("Double-click to collapse/expand.", 1, 1, 1, true)
        GameTooltip:AddLine("Ctrl+Left-click to multi-select.", 1, 1, 1, true)
        GameTooltip:AddLine("Middle-click to toggle anchor lock.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Buttons", 1, 0.82, 0)
        GameTooltip:AddLine("Ctrl+Left-click to multi-select.", 1, 1, 1, true)
        GameTooltip:AddLine("Middle-click to move to another panel.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag spells/items from your spellbook or inventory onto a panel to add.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    col2._infoBtn = infoBtn

    -- Column 3: Button Settings
    local col3 = AceGUI:Create("InlineGroup")
    col3:SetTitle("Button Settings")
    col3:SetAutoAdjustHeight(false)
    col3:SetLayout(MANUAL_COLUMN_LAYOUT)
    col3.frame:SetParent(colParent)
    col3.frame:Show()

    -- Info button next to Column 3 title
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
            GameTooltip:AddLine("Track any buff or debuff as a resource-style bar.", 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Each slot is configured per-spec and supports autocomplete by name or spell ID.", 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Tracking Modes", 1, 0.82, 0)
            GameTooltip:AddLine("Stack Count: fills the bar based on current stacks (e.g. 3/5 = 60%).", 1, 1, 1)
            GameTooltip:AddLine("Active: shows a full bar that drains as the aura expires.", 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Both modes support optional duration and stack text overlays.", 1, 1, 1)
        elseif CS.autoAddFlowActive then
            GameTooltip:AddLine("Auto Add")
            GameTooltip:AddLine("Guided import flow for Action Bars, Spellbook, and CDM Auras.", 1, 1, 1, true)
        else
            local selection = GetConfigSelectionSummary()
            local mode = GetColumn3HeaderMode(selection)
            if mode == "panel_actions" then
                GameTooltip:AddLine("Panel Actions")
                GameTooltip:AddLine("Select multiple panels to batch-manage them here.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Single-panel settings stay in column 4.", 1, 1, 1, true)
            else
                GameTooltip:AddLine("Button Settings")
                GameTooltip:AddLine("Select a button to configure that entry here.", 1, 1, 1)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("These settings only apply to the selected entry.", 1, 1, 1, true)
            end
        end
        GameTooltip:Show()
    end)
    bsInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Column 4: Group Settings (AceGUI InlineGroup)
    local col4 = AceGUI:Create("InlineGroup")
    col4:SetTitle("Group Settings")
    col4:SetAutoAdjustHeight(false)
    col4:SetLayout(MANUAL_COLUMN_LAYOUT)
    col4.frame:SetParent(colParent)
    col4.frame:Show()

    -- Info button next to Column 4 title
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
            GameTooltip:AddLine("Layout & Order")
                GameTooltip:AddLine("Arrange attached bars by dragging them around the mirrored icon panel.", 1, 1, 1)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("This only applies when resource anchoring is using panel anchoring.", 1, 1, 1)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Horizontal layouts drag bars above or below the icon row.\nVertical layouts drag bars to the left or right of the icon row.", 1, 1, 1)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Layout is saved per specialization and swaps automatically.", 1, 1, 1)
        else
            local selection = GetConfigSelectionSummary()
            local mode = GetColumn4HeaderMode(selection)
            if mode == "panel" then
                GameTooltip:AddLine("Panel Settings")
                if selection.panelMultiCount >= 2 then
                    GameTooltip:AddLine("Select a single panel to configure it here.", 1, 1, 1, true)
                else
                    GameTooltip:AddLine("Select a panel header or any button inside it to configure that panel here.", 1, 1, 1, true)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Panel settings apply to all buttons in that panel.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("If you want to override a setting for one specific button, click the |A:Crosshair_VehichleCursor_32:14:14|a badge next to the associated setting while the button is selected.", 1, 1, 1, true)
            else
                GameTooltip:AddLine("Group Settings")
                if selection.groupMultiCount >= 2 then
                    GameTooltip:AddLine("Select a single group to configure it here.", 1, 1, 1, true)
                elseif selection.hasSelectedGroup then
                    GameTooltip:AddLine("The selected group is configured here.", 1, 1, 1, true)
                else
                    GameTooltip:AddLine("Select a group to configure it here.", 1, 1, 1, true)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Group settings apply to all panels in the group.", 1, 1, 1, true)
            end
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

    -- Static button bar at bottom of column 1 (New Group + New Folder + Import)
    local btnBar = CreateFrame("Frame", nil, col1.content)
    btnBar:SetPoint("BOTTOMLEFT", col1.content, "BOTTOMLEFT", 0, 0)
    btnBar:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 0)
    btnBar:SetHeight(30)
    CS.col1ButtonBar = btnBar

    -- AceGUI ScrollFrames in columns 1 and 2
    local scroll1 = AceGUI:Create("ScrollFrame")
    scroll1:SetLayout("List")
    scroll1.frame:SetParent(col1.content)
    scroll1.frame:ClearAllPoints()
    scroll1.frame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, 0)
    scroll1.frame:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 30)
    scroll1.frame:Show()
    CS.col1Scroll = scroll1

    local scroll2 = AceGUI:Create("ScrollFrame")
    scroll2:SetLayout("List")
    scroll2.frame:SetParent(col2.content)
    scroll2.frame:ClearAllPoints()
    scroll2.frame:SetPoint("TOPLEFT", col2.content, "TOPLEFT", 0, 0)
    scroll2.frame:SetPoint("BOTTOMRIGHT", col2.content, "BOTTOMRIGHT", 0, 30)
    scroll2.frame:Show()
    CS.col2Scroll = scroll2

    -- Static button bar at bottom of column 2 (Icon/Bar/Text Panel)
    local btnBar2 = CreateFrame("Frame", nil, col2.content)
    btnBar2:SetPoint("BOTTOMLEFT", col2.content, "BOTTOMLEFT", 0, 0)
    btnBar2:SetPoint("BOTTOMRIGHT", col2.content, "BOTTOMRIGHT", 0, 0)
    btnBar2:SetHeight(30)
    btnBar2:Hide()
    CS.col2ButtonBar = btnBar2

    -- Button Settings TabGroup. The tab list is refreshed later based on the
    -- selected group's display mode, so texture panels can omit Overrides.
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
        CooldownCompanion:ClearAllReadyGlowPreviews()
        CooldownCompanion:ClearAllKeyPressHighlightPreviews()
        CooldownCompanion:ClearAllBarAuraActivePreviews()
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
            ST._BuildCustomKeybindSection(scroll, buttonData)
            ST._BuildCustomNameSection(scroll, buttonData)
        elseif tab == "soundalerts" then
            ST._BuildSpellSoundAlertsTab(scroll, buttonData, CS.buttonSettingsInfoButtons)
        elseif tab == "overrides" then
            ST._BuildOverridesTab(scroll, buttonData, CS.buttonSettingsInfoButtons)
        end

        if CS.browseMode then
            ST._DisableAllWidgets(scroll)
            for _, btn in ipairs(CS.buttonSettingsInfoButtons) do
                if btn.Disable then btn:Disable() end
            end
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

    -- Per-panel drop highlight system
    local function IsCursorDropPayload(cursorType)
        return cursorType == "spell" or cursorType == "item" or cursorType == "petaction"
    end

    CS._panelDropTargets = {}

    -- Throttled OnUpdate scanner: shows/hides per-panel overlays based on cursor position
    local DROP_SCAN_INTERVAL = 1 / 20  -- 20 Hz
    local dropScanElapsed = 0
    local dropScanFrame = CreateFrame("Frame")

    dropScanFrame:SetScript("OnUpdate", function(self, dt)
        dropScanElapsed = dropScanElapsed + dt
        if dropScanElapsed < DROP_SCAN_INTERVAL then return end
        dropScanElapsed = 0

        local targets = CS._panelDropTargets
        if not targets or #targets == 0 then
            if ClearCol2AnimatedPreview then
                ClearCol2AnimatedPreview()
            end
            self:Hide()
            return
        end

        local hoveredPanelId = nil
        for _, entry in ipairs(targets) do
            if entry.frame:IsMouseOver() then
                hoveredPanelId = entry.panelId
                entry.overlay:SetAlpha(0.01)
                entry.overlay:Show()
            else
                entry.overlay:SetAlpha(1)
                entry.overlay:Hide()
            end
        end

        if UpdateCol2CursorPreview then
            UpdateCol2CursorPreview(hoveredPanelId)
        end
    end)
    dropScanFrame:Hide()

    local function HideAllPanelDropOverlays()
        local targets = CS._panelDropTargets
        if targets then
            for _, entry in ipairs(targets) do
                entry.overlay:SetAlpha(1)
                entry.overlay:Hide()
            end
        end
        if ClearCol2AnimatedPreview then
            ClearCol2AnimatedPreview()
        end
    end

    local function UpdatePanelDropScan()
        local cursorType = GetCursorInfo()
        local targets = CS._panelDropTargets
        if IsCursorDropPayload(cursorType)
            and targets and #targets > 0
            and col2.frame:IsShown() then
            dropScanElapsed = DROP_SCAN_INTERVAL  -- scan immediately on first tick
            dropScanFrame:Show()
        else
            dropScanFrame:Hide()
            HideAllPanelDropOverlays()
        end
    end

    local dropEventFrame = CreateFrame("Frame")
    dropEventFrame:RegisterEvent("CURSOR_CHANGED")
    dropEventFrame:SetScript("OnEvent", function()
        UpdatePanelDropScan()
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
    frame.changelogOverlay = changelogOverlay
    frame.col1 = col1
    frame.col2 = col2
    frame.col3 = col3
    frame.col4 = col4
    frame.colParent = colParent
    frame.LayoutColumns = LayoutColumns
    frame.UpdateModeNavigationUI = UpdateModeNavigationUI
    frame.UpdateBrowseButtonState = UpdateBrowseBtnState
    UpdateBrowseBtnState()
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
    if ClearConfigShiftTooltipHover then
        ClearConfigShiftTooltipHover()
    end

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
    CS.configFrame.versionText:SetText(GetVersionFooterText())
    if CS.configFrame.UpdateModeNavigationUI then
        CS.configFrame.UpdateModeNavigationUI()
    end
    if CS.configFrame.UpdateBrowseButtonState then
        CS.configFrame.UpdateBrowseButtonState()
    end
    RefreshColumn1()
    RefreshColumn2()
    RefreshColumn3()
    RefreshColumn4(CS.col4Container)
    ApplyConfigColumnTitles(CS.configFrame)

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
            if not (CS.configFrame and CS.configFrame.frame and CS.configFrame.frame:IsShown()) then
                return
            end
            CooldownCompanion:RefreshConfigPanel()
            MaybeAutoOpenChangelog()
        end)
        return -- AceGUI Frame is already shown on creation
    end

    -- If minimized, close everything and reset state
    if CS.configFrame._miniFrame and CS.configFrame._miniFrame:IsShown() then
        if CS.configFrame.HideChangelogOverlay then
            CS.configFrame.HideChangelogOverlay()
        end
        CS.configFrame._miniFrame:Hide()
        return
    end

    if CS.configFrame.frame:IsShown() then
        CS.configFrame.frame:Hide()
    else
        SetPrimaryMode("buttons", { skipRefresh = true })
        CS.configFrame.frame:Show()
        self:RefreshConfigPanel()
        MaybeAutoOpenChangelog()
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
            if CooldownCompanion.db.profile.groupContainers then
                for _, container in pairs(CooldownCompanion.db.profile.groupContainers) do
                    if not container.isGlobal then
                        container.createdBy = charKey
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
