--[[
    CooldownCompanion - Config/State
    Shared mutable state, constants, core helpers, and UI building blocks.
    All cross-file state lives in ST._configState (aliased as CS).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local AceGUI = LibStub("AceGUI-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

if AceGUI and not ST._aceguiCheckboxCreatePatched then
    ST._aceguiCheckboxCreatePatched = true
    local aceguiCreate = AceGUI.Create
    AceGUI.Create = function(self, widgetType, ...)
        local widget = aceguiCreate(self, widgetType, ...)
        if widgetType == "CheckBox" and widget and widget.checkbg then
            widget.checkbg:ClearAllPoints()
            widget.checkbg:SetPoint("TOPLEFT")
        end
        return widget
    end
end

-- Viewer frame names (mirrors Core.lua's local VIEWER_NAMES)
local CDM_VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

-- Font options for dropdown (LSM-backed, cached and invalidated on new font registration)
local fontOptionsCache
local function GetFontOptions()
    if fontOptionsCache then return fontOptionsCache end
    local t = {}
    for _, name in ipairs(LSM:List("font")) do
        t[name] = name
    end
    fontOptionsCache = t
    return t
end

local function InvalidateFontCache()
    fontOptionsCache = nil
end
ST._InvalidateFontCache = InvalidateFontCache

-- Sets up a font dropdown with correct name→name list and per-item font preview
local function SetupFontDropdown(dropdown)
    dropdown:SetList(GetFontOptions())
    dropdown:SetCallback("OnOpened", function(self)
        for i, item in self.pullout:IterateItems() do
            local fontName = item.userdata.value
            if fontName and item.text then
                local fontPath = LSM:Fetch("font", fontName)
                if fontPath then
                    local _, size, flags = item.text:GetFont()
                    item.text:SetFont(fontPath, size or 11, flags or "")
                end
            end
        end
    end)
end

local outlineOptions = {
    [""] = "None",
    ["OUTLINE"] = "Outline",
    ["THICKOUTLINE"] = "Thick Outline",
    ["MONOCHROME"] = "Monochrome",
}

-- Strata ordering element definitions
local strataElementLabels = {
    cooldown = "Cooldown Swipe",
    auraGlow = "Aura / Pandemic Glow",
    readyGlow = "Ready Glow",
    chargeText = "Text Overlay",
    procGlow = "Proc Glow",
    assistedHighlight = "Assisted Highlight",
}
local strataElementKeys = {"cooldown", "auraGlow", "readyGlow", "chargeText", "assistedHighlight", "procGlow"}

-- Anchor point options
local anchorPoints = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

local anchorPointLabels = {
    TOPLEFT = "Top Left",
    TOP = "Top",
    TOPRIGHT = "Top Right",
    LEFT = "Left",
    CENTER = "Center",
    RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left",
    BOTTOM = "Bottom",
    BOTTOMRIGHT = "Bottom Right",
}

-- Pre-built anchor dropdown list (avoids rebuilding per-widget)
local anchorDropdownList = {}
for _, pt in ipairs(anchorPoints) do
    anchorDropdownList[pt] = anchorPointLabels[pt]
end

-- Layout constants
local COLUMN_PADDING = 8
local BUTTON_HEIGHT = 24
local BUTTON_SPACING = 2
local PROFILE_BAR_HEIGHT = 36

------------------------------------------------------------------------
-- Shared config state table
------------------------------------------------------------------------
ST._configState = {
    -- Selection state
    selectedContainer = nil,     -- containerId selected in Column 1
    selectedGroup = nil,         -- panelId (groupId) selected in Column 2 panel list
    selectedButton = nil,
    selectedButtons = {},
    selectedPanels = {},         -- multi-selected panel IDs (within a container)
    selectedGroups = {},         -- multi-selected container IDs
    selectedTab = "appearance",
    selectedContainerTab = "general",
    buttonSettingsTab = "settings",
    panelSettingsTab = "appearance",
    newInput = "",

    -- Main frame reference
    configFrame = nil,

    -- Column content frames
    col1Scroll = nil,
    col1ButtonBar = nil,
    col2Scroll = nil,
    col2ButtonBar = nil,
    col4Container = nil,
    col4Scroll = nil,

    -- AceGUI widget tracking for cleanup
    col1BarWidgets = {},
    col2BarWidgets = {},
    profileBarAceWidgets = {},
    buttonSettingsInfoButtons = {},

    buttonSettingsScroll = nil,
    columnInfoButtons = {},
    moveMenuFrame = nil,
    groupContextMenu = nil,
    buttonContextMenu = nil,
    gearDropdownFrame = nil,
    folderContextMenu = nil,
    folderIconPickerFrame = nil,
    buttonIconPickerFrame = nil,
    panelContextMenu = nil,
    charCopyMenu = nil,

    -- Cross-character browse mode
    browseMode = false,
    browseCharKey = nil,
    browseContainerId = nil,
    browseContextMenu = nil,

    -- Drag-reorder state
    dragState = nil,
    dragIndicator = nil,
    dragTracker = nil,
    showPhantomSections = false,
    lastCol1RenderedRows = nil,
    lastCol2PanelMetas = nil,
    col1Preview = nil,
    col2Preview = nil,

    -- Pending strata order state
    pendingStrataOrder = nil,
    pendingStrataGroup = nil,

    -- Collapsed sections state
    collapsedSections = {},
    collapsedFolders = {},
    collapsedPanels = {},
    panelClickTimes = {},
    addingToPanelId = nil,
    folderAccentBars = {},
    _panelDropTargets = {},

    -- Talent picker mode (2-column layout)
    talentPickerMode = false,

    -- Autocomplete state
    autocompleteCache = nil,
    pendingEditBoxFocus = false,

    -- Spec filter inline expansion
    specExpandedGroupId = nil,
    specExpandedFolderId = nil,

    -- Auto Add flow state (Column 3 wizard mode)
    autoAddFlowActive = false,
    autoAddFlowState = nil,

    -- Tab UI state (populated by ConfigSettings, cleaned by both files)
    tabInfoButtons = {},
    appearanceTabElements = {},
    resourceBarPanelActive = false,
    barPanelTab = "resource_anchoring",
    resourceStylingTab = "bar_text",
    castBarStylingTab = "styling",
    resourceAuraOverlayDrafts = {},
    customAuraBarTab = "bar_1",
    customAuraBarSubTabs = {},
    groupPresetSelection = {
        icons = nil,
        bars = nil,
    },

    -- Static lookup tables
    fontOptions = GetFontOptions,
    SetupFontDropdown = SetupFontDropdown,
    outlineOptions = outlineOptions,
    strataElementLabels = strataElementLabels,
    strataElementKeys = strataElementKeys,
    anchorPoints = anchorPoints,
    anchorPointLabels = anchorPointLabels,
    anchorDropdownList = anchorDropdownList,

    -- CS.* function forward declarations (set by later files)
    IsStrataOrderComplete = nil,
    InitPendingStrataOrder = nil,
    SetConfigPrimaryMode = nil,
    StartPickFrame = nil,
    StartPickCDM = nil,
    ShowPopupAboveConfig = nil,
    ShowAutocompleteResults = nil,
    HideAutocomplete = nil,
    SearchAutocompleteInCache = nil,
    HandleAutocompleteKeyDown = nil,
    ConsumeAutocompleteEnter = nil,
    SetupAutocompleteKeyHandler = nil,
}
local CS = ST._configState

------------------------------------------------------------------------
-- Strata order helpers
------------------------------------------------------------------------
local STRATA_ELEMENT_COUNT = #ST.DEFAULT_STRATA_ORDER

local function IsStrataOrderComplete(order)
    if not order then return false end
    for i = 1, STRATA_ELEMENT_COUNT do
        if not order[i] then return false end
    end
    return true
end

local function InitPendingStrataOrder(groupId)
    if CS.pendingStrataGroup == groupId and CS.pendingStrataOrder then return end
    CS.pendingStrataGroup = groupId
    local groups = CooldownCompanion.db.profile.groups
    local group = groups[groupId]
    local saved = group and group.style and group.style.strataOrder
    if saved and IsStrataOrderComplete(saved) then
        CS.pendingStrataOrder = {}
        for i = 1, STRATA_ELEMENT_COUNT do
            CS.pendingStrataOrder[i] = saved[i]
        end
    else
        CS.pendingStrataOrder = {}
        for i = 1, STRATA_ELEMENT_COUNT do
            CS.pendingStrataOrder[i] = ST.DEFAULT_STRATA_ORDER[i]
        end
    end
end

CS.IsStrataOrderComplete = IsStrataOrderComplete
CS.InitPendingStrataOrder = InitPendingStrataOrder

------------------------------------------------------------------------
-- Helper: Show a StaticPopup above the config panel
------------------------------------------------------------------------
local function ShowPopupAboveConfig(which, text_arg1, data)
    local dialog = StaticPopup_Show(which, text_arg1, nil, data)
    if dialog then
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(200)
    end
    return dialog
end
CS.ShowPopupAboveConfig = ShowPopupAboveConfig

------------------------------------------------------------------------
-- Helper: Get icon for a button data entry
------------------------------------------------------------------------
local function GetButtonIcon(buttonData)
    local manualIcon = buttonData.manualIcon
    if type(manualIcon) == "number" or type(manualIcon) == "string" then
        return manualIcon
    end
    if buttonData.type == "spell" then
        return C_Spell.GetSpellTexture(buttonData.id) or 134400
    elseif buttonData.type == "item" then
        return C_Item.GetItemIconByID(buttonData.id) or 134400
    end
    return 134400
end

------------------------------------------------------------------------
-- Helper: Get icon for a group (from its first button)
------------------------------------------------------------------------
local function GetGroupIcon(group)
    if group.buttons and group.buttons[1] then
        return GetButtonIcon(group.buttons[1])
    end
    return 134400
end

------------------------------------------------------------------------
-- Helper: Validate icon texture (number or string)
------------------------------------------------------------------------
local function IsValidIconTexture(iconTexture)
    local iconType = type(iconTexture)
    return iconType == "number" or iconType == "string"
end

------------------------------------------------------------------------
-- Helper: Get icon for a container (from its first panel's first button)
------------------------------------------------------------------------
local function GetContainerIcon(containerId, db)
    if not db then return 134400 end
    local container = db.groupContainers and db.groupContainers[containerId]
    if container and IsValidIconTexture(container.manualIcon) then
        return container.manualIcon
    end
    if not db.groups then return 134400 end
    local firstPanel, firstOrder
    for gid, group in pairs(db.groups) do
        if group.parentContainerId == containerId then
            local order = group.order or gid
            if not firstOrder or order < firstOrder then
                firstOrder = order
                firstPanel = group
            end
        end
    end
    if firstPanel then
        return GetGroupIcon(firstPanel)
    end
    return 134400
end

------------------------------------------------------------------------
-- Helper: Get icon for a folder (manual override, else first child group's first button)
------------------------------------------------------------------------
local function GetAutoFolderIcon(folderId, db)
    if not db then
        return 134400
    end
    -- Post-migration: folderId lives on containers, not groups
    local containers = db.groupContainers
    if containers then
        local children = {}
        for cid, container in pairs(containers) do
            if container.folderId == folderId then
                table.insert(children, { id = cid, order = CooldownCompanion:GetOrderForSpec(container, CooldownCompanion._currentSpecId, cid) })
            end
        end
        table.sort(children, function(a, b) return a.order < b.order end)
        if children[1] and db.groups then
            -- Find first panel of this container for its icon
            local containerId = children[1].id
            local firstPanel, firstOrder
            for gid, group in pairs(db.groups) do
                if group.parentContainerId == containerId then
                    local order = group.order or gid
                    if not firstOrder or order < firstOrder then
                        firstOrder = order
                        firstPanel = group
                    end
                end
            end
            if firstPanel then
                return GetGroupIcon(firstPanel)
            end
        end
    end
    return 134400
end

local function GetFolderIcon(folderId, db)
    if not db then
        return 134400
    end
    local folder = db.folders and db.folders[folderId]
    if folder and IsValidIconTexture(folder.manualIcon) then
        return folder.manualIcon
    end
    return GetAutoFolderIcon(folderId, db)
end

------------------------------------------------------------------------
-- Helper: generate a unique folder name
------------------------------------------------------------------------
local function GenerateFolderName(base)
    local db = CooldownCompanion.db.profile
    local existing = {}
    for _, f in pairs(db.folders) do
        existing[f.name] = true
    end
    local name = base
    if existing[name] then
        local n = 1
        while existing[name .. " " .. n] do
            n = n + 1
        end
        name = name .. " " .. n
    end
    return name
end

------------------------------------------------------------------------
-- Folder icon picker
------------------------------------------------------------------------
local function EnsureFolderIconPickerFrame()
    if CS.folderIconPickerFrame then
        return CS.folderIconPickerFrame
    end

    if not CreateAndInitFromMixin
        or not IconDataProviderMixin
        or not IconDataProviderExtraType
        or not IconSelectorPopupFrameTemplateMixin
        or not IconSelectorPopupFrameIconFilterTypes then
        return nil
    end

    local frame = CreateFrame("Frame", "CDCFolderIconPickerFrame", UIParent, "IconSelectorPopupFrameTemplate")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(200)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame.BorderBox.EditBoxHeaderText:Hide()
    frame.BorderBox.IconSelectorEditBox:Hide()

    -- Override strata/level: the template hardcodes IconSelector to HIGH strata
    -- and BorderBox to frameLevel 50, both below FULLSCREEN_DIALOG where CC lives.
    frame.IconSelector:SetFrameStrata("FULLSCREEN_DIALOG")
    frame.IconSelector:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.BorderBox:SetFrameLevel(frame:GetFrameLevel() + 5)
    -- Dropdown menu popup must be at TOOLTIP strata so it renders above the picker.
    -- The menu system mirrors ownerRegion strata when it is TOOLTIP (MenuManagerMixin:AcquireMenu).
    frame.BorderBox.IconTypeDropdown:SetFrameStrata("TOOLTIP")

    function frame:OnHide()
        IconSelectorPopupFrameTemplateMixin.OnHide(self)
        if self.iconDataProvider then
            self.iconDataProvider:Release()
            self.iconDataProvider = nil
        end
        self._cdcFolderId = nil
        self.IconSelector:SetSelectedCallback(nil)
    end

    function frame:OkayButton_OnClick()
        local folderId = self._cdcFolderId
        local iconTexture = self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture()
        local db = CooldownCompanion.db and CooldownCompanion.db.profile
        local folder = db and db.folders and db.folders[folderId]
        if folder and IsValidIconTexture(iconTexture) then
            folder.manualIcon = iconTexture
            CooldownCompanion:RefreshConfigPanel()
        end
        IconSelectorPopupFrameTemplateMixin.OkayButton_OnClick(self)
    end

    function frame:CancelButton_OnClick()
        IconSelectorPopupFrameTemplateMixin.CancelButton_OnClick(self)
    end

    CS.folderIconPickerFrame = frame
    return frame
end

local function OpenFolderIconPicker(folderId)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local folder = db and db.folders and db.folders[folderId]
    if not folder then
        return false
    end

    local pickerFrame = EnsureFolderIconPickerFrame()
    if not pickerFrame then
        CooldownCompanion:Print("Folder icon picker is unavailable on this client build.")
        return false
    end

    if pickerFrame:IsShown() then
        pickerFrame:Hide()
    end

    pickerFrame._cdcFolderId = folderId
    pickerFrame.iconDataProvider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.None)
    pickerFrame:SetIconFilter(IconSelectorPopupFrameIconFilterTypes.All)

    local currentIcon = folder.manualIcon
    if not IsValidIconTexture(currentIcon) then
        currentIcon = GetAutoFolderIcon(folderId, db)
    end

    local selectedIndex = pickerFrame:GetIndexOfIcon(currentIcon)
    if not selectedIndex then
        selectedIndex = 1
        currentIcon = pickerFrame:GetIconByIndex(selectedIndex)
    end

    pickerFrame.IconSelector:SetSelectionsDataProvider(
        function(selectionIndex)
            return pickerFrame:GetIconByIndex(selectionIndex)
        end,
        function()
            return pickerFrame:GetNumIcons()
        end
    )
    pickerFrame.IconSelector:SetSelectedIndex(selectedIndex)
    pickerFrame.IconSelector:ScrollToSelectedIndex()
    pickerFrame.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(currentIcon)
    pickerFrame:SetSelectedIconText()
    pickerFrame.BorderBox.OkayButton:Enable()

    pickerFrame.IconSelector:SetSelectedCallback(function(_, icon)
        pickerFrame.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(icon)
        pickerFrame:SetSelectedIconText()
    end)

    pickerFrame:Show()
    return true
end

------------------------------------------------------------------------
-- Button icon picker (per-entry icon art override)
------------------------------------------------------------------------
local function EnsureButtonIconPickerFrame()
    if CS.buttonIconPickerFrame then
        return CS.buttonIconPickerFrame
    end

    if not CreateAndInitFromMixin
        or not IconDataProviderMixin
        or not IconDataProviderExtraType
        or not IconSelectorPopupFrameTemplateMixin
        or not IconSelectorPopupFrameIconFilterTypes then
        return nil
    end

    local frame = CreateFrame("Frame", "CDCButtonIconPickerFrame", UIParent, "IconSelectorPopupFrameTemplate")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(200)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.BorderBox.EditBoxHeaderText:Hide()
    frame.BorderBox.IconSelectorEditBox:Hide()

    -- Override strata/level: the template hardcodes IconSelector to HIGH strata
    -- and BorderBox to frameLevel 50, both below FULLSCREEN_DIALOG where CC lives.
    frame.IconSelector:SetFrameStrata("FULLSCREEN_DIALOG")
    frame.IconSelector:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.BorderBox:SetFrameLevel(frame:GetFrameLevel() + 5)
    -- Dropdown menu popup must be at TOOLTIP strata so it renders above the picker.
    -- The menu system mirrors ownerRegion strata when it is TOOLTIP (MenuManagerMixin:AcquireMenu).
    frame.BorderBox.IconTypeDropdown:SetFrameStrata("TOOLTIP")

    function frame:OnHide()
        IconSelectorPopupFrameTemplateMixin.OnHide(self)
        if self.iconDataProvider then
            self.iconDataProvider:Release()
            self.iconDataProvider = nil
        end
        self._cdcGroupId = nil
        self._cdcButtonIndex = nil
        self.IconSelector:SetSelectedCallback(nil)
    end

    function frame:OkayButton_OnClick()
        local groupId = self._cdcGroupId
        local buttonIndex = self._cdcButtonIndex
        local iconTexture = self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture()
        local db = CooldownCompanion.db and CooldownCompanion.db.profile
        local group = db and db.groups and db.groups[groupId]
        local buttonData = group and group.buttons and group.buttons[buttonIndex]
        if buttonData and IsValidIconTexture(iconTexture) then
            buttonData.manualIcon = iconTexture
            CooldownCompanion:RefreshGroupFrame(groupId)
            CooldownCompanion:RefreshConfigPanel()
        end
        IconSelectorPopupFrameTemplateMixin.OkayButton_OnClick(self)
    end

    function frame:CancelButton_OnClick()
        IconSelectorPopupFrameTemplateMixin.CancelButton_OnClick(self)
    end

    CS.buttonIconPickerFrame = frame
    return frame
end

local function OpenButtonIconPicker(groupId, buttonIndex)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = db and db.groups and db.groups[groupId]
    local buttonData = group and group.buttons and group.buttons[buttonIndex]
    if not buttonData then
        return false
    end

    local pickerFrame = EnsureButtonIconPickerFrame()
    if not pickerFrame then
        CooldownCompanion:Print("Icon picker is unavailable on this client build.")
        return false
    end

    if pickerFrame:IsShown() then
        pickerFrame:Hide()
    end

    pickerFrame._cdcGroupId = groupId
    pickerFrame._cdcButtonIndex = buttonIndex
    pickerFrame.iconDataProvider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.None)
    pickerFrame:SetIconFilter(IconSelectorPopupFrameIconFilterTypes.All)

    local currentIcon = buttonData.manualIcon
    if not IsValidIconTexture(currentIcon) then
        currentIcon = GetButtonIcon(buttonData)
    end

    local selectedIndex = pickerFrame:GetIndexOfIcon(currentIcon)
    if not selectedIndex then
        selectedIndex = 1
        currentIcon = pickerFrame:GetIconByIndex(selectedIndex)
    end

    pickerFrame.IconSelector:SetSelectionsDataProvider(
        function(selectionIndex)
            return pickerFrame:GetIconByIndex(selectionIndex)
        end,
        function()
            return pickerFrame:GetNumIcons()
        end
    )
    pickerFrame.IconSelector:SetSelectedIndex(selectedIndex)
    pickerFrame.IconSelector:ScrollToSelectedIndex()
    pickerFrame.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(currentIcon)
    pickerFrame:SetSelectedIconText()
    pickerFrame.BorderBox.OkayButton:Enable()

    pickerFrame.IconSelector:SetSelectedCallback(function(_, icon)
        pickerFrame.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(icon)
        pickerFrame:SetSelectedIconText()
    end)

    pickerFrame:Show()
    return true
end

------------------------------------------------------------------------
-- Container icon picker (per-group icon in Column 1)
------------------------------------------------------------------------
local function EnsureContainerIconPickerFrame()
    if CS.containerIconPickerFrame then
        return CS.containerIconPickerFrame
    end

    if not CreateAndInitFromMixin
        or not IconDataProviderMixin
        or not IconDataProviderExtraType
        or not IconSelectorPopupFrameTemplateMixin
        or not IconSelectorPopupFrameIconFilterTypes then
        return nil
    end

    local frame = CreateFrame("Frame", "CDCContainerIconPickerFrame", UIParent, "IconSelectorPopupFrameTemplate")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(200)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame.BorderBox.EditBoxHeaderText:Hide()
    frame.BorderBox.IconSelectorEditBox:Hide()

    -- Override strata/level: the template hardcodes IconSelector to HIGH strata
    -- and BorderBox to frameLevel 50, both below FULLSCREEN_DIALOG where CC lives.
    frame.IconSelector:SetFrameStrata("FULLSCREEN_DIALOG")
    frame.IconSelector:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.BorderBox:SetFrameLevel(frame:GetFrameLevel() + 5)
    -- Dropdown menu popup must be at TOOLTIP strata so it renders above the picker.
    -- The menu system mirrors ownerRegion strata when it is TOOLTIP (MenuManagerMixin:AcquireMenu).
    frame.BorderBox.IconTypeDropdown:SetFrameStrata("TOOLTIP")

    function frame:OnHide()
        IconSelectorPopupFrameTemplateMixin.OnHide(self)
        if self.iconDataProvider then
            self.iconDataProvider:Release()
            self.iconDataProvider = nil
        end
        self._cdcContainerId = nil
        self.IconSelector:SetSelectedCallback(nil)
    end

    function frame:OkayButton_OnClick()
        local containerId = self._cdcContainerId
        local iconTexture = self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture()
        local db = CooldownCompanion.db and CooldownCompanion.db.profile
        local container = db and db.groupContainers and db.groupContainers[containerId]
        if container and IsValidIconTexture(iconTexture) then
            container.manualIcon = iconTexture
            CooldownCompanion:RefreshConfigPanel()
        end
        IconSelectorPopupFrameTemplateMixin.OkayButton_OnClick(self)
    end

    function frame:CancelButton_OnClick()
        IconSelectorPopupFrameTemplateMixin.CancelButton_OnClick(self)
    end

    CS.containerIconPickerFrame = frame
    return frame
end

local function OpenContainerIconPicker(containerId)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local container = db and db.groupContainers and db.groupContainers[containerId]
    if not container then
        return false
    end

    local pickerFrame = EnsureContainerIconPickerFrame()
    if not pickerFrame then
        CooldownCompanion:Print("Icon picker is unavailable on this client build.")
        return false
    end

    if pickerFrame:IsShown() then
        pickerFrame:Hide()
    end

    pickerFrame._cdcContainerId = containerId
    pickerFrame.iconDataProvider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.None)
    pickerFrame:SetIconFilter(IconSelectorPopupFrameIconFilterTypes.All)

    local currentIcon = container.manualIcon
    if not IsValidIconTexture(currentIcon) then
        currentIcon = GetContainerIcon(containerId, db)
    end

    local selectedIndex = pickerFrame:GetIndexOfIcon(currentIcon)
    if not selectedIndex then
        selectedIndex = 1
        currentIcon = pickerFrame:GetIconByIndex(selectedIndex)
    end

    pickerFrame.IconSelector:SetSelectionsDataProvider(
        function(selectionIndex)
            return pickerFrame:GetIconByIndex(selectionIndex)
        end,
        function()
            return pickerFrame:GetNumIcons()
        end
    )
    pickerFrame.IconSelector:SetSelectedIndex(selectedIndex)
    pickerFrame.IconSelector:ScrollToSelectedIndex()
    pickerFrame.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(currentIcon)
    pickerFrame:SetSelectedIconText()
    pickerFrame.BorderBox.OkayButton:Enable()

    pickerFrame.IconSelector:SetSelectedCallback(function(_, icon)
        pickerFrame.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(icon)
        pickerFrame:SetSelectedIconText()
    end)

    pickerFrame:Show()
    return true
end

------------------------------------------------------------------------
-- Badge pool for group row status indicators
------------------------------------------------------------------------
local BADGE_SIZE = 24
local BADGE_SPACING = 2
local BADGE_RIGHT_PAD = 4

local function CleanRecycledEntry(entry)
    if entry._cdcModeBadge then entry._cdcModeBadge:Hide() end
    if entry.frame._cdcBadges then
        for _, b in ipairs(entry.frame._cdcBadges) do b:Hide() end
    end
    if entry.frame._cdcSpecBadges then
        for _, sb in ipairs(entry.frame._cdcSpecBadges) do sb:Hide() end
    end
    if entry.frame._cdcWarnBtn then entry.frame._cdcWarnBtn:Hide() end
    if entry.frame._cdcOverrideBadge then entry.frame._cdcOverrideBadge:Hide() end
    if entry.frame._cdcSoundBadge then entry.frame._cdcSoundBadge:Hide() end
    if entry.frame._cdcAuraBadge then entry.frame._cdcAuraBadge:Hide() end
    if entry.frame._cdcTalentBadge then entry.frame._cdcTalentBadge:Hide() end
    if entry.frame._cdcCollapseIcon then entry.frame._cdcCollapseIcon:Hide() end
    if entry.frame._cdcCollapseBtn then entry.frame._cdcCollapseBtn:Hide() end
    if entry.frame._cdcAddBtn then entry.frame._cdcAddBtn:Hide() end
    if entry.frame._cdcAnchorBadge then entry.frame._cdcAnchorBadge:Hide() end
    if entry.frame._cdcHeaderDisabledBadge then entry.frame._cdcHeaderDisabledBadge:Hide() end
    if entry.frame._cdcDisabledBadge then entry.frame._cdcDisabledBadge:Hide() end
    if entry.frame._cdcMarkerLeft then entry.frame._cdcMarkerLeft:Hide() end
    if entry.frame._cdcMarkerRight then entry.frame._cdcMarkerRight:Hide() end
    entry.frame:SetScript("OnMouseUp", nil)
    entry.frame:SetScript("OnReceiveDrag", nil)
    entry.frame._cdcOnMouseDown = nil
    entry.frame._cdcLastClickTime = nil
    if entry.image then
        entry.image:Show()
        entry.image:SetAlpha(1)
        if entry.image.SetDesaturated then
            entry.image:SetDesaturated(false)
        end
    end
end

local function AcquireBadge(frame, index)
    if not frame._cdcBadges then frame._cdcBadges = {} end
    local badge = frame._cdcBadges[index]
    if not badge then
        badge = CreateFrame("Frame", nil, frame)
        badge:SetSize(BADGE_SIZE, BADGE_SIZE)
        badge.icon = badge:CreateTexture(nil, "OVERLAY")
        badge.icon:SetAllPoints()
        badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badge.text:SetPoint("CENTER")
        badge:EnableMouse(false)
        frame._cdcBadges[index] = badge
    end
    badge.icon:SetAtlas(nil)
    badge.icon:SetTexture(nil)
    badge.icon:SetVertexColor(1, 1, 1, 1)
    badge.icon:SetTexCoord(0, 1, 0, 1)
    if badge._cdcCircleMask then
        badge.icon:RemoveMaskTexture(badge._cdcCircleMask)
    end
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge.text:SetText("")
    badge:SetFrameLevel(frame:GetFrameLevel() + 5)
    return badge
end

local function SetupGroupRowIndicators(entry, group)
    local frame = entry.frame
    if frame._cdcBadges then
        for _, b in ipairs(frame._cdcBadges) do b:Hide() end
    end

    local badgeIndex = 0
    local function AddAtlasBadge(atlas, r, g, b, a)
        badgeIndex = badgeIndex + 1
        local badge = AcquireBadge(frame, badgeIndex)
        badge.icon:SetAtlas(atlas, false)
        if r then badge.icon:SetVertexColor(r, g, b, a or 1) end
        badge:Show()
    end
    local function AddIconBadge(texture, r, g, b, a)
        badgeIndex = badgeIndex + 1
        local badge = AcquireBadge(frame, badgeIndex)
        badge.icon:SetTexture(texture)
        if r then badge.icon:SetVertexColor(r, g, b, a or 1) end
        badge:Show()
    end
    local function AddTextBadge(str)
        badgeIndex = badgeIndex + 1
        local badge = AcquireBadge(frame, badgeIndex)
        badge.text:SetText(str)
        badge:Show()
    end

    -- Disabled
    if group.enabled == false then
        AddAtlasBadge("GM-icon-visibleDis-pressed")
    end
    -- Unlocked (lock icon)
    if group.locked == false then
        AddAtlasBadge("ShipMissionIcon-Training-Map")
    end
    -- Look up folder data for per-badge filtering: badges that exist at the
    -- folder level are shown on the folder row only, not on child containers.
    local folderId = group.folderId
    local folderSpecs, folderHeroTalents
    if folderId then
        local folders = CooldownCompanion.db and CooldownCompanion.db.profile
            and CooldownCompanion.db.profile.folders
        local folder = folders and folders[folderId]
        if folder then
            folderSpecs = folder.specs
            folderHeroTalents = folder.heroTalents
        end
    end

    -- Spec filter badges: show own specs, skip any that exist at folder level
    local SPEC_BADGE_SIZE = 16
    local specs = group.specs
    if specs then
        for specId in pairs(specs) do
            if not (folderSpecs and folderSpecs[specId]) then
                local _, _, _, specIcon = GetSpecializationInfoForSpecID(specId)
                if specIcon then
                    badgeIndex = badgeIndex + 1
                    local badge = AcquireBadge(frame, badgeIndex)
                    badge:SetSize(SPEC_BADGE_SIZE, SPEC_BADGE_SIZE)
                    badge.icon:SetTexture(specIcon)
                    badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    if not badge._cdcCircleMask then
                        local mask = badge:CreateMaskTexture()
                        mask:SetAllPoints(badge.icon)
                        mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                        badge._cdcCircleMask = mask
                    end
                    badge.icon:AddMaskTexture(badge._cdcCircleMask)
                    badge:Show()
                end
            end
        end
    end

    -- Hero talent filter badges: show own, skip any that exist at folder level
    local HERO_BADGE_SIZE = SPEC_BADGE_SIZE
    local heroTalents = group.heroTalents
    if heroTalents then
        local configID = C_ClassTalents.GetActiveConfigID()
        if configID then
            for subTreeID in pairs(heroTalents) do
                if not (folderHeroTalents and folderHeroTalents[subTreeID]) then
                    local subTreeInfo = C_Traits.GetSubTreeInfo(configID, subTreeID)
                    if subTreeInfo and subTreeInfo.iconElementID then
                        badgeIndex = badgeIndex + 1
                        local badge = AcquireBadge(frame, badgeIndex)
                        badge:SetSize(HERO_BADGE_SIZE, HERO_BADGE_SIZE)
                        badge.icon:SetAtlas(subTreeInfo.iconElementID, false)
                        badge:Show()
                    end
                end
            end
        end
    end

    -- Position badges right-to-left
    local offsetX = -BADGE_RIGHT_PAD
    if frame._cdcBadges then
        for i = 1, badgeIndex do
            local badge = frame._cdcBadges[i]
            if badge:IsShown() then
                badge:ClearAllPoints()
                badge:SetPoint("RIGHT", frame, "RIGHT", offsetX, 0)
                offsetX = offsetX - badge:GetWidth() - BADGE_SPACING
            end
        end
    end
end

local function SetupFolderRowIndicators(entry, folder)
    local frame = entry.frame
    if frame._cdcBadges then
        for _, b in ipairs(frame._cdcBadges) do b:Hide() end
    end

    local badgeIndex = 0
    local SPEC_BADGE_SIZE = 16
    local specs = folder and folder.specs
    if specs and next(specs) then
        for specId in pairs(specs) do
            local _, _, _, specIcon = GetSpecializationInfoForSpecID(specId)
            if specIcon then
                badgeIndex = badgeIndex + 1
                local badge = AcquireBadge(frame, badgeIndex)
                badge:SetSize(SPEC_BADGE_SIZE, SPEC_BADGE_SIZE)
                badge.icon:SetTexture(specIcon)
                badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if not badge._cdcCircleMask then
                    local mask = badge:CreateMaskTexture()
                    mask:SetAllPoints(badge.icon)
                    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                    badge._cdcCircleMask = mask
                end
                badge.icon:AddMaskTexture(badge._cdcCircleMask)
                badge:Show()
            end
        end
    end

    local HERO_BADGE_SIZE = SPEC_BADGE_SIZE
    if folder and folder.heroTalents and next(folder.heroTalents) then
        local configID = C_ClassTalents.GetActiveConfigID()
        if configID then
            for subTreeID in pairs(folder.heroTalents) do
                local subTreeInfo = C_Traits.GetSubTreeInfo(configID, subTreeID)
                if subTreeInfo and subTreeInfo.iconElementID then
                    badgeIndex = badgeIndex + 1
                    local badge = AcquireBadge(frame, badgeIndex)
                    badge:SetSize(HERO_BADGE_SIZE, HERO_BADGE_SIZE)
                    badge.icon:SetAtlas(subTreeInfo.iconElementID, false)
                    badge:Show()
                end
            end
        end
    end

    local offsetX = -BADGE_RIGHT_PAD
    if frame._cdcBadges then
        for i = 1, badgeIndex do
            local badge = frame._cdcBadges[i]
            if badge:IsShown() then
                badge:ClearAllPoints()
                badge:SetPoint("RIGHT", frame, "RIGHT", offsetX, 0)
                offsetX = offsetX - badge:GetWidth() - BADGE_SPACING
            end
        end
    end
end

local function EnsureColumn1MarkerParts(frame)
    if not frame._cdcMarkerLeft then
        local left = frame:CreateTexture(nil, "ARTWORK")
        left:SetHeight(1)
        frame._cdcMarkerLeft = left
    end
    if not frame._cdcMarkerRight then
        local right = frame:CreateTexture(nil, "ARTWORK")
        right:SetHeight(1)
        frame._cdcMarkerRight = right
    end
end

local function ClearColumn1MarkerAppearance(target)
    local frame = target and target.frame
    if not frame then
        return
    end
    if frame._cdcMarkerLeft then
        frame._cdcMarkerLeft:Hide()
        frame._cdcMarkerLeft:ClearAllPoints()
    end
    if frame._cdcMarkerRight then
        frame._cdcMarkerRight:Hide()
        frame._cdcMarkerRight:ClearAllPoints()
    end
end

local function ApplyColumn1MarkerAppearance(target, opts)
    opts = opts or {}
    local frame = target and target.frame
    local label = target and (target.label or target._cdcLabel)
    if not (frame and label) then
        return
    end

    ClearColumn1MarkerAppearance(target)
    EnsureColumn1MarkerParts(frame)

    if frame._cdcBadges then
        for _, badge in ipairs(frame._cdcBadges) do
            badge:Hide()
        end
    end

    local text = opts.text or ""
    local color = opts.color or { 0.8, 0.8, 0.8 }
    local inset = opts.inset or 8
    local gap = opts.gap or 6
    local lineAlpha = opts.lineAlpha or 0.55
    local lineYOffset = opts.lineYOffset or 0

    label:SetText(text)
    if label.SetFontObject then
        label:SetFontObject(GameFontHighlight)
    end
    if label.SetWordWrap then
        label:SetWordWrap(false)
    end
    label:SetJustifyH("CENTER")
    label:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1)
    label:ClearAllPoints()
    label:SetPoint("CENTER", frame, "CENTER", opts.textOffsetX or 0, opts.textOffsetY or 0)
    if label.SetWidth then
        local frameWidth = frame.GetWidth and frame:GetWidth() or 0
        local desiredWidth = math.max(1, (label.GetStringWidth and label:GetStringWidth() or 0) + 2)
        if frameWidth > 0 then
            desiredWidth = math.min(desiredWidth, math.max(1, frameWidth - ((inset + gap) * 2)))
        end
        label:SetWidth(desiredWidth)
    end

    if target.image then
        target.image:Hide()
    end
    if target._cdcIcon then
        target._cdcIcon:Hide()
    end

    frame._cdcMarkerLeft:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, lineAlpha)
    frame._cdcMarkerLeft:ClearAllPoints()
    frame._cdcMarkerRight:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, lineAlpha)
    frame._cdcMarkerRight:ClearAllPoints()
    local frameWidth = frame.GetWidth and frame:GetWidth() or 0
    local textWidth = label.GetStringWidth and label:GetStringWidth() or 0
    local textOffsetX = opts.textOffsetX or 0
    if frameWidth > 0 and textWidth > 0 then
        local centerX = (frameWidth / 2) + textOffsetX
        local leftWidth = math.max(0, centerX - (textWidth / 2) - gap - inset)
        local rightStart = centerX + (textWidth / 2) + gap
        local rightWidth = math.max(0, frameWidth - inset - rightStart)

        frame._cdcMarkerLeft:SetPoint("LEFT", frame, "LEFT", inset, lineYOffset)
        frame._cdcMarkerLeft:SetWidth(leftWidth)
        frame._cdcMarkerLeft:Show()

        frame._cdcMarkerRight:SetPoint("LEFT", frame, "LEFT", rightStart, lineYOffset)
        frame._cdcMarkerRight:SetWidth(rightWidth)
        frame._cdcMarkerRight:Show()
    else
        frame._cdcMarkerLeft:SetPoint("LEFT", frame, "LEFT", inset, lineYOffset)
        frame._cdcMarkerLeft:SetPoint("RIGHT", label, "LEFT", -gap, lineYOffset)
        frame._cdcMarkerLeft:SetPoint("CENTER", frame, "CENTER", 0, lineYOffset)
        frame._cdcMarkerLeft:Show()

        frame._cdcMarkerRight:SetPoint("LEFT", label, "RIGHT", gap, lineYOffset)
        frame._cdcMarkerRight:SetPoint("RIGHT", frame, "RIGHT", -inset, lineYOffset)
        frame._cdcMarkerRight:SetPoint("CENTER", frame, "CENTER", 0, lineYOffset)
        frame._cdcMarkerRight:Show()
    end
