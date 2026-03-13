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

-- Font options for dropdown (LSM-backed, returns fresh table each call)
local function GetFontOptions()
    local t = {}
    for _, name in ipairs(LSM:List("font")) do
        t[name] = name
    end
    return t
end

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
    chargeText = "Charge Text",
    procGlow = "Proc Glow",
    assistedHighlight = "Assisted Highlight",
}
local strataElementKeys = {"cooldown", "chargeText", "procGlow", "assistedHighlight"}

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
    panelContextMenu = nil,

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
    resourceAuraOverlayDrafts = {},
    characterScopedCopySelection = {
        resourceBars = nil,
        castBar = nil,
        frameAnchoring = nil,
    },
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
}
local CS = ST._configState

------------------------------------------------------------------------
-- Strata order helpers
------------------------------------------------------------------------
local function IsStrataOrderComplete(order)
    if not order then return false end
    for i = 1, 4 do
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
        for i = 1, 4 do
            CS.pendingStrataOrder[i] = saved[i]
        end
    else
        CS.pendingStrataOrder = {}
        for i = 1, 4 do
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
-- Helper: Get icon for a container (from its first panel's first button)
------------------------------------------------------------------------
local function GetContainerIcon(containerId, db)
    if not db or not db.groups then return 134400 end
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
local function IsValidIconTexture(iconTexture)
    local iconType = type(iconTexture)
    return iconType == "number" or iconType == "string"
end

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
                table.insert(children, { id = cid, order = container.order or cid })
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
    if entry.frame._cdcWarnBtn then entry.frame._cdcWarnBtn:Hide() end
    if entry.frame._cdcOverrideBadge then entry.frame._cdcOverrideBadge:Hide() end
    if entry.frame._cdcSoundBadge then entry.frame._cdcSoundBadge:Hide() end
    if entry.frame._cdcAuraBadge then entry.frame._cdcAuraBadge:Hide() end
    if entry.frame._cdcTalentBadge then entry.frame._cdcTalentBadge:Hide() end
    if entry.frame._cdcCollapseIcon then entry.frame._cdcCollapseIcon:Hide() end
    if entry.frame._cdcCollapseBtn then entry.frame._cdcCollapseBtn:Hide() end
    if entry.frame._cdcAddBtn then entry.frame._cdcAddBtn:Hide() end
    if entry.frame._cdcAnchorBadge then entry.frame._cdcAnchorBadge:Hide() end
    if entry.frame._cdcDisabledBadge then entry.frame._cdcDisabledBadge:Hide() end
    entry.frame:SetScript("OnMouseUp", nil)
    entry.frame:SetScript("OnReceiveDrag", nil)
    entry.frame._cdcOnMouseDown = nil
    entry.frame._cdcLastClickTime = nil
    entry.image:SetAlpha(1)
    if entry.image and entry.image.SetDesaturated then
        entry.image:SetDesaturated(false)
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

    if not (specsSource and specsSource[specId] and configID) then return end
    local subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specId)
    if not subTreeIDs then return end
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
                    CooldownCompanion:RefreshGroupFrame(groupId)
                    CooldownCompanion:RefreshConfigPanel()
                end)
            end
            container:AddChild(htCb)
            ApplyCheckboxIndent(htCb, indentOffset)
            if subTreeInfo.iconElementID then
                htCb:SetImage(136235)
                htCb.image:SetAtlas(subTreeInfo.iconElementID, false)
                htCb.image:SetTexCoord(0, 1, 0, 1)
            end
        end
    end
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
ST._CreateScrollFrame = CreateScrollFrame
ST._CreateTextButton = CreateTextButton
ST._EmbedWidget = EmbedWidget
ST._GetButtonIcon = GetButtonIcon
ST._GetGroupIcon = GetGroupIcon
ST._GetContainerIcon = GetContainerIcon
ST._GetFolderIcon = GetFolderIcon
ST._OpenFolderIconPicker = OpenFolderIconPicker
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
ST._DisableAllWidgets = DisableAllWidgets
