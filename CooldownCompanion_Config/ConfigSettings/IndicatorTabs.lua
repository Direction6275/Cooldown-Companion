-- One display and its sources. Aura readouts are configured, never queried.
local _, ST = ...
local Addon, I, CS = ST.Addon, ST.Indicator, ST._configState
local AceGUI = LibStub("AceGUI-3.0")
local Dropdown, Check, Slider = ST._AddDropdownRow, ST._AddCheckboxRow, ST._AddSliderRow
local Label, Edit = ST._AddLabelRow, ST._AddEditBoxRow
local anchors = {TOPLEFT="Top Left",TOP="Top",TOPRIGHT="Top Right",LEFT="Left",CENTER="Center",
    RIGHT="Right",BOTTOMLEFT="Bottom Left",BOTTOM="Bottom",BOTTOMRIGHT="Bottom Right"}
local anchorOrder = {"TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT"}
local ROW_SECTION = {leftAligned = true}
local TAB_LABELS = {loadconditions = "Visibility", appearance = "Appearance", effects = "Effects"}
-- The Entry identity line's muted grey, so "(Aura)" reads the same everywhere.
local KIND_COLOR = "|cff7d7566"

-- Each section owns its collapse key; finder routes force that key open.
local function Route(tab, section, sectionLabel, collapseKey, extra)
    local defaults = {idPrefix="panel.indicator."..section, scope="panel", rowScope="primary",
        tab=tab, tabLabel=TAB_LABELS[tab], section=section, sectionLabel=sectionLabel,
        collapseKeys={collapseKey},
        applies=function(context)
            return ST.IsIndicatorGroup(context.group) and (tab == "loadconditions" or I.Primary(context.group) ~= nil)
        end}
    for key, value in pairs(extra or {}) do defaults[key] = value end
    return ST._DefineSettingRoute(defaults)
end
local function Applies(predicate)
    return function(context)
        local g=context.group
        return ST.IsIndicatorGroup(g) and I.Primary(g) ~= nil and predicate(g,I.Settings(g))
    end
end
local textOnly = Applies(function(_,s) return s.displayType == "text" end)
local function CountReadoutKey(group)
    return I.IsAura(group) and "stacks" or I.Primary(group).type == "spell" and "charges" or "item"
end
-- While Missing shows only while the aura is absent: no timer, count or drain,
-- unless Also During Pandemic adds the live display in the refresh window.
local function LiveReadouts(group)
    return not I.UsesPresence(group) or I.AlsoDuringPandemic(group)
end
local drainable = Applies(function(g,s) return s.displayType == "texture" and LiveReadouts(g) end)
local drain = Applies(function(g,s) return s.displayType == "texture" and s.progress.enabled == true
    and LiveReadouts(g) end)
local function Enabled(settings, key)
    local r = settings.readouts
    if key == "timer" then return r.timer == true end
    return r[key] ~= "none"
end

-- Row labels match the panel Text rows. Descriptors are keyed by the old
-- setting keys, so saved finder ids and old names keep working.
local READOUT_ROWS = {
    label = {label="Show Label Text", aliases={"label"}},
    timer = {label="Show Cooldown Text", aliases={"timer"},
        applies=Applies(function(g) return not I.IsAura(g) end)},
    auraTimer = {label="Show Aura Duration Text", aliases={"timer"},
        applies=Applies(function(g) return I.ShowsLiveDisplay(g) end)},
    stacks = {label="Show Aura Stack Text", aliases={"aura stacks","count"},
        applies=Applies(function(g) return CountReadoutKey(g) == "stacks" and LiveReadouts(g) end)},
    charges = {label="Show Count Text (Charges / Uses)", aliases={"charges","display count"},
        applies=Applies(function(g) return CountReadoutKey(g) == "charges" end)},
    item = {label="Show Item Count Text", aliases={"item count"},
        applies=Applies(function(g) return CountReadoutKey(g) == "item" end)},
}
local function ReadoutRowKey(group, key)
    if key == "timer" then return I.IsAura(group) and "auraTimer" or "timer" end
    if key == "count" then return CountReadoutKey(group) end
    return key
end

local display = Route("appearance", "display", "Display", "indicator_display"):Settings({
    displayType={label="Display As",aliases={"display","indicator","texture","icon","text"}},
    width={label="Width",applies=textOnly},height={label="Height",applies=textOnly},
    background={label="Background Color",aliases={"text background"},applies=textOnly},
})
READOUT_ROWS.timerFormat = {label="Duration Format",aliases={"timer format"},
    applies=Applies(function(g,s) return s.readouts.timer == true and LiveReadouts(g) end)}
local text = Route("appearance", "text", "Text", "indicator_text", {idPrefix="panel.indicator.display"}):Settings(READOUT_ROWS)
local drainSettings = Route("appearance", "drain", "Duration Drain", "indicator_drain",
    {idPrefix="panel.indicator.display"}):Settings({
    progress={label="Duration Drain",aliases={"depletion","dim silhouette"},applies=drainable},
    direction={label="Drain Direction",applies=drain},dim={label="Dim Silhouette",applies=drain},
})
local labelContent = Route("appearance", "labelPosition", "Label Text", "indicator_text",
    {idPrefix="panel.indicator.display", advancedKey="indicatorText_label"}):Settings({
    labelType={label="Label Content"},
    customText={label="Custom Label",applies=Applies(function(_,s) return s.readouts.label == "custom" end)},
})

local whenToShow = Route("loadconditions", "whenToShow", "When to Show", "indicator_whenToShow",
    {idPrefix="panel.indicator.source"}):Settings({
    sourceVisibility={label="Use Saved Source Visibility",applies=Applies(function(g,s) return s.sourceVisibility ~= nil and not I.IsAura(g) end)},
    -- Bound to the section heading: the rules themselves are one row each.
    -- Every Indicator with a source has the section; an aura's holds the aura
    -- and any extra spell/item sources with their rules.
    conditions={label="When to Show",aliases={"show when","conditions","rules","ready","on cooldown","always"},
        applies=Applies(function() return true end)},
    unit={label="Tracked on",aliases={"aura unit","unit"},applies=Applies(function(g) return I.IsAura(g) end)},
    auraWhen={label="When",aliases={"stacks","stack count","at least","fewer than","exactly","max stacks","while active",
        "while missing","missing","inactive"},
        applies=Applies(function(g) return I.IsAura(g) and not I.IsMultiAura(g) end)},
    auraMatch={label="Match",aliases={"all","any","and","or","several auras","multiple auras"},
        applies=Applies(function(g) return I.IsMultiAura(g) end)},
    auraEntryWhen={label="When",aliases={"while active","while missing","missing","inactive"},
        applies=Applies(function(g) return I.IsMultiAura(g) end)},
    auraPandemic={label="Also During Pandemic",aliases={"pandemic window","refresh window","while missing or pandemic"},
        applies=Applies(function(g) return I.ShowsWhileMissing(g) and I.Primary(g).auraTrackGroup ~= true end)},
    stackCount={label="Stacks",aliases={"stack count"},applies=Applies(function(g)
        local compare = I.StackCompare(g)
        return compare ~= nil and compare ~= "max"
    end)}})

