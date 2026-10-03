--[[
    CooldownCompanion - Config/ButtonsWideColumn
    Workspace for the plain buttons view and Other Class browsing:
    hosts the entry settings surfaces (bsTabGroup, entry multi-select),
    the panel batch actions, and the group-side settings surfaces (via
    GroupSettingsHost) in one unified surface. It frames two labeled areas:
    the pinned Live Preview in the center column (the column title names
    it) and the editing surface in the Settings column to its right
    (the "Editing:" path and selected-entry context on one line,
    followed by the add box and settings).
    Other Class browsing uses the same pinned preview cluster, so it never
    needs to surface browsed panels in the live world.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")
local ShouldSubmitRawAddOnEnter = ST._ShouldSubmitRawAddOnEnter
local CreateAddBoxInfoButton = ST._CreateAddBoxInfoButton

local PREVIEW_GAP = 4
-- Standalone resources use this parent crumb; attached objects use their panel.
local BARS_HOME_LABEL = "Resource Bars"
local ADD_BOX_HEIGHT = 26
local EDIT_ACTION_FIELD_GAP = 6
local EDIT_CONTEXT_ICON_SIZE = 16
local EDIT_CONTEXT_BADGE_SIZE = 16
local EDIT_CONTEXT_BADGE_GAP = 3
local EDIT_INSET = 6
local EDIT_HEADER_TOP_GAP = 6
local EDIT_HEADER_HEIGHT = 18
local EDIT_HEADER_GAP = 5
local EDIT_BOTTOM_INSET = 6
local EDIT_CHIPS_HEIGHT = 18
local EDIT_CHIPS_GAP = 4
local EDIT_CHIPS_MORE_GAP = 8
local UpdatePanelWorkspaceChips
local EDIT_ACTION_FIELD_LEFT_NUDGE = -1
local SETTINGS_FINDER_MAX_ROWS = 8
local SETTINGS_FINDER_ROW_HEIGHT = 25
local SETTINGS_FINDER_FOOTER_HEIGHT = 19

local settingsFinderDropdown

local SETTINGS_FINDER_TOOLTIP = {
    "Find Setting",
    {"Searches every setting for the object you are currently editing, including other tabs, collapsed sections, and Advanced settings.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Choose a result to open its location and highlight the setting.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"It does not search other Groups, Panels, or Entries.", 0.65, 0.65, 0.65, true},
}

local function AnchorWidePreviewHost(col3, host)
    host:ClearAllPoints()
    if col3._cdcEmptyGroupPreviewTakeover then
        host:SetAllPoints(col3.content)
    else
        host:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
        host:SetPoint("TOPRIGHT", col3.content, "TOPRIGHT", 0, 0)
    end
end

local function HideEntrySurfaces(col3)
    if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
    if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
end

-- The wide col3 layout hosts exactly one pinned preview at a time: the
-- buttons panel mirror or the Resources home's Layout & Order preview.
-- The host height and resize rebuild below are shared; each view registers
-- its host frame and rebuild function while its preview is showing, and
-- clears the registration when it hides.
local function SetActiveWidePreview(col3, host, rebuild)
    AnchorWidePreviewHost(col3, host)
    col3._cdcActiveWideHost = host
    col3._cdcActiveWideRebuild = rebuild
end

local function ClearActiveWidePreview(col3, host)
    if col3._cdcActiveWideHost == host then
        col3._cdcActiveWideHost = nil
        col3._cdcActiveWideRebuild = nil
    end
end

local function RebuildActiveWidePreview(col3)
    local host = col3._cdcActiveWideHost
    local rebuild = col3._cdcActiveWideRebuild
    if host and rebuild then
        rebuild(host)
    end
end

-- Structural container in the Settings column. It hosts the Editing path
-- (including any selected entry context), the add box, and the settings
-- surfaces.
local function EnsureEditingSurface(col3)
    local surface = col3._cdcEditingSurface
    if surface then return surface end

    surface = CreateFrame("Frame", nil, col3.content)
    -- Keep the structural host at content level; its child header and
    -- badges then sit alongside the sibling settings widgets.
    surface:SetFrameLevel(col3.content:GetFrameLevel())

    local headerLine = CreateFrame("Frame", nil, surface)
    headerLine:SetPoint("TOPLEFT", surface, "TOPLEFT", EDIT_INSET, -EDIT_HEADER_TOP_GAP)
    headerLine:SetPoint("TOPRIGHT", surface, "TOPRIGHT", -EDIT_INSET, -EDIT_HEADER_TOP_GAP)
    headerLine:SetHeight(EDIT_HEADER_HEIGHT)
    headerLine.badges = {}

    local text = headerLine:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", headerLine, "LEFT", 0, 0)
    text:SetPoint("RIGHT", headerLine, "RIGHT", 0, 0)
    text:SetHeight(EDIT_HEADER_HEIGHT)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    headerLine.text = text

    -- Breadcrumb pieces: when the path has clickable ancestor scopes, the
    -- line renders as the "Editing: " prefix + one crumb button per
    -- ancestor + the main text (the current selection). With no clickable
    -- ancestors everything but the main text stays hidden and it renders
    -- the whole line exactly as before.
    local prefix = headerLine:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    prefix:SetPoint("LEFT", headerLine, "LEFT", 0, 0)
    prefix:SetHeight(EDIT_HEADER_HEIGHT)
    prefix:SetJustifyH("LEFT")
    prefix:SetWordWrap(false)
    prefix:Hide()
    headerLine.prefix = prefix
    headerLine.crumbs = {}

    surface._cdcHeader = headerLine

    col3._cdcEditingSurface = surface
    return surface
end

local function GetActiveEditingAddBox(col3)
    local alternate = col3._cdcAlternateEditingAddBox
    if alternate and alternate.frame and alternate.frame:IsShown() then
        return alternate
    end
    local panelAddBox = col3.buttonsAddBox
    if panelAddBox and panelAddBox.frame and panelAddBox.frame:IsShown() then
        return panelAddBox
    end
    return nil
end


local function SetWideEditingAddBox(col3, widget)
    local previous = col3._cdcAlternateEditingAddBox
    if previous and previous ~= widget and previous.frame then
        previous.frame:Hide()
    end
    col3._cdcAlternateEditingAddBox = widget
    if widget and widget.frame then
        widget.frame._cdcEditingHeight = widget.frame._cdcEditingHeight or ADD_BOX_HEIGHT
        widget.frame:Show()
    end
end

------------------------------------------------------------------------
-- Editing action row: Add Entry + Settings Finder
------------------------------------------------------------------------

local SettingsFinderActionBehavior = {}

local function HasMultipleSelections(selection)
    local count = 0
    for _ in pairs(selection or {}) do
        count = count + 1
        if count >= 2 then return true end
    end
    return false
end

function SettingsFinderActionBehavior.IsSuppressed(state)
    state = state or {}
    return state.importMode ~= nil
        or state.exportMode ~= nil
        or state.talentPickerMode == true
        or state.inlineTextureBrowserOpen ~= nil
        or state.auraTexturePickerOpen == true
        or state.emptyGroupPreviewTakeover == true
        or HasMultipleSelections(state.selectedGroups)
        or HasMultipleSelections(state.selectedPanels)
        or HasMultipleSelections(state.selectedButtons)
end

function SettingsFinderActionBehavior.IsQueuedSearchCurrent(serial, currentSerial)
    return serial == currentSerial
end

function SettingsFinderActionBehavior.ResolveKey(highlightIndex, numResults, key)
    local selected = tonumber(highlightIndex) or 0
    local count = math.max(0, tonumber(numResults) or 0)
    if key == "ESCAPE" then
        return selected, "clear"
    elseif count == 0 then
        return selected, nil
    elseif key == "DOWN" then
        return (selected % count) + 1, "move"
    elseif key == "UP" then
        selected = selected - 1
        if selected < 1 then selected = count end
        return selected, "move"
    elseif key == "ENTER" then
        return selected, "select"
    end
    return selected, nil
end

function SettingsFinderActionBehavior.CanSelectResult(
    expectedIdentity, currentIdentity, descriptorApplicable)
    if expectedIdentity == nil or currentIdentity == nil
        or expectedIdentity ~= currentIdentity
    then
        return false
    end
    return descriptorApplicable ~= false
end

function SettingsFinderActionBehavior.GetPopupHandoff(owner)
    if owner == "finder" then
        return false, true
    elseif owner == "add" then
        return true, false
    end
    return false, false
end

-- Internal, deterministic state transitions shared by the UI handlers and
-- the plain-Lua action-row behavior contract. This is not an addon API.
ST._SettingsFinderActionRowBehavior = SettingsFinderActionBehavior

local function IsEditingActionRowSuppressed(col3)
    return SettingsFinderActionBehavior.IsSuppressed({
        importMode = CS.importMode ~= nil and true or nil,
        exportMode = CS.exportMode ~= nil and true or nil,
        talentPickerMode = CS.talentPickerMode,
        inlineTextureBrowserOpen = CS.inlineTextureBrowserOpen,
        auraTexturePickerOpen = CS.IsAuraTexturePickerOpen
            and CS.IsAuraTexturePickerOpen() == true,
        emptyGroupPreviewTakeover = col3._cdcEmptyGroupPreviewTakeover,
        selectedGroups = CS.selectedGroups,
        selectedPanels = CS.selectedPanels,
        selectedButtons = CS.selectedButtons,
    })
end

local function GetSettingsFinderContextIdentity(context)
    if not context then return nil end
    if ST._GetSettingsFinderContextIdentity then
        return ST._GetSettingsFinderContextIdentity(context)
    end
    return context.identity
end

local function HideSettingsFinderResults()
    if settingsFinderDropdown then
        settingsFinderDropdown:Hide()
    end
end

-- Resolve at use time rather than storing an anchor on pooled Add widgets.
-- The active input may be the persistent panel box or a rebuilt Add box.
ST._GetEditingAddResultsAnchor = function(input)
    local col3 = CS.configFrame and CS.configFrame.col3
    local row = col3 and col3._cdcEditingActionRow
    local widget = row and row._cdcAddBox
    local activeInput = widget and (widget.editbox and widget or widget._cdcAddInput)
    if row and row:IsVisible()
        and input and input == activeInput
    then
        return row
    end
end

local function ApplyEditingActionPopupHandoff(owner)
    local closeFinder, closeAdd = SettingsFinderActionBehavior.GetPopupHandoff(owner)
    if closeFinder then
        HideSettingsFinderResults()
    end
    if closeAdd then
        if CS.HideAutocomplete then CS.HideAutocomplete() end
    end
end

-- Spell/item autocomplete calls this before showing its own popup. Keeping
-- that mutual exclusion at the popup boundary also covers alternate Add
-- widgets.
CS.HideSettingsFinderResults = function()
    ApplyEditingActionPopupHandoff("add")
end

local function UpdateSettingsFinderPlaceholder(widget)
    if not (widget and widget._cdcInstructions) then return end
    widget._cdcInstructions:SetShown((widget:GetText() or "") == "")
end

local function ClearSettingsFinderUI(col3, clearFocus, clearNavigation)
    HideSettingsFinderResults()
    col3._cdcSettingsFinderSearchSerial = (col3._cdcSettingsFinderSearchSerial or 0) + 1
    col3._cdcSettingsFinderRestoreFocus = nil
    local widget = col3._cdcSettingsFinder
    if widget then
        if widget:GetText() ~= "" then
            widget:SetText("")
        end
        UpdateSettingsFinderPlaceholder(widget)
        if clearFocus and widget.editbox then
            widget:ClearFocus()
        end
    end
    if clearNavigation and ST._ClearSettingsFinderNavigation then
        ST._ClearSettingsFinderNavigation()
    end
end

-- Config visibility can change without releasing the preserved AceGUI
-- workspace (the minimized puck is the important case). Keep the owner-side
-- reset here so callers do not need to know about the Finder's popup, query,
-- or captured object identity individually.
local function ClearSettingsFinderActionRowState(col3)
    if not col3 then return end
    col3._cdcSettingsFinderContext = nil
    col3._cdcSettingsFinderContextIdentity = nil
    ClearSettingsFinderUI(col3, true, true)
end

ST._ClearSettingsFinderActionRowState = ClearSettingsFinderActionRowState

-- Ordinary settings refreshes rebuild the edited surface without changing
-- the edited object. Preserve the persistent field's query/focus, but discard
-- its applicability context so newly shown or hidden settings are recomputed.
-- Full view changes continue to use ClearSettingsFinderActionRowState.
local function PrepareSettingsFinderActionRowRefresh(col3)
    if not col3 then return end
    HideSettingsFinderResults()
    col3._cdcSettingsFinderSearchSerial = (col3._cdcSettingsFinderSearchSerial or 0) + 1
    local widget = col3._cdcSettingsFinder
    if widget and widget.frame:IsShown() and widget.editbox:HasFocus() then
        col3._cdcSettingsFinderRestoreFocus = true
    end
    col3._cdcSettingsFinderContext = nil
end

local function UpdateSettingsFinderHighlight(dropdown)
    local selected = dropdown and dropdown._highlightIndex or 0
    for index, row in ipairs((dropdown and dropdown.rows) or {}) do
        row.selectionBg:SetShown(index == selected and row:IsShown())
    end
end

local function SelectSettingsFinderResult(col3, descriptor, context, contextIdentity)
    if not (descriptor and context and ST._NavigateToFinderSetting) then
        ClearSettingsFinderUI(col3, true, true)
        return
    end

    local current = ST._GetSettingsFinderContext and ST._GetSettingsFinderContext()
    local currentIdentity = GetSettingsFinderContextIdentity(current)
    local descriptorApplicable
    if currentIdentity ~= nil and currentIdentity == contextIdentity
        and ST._IsSettingsFinderDescriptorApplicable
    then
        descriptorApplicable = ST._IsSettingsFinderDescriptorApplicable(
            descriptor, current) == true
    end
    if not SettingsFinderActionBehavior.CanSelectResult(
        contextIdentity, currentIdentity, descriptorApplicable)
    then
        ClearSettingsFinderUI(col3, true, true)
        return
    end

    -- Navigation owns the pending highlight from this point forward. Clear
    -- only finder UI here; clearing engine state after navigation would cancel
    -- the exact-row pulse it just queued.
    ClearSettingsFinderUI(col3, true, false)
    if not ST._NavigateToFinderSetting(descriptor, current)
        and ST._ClearSettingsFinderNavigation then
        ST._ClearSettingsFinderNavigation()
    end
end

local function GetOrCreateSettingsFinderDropdown(col3)
    if settingsFinderDropdown then return settingsFinderDropdown end

    local dropdown = CreateFrame(
        "Frame", "CooldownCompanionSettingsFinderResults", UIParent, "BackdropTemplate")
    dropdown:SetFrameStrata("TOOLTIP")
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    dropdown:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    ST.CreatePixelBorders(dropdown, 0, 0, 0, 1)
    dropdown:Hide()
    dropdown.rows = {}

    for index = 1, SETTINGS_FINDER_MAX_ROWS do
        local row = CreateFrame("Button", nil, dropdown)
        row:RegisterForClicks("AnyUp")
        row:SetHeight(SETTINGS_FINDER_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 1,
            -1 - ((index - 1) * SETTINGS_FINDER_ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -1,
            -1 - ((index - 1) * SETTINGS_FINDER_ROW_HEIGHT))

        local selectionBg = row:CreateTexture(nil, "BACKGROUND")
        selectionBg:SetPoint("TOPLEFT", row, "TOPLEFT", -1, index == 1 and 1 or 0)
        selectionBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 1, 0)
        selectionBg:SetColorTexture(0.2, 0.4, 0.7, 0.4)
        selectionBg:Hide()
        row.selectionBg = selectionBg

        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetPoint("TOPLEFT", row, "TOPLEFT", -1, index == 1 and 1 or 0)
        hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 1, 0)
        hover:SetColorTexture(0.3, 0.5, 0.8, 0.3)

        local breadcrumb = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        breadcrumb:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        breadcrumb:SetWidth(96)
        breadcrumb:SetJustifyH("RIGHT")
        breadcrumb:SetWordWrap(false)
        row.breadcrumb = breadcrumb

        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", row, "LEFT", 7, 0)
        name:SetPoint("RIGHT", breadcrumb, "LEFT", -8, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        row.nameText = name
        row._cdcFinderIndex = index

        row:SetScript("OnMouseDown", function()
            dropdown._clickInProgress = true
        end)
        row:SetScript("OnMouseUp", function()
            -- A press dragged off the row does not fire OnClick. Always
            -- release this focus-handoff guard on mouse-up so an abandoned
            -- click cannot pin the results popup open.
            dropdown._clickInProgress = false
        end)
        row:SetScript("OnEnter", function()
            dropdown._highlightIndex = row._cdcFinderIndex
            UpdateSettingsFinderHighlight(dropdown)
        end)
        row:SetScript("OnClick", function()
            dropdown._clickInProgress = false
            if row.descriptor then
                SelectSettingsFinderResult(
                    col3, row.descriptor, dropdown._context, dropdown._contextIdentity)
            end
        end)
        row:Hide()
        dropdown.rows[index] = row
    end

    local footer = dropdown:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", dropdown, "BOTTOMLEFT", 7, 2)
    footer:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -7, 2)
    footer:SetJustifyH("CENTER")
    footer:SetText("Keep typing to narrow results")
    footer:Hide()
    dropdown.footer = footer

    dropdown:SetScript("OnUpdate", function(self)
        if self._clickInProgress then return end
        if not (self._editbox and self._editbox:HasFocus()) then
            self:Hide()
        end
    end)
    dropdown:SetScript("OnHide", function(self)
        self._clickInProgress = nil
        self._editbox = nil
        self._context = nil
        self._contextIdentity = nil
        self._highlightIndex = nil
        self._numResults = nil
        if self.footer then self.footer:Hide() end
        for _, row in ipairs(self.rows or {}) do
            row.descriptor = nil
            row.selectionBg:Hide()
            row:Hide()
        end
    end)

    settingsFinderDropdown = dropdown
    return dropdown
end

local function ShowSettingsFinderResults(col3, results, truncated, context, contextIdentity)
    local widget = col3._cdcSettingsFinder
    if not (widget and widget.frame:IsShown() and results and #results > 0) then
        HideSettingsFinderResults()
        return
    end

    ApplyEditingActionPopupHandoff("finder")

    local dropdown = GetOrCreateSettingsFinderDropdown(col3)
    dropdown._editbox = widget.editbox
    dropdown._context = context
    dropdown._contextIdentity = contextIdentity
    dropdown._highlightIndex = 1
    dropdown._numResults = math.min(#results, SETTINGS_FINDER_MAX_ROWS)

    local finderWidth = math.max(1, widget.frame:GetWidth() or 1)
    local actionRow = col3._cdcEditingActionRow
    local fullRowResults = actionRow and actionRow:IsVisible()
    local widestName = 0
    local widestBreadcrumb = 0

    for index = 1, SETTINGS_FINDER_MAX_ROWS do
        local row = dropdown.rows[index]
        local descriptor = results[index]
        if descriptor then
            local breadcrumb = descriptor.breadcrumb
            if not breadcrumb or breadcrumb == "" then
                local pieces = {}
                if descriptor.tabLabel and descriptor.tabLabel ~= "" then
                    pieces[#pieces + 1] = descriptor.tabLabel
                end
                if descriptor.sectionLabel and descriptor.sectionLabel ~= "" then
                    pieces[#pieces + 1] = descriptor.sectionLabel
                end
                breadcrumb = table.concat(pieces, " \194\187 ")
            end
            row.descriptor = descriptor
            row.nameText:SetText(descriptor.label or "Setting")
            row.breadcrumb:SetText(breadcrumb or "")
            widestName = math.max(
                widestName, row.nameText:GetUnboundedStringWidth() or 0)
            widestBreadcrumb = math.max(
                widestBreadcrumb, row.breadcrumb:GetUnboundedStringWidth() or 0)
            row:Show()
        else
            row.descriptor = nil
            row:Hide()
        end
    end

    -- Keep compact one-line results spanning the whole editing row, so
    -- labels and routes do not compete for the Finder field's half-row width.
    local resultHorizontalPadding = 1 + 7 + 8 + 6 + 1
    local dropdownWidth = fullRowResults
        and math.max(1, actionRow:GetWidth() or 1) or finderWidth
    local breadcrumbWidth = math.min(
        math.ceil(widestBreadcrumb + 1),
        math.max(72, dropdownWidth - math.ceil(widestName) - resultHorizontalPadding))
    for _, row in ipairs(dropdown.rows) do
        row.breadcrumb:SetWidth(breadcrumbWidth)
    end

    dropdown:ClearAllPoints()
    if fullRowResults then
        dropdown:SetPoint("TOPLEFT", actionRow, "BOTTOMLEFT", 0, -2)
        dropdown:SetPoint("TOPRIGHT", actionRow, "BOTTOMRIGHT", 0, -2)
    else
        dropdown:SetPoint("TOPRIGHT", widget.frame, "BOTTOMRIGHT", 0, -2)
        dropdown:SetWidth(dropdownWidth)
    end

    dropdown.footer:SetShown(truncated == true)
    local footerHeight = truncated and SETTINGS_FINDER_FOOTER_HEIGHT or 0
    dropdown:SetHeight(2 + (dropdown._numResults * SETTINGS_FINDER_ROW_HEIGHT) + footerHeight)
    dropdown:Show()
    UpdateSettingsFinderHighlight(dropdown)
end

local function RunSettingsFinderSearch(col3, serial)
    if not SettingsFinderActionBehavior.IsQueuedSearchCurrent(
        serial, col3._cdcSettingsFinderSearchSerial)
    then
        return
    end
    local widget = col3._cdcSettingsFinder
    if not (widget and widget.frame:IsShown() and widget.editbox:HasFocus()) then
        HideSettingsFinderResults()
        return
    end

    local context = col3._cdcSettingsFinderContext
    local contextIdentity = GetSettingsFinderContextIdentity(context)
    local contextIsCurrent = context ~= nil
        and (not ST._IsSettingsFinderContextCurrent
            or ST._IsSettingsFinderContextCurrent(context) == true)
    if not contextIsCurrent
        or contextIdentity ~= col3._cdcSettingsFinderContextIdentity
    then
        ClearSettingsFinderUI(col3, true, true)
        return
    end

    if not ST._SearchSettingsFinder then
        HideSettingsFinderResults()
        return
    end
    local results, truncated = ST._SearchSettingsFinder(widget:GetText() or "", context,
        SETTINGS_FINDER_MAX_ROWS)
    ShowSettingsFinderResults(col3, results, truncated, context, contextIdentity)
end

local function QueueSettingsFinderSearch(col3)
    col3._cdcSettingsFinderSearchSerial = (col3._cdcSettingsFinderSearchSerial or 0) + 1
    local serial = col3._cdcSettingsFinderSearchSerial
    C_Timer.After(0, function()
        RunSettingsFinderSearch(col3, serial)
    end)
end

local function HandleSettingsFinderKeyDown(col3, key)
    local supportedKey = key == "ESCAPE" or key == "DOWN"
        or key == "UP" or key == "ENTER"
    if not supportedKey then return end
    local dropdown = settingsFinderDropdown
    local nextIndex, action = SettingsFinderActionBehavior.ResolveKey(
        dropdown and dropdown._highlightIndex,
        dropdown and dropdown:IsShown() and dropdown._numResults or 0,
        key)
    if action == "clear" then
        ClearSettingsFinderUI(col3, true, true)
        return
    end
    if not (dropdown and dropdown:IsShown() and dropdown._numResults > 0) then return end

    if action == "move" then
        dropdown._highlightIndex = nextIndex
        UpdateSettingsFinderHighlight(dropdown)
    elseif action == "select" then
        local row = dropdown.rows[nextIndex]
        if row and row.descriptor then
            SelectSettingsFinderResult(
                col3, row.descriptor, dropdown._context, dropdown._contextIdentity)
        end
    end
end

local function EnsureSettingsFinder(col3)
    local widget = col3._cdcSettingsFinder
    if widget then return widget end

    widget = AceGUI:Create("EditBox")
    if widget.editbox.Instructions then widget.editbox.Instructions:Hide() end
    widget:SetLabel("")
    widget:SetText("")
    widget:DisableButton(true)
    widget.frame:SetParent(EnsureEditingSurface(col3))
    widget.frame._cdcEditingHeight = ADD_BOX_HEIGHT
    widget.editbox:SetPoint("BOTTOMRIGHT", widget.frame, "BOTTOMRIGHT", -18, 0)

    if ST._CreateInfoButton then
        widget._cdcFinderInfoButton = ST._CreateInfoButton(
            widget.frame, widget.frame, "RIGHT", "RIGHT", -1, 0,
            SETTINGS_FINDER_TOOLTIP)
    end

    local instructions = widget.editbox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    instructions:SetPoint("LEFT", widget.editbox, "LEFT", 6, 0)
    instructions:SetPoint("RIGHT", widget.editbox, "RIGHT", -6, 0)
    instructions:SetJustifyH("LEFT")
    instructions:SetTextColor(0.5, 0.5, 0.5)
    instructions:SetText("Search...")
    widget._cdcInstructions = instructions

    widget:SetCallback("OnTextChanged", function(_, _, text)
        instructions:SetShown((text or "") == "")
        ApplyEditingActionPopupHandoff("finder")
        QueueSettingsFinderSearch(col3)
    end)
    widget.editbox:HookScript("OnKeyDown", function(_, key)
        HandleSettingsFinderKeyDown(col3, key)
    end)
    widget.editbox:HookScript("OnEditFocusGained", function()
        ApplyEditingActionPopupHandoff("finder")
        QueueSettingsFinderSearch(col3)
    end)

    col3._cdcSettingsFinder = widget
    return widget
end

local function LayoutEditingActionRow(col3)
    local row = col3._cdcEditingActionRow
    if not (row and row:IsShown()) then return end

    local addBox = row._cdcAddBox
    local finder = row._cdcFinder
    local hasAdd = addBox and addBox.frame and addBox.frame:IsShown()
    local hasFinder = finder and finder.frame and finder.frame:IsShown()
    if not (hasAdd or hasFinder) then
        row:Hide()
        return
    end

    local height = ADD_BOX_HEIGHT
    if hasAdd then
        -- Anchors alone do not inherit the settings column's visibility.
        -- Both the normal and alternate add fields belong to this action row.
        addBox.frame:SetParent(row)
        height = math.max(height, addBox.frame._cdcEditingHeight or ADD_BOX_HEIGHT)
    end
    row:SetHeight(height)
    row._cdcEditingHeight = height
    if hasAdd and hasFinder then
        -- The Settings column is narrow, so the two fields split it evenly.
        local rowWidth = math.max(1, row:GetWidth() or 1)
        local fieldGap = EDIT_ACTION_FIELD_GAP
        local finderWidth = math.max(1, (rowWidth - fieldGap) / 2)

        finder.frame:ClearAllPoints()
        finder.frame:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        finder.frame:SetWidth(finderWidth)
        finder.frame:SetHeight(ADD_BOX_HEIGHT)

        addBox.frame:ClearAllPoints()
        addBox.frame:SetPoint(
            "LEFT", row, "LEFT", EDIT_ACTION_FIELD_LEFT_NUDGE, 0)
        addBox.frame:SetPoint("RIGHT", finder.frame, "LEFT", -fieldGap, 0)
        addBox.frame:SetHeight(addBox.frame._cdcEditingHeight or ADD_BOX_HEIGHT)
    elseif hasFinder then
        finder.frame:ClearAllPoints()
        finder.frame:SetPoint(
            "LEFT", row, "LEFT", EDIT_ACTION_FIELD_LEFT_NUDGE, 0)
        finder.frame:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        finder.frame:SetHeight(ADD_BOX_HEIGHT)
    else
        addBox.frame:ClearAllPoints()
        addBox.frame:SetPoint(
            "LEFT", row, "LEFT", EDIT_ACTION_FIELD_LEFT_NUDGE, 0)
        addBox.frame:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        addBox.frame:SetHeight(addBox.frame._cdcEditingHeight or ADD_BOX_HEIGHT)
    end
end

local function EnsureEditingActionRow(col3)
    local row = col3._cdcEditingActionRow
    if row then return row end

    local surface = EnsureEditingSurface(col3)
    row = CreateFrame("Frame", nil, surface)
    row:SetPoint("TOPLEFT", surface._cdcHeader, "BOTTOMLEFT", 0, -EDIT_HEADER_GAP)
    row:SetPoint("TOPRIGHT", surface._cdcHeader, "BOTTOMRIGHT", 0, -EDIT_HEADER_GAP)
    row:SetHeight(ADD_BOX_HEIGHT)
    row:SetScript("OnSizeChanged", function()
        LayoutEditingActionRow(col3)
    end)
    col3._cdcEditingActionRow = row
    return row
end

local function UpdateEditingActionRow(col3)
    local row = EnsureEditingActionRow(col3)
    local addBox = GetActiveEditingAddBox(col3)
    local previousContextIdentity = col3._cdcSettingsFinderContextIdentity
    local restoreFinderFocus = col3._cdcSettingsFinderRestoreFocus == true
    local finderEngineLoaded = type(ST._GetSettingsFinderContext) == "function"
    local context = col3._cdcSettingsFinderContext
    if not (context and ST._IsSettingsFinderContextCurrent
        and ST._IsSettingsFinderContextCurrent(context))
    then
        context = finderEngineLoaded and ST._GetSettingsFinderContext() or nil
    end
    local contextIdentity = GetSettingsFinderContextIdentity(context)
    local suppressed = IsEditingActionRowSuppressed(col3)
    local hasFinderEntries = context ~= nil
        and (not ST._HasSettingsFinderEntries
            or ST._HasSettingsFinderEntries(context) == true)
    local showFinder = not suppressed and hasFinderEntries and contextIdentity ~= nil
    local resumeFinder = restoreFinderFocus and showFinder
        and previousContextIdentity ~= nil
        and previousContextIdentity == contextIdentity

    if previousContextIdentity ~= contextIdentity or not showFinder then
        ClearSettingsFinderUI(col3, true, true)
    end
    col3._cdcSettingsFinderContext = showFinder and context or nil
    col3._cdcSettingsFinderContextIdentity = showFinder and contextIdentity or nil

    local finder = col3._cdcSettingsFinder
    if showFinder then
        finder = EnsureSettingsFinder(col3)
        finder.frame:Show()
    elseif finder then
        finder.frame:Hide()
    end

    -- Add remains available whenever its own panel rules elected to show it;
    -- a missing or temporarily unavailable finder catalog must never close
    -- that existing workflow.
    local showAdd = addBox ~= nil and not suppressed
    if addBox and not showAdd then
        addBox.frame:Hide()
        addBox = nil
    end

    row._cdcAddBox = addBox
    row._cdcFinder = showFinder and finder or nil
    row:SetShown(showAdd or showFinder)
    if row:IsShown() then
        LayoutEditingActionRow(col3)
    end
    col3._cdcSettingsFinderRestoreFocus = nil
    if resumeFinder and finder then
        local resumeIdentity = contextIdentity
        C_Timer.After(0, function()
            if col3._cdcSettingsFinderContextIdentity ~= resumeIdentity
                or not (finder.frame:IsShown() and finder.editbox)
            then
                return
            end
            finder:SetFocus()
            -- SetFocus normally fires OnEditFocusGained and queues the
            -- search. Queue once explicitly as well for clients that retain
            -- focus while the persistent frame is briefly hidden; the serial
            -- guard coalesces the duplicate callback.
            QueueSettingsFinderSearch(col3)
        end)
    end
    return row:IsShown() and row or nil
end

local function RefreshEditingChipColor(button)
    if button._cdcHovered then
        button.text:SetTextColor(1, 0.82, 0)
    elseif button._cdcSelected then
        button.text:SetTextColor(1, 1, 1)
    else
        button.text:SetTextColor(0.70, 0.68, 0.64)
    end
end

local function CloseEditingChipMenu(frame)
    if frame._cdcMenuOpen then CloseDropDownMenus() end
end

local function LayoutWideEditingChips(frame)
    if not (frame and frame:IsShown()) then return end
    local label, more = frame._cdcPrefix, frame._cdcMore
    local items, buttons = frame._cdcItems or {}, frame._cdcButtons
    local labelWidth = math.ceil(label:GetStringWidth())
    local available = math.max(0, frame:GetWidth() - labelWidth)
    local total = 0
    for index = 1, #items do total = total + buttons[index]:GetWidth() end
    local overflow = total > available
    if overflow then available = math.max(0, available - more:GetWidth() - EDIT_CHIPS_MORE_GAP) end

    local inlineCount, width = 0, 0
    for index = 1, #items do
        local buttonWidth = buttons[index]:GetWidth()
        if width + buttonWidth > available then break end
        inlineCount, width = index, width + buttonWidth
    end
    if frame._cdcInlineCount ~= inlineCount then
        CloseEditingChipMenu(frame)
        frame._cdcRevision = (frame._cdcRevision or 0) + 1
    end
    frame._cdcInlineCount = inlineCount
    local offset = labelWidth
    more._cdcSelected = false
    for index, button in ipairs(buttons) do
        button:SetShown(index <= inlineCount)
        if index <= inlineCount then
            button:ClearAllPoints()
            button:SetPoint("LEFT", frame, "LEFT", offset, 0)
            offset = offset + button:GetWidth()
        elseif items[index] and items[index].selected then
            more._cdcSelected = true
        end
    end
    more:SetShown(overflow)
    RefreshEditingChipColor(more)
end

local function OpenEditingChipMenu(frame)
    if frame._cdcMenuOpen then
        CloseEditingChipMenu(frame)
        return
    end
    -- Match the config gear: an outside mouse-down may already have closed
    -- this menu during the same click. Do not immediately reopen it.
    if frame._cdcMenuClosedAt == GetTime() then return end
    local items = frame._cdcItems or {}
    local first = (frame._cdcInlineCount or 0) + 1
    if first > #items then return end
    local menu = frame._cdcMenu
    if not menu then
        menu = CreateFrame("Frame", "CDCEditingSelectDropdown", UIParent, "UIDropDownMenuTemplate")
        menu.point, menu.relativePoint = "TOPRIGHT", "BOTTOMRIGHT"
        menu.xOffset, menu.yOffset = 0, -2
        menu.listFrameStrata = "FULLSCREEN_DIALOG"
        menu.onHide = function()
            frame._cdcMenuOpen = nil
            frame._cdcMenuClosedAt = GetTime()
        end
        frame._cdcMenu = menu
    end
    local revision = frame._cdcRevision
    UIDropDownMenu_Initialize(menu, function(_, level)
        for index = first, #items do
            local itemIndex = index
            local item = frame._cdcItems[itemIndex]
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.label
            info.checked = item.selected == true
            info.registerForRightClick = item.onRightClick ~= nil
            info.tooltipTitle = item.tooltip
            info.func = function(_, _, _, _, mouseButton)
                if not frame:IsVisible() or frame._cdcRevision ~= revision then return end
                local current = frame._cdcItems[itemIndex]
                if not current then return end
                CloseDropDownMenus()
                if mouseButton == "RightButton" and current.onRightClick then
                    current.onRightClick()
                elseif mouseButton == "LeftButton" and current.onClick then
                    current.onClick()
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    frame._cdcMenuOpen = ToggleDropDownMenu(1, nil, menu, frame._cdcMore, 0, 0) and true or nil
end

local function SetWideEditingChips(col3, prefix, items)
    local surface = EnsureEditingSurface(col3)
    local frame = col3._cdcEditingChips
    if not frame then
        frame = CreateFrame("Frame", nil, surface)
        frame:SetHeight(EDIT_CHIPS_HEIGHT)
        frame._cdcPrefix = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        frame._cdcPrefix:SetJustifyH("LEFT")
        frame._cdcPrefix:SetPoint("LEFT", frame, "LEFT", 0, 0)
        local more = CreateFrame("Button", nil, frame)
        more.text = more:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        more.text:SetPoint("LEFT")
        more.text:SetText("More")
        more:SetSize(math.ceil(more.text:GetStringWidth()) + 16, EDIT_CHIPS_HEIGHT)
        more:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        local arrow = more:CreateTexture(nil, "ARTWORK")
        arrow:SetSize(12, 12)
        arrow:SetPoint("RIGHT")
        arrow:SetAtlas("uitools-icon-chevron-down", false)
        arrow:SetVertexColor(0.70, 0.68, 0.64)
        more:RegisterForClicks("LeftButtonDown")
        more:SetScript("OnClick", function() OpenEditingChipMenu(frame) end)
        more:SetScript("OnEnter", function(self)
            self._cdcHovered = true
            RefreshEditingChipColor(self)
        end)
        local function ClearMoreHover(self)
            self._cdcHovered = nil
            RefreshEditingChipColor(self)
        end
        more:SetScript("OnLeave", ClearMoreHover)
        more:SetScript("OnHide", ClearMoreHover)
        frame._cdcMore = more
        frame._cdcButtons = {}
        frame:SetScript("OnSizeChanged", LayoutWideEditingChips)
        frame:SetScript("OnHide", function(self)
            CloseEditingChipMenu(self)
            self._cdcRevision = (self._cdcRevision or 0) + 1
        end)
        col3._cdcEditingChips = frame
    end
    local wasShown = frame:IsShown()

    -- Keep callbacks current without disturbing an open menu on a repaint
    -- whose destinations and selection have not changed.
    local old = frame._cdcItems or {}
    items = items or {}
    local workspace = CS.barsEntrySelected and CS.barWorkspaceKind or nil
    local changed = frame._cdcProfile ~= CooldownCompanion.db.profile
        or frame._cdcPanel ~= CS.selectedGroup or frame._cdcWorkspace ~= workspace
        or frame._cdcLabel ~= prefix or #old ~= #items
    for index, item in ipairs(items) do
        local previous = old[index]
        if not previous or previous.key ~= item.key or previous.label ~= item.label
            or previous.selected ~= item.selected or previous.tooltip ~= item.tooltip then
            changed = true
        end
    end
    frame._cdcItems = items
    frame._cdcProfile, frame._cdcPanel = CooldownCompanion.db.profile, CS.selectedGroup
    frame._cdcWorkspace, frame._cdcLabel = workspace, prefix
    if changed then
        CloseEditingChipMenu(frame)
        frame._cdcRevision = (frame._cdcRevision or 0) + 1
    end
    if #items == 0 then
        frame:Hide()
        return wasShown
    end
    if not changed and frame:IsShown() then return end

    frame._cdcPrefix:SetText((prefix or "Not currently shown:") .. " ")
    for index, item in ipairs(items) do
        local button = frame._cdcButtons[index]
        if not button then
            local itemIndex = index
            button = CreateFrame("Button", nil, frame)
            button:RegisterForClicks("AnyUp")
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.text:SetPoint("LEFT")
            button.text:SetJustifyH("LEFT")
            button.text:SetWordWrap(false)
            button:SetScript("OnEnter", function(self)
                self._cdcHovered = true
                RefreshEditingChipColor(self)
                if self._cdcTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self._cdcTooltip, 1, 1, 1)
                    GameTooltip:Show()
                end
            end)
            local function ClearHover(self)
                self._cdcHovered = nil
                RefreshEditingChipColor(self)
                if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
            end
            button:SetScript("OnLeave", ClearHover)
            button:SetScript("OnHide", ClearHover)
            button:SetScript("OnClick", function(_, mouseButton)
                local current = frame._cdcItems[itemIndex]
                if not current or not frame:IsVisible() then return end
                CloseEditingChipMenu(frame)
                if mouseButton == "RightButton" and current.onRightClick then
                    current.onRightClick()
                elseif mouseButton == "LeftButton" and current.onClick then
                    current.onClick()
                end
            end)
            frame._cdcButtons[index] = button
        end
        button.text:SetText((index > 1 and "  \194\183  " or "") .. tostring(item.label or ""))
        button:SetSize(math.ceil(button.text:GetStringWidth()) + 2, EDIT_CHIPS_HEIGHT)
        button._cdcSelected = item.selected == true
        button._cdcTooltip = item.tooltip
        RefreshEditingChipColor(button)
    end
    for index = #items + 1, #frame._cdcButtons do
        frame._cdcButtons[index]:Hide()
    end
    frame:Show()
    LayoutWideEditingChips(frame)
    return not wasShown
end

local function ClearWideEditingExtras(col3, preserveFinderState)
    local alternate = col3._cdcAlternateEditingAddBox
    if alternate and alternate.frame then
        alternate.frame:Hide()
    end
    col3._cdcAlternateEditingAddBox = nil
    if col3._cdcEditingChips then
        col3._cdcEditingChips:Hide()
    end
    if preserveFinderState then
        PrepareSettingsFinderActionRowRefresh(col3)
    else
        ClearSettingsFinderActionRowState(col3)
    end
    if col3._cdcSettingsFinder then
        col3._cdcSettingsFinder.frame:Hide()
    end
end

local function AcquireEditingHeaderBadge(headerLine, index)
    local badge = headerLine.badges[index]
    if badge then return badge end

    badge = CreateFrame("Frame", nil, headerLine)
    badge:SetSize(EDIT_CONTEXT_BADGE_SIZE, EDIT_CONTEXT_BADGE_SIZE)
    badge:EnableMouse(true)
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetAllPoints()
    badge:SetScript("OnEnter", function(self)
        if not self._cdcLabel then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self._cdcLabel, 1, 1, 1)
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    headerLine.badges[index] = badge
    return badge
end

-- Path shown in the editing header: the parent context dimmed, the leaf
-- (what the settings below actually edit) emphasized.
local function GetEditingHeaderPath()
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if CS.barsEntrySelected and CS.castFramesSelectedItem then
        if CS.castFramesSelectedItem == "player" or CS.castFramesSelectedItem == "target" then
            return nil, "Unit Frames"
        end
        return nil, "Cast Bar"
    end
    if CS.barsEntrySelected then
        local settings = CooldownCompanion.GetResourceBarSettings
            and CooldownCompanion:GetResourceBarSettings()
        if CS.selectedResourcePowerType and ST._RBP
            and ST._RBP.IsResourceEditableInColumn4
            and ST._RBP.IsResourceEditableInColumn4(CS.selectedResourcePowerType, settings, true) then
            local powerNames = ST._RB and ST._RB.POWER_NAMES
            local resourceName = powerNames and powerNames[tonumber(CS.selectedResourcePowerType)]
            return BARS_HOME_LABEL, resourceName or "Resource"
        end
        return nil, "Resources"
    end
    local group = db and CS.selectedGroup and db.groups[CS.selectedGroup]
    if not group then return nil, nil end
    local containerId = group.parentContainerId or CS.selectedContainer
    local container = containerId and db.groupContainers and db.groupContainers[containerId]
    return container and container.name, group.name or "Panel"
end

local function AcquireHeaderCrumb(headerLine, index)
    local crumb = headerLine.crumbs[index]
    if crumb then return crumb end

    crumb = CreateFrame("Button", nil, headerLine)
    crumb:SetHeight(EDIT_HEADER_HEIGHT)
    local crumbText = crumb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    crumbText:SetAllPoints()
    crumbText:SetJustifyH("LEFT")
    crumbText:SetWordWrap(false)
    crumbText:SetTextColor(0.616, 0.584, 0.529)
    crumb.text = crumbText
    crumb:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
        if self._cdcTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self._cdcTooltip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    crumb:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.616, 0.584, 0.529)
        GameTooltip:Hide()
    end)
    crumb:SetScript("OnClick", function(self)
        if self._cdcOnClick then
            self._cdcOnClick()
        end
    end)
    headerLine.crumbs[index] = crumb
    return crumb
end

-- Breadcrumb click handlers: every ancestor scope in the path navigates.
-- The group crumb opens the group's own settings (same landing as clicking
-- the group in the navigator); the panel crumb deselects the entry or
-- attached bar; the Resources crumb returns to the Resources overview.
local function BreadcrumbToGroup()
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = db and CS.selectedGroup and db.groups[CS.selectedGroup]
    local containerId = (group and group.parentContainerId) or CS.selectedContainer
    if not (containerId and ST._SelectConfigContainer) then return end
    if CS.spellbookPanelWindow then CS.CloseSpellbookPanel() end
    CS.unifiedBarKind = nil
    ST._SelectConfigContainer(containerId)
    CooldownCompanion:RefreshConfigPanel()
end

local function BreadcrumbToPanel()
    if CS.spellbookPanelWindow then CS.CloseSpellbookPanel() end
    GameTooltip:Hide()
    CS.unifiedBarKind = nil
    if CS.selectedGroup and ST._SelectConfigPanel then
        ST._SelectConfigPanel(CS.selectedGroup)
    elseif ST._ClearConfigButtonSelection then
        ST._ClearConfigButtonSelection()
    end
    CooldownCompanion:RefreshConfigPanel()
end

local function BreadcrumbToResourcesHome()
    if CS.spellbookPanelWindow then CS.CloseSpellbookPanel() end
    -- Drops the resource or cast/frames item being edited, so
    -- the workspace falls back to its Resources home.
    if ST._ClearConfigBarsHomeSelection then
        ST._ClearConfigBarsHomeSelection()
    end
    CooldownCompanion:RefreshConfigPanel()
end

local function UpdateEditingHeader(col3)
    local headerLine = EnsureEditingSurface(col3)._cdcHeader
    local header = headerLine.text
    local parent, leaf = GetEditingHeaderPath()
    local context = col3._cdcEditingContext

    -- Status badges fill the header's right edge, chaining leftward.
    local shown = 0
    local rightAnchor
    local badgeStatus = context and context.badgeStatus
    if badgeStatus and ST._EntryStatusBadges then
        for _, desc in ipairs(ST._EntryStatusBadges) do
            if badgeStatus[desc.key] then
                shown = shown + 1
                local badge = AcquireEditingHeaderBadge(headerLine, shown)
                badge.icon:SetAtlas(desc.atlas, false)
                badge._cdcLabel = (desc.key == "warn" and badgeStatus.loadBlocked)
                    and "Hidden by visibility rules" or desc.label
                badge:ClearAllPoints()
                if rightAnchor then
                    badge:SetPoint("RIGHT", rightAnchor, "LEFT", -EDIT_CONTEXT_BADGE_GAP, 0)
                else
                    badge:SetPoint("RIGHT", headerLine, "RIGHT", 0, 0)
                end
                badge:Show()
                rightAnchor = badge
            end
        end
    end
    for i = shown + 1, #headerLine.badges do
        headerLine.badges[i]:Hide()
    end

    header:ClearAllPoints()
    header:SetPoint("LEFT", headerLine, "LEFT", 0, 0)
    if rightAnchor then
        header:SetPoint("RIGHT", rightAnchor, "LEFT", -EDIT_CONTEXT_BADGE_GAP - 3, 0)
    else
        header:SetPoint("RIGHT", headerLine, "RIGHT", 0, 0)
    end

    local prefix = headerLine.prefix
    local crumbs = headerLine.crumbs

    local function HideCrumbsFrom(startIndex)
        for i = startIndex, #crumbs do
            crumbs[i]:Hide()
        end
    end

    if not leaf then
        prefix:Hide()
        HideCrumbsFrom(1)
        header:SetText("Editing")
        return
    end

    -- Every ancestor scope in the dimmed path is a clickable crumb; only
    -- the current selection stays plain text. In the bars workspace that
    -- ancestor is its Resources home, which every object it edits - bars,
    -- cast bar, unit frames - returns to.
    local segments = {}
    local currentText
    if context and context.name then
        if parent then
            segments[#segments + 1] = { label = parent,
                tooltip = "Back to group settings", onClick = BreadcrumbToGroup }
        end
        segments[#segments + 1] = { label = leaf,
            tooltip = "Back to panel settings", onClick = BreadcrumbToPanel }
        local contextName = context.name
        if context.icon then
            contextName = "|T" .. context.icon .. ":" .. EDIT_CONTEXT_ICON_SIZE
                .. ":" .. EDIT_CONTEXT_ICON_SIZE .. ":0:0:64:64:5:59:5:59|t " .. contextName
        end
        if context.kindText then
            contextName = contextName .. " |cff7d7566(" .. context.kindText .. ")|r"
        end
        -- Section placement rides the same muted tail as the tracking kind, one
        -- middot further out: it says where the entry sits, not what it is.
        if context.sectionText then
            contextName = contextName .. " |cff7d7566\194\183 " .. context.sectionText .. "|r"
        end
        currentText = contextName
    elseif CS.barsEntrySelected and parent == BARS_HOME_LABEL then
        segments[1] = { label = parent,
            tooltip = "Back to Resources", onClick = BreadcrumbToResourcesHome }
        currentText = leaf
    elseif parent and not CS.barsEntrySelected then
        -- Panel scope in the buttons workspace: the group is the one
        -- clickable ancestor.
        segments[1] = { label = parent,
            tooltip = "Back to group settings", onClick = BreadcrumbToGroup }
        currentText = leaf
    end

    if #segments > 0 then
        prefix:SetText("Editing: ")
        prefix:Show()
        local anchor = prefix
        for index, segment in ipairs(segments) do
            local crumb = AcquireHeaderCrumb(headerLine, index)
            crumb.text:SetText(segment.label .. " \194\187 ")
            crumb.text:SetTextColor(0.616, 0.584, 0.529)
            crumb:SetWidth(crumb.text:GetStringWidth() + 1)
            crumb._cdcTooltip = segment.tooltip
            crumb._cdcOnClick = segment.onClick
            crumb:ClearAllPoints()
            crumb:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
            crumb:Show()
            anchor = crumb
        end
        HideCrumbsFrom(#segments + 1)
        header:ClearAllPoints()
        header:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
        if rightAnchor then
            header:SetPoint("RIGHT", rightAnchor, "LEFT", -EDIT_CONTEXT_BADGE_GAP - 3, 0)
        else
            header:SetPoint("RIGHT", headerLine, "RIGHT", 0, 0)
        end
        header:SetFormattedText("|cffffffff%s|r", currentText)
        return
    end

    prefix:Hide()
    HideCrumbsFrom(1)
    if parent then
        header:SetFormattedText("Editing: |cff9d9587%s \194\187 |r|cffffffff%s|r", parent, leaf)
    else
        header:SetFormattedText("Editing: |cffffffff%s|r", leaf)
    end
end

-- Shared hide for the editing surface: every path that stops showing the
-- preview/editing pair must run this so the chrome never lingers over a
-- full-column surface.
local function HideEditingChrome(col3)
    if col3._cdcEditingSurface then
        col3._cdcEditingSurface:Hide()
    end
    if col3._cdcEditingActionRow then
        col3._cdcEditingActionRow:Hide()
    end
    if col3._cdcSettingsFinder then
        col3._cdcSettingsFinder.frame:Hide()
    end
    col3._cdcSettingsFinderContext = nil
    col3._cdcSettingsFinderContextIdentity = nil
    ClearSettingsFinderUI(col3, true, true)
end

-- Single source of truth for the preview host height: settings have their
-- own column, so the preview fills the center column's full height.
local function ComputePreviewHostHeight(col3)
    return math.max(1, col3.content:GetHeight() or 0)
end

-- The size the host's preview was last laid out at. Every direct build
-- records it, so a later column change (the Settings column appearing after
-- a refresh built the preview at full width) is seen as a size change.
local function StampWidePreviewLayout(host)
    host._cdcLastLayoutWidth = host:GetWidth() or 0
    host._cdcLastLayoutHeight = host:GetHeight() or 0
end

-- Anchored widths are not guaranteed to settle until the frame after the
-- config columns resize. Coalesce resize traffic into one trailing pass so
-- the preview always rebuilds from the latest propagated host dimensions.
local function ScheduleFinalWidePreviewLayout(col3, host, forceRebuild)
    col3._cdcFinalWidePreviewHost = host
    if forceRebuild then
        col3._cdcFinalWidePreviewForceRebuild = true
    end
    if col3._cdcFinalWidePreviewLayoutScheduled then return end
    col3._cdcFinalWidePreviewLayoutScheduled = true

    C_Timer.After(0, function()
        col3._cdcFinalWidePreviewLayoutScheduled = nil
        local requestedHost = col3._cdcFinalWidePreviewHost
        local requestedForceRebuild = col3._cdcFinalWidePreviewForceRebuild
        col3._cdcFinalWidePreviewHost = nil
        col3._cdcFinalWidePreviewForceRebuild = nil
        if not (requestedHost
            and col3._cdcActiveWideHost == requestedHost
            and requestedHost:IsShown()) then
            return
        end
        if (col3.content:GetHeight() or 0) <= 0 then return end

        local takeover = col3._cdcEmptyGroupPreviewTakeover == true
        local newHeight = takeover and (requestedHost:GetHeight() or 0)
            or ComputePreviewHostHeight(col3)
        local hostHeightChanged = not takeover and math.abs(
            (requestedHost:GetHeight() or 0) - newHeight) >= 0.5
        if hostHeightChanged then
            requestedHost:SetHeight(newHeight)
        end

        local width = requestedHost:GetWidth() or 0
        local widthChanged = math.abs(
            (requestedHost._cdcLastLayoutWidth or 0) - width) >= 0.5
        local heightChanged = math.abs(
            (requestedHost._cdcLastLayoutHeight or 0) - newHeight) >= 0.5
        if not (requestedForceRebuild or hostHeightChanged
            or heightChanged or widthChanged) then
            return
        end

        requestedHost._cdcLastLayoutWidth = width
        requestedHost._cdcLastLayoutHeight = newHeight
        RebuildActiveWidePreview(col3)
    end)
end

-- Re-fit the preview host to the CURRENT column size. Called from
-- LayoutColumns, which runs on every window resize and whenever the
-- Settings column appears or hides; the trailing layout pass rebuilds from
-- settled host dimensions whenever they differ from the last build.
local function RefitWidePreviewHost()
    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3._cdcActiveWideHost
    if not (host and host:IsShown()) then return end
    if (col3.content:GetHeight() or 0) <= 0 then return end
    if col3._cdcEmptyGroupPreviewTakeover == true then
        ScheduleFinalWidePreviewLayout(col3, host)
        return
    end
    local newHeight = ComputePreviewHostHeight(col3)
    local heightChanged = math.abs((host:GetHeight() or 0) - newHeight) >= 0.5
    -- The preview's scale-to-fit reads the host width too, so a width-only
    -- window resize still needs a rebuild even when the height held.
    local width = host:GetWidth() or 0
    local widthChanged = math.abs((host._cdcLastLayoutWidth or 0) - width) >= 0.5
    if heightChanged then
        host:SetHeight(newHeight)
    end
    ScheduleFinalWidePreviewLayout(col3, host, heightChanged or widthChanged)
end

local function AnchorEditingSurface(col3, surface)
    surface:ClearAllPoints()
    local settingsContent = col3._cdcSettingsColumn.content
    surface:SetParent(settingsContent)
    surface:SetAllPoints(settingsContent)
end

-- Settings surfaces anchor inside the editing surface in the Settings
-- column, beneath the editing header and add box; they fill the whole
-- center column when no preview is active.
local function AnchorButtonsContentFrame(col3, frame)
    col3._cdcEditingContentFrame = frame
    frame:ClearAllPoints()
    local actionRow = UpdateEditingActionRow(col3)
    local previewHost = col3._cdcActiveWideHost
    if previewHost and previewHost:IsShown() then
        local surface = EnsureEditingSurface(col3)
        AnchorEditingSurface(col3, surface)
        frame:SetParent(surface)
        surface:Show()
        UpdateEditingHeader(col3)

        local topAnchor = surface._cdcHeader
        if actionRow then
            actionRow:ClearAllPoints()
            actionRow:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -EDIT_HEADER_GAP)
            actionRow:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 0, -EDIT_HEADER_GAP)
            actionRow:SetHeight(actionRow._cdcEditingHeight or ADD_BOX_HEIGHT)
            LayoutEditingActionRow(col3)
            topAnchor = actionRow
        end

        local chips = col3._cdcEditingChips
        if chips and chips:IsShown() then
            chips:SetParent(surface)
            chips:ClearAllPoints()
            chips:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -EDIT_CHIPS_GAP)
            chips:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 0, -EDIT_CHIPS_GAP)
            chips:SetHeight(EDIT_CHIPS_HEIGHT)
            topAnchor = chips
        end
        frame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -PREVIEW_GAP)
        frame:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", -EDIT_INSET, EDIT_BOTTOM_INSET)
    else
        frame:SetParent(col3.content)

        local chips = col3._cdcEditingChips
        local hasChips = chips and chips:IsShown()
        if actionRow or hasChips then
            local surface = EnsureEditingSurface(col3)
            surface:SetParent(col3.content)
            surface:ClearAllPoints()
            surface:SetAllPoints(col3.content)
            surface:Show()
            UpdateEditingHeader(col3)

            local topAnchor = surface._cdcHeader
            if actionRow then
                actionRow:ClearAllPoints()
                actionRow:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -EDIT_HEADER_GAP)
                actionRow:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 0, -EDIT_HEADER_GAP)
                actionRow:SetHeight(actionRow._cdcEditingHeight or ADD_BOX_HEIGHT)
                LayoutEditingActionRow(col3)
                topAnchor = actionRow
            end
            if hasChips then
                chips:SetParent(surface)
                chips:ClearAllPoints()
                chips:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -EDIT_CHIPS_GAP)
                chips:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 0, -EDIT_CHIPS_GAP)
                chips:SetHeight(EDIT_CHIPS_HEIGHT)
                topAnchor = chips
            end
            frame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -PREVIEW_GAP)
            frame:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", -EDIT_INSET, EDIT_BOTTOM_INSET)
        else
            HideEditingChrome(col3)
            frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
            frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
        end
    end
