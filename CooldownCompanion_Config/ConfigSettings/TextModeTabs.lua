--[[
    CooldownCompanion - ConfigSettings/TextModeTabs.lua: Text-mode tab builders
    (the Format tab and the Appearance tab)
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local CreateInfoButton = ST._CreateInfoButton
local BuildCompactModeControls = ST._BuildCompactModeControls
local CreatePromoteButton = ST._CreatePromoteButton

-- Imports from ButtonFrame/TextMode.lua (the renderer this tab configures).
-- Text entries auto-size from a measured worst-case render of their format, so
-- this tab reports the measurement rather than offering width/height sliders.
local GetTextEntryMetrics = ST._GetTextEntryMetrics

-- Imports from SectionBuilders.lua
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown
local BuildTextFontControls = ST._BuildTextFontControls
local BuildTextColorsControls = ST._BuildTextColorsControls
local BuildTextBackgroundControls = ST._BuildTextBackgroundControls

-- Imports from RowWidgets.lua (the row grammar)
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddColorRow = ST._AddColorRow
local AddEditBoxRow = ST._AddEditBoxRow
local AddLabelRow = ST._AddLabelRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid

local tabInfoButtons = CS.tabInfoButtons

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right. The rules every row-grammar section follows are stated
-- once, in the recipe comment at the top of BuildAppearanceTab's icons path in
-- GroupTabs.lua; the sections below conform to them rather than restating them.
local ROW_SECTION = { leftAligned = true }

------------------------------------------------------------------------
-- FORMAT TAB
--
-- The whole format editor, hosted on a text panel's first tab, plus the two
-- settings that are format vocabulary. Typing repaints the pinned preview on
-- a short debounce and commits the live panel when the edit surface is left,
-- so this tab has a lifecycle the other tabs do not: a controller
-- that owns an animation driver and a pending write, both of which have to be
-- settled before the container that holds them is released or rebuilt.
--
-- Exactly one tab editor exists at a time, and it is never live at the same
-- time as the entry Format Override section's twin (ButtonSettingsOverrides.lua
-- states that contract). The three module-locals below are this one editor's
-- whole state; ReleaseTextFormatTabEditor is the single teardown, and every
-- seam that can take the container away calls it.
------------------------------------------------------------------------
local FORMAT_COMMIT_DELAY = 0.3

local formatTabController = nil
local formatCommitTimer = nil
local formatCommitTarget = nil   -- { style, groupId }, captured when scheduled
local formatLiveCommitTarget = nil
local formatPendingValue = nil

-- Temporarily exposes the edited format while repainting the pinned preview.
-- FlushTextFormatTabCommit saves it and updates the live panel when the editor
-- loses its surface.
--
-- The commit is deliberately the host's: the editor component owns no commit
-- method at all, because a shared one would have to end in RefreshConfigPanel
-- and that releases the very tab being typed in, dropping the cursor.
-- RefreshGroupFrame is everything this write needs. It covers the world side,
-- where the live panel re-parses the format through PopulateGroupButtons ->
-- UpdateTextStyle, and the config side, where it repaints the pinned mirror on
-- the way in (ST._RefreshButtonsPreviewMirror, the first thing GroupFrame.lua's
-- RefreshGroupFrame does). Neither touches the settings column.
local function CommitTextFormatTabEdit()
    formatCommitTimer = nil
    local target = formatCommitTarget
    formatCommitTarget = nil
    if not (target and formatTabController) then return end

    local raw = formatTabController:GetRawText()
    -- An empty format is never written: it would leave the panel with nothing
    -- to render and no way back except retyping the string from scratch.
    if not raw or raw == "" then return end
    if target.style.textFormat == raw then
        if formatLiveCommitTarget then
            formatLiveCommitTarget = nil
            formatPendingValue = nil
            if ST._RefreshButtonsPreviewMirror then
                ST._RefreshButtonsPreviewMirror(target.groupId)
            end
        end
        return
    end

    formatLiveCommitTarget = target
    formatPendingValue = raw
    local committed = target.style.textFormat
    target.style.textFormat = raw
    if ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(target.groupId)
    end
    target.style.textFormat = committed
end

-- The target is captured per schedule, not read at fire time, so a write that
-- lands after the user has moved on still goes to the panel they typed it in.
local function ScheduleTextFormatTabCommit(style, groupId)
    formatCommitTarget = { style = style, groupId = groupId }
    if formatCommitTimer then
        formatCommitTimer:Cancel()
    end
    formatCommitTimer = C_Timer.NewTimer(FORMAT_COMMIT_DELAY, CommitTextFormatTabEdit)
end

local function FlushTextFormatTabCommit()
    if formatCommitTimer then
        formatCommitTimer:Cancel()
        CommitTextFormatTabEdit()
    end
    local target = formatLiveCommitTarget
    formatLiveCommitTarget = nil
    if target then
        target.style.textFormat = formatPendingValue
        CooldownCompanion:RefreshGroupFrame(target.groupId)
    end
    formatPendingValue = nil
end

-- Settle the pending write FIRST, then drop the controller: the container
-- frame is about to go back into AceGUI's pool, and a commit that fires after
-- that would write against a released editor.
local function ReleaseTextFormatTabEditor()
    FlushTextFormatTabCommit()
    if formatTabController then
        formatTabController:Release()
        formatTabController = nil
    end
    formatCommitTarget = nil
    formatLiveCommitTarget = nil
    formatPendingValue = nil
end

local function BuildTextFormatTab(container)
    -- Defensive: every seam already releases before it gets here, so this is
    -- a no-op in the normal path and the backstop for anything that is not.
    ReleaseTextFormatTabEditor()

    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group or group.displayMode ~= "text" then return end
    local style = group.style
    if not style then return end
    local groupId = CS.selectedGroup

    -- Component-internal DoLayout calls are no-ops while the container is
    -- paused, so the whole tab lays out once at the end.
    container:PauseLayout()

    formatTabController = ST._BuildFormatEditorContent(container, {
        -- The Format tab always edits the PANEL's format, whether or not an
        -- entry is selected: per-entry overrides live on the entry's own
        -- Overrides section. No saveTarget, so the component targets the
        -- style table itself.
        target = { style = style, groupId = groupId },
        onDirty = function()
            ScheduleTextFormatTabCommit(style, groupId)
        end,
        onCommit = FlushTextFormatTabCommit,
    })

    -- Repaints the editor's preview and swatches from the style that just
    -- changed. The flush comes FIRST, before both of the reads below.
    --
    -- Against SetTarget it is what makes the refresh lossless: SetTarget
    -- re-reads style.textFormat, so any typing still sitting in the debounce
    -- has to be written before it is read back.
    --
    -- Against UpdateGroupStyle it is what keeps the panel from rendering a
    -- format the user has already replaced: restyling first laid the panel out
    -- against the stale string and then had the flush's own RefreshGroupFrame
    -- re-measure it a moment later, so the panel showed one frame of the old
    -- format for nothing.
    local function refreshStyleAndPreview()
        FlushTextFormatTabCommit()
        CooldownCompanion:UpdateGroupStyle(groupId)
        if formatTabController and not formatTabController.released then
            formatTabController:SetTarget({ style = style, groupId = groupId })
        end
    end

    -- ================================================================
    -- Format Settings
    --
    -- LEFT: how a duration reads wherever the format prints one. RIGHT: the
    -- word {status} falls back to. Both are vocabulary the format spends, so
    -- they sit under the editor that spends it rather than with the panel's
    -- geometry on Appearance.
    -- ================================================================
    local _, settingsCollapsed = BuildCollapsibleSection(container, "Format Settings", "textformat_settings", nil, nil, ROW_SECTION)

    if not settingsCollapsed then
    local fmtLeft, fmtRight = BeginRowGrid(container)

    -- The shared builder has no tooltip of its own, so the row gets one here.
    local durationRow = AddDurationFormatDropdown(fmtLeft, style, refreshStyleAndPreview, { row = true })
    if durationRow and durationRow.SetRowTooltip then
        durationRow:SetRowTooltip({
            "Duration Format",
            {"How a countdown reads wherever the format prints one.", 1, 1, 1, true},
        })
    end

    -- The CDC-EditBoxRow embeds a stock EditBox, so the raw frame the
    -- Instructions text hangs on is still reachable through row.editbox.
    local readyTextRow = AddEditBoxRow(fmtRight, {
        label = "Ready Text",
        value = style.textReadyText or "Ready",
        onEnterPressed = function(val)
            style.textReadyText = val
            refreshStyleAndPreview()
        end,
    })
    if readyTextRow.editbox and readyTextRow.editbox.Instructions then
        readyTextRow.editbox.Instructions:Hide()
    end
    -- Anchor args are a placeholder - AnchorRowBadge re-points the button onto
    -- the end of the row's label.
    AnchorRowBadge(readyTextRow, CreateInfoButton(readyTextRow.frame, readyTextRow.frame, "LEFT", "LEFT", 0, 0, {
        "Ready Text",
        {"The word |cff00ff00{status}|r shows when the spell is ready.", 1, 1, 1, true},
    }, tabInfoButtons))
    end -- not settingsCollapsed

    container:ResumeLayout()
    container:DoLayout()
end

local function BuildTextAppearanceTab(container, group, style)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    local refreshFrame = function() CooldownCompanion:RefreshGroupFrame(CS.selectedGroup) end

    -- The format itself, and the two settings that are format vocabulary
    -- rather than panel geometry, now own the Format tab (BuildTextFormatTab
    -- below). What is left here decorates what the format already decided to
    -- say: Font, Colors, Panel, Background & Border, Compact Mode.

    -- ================================================================
    -- Font
    -- ================================================================
    local fontHeading, fontCollapsed = BuildCollapsibleSection(container, "Font", "textappearance_font", nil, nil, ROW_SECTION)

    CreatePromoteButton(fontHeading, "textFont", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not fontCollapsed then
    -- The shared builder splits its own rows: LEFT what the text is drawn
    -- with, RIGHT how the line is laid out.
    local fontLeft, fontRight = BeginRowGrid(container)
    BuildTextFontControls(fontLeft, style, refreshStyle, { row = true, rightColumn = fontRight })
    end -- not fontCollapsed

    -- ================================================================
    -- Colors
    -- ================================================================
    local colorsHeading, colorsCollapsed = BuildCollapsibleSection(container, "Colors", "textappearance_colors", nil, nil, ROW_SECTION)

    CreatePromoteButton(colorsHeading, "textColors", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not colorsCollapsed then
    -- The whole palette the text renderer can reach. The shared builder splits
    -- its own rows: LEFT the base color and the two cooldown states, RIGHT the
    -- aura color and the tag-only custom color.
    local colorsLeft, colorsRight = BeginRowGrid(container)
    BuildTextColorsControls(colorsLeft, style, refreshStyle, { row = true, rightColumn = colorsRight })
    end -- not colorsCollapsed

    -- ================================================================
    -- Panel (padding, spacing, header)
    --
    -- There is no width or height slider here. A text entry measures itself
    -- from its format and its font (ButtonFrame/TextMode.lua renders a
    -- worst-case mock of the format onto a hidden FontString), so the only
    -- manual size knob is how much room to leave around that text. What the
    -- measurement produced is reported below it, read-only.
    -- ================================================================
    local _, panelCollapsed = BuildCollapsibleSection(container, "Panel", "textappearance_settings", nil, nil, ROW_SECTION)

    if not panelCollapsed then
    -- LEFT column: how one entry is sized and how the entries stack.
    -- RIGHT column: the optional group header with the two rows it owns.
    local panelLeft, panelRight = BeginRowGrid(container)

    -- Declared ahead of the slider that changes it: dragging Padding resizes
    -- the entry, so the reported size has to move with the drag rather than
    -- wait for the next tab rebuild.
    local entrySizeRow

    -- The panel's grid pitch, computed exactly the way GroupFrame's
    -- GetButtonDimensions and the mirror's GetPanelGeometry compute it: the
    -- panel's own baseline entry (no entry data) as a floor, then the max over
    -- every entry measured through its OWN effective style and format.
    --
    -- The baseline alone measures {name} as an empty string, which under-reports
    -- a real panel by roughly the width of its longest spell name.
    local function FormatEntrySize()
        if not GetTextEntryMetrics then return "" end
        local entryWidth, entryHeight = GetTextEntryMetrics(style, nil, style.textFormat)
        for _, buttonData in ipairs(group.buttons or {}) do
            local effectiveStyle = CooldownCompanion.GetEffectiveStyle
                and CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
            local fmt = buttonData.textFormat or effectiveStyle.textFormat
            local width, height = GetTextEntryMetrics(effectiveStyle, buttonData, fmt)
            if width > entryWidth then entryWidth = width end
            if height > entryHeight then entryHeight = height end
        end
        return string.format("%d \195\151 %d", math.floor(entryWidth + 0.5), math.floor(entryHeight + 0.5))
    end

    AddSliderRow(panelLeft, {
        label = "Padding",
        min = 0, max = 20, step = 1,
        value = style.textPadding or 4,
        onChange = function(val)
            local committed = style.textPadding
            style.textPadding = val
            ST._RefreshSelectedButtonsPreview()
            if entrySizeRow then
                entrySizeRow:SetControlText(FormatEntrySize())
            end
            style.textPadding = committed
        end,
        onRelease = function(val)
            style.textPadding = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })

    if GetTextEntryMetrics then
        entrySizeRow = AddLabelRow(panelLeft, {
            label = "Entry Size",
            controlText = FormatEntrySize(),
        })
        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label.
        AnchorRowBadge(entrySizeRow, CreateInfoButton(entrySizeRow.frame, entrySizeRow.frame, "LEFT", "LEFT", 0, 0, {
            "Entry Size",
            {"The panel sizes each entry from its format and its font.", 1, 1, 1, true},
            " ",
            {"Padding adds room around the text.", 1, 1, 1, true},
        }, tabInfoButtons))
    end

    if group.buttons and #group.buttons > 1 then
        AddSliderRow(panelLeft, {
            label = "Entry Spacing",
            min = -10, max = 100, step = 0.1,
            value = style.buttonSpacing or ST.BUTTON_SPACING,
            onChange = function(val)
                ST._PreviewScalarSetting(style, "buttonSpacing", val, ST._RefreshSelectedButtonsPreview)
            end,
            onRelease = function(val)
                style.buttonSpacing = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
    end

    AddCheckboxRow(panelRight, {
        label = "Show Group Header",
        value = style.showTextGroupHeader == true,
        onChange = function(val)
            style.showTextGroupHeader = val or false
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if style.showTextGroupHeader then
        AddSliderRow(panelRight, {
            label = "Header Font Size",
            indent = true,
            min = 6, max = 72, step = 1,
            value = style.textHeaderFontSize or 12,
            onChange = function(val)
                ST._PreviewScalarSetting(style, "textHeaderFontSize", val, ST._RefreshSelectedButtonsPreview)
            end,
            onRelease = function(val)
                style.textHeaderFontSize = val
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end,
        })

        AddColorRow(panelRight, {
            label = "Header Color",
            indent = true,
            tbl = style, key = "textHeaderFontColor",
            default = {1, 1, 1, 1}, hasAlpha = true,
            onConfirm = refreshFrame, onChange = refreshFrame,
        })
    end
    end -- not panelCollapsed

    -- ================================================================
    -- Background & Border
    -- ================================================================
    local bgHeading, bgCollapsed = BuildCollapsibleSection(container, "Background & Border", "textappearance_bg", nil, nil, ROW_SECTION)

    CreatePromoteButton(bgHeading, "textBackground", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not bgCollapsed then
    -- The backdrop and the border that frames it read together, so they stay
    -- in one column. The right column is deliberately empty.
    local bgLeft = BeginRowGrid(container)
    BuildTextBackgroundControls(bgLeft, style, refreshStyle, { row = true })
    end -- not bgCollapsed

    -- ================================================================
    -- Compact Mode Controls
    -- ================================================================
    -- One row, in a grid of its own so it keeps the grammar's half-width cell
    -- rather than stretching its control column across the whole tab.
    local compactLeft = BeginRowGrid(container)
    BuildCompactModeControls(compactLeft, group, tabInfoButtons)
end

-- Exports
ST._BuildTextAppearanceTab = BuildTextAppearanceTab
ST._BuildTextFormatTab = BuildTextFormatTab

-- Lifecycle hooks for the Format tab's live editor. Called through ST at fire
-- time rather than captured at load, so file order does not matter:
--   Release - every seam that releases or rebuilds the tab's container
--             (GroupSettingsHost's tab callback and refresh, the config's
--             OnHide).
--   Flush   - seams that do not take the container away but must not read a
--             stale format (the popout opening over a live tab).
ST._ReleaseTextFormatTabEditor = ReleaseTextFormatTabEditor
ST._FlushTextFormatTabCommit = FlushTextFormatTabCommit