local soundRoute = ST._DefineSettingRoute({
    idPrefix="panel.indicator.sounds",scope="panel",rowScope="primary",tab="effects",tabLabel="Effects",
    section="sounds",sectionLabel="Sound Alerts",
    collapseKeys=function(context) return {tostring(context.groupId).."_nil_soundalerts"} end,
    applies=Applies(function(g) return not Addon.IsEquipmentSlotEntry(I.Primary(g)) end),
})
local soundDefinitions = {
    sourceSounds={label="Sound Events",applies=Applies(function(g) return not I.IsAura(g) and I.Primary(g).type == "spell" end)},
    triggered={label="Triggered",aliases={"on show","sound"},
    applies=Applies(function(g) return not I.UsesSourceSounds(g) end)}}
for key, label in pairs({available="Available",availableWithCharges="Available / Charge Gained",
    onCooldown="On Cooldown",chargeGained="Charge Gained",onAuraApplied="Aura Applied",
    onAuraStackGained="Aura Stack Gained",onAuraRemoved="Aura Removed"}) do
    local eventKey, charged = key == "availableWithCharges" and "available" or key, key == "availableWithCharges"
    soundDefinitions[key]={label=label,applies=Applies(function(g)
        if not I.UsesSourceSounds(g) then return false end
        local source=I.Primary(g)
        local events=Addon:GetScopedValidSoundAlertEventsForButton(source,nil,nil,g)
        return events and events[eventKey] == true
            and (eventKey ~= "available" or (Addon.UsesChargeBehavior(source) == true) == charged)
    end)}
end
ST._IndicatorSoundSettings = soundRoute:Settings(soundDefinitions)

-- One gear per readout, holding its font and position like a panel's text
-- gears. Structural: the gear exists with the readout off, behind its unlock.
local READOUT_SECTION_LABELS = {label="Label Text", timer="Duration Text", count="Count Text"}
-- The panel Low Time family, drawn inside the Duration Text gear. Its keys
-- live in `readouts` under the panel names; a missing threshold is off.
local function LowTimeThreshold(settings)
    local threshold = tonumber(settings.readouts.durationLowTimeThreshold)
    return threshold and threshold > 0 and threshold or nil
end
local lowTimeOn = Applies(function(_,s) return LowTimeThreshold(s) ~= nil end)
local criticalOn = Applies(function(_,s)
    local threshold, second = LowTimeThreshold(s), tonumber(s.readouts.durationLowTimeThreshold2)
    return threshold ~= nil and second ~= nil and second > 0 and second < threshold
end)
local LOW_TIME_ROWS = {
    lowTime={label="Change Text Near Expiry",aliases={"low time","warning time"}},
    lowTimeWarning={label="Start Warning Below",applies=lowTimeOn},
    lowTimeWarningColor={label="Warning Color",applies=lowTimeOn},
    lowTimeCritical={label="Add Critical Styling",applies=lowTimeOn},
    lowTimeCriticalThreshold={label="Start Critical Below",applies=criticalOn},
    lowTimeCriticalColor={label="Critical Color",applies=criticalOn},
    lowTimeDecimals={label="Show Decimals Near Expiry",applies=lowTimeOn},
}
local positions = {}
for _,key in ipairs({"label","timer","count"}) do
    local name=key:sub(1,1):upper()..key:sub(2)
    local definitions = {
        fontSize={label="Font Size",aliases={"text size"}},
        font={label="Font"},
        outline={label="Font Outline"},
        color={label="Font Color",aliases={"text color"}},
        anchor={label="Anchor",aliases={name.." Anchor"}},
        X={label="X Offset",aliases={name.." X"}}, Y={label="Y Offset",aliases={name.." Y"}},
    }
    if key == "timer" then
        for field, definition in pairs(LOW_TIME_ROWS) do definitions[field] = definition end
    end
    positions[key]=Route("appearance", key.."Position", READOUT_SECTION_LABELS[key], "indicator_text",
        {advancedKey="indicatorText_"..key}):Settings(definitions)
end

-- Pandemic, for aura Indicators whose live display shows: the effect (a
-- glow on Icon artwork, a recolor on Texture and Text) and the marker (on
-- the duration text) rows.
local auraOnly = Applies(function(g) return I.ShowsLiveDisplay(g) end)
local auraArtwork = Applies(function(g,s) return I.ShowsLiveDisplay(g) and s.displayType == "icon" end)
local auraTimer = Applies(function(g,s) return I.ShowsLiveDisplay(g) and s.readouts.timer == true end)
local pandemic = Route("effects", "pandemic", "Pandemic", "indicator_pandemic", {applies=auraOnly}):Settings({
    effect={label="Show Pandemic Effect",aliases={"pandemic glow","pandemic","pandemic recolor"},
        applies=Applies(function(g) return I.ShowsLiveDisplay(g) and I.PandemicEffectApplies(g) end)},
    -- Texture and Text recolor in the effect color (Icons glow).
    color={label="Pandemic Color",aliases={"pandemic recolor","pandemic tint"},
        applies=Applies(function(g,s) return I.ShowsLiveDisplay(g) and s.displayType ~= "icon"
            and I.PandemicEffectApplies(g) and I.PandemicEffectOn(g) end)},
    marker={label="Pandemic Marker",aliases={"pandemic"},applies=auraTimer},
})
local function PandemicGlowStyle(settings)
    return ST._NormalizeGlowStyleForDisplay(settings.pandemic and settings.pandemic.pandemicGlowStyle, "solid")
end
local function GlowUses(...)
    local styles = {}
    for index = 1, select("#", ...) do styles[select(index, ...)] = true end
    return Applies(function(g,s) return I.ShowsLiveDisplay(g) and s.displayType == "icon" and styles[PandemicGlowStyle(s)] == true end)
