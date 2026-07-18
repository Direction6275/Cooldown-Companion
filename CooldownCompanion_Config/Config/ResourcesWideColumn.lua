--[[
    CooldownCompanion - Config/ResourcesWideColumn
    Wide column 3 for the Resources home: the pinned Layout & Order
    preview (sharing the split divider and persisted split fraction from
    ButtonsWideColumn) above the resources settings surfaces relocated
    from column 4 - the resources tab page, per-resource settings, the
    Custom Bar detail tabs, and the Custom Bar multi-select. The Custom
    Bars & Resources list lives in column 2 (Column2.lua).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local SetConfigCustomBarSettingsTab = ST._SetConfigCustomBarSettingsTab
local PruneConfigCustomBarSelection = ST._PruneConfigCustomBarSelection
local SetConfigResourceSettingsSpecID = ST._SetConfigResourceSettingsSpecID
local PruneConfigResourceSelection = ST._PruneConfigResourceSelection
local BlockCustomBarExportForResourceBarConflict = ST._BlockCustomBarExportForResourceBarConflict

local function ClearInfoButtons(buttons)
    if type(buttons) ~= "table" then
        return
    end

    for _, btn in ipairs(buttons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(buttons)
end

local function HideWidgetFrame(widget)
    if widget and widget.frame then
        widget.frame:Hide()
    end
end

local function FindCustomBarById(settings, customBarId)
    if not customBarId then
        return nil
    end

    if ST._RB and ST._RB.FindCustomBarById then
        return ST._RB.FindCustomBarById(settings, customBarId)
    end

    if not CooldownCompanion.GetSpecCustomAuraBars then
        return nil
    end

    for _, entry in ipairs(CooldownCompanion:GetSpecCustomAuraBars() or {}) do
        if type(entry) == "table" and entry.customBarId == customBarId then
            return entry
        end
    end
    return nil
end

local function FindSelectedCustomBar()
    return FindCustomBarById(CooldownCompanion:GetResourceBarSettings(), CS.selectedCustomBarId)
end

local function GetCustomBarEntryTabs(entry)
    local tabs = {
        { value = "appearance", text = "Appearance" },
    }

    tabs[#tabs + 1] = { value = "soundalerts", text = "Sound Alerts" }
    tabs[#tabs + 1] = { value = "loadconditions", text = "Load Conditions" }
    return tabs
end

local function IsCustomBarEntryTabAllowed(entry, tab)
    if tab == "appearance" or tab == "soundalerts" or tab == "loadconditions" then
        return true
    end
    return false
end

local function GetCustomBarDetailScrollKey()
    if not CS.selectedCustomBarId then return nil end
    return tostring(CS.selectedCustomBarId) .. ":" .. tostring(CS.customBarSettingsTab or "appearance")
end

local function GetResourceSettingsDetailScrollKey()
    if not CS.selectedResourcePowerType or not CS.resourceSettingsSpecID then return nil end
    return tostring(CS.selectedResourcePowerType) .. ":" .. tostring(CS.resourceSettingsSpecID)
end

local function GetResourceSettingsSpecTabText(info, specID)
    local specName = (info and info.name) or tostring(specID)
    local icon = info and info.icon
    if icon and icon ~= "" then
        return string.format("|T%s:13:13:0:0|t %s", tostring(icon), specName)
    end
    return specName
end

local function GetResourceSettingsSpecTabs(powerType)
    local RBP = ST._RBP
    if not (RBP and RBP.GetResourceApplicableSpecIDs and RBP.GetPlayerSpecOptionsConfig) then
        return {}
    end

    local _, _, specInfoByID = RBP.GetPlayerSpecOptionsConfig()
    local tabs = {}
    for _, specID in ipairs(RBP.GetResourceApplicableSpecIDs(powerType) or {}) do
        local info = specInfoByID and specInfoByID[specID] or nil
        tabs[#tabs + 1] = {
            value = tostring(specID),
            text = GetResourceSettingsSpecTabText(info, specID),
        }
    end
    return tabs
end

-- Hides every surface this file owns and releases the shared divider if
-- the resources preview host holds it. Called from every view branch that
-- takes col3 over (buttons wide view, cast frames, the normal fall-through,
-- the talent picker) and at the top of this view's own refresh.
local function HideResourcesWideSurfaces(col3)
    HideWidgetFrame(col3._resourcesConflictScroll)
    HideWidgetFrame(col3._resourcesTabGroup)
    HideWidgetFrame(col3._resourceSettingsTabGroup)
    HideWidgetFrame(col3._customBarEntryTabGroup)
    HideWidgetFrame(col3._customBarsMultiSelectScroll)
    local host = col3._resourcesPreviewHost
    if host then
        if col3.buttonsSplitDivider and col3._cdcActiveWideHost == host then
            col3.buttonsSplitDivider:CancelDrag()
            col3.buttonsSplitDivider:Hide()
        end
        if ST._ClearActiveWidePreview then
            ST._ClearActiveWidePreview(col3, host)
        end
        host:Hide()
    end
end

-- Profile conflict: the gate replaces the whole wide column.
local function ShowResourcesConflictScroll(col3)
    if not col3._resourcesConflictScroll then
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(col3.content)
        col3._resourcesConflictScroll = scroll
    end

    local scroll = col3._resourcesConflictScroll
    scroll.frame:ClearAllPoints()
    scroll.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
    scroll.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
    scroll:ReleaseChildren()
    scroll.frame:Show()

    local RBP = ST._RBP
    if RBP and RBP.BuildResourceBarConflictGate
        and RBP.BuildResourceBarConflictGate(scroll, "Layout & Order", true)
    then
        return
    end

    local label = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText("Resolve Resource Bars before editing Layout & Order.")
    label:SetFullWidth(true)
    scroll:AddChild(label)
end

-- Pinned Layout & Order preview at the top of the wide column, registered
-- as the active wide preview so the shared divider drags and the persisted
-- split reapply rebuild it.
local function UpdateResourcesPreviewHost(col3)
    local host = col3._resourcesPreviewHost
    if not host then
        host = CreateFrame("Frame", nil, col3.content)
        host:SetClipsChildren(false)
        col3._resourcesPreviewHost = host
    end
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
    host:SetPoint("TOPRIGHT", col3.content, "TOPRIGHT", 0, 0)
    if ST._SetActiveWidePreview then
        ST._SetActiveWidePreview(col3, host, function(hostFrame)
            if ST._BuildLayoutOrderPanel then
                ST._BuildLayoutOrderPanel(hostFrame)
            end
        end)
    end
    if ST._ComputeWidePreviewHostHeight then
        host:SetHeight(ST._ComputeWidePreviewHostHeight(col3))
    end
    host:Show()
    ST._BuildLayoutOrderPanel(host)
end

-- Targeted preview rebuild (value changes that only affect the layout
-- preview), without a full config refresh.
local function RefreshResourcesLayoutPreview()
    if not CS.resourcesEntrySelected then return end
    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3._resourcesPreviewHost
    if host and host:IsShown() and ST._BuildLayoutOrderPanel then
        ST._BuildLayoutOrderPanel(host)
    end
end

local function ShowCustomBarMultiSelect(col3, selectedIds, selectedEntries)
    if not col3._customBarsMultiSelectScroll then
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(col3.content)
        col3._customBarsMultiSelectScroll = scroll
    end
    local scroll = col3._customBarsMultiSelectScroll
    ST._AnchorButtonsContentFrame(col3, scroll.frame)
    scroll:ReleaseChildren()
    scroll.frame:Show()

    local heading = AceGUI:Create("Heading")
    heading:SetText(#selectedEntries .. " Custom Bars Selected")
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", heading.label, "RIGHT", 5, 0)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local function AddSpacer()
        local sp = AceGUI:Create("Label")
        sp:SetText(" ")
        sp:SetFullWidth(true)
        local f, _, fl = sp.label:GetFont()
        sp:SetFont(f, 3, fl or "")
        scroll:AddChild(sp)
    end

    local anyDisabled = false
    for _, entry in ipairs(selectedEntries) do
        if entry.enabled ~= true then
            anyDisabled = true
            break
        end
    end

    local enableBtn = AceGUI:Create("Button")
    enableBtn:SetText(anyDisabled and "Enable Selected" or "Disable Selected")
    enableBtn:SetFullWidth(true)
    enableBtn:SetCallback("OnClick", function()
        for _, entry in ipairs(selectedEntries) do
            entry.enabled = anyDisabled and true or false
            if entry.enabled and not entry.trackingMode then
                entry.trackingMode = "active"
            end
        end
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(enableBtn)

    AddSpacer()

    local exportBtn = AceGUI:Create("Button")
    exportBtn:SetText("Export Selected")
    exportBtn:SetFullWidth(true)
    exportBtn:SetCallback("OnClick", function()
        if BlockCustomBarExportForResourceBarConflict and BlockCustomBarExportForResourceBarConflict() then
            return
        end
        local settings = CooldownCompanion:GetResourceBarSettings()
        local payload = ST._RB.BuildCustomBarsExportPayload and ST._RB.BuildCustomBarsExportPayload(settings, selectedEntries)
        local exportString = payload and ST._EncodeExportData and ST._EncodeExportData(payload)
        if exportString then
            CS.ShowPopupAboveConfig("CDC_EXPORT_CUSTOM_BARS", nil, { exportString = exportString })
        else
            CooldownCompanion:Print("Export failed: Custom Bar data was unavailable.")
        end
    end)
    scroll:AddChild(exportBtn)

    AddSpacer()

    local deleteBtn = AceGUI:Create("Button")
    deleteBtn:SetText("Delete Selected")
    deleteBtn:SetFullWidth(true)
    deleteBtn:SetCallback("OnClick", function()
        CS.ShowPopupAboveConfig("CDC_DELETE_SELECTED_CUSTOM_BARS", #selectedIds, { ids = selectedIds })
    end)
    scroll:AddChild(deleteBtn)
end

local function ShowResourceSettingsPanel(col3)
    local tabs = GetResourceSettingsSpecTabs(CS.selectedResourcePowerType)
    if #tabs == 0 then
        return false
    end
    if SetConfigResourceSettingsSpecID then
        SetConfigResourceSettingsSpecID(CS.resourceSettingsSpecID)
    end
    if not CS.resourceSettingsSpecID then
        return false
    end

    if not col3._resourceSettingsTabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")
        tabGroup.frame:SetParent(col3.content)
        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            SetConfigResourceSettingsSpecID(tab)
            widget:ReleaseChildren()

            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            col3._resourceSettingsDetailScroll = scroll
            col3._resourceSettingsDetailScrollKey = GetResourceSettingsDetailScrollKey()
            if ST._BuildResourceSettingsPanel then
                ST._BuildResourceSettingsPanel(scroll, CS.selectedResourcePowerType, CS.resourceSettingsSpecID)
            else
                local label = AceGUI:Create("Label")
                ST._ConfigureWrappedHelperLabel(label)
                label:SetText("|cff888888Resource settings are unavailable.|r")
                label:SetFullWidth(true)
                scroll:AddChild(label)
            end
        end)
        col3._resourceSettingsTabGroup = tabGroup
    end

    local tabGroup = col3._resourceSettingsTabGroup
    ST._AnchorButtonsContentFrame(col3, tabGroup.frame)
    tabGroup:SetTabs(tabs)
    tabGroup.frame:Show()

    local savedOffset, savedScrollvalue
    local currentScrollKey = GetResourceSettingsDetailScrollKey()
    if col3._resourceSettingsDetailScroll and col3._resourceSettingsDetailScrollKey == currentScrollKey then
        local state = col3._resourceSettingsDetailScroll.status or col3._resourceSettingsDetailScroll.localstatus
        if state and state.offset and state.offset > 0 then
            savedOffset = state.offset
            savedScrollvalue = state.scrollvalue
        end
    end

    tabGroup:SelectTab(tostring(CS.resourceSettingsSpecID))

    if savedOffset and col3._resourceSettingsDetailScroll then
        local state = col3._resourceSettingsDetailScroll.status or col3._resourceSettingsDetailScroll.localstatus
        if state then
            state.offset = savedOffset
            state.scrollvalue = savedScrollvalue
        end
    end

    return true
end

local function ShowCustomBarDetail(col3, selectedEntry)
    if CS.customBarSettingsTab == "settings"
        or CS.customBarSettingsTab == "layout"
        or CS.customBarSettingsTab == "anchor"
        or CS.customBarSettingsTab == "alpha"
    then
        SetConfigCustomBarSettingsTab("appearance")
    end
    if not IsCustomBarEntryTabAllowed(selectedEntry, CS.customBarSettingsTab) then
        SetConfigCustomBarSettingsTab("appearance")
    end

    if not col3._customBarEntryTabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")
        tabGroup.frame:SetParent(col3.content)
        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            SetConfigCustomBarSettingsTab(tab)
            ClearInfoButtons(CS.customBarInfoButtons)
            widget:ReleaseChildren()

            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            col3._customBarsDetailScroll = scroll
            col3._customBarDetailScrollKey = GetCustomBarDetailScrollKey()
            ST._BuildCustomAuraBarPanel(scroll, CS.selectedCustomBarId, CS.customBarSettingsTab)
        end)
        col3._customBarEntryTabGroup = tabGroup
    end

    local tabGroup = col3._customBarEntryTabGroup
    ST._AnchorButtonsContentFrame(col3, tabGroup.frame)
    tabGroup:SetTabs(GetCustomBarEntryTabs(selectedEntry))
    tabGroup.frame:Show()

    local savedOffset, savedScrollvalue
    local currentScrollKey = GetCustomBarDetailScrollKey()
    if col3._customBarsDetailScroll and col3._customBarDetailScrollKey == currentScrollKey then
        local state = col3._customBarsDetailScroll.status or col3._customBarsDetailScroll.localstatus
        if state and state.offset and state.offset > 0 then
            savedOffset = state.offset
            savedScrollvalue = state.scrollvalue
        end
    end

    tabGroup:SelectTab(CS.customBarSettingsTab or "appearance")

    if savedOffset and col3._customBarsDetailScroll then
        local state = col3._customBarsDetailScroll.status or col3._customBarsDetailScroll.localstatus
        if state then
            state.offset = savedOffset
            state.scrollvalue = savedScrollvalue
        end
    end
end

-- Default page for the Resources home: the tabbed shared settings view.
-- Re-hosts the existing bars-mode builders unmodified: General = anchoring,
-- Appearance = bar text styling, Layout = positioning, Health (when the
-- health resource is enabled). The Layout & Order preview lives in the
-- pinned host above this page, not in a tab.
local function ShowResourcesTabPage(col3)
    if not col3._resourcesTabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")
        tabGroup.frame:SetParent(col3.content)
        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            CS.resourcesSettingsTab = tab
            -- Clean up info buttons from the previous tab before recycling widgets
            ClearInfoButtons(CS.tabInfoButtons)
            widget:ReleaseChildren()
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            col3._resourcesDetailScroll = scroll
            col3._resourcesDetailScrollKey = "resources:" .. tab
            if tab == "general" then
                ST._BuildResourceBarAnchoringPanel(scroll)
            elseif tab == "appearance" then
                ST._BuildResourceBarBarTextStylingPanel(scroll)
            elseif tab == "layout" then
                ST._BuildResourceBarPositioningPanel(scroll)
            elseif tab == "health" then
                ST._BuildResourceBarHealthStylingPanel(scroll)
            end
        end)
        col3._resourcesTabGroup = tabGroup
    end

    local tabGroup = col3._resourcesTabGroup
    ST._AnchorButtonsContentFrame(col3, tabGroup.frame)

    local settings = CooldownCompanion:GetResourceBarSettings()
    local RESOURCE_HEALTH = ST._RB and ST._RB.RESOURCE_HEALTH
    local health = settings and settings.resources and RESOURCE_HEALTH
        and settings.resources[RESOURCE_HEALTH]
    local healthEnabled = health and health.enabled == true

    local tabs = {
        { value = "general", text = "General" },
        { value = "appearance", text = "Appearance" },
        { value = "layout", text = "Layout" },
    }
    if healthEnabled then
        tabs[#tabs + 1] = { value = "health", text = "Health" }
    end
    tabGroup:SetTabs(tabs)

    local tab = CS.resourcesSettingsTab
    local valid = { general = true, appearance = true, layout = true }
    if healthEnabled then valid.health = true end
    if not tab or not valid[tab] then tab = "general" end
    CS.resourcesSettingsTab = tab

    -- Preserve scroll position across value-change refreshes (same pattern
    -- as the custom-bar detail tabs)
    local savedOffset, savedScrollvalue
    local currentScrollKey = "resources:" .. tab
    if col3._resourcesDetailScroll and col3._resourcesDetailScrollKey == currentScrollKey then
        local state = col3._resourcesDetailScroll.status or col3._resourcesDetailScroll.localstatus
        if state and state.offset and state.offset > 0 then
            savedOffset = state.offset
            savedScrollvalue = state.scrollvalue
        end
    end

    tabGroup.frame:Show()
    tabGroup:SelectTab(tab)

    if savedOffset and col3._resourcesDetailScroll then
        local state = col3._resourcesDetailScroll.status or col3._resourcesDetailScroll.localstatus
        if state then
            state.offset = savedOffset
            state.scrollvalue = savedScrollvalue
        end
    end
end

-- Refresh for the Resources home while Resource Bars are enabled (the
-- disabled empty state keeps its wide intro pane in Column3.lua). Pinned
-- preview on top, then exactly one settings surface below the divider.
local function RefreshResourcesWideColumn(col3)
    -- Everything restarts hidden; the active surface re-shows below.
    HideResourcesWideSurfaces(col3)

    if CooldownCompanion.GetCurrentResourceBarConflict and CooldownCompanion:GetCurrentResourceBarConflict() then
        ShowResourcesConflictScroll(col3)
        return
    end

    local settings = CooldownCompanion:GetResourceBarSettings()
    local function CustomBarExists(customBarId)
        return FindCustomBarById(settings, customBarId) ~= nil
    end
    PruneConfigCustomBarSelection(CustomBarExists, true)
    if PruneConfigResourceSelection then
        local RBP = ST._RBP
        PruneConfigResourceSelection(function(powerType)
            if not (RBP and RBP.IsResourceEditableInColumn4) then
                return false
            end
            return RBP.IsResourceEditableInColumn4(powerType, settings)
        end)
    end

    UpdateResourcesPreviewHost(col3)

    local selectedCustomBarIds = {}
    local selectedCustomBarEntries = {}
    for customBarId in pairs(CS.selectedCustomBars) do
        local entry = FindCustomBarById(settings, customBarId)
        selectedCustomBarIds[#selectedCustomBarIds + 1] = customBarId
        selectedCustomBarEntries[#selectedCustomBarEntries + 1] = entry
    end
    table.sort(selectedCustomBarIds)

    if #selectedCustomBarEntries >= 2 then
        ShowCustomBarMultiSelect(col3, selectedCustomBarIds, selectedCustomBarEntries)
    elseif CS.selectedResourcePowerType and ShowResourceSettingsPanel(col3) then
        -- Per-resource settings shown.
    else
        local selectedEntry = CS.selectedCustomBarId and FindSelectedCustomBar()
        if selectedEntry then
            ShowCustomBarDetail(col3, selectedEntry)
        else
            if CS.selectedCustomBarId then
                PruneConfigCustomBarSelection(CustomBarExists, true)
            end
            ShowResourcesTabPage(col3)
        end
    end

    -- Final height pass: the settings surface just anchored below the
    -- divider, so re-clamp the persisted split against current overhead.
    if ST._ReapplyPanelPreviewSplit then
        ST._ReapplyPanelPreviewSplit()
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshResourcesWideColumn = RefreshResourcesWideColumn
ST._HideResourcesWideSurfaces = HideResourcesWideSurfaces
ST._RefreshResourcesLayoutPreview = RefreshResourcesLayoutPreview
