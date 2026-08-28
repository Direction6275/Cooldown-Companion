--[[
    CooldownCompanion - ConfigSettings/BarModeTabs.lua: Bar-mode appearance and effects tab builders
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Core/Defaults.lua. "Can this PANEL ever use this override section?" - false
-- only on an Aura Panel, for the sections that read spell cooldown, castability,
-- proc, charge, cast or GCD state its pure-aura entries do not have.
local CanGroupUseOverrideSection = ST.CanGroupUseOverrideSection

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local BuildCompactModeControls = ST._BuildCompactModeControls
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders
local GroupHasAuraTrackingEntry = ST._GroupHasAuraTrackingEntry
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls

-- Style lens (Helpers.lua). Selecting an entry turns these tabs into a view of
-- that entry's effective values, with per-section scope deciding where - or
-- whether - each section writes. Helpers.lua loads first (the .toc), so these
-- resolve at load like every other import above.
-- ResolveLensSection is kept for the inert-section sweeps at the foot of both
-- builders, which only ask whether a section has a write table; every section
-- that draws rows goes through the host below instead.
local ResolveStyleLens = ST._ResolveStyleLens
local ResolveLensSection = ST._ResolveLensSection
local BeginLensSection = ST._BeginLensSection
local ResolveLensCollapseKey = ST._ResolveLensCollapseKey
local AddLensPanelScopeNote = ST._AddLensPanelScopeNote

-- Imports from SectionBuilders.lua
local BuildBorderControls = ST._BuildBorderControls
local BuildIconTintControls = ST._BuildIconTintControls
local BuildLossOfControlControls = ST._BuildLossOfControlControls
local BuildUnusableDimmingControls = ST._BuildUnusableDimmingControls
local BuildShowTooltipsControls = ST._BuildShowTooltipsControls
local BuildAllowPingsControls = ST._BuildAllowPingsControls
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown
local AddPandemicMarkerControls = ST._AddPandemicMarkerControls
local ReconcilePandemicMarkerPreview = ST._ReconcilePandemicMarkerPreview

-- Imports from RowWidgets.lua (the row grammar)
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddEditBoxRow = ST._AddEditBoxRow
local AddColorRow = ST._AddColorRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid

local tabInfoButtons = CS.tabInfoButtons

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right. The rules every row-grammar section follows are stated
-- once, in the recipe comment at the top of BuildAppearanceTab's icons path in
-- GroupTabsAppearance.lua; the sections below conform to them rather than
-- restating them.
local ROW_SECTION = { leftAligned = true }

-- The bar Effects tab draws the same four sections as the icons Effects tab
-- and deliberately SHARES their collapse keys, so the gear-to-section map
-- GroupTabsEffects.lua owns (ST._INDICATORS_SECTION_BY_ADVANCED_KEY) covers both tabs
-- with one entry per advanced key. Keep these in step with the constants
-- declared beside that map: the literals must MATCH, or collapsing a section
-- on an icon panel would leave it open on a bar panel.
local EFFECTS_GLOWS_SECTION = "effects_glows"
local EFFECTS_PANDEMIC_SECTION = "effects_pandemic"
local EFFECTS_TIMERS_SECTION = "effects_timers"
local EFFECTS_STATES_SECTION = "effects_states"

-- LibSharedMedia statusbar names run well past the 140px control column, and a
-- dropdown sizes its menu from the control it hangs under.
local BAR_TEXTURE_PULLOUT_WIDTH = 300

-- Bar mode's advanced gears, by the OVERRIDE SECTION each one belongs to.
-- Shaped and named after ST._APPEARANCE_SECTION_BY_ADVANCED_KEY (GroupTabsAppearance.lua),
-- and deliberately NOT the same question as ST._INDICATORS_SECTION_BY_ADVANCED_KEY
-- beside it: that map answers "which COLLAPSE section is this gear inside",
-- this one answers "which OVERRIDE section owns this gear's values".
--
-- Both bar builders sweep the WHOLE map at the foot of their build. A section
-- the lens resolved read-only builds no gear, so nothing rebound or closed an
-- advanced panel already open on it, and that panel's controls still write to
-- the table the PREVIOUS build handed them. A stale panel is just as live when
-- its gear lives on the other bars tab, so neither builder limits itself to
-- its own keys.
--
-- A gear added to any converted section belongs here the same day.
ST._BARMODE_SECTION_BY_ADVANCED_KEY = {
    barIcon = "barIcon",
    barNameText = "barNameText",
    barCooldownText = "cooldownText",
    barChargeText = "chargeText",
    barReadyText = "barReadyText",
    barAuraText = "auraText",
    barAuraStackText = "auraStackText",
    barActiveAura = "barActiveAura",
    barPandemicMarker = "pandemic",
    -- Shared with the icons Effects tab: these two gears are named by the
    -- shared builders themselves (SectionBuilders.lua), and only one panel's
    -- tabs are ever built at a time, so one entry each covers both modes.
    unusableVisual = "unusableDimming",
    tooltipBehavior = "showTooltips",
}

-- Does the active aura indicator actually RENDER for these values: enabled AND
-- at least one visible effect chosen. Declared here rather than inside
-- BuildBarActiveAuraSection because the section home below has to answer the
-- same question for a consumer that is not on this tab - one owner, so the two
-- can never drift.
local function BarAuraIndicatorRenders(read)
    local hasBorderEffect = read.barAuraEffect ~= nil
        and read.barAuraEffect ~= "color" and read.barAuraEffect ~= "none"
    local anyEffect = hasBorderEffect
        or read.barAuraPulseEnabled == true
        or read.barAuraColorShiftEnabled == true
    return ST.IsBarAuraIndicatorEnabled(read) and anyEffect
end

-- The two gates the bars tabs draw whole regions behind, named once because
-- each covers several sections below. Both mirror a builder gate exactly; the
-- gate site is cited on the sections that carry them.
local function BarsIconShown(_, style)
    return style.showBarIcon ~= false
end

-- Show Tooltips is the one row in the icon-gated States block that is NOT
-- icon-bound on an Aura Panel. An ordinary bar hangs its tooltip off the icon
-- square alone (BarMode.lua: `iconTooltips = showTooltips and showIcon`, hover
-- surface `_iconBounds`), so hiding the icon really does take the setting's
-- effect with it. An Aura Panel cell has no CC button under it at all: the aura
-- host frame is the whole cell and the only surface a tooltip can hang off, so
-- BindPanelGroup (AuraDisplay.lua) enables its mouse motion straight from
-- style.showTooltips with the bar icon nowhere in the expression. Left behind
-- the icon gate, hiding the icon there hid a control that was still live.
local function BarsTooltipRowShown(group, style)
    return ST.IsAuraPanelGroup(group) or BarsIconShown(group, style)
end

local function BarsGroupTracksAura(group)
    return GroupHasAuraTrackingEntry(group)
end

-- The Cooldown Text ROW is left out on an Aura Panel (BuildBarAppearanceTab's
-- `if not isAuraPanel`): nothing there has a cooldown, so the toggle is dead and
-- the live rows that hung off it - Duration Format, Flip Time Text and the two
-- time-text offsets - move under the aura duration text they actually place. The
-- section itself stays usable, so this is an `available` predicate rather than a
-- denial in ST.AURA_PANEL_DENIED_OVERRIDE_SECTIONS. Without it the
-- Customizations index would offer a name link onto a row that is not drawn.
local function GroupDrawsCooldownTextRow(group)
    return not ST.IsAuraPanelGroup(group)
end

-- Low Time Threshold is drawn once beside a duration surface that can consume
-- it: cooldown-side when effective cooldown text is visible, otherwise
-- aura-side while the group tracks an aura and effective aura text is visible.
-- Keep these predicates in step with the icon-mode twins in
-- GroupTabsAppearance.lua: both modes edit the same durationLowTime policy.
local function BarsDrawCooldownDurationRows(group, style)
    return not ST.IsAuraPanelGroup(group)
        and style and style.showCooldownText == true
end

local function BarsDrawAuraDurationRows(group, style)
    return BarsGroupTracksAura(group)
        and style and style.showAuraText ~= false
end

local function BarsDrawDurationRows(group, style)
    return BarsDrawCooldownDurationRows(group, style)
        or BarsDrawAuraDurationRows(group, style)
end

-- Where each bars override section is EDITED, now that the panel tabs are the
-- lens onto a selected entry: the tab that draws it and the collapse key of the
-- section it is drawn in. Per-MODE axis, because the same section id is drawn
-- somewhere else entirely on an icons panel.
--
-- This file loads BEFORE GroupTabsAppearance.lua (the .toc), which declares the `icons`
-- axis the same way, so the table is created here and that file's own `or {}`
-- keeps it. Neither axis assignment can clobber the other.
--
-- No collapseKey where a section has no collapsible of its own: the four bar
-- colors sit in a heading-less grid that is always drawn, so there is nothing
-- to uncollapse on the way to them.
--
-- OPTIONAL PREDICATES - the contract for every mode's axis, stated here because
-- this file registers the first one (.toc order):
--
--   available(group, style)   - is the section DRAWN at all on that tab, for
--                               this group and this entry's effective style?
--   gearEnabled(group, style) - would that section's advanced gear be BUILT
--                               there?
--
-- `style` is the entry's DETACHED EFFECTIVE style (ST._ResolveStyleLens'
-- `lens.effective`), which is exactly what a builder's own `sec.read` resolves
-- to under an entry lens.
--
-- Registered ONLY where a builder has a gate; a missing predicate means
-- "always". The BUILDERS' inline gates remain the authority - these mirror
-- them for a consumer that cannot see the tab, and each is a one-liner copied
-- from the gate it cites so drift shows up in a diff.
--
-- The consumer is the entry Settings pane's Customizations list (Helpers.lua):
-- it gates a row's name LINK on `available`, because a click landing on a tab
-- that never draws the section goes nowhere, and its advanced gear on both,
-- because a gear queues a panel that a gear which was never built can never
-- consume.
--
-- gearEnabled mirrors AddAdvancedToggle's own gate, which hides the gear on an
-- EXACT `false` and builds it for nil - so each one is its call site's
-- isEnabled expression tested `~= false`, copied rather than simplified.
--
-- Only sections the entry has CUSTOMIZED are ever asked, so a builder reading
-- `sec.tbl` (the override store) and one reading `sec.read` (the effective
-- style) agree about that section's own keys: promotion copies them across.
ST._SECTION_HOME = ST._SECTION_HOME or {}
ST._SECTION_HOME.bars = {
    barColor = { tab = "appearance" },
    barBgColor = { tab = "appearance" },
    barCooldownColor = { tab = "appearance" },
    barChargeColor = { tab = "appearance" },
    borderSettings = { tab = "appearance", collapseKey = "barappearance_border" },
    -- Icon Tint is drawn only while the icon renders for the current selection
    -- (BuildBarAppearanceTab's `iconVisSec.read.showBarIcon ~= false`).
    iconTint = {
        tab = "appearance", collapseKey = "barappearance_iconTint",
        available = BarsIconShown,
    },
    barIcon = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
        gearEnabled = function(_, style) return (style.showBarIcon ~= false) ~= false end,
    },
    barNameText = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
        gearEnabled = function(_, style) return (style.showBarNameText ~= false) ~= false end,
    },
    cooldownText = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
        available = GroupDrawsCooldownTextRow,
        gearEnabled = function(_, style) return (style.showCooldownText) ~= false end,
    },
    durationLowTime = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
        available = BarsDrawDurationRows,
    },
    chargeText = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
        gearEnabled = function(_, style) return (style.showChargeText ~= false) ~= false end,
    },
    barReadyText = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
        gearEnabled = function(_, style) return (style.showBarReadyText) ~= false end,
    },
    -- The bar aura block is drawn only while the GROUP tracks an aura.
    auraText = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
        available = BarsGroupTracksAura,
        gearEnabled = function(_, style) return (style.showAuraText ~= false) ~= false end,
    },
    auraStackText = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
        available = BarsGroupTracksAura,
        gearEnabled = function(_, style) return (style.showAuraStackText ~= false) ~= false end,
    },
    -- Icon Zoom is edited inside the Show Icon gear's advanced panel in bar
    -- mode, so its home is that gear's section.
    iconZoom = { tab = "appearance", collapseKey = "barappearance_textIcon" },
    -- The bar-host slice of While Aura Active (aura icon swap + active-state
    -- desaturate; the keep-swipe/keep-text keys are icons-only in effect).
    -- Both rows render on the icon square, so the section is drawn only while
    -- that icon renders for the current selection, same as Icon Tint.
    whileAuraActive = {
        tab = "appearance", collapseKey = "barappearance_whileAuraActive",
        available = function(group, style)
            return BarsGroupTracksAura(group) and BarsIconShown(group, style)
        end,
    },
    barActiveAura = {
        tab = "effects", collapseKey = EFFECTS_GLOWS_SECTION,
        available = BarsGroupTracksAura,
        gearEnabled = function(_, style) return BarAuraIndicatorRenders(style) ~= false end,
    },
    pandemic = {
        tab = "effects", collapseKey = EFFECTS_PANDEMIC_SECTION,
        available = BarsGroupTracksAura,
        -- One gear on this section in bar mode (barPandemicMarker), so the
        -- list can resolve it while the marker's aura-duration-text surface
        -- renders - unlike icons, where the glow and the marker are two and
        -- the row carries none. The fill half remains available independently.
        gearEnabled = function(group, style)
            return BarsDrawAuraDurationRows(group, style)
                and style.pandemicMarkerMode ~= "off"
        end,
    },
    -- The Timers and States sections are drawn only while the bar icon renders
    -- for the current selection (BuildBarEffectsTab's
    -- `effIconSec.read.showBarIcon ~= false`): everything in them renders on
    -- the icon square.
    showGCDSwipe = {
        tab = "effects", collapseKey = EFFECTS_TIMERS_SECTION,
        available = BarsIconShown,
    },
    desaturation = {
        tab = "effects", collapseKey = EFFECTS_STATES_SECTION,
        available = BarsIconShown,
    },
    -- Its own section (owner ruling 2026-08-16); the row draws only while the
    -- bar icon renders AND the group tracks an aura.
    auraMissingDesaturation = {
        tab = "effects", collapseKey = EFFECTS_STATES_SECTION,
        available = function(group, style)
            return BarsIconShown(group, style) and BarsGroupTracksAura(group)
        end,
    },
    unusableDimming = {
        tab = "effects", collapseKey = EFFECTS_STATES_SECTION,
        available = BarsIconShown,
        gearEnabled = function(_, style) return (style.showUnusable == true) ~= false end,
    },
    showOutOfRange = {
        tab = "effects", collapseKey = EFFECTS_STATES_SECTION,
        available = BarsIconShown,
    },
    lossOfControl = {
        tab = "effects", collapseKey = EFFECTS_STATES_SECTION,
        available = BarsIconShown,
    },
    -- Not BarsIconShown: on an Aura Panel this row is drawn outside the icon
    -- gate, so its Customizations link and gear stay reachable with the bar icon
    -- hidden (BuildBarEffectsTab's `barIconShown or isAuraPanel`).
    showTooltips = {
        tab = "effects", collapseKey = EFFECTS_STATES_SECTION,
        available = BarsTooltipRowShown,
        gearEnabled = function(_, style) return (style.showTooltips == true) ~= false end,
    },
}

