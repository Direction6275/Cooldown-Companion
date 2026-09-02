--[[
    CooldownCompanion - ConfigSettings/TextModeTabs.lua: Text-mode tab builders
    (the Format tab and the Appearance tab)
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local CreateInfoButton = ST._CreateInfoButton

-- Style lens (Helpers.lua). Selecting an entry turns the Appearance tab into a
-- view of that entry's effective values, with per-section scope deciding where
-- - or whether - each section writes. Helpers.lua loads first (the .toc), so
-- these resolve at load like every other import above.
--
-- BeginLensSection owns the per-section ritual on both tabs. ResolveLensSection
-- stays only for the finder predicates below, which want a section's scope
-- and nothing else.
local ResolveStyleLens = ST._ResolveStyleLens
local ResolveLensSection = ST._ResolveLensSection
local BeginLensSection = ST._BeginLensSection
local ResolveLensCollapseKey = ST._ResolveLensCollapseKey
local AddLensPanelScopeNote = ST._AddLensPanelScopeNote

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
-- GroupTabsAppearance.lua; the sections below conform to them rather than
-- restating them.
local ROW_SECTION = { leftAligned = true }

-- Section actions sit on one grammar-height line (ButtonConditions.lua states
-- the idiom): compact SetAutoWidth buttons, flush left, never page-wide.
local FORMAT_ACTION_STRIP_HEIGHT = (ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT) or 30

-- Populated at module load near the exports. Builders close over this table so
-- every rendered row can bind the exact descriptor without constructing an
-- unopened tab.
local TEXTMODE_FINDER = {}

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
-- The tab is a LENS, like the styling tabs beside it: with exactly one entry
-- selected it edits THAT ENTRY's format - the flat buttonData.textFormat
-- field, which lives outside the styleOverrides section machinery - and with
-- none selected, or several, it edits the panel's. There is exactly ONE format
-- editor in the config, and this is it. The module-locals below are its whole
-- state; ReleaseTextFormatTabEditor is the single teardown, and every seam
-- that can take the container away calls it.
------------------------------------------------------------------------
local FORMAT_COMMIT_DELAY = 0.3

-- Mirrors DEFAULT_TEXT_FORMAT in ButtonFrame/TextMode.lua, and the same
-- seeding string the entry format editor has always used.
local DEFAULT_TEXT_FORMAT = "{name}  {status}"

-- The scope note's two states, in the scope chrome's own colors
-- (SCOPE_CHROME_GREY / SCOPE_CHROME_GOLD, Helpers.lua).
local FORMAT_SCOPE_GREY = { 0.5, 0.5, 0.5 }
local FORMAT_SCOPE_GOLD = { 1, 0.82, 0 }

local formatTabController = nil
local formatCommitTimer = nil
local formatCommitTarget = nil   -- { style, saveTarget, groupId }, captured when scheduled
local formatLiveCommitTarget = nil
local formatPendingValue = nil
-- The live tab's ENTRY chrome, or nil under a panel/multi lens: the revert
-- button and the scope note, both of which the debounced commit flips in place
-- on the edit that creates the entry's format.
local formatClearButton = nil
local formatScopeNote = nil
local formatScopeCustomText = nil

-- Where the edited format is SAVED: the entry when the tab is a lens onto one,
-- the panel style otherwise. The component follows the same rule for reading
-- (target.saveTarget or target.style), so the two never disagree.
local function GetFormatCommitHost(target)
    return target.saveTarget or target.style
end

-- The entry's format did not exist a moment ago and does now, and the commit
-- deliberately does not rebuild the config, so nothing else would notice.
local function MarkFormatScopeCustomized()
    if formatScopeNote and formatScopeCustomText then
        formatScopeNote:SetText(formatScopeCustomText)
        formatScopeNote:SetColor(FORMAT_SCOPE_GOLD[1], FORMAT_SCOPE_GOLD[2], FORMAT_SCOPE_GOLD[3])
    end
end

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
--
-- Under an entry lens the editor seeds from the panel's format when the entry
-- has none of its own, so the first edit is what CREATES the entry's format -
-- including an edit that lands back on the panel's own text. Clear is the way
-- back.
local function CommitTextFormatTabEdit()
    formatCommitTimer = nil
    local target = formatCommitTarget
    formatCommitTarget = nil
    if not (target and formatTabController) then return end

    local raw = formatTabController:GetRawText()
    -- An empty format is never written: it would leave the panel with nothing
    -- to render and no way back except retyping the string from scratch.
    if not raw or raw == "" then return end
    local host = GetFormatCommitHost(target)
    if host.textFormat == raw then
        if formatLiveCommitTarget then
            formatLiveCommitTarget = nil
            formatPendingValue = nil
            if ST._RefreshButtonsPreviewMirror then
                ST._RefreshButtonsPreviewMirror(target.groupId)
            end
        end
        return
    end

    -- This is the write that can CREATE an entry's format, and it deliberately
    -- does not rebuild the config, so the entry chrome is flipped in place.
    -- Cheap and unconditional: on an edit that only UPDATES an existing format
    -- the button is already enabled and this is a no-op, and under a panel lens
    -- there is no chrome to flip.
    --
    -- The references are only ever the live tab's own widgets - they are
    -- dropped before this can run against a torn-down tab (see
    -- ReleaseTextFormatTabEditor) and again by each widget's own OnRelease (see
    -- BuildTextFormatTab), so they never point into AceGUI's pool.
    if formatClearButton then
        formatClearButton:SetDisabled(false)
    end
    MarkFormatScopeCustomized()

    formatLiveCommitTarget = target
    formatPendingValue = raw
    local committed = host.textFormat
    host.textFormat = raw
    if ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(target.groupId)
    end
    host.textFormat = committed
end

-- The target is captured per schedule, not read at fire time, so a write that
-- lands after the user has moved on still goes to the panel - or the ENTRY -
-- they typed it in.
local function ScheduleTextFormatTabCommit(style, groupId, saveTarget)
    formatCommitTarget = { style = style, groupId = groupId, saveTarget = saveTarget }
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
        GetFormatCommitHost(target).textFormat = formatPendingValue
        CooldownCompanion:RefreshGroupFrame(target.groupId)
    end
    formatPendingValue = nil
end

-- Drops a pending write instead of settling it. Only Clear wants this: the
-- write it would flush is the very key the clear removes.
local function CancelTextFormatTabCommit()
    if formatCommitTimer then
        formatCommitTimer:Cancel()
        formatCommitTimer = nil
    end
    formatCommitTarget = nil
    formatLiveCommitTarget = nil
    formatPendingValue = nil
end

-- Settle the pending write FIRST, then drop the controller: the container
-- frame is about to go back into AceGUI's pool, and a commit that fires after
-- that would write against a released editor.
local function ReleaseTextFormatTabEditor()
    -- The entry chrome is dropped BEFORE the flush, not with the rest of the
    -- state after it. One caller (BuildTextFormatTab's defensive release) runs
    -- after the container has already been recycled, so by flush time those
    -- widgets can be back in AceGUI's pool wearing someone else's label.
    -- Nothing is lost by skipping the flip here: a release is always followed
    -- by a rebuild that reads buttonData.textFormat fresh.
    formatClearButton = nil
    formatScopeNote = nil
    formatScopeCustomText = nil
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

    -- STYLE LENS (Helpers.lua), resolved once for the whole tab. Exactly one
    -- entry selected turns the editor onto that entry's own format; panel and
    -- multi keep the panel's, which is what the tab has always edited.
    local lens = ResolveStyleLens(group)
    local entryData = (lens.mode == "entry") and lens.buttonData or nil

    -- Component-internal DoLayout calls are no-ops while the container is
    -- paused, so the whole tab lays out once at the end.
    container:PauseLayout()

    -- Under a multi selection this tab edits the PANEL's format, and only this
    -- line says so. No-op in every other lens mode. Added while the layout is
    -- paused, like every other child of this tab.
    AddLensPanelScopeNote(container, lens)

    -- Fresh table per call: the component keeps the one it is handed, and the
    -- commit captures its own per schedule, so no two may be the same table.
    -- defaultFormat is the seeding contract - an entry with no format of its
    -- own opens on the panel's.
    local function MakeEditorTarget()
        if entryData then
            return {
                style = style,
                groupId = groupId,
                saveTarget = entryData,
                defaultFormat = style.textFormat or DEFAULT_TEXT_FORMAT,
            }
        end
        return { style = style, groupId = groupId }
    end

    -- Whose format is being edited, in the scope chrome's language - the same
    -- two strings a section heading shows, grey "Panel setting" and gold
    -- "Customized for <name>", off the same name resolver and truncation
    -- (ST._GetLensEntryName). Bespoke only in its plumbing rather than its
    -- wording: that chrome's actions are the section machinery's Promote and
    -- Revert, and this field is a flat one outside it - Revert to Panel Format
    -- below is its only way back.
    if entryData then
        local entryName = ST._GetLensEntryName and ST._GetLensEntryName(lens)
        formatScopeCustomText = "Customized for " .. (entryName or "this entry")

        local note = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(note)
        note:SetFullWidth(true)
        note:SetFontObject(GameFontNormalSmall)
        if entryData.textFormat ~= nil then
            note:SetText(formatScopeCustomText)
            note:SetColor(FORMAT_SCOPE_GOLD[1], FORMAT_SCOPE_GOLD[2], FORMAT_SCOPE_GOLD[3])
        else
            note:SetText("Panel setting")
            note:SetColor(FORMAT_SCOPE_GREY[1], FORMAT_SCOPE_GREY[2], FORMAT_SCOPE_GREY[3])
        end
        -- Second half of the reference's lifecycle, same shape as the revert
        -- button's below: AceGUI fires OnRelease on the way into the pool, so the
        -- reference cannot outlive the widget it names. Chain, don't replace -
        -- ConfigureWrappedHelperLabel already installed its own restore handler.
        local prevOnRelease = note.events and note.events["OnRelease"]
        note:SetCallback("OnRelease", function(widget, event, ...)
            if prevOnRelease then
                prevOnRelease(widget, event, ...)
            end
            if formatScopeNote == widget then
                formatScopeNote = nil
            end
        end)
        formatScopeNote = note
        container:AddChild(note)
    end

    formatTabController = ST._BuildFormatEditorContent(container, {
        setting = TEXTMODE_FINDER.format and TEXTMODE_FINDER.format.string,
        target = MakeEditorTarget(),
        onDirty = function()
            ScheduleTextFormatTabCommit(style, groupId, entryData)
        end,
        onCommit = FlushTextFormatTabCommit,
    })

    -- The way back to the panel's format sits below the content it replaces,
    -- compact and flush left on one grammar-height line.
    --
    -- Built ALWAYS under an entry lens, disabled while the entry has no format
    -- of its own, rather than built with the field: the debounced commit that
    -- creates it does not rebuild the config (it would drop the edit box's
    -- focus), so a strip conditional on the field would arrive a rebuild late -
    -- the user would type a format and see no way back until something else
    -- refreshed the tab. A row that is always present only has to change
    -- state, which the commit can do in place, and the tab's height never moves.
    if entryData then
        local btnRow = AceGUI:Create("SimpleGroup")
        btnRow:SetFullWidth(true)
        btnRow:SetLayout("Flow")
        btnRow:SetHeight(FORMAT_ACTION_STRIP_HEIGHT)
        btnRow.noAutoHeight = true

        local clearBtn = AceGUI:Create("Button")
        -- Named for where the click LANDS, the way the section chrome's Revert
        -- is. SetAutoWidth measures the string it is given (SetText recomputes
        -- through the same path), so the longer label needs no sizing of its own.
        clearBtn:SetText("Revert to Panel Format")
        clearBtn:SetAutoWidth(true)
        -- Stock AceGUI disabled look: SetDisabled just calls Enable/Disable on
        -- the UIPanelButtonTemplate underneath, and OnAcquire resets it to
        -- enabled, so no state leaks into the pool and nothing here is
        -- custom-styled.
        clearBtn:SetDisabled(entryData.textFormat == nil)
        clearBtn:SetCallback("OnClick", function()
            -- A debounced write from just before the click would land back on
            -- the field this clears, so it is dropped rather than flushed.
            CancelTextFormatTabCommit()
            entryData.textFormat = nil
            CooldownCompanion:RefreshGroupFrame(groupId)
            -- The one place this tab rebuilds itself: the strip comes back
            -- disabled, the note back to "Panel setting", and the rebuilt
            -- editor re-seeds from the panel's format. (Typing never takes
            -- this path - see the commit above.)
            CooldownCompanion:RefreshConfigPanel()
        end)
        clearBtn:SetCallback("OnRelease", function(widget)
            if formatClearButton == widget then
                formatClearButton = nil
            end
        end)
        formatClearButton = clearBtn
        btnRow:AddChild(clearBtn)

        -- Added last so the List-layout parent measures a populated row.
        container:AddChild(btnRow)
    end

    -- Repaints the editor's preview and swatches from the style that just
    -- changed. The flush comes FIRST, before both of the reads below.
    --
    -- Against SetTarget it is what makes the refresh lossless: SetTarget
    -- re-reads the target's format, so any typing still sitting in the debounce
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
            formatTabController:SetTarget(MakeEditorTarget())
        end
    end

    -- ================================================================
    -- Format Settings
    --
    -- LEFT: how a duration reads wherever the format prints one. RIGHT: the
    -- word {status} falls back to. Both are vocabulary the format spends, so
    -- they sit under the editor that spends it rather than with the panel's
    -- geometry on Appearance.
    --
    -- Both are PANEL settings with no per-entry form, so under an entry lens
    -- they stay bound to the panel style and go read-only rather than letting
    -- a panel-wide edit be made from an entry's page - the same rule the
    -- Appearance tab's panel-only sections follow.
    -- ================================================================
    -- Panel-only under an entry lens, so the collapse key is lens-scoped and
    -- opens folded the first time (ST._ResolveLensCollapseKey owns that rule).
    local _, settingsCollapsed = BuildCollapsibleSection(container, "Format Settings",
        ResolveLensCollapseKey(lens, group, nil, "textformat_settings"), nil, nil, ROW_SECTION)

    if not settingsCollapsed then
    local settingsSec = BeginLensSection(lens, group, nil)
    local fmtLeft, fmtRight = BeginRowGrid(container)
    settingsSec:Mark(fmtLeft)
    local fmtRightBracket = settingsSec:Bracket(fmtRight)

    -- The shared builder has no tooltip of its own, so the row gets one here.
    local durationRow = AddDurationFormatDropdown(fmtLeft, style, refreshStyleAndPreview, {
        row = true,
        setting = TEXTMODE_FINDER.formatSettings and TEXTMODE_FINDER.formatSettings.duration,
    })
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
        setting = TEXTMODE_FINDER.formatSettings and TEXTMODE_FINDER.formatSettings.readyText,
        value = style.textReadyText or "Ready",
        disabled = settingsSec.disabled,
        onEnterPressed = function(val)
            style.textReadyText = val
            refreshStyleAndPreview()
        end,
    })
    if readyTextRow.editbox and readyTextRow.editbox.Instructions then
        readyTextRow.editbox.Instructions:Hide()
    end
    -- Anchor args are a placeholder - AnchorRowBadge re-points the button onto
    -- the end of the row's label. The "?" badge stays readable through an inert
    -- section: the inert walk reaches AceGUI children and the gear, not the
    -- badges on a row's frame.
    AnchorRowBadge(readyTextRow, CreateInfoButton(readyTextRow.frame, readyTextRow.frame, "LEFT", "LEFT", 0, 0, {
        "Ready Text",
        {"The word |cff00ff00{status}|r shows when the spell is ready.", 1, 1, 1, true},
    }, tabInfoButtons))

    settingsSec:Finish()
    settingsSec:FinishBracket(fmtRightBracket)
    end -- not settingsCollapsed

    container:ResumeLayout()
    container:DoLayout()
