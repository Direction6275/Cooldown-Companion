-- One display and its sources. Aura readouts are configured, never queried.
local _, ST = ...
local Addon, I, CS = ST.Addon, ST.Indicator, ST._configState
local AceGUI = LibStub("AceGUI-3.0")
local Dropdown, Check, Slider = ST._AddDropdownRow, ST._AddCheckboxRow, ST._AddSliderRow
local Label, Edit = ST._AddLabelRow, ST._AddEditBoxRow
local anchors = {TOPLEFT="Top Left",TOP="Top",TOPRIGHT="Top Right",LEFT="Left",CENTER="Center",
    RIGHT="Right",BOTTOMLEFT="Bottom Left",BOTTOM="Bottom",BOTTOMRIGHT="Bottom Right"}
local anchorOrder = {"TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT"}

local function Route(tab, section)
    return ST._DefineSettingRoute({idPrefix="panel.indicator."..section, scope="panel",rowScope="primary",
        tab=tab,tabLabel=tab == "tracking" and "Tracking" or tab == "effects" and "Effects" or "Appearance",section=section,
        sectionLabel="Indicator", applies=function(context)
            return ST.IsIndicatorGroup(context.group) and (tab == "tracking" or I.Primary(context.group) ~= nil)
        end})
end
local function Applies(predicate)
    return function(context)
        local g=context.group
        return ST.IsIndicatorGroup(g) and I.Primary(g) ~= nil and predicate(g,I.Settings(g))
    end
end
local texture = Applies(function(_,s) return s.displayType == "texture" end)
local drain = Applies(function(_,s) return s.displayType == "texture" and s.progress.enabled == true end)
local textOnly = Applies(function(_,s) return s.displayType == "text" end)
local function HasText(settings)
    local r = settings.readouts
    return r.label ~= "none" or r.timer == true or r.count ~= "none"
end
local textEnabled = Applies(function(_,s) return HasText(s) end)
local labelEnabled = Applies(function(_,s) return s.readouts.label ~= "none" end)
local function CountReadoutKey(group)
    return I.IsAura(group) and "stacks" or I.Primary(group).type == "spell" and "charges" or "item"
end
local appearance = Route("appearance", "display"):Settings({
    displayType={label="Display",aliases={"indicator","texture","icon","text"}},
    label={label="Label"},timer={label="Timer"},
    stacks={label="Aura Stacks",aliases={"count"},applies=Applies(function(g) return CountReadoutKey(g) == "stacks" end)},
    charges={label="Charges / Display Count",applies=Applies(function(g) return CountReadoutKey(g) == "charges" end)},
    item={label="Item Count",applies=Applies(function(g) return CountReadoutKey(g) == "item" end)},
    progress={label="Duration Drain",aliases={"depletion","dim silhouette"},applies=texture},
    direction={label="Drain Direction",applies=drain},dim={label="Dim Silhouette",applies=drain},
    labelType={label="Label Content",advancedKey="indicatorText",applies=labelEnabled},
    fontSize={label="Text Size",advancedKey="indicatorText",applies=textEnabled},
    customText={label="Custom Label",advancedKey="indicatorText",applies=Applies(function(_,s) return s.readouts.label == "custom" end)},
    width={label="Width",applies=textOnly},height={label="Height",applies=textOnly},
    font={label="Font",advancedKey="indicatorText",applies=textEnabled},
    outline={label="Font Outline",advancedKey="indicatorText",applies=textEnabled},
    color={label="Text Color",advancedKey="indicatorText",applies=textEnabled},
    background={label="Text Background",advancedKey="indicatorText",applies=Applies(function(_,s) return s.displayType == "text" and HasText(s) end)},
    timerFormat={label="Timer Format",advancedKey="indicatorText",applies=Applies(function(_,s) return s.readouts.timer == true end)},
})
local tracking = Route("tracking", "source"):Settings({source={label="Source"},
    sourceVisibility={label="Use Saved Source Visibility",applies=Applies(function(g,s) return s.sourceVisibility ~= nil and not I.IsAura(g) end)},
    conditions={label="Show When",aliases={"conditions","ready","on cooldown","always"},applies=Applies(function(g) return not I.IsAura(g) end)},
    unit={label="Aura Unit",applies=Applies(function(g) return I.IsAura(g) end)}})

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

