local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders
local AddBorderRenderModeDropdown = ST._AddBorderRenderModeDropdown

-- Imports from RowWidgets.lua (the row grammar). Every builder with an
-- opts.row branch draws from these; the stock shapes below are unchanged for
-- the call sites that omit it.
--
-- opts.rightColumn is the second half of the grid the CALLER opened: a builder
-- with a natural two-column split writes its "what it looks like / where it
-- lands" rows there and its "what it is drawn with" rows into `container`.
-- Builders that ignore it simply fill the left column, which is what the
-- fill-LEFT-first rule asks for. Only the Overrides tab passes it today.
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddEditBoxRow = ST._AddEditBoxRow
local AddColorRow = ST._AddColorRow
local AddLabelRow = ST._AddLabelRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid

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
        local info = C_Spell.GetSpellInfo(input)
        spellID = info and info.spellID
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

-- opts.row opts into the row grammar (RowWidgets.lua). A tracked aura presents
-- an ITEM, not a setting, so it draws as a CDC-LabelRow: the spell's icon
-- inlined into the label text (the row's label is a FontString, so the icon
-- rides an inline texture escape) and a Remove link owned by the row's control
-- column. The stock shape below is a 22px Flow row and would break the 30px
-- rhythm inside a grid column.
local function AddAuraCandidateRow(container, spellID, onRemove, opts)
    local info = C_Spell.GetSpellInfo(spellID)
    local name = info and info.name or ("Spell " .. spellID)

    if opts and opts.row then
        local icon = C_Spell.GetSpellTexture(spellID) or 134400
        local row = AddLabelRow(container, {
            label = ("|T%d:16:16:0:0|t %s |cff999999(%d)|r"):format(icon, name, spellID),
            indent = true,
        })

        -- Right-justified so the word lands on the control column's right edge
        -- like every other row's control. SetJustifyH is public API and the
        -- stock Label resets it to LEFT in OnAcquire, so the pool stays clean.
        local removeLabel = AceGUI:Create("InteractiveLabel")
        removeLabel:SetText("|cffff5555Remove|r")
        removeLabel:SetWidth(60)
        removeLabel:SetJustifyH("RIGHT")
        removeLabel:SetCallback("OnClick", function()
            onRemove(spellID)
        end)
        row:SetControlWidget(removeLabel)
        return row
    end

    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)

    local label = AceGUI:Create("Label")
    label:SetImage(C_Spell.GetSpellTexture(spellID) or 134400)
    label:SetImageSize(16, 16)
    label:SetText(("%s |cff999999(%d)|r"):format(name, spellID))
    label:SetRelativeWidth(0.8)
    row:AddChild(label)

    local remove = AceGUI:Create("InteractiveLabel")
    remove:SetText("|cffff5555Remove|r")
    remove:SetRelativeWidth(0.2)
    remove:SetCallback("OnClick", function()
        onRemove(spellID)
    end)
    row:AddChild(remove)

    container:AddChild(row)
end

-- The stack-bar status line. A nil max means one of two very different
-- things, and only the combat check tells them apart: in combat the game
-- returns the stack maximum as a secret the addon must discard, so claiming
-- the aura doesn't stack would be a lie the tab tells whenever it is
-- rebuilt mid-fight.
-- The three texts live here alone so the stock label below and the row-grammar
-- label row the custom-bar Aura tab draws cannot word one of them differently.
local function GetAuraStackMaxStatusText(maxStacks)
    if maxStacks then
        return "|cffffd100Stack bar:|r full at " .. maxStacks .. " stacks"
    elseif InCombatLockdown() then
        return "|cffff9955The stack maximum can't be read in combat — it resolves when you leave combat.|r"
    else
        return "|cffff9955This aura doesn't stack — the bar will show duration.|r"
    end
end

-- opts.row opts into the row grammar (RowWidgets.lua). The stock shape is a
-- wrapped Label - 1-3 lines of unpredictable height, which between two rows
-- shoves everything below it out of rhythm; as a label row it occupies exactly
-- one row slot whether it is there or not. Same three texts, same colors, same
-- conditions - the row is just the shape. It always indents, because it is
-- always a child of the stacks toggle it explains, and row labels never wrap,
-- so the sentence also says its piece on hover.
local function AddAuraStackMaxStatusLabel(container, maxStacks, opts)
    local statusText = GetAuraStackMaxStatusText(maxStacks)

    if opts and opts.row then
        return AddLabelRow(container, {
            label = statusText,
            indent = true,
            tooltip = { { statusText, 1, 1, 1, true } },
        })
    end

    local statusLabel = AceGUI:Create("Label")
    statusLabel:SetText(statusText)
    statusLabel:SetFullWidth(true)
    container:AddChild(statusLabel)
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

-- opts.row opts into the row grammar (RowWidgets.lua); opts.indent makes it a
-- child row and opts.pulloutWidth widens its menu. No default pullout width:
-- the longest option ("1:30 / 45.0 / 8.7") is the same list the already
-- converted group Text tab renders at the stock 140px control width.
local function AddDurationFormatDropdown(container, settings, refreshCallback, opts)
    if not (container and settings and CooldownCompanion.GetDurationFormatOptions) then
        return nil
    end

    local formatOptions, formatOrder = CooldownCompanion:GetDurationFormatOptions()

    local function ApplyDurationFormat(val)
        settings.durationFormat = CooldownCompanion.NormalizeDurationFormat(val)
        settings.decimalTimers = nil
        if refreshCallback then
            refreshCallback()
        end
    end

    if opts and opts.row then
        return AddDropdownRow(container, {
            label = "Duration Format",
            indent = opts.indent,
            pulloutWidth = opts.pulloutWidth,
            list = formatOptions,
            order = formatOrder,
            value = CooldownCompanion.GetDurationFormat(settings),
            onChange = ApplyDurationFormat,
        })
    end

    local durationDrop = AceGUI:Create("Dropdown")
    durationDrop:SetLabel("Duration Format")
    durationDrop:SetList(formatOptions, formatOrder)
    durationDrop:SetValue(CooldownCompanion.GetDurationFormat(settings))
    durationDrop:SetFullWidth(true)
    durationDrop:SetCallback("OnValueChanged", function(widget, event, val)
        ApplyDurationFormat(val)
    end)
    container:AddChild(durationDrop)
    return durationDrop
end

-- opts.row opts into the row grammar (RowWidgets.lua). LEFT column (the
-- container the caller hands over): the toggle and what the text is drawn
-- WITH. RIGHT column (opts.rightColumn): what it looks like and where it
-- lands. Rows in the LEFT column indent under the toggle they belong to; the
-- RIGHT column's rows head their own column, so they do not - the same
-- convention every text builder below follows.
local function BuildCooldownTextControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local fallbackStyle = opts.fallbackStyle
    local showCooldownText = styleTable.showCooldownText
    if showCooldownText == nil and type(fallbackStyle) == "table" then
        showCooldownText = fallbackStyle.showCooldownText
    end

    -- The write both shapes perform, hoisted so neither can wire a different
    -- store than the other.
    local function ApplyShowCooldownText(val)
        styleTable.showCooldownText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end

    if opts.row then
        local right = opts.rightColumn or container

        AddCheckboxRow(container, {
            label = "Show Cooldown Text",
            value = showCooldownText or false,
            indent = opts.indent,
            onChange = ApplyShowCooldownText,
        })

        -- Same suppression the stock path applies: a per-entry override does
        -- not carry the group's duration format.
        if not opts.isOverride and showCooldownText then
            AddDurationFormatDropdown(container, styleTable, refreshCallback,
                { row = true, indent = true })
        end

        if showCooldownText then
            AddFontControls(container, styleTable, "cooldown", {}, refreshCallback,
                { row = true, indent = true })

            -- deferCommit is deliberately absent throughout, matching the
            -- AddColorPicker calls the stock path makes.
            AddColorRow(right, {
                label = "Font Color",
                tbl = styleTable,
                key = "cooldownFontColor",
                default = {1, 1, 1, 1},
                onConfirm = refreshCallback,
                onChange = refreshCallback,
            })
            AddAnchorDropdown(right, styleTable, "cooldownTextAnchor", "CENTER", refreshCallback,
                nil, { row = true })
            AddOffsetSliders(right, styleTable, "cooldownTextXOffset", "cooldownTextYOffset", {},
                refreshCallback, { row = true })
        end
        return
    end

    local cdTextCb = AceGUI:Create("CheckBox")
    cdTextCb:SetLabel("Show Cooldown Text")
    cdTextCb:SetValue(showCooldownText or false)
    cdTextCb:SetFullWidth(true)
    cdTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showCooldownText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(cdTextCb)

    if not (opts and opts.isOverride) and showCooldownText then
        AddDurationFormatDropdown(container, styleTable, refreshCallback, opts)
    end

    if showCooldownText then
        AddFontControls(container, styleTable, "cooldown", {}, refreshCallback)
        AddColorPicker(container, styleTable, "cooldownFontColor", "Font Color", {1, 1, 1, 1}, false, refreshCallback, refreshCallback)
        AddAnchorDropdown(container, styleTable, "cooldownTextAnchor", "CENTER", refreshCallback)
        AddOffsetSliders(container, styleTable, "cooldownTextXOffset", "cooldownTextYOffset", {}, refreshCallback)

    end
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
    {"Marks the aura duration text during the last 30% of the aura's duration — the refresh window where recasting extends the remaining time instead of wasting it. Blizzard evaluates the timing; the addon never reads combat values.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"On by default for debuffs on your target; each entry's Aura tab has the per-entry switch. If a game update ever breaks this display, turn it off here to restore standard duration text.", 1, 1, 1, true},
}