end

-- Text mode's advanced gears, by the OVERRIDE SECTION each one belongs to.
-- Shaped and named after ST._APPEARANCE_SECTION_BY_ADVANCED_KEY (GroupTabsAppearance.lua)
-- and ST._BARMODE_SECTION_BY_ADVANCED_KEY (BarModeTabs.lua): those answer "which
-- OVERRIDE section owns this gear's values", and so does this one.
--
-- EMPTY today, deliberately. The three text override sections are drawn by
-- shared builders that carry no gear at all (BuildTextFontControls,
-- BuildTextColorsControls and BuildTextBackgroundControls in
-- SectionBuilders.lua build plain rows only). Compact Mode's gear is not
-- listed either, and no longer could be: it is group data with no override
-- section, and its row now lives on the Layout tab (GroupTabsLayout.lua's
-- Arrangement section), which this map does not describe.
--
-- The map is kept even so: a gear added to any of the three sections belongs
-- here the same day for the Customizations list. Stale-panel cleanup runs
-- maplessly through the gear-stamp sweep (AdvancedSettingsPanel.lua).
ST._TEXTMODE_SECTION_BY_ADVANCED_KEY = {}

-- Where each text override section is EDITED, now that the panel tabs are the
-- lens onto a selected entry: the tab that draws it and the collapse key of the
-- section it is drawn in. Per-MODE axis, because the same question has a
-- different answer on an icons or bars panel.
--
-- BarModeTabs.lua loads BEFORE this file (the .toc) and GroupTabsAppearance.lua
-- after it;
-- all three create the table the same way, so no axis assignment can clobber
-- another. Never replace the root - only add this axis to it.
ST._SECTION_HOME = ST._SECTION_HOME or {}
ST._SECTION_HOME.text = {
    textFont = { tab = "appearance", collapseKey = "textappearance_font" },
    textColors = { tab = "appearance", collapseKey = "textappearance_colors" },
    textBackground = { tab = "appearance", collapseKey = "textappearance_bg" },
}