end

local function SetupColumn1MarkerRow(widget, opts)
    if not widget then
        return
    end
    if not widget._cdcMarkerWidthHooked then
        local previousOnWidthSet = widget.OnWidthSet
        widget.OnWidthSet = function(self, width)
            if previousOnWidthSet then
                previousOnWidthSet(self, width)
            end
            if self._cdcMarkerOpts then
                ApplyColumn1MarkerAppearance(self, self._cdcMarkerOpts)
            end
        end
        widget._cdcMarkerWidthHooked = true
    end
    if not widget._cdcMarkerReleaseHooked then
        local previousOnRelease = widget.OnRelease
        widget.OnRelease = function(self, ...)
            self._cdcMarkerOpts = nil
            ClearColumn1MarkerAppearance(self)
            if previousOnRelease then
                previousOnRelease(self, ...)
            end
        end
        widget._cdcMarkerReleaseHooked = true
    end
    if widget.SetFullWidth then
        widget:SetFullWidth(true)
    end
    if widget.SetHeight then
        widget:SetHeight((opts and opts.height) or 18)
    elseif widget.frame and widget.frame.SetHeight then
        widget.frame:SetHeight((opts and opts.height) or 18)
    end
    if widget.SetText then
        widget:SetText((opts and opts.text) or "")
    end
    widget._cdcMarkerOpts = opts
    ApplyColumn1MarkerAppearance(widget, opts)
