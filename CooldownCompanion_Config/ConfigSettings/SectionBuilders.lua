local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders
local AddBorderRenderModeDropdown = ST._AddBorderRenderModeDropdown

-- Imports from RowWidgets.lua (the row grammar). Only BuildBarActiveAuraControls'
-- opts.row branch uses these today; every other builder here is still stock.
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddColorRow = ST._AddColorRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid

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

local function AddAuraCandidateRow(container, spellID, onRemove)
    local row = AceGUI:Create("SimpleGroup")
    row:SetLayout("Flow")
    row:SetFullWidth(true)

    local info = C_Spell.GetSpellInfo(spellID)
    local name = info and info.name or ("Spell " .. spellID)

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

local function AddAuraStackMaxStatusLabel(container, maxStacks)
    local statusLabel = AceGUI:Create("Label")
    statusLabel:SetText(GetAuraStackMaxStatusText(maxStacks))
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

local function ApplyOverrideCheckboxIndent(checkbox, opts)
    if opts and opts.isOverride then
        ApplyCheckboxIndent(checkbox, 20)
    end
end

local function AddDurationFormatDropdown(container, settings, refreshCallback, opts)
    if not (container and settings and CooldownCompanion.GetDurationFormatOptions) then
        return nil
    end

    local formatOptions, formatOrder = CooldownCompanion:GetDurationFormatOptions()
    local durationDrop = AceGUI:Create("Dropdown")
    durationDrop:SetLabel("Duration Format")
    durationDrop:SetList(formatOptions, formatOrder)
    durationDrop:SetValue(CooldownCompanion.GetDurationFormat(settings))
    durationDrop:SetFullWidth(true)
    durationDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.durationFormat = CooldownCompanion.NormalizeDurationFormat(val)
        settings.decimalTimers = nil
        if refreshCallback then
            refreshCallback()
        end
    end)
    container:AddChild(durationDrop)
    return durationDrop
end

local function BuildCooldownTextControls(container, styleTable, refreshCallback, opts)
    local fallbackStyle = opts and opts.fallbackStyle
    local showCooldownText = styleTable.showCooldownText
    if showCooldownText == nil and type(fallbackStyle) == "table" then
        showCooldownText = fallbackStyle.showCooldownText
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

