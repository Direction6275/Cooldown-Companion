local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders
local AddBorderRenderModeDropdown = ST._AddBorderRenderModeDropdown

-- Imports from RowWidgets.lua (the row grammar). Every builder in this file
-- draws from these: the pre-redesign stock shapes are gone, so there is only
-- one shape left per section.
--
-- opts.rightColumn is the second half of the grid the CALLER opened: a builder
-- with a natural two-column split writes its "what it looks like / where it
-- lands" rows there and its "what it is drawn with" rows into `container`.
-- Builders that ignore it simply fill the left column, which is what the
-- fill-LEFT-first rule asks for. The styling tabs pass it wherever a section
-- opens its own two-column grid (Text mode's Font and Colors sections, the
-- rotation assistant's keybind block, the bar aura indicator's effects grid).
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddEditBoxRow = ST._AddEditBoxRow
local AddColorRow = ST._AddColorRow
local AddLabelRow = ST._AddLabelRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid
local CleanRecycledEntry = ST._CleanRecycledEntry

-- Dropdown items past ~16 characters need a menu wider than the 140px control
-- column can size ("Color the Whole Text", the override section labels).
local WIDE_PULLOUT_WIDTH = 300

-- Module-level aliases
local tabInfoButtons = CS.tabInfoButtons

------------------------------------------------------------------------
-- TRACKED-AURA CANDIDATE LISTS
------------------------------------------------------------------------
-- Both aura surfaces (panel entries and custom bars) store the same shape:
-- a CSV of spell IDs on `auraSpellID`, with the Blizzard polarity rule that
-- one entry may never mix buffs and debuffs. The rules and their messages
-- live here once so the two surfaces cannot answer the same action
-- differently. Callers supply their own derived unit and a post-change hook
-- (each surface normalizes its own entry shape afterwards).

local function ClassifyAuraSpellUnit(spellID)
    if not (spellID and C_Spell.DoesSpellExist(spellID)) then return nil end
    return C_Spell.IsSpellHarmful(spellID) and "target" or "player"
end