end

-- Core owns every "can this panel take a manual add" rule, so the add box, the
-- drop overlay, and the move menus cannot answer differently. Kept as a wrapper
-- because callers pass a group table, not an id, and nil has to answer false.
local function CanManuallyAddToPanel(group)
    if not group then return false end
    return CooldownCompanion:CanPanelAcceptManualEntry(group)
end

-- CanManuallyAddToPanel is entry-blind (it answers before there is an entry to
-- judge), so the payload question is asked here. An Aura Panel holds aura
-- entries only: a spell cursor is aura intent by destination and TryAddSpell
-- routes it, but an item or pet action has no aura to route to and the add door
-- refuses it -- so the overlay must not offer a drop the panel will reject.
local function IsCursorDropPayload(cursorType, group)
    if cursorType ~= "spell" and cursorType ~= "item" and cursorType ~= "petaction" then
        return false
    end
    if group and CooldownCompanion:IsAuraPanel(group) then
        return cursorType == "spell"
    end
    return true
end

-- Drop-to-add overlay over the preview: shown while a spell/item is on the
-- cursor, mirroring the Navigator panel drop overlays. TryReceiveCursorDrop
-- targets CS.selectedGroup, which is exactly the previewed panel.
--
-- Two looks. Alone, the overlay is the whole message: a wash, a darker
-- plate, "Drop here" in the middle. Over a panel whose preview tracks the
-- cursor against its section landings (ST._TrackPreviewCursorDrop), or draws
-- the drop ghost (ST._ShowPreviewDropGhost: the cell the release will add,
-- where it will land), the preview is the message: the plate goes, and the
-- line moves to the bottom band, where it says what is on offer and, once
-- the cursor is near a section's landing, names the release outright. The
-- ghost draws on the preview beneath the wash, and without the plate the
-- wash alone is light enough to read it through.

