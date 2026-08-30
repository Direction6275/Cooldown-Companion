local ADDON_NAME, ST = ...
-- Core/Defaults.lua. "Can this PANEL ever use this override section?" - false
-- only on an Aura Panel, for the sections that read spell cooldown, castability,
-- proc, charge, cast or GCD state its pure-aura entries do not have.
local CanGroupUseOverrideSection = ST.CanGroupUseOverrideSection
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local BuildCompactModeControls = ST._BuildCompactModeControls
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders
local AddBorderRenderModeDropdown = ST._AddBorderRenderModeDropdown
local ResolveLensSection = ST._ResolveLensSection
local BeginLensSection = ST._BeginLensSection
local ResolveLensCollapseKey = ST._ResolveLensCollapseKey
local AddLensPanelScopeNote = ST._AddLensPanelScopeNote
local ChainHeadingBadges = ST._ChainHeadingBadges

-- Imports from SectionBuilders.lua
local BuildKeybindTextControls = ST._BuildKeybindTextControls
local BuildBorderControls = ST._BuildBorderControls
local BuildIconTintControls = ST._BuildIconTintControls
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown
local AddDurationTextVisibilityRows = ST._AddDurationTextVisibilityRows
local AddSettingsSubheading = ST._AddSettingsSubheading
local BeginFullWidthRowGroup = ST._BeginFullWidthRowGroup

-- Imports from RowWidgets.lua (the row grammar)
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddColorRow = ST._AddColorRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid

-- Imports from GroupTabsShared.lua
local WireMirrorFirstSlider = ST._WireMirrorFirstSlider
local RefreshActiveAdvancedSettingsPanel = ST._RefreshActiveAdvancedSettingsPanel
local MakeCooldownTextAdvancedDescriptor = ST._MakeCooldownTextAdvancedDescriptor

-- Imports from GroupTabsSpecial.lua
local AddTriggerDisplayTypeDropdown = ST._AddTriggerDisplayTypeDropdown
local BuildTriggerIconAppearanceTab = ST._BuildTriggerIconAppearanceTab
local BuildTriggerTextAppearanceTab = ST._BuildTriggerTextAppearanceTab
local BuildTexturePanelAppearanceTab = ST._BuildTexturePanelAppearanceTab

-- Imports from GroupTabsEffects.lua
local EFFECTS_GLOWS_SECTION = ST._EFFECTS_GLOWS_SECTION
local EFFECTS_PANDEMIC_SECTION = ST._EFFECTS_PANDEMIC_SECTION
local EFFECTS_TIMERS_SECTION = ST._EFFECTS_TIMERS_SECTION
local EFFECTS_STATES_SECTION = ST._EFFECTS_STATES_SECTION

-- Imports from BarModeTabs.lua
local BuildBarAppearanceTab = ST._BuildBarAppearanceTab

-- Imports from TextModeTabs.lua
local BuildTextAppearanceTab = ST._BuildTextAppearanceTab

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements
local KEYBIND_CUSTOM_LABEL = "Show Keybind/Custom Text"
local KEYBIND_CUSTOM_TOOLTIP = {
    "Show Keybind/Custom Text",
    {"Shows detected keybind text on icon buttons by default.", 1, 1, 1, true},
    " ",
    {"When enabled for a button, that button's settings can also provide custom text to replace the detected bind until cleared.", 1, 1, 1, true},
}

-- The per-section aura toggle's tooltip. What the section becomes, and what
-- that changes about the way it takes up room; the rest the surface teaches.
local AURA_SECTION_TOOLTIP = {
    "Aura Only Section",
    {"Only Aura entries can live here.", 1, 1, 1, true},
    " ",
    {"Active auras appear and pack together. Inactive auras take no space.", 1, 1, 1, true},
    " ",
    {"Buffs on you and debuffs on your target can't share one section.", 1, 1, 1, true},
}