local function GetAuraCandidateList(config)
    local list = {}
    local raw = config and config.auraSpellID and tostring(config.auraSpellID) or nil
    if raw then
        for id in raw:gmatch("%d+") do
            list[#list + 1] = tonumber(id)
        end
    end
    return list
end

local function SetAuraCandidateList(config, list, onChanged)
    if #list > 0 then
        local parts = {}
        for i, id in ipairs(list) do parts[i] = tostring(id) end
        config.auraSpellID = table.concat(parts, ",")
    else
        config.auraSpellID = nil
    end
    if onChanged then onChanged(config) end
end

-- currentUnit is the surface's own derived tracking unit. Returns true when
-- the list actually changed.
local function TryAddAuraCandidate(config, input, currentUnit, onChanged)
    input = input and input:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if input == "" then return false end
    local spellID = tonumber(input)
    if not spellID then
        -- Typed names must land the same ID an autocomplete pick would: the
        -- tracked slice re-identifies CDM rows to the applied-aura spellID,
        -- while GetSpellInfo resolves a name to the castable spell, whose ID
        -- never matches an aura applied under a linked spell (Rake 1822 vs
        -- bleed 155722). ST._RBP is read at call time: ResourceBarPanels-
        -- Helpers loads after this file.
        local RBP = ST._RBP
        if RBP and RBP.ResolveTrackedAuraSpellIDFromText then
            spellID = RBP.ResolveTrackedAuraSpellIDFromText(input)
        else
            local info = C_Spell.GetSpellInfo(input)
            spellID = info and info.spellID
        end
    end
    if not (spellID and C_Spell.DoesSpellExist(spellID)) then
        CooldownCompanion:Print("Aura not found: " .. input .. ". Try the spell ID.")
        return false
    end
    local list = GetAuraCandidateList(config)
    for _, existing in ipairs(list) do
        if existing == spellID then
            return false
        end
    end
    local newUnit = ClassifyAuraSpellUnit(spellID)
    if newUnit and currentUnit and newUnit ~= currentUnit then
        CooldownCompanion:Print("Buffs and debuffs can't be tracked by the same entry. Debuffs are tracked on your target, buffs on you.")
        return false
    end
    list[#list + 1] = spellID
    SetAuraCandidateList(config, list, onChanged)
    return true
end

-- Removing the last listed aura is always allowed: the entry's own aura is
-- implicit, so an empty list just returns to the default.
local function RemoveAuraCandidate(config, spellID, onChanged)
    local list = GetAuraCandidateList(config)
    for i, existing in ipairs(list) do
        if existing == spellID then
            table.remove(list, i)
            SetAuraCandidateList(config, list, onChanged)
            return true
        end
    end
    return false
end

-- Row grammar only (RowWidgets.lua). A tracked aura presents an ITEM, not a
-- setting, so it draws as a CDC-LabelRow: the spell's icon inlined into the
-- label text (the row's label is a FontString, so the icon rides an inline
-- texture escape) and a Remove link owned by the row's control column. The
-- pre-redesign 22px Flow row broke the 30px rhythm inside a grid column and had
-- no call sites left after the conversion packets.
local function AddAuraCandidateRow(container, spellID, onRemove, opts)
    local info = C_Spell.GetSpellInfo(spellID)
    local name = info and info.name or ("Spell " .. spellID)
    local icon = C_Spell.GetSpellTexture(spellID) or 134400

    local row = AddLabelRow(container, {
        label = ("|T%d:16:16:0:0|t %s |cff999999(%d)|r"):format(icon, name, spellID),
        indent = true,
    })

    -- Right-justified so the word lands on the control column's right edge
    -- like every other row's control. SetJustifyH is public API and the
    -- stock Label resets it to LEFT in OnAcquire, so the pool stays clean.
    local removeLabel = AceGUI:Create("InteractiveLabel")
    -- The shared InteractiveLabel pool also serves the Navigator, whose rows
    -- hang plain-child badges off the label FRAME; nothing hides those on
    -- release, so a reacquired frame arrives wearing its previous tenant's
    -- badges. Same clean-on-acquire call every Navigator site makes.
    CleanRecycledEntry(removeLabel)
    removeLabel:SetText("|cffff5555Remove|r")
    removeLabel:SetWidth(60)
    removeLabel:SetJustifyH("RIGHT")
    removeLabel:SetCallback("OnClick", function()
        onRemove(spellID)
    end)
    row:SetControlWidget(removeLabel)
    return row
end

-- The stack-bar status line. A nil max means one of two very different
-- things, and only the combat check tells them apart: in combat the game
-- returns the stack maximum as a secret the addon must discard, so claiming
-- the aura doesn't stack would be a lie the tab tells whenever it is
-- rebuilt mid-fight.
-- The three texts live here alone so every surface that reports the stack
-- maximum words them identically.
local function GetAuraStackMaxStatusText(maxStacks)
    if maxStacks then
        return "|cffffd100Stack bar:|r full at " .. maxStacks .. " stacks"
    elseif InCombatLockdown() then
        return "|cffff9955The stack maximum can't be read in combat; it resolves when you leave combat.|r"
    else
        return "|cffff9955This aura doesn't stack; the bar will show duration.|r"
    end
end

-- Row grammar only (RowWidgets.lua). The pre-redesign shape was a wrapped Label
-- - 1-3 lines of unpredictable height, which between two rows shoves everything
-- below it out of rhythm; as a label row it occupies exactly one row slot
-- whether it is there or not. It always indents, because it is always a child
-- of the stacks toggle it explains, and row labels never wrap, so the sentence
-- also says its piece on hover.
local function AddAuraStackMaxStatusLabel(container, maxStacks, opts)
    local statusText = GetAuraStackMaxStatusText(maxStacks)

    return AddLabelRow(container, {
        label = statusText,
        indent = true,
        tooltip = { { statusText, 1, 1, 1, true } },
    })
end

------------------------------------------------------------------------
-- REUSABLE SECTION BUILDER FUNCTIONS
------------------------------------------------------------------------
-- Each builder takes (container, styleTable, refreshCallback) and adds
-- AceGUI widgets to the container, reading/writing values from styleTable.

local KEYBIND_CUSTOM_LABEL = "Show Keybind/Custom Text"
local KEYBIND_CUSTOM_TOOLTIP = {
    "Show Keybind/Custom Text",
    {"Shows detected keybind text on icon buttons by default.", 1, 1, 1, true},
    " ",
    {"When enabled for a button, that button's settings can also provide custom text to replace the detected bind until cleared.", 1, 1, 1, true},
}
local function IsAdvancedSettingsPanelContainer(container)
    return container and container._isAdvancedSettingsPanel == true
end

local function RefreshStructuralControls(container)
    if IsAdvancedSettingsPanelContainer(container) and CS.RefreshAdvancedSettingsPanel then
        CS.RefreshAdvancedSettingsPanel()
    elseif CooldownCompanion.RefreshConfigPanel then
        CooldownCompanion:RefreshConfigPanel()
    end
end

-- Row grammar only (RowWidgets.lua): opts.indent makes it a child row and
-- opts.pulloutWidth widens its menu. No default pullout width: the longest
-- option ("1:30 / 45.0 / 8.7") sizes fine against the 140px control column.
-- The pre-redesign full-width stock Dropdown had no call sites left after the
-- conversion packets.
local function AddDurationFormatDropdown(container, settings, refreshCallback, opts)
    if not (container and settings and CooldownCompanion.GetDurationFormatOptions) then
        return nil
    end

    local formatOptions, formatOrder = CooldownCompanion:GetDurationFormatOptions()

    return AddDropdownRow(container, {
        label = "Duration Format",
        indent = opts and opts.indent,
        pulloutWidth = opts and opts.pulloutWidth,
        list = formatOptions,
        order = formatOrder,
        value = CooldownCompanion.GetDurationFormat(settings),
        onChange = function(val)
            settings.durationFormat = CooldownCompanion.NormalizeDurationFormat(val)
            settings.decimalTimers = nil
            if refreshCallback then
                refreshCallback()
            end
        end,
    })
end

-- Pandemic marker controls (tracker C9), shared between the group-tab
-- advanced panel and the per-button override builder. The marker rides the
-- aura duration text, so it lives with these options. rebuildCallback
-- re-renders the surrounding panel when a structural choice changes.
local PANDEMIC_COLOR_MODES = {
    off = "No Color",
    marker = "Color the Marker",
    whole = "Color the Whole Text",
}
local PANDEMIC_COLOR_MODE_ORDER = { "off", "marker", "whole" }

local PANDEMIC_MARKER_TOOLTIP_LINES = {
    "Pandemic Marker",
    {"Marks the duration text for the last 30% of an aura, where recasting adds to the remaining time instead of wasting it.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"It rides that text. With Aura Duration Text off, nothing shows.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"On by default for debuffs on your target.", 1, 1, 1, true},
}

-- Row grammar only (RowWidgets.lua). Three shapes, one builder:
--   opts.enableOnly   - just the toggle, returned so the caller can chain a
--                       gear and the section's scope chrome off it (the
--                       Indicators tab's Pandemic section).
--   opts.childrenOnly - just what that gear opens, so the rows fill the panel
--                       instead of indenting under a toggle that is elsewhere.
--   neither           - both, with the three styling rows as children of the
--                       toggle. No caller asks for this shape today.
-- Labels deliberately say "Marker": these rows share a section with the
-- pandemic EFFECT's own color, and three rows reading "Pandemic Color" in one
-- column would be unreadable.
local function AddPandemicMarkerControls(container, styleTable, refreshCallback, rebuildCallback, opts)
    opts = opts or {}
    local enableRow
    if not opts.childrenOnly then
        enableRow = AddCheckboxRow(container, {
            label = "Pandemic Marker",
            value = styleTable.pandemicMarkerEnabled ~= false,
            indent = opts.indent,
            onChange = function(val)
                styleTable.pandemicMarkerEnabled = val
                refreshCallback()
                rebuildCallback()
            end,
        })
        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label.
        AnchorRowBadge(enableRow, CreateInfoButton(enableRow.frame, enableRow.frame, "LEFT", "LEFT", 0, 0,
            PANDEMIC_MARKER_TOOLTIP_LINES, enableRow))
    end

    if opts.enableOnly or styleTable.pandemicMarkerEnabled == false then
        return enableRow
    end

    local childIndent = not opts.childrenOnly

    AddEditBoxRow(container, {
        label = "Marker Text",
        indent = childIndent,
        value = styleTable.pandemicMarkerText or "!!",
        onEnterPressed = function(text, widget)
            text = tostring(text or ""):gsub("[|%%]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 8)
            styleTable.pandemicMarkerText = text
            widget:SetText(text)
            refreshCallback()
        end,
    })

    AddDropdownRow(container, {
        label = "Marker Coloring",
        indent = childIndent,
        pulloutWidth = WIDE_PULLOUT_WIDTH,
        list = PANDEMIC_COLOR_MODES,
        order = PANDEMIC_COLOR_MODE_ORDER,
        value = styleTable.pandemicMarkerColorMode or "marker",
        onChange = function(val)
            styleTable.pandemicMarkerColorMode = val
            refreshCallback()
            rebuildCallback()
        end,
    })

    if (styleTable.pandemicMarkerColorMode or "marker") ~= "off" then
        -- deferCommit is deliberately absent, matching the stock color picker
        -- this row replaced.
        AddColorRow(container, {
            label = "Marker Color",
            indent = childIndent,
            tbl = styleTable,
            key = "pandemicMarkerColor",
            default = {1, 0.5, 0, 1},
            onConfirm = refreshCallback,
            onChange = refreshCallback,
        })
    end

    return enableRow
end

-- Row grammar only: LEFT column (the container the caller hands over) the
-- toggle and the font trio, RIGHT column (opts.rightColumn) the color, anchor
-- and offsets. opts.label / opts.tooltip let the rotation assistant name this
-- "Show Keybind Text" - it has no custom-text form.
local function BuildKeybindTextControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local label = opts.label or KEYBIND_CUSTOM_LABEL
    local tooltip = opts.tooltip or KEYBIND_CUSTOM_TOOLTIP
    local right = opts.rightColumn or container

    local function ApplyShowKeybindText(val)
        styleTable.showKeybindText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end

    local kbRow = AddCheckboxRow(container, {
        label = label,
        value = styleTable.showKeybindText or false,
        indent = opts.indent,
        onChange = ApplyShowKeybindText,
    })
    -- Anchor args are a placeholder - AnchorRowBadge re-points the button
    -- onto the end of the row's label.
    AnchorRowBadge(kbRow, CreateInfoButton(kbRow.frame, kbRow.frame, "LEFT", "LEFT", 0, 0,
        tooltip, kbRow))

    if styleTable.showKeybindText then
        AddFontControls(container, styleTable, "keybind", {size = 10, sizeMin = 6, sizeMax = 24},
            refreshCallback, { row = true, indent = true })
        -- deferCommit is deliberately absent, matching the stock color picker
        -- this row replaced.
        AddColorRow(right, {
            label = "Font Color",
            tbl = styleTable,
            key = "keybindFontColor",
            default = {1, 1, 1, 1},
            hasAlpha = true,
            onConfirm = refreshCallback,
            onChange = refreshCallback,
        })
        AddAnchorDropdown(right, styleTable, "keybindAnchor", "TOPRIGHT", refreshCallback,
            nil, { row = true })
        AddOffsetSliders(right, styleTable, "keybindXOffset", "keybindYOffset", {x = -2, y = -2},
            refreshCallback, { row = true })
    end
end

-- Row grammar only: the render-mode dropdown reuses
-- AddBorderRenderModeDropdown's own row mode, the conditional thickness slider
-- is its child row, and the color is a color row. Three rows in one column -
-- splitting a parent from its children would orphan the indent.
local function BuildBorderControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local previewRefresh = opts.previewRefresh or ST._RefreshSelectedButtonsPreview

    local function ApplyRenderModeChanged()
        refreshCallback()
        RefreshStructuralControls(container)
    end
    local renderMode = AddBorderRenderModeDropdown(container, styleTable, "borderRenderMode",
        ApplyRenderModeChanged, nil, { row = true, indent = opts.indent })
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        AddSliderRow(container, {
            label = "Border Size",
            indent = true,
            min = 0, max = 5, step = 0.1,
            value = styleTable.borderSize or ST.DEFAULT_BORDER_SIZE,
            disabled = borderThicknessLocked,
            onChange = function(val)
                if borderThicknessLocked then return end
                ST._PreviewScalarSetting(styleTable, "borderSize", val, previewRefresh)
            end,
            onRelease = function(val)
                if borderThicknessLocked then return end
                styleTable.borderSize = val
                refreshCallback()
            end,
        })
    end

    -- deferCommit is deliberately absent, matching the stock color picker this
    -- row replaced.
    AddColorRow(container, {
        label = "Border Color",
        indent = opts.indent,
        tbl = styleTable,
        key = "borderColor",
        default = {0, 0, 0, 1},
        hasAlpha = true,
        onConfirm = refreshCallback,
        onChange = refreshCallback,
    })
end

-- Row grammar only: one slider row. WeakAuras-style zoom: crops the icon
-- artwork toward its center without changing the frame's size.
-- Mirror-first when opts.previewRefresh is given: drag ticks save the value
-- and repaint only that preview, and refreshCallback restyles the live
-- surface once on release (the slider's edit box fires the release path on
-- Enter too, so typed values also apply live).
local function BuildIconZoomControls(container, styleTable, refreshCallback, opts)
    -- Masque skins own the icon's texture coordinates, so the row locks
    -- whenever the panel is skinned (mirrors the Square Icons row).
    local locked = opts and (opts.disabled or opts.masqueEnabled) or false
    local previewRefresh = (opts and opts.previewRefresh) or ST._RefreshSelectedButtonsPreview
    return AddSliderRow(container, {
        label = "Icon Zoom",
        indent = opts and opts.indent,
        disabled = locked,
        min = 0, max = 50, step = 1,
        value = styleTable.iconZoom or 0,
        onChange = function(val)
            if locked then return end
            ST._PreviewScalarSetting(styleTable, "iconZoom", val, previewRefresh)
        end,
        onRelease = function(val)
            if locked then return end
            styleTable.iconZoom = val
            refreshCallback()
        end,
    })
end

-- Row grammar only (RowWidgets.lua). The icons and bars styling tabs draw the
-- SAME Icon Tint block over the same keys - the tint pipeline is shared
-- (ButtonFrame/Tracking.lua serves both display modes) - so the rows live here
-- once and each tab keeps its own heading, info badge, gates and brackets.
--
-- Unlike the (container, styleTable, refreshCallback) builders above, this one
-- takes BOTH grid columns and the tab's already-begun iconTint lens section:
-- the block's natural split is always-on colors LEFT, conditional state tints
-- RIGHT, and every row binds sec.tbl / takes sec.disabled / guards its commit
-- on sec.write. Brackets stay with the caller, which owns both columns.
--
-- opts.mode          "icons" | "bars". Bars omits the Background Color ROW (the
--                    bar's icon square never renders a backdrop - Bar
--                    Background Color owns that) but the reset still writes the
--                    key: it belongs to this section, and a value left pinned
--                    would surface as a stale icon backdrop if the panel ever
--                    converts to icons.
-- opts.hasAuraEntry  the caller's ST._GroupHasAuraTrackingEntry(group) result.
--                    The aura tint applies to the slot-kit aura layer (consumed
--                    at bind time by AuraDisplay.StyleSlotKit), so it is only
--                    offered where an aura display exists.
-- opts.hasCooldownState  false on an Aura Panel, whose entries have no spell
--                    cooldown to tint. Anything but an explicit false keeps the
--                    cooldown tint pair, so existing callers are unchanged.
-- opts.refresh       the tab's style-only refresh, run on every value change.
local function BuildIconTintControls(leftColumn, rightColumn, sec, opts)
    opts = opts or {}
    local refresh = opts.refresh
    -- A color row binds its picker to one table for both reading and writing,
    -- so it gets the write table where the section has one and the lens'
    -- detached snapshot where it does not.
    local tintTbl = sec.tbl

    AddColorRow(leftColumn, {
        label = "Base Icon Color",
        tbl = tintTbl, key = "iconTintColor",
        default = {1, 1, 1, 1}, hasAlpha = true,
        disabled = sec.disabled,
        onConfirm = refresh, onChange = refresh,
    })

    if opts.mode == "icons" then
        AddColorRow(leftColumn, {
            label = "Background Color",
            tbl = tintTbl, key = "backgroundColor",
            default = {0, 0, 0, 0.5}, hasAlpha = true,
            disabled = sec.disabled,
            onConfirm = refresh, onChange = refresh,
        })
    end

    -- opts.hasCooldownState is false on an Aura Panel, where nothing has a spell
    -- cooldown to tint and AuraDisplay never reads either key.
    if opts.hasCooldownState ~= false then
        AddCheckboxRow(leftColumn, {
            label = "Use Separate Cooldown Tint",
            value = sec.read.iconCooldownTintEnabled or false,
            disabled = sec.disabled,
            onChange = function(val)
                if not sec.write then return end
                sec.write.iconCooldownTintEnabled = val
                refresh()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if sec.read.iconCooldownTintEnabled then
            AddColorRow(leftColumn, {
                label = "Cooldown Icon Color",
                indent = true,
                tbl = tintTbl, key = "iconCooldownTintColor",
                default = {1, 0, 0.102, 1}, hasAlpha = true,
                disabled = sec.disabled,
                onConfirm = refresh, onChange = refresh,
            })
        end
    end

    if opts.hasAuraEntry then
        AddCheckboxRow(rightColumn, {
            label = "Use Separate Aura Tint",
            value = sec.read.iconAuraTintEnabled or false,
            disabled = sec.disabled,
            onChange = function(val)
                if not sec.write then return end
                sec.write.iconAuraTintEnabled = val
                refresh()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if sec.read.iconAuraTintEnabled then
            AddColorRow(rightColumn, {
                label = "Aura Active Icon Color",
                indent = true,
                tbl = tintTbl, key = "iconAuraTintColor",
                default = {0, 0.925, 1, 1}, hasAlpha = true,
                disabled = sec.disabled,
                onConfirm = refresh, onChange = refresh,
            })
        end
    end

    -- The right column runs 2-3 rows short of the left one, so the section
    -- action fills its empty tail instead of hanging off the bottom of the
    -- grid. No wrapper needed: SetAutoWidth leaves widget.width nil, so the
    -- column's List layout neither stretches nor right-anchors it and it sits
    -- flush left under the last row.
    --
    -- Not built at all while the section is inert: a section with nowhere to
    -- write has no defaults to restore, and a greyed-out button under a
    -- read-only section is one more thing to explain.
    if sec.write then
        local resetTintBtn = AceGUI:Create("Button")
        resetTintBtn:SetText("Reset Colors to Default")
        resetTintBtn:SetAutoWidth(true)
        resetTintBtn:SetCallback("OnClick", function()
            sec.write.iconTintColor = {1, 1, 1, 1}
            sec.write.iconCooldownTintColor = {1, 0, 0.102, 1}
            sec.write.iconAuraTintColor = {0, 0.925, 1, 1}
            sec.write.backgroundColor = {0, 0, 0, 0.5}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        rightColumn:AddChild(resetTintBtn)
    end
end

-- Row grammar only: one checkbox row.
local function BuildDesaturationControls(container, styleTable, refreshCallback, opts)
    return AddCheckboxRow(container, {
        label = "Show Desaturate On Cooldown",
        value = styleTable.desaturateOnCooldown or false,
        indent = opts and opts.indent,
        onChange = function(val)
            styleTable.desaturateOnCooldown = val
            refreshCallback()
        end,
    })
end

-- Tooltip position + combat hide (tracker D-C1). Group-level only (owner
-- ruling 2026-07-24) and applied to both the normal button tooltip and the
-- aura display's tooltip. Lives in the Show Tooltips advanced panel.
local TOOLTIP_ANCHOR_LIST = {
    default = "Default",
    above = "Above",
    below = "Below",
    left = "Left",
    right = "Right",
    cursor = "At Cursor",
}
local TOOLTIP_ANCHOR_ORDER = { "default", "above", "below", "left", "right", "cursor" }

-- Row grammar only (RowWidgets.lua), single rail: this is the interior of the
-- Show Tooltips advanced panel and has no other call site. A panel is one
-- narrow column (AdvancedSettingsPanel.lua), so both rows go straight onto
-- `container`.
local function BuildTooltipBehaviorControls(container, styleTable, refreshCallback)
    local drop = AddDropdownRow(container, {
        label = "Tooltip Position",
        list = TOOLTIP_ANCHOR_LIST,
        order = TOOLTIP_ANCHOR_ORDER,
        value = styleTable.tooltipAnchor or "default",
        onChange = function(val)
            styleTable.tooltipAnchor = val
            refreshCallback()
        end,
    })

    local combatCb = AddCheckboxRow(container, {
        label = "Hide Tooltips in Combat",
        value = styleTable.tooltipHideInCombat == true,
        onChange = function(val)
            styleTable.tooltipHideInCombat = val
            refreshCallback()
        end,
    })

    return drop, combatCb
end

-- opts.advanced: attach the gear that opens Tooltip Position / Hide in Combat
-- (group-level tabs only — those keys are group style, with no per-entry
-- override section, so the override editor calls this without it).
--
-- Row grammar only: the toggle is a CDC-CheckBoxRow whose gear chains off the
-- label.
local function BuildShowTooltipsControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    local cb = AddCheckboxRow(container, {
        label = "Show Tooltips",
        value = styleTable.showTooltips == true,
        indent = opts.indent,
        onChange = function(val)
            styleTable.showTooltips = val
            refreshCallback()
        end,
    })

    if not opts.advanced then
        return cb
    end

    local _, advBtn = AddAdvancedToggle(cb, "tooltipBehavior",
        opts.infoButtons or tabInfoButtons,
        styleTable.showTooltips == true, {
            title = "Tooltip Advanced",
            build = function(panel)
                BuildTooltipBehaviorControls(panel, styleTable, refreshCallback)
            end,
        })

    return cb, advBtn
end

-- Row grammar only: one checkbox row.
local function BuildShowOutOfRangeControls(container, styleTable, refreshCallback, opts)
    return AddCheckboxRow(container, {
        label = "Show Out of Range",
        value = styleTable.showOutOfRange or false,
        indent = opts and opts.indent,
        onChange = function(val)
            styleTable.showOutOfRange = val
            refreshCallback()
        end,
    })
end

local ALLOW_PINGS_TOOLTIP_LINES = {
    "Allow Pings",
    {"Ping an entry to your group like a Cooldown Manager icon: hold the ping keybind and click it.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"The ping shows the spell or item and whether it is ready.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Works with tooltips off. Entries added as auras cannot be pinged.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Bars ping from the bar icon.", 1, 1, 1, true},
}

-- Row grammar only: one checkbox row with a "?" badge.
local function BuildAllowPingsControls(container, styleTable, refreshCallback, opts)
    local cb = AddCheckboxRow(container, {
        label = "Allow Pings",
        value = styleTable.allowPings == true,
        indent = opts and opts.indent,
        onChange = function(val)
            styleTable.allowPings = val
            refreshCallback()
        end,
    })
    AnchorRowBadge(cb, CreateInfoButton(cb.frame, cb.frame, "LEFT", "LEFT", 0, 0,
        ALLOW_PINGS_TOOLTIP_LINES, cb))
    return cb
end

-- Row grammar only: one checkbox row.
local function BuildShowGCDSwipeControls(container, styleTable, refreshCallback, opts)
    return AddCheckboxRow(container, {
        label = "Show GCD Swipe",
        value = styleTable.showGCDSwipe == true,
        indent = opts and opts.indent,
        onChange = function(val)
            styleTable.showGCDSwipe = val
            refreshCallback()
        end,
    })
end

local function IsIconFillTimerEnabled(styleTable, opts)
    if opts and opts.masqueEnabled == true then
        return false
    end
    if styleTable and styleTable.iconFillEnabled ~= nil then
        return styleTable.iconFillEnabled == true
    end
    return opts and opts.fallbackStyle and opts.fallbackStyle.iconFillEnabled == true
end

local BuildIconFillTimerAdvancedControls

-- Row grammar only. The three follow-on toggles keep the indent rule (children
-- of the first one in override mode, siblings otherwise); the two conditional
-- controls always indent under the toggle that reveals them. One parent chain,
-- so it stays in a single column.
local function BuildCooldownSwipeControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local disabledByIconFill = IsIconFillTimerEnabled(styleTable, opts)
    local previewRefresh = opts.previewRefresh or ST._RefreshSelectedButtonsPreview

    -- The writes both shapes perform, hoisted so neither can wire a different
    -- store than the other. RefreshStructuralControls is on exactly the calls
    -- that change which further controls exist.
    local function ApplyShowSwipe(val)
        if disabledByIconFill then return end
        styleTable.showCooldownSwipe = val
        refreshCallback()
    end
    local function ApplyReverse(val)
        if disabledByIconFill then return end
        styleTable.cooldownSwipeReverse = val
        refreshCallback()
    end
    local function ApplyShowFill(val)
        if disabledByIconFill then return end
        styleTable.showCooldownSwipeFill = val
        refreshCallback()
        RefreshStructuralControls(container)
    end
    local function ApplyFillAlpha(val)
        if disabledByIconFill then return end
        ST._PreviewScalarSetting(styleTable, "cooldownSwipeAlpha", val, previewRefresh)
    end
    local function ApplyShowEdge(val)
        if disabledByIconFill then return end
        styleTable.cooldownSwipeEdgeEnabled = val
        refreshCallback()
        RefreshStructuralControls(container)
    end

    local childIndent = opts.indent

    local swipeRow = AddCheckboxRow(container, {
        label = "Show Cooldown Swipe",
        value = styleTable.showCooldownSwipe ~= false,
        indent = opts.indent,
        disabled = disabledByIconFill,
        onChange = ApplyShowSwipe,
    })

    AddCheckboxRow(container, {
        label = "Reverse Swipe",
        value = styleTable.cooldownSwipeReverse or false,
        indent = childIndent,
        disabled = disabledByIconFill,
        onChange = ApplyReverse,
    })

    AddCheckboxRow(container, {
        label = "Show Swipe Fill",
        value = styleTable.showCooldownSwipeFill ~= false,
        indent = childIndent,
        disabled = disabledByIconFill,
        onChange = ApplyShowFill,
    })

    if styleTable.showCooldownSwipeFill ~= false then
        -- Row grammar has no percent readout, so this reads 0 - 1 rather
        -- than the pre-redesign slider's 0% - 100%; same store, same range.
        -- The resource-bar opacity rows already read that way.
        AddSliderRow(container, {
            label = "Swipe Fill Opacity",
            indent = true,
            min = 0, max = 1, step = 0.05,
            value = styleTable.cooldownSwipeAlpha or 0.8,
            disabled = disabledByIconFill,
            onChange = ApplyFillAlpha,
            onRelease = function(val)
                if disabledByIconFill then return end
                styleTable.cooldownSwipeAlpha = val
                refreshCallback()
            end,
        })
    end

    AddCheckboxRow(container, {
        label = "Show Swipe Edge",
        value = styleTable.cooldownSwipeEdgeEnabled == true,
        indent = childIndent,
        disabled = disabledByIconFill,
        onChange = ApplyShowEdge,
    })

    if styleTable.cooldownSwipeEdgeEnabled == true then
        -- deferCommit is deliberately absent, matching the stock color picker
        -- this row replaced.
        AddColorRow(container, {
            label = "Swipe Edge Color",
            indent = true,
            tbl = styleTable,
            key = "cooldownSwipeEdgeColor",
            default = {1, 1, 1, 1},
            hasAlpha = true,
            disabled = disabledByIconFill,
            onConfirm = refreshCallback,
            onChange = refreshCallback,
        })
    end

    return swipeRow
end

-- Aura duration swipe (12.1 compositing): the swipe is a slot-kit region that
-- Blizzard drives directly; these keys are consumed at bind time by
-- AuraDisplay.StyleSlotKit. Unlike the cooldown swipe there is no icon-fill
-- coupling: the fill can no longer render aura durations, so disabling the
-- swipe under it would leave aura entries with no timer at all.
local AURA_BLIZZARD_SWIPE_TOOLTIP = {
    "Blizzard Style Aura Swipe",
    {"Uses Blizzard's fixed bright aura swipe style while Aura Duration Swipe is enabled. The other swipe settings in this panel do not affect it.", 1, 1, 1, true},
}

-- Row grammar only (RowWidgets.lua). This whole block is one parent chain
-- hanging off Show Aura Duration Swipe, so it stays in the column that toggle
-- sits in - splitting a chain across the grid would orphan the children from
-- the row that gates them. Same rule the cooldown swipe follows.
local function BuildAuraDurationSwipeAdvancedControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local blizzardStyleActive = styleTable.auraUseBlizzardSwipe == true
    local childIndent = opts.indent
    local previewRefresh = opts.previewRefresh or ST._RefreshSelectedButtonsPreview

    local blizzardRow = AddCheckboxRow(container, {
        label = "Blizzard Style Aura Swipe",
        value = blizzardStyleActive,
        indent = childIndent,
        onChange = function(val)
            styleTable.auraUseBlizzardSwipe = val == true
            refreshCallback()
            RefreshStructuralControls(container)
        end,
    })
    -- Anchor args are a placeholder - AnchorRowBadge re-points the button
    -- onto the end of the row's label.
    AnchorRowBadge(blizzardRow, CreateInfoButton(blizzardRow.frame, blizzardRow.frame, "LEFT", "LEFT", 0, 0,
        AURA_BLIZZARD_SWIPE_TOOLTIP, blizzardRow))

    AddCheckboxRow(container, {
        label = "Reverse Swipe",
        value = styleTable.auraDurationSwipeReverse ~= false,
        indent = childIndent,
        disabled = blizzardStyleActive,
        onChange = function(val)
            if blizzardStyleActive then return end
            styleTable.auraDurationSwipeReverse = val
            refreshCallback()
        end,
    })

    AddCheckboxRow(container, {
        label = "Show Swipe Fill",
        value = styleTable.showAuraDurationSwipeFill ~= false,
        indent = childIndent,
        disabled = blizzardStyleActive,
        onChange = function(val)
            if blizzardStyleActive then return end
            styleTable.showAuraDurationSwipeFill = val
            refreshCallback()
            RefreshStructuralControls(container)
        end,
    })

    if styleTable.showAuraDurationSwipeFill ~= false then
        -- Row grammar has no percent readout, so this reads 0 - 1 rather than
        -- the pre-redesign slider's 0% - 100%; same store, same range.
        AddSliderRow(container, {
            label = "Swipe Fill Opacity",
            indent = true,
            min = 0, max = 1, step = 0.05,
            value = styleTable.auraDurationSwipeAlpha or 0.8,
            disabled = blizzardStyleActive,
            onChange = function(val)
                if blizzardStyleActive then return end
                ST._PreviewScalarSetting(styleTable, "auraDurationSwipeAlpha", val, previewRefresh)
            end,
            onRelease = function(val)
                if blizzardStyleActive then return end
                styleTable.auraDurationSwipeAlpha = val
                refreshCallback()
            end,
        })
    end

    AddCheckboxRow(container, {
        label = "Show Swipe Edge",
        value = styleTable.auraDurationSwipeEdgeEnabled == true,
        indent = childIndent,
        disabled = blizzardStyleActive,
        onChange = function(val)
            if blizzardStyleActive then return end
            styleTable.auraDurationSwipeEdgeEnabled = val
            refreshCallback()
            RefreshStructuralControls(container)
        end,
    })

    if styleTable.auraDurationSwipeEdgeEnabled == true then
        -- deferCommit is deliberately absent, matching the stock color picker
        -- this row replaced.
        AddColorRow(container, {
            label = "Swipe Edge Color",
            indent = true,
            tbl = styleTable,
            key = "auraDurationSwipeEdgeColor",
            default = {1, 1, 1, 1},
            hasAlpha = true,
            disabled = blizzardStyleActive,
            onConfirm = refreshCallback,
            onChange = refreshCallback,
        })
    end
end

local function BuildAuraDurationSwipeControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local showAuraDurationSwipe = styleTable.showAuraDurationSwipe
    if showAuraDurationSwipe == nil and type(opts.fallbackStyle) == "table" then
        showAuraDurationSwipe = opts.fallbackStyle.showAuraDurationSwipe
    end

    -- Row grammar only: one checkbox row.
    local auraCb = AddCheckboxRow(container, {
        label = "Show Aura Duration Swipe",
        value = showAuraDurationSwipe ~= false,
        indent = opts.indent,
        onChange = function(val)
            styleTable.showAuraDurationSwipe = val
            refreshCallback()
            RefreshStructuralControls(container)
        end,
    })

    if opts.showAdvancedControlsInline ~= false and showAuraDurationSwipe ~= false then
        BuildAuraDurationSwipeAdvancedControls(container, styleTable, refreshCallback, opts)
    end

    return auraCb
end

-- Row grammar only (RowWidgets.lua). The masque note is a row tooltip rather
-- than an inline gray line: a wrapped sentence does not fit a grid cell, and
-- the row's own (?) badge already carries the same sentence.
local function BuildIconFillTimerControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local disabledByMasque = opts.masqueEnabled == true

    local function ApplyIconFillEnabled(val)
        if disabledByMasque then return end
        styleTable.iconFillEnabled = val == true
        if styleTable.iconFillEnabled and type(opts.onEnabled) == "function" then
            opts.onEnabled()
        end
        refreshCallback()
        CooldownCompanion:UpdateAllCooldowns()
        CooldownCompanion:RefreshConfigPanel()
    end

    local cb = AddCheckboxRow(container, {
        label = "Icon Fill Timer",
        value = styleTable.iconFillEnabled == true,
        disabled = disabledByMasque,
        indent = opts.indent,
        tooltip = disabledByMasque and {
            "Icon Fill Timer",
            {"Unavailable while Masque skinning is enabled for this group.", 1, 1, 1, true},
        } or nil,
        onChange = ApplyIconFillEnabled,
    })

    if disabledByMasque then
        return cb
    end

    if opts.showAdvancedControlsInline ~= false then
        -- opts rides along so the inline block draws in the same shape as the
        -- toggle above it.
        BuildIconFillTimerAdvancedControls(container, styleTable, refreshCallback, opts)
    end

    return cb
end

-- Row grammar only (RowWidgets.lua). Like the aura swipe block above, these
-- four are one parent chain under Icon Fill Timer and stay in that toggle's
-- column.
BuildIconFillTimerAdvancedControls = function(container, styleTable, refreshCallback, opts)
    if styleTable.iconFillEnabled ~= true then
        return
    end

    opts = opts or {}
    local iconFillOrientation = styleTable.iconFillOrientation == "horizontal" and "horizontal" or "vertical"

    -- Inline these rows hang off the Icon Fill Timer toggle and indent as its
    -- children; in the advanced panel's single rail the toggle lives back on
    -- the tab, so the caller passes indent = false.
    local childIndent = opts.indent ~= false
    AddDropdownRow(container, {
        label = "Orientation",
        indent = childIndent,
        list = { vertical = "Vertical", horizontal = "Horizontal" },
        order = { "vertical", "horizontal" },
        value = iconFillOrientation,
        onChange = function(val)
            styleTable.iconFillOrientation = val == "vertical" and "vertical" or "horizontal"
            refreshCallback()
            CooldownCompanion:UpdateAllCooldowns()
            RefreshStructuralControls(container)
        end,
    })

    local edgeList, edgeOrder
    if iconFillOrientation == "vertical" then
        edgeList, edgeOrder = { default = "Bottom", reverse = "Top" }, { "default", "reverse" }
    else
        edgeList, edgeOrder = { default = "Left", reverse = "Right" }, { "default", "reverse" }
    end
    AddDropdownRow(container, {
        label = "Anchor Edge",
        indent = childIndent,
        list = edgeList,
        order = edgeOrder,
        value = styleTable.iconFillReverse == true and "reverse" or "default",
        onChange = function(val)
            styleTable.iconFillReverse = val == "reverse"
            refreshCallback()
            CooldownCompanion:UpdateAllCooldowns()
        end,
    })

    AddDropdownRow(container, {
        label = "Timer Motion",
        indent = childIndent,
        pulloutWidth = WIDE_PULLOUT_WIDTH,
        list = { drain = "Starts Full (Drain)", fill = "Starts Empty (Fill)" },
        order = { "drain", "fill" },
        value = styleTable.iconFillTimerBehavior == "fill" and "fill" or "drain",
        onChange = function(val)
            styleTable.iconFillTimerBehavior = val == "drain" and "drain" or "fill"
            refreshCallback()
            CooldownCompanion:UpdateAllCooldowns()
        end,
    })

    -- deferCommit is deliberately absent, matching the stock color picker this
    -- row replaced.
    AddColorRow(container, {
        label = "Cooldown Fill Color",
        indent = childIndent,
        tbl = styleTable,
        key = "iconFillCooldownColor",
        default = {0.6, 0.13, 0.18, 0.55},
        hasAlpha = true,
        onConfirm = refreshCallback,
        onChange = refreshCallback,
    })
end

-- Row grammar only: one checkbox row.
local function BuildLossOfControlControls(container, styleTable, refreshCallback, opts)
    return AddCheckboxRow(container, {
        label = "Show Loss of Control",
        value = styleTable.showLossOfControl or false,
        indent = opts and opts.indent,
        onChange = function(val)
            styleTable.showLossOfControl = val
            refreshCallback()
        end,
    })
end

-- Row grammar only (RowWidgets.lua), single rail: this is the interior of the
-- Unusable Visual advanced panel and has no other call site. `container` stays
-- the panel scroll, which is what keeps RefreshStructuralControls routing to a
-- panel rebuild rather than a whole-config one.
local function BuildUnusableVisualModeControls(container, styleTable, refreshCallback)
    AddCheckboxRow(container, {
        label = "Dim Icon",
        value = ST.UnusableVisualUsesDimTint(styleTable),
        onChange = function(val)
            ST.SetUnusableVisualMode(styleTable, val == true, ST.UnusableVisualUsesDesaturation(styleTable))
            refreshCallback()
            RefreshStructuralControls(container)
        end,
    })

    -- The dim color is this section's own key (ST.OVERRIDE_SECTIONS lists
    -- iconUnusableTintColor under unusableDimming) and it colors nothing until
    -- the dim mode is on, so it rides here as the Dim Icon row's child rather
    -- than in the styling tabs' Icon Tint block, where it read as a tint but
    -- resolved a foreign section. The toggle above reruns this panel through
    -- RefreshStructuralControls, which is what keeps the conditional build live.
    if ST.UnusableVisualUsesDimTint(styleTable) then
        -- Style-only refresh, matching the row's previous home: refreshCallback
        -- here also rebuilds the whole config panel, which would tear down this
        -- advanced panel out from under the open picker.
        local tintRefresh = function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end
        AddColorRow(container, {
            label = "Unusable Dim Color",
            indent = true,
            tbl = styleTable, key = "iconUnusableTintColor",
            default = {0.4, 0.4, 0.4, 1}, hasAlpha = true,
            onConfirm = tintRefresh, onChange = tintRefresh,
        })
    end

    AddCheckboxRow(container, {
        label = "Desaturate Icon",
        value = ST.UnusableVisualUsesDesaturation(styleTable),
        onChange = function(val)
            ST.SetUnusableVisualMode(styleTable, ST.UnusableVisualUsesDimTint(styleTable), val == true)
            refreshCallback()
            RefreshStructuralControls(container)
        end,
    })
end

-- Row grammar only: the toggle is a CDC-CheckBoxRow whose gear chains off the
-- label. The advanced Dim/Desaturate panel it opens is unchanged.
local function BuildUnusableDimmingControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    local unusableCb = AddCheckboxRow(container, {
        label = "Show Unusable Visual",
        value = styleTable.showUnusable == true,
        indent = opts.indent,
        onChange = function(val)
            styleTable.showUnusable = val == true
            refreshCallback()
            RefreshStructuralControls(container)
        end,
    })

    local _, unusableAdvBtn = AddAdvancedToggle(unusableCb,
        opts.advancedKey or "unusableVisual",
        opts.infoButtons or tabInfoButtons,
        styleTable.showUnusable == true, {
            title = "Unusable Visual Advanced",
            build = function(panel)
                BuildUnusableVisualModeControls(panel, styleTable, refreshCallback)
            end,
        })

    return unusableCb, unusableAdvBtn
end

local ASSISTED_HIGHLIGHT_STYLES = {
    blizzard = "Blizzard (Marching Ants)",
    proc = "Proc Glow",
    solid = "Solid Border",
}

-- Row grammar only (RowWidgets.lua). LEFT column: when the highlight is allowed
-- to show (the caller's Show Only In Combat row lands there too). RIGHT column:
-- what it looks like - the style and whichever controls that style owns, which
-- indent as its children.
local function BuildAssistedHighlightControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local right = opts.rightColumn or container
    local previewRefresh = opts.previewRefresh or ST._RefreshSelectedButtonsPreview

    AddCheckboxRow(container, {
        label = "Hostile Target Only",
        value = styleTable.assistedHighlightHostileTargetOnly ~= false,
        indent = opts.indent,
        onChange = function(val)
            styleTable.assistedHighlightHostileTargetOnly = val
            refreshCallback()
        end,
    })

    AddDropdownRow(right, {
        label = "Highlight Style",
        pulloutWidth = WIDE_PULLOUT_WIDTH,
        list = ASSISTED_HIGHLIGHT_STYLES,
        value = styleTable.assistedHighlightStyle or "blizzard",
        onChange = function(val)
            styleTable.assistedHighlightStyle = val
            refreshCallback()
            RefreshStructuralControls(container)
        end,
    })

    -- deferCommit is deliberately absent throughout, matching the
    -- stock color pickers these rows replaced.
    local function HighlightColorRow(rowLabel, key, default)
        AddColorRow(right, {
            label = rowLabel,
            indent = true,
            tbl = styleTable,
            key = key,
            default = default,
            hasAlpha = true,
            onConfirm = refreshCallback,
            onChange = refreshCallback,
        })
    end
    local function HighlightSliderRow(rowLabel, key, minValue, maxValue, default)
        AddSliderRow(right, {
            label = rowLabel,
            indent = true,
            min = minValue, max = maxValue, step = 0.1,
            value = styleTable[key] or default,
            onChange = function(val)
                ST._PreviewScalarSetting(styleTable, key, val, previewRefresh)
            end,
            onRelease = function(val)
                styleTable[key] = val
                refreshCallback()
            end,
        })
    end

    if styleTable.assistedHighlightStyle == "solid" then
        HighlightColorRow("Highlight Color", "assistedHighlightColor", {0.3, 1, 0.3, 0.9})
        HighlightSliderRow("Border Size", "assistedHighlightBorderSize", 1, 6, 2)
    elseif styleTable.assistedHighlightStyle == "blizzard" then
        HighlightSliderRow("Glow Size", "assistedHighlightBlizzardOverhang", 0, 60, 32)
    elseif styleTable.assistedHighlightStyle == "proc" then
        HighlightColorRow("Glow Color", "assistedHighlightProcColor", {1, 1, 1, 1})
        HighlightSliderRow("Glow Size", "assistedHighlightProcOverhang", 0, 60, 32)
    end
end

------------------------------------------------------------------------
-- GENERIC GLOW/EFFECT HELPERS
------------------------------------------------------------------------
-- ONE SPEC, ONE RENDERER. Every per-style slider the glow vocabulary can draw
-- is declared once here and rendered once, by AddGlowSliderRows below; the
-- renderer owns no label, range, step, store key or fallback of its own, so a
-- style's sliders cannot differ between the surfaces that draw them.
--
-- keys = { size = "...", thickness = "...", speed = "...", lines = "...",
--          solidSizeDefault = n } - the calling glow family's store keys.
-- pixelSizeMin: minimum for the pixel "Line Length" slider (1 for glow
--   style controls, 2 for bar effect controls).
--
-- Entry fields:
--   label, min, max, step  literal slider setup
--   keyField               which name in `keys` holds this slider's store key
--   default                fallback when the store holds nothing
--   defaultFrom            name in `keys` whose value outranks `default`
--   minFrom                "pixelSizeMin": the min comes from the parameter
--   requiresKey            skip the entry when `keys[keyField]` is absent
--                          (the optional dash count/thickness sliders)
--   clampToRange           a stored value outside [min, max] falls back to
--                          `default` (autocast's particle scale)
--
-- A style with no list here (color, overlay, none, anything unknown) draws
-- nothing, exactly as the old if/else chain did by falling through.
local GLOW_SLIDER_SPEC = {
    solid = {
        {label = "Border Size", keyField = "size", min = 1, max = 8, step = 0.1,
            default = 5, defaultFrom = "solidSizeDefault"},
    },
    pulse = {
        {label = "Border Size", keyField = "size", min = 1, max = 8, step = 0.1,
            default = 2, defaultFrom = "solidSizeDefault"},
        {label = "Pulse Duration", keyField = "speed", min = 0.1, max = 2.0, step = 0.05, default = 0.5},
    },
    pixel = {
        {label = "Line Length", keyField = "size", minFrom = "pixelSizeMin", max = 12, step = 0.1, default = 8},
        {label = "Line Thickness", keyField = "thickness", min = 1, max = 6, step = 0.1, default = 4},
        {label = "Speed", keyField = "speed", min = 10, max = 200, step = 0.1, default = 50},
        {label = "Number of Lines", keyField = "lines", min = 1, max = 16, step = 1, default = 8, requiresKey = true},
    },
    glow = {
        {label = "Glow Size", keyField = "size", min = 0, max = 60, step = 0.1, default = 30},
    },
    -- Same slider as glow, tighter default: the marching-ants art overhangs
    -- less than Blizzard's proc glow at the same nominal size.
    ants = {
        {label = "Glow Size", keyField = "size", min = 0, max = 60, step = 0.1, default = 23},
    },
    colorShift = {
        {label = "Border Size", keyField = "size", min = 1, max = 8, step = 0.1,
            default = 2, defaultFrom = "solidSizeDefault"},
        {label = "Shift Duration", keyField = "speed", min = 0.1, max = 2.0, step = 0.05, default = 0.8},
    },
    dashes = {
        {label = "Dash Length", keyField = "size", min = 2, max = 20, step = 0.5, default = 12},
        {label = "Dash Thickness", keyField = "thickness", min = 1, max = 8, step = 0.5, default = 3, requiresKey = true},
        {label = "Number of Dashes", keyField = "lines", min = 1, max = 8, step = 1, default = 5, requiresKey = true},
        {label = "Lap Duration", keyField = "speed", min = 1, max = 3, step = 0.05, default = 2},
    },
    autocast = {
        {label = "Particle Scale", keyField = "size", min = 0.2, max = 3, step = 0.05, default = 2, clampToRange = true},
        {label = "Frequency", keyField = "speed", min = 10, max = 200, step = 0.1, default = 50},
    },
}
-- proc is Blizzard's glow under the aura kit's name, and pulsingBorder is the
-- legacy spelling of pulse; a saved profile carrying either must draw the same
-- sliders the modern value does.
GLOW_SLIDER_SPEC.proc = GLOW_SLIDER_SPEC.glow
GLOW_SLIDER_SPEC.pulsingBorder = GLOW_SLIDER_SPEC.pulse

-- Resolve one spec entry against a caller's store. Returns false when the
-- entry is conditional on a key this caller does not have; otherwise the store
-- key, the resolved minimum and the value to seed the slider with.
--
-- storeKey may legitimately come back nil for an entry without requiresKey
-- (the pixel thickness slider has always been emitted unconditionally); that
-- reads as nil from the style table exactly as it did before.
local function ResolveGlowSliderEntry(entry, styleTable, keys, pixelSizeMin)
    local storeKey = keys[entry.keyField]
    if entry.requiresKey and not storeKey then
        return false
    end

    local minValue = entry.minFrom and pixelSizeMin or entry.min
    local default = (entry.defaultFrom and keys[entry.defaultFrom]) or entry.default
    local value = styleTable[storeKey]
    if entry.clampToRange and (not value or value < minValue or value > entry.max) then
        value = default
    end

    return true, storeKey, minValue, value or default
end

-- The `keys` table the renderer reads, assembled from a glow cfg. Shared so
-- every caller hands the spec the same stores.
local function GlowSliderKeys(cfg)
    return {
        size = cfg.sizeKey,
        thickness = cfg.thicknessKey,
        speed = cfg.speedKey,
        lines = cfg.linesKey,
        solidSizeDefault = cfg.solidSizeDefault,
    }
end

-- The one renderer over the spec above, so the surfaces that draw a glow
-- (BuildGlowStyleControls and, through it, BuildBarActiveAuraControls) cannot
-- draw one style's sliders differently. Everything that varies is already in
-- GLOW_SLIDER_SPEC and the caller's `keys`; this function owns nothing but the
-- row shape.
--
-- `previewRefresh` lets resource/cast surfaces name their own canvas. Ordinary
-- panel callers fall back to the pinned Buttons preview. Every live apply runs
-- once on release.
local function AddGlowSliderRows(container, styleTable, currentStyle, keys, refreshCallback, pixelSizeMin, indent, previewRefresh)
    previewRefresh = previewRefresh or ST._RefreshSelectedButtonsPreview
    for _, entry in ipairs(GLOW_SLIDER_SPEC[currentStyle] or {}) do
        local ok, storeKey, minValue, value = ResolveGlowSliderEntry(entry, styleTable, keys, pixelSizeMin)
        if ok then
            AddSliderRow(container, {
                label = entry.label,
                indent = indent,
                min = minValue, max = entry.max, step = entry.step,
                value = value,
                onChange = function(val)
                    ST._PreviewScalarSetting(styleTable, storeKey, val, previewRefresh)
                end,
                onRelease = function(val)
                    styleTable[storeKey] = val
                    refreshCallback()
                end,
            })
        end
    end
end

-- Legacy profile compatibility: lcgProc duplicated Blizzard glow; lcgButton
-- and lcgAutoCast came from the removed LibCustomGlow library (lcgButton maps
-- to its modern Blizzard successor, lcgAutoCast to the CC-owned rebuild).
local function NormalizeLegacyGlowStyle(style)
    if style == "lcgProc" or style == "lcgButton" then
        return "glow"
    end
    if style == "lcgAutoCast" then
        return "autocast"
    end
    return style
end

local PROC_GLOW_STYLE_OPTIONS = {
    ["solid"] = "Solid Border",
    ["pixel"] = "Pixel Glow",
    ["glow"] = "Glow (Blizzard)",
    ["autocast"] = "Autocast Shine",
}
local PROC_GLOW_STYLE_ORDER = {"solid", "pixel", "glow", "autocast"}

-- Generic glow style builder (Group A), row grammar only: a style row, a color
-- row and this style's conditional slider rows. Backs BuildProcGlowControls,
-- BuildReadyGlowControls, BuildKeyPressHighlightControls.
--
-- cfg = { styleKey, colorKey, colorLabel, sizeKey, thicknessKey,
--         speedKey, linesKey, defaultStyle, defaultColor }
local function BuildGlowStyleControls(container, styleTable, refreshCallback, cfg, opts)
    opts = opts or {}
    local function ApplyStyle(val)
        if cfg.enableKey then
            styleTable[cfg.enableKey] = true
        end
        styleTable[cfg.styleKey] = val
        if cfg.onStyleChanged then
            cfg.onStyleChanged(styleTable, val)
        end
        refreshCallback()
        RefreshStructuralControls(container)
    end

    if styleTable[cfg.styleKey] == "lcgProc" then
        styleTable[cfg.styleKey] = "glow"
    end
    local currentStyle = NormalizeLegacyGlowStyle(styleTable[cfg.styleKey] or cfg.defaultStyle)
    if currentStyle == "none" then
        currentStyle = cfg.defaultStyle
    end

    local styleOptions = cfg.styleOptions or {
        ["solid"] = "Solid Border",
        ["pixel"] = "Pixel Glow",
        ["glow"] = "Glow",
    }
    local styleOrder = cfg.styleOrder or {"solid", "pixel", "glow"}

    local childIndent = opts.indent

    AddDropdownRow(container, {
        label = "Glow Style",
        indent = childIndent,
        pulloutWidth = WIDE_PULLOUT_WIDTH,
        list = styleOptions,
        order = styleOrder,
        value = currentStyle,
        onChange = ApplyStyle,
    })

    -- deferCommit is deliberately absent, matching the stock color pickers
    -- these rows replaced. opts.previewRefresh (the mirror-first opt-in) moves
    -- the picker-open path onto the caller's preview and leaves the commit on
    -- refreshCallback; without it both stay on refreshCallback as before.
    local pickerOpenRefresh = opts.previewRefresh or refreshCallback
    -- cfg.noColorStyles: styles whose art is untinted (the pandemic CDM
    -- look), so a color row would be a dead control.
    if not opts.hidePrimaryColorPicker
        and not (cfg.noColorStyles and cfg.noColorStyles[currentStyle]) then
        AddColorRow(container, {
            label = cfg.colorLabel,
            indent = childIndent,
            tbl = styleTable,
            key = cfg.colorKey,
            default = cfg.defaultColor,
            hasAlpha = true,
            onConfirm = refreshCallback,
            onChange = pickerOpenRefresh,
        })
    end

    if cfg.color2Key and currentStyle == "colorShift" then
        AddColorRow(container, {
            label = cfg.color2Label or "Second Color",
            indent = true,
            tbl = styleTable,
            key = cfg.color2Key,
            default = cfg.defaultColor2,
            hasAlpha = true,
            onConfirm = refreshCallback,
            onChange = pickerOpenRefresh,
        })
    end

    AddGlowSliderRows(container, styleTable, currentStyle, GlowSliderKeys(cfg), refreshCallback, 1, true,
        opts.previewRefresh)
end

------------------------------------------------------------------------
-- PUBLIC GLOW/EFFECT WRAPPERS (same signatures as original functions)
------------------------------------------------------------------------
local function BuildProcGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "procGlowStyle", colorKey = "procGlowColor", colorLabel = "Glow Color",
        sizeKey = "procGlowSize", thicknessKey = "procGlowThickness", speedKey = "procGlowSpeed", linesKey = "procGlowLines",
        defaultStyle = "glow", defaultColor = {1, 1, 1, 1},
        styleOptions = PROC_GLOW_STYLE_OPTIONS,
        styleOrder = PROC_GLOW_STYLE_ORDER,
    }, opts)
end

local function BuildReadyGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "readyGlowStyle", colorKey = "readyGlowColor", colorLabel = "Glow Color",
        sizeKey = "readyGlowSize", thicknessKey = "readyGlowThickness", speedKey = "readyGlowSpeed", linesKey = "readyGlowLines",
        defaultStyle = "solid", defaultColor = {0.2, 1.0, 0.2, 1},
        styleOptions = PROC_GLOW_STYLE_OPTIONS,
        styleOrder = PROC_GLOW_STYLE_ORDER,
    }, opts)
end

-- Aura glow styles are limited to what the aura slot kit can render: static
-- textures and AnimationGroup-driven effects. The proc/ready-only styles
-- (pixel/autocast) are not offered here; the kit's dashes style is the
-- pixel equivalent.
local AURA_GLOW_STYLE_OPTIONS = {
    ["solid"] = "Solid Border",
    ["pulse"] = "Pulsing Border",
    ["colorShift"] = "Color Shift",
    ["dashes"] = "Pixel Dashes",
    ["ants"] = "Marching Ants",
    ["proc"] = "Proc Glow",
    ["overlay"] = "Overlay",
}
local AURA_GLOW_STYLE_ORDER = {"solid", "pulse", "colorShift", "dashes", "ants", "proc", "overlay"}

-- The pandemic menu offers the aura-glow vocabulary plus Blizzard's own
-- Cooldown Manager pandemic look (PTR 8 Phase 2). "cdm" is pandemic-only:
-- the aura menu never emits it and the kit's aura resolver degrades it to
-- pulse. Untinted fixed-choreography art, so it draws no color row (via
-- noColorStyles) and no sliders (no GLOW_SLIDER_SPEC entry).
local PANDEMIC_GLOW_STYLE_OPTIONS = {
    ["cdm"] = "Cooldown Manager",
}
for k, v in pairs(AURA_GLOW_STYLE_OPTIONS) do
    PANDEMIC_GLOW_STYLE_OPTIONS[k] = v
end
local PANDEMIC_GLOW_STYLE_ORDER = {"solid", "pulse", "colorShift", "dashes", "ants", "proc", "overlay", "cdm"}

-- The size and speed keys change meaning per style (border/dash px vs
-- overhang %; cycle vs lap seconds), so switching styles resets the sliders
-- to that style's defaults.
local AURA_GLOW_SIZE_RESETS = { proc = 30, ants = 23, dashes = 12 }
local AURA_GLOW_SPEED_RESETS = { colorShift = 0.8, dashes = 2 }

local function BuildAuraGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "auraGlowStyle", colorKey = "auraGlowColor", colorLabel = "Glow Color",
        color2Key = "auraGlowColor2", color2Label = "Second Color", defaultColor2 = {0.1, 0.3, 1, 0.9},
        sizeKey = "auraGlowSize", speedKey = "auraGlowSpeed", linesKey = "auraGlowDashCount",
        thicknessKey = "auraGlowDashThickness",
        defaultStyle = "pulse", defaultColor = {1, 0.84, 0, 0.9},
        styleOptions = AURA_GLOW_STYLE_OPTIONS,
        styleOrder = AURA_GLOW_STYLE_ORDER,
        solidSizeDefault = 2,
        onStyleChanged = function(targetStyle, val)
            targetStyle.auraGlowSize = AURA_GLOW_SIZE_RESETS[val] or 2
            targetStyle.auraGlowSpeed = AURA_GLOW_SPEED_RESETS[val] or 0.5
            targetStyle.auraGlowDashCount = 5
            targetStyle.auraGlowDashThickness = 3
        end,
    }, opts)
end

-- Pandemic glow (PTR 8): the icon-mode pandemic display, a second aura-kit
-- glow Blizzard reveals only while the tracked aura sits inside its refresh
-- window. Same style vocabulary as the aura glow, its own key family
-- (the dormant-era pandemicGlow* stores, retuned to kit seconds/px). The
-- enable is an explicit-true key: the dormant style default is "solid", so
-- style-derived enablement would light every panel unasked.
local function BuildPandemicGlowControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "pandemicGlowStyle", colorKey = "pandemicGlowColor", colorLabel = "Effect Color",
        color2Key = "pandemicGlowColor2", color2Label = "Second Color", defaultColor2 = {1, 1, 1, 0.9},
        sizeKey = "pandemicGlowSize", speedKey = "pandemicGlowSpeed", linesKey = "pandemicGlowLines",
        thicknessKey = "pandemicGlowThickness",
        defaultStyle = "solid", defaultColor = {1, 0.5, 0, 1},
        enableKey = "pandemicEffectEnabled",
        styleOptions = PANDEMIC_GLOW_STYLE_OPTIONS,
        styleOrder = PANDEMIC_GLOW_STYLE_ORDER,
        noColorStyles = { cdm = true },
        solidSizeDefault = 2,
        onStyleChanged = function(targetStyle, val)
            targetStyle.pandemicGlowSize = AURA_GLOW_SIZE_RESETS[val] or 2
            targetStyle.pandemicGlowSpeed = AURA_GLOW_SPEED_RESETS[val] or 0.5
            targetStyle.pandemicGlowLines = 5
            targetStyle.pandemicGlowThickness = 3
        end,
    }, opts)

    -- The marker shares this section's keys but NOT the effect's enable: it
    -- works with the effect off, so the tabs draw it themselves (with its own
    -- gear) rather than through this builder.
end

-- Bar aura indicator (barActiveAura): the border effect shares the aura glow
-- kit vocabulary plus the "color" value, which keeps the aura fill color as
-- the only signal (the stored default). The preview renders the border
-- effect CC-side and simulates the aura fill color plus the fill
-- pulse/color-shift effects (BarMode.lua).
-- Border styles only (owner ruling): the flipbook/fill styles (ants, proc,
-- overlay) are not offered on bars.
local BAR_AURA_EFFECT_STYLE_OPTIONS = {
    ["color"] = "None (bar color only)",
    ["solid"] = "Solid Border",
    ["pulse"] = "Pulsing Border",
    ["colorShift"] = "Color Shift",
    ["dashes"] = "Pixel Dashes",
}
local BAR_AURA_EFFECT_STYLE_ORDER = {"color", "solid", "pulse", "colorShift", "dashes"}

-- "None (bar color only)" runs 21 characters, past what the row grammar's
-- 140px control column can size a menu from - the case WIDE_PULLOUT_WIDTH at
-- the top of this file exists for, and what the shared glow builder gives every
-- style dropdown.

-- One spec, one consumer: BuildGlowStyleControls reads every key, label and
-- default out of it, so no surface can drift from another's store.
-- Nothing mutates it (BuildGlowStyleControls only reads cfg, and
-- onStyleChanged writes through its targetStyle argument), so it is safe as a
-- shared constant.
local BAR_AURA_EFFECT_CFG = {
    styleKey = "barAuraEffect", colorKey = "barAuraEffectColor", colorLabel = "Effect Color",
    color2Key = "barAuraColorShiftColor", color2Label = "Second Color", defaultColor2 = {1, 1, 1, 1},
    sizeKey = "barAuraEffectSize", speedKey = "barAuraEffectSpeed", linesKey = "barAuraEffectLines",
    thicknessKey = "barAuraEffectThickness",
    defaultStyle = "color", defaultColor = {1, 0.84, 0, 0.9},
    enableKey = "barAuraIndicatorEnabled",
    styleOptions = BAR_AURA_EFFECT_STYLE_OPTIONS,
    styleOrder = BAR_AURA_EFFECT_STYLE_ORDER,
    solidSizeDefault = 2,
    onStyleChanged = function(targetStyle, val)
        targetStyle.barAuraEffectSize = AURA_GLOW_SIZE_RESETS[val] or 2
        targetStyle.barAuraEffectSpeed = AURA_GLOW_SPEED_RESETS[val] or 0.5
        targetStyle.barAuraEffectLines = 5
        targetStyle.barAuraEffectThickness = 3
    end,
}

local FILL_EFFECTS_TOOLTIP = {
    "Fill Effects",
    {"The bar fill breathes (pulse) or cycles color (color shift) while the aura is active. Use the preview toggle to see them without a live aura.", 1, 1, 1, true},
}

-- Row grammar only (RowWidgets.lua): the builder opens its own two-column grid
-- on `container` and returns the two columns. LEFT is the border effect (style,
-- its color, its per-style sliders); RIGHT is the two fill effects and their
-- children.
--
-- opts.singleRail suppresses that grid: an advanced settings panel is ONE
-- narrow column (AdvancedSettingsPanel.lua), where a two-column split would
-- leave ~150px per cell, so both halves rail onto `container` itself in the
-- order they are written. It is additive - the two tab callers that omit it get
-- byte-identical output - and railing onto the container is also what keeps the
-- panel's refresh seam intact, since RefreshStructuralControls only routes to
-- the panel rebuild while it can still see the scroll's own
-- _isAdvancedSettingsPanel marker.
local function BuildBarActiveAuraControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    local effectsLeft, effectsRight
    if opts.singleRail then
        effectsLeft, effectsRight = container, container
    else
        effectsLeft, effectsRight = BeginRowGrid(container)
    end

    -- The LEFT column IS the border effect, which is exactly what the shared
    -- glow builder draws - style, its color, its per-style sliders.
    -- Delegating rather than re-implementing is what keeps every surface on one
    -- store.
    BuildGlowStyleControls(effectsLeft, styleTable, refreshCallback, BAR_AURA_EFFECT_CFG, {
        previewRefresh = opts.previewRefresh,
    })

    local pulseRow = AddCheckboxRow(effectsRight, {
        label = "Pulse Bar Fill",
        value = styleTable.barAuraPulseEnabled == true,
        onChange = function(val)
            styleTable.barAuraPulseEnabled = val
            refreshCallback()
            RefreshStructuralControls(container)
        end,
    })
    -- Anchor args are a placeholder - AnchorRowBadge re-points the button
    -- onto the end of the row's label.
    AnchorRowBadge(pulseRow, CreateInfoButton(pulseRow.frame, pulseRow.frame, "LEFT", "LEFT", 0, 0,
        FILL_EFFECTS_TOOLTIP, opts.infoButtons))

    -- Resource/cast callers can name their own canvas; ordinary panels use the
    -- pinned Buttons preview. The live apply lands on release in either case.
    local previewRefresh = opts.previewRefresh or ST._RefreshSelectedButtonsPreview

    if styleTable.barAuraPulseEnabled == true then
        AddSliderRow(effectsRight, {
            label = "Pulse Duration",
            indent = true,
            min = 0.1, max = 2.0, step = 0.05,
            value = styleTable.barAuraPulseSpeed or 0.5,
            onChange = function(val)
                ST._PreviewScalarSetting(styleTable, "barAuraPulseSpeed", val, previewRefresh)
            end,
            onRelease = function(val)
                styleTable.barAuraPulseSpeed = val
                refreshCallback()
            end,
        })
    end

    AddCheckboxRow(effectsRight, {
        label = "Color Shift Bar Fill",
        value = styleTable.barAuraColorShiftEnabled == true,
        onChange = function(val)
            styleTable.barAuraColorShiftEnabled = val
            refreshCallback()
            RefreshStructuralControls(container)
        end,
    })

    if styleTable.barAuraColorShiftEnabled == true then
        AddSliderRow(effectsRight, {
            label = "Shift Duration",
            indent = true,
            min = 0.1, max = 2.0, step = 0.05,
            value = styleTable.barAuraColorShiftSpeed or 0.5,
            onChange = function(val)
                ST._PreviewScalarSetting(styleTable, "barAuraColorShiftSpeed", val, previewRefresh)
            end,
            onRelease = function(val)
                styleTable.barAuraColorShiftSpeed = val
                refreshCallback()
            end,
        })

        AddColorRow(effectsRight, {
            label = "Shift Color",
            indent = true,
            tbl = styleTable,
            key = "barAuraColorShiftColor",
            default = {1, 1, 1, 1},
            hasAlpha = true,
            onConfirm = refreshCallback,
            onChange = previewRefresh or refreshCallback,
        })
    end

    return effectsLeft, effectsRight
end

local KPH_STYLE_OPTIONS = {["solid"] = "Solid Border", ["overlay"] = "Overlay"}
local KPH_STYLE_ORDER = {"solid", "overlay"}

local function BuildKeyPressHighlightControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "keyPressHighlightStyle", colorKey = "keyPressHighlightColor", colorLabel = "Highlight Color",
        sizeKey = "keyPressHighlightSize",
        defaultStyle = "solid", defaultColor = {1, 1, 1, 0.4},
        styleOptions = KPH_STYLE_OPTIONS,
        styleOrder = KPH_STYLE_ORDER,
    }, opts)
