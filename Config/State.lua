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
    selectedFolder = nil,        -- folderId selected in Column 1
    selectedContainer = nil,     -- containerId selected in Column 1
    selectedGroup = nil,         -- panelId (groupId) selected in Column 2 panel list
    selectedButton = nil,
    selectedButtons = {},
    selectedPanels = {},         -- multi-selected panel IDs (within a container)
    selectedGroups = {},         -- multi-selected container IDs
    selectedCustomBars = {},     -- multi-selected custom bar IDs
    selectedTab = "appearance",
    selectedContainerTab = "general",
    buttonSettingsTab = "settings",
    panelSettingsTab = "appearance",
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
    customBarContextMenu = nil,
    gearDropdownFrame = nil,
    folderContextMenu = nil,
    folderIconPickerFrame = nil,
    buttonIconPickerFrame = nil,
    triggerPanelIconPickerFrame = nil,
    containerIconPickerFrame = nil,
    panelContextMenu = nil,
    col2PanelTypeMenu = nil,
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

    -- Config finder state
    configSearchText = "",
    configFinderBox = nil,
    configFinderSuppressTextChanged = false,
    compactConfigRows = false,

    -- Spec filter inline expansion
    specExpandedGroupId = nil,
    specExpandedFolderId = nil,

    -- Auto Add flow state (Column 3 wizard mode)
    autoAddFlowActive = false,
    autoAddFlowState = nil,
    autoAddFlowSerial = 0,
    configShiftTooltipActive = nil,

    -- Tab UI state (populated by ConfigSettings, cleaned by both files)
    tabInfoButtons = {},
    customBarInfoButtons = {},
    appearanceTabElements = {},
    resourceBarPanelActive = false,
    barPanelTab = "resource_anchoring",
    resourceStylingTab = "bar_text",
    castBarStylingTab = "styling",
    resourceAuraOverlayDrafts = {},
    customBarSettingsTab = "appearance",
    selectedCustomBarId = nil,
    customBarSpecExpandedId = nil,
    customBarIndicatorPreviewActive = nil,
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
    SearchCDMAuraAutocomplete = nil,
    ResolveCDMAuraAutocompleteEntry = nil,
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
    local entryName = buttonData.customName or buttonData.name

    if buttonData.type == "spell" then
        local child
        if buttonData.cdmChildSlot then
            local allChildren = CooldownCompanion.viewerAuraAllChildren[buttonData.id]
            child = allChildren and allChildren[buttonData.cdmChildSlot]
        else
            child = CooldownCompanion.viewerAuraFrames[buttonData.id]
        end

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
            local icons = ""
            if addedAs ~= "aura" then
                icons = icons .. "|A:ui_adv_atk:15:15|a"
            end
            if addedAs == "aura" or buttonData.auraTracking then
                icons = icons .. "|A:ui_adv_health:15:15|a"
            end
            if icons ~= "" then
                entryName = (entryName or ("Unknown " .. tostring(buttonData.type))) .. "  " .. icons
            end
        end
    elseif buttonData.type == "item" and includeDecorations then
        entryName = entryName or ("Unknown " .. tostring(buttonData.type))
        if C_Item.IsEquippableItem(buttonData.id) then
            entryName = entryName .. "  |A:Crosshair_repairnpc_32:15:15|a"
        else
            entryName = entryName .. "  |A:auctionhouse-icon-coin-gold:12:12|a"
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

local function ConfigFinderTextMatches(value, query)
    if not query or query == "" then
        return false
    end
    return NormalizeConfigFinderText(value):find(query, 1, true) ~= nil
end

local function IsConfigFinderAvailable()
    return not CS.resourceBarPanelActive
        and not CS.browseMode
        and not CS.talentPickerMode
        and not CooldownCompanion._unsupportedLegacyProfile
end

local function IsConfigFinderActive()
    return IsConfigFinderAvailable() and NormalizeConfigFinderText(CS.configSearchText) ~= ""
end

local function SetConfigFinderText(text, opts)
    text = type(text) == "string" and text or ""
    if CS.configSearchText ~= text then
        CS._configFinderResults = nil
        CS._configFinderResultsQuery = nil
        CS._configFinderResultsDb = nil
        CS._configFinderResultsCharKey = nil
    end
    CS.configSearchText = text

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
end