-- The While Aura Active Cooldown control. Its two style keys used to live elsewhere
-- (an entry-data checkbox on the entry's Aura Tracking section; a "Separate
-- Text Positions" checkbox inside the Aura Duration Text advanced panel) and
-- then were two checkboxes here - but "keep the swipe" contains "keep the
-- text" (owner ruling), so two toggles modeled four states where only three
-- exist. One dropdown states the ladder directly; both storage keys stay
-- (whileAuraActive section, Defaults.lua), written as normalized combinations
-- so the redundant state is unrepresentable from the UI. The tooltip also
-- covers the section's other two rows (Show Aura Icon, Desaturate Icon), which
-- share the one info button rather than growing a badge each.
local WHILE_AURA_ACTIVE_TOOLTIP = {
    "Cooldown While Aura Active",
    {"Hidden by Aura: the aura duration swipe and text take over the icon.", 1, 1, 1, true},
    " ",
    {"Show Text: the cooldown countdown and charge count draw above the aura display. The aura duration text moves to its own position.", 1, 1, 1, true},
    " ",
    {"Show Swipe and Text: the icon and cooldown swipe stay, replacing the aura duration swipe. All texts show.", 1, 1, 1, true},
    " ",
    {"Stack text and glows always follow their own settings.", 1, 1, 1, true},
    " ",
    {"With Show Aura Icon on, the aura icon covers the swipe unless Layer Order raises Cooldown Swipe above it. The icon keeps its own tint.", 1, 1, 1, true},
    " ",
    {"Show Aura Icon swaps the live aura's own icon in while it runs. Standalone and passive entries always do this.", 1, 1, 1, true},
    " ",
    {"Desaturate Icon grays the aura display. Passives gray while the aura is missing by default, so this inverts them.", 1, 1, 1, true},
    " ",
    {"Cooldown applies to icon panels only.", 1, 1, 1, true},
}

local WHILE_AURA_ACTIVE_LIST = {
    hidden = "Hidden by Aura",
    text = "Show Text",
    swipeText = "Show Swipe and Text",
}
local WHILE_AURA_ACTIVE_ORDER = { "hidden", "text", "swipeText" }

-- The section's read rule, stated once because two places need it: the Text
-- section reads it to gate the aura duration text's position rows, and the
-- While Aura Active section below reads it for its own rows.
--
-- .write first, .read only as the read-only fallback. .write is the LIVE store
-- (the panel style, or this entry's override table wearing the runtime __index
-- onto the panel), so the aura text advanced panel reads the current flag
-- immediately after RefreshActiveAdvancedSettingsPanel rebuilds just that
-- panel. lens.effective behind .read is a DETACHED snapshot and would go stale
-- on that partial rebuild, so it serves only the inherited/denied case where
-- there is nothing to write anyway.
local function WhileAuraFlagOn(sec, key)
    local src = sec.write or sec.read
    return (src and src[key]) == true
end

-- Owner ruling (aura rebuild plan): group-level aura style sections are shown
-- only while the group actually has an aura-tracking entry. Shared helper
-- (Helpers.lua) so BarModeTabs can gate its aura section too.
local GroupHasAuraTrackingEntry = ST._GroupHasAuraTrackingEntry

-- The icons Appearance tab's advanced gears, by the OVERRIDE SECTION each one
-- belongs to. Shaped and named after ST._INDICATORS_SECTION_BY_ADVANCED_KEY
-- above, with one deliberate difference: that map answers "which COLLAPSE
-- section is this gear inside", this one answers "which OVERRIDE section owns
-- this gear's values". Keep them apart - they are read for different reasons.
--
-- The style lens reads it at the foot of BOTH icons builders: a section the
-- selected entry only INHERITS builds no gear at all, so nothing rebinds or
-- closes an advanced panel that was already open on it, and that panel's
-- controls still point at the table the previous build handed them. The sweeps
-- close those, each over this map AND the indicators map above.
--
-- A gear added to one of these five sections belongs here the same day. The
-- tab's other lens sections (Border, Icon Tint, Icon Zoom) carry no gear at
-- all, and Compact Mode's gear is not listed because compact mode is group
-- data with no override section - see the note at its call site.
ST._APPEARANCE_SECTION_BY_ADVANCED_KEY = {
    cooldownText = "cooldownText",
    chargeText = "chargeText",
    auraText = "auraText",
    auraStackText = "auraStackText",
    keybindText = "keybindText",
}

-- The one gate the icons tabs draw whole aura sections behind, named once
-- because it covers five sections below. The Indicators-tab gate sites are
-- cited on the sections that carry it.
local function IconsGroupTracksAura(group)
    return GroupHasAuraTrackingEntry(group)
end

-- The Cooldown Text ROW is left out on an Aura Panel (BuildAppearanceTab's
-- `if not isAuraPanel`): nothing there has a cooldown, so the toggle is dead and
-- its two live children move under the aura duration text. The section itself
-- stays usable - those children still read and write its keys - so this is an
-- `available` predicate rather than a denial in
-- ST.AURA_PANEL_DENIED_OVERRIDE_SECTIONS. Without it the Customizations index
-- would offer a name link onto a row that is no longer drawn.
local function GroupDrawsCooldownTextRow(group)
    return not ST.IsAuraPanelGroup(group)
end

-- Low Time Threshold is drawn once beside a duration surface that can consume
-- it: cooldown-side when effective cooldown text is visible, otherwise
-- aura-side while the group tracks an aura and effective aura text is visible.
local function IconsDrawCooldownDurationLowTimeRows(group, style)
    return not ST.IsAuraPanelGroup(group)
        and style and style.showCooldownText == true
end

local function IconsDrawAuraDurationLowTimeRows(group, style)
    return IconsGroupTracksAura(group)
        and style and style.showAuraText ~= false
end

local function IconsDrawDurationLowTimeRows(group, style)
    return IconsDrawCooldownDurationLowTimeRows(group, style)
        or IconsDrawAuraDurationLowTimeRows(group, style)
end

-- The fill timer's own interlock, exactly as BuildEffectsTab derives it
-- (`fillSec.read.iconFillEnabled == true and group.masqueEnabled ~= true`):
-- Masque is GROUP data with no override section, so that half stays
-- group-level. It gates two gears, so it is named rather than copied twice.
local function IconsFillTimerActive(group, style)
    return style.iconFillEnabled == true and group.masqueEnabled ~= true
end

-- Where each override section is EDITED, now that the panel tabs are the lens
-- onto a selected entry: the tab that draws it and the collapse key of the
-- section it is drawn in.
--
-- Keyed by DISPLAY MODE first. The same section id is drawn in different
-- places depending on the mode - borderSettings sits under "Border" on the
-- icons Appearance tab and somewhere else entirely on a bar panel - so a flat
-- map could only ever describe one mode. Later packets add the `bars` and
-- `text` axes beside this one; a lookup that misses its mode has no home yet
-- rather than the wrong one.
--
-- The optional `available` / `gearEnabled` predicates are contracted at the
-- FIRST registration (ST._SECTION_HOME.bars, BarModeTabs.lua) - read that note
-- before adding one. In short: they mirror the builder's own gate, the builder
-- stays the authority, and a missing predicate means "always".
--
-- The Indicators-tab rows below carry predicates for gates GroupTabsEffects.lua
-- owns, for the same reason their collapse keys are imported from that file
-- rather than written as literals: this axis is ONE table, and the icons homes
-- for both tabs have always been stated here together. Each cites its gate.
ST._SECTION_HOME = ST._SECTION_HOME or {}
ST._SECTION_HOME.icons = {
    cooldownText = {
        tab = "appearance", collapseKey = "appearance_text",
        available = GroupDrawsCooldownTextRow,
        gearEnabled = function(_, style) return (style.showCooldownText) ~= false end,
    },
    durationLowTime = {
        tab = "appearance", collapseKey = "appearance_text",
        available = IconsDrawDurationLowTimeRows,
    },
    chargeText = {
        tab = "appearance", collapseKey = "appearance_text",
        gearEnabled = function(_, style) return (style.showChargeText ~= false) ~= false end,
    },
    -- The aura text sections are drawn only while the GROUP tracks an aura
    -- (BuildAppearanceTab's `if groupHasAuraEntry then`).
    auraText = {
        tab = "appearance", collapseKey = "appearance_text",
        available = IconsGroupTracksAura,
        gearEnabled = function(_, style) return (style.showAuraText ~= false) ~= false end,
    },
    -- While Aura Active is its own collapsible, right after Text: it names a
    -- STATE, not a kind of text (owner ruling 2026-08-16). One gate, mirrored
    -- from the builder: the group must track an aura. Aura Panels keep the
    -- section (the Desaturate row applies there); the builder hides the dead
    -- rows itself. No gearEnabled: the section owns no advanced panel.
    whileAuraActive = {
        tab = "appearance", collapseKey = "appearance_whileAuraActive",
        available = IconsGroupTracksAura,
    },
    auraStackText = {
        tab = "appearance", collapseKey = "appearance_text",
        available = IconsGroupTracksAura,
        gearEnabled = function(_, style) return (style.showAuraStackText ~= false) ~= false end,
    },
    keybindText = {
        tab = "appearance", collapseKey = "appearance_text",
        gearEnabled = function(_, style) return (style.showKeybindText) ~= false end,
    },
    borderSettings = { tab = "appearance", collapseKey = "appearance_border" },
    iconTint = { tab = "appearance", collapseKey = "appearance_iconTint" },
    -- Icon Zoom is one row inside the panel's own Icon Settings section, which
    -- is where its collapse key comes from.
    iconZoom = { tab = "appearance", collapseKey = "appearance_icons" },
    -- Indicators tab. The collapse keys come from the section constants
    -- imported from GroupTabsEffects.lua, never from literals: the bar tab
    -- shares those same constants, and a copy could drift from them.
    procGlow = {
        tab = "effects", collapseKey = EFFECTS_GLOWS_SECTION,
        gearEnabled = function(_, style) return (style.procGlowStyle ~= "none") ~= false end,
    },
    -- BuildAuraGlowSection returns early without an aura-tracking entry.
    auraIndicator = {
        tab = "effects", collapseKey = EFFECTS_GLOWS_SECTION,
        available = IconsGroupTracksAura,
        gearEnabled = function(_, style) return ((style.auraGlowStyle or "pulse") ~= "none") ~= false end,
    },
    readyGlow = {
        tab = "effects", collapseKey = EFFECTS_GLOWS_SECTION,
        gearEnabled = function(_, style)
            return (style.readyGlowStyle and style.readyGlowStyle ~= "none") ~= false
        end,
    },
    keyPressHighlight = {
        tab = "effects", collapseKey = EFFECTS_GLOWS_SECTION,
        gearEnabled = function(_, style)
            return (style.keyPressHighlightStyle and style.keyPressHighlightStyle ~= "none") ~= false
        end,
    },
    assistedHighlight = {
        tab = "effects", collapseKey = EFFECTS_GLOWS_SECTION,
        gearEnabled = function(_, style) return (style.showAssistedHighlight or false) ~= false end,
    },
    -- Both halves of the refresh window live in one section, so the feature has
    -- one home whichever half a consumer was looking for. The whole Pandemic
    -- heading is gated on an aura-tracking entry (BuildEffectsTab), and both
    -- halves return early without one.
    --
    -- No gearEnabled: this section owns TWO gears in icons mode (pandemicGlow
    -- and pandemicMarker), so the Customizations list resolves none for it.
    pandemic = {
        tab = "effects", collapseKey = EFFECTS_PANDEMIC_SECTION,
        available = IconsGroupTracksAura,
    },
    iconFillTimer = {
        tab = "effects", collapseKey = EFFECTS_TIMERS_SECTION,
        gearEnabled = function(group, style) return IconsFillTimerActive(group, style) ~= false end,
    },
    cooldownSwipe = {
        tab = "effects", collapseKey = EFFECTS_TIMERS_SECTION,
        gearEnabled = function(group, style)
            return (style.showCooldownSwipe ~= false and not IconsFillTimerActive(group, style)) ~= false
        end,
    },
    -- The aura duration swipe is drawn only while the GROUP tracks an aura.
    auraDurationSwipe = {
        tab = "effects", collapseKey = EFFECTS_TIMERS_SECTION,
        available = IconsGroupTracksAura,
        gearEnabled = function(_, style) return (style.showAuraDurationSwipe ~= false) ~= false end,
    },
    showGCDSwipe = { tab = "effects", collapseKey = EFFECTS_TIMERS_SECTION },
    desaturation = { tab = "effects", collapseKey = EFFECTS_STATES_SECTION },
    -- Its own section (owner ruling 2026-08-16); drawn only while the group
    -- tracks an aura, same gate as the row.
    auraMissingDesaturation = {
        tab = "effects", collapseKey = EFFECTS_STATES_SECTION,
        available = IconsGroupTracksAura,
    },
    unusableDimming = {
        tab = "effects", collapseKey = EFFECTS_STATES_SECTION,
        gearEnabled = function(_, style) return (style.showUnusable == true) ~= false end,
    },
    showOutOfRange = { tab = "effects", collapseKey = EFFECTS_STATES_SECTION },
    lossOfControl = { tab = "effects", collapseKey = EFFECTS_STATES_SECTION },
    showTooltips = {
        tab = "effects", collapseKey = EFFECTS_STATES_SECTION,
        gearEnabled = function(_, style) return (style.showTooltips == true) ~= false end,
    },
}

local function BuildAppearanceTab(container)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end

    -- Clean up elements from previous build
    for _, elem in ipairs(appearanceTabElements) do
        elem:ClearAllPoints()
        elem:Hide()
        elem:SetParent(nil)
    end
    wipe(appearanceTabElements)

    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
    local style = group.style

    CooldownCompanion:ClearAllTextureIndicatorPreviews()
    if CooldownCompanion.ClearAllTriggerPanelEffectPreviews then
        CooldownCompanion:ClearAllTriggerPanelEffectPreviews()
    end

    if group.displayMode == "trigger" then
        AddTriggerDisplayTypeDropdown(container, group)
        local displayType = CooldownCompanion:GetTriggerPanelDisplayType(group, true)
        if displayType == "icon" then
            BuildTriggerIconAppearanceTab(container, group)
            return
        elseif displayType == "text" then
            BuildTriggerTextAppearanceTab(container, group)
            return
        end
    end

    if group.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
        -- Row grammar. A rotation assistant panel shows one recommendation at
        -- a time, so its whole Appearance tab is a single section.
        local _, assistantCollapsed = BuildCollapsibleSection(container, "Assistant Panel",
            "appearance_assistant", nil, nil, ROW_SECTION)

        if not assistantCollapsed then
        -- LEFT column: how the one icon is shaped and sized, then the keybind
        -- text drawn on it and what that text is drawn WITH.
        -- RIGHT column: the border around it, then where the keybind text
        -- lands and what colour it takes.
        local assistLeft, assistRight = BeginRowGrid(container)

        AddCheckboxRow(assistLeft, {
            label = "Square Icons",
            value = style.maintainAspectRatio ~= false,
            onChange = function(value)
                style.maintainAspectRatio = value ~= false
                style.buttonsPerRow = 1
                if not style.maintainAspectRatio then
                    local size = style.buttonSize or ST.BUTTON_SIZE
                    style.iconWidth = style.iconWidth or size
                    style.iconHeight = style.iconHeight or size
                end
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if style.maintainAspectRatio ~= false then
            local sizeRow = AddSliderRow(assistLeft, {
                label = "Button Size",
                min = 10, max = 150, step = 0.1,
                value = style.buttonSize or ST.BUTTON_SIZE,
            })
            WireMirrorFirstSlider(sizeRow, function(value)
                style.buttonSize = value
                style.buttonsPerRow = 1
            end, nil, nil, style, { "buttonSize", "buttonsPerRow" })
        else
            local widthRow = AddSliderRow(assistLeft, {
                label = "Icon Width",
                min = 10, max = 150, step = 0.1,
                value = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE,
            })
            WireMirrorFirstSlider(widthRow, function(value)
                style.iconWidth = value
                style.buttonsPerRow = 1
            end, nil, nil, style, { "iconWidth", "buttonsPerRow" })

            local heightRow = AddSliderRow(assistLeft, {
                label = "Icon Height",
                min = 10, max = 150, step = 0.1,
                value = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE,
            })
            WireMirrorFirstSlider(heightRow, function(value)
                style.iconHeight = value
                style.buttonsPerRow = 1
            end, nil, nil, style, { "iconHeight", "buttonsPerRow" })
        end

        ST._BuildIconZoomControls(assistLeft, style, refreshStyle, {
            previewRefresh = function()
                if ST._RefreshButtonsPreviewMirror then
                    ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
                end
            end,
        })

        -- The border builder has no second-column split of its own, so its
        -- whole block heads the right column.
        BuildBorderControls(assistRight, style, refreshStyle, { row = true })

        BuildKeybindTextControls(assistLeft, style, refreshStyle, {
            row = true,
            rightColumn = assistRight,
            label = "Show Keybind Text",
            tooltip = {
                "Show Keybind Text",
                {"Shows detected keybind text for the current recommendation.", 1, 1, 1, true},
            },
        })
        end -- not assistantCollapsed
        return
    end

    if group.displayMode == "textures" or group.displayMode == "trigger" then
        BuildTexturePanelAppearanceTab(container, group)
        return
    end

    -- Branch for text mode
    if group.displayMode == "text" then
        BuildTextAppearanceTab(container, group, style)
        return
    end

    -- Branch for bar mode
    if group.displayMode == "bars" then
        BuildBarAppearanceTab(container, group, style)
        return
    end

    -- ================================================================
    -- Row grammar (RowWidgets.lua): every setting below is a fixed-height row
    -- - label left, control right-aligned in a 140px control column,
    -- gear/info/scope badges chained off the end of the label. Rows sit in
    -- curated two-column grids from BeginRowGrid, each section splitting its
    -- rows along whatever line reads naturally for that section. Sections with
    -- too little to split keep the left column only.
    --
    -- Standing ruling (owner, 2026-07-27) - the two rules every row-grammar
    -- section on every tab follows:
    --
    -- 1. Split the rows so the columns run as even as the semantics allow.
    --    Meaning still wins where the two disagree: rows that must stay
    --    adjacent (one disables the next) stay adjacent, and a gated row can
    --    leave its column short, because the grid top-aligns its columns and
    --    a short side just ends early.
    -- 2. Every section is collapsible (BuildCollapsibleSection with a
    --    ROW_SECTION header). A collapsed section builds none of its rows, so
    --    any gear inside one needs queue-safe uncollapse wiring: whatever
    --    queues an advanced-panel open for that gear must clear the section's
    --    collapse key first, or the queued key expires against a gear that
    --    never built. The Indicators tab does this with a gear-to-section map
    --    (ST._INDICATORS_SECTION_BY_ADVANCED_KEY) read by the preview command
    --    center; bar mode's text section names its key on the route itself
    --    (`uncollapse`). Either shape is fine; having neither is not.
    -- 3. When a section's row set comes out of a FILTER - event families, a
    --    gate, anything that can delete whole groups of rows before they are
    --    assigned - fill the LEFT column first. A populated right column
    --    beside an empty left one is never acceptable. A semantic split that
    --    survives the filter intact still wins (both halves populated), but
    --    the moment the filter leaves only one of them the survivors split
    --    themselves across the columns left-first, ceil(n/2) left. The
    --    custom-bar Sound Alerts tab is the worked example: it splits
    --    cooldown-family left / aura-family right when a bar has both, and an
    --    aura-only bar's three dropdowns 2/1 instead of 0/3.
    --
    -- Section headers are left-aligned (ROW_SECTION) and own the vertical air
    -- BEFORE their section, so sections never butt together and nothing here
    -- adds spacers of its own.
    --
    -- Section-level action buttons ("Reset Colors to Default") are compact
    -- and flush left: SetAutoWidth(true),
    -- never SetFullWidth. A page-wide button is louder than every setting it
    -- sits under, and both List and Flow anchor their children from the left,
    -- so no alignment wrapper is needed. They go INSIDE the grid, filling the
    -- shorter column's empty tail, rather than below it - a lopsided section
    -- with a lone button hanging off the bottom reads as unfinished.
    -- ================================================================
    local groupHasAuraEntry = GroupHasAuraTrackingEntry(group)
    -- An Aura Panel draws no cooldown text (nothing on it has a cooldown), so
    -- the Text section drops that toggle. Duration Format remains a shared row
    -- in the duration options, while the shared-position keys move under the aura
    -- duration text they actually drive (owner ruling 2026-08-15).
    local isAuraPanel = ST.IsAuraPanelGroup(group)

    -- STYLE LENS (Helpers.lua). With an entry selected these sections stop
    -- being the panel's settings and become a view of that entry's EFFECTIVE
    -- ones, with per-section scope deciding where - or whether - they write.
    -- Resolved ONCE here and handed to every section below, so one tab cannot
    -- disagree with itself about which entry it is showing.
    local lens = ST._ResolveStyleLens(group)

    -- Under a multi selection these tabs edit the PANEL, and only this line
    -- says so - the per-section scope chrome speaks under an entry lens alone.
    -- No-op in every other lens mode. The trigger, texture, assistant and
    -- other-mode paths returned above, so only the standard icons path carries
    -- it; the modes with their own builders add their own.
    AddLensPanelScopeNote(container, lens)

    -- Sections with NO override identity of their own (the panel's layout, its
    -- Masque skinning): an entry cannot own them, so under an entry lens they
    -- say "Applies to all entries" and go read-only rather than quietly letting
    -- a panel-wide edit be made from an entry's page. They begin a lens section
    -- with a nil sectionId, which resolves to no write table exactly under an
    -- entry lens.

    -- ================================================================
    -- Icon Settings (shape, size, spacing, packing)
    -- ================================================================
    -- Panel-only under an entry lens, so the collapse key is lens-scoped and
    -- opens folded the first time (ST._ResolveLensCollapseKey owns that rule).
    -- Icon Zoom lives INSIDE this section, so an entry that customized it
    -- keeps the section open (the hostsSections exception).
    local iconHeading, iconSettingsCollapsed = BuildCollapsibleSection(container, "Icon Settings",
        ResolveLensCollapseKey(lens, group, nil, "appearance_icons", { hostsSections = { "iconZoom" } }), nil, nil, ROW_SECTION)
    -- Panel-only (sectionId nil): shape, size and packing belong to the panel.
    -- Icon Zoom is the one exception inside this section - it IS an override
    -- section, so it resolves its own scope further down.
    local iconSec = BeginLensSection(lens, group, nil)
    iconSec:HeadingChrome(iconHeading)

    if not iconSettingsCollapsed then
    -- LEFT column: how a single icon is shaped and sized.
    -- RIGHT column: how the icons sit together as a group.
    local iconLeft, iconRight = BeginRowGrid(container)

    -- The columns only exist here, so the section's primary bracket is taken
    -- now rather than at Begin.
    iconSec:Mark(iconLeft)

    local squareRow = AddCheckboxRow(iconLeft, {
        label = "Square Icons",
        value = style.maintainAspectRatio or false,
        disabled = iconSec.disabled or group.masqueEnabled == true,
        onChange = function(val)
            style.maintainAspectRatio = val
            if not val then
                local size = style.buttonSize or ST.BUTTON_SIZE
                style.iconWidth = style.iconWidth or size
                style.iconHeight = style.iconHeight or size
            end
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- The note belongs to the label, so it hangs off badgeAnchor like a badge
    -- would. Label + note runs ~230px inside a ~360px cell, so it can reach a
    -- little past the control column's left edge - harmless here because the
    -- control is a 24px checkbox pinned to the cell's far right. Do not copy
    -- this onto a slider row, whose track starts at that same edge.
    if group.masqueEnabled then
        local masqueLabel = squareRow.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        masqueLabel:SetPoint("LEFT", squareRow.badgeAnchor, "RIGHT", 8, 0)
        masqueLabel:SetText("|cff00ff00(Masque skinning is active)|r")
        table.insert(appearanceTabElements, masqueLabel)
    end

    -- Size sliders — always visible
    if style.maintainAspectRatio then
        local sizeRow = AddSliderRow(iconLeft, {
            label = "Button Size",
            min = 10, max = 150, step = 0.1,
            value = style.buttonSize or ST.BUTTON_SIZE,
            disabled = iconSec.disabled,
        })
        WireMirrorFirstSlider(sizeRow, function(val)
            style.buttonSize = val
        end, nil, nil, style, "buttonSize")
    else
        local wRow = AddSliderRow(iconLeft, {
            label = "Icon Width",
            min = 10, max = 150, step = 0.1,
            value = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE,
            disabled = iconSec.disabled,
        })
        WireMirrorFirstSlider(wRow, function(val)
            style.iconWidth = val
        end, nil, nil, style, "iconWidth")

        local hRow = AddSliderRow(iconLeft, {
            label = "Icon Height",
            min = 10, max = 150, step = 0.1,
            value = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE,
            disabled = iconSec.disabled,
        })
        WireMirrorFirstSlider(hRow, function(val)
            style.iconHeight = val
        end, nil, nil, style, "iconHeight")
    end

    -- Closed BEFORE the zoom row goes in. An inert range covers the children
    -- already in the column, and Icon Zoom is not one of the panel's own
    -- settings: it is an override section that follows the lens like any other.
    iconSec:Finish()

    -- Icon Zoom - an override section living inside a panel-only one. The
    -- shared builder reads and writes one table, so it is handed the section's
    -- WRITE table where there is one and the lens' detached snapshot where
    -- there is not (an inert row is disabled, and a write into the snapshot
    -- would go nowhere anyway).
    local zoomSec = BeginLensSection(lens, group, "iconZoom", { column = iconLeft })

    local zoomRow = ST._BuildIconZoomControls(iconLeft, zoomSec.tbl, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end, {
        disabled = group.masqueEnabled == true or zoomSec.disabled,
        previewRefresh = function()
            if ST._RefreshButtonsPreviewMirror then
                ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
            end
        end,
    })
    zoomSec:Chrome(zoomRow)

    zoomSec:Finish()

    -- The right column is the same panel-only section, so it takes a second,
    -- independent bracket of its own.
    local iconRightBracket = iconSec:Bracket(iconRight)

    if group.buttons and #group.buttons > 1 then
        local spacingRow = AddSliderRow(iconRight, {
            label = "Button Spacing",
            min = 0, max = 30, step = 0.1,
            value = style.buttonSpacing or ST.BUTTON_SPACING,
            disabled = iconSec.disabled,
        })
        WireMirrorFirstSlider(spacingRow, function(val)
            style.buttonSpacing = val
        end, nil, nil, style, "buttonSpacing")
    end

    -- Compact Mode toggle + advanced (growth direction, max visible buttons).
    -- Its gear is not skipped under an entry lens the way the Text sections'
    -- are: compact mode is group data with no override section, so there is no
    -- second table to bind it to. The inert walk disables and dims it instead,
    -- and an advanced panel left open from before the selection closes itself
    -- on the next refresh (its descriptor context carries selectedButton).
    BuildCompactModeControls(iconRight, group, tabInfoButtons)

    iconSec:FinishBracket(iconRightBracket)
    end -- not iconSettingsCollapsed

    -- ================================================================
    -- Panel Sections (per-cluster icon size and spacing)
    -- ================================================================
    -- One quiet block per placed cluster, right under the panel's own icon
    -- sizing because that is where size and spacing live everywhere else in
    -- this addon; a section's placement (its X/Y offsets) stays in the Layout
    -- tab. Nothing here exists on a panel with no sections. Every displayed
    -- number is the RESOLVED one, so an untouched key reads as the panel's own
    -- value rather than a lie about zero; writing the slider is what sets the
    -- key, and inheritance ends there. Panel-only under an entry lens, same as
    -- Icon Settings above.
    local panelSections = ST.PanelSupportsSections(group) and group.sections or nil
    if type(panelSections) == "table" and next(panelSections) then
        local panelSpacing = style.buttonSpacing or ST.BUTTON_SPACING
        local sectionPanelW, sectionPanelH
        if style.maintainAspectRatio then
            sectionPanelW = style.buttonSize or ST.BUTTON_SIZE
            sectionPanelH = sectionPanelW
        else
            sectionPanelW = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
            sectionPanelH = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
        end

        -- Reading order, so the blocks sit in the order the anchors read on the
        -- panel rather than whatever order the profile happens to store them in.
        for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
            local section = panelSections[anchor]
            if type(section) == "table" then
                local sectionHeading, sectionCollapsed = BuildCollapsibleSection(container,
                    ST.PANEL_SECTION_ANCHOR_LABELS[anchor] .. " Section",
                    ResolveLensCollapseKey(lens, group, nil, "appearance_section_" .. anchor),
                    nil, nil, ROW_SECTION)
                local sectionSec = BeginLensSection(lens, group, nil)
                sectionSec:HeadingChrome(sectionHeading)

                if not sectionCollapsed then
                -- WHAT this cluster is comes before how big it is, so the aura
                -- toggle heads the block on its own full-width line above the
                -- size/spacing grid. Its own bracket carries the panel-only
                -- dimming, exactly like the grid columns below.
                --
                -- A section holding anything the aura container cannot draw is
                -- told so on a DISABLED checkbox rather than being allowed to
                -- click and fail: the engine's refusal is asked for here, before
                -- the write, and the blocking entry's own sentence is what the
                -- row explains itself with. The blocker only ever gates turning
                -- the flag ON. A section already flagged can still develop one
                -- (polarity is spec-dependent, so a member admitted on one spec
                -- can mismatch on another), and the setter deliberately lets OFF
                -- through unconditionally - so the checkbox must stay clickable
                -- there, or the section is trapped aura-only.
                local sectionAuraOnly = ST.IsAuraOnlyPanelSection(group, anchor)
                local sectionBlocker = not sectionAuraOnly
                    and ST.GetAuraSectionToggleBlocker(group, anchor) or nil
                local sectionToggleTooltip = AURA_SECTION_TOOLTIP
                if sectionBlocker then
                    sectionToggleTooltip = {
                        AURA_SECTION_TOOLTIP[1],
                        {sectionBlocker, 1, 0.4, 0.4, true},
                        " ",
                    }
                    for line = 2, #AURA_SECTION_TOOLTIP do
                        sectionToggleTooltip[#sectionToggleTooltip + 1] = AURA_SECTION_TOOLTIP[line]
                    end
                end

                local sectionTopBracket = sectionSec:Bracket(container)
                AddCheckboxRow(container, {
                    label = "Aura Only Section",
                    relativeWidth = 0.5,
                    value = sectionAuraOnly,
                    tooltip = sectionToggleTooltip,
                    disabled = sectionSec.disabled or sectionBlocker ~= nil,
                    onChange = function(value, widget)
                        -- A structural commit, not a styling one: the flag
                        -- changes which entries materialize a button at all, so
                        -- it takes the same pair a section drop takes rather
                        -- than the sliders' UpdateGroupStyle. Safe here for the
                        -- same reason it is safe there - a click is over.
                        if not ST.SetPanelSectionAuraOnly(group, anchor, value) then
                            widget:SetValue(ST.IsAuraOnlyPanelSection(group, anchor))
                            return
                        end
                        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                        CooldownCompanion:RefreshConfigPanel()
                    end,
                })
                sectionSec:FinishBracket(sectionTopBracket)

                local sectionLeft, sectionRight = BeginRowGrid(container)
                sectionSec:Mark(sectionLeft)

                local sectionW, sectionH, sectionSpacing =
                    ST.ResolvePanelSectionGeometry(style, section, sectionPanelW, sectionPanelH, panelSpacing)

                if style.maintainAspectRatio then
                    -- Square panel, square section: the engine derives both
                    -- dimensions from the one stored value, so there is one
                    -- slider and it writes that value.
                    local sectionSizeRow = AddSliderRow(sectionLeft, {
                        label = "Icon Size",
                        min = 10, max = 150, step = 0.1,
                        value = sectionW,
                        disabled = sectionSec.disabled,
                    })
                    WireMirrorFirstSlider(sectionSizeRow, function(val)
                        section.iconWidth = val
                    end, nil, nil, section, "iconWidth")
                else
                    local sectionWidthRow = AddSliderRow(sectionLeft, {
                        label = "Icon Width",
                        min = 10, max = 150, step = 0.1,
                        value = sectionW,
                        disabled = sectionSec.disabled,
                    })
                    WireMirrorFirstSlider(sectionWidthRow, function(val)
                        section.iconWidth = val
                    end, nil, nil, section, "iconWidth")

                    local sectionHeightRow = AddSliderRow(sectionLeft, {
                        label = "Icon Height",
                        min = 10, max = 150, step = 0.1,
                        value = sectionH,
                        disabled = sectionSec.disabled,
                    })
                    WireMirrorFirstSlider(sectionHeightRow, function(val)
                        section.iconHeight = val
                    end, nil, nil, section, "iconHeight")
                end

                sectionSec:Finish()

                local sectionRightBracket = sectionSec:Bracket(sectionRight)
                local sectionSpacingRow = AddSliderRow(sectionRight, {
                    label = "Spacing",
                    min = 0, max = 30, step = 0.1,
                    value = sectionSpacing,
                    disabled = sectionSec.disabled,
                })
                WireMirrorFirstSlider(sectionSpacingRow, function(val)
                    section.spacing = val
                end, nil, nil, section, "spacing")
                sectionSec:FinishBracket(sectionRightBracket)
                end -- not sectionCollapsed
            end
        end
    end

    -- ================================================================
    -- Text (the optional text drawn on top of the icons)
    -- ================================================================
    -- On an Aura Panel every possible Text row is aura-gated (Cooldown Text is
    -- left out, Count and Keybind are denied), so with no entries yet the
    -- heading would stand over an empty grid. Same guard shape as Glows.
    if not isAuraPanel or groupHasAuraEntry then
    local textHeading, textCollapsed = BuildCollapsibleSection(container, "Text", "appearance_text", nil, nil, ROW_SECTION)

    if not textCollapsed then
    local durationLowTimeStyle = (lens and lens.effective) or group.style
    local drawsCooldownLowTime = IconsDrawCooldownDurationLowTimeRows(group, durationLowTimeStyle)
    local drawsAuraLowTime = IconsDrawAuraDurationLowTimeRows(group, durationLowTimeStyle)
    -- Duration Format is panel-owned. Keep it reachable when either the panel
    -- default or the selected entry still has a duration consumer; an entry
    -- override must not strand a setting that remains live on other entries.
    local drawsCooldownFormat = IconsDrawCooldownDurationLowTimeRows(group, group.style)
        or drawsCooldownLowTime
    local drawsAuraFormat = IconsDrawAuraDurationLowTimeRows(group, group.style)
        or drawsAuraLowTime
    AddSettingsSubheading(container, "Duration Text")
    local durationLeft, durationRight
    if isAuraPanel then
        durationLeft = BeginFullWidthRowGroup(container)
        durationRight = durationLeft
    else
        durationLeft, durationRight = BeginRowGrid(container)
    end
    local lowTimeLeft, lowTimeRight
    if drawsCooldownLowTime or drawsAuraLowTime then
        if isAuraPanel then
            lowTimeLeft = BeginFullWidthRowGroup(container)
            lowTimeRight = lowTimeLeft
        else
            lowTimeLeft, lowTimeRight = BeginRowGrid(container)
        end
    end

    AddSettingsSubheading(container, "Other Text")
    local otherLeft, otherRight
    if isAuraPanel then
        otherLeft = BeginFullWidthRowGroup(container)
        otherRight = otherLeft
    else
        otherLeft, otherRight = BeginRowGrid(container)
    end

    -- Ordinary icon panels give cooldown and aura parallel columns. Aura
    -- Panels have no cooldown consumer, so their duration and other-text rails
    -- are full width rather than preserving an empty left or right column.
    local auraTextHost = isAuraPanel and durationLeft or durationRight

    local durationFormatAdded = false
    local function AddDurationFormatRow()
        if durationFormatAdded then return nil end
        local row = AddDurationFormatDropdown(durationLeft, group.style, refreshStyle, {
            sharedHelp = true,
            infoButtons = tabInfoButtons,
        })
        durationFormatAdded = row ~= nil
        return row
    end

    -- Each of the five sections below resolves its own scope against the lens.
    -- The write table is the whole gate: nil means the section is INERT, so its
    -- rows go in read-only, it builds no gear, and no callback of its own can
    -- reach a saved table. The scope chrome is attached LAST on the row (after
    -- the gear, after any info button, after the row's disabled state is
    -- final), because it is the one control that stays live in an inert
    -- section - the way back out of it.

    -- Dedicated override section (owner ruling 2026-08-25): the shared keys
    -- are entry-customizable as one unit, independent of cooldownText and
    -- auraText. The master row carries the section's one scope affordance and
    -- the inert sweep gates the whole dependent family.
    local function AddDurationLowTimeSection()
        if not (ST._AddDurationLowTimeRows and lowTimeLeft and lowTimeRight) then return end
        local lowTimeSec = BeginLensSection(lens, group, "durationLowTime", { column = lowTimeLeft })
        local rightBracket = lowTimeRight ~= lowTimeLeft
            and lowTimeSec:Bracket(lowTimeRight) or nil
        local entryIsAuraOnly = (lens and lens.mode == "entry") and lens.buttonData
            and ST.IsAuraSectionEntry(group, lens.buttonData)
        -- Master row unindented (owner ruling 2026-08-28): the policy serves
        -- cooldown AND aura text, so it no longer reads as a child of Show
        -- Cooldown Text. The aura opt-in row rides only where the aura
        -- surface exists; Aura Panels apply unconditionally (runtime gate).
        local rows = ST._AddDurationLowTimeRows(lowTimeLeft, lowTimeSec.tbl, refreshStyle, {
            explicitOff = lowTimeSec.scope == "customized",
            disabled = lowTimeSec.disabled,
            rightColumn = lowTimeRight,
            auraOnly = isAuraPanel or entryIsAuraOnly,
            -- Aura-section entries render through the auraPanel host live,
            -- so their aura text applies unconditionally: the opt-in row
            -- would be a lie at that entry's lens and hides there. The
            -- panel-scope row stays: the base grid can still hold
            -- cooldown-capable entries.
            auraToggle = not isAuraPanel and not entryIsAuraOnly
                and IconsDrawAuraDurationLowTimeRows(group, (lens and lens.effective) or group.style),
            infoButtons = tabInfoButtons,
            rebuild = function()
                refreshStyle()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
        if rows and rows[1] then
            lowTimeSec:Chrome(rows[1])
        end
        lowTimeSec:Finish()
        lowTimeSec:FinishBracket(rightBracket)
    end

    -- Show Cooldown Text toggle. An Aura Panel has no cooldown to count down, so
    -- the toggle itself is dead there and is left out; the two live things that
    -- hung off it (Duration Format, and the cooldownText* position keys that
    -- place the aura duration text while the aura hides the cooldown) move
    -- into the aura duration text section on the right.
    if not isAuraPanel then
    local cdTextSec = BeginLensSection(lens, group, "cooldownText", { column = durationLeft })

    local cdTextRow = AddCheckboxRow(durationLeft, {
        label = "Show Cooldown Text",
        value = cdTextSec.read.showCooldownText or false,
        disabled = cdTextSec.disabled,
        onChange = function(val)
            if not cdTextSec.write then return end
            cdTextSec.write.showCooldownText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if cdTextSec.write then
        -- Panel scope hands the descriptor NO table, so it keeps resolving the
        -- live group style itself (see the factory's note). An entry's override
        -- store has no such resolver, so that one is handed over explicitly.
        local cdTextAdvanced = MakeCooldownTextAdvancedDescriptor(
            cdTextSec.scope == "customized" and cdTextSec.write or nil)

        AddAdvancedToggle(cdTextRow, cdTextAdvanced.settingKey, tabInfoButtons, cdTextSec.read.showCooldownText, {
            title = cdTextAdvanced.title,
            build = cdTextAdvanced.build,
        })
    end
    cdTextSec:Chrome(cdTextRow)

    if cdTextSec.read.showCooldownText == true then
        AddDurationTextVisibilityRows(durationLeft, cdTextSec.read, cdTextSec.write,
            "cooldown", refreshStyle, {
                explicitOff = cdTextSec.scope == "customized",
                disabled = cdTextSec.disabled,
                infoButtons = tabInfoButtons,
                rebuild = function()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
    end

    cdTextSec:Finish()
    if drawsCooldownFormat then
        local dfRow = AddDurationFormatRow()
        if dfRow then
            cdTextSec:PanelRowChrome(dfRow)
        end
    end
    if drawsCooldownLowTime then
        AddDurationLowTimeSection()
    end
    end -- not isAuraPanel

    -- Show Charge Text toggle. Charges and uses are spell mechanics, so an Aura
    -- Panel never counts anything here (ST.CanGroupUseOverrideSection); the
    -- aura's own stack count is the Show Aura Stack Text row on the right.
    if CanGroupUseOverrideSection(group, "chargeText") then
    local chargeSec = BeginLensSection(lens, group, "chargeText", { column = otherLeft })

    local chargeTextRow = AddCheckboxRow(otherLeft, {
        label = "Show Count Text (Charges/Uses)",
        value = chargeSec.read.showChargeText ~= false,
        disabled = chargeSec.disabled,
        onChange = function(val)
            if not chargeSec.write then return end
            chargeSec.write.showChargeText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- every builder runs with { row = true } and no rightColumn.
    --
    -- The three count colors are the panel's longest labels. They end in a 19px
    -- swatch, which is the narrow control the row grammar reserves long labels
    -- for, and each states itself on hover so a narrower config column cannot
    -- silently swallow which charge state it names.
    --
    -- deferCommit is deliberately absent throughout, matching the
    -- stock color pickers these rows replaced.
    --
    -- The panel captures the section's WRITE table, which is the group style or
    -- the selected entry's override store depending on scope. Only built while
    -- there is one: an inert section has no gear to open it from.
    local function BuildChargeTextAdvanced(panel)
        AddFontControls(panel, chargeSec.write, "charge", { size = 12 }, refreshStyle, { row = true })

        local function ChargeColorRow(rowLabel, key)
            AddColorRow(panel, {
                label = rowLabel,
                tooltip = { rowLabel },
                tbl = chargeSec.write,
                key = key,
                default = {1, 1, 1, 1},
                hasAlpha = true,
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })
        end
        ChargeColorRow("Font Color (Max Charges)", "chargeFontColor")
        ChargeColorRow("Font Color (Missing Charges)", "chargeFontColorMissing")
        ChargeColorRow("Font Color (Zero Charges)", "chargeFontColorZero")

        AddAnchorDropdown(panel, chargeSec.write, "chargeAnchor", "BOTTOMRIGHT", refreshStyle, nil, { row = true })
        AddOffsetSliders(panel, chargeSec.write, "chargeXOffset", "chargeYOffset", { x = -2, y = 2 }, refreshStyle, { row = true })
    end

    if chargeSec.write then
        AddAdvancedToggle(chargeTextRow, "chargeText", tabInfoButtons, chargeSec.read.showChargeText ~= false, {
            title = "Count Text Advanced",
            build = BuildChargeTextAdvanced,
        })
    end
    chargeSec:Chrome(chargeTextRow)

    chargeSec:Finish()
    end -- CanGroupUseOverrideSection chargeText

    -- Aura text sections (shown only while the group has an aura-tracking entry)
    if groupHasAuraEntry then
        -- Show Aura Duration Text toggle
        local auraTextSec = BeginLensSection(lens, group, "auraText", { column = auraTextHost })
        -- While Aura Active: its own override section (Defaults.lua), drawn in
        -- its own collapsible after this one. It is resolved HERE too, ahead of
        -- the aura text rows, because the aura text advanced panel reads one of
        -- its flags to decide which position rows to draw and that panel is
        -- built from inside this section. READ-ONLY here - no rows, no chrome,
        -- no bracket; the collapsible below resolves the section again for
        -- those. Under an entry lens the two sections can disagree about scope,
        -- which is why this one is asked rather than auraTextSec.
        local whileAuraSec = BeginLensSection(lens, group, "whileAuraActive")
        local function SeparatePositionsOn()
            return WhileAuraFlagOn(whileAuraSec, "separateTextPositions")
        end

        local auraTextRow = AddCheckboxRow(auraTextHost, {
            label = "Show Aura Duration Text",
            value = auraTextSec.read.showAuraText ~= false,
            disabled = auraTextSec.disabled,
            onChange = function(val)
                if not auraTextSec.write then return end
                auraTextSec.write.showAuraText = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Single rail (AdvancedSettingsPanel.lua): every builder runs with
        -- { row = true } and no rightColumn.
        local function BuildAuraDurationTextAdvanced(panel)
            AddFontControls(panel, auraTextSec.write, "auraText", { size = 12 }, refreshStyle, { row = true })

            -- deferCommit is deliberately absent, matching the stock color picker
            -- this row replaced.
            AddColorRow(panel, {
                label = "Font Color",
                tbl = auraTextSec.write,
                key = "auraTextFontColor",
                default = {0, 0.925, 1, 1},
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })

            -- WHICH position keys this text uses is decided by Keep Cooldown
            -- Text, a row in the While Aura Active section. This panel
            -- only draws the keys that are actually live, which is the same
            -- answer GetAuraDurationTextPlacement gives at runtime: the aura
            -- keys once the flag is on, the shared cooldown-text keys while it
            -- is off. That also means a style which arrived with the flag
            -- already true (a copied or imported panel style) still edits the
            -- keys placing the text, and an Aura Panel - which has no cooldown
            -- text to share with and never draws the flag's row - needs no
            -- special case beyond the branch below.
            --
            -- The keep-swipe state (Show Swipe and Text) also switches the text to the aura keys
            -- (GetAuraDurationTextPlacement: the uncovered cooldown text keeps
            -- the shared spot), so the aura-key rows draw for that flag too -
            -- otherwise a keep-swipe entry's live position keys would have no
            -- rows to edit them.
            if SeparatePositionsOn() or WhileAuraFlagOn(whileAuraSec, "auraKeepSpellCooldownSwipe") then
                AddAnchorDropdown(panel, auraTextSec.write, "auraTextAnchor", "TOPLEFT", refreshStyle, nil, { row = true })
                AddOffsetSliders(panel, auraTextSec.write, "auraTextXOffset", "auraTextYOffset", { x = 2, y = -2 }, refreshStyle, { row = true })
            elseif isAuraPanel then
                -- The re-homed shared-position rows. Same STORAGE KEYS as before
                -- (the engine reads cooldownTextAnchor/XOffset/YOffset for this
                -- text whenever separateTextPositions is off), so nothing is
                -- migrated - only where they are edited moves.
                --
                -- They write group.style rather than this section's store: those
                -- keys belong to the cooldownText override section, and a copy of
                -- them inside the auraText store would be keys RevertSection
                -- cannot clear (the never-share-a-key rule the bar name offsets
                -- and Duration Format both follow). So they are openly
                -- PANEL-OWNED and wear the grey "Panel setting" label.
                local panelStyle = group.style
                local anchorRow = AddAnchorDropdown(panel, panelStyle, "cooldownTextAnchor", "CENTER", refreshStyle, nil, { row = true })
                local offsetXRow, offsetYRow = AddOffsetSliders(panel, panelStyle, "cooldownTextXOffset", "cooldownTextYOffset", { x = 0, y = 0 }, refreshStyle, { row = true })
                auraTextSec:PanelRowChrome(anchorRow)
                auraTextSec:PanelRowChrome(offsetXRow)
                auraTextSec:PanelRowChrome(offsetYRow)
            end
        end

        if auraTextSec.write then
            AddAdvancedToggle(auraTextRow, "auraText", tabInfoButtons, auraTextSec.read.showAuraText ~= false, {
                title = "Aura Duration Text Advanced",
                build = BuildAuraDurationTextAdvanced,
            })
        end
        -- Second badge in the chain: gear, then this, then the scope chrome the
        -- lens attaches last. The anchor args below are a placeholder -
        -- AnchorRowBadge re-points the button onto the end of the chain.
        --
        -- Nothing to explain on an Aura Panel: there is no cooldown text to
        -- share a position with, and the advanced panel there draws the position
        -- rows directly rather than behind a choice.
        if not isAuraPanel then
            local auraPosInfo = AnchorRowBadge(auraTextRow, CreateInfoButton(auraTextRow.frame, auraTextRow.frame, "LEFT", "LEFT", 0, 0, {
                "Shared Position",
                {"Position is shared with Cooldown Text by default. Set Cooldown under While Aura Active to Show Text for an independent position, set in advanced settings.", 1, 1, 1, true},
            }, auraTextRow))
            if auraTextSec.read.showAuraText == false then
                auraPosInfo:Hide()
            end
        end
        auraTextSec:Chrome(auraTextRow)

        if auraTextSec.read.showAuraText ~= false then
            AddDurationTextVisibilityRows(auraTextHost, auraTextSec.read, auraTextSec.write,
                "aura", refreshStyle, {
                    explicitOff = auraTextSec.scope == "customized",
                    disabled = auraTextSec.disabled,
                    infoButtons = tabInfoButtons,
                    rebuild = function()
                        CooldownCompanion:RefreshConfigPanel()
                    end,
                })
        end

        auraTextSec:Finish()
        if drawsAuraFormat and not durationFormatAdded then
            local dfRow = AddDurationFormatRow()
            if dfRow then
                auraTextSec:PanelRowChrome(dfRow)
            end
        end

        -- Ordinary panels keep one row family: if effective cooldown text is
        -- hidden, the visible aura duration surface becomes its config home.
        if IconsDrawAuraDurationLowTimeRows(group, durationLowTimeStyle)
            and not drawsCooldownLowTime then
            AddDurationLowTimeSection()
        end

        -- Show Aura Stack Text toggle
        local auraStackSec = BeginLensSection(lens, group, "auraStackText", { column = otherRight })

        local auraStackRow = AddCheckboxRow(otherRight, {
            label = "Show Aura Stack Text",
            value = auraStackSec.read.showAuraStackText ~= false,
            disabled = auraStackSec.disabled,
            onChange = function(val)
                if not auraStackSec.write then return end
                auraStackSec.write.showAuraStackText = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
        local function BuildAuraStackTextAdvanced(panel)
            AddFontControls(panel, auraStackSec.write, "auraStack", { size = 12 }, refreshStyle, { row = true })
            -- deferCommit is deliberately absent, matching the stock color picker
            -- this row replaced.
            AddColorRow(panel, {
                label = "Font Color",
                tbl = auraStackSec.write,
                key = "auraStackFontColor",
                default = {1, 1, 1, 1},
                hasAlpha = true,
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })
            AddAnchorDropdown(panel, auraStackSec.write, "auraStackAnchor", "BOTTOMLEFT", refreshStyle, nil, { row = true })
            AddOffsetSliders(panel, auraStackSec.write, "auraStackXOffset", "auraStackYOffset", { x = 2, y = 2 }, refreshStyle, { row = true })
        end

        if auraStackSec.write then
            AddAdvancedToggle(auraStackRow, "auraStackText", tabInfoButtons, auraStackSec.read.showAuraStackText ~= false, {
                title = "Aura Stack Text Advanced",
                build = BuildAuraStackTextAdvanced,
            })
        end
        auraStackSec:Chrome(auraStackRow)

        auraStackSec:Finish()
    end

    -- Show Keybind/Custom Text toggle. Nothing on an Aura Panel is cast, so
    -- there is no bind to detect and nothing for a custom replacement to stand
    -- in for (owner ruling 2026-08-15, carried by
    -- ST.AURA_PANEL_DENIED_OVERRIDE_SECTIONS).
    if CanGroupUseOverrideSection(group, "keybindText") then
    local kbSec = BeginLensSection(lens, group, "keybindText", { column = otherLeft })

    local kbRow = AddCheckboxRow(otherLeft, {
        label = KEYBIND_CUSTOM_LABEL,
        value = kbSec.read.showKeybindText or false,
        disabled = kbSec.disabled,
        onChange = function(val)
            if not kbSec.write then return end
            kbSec.write.showKeybindText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
    local function BuildKeybindTextAdvanced(panel)
        -- Keybind uses a hardcoded 4-point anchor (not the full 9-point list),
        -- so this is a dropdown row of its own rather than AddAnchorDropdown.
        AddDropdownRow(panel, {
            label = "Anchor",
            list = {
                TOPRIGHT = "Top Right",
                TOPLEFT = "Top Left",
                BOTTOMRIGHT = "Bottom Right",
                BOTTOMLEFT = "Bottom Left",
            },
            value = kbSec.write.keybindAnchor or "TOPRIGHT",
            onChange = function(val)
                kbSec.write.keybindAnchor = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })

        AddOffsetSliders(panel, kbSec.write, "keybindXOffset", "keybindYOffset", { x = -2, y = -2 }, refreshStyle, { row = true })
        AddFontControls(panel, kbSec.write, "keybind", { size = 10, sizeMin = 6, sizeMax = 24 }, refreshStyle, { row = true })
        -- deferCommit is deliberately absent, matching the stock color picker
        -- this row replaced.
        AddColorRow(panel, {
            label = "Font Color",
            tbl = kbSec.write,
            key = "keybindFontColor",
            default = {1, 1, 1, 1},
            hasAlpha = true,
            onConfirm = refreshStyle,
            onChange = refreshStyle,
        })
    end

    if kbSec.write then
        AddAdvancedToggle(kbRow, "keybindText", tabInfoButtons, kbSec.read.showKeybindText, {
            title = KEYBIND_CUSTOM_LABEL .. " Advanced",
            build = BuildKeybindTextAdvanced,
        })
    end
    -- The gear is already chained off the label; this info button lands to its
    -- right, and the lens' scope chrome after that. Anchor args are a placeholder.
    AnchorRowBadge(kbRow, CreateInfoButton(kbRow.frame, kbRow.frame, "LEFT", "LEFT", 0, 0, KEYBIND_CUSTOM_TOOLTIP, kbRow))
    kbSec:Chrome(kbRow)

    kbSec:Finish()
    end -- CanGroupUseOverrideSection keybindText
    end -- not textCollapsed
    end -- Text section drawn (aura panels need an aura entry)

    -- ================================================================
    -- While Aura Active
    -- ================================================================
    -- What the entry keeps showing on its OWN icon while the tracked aura runs.
    -- Its own section rather than a block inside Text (owner ruling 2026-08-16):
    -- keeping the cooldown swipe is not text at all, and the control names a STATE the
    -- icon is in.
    --
    -- One gate: the group must track an aura, or no heading is drawn. An Aura
    -- Panel keeps the section but only the Desaturate row inside it - there is
    -- no cooldown there to keep a swipe or a countdown for, and its entries
    -- are all standalone auras whose live icon the engine forces on
    -- (ShouldShowAuraIcon), so those two controls would be dead.
    if groupHasAuraEntry then
    -- The whole collapsible IS the whileAuraActive section, so its collapse key
    -- follows that section's scope through ST._ResolveLensCollapseKey, exactly
    -- as Border and Icon Tint do below.
    local whileAuraHeading, whileAuraCollapsed = BuildCollapsibleSection(container, "While Aura Active",
        ResolveLensCollapseKey(lens, group, "whileAuraActive", "appearance_whileAuraActive"), nil, nil, ROW_SECTION)
    -- Resolved again here. The Text section above resolves the same section
    -- READ-ONLY for its position-row gate, and that one is out of scope by now
    -- (it lives inside the Text collapsible, which may not have been built at
    -- all). Both resolutions read the same store, so they cannot disagree.
    local whileAuraSec = BeginLensSection(lens, group, "whileAuraActive")
    -- Section-owning collapsible, so the scope chrome hangs off the HEADING
    -- like Border's and Icon Tint's. It has to: under an entry lens that only
    -- inherits this section the collapsible opens folded, and chrome buried on
    -- a row inside would leave no Customize button in reach.
    whileAuraSec:HeadingChrome(whileAuraHeading)

    if not whileAuraCollapsed then
    -- Single column; the right one is deliberately empty, as Border's is.
    local whileAuraLeft = BeginRowGrid(container)

    -- The column only exists here, so the section's bracket is taken now rather
    -- than at Begin.
    whileAuraSec:Mark(whileAuraLeft)

    -- The selected entry, or nil at panel/multi scope. Every gate below that
    -- reads it is ENTRY SCOPE ONLY: a panel default must stay offered even
    -- where today's entries cannot use it (mixed panels, entries added later).
    local lensEntry = (lens and lens.mode == "entry") and lens.buttonData or nil
    -- The same store WhileAuraFlagOn reads, so a gate below can never disagree
    -- with the row it is gating (see that helper's note on write-before-read).
    local whileAuraStyle = whileAuraSec.write or whileAuraSec.read or {}

    if not isAuraPanel then
    -- ENTRY SCOPE ONLY: which of the three states this selection can actually
    -- reach. Keep-swipe carries entry-shape terms the panel cannot see
    -- (IsKeepSpellCooldownSwipeEntry: aura-tracking, not standalone, not
    -- passive, not a shell), so on those entries the swipe state is a choice
    -- the engine would refuse. The other two states stay: separateTextPositions
    -- is live for EVERY aura entry, standalone and passive included, because
    -- GetAuraDurationTextPlacement reads it to decide which anchor keys place
    -- the aura duration text. Panel scope offers all three unchanged - a panel
    -- default outlives the entries currently under it.
    local keepSwipeReachable = lensEntry == nil
        or CooldownCompanion:IsKeepSpellCooldownSwipeEntry(lensEntry,
            { auraKeepSpellCooldownSwipe = true })
    -- The three-state ladder, stated as one dropdown (see the tooltip
    -- constant's note). Derivation mirrors the engine: keep-swipe contains
    -- keep-text, so a store holding keep without sep (a migrated profile)
    -- still reads as the full-keep state. Where the engine refuses the swipe
    -- the keep flag is simply inert, so separateTextPositions alone decides
    -- what the row says - reading a stored value down is not writing it down,
    -- and the store is left exactly as it is.
    local whileAuraState = (keepSwipeReachable
            and WhileAuraFlagOn(whileAuraSec, "auraKeepSpellCooldownSwipe") and "swipeText")
        or (WhileAuraFlagOn(whileAuraSec, "separateTextPositions") and "text")
        or "hidden"
    local cooldownStateList, cooldownStateOrder = WHILE_AURA_ACTIVE_LIST, WHILE_AURA_ACTIVE_ORDER
    if not keepSwipeReachable then
        cooldownStateList = { hidden = WHILE_AURA_ACTIVE_LIST.hidden, text = WHILE_AURA_ACTIVE_LIST.text }
        cooldownStateOrder = { "hidden", "text" }
    end
    local cooldownStateRow = AddDropdownRow(whileAuraLeft, {
        label = "Cooldown",
        list = cooldownStateList,
        order = cooldownStateOrder,
        value = whileAuraState,
        disabled = whileAuraSec.disabled,
        onChange = function(val)
            if not whileAuraSec.write then return end
            -- Both keys written as a normalized combination; explicit false
            -- under "customized" (LensSection:BoolValue), or a deleted key
            -- would fall back to the panel value through the entry's runtime
            -- __index. swipeText also sets separateTextPositions true: the
            -- engine already treats keep-swipe as containing keep-text, this
            -- just makes the stored state say so.
            whileAuraSec.write.auraKeepSpellCooldownSwipe = whileAuraSec:BoolValue(val == "swipeText")
            whileAuraSec.write.separateTextPositions = whileAuraSec:BoolValue(val ~= "hidden")
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            -- Full rebuild: the entry-tab desaturate row and the aura text
            -- advanced panel's position rows both gate on these keys. The
            -- control lives outside that advanced panel now, so closing an
            -- open one is acceptable where it wasn't for the old in-panel
            -- checkbox.
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    -- Anchor args are a placeholder - AnchorRowBadge re-points the button onto
    -- the end of the row's label.
    AnchorRowBadge(cooldownStateRow, CreateInfoButton(cooldownStateRow.frame, cooldownStateRow.frame, "LEFT", "LEFT", 0, 0,
        WHILE_AURA_ACTIVE_TOOLTIP, tabInfoButtons))

    -- The other two things the aura display does to this icon, both former
    -- entry-data checkboxes on the entry's Aura Tracking section. Unindented:
    -- they are siblings of the dropdown, not details of it. Explicit false
    -- under "customized" (LensSection:BoolValue), or a deleted key would fall
    -- back to the panel value through the entry's runtime __index.
    --
    -- Standalone and passive entries always show the live aura icon whatever
    -- this says (ShouldShowAuraIcon), so at ENTRY SCOPE the row is left out for
    -- them: the toggle could only ever agree with the engine. It still draws at
    -- panel scope, where it is a default for whatever the panel holds next.
    if not (lensEntry and CooldownCompanion:IsAuraIconForcedEntry(lensEntry)) then
    AddCheckboxRow(whileAuraLeft, {
        label = "Show Aura Icon",
        value = WhileAuraFlagOn(whileAuraSec, "auraShowAuraIcon"),
        disabled = whileAuraSec.disabled,
        onChange = function(val)
            if not whileAuraSec.write then return end
            whileAuraSec.write.auraShowAuraIcon = whileAuraSec:BoolValue(val)
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            -- Full rebuild: the Cooldown tooltip's icon-cover interaction and
            -- the keep-swipe composition both turn on this flag.
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    end -- aura icon not forced for this entry
    end -- not isAuraPanel (Cooldown dropdown + Show Aura Icon)

    -- Desaturate Icon grays the AURA LAYER's icon regions, and a keep-swipe
    -- entry with the icon swap off hides both of them: StyleSlotKit drops the
    -- occluding cover for keep-swipe and leaves the aura icon at zero alpha
    -- without the swap, so nothing is left to gray. ENTRY SCOPE only - the
    -- combination is an entry's effective style, not a panel fact.
    local desatHasTarget = not (lensEntry
        and CooldownCompanion:IsKeepSpellCooldownSwipeEntry(lensEntry, whileAuraStyle)
        and whileAuraStyle.auraShowAuraIcon ~= true)
    if desatHasTarget then
    AddCheckboxRow(whileAuraLeft, {
        label = "Desaturate Icon",
        value = WhileAuraFlagOn(whileAuraSec, "invertAuraDesaturationLogic"),
        disabled = whileAuraSec.disabled,
        onChange = function(val)
            if not whileAuraSec.write then return end
            whileAuraSec.write.invertAuraDesaturationLogic = whileAuraSec:BoolValue(val)
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            -- Full rebuild: passives read the same key for their missing-state
            -- default on the entry tab.
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    end -- desaturate has a visible aura-layer icon to gray

    whileAuraSec:Finish()
    end -- not whileAuraCollapsed
    end -- While Aura Active section drawn

    -- ================================================================
    -- Border
    -- ================================================================
    -- The whole collapsible IS the borderSettings section, so its collapse key
    -- follows that section's scope through ST._ResolveLensCollapseKey.
    local borderHeading, borderCollapsed = BuildCollapsibleSection(container, "Border",
        ResolveLensCollapseKey(lens, group, "borderSettings", "appearance_border"), nil, nil, ROW_SECTION)
    -- The lens' section scope: with an entry selected the heading says whose
    -- border this is and offers the one action that changes that.
    local borderSec = BeginLensSection(lens, group, "borderSettings")
    borderSec:HeadingChrome(borderHeading)

    if not borderCollapsed then
    -- Three related rows, so they stay in one column rather than splitting a
    -- parent from its children. The right column is deliberately empty.
    local borderLeft = BeginRowGrid(container)

    -- The column only exists here, so the section's bracket is taken now
    -- rather than at Begin.
    borderSec:Mark(borderLeft)

    -- Masque gating stays on the GROUP flag, not the lens: skinning owns the
    -- border art for the whole panel, and no entry can override that.
    --
    -- Border Color owns the section; thickness and size are its children.
    local borderColorRow = AddColorRow(borderLeft, {
        label = "Border Color",
        tbl = borderSec.tbl,
        key = "borderColor",
        default = {0, 0, 0, 1},
        hasAlpha = true,
        disabled = borderSec.disabled or group.masqueEnabled == true,
        onConfirm = refreshStyle,
        onChange = refreshStyle,
    })
    borderSec:DirectColorControl(borderColorRow, "borderColor", group.masqueEnabled == true)

    local renderMode = AddBorderRenderModeDropdown(borderLeft, borderSec.tbl, "borderRenderMode", function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end, group.masqueEnabled or borderSec.disabled, { row = true, indent = true })
    local borderThicknessLocked = group.masqueEnabled or ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderSizeRow = AddSliderRow(borderLeft, {
            label = "Border Size",
            indent = true,
            min = 0, max = 5, step = 0.1,
            value = borderSec.read.borderSize or ST.DEFAULT_BORDER_SIZE,
            disabled = (borderSec.disabled or borderThicknessLocked) and true or false,
        })
        -- Not wired at all while the section is inert. The mirror-first path
        -- SNAPSHOTS AND RESTORES its state owner on every drag tick, so wiring
        -- it to anything is wiring a write path; the read-only lens has no
        -- table for one, so it gets no wiring instead of a harmless-looking one.
        if borderSec.write then
            WireMirrorFirstSlider(borderSizeRow, function(val)
                if borderThicknessLocked then return end
                borderSec.write.borderSize = val
            end, function()
                if borderThicknessLocked then return end
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end, nil, borderSec.write, "borderSize")
        end
    end

    borderSec:Finish()
    end -- not borderCollapsed

    -- ================================================================
    -- Icon Tint
    -- ================================================================
    local iconTintHeading, iconTintCollapsed = BuildCollapsibleSection(container, "Icon Tint",
        ResolveLensCollapseKey(lens, group, "iconTint", "appearance_iconTint"), nil, nil, ROW_SECTION)
    local tintSec = BeginLensSection(lens, group, "iconTint")

    local iconTintTooltip = {
        "Icon Tint",
        {"Recolor or fade icons without affecting cooldown text, glows, or borders.", 1, 1, 1, true},
        " ",
        {"Base Icon Color:", 1, 0.82, 0},
        {"The default color for your icons. Lower the alpha to make icons semi-transparent while everything else stays visible.", 1, 1, 1, true},
        " ",
        {"Cooldown Tint:", 1, 0.82, 0},
        {"A separate color used only while an ability is on cooldown. Great for dimming icons on cooldown while keeping ready abilities bright.", 1, 1, 1, true},
    }
    if groupHasAuraEntry then
        table.insert(iconTintTooltip, " ")
        table.insert(iconTintTooltip, {"Aura Tint:", 1, 0.82, 0})
        table.insert(iconTintTooltip, {"A separate color used only while a tracked aura is active.", 1, 1, 1, true})
    end
    -- The (?) badge chains off the heading label, and the lens' scope chrome
    -- lands after it: label -> (?) -> scope. Chaining also keeps the fading
    -- rule behind whichever decoration ends up last.
    ChainHeadingBadges(iconTintHeading, CreateInfoButton(iconTintHeading.frame,
        iconTintHeading.label, "LEFT", "RIGHT", 4, 0, iconTintTooltip, tabInfoButtons))

    tintSec:HeadingChrome(iconTintHeading)

    if not iconTintCollapsed then
        local tintRefresh = function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end

        -- LEFT column: the always-on colors plus the cooldown tint pair.
        -- RIGHT column: the conditional state tints.
        local tintLeft, tintRight = BeginRowGrid(container)

        -- Both columns bracket separately: an inert range is a contiguous slice
        -- of ONE column's children, and this section fills two.
        tintSec:Mark(tintLeft)
        local tintRightBracket = tintSec:Bracket(tintRight)

        -- Rows only; the shared builder draws the same block on the bars tab.
        BuildIconTintControls(tintLeft, tintRight, tintSec, {
            mode = "icons",
            hasAuraEntry = groupHasAuraEntry,
            hasCooldownState = CanGroupUseOverrideSection(group, "desaturation"),
            refresh = tintRefresh,
        })

        tintSec:Finish()
        tintSec:FinishBracket(tintRightBracket)
    end -- not iconTintCollapsed

    -- ================================================================
    -- Masque skinning (icon-only)
    -- ================================================================
    -- Aura Panels draw no CC buttons for Masque to skin - every cell is a
    -- Blizzard aura frame CC styles through the slot kit - and the group frame
    -- already refuses to register one (GroupFrame's masque branch). Offering the
    -- toggle here would be a switch with nothing behind it.
    if CooldownCompanion.Masque and not CooldownCompanion:IsAuraPanel(group) then
        local masqueHeading, masqueCollapsed = BuildCollapsibleSection(container, "Masque",
            ResolveLensCollapseKey(lens, group, nil, "appearance_masque"), nil, nil, ROW_SECTION)
        -- Panel-only (sectionId nil): skinning is switched on for the whole
        -- panel, and there is no per-entry form of it to offer.
        local masqueSec = BeginLensSection(lens, group, nil)
        masqueSec:HeadingChrome(masqueHeading)

        if not masqueCollapsed then
        -- One setting; the right column stays empty.
        local masqueLeft = BeginRowGrid(container)

        -- The column only exists here, so the section's bracket is taken now
        -- rather than at Begin.
        masqueSec:Mark(masqueLeft)

        local masqueRow = AddCheckboxRow(masqueLeft, {
            label = "Enable Masque Skinning",
            value = group.masqueEnabled or false,
            disabled = masqueSec.disabled,
            onChange = function(val)
                CooldownCompanion:ToggleGroupMasque(CS.selectedGroup, val)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Anchor args are a placeholder: AnchorRowBadge re-points the button
        -- onto the end of the label's badge chain.
        AnchorRowBadge(masqueRow, CreateInfoButton(masqueRow.frame, masqueRow.frame, "LEFT", "LEFT", 0, 0, {
            "Masque Skinning",
            {"Uses the Masque addon to apply custom button skins to this group. Configure skins via /masque or the Masque config panel.", 1, 1, 1, true},
            " ",
            {"Overridden Settings:", 1, 0.82, 0},
            {"Border Thickness, Border Size, Border Color, Square Icons (forced on)", 0.7, 0.7, 0.7, true},
        }, tabInfoButtons))

        masqueSec:Finish()
        end -- not masqueCollapsed
    end

    -- Inert-section sweep, over BOTH icons gear maps. A section the lens
    -- resolved read-only builds no gear, so nothing rebound or closed an
    -- advanced panel that was already open on that gear - and its controls
    -- still write to the table the PREVIOUS build handed them. Close those here.
    --
    -- Scope-driven, not collapse-driven: a collapsed section builds no gear
    -- either, and a panel left over from before an entry was selected is just
    -- as live behind a closed section as behind an open one.
    --
    -- Both maps, not just this tab's: only one panel tab is ever built at a
    -- time, so a stale panel whose gear lives on the icons Indicators tab is
    -- just as live from here as one of this tab's own. See the twin sweep at
    -- the foot of BuildEffectsTab.
    if CS.CloseAdvancedSettingsPanel then
        local gearMaps = { ST._APPEARANCE_SECTION_BY_ADVANCED_KEY, ST._INDICATORS_OVERRIDE_SECTION_BY_ADVANCED_KEY }
        for i = 1, #gearMaps do
            for advancedKey, sectionId in pairs(gearMaps[i]) do
                local _, _, sectionWrite = ResolveLensSection(lens, group, sectionId)
                if sectionWrite == nil then
                    CS.CloseAdvancedSettingsPanel({ settingKey = advancedKey })
                end
            end
        end
    end
end

ST._BuildAppearanceTab = BuildAppearanceTab