end

------------------------------------------------------------------------
-- Text Mode — Text Colors
------------------------------------------------------------------------
-- Row grammar only (RowWidgets.lua): the backdrop and the border that frames
-- it, reading top to bottom - four rows at most, so they stay in one column
-- (the <4-rows rule). opts.indent makes them child rows. The pre-redesign
-- full-width stock shape had no call sites left after the conversion packets.
local function BuildTextBackgroundControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local previewRefresh = opts.previewRefresh or ST._RefreshSelectedButtonsPreview

    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    -- deferCommit is deliberately absent throughout, matching the
    -- stock color pickers this section used to make.
    AddColorRow(container, {
        label = "Background Color",
        indent = opts.indent,
        tbl = styleTable,
        key = "textBgColor",
        default = {0, 0, 0, 0},
        hasAlpha = true,
        onConfirm = refreshCallback,
        onChange = refreshCallback,
    })

    local renderMode = AddBorderRenderModeDropdown(container, styleTable, "textBorderRenderMode", function()
        refreshCallback()
        RefreshStructuralControls(container)
    end, nil, { row = true, indent = opts.indent })

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        AddSliderRow(container, {
            label = "Border Size",
            indent = true,
            min = 0, max = 5, step = 0.1,
            value = styleTable.textBorderSize or 0,
            disabled = borderThicknessLocked,
            onChange = function(val)
                if borderThicknessLocked then return end
                ST._PreviewScalarSetting(styleTable, "textBorderSize", val, previewRefresh)
            end,
            onRelease = function(val)
                if borderThicknessLocked then return end
                styleTable.textBorderSize = val
                refreshCallback()
            end,
        })
    end

    AddColorRow(container, {
        label = "Border Color",
        indent = opts.indent,
        tbl = styleTable,
        key = "textBorderColor",
        default = {0, 0, 0, 1},
        hasAlpha = true,
        onConfirm = refreshCallback,
        onChange = refreshCallback,
    })