-- Cooldown text advanced, as a descriptor.
--
-- The preview command center's gear opens the advanced panels behind the
-- preview it names without going through their gears (owner ruling
-- 2026-07-26), which for a bar-mode cooldown is this one - and its gear sits
-- inside the "Text & Icon" collapsible, so it is not always built. The tab
-- below calls the same factory, so the panel has exactly one definition.
--
-- The style table is resolved inside `build`, never captured: a panel the
-- command center opened has no gear on screen to rebind its descriptor, so a
-- wholesale style replacement that keeps the same context (an imported panel
-- can assign a fresh group.style outright) would leave a captured table
-- orphaned and every control writing into nothing.
--
-- A caller whose values do NOT live in the group style passes its own table
-- (`styleTable`): with an entry selected, the style lens hands this tab that
-- entry's override store for the sections it owns, and there is no resolver for
-- those. Only a caller that rebinds every refresh may do this - which the tab
-- builder does, and the command center's tab-less opens do not.
local function ResolveSelectedGroupStyle()
    local groupId = CS.selectedGroup
    local profile = groupId and CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    return group and group.style or nil
end

local function MakeBarCooldownTextAdvancedDescriptor(styleTable)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    -- Panel scope hands this factory NO table, so the panel keeps resolving the
    -- live group style itself; a table means the panel is editing one entry's
    -- override store instead.
    local isEntryOverride = styleTable ~= nil
    return {
        settingKey = "barCooldownText",
        title = "Cooldown Text Advanced",
        build = function(panel)
            local style = styleTable or ResolveSelectedGroupStyle()
            if not style then
                return
            end

            -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow
            -- column, so every row goes straight onto the panel scroll and each
            -- shared builder runs with { row = true } and no rightColumn.
            --
            -- Flip Time Text and the two offsets are NOT cooldownText keys
            -- (ST.OVERRIDE_SECTIONS in Defaults.lua): they are bar-wide, and
            -- the time text position is shared with ready text. So they are
            -- drawn only while this panel edits the panel style. Writing them
            -- into an entry's override store would leave keys behind that
            -- RevertSection cannot clear. Duration Format has the same problem
            -- and answers it the other way: it stays panel-owned and labeled
            -- rather than hidden (see the row in the Text section).
            if not isEntryOverride then
                local flipTimeRow = AddCheckboxRow(panel, {
                    label = "Flip Time Text",
                    value = style.barTimeTextReverse or false,
                    onChange = function(val)
                        style.barTimeTextReverse = val or nil
                        refreshStyle()
                    end,
                })

                -- (?) tooltip for Flip Time Text. Anchor args are a placeholder -
                -- AnchorRowBadge re-points the button onto the end of the label.
                AnchorRowBadge(flipTimeRow, CreateInfoButton(flipTimeRow.frame, flipTimeRow.frame, "LEFT", "LEFT", 0, 0, {
                    "Flip Time Text",
                    {"Applies to all time-based text, including cooldown time and ready text.", 1, 1, 1, true},
                }, flipTimeRow))
            end

            AddFontControls(panel, style, "cooldown", {sizeMin = 6, sizeMax = 24}, refreshStyle, { row = true })
            -- deferCommit is deliberately absent, matching the stock color-picker
            -- call this row replaced.
            AddColorRow(panel, {
                label = "Font Color",
                tbl = style,
                key = "cooldownFontColor",
                default = {1, 1, 1, 1},
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })
            if not isEntryOverride then
                AddOffsetSliders(panel, style, "barCdTextOffsetX", "barCdTextOffsetY", {range = 50}, refreshStyle, { row = true })
            end
        end,
    }
end