end

------------------------------------------------------------------------
-- Helper: Create a scroll frame inside a parent
------------------------------------------------------------------------
local function CreateScrollFrame(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1) -- will be set dynamically
    scrollFrame:SetScrollChild(scrollChild)

    -- Update child width on resize
    scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        scrollChild:SetWidth(w)
    end)

    return scrollFrame, scrollChild
end

------------------------------------------------------------------------
-- Helper: Create a text button
------------------------------------------------------------------------
local function CreateTextButton(parent, text, width, height, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)

    btn:RegisterForClicks("AnyUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and onClick then
            onClick(self)
        end
    end)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.3, 0.3, 0.9)
    end)
    btn:SetScript("OnLeave", function(self)
        if self.isSelected then
            self:SetBackdropColor(0.15, 0.4, 0.15, 0.9)
        else
            self:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
        end
    end)

    return btn
end

------------------------------------------------------------------------
-- Shared helper: persistent overlay host for column drag/drop previews
------------------------------------------------------------------------
local function EnsureColumnPreviewHost(previewKey, scrollWidget)
    local preview = CS[previewKey]
    if not preview then
        preview = {
            rows = {},
            panels = {},
            hiddenFrames = {},
            hiddenRegions = {},
            tweens = {},
        }
        CS[previewKey] = preview
    end

    if not preview.root then
        local root = CreateFrame("Frame", nil, UIParent)
        root:SetFrameStrata("FULLSCREEN_DIALOG")
        root:EnableMouse(false)
        root:SetClipsChildren(false)
        root:Hide()
        preview.root = root
    end

    if not preview.ghost then
        local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        ghost:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        ghost:SetBackdropColor(0.10, 0.115, 0.16, 0.92)
        ghost:SetBackdropBorderColor(0.24, 0.27, 0.33, 1)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:EnableMouse(false)
        ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
        ghost.icon:SetSize(24, 24)
        ghost.icon:SetPoint("LEFT", ghost, "LEFT", 8, 0)
        ghost.label = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ghost.label:SetPoint("LEFT", ghost.icon, "RIGHT", 8, 0)
        ghost.label:SetPoint("RIGHT", ghost, "RIGHT", -8, 0)
        ghost.label:SetJustifyH("LEFT")
        ghost:Hide()
        preview.ghost = ghost
    end

    local content = scrollWidget and scrollWidget.content
    if content then
        preview.root:SetParent(content)
        preview.root:ClearAllPoints()
        preview.root:SetAllPoints(content)
        preview.root:SetFrameLevel((content:GetFrameLevel() or 1) + 100)
    else
        preview.root:SetParent(UIParent)
    end

    return preview