local positions = {}
for _,key in ipairs({"label","timer","count"}) do
    local readout=key
    local name=key:sub(1,1):upper()..key:sub(2)
    local shown=Applies(function(_,s)
        local r=s.readouts
        return readout == "timer" and r.timer == true or readout ~= "timer" and r[readout] ~= "none"
    end)
    positions[key]=Route("appearance", key.."Position"):Settings({
        anchor={label=name.." Anchor",advancedKey="indicatorText",applies=shown},
        X={label=name.." X",advancedKey="indicatorText",applies=shown}, Y={label=name.." Y",advancedKey="indicatorText",applies=shown},
    })
end

local function Button(container, label, callback)
    local button = AceGUI:Create("Button")
    button:SetText(label)
    button:SetAutoWidth(true)
    button:SetCallback("OnClick", callback)
    container:AddChild(button)
    return button
end

local function Heading(container, text, setting)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    heading:SetFullWidth(true)
    ST._ApplyLeftAlignedHeading(heading,nil,true)
    container:AddChild(heading)
    if setting and ST._BindSettingWidget then
        ST._BindSettingWidget(heading,setting,text)
        local onRelease = heading.events and heading.events.OnRelease
        heading:SetCallback("OnRelease",function(widget,event,...)
            widget._cdcSettingDescriptor=nil
            if onRelease then onRelease(widget,event,...) end
        end)
    end
    return heading
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

local function ShowWhen(entry)
    local clauses = entry.triggerConditions or {}
    -- Always can still have additional checks. Remember that explicit choice
    -- so adding one does not silently turn the selector into Custom.
    if entry.indicatorShowWhen == "always" then return "always" end
    if #clauses == 0 then return "always" end
    if clauses[1].unavailable then return "custom" end
    if clauses[1].key == "cooldownActive" and clauses[1].state == nil then
        return clauses[1].expected == false and "ready" or "cooldown"
    end
    return "custom"
end

