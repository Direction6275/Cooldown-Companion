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
local ClearConfigPrimarySelection = ST._ClearConfigPrimarySelection
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local COLUMN_PADDING = ST._COLUMN_PADDING
local RefreshColumn1 = ST._RefreshColumn1
local RefreshColumn2 = ST._RefreshColumn2
local RefreshColumn3 = ST._RefreshColumn3
local RefreshColumn4 = ST._RefreshColumn4
local RefreshProfileBar = ST._RefreshProfileBar
local SetConfigPrimaryMode = ST._SetConfigPrimaryMode
local UpdateCol2CursorPreview = ST._UpdateCol2CursorPreview
local ClearCol2AnimatedPreview = ST._ClearCol2AnimatedPreview
local ClearConfigShiftTooltipHover = ST._ClearConfigShiftTooltipHover
local GetConfigEntryDisplayName = ST._GetConfigEntryDisplayName
local IsConfigFinderAvailable = ST._IsConfigFinderAvailable
local IsConfigFinderActive = ST._IsConfigFinderActive
local SetConfigFinderText = ST._SetConfigFinderText
local ClearConfigFinderText = ST._ClearConfigFinderText
local ClearHideActiveCurrentClassPanels = ST._ClearOtherClassHideActive
local ResetOtherClassBrowseState = ST._ResetOtherClassLibraryState
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
    ClearHideActiveCurrentClassPanels()
    if CS.previewToggleRefreshActive then
        return
    end
    if CooldownCompanion.ClearAllConfigPreviews then
        CooldownCompanion:ClearAllConfigPreviews()
    end
    if CooldownCompanion.RefreshConfigSelectedGroupFrames then
        CooldownCompanion:RefreshConfigSelectedGroupFrames()
    end
end

local MANUAL_COLUMN_LAYOUT = "CDC_MANUAL"
local CONFIG_FINDER_BOX_HEIGHT = 28
local CONFIG_FINDER_BUTTON_GAP = 3
local CONFIG_FINDER_RESERVED_HEIGHT = CONFIG_FINDER_BOX_HEIGHT + CONFIG_FINDER_BUTTON_GAP
local CONFIG_COMPACT_ROW_MIN_WIDTH = 236
local CONFIG_NESTED_INLINE_GROUP_INSET = 20
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

    for _, columnKey in ipairs({ "col1", "col2", "col3", "col4" }) do
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
        window.frame:ClearAllPoints()
        window.frame:SetPoint("TOPLEFT", configFrame.frame, "TOPRIGHT", 4, 0)
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
    if ST._CloseFormatEditor then
        ST._CloseFormatEditor()
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
    if ST._CloseFormatEditor then
        ST._CloseFormatEditor()
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

    if not searchFiltered and CooldownCompanion.ResolveFolderClassScope then
        for folderId, folder in pairs(db.folders or {}) do
            local scope = CooldownCompanion:ResolveFolderClassScope(folder or folderId)
            if scope and scope.scope == "other-class" then
                return true, false, true
            end
        end
    end

    return false, searchFiltered == true, hasOtherInventory
end

local GetClassColoredText = ST._GetClassColoredText

local function GetCustomBarsColumnTitle()
    return "Custom Bars & Resources"
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

local function GetSelectedFolderHeaderName(selection)
    if not (selection and selection.hasSelectedFolder and CS.selectedFolder) then
        return nil
    end

    local profile = GetConfigProfile()
    local folder = profile and profile.folders and profile.folders[CS.selectedFolder]
    return folder and NormalizeHeaderName(folder.name)
end

local function GetConfigSelectionSummary()
    return {
        panelMultiCount = CountSelections(CS.selectedPanels),
        groupMultiCount = CountSelections(CS.selectedGroups),
        hasSelectedPanel = CS.selectedGroup ~= nil,
        hasSelectedGroup = CS.selectedContainer ~= nil,
        hasSelectedFolder = CS.selectedFolder ~= nil and CS.selectedContainer == nil and CS.selectedGroup == nil,
    }
end