local function AddPandemicMarkerControls(container, styleTable, refreshCallback, rebuildCallback)
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

    CreateInfoButton(enableCb.frame, enableCb.checkbg, "LEFT", "RIGHT", enableCb.text:GetStringWidth() + 4, 0, {
        "Pandemic Marker",
        {"Marks the aura duration text during the last 30% of the aura's duration — the refresh window where recasting extends the remaining time instead of wasting it. Blizzard evaluates the timing; the addon never reads combat values.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"On by default for debuffs on your target; each entry's Aura tab has the per-entry switch. If a game update ever breaks this display, turn it off here to restore standard duration text.", 1, 1, 1, true},
    }, enableCb)

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

local function BuildAuraTextControls(container, styleTable, refreshCallback, opts)
    local fallbackStyle = opts and opts.fallbackStyle
    local showAuraText = styleTable.showAuraText
    if showAuraText == nil and type(fallbackStyle) == "table" then
        showAuraText = fallbackStyle.showAuraText
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

    CreateInfoButton(auraTextCb.frame, auraTextCb.checkbg, "LEFT", "RIGHT", auraTextCb.text:GetStringWidth() + 4, 0, {
        "Shared Position",
        {"Position is shared with Cooldown Text by default. Enable 'Separate Text Positions' below to use independent positions.", 1, 1, 1, true},
    }, auraTextCb)

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

        CreateInfoButton(sepPosCb.frame, sepPosCb.checkbg, "LEFT", "RIGHT", sepPosCb.text:GetStringWidth() + 4, 0, {
            "Separate Text Positions",
            {"When enabled, aura duration text and cooldown text use independent positions and can show at the same time. Aura text position controls appear below when toggled on; cooldown text position is in the Cooldown Text section.", 1, 1, 1, true},
        }, sepPosCb)

        if styleTable.separateTextPositions then
            AddAnchorDropdown(container, styleTable, "auraTextAnchor", "TOPLEFT", refreshCallback)
            AddOffsetSliders(container, styleTable, "auraTextXOffset", "auraTextYOffset", {x = 2, y = -2}, refreshCallback)
        end

        AddPandemicMarkerControls(container, styleTable, refreshCallback, function()
            RefreshStructuralControls(container)
        end)
    end
end

local function BuildAuraStackTextControls(container, styleTable, refreshCallback, opts)
    local fallbackStyle = opts and opts.fallbackStyle
    local showAuraStackText = styleTable.showAuraStackText
    if showAuraStackText == nil and type(fallbackStyle) == "table" then
        showAuraStackText = fallbackStyle.showAuraStackText
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

local function BuildKeybindTextControls(container, styleTable, refreshCallback, opts)
    local label = opts and opts.label or KEYBIND_CUSTOM_LABEL
    local tooltip = opts and opts.tooltip or KEYBIND_CUSTOM_TOOLTIP
    local kbCb = AceGUI:Create("CheckBox")
    kbCb:SetLabel(label)
    kbCb:SetValue(styleTable.showKeybindText or false)
    kbCb:SetFullWidth(true)
    kbCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showKeybindText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(kbCb)

    CreateInfoButton(kbCb.frame, kbCb.checkbg, "LEFT", "RIGHT", kbCb.text:GetStringWidth() + 4, 0, tooltip, kbCb)

    if styleTable.showKeybindText then
        AddAnchorDropdown(container, styleTable, "keybindAnchor", "TOPRIGHT", refreshCallback)
        AddOffsetSliders(container, styleTable, "keybindXOffset", "keybindYOffset", {x = -2, y = -2}, refreshCallback)
        AddFontControls(container, styleTable, "keybind", {size = 10, sizeMin = 6, sizeMax = 24}, refreshCallback)
        AddColorPicker(container, styleTable, "keybindFontColor", "Font Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
    end
end

local function BuildChargeTextControls(container, styleTable, refreshCallback)
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

local function BuildBorderControls(container, styleTable, refreshCallback)
    local renderMode = AddBorderRenderModeDropdown(container, styleTable, "borderRenderMode", function()
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderSlider = AceGUI:Create("Slider")
        borderSlider:SetLabel("Border Size")
        borderSlider:SetSliderValues(0, 5, 0.1)
        borderSlider:SetValue(styleTable.borderSize or ST.DEFAULT_BORDER_SIZE)
        borderSlider:SetFullWidth(true)
        borderSlider:SetDisabled(borderThicknessLocked)
        borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if borderThicknessLocked then return end
            styleTable.borderSize = val
            refreshCallback()
        end)
        container:AddChild(borderSlider)
    end

    AddColorPicker(container, styleTable, "borderColor", "Border Color", {0, 0, 0, 1}, true, refreshCallback, refreshCallback)
end

local function BuildBackgroundColorControls(container, styleTable, refreshCallback, setWidth)
    local picker = AddColorPicker(container, styleTable, "backgroundColor", "Background Color", {0, 0, 0, 0.5}, true, refreshCallback, refreshCallback)
    if setWidth then setWidth(picker) end
end

local function BuildDesaturationControls(container, styleTable, refreshCallback)
    local desatCb = AceGUI:Create("CheckBox")
    desatCb:SetLabel("Show Desaturate On Cooldown")
    desatCb:SetValue(styleTable.desaturateOnCooldown or false)
    desatCb:SetFullWidth(true)
    desatCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.desaturateOnCooldown = val
        refreshCallback()
    end)
    container:AddChild(desatCb)
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

local function BuildTooltipBehaviorControls(container, styleTable, refreshCallback)
    local drop = AceGUI:Create("Dropdown")
    drop:SetLabel("Tooltip Position")
    drop:SetList(TOOLTIP_ANCHOR_LIST, TOOLTIP_ANCHOR_ORDER)
    drop:SetValue(styleTable.tooltipAnchor or "default")
    drop:SetFullWidth(true)
    drop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.tooltipAnchor = val
        refreshCallback()
    end)
    container:AddChild(drop)

    local combatCb = AceGUI:Create("CheckBox")
    combatCb:SetLabel("Hide Tooltips in Combat")
    combatCb:SetValue(styleTable.tooltipHideInCombat == true)
    combatCb:SetFullWidth(true)
    combatCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.tooltipHideInCombat = val
        refreshCallback()
    end)
    container:AddChild(combatCb)

    return drop, combatCb