-- opts.row opts into the row grammar (RowWidgets.lua); the marker text, the
-- color mode and the color are children of the toggle, so they indent under
-- it. Omitting opts keeps the full-width stock widgets the group-tab advanced
-- panel draws today.
local function AddPandemicMarkerControls(container, styleTable, refreshCallback, rebuildCallback, opts)
    if opts and opts.row then
        local enableRow = AddCheckboxRow(container, {
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

        if styleTable.pandemicMarkerEnabled == false then
            return
        end

        AddEditBoxRow(container, {
            label = "Marker Text",
            indent = true,
            value = styleTable.pandemicMarkerText or "!!",
            onEnterPressed = function(text, widget)
                text = tostring(text or ""):gsub("[|%%]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 8)
                styleTable.pandemicMarkerText = text
                widget:SetText(text)
                refreshCallback()
            end,
        })

        AddDropdownRow(container, {
            label = "Pandemic Color",
            indent = true,
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
            -- deferCommit is deliberately absent, matching the AddColorPicker
            -- call the stock path makes.
            AddColorRow(container, {
                label = "Pandemic Color",
                indent = true,
                tbl = styleTable,
                key = "pandemicMarkerColor",
                default = {1, 0.5, 0, 1},
                onConfirm = refreshCallback,
                onChange = refreshCallback,
            })
        end
        return
    end

    local enableCb = AceGUI:Create("CheckBox")
    enableCb:SetLabel("Pandemic Marker")
    enableCb:SetValue(styleTable.pandemicMarkerEnabled ~= false)
    enableCb:SetFullWidth(true)
    enableCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.pandemicMarkerEnabled = val
        refreshCallback()
        rebuildCallback()
    end)
    container:AddChild(enableCb)

    CreateInfoButton(enableCb.frame, enableCb.checkbg, "LEFT", "RIGHT", enableCb.text:GetStringWidth() + 4, 0,
        PANDEMIC_MARKER_TOOLTIP_LINES, enableCb)

    if styleTable.pandemicMarkerEnabled ~= false then
        local markerBox = AceGUI:Create("EditBox")
        markerBox:SetLabel("Marker Text")
        markerBox:SetText(styleTable.pandemicMarkerText or "!!")
        markerBox:SetFullWidth(true)
        markerBox:SetCallback("OnEnterPressed", function(widget, event, text)
            text = tostring(text or ""):gsub("[|%%]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 8)
            styleTable.pandemicMarkerText = text
            widget:SetText(text)
            refreshCallback()
        end)
        container:AddChild(markerBox)

        local modeDrop = AceGUI:Create("Dropdown")
        modeDrop:SetLabel("Pandemic Color")
        modeDrop:SetList(PANDEMIC_COLOR_MODES, PANDEMIC_COLOR_MODE_ORDER)
        modeDrop:SetValue(styleTable.pandemicMarkerColorMode or "marker")
        modeDrop:SetFullWidth(true)
        modeDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.pandemicMarkerColorMode = val
            refreshCallback()
            rebuildCallback()
        end)
        container:AddChild(modeDrop)

        if (styleTable.pandemicMarkerColorMode or "marker") ~= "off" then
            AddColorPicker(container, styleTable, "pandemicMarkerColor", "Pandemic Color", {1, 0.5, 0, 1}, false, refreshCallback, refreshCallback)
        end
    end
end

local AURA_TEXT_SHARED_POSITION_TOOLTIP = {
    "Shared Position",
    {"Position is shared with Cooldown Text by default. Enable 'Separate Text Positions' below to use independent positions.", 1, 1, 1, true},
}

local SEPARATE_TEXT_POSITIONS_TOOLTIP = {
    "Separate Text Positions",
    {"When enabled, aura duration text and cooldown text use independent positions and can show at the same time. Aura text position controls appear below when toggled on; cooldown text position is in the Cooldown Text section.", 1, 1, 1, true},
}

-- opts.row: LEFT column is the toggle and what the text is drawn with; RIGHT
-- is where it lands (the separate-position chain) plus the pandemic marker,
-- which rides this text and so belongs to this section.
local function BuildAuraTextControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local fallbackStyle = opts.fallbackStyle
    local showAuraText = styleTable.showAuraText
    if showAuraText == nil and type(fallbackStyle) == "table" then
        showAuraText = fallbackStyle.showAuraText
    end

    local function ApplyShowAuraText(val)
        styleTable.showAuraText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end
    local function ApplySeparatePositions(val)
        styleTable.separateTextPositions = val
        refreshCallback()
        RefreshStructuralControls(container)
    end

    if opts.row then
        local right = opts.rightColumn or container

        local auraTextRow = AddCheckboxRow(container, {
            label = "Show Aura Duration Text",
            value = showAuraText ~= false,
            indent = opts.indent,
            onChange = ApplyShowAuraText,
        })
        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label.
        AnchorRowBadge(auraTextRow, CreateInfoButton(auraTextRow.frame, auraTextRow.frame, "LEFT", "LEFT", 0, 0,
            AURA_TEXT_SHARED_POSITION_TOOLTIP, auraTextRow))

        if showAuraText == false then
            return
        end

        AddFontControls(container, styleTable, "auraText", {}, refreshCallback,
            { row = true, indent = true })
        -- deferCommit is deliberately absent, matching the AddColorPicker call
        -- the stock path makes.
        AddColorRow(container, {
            label = "Font Color",
            indent = true,
            tbl = styleTable,
            key = "auraTextFontColor",
            default = {0, 0.925, 1, 1},
            onConfirm = refreshCallback,
            onChange = refreshCallback,
        })

        local sepPosRow = AddCheckboxRow(right, {
            label = "Separate Text Positions",
            onChange = ApplySeparatePositions,
            value = styleTable.separateTextPositions or false,
        })
        AnchorRowBadge(sepPosRow, CreateInfoButton(sepPosRow.frame, sepPosRow.frame, "LEFT", "LEFT", 0, 0,
            SEPARATE_TEXT_POSITIONS_TOOLTIP, sepPosRow))

        if styleTable.separateTextPositions then
            AddAnchorDropdown(right, styleTable, "auraTextAnchor", "TOPLEFT", refreshCallback,
                nil, { row = true, indent = true })
            AddOffsetSliders(right, styleTable, "auraTextXOffset", "auraTextYOffset", {x = 2, y = -2},
                refreshCallback, { row = true, indent = true })
        end

        AddPandemicMarkerControls(right, styleTable, refreshCallback, function()
            RefreshStructuralControls(container)
        end, { row = true })
        return
    end

    local auraTextCb = AceGUI:Create("CheckBox")
    auraTextCb:SetLabel("Show Aura Duration Text")
    auraTextCb:SetValue(showAuraText ~= false)
    auraTextCb:SetFullWidth(true)
    auraTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showAuraText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(auraTextCb)

    CreateInfoButton(auraTextCb.frame, auraTextCb.checkbg, "LEFT", "RIGHT", auraTextCb.text:GetStringWidth() + 4, 0,
        AURA_TEXT_SHARED_POSITION_TOOLTIP, auraTextCb)

    if showAuraText ~= false then
        AddFontControls(container, styleTable, "auraText", {}, refreshCallback)
        AddColorPicker(container, styleTable, "auraTextFontColor", "Font Color", {0, 0.925, 1, 1}, false, refreshCallback, refreshCallback)

        local sepPosCb = AceGUI:Create("CheckBox")
        sepPosCb:SetLabel("Separate Text Positions")
        sepPosCb:SetValue(styleTable.separateTextPositions or false)
        sepPosCb:SetFullWidth(true)
        sepPosCb:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.separateTextPositions = val
            refreshCallback()
            RefreshStructuralControls(container)
        end)
        container:AddChild(sepPosCb)

        CreateInfoButton(sepPosCb.frame, sepPosCb.checkbg, "LEFT", "RIGHT", sepPosCb.text:GetStringWidth() + 4, 0,
            SEPARATE_TEXT_POSITIONS_TOOLTIP, sepPosCb)

        if styleTable.separateTextPositions then
            AddAnchorDropdown(container, styleTable, "auraTextAnchor", "TOPLEFT", refreshCallback)
            AddOffsetSliders(container, styleTable, "auraTextXOffset", "auraTextYOffset", {x = 2, y = -2}, refreshCallback)
        end

        AddPandemicMarkerControls(container, styleTable, refreshCallback, function()
            RefreshStructuralControls(container)
        end)
    end
end

-- opts.row: same split as Cooldown Text - LEFT the toggle and the font trio,
-- RIGHT the color, anchor and offsets.
local function BuildAuraStackTextControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local fallbackStyle = opts.fallbackStyle
    local showAuraStackText = styleTable.showAuraStackText
    if showAuraStackText == nil and type(fallbackStyle) == "table" then
        showAuraStackText = fallbackStyle.showAuraStackText
    end

    local function ApplyShowAuraStackText(val)
        styleTable.showAuraStackText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end

    if opts.row then
        local right = opts.rightColumn or container

        AddCheckboxRow(container, {
            label = "Show Aura Stack Text",
            value = showAuraStackText ~= false,
            indent = opts.indent,
            onChange = ApplyShowAuraStackText,
        })

        if showAuraStackText ~= false then
            AddFontControls(container, styleTable, "auraStack", {}, refreshCallback,
                { row = true, indent = true })
            -- deferCommit is deliberately absent, matching the AddColorPicker
            -- call the stock path makes.
            AddColorRow(right, {
                label = "Font Color",
                tbl = styleTable,
                key = "auraStackFontColor",
                default = {1, 1, 1, 1},
                hasAlpha = true,
                onConfirm = refreshCallback,
                onChange = refreshCallback,
            })
            AddAnchorDropdown(right, styleTable, "auraStackAnchor", "BOTTOMLEFT", refreshCallback,
                nil, { row = true })
            AddOffsetSliders(right, styleTable, "auraStackXOffset", "auraStackYOffset", {x = 2, y = 2},
                refreshCallback, { row = true })
        end
        return
    end

    local auraStackCb = AceGUI:Create("CheckBox")
    auraStackCb:SetLabel("Show Aura Stack Text")
    auraStackCb:SetValue(showAuraStackText ~= false)
    auraStackCb:SetFullWidth(true)
    auraStackCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showAuraStackText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(auraStackCb)

    if showAuraStackText ~= false then
        AddFontControls(container, styleTable, "auraStack", {}, refreshCallback)
        AddColorPicker(container, styleTable, "auraStackFontColor", "Font Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        AddAnchorDropdown(container, styleTable, "auraStackAnchor", "BOTTOMLEFT", refreshCallback)
        AddOffsetSliders(container, styleTable, "auraStackXOffset", "auraStackYOffset", {x = 2, y = 2}, refreshCallback)
    end
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
        -- deferCommit is deliberately absent, matching the AddColorPicker call
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

-- opts.row: LEFT the toggle and the font trio, RIGHT the three state colors
-- and the placement.
local function BuildChargeTextControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    local function ApplyShowChargeText(val)
        styleTable.showChargeText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end

    if opts.row then
        local right = opts.rightColumn or container

        AddCheckboxRow(container, {
            label = "Show Count Text (Charges/Uses)",
            value = styleTable.showChargeText ~= false,
            indent = opts.indent,
            onChange = ApplyShowChargeText,
        })

        if styleTable.showChargeText ~= false then
            AddFontControls(container, styleTable, "charge", {}, refreshCallback,
                { row = true, indent = true })

            -- deferCommit is deliberately absent throughout, matching the
            -- AddColorPicker calls the stock path makes.
            local function ChargeColorRow(rowLabel, key)
                AddColorRow(right, {
                    label = rowLabel,
                    tbl = styleTable,
                    key = key,
                    default = {1, 1, 1, 1},
                    hasAlpha = true,
                    onConfirm = refreshCallback,
                    onChange = refreshCallback,
                })
            end
            ChargeColorRow("Font Color (Max Charges)", "chargeFontColor")
            ChargeColorRow("Font Color (Missing Charges)", "chargeFontColorMissing")
            ChargeColorRow("Font Color (Zero Charges)", "chargeFontColorZero")

            AddAnchorDropdown(right, styleTable, "chargeAnchor", "BOTTOMRIGHT", refreshCallback,
                nil, { row = true })
            AddOffsetSliders(right, styleTable, "chargeXOffset", "chargeYOffset", {x = -2, y = 2},
                refreshCallback, { row = true })
        end
        return
    end

    local chargeTextCb = AceGUI:Create("CheckBox")
    chargeTextCb:SetLabel("Show Count Text (Charges/Uses)")
    chargeTextCb:SetValue(styleTable.showChargeText ~= false)
    chargeTextCb:SetFullWidth(true)
    chargeTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showChargeText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(chargeTextCb)

    if styleTable.showChargeText ~= false then
        AddFontControls(container, styleTable, "charge", {}, refreshCallback)
        AddColorPicker(container, styleTable, "chargeFontColor", "Font Color (Max Charges)", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        AddColorPicker(container, styleTable, "chargeFontColorMissing", "Font Color (Missing Charges)", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        AddColorPicker(container, styleTable, "chargeFontColorZero", "Font Color (Zero Charges)", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        AddAnchorDropdown(container, styleTable, "chargeAnchor", "BOTTOMRIGHT", refreshCallback)
        AddOffsetSliders(container, styleTable, "chargeXOffset", "chargeYOffset", {x = -2, y = 2}, refreshCallback)
    end
end

-- Row grammar only: the render-mode dropdown reuses
-- AddBorderRenderModeDropdown's own row mode, the conditional thickness slider
-- is its child row, and the color is a color row. Three rows in one column -
-- splitting a parent from its children would orphan the indent.
local function BuildBorderControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    local function ApplyRenderModeChanged()
        refreshCallback()
        RefreshStructuralControls(container)
    end
    local function ApplyBorderSize(val)
        styleTable.borderSize = val
        refreshCallback()
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
                ApplyBorderSize(val)
            end,
        })
    end

    -- deferCommit is deliberately absent, matching the AddColorPicker call this
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

-- setWidth is a stock-only width setter for two-column Flow hosts; opts.row
-- opts into the row grammar instead, where the row sizes itself.
local function BuildBackgroundColorControls(container, styleTable, refreshCallback, setWidth, opts)
    if opts and opts.row then
        return AddColorRow(container, {
            label = "Background Color",
            indent = opts.indent,
            tbl = styleTable,
            key = "backgroundColor",
            default = {0, 0, 0, 0.5},
            hasAlpha = true,
            onConfirm = refreshCallback,
            onChange = refreshCallback,
        })
    end

    local picker = AddColorPicker(container, styleTable, "backgroundColor", "Background Color", {0, 0, 0, 0.5}, true, refreshCallback, refreshCallback)
    if setWidth then setWidth(picker) end
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
-- Show Tooltips advanced panel and has no other call site, so it was converted
-- outright rather than growing an opts.row mode. A panel is one narrow column
-- (AdvancedSettingsPanel.lua), so both rows go straight onto `container`.
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

local function BuildIconTintControls(container, styleTable, refreshCallback, opts)
    -- opts.setWidth: width setter for two-column hosts; applies to the
    -- toggles and color pickers alike. Absent = full width (advanced panels).
    -- Two-column reading order: the always-present colors group first, then a
    -- row break, then each tint toggle beside its own color when enabled.
    local setWidth = (opts and opts.setWidth) or function(w) w:SetFullWidth(true) end

    -- The writes both shapes perform, hoisted so neither can wire a different
    -- store than the other.
    local function ApplyCooldownTintEnabled(val)
        styleTable.iconCooldownTintEnabled = val
        refreshCallback()
        RefreshStructuralControls(container)
    end
    local function ApplyAuraTintEnabled(val)
        styleTable.iconAuraTintEnabled = val
        refreshCallback()
        RefreshStructuralControls(container)
    end

    -- opts.row opts into the row grammar (RowWidgets.lua). Same order and the
    -- same conditions as the stock path; each conditional color indents as the
    -- child of the toggle that reveals it, and the stock row-break spacer has
    -- no row-grammar equivalent (the grid columns do that work).
    -- deferCommit is deliberately absent throughout, matching the
    -- AddColorPicker calls the stock path makes.
    if opts and opts.row then
        local function TintColorRow(label, key, default, indent)
            AddColorRow(container, {
                label = label,
                indent = indent,
                tbl = styleTable,
                key = key,
                default = default,
                hasAlpha = true,
                onConfirm = refreshCallback,
                onChange = refreshCallback,
            })
        end

        TintColorRow("Base Icon Color", "iconTintColor", {1, 1, 1, 1}, opts.indent)

        if styleTable.showUnusable and ST.UnusableVisualUsesDimTint(styleTable) then
            TintColorRow("Unusable Dim Color", "iconUnusableTintColor", {0.4, 0.4, 0.4, 1}, opts.indent)
        end

        if opts.includeBackground then
            BuildBackgroundColorControls(container, styleTable, refreshCallback, nil, opts)
        end

        AddCheckboxRow(container, {
            label = "Use Separate Cooldown Tint",
            value = styleTable.iconCooldownTintEnabled or false,
            indent = opts.indent,
            onChange = ApplyCooldownTintEnabled,
        })

        if styleTable.iconCooldownTintEnabled then
            TintColorRow("Cooldown Icon Color", "iconCooldownTintColor", {1, 0, 0.102, 1}, true)
        end

        if opts.showAuraTint then
            AddCheckboxRow(container, {
                label = "Use Separate Aura Tint",
                value = styleTable.iconAuraTintEnabled or false,
                indent = opts.indent,
                onChange = ApplyAuraTintEnabled,
            })

            if styleTable.iconAuraTintEnabled then
                TintColorRow("Aura Active Icon Color", "iconAuraTintColor", {0, 0.925, 1, 1}, true)
            end
        end
        return
    end

    setWidth(AddColorPicker(container, styleTable, "iconTintColor", "Base Icon Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback))

    if styleTable.showUnusable and ST.UnusableVisualUsesDimTint(styleTable) then
        setWidth(AddColorPicker(container, styleTable, "iconUnusableTintColor", "Unusable Dim Color", {0.4, 0.4, 0.4, 1}, true, refreshCallback, refreshCallback))
    end

    if opts and opts.includeBackground then
        BuildBackgroundColorControls(container, styleTable, refreshCallback, setWidth)
    end

    if opts and opts.setWidth then
        -- Row break between the colors group and the tint toggles, so the
        -- conditional widgets above never shift the toggle pairing.
        local spacer = AceGUI:Create("Label")
        spacer:SetText(" ")
        spacer:SetFullWidth(true)
        container:AddChild(spacer)
    end

    local cdTintCb = AceGUI:Create("CheckBox")
    cdTintCb:SetLabel("Use Separate Cooldown Tint")
    cdTintCb:SetValue(styleTable.iconCooldownTintEnabled or false)
    setWidth(cdTintCb)
    cdTintCb:SetCallback("OnValueChanged", function(w, e, val)
        ApplyCooldownTintEnabled(val)
    end)
    container:AddChild(cdTintCb)

    if styleTable.iconCooldownTintEnabled then
        setWidth(AddColorPicker(container, styleTable, "iconCooldownTintColor", "Cooldown Icon Color", {1, 0, 0.102, 1}, true, refreshCallback, refreshCallback))
    end

    -- Aura tint applies to the slot-kit aura layer (consumed at bind time by
    -- AuraDisplay.StyleSlotKit); only offered where an aura display exists.
    if opts and opts.showAuraTint then
        local auraTintCb = AceGUI:Create("CheckBox")
        auraTintCb:SetLabel("Use Separate Aura Tint")
        auraTintCb:SetValue(styleTable.iconAuraTintEnabled or false)
        setWidth(auraTintCb)
        auraTintCb:SetCallback("OnValueChanged", function(w, e, val)
            ApplyAuraTintEnabled(val)
        end)
        container:AddChild(auraTintCb)

        if styleTable.iconAuraTintEnabled then
            setWidth(AddColorPicker(container, styleTable, "iconAuraTintColor", "Aura Active Icon Color", {0, 0.925, 1, 1}, true, refreshCallback, refreshCallback))
        end
    end
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
        styleTable.cooldownSwipeAlpha = val
        refreshCallback()
    end
    local function ApplyShowEdge(val)
        if disabledByIconFill then return end
        styleTable.showCooldownSwipeEdge = val
        refreshCallback()
        RefreshStructuralControls(container)
    end

    local childIndent = opts.isOverride and true or opts.indent

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
        })
    end

    AddCheckboxRow(container, {
        label = "Show Swipe Edge",
        value = styleTable.showCooldownSwipeEdge ~= false,
        indent = childIndent,
        disabled = disabledByIconFill,
        onChange = ApplyShowEdge,
    })

    if styleTable.showCooldownSwipeEdge ~= false then
        -- deferCommit is deliberately absent, matching the AddColorPicker call
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

-- opts.row opts into the row grammar (RowWidgets.lua). This whole block is one
-- parent chain hanging off Show Aura Duration Swipe, so it stays in the column
-- that toggle sits in - splitting a chain across the grid would orphan the
-- children from the row that gates them. Same rule the cooldown swipe follows.
-- The group tabs reach this builder through an advanced side panel and omit
-- opts.row, keeping the full-width stock widgets.
local function BuildAuraDurationSwipeAdvancedControls(container, styleTable, refreshCallback, opts)
    local blizzardStyleActive = styleTable.auraUseBlizzardSwipe == true

    if opts and opts.row then
        local childIndent = opts.isOverride and true or opts.indent

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
            -- Row grammar has no percent readout, so this reads 0 - 1 rather
            -- than the stock slider's 0% - 100%; same store, same range.
            AddSliderRow(container, {
                label = "Swipe Fill Opacity",
                indent = true,
                min = 0, max = 1, step = 0.05,
                value = styleTable.auraDurationSwipeAlpha or 0.8,
                disabled = blizzardStyleActive,
                onChange = function(val)
                    if blizzardStyleActive then return end
                    styleTable.auraDurationSwipeAlpha = val
                    refreshCallback()
                end,
            })
        end

        AddCheckboxRow(container, {
            label = "Show Swipe Edge",
            value = styleTable.showAuraDurationSwipeEdge ~= false,
            indent = childIndent,
            disabled = blizzardStyleActive,
            onChange = function(val)
                if blizzardStyleActive then return end
                styleTable.showAuraDurationSwipeEdge = val
                refreshCallback()
                RefreshStructuralControls(container)
            end,
        })

        if styleTable.showAuraDurationSwipeEdge ~= false then
            -- deferCommit is deliberately absent, matching the AddColorPicker
            -- call the stock path makes.
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
        return
    end

    local blizzardCb = AceGUI:Create("CheckBox")
    blizzardCb:SetLabel("Blizzard Style Aura Swipe")
    blizzardCb:SetValue(blizzardStyleActive)
    blizzardCb:SetFullWidth(true)
    blizzardCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.auraUseBlizzardSwipe = val == true
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(blizzardCb)
    CreateInfoButton(blizzardCb.frame, blizzardCb.checkbg, "LEFT", "RIGHT", blizzardCb.text:GetStringWidth() + 4, 0, AURA_BLIZZARD_SWIPE_TOOLTIP, blizzardCb)

    local reverseCb = AceGUI:Create("CheckBox")
    reverseCb:SetLabel("Reverse Swipe")
    reverseCb:SetValue(styleTable.auraDurationSwipeReverse ~= false)
    reverseCb:SetFullWidth(true)
    reverseCb:SetDisabled(blizzardStyleActive)
    reverseCb:SetCallback("OnValueChanged", function(widget, event, val)
        if blizzardStyleActive then return end
        styleTable.auraDurationSwipeReverse = val
        refreshCallback()
    end)
    container:AddChild(reverseCb)

    local fillCb = AceGUI:Create("CheckBox")
    fillCb:SetLabel("Show Swipe Fill")
    fillCb:SetValue(styleTable.showAuraDurationSwipeFill ~= false)
    fillCb:SetFullWidth(true)
    fillCb:SetDisabled(blizzardStyleActive)
    fillCb:SetCallback("OnValueChanged", function(widget, event, val)
        if blizzardStyleActive then return end
        styleTable.showAuraDurationSwipeFill = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(fillCb)

    if styleTable.showAuraDurationSwipeFill ~= false then
        local alphaSlider = AceGUI:Create("Slider")
        alphaSlider:SetLabel("Swipe Fill Opacity")
        alphaSlider:SetSliderValues(0, 1, 0.05)
        alphaSlider:SetIsPercent(true)
        alphaSlider:SetValue(styleTable.auraDurationSwipeAlpha or 0.8)
        alphaSlider:SetFullWidth(true)
        alphaSlider:SetDisabled(blizzardStyleActive)
        alphaSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if blizzardStyleActive then return end
            styleTable.auraDurationSwipeAlpha = val
            refreshCallback()
        end)
        container:AddChild(alphaSlider)
    end

    local edgeCb = AceGUI:Create("CheckBox")
    edgeCb:SetLabel("Show Swipe Edge")
    edgeCb:SetValue(styleTable.showAuraDurationSwipeEdge ~= false)
    edgeCb:SetFullWidth(true)
    edgeCb:SetDisabled(blizzardStyleActive)
    edgeCb:SetCallback("OnValueChanged", function(widget, event, val)
        if blizzardStyleActive then return end
        styleTable.showAuraDurationSwipeEdge = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(edgeCb)

    if styleTable.showAuraDurationSwipeEdge ~= false then
        AddColorPicker(container, styleTable, "auraDurationSwipeEdgeColor", "Swipe Edge Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
    end
end

local function BuildAuraDurationSwipeControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local showAuraDurationSwipe = styleTable.showAuraDurationSwipe
    if showAuraDurationSwipe == nil and type(opts.fallbackStyle) == "table" then
        showAuraDurationSwipe = opts.fallbackStyle.showAuraDurationSwipe
    end

    -- opts.row opts into the row grammar (RowWidgets.lua); every other call
    -- site keeps the full-width stock checkbox.
    local auraCb
    if opts.row then
        auraCb = ST._AddCheckboxRow(container, {
            label = "Show Aura Duration Swipe",
            value = showAuraDurationSwipe ~= false,
            indent = opts.indent,
            onChange = function(val)
                styleTable.showAuraDurationSwipe = val
                refreshCallback()
                RefreshStructuralControls(container)
            end,
        })
    else
        auraCb = AceGUI:Create("CheckBox")
        auraCb:SetLabel("Show Aura Duration Swipe")
        auraCb:SetValue(showAuraDurationSwipe ~= false)
        auraCb:SetFullWidth(true)
        auraCb:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.showAuraDurationSwipe = val
            refreshCallback()
            RefreshStructuralControls(container)
        end)
        container:AddChild(auraCb)
    end

    if opts.showAdvancedControlsInline ~= false and showAuraDurationSwipe ~= false then
        BuildAuraDurationSwipeAdvancedControls(container, styleTable, refreshCallback, opts)
    end

    return auraCb
end

-- opts.row opts into the row grammar (RowWidgets.lua). The masque note is a
-- row tooltip there rather than an inline gray line: a wrapped sentence does
-- not fit a grid cell, and the row's own (?) badge already carries the same
-- sentence. Non-row callers keep the inline label unchanged.
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

    local cb
    if opts.row then
        cb = ST._AddCheckboxRow(container, {
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
    else
        cb = AceGUI:Create("CheckBox")
        cb:SetLabel("Icon Fill Timer")
        cb:SetValue(styleTable.iconFillEnabled == true)
        cb:SetFullWidth(true)
        cb:SetDisabled(disabledByMasque)
        cb:SetCallback("OnValueChanged", function(widget, event, val)
            ApplyIconFillEnabled(val)
        end)
        container:AddChild(cb)
    end

    if disabledByMasque then
        if opts.row then
            return cb
        end
        local note = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(note)
        note:SetText("|cff888888Unavailable while Masque skinning is enabled for this group.|r")
        note:SetFullWidth(true)
        container:AddChild(note)
        return cb
    end

    if opts.showAdvancedControlsInline ~= false then
        -- opts rides along so the inline block draws in the same shape as the
        -- toggle above it; the advanced-panel callers pass no opts at all.
        BuildIconFillTimerAdvancedControls(container, styleTable, refreshCallback, opts)
    end

    return cb
end

-- opts.row opts into the row grammar (RowWidgets.lua). Like the aura swipe
-- block above, these four are one parent chain under Icon Fill Timer and stay
-- in that toggle's column. The group Indicators tab reaches this through an
-- advanced side panel and omits opts entirely, keeping the stock widgets.
BuildIconFillTimerAdvancedControls = function(container, styleTable, refreshCallback, opts)
    if styleTable.iconFillEnabled ~= true then
        return
    end

    local iconFillOrientation = styleTable.iconFillOrientation == "horizontal" and "horizontal" or "vertical"

    if opts and opts.row then
        -- On the Overrides tab these rows hang off the Icon Fill Timer toggle
        -- and indent as its children; in the advanced panel's single rail the
        -- toggle lives back on the tab, so the caller passes indent = false.
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

        -- deferCommit is deliberately absent, matching the AddColorPicker call
        -- the stock path makes.
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
        return
    end

    local orientationDrop = AceGUI:Create("Dropdown")
    orientationDrop:SetLabel("Orientation")
    orientationDrop:SetList({
        vertical = "Vertical",
        horizontal = "Horizontal",
    }, { "vertical", "horizontal" })
    orientationDrop:SetValue(iconFillOrientation)
    orientationDrop:SetFullWidth(true)
    orientationDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.iconFillOrientation = val == "vertical" and "vertical" or "horizontal"
        refreshCallback()
        CooldownCompanion:UpdateAllCooldowns()
        RefreshStructuralControls(container)
    end)
    container:AddChild(orientationDrop)

    local anchorEdgeDrop = AceGUI:Create("Dropdown")
    anchorEdgeDrop:SetLabel("Anchor Edge")
    if iconFillOrientation == "vertical" then
        anchorEdgeDrop:SetList({
            default = "Bottom",
            reverse = "Top",
        }, { "default", "reverse" })
    else
        anchorEdgeDrop:SetList({
            default = "Left",
            reverse = "Right",
        }, { "default", "reverse" })
    end
    anchorEdgeDrop:SetValue(styleTable.iconFillReverse == true and "reverse" or "default")
    anchorEdgeDrop:SetFullWidth(true)
    anchorEdgeDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.iconFillReverse = val == "reverse"
        refreshCallback()
        CooldownCompanion:UpdateAllCooldowns()
    end)
    container:AddChild(anchorEdgeDrop)

    local timerMotionDrop = AceGUI:Create("Dropdown")
    timerMotionDrop:SetLabel("Timer Motion")
    timerMotionDrop:SetList({
        drain = "Starts Full (Drain)",
        fill = "Starts Empty (Fill)",
    }, { "drain", "fill" })
    timerMotionDrop:SetValue(styleTable.iconFillTimerBehavior == "fill" and "fill" or "drain")
    timerMotionDrop:SetFullWidth(true)
    timerMotionDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.iconFillTimerBehavior = val == "drain" and "drain" or "fill"
        refreshCallback()
        CooldownCompanion:UpdateAllCooldowns()
    end)
    container:AddChild(timerMotionDrop)

    AddColorPicker(container, styleTable, "iconFillCooldownColor", "Cooldown Fill Color", {0.6, 0.13, 0.18, 0.55}, true, refreshCallback, refreshCallback)
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
-- Unusable Visual advanced panel and has no other call site, so it was
-- converted outright rather than growing an opts.row mode. `container` stays
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

-- opts.row opts into the row grammar (RowWidgets.lua). LEFT column: when the
-- highlight is allowed to show (the caller's Show Only In Combat row lands
-- there too). RIGHT column: what it looks like - the style and whichever
-- controls that style owns, which indent as its children.
local function BuildAssistedHighlightControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    if opts.row then
        local right = opts.rightColumn or container

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
        -- AddColorPicker calls the stock path makes.
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
        return
    end

    local hostileOnlyCb = AceGUI:Create("CheckBox")
    hostileOnlyCb:SetLabel("Hostile Target Only")
    hostileOnlyCb:SetValue(styleTable.assistedHighlightHostileTargetOnly ~= false)
    hostileOnlyCb:SetFullWidth(true)
    hostileOnlyCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.assistedHighlightHostileTargetOnly = val
        refreshCallback()
    end)
    container:AddChild(hostileOnlyCb)

    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Highlight Style")
    styleDrop:SetList(ASSISTED_HIGHLIGHT_STYLES)
    styleDrop:SetValue(styleTable.assistedHighlightStyle or "blizzard")
    styleDrop:SetFullWidth(true)
    styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.assistedHighlightStyle = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(styleDrop)

    if styleTable.assistedHighlightStyle == "solid" then
        AddColorPicker(container, styleTable, "assistedHighlightColor", "Highlight Color", {0.3, 1, 0.3, 0.9}, true, refreshCallback, refreshCallback)

        local hlSizeSlider = AceGUI:Create("Slider")
        hlSizeSlider:SetLabel("Border Size")
        hlSizeSlider:SetSliderValues(1, 6, 0.1)
        hlSizeSlider:SetValue(styleTable.assistedHighlightBorderSize or 2)
        hlSizeSlider:SetFullWidth(true)
        hlSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.assistedHighlightBorderSize = val
            refreshCallback()
        end)
        container:AddChild(hlSizeSlider)
    elseif styleTable.assistedHighlightStyle == "blizzard" then
        local blizzSlider = AceGUI:Create("Slider")
        blizzSlider:SetLabel("Glow Size")
        blizzSlider:SetSliderValues(0, 60, 0.1)
        blizzSlider:SetValue(styleTable.assistedHighlightBlizzardOverhang or 32)
        blizzSlider:SetFullWidth(true)
        blizzSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.assistedHighlightBlizzardOverhang = val
            refreshCallback()
        end)
        container:AddChild(blizzSlider)
    elseif styleTable.assistedHighlightStyle == "proc" then
        AddColorPicker(container, styleTable, "assistedHighlightProcColor", "Glow Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)

        local procSlider = AceGUI:Create("Slider")
        procSlider:SetLabel("Glow Size")
        procSlider:SetSliderValues(0, 60, 0.1)
        procSlider:SetValue(styleTable.assistedHighlightProcOverhang or 32)
        procSlider:SetFullWidth(true)
        procSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.assistedHighlightProcOverhang = val
            refreshCallback()
        end)
        container:AddChild(procSlider)
    end
end

------------------------------------------------------------------------
-- GENERIC GLOW/EFFECT HELPERS
------------------------------------------------------------------------
-- ONE SPEC, TWO RENDERERS. Every per-style slider the glow vocabulary can
-- draw is declared once here. BuildGlowSliders renders an entry as a stock
-- full-width Slider; BuildBarActiveAuraControls' opts.row path renders the
-- same entry as a CDC-SliderRow. Neither renderer owns a label, range, step,
-- store key or fallback of its own, so the two shapes cannot drift apart.
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
        {label = "Dash Length", keyField = "size", min = 2, max = 20, step = 0.5, default = 8},
        {label = "Dash Thickness", keyField = "thickness", min = 1, max = 8, step = 0.5, default = 4, requiresKey = true},
        {label = "Number of Dashes", keyField = "lines", min = 1, max = 8, step = 1, default = 2, requiresKey = true},
        {label = "Lap Duration", keyField = "speed", min = 0.1, max = 2.0, step = 0.05, default = 2},
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

-- The `keys` table BuildGlowSliders reads, assembled from a glow cfg. Shared
-- so the stock path and the row path can never hand the spec different stores.
local function GlowSliderKeys(cfg)
    return {
        size = cfg.sizeKey,
        thickness = cfg.thicknessKey,
        speed = cfg.speedKey,
        lines = cfg.linesKey,
        solidSizeDefault = cfg.solidSizeDefault,
    }
end

local function BuildGlowSliders(container, styleTable, currentStyle, keys, refreshCallback, pixelSizeMin)
    for _, entry in ipairs(GLOW_SLIDER_SPEC[currentStyle] or {}) do
        local ok, storeKey, minValue, value = ResolveGlowSliderEntry(entry, styleTable, keys, pixelSizeMin)
        if ok then
            local slider = AceGUI:Create("Slider")
            slider:SetLabel(entry.label)
            slider:SetSliderValues(minValue, entry.max, entry.step)
            slider:SetValue(value)
            slider:SetFullWidth(true)
            slider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable[storeKey] = val
                refreshCallback()
            end)
            container:AddChild(slider)
        end
    end
end

-- The row-grammar half of the pair above: ONE renderer over the same spec, so
-- the two row consumers (BuildGlowStyleControls' opts.row branch and
-- BuildBarActiveAuraControls' opts.row branch) cannot draw one style's sliders
-- differently. Everything that varies is already in GLOW_SLIDER_SPEC and the
-- caller's `keys`; this function owns nothing but the row shape.
local function AddGlowSliderRows(container, styleTable, currentStyle, keys, refreshCallback, pixelSizeMin, indent)
    for _, entry in ipairs(GLOW_SLIDER_SPEC[currentStyle] or {}) do
        local ok, storeKey, minValue, value = ResolveGlowSliderEntry(entry, styleTable, keys, pixelSizeMin)
        if ok then
            AddSliderRow(container, {
                label = entry.label,
                indent = indent,
                min = minValue, max = entry.max, step = entry.step,
                value = value,
                onChange = function(val)
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

-- Generic glow style builder (Group A): style dropdown + color picker +
-- conditional sliders. Backs BuildProcGlowControls, BuildReadyGlowControls,
-- BuildKeyPressHighlightControls.
--
-- cfg = { styleKey, colorKey, colorLabel, sizeKey, thicknessKey,
--         speedKey, linesKey, defaultStyle, defaultColor }
local function BuildGlowStyleControls(container, styleTable, refreshCallback, cfg, opts)
    local isOverrideMode = opts and opts.isOverride == true
    local isEnabled
    if cfg.enableKey then
        local enabledVal = rawget(styleTable, cfg.enableKey)
        if enabledVal == nil and cfg.deriveEnableFromEffect and rawget(styleTable, cfg.effectKey) ~= nil then
            enabledVal = (styleTable[cfg.effectKey] or "none") ~= "none"
        end
        if enabledVal == nil and opts and opts.fallbackStyle then
            enabledVal = opts.fallbackStyle[cfg.enableKey]
            if enabledVal == nil and cfg.deriveEnableFromEffect then
                enabledVal = (opts.fallbackStyle[cfg.effectKey] or "none") ~= "none"
            end
        end
        isEnabled = enabledVal ~= false
    else
        isEnabled = styleTable[cfg.styleKey] ~= "none"
    end

    -- The enable write both shapes perform, hoisted so neither can wire a
    -- different store than the other.
    local function ApplyEnabled(val)
        if cfg.enableKey then
            styleTable[cfg.enableKey] = val
            if val and styleTable[cfg.styleKey] == "none" then
                styleTable[cfg.styleKey] = cfg.defaultStyle
            end
        else
            styleTable[cfg.styleKey] = val and cfg.defaultStyle or "none"
            -- Re-enabling forces the default style, so per-style keys must
            -- reset with it (a proc-scale size on the pulse border renders
            -- a 30px wall).
            if val and cfg.onStyleChanged then
                cfg.onStyleChanged(styleTable, cfg.defaultStyle)
            end
        end
        refreshCallback()
        RefreshStructuralControls(container)
    end
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

    local rowMode = opts and opts.row == true
    -- Row mode: LEFT column (the container handed over) is what the glow LOOKS
    -- like - the enable toggle, the style, its colors and its sliders. RIGHT
    -- (opts.rightColumn) is where afterEnableCallback's extras land, which on
    -- the Overrides tab are the when-it-shows behaviour rows. The STOCK path's
    -- callback contract is unchanged: it still receives `container`.
    local extrasColumn = (rowMode and opts.rightColumn) or container

    if isOverrideMode and cfg.enableLabel then
        if rowMode then
            AddCheckboxRow(container, {
                label = cfg.enableLabel,
                value = isEnabled,
                indent = opts.indent,
                onChange = ApplyEnabled,
            })
        else
            local enableCb = AceGUI:Create("CheckBox")
            enableCb:SetLabel(cfg.enableLabel)
            enableCb:SetValue(isEnabled)
            enableCb:SetFullWidth(true)
            enableCb:SetCallback("OnValueChanged", function(widget, event, val)
                ApplyEnabled(val)
            end)
            container:AddChild(enableCb)
        end

        if not isEnabled then
            return
        end
    end

    if opts and opts.afterEnableCallback then
        opts.afterEnableCallback(extrasColumn)
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

    if rowMode then
        -- Everything below the enable toggle belongs to it and disappears with
        -- it, so it indents as its child - the same rule the bar aura effect's
        -- row path follows.
        local childIndent = (isOverrideMode and cfg.enableLabel) and true or opts.indent

        AddDropdownRow(container, {
            label = "Glow Style",
            indent = childIndent,
            pulloutWidth = WIDE_PULLOUT_WIDTH,
            list = styleOptions,
            order = styleOrder,
            value = currentStyle,
            onChange = ApplyStyle,
        })

        -- deferCommit is deliberately absent, matching the AddColorPicker calls
        -- the stock path makes.
        if not opts.hidePrimaryColorPicker then
            AddColorRow(container, {
                label = cfg.colorLabel,
                indent = childIndent,
                tbl = styleTable,
                key = cfg.colorKey,
                default = cfg.defaultColor,
                hasAlpha = true,
                onConfirm = refreshCallback,
                onChange = refreshCallback,
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
                onChange = refreshCallback,
            })
        end

        AddGlowSliderRows(container, styleTable, currentStyle, GlowSliderKeys(cfg), refreshCallback, 1, true)
        return
    end

    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Glow Style")
    styleDrop:SetList(styleOptions, styleOrder)
    styleDrop:SetValue(currentStyle)
    styleDrop:SetFullWidth(true)
    styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        ApplyStyle(val)
    end)
    container:AddChild(styleDrop)

    if not (opts and opts.hidePrimaryColorPicker) then
        AddColorPicker(container, styleTable, cfg.colorKey, cfg.colorLabel, cfg.defaultColor, true, refreshCallback, refreshCallback)
    end

    if cfg.color2Key and currentStyle == "colorShift" then
        AddColorPicker(container, styleTable, cfg.color2Key, cfg.color2Label or "Second Color", cfg.defaultColor2, true, refreshCallback, refreshCallback)
    end

    BuildGlowSliders(container, styleTable, currentStyle, GlowSliderKeys(cfg), refreshCallback, 1)
end

------------------------------------------------------------------------
-- PUBLIC GLOW/EFFECT WRAPPERS (same signatures as original functions)
------------------------------------------------------------------------
local function BuildProcGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "procGlowStyle", colorKey = "procGlowColor", colorLabel = "Glow Color",
        sizeKey = "procGlowSize", thicknessKey = "procGlowThickness", speedKey = "procGlowSpeed", linesKey = "procGlowLines",
        defaultStyle = "glow", defaultColor = {1, 1, 1, 1},
        enableLabel = "Show Proc Glow",
        styleOptions = PROC_GLOW_STYLE_OPTIONS,
        styleOrder = PROC_GLOW_STYLE_ORDER,
    }, opts)
end

local function BuildReadyGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "readyGlowStyle", colorKey = "readyGlowColor", colorLabel = "Glow Color",
        sizeKey = "readyGlowSize", thicknessKey = "readyGlowThickness", speedKey = "readyGlowSpeed", linesKey = "readyGlowLines",
        defaultStyle = "solid", defaultColor = {0.2, 1.0, 0.2, 1},
        enableLabel = "Show Ready Glow",
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

-- The size and speed keys change meaning per style (border/dash px vs
-- overhang %; cycle vs lap seconds), so switching styles resets the sliders
-- to that style's defaults.
local AURA_GLOW_SIZE_RESETS = { proc = 30, ants = 23, dashes = 8 }
local AURA_GLOW_SPEED_RESETS = { colorShift = 0.8, dashes = 2 }

local function BuildAuraGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "auraGlowStyle", colorKey = "auraGlowColor", colorLabel = "Glow Color",
        color2Key = "auraGlowColor2", color2Label = "Second Color", defaultColor2 = {0.1, 0.3, 1, 0.9},
        sizeKey = "auraGlowSize", speedKey = "auraGlowSpeed", linesKey = "auraGlowDashCount",
        thicknessKey = "auraGlowDashThickness",
        defaultStyle = "pulse", defaultColor = {1, 0.84, 0, 0.9},
        enableLabel = "Show Aura Glow",
        styleOptions = AURA_GLOW_STYLE_OPTIONS,
        styleOrder = AURA_GLOW_STYLE_ORDER,
        solidSizeDefault = 2,
        onStyleChanged = function(targetStyle, val)
            targetStyle.auraGlowSize = AURA_GLOW_SIZE_RESETS[val] or 2
            targetStyle.auraGlowSpeed = AURA_GLOW_SPEED_RESETS[val] or 0.5
            targetStyle.auraGlowDashCount = 2
            targetStyle.auraGlowDashThickness = 4
        end,
    }, opts)
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
-- the top of this file exists for, and what the shared glow builder's row mode
-- gives every style dropdown.

