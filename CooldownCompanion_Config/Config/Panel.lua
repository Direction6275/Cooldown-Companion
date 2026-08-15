--[[
    CooldownCompanion - Config/Panel
    Panel creation and loaded-config implementation hooks.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local ResetConfigSelection = ST._ResetConfigSelection
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local COLUMN_PADDING = ST._COLUMN_PADDING
local RefreshColumn1 = ST._RefreshColumn1
local RefreshColumn3 = ST._RefreshColumn3
local RefreshProfileBar = ST._RefreshProfileBar
local SetConfigPrimaryMode = ST._SetConfigPrimaryMode
local ClearConfigShiftTooltipHover = ST._ClearConfigShiftTooltipHover
local GetConfigEntryDisplayName = ST._GetConfigEntryDisplayName
local IsConfigFinderAvailable = ST._IsConfigFinderAvailable
local IsConfigFinderActive = ST._IsConfigFinderActive
local SetConfigFinderText = ST._SetConfigFinderText
local ClearConfigFinderText = ST._ClearConfigFinderText
local InvalidateConfigFinderResults = ST._InvalidateConfigFinderResults
local BuildConfigFinderResults = ST._BuildConfigFinderResults
local MaybeAutoStartFirstIconPanelTutorial = ST._MaybeAutoStartFirstIconPanelTutorial
local StartFirstIconPanelTutorial = ST._StartFirstIconPanelTutorial
local CancelFirstIconPanelTutorial = ST._CancelFirstIconPanelTutorial
local RebuildTutorialAnchors = ST._RebuildTutorialAnchors
local RefreshTutorialPlacement = ST._RefreshTutorialPlacement
local SetupChangelogOverlay = ST._SetupChangelogOverlay
local RefreshVisibleConfigCompactRows = ST._RefreshVisibleConfigCompactRows

local function ClearTransientConfigPreviewState()
    CS.textureConfigPreviewStage = nil
    if CooldownCompanion.ClearAllConfigPreviews then
        CooldownCompanion:ClearAllConfigPreviews()
    end
end

local MANUAL_COLUMN_LAYOUT = "CDC_MANUAL"
local CONFIG_FINDER_BOX_HEIGHT = 28
local CONFIG_FINDER_BUTTON_GAP = 3
local CONFIG_FINDER_RESERVED_HEIGHT = CONFIG_FINDER_BOX_HEIGHT + CONFIG_FINDER_BUTTON_GAP
local NAVIGATOR_DESTINATIONS_HEIGHT = 33
local CONFIG_COMPACT_ROW_MIN_WIDTH = 236
local NAVIGATOR_WIDTH = 300
local CONFIG_DRAG_ALPHA = 0.40
local PROFILE_WIDE_FONT_WINDOW_FALLBACK_WIDTH = 330
local PROFILE_WIDE_FONT_WINDOW_HEIGHT = 168
local PROFILE_WIDE_BAR_TEXTURE_WINDOW_HEIGHT = 106

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
    local footer = version .. "  |  " .. (CooldownCompanion.db:GetCurrentProfile() or "Default")
    if CooldownCompanion._unsupportedLegacyProfile then
        footer = footer .. "  |  Unsupported Profile"
    end
    return footer
end

local function GetProfileWideSideWindowWidth()
    local configFrame = CS.configFrame
    local narrowestWidth

    for _, columnKey in ipairs({ "col1", "col3" }) do
        local column = configFrame and configFrame[columnKey]
        local frame = column and column.frame
        local visible = frame and (frame:IsVisible() or frame:IsShown())
        if visible then
            local width = frame:GetWidth()
            if width and width > 0 then
                narrowestWidth = narrowestWidth and math.min(narrowestWidth, width) or width
            end
        end
    end

    return math.floor((narrowestWidth or PROFILE_WIDE_FONT_WINDOW_FALLBACK_WIDTH) + 0.5)
end

-- One placement rule for every window that hangs off the config's side:
-- right when it fits, left when only the left has room, and otherwise a
-- right anchor slid just far enough left to stay on-screen over the config.
-- Positions are measured in physical coordinates so the config and side
-- window scales can differ; the returned x offset is in the side window's
-- own scale, for the anchor point the returned side implies (TOPLEFT to
-- TOPRIGHT when "right", TOPRIGHT to TOPLEFT when "left").
local SIDE_WINDOW_GAP = 4

local function ComputeConfigSidePlacement(sideFrame, windowWidth)
    local configFrame = CS.configFrame
    local cf = configFrame and configFrame.frame
    if not (cf and cf:IsShown() and sideFrame) then
        return "right", SIDE_WINDOW_GAP
    end
    local wfScale = sideFrame:GetEffectiveScale()
    local cfScale = cf:GetEffectiveScale()
    local cfLeft, cfRight = cf:GetLeft(), cf:GetRight()
    if not (cfLeft and cfRight and wfScale and wfScale > 0) then
        return "right", SIDE_WINDOW_GAP
    end
    local screenRight = UIParent:GetRight() * UIParent:GetEffectiveScale()
    local needed = (windowWidth + SIDE_WINDOW_GAP) * wfScale
    local spaceRight = screenRight - cfRight * cfScale
    local spaceLeft = cfLeft * cfScale
    if spaceRight >= needed or spaceLeft < needed then
        local overflow = needed - spaceRight
        return "right", SIDE_WINDOW_GAP - (overflow > 0 and overflow / wfScale or 0)
    end
    return "left", -SIDE_WINDOW_GAP
end
ST._ComputeConfigSidePlacement = ComputeConfigSidePlacement

local function CleanupProfileWideSideWindow(widget, stateKey)
    if CS.UnregisterConfigDragAlphaFrame then
        CS.UnregisterConfigDragAlphaFrame(widget.frame)
    end
    widget:ReleaseChildren()
    AceGUI:Release(widget)
    CS[stateKey] = nil
end

local function CloseProfileWideSideWindow(stateKey)
    local window = CS[stateKey]
    if window then
        window:Hide()
        return true
    end
    return false
end

local function AnchorProfileWideSideWindow(window)
    local configFrame = CS.configFrame
    if configFrame and configFrame.frame and configFrame.frame:IsShown() then
        local wf = window.frame
        wf:ClearAllPoints()
        local width = wf:GetWidth()
        if not width or width <= 0 then
            width = GetProfileWideSideWindowWidth()
        end
        local side, xOff = ComputeConfigSidePlacement(wf, width)
        if side == "left" then
            wf:SetPoint("TOPRIGHT", configFrame.frame, "TOPLEFT", xOff, 0)
        else
            wf:SetPoint("TOPLEFT", configFrame.frame, "TOPRIGHT", xOff, 0)
        end
    end
end

local function PrepareProfileWideSideWindow(stateKey, title, height)
    local window = CS[stateKey]
    if not window then
        window = AceGUI:Create("Window")
        window:SetTitle(title)
        window:SetWidth(GetProfileWideSideWindowWidth())
        window:SetHeight(height)
        window:SetLayout("List")
        window:EnableResize(false)
        window:SetCallback("OnClose", function(widget)
            CleanupProfileWideSideWindow(widget, stateKey)
        end)
        CS[stateKey] = window
        if CS.RegisterConfigDragAlphaFrame then
            CS.RegisterConfigDragAlphaFrame(window.frame)
        end
    else
        window:Show()
        window.frame:Raise()
        window:ReleaseChildren()
        window:SetWidth(GetProfileWideSideWindowWidth())
    end

    AnchorProfileWideSideWindow(window)
    return window
end

local function CloseProfileWideFontWindow()
    return CloseProfileWideSideWindow("profileWideFontWindow")
end

local function CloseProfileWideBarTextureWindow()
    return CloseProfileWideSideWindow("profileWideBarTextureWindow")
end

local function OpenProfileWideFontWindow()
    if not ST.IsProfileWideFontEnabled or not ST.IsProfileWideFontEnabled() then
        CloseProfileWideFontWindow()
        return
    end

    if CS.CloseAdvancedSettingsPanel then
        CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
    end
    if CS.CancelPickAuraTexture then
        CS.CancelPickAuraTexture()
    end
    if CS.CloseSpellbookPanel then
        CS.CloseSpellbookPanel()
    end
    CloseProfileWideBarTextureWindow()

    local window = PrepareProfileWideSideWindow("profileWideFontWindow", "Profile-wide Font + Outline", PROFILE_WIDE_FONT_WINDOW_HEIGHT)

    local dropdown = AceGUI:Create("Dropdown")
    dropdown:SetLabel("Font")
    CS.SetupFontDropdown(dropdown, { ignoreProfileWideFontLock = true })
    dropdown:SetValue(CS.GetProfileWideFontPickerValue and CS.GetProfileWideFontPickerValue() or ST.DEFAULT_FONT_NAME or "Friz Quadrata TT")
    dropdown:SetFullWidth(true)
    CS.SetFontDropdownCallback(dropdown, function(widget, event, val)
        CooldownCompanion:SetProfileWideFontName(val, { enable = true })
    end, { ignoreProfileWideFontLock = true })
    window:AddChild(dropdown)

    local outlineDrop = AceGUI:Create("Dropdown")
    outlineDrop:SetLabel("Outline")
    CS.SetupFontOutlineDropdown(outlineDrop, { ignoreProfileWideFontLock = true })
    outlineDrop:SetValue(CS.GetProfileWideFontOutlinePickerValue and CS.GetProfileWideFontOutlinePickerValue() or ST.DEFAULT_FONT_OUTLINE or "OUTLINE")
    outlineDrop:SetFullWidth(true)
    CS.SetFontOutlineDropdownCallback(outlineDrop, function(widget, event, val)
        CooldownCompanion:SetProfileWideFontOutline(val, { enable = true })
    end, { ignoreProfileWideFontLock = true })
    window:AddChild(outlineDrop)
end

local function OpenProfileWideBarTextureWindow()
    if not ST.IsProfileWideBarTextureEnabled or not ST.IsProfileWideBarTextureEnabled() then
        CloseProfileWideBarTextureWindow()
        return
    end

    if CS.CloseAdvancedSettingsPanel then
        CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
    end
    if CS.CancelPickAuraTexture then
        CS.CancelPickAuraTexture()
    end
    if CS.CloseSpellbookPanel then
        CS.CloseSpellbookPanel()
    end
    CloseProfileWideFontWindow()

    local window = PrepareProfileWideSideWindow("profileWideBarTextureWindow", "Profile-wide Bar Texture", PROFILE_WIDE_BAR_TEXTURE_WINDOW_HEIGHT)

    local dropdown = AceGUI:Create("Dropdown")
    dropdown:SetLabel("Bar Texture")
    CS.SetupBarTextureDropdown(dropdown, { ignoreProfileWideBarTextureLock = true })
    dropdown:SetValue(CS.GetProfileWideBarTexturePickerValue and CS.GetProfileWideBarTexturePickerValue() or "Solid")
    dropdown:SetFullWidth(true)
    CS.SetBarTextureDropdownCallback(dropdown, function(widget, event, val)
        CooldownCompanion:SetProfileWideBarTextureName(val, { enable = true })
    end, { ignoreProfileWideBarTextureLock = true })
    window:AddChild(dropdown)
end

CS.CloseProfileWideFontWindow = CloseProfileWideFontWindow
CS.CloseProfileWideBarTextureWindow = CloseProfileWideBarTextureWindow

if not AceGUI:GetLayout(MANUAL_COLUMN_LAYOUT) then
    -- These columns are positioned and sized manually, so their layout should
    -- not call LayoutFinished and auto-shrink them based on child height.
    AceGUI:RegisterLayout(MANUAL_COLUMN_LAYOUT, function()
    end)
end

local function HasOtherClassInventory()
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if not db then return false, false, false end

    local searchFiltered = IsConfigFinderActive and IsConfigFinderActive() and BuildConfigFinderResults ~= nil
    local searchResults = searchFiltered and BuildConfigFinderResults() or nil
    local hasOtherInventory = false

    if CooldownCompanion.ResolveContainerClassScope then
        for id, container in pairs(db.groupContainers or {}) do
            local scope = CooldownCompanion:ResolveContainerClassScope(container or id)
            if scope and scope.scope == "other-class" then
                hasOtherInventory = true
                if not searchFiltered or (searchResults and searchResults.containerMatches and searchResults.containerMatches[id]) then
                    return true, searchFiltered == true, true
                end
            end
        end
    end

    return false, searchFiltered == true, hasOtherInventory
end

local function ShouldShowOtherClassNavigatorRow()
    local _, _, hasInventory = HasOtherClassInventory()
    return hasInventory or CS.otherClassLibraryActive == true
end
ST._ShouldShowOtherClassNavigatorRow = ShouldShowOtherClassNavigatorRow

-- 8px top offset + 24px per row (+1 slack). The second row appears only when
-- another class has browsable inventory.
local function GetNavigatorDestinationsHeight()
    return ShouldShowOtherClassNavigatorRow() and (NAVIGATOR_DESTINATIONS_HEIGHT + 24) or NAVIGATOR_DESTINATIONS_HEIGHT
end

-- Title bar buttons share one flat monochrome treatment: desaturated glyphs
-- in the Navigator's muted label color, tinted to the class color on hover
-- (destructive buttons pass their own hover color).
local TITLEBAR_ICON_R, TITLEBAR_ICON_G, TITLEBAR_ICON_B = 0.82, 0.78, 0.70

local function GetTitlebarHoverColor()
    local _, classKey = UnitClass("player")
    local color = classKey and C_ClassColor.GetClassColor(classKey)
    return color and color.r or 0.40, color and color.g or 0.67, color and color.b or 1.0
end

local function UpdateTitlebarButtonTint(button)
    local icon = button._cdcTitlebarIcon
    if not icon then return end
    if button._cdcTitlebarHovered then
        if button._cdcTitlebarHoverR then
            icon:SetVertexColor(button._cdcTitlebarHoverR, button._cdcTitlebarHoverG, button._cdcTitlebarHoverB, 1)
        else
            local r, g, b = GetTitlebarHoverColor()
            icon:SetVertexColor(r, g, b, 1)
        end
    else
        icon:SetVertexColor(TITLEBAR_ICON_R, TITLEBAR_ICON_G, TITLEBAR_ICON_B, 1)
    end
end

-- Call after the button's own OnEnter/OnLeave scripts are set: SetScript
-- replaces hooks, so the tint hooks must be installed last.
local function SkinTitlebarButton(button, icon, hoverR, hoverG, hoverB)
    icon:SetDesaturated(true)
    button._cdcTitlebarIcon = icon
    button._cdcTitlebarHoverR = hoverR
    button._cdcTitlebarHoverG = hoverG
    button._cdcTitlebarHoverB = hoverB
    button:HookScript("OnEnter", function(self)
        self._cdcTitlebarHovered = true
        UpdateTitlebarButtonTint(self)
    end)
    button:HookScript("OnLeave", function(self)
        self._cdcTitlebarHovered = nil
        UpdateTitlebarButtonTint(self)
    end)
    UpdateTitlebarButtonTint(button)
end

local function GetResourceSettingsColumnTitle()
    local powerType = tonumber(CS.selectedResourcePowerType)
    local powerNames = ST._RB and ST._RB.POWER_NAMES
    local resourceName = powerType and powerNames and powerNames[powerType] or nil
    if resourceName and resourceName ~= "" then
        return "Resource: " .. resourceName
    end
    return "Resource Settings"
end

local function CountSelections(selectionSet)
    local count = 0
    for _ in pairs(selectionSet or {}) do
        count = count + 1
    end
    return count
end

local function GetConfigProfile()
    return CooldownCompanion.db and CooldownCompanion.db.profile
end

local function NormalizeHeaderName(name)
    if type(name) ~= "string" then
        return nil
    end
    local trimmed = name:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        return nil
    end
    return trimmed
end

local function GetSelectedEntryHeaderName()
    if not (CS.selectedGroup and CS.selectedButton) then
        return nil
    end
    if next(CS.selectedButtons) then
        return nil
    end

    local profile = GetConfigProfile()
    local group = profile and profile.groups and profile.groups[CS.selectedGroup]
    local buttonData = group and group.buttons and group.buttons[CS.selectedButton]
    return buttonData and NormalizeHeaderName(GetConfigEntryDisplayName(buttonData))
end

local function GetSelectedPanelHeaderName(selection)
    if not selection or selection.panelMultiCount >= 2 or not CS.selectedGroup then
        return nil
    end

    local profile = GetConfigProfile()
    local group = profile and profile.groups and profile.groups[CS.selectedGroup]
    return group and NormalizeHeaderName(group.name)
end

local function GetSelectedGroupHeaderName(selection)
    if not selection or selection.groupMultiCount >= 2 or not CS.selectedContainer or CS.selectedGroup then
        return nil
    end

    local profile = GetConfigProfile()
    local container = profile and profile.groupContainers and profile.groupContainers[CS.selectedContainer]
    return container and NormalizeHeaderName(container.name)
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
    -- The bars workspace shows whichever object is selected: a cast/frames
    -- item first, otherwise the Resources home and its editing surfaces.
    -- With every module disabled the overview pane replaces all of them.
    local barsOverview = CS.barsEntrySelected
        and ST._IsBarsOverviewActive
        and ST._IsBarsOverviewActive()
    if barsOverview then
        return "bars_overview"
    end
    if CS.barsEntrySelected and CS.castFramesSelectedItem then
        if CS.castFramesSelectedItem == "player" then
            return "player_frame"
        elseif CS.castFramesSelectedItem == "target" then
            return "target_frame"
        end
        return "cast_bar"
    end
    if CS.barsEntrySelected then
        local resourceBarSettings = CooldownCompanion:GetResourceBarSettings()
        if resourceBarSettings and resourceBarSettings.enabled == true then
            if CS.selectedResourcePowerType
                and ST._RBP
                and ST._RBP.IsResourceEditableInColumn4
                and ST._RBP.IsResourceEditableInColumn4(CS.selectedResourcePowerType, resourceBarSettings, true)
            then
                return "resource_settings"
            end
            if CS.selectedCustomBarId then
                return "custom_bar"
            end
        end
        return "resources_panel"
    end
    if selection.groupMultiCount >= 2 then
        return "group_actions"
    end
    if selection.panelMultiCount >= 2 then
        return "panel_actions"
    end
    return "button"
end

-- Group-side titles (panel / group): used for the workspace
-- header during Other Class browsing, where it hosts both entry and
-- group-side settings.
local function GetGroupSideHeaderMode(selection)
    if selection.panelMultiCount >= 2 or selection.hasSelectedPanel then
        return "panel"
    end
    return "group"
end

local function GetGroupSideHeaderTitle(selection)
    local mode = GetGroupSideHeaderMode(selection)
    if mode == "panel" then
        local panelName = GetSelectedPanelHeaderName(selection)
        if panelName then
            return "Panel: " .. panelName
        end
        return "Panel Settings"
    end
    local groupName = GetSelectedGroupHeaderName(selection)
    if groupName then
        return "Group: " .. groupName
    end
    return "Group Settings"
end

local function GetColumn3HeaderTitle(selection)
    local mode = GetColumn3HeaderMode(selection)
    if mode == "bars_overview" then
        return "Resources, Cast Bar & Unit Frames"
    elseif mode == "resources_panel" then
        return "Resource Bars"
    elseif mode == "resource_settings" then
        return GetResourceSettingsColumnTitle()
    elseif mode == "custom_bar" then
        return "Custom Bar Settings"
    elseif mode == "cast_bar" then
        return "Cast Bar"
    elseif mode == "player_frame" then
        return "Player Frame"
    elseif mode == "target_frame" then
        return "Target Frame"
    elseif mode == "group_actions" then
        return "Group Actions"
    elseif mode == "panel_actions" then
        return "Panel Actions"
    end
    if ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive() then
        -- Merged wide column: the identity strip under the preview names
        -- the selection, so the header stays static instead of tracking it.
        return "Buttons"
    end
    -- Other Class browsing: no identity strip, so name whatever the wide
    -- column is showing - the selected entry or the group-side selection.
    local entryName = GetSelectedEntryHeaderName()
    if entryName then
        return "Entry: " .. entryName
    end
    return GetGroupSideHeaderTitle(selection)
end

local function ApplyConfigColumnTitles(frame)
    if CS.exportMode then
        frame.col1:SetTitle("|cffffd100Export Mode|r")
        frame.col3:SetTitle("|cffffd100Export Summary|r")
        return
    end
    if CS.importMode then
        frame.col1:SetTitle("|cffffd100Import Mode|r")
        frame.col3:SetTitle("|cffffd100Import Summary|r")
        return
    end
    frame.col1:SetTitle("Navigator")

    local selection = GetConfigSelectionSummary()
    -- Two labeled workspace areas: while a pinned preview is showing, the
    -- column title names the preview region and the editing surface below
    -- the divider carries its own "Editing:" header; without a preview the
    -- title keeps naming the settings content.
    local activeHost = frame.col3._cdcActiveWideHost
    if activeHost and activeHost:IsShown() then
        frame.col3:SetTitle("Live Preview")
    else
        frame.col3:SetTitle(GetColumn3HeaderTitle(selection))
    end
end

local function SaveScrollState(widget)
    if not widget then return nil end
    local state = widget.status or widget.localstatus
    if not state then return nil end

    local offset = tonumber(state.offset) or 0
    local scrollvalue = tonumber(state.scrollvalue) or 0
    if offset <= 0 and scrollvalue <= 0 then
        return nil
    end

    return {
        offset = state.offset,
        scrollvalue = state.scrollvalue,
    }
end

local function RestoreScrollState(widget, saved)
    if not (widget and saved) then return end
    local state = widget.status or widget.localstatus
    if not state then return end
    state.offset = saved.offset
    state.scrollvalue = saved.scrollvalue
end

local function ClearScrollState(widget)
    if not widget then return end
    local state = widget.status or widget.localstatus
    if not state then return end
    state.offset = nil
    state.scrollvalue = nil
end

local function ResetScrollState(widget)
    if not widget then return end
    ClearScrollState(widget)
    if widget.SetScroll then
        widget:SetScroll(0)
    end
end

local pendingOverrideConfigRefreshToken = 0
local pendingOverrideSpellIds = {}
local pendingConfigFinderRefreshToken = 0

local function IsConfigFrameOpenForRefresh()
    return CS.configFrame
        and CS.configFrame.frame
        and CS.configFrame.frame:IsShown()
        and not CS.talentPickerMode
end

local function QueueConfigFinderRefresh()
    pendingConfigFinderRefreshToken = pendingConfigFinderRefreshToken + 1
    local token = pendingConfigFinderRefreshToken
    C_Timer.After(0.1, function()
        if pendingConfigFinderRefreshToken ~= token then return end
        if not IsConfigFrameOpenForRefresh() then return end

        local finderActive = IsConfigFinderActive and IsConfigFinderActive()
        local saved1 = not finderActive and SaveScrollState(CS.col1Scroll) or nil
        if finderActive then
            ResetScrollState(CS.col1Scroll)
        end
        RefreshColumn1()
        if CS.configFrame.UpdateCompactConfigRows then
            CS.configFrame.UpdateCompactConfigRows()
        end
        ApplyConfigColumnTitles(CS.configFrame)
        if finderActive then
            ResetScrollState(CS.col1Scroll)
        else
            RestoreScrollState(CS.col1Scroll, saved1)
        end
    end)
end

local function IsConfigSpellOverrideRefreshMode()
    if not IsConfigFrameOpenForRefresh() then
        return false
    end
    if CountSelections(CS.selectedGroups) >= 2 then
        return false
    end
    return CS.selectedContainer ~= nil
end

local function IsPendingOverrideSpellId(spellID, pendingSpellIds)
    return spellID and spellID ~= 0 and pendingSpellIds and pendingSpellIds[spellID] == true
end

local function DoesButtonReferencePendingOverrideSpell(buttonData, pendingSpellIds)
    if not (buttonData and buttonData.type == "spell") then
        return false
    end
    if IsPendingOverrideSpellId(buttonData.id, pendingSpellIds) then
        return true
    end

    local overrideSpellID = C_Spell.GetOverrideSpell(buttonData.id)
    return IsPendingOverrideSpellId(overrideSpellID, pendingSpellIds)
end

local function GetSelectedConfigButtonData()
    if not (CS.selectedGroup and CS.selectedButton) then
        return nil
    end
    if next(CS.selectedButtons) then
        return nil
    end

    local profile = GetConfigProfile()
    local group = profile and profile.groups and profile.groups[CS.selectedGroup]
    return group and group.buttons and group.buttons[CS.selectedButton]
end

local function DoesSelectedPanelReferencePendingOverrideSpell(pendingSpellIds)
    local profile = GetConfigProfile()
    local group = profile and profile.groups and profile.groups[CS.selectedGroup]
    for _, buttonData in ipairs(group and group.buttons or {}) do
        if DoesButtonReferencePendingOverrideSpell(buttonData, pendingSpellIds) then
            return true
        end
    end
    return false
end

function CooldownCompanion:DoesCurrentConfigSelectionReferenceSpell(pendingSpellIds)
    if not IsConfigSpellOverrideRefreshMode() then
        return false
    end

    local selectedButtonData = GetSelectedConfigButtonData()
    if DoesButtonReferencePendingOverrideSpell(selectedButtonData, pendingSpellIds) then
        return true
    end

    -- Entries render only on the selected panel's mirror in the workspace,
    -- so scan the selected panel unconditionally.
    if ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive() then
        return DoesSelectedPanelReferencePendingOverrideSpell(pendingSpellIds)
    end

    local panels = self:GetPanels(CS.selectedContainer)
    for _, panelInfo in ipairs(panels or {}) do
        local panelId = panelInfo.groupId
        local panel = panelInfo.group
        local entriesVisible = not CS.collapsedPanels[panelId]
        if entriesVisible and panel and panel.buttons then
            for _, buttonData in ipairs(panel.buttons) do
                if DoesButtonReferencePendingOverrideSpell(buttonData, pendingSpellIds) then
                    return true
                end
            end
        end
    end

    return false
end

function CooldownCompanion:RefreshConfigForSpellOverride(pendingSpellIds)
    if not self:DoesCurrentConfigSelectionReferenceSpell(pendingSpellIds) then
        return false
    end

    local savedButtonSettings = SaveScrollState(CS.buttonSettingsScroll)
    local selectedEntryAffected = DoesButtonReferencePendingOverrideSpell(GetSelectedConfigButtonData(), pendingSpellIds)

    if CS.configFrame.UpdateCompactConfigRows then
        CS.configFrame.UpdateCompactConfigRows()
    end
    if selectedEntryAffected then
        RefreshColumn3()
    elseif ST._RefreshButtonsPreviewMirror
        and DoesSelectedPanelReferencePendingOverrideSpell(pendingSpellIds) then
        -- A non-selected entry of the mirrored panel picked up the override;
        -- its name and icon render on the mirror.
        ST._RefreshButtonsPreviewMirror()
    end
    ApplyConfigColumnTitles(CS.configFrame)

    if selectedEntryAffected then
        RestoreScrollState(CS.buttonSettingsScroll, savedButtonSettings)
    end

    return true
end

function CooldownCompanion:QueueOverrideConfigRefresh(baseSpellID, overrideSpellID)
    if not IsConfigFrameOpenForRefresh() then
        return
    end

    if baseSpellID and baseSpellID ~= 0 then
        pendingOverrideSpellIds[baseSpellID] = true
    end
    if overrideSpellID and overrideSpellID ~= 0 then
        pendingOverrideSpellIds[overrideSpellID] = true
    end
    if not next(pendingOverrideSpellIds) then
        return
    end

    pendingOverrideConfigRefreshToken = pendingOverrideConfigRefreshToken + 1
    local token = pendingOverrideConfigRefreshToken
    C_Timer.After(0.1, function()
        if pendingOverrideConfigRefreshToken ~= token then return end
        if not IsConfigFrameOpenForRefresh() then
            wipe(pendingOverrideSpellIds)
            return
        end

        local queuedSpellIds = pendingOverrideSpellIds
        pendingOverrideSpellIds = {}
        self:RefreshConfigForSpellOverride(queuedSpellIds)
    end)
end

-- Shared reset for profile change/copy/reset callbacks
local function ResetConfigForProfileChange()
    CloseProfileWideFontWindow()
    CloseProfileWideBarTextureWindow()
    if CancelFirstIconPanelTutorial then
        CancelFirstIconPanelTutorial("profile_changed")
    end
    -- Export/import selections name entities in the OUTGOING profile; left
    -- standing they would resolve against the new profile's ids and export
    -- or import something the user never picked. A refresh follows this.
    if CS.exportMode and ST._ExitExportMode then
        ST._ExitExportMode({ skipRefresh = true })
    end
    if CS.importMode and ST._ExitImportMode then
        ST._ExitImportMode({ skipRefresh = true })
    end
    ResetConfigSelection(true)
    wipe(CS.collapsedPanels)
    if ClearConfigFinderText then
        ClearConfigFinderText()
    end
    SetConfigPrimaryMode("buttons", { skipRefresh = true })
end

function CooldownCompanion:_configResetForProfileChangeImpl()
    ResetConfigForProfileChange()
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
-- Config window geometry (size and position persist account-wide)
------------------------------------------------------------------------
local CONFIG_WINDOW_DEFAULT_WIDTH = 1180
local CONFIG_WINDOW_DEFAULT_HEIGHT = 780
-- Must match the SetResizeBounds call in CreateConfigPanel.
local CONFIG_WINDOW_MIN_WIDTH = 993
local CONFIG_WINDOW_MIN_HEIGHT = 400

-- Every side window follows the config's settled geometry; run from
-- SaveConfigWindowGeometry so any move, resize, or reset re-picks their side.
local function ReanchorConfigSideWindows()
    for _, stateKey in ipairs({ "profileWideFontWindow", "profileWideBarTextureWindow" }) do
        local sideWindow = CS[stateKey]
        if sideWindow then
            AnchorProfileWideSideWindow(sideWindow)
        end
    end
    if ST._ReanchorSpellbookPanelWindow then
        ST._ReanchorSpellbookPanelWindow()
    end
    if ST._ReanchorAdvancedSettingsPanels then
        ST._ReanchorAdvancedSettingsPanels()
    end
end

local function SaveConfigWindowGeometry(content)
    local db = CooldownCompanion.db
    local global = db and db.global
    -- GetLeft is nil until the frame has settled at least one layout pass.
    if not (global and content:GetLeft()) then return end
    local geo = global.configWindow
    if not geo then
        geo = {}
        global.configWindow = geo
    end
    geo.width = content:GetWidth()
    geo.height = content:GetHeight()
    geo.left = content:GetLeft()
    geo.top = content:GetTop()
    ReanchorConfigSideWindows()
end

-- Apply saved (or default) window size, clamped to the current screen: at
-- UI scale 1.0 the whole screen is only 768 units tall, so the taller
-- default and any geometry saved under a different scale/resolution must
-- shrink to fit rather than overflow. A saved position is re-clamped the
-- same way; with none saved the frame keeps AceGUI's centered default.
local function ApplyConfigWindowGeometry(frame)
    local content = frame.frame
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()
    local db = CooldownCompanion.db
    local geo = db and db.global and db.global.configWindow
    local width = (geo and geo.width) or CONFIG_WINDOW_DEFAULT_WIDTH
    local height = (geo and geo.height) or CONFIG_WINDOW_DEFAULT_HEIGHT
    width = math.max(CONFIG_WINDOW_MIN_WIDTH,
        math.min(width, screenWidth * 0.95))
    height = math.max(CONFIG_WINDOW_MIN_HEIGHT,
        math.min(height, screenHeight * 0.9))
    frame:SetWidth(width)
    frame:SetHeight(height)
    if geo and geo.left and geo.top then
        local left = math.max(0, math.min(geo.left, screenWidth - width))
        local top = math.max(height, math.min(geo.top, screenHeight))
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
end

------------------------------------------------------------------------
-- Main Panel Creation
------------------------------------------------------------------------
local function CreateConfigPanel()
    if CS.configFrame then return CS.configFrame end

    -- Main AceGUI Frame
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Cooldown Companion")
    frame:SetStatusText("")
    ApplyConfigWindowGeometry(frame)
    frame:SetLayout(nil) -- manual positioning

    -- Store the raw frame for raw child parenting
    local content = frame.frame
    -- Get the content area (below the title bar)
    local contentFrame = frame.content

    local configDragAlphaFrames = setmetatable({}, { __mode = "k" })
    local configDragAlphaBeforeMove = setmetatable({}, { __mode = "k" })
    local configDragAlphaHandles = setmetatable({}, { __mode = "k" })
    local configDragAlphaActive = false
    local SetMainConfigDragAlpha

    local function SetConfigDragAlphaFrame(targetFrame, active)
        if not (targetFrame and targetFrame.SetAlpha) then
            return
        end

        if active then
            if configDragAlphaBeforeMove[targetFrame] == nil then
                configDragAlphaBeforeMove[targetFrame] = targetFrame.GetAlpha and targetFrame:GetAlpha() or 1
            end
            targetFrame:SetAlpha(math.min(configDragAlphaBeforeMove[targetFrame] or 1, CONFIG_DRAG_ALPHA))
        elseif configDragAlphaBeforeMove[targetFrame] ~= nil then
            targetFrame:SetAlpha(configDragAlphaBeforeMove[targetFrame])
            configDragAlphaBeforeMove[targetFrame] = nil
        end
    end

    local function GetConfigDragAlphaHandle(targetFrame)
        return targetFrame and targetFrame.obj and targetFrame.obj.title
    end

    local function HookConfigDragAlphaHandle(handle)
        if not (handle and handle.HookScript) or handle._cdcConfigDragAlphaHooked then
            return
        end

        handle._cdcConfigDragAlphaHooked = true
        handle:HookScript("OnMouseDown", function(self)
            if configDragAlphaHandles[self] and SetMainConfigDragAlpha then
                SetMainConfigDragAlpha(true)
            end
        end)
        handle:HookScript("OnMouseUp", function(self)
            if configDragAlphaHandles[self] and SetMainConfigDragAlpha then
                SetMainConfigDragAlpha(false)
            end
        end)
    end

    CS.RegisterConfigDragAlphaFrame = function(targetFrame)
        if not targetFrame then
            return
        end

        configDragAlphaFrames[targetFrame] = true
        local dragHandle = GetConfigDragAlphaHandle(targetFrame)
        if dragHandle then
            configDragAlphaHandles[dragHandle] = true
            HookConfigDragAlphaHandle(dragHandle)
        end
        if configDragAlphaActive then
            SetConfigDragAlphaFrame(targetFrame, true)
        end
    end

    CS.UnregisterConfigDragAlphaFrame = function(targetFrame)
        if not targetFrame then
            return
        end

        local dragHandle = GetConfigDragAlphaHandle(targetFrame)
        if dragHandle then
            configDragAlphaHandles[dragHandle] = nil
        end
        if configDragAlphaActive then
            SetMainConfigDragAlpha(false)
        else
            SetConfigDragAlphaFrame(targetFrame, false)
        end
        configDragAlphaFrames[targetFrame] = nil
    end

    SetMainConfigDragAlpha = function(active)
        if active then
            configDragAlphaActive = true
            SetConfigDragAlphaFrame(content, true)
            for targetFrame in pairs(configDragAlphaFrames) do
                SetConfigDragAlphaFrame(targetFrame, true)
            end
        else
            configDragAlphaActive = false
            SetConfigDragAlphaFrame(content, false)
            for targetFrame in pairs(configDragAlphaFrames) do
                SetConfigDragAlphaFrame(targetFrame, false)
            end
        end
    end

    local titleMover = frame.titletext and frame.titletext:GetParent()
    if titleMover then
        configDragAlphaHandles[titleMover] = true
        HookConfigDragAlphaHandle(titleMover)
        -- AceGUI's own OnMouseUp has already run StopMovingOrSizing by the
        -- time hooks fire, so the read here sees the settled position.
        titleMover:HookScript("OnMouseUp", function()
            SaveConfigWindowGeometry(content)
        end)
    end

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
    local fullHeight = content:GetHeight()
    local fullWidth = content:GetWidth()

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
        SaveConfigWindowGeometry(content)
    end)
    -- Double-click the grip: return to the default size (clamped to the
    -- current screen), keeping the top-left corner planted since the grip
    -- resizes from the bottom-right.
    resizeGrip:SetScript("OnDoubleClick", function()
        content:StopMovingOrSizing()
        local screenWidth = UIParent:GetWidth()
        local screenHeight = UIParent:GetHeight()
        local width = math.max(CONFIG_WINDOW_MIN_WIDTH,
            math.min(CONFIG_WINDOW_DEFAULT_WIDTH, screenWidth * 0.95))
        local height = math.max(CONFIG_WINDOW_MIN_HEIGHT,
            math.min(CONFIG_WINDOW_DEFAULT_HEIGHT, screenHeight * 0.9))
        local left, top = content:GetLeft(), content:GetTop()
        if left and top then
            -- Reclamp the kept corner against the restored size, so a config
            -- parked near the right or bottom edge cannot grow off-screen.
            left = math.max(0, math.min(left, screenWidth - width))
            top = math.min(screenHeight, math.max(top, height))
            content:ClearAllPoints()
            content:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        frame:SetWidth(width)
        frame:SetHeight(height)
        fullWidth = width
        fullHeight = height
        SaveConfigWindowGeometry(content)
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
        SetMainConfigDragAlpha(false)
        if CancelFirstIconPanelTutorial then
            CancelFirstIconPanelTutorial(isCollapsing and "config_collapsed" or "config_hidden")
        end
        -- The text Format tab commits typing on a debounce, so a close mid-word
        -- has a write still pending. Flush before the collapse guard: collapsing
        -- keeps the tab built, so its editor must stay alive, but the pending
        -- write is settled either way.
        if ST._FlushTextFormatTabCommit then
            ST._FlushTextFormatTabCommit()
        end
        if isCollapsing then return end
        -- Truly closing: the next open runs RefreshConfigPanel, which rebuilds
        -- the tab and its editor, so drop this one's animation driver and any
        -- confirmation it left standing.
        if ST._ReleaseTextFormatTabEditor then
            ST._ReleaseTextFormatTabEditor()
        end
        if frame.HideChangelogOverlay then
            frame.HideChangelogOverlay()
        end
        CloseProfileWideFontWindow()
        CloseProfileWideBarTextureWindow()
        -- If talent picker is open when panel closes, clean up its raw frames
        -- (RefreshConfigPanel inside CloseTalentPicker is guarded by IsShown, so it's safe)
        if CS.talentPickerMode then
            CooldownCompanion:CloseTalentPicker()
        end
        if CS.CancelPickAuraTexture then
            CS.CancelPickAuraTexture()
        end
        if ST._CloseConfigIconPicker then
            ST._CloseConfigIconPicker()
        end
        if CS.CloseAdvancedSettingsPanel then
            CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
        end
        if CS.CloseSpellbookPanel then
            CS.CloseSpellbookPanel()
        end
        ClearTransientConfigPreviewState()
        -- Release the panel-preview mirror: stops its conditional ticker
        -- while the config is closed.
        if ST._HideButtonsPanelPreviewSurfaces and CS.configFrame and CS.configFrame.col3 then
            ST._HideButtonsPanelPreviewSurfaces(CS.configFrame.col3)
        end
        if ST._HideResourcesWideSurfaces and CS.configFrame and CS.configFrame.col3 then
            ST._HideResourcesWideSurfaces(CS.configFrame.col3)
        end
        if ClearConfigShiftTooltipHover then
            ClearConfigShiftTooltipHover()
        end
        CloseDropDownMenus()
        CS.HideAutocomplete()
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
            -- Export mode: Escape cancels the mode instead of the panel
            if CS.exportMode then
                if not InCombatLockdown() then
                    self:SetPropagateKeyboardInput(false)
                end
                if ST._ExitExportMode then
                    ST._ExitExportMode()
                end
                return
            end
            -- Import mode: same deal
            if CS.importMode then
                if not InCombatLockdown() then
                    self:SetPropagateKeyboardInput(false)
                end
                if ST._ExitImportMode then
                    ST._ExitImportMode()
                end
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

    -- Title bar buttons: [Arrange] [Import] [Gear] [Collapse] [X] at top-right

    -- X (close) button — rightmost
    local closeBtn = CreateFrame("Button", nil, content)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, -14)
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetAllPoints()
    closeBtn:SetScript("OnClick", function()
        content:Hide()
    end)
    SkinTitlebarButton(closeBtn, closeIcon, 0.90, 0.30, 0.30)

    -- Collapse button — left of X
    local collapseBtn = CreateFrame("Button", nil, content)
    collapseBtn:SetSize(18, 18)
    collapseBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    local collapseIcon = collapseBtn:CreateTexture(nil, "ARTWORK")
    collapseIcon:SetAtlas("uitools-icon-minus")
    collapseIcon:SetAllPoints()
    SkinTitlebarButton(collapseBtn, collapseIcon)

    -- Import button — left of the Gear button; gold while import mode is active
    local importClusterBtn = CreateFrame("Button", nil, content)
    importClusterBtn:SetSize(18, 18)
    local importClusterIcon = importClusterBtn:CreateTexture(nil, "ARTWORK")
    importClusterIcon:SetAtlas("uitools-icon-collapse-window", false)
    importClusterIcon:SetAllPoints()
    local function UpdateImportModeTitleButton()
        if importClusterBtn._cdcTitlebarHovered then return end
        if CS.importMode then
            importClusterIcon:SetVertexColor(1, 0.82, 0, 1)
        else
            importClusterIcon:SetVertexColor(TITLEBAR_ICON_R, TITLEBAR_ICON_G, TITLEBAR_ICON_B, 1)
        end
    end
    ST._UpdateImportModeTitleButton = UpdateImportModeTitleButton
    importClusterBtn:SetScript("OnClick", function()
        if ST._ToggleImportMode then
            ST._ToggleImportMode()
        end
    end)
    importClusterBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Import")
        if CS.importMode then
            GameTooltip:AddLine("Leave import mode.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Paste any export string to review and import it.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    importClusterBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    SkinTitlebarButton(importClusterBtn, importClusterIcon)
    -- Installed after the skin's own OnLeave tint hook so the active-gold
    -- state survives hover round trips.
    importClusterBtn:HookScript("OnLeave", UpdateImportModeTitleButton)
    UpdateImportModeTitleButton()

    -- Export button — left of Import; gold while export mode is active
    local exportClusterBtn = CreateFrame("Button", nil, content)
    exportClusterBtn:SetSize(18, 18)
    exportClusterBtn:SetPoint("RIGHT", importClusterBtn, "LEFT", -6, 0)
    local exportClusterIcon = exportClusterBtn:CreateTexture(nil, "ARTWORK")
    exportClusterIcon:SetAtlas("uitools-icon-external-window", false)
    exportClusterIcon:SetAllPoints()
    local function UpdateExportModeTitleButton()
        if exportClusterBtn._cdcTitlebarHovered then return end
        if CS.exportMode then
            exportClusterIcon:SetVertexColor(1, 0.82, 0, 1)
        else
            exportClusterIcon:SetVertexColor(TITLEBAR_ICON_R, TITLEBAR_ICON_G, TITLEBAR_ICON_B, 1)
        end
    end
    ST._UpdateExportModeTitleButton = UpdateExportModeTitleButton
    exportClusterBtn:SetScript("OnClick", function()
        if ST._ToggleExportMode then
            ST._ToggleExportMode()
        end
    end)
    exportClusterBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Export")
        if CS.exportMode then
            GameTooltip:AddLine("Leave export mode.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Pick groups, panels, Resources, and Custom Bars to share as one string.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    exportClusterBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    SkinTitlebarButton(exportClusterBtn, exportClusterIcon)
    -- Installed after the skin's own OnLeave tint hook so the active-gold
    -- state survives hover round trips.
    exportClusterBtn:HookScript("OnLeave", UpdateExportModeTitleButton)
    UpdateExportModeTitleButton()

    local changelogOverlay

    -- Gear button — left of Collapse
    local gearBtn = CreateFrame("Button", nil, content)
    gearBtn:SetSize(18, 18)
    gearBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -6, 0)
    importClusterBtn:SetPoint("RIGHT", gearBtn, "LEFT", -6, 0)
    local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
    gearIcon:SetAtlas("uitools-icon-settings", false)
    gearIcon:SetAllPoints()
    SkinTitlebarButton(gearBtn, gearIcon)
    -- Fire on mouse down so a second gear click closes the open dropdown instead of reopening it on mouse up.
    gearBtn:RegisterForClicks("LeftButtonDown")
    CS.gearButton = gearBtn

    -- Gear dropdown menu. Open/closed state comes from ToggleDropDownMenu's
    -- return value plus the menu frame's onHide (re-armed on every open) —
    -- never from sniffing _G.DropDownList1, which runs in the dropdown
    -- code's own environment on 12.1 and never matches the live list (the
    -- PreviewCommandCenter chooser uses this same pattern).
    gearBtn:SetScript("OnClick", function()
        -- Our click reached OnClick with the list still up: this click is
        -- the close. (Covers the ordering where frame scripts run before
        -- the global mouse-down handler.)
        if CS.gearDropdownOpen then
            CloseDropDownMenus()
            return
        end
        -- The list already hid this same frame — the global mouse-down
        -- handler closed it because our click landed outside the list.
        -- That click was the close; consume it instead of reopening.
        -- GetTime() is frame-constant, so equality means "this click".
        if CS.gearDropdownClosedAt == GetTime() then
            return
        end

        if not CS.gearDropdownFrame then
            CS.gearDropdownFrame = CreateFrame("Frame", "CDCGearDropdown", UIParent, "UIDropDownMenuTemplate")
            CS.gearDropdownFrame.onHide = function()
                CS.gearDropdownOpen = nil
                CS.gearDropdownClosedAt = GetTime()
            end
        end
        UIDropDownMenu_Initialize(CS.gearDropdownFrame, function(self, level)
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
            info3.text = "  Profile One-pixel Borders"
            info3.checked = function() return ST.IsProfileOnePixelBordersEnabled() end
            info3.isNotRadio = true
            info3.keepShownOnClick = true
            info3.tooltipTitle = "Profile One-pixel Borders"
            info3.tooltipText = "Use one-pixel borders for this profile's panels, resource bars, and cast bars. Border size controls for those borders are disabled while this is on."
            info3.tooltipOnButton = true
            info3.func = function()
                CooldownCompanion:SetProfileOnePixelBordersEnabled(not ST.IsProfileOnePixelBordersEnabled())
            end
            UIDropDownMenu_AddButton(info3, level)

            local infoFont = UIDropDownMenu_CreateInfo()
            infoFont.text = "  Profile Font"
            infoFont.checked = function() return ST.IsProfileWideFontEnabled and ST.IsProfileWideFontEnabled() end
            infoFont.isNotRadio = true
            infoFont.keepShownOnClick = true
            infoFont.tooltipTitle = "Profile Font"
            infoFont.tooltipText = "Use one font face and outline for this profile's configurable text."
            infoFont.tooltipOnButton = true
            infoFont.func = function()
                local enabling = not (ST.IsProfileWideFontEnabled and ST.IsProfileWideFontEnabled())
                if CooldownCompanion:SetProfileWideFontEnabled(enabling) then
                    CloseDropDownMenus()
                    if enabling then
                        OpenProfileWideFontWindow()
                    else
                        CloseProfileWideFontWindow()
                    end
                end
            end
            UIDropDownMenu_AddButton(infoFont, level)

            if ST.IsProfileWideFontEnabled and ST.IsProfileWideFontEnabled() then
                local infoFontPicker = UIDropDownMenu_CreateInfo()
                infoFontPicker.text = "  Pick Font"
                infoFontPicker.notCheckable = true
                infoFontPicker.func = function()
                    CloseDropDownMenus()
                    OpenProfileWideFontWindow()
                end
                UIDropDownMenu_AddButton(infoFontPicker, level)
            end

            local infoBarTexture = UIDropDownMenu_CreateInfo()
            infoBarTexture.text = "  Profile Bar Texture"
            infoBarTexture.checked = function() return ST.IsProfileWideBarTextureEnabled and ST.IsProfileWideBarTextureEnabled() end
            infoBarTexture.isNotRadio = true
            infoBarTexture.keepShownOnClick = true
            infoBarTexture.tooltipTitle = "Profile Bar Texture"
            infoBarTexture.tooltipText = "Use one texture for this profile's main bar fills."
            infoBarTexture.tooltipOnButton = true
            infoBarTexture.func = function()
                local enabling = not (ST.IsProfileWideBarTextureEnabled and ST.IsProfileWideBarTextureEnabled())
                if CooldownCompanion:SetProfileWideBarTextureEnabled(enabling) then
                    CloseDropDownMenus()
                    if enabling then
                        OpenProfileWideBarTextureWindow()
                    else
                        CloseProfileWideBarTextureWindow()
                    end
                end
            end
            UIDropDownMenu_AddButton(infoBarTexture, level)

            if ST.IsProfileWideBarTextureEnabled and ST.IsProfileWideBarTextureEnabled() then
                local infoBarTexturePicker = UIDropDownMenu_CreateInfo()
                infoBarTexturePicker.text = "  Pick Texture"
                infoBarTexturePicker.notCheckable = true
                infoBarTexturePicker.func = function()
                    CloseDropDownMenus()
                    OpenProfileWideBarTextureWindow()
                end
                UIDropDownMenu_AddButton(infoBarTexturePicker, level)
            end

            local info4 = UIDropDownMenu_CreateInfo()
            info4.text = "  Generate Bug Report"
            info4.notCheckable = true
            info4.tooltipTitle = "Generate Bug Report"
            info4.tooltipText = "Creates a support report with current runtime details and a compact profile export. If possible, select the broken group, panel, or entry before generating it."
            info4.tooltipOnButton = true
            info4.func = function()
                CloseDropDownMenus()
                ShowPopupAboveConfig("CDC_DIAGNOSTIC_BUG_REPORT")
            end
            UIDropDownMenu_AddButton(info4, level)

            local infoChangelog = UIDropDownMenu_CreateInfo()
            infoChangelog.text = "  View Changelog"
            infoChangelog.notCheckable = true
            infoChangelog.tooltipTitle = "View Changelog"
            infoChangelog.tooltipText = "Open the bundled release notes for the latest and older versions."
            infoChangelog.tooltipOnButton = true
            infoChangelog.func = function()
                CloseDropDownMenus()
                if frame.ToggleChangelogOverlay then
                    frame.ToggleChangelogOverlay()
                end
            end
            UIDropDownMenu_AddButton(infoChangelog, level)

            local info6 = UIDropDownMenu_CreateInfo()
            info6.text = "  Replay Tutorial"
            info6.notCheckable = true
            info6.func = function()
                CloseDropDownMenus()
                if StartFirstIconPanelTutorial then
                    StartFirstIconPanelTutorial(true)
                end
            end
            UIDropDownMenu_AddButton(info6, level)

            local info7 = UIDropDownMenu_CreateInfo()
            info7.text = "  Join Discord"
            info7.notCheckable = true
            info7.func = function()
                CloseDropDownMenus()
                ShowPopupAboveConfig("CDC_DISCORD_INVITE")
            end
            UIDropDownMenu_AddButton(info7, level)
        end, "MENU")
        CS.gearDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        -- Returns true when it opened the list, false when it toggled it
        -- closed or refused (empty menu).
        local opened = ToggleDropDownMenu(1, nil, CS.gearDropdownFrame, gearBtn, 0, 0)
        CS.gearDropdownOpen = opened and true or nil
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
        if CS.CloseAdvancedSettingsPanel then
            CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
        end
        if CS.CloseSpellbookPanel then
            CS.CloseSpellbookPanel()
        end
        miniWasDragged = false
        isMinimized = false
        frame._collapsedForUnlock = nil
        collapseIcon:SetAtlas("uitools-icon-minus")
        collapseBtn:SetParent(content)
        collapseBtn:ClearAllPoints()
        collapseBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    end)

    local function CloseMinimizedConfig()
        GameTooltip:Hide()
        if frame.HideChangelogOverlay then
            frame.HideChangelogOverlay()
        end
        ClearTransientConfigPreviewState()
        miniFrame:Hide()
    end

    -- ESC handler for mini frame
    miniFrame:EnableKeyboard(true)
    miniFrame:SetScript("OnKeyDown", function(self, key)
        -- While arranging, Escape belongs to the arrange pill: it cancels the
        -- session, which locks everything and re-expands this config. Closing
        -- here would consume the press and leave nothing to expand. Standing
        -- down means the first Escape restores the window and a second one
        -- closes it.
        local arranging = CooldownCompanion.IsArrangeModeActive
            and CooldownCompanion:IsArrangeModeActive()
        if key == "ESCAPE"
            and CooldownCompanion.db.profile.escClosesConfig
            and not arranging then
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(false)
            end
            CloseMinimizedConfig()
        elseif not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
    end)

    frame._miniFrame = miniFrame

    local function CollapseConfigWindow()
        if isMinimized or not content:IsShown() then return end

        CloseDropDownMenus()
        CloseProfileWideFontWindow()
        CloseProfileWideBarTextureWindow()
        if CS.CloseAdvancedSettingsPanel then
            CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
        end
        if CS.CloseSpellbookPanel then
            CS.CloseSpellbookPanel()
        end

        savedFrameRight = content:GetRight()
        savedFrameTop = content:GetTop()

        local btnLeft = collapseBtn:GetLeft()
        local btnBottom = collapseBtn:GetBottom()

        isCollapsing = true
        content:Hide()
        isCollapsing = false
        ClearTransientConfigPreviewState()

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

        collapseIcon:SetAtlas("uitools-icon-plus")
        isMinimized = true
    end

    local function ExpandConfigWindow()
        if not isMinimized then return end
        if InCombatLockdown() then
            CooldownCompanion:RunConfigIntent({
                action = "open",
                entryPoint = "puck expand",
            })
            return
        end

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
        -- A dragged mini frame moves the expanded window too.
        SaveConfigWindowGeometry(content)
        CooldownCompanion:RefreshConfigPanel()
    end

    frame.CollapseConfigWindow = CollapseConfigWindow
    frame.ExpandConfigWindow = ExpandConfigWindow

    collapseBtn:RegisterForClicks("LeftButtonUp")

    -- Collapse button callback
    collapseBtn:SetScript("OnClick", function()
        if not isMinimized then
            CollapseConfigWindow()
            return
        end

        ExpandConfigWindow()
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
    CS.profileBar = profileBar

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

    -- Bundled changelog overlay (kept separate from column refreshes).
    changelogOverlay = SetupChangelogOverlay(frame, colParent)

    -- Navigator rail (AceGUI InlineGroup)
    local col1 = AceGUI:Create("InlineGroup")
    col1:SetTitle("Navigator")
    col1:SetAutoAdjustHeight(false)
    col1:SetLayout(MANUAL_COLUMN_LAYOUT)
    col1.frame:SetParent(colParent)
    col1.frame:Show()

    -- Info button next to the Navigator title
    local groupInfoBtn = CreateFrame("Button", nil, col1.frame)
    groupInfoBtn:SetSize(16, 16)
    groupInfoBtn:SetPoint("LEFT", col1.titletext, "RIGHT", -2, 0)
    local groupInfoIcon = groupInfoBtn:CreateTexture(nil, "OVERLAY")
    groupInfoIcon:SetSize(12, 12)
    groupInfoIcon:SetPoint("CENTER")
    groupInfoIcon:SetAtlas("QuestRepeatableTurnin")
    groupInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if CS.exportMode then
            GameTooltip:AddLine("Export Mode")
            GameTooltip:AddLine("Click rows to choose what the string will contain.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Escape or Cancel leaves without exporting.", 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
        if CS.importMode then
            GameTooltip:AddLine("Import Mode")
            GameTooltip:AddLine("Paste a string on the right to review what it contains.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Escape or Cancel leaves without importing.", 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
        GameTooltip:AddLine("Navigator")
        GameTooltip:AddLine("Groups contain panels; panels contain entries.", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-click for options.", 1, 1, 1)
        GameTooltip:AddLine("Hold left-click and drag to reorder.", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Group Rows", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click to select/deselect.", 1, 1, 1, true)
        GameTooltip:AddLine("Ctrl+Left-click to multi-select.", 1, 1, 1, true)
        GameTooltip:AddLine("Shift+Left-click to open Visibility.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Panel Rows", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click to select; Ctrl+Left-click to multi-select.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    groupInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Arrange toggle in the Navigator header corner
    local arrangeBtn = CreateFrame("Button", nil, col1.frame)
    arrangeBtn:SetSize(16, 16)
    -- Share the info button's baseline: it is centred on the title text, and
    -- both buttons are the same size, so TOP-to-TOP puts them on one line.
    arrangeBtn:SetPoint("TOP", groupInfoBtn, "TOP", 0, 0)
    arrangeBtn:SetPoint("RIGHT", col1.frame, "RIGHT", -10, 0)
    local arrangeIcon = arrangeBtn:CreateTexture(nil, "OVERLAY")
    arrangeIcon:SetSize(16, 16)
    arrangeIcon:SetPoint("CENTER")
    arrangeIcon:SetAtlas("questlog-questtypeicon-lock", false)
    local function UpdateArrangeBadgeTint()
        -- The modes own the Navigator; arranging is parked until they end.
        arrangeBtn:SetShown(not CS.exportMode and not CS.importMode)
        if CooldownCompanion.IsArrangeModeActive and CooldownCompanion:IsArrangeModeActive() then
            arrangeIcon:SetVertexColor(1, 0.82, 0, 0.9)
        else
            arrangeIcon:SetVertexColor(0.8, 0.8, 0.8, 0.8)
        end
    end
    ST.UpdateArrangeBadge = UpdateArrangeBadgeTint
    UpdateArrangeBadgeTint()
    arrangeBtn:SetScript("OnClick", function()
        if CS.exportMode or CS.importMode then return end
        if CooldownCompanion.IsArrangeModeActive and CooldownCompanion:IsArrangeModeActive() then
            CooldownCompanion:ExitArrangeMode()
        else
            CooldownCompanion:EnterArrangeMode()
        end
        UpdateArrangeBadgeTint()
    end)
    arrangeBtn:SetScript("OnEnter", function(self)
        arrangeIcon:SetVertexColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if CooldownCompanion.IsArrangeModeActive and CooldownCompanion:IsArrangeModeActive() then
            GameTooltip:AddLine("Finish arranging")
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Locks everything and saves your changes.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Arrange panels")
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Unlocks everything for moving.", 1, 1, 1, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Typing /cdc lock does the same thing.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    arrangeBtn:SetScript("OnLeave", function()
        UpdateArrangeBadgeTint()
        GameTooltip:Hide()
    end)

    -- Config finder searches saved groups, panels, and entries without
    -- changing the active selection while the user types.
    local configFinder = AceGUI:Create("EditBox")
    configFinder:SetLabel("")
    configFinder:SetText(CS.configSearchText or "")
    configFinder:DisableButton(true)
    configFinder.frame:SetParent(col1.content)
    configFinder.frame:ClearAllPoints()
    configFinder.frame:SetPoint("BOTTOMLEFT", col1.content, "BOTTOMLEFT", 0, 30 + CONFIG_FINDER_BUTTON_GAP)
    configFinder.frame:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 30 + CONFIG_FINDER_BUTTON_GAP)
    configFinder.frame:SetHeight(CONFIG_FINDER_BOX_HEIGHT)
    local configFinderPlaceholder
    if configFinder.editbox then
        configFinderPlaceholder = configFinder.editbox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        configFinderPlaceholder:SetPoint("LEFT", configFinder.editbox, "LEFT", 6, 0)
        configFinderPlaceholder:SetPoint("RIGHT", configFinder.editbox, "RIGHT", -6, 0)
        configFinderPlaceholder:SetJustifyH("LEFT")
        configFinderPlaceholder:SetText("Find groups, panels, entries...")
    end
    local function UpdateConfigFinderPlaceholder(text)
        if not configFinderPlaceholder then return end
        configFinderPlaceholder:SetShown((text or "") == "")
    end
    configFinder._cdcUpdatePlaceholder = UpdateConfigFinderPlaceholder
    UpdateConfigFinderPlaceholder(CS.configSearchText)
    configFinder:SetCallback("OnTextChanged", function(widget, event, text)
        if CS.configFinderSuppressTextChanged then
            UpdateConfigFinderPlaceholder(text)
            return
        end
        local wasFinderActive = IsConfigFinderActive and IsConfigFinderActive()
        if SetConfigFinderText then
            SetConfigFinderText(text or "", { syncWidget = false })
        else
            CS.configSearchText = text or ""
        end
        UpdateConfigFinderPlaceholder(text)
        local isFinderActive = IsConfigFinderActive and IsConfigFinderActive()
        if wasFinderActive or isFinderActive then
            QueueConfigFinderRefresh()
        end
    end)
    configFinder:SetCallback("OnEnterPressed", function(widget)
        widget:ClearFocus()
    end)
    if configFinder.editbox then
        configFinder.editbox:HookScript("OnEditFocusGained", function(self)
            UpdateConfigFinderPlaceholder(self:GetText())
        end)
        configFinder.editbox:HookScript("OnEditFocusLost", function(self)
            UpdateConfigFinderPlaceholder(self:GetText())
        end)
    end
    CS.configFinderBox = configFinder

    -- Workspace: live preview and editing surfaces
    local col3 = AceGUI:Create("InlineGroup")
    col3:SetTitle("Live Preview")
    col3:SetAutoAdjustHeight(false)
    col3:SetLayout(MANUAL_COLUMN_LAYOUT)
    col3.frame:SetParent(colParent)
    col3.frame:Show()

    -- Info button next to the workspace title
    local bsInfoBtn = CreateFrame("Button", nil, col3.frame)
    bsInfoBtn:SetSize(16, 16)
    bsInfoBtn:SetPoint("LEFT", col3.titletext, "RIGHT", -2, 0)
    local bsInfoIcon = bsInfoBtn:CreateTexture(nil, "OVERLAY")
    bsInfoIcon:SetSize(12, 12)
    bsInfoIcon:SetPoint("CENTER")
    bsInfoIcon:SetAtlas("QuestRepeatableTurnin")
    bsInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if CS.barsEntrySelected and ST._IsBarsOverviewActive and ST._IsBarsOverviewActive() then
            GameTooltip:AddLine("Resources, Cast Bar & Unit Frames")
            GameTooltip:AddLine("Resource Bars, the cast bar, and unit frame anchoring are all disabled. Enable any of them to start building this workspace.", 1, 1, 1, true)
        elseif CS.barsEntrySelected and CS.castFramesSelectedItem == "castbar" then
            GameTooltip:AddLine("Cast Bar")
            GameTooltip:AddLine("Draws your cast bar in your chosen style, anchored to a panel or positioned anywhere on screen.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("These settings are saved per character.", 1, 1, 1, true)
        elseif CS.barsEntrySelected and CS.castFramesSelectedItem then
            GameTooltip:AddLine("Unit Frames")
            GameTooltip:AddLine("Anchors your player and target unit frames to your panels.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("These settings are saved per character.", 1, 1, 1, true)
        elseif CS.barsEntrySelected and not CS.selectedResourcePowerType and not CS.selectedCustomBarId then
            GameTooltip:AddLine("Resource Bars")
            GameTooltip:AddLine("Shared resource bar settings, organized into tabs.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Layout is saved per specialization.", 1, 1, 1, true)
        elseif CS.barsEntrySelected then
            GameTooltip:AddLine("Layout & Order")
            GameTooltip:AddLine("Arrange attached bars by dragging them around the mirrored icon panel.", 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Only applies when resource anchoring uses panel anchoring.", 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Layout is saved per specialization and swaps automatically.", 1, 1, 1)
        else
            local selection = GetConfigSelectionSummary()
            local mode = GetColumn3HeaderMode(selection)
            if mode == "group_actions" then
                GameTooltip:AddLine("Group Actions")
                GameTooltip:AddLine("Select multiple groups to batch-manage them here.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Select a single group to configure it here instead.", 1, 1, 1, true)
            elseif mode == "panel_actions" then
                GameTooltip:AddLine("Panel Actions")
                GameTooltip:AddLine("Select multiple panels to batch-manage them here.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Select a single panel to configure it here instead.", 1, 1, 1, true)
            else
                GameTooltip:AddLine("Settings")
                GameTooltip:AddLine("Settings for the selected group, panel, or entry, with a live preview of the panel above them.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Panel settings apply to every button in the panel. Selecting a button shows that entry's own settings; deselect it to return to the panel settings.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("With a button selected, each section shows whose settings you are looking at.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Use Customize on a section to give that button its own settings there. Revert hands them back to the panel.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("The Customizations section in the Settings tab lists everything that button customizes, each with its own Revert.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("The Visibility tab shows the selected button's conditions. Deselect to see the panel's own.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Drag the line under the preview to resize it. Double-click to reset.", 1, 1, 1, true)
            end
        end
        GameTooltip:Show()
    end)
    bsInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Store column header (?) buttons for lifecycle cleanup.
    wipe(CS.columnInfoButtons)
    CS.columnInfoButtons[1] = groupInfoBtn
    CS.columnInfoButtons[2] = bsInfoBtn

    -- Static Create/browse button bar at the bottom of the Navigator.
    local btnBar = CreateFrame("Frame", nil, col1.content)
    btnBar:SetPoint("BOTTOMLEFT", col1.content, "BOTTOMLEFT", 0, 0)
    btnBar:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 0)
    btnBar:SetHeight(30)
    CS.col1ButtonBar = btnBar

    -- Fixed destinations sit between the scrolling Group -> Panel tree and
    -- the finder/Create controls. Column1 paints the two compact rows here.
    local destinationBar = CreateFrame("Frame", nil, col1.content)
    destinationBar:SetPoint("BOTTOMLEFT", col1.content, "BOTTOMLEFT", 0, 30 + CONFIG_FINDER_RESERVED_HEIGHT)
    destinationBar:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 30 + CONFIG_FINDER_RESERVED_HEIGHT)
    destinationBar:SetHeight(GetNavigatorDestinationsHeight())
    destinationBar:Show()
    CS.col1DestinationBar = destinationBar

    -- Navigator scroll
    local scroll1 = AceGUI:Create("ScrollFrame")
    scroll1:SetLayout("List")
    scroll1.frame:SetParent(col1.content)
    scroll1.frame:ClearAllPoints()
    scroll1.frame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, 0)
    scroll1.frame:SetPoint(
        "BOTTOMRIGHT",
        col1.content,
        "BOTTOMRIGHT",
        0,
        30 + CONFIG_FINDER_RESERVED_HEIGHT + GetNavigatorDestinationsHeight()
    )
    scroll1.frame:Show()
    CS.col1Scroll = scroll1

    -- Button Settings TabGroup. The tab list is refreshed later from the
    -- selected entry: one Settings tab (labelled "Condition" on trigger
    -- panels), or the single appended multi-select tab.
    local bsTabGroup = AceGUI:Create("TabGroup")
    bsTabGroup:SetTabs({
        { value = "settings", text = "Settings" },
    })
    bsTabGroup:SetLayout("Fill")

    bsTabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
        -- The config's one text-format editor is settled here, before anything
        -- else: it lives on the panel Format tab, and selecting an entry tab
        -- hands the settings surface away from it. Release is idempotent, so
        -- the panel-side seams releasing again costs nothing.
        if ST._ReleaseTextFormatTabEditor then
            ST._ReleaseTextFormatTabEditor()
        end
        local previousTab = col3._activeButtonSettingsTab
        local tabChanged = previousTab ~= nil and previousTab ~= tab
        -- Selecting an entry tab hands the settings surface back to entry
        -- scope; the panel tabs stay in the row, just unselected.
        local scopeChanged = ST._UnifiedRowGetScope() ~= "detail"
        ST._UnifiedRowSetScope("detail")
        col3._activeButtonSettingsTab = tab
        if tab ~= "multiselect" then
            CS.buttonSettingsTab = tab
        end
        -- Clean up info/collapse buttons before releasing
        for _, btn in ipairs(CS.buttonSettingsInfoButtons) do
            btn:ClearAllPoints()
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(CS.buttonSettingsInfoButtons)

        if tabChanged or scopeChanged then
            CooldownCompanion:ClearAllConfigPreviews()
        end
        widget:ReleaseChildren()

        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        widget:AddChild(scroll)
        buttonSettingsScroll = scroll
        CS.buttonSettingsScroll = scroll

        local function BuildEntryTabContent()
            local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
            if not group then return end

            -- Entry multi-select joins the row as a single appended tab
            -- rather than taking the whole surface over.
            if tab == "multiselect" then
                ST._BuildEntryMultiSelectTab(scroll)
                return
            end

            -- The rotation assistant entry has no entry tabs at all: its one
            -- surface is Visibility, which the panel-side tab now builds for
            -- whichever entry is selected. Nothing to build here.

            local buttonData = CS.selectedButton and group.buttons[CS.selectedButton]
            if not buttonData then return end

            -- One identity line at the top of the entry pane, emitted here
            -- rather than inside the builders so it appears exactly once
            -- whatever they go on to add. Multi-select returned above: it
            -- heads its own "<n> Selected".
            if tab == "settings" then
                ST._BuildEntryIdentityHeading(scroll, buttonData)

                -- Customizations leads the tab (owner ruling): it is the
                -- entry's index of what it changes, it builds nothing until
                -- something is customized, and when it exists it is likely
                -- why the entry was selected.
                ST._BuildCustomizationsSection(scroll, group, buttonData, CS.buttonSettingsInfoButtons)

                if group.displayMode == "trigger" then
                    ST._BuildTriggerConditionSettings(scroll, buttonData, CS.buttonSettingsInfoButtons)
                    -- Trigger panels have no Talent Conditions section.
                    ST._BuildEntrySoundAlertsSection(scroll, group, buttonData, CS.buttonSettingsInfoButtons)
                else
                    if buttonData.type == "item" and not CooldownCompanion.IsItemEquippable(buttonData) then
                        ST._BuildItemSettings(scroll, buttonData, CS.buttonSettingsInfoButtons)
                    elseif buttonData.type == "item" and CooldownCompanion.IsItemEquippable(buttonData) then
                        ST._BuildEquipItemSettings(scroll, buttonData, CS.buttonSettingsInfoButtons)
                    end
                    -- Talent Conditions is always the last section (owner ruling),
                    -- so everything below Show Conditions is emitted through the
                    -- visibility builder's mid-point hook rather than after it.
                    ST._BuildVisibilitySettings(scroll, buttonData, CS.buttonSettingsInfoButtons, nil, function()
                        -- Aura Tracking leads the hook, so it lands directly
                        -- under Show Conditions (owner ruling): the aura
                        -- toggles up there configure behavior that depends on
                        -- the setup made here. Gated exactly as the retired
                        -- Aura tab was, so entries that never offered it still
                        -- get nothing.
                        if ST._EntryOffersAuraTab(group, buttonData) then
                            ST._BuildAuraTrackingSection(scroll, group, buttonData, CS.buttonSettingsInfoButtons)
                        end
                        ST._BuildCustomKeybindSection(scroll, buttonData)
                        ST._BuildCustomNameSection(scroll, buttonData)
                        ST._BuildItemFallbacksSection(scroll, buttonData, CS.buttonSettingsInfoButtons)
                        ST._BuildEntrySoundAlertsSection(scroll, group, buttonData, CS.buttonSettingsInfoButtons)
                    end)
                end
            end
        end

        BuildEntryTabContent()

        -- Re-run the layout with final widths (AddChild lays out on every
        -- insertion; width overrides applied after a builder returns are
        -- invisible until the next layout).
        scroll:DoLayout()

    end)

    bsTabGroup.frame:SetParent(col3.content)
    bsTabGroup.frame:ClearAllPoints()
    bsTabGroup.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
    bsTabGroup.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
    bsTabGroup.frame:Hide()

    -- Entry tabs are one of the right-hand clusters of the unified tab row:
    -- offset past the panel tabs and laid out against the space they leave.
    ST._UnifiedRowInstallStrip(bsTabGroup, "detail")

    col3.bsTabGroup = bsTabGroup

    -- Placeholder label shown when no button is selected
    local bsPlaceholderLabel = col3.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bsPlaceholderLabel:SetPoint("TOPLEFT", col3.content, "TOPLEFT", -1, 0)
    bsPlaceholderLabel:SetText("Select an entry to configure")
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
            self:Hide()
            return
        end

        for _, entry in ipairs(targets) do
            if entry.frame:IsMouseOver() then
                entry.overlay:SetAlpha(entry.showHighlight and 1 or 0.01)
                entry.overlay:Show()
            else
                entry.overlay:SetAlpha(1)
                entry.overlay:Hide()
            end
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
    end

    local function UpdatePanelDropScan()
        local cursorType = GetCursorInfo()
        local targets = CS._panelDropTargets
        if IsCursorDropPayload(cursorType)
            and targets and #targets > 0
            and col1.frame:IsShown()
            and not (IsConfigFinderActive and IsConfigFinderActive())
            and not CS.otherClassLibraryActive then
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

    local function PositionPrimaryAxisUI()
        if frame.titlebg then
            frame.titlebg:ClearAllPoints()
            frame.titlebg:SetPoint("TOP", content, "TOP", 0, 12)
        end
    end
    CS._UpdatePanelDropScan = UpdatePanelDropScan

    local function GetScrollRowWidth(scrollWidget, fallbackFrame)
        local contentWidth = scrollWidget and scrollWidget.content and scrollWidget.content.width
        if contentWidth and contentWidth > 0 then
            return contentWidth
        end

        local scrollFrame = scrollWidget and scrollWidget.scrollframe
        local width = (scrollFrame and scrollFrame:GetWidth()) or (fallbackFrame and fallbackFrame:GetWidth()) or 0
        return math.max(0, width or 0)
    end

    local function UpdateCompactConfigRows()
        local col1RowWidth = GetScrollRowWidth(CS.col1Scroll, col1.content)
        if col1RowWidth <= 0 then
            return
        end

        local compact = col1RowWidth < CONFIG_COMPACT_ROW_MIN_WIDTH
        if CS.compactConfigRows ~= compact then
            CS.compactConfigRows = compact
            if RefreshVisibleConfigCompactRows then
                RefreshVisibleConfigCompactRows()
            end
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

        -- Talent picker mode: two equally wide surfaces.
        if CS.talentPickerMode then
            if CS.configFinderBox then
                CS.configFinderBox.frame:Hide()
            end
            if CS.col1DestinationBar then
                CS.col1DestinationBar:Hide()
            end
            if ClearConfigFinderText then
                ClearConfigFinderText()
            end
            local wideColWidth = equalColWidth * 2 + pad
            local usedWidth = (wideColWidth * 2) + pad
            local leftoverWidth = math.max(0, w - usedWidth)

            col1.frame:ClearAllPoints()
            col1.frame:SetPoint("TOPLEFT", colParent, "TOPLEFT", 0, 0)
            col1.frame:SetSize(wideColWidth, h)

            col3.frame:ClearAllPoints()
            col3.frame:SetPoint("TOPLEFT", col1.frame, "TOPRIGHT", pad, 0)
            col3.frame:SetSize(wideColWidth + leftoverWidth, h)
            return
        end

        -- Final cutover layout: one fixed Navigator rail and one workspace.
        local col1Width = math.min(NAVIGATOR_WIDTH, math.max(260, w - 600 - pad))
        local col3Width = math.max(1, w - col1Width - pad)
        local finderAvailable = IsConfigFinderAvailable and IsConfigFinderAvailable()
            and not CS.exportMode and not CS.importMode
        local destinationBottomInset = finderAvailable and (30 + CONFIG_FINDER_RESERVED_HEIGHT) or 30
        local showDestinations = not CooldownCompanion._unsupportedLegacyProfile
            and not CS.exportMode and not CS.importMode

        if CS.col1DestinationBar then
            CS.col1DestinationBar:ClearAllPoints()
            CS.col1DestinationBar:SetPoint("BOTTOMLEFT", col1.content, "BOTTOMLEFT", 0, destinationBottomInset)
            CS.col1DestinationBar:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, destinationBottomInset)
            CS.col1DestinationBar:SetHeight(GetNavigatorDestinationsHeight())
            CS.col1DestinationBar:SetShown(showDestinations)
        end

        if CS.configFinderBox then
            if finderAvailable then
                CS.configFinderBox.frame:ClearAllPoints()
                CS.configFinderBox.frame:SetPoint("BOTTOMLEFT", col1.content, "BOTTOMLEFT", 0, 30 + CONFIG_FINDER_BUTTON_GAP)
                CS.configFinderBox.frame:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 30 + CONFIG_FINDER_BUTTON_GAP)
                CS.configFinderBox.frame:SetHeight(CONFIG_FINDER_BOX_HEIGHT)
                CS.configFinderBox.frame:Show()
            else
                CS.configFinderBox.frame:Hide()
                if ClearConfigFinderText then
                    ClearConfigFinderText()
                end
            end
        end
        if CS.col1Scroll and CS.col1Scroll.frame then
            local bottomInset = destinationBottomInset
                + (showDestinations and GetNavigatorDestinationsHeight() or 0)
            CS.col1Scroll.frame:ClearAllPoints()
            CS.col1Scroll.frame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, 0)
            CS.col1Scroll.frame:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, bottomInset)
        end

        col1.frame:ClearAllPoints()
        col1.frame:SetPoint("TOPLEFT", colParent, "TOPLEFT", 0, 0)
        col1.frame:SetSize(col1Width, h)

        col3.frame:ClearAllPoints()
        col3.frame:SetPoint("TOPLEFT", col1.frame, "TOPRIGHT", pad, 0)
        col3.frame:SetSize(col3Width, h)

        UpdateCompactConfigRows()
        PositionPrimaryAxisUI()

        -- Window resizes change the column height the persisted preview
        -- split is applied against; recompute and re-clamp the preview.
        if ST._ReapplyPanelPreviewSplit then
            ST._ReapplyPanelPreviewSplit()
        end
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
    frame.profileGear = profileGear
    frame.changelogOverlay = changelogOverlay
    frame.col1 = col1
    frame.col3 = col3
    frame.colParent = colParent
    frame.LayoutColumns = LayoutColumns
    frame.UpdateCompactConfigRows = UpdateCompactConfigRows

    CS.configFrame = frame
    return frame
end

function ST.CollapseConfigForUnlock()
    local frame = CS.configFrame
    if not (frame and frame.frame and frame.frame:IsShown()) then return end
    if frame._miniFrame and frame._miniFrame:IsShown() then return end
    if frame.CollapseConfigWindow then
        frame.CollapseConfigWindow()
        if frame._miniFrame and frame._miniFrame:IsShown() then
            frame._collapsedForUnlock = true
        end
    end
end

function ST.ExpandConfigAfterLock()
    local frame = CS.configFrame
    if not frame then return end
    if not frame._collapsedForUnlock then return end
    if not (frame._miniFrame and frame._miniFrame:IsShown()) then return end
    if frame.ExpandConfigWindow then
        frame.ExpandConfigWindow()
    end
end

------------------------------------------------------------------------
-- Refresh only the editing workspace after an in-preview selection change.
-- The Navigator's structure and selected panel do not change, so rebuilding
-- it here is both unnecessary and the largest remaining source of click work.
------------------------------------------------------------------------
function CooldownCompanion:RefreshConfigSelection()
    if not (CS.configFrame and CS.configFrame.frame:IsShown()) then return end
    if CS.talentPickerMode then return end
    if CS.configRefreshInProgress or CS.advancedSettingsPanelRefreshing then return end

    CS.configRefreshInProgress = true
    local savedButtonSettings = SaveScrollState(buttonSettingsScroll)
    if ClearConfigShiftTooltipHover then
        ClearConfigShiftTooltipHover()
    end
    RefreshColumn3(true)
    ApplyConfigColumnTitles(CS.configFrame)
    RestoreScrollState(buttonSettingsScroll, savedButtonSettings)
    CS.configRefreshInProgress = false

    if CS.RefreshAdvancedSettingsPanel then
        CS.RefreshAdvancedSettingsPanel()
    end
    if RebuildTutorialAnchors then
        RebuildTutorialAnchors()
    end
    if RefreshTutorialPlacement then
        RefreshTutorialPlacement()
    end
    if ST.UpdateArrangeBadge then
        ST.UpdateArrangeBadge()
    end
end

------------------------------------------------------------------------
-- Refresh entire panel
------------------------------------------------------------------------
function CooldownCompanion:_configRefreshPanelImpl()
    if not CS.configFrame then return end
    if not CS.configFrame.frame:IsShown() then return end
    if CS.talentPickerMode then return end
    if CS.configRefreshInProgress or CS.advancedSettingsPanelRefreshing then return end
    CS.configRefreshInProgress = true

    -- Texture panels only ever hold one entry, so the config never asks the
    -- user to select it: as long as the entry exists it stays selected, and
    -- every selection path that could drop it self-heals here on refresh.
    local healGroup = CS.selectedGroup and self.db.profile.groups[CS.selectedGroup]
    if healGroup and not CS.selectedButton
        and self.IsTexturePanelGroup and self:IsTexturePanelGroup(healGroup)
        and healGroup.buttons and healGroup.buttons[1] then
        wipe(CS.selectedButtons)
        CS.selectedButton = 1
    end

    if IsConfigFinderAvailable and not IsConfigFinderAvailable() and ClearConfigFinderText then
        ClearConfigFinderText()
    elseif SetConfigFinderText then
        SetConfigFinderText(CS.configSearchText or "")
    end
    if InvalidateConfigFinderResults then
        InvalidateConfigFinderResults()
    end
    if ClearConfigShiftTooltipHover then
        ClearConfigShiftTooltipHover()
    end

    -- Save the Navigator and entry-settings scroll state before rebuilding.
    local saved1   = SaveScrollState(CS.col1Scroll)
    local savedBtn = SaveScrollState(buttonSettingsScroll)

    if CS.configFrame.profileBar:IsShown() then
        RefreshProfileBar(CS.configFrame.profileBar)
    end
    CS.configFrame.versionText:SetText(GetVersionFooterText())
    if CS.configFrame.LayoutColumns then
        CS.configFrame.LayoutColumns()
    end
    RefreshColumn1()
    if CS.configFrame.UpdateCompactConfigRows then
        CS.configFrame.UpdateCompactConfigRows()
    end
    RefreshColumn3()
    ApplyConfigColumnTitles(CS.configFrame)

    -- Restore AceGUI scroll state.
    RestoreScrollState(CS.col1Scroll, saved1)
    if CS.pendingConfigFinderEntryScrollReset then
        CS.pendingConfigFinderEntryScrollReset = nil
        ResetScrollState(buttonSettingsScroll)
    else
        RestoreScrollState(buttonSettingsScroll, savedBtn)
    end

    if RebuildTutorialAnchors then
        RebuildTutorialAnchors()
    end
    if RefreshTutorialPlacement then
        RefreshTutorialPlacement()
    end
    CS.configRefreshInProgress = false
    if CS.RefreshAdvancedSettingsPanel then
        CS.RefreshAdvancedSettingsPanel()
    end
    if ST.UpdateArrangeBadge then
        ST.UpdateArrangeBadge()
    end

end

------------------------------------------------------------------------
-- Toggle config panel open/closed
------------------------------------------------------------------------
function CooldownCompanion:_configToggleImpl()
    if not CS.configFrame then
        CreateConfigPanel()
        SetConfigPrimaryMode("buttons", { skipRefresh = true })
        -- Defer first refresh until after column layout is computed (next frame)
        C_Timer.After(0, function()
            if not (CS.configFrame and CS.configFrame.frame and CS.configFrame.frame:IsShown()) then
                return
            end
            CooldownCompanion:RefreshConfigPanel()
            MaybeAutoOpenChangelog()
            if MaybeAutoStartFirstIconPanelTutorial then
                MaybeAutoStartFirstIconPanelTutorial()
            end
        end)
        return -- AceGUI Frame is already shown on creation
    end

    -- If minimized, close everything and reset state
    if CS.configFrame._miniFrame and CS.configFrame._miniFrame:IsShown() then
        if CS.configFrame.HideChangelogOverlay then
            CS.configFrame.HideChangelogOverlay()
        end
        if CS.CloseAdvancedSettingsPanel then
            CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
        end
        if CS.CloseSpellbookPanel then
            CS.CloseSpellbookPanel()
        end
        ClearTransientConfigPreviewState()
        CS.configFrame._miniFrame:Hide()
        return
    end

    if CS.configFrame.frame:IsShown() then
        CS.configFrame.frame:Hide()
    else
        SetConfigPrimaryMode("buttons", { skipRefresh = true })
        CS.configFrame.frame:Show()
        self:RefreshConfigPanel()
        MaybeAutoOpenChangelog()
        if MaybeAutoStartFirstIconPanelTutorial then
            MaybeAutoStartFirstIconPanelTutorial()
        end
    end
end

function CooldownCompanion:_configGetFrameImpl()
    return CS.configFrame
end
