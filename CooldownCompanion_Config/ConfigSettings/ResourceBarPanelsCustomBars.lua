--[[
    CooldownCompanion - ResourceBarPanelsCustomBars
    Config panel builders for the Custom Bars list, editor, tabs,
    badges, row actions, and preview toggles.
    Query helpers and shared builders live in ResourceBarPanelsHelpers.lua.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local IsPassiveOrProc = ST._IsPassiveOrProc
local ShowPopupAboveConfig = CS.ShowPopupAboveConfig
local SelectConfigCustomBar = ST._SelectConfigCustomBar
local ClearConfigCustomBarSelection = ST._ClearConfigCustomBarSelection

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AnchorLeftAlignedHeadingRule = ST._AnchorLeftAlignedHeadingRule
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local AddFontControls = ST._AddFontControls
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown

-- Imports from RowWidgets.lua (the row grammar). The rules every row-grammar
-- section follows are stated once, in the recipe comment at the top of
-- BuildAppearanceTab's icons path (GroupTabsAppearance.lua); this file conforms to them
-- rather than restating them.
local AddCheckboxRow = ST._AddCheckboxRow
local AddDropdownRow = ST._AddDropdownRow
local AddSoundPreviewDropdownRow = ST._AddSoundPreviewDropdownRow
local AddColorRow = ST._AddColorRow
local AddEditBoxRow = ST._AddEditBoxRow
local AddLabelRow = ST._AddLabelRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

-- Sound option labels read "Category - Name" and run well past the 140px
-- control column, and a dropdown sizes its menu from the control.
local SOUND_PULLOUT_WIDTH = 300

-- Row-grammar action strip metrics: the talent section's closing row puts its
-- buttons in the row's control column (same treatment as the entry Visibility
-- tab in ButtonConditions.lua). Flow insets its single row by 3px top and
-- bottom, so 3 + 24 + 3 centres inside the 30px band.
local ACTION_STRIP_HEIGHT = (ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT) or 30
local ACTION_STRIP_BUTTON_HEIGHT = 24
local ACTION_STRIP_GUTTER = 4
local ROW_CONTROL_WIDTH = (ST._RowGrammar and ST._RowGrammar.CONTROL_COLUMN_WIDTH) or 140

local function RefreshLayoutOrderPreview()
    -- Both the Resources home and the Cast Bar & Unit Frames home pin the
    -- preview in the workspace; the helper self-gates on view state.
    if ST._RefreshResourcesLayoutPreview then
        ST._RefreshResourcesLayoutPreview()
    end
end

-- Mirror-first slider wiring and its drag-tick repaint (owner ruling
-- 2026-08-02, contract stated once in ResourceBarPanelsHelpers.lua). That file
-- loads before this one, so both alias at file scope.
local AddMirrorFirstSliderRow = ST._AddMirrorFirstSliderRow
local RefreshLayoutOrderPreviewForDrag = ST._RefreshResourcesCanvasForDrag

-- Shared constants from ResourceBarConstants
local RB = ST._RB
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE
local DEFAULT_RESOURCE_TEXT_COLOR = RB.DEFAULT_RESOURCE_TEXT_COLOR
local GetCustomBarEntryType = RB.GetCustomBarEntryType
local EnsureCustomBarId = RB.EnsureCustomBarId
local EnsureCustomBarLayout = RB.EnsureCustomBarLayout
local GetCustomBarLayout = RB.GetCustomBarLayout
local resourceSpecCopyButton
local resourceSpecCopyMenu

local function IsHeroSpecProxyCondition(cond)
    return type(cond) == "table"
        and cond.nodeID ~= nil
        and cond.heroSubTreeID ~= nil
        and cond.entryID == nil
        and type(cond.name) == "string"
        and type(cond.heroName) == "string"
        and cond.name == cond.heroName
end
local function IsSpellCustomBarConfig(cab)
    if RB.IsSpellCustomBarConfig then
        return RB.IsSpellCustomBarConfig(cab)
    end
    return GetCustomBarEntryType and GetCustomBarEntryType(cab) == "spell"
end

-- Imports from ResourceBarPanelsHelpers
local RBP = ST._RBP
local resourceBarCollapsedSections = RBP.collapsedSections
local BuildResourceBarConflictGate = RBP.BuildResourceBarConflictGate
local GetCurrentConfigSpecID = RBP.GetCurrentConfigSpecID
local ResolveAuraColorSpellIDFromText = RBP.ResolveAuraColorSpellIDFromText
local GetAuraBarAutocompleteDisplayName = RBP.GetAuraBarAutocompleteDisplayName
local GetAuraBarAutocompleteDisplayIcon = RBP.GetAuraBarAutocompleteDisplayIcon
local GetAuraBarAutocompleteEntryName = RBP.GetAuraBarAutocompleteEntryName
local ResolveAuraBarAutocompleteEntry = RBP.ResolveAuraBarAutocompleteEntry
local ShowAuraBarAutocompleteResults = RBP.ShowAuraBarAutocompleteResults
local BuildAuraBarAutocompleteCache = RBP.BuildAuraBarAutocompleteCache
local GetResourceThicknessFieldConfig = RBP.GetResourceThicknessFieldConfig
local CopyTableValue = RBP.CopyTableValue

------------------------------------------------------------------------
-- Custom Bars detail panel
------------------------------------------------------------------------

local function ApplyCustomAuraBarPanelChanges(opts)
    CooldownCompanion:ApplyResourceBars()
    if opts and opts.updateAnchors then
        CooldownCompanion:UpdateAnchorStacking()
    end
    if opts and opts.refreshConfig then
        CooldownCompanion:RefreshConfigPanel()
    end
    if opts and opts.refreshLayoutPreview then
        RefreshLayoutOrderPreview()
    end
end

local function FindCustomBarIndexById(customBars, customBarId)
    if type(customBars) ~= "table" or type(customBarId) ~= "string" then
        return nil
    end
    for index, entry in ipairs(customBars) do
        if type(entry) == "table" and entry.customBarId == customBarId then
            return index
        end
    end
    return nil
end

local function GetCustomBarSpecOptions()
    local specs = {}
    local _, _, classID = UnitClass("player")
    local numSpecs = classID
        and C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
        or 0
    for specIndex = 1, numSpecs do
        local specID, specName, _, specIcon = C_SpecializationInfo.GetSpecializationInfo(
            specIndex,
            false,
            false,
            nil,
            nil,
            nil,
            classID
        )
        if specID then
            specs[#specs + 1] = {
                id = specID,
                name = specName or ("Spec " .. tostring(specID)),
                icon = specIcon,
            }
        end
    end
    return specs
end

-- Every collapsible section on a Custom Bar's Settings pane is keyed per
-- bar, so collapsing one bar's section leaves the next bar's alone.
local function GetCustomBarCollapseKey(cab)
    return tostring((type(cab) == "table" and cab.customBarId) or "")
end

local function AddCustomBarSection(container, title, name, key)
    local fullKey = "cab_" .. name .. "_" .. key
    local heading, collapsed = BuildCollapsibleSection(container, title, fullKey,
        resourceBarCollapsedSections, nil, ROW_SECTION)
    -- A routed gear click (PreviewCommandCenter) names one section of the
    -- pane; remember its heading so the caller can scroll it into view
    -- after this rebuild lays out.
    if CS.pendingCustomBarScrollSection == fullKey then
        container._cdcPendingScrollHeading = heading
    end
    return heading, collapsed
end

-- One CDC-CheckBoxRow per spec this class can play, split down the middle of
-- the caller's grid. The store writes are untouched: this path deliberately
-- does NOT go through SetSpecFilterValue/SetSpecAllowlistValue, it drives
-- RB.AddCustomBarToSpec/RB.RemoveCustomBarFromSpec directly.
local function AddCustomBarSpecFilterControls(specLeft, specRight, settings, entry, currentSpecID)
    local specs = GetCustomBarSpecOptions()
    local splitAt = math.ceil(#specs / 2)
    for index, spec in ipairs(specs) do
        local capturedSpec = spec
        -- The spec icon rides an inline texture escape in the label text: a
        -- row label is a FontString, so there is no SetImage to hang it off
        -- the way the stock checkbox did.
        local label = capturedSpec.name
        if capturedSpec.icon then
            label = ("|T%s:16:16:0:0|t %s"):format(tostring(capturedSpec.icon), label)
        end
        AddCheckboxRow(index <= splitAt and specLeft or specRight, {
            label = label,
            value = RB.CustomBarHasExplicitSpec and RB.CustomBarHasExplicitSpec(entry, capturedSpec.id) or false,
            onChange = function(value)
                if value then
                    if RB.AddCustomBarToSpec then
                        RB.AddCustomBarToSpec(settings, entry, capturedSpec.id, currentSpecID)
                    end
                else
                    if RB.RemoveCustomBarFromSpec then
                        RB.RemoveCustomBarFromSpec(settings, entry, capturedSpec.id)
                    end
                end
                ApplyCustomAuraBarPanelChanges({
                    updateAnchors = true,
                    refreshConfig = true,
                    refreshLayoutPreview = true,
                })
            end,
        })
    end
end

local function ConfigureCustomBarAddInstructions(addBox, placeholderText)
    local editFrame = addBox and addBox.editbox
    if not editFrame then
        return function() end
    end

    local instructions = editFrame._cdcCustomBarAddInstructions
    if not instructions then
        instructions = editFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        instructions:SetPoint("LEFT", editFrame, "LEFT", 6, 0)
        instructions:SetPoint("RIGHT", editFrame, "RIGHT", -6, 0)
        instructions:SetJustifyH("LEFT")
        instructions:SetTextColor(0.5, 0.5, 0.5)
        editFrame._cdcCustomBarAddInstructions = instructions
    end
    instructions:SetText(placeholderText)

    local function Update(text)
        instructions:SetShown((text or "") == "")
    end

    local prevOnRelease = addBox.events and addBox.events["OnRelease"]
    addBox:SetCallback("OnRelease", function(widget)
        if prevOnRelease then
            prevOnRelease(widget, "OnRelease")
        end
        instructions:Hide()
        instructions:SetText("")
    end)

    Update(editFrame:GetText())
    return Update
end

local function DeleteCustomBarById(settings, specID, customBars, customBarId)
    if RB.DeleteCustomBar then
        return RB.DeleteCustomBar(settings, customBarId)
    end

    return false
end

-- What a Custom Bar is called in prose the owner reads (popup text, tooltips):
-- its own label, else the tracked spell's name, else a generic fallback.
local function GetCustomBarDisplayName(entry)
    if type(entry) ~= "table" then
        return "Custom Bar"
    end
    local name = entry.label
    if not name or name == "" then
        local spellID = tonumber(entry.spellID)
        name = spellID and C_Spell.GetSpellName(spellID) or nil
    end
    if not name or name == "" then
        return "Custom Bar"
    end
    return name
end

-- The Delete menu item's confirmed half. Ids freeze when the popup opens, so
-- everything this needs is re-resolved here rather than captured: the bar may
-- already be gone, or the config may have moved on, by the time it runs.
local function DeleteConfigCustomBar(customBarId)
    local settings = CooldownCompanion:GetResourceBarSettings()
    local customBars = RB.GetAllCustomBars and RB.GetAllCustomBars(settings)
        or CooldownCompanion:GetSpecCustomAuraBars()
    if DeleteCustomBarById(settings, GetCurrentConfigSpecID(), customBars, customBarId) then
        if CS.selectedCustomBarId == customBarId then
            ClearConfigCustomBarSelection()
        end
        if CS.customBarSpecExpandedId == customBarId then
            CS.customBarSpecExpandedId = nil
        end
    end
    ApplyCustomAuraBarPanelChanges({
        updateAnchors = true,
        refreshConfig = true,
    })
end

local function DuplicateCustomBarById(settings, specID, customBars, customBarId)
    local sourceIndex = FindCustomBarIndexById(customBars, customBarId)
    local sourceEntry = sourceIndex and customBars[sourceIndex]
    if type(settings) ~= "table" or type(sourceEntry) ~= "table" then
        return nil
    end

    local fallbackOrder = 1000 + sourceIndex + 1
    local newId
    if RB.DuplicateCustomBar then
        newId = RB.DuplicateCustomBar(settings, sourceEntry, specID, fallbackOrder)
    elseif RB.AddCustomBar then
        local sourceLayout = GetCustomBarLayout(settings, specID, sourceEntry, false)
        local copy = CopyTable(sourceEntry)
        copy.customBarId = nil
        newId = RB.AddCustomBar(settings, copy, specID, fallbackOrder)
        if newId then
            local targetLayout = EnsureCustomBarLayout(settings, specID, newId, fallbackOrder)
            if type(sourceLayout) == "table" and type(targetLayout) == "table" then
                for key, value in pairs(sourceLayout) do
                    targetLayout[key] = CopyTableValue(value)
                end
                if sourceLayout.order ~= nil then
                    targetLayout.order = (tonumber(sourceLayout.order) or 1000) + 1
                end
                if sourceLayout.verticalOrder ~= nil then
                    targetLayout.verticalOrder = (tonumber(sourceLayout.verticalOrder) or 1000) + 1
                end
            end
        end
    else
        local copy = CopyTable(sourceEntry)
        copy.customBarId = nil
        newId = EnsureCustomBarId(settings, copy)
        table.insert(customBars, sourceIndex + 1, copy)
    end
    if not newId then
        return nil
    end

    return newId
end

local function OpenCustomBarRowMenu(customBars, specID, customBarId, entry)
    if not CS.customBarContextMenu then
        CS.customBarContextMenu = CreateFrame("Frame", "CDCCustomBarContextMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(CS.customBarContextMenu, function(_, level)
        if level ~= 1 then return end

        local toggleInfo = UIDropDownMenu_CreateInfo()
        toggleInfo.text = (entry.enabled == true) and "Disable" or "Enable"
        toggleInfo.notCheckable = true
        toggleInfo.func = function()
            CloseDropDownMenus()
            entry.enabled = entry.enabled ~= true
            if entry.enabled and not entry.trackingMode then
                entry.trackingMode = "active"
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end
        UIDropDownMenu_AddButton(toggleInfo, level)

        local duplicateInfo = UIDropDownMenu_CreateInfo()
        duplicateInfo.text = "Duplicate"
        duplicateInfo.notCheckable = true
        duplicateInfo.func = function()
            CloseDropDownMenus()
            local newId = DuplicateCustomBarById(CooldownCompanion:GetResourceBarSettings(), specID, customBars, customBarId)
            if newId then
                SelectConfigCustomBar(newId)
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end
        UIDropDownMenu_AddButton(duplicateInfo, level)

        -- Red "Delete" behind a confirmation, matching how the navigator's
        -- group and panel menus spend the same destructive gesture.
        local deleteInfo = UIDropDownMenu_CreateInfo()
        deleteInfo.text = "|cffff4444Delete|r"
        deleteInfo.notCheckable = true
        deleteInfo.func = function()
            CloseDropDownMenus()
            ShowPopupAboveConfig("CDC_DELETE_CUSTOM_BAR", GetCustomBarDisplayName(entry),
                { customBarId = customBarId })
        end
        UIDropDownMenu_AddButton(deleteInfo, level)
    end, "MENU")

    CS.customBarContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.customBarContextMenu, "cursor", 0, 0)
end

local function OpenConfigCustomBarMenu(customBarId)
    local settings = CooldownCompanion:GetResourceBarSettings()
    local customBars = RB.GetAllCustomBars and RB.GetAllCustomBars(settings)
        or CooldownCompanion:GetSpecCustomAuraBars()
    local index = FindCustomBarIndexById(customBars, customBarId)
    local entry = index and customBars[index]
    if not entry then return false end
    OpenCustomBarRowMenu(customBars, RBP.GetCurrentConfigSpecID(), customBarId, entry)
    return true
end

local function BuildCustomBarSoundAlertsTab(container, cab, infoButtons)
    local soundHeading, soundCollapsed =
        AddCustomBarSection(container, "Sound Alerts", "sound", GetCustomBarCollapseKey(cab))

    local soundInfoBtn = CreateInfoButton(soundHeading.frame, soundHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Sound Alerts",
        {"Sound effects use the Master channel and follow Master Volume. Text to Speech uses WoW's selected voice, speech rate, and speech volume.", 1, 1, 1, true},
        {" ", 1, 1, 1, false},
        {"Aura-event alerts use Blizzard's aura-sound API, which supports file-backed sounds only. Cooldown Manager sound-kit choices and Text to Speech are therefore unavailable in these aura-event menus.", 1, 1, 1, true},
    }, infoButtons)
    AnchorLeftAlignedHeadingRule(soundHeading, soundInfoBtn)

    if soundCollapsed then return end

    local validEvents = CooldownCompanion:GetScopedValidSoundAlertEventsForCustomBar(cab)
    if not validEvents then
        local noEvents = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(noEvents)
        noEvents:SetText("|cff888888No alertable sound events are available for this Custom Bar entry.|r")
        noEvents:SetFullWidth(true)
        container:AddChild(noEvents)
        return
    end

    local soundOptions = CooldownCompanion:GetSoundAlertOptions()
    local soundOptionOrder = CooldownCompanion:GetSoundAlertOptionOrder(soundOptions)
    local eventOrder = CooldownCompanion:GetSoundAlertEventOrder()

    -- The aura sounds play through Blizzard's aura system, which accepts
    -- sound files only — offer the file-backed options (panel parity).
    local auraSoundOptions, auraSoundOptionOrder
    if validEvents.onAuraApplied or validEvents.onAuraStackGained or validEvents.onAuraRemoved then
        auraSoundOptions = CooldownCompanion:GetAuraSoundAlertOptions()
        auraSoundOptionOrder = CooldownCompanion:GetSoundAlertOptionOrder(auraSoundOptions)
    end

    -- This row set is FILTERED (see the fill rule in the recipe comment): a
    -- Custom Bar carries only the event families its entry type allows, and an
    -- aura bar has no cooldown events at all. So the family split - LEFT the
    -- cooldown-side events, RIGHT the aura-side ones (the native C_UnitAuras
    -- triggers, the same split the runtime keeps) - only runs when BOTH
    -- families survive the filter. When one family is all that is left it
    -- splits itself across the columns left-first, so the left column is never
    -- the empty one.
    local cooldownEvents, auraEvents = {}, {}
    for _, eventKey in ipairs(eventOrder) do
        if validEvents[eventKey] then
            local family = CooldownCompanion:IsAuraSoundAlertEvent(eventKey) and auraEvents or cooldownEvents
            family[#family + 1] = eventKey
        end
    end

    local soundLeft, soundRight = BeginRowGrid(container)

    local function AddSoundEventRow(column, eventKey)
        local isAuraEvent = CooldownCompanion:IsAuraSoundAlertEvent(eventKey)
        AddSoundPreviewDropdownRow(column, {
            label = CooldownCompanion:GetCustomBarSoundAlertEventLabel(cab, eventKey),
            pulloutWidth = SOUND_PULLOUT_WIDTH,
            list = isAuraEvent and auraSoundOptions or soundOptions,
            order = isAuraEvent and auraSoundOptionOrder or soundOptionOrder,
            value = CooldownCompanion:GetCustomBarSoundAlertSelection(cab, eventKey),
            onChange = function(val)
                CooldownCompanion:SetCustomBarSoundAlertEvent(cab, eventKey, val)
                if isAuraEvent then
                    -- The native registration lives on the aura display
                    -- binding, so the edit only lands on the next rebind.
                    CooldownCompanion:RequestAuraRebind("config")
                end
                CooldownCompanion:RefreshConfigPanel()
            end,
            onPreview = function(value)
                CooldownCompanion:PreviewCustomBarSoundAlertSelection(cab, value)
            end,
        })
    end

    if #cooldownEvents > 0 and #auraEvents > 0 then
        for _, eventKey in ipairs(cooldownEvents) do
            AddSoundEventRow(soundLeft, eventKey)
        end
        for _, eventKey in ipairs(auraEvents) do
            AddSoundEventRow(soundRight, eventKey)
        end
    else
        -- ceil(n/2) left, the rest right - the per-resource Colors precedent.
        local survivors = (#cooldownEvents > 0) and cooldownEvents or auraEvents
        local splitAt = math.ceil(#survivors / 2)
        for index, eventKey in ipairs(survivors) do
            AddSoundEventRow(index <= splitAt and soundLeft or soundRight, eventKey)
        end
    end
end

local function BuildCustomBarLoadConditionsTab(container, cab, infoButtons)
    local settings = CooldownCompanion:GetResourceBarSettings()
    local currentSpecID = GetCurrentConfigSpecID()

    -- The who-half of this tab: which specs the bar belongs to. The
    -- where-half is the shared toggles below.
    local _, specsCollapsed =
        AddCustomBarSection(container, "Specializations", "specs", GetCustomBarCollapseKey(cab))

    if not specsCollapsed then
        local specLeft, specRight = BeginRowGrid(container)
        AddCustomBarSpecFilterControls(specLeft, specRight, settings, cab, currentSpecID)
    end

    -- ButtonConditions.lua loads after this file, so both helpers are read at
    -- call time rather than captured at file scope.
    local addScopedLoadConditionToggles = ST._AddScopedLoadConditionToggles
    local buildWhereToHideTooltip = ST._BuildWhereToHideTooltip
    if type(addScopedLoadConditionToggles) ~= "function" then
        local unavailable = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(unavailable)
        unavailable:SetText("|cff888888Visibility controls are not available yet.|r")
        unavailable:SetFullWidth(true)
        container:AddChild(unavailable)
        return
    end

    local _, togglesRight = addScopedLoadConditionToggles(container, {
        target = cab,
        defaults = CooldownCompanion:GetLocalLoadConditionDefaults(),
        inheritedSources = {},
        headingText = "Where To Hide It",
        localCollapsedKey = "loadconditions_custombar_local",
        preserveMissing = true,
        row = true,
        infoTooltipLines = type(buildWhereToHideTooltip) == "function"
            and buildWhereToHideTooltip("bar", false) or nil,
        infoButtons = infoButtons,
        onChanged = function()
            if cab.loadConditions and not next(cab.loadConditions) then
                cab.loadConditions = nil
            end
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if CooldownCompanion:HasLocalLoadConditions(cab) then
        -- Compact and flush left, filling the shorter (4-row) right column's
        -- tail. With the section collapsed there is no grid to sit in, so it
        -- falls back to the tab surface - still reachable, still compact.
        local clearHost = togglesRight or container
        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear Bar Visibility Rules")
        clearBtn:SetAutoWidth(true)
        clearBtn:SetCallback("OnClick", function()
            cab.loadConditions = nil
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end)
        clearHost:AddChild(clearBtn)
    end
end

-- A collapsible row-grammar section header with the optional "?" chained off
-- the end of its label; the fading rule restarts after that badge.
local function AddCustomBarSettingsHeading(container, text, name, key, infoButtons, tooltip)
    local heading, collapsed = AddCustomBarSection(container, text, name, key)

    if tooltip then
        local tooltipLines = { text }
        if type(tooltip) == "table" then
            for _, line in ipairs(tooltip) do
                tooltipLines[#tooltipLines + 1] = { line, 1, 1, 1, true }
            end
        else
            tooltipLines[#tooltipLines + 1] = { tooltip, 1, 1, 1, true }
        end
        local infoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
            unpack(tooltipLines)
        }, infoButtons)
        AnchorLeftAlignedHeadingRule(heading, infoBtn)
    end

    return heading, collapsed
end

local function AddResourceBarsDisabledLabel(container, text)
    local label = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText(text)
    label:SetFullWidth(true)
    container:AddChild(label)
end

------------------------------------------------------------------------
-- Aura tracking section (the aura pass): the panel Aura-tab vocabulary on
-- custom bars. The tracked unit is auto-derived from spell polarity and
-- never user-set (Blizzard's anti-cheat gate makes illegal configurations
-- unrepresentable); max stacks is automatic from game data. Every change
-- goes through ApplyResourceBars, which requests the OOC aura rebind.
------------------------------------------------------------------------

local function RefreshCustomBarAuraConfig()
    CooldownCompanion:ApplyResourceBars()
    CooldownCompanion:RefreshConfigPanel()
end

-- Shared tracked-aura list rules (SectionBuilders.lua), the same ones the
-- panel Aura tab runs on.
local ClassifyAuraSpellUnit = ST._ClassifyAuraSpellUnit
local GetAuraCandidateList = ST._GetAuraCandidateList
local TryAddAuraCandidate = ST._TryAddAuraCandidate
local RemoveAuraCandidate = ST._RemoveAuraCandidate
local AddAuraCandidateRow = ST._AddAuraCandidateRow
local AddAuraStackMaxStatusLabel = ST._AddAuraStackMaxStatusLabel
-- The same three marker styling rows the panel Pandemic section hangs off its
-- gear. Custom bars keep the marker keys FLAT on the entry under exactly these
-- names (ResourceBarAuraHost's style adapter reads them straight through), so
-- the shared builder writes the right store with `cab` handed in as the style.
local AddPandemicMarkerControls = ST._AddPandemicMarkerControls

-- Candidate-resolution probe: the buttonData shape Core/Aura.lua reads,
-- synthesized from cabConfig (the same mapping the runtime adapter uses).
local function BuildCustomBarAuraProbe(cab)
    return {
        type = "spell",
        id = tonumber(cab.spellID),
        addedAs = (not IsSpellCustomBarConfig(cab)) and "aura" or nil,
        auraTracking = true,
        auraSpellID = cab.auraSpellID,
        auraUnit = cab.auraUnit,
    }
end

-- Whether this bar renders aura stack text, mirroring the runtime style
-- adapter's rule (ResourceBarAuraHost BuildStyleAdapter) including the
-- legacy compat leg: stacks-mode aura bars with no explicit showStackText
-- fall back to the old showText flag.
local function CustomBarShowsStackText(cab)
    local showStack = cab.showStackText
    if not IsSpellCustomBarConfig(cab) and showStack == nil then
        return cab.trackingMode ~= "active" and cab.showText == true
    end
    return showStack == true
end

local function GetCustomBarAuraUnit(cab)
    local resolved = CooldownCompanion:ResolveAuraSpellID(BuildCustomBarAuraProbe(cab))
    return ClassifyAuraSpellUnit(resolved) or cab.auraUnit or "player"
end

-- Store the derived unit whenever tracking config changes, so the runtime
-- fallback (uncached spells at login) starts from the right value.
local function SyncCustomBarDerivedAuraUnit(cab)
    local unit = ClassifyAuraSpellUnit(CooldownCompanion:ResolveAuraSpellID(BuildCustomBarAuraProbe(cab)))
    if unit then
        cab.auraUnit = unit
        cab.auraUnitExplicit = nil
    end
end

local function BuildCustomBarAuraTrackingSection(container, cab, infoButtons, sectionKey)
    local isSpellBar = IsSpellCustomBarConfig(cab)

    local _, collapsed = AddCustomBarSettingsHeading(container, "Aura Tracking", "aura", sectionKey, infoButtons, {
        "Blizzard tracks the aura and drives the bar; the addon never reads aura state in combat.",
        " ",
        "Buffs are tracked on you, and your own debuffs on your target. This is a Blizzard restriction. The tracked unit is set automatically.",
        " ",
        "With no auras listed, the bar tracks its own aura. Added aura IDs override that; spell bars always keep their own aura as a fallback.",
    })

    if collapsed then return end

    -- LEFT column: which aura is tracked, and on whom. RIGHT column: how the
    -- bar draws it. Both halves are gated on the toggle at the head of the
    -- left one, so the right side is empty until tracking is on.
    local auraLeft, auraRight = BeginRowGrid(container)

    if isSpellBar then
        AddCheckboxRow(auraLeft, {
            label = "Track an Aura",
            value = cab.auraTracking == true,
            onChange = function(value)
                cab.auraTracking = value and true or nil
                if value then
                    SyncCustomBarDerivedAuraUnit(cab)
                end
                RefreshCustomBarAuraConfig()
            end,
        })
        if cab.auraTracking ~= true then
            return
        end
    end

    -- Derived unit line (read-only by design; the "?" heading explains why).
    local unit = GetCustomBarAuraUnit(cab)
    AddLabelRow(auraLeft, {
        label = "Tracked on",
        indent = isSpellBar,
        controlText = unit == "target" and "Target" or "You",
    })

    for _, spellID in ipairs(GetAuraCandidateList(cab)) do
        AddAuraCandidateRow(auraLeft, spellID, function(removedID)
            if RemoveAuraCandidate(cab, removedID, SyncCustomBarDerivedAuraUnit) then
                RefreshCustomBarAuraConfig()
            end
        end, { row = true })
    end

    AddEditBoxRow(auraLeft, {
        label = "Add aura by name or ID",
        indent = true,
        value = "",
        onEnterPressed = function(text, widget)
            if TryAddAuraCandidate(cab, text, GetCustomBarAuraUnit(cab), SyncCustomBarDerivedAuraUnit) then
                widget:SetText("")
                RefreshCustomBarAuraConfig()
            end
        end,
    })

    -- Bar fill mode: duration drain or stack count. Max stacks is automatic
    -- (game data); the status line shows what resolved.
    local mode = cab.trackingMode
    if mode ~= "active" and mode ~= "stacks" then
        mode = isSpellBar and "active" or "stacks"
    end
    local stacksRow = AddCheckboxRow(auraRight, {
        label = "Bar Shows Stacks",
        value = mode == "stacks",
        onChange = function(value)
            cab.trackingMode = value and "stacks" or "active"
            RefreshCustomBarAuraConfig()
        end,
    })
    -- Anchor args are a placeholder - AnchorRowBadge re-points the button onto
    -- the end of the row's label.
    AnchorRowBadge(stacksRow, CreateInfoButton(stacksRow.frame, stacksRow.frame, "LEFT", "LEFT", 0, 0, {
        "Bar Shows Stacks",
        {"The bar fills by stack count instead of draining with time. Blizzard drives the fill, and the maximum comes from the game's spell data.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Stack Style picks the look. Segmented shows one bordered piece per stack; Continuous is one plain bar that fills as stacks build. Segment Gap picks from preset widths. Smoothing follows the Resource Bars settings.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"If the aura doesn't stack, the bar keeps the normal duration fill.", 1, 1, 1, true},
    }, infoButtons))

    if mode == "stacks" then
        -- Constrained, matching every runtime resolve since the review
        -- alignment (2026-08-15): one max across config, bind, and policy.
        local maxStacks = CooldownCompanion:GetAuraStackBarMax(BuildCustomBarAuraProbe(cab), true)
        if maxStacks then
            AddDropdownRow(auraRight, {
                label = "Stack Style",
                indent = true,
                list = { segmented = "Segmented", continuous = "Continuous" },
                order = { "segmented", "continuous" },
                value = cab.displayMode == "continuous" and "continuous" or "segmented",
                onChange = function(value)
                    cab.displayMode = value
                    RefreshCustomBarAuraConfig()
                end,
            })

            -- Widget block bars only (pure aura bars): a preset picking
            -- which gap-variant atlas set the bind uses. Spell bars with
            -- stacks paint their dividers from the Resource Bars segment
            -- gap instead.
            if not isSpellBar and cab.displayMode ~= "continuous"
                and maxStacks <= ST.STACK_SEGMENT_ATLAS_MAX then
                ST._AddStackBlockGapRow(auraRight, cab, {
                    maxStacks = maxStacks,
                    commit = function()
                        CooldownCompanion:ApplyResourceBars()
                        RefreshLayoutOrderPreview()
                    end,
                })
            end
        end

        -- What the game resolved (or that combat is hiding it), reported as a
        -- child of the toggle it explains. The shared helper owns the shape.
        AddAuraStackMaxStatusLabel(auraRight, maxStacks, { row = true })
    end

    -- Stack text threshold colors, the same rows the panel entry section
    -- shows (SectionBuilders.lua): count text recolors at a chosen stack
    -- count and again at max. Outside the Bar Shows Stacks gate because
    -- the count text runs on duration bars too, but gated on the stack
    -- text actually showing (owner ruling 2026-08-16: settings for a
    -- hidden text hide with it). The keys live in cab.auraBar under the
    -- panel names, which is what lets the runtime adapter and the engine
    -- policy read them unchanged. Resolved with constrained fallbacks,
    -- the one max every custom-bar surface shares since the review
    -- alignment.
    if CustomBarShowsStackText(cab) then
        ST._BuildStackThresholdColorRows(auraRight, cab,
            CooldownCompanion:GetAuraStackBarMax(BuildCustomBarAuraProbe(cab), true), {
                infoButtons = infoButtons,
                refresh = RefreshCustomBarAuraConfig,
                commit = function()
                    CooldownCompanion:ApplyResourceBars()
                    RefreshLayoutOrderPreview()
                end,
                previewRefresh = RefreshLayoutOrderPreviewForDrag,
            })
    end

    -- The marker row hides with the duration text it rides (owner ruling
    -- 2026-08-16); the stored keys are untouched, so re-enabling the text
    -- brings the row back as it was. The fill recolor below stays
    -- unconditional — it colors the bar, not the text.
    if cab.showDurationText == true then
        -- Pandemic marker per-entry switch. The auto default follows the
        -- tracked unit (on for target debuffs, off for player buffs); only
        -- an explicit override is stored.
        local pandemicDefault = unit == "target"
        local pandemicValue = cab.pandemicMarker
        if pandemicValue == nil then pandemicValue = pandemicDefault end
        local pandemicRow = AddCheckboxRow(auraRight, {
            label = "Pandemic Marker",
            value = pandemicValue == true,
            onChange = function(value)
                if value == pandemicDefault then
                    cab.pandemicMarker = nil
                else
                    cab.pandemicMarker = value and true or false
                end
                -- Turning it off drops the command-center control, so disarm
                -- its preview here or the stand-in strands with no toggle
                -- left to stop it (the Show Pandemic Color twin below clears
                -- its own the same way). Asked through the shared gate the
                -- control is offered on.
                -- The gate is style-only now, so the cab's own keys go through
                -- the same translation the bind-time style adapter applies.
                if not CooldownCompanion:IsCustomBarPandemicMarkerPreviewWanted(cab) then
                    CooldownCompanion:SetCustomAuraBarMarkerPreview(cab, false)
                end
                RefreshCustomBarAuraConfig()
            end,
        })
        -- The marker's look had no control on this surface at all: the style
        -- adapter has always read these four keys off the entry, but nothing
        -- ever wrote them, so every custom aura bar drew a hardcoded orange
        -- "!!". Only the three styling rows are added here — the on/off above
        -- IS this entry's switch, and the panels' three-state marker mode has
        -- no meaning on a surface where the bar is the entry.
        local function BuildCustomBarPandemicMarkerAdvanced(panel)
            AddPandemicMarkerControls(panel, cab, function()
                CooldownCompanion:ApplyResourceBars()
            end, function()
                if CS.RefreshAdvancedSettingsPanel then
                    CS.RefreshAdvancedSettingsPanel()
                end
            end, { childrenOnly = true })
        end
        AddAdvancedToggle(pandemicRow, "rbCabPandemicMarker_" .. tostring(sectionKey), infoButtons,
            pandemicValue == true, {
                title = "Pandemic Marker Advanced",
                build = BuildCustomBarPandemicMarkerAdvanced,
            })
        AnchorRowBadge(pandemicRow, CreateInfoButton(pandemicRow.frame, pandemicRow.frame, "LEFT", "LEFT", 0, 0, {
            "Pandemic Marker",
            {"Marks the duration text for the last 30% of the aura, where recasting adds to the remaining time instead of wasting it.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"On by default for debuffs on your target.", 1, 1, 1, true},
        }, infoButtons))
    end

    -- Pandemic fill recolor (PTR 8 Phase 2). Fresh entry keys: the retired
    -- showPandemicGlow/barPandemicColor names are wiped on every import and
    -- must never be written again.
    local effectRow = AddCheckboxRow(auraRight, {
        label = "Show Pandemic Color",
        value = cab.pandemicEffect == true,
        onChange = function(value)
            cab.pandemicEffect = value and true or nil
            -- Disabling drops the command-center control, so disarm its
            -- preview here or it strands active with no toggle left and
            -- silently resumes on re-check (the panel twins clear theirs
            -- the same way when rebuilt disabled).
            if not value then
                CooldownCompanion:SetCustomAuraBarPandemicPreview(cab, false)
            end
            RefreshCustomBarAuraConfig()
        end,
    })
    AnchorRowBadge(effectRow, CreateInfoButton(effectRow.frame, effectRow.frame, "LEFT", "LEFT", 0, 0, {
        "Pandemic Color",
        {"The bar fill wears this color instead of the aura color while the tracked aura is in its refresh window, where recasting adds bonus time.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Auras that gain no time when refreshed never show it.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"A bar showing stacks keeps its stack look.", 1, 1, 1, true},
    }, infoButtons))
    if cab.pandemicEffect == true then
        -- No alpha: the pandemic color REPLACES the aura fill color (owner
        -- ruling), so the live clone renders it opaque.
        --
        -- "Fill Color", not "Pandemic Color": the marker gear a few rows up
        -- opens its own "Marker Color", and the two drive different visuals.
        AddColorRow(auraRight, {
            label = "Fill Color",
            indent = true,
            tbl = cab,
            key = "pandemicColor",
            default = {1, 0.5, 0, 1},
            hasAlpha = false,
            onConfirm = function()
                CooldownCompanion:ApplyResourceBars()
                RefreshLayoutOrderPreview()
            end,
            onChange = RefreshLayoutOrderPreviewForDrag,
            deferCommit = true,
        })
    end

    local shellRow = AddCheckboxRow(auraRight, {
        label = "Show Only While Aura Active",
        value = cab.hideWhenInactive == true,
        onChange = function(value)
            cab.hideWhenInactive = value or nil
            -- Toggling moves an aura bar between the fixed stack and the
            -- collapsing block, so the stack's extent changes: this needs
            -- the same commit as a layout drop, not just a config refresh.
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RepositionCastBar()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    local shellInfo = {
        "Show Only While Aura Active",
        {"The bar shows only while the aura is running.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
    }
    -- Only aura entries join the collapsing aura block
    -- (RB.IsAuraBlockEntry); a spell bar keeps its slot either way.
    if isSpellBar then
        shellInfo[#shellInfo + 1] = {"Its slot in the bar stack stays reserved.", 1, 1, 1, true}
    else
        shellInfo[#shellInfo + 1] = {"It leaves the stack while hidden. It returns at the far end of its side, in order with the other bars that do the same.", 1, 1, 1, true}
        shellInfo[#shellInfo + 1] = {" ", 1, 1, 1, true}
        shellInfo[#shellInfo + 1] = {"Your auras and the target's collapse in separate groups.", 1, 1, 1, true}
        shellInfo[#shellInfo + 1] = {" ", 1, 1, 1, true}
        shellInfo[#shellInfo + 1] = {"A group whose bars are all hidden still holds one bar gap of space. The game hides aura activity from addons, so that space cannot close.", 1, 1, 1, true}
        shellInfo[#shellInfo + 1] = {" ", 1, 1, 1, true}
        shellInfo[#shellInfo + 1] = {"Splitting your auras and the target's onto different sides avoids the extra gap.", 1, 1, 1, true}
    end
    AnchorRowBadge(shellRow, CreateInfoButton(shellRow.frame, shellRow.frame, "LEFT", "LEFT", 0, 0, shellInfo, infoButtons))
end

local function BuildCustomBarWorkspaceAddBox(container)
    if BuildResourceBarConflictGate(container, "Custom Bars", false) then
        return
    end

    local settings = CooldownCompanion:GetResourceBarSettings()
    if not (settings and settings.enabled) then
        return
    end

    local customBarsSpecID = ST._RBP.GetCurrentConfigSpecID()
    local customBars = RB.GetAllCustomBars and RB.GetAllCustomBars(settings) or CooldownCompanion:GetSpecCustomAuraBars()
    ST._PruneConfigCustomBarSelection(function(customBarId)
        return FindCustomBarIndexById(customBars, customBarId) ~= nil
    end)
    local addBox = AceGUI:Create("EditBox")
    if addBox.editbox.Instructions then addBox.editbox.Instructions:Hide() end
    addBox:SetLabel("")
    addBox:SetFullWidth(true)
    addBox:DisableButton(true)
    local updatePlaceholder = ConfigureCustomBarAddInstructions(addBox, "Add spell by name or ID")

    local function GetCustomBarEntryTypeForAutocomplete(entry)
        if type(entry) ~= "table" then
            return "spell"
        end
        if entry.forceAura == true or entry.isPassive == true then
            return "aura"
        end
        if entry.forceAura == false then
            return "spell"
        end
        if IsPassiveOrProc and entry.id and IsPassiveOrProc(entry.id) then
            return "aura"
        end
        return "spell"
    end

    local function StripExplicitCustomBarEntryTypeSuffix(text)
        local cleaned = text and text:gsub("^%s+", ""):gsub("%s+$", ""):lower() or ""
        if cleaned:match("%s%((buff)%)$") or cleaned:match("%s%((aura)%)$") then
            return (text or ""):gsub("%s+%([Bb][Uu][Ff][Ff]%)%s*$", ""):gsub("%s+%([Aa][Uu][Rr][Aa]%)%s*$", ""), "aura"
        end
        if cleaned:match("%s%((cooldown)%)$") then
            return (text or ""):gsub("%s+%([Cc][Oo][Oo][Ll][Dd][Oo][Ww][Nn]%)%s*$", ""), "spell"
        end
        return text, nil
    end

    local function GetCustomBarEntryTypeForSpellID(spellId, explicitType)
        if explicitType then
            return explicitType
        end
        if not spellId or not C_Spell.GetSpellInfo(spellId) then
            return "aura"
        end
        local sawAuraEntry = false
        local sawSpellEntry = false
        local cache = ST._RBP.BuildAuraBarAutocompleteCache and ST._RBP.BuildAuraBarAutocompleteCache() or nil
        for _, entry in ipairs(cache or {}) do
            if entry.id == spellId then
                if GetCustomBarEntryTypeForAutocomplete(entry) == "aura" then
                    sawAuraEntry = true
                else
                    sawSpellEntry = true
                end
            end
        end
        if sawAuraEntry and not sawSpellEntry then
            return "aura"
        elseif sawSpellEntry and not sawAuraEntry then
            return "spell"
        end
        if IsPassiveOrProc and IsPassiveOrProc(spellId) then
            return "aura"
        end
        return "spell"
    end

    local function AddCustomBarFromSpell(spellId, labelOverride, entryType)
        if not spellId then return false end
        local entry
        if entryType == "aura" then
            -- Aura-driven Custom Bar (the aura pass): duration bar by
            -- default; stacks are the "Bar Shows Stacks" opt-in. The unit
            -- seed derives from spell polarity (never user-set).
            -- hideWhenInactive defaults on: a new aura bar joins the
            -- collapsing aura block rather than parking an empty slot in
            -- the stack. Existing bars keep whatever they were saved with.
            entry = {
                entryType = "aura",
                enabled = true,
                spellID = spellId,
                trackingMode = "active",
                showDurationText = true,
                hideWhenInactive = true,
                auraUnit = ClassifyAuraSpellUnit(spellId) or "player",
                label = labelOverride or GetAuraBarAutocompleteDisplayName(spellId) or C_Spell.GetSpellName(spellId) or "",
            }
        else
            entry = {
                entryType = "spell",
                enabled = true,
                spellID = spellId,
                label = labelOverride or GetAuraBarAutocompleteDisplayName(spellId) or C_Spell.GetSpellName(spellId) or "",
            }
            local charges = C_Spell.GetSpellCharges(spellId)
            local maxCharges = charges and tonumber(charges.maxCharges)
            if maxCharges and maxCharges > 1 then
                entry.hasCharges = true
                entry.maxCharges = maxCharges
            end
        end
        local id = RB.AddCustomBar
            and RB.AddCustomBar(settings, entry, customBarsSpecID, 1000 + #CooldownCompanion:GetSpecCustomAuraBars() + 1)
            or EnsureCustomBarId(settings, entry)
        if not RB.AddCustomBar then
            customBars[#customBars + 1] = entry
            EnsureCustomBarLayout(settings, nil, id, 1000 + #customBars)
        end
        ST._SelectConfigCustomBar(id)
        ApplyCustomAuraBarPanelChanges({
            updateAnchors = true,
            refreshConfig = true,
        })
        return true
    end

    local function CommitCustomBarText(widget, text)
        local lookupText, explicitType = StripExplicitCustomBarEntryTypeSuffix(text)
        local autocompleteEntry = ResolveAuraBarAutocompleteEntry and (
            ResolveAuraBarAutocompleteEntry(text)
            or (lookupText ~= text and ResolveAuraBarAutocompleteEntry(lookupText))
        )
        if autocompleteEntry and AddCustomBarFromSpell(
            autocompleteEntry.id,
            GetAuraBarAutocompleteEntryName(autocompleteEntry),
            explicitType or GetCustomBarEntryTypeForAutocomplete(autocompleteEntry)
        ) then
            widget:SetText("")
            return true
        end

        local id, explicitClear = ResolveAuraColorSpellIDFromText(lookupText)
        if explicitClear then
            widget:SetText("")
            return true
        end
        if AddCustomBarFromSpell(id, nil, GetCustomBarEntryTypeForSpellID(id, explicitType)) then
            widget:SetText("")
            return true
        end

        local cleaned = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
        if cleaned ~= "" then
            CooldownCompanion:Print("Custom Bar spell not found: " .. cleaned)
        end
        return false
    end

    local function onAuraBarSelect(entry)
        CS.HideAutocomplete()
        if entry and AddCustomBarFromSpell(
            entry.id,
            GetAuraBarAutocompleteEntryName(entry),
            GetCustomBarEntryTypeForAutocomplete(entry)
        ) then
            addBox._cdcCustomBarAutocompleteCommitted = true
            addBox:SetText("")
        end
    end

    addBox:SetCallback("OnTextChanged", function(widget, event, text)
        updatePlaceholder(text)
        ShowAuraBarAutocompleteResults(text, widget, onAuraBarSelect)
    end)
    addBox:SetCallback("OnEnterPressed", function(widget, event, text)
        if CS.ConsumeAutocompleteEnter then
            CS.ConsumeAutocompleteEnter()
        end
        if widget._cdcCustomBarAutocompleteCommitted then
            widget._cdcCustomBarAutocompleteCommitted = nil
            return
        end
        CS.HideAutocomplete()
        CommitCustomBarText(widget, text)
    end)
    CS.SetupAutocompleteKeyHandler(addBox)
    addBox.editbox:SetPoint("BOTTOMRIGHT", 1, 0)

    local actionControls = AceGUI:Create("SimpleGroup")
    actionControls:SetFullWidth(true)
    actionControls.noAutoHeight = true
    actionControls:SetHeight(28)
    actionControls:SetLayout("Fill")
    actionControls:AddChild(addBox)
    container:AddChild(actionControls)
    return actionControls, addBox
end

-- Helpers.lua loads before this file, so the shared builder is importable
-- directly.
local BuildEntryIdentityHeading = ST._BuildEntryIdentityHeading

-- The identity heading at the top of the Settings pane, panel-entry parity:
-- the shared builder reads a buttonData-shaped table, so the cab is adapted
-- into one. customName pins the title to the custom-bar naming rule -
-- label > spell name > "Custom Bar" (GetCustomBarDisplayName) - so the
-- entry namer never rederives it; spellID feeds the icon and the
-- (Spell)/(Aura) kind suffix, and bars without one take the plain-name
-- path and the stock icon.
local function BuildCustomBarIdentityHeading(container, cab)
    if type(cab) ~= "table" then return end
    local spellID = tonumber(cab.spellID)
    BuildEntryIdentityHeading(container, {
        type = spellID and "spell" or nil,
        id = spellID,
        addedAs = IsSpellCustomBarConfig(cab) and "spell" or "aura",
        customName = GetCustomBarDisplayName(cab),
    })
end

-- The whole Custom Bar entry surface as ONE Settings pane (panel-entry
-- parity): identity heading, then every former tab as collapsible sections,
-- Talent Conditions last. Collapse keys are unchanged from the tab era, so
-- expand state and the command-center deep links survived the merge.
local function BuildCustomAuraBarPanel(container, customBarId)
    if BuildResourceBarConflictGate(container, "Custom Bars", false) then
        return
    end

    local settings = CooldownCompanion:GetResourceBarSettings()
    if not (settings and settings.enabled) then
        AddResourceBarsDisabledLabel(container, "Enable Resource Bars to configure Custom Bar settings.")
        return
    end

    local customBars = RB.GetAllCustomBars and RB.GetAllCustomBars(settings) or CooldownCompanion:GetSpecCustomAuraBars()
    local rbCabTextAdvBtns = {}
    local selectedIndex = FindCustomBarIndexById(customBars, customBarId)
    local infoButtons = CS.customBarInfoButtons
    if not infoButtons then
        infoButtons = {}
        CS.customBarInfoButtons = infoButtons
    end

    if not selectedIndex then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Select a Custom Bar to configure it.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end
    local cab = customBars[selectedIndex]
    local capturedIdx = selectedIndex
    local capturedId = EnsureCustomBarId(settings, cab)
    local capturedKey = capturedId or tostring(capturedIdx)
    local currentConfigSpecID = GetCurrentConfigSpecID()
    local function resolveLayoutSpecID(entry, fallbackSpecID)
        fallbackSpecID = tonumber(fallbackSpecID) or fallbackSpecID
        if RB.CustomBarHasSpec and fallbackSpecID and RB.CustomBarHasSpec(entry, fallbackSpecID) then
            return fallbackSpecID
        end
        if RB.CustomBarHasExplicitSpec then
            for _, spec in ipairs(GetCustomBarSpecOptions()) do
                if RB.CustomBarHasExplicitSpec(entry, spec.id) then
                    return spec.id
                end
            end
        end

        local entryCustomBarId = type(entry) == "table" and entry.customBarId or nil
        local layoutOrder = type(settings) == "table" and settings.layoutOrder or nil
        if type(entryCustomBarId) == "string" and type(layoutOrder) == "table" then
            local layoutSpecIDs = {}
            for specID, specLayout in pairs(layoutOrder) do
                if type(specLayout) == "table"
                    and type(specLayout.customBars) == "table"
                    and type(specLayout.customBars[entryCustomBarId]) == "table" then
                    layoutSpecIDs[#layoutSpecIDs + 1] = tonumber(specID) or specID
                end
            end
            table.sort(layoutSpecIDs, function(a, b) return tostring(a) < tostring(b) end)
            if layoutSpecIDs[1] then
                return layoutSpecIDs[1]
            end
        end

        return fallbackSpecID
    end

    local layoutSpecID = resolveLayoutSpecID(cab, currentConfigSpecID)
    local layout = RB.GetSpecLayoutOrder and RB.GetSpecLayoutOrder(settings, layoutSpecID) or CooldownCompanion:GetSpecLayoutOrder()
    local thicknessField, thicknessLabel = GetResourceThicknessFieldConfig(settings, layout)
    local isSpellCustomBar = IsSpellCustomBarConfig(cab)

    BuildCustomBarIdentityHeading(container, cab)

            -- Per-slot bar thickness override
            if layout and layout.customBarHeights then
                local _, sizeCollapsed = AddCustomBarSettingsHeading(container, "Size", "size", capturedKey)

                if not sizeCollapsed then
                    -- One setting with nothing to pair it against, so the left
                    -- column carries it alone.
                    local sizeLeft = BeginRowGrid(container)

                    local slotLayout = EnsureCustomBarLayout(settings, layoutSpecID, capturedId, 1000 + capturedIdx) or {}
                    local thicknessValue
                    if thicknessField == "barWidth" then
                        thicknessValue = slotLayout.barWidth or slotLayout.barHeight or layout.barWidth or layout.barHeight or settings.barWidth or settings.barHeight or 12
                    else
                        thicknessValue = slotLayout.barHeight or slotLayout.barWidth or layout.barHeight or layout.barWidth or settings.barHeight or settings.barWidth or 12
                    end
                    local cabIdx = capturedIdx
                    -- This bar's slot on the canvas is drawn at this thickness,
                    -- so the stack reflows under the drag and the live bars
                    -- resize once, on release.
                    AddMirrorFirstSliderRow(sizeLeft, {
                        label = thicknessLabel,
                        min = 4, max = 40, step = 0.1,
                        value = thicknessValue,
                        set = function(val)
                            local customBar = customBars[cabIdx]
                            local customLayout = EnsureCustomBarLayout(settings, layoutSpecID, customBar and customBar.customBarId, 1000 + cabIdx)
                            if customLayout then
                                customLayout[thicknessField] = val
                            end
                        end,
                        apply = function()
                            CooldownCompanion:ApplyResourceBars()
                            CooldownCompanion:RepositionCastBar()
                            CooldownCompanion:UpdateAnchorStacking()
                        end,
                        stateOwner = slotLayout,
                        stateKeys = thicknessField,
                    })
                end
            end

            -- ---- Colors / Texts sections ----
            if cab.spellID then
                local cabIdx = capturedIdx
                -- Commit path: apply to the live bars AND repaint the config
                -- canvas, so a confirmed color shows on both surfaces at once.
                local cabApplyBars = function()
                    CooldownCompanion:ApplyResourceBars()
                    RefreshLayoutOrderPreview()
                end
                -- Drag path: uncommitted edits belong to the config canvas
                -- only — the live display keeps its committed style until the
                -- picker closes. The drag-flavoured repaint reuses the built
                -- panel mirror: nothing a bar colour or font can change
                -- reaches the icon panel the lanes wrap.
                local cabPreviewOnly = RefreshLayoutOrderPreviewForDrag
                local isAuraTracked = (not isSpellCustomBar) or cab.auraTracking == true

                local _, colorsCollapsed = AddCustomBarSettingsHeading(container, "Colors", "colors", capturedKey)

                if not colorsCollapsed then
                -- LEFT column: the two base fills - what the bar shows when it
                -- is ready, and what it shows while the cooldown runs. RIGHT
                -- column: the conditional fills layered over those. Aura bars
                -- have only the first, so the right side is empty for them.
                local colorsLeft, colorsRight = BeginRowGrid(container)

                -- deferCommit is true on every picker here: the Layout & Order
                -- canvas re-reads these tables on every repaint, so a drag
                -- value may only exist in them while that repaint runs.
                --
                -- Standalone aura bars: the fill IS the aura, so the label
                -- says so — "Bar Color" stays the spell-cooldown verbiage.
                -- Same barColor key either way; label only.
                AddColorRow(colorsLeft, {
                    label = isSpellCustomBar and "Bar Color" or "Aura Bar Color",
                    tbl = customBars[cabIdx],
                    key = "barColor",
                    default = {0.5, 0.5, 1},
                    onConfirm = cabApplyBars,
                    onChange = cabPreviewOnly,
                    deferCommit = true,
                })

                if isSpellCustomBar then
                    AddColorRow(colorsLeft, {
                        label = "Bar Cooldown Color",
                        tbl = customBars[cabIdx],
                        key = "barCooldownColor",
                        default = {0.6, 0.13, 0.18, 1},
                        hasAlpha = true,
                        onConfirm = cabApplyBars,
                        onChange = cabPreviewOnly,
                        deferCommit = true,
                    })

                    AddColorRow(colorsRight, {
                        label = "Bar Recharging Color",
                        tbl = customBars[cabIdx],
                        key = "barChargeColor",
                        default = {1.0, 0.82, 0.0, 1},
                        hasAlpha = true,
                        onConfirm = cabApplyBars,
                        onChange = cabPreviewOnly,
                        deferCommit = true,
                    })

                    if isAuraTracked then
                        -- The kit's aura-drain fill while the tracked aura
                        -- runs (pure aura bars use Bar Color — the fill IS
                        -- the bar there).
                        AddColorRow(colorsRight, {
                            label = "Aura Bar Color",
                            tbl = customBars[cabIdx],
                            key = "barAuraColor",
                            default = {0.2, 1.0, 0.2, 1},
                            hasAlpha = true,
                            onConfirm = cabApplyBars,
                            onChange = cabPreviewOnly,
                            deferCommit = true,
                        })
                    end
                end
                end -- not colorsCollapsed

                -- ---- Text / Duration controls ----
                local _, textsCollapsed = AddCustomBarSettingsHeading(container, "Texts", "texts", capturedKey)

                if not textsCollapsed then
                    -- One text per column: each carries its own gear, and the
                    -- two are independent, so neither has to stay adjacent to
                    -- anything.
                    local textsLeft, textsRight = BeginRowGrid(container)

                    local showDurationControls = true
                    local durationTextRow
                    if showDurationControls then
                        durationTextRow = AddCheckboxRow(textsLeft, {
                            label = "Show Duration Text",
                            value = cab.showDurationText == true,
                            onChange = function(val)
                                customBars[cabIdx].showDurationText = val or nil
                                -- Turning the text off hides the Pandemic
                                -- Marker row and its command-center control
                                -- (the marker rides this text), so disarm an
                                -- active marker preview or it strands with no
                                -- toggle left and silently resumes when the
                                -- text returns. The marker settings themselves
                                -- stay stored.
                                if not val then
                                    CooldownCompanion:SetCustomAuraBarMarkerPreview(customBars[cabIdx], false)
                                end
                                CooldownCompanion:ApplyResourceBars()
                                CooldownCompanion:RefreshConfigPanel()
                            end,
                        })
                    end

                    -- Show Stack Text
                    local stackVal = cab.showStackText

                    local stackTextLabel = isSpellCustomBar
                        and "Show Count Text (Charges/Uses)"
                        or "Show Stack Text"
                    local stackTextRow = AddCheckboxRow(textsRight, {
                        label = stackTextLabel,
                        value = stackVal == true,
                        onChange = function(val)
                            customBars[cabIdx].showStackText = val or nil
                            CooldownCompanion:ApplyResourceBars()
                            CooldownCompanion:RefreshConfigPanel()
                        end,
                    })

                    local showDuration = showDurationControls and cab.showDurationText == true
                    local showStack = (stackVal == true)
                    -- The font trio's store keys are exactly durationTextFont /
                    -- durationTextFontSize / durationTextFontOutline, so the
                    -- shared helper owns it; it writes the same table `cab`
                    -- aliases and applies the bars, which is what the three
                    -- hand-written callbacks did. The canvas draws these texts,
                    -- so the commit path is cabApplyBars (apply + repaint) and
                    -- previewRefresh keeps the size slider's drag on the canvas.

                    -- Single rail (AdvancedSettingsPanel.lua): a panel is one
                    -- narrow column, so every row goes straight onto the panel
                    -- scroll.
                    local function BuildDurationTextAdvanced(panel)
                        AddFontControls(panel, customBars[cabIdx], "durationText", {
                            size = DEFAULT_RESOURCE_TEXT_SIZE, sizeMin = 6, sizeMax = 24, sizeStep = 1,
                            font = DEFAULT_RESOURCE_TEXT_FONT, outline = DEFAULT_RESOURCE_TEXT_OUTLINE,
                        }, cabApplyBars, { row = true, previewRefresh = cabPreviewOnly })

                        -- deferCommit stays true: the Layout & Order canvas
                        -- re-reads this table on every repaint, so a drag value
                        -- may only exist in it while that repaint runs.
                        AddColorRow(panel, {
                            label = "Duration Text Color",
                            tbl = customBars[cabIdx],
                            key = "durationTextFontColor",
                            default = DEFAULT_RESOURCE_TEXT_COLOR,
                            hasAlpha = true,
                            onConfirm = cabApplyBars,
                            onChange = cabPreviewOnly,
                            deferCommit = true,
                        })

                        AddDurationFormatDropdown(panel, customBars[cabIdx], cabApplyBars, { row = true })
                        -- Low Time Threshold: custom-bar COOLDOWN lane text
                        -- only. Standalone aura bars render through the aura
                        -- host, which never consumes these keys (review
                        -- 2026-08-16: no dead controls on aura bars).
                        if ST._AddDurationLowTimeRows and isSpellCustomBar then
                            ST._AddDurationLowTimeRows(panel, customBars[cabIdx], cabApplyBars, {
                                indent = true,
                                rebuild = RefreshCustomBarAuraConfig,
                            })
                        end
                    end

                    if showDurationControls then
                        AddAdvancedToggle(durationTextRow, "rbCabDurationText_" .. capturedKey, rbCabTextAdvBtns, showDuration, {
                            title = "Duration Text Advanced",
                            build = BuildDurationTextAdvanced,
                        })
                    end

                    local function BuildStackTextAdvanced(panel)
                        AddFontControls(panel, customBars[cabIdx], "stackText", {
                            size = DEFAULT_RESOURCE_TEXT_SIZE, sizeMin = 6, sizeMax = 24, sizeStep = 1,
                            font = DEFAULT_RESOURCE_TEXT_FONT, outline = DEFAULT_RESOURCE_TEXT_OUTLINE,
                        }, cabApplyBars, { row = true, previewRefresh = cabPreviewOnly })

                        -- deferCommit stays true, for the same reason as the
                        -- duration text color above.
                        AddColorRow(panel, {
                            label = "Stack Text Color",
                            tbl = customBars[cabIdx],
                            key = "stackTextFontColor",
                            default = DEFAULT_RESOURCE_TEXT_COLOR,
                            hasAlpha = true,
                            onConfirm = cabApplyBars,
                            onChange = cabPreviewOnly,
                            deferCommit = true,
                        })
                    end

                    AddAdvancedToggle(stackTextRow, "rbCabStackText_" .. capturedKey, rbCabTextAdvBtns, showStack, {
                        title = stackTextLabel .. " Advanced",
                        build = BuildStackTextAdvanced,
                    })
                end -- not textsCollapsed
            end -- cab.spellID (Colors/Texts)

            -- ---- Aura Tracking + Effects ----
            -- The former Aura tab body (the aura pass): the tracking section
            -- plus the active-aura effects, the same shape as the panel
            -- entry's Aura Tracking section. Aura-look colors and texts stay
            -- above with the rest of the bar style. Panel-entry order (owner
            -- ruling): aura near the top, visibility toward the bottom.
            if cab.spellID then
                BuildCustomBarAuraTrackingSection(container, cab, infoButtons, capturedKey)

                -- Shared builder (SectionBuilders): the cabConfig speaks the
                -- same barAura* key family as the panel bar style tables. The
                -- builder is row-only now and opens its own grid on this
                -- container - LEFT the border effect, RIGHT the two fill effects -
                -- so this section reads like every other one on the pane. Only a
                -- caller passing opts.singleRail suppresses that grid: the
                -- bar-mode advanced panel, whose popout is too narrow for two
                -- columns.
                local isAuraTracked = (not isSpellCustomBar) or cab.auraTracking == true
                if isAuraTracked and ST._BuildBarActiveAuraControls then
                    local _, effectsCollapsed = AddCustomBarSettingsHeading(container, "Effects",
                        "aura_effects", capturedKey, infoButtons, {
                            "Effects the bar plays while the tracked aura is active: a border effect, a fill pulse, and a fill color shift.",
                            "Use the preview in the command center below the bar list to see them without a live aura.",
                        })
                    if not effectsCollapsed then
                        -- These effects render on the canvas too (its Active Aura
                        -- stand-in draws them), and nothing here rebuilds the
                        -- settings column - so the commit path repaints it and
                        -- previewRefresh keeps drags and open pickers on it alone.
                        ST._BuildBarActiveAuraControls(container, cab, function()
                            CooldownCompanion:ApplyResourceBars()
                            RefreshLayoutOrderPreview()
                        end, {
                            row = true,
                            infoButtons = infoButtons,
                            previewRefresh = RefreshLayoutOrderPreviewForDrag,
                        })
                    end
                end
            end

            -- ---- Sound Alerts ----
            BuildCustomBarSoundAlertsTab(container, cab, infoButtons)

            -- ---- Visibility ----
            -- The former Visibility tab body: the Specializations and
            -- Where To Hide It sections, each its own collapsible.
            BuildCustomBarLoadConditionsTab(container, cab, infoButtons)

            -- ---- Talent Conditions (LAST, panel-entry parity) ----
            if cab.spellID then
                local cabIdx = capturedIdx
                -- Key unchanged from the pre-row tab, so a bar's collapse
                -- state survives this conversion.
                local talentHeading, talentCollapsed =
                    AddCustomBarSection(container, "Talent Conditions", "talent", capturedKey)

                local talentInfoBtn = CreateInfoButton(talentHeading.frame, talentHeading.label, "LEFT", "RIGHT", 4, 0, {
                    "Talent Conditions",
                    {"Show or hide this Custom Bar based on which talents you have selected. If you add multiple conditions, all of them must pass.", 1, 1, 1, true},
                }, infoButtons)
                AnchorLeftAlignedHeadingRule(talentHeading, talentInfoBtn)

                local conditions = cab.talentConditions
                local condCount = conditions and #conditions or 0

                if talentCollapsed then
                    local summaryLabel = AceGUI:Create("Label")
                    ST._ConfigureWrappedHelperLabel(summaryLabel)
                    if condCount > 0 then
                        local firstCond = conditions[1]
                        local displayIcon = not IsHeroSpecProxyCondition(firstCond)
                            and firstCond.spellID
                            and C_Spell.GetSpellTexture(firstCond.spellID)
                        if displayIcon then
                            summaryLabel:SetImage(displayIcon, 0.08, 0.92, 0.08, 0.92)
                            summaryLabel:SetImageSize(16, 16)
                        end
                        if condCount == 1 then
                            local showText = (firstCond.show == "not_taken") and " (not taken)" or " (taken)"
                            summaryLabel:SetText(ST._GetConditionDisplayName(firstCond) .. showText)
                        else
                            summaryLabel:SetText(condCount .. " conditions" .. ST._GetConditionListContextSuffix(conditions))
                        end
                    else
                        summaryLabel:SetText("|cff888888None|r")
                    end
                    summaryLabel:SetFullWidth(true)
                    container:AddChild(summaryLabel)
                end

                if not talentCollapsed then

                -- One-column row grid, matching the entry Visibility tab's
                -- talent section: condition ITEM rows stacked in the left
                -- column, the actions on one closing grammar row whose
                -- control column owns the buttons.
                local talentLeft = BeginRowGrid(container)

                -- Condition list display. Each condition presents an ITEM, not
                -- a setting: a CDC-LabelRow with the talent icon inlined into
                -- the label text and the taken/not-taken state as the row's
                -- right-aligned status word.
                if condCount > 0 then
                    local cache = CooldownCompanion._talentNodeCache
                    local currentSpecID = layoutSpecID or CooldownCompanion._currentSpecId
                    local currentHeroSubTreeID = CooldownCompanion._currentHeroSpecId
                    for _, cond in ipairs(conditions) do
                        local displayIcon = not IsHeroSpecProxyCondition(cond)
                            and cond.spellID
                            and C_Spell.GetSpellTexture(cond.spellID)
                        local nameText = ST._GetConditionDisplayName(cond)
                        if displayIcon then
                            nameText = ("|T%s:16:16:0:0|t %s"):format(tostring(displayIcon), nameText)
                        end
                        AddLabelRow(talentLeft, {
                            label = "|cffFFFFFF" .. nameText .. "|r",
                            controlText = (cond.show == "not_taken")
                                and "|cffff4d4d(not taken)|r"
                                or "|cff33dd33(taken)|r",
                        })

                        -- Per-condition stale node warning. A wrapped sentence
                        -- rather than a setting, so it keeps its stock Label
                        -- shape and sits directly under the row it warns about.
                        local matchesCurrentScope = (not cond.specID or cond.specID == currentSpecID)
                            and (not cond.heroSubTreeID or cond.heroSubTreeID == currentHeroSubTreeID)
                        if matchesCurrentScope and cache and not cache[cond.nodeID] then
                            local warnLabel = AceGUI:Create("Label")
                            ST._ConfigureWrappedHelperLabel(warnLabel)
                            warnLabel:SetText("|cffff8800This talent is not in your current active tree, so it behaves as not taken right now.|r")
                            warnLabel:SetFullWidth(true)
                            talentLeft:AddChild(warnLabel)
                        end
                    end
                end

                -- The section's status prose and its actions share one
                -- closing grammar row, so the picker wears the same 140px
                -- right-aligned footprint as every control above it.
                local pickBtn = AceGUI:Create("Button")
                pickBtn:SetText(condCount > 0 and "Edit" or "Pick Talents")
                pickBtn:SetHeight(ACTION_STRIP_BUTTON_HEIGHT)
                pickBtn:SetCallback("OnClick", function()
                    local initialConditions = cab.talentConditions
                    local specID = layoutSpecID or CooldownCompanion._currentSpecId
                    local specHint = specID and { specs = { [specID] = true } } or nil
                    CooldownCompanion:OpenTalentPicker(function(results)
                        if results then
                            local normalized, changed = CooldownCompanion:NormalizeTalentConditions(results)
                            if changed then
                                results = normalized
                            end
                            customBars[cabIdx].talentConditions = results
                        else
                            customBars[cabIdx].talentConditions = nil
                        end
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:UpdateAnchorStacking()
                        CooldownCompanion:RefreshConfigPanel()
                    end, initialConditions, specHint)
                end)

                local talentActionControl
                if condCount > 0 then
                    -- Edit and Clear split the control column. Clear is
                    -- destructive, so it shares the row with the picker that
                    -- owns what it clears. Flow packs siblings at 0px, so the
                    -- gutter is a fixed-size spacer group.
                    local strip = AceGUI:Create("SimpleGroup")
                    strip:SetLayout("Flow")
                    strip:SetWidth(ROW_CONTROL_WIDTH)
                    strip:SetHeight(ACTION_STRIP_HEIGHT)
                    strip.noAutoHeight = true

                    pickBtn:SetWidth((ROW_CONTROL_WIDTH - ACTION_STRIP_GUTTER) / 2)
                    strip:AddChild(pickBtn)

                    local gutter = AceGUI:Create("SimpleGroup")
                    gutter:SetWidth(ACTION_STRIP_GUTTER)
                    gutter:SetHeight(ACTION_STRIP_BUTTON_HEIGHT)
                    gutter.noAutoHeight = true
                    strip:AddChild(gutter)

                    local clearBtn = AceGUI:Create("Button")
                    clearBtn:SetText("Clear")
                    clearBtn:SetHeight(ACTION_STRIP_BUTTON_HEIGHT)
                    clearBtn:SetWidth((ROW_CONTROL_WIDTH - ACTION_STRIP_GUTTER) / 2)
                    clearBtn:SetCallback("OnClick", function()
                        customBars[cabIdx].talentConditions = nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:UpdateAnchorStacking()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    strip:AddChild(clearBtn)

                    talentActionControl = strip
                else
                    pickBtn:SetWidth(ROW_CONTROL_WIDTH)
                    talentActionControl = pickBtn
                end

                AddLabelRow(talentLeft, {
                    label = (condCount > 0) and "" or "|cff888888No talent conditions set.|r",
                    controlWidget = talentActionControl,
                })

                end -- not talentCollapsed
            end

end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildCustomBarWorkspaceAddBox = BuildCustomBarWorkspaceAddBox
ST._OpenConfigCustomBarMenu = OpenConfigCustomBarMenu
ST._DeleteConfigCustomBar = DeleteConfigCustomBar
ST._BuildCustomAuraBarPanel = BuildCustomAuraBarPanel