-- One spec, both shapes. The stock path hands this straight to
-- BuildGlowStyleControls; the opts.row path reads the same keys, labels and
-- defaults out of it, so neither shape can drift from the other's store.
-- Nothing mutates it (BuildGlowStyleControls only reads cfg, and
-- onStyleChanged writes through its targetStyle argument), so it is safe as a
-- shared constant.
local BAR_AURA_EFFECT_CFG = {
    styleKey = "barAuraEffect", colorKey = "barAuraEffectColor", colorLabel = "Effect Color",
    color2Key = "barAuraColorShiftColor", color2Label = "Second Color", defaultColor2 = {1, 1, 1, 1},
    sizeKey = "barAuraEffectSize", speedKey = "barAuraEffectSpeed", linesKey = "barAuraEffectLines",
    thicknessKey = "barAuraEffectThickness",
    defaultStyle = "color", defaultColor = {1, 0.84, 0, 0.9},
    enableLabel = "Show Active Aura Indicator",
    enableKey = "barAuraIndicatorEnabled",
    deriveEnableFromEffect = true, effectKey = "barAuraEffect",
    styleOptions = BAR_AURA_EFFECT_STYLE_OPTIONS,
    styleOrder = BAR_AURA_EFFECT_STYLE_ORDER,
    solidSizeDefault = 2,
    onStyleChanged = function(targetStyle, val)
        targetStyle.barAuraEffectSize = AURA_GLOW_SIZE_RESETS[val] or 2
        targetStyle.barAuraEffectSpeed = AURA_GLOW_SPEED_RESETS[val] or 0.5
        targetStyle.barAuraEffectLines = 2
        targetStyle.barAuraEffectThickness = 4
    end,
}