local function BuildTextAppearanceTab(container, group, style)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    local refreshFrame = function() CooldownCompanion:RefreshGroupFrame(CS.selectedGroup) end

    -- STYLE LENS (Helpers.lua). With an entry selected the sections below stop
    -- being the panel's settings and become a view of that entry's EFFECTIVE
    -- ones, with per-section scope deciding where - or whether - they write.
    -- Resolved ONCE here and handed to every section, so one tab cannot
    -- disagree with itself about which entry it is showing.
    --
    -- The write table is the whole gate: nil means the section is INERT, so its
    -- rows go in read-only and no callback of its own can reach a saved table.
    local lens = ResolveStyleLens(group)

    -- Under a multi selection these sections edit the PANEL, and only this line
    -- says so - the per-section scope chrome speaks under an entry lens alone.
    -- No-op in every other lens mode.
    AddLensPanelScopeNote(container, lens)

    -- Sections with NO override identity of their own (the panel's padding,
    -- spacing and group header): an entry cannot own them, so under an entry
    -- lens they say "Applies to all entries" and go read-only
    -- rather than quietly letting a panel-wide edit be made from an entry's
    -- page. They begin a lens section with a nil sectionId, which resolves to
    -- no write table exactly under an entry lens. They keep reading and writing
    -- the PANEL style, which is the value they claim to apply to; the rows are
    -- disabled, so no callback of theirs can run.

    -- The format itself, and the two settings that are format vocabulary
    -- rather than panel geometry, now own the Format tab (BuildTextFormatTab
    -- below). What is left here decorates what the format already decided to
    -- say: Font, Colors, Panel, Background & Border.

    -- ================================================================
    -- Font
    -- ================================================================
    -- The whole collapsible IS the textFont section, so its collapse key
    -- follows that section's scope through ST._ResolveLensCollapseKey.
    local fontHeading, fontCollapsed = BuildCollapsibleSection(container, "Font",
        ResolveLensCollapseKey(lens, group, "textFont", "textappearance_font"), nil, nil, ROW_SECTION)
    local fontSec = BeginLensSection(lens, group, "textFont")
    fontSec:HeadingChrome(fontHeading)

    if not fontCollapsed then
    -- The shared builder splits its own rows: LEFT what the text is drawn
    -- with, RIGHT how the line is laid out - so BOTH columns are bracketed.
    local fontLeft, fontRight = BeginRowGrid(container)

    -- The columns only exist here, so the section's primary bracket is taken
    -- now rather than at Begin, and the right column takes a second one.
    fontSec:Mark(fontLeft)
    local fontRightBracket = fontSec:Bracket(fontRight)

    -- The shared builder reads and writes ONE table, so it is handed the
    -- section's WRITE table with the panel style behind it in opts - the
    -- styleTable + fallbackStyle pair a customized section passes - or, inert,
    -- the read-only snapshot whose stray writes go nowhere by design. The lens
    -- draws one shape for both scopes. The builder takes no `disabled` of its
    -- own: the brackets are the whole gate.
    BuildTextFontControls(fontLeft, fontSec.tbl, refreshStyle, {
        row = true,
        rightColumn = fontRight,
        fallbackStyle = fontSec.fallbackStyle,
        settings = TEXTMODE_FINDER.font,
    })

    fontSec:Finish()
    fontSec:FinishBracket(fontRightBracket)
    end -- not fontCollapsed

    -- ================================================================
    -- Colors
    -- ================================================================
    local colorsHeading, colorsCollapsed = BuildCollapsibleSection(container, "Colors",
        ResolveLensCollapseKey(lens, group, "textColors", "textappearance_colors"), nil, nil, ROW_SECTION)
    local colorsSec = BeginLensSection(lens, group, "textColors")
    colorsSec:HeadingChrome(colorsHeading)

    if not colorsCollapsed then
    -- The whole palette the text renderer can reach. The shared builder splits
    -- its own rows: LEFT the base color and the two cooldown states, RIGHT the
    -- aura color and the tag-only custom color - so BOTH columns are bracketed.
    --
    -- The "?" badges the builder hangs on each row stay readable through an
    -- inert section: the inert walk reaches AceGUI children and the gear, not
    -- the badges on a row's frame.
    local colorsLeft, colorsRight = BeginRowGrid(container)

    -- The columns only exist here, so the section's primary bracket is taken
    -- now rather than at Begin, and the right column takes a second one.
    colorsSec:Mark(colorsLeft)
    local colorsRightBracket = colorsSec:Bracket(colorsRight)

    -- Same styleTable + fallbackStyle pair as the Font section above. Ready
    -- Text is not drawn here on the panel: on this tab it belongs to the
    -- Format tab (the row below is the one exception).
    BuildTextColorsControls(colorsLeft, colorsSec.tbl, refreshStyle, {
        row = true,
        rightColumn = colorsRight,
        fallbackStyle = colorsSec.fallbackStyle,
        settings = TEXTMODE_FINDER.colors,
    })

    -- Ready Text is a key of THIS section (ST.OVERRIDE_SECTIONS lists
    -- textReadyText under textColors), but its panel editor lives on the
    -- Format tab, which always writes the panel style. Once the entry owns
    -- the section, the promoted copy would be frozen with no editor anywhere
    -- - so the row is drawn here, in the section that owns the key, exactly
    -- while that is true. Everywhere else the Format tab remains its one home.
    if colorsSec.scope == "customized" then
        -- write-or-read fallback like every sibling: "customized" promises a
        -- section flag, not a store, so the write table is never indexed on
        -- faith (a half-migrated or hand-edited profile can carry the flag
        -- with no styleOverrides table behind it). sec.tbl IS that fallback.
        local readyTextRow = AddEditBoxRow(colorsRight, {
            label = "Ready Text",
            setting = TEXTMODE_FINDER.colors and TEXTMODE_FINDER.colors.readyText,
            value = colorsSec.tbl.textReadyText or "Ready",
            onEnterPressed = function(val)
                if not colorsSec.write then return end
                colorsSec.write.textReadyText = val
                refreshStyle()
            end,
        })
        if readyTextRow.editbox and readyTextRow.editbox.Instructions then
            readyTextRow.editbox.Instructions:Hide()
        end
        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label.
        AnchorRowBadge(readyTextRow, CreateInfoButton(readyTextRow.frame, readyTextRow.frame, "LEFT", "LEFT", 0, 0, {
            "Ready Text",
            {"The word |cff00ff00{status}|r shows when the spell is ready.", 1, 1, 1, true},
        }, tabInfoButtons))
    end

    colorsSec:Finish()
    colorsSec:FinishBracket(colorsRightBracket)
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
    local panelHeading, panelCollapsed = BuildCollapsibleSection(container, "Panel",
        ResolveLensCollapseKey(lens, group, nil, "textappearance_settings"), nil, nil, ROW_SECTION)
    -- Panel-only (sectionId nil). Safe with no entry selected: panel and multi
    -- scope attach no chrome at all.
    local panelSec = BeginLensSection(lens, group, nil)
    panelSec:HeadingChrome(panelHeading)

    if not panelCollapsed then
    -- LEFT column: how one entry is sized and how the entries stack.
    -- RIGHT column: the optional group header with the two rows it owns.
    local panelLeft, panelRight = BeginRowGrid(container)

    -- The columns only exist here, so the section's primary bracket is taken
    -- now rather than at Begin, and the right column takes a second one.
    panelSec:Mark(panelLeft)
    local panelRightBracket = panelSec:Bracket(panelRight)

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
        setting = TEXTMODE_FINDER.panel and TEXTMODE_FINDER.panel.padding,
        min = 0, max = 20, step = 1,
        value = style.textPadding or 4,
        disabled = panelSec.disabled,
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
            setting = TEXTMODE_FINDER.panel and TEXTMODE_FINDER.panel.spacing,
            min = -10, max = 100, step = 0.1,
            value = style.buttonSpacing or ST.BUTTON_SPACING,
            disabled = panelSec.disabled,
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
        setting = TEXTMODE_FINDER.panel and TEXTMODE_FINDER.panel.header,
        value = style.showTextGroupHeader == true,
        disabled = panelSec.disabled,
        onChange = function(val)
            style.showTextGroupHeader = val or false
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if style.showTextGroupHeader then
        AddSliderRow(panelRight, {
            label = "Header Font Size",
            setting = TEXTMODE_FINDER.panel and TEXTMODE_FINDER.panel.headerSize,
            indent = true,
            min = 6, max = 72, step = 1,
            value = style.textHeaderFontSize or 12,
            disabled = panelSec.disabled,
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
            setting = TEXTMODE_FINDER.panel and TEXTMODE_FINDER.panel.headerColor,
            indent = true,
            tbl = style, key = "textHeaderFontColor",
            default = {1, 1, 1, 1}, hasAlpha = true,
            disabled = panelSec.disabled,
            onConfirm = refreshFrame, onChange = refreshFrame,
        })
    end

    panelSec:Finish()
    panelSec:FinishBracket(panelRightBracket)
    end -- not panelCollapsed

    -- ================================================================
    -- Background & Border
    -- ================================================================
    local bgHeading, bgCollapsed = BuildCollapsibleSection(container, "Background & Border",
        ResolveLensCollapseKey(lens, group, "textBackground", "textappearance_bg"), nil, nil, ROW_SECTION)
    local bgSec = BeginLensSection(lens, group, "textBackground")
    bgSec:HeadingChrome(bgHeading)

    if not bgCollapsed then
    -- The backdrop and the border that frames it read together, so they stay
    -- in one column. The right column is deliberately empty, so there is one
    -- column to bracket.
    local bgLeft = BeginRowGrid(container)

    -- The column only exists here, so the section's bracket is taken now
    -- rather than at Begin.
    bgSec:Mark(bgLeft)

    -- Same styleTable + fallbackStyle pair as the two sections above.
    BuildTextBackgroundControls(bgLeft, bgSec.tbl, refreshStyle, {
        row = true,
        fallbackStyle = bgSec.fallbackStyle,
        settings = TEXTMODE_FINDER.background,
    })

    bgSec:Finish()
    end -- not bgCollapsed

    -- Compact Mode used to close this tab. It is packing, not look, so it now
    -- lives on the Layout tab's Arrangement section beside the wrap count (its
    -- copy membership is unchanged - still this tab's appearance scope in
    -- ST.PANEL_COPY_SCOPES).

    -- The dispatch-level gear build pass brackets this builder
    -- (RunAdvancedGearBuildPass, AdvancedSettingsPanel.lua), so the first
    -- text-section gear added here gets the same lifecycle as every other
    -- styling tab's.