local function BuildBarAppearanceTab(container, group, style)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end

    -- STYLE LENS (Helpers.lua). With an entry selected the sections below stop
    -- being the panel's settings and become a view of that entry's EFFECTIVE
    -- ones, with per-section scope deciding where - or whether - they write.
    -- Resolved ONCE here and handed to every section, so one tab cannot
    -- disagree with itself about which entry it is showing.
    --
    -- The write table is the whole gate: nil means the section is INERT, so its
    -- rows go in read-only, it builds no gear, and no callback of its own can
    -- reach a saved table. The scope chrome is attached LAST on a row (after
    -- the gear, after any info button, after the row's disabled state is
    -- final), because it is the one control that stays live in an inert
    -- section - the way back out of it.
    local lens = ResolveStyleLens(group)

    -- An Aura Panel bar draws no cooldown text (nothing on it has a cooldown),
    -- so the Text & Icon section drops that toggle and re-homes the rows under
    -- it that DO still work - Duration Format, Flip Time Text and the two
    -- time-text offsets - under the aura duration text they actually place
    -- (owner ruling 2026-08-15).
    local isAuraPanel = ST.IsAuraPanelGroup(group)

    -- Under a multi selection this tab edits the PANEL, and only this line says
    -- so - the per-section scope chrome speaks under an entry lens alone. No-op
    -- in every other lens mode.
    AddLensPanelScopeNote(container, lens)

    -- Sections with NO override identity of their own (bar geometry, the bar
    -- texture): an entry cannot own them, so under an entry lens they say
    -- "Applies to all entries" and go read-only rather than quietly letting a
    -- panel-wide edit be made from an entry's page. They keep reading and
    -- writing the PANEL style, which is the value they claim to apply to; the
    -- rows are disabled, so no callback of theirs can run. They begin a lens
    -- section with a nil sectionId, which resolves to no write table exactly
    -- under an entry lens.

    -- ================================================================
    -- Bar Settings (length, height, spacing, texture)
    -- ================================================================
    -- Panel-only under an entry lens, so the collapse key is lens-scoped and
    -- opens folded the first time (ST._ResolveLensCollapseKey owns that rule).
    local barSettingsHeading, barSettingsCollapsed = BuildCollapsibleSection(container, "Bar Settings",
        ResolveLensCollapseKey(lens, group, nil, "barappearance_settings"), nil, nil, ROW_SECTION)
    -- Panel-only (sectionId nil). Safe with no entry selected: panel and multi
    -- scope attach no chrome at all.
    local barSettingsSec = BeginLensSection(lens, group, nil)
    barSettingsSec:HeadingChrome(barSettingsHeading)

    if not barSettingsCollapsed then
    -- LEFT column: how one bar is shaped. RIGHT column: how the bars sit
    -- together and what they are drawn with.
    local barLeft, barRight = BeginRowGrid(container)
    -- The columns only exist here, so the section's brackets are taken now
    -- rather than at Begin; it fills two, so the right one is a bracket of its
    -- own.
    barSettingsSec:Mark(barLeft)
    local barRightBracket = barSettingsSec:Bracket(barRight)

    AddSliderRow(barLeft, {
        label = "Bar Length",
        min = 10, max = 500, step = 0.1,
        value = style.barLength or 180,
        disabled = barSettingsSec.disabled,
        onChange = function(val)
            ST._PreviewScalarSetting(style, "barLength", val, ST._RefreshSelectedButtonsPreview)
        end,
        onRelease = function(val)
            style.barLength = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })

    AddSliderRow(barLeft, {
        label = "Bar Height",
        min = 5, max = 100, step = 0.1,
        value = style.barHeight or 20,
        disabled = barSettingsSec.disabled,
        onChange = function(val)
            ST._PreviewScalarSetting(style, "barHeight", val, ST._RefreshSelectedButtonsPreview)
        end,
        onRelease = function(val)
            style.barHeight = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })

    if group.buttons and #group.buttons > 1 then
        AddSliderRow(barRight, {
            label = "Bar Spacing",
            min = -10, max = 100, step = 0.1,
            value = style.buttonSpacing or ST.BUTTON_SPACING,
            disabled = barSettingsSec.disabled,
            onChange = function(val)
                ST._PreviewScalarSetting(style, "buttonSpacing", val, ST._RefreshSelectedButtonsPreview)
            end,
            onRelease = function(val)
                style.buttonSpacing = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
    end

    -- MEDIA ROW - the same recipe the font rows follow (stated in full at
    -- AddFontControls' row branch): the row is created with a label and a
    -- widened pullout but NO list and NO onChange, then handed to the shared
    -- bar-texture helpers exactly as a stock Dropdown would be.
    -- CDC-DropdownRow forwards SetList and SetDisabled to its embedded child,
    -- which is everything SetupBarTextureDropdown touches, and AddDropdownRow
    -- registers OnValueChanged only when opts.onChange is given - so the
    -- callback helper is the one registration and the profile-wide bar texture
    -- lock still gates every write. The value is set AFTER the setup call,
    -- because SetList rebuilds the list the displayed text is read from.
    --
    -- The read-only pass runs after all of that (the bracket close below), so
    -- the lock's own SetDisabled and the lens' cannot fight over the row.
    local barTexRow = AddDropdownRow(barRight, {
        label = "Bar Texture",
        pulloutWidth = BAR_TEXTURE_PULLOUT_WIDTH,
    })
    CS.SetupBarTextureDropdown(barTexRow)
    barTexRow:SetValue(style.barTexture or "Solid")
    CS.SetBarTextureDropdownCallback(barTexRow, function(widget, event, val)
        style.barTexture = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    barSettingsSec:Finish()
    barSettingsSec:FinishBracket(barRightBracket)
    end -- not barSettingsCollapsed

    -- Bar colors have no heading and no collapse state, so they stay on screen
    -- while Bar Settings is folded away. They get a grid of their own, which is
    -- also what keeps them off the section's last line.
    -- LEFT column: the bar at rest - its fill and the backdrop behind it.
    -- RIGHT column: the colors a timer paints over that. The aura timer color
    -- is one of them, so it lives here rather than beside the aura TEXT toggles
    -- in Text & Icon, and it carries that section's aura-tracking gate with it.
    local colorLeft, colorRight = BeginRowGrid(container)

    -- Each bar color is a one-key override section of its own, so each row
    -- resolves its own scope and wears its own chrome. A single row needs no
    -- inert bracket: `disabled` is the whole gate (no gear, no child rows), and
    -- the chrome that undoes it is attached after.
    --
    -- The row edits its table in place, so it is handed the section's WRITE
    -- table - the group style, the entry's override store, or, inert, the
    -- read-only snapshot whose stray writes go nowhere by design. Promotion
    -- copies the section's keys across (PromoteSection), so a customized read
    -- finds real values rather than the row's fallback default.
    local function AddBarColorRow(column, sectionId, label, key, default)
        local sec = BeginLensSection(lens, group, sectionId)
        local row = AddColorRow(column, {
            label = label,
            tbl = sec.tbl, key = key,
            default = default, hasAlpha = true,
            disabled = sec.disabled,
            onConfirm = refreshStyle, onChange = refreshStyle,
        })
        sec:Chrome(row)
        return row
    end

    -- The bar at rest. An Aura Panel bar has no resting state: the panel
    -- materializes no CC buttons, so barColor never paints anything - the only
    -- fill is the aura kit's, and that reads barAuraColor alone
    -- (StyleActiveBarFill, AuraDisplay.lua). The backdrop still shows, so
    -- Bar Background Color stays.
    if CanGroupUseOverrideSection(group, "barColor") then
        AddBarColorRow(colorLeft, "barColor", "Bar Color", "barColor", {0.2, 0.6, 1.0, 1.0})
    end
    AddBarColorRow(colorLeft, "barBgColor", "Bar Background Color", "barBgColor", {0.1, 0.1, 0.1, 0.8})
    -- The two colors a spell TIMER paints. An Aura Panel bar has no cooldown and
    -- no recharge to paint, so the right column starts at the aura timer color.
    if CanGroupUseOverrideSection(group, "barCooldownColor") then
        AddBarColorRow(colorRight, "barCooldownColor", "Bar Cooldown Color", "barCooldownColor", {0.6, 0.6, 0.6, 1.0})
        AddBarColorRow(colorRight, "barChargeColor", "Bar Recharging Color", "barChargeColor", {1.0, 0.82, 0.0, 1.0})
    end

    -- The color the aura timer drains in. Same gate as the aura block down in
    -- Text & Icon, so it appears only while the group tracks an aura.
    --
    -- barAuraColor belongs to the barActiveAura section, whose home is the
    -- Effects tab's Active Aura Indicator row - so this row FOLLOWS that
    -- section's scope and carries no chrome of its own, the way the pandemic
    -- marker row follows the pandemic enable row. One section, one affordance.
    if GroupHasAuraTrackingEntry(group) then
        local auraColorSec = BeginLensSection(lens, group, "barActiveAura")
        AddColorRow(colorRight, {
            label = "Bar Aura Timer Color",
            tbl = auraColorSec.tbl, key = "barAuraColor",
            default = {0.2, 1.0, 0.2, 1.0}, hasAlpha = true,
            disabled = auraColorSec.disabled,
            onConfirm = refreshStyle, onChange = refreshStyle,
        })
    end

    -- ================================================================
    -- Border (thickness, size, color - mirrors the icon-mode Border section)
    -- ================================================================
    -- The whole collapsible IS the borderSettings section, so its collapse key
    -- follows that section's scope through ST._ResolveLensCollapseKey.
    local borderHeading, borderCollapsed = BuildCollapsibleSection(container, "Border",
        ResolveLensCollapseKey(lens, group, "borderSettings", "barappearance_border"), nil, nil, ROW_SECTION)
    local borderSec = BeginLensSection(lens, group, "borderSettings")
    borderSec:HeadingChrome(borderHeading)

    if not borderCollapsed then
    -- Three related rows, so they stay in one column rather than splitting a
    -- parent from its children. The right column is deliberately empty.
    local borderLeft = BeginRowGrid(container)
    -- The column only exists here, so the section's bracket is taken now rather
    -- than at Begin.
    borderSec:Mark(borderLeft)

    -- The shared builder reads and writes ONE table, so it is handed the
    -- section's WRITE table with the panel style behind it in opts - the
    -- styleTable + fallbackStyle pair a customized section passes - or, inert,
    -- the read-only snapshot. The lens draws one shape for both scopes.
    BuildBorderControls(borderLeft, borderSec.tbl, refreshStyle, {
        row = true,
        fallbackStyle = borderSec.fallbackStyle,
    })

    borderSec:Finish()
    end -- not borderCollapsed

    -- ================================================================
    -- Icon Tint (the bar's icon square)
    --
    -- Drawn only while the icon actually renders for the CURRENT SELECTION,
    -- the same gate the Effects tab's icon-square sections use. showBarIcon
    -- is itself a per-entry key (the barIcon section), so the gate reads
    -- through the lens: a panel that hides icons can still select an entry
    -- that shows its own, and that entry's tint controls must not vanish
    -- with the panel's toggle. The tint pipeline is the shared one
    -- (ButtonFrame/Tracking.lua serves both display modes), so the rows come
    -- from the same shared builder the icons tab calls, in "bars" mode - minus
    -- Background Color, which the bar icon does not render (its backdrop is
    -- Bar Background Color above).
    -- ================================================================
    local iconVisSec = BeginLensSection(lens, group, "barIcon")
    if iconVisSec.read.showBarIcon ~= false then
    local iconTintHeading, iconTintCollapsed = BuildCollapsibleSection(container, "Icon Tint",
        ResolveLensCollapseKey(lens, group, "iconTint", "barappearance_iconTint"), nil, nil, ROW_SECTION)
    local tintSec = BeginLensSection(lens, group, "iconTint")

    -- The (?) badge chains off the heading label, and the lens' scope chrome
    -- lands after it: label -> (?) -> scope.
    ST._ChainHeadingBadges(iconTintHeading, CreateInfoButton(iconTintHeading.frame,
        iconTintHeading.label, "LEFT", "RIGHT", 4, 0, {
            "Icon Tint",
            {"Colors the bar's icon.", 1, 1, 1, true},
            " ",
            {"The cooldown and aura tints take over while their state is active.", 1, 1, 1, true},
        }, tabInfoButtons))
    tintSec:HeadingChrome(iconTintHeading)

    if not iconTintCollapsed then
        -- LEFT column: the always-on tint plus the cooldown pair. RIGHT
        -- column: the conditional state tints. Both columns bracket
        -- separately: an inert range is a contiguous slice of ONE column's
        -- children, and this section fills two.
        local tintLeft, tintRight = BeginRowGrid(container)

        tintSec:Mark(tintLeft)
        local tintRightBracket = tintSec:Bracket(tintRight)

        -- Rows only; the shared builder draws the same block on the icons tab.
        BuildIconTintControls(tintLeft, tintRight, tintSec, {
            mode = "bars",
            hasAuraEntry = GroupHasAuraTrackingEntry(group),
            hasCooldownState = CanGroupUseOverrideSection(group, "desaturation"),
            refresh = refreshStyle,
        })

        tintSec:Finish()
        tintSec:FinishBracket(tintRightBracket)
    end -- not iconTintCollapsed
    end -- showBarIcon (Icon Tint)

    -- ================================================================
    -- Text & Icon (per-bar display elements)
    --
    -- The collapse key is load-bearing: the preview command center's text and
    -- cooldown routes name it (PreviewCommandCenter's BAR_TEXT_SECTION) so a
    -- queued gear inside this section is uncollapsed on the way past.
    -- ================================================================
    local _, textIconCollapsed = BuildCollapsibleSection(container, "Text & Icon", "barappearance_textIcon", nil, nil, ROW_SECTION)

    if not textIconCollapsed then
    -- LEFT column: what every bar can draw, top to bottom as it reads on the
    -- bar itself. RIGHT column: the aura block (gated on the group tracking an
    -- aura, so this column can run short - the grid top-aligns its columns) and
    -- the panel-level packing toggle.
    local textLeft, textRight = BeginRowGrid(container)

    -- Dedicated override section (owner ruling 2026-08-25): one shared policy
    -- for cooldown and aura duration phases, customized as one entry-owned
    -- unit. The master row carries the section's scope affordance.
    local function AddDurationLowTimeSection(column)
        if not ST._AddDurationLowTimeRows then return end
        local lowTimeSec = BeginLensSection(lens, group, "durationLowTime", { column = column })
        local rows = ST._AddDurationLowTimeRows(column, lowTimeSec.tbl, refreshStyle, {
            indent = true,
            explicitOff = lowTimeSec.scope == "customized",
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
    end

    local panelDurationStyle = group.style or {}
    local effectiveDurationStyle = (lens and lens.effective) or panelDurationStyle
    local drawsCooldownLowTime = BarsDrawCooldownDurationRows(group, effectiveDurationStyle)
    local drawsAuraLowTime = BarsDrawAuraDurationRows(group, effectiveDurationStyle)
    -- Duration Format is panel-owned. Keep it reachable when either the panel
    -- default or the selected entry still has a duration consumer; an entry
    -- override must not strand a setting that remains live on other entries.
    local drawsCooldownFormat = BarsDrawCooldownDurationRows(group, panelDurationStyle)
        or drawsCooldownLowTime
    local drawsAuraFormat = BarsDrawAuraDurationRows(group, panelDurationStyle)
        or drawsAuraLowTime

    -- ================================================================
    -- Show Icon
    -- ================================================================
    local iconSec = BeginLensSection(lens, group, "barIcon", { column = textLeft })

    local showIconRow = AddCheckboxRow(textLeft, {
        label = "Show Icon",
        value = iconSec.read.showBarIcon ~= false,
        disabled = iconSec.disabled,
        onChange = function(val)
            if not iconSec.write then return end
            iconSec.write.showBarIcon = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- the rows go straight onto the panel scroll and Icon Size indents under the
    -- toggle that gates it.
    --
    -- The panel captures the section's WRITE table - the group style, or the
    -- selected entry's override store - and reads its starting values from the
    -- section's READ table. Built only while there is a write table: an inert
    -- section has no gear to open it from.
    local function BuildBarIconAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Flip Icon Side",
            value = iconSec.read.barIconReverse or false,
            onChange = function(val)
                -- An override store needs the explicit false: nil DELETES the
                -- key and the entry falls back to the panel value, so a
                -- customized entry could never turn this OFF against a panel
                -- that has it on. Panel scope keeps nil-for-false (the lean
                -- saved default).
                iconSec.write.barIconReverse = iconSec:BoolValue(val)
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        AddSliderRow(panel, {
            label = "Icon Offset",
            min = -5, max = 50, step = 0.1,
            value = iconSec.read.barIconOffset or 0,
            onChange = function(val)
                ST._PreviewScalarSetting(iconSec.write, "barIconOffset", val, ST._RefreshSelectedButtonsPreview)
            end,
            onRelease = function(val)
                iconSec.write.barIconOffset = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })

        AddCheckboxRow(panel, {
            label = "Custom Icon Size",
            value = iconSec.read.barIconSizeOverride or false,
            onChange = function(val)
                iconSec.write.barIconSizeOverride = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if iconSec.read.barIconSizeOverride then
            AddSliderRow(panel, {
                label = "Icon Size",
                indent = true,
                min = 5, max = 100, step = 0.1,
                value = iconSec.read.barIconSize or 20,
                onChange = function(val)
                    ST._PreviewScalarSetting(iconSec.write, "barIconSize", val, ST._RefreshSelectedButtonsPreview)
                end,
                onRelease = function(val)
                    iconSec.write.barIconSize = val
                    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                end,
            })
        end

        -- Icon Zoom is its OWN override section (iconZoom), not part of
        -- barIcon, so it resolves its own scope rather than riding this panel's
        -- table: a zoom written into the override store while iconZoom is not
        -- owned would apply to the entry with no section to revert it. While
        -- the entry inherits it the row shows the effective zoom read-only, and
        -- the row's own scope chrome below is the way to take that section over.
        local zoomSec = BeginLensSection(lens, group, "iconZoom", { column = panel })
        local zoomRow = ST._BuildIconZoomControls(panel, zoomSec.tbl, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, {
            disabled = zoomSec.disabled,
            previewRefresh = function()
                if ST._RefreshButtonsPreviewMirror then
                    ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
                end
            end,
        })
        -- The row carries its own scope chrome, exactly as it does on the icons
        -- tab: it is the only affordance for this section here, and without it
        -- an inherited zoom would be a greyed row inside a panel with no way
        -- out. Clicking it rebuilds the config, which rebinds this panel.
        zoomSec:Chrome(zoomRow)
        zoomSec:Finish()
    end

    if iconSec.write then
        AddAdvancedToggle(showIconRow, "barIcon", tabInfoButtons, iconSec.read.showBarIcon ~= false, {
            title = "Bar Icon Advanced",
            build = BuildBarIconAdvanced,
        })
    end
    iconSec:Chrome(showIconRow)

    iconSec:Finish()

    -- Show Name Text toggle
    local nameSec = BeginLensSection(lens, group, "barNameText", { column = textLeft })

    local showNameRow = AddCheckboxRow(textLeft, {
        label = "Show Name Text",
        value = nameSec.read.showBarNameText ~= false,
        disabled = nameSec.disabled,
        onChange = function(val)
            if not nameSec.write then return end
            nameSec.write.showBarNameText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
    local function BuildBarNameTextAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Flip Name Text",
            value = nameSec.read.barNameTextReverse or false,
            onChange = function(val)
                -- Explicit false for an override store; see Flip Icon Side.
                nameSec.write.barNameTextReverse = nameSec:BoolValue(val)
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })

        AddFontControls(panel, nameSec.write, "barName", {sizeMin = 6, sizeMax = 24, size = 10}, refreshStyle, { row = true })
        -- deferCommit is deliberately absent, matching the stock color-picker call
        -- this row replaced.
        AddColorRow(panel, {
            label = "Font Color",
            tbl = nameSec.write,
            key = "barNameFontColor",
            default = {1, 1, 1, 1},
            hasAlpha = true,
            onConfirm = refreshStyle,
            onChange = refreshStyle,
        })
        -- barNameTextOffsetX/Y are not one of this section's override keys, so
        -- the rows are openly PANEL-OWNED: they read and write group.style
        -- whatever the lens shows, and stay live when an entry owns the
        -- section. They used to hide themselves once the section was
        -- customized, which stranded the setting on some other selection
        -- state. Duration Format answers the same problem the same way (see
        -- the row in the Text section).
        local offsetXRow, offsetYRow = AddOffsetSliders(panel, group.style, "barNameTextOffsetX", "barNameTextOffsetY", {range = 50}, refreshStyle, { row = true })
        nameSec:PanelRowChrome(offsetXRow)
        nameSec:PanelRowChrome(offsetYRow)
    end

    if nameSec.write then
        AddAdvancedToggle(showNameRow, "barNameText", tabInfoButtons, nameSec.read.showBarNameText ~= false, {
            title = "Name Text Advanced",
            build = BuildBarNameTextAdvanced,
        })
    end
    nameSec:Chrome(showNameRow)

    nameSec:Finish()

    -- Show Cooldown Text toggle. An Aura Panel bar has no cooldown to count
    -- down, so the toggle itself is dead there and is left out; everything live
    -- that hung off it (Duration Format, Flip Time Text, the two time-text
    -- offsets) moves into the aura duration text section on the right.
    if not isAuraPanel then
    local cdTextSec = BeginLensSection(lens, group, "cooldownText", { column = textLeft })

    local showTimeRow = AddCheckboxRow(textLeft, {
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
        local barCdTextAdvanced = MakeBarCooldownTextAdvancedDescriptor(
            cdTextSec.scope == "customized" and cdTextSec.write or nil)

        AddAdvancedToggle(showTimeRow, barCdTextAdvanced.settingKey, tabInfoButtons, cdTextSec.read.showCooldownText, {
            title = barCdTextAdvanced.title,
            build = barCdTextAdvanced.build,
        })
    end
    cdTextSec:Chrome(showTimeRow)

    -- The inert sweep is taken HERE, ahead of Duration Format, so the sweep
    -- covers the rows above and leaves that one live (ApplyInertRange walks the
    -- column from the mark at call time).
    cdTextSec:Finish()

    -- Duration Format sits with the effective cooldown text it formats. Ready
    -- Text is a fixed label, not a duration consumer, so it does not keep this
    -- row alive by itself.
    --
    -- durationFormat is not one of the Cooldown Text section's override keys, so
    -- the row is openly PANEL-OWNED: it reads and writes group.style whatever
    -- the lens shows, stays live when an entry owns the section, and wears the
    -- grey "Panel setting" label there. It used to hide itself once the section
    -- was customized, which stranded the setting on some other selection state.
    -- The icons tab draws it the same way (GroupTabsAppearance.lua).
    if drawsCooldownFormat then
        local durationFormatRow = AddDurationFormatDropdown(textLeft, group.style, refreshStyle, { row = true })
        if durationFormatRow then
            cdTextSec:PanelRowChrome(durationFormatRow)
        end
    end
    if drawsCooldownLowTime then
        AddDurationLowTimeSection(textLeft)
    end
    end -- not isAuraPanel

    -- Show Charge Text toggle. Charges and uses are spell mechanics, so an Aura
    -- Panel never counts anything here; the aura's own stack count is the Show
    -- Aura Stack Text row.
    if CanGroupUseOverrideSection(group, "chargeText") then
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

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
    --
    -- The three count colors are the panel's longest labels. They end in a 19px
    -- swatch, the narrow control the row grammar reserves long labels for, and
    -- each states itself on hover so a narrower config column cannot silently
    -- swallow which charge state it names.
    --
    -- deferCommit is deliberately absent throughout, matching the stock color-picker
    -- calls these rows replaced.
    local function BuildBarChargeTextAdvanced(panel)
        AddFontControls(panel, chargeSec.write, "charge", {}, refreshStyle, { row = true })

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
        AddOffsetSliders(panel, chargeSec.write, "chargeXOffset", "chargeYOffset", {x = -2, y = 2}, refreshStyle, { row = true })
    end

    if chargeSec.write then
        AddAdvancedToggle(chargeTextRow, "barChargeText", tabInfoButtons, chargeSec.read.showChargeText ~= false, {
            title = "Count Text Advanced",
            build = BuildBarChargeTextAdvanced,
        })
    end
    chargeSec:Chrome(chargeTextRow)

    chargeSec:Finish()
    end -- CanGroupUseOverrideSection chargeText

    -- Show Ready Text toggle. "Ready" is the off-cooldown state, so an Aura
    -- Panel bar never reaches it.
    if CanGroupUseOverrideSection(group, "barReadyText") then
    local readySec = BeginLensSection(lens, group, "barReadyText", { column = textLeft })

    local showReadyRow = AddCheckboxRow(textLeft, {
        label = "Show Ready Text",
        value = readySec.read.showBarReadyText or false,
        disabled = readySec.disabled,
        onChange = function(val)
            if not readySec.write then return end
            readySec.write.showBarReadyText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn. The
    -- CDC-EditBoxRow embeds a stock EditBox, so the raw frame the Instructions
    -- text hangs on is still reachable through row.editbox.
    local function BuildBarReadyTextAdvanced(panel)
        local readyRow = AddEditBoxRow(panel, {
            label = "Ready Text",
            value = readySec.read.barReadyText or "Ready",
            onEnterPressed = function(val)
                readySec.write.barReadyText = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
        if readyRow.editbox and readyRow.editbox.Instructions then
            readyRow.editbox.Instructions:Hide()
        end

        -- deferCommit is deliberately absent, matching the stock color-picker call
        -- this row replaced.
        AddColorRow(panel, {
            label = "Ready Text Color",
            tbl = readySec.write,
            key = "barReadyTextColor",
            default = {0.2, 1.0, 0.2, 1.0},
            hasAlpha = true,
            onConfirm = refreshStyle,
            onChange = refreshStyle,
        })
        AddFontControls(panel, readySec.write, "barReady", {sizeMin = 6, sizeMax = 24}, refreshStyle, { row = true })
    end

    if readySec.write then
        AddAdvancedToggle(showReadyRow, "barReadyText", tabInfoButtons, readySec.read.showBarReadyText, {
            title = "Ready Text Advanced",
            build = BuildBarReadyTextAdvanced,
        })
    end
    readySec:Chrome(showReadyRow)

    readySec:Finish()
    end -- CanGroupUseOverrideSection barReadyText

    -- Bar aura block: the aura text toggles. Shown only while the GROUP has an
    -- aura-tracking entry (same gate as the icon-side aura sections, and as the
    -- Bar Aura Timer Color row up with the other bar colors). The gate stays on
    -- the group: with an entry selected that tracks no aura, the rows are still
    -- drawn and the lens resolves them "not available" for that entry, which is
    -- what states the reason rather than hiding it. Style edits route through
    -- refreshStyle -> UpdateGroupStyle -> RequestAuraRebind, which defers to
    -- combat end with the one-time note when needed.
    if GroupHasAuraTrackingEntry(group) then
        -- Aura duration text: rendered by the aura display at the bar's time
        -- text position (it follows the Flip Time Text and offset settings
        -- from the Cooldown Text section).
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

        -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
        -- deferCommit is deliberately absent, matching the stock color-picker call
        -- the color row replaced.
        local function BuildBarAuraTextAdvanced(panel)
            AddFontControls(panel, auraTextSec.write, "auraText", { size = 12 }, refreshStyle, { row = true })
            AddColorRow(panel, {
                label = "Font Color",
                tbl = auraTextSec.write,
                key = "auraTextFontColor",
                default = {0, 0.925, 1, 1},
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })

            -- The re-homed position rows. Same STORAGE KEYS as before - the aura
            -- display places this text from barTimeTextReverse and
            -- barCdTextOffsetX/Y (AuraDisplay.lua's bar branch) - so nothing is
            -- migrated; only where they are edited moves.
            --
            -- They write group.style rather than this section's store, exactly as
            -- they did under the Cooldown Text gear: the keys are bar-wide and
            -- belong to no override section, so a copy inside the auraText store
            -- would be keys RevertSection cannot clear. Openly PANEL-OWNED, with
            -- the grey "Panel setting" label, the way the bar name offsets and
            -- Duration Format already answer this.
            if isAuraPanel then
                local panelStyle = group.style
                local flipRow = AddCheckboxRow(panel, {
                    label = "Flip Time Text",
                    value = panelStyle.barTimeTextReverse or false,
                    onChange = function(val)
                        panelStyle.barTimeTextReverse = val or nil
                        refreshStyle()
                    end,
                })
                local offsetXRow, offsetYRow = AddOffsetSliders(panel, panelStyle, "barCdTextOffsetX", "barCdTextOffsetY", {range = 50}, refreshStyle, { row = true })
                auraTextSec:PanelRowChrome(flipRow)
                auraTextSec:PanelRowChrome(offsetXRow)
                auraTextSec:PanelRowChrome(offsetYRow)
            end
        end

        if auraTextSec.write then
            AddAdvancedToggle(auraTextRow, "barAuraText", tabInfoButtons, auraTextSec.read.showAuraText ~= false, {
                title = "Aura Duration Text Advanced",
                build = BuildBarAuraTextAdvanced,
            })
        end
        -- Second badge in the chain: gear, then this, then the scope chrome the
        -- lens attaches last. The anchor args below are a placeholder -
        -- AnchorRowBadge re-points the button onto the end of the chain.
        --
        -- On an Aura Panel the flip and offset rows live in this section's own
        -- gear, so the pointer to the Cooldown Text section would send the user
        -- to a row that is not drawn.
        AnchorRowBadge(auraTextRow, CreateInfoButton(auraTextRow.frame, auraTextRow.frame, "LEFT", "LEFT", 0, 0, isAuraPanel and {
            "Aura Duration Text",
            {"Shows the remaining aura time at the bar's time text position while the aura is active.", 1, 1, 1, true},
        } or {
            "Aura Duration Text",
            {"Shows the remaining aura time at the bar's time text position while the aura is active. Position follows the flip and offset settings in the Cooldown Text section.", 1, 1, 1, true},
        }, auraTextRow))
        auraTextSec:Chrome(auraTextRow)

        auraTextSec:Finish()

        -- Duration Format is panel-owned, so it follows either the panel's or
        -- selected entry's remaining duration surface. Low Time stays
        -- entry-effective because that override section belongs to the lens.
        if drawsAuraFormat and not drawsCooldownFormat then
            local auraFormatRow = AddDurationFormatDropdown(textRight, group.style, refreshStyle, { row = true })
            if auraFormatRow then
                auraTextSec:PanelRowChrome(auraFormatRow)
            end
        end
        if drawsAuraLowTime and not drawsCooldownLowTime then
            AddDurationLowTimeSection(textRight)
        end

        -- Aura stack text: Blizzard writes the live stack count; anchored to
        -- the icon square (or the bar with the icon hidden).
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
        local function BuildBarAuraStackTextAdvanced(panel)
            AddFontControls(panel, auraStackSec.write, "auraStack", { size = 12 }, refreshStyle, { row = true })
            -- deferCommit is deliberately absent, matching the stock color-picker
            -- call this row replaced.
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
            AddAdvancedToggle(auraStackRow, "barAuraStackText", tabInfoButtons, auraStackSec.read.showAuraStackText ~= false, {
                title = "Aura Stack Text Advanced",
                build = BuildBarAuraStackTextAdvanced,
            })
        end
        AnchorRowBadge(auraStackRow, CreateInfoButton(auraStackRow.frame, auraStackRow.frame, "LEFT", "LEFT", 0, 0, {
            "Aura Stack Text",
            {"Shows the live stack count while the aura is active, drawn by the game so it stays accurate in combat. Stack counts cannot drive the bar fill; the count is hidden from addons during combat.", 1, 1, 1, true},
        }, auraStackRow))
        auraStackSec:Chrome(auraStackRow)

        auraStackSec:Finish()
    end

    -- Compact Mode toggle + advanced (growth direction, max visible buttons).
    -- Panel-level packing with no override section, so under an entry lens it
    -- goes read-only along with the rest of the panel-only content rather than
    -- letting a panel-wide edit be made from an entry's page. Its gear is not
    -- skipped the way the lens sections' are: compact mode is group data with
    -- no second table to bind a gear to, so the inert walk disables and dims it
    -- instead (the icons tab does exactly this).
    local compactSec = BeginLensSection(lens, group, nil, { column = textRight })
    BuildCompactModeControls(textRight, group, tabInfoButtons)
    compactSec:Finish()
    end -- not textIconCollapsed

    -- ================================================================
    -- While Aura Active
    -- ================================================================
    -- The bar-host slice of the whileAuraActive section (the full section,
    -- with the Cooldown dropdown, is the icons tab's): the aura icon swap and
    -- the active-state desaturate both render on the bar's icon square. The
    -- keep-swipe/keep-text keys are icons-only in effect, so no dropdown here.
    -- Aura Panel bars keep only the Desaturate row: their entries are all
    -- standalone auras whose live icon the engine forces on.
    --
    -- Both rows render on the icon square, so the section carries the same
    -- lens-resolved icon gate the Icon Tint section above and the Effects tab's
    -- Timers/States sections use: with the icon hidden StyleSlotKit shows
    -- neither the aura icon nor its cover on a bar host, so both controls would
    -- be dead. Read through the lens because showBarIcon is itself a per-entry
    -- key - a panel that hides icons can still hold an entry that shows its own.
    -- Aura Panels are NOT excused here (unlike Show Tooltips): their cells are
    -- bar hosts too, and the kit answers barIconShown for them the same way.
    local whileAuraIconSec = BeginLensSection(lens, group, "barIcon")
    if GroupHasAuraTrackingEntry(group) and whileAuraIconSec.read.showBarIcon ~= false then
    local whileAuraHeading, whileAuraCollapsed = BuildCollapsibleSection(container, "While Aura Active",
        ResolveLensCollapseKey(lens, group, "whileAuraActive", "barappearance_whileAuraActive"), nil, nil, ROW_SECTION)
    local whileAuraSec = BeginLensSection(lens, group, "whileAuraActive")
    -- Section-owning collapsible: scope chrome on the heading, like Border's.
    whileAuraSec:HeadingChrome(whileAuraHeading)

    if not whileAuraCollapsed then
    local whileAuraLeft = BeginRowGrid(container)
    whileAuraSec:Mark(whileAuraLeft)

    -- .write first, .read as the read-only fallback - the same live-store
    -- rule the icons tab's WhileAuraFlagOn states in full.
    local function WhileAuraOn(key)
        local src = whileAuraSec.write or whileAuraSec.read
        return (src and src[key]) == true
    end

    -- Standalone and passive entries always show the live aura icon whatever
    -- this says (IsAuraIconForcedEntry), so at ENTRY SCOPE the row is left out
    -- for them - the icons twin's rule. It still draws at panel scope, where
    -- it is a default for whatever the panel holds next.
    local whileAuraLensEntry = (lens and lens.mode == "entry") and lens.buttonData or nil
    if not ST.IsAuraPanelGroup(group)
        and not (whileAuraLensEntry and CooldownCompanion:IsAuraIconForcedEntry(whileAuraLensEntry)) then
        AddCheckboxRow(whileAuraLeft, {
            label = "Show Aura Icon",
            value = WhileAuraOn("auraShowAuraIcon"),
            disabled = whileAuraSec.disabled,
            onChange = function(val)
                if not whileAuraSec.write then return end
                whileAuraSec.write.auraShowAuraIcon = whileAuraSec:BoolValue(val)
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
    end

    AddCheckboxRow(whileAuraLeft, {
        label = "Desaturate Icon",
        value = WhileAuraOn("invertAuraDesaturationLogic"),
        disabled = whileAuraSec.disabled,
        onChange = function(val)
            if not whileAuraSec.write then return end
            whileAuraSec.write.invertAuraDesaturationLogic = whileAuraSec:BoolValue(val)
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    whileAuraSec:Finish()
    end -- not whileAuraCollapsed
    end -- While Aura Active section drawn

    -- Inert-section sweep. A section the lens resolved read-only builds no
    -- gear, so nothing rebound or closed an advanced panel that was already
    -- open on that gear - and its controls still write to the table the
    -- PREVIOUS build handed them. Close those here.
    --
    -- Scope-driven, not collapse-driven: a collapsed section builds no gear
    -- either, and a panel left over from before an entry was selected is just
    -- as live behind a closed section as behind an open one.
    if CS.CloseAdvancedSettingsPanel then
        for advancedKey, sectionId in pairs(ST._BARMODE_SECTION_BY_ADVANCED_KEY) do
            local _, _, sectionWrite = ResolveLensSection(lens, group, sectionId)
            if sectionWrite == nil then
                CS.CloseAdvancedSettingsPanel({ settingKey = advancedKey })
            end
        end
    end
end

------------------------------------------------------------------------
-- EFFECTS TAB (Glows / Timers / States)
--
-- Row grammar (RowWidgets.lua), and the SAME three collapse keys the icons
-- Effects tab uses - see the note by the section constants at the top of this
-- file for why they are shared rather than bar-specific.
------------------------------------------------------------------------

-- Active aura indicator: border effect + fill effects rendered by the aura
-- kit while the tracked aura runs. The checkbox reflects whether anything
-- actually renders (enabled AND a visible effect chosen); checking it with
-- no visible effect forces the pulse border, mirroring the icon aura glow.
--
-- `container` is nil when there is nothing to draw into - the group lost its
-- last aura entry, or the Glows section is collapsed. The reconciliation below
-- still has to run in that case: an indicator that is no longer on must not
-- leave its preview glowing on the panel.
local function BuildBarActiveAuraSection(container, group, style, lens)
    if not GroupHasAuraTrackingEntry(group) then
        -- The section owning an active preview just disappeared (last aura
        -- entry removed); don't leave the preview glow orphaned.
        CooldownCompanion:SetGroupBarAuraEffectPreview(CS.selectedGroup, false)
        return
    end

    -- Read through the lens: with an entry selected this row states that
    -- entry's effective indicator, and writes only where the entry owns the
    -- section. The preview reconciliation below follows the same read, so a
    -- group preview is cleared whenever what is on screen would not render -
    -- clearing is the safe direction, and never starts anything.
    local auraSec = BeginLensSection(lens, group, "barActiveAura")

    -- Shared with this section's home entry (BarAuraIndicatorRenders at the top
    -- of this file), so the tab and a consumer that cannot see it can never
    -- disagree about whether the indicator renders.
    local indicatorOn = BarAuraIndicatorRenders(auraSec.read)

    if container then
        -- The host column only exists under this guard, so the section's
        -- bracket is taken here rather than at Begin.
        auraSec:Mark(container)

        local enableRow = AddCheckboxRow(container, {
            label = "Show Active Aura Indicator",
            value = indicatorOn,
            disabled = auraSec.disabled,
            onChange = function(val)
                if not auraSec.write then return end
                auraSec.write.barAuraIndicatorEnabled = val
                if val and not (auraSec.write.barAuraEffect and auraSec.write.barAuraEffect ~= "color" and auraSec.write.barAuraEffect ~= "none"
                    or auraSec.write.barAuraPulseEnabled == true or auraSec.write.barAuraColorShiftEnabled == true) then
                    -- Nothing visible was configured; force the pulse border and
                    -- reset its per-style keys (a leftover proc-scale size would
                    -- render a 30px wall).
                    auraSec.write.barAuraEffect = "pulse"
                    auraSec.write.barAuraEffectSize = 2
                    auraSec.write.barAuraEffectSpeed = 0.5
                end
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Single rail (AdvancedSettingsPanel.lua): this builder's row path opens
        -- its own two-column grid, which a ~330px panel has no room for, so
        -- opts.singleRail suppresses it and rails the border effect and the two
        -- fill effects onto the panel scroll in order.
        --
        -- The panel captures the section's WRITE table with the panel style
        -- behind it in opts - the styleTable + fallbackStyle pair a customized
        -- section passes. The section's enable toggle lives on the row above,
        -- never in the shared builder.
        local function BuildBarActiveAuraAdvanced(panel)
            BuildBarActiveAuraControls(panel, auraSec.write, function()
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end, {
                row = true,
                singleRail = true,
                infoButtons = tabInfoButtons,
                fallbackStyle = auraSec.fallbackStyle,
            })
        end

        if auraSec.write then
            AddAdvancedToggle(enableRow, "barActiveAura", tabInfoButtons, indicatorOn, {
                title = "Active Aura Indicator Advanced",
                build = BuildBarActiveAuraAdvanced,
            })
        end
        -- Second badge in the chain: gear, then this, then the scope chrome the
        -- lens attaches last. The anchor args below are a placeholder -
        -- AnchorRowBadge appends to whatever the chain actually ends at.
        AnchorRowBadge(enableRow, CreateInfoButton(enableRow.frame, enableRow.frame, "LEFT", "LEFT", 0, 0, {
            "Active Aura Indicator",
            {"Adds a border effect to a bar while its tracked aura is active, with optional fill pulse and fill color shift. The preview shows the bar as if the aura were running.", 1, 1, 1, true},
        }, tabInfoButtons))
        auraSec:Chrome(enableRow)

        auraSec:Finish()
    end

    if not indicatorOn then
        CooldownCompanion:SetGroupBarAuraEffectPreview(CS.selectedGroup, false)
    end
end

-- Pandemic color (PTR 8): the aura kit reveals a pandemic-colored clone of
-- the duration fill while the tracked aura sits inside its refresh window.
-- Enable + color only; the window itself is game-computed. Same nil-container
-- reconciliation contract as the active aura section above.
--
-- Shares the Pandemic section, and the mode-spanning "pandemic" OVERRIDE
-- section, with the marker below - so this row carries the section's ONE scope
-- chrome and the marker row follows the same scope silently.
local function BuildBarPandemicSection(container, group, style, lens)
    local function ClearPandemicPreview()
        if CooldownCompanion.SetGroupBarPandemicPreview then
            CooldownCompanion:SetGroupBarPandemicPreview(CS.selectedGroup, false)
        end
    end
    if not GroupHasAuraTrackingEntry(group) then
        ClearPandemicPreview()
        return
    end

    local pandemicSec = BeginLensSection(lens, group, "pandemic")
    local pandemicOn = pandemicSec.read.pandemicEffectEnabled == true
    if container then
        -- The host column only exists under this guard, so the section's
        -- bracket is taken here rather than at Begin.
        pandemicSec:Mark(container)

        local enableRow = AddCheckboxRow(container, {
            label = "Show Pandemic Color",
            value = pandemicOn,
            disabled = pandemicSec.disabled,
            onChange = function(val)
                if not pandemicSec.write then return end
                pandemicSec.write.pandemicEffectEnabled = val and true or false
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
        AnchorRowBadge(enableRow, CreateInfoButton(enableRow.frame, enableRow.frame, "LEFT", "LEFT", 0, 0, {
            "Pandemic Color",
            {"The bar fill wears this color instead of the aura color while the tracked aura is in its refresh window, where recasting adds bonus time.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"Auras that gain no time when refreshed never show it.", 1, 1, 1, true},
        }, tabInfoButtons))
        pandemicSec:Chrome(enableRow)

        if pandemicOn then
            -- No alpha: the pandemic color REPLACES the aura fill color
            -- (owner ruling — never blends with it), so the live clone and
            -- the mirror both render it opaque.
            --
            -- "Fill Color", not "Pandemic Color": the marker's own color row
            -- sits in the same section now, and two rows reading the same
            -- thing would leave no way to tell the fill from the text.
            AddColorRow(container, {
                label = "Fill Color",
                indent = true,
                tbl = pandemicSec.tbl,
                key = "barPandemicColor",
                default = {1, 0.5, 0, 1},
                hasAlpha = false,
                disabled = pandemicSec.disabled,
                onConfirm = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end,
                onChange = ST._RefreshSelectedButtonsPreview,
            })
        end

        pandemicSec:Finish()
    end

    if not pandemicOn then
        ClearPandemicPreview()
    end
end

-- The text half of the same window, new to bar mode: the marker has always
-- rendered on bar panels (it rides the aura duration text, which the kit
-- draws in both modes) but had no group-level control anywhere - the only way
-- to reach it was a per-entry override of Aura Duration Text.
--
-- Rows only, and no nil-container contract: nothing previews the marker in
-- any mode, so there is no preview state to reconcile.
local function BuildBarPandemicMarkerSection(container, group, style, lens)
    local effectiveStyle = (lens and lens.effective) or style
    if effectiveStyle and effectiveStyle.showAuraText == false then
        if CS.CloseAdvancedSettingsPanel then
            CS.CloseAdvancedSettingsPanel({ settingKey = "barPandemicMarker" })
        end
        return
    end
    if not container or not GroupHasAuraTrackingEntry(group) then
        return
    end

    -- Same override section as the fill rows in the left column, so this half
    -- FOLLOWS that section's scope silently: one feature, one affordance, and
    -- the chrome for it is on the enable row beside this one.
    local markerSec = BeginLensSection(lens, group, "pandemic", { column = container })

    local applyStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    local markerRow = AddPandemicMarkerControls(container, markerSec.tbl, applyStyle, function()
        CooldownCompanion:RefreshConfigPanel()
    end, {
        enableOnly = true,
        onModeChanged = function(mode)
            ReconcilePandemicMarkerPreview(lens, mode)
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): the styling rows fill the panel,
    -- so childrenOnly drops the indent they carry when inline. The panel
    -- captures the section's WRITE table, and is only built while there is one.
    local function BuildBarPandemicMarkerAdvanced(panel)
        AddPandemicMarkerControls(panel, markerSec.write, applyStyle, function()
            if CS.RefreshAdvancedSettingsPanel then
                CS.RefreshAdvancedSettingsPanel()
            end
        end, { childrenOnly = true })
    end

    -- "barPandemicMarker", not the icons key: every bars gear in this file
    -- carries its own prefixed key (barAuraText, barNameText, barChargeText),
    -- so a panel switch can never rebind an open panel onto the other mode's
    -- builder. The gear-to-section maps name both.
    if markerSec.write then
        AddAdvancedToggle(markerRow, "barPandemicMarker", tabInfoButtons,
            markerSec.read.pandemicMarkerMode ~= "off", {
                title = "Pandemic Marker Advanced",
                build = BuildBarPandemicMarkerAdvanced,
            })
    end

    markerSec:Finish()
end

local function BuildBarEffectsTab(container, group, style)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end

    -- STYLE LENS (Helpers.lua), resolved ONCE for the whole tab and handed to
    -- every section below - see the note at the top of BuildBarAppearanceTab
    -- for what the scopes mean and why the write table is the only gate.
    local lens = ResolveStyleLens(group)

    -- COLUMN ROUTING on an Aura Panel (owner ruling 2026-08-15). The States
    -- section below loses its whole LEFT column to the panel predicate and keeps
    -- one row on the right; the standing fill rule (stated in full in the recipe
    -- comment at the top of BuildAppearanceTab's icons path in
    -- GroupTabsAppearance.lua, rule 3) says a filtered row set fills the left
    -- column first, so that survivor moves across. Gated on this predicate
    -- alone, so an ordinary bar panel's columns are byte-identical to before.
    local isAuraPanel = ST.IsAuraPanelGroup(group)

    -- Under a multi selection this tab edits the PANEL, and only this line says
    -- so. No-op in every other lens mode.
    AddLensPanelScopeNote(container, lens)

    -- ================================================================
    -- Glows
    -- ================================================================
    -- The section is offered only while the group tracks an aura, but the
    -- builder below runs either way and with whatever host it ends up with:
    -- it reconciles its own preview, and a glow left running by a deleted aura
    -- entry - or by a collapsed section - still has to be cleared.
    local glowsHost
    if GroupHasAuraTrackingEntry(group) then
        local _, glowsCollapsed = BuildCollapsibleSection(container, "Glows", EFFECTS_GLOWS_SECTION, nil, nil, ROW_SECTION)
        if not glowsCollapsed then
            -- One row; the right column is deliberately empty.
            glowsHost = BeginRowGrid(container)
        end
    end
    BuildBarActiveAuraSection(glowsHost, group, style, lens)

    -- ================================================================
    -- Pandemic
    -- ================================================================
    -- Deliberately OUTSIDE the icon-square block below: neither the fill
    -- recolor nor the marker draws on the icon, so hiding the icon must not
    -- take them with it. Same aura gate and same nil-host reconciliation as
    -- Glows above.
    local pandemicLeft, pandemicRight
    if GroupHasAuraTrackingEntry(group) then
        -- Both halves are the one "pandemic" section, so the collapsible's key
        -- follows that section's scope through ST._ResolveLensCollapseKey.
        local _, pandemicCollapsed = BuildCollapsibleSection(container, "Pandemic",
            ResolveLensCollapseKey(lens, group, "pandemic", EFFECTS_PANDEMIC_SECTION), nil, nil, ROW_SECTION)
        if not pandemicCollapsed then
            -- LEFT the fill half, RIGHT the text half.
            pandemicLeft, pandemicRight = BeginRowGrid(container)
        end
    end
    BuildBarPandemicSection(pandemicLeft, group, style, lens)
    BuildBarPandemicMarkerSection(pandemicRight, group, style, lens)

    -- The remaining indicators all render on the bar's icon square, so the
    -- gate reads the icon's visibility THROUGH THE LENS: showBarIcon is a
    -- per-entry key (the barIcon section), and what the tab offers follows
    -- what the current selection actually renders. A panel that hides icons
    -- can still select an entry that shows its own - its state controls must
    -- not vanish with the panel's toggle - and an entry that hides its icon
    -- has nothing here to configure (the Show Icon row on Appearance is the
    -- way back).
    local effIconSec = BeginLensSection(lens, group, "barIcon")
    local barIconShown = effIconSec.read.showBarIcon ~= false
    -- Show Tooltips is the exception, and only on an Aura Panel: its cell has no
    -- CC button, so the aura host frame carries the tooltip whether or not the
    -- icon draws (see BarsTooltipRowShown above). The block therefore opens for
    -- an Aura Panel with the icon hidden, and the icon-bound rows inside keep
    -- their own gate so nothing else comes through with it. On an ordinary bar
    -- panel the condition is barIconShown and nothing changes.
    if barIconShown or isAuraPanel then
        -- ================================================================
        -- Timers
        -- ================================================================
        -- The GCD swipe is the section's only row, so on an Aura Panel the
        -- heading goes with it rather than standing over nothing.
        if barIconShown and CanGroupUseOverrideSection(group, "showGCDSwipe") then
        local _, timersCollapsed = BuildCollapsibleSection(container, "Timers", EFFECTS_TIMERS_SECTION, nil, nil, ROW_SECTION)

        if not timersCollapsed then
        -- One row; the right column is deliberately empty.
        local timerLeft = BeginRowGrid(container)

        -- One row, no gear: `disabled` is the whole gate, so no inert bracket
        -- is needed - the chrome that undoes it is attached after.
        local gcdSec = BeginLensSection(lens, group, "showGCDSwipe")
        local gcdRow = AddCheckboxRow(timerLeft, {
            label = "Show GCD Swipe",
            value = gcdSec.read.showGCDSwipe == true,
            disabled = gcdSec.disabled,
            onChange = function(val)
                if not gcdSec.write then return end
                gcdSec.write.showGCDSwipe = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
        gcdSec:Chrome(gcdRow)
        end -- not timersCollapsed
        end -- CanGroupUseOverrideSection showGCDSwipe

        -- ================================================================
        -- States
        -- ================================================================
        local _, statesCollapsed = BuildCollapsibleSection(container, "States", EFFECTS_STATES_SECTION, nil, nil, ROW_SECTION)

        if not statesCollapsed then
        -- LEFT column: the looks the bar's icon takes on by itself.
        -- RIGHT column: the situational state and the hover behavior.
        local stateLeft, stateRight = BeginRowGrid(container)

        -- On an Aura Panel the left column empties out and Loss of Control
        -- leaves the right one: desaturate-on-cooldown, the unusable visual,
        -- out-of-range tint and the control lockout all read spell state these
        -- entries do not have.
        if barIconShown and CanGroupUseOverrideSection(group, "desaturation") then
        local desatSec = BeginLensSection(lens, group, "desaturation")
        local desatRow = AddCheckboxRow(stateLeft, {
            label = "Desaturate On Cooldown",
            value = desatSec.read.desaturateOnCooldown or false,
            disabled = desatSec.disabled,
            onChange = function(val)
                if not desatSec.write then return end
                desatSec.write.desaturateOnCooldown = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
        desatSec:Chrome(desatRow)
        end -- CanGroupUseOverrideSection desaturation

        -- The missing-aura sibling, as its OWN section (owner ruling
        -- 2026-08-16); static desat on the bar's icon square. Same notes as
        -- the icons tab - passives gray by default with entry-side Never
        -- Desaturate as the off switch, and the section is aura-entry-denied
        -- plus aura-tracking-config-only.
        if barIconShown and GroupHasAuraTrackingEntry(group)
            and CanGroupUseOverrideSection(group, "auraMissingDesaturation") then
        local missingSec = BeginLensSection(lens, group, "auraMissingDesaturation")
        local missingRow = AddCheckboxRow(stateLeft, {
            label = "Desaturate While Aura Missing",
            value = missingSec.read.desaturateWhileAuraNotActive == true,
            disabled = missingSec.disabled,
            onChange = function(val)
                if not missingSec.write then return end
                missingSec.write.desaturateWhileAuraNotActive = missingSec:BoolValue(val)
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label. Same split the icons States row
        -- states: passive-sourced auras desaturate by default and never read
        -- this key.
        AnchorRowBadge(missingRow, CreateInfoButton(missingRow.frame, missingRow.frame, "LEFT", "LEFT", 0, 0, {
            "Desaturate While Aura Missing",
            {"Grays the bar icon while the tracked aura is not active.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"Passive auras already do this by default and ignore this setting. Use Never Desaturate on the entry to turn theirs off.", 1, 1, 1, true},
        }, tabInfoButtons))
        missingSec:Chrome(missingRow)
        end -- CanGroupUseOverrideSection auraMissingDesaturation

        -- The two shared builders below own their gears, so an inert scope
        -- cannot skip building one the way the hand-written sections do: the
        -- inert pass gates the gear it finds on the row (_cdcAdvancedBtn), and
        -- the sweep at the foot of this builder closes a panel it rebound.
        if barIconShown and CanGroupUseOverrideSection(group, "unusableDimming") then
        local unusableSec = BeginLensSection(lens, group, "unusableDimming", { column = stateLeft })
        local unusableRow = BuildUnusableDimmingControls(stateLeft, unusableSec.tbl, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, {
            row = true,
            fallbackStyle = unusableSec.fallbackStyle,
        })
        unusableSec:Chrome(unusableRow)
        unusableSec:Finish()
        end -- CanGroupUseOverrideSection unusableDimming

        -- Same single-row override the icons States section exposes. The live
        -- bar path already applies range tint to the icon square, so this row is
        -- relevant only while that square renders.
        if barIconShown and CanGroupUseOverrideSection(group, "showOutOfRange") then
        local oorSec = BeginLensSection(lens, group, "showOutOfRange")
        local oorRow = AddCheckboxRow(stateLeft, {
            label = "Show Out of Range",
            value = oorSec.read.showOutOfRange or false,
            disabled = oorSec.disabled,
            onChange = function(val)
                if not oorSec.write then return end
                oorSec.write.showOutOfRange = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
        oorSec:Chrome(oorRow)
        end -- CanGroupUseOverrideSection showOutOfRange

        if barIconShown and CanGroupUseOverrideSection(group, "lossOfControl") then
        local locSec = BeginLensSection(lens, group, "lossOfControl")
        local locRow = BuildLossOfControlControls(stateRight, locSec.tbl, refreshStyle, {
            row = true,
        })
        locRow:SetDisabled(locSec.disabled)
        locSec:Chrome(locRow)
        end -- CanGroupUseOverrideSection lossOfControl

        -- On an Aura Panel this is the section's ONLY row (everything above is
        -- denied, and Allow Pings below is not offered), so it takes the left
        -- column instead of stranding itself beside an empty one.
        local tooltipHost = isAuraPanel and stateLeft or stateRight
        local tooltipSec = BeginLensSection(lens, group, "showTooltips", { column = tooltipHost })
        local tooltipRow = BuildShowTooltipsControls(tooltipHost, tooltipSec.tbl, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, {
            row = true,
            advanced = true,
            infoButtons = tabInfoButtons,
            fallbackStyle = tooltipSec.fallbackStyle,
        })
        tooltipSec:Chrome(tooltipRow)
        tooltipSec:Finish()

        -- Allow Pings is a PANEL setting with no override section of its own
        -- (ST.OVERRIDE_SECTIONS), so under an entry lens it goes read-only with
        -- the rest of the panel-only content instead of letting a panel-wide
        -- edit be made from an entry's page. Its "?" badge stays readable: the
        -- inert walk only reaches AceGUI children and the gear.
        --
        -- Not offered on an Aura Panel: the row's own tooltip already says
        -- entries added as auras cannot be pinged, and every entry here is one.
        if not CooldownCompanion:IsAuraPanel(group) then
        local pingsSec = BeginLensSection(lens, group, nil, { column = stateRight })
        BuildAllowPingsControls(stateRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        pingsSec:Finish()
        end
        end -- not statesCollapsed
    end

    -- Inert-section sweep, over the WHOLE bars map - see the note by
    -- ST._BARMODE_SECTION_BY_ADVANCED_KEY at the top of this file for why
    -- neither builder limits itself to its own tab's keys.
    if CS.CloseAdvancedSettingsPanel then
        for advancedKey, sectionId in pairs(ST._BARMODE_SECTION_BY_ADVANCED_KEY) do
            local _, _, sectionWrite = ResolveLensSection(lens, group, sectionId)
            if sectionWrite == nil then
                CS.CloseAdvancedSettingsPanel({ settingKey = advancedKey })
            end
        end
    end
end

-- Expose for the tab dispatchers (GroupTabsAppearance.lua / GroupTabsEffects.lua)
ST._BuildBarAppearanceTab = BuildBarAppearanceTab
ST._BuildBarEffectsTab = BuildBarEffectsTab