end

local function ClearColumnPreviewHost(previewKey)
    local preview = CS[previewKey]
    if not preview then
        return
    end

    if preview.hiddenFrames then
        for frame, alpha in pairs(preview.hiddenFrames) do
            if frame and frame.SetAlpha then
                frame:SetAlpha(alpha)
            end
            preview.hiddenFrames[frame] = nil
        end
    end

    if preview.hiddenRegions then
        for region, alpha in pairs(preview.hiddenRegions) do
            if region and region.SetAlpha then
                region:SetAlpha(alpha)
            end
            preview.hiddenRegions[region] = nil
        end
    end

    if preview.rows then
        for _, row in ipairs(preview.rows) do
            if row.frame then
                row.frame:Hide()
            end
        end
    end

    if preview.panels then
        for _, panel in ipairs(preview.panels) do
            if panel.frame then
                panel.frame:Hide()
            end
        end
    end

    if preview.tweens then
        for frame in pairs(preview.tweens) do
            preview.tweens[frame] = nil
        end
    end

    if preview.root then
        preview.root:Hide()
        preview.root:SetScript("OnUpdate", nil)
    end

    if preview.ghost then
        preview.ghost:Hide()
    end

    preview.ghostActive = false
    preview.mode = nil
    preview.compactEntries = nil
