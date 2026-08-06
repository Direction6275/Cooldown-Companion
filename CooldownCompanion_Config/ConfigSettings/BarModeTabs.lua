--[[
    CooldownCompanion - ConfigSettings/BarModeTabs.lua: Bar-mode appearance and effects tab builders
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreatePromoteButton = ST._CreatePromoteButton
local CreateCheckboxPromoteButton = ST._CreateCheckboxPromoteButton
local CreateColorPickerPromoteButton = ST._CreateColorPickerPromoteButton
local CreateInfoButton = ST._CreateInfoButton
local BuildCompactModeControls = ST._BuildCompactModeControls
local BuildGroupSettingPresetControls = ST._BuildGroupSettingPresetControls
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders
local GroupHasAuraTrackingEntry = ST._GroupHasAuraTrackingEntry
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls

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
local function ResolveSelectedGroupStyle()
    local groupId = CS.selectedGroup
    local profile = groupId and CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    return group and group.style or nil
end

local function MakeBarCooldownTextAdvancedDescriptor()
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    return {
        settingKey = "barCooldownText",
        title = "Cooldown Text Advanced",
        build = function(panel)
            local style = ResolveSelectedGroupStyle()
            if not style then
                return
            end

            -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow
            -- column, so every row goes straight onto the panel scroll and each
            -- shared builder runs with { row = true } and no rightColumn.
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

            AddFontControls(panel, style, "cooldown", {sizeMin = 6, sizeMax = 24}, refreshStyle, { row = true })
            -- deferCommit is deliberately absent, matching the AddColorPicker
            -- call this row replaced.
            AddColorRow(panel, {
                label = "Font Color",
                tbl = style,
                key = "cooldownFontColor",
                default = {1, 1, 1, 1},
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })
            AddOffsetSliders(panel, style, "barCdTextOffsetX", "barCdTextOffsetY", {range = 50}, refreshStyle, { row = true })
        end,
    }
end
ST._MakeBarCooldownTextAdvancedDescriptor = MakeBarCooldownTextAdvancedDescriptor

local function BuildBarAppearanceTab(container, group, style)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end

    -- ================================================================
    -- Bar Settings (length, height, spacing, texture)
    -- ================================================================
    local _, barSettingsCollapsed = BuildCollapsibleSection(container, "Bar Settings", "barappearance_settings", nil, nil, ROW_SECTION)

    if not barSettingsCollapsed then
    -- LEFT column: how one bar is shaped. RIGHT column: how the bars sit
    -- together and what they are drawn with.
    local barLeft, barRight = BeginRowGrid(container)

    AddSliderRow(barLeft, {
        label = "Bar Length",
        min = 10, max = 500, step = 0.1,
        value = style.barLength or 180,
        onChange = function(val)
            style.barLength = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })

    AddSliderRow(barLeft, {
        label = "Bar Height",
        min = 5, max = 100, step = 0.1,
        value = style.barHeight or 20,
        onChange = function(val)
            style.barHeight = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })

    if group.buttons and #group.buttons > 1 then
        AddSliderRow(barRight, {
            label = "Bar Spacing",
            min = -10, max = 100, step = 0.1,
            value = style.buttonSpacing or ST.BUTTON_SPACING,
            onChange = function(val)
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
    end -- not barSettingsCollapsed

    -- Bar colors have no heading and no collapse state, so they stay on screen
    -- while Bar Settings is folded away. They get a grid of their own, which is
    -- also what keeps them off the section's last line.
    -- LEFT column: the bar at rest - its fill and the backdrop behind it.
    -- RIGHT column: the two colors a timer paints over that.
    local colorLeft, colorRight = BeginRowGrid(container)

    local barColorRow = AddColorRow(colorLeft, {
        label = "Bar Color",
        tbl = style, key = "barColor",
        default = {0.2, 0.6, 1.0, 1.0}, hasAlpha = true,
        onConfirm = refreshStyle, onChange = refreshStyle,
    })
    CreateColorPickerPromoteButton(barColorRow, "barColor", group, style)

    local barBgColorRow = AddColorRow(colorLeft, {
        label = "Bar Background Color",
        tbl = style, key = "barBgColor",
        default = {0.1, 0.1, 0.1, 0.8}, hasAlpha = true,
        onConfirm = refreshStyle, onChange = refreshStyle,
    })
    CreateColorPickerPromoteButton(barBgColorRow, "barBgColor", group, style)

    local barCooldownColorRow = AddColorRow(colorRight, {
        label = "Bar Cooldown Color",
        tbl = style, key = "barCooldownColor",
        default = {0.6, 0.6, 0.6, 1.0}, hasAlpha = true,
        onConfirm = refreshStyle, onChange = refreshStyle,
    })
    CreateColorPickerPromoteButton(barCooldownColorRow, "barCooldownColor", group, style)

    local barChargeColorRow = AddColorRow(colorRight, {
        label = "Bar Recharging Color",
        tbl = style, key = "barChargeColor",
        default = {1.0, 0.82, 0.0, 1.0}, hasAlpha = true,
        onConfirm = refreshStyle, onChange = refreshStyle,
    })
    CreateColorPickerPromoteButton(barChargeColorRow, "barChargeColor", group, style)

    -- ================================================================
    -- Border (thickness, size, color - mirrors the icon-mode Border section)
    -- ================================================================
    local borderHeading, borderCollapsed = BuildCollapsibleSection(container, "Border", "barappearance_border", nil, nil, ROW_SECTION)
    CreatePromoteButton(borderHeading, "borderSettings", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not borderCollapsed then
    -- Three related rows, so they stay in one column rather than splitting a
    -- parent from its children. The right column is deliberately empty.
    local borderLeft = BeginRowGrid(container)

    BuildBorderControls(borderLeft, style, refreshStyle, { row = true })
    end -- not borderCollapsed

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
    local showIconRow = AddCheckboxRow(textLeft, {
        label = "Show Icon",
        value = style.showBarIcon ~= false,
        onChange = function(val)
            style.showBarIcon = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- the rows go straight onto the panel scroll and Icon Size indents under the
    -- toggle that gates it.
    local function BuildBarIconAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Flip Icon Side",
            value = style.barIconReverse or false,
            onChange = function(val)
                style.barIconReverse = val or nil
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        AddSliderRow(panel, {
            label = "Icon Offset",
            min = -5, max = 50, step = 0.1,
            value = style.barIconOffset or 0,
            onChange = function(val)
                style.barIconOffset = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })

        AddCheckboxRow(panel, {
            label = "Custom Icon Size",
            value = style.barIconSizeOverride or false,
            onChange = function(val)
                style.barIconSizeOverride = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if style.barIconSizeOverride then
            AddSliderRow(panel, {
                label = "Icon Size",
                indent = true,
                min = 5, max = 100, step = 0.1,
                value = style.barIconSize or 20,
                onChange = function(val)
                    style.barIconSize = val
                    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                end,
            })
        end

        ST._BuildIconZoomControls(panel, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, {
            previewRefresh = function()
                if ST._RefreshButtonsPreviewMirror then
                    ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
                end
            end,
        })
    end

    local _, iconAdvBtn = AddAdvancedToggle(showIconRow, "barIcon", tabInfoButtons, style.showBarIcon ~= false, {
        title = "Bar Icon Advanced",
        build = BuildBarIconAdvanced,
    })
    CreateCheckboxPromoteButton(showIconRow, iconAdvBtn, "barIcon", group, style)

    -- Show Name Text toggle
    local showNameRow = AddCheckboxRow(textLeft, {
        label = "Show Name Text",
        value = style.showBarNameText ~= false,
        onChange = function(val)
            style.showBarNameText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
    local function BuildBarNameTextAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Flip Name Text",
            value = style.barNameTextReverse or false,
            onChange = function(val)
                style.barNameTextReverse = val or nil
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })

        AddFontControls(panel, style, "barName", {sizeMin = 6, sizeMax = 24, size = 10}, refreshStyle, { row = true })
        -- deferCommit is deliberately absent, matching the AddColorPicker call
        -- this row replaced.
        AddColorRow(panel, {
            label = "Font Color",
            tbl = style,
            key = "barNameFontColor",
            default = {1, 1, 1, 1},
            hasAlpha = true,
            onConfirm = refreshStyle,
            onChange = refreshStyle,
        })
        AddOffsetSliders(panel, style, "barNameTextOffsetX", "barNameTextOffsetY", {range = 50}, refreshStyle, { row = true })
    end

    local _, nameAdvBtn = AddAdvancedToggle(showNameRow, "barNameText", tabInfoButtons, style.showBarNameText ~= false, {
        title = "Name Text Advanced",
        build = BuildBarNameTextAdvanced,
    })
    CreateCheckboxPromoteButton(showNameRow, nameAdvBtn, "barNameText", group, style)

    -- Show Cooldown Text toggle
    local showTimeRow = AddCheckboxRow(textLeft, {
        label = "Show Cooldown Text",
        value = style.showCooldownText or false,
        onChange = function(val)
            style.showCooldownText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    local barCdTextAdvanced = MakeBarCooldownTextAdvancedDescriptor()

    local _, timeAdvBtn = AddAdvancedToggle(showTimeRow, barCdTextAdvanced.settingKey, tabInfoButtons, style.showCooldownText, {
        title = barCdTextAdvanced.title,
        build = barCdTextAdvanced.build,
    })
    CreateCheckboxPromoteButton(showTimeRow, timeAdvBtn, "cooldownText", group, style)

    -- Duration Format sits with the cooldown text it formats. It is not gated
    -- on that toggle in bar mode (ready text reads it too), so it is a row of
    -- its own rather than an indented child.
    AddDurationFormatDropdown(textLeft, style, refreshStyle, { row = true })

    -- Show Charge Text toggle
    local chargeTextRow = AddCheckboxRow(textLeft, {
        label = "Show Count Text (Charges/Uses)",
        value = style.showChargeText ~= false,
        onChange = function(val)
            style.showChargeText = val
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
    -- deferCommit is deliberately absent throughout, matching the AddColorPicker
    -- calls these rows replaced.
    local function BuildBarChargeTextAdvanced(panel)
        AddFontControls(panel, style, "charge", {}, refreshStyle, { row = true })

        local function ChargeColorRow(rowLabel, key)
            AddColorRow(panel, {
                label = rowLabel,
                tooltip = { rowLabel },
                tbl = style,
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

        AddAnchorDropdown(panel, style, "chargeAnchor", "BOTTOMRIGHT", refreshStyle, nil, { row = true })
        AddOffsetSliders(panel, style, "chargeXOffset", "chargeYOffset", {x = -2, y = 2}, refreshStyle, { row = true })
    end

    local _, chargeAdvBtn = AddAdvancedToggle(chargeTextRow, "barChargeText", tabInfoButtons, style.showChargeText ~= false, {
        title = "Count Text Advanced",
        build = BuildBarChargeTextAdvanced,
    })
    CreateCheckboxPromoteButton(chargeTextRow, chargeAdvBtn, "chargeText", group, style)

    -- Show Ready Text toggle
    local showReadyRow = AddCheckboxRow(textLeft, {
        label = "Show Ready Text",
        value = style.showBarReadyText or false,
        onChange = function(val)
            style.showBarReadyText = val
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
            value = style.barReadyText or "Ready",
            onEnterPressed = function(val)
                style.barReadyText = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
        if readyRow.editbox and readyRow.editbox.Instructions then
            readyRow.editbox.Instructions:Hide()
        end

        -- deferCommit is deliberately absent, matching the AddColorPicker call
        -- this row replaced.
        AddColorRow(panel, {
            label = "Ready Text Color",
            tbl = style,
            key = "barReadyTextColor",
            default = {0.2, 1.0, 0.2, 1.0},
            hasAlpha = true,
            onConfirm = refreshStyle,
            onChange = refreshStyle,
        })
        AddFontControls(panel, style, "barReady", {sizeMin = 6, sizeMax = 24}, refreshStyle, { row = true })
    end

    local _, readyAdvBtn = AddAdvancedToggle(showReadyRow, "barReadyText", tabInfoButtons, style.showBarReadyText, {
        title = "Ready Text Advanced",
        build = BuildBarReadyTextAdvanced,
    })
    CreateCheckboxPromoteButton(showReadyRow, readyAdvBtn, "barReadyText", group, style)

    -- Bar aura block: fills the Blizzard-driven aura bar composited over the CC
    -- bar, plus the aura text toggles. Shown only while the group has an
    -- aura-tracking entry (same gate as the icon-side aura sections). Style
    -- edits route through refreshStyle -> UpdateGroupStyle -> RequestAuraRebind,
    -- which defers to combat end with the one-time note when needed.
    if GroupHasAuraTrackingEntry(group) then
        AddColorRow(textRight, {
            label = "Bar Aura Timer Color",
            tbl = style, key = "barAuraColor",
            default = {0.2, 1.0, 0.2, 1.0}, hasAlpha = true,
            onConfirm = refreshStyle, onChange = refreshStyle,
        })

        -- Aura duration text: rendered by the aura display at the bar's time
        -- text position (it follows the Flip Time Text and offset settings
        -- from the Cooldown Text section).
        local auraTextRow = AddCheckboxRow(textRight, {
            label = "Show Aura Duration Text",
            value = style.showAuraText ~= false,
            onChange = function(val)
                style.showAuraText = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
        -- deferCommit is deliberately absent, matching the AddColorPicker call
        -- the color row replaced.
        local function BuildBarAuraTextAdvanced(panel)
            AddFontControls(panel, style, "auraText", { size = 12 }, refreshStyle, { row = true })
            AddColorRow(panel, {
                label = "Font Color",
                tbl = style,
                key = "auraTextFontColor",
                default = {0, 0.925, 1, 1},
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })
        end
        AddAdvancedToggle(auraTextRow, "barAuraText", tabInfoButtons, style.showAuraText ~= false, {
            title = "Aura Duration Text Advanced",
            build = BuildBarAuraTextAdvanced,
        })
        -- Second badge in the chain, after the gear. The anchor args below are
        -- a placeholder - AnchorRowBadge re-points the button onto the end of
        -- the label's chain.
        AnchorRowBadge(auraTextRow, CreateInfoButton(auraTextRow.frame, auraTextRow.frame, "LEFT", "LEFT", 0, 0, {
            "Aura Duration Text",
            {"Shows the remaining aura time at the bar's time text position while the aura is active. Position follows the flip and offset settings in the Cooldown Text section.", 1, 1, 1, true},
        }, auraTextRow))

        -- Aura stack text: Blizzard writes the live stack count; anchored to
        -- the icon square (or the bar with the icon hidden).
        local auraStackRow = AddCheckboxRow(textRight, {
            label = "Show Aura Stack Text",
            value = style.showAuraStackText ~= false,
            onChange = function(val)
                style.showAuraStackText = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
        local function BuildBarAuraStackTextAdvanced(panel)
            AddFontControls(panel, style, "auraStack", { size = 12 }, refreshStyle, { row = true })
            -- deferCommit is deliberately absent, matching the AddColorPicker
            -- call this row replaced.
            AddColorRow(panel, {
                label = "Font Color",
                tbl = style,
                key = "auraStackFontColor",
                default = {1, 1, 1, 1},
                hasAlpha = true,
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })
            AddAnchorDropdown(panel, style, "auraStackAnchor", "BOTTOMLEFT", refreshStyle, nil, { row = true })
            AddOffsetSliders(panel, style, "auraStackXOffset", "auraStackYOffset", { x = 2, y = 2 }, refreshStyle, { row = true })
        end
        AddAdvancedToggle(auraStackRow, "barAuraStackText", tabInfoButtons, style.showAuraStackText ~= false, {
            title = "Aura Stack Text Advanced",
            build = BuildBarAuraStackTextAdvanced,
        })
        AnchorRowBadge(auraStackRow, CreateInfoButton(auraStackRow.frame, auraStackRow.frame, "LEFT", "LEFT", 0, 0, {
            "Aura Stack Text",
            {"Shows the live stack count while the aura is active, drawn by the game so it stays accurate in combat. Stack counts cannot drive the bar fill; the count is hidden from addons during combat.", 1, 1, 1, true},
        }, auraStackRow))
    end

    -- Compact Mode toggle + advanced (growth direction, max visible buttons)
    BuildCompactModeControls(textRight, group, tabInfoButtons)
    end -- not textIconCollapsed

    BuildGroupSettingPresetControls(container, group, "bars", tabInfoButtons)

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
local function BuildBarActiveAuraSection(container, group, style)
    if not GroupHasAuraTrackingEntry(group) then
        -- The section owning an active preview just disappeared (last aura
        -- entry removed); don't leave the preview glow orphaned.
        CooldownCompanion:SetGroupBarAuraEffectPreview(CS.selectedGroup, false)
        return
    end

    local hasBorderEffect = style.barAuraEffect ~= nil
        and style.barAuraEffect ~= "color" and style.barAuraEffect ~= "none"
    local anyEffect = hasBorderEffect
        or style.barAuraPulseEnabled == true
        or style.barAuraColorShiftEnabled == true
    local indicatorOn = ST.IsBarAuraIndicatorEnabled(style) and anyEffect

    if container then
        local enableRow = AddCheckboxRow(container, {
            label = "Show Active Aura Indicator",
            value = indicatorOn,
            onChange = function(val)
                style.barAuraIndicatorEnabled = val
                if val and not (style.barAuraEffect and style.barAuraEffect ~= "color" and style.barAuraEffect ~= "none"
                    or style.barAuraPulseEnabled == true or style.barAuraColorShiftEnabled == true) then
                    -- Nothing visible was configured; force the pulse border and
                    -- reset its per-style keys (a leftover proc-scale size would
                    -- render a 30px wall).
                    style.barAuraEffect = "pulse"
                    style.barAuraEffectSize = 2
                    style.barAuraEffectSpeed = 0.5
                end
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Single rail (AdvancedSettingsPanel.lua): this builder's row path opens
        -- its own two-column grid, which a ~330px panel has no room for, so
        -- opts.singleRail suppresses it and rails the border effect and the two
        -- fill effects onto the panel scroll in order.
        local function BuildBarActiveAuraAdvanced(panel)
            BuildBarActiveAuraControls(panel, style, function()
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end, { row = true, singleRail = true, infoButtons = tabInfoButtons })
        end

        AddAdvancedToggle(enableRow, "barActiveAura", tabInfoButtons, indicatorOn, {
            title = "Active Aura Indicator Advanced",
            build = BuildBarActiveAuraAdvanced,
        })
        CreateCheckboxPromoteButton(enableRow, nil, "barActiveAura", group, style)
        -- Third badge in the chain: gear, promote, then this. The anchor args
        -- below are a placeholder - AnchorRowBadge appends to whatever the
        -- chain actually ends at.
        AnchorRowBadge(enableRow, CreateInfoButton(enableRow.frame, enableRow.frame, "LEFT", "LEFT", 0, 0, {
            "Active Aura Indicator",
            {"Adds a border effect to a bar while its tracked aura is active, with optional fill pulse and fill color shift. The preview shows the bar as if the aura were running.", 1, 1, 1, true},
        }, tabInfoButtons))
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
-- section, with the marker below.
local function BuildBarPandemicSection(container, group, style)
    local function ClearPandemicPreview()
        if CooldownCompanion.SetGroupBarPandemicPreview then
            CooldownCompanion:SetGroupBarPandemicPreview(CS.selectedGroup, false)
        end
    end
    if not GroupHasAuraTrackingEntry(group) then
        ClearPandemicPreview()
        return
    end

    local pandemicOn = style.pandemicEffectEnabled == true
    if container then
        local enableRow = AddCheckboxRow(container, {
            label = "Show Pandemic Color",
            value = pandemicOn,
            onChange = function(val)
                style.pandemicEffectEnabled = val and true or false
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
        CreateCheckboxPromoteButton(enableRow, nil, "pandemic", group, style)
        AnchorRowBadge(enableRow, CreateInfoButton(enableRow.frame, enableRow.frame, "LEFT", "LEFT", 0, 0, {
            "Pandemic Color",
            {"The bar fill wears this color instead of the active aura color while the tracked aura is in its refresh window, when recasting adds bonus time.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"Only appears for auras that gain bonus time when refreshed. The game decides the window.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"Each entry can opt out in its Aura tab.", 1, 1, 1, true},
        }, tabInfoButtons))

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
                tbl = style,
                key = "barPandemicColor",
                default = {1, 0.5, 0, 1},
                hasAlpha = false,
                onConfirm = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end,
                onChange = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end,
            })
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
local function BuildBarPandemicMarkerSection(container, group, style)
    if not container or not GroupHasAuraTrackingEntry(group) then
        return
    end

    local applyStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    local markerRow = AddPandemicMarkerControls(container, style, applyStyle, function()
        CooldownCompanion:RefreshConfigPanel()
    end, { enableOnly = true })

    -- Single rail (AdvancedSettingsPanel.lua): the styling rows fill the panel,
    -- so childrenOnly drops the indent they carry when inline.
    local function BuildBarPandemicMarkerAdvanced(panel)
        AddPandemicMarkerControls(panel, style, applyStyle, function()
            if CS.RefreshAdvancedSettingsPanel then
                CS.RefreshAdvancedSettingsPanel()
            end
        end, { childrenOnly = true })
    end

    -- "barPandemicMarker", not the icons key: every bars gear in this file
    -- carries its own prefixed key (barAuraText, barNameText, barChargeText),
    -- so a panel switch can never rebind an open panel onto the other mode's
    -- builder. The gear-to-section map names both.
    local _, markerAdvBtn = AddAdvancedToggle(markerRow, "barPandemicMarker", tabInfoButtons,
        style.pandemicMarkerEnabled ~= false, {
            title = "Pandemic Marker Advanced",
            build = BuildBarPandemicMarkerAdvanced,
        })
    -- Same override section as the fill row above: one feature, one promote
    -- target, a badge on either row.
    CreateCheckboxPromoteButton(markerRow, markerAdvBtn, "pandemic", group, style)
end

local function BuildBarEffectsTab(container, group, style)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end

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
    BuildBarActiveAuraSection(glowsHost, group, style)

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
    BuildBarPandemicSection(pandemicLeft, group, style)
    BuildBarPandemicMarkerSection(pandemicRight, group, style)

    -- The remaining indicators all render on the bar's icon square.
    if style.showBarIcon ~= false then
        -- ================================================================
        -- Timers
        -- ================================================================
        local _, timersCollapsed = BuildCollapsibleSection(container, "Timers", EFFECTS_TIMERS_SECTION, nil, nil, ROW_SECTION)

        if not timersCollapsed then
        -- One row; the right column is deliberately empty.
        local timerLeft = BeginRowGrid(container)

        local gcdRow = AddCheckboxRow(timerLeft, {
            label = "Show GCD Swipe",
            value = style.showGCDSwipe == true,
            onChange = function(val)
                style.showGCDSwipe = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
        CreateCheckboxPromoteButton(gcdRow, nil, "showGCDSwipe", group, style)
        end -- not timersCollapsed

        -- ================================================================
        -- States
        -- ================================================================
        local _, statesCollapsed = BuildCollapsibleSection(container, "States", EFFECTS_STATES_SECTION, nil, nil, ROW_SECTION)

        if not statesCollapsed then
        -- LEFT column: the two looks the bar's icon takes on by itself.
        -- RIGHT column: the situational state and the hover behavior.
        local stateLeft, stateRight = BeginRowGrid(container)

        local desatRow = AddCheckboxRow(stateLeft, {
            label = "Show Desaturate On Cooldown",
            value = style.desaturateOnCooldown or false,
            onChange = function(val)
                style.desaturateOnCooldown = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
        CreateCheckboxPromoteButton(desatRow, nil, "desaturation", group, style)

        local unusableRow, unusableAdvBtn = BuildUnusableDimmingControls(stateLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, { row = true })
        CreateCheckboxPromoteButton(unusableRow, unusableAdvBtn, "unusableDimming", group, style)

        local locRow = BuildLossOfControlControls(stateRight, style, refreshStyle, { row = true })
        CreateCheckboxPromoteButton(locRow, nil, "lossOfControl", group, style)

        local tooltipRow, tooltipAdvBtn = BuildShowTooltipsControls(stateRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, { row = true, advanced = true, infoButtons = tabInfoButtons })
        CreateCheckboxPromoteButton(tooltipRow, tooltipAdvBtn, "showTooltips", group, style)

        BuildAllowPingsControls(stateRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        end -- not statesCollapsed
    end

end

-- Expose for GroupTabs.lua dispatchers
ST._BuildBarAppearanceTab = BuildBarAppearanceTab
ST._BuildBarEffectsTab = BuildBarEffectsTab