local FILL_EFFECTS_TOOLTIP = {
    "Fill Effects",
    {"The bar fill breathes (pulse) or cycles color (color shift) while the aura is active. Use the preview toggle to see them without a live aura.", 1, 1, 1, true},
}

-- opts.row opts into the row grammar (RowWidgets.lua): the builder opens its
-- own two-column grid on `container` and returns the two columns. LEFT is the
-- border effect (style, its color, its per-style sliders); RIGHT is the two
-- fill effects and their children.
--
-- opts.singleRail (row mode only) suppresses that grid: an advanced settings
-- panel is ONE narrow column (AdvancedSettingsPanel.lua), where a two-column
-- split would leave ~150px per cell, so both halves rail onto `container`
-- itself in the order they are written. It is additive - the two tab callers
-- that omit it get byte-identical output - and railing onto the container is
-- also what keeps the panel's refresh seam intact, since
-- RefreshStructuralControls only routes to the panel rebuild while it can still
-- see the scroll's own _isAdvancedSettingsPanel marker.
--
-- Omitting opts.row keeps the full-width stock widgets.
local function BuildBarActiveAuraControls(container, styleTable, refreshCallback, opts)
    local rowMode = opts and opts.row == true

    -- The writes both shapes perform, hoisted so neither can wire a different
    -- store than the other. RefreshStructuralControls is on exactly the calls
    -- that change which further controls exist.
    local function ApplyPulseEnabled(val)
        styleTable.barAuraPulseEnabled = val
        refreshCallback()
        RefreshStructuralControls(container)
    end
    local function ApplyPulseSpeed(val)
        styleTable.barAuraPulseSpeed = val
        refreshCallback()
    end
    local function ApplyColorShiftEnabled(val)
        styleTable.barAuraColorShiftEnabled = val
        refreshCallback()
        RefreshStructuralControls(container)
    end
    local function ApplyColorShiftSpeed(val)
        styleTable.barAuraColorShiftSpeed = val
        refreshCallback()
    end

    if not rowMode then
        BuildGlowStyleControls(container, styleTable, refreshCallback, BAR_AURA_EFFECT_CFG, opts)
    end

    -- Fill effects apply while the indicator is enabled, independent of the
    -- border effect choice. Same enable derivation as the builder above so
    -- these controls collapse with the section in override mode.
    local enabledVal = rawget(styleTable, "barAuraIndicatorEnabled")
    if enabledVal == nil and rawget(styleTable, "barAuraEffect") ~= nil then
        enabledVal = (styleTable.barAuraEffect or "none") ~= "none"
    end
    if enabledVal == nil and opts and opts.fallbackStyle then
        enabledVal = opts.fallbackStyle.barAuraIndicatorEnabled
        if enabledVal == nil then
            enabledVal = (opts.fallbackStyle.barAuraEffect or "none") ~= "none"
        end
    end
    local overrideDisabled = opts and opts.isOverride == true and enabledVal == false
    if overrideDisabled then
        -- The preview toggle disappears with the disabled section; make sure
        -- a preview it owned doesn't keep rendering.
        if CS.selectedGroup and CS.selectedButton and CooldownCompanion.SetBarAuraEffectPreview then
            CooldownCompanion:SetBarAuraEffectPreview(CS.selectedGroup, CS.selectedButton, false)
        end
        if not rowMode then
            -- The stock path already drew the enable checkbox above and
            -- BuildGlowStyleControls stopped there; nothing else to add.
            return
        end
    end

    if rowMode then
        local effectsLeft, effectsRight
        if opts.singleRail then
            effectsLeft, effectsRight = container, container
        else
            effectsLeft, effectsRight = BeginRowGrid(container)
        end

        -- The LEFT column IS the border effect, which is exactly what the
        -- shared glow builder draws - style, its color, its per-style sliders,
        -- and in override mode the section's own enable toggle (nothing else
        -- gates the section there, and it stops at that toggle when the
        -- indicator is off). Delegating rather than re-implementing is what
        -- keeps the two shapes on one store: the tab callers that omit
        -- opts.isOverride get exactly the rows they got before.
        BuildGlowStyleControls(effectsLeft, styleTable, refreshCallback, BAR_AURA_EFFECT_CFG, {
            row = true,
            rightColumn = effectsRight,
            isOverride = opts.isOverride,
            fallbackStyle = opts.fallbackStyle,
            infoButtons = opts.infoButtons,
        })

        if overrideDisabled then
            return effectsLeft, effectsRight
        end

        local pulseRow = AddCheckboxRow(effectsRight, {
            label = "Pulse Bar Fill",
            value = styleTable.barAuraPulseEnabled == true,
            onChange = ApplyPulseEnabled,
        })
        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label.
        AnchorRowBadge(pulseRow, CreateInfoButton(pulseRow.frame, pulseRow.frame, "LEFT", "LEFT", 0, 0,
            FILL_EFFECTS_TOOLTIP, opts.infoButtons))

        if styleTable.barAuraPulseEnabled == true then
            AddSliderRow(effectsRight, {
                label = "Pulse Duration",
                indent = true,
                min = 0.1, max = 2.0, step = 0.05,
                value = styleTable.barAuraPulseSpeed or 0.5,
                onChange = ApplyPulseSpeed,
            })
        end

        AddCheckboxRow(effectsRight, {
            label = "Color Shift Bar Fill",
            value = styleTable.barAuraColorShiftEnabled == true,
            onChange = ApplyColorShiftEnabled,
        })

        if styleTable.barAuraColorShiftEnabled == true then
            AddSliderRow(effectsRight, {
                label = "Shift Duration",
                indent = true,
                min = 0.1, max = 2.0, step = 0.05,
                value = styleTable.barAuraColorShiftSpeed or 0.5,
                onChange = ApplyColorShiftSpeed,
            })

            AddColorRow(effectsRight, {
                label = "Shift Color",
                indent = true,
                tbl = styleTable,
                key = "barAuraColorShiftColor",
                default = {1, 1, 1, 1},
                hasAlpha = true,
                onConfirm = refreshCallback,
                onChange = refreshCallback,
            })
        end

        return effectsLeft, effectsRight
    end

    local pulseCb = AceGUI:Create("CheckBox")
    pulseCb:SetLabel("Pulse Bar Fill")
    pulseCb:SetValue(styleTable.barAuraPulseEnabled == true)
    pulseCb:SetFullWidth(true)
    pulseCb:SetCallback("OnValueChanged", function(widget, event, val)
        ApplyPulseEnabled(val)
    end)
    container:AddChild(pulseCb)
    CreateInfoButton(pulseCb.frame, pulseCb.checkbg, "LEFT", "RIGHT", pulseCb.text:GetStringWidth() + 4, 0,
        FILL_EFFECTS_TOOLTIP, pulseCb)

    if styleTable.barAuraPulseEnabled == true then
        local pulseSpeed = AceGUI:Create("Slider")
        pulseSpeed:SetLabel("Pulse Duration")
        pulseSpeed:SetSliderValues(0.1, 2.0, 0.05)
        pulseSpeed:SetValue(styleTable.barAuraPulseSpeed or 0.5)
        pulseSpeed:SetFullWidth(true)
        pulseSpeed:SetCallback("OnValueChanged", function(widget, event, val)
            ApplyPulseSpeed(val)
        end)
        container:AddChild(pulseSpeed)
    end

    local shiftCb = AceGUI:Create("CheckBox")
    shiftCb:SetLabel("Color Shift Bar Fill")
    shiftCb:SetValue(styleTable.barAuraColorShiftEnabled == true)
    shiftCb:SetFullWidth(true)
    shiftCb:SetCallback("OnValueChanged", function(widget, event, val)
        ApplyColorShiftEnabled(val)
    end)
    container:AddChild(shiftCb)

    if styleTable.barAuraColorShiftEnabled == true then
        local shiftSpeed = AceGUI:Create("Slider")
        shiftSpeed:SetLabel("Shift Duration")
        shiftSpeed:SetSliderValues(0.1, 2.0, 0.05)
        shiftSpeed:SetValue(styleTable.barAuraColorShiftSpeed or 0.5)
        shiftSpeed:SetFullWidth(true)
        shiftSpeed:SetCallback("OnValueChanged", function(widget, event, val)
            ApplyColorShiftSpeed(val)
        end)
        container:AddChild(shiftSpeed)

        AddColorPicker(container, styleTable, "barAuraColorShiftColor", "Shift Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
    end
end

local KPH_STYLE_OPTIONS = {["solid"] = "Solid Border", ["overlay"] = "Overlay"}
local KPH_STYLE_ORDER = {"solid", "overlay"}

local function BuildKeyPressHighlightControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "keyPressHighlightStyle", colorKey = "keyPressHighlightColor", colorLabel = "Highlight Color",
        sizeKey = "keyPressHighlightSize",
        defaultStyle = "solid", defaultColor = {1, 1, 1, 0.4},
        enableLabel = "Show Key Press Highlight",
        styleOptions = KPH_STYLE_OPTIONS,
        styleOrder = KPH_STYLE_ORDER,
    }, opts)