-- Screen pixels between the bottom band's line and whatever sits below it:
-- the command center's reserve when the bar is up, the host's edge otherwise.
local DROP_OVERLAY_TEXT_INSET = 6

local function SetPreviewDropOverlayMode(overlay, host, landings, hasFree, ghostShown, target)
    landings = landings and true or false
    hasFree = landings and hasFree and true or false
    ghostShown = ghostShown and true or false
    local bottomBand = landings or ghostShown
    -- The reserve comes and goes with the selection, so the anchor is re-read
    -- on every frame the band is used and rewritten only when it moved.
    local inset = bottomBand
        and ((host._cdcPreviewReserveBottom or 0) + DROP_OVERLAY_TEXT_INSET) or nil
    -- The line. Near a landing it names the release outright: the game's
    -- own cursor icon draws over the ghost's cell, so the words are the one
    -- readable confirmation of the choice besides the trail.
    local line
    local anchor = target and (target.create or target.section)
    local label = anchor and ST.PANEL_SECTION_ANCHOR_LABELS
        and ST.PANEL_SECTION_ANCHOR_LABELS[anchor] or anchor
    if target and target.rejectMessage then
        line = "|cffff6666" .. label .. " section: " .. target.rejectMessage .. "|r"
    elseif target and target.create then
        line = "|cffFFD100Release to start a section on the " .. label .. " edge|r"
    elseif target and target.section then
        line = "|cffFFD100Release to join the " .. label .. " section|r"
    elseif landings then
        line = hasFree
            and "|cffAADDFFDrop here, or near a section's spot to start or join one|r"
            or "|cffAADDFFDrop here, or on a section to join it|r"
    else
        line = "|cffAADDFFDrop here|r"
    end
    if overlay._cdcBottomBand == bottomBand and overlay._cdcLine == line
        and overlay._cdcLineInset == inset then
        return
    end
    overlay._cdcBottomBand = bottomBand
    overlay._cdcLine = line
    overlay._cdcLineInset = inset
    local text = overlay._cdcText
    text:ClearAllPoints()
    if bottomBand then
        overlay._cdcInner:Hide()
        text:SetPoint("BOTTOM", overlay, "BOTTOM", 0, inset)
    else
        overlay._cdcInner:Show()
        text:SetPoint("CENTER", 0, 0)
    end
    text:SetText(line)
