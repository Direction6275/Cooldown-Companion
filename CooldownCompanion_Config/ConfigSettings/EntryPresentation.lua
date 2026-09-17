local ADDON_NAME, ST = ...
local Addon = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

local function OrdinaryOwner(context)
    local group = context.group
    group = group and (group._attachedBarOwner or group._unifiedPanelOwner or group)
    return ST.PanelSupportsAttachedBars(group) and group or nil
end
local function AttachedContext(context)
    local group = OrdinaryOwner(context)
    return group and context.group._attachedBarOwner
        and ST.PanelUsesAttachedBarLayout(group) or false
end
local function AttachmentApplies(context)
    local owner = OrdinaryOwner(context)
    if not owner or not context.group._attachedBarOwner then return false end
    return ST._PanelHasConfiguredModuleBars(context.groupId) or ST.AttachedBarGapApplies(owner)
end
local presentationSetting = ST._DefineSettingRoute({
    idPrefix = "entry.settings.presentation", scope = "entry", rowScope = "detail",
    tab = "settings", section = "presentation", sectionLabel = "Display as",
    applies = function(context) return OrdinaryOwner(context) ~= nil end,
}):Settings({ display = { label = "Display as", aliases = { "icon", "bar", "presentation" } } })
local chargeSetting = ST._DefineSettingRoute({
    idPrefix = "entry.settings.charges", scope = "entry", rowScope = "detail",
    tab = "settings", section = "charges", sectionLabel = "Charges",
    applies = function(context) return ST.CanSegmentEntryCharges(context.group, context.buttonData) end,
}):Settings({ segmented = { label = "Segment Charges", aliases = { "charge bars", "segmented charges" } } })
local panelSettings = ST._DefineSettingRoute({
    idPrefix = "panel.layout.bars", scope = "panel", rowScope = "primary",
    tab = "layout", tabLabel = "Layout", section = "arrangement", sectionLabel = "Arrangement",
    collapseKeys = { "layout_arrangement" },
}):Settings({
    mode = { label = "Bar Arrangement", aliases = { "grid", "collapsing stack" }, applies = function(context)
        local group = OrdinaryOwner(context)
        return group and context.group._attachedBarOwner and ST.GetPanelLayoutKind(group) == "bars" or false
    end },
    spacing = { label = "Stack Spacing", aliases = { "Bar Spacing", "Attached Bar Spacing" }, collapseKeys = { "layout_attached" }, applies = AttachmentApplies },
    gap = { label = "Distance from Panel", aliases = { "Distance from icons", "Gap from anchor" }, collapseKeys = { "layout_attached" }, applies = function(context)
        local owner = OrdinaryOwner(context)
        return AttachmentApplies(context) and not (ST.GetPanelLayoutKind(owner) == "bars" and ST.GetBarOnlyLayoutMode(owner) == "stack")
    end },
    gridSpacing = { label = "Grid Spacing", applies = function(context)
        local owner = OrdinaryOwner(context)
        return owner and context.group._attachedBarOwner and ST.GetPanelLayoutKind(owner) == "bars"
            and ST.GetBarOnlyLayoutMode(owner) == "grid" or false
    end },
    stackGap = { label = "Stack offset", applies = function(context)
        local owner = OrdinaryOwner(context)
        return owner and context.group._attachedBarOwner and ST.GetPanelLayoutKind(owner) == "bars"
            and ST.GetBarOnlyLayoutMode(owner) == "stack" or false
    end },
})
local placementSettings = ST._DefineSettingRoute({
    idPrefix = "entry.layout.bar_placement", scope = "entry", rowScope = "primary",
    tab = "layout", tabLabel = "Layout", section = "arrangement", sectionLabel = "Arrangement",
    collapseKeys = { "layout_arrangement" }, applies = AttachedContext,
}):Settings({
    side = { label = "Side", aliases = { "above", "below", "left", "right" } },
    region = { label = "Anchor to", aliases = { "main icons", "entire icon region" } },
    resources = { label = "Resources", aliases = { "before Resources", "after Resources" } },
})