local function GetColumn3HeaderMode(selection)
    -- Cast Bar & Unit Frames home: the wide column 3 shows the selected
    -- column-2 row's settings.
    if CS.castFramesEntrySelected then
        if CS.castFramesSelectedItem == "player" then
            return "player_frame"
        elseif CS.castFramesSelectedItem == "target" then
            return "target_frame"
        end
        return "cast_bar"
    end
    -- Resources home: the wide column 3 hosts the surfaces column 4 used
    -- to show, so it takes over column 4's header modes too.
    if CS.resourcesEntrySelected then
        if ST._IsResourcesEmptyStateActive and ST._IsResourcesEmptyStateActive() then
            return "resources_intro"
        end
        local resourceBarSettings = CooldownCompanion:GetResourceBarSettings()
        if resourceBarSettings and resourceBarSettings.enabled == true then
            if CS.selectedResourcePowerType
                and ST._RBP
                and ST._RBP.IsResourceEditableInColumn4
                and ST._RBP.IsResourceEditableInColumn4(CS.selectedResourcePowerType, resourceBarSettings)
            then
                return "resource_settings"
            end
            if CS.selectedCustomBarId then
                return "custom_bar"
            end
        end
        return "resources_panel"
    end
    if selection.panelMultiCount >= 2 then
        return "panel_actions"
    end
    return "button"
end

local function GetColumn4HeaderMode(selection)
    if selection.panelMultiCount >= 2 or selection.hasSelectedPanel then
        return "panel"
    end
    if selection.hasSelectedFolder then
        return "folder"
    end
    return "group"
end

local function GetColumn4HeaderTitle(selection)
    local mode = GetColumn4HeaderMode(selection)
    if mode == "panel" then
        local panelName = GetSelectedPanelHeaderName(selection)
        if panelName then
            return "Panel: " .. panelName
        end
        return "Panel Settings"
    elseif mode == "folder" then
        local folderName = GetSelectedFolderHeaderName(selection)
        if folderName then
            return "Folder: " .. folderName
        end
        return "Folder Settings"
    end
    local groupName = GetSelectedGroupHeaderName(selection)
    if groupName then
        return "Group: " .. groupName
    end
    return "Group Settings"
end

local function GetColumn3HeaderTitle(selection)
    local mode = GetColumn3HeaderMode(selection)
    if mode == "resources_intro" then
        return "Resource Bars"
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
    elseif mode == "panel_actions" then
        return "Panel Actions"
    end
    if ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive() then
        -- Merged wide column: the identity strip under the preview names
        -- the selection, so the header stays static instead of tracking it.
        return "Buttons"
    end
    local entryName = GetSelectedEntryHeaderName()
    if entryName then
        return "Entry: " .. entryName
    end
    return "Button Settings"
end