end

------------------------------------------------------------------------
-- SETTINGS FINDER CATALOG
------------------------------------------------------------------------

local TEXTMODE_FINDER_SCOPE = { "panel", "entry" }

local function TextModeFinderApplies(context)
    return context and context.group and context.displayMode == "text"
end

local function TextModeFinderEffectiveStyle(context)
    local group = context and context.group
    if not group then return nil end
    local lens = ResolveStyleLens(group)
    return (lens and lens.effective) or group.style
end

local function TextModeFinderCustomizedColors(context)
    if not TextModeFinderApplies(context) or context.scope ~= "entry" then
        return false
    end
    local lens = ResolveStyleLens(context.group)
    local scope = ResolveLensSection(lens, context.group, "textColors")
    return scope == "customized"
end

local function TextModeFinderHasSpacing(context)
    local buttons = context and context.group and context.group.buttons
    return TextModeFinderApplies(context) and buttons and #buttons > 1
end

local function TextModeFinderHeaderEnabled(context)
    local style = context and context.group and context.group.style
    return TextModeFinderApplies(context) and style and style.showTextGroupHeader == true
end

local function TextModeFinderCustomBorder(context)
    local style = TextModeFinderEffectiveStyle(context)
    return TextModeFinderApplies(context) and style
        and ST.GetBorderRenderMode(style, "textBorderRenderMode") ~= ST.BORDER_RENDER_MODE_CRISP
