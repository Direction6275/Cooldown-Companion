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
local AddDurationTextVisibilityRows = ST._AddDurationTextVisibilityRows
local AddSettingsSubheading = ST._AddSettingsSubheading
local AddFamilyColumnCaptions = ST._AddFamilyColumnCaptions
local BeginFullWidthRowGroup = ST._BeginFullWidthRowGroup

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

-- The gear sites' "Turn On" enable specs, riding the LAZY unlock specs the
-- gears store in options.unlock (resolved only at panel-build time by
-- ST._ResolveAdvancedUnlock, Helpers.lua). File-local constant so a rebuild
-- allocates none of it; the stack text twin's label varies per bar kind, so
-- its spec stays inline at the site.
local TURNON_SHOW_DURATION_TEXT = { label = "Enable Duration Text", key = "showDurationText" }

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

local IsHeroSpecProxyCondition = ST._IsHeroSpecProxyCondition
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
local GetAuraBarAutocompleteEntryName = RBP.GetAuraBarAutocompleteEntryName
local ResolveAuraBarAutocompleteEntry = RBP.ResolveAuraBarAutocompleteEntry
local ShowAuraBarAutocompleteResults = RBP.ShowAuraBarAutocompleteResults
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

-- Candidate-resolution probe: the buttonData shape Core/Aura.lua reads,
-- synthesized from Custom Bar config (the same mapping the runtime adapter
-- uses). It is also safe for the Finder's one-time applicability preparation.
local function BuildCustomBarAuraProbe(cab)
    return {
        type = "spell",
        id = tonumber(cab.spellID),
        addedAs = (not IsSpellCustomBarConfig(cab)) and "aura" or nil,
        auraTracking = true,
        auraSpellID = cab.auraSpellID,
        auraUnit = cab.auraUnit,
        auraUnitOverride = cab.auraUnitOverride,
        auraIDOverride = tonumber(cab.auraIDOverride),
    }
end

local function ResolveCustomBarLayoutSpecID(settings, entry, fallbackSpecID)
    fallbackSpecID = tonumber(fallbackSpecID) or fallbackSpecID
    if RB.CustomBarHasSpec and fallbackSpecID
        and RB.CustomBarHasSpec(entry, fallbackSpecID)
    then
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
                and type(specLayout.customBars[entryCustomBarId]) == "table"
            then
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

------------------------------------------------------------------------
-- SETTINGS FINDER CATALOG
------------------------------------------------------------------------

local CUSTOM_BAR_FINDER = { sounds = {}, specs = {} }

local function FinderCustomBar(context)
    return context and context.customBar or nil
end

local function CustomBarEditorKey(prefix)
    return function(context)
        return prefix .. GetCustomBarCollapseKey(FinderCustomBar(context))
    end
end

local function FinderCustomBarCapabilities(context)
    local prepared = context and context._settingsFinderCustomBarState
    return prepared and prepared.capabilities or nil
end

local function FinderCustomBarHasSpell(context)
    local cab = FinderCustomBar(context)
    return cab and cab.spellID ~= nil
end

local function FinderCustomBarIsSpell(context)
    local caps = FinderCustomBarCapabilities(context)
    return caps and caps.isSpellBar == true
end

local function FinderCustomBarAuraActive(context)
    local cab = FinderCustomBar(context)
    return cab and cab.spellID ~= nil
        and (not IsSpellCustomBarConfig(cab) or cab.auraTracking == true)
end

local function FinderCustomBarAuraTracked(context)
    local caps = FinderCustomBarCapabilities(context)
    return caps and caps.auraTracked == true
end

local function FinderCustomBarShowsStackText(context)
    local cab = FinderCustomBar(context)
    if not cab then return false end
    local showStack = cab.showStackText
    if not IsSpellCustomBarConfig(cab) and showStack == nil then
        return cab.trackingMode ~= "active" and cab.showText == true
    end
    return showStack == true
end

local function FinderCustomBarAuraMax(context)
    local prepared = context and context._settingsFinderCustomBarState
    local value = prepared and prepared.auraMax
    return type(value) == "number" and value or nil
end

local function FinderCustomBarStackRowsInCombat(context)
    local prepared = context and context._settingsFinderCustomBarState
    return prepared and prepared.stackRowsInCombat == true or false
end

local function FinderCustomBarSizeField(context)
    local prepared = context and context._settingsFinderCustomBarState
    return prepared and prepared.sizeField or nil
end

local function FinderCustomBarSoundEvent(context, key)
    local prepared = context and context._settingsFinderCustomBarState
    local events = prepared and prepared.soundEvents
    return events and events[key] == true
end

local function FinderCustomBarLowTimeActive(context)
    local cab = FinderCustomBar(context)
    local threshold = cab and tonumber(cab.durationLowTimeThreshold)
    return threshold ~= nil and threshold > 0
end

local function FinderCustomBarLowTimeCriticalActive(context)
    local cab = FinderCustomBar(context)
    if not cab then return false end
    local threshold = tonumber(cab.durationLowTimeThreshold)
    local critical = tonumber(cab.durationLowTimeThreshold2)
    return threshold ~= nil and threshold > 0
        and critical ~= nil and critical > 0 and critical < threshold
end

local function PrepareCustomBarFinderContext(context)
    local cab = FinderCustomBar(context)
    if not cab then return end
    local settings = context.resourceSettings
        or CooldownCompanion:GetResourceBarSettings()
    local layoutSpecID = ResolveCustomBarLayoutSpecID(
        settings, cab, context.resourceSpecID or GetCurrentConfigSpecID())
    local layout = RB.GetSpecLayoutOrder
        and RB.GetSpecLayoutOrder(settings, layoutSpecID)
        or CooldownCompanion:GetSpecLayoutOrder()
    local thicknessField = GetResourceThicknessFieldConfig(settings, layout)
    local capabilities = RB.GetCustomBarConfigCapabilities(cab)

    local validEvents = CooldownCompanion:GetScopedValidSoundAlertEventsForCustomBar(cab)
    local soundEvents = {}
    for eventKey, available in pairs(validEvents or {}) do
        if available then
            local finderKey = eventKey
            if eventKey == "available"
                and CooldownCompanion:GetCustomBarSoundAlertEventLabel(cab, eventKey)
                    == "Available / Charge Gained"
            then
                finderKey = "availableCharges"
            end
            soundEvents[finderKey] = true
        end
    end

    local mode = cab.trackingMode
    if mode ~= "active" and mode ~= "stacks" then
        mode = capabilities.isSpellBar and "active" or "stacks"
    end
    local showsStackText = FinderCustomBarShowsStackText(context)
    local auraMax
    if (not capabilities.isSpellBar or cab.auraTracking == true)
        and (mode == "stacks" or showsStackText)
    then
        auraMax = CooldownCompanion:GetAuraStackBarMax(
            BuildCustomBarAuraProbe(cab), true)
    end

    context._settingsFinderCustomBarState = {
        capabilities = capabilities,
        sizeField = (layout and layout.customBarHeights) and thicknessField or false,
        soundEvents = soundEvents,
        auraMax = auraMax,
        stackRowsInCombat = showsStackText and InCombatLockdown() == true,
    }
end

if ST._RegisterSettingsFinderContextPreparer then
    ST._RegisterSettingsFinderContextPreparer(
        "customBar", PrepareCustomBarFinderContext)
end

local function FinderCustomBarCollapse(name)
    return function(context)
        return "cab_" .. name .. "_" .. GetCustomBarCollapseKey(FinderCustomBar(context))
    end
end

local function DefineCustomBarRoute(name, sectionLabel, opts)
    opts = opts or {}
    return ST._DefineSettingRoute({
        idPrefix = "customBar.settings." .. name,
        scope = "customBar",
        tab = "settings",
        tabLabel = "Settings",
        section = name,
        sectionLabel = sectionLabel,
        collapseKeys = FinderCustomBarCollapse(opts.collapseName or name),
        collapseStore = "resource",
        rowScope = "detail",
        advancedKey = opts.advancedKey,
        applies = opts.applies,
    })
end

