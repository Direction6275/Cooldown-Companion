--[[
    CooldownCompanion - ConfigSettings/BarModeTabs.lua: Bar-mode appearance and effects tab builders
]]

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
local GroupHasAuraTrackingEntry = ST._GroupHasAuraTrackingEntry
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls

-- Style lens (Helpers.lua). Selecting an entry turns these tabs into a view of
-- that entry's effective values, with per-section scope deciding where - or
-- whether - each section writes. Helpers.lua loads first (the .toc), so these
-- resolve at load like every other import above.
local ResolveStyleLens = ST._ResolveStyleLens
local ResolveLensSection = ST._ResolveLensSection
local AttachRowScopeChrome = ST._AttachRowScopeChrome
local AttachHeadingScopeChrome = ST._AttachHeadingScopeChrome
local MarkInertRange = ST._MarkInertRange
local ApplyInertRange = ST._ApplyInertRange

-- Imports from SectionBuilders.lua
local BuildBorderControls = ST._BuildBorderControls
local BuildLossOfControlControls = ST._BuildLossOfControlControls
local BuildUnusableDimmingControls = ST._BuildUnusableDimmingControls
local BuildShowTooltipsControls = ST._BuildShowTooltipsControls
local BuildAllowPingsControls = ST._BuildAllowPingsControls
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown
local AddPandemicMarkerControls = ST._AddPandemicMarkerControls

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
-- GroupTabs.lua; the sections below conform to them rather than restating them.
local ROW_SECTION = { leftAligned = true }

-- The bar Effects tab draws the same four sections as the icons Effects tab
-- and deliberately SHARES their collapse keys, so the gear-to-section map
-- GroupTabs owns (ST._INDICATORS_SECTION_BY_ADVANCED_KEY) covers both tabs
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
-- Shaped and named after ST._APPEARANCE_SECTION_BY_ADVANCED_KEY (GroupTabs.lua),
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