local function FlushPresentationEditors()
    if ST._FlushSettingsEdits then ST._FlushSettingsEdits() end
    if ST._ReleaseTextFormatTabEditor then ST._ReleaseTextFormatTabEditor() end
    Addon:ClearAllConfigPreviews()
end
ST._FlushPresentationEditors = FlushPresentationEditors

function ST._BuildEntryPresentation(container, group, entry)
    if not ST.PanelSupportsAttachedBars(group) then return end
    local groupId, index = CS.selectedGroup, CS.selectedButton
    ST._AddDropdownRow(container, {
        label = "Display as", setting = presentationSetting.display,
        list = { icons = "Icon", bars = "Bar" }, order = { "icons", "bars" },
        value = ST.GetEntryPresentation(group, entry),
        onChange = function(value)
            FlushPresentationEditors()
            -- A released dropdown must never edit whichever entry has since
            -- taken its old numeric index.
            if CS.selectedGroup ~= groupId or CS.selectedButton ~= index or group.buttons[index] ~= entry then return end
            Addon:SetEntryPresentation(groupId, index, value)
            Addon:RefreshConfigPanel()
        end,
    })
end

function ST._BuildEntryChargePresentation(container, group, entry)
    if not ST.CanSegmentEntryCharges(group, entry) then return end
    local context = ST._CreatePanelSettingsContext(group)
    ST._AddCheckboxRow(container, {
        label = "Segment Charges", setting = chargeSetting.segmented,
        value = entry.barSegmentCharges == true,
        onChange = function(value)
            if not context:IsCurrent() then return end
            FlushPresentationEditors()
            if not context:IsCurrent() then return end
            entry.barSegmentCharges = value
            Addon:UpdateGroupStyle(context.panelId)
            Addon:RefreshConfigPanel()
        end,
    })
end

function ST._BuildAttachedBarLayout(container, group)
    if not ST.PanelSupportsAttachedBars(group) then return false end
    local context = ST._CreatePanelSettingsContext(group)
    local entry = context.entry
    if not entry or context.presentation ~= "bars" or not ST.PanelUsesAttachedBarLayout(group) then return false end
    container = ST._NewPanelSettingsSectionHost(container, context)
    local groupId = CS.selectedGroup
    local function refresh()
        Addon:UpdateGroupStyle(groupId)
        Addon:RefreshConfigPanel()
    end
    local _, collapsed = ST._BuildCollapsibleSection(container, "Bar Placement", "layout_arrangement", nil, nil, { leftAligned = true })
    if collapsed then return true end
    local side, region, resources = ST.GetAttachedBarPlacement(entry)
    local function place(key, value)
        FlushPresentationEditors()
        if not context:IsCurrent() then return end
        entry.barPlacement = entry.barPlacement or {}
        entry.barPlacement[key] = value
        refresh()
    end
    ST._AddDropdownRow(container, {
        label = "Side", setting = placementSettings.side, value = side,
        list = { above = "Above", below = "Below", left = "Left", right = "Right" },
        order = { "above", "below", "left", "right" },
        onChange = function(value) place("side", value) end,
    })
    ST._AddDropdownRow(container, {
        label = "Anchor to", setting = placementSettings.region, value = region,
        list = { main = "Main icons", outer = "Entire icon region" }, order = { "main", "outer" },
        onChange = function(value) place("region", value) end,
    })
    ST._AddDropdownRow(container, {
        label = "Resources", setting = placementSettings.resources, value = resources,
        list = { before = "Before Resources", after = "After Resources" }, order = { "before", "after" },
        onChange = function(value) place("resources", value) end,
    })
    return true
end