end

-- opts.advanced: attach the gear that opens Tooltip Position / Hide in Combat
-- (group-level tabs only — those keys are group style, with no per-entry
-- override section, so the override editor calls this without opts).
--
-- opts.row opts into the row grammar (RowWidgets.lua): the toggle becomes a
-- CDC-CheckBoxRow whose gear chains off the label. Omitting it keeps the
-- full-width stock checkbox every other call site draws today.
local function BuildShowTooltipsControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    local cb
    if opts.row then
        cb = ST._AddCheckboxRow(container, {
            label = "Show Tooltips",
            value = styleTable.showTooltips == true,
            indent = opts.indent,
            onChange = function(val)
                styleTable.showTooltips = val
                refreshCallback()
            end,
        })
    else
        cb = AceGUI:Create("CheckBox")
        cb:SetLabel("Show Tooltips")
        cb:SetValue(styleTable.showTooltips == true)
        cb:SetFullWidth(true)
        cb:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.showTooltips = val
            refreshCallback()
        end)
        container:AddChild(cb)
    end

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

local function BuildShowOutOfRangeControls(container, styleTable, refreshCallback)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Show Out of Range")
    cb:SetValue(styleTable.showOutOfRange or false)
    cb:SetFullWidth(true)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showOutOfRange = val
        refreshCallback()
    end)
    container:AddChild(cb)
    return cb
end

local function BuildIconTintControls(container, styleTable, refreshCallback, opts)
    -- opts.setWidth: width setter for two-column hosts; applies to the
    -- toggles and color pickers alike. Absent = full width (advanced panels).
    -- Two-column reading order: the always-present colors group first, then a
    -- row break, then each tint toggle beside its own color when enabled.
    local setWidth = (opts and opts.setWidth) or function(w) w:SetFullWidth(true) end

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
        styleTable.iconCooldownTintEnabled = val
        refreshCallback()
        RefreshStructuralControls(container)
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
            styleTable.iconAuraTintEnabled = val
            refreshCallback()
            RefreshStructuralControls(container)
        end)
        container:AddChild(auraTintCb)

        if styleTable.iconAuraTintEnabled then
            setWidth(AddColorPicker(container, styleTable, "iconAuraTintColor", "Aura Active Icon Color", {0, 0.925, 1, 1}, true, refreshCallback, refreshCallback))
        end
    end
end

local function BuildShowGCDSwipeControls(container, styleTable, refreshCallback)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Show GCD Swipe")
    cb:SetValue(styleTable.showGCDSwipe == true)
    cb:SetFullWidth(true)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showGCDSwipe = val
        refreshCallback()
    end)
    container:AddChild(cb)
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