end

-- opts.row: LEFT the toggle and the font trio, RIGHT the two rows that decide
-- how the name reads on the bar - which side it sits on and its color.
local function BuildBarNameTextControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    local function ApplyShowNameText(val)
        styleTable.showBarNameText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end

    if opts.row then
        local right = opts.rightColumn or container

        AddCheckboxRow(container, {
            label = "Show Name Text",
            value = styleTable.showBarNameText ~= false,
            indent = opts.indent,
            onChange = ApplyShowNameText,
        })

        if styleTable.showBarNameText ~= false then
            AddFontControls(container, styleTable, "barName", {size = 10, sizeMin = 6, sizeMax = 24},
                refreshCallback, { row = true, indent = true })

            AddCheckboxRow(right, {
                label = "Flip Name Text",
                value = styleTable.barNameTextReverse or false,
                onChange = function(val)
                    styleTable.barNameTextReverse = val
                    refreshCallback()
                end,
            })
            -- deferCommit is deliberately absent, matching the AddColorPicker
            -- call the stock path makes.
            AddColorRow(right, {
                label = "Font Color",
                tbl = styleTable,
                key = "barNameFontColor",
                default = {1, 1, 1, 1},
                hasAlpha = true,
                onConfirm = refreshCallback,
                onChange = refreshCallback,
            })
        end
        return
    end

    local showNameCb = AceGUI:Create("CheckBox")
    showNameCb:SetLabel("Show Name Text")
    showNameCb:SetValue(styleTable.showBarNameText ~= false)
    showNameCb:SetFullWidth(true)
    showNameCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showBarNameText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(showNameCb)

    if styleTable.showBarNameText ~= false then
        local flipNameCheck = AceGUI:Create("CheckBox")
        flipNameCheck:SetLabel("Flip Name Text")
        flipNameCheck:SetValue(styleTable.barNameTextReverse or false)
        flipNameCheck:SetFullWidth(true)
        flipNameCheck:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barNameTextReverse = val
            refreshCallback()
        end)
        container:AddChild(flipNameCheck)

        AddFontControls(container, styleTable, "barName", {size = 10, sizeMin = 6, sizeMax = 24}, refreshCallback)
        AddColorPicker(container, styleTable, "barNameFontColor", "Font Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
    end
end

-- opts.row: LEFT the toggle and the font trio, RIGHT the wording and color of
-- the text itself.
local function BuildBarReadyTextControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    local function ApplyShowReadyText(val)
        styleTable.showBarReadyText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end

    if opts.row then
        local right = opts.rightColumn or container

        AddCheckboxRow(container, {
            label = "Show Ready Text",
            value = styleTable.showBarReadyText or false,
            indent = opts.indent,
            onChange = ApplyShowReadyText,
        })

        if styleTable.showBarReadyText then
            AddFontControls(container, styleTable, "barReady", {sizeMin = 6, sizeMax = 24},
                refreshCallback, { row = true, indent = true })

            local readyRow = AddEditBoxRow(right, {
                label = "Ready Text",
                value = styleTable.barReadyText or "Ready",
                onEnterPressed = function(val)
                    styleTable.barReadyText = val
                    refreshCallback()
                end,
            })
            if readyRow.editbox and readyRow.editbox.Instructions then
                readyRow.editbox.Instructions:Hide()
            end

            -- deferCommit is deliberately absent, matching the AddColorPicker
            -- call the stock path makes.
            AddColorRow(right, {
                label = "Ready Text Color",
                tbl = styleTable,
                key = "barReadyTextColor",
                default = {0.2, 1.0, 0.2, 1.0},
                hasAlpha = true,
                onConfirm = refreshCallback,
                onChange = refreshCallback,
            })
        end
        return
    end

    local showReadyCb = AceGUI:Create("CheckBox")
    showReadyCb:SetLabel("Show Ready Text")
    showReadyCb:SetValue(styleTable.showBarReadyText or false)
    showReadyCb:SetFullWidth(true)
    showReadyCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showBarReadyText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(showReadyCb)

    if styleTable.showBarReadyText then
        local readyTextBox = AceGUI:Create("EditBox")
        if readyTextBox.editbox.Instructions then readyTextBox.editbox.Instructions:Hide() end
        readyTextBox:SetLabel("Ready Text")
        readyTextBox:SetText(styleTable.barReadyText or "Ready")
        readyTextBox:SetFullWidth(true)
        readyTextBox:SetCallback("OnEnterPressed", function(widget, event, val)
            styleTable.barReadyText = val
            refreshCallback()
        end)
        container:AddChild(readyTextBox)

        AddColorPicker(container, styleTable, "barReadyTextColor", "Ready Text Color", {0.2, 1.0, 0.2, 1.0}, true, refreshCallback, refreshCallback)
        AddFontControls(container, styleTable, "barReady", {sizeMin = 6, sizeMax = 24}, refreshCallback)
    end
end

------------------------------------------------------------------------
-- Text Mode — Text Colors
------------------------------------------------------------------------
-- opts.row: four rows at most, reading top to bottom as background then
-- border, so they stay in one column (the <4-rows rule).
-- Row grammar only (RowWidgets.lua): the backdrop and the border that frames
-- it, in one column. opts.indent makes them child rows. The pre-redesign
-- full-width stock shape had no call sites left after the conversion packets.
local function BuildTextBackgroundControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    -- deferCommit is deliberately absent throughout, matching the
    -- AddColorPicker calls this section used to make.
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

-- opts.row: LEFT what the text is drawn with, RIGHT how the line is laid out.
local function BuildTextFontControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    if opts.row then
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
        return
    end

    AddFontControls(container, styleTable, "text", {sizeMin = 6, sizeMax = 72}, refreshCallback)

    local alignDrop = AceGUI:Create("Dropdown")
    alignDrop:SetLabel("Alignment")
    alignDrop:SetList({LEFT = "Left", CENTER = "Center", RIGHT = "Right"})
    alignDrop:SetValue(styleTable.textAlignment or "LEFT")
    alignDrop:SetFullWidth(true)
    alignDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.textAlignment = val
        refreshCallback()
    end)
    container:AddChild(alignDrop)

    local shadowCb = AceGUI:Create("CheckBox")
    shadowCb:SetLabel("Text Shadow")
    shadowCb:SetValue(styleTable.textShadow == true)
    shadowCb:SetFullWidth(true)
    shadowCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.textShadow = val or false
        refreshCallback()
    end)
    container:AddChild(shadowCb)