end

local function EnsureCol1PreviewHost()
    return EnsureColumnPreviewHost("col1Preview", CS.col1Scroll)
end

local function EnsureCol2PreviewHost()
    return EnsureColumnPreviewHost("col2Preview", CS.col2Scroll)
end

local function ClearCol1PreviewHost()
    ClearColumnPreviewHost("col1Preview")
end

local function ClearCol2PreviewHost()
    ClearColumnPreviewHost("col2Preview")
end

------------------------------------------------------------------------
-- Helper: Embed an AceGUI widget into a raw frame
------------------------------------------------------------------------
local function EmbedWidget(widget, parent, x, y, width, widgetList)
    widget.frame:SetParent(parent)
    widget.frame:ClearAllPoints()
    widget.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then widget:SetWidth(width) end
    widget.frame:Show()
    if widgetList then
        table.insert(widgetList, widget)
    end
    return widget
end

------------------------------------------------------------------------
-- Shared helper: render hero talent sub-tree checkboxes for a given spec.
-- Used by both Column1 (group filter inline panel) and ButtonConditions (load conditions tab).
------------------------------------------------------------------------
local function ApplyCheckboxIndent(checkbox, offsetX)
    if not (checkbox and checkbox.checkbg) then return end
    -- AceGUI checkboxes are pooled; normalize anchor state before applying offset.
    checkbox.checkbg:ClearAllPoints()
    checkbox.checkbg:SetPoint("TOPLEFT", offsetX or 0, 0)