local function BuildCooldownSwipeControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local disabledByIconFill = IsIconFillTimerEnabled(styleTable, opts)

    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Show Cooldown Swipe")
    cb:SetValue(styleTable.showCooldownSwipe ~= false)
    cb:SetFullWidth(true)
    cb:SetDisabled(disabledByIconFill)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        if disabledByIconFill then return end
        styleTable.showCooldownSwipe = val
        refreshCallback()
    end)
    container:AddChild(cb)

    local reverseCb = AceGUI:Create("CheckBox")
    reverseCb:SetLabel("Reverse Swipe")
    reverseCb:SetValue(styleTable.cooldownSwipeReverse or false)
    reverseCb:SetFullWidth(true)
    reverseCb:SetDisabled(disabledByIconFill)
    reverseCb:SetCallback("OnValueChanged", function(widget, event, val)
        if disabledByIconFill then return end
        styleTable.cooldownSwipeReverse = val
        refreshCallback()
    end)
    container:AddChild(reverseCb)
    ApplyOverrideCheckboxIndent(reverseCb, opts)

    local fillCb = AceGUI:Create("CheckBox")
    fillCb:SetLabel("Show Swipe Fill")
    fillCb:SetValue(styleTable.showCooldownSwipeFill ~= false)
    fillCb:SetFullWidth(true)
    fillCb:SetDisabled(disabledByIconFill)
    fillCb:SetCallback("OnValueChanged", function(widget, event, val)
        if disabledByIconFill then return end
        styleTable.showCooldownSwipeFill = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(fillCb)
    ApplyOverrideCheckboxIndent(fillCb, opts)

    -- Swipe Fill Opacity (only when fill is visible)
    if styleTable.showCooldownSwipeFill ~= false then
        local alphaSlider = AceGUI:Create("Slider")
        alphaSlider:SetLabel("Swipe Fill Opacity")
        alphaSlider:SetSliderValues(0, 1, 0.05)
        alphaSlider:SetIsPercent(true)
        alphaSlider:SetValue(styleTable.cooldownSwipeAlpha or 0.8)
        alphaSlider:SetFullWidth(true)
        if alphaSlider.SetDisabled then alphaSlider:SetDisabled(disabledByIconFill) end
        alphaSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if disabledByIconFill then return end
            styleTable.cooldownSwipeAlpha = val
            refreshCallback()
        end)
        container:AddChild(alphaSlider)
    end

    local edgeCb = AceGUI:Create("CheckBox")
    edgeCb:SetLabel("Show Swipe Edge")
    edgeCb:SetValue(styleTable.showCooldownSwipeEdge ~= false)
    edgeCb:SetFullWidth(true)
    edgeCb:SetDisabled(disabledByIconFill)
    edgeCb:SetCallback("OnValueChanged", function(widget, event, val)
        if disabledByIconFill then return end
        styleTable.showCooldownSwipeEdge = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(edgeCb)
    ApplyOverrideCheckboxIndent(edgeCb, opts)

    -- Swipe Edge Color (only when edge is visible)
    if styleTable.showCooldownSwipeEdge ~= false then
        local edgeColor = AddColorPicker(container, styleTable, "cooldownSwipeEdgeColor", "Swipe Edge Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        if edgeColor.SetDisabled then edgeColor:SetDisabled(disabledByIconFill) end
    end
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

local function BuildAuraDurationSwipeAdvancedControls(container, styleTable, refreshCallback, opts)
    local blizzardStyleActive = styleTable.auraUseBlizzardSwipe == true

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
    ApplyOverrideCheckboxIndent(blizzardCb, opts)

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
    ApplyOverrideCheckboxIndent(reverseCb, opts)

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
    ApplyOverrideCheckboxIndent(fillCb, opts)

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
    ApplyOverrideCheckboxIndent(edgeCb, opts)

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
        BuildIconFillTimerAdvancedControls(container, styleTable, refreshCallback)
    end

    return cb
end

BuildIconFillTimerAdvancedControls = function(container, styleTable, refreshCallback)
    if styleTable.iconFillEnabled ~= true then
        return
    end

    local iconFillOrientation = styleTable.iconFillOrientation == "horizontal" and "horizontal" or "vertical"

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

local function BuildLossOfControlControls(container, styleTable, refreshCallback)
    local locCb = AceGUI:Create("CheckBox")
    locCb:SetLabel("Show Loss of Control")
    locCb:SetValue(styleTable.showLossOfControl or false)
    locCb:SetFullWidth(true)
    locCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showLossOfControl = val
        refreshCallback()
    end)
    container:AddChild(locCb)
    return locCb
end

local function BuildUnusableVisualModeControls(container, styleTable, refreshCallback)
    local dimCb = AceGUI:Create("CheckBox")
    dimCb:SetLabel("Dim Icon")
    dimCb:SetValue(ST.UnusableVisualUsesDimTint(styleTable))
    dimCb:SetFullWidth(true)
    dimCb:SetCallback("OnValueChanged", function(widget, event, val)
        ST.SetUnusableVisualMode(styleTable, val == true, ST.UnusableVisualUsesDesaturation(styleTable))
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(dimCb)

    local desatCb = AceGUI:Create("CheckBox")
    desatCb:SetLabel("Desaturate Icon")
    desatCb:SetValue(ST.UnusableVisualUsesDesaturation(styleTable))
    desatCb:SetFullWidth(true)
    desatCb:SetCallback("OnValueChanged", function(widget, event, val)
        ST.SetUnusableVisualMode(styleTable, ST.UnusableVisualUsesDimTint(styleTable), val == true)
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(desatCb)
end

-- opts.row opts into the row grammar (RowWidgets.lua). The advanced gear and
-- its Dim/Desaturate panel are unchanged either way.
local function BuildUnusableDimmingControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    local unusableCb
    if opts.row then
        unusableCb = ST._AddCheckboxRow(container, {
            label = "Show Unusable Visual",
            value = styleTable.showUnusable == true,
            indent = opts.indent,
            onChange = function(val)
                styleTable.showUnusable = val == true
                refreshCallback()
                RefreshStructuralControls(container)
            end,
        })
    else
        unusableCb = AceGUI:Create("CheckBox")
        unusableCb:SetLabel("Show Unusable Visual")
        unusableCb:SetValue(styleTable.showUnusable == true)
        unusableCb:SetFullWidth(true)
        unusableCb:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.showUnusable = val == true
            refreshCallback()
            RefreshStructuralControls(container)
        end)
        container:AddChild(unusableCb)
    end

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

local function BuildAssistedHighlightControls(container, styleTable, refreshCallback, opts)
    local hostileOnlyCb = AceGUI:Create("CheckBox")
    hostileOnlyCb:SetLabel("Hostile Target Only")
    hostileOnlyCb:SetValue(styleTable.assistedHighlightHostileTargetOnly ~= false)
    hostileOnlyCb:SetFullWidth(true)
    hostileOnlyCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.assistedHighlightHostileTargetOnly = val
        refreshCallback()
    end)
    container:AddChild(hostileOnlyCb)
    ApplyOverrideCheckboxIndent(hostileOnlyCb, opts)

    local highlightStyles = {
        blizzard = "Blizzard (Marching Ants)",
        proc = "Proc Glow",
        solid = "Solid Border",
    }
    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Highlight Style")
    styleDrop:SetList(highlightStyles)
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
-- Shared slider block used by both glow style controls and bar effect
-- controls. Builds conditional size/thickness/speed sliders based on
-- the current glow style.
--
-- keys = { size = "...", thickness = "...", speed = "...", lines = "..." }
-- pixelSizeMin: minimum for the pixel "Line Length" slider (1 for glow
--   style controls, 2 for bar effect controls)
local function BuildGlowSliders(container, styleTable, currentStyle, keys, refreshCallback, pixelSizeMin)
    if currentStyle == "solid" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or keys.solidSizeDefault or 5)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    elseif currentStyle == "pulsingBorder" or currentStyle == "pulse" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or keys.solidSizeDefault or 2)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Pulse Duration")
        speedSlider:SetSliderValues(0.1, 2.0, 0.05)
        speedSlider:SetValue(styleTable[keys.speed] or 0.5)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "pixel" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Line Length")
        sizeSlider:SetSliderValues(pixelSizeMin, 12, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or 8)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local thicknessSlider = AceGUI:Create("Slider")
        thicknessSlider:SetLabel("Line Thickness")
        thicknessSlider:SetSliderValues(1, 6, 0.1)
        thicknessSlider:SetValue(styleTable[keys.thickness] or 4)
        thicknessSlider:SetFullWidth(true)
        thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.thickness] = val
            refreshCallback()
        end)
        container:AddChild(thicknessSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Speed")
        speedSlider:SetSliderValues(10, 200, 0.1)
        speedSlider:SetValue(styleTable[keys.speed] or 50)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)

        if keys.lines then
            local linesSlider = AceGUI:Create("Slider")
            linesSlider:SetLabel("Number of Lines")
            linesSlider:SetSliderValues(1, 16, 1)
            linesSlider:SetValue(styleTable[keys.lines] or 8)
            linesSlider:SetFullWidth(true)
            linesSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable[keys.lines] = val
                refreshCallback()
            end)
            container:AddChild(linesSlider)
        end
    elseif currentStyle == "glow" or currentStyle == "proc" or currentStyle == "ants" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Glow Size")
        sizeSlider:SetSliderValues(0, 60, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or (currentStyle == "ants" and 23 or 30))
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    elseif currentStyle == "colorShift" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or keys.solidSizeDefault or 2)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Shift Duration")
        speedSlider:SetSliderValues(0.1, 2.0, 0.05)
        speedSlider:SetValue(styleTable[keys.speed] or 0.8)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "dashes" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Dash Length")
        sizeSlider:SetSliderValues(2, 20, 0.5)
        sizeSlider:SetValue(styleTable[keys.size] or 8)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        if keys.thickness then
            local thicknessSlider = AceGUI:Create("Slider")
            thicknessSlider:SetLabel("Dash Thickness")
            thicknessSlider:SetSliderValues(1, 8, 0.5)
            thicknessSlider:SetValue(styleTable[keys.thickness] or 4)
            thicknessSlider:SetFullWidth(true)
            thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable[keys.thickness] = val
                refreshCallback()
            end)
            container:AddChild(thicknessSlider)
        end

        if keys.lines then
            local countSlider = AceGUI:Create("Slider")
            countSlider:SetLabel("Number of Dashes")
            countSlider:SetSliderValues(1, 8, 1)
            countSlider:SetValue(styleTable[keys.lines] or 2)
            countSlider:SetFullWidth(true)
            countSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable[keys.lines] = val
                refreshCallback()
            end)
            container:AddChild(countSlider)
        end

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Lap Duration")
        speedSlider:SetSliderValues(0.1, 2.0, 0.05)
        speedSlider:SetValue(styleTable[keys.speed] or 2)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "autocast" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Particle Scale")
        sizeSlider:SetSliderValues(0.2, 3, 0.05)
        local currentScale = styleTable[keys.size]
        if not currentScale or currentScale < 0.2 or currentScale > 3 then
            currentScale = 2
        end
        sizeSlider:SetValue(currentScale)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Frequency")
        speedSlider:SetSliderValues(10, 200, 0.1)
        speedSlider:SetValue(styleTable[keys.speed] or 50)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
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

    if isOverrideMode and cfg.enableLabel then
        local enableCb = AceGUI:Create("CheckBox")
        enableCb:SetLabel(cfg.enableLabel)
        enableCb:SetValue(isEnabled)
        enableCb:SetFullWidth(true)
        enableCb:SetCallback("OnValueChanged", function(widget, event, val)
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
        end)
        container:AddChild(enableCb)

        if not isEnabled then
            return
        end
    end

    if opts and opts.afterEnableCallback then
        opts.afterEnableCallback(container)
    end

    if styleTable[cfg.styleKey] == "lcgProc" then
        styleTable[cfg.styleKey] = "glow"
    end
    local currentStyle = NormalizeLegacyGlowStyle(styleTable[cfg.styleKey] or cfg.defaultStyle)
    if currentStyle == "none" then
        currentStyle = cfg.defaultStyle
    end

    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Glow Style")
    local styleOptions = cfg.styleOptions or {
        ["solid"] = "Solid Border",
        ["pixel"] = "Pixel Glow",
        ["glow"] = "Glow",
    }
    local styleOrder = cfg.styleOrder or {"solid", "pixel", "glow"}
    styleDrop:SetList(styleOptions, styleOrder)
    styleDrop:SetValue(currentStyle)
    styleDrop:SetFullWidth(true)
    styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        if cfg.enableKey then
            styleTable[cfg.enableKey] = true
        end
        styleTable[cfg.styleKey] = val
        if cfg.onStyleChanged then
            cfg.onStyleChanged(styleTable, val)
        end
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(styleDrop)

    if not (opts and opts.hidePrimaryColorPicker) then
        AddColorPicker(container, styleTable, cfg.colorKey, cfg.colorLabel, cfg.defaultColor, true, refreshCallback, refreshCallback)
    end

    if cfg.color2Key and currentStyle == "colorShift" then
        AddColorPicker(container, styleTable, cfg.color2Key, cfg.color2Label or "Second Color", cfg.defaultColor2, true, refreshCallback, refreshCallback)
    end

    BuildGlowSliders(container, styleTable, currentStyle, {
        size = cfg.sizeKey, thickness = cfg.thicknessKey, speed = cfg.speedKey, lines = cfg.linesKey,
        solidSizeDefault = cfg.solidSizeDefault,
    }, refreshCallback, 1)
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
-- 140px control column can size a menu from; every other row-grammar dropdown
-- with long items widens its pullout to the same 300.
local BAR_AURA_EFFECT_PULLOUT_WIDTH = 300

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