end

-- The stub the drop ghost renders for what the cursor carries: the same four
-- values TryReceiveCursorDrop reads, mapped the way the add will map them
-- (a pet action is a pet spell; an item is an item), then routed the way
-- the add routes them (CS.ResolveProspectiveAdd: a passive is born an aura
-- entry, and a spell the add would refuse gets no ghost at all). One table,
-- refilled only when the payload or the panel changes: the overlay asks
-- every frame.
local cursorGhostSpec = {}
local function CursorGhostSpec()
    local cursorType, cursorID, _, cursorSpellID = GetCursorInfo()
    local spec = cursorGhostSpec
    local id
    if cursorType == "spell" then
        id = cursorSpellID
    elseif cursorType == "petaction" or cursorType == "item" then
        id = cursorID
    end
    if not id then return nil end
    if spec.cursorType == cursorType and spec.id == id and spec.panelId == CS.selectedGroup then
        if spec.refused then return nil end
        return spec
    end
    wipe(spec)
    spec.cursorType = cursorType
    spec.id = id
    spec.panelId = CS.selectedGroup
    if cursorType == "item" then
        spec.type = "item"
        spec.name = C_Item.GetItemNameByID(id)
    else
        spec.type = "spell"
        spec.isPetSpell = (cursorType == "petaction") or nil
        spec.name = C_Spell.GetSpellName(id)
    end
    if CS.ResolveProspectiveAdd and not CS.ResolveProspectiveAdd(spec, CS.selectedGroup) then
        spec.refused = true
        return nil
    end
    return spec