end

-- Row grammar only: the row sizes itself and the Ready Color gear rides the
-- row's badge chain rather than a hand-placed anchor. Three rows, so they stay
-- in one column.
local function BuildTextColorsControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    -- Single rail (AdvancedSettingsPanel.lua): one row straight onto the panel
    -- scroll. The CDC-EditBoxRow embeds a stock EditBox, so the raw frame the
    -- Instructions text hangs on is still reachable through row.editbox.
    local function BuildReadyTextAdvanced(panel)
        local readyRow = AddEditBoxRow(panel, {
            label = "Ready Text",
            value = styleTable.textReadyText or "Ready",
            onEnterPressed = function(val)
                styleTable.textReadyText = val
                refreshCallback()
            end,
        })
        if readyRow.editbox and readyRow.editbox.Instructions then
            readyRow.editbox.Instructions:Hide()
        end
    end

    -- deferCommit is deliberately absent throughout, matching the
    -- AddColorPicker calls these rows replaced.
    local function TextColorRow(rowLabel, key, default)
        return AddColorRow(container, {
            label = rowLabel,
            indent = opts.indent,
            tbl = styleTable,
            key = key,
            default = default,
            hasAlpha = true,
            onConfirm = refreshCallback,
            onChange = refreshCallback,
        })
    end

    TextColorRow("Text Color", "textFontColor", {1, 1, 1, 1})
    TextColorRow("Cooldown Color", "textCooldownColor", {1, 0.3, 0.3, 1})
    local readyRow = TextColorRow("Ready Color", "textReadyColor", {0.2, 1.0, 0.2, 1})

    -- AnchorRowBadge handles the placement: the gear chains off the end of the
    -- row's label, so no manual re-anchor is needed here.
    AddAdvancedToggle(readyRow, opts.advancedKey or "textReadyText",
        opts.infoButtons or tabInfoButtons, nil, {
            title = "Ready Color Advanced",
            build = BuildReadyTextAdvanced,
        })