local function IsContainerVisibleInConfig(container, charKey)
    if not container then
        return false
    end
    return container.isGlobal or container.createdBy == charKey
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
    }

    local function markContainer(containerId)
        if containerId then
            results.containerMatches[containerId] = true
        end
    end

    for containerId, container in pairs(db.groupContainers or {}) do
        if IsContainerVisibleInConfig(container, charKey) and ConfigFinderTextMatches(container.name, query) then
            markContainer(containerId)
        end
    end

    for panelId, panel in pairs(db.groups or {}) do
        local containerId = panel.parentContainerId
        local container = containerId and db.groupContainers and db.groupContainers[containerId]
        if IsContainerVisibleInConfig(container, charKey) then
            local panelMatches = ConfigFinderTextMatches(panel.name, query)
            local entryMatches

            for buttonIndex, buttonData in ipairs(panel.buttons or {}) do
                local entryName = GetConfigEntryDisplayName(buttonData, { includeDecorations = true })
                    or buttonData.name
                    or ("Unknown " .. tostring(buttonData.type))
                local idText = buttonData.id and tostring(buttonData.id) or nil
                if ConfigFinderTextMatches(entryName, query) or ConfigFinderTextMatches(idText, query) then
                    if not entryMatches then
                        entryMatches = {}
                    end
                    entryMatches[#entryMatches + 1] = {
                        index = buttonIndex,
                        button = buttonData,
                        text = entryName,
                    }
                end
            end

            local entryMatchCount = entryMatches and #entryMatches or 0
            if panelMatches or entryMatchCount > 0 then
                markContainer(containerId)
                results.totalPanelResults = results.totalPanelResults + 1
                results.totalEntryResults = results.totalEntryResults + entryMatchCount
                results.panelResults[#results.panelResults + 1] = {
                    containerId = containerId,
                    container = container,
                    panelId = panelId,
                    panel = panel,
                    panelMatches = panelMatches,
                    entryMatches = entryMatches,
                }
            end
        end
    end

    table.sort(results.panelResults, function(a, b)
        local orderA = a.container and CooldownCompanion:GetOrderForSpec(a.container, CooldownCompanion._currentSpecId, a.containerId) or 0
        local orderB = b.container and CooldownCompanion:GetOrderForSpec(b.container, CooldownCompanion._currentSpecId, b.containerId) or 0
        if orderA ~= orderB then
            return orderA < orderB
        end
        return (a.panel and a.panel.order or 0) < (b.panel and b.panel.order or 0)
    end)

    CS._configFinderResults = results
    CS._configFinderResultsQuery = query
    CS._configFinderResultsDb = db
    CS._configFinderResultsCharKey = charKey
    return results
end