end

local function EnsurePreviewDropOverlay(host)
    local overlay = host._cdcDropOverlay
    if not overlay then
        overlay = CreateFrame("Frame", nil, host, "BackdropTemplate")
        overlay:SetAllPoints(host)
        overlay:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
        overlay:SetBackdropColor(0.15, 0.55, 0.85, 0.25)
        overlay:EnableMouse(true)

        local inner = overlay:CreateTexture(nil, "ARTWORK")
        inner:SetPoint("TOPLEFT", 2, -2)
        inner:SetPoint("BOTTOMRIGHT", -2, 2)
        inner:SetColorTexture(0.05, 0.15, 0.25, 0.6)
        overlay._cdcInner = inner

        overlay._cdcText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        overlay._cdcText:SetPoint("CENTER", 0, 0)
        overlay._cdcText:SetText("|cffAADDFFDrop here|r")
        overlay._cdcBottomBand = false
        overlay._cdcLine = "|cffAADDFFDrop here|r"

        local function ReceiveDrop()
            if not ST._TryReceiveCursorDrop then return end
            -- Read BEFORE the add: the add rebuilds the preview, and the
            -- rebuild ends the gesture the answer belongs to.
            local target = ST._ResolvePreviewCursorDrop
                and ST._ResolvePreviewCursorDrop(host)
            if target and target.rejectMessage then
                CooldownCompanion:Print(target.rejectMessage)
                return
            end
            ST._TryReceiveCursorDrop({
                groupId = CS.selectedGroup,
                section = target and (target.create or target.section) or nil,
            })
        end
        overlay:SetScript("OnReceiveDrag", ReceiveDrop)
        overlay:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and GetCursorInfo() then
                ReceiveDrop()
            end
        end)
        -- Runs only while the overlay is shown (a hidden frame gets no
        -- OnUpdate): the preview tracks the cursor, and the overlay wears
        -- whichever look the preview's answer calls for.
        overlay:SetScript("OnUpdate", function(self)
            local target, landings, hasFree
            if ST._TrackPreviewCursorDrop then
                target, landings, hasFree = ST._TrackPreviewCursorDrop(host, GetCursorPosition())
            end
            -- The ghost follows the pointer, not the payload: off the overlay
            -- there is no landing to show. It lands where the preview's
            -- answer says the release will.
            local ghostShown = false
            if self:IsMouseOver() and not (target and target.rejectMessage) and ST._ShowPreviewDropGhost then
                local spec = CursorGhostSpec()
                ghostShown = spec ~= nil
                    and ST._ShowPreviewDropGhost(host, spec, target, "cursor")
            end
            if not ghostShown and ST._HidePreviewDropGhost then
                ST._HidePreviewDropGhost(host, "cursor")
            end
            SetPreviewDropOverlayMode(self, host, landings, hasFree, ghostShown, target)
        end)
        -- One hider, however the overlay goes (the payload cleared, the host
        -- hidden, the view switched): the gesture and the ghost go with it.
        overlay:SetScript("OnHide", function(self)
            SetPreviewDropOverlayMode(self, host, false)
            if ST._EndPreviewCursorDrop then
                ST._EndPreviewCursorDrop(host)
            end
            if ST._HidePreviewDropGhost then
                ST._HidePreviewDropGhost(host, "cursor")
            end
        end)
        overlay:Hide()
        host._cdcDropOverlay = overlay
    end
    overlay:SetFrameLevel(host:GetFrameLevel() + 30)
    return overlay