-- Row-mode restatement of the per-style sliders BuildGlowSliders emits for
-- these five styles: identical labels, ranges, steps, store keys and fallback
-- values, in the identical order. Only the widget shape differs. "color" has
-- no entry because BuildGlowSliders matches none of its branches for it.
local BAR_AURA_EFFECT_SLIDER_ROWS = {
    solid = {
        {label = "Border Size", key = "barAuraEffectSize", min = 1, max = 8, step = 0.1, default = 2},
    },
    pulse = {
        {label = "Border Size", key = "barAuraEffectSize", min = 1, max = 8, step = 0.1, default = 2},
        {label = "Pulse Duration", key = "barAuraEffectSpeed", min = 0.1, max = 2.0, step = 0.05, default = 0.5},
    },
    colorShift = {
        {label = "Border Size", key = "barAuraEffectSize", min = 1, max = 8, step = 0.1, default = 2},
        {label = "Shift Duration", key = "barAuraEffectSpeed", min = 0.1, max = 2.0, step = 0.05, default = 0.8},
    },
    dashes = {
        {label = "Dash Length", key = "barAuraEffectSize", min = 2, max = 20, step = 0.5, default = 8},
        {label = "Dash Thickness", key = "barAuraEffectThickness", min = 1, max = 8, step = 0.5, default = 4},
        {label = "Number of Dashes", key = "barAuraEffectLines", min = 1, max = 8, step = 1, default = 2},
        {label = "Lap Duration", key = "barAuraEffectSpeed", min = 0.1, max = 2.0, step = 0.05, default = 2},
    },
}
-- BuildGlowSliders treats the legacy "pulsingBorder" value as "pulse"; a saved
-- profile carrying it must draw the same sliders here.
BAR_AURA_EFFECT_SLIDER_ROWS.pulsingBorder = BAR_AURA_EFFECT_SLIDER_ROWS.pulse

