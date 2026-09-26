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
        tab=tab,tabLabel=tab == "tracking" and "Tracking" or "Appearance",section=section,
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
local appearance = Route("appearance", "display"):Settings({
    displayType={label="Display",aliases={"indicator","texture","icon","text"}},
    label={label="Label"},timer={label="Timer"},count={label="Count"},
    progress={label="Duration Drain",aliases={"depletion","dim silhouette"},applies=texture},
    direction={label="Drain Direction",applies=drain},dim={label="Dim Silhouette",applies=drain},preview={label="Preview Duration"},
    fontSize={label="Text Size"},customText={label="Custom Label",applies=Applies(function(_,s) return s.readouts.label == "custom" end)},
    width={label="Width",applies=textOnly},height={label="Height",applies=textOnly},
    font={label="Font"},outline={label="Font Outline"},color={label="Text Color"},background={label="Text Background"},
    timerFormat={label="Timer Format",applies=Applies(function(_,s) return s.readouts.timer == true end)},
})
local tracking = Route("tracking", "source"):Settings({source={label="Source"},conditions={label="Conditions",applies=Applies(function(g) return not I.IsAura(g) end)},unit={label="Aura Unit",applies=Applies(function(g) return I.IsAura(g) end)}})

local positions = {}
for _,key in ipairs({"label","timer","count"}) do
    local readout=key
    local name=key:sub(1,1):upper()..key:sub(2)
    local shown=Applies(function(_,s)
        local r=s.readouts
        return readout == "timer" and r.timer == true or readout ~= "timer" and r[readout] ~= "none"
    end)
    positions[key]=Route("appearance", key.."Position"):Settings({
        anchor={label=name.." Anchor",applies=shown}, X={label=name.." X",applies=shown}, Y={label=name.." Y",applies=shown},
    })
end

local function Button(container, label, callback)
    local button = AceGUI:Create("Button")
    button:SetText(label)
    button:SetAutoWidth(true)
    button:SetCallback("OnClick", callback)
    container:AddChild(button)
end