end

local function UpdatePreviewDropOverlay()
    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3.buttonsPreviewHost
    if not host then return end
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    -- Parenthesized: GetCursorInfo returns several values and only the type is
    -- this call's first argument.
    local show = host:IsShown()
        and IsCursorDropPayload((GetCursorInfo()), group)
        and CanManuallyAddToPanel(group)
        and ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive()
    if show then
        EnsurePreviewDropOverlay(host):Show()
    elseif host._cdcDropOverlay then
        host._cdcDropOverlay:Hide()
    end
end

local previewCursorWatcher = CreateFrame("Frame")
previewCursorWatcher:RegisterEvent("CURSOR_CHANGED")
previewCursorWatcher:SetScript("OnEvent", UpdatePreviewDropOverlay)

-- Close the inline texture browser from ButtonsWideColumn's side: hide its
-- grid host and, if it was open, drop the flag and clear the staged mirror
-- texture. Clearing the staging
-- matters when the browser is left without a thumbnail OnLeave firing first --
-- e.g. Escape-to-close or a jump to Resources with the cursor still on a tile.
local function CloseInlineTextureBrowser(col3)
    if col3._inlineTextureBrowserHost then
        col3._inlineTextureBrowserHost:Hide()
    end
    if CS.inlineTextureBrowserOpen then
        CS.inlineTextureBrowserOpen = nil
        CS.textureMirrorStage = nil
    end
end

local function ReleaseButtonsPreviewRenderer(host)
    if not host then return end
    if host._cdcButtonsPreviewMode == "group-overview" then
        if ST._ReleaseGroupPanelOverview then
            ST._ReleaseGroupPanelOverview(host)
        end
    else
        if ST._ReleaseAnchorAwarePanelPreview then
            ST._ReleaseAnchorAwarePanelPreview(host)
        elseif ST._ReleaseButtonPanelPreview then
            ST._ReleaseButtonPanelPreview(host)
        end
    end
    host._cdcButtonsPreviewMode = nil
end

local function SetButtonsPreviewRenderer(host, mode)
    if host._cdcButtonsPreviewMode == mode then return end
    ReleaseButtonsPreviewRenderer(host)
    host._cdcButtonsPreviewMode = mode
end

local function HidePanelPreview(col3)
    local host = col3.buttonsPreviewHost
    if host then
        ClearActiveWidePreview(col3, host)
        host:Hide()
        if host._cdcDropOverlay then
            host._cdcDropOverlay:Hide()
        end
        ReleaseButtonsPreviewRenderer(host)
    end
    if col3.buttonsAddBox then
        col3.buttonsAddBox.frame:Hide()
    end
    CloseInlineTextureBrowser(col3)
    col3._cdcEditingContext = nil
    col3._cdcEmptyGroupPreviewTakeover = nil
    HideEditingChrome(col3)
end

-- A new editable Group has no visible object for position, alpha, strata, or
-- visibility settings to affect. Let its create surface own the workspace until
-- the first Panel exists; ineligible/browse-only Groups keep the normal split.
local function ShouldEmptyGroupPreviewTakeOver(containerId, container)
    if not (containerId and container and not CS.selectedGroup) then
        return false
    end
    if not (ST._IsCreateTargetContainer
        and ST._IsCreateTargetContainer(containerId)) then
        return false
    end
    return CooldownCompanion:GetPanelCount(containerId) == 0
end

-- Pinned preview of the selected Panel, or an organized navigation overview
-- when a single editable Group is selected with no child Panel selected.
local function UpdatePanelPreview(col3, selectionOnly, edit)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local panelId = CS.selectedGroup
    local containerId = not panelId and CS.selectedContainer or nil
    local hasGroupMulti = next(CS.selectedGroups) ~= nil
    local hasPanelMulti = next(CS.selectedPanels) ~= nil
    local container = containerId and db and db.groupContainers
        and db.groupContainers[containerId] or nil

    if not panelId and (not container
        or hasGroupMulti
        or hasPanelMulti) then
        HidePanelPreview(col3)
        return
    end

    local host = col3.buttonsPreviewHost
    -- A settings-only rebuild keeps the saved design and the preview's owner.
    -- Never reuse this path for selection changes or a newly materialized host.
    if edit and edit.preservePreview and edit.panelId == panelId
        and (not edit.moduleKind or edit.previewHost == host)
        and host and host:IsShown() and col3._cdcActiveWideHost == host then
        edit.previewBuilt = true
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, col3.content)
        host:SetClipsChildren(false)
        col3.buttonsPreviewHost = host
    end
    local emptyGroupTakeover = ShouldEmptyGroupPreviewTakeOver(
        containerId, container)
    col3._cdcEmptyGroupPreviewTakeover = emptyGroupTakeover
    AnchorWidePreviewHost(col3, host)
    local function BuildPreview(hostFrame, outcome)
        -- Owns the host's bottom reserve, so it must settle before either
        -- renderer measures itself. Sits inside the build closure so every
        -- rebuild path (selection, resize, preview toggle) refreshes the
        -- strip without its own hook.
        if ST._UpdatePreviewCommandCenter then
            ST._UpdatePreviewCommandCenter(hostFrame)
        end

        local activePanelId = CS.selectedGroup
        if activePanelId then
            SetButtonsPreviewRenderer(hostFrame, "panel")
            -- Anchor-aware build: the unified preview (real mirror + attached
            -- bar lanes) on the anchor panel, the plain mirror elsewhere.
            if ST._BuildAnchorAwarePanelPreview then
                ST._BuildAnchorAwarePanelPreview(hostFrame, activePanelId, outcome)
            elseif ST._BuildButtonPanelPreview then
                if not (outcome and ST._UpdateButtonPanelPreview
                    and ST._UpdateButtonPanelPreview(hostFrame, activePanelId, outcome)) then
                    ST._BuildButtonPanelPreview(hostFrame, activePanelId)
                end
            end
            UpdatePanelWorkspaceChips(col3)
            return
        end

        local activeContainerId = CS.selectedContainer
        local activeContainer = activeContainerId and CooldownCompanion.db.profile.groupContainers
            and CooldownCompanion.db.profile.groupContainers[activeContainerId] or nil
        if activeContainer and ST._BuildGroupPanelOverview then
            SetButtonsPreviewRenderer(hostFrame, "group-overview")
            ST._BuildGroupPanelOverview(hostFrame, activeContainerId)
        end
    end
    if selectionOnly and panelId and host:IsShown()
        and col3._cdcActiveWideHost == host
        and ST._RefreshButtonPanelPreviewSelection then
        local previousReserve = host._cdcPreviewReserveBottom or 0
        if ST._UpdatePreviewCommandCenter then
            ST._UpdatePreviewCommandCenter(host)
        end
        if previousReserve == (host._cdcPreviewReserveBottom or 0) then
            local selectionRefreshed = ST._RefreshButtonPanelPreviewSelection(host, panelId)
            if not selectionRefreshed and host._cdcUnifiedMirrorHost then
                selectionRefreshed = ST._RefreshButtonPanelPreviewSelection(
                    host._cdcUnifiedMirrorHost,
                    panelId
                )
            end
            if selectionRefreshed then
                UpdatePreviewDropOverlay()
                return
            end
        end
    end

    SetActiveWidePreview(col3, host, BuildPreview)
    if not emptyGroupTakeover then
        host:SetHeight(ComputePreviewHostHeight(col3))
    end
    host:Show()
    BuildPreview(host, edit and edit.previewOutcome)
    StampWidePreviewLayout(host)
    if edit and edit.panelId == panelId then
        edit.previewBuilt = true
    end
    UpdatePreviewDropOverlay()