end

local function BuildHeroTalentSubTreeCheckboxes(container, group, configID, specId, indentOffset, groupId, opts)
    opts = opts or {}
    local specsSource = opts.specsSource or group.specs
    local useHeroTalentsSource = opts.useHeroTalentsSource and true or false
    local heroTalentsSource
    if useHeroTalentsSource then
        heroTalentsSource = opts.heroTalentsSource
    else
        heroTalentsSource = opts.heroTalentsSource or group.heroTalents
    end
    local disableToggles = opts.disableToggles and true or false

    local created = {}
    if not (specsSource and specsSource[specId] and configID) then return created end
    local subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specId)
    if not subTreeIDs then return created end
    for _, subTreeID in ipairs(subTreeIDs) do
        local subTreeInfo = C_Traits.GetSubTreeInfo(configID, subTreeID)
        if subTreeInfo then
            local htCb = AceGUI:Create("CheckBox")
            htCb:SetLabel(subTreeInfo.name or ("Hero " .. subTreeID))
            htCb:SetFullWidth(true)
            htCb:SetValue(heroTalentsSource and heroTalentsSource[subTreeID] or false)
            if disableToggles then
                htCb:SetDisabled(true)
            else
                htCb:SetCallback("OnValueChanged", function(widget, event, value)
                    if value then
                        if not group.heroTalents then group.heroTalents = {} end
                        group.heroTalents[subTreeID] = true
                    else
                        if group.heroTalents then
                            group.heroTalents[subTreeID] = nil
                            if not next(group.heroTalents) then
                                group.heroTalents = nil
                            end
                        end
                    end
                    if opts.onChanged then
                        opts.onChanged()
                    else
                        CooldownCompanion:RefreshGroupFrame(groupId)
                        CooldownCompanion:RefreshConfigPanel()
                    end
                end)
            end
            container:AddChild(htCb)
            created[#created + 1] = htCb
            ApplyCheckboxIndent(htCb, indentOffset)
            if subTreeInfo.iconElementID then
                htCb:SetImage(136235)
                htCb.image:SetAtlas(subTreeInfo.iconElementID, false)
                htCb.image:SetTexCoord(0, 1, 0, 1)
            end
        end
    end
    return created
end

------------------------------------------------------------------------
-- Shared selection / spec helpers (consumed by Popups, Panel, Column*, DragReorder)
------------------------------------------------------------------------

local function ResetConfigSelection(full)
    if full and ST._CancelAutoAddFlow then
        ST._CancelAutoAddFlow()
    end
    CS.selectedButton = nil
    wipe(CS.selectedButtons)
    wipe(CS.selectedPanels)
    if full then
        CS.selectedContainer = nil
        CS.selectedGroup = nil
        wipe(CS.selectedGroups)
        CS.addingToPanelId = nil
        -- Exit browse mode on full reset
        CS.browseMode = false
        CS.browseCharKey = nil
        CS.browseContainerId = nil
    end
end

local function SetConfigPrimaryMode(mode, opts)
    local toBars
    if mode == "bars" then
        toBars = true
    elseif mode == "buttons" then
        toBars = false
    else
        return false
    end

    local wasBars = CS.resourceBarPanelActive == true
    if toBars and not wasBars then
        -- Preserve existing behavior when entering Bars & Frames mode.
        ResetConfigSelection(true)
    elseif (not toBars) and wasBars then
        -- Stop preview loops when returning to button settings mode.
        CooldownCompanion:StopCastBarPreview()
        CooldownCompanion:StopResourceBarPreview()
    end

    CS.resourceBarPanelActive = toBars
    if not (opts and opts.skipRefresh) and CS.configFrame and CS.configFrame.frame and CS.configFrame.frame:IsShown() then
        CooldownCompanion:RefreshConfigPanel()
    end
    return true
end

local function BuildPlayerSpecSet()
    local playerSpecIds = {}
    local numSpecs = GetNumSpecializations()
    for i = 1, numSpecs do
        local specId = C_SpecializationInfo.GetSpecializationInfo(i)
        if specId then
            playerSpecIds[specId] = true
        end
    end
    return playerSpecIds
end

local function SpecSetHasForeignSpecs(specs, playerSpecIds)
    if not specs then return false end
    for specId in pairs(specs) do
        if not playerSpecIds[specId] then
            return true
        end
    end
    return false
end

local function GetEffectiveContainerSpecFilter(container, db)
    if not container then return nil end
    return container.specs
end

local function ContainersHaveForeignSpecs(containers, requireGlobal)
    local playerSpecIds = BuildPlayerSpecSet()
    for _, c in ipairs(containers) do
        if not requireGlobal or c.isGlobal then
            local effectiveSpecs = GetEffectiveContainerSpecFilter(c)
            if SpecSetHasForeignSpecs(effectiveSpecs, playerSpecIds) then
                return true
            end
        end
    end
    return false
end

-- Legacy compat: used by folder-level checks
local function GetEffectiveGroupSpecFilter(group, db)
    if not group then return nil end
    if group.folderId and db and db.folders then
        local folder = db.folders[group.folderId]
        if folder and folder.specs and next(folder.specs) then
            return folder.specs
        end
    end
    return group.specs
end

local function GroupsHaveForeignSpecs(groups, requireGlobal)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local playerSpecIds = BuildPlayerSpecSet()
    for _, g in ipairs(groups) do
        if not requireGlobal or g.isGlobal then
            local effectiveSpecs = GetEffectiveGroupSpecFilter(g, db)
            if SpecSetHasForeignSpecs(effectiveSpecs, playerSpecIds) then
                return true
            end
        end
    end
    return false
end

local function FolderHasForeignSpecs(folderId)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if not (db and db.folders) then return false end

    local folder = db.folders[folderId]
    if not folder then return false end

    local playerSpecIds = BuildPlayerSpecSet()
    -- Post-migration: specs live on containers, not folders
    local containers = db.groupContainers
    if containers then
        for _, container in pairs(containers) do
            if container.folderId == folderId then
                if SpecSetHasForeignSpecs(container.specs, playerSpecIds) then
                    return true
                end
            end
        end
    end

    return false
end

------------------------------------------------------------------------
-- CompactUntitledInlineGroupConfig (shared utility for bordered panels)
------------------------------------------------------------------------
local function CompactUntitledInlineGroupConfig(group)
    local frame = group and group.frame
    local content = group and group.content
    local border = content and content:GetParent()
    local titleText = group and group.titletext
    if not frame or not content or not border or not titleText then
        return
    end

    local originalLayoutFinished = group.LayoutFinished

    titleText:Hide()
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetPoint("BOTTOMRIGHT", -1, 3)
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", 10, -6)
    content:SetPoint("BOTTOMRIGHT", -10, 6)
    group.LayoutFinished = function(self, width, height)
        if self.noAutoHeight then
            return
        end
        self:SetHeight((height or 0) + 15)
    end

    group:SetCallback("OnRelease", function(widget)
        local releaseTitle = widget and widget.titletext
        local releaseContent = widget and widget.content
        local releaseBorder = releaseContent and releaseContent:GetParent()
        if not releaseTitle or not releaseContent or not releaseBorder then
            return
        end

        releaseTitle:Show()
        releaseBorder:ClearAllPoints()
        releaseBorder:SetPoint("TOPLEFT", 0, -17)
        releaseBorder:SetPoint("BOTTOMRIGHT", -1, 3)
        releaseContent:ClearAllPoints()
        releaseContent:SetPoint("TOPLEFT", 10, -10)
        releaseContent:SetPoint("BOTTOMRIGHT", -10, 10)
        widget.LayoutFinished = originalLayoutFinished
    end)
end

------------------------------------------------------------------------
-- ST._ exports (consumed by later Config/ files at load time)
------------------------------------------------------------------------
CS.SetConfigPrimaryMode = SetConfigPrimaryMode
ST._CompactUntitledInlineGroupConfig = CompactUntitledInlineGroupConfig
ST._CDM_VIEWER_NAMES = CDM_VIEWER_NAMES
ST._CleanRecycledEntry = CleanRecycledEntry
ST._AcquireBadge = AcquireBadge
ST._SetupGroupRowIndicators = SetupGroupRowIndicators
ST._SetupFolderRowIndicators = SetupFolderRowIndicators
ST._ApplyColumn1MarkerAppearance = ApplyColumn1MarkerAppearance
ST._SetupColumn1MarkerRow = SetupColumn1MarkerRow
ST._CreateScrollFrame = CreateScrollFrame
ST._CreateTextButton = CreateTextButton
ST._EnsureCol1PreviewHost = EnsureCol1PreviewHost
ST._EnsureCol2PreviewHost = EnsureCol2PreviewHost
ST._ClearCol1PreviewHost = ClearCol1PreviewHost
ST._ClearCol2PreviewHost = ClearCol2PreviewHost
ST._EmbedWidget = EmbedWidget
ST._GetButtonIcon = GetButtonIcon
ST._GetGroupIcon = GetGroupIcon
ST._GetContainerIcon = GetContainerIcon
ST._GetFolderIcon = GetFolderIcon
ST._OpenFolderIconPicker = OpenFolderIconPicker
ST._OpenButtonIconPicker = OpenButtonIconPicker
ST._OpenContainerIconPicker = OpenContainerIconPicker
ST._IsValidIconTexture = IsValidIconTexture
ST._GenerateFolderName = GenerateFolderName
ST._ShowPopupAboveConfig = ShowPopupAboveConfig
ST._COLUMN_PADDING = COLUMN_PADDING
ST._BUTTON_HEIGHT = BUTTON_HEIGHT
ST._BUTTON_SPACING = BUTTON_SPACING
ST._PROFILE_BAR_HEIGHT = PROFILE_BAR_HEIGHT
ST._BuildHeroTalentSubTreeCheckboxes = BuildHeroTalentSubTreeCheckboxes
ST._ApplyCheckboxIndent = ApplyCheckboxIndent
ST._ResetConfigSelection = ResetConfigSelection
ST._SetConfigPrimaryMode = SetConfigPrimaryMode
ST._GroupsHaveForeignSpecs = GroupsHaveForeignSpecs
ST._ContainersHaveForeignSpecs = ContainersHaveForeignSpecs
ST._FolderHasForeignSpecs = FolderHasForeignSpecs

------------------------------------------------------------------------
-- Helper: Recursively disable all interactive AceGUI widgets
------------------------------------------------------------------------
local function DisableAllWidgets(container)
    if container.children then
        for _, child in ipairs(container.children) do
            if child.SetDisabled then child:SetDisabled(true) end
            DisableAllWidgets(child)
        end
    end
end

------------------------------------------------------------------------
-- Helper: Get class-colored text for current player
------------------------------------------------------------------------
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
ST._GetClassColoredText = GetClassColoredText

ST._DisableAllWidgets = DisableAllWidgets
