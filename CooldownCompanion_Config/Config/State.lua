--[[
    CooldownCompanion - Config/State
    Shared mutable state, constants, core helpers, and UI building blocks.
    All cross-file state lives in ST._configState (aliased as CS).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local ResolveViewerChildForSpellDisplay = ST.ResolveViewerChildForSpellDisplay

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

local outlineOptions = {
    [""] = "None",
    ["OUTLINE"] = "Outline",
    ["OUTLINE, SLUG"] = "Outline + Slug",
    ["THICKOUTLINE"] = "Thick Outline",
    ["MONOCHROME"] = "Monochrome",
}

local function IsFontControlLocked(opts)
    return ST.IsFontPickerLocked and ST.IsFontPickerLocked() and not (opts and opts.ignoreProfileWideFontLock)
end

local function GetBarTextureOptions()
    local t = {}
    for _, name in ipairs(LSM:List("statusbar")) do
        t[name] = name
    end
    return t
end

local function IsBarTextureControlLocked(opts)
    return ST.IsBarTexturePickerLocked and ST.IsBarTexturePickerLocked() and not (opts and opts.ignoreProfileWideBarTextureLock)
end

local function SetLockedDropdownCallback(dropdown, callback, isLocked, opts)
    dropdown:SetCallback("OnValueChanged", function(widget, event, val, checked)
        if isLocked(opts) then
            return
        end
        callback(widget, event, val, checked)
    end)
end

-- Sets up a font dropdown with correct name→name list and per-item font preview.
local function SetupFontDropdown(dropdown, opts)
    dropdown:SetList(GetFontOptions())
    if dropdown.SetDisabled then
        dropdown:SetDisabled(IsFontControlLocked(opts))
    end
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

local function SetFontDropdownCallback(dropdown, callback, opts)
    SetLockedDropdownCallback(dropdown, callback, IsFontControlLocked, opts)
end

local function SetupFontOutlineDropdown(dropdown, opts)
    dropdown:SetList(outlineOptions)
    if dropdown.SetDisabled then
        dropdown:SetDisabled(IsFontControlLocked(opts))
    end
end

local function SetFontOutlineDropdownCallback(dropdown, callback, opts)
    SetLockedDropdownCallback(dropdown, callback, IsFontControlLocked, opts)
end

local function GetProfileWideFontPickerValue()
    local name = ST.GetProfileWideFontName and ST.GetProfileWideFontName()
    if name and (not LSM.IsValid or LSM:IsValid("font", name)) then
        return name
    end
    return ST.DEFAULT_FONT_NAME or "Friz Quadrata TT"
end

local function GetProfileWideFontOutlinePickerValue()
    local outline = ST.GetProfileWideFontOutline and ST.GetProfileWideFontOutline()
    if type(outline) == "string" then
        return ST.NormalizeFontOutline(outline)
    end
    return ST.DEFAULT_FONT_OUTLINE or "OUTLINE"
end

local function SetupBarTextureDropdown(dropdown, opts)
    opts = opts or {}
    dropdown:SetList(opts.list or GetBarTextureOptions(), opts.order)
    if dropdown.SetDisabled then
        dropdown:SetDisabled(IsBarTextureControlLocked(opts))
    end
end

local function SetBarTextureDropdownCallback(dropdown, callback, opts)
    SetLockedDropdownCallback(dropdown, callback, IsBarTextureControlLocked, opts)
end

local function GetProfileWideBarTexturePickerValue()
    local name = ST.GetProfileWideBarTextureName and ST.GetProfileWideBarTextureName()
    if name and (not LSM.IsValid or LSM:IsValid("statusbar", name)) then
        return name
    end
    return "Solid"
end

-- Strata ordering element definitions
-- Dropdown labels. Order below matches ST.DEFAULT_STRATA_ORDER (lowest first);
-- the section renders the stack top-down, so the list order is presentational
-- only. "Aura Display" is the whole Blizzard slot subtree — aura glow,
-- pandemic glow, aura duration swipe and aura text move together, because CC
-- cannot reorder inside it.
local strataElementLabels = {
    iconFill = "Icon Fill Timer",
    cooldown = "Cooldown Swipe",
    readyGlow = "Ready Glow",
    keyPressHighlight = "Key Press Highlight",
    chargeText = "Text Overlay",
    assistedHighlight = "Assisted Highlight",
    procGlow = "Proc Glow",
    auraDisplay = "Aura Display",
}
local strataElementKeys = {
    "iconFill", "cooldown", "readyGlow", "keyPressHighlight",
    "chargeText", "assistedHighlight", "procGlow", "auraDisplay",
}

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

------------------------------------------------------------------------
-- Shared config state table
------------------------------------------------------------------------
ST._configState = {
    -- Selection state
    initialContainerSelectionAttempted = false, -- Once per login/reload; not reset with selection
    selectedContainer = nil,     -- Group container selected in the Navigator
    selectedGroup = nil,         -- Panel selected in the Navigator
    selectedButton = nil,
    selectedRotationAssistantEntry = nil,
    selectedButtons = {},
    selectedPanels = {},         -- multi-selected panel IDs (within a container)
    selectedGroups = {},         -- multi-selected container IDs
    selectedCustomBars = {},     -- multi-selected custom bar IDs
    selectedResourcePowerType = nil,
    resourceSettingsSpecID = nil,
    selectedTab = "appearance",
    selectedContainerTab = "general",
    buttonSettingsTab = "settings",
    panelSettingsTab = "appearance",
    -- Whether `selectedTab` above is an explicit choice — a tab the user
    -- clicked, or one a route deliberately sent them to — rather than the
    -- shipped default. Until it is, a text panel lands on its Format tab
    -- instead of honoring it. Set beside every deliberate assignment of
    -- selectedTab; the panel tab callback sets it for clicks.
    panelSettingsTabExplicit = false,
    -- Which half of the unified tab row owns the settings surface while a
    -- detail cluster (entry, entry multi-select, attached bar, resource) is
    -- in it: "detail" (the default - selecting one zooms into it) or
    -- "primary" (a panel or module tab was opened without dropping that
    -- selection).
    unifiedRowScope = "detail",
    newInput = "",
    tutorialAnchors = {},
    tutorialFrame = nil,
    tutorialHighlight = nil,
    tutorialArrow = nil,
    tutorialRuntime = nil,
    tutorialButton = nil,

    -- Main frame reference
    configFrame = nil,

    -- Column content frames
    col1Scroll = nil,
    col1DestinationBar = nil,
    col1ButtonBar = nil,
    -- Group-settings scroll inside the active workspace host. The legacy
    -- name remains internal so existing builders do not need a broad rename.
    col4Scroll = nil,

    -- The group id the inline texture browser is open for (nil = closed). Set
    -- by AuraTexturePicker; drives the takeover branch in ButtonsWideColumn.
    inlineTextureBrowserOpen = nil,
    -- Config-only texture appearance values staged during slider/color edits.
    -- ButtonPanelPreview consumes them; runtime reads only the saved settings.
    textureConfigPreviewStage = nil,

    -- AceGUI widget tracking for cleanup
    col1BarWidgets = {},
    profileBarAceWidgets = {},
    buttonSettingsInfoButtons = {},

    buttonSettingsScroll = nil,
    columnInfoButtons = {},
    moveMenuFrame = nil,
    groupContextMenu = nil,
    buttonContextMenu = nil,
    customBarContextMenu = nil,
    gearDropdownFrame = nil,
    profileWideFontWindow = nil,
    profileWideBarTextureWindow = nil,
    buttonIconPickerFrame = nil,
    triggerPanelIconPickerFrame = nil,
    containerIconPickerFrame = nil,
    panelContextMenu = nil,
    charCopyMenu = nil,

    -- Drag-reorder state
    dragState = nil,
    dragIndicator = nil,
    dragTracker = nil,
    showPhantomSections = false,
    lastCol1RenderedRows = nil,

    -- Pending strata order state
    pendingStrataOrder = nil,
    pendingStrataGroup = nil,

    -- One-shot navigated-setting highlight request: written by the gear /
    -- Customizations navigation writers (PreviewCommandCenter), matched by
    -- the section and advanced-gear builders during the rebuild, consumed by
    -- the deferred scroll-and-pulse fire (ConfigSettings/Helpers.lua).
    pendingSettingHighlight = nil,
    -- One-shot semantic scroll handoff between the Panel and Entry lenses.
    -- Helpers.lua owns both the active heading registry and the pending anchor.
    lensAnchorRegistry = nil,
    pendingLensAnchor = nil,

    -- Collapsed sections state
    collapsedSections = {},
    collapsedPanels = {},
    expandedContainer = nil,
    peekedContainers = {},
    springOpenContainer = nil,
    configFinderExpansionSnapshot = nil,
    configFinderNavigated = nil,
    configFinderRestoredCollapsedContainerId = nil,
    pendingConfigFinderEntryScrollReset = nil,
    otherClassLibraryActive = false,
    otherClassLibraryClassKey = nil,
    otherClassLibrarySnapshot = nil,
    panelClickTimes = {},
    addingToPanelId = nil,
    _panelDropTargets = {},

    -- Talent picker mode (2-column layout)
    talentPickerMode = false,

    -- Autocomplete state
    autocompleteCache = nil,
    pendingEditBoxFocus = false,
    pendingWideAddFocus = false,

    -- Config finder state
    configSearchText = "",
    configFinderBox = nil,
    configFinderSuppressTextChanged = false,
    compactConfigRows = false,

    configShiftTooltipActive = nil,

    -- Tab UI state (populated by ConfigSettings, cleaned by both files)
    tabInfoButtons = {},
    customBarInfoButtons = {},
    appearanceTabElements = {},
    selectedCustomBarId = nil,
    customBarSpecExpandedId = nil,
    -- A standalone bar destination in the panel inventory
    barsEntrySelected = false,
    barWorkspaceKind = nil,
    -- Which cast/frames object that workspace is editing
    -- ("castbar" | "player" | "target"); nil is the Resources home, where a
    -- resource or a custom bar can be selected instead
    castFramesSelectedItem = nil,
    -- Buttons view, unified anchor preview: which attached bar's settings
    -- own the settings area ("resource" | "custom" | "cast", nil = none).
    -- The matching id lives in selectedResourcePowerType/selectedCustomBarId.
    unifiedBarKind = nil,
    resourcesSettingsTab = "general",
    -- Copy Panel Settings mode (CopyPanelSettingsMode.lua):
    -- { sourceGroupId, scope, lastAppliedText } while armed, nil otherwise.
    copyPanelSettings = nil,
    -- The mode's Navigator banner frame, created on first arm.
    copyPanelSettingsBanner = nil,

    -- Static lookup tables
    fontOptions = GetFontOptions,
    SetupFontDropdown = SetupFontDropdown,
    SetFontDropdownCallback = SetFontDropdownCallback,
    SetupFontOutlineDropdown = SetupFontOutlineDropdown,
    SetFontOutlineDropdownCallback = SetFontOutlineDropdownCallback,
    GetProfileWideFontPickerValue = GetProfileWideFontPickerValue,
    GetProfileWideFontOutlinePickerValue = GetProfileWideFontOutlinePickerValue,
    SetupBarTextureDropdown = SetupBarTextureDropdown,
    SetBarTextureDropdownCallback = SetBarTextureDropdownCallback,
    GetProfileWideBarTexturePickerValue = GetProfileWideBarTexturePickerValue,
    outlineOptions = outlineOptions,
    strataElementLabels = strataElementLabels,
    strataElementKeys = strataElementKeys,
    anchorPoints = anchorPoints,
    anchorPointLabels = anchorPointLabels,
    anchorDropdownList = anchorDropdownList,

    -- CS.* function forward declarations (set by later files)
    IsStrataOrderComplete = nil,
    InitPendingStrataOrder = nil,
    StartPickFrame = nil,
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
        dialog:SetFrameStrata("TOOLTIP")
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
    elseif CooldownCompanion.IsEquipmentSlotEntry
        and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        local effectiveItem = CooldownCompanion.ResolveEffectiveItem
            and CooldownCompanion.ResolveEffectiveItem(buttonData, true) or nil
        if effectiveItem and effectiveItem.trackable and effectiveItem.icon then
            return effectiveItem.icon
        end
        return 134400
    elseif buttonData.type == "item" then
        return C_Item.GetItemIconByID(buttonData.id) or 134400
    end
    return 134400
end

local function GetCooldownInfoDisplaySpellID(cooldownInfo)
    if type(cooldownInfo) ~= "table" then
        return nil
    end

    local tooltipID = cooldownInfo.overrideTooltipSpellID
    if type(tooltipID) == "number" and tooltipID > 0
        and not (issecretvalue and issecretvalue(tooltipID))
    then
        return tooltipID
    end

    local overrideID = cooldownInfo.overrideSpellID
    if type(overrideID) == "number" and overrideID > 0
        and not (issecretvalue and issecretvalue(overrideID))
    then
        return overrideID
    end

    local spellID = cooldownInfo.spellID
    if type(spellID) == "number" and spellID > 0
        and not (issecretvalue and issecretvalue(spellID))
    then
        return spellID
    end

    return nil
end

local function GetConfigEntryDisplayName(buttonData, opts)
    if not buttonData then
        return nil
    end

    opts = opts or {}
    local includeDecorations = opts.includeDecorations == true
    local isEquipmentSlot = CooldownCompanion.IsEquipmentSlotEntry
        and CooldownCompanion.IsEquipmentSlotEntry(buttonData)
    local entryName = isEquipmentSlot
        and (CooldownCompanion.GetEquipmentSlotDisplayName
            and CooldownCompanion.GetEquipmentSlotDisplayName(buttonData) or buttonData.name)
        or buttonData.customName or buttonData.name

    if isEquipmentSlot then
        entryName = entryName or ("Unknown " .. tostring(buttonData.type))
    elseif buttonData.type == "spell" then
        local child = ResolveViewerChildForSpellDisplay(CooldownCompanion, buttonData)

        if not buttonData.customName then
            local displayId = GetCooldownInfoDisplaySpellID(child and child.cooldownInfo)
            if not displayId then
                local raw = C_Spell.GetOverrideSpell(buttonData.id)
                displayId = (raw and raw ~= 0) and raw or buttonData.id
            end
            if displayId then
                local spellName = C_Spell.GetSpellName(displayId)
                if spellName then
                    entryName = spellName
                end
            end
        end

        if buttonData.cdmChildSlot then
            entryName = (entryName or ("Unknown " .. tostring(buttonData.type))) .. " #" .. buttonData.cdmChildSlot
        end

        if includeDecorations then
            local addedAs = buttonData.addedAs
            if addedAs ~= "spell" and addedAs ~= "aura" then
                addedAs = buttonData.isPassive and "aura" or "spell"
            end
            entryName = (entryName or ("Unknown " .. tostring(buttonData.type)))
                .. " |cff7d7566(" .. (addedAs == "aura" and "Aura" or "Spell") .. ")|r"
        end
    elseif buttonData.type == "item" and includeDecorations then
        entryName = entryName or ("Unknown " .. tostring(buttonData.type))
        if C_Item.IsEquippableItem(buttonData.id) then
            entryName = entryName .. " |cff7d7566(Equipment)|r"
        else
            entryName = entryName .. " |cff7d7566(Item)|r"
        end
    end

    return entryName
end

local function NormalizeConfigFinderText(text)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
        :gsub("|A:.-|a", "")
        :gsub("^%s*(.-)%s*$", "%1")
    return strlower(text)
end

-- The Global section's identity colour. Shared so the Navigator heading and the
-- drag insertion line cannot drift apart: consumed by Column1's RenderSection
-- call and by DragReorderTargets' GetCol1SectionColor.
ST._COL1_GLOBAL_SECTION_COLOR = { 0.4, 0.67, 1.0 }

local CONFIG_FINDER_MIN_QUERY_LENGTH = 2
local CONFIG_FINDER_MAX_PANEL_RESULTS = 80
local CONFIG_FINDER_MAX_ENTRY_RESULTS = 200

local function IsConfigFinderQueryUsable(text)
    return #NormalizeConfigFinderText(text) >= CONFIG_FINDER_MIN_QUERY_LENGTH
end

local function ConfigFinderSearchTextMatches(searchText, query)
    return type(searchText) == "string"
        and query
        and query ~= ""
        and searchText:find(query, 1, true) ~= nil
end

local function GetConfigFinderEntryDisplaySearchText(entryRecord)
    if not entryRecord then
        return ""
    end
    if entryRecord.displaySearchText == nil then
        entryRecord.displaySearchText = NormalizeConfigFinderText(GetConfigEntryDisplayName(entryRecord.button))
    end
    return entryRecord.displaySearchText
end

local function ConfigFinderEntryMatches(entryRecord, query)
    if ConfigFinderSearchTextMatches(entryRecord.searchText, query)
        or ConfigFinderSearchTextMatches(entryRecord.idSearchText, query) then
        return true
    end

    return entryRecord.needsDisplaySearch == true
        and ConfigFinderSearchTextMatches(GetConfigFinderEntryDisplaySearchText(entryRecord), query)
end

local function IsConfigFinderAvailable()
    return not CS.talentPickerMode
        and not CooldownCompanion._unsupportedLegacyProfile
end

local function IsConfigFinderActive()
    return IsConfigFinderAvailable() and IsConfigFinderQueryUsable(CS.configSearchText)
end

local function CopyConfigStateMap(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local function SnapshotOtherClassLibraryState()
    if CS.otherClassLibrarySnapshot then
        return
    end
    CS.otherClassLibrarySnapshot = {
        selectedContainer = CS.selectedContainer,
        selectedGroup = CS.selectedGroup,
        selectedButton = CS.selectedButton,
        selectedRotationAssistantEntry = CS.selectedRotationAssistantEntry,
        selectedGroups = CopyConfigStateMap(CS.selectedGroups),
        selectedPanels = CopyConfigStateMap(CS.selectedPanels),
        selectedButtons = CopyConfigStateMap(CS.selectedButtons),
        selectedCustomBars = CopyConfigStateMap(CS.selectedCustomBars),
        selectedCustomBarId = CS.selectedCustomBarId,
        selectedResourcePowerType = CS.selectedResourcePowerType,
        resourceSettingsSpecID = CS.resourceSettingsSpecID,
        barsEntrySelected = CS.barsEntrySelected,
        barWorkspaceKind = CS.barWorkspaceKind,
        castFramesSelectedItem = CS.castFramesSelectedItem,
        unifiedBarKind = CS.unifiedBarKind,
        addingToPanelId = CS.addingToPanelId,
        newInput = CS.newInput,
        expandedContainer = CS.expandedContainer,
        peekedContainers = CopyConfigStateMap(CS.peekedContainers),
        selectedTab = CS.selectedTab,
        panelSettingsTab = CS.panelSettingsTab,
        panelSettingsTabExplicit = CS.panelSettingsTabExplicit,
        selectedContainerTab = CS.selectedContainerTab,
        buttonSettingsTab = CS.buttonSettingsTab,
        unifiedRowScope = CS.unifiedRowScope,
    }
end

local function RestoreOtherClassLibrarySnapshot()
    local snapshot = CS.otherClassLibrarySnapshot
    if not snapshot then
        return
    end

    CS.selectedContainer = snapshot.selectedContainer
    CS.selectedGroup = snapshot.selectedGroup
    CS.selectedButton = snapshot.selectedButton
    CS.selectedRotationAssistantEntry = snapshot.selectedRotationAssistantEntry
    wipe(CS.selectedGroups)
    wipe(CS.selectedPanels)
    wipe(CS.selectedButtons)
    wipe(CS.selectedCustomBars)
    for id, selected in pairs(snapshot.selectedGroups or {}) do CS.selectedGroups[id] = selected end
    for id, selected in pairs(snapshot.selectedPanels or {}) do CS.selectedPanels[id] = selected end
    for id, selected in pairs(snapshot.selectedButtons or {}) do CS.selectedButtons[id] = selected end
    for id, selected in pairs(snapshot.selectedCustomBars or {}) do CS.selectedCustomBars[id] = selected end
    CS.selectedCustomBarId = snapshot.selectedCustomBarId
    CS.selectedResourcePowerType = snapshot.selectedResourcePowerType
    CS.resourceSettingsSpecID = snapshot.resourceSettingsSpecID
    CS.barsEntrySelected = snapshot.barsEntrySelected
    CS.barWorkspaceKind = snapshot.barWorkspaceKind
    CS.castFramesSelectedItem = snapshot.castFramesSelectedItem
    CS.unifiedBarKind = snapshot.unifiedBarKind
    CS.addingToPanelId = snapshot.addingToPanelId
    CS.newInput = snapshot.newInput
    CS.expandedContainer = snapshot.expandedContainer
    wipe(CS.peekedContainers)
    for id, expanded in pairs(snapshot.peekedContainers or {}) do CS.peekedContainers[id] = expanded end
    CS.selectedTab = snapshot.selectedTab
    CS.panelSettingsTab = snapshot.panelSettingsTab
    CS.panelSettingsTabExplicit = snapshot.panelSettingsTabExplicit
    CS.selectedContainerTab = snapshot.selectedContainerTab
    CS.buttonSettingsTab = snapshot.buttonSettingsTab
    CS.unifiedRowScope = snapshot.unifiedRowScope
    CS.otherClassLibrarySnapshot = nil
end

local function EnterOtherClassLibraryState(classKey)
    if not CS.otherClassLibraryActive then
        SnapshotOtherClassLibraryState()
    end
    CS.otherClassLibraryActive = true
    CS.otherClassLibraryClassKey = classKey
end

local function ResetOtherClassLibraryState(opts)
    local wasActive = CS.otherClassLibraryActive == true
    CS.otherClassLibraryActive = false
    CS.otherClassLibraryClassKey = nil
    if wasActive then
        if opts and opts.discardSelectionSnapshot then
            -- The snapshot belongs to the selection we are throwing away, so
            -- writing it back would resurrect ids the caller just cleared.
            CS.otherClassLibrarySnapshot = nil
        else
            RestoreOtherClassLibrarySnapshot()
        end
    end
    return wasActive
end

local ClearConfigPrimarySelection

local function CopyConfigFinderExpansionMap(source)
    return CopyConfigStateMap(source)
end

local function SnapshotConfigFinderExpansion()
    CS.configFinderExpansionSnapshot = {
        expandedContainer = CS.expandedContainer,
        peekedContainers = CopyConfigFinderExpansionMap(CS.peekedContainers),
    }
    CS.configFinderNavigated = nil
    CS.configFinderRestoredCollapsedContainerId = nil
end

local function RestoreConfigFinderExpansion()
    local snapshot = CS.configFinderExpansionSnapshot
    if not snapshot then
        return
    end

    CS.expandedContainer = snapshot.expandedContainer
    CS.peekedContainers = CS.peekedContainers or {}
    wipe(CS.peekedContainers)
    for containerId in pairs(snapshot.peekedContainers or {}) do
        CS.peekedContainers[containerId] = true
    end

    local selectedPanel = CS.selectedGroup
        and CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups
        and CooldownCompanion.db.profile.groups[CS.selectedGroup]
        or nil
    local selectedContainerId = selectedPanel and selectedPanel.parentContainerId or nil
    if selectedContainerId
        and CS.expandedContainer ~= selectedContainerId
        and CS.peekedContainers[selectedContainerId] ~= true then
        CS.configFinderRestoredCollapsedContainerId = selectedContainerId
    else
        CS.configFinderRestoredCollapsedContainerId = nil
    end

    CS.configFinderExpansionSnapshot = nil
end

local function SetConfigFinderText(text, opts)
    text = type(text) == "string" and text or ""
    local wasSearching = IsConfigFinderQueryUsable(CS.configSearchText)
    local willSearch = IsConfigFinderQueryUsable(text)
    if not wasSearching and willSearch then
        SnapshotConfigFinderExpansion()
    elseif wasSearching and not willSearch then
        RestoreConfigFinderExpansion()
    end
    if CS.configSearchText ~= text then
        CS._configFinderResults = nil
        CS._configFinderResultsQuery = nil
        CS._configFinderResultsDb = nil
        CS._configFinderResultsCharKey = nil
    end
    CS.configSearchText = text
    if wasSearching and not willSearch and CS.otherClassLibraryActive then
        if not CS.configFinderNavigated
            and not (opts and opts.preservePrimarySelection)
            and ClearConfigPrimarySelection then
            ClearConfigPrimarySelection()
        end
        if not CS.configFinderNavigated then
            ResetOtherClassLibraryState()
        end
    end
    if wasSearching and not willSearch then
        CS.configFinderNavigated = nil
    end

    if opts and opts.syncWidget == false then
        return
    end

    local searchBox = CS.configFinderBox
    if searchBox and searchBox.GetText and searchBox:GetText() ~= text then
        CS.configFinderSuppressTextChanged = true
        searchBox:SetText(text)
        CS.configFinderSuppressTextChanged = false
    end
    if searchBox and searchBox._cdcUpdatePlaceholder then
        searchBox._cdcUpdatePlaceholder(text)
    end
end

local function ClearConfigFinderText(opts)
    SetConfigFinderText("", opts)
end

local function InvalidateConfigFinderResults()
    CS._configFinderResults = nil
    CS._configFinderResultsQuery = nil
    CS._configFinderResultsDb = nil
    CS._configFinderResultsCharKey = nil
    CS._configFinderIndex = nil
    CS._configFinderIndexDb = nil
    CS._configFinderIndexCharKey = nil
end

local function IsContainerVisibleInConfig(container, charKey)
    if not container then
        return false
    end
    if CooldownCompanion.ResolveContainerClassScope then
        local scope = CooldownCompanion:ResolveContainerClassScope(container)
        return scope.isInvalid ~= true
    end
    return container.isGlobal or container.createdBy == charKey
end

local function GetConfigFinderEntrySearchName(buttonData)
    if not buttonData then
        return nil
    end

    if CooldownCompanion.IsEquipmentSlotEntry
        and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        return (CooldownCompanion.GetEquipmentSlotDisplayName
            and CooldownCompanion.GetEquipmentSlotDisplayName(buttonData))
            or buttonData.name
            or ("Unknown " .. tostring(buttonData.type))
    end

    return buttonData.customName
        or buttonData.name
        or ("Unknown " .. tostring(buttonData.type))
end

local function GetConfigFinderEntryDisplayText(entryRecord)
    if not entryRecord then
        return "Entry"
    end
    if entryRecord.displayText == nil then
        local buttonData = entryRecord.button
        entryRecord.displayText = GetConfigEntryDisplayName(buttonData, { includeDecorations = true })
            or entryRecord.text
            or (buttonData and ("Unknown " .. tostring(buttonData.type)))
            or "Entry"
    end
    return entryRecord.displayText
end

local function BuildConfigFinderIndex(db, charKey)
    if CS._configFinderIndex
        and CS._configFinderIndexDb == db
        and CS._configFinderIndexCharKey == charKey then
        return CS._configFinderIndex
    end

    local index = {
        containers = {},
        panels = {},
    }
    local visibleContainers = {}

    for containerId, container in pairs(db.groupContainers or {}) do
        if IsContainerVisibleInConfig(container, charKey) then
            visibleContainers[containerId] = container
            index.containers[#index.containers + 1] = {
                containerId = containerId,
                searchText = NormalizeConfigFinderText(container.name),
            }
        end
    end

    for panelId, panel in pairs(db.groups or {}) do
        local containerId = panel.parentContainerId
        local container = containerId and visibleContainers[containerId]
        if container then
            local entries = {}
            for buttonIndex, buttonData in ipairs(panel.buttons or {}) do
                local entryName = GetConfigFinderEntrySearchName(buttonData)
                entries[#entries + 1] = {
                    index = buttonIndex,
                    button = buttonData,
                    text = entryName,
                    searchText = NormalizeConfigFinderText(entryName),
                    idSearchText = buttonData.id and NormalizeConfigFinderText(tostring(buttonData.id)) or "",
                    needsDisplaySearch = buttonData.type == "spell",
                }
            end

            index.panels[#index.panels + 1] = {
                containerId = containerId,
                container = container,
                panelId = panelId,
                panel = panel,
                searchText = NormalizeConfigFinderText(panel.name),
                entries = entries,
            }
        end
    end

    CS._configFinderIndex = index
    CS._configFinderIndexDb = db
    CS._configFinderIndexCharKey = charKey
    return index
end

local function BuildConfigFinderResults()
    if not IsConfigFinderActive() then
        return nil
    end

    local query = NormalizeConfigFinderText(CS.configSearchText)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if not db then
        return nil
    end

    local charKey = CooldownCompanion.db.keys.char
    if CS._configFinderResults
        and CS._configFinderResultsQuery == query
        and CS._configFinderResultsDb == db
        and CS._configFinderResultsCharKey == charKey then
        return CS._configFinderResults
    end

    local results = {
        query = query,
        containerMatches = {},
        panelResults = {},
        totalPanelResults = 0,
        totalEntryResults = 0,
        renderedEntryResults = 0,
    }

    local function markContainer(containerId)
        if containerId then
            results.containerMatches[containerId] = true
        end
    end

    local index = BuildConfigFinderIndex(db, charKey)
    for _, containerRecord in ipairs(index.containers) do
        if ConfigFinderSearchTextMatches(containerRecord.searchText, query) then
            markContainer(containerRecord.containerId)
        end
    end

    local matchedPanels = {}
    for _, panelRecord in ipairs(index.panels) do
        local panelMatches = ConfigFinderSearchTextMatches(panelRecord.searchText, query)
        local entryMatchCount = 0

        for _, entryRecord in ipairs(panelRecord.entries or {}) do
            if ConfigFinderEntryMatches(entryRecord, query) then
                entryMatchCount = entryMatchCount + 1
            end
        end

        if panelMatches or entryMatchCount > 0 then
            markContainer(panelRecord.containerId)
            results.totalPanelResults = results.totalPanelResults + 1
            results.totalEntryResults = results.totalEntryResults + entryMatchCount
            matchedPanels[#matchedPanels + 1] = {
                containerId = panelRecord.containerId,
                container = panelRecord.container,
                panelId = panelRecord.panelId,
                panel = panelRecord.panel,
                panelMatches = panelMatches,
                sourceEntries = panelRecord.entries,
            }
        end
    end

    table.sort(matchedPanels, function(a, b)
        local orderA = a.container and CooldownCompanion:GetOrderForSpec(a.container, CooldownCompanion._currentSpecId, a.containerId) or 0
        local orderB = b.container and CooldownCompanion:GetOrderForSpec(b.container, CooldownCompanion._currentSpecId, b.containerId) or 0
        if orderA ~= orderB then
            return orderA < orderB
        end
        return (a.panel and a.panel.order or 0) < (b.panel and b.panel.order or 0)
    end)

    for _, match in ipairs(matchedPanels) do
        if #results.panelResults >= CONFIG_FINDER_MAX_PANEL_RESULTS then
            break
        end

        local renderedEntryMatches
        if match.sourceEntries then
            for _, entryRecord in ipairs(match.sourceEntries) do
                if ConfigFinderEntryMatches(entryRecord, query) then
                    if results.renderedEntryResults >= CONFIG_FINDER_MAX_ENTRY_RESULTS then
                        break
                    end
                    if not renderedEntryMatches then
                        renderedEntryMatches = {}
                    end
                    renderedEntryMatches[#renderedEntryMatches + 1] = {
                        index = entryRecord.index,
                        button = entryRecord.button,
                        text = GetConfigFinderEntryDisplayText(entryRecord),
                    }
                    results.renderedEntryResults = results.renderedEntryResults + 1
                end
            end
        end

        if match.panelMatches or (renderedEntryMatches and #renderedEntryMatches > 0) then
            match.sourceEntries = nil
            match.entryMatches = renderedEntryMatches
            results.panelResults[#results.panelResults + 1] = match
        end
    end

    if #results.panelResults < results.totalPanelResults
        or results.renderedEntryResults < results.totalEntryResults then
        results.truncated = true
    end

    CS._configFinderResults = results
    CS._configFinderResultsQuery = query
    CS._configFinderResultsDb = db
    CS._configFinderResultsCharKey = charKey
    return results
end

local function ResolveConfigContainerClassScope(containerId)
    local selectedContainer = containerId
        and CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groupContainers
        and CooldownCompanion.db.profile.groupContainers[containerId]
        or nil
    if not (selectedContainer and CooldownCompanion.ResolveContainerClassScope) then
        return nil
    end
    return CooldownCompanion:ResolveContainerClassScope(selectedContainer)
end

local function RestoreOtherClassLibraryForScope(scope)
    if scope and scope.isOtherClass then
        EnterOtherClassLibraryState(scope.ownerClassKey)
        return true
    end
    return false
end

local function SelectConfigFinderResult(containerId, panelId, buttonIndex)
    CooldownCompanion:ClearAllConfigPreviews()
    local selectedScope = ResolveConfigContainerClassScope(containerId)
    if selectedScope and selectedScope.isOtherClass then
        EnterOtherClassLibraryState(selectedScope.ownerClassKey)
    else
        ResetOtherClassLibraryState({ skipRefresh = true })
    end
    wipe(CS.selectedGroups)
    wipe(CS.selectedPanels)
    wipe(CS.selectedButtons)
    wipe(CS.selectedCustomBars)
    CS.selectedResourcePowerType = nil
    CS.resourceSettingsSpecID = nil
    CS.selectedContainer = containerId
    CS.selectedGroup = panelId
    CS.selectedButton = buttonIndex
    CS.selectedRotationAssistantEntry = nil
    -- Finder results are explicit destinations, not ordinary focus changes.
    -- Never let an anchor captured by an earlier selection switch override
    -- the result the user chose.
    CS.pendingLensAnchor = nil
    CS.barsEntrySelected = false
    CS.castFramesSelectedItem = nil
    CS.unifiedBarKind = nil
    CS.addingToPanelId = nil
    CS.configFinderNavigated = true
    CS.pendingConfigFinderEntryScrollReset = buttonIndex ~= nil
    RestoreOtherClassLibraryForScope(selectedScope)
    CooldownCompanion:RefreshConfigPanel()
end

------------------------------------------------------------------------
-- Helper: Get icon for a group (from its first button)
------------------------------------------------------------------------
local function GetGroupIcon(group)
    if group and group.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
        return CooldownCompanion:GetRotationAssistantFallbackIcon()
    end
    if group.buttons and group.buttons[1] then
        return GetButtonIcon(group.buttons[1])
    end
    return 134400
end

local function GetFirstPanelForContainer(containerId, db)
    if not (containerId and db and db.groups) then
        return nil
    end

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

    return firstPanel
end

------------------------------------------------------------------------
-- Helper: Validate icon texture (number or string)
------------------------------------------------------------------------
local function IsValidIconTexture(iconTexture)
    local iconType = type(iconTexture)
    return iconType == "number" or iconType == "string"
end

local function ApplyConfigIconPickerSelection(spec, context, iconTexture)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local entity = db and spec and spec.validateContext and spec.validateContext(context, db)
    if entity and IsValidIconTexture(iconTexture) and spec and spec.applySelection then
        spec.applySelection(iconTexture, entity, context, db)
        return true
    end
    return false
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
    local firstPanel = GetFirstPanelForContainer(containerId, db)
    if firstPanel then
        return GetGroupIcon(firstPanel)
    end
    return 134400
end

------------------------------------------------------------------------
-- Shared compact panel-row presentation helpers
------------------------------------------------------------------------
local function GetConfigPanelTypeBadgeAtlas(displayMode)
    if displayMode == "bars" then
        return "CreditsScreen-Assets-Buttons-Pause"
    elseif displayMode == "text" then
        return "poi-workorders"
    elseif displayMode == "textures" or displayMode == "trigger" then
        return "UI-HUD-MicroMenu-Communities-Icon-Notification"
    end

    return "UI-QuestPoi-QuestNumber-SuperTracked"
end

-- An Aura Panel's type badge also carries its polarity, so the Navigator says
-- which unit the panel tracks without opening it. The unit is DERIVED from the
-- panel's entries (GetAuraPanelUnit), so an empty panel, or one whose entries
-- cannot be resolved right now, has no answer yet and keeps the plain badge.
--
-- Returned as a vertex color because the badge is an atlas: the caller pairs it
-- with desaturation, the same recipe the trigger badge uses, so the tint lands
-- on grey instead of multiplying against the atlas's own gold.
local CONFIG_AURA_PANEL_BADGE_TINTS = {
    player = { 0.3, 1, 0.3, 1 },
    target = { 1, 0.3, 0.3, 1 },
}

local function GetConfigAuraPanelBadgeTint(panel)
    if not ST.IsAuraPanelGroup(panel) then
        return nil
    end
    return CONFIG_AURA_PANEL_BADGE_TINTS[CooldownCompanion:GetAuraPanelUnit(panel)]
end

local function GetConfigPanelEntryCount(panel)
    if panel and panel.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
        return 1
    end
    return panel and panel.buttons and #panel.buttons or 0
end

local function IsConfigPanelEntryUsable(panel, buttonData)
    return CooldownCompanion:IsButtonUsable(buttonData, panel)
end

local function ConfigPanelHasWarning(panel)
    for _, buttonData in ipairs(panel and panel.buttons or {}) do
        if buttonData.enabled ~= false and not IsConfigPanelEntryUsable(panel, buttonData) then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- Shared icon picker helpers
------------------------------------------------------------------------
local STANDALONE_ICON_BROWSER_ADDON = "IconBrowser"
local CONFIG_ICON_PICKER_CACHE_KEYS = {
    "buttonIconPickerFrame",
    "triggerPanelIconPickerFrame",
    "containerIconPickerFrame",
}

local function GetStandaloneIconBrowserAPI()
    local api = LRPMediaIconBrowserAPI
    if api and type(api.CreateBrowser) == "function" then
        return api
    end

    if not C_AddOns or not C_AddOns.GetAddOnInfo or not C_AddOns.IsAddOnLoaded or not C_AddOns.LoadAddOn then
        return nil
    end

    local addOnName, _, _, loadable, reason = C_AddOns.GetAddOnInfo(STANDALONE_ICON_BROWSER_ADDON)
    if not addOnName or (not loadable and reason ~= "DEMAND_LOADED") then
        return nil
    end

    local loadedOrLoading, loaded = C_AddOns.IsAddOnLoaded(STANDALONE_ICON_BROWSER_ADDON)
    if loadedOrLoading and not loaded then
        return nil
    end

    if not loaded then
        loaded = C_AddOns.LoadAddOn(STANDALONE_ICON_BROWSER_ADDON)
        if not loaded then
            return nil
        end
    end

    api = LRPMediaIconBrowserAPI
    if api and type(api.CreateBrowser) == "function" then
        return api
    end

    return nil
end

local function HideConfigIconPickerFrames()
    for _, cacheKey in ipairs(CONFIG_ICON_PICKER_CACHE_KEYS) do
        local frame = CS[cacheKey]
        if frame and frame.IsShown and frame:IsShown() then
            frame:Hide()
        end
    end
end

local function SetConfigIconPickerBrowserMode(frame, browser)
    if browser then
        frame._cdcIconBrowserActive = true
        frame.IconSelector:Hide()
        frame.IconSelector:SetAlpha(0)
        frame.BorderBox.IconDragArea:Hide()
        frame.BorderBox.IconDragArea:SetAlpha(0)
        frame.BorderBox.IconTypeDropdown:Hide()
        frame.BorderBox.IconTypeDropdown:SetAlpha(0)
        browser:Show()
        return
    end

    frame._cdcIconBrowserActive = nil
    if frame._cdcIconBrowser then
        frame._cdcIconBrowser:Hide()
    end
    frame.BorderBox.IconDragArea:SetAlpha(1)
    frame.IconSelector:SetAlpha(1)
    frame.IconSelector:Show()
    frame.BorderBox.IconTypeDropdown:SetAlpha(1)
    frame.BorderBox.IconTypeDropdown:Show()
end

local function CloseConfigIconPicker()
    HideConfigIconPickerFrames()
end

local function ResetConfigIconBrowser(browser)
    if browser.OnFilterDropdownResetClicked then
        browser:OnFilterDropdownResetClicked()
    end
end

local function SetConfigIconBrowserSelectedText(frame)
    local selectedText = frame
        and frame.BorderBox
        and frame.BorderBox.SelectedIconArea
        and frame.BorderBox.SelectedIconArea.SelectedIconText
    local description = selectedText and selectedText.SelectedIconDescription
    if description then
        description:SetText(ICON_SELECTION_CLICK)
        description:SetFontObject(GameFontHighlightSmall)
        if selectedText.Layout then
            selectedText:Layout()
        end
        return
    end

    if frame and frame.SetSelectedIconText then
        frame:SetSelectedIconText()
    end
end

local function EnsureConfigIconBrowser(frame)
    if frame._cdcIconBrowser then
        return frame._cdcIconBrowser
    end

    local api = GetStandaloneIconBrowserAPI()
    if not api then
        return nil
    end

    local browser = api.CreateBrowser(frame.BorderBox, frame.BorderBox.SelectedIconArea, 474, 330, function(iconTexture)
        if not IsValidIconTexture(iconTexture) then
            return
        end
        frame.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(iconTexture)
        SetConfigIconBrowserSelectedText(frame)
        frame.BorderBox.OkayButton:Enable()
    end)

    if not browser then
        return nil
    end

    browser:ClearAllPoints()
    browser:SetPoint("TOPLEFT", frame.IconSelector, "TOPLEFT", 0, 0)
    browser:SetPoint("BOTTOMRIGHT", frame.IconSelector, "BOTTOMRIGHT", 0, 0)
    browser:SetFrameStrata("FULLSCREEN_DIALOG")
    browser:SetFrameLevel(frame.IconSelector:GetFrameLevel() + 1)

    frame._cdcIconBrowser = browser
    return browser
end

local function OpenConfigIconBrowser(frame, currentIcon)
    if InCombatLockdown and InCombatLockdown() then
        return false
    end

    local browser = EnsureConfigIconBrowser(frame)
    if not browser then
        return false
    end

    ResetConfigIconBrowser(browser)
    browser.selectedFile = IsValidIconTexture(currentIcon) and currentIcon or nil
    if browser.selectionModel and browser.selectionModel.SetSelectedFileID then
        browser.selectionModel:SetSelectedFileID(browser.selectedFile)
    end

    SetConfigIconPickerBrowserMode(frame, browser)
    return true
end

local function EnsureConfigIconPickerFrame(spec)
    if CS[spec.cacheKey] then
        return CS[spec.cacheKey]
    end

    if not CreateAndInitFromMixin
        or not IconDataProviderMixin
        or not IconDataProviderExtraType
        or not IconSelectorPopupFrameTemplateMixin
        or not IconSelectorPopupFrameIconFilterTypes then
        return nil
    end

    local frame = CreateFrame("Frame", spec.frameName, UIParent, "IconSelectorPopupFrameTemplate")
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

    frame._cdcPickerSpec = spec

    if spec.configureFrame then
        spec.configureFrame(frame)
    end

    function frame:OnHide()
        IconSelectorPopupFrameTemplateMixin.OnHide(self)
        SetConfigIconPickerBrowserMode(self, nil)
        if self.iconDataProvider then
            self.iconDataProvider:Release()
            self.iconDataProvider = nil
        end
        self.IconSelector:SetSelectedCallback(nil)
        if self._cdcPickerSpec and self._cdcPickerSpec.clearContext then
            self._cdcPickerSpec.clearContext(self)
        else
            self._cdcPickerContext = nil
        end
    end

    function frame:OnEvent(event, ...)
        IconSelectorPopupFrameTemplateMixin.OnEvent(self, event, ...)
        if self._cdcIconBrowserActive and self._cdcIconBrowser then
            SetConfigIconPickerBrowserMode(self, self._cdcIconBrowser)
        end
    end

    function frame:OkayButton_OnClick()
        local iconTexture = self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture()
        local spec = self._cdcPickerSpec
        local context = self._cdcPickerContext
        ApplyConfigIconPickerSelection(spec, context, iconTexture)
        IconSelectorPopupFrameTemplateMixin.OkayButton_OnClick(self)
    end

    function frame:CancelButton_OnClick()
        IconSelectorPopupFrameTemplateMixin.CancelButton_OnClick(self)
    end

    CS[spec.cacheKey] = frame
    return frame
end

local function OpenConfigIconPicker(spec, context)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local entity = db and spec.validateContext and spec.validateContext(context, db)
    if not entity then
        return false
    end

    HideConfigIconPickerFrames()

    local pickerFrame = EnsureConfigIconPickerFrame(spec)
    if not pickerFrame then
        CooldownCompanion:Print(spec.unavailableMessage)
        return false
    end

    if pickerFrame:IsShown() then
        pickerFrame:Hide()
    end

    if pickerFrame.iconDataProvider then
        pickerFrame.iconDataProvider:Release()
        pickerFrame.iconDataProvider = nil
    end
    pickerFrame.iconDataProvider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.None)

    pickerFrame._cdcPickerContext = context
    local currentIcon = spec.getCurrentIcon and spec.getCurrentIcon(entity, context, db)
    if IsValidIconTexture(currentIcon) then
        pickerFrame.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(currentIcon)
        pickerFrame:SetSelectedIconText()
        pickerFrame.BorderBox.OkayButton:Enable()
    else
        pickerFrame.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(nil)
        pickerFrame:SetSelectedIconText()
        pickerFrame.BorderBox.OkayButton:Disable()
    end

    if OpenConfigIconBrowser(pickerFrame, currentIcon) then
        if IsValidIconTexture(currentIcon) then
            SetConfigIconBrowserSelectedText(pickerFrame)
        end
        pickerFrame:Show()
        SetConfigIconPickerBrowserMode(pickerFrame, pickerFrame._cdcIconBrowser)
        return true
    end

    SetConfigIconPickerBrowserMode(pickerFrame, nil)
    pickerFrame:SetIconFilter(IconSelectorPopupFrameIconFilterTypes.All)

    local selectedIndex = currentIcon and pickerFrame:GetIndexOfIcon(currentIcon) or nil

    pickerFrame.IconSelector:SetSelectionsDataProvider(
        function(selectionIndex)
            return pickerFrame:GetIconByIndex(selectionIndex)
        end,
        function()
            return pickerFrame:GetNumIcons()
        end
    )
    if selectedIndex then
        pickerFrame.IconSelector:SetSelectedIndex(selectedIndex)
        pickerFrame.IconSelector:ScrollToSelectedIndex()
        pickerFrame.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(currentIcon)
        pickerFrame:SetSelectedIconText()
        pickerFrame.BorderBox.OkayButton:Enable()
    else
        pickerFrame.IconSelector:SetSelectedIndex(nil)
        pickerFrame.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(nil)
        pickerFrame:SetSelectedIconText()
        pickerFrame.BorderBox.OkayButton:Disable()
    end

    pickerFrame.IconSelector:SetSelectedCallback(function(_, icon)
        pickerFrame.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(icon)
        pickerFrame:SetSelectedIconText()
        pickerFrame.BorderBox.OkayButton:Enable()
    end)

    pickerFrame:Show()
    return true
end

local function StartConfigIconPickerMoving(self)
    local frame = self._cdcMovableFrame or self
    frame:StartMoving()
end

local function StopConfigIconPickerMoving(self)
    local frame = self._cdcMovableFrame or self
    frame:StopMovingOrSizing()
end

local function AttachConfigIconPickerDragScripts(region, frame)
    if not region then
        return
    end

    region._cdcMovableFrame = frame
    region:EnableMouse(true)
    region:RegisterForDrag("LeftButton")
    region:SetScript("OnDragStart", StartConfigIconPickerMoving)
    region:SetScript("OnDragStop", StopConfigIconPickerMoving)
end

local function ConfigureMovableIconPickerFrame(frame)
    frame:SetMovable(true)
    AttachConfigIconPickerDragScripts(frame, frame)
    AttachConfigIconPickerDragScripts(frame.BorderBox, frame)
end

local BUTTON_ICON_PICKER_SPEC = {
    cacheKey = "buttonIconPickerFrame",
    frameName = "CDCButtonIconPickerFrame",
    unavailableMessage = "Icon picker is unavailable on this client build.",
    configureFrame = ConfigureMovableIconPickerFrame,
    validateContext = function(context, db)
        local groupId = context and context.groupId
        local buttonIndex = context and context.buttonIndex
        local group = db and db.groups and db.groups[groupId]
        return group and group.buttons and group.buttons[buttonIndex]
    end,
    getCurrentIcon = function(buttonData)
        local currentIcon = buttonData.manualIcon
        if not IsValidIconTexture(currentIcon) then
            currentIcon = GetButtonIcon(buttonData)
        end
        return currentIcon
    end,
    applySelection = function(iconTexture, buttonData, context)
        buttonData.manualIcon = iconTexture
        CooldownCompanion:RefreshGroupFrame(context.groupId)
        CooldownCompanion:RefreshConfigPanel()
    end,
    clearContext = function(frame)
        frame._cdcPickerContext = nil
    end,
}

local TRIGGER_PANEL_ICON_PICKER_SPEC = {
    cacheKey = "triggerPanelIconPickerFrame",
    frameName = "CDCTriggerPanelIconPickerFrame",
    unavailableMessage = "Icon picker is unavailable on this client build.",
    configureFrame = ConfigureMovableIconPickerFrame,
    validateContext = function(context, db)
        local groupId = context and context.groupId
        local group = db and db.groups and db.groups[groupId]
        return group and group.displayMode == "trigger" and group or nil
    end,
    getCurrentIcon = function(group)
        local settings = CooldownCompanion.GetTriggerPanelIconSettings
            and CooldownCompanion:GetTriggerPanelIconSettings(group, true)
            or nil
        return settings and settings.manualIcon or nil
    end,
    applySelection = function(iconTexture, group)
        local settings = CooldownCompanion.GetTriggerPanelIconSettings
            and CooldownCompanion:GetTriggerPanelIconSettings(group, true)
            or nil
        if not settings then
            return
        end
        settings.manualIcon = iconTexture
        CooldownCompanion:RefreshAllAuraTextureVisuals()
        CooldownCompanion:RefreshConfigPanel()
    end,
    clearContext = function(frame)
        frame._cdcPickerContext = nil
    end,
}

local CONTAINER_ICON_PICKER_SPEC = {
    cacheKey = "containerIconPickerFrame",
    frameName = "CDCContainerIconPickerFrame",
    unavailableMessage = "Icon picker is unavailable on this client build.",
    configureFrame = ConfigureMovableIconPickerFrame,
    validateContext = function(context, db)
        local containerId = context and context.containerId
        return db and db.groupContainers and db.groupContainers[containerId]
    end,
    getCurrentIcon = function(container, context, db)
        local currentIcon = container.manualIcon
        if not IsValidIconTexture(currentIcon) then
            currentIcon = GetContainerIcon(context.containerId, db)
        end
        return currentIcon
    end,
    applySelection = function(iconTexture, container)
        container.manualIcon = iconTexture
        CooldownCompanion:RefreshConfigPanel()
    end,
    clearContext = function(frame)
        frame._cdcPickerContext = nil
    end,
}

------------------------------------------------------------------------
-- Button icon picker (per-entry icon art override)
------------------------------------------------------------------------
local function OpenButtonIconPicker(groupId, buttonIndex)
    return OpenConfigIconPicker(BUTTON_ICON_PICKER_SPEC, {
        groupId = groupId,
        buttonIndex = buttonIndex,
    })
end

------------------------------------------------------------------------
-- Trigger panel icon picker (panel-level manual icon for trigger display)
------------------------------------------------------------------------
local function OpenTriggerPanelIconPicker(groupId)
    return OpenConfigIconPicker(TRIGGER_PANEL_ICON_PICKER_SPEC, {
        groupId = groupId,
    })
end

------------------------------------------------------------------------
-- Container icon picker (per-Group icon in the Navigator)
------------------------------------------------------------------------
local function OpenContainerIconPicker(containerId)
    return OpenConfigIconPicker(CONTAINER_ICON_PICKER_SPEC, {
        containerId = containerId,
    })
end

------------------------------------------------------------------------
-- Shared Shift-hover tooltip controller for config entry rows
------------------------------------------------------------------------
local function HideConfigShiftTooltip(active)
    active = active or CS.configShiftTooltipActive
    local owner = active and active.tooltipOwner
    if active then
        active.tooltipShown = nil
    end
    if owner and GameTooltip:GetOwner() ~= owner then
        return
    end
    GameTooltip:Hide()
end

local function ShowConfigShiftTooltip()
    local active = CS.configShiftTooltipActive
    if not active then
        return false
    end

    local widget = active.widget
    if not widget or not widget.frame or not widget.frame:IsShown() then
        CS.configShiftTooltipActive = nil
        HideConfigShiftTooltip(active)
        return false
    end

    if not IsShiftKeyDown() then
        if active.tooltipShown then
            HideConfigShiftTooltip(active)
        end
        return false
    end

    local kind = widget:GetUserData("cdcShiftTooltipKind")
    local id = tonumber(widget:GetUserData("cdcShiftTooltipID"))
    if not kind or not id or id <= 0 then
        if active.tooltipShown then
            HideConfigShiftTooltip(active)
        end
        return false
    end

    local owner = widget:GetUserData("cdcShiftTooltipOwner") or widget.frame
    local anchor = widget:GetUserData("cdcShiftTooltipAnchor") or "ANCHOR_RIGHT"
    local currentOwner = GameTooltip:GetOwner()
    if currentOwner and currentOwner ~= owner then
        if active.tooltipShown then
            active.tooltipShown = nil
        end
        return false
    end
    GameTooltip:SetOwner(owner, anchor)
    if kind == "spell" then
        GameTooltip:SetSpellByID(id)
    elseif kind == "item" then
        GameTooltip:SetItemByID(id)
    else
        if active.tooltipShown then
            HideConfigShiftTooltip(active)
        end
        return false
    end
    local extraLine = widget:GetUserData("cdcShiftTooltipExtraLine")
    if extraLine then
        GameTooltip:AddLine(extraLine, 0.7, 0.7, 0.7, true)
    end
    active.tooltipOwner = owner
    active.tooltipShown = true
    GameTooltip:Show()
    return true
end

local function ClearConfigShiftTooltipHover(widget)
    local active = CS.configShiftTooltipActive
    if widget then
        if not active or active.widget ~= widget then
            return
        end
    end

    CS.configShiftTooltipActive = nil
    if active and active.tooltipShown then
        HideConfigShiftTooltip(active)
    end
    if active then
        active.tooltipOwner = nil
    end
end

local configShiftTooltipEventFrame = CreateFrame("Frame")
configShiftTooltipEventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
configShiftTooltipEventFrame:SetScript("OnEvent", function(_, event, key)
    if event ~= "MODIFIER_STATE_CHANGED" then
        return
    end
    key = tostring(key or "")
    if not key:find("SHIFT", 1, true) then
        return
    end
    if IsShiftKeyDown() then
        ShowConfigShiftTooltip()
    else
        local active = CS.configShiftTooltipActive
        if active and active.tooltipShown then
            HideConfigShiftTooltip(active)
        end
    end
end)

local function ActivateConfigShiftTooltip(widget)
    if not widget then
        ClearConfigShiftTooltipHover()
        return false
    end

    CS.configShiftTooltipActive = {
        widget = widget,
        tooltipOwner = nil,
        tooltipShown = nil,
    }
    return ShowConfigShiftTooltip()
end

local function BindConfigShiftTooltip(widget, kind, id, owner, anchor)
    if not (widget and kind and id) then
        return false
    end

    widget:SetUserData("cdcShiftTooltipKind", kind)
    widget:SetUserData("cdcShiftTooltipID", tonumber(id))
    widget:SetUserData("cdcShiftTooltipOwner", owner or widget.frame)
    widget:SetUserData("cdcShiftTooltipAnchor", anchor or "ANCHOR_RIGHT")
    widget:SetCallback("OnEnter", function(hoveredWidget)
        ActivateConfigShiftTooltip(hoveredWidget)
    end)
    widget:SetCallback("OnLeave", function(leftWidget)
        ClearConfigShiftTooltipHover(leftWidget)
    end)
    return true
end

local function ResetDefaultLabelWrapping(widget)
    local label = widget and (widget.label or widget)
    if not label then return end
    if label.SetWordWrap then
        label:SetWordWrap(true)
    end
    if label.SetNonSpaceWrap then
        label:SetNonSpaceWrap(false)
    end
    if label.SetMaxLines then
        label:SetMaxLines(0)
    end
end

local function ConfigureWrappedHelperLabel(widget)
    local label = widget and (widget.label or widget)
    if not label then
        return widget
    end
    if label.SetWordWrap then
        label:SetWordWrap(true)
    end
    if label.SetNonSpaceWrap then
        label:SetNonSpaceWrap(true)
    end
    if label.SetMaxLines then
        label:SetMaxLines(0)
    end
    local releaseCallbackInstalled = widget
        and widget.SetCallback
        and widget.events
        and widget.events["OnRelease"] == widget._cdcWrappedHelperLabelReleaseCallback
    if widget and widget.SetCallback and widget.events and not releaseCallbackInstalled then
        local prevOnRelease = widget.events["OnRelease"]
        local releaseCallback
        releaseCallback = function(releasedWidget, event, ...)
            if prevOnRelease then
                prevOnRelease(releasedWidget, event, ...)
            end
            ResetDefaultLabelWrapping(releasedWidget)
            releasedWidget._cdcWrappedHelperLabelReleaseCallback = nil
        end
        widget._cdcWrappedHelperLabelReleaseCallback = releaseCallback
        widget:SetCallback("OnRelease", releaseCallback)
    end
    return widget
end

------------------------------------------------------------------------
-- Badge pool for group row status indicators
------------------------------------------------------------------------
local BADGE_SIZE = 24
local BADGE_SPACING = 2
local BADGE_RIGHT_PAD = 4
local COMPACT_ROW_HEIGHT = 32
local CONFIG_ROW_ICON_SIZE = 32
local CONFIG_ROW_ICON_GAP = 4
local CONFIG_ROW_RIGHT_PAD = 4

local function ClearConfigRowLayout(entry, restoreHandlers)
    if not entry then
        return
    end

    local icon = entry.image
    if icon then
        icon:Hide()
        icon:ClearAllPoints()
        icon:SetTexture(nil)
        icon:SetAtlas(nil)
        icon:SetAlpha(1)
        icon:SetVertexColor(1, 1, 1, 1)
        icon:SetTexCoord(0, 1, 0, 1)
        if icon.SetDesaturated then
            icon:SetDesaturated(false)
        end
    end

    local label = entry.label
    if label then
        if label.SetWordWrap then label:SetWordWrap(true) end
        if label.SetNonSpaceWrap then label:SetNonSpaceWrap(false) end
        if label.SetMaxLines then label:SetMaxLines(0) end
    end

    entry._cdcConfigRow = nil
    entry.imageshown = nil
    if icon then icon:Show() end

    if restoreHandlers then
        if entry._cdcConfigRowWidthHandlerInstalled then
            entry.OnWidthSet = entry._cdcConfigRowOriginalOnWidthSet
            entry._cdcConfigRowOriginalOnWidthSet = nil
            entry._cdcConfigRowWidthHandlerInstalled = nil
        end
        if entry._cdcConfigRowReleaseHandlerInstalled then
            entry.OnRelease = entry._cdcConfigRowOriginalOnRelease
            entry._cdcConfigRowOriginalOnRelease = nil
            entry._cdcConfigRowReleaseHandlerInstalled = nil
        end
    end
end

local function ApplyConfigRowLayout(entry)
    local row = entry and entry._cdcConfigRow
    if not (row and entry.frame and entry.label) then
        return
    end

    local compact = CS.compactConfigRows == true
    local hasIcon = row.kind == "icon"
    local frame = entry.frame
    local label = entry.label
    local leftPad = 0
    local indent = row.indent or 0
    local iconSize = row.iconSize or CONFIG_ROW_ICON_SIZE
    local iconGap = row.iconGap or CONFIG_ROW_ICON_GAP

    if not compact then
        if hasIcon then
            leftPad = indent + iconSize + iconGap
        else
            leftPad = indent + (row.normalLeftPad or 0)
        end
    else
        leftPad = indent
    end

    local rowHeight = compact and (row.compactRowHeight or COMPACT_ROW_HEIGHT) or (row.rowHeight or COMPACT_ROW_HEIGHT)
    entry:SetHeight(rowHeight)
    frame.height = rowHeight

    label:ClearAllPoints()
    label:SetPoint("LEFT", frame, "LEFT", leftPad, 0)
    local rightPad = row.rightPad or CONFIG_ROW_RIGHT_PAD
    label:SetPoint("RIGHT", frame, "RIGHT", -rightPad, 0)
    local rowWidth = frame.width or frame:GetWidth() or 0
    if rowWidth > 0 then
        label:SetWidth(math.max(1, rowWidth - leftPad - rightPad))
    end
    if label.SetWordWrap then
        label:SetWordWrap(false)
    end
    if label.SetNonSpaceWrap then
        label:SetNonSpaceWrap(false)
    end
    if label.SetMaxLines then
        label:SetMaxLines(1)
    end
    label:SetJustifyH(row.justifyH or "LEFT")
    label:SetJustifyV("MIDDLE")

    local icon = entry.image
    if icon then
        icon:ClearAllPoints()
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("LEFT", frame, "LEFT", indent, 0)

        if hasIcon and not compact and (row.texture or row.atlas) then
            if row.atlas then
                icon:SetAtlas(row.atlas, false)
            else
                icon:SetAtlas(nil)
                icon:SetTexture(row.texture)
                local texCoord = row.texCoord
                if texCoord then
                    icon:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4])
                else
                    icon:SetTexCoord(0, 1, 0, 1)
                end
            end
            local vertexColor = row.vertexColor
            if vertexColor then
                icon:SetVertexColor(vertexColor[1], vertexColor[2], vertexColor[3], vertexColor[4] or 1)
            else
                icon:SetVertexColor(1, 1, 1, 1)
            end
            icon:SetAlpha(1)
            if icon.SetDesaturated then
                icon:SetDesaturated(row.desaturated == true)
            end
            icon:Show()
        else
            icon:Hide()
        end
    end

    if entry._cdcAfterConfigRowLayout then
        entry:_cdcAfterConfigRowLayout()
    end
end

local function EnsureConfigRowHandlers(entry)
    if not entry._cdcConfigRowWidthHandlerInstalled then
        entry._cdcConfigRowOriginalOnWidthSet = entry.OnWidthSet
        entry.OnWidthSet = function(self, width)
            if self._cdcConfigRowOriginalOnWidthSet then
                self:_cdcConfigRowOriginalOnWidthSet(width)
            end
            ApplyConfigRowLayout(self)
        end
        entry._cdcConfigRowWidthHandlerInstalled = true
    end

    if not entry._cdcConfigRowReleaseHandlerInstalled then
        entry._cdcConfigRowOriginalOnRelease = entry.OnRelease
        entry.OnRelease = function(self)
            local originalOnRelease = self._cdcConfigRowOriginalOnRelease
            if self.frame._cdcDisabledModuleSelection then
                self.frame._cdcDisabledModuleSelection:Hide()
            end
            self.frame:SetAlpha(1)
            ClearConfigRowLayout(self, true)
            if originalOnRelease then
                originalOnRelease(self)
            end
        end
        entry._cdcConfigRowReleaseHandlerInstalled = true
    end
end

local function CleanRecycledEntry(entry)
    if entry.frame._cdcDisabledModuleSelection then entry.frame._cdcDisabledModuleSelection:Hide() end
    if entry._cdcModeBadge then entry._cdcModeBadge:Hide() end
    if entry._cdcModeBadgeHitRect then entry._cdcModeBadgeHitRect:Hide() end
    if entry.frame._cdcBadges then
        for _, b in ipairs(entry.frame._cdcBadges) do b:Hide() end
    end
    if entry.frame._cdcSpecBadges then
        for _, sb in ipairs(entry.frame._cdcSpecBadges) do sb:Hide() end
    end
    if entry.frame._cdcWarnBtn then entry.frame._cdcWarnBtn:Hide() end
    if entry.frame._cdcOverrideBadge then entry.frame._cdcOverrideBadge:Hide() end
    if entry.frame._cdcSoundBadge then entry.frame._cdcSoundBadge:Hide() end
    if entry.frame._cdcFallbackBadge then entry.frame._cdcFallbackBadge:Hide() end
    if entry.frame._cdcTalentBadge then entry.frame._cdcTalentBadge:Hide() end
    if entry.frame._cdcCollapseIcon then entry.frame._cdcCollapseIcon:Hide() end
    if entry.frame._cdcCollapseBtn then entry.frame._cdcCollapseBtn:Hide() end
    if entry.frame._cdcAddBtn then entry.frame._cdcAddBtn:Hide() end
    if entry.frame._cdcGenericRenameBadge then entry.frame._cdcGenericRenameBadge:Hide() end
    if entry.frame._cdcCopyPanelWash then entry.frame._cdcCopyPanelWash:Hide() end
    if entry.frame._cdcCopyPanelWashLine then entry.frame._cdcCopyPanelWashLine:Hide() end
    if entry.frame._cdcTreeExpandButton then
        entry.frame._cdcTreeExpandButton:Hide()
        entry.frame._cdcTreeExpandButton:ClearAllPoints()
        entry.frame._cdcTreeExpandButton:SetScript("OnClick", nil)
        entry.frame._cdcTreeExpandButton:SetScript("OnEnter", nil)
        entry.frame._cdcTreeExpandButton:SetScript("OnLeave", nil)
    end
    if entry.frame._cdcTreePanelMeta then
        entry.frame._cdcTreePanelMeta:Hide()
        entry.frame._cdcTreePanelMeta:ClearAllPoints()
    end
    if entry.frame._cdcDropOverlay then
        entry.frame._cdcDropOverlay:Hide()
        entry.frame._cdcDropOverlay:SetScript("OnReceiveDrag", nil)
        entry.frame._cdcDropOverlay:SetScript("OnMouseUp", nil)
    end
    if entry.highlight then
        entry.highlight:ClearAllPoints()
        entry.highlight:SetAllPoints(entry.frame)
        entry.highlight:SetVertexColor(1, 1, 1, 1)
        entry.highlight:SetAlpha(1)
    end
    if entry.label then entry.label:SetAlpha(1) end
    entry.frame:SetAlpha(1)
    if entry.frame._cdcCursorAnchorBadge then entry.frame._cdcCursorAnchorBadge:Hide() end
    if entry.frame._cdcCDMRefreshBadge then
        entry.frame._cdcCDMRefreshBadge:Hide()
        entry.frame._cdcCDMRefreshBadge:ClearAllPoints()
        entry.frame._cdcCDMRefreshBadge:SetScript("OnClick", nil)
    end
    if entry.frame._cdcAnchorBadge then entry.frame._cdcAnchorBadge:Hide() end
    if entry.frame._cdcResourcePinBadge then
        entry.frame._cdcResourcePinBadge:Hide()
        entry.frame._cdcResourcePinBadge:EnableMouse(false)
    end
    if entry.frame._cdcHeaderDisabledBadge then entry.frame._cdcHeaderDisabledBadge:Hide() end
    if entry.frame._cdcDisabledBadge then entry.frame._cdcDisabledBadge:Hide() end
    if entry.frame._cdcCustomBarTypeBadge then entry.frame._cdcCustomBarTypeBadge:Hide() end
    if entry.frame._cdcCustomBarDisabledBadge then entry.frame._cdcCustomBarDisabledBadge:Hide() end
    if entry.frame._cdcCustomBarSpecBadges then
        for _, badge in ipairs(entry.frame._cdcCustomBarSpecBadges) do badge:Hide() end
    end
    if entry.frame._cdcFallbackRemoveBtn then entry.frame._cdcFallbackRemoveBtn:Hide() end
    if entry.frame._cdcPriorityUpBtn then entry.frame._cdcPriorityUpBtn:Hide() end
    if entry.frame._cdcPriorityDownBtn then entry.frame._cdcPriorityDownBtn:Hide() end
    if entry.frame._cdcFallbackUpBtn then entry.frame._cdcFallbackUpBtn:Hide() end
    if entry.frame._cdcFallbackDownBtn then entry.frame._cdcFallbackDownBtn:Hide() end
    entry._cdcAfterConfigRowLayout = nil
    entry.frame:SetScript("OnMouseUp", nil)
    entry.frame:SetScript("OnReceiveDrag", nil)
    ClearConfigRowLayout(entry, true)
end

local function ApplyConfigRowIcon(entry, texture, opts)
    opts = opts or {}
    entry._cdcConfigRow = {
        kind = "icon",
        texture = texture,
        atlas = opts.atlas,
        desaturated = opts.desaturated == true,
        indent = opts.indent,
        iconSize = opts.iconSize,
        iconGap = opts.iconGap,
        rowHeight = opts.rowHeight,
        compactRowHeight = opts.compactRowHeight,
        texCoord = opts.texCoord,
        vertexColor = opts.vertexColor,
        rightPad = opts.rightPad,
    }
    EnsureConfigRowHandlers(entry)

    entry:SetImage(nil)
    entry.imageshown = nil

    ApplyConfigRowLayout(entry)
end

local function ApplyConfigTextRow(entry, justifyH, normalLeftPad, rightPad)
    entry._cdcConfigRow = {
        kind = "text",
        justifyH = justifyH or "LEFT",
        normalLeftPad = normalLeftPad or 0,
        rightPad = rightPad,
    }
    EnsureConfigRowHandlers(entry)

    entry:SetImage(nil)
    entry.imageshown = nil

    ApplyConfigRowLayout(entry)
end

local function ReapplyConfigRowLayouts(widget)
    if not widget then
        return
    end

    if widget._cdcConfigRow then
        ApplyConfigRowLayout(widget)
    end

    if widget.children then
        for _, child in ipairs(widget.children) do
            ReapplyConfigRowLayouts(child)
        end
    end
end

local function UpdateNestedPanelAccents(widget)
    if not widget then return end
    local frame = widget.frame
    local accent = frame and frame._cdcNestedPanelAccent
    if accent then
        accent:SetShown(CS.compactConfigRows ~= true and frame._cdcNestedPanelAccentActive == true)
    end
    for _, child in ipairs(widget.children or {}) do
        UpdateNestedPanelAccents(child)
    end
end

local function RefreshVisibleConfigCompactRows()
    ReapplyConfigRowLayouts(CS.col1Scroll)
    UpdateNestedPanelAccents(CS.col1Scroll)
    if CS.col1Scroll and CS.col1Scroll.DoLayout then CS.col1Scroll:DoLayout() end
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
    badge:EnableMouse(false)
    badge:SetScript("OnEnter", nil)
    badge:SetScript("OnLeave", nil)
    return badge
end

local function BuildEligibilityBadgeMap(...)
    local badgeMap
    for i = 1, select("#", ...) do
        local source = select(i, ...)
        if type(source) == "table" then
            for key, enabled in pairs(source) do
                local numericKey = tonumber(key)
                if enabled == true and numericKey then
                    badgeMap = badgeMap or {}
                    badgeMap[numericKey] = true
                end
            end
        end
    end
    return badgeMap
end

local function ConfigureResourceAttachmentBadge(frame, index, description)
    local badge = AcquireBadge(frame, index)
    badge.icon:SetAtlas("Waypoint-MapPin-Tracked", false)
    if not InCombatLockdown() and badge.SetPropagateMouseClicks then
        badge:EnableMouse(true)
        badge:SetPropagateMouseClicks(true)
        badge:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Resources attached")
            GameTooltip:AddLine(description, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    badge:Show()
    return badge
end

local function SetupPanelResourceIndicator(entry, panelId, rightReserve)
    local placement, anchorPanelId = ST._GetResourcesEntryPlacement()
    if placement ~= "attached" or anchorPanelId ~= panelId then return 0 end
    local badge = ConfigureResourceAttachmentBadge(entry.frame, 1,
        "Your resource bars are attached to this panel. Select Resources below the preview to edit shared settings and bar order.")
    badge:SetSize(16, 16)
    badge:ClearAllPoints()
    badge:SetPoint("RIGHT", entry.frame, "RIGHT", -(rightReserve or 4), 0)
    return badge:GetWidth() + BADGE_SPACING
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

    -- Disabled
    if group.enabled == false then
        AddAtlasBadge("GM-icon-visibleDis-pressed")
    end
    -- Unlocked (lock icon)
    if group.locked == false then
        AddAtlasBadge("ShipMissionIcon-Training-Map")
    end
    -- Resource Bars anchored to a panel in this group (pin badge).
    -- Mouse is enabled for the tooltip with clicks propagating to the row;
    -- SetPropagateMouseClicks is protected in combat, so the tooltip is
    -- skipped when refreshed mid-combat.
    -- ST._ lookup: GetResourcesEntryPlacement is declared later in this file.
    if ST._GetResourcesEntryPlacement then
        local placement, anchorPanelId = ST._GetResourcesEntryPlacement()
        if placement == "attached" and anchorPanelId then
            local dbProfile = CooldownCompanion.db and CooldownCompanion.db.profile
            local anchorGroup = dbProfile and dbProfile.groups and dbProfile.groups[anchorPanelId]
            local anchorContainer = anchorGroup and dbProfile.groupContainers
                and dbProfile.groupContainers[anchorGroup.parentContainerId]
            if anchorContainer ~= nil and anchorContainer == group then
                local anchorPanelName = anchorGroup.name or "a panel"
                badgeIndex = badgeIndex + 1
                ConfigureResourceAttachmentBadge(frame, badgeIndex,
                    "Your resource bars are anchored to " .. anchorPanelName .. " in this group.")
            end
        end
    end
    -- Spec filter badges
    local SPEC_BADGE_SIZE = 16
    local specs = BuildEligibilityBadgeMap(
        group.specs,
        group.loadConditions and group.loadConditions.specAllowlist
    )
    if specs then
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

    -- Hero talent filter badges
    local HERO_BADGE_SIZE = SPEC_BADGE_SIZE
    local heroTalents = group.heroTalents
    if heroTalents then
        local configID = C_ClassTalents.GetActiveConfigID()
        if configID then
            for subTreeID in pairs(heroTalents) do
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

local function GetConfigRowBadgeReserve(frame)
    local reserve = BADGE_RIGHT_PAD
    local hasShownBadge = false

    if frame and frame._cdcBadges then
        for _, badge in ipairs(frame._cdcBadges) do
            if badge:IsShown() then
                if hasShownBadge then
                    reserve = reserve + BADGE_SPACING
                end
                reserve = reserve + badge:GetWidth()
                hasShownBadge = true
            end
        end
    end

    return reserve
end

------------------------------------------------------------------------
-- Shared selection / spec helpers (consumed by Popups, Panel, Column*, DragReorder)
------------------------------------------------------------------------

local function CaptureLensTransition()
    CS.pendingLensAnchor = nil
    if ST._CaptureLensAnchor then
        ST._CaptureLensAnchor()
    end
end

local function ClearSelectedButton(opts)
    CS.selectedButton = nil
    CS.selectedRotationAssistantEntry = nil
    wipe(CS.selectedButtons)
    if not (opts and opts.preserveLensAnchor) then
        CS.pendingLensAnchor = nil
    end
end

local function ClearConfigButtonSelection()
    ClearSelectedButton()
end

local function ClearConfigPanelSelection()
    CS.selectedGroup = nil
    ClearSelectedButton()
end

local function ClearConfigContainerSelection()
    CS.selectedContainer = nil
    ClearConfigPanelSelection()
end

local function ClearConfigPanelMultiSelection(opts)
    wipe(CS.selectedPanels)
    if opts and opts.selectContainerId ~= nil then
        CS.selectedContainer = opts.selectContainerId
    end
end

local function ClearConfigContainerMultiSelection()
    wipe(CS.selectedGroups)
end

local function ClearConfigResourceSelection()
    CS.selectedResourcePowerType = nil
    CS.resourceSettingsSpecID = nil
end

ClearConfigPrimarySelection = function()
    CooldownCompanion:ClearAllConfigPreviews()
    CS.selectedContainer = nil
    CS.selectedGroup = nil
    CS.barsEntrySelected = false
    CS.castFramesSelectedItem = nil
    ClearSelectedButton()
    wipe(CS.selectedPanels)
    wipe(CS.selectedGroups)
    wipe(CS.selectedCustomBars)
    ClearConfigResourceSelection()
end

local function SelectConfigContainer(containerId, opts)
    CooldownCompanion:ClearAllConfigPreviews()
    CS.configFinderRestoredCollapsedContainerId = nil
    if not (opts and opts.keepContainerMulti) then
        wipe(CS.selectedGroups)
    end
    if opts and opts.toggle and CS.selectedContainer == containerId then
        if CS.selectedGroup then
            CS.selectedGroup = nil
        else
            CS.selectedContainer = nil
        end
    else
        CS.selectedContainer = containerId
        CS.selectedGroup = nil
    end

    CS.barsEntrySelected = false
    CS.castFramesSelectedItem = nil
    ClearSelectedButton()
    wipe(CS.selectedPanels)
    if opts and opts.clearFinder then
        local selectedScope = ResolveConfigContainerClassScope(CS.selectedContainer)
        ClearConfigFinderText({ preservePrimarySelection = true })
        RestoreOtherClassLibraryForScope(selectedScope)
    end
end

local function ToggleConfigContainerMultiSelect(containerId)
    CooldownCompanion:ClearAllConfigPreviews()
    if CS.selectedGroups[containerId] then
        CS.selectedGroups[containerId] = nil
    else
        CS.selectedGroups[containerId] = true
    end
    if CS.selectedContainer and not CS.selectedGroups[CS.selectedContainer] and next(CS.selectedGroups) then
        CS.selectedGroups[CS.selectedContainer] = true
    end

    CS.selectedContainer = nil
    CS.selectedGroup = nil
    CS.barsEntrySelected = false
    CS.castFramesSelectedItem = nil
    ClearSelectedButton()
    wipe(CS.selectedPanels)
    wipe(CS.selectedCustomBars)
end

local function SelectConfigPanel(panelId, opts)
    if CS.selectedGroup ~= panelId or CS.barsEntrySelected then
        CS.customBarAddContextRevision = (CS.customBarAddContextRevision or 0) + 1
        CS.panelAddModePanelId = panelId
        CS.panelAddMode = "entry"
        CS.panelAddModeQuery = nil
    end
    CooldownCompanion:ClearAllConfigPreviews()
    CS.configFinderRestoredCollapsedContainerId = nil
    if opts and opts.containerId ~= nil then
        CS.selectedContainer = opts.containerId
    end
    wipe(CS.selectedPanels)
    wipe(CS.selectedGroups)

    -- The selected object is the editing target. Returning from an entry to
    -- its own panel clears the entry highlight, but hands the semantic viewport
    -- anchor to the panel build so the user keeps their place.
    local samePanelEntry = CS.selectedGroup == panelId
        and (CS.selectedButton ~= nil or CS.selectedRotationAssistantEntry == true)
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local selectedPanel = profile and profile.groups and profile.groups[panelId]
    local supportsEntryLens = ST._GroupSupportsPerButtonOverrides
        and ST._GroupSupportsPerButtonOverrides(selectedPanel)
    local preservePlace = samePanelEntry and supportsEntryLens
    if preservePlace then
        CaptureLensTransition()
    end

    if opts and opts.toggle
        and CS.selectedGroup == panelId
        and not CS.selectedButton
        and not CS.selectedRotationAssistantEntry then
        CS.selectedGroup = nil
    else
        CS.selectedGroup = panelId
    end

    CS.barsEntrySelected = false
    CS.castFramesSelectedItem = nil
    CS.unifiedBarKind = nil
    CS.unifiedRowScope = "primary"
    ClearSelectedButton({ preserveLensAnchor = preservePlace })
end

local function ToggleConfigPanelMultiSelect(panelId)
    CooldownCompanion:ClearAllConfigPreviews()
    if CS.selectedPanels[panelId] then
        CS.selectedPanels[panelId] = nil
    else
        CS.selectedPanels[panelId] = true
    end
    if CS.selectedGroup and not CS.selectedPanels[CS.selectedGroup] and next(CS.selectedPanels) then
        CS.selectedPanels[CS.selectedGroup] = true
    end

    CS.selectedGroup = nil
    CS.barsEntrySelected = false
    CS.castFramesSelectedItem = nil
    ClearSelectedButton()
    wipe(CS.selectedGroups)
    CS.addingToPanelId = nil
end

-- Selecting an entry makes that entry the editing target. A panel tab that is
-- already open stays open and re-resolves through the selected entry's lens,
-- so changing entries immediately shows the new entry's customization state.
-- Only two things pull the surface to the
-- entry cluster: growing a multi-select (its one tab is the only place that
-- surface lives), and a caller that names a destination with opts.scope -
-- adding a spell, whose new entry is the destination.
local function SelectConfigButton(panelId, buttonIndex, opts)
    local panelChanged = CS.selectedGroup ~= panelId
    local hadEntryFocus = not panelChanged
        and (CS.selectedButton ~= nil or CS.selectedRotationAssistantEntry == true)
    local explicitDestination = opts
        and (opts.scope == "detail" or opts.scope == "primary")
    local togglingOff = not panelChanged
        and not (opts and (opts.force or opts.multi))
        and CS.selectedButton == buttonIndex
    local enteringFromPanel = not panelChanged
        and not hadEntryFocus
        and not (opts and opts.multi)
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[panelId]
    local supportsEntryLens = ST._GroupSupportsPerButtonOverrides
        and ST._GroupSupportsPerButtonOverrides(group)
    local preservePlace = supportsEntryLens
        and not explicitDestination
        and (togglingOff or enteringFromPanel)
    if preservePlace then
        CaptureLensTransition()
    elseif explicitDestination then
        CS.pendingLensAnchor = nil
    end
    if opts and opts.containerId ~= nil then
        CS.selectedContainer = opts.containerId
    end
    CS.barsEntrySelected = false
    CS.castFramesSelectedItem = nil
    CS.unifiedBarKind = nil
    if panelChanged then
        CS.selectedGroup = panelId
        ClearSelectedButton()
    end
    wipe(CS.selectedPanels)
    wipe(CS.selectedGroups)

    if opts and opts.multi then
        if CS.selectedButtons[buttonIndex] then
            CS.selectedButtons[buttonIndex] = nil
        else
            CS.selectedButtons[buttonIndex] = true
        end
        if CS.selectedButton and not CS.selectedButtons[CS.selectedButton] and next(CS.selectedButtons) then
            CS.selectedButtons[CS.selectedButton] = true
        end
        CS.selectedButton = nil
        CS.selectedRotationAssistantEntry = nil
        -- A multi-select of two or more only exists as the entry cluster's
        -- one appended tab, so the surface has to follow it there.
        local multiCount = 0
        for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
        if multiCount >= 2 then
            CS.unifiedRowScope = "detail"
        end
    else
        wipe(CS.selectedButtons)
        CS.selectedRotationAssistantEntry = nil
        if opts and opts.force then
            CS.selectedButton = buttonIndex
        elseif not panelChanged and CS.selectedButton == buttonIndex then
            CS.selectedButton = nil
        else
            CS.selectedButton = buttonIndex
        end
    end

    if not CS.selectedButton and not next(CS.selectedButtons) then
        CS.unifiedRowScope = "primary"
    end

    -- An explicit destination outranks the lens rule, in both directions.
    if opts and (opts.scope == "detail" or opts.scope == "primary") then
        CS.unifiedRowScope = opts.scope
    end

    CooldownCompanion:ClearAllConfigPreviews()
end

local function SelectConfigRotationAssistantEntry(panelId, opts)
    if opts and opts.containerId ~= nil then
        CS.selectedContainer = opts.containerId
    end
    wipe(CS.selectedPanels)
    wipe(CS.selectedGroups)

    CS.selectedGroup = panelId
    CS.selectedButton = nil
    CS.selectedRotationAssistantEntry = true
    CS.barsEntrySelected = false
    CS.castFramesSelectedItem = nil
    CS.unifiedBarKind = nil
    wipe(CS.selectedButtons)
    CS.pendingLensAnchor = nil
    -- The rotation assistant entry has no entry tabs of its own. Everything
    -- it offers is visibility, and the panel-side Visibility tab reads the
    -- selected entry, so this selection lands on the panel tabs and names
    -- Visibility as its destination. The explicit flag is what stops a
    -- display mode's own default landing tab from overriding that.
    CS.unifiedRowScope = "primary"
    CS.selectedTab = "loadconditions"
    CS.panelSettingsTab = "loadconditions"
    CS.panelSettingsTabExplicit = true
    CooldownCompanion:ClearAllConfigPreviews()
end

local function SelectConfigButtonPanel(panelId, opts)
    -- The panel becomes the sole selected editing target.
    CS.unifiedBarKind = nil
    SelectConfigPanel(panelId)
    if opts and opts.clearPanelMulti then
        wipe(CS.selectedPanels)
    end
end

local function ClearConfigCustomBarSelection(opts)
    CS.selectedCustomBarId = nil
    if opts and opts.clearExpanded then
        CS.customBarSpecExpandedId = nil
    end
    wipe(CS.selectedCustomBars)
end

-- The unified bars workspace edits one object at a time: a resource, a
-- custom bar, or a cast/frames item. Clearing all three is "back to the
-- Resources home".
local function ClearConfigBarsHomeSelection()
    ClearConfigResourceSelection()
    ClearConfigCustomBarSelection({ clearExpanded = true })
    CS.castFramesSelectedItem = nil
end

local function SelectConfigCustomBar(customBarId, opts)
    local wasActive = CS.barsEntrySelected or CS.unifiedBarKind == "custom"
    if not CS.barsEntrySelected and CS.selectedGroup then
        CS.unifiedBarKind = "custom"
        ClearSelectedButton()
    end
    local selectionChanged = CS.selectedCustomBarId ~= customBarId or not wasActive
    if opts and opts.toggle and not selectionChanged then
        ClearConfigCustomBarSelection()
        return true
    end

    ClearConfigResourceSelection()
    CS.castFramesSelectedItem = nil
    -- Selecting a bar jumps to its one Settings tab, the same way selecting
    -- an entry does, even if a module tab was the last thing shown.
    CS.unifiedRowScope = "detail"
    CS.selectedCustomBarId = customBarId
    wipe(CS.selectedCustomBars)
    if opts and opts.clearButtonMulti then
        CS.selectedRotationAssistantEntry = nil
        wipe(CS.selectedButtons)
    end
    return selectionChanged
end

local function ToggleConfigCustomBarMultiSelect(customBarId)
    ClearConfigResourceSelection()
    CS.castFramesSelectedItem = nil
    if CS.selectedCustomBars[customBarId] then
        CS.selectedCustomBars[customBarId] = nil
    else
        CS.selectedCustomBars[customBarId] = true
    end
    if CS.selectedCustomBarId and not CS.selectedCustomBars[CS.selectedCustomBarId] and next(CS.selectedCustomBars) then
        CS.selectedCustomBars[CS.selectedCustomBarId] = true
    end
end

local function SetConfigResourceSettingsSpecID(specID)
    local powerType = CS.selectedResourcePowerType
    if powerType == nil then
        CS.resourceSettingsSpecID = nil
        return false
    end

    local numericSpecID = tonumber(specID)
    local RBP = ST._RBP
    local resolvedSpecID = RBP
        and RBP.GetDefaultResourceSettingsSpecID
        and RBP.GetDefaultResourceSettingsSpecID(powerType, numericSpecID)
        or nil
    local changed = CS.resourceSettingsSpecID ~= resolvedSpecID
    CS.resourceSettingsSpecID = resolvedSpecID
    return changed
end

local function SelectConfigResource(powerType, opts)
    local numericPowerType = tonumber(powerType)
    if numericPowerType == nil then return false end
    local wasActive = CS.barsEntrySelected or CS.unifiedBarKind == "resource"
    if not CS.barsEntrySelected and CS.selectedGroup then
        CS.unifiedBarKind = "resource"
        ClearSelectedButton()
    end

    local selectionChanged = CS.selectedResourcePowerType ~= numericPowerType or not wasActive
    if opts and opts.toggle and not selectionChanged then
        ClearConfigResourceSelection()
        return true
    end

    CS.selectedCustomBarId = nil
    CS.customBarSpecExpandedId = nil
    wipe(CS.selectedCustomBars)
    CS.castFramesSelectedItem = nil
    -- Selecting a resource jumps to its own tabs, the same way selecting an
    -- entry does, even if a module tab was the last thing shown.
    CS.unifiedRowScope = "detail"
    if opts and opts.clearButtonMulti then
        CS.selectedRotationAssistantEntry = nil
        wipe(CS.selectedButtons)
    end

    CS.selectedResourcePowerType = numericPowerType
    CS.resourceSettingsSpecID = nil
    SetConfigResourceSettingsSpecID(opts and opts.specID)
    return selectionChanged
end

local function PruneConfigResourceSelection(resourceExists)
    if type(resourceExists) ~= "function" or CS.selectedResourcePowerType == nil then
        return false
    end

    if not resourceExists(CS.selectedResourcePowerType) then
        ClearConfigResourceSelection()
        return true
    end

    return SetConfigResourceSettingsSpecID(CS.resourceSettingsSpecID)
end

local function PruneConfigCustomBarSelection(customBarExists)
    if type(customBarExists) ~= "function" then
        return
    end

    if CS.selectedCustomBarId and not customBarExists(CS.selectedCustomBarId) then
        CS.selectedCustomBarId = nil
    end
    if CS.customBarSpecExpandedId and not customBarExists(CS.customBarSpecExpandedId) then
        CS.customBarSpecExpandedId = nil
    end
    for customBarId in pairs(CS.selectedCustomBars) do
        if not customBarExists(customBarId) then
            CS.selectedCustomBars[customBarId] = nil
        end
    end
end

-- Unified anchor preview (buttons view): clicking an attached bar in the
-- pinned preview selects it for editing below the divider. Toggle
-- semantics by default; `opts.toggle = false` selects without the
-- toggle-off (the right-click menu must keep an already-selected bar
-- selected under its menu). A bar selection replaces any entry
-- selection, and the entry/panel selectors clear unifiedBarKind in
-- return.
local function SelectUnifiedAnchorBar(slot, opts)
    if type(slot) ~= "table" then
        return false
    end
    local allowToggle = not (opts and opts.toggle == false)
    if slot.kind == "custom" and opts and opts.multi then
        if not CS.selectedCustomBarId then SelectConfigCustomBar(slot.customBarId) end
        ToggleConfigCustomBarMultiSelect(slot.customBarId)
        CS.unifiedBarKind = "custom"
        CS.unifiedRowScope = "detail"
        ClearSelectedButton()
        return true
    end

    if slot.kind == "resource" and slot.powerType ~= nil then
        if allowToggle
            and CS.unifiedBarKind == "resource"
            and tostring(CS.selectedResourcePowerType) == tostring(slot.powerType) then
            CS.unifiedBarKind = nil
            ClearConfigResourceSelection()
            return true
        end
        SelectConfigResource(slot.powerType)
        if CS.selectedResourcePowerType == nil then
            return false
        end
        CS.unifiedBarKind = "resource"
    elseif slot.kind == "custom" and slot.customBarId ~= nil then
        if allowToggle
            and CS.unifiedBarKind == "custom"
            and tostring(CS.selectedCustomBarId) == tostring(slot.customBarId) then
            CS.unifiedBarKind = nil
            ClearConfigCustomBarSelection()
            return true
        end
        SelectConfigCustomBar(slot.customBarId)
        CS.unifiedBarKind = "custom"
    elseif slot.kind == "cast" then
        if allowToggle and CS.unifiedBarKind == "cast" then
            CS.unifiedBarKind = nil
            return true
        end
        ClearConfigResourceSelection()
        ClearConfigCustomBarSelection()
        CS.unifiedBarKind = "cast"
    else
        return false
    end

    -- The bar's settings own the settings area; entry selection ends. Like
    -- selecting an entry, this jumps to the bar's own tabs even if a panel
    -- tab was the last thing shown.
    CS.unifiedRowScope = "detail"
    ClearSelectedButton()
    return true
end

-- Route legacy Resources-home callers to the actual stack destination.
-- Only the workspace router requests a standalone inventory destination.
local function SelectConfigBarsEntry(opts)
    if not (opts and opts.standalone) and ST._OpenBarWorkspace then
        return ST._OpenBarWorkspace("resources")
    end
    local kind = opts and opts.kind or "resources"
    if not CS.barsEntrySelected or CS.barWorkspaceKind ~= kind then
        CS.customBarAddContextRevision = (CS.customBarAddContextRevision or 0) + 1
    end
    CS.barWorkspaceKind = kind
    CooldownCompanion:ClearAllConfigPreviews()
    ResetOtherClassLibraryState()
    -- Destination navigation exits the temporary filtered-tree view.
    ClearConfigFinderText({ preservePrimarySelection = true })
    if opts and opts.toggle and CS.barsEntrySelected then
        CS.barsEntrySelected = false
    else
        CS.barsEntrySelected = true
    end
    CS.selectedGroup = nil
    CS.unifiedBarKind = nil
    ClearSelectedButton()
    wipe(CS.selectedPanels)
    wipe(CS.selectedGroups)
    ClearConfigBarsHomeSelection()
end

-- A cast/frames item belongs to the same mutually exclusive family as the
-- resources and custom bars beside it, so selecting one drops any bar.
local function SelectConfigCastFramesItem(item)
    if item ~= "castbar" and item ~= "player" and item ~= "target" then
        return false
    end
    local changed = CS.castFramesSelectedItem ~= item
    if ST._OpenBarWorkspace then ST._OpenBarWorkspace(item) end
    ClearConfigResourceSelection()
    ClearConfigCustomBarSelection({ clearExpanded = true })
    CS.castFramesSelectedItem = item
    return changed
end

-- Where the "Resource Bars" entry lives in the panel list right now.
-- Returns "disabled" | "independent" | "attached", anchorPanelId (nil when
-- enabled+dependent but no eligible anchor panel exists).
local function GetResourcesEntryPlacement()
    local settings = CooldownCompanion.GetResourceBarSettings
        and CooldownCompanion:GetResourceBarSettings()
        or nil
    if not settings or settings.enabled ~= true then
        return "disabled"
    end
    if CooldownCompanion.IsResourceBarAnchorIndependent
        and CooldownCompanion:IsResourceBarAnchorIndependent() then
        return "independent"
    end
    return "attached", CooldownCompanion:GetFirstAvailableAnchorGroup()
end

-- A disabled standalone feature introduces itself before exposing its editor.
-- The resource conflict gate must remain reachable instead of being covered.
local function GetBarWorkspaceIntroKind()
    if not CS.barsEntrySelected then return nil end
    local kind = CS.barWorkspaceKind or CS.castFramesSelectedItem or "resources"
    local settings
    if kind == "resources" then
        if CooldownCompanion.GetCurrentResourceBarConflict
            and CooldownCompanion:GetCurrentResourceBarConflict() then return nil end
        settings = CooldownCompanion:GetResourceBarSettings()
    elseif kind == "castbar" then
        settings = CooldownCompanion:GetCastBarSettings()
    elseif kind == "player" or kind == "target" then
        kind = "frames"
        settings = CooldownCompanion:GetFrameAnchoringSettings()
    else
        return nil
    end
    if not (settings and settings.enabled == true) then return kind end
    return nil
end

-- True for the normal panel workspace, including Other Class browsing,
-- which shares it wholesale. The bars workspace and the talent picker have
-- their own workspace routing even though the cutover now gives every
-- non-picker view the same Navigator + workspace frame.
local function IsButtonsWideViewActive()
    return not (CS.barsEntrySelected
        or CS.talentPickerMode)
end

local function ResetConfigSelection(full)
    CooldownCompanion:ClearAllConfigPreviews()
    CS.selectedButton = nil
    CS.selectedRotationAssistantEntry = nil
    CS.unifiedBarKind = nil
    CS.selectedCustomBarId = nil
    CS.customBarSpecExpandedId = nil
    ClearConfigResourceSelection()
    wipe(CS.selectedButtons)
    CS.pendingLensAnchor = nil
    wipe(CS.selectedPanels)
    wipe(CS.selectedCustomBars)
    if full then
        CS.selectedContainer = nil
        CS.selectedGroup = nil
        CS.barsEntrySelected = false
        CS.castFramesSelectedItem = nil
        wipe(CS.selectedGroups)
        wipe(CS.selectedCustomBars)
        CS.addingToPanelId = nil
        ResetOtherClassLibraryState({ discardSelectionSnapshot = true })
    end
end

-- The legacy Bars & Frames mode is gone; only "buttons" remains and it is
-- a plain view refresh. The calls still matter: ResourceBarLifecycle
-- hooksecurefuncs the exported wrapper (ST._SetConfigPrimaryMode) to
-- re-apply bars whenever the config opens or resets its view — never
-- delete or replace that wrapper symbol, change only this impl.
local function SetConfigPrimaryMode(mode, opts)
    if mode ~= "buttons" then
        return false
    end
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
        local normalizedSpecId = tonumber(specId)
        if normalizedSpecId and not playerSpecIds[normalizedSpecId] then
            return true
        end
    end
    return false
end

local function BuildPlayerHeroTalentSet(playerSpecIds)
    local playerHeroTalentIds = {}
    if not (C_ClassTalents and C_ClassTalents.GetHeroTalentSpecsForClassSpec) then
        return playerHeroTalentIds, false
    end
    for specId in pairs(playerSpecIds or {}) do
        local subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specId)
        for _, subTreeID in ipairs(subTreeIDs or {}) do
            local normalizedSubTreeID = tonumber(subTreeID)
            if normalizedSubTreeID then
                playerHeroTalentIds[normalizedSubTreeID] = true
            end
        end
    end
    return playerHeroTalentIds, true
end

local function HasEnabledMapValue(map)
    if type(map) ~= "table" then return false end
    for _, enabled in pairs(map) do
        if enabled == true then return true end
    end
    return false
end

local function HeroTalentSetHasForeignHeroTalents(heroTalents, playerHeroTalentIds, hasHeroTalentData)
    if type(heroTalents) ~= "table" then return false end
    if not hasHeroTalentData then
        return HasEnabledMapValue(heroTalents)
    end
    for subTreeID, enabled in pairs(heroTalents) do
        local normalizedSubTreeID = tonumber(subTreeID)
        if enabled == true and (not normalizedSubTreeID or not playerHeroTalentIds[normalizedSubTreeID]) then
            return true
        end
    end
    return false
end

local function BuildPlayerClassKey()
    if not UnitClass then return nil end
    local _, classFilename = UnitClass("player")
    return type(classFilename) == "string" and string.upper(classFilename) or nil
end

local function BuildPlayerCharacterKey()
    return CooldownCompanion.db
        and CooldownCompanion.db.keys
        and CooldownCompanion.db.keys.char
        or nil
end

local function ClassAllowlistHasForeignClasses(classAllowlist, playerClassKey)
    if type(classAllowlist) ~= "table" or not playerClassKey then return false end
    for classKey, enabled in pairs(classAllowlist) do
        if enabled == true
            and type(classKey) == "string"
            and string.upper(classKey) ~= playerClassKey
        then
            return true
        end
    end
    return false
end

local function CharacterInfoClassKey(charKey)
    local info = charKey
        and CooldownCompanion.db
        and CooldownCompanion.db.global
        and CooldownCompanion.db.global.characterInfo
        and CooldownCompanion.db.global.characterInfo[charKey]
        or nil
    if type(info) ~= "table" then return nil end
    if type(info.classFilename) == "string" and info.classFilename ~= "" then
        return string.upper(info.classFilename)
    end
    local classID = tonumber(info.classID)
    if classID then
        local classInfo = C_CreatureInfo and C_CreatureInfo.GetClassInfo
            and C_CreatureInfo.GetClassInfo(classID)
            or nil
        local classFilename = type(classInfo) == "table" and classInfo.classFile or nil
        if not classFilename and GetClassInfo then
            classFilename = select(2, GetClassInfo(classID))
        end
        if type(classFilename) == "string" and classFilename ~= "" then
            return string.upper(classFilename)
        end
    end
    return nil
end

local function CharacterAllowlistHasForeignClasses(characterAllowlist, playerClassKey, playerCharKey)
    if type(characterAllowlist) ~= "table" or not playerClassKey then return false end
    for charKey, enabled in pairs(characterAllowlist) do
        if enabled == true then
            if type(charKey) ~= "string" or charKey == "" then
                return true
            end
            if not (playerCharKey and charKey == playerCharKey) then
                local characterClassKey = CharacterInfoClassKey(charKey)
                if characterClassKey ~= playerClassKey then
                    return true
                end
            end
        end
    end
    return false
end

local function EntityHasForeignEligibility(entity, playerSpecIds, playerClassKey, playerCharKey, playerHeroTalentIds, hasHeroTalentData)
    if type(entity) ~= "table" then return false end
    local loadConditions = entity.loadConditions
    return SpecSetHasForeignSpecs(entity.specs, playerSpecIds)
        or HeroTalentSetHasForeignHeroTalents(entity.heroTalents, playerHeroTalentIds, hasHeroTalentData)
        or SpecSetHasForeignSpecs(
            type(loadConditions) == "table" and loadConditions.specAllowlist or nil,
            playerSpecIds
        )
        or ClassAllowlistHasForeignClasses(
            type(loadConditions) == "table" and loadConditions.classAllowlist or nil,
            playerClassKey
        )
        or CharacterAllowlistHasForeignClasses(
            type(loadConditions) == "table" and loadConditions.characterAllowlist or nil,
            playerClassKey,
            playerCharKey
        )
end

local function FindContainerId(db, container)
    if not (db and db.groupContainers and type(container) == "table") then return nil end
    for containerId, candidate in pairs(db.groupContainers) do
        if candidate == container then
            return containerId
        end
    end
    return nil
end

local function ContainerPanelsHaveForeignEligibility(containerId, playerSpecIds, playerClassKey, playerCharKey, playerHeroTalentIds, hasHeroTalentData)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if not (db and db.groups and containerId) then return false end
    for _, group in pairs(db.groups) do
        if type(group) == "table"
            and group.parentContainerId == containerId
            and EntityHasForeignEligibility(group, playerSpecIds, playerClassKey, playerCharKey, playerHeroTalentIds, hasHeroTalentData)
        then
            return true
        end
    end
    return false
end

local function EntityOrChildPanelsHaveForeignEligibility(entity, playerSpecIds, playerClassKey, playerCharKey, playerHeroTalentIds, hasHeroTalentData)
    if EntityHasForeignEligibility(entity, playerSpecIds, playerClassKey, playerCharKey, playerHeroTalentIds, hasHeroTalentData) then
        return true
    end
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local containerId = FindContainerId(db, entity)
    return ContainerPanelsHaveForeignEligibility(containerId, playerSpecIds, playerClassKey, playerCharKey, playerHeroTalentIds, hasHeroTalentData)
end

local function ContainersHaveForeignSpecs(containers, requireGlobal)
    local playerSpecIds = BuildPlayerSpecSet()
    local playerClassKey = BuildPlayerClassKey()
    local playerCharKey = BuildPlayerCharacterKey()
    local playerHeroTalentIds, hasHeroTalentData = BuildPlayerHeroTalentSet(playerSpecIds)
    for _, c in ipairs(containers) do
        if not requireGlobal or c.isGlobal then
            if EntityOrChildPanelsHaveForeignEligibility(c, playerSpecIds, playerClassKey, playerCharKey, playerHeroTalentIds, hasHeroTalentData) then
                return true
            end
        end
    end
    return false
end

local function GroupsHaveForeignSpecs(groups, requireGlobal)
    local playerSpecIds = BuildPlayerSpecSet()
    local playerClassKey = BuildPlayerClassKey()
    local playerCharKey = BuildPlayerCharacterKey()
    local playerHeroTalentIds, hasHeroTalentData = BuildPlayerHeroTalentSet(playerSpecIds)
    for _, g in ipairs(groups) do
        if not requireGlobal or g.isGlobal then
            if EntityOrChildPanelsHaveForeignEligibility(g, playerSpecIds, playerClassKey, playerCharKey, playerHeroTalentIds, hasHeroTalentData) then
                return true
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
        if widget.frame and widget.frame._cdcNestedPanelAccent then
            widget.frame._cdcNestedPanelAccent:Hide()
            widget.frame._cdcNestedPanelAccent:ClearAllPoints()
            widget.frame._cdcNestedPanelAccentActive = nil
        end
        widget.LayoutFinished = originalLayoutFinished
    end)
end

------------------------------------------------------------------------
-- ST._ exports (consumed by later Config/ files at load time)
------------------------------------------------------------------------
ST._CompactUntitledInlineGroupConfig = CompactUntitledInlineGroupConfig
ST._CleanRecycledEntry = CleanRecycledEntry
ST._ApplyConfigRowIcon = ApplyConfigRowIcon
ST._ApplyConfigTextRow = ApplyConfigTextRow
ST._RefreshVisibleConfigCompactRows = RefreshVisibleConfigCompactRows
ST._SetupGroupRowIndicators = SetupGroupRowIndicators
ST._SetupPanelResourceIndicator = SetupPanelResourceIndicator
ST._GetConfigRowBadgeReserve = GetConfigRowBadgeReserve
ST._GetButtonIcon = GetButtonIcon
ST._GetConfigEntryDisplayName = GetConfigEntryDisplayName
ST._IsConfigFinderAvailable = IsConfigFinderAvailable
ST._IsConfigFinderActive = IsConfigFinderActive
ST._SetConfigFinderText = SetConfigFinderText
ST._ClearConfigFinderText = ClearConfigFinderText
ST._ResetOtherClassLibraryState = ResetOtherClassLibraryState
ST._EnterOtherClassLibraryState = EnterOtherClassLibraryState
ST._BuildConfigFinderResults = BuildConfigFinderResults
ST._InvalidateConfigFinderResults = InvalidateConfigFinderResults
ST._SelectConfigFinderResult = SelectConfigFinderResult
ST._GetContainerIcon = GetContainerIcon
ST._GetConfigPanelTypeBadgeAtlas = GetConfigPanelTypeBadgeAtlas
ST._GetConfigAuraPanelBadgeTint = GetConfigAuraPanelBadgeTint
ST._GetConfigPanelEntryCount = GetConfigPanelEntryCount
ST._ConfigPanelHasWarning = ConfigPanelHasWarning
ST._OpenButtonIconPicker = OpenButtonIconPicker
ST._OpenTriggerPanelIconPicker = OpenTriggerPanelIconPicker
ST._OpenContainerIconPicker = OpenContainerIconPicker
ST._CloseConfigIconPicker = CloseConfigIconPicker
ST._IsValidIconTexture = IsValidIconTexture
ST._ShowPopupAboveConfig = ShowPopupAboveConfig
ST._BindConfigShiftTooltip = BindConfigShiftTooltip
ST._ActivateConfigShiftTooltip = ActivateConfigShiftTooltip
ST._ConfigureWrappedHelperLabel = ConfigureWrappedHelperLabel
ST._ClearConfigShiftTooltipHover = ClearConfigShiftTooltipHover
ST._COLUMN_PADDING = COLUMN_PADDING
ST._ClearConfigButtonSelection = ClearConfigButtonSelection
ST._ClearConfigPanelSelection = ClearConfigPanelSelection
ST._ClearConfigContainerSelection = ClearConfigContainerSelection
ST._ClearConfigPanelMultiSelection = ClearConfigPanelMultiSelection
ST._ClearConfigContainerMultiSelection = ClearConfigContainerMultiSelection
ST._ClearConfigPrimarySelection = ClearConfigPrimarySelection
ST._SelectConfigContainer = SelectConfigContainer
ST._ToggleConfigContainerMultiSelect = ToggleConfigContainerMultiSelect
ST._SelectConfigPanel = SelectConfigPanel
ST._ToggleConfigPanelMultiSelect = ToggleConfigPanelMultiSelect
ST._SelectConfigButton = SelectConfigButton
ST._SelectConfigRotationAssistantEntry = SelectConfigRotationAssistantEntry
ST._SelectConfigButtonPanel = SelectConfigButtonPanel
ST._ClearConfigCustomBarSelection = ClearConfigCustomBarSelection
ST._ClearConfigBarsHomeSelection = ClearConfigBarsHomeSelection
ST._SelectConfigCustomBar = SelectConfigCustomBar
ST._ToggleConfigCustomBarMultiSelect = ToggleConfigCustomBarMultiSelect
ST._PruneConfigCustomBarSelection = PruneConfigCustomBarSelection
ST._SelectConfigResource = SelectConfigResource
ST._SelectUnifiedAnchorBar = SelectUnifiedAnchorBar
ST._SetConfigResourceSettingsSpecID = SetConfigResourceSettingsSpecID
ST._PruneConfigResourceSelection = PruneConfigResourceSelection
ST._SelectConfigBarsEntry = SelectConfigBarsEntry
ST._SelectConfigCastFramesItem = SelectConfigCastFramesItem
ST._GetResourcesEntryPlacement = GetResourcesEntryPlacement
ST._GetBarWorkspaceIntroKind = GetBarWorkspaceIntroKind
ST._IsButtonsWideViewActive = IsButtonsWideViewActive
ST._ResetConfigSelection = ResetConfigSelection
ST._SetConfigPrimaryModeImpl = SetConfigPrimaryMode
ST._GroupsHaveForeignSpecs = GroupsHaveForeignSpecs
ST._ContainersHaveForeignSpecs = ContainersHaveForeignSpecs

-- Runtime mover menus load the config on demand, then route directly to the
-- selected object's Layout controls. Keeping the route inside the config
-- addon avoids duplicating its selection state in the runtime addon.
ST._ApplyConfigRoute = function(route)
    if type(route) ~= "table" then return end
    if route.kind == "panel" and route.id then
        SelectConfigPanel(route.id, { containerId = route.containerId })
        CS.selectedTab = "layout"
        CS.panelSettingsTab = "layout"
        CS.panelSettingsTabExplicit = true
        CS.collapsedSections.layout_anchor = false
    elseif route.kind == "container" and route.id then
        SelectConfigContainer(route.id)
        CS.selectedContainerTab = "general"
        CS.collapsedSections.container_layout = false
    elseif route.kind == "resource" then
        SetConfigPrimaryMode("bars")
        SelectConfigBarsEntry()
        CS.resourcesSettingsTab = "layout"
        if ST._RBP and ST._RBP.collapsedSections then
            ST._RBP.collapsedSections.rb_stack_position = false
        end
    elseif route.kind == "cast" then
        SetConfigPrimaryMode("bars")
        SelectConfigBarsEntry()
        SelectConfigCastFramesItem("castbar")
        CS.unifiedRowScope = "detail"
        CS.castBarHomeTab = "layout"
        CS.collapsedSections.castbar_anchor = false
    else
        return
    end
    CooldownCompanion:RefreshConfigPanel()
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