local function SelectConfigFinderResult(containerId, panelId, buttonIndex)
    CooldownCompanion:ClearAllConfigPreviews()
    wipe(CS.selectedGroups)
    wipe(CS.selectedPanels)
    wipe(CS.selectedButtons)
    wipe(CS.selectedCustomBars)
    CS.selectedFolder = nil
    CS.selectedContainer = containerId
    CS.selectedGroup = panelId
    CS.selectedButton = buttonIndex
    CS.addingToPanelId = nil
    ClearConfigFinderText()
    CooldownCompanion:RefreshConfigPanel()
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
-- Shared icon picker helpers
------------------------------------------------------------------------
local STANDALONE_ICON_BROWSER_ADDON = "IconBrowser"
local CONFIG_ICON_PICKER_CACHE_KEYS = {
    "folderIconPickerFrame",
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

local FOLDER_ICON_PICKER_SPEC = {
    cacheKey = "folderIconPickerFrame",
    frameName = "CDCFolderIconPickerFrame",
    unavailableMessage = "Folder icon picker is unavailable on this client build.",
    configureFrame = ConfigureMovableIconPickerFrame,
    validateContext = function(context, db)
        local folderId = context and context.folderId
        return db and db.folders and db.folders[folderId]
    end,
    getCurrentIcon = function(folder, context, db)
        local currentIcon = folder.manualIcon
        if not IsValidIconTexture(currentIcon) then
            currentIcon = GetAutoFolderIcon(context.folderId, db)
        end
        return currentIcon
    end,
    applySelection = function(iconTexture, folder)
        folder.manualIcon = iconTexture
        CooldownCompanion:RefreshConfigPanel()
    end,
    clearContext = function(frame)
        frame._cdcPickerContext = nil
    end,
}

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
-- Folder icon picker
------------------------------------------------------------------------
local function OpenFolderIconPicker(folderId)
    return OpenConfigIconPicker(FOLDER_ICON_PICKER_SPEC, {
        folderId = folderId,
    })
end

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
-- Container icon picker (per-group icon in Column 1)
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

    if not compact then
        if hasIcon then
            leftPad = CONFIG_ROW_ICON_SIZE + CONFIG_ROW_ICON_GAP
        else
            leftPad = row.normalLeftPad or 0
        end
    end

    entry:SetHeight(COMPACT_ROW_HEIGHT)
    frame.height = COMPACT_ROW_HEIGHT

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
        icon:SetSize(CONFIG_ROW_ICON_SIZE, CONFIG_ROW_ICON_SIZE)
        icon:SetPoint("LEFT", frame, "LEFT", 0, 0)

        if hasIcon and not compact and (row.texture or row.atlas) then
            if row.atlas then
                icon:SetAtlas(row.atlas, false)
            else
                icon:SetAtlas(nil)
                icon:SetTexture(row.texture)
                icon:SetTexCoord(0, 1, 0, 1)
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
            ClearConfigRowLayout(self, true)
            if originalOnRelease then
                originalOnRelease(self)
            end
        end
        entry._cdcConfigRowReleaseHandlerInstalled = true
    end
end

local function CleanRecycledEntry(entry)
    local function CleanFrameButton(button)
        if not button then return end
        button:Hide()
        button:ClearAllPoints()
        button:SetScript("OnClick", nil)
        button:SetScript("OnEnter", nil)
        button:SetScript("OnLeave", nil)
    end

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
    if entry.frame._cdcAuraBadge then entry.frame._cdcAuraBadge:Hide() end
    if entry.frame._cdcFallbackBadge then entry.frame._cdcFallbackBadge:Hide() end
    if entry.frame._cdcTalentBadge then entry.frame._cdcTalentBadge:Hide() end
    if entry.frame._cdcCollapseIcon then entry.frame._cdcCollapseIcon:Hide() end
    if entry.frame._cdcCollapseBtn then entry.frame._cdcCollapseBtn:Hide() end
    if entry.frame._cdcAddBtn then entry.frame._cdcAddBtn:Hide() end
    if entry.frame._cdcGenericRenameBadge then entry.frame._cdcGenericRenameBadge:Hide() end
    if entry.frame._cdcCursorAnchorBadge then entry.frame._cdcCursorAnchorBadge:Hide() end
    if entry.frame._cdcAnchorBadge then entry.frame._cdcAnchorBadge:Hide() end
    if entry.frame._cdcHeaderDisabledBadge then entry.frame._cdcHeaderDisabledBadge:Hide() end
    if entry.frame._cdcDisabledBadge then entry.frame._cdcDisabledBadge:Hide() end
    if entry.frame._cdcCustomBarTypeBadge then entry.frame._cdcCustomBarTypeBadge:Hide() end
    if entry.frame._cdcCustomBarAuraStatusBadge then entry.frame._cdcCustomBarAuraStatusBadge:Hide() end
    if entry.frame._cdcCustomBarDisabledBadge then entry.frame._cdcCustomBarDisabledBadge:Hide() end
    if entry.frame._cdcFallbackRemoveBtn then entry.frame._cdcFallbackRemoveBtn:Hide() end
    if entry.frame._cdcPriorityUpBtn then entry.frame._cdcPriorityUpBtn:Hide() end
    if entry.frame._cdcPriorityDownBtn then entry.frame._cdcPriorityDownBtn:Hide() end
    if entry.frame._cdcFallbackUpBtn then entry.frame._cdcFallbackUpBtn:Hide() end
    if entry.frame._cdcFallbackDownBtn then entry.frame._cdcFallbackDownBtn:Hide() end
    CleanFrameButton(entry.frame._cdcCustomBarAuraUpBtn)
    CleanFrameButton(entry.frame._cdcCustomBarAuraDownBtn)
    if entry.frame._cdcMarkerLeft then entry.frame._cdcMarkerLeft:Hide() end
    if entry.frame._cdcMarkerRight then entry.frame._cdcMarkerRight:Hide() end
    entry._cdcAfterConfigRowLayout = nil
    entry.frame:SetScript("OnMouseUp", nil)
    entry.frame:SetScript("OnReceiveDrag", nil)
    entry.frame._cdcOnMouseDown = nil
    entry.frame._cdcLastClickTime = nil
    ClearConfigRowLayout(entry, true)
end

local function ApplyConfigRowIcon(entry, texture, opts)
    opts = opts or {}
    entry._cdcConfigRow = {
        kind = "icon",
        texture = texture,
        atlas = opts.atlas,
        desaturated = opts.desaturated == true,
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

local function UpdateConfigFolderAccentBars()
    local showBars = not CS.compactConfigRows
    for _, bar in ipairs(CS.folderAccentBars or {}) do
        if showBars and bar._cdcFolderAccentActive then
            bar:Show()
        else
            bar:Hide()
        end
    end
end

local function RefreshVisibleConfigCompactRows()
    ReapplyConfigRowLayouts(CS.col1Scroll)
    ReapplyConfigRowLayouts(CS.col2Scroll)
    UpdateConfigFolderAccentBars()
    if CS.col1Scroll and CS.col1Scroll.DoLayout then CS.col1Scroll:DoLayout() end
    if CS.col2Scroll and CS.col2Scroll.DoLayout then CS.col2Scroll:DoLayout() end
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
    if group.locked == false
        and not (CooldownCompanion.IsGroupCursorAnchored and CooldownCompanion:IsGroupCursorAnchored(group)) then
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

local function ClearSelectedButton()
    CS.selectedButton = nil
    wipe(CS.selectedButtons)
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

local function ClearConfigPrimarySelection()
    CooldownCompanion:ClearAllConfigPreviews()
    CS.selectedFolder = nil
    CS.selectedContainer = nil
    CS.selectedGroup = nil
    ClearSelectedButton()
    wipe(CS.selectedPanels)
    wipe(CS.selectedGroups)
    wipe(CS.selectedCustomBars)
end

local function SelectConfigFolder(folderId)
    CooldownCompanion:ClearAllConfigPreviews()
    CS.selectedFolder = folderId
    CS.selectedContainer = nil
    CS.selectedGroup = nil
    ClearSelectedButton()
    wipe(CS.selectedGroups)
    wipe(CS.selectedPanels)
end

local function SelectConfigContainer(containerId, opts)
    CooldownCompanion:ClearAllConfigPreviews()
    if not (opts and opts.keepContainerMulti) then
        wipe(CS.selectedGroups)
    end
    CS.selectedFolder = nil

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

    ClearSelectedButton()
    wipe(CS.selectedPanels)
    if opts and opts.clearFinder then
        ClearConfigFinderText()
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

    CS.selectedFolder = nil
    CS.selectedContainer = nil
    CS.selectedGroup = nil
    ClearSelectedButton()
    wipe(CS.selectedPanels)
    wipe(CS.selectedCustomBars)
end

local function SelectConfigPanel(panelId, opts)
    CooldownCompanion:ClearAllConfigPreviews()
    if opts and opts.containerId ~= nil then
        CS.selectedContainer = opts.containerId
    end
    if not (opts and opts.keepPanelMulti) then
        wipe(CS.selectedPanels)
    end

    if opts and opts.toggle and CS.selectedGroup == panelId and not CS.selectedButton then
        CS.selectedGroup = nil
    else
        CS.selectedGroup = panelId
    end

    ClearSelectedButton()
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
    ClearSelectedButton()
    CS.addingToPanelId = nil
end

local function SelectConfigButton(panelId, buttonIndex, opts)
    local panelChanged = CS.selectedGroup ~= panelId
    if opts and opts.containerId ~= nil then
        CS.selectedContainer = opts.containerId
    end
    if panelChanged then
        CS.selectedGroup = panelId
        ClearSelectedButton()
    end
    if not (opts and opts.keepPanelMulti) then
        wipe(CS.selectedPanels)
    end

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
    else
        wipe(CS.selectedButtons)
        if opts and opts.force then
            CS.selectedButton = buttonIndex
        elseif not panelChanged and CS.selectedButton == buttonIndex then
            CS.selectedButton = nil
        else
            CS.selectedButton = buttonIndex
        end
    end

    CooldownCompanion:ClearAllConfigPreviews()
end

local function SelectConfigButtonPanel(panelId, opts)
    if CS.selectedGroup ~= panelId then
        CooldownCompanion:ClearAllConfigPreviews()
        CS.selectedGroup = panelId
        ClearSelectedButton()
    end
    if opts and opts.clearPanelMulti then
        wipe(CS.selectedPanels)
    end
end

local function ClearConfigCustomBarPreviewState()
    if CooldownCompanion.ClearAllCustomAuraBarPreviews then
        CooldownCompanion:ClearAllCustomAuraBarPreviews()
    end
    if CS.customBarIndicatorPreviewActive and CooldownCompanion.StopResourceBarPreview then
        CooldownCompanion:StopResourceBarPreview()
    end
end

local function SetConfigCustomBarSettingsTab(tab, clearPreviewOnNonIndicator)
    CS.customBarSettingsTab = tab or "appearance"
    if clearPreviewOnNonIndicator and CS.customBarSettingsTab ~= "indicators" then
        ClearConfigCustomBarPreviewState()
    end
end

local function ClearConfigCustomBarSelection(clearPreview, opts)
    if clearPreview then
        ClearConfigCustomBarPreviewState()
    end
    CS.selectedCustomBarId = nil
    if opts and opts.clearExpanded then
        CS.customBarSpecExpandedId = nil
    end
    wipe(CS.selectedCustomBars)
    SetConfigCustomBarSettingsTab("appearance")
end

local function SelectConfigCustomBar(customBarId, opts)
    local selectionChanged = CS.selectedCustomBarId ~= customBarId
    if opts and opts.toggle and not selectionChanged then
        ClearConfigCustomBarSelection(opts.clearPreview)
        return true
    end

    if selectionChanged and opts and opts.clearPreview then
        ClearConfigCustomBarPreviewState()
    end
    CS.selectedCustomBarId = customBarId
    if opts and opts.resetTab then
        SetConfigCustomBarSettingsTab("appearance")
    end
    wipe(CS.selectedCustomBars)
    if opts and opts.clearButtonMulti then
        wipe(CS.selectedButtons)
    end
    return selectionChanged
end

local function ToggleConfigCustomBarMultiSelect(customBarId)
    if CS.selectedCustomBars[customBarId] then
        CS.selectedCustomBars[customBarId] = nil
    else
        CS.selectedCustomBars[customBarId] = true
    end
    if CS.selectedCustomBarId and not CS.selectedCustomBars[CS.selectedCustomBarId] and next(CS.selectedCustomBars) then
        CS.selectedCustomBars[CS.selectedCustomBarId] = true
    end
    ClearConfigCustomBarPreviewState()
end

local function PruneConfigCustomBarSelection(customBarExists, resetTab)
    if type(customBarExists) ~= "function" then
        return
    end

    if CS.selectedCustomBarId and not customBarExists(CS.selectedCustomBarId) then
        CS.selectedCustomBarId = nil
        if resetTab then
            SetConfigCustomBarSettingsTab("appearance")
        end
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

local function ResetConfigSelection(full)
    if full and ST._CancelAutoAddFlow then
        ST._CancelAutoAddFlow()
    end
    CooldownCompanion:ClearAllConfigPreviews()
    CS.selectedFolder = nil
    CS.selectedButton = nil
    CS.selectedCustomBarId = nil
    CS.customBarSpecExpandedId = nil
    CS.customBarSettingsTab = "appearance"
    wipe(CS.selectedButtons)
    wipe(CS.selectedPanels)
    wipe(CS.selectedCustomBars)
    if full then
        CS.selectedContainer = nil
        CS.selectedGroup = nil
        wipe(CS.selectedGroups)
        wipe(CS.selectedCustomBars)
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
        CooldownCompanion:ClearAllConfigPreviews()
        CS.selectedCustomBarId = nil
        CS.customBarSettingsTab = "appearance"
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

local function GroupsHaveForeignSpecs(groups, requireGlobal)
    local playerSpecIds = BuildPlayerSpecSet()
    for _, g in ipairs(groups) do
        if not requireGlobal or g.isGlobal then
            if SpecSetHasForeignSpecs(g.specs, playerSpecIds) then
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
ST._ApplyConfigRowIcon = ApplyConfigRowIcon
ST._ApplyConfigTextRow = ApplyConfigTextRow
ST._RefreshVisibleConfigCompactRows = RefreshVisibleConfigCompactRows
ST._AcquireBadge = AcquireBadge
ST._SetupGroupRowIndicators = SetupGroupRowIndicators
ST._SetupFolderRowIndicators = SetupFolderRowIndicators
ST._GetConfigRowBadgeReserve = GetConfigRowBadgeReserve
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
ST._GetConfigEntryDisplayName = GetConfigEntryDisplayName
ST._NormalizeConfigFinderText = NormalizeConfigFinderText
ST._IsConfigFinderAvailable = IsConfigFinderAvailable
ST._IsConfigFinderActive = IsConfigFinderActive
ST._SetConfigFinderText = SetConfigFinderText
ST._ClearConfigFinderText = ClearConfigFinderText
ST._BuildConfigFinderResults = BuildConfigFinderResults
ST._InvalidateConfigFinderResults = InvalidateConfigFinderResults
ST._SelectConfigFinderResult = SelectConfigFinderResult
ST._GetGroupIcon = GetGroupIcon
ST._GetContainerIcon = GetContainerIcon
ST._GetFolderIcon = GetFolderIcon
ST._OpenFolderIconPicker = OpenFolderIconPicker
ST._OpenButtonIconPicker = OpenButtonIconPicker
ST._OpenTriggerPanelIconPicker = OpenTriggerPanelIconPicker
ST._OpenContainerIconPicker = OpenContainerIconPicker
ST._CloseConfigIconPicker = CloseConfigIconPicker
ST._IsValidIconTexture = IsValidIconTexture
ST._GenerateFolderName = GenerateFolderName
ST._ShowPopupAboveConfig = ShowPopupAboveConfig
ST._BindConfigShiftTooltip = BindConfigShiftTooltip
ST._ConfigureWrappedHelperLabel = ConfigureWrappedHelperLabel
ST._ActivateConfigShiftTooltip = ActivateConfigShiftTooltip
ST._ClearConfigShiftTooltipHover = ClearConfigShiftTooltipHover
ST._ShowConfigShiftTooltip = ShowConfigShiftTooltip
ST._COLUMN_PADDING = COLUMN_PADDING
ST._BUTTON_HEIGHT = BUTTON_HEIGHT
ST._BUTTON_SPACING = BUTTON_SPACING
ST._PROFILE_BAR_HEIGHT = PROFILE_BAR_HEIGHT
ST._BuildHeroTalentSubTreeCheckboxes = BuildHeroTalentSubTreeCheckboxes
ST._ApplyCheckboxIndent = ApplyCheckboxIndent
ST._ClearConfigButtonSelection = ClearConfigButtonSelection
ST._ClearConfigPanelSelection = ClearConfigPanelSelection
ST._ClearConfigContainerSelection = ClearConfigContainerSelection
ST._ClearConfigPanelMultiSelection = ClearConfigPanelMultiSelection
ST._ClearConfigContainerMultiSelection = ClearConfigContainerMultiSelection
ST._ClearConfigPrimarySelection = ClearConfigPrimarySelection
ST._SelectConfigFolder = SelectConfigFolder
ST._SelectConfigContainer = SelectConfigContainer
ST._ToggleConfigContainerMultiSelect = ToggleConfigContainerMultiSelect
ST._SelectConfigPanel = SelectConfigPanel
ST._ToggleConfigPanelMultiSelect = ToggleConfigPanelMultiSelect
ST._SelectConfigButton = SelectConfigButton
ST._SelectConfigButtonPanel = SelectConfigButtonPanel
ST._ClearConfigCustomBarPreviewState = ClearConfigCustomBarPreviewState
ST._SetConfigCustomBarSettingsTab = SetConfigCustomBarSettingsTab
ST._ClearConfigCustomBarSelection = ClearConfigCustomBarSelection
ST._SelectConfigCustomBar = SelectConfigCustomBar
ST._ToggleConfigCustomBarMultiSelect = ToggleConfigCustomBarMultiSelect
ST._PruneConfigCustomBarSelection = PruneConfigCustomBarSelection
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