local FILL_EFFECTS_TOOLTIP = {
    "Fill Effects",
    {"The bar fill breathes (pulse) or cycles color (color shift) while the aura is active. Use the preview toggle to see them without a live aura.", 1, 1, 1, true},
}

-- opts.row opts into the row grammar (RowWidgets.lua): the builder opens its
-- own two-column grid on `container` and returns the two columns. LEFT is the
-- border effect (style, its color, its per-style sliders); RIGHT is the two
-- fill effects and their children. Omitting opts.row keeps the full-width
-- stock widgets the unconverted callers draw (the bar-mode advanced panel and
-- the entry override tab).
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
    if opts and opts.isOverride == true and enabledVal == false then
        -- The preview toggle disappears with the disabled section; make sure
        -- a preview it owned doesn't keep rendering.
        if CS.selectedGroup and CS.selectedButton and CooldownCompanion.SetBarAuraEffectPreview then
            CooldownCompanion:SetBarAuraEffectPreview(CS.selectedGroup, CS.selectedButton, false)
        end
        return
    end

    if rowMode then
        local cfg = BAR_AURA_EFFECT_CFG
        local effectsLeft, effectsRight = BeginRowGrid(container)

        -- Same normalization the stock path runs before it draws the dropdown.
        if styleTable[cfg.styleKey] == "lcgProc" then
            styleTable[cfg.styleKey] = "glow"
        end
        local currentStyle = NormalizeLegacyGlowStyle(styleTable[cfg.styleKey] or cfg.defaultStyle)
        if currentStyle == "none" then
            currentStyle = cfg.defaultStyle
        end

        AddDropdownRow(effectsLeft, {
            label = "Glow Style",
            pulloutWidth = BAR_AURA_EFFECT_PULLOUT_WIDTH,
            list = cfg.styleOptions,
            order = cfg.styleOrder,
            value = currentStyle,
            onChange = function(val)
                styleTable[cfg.enableKey] = true
                styleTable[cfg.styleKey] = val
                cfg.onStyleChanged(styleTable, val)
                refreshCallback()
                RefreshStructuralControls(container)
            end,
        })

        -- deferCommit is deliberately absent, matching the AddColorPicker call
        -- the stock path makes: nothing on this surface re-reads the style
        -- table mid-drag, so the live value may reach it directly.
        AddColorRow(effectsLeft, {
            label = cfg.colorLabel,
            tbl = styleTable,
            key = cfg.colorKey,
            default = cfg.defaultColor,
            hasAlpha = true,
            onConfirm = refreshCallback,
            onChange = refreshCallback,
        })

        -- Everything below belongs to the style above it and disappears with
        -- it, so it indents as its child.
        if currentStyle == "colorShift" then
            AddColorRow(effectsLeft, {
                label = cfg.color2Label,
                indent = true,
                tbl = styleTable,
                key = cfg.color2Key,
                default = cfg.defaultColor2,
                hasAlpha = true,
                onConfirm = refreshCallback,
                onChange = refreshCallback,
            })
        end

        for _, slider in ipairs(BAR_AURA_EFFECT_SLIDER_ROWS[currentStyle] or {}) do
            local sliderKey = slider.key
            AddSliderRow(effectsLeft, {
                label = slider.label,
                indent = true,
                min = slider.min, max = slider.max, step = slider.step,
                value = styleTable[sliderKey] or slider.default,
                onChange = function(val)
                    styleTable[sliderKey] = val
                    refreshCallback()
                end,
            })
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

