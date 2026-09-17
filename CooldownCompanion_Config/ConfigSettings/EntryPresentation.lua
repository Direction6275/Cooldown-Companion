local ADDON_NAME, ST = ...
local Addon = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

local function OrdinaryOwner(context)
    local group = context.group
    group = group and (group._attachedBarOwner or group._unifiedPanelOwner or group)
    return ST.PanelSupportsAttachedBars(group) and group or nil
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