local function ApplyConfigColumnTitles(frame)
    if IsConfigFinderActive and IsConfigFinderActive() then
        frame.col1:SetTitle("Groups")
        frame.col2:SetTitle("Search Results")
    elseif CS.resourcesEntrySelected then
        -- Resources home: column 2 hosts the Custom Bars & Resources list
        frame.col1:SetTitle("Groups")
        frame.col2:SetTitle(GetCustomBarsColumnTitle())
    elseif CS.castFramesEntrySelected then
        frame.col1:SetTitle("Groups")
        frame.col2:SetTitle("Cast Bar & Unit Frames")
    else
        frame.col1:SetTitle("Groups")
        frame.col2:SetTitle("Panels")
    end

    local selection = GetConfigSelectionSummary()
    frame.col3:SetTitle(GetColumn3HeaderTitle(selection))
    frame.col4:SetTitle(GetColumn4HeaderTitle(selection))
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
        local saved2 = not finderActive and SaveScrollState(CS.col2Scroll) or nil
        if finderActive then
            ResetScrollState(CS.col1Scroll)
            ResetScrollState(CS.col2Scroll)
        end
        RefreshColumn1()
        RefreshColumn2()
        if CS.configFrame.UpdateCompactConfigRows then
            CS.configFrame.UpdateCompactConfigRows()
        end
        ApplyConfigColumnTitles(CS.configFrame)
        if finderActive then
            ResetScrollState(CS.col1Scroll)
            ResetScrollState(CS.col2Scroll)
        else
            RestoreScrollState(CS.col1Scroll, saved1)
            RestoreScrollState(CS.col2Scroll, saved2)
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

    -- Wide view: entries render only on the selected panel's mirror; the
    -- retired column 2 entry rows (and their collapse state) are not a
    -- display surface here, so scan the selected panel unconditionally.
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

    local savedCol2 = SaveScrollState(CS.col2Scroll)
    local savedButtonSettings = SaveScrollState(CS.buttonSettingsScroll)
    local selectedEntryAffected = DoesButtonReferencePendingOverrideSpell(GetSelectedConfigButtonData(), pendingSpellIds)

    RefreshColumn2()
    if CS.configFrame.UpdateCompactConfigRows then
        CS.configFrame.UpdateCompactConfigRows()
    end
    if selectedEntryAffected then
        RefreshColumn3()
    elseif ST._RefreshButtonsPreviewMirror
        and DoesSelectedPanelReferencePendingOverrideSpell(pendingSpellIds) then
        -- Wide view: a non-selected entry of the mirrored panel picked up
        -- the override — its name/icon render on the mirror, not column 2.
        ST._RefreshButtonsPreviewMirror()
    end
    ApplyConfigColumnTitles(CS.configFrame)

    RestoreScrollState(CS.col2Scroll, savedCol2)
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
    ResetConfigSelection(true)
    wipe(CS.collapsedFolders)
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
        SetMainConfigDragAlpha(false)
        if CancelFirstIconPanelTutorial then
            CancelFirstIconPanelTutorial(isCollapsing and "config_collapsed" or "config_hidden")
        end
        if isCollapsing then return end
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
        ClearTransientConfigPreviewState()
        -- Release the panel-preview mirror: stops its conditional ticker
        -- and disarms override targeting while the config is closed.
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

    -- CDM Display toggle button — left of the Other Classes button
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

    cdmDisplayBtn:SetScript("OnClick", function()
        CooldownCompanion.db.profile.cdmHidden = not CooldownCompanion.db.profile.cdmHidden
        CooldownCompanion:ApplyCdmAlpha()
        UpdateCdmDisplayIcon()
    end)
    cdmDisplayBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Toggle CDM Display")
        GameTooltip:AddLine("This only toggles the visibility of the Cooldown Manager on your screen.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    cdmDisplayBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Import button — left of the CDM display toggle
    local importClusterBtn = CreateFrame("Button", nil, content)
    importClusterBtn:SetSize(18, 18)
    local importClusterIcon = importClusterBtn:CreateTexture(nil, "ARTWORK")
    importClusterIcon:SetAtlas("streamcinematic-downloadicon", false)
    importClusterIcon:SetAllPoints()
    importClusterBtn:SetHighlightAtlas("streamcinematic-downloadicon")
    importClusterBtn:GetHighlightTexture():SetAlpha(0.3)
    importClusterBtn:SetScript("OnClick", function()
        if ST._OpenImportReviewWindow then
            ST._OpenImportReviewWindow()
        end
    end)
    importClusterBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Import")
        GameTooltip:AddLine("Paste an export string to import groups, panels, or bars.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    importClusterBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Cast Bar & Unit Frames button — left of Import
    local castFramesBtn = CreateFrame("Button", nil, content)
    castFramesBtn:SetSize(18, 18)
    local castFramesIcon = castFramesBtn:CreateTexture(nil, "ARTWORK")
    castFramesIcon:SetAtlas("groupfinder-icon-friend", false)
    castFramesIcon:SetAllPoints()
    castFramesBtn:SetHighlightAtlas("groupfinder-icon-friend")
    castFramesBtn:GetHighlightTexture():SetAlpha(0.3)
    local castFramesBtnBorder
    local function UpdateCastFramesBadgeState()
        if CS.castFramesEntrySelected then
            if not castFramesBtnBorder then
                castFramesBtnBorder = castFramesBtn:CreateTexture(nil, "OVERLAY")
                castFramesBtnBorder:SetPoint("TOPLEFT", -1, 1)
                castFramesBtnBorder:SetPoint("BOTTOMRIGHT", 1, -1)
                castFramesBtnBorder:SetColorTexture(0.85, 0.65, 0.0, 0.6)
            end
            castFramesBtnBorder:Show()
        elseif castFramesBtnBorder then
            castFramesBtnBorder:Hide()
        end
    end

    castFramesBtn:SetScript("OnClick", function()
        if ST._SelectConfigCastFramesEntry then
            ST._SelectConfigCastFramesEntry({ toggle = true })
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    castFramesBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Cast Bar & Unit Frames")
        GameTooltip:AddLine("Configure the cast bar and unit frame attachments.", 1, 1, 1, true)
        GameTooltip:AddLine("Click again to return to your panels.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    castFramesBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Other Classes browse button — between the Changelog and CDM buttons
    local otherClassBrowseBtn = CreateFrame("Button", nil, content)
    otherClassBrowseBtn:SetSize(16, 16)
    if otherClassBrowseBtn.SetMotionScriptsWhileDisabled then
        otherClassBrowseBtn:SetMotionScriptsWhileDisabled(true)
    end
    local otherClassBrowseIcon = otherClassBrowseBtn:CreateTexture(nil, "ARTWORK")
    otherClassBrowseIcon:SetAtlas("BattleBar-SwapPetIcon", false)
    otherClassBrowseIcon:SetAllPoints()
    otherClassBrowseBtn:SetHighlightAtlas("BattleBar-SwapPetIcon")
    otherClassBrowseBtn:GetHighlightTexture():SetAlpha(0.3)

    local otherClassBrowseBtnBorder = nil
    local otherClassBrowseAvailable = false
    local otherClassBrowseActionAvailable = false
    local otherClassBrowseSearchFiltered = false
    local otherClassBrowseHasInventory = false

    local function UpdateOtherClassBrowseBtnHighlight()
        local shouldHighlight = otherClassBrowseActionAvailable and CS.otherClassLibraryActive == true
        if shouldHighlight then
            if not otherClassBrowseBtnBorder then
                otherClassBrowseBtnBorder = otherClassBrowseBtn:CreateTexture(nil, "OVERLAY")
                otherClassBrowseBtnBorder:SetPoint("TOPLEFT", -1, 1)
                otherClassBrowseBtnBorder:SetPoint("BOTTOMRIGHT", 1, -1)
                otherClassBrowseBtnBorder:SetColorTexture(0.85, 0.65, 0.0, 0.6)
            end
            otherClassBrowseBtnBorder:Show()
        elseif otherClassBrowseBtnBorder then
            otherClassBrowseBtnBorder:Hide()
        end
    end

    local function UpdateOtherClassBrowseButtonState()
        otherClassBrowseAvailable, otherClassBrowseSearchFiltered, otherClassBrowseHasInventory = HasOtherClassInventory()
        otherClassBrowseActionAvailable = otherClassBrowseAvailable or CS.otherClassLibraryActive == true

        if otherClassBrowseBtn.SetEnabled then
            otherClassBrowseBtn:SetEnabled(otherClassBrowseActionAvailable)
        elseif otherClassBrowseActionAvailable and otherClassBrowseBtn.Enable then
            otherClassBrowseBtn:Enable()
        elseif otherClassBrowseBtn.Disable then
            otherClassBrowseBtn:Disable()
        end
        if otherClassBrowseIcon.SetDesaturated then
            otherClassBrowseIcon:SetDesaturated(not otherClassBrowseActionAvailable)
        end
        if otherClassBrowseActionAvailable then
            otherClassBrowseBtn:SetAlpha(1)
            otherClassBrowseIcon:SetVertexColor(1, 1, 1, 1)
            if otherClassBrowseBtn:GetHighlightTexture() then
                otherClassBrowseBtn:GetHighlightTexture():SetAlpha(0.3)
            end
        else
            otherClassBrowseBtn:SetAlpha(0.75)
            otherClassBrowseIcon:SetVertexColor(0.6, 0.6, 0.6, 1)
            if otherClassBrowseBtn:GetHighlightTexture() then
                otherClassBrowseBtn:GetHighlightTexture():SetAlpha(0)
            end
        end

        UpdateOtherClassBrowseBtnHighlight()
    end

    otherClassBrowseBtn:SetScript("OnClick", function()
        CloseDropDownMenus()
        if CS.otherClassLibraryActive then
            if ClearConfigPrimarySelection then
                ClearConfigPrimarySelection()
            end
            ResetOtherClassBrowseState()
            CooldownCompanion:RefreshConfigPanel()
            return
        end
        if not otherClassBrowseAvailable then
            return
        end
        if ClearConfigPrimarySelection then
            ClearConfigPrimarySelection()
        end
        ClearHideActiveCurrentClassPanels()
        CS.otherClassLibraryActive = true
        CS.otherClassLibraryClassKey = nil
        CooldownCompanion:RefreshConfigPanel()
    end)
    otherClassBrowseBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Browse Other Classes")
        if CS.otherClassLibraryActive then
            GameTooltip:AddLine("Class library is open. Click to return to the regular config view.", 1, 1, 1, true)
        elseif not otherClassBrowseActionAvailable then
            if otherClassBrowseSearchFiltered and otherClassBrowseHasInventory then
                GameTooltip:AddLine("No other classes match the current search.", 1, 1, 1, true)
            else
                GameTooltip:AddLine("No other classes on this profile currently have groups to browse.", 1, 1, 1, true)
            end
        else
            GameTooltip:AddLine("View and edit groups saved for other classes on this profile.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    otherClassBrowseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
    otherClassBrowseBtn:SetPoint("RIGHT", changelogBtn, "LEFT", -4, 0)
    cdmDisplayBtn:SetPoint("RIGHT", otherClassBrowseBtn, "LEFT", -4, 0)
    importClusterBtn:SetPoint("RIGHT", cdmDisplayBtn, "LEFT", -4, 0)
    castFramesBtn:SetPoint("RIGHT", importClusterBtn, "LEFT", -4, 0)
    local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
    gearIcon:SetTexture("Interface\\WorldMap\\GEAR_64GREY")
    gearIcon:SetAllPoints()
    gearBtn:SetHighlightTexture("Interface\\WorldMap\\GEAR_64GREY")
    gearBtn:GetHighlightTexture():SetAlpha(0.3)
    -- Fire on mouse down so a second gear click closes the open dropdown instead of reopening it on mouse up.
    gearBtn:RegisterForClicks("LeftButtonDown")
    CS.gearButton = gearBtn

    local function IsGearDropdownOpen()
        local listFrame = _G.DropDownList1
        return CS.gearDropdownFrame and listFrame and listFrame:IsShown() and listFrame.dropdown == CS.gearDropdownFrame
    end

    local function HookGearDropdownHide()
        local listFrame = _G.DropDownList1
        if not listFrame or CS.gearDropdownHideHooked then return end
        CS.gearDropdownHideHooked = true
        listFrame:HookScript("OnHide", function(frame)
            local currentGearButton = CS.gearButton
            local gearClickHidden = currentGearButton
                and MouseIsOver and MouseIsOver(currentGearButton)
                and IsMouseButtonDown and IsMouseButtonDown("LeftButton")
            if frame.dropdown == CS.gearDropdownFrame and gearClickHidden then
                CS.gearDropdownClosedByGearClick = true
            end
        end)
    end

    -- Gear dropdown menu
    gearBtn:SetScript("OnMouseDown", function()
        CS.gearDropdownWasOpenOnMouseDown = IsGearDropdownOpen()
    end)

    gearBtn:SetScript("OnClick", function()
        if CS.gearDropdownWasOpenOnMouseDown or CS.gearDropdownClosedByGearClick then
            CS.gearDropdownWasOpenOnMouseDown = nil
            CS.gearDropdownClosedByGearClick = nil
            CloseDropDownMenus()
            CS.gearDropdownClosedByGearClick = nil
            return
        end
        CS.gearDropdownWasOpenOnMouseDown = nil

        if not CS.gearDropdownFrame then
            CS.gearDropdownFrame = CreateFrame("Frame", "CDCGearDropdown", UIParent, "UIDropDownMenuTemplate")
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
        ToggleDropDownMenu(1, nil, CS.gearDropdownFrame, gearBtn, 0, 0)
        HookGearDropdownHide()
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
            ClearTransientConfigPreviewState()
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
            CloseProfileWideFontWindow()
            CloseProfileWideBarTextureWindow()
            if CS.CloseAdvancedSettingsPanel then
                CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
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
    changelogOverlay = SetupChangelogOverlay(frame, colParent, UpdateChangelogBtnHighlight)

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
        if CS.resourcesEntrySelected then
            GameTooltip:AddLine("Custom Bars & Resources")
            GameTooltip:AddLine("Create Custom Bars and manage enabled resource-specific settings.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Active Custom Bars shows Custom Bars currently loadable for your spec and conditions.", 1, 1, 1, true)
            GameTooltip:AddLine("Resources opens settings for enabled non-health resources.", 1, 1, 1, true)
            GameTooltip:AddLine("Inactive Custom Bars shows Custom Bars blocked by spec, talents, load conditions, or disabled state.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("No spec filter means a Custom Bar applies to every spec.", 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
        if CS.castFramesEntrySelected then
            GameTooltip:AddLine("Cast Bar & Unit Frames")
            GameTooltip:AddLine("Select the Cast Bar or a unit frame to configure it in the settings column.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("These settings are saved per character.", 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
        GameTooltip:AddLine("Panels")
        GameTooltip:AddLine("A panel controls dimensions, display mode, and layout for all entries inside it. Every entry needs a panel, even if it's just one.", 1, 1, 1, true)
        GameTooltip:AddLine("Select a panel to preview and edit its entries in the settings column.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click to select/deselect.", 1, 1, 1)
        GameTooltip:AddLine("Right-click for options.", 1, 1, 1)
        GameTooltip:AddLine("Hold left-click and drag to reorder.", 1, 1, 1)
        GameTooltip:AddLine("Ctrl+Left-click to multi-select.", 1, 1, 1, true)
        GameTooltip:AddLine("Middle-click to toggle anchor lock.", 1, 1, 1, true)
        GameTooltip:AddLine("Click |cff4dcc4d+|r to add an entry to that panel.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag spells/items from your spellbook or inventory onto a panel to add.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    col2._infoBtn = infoBtn

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
        if CS.castFramesEntrySelected and CS.castFramesSelectedItem ~= "player" and CS.castFramesSelectedItem ~= "target" then
            GameTooltip:AddLine("Cast Bar")
            GameTooltip:AddLine("Skins the Blizzard cast bar and anchors it to a panel, or positions it anywhere on screen.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Use the preview pane to drag the attached cast bar around the mirrored icon panel.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("These settings are saved per character.", 1, 1, 1, true)
        elseif CS.castFramesEntrySelected then
            GameTooltip:AddLine("Unit Frames")
            GameTooltip:AddLine("Anchors your player and target unit frames to your panels.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("These settings are saved per character.", 1, 1, 1, true)
        elseif ST._IsResourcesEmptyStateActive and ST._IsResourcesEmptyStateActive() then
            GameTooltip:AddLine("Resource Bars")
            GameTooltip:AddLine("Enable Resource Bars to configure Resources and Custom Bars here.", 1, 1, 1, true)
        elseif CS.resourcesEntrySelected and not CS.selectedResourcePowerType and not CS.selectedCustomBarId then
            GameTooltip:AddLine("Resource Bars")
            GameTooltip:AddLine("Shared resource bar settings, organized into tabs.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Use the preview pane to drag attached bars around the mirrored icon panel. Layout is saved per specialization.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Select a resource or Custom Bar in the list column for per-bar settings.", 1, 1, 1, true)
        elseif CS.resourcesEntrySelected then
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
            local mode = GetColumn3HeaderMode(selection)
            if mode == "panel_actions" then
                GameTooltip:AddLine("Panel Actions")
                GameTooltip:AddLine("Select multiple panels to batch-manage them here.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Select a single panel to configure it here instead.", 1, 1, 1, true)
            else
                GameTooltip:AddLine("Settings")
                GameTooltip:AddLine("Shows settings for the selected group, panel, or entry.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Panel settings apply to every button in the panel. Selecting a button shows that entry's own settings; deselect it to return to the panel settings.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("To override a panel setting for one button, click the |A:Crosshair_VehichleCursor_32:14:14|a badge next to that setting while the button is selected.", 1, 1, 1, true)
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
        do
            local selection = GetConfigSelectionSummary()
            local mode = GetColumn4HeaderMode(selection)
            if mode == "folder" then
                GameTooltip:AddLine("Folder Settings")
                GameTooltip:AddLine("The selected folder is configured here.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Folder load conditions apply to all groups inside the folder.", 1, 1, 1, true)
            elseif mode == "panel" then
                GameTooltip:AddLine("Panel Settings")
                if selection.panelMultiCount >= 2 then
                    GameTooltip:AddLine("Select a single panel to configure it here.", 1, 1, 1, true)
                else
                    GameTooltip:AddLine("Select a panel header or any button inside it to configure that panel here.", 1, 1, 1, true)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Panel settings apply to all buttons in that panel.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("If you want to override a setting for this specific button, click the |A:Crosshair_VehichleCursor_32:14:14|a badge next to the associated panel level setting while this button is selected.", 1, 1, 1, true)
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

    -- Store column header (?) buttons for lifecycle cleanup.
    wipe(CS.columnInfoButtons)
    CS.columnInfoButtons[1] = groupInfoBtn
    CS.columnInfoButtons[2] = infoBtn
    CS.columnInfoButtons[3] = bsInfoBtn
    CS.columnInfoButtons[4] = settingsInfoBtn

    -- Static button bar at bottom of column 1 (New Group + New Folder + Resources)
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
        { value = "loadconditions", text = "Load Conditions" },
    })
    bsTabGroup:SetLayout("Fill")

    bsTabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
        local previousTab = col3._activeButtonSettingsTab
        local tabChanged = previousTab ~= nil and previousTab ~= tab
        col3._activeButtonSettingsTab = tab
        CS.buttonSettingsTab = tab
        -- Clean up info/collapse buttons before releasing
        for _, btn in ipairs(CS.buttonSettingsInfoButtons) do
            btn:ClearAllPoints()
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(CS.buttonSettingsInfoButtons)

        if tabChanged and not CS.previewToggleRefreshActive then
            CooldownCompanion:ClearAllConfigPreviews()
        end
        widget:ReleaseChildren()

        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        widget:AddChild(scroll)
        buttonSettingsScroll = scroll
        CS.buttonSettingsScroll = scroll

        local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
        if not group then return end

        if group.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT
            and CS.selectedRotationAssistantEntry == true then
            if tab == "loadconditions" then
                local buttonData = CooldownCompanion:GetRotationAssistantConfigButtonData(group)
                ST._BuildEntryLoadConditionsTab(scroll, buttonData, CS.buttonSettingsInfoButtons)
            end
            return
        end

        local buttonData = CS.selectedButton and group.buttons[CS.selectedButton]
        if not buttonData then return end

        if tab == "settings" then
            if group.displayMode == "trigger" then
                ST._BuildTriggerConditionSettings(scroll, buttonData, CS.buttonSettingsInfoButtons)
            else
                if buttonData.type == "item" and not CooldownCompanion.IsItemEquippable(buttonData) then
                    ST._BuildItemSettings(scroll, buttonData, CS.buttonSettingsInfoButtons)
                elseif buttonData.type == "item" and CooldownCompanion.IsItemEquippable(buttonData) then
                    ST._BuildEquipItemSettings(scroll, buttonData, CS.buttonSettingsInfoButtons)
                end
                ST._BuildVisibilitySettings(scroll, buttonData, CS.buttonSettingsInfoButtons)
                ST._BuildCustomKeybindSection(scroll, buttonData)
                ST._BuildCustomNameSection(scroll, buttonData)
            end
        elseif tab == "aura" then
            ST._BuildAuraTab(scroll, group, buttonData, CS.buttonSettingsInfoButtons)
        elseif tab == "soundalerts" then
            if group.displayMode == "trigger" then
                ST._BuildTriggerPanelSoundAlertsTab(scroll, group, buttonData, CS.buttonSettingsInfoButtons)
            else
                ST._BuildSpellSoundAlertsTab(scroll, buttonData, CS.buttonSettingsInfoButtons)
            end
        elseif tab == "fallbacks" then
            ST._BuildItemFallbacksTab(scroll, buttonData, CS.buttonSettingsInfoButtons)
        elseif tab == "loadconditions" then
            ST._BuildEntryLoadConditionsTab(scroll, buttonData, CS.buttonSettingsInfoButtons)
        elseif tab == "overrides" then
            ST._BuildOverridesTab(scroll, buttonData, CS.buttonSettingsInfoButtons)
        end

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

        if frame.titlebg then
            frame.titlebg:ClearAllPoints()
            frame.titlebg:SetPoint("TOP", content, "TOP", xOffset, 12)
        end
    end

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
        local col2RowWidth = GetScrollRowWidth(CS.col2Scroll, col2.content) - CONFIG_NESTED_INLINE_GROUP_INSET
        local narrowestRowWidth = math.min(col1RowWidth, math.max(0, col2RowWidth))
        if narrowestRowWidth <= 0 then
            return
        end

        local compact = narrowestRowWidth < CONFIG_COMPACT_ROW_MIN_WIDTH
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

        -- Talent picker mode: 2 wide columns (col1 + col3), col2/col4 hidden
        if CS.talentPickerMode then
            if CS.configFinderBox then
                CS.configFinderBox.frame:Hide()
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

        local usedWidth = (equalColWidth * 4) + (pad * 3)
        local leftoverWidth = math.max(0, w - usedWidth)

        -- Wide col3 layouts: cols 1-2 stay normal, col3 widens across the
        -- col4 region, col4 hides. Used by the plain buttons view (merged
        -- settings column) and the Resources home (preview + settings).
        local wideCol3 = ST._IsWideCol3LayoutActive
            and ST._IsWideCol3LayoutActive()

        local col1Width = equalColWidth
        local col2Width = equalColWidth
        local col3Width = equalColWidth
        local col4Width = equalColWidth + leftoverWidth
        if wideCol3 then
            col3Width = (equalColWidth * 2) + pad + leftoverWidth
        end
        local finderAvailable = IsConfigFinderAvailable and IsConfigFinderAvailable()

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
            local bottomInset = finderAvailable and (30 + CONFIG_FINDER_RESERVED_HEIGHT) or 30
            CS.col1Scroll.frame:ClearAllPoints()
            CS.col1Scroll.frame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, 0)
            CS.col1Scroll.frame:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, bottomInset)
        end

        col1.frame:ClearAllPoints()
        col1.frame:SetPoint("TOPLEFT", colParent, "TOPLEFT", 0, 0)
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
        col4.frame:SetShown(not wideCol3)

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
    frame.otherClassBrowseButton = otherClassBrowseBtn
    frame.col1 = col1
    frame.col2 = col2
    frame.col3 = col3
    frame.col4 = col4
    frame.colParent = colParent
    frame.LayoutColumns = LayoutColumns
    frame.UpdateCompactConfigRows = UpdateCompactConfigRows
    frame.UpdateCastFramesBadgeState = UpdateCastFramesBadgeState
    frame.UpdateOtherClassBrowseButtonState = UpdateOtherClassBrowseButtonState
    UpdateOtherClassBrowseButtonState()

    CS.configFrame = frame
    return frame
end

------------------------------------------------------------------------
-- Refresh entire panel
------------------------------------------------------------------------
function CooldownCompanion:_configRefreshPanelImpl()
    if not CS.configFrame then return end
    if not CS.configFrame.frame:IsShown() then return end
    if CS.talentPickerMode then return end
    if CS.configRefreshInProgress or CS.advancedSettingsPanelRefreshing then return end
    if self.RefreshConfigSelectedGroupFrames then
        self:RefreshConfigSelectedGroupFrames()
    end
    CS.configRefreshInProgress = true
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

    -- Save AceGUI scroll state before any column rebuilds. (The relocated
    -- resources/cast settings surfaces preserve their own scroll positions
    -- inside ResourcesWideColumn.lua; the moved Custom Bars list rides the
    -- col2 save below.)
    local saved1   = SaveScrollState(CS.col1Scroll)
    local saved2   = SaveScrollState(CS.col2Scroll)
    local savedBtn = SaveScrollState(buttonSettingsScroll)

    if CS.configFrame.profileBar:IsShown() then
        RefreshProfileBar(CS.configFrame.profileBar)
    end
    CS.configFrame.versionText:SetText(GetVersionFooterText())
    if CS.configFrame.UpdateCastFramesBadgeState then
        CS.configFrame.UpdateCastFramesBadgeState()
    end
    if CS.configFrame.UpdateOtherClassBrowseButtonState then
        CS.configFrame.UpdateOtherClassBrowseButtonState()
    end
    if CS.configFrame.LayoutColumns then
        CS.configFrame.LayoutColumns()
    end
    RefreshColumn1()
    RefreshColumn2()
    if CS.configFrame.UpdateCompactConfigRows then
        CS.configFrame.UpdateCompactConfigRows()
    end
    RefreshColumn3()
    RefreshColumn4(CS.col4Container)
    ApplyConfigColumnTitles(CS.configFrame)

    -- Restore AceGUI scroll state.
    RestoreScrollState(CS.col1Scroll, saved1)
    RestoreScrollState(CS.col2Scroll, saved2)
    RestoreScrollState(buttonSettingsScroll, savedBtn)

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
        ClearTransientConfigPreviewState()
        CS.configFrame._miniFrame:Hide()
        return
    end

    if CS.configFrame.frame:IsShown() then
        ClearHideActiveCurrentClassPanels()
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