end
-- Same rows the panel's Pandemic Effect gear draws for these styles.
local pandemicGlow = Route("effects", "pandemic", "Pandemic Effect", "indicator_pandemic",
    {idPrefix="panel.indicator.pandemicGlow", advancedKey="indicatorPandemicGlow", applies=auraArtwork}):Settings({
    style={label="Glow Style"},
    color={label="Effect Color",applies=Applies(function(g,s)
        return I.ShowsLiveDisplay(g) and s.displayType == "icon" and PandemicGlowStyle(s) ~= "cdm" end)},
    color2={label="Second Color",applies=GlowUses("colorShift")},
    borderSize={label="Border Size",applies=GlowUses("solid","pulse","colorShift")},
    pulseDuration={label="Pulse Duration",applies=GlowUses("pulse")},
    glowSize={label="Glow Size",applies=GlowUses("ants","proc")},
    shiftDuration={label="Shift Duration",applies=GlowUses("colorShift")},
    dashLength={label="Dash Length",applies=GlowUses("dashes")},
    dashThickness={label="Dash Thickness",applies=GlowUses("dashes")},
    dashCount={label="Number of Dashes",applies=GlowUses("dashes")},
    lapDuration={label="Lap Duration",applies=GlowUses("dashes")},
    particleScale={label="Particle Scale",applies=GlowUses("autocast")},
    frequency={label="Frequency",applies=GlowUses("autocast")},
})
-- A Text display's Pandemic effect colors the whole timer, marker included
-- (I.PandemicRecolorsText), so the marker's own coloring rows step aside.
local pandemicMarker = Route("effects", "pandemic", "Pandemic Marker", "indicator_pandemic",
    {idPrefix="panel.indicator.pandemicMarker", advancedKey="indicatorPandemicMarker", applies=auraTimer}):Settings({
    text={label="Marker Text"},
    coloring={label="Marker Coloring",applies=Applies(function(g,s)
        return I.ShowsLiveDisplay(g) and s.readouts.timer == true and not I.PandemicRecolorsText(g) end)},
    color={label="Marker Color",applies=Applies(function(g,s)
        return I.ShowsLiveDisplay(g) and s.readouts.timer == true and not I.PandemicRecolorsText(g)
            and (s.readouts.pandemicMarkerColorMode or "marker") ~= "off" end)},
})

-- Buttons sharing one row's control column (ST._CreateRowActionStrip), from
-- {text, onClick, tooltip = {title, body}}.
local function ActionStrip(actions)
    local buttons = {}
    for index, action in ipairs(actions) do
        local button = AceGUI:Create("Button")
        button:SetText(action.text)
        button:SetCallback("OnClick", function()
            -- The click can rebuild the page and release this hovered button,
            -- so its tooltip would never see OnLeave.
            if GameTooltip:IsOwned(button.frame) then GameTooltip:Hide() end
            action.onClick()
        end)
        if action.tooltip then
            button:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
                GameTooltip:SetText(action.tooltip[1])
                GameTooltip:AddLine(action.tooltip[2], 1, 1, 1, true)
                GameTooltip:Show()
            end)
            button:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        end
        buttons[index] = button
    end
    return ST._CreateRowActionStrip(buttons)
end

local function Section(container, text, key, setting)
    local heading, collapsed = ST._BuildCollapsibleSection(container, text, key, nil, nil, ROW_SECTION)
    if setting and ST._BindSettingWidget then
        ST._BindSettingWidget(heading,setting,text)
        local onRelease = heading.events and heading.events.OnRelease
        heading:SetCallback("OnRelease",function(widget,event,...)
            widget._cdcSettingDescriptor=nil
            if onRelease then onRelease(widget,event,...) end
        end)
    end
    return heading, collapsed
end

local function Hint(container, text)
    local hint = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(hint)
    hint:SetFontObject(GameFontHighlight)
    hint:SetText(text)
    hint:SetFullWidth(true)
    container:AddChild(hint)
end

local function FocusSourceSearch()
    CS.panelAddModeQuery = ""
    CS.pendingWideAddFocus = true
    Addon:RefreshConfigPanel()
end

-- Edits are bound to the Indicator and profile they were built for.
local function MakeChanged(group)
    local id, profile = CS.selectedGroup, Addon.db.profile
    return function(rebuild)
        if Addon.db.profile ~= profile or profile.groups[id] ~= group then return end
        Addon:RefreshGroupFrame(id)
        Addon:RequestAuraRebind("style", id)
        if rebuild then Addon:RefreshConfigPanel()
        elseif ST._RefreshButtonsPreviewMirror then ST._RefreshButtonsPreviewMirror(id) end
    end
end

-- One short name per rule, shared by the Visibility editor and the Live
-- Preview's rules card, so a tag and the row it opens read the same.
local RULE_LABELS = {
    cooldownActive = {["true"]="On Cooldown", ["false"]="Off Cooldown"},
    procActive = {["true"]="Proc Active", ["false"]="No Proc"},
    rangeActive = {["true"]="In Range", ["false"]="Out of Range"},
    usable = {["true"]="Usable", ["false"]="Unusable"},
    chargesRecharging = {["true"]="Recharging", ["false"]="Not Recharging"},
    chargeState = {full="Full Charges", missing="Charges Missing", zero="No Charges"},
    countTextActive = {["true"]="Count Shown", ["false"]="Count Hidden"},
    countState = {full="Full Count", missing="Count Below Max", zero="Zero Count"},
}

local function RuleValue(clause)
    return clause.state or (clause.expected == false and "false" or "true")
end

-- nil for a saved rule this client cannot evaluate; it fails closed.
local function RuleLabel(clause)
    if clause.unavailable or not I.ConditionKeys[clause.key] then return end
    local labels = RULE_LABELS[clause.key]
    return labels and labels[RuleValue(clause)]
end

-- Every rule an entry offers, as one dropdown of "key:value" choices. A saved
-- rule the list no longer offers stays listed so it can be seen and replaced.
local function RuleChoices(entry, clause)
    local _, keys = Addon:GetTriggerConditionTypeOptions(entry)
    local list, order = {}, {}
    for _, key in ipairs(keys) do
        local labels = I.ConditionKeys[key] and RULE_LABELS[key]
        if labels then
            local _, values = Addon:GetTriggerConditionExpectedOptions(key)
            for _, value in ipairs(values) do
                if labels[value] then
                    local id = key .. ":" .. value
                    list[id], order[#order + 1] = labels[value], id
                end
            end
        end
    end
    local current = clause and (tostring(clause.key) .. ":" .. RuleValue(clause))
    if current and (clause.unavailable or not list[current]) then
        list[current] = "Unavailable: " .. tostring(clause.key)
        table.insert(order, 1, current)
    end
    return list, order, current
end

local function RuleFromChoice(id)
    local key, value = id:match("^(.-):(.+)$")
    return {key=key, expected=value ~= "false", state=value ~= "true" and value ~= "false" and value or nil}
end

-- A tag clicked in the preview names its rule. Navigation opens When to Show;
-- the rebuilt row for that rule then claims the settings highlight.
local function OpenRule(clause)
    CS.indicatorRuleFocus = clause and {clause=clause} or nil
    ST._NavigateToFinderSetting(whenToShow.conditions.id)
end

local function ClaimRuleFocus(row, clause)
    local focus = CS.indicatorRuleFocus
    if not (focus and focus.clause == clause) then return end
    CS.indicatorRuleFocus = nil
    if CS.pendingSettingHighlight then CS.pendingSettingHighlight.settingWidget = row end
end

local CHANGE_HOVER_COLOR = {1, 0.82, 0}

-- A small flat icon action after a row's label (CDC-RowIconBadge): the
-- remove X unless `atlas` names another icon. `tooltip` is a title or
-- {title, body}. The row owns it and releases it with itself.
local function RowBadge(row, tooltip, onClick, atlas, hoverColor, rotation)
    local badge = AceGUI:Create("CDC-RowIconBadge")
    if atlas then badge:SetIcon(atlas, hoverColor, rotation) end
    badge:SetCallback("OnClick", function()
        GameTooltip:Hide()
        onClick()
    end)
    badge:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
        if type(tooltip) == "table" then
            GameTooltip:SetText(tooltip[1])
            GameTooltip:AddLine(tooltip[2], 1, 1, 1, true)
        else
            GameTooltip:SetText(tooltip)
        end
        GameTooltip:Show()
    end)
    badge:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    return ST._AnchorRowBadgeWidget(row, badge)
