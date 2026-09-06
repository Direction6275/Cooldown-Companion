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
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddBarTextPositionControls = ST._AddBarTextPositionControls
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders
local GroupHasAuraTrackingEntry = ST._GroupHasAuraTrackingEntry
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls

-- Style lens (Helpers.lua). Selecting an entry turns these tabs into a view of
-- that entry's effective values, with per-section scope deciding where - or
-- whether - each section writes. Helpers.lua loads first (the .toc), so these
-- resolve at load like every other import above.
-- ResolveLensSection is kept for the finder predicates below, which only ask
-- a section's scope; every section that draws rows goes through the host
-- below instead.
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
local AddDurationTextVisibilityRows = ST._AddDurationTextVisibilityRows
local AddSettingsSubheading = ST._AddSettingsSubheading
local AddFamilyColumnCaptions = ST._AddFamilyColumnCaptions
local BeginFullWidthRowGroup = ST._BeginFullWidthRowGroup

-- Imports from RowWidgets.lua (the row grammar)
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddEditBoxRow = ST._AddEditBoxRow
local AddColorRow = ST._AddColorRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid

local tabInfoButtons = CS.tabInfoButtons

-- The gear sites' "Turn On" enable specs, riding the LAZY unlock specs the
-- gears store in options.unlock (resolved only at panel-build time by
-- ST._ResolveAdvancedUnlock, Helpers.lua). File-local constants so a tab
-- rebuild allocates none of them.
local TURNON_BAR_ICON = { label = "Enable Icon", key = "showBarIcon" }
local TURNON_BAR_NAME_TEXT = { label = "Enable Name Text", key = "showBarNameText" }
local TURNON_BAR_COOLDOWN_TEXT = { label = "Enable Cooldown Text", key = "showCooldownText" }
local TURNON_BAR_CHARGE_TEXT = { label = "Enable Count Text", key = "showChargeText" }
local TURNON_BAR_READY_TEXT = { label = "Enable Ready Text", key = "showBarReadyText" }
local TURNON_BAR_AURA_TEXT = { label = "Enable Aura Duration Text", key = "showAuraText" }
local TURNON_BAR_AURA_STACK_TEXT = { label = "Enable Aura Stack Text", key = "showAuraStackText" }
local TURNON_SHOW_UNUSABLE = { label = "Enable Unusable Visual", key = "showUnusable" }
local TURNON_SHOW_TOOLTIPS = { label = "Enable Tooltips", key = "showTooltips" }
-- The marker's enable is a mode, not a boolean.
local TURNON_BAR_PANDEMIC_MARKER = {
    label = "Enable Pandemic Marker",
    apply = function(write) write.pandemicMarkerMode = "auto" end,
}

-- One enable path for the checkbox AND the read-only panel's Turn On
-- footer: enabling with nothing visible configured forces the pulse
-- border and resets its per-style keys (a leftover proc-scale size
-- would render a 30px wall), and the two entrances of one feature
-- must never drift.
local function EnableBarAuraIndicator(write)
    write.barAuraIndicatorEnabled = true
    if not (write.barAuraEffect and write.barAuraEffect ~= "color" and write.barAuraEffect ~= "none"
        or write.barAuraPulseEnabled == true or write.barAuraColorShiftEnabled == true) then
        write.barAuraEffect = "pulse"
        write.barAuraEffectSize = 2
        write.barAuraEffectSpeed = 0.5
    end
end

local TURNON_BAR_AURA_INDICATOR = {
    label = "Enable Active Aura Indicator",
    apply = EnableBarAuraIndicator,
}

-- Populated at module load near the exports. Bar mode has several advanced
-- text panels with identical visible labels, so callers pass exact descriptor
-- maps instead of relying on label-only binding.
local BAR_FINDER = {
    appearance = {},
    advanced = {},
    effects = { aura = {}, spell = {}, interaction = {} },
}

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right. The rules every row-grammar section follows are stated
-- once, in the recipe comment at the top of BuildAppearanceTab's icons path in
-- GroupTabsAppearance.lua; the sections below conform to them rather than
-- restating them.
local ROW_SECTION = { leftAligned = true }

-- The bar Effects tab draws the same sections as the icons Effects tab
-- and deliberately SHARES their collapse keys, so the gear-to-section map
-- GroupTabsEffects.lua owns (ST._INDICATORS_SECTION_BY_ADVANCED_KEY) covers both tabs
-- with one entry per advanced key. Keep these in step with the constants
-- declared beside that map: the literals must MATCH, or collapsing a section
-- on an icon panel would leave it open on a bar panel.
--
-- TWO indicator sections on both tabs (owner ruling 2026-08-30): the
-- cooldown/spell family and the aura family. What used to be the Timers,
-- States and Pandemic collapsibles are quiet SUBHEADINGS inside them, so the
-- "effects_timers", "effects_states" and "effects_pandemic" keys are retired -
-- nothing may name them again. Bars has no spell glows at all (its one glow row
-- is the active aura indicator, which belongs to Aura Indicators), so it draws
-- no Glows subheading.
local EFFECTS_SPELL_SECTION = "effects_spell"
local EFFECTS_AURA_SECTION = "effects_aura"
local EFFECTS_INTERACTION_SECTION = "effects_interaction"

-- LibSharedMedia statusbar names run well past the 140px control column, and a
-- dropdown sizes its menu from the control it hangs under.
local BAR_TEXTURE_PULLOUT_WIDTH = 300

