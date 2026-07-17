--[[
    CooldownCompanion - Config/Column4
    RefreshColumn4, RefreshProfileBar.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local ResetConfigSelection = ST._ResetConfigSelection
local SetConfigCustomBarSettingsTab = ST._SetConfigCustomBarSettingsTab
local PruneConfigCustomBarSelection = ST._PruneConfigCustomBarSelection
local SetConfigResourceSettingsSpecID = ST._SetConfigResourceSettingsSpecID
local PruneConfigResourceSelection = ST._PruneConfigResourceSelection
local BlockCustomBarExportForResourceBarConflict = ST._BlockCustomBarExportForResourceBarConflict
local RefreshGroupSettingsHost = ST._RefreshGroupSettingsHost

------------------------------------------------------------------------
-- COLUMN 4: Group / Panel Settings Column
------------------------------------------------------------------------
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

local function AreResourceBarsConfigEnabled()
    local settings = CooldownCompanion:GetResourceBarSettings()
    return type(settings) == "table" and settings.enabled == true
end

local function HideWidgetFrame(widget)
    if widget and widget.frame then
        widget.frame:Hide()
    end
end

local function HideFrame(frame)
    if frame then
        frame:Hide()
    end
end

local function HideLayoutOrderConflictScroll(container)
    HideWidgetFrame(container.layoutOrderConflictScroll)
end

local function HideResourceBarPanelSurfaces(container)
    HideFrame(container.placeholderLabel)
    HideWidgetFrame(container.tabGroup)
    HideWidgetFrame(container.containerTabGroup)
    HideWidgetFrame(container.folderTabGroup)
    HideWidgetFrame(container.customAuraScroll)
    HideWidgetFrame(container.layoutOrderScroll)
    HideWidgetFrame(container.customBarsDetailScroll)
    HideWidgetFrame(container.customBarsMultiSelectScroll)
    HideWidgetFrame(container.customBarEntryTabGroup)
    HideWidgetFrame(container.resourceSettingsDetailScroll)
    HideWidgetFrame(container.resourceSettingsTabGroup)
    HideWidgetFrame(container.resourcesTabGroup)
    HideFrame(container.resourcesPreviewHost)
    HideWidgetFrame(container.castBarHomeTabGroup)
    HideFrame(container._castBarIntroPane)
    HideLayoutOrderConflictScroll(container)
end

local function ShowLayoutOrderConflictScroll(container)
    HideResourceBarPanelSurfaces(container)

    if not container.layoutOrderConflictScroll then
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(container)
        container.layoutOrderConflictScroll = scroll
    end

    local scroll = container.layoutOrderConflictScroll
    scroll.frame:SetParent(container)
    scroll.frame:ClearAllPoints()
    scroll.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    scroll.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
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

-- In the Resources and Cast Bar homes a persistent Layout & Order preview
-- pane occupies the top of the column; every settings surface anchors
-- beneath it. When no preview pane is shown (e.g. a per-bar detail page
-- replacing it) surfaces fill the whole column.
local function AnchorResourcesContentFrame(container, frame)
    frame:ClearAllPoints()
    local previewHost = container.resourcesPreviewHost
    if (CS.resourcesEntrySelected or CS.castFramesEntrySelected)
        and previewHost and previewHost:IsShown() then
        frame:SetPoint("TOPLEFT", previewHost, "BOTTOMLEFT", 0, -4)
        frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    else
        frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    end
end

local function ShowCustomBarMultiSelect(container, selectedIds, selectedEntries)
    HideFrame(container.placeholderLabel)
    HideWidgetFrame(container.customBarEntryTabGroup)
    HideWidgetFrame(container.customBarsDetailScroll)
    HideWidgetFrame(container.resourceSettingsTabGroup)
    HideWidgetFrame(container.resourceSettingsDetailScroll)
    if not container.customBarsMultiSelectScroll then
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(container)
        container.customBarsMultiSelectScroll = scroll
    end
    local scroll = container.customBarsMultiSelectScroll
    scroll.frame:SetParent(container)
    AnchorResourcesContentFrame(container, scroll.frame)
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

local function ShowResourceSettingsPanel(container)
    HideFrame(container.placeholderLabel)
    HideWidgetFrame(container.customBarEntryTabGroup)
    HideWidgetFrame(container.customBarsDetailScroll)
    HideWidgetFrame(container.customBarsMultiSelectScroll)

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

    if not container.resourceSettingsTabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")
        tabGroup.frame:SetParent(container)
        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            SetConfigResourceSettingsSpecID(tab)
            widget:ReleaseChildren()

            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            container.resourceSettingsDetailScroll = scroll
            container._resourceSettingsDetailScrollKey = GetResourceSettingsDetailScrollKey()
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
        container.resourceSettingsTabGroup = tabGroup
    end

    local tabGroup = container.resourceSettingsTabGroup
    AnchorResourcesContentFrame(container, tabGroup.frame)
    tabGroup:SetTabs(tabs)
    tabGroup.frame:Show()

    local savedOffset, savedScrollvalue
    local currentScrollKey = GetResourceSettingsDetailScrollKey()
    if container.resourceSettingsDetailScroll and container._resourceSettingsDetailScrollKey == currentScrollKey then
        local state = container.resourceSettingsDetailScroll.status or container.resourceSettingsDetailScroll.localstatus
        if state and state.offset and state.offset > 0 then
            savedOffset = state.offset
            savedScrollvalue = state.scrollvalue
        end
    end

    tabGroup:SelectTab(tostring(CS.resourceSettingsSpecID))

    if savedOffset and container.resourceSettingsDetailScroll then
        local state = container.resourceSettingsDetailScroll.status or container.resourceSettingsDetailScroll.localstatus
        if state then
            state.offset = savedOffset
            state.scrollvalue = savedScrollvalue
        end
    end

    return true
end

-- Tabbed settings page for the Resources home (col1 Resources button).
-- Re-hosts the existing bars-mode builders unmodified:
-- General = anchoring, Appearance = bar text styling, Layout = positioning,
-- Health (when the health resource is enabled). The Layout & Order preview
-- lives in the persistent pane above this page, not in a tab.
local function ShowResourcesTabPage(container)
    if not container.resourcesTabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")
        tabGroup.frame:SetParent(container)
        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            CS.resourcesSettingsTab = tab
            -- Clean up info buttons from the previous tab before recycling widgets
            for _, btn in ipairs(CS.tabInfoButtons) do
                btn:ClearAllPoints()
                btn:Hide()
                btn:SetParent(nil)
            end
            wipe(CS.tabInfoButtons)
            widget:ReleaseChildren()
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            container.resourcesDetailScroll = scroll
            container._resourcesDetailScrollKey = "resources:" .. tab
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
        container.resourcesTabGroup = tabGroup
    end

    local tabGroup = container.resourcesTabGroup
    AnchorResourcesContentFrame(container, tabGroup.frame)

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
    if container.resourcesDetailScroll and container._resourcesDetailScrollKey == currentScrollKey then
        local state = container.resourcesDetailScroll.status or container.resourcesDetailScroll.localstatus
        if state and state.offset and state.offset > 0 then
            savedOffset = state.offset
            savedScrollvalue = state.scrollvalue
        end
    end

    tabGroup.frame:Show()
    tabGroup:SelectTab(tab)

    if savedOffset and container.resourcesDetailScroll then
        local state = container.resourcesDetailScroll.status or container.resourcesDetailScroll.localstatus
        if state then
            state.offset = savedOffset
            state.scrollvalue = savedScrollvalue
        end
    end
end

local function RefreshColumn4(container)
    -- Hide browse placeholder
    if container._browsePlaceholder then
        container._browsePlaceholder:Hide()
    end
    HideLayoutOrderConflictScroll(container)

    -- Cast Bar & Unit Frames home: col4 = Cast Bar, with the persistent
    -- Layout & Order preview pane pinned at the top like the Resources home
    if CS.castFramesEntrySelected then
        HideResourceBarPanelSurfaces(container)
        if CooldownCompanion.GetCurrentResourceBarConflict and CooldownCompanion:GetCurrentResourceBarConflict() then
            ShowLayoutOrderConflictScroll(container)
            return
        end

        local settings = CooldownCompanion:GetCastBarSettings()
        if not (settings and settings.enabled) then
            if ST._ShowColumnIntroPane then
                ST._ShowColumnIntroPane(container, "_castBarIntroPane", {
                    title = "Cast Bar",
                    body = "Skin the Blizzard cast bar and anchor it to a panel, or position it anywhere on screen.",
                    buttonText = "Enable Cast Bar",
                    sideInset = 24,
                    onEnable = function()
                        local cb = CooldownCompanion:GetCastBarSettings()
                        if not cb then
                            return
                        end
                        cb.enabled = true
                        CooldownCompanion:EvaluateCastBar()
                        CooldownCompanion:UpdateAnchorStacking()
                        CooldownCompanion:RefreshConfigPanel()
                    end,
                })
            end
            return
        end

        local previewHost = container.resourcesPreviewHost
        if not previewHost then
            previewHost = CreateFrame("Frame", nil, container)
            previewHost:SetClipsChildren(false)
            container.resourcesPreviewHost = previewHost
        end
        previewHost:ClearAllPoints()
        previewHost:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        previewHost:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
        local columnHeight = container:GetHeight() or 0
        previewHost:SetHeight(math.max(150, math.floor(columnHeight * 0.35)))
        previewHost:Show()
        ST._BuildLayoutOrderPanel(previewHost)

        if not container.castBarHomeTabGroup then
            local tabGroup = AceGUI:Create("TabGroup")
            tabGroup:SetLayout("Fill")
            tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
                CS.castBarHomeTab = tab
                -- Clean up info buttons from the previous tab before recycling widgets
                for _, btn in ipairs(CS.tabInfoButtons) do
                    btn:ClearAllPoints()
                    btn:Hide()
                    btn:SetParent(nil)
                end
                wipe(CS.tabInfoButtons)
                widget:ReleaseChildren()
                local scroll = AceGUI:Create("ScrollFrame")
                scroll:SetLayout("List")
                widget:AddChild(scroll)
                container.castBarHomeScroll = scroll
                container._castBarHomeScrollKey = "castbar:" .. tab
                if tab == "general" then
                    ST._BuildCastBarAnchoringPanel(scroll)
                elseif tab == "appearance" then
                    ST._BuildCastBarStylingPanel(scroll)
                elseif tab == "layout" then
                    ST._BuildCastBarPositioningPanel(scroll)
                end
            end)
            tabGroup.frame:SetParent(container)
            container.castBarHomeTabGroup = tabGroup
        end

        local tabGroup = container.castBarHomeTabGroup
        AnchorResourcesContentFrame(container, tabGroup.frame)
        tabGroup:SetTabs({
            { value = "general", text = "General" },
            { value = "appearance", text = "Appearance" },
            { value = "layout", text = "Layout" },
        })

        local tab = CS.castBarHomeTab
        if tab ~= "general" and tab ~= "appearance" and tab ~= "layout" then
            tab = "general"
        end
        CS.castBarHomeTab = tab

        -- Preserve scroll position across value-change refreshes
        local savedOffset, savedScrollvalue
        local currentScrollKey = "castbar:" .. tab
        if container.castBarHomeScroll and container._castBarHomeScrollKey == currentScrollKey then
            local state = container.castBarHomeScroll.status or container.castBarHomeScroll.localstatus
            if state and state.offset and state.offset > 0 then
                savedOffset = state.offset
                savedScrollvalue = state.scrollvalue
            end
        end

        tabGroup.frame:Show()
        tabGroup:SelectTab(tab)

        if savedOffset and container.castBarHomeScroll then
            local state = container.castBarHomeScroll.status or container.castBarHomeScroll.localstatus
            if state then
                state.offset = savedOffset
                state.scrollvalue = savedScrollvalue
            end
        end
        return
    end

    -- Resources home: show selected Custom Bar settings, the resources tab
    -- page, or Layout & Order.
    if CS.resourcesEntrySelected then
        HideResourceBarPanelSurfaces(container)
        if CooldownCompanion.GetCurrentResourceBarConflict and CooldownCompanion:GetCurrentResourceBarConflict() then
            ShowLayoutOrderConflictScroll(container)
            return
        end

        local resourceBarsEnabled = AreResourceBarsConfigEnabled()

        -- Resources home while disabled: column 3 owns the enable step, so
        -- this column stays quiet until Resource Bars are enabled.
        if not resourceBarsEnabled then
            return
        end

        -- Persistent Layout & Order preview pane at the top of the column;
        -- every settings surface below anchors beneath it.
        do
            local previewHost = container.resourcesPreviewHost
            if not previewHost then
                previewHost = CreateFrame("Frame", nil, container)
                previewHost:SetClipsChildren(false)
                container.resourcesPreviewHost = previewHost
            end
            previewHost:ClearAllPoints()
            previewHost:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            previewHost:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
            local columnHeight = container:GetHeight() or 0
            previewHost:SetHeight(math.max(150, math.floor(columnHeight * 0.35)))
            previewHost:Show()
            ST._BuildLayoutOrderPanel(previewHost)
        end

        if resourceBarsEnabled then
            local selectedCustomBarIds = {}
            local selectedCustomBarEntries = {}
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
            for customBarId in pairs(CS.selectedCustomBars) do
                local entry = FindCustomBarById(settings, customBarId)
                selectedCustomBarIds[#selectedCustomBarIds + 1] = customBarId
                selectedCustomBarEntries[#selectedCustomBarEntries + 1] = entry
            end
            table.sort(selectedCustomBarIds)
            if #selectedCustomBarEntries >= 2 then
                ShowCustomBarMultiSelect(container, selectedCustomBarIds, selectedCustomBarEntries)
                return
            end
            if CS.selectedResourcePowerType then
                if ShowResourceSettingsPanel(container) then
                    return
                end
            end
            if CS.selectedCustomBarId then
                local selectedEntry = FindSelectedCustomBar()
                if not selectedEntry then
                    PruneConfigCustomBarSelection(CustomBarExists, true)
                else
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

                    if not container.customBarEntryTabGroup then
                        local tabGroup = AceGUI:Create("TabGroup")
                        tabGroup:SetLayout("Fill")
                        tabGroup.frame:SetParent(container)
                        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
                            SetConfigCustomBarSettingsTab(tab)
                            ClearInfoButtons(CS.customBarInfoButtons)
                            widget:ReleaseChildren()

                            local scroll = AceGUI:Create("ScrollFrame")
                            scroll:SetLayout("List")
                            widget:AddChild(scroll)
                            container.customBarsDetailScroll = scroll
                            container._customBarDetailScrollKey = GetCustomBarDetailScrollKey()
                            ST._BuildCustomAuraBarPanel(scroll, CS.selectedCustomBarId, CS.customBarSettingsTab)
                        end)
                        container.customBarEntryTabGroup = tabGroup
                    end

                    local tabGroup = container.customBarEntryTabGroup
                    HideWidgetFrame(container.customBarsMultiSelectScroll)
                    AnchorResourcesContentFrame(container, tabGroup.frame)
                    tabGroup:SetTabs(GetCustomBarEntryTabs(selectedEntry))
                    tabGroup.frame:Show()

                    local savedOffset, savedScrollvalue
                    local currentScrollKey = GetCustomBarDetailScrollKey()
                    if container.customBarsDetailScroll and container._customBarDetailScrollKey == currentScrollKey then
                        local state = container.customBarsDetailScroll.status or container.customBarsDetailScroll.localstatus
                        if state and state.offset and state.offset > 0 then
                            savedOffset = state.offset
                            savedScrollvalue = state.scrollvalue
                        end
                    end

                    tabGroup:SelectTab(CS.customBarSettingsTab or "appearance")

                    if savedOffset and container.customBarsDetailScroll then
                        local state = container.customBarsDetailScroll.status or container.customBarsDetailScroll.localstatus
                        if state then
                            state.offset = savedOffset
                            state.scrollvalue = savedScrollvalue
                        end
                    end
                    return
                end
            end
            HideWidgetFrame(container.customBarEntryTabGroup)
            HideWidgetFrame(container.customBarsDetailScroll)
            HideWidgetFrame(container.customBarsMultiSelectScroll)
            if not CS.selectedCustomBarId then
                -- Fall through to the tab page when the selected Custom Bar was removed.
            else
                return
            end
        end

        -- Resources home default page: the tabbed settings view
        ShowResourcesTabPage(container)
        return
    end
    if container.customBarsDetailScroll then
        container.customBarsDetailScroll.frame:Hide()
    end
    if container.customBarsMultiSelectScroll then
        container.customBarsMultiSelectScroll.frame:Hide()
    end
    if container.customBarEntryTabGroup then
        container.customBarEntryTabGroup.frame:Hide()
    end
    if container.resourceSettingsDetailScroll then
        container.resourceSettingsDetailScroll.frame:Hide()
    end
    if container.resourceSettingsTabGroup then
        container.resourceSettingsTabGroup.frame:Hide()
    end
    if container.resourcesTabGroup then
        container.resourcesTabGroup.frame:Hide()
    end
    if container.resourcesPreviewHost then
        container.resourcesPreviewHost:Hide()
    end
    if container.castBarHomeTabGroup then
        container.castBarHomeTabGroup.frame:Hide()
    end
    if container._castBarIntroPane then
        container._castBarIntroPane:Hide()
    end
    -- Hide layout order scroll if it exists
    if container.layoutOrderScroll then
        container.layoutOrderScroll.frame:Hide()
    end
    -- Hide custom aura scroll if it exists (now lives in col3)
    if container.customAuraScroll then
        container.customAuraScroll.frame:Hide()
    end

    -- Group-side settings surfaces (multi-select placeholders, folder,
    -- container, and single-panel tabs) live in GroupSettingsHost.lua;
    -- their widgets are still stored on this container.
    RefreshGroupSettingsHost(container)
end

local function RefreshProfileBar(bar)
    -- Release tracked AceGUI widgets
    for _, widget in ipairs(CS.profileBarAceWidgets) do
        widget:Release()
    end
    wipe(CS.profileBarAceWidgets)

    local db = CooldownCompanion.db
    local profiles = db:GetProfiles()
    local currentProfile = db:GetCurrentProfile()

    -- Build ordered profile list for AceGUI Dropdown
    local profileList = {}
    for _, name in ipairs(profiles) do
        profileList[name] = name
    end

    -- Profile dropdown (no label, compact)
    local profileDrop = AceGUI:Create("Dropdown")
    profileDrop:SetLabel("")
    profileDrop:SetList(profileList, profiles)
    profileDrop:SetValue(currentProfile)
    profileDrop:SetWidth(150)
    profileDrop:SetCallback("OnValueChanged", function(widget, event, val)
        db:SetProfile(val)
        ResetConfigSelection(true)
        CooldownCompanion:RefreshConfigPanel()
        CooldownCompanion:RefreshAllGroups()
    end)
    profileDrop.frame:SetParent(bar)
    profileDrop.frame:ClearAllPoints()
    profileDrop.frame:SetPoint("LEFT", bar, "LEFT", 0, 0)
    profileDrop.frame:Show()
    table.insert(CS.profileBarAceWidgets, profileDrop)

    -- Helper to create horizontally chained buttons
    local lastAnchor = profileDrop.frame
    local createdButtons = {}
    local PROFILE_BAR_BUTTON_MIN_WIDTH = 55
    local PROFILE_BAR_BUTTON_EXTRA_PADDING = 8
    local PROFILE_BAR_BUTTON_TRUNCATION_STEP = 4
    local PROFILE_BAR_BUTTON_TRUNCATION_MAX_WIDTH = 220
    local function AddBarButton(text, onClick)
        local btn = AceGUI:Create("Button")
        btn:SetText(text)
        btn:SetAutoWidth(true)
        btn:SetCallback("OnClick", onClick)
        btn.frame:SetParent(bar)
        btn.frame:ClearAllPoints()
        btn.frame:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
        btn:SetHeight(22)
        local measuredWidth = btn.frame:GetWidth() or 0
        local desiredWidth = math.max(PROFILE_BAR_BUTTON_MIN_WIDTH, measuredWidth + PROFILE_BAR_BUTTON_EXTRA_PADDING)
        btn:SetWidth(desiredWidth)
        btn.frame:Show()
        table.insert(CS.profileBarAceWidgets, btn)
        table.insert(createdButtons, btn)
        lastAnchor = btn.frame
        return btn
    end

    AddBarButton("New", function()
        ShowPopupAboveConfig("CDC_NEW_PROFILE")
    end)

    AddBarButton("Rename", function()
        ShowPopupAboveConfig("CDC_RENAME_PROFILE", currentProfile, { oldName = currentProfile })
    end)

    AddBarButton("Duplicate", function()
        ShowPopupAboveConfig("CDC_DUPLICATE_PROFILE", nil, { source = currentProfile })
    end)

    AddBarButton("Delete", function()
        local allProfiles = db:GetProfiles()
        local isOnly = #allProfiles <= 1
        if isOnly then
            ShowPopupAboveConfig("CDC_RESET_PROFILE", currentProfile, { profileName = currentProfile, isOnly = true })
        else
            ShowPopupAboveConfig("CDC_DELETE_PROFILE", currentProfile, { profileName = currentProfile })
        end
    end)

    AddBarButton("Export Backup", function()
        ShowPopupAboveConfig("CDC_EXPORT_PROFILE")
    end)

    -- Keep widening while text truncates so skin/font variations don't clip labels.
    for _, btn in ipairs(createdButtons) do
        local fontString = btn.frame.GetFontString and btn.frame:GetFontString() or nil
        if fontString and fontString.IsTruncated and fontString:IsTruncated() then
            local width = btn.frame:GetWidth() or PROFILE_BAR_BUTTON_MIN_WIDTH
            while width < PROFILE_BAR_BUTTON_TRUNCATION_MAX_WIDTH and fontString:IsTruncated() do
                width = math.min(PROFILE_BAR_BUTTON_TRUNCATION_MAX_WIDTH, width + PROFILE_BAR_BUTTON_TRUNCATION_STEP)
                btn:SetWidth(width)
            end
        end
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn4 = RefreshColumn4
ST._RefreshProfileBar = RefreshProfileBar