function ST._BuildUnifiedPanelArrangement(container, group, buildGrid)
    group = group._settingsOwner or group
    if not ST.PanelSupportsAttachedBars(group) then return false end
    local contents = ST._GetPanelSettingsContents(group)
    local presentations = contents.icons and { "icons" } or contents.bars and { "bars" } or {}
    for _, presentation in ipairs(presentations) do
        local context = ST._CreatePanelSettingsContext(group, presentation)
        local host = ST._NewPanelSettingsSectionHost(container, context)
        local _, collapsed = ST._BuildCollapsibleSection(host,
            presentation == "icons" and "Icon Arrangement" or "Bar-only Arrangement",
            "layout_arrangement", nil, nil, { leftAligned = true })
        if not collapsed then
            if presentation == "icons" then buildGrid(host, context.group, #(group.buttons or {}))
            else
                local note = AceGUI:Create("Label")
                note:SetFullWidth(true)
                note:SetText("Used when the panel contains only bars.")
                host:AddChild(note)
                ST._AddDropdownRow(host, { setting = panelSettings.mode, value = ST.GetBarOnlyLayoutMode(group),
                    list = { grid = "Grid", stack = "Collapsing Stack" }, order = { "grid", "stack" },
                    onChange = function(value)
                        FlushPresentationEditors()
                        if not context:IsCurrent() then return end
                        group.barOnlyLayout = group.barOnlyLayout or {}
                        group.barOnlyLayout.mode = value
                        Addon:RefreshGroupFrame(context.panelId)
                        Addon:RefreshConfigPanel()
                    end,
                })
                if ST.GetBarOnlyLayoutMode(group) == "grid" then
                    buildGrid(host, context.group, #(group.buttons or {}))
                    ST._AddSliderRow(host, { setting = panelSettings.gridSpacing,
                        value = context.writeStyle.buttonSpacing or ST.BUTTON_SPACING, min = -10, max = 100, step = 0.1,
                        onChange = function(value)
                            ST._PreviewScalarSetting(context.writeStyle, "buttonSpacing", value, ST._RefreshSelectedButtonsPreview)
                        end,
                        onRelease = function(value)
                            context.writeStyle.buttonSpacing = value
                            if context:IsCurrent() then Addon:UpdateGroupStyle(context.panelId) end
                        end,
                    })
                else
                    ST._AddSliderRow(host, { setting = panelSettings.stackGap,
                        value = group.barOnlyLayout and group.barOnlyLayout.stackGap or 0, min = 0, max = 80, step = 0.1,
                        onChange = function(value)
                            if not context:IsCurrent() then return end
                            group.barOnlyLayout = group.barOnlyLayout or { mode = "stack" }
                            group.barOnlyLayout.stackGap = value
                            Addon:UpdateGroupStyle(context.panelId)
                        end,
                    })
                end
            end
        end
    end
    local context = ST._CreatePanelSettingsContext(group, "bars")
    if not AttachmentApplies({ group = context.group, groupId = context.panelId }) then return true end
    local host = ST._NewPanelSettingsSectionHost(container, context)
    local _, collapsed = ST._BuildCollapsibleSection(host, "Attached Bars", "layout_attached", nil, nil, { leftAligned = true })
    if not collapsed then
        local fields = { { "spacing", 3, 40 } }
        if not (ST.GetPanelLayoutKind(group) == "bars" and ST.GetBarOnlyLayoutMode(group) == "stack") then
            fields[#fields + 1] = { "gap", 3, 80 }
        end
        for _, field in ipairs(fields) do
            local key = field[1]
            ST._AddSliderRow(host, { setting = panelSettings[key],
                value = group.attachedBarLayout and group.attachedBarLayout[key] or field[2], min = 0, max = field[3], step = 0.1,
                tooltip = key == "gap" and { "Distance from Panel",
                    { "Distance from the selected panel region to the first bar or block on each side.", 1, 1, 1, true } }
                    or { "Stack Spacing",
                        { "Space between attached bars, including Resources and the cast bar, or bars arranged in a Collapsing Stack.", 1, 1, 1, true } },
                onChange = function(value)
                    if not context:IsCurrent() then return end
                    group.attachedBarLayout = group.attachedBarLayout or {}
                    group.attachedBarLayout[key] = value
                    Addon:UpdateGroupStyle(context.panelId)
                end,
            })
        end
    end
    return true
end