end

-- Row grammar only: LEFT what the text is drawn with, RIGHT how the line is
-- laid out.
local function BuildTextFontControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local right = opts.rightColumn or container

    AddFontControls(container, styleTable, "text", {sizeMin = 6, sizeMax = 72}, refreshCallback,
        { row = true, indent = opts.indent })

    AddDropdownRow(right, {
        label = "Alignment",
        list = {LEFT = "Left", CENTER = "Center", RIGHT = "Right"},
        value = styleTable.textAlignment or "LEFT",
        onChange = function(val)
            styleTable.textAlignment = val
            refreshCallback()
        end,
    })

    AddCheckboxRow(right, {
        label = "Text Shadow",
        value = styleTable.textShadow == true,
        onChange = function(val)
            styleTable.textShadow = val or false
            refreshCallback()
        end,
    })
end

-- Row grammar only: the complete palette the text renderer can reach. LEFT
-- column (the container the caller hands over): the base color and the two
-- cooldown states. RIGHT column (opts.rightColumn): the aura color and the
-- custom color, which no token claims on its own.
--
-- Every row carries a "?" badge naming the tokens it paints. A swatch says
-- nothing about which token it reaches, and two of these five are reachable
-- only through a color tag.
--
-- Ready Text is a format-vocabulary setting, so on the panel path it lives in
-- the Format String section (TextModeTabs.lua). A per-entry override has no
-- Format String section of its own, so the override path keeps its own row for
-- it here - a plain row, not the advanced gear this section used to carry.
local function BuildTextColorsControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local right = opts.rightColumn or container
    local infoButtons = opts.infoButtons or tabInfoButtons

    -- deferCommit is deliberately absent throughout, matching the
    -- stock color pickers these rows replaced.
    local function TextColorRow(host, rowLabel, key, default, tooltipLines)
        local row = AddColorRow(host, {
            label = rowLabel,
            indent = opts.indent,
            tbl = styleTable,
            key = key,
            default = default,
            hasAlpha = true,
            onConfirm = refreshCallback,
            onChange = refreshCallback,
        })
        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label.
        AnchorRowBadge(row, CreateInfoButton(row.frame, row.frame, "LEFT", "LEFT", 0, 0,
            tooltipLines, infoButtons))
        return row
    end

    TextColorRow(container, "Text Color", "textFontColor", {1, 1, 1, 1}, {
        "Text Color",
        {"The color text falls back to.", 1, 1, 1, true},
        " ",
        {"Paints |cff00ff00{name}|r, |cff00ff00{keybind}|r, |cff00ff00{stacks}|r and |cff00ff00{maxcharges}|r.", 1, 1, 1, true},
        " ",
        {"Color tags in the format override it.", 1, 1, 1, true},
    })

    TextColorRow(container, "Cooldown Color", "textCooldownColor", {1, 0.3, 0.3, 1}, {
        "Cooldown Color",
        {"Paints |cff00ff00{time}|r, and |cff00ff00{status}|r while the spell is on cooldown.", 1, 1, 1, true},
        " ",
        {"The |cff44bbff{cooldown}|r tag paints anything with it.", 1, 1, 1, true},
    })

    TextColorRow(container, "Ready Color", "textReadyColor", {0.2, 1.0, 0.2, 1}, {
        "Ready Color",
        {"Paints |cff00ff00{status}|r when the spell is ready.", 1, 1, 1, true},
        " ",
        {"The |cff44bbff{ready}|r tag paints anything with it.", 1, 1, 1, true},
    })

    TextColorRow(right, "Aura Color", "textAuraColor", {0, 0.925, 1, 1}, {
        "Aura Color",
        {"The |cff44bbff{active}|r tag paints anything with it.", 1, 1, 1, true},
    })

    TextColorRow(right, "Custom Color", "textCustomColor", {1, 0.82, 0, 1}, {
        "Custom Color",
        {"No token paints with this color on its own.", 1, 1, 1, true},
        " ",
        {"The |cff44bbff{custom}|r tag paints anything with it.", 1, 1, 1, true},
    })