-- Where each bars override section is EDITED, now that the panel tabs are the
-- lens onto a selected entry: the tab that draws it and the collapse key of the
-- section it is drawn in. Per-MODE axis, because the same section id is drawn
-- somewhere else entirely on an icons panel.
--
-- This file loads BEFORE GroupTabs.lua (the .toc), which declares the `icons`
-- axis the same way, so the table is created here and that file's own `or {}`
-- keeps it. Neither axis assignment can clobber the other.
--
-- No collapseKey where a section has no collapsible of its own: the four bar
-- colors sit in a heading-less grid that is always drawn, so there is nothing
-- to uncollapse on the way to them.
ST._SECTION_HOME = ST._SECTION_HOME or {}
ST._SECTION_HOME.bars = {
    barColor = { tab = "appearance" },
    barBgColor = { tab = "appearance" },
    barCooldownColor = { tab = "appearance" },
    barChargeColor = { tab = "appearance" },
    borderSettings = { tab = "appearance", collapseKey = "barappearance_border" },
    iconTint = { tab = "appearance", collapseKey = "barappearance_iconTint" },
    barIcon = { tab = "appearance", collapseKey = "barappearance_textIcon" },
    barNameText = { tab = "appearance", collapseKey = "barappearance_textIcon" },
    cooldownText = { tab = "appearance", collapseKey = "barappearance_textIcon" },
    chargeText = { tab = "appearance", collapseKey = "barappearance_textIcon" },
    barReadyText = { tab = "appearance", collapseKey = "barappearance_textIcon" },
    auraText = { tab = "appearance", collapseKey = "barappearance_textIcon" },
    auraStackText = { tab = "appearance", collapseKey = "barappearance_textIcon" },
    -- Icon Zoom is edited inside the Show Icon gear's advanced panel in bar
    -- mode, so its home is that gear's section.
    iconZoom = { tab = "appearance", collapseKey = "barappearance_textIcon" },
    barActiveAura = { tab = "effects", collapseKey = EFFECTS_GLOWS_SECTION },
    pandemic = { tab = "effects", collapseKey = EFFECTS_PANDEMIC_SECTION },
    -- The Timers and States sections are drawn only while the PANEL shows the
    -- bar icon (BuildBarEffectsTab): everything in them renders on the icon
    -- square. A consumer that navigates here still lands on the right tab and
    -- section key either way.
    showGCDSwipe = { tab = "effects", collapseKey = EFFECTS_TIMERS_SECTION },
    desaturation = { tab = "effects", collapseKey = EFFECTS_STATES_SECTION },
    unusableDimming = { tab = "effects", collapseKey = EFFECTS_STATES_SECTION },
    lossOfControl = { tab = "effects", collapseKey = EFFECTS_STATES_SECTION },
    showTooltips = { tab = "effects", collapseKey = EFFECTS_STATES_SECTION },
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
-- wholesale style replacement that keeps the same context (Copy Style From
-- Panel assigns a fresh group.style outright) would leave a captured table
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
            -- RevertSection cannot clear - the same reason the icons tab drops
            -- Duration Format from an owned Cooldown Text section.
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

    -- Sections with NO override identity of their own (bar geometry, the bar
    -- texture): an entry cannot own them, so under an entry lens they say
    -- "Applies to all entries" and go read-only rather than quietly letting a
    -- panel-wide edit be made from an entry's page. They keep reading and
    -- writing the PANEL style, which is the value they claim to apply to; the
    -- rows are disabled, so no callback of theirs can run.
    local panelOnlyInert = lens.mode == "entry"

    -- ================================================================
    -- Bar Settings (length, height, spacing, texture)
    -- ================================================================
    local barSettingsHeading, barSettingsCollapsed = BuildCollapsibleSection(container, "Bar Settings", "barappearance_settings", nil, nil, ROW_SECTION)
    -- Panel-only (sectionId nil). Safe with no entry selected: panel and multi
    -- scope attach no chrome at all.
    AttachHeadingScopeChrome(barSettingsHeading, lens, group, nil)

    if not barSettingsCollapsed then
    -- LEFT column: how one bar is shaped. RIGHT column: how the bars sit
    -- together and what they are drawn with.
    local barLeft, barRight = BeginRowGrid(container)
    local barLeftInertMark = panelOnlyInert and MarkInertRange(barLeft) or nil
    local barRightInertMark = panelOnlyInert and MarkInertRange(barRight) or nil

    AddSliderRow(barLeft, {
        label = "Bar Length",
        min = 10, max = 500, step = 0.1,
        value = style.barLength or 180,
        disabled = panelOnlyInert,
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
        disabled = panelOnlyInert,
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
            disabled = panelOnlyInert,
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
    -- The read-only pass runs after all of that (ApplyInertRange below), so the
    -- lock's own SetDisabled and the lens' cannot fight over the row.
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

    if barLeftInertMark then
        ApplyInertRange(barLeft, barLeftInertMark)
        ApplyInertRange(barRight, barRightInertMark)
    end
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
        local _, sectionRead, sectionWrite = ResolveLensSection(lens, group, sectionId)
        local row = AddColorRow(column, {
            label = label,
            tbl = sectionWrite or sectionRead, key = key,
            default = default, hasAlpha = true,
            disabled = sectionWrite == nil,
            onConfirm = refreshStyle, onChange = refreshStyle,
        })
        AttachRowScopeChrome(row, lens, group, sectionId)
        return row
    end

    AddBarColorRow(colorLeft, "barColor", "Bar Color", "barColor", {0.2, 0.6, 1.0, 1.0})
    AddBarColorRow(colorLeft, "barBgColor", "Bar Background Color", "barBgColor", {0.1, 0.1, 0.1, 0.8})
    AddBarColorRow(colorRight, "barCooldownColor", "Bar Cooldown Color", "barCooldownColor", {0.6, 0.6, 0.6, 1.0})
    AddBarColorRow(colorRight, "barChargeColor", "Bar Recharging Color", "barChargeColor", {1.0, 0.82, 0.0, 1.0})

    -- The color the aura timer drains in. Same gate as the aura block down in
    -- Text & Icon, so it appears only while the group tracks an aura.
    --
    -- barAuraColor belongs to the barActiveAura section, whose home is the
    -- Effects tab's Active Aura Indicator row - so this row FOLLOWS that
    -- section's scope and carries no chrome of its own, the way the pandemic
    -- marker row follows the pandemic enable row. One section, one affordance.
    if GroupHasAuraTrackingEntry(group) then
        local _, auraColorRead, auraColorWrite = ResolveLensSection(lens, group, "barActiveAura")
        AddColorRow(colorRight, {
            label = "Bar Aura Timer Color",
            tbl = auraColorWrite or auraColorRead, key = "barAuraColor",
            default = {0.2, 1.0, 0.2, 1.0}, hasAlpha = true,
            disabled = auraColorWrite == nil,
            onConfirm = refreshStyle, onChange = refreshStyle,
        })
    end

    -- ================================================================
    -- Border (thickness, size, color - mirrors the icon-mode Border section)
    -- ================================================================
    local borderHeading, borderCollapsed = BuildCollapsibleSection(container, "Border", "barappearance_border", nil, nil, ROW_SECTION)
    local borderScope, borderRead, borderWrite = ResolveLensSection(lens, group, "borderSettings")
    AttachHeadingScopeChrome(borderHeading, lens, group, "borderSettings")

    if not borderCollapsed then
    -- Three related rows, so they stay in one column rather than splitting a
    -- parent from its children. The right column is deliberately empty.
    local borderLeft = BeginRowGrid(container)
    local borderInertMark = (borderWrite == nil) and MarkInertRange(borderLeft) or nil

    -- The shared builder reads and writes ONE table, so it is handed the
    -- section's WRITE table with the panel style behind it in opts - the
    -- styleTable + fallbackStyle pair a customized section passes - or, inert,
    -- the read-only snapshot. The lens draws one shape for both scopes.
    BuildBorderControls(borderLeft, borderWrite or borderRead, refreshStyle, {
        row = true,
        fallbackStyle = (borderScope == "customized") and style or nil,
    })

    if borderInertMark then
        ApplyInertRange(borderLeft, borderInertMark)
    end
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
    -- (ButtonFrame/Tracking.lua serves both display modes), so the rows
    -- mirror the icons tab's section - minus Background Color, which the bar
    -- icon does not render (its backdrop is Bar Background Color above).
    -- ================================================================
    local _, iconVisRead = ResolveLensSection(lens, group, "barIcon")
    if iconVisRead.showBarIcon ~= false then
    local iconTintHeading, iconTintCollapsed = BuildCollapsibleSection(container, "Icon Tint", "barappearance_iconTint", nil, nil, ROW_SECTION)
    local _, tintRead, tintWrite = ResolveLensSection(lens, group, "iconTint")

    -- The (?) badge chains off the heading label, and the lens' scope chrome
    -- lands after it: label -> (?) -> scope.
    ST._ChainHeadingBadges(iconTintHeading, CreateInfoButton(iconTintHeading.frame,
        iconTintHeading.label, "LEFT", "RIGHT", 4, 0, {
            "Icon Tint",
            {"Colors the bar's icon.", 1, 1, 1, true},
            " ",
            {"The cooldown, unusable and aura tints take over while their state is active.", 1, 1, 1, true},
        }, tabInfoButtons))
    AttachHeadingScopeChrome(iconTintHeading, lens, group, "iconTint")

    if not iconTintCollapsed then
        -- LEFT column: the always-on tint plus the cooldown pair. RIGHT
        -- column: the conditional state tints. Both columns bracket
        -- separately: an inert range is a contiguous slice of ONE column's
        -- children, and this section fills two.
        local tintLeft, tintRight = BeginRowGrid(container)

        local tintLeftInertMark = (tintWrite == nil) and MarkInertRange(tintLeft) or nil
        -- A color row binds its picker to one table for both reading and
        -- writing, so it gets the write table where the section has one and
        -- the lens' detached snapshot where it does not.
        local tintTbl = tintWrite or tintRead

        AddColorRow(tintLeft, {
            label = "Base Icon Color",
            tbl = tintTbl, key = "iconTintColor",
            default = {1, 1, 1, 1}, hasAlpha = true,
            disabled = tintWrite == nil,
            onConfirm = refreshStyle, onChange = refreshStyle,
        })

        AddCheckboxRow(tintLeft, {
            label = "Use Separate Cooldown Tint",
            value = tintRead.iconCooldownTintEnabled or false,
            disabled = tintWrite == nil,
            onChange = function(val)
                if not tintWrite then return end
                tintWrite.iconCooldownTintEnabled = val
                refreshStyle()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if tintRead.iconCooldownTintEnabled then
            AddColorRow(tintLeft, {
                label = "Cooldown Icon Color",
                indent = true,
                tbl = tintTbl, key = "iconCooldownTintColor",
                default = {1, 0, 0.102, 1}, hasAlpha = true,
                disabled = tintWrite == nil,
                onConfirm = refreshStyle, onChange = refreshStyle,
            })
        end

        if tintLeftInertMark then
            ApplyInertRange(tintLeft, tintLeftInertMark)
        end

        -- Unusable Dim Color is an Unusable Visual key (ST.OVERRIDE_SECTIONS
        -- lists iconUnusableTintColor under unusableDimming), shown here only
        -- because it reads as one of the icon's tints. So it resolves and
        -- follows THAT section's scope silently - writing it through Icon
        -- Tint's store would leave a key Icon Tint's revert cannot clear. Its
        -- chrome lives on the Effects tab's Unusable Visual row; the
        -- lens-resolved read decides whether the dim mode has it on show.
        local _, dimRead, dimWrite = ResolveLensSection(lens, group, "unusableDimming")
        if dimRead.showUnusable and ST.UnusableVisualUsesDimTint(dimRead) then
            AddColorRow(tintRight, {
                label = "Unusable Dim Color",
                tbl = dimWrite or dimRead, key = "iconUnusableTintColor",
                default = {0.4, 0.4, 0.4, 1}, hasAlpha = true,
                disabled = dimWrite == nil,
                onConfirm = refreshStyle, onChange = refreshStyle,
            })
        end

        -- Taken AFTER the dim row so the Icon Tint bracket never reaches a
        -- row another section owns; everything below is this section's own.
        local tintRightInertMark = (tintWrite == nil) and MarkInertRange(tintRight) or nil

        -- Aura tint applies to the slot-kit aura layer (consumed at bind time
        -- by AuraDisplay.StyleSlotKit); only offered where an aura display
        -- exists. Same group-level gate the aura block below follows.
        if GroupHasAuraTrackingEntry(group) then
            AddCheckboxRow(tintRight, {
                label = "Use Separate Aura Tint",
                value = tintRead.iconAuraTintEnabled or false,
                disabled = tintWrite == nil,
                onChange = function(val)
                    if not tintWrite then return end
                    tintWrite.iconAuraTintEnabled = val
                    refreshStyle()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })

            if tintRead.iconAuraTintEnabled then
                AddColorRow(tintRight, {
                    label = "Aura Active Icon Color",
                    indent = true,
                    tbl = tintTbl, key = "iconAuraTintColor",
                    default = {0, 0.925, 1, 1}, hasAlpha = true,
                    disabled = tintWrite == nil,
                    onConfirm = refreshStyle, onChange = refreshStyle,
                })
            end
        end

        -- Compact reset, matching the icons tab's twin. AutoWidth: the
        -- column's List layout neither stretches nor right-anchors it and it
        -- sits flush left under the last row.
        --
        -- Not built at all while the section is inert: a section with nowhere
        -- to write has no defaults to restore. backgroundColor has no ROW here
        -- (the bar icon never renders it) but the reset still writes it: the
        -- key belongs to this section, and a value left pinned would surface
        -- as a stale icon backdrop if the panel ever converts to icons.
        if tintWrite then
            local resetTintBtn = AceGUI:Create("Button")
            resetTintBtn:SetText("Reset Colors to Default")
            resetTintBtn:SetAutoWidth(true)
            resetTintBtn:SetCallback("OnClick", function()
                tintWrite.iconTintColor = {1, 1, 1, 1}
                tintWrite.iconCooldownTintColor = {1, 0, 0.102, 1}
                tintWrite.iconAuraTintColor = {0, 0.925, 1, 1}
                tintWrite.backgroundColor = {0, 0, 0, 0.5}
                -- The dim color is Unusable Visual's key, so it resets through
                -- that section's own write table - and only while it has one,
                -- never into a store that section does not own.
                if dimWrite then
                    dimWrite.iconUnusableTintColor = {0.4, 0.4, 0.4, 1}
                end
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end)
            tintRight:AddChild(resetTintBtn)
        end

        if tintRightInertMark then
            ApplyInertRange(tintRight, tintRightInertMark)
        end
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

    -- ================================================================
    -- Show Icon
    -- ================================================================
    local iconScope, iconRead, iconWrite = ResolveLensSection(lens, group, "barIcon")
    local iconInertMark = (iconWrite == nil) and MarkInertRange(textLeft) or nil

    local showIconRow = AddCheckboxRow(textLeft, {
        label = "Show Icon",
        value = iconRead.showBarIcon ~= false,
        disabled = iconWrite == nil,
        onChange = function(val)
            if not iconWrite then return end
            iconWrite.showBarIcon = val
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
            value = iconRead.barIconReverse or false,
            onChange = function(val)
                -- An override store needs the explicit false: nil DELETES the
                -- key and the entry falls back to the panel value, so a
                -- customized entry could never turn this OFF against a panel
                -- that has it on. Panel scope keeps nil-for-false (the lean
                -- saved default).
                iconWrite.barIconReverse = val and true
                    or (iconScope == "customized" and false or nil)
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        AddSliderRow(panel, {
            label = "Icon Offset",
            min = -5, max = 50, step = 0.1,
            value = iconRead.barIconOffset or 0,
            onChange = function(val)
                ST._PreviewScalarSetting(iconWrite, "barIconOffset", val, ST._RefreshSelectedButtonsPreview)
            end,
            onRelease = function(val)
                iconWrite.barIconOffset = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })

        AddCheckboxRow(panel, {
            label = "Custom Icon Size",
            value = iconRead.barIconSizeOverride or false,
            onChange = function(val)
                iconWrite.barIconSizeOverride = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if iconRead.barIconSizeOverride then
            AddSliderRow(panel, {
                label = "Icon Size",
                indent = true,
                min = 5, max = 100, step = 0.1,
                value = iconRead.barIconSize or 20,
                onChange = function(val)
                    ST._PreviewScalarSetting(iconWrite, "barIconSize", val, ST._RefreshSelectedButtonsPreview)
                end,
                onRelease = function(val)
                    iconWrite.barIconSize = val
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
        local _, zoomRead, zoomWrite = ResolveLensSection(lens, group, "iconZoom")
        local zoomInertMark = (zoomWrite == nil) and MarkInertRange(panel) or nil
        local zoomRow = ST._BuildIconZoomControls(panel, zoomWrite or zoomRead, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, {
            disabled = zoomWrite == nil,
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
        AttachRowScopeChrome(zoomRow, lens, group, "iconZoom")
        if zoomInertMark then
            ApplyInertRange(panel, zoomInertMark)
        end
    end

    if iconWrite then
        AddAdvancedToggle(showIconRow, "barIcon", tabInfoButtons, iconRead.showBarIcon ~= false, {
            title = "Bar Icon Advanced",
            build = BuildBarIconAdvanced,
        })
    end
    AttachRowScopeChrome(showIconRow, lens, group, "barIcon")

    if iconInertMark then
        ApplyInertRange(textLeft, iconInertMark)
    end

    -- Show Name Text toggle
    local nameScope, nameRead, nameWrite = ResolveLensSection(lens, group, "barNameText")
    local nameInertMark = (nameWrite == nil) and MarkInertRange(textLeft) or nil

    local showNameRow = AddCheckboxRow(textLeft, {
        label = "Show Name Text",
        value = nameRead.showBarNameText ~= false,
        disabled = nameWrite == nil,
        onChange = function(val)
            if not nameWrite then return end
            nameWrite.showBarNameText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
    --
    -- The two name-text offsets are NOT barNameText keys (ST.OVERRIDE_SECTIONS
    -- in Defaults.lua): they place the name on every bar the panel draws. They
    -- are drawn only while this panel edits the panel style, for the reason
    -- stated on the cooldown text descriptor at the top of this file - an
    -- override would store a key RevertSection cannot clear.
    local function BuildBarNameTextAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Flip Name Text",
            value = nameRead.barNameTextReverse or false,
            onChange = function(val)
                -- Explicit false for an override store; see Flip Icon Side.
                nameWrite.barNameTextReverse = val and true
                    or (nameScope == "customized" and false or nil)
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })

        AddFontControls(panel, nameWrite, "barName", {sizeMin = 6, sizeMax = 24, size = 10}, refreshStyle, { row = true })
        -- deferCommit is deliberately absent, matching the stock color-picker call
        -- this row replaced.
        AddColorRow(panel, {
            label = "Font Color",
            tbl = nameWrite,
            key = "barNameFontColor",
            default = {1, 1, 1, 1},
            hasAlpha = true,
            onConfirm = refreshStyle,
            onChange = refreshStyle,
        })
        if nameScope ~= "customized" then
            AddOffsetSliders(panel, nameWrite, "barNameTextOffsetX", "barNameTextOffsetY", {range = 50}, refreshStyle, { row = true })
        end
    end

    if nameWrite then
        AddAdvancedToggle(showNameRow, "barNameText", tabInfoButtons, nameRead.showBarNameText ~= false, {
            title = "Name Text Advanced",
            build = BuildBarNameTextAdvanced,
        })
    end
    AttachRowScopeChrome(showNameRow, lens, group, "barNameText")

    if nameInertMark then
        ApplyInertRange(textLeft, nameInertMark)
    end

    -- Show Cooldown Text toggle
    local cdTextScope, cdTextRead, cdTextWrite = ResolveLensSection(lens, group, "cooldownText")
    local cdTextInertMark = (cdTextWrite == nil) and MarkInertRange(textLeft) or nil

    local showTimeRow = AddCheckboxRow(textLeft, {
        label = "Show Cooldown Text",
        value = cdTextRead.showCooldownText or false,
        disabled = cdTextWrite == nil,
        onChange = function(val)
            if not cdTextWrite then return end
            cdTextWrite.showCooldownText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if cdTextWrite then
        -- Panel scope hands the descriptor NO table, so it keeps resolving the
        -- live group style itself (see the factory's note). An entry's override
        -- store has no such resolver, so that one is handed over explicitly.
        local barCdTextAdvanced = MakeBarCooldownTextAdvancedDescriptor(
            cdTextScope == "customized" and cdTextWrite or nil)

        AddAdvancedToggle(showTimeRow, barCdTextAdvanced.settingKey, tabInfoButtons, cdTextRead.showCooldownText, {
            title = barCdTextAdvanced.title,
            build = barCdTextAdvanced.build,
        })
    end
    AttachRowScopeChrome(showTimeRow, lens, group, "cooldownText")

    -- Duration Format sits with the cooldown text it formats. It is not gated
    -- on that toggle in bar mode (ready text reads it too), so it is a row of
    -- its own rather than an indented child - but it still follows the Cooldown
    -- Text section's scope, and is never shown once an entry OWNS that section:
    -- the format is not one of the section's keys, so an override would store a
    -- key revert could not clear. The icons tab draws it the same way
    -- (GroupTabs.lua).
    --
    -- The shared helper takes no `disabled`, so the inert bracket below is what
    -- makes this row read-only along with the rest of the section.
    if cdTextScope ~= "customized" then
        AddDurationFormatDropdown(textLeft, cdTextWrite or cdTextRead, refreshStyle, { row = true })
    end

    if cdTextInertMark then
        ApplyInertRange(textLeft, cdTextInertMark)
    end

    -- Show Charge Text toggle
    local _, chargeRead, chargeWrite = ResolveLensSection(lens, group, "chargeText")
    local chargeInertMark = (chargeWrite == nil) and MarkInertRange(textLeft) or nil

    local chargeTextRow = AddCheckboxRow(textLeft, {
        label = "Show Count Text (Charges/Uses)",
        value = chargeRead.showChargeText ~= false,
        disabled = chargeWrite == nil,
        onChange = function(val)
            if not chargeWrite then return end
            chargeWrite.showChargeText = val
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
        AddFontControls(panel, chargeWrite, "charge", {}, refreshStyle, { row = true })

        local function ChargeColorRow(rowLabel, key)
            AddColorRow(panel, {
                label = rowLabel,
                tooltip = { rowLabel },
                tbl = chargeWrite,
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

        AddAnchorDropdown(panel, chargeWrite, "chargeAnchor", "BOTTOMRIGHT", refreshStyle, nil, { row = true })
        AddOffsetSliders(panel, chargeWrite, "chargeXOffset", "chargeYOffset", {x = -2, y = 2}, refreshStyle, { row = true })
    end

    if chargeWrite then
        AddAdvancedToggle(chargeTextRow, "barChargeText", tabInfoButtons, chargeRead.showChargeText ~= false, {
            title = "Count Text Advanced",
            build = BuildBarChargeTextAdvanced,
        })
    end
    AttachRowScopeChrome(chargeTextRow, lens, group, "chargeText")

    if chargeInertMark then
        ApplyInertRange(textLeft, chargeInertMark)
    end

    -- Show Ready Text toggle
    local _, readyRead, readyWrite = ResolveLensSection(lens, group, "barReadyText")
    local readyInertMark = (readyWrite == nil) and MarkInertRange(textLeft) or nil

    local showReadyRow = AddCheckboxRow(textLeft, {
        label = "Show Ready Text",
        value = readyRead.showBarReadyText or false,
        disabled = readyWrite == nil,
        onChange = function(val)
            if not readyWrite then return end
            readyWrite.showBarReadyText = val
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
            value = readyRead.barReadyText or "Ready",
            onEnterPressed = function(val)
                readyWrite.barReadyText = val
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
            tbl = readyWrite,
            key = "barReadyTextColor",
            default = {0.2, 1.0, 0.2, 1.0},
            hasAlpha = true,
            onConfirm = refreshStyle,
            onChange = refreshStyle,
        })
        AddFontControls(panel, readyWrite, "barReady", {sizeMin = 6, sizeMax = 24}, refreshStyle, { row = true })
    end

    if readyWrite then
        AddAdvancedToggle(showReadyRow, "barReadyText", tabInfoButtons, readyRead.showBarReadyText, {
            title = "Ready Text Advanced",
            build = BuildBarReadyTextAdvanced,
        })
    end
    AttachRowScopeChrome(showReadyRow, lens, group, "barReadyText")

    if readyInertMark then
        ApplyInertRange(textLeft, readyInertMark)
    end

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
        local _, auraTextRead, auraTextWrite = ResolveLensSection(lens, group, "auraText")
        local auraTextInertMark = (auraTextWrite == nil) and MarkInertRange(textRight) or nil

        local auraTextRow = AddCheckboxRow(textRight, {
            label = "Show Aura Duration Text",
            value = auraTextRead.showAuraText ~= false,
            disabled = auraTextWrite == nil,
            onChange = function(val)
                if not auraTextWrite then return end
                auraTextWrite.showAuraText = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
        -- deferCommit is deliberately absent, matching the stock color-picker call
        -- the color row replaced.
        local function BuildBarAuraTextAdvanced(panel)
            AddFontControls(panel, auraTextWrite, "auraText", { size = 12 }, refreshStyle, { row = true })
            AddColorRow(panel, {
                label = "Font Color",
                tbl = auraTextWrite,
                key = "auraTextFontColor",
                default = {0, 0.925, 1, 1},
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })
        end

        if auraTextWrite then
            AddAdvancedToggle(auraTextRow, "barAuraText", tabInfoButtons, auraTextRead.showAuraText ~= false, {
                title = "Aura Duration Text Advanced",
                build = BuildBarAuraTextAdvanced,
            })
        end
        -- Second badge in the chain: gear, then this, then the scope chrome the
        -- lens attaches last. The anchor args below are a placeholder -
        -- AnchorRowBadge re-points the button onto the end of the chain.
        AnchorRowBadge(auraTextRow, CreateInfoButton(auraTextRow.frame, auraTextRow.frame, "LEFT", "LEFT", 0, 0, {
            "Aura Duration Text",
            {"Shows the remaining aura time at the bar's time text position while the aura is active. Position follows the flip and offset settings in the Cooldown Text section.", 1, 1, 1, true},
        }, auraTextRow))
        AttachRowScopeChrome(auraTextRow, lens, group, "auraText")

        if auraTextInertMark then
            ApplyInertRange(textRight, auraTextInertMark)
        end

        -- Aura stack text: Blizzard writes the live stack count; anchored to
        -- the icon square (or the bar with the icon hidden).
        local _, auraStackRead, auraStackWrite = ResolveLensSection(lens, group, "auraStackText")
        local auraStackInertMark = (auraStackWrite == nil) and MarkInertRange(textRight) or nil

        local auraStackRow = AddCheckboxRow(textRight, {
            label = "Show Aura Stack Text",
            value = auraStackRead.showAuraStackText ~= false,
            disabled = auraStackWrite == nil,
            onChange = function(val)
                if not auraStackWrite then return end
                auraStackWrite.showAuraStackText = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
        local function BuildBarAuraStackTextAdvanced(panel)
            AddFontControls(panel, auraStackWrite, "auraStack", { size = 12 }, refreshStyle, { row = true })
            -- deferCommit is deliberately absent, matching the stock color-picker
            -- call this row replaced.
            AddColorRow(panel, {
                label = "Font Color",
                tbl = auraStackWrite,
                key = "auraStackFontColor",
                default = {1, 1, 1, 1},
                hasAlpha = true,
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })
            AddAnchorDropdown(panel, auraStackWrite, "auraStackAnchor", "BOTTOMLEFT", refreshStyle, nil, { row = true })
            AddOffsetSliders(panel, auraStackWrite, "auraStackXOffset", "auraStackYOffset", { x = 2, y = 2 }, refreshStyle, { row = true })
        end

        if auraStackWrite then
            AddAdvancedToggle(auraStackRow, "barAuraStackText", tabInfoButtons, auraStackRead.showAuraStackText ~= false, {
                title = "Aura Stack Text Advanced",
                build = BuildBarAuraStackTextAdvanced,
            })
        end
        AnchorRowBadge(auraStackRow, CreateInfoButton(auraStackRow.frame, auraStackRow.frame, "LEFT", "LEFT", 0, 0, {
            "Aura Stack Text",
            {"Shows the live stack count while the aura is active, drawn by the game so it stays accurate in combat. Stack counts cannot drive the bar fill; the count is hidden from addons during combat.", 1, 1, 1, true},
        }, auraStackRow))
        AttachRowScopeChrome(auraStackRow, lens, group, "auraStackText")

        if auraStackInertMark then
            ApplyInertRange(textRight, auraStackInertMark)
        end
    end

    -- Compact Mode toggle + advanced (growth direction, max visible buttons).
    -- Panel-level packing with no override section, so under an entry lens it
    -- goes read-only along with the rest of the panel-only content rather than
    -- letting a panel-wide edit be made from an entry's page. Its gear is not
    -- skipped the way the lens sections' are: compact mode is group data with
    -- no second table to bind a gear to, so the inert walk disables and dims it
    -- instead (the icons tab does exactly this).
    local compactInertMark = panelOnlyInert and MarkInertRange(textRight) or nil
    BuildCompactModeControls(textRight, group, tabInfoButtons)
    if compactInertMark then
        ApplyInertRange(textRight, compactInertMark)
    end
    end -- not textIconCollapsed

    BuildGroupSettingPresetControls(container, group, "bars", tabInfoButtons)

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
    local auraScope, auraRead, auraWrite = ResolveLensSection(lens, group, "barActiveAura")

    local hasBorderEffect = auraRead.barAuraEffect ~= nil
        and auraRead.barAuraEffect ~= "color" and auraRead.barAuraEffect ~= "none"
    local anyEffect = hasBorderEffect
        or auraRead.barAuraPulseEnabled == true
        or auraRead.barAuraColorShiftEnabled == true
    local indicatorOn = ST.IsBarAuraIndicatorEnabled(auraRead) and anyEffect

    if container then
        local inertMark = (auraWrite == nil) and MarkInertRange(container) or nil

        local enableRow = AddCheckboxRow(container, {
            label = "Show Active Aura Indicator",
            value = indicatorOn,
            disabled = auraWrite == nil,
            onChange = function(val)
                if not auraWrite then return end
                auraWrite.barAuraIndicatorEnabled = val
                if val and not (auraWrite.barAuraEffect and auraWrite.barAuraEffect ~= "color" and auraWrite.barAuraEffect ~= "none"
                    or auraWrite.barAuraPulseEnabled == true or auraWrite.barAuraColorShiftEnabled == true) then
                    -- Nothing visible was configured; force the pulse border and
                    -- reset its per-style keys (a leftover proc-scale size would
                    -- render a 30px wall).
                    auraWrite.barAuraEffect = "pulse"
                    auraWrite.barAuraEffectSize = 2
                    auraWrite.barAuraEffectSpeed = 0.5
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
            BuildBarActiveAuraControls(panel, auraWrite, function()
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end, {
                row = true,
                singleRail = true,
                infoButtons = tabInfoButtons,
                fallbackStyle = (auraScope == "customized") and style or nil,
            })
        end

        if auraWrite then
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
        AttachRowScopeChrome(enableRow, lens, group, "barActiveAura")

        if inertMark then
            ApplyInertRange(container, inertMark)
        end
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

    local _, pandemicRead, pandemicWrite = ResolveLensSection(lens, group, "pandemic")
    local pandemicOn = pandemicRead.pandemicEffectEnabled == true
    if container then
        local inertMark = (pandemicWrite == nil) and MarkInertRange(container) or nil

        local enableRow = AddCheckboxRow(container, {
            label = "Show Pandemic Color",
            value = pandemicOn,
            disabled = pandemicWrite == nil,
            onChange = function(val)
                if not pandemicWrite then return end
                pandemicWrite.pandemicEffectEnabled = val and true or false
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
        AttachRowScopeChrome(enableRow, lens, group, "pandemic")

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
                tbl = pandemicWrite or pandemicRead,
                key = "barPandemicColor",
                default = {1, 0.5, 0, 1},
                hasAlpha = false,
                disabled = pandemicWrite == nil,
                onConfirm = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end,
                onChange = ST._RefreshSelectedButtonsPreview,
            })
        end

        if inertMark then
            ApplyInertRange(container, inertMark)
        end
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
    if not container or not GroupHasAuraTrackingEntry(group) then
        return
    end

    -- Same override section as the fill rows in the left column, so this half
    -- FOLLOWS that section's scope silently: one feature, one affordance, and
    -- the chrome for it is on the enable row beside this one.
    local _, markerRead, markerWrite = ResolveLensSection(lens, group, "pandemic")
    local inertMark = (markerWrite == nil) and MarkInertRange(container) or nil

    local applyStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    local markerRow = AddPandemicMarkerControls(container, markerWrite or markerRead, applyStyle, function()
        CooldownCompanion:RefreshConfigPanel()
    end, { enableOnly = true })

    -- Single rail (AdvancedSettingsPanel.lua): the styling rows fill the panel,
    -- so childrenOnly drops the indent they carry when inline. The panel
    -- captures the section's WRITE table, and is only built while there is one.
    local function BuildBarPandemicMarkerAdvanced(panel)
        AddPandemicMarkerControls(panel, markerWrite, applyStyle, function()
            if CS.RefreshAdvancedSettingsPanel then
                CS.RefreshAdvancedSettingsPanel()
            end
        end, { childrenOnly = true })
    end

    -- "barPandemicMarker", not the icons key: every bars gear in this file
    -- carries its own prefixed key (barAuraText, barNameText, barChargeText),
    -- so a panel switch can never rebind an open panel onto the other mode's
    -- builder. The gear-to-section maps name both.
    if markerWrite then
        AddAdvancedToggle(markerRow, "barPandemicMarker", tabInfoButtons,
            markerRead.pandemicMarkerEnabled ~= false, {
                title = "Pandemic Marker Advanced",
                build = BuildBarPandemicMarkerAdvanced,
            })
    end

    if inertMark then
        ApplyInertRange(container, inertMark)
    end
end

local function BuildBarEffectsTab(container, group, style)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end

    -- STYLE LENS (Helpers.lua), resolved ONCE for the whole tab and handed to
    -- every section below - see the note at the top of BuildBarAppearanceTab
    -- for what the scopes mean and why the write table is the only gate.
    local lens = ResolveStyleLens(group)
    -- Panel-only content on this tab (Allow Pings): read-only under an entry
    -- lens, same rule as the appearance tab's layout section.
    local panelOnlyInert = lens.mode == "entry"

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
        local _, pandemicCollapsed = BuildCollapsibleSection(container, "Pandemic",
            EFFECTS_PANDEMIC_SECTION, nil, nil, ROW_SECTION)
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
    local _, effIconRead = ResolveLensSection(lens, group, "barIcon")
    if effIconRead.showBarIcon ~= false then
        -- ================================================================
        -- Timers
        -- ================================================================
        local _, timersCollapsed = BuildCollapsibleSection(container, "Timers", EFFECTS_TIMERS_SECTION, nil, nil, ROW_SECTION)

        if not timersCollapsed then
        -- One row; the right column is deliberately empty.
        local timerLeft = BeginRowGrid(container)

        -- One row, no gear: `disabled` is the whole gate, so no inert bracket
        -- is needed - the chrome that undoes it is attached after.
        local _, gcdRead, gcdWrite = ResolveLensSection(lens, group, "showGCDSwipe")
        local gcdRow = AddCheckboxRow(timerLeft, {
            label = "Show GCD Swipe",
            value = gcdRead.showGCDSwipe == true,
            disabled = gcdWrite == nil,
            onChange = function(val)
                if not gcdWrite then return end
                gcdWrite.showGCDSwipe = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
        AttachRowScopeChrome(gcdRow, lens, group, "showGCDSwipe")
        end -- not timersCollapsed

        -- ================================================================
        -- States
        -- ================================================================
        local _, statesCollapsed = BuildCollapsibleSection(container, "States", EFFECTS_STATES_SECTION, nil, nil, ROW_SECTION)

        if not statesCollapsed then
        -- LEFT column: the two looks the bar's icon takes on by itself.
        -- RIGHT column: the situational state and the hover behavior.
        local stateLeft, stateRight = BeginRowGrid(container)

        local _, desatRead, desatWrite = ResolveLensSection(lens, group, "desaturation")
        local desatRow = AddCheckboxRow(stateLeft, {
            label = "Show Desaturate On Cooldown",
            value = desatRead.desaturateOnCooldown or false,
            disabled = desatWrite == nil,
            onChange = function(val)
                if not desatWrite then return end
                desatWrite.desaturateOnCooldown = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
        AttachRowScopeChrome(desatRow, lens, group, "desaturation")

        -- The two shared builders below own their gears, so an inert scope
        -- cannot skip building one the way the hand-written sections do: the
        -- inert pass gates the gear it finds on the row (_cdcAdvancedBtn), and
        -- the sweep at the foot of this builder closes a panel it rebound.
        local unusableScope, unusableRead, unusableWrite = ResolveLensSection(lens, group, "unusableDimming")
        local unusableInertMark = (unusableWrite == nil) and MarkInertRange(stateLeft) or nil
        local unusableRow = BuildUnusableDimmingControls(stateLeft, unusableWrite or unusableRead, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, {
            row = true,
            fallbackStyle = (unusableScope == "customized") and style or nil,
        })
        AttachRowScopeChrome(unusableRow, lens, group, "unusableDimming")
        if unusableInertMark then
            ApplyInertRange(stateLeft, unusableInertMark)
        end

        local _, locRead, locWrite = ResolveLensSection(lens, group, "lossOfControl")
        local locRow = BuildLossOfControlControls(stateRight, locWrite or locRead, refreshStyle, {
            row = true,
        })
        locRow:SetDisabled(locWrite == nil)
        AttachRowScopeChrome(locRow, lens, group, "lossOfControl")

        local tooltipScope, tooltipRead, tooltipWrite = ResolveLensSection(lens, group, "showTooltips")
        local tooltipInertMark = (tooltipWrite == nil) and MarkInertRange(stateRight) or nil
        local tooltipRow = BuildShowTooltipsControls(stateRight, tooltipWrite or tooltipRead, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, {
            row = true,
            advanced = true,
            infoButtons = tabInfoButtons,
            fallbackStyle = (tooltipScope == "customized") and style or nil,
        })
        AttachRowScopeChrome(tooltipRow, lens, group, "showTooltips")
        if tooltipInertMark then
            ApplyInertRange(stateRight, tooltipInertMark)
        end

        -- Allow Pings is a PANEL setting with no override section of its own
        -- (ST.OVERRIDE_SECTIONS), so under an entry lens it goes read-only with
        -- the rest of the panel-only content instead of letting a panel-wide
        -- edit be made from an entry's page. Its "?" badge stays readable: the
        -- inert walk only reaches AceGUI children and the gear.
        local pingsInertMark = panelOnlyInert and MarkInertRange(stateRight) or nil
        BuildAllowPingsControls(stateRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        if pingsInertMark then
            ApplyInertRange(stateRight, pingsInertMark)
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

-- Expose for GroupTabs.lua dispatchers
ST._BuildBarAppearanceTab = BuildBarAppearanceTab
ST._BuildBarEffectsTab = BuildBarEffectsTab