local function BuildConditions(container, entry, first, changed)
    local clauses = entry.triggerConditions or {}
    for clauseIndex = first, #clauses do
        local ci, clause = clauseIndex, clauses[clauseIndex]
        local choices, order = Addon:GetTriggerConditionTypeOptions(entry)
        local filtered = {}
        for _, key in ipairs(order) do if I.ConditionKeys[key] then filtered[#filtered+1]=key end end
        if clause.unavailable or not I.ConditionKeys[clause.key] then
            local offered = false
            for _, key in ipairs(filtered) do if key == clause.key then offered = true end end
            choices[clause.key] = "Unavailable: " .. tostring(clause.key)
            if not offered then filtered[#filtered+1] = clause.key end
            Hint(container,"This saved condition cannot match. Replace or remove it to enable this display.")
        end
        local left, right = ST._BeginRowGrid(container)
        Dropdown(left,{label="Check",list=choices,order=filtered,value=clause.key,
            onChange=function(value)
                local _,values=Addon:GetTriggerConditionExpectedOptions(value)
                local initial=values[1]
                clauses[ci]={key=value,expected=initial ~= "false",
                    state=initial ~= "true" and initial ~= "false" and initial or nil}
                entry.triggerConditions=clauses; changed(true)
            end})
        local states,stateOrder=Addon:GetTriggerConditionExpectedOptions(clause.key)
        Dropdown(right,{label="State",list=states,order=stateOrder,
            value=clause.state or (clause.expected == false and "false" or "true"),
            onChange=function(value)
                clause.state=value ~= "true" and value ~= "false" and value or nil
                clause.expected=value ~= "false"; changed()
            end})
        Button(right,"Remove Condition",function() table.remove(clauses,ci); entry.triggerConditions=clauses; changed(true) end)
    end
    local left = ST._BeginRowGrid(container)
    Button(left,"Add Condition",function()
        clauses[#clauses+1]={key="usable",expected=true}; entry.triggerConditions=clauses; changed(true)
    end)
end

local function BuildTracking(container, group, changed)
    local source = I.Primary(group)
    if not source then
        Label(container, {setting=tracking.source, controlText="No source"})
        Hint(container,"Add a spell, aura, or item using the search field below the preview.")
        return
    end
    -- Search targets the stable heading; the source name is display content.
    Heading(container,"Source",tracking.source)
    local sourceLeft, sourceRight = ST._BeginRowGrid(container)
    local kind = I.IsAura(group) and "Aura" or source.type == "spell" and "Spell"
        or Addon.IsEquipmentSlotEntry(source) and "Equipment" or "Item"
    local icon = ST._GetButtonIcon(source)
    local sourceRow = Label(sourceLeft,{
        label=(icon and "|T"..tostring(icon)..":16:16|t " or "")..(source.name or tostring(source.id)),controlText=kind})
    ST._AddAdvancedToggle(sourceRow,"indicatorSource",CS.tabInfoButtons,true,{
        title="Source Settings",build=function(panel)
            Button(panel,#group.buttons > 1 and "Remove All Sources" or "Remove Source",
                function() I.ClearSource(group); changed(true) end)
        end,
    })
    local replacing = CS.GetIndicatorSourceReplacement(CS.selectedGroup)
    Button(sourceRight,replacing and "Cancel Change" or "Change...",function()
        CS.indicatorSourceReplacement = not replacing and {
            groupId=CS.selectedGroup,group=group,profile=Addon.db.profile,source=source,
        } or nil
        CS.HideAutocomplete()
        if replacing then
            CS.pendingWideAddFocus = nil
            CS.panelAddModeQuery = ""
            Addon:RefreshConfigPanel()
        else
            FocusSourceSearch()
        end
    end)
    if replacing then
        Hint(container,"Choose a replacement below the preview. Replacing the source resets its conditions; appearance is kept.")
    end
    Heading(container,"When to Show")
    local settings = I.Settings(group)
    if settings.sourceVisibility ~= nil and not I.IsAura(group) then
        local rules = ST._BeginRowGrid(container)
        Check(rules,{label="Use Saved Source Visibility",setting=tracking.sourceVisibility,value=settings.sourceVisibility,
            tooltip={"Source Visibility",{"Preserves the source's saved cooldown, charge, item, and usability visibility rules.",1,1,1,true}},
            onChange=function(value) settings.sourceVisibility=value; changed() end})
    end
    if I.IsAura(group) then
        Hint(container,"While this aura is active")
        local left = ST._BeginRowGrid(container)
        local automaticSource = CopyTable(source)
        automaticSource.auraUnitOverride = nil
        local automaticUnit = Addon:ResolveStandaloneAuraDefaultUnit(automaticSource)
        local units = {automatic="Automatic ("..(automaticUnit == "target" and "Target" or "Player")..")",
            player="Player",target="Target",group="Group (Your Buffs)",pet="Pet"}
        local scope = source.auraTrackPet and "pet" or source.auraTrackGroup and "group"
            or source.auraUnitOverride or "automatic"
        Dropdown(left,{setting=tracking.unit,list=units,
            order={"automatic","player","target","group","pet"},value=scope,
            onChange=function(value)
                source.auraUnitOverride=(value == "player" or value == "target") and value or nil
                source.auraTrackGroup = value == "group" or nil
                source.auraTrackPet = value == "pet" or nil
                if source.auraTrackGroup or source.auraTrackPet then source.auraUnitOverride = "player" end
                source.auraUnit=Addon:ResolveStandaloneAuraDefaultUnit(source)
                changed()
            end})
    else
        local left = ST._BeginRowGrid(container)
        local mode = ShowWhen(source)
        local list, order = {ready="Ready",cooldown="On Cooldown",always="Always"},{"ready","cooldown","always"}
        if mode == "custom" then list.custom="Custom Conditions"; order[#order+1]="custom" end
        Dropdown(left,{setting=tracking.conditions,list=list,order=order,value=mode,
            onChange=function(value)
                if value == "custom" then return end
                local clauses=source.triggerConditions or {}
                if mode == "ready" or mode == "cooldown" then table.remove(clauses,1) end
                if value ~= "always" then table.insert(clauses,1,{key="cooldownActive",expected=value == "cooldown"}) end
                source.indicatorShowWhen = value == "always" and "always" or nil
                source.triggerConditions=clauses; changed(true)
            end})
        if #group.buttons > 1 or #(source.triggerConditions or {}) > ((mode == "ready" or mode == "cooldown") and 1 or 0) then
            Hint(container,"All additional conditions must also match.")
        end
        BuildConditions(container,source,(mode == "ready" or mode == "cooldown") and 2 or 1,changed)
        for index, entry in ipairs(group.buttons or {}) do
            if entry ~= source then
                local entryIndex = index
                Heading(container,"Also Check: " .. (entry.name or tostring(entry.id)))
                local entryLeft, entryRight = ST._BeginRowGrid(container)
                Check(entryLeft,{label="Use This Source",value=entry.enabled ~= false,
                    onChange=function(value) entry.enabled=value; changed() end})
                Button(entryRight,"Remove Source",function() table.remove(group.buttons, entryIndex); changed(true) end)
                BuildConditions(container,entry,1,changed)
            end
        end
        Hint(container,"Add another spell or item below the preview for an additional source. Combat and specialization limits are in Visibility.")
    end
end

local function BuildTextFormatting(container, group, changed)
    local settings = I.Settings(group)
    local r = settings.readouts
    if r.label ~= "none" then
        Dropdown(container,{setting=appearance.labelType,list={name="Source Name",custom="Custom Text"},
            order={"name","custom"},value=r.label,onChange=function(value)
                r.label=value; changed(true)
            end})
        if r.label == "custom" then
            Edit(container,{setting=appearance.customText,value=r.customText or "",onEnterPressed=function(value)
                r.customText=value; settings.text.value=value; changed()
            end})
        end
    end
    if r.timer then
        Dropdown(container,{setting=appearance.timerFormat,pulloutWidth=230,
            list={clock="1:30 / 45 / 8",units="1m 30s / 45s / 8s",decimal_under_10="1:30 / 45 / 8.7"},
            tooltip={"Timer Format",
                {"Examples show 1 minute 30 seconds, 45 seconds, and 8.7 seconds remaining.",1,1,1,true},
                {"The last option shows decimals only below 10 seconds.",1,1,1,true}},
            order={"clock","units","decimal_under_10"},value=r.durationFormat,onChange=function(value) r.durationFormat=value; changed() end})
    end
    Slider(container,{setting=appearance.fontSize,min=6,max=72,step=1,value=settings.text.textFontSize,
        onRelease=function(value) settings.text.textFontSize=value; changed() end})
    local font = Dropdown(container,{setting=appearance.font,pulloutWidth=300})
    CS.SetupFontDropdown(font)
    font:SetValue(settings.text.textFont or "Friz Quadrata TT")
    CS.SetFontDropdownCallback(font,function(_,_,value) settings.text.textFont=value; changed() end)
    local outline = Dropdown(container,{setting=appearance.outline})
    CS.SetupFontOutlineDropdown(outline)
    outline:SetValue(settings.text.textFontOutline or "OUTLINE")
    CS.SetFontOutlineDropdownCallback(outline,function(_,_,value) settings.text.textFontOutline=value; changed() end)
    ST._AddColorRow(container,{setting=appearance.color,hasAlpha=true,tbl=settings.text,key="textFontColor",onConfirm=changed})
    if settings.displayType == "text" then
        ST._AddColorRow(container,{setting=appearance.background,hasAlpha=true,tbl=settings.text,key="textBgColor",onConfirm=changed})
    end
    for _, key in ipairs({"label","timer","count"}) do
        local enabled=key == "label" and r.label ~= "none" or key == "timer" and r.timer or key == "count" and r.count ~= "none"
        if enabled then
            local function positionChanged()
                changed()
            end
            Dropdown(container,{setting=positions[key].anchor,list=anchors,order=anchorOrder,value=r[key.."Anchor"],
                onChange=function(value) r[key.."Anchor"]=value; r[key.."X"],r[key.."Y"]=0,0; positionChanged() end})
            for _, axis in ipairs({"X","Y"}) do
                local field=key..axis
                Slider(container,{setting=positions[key][axis],min=-300,max=300,step=1,value=r[field] or 0,
                    onRelease=function(value) r[field]=value; positionChanged() end})
            end
        end
    end
end

local function BuildAppearance(container, group, changed)
    local settings = I.Initialize(group)
    Heading(container,"Display")
    local displayLeft, displayRight = ST._BeginRowGrid(container)
    Dropdown(displayLeft,{setting=appearance.displayType,list={icon="Icon",texture="Texture",text="Text"},
        order={"icon","texture","text"},value=settings.displayType,
        onChange=function(value) I.SetDisplayType(group,value); changed(true) end})
    if settings.displayType == "icon" then
        Button(displayRight,"Choose Icon",function() ST._OpenTriggerPanelIconPicker(CS.selectedGroup) end)
        Button(displayRight,"Use Source Icon",function() settings.icon.manualIcon=nil; changed() end)
        ST._BuildTriggerIconAppearanceTab(container,group)
    elseif settings.displayType == "texture" then
        Button(displayRight,"Choose Texture",function() ST._OpenStandaloneTexturePicker(CS.selectedGroup) end)
        ST._BuildTexturePanelAppearanceTab(container,group)
    else
        local left, right = ST._BeginRowGrid(container)
        Slider(left,{setting=appearance.width,min=20,max=600,step=1,value=settings.text.width or 180,
            onRelease=function(value) settings.text.width=value; changed() end})
        Slider(right,{setting=appearance.height,min=10,max=300,step=1,value=settings.text.height or 48,
            onRelease=function(value) settings.text.height=value; changed() end})
    end
    Heading(container,"Text")
    local r = settings.readouts
    local left, right = ST._BeginRowGrid(container)
    Check(left,{setting=appearance.label,value=r.label ~= "none",onChange=function(value)
        if value then r.label=r.lastLabel or "name"
        else r.lastLabel=r.label; r.label="none" end
        changed(true)
    end})
    Check(left,{setting=appearance.timer,value=r.timer,onChange=function(value) r.timer=value; changed(true) end})
    local countKey = CountReadoutKey(group)
    Check(right,{setting=appearance[countKey],value=r.count ~= "none",
        onChange=function(value) r.count=value and countKey or "none"; changed(true) end})
    if HasText(settings) then
        local formattingRow = Label(right,{label="Formatting & Position"})
        ST._AddAdvancedToggle(formattingRow,"indicatorText",CS.tabInfoButtons,true,{
            title="Text Formatting",isAvailable=function() return HasText(settings) end,
            build=function(panel) BuildTextFormatting(panel,group,changed) end,
        })
    end
    if not HasText(settings) then Hint(container,"Enable a text readout to access formatting and position settings.") end
    if settings.displayType == "texture" then
        Heading(container,"Duration Drain")
        local container = ST._BeginRowGrid(container)
        Check(container,{setting=appearance.progress,value=settings.progress.enabled,
            onChange=function(value) settings.progress.enabled=value; changed(true) end})
        if settings.progress.enabled then
            Dropdown(container,{setting=appearance.direction,list={down="Top to Bottom",up="Bottom to Top",left="Right to Left",right="Left to Right"},
                order={"down","up","right","left"},value=settings.progress.direction,
                onChange=function(value) settings.progress.direction=value; changed() end})
            Slider(container,{setting=appearance.dim,min=0,max=1,step=0.05,value=settings.progress.dimAlpha,
                onRelease=function(value) settings.progress.dimAlpha=value; changed() end})
        end
    end
end

function ST._BuildIndicatorTab(container, group, tab)
    local id, profile = CS.selectedGroup, Addon.db.profile
    local function changed(rebuild)
        if Addon.db.profile ~= profile or profile.groups[id] ~= group then return end
        Addon:RefreshGroupFrame(id)
        Addon:RequestAuraRebind("style", id)
        if rebuild then Addon:RefreshConfigPanel()
        elseif ST._RefreshButtonsPreviewMirror then ST._RefreshButtonsPreviewMirror(id) end
    end
    I.Initialize(group)
    if tab == "tracking" then BuildTracking(container,group,changed)
    elseif not I.Primary(group) then Hint(container,"Choose a source in Tracking to set up this Indicator.")
    elseif tab == "appearance" then BuildAppearance(container,group,changed)
    elseif tab == "effects" then
        if I.IsAura(group) then ST._BuildTextureEffectsTab(container,group)
        else ST._BuildTriggerEffectsTab(container,group) end
        if not I.IsAura(group) and I.Primary(group).type == "spell" then
            Dropdown(container,{setting=ST._IndicatorSoundSettings.sourceSounds,
                list={source="Source Cooldown",indicator="Indicator Appears"},order={"indicator","source"},
                value=I.UsesSourceSounds(group) and "source" or "indicator",
                onChange=function(value) I.Settings(group).sourceSounds=value == "source"; changed(true) end})
        end
        ST._BuildEntrySoundAlertsSection(container,group,I.Primary(group),CS.tabInfoButtons,ST._IndicatorSoundSettings)
    end
end