-- Bar mode's advanced gears, by the OVERRIDE SECTION each one belongs to.
-- Shaped and named after ST._APPEARANCE_SECTION_BY_ADVANCED_KEY (GroupTabsAppearance.lua),
-- and deliberately NOT the same question as ST._INDICATORS_SECTION_BY_ADVANCED_KEY
-- beside it: that map answers "which COLLAPSE section is this gear inside",
-- this one answers "which OVERRIDE section owns this gear's values".
--
-- Read by the Customizations list (Helpers.lua) to resolve a section's gear.
-- Stale-panel cleanup no longer iterates it: the gear-stamp sweep in
-- AdvancedSettingsPanel.lua closes unrebuilt gear panels by key, mapless.
--
-- A gear added to any converted section belongs here the same day.
ST._BARMODE_SECTION_BY_ADVANCED_KEY = {
    panelBorder = "borderSettings",
    durationLowTime = "durationLowTime",
    iconCooldownTintEnabled = "iconTint",
    iconAuraTintEnabled = "iconTint",
    barPandemicColor = "pandemic",
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
-- Duration Format remains a shared row in the duration options; time placement
-- and the two time-text offsets move under the aura duration text they place. The
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
-- gearEnabled mirrors the STRUCTURAL gates that still remove a gear outright
-- (Masque, the fill-timer interlock, a row surface that is not drawn). Parent
-- toggles and customization state stopped hiding gears: those gears build
-- with their normal looks (locked and live gears wear the SAME two colors,
-- owner ruling 2026-08-31 - the panel is what says locked) and open
-- read-only behind an unlock strip, so no predicate mirrors them any more.
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
    -- gearEnabled predicates survive only where a STRUCTURAL gate still hides
    -- a gear; parent-toggle state no longer hides gears anywhere - a gear
    -- behind an off toggle keeps its normal looks and opens its panel
    -- read-only behind an unlock strip.
    barIcon = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
    },
    barNameText = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
    },
    cooldownText = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
        available = GroupDrawsCooldownTextRow,
    },
    durationLowTime = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
        available = BarsDrawDurationRows,
    },
    chargeText = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
    },
    barReadyText = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
    },
    -- The bar aura block is drawn only while the GROUP tracks an aura.
    auraText = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
        available = BarsGroupTracksAura,
    },
    auraStackText = {
        tab = "appearance", collapseKey = "barappearance_textIcon",
        available = BarsGroupTracksAura,
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
        tab = "effects", collapseKey = EFFECTS_AURA_SECTION,
        available = BarsGroupTracksAura,
    },
    -- The Pandemic subheading at the foot of Aura Indicators, so the home names
    -- that section's key.
    pandemic = {
        tab = "effects", collapseKey = EFFECTS_AURA_SECTION,
        available = BarsGroupTracksAura,
        -- One gear on this section in bar mode (barPandemicMarker). The marker
        -- rides the aura duration text, so its ROW - and with it the gear -
        -- exists only while that surface renders; the marker's own on/off no
        -- longer hides it. The fill half remains available independently.
        gearEnabled = BarsDrawAuraDurationRows,
    },
    -- The Timers and States subheadings sit inside the Cooldown / Spell
    -- Indicators section, drawn only while the bar icon renders for the current
    -- selection (BuildBarEffectsTab's `effIconSec.read.showBarIcon ~= false`):
    -- everything in them renders on the icon square.
    showGCDSwipe = {
        tab = "effects", collapseKey = EFFECTS_SPELL_SECTION,
        available = BarsIconShown,
    },
    desaturation = {
        tab = "effects", collapseKey = EFFECTS_SPELL_SECTION,
        available = BarsIconShown,
    },
    -- Its own override section (owner ruling 2026-08-16), drawn in the Aura
    -- Indicators section rather than with the spell states (owner ruling
    -- 2026-08-30). The row's reach is unchanged by that move: it draws only
    -- while the bar icon renders AND the group tracks an aura, because what it
    -- grays is the icon square.
    auraMissingDesaturation = {
        tab = "effects", collapseKey = EFFECTS_AURA_SECTION,
        available = function(group, style)
            return BarsIconShown(group, style) and BarsGroupTracksAura(group)
        end,
    },
    unusableDimming = {
        tab = "effects", collapseKey = EFFECTS_SPELL_SECTION,
        available = BarsIconShown,
    },
    showOutOfRange = {
        tab = "effects", collapseKey = EFFECTS_SPELL_SECTION,
        available = BarsIconShown,
    },
    lossOfControl = {
        tab = "effects", collapseKey = EFFECTS_SPELL_SECTION,
        available = BarsIconShown,
    },
    -- Its own Interaction section at the foot of the tab, not the spell states.
    --
    -- Not BarsIconShown: on an Aura Panel this row is drawn outside the icon
    -- gate, so its Customizations link and gear stay reachable with the bar icon
    -- hidden (BuildBarEffectsTab's `barIconShown or isAuraPanel`).
    showTooltips = {
        tab = "effects", collapseKey = EFFECTS_INTERACTION_SECTION,
        available = BarsTooltipRowShown,
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

local function MakeBarCooldownTextAdvancedDescriptor(styleTable, finderSettings)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    return {
        settingKey = "barCooldownText",
        title = "Cooldown Text Advanced",
        build = function(panel)
            local style = styleTable or ResolveSelectedGroupStyle()
            if not style then
                return
            end

            AddFontControls(panel, style, "cooldown", {sizeMin = 6, sizeMax = 24}, refreshStyle, {
                row = true,
                settings = finderSettings and {
                    size = finderSettings.fontSize,
                    font = finderSettings.font,
                    outline = finderSettings.outline,
                },
            })
            -- deferCommit is deliberately absent, matching the stock color-picker
            -- call this row replaced.
            AddColorRow(panel, {
                label = "Font Color",
                setting = finderSettings and finderSettings.color,
                tbl = style,
                key = "cooldownFontColor",
                default = {1, 1, 1, 1},
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })
            local anchorRow = AddBarTextPositionControls(panel, style,
                "barTimeTextAnchor", "barCdTextOffsetX", "barCdTextOffsetY", refreshStyle, {
                    automatic = true, settings = finderSettings,
                })
            AnchorRowBadge(anchorRow, CreateInfoButton(anchorRow.frame, anchorRow.frame, "LEFT", "LEFT", 0, 0, {
                "Time Text Position",
                {"Cooldown and Ready text share this position. Aura Duration follows it unless Independent Position is enabled. Automatic keeps the bar's original placement.", 1, 1, 1, true},
            }, anchorRow))
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
    -- it that DO still work - Duration Format, Time text positioning and the two
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
    -- Bar Settings (length, height, fill direction, spacing, texture)
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
    -- LEFT column: how one bar is shaped, and which way its own fill runs.
    -- RIGHT column: how the bars sit together and what they are drawn with.
    local barLeft, barRight = BeginRowGrid(container)
    -- The columns only exist here, so the section's brackets are taken now
    -- rather than at Begin; it fills two, so the right one is a bracket of its
    -- own.
    barSettingsSec:Mark(barLeft)
    local barRightBracket = barSettingsSec:Bracket(barRight)

    AddSliderRow(barLeft, {
        label = "Bar Length",
        setting = BAR_FINDER.appearance.barSettings and BAR_FINDER.appearance.barSettings.length,
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
        setting = BAR_FINDER.appearance.barSettings and BAR_FINDER.appearance.barSettings.height,
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

    -- Which way a single bar's own fill runs is what the bar LOOKS like, not
    -- where the bars sit, so it belongs with the bar's shape rather than with
    -- the Layout tab's arrangement rows. Panel-only like the sliders above:
    -- plain rows carrying the section's `disabled`, inside its bracket.
    AddCheckboxRow(barLeft, {
        label = "Vertical Bar Fill",
        setting = BAR_FINDER.appearance.barSettings and BAR_FINDER.appearance.barSettings.vertical,
        value = style.barFillVertical or false,
        disabled = barSettingsSec.disabled,
        onChange = function(val)
            style.barFillVertical = val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    AddCheckboxRow(barLeft, {
        label = "Flip Fill/Drain Direction",
        setting = BAR_FINDER.appearance.barSettings and BAR_FINDER.appearance.barSettings.reverse,
        value = style.barReverseFill or false,
        disabled = barSettingsSec.disabled,
        onChange = function(val)
            style.barReverseFill = val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end,
    })

    if group.buttons and #group.buttons > 1 then
        AddSliderRow(barRight, {
            label = "Bar Spacing",
            setting = BAR_FINDER.appearance.barSettings and BAR_FINDER.appearance.barSettings.spacing,
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
        setting = BAR_FINDER.appearance.barSettings and BAR_FINDER.appearance.barSettings.texture,
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
    -- LEFT column: everything a SPELL paints - the bar at rest, the backdrop
    -- behind it, and the two colors a spell timer draws over that.
    -- RIGHT column: the aura timer color. It lives here rather than beside the
    -- aura TEXT toggles in Text & Icon, and it carries that section's
    -- aura-tracking gate with it.
    local colorLeft, colorRight = BeginRowGrid(container)

    -- Captions only where both families really draw. The left predicate is the
    -- OR of the two spell-side gates below (Bar Background Color is ungated,
    -- but it is the bar's own chrome rather than a spell row, so it does not
    -- speak for that family); the right one is the aura timer color's gate.
    -- Both spell gates are false on an Aura Panel, which is what keeps a
    -- single-family grid uncaptioned there.
    if (CanGroupUseOverrideSection(group, "barColor")
        or CanGroupUseOverrideSection(group, "barCooldownColor"))
        and GroupHasAuraTrackingEntry(group) then
        AddFamilyColumnCaptions(colorLeft, colorRight)
    end

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
    local function AddBarColorRow(column, sectionId, label, key, default, setting)
        local sec = BeginLensSection(lens, group, sectionId)
        local row = AddColorRow(column, {
            label = label,
            setting = setting,
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
        AddBarColorRow(colorLeft, "barColor", "Bar Color", "barColor", {0.2, 0.6, 1.0, 1.0},
            BAR_FINDER.appearance.colors and BAR_FINDER.appearance.colors.bar)
    end
    AddBarColorRow(colorLeft, "barBgColor", "Bar Background Color", "barBgColor", {0.1, 0.1, 0.1, 0.8},
        BAR_FINDER.appearance.colors and BAR_FINDER.appearance.colors.background)
    -- The two colors a spell TIMER paints - spell-side, so they close the left
    -- column. An Aura Panel bar has no cooldown and no recharge to paint.
    if CanGroupUseOverrideSection(group, "barCooldownColor") then
        AddBarColorRow(colorLeft, "barCooldownColor", "Bar Cooldown Color", "barCooldownColor", {0.6, 0.6, 0.6, 1.0},
            BAR_FINDER.appearance.colors and BAR_FINDER.appearance.colors.cooldown)
        AddBarColorRow(colorLeft, "barChargeColor", "Bar Recharging Color", "barChargeColor", {1.0, 0.82, 0.0, 1.0},
            BAR_FINDER.appearance.colors and BAR_FINDER.appearance.colors.recharging)
    end

    -- The color the aura timer drains in - the RIGHT column's one row. Same
    -- gate as the aura block down in Text & Icon, so it appears only while the
    -- group tracks an aura.
    --
    -- barAuraColor belongs to the barActiveAura section, whose home is the
    -- Effects tab's Active Aura Indicator row - so this row FOLLOWS that
    -- section's scope and carries no chrome of its own, the way the pandemic
    -- marker row follows the pandemic enable row. One section, one affordance.
    if GroupHasAuraTrackingEntry(group) then
        local auraColorSec = BeginLensSection(lens, group, "barActiveAura")
        AddColorRow(colorRight, {
            label = "Bar Aura Timer Color",
            setting = BAR_FINDER.appearance.colors and BAR_FINDER.appearance.colors.aura,
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
    local borderColorRow = BuildBorderControls(borderLeft, borderSec.tbl, refreshStyle, {
        sec = borderSec,
        row = true,
        fallbackStyle = borderSec.fallbackStyle,
        settings = BAR_FINDER.appearance.border,
    })
    borderSec:DirectColorControl(borderColorRow, "borderColor")

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
            settings = BAR_FINDER.appearance.tint,
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

    AddSettingsSubheading(container, "Duration Text")
    local durationLeft, durationRight
    if isAuraPanel then
        durationLeft = BeginFullWidthRowGroup(container)
        durationRight = durationLeft
    else
        durationLeft, durationRight = BeginRowGrid(container)
    end
    -- Column captions, drawn only where both families really appear - the same
    -- rule and the same predicate the icons twin uses. LEFT is the Show
    -- Cooldown Text block, whose only gate is `not isAuraPanel`; RIGHT is the
    -- aura duration text block, gated on an aura-tracking entry. An Aura Panel
    -- is a single rail, which the helper also refuses on its own. The low-time
    -- grid below is NOT captioned: one feature across two columns, not a family
    -- split.
    if not isAuraPanel and GroupHasAuraTrackingEntry(group) then
        AddFamilyColumnCaptions(durationLeft, durationRight)
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
    local otherLeft, otherRight = BeginRowGrid(container)
    -- Same rule as the Duration Text grid above: the left predicate is the OR
    -- of the two spell-side row gates (count text, ready text - Show Name Text
    -- is ungated, but a bar's name is not a spell-state row and does not speak
    -- for that family); the right one is the aura stack row's gate. Both spell
    -- gates are false on an Aura Panel, so this grid goes uncaptioned there
    -- even though it stays a real two-column grid.
    if (CanGroupUseOverrideSection(group, "chargeText")
        or CanGroupUseOverrideSection(group, "barReadyText"))
        and GroupHasAuraTrackingEntry(group) then
        AddFamilyColumnCaptions(otherLeft, otherRight)
    end

    -- One setting (Show Icon, with its own gear); the right column stays empty
    -- now that Compact Mode has moved to the Layout tab.
    AddSettingsSubheading(container, "Icon")
    local iconLeft = BeginRowGrid(container)

    -- Dedicated override section (owner ruling 2026-08-25): one shared policy
    -- for cooldown and aura duration phases, customized as one entry-owned
    -- unit. The master row carries the section's scope affordance.
    local function AddDurationLowTimeSection()
        if not (ST._AddDurationLowTimeRows and lowTimeLeft and lowTimeRight) then return end
        local lowTimeSec = BeginLensSection(lens, group, "durationLowTime", { column = lowTimeLeft })
        local rightBracket = lowTimeRight ~= lowTimeLeft
            and lowTimeSec:Bracket(lowTimeRight) or nil
        local entryIsAuraOnly = (lens and lens.mode == "entry") and lens.buttonData
            and ST.IsAuraSectionEntry(group, lens.buttonData)
        -- Master row unindented and aura opt-in row: keep in step with the
        -- icon-mode twin in GroupTabsAppearance.lua (owner ruling 2026-08-28).
        local rows = ST._AddDurationLowTimeRows(lowTimeLeft, lowTimeSec.tbl, refreshStyle, {
            sec = lowTimeSec,
            explicitOff = lowTimeSec.scope == "customized",
            disabled = lowTimeSec.disabled,
            rightColumn = lowTimeRight,
            auraOnly = ST.IsAuraPanelGroup(group) or entryIsAuraOnly,
            auraToggle = not ST.IsAuraPanelGroup(group) and not entryIsAuraOnly
                and BarsDrawAuraDurationRows(group, (lens and lens.effective) or group.style),
            infoButtons = tabInfoButtons,
            settings = BAR_FINDER.appearance.lowTime,
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

    -- ================================================================
    -- Show Icon
    -- ================================================================
    local iconSec = BeginLensSection(lens, group, "barIcon", { column = iconLeft })

    local showIconRow = AddCheckboxRow(iconLeft, {
        label = "Show Icon",
        setting = BAR_FINDER.appearance.text and BAR_FINDER.appearance.text.icon,
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
    -- The panel reads its starting values from the section's READ table and
    -- writes through its WRITE table; with no write table it opens read-only
    -- behind the unlock strip, so no write callback of its own can fire.
    local function BuildBarIconAdvanced(panel, descriptor)
        AddCheckboxRow(panel, {
            label = "Flip Icon Side",
            setting = BAR_FINDER.advanced.icon and BAR_FINDER.advanced.icon.flip,
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
            setting = BAR_FINDER.advanced.icon and BAR_FINDER.advanced.icon.offset,
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
            setting = BAR_FINDER.advanced.icon and BAR_FINDER.advanced.icon.customSize,
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
                setting = BAR_FINDER.advanced.icon and BAR_FINDER.advanced.icon.size,
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
            setting = BAR_FINDER.advanced.icon and BAR_FINDER.advanced.icon.zoom,
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

        -- This section is the row's OWN: once the entry has taken it over,
        -- its override outranks whatever Bar Icon resolves to, so a read-only
        -- build must not grey it - the row's Customize would otherwise create
        -- an override behind a dead slider. Customized scope only: at panel
        -- or multi scope the zoom rides the panel's lock like every other
        -- row (the grey answers a toggle that is off, and no Customize can
        -- strand an override there). Consumed (and cleared) by
        -- MakeWidgetTreeInert in the same build; the revert glyph still
        -- hides with the rest of the locked surface (owner ruling
        -- 2026-08-31).
        if descriptor and descriptor._resolvedUnlock and zoomSec.scope == "customized" then
            zoomRow._cdcReadOnlyExempt = true
        end
    end

    if iconSec.scope ~= "denied" then
        AddAdvancedToggle(showIconRow, "barIcon", tabInfoButtons, true, {
            title = "Bar Icon Advanced",
            build = BuildBarIconAdvanced,
            unlock = { sec = iconSec,
                enable = iconSec.read.showBarIcon == false and TURNON_BAR_ICON or nil },
        })
    end
    iconSec:Chrome(showIconRow)

    iconSec:Finish()

    -- Show Name Text toggle
    local nameSec = BeginLensSection(lens, group, "barNameText", { column = otherLeft })

    local showNameRow = AddCheckboxRow(otherLeft, {
        label = "Show Name Text",
        setting = BAR_FINDER.appearance.text and BAR_FINDER.appearance.text.name,
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
        AddFontControls(panel, nameSec.tbl, "barName", {sizeMin = 6, sizeMax = 24, size = 10}, refreshStyle, {
            row = true,
            settings = BAR_FINDER.advanced.name and {
                size = BAR_FINDER.advanced.name.fontSize,
                font = BAR_FINDER.advanced.name.font,
                outline = BAR_FINDER.advanced.name.outline,
            },
        })
        -- deferCommit is deliberately absent, matching the stock color-picker call
        -- this row replaced.
        AddColorRow(panel, {
            label = "Font Color",
            setting = BAR_FINDER.advanced.name and BAR_FINDER.advanced.name.color,
            tbl = nameSec.tbl,
            key = "barNameFontColor",
            default = {1, 1, 1, 1},
            hasAlpha = true,
            onConfirm = refreshStyle,
            onChange = refreshStyle,
        })
        AddBarTextPositionControls(panel, nameSec.tbl,
            "barNameTextAnchor", "barNameTextOffsetX", "barNameTextOffsetY", refreshStyle, {
                automatic = true, settings = BAR_FINDER.advanced.name, disabled = nameSec.disabled,
            })
    end

    if nameSec.scope ~= "denied" then
        AddAdvancedToggle(showNameRow, "barNameText", tabInfoButtons, true, {
            title = "Name Text Advanced",
            build = BuildBarNameTextAdvanced,
            unlock = { sec = nameSec,
                enable = nameSec.read.showBarNameText == false and TURNON_BAR_NAME_TEXT or nil },
        })
    end
    nameSec:Chrome(showNameRow)

    nameSec:Finish()

    -- Show Cooldown Text toggle. An Aura Panel bar has no cooldown to count
    -- down, so the toggle itself is dead there and is left out; everything live
    -- that hung off it (Duration Format, time text positioning, the two time-text
    -- offsets) moves into the aura duration text section on the right.
    if not isAuraPanel then
    local cdTextSec = BeginLensSection(lens, group, "cooldownText", { column = durationLeft })

    local showTimeRow = AddCheckboxRow(durationLeft, {
        label = "Show Cooldown Text",
        setting = BAR_FINDER.appearance.text and BAR_FINDER.appearance.text.cooldown,
        value = cdTextSec.read.showCooldownText or false,
        disabled = cdTextSec.disabled,
        onChange = function(val)
            if not cdTextSec.write then return end
            cdTextSec.write.showCooldownText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if cdTextSec.scope ~= "denied" then
        -- Panel scope hands the descriptor NO table, so it keeps resolving the
        -- live group style itself (see the factory's note). A customized entry
        -- hands its override store; an inherited one hands the effective read
        -- table, whose panel opens read-only behind the unlock strip.
        local barCdTextAdvanced = MakeBarCooldownTextAdvancedDescriptor(
            cdTextSec.scope == "customized" and cdTextSec.write
                or cdTextSec.write == nil and cdTextSec.read or nil,
            BAR_FINDER.advanced.cooldown)

        AddAdvancedToggle(showTimeRow, barCdTextAdvanced.settingKey, tabInfoButtons, true, {
            title = barCdTextAdvanced.title,
            build = function(panel)
                AddDurationTextVisibilityRows(panel, cdTextSec.read, cdTextSec.write,
                    "cooldown", refreshStyle, {
                        indent = false,
                        explicitOff = cdTextSec.scope == "customized",
                        disabled = cdTextSec.disabled,
                        infoButtons = CS.advancedSettingsInfoButtons,
                        rebuild = function()
                            CooldownCompanion:RefreshConfigPanel()
                        end,
                        settings = BAR_FINDER.appearance.cooldownVisibility,
                    })
                    barCdTextAdvanced.build(panel)
            end,
            unlock = { sec = cdTextSec,
                enable = cdTextSec.read.showCooldownText ~= true and TURNON_BAR_COOLDOWN_TEXT or nil },
        })
    end
    cdTextSec:Chrome(showTimeRow)

    cdTextSec:Finish()
    if drawsCooldownFormat then
        local durationFormatRow = AddDurationFormatDropdown(durationLeft, group.style, refreshStyle, {
            row = true,
            sharedHelp = true,
            infoButtons = tabInfoButtons,
            setting = BAR_FINDER.appearance.text and BAR_FINDER.appearance.text.durationFormat,
        })
        if durationFormatRow then
            cdTextSec:PanelRowChrome(durationFormatRow)
        end
    end
    if drawsCooldownLowTime then
        AddDurationLowTimeSection()
    end
    end -- not isAuraPanel

    -- Show Charge Text toggle. Charges and uses are spell mechanics, so an Aura
    -- Panel never counts anything here; the aura's own stack count is the Show
    -- Aura Stack Text row.
    if CanGroupUseOverrideSection(group, "chargeText") then
    local chargeSec = BeginLensSection(lens, group, "chargeText", { column = otherLeft })

    local chargeTextRow = AddCheckboxRow(otherLeft, {
        label = "Show Count Text (Charges/Uses)",
        setting = BAR_FINDER.appearance.text and BAR_FINDER.appearance.text.count,
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
        AddFontControls(panel, chargeSec.tbl, "charge", {}, refreshStyle, {
            row = true,
            settings = BAR_FINDER.advanced.charge and {
                size = BAR_FINDER.advanced.charge.fontSize,
                font = BAR_FINDER.advanced.charge.font,
                outline = BAR_FINDER.advanced.charge.outline,
            },
        })

        local function ChargeColorRow(rowLabel, key)
            AddColorRow(panel, {
                label = rowLabel,
                setting = BAR_FINDER.advanced.charge and BAR_FINDER.advanced.charge[key],
                tooltip = { rowLabel },
                tbl = chargeSec.tbl,
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

        AddAnchorDropdown(panel, chargeSec.tbl, "chargeAnchor", "BOTTOMRIGHT", refreshStyle, nil, {
            row = true,
            setting = BAR_FINDER.advanced.charge and BAR_FINDER.advanced.charge.anchor,
        })
        AddOffsetSliders(panel, chargeSec.tbl, "chargeXOffset", "chargeYOffset", {x = -2, y = 2}, refreshStyle, {
            row = true,
            settings = BAR_FINDER.advanced.charge and {
                x = BAR_FINDER.advanced.charge.xOffset,
                y = BAR_FINDER.advanced.charge.yOffset,
            },
        })
    end

    if chargeSec.scope ~= "denied" then
        AddAdvancedToggle(chargeTextRow, "barChargeText", tabInfoButtons, true, {
            title = "Count Text Advanced",
            build = BuildBarChargeTextAdvanced,
            unlock = { sec = chargeSec,
                enable = chargeSec.read.showChargeText == false and TURNON_BAR_CHARGE_TEXT or nil },
        })
    end
    chargeSec:Chrome(chargeTextRow)

    chargeSec:Finish()
    end -- CanGroupUseOverrideSection chargeText

    -- Show Ready Text toggle. "Ready" is the off-cooldown state, so an Aura
    -- Panel bar never reaches it.
    if CanGroupUseOverrideSection(group, "barReadyText") then
    local readySec = BeginLensSection(lens, group, "barReadyText", { column = otherLeft })

    local showReadyRow = AddCheckboxRow(otherLeft, {
        label = "Show Ready Text",
        setting = BAR_FINDER.appearance.text and BAR_FINDER.appearance.text.ready,
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
            setting = BAR_FINDER.advanced.ready and BAR_FINDER.advanced.ready.text,
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
            setting = BAR_FINDER.advanced.ready and BAR_FINDER.advanced.ready.color,
            tbl = readySec.tbl,
            key = "barReadyTextColor",
            default = {0.2, 1.0, 0.2, 1.0},
            hasAlpha = true,
            onConfirm = refreshStyle,
            onChange = refreshStyle,
        })
        AddFontControls(panel, readySec.tbl, "barReady", {sizeMin = 6, sizeMax = 24}, refreshStyle, {
            row = true,
            settings = BAR_FINDER.advanced.ready and {
                size = BAR_FINDER.advanced.ready.fontSize,
                font = BAR_FINDER.advanced.ready.font,
                outline = BAR_FINDER.advanced.ready.outline,
            },
        })
    end

    if readySec.scope ~= "denied" then
        AddAdvancedToggle(showReadyRow, "barReadyText", tabInfoButtons, true, {
            title = "Ready Text Advanced",
            build = BuildBarReadyTextAdvanced,
            unlock = { sec = readySec,
                enable = not readySec.read.showBarReadyText and TURNON_BAR_READY_TEXT or nil },
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
        -- text position by default, with optional independent placement.
        local auraTextSec = BeginLensSection(lens, group, "auraText", { column = durationRight })

        local auraTextRow = AddCheckboxRow(durationRight, {
            label = "Show Aura Duration Text",
            setting = BAR_FINDER.appearance.text and BAR_FINDER.appearance.text.auraDuration,
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
            AddDurationTextVisibilityRows(panel, auraTextSec.read, auraTextSec.write,
                "aura", refreshStyle, {
                    indent = false,
                    explicitOff = auraTextSec.scope == "customized",
                    disabled = auraTextSec.disabled,
                    infoButtons = CS.advancedSettingsInfoButtons,
                    rebuild = function()
                        CooldownCompanion:RefreshConfigPanel()
                    end,
                    settings = BAR_FINDER.appearance.auraVisibility,
                })
            AddFontControls(panel, auraTextSec.tbl, "auraText", { size = 12 }, refreshStyle, {
                row = true,
                settings = BAR_FINDER.advanced.auraText and {
                    size = BAR_FINDER.advanced.auraText.fontSize,
                    font = BAR_FINDER.advanced.auraText.font,
                    outline = BAR_FINDER.advanced.auraText.outline,
                },
            })
            AddColorRow(panel, {
                label = "Font Color",
                setting = BAR_FINDER.advanced.auraText and BAR_FINDER.advanced.auraText.color,
                tbl = auraTextSec.tbl,
                key = "auraTextFontColor",
                default = {0, 0.925, 1, 1},
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })

            if not isAuraPanel then
                AddCheckboxRow(panel, {
                    label = "Independent Position",
                    setting = BAR_FINDER.advanced.auraText.independent,
                    value = auraTextSec.read.barAuraTextIndependent == true,
                    disabled = auraTextSec.disabled,
                    onChange = function(value)
                        if not auraTextSec.write then return end
                        ST.BarTextLayout.SetAuraIndependent(auraTextSec.write,
                            auraTextSec.read, group.style.barFillVertical, value)
                        refreshStyle()
                        CooldownCompanion:RefreshConfigPanel()
                    end,
                })
            end
            if isAuraPanel or auraTextSec.read.barAuraTextIndependent == true then
                AddBarTextPositionControls(panel, auraTextSec.tbl,
                    "barAuraTextAnchor", "barAuraTextOffsetX", "barAuraTextOffsetY", refreshStyle, {
                        settings = BAR_FINDER.advanced.auraText,
                        disabled = auraTextSec.disabled,
                        resolve = function()
                            return ST.BarTextLayout.Resolve(auraTextSec.read, "aura", group.style.barFillVertical)
                        end,
                        prepareKey = "barAuraTextIndependent",
                        prepare = function()
                            ST.BarTextLayout.SetAuraIndependent(auraTextSec.tbl,
                                auraTextSec.read, group.style.barFillVertical, true)
                        end,
                    })
            end
        end

        if auraTextSec.scope ~= "denied" then
            AddAdvancedToggle(auraTextRow, "barAuraText", tabInfoButtons, true, {
                title = "Aura Duration Text Advanced",
                build = BuildBarAuraTextAdvanced,
                unlock = { sec = auraTextSec,
                    enable = auraTextSec.read.showAuraText == false and TURNON_BAR_AURA_TEXT or nil },
            })
        end
        -- Second badge in the chain: gear, then this, then the scope chrome the
        -- lens attaches last. The anchor args below are a placeholder -
        -- AnchorRowBadge re-points the button onto the end of the chain.
        --
        -- On an Aura Panel the anchor and offset rows live in this section's own
        -- gear, so the pointer to the Cooldown Text section would send the user
        -- to a row that is not drawn.
        AnchorRowBadge(auraTextRow, CreateInfoButton(auraTextRow.frame, auraTextRow.frame, "LEFT", "LEFT", 0, 0, isAuraPanel and {
            "Aura Duration Text",
            {"Shows the remaining aura time while the aura is active. Set its Anchor and offsets in this section.", 1, 1, 1, true},
        } or {
            "Aura Duration Text",
            {"Shows the remaining aura time at the bar's time text position while the aura is active. Position follows Cooldown Text unless Independent Position is enabled; the last independent placement is remembered.", 1, 1, 1, true},
        }, auraTextRow))
        auraTextSec:Chrome(auraTextRow)

        auraTextSec:Finish()
        if drawsAuraFormat and not drawsCooldownFormat then
            local auraFormatRow = AddDurationFormatDropdown(durationLeft, group.style, refreshStyle, {
                row = true,
                sharedHelp = true,
                infoButtons = tabInfoButtons,
                setting = BAR_FINDER.appearance.text and BAR_FINDER.appearance.text.durationFormat,
            })
            if auraFormatRow then
                auraTextSec:PanelRowChrome(auraFormatRow)
            end
        end

        if drawsAuraLowTime and not drawsCooldownLowTime then
            AddDurationLowTimeSection()
        end

        -- Aura stack text: Blizzard writes the live stack count; anchored to
        -- the icon square (or the bar with the icon hidden).
        local auraStackSec = BeginLensSection(lens, group, "auraStackText", { column = otherRight })

        local auraStackRow = AddCheckboxRow(otherRight, {
            label = "Show Aura Stack Text",
            setting = BAR_FINDER.appearance.text and BAR_FINDER.appearance.text.auraStacks,
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
            AddFontControls(panel, auraStackSec.tbl, "auraStack", { size = 12 }, refreshStyle, {
                row = true,
                settings = BAR_FINDER.advanced.auraStack and {
                    size = BAR_FINDER.advanced.auraStack.fontSize,
                    font = BAR_FINDER.advanced.auraStack.font,
                    outline = BAR_FINDER.advanced.auraStack.outline,
                },
            })
            -- deferCommit is deliberately absent, matching the stock color-picker
            -- call this row replaced.
            AddColorRow(panel, {
                label = "Font Color",
                setting = BAR_FINDER.advanced.auraStack and BAR_FINDER.advanced.auraStack.color,
                tbl = auraStackSec.tbl,
                key = "auraStackFontColor",
                default = {1, 1, 1, 1},
                hasAlpha = true,
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })
            AddAnchorDropdown(panel, auraStackSec.tbl, "auraStackAnchor", "BOTTOMLEFT", refreshStyle, nil, {
                row = true,
                setting = BAR_FINDER.advanced.auraStack and BAR_FINDER.advanced.auraStack.anchor,
            })
            AddOffsetSliders(panel, auraStackSec.tbl, "auraStackXOffset", "auraStackYOffset", { x = 2, y = 2 }, refreshStyle, {
                row = true,
                settings = BAR_FINDER.advanced.auraStack and {
                    x = BAR_FINDER.advanced.auraStack.xOffset,
                    y = BAR_FINDER.advanced.auraStack.yOffset,
                },
            })
        end

        if auraStackSec.scope ~= "denied" then
            AddAdvancedToggle(auraStackRow, "barAuraStackText", tabInfoButtons, true, {
                title = "Aura Stack Text Advanced",
                build = BuildBarAuraStackTextAdvanced,
                unlock = { sec = auraStackSec,
                    enable = auraStackSec.read.showAuraStackText == false and TURNON_BAR_AURA_STACK_TEXT or nil },
            })
        end
        AnchorRowBadge(auraStackRow, CreateInfoButton(auraStackRow.frame, auraStackRow.frame, "LEFT", "LEFT", 0, 0, {
            "Aura Stack Text",
            {"Shows the live stack count while the aura is active, drawn by the game so it stays accurate in combat. Stack counts cannot drive the bar fill; the count is hidden from addons during combat.", 1, 1, 1, true},
        }, auraStackRow))
        auraStackSec:Chrome(auraStackRow)

        auraStackSec:Finish()
    end

    -- Compact Mode used to close this grid's right column. It is packing, not
    -- look, so it now lives on the Layout tab's Arrangement section beside the
    -- wrap count (its copy membership is unchanged - still this tab's
    -- appearance scope in ST.PANEL_COPY_SCOPES).
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
            setting = BAR_FINDER.appearance.whileAura and BAR_FINDER.appearance.whileAura.icon,
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
        setting = BAR_FINDER.appearance.whileAura and BAR_FINDER.appearance.whileAura.desaturate,
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

    -- Gear panels whose gear did not rebuild (collapsed sections, the bar
    -- icon gate above, the other bars sub-tab) are closed by the
    -- dispatch-level gear build pass that brackets this builder
    -- (RunAdvancedGearBuildPass, AdvancedSettingsPanel.lua).
end

------------------------------------------------------------------------
-- EFFECTS TAB (Aura / Pandemic / Timers / States / Interaction)
--
-- Row grammar (RowWidgets.lua), and the SAME collapse keys the icons Effects
-- tab uses - see the note by the section constants at the top of this file for
-- why they are shared rather than bar-specific.
------------------------------------------------------------------------

-- Active aura indicator: border effect + fill effects rendered by the aura
-- kit while the tracked aura runs. The checkbox reflects whether anything
-- actually renders (enabled AND a visible effect chosen); checking it with
-- no visible effect forces the pulse border, mirroring the icon aura glow.
--
-- `container` is nil when there is nothing to draw into - the group lost its
-- last aura entry, or the Aura section is collapsed. The reconciliation below
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

        -- EnableBarAuraIndicator (file-local, by the Turn On constants) is
        -- the one enable path for this checkbox AND the read-only panel's
        -- Turn On footer.
        local enableRow = AddCheckboxRow(container, {
            label = "Show Active Aura Indicator",
            setting = BAR_FINDER.effects.aura.active,
            value = indicatorOn,
            disabled = auraSec.disabled,
            onChange = function(val)
                if not auraSec.write then return end
                if val then
                    EnableBarAuraIndicator(auraSec.write)
                else
                    auraSec.write.barAuraIndicatorEnabled = false
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
            BuildBarActiveAuraControls(panel, auraSec.tbl, function()
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end, {
                row = true,
                singleRail = true,
                infoButtons = tabInfoButtons,
                fallbackStyle = auraSec.fallbackStyle,
                settings = BAR_FINDER.advanced.activeAura,
            })
        end

        if auraSec.scope ~= "denied" then
            AddAdvancedToggle(enableRow, "barActiveAura", tabInfoButtons, true, {
                title = "Active Aura Indicator Advanced",
                build = BuildBarActiveAuraAdvanced,
                unlock = { sec = auraSec,
                    enable = not indicatorOn and TURNON_BAR_AURA_INDICATOR or nil },
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
            setting = BAR_FINDER.effects.aura.pandemicColor,
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

        ST._AddAdvancedToggle(enableRow, "barPandemicColor", {}, pandemicSec.scope ~= "denied", {
            unlock = { sec = pandemicSec, enable = not pandemicOn and { label = "Enable Pandemic Color", key = "pandemicEffectEnabled" } or nil },
            build = function(panel)
                -- No alpha: the pandemic color REPLACES the aura fill color
                -- (owner ruling — never blends with it), so the live clone and
                -- the mirror both render it opaque.
                --
                -- "Fill Color", not "Pandemic Color": the marker's own color row
                -- sits in the same section now, and two rows reading the same
                -- thing would leave no way to tell the fill from the text.
                AddColorRow(panel, {
                    label = "Fill Color",
                    setting = BAR_FINDER.effects.aura.pandemicFill,
                    indent = false,
                    tbl = pandemicSec.tbl,
                    key = "barPandemicColor",
                    default = {1, 0.5, 0, 1},
                    hasAlpha = false,
                    disabled = pandemicSec.disabled,
                    onConfirm = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end,
                    onChange = ST._RefreshSelectedButtonsPreview,
                })
            end,
        })

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
        setting = BAR_FINDER.effects.aura.pandemicMarker,
        enableOnly = true,
        onModeChanged = function(mode)
            ReconcilePandemicMarkerPreview(lens, mode)
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): the styling rows fill the panel,
    -- so childrenOnly drops the indent they carry when inline. The panel
    -- captures the section's resolved table (sec.tbl), read-only behind the
    -- unlock strip while the section is inherited or the marker is off.
    local function BuildBarPandemicMarkerAdvanced(panel)
        AddPandemicMarkerControls(panel, markerSec.tbl, applyStyle, function()
            if CS.RefreshAdvancedSettingsPanel then
                CS.RefreshAdvancedSettingsPanel()
            end
        end, {
            childrenOnly = true,
            settings = BAR_FINDER.advanced.pandemicMarker,
        })
    end

    -- "barPandemicMarker", not the icons key: every bars gear in this file
    -- carries its own prefixed key (barAuraText, barNameText, barChargeText),
    -- so a panel switch can never rebind an open panel onto the other mode's
    -- builder. The gear-to-section maps name both.
    if markerSec.scope ~= "denied" then
        AddAdvancedToggle(markerRow, "barPandemicMarker", tabInfoButtons, true, {
            title = "Pandemic Marker Advanced",
            build = BuildBarPandemicMarkerAdvanced,
            unlock = { sec = markerSec,
                enable = markerSec.read.pandemicMarkerMode == "off" and TURNON_BAR_PANDEMIC_MARKER or nil },
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

    -- An Aura Panel keeps NONE of the States rows below (the panel predicate
    -- denies every one of them), so that section is skipped outright rather
    -- than re-columned, and the Interaction section at the foot leads with Show
    -- Tooltips in its left column on every bar panel - the standing fill rule
    -- (stated in full in the recipe comment at the top of BuildAppearanceTab's
    -- icons path in GroupTabsAppearance.lua, rule 3). What this predicate still
    -- decides is the icon-square block: an Aura Panel opens it for Show
    -- Tooltips alone, with the bar icon hidden.
    local isAuraPanel = ST.IsAuraPanelGroup(group)

    -- Under a multi selection this tab edits the PANEL, and only this line says
    -- so. No-op in every other lens mode.
    AddLensPanelScopeNote(container, lens)

    -- The remaining indicators all render on the bar's icon square, so the
    -- gate reads the icon's visibility THROUGH THE LENS: showBarIcon is a
    -- per-entry key (the barIcon section), and what the tab offers follows
    -- what the current selection actually renders. A panel that hides icons
    -- can still select an entry that shows its own - its state controls must
    -- not vanish with the panel's toggle - and an entry that hides its icon
    -- has nothing here to configure (the Show Icon row on Appearance is the
    -- way back).
    --
    -- Resolved before the Aura section below because the missing-aura row in it
    -- is icon-bound while the aura indicator beside it is not; the block gate
    -- further down is the same value.
    local effIconSec = BeginLensSection(lens, group, "barIcon")
    local barIconShown = effIconSec.read.showBarIcon ~= false

    -- ================================================================
    -- Aura Indicators
    -- ================================================================
    -- The bars twin of the icons Aura Indicators section (owner ruling
    -- 2026-08-30): the aura family's own section, holding what used to be a lone
    -- "Glows" row, the missing-aura desaturate that used to hang in the States
    -- right column, and - as a SUBHEADING at its foot - the Pandemic pair that
    -- used to be a collapsible of its own. Offered only while the group tracks
    -- an aura, but the indicator builder runs either way and with whatever host
    -- it ends up with: it reconciles its own preview, and an effect left running
    -- by a deleted aura entry - or by a collapsed section - still has to be
    -- cleared.
    local auraLeft, auraRight
    if GroupHasAuraTrackingEntry(group) then
        local _, auraCollapsed = BuildCollapsibleSection(container, "Aura Indicators", EFFECTS_AURA_SECTION, nil, nil, ROW_SECTION)
        if not auraCollapsed then
            -- LEFT the look the aura's PRESENCE gives the bar, RIGHT the look
            -- its ABSENCE gives the icon square - the same split the icons twin
            -- makes.
            auraLeft, auraRight = BeginRowGrid(container)
        end
    end
    BuildBarActiveAuraSection(auraLeft, group, style, lens)

    -- The missing-aura sibling of Desaturate On Cooldown, as its OWN section
    -- (owner ruling 2026-08-16); static desat on the bar's icon square. Same
    -- notes as the icons tab - passives gray by default with entry-side Never
    -- Desaturate as the off switch, and the section is aura-entry-denied plus
    -- aura-tracking-config-only.
    --
    -- It moved here from the spell states, and it keeps the icon gate it had
    -- there unchanged: what it grays is the icon square, so it stays out while
    -- that square does not render. The section around it is deliberately OUTSIDE
    -- the icon-square block below - the aura indicator above was never
    -- icon-bound - which is why this one row carries `barIconShown` itself.
    if auraRight and barIconShown and CanGroupUseOverrideSection(group, "auraMissingDesaturation") then
    local missingSec = BeginLensSection(lens, group, "auraMissingDesaturation")
    local missingRow = AddCheckboxRow(auraRight, {
        label = "Desaturate While Aura Missing",
        setting = BAR_FINDER.effects.aura.missing,
        value = missingSec.read.desaturateWhileAuraNotActive == true,
        disabled = missingSec.disabled,
        onChange = function(val)
            if not missingSec.write then return end
            missingSec.write.desaturateWhileAuraNotActive = missingSec:BoolValue(val)
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })
    -- Anchor args are a placeholder - AnchorRowBadge re-points the button
    -- onto the end of the row's label. Same split the icons Aura row
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

    -- ---------------------------------------------------------------
    -- Pandemic
    -- ---------------------------------------------------------------
    -- A SUBHEADING inside Aura Indicators now (owner ruling 2026-08-30), not a
    -- collapsible of its own: both halves are aura-only, like the rows above
    -- them, and its old "effects_pandemic" key is retired with it.
    --
    -- Still deliberately OUTSIDE the icon-square block below - neither the fill
    -- recolor nor the marker draws on the icon, so hiding the icon must not take
    -- them with it - which the section around it already was. Same aura gate and
    -- same nil-host reconciliation as the rows above.
    --
    -- The section's ONE scope chrome stays on the enable ROW inside
    -- BuildBarPandemicSection (unlike the icons twin, whose chrome moved onto
    -- this subheading), so nothing here attaches chrome of its own.
    local pandemicLeft, pandemicRight
    if auraLeft then
        AddSettingsSubheading(container, "Pandemic")
        -- LEFT the fill half, RIGHT the text half.
        pandemicLeft, pandemicRight = BeginRowGrid(container)
    end
    BuildBarPandemicSection(pandemicLeft, group, style, lens)
    BuildBarPandemicMarkerSection(pandemicRight, group, style, lens)

    -- The remaining indicators all render on the bar's icon square, so they sit
    -- behind the icon gate resolved at the top of this builder.
    --
    -- Show Tooltips is the exception, and only on an Aura Panel: its cell has no
    -- CC button, so the aura host frame carries the tooltip whether or not the
    -- icon draws (see BarsTooltipRowShown above). The block therefore opens for
    -- an Aura Panel with the icon hidden, and the icon-bound rows inside keep
    -- their own gate so nothing else comes through with it. On an ordinary bar
    -- panel the condition is barIconShown and nothing changes.
    if barIconShown or isAuraPanel then
        -- ================================================================
        -- Cooldown / Spell Indicators
        -- ================================================================
        -- The bars twin of the icons mega-section (owner ruling 2026-08-30):
        -- ONE section for everything the spell's own state drives, with the
        -- former Timers and States collapsibles as quiet SUBHEADINGS inside it.
        -- Bars has no spell glows, so there is no Glows subheading here.
        --
        -- Reach is exactly what the two sections had: both were icon-bound and
        -- panel-predicate-gated, so the section is drawn only when at least one
        -- subgroup would draw, which on an Aura Panel (every row denied) or with
        -- the bar icon hidden is never. Each subgroup keeps its own lead
        -- predicate, and the rows inside keep the `barIconShown` gate they
        -- carried.
        local barSpellTimersShown = barIconShown
            and CanGroupUseOverrideSection(group, "showGCDSwipe")
        local barSpellStatesShown = barIconShown
            and CanGroupUseOverrideSection(group, "desaturation")

        if barSpellTimersShown or barSpellStatesShown then
        local _, spellCollapsed = BuildCollapsibleSection(container, "Cooldown / Spell Indicators", EFFECTS_SPELL_SECTION, nil, nil, ROW_SECTION)

        if not spellCollapsed then

        -- ---------------------------------------------------------------
        -- Timers
        -- ---------------------------------------------------------------
        -- The GCD swipe is the subgroup's only row, so on an Aura Panel the
        -- subheading goes with it rather than standing over nothing.
        if barSpellTimersShown then
        AddSettingsSubheading(container, "Timers")
        -- One row; the right column is deliberately empty.
        local timerLeft = BeginRowGrid(container)

        -- One row, no gear: `disabled` is the whole gate, so no inert bracket
        -- is needed - the chrome that undoes it is attached after.
        local gcdSec = BeginLensSection(lens, group, "showGCDSwipe")
        local gcdRow = AddCheckboxRow(timerLeft, {
            label = "Show GCD Swipe",
            setting = BAR_FINDER.effects.spell.gcd,
            value = gcdSec.read.showGCDSwipe == true,
            disabled = gcdSec.disabled,
            onChange = function(val)
                if not gcdSec.write then return end
                gcdSec.write.showGCDSwipe = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
        gcdSec:Chrome(gcdRow)
        end -- Timers subheading

        -- ---------------------------------------------------------------
        -- States
        -- ---------------------------------------------------------------
        -- Every row below is icon-bound AND spell-state-bound, so the
        -- subheading goes with them rather than standing over nothing - the same
        -- pre-check shape the Timers subgroup above uses. The block this sits in
        -- can open for Show Tooltips alone (an Aura Panel with the bar icon
        -- hidden), and on an Aura Panel the panel predicate denies every row
        -- here anyway.
        if barSpellStatesShown then
        AddSettingsSubheading(container, "States")
        -- Spell-side only, now that the missing-aura desaturate has moved into
        -- the Aura Indicators section above. The same even split the icons twin
        -- makes of the same four rows: LEFT whether the spell is READY to cast
        -- (on cooldown, unusable), RIGHT whether it can REACH its target (out of
        -- range, locked out of control). No family captions: both columns are
        -- the cooldown/spell family now.
        local stateLeft, stateRight = BeginRowGrid(container)

        if barIconShown and CanGroupUseOverrideSection(group, "desaturation") then
        local desatSec = BeginLensSection(lens, group, "desaturation")
        local desatRow = AddCheckboxRow(stateLeft, {
            label = "Desaturate On Cooldown",
            setting = BAR_FINDER.effects.spell.desaturate,
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

        -- The two shared builders below own their gears; the callers pass the
        -- denied gate as opts.advanced and the Customize/Turn On footer as
        -- opts.advancedUnlock, so an inert scope's gear stays live and opens
        -- the panel read-only like every hand-written section's.
        if barIconShown and CanGroupUseOverrideSection(group, "unusableDimming") then
        local unusableSec = BeginLensSection(lens, group, "unusableDimming", { column = stateLeft })
        local unusableRow = BuildUnusableDimmingControls(stateLeft, unusableSec.tbl, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, {
            row = true,
            advanced = unusableSec.scope ~= "denied",
            advancedUnlock = { sec = unusableSec,
                enable = unusableSec.read.showUnusable ~= true and TURNON_SHOW_UNUSABLE or nil },
            fallbackStyle = unusableSec.fallbackStyle,
            setting = BAR_FINDER.effects.spell.unusable,
            settings = BAR_FINDER.advanced.unusable,
        })
        unusableSec:Chrome(unusableRow)
        unusableSec:Finish()
        end -- CanGroupUseOverrideSection unusableDimming

        -- Same single-row override the icons States section exposes. The live
        -- bar path already applies range tint to the icon square, so this row is
        -- relevant only while that square renders.
        if barIconShown and CanGroupUseOverrideSection(group, "showOutOfRange") then
        local oorSec = BeginLensSection(lens, group, "showOutOfRange")
        local oorRow = AddCheckboxRow(stateRight, {
            label = "Show Out of Range",
            setting = BAR_FINDER.effects.spell.outOfRange,
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

        -- A lockout stops the cast reaching its target the way distance does, so
        -- it closes the RIGHT column after Out of Range - the icons States twin
        -- does the same.
        if barIconShown and CanGroupUseOverrideSection(group, "lossOfControl") then
        local locSec = BeginLensSection(lens, group, "lossOfControl")
        local locRow = BuildLossOfControlControls(stateRight, locSec.tbl, refreshStyle, {
            row = true,
            setting = BAR_FINDER.effects.spell.lossOfControl,
        })
        locRow:SetDisabled(locSec.disabled)
        locSec:Chrome(locRow)
        end -- CanGroupUseOverrideSection lossOfControl
        end -- States subheading

        end -- not spellCollapsed
        end -- Cooldown / Spell Indicators has at least one subgroup

        -- ================================================================
        -- Interaction
        -- ================================================================
        -- The bars twin of the icons Interaction section: hover and click
        -- behavior, at the foot of the tab rather than trailing the state
        -- rows. It stays INSIDE the icon-square block, which is exactly the two
        -- rows' existing reach - Show Tooltips gets the Aura Panel exception
        -- the block already carries (BarsTooltipRowShown), and Allow Pings,
        -- like the icon-bound rows, has nothing to ping while the bar draws no
        -- icon square.
        local _, interactionCollapsed = BuildCollapsibleSection(container, "Interaction", EFFECTS_INTERACTION_SECTION, nil, nil, ROW_SECTION)

        if not interactionCollapsed then
        -- LEFT column: the hover behavior. RIGHT column: the click behavior,
        -- which an Aura Panel does not offer - and the fill-left-first rule is
        -- why the hover row is on the left rather than beside an empty column.
        local interactionLeft, interactionRight = BeginRowGrid(container)

        local tooltipSec = BeginLensSection(lens, group, "showTooltips", { column = interactionLeft })
        local tooltipRow = BuildShowTooltipsControls(interactionLeft, tooltipSec.tbl, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, {
            row = true,
            advanced = tooltipSec.scope ~= "denied",
            advancedUnlock = { sec = tooltipSec,
                enable = tooltipSec.read.showTooltips ~= true and TURNON_SHOW_TOOLTIPS or nil },
            infoButtons = tabInfoButtons,
            fallbackStyle = tooltipSec.fallbackStyle,
            setting = BAR_FINDER.effects.interaction.tooltips,
            settings = BAR_FINDER.advanced.tooltip,
        })
        tooltipSec:Chrome(tooltipRow)
        tooltipSec:Finish()

        -- Allow Pings is a PANEL setting with no override section of its own
        -- (ST.OVERRIDE_SECTIONS), so under an entry lens it goes read-only with
        -- the rest of the panel-only content instead of letting a panel-wide
        -- edit be made from an entry's page. Its "?" badge stays readable: the
        -- inert walk only reaches AceGUI children, never frame badges.
        --
        -- Not offered on an Aura Panel: the row's own tooltip already says
        -- entries added as auras cannot be pinged, and every entry here is one.
        if not CooldownCompanion:IsAuraPanel(group) then
        local pingsSec = BeginLensSection(lens, group, nil, { column = interactionRight })
        BuildAllowPingsControls(interactionRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, {
            row = true,
            setting = BAR_FINDER.effects.interaction.pings,
        })
        pingsSec:Finish()
        end
        end -- not interactionCollapsed
    end

    -- Gear panels whose gear did not rebuild are closed by the dispatch-level
    -- gear build pass that brackets this builder (RunAdvancedGearBuildPass,
    -- AdvancedSettingsPanel.lua).
end

------------------------------------------------------------------------
-- SETTINGS FINDER CATALOG
------------------------------------------------------------------------

local BAR_FINDER_SCOPE = { "panel", "entry" }

local function BarFinderUsesBars(context)
    return context and context.group and context.displayMode == "bars"
end

-- Finder predicates resolve the same current style lens as the builders. This
-- is table-only work over the selected panel/entry; searching never builds an
-- unopened tab or calls a gameplay API.
local function BarFinderLens(context)
    local group = context and context.group
    if not group then return nil end
    local cached = rawget(context, "_cdcBarFinderLens")
    if cached and cached.group == group and cached.buttonData == context.buttonData then
        return cached.lens
    end
    local lens = ResolveStyleLens(group)
    rawset(context, "_cdcBarFinderLens", {
        group = group,
        buttonData = context.buttonData,
        lens = lens,
    })
    return lens
end

local function BarFinderStyle(context)
    local group = context and context.group
    local lens = BarFinderLens(context)
    return (lens and lens.effective) or (group and group.style) or nil
end

local function BarFinderSectionState(context, sectionId)
    local group = context and context.group
    local lens = BarFinderLens(context)
    if not (group and lens) then return nil, nil end
    local _, read, write = ResolveLensSection(lens, group, sectionId)
    return read, write
end

local function BarFinderAuraPositionVisible(context)
    if ST.IsAuraPanelGroup(context.group) then return true end
    local read = BarFinderSectionState(context, "auraText")
    return read and read.barAuraTextIndependent == true or false
end

local function BarFinderTracksAura(context)
    return context and context.group and GroupHasAuraTrackingEntry(context.group) or false
end

local function BarFinderIconShown(context)
    local style = BarFinderStyle(context)
    return style and style.showBarIcon ~= false or false
end

local function BarFinderCanUse(context, sectionId)
    return context and context.group
        and CanGroupUseOverrideSection(context.group, sectionId) or false
end

local function BarFinderWrap(predicate)
    return function(context)
        return BarFinderUsesBars(context)
            and (predicate == nil or predicate(context) == true)
    end
end

-- Advanced routes index on STRUCTURE alone: the gear now exists for every
-- scope except "denied", and an uncustomized section or an off parent toggle
-- opens its panel read-only behind the unlock strip with the searched row
-- drawn inside. `structural` keeps the gates that still remove the gear's row
-- outright (aura tracking, the cooldown-text row, the marker's text surface).
local function BarFinderAdvanced(sectionId, structural)
    return BarFinderWrap(function(context)
        if structural and not structural(context) then return false end
        local group = context and context.group
        local lens = BarFinderLens(context)
        if not (group and lens) then return false end
        local scope = ResolveLensSection(lens, group, sectionId)
        return scope ~= "denied"
    end)
end

local function BarFinderRoute(prefix, tab, section, sectionLabel, collapseKey,
        applies, advancedKey, sectionId)
    return ST._DefineSettingRoute({
        idPrefix = prefix,
        scope = BAR_FINDER_SCOPE,
        tab = tab,
        tabLabel = tab == "effects" and "Indicators" or "Appearance",
        section = section,
        sectionId = sectionId or section,
        sectionLabel = sectionLabel,
        collapseKeys = collapseKey and { collapseKey } or nil,
        rowScope = "primary",
        advancedKey = advancedKey,
        applies = BarFinderWrap(applies),
    })
end

local BAR_FINDER_ADVANCED_SECTION_LABELS = {
    barIcon = "Icon",
    barNameText = "Name Text",
    barCooldownText = "Cooldown Text",
    barChargeText = "Count Text",
    barReadyText = "Ready Text",
    barAuraText = "Aura Duration Text",
    barAuraStackText = "Aura Stack Text",
}

local BAR_FINDER_TEXT_SECTION_LABELS = {
    cooldownText = "Cooldown Text",
    auraText = "Aura Duration Text",
    durationLowTime = "Low-Time Text",
}

local function BarFinderTextRoute(prefix, sectionId, advancedKey, applies)
    local sectionLabel = BAR_FINDER_ADVANCED_SECTION_LABELS[advancedKey]
        or BAR_FINDER_TEXT_SECTION_LABELS[sectionId]
        or "Text & Icon"
    return BarFinderRoute(prefix, "appearance", "textIcon", sectionLabel,
        "barappearance_textIcon", applies, advancedKey, sectionId)
end

local function BarFinderEffectRoute(prefix, section, sectionLabel, applies,
        advancedKey, sectionId)
    return BarFinderRoute(prefix, "effects", section, sectionLabel, section,
        applies, advancedKey, sectionId)
end

local function BarFinderCooldownText(context)
    return context and context.group and not ST.IsAuraPanelGroup(context.group)
end

local function BarFinderCooldownTextVisible(context)
    if not BarFinderCooldownText(context) then return false end
    local read = BarFinderSectionState(context, "cooldownText")
    return read and read.showCooldownText == true or false
end

local function BarFinderAuraTextVisible(context)
    if not BarFinderTracksAura(context) then return false end
    local read = BarFinderSectionState(context, "auraText")
    return read and read.showAuraText ~= false or false
end

local function BarFinderDurationFormat(context)
    local group = context and context.group
    if not group then return false end
    local panelStyle = group.style or {}
    local effectiveStyle = BarFinderStyle(context) or panelStyle
    return BarsDrawCooldownDurationRows(group, panelStyle)
        or BarsDrawCooldownDurationRows(group, effectiveStyle)
        or BarsDrawAuraDurationRows(group, panelStyle)
        or BarsDrawAuraDurationRows(group, effectiveStyle)
end

local function BarFinderLowTime(context)
    local group = context and context.group
    local style = BarFinderStyle(context)
    return group and style and BarsDrawDurationRows(group, style) or false
end

local function BarFinderLowTimeState(context)
    local read = BarFinderSectionState(context, "durationLowTime") or {}
    local first = tonumber(read.durationLowTimeThreshold) or 0
    local second = tonumber(read.durationLowTimeThreshold2) or 0
    return read, first, second, first > 0, second > 0 and second < first
end

local function BarFinderLowTimeAuraToggle(context)
    if not BarFinderLowTime(context) or not BarFinderTracksAura(context) then return false end
    local _, _, _, active = BarFinderLowTimeState(context)
    if not active then return false end
    local group = context.group
    if ST.IsAuraPanelGroup(group) then return false end
    if context.scope == "entry" and context.buttonData
        and ST.IsAuraSectionEntry(group, context.buttonData) then
        return false
    end
    return BarsDrawAuraDurationRows(group, BarFinderStyle(context))
end

if ST._DefineSettingRoute then
    BAR_FINDER.appearance.barSettings = BarFinderRoute(
        "panel.bars.appearance.settings", "appearance", "barSettings",
        "Bar Settings", "barappearance_settings"):Settings({
        length = { label = "Bar Length" },
        height = { label = "Bar Height" },
        vertical = { label = "Vertical Bar Fill", aliases = { "orientation" } },
        reverse = { label = "Flip Fill/Drain Direction", aliases = { "reverse fill" } },
        spacing = {
            label = "Bar Spacing",
            applies = function(context)
                local buttons = context and context.group and context.group.buttons
                return buttons and #buttons > 1 or false
            end,
        },
        texture = { label = "Bar Texture" },
    })

    BAR_FINDER.appearance.colors = BarFinderRoute(
        "panel.bars.appearance.colors", "appearance", "barColors",
        "Bar Colors", nil):Settings({
        bar = {
            label = "Bar Color", sectionId = "barColor",
            applies = function(context) return BarFinderCanUse(context, "barColor") end,
        },
        background = { label = "Bar Background Color", sectionId = "barBgColor" },
        cooldown = {
            label = "Bar Cooldown Color", sectionId = "barCooldownColor",
            applies = function(context) return BarFinderCanUse(context, "barCooldownColor") end,
        },
        recharging = {
            label = "Bar Recharging Color", aliases = { "charges" }, sectionId = "barChargeColor",
            applies = function(context) return BarFinderCanUse(context, "barCooldownColor") end,
        },
        aura = {
            label = "Bar Aura Timer Color", aliases = { "aura fill color" }, sectionId = "barActiveAura",
            applies = BarFinderTracksAura,
        },
    })

    BAR_FINDER.appearance.border = BarFinderRoute(
        "panel.bars.appearance.border", "appearance", "borderSettings",
        "Border", "barappearance_border", nil, nil, "borderSettings"):Settings({
        thickness = { advancedKey = "panelBorder", label = "Border Thickness" },
        size = { advancedKey = "panelBorder",
            label = "Border Size",
            applies = function(context)
                local read = BarFinderSectionState(context, "borderSettings")
                return read and ST.GetBorderRenderMode(read, "borderRenderMode")
                    ~= ST.BORDER_RENDER_MODE_CRISP
            end,
        },
        color = { label = "Border Color" },
    })

    BAR_FINDER.appearance.tint = BarFinderRoute(
        "panel.bars.appearance.iconTint", "appearance", "iconTint",
        "Icon Tint", "barappearance_iconTint", BarFinderIconShown, nil,
        "iconTint"):Settings({
        base = { label = "Base Icon Color" },
        separateCooldown = {
            label = "Use Separate Cooldown Tint",
            applies = function(context) return BarFinderCanUse(context, "desaturation") end,
        },
        cooldown = { advancedKey = "iconCooldownTintEnabled",
            label = "Cooldown Icon Color",
            applies = function(context)
                if not BarFinderCanUse(context, "desaturation") then return false end
                local read = BarFinderSectionState(context, "iconTint")
                return read and read.iconCooldownTintEnabled == true or false
            end,
        },
        separateAura = { label = "Use Separate Aura Tint", applies = BarFinderTracksAura },
        aura = { advancedKey = "iconAuraTintEnabled",
            label = "Aura Active Icon Color",
            applies = function(context)
                if not BarFinderTracksAura(context) then return false end
                local read = BarFinderSectionState(context, "iconTint")
                return read and read.iconAuraTintEnabled == true or false
            end,
        },
    })

    BAR_FINDER.appearance.text = BarFinderTextRoute(
        "panel.bars.appearance.text", "textIcon", nil):Settings({
        icon = { label = "Show Icon", sectionId = "barIcon" },
        name = { label = "Show Name Text", sectionId = "barNameText" },
        cooldown = {
            label = "Show Cooldown Text", sectionId = "cooldownText",
            applies = BarFinderCooldownText,
        },
        count = {
            label = "Show Count Text (Charges/Uses)", aliases = { "charges", "uses" },
            sectionId = "chargeText",
            applies = function(context) return BarFinderCanUse(context, "chargeText") end,
        },
        ready = {
            label = "Show Ready Text", sectionId = "barReadyText",
            applies = function(context) return BarFinderCanUse(context, "barReadyText") end,
        },
        auraDuration = {
            label = "Show Aura Duration Text", sectionId = "auraText",
            applies = BarFinderTracksAura,
        },
        auraStacks = {
            label = "Show Aura Stack Text", sectionId = "auraStackText",
            applies = BarFinderTracksAura,
        },
        durationFormat = {
            label = "Duration Format", aliases = { "timer format" },
            applies = BarFinderDurationFormat,
        },
    })

    BAR_FINDER.appearance.cooldownVisibility = BarFinderTextRoute(
        "panel.bars.appearance.cooldownVisibility", "cooldownText", "barCooldownText",
        BarFinderCooldownTextVisible):Settings({
        mode = { label = "Visible", aliases = { "cooldown text visibility" } },
        threshold = {
            label = "Show During Last", aliases = { "cooldown text threshold" },
            applies = function(context)
                local read = BarFinderSectionState(context, "cooldownText")
                return read and CooldownCompanion.GetDurationTextVisibilityThreshold
                    and CooldownCompanion.GetDurationTextVisibilityThreshold(read, "cooldown") ~= nil
            end,
        },
    })

    BAR_FINDER.appearance.auraVisibility = BarFinderTextRoute(
        "panel.bars.appearance.auraVisibility", "auraText", "barAuraText",
        BarFinderAuraTextVisible):Settings({
        mode = { label = "Visible", aliases = { "aura text visibility" } },
        threshold = {
            label = "Show During Last", aliases = { "aura text threshold" },
            applies = function(context)
                local read = BarFinderSectionState(context, "auraText")
                return read and CooldownCompanion.GetDurationTextVisibilityThreshold
                    and CooldownCompanion.GetDurationTextVisibilityThreshold(read, "aura") ~= nil
            end,
        },
    })

    BAR_FINDER.appearance.lowTime = BarFinderTextRoute(
        "panel.bars.appearance.lowTime", "durationLowTime", nil,
        BarFinderLowTime):Settings({
        enabled = { label = "Change Text Near Expiry", aliases = { "low time", "warning time" } },
        warningThreshold = { advancedKey = "durationLowTime",
            label = "Start Warning Below",
            applies = function(context) local _, _, _, active = BarFinderLowTimeState(context); return active end,
        },
        warningColor = { advancedKey = "durationLowTime",
            label = "Warning Color",
            applies = function(context) local _, _, _, active = BarFinderLowTimeState(context); return active end,
        },
        auras = { advancedKey = "durationLowTime", label = "Also Apply to Aura Text", applies = BarFinderLowTimeAuraToggle },
        critical = { advancedKey = "durationLowTime",
            label = "Add Critical Styling",
            applies = function(context) local _, _, _, active = BarFinderLowTimeState(context); return active end,
        },
        criticalThreshold = { advancedKey = "durationLowTime",
            label = "Start Critical Below",
            applies = function(context) local _, _, _, _, active = BarFinderLowTimeState(context); return active end,
        },
        criticalColor = { advancedKey = "durationLowTime",
            label = "Critical Color",
            applies = function(context) local _, _, _, _, active = BarFinderLowTimeState(context); return active end,
        },
        decimals = { advancedKey = "durationLowTime",
            label = "Show Decimals Near Expiry",
            applies = function(context) local _, _, _, active = BarFinderLowTimeState(context); return active end,
        },
    })

    BAR_FINDER.appearance.whileAura = BarFinderRoute(
        "panel.bars.appearance.whileAura", "appearance", "whileAuraActive",
        "While Aura Active", "barappearance_whileAuraActive", function(context)
            return BarFinderTracksAura(context) and BarFinderIconShown(context)
        end, nil, "whileAuraActive"):Settings({
        icon = {
            label = "Show Aura Icon",
            applies = function(context)
                local group = context and context.group
                if not group or ST.IsAuraPanelGroup(group) then return false end
                return not (context.scope == "entry" and context.buttonData
                    and CooldownCompanion:IsAuraIconForcedEntry(context.buttonData))
            end,
        },
        desaturate = { label = "Desaturate Icon", aliases = { "while aura active" } },
    })

    local iconAdvanced = BarFinderTextRoute(
        "panel.bars.appearance.iconAdvanced", "barIcon", "barIcon",
        BarFinderAdvanced("barIcon"))
    BAR_FINDER.advanced.icon = iconAdvanced:Settings({
        flip = { label = "Flip Icon Side" },
        offset = { label = "Icon Offset" },
        customSize = { label = "Custom Icon Size" },
        size = {
            label = "Icon Size",
            applies = function(context)
                local read = BarFinderSectionState(context, "barIcon")
                return read and read.barIconSizeOverride == true or false
            end,
        },
        zoom = { label = "Icon Zoom", sectionId = "iconZoom" },
    })

    BAR_FINDER.advanced.name = BarFinderTextRoute(
        "panel.bars.appearance.nameAdvanced", "barNameText", "barNameText",
        BarFinderAdvanced("barNameText")):Settings({
        anchor = { label = "Anchor", aliases = { "position", "center", "flip name text" } },
        fontSize = { label = "Font Size" }, font = { label = "Font" },
        outline = { label = "Font Outline" }, color = { label = "Font Color" },
        xOffset = { label = "X Offset" }, yOffset = { label = "Y Offset" },
    })

    BAR_FINDER.advanced.cooldown = BarFinderTextRoute(
        "panel.bars.appearance.cooldownAdvanced", "cooldownText", "barCooldownText",
        BarFinderAdvanced("cooldownText", BarFinderCooldownText)):Settings({
        anchor = { label = "Anchor", aliases = { "position", "center", "ready text position", "flip time text" } },
        fontSize = { label = "Font Size" }, font = { label = "Font" },
        outline = { label = "Font Outline" }, color = { label = "Font Color" },
        xOffset = { label = "X Offset" }, yOffset = { label = "Y Offset" },
    })

    BAR_FINDER.advanced.charge = BarFinderTextRoute(
        "panel.bars.appearance.countAdvanced", "chargeText", "barChargeText",
        BarFinderAdvanced("chargeText",
            function(context) return BarFinderCanUse(context, "chargeText") end)):Settings({
        fontSize = { label = "Font Size" }, font = { label = "Font" },
        outline = { label = "Font Outline" },
        chargeFontColor = { label = "Font Color (Max Charges)" },
        chargeFontColorMissing = { label = "Font Color (Missing Charges)" },
        chargeFontColorZero = { label = "Font Color (Zero Charges)" },
        anchor = { label = "Anchor" }, xOffset = { label = "X Offset" },
        yOffset = { label = "Y Offset" },
    })

    BAR_FINDER.advanced.ready = BarFinderTextRoute(
        "panel.bars.appearance.readyAdvanced", "barReadyText", "barReadyText",
        BarFinderAdvanced("barReadyText",
            function(context) return BarFinderCanUse(context, "barReadyText") end)):Settings({
        text = { label = "Ready Text" }, color = { label = "Ready Text Color" },
        fontSize = { label = "Font Size" }, font = { label = "Font" },
        outline = { label = "Font Outline" },
    })

    BAR_FINDER.advanced.auraText = BarFinderTextRoute(
        "panel.bars.appearance.auraTextAdvanced", "auraText", "barAuraText",
        BarFinderAdvanced("auraText", BarFinderTracksAura)):Settings({
        fontSize = { label = "Font Size" }, font = { label = "Font" },
        outline = { label = "Font Outline" }, color = { label = "Font Color" },
        independent = {
            label = "Independent Position", aliases = { "separate aura position", "aura anchor", "center aura text", "aura offset" },
            applies = function(context) return not ST.IsAuraPanelGroup(context.group) end,
        },
        anchor = { label = "Anchor", aliases = { "position", "center" }, applies = BarFinderAuraPositionVisible },
        xOffset = { label = "X Offset", applies = BarFinderAuraPositionVisible },
        yOffset = { label = "Y Offset", applies = BarFinderAuraPositionVisible },
    })

    BAR_FINDER.advanced.auraStack = BarFinderTextRoute(
        "panel.bars.appearance.auraStackAdvanced", "auraStackText", "barAuraStackText",
        BarFinderAdvanced("auraStackText", BarFinderTracksAura)):Settings({
        fontSize = { label = "Font Size" }, font = { label = "Font" },
        outline = { label = "Font Outline" }, color = { label = "Font Color" },
        anchor = { label = "Anchor" }, xOffset = { label = "X Offset" },
        yOffset = { label = "Y Offset" },
    })

    local auraEffects = BarFinderEffectRoute(
        "panel.bars.effects.aura", EFFECTS_AURA_SECTION, "Aura Indicators",
        BarFinderTracksAura)
    BAR_FINDER.effects.aura = auraEffects:Settings({
        active = { label = "Show Active Aura Indicator", sectionId = "barActiveAura" },
        missing = {
            label = "Desaturate While Aura Missing", sectionId = "auraMissingDesaturation",
            applies = function(context)
                return BarFinderIconShown(context)
                    and BarFinderCanUse(context, "auraMissingDesaturation")
            end,
        },
        pandemicColor = { label = "Show Pandemic Color", sectionId = "pandemic" },
        pandemicFill = { advancedKey = "barPandemicColor",
            label = "Fill Color", aliases = { "pandemic fill color" }, sectionId = "pandemic",
            applies = function(context)
                local read = BarFinderSectionState(context, "pandemic")
                return read and read.pandemicEffectEnabled == true or false
            end,
        },
        pandemicMarker = {
            label = "Pandemic Marker", sectionId = "pandemic",
            applies = BarFinderAuraTextVisible,
        },
    })

    local spellEffects = BarFinderEffectRoute(
        "panel.bars.effects.spell", EFFECTS_SPELL_SECTION,
        "Cooldown / Spell Indicators")
    local function SpellStates(context)
        return BarFinderIconShown(context) and BarFinderCanUse(context, "desaturation")
    end
    BAR_FINDER.effects.spell = spellEffects:Settings({
        gcd = {
            label = "Show GCD Swipe", sectionId = "showGCDSwipe",
            applies = function(context)
                return BarFinderIconShown(context) and BarFinderCanUse(context, "showGCDSwipe")
            end,
        },
        desaturate = {
            label = "Desaturate On Cooldown", sectionId = "desaturation",
            applies = SpellStates,
        },
        unusable = {
            label = "Show Unusable Visual", sectionId = "unusableDimming",
            applies = function(context)
                return SpellStates(context) and BarFinderCanUse(context, "unusableDimming")
            end,
        },
        outOfRange = {
            label = "Show Out of Range", sectionId = "showOutOfRange",
            applies = function(context)
                return SpellStates(context) and BarFinderCanUse(context, "showOutOfRange")
            end,
        },
        lossOfControl = {
            label = "Show Loss of Control", sectionId = "lossOfControl",
            applies = function(context)
                return SpellStates(context) and BarFinderCanUse(context, "lossOfControl")
            end,
        },
    })

    local interaction = BarFinderEffectRoute(
        "panel.bars.effects.interaction", EFFECTS_INTERACTION_SECTION,
        "Interaction")
    BAR_FINDER.effects.interaction = interaction:Settings({
        tooltips = { label = "Show Tooltips", sectionId = "showTooltips", applies = function(context)
            return BarsTooltipRowShown(context.group, BarFinderStyle(context))
        end },
        pings = { label = "Allow Pings", applies = function(context)
            return BarFinderIconShown(context)
                and not CooldownCompanion:IsAuraPanel(context.group)
        end },
    })

    local ActiveAuraAdvanced = BarFinderAdvanced(
        "barActiveAura", BarFinderTracksAura)
    local function ActiveAuraStyle(context)
        local read = BarFinderSectionState(context, "barActiveAura") or {}
        local style = read.barAuraEffect or "color"
        if style == "lcgProc" or style == "lcgButton" then
            style = "glow"
        elseif style == "lcgAutoCast" then
            style = "autocast"
        end
        if style == "none" then style = "color" end
        return style, read
    end
    local function ActiveAuraStyleIs(...)
        local allowed = {}
        for index = 1, select("#", ...) do allowed[select(index, ...)] = true end
        return function(context)
            local style = ActiveAuraStyle(context)
            return allowed[style] == true
        end
    end

    local activeAura = BarFinderEffectRoute(
        "panel.bars.effects.activeAura", EFFECTS_AURA_SECTION, "Aura Indicators",
        ActiveAuraAdvanced, "barActiveAura", "barActiveAura")
    BAR_FINDER.advanced.activeAura = activeAura:Settings({
        style = { label = "Glow Style", aliases = { "border effect", "aura indicator style" } },
        color = { label = "Effect Color" },
        color2 = { label = "Second Color", applies = ActiveAuraStyleIs("colorShift") },
        borderSize = {
            label = "Border Size",
            applies = ActiveAuraStyleIs("solid", "pulse", "pulsingBorder", "colorShift"),
        },
        pulseDuration = {
            label = "Border Pulse Duration", aliases = { "pulse duration" },
            applies = ActiveAuraStyleIs("pulse", "pulsingBorder"),
        },
        shiftDuration = {
            label = "Border Shift Duration", aliases = { "shift duration" },
            applies = ActiveAuraStyleIs("colorShift"),
        },
        dashLength = { label = "Dash Length", applies = ActiveAuraStyleIs("dashes") },
        dashThickness = { label = "Dash Thickness", applies = ActiveAuraStyleIs("dashes") },
        dashCount = { label = "Number of Dashes", applies = ActiveAuraStyleIs("dashes") },
        lapDuration = { label = "Lap Duration", applies = ActiveAuraStyleIs("dashes") },
        lineLength = { label = "Line Length", applies = ActiveAuraStyleIs("pixel") },
        lineThickness = { label = "Line Thickness", applies = ActiveAuraStyleIs("pixel") },
        speed = { label = "Speed", applies = ActiveAuraStyleIs("pixel") },
        lineCount = { label = "Number of Lines", applies = ActiveAuraStyleIs("pixel") },
        glowSize = { label = "Glow Size", applies = ActiveAuraStyleIs("glow", "ants", "proc") },
        particleScale = { label = "Particle Scale", applies = ActiveAuraStyleIs("autocast") },
        frequency = { label = "Frequency", applies = ActiveAuraStyleIs("autocast") },
        pulseFill = { label = "Pulse Bar Fill" },
        pulseFillDuration = {
            label = "Fill Pulse Duration", aliases = { "pulse duration" },
            applies = function(context)
                local _, read = ActiveAuraStyle(context)
                return read.barAuraPulseEnabled == true
            end,
        },
        colorShiftFill = { label = "Color Shift Bar Fill" },
        colorShiftDuration = {
            label = "Fill Shift Duration", aliases = { "shift duration" },
            applies = function(context)
                local _, read = ActiveAuraStyle(context)
                return read.barAuraColorShiftEnabled == true
            end,
        },
        shiftColor = {
            label = "Shift Color",
            applies = function(context)
                local _, read = ActiveAuraStyle(context)
                return read.barAuraColorShiftEnabled == true
            end,
        },
    })

    BAR_FINDER.advanced.pandemicMarker = BarFinderEffectRoute(
        "panel.bars.effects.pandemicMarker", EFFECTS_AURA_SECTION,
        "Aura Indicators", BarFinderAdvanced("pandemic", BarFinderAuraTextVisible),
        "barPandemicMarker", "pandemic"):Settings({
        text = { label = "Marker Text" },
        coloring = { label = "Marker Coloring" },
        color = {
            label = "Marker Color",
            applies = function(context)
                local read = BarFinderSectionState(context, "pandemic")
                return read and (read.pandemicMarkerColorMode or "marker") ~= "off"
            end,
        },
    })

    BAR_FINDER.advanced.unusable = BarFinderEffectRoute(
        "panel.bars.effects.unusable", EFFECTS_SPELL_SECTION,
        "Cooldown / Spell Indicators", BarFinderAdvanced("unusableDimming",
            function(context)
                return SpellStates(context) and BarFinderCanUse(context, "unusableDimming")
            end),
        "unusableVisual", "unusableDimming"):Settings({
        dim = { label = "Dim Icon" },
        dimColor = {
            label = "Unusable Dim Color",
            applies = function(context)
                local read = BarFinderSectionState(context, "unusableDimming")
                return read and ST.UnusableVisualUsesDimTint(read) or false
            end,
        },
        desaturate = { label = "Desaturate Icon" },
    })

    BAR_FINDER.advanced.tooltip = BarFinderEffectRoute(
        "panel.bars.effects.tooltip", EFFECTS_INTERACTION_SECTION,
        "Interaction", BarFinderAdvanced("showTooltips", function(context)
            return BarsTooltipRowShown(context.group, BarFinderStyle(context))
        end),
        "tooltipBehavior", "showTooltips"):Settings({
        position = { label = "Tooltip Position" },
        hideInCombat = { label = "Hide Tooltips in Combat" },
    })
end

-- Expose for the tab dispatchers (GroupTabsAppearance.lua / GroupTabsEffects.lua)
ST._BuildBarAppearanceTab = BuildBarAppearanceTab
ST._BuildBarEffectsTab = BuildBarEffectsTab
