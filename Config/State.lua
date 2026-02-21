--[[
    CooldownCompanion - Config/State
    Shared mutable state, constants, core helpers, and UI building blocks.
    All cross-file state lives in ST._configState (aliased as CS).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local AceGUI = LibStub("AceGUI-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

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
    selectedGroup = nil,
    selectedButton = nil,
    selectedButtons = {},
    selectedGroups = {},
    selectedTab = "appearance",
    buttonSettingsTab = "settings",
    newInput = "",

    -- Main frame reference
    configFrame = nil,

    -- Column content frames
    col1Scroll = nil,
    col1ButtonBar = nil,
    col2Scroll = nil,
    col4Container = nil,
    col4Scroll = nil,

    -- AceGUI widget tracking for cleanup
    col1BarWidgets = {},
    profileBarAceWidgets = {},
    buttonSettingsInfoButtons = {},

    buttonSettingsScroll = nil,
    columnInfoButtons = {},
    moveMenuFrame = nil,
    groupContextMenu = nil,
    buttonContextMenu = nil,
    gearDropdownFrame = nil,
    folderContextMenu = nil,

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
    folderAccentBars = {},

    -- Autocomplete state
    autocompleteCache = nil,
    pendingEditBoxFocus = false,

    -- Spec filter inline expansion
    specExpandedGroupId = nil,

    -- Tab UI state (populated by ConfigSettings, cleaned by both files)
    tabInfoButtons = {},
    appearanceTabElements = {},
    castBarPanelActive = false,
    resourceBarPanelActive = false,
    frameAnchoringPanelActive = false,

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
    local dialog = StaticPopup_Show(which, text_arg1)
    if dialog then
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(200)
        if data then
            dialog.data = data
        end
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
-- Helper: Get icon for a folder (from its first child group's first button)
------------------------------------------------------------------------
local function GetFolderIcon(folderId, db)
    local children = {}
    for gid, group in pairs(db.groups) do
        if group.folderId == folderId then
            table.insert(children, { id = gid, order = group.order or gid })
        end
    end
    table.sort(children, function(a, b) return a.order < b.order end)
    if children[1] then
        local group = db.groups[children[1].id]
        if group then
            return GetGroupIcon(group)
        end
    end
    return 134400
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
    if entry.frame._cdcCollapseIcon then entry.frame._cdcCollapseIcon:Hide() end
    entry.image:SetAlpha(1)
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
    -- Spec filter badges
    local SPEC_BADGE_SIZE = 16
    if group.specs and next(group.specs) then
        for specId in pairs(group.specs) do
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
-- ST._ exports (consumed by later Config/ files at load time)
------------------------------------------------------------------------
ST._CDM_VIEWER_NAMES = CDM_VIEWER_NAMES
ST._CleanRecycledEntry = CleanRecycledEntry
ST._AcquireBadge = AcquireBadge
ST._SetupGroupRowIndicators = SetupGroupRowIndicators
ST._CreateScrollFrame = CreateScrollFrame
ST._CreateTextButton = CreateTextButton
ST._EmbedWidget = EmbedWidget
ST._GetButtonIcon = GetButtonIcon
ST._GetGroupIcon = GetGroupIcon
ST._GetFolderIcon = GetFolderIcon
ST._GenerateFolderName = GenerateFolderName
ST._ShowPopupAboveConfig = ShowPopupAboveConfig
ST._COLUMN_PADDING = COLUMN_PADDING
ST._BUTTON_HEIGHT = BUTTON_HEIGHT
ST._BUTTON_SPACING = BUTTON_SPACING
ST._PROFILE_BAR_HEIGHT = PROFILE_BAR_HEIGHT