local function BuildBarNameTextControls(container, styleTable, refreshCallback)
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

local function BuildBarReadyTextControls(container, styleTable, refreshCallback)
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
local function BuildTextBackgroundControls(container, styleTable, refreshCallback)
    AddColorPicker(container, styleTable, "textBgColor", "Background Color", {0, 0, 0, 0}, true, refreshCallback, refreshCallback)

    local renderMode = AddBorderRenderModeDropdown(container, styleTable, "textBorderRenderMode", function()
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderSlider = AceGUI:Create("Slider")
        borderSlider:SetLabel("Border Size")
        borderSlider:SetSliderValues(0, 5, 0.1)
        borderSlider:SetValue(styleTable.textBorderSize or 0)
        borderSlider:SetFullWidth(true)
        borderSlider:SetDisabled(borderThicknessLocked)
        borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if borderThicknessLocked then return end
            styleTable.textBorderSize = val
            refreshCallback()
        end)
        container:AddChild(borderSlider)
    end

    AddColorPicker(container, styleTable, "textBorderColor", "Border Color", {0, 0, 0, 1}, true, refreshCallback, refreshCallback)
end

local function BuildTextFontControls(container, styleTable, refreshCallback)
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

local function BuildTextColorsControls(container, styleTable, refreshCallback, setWidth)
    local textColorPicker = AddColorPicker(container, styleTable, "textFontColor", "Text Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
    local cdColorPicker = AddColorPicker(container, styleTable, "textCooldownColor", "Cooldown Color", {1, 0.3, 0.3, 1}, true, refreshCallback, refreshCallback)

    local readyColorPicker = AddColorPicker(container, styleTable, "textReadyColor", "Ready Color", {0.2, 1.0, 0.2, 1}, true, refreshCallback, refreshCallback)
    if setWidth then
        setWidth(textColorPicker)
        setWidth(cdColorPicker)
        setWidth(readyColorPicker)
    end

    local function BuildReadyTextAdvanced(panel)
        local readyTextBox = AceGUI:Create("EditBox")
        if readyTextBox.editbox.Instructions then readyTextBox.editbox.Instructions:Hide() end
        readyTextBox:SetLabel("Ready Text")
        readyTextBox:SetText(styleTable.textReadyText or "Ready")
        readyTextBox:SetFullWidth(true)
        readyTextBox:SetCallback("OnEnterPressed", function(widget, event, val)
            styleTable.textReadyText = val
            refreshCallback()
        end)
        panel:AddChild(readyTextBox)
    end

    local _, readyAdvBtn = AddAdvancedToggle(readyColorPicker, "textReadyText", tabInfoButtons, nil, {
        title = "Ready Color Advanced",
        build = BuildReadyTextAdvanced,
    })
    readyAdvBtn:SetPoint("LEFT", readyColorPicker.colorSwatch, "RIGHT", readyColorPicker.text:GetStringWidth() + 8, 0)
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