end

if ST._DefineSettingRoute then
    TEXTMODE_FINDER.format = ST._DefineSettingRoute({
        idPrefix = "panel.text.format.editor",
        scope = TEXTMODE_FINDER_SCOPE,
        tab = "format",
        tabLabel = "Format",
        section = "formatEditor",
        sectionLabel = "Format",
        rowScope = "primary",
        applies = TextModeFinderApplies,
    }):Settings({
        string = { label = "Format String", aliases = { "text format", "tokens" } },
    })

    TEXTMODE_FINDER.formatSettings = ST._DefineSettingRoute({
        idPrefix = "panel.text.format.settings",
        scope = TEXTMODE_FINDER_SCOPE,
        tab = "format",
        tabLabel = "Format",
        section = "formatSettings",
        sectionLabel = "Format Settings",
        collapseKeys = { "textformat_settings" },
        rowScope = "primary",
        applies = TextModeFinderApplies,
    }):Settings({
        duration = { label = "Duration Format", aliases = { "timer format" } },
        readyText = { label = "Ready Text", aliases = { "status text" } },
    })

    TEXTMODE_FINDER.font = ST._DefineSettingRoute({
        idPrefix = "panel.text.appearance.font",
        scope = TEXTMODE_FINDER_SCOPE,
        tab = "appearance",
        tabLabel = "Appearance",
        section = "font",
        sectionId = "textFont",
        sectionLabel = "Font",
        collapseKeys = { "textappearance_font" },
        rowScope = "primary",
        applies = TextModeFinderApplies,
    }):Settings({
        fontSize = { label = "Font Size" },
        font = { label = "Font" },
        outline = { label = "Font Outline" },
        alignment = { label = "Alignment" },
        shadow = { label = "Text Shadow" },
    })

    TEXTMODE_FINDER.colors = ST._DefineSettingRoute({
        idPrefix = "panel.text.appearance.colors",
        scope = TEXTMODE_FINDER_SCOPE,
        tab = "appearance",
        tabLabel = "Appearance",
        section = "colors",
        sectionId = "textColors",
        sectionLabel = "Colors",
        collapseKeys = { "textappearance_colors" },
        rowScope = "primary",
        applies = TextModeFinderApplies,
    }):Settings({
        text = { label = "Text Color" },
        cooldown = { label = "Cooldown Color" },
        ready = { label = "Ready Color" },
        aura = { label = "Aura Color" },
        custom = { label = "Custom Color" },
        readyText = { label = "Ready Text", aliases = { "status text" }, applies = TextModeFinderCustomizedColors },
    })

    TEXTMODE_FINDER.panel = ST._DefineSettingRoute({
        idPrefix = "panel.text.appearance.panel",
        scope = TEXTMODE_FINDER_SCOPE,
        tab = "appearance",
        tabLabel = "Appearance",
        section = "panel",
        sectionLabel = "Panel",
        collapseKeys = { "textappearance_settings" },
        rowScope = "primary",
        applies = TextModeFinderApplies,
    }):Settings({
        padding = { label = "Padding" },
        spacing = { label = "Entry Spacing", applies = TextModeFinderHasSpacing },
        header = { label = "Show Group Header" },
        headerSize = { label = "Header Font Size", applies = TextModeFinderHeaderEnabled },
        headerColor = { label = "Header Color", applies = TextModeFinderHeaderEnabled },
    })

    TEXTMODE_FINDER.background = ST._DefineSettingRoute({
        idPrefix = "panel.text.appearance.background",
        scope = TEXTMODE_FINDER_SCOPE,
        tab = "appearance",
        tabLabel = "Appearance",
        section = "background",
        sectionId = "textBackground",
        sectionLabel = "Background & Border",
        collapseKeys = { "textappearance_bg" },
        rowScope = "primary",
        applies = TextModeFinderApplies,
    }):Settings({
        background = { label = "Background Color" },
        thickness = { label = "Border Thickness" },
        size = { label = "Border Size", applies = TextModeFinderCustomBorder },
        color = { label = "Border Color" },
    })
end

-- Exports
ST._BuildTextAppearanceTab = BuildTextAppearanceTab
ST._BuildTextFormatTab = BuildTextFormatTab

-- Lifecycle hooks for the config's ONE format editor. Called through ST at
-- fire time rather than captured at load, so file order does not matter:
--   Release - every seam that releases or rebuilds the tab's container, or
--             takes the settings surface off it (GroupSettingsHost's tab
--             callback and refresh, the entry tab group's callback, the
--             config's OnHide).
--   Flush   - seams that do not take the container away but must not leave a
--             write pending (the config's OnHide while collapsing).
ST._ReleaseTextFormatTabEditor = ReleaseTextFormatTabEditor
ST._FlushTextFormatTabCommit = FlushTextFormatTabCommit