end

local function SourceName(entry, icon)
    return (icon and "|T"..tostring(icon)..":16:16|t " or "")..(entry.name or tostring(entry.id))
end

-- Change and Remove for the main source, as badges after its name. Change
-- stays lit while a replacement is being picked; clicking it again cancels.
local function AddMainSourceBadges(row, group, source, changed)
    local replacing = CS.GetIndicatorSourceReplacement(CS.selectedGroup) ~= nil
    -- The next source takes over; with none, the Indicator is cleared.
    local nextSource = I.NextMainSource(group)
    local removeText = nextSource
        and ((nextSource.name or tostring(nextSource.id)) .. " is shown on the display instead"
            .. (I.IsListedAura(group, nextSource) and "." or ", with its rules."))
        or #group.buttons > 1 and "No other source can drive the display, so every source is removed. The look is kept."
        or "Removes the source; the look is kept."
    local change = RowBadge(row,
        replacing and {"Cancel Change", "Keep the current source."}
            or I.IsMultiAura(group) and {"Change Source", "Search for another aura in the field at the top. With several auras, only an aura can replace it."}
            or {"Change Source", "Search for a replacement in the field at the top."},
        function()
            CS.indicatorSourceReplacement = not replacing and {
                groupId=CS.selectedGroup,group=group,profile=Addon.db.profile,source=source,
            } or nil
            CS.HideAutocomplete()
            if replacing then
                CS.pendingWideAddFocus = nil
                CS.panelAddModeQuery = ""
                Addon:RefreshConfigPanel()
            else
                CS.pendingWideAddFlash = true
                FocusSourceSearch()
            end
        end, "uitools-icon-refresh", CHANGE_HOVER_COLOR)
    change:SetActive(replacing)
    RowBadge(row, {"Remove Source", removeText}, function()
        local removed, reason, notice = I.RemoveSource(group, source)
        if reason then Addon:Print(I.EffectFailureText[reason]) end
        if notice then Addon:Print(notice) end
        if removed then changed(true) end
    end)
end

-- Where an aura Indicator looks for an aura. Each aura in a list has its own
-- (each gets its own hidden tracker).
local function AddTrackedOn(column, group, source, changed)
    local automaticSource = CopyTable(source)
    automaticSource.auraUnitOverride = nil
    local automaticUnit = Addon:ResolveStandaloneAuraDefaultUnit(automaticSource)
    -- Presence-drawn auras have no group form yet: Group is offered only if saved.
    local order = {"automatic","player","target","group","pet"}
    if I.UsesPresence(group) and not source.auraTrackGroup then table.remove(order, 4) end
    Dropdown(column, {setting=whenToShow.unit, indent=true,
        list={automatic="Automatic ("..(automaticUnit == "target" and "Target" or "Player")..")",
            player="Player",target="Target",group="Group (Your Buffs)",pet="Pet"},
        order=order,
        value=source.auraTrackPet and "pet" or source.auraTrackGroup and "group"
            or source.auraUnitOverride or "automatic",
        onChange=function(value)
            local function Apply(entry)
                entry.auraUnitOverride=(value == "player" or value == "target") and value or nil
                entry.auraTrackGroup = value == "group" or nil
                entry.auraTrackPet = value == "pet" or nil
                if entry.auraTrackGroup or entry.auraTrackPet then entry.auraUnitOverride = "player" end
                entry.auraUnit=Addon:ResolveStandaloneAuraDefaultUnit(entry)
            end
            -- A list never checks the same aura twice on one unit.
            local probe = CopyTable(source)
            Apply(probe)
            for _, other in ipairs(I.AuraList(group)) do
                if other ~= source and I.SameAura(other, probe) then
                    Addon:Print(I.SameAuraUnitText)
                    changed(true)
                    return
                end
            end
            Apply(source)
            changed(true)
        end})
end

-- An aura list's Match: every aura's When must hold, or at least one.
local AURA_MATCH_TOOLTIP = {"Match",
    {"All shows when every aura matches its When. Any shows when at least one does.", 1, 1, 1, true},
    " ",
    {"There is no timer or count.", 1, 1, 1, true},
    " ",
    {"Target auras need a hostile target, pet auras your pet. Without them, All stays hidden. Any still shows from auras on you.", 1, 1, 1, true}}
local function AddAuraMatch(column, group, changed)
    local current = I.AuraMatch(group)
    Dropdown(column, {setting=whenToShow.auraMatch, indent=true, list=I.AURA_MATCH_LABELS,
        order=I.AURA_MATCH_ORDER, value=current, tooltip=AURA_MATCH_TOOLTIP,
        onChange=function(value)
            if value == current then return end
            I.SetAuraMatch(group, value)
            changed(true)
        end})
    if I.AuraListProblem(group) == "indicator_aura_group" then
        Hint(column, "Group tracking works with a single aura, so this stays hidden. Choose another Tracked On.")
    end
end

-- One aura's When inside a list.
local AURA_ENTRY_WHEN_LIST = {active="While Active", missing="While Missing"}
local function AddListedAuraWhen(column, group, entry, changed)
    local current = I.AuraWantsActive(entry) and "active" or "missing"
    -- The Finder row lands on the main aura's When, at the top of the list;
    -- one descriptor can address one widget.
    Dropdown(column, {setting=entry == I.Primary(group) and whenToShow.auraEntryWhen or nil,
        label="When", indent=true, list=AURA_ENTRY_WHEN_LIST,
        order={"active", "missing"}, value=current,
        tooltip={"When", {"While Active counts this aura while it is on; While Missing while it is off.", 1, 1, 1, true}},
        onChange=function(value)
            if value == current then return end
            I.SetAuraEntryWhen(group, entry, value)
            changed(true)
        end})