end

------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
ST._BuildCooldownTextControls = BuildCooldownTextControls
ST._AddDurationFormatDropdown = AddDurationFormatDropdown
ST._BuildAuraTextControls = BuildAuraTextControls
ST._AddPandemicMarkerControls = AddPandemicMarkerControls
ST._BuildAuraStackTextControls = BuildAuraStackTextControls
ST._BuildAuraDurationSwipeControls = BuildAuraDurationSwipeControls
ST._BuildAuraDurationSwipeAdvancedControls = BuildAuraDurationSwipeAdvancedControls
ST._BuildKeybindTextControls = BuildKeybindTextControls
ST._BuildChargeTextControls = BuildChargeTextControls
ST._BuildBorderControls = BuildBorderControls
ST._BuildBackgroundColorControls = BuildBackgroundColorControls
ST._BuildDesaturationControls = BuildDesaturationControls
ST._BuildShowTooltipsControls = BuildShowTooltipsControls
ST._BuildShowOutOfRangeControls = BuildShowOutOfRangeControls
ST._BuildShowGCDSwipeControls = BuildShowGCDSwipeControls
ST._BuildCooldownSwipeControls = BuildCooldownSwipeControls
ST._BuildIconFillTimerControls = BuildIconFillTimerControls
ST._BuildIconFillTimerAdvancedControls = BuildIconFillTimerAdvancedControls
ST._BuildLossOfControlControls = BuildLossOfControlControls
ST._BuildUnusableDimmingControls = BuildUnusableDimmingControls
ST._BuildIconTintControls = BuildIconTintControls
ST._BuildAssistedHighlightControls = BuildAssistedHighlightControls
ST._BuildProcGlowControls = BuildProcGlowControls
ST._BuildAuraGlowControls = BuildAuraGlowControls
ST._BuildBarActiveAuraControls = BuildBarActiveAuraControls
ST._BuildReadyGlowControls = BuildReadyGlowControls
ST._BuildKeyPressHighlightControls = BuildKeyPressHighlightControls
ST._BuildBarNameTextControls = BuildBarNameTextControls
ST._BuildBarReadyTextControls = BuildBarReadyTextControls
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
ST._GetAuraStackMaxStatusText = GetAuraStackMaxStatusText