if ST._DefineSettingRoute then
    local size = DefineCustomBarRoute("size", "Size")
    CUSTOM_BAR_FINDER.size = size:Settings({
        height = {
            label = "Bar Height",
            applies = function(context) return FinderCustomBarSizeField(context) == "barHeight" end,
        },
        width = {
            label = "Bar Width",
            applies = function(context) return FinderCustomBarSizeField(context) == "barWidth" end,
        },
    })

    local colors = DefineCustomBarRoute("colors", "Colors", { applies = FinderCustomBarHasSpell })
    CUSTOM_BAR_FINDER.colors = colors:Settings({
        bar = {
            label = "Bar Color",
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                return caps and caps.isSpellBar and caps.baseSpellShellConsumer
            end,
        },
        cooldown = {
            label = "Bar Cooldown Color",
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                return caps and caps.isSpellBar and caps.baseSpellShellConsumer and caps.cooldownConsumer
            end,
        },
        recharging = {
            label = "Bar Recharging Color",
            aliases = { "charge color" },
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                return caps and caps.isSpellBar and caps.hasCharges
            end,
        },
        aura = {
            label = "Aura Bar Color",
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                return caps and ((not caps.isSpellBar) or caps.auraTracked)
            end,
        },
    })

    local texts = DefineCustomBarRoute("texts", "Texts", { applies = FinderCustomBarHasSpell })
    CUSTOM_BAR_FINDER.texts = texts:Settings({
        duration = {
            label = "Show Duration Text",
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                return caps and caps.durationConsumer
            end,
        },
        count = {
            label = "Show Count Text (Charges/Uses)",
            aliases = { "charges", "uses" },
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                return caps and caps.isSpellBar and caps.countConsumer
            end,
        },
        stacks = {
            label = "Show Stack Text",
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                return caps and not caps.isSpellBar and caps.countConsumer
            end,
        },
        cooldownVisibility = { advancedKey = CustomBarEditorKey("rbCabDurationText_"),
            label = "Cooldown Visibility",
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                local cab = FinderCustomBar(context)
                return caps and cab and cab.showDurationText == true
                    and caps.isSpellBar and caps.auraTracked
            end,
        },
        cooldownLast = { advancedKey = CustomBarEditorKey("rbCabDurationText_"),
            label = "Cooldown: Show During Last",
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                local cab = FinderCustomBar(context)
                return caps and cab and cab.showDurationText == true
                    and caps.isSpellBar and caps.auraTracked
            end,
        },
        spellVisibility = { advancedKey = CustomBarEditorKey("rbCabDurationText_"),
            label = "Visible",
            aliases = { "cooldown visibility" },
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                local cab = FinderCustomBar(context)
                return caps and cab and cab.showDurationText == true
                    and caps.isSpellBar and not caps.auraTracked
            end,
        },
        spellLast = { advancedKey = CustomBarEditorKey("rbCabDurationText_"),
            label = "Show During Last",
            aliases = { "cooldown text threshold" },
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                local cab = FinderCustomBar(context)
                return caps and cab and cab.showDurationText == true
                    and caps.isSpellBar and not caps.auraTracked
            end,
        },
        auraVisibility = { advancedKey = CustomBarEditorKey("rbCabDurationText_"),
            label = "Aura Visibility",
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                local cab = FinderCustomBar(context)
                return caps and cab and cab.showDurationText == true
                    and caps.isSpellBar and caps.auraTracked
            end,
        },
        auraLast = { advancedKey = CustomBarEditorKey("rbCabDurationText_"),
            label = "Aura: Show During Last",
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                local cab = FinderCustomBar(context)
                return caps and cab and cab.showDurationText == true
                    and caps.isSpellBar and caps.auraTracked
            end,
        },
        auraOnlyVisibility = { advancedKey = CustomBarEditorKey("rbCabDurationText_"),
            label = "Visible",
            aliases = { "aura visibility" },
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                local cab = FinderCustomBar(context)
                return caps and cab and cab.showDurationText == true and not caps.isSpellBar
            end,
        },
        auraOnlyLast = { advancedKey = CustomBarEditorKey("rbCabDurationText_"),
            label = "Show During Last",
            aliases = { "aura text threshold" },
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                local cab = FinderCustomBar(context)
                return caps and cab and cab.showDurationText == true and not caps.isSpellBar
            end,
        },
        format = { advancedKey = CustomBarEditorKey("rbCabDurationText_"),
            label = "Duration Format",
            aliases = { "timer format" },
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                local cab = FinderCustomBar(context)
                return caps and cab and caps.durationConsumer and cab.showDurationText == true
            end,
        },
    })

    local function TextAdvanced(suffix, label, keyPrefix, applies)
        return DefineCustomBarRoute("texts." .. suffix, label, {
            collapseName = "texts",
            applies = applies,
            advancedKey = function(context)
                return keyPrefix .. GetCustomBarCollapseKey(FinderCustomBar(context))
            end,
        })
    end
    -- Advanced routes index on the bar's CAPABILITY alone: the gear now exists
    -- with the text toggle off too, opening its panel read-only behind the
    -- unlock strip with the searched row drawn inside.
    CUSTOM_BAR_FINDER.durationText = TextAdvanced("duration", "Duration Text", "rbCabDurationText_",
        function(context)
            local caps = FinderCustomBarCapabilities(context)
            return caps and FinderCustomBar(context) and caps.durationConsumer or false
        end):Settings({
            fontSize = { label = "Font Size" }, font = { label = "Font" }, outline = { label = "Font Outline" },
            color = { label = "Duration Text Color" },
        })
    CUSTOM_BAR_FINDER.stackText = TextAdvanced("stack", "Other Text", "rbCabStackText_",
        function(context)
            local caps = FinderCustomBarCapabilities(context)
            return caps and FinderCustomBar(context) and caps.countConsumer or false
        end):Settings({
            fontSize = { label = "Font Size" }, font = { label = "Font" }, outline = { label = "Font Outline" },
            color = { label = "Stack Text Color" },
        })

    local lowTime = DefineCustomBarRoute("texts.lowTime", "Duration Text", {
        collapseName = "texts",
        applies = function(context)
            local caps = FinderCustomBarCapabilities(context)
            local cab = FinderCustomBar(context)
            return caps and cab and caps.durationConsumer and cab.showDurationText == true
        end,
    })
    CUSTOM_BAR_FINDER.lowTime = lowTime:Settings({
        enabled = { label = "Change Text Near Expiry", aliases = { "low time", "warning time" } },
        warningThreshold = { advancedKey = CustomBarEditorKey("rbCabLowTime_"), label = "Start Warning Below", applies = FinderCustomBarLowTimeActive },
        warningColor = { advancedKey = CustomBarEditorKey("rbCabLowTime_"), label = "Warning Color", applies = FinderCustomBarLowTimeActive },
        auras = { advancedKey = CustomBarEditorKey("rbCabLowTime_"),
            label = "Also Apply to Aura Text",
            applies = function(context)
                return FinderCustomBarLowTimeActive(context)
                    and FinderCustomBarIsSpell(context)
                    and FinderCustomBarAuraTracked(context)
            end,
        },
        critical = { advancedKey = CustomBarEditorKey("rbCabLowTime_"), label = "Add Critical Styling", applies = FinderCustomBarLowTimeActive },
        criticalThreshold = { advancedKey = CustomBarEditorKey("rbCabLowTime_"), label = "Start Critical Below", applies = FinderCustomBarLowTimeCriticalActive },
        criticalColor = { advancedKey = CustomBarEditorKey("rbCabLowTime_"), label = "Critical Color", applies = FinderCustomBarLowTimeCriticalActive },
        decimals = { advancedKey = CustomBarEditorKey("rbCabLowTime_"), label = "Show Decimals Near Expiry", applies = FinderCustomBarLowTimeActive },
    })

    local aura = DefineCustomBarRoute("aura", "Aura Tracking", { applies = FinderCustomBarHasSpell })
    CUSTOM_BAR_FINDER.aura = aura:Settings({
        tracking = { label = "Track an Aura", applies = FinderCustomBarIsSpell },
        trackedOn = { label = "Tracked on", aliases = { "aura unit", "target", "player", "group", "pet" }, applies = FinderCustomBarAuraActive },
        idOverride = { label = "Aura ID Override", applies = FinderCustomBarAuraActive },
        showsStacks = { label = "Bar Shows Stacks", applies = FinderCustomBarAuraActive },
        stackStyle = { advancedKey = CustomBarEditorKey("rbCabStackDisplay_"),
            label = "Stack Style",
            applies = function(context)
                local cab = FinderCustomBar(context)
                return FinderCustomBarAuraActive(context) and cab and cab.trackingMode == "stacks"
                    and FinderCustomBarAuraMax(context) ~= nil
            end,
        },
        segmentGap = { advancedKey = CustomBarEditorKey("rbCabStackDisplay_"),
            label = "Segment Gap",
            applies = function(context)
                local cab = FinderCustomBar(context)
                return FinderCustomBarAuraActive(context) and cab
                    and not IsSpellCustomBarConfig(cab) and cab.trackingMode == "stacks"
                    and cab.displayMode ~= "continuous"
                    and FinderCustomBarAuraMax(context) ~= nil
                    and FinderCustomBarAuraMax(context) <= ST.STACK_SEGMENT_ATLAS_MAX
            end,
        },
        showOne = { advancedKey = CustomBarEditorKey("rbCabStackText_"), collapseKeys = FinderCustomBarCollapse("texts"),
            label = "Show Count at 1 Stack",
            applies = function(context)
                local cab = FinderCustomBar(context)
                local auraBar = cab and cab.auraBar
                return FinderCustomBarAuraActive(context) and FinderCustomBarShowsStackText(context)
                    and (FinderCustomBarAuraMax(context) ~= nil
                        or FinderCustomBarStackRowsInCombat(context)
                        or (type(auraBar) == "table" and auraBar.showCountAtOne == true))
            end,
        },
        threshold = { advancedKey = CustomBarEditorKey("rbCabStackText_"), collapseKeys = FinderCustomBarCollapse("texts"),
            label = "Stack Text Threshold Color",
            applies = function(context)
                return FinderCustomBarAuraActive(context) and FinderCustomBarShowsStackText(context)
                    and (FinderCustomBarAuraMax(context) ~= nil or FinderCustomBarStackRowsInCombat(context))
            end,
        },
        thresholdStacks = { advancedKey = CustomBarEditorKey("rbCabStackText_"), collapseKeys = FinderCustomBarCollapse("texts"),
            label = "Threshold Stacks",
            applies = function(context)
                local cab = FinderCustomBar(context)
                return cab and type(cab.auraBar) == "table" and cab.auraBar.thresholdValue ~= nil
                    and FinderCustomBarShowsStackText(context)
                    and (FinderCustomBarAuraMax(context) ~= nil or FinderCustomBarStackRowsInCombat(context))
            end,
        },
        thresholdColor = { advancedKey = CustomBarEditorKey("rbCabStackText_"), collapseKeys = FinderCustomBarCollapse("texts"),
            label = "Threshold Color",
            applies = function(context)
                local cab = FinderCustomBar(context)
                return cab and type(cab.auraBar) == "table" and cab.auraBar.thresholdValue ~= nil
                    and FinderCustomBarShowsStackText(context)
                    and (FinderCustomBarAuraMax(context) ~= nil or FinderCustomBarStackRowsInCombat(context))
            end,
        },
        maxStacks = { advancedKey = CustomBarEditorKey("rbCabStackText_"), collapseKeys = FinderCustomBarCollapse("texts"),
            label = "Max Stacks Text Color",
            applies = function(context)
                return FinderCustomBarAuraActive(context) and FinderCustomBarShowsStackText(context)
                    and FinderCustomBarAuraMax(context) ~= nil
            end,
        },
        maxColor = { advancedKey = CustomBarEditorKey("rbCabStackText_"), collapseKeys = FinderCustomBarCollapse("texts"),
            label = "Max Color",
            applies = function(context)
                local cab = FinderCustomBar(context)
                return cab and type(cab.auraBar) == "table" and cab.auraBar.maxColorEnabled == true
                    and FinderCustomBarShowsStackText(context) and FinderCustomBarAuraMax(context) ~= nil
            end,
        },
        pandemic = {
            label = "Pandemic Marker",
            applies = function(context)
                local cab = FinderCustomBar(context)
                return FinderCustomBarAuraActive(context) and cab and cab.showDurationText == true
            end,
        },
        pandemicColor = { label = "Show Pandemic Color", applies = FinderCustomBarAuraActive },
        fillColor = { advancedKey = CustomBarEditorKey("rbCabPandemicColor_"),
            label = "Fill Color",
            applies = function(context)
                local cab = FinderCustomBar(context)
                return FinderCustomBarAuraActive(context) and cab and cab.pandemicEffect == true
            end,
        },
        inactiveState = {
            label = "While Aura Inactive",
            aliases = { "show only while aura active", "dim while aura inactive", "hide aura inactive" },
            applies = FinderCustomBarAuraActive,
        },
    })
    CUSTOM_BAR_FINDER.stackFormatting = {
        showOne = CUSTOM_BAR_FINDER.aura.showOne,
        threshold = CUSTOM_BAR_FINDER.aura.threshold,
        thresholdStacks = CUSTOM_BAR_FINDER.aura.thresholdStacks,
        thresholdColor = CUSTOM_BAR_FINDER.aura.thresholdColor,
        maxStacks = CUSTOM_BAR_FINDER.aura.maxStacks,
        maxColor = CUSTOM_BAR_FINDER.aura.maxColor,
    }

    local marker = DefineCustomBarRoute("aura.marker", "Aura Tracking", {
        collapseName = "aura",
        applies = function(context)
            local cab = FinderCustomBar(context)
            return FinderCustomBarAuraActive(context) and cab and cab.showDurationText == true
        end,
        advancedKey = function(context)
            return "rbCabPandemicMarker_" .. GetCustomBarCollapseKey(FinderCustomBar(context))
        end,
    })
    CUSTOM_BAR_FINDER.marker = marker:Settings({
        text = { label = "Marker Text" }, coloring = { label = "Marker Coloring" }, color = { label = "Marker Color" },
    })

    local effects = DefineCustomBarRoute("effects", "Effects", {
        collapseName = "aura_effects",
        applies = FinderCustomBarAuraTracked,
    })
    local function FinderBarAuraEffectIs(context, expected)
        local cab = FinderCustomBar(context)
        return cab and (cab.barAuraEffect or "color") == expected
    end
    CUSTOM_BAR_FINDER.effects = effects:Settings({
        style = { label = "Glow Style" }, color = { advancedKey = "customBarAuraBorder", label = "Effect Color" },
        color2 = { advancedKey = "customBarAuraBorder", label = "Second Color", applies = function(context) return FinderBarAuraEffectIs(context, "colorShift") end },
        borderSize = { advancedKey = "customBarAuraBorder",
            label = "Border Size",
            applies = function(context)
                return FinderBarAuraEffectIs(context, "solid") or FinderBarAuraEffectIs(context, "pulse")
                    or FinderBarAuraEffectIs(context, "colorShift")
            end,
        },
        pulseDuration = { advancedKey = "customBarAuraBorder", label = "Border Pulse Duration", aliases = { "pulse duration" }, applies = function(context) return FinderBarAuraEffectIs(context, "pulse") end },
        dashLength = { advancedKey = "customBarAuraBorder", label = "Dash Length", applies = function(context) return FinderBarAuraEffectIs(context, "dashes") end },
        dashThickness = { advancedKey = "customBarAuraBorder", label = "Dash Thickness", applies = function(context) return FinderBarAuraEffectIs(context, "dashes") end },
        dashCount = { advancedKey = "customBarAuraBorder", label = "Number of Dashes", applies = function(context) return FinderBarAuraEffectIs(context, "dashes") end },
        lapDuration = { advancedKey = "customBarAuraBorder", label = "Lap Duration", applies = function(context) return FinderBarAuraEffectIs(context, "dashes") end },
        shiftDuration = { advancedKey = "customBarAuraBorder", label = "Border Shift Duration", aliases = { "shift duration" }, applies = function(context) return FinderBarAuraEffectIs(context, "colorShift") end },
        pulseFill = { label = "Pulse Bar Fill" },
        pulseFillDuration = { advancedKey = "customBarAuraPulse",
            label = "Fill Pulse Duration", aliases = { "pulse duration" },
            applies = function(context)
                local cab = FinderCustomBar(context)
                return cab and cab.barAuraPulseEnabled == true
            end,
        },
        colorShiftFill = { label = "Color Shift Bar Fill" },
        colorShiftDuration = { advancedKey = "customBarAuraShift",
            label = "Fill Shift Duration", aliases = { "shift duration" },
            applies = function(context)
                local cab = FinderCustomBar(context)
                return cab and cab.barAuraColorShiftEnabled == true
            end,
        },
        shiftColor = { advancedKey = "customBarAuraShift",
            label = "Shift Color",
            applies = function(context)
                local cab = FinderCustomBar(context)
                return cab and cab.barAuraColorShiftEnabled == true
            end,
        },
    })

    local sound = DefineCustomBarRoute("sound", "Sound Alerts", {
        applies = FinderCustomBarHasSpell,
    })
    local soundLabels = {
        available = "Available", availableCharges = "Available / Charge Gained", onCooldown = "On Cooldown",
        onAuraApplied = "Aura Applied", onAuraStackGained = "Aura Stack Gained", onAuraRemoved = "Aura Removed",
    }
    for key, label in pairs(soundLabels) do
        local descriptorKey = key
        CUSTOM_BAR_FINDER.sounds[descriptorKey] = sound:Setting({
            key = descriptorKey,
            label = label,
            aliases = descriptorKey == "availableCharges" and { "available", "charge gained" } or nil,
            applies = function(context)
                return FinderCustomBarSoundEvent(context, descriptorKey)
            end,
        })
    end

    local rules = DefineCustomBarRoute("hiderules", "Show & Hide Rules", {
        applies = function(context)
            local caps = FinderCustomBarCapabilities(context)
            return caps and caps.isSpellBar and caps.cooldownConsumer
        end,
    })
    CUSTOM_BAR_FINDER.rules = rules:Settings({
        cooldownVisibility = {
            label = "Cooldown Visibility",
            aliases = {
                "hide while on cooldown", "hide while not on cooldown", "hide while ready",
                "only show at zero charges", "zero charges only",
            },
        },
        hideZero = {
            label = "Hide While At Zero Charges",
            applies = function(context)
                local caps = FinderCustomBarCapabilities(context)
                return caps and caps.hasCharges
            end,
        },
    })

    local specs = DefineCustomBarRoute("specs", "Specializations")
    for _, spec in ipairs(GetCustomBarSpecOptions()) do
        CUSTOM_BAR_FINDER.specs[spec.id] = specs:Setting({
            key = tostring(spec.id),
            label = spec.name,
            aliases = { "specialization", "spec" },
        })
    end
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
        local specRow = AddCheckboxRow(index <= splitAt and specLeft or specRight, {
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
        if ST._BindSettingWidget and CUSTOM_BAR_FINDER.specs[capturedSpec.id] then
            ST._BindSettingWidget(specRow, CUSTOM_BAR_FINDER.specs[capturedSpec.id])
        end
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

    local validEvents = CooldownCompanion:GetScopedValidSoundAlertEventsForCustomBar(cab)

    if soundCollapsed then return end

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
        local soundSettingKey = eventKey
        if eventKey == "available"
            and CooldownCompanion:GetCustomBarSoundAlertEventLabel(cab, eventKey) == "Available / Charge Gained" then
            soundSettingKey = "availableCharges"
        end
        AddSoundPreviewDropdownRow(column, {
            label = CooldownCompanion:GetCustomBarSoundAlertEventLabel(cab, eventKey),
            setting = CUSTOM_BAR_FINDER.sounds[soundSettingKey],
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

    local auraNoteColumn
    if #cooldownEvents > 0 and #auraEvents > 0 then
        for _, eventKey in ipairs(cooldownEvents) do
            AddSoundEventRow(soundLeft, eventKey)
        end
        for _, eventKey in ipairs(auraEvents) do
            AddSoundEventRow(soundRight, eventKey)
        end
        auraNoteColumn = soundRight
    else
        -- ceil(n/2) left, the rest right - the per-resource Colors precedent.
        local survivors = (#cooldownEvents > 0) and cooldownEvents or auraEvents
        local splitAt = math.ceil(#survivors / 2)
        for index, eventKey in ipairs(survivors) do
            AddSoundEventRow(index <= splitAt and soundLeft or soundRight, eventKey)
        end
        if survivors == auraEvents then
            auraNoteColumn = soundRight
        end
    end

    -- Group scope caveat: the aura sound registration is per person, so the
    -- engine only arms it while the tracked unit set is a single unit
    -- (ungrouped). The rows stay live because they DO play solo; this line
    -- keeps the limitation visible instead of silent.
    if cab.auraTrackGroup == true and #auraEvents > 0 and auraNoteColumn then
        local groupNote = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(groupNote)
        groupNote:SetText("|cff888888Tracking your group: aura sounds only play while you are ungrouped.|r")
        groupNote:SetFullWidth(true)
        auraNoteColumn:AddChild(groupNote)
    end
end

local function BuildCustomBarLoadConditionsTab(container, cab, infoButtons, capabilities)
    local settings = CooldownCompanion:GetResourceBarSettings()
    local currentSpecID = GetCurrentConfigSpecID()

    -- Show & hide rules (spell bars): the cheap panel subset, computed from
    -- state the per-tick cooldown evaluation already resolves. Labels,
    -- keys, and interlocks mirror ButtonConditions so the two surfaces
    -- teach each other.
    if capabilities.isSpellBar and capabilities.cooldownConsumer then
        local rulesHeading, rulesCollapsed =
            AddCustomBarSection(container, "Show & Hide Rules", "hiderules", GetCustomBarCollapseKey(cab))
        local rulesInfoBtn = CreateInfoButton(rulesHeading.frame, rulesHeading.label, "LEFT", "RIGHT", 4, 0, {
            "Show & Hide Rules",
            {"Hides the bar by cooldown or charge state.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"Its slot in the bar stack stays reserved while hidden.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"When the game hides a spell's cooldown from addons, the bar stays shown.", 1, 1, 1, true},
        }, infoButtons)
        AnchorLeftAlignedHeadingRule(rulesHeading, rulesInfoBtn)

        if not rulesCollapsed then
            local function CommitRules()
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RefreshConfigPanel()
            end
            local rulesLeft, rulesRight = BeginRowGrid(container)
            local isChargeSpell = capabilities.hasCharges

            -- One dropdown states the cooldown family (panel parity: the
            -- Cooldown Visibility row in ButtonConditions). The three keys
            -- underneath are unchanged; the row derives one value from them
            -- and writes them back as a set, so the two directions can never
            -- both be on. A bar has no dim variants: it either keeps its slot
            -- or hides in it.
            local zeroOnly = isChargeSpell and cab.showOnlyAtZeroCharges == true
                and cab.hideWhileNotOnCooldown == true
            -- Labels and tooltip are the panel row's own (ST._COOLDOWN_VISIBILITY,
            -- Helpers.lua), so the two surfaces cannot drift apart.
            local cooldownLabels = ST._COOLDOWN_VISIBILITY.labels
            local cooldownList = {
                show = cooldownLabels.show,
                hide_cooldown = cooldownLabels.hide_cooldown,
                hide_ready = cooldownLabels.hide_ready,
            }
            local cooldownOrder = { "show", "hide_cooldown", "hide_ready" }
            if isChargeSpell then
                cooldownList.zero_only = cooldownLabels.zero_only
                cooldownOrder[#cooldownOrder + 1] = "zero_only"
            end
            local cooldownValue = "show"
            if cab.hideWhileOnCooldown == true then
                cooldownValue = "hide_cooldown"
            elseif cab.hideWhileNotOnCooldown == true then
                cooldownValue = zeroOnly and "zero_only" or "hide_ready"
            end
            local cooldownRow = AddDropdownRow(rulesLeft, {
                setting = CUSTOM_BAR_FINDER.rules.cooldownVisibility,
                list = cooldownList,
                order = cooldownOrder,
                value = cooldownValue,
                onChange = function(value)
                    cab.hideWhileOnCooldown = value == "hide_cooldown" or nil
                    cab.hideWhileNotOnCooldown = (value == "hide_ready" or value == "zero_only") or nil
                    cab.showOnlyAtZeroCharges = value == "zero_only" or nil
                    if value == "zero_only" then
                        cab.hideWhileZeroCharges = nil
                    end
                    CommitRules()
                end,
            })
            -- Showing only at zero charges contradicts hiding at zero
            -- charges, so each side greys the other's option rather than
            -- silently clearing it.
            if isChargeSpell and cab.hideWhileZeroCharges == true then
                cooldownRow:SetItemDisabled("zero_only", true)
            end
            local cooldownInfo = { "Cooldown Visibility" }
            for _, line in ipairs(ST._COOLDOWN_VISIBILITY.tooltipLines) do
                cooldownInfo[#cooldownInfo + 1] = line
            end
            AnchorRowBadge(cooldownRow, CreateInfoButton(cooldownRow.frame, cooldownRow.frame, "LEFT", "LEFT", 0, 0,
                cooldownInfo, infoButtons))

            if isChargeSpell then
                AddCheckboxRow(rulesRight, {
                    label = "Hide While At Zero Charges",
                    setting = CUSTOM_BAR_FINDER.rules.hideZero,
                    value = cab.hideWhileZeroCharges == true,
                    disabled = zeroOnly,
                    tooltip = zeroOnly and {
                        "Hide While At Zero Charges",
                        {"Not available while Cooldown Visibility shows the bar only at zero charges.", 1, 1, 1, true},
                    } or nil,
                    onChange = function(value)
                        cab.hideWhileZeroCharges = value or nil
                        if value then
                            cab.showOnlyAtZeroCharges = nil
                        end
                        CommitRules()
                    end,
                })
            end
        end
    end

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
        settings = ST._CustomBarLoadConditionFinderSettings,
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
-- custom bars. The tracked unit is auto-derived from spell polarity by
-- default, with the same user override as panels (Blizzard's anti-cheat
-- gate checks the live aura instance, so an override that lies about real
-- polarity harmlessly matches nothing); max stacks is automatic from game
-- data. Every change goes through ApplyResourceBars, which requests the
-- OOC aura rebind.
--
-- PARITY TWIN (owner directive 2026-08-28): this section mirrors the panel
-- entry Aura Tracking section (ButtonSettingsAura.lua). A feature added or
-- changed there must land here in the same change, or the gap explicitly
-- surfaced to the owner. Custom bars behave exactly like bar panel entries
-- outside their two structural roles (panels anchor freely; custom bars
-- ride the resource stack). One shape difference stands: polarity override
-- and scope share this section's single Tracked on dropdown (scope
-- exclusivity ruling 2026-08-26) where panels use a dropdown + checkboxes.
-- Known gap from that shape: a bar holding BOTH a player unit override and
-- a group/pet scope displays the scope, so the override is active but
-- invisible until Automatic clears both (panels show two controls and
-- never shadow it).
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

-- The user's explicit unit override, when set (panel parity: absolute over
-- every derived answer in this section).
local function GetCustomBarAuraUnitOverride(cab)
    local override = cab.auraUnitOverride
    if override == "player" or override == "target" then
        return override
    end
    return nil
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

-- Polarity guard unit for the shared add path (panel parity,
-- GetCandidateAddGuardUnit): inert while the unit override is set — the
-- guard judges by the classifier the override exists to overrule.
local function GetCustomBarAuraAddGuardUnit(cab)
    if GetCustomBarAuraUnitOverride(cab) then
        return nil
    end
    local resolved = CooldownCompanion:ResolveAuraSpellID(BuildCustomBarAuraProbe(cab))
    return ClassifyAuraSpellUnit(resolved) or cab.auraUnit or "player"
end

-- Store the derived unit whenever tracking config changes, so the runtime
-- fallback (uncached spells at login) starts from the right value.
local function SyncCustomBarDerivedAuraUnit(cab)
    local probe = BuildCustomBarAuraProbe(cab)
    -- The stored auraUnit tracks the EFFECTIVE unit (panel parity): the
    -- user override when set, else derived.
    local unit = GetCustomBarAuraUnitOverride(cab)
        or ClassifyAuraSpellUnit(CooldownCompanion:ResolveAuraSpellID(probe))
    if unit then
        cab.auraUnit = unit
        cab.auraUnitExplicit = nil
        -- Drop scope flags the runtime would ignore (panel parity:
        -- SyncDerivedAuraUnit). Debuffs resolve to your target and ignore both.
        -- Group scope still requires ownership through the bar's castable spell;
        -- pet scope also accepts standalone Aura bars because they may describe
        -- a pet self-buff with no separate cast entry.
        local barSpellID = tonumber(cab.spellID)
        if unit == "target" then
            cab.auraTrackGroup = nil
            cab.auraTrackPet = nil
        else
            if CooldownCompanion:EntryOwnsAuraForGroupScope(probe, barSpellID) ~= true then
                cab.auraTrackGroup = nil
            end
            if not CooldownCompanion:EntryCanUsePetAuraScope(probe, barSpellID) then
                cab.auraTrackPet = nil
            end
            -- Same classifier-polarity veto as the section's groupVetoed:
            -- inert under a valid unit override.
            if cab.auraTrackGroup == true and IsSpellCustomBarConfig(cab)
                and not GetCustomBarAuraUnitOverride(cab)
                and #GetAuraCandidateList(cab) > 0 then
                local baseUnit = ClassifyAuraSpellUnit(barSpellID)
                if baseUnit and baseUnit ~= unit then
                    cab.auraTrackGroup = nil
                end
            end
        end
    end
end

local function BuildCustomBarAuraTrackingSection(container, cab, infoButtons, sectionKey)
    local isSpellBar = IsSpellCustomBarConfig(cab)
    local mode = cab.trackingMode
    if mode ~= "active" and mode ~= "stacks" then
        mode = isSpellBar and "active" or "stacks"
    end
    local showsStackText = CustomBarShowsStackText(cab)
    local maxStacks
    if (not isSpellBar or cab.auraTracking == true)
        and (mode == "stacks" or showsStackText) then
        maxStacks = CooldownCompanion:GetAuraStackBarMax(BuildCustomBarAuraProbe(cab), true)
    end
    local _, collapsed = AddCustomBarSettingsHeading(container, "Aura Tracking", "aura", sectionKey, infoButtons, {
        "Blizzard tracks the aura and drives the bar; the addon never reads aura state in combat.",
        " ",
        "Buffs are tracked on you, and your own debuffs on your target. This is a Blizzard restriction. The tracked unit is detected automatically. If the game's data gets one wrong, set Tracked on yourself.",
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
            setting = CUSTOM_BAR_FINDER.aura.tracking,
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

    -- Tracked unit: automatic polarity with a user override, plus the
    -- eligible scope choices, in ONE dropdown — scopes stay structurally
    -- exclusive (owner ruling 2026-08-26) and the polarity entries are the
    -- user unit override (panel parity 2026-08-28, absolute at bind time).
    local probe = BuildCustomBarAuraProbe(cab)
    local resolvedAuraID = CooldownCompanion:ResolveAuraSpellID(probe)
    -- The resolved aura can be a LINKED applied-aura ID distinct from the
    -- castable spell (Lifebloom 33763 applies 1227806, runtime-confirmed
    -- 2026-08-26), so classification falls back to the bar's own spell and
    -- ownership is probed on the bar's own spell only — that IS the
    -- castable identity the user added; the applied ID is never castable.
    local barSpellID = tonumber(cab.spellID)
    local unitOverride = GetCustomBarAuraUnitOverride(cab)
    local classifiedUnit = ClassifyAuraSpellUnit(resolvedAuraID)
        or ClassifyAuraSpellUnit(barSpellID)
    -- A user override IS confirmed polarity: it decides the bind unit.
    local confirmedUnit = unitOverride or classifiedUnit
    local unit = confirmedUnit or cab.auraUnit or "player"
    local isBuff = unit ~= "target"

    -- Reconcile stale scope on a CONFIRMED-harmful bar (imported or drifted
    -- config): the runtime resolves it to the target and ignores the flags,
    -- while they still steer IsAuraBlockEntry. Confirmed polarity only;
    -- never clear on the uncached-spell fallback guess.
    if confirmedUnit == "target"
        and (cab.auraTrackGroup ~= nil or cab.auraTrackPet ~= nil) then
        cab.auraTrackGroup = nil
        cab.auraTrackPet = nil
    end

    -- Scope eligibility, panel parity (ButtonSettingsAura): group requires a
    -- confirmed owned buff and additionally loses to an opposite-polarity Aura
    -- list on spell bars. Pet requires a confirmed buff plus the CORE pet rule,
    -- which admits standalone Aura bars, and sticky pet-class capability. A
    -- stored flag always keeps its clearing path regardless of gates.
    local coreOwnsForGroupScope = confirmedUnit ~= nil and isBuff
        and CooldownCompanion:EntryOwnsAuraForGroupScope(probe, barSpellID) == true
    local coreAllowsPetScope = confirmedUnit ~= nil and isBuff
        and CooldownCompanion:EntryCanUsePetAuraScope(probe, barSpellID)
    -- The opposite-polarity veto judges by classifier polarity, which a
    -- valid unit override overrules by fiat — skip only the veto under an
    -- override; castability/ownership checks above still apply.
    local groupVetoed = false
    if isSpellBar and not unitOverride and #GetAuraCandidateList(cab) > 0 then
        local baseUnit = ClassifyAuraSpellUnit(tonumber(cab.spellID))
        if baseUnit and confirmedUnit and baseUnit ~= confirmedUnit then
            groupVetoed = true
        end
    end
    local canPets = ST._CharacterCanCommandPets
    local canTrackGroup = (coreOwnsForGroupScope and not groupVetoed)
        or cab.auraTrackGroup == true
    local canTrackPet = (coreAllowsPetScope and canPets and canPets() == true)
        or cab.auraTrackPet == true

    local automaticLabel = "Automatic"
    if classifiedUnit == "target" then
        automaticLabel = "Automatic (Target)"
    elseif classifiedUnit == "player" then
        automaticLabel = "Automatic (You)"
    end
    local scopeList = {
        automatic = automaticLabel,
        player = "You",
        target = "Target",
    }
    local scopeOrder = { "automatic", "player", "target" }
    if canTrackGroup then
        scopeList.group = "You and your group"
        scopeOrder[#scopeOrder + 1] = "group"
    end
    if canTrackPet then
        scopeList.pet = "Your pet"
        scopeOrder[#scopeOrder + 1] = "pet"
    end
    local scopeValue = cab.auraTrackPet == true and "pet"
        or cab.auraTrackGroup == true and "group"
        or unitOverride
        or "automatic"
    local scopeRow = AddDropdownRow(auraLeft, {
        label = "Tracked on",
        setting = CUSTOM_BAR_FINDER.aura.trackedOn,
        indent = isSpellBar,
        list = scopeList,
        order = scopeOrder,
        value = scopeValue,
        onChange = function(value)
            if value == "group" or value == "pet" then
                -- Scope choices leave the unit override untouched: both
                -- are only offered on confirmed buffs, and an override to
                -- "player" is what confirmed some of them.
                cab.auraTrackGroup = value == "group" and true or nil
                cab.auraTrackPet = value == "pet" and true or nil
            else
                cab.auraTrackGroup = nil
                cab.auraTrackPet = nil
                cab.auraUnitOverride = (value == "player" or value == "target")
                    and value or nil
            end
            SyncCustomBarDerivedAuraUnit(cab)
            -- Scope can move an aura bar between the collapsing block
            -- and the fixed stack (group/pet bars always keep a slot),
            -- so commit like a layout change, not just a refresh.
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RepositionCastBar()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    AnchorRowBadge(scopeRow, CreateInfoButton(scopeRow.frame, scopeRow.frame, "LEFT", "LEFT", 0, 0, {
        "Tracked On",
        {"Automatic follows the detected buff or debuff. You and Target force it when the game's data gets one wrong.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"You and your group follows the buff onto anyone in your party or raid, like a healer's Lifebloom on a tank.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Best for buffs that sit on one person at a time. The addon is never told who holds the aura, so a buff on several people draws overlapping displays.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Aura sounds only play while you are ungrouped. In a group they fire per person, so moving the buff would sound like it dropped.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Your pet tracks the buff on your summoned pet instead of on you, like Dark Transformation on a ghoul.", 1, 1, 1, true},
    }, infoButtons))

    -- The head-replacement escape hatch, one shape on every entry kind
    -- (panel parity, ButtonSettingsAura): replaces the automatic aura head
    -- verbatim; the list below keeps adding auras beside it. On spell bars
    -- it also retires the own-aura implicit fallback.
    AddEditBoxRow(auraLeft, {
        label = "Aura ID Override",
        setting = CUSTOM_BAR_FINDER.aura.idOverride,
        indent = isSpellBar,
        value = cab.auraIDOverride and tostring(cab.auraIDOverride) or "",
        tooltip = {
            "Aura ID Override",
            {"Replaces the automatically detected aura with exactly this ID. Auras added below still track alongside it.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"Use when detection picks the wrong aura for this bar. Leave empty for automatic.", 1, 1, 1, true},
        },
        onEnterPressed = function(text, widget)
            text = text and text:gsub("%s+", "") or ""
            if text == "" then
                if cab.auraIDOverride ~= nil then
                    cab.auraIDOverride = nil
                    SyncCustomBarDerivedAuraUnit(cab)
                end
                RefreshCustomBarAuraConfig()
                return
            end
            local spellID = tonumber(text)
            if not (spellID and spellID > 0 and C_Spell.DoesSpellExist(spellID)) then
                CooldownCompanion:Print("Aura ID not found: " .. text
                    .. ". Enter a numeric spell ID, or leave empty for automatic.")
                widget:SetText(cab.auraIDOverride and tostring(cab.auraIDOverride) or "")
                return
            end
            cab.auraIDOverride = spellID
            SyncCustomBarDerivedAuraUnit(cab)
            RefreshCustomBarAuraConfig()
        end,
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
            if TryAddAuraCandidate(cab, text, GetCustomBarAuraAddGuardUnit(cab), SyncCustomBarDerivedAuraUnit) then
                widget:SetText("")
                RefreshCustomBarAuraConfig()
            end
        end,
    })

    -- Read-only, panel parity (ButtonSettingsAura "Tracked Aura ID"): the
    -- aura ID(s) that can actually appear on a unit for this bar, not the
    -- bind's full insurance filter. Spell bars list the user's adds plus
    -- their own aura, which custom bars keep as a fallback unconditionally
    -- (their candidate build is unconstrained); Aura bars lead with the
    -- resolved applied identity.
    --
    -- Last row of this block, same as the twin: it is the RESULT of every
    -- control above it, so it reads after its causes rather than ahead of
    -- them.
    local trackedAuraIDs = {}
    local trackedAuraIDSeen = {}
    local function AppendTrackedAuraID(id)
        id = tonumber(id)
        if id and not trackedAuraIDSeen[id] then
            trackedAuraIDSeen[id] = true
            trackedAuraIDs[#trackedAuraIDs + 1] = tostring(id)
        end
    end
    local hasIDOverride = tonumber(cab.auraIDOverride) ~= nil
    if isSpellBar then
        -- An ID override replaces the implicit head: it leads the line and
        -- the bar's own aura leaves the filter with the rest of the
        -- automatic machinery (panel parity).
        if hasIDOverride then
            AppendTrackedAuraID(resolvedAuraID)
        end
        for _, id in ipairs(GetAuraCandidateList(cab)) do
            AppendTrackedAuraID(id)
        end
        if not hasIDOverride then
            AppendTrackedAuraID(CooldownCompanion:ResolveImplicitAuraSpellID(probe))
        end
    else
        AppendTrackedAuraID(resolvedAuraID)
        for _, id in ipairs(GetAuraCandidateList(cab)) do
            AppendTrackedAuraID(id)
        end
    end
    AddLabelRow(auraLeft, {
        label = #trackedAuraIDs > 1 and "Tracked Aura IDs" or "Tracked Aura ID",
        indent = isSpellBar,
        controlText = #trackedAuraIDs > 0
            and table.concat(trackedAuraIDs, ", ") or "None",
    })

    -- Bar fill mode: duration drain or stack count. Max stacks is automatic
    -- (game data); the status line shows what resolved.
    local stacksRow = AddCheckboxRow(auraRight, {
        label = "Bar Shows Stacks",
        setting = CUSTOM_BAR_FINDER.aura.showsStacks,
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

    ST._AddAdvancedToggle(stacksRow, "rbCabStackDisplay_" .. tostring(sectionKey), {}, true, {
        unlock = mode ~= "stacks" and { target = cab, refreshKind = "resourceBars",
            enable = { label = "Enable Stack Display", apply = function(write) write.trackingMode = "stacks" end } } or nil,
        build = function(panel)
            -- Constrained, matching every runtime resolve since the review
            -- alignment (2026-08-15): one max across config, bind, and policy.
            if maxStacks then
                AddDropdownRow(panel, {
                    label = "Stack Style",
                    setting = CUSTOM_BAR_FINDER.aura.stackStyle,
                    indent = false,
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
                    ST._AddStackBlockGapRow(panel, cab, {
                        setting = CUSTOM_BAR_FINDER.aura.segmentGap,
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
            AddAuraStackMaxStatusLabel(panel, maxStacks, { row = true })
        end,
    })

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
            setting = CUSTOM_BAR_FINDER.aura.pandemic,
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
            end, {
                childrenOnly = true,
                settings = CUSTOM_BAR_FINDER.marker,
            })
        end
        AddAdvancedToggle(pandemicRow, "rbCabPandemicMarker_" .. tostring(sectionKey), infoButtons,
            true, {
                title = "Pandemic Marker Advanced",
                build = BuildCustomBarPandemicMarkerAdvanced,
                -- Non-lens lazy spec (ST._ResolveAdvancedUnlock): the
                -- resourceBars refresh kind is the same apply-then-rebuild
                -- pair RefreshCustomBarAuraConfig runs.
                unlock = pandemicValue ~= true and {
                    target = cab,
                    refreshKind = "resourceBars",
                    enable = {
                        label = "Enable Pandemic Marker",
                        apply = function(write)
                            -- Mirrors the checkbox: the stored key stays nil
                            -- when on IS this bar's default.
                            if pandemicDefault == true then
                                write.pandemicMarker = nil
                            else
                                write.pandemicMarker = true
                            end
                        end,
                    },
                } or nil,
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
        setting = CUSTOM_BAR_FINDER.aura.pandemicColor,
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
        {"While the bar shows stacks, its filled stack run or filled segments wear this color; gaps, borders, and stack geometry stay unchanged.", 1, 1, 1, true},
    }, infoButtons))
    ST._AddAdvancedToggle(effectRow, "rbCabPandemicColor_" .. tostring(sectionKey), {}, true, {
        unlock = cab.pandemicEffect ~= true and { target = cab, refreshKind = "resourceBars", enable = { label = "Enable Pandemic Color", key = "pandemicEffect" } } or nil,
        build = function(panel)
            -- No alpha: the pandemic color REPLACES the aura fill color (owner
            -- ruling), so the live clone renders it opaque.
            --
            -- "Fill Color", not "Pandemic Color": the marker gear a few rows up
            -- opens its own "Marker Color", and the two drive different visuals.
            AddColorRow(panel, {
                label = "Fill Color",
                setting = CUSTOM_BAR_FINDER.aura.fillColor,
                indent = false,
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
        end,
    })

    -- Group/pet-tracked aura bars cannot join the collapsing aura block
    -- (owner ruling 2026-08-26: they always keep their slot), so the Hide
    -- choice greys out rather than lying. The stored key survives, and
    -- switching the scope back restores it. Spell bars shell in place, so
    -- their Hide stays live under every scope.
    local scopeExpanded = cab.auraTrackGroup == true or cab.auraTrackPet == true
    local shellDisabled = scopeExpanded and not isSpellBar
    -- The two inactive-state presentations, hide (hideWhenInactive) and dim
    -- (auraShellDim), are mutually exclusive, so they are one dropdown (panel
    -- parity: the While Aura Inactive row in ButtonConditions). Both keys are
    -- unchanged; the row derives one value and writes the pair back. Hide
    -- greys out under a group or pet scope rather than leaving the row.
    local inactiveValue = "show"
    if cab.hideWhenInactive == true then
        inactiveValue = "hide"
    elseif cab.auraShellDim == true then
        inactiveValue = "dim"
    end
    local inactiveRow = AddDropdownRow(auraRight, {
        setting = CUSTOM_BAR_FINDER.aura.inactiveState,
        list = { show = "Show", dim = "Dim", hide = "Hide" },
        order = { "show", "dim", "hide" },
        value = inactiveValue,
        onChange = function(value)
            cab.hideWhenInactive = value == "hide" or nil
            cab.auraShellDim = value == "dim" or nil
            if value == "hide" and isSpellBar then
                -- The hidden spell shell has no cooldown/zero-charge or
                -- recharge look. Disarm its canvas stand-in immediately;
                -- saved colors remain untouched and return with the shell.
                CooldownCompanion:SetCustomBarCooldownPreview(cab, nil)
            end
            -- Hiding moves an aura bar between the fixed stack and the
            -- collapsing block, so the stack's extent changes: this needs
            -- the same commit as a layout drop, not just a config refresh.
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RepositionCastBar()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    if shellDisabled then
        inactiveRow:SetItemDisabled("hide", true)
        -- A stored Hide survives the scope switch (it returns with the
        -- scope), but under this scope it is inert, so the row says so
        -- instead of presenting a greyed item as a live selection.
        if inactiveValue == "hide" then
            inactiveRow:SetText("Hide (unavailable)")
        end
    end
    local inactiveInfo = {
        "While Aura Inactive",
        {"What the bar does until its tracked aura is running. It returns to full strength while the aura is up.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Dim keeps the bar in its place at reduced strength.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
    }
    -- Only aura entries join the collapsing aura block
    -- (RB.IsAuraBlockEntry); a spell bar keeps its slot either way.
    if isSpellBar then
        inactiveInfo[#inactiveInfo + 1] = {"Hide keeps the bar's slot in the stack reserved.", 1, 1, 1, true}
    else
        inactiveInfo[#inactiveInfo + 1] = {"Hide takes the bar out of the stack. It returns at the far end of its side, in order with the other bars that do the same.", 1, 1, 1, true}
        inactiveInfo[#inactiveInfo + 1] = {" ", 1, 1, 1, true}
        inactiveInfo[#inactiveInfo + 1] = {"Your auras and the target's collapse in separate groups.", 1, 1, 1, true}
        inactiveInfo[#inactiveInfo + 1] = {" ", 1, 1, 1, true}
        inactiveInfo[#inactiveInfo + 1] = {"A group whose bars are all hidden still holds one bar gap of space. The game hides aura activity from addons, so that space cannot close.", 1, 1, 1, true}
        inactiveInfo[#inactiveInfo + 1] = {" ", 1, 1, 1, true}
        inactiveInfo[#inactiveInfo + 1] = {"Splitting your auras and the target's onto different sides avoids the extra gap.", 1, 1, 1, true}
    end
    if shellDisabled then
        inactiveInfo[#inactiveInfo + 1] = {" ", 1, 1, 1, true}
        inactiveInfo[#inactiveInfo + 1] = {"Hide is not available while tracking your group or your pet. Those bars keep their place in the stack.", 1, 1, 1, true}
    end
    AnchorRowBadge(inactiveRow, CreateInfoButton(inactiveRow.frame, inactiveRow.frame, "LEFT", "LEFT", 0, 0, inactiveInfo, infoButtons))
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
    local updatePlaceholder = ConfigureCustomBarAddInstructions(addBox, "Add a spell by name or ID…")

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
        -- The refresh rebuilds the Add field. Clear before it so a successful
        -- creation cannot restore the just-committed query into the new widget.
        addBox:SetText("")
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
-- Early returns in here (conflict gate, resource bars disabled, no bar
-- selected) land on the dispatch-level gear build pass's sweep
-- (RunAdvancedGearBuildPass, AdvancedSettingsPanel.lua), which closes this
-- pane's gear panels - the pandemic marker and the duration/stack text pair
-- - when their gear does not rebuild.
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
    local layoutSpecID = ResolveCustomBarLayoutSpecID(
        settings, cab, currentConfigSpecID)
    local layout = RB.GetSpecLayoutOrder and RB.GetSpecLayoutOrder(settings, layoutSpecID) or CooldownCompanion:GetSpecLayoutOrder()
    local thicknessField, thicknessLabel = GetResourceThicknessFieldConfig(settings, layout)
    local capabilities = RB.GetCustomBarConfigCapabilities(cab)
    local isSpellCustomBar = capabilities.isSpellBar

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
                        setting = thicknessField == "barWidth"
                            and CUSTOM_BAR_FINDER.size.width or CUSTOM_BAR_FINDER.size.height,
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
                local isAuraTracked = capabilities.auraTracked

                local _, colorsCollapsed = AddCustomBarSettingsHeading(container, "Colors", "colors", capturedKey)

                if not colorsCollapsed then
                -- The styling tabs' standing column rule, on this grid too:
                -- LEFT is everything the SPELL paints - the bar at rest, the
                -- cooldown fill, and the recharge fill drawn over it - and
                -- RIGHT is the aura fill. A bar that draws only one family
                -- fills the left column first and takes no captions.
                local colorsLeft, colorsRight = BeginRowGrid(container)

                -- Captions only where both families really draw, computed from
                -- the same gates the rows below carry: every spell row sits
                -- behind baseSpellShellConsumer on a spell bar, and the aura
                -- row behind auraTracked. A standalone aura bar (no spell
                -- shell) and a spell bar with no tracked aura each draw one
                -- family only, so they stay uncaptioned.
                if isSpellCustomBar and capabilities.baseSpellShellConsumer and isAuraTracked then
                    AddFamilyColumnCaptions(colorsLeft, colorsRight)
                end

                -- deferCommit is true on every picker here: the Layout & Order
                -- canvas re-reads these tables on every repaint, so a drag
                -- value may only exist in them while that repaint runs.
                --
                -- Standalone aura bars: the fill IS the aura, so the label
                -- says so — "Bar Color" stays the spell-cooldown verbiage.
                -- Same barColor key either way; label only.
                if not isSpellCustomBar or capabilities.baseSpellShellConsumer then
                    AddColorRow(colorsLeft, {
                        label = isSpellCustomBar and "Bar Color" or "Aura Bar Color",
                        setting = isSpellCustomBar
                            and CUSTOM_BAR_FINDER.colors.bar or CUSTOM_BAR_FINDER.colors.aura,
                        tbl = customBars[cabIdx],
                        key = "barColor",
                        default = {0.5, 0.5, 1},
                        onConfirm = cabApplyBars,
                        onChange = cabPreviewOnly,
                        deferCommit = true,
                    })
                end

                if isSpellCustomBar then
                    if capabilities.baseSpellShellConsumer and capabilities.cooldownConsumer then
                        AddColorRow(colorsLeft, {
                            label = "Bar Cooldown Color",
                            setting = CUSTOM_BAR_FINDER.colors.cooldown,
                            tbl = customBars[cabIdx],
                            key = "barCooldownColor",
                            default = {0.6, 0.13, 0.18, 1},
                            hasAlpha = true,
                            onConfirm = cabApplyBars,
                            onChange = cabPreviewOnly,
                            deferCommit = true,
                        })

                        if capabilities.hasCharges then
                            AddColorRow(colorsLeft, {
                                label = "Bar Recharging Color",
                                setting = CUSTOM_BAR_FINDER.colors.recharging,
                                tbl = customBars[cabIdx],
                                key = "barChargeColor",
                                default = {1.0, 0.82, 0.0, 1},
                                hasAlpha = true,
                                onConfirm = cabApplyBars,
                                onChange = cabPreviewOnly,
                                deferCommit = true,
                            })
                        end
                    end

                    if isAuraTracked then
                        -- The kit's aura-drain fill while the tracked aura
                        -- runs (pure aura bars use Bar Color — the fill IS
                        -- the bar there).
                        AddColorRow(capabilities.baseSpellShellConsumer and colorsRight or colorsLeft, {
                            label = "Aura Bar Color",
                            setting = CUSTOM_BAR_FINDER.colors.aura,
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
                -- A capability change can remove one of these rows while its
                -- advanced window remains in the same custom-bar context.
                -- Close that exact window before omitting its replacement
                -- gear, otherwise it keeps editing a setting now hidden here.
                if CS.CloseAdvancedSettingsPanel then
                    if not capabilities.durationConsumer then
                        CS.CloseAdvancedSettingsPanel({ settingKey = "rbCabDurationText_" .. capturedKey })
                    end
                    if not capabilities.countConsumer then
                        CS.CloseAdvancedSettingsPanel({ settingKey = "rbCabStackText_" .. capturedKey })
                    end
                end
                local textsCollapsed = true
                if capabilities.durationConsumer or capabilities.countConsumer then
                    local _
                    _, textsCollapsed = AddCustomBarSettingsHeading(container, "Texts", "texts", capturedKey)
                end

                if not textsCollapsed then
                    local showDurationControls = capabilities.durationConsumer
                    local showDuration = showDurationControls and cab.showDurationText == true
                    local durationLeft, durationRight
                    local lowTimeLeft, lowTimeRight
                    if showDurationControls then
                        AddSettingsSubheading(container, "Duration Text")
                        if isSpellCustomBar and isAuraTracked then
                            durationLeft, durationRight = BeginRowGrid(container)
                        else
                            durationLeft = BeginFullWidthRowGroup(container)
                            durationRight = durationLeft
                        end
                        if showDuration then
                            if isSpellCustomBar and isAuraTracked then
                                lowTimeLeft, lowTimeRight = BeginRowGrid(container)
                            else
                                lowTimeLeft = BeginFullWidthRowGroup(container)
                                lowTimeRight = lowTimeLeft
                            end
                        end
                    end

                    local otherLeft
                    if capabilities.countConsumer then
                        AddSettingsSubheading(container, "Other Text")
                        otherLeft = BeginFullWidthRowGroup(container)
                    end

                    local durationTextRow
                    if showDurationControls then
                        durationTextRow = AddCheckboxRow(durationLeft, {
                            label = "Show Duration Text",
                            setting = CUSTOM_BAR_FINDER.texts.duration,
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
                    local stackTextRow
                    if capabilities.countConsumer then
                        stackTextRow = AddCheckboxRow(otherLeft, {
                            label = stackTextLabel,
                            setting = isSpellCustomBar
                                and CUSTOM_BAR_FINDER.texts.count or CUSTOM_BAR_FINDER.texts.stacks,
                            value = stackVal == true,
                            onChange = function(val)
                                customBars[cabIdx].showStackText = val or nil
                                CooldownCompanion:ApplyResourceBars()
                                CooldownCompanion:RefreshConfigPanel()
                            end,
                        })
                    end

                    local showStack = capabilities.countConsumer and stackVal == true
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
                        if isSpellCustomBar then
                            AddDurationTextVisibilityRows(
                                panel, customBars[cabIdx], customBars[cabIdx],
                                "cooldown", nil, {
                                    indent = false,
                                    modeLabel = isAuraTracked and "Cooldown Visibility" or "Visible",
                                    sliderLabel = isAuraTracked
                                        and "Cooldown: Show During Last" or "Show During Last",
                                    infoButtons = CS.advancedSettingsInfoButtons,
                                    preview = cabPreviewOnly,
                                    settings = isAuraTracked and {
                                        mode = CUSTOM_BAR_FINDER.texts.cooldownVisibility,
                                        threshold = CUSTOM_BAR_FINDER.texts.cooldownLast,
                                    } or {
                                        mode = CUSTOM_BAR_FINDER.texts.spellVisibility,
                                        threshold = CUSTOM_BAR_FINDER.texts.spellLast,
                                    },
                                    rebuild = RefreshCustomBarAuraConfig,
                                })
                        end
                        if not isSpellCustomBar or isAuraTracked then
                            local auraHost = panel
                            AddDurationTextVisibilityRows(
                                auraHost, customBars[cabIdx], customBars[cabIdx],
                                "aura", nil, {
                                    indent = false,
                                    modeLabel = isSpellCustomBar and "Aura Visibility" or "Visible",
                                    sliderLabel = isSpellCustomBar
                                        and "Aura: Show During Last" or "Show During Last",
                                    infoButtons = CS.advancedSettingsInfoButtons,
                                    preview = cabPreviewOnly,
                                    settings = isSpellCustomBar and {
                                        mode = CUSTOM_BAR_FINDER.texts.auraVisibility,
                                        threshold = CUSTOM_BAR_FINDER.texts.auraLast,
                                    } or {
                                        mode = CUSTOM_BAR_FINDER.texts.auraOnlyVisibility,
                                        threshold = CUSTOM_BAR_FINDER.texts.auraOnlyLast,
                                    },
                                    rebuild = RefreshCustomBarAuraConfig,
                                })
                        end

                        AddDurationFormatDropdown(
                            panel, customBars[cabIdx], cabApplyBars, {
                                row = true,
                                setting = CUSTOM_BAR_FINDER.texts.format,
                                sharedHelp = isSpellCustomBar and isAuraTracked,
                                infoButtons = CS.advancedSettingsInfoButtons,
                            })

                        AddFontControls(panel, customBars[cabIdx], "durationText", {
                            size = DEFAULT_RESOURCE_TEXT_SIZE, sizeMin = 6, sizeMax = 24, sizeStep = 1,
                            font = DEFAULT_RESOURCE_TEXT_FONT, outline = DEFAULT_RESOURCE_TEXT_OUTLINE,
                        }, cabApplyBars, {
                            row = true,
                            previewRefresh = cabPreviewOnly,
                            settings = {
                                size = CUSTOM_BAR_FINDER.durationText.fontSize,
                                font = CUSTOM_BAR_FINDER.durationText.font,
                                outline = CUSTOM_BAR_FINDER.durationText.outline,
                            },
                        })

                        -- deferCommit stays true: the Layout & Order canvas
                        -- re-reads this table on every repaint, so a drag value
                        -- may only exist in it while that repaint runs.
                        AddColorRow(panel, {
                            label = "Duration Text Color",
                            setting = CUSTOM_BAR_FINDER.durationText.color,
                            tbl = customBars[cabIdx],
                            key = "durationTextFontColor",
                            default = DEFAULT_RESOURCE_TEXT_COLOR,
                            hasAlpha = true,
                            onConfirm = cabApplyBars,
                            onChange = cabPreviewOnly,
                            deferCommit = true,
                        })
                    end

                    if showDurationControls then
                        AddAdvancedToggle(durationTextRow, "rbCabDurationText_" .. capturedKey, rbCabTextAdvBtns, true, {
                            title = "Duration Text Advanced",
                            build = BuildDurationTextAdvanced,
                            unlock = not showDuration and {
                                target = customBars[cabIdx],
                                enable = TURNON_SHOW_DURATION_TEXT,
                                refreshKind = "resourceBars",
                            } or nil,
                        })
                    end

                    if showDuration then
                        if ST._AddDurationLowTimeRows then
                            ST._AddDurationLowTimeRows(
                                lowTimeLeft, customBars[cabIdx], cabApplyBars, {
                                    settings = CUSTOM_BAR_FINDER.lowTime,
                                    advancedKey = "rbCabLowTime_" .. GetCustomBarCollapseKey(customBars[cabIdx]),
                                    rightColumn = lowTimeRight,
                                    auraOnly = not isSpellCustomBar,
                                    auraToggle = isSpellCustomBar and isAuraTracked,
                                    infoButtons = infoButtons,
                                    preview = cabPreviewOnly,
                                    rebuild = RefreshCustomBarAuraConfig,
                                })
                        end
                    end

                    local function BuildStackTextAdvanced(panel)
                        if isAuraTracked then
                            ST._BuildStackThresholdColorRows(panel, customBars[cabIdx],
                                CooldownCompanion:GetAuraStackBarMax(BuildCustomBarAuraProbe(customBars[cabIdx]), true), {
                                    infoButtons = CS.advancedSettingsInfoButtons,
                                    settings = CUSTOM_BAR_FINDER.stackFormatting,
                                    refresh = RefreshCustomBarAuraConfig,
                                    commit = cabApplyBars,
                                    previewRefresh = cabPreviewOnly,
                                })
                        end

                        AddFontControls(panel, customBars[cabIdx], "stackText", {
                            size = DEFAULT_RESOURCE_TEXT_SIZE, sizeMin = 6, sizeMax = 24, sizeStep = 1,
                            font = DEFAULT_RESOURCE_TEXT_FONT, outline = DEFAULT_RESOURCE_TEXT_OUTLINE,
                        }, cabApplyBars, {
                            row = true,
                            previewRefresh = cabPreviewOnly,
                            settings = {
                                size = CUSTOM_BAR_FINDER.stackText.fontSize,
                                font = CUSTOM_BAR_FINDER.stackText.font,
                                outline = CUSTOM_BAR_FINDER.stackText.outline,
                            },
                        })

                        -- deferCommit stays true, for the same reason as the
                        -- duration text color above.
                        AddColorRow(panel, {
                            label = "Stack Text Color",
                            setting = CUSTOM_BAR_FINDER.stackText.color,
                            tbl = customBars[cabIdx],
                            key = "stackTextFontColor",
                            default = DEFAULT_RESOURCE_TEXT_COLOR,
                            hasAlpha = true,
                            onConfirm = cabApplyBars,
                            onChange = cabPreviewOnly,
                            deferCommit = true,
                        })
                    end

                    if capabilities.countConsumer then
                        AddAdvancedToggle(stackTextRow, "rbCabStackText_" .. capturedKey, rbCabTextAdvBtns, true, {
                            title = stackTextLabel .. " Advanced",
                            build = BuildStackTextAdvanced,
                            unlock = not showStack and {
                                target = customBars[cabIdx],
                                enable = { label = isSpellCustomBar and "Enable Count Text (Charges/Uses)" or "Enable Stack Text", key = "showStackText" },
                                refreshKind = "resourceBars",
                            } or nil,
                        })
                    end
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
                -- overview groups the border and fill effect choices into two
                -- columns. Each choice owns its tuning editor. Inside a panel's
                -- existing editor, singleRail keeps their conditional controls
                -- together without another disclosure level.
                local isAuraTracked = capabilities.auraTracked
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
                            settings = CUSTOM_BAR_FINDER.effects,
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
            BuildCustomBarLoadConditionsTab(container, cab, infoButtons, capabilities)

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