end

-- Add-entry box inside the editing surface (under its header), scoped to
-- the selected panel. Reuses the same TryAdd/autocomplete plumbing as the
-- shared inline add.
local function EnsureAddBox(col3)
    local addBox = col3.buttonsAddBox
    if addBox then return addBox end

    addBox = AceGUI:Create("EditBox")
    if addBox.editbox.Instructions then addBox.editbox.Instructions:Hide() end
    addBox:SetLabel("")
    addBox:SetText("")
    addBox:DisableButton(true)
    addBox.frame:SetParent(col3.content)
    addBox.frame._cdcEditingHeight = ADD_BOX_HEIGHT

    local editFrame = addBox.editbox
    local instructions = editFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    instructions:SetPoint("LEFT", editFrame, "LEFT", 6, 0)
    instructions:SetPoint("RIGHT", editFrame, "RIGHT", -6, 0)
    instructions:SetJustifyH("LEFT")
    instructions:SetTextColor(0.5, 0.5, 0.5)
    instructions:SetText("Add...")
    addBox._cdcInstructions = instructions
    editFrame:SetPoint("BOTTOMRIGHT", addBox.frame, "BOTTOMRIGHT", -18, 0)
    CreateAddBoxInfoButton(addBox.frame, addBox.frame)

    addBox:SetCallback("OnEnterPressed", function(widget, event, text)
        if CS.ConsumeAutocompleteEnter() then return end
        text = text or ""
        if not ShouldSubmitRawAddOnEnter(text) then return end
        CS.HideAutocomplete()
        if text == "" or not CS.selectedGroup then return end
        -- The workspace box always targets the selected panel; a stale
        -- inline-add target left over from browse mode must not win.
        CS.addingToPanelId = nil
        local targetGroupId = CS.selectedGroup
        if not ST._TryAdd(text, { groupId = targetGroupId, tutorialInput = text, clearInput = text }) then return end
        widget:SetText("")
        CS.pendingWideAddFocus = true
        CooldownCompanion:RefreshConfigPanel()
    end)
    addBox:SetCallback("OnTextChanged", function(widget, event, text)
        instructions:SetShown((text or "") == "")
        CS.addingToPanelId = nil
        HideSettingsFinderResults()
        if text and #text >= 1 then
            local results = ST._SearchAutocomplete(text)
            -- This box is persistent (not rebuilt from CS.newInput like the
            -- inline box), so a successful pick must clear it here
            -- or the stale text re-adds on the next Enter press.
            CS.ShowAutocompleteResults(results, widget, function(entry)
                -- Explicit target: the shared select handler prefers
                -- CS.addingToPanelId, which never belongs to this box.
                CS.addingToPanelId = nil
                if ST._OnAutocompleteSelect(entry) then
                    widget:SetText("")
                    instructions:Show()
                end
            end, {
                requireExactNumericEnter = true,
                requireExplicitChoice = true,
                addTargetPanelId = CS.selectedGroup,
                -- The suggestion under consideration ghosts onto this box's
                -- Live Preview (SpellItemAdd's autocomplete ghost); no other
                -- field's dropdown names a host.
                previewGhostHost = col3.buttonsPreviewHost,
            })
        else
            CS.HideAutocomplete()
        end
    end)
    CS.SetupAutocompleteKeyHandler(addBox)
    -- This persistent input owns Tab only while its add-mode popup is active.
    -- Otherwise retain InputBoxTemplate's ordinary focus traversal.
    addBox.editbox:SetScript("OnTabPressed", function(self)
        if not CS.HandleAutocompleteKeyDown("TAB", self) then
            EditBox_OnTabPressed(self)
        end
    end)
    addBox.editbox:HookScript("OnEditFocusGained", function()
        HideSettingsFinderResults()
    end)

    col3.buttonsAddBox = addBox
    return addBox
end

local function UpdateAddBox(col3)
    -- Change... on an Indicator's source also flashes the field, the way a
    -- setting found by search is flashed, so the eye lands on it. Taken here,
    -- first: a request the box cannot honor now must not fire later.
    local wantFlash = CS.pendingWideAddFlash
    CS.pendingWideAddFlash = nil
    local host = col3.buttonsPreviewHost
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    local replacement = CS.GetIndicatorSourceReplacement(CS.selectedGroup)
    local indicator = ST.IsIndicatorGroup(group)
    local canAddEntry = replacement or CanManuallyAddToPanel(group)
    if not (host and host:IsShown() and canAddEntry) then
        if col3.buttonsAddBox then col3.buttonsAddBox.frame:Hide() end
        UpdateEditingActionRow(col3)
        return
    end
    if CS.panelAddModePanelId ~= CS.selectedGroup then
        CS.panelAddModePanelId = CS.selectedGroup
        CS.panelAddPresentation = "icons"
    end
    local addBox = EnsureAddBox(col3)
    if CS.panelAddModeQuery ~= nil then addBox:SetText(CS.panelAddModeQuery) end
    CS.panelAddModeQuery = nil
    addBox._cdcInstructions:SetText(replacement and "Choose a replacement source..."
        or indicator and (ST.Indicator.Primary(group) and "Add a condition source..." or "Choose a source...")
        or "Add...")
    addBox.frame:SetHeight(ADD_BOX_HEIGHT)
    addBox.frame:Show()
    UpdateEditingActionRow(col3)

    -- Also consume the shared autocomplete focus flag when an inline
    -- inline add isn't open (its box consumes it when addingToPanelId is set).
    local wantFocus = CS.pendingWideAddFocus
    if not wantFocus and CS.pendingEditBoxFocus and not CS.addingToPanelId then
        CS.pendingEditBoxFocus = false
        wantFocus = true
    end
    if wantFocus then
        CS.pendingWideAddFocus = false
        C_Timer.After(0, function()
            if addBox.editbox and addBox.frame:IsShown() then
                addBox:SetFocus()
                if wantFlash then ST._FlashConfigFrame(addBox.editbox) end
            end
        end)
    end
end

-- A full-width layout host contains only a compact interactive entry chip.
-- The unused space remains inert; all actions use the shared entry menu.



-- Async adds (uncached item IDs) complete after the add box's Enter
-- handler already returned false; the loader calls this on success so the
-- persistent box doesn't keep the added item's text armed for a duplicate
-- Enter. The text guard skips the clear if the user has typed since; a
-- hidden box still clears (its text would otherwise re-arm on re-show).
local function ClearWideAddBoxAfterAdd(originalInput)
    local col3 = CS.configFrame and CS.configFrame.col3
    local addBox = col3 and col3.buttonsAddBox
    if not addBox then return end
    if originalInput and addBox:GetText() ~= originalInput then return end
    addBox:SetText("")
    if addBox._cdcInstructions then
        addBox._cdcInstructions:Show()
    end
end

-- Extend the Editing path with a selected entry or attached bar. The entry
-- icon, tracking kind, and status badges all share that header line instead
-- of consuming a separate identity row below the add box.
UpdatePanelWorkspaceChips = function(col3)
    if ST._GetPanelWorkspaceChips then
        local rendered = ST._GetLayoutPreviewRenderedSelectionKeys
            and ST._GetLayoutPreviewRenderedSelectionKeys(col3.buttonsPreviewHost) or {}
        local chips = ST._GetPanelWorkspaceChips(rendered)
        local _, resourcePanel = ST._GetBarWorkspacePlacement("resources")
        if resourcePanel and resourcePanel == CS.selectedGroup and ST._CollectBarsOffCanvasChips then
            -- Disabled and unavailable resources retain their fallback route.
            for _, item in ipairs(ST._CollectBarsOffCanvasChips(rendered or {})) do
                chips[#chips + 1] = item
            end
        end
        local visibilityChanged = SetWideEditingChips(col3, "Select:", chips)
        local content = col3._cdcEditingContentFrame
        if visibilityChanged and content and content:IsVisible() then
            AnchorButtonsContentFrame(col3, content)
        end
    end
end

local function UpdateEditingContext(col3)
    UpdatePanelWorkspaceChips(col3)
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    local icon, name, badgeStatus, kindText, sectionText
    if group then
        local multiCount = 0
        for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
        if CS.unifiedBarKind then
            -- Unified anchor preview: name the selected attached bar.
            if CS.unifiedBarKind == "resource" and CS.selectedResourcePowerType then
                local powerNames = ST._RB and ST._RB.POWER_NAMES
                name = powerNames and powerNames[tonumber(CS.selectedResourcePowerType)]
                    or "Resource"
                kindText = "Resource"
            elseif CS.unifiedBarKind == "stack" then
                name = "Resources"
            elseif CS.unifiedBarKind == "player" or CS.unifiedBarKind == "target" then
                name = "Unit Frames"
            elseif CS.unifiedBarKind == "cast" then
                name = "Cast Bar"
            end
        elseif multiCount >= 2 then
            -- Entry multi-select surface lists its members itself.
        elseif CS.selectedButton and group.buttons[CS.selectedButton] then
            local buttonData = group.buttons[CS.selectedButton]
            icon = ST._GetLayoutPreviewIcon and ST._GetLayoutPreviewIcon(buttonData)
            -- Undecorated name: the decoration marks and tracking kind live
            -- in the preview icons' hover tooltip instead.
            name = ST._GetConfigEntryDisplayName
                and ST._GetConfigEntryDisplayName(buttonData)
                or buttonData.name
            -- Same addedAs fallback the name decorations use.
            if buttonData.type == "spell" then
                local addedAs = buttonData.addedAs
                if addedAs ~= "spell" and addedAs ~= "aura" then
                    addedAs = buttonData.isPassive and "aura" or "spell"
                end
                kindText = addedAs == "aura" and "Aura" or "Spell"
            end
            badgeStatus = ST._CollectEntryStatus and ST._CollectEntryStatus(buttonData, group)
            -- Panel Sections: an entry placed in one names it here. The engine
            -- resolves membership, so a base entry and an entry still naming a
            -- dissolved anchor both come back nil and show nothing. The wording
            -- is the shared label table's, never a second copy of it.
            local sectionAnchor = ST.GetPanelSectionForEntry
                and ST.GetPanelSectionForEntry(group, buttonData)
            sectionText = sectionAnchor and ST.PANEL_SECTION_ANCHOR_LABELS[sectionAnchor]
            -- An AURA section is a different thing to sit in than an ordinary
            -- one: the entry draws through Blizzard's container rather than as
            -- a CC icon. The marker rides the same tail, one middot further
            -- out, so "where" and "how" read as one phrase.
            if sectionText and ST.IsAuraOnlyPanelSection(group, sectionAnchor) then
                sectionText = sectionText .. " \194\183 Aura"
            end
        end
    end

    if name then
        col3._cdcEditingContext = {
            icon = icon,
            name = name,
            badgeStatus = badgeStatus,
            kindText = kindText,
            sectionText = sectionText,
        }
    else
        col3._cdcEditingContext = nil
    end
    UpdateEditingHeader(col3)
end

-- Validate the unified bar selection before showing its settings: clears
-- it (returning nil) when the panel stopped being the anchor target, the
-- bar was deleted, or its module was disabled.
local function GetValidatedUnifiedBarKind()
    local kind = CS.unifiedBarKind
    if not kind then return nil end
    local owner = (kind == "cast") and "castbar"
        or (kind == "player" or kind == "target") and kind or "resources"
    local _, anchorId = ST._GetBarWorkspacePlacement(owner)
    if anchorId ~= CS.selectedGroup or not anchorId then
        CS.unifiedBarKind = nil
        return nil
    end
    if kind == "stack" or kind == "player" or kind == "target" then return kind end
    if kind == "resource" then
        local settings = CooldownCompanion:GetResourceBarSettings()
        local RBP = ST._RBP
        if not (CS.selectedResourcePowerType and RBP and RBP.IsResourceEditableInColumn4
            and RBP.IsResourceEditableInColumn4(CS.selectedResourcePowerType, settings, true)) then
            CS.unifiedBarKind = nil
            return nil
        end
    elseif kind == "cast" then
        local cb = CooldownCompanion:GetCastBarSettings()
        local independent = cb and CooldownCompanion:IsModuleAnchorIndependent("castbar")
        if not (cb and cb.enabled == true and not independent) then
            CS.unifiedBarKind = nil
            return nil
        end
    else
        CS.unifiedBarKind = nil
        return nil
    end
    return kind
end

-- True when the column should show entry settings instead of the
-- group-side surfaces: a valid single entry or an entry multi-select.
local function IsEntrySelectionActive()
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then
        return false
    end
    local multiCount = 0
    for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
    if multiCount >= 2 then
        return true
    end

    return CS.selectedButton ~= nil and group.buttons[CS.selectedButton] ~= nil
end

-- Raw host for the panel-scope settings surfaces. It carries the panel half
-- of the unified tab row, so it is shown for an entry selection too - the
-- entry cluster is appended beside those tabs rather than replacing them.
local function EnsureGroupSettingsHost(col3)
    local host = col3.groupSettingsHost
    if not host then
        host = CreateFrame("Frame", nil, col3.content)
        col3.groupSettingsHost = host
    end
    return host
end

local function EnsureInlineTextureBrowserHost(col3)
    local host = col3._inlineTextureBrowserHost
    if host then return host end
    host = CreateFrame("Frame", nil, col3.content)
    col3._inlineTextureBrowserHost = host
    return host
end

local function ShowMultiSelectActions(col3, refreshFn, multiCount, selectedIds)
    -- Batch actions replace the edited object rather than refreshing it.
    -- Do not carry a Finder query or captured identity into this takeover.
    ClearSettingsFinderActionRowState(col3)
    HideEntrySurfaces(col3)
    HidePanelPreview(col3)
    if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end

    if not col3._multiSelectActionsScroll then
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(col3.content)
        scroll.frame:ClearAllPoints()
        scroll.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
        scroll.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
        col3._multiSelectActionsScroll = scroll
    end
    col3._multiSelectActionsScroll:ReleaseChildren()
    col3._multiSelectActionsScroll.frame:Show()
    refreshFn(col3._multiSelectActionsScroll, multiCount, selectedIds)
    -- AddChild lays out on every insertion, so width overrides applied after a
    -- builder returns are invisible until one final layout pass.
    col3._multiSelectActionsScroll:DoLayout()
end

local function CollectSelection(set)
    local count, ids = 0, {}
    for id in pairs(set) do
        count = count + 1
        ids[#ids + 1] = id
    end
    return count, ids
end

local function RefreshButtonsWideColumn(selectionOnly, edit)
    local col3 = CS.configFrame and CS.configFrame.col3
    if not col3 then return end

    -- Hide surfaces owned by the resources/cast homes that share col3
    if ST._HideResourcesWideSurfaces then ST._HideResourcesWideSurfaces(col3, true) end
    if col3._inlineTextureBrowserHost then col3._inlineTextureBrowserHost:Hide() end

    -- Group multi-select: batch operations replace everything else.
    local groupMultiCount, multiGroupIds = CollectSelection(CS.selectedGroups)
    if groupMultiCount >= 2 then
        ShowMultiSelectActions(col3, ST._RefreshGroupMultiSelect,
            groupMultiCount, multiGroupIds)
        return
    end

    -- Panel multi-select uses the same batch-action host.
    local panelMultiCount, multiPanelIds = CollectSelection(CS.selectedPanels)
    if panelMultiCount >= 2 and CS.selectedContainer then
        ShowMultiSelectActions(col3, ST._RefreshPanelMultiSelect,
            panelMultiCount, multiPanelIds)
        return
    end
    if col3._multiSelectActionsScroll then
        col3._multiSelectActionsScroll.frame:Hide()
    end

    -- The inline texture browser is scoped to its own panel; drop a stale flag
    -- when the selection moved away, so IsAuraTexturePickerOpen never reports
    -- it open over the wrong surface.
    if CS.inlineTextureBrowserOpen
        and CS.inlineTextureBrowserOpen ~= CS.selectedGroup
    then
        CloseInlineTextureBrowser(col3)
    end

    if CS.inlineTextureBrowserOpen and ST._RenderInlineTextureBrowser then
        local browserGroup = CooldownCompanion.db.profile.groups[CS.selectedGroup]
        if browserGroup and CooldownCompanion:IsStandaloneTexturePanelGroup(browserGroup) then
            -- Same as the multi-select takeover above: the settings host goes
            -- away without its own tab seams running, so settle the format
            -- editor first. Release is idempotent.
            HideEntrySurfaces(col3)
            if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end
            UpdatePanelPreview(col3, selectionOnly, edit)
            UpdateAddBox(col3)

            UpdateEditingContext(col3)
            local host = EnsureInlineTextureBrowserHost(col3)
            AnchorButtonsContentFrame(col3, host)
            host:Show()
            ST._RenderInlineTextureBrowser(host)
            return
        end
        -- Selected panel is no longer an Indicator; drop
        -- the flag and fall through to the normal branches.
        CloseInlineTextureBrowser(col3)
    end

    -- Attached bar selected in the unified anchor preview: that bar's
    -- settings own the settings area
    local unifiedBarKind = GetValidatedUnifiedBarKind()
    if unifiedBarKind then
        HideEntrySurfaces(col3)
        UpdatePanelPreview(col3, selectionOnly, edit)
        UpdateAddBox(col3)

        UpdateEditingContext(col3)

        -- The selected object owns the settings area. Reuse exactly the
        -- standalone resource/cast surfaces, with the panel preview retained.
        if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end
        if unifiedBarKind == "stack" or unifiedBarKind == "resource" then
            ST._ShowResourceWorkspaceSurfaces(col3)
            return
        elseif unifiedBarKind == "player" or unifiedBarKind == "target" then
            ST._ShowUnitFrameSettingsSurface(col3)
            return
        elseif unifiedBarKind == "cast" then
            ST._ShowCastBarSettingsSurface(col3)
            return
        end
        -- The surface didn't materialize (transient state); clear the bar
        -- selection and run a clean pass through the normal branches.
        CS.unifiedBarKind = nil
        return RefreshButtonsWideColumn()
    end

    -- Entry selected: the entry tabs join the panel tabs in one row, and
    -- whichever scope owns the surface builds its content there.
    if IsEntrySelectionActive() then
        UpdatePanelPreview(col3, selectionOnly, edit)
        UpdateAddBox(col3)

        UpdateEditingContext(col3)

        local host = EnsureGroupSettingsHost(col3)
        AnchorButtonsContentFrame(col3, host)
        host:Show()
        -- Panel tabs first: the entry strip is offset by their measured
        -- width, and only one of the two builds content.
        ST._RefreshGroupSettingsHost(host, nil, ST._UnifiedRowGetScope() ~= "primary")

        if col3.bsTabGroup then
            AnchorButtonsContentFrame(col3, col3.bsTabGroup.frame)
        end
        ST._RefreshButtonSettingsColumn()
        return
    end

    -- Otherwise the group-side surfaces (panel and Group settings,
    -- placeholders) own the settings area
    HideEntrySurfaces(col3)
    UpdatePanelPreview(col3, selectionOnly, edit)
    UpdateAddBox(col3)

    UpdateEditingContext(col3)

    -- The empty Group picker is the only actionable surface until a Panel is
    -- created. Keep stale Group settings and the split chrome fully out of the
    -- workspace; the next refresh restores both automatically once one exists.
    if col3._cdcEmptyGroupPreviewTakeover == true then
        if col3.groupSettingsHost then
            col3.groupSettingsHost:Hide()
        end
        HideEditingChrome(col3)
        return
    end

    local host = EnsureGroupSettingsHost(col3)
    AnchorButtonsContentFrame(col3, host)
    host:Show()
    ST._RefreshGroupSettingsHost(host)
    -- No entry cluster in the row: the panel strip owns the surface again.
    ST._UnifiedRowApply()
end

-- Rebuild just the pinned mirror (e.g. after a preview toggle flips, or
-- from UpdateGroupStyle so style edits reflect immediately) without a full
-- config refresh. An optional groupId scopes the rebuild: updates to a
-- panel other than the mirrored one are skipped.
local function RefreshButtonsPreviewMirror(groupId, visualOnly, outcome)
    if not (ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive()) then return end
    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3.buttonsPreviewHost
    if not (host and host:IsShown() and col3._cdcActiveWideHost == host) then return end

    if CS.selectedGroup then
        if groupId and groupId ~= CS.selectedGroup then return end
        if not col3._cdcActiveWideRebuild then return false end
        col3._cdcActiveWideRebuild(host, outcome)
        if not visualOnly then
            -- Discrete edits can change identity/status chrome. Continuous
            -- controls pass visualOnly because repainting this metadata on
            -- every drag tick is unrelated to the visual candidate.
            UpdateEditingContext(col3)

        end
        return true
    end

    local containerId = CS.selectedContainer
    if not containerId or host._cdcButtonsPreviewMode ~= "group-overview" then return end
    if groupId then
        local belongsToSelectedContainer = false
        for _, panelInfo in ipairs(CooldownCompanion:GetPanels(containerId) or {}) do
            if tostring(panelInfo.groupId) == tostring(groupId) then
                belongsToSelectedContainer = true
                break
            end
        end
        if not belongsToSelectedContainer then return end
    end
    if col3._cdcActiveWideRebuild then
        col3._cdcActiveWideRebuild(host)
        return true
    end
end

ST._RefreshButtonsWideColumn = RefreshButtonsWideColumn
ST._AnchorButtonsContentFrame = AnchorButtonsContentFrame
-- Shared wide-preview plumbing (also used by the Resources wide column):
-- host registration, the height computation, the build-size record, and
-- the resize refit.
ST._SetActiveWidePreview = SetActiveWidePreview
ST._ClearActiveWidePreview = ClearActiveWidePreview
ST._ComputeWidePreviewHostHeight = ComputePreviewHostHeight
ST._RefreshButtonsPreviewMirror = RefreshButtonsPreviewMirror
ST._RefitWidePreviewHost = RefitWidePreviewHost
ST._StampWidePreviewLayout = StampWidePreviewLayout
ST._ClearWideAddBoxAfterAdd = ClearWideAddBoxAfterAdd
ST._SetWideEditingAddBox = SetWideEditingAddBox
ST._SetWideEditingChips = SetWideEditingChips
ST._ClearWideEditingExtras = ClearWideEditingExtras
-- Editing-surface hide for view branches that release the preview/editing
-- pair while their own preview host holds it (Resources/cast homes).
ST._HideWideEditingChrome = HideEditingChrome
-- Shared teardown for view switches away from the buttons view (resources,
-- cast frames, talent picker, config close): hides the preview surfaces AND
-- releases the preview so its conditional ticker and texture-mirror effects
-- stop. Transient same-view hides must NOT use this - the following rebuild
-- pass re-shows the preview, and tearing it down would be wasted work.
ST._HideButtonsPanelPreviewSurfaces = HidePanelPreview
