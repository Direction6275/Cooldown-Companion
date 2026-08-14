local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local BuildCompactModeControls = ST._BuildCompactModeControls
local BuildGroupSettingPresetControls = ST._BuildGroupSettingPresetControls
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
        gearEnabled = function(_, style) return (style.showCooldownText) ~= false end,
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
    -- Section-level action buttons ("Reset Colors to Default", the preset
    -- Apply/Save/Delete trio) are compact and flush left: SetAutoWidth(true),
    -- never SetFullWidth. A page-wide button is louder than every setting it
    -- sits under, and both List and Flow anchor their children from the left,
    -- so no alignment wrapper is needed. They go INSIDE the grid, filling the
    -- shorter column's empty tail, rather than below it - a lopsided section
    -- with a lone button hanging off the bottom reads as unfinished.
    -- ================================================================
    local groupHasAuraEntry = GroupHasAuraTrackingEntry(group)

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
    -- Text (the optional text drawn on top of the icons)
    -- ================================================================
    local textHeading, textCollapsed = BuildCollapsibleSection(container, "Text", "appearance_text", nil, nil, ROW_SECTION)

    if not textCollapsed then
    -- LEFT column: the text every group can show (cooldown, count).
    -- RIGHT column: the conditional text (aura, keybind). The aura rows are
    -- gated on the group tracking an aura, so this column can run short - the
    -- grid top-aligns its columns, so a short side just ends early.
    local textLeft, textRight = BeginRowGrid(container)

    -- Each of the five sections below resolves its own scope against the lens.
    -- The write table is the whole gate: nil means the section is INERT, so its
    -- rows go in read-only, it builds no gear, and no callback of its own can
    -- reach a saved table. The scope chrome is attached LAST on the row (after
    -- the gear, after any info button, after the row's disabled state is
    -- final), because it is the one control that stays live in an inert
    -- section - the way back out of it.

    -- Show Cooldown Text toggle
    local cdTextSec = BeginLensSection(lens, group, "cooldownText", { column = textLeft })

    local cdTextRow = AddCheckboxRow(textLeft, {
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

    -- The inert sweep is taken HERE, ahead of Duration Format, so the sweep
    -- covers the rows above and leaves that one live (ApplyInertRange walks the
    -- column from the mark at call time).
    cdTextSec:Finish()

    -- Duration Format, an indented child of Show Cooldown Text.
    --
    -- durationFormat is not one of this section's override keys, so the row is
    -- openly PANEL-OWNED: it reads and writes group.style whatever the lens
    -- shows, stays live when an entry owns the section, and wears the grey
    -- "Panel setting" label there. It used to hide itself once the section was
    -- customized, which stranded the setting on some other selection state.
    -- The bars tab draws it the same way (BarModeTabs.lua).
    if cdTextSec.read.showCooldownText and CooldownCompanion.GetDurationFormatOptions then
        local formatOptions, formatOrder = CooldownCompanion:GetDurationFormatOptions()
        local dfRow = AddDropdownRow(textLeft, {
            label = "Duration Format",
            indent = true,
            list = formatOptions,
            order = formatOrder,
            value = CooldownCompanion.GetDurationFormat(group.style),
            onChange = function(val)
                group.style.durationFormat = CooldownCompanion.NormalizeDurationFormat(val)
                group.style.decimalTimers = nil
                refreshStyle()
            end,
        })
        cdTextSec:PanelRowChrome(dfRow)
    end

    -- Show Charge Text toggle
    local chargeSec = BeginLensSection(lens, group, "chargeText", { column = textLeft })

    local chargeTextRow = AddCheckboxRow(textLeft, {
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

    -- Aura text sections (shown only while the group has an aura-tracking entry)
    if groupHasAuraEntry then
        -- Show Aura Duration Text toggle
        local auraTextSec = BeginLensSection(lens, group, "auraText", { column = textRight })

        local auraTextRow = AddCheckboxRow(textRight, {
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
        -- { row = true } and no rightColumn, and the position rows the separate
        -- -positions toggle owns indent as its children.
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

            local sepPosRow = AddCheckboxRow(panel, {
                label = "Separate Text Positions",
                value = auraTextSec.write.separateTextPositions or false,
                onChange = function(val)
                    auraTextSec.write.separateTextPositions = val
                    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                    -- Rebuilds THIS panel, not the whole config, which is what
                    -- makes the two position rows appear in place.
                    RefreshActiveAdvancedSettingsPanel()
                end,
            })
            -- Anchor args are a placeholder - AnchorRowBadge re-points the
            -- button onto the end of the row's label.
            AnchorRowBadge(sepPosRow, CreateInfoButton(sepPosRow.frame, sepPosRow.frame, "LEFT", "LEFT", 0, 0, {
                "Separate Text Positions",
                {"Gives the aura duration text and the cooldown text independent positions.", 1, 1, 1, true},
                " ",
                {"The cooldown text also draws above the aura display, so both timers stay visible while the aura runs.", 1, 1, 1, true},
            }, sepPosRow))

            if auraTextSec.write.separateTextPositions then
                AddAnchorDropdown(panel, auraTextSec.write, "auraTextAnchor", "TOPLEFT", refreshStyle, nil, { row = true, indent = true })
                AddOffsetSliders(panel, auraTextSec.write, "auraTextXOffset", "auraTextYOffset", { x = 2, y = -2 }, refreshStyle, { row = true, indent = true })
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
        local auraPosInfo = AnchorRowBadge(auraTextRow, CreateInfoButton(auraTextRow.frame, auraTextRow.frame, "LEFT", "LEFT", 0, 0, {
            "Shared Position",
            {"Position is shared with Cooldown Text by default. Enable 'Separate Text Positions' in advanced settings to use independent positions.", 1, 1, 1, true},
        }, auraTextRow))
        if auraTextSec.read.showAuraText == false then
            auraPosInfo:Hide()
        end
        auraTextSec:Chrome(auraTextRow)

        auraTextSec:Finish()

        -- Show Aura Stack Text toggle
        local auraStackSec = BeginLensSection(lens, group, "auraStackText", { column = textRight })

        local auraStackRow = AddCheckboxRow(textRight, {
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

    -- Show Keybind/Custom Text toggle
    local kbSec = BeginLensSection(lens, group, "keybindText", { column = textRight })

    local kbRow = AddCheckboxRow(textRight, {
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
    end -- not textCollapsed

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
    AddColorRow(borderLeft, {
        label = "Border Color",
        tbl = borderSec.tbl,
        key = "borderColor",
        default = {0, 0, 0, 1},
        hasAlpha = true,
        disabled = borderSec.disabled or group.masqueEnabled == true,
        onConfirm = refreshStyle,
        onChange = refreshStyle,
    })

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
            refresh = tintRefresh,
        })

        tintSec:Finish()
        tintSec:FinishBracket(tintRightBracket)
    end -- not iconTintCollapsed

    -- ================================================================
    -- Masque skinning (icon-only)
    -- ================================================================
    if CooldownCompanion.Masque then
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

    BuildGroupSettingPresetControls(container, group, "icons", tabInfoButtons)

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
