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
        and (ST.GetPanelLayoutKind(group) == "mixed" or ST.GetBarOnlyLayoutMode(group) == "stack") or false
end
local presentationSetting = ST._DefineSettingRoute({
    idPrefix = "entry.settings.presentation", scope = "entry", rowScope = "detail",
    tab = "settings", section = "presentation", sectionLabel = "Display as",
    applies = function(context) return OrdinaryOwner(context) ~= nil end,
}):Settings({ display = { label = "Display as", aliases = { "icon", "bar", "presentation" } } })
local panelSettings = ST._DefineSettingRoute({
    idPrefix = "panel.layout.bars", scope = "panel", rowScope = "primary",
    tab = "layout", tabLabel = "Layout", section = "arrangement", sectionLabel = "Arrangement",
    collapseKeys = { "layout_arrangement" },
}):Settings({
    mode = { label = "Bar Arrangement", aliases = { "grid", "collapsing stack" }, applies = function(context)
        local group = OrdinaryOwner(context)
        return group and context.group._attachedBarOwner and ST.GetPanelLayoutKind(group) ~= "mixed" or false
    end },
    spacing = { label = "Bar spacing", applies = AttachedContext },
    gap = { label = "Gap from anchor", applies = AttachedContext },
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
    if ST._FlushTextFormatTabCommit then ST._FlushTextFormatTabCommit() end
    if ST._ReleaseTextFormatTabEditor then ST._ReleaseTextFormatTabEditor() end
    AceGUI:ClearFocus()
    Addon:ClearAllConfigPreviews()
end
ST._FlushPresentationEditors = FlushPresentationEditors

function ST._BuildPanelStyleView(container, group)
    if not ST.PanelSupportsAttachedBars(group) then return end
    local count = 0
    for _ in pairs(CS.selectedButtons or {}) do count = count + 1 end
    if count < 2 and CS.selectedButton and group.buttons[CS.selectedButton] then return end
    CS.panelStyleViews = CS.panelStyleViews or setmetatable({}, { __mode = "k" })
    ST._AddDropdownRow(container, {
        label = "Style", list = { icons = "Icons", bars = "Bars" }, order = { "icons", "bars" },
        value = CS.panelStyleViews[group] or (ST.GetPanelLayoutKind(group) == "bars" and "bars" or "icons"),
        onChange = function(value)
            FlushPresentationEditors()
            CS.panelStyleViews[group] = value
            Addon:RefreshConfigPanel()
        end,
    })
end

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
            if group.buttons[index] ~= entry then return end
            Addon:SetEntryPresentation(groupId, index, value)
            Addon:RefreshConfigPanel()
        end,
    })
end

function ST._BuildAttachedBarLayout(container, group)
    if not ST.PanelSupportsAttachedBars(group) then return false end
    local view = ST._ResolveStylingGroup(group)
    if not view._attachedBarOwner then return false end
    local groupId = CS.selectedGroup
    local entry = CS.selectedButton and group.buttons[CS.selectedButton]
    local count = 0
    for _ in pairs(CS.selectedButtons or {}) do count = count + 1 end
    if count >= 2 then entry = nil end
    local function refresh()
        Addon:UpdateGroupStyle(groupId)
        Addon:RefreshConfigPanel()
    end
    local kind = ST.GetPanelLayoutKind(group)
    if kind ~= "mixed" then
        ST._AddDropdownRow(container, {
            label = "Bar Arrangement", setting = panelSettings.mode, value = ST.GetBarOnlyLayoutMode(group),
            list = { grid = "Grid", stack = "Collapsing Stack" }, order = { "grid", "stack" },
            onChange = function(value)
                FlushPresentationEditors()
                group.barOnlyLayout = group.barOnlyLayout or {}
                group.barOnlyLayout.mode = value
                Addon:RefreshGroupFrame(groupId)
                Addon:RefreshConfigPanel()
            end,
        })
        if ST.GetBarOnlyLayoutMode(group) == "grid" then return false end
    end
    if entry then
        local side, region, resources = ST.GetAttachedBarPlacement(entry)
        local function place(key, value)
            FlushPresentationEditors()
            if group.buttons[CS.selectedButton or 0] ~= entry then return end
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
    else
        group.attachedBarLayout = group.attachedBarLayout or {}
        local layout = group.attachedBarLayout
        for _, field in ipairs({ { "spacing", "Bar spacing", 3, 0, 40 },
            { kind == "mixed" and "gap" or "stackGap", "Gap from anchor", kind == "mixed" and 3 or 0, 0, 80 } }) do
            local key = field[1]
            local owner = key == "stackGap" and group.barOnlyLayout or layout
            ST._AddSliderRow(container, {
                label = field[2], setting = key == "spacing" and panelSettings.spacing or panelSettings.gap,
                value = owner[key] or field[3], min = field[4], max = field[5], step = 1,
                onChange = function(value) owner[key] = value; Addon:UpdateGroupStyle(groupId) end,
            })
        end
    end
    return true
end