end

-- The aura's one rule: While Active, or a stack count it must reach, stay
-- under, or match. Blizzard applies it in combat (see Indicator.StackRule).
local AURA_WHEN_LIST = {active="While Active", missing="While Missing", atLeast="At Least N Stacks",
    fewer="Fewer Than N Stacks", exactly="Exactly N Stacks", max="At Max Stacks"}
local STACK_CHOICES = {"atLeast", "fewer", "exactly", "max"}
local function AddAuraWhen(column, group, entry, changed)
    -- `max` is the aura's max from spell data: it caps the slider. An aura
    -- with none reported does not stack (owner ruling 2026-09-30), so only
    -- While Active is offered, plus a stack rule it already saved.
    local compare, count, max = I.StackRule(group)
    if not compare then max = I.StackMax(group) end
    local current = I.AuraWhen(group)
    local missing = current == "missing"
    -- While Missing has no group form yet: not offered on Group tracking.
    local order = {"active"}
    if missing or not entry.auraTrackGroup then order[2] = "missing" end
    for _, choice in ipairs(STACK_CHOICES) do
        if max or choice == current then order[#order + 1] = choice end
    end
    local tooltip = {"When", {"While Active shows whenever this aura is on.", 1, 1, 1, true},
        " ", {"While Missing shows only while it is off, with no timer or count. A target aura needs a hostile target.", 1, 1, 1, true}}
    if max then
        tooltip[#tooltip + 1] = " "
        tooltip[#tooltip + 1] = {"A stack choice also needs the aura's stacks to pass. At Max Stacks follows the aura's maximum from the game.", 1, 1, 1, true}
    end
    Dropdown(column, {setting=whenToShow.auraWhen, indent=true, list=AURA_WHEN_LIST, order=order,
        value=current, tooltip=tooltip,
        onChange=function(value)
            if value == current then return end
            local keep = compare and compare ~= "max" and count or 2
            local notice = I.SetAuraWhen(group, value, math.max(I.StackCountMin(value), keep))
            if notice then Addon:Print(notice) end
            changed(true)
        end})
    if missing then
        if entry.auraTrackGroup then
            Hint(column, "While Missing doesn't work with Group tracking yet, so this stays hidden.")
        else
            Check(column, {setting=whenToShow.auraPandemic, indent=true, value=entry.showWhileAuraPandemic == true,
                tooltip={"Also During Pandemic",
                    {"Also shows the Indicator near the end of the aura, in the window where recasting keeps the leftover time.", 1, 1, 1, true},
                    " ",
                    {"In that window it shows the aura's live display, timer included. Only auras with that window use it; leave it off for others.", 1, 1, 1, true},
                    " ",
                    {"Effects set to Only In Combat play on the missing look only.", 1, 1, 1, true}},
                onChange=function(value)
                    entry.showWhileAuraPandemic = value or nil
                    changed(true)
                end})
        end
        return
    end
    if compare and not max then
        Hint(column, ("This aura doesn't stack, so this %s."):format(
            I.StackRuleOutcome(compare, count, max) == "always" and "always shows while it is active" or "never shows"))
        return
    end
    if not compare or compare == "max" then return end
    -- A saved count above the max keeps its meaning and stays reachable.
    Slider(column, {setting=whenToShow.stackCount, indent=true, min=I.StackCountMin(compare),
        max=max and math.max(max, count) or I.STACK_COUNT_MAX, step=1, value=count,
        onRelease=function(value)
            entry.indicatorStackRule.count = math.floor(value + 0.5)
            changed(true)
        end})
    local outcome = I.StackRuleOutcome(compare, count, max)
    if outcome then
        Hint(column, ("This aura stacks to %d, so this %s."):format(max,
            outcome == "never" and "never shows" or "always shows while it is active"))
    end
end

-- One block per source: its name and actions, then one "When / And" row per
-- rule, then a small Add Condition link. The main source changes or goes
-- here; any other spell/item source can be made main, removed or turned off.
-- An aura Indicator's main source is an aura (slot one): a lone aura has its
-- When (While Active, While Missing or a stack rule) and Tracked On; with
-- several, the main aura also holds Match, and every listed aura has its own
-- When and Tracked On plus Promote and Remove. Spell/item sources of an aura
-- Indicator are never made main (CanBeMainSource).
local function BuildSourceRules(container, group, entry, changed)
    local primary = entry == I.Primary(group)
    local column = ST._BeginRowGrid(container)
    local name = SourceName(entry, ST._GetButtonIcon(entry))
    if primary then
        local row = Label(column, {label=name, controlText=KIND_COLOR.."Shown on display|r"})
        AddMainSourceBadges(row, group, entry, changed)
        if I.IsMultiAura(group) then
            AddAuraMatch(column, group, changed)
            AddListedAuraWhen(column, group, entry, changed)
            AddTrackedOn(column, group, entry, changed)
            return
        elseif I.IsAura(group) then
            AddAuraWhen(column, group, entry, changed)
            AddTrackedOn(column, group, entry, changed)
            return
        end
    elseif I.IsListedAura(group, entry) then
        -- Another aura in the list: its own When and unit, no spell rules.
        local row = Label(column, {label=name})
        RowBadge(row, {"Promote to Display", "Use this aura's icon and name on the Indicator. The list and Match stay the same."},
            function() if I.PromoteAura(group, entry) then changed(true) end end,
            "uitools-icon-chevron-down", CHANGE_HOVER_COLOR, math.pi)
        RowBadge(row, {"Remove Aura", "Removes this aura from the list."}, function()
            local removed, reason, notice = I.RemoveSource(group, entry)
            if reason then Addon:Print(I.EffectFailureText[reason]) end
            if notice then Addon:Print(notice) end
            if removed then changed(true) end
        end)
        AddListedAuraWhen(column, group, entry, changed)
        AddTrackedOn(column, group, entry, changed)
        return
    else
        local row = Label(column, {label=name})
        if I.CanBeMainSource(group, entry) then
            -- Promote: an up chevron, like moving the source to the top.
            local promoteText = "Use this source's icon, name, timer and count on the Indicator. It still has to pass its rules like every other source."
            if entry.enabled == false then
                promoteText = promoteText .. " It is off now, so promoting turns it back on."
            end
            RowBadge(row, {"Promote to Display", promoteText},
                function()
                    local promoted, reason = I.PromoteSource(group, entry)
                    if reason then Addon:Print(I.EffectFailureText[reason]) end
                    if promoted then changed(true) end
                end, "uitools-icon-chevron-down", CHANGE_HOVER_COLOR, math.pi)
        end
        RowBadge(row, {"Remove Source", "Removes this source and its rules."},
            function() if I.RemoveSource(group, entry) then changed(true) end end)
        Check(column, {label="Check This Source", indent=true, value=entry.enabled ~= false,
            tooltip={"Check This Source", {"Turn off to keep this source's rules without checking them.", 1, 1, 1, true}},
            onChange=function(value) entry.enabled=value; changed(true) end})
    end
    local clauses = entry.triggerConditions or {}
    if #clauses == 0 then
        Label(column, {label="When", indent=true, controlText="Always",
            tooltip={"Always", {"Shows whenever this source can be tracked. Add a condition to narrow it.", 1, 1, 1, true}}})
    end
    for clauseIndex, clause in ipairs(clauses) do
        local ci = clauseIndex
        if not RuleLabel(clause) then
            Hint(column, "This saved rule cannot match. Replace or remove it to enable this display.")
        end
        local list, order, current = RuleChoices(entry, clause)
        local row = Dropdown(column, {label=ci == 1 and "When" or "And", indent=true, list=list, order=order,
            value=current, pulloutWidth=220,
            onChange=function(value)
                if value == current then return end
                clauses[ci] = RuleFromChoice(value)
                entry.triggerConditions = clauses; changed(true)
            end})
        RowBadge(row, "Remove this rule", function()
            table.remove(clauses, ci); entry.triggerConditions = clauses; changed(true)
        end)
        ClaimRuleFocus(row, clause)
    end
    local add = Label(column, {label="+ Add Condition", indent=true})
    add:SetSettingsDisclosure(function()
        local have = {}
        for _, clause in ipairs(clauses) do have[tostring(clause.key) .. ":" .. RuleValue(clause)] = true end
        local _, order = RuleChoices(entry)
        for _, id in ipairs(order) do
            if not have[id] then
                clauses[#clauses + 1] = RuleFromChoice(id)
                entry.triggerConditions = clauses; changed(true)
                return
            end
        end
    end)
end

-- The Live Preview's rules card (ButtonPanelPreviewTriggers.lua) only shows:
-- every source and its rules, each rule opening its row here. Everything it
-- would edit lives in When to Show; the preview only draws this model.
function ST._GetIndicatorSourceControls(group)
    local source = I.Primary(group)
    if not source then return end
    local aura = I.IsAura(group)
    local replacing = CS.GetIndicatorSourceReplacement(CS.selectedGroup) ~= nil
    -- Everything the card draws and every closure it keeps, so an unchanged
    -- card can be reused across preview refreshes (drags refresh per tick).
    local key = {tostring(group), tostring(aura), tostring(replacing), tostring(group.enabled)}
    local model = {
        replacing = replacing, disabled = group.enabled == false,
        openRule = OpenRule,
        sources = {},
    }
    -- An Icon display showing this same icon as its artwork already names the
    -- main source; repeating it small in the card adds nothing.
    local artwork = I.Settings(group).displayType == "icon" and I.ArtworkIcon(group)
    -- Same order as When to Show: the aura list, then the rule sources.
    local ordered = I.AuraList(group)
    for _, entry in ipairs(group.buttons or {}) do
        if not I.IsListedAura(group, entry) then ordered[#ordered + 1] = entry end
    end
    for _, entry in ipairs(ordered) do
        local primary = entry == source
        local icon = ST._GetButtonIcon(entry)
        if primary and artwork == icon then icon = nil end
        -- Auras show their When (a lone aura's may be a stack rule; later
        -- auras in a list read joined by Match); spell/item sources carry
        -- their rules.
        local item = {name=entry.name or tostring(entry.id), icon=icon, primary=primary,
            aura=I.IsListedAura(group, entry), enabled=entry.enabled ~= false, rules={}}
        if item.aura and primary then
            -- A rule the aura's max rules out reads as a warning.
            local compare, count, max = I.StackRule(group)
            item.auraRule = I.AuraWhenLabel(group)
            item.auraRuleNever = I.StackRuleOutcome(compare, count, max) == "never"
                or I.UsesPresence(group) and entry.auraTrackGroup == true
                or I.AuraListProblem(group) ~= nil
        elseif item.aura then
            -- Later auras read joined by the list's Match.
            item.auraRule = (I.AuraMatch(group) == "any" and "or " or "and ") .. I.AuraEntryWhenLabel(entry)
            item.enabled = true
        end
        key[#key + 1] = table.concat({tostring(entry), tostring(icon), item.name, tostring(item.enabled),
            tostring(item.auraRule), tostring(item.auraRuleNever)}, ",")
        if not item.aura then
            for _, clause in ipairs(entry.triggerConditions or {}) do
                local label = RuleLabel(clause)
                item.rules[#item.rules + 1] = {label=label, clause=clause}
                key[#key + 1] = tostring(clause) .. "=" .. tostring(label)
            end
        end
        model.sources[#model.sources + 1] = item
    end
    model.key = table.concat(key, "|")
    return model
end

-- Top of an Indicator's Visibility tab: When to Show, where a panel entry
-- keeps its Show & Hide Rules. A checklist: the auras first (the main one
-- with Match when there are several), then every spell/item source and its
-- rules. It shows when the auras pass and every rule row does.
local function BuildWhenToShow(container, group, changed)
    local source = I.Primary(group)
    if not source then
        Hint(container,"Add spells, items, or auras in the field at the top.")
        return
    end
    local aura = I.IsAura(group)

    -- One checklist text for both kinds: order never matters to the user.
    local whenHeading, whenCollapsed = Section(container,"When to Show","indicator_whenToShow",whenToShow.conditions)
    ST._ChainHeadingBadges(whenHeading, ST._CreateInfoButton(whenHeading.frame, whenHeading.label,
        "LEFT", "RIGHT", 4, 0, {"When to Show",
            {"Shows when every rule on every checked row is true. Visibility settings still apply.", 1, 1, 1, true},
            " ",
            {"Checked spells and items must be available to you, or it stays hidden.", 1, 1, 1, true},
            " ",
            {"Add spells, items, or auras in the field at the top.", 1, 1, 1, true},
            " ",
            {"With one aura, its timer and stacks feed the display. Its sounds still play when other rules hide it.", 1, 1, 1, true},
            " ",
            {"With several auras, each has its own When and unit, and Match decides whether all or any must hold. There is no timer or count.", 1, 1, 1, true}},
        CS.tabInfoButtons))
    if whenCollapsed then return end
    local settings = I.Settings(group)
    if settings.sourceVisibility ~= nil and not aura then
        Check(ST._BeginRowGrid(container),{label="Use Saved Source Visibility",setting=whenToShow.sourceVisibility,value=settings.sourceVisibility,
            tooltip={"Source Visibility",{"Preserves the source's saved cooldown, charge, item, and usability visibility rules. They must also allow the Indicator to show.",1,1,1,true}},
            onChange=function(value) settings.sourceVisibility=value; changed() end})
    end
    -- The aura list first (main aura heading it), then the rule sources.
    local list = I.AuraList(group)
    for _, entry in ipairs(list) do BuildSourceRules(container, group, entry, changed) end
    for _, entry in ipairs(group.buttons or {}) do
        if not I.IsListedAura(group, entry) then BuildSourceRules(container, group, entry, changed) end
    end
end

local function BuildReadoutGear(panel, group, key, changed)
    local settings = I.Settings(group)
    local r = settings.readouts
    local groupId = CS.selectedGroup
    if key == "label" then
        Dropdown(panel,{setting=labelContent.labelType,list={name="Source Name",custom="Custom Text"},
            order={"name","custom"},value=r.label ~= "none" and r.label or r.lastLabel or "name",
            onChange=function(value)
                if r.label == "none" then r.lastLabel=value else r.label=value end
                changed(true)
            end})
        if r.label == "custom" then
            Edit(panel,{setting=labelContent.customText,value=r.customText or "",onEnterPressed=function(value)
                r.customText=value; settings.text.value=value; changed()
            end})
        end
    end
    -- Fonts live in `text`, shared by every display type; positions stay in
    -- the per-display readouts.
    local pos = positions[key]
    local font, size, outline, color = I.ReadoutFont(settings, key)
    ST._AddFontControls(panel, settings.text, key, {font=font, size=size, outline=outline, sizeMin=6, sizeMax=72},
        changed, {settings={size=pos.fontSize, font=pos.font, outline=pos.outline},
            previewRefresh=function()
                if ST._RefreshButtonsPreviewMirror then ST._RefreshButtonsPreviewMirror(groupId) end
            end})
    ST._AddColorRow(panel,{setting=pos.color,hasAlpha=true,tbl=settings.text,key=key.."FontColor",
        default=CopyTable(color),onConfirm=changed})
    Dropdown(panel,{setting=pos.anchor,list=anchors,order=anchorOrder,value=r[key.."Anchor"],
        onChange=function(value) r[key.."Anchor"]=value; r[key.."X"],r[key.."Y"]=0,0; changed(true) end})
    for _, axis in ipairs({"X","Y"}) do
        local field=key..axis
        Slider(panel,{setting=pos[axis],min=-300,max=300,step=1,value=r[field] or 0,
            onRelease=function(value) r[field]=value; changed() end})
    end
    -- The panel's Low Time rows, on this Indicator's timer keys.
    if key == "timer" then
        ST._AddDurationLowTimeRows(panel, r, function() changed() end, {
            inline=true, summaryTarget=I.IsAura(group) and "Aura" or "Cooldown",
            settings={enabled=pos.lowTime, warningThreshold=pos.lowTimeWarning, warningColor=pos.lowTimeWarningColor,
                critical=pos.lowTimeCritical, criticalThreshold=pos.lowTimeCriticalThreshold,
                criticalColor=pos.lowTimeCriticalColor, decimals=pos.lowTimeDecimals},
            rebuild=function() changed(true) end,
            preview=function()
                if ST._RefreshButtonsPreviewMirror then ST._RefreshButtonsPreviewMirror(groupId) end
            end,
        })
    end
end

-- Effects tab, aura Indicators whose live display shows: the Pandemic rows.
-- The effect glows an Icon and recolors Texture and Text; the marker rides
-- the duration text.
local TURNON_PANDEMIC_EFFECT = "Enable Pandemic Effect"
local TURNON_PANDEMIC_MARKER = "Enable Pandemic Marker"
local function BuildPandemic(container, group, changed)
    local settings = I.Settings(group)
    local r, p = settings.readouts, settings.pandemic
    -- Icons glow, Texture and Text recolor; Text needs a label or timer to.
    local showEffect, showMarker = I.PandemicEffectApplies(group), r.timer == true
    local glow = settings.displayType == "icon"
    if not showMarker and CS.CloseAdvancedSettingsPanel then
        CS.CloseAdvancedSettingsPanel({settingKey="indicatorPandemicMarker"})
    end
    if not glow and CS.CloseAdvancedSettingsPanel then
        CS.CloseAdvancedSettingsPanel({settingKey="indicatorPandemicGlow"})
    end
    if not (showEffect or showMarker) then return end
    local _, collapsed = Section(container,"Pandemic","indicator_pandemic")
    if collapsed then return end
    local column = ST._BeginRowGrid(container)
    local groupId = CS.selectedGroup
    local function refresh() changed() end
    local enabled = I.PandemicEffectOn(group)
    local row = showEffect and Check(column,{setting=pandemic.effect,value=enabled,onChange=function(value)
        p.pandemicEffectEnabled = value and true or false
        changed(true)
    end})
    -- No effect row on Text with neither label nor timer: nothing to recolor.
    if row and not glow then
        local texture = settings.displayType == "texture"
        ST._AnchorRowBadge(row, ST._CreateInfoButton(row.frame, row.frame, "LEFT", "LEFT", 0, 0, {
            "Pandemic Effect",
            {texture and "Recolors the texture while its aura is in the refresh window, where recasting adds bonus time."
                or "Recolors the text while its aura is in the refresh window, where recasting adds bonus time.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {texture and "Auras that gain no time when refreshed never show it."
                or "On auras that gain no time when refreshed, only the timer recolors, in its last 30%.", 1, 1, 1, true},
        }, CS.tabInfoButtons))
        if enabled then
            ST._AddColorRow(column,{setting=pandemic.color,tbl=p,key="pandemicGlowColor",
                default=CopyTable(ST.DEFAULT_PANDEMIC_COLOR),indent=true,onConfirm=function() changed(true) end})
        end
    elseif row then
        ST._AddAdvancedToggle(row,"indicatorPandemicGlow",CS.tabInfoButtons,true,{
            title="Pandemic Effect Advanced",
            build=function(panel)
                ST._BuildPandemicGlowControls(panel, p, refresh, {settings=pandemicGlow,
                    previewRefresh=function()
                        if ST._RefreshButtonsPreviewMirror then ST._RefreshButtonsPreviewMirror(groupId) end
                    end})
            end,
            unlock=not enabled and {enable={label=TURNON_PANDEMIC_EFFECT,run=function()
                p.pandemicEffectEnabled=true; changed(true)
            end}} or nil,
        })
        ST._AnchorRowBadge(row, ST._CreateInfoButton(row.frame, row.frame, "LEFT", "LEFT", 0, 0, {
            "Pandemic Effect",
            {"Glows the Indicator while its aura is in the refresh window, where recasting adds bonus time.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"Auras that gain no time when refreshed never show it.", 1, 1, 1, true},
        }, CS.tabInfoButtons))
    end
    if showMarker then
        local row = ST._AddPandemicMarkerControls(column, r, function() changed(true); return true end, refresh,
            {enableOnly=true, defaultMode="off", setting=pandemic.marker})
        ST._AddAdvancedToggle(row,"indicatorPandemicMarker",CS.tabInfoButtons,true,{
            title="Pandemic Marker Advanced",
            build=function(panel)
                ST._AddPandemicMarkerControls(panel, r, refresh, function() ST._RefreshActiveAdvancedSettingsPanel() end,
                    {childrenOnly=true, settings=pandemicMarker, noColoring=I.PandemicRecolorsText(group)})
            end,
            unlock=(r.pandemicMarkerMode or "off") == "off" and {enable={label=TURNON_PANDEMIC_MARKER,run=function()
                -- On, not Auto: Auto marks target auras only, so it would do
                -- nothing on an Indicator tracking a buff on the player.
                r.pandemicMarkerMode="on"; changed(true)
            end}} or nil,
        })
        ST._AddPandemicMarkerInfo(row)
    end
end

local function BuildText(container, group, changed)
    local settings = I.Settings(group)
    local r = settings.readouts
    local _, collapsed = Section(container,"Text","indicator_text")
    if collapsed then return end
    local column = ST._BeginRowGrid(container)
    -- While Missing has no timer or count to show.
    for _, key in ipairs(LiveReadouts(group) and {"label","timer","count"} or {"label"}) do
        local readout = key
        local descriptor = text[ReadoutRowKey(group, readout)]
        local countKey = CountReadoutKey(group)
        local function SetEnabled(value)
            if readout == "label" then
                if value then r.label=r.lastLabel or "name"
                else r.lastLabel=r.label; r.label="none" end
            elseif readout == "timer" then r.timer=value
            else r.count=value and countKey or "none" end
            changed(true)
        end
        local enabled = Enabled(settings, readout)
        local row = Check(column,{setting=descriptor,value=enabled,onChange=SetEnabled})
        local title = descriptor.label:gsub("^Show ", "")
        ST._AddAdvancedToggle(row,"indicatorText_"..readout,CS.tabInfoButtons,true,{
            title=title.." Advanced",
            build=function(panel) BuildReadoutGear(panel,group,readout,changed) end,
            unlock=not enabled and {enable={label="Enable "..title,run=function() SetEnabled(true) end}} or nil,
        })
        -- Duration Format leads the duration text, as on a panel's Text section.
        if readout == "timer" and enabled then
            ST._AddDurationFormatDropdown(column, r, changed, {setting=text.timerFormat})
        end
    end
end

local function BuildAppearance(container, group, changed)
    local settings = I.Initialize(group)
    local _, displayCollapsed = Section(container,"Display","indicator_display")
    if not displayCollapsed then
        local column = ST._BeginRowGrid(container)
        Dropdown(column,{setting=display.displayType,list={icon="Icon",texture="Texture",text="Text"},
            order={"icon","texture","text"},value=settings.displayType,
            onChange=function(value)
                I.SetDisplayType(group,value)
                -- Text Only has no pandemic glow; don't leave its editor open.
                if value == "text" and CS.CloseAdvancedSettingsPanel then
                    CS.CloseAdvancedSettingsPanel({settingKey="indicatorPandemicGlow"})
                end
                changed(true)
            end})
        if settings.displayType == "icon" then
            local actions = {{text="Choose...",onClick=function() ST._OpenTriggerPanelIconPicker(CS.selectedGroup) end}}
            -- Only a chosen icon has anything to reset.
            if settings.icon.manualIcon then
                actions[2] = {text="Reset",tooltip={"Reset Icon","Use the source's icon again."},
                    onClick=function() settings.icon.manualIcon=nil; changed(true) end}
            end
            Label(column,{label="Icon",controlWidget=ActionStrip(actions)})
        elseif settings.displayType == "texture" then
            Label(column,{label="Texture",controlWidget=ActionStrip({{text="Choose...",
                onClick=function() ST._OpenStandaloneTexturePicker(CS.selectedGroup) end}})})
        else
            Slider(column,{setting=display.width,min=20,max=600,step=1,value=settings.text.width or 180,
                onRelease=function(value) settings.text.width=value; changed() end})
            Slider(column,{setting=display.height,min=10,max=300,step=1,value=settings.text.height or 48,
                onRelease=function(value) settings.text.height=value; changed() end})
            ST._AddColorRow(column,{setting=display.background,hasAlpha=true,tbl=settings.text,key="textBgColor",onConfirm=changed})
        end
    end
    if settings.displayType == "icon" then
        ST._BuildTriggerIconAppearanceTab(container,group)
    elseif settings.displayType == "texture" then
        ST._BuildTexturePanelAppearanceTab(container,group)
    end
    BuildText(container, group, changed)
    if settings.displayType == "texture" and LiveReadouts(group) then
        local _, drainCollapsed = Section(container,"Duration Drain","indicator_drain")
        if not drainCollapsed then
            local column = ST._BeginRowGrid(container)
            Check(column,{setting=drainSettings.progress,value=settings.progress.enabled,
                onChange=function(value) settings.progress.enabled=value; changed(true) end})
            if settings.progress.enabled then
                Dropdown(column,{setting=drainSettings.direction,list={down="Top to Bottom",up="Bottom to Top",left="Right to Left",right="Left to Right"},
                    order={"down","up","right","left"},value=settings.progress.direction,
                    onChange=function(value) settings.progress.direction=value; changed() end})
                Slider(column,{setting=drainSettings.dim,min=0,max=1,step=0.05,value=settings.progress.dimAlpha,
                    onRelease=function(value) settings.progress.dimAlpha=value; changed() end})
            end
        end
    end
end

function ST._BuildIndicatorTab(container, group, tab)
    local changed = MakeChanged(group)
    I.Initialize(group)
    if tab == "loadconditions" then BuildWhenToShow(container,group,changed)
    elseif not I.Primary(group) then Hint(container,"Add spells, items, or auras in the field at the top.")
    elseif tab == "appearance" then BuildAppearance(container,group,changed)
    elseif tab == "effects" then
        -- One effect grammar for every source; aura rows omit the controls
        -- that would start or stop effects on their own.
        ST._BuildTriggerEffectsTab(container,group)
        if I.ShowsLiveDisplay(group) then BuildPandemic(container,group,changed) end
        if not I.IsAura(group) and I.Primary(group).type == "spell" then
            Dropdown(container,{setting=ST._IndicatorSoundSettings.sourceSounds,
                list={source="Source Cooldown",indicator="Indicator Appears"},order={"indicator","source"},
                value=I.UsesSourceSounds(group) and "source" or "indicator",
                onChange=function(value) I.Settings(group).sourceSounds=value == "source"; changed(true) end})
        end
        ST._BuildEntrySoundAlertsSection(container,group,I.Primary(group),CS.tabInfoButtons,ST._IndicatorSoundSettings)
    end
end