local function BuildTracking(container, group, changed)
    local source = I.Primary(group)
    Label(container, {setting=tracking.source, controlText=source and source.name or "No source"})
    if not source then
        Label(container,{label="Add a spell, aura, or item using the search field below the preview."})
        return
    end
    Button(container, "Clear Sources", function()
        I.ClearSource(group)
        changed(true)
    end)
    if I.IsAura(group) then
        Label(container,{label="Shows while this aura is active. Aura conditions cannot be combined."})
        Check(container,{label="Enable Source",value=source.enabled ~= false,
            onChange=function(value) source.enabled=value; changed() end})
        Dropdown(container,{setting=tracking.unit,list={automatic="Automatic",player="Player",target="Target"},
            order={"automatic","player","target"},value=source.auraUnitOverride or "automatic",
            onChange=function(value)
                source.auraUnitOverride=(value == "player" or value == "target") and value or nil
                source.auraTrackGroup,source.auraTrackPet=nil,nil
                source.auraUnit=Addon:ResolveStandaloneAuraDefaultUnit(source)
                changed()
            end})
    else
        Label(container,{setting=tracking.conditions, controlText="All must match"})
        for index, entry in ipairs(group.buttons or {}) do
            local entryIndex = index
            Label(container,{label=(index == 1 and "Primary: " or "Condition source: ") .. (entry.name or tostring(entry.id))})
            Check(container,{label="Use This Source",value=entry.enabled ~= false,
                onChange=function(value) entry.enabled=value; changed() end})
            if index > 1 then
                Button(container,"Remove Source",function() table.remove(group.buttons, entryIndex); changed(true) end)
            end
            local clauses = entry.triggerConditions or {}
            if #clauses == 0 then Label(container,{label="Always (when this source is available)"}) end
            for clauseIndex, clause in ipairs(clauses) do
                local ci = clauseIndex
                local choices, order = Addon:GetTriggerConditionTypeOptions(entry)
                choices.auraActive = nil
                local filtered = {}
                for _, key in ipairs(order) do if I.ConditionKeys[key] then filtered[#filtered+1]=key end end
                local left,right = ST._BeginRowGrid(container)
                Dropdown(left,{label="Check",list=choices,order=filtered,value=clause.key,
                    onChange=function(value)
                        local _,values=Addon:GetTriggerConditionExpectedOptions(value)
                        local initial=values[1]
                        clauses[ci]={key=value,expected=initial ~= "false",
                            state=initial ~= "true" and initial ~= "false" and initial or nil}
                        entry.triggerConditions=clauses; changed(true)
                    end})
                local states,stateOrder=Addon:GetTriggerConditionExpectedOptions(clause.key)
                local value=clause.state or (clause.expected == false and "false" or "true")
                Dropdown(right,{label="State",list=states,order=stateOrder,value=value,
                    onChange=function(selected)
                        clause.state = selected ~= "true" and selected ~= "false" and selected or nil
                        clause.expected = selected ~= "false"
                        changed()
                    end})
                Button(container,"Remove Condition",function() table.remove(clauses,ci); entry.triggerConditions=clauses; changed(true) end)
            end
            Button(container,"Add Condition",function()
                clauses[#clauses+1]={key="cooldownActive",expected=false}; entry.triggerConditions=clauses; changed(true)
            end)
        end
        Label(container,{label="Add another spell or item below the preview to use it as a condition source."})
    end
    ST._BuildEntrySoundAlertsSection(container, group, source, CS.tabInfoButtons)
end

local function BuildAppearance(container, group, changed)
    local settings = I.Initialize(group)
    Dropdown(container,{setting=appearance.displayType,list={icon="Icon",texture="Texture",text="Text Only"},
        order={"icon","texture","text"},value=settings.displayType,
        onChange=function(value) I.SetDisplayType(group,value); changed(true) end})
    if settings.displayType == "icon" then
        Button(container,"Choose Icon",function() ST._OpenTriggerPanelIconPicker(CS.selectedGroup) end)
        Button(container,"Use Source Icon",function() settings.icon.manualIcon=nil; changed() end)
        ST._BuildTriggerIconAppearanceTab(container,group)
    elseif settings.displayType == "texture" then
        Button(container,"Choose Texture",function() ST._OpenStandaloneTexturePicker(CS.selectedGroup) end)
        ST._BuildTexturePanelAppearanceTab(container,group)
    else
        Slider(container,{setting=appearance.width,min=20,max=600,step=1,value=settings.text.width or 180,
            onRelease=function(value) settings.text.width=value; changed() end})
        Slider(container,{setting=appearance.height,min=10,max=300,step=1,value=settings.text.height or 48,
            onRelease=function(value) settings.text.height=value; changed() end})
    end
    local r = settings.readouts
    Dropdown(container,{setting=appearance.label,list={none="None",name="Source Name",custom="Custom Text"},
        order={"none","name","custom"},value=r.label,onChange=function(value)
            r.label=value; settings.legacyTextMetrics=nil; changed(true)
        end})
    if r.label == "custom" then
        Edit(container,{setting=appearance.customText,value=r.customText or "",onEnterPressed=function(value)
            r.customText=value; settings.text.value=value; changed()
        end})
    end
    Check(container,{setting=appearance.timer,value=r.timer,onChange=function(value) r.timer=value; changed(true) end})
    if r.timer then
        Dropdown(container,{setting=appearance.timerFormat,list={clock="Minutes:Seconds",units="Time Units",decimal_under_10="Decimals Under 10s"},
            order={"clock","units","decimal_under_10"},value=r.durationFormat,onChange=function(value) r.durationFormat=value; changed() end})
    end
    local source=I.Primary(group)
    local countList,countOrder={none="None"},{"none"}
    if I.IsAura(group) then countList.stacks="Aura Stacks"; countOrder[2]="stacks"
    elseif source and source.type == "spell" then countList.charges="Charges / Display Count"; countOrder[2]="charges"
    elseif source then countList.item="Item Count"; countOrder[2]="item" end
    Dropdown(container,{setting=appearance.count,list=countList,order=countOrder,value=r.count,
        onChange=function(value) r.count=value; changed(true) end})
    Slider(container,{setting=appearance.fontSize,min=6,max=72,step=1,value=settings.text.textFontSize,
        onRelease=function(value) settings.text.textFontSize=value; changed() end})
    local fonts={}
    for name in pairs(LibStub("LibSharedMedia-3.0"):HashTable("font")) do fonts[name]=name end
    Dropdown(container,{setting=appearance.font,list=fonts,value=settings.text.textFont,
        onChange=function(value) settings.text.textFont=value; changed() end})
    Dropdown(container,{setting=appearance.outline,list={[""]="None",OUTLINE="Outline",THICKOUTLINE="Thick Outline"},
        order={"","OUTLINE","THICKOUTLINE"},value=settings.text.textFontOutline,
        onChange=function(value) settings.text.textFontOutline=value; changed() end})
    ST._AddColorRow(container,{setting=appearance.color,hasAlpha=true,tbl=settings.text,key="textFontColor",onConfirm=changed})
    ST._AddColorRow(container,{setting=appearance.background,hasAlpha=true,tbl=settings.text,key="textBgColor",onConfirm=changed})
    for _, key in ipairs({"label","timer","count"}) do
        local enabled=key == "label" and r.label ~= "none" or key == "timer" and r.timer or key == "count" and r.count ~= "none"
        if enabled then
            local name = key:sub(1,1):upper() .. key:sub(2)
            Dropdown(container,{setting=positions[key].anchor,list=anchors,order=anchorOrder,value=r[key.."Anchor"],
                onChange=function(value) r[key.."Anchor"]=value; r[key.."X"],r[key.."Y"]=0,0; changed() end})
            for _, axis in ipairs({"X","Y"}) do
                local field=key..axis
                Slider(container,{setting=positions[key][axis],min=-300,max=300,step=1,value=r[field] or 0,
                    onRelease=function(value) r[field]=value; changed() end})
            end
        end
    end
    if settings.displayType == "texture" then
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
    Dropdown(container,{setting=appearance.preview,list={full="Full",half="Half",empty="Empty",timeless="No Timer"},
        order={"full","half","empty","timeless"},value=CS.indicatorPreviewState or "half",
        onChange=function(value) CS.indicatorPreviewState=value; Addon:RefreshConfigPanel() end})
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
    elseif not I.Primary(group) then Label(container,{label="Choose a source in Tracking to set up this Indicator."})
    elseif tab == "appearance" then BuildAppearance(container,group,changed)
    elseif tab == "effects" then
        if I.IsAura(group) then ST._BuildTextureEffectsTab(container,group)
        else ST._BuildTriggerEffectsTab(container,group) end
    end
end