end

------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
ST._AddDurationFormatDropdown = AddDurationFormatDropdown
ST._AddPandemicMarkerControls = AddPandemicMarkerControls
ST._BuildAuraDurationSwipeControls = BuildAuraDurationSwipeControls
ST._BuildAuraDurationSwipeAdvancedControls = BuildAuraDurationSwipeAdvancedControls
ST._BuildKeybindTextControls = BuildKeybindTextControls
ST._BuildBorderControls = BuildBorderControls
ST._BuildIconTintControls = BuildIconTintControls
ST._BuildDesaturationControls = BuildDesaturationControls
ST._BuildIconZoomControls = BuildIconZoomControls
ST._BuildShowTooltipsControls = BuildShowTooltipsControls
ST._BuildShowOutOfRangeControls = BuildShowOutOfRangeControls
ST._BuildAllowPingsControls = BuildAllowPingsControls
ST._BuildShowGCDSwipeControls = BuildShowGCDSwipeControls
ST._BuildCooldownSwipeControls = BuildCooldownSwipeControls
ST._BuildIconFillTimerControls = BuildIconFillTimerControls
ST._BuildIconFillTimerAdvancedControls = BuildIconFillTimerAdvancedControls
ST._BuildLossOfControlControls = BuildLossOfControlControls
ST._BuildUnusableDimmingControls = BuildUnusableDimmingControls
ST._BuildAssistedHighlightControls = BuildAssistedHighlightControls
ST._BuildProcGlowControls = BuildProcGlowControls
ST._BuildAuraGlowControls = BuildAuraGlowControls
ST._BuildPandemicGlowControls = BuildPandemicGlowControls
-- The bare per-style slider renderer, for surfaces that own their style
-- dropdown but must draw the same sliders (resource aura border, MW
-- max-stack border). Callers hand a keys table in GlowSliderKeys' shape.
ST._AddGlowSliderRows = AddGlowSliderRows
ST._BuildBarActiveAuraControls = BuildBarActiveAuraControls
ST._BuildReadyGlowControls = BuildReadyGlowControls
ST._BuildKeyPressHighlightControls = BuildKeyPressHighlightControls
ST._BuildTextFontControls = BuildTextFontControls
ST._BuildTextColorsControls = BuildTextColorsControls
ST._BuildTextBackgroundControls = BuildTextBackgroundControls

-- Tracked-aura candidate lists (shared by the panel Aura tab and the
-- custom-bar Aura tab).
ST._ClassifyAuraSpellUnit = ClassifyAuraSpellUnit
ST._GetAuraCandidateList = GetAuraCandidateList
ST._TryAddAuraCandidate = TryAddAuraCandidate
ST._RemoveAuraCandidate = RemoveAuraCandidate
ST._AddAuraCandidateRow = AddAuraCandidateRow
ST._AddAuraStackMaxStatusLabel = AddAuraStackMaxStatusLabel
