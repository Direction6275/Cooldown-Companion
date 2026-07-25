--[[
    CooldownCompanion - Config/ResourcesWideColumn
    Workspace for the Resources home and the Cast Bar & Unit Frames
    home: the pinned Layout & Order preview (sharing the split divider and
    persisted split fraction from ButtonsWideColumn) above the editing
    surfaces: the resources tab page, per-resource
    settings, the Custom Bar detail tabs, the Custom Bar multi-select, and
    the Cast Bar tabs - plus the player/target frame anchoring panels.
    The Navigator keeps only the two destination rows; preview objects and
    the inactive-object chips below select the concrete bar/frame settings.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")
local RB = ST._RB

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

local function GetRenderedDestinationKeys(col3)
    local host = col3 and col3._resourcesPreviewHost
    if not (host and host:IsShown()) then
        return {}
    end
    if ST._GetLayoutPreviewRenderedSelectionKeys then
        return ST._GetLayoutPreviewRenderedSelectionKeys(host)
    end
    return {}
end

local function ExportAllCustomBars()
    if BlockCustomBarExportForResourceBarConflict and BlockCustomBarExportForResourceBarConflict() then
        return
    end
    local settings = CooldownCompanion:GetResourceBarSettings()
    local customBars = RB and RB.GetAllCustomBars and RB.GetAllCustomBars(settings)
        or CooldownCompanion:GetSpecCustomAuraBars()
    local payload = RB and RB.BuildCustomBarsExportPayload
        and RB.BuildCustomBarsExportPayload(settings, customBars)
    local exportString = payload and ST._EncodeExportData and ST._EncodeExportData(payload)
    if exportString then
        ST._ShowPopupAboveConfig("CDC_EXPORT_CUSTOM_BARS", nil, { exportString = exportString })
    else
        CooldownCompanion:Print("Export failed: Custom Bar data was unavailable.")
    end
end

local function EnsureResourcesAddBox(col3)
    local host = col3._resourcesAddBoxHost
    if not host then
        host = AceGUI:Create("SimpleGroup")
        host:SetLayout("Fill")
        host:SetHeight(28)
        host.noAutoHeight = true
        host.frame:SetParent(col3.content)
        host.frame._cdcEditingHeight = 28
        host.frame:SetScript("OnSizeChanged", function(_, width, height)
            host.content.width = width
            host.content.height = height
            host:DoLayout()
        end)
        col3._resourcesAddBoxHost = host
    end
    host:ReleaseChildren()
    if ST._BuildCustomBarWorkspaceAddBox then
        ST._BuildCustomBarWorkspaceAddBox(host)
    end
    host.frame:Show()
    if ST._SetWideEditingAddBox then
        ST._SetWideEditingAddBox(col3, host)
    end
end

local function BuildResourcesInactiveChips(col3, settings)
    if not ST._SetWideEditingChips then return end
    local rendered = GetRenderedDestinationKeys(col3)
    local items = {}
    local RBP = ST._RBP
    local powerNames = RB and RB.POWER_NAMES or {}

    for _, powerType in ipairs(RBP and RBP.GetConfigEditableResources
        and RBP.GetConfigEditableResources(settings, true) or {}) do
        local capturedPowerType = powerType
        local key = "resource:" .. tostring(powerType)
        if not rendered[key] then
            items[#items + 1] = {
                label = powerNames[powerType] or ("Power " .. tostring(powerType)),
                selected = tostring(CS.selectedResourcePowerType) == tostring(powerType),
                onClick = function()
                    ST._SelectConfigResource(capturedPowerType, { toggle = true })
                    CooldownCompanion:RefreshConfigPanel()
                end,
            }
        end
    end

    local customBars = RB and RB.GetAllCustomBars and RB.GetAllCustomBars(settings)
        or CooldownCompanion:GetSpecCustomAuraBars()
    for index, entry in ipairs(customBars or {}) do
        local customBarId = RB and RB.EnsureCustomBarId and RB.EnsureCustomBarId(settings, entry)
            or entry.customBarId
        local capturedCustomBarId = customBarId
        local key = customBarId and ("custom:" .. tostring(customBarId)) or nil
        if customBarId and not rendered[key] then
            local label = entry.label
                or (entry.spellID and C_Spell.GetSpellName(entry.spellID))
                or ("Custom Bar " .. tostring(index))
            items[#items + 1] = {
                label = label,
                selected = tostring(CS.selectedCustomBarId) == tostring(customBarId)
                    or (CS.selectedCustomBars and CS.selectedCustomBars[customBarId] == true),
                tooltip = "Left-click to edit. Ctrl+Left-click to multi-select. Right-click for actions.",
                onClick = function()
                    if IsControlKeyDown and IsControlKeyDown() then
                        if not CS.selectedCustomBarId then
                            ST._SelectConfigCustomBar(capturedCustomBarId)
                        end
                        ST._ToggleConfigCustomBarMultiSelect(capturedCustomBarId)
                    else
                        ST._SelectConfigCustomBar(capturedCustomBarId, { toggle = true })
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end,
                onRightClick = function()
                    ST._SelectConfigCustomBar(capturedCustomBarId)
                    CooldownCompanion:RefreshConfigPanel()
                    if ST._OpenConfigCustomBarMenu then
                        ST._OpenConfigCustomBarMenu(capturedCustomBarId)
                    end
                end,
            }
        end
    end

    ST._SetWideEditingChips(col3, "Not currently shown:", items)
end

local function PrepareResourcesEditingChrome(col3, settings)
    EnsureResourcesAddBox(col3)
    if ST._SetWideEditingHeaderActions then
        ST._SetWideEditingHeaderActions(col3, {
            {
                text = "Import",
                width = 58,
                onClick = function()
                    ST._OpenImportReviewWindow()
                end,
            },
            {
                text = "Export All",
                width = 72,
                onClick = ExportAllCustomBars,
            },
        })
    end
    BuildResourcesInactiveChips(col3, settings)
end

local function PrepareCastEditingChips(col3)
    if not ST._SetWideEditingChips then return end
    local rendered = GetRenderedDestinationKeys(col3)
    local definitions = {
        { key = "cast", item = "castbar", label = "Cast Bar" },
        { key = "frame:player", item = "player", label = "Player Frame" },
        { key = "frame:target", item = "target", label = "Target Frame" },
    }
    local items = {}
    for _, definition in ipairs(definitions) do
        if not rendered[definition.key] then
            local captured = definition
            items[#items + 1] = {
                label = captured.label,
                selected = CS.castFramesSelectedItem == captured.item,
                onClick = function()
                    if ST._SelectConfigCastFramesItem then
                        ST._SelectConfigCastFramesItem(captured.item)
                    else
                        CS.castFramesSelectedItem = captured.item
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end,
            }
        end
    end
    ST._SetWideEditingChips(col3, "Not currently shown:", items)
end

local function BuildCastIntroLinks(currentItem)
    local definitions = {
        { item = "castbar", label = "Cast Bar" },
        { item = "player", label = "Player Frame" },
        { item = "target", label = "Target Frame" },
    }
    local links = {}
    for _, definition in ipairs(definitions) do
        if definition.item ~= currentItem then
            local captured = definition
            links[#links + 1] = {
                label = captured.label,
                onClick = function()
                    if ST._SelectConfigCastFramesItem then
                        ST._SelectConfigCastFramesItem(captured.item)
                    else
                        CS.castFramesSelectedItem = captured.item
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end,
            }
        end
    end
    return links
end

-- Attached-bar tabs join the unified tab row beside the panel tabs, so they
-- carry the same accent tint the entry cluster does: `text` is what the tab
-- measures against and what the selected one shows, `accentText` is what
-- the rest wear while the row is shared. UnifiedTabRow drops the tint when
-- the strip owns the whole row (the Resources and Cast Bar homes).
local function AddTabAccent(tabs)
    for _, tab in ipairs(tabs) do
        tab.accentText = ST._GetClassColoredText(tab.text)
    end
    return tabs
end

-- Every tab strip in this file shows the same way: its tabs go into the
-- unified row unconditionally, content is built only when this strip owns
-- the settings surface, and the scroll position survives a rebuild that
-- lands on the same tab. Each strip's scroll widget and the key naming
-- what it was built for live on the strip itself, so no two surfaces can
-- clobber each other's reference.
local function GetStripScrollState(tabGroup)
    local scroll = tabGroup._cdcScroll
    return scroll and (scroll.status or scroll.localstatus) or nil
end

local function ShowStrip(col3, tabGroup, tabs, activeTab, scrollKey, stripOnly)
    ST._AnchorButtonsContentFrame(col3, tabGroup.frame)
    tabGroup.frame:Show()
    tabGroup:SetTabs(tabs)

    if stripOnly then
        -- Another strip owns the surface: these tabs stay in the row
        -- unselected and build nothing.
        ST._UnifiedRowApply()
        return
    end

    local savedOffset, savedScrollvalue
    if tabGroup._cdcScrollKey == scrollKey then
        local state = GetStripScrollState(tabGroup)
        if state and state.offset and state.offset > 0 then
            savedOffset = state.offset
            savedScrollvalue = state.scrollvalue
        end
    end

    tabGroup:SelectTab(activeTab)

    -- LayoutFinished has already scheduled FixScrollOnUpdate for next
    -- frame; it reads these values.
    if savedOffset then
        local state = GetStripScrollState(tabGroup)
        if state then
            state.offset = savedOffset
            state.scrollvalue = savedScrollvalue
        end
    end
end

local function GetCustomBarEntryTabs(entry)
    local tabs = {
        { value = "appearance", text = "Appearance" },
    }

    tabs[#tabs + 1] = { value = "soundalerts", text = "Sound Alerts" }
    tabs[#tabs + 1] = { value = "loadconditions", text = "Load Conditions" }
    return AddTabAccent(tabs)
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

-- Returns the plain label and its accent-tinted twin; the spec icon stays
-- outside the colour escape.
local function GetResourceSettingsSpecTabText(info, specID)
    local specName = (info and info.name) or tostring(specID)
    local icon = info and info.icon
    local prefix = ""
    if icon and icon ~= "" then
        prefix = string.format("|T%s:13:13:0:0|t ", tostring(icon))
    end
    return prefix .. specName, prefix .. ST._GetClassColoredText(specName)
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
        local text, accentText = GetResourceSettingsSpecTabText(info, specID)
        tabs[#tabs + 1] = {
            value = tostring(specID),
            text = text,
            accentText = accentText,
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
    HideWidgetFrame(col3._castBarHomeTabGroup)
    HideWidgetFrame(col3._castFramesSettingsScroll)
    HideWidgetFrame(col3._resourcesAddBoxHost)
    if ST._ClearWideEditingExtras then
        ST._ClearWideEditingExtras(col3)
    end
    if col3._resourcesIntroPane then col3._resourcesIntroPane:Hide() end
    if col3._castBarIntroPane then col3._castBarIntroPane:Hide() end
    if col3._unitFramesIntroPane then col3._unitFramesIntroPane:Hide() end
    local host = col3._resourcesPreviewHost
    if host then
        if col3.buttonsSplitDivider and col3._cdcActiveWideHost == host then
            if ST._HideWideEditingChrome then
                ST._HideWideEditingChrome(col3)
            else
                col3.buttonsSplitDivider:CancelDrag()
                col3.buttonsSplitDivider:Hide()
            end
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

-- Single build entry for this workspace's pinned preview. The preview
-- command center owns the host's bottom reserve, so it has to settle
-- before the renderer measures itself; routing every rebuild through here
-- keeps the two in step without a second hook, and refreshes the bar on
-- divider drags, split reapplies and workspace switches alike.
local function BuildResourcesLayoutPreview(host)
    if ST._UpdateResourcesPreviewCommandCenter then
        ST._UpdateResourcesPreviewCommandCenter(host)
    end
    ST._BuildLayoutOrderPanel(host)
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
                BuildResourcesLayoutPreview(hostFrame)
            end
        end)
    end
    if ST._ComputeWidePreviewHostHeight then
        host:SetHeight(ST._ComputeWidePreviewHostHeight(col3))
    end
    host:Show()
    BuildResourcesLayoutPreview(host)
end

-- Targeted preview rebuild (value changes that only affect the layout
-- preview), without a full config refresh.
local function RefreshResourcesLayoutPreview()
    if CS.resourcesEntrySelected or CS.castFramesEntrySelected then
        local col3 = CS.configFrame and CS.configFrame.col3
        local host = col3 and col3._resourcesPreviewHost
        if host and host:IsShown() and ST._BuildLayoutOrderPanel then
            BuildResourcesLayoutPreview(host)
        end
        return
    end
    -- Buttons view: the lanes live inside the unified anchor preview on
    -- the buttons preview host; the mirror refresh self-gates.
    if ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
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
            -- Selecting a bar tab hands the settings surface to the bar;
            -- any panel tabs sharing the row just go unselected.
            ST._UnifiedRowSetScope("detail")
            SetConfigResourceSettingsSpecID(tab)
            widget:ReleaseChildren()

            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            widget._cdcScroll = scroll
            widget._cdcScrollKey = GetResourceSettingsDetailScrollKey()
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
        ST._UnifiedRowInstallStrip(tabGroup, "detail")
        col3._resourceSettingsTabGroup = tabGroup
    end

    -- A primary tab is showing its own content: the bar keeps its place in
    -- the row and stays selected, it just does not own the surface.
    ShowStrip(col3, col3._resourceSettingsTabGroup, tabs,
        tostring(CS.resourceSettingsSpecID), GetResourceSettingsDetailScrollKey(),
        ST._UnifiedRowPrimaryOwnsSurface())

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
            -- Selecting a bar tab hands the settings surface to the bar;
            -- any panel tabs sharing the row just go unselected.
            ST._UnifiedRowSetScope("detail")
            SetConfigCustomBarSettingsTab(tab)
            ClearInfoButtons(CS.customBarInfoButtons)
            widget:ReleaseChildren()

            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            widget._cdcScroll = scroll
            widget._cdcScrollKey = GetCustomBarDetailScrollKey()
            ST._BuildCustomAuraBarPanel(scroll, CS.selectedCustomBarId, CS.customBarSettingsTab)
        end)
        ST._UnifiedRowInstallStrip(tabGroup, "detail")
        col3._customBarEntryTabGroup = tabGroup
    end

    -- A primary tab is showing its own content: the bar keeps its place in
    -- the row and stays selected, it just does not own the surface.
    ShowStrip(col3, col3._customBarEntryTabGroup, GetCustomBarEntryTabs(selectedEntry),
        CS.customBarSettingsTab or "appearance", GetCustomBarDetailScrollKey(),
        ST._UnifiedRowPrimaryOwnsSurface())
end

-- Default page for the Resources home: the tabbed shared settings view.
-- Re-hosts the existing bars-mode builders unmodified: General = anchoring,
-- Appearance = bar text styling, Layout = positioning, Health (when the
-- health resource is enabled). The Layout & Order preview lives in the
-- pinned host above this page, not in a tab.
local function ShowResourcesTabPage(col3, stripOnly)
    if not col3._resourcesTabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")
        tabGroup.frame:SetParent(col3.content)
        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            -- These are the module-scope tabs of the Resources home, the
            -- left cluster of its unified row; selecting one hands them the
            -- settings surface without dropping the selected bar.
            ST._UnifiedRowSetScope("primary")
            CS.resourcesSettingsTab = tab
            -- Clean up info buttons from the previous tab before recycling widgets
            ClearInfoButtons(CS.tabInfoButtons)
            widget:ReleaseChildren()
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            widget._cdcScroll = scroll
            widget._cdcScrollKey = "resources:" .. tab
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
        ST._UnifiedRowInstallStrip(tabGroup, "primary")
        col3._resourcesTabGroup = tabGroup
    end

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

    local tab = CS.resourcesSettingsTab
    local valid = { general = true, appearance = true, layout = true }
    if healthEnabled then valid.health = true end
    if not tab or not valid[tab] then tab = "general" end
    CS.resourcesSettingsTab = tab

    ShowStrip(col3, col3._resourcesTabGroup, tabs, tab, "resources:" .. tab, stripOnly)
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
            return RBP.IsResourceEditableInColumn4(powerType, settings, true)
        end)
    end

    UpdateResourcesPreviewHost(col3)
    PrepareResourcesEditingChrome(col3, settings)

    local selectedCustomBarIds = {}
    local selectedCustomBarEntries = {}
    for customBarId in pairs(CS.selectedCustomBars) do
        local entry = FindCustomBarById(settings, customBarId)
        selectedCustomBarIds[#selectedCustomBarIds + 1] = customBarId
        selectedCustomBarEntries[#selectedCustomBarEntries + 1] = entry
    end
    table.sort(selectedCustomBarIds)

    if #selectedCustomBarEntries >= 2 then
        -- Batch edits replace the surface outright, as panel multi-select
        -- does in the buttons workspace.
        ShowCustomBarMultiSelect(col3, selectedCustomBarIds, selectedCustomBarEntries)
    else
        local selectedEntry = CS.selectedCustomBarId and FindSelectedCustomBar()
        local wantsBarDetail = CS.selectedResourcePowerType ~= nil or selectedEntry ~= nil

        -- The module tabs are the left cluster of this home's unified row:
        -- they stay put while a bar is selected, and the bar's own tabs are
        -- appended beside them. Built first, since the bar strip is offset
        -- by their measured width - which is also why the scope is read
        -- directly here: every strip is still hidden at this point, so
        -- PrimaryOwnsSurface would report false whatever the scope is.
        ShowResourcesTabPage(col3, wantsBarDetail and ST._UnifiedRowGetScope() ~= "primary")

        local barShown = false
        if CS.selectedResourcePowerType then
            barShown = ShowResourceSettingsPanel(col3) == true
        end
        if not barShown and selectedEntry then
            ShowCustomBarDetail(col3, selectedEntry)
            barShown = true
        end
        if not barShown then
            if CS.selectedCustomBarId then
                PruneConfigCustomBarSelection(CustomBarExists, true)
            end
            if wantsBarDetail then
                -- The bar surface did not materialise after all (a resource
                -- with no applicable specs); the module tabs take the row
                -- back rather than leaving it empty.
                ShowResourcesTabPage(col3)
            end
        end
    end

    -- Final height pass: the settings surface just anchored below the
    -- divider, so re-clamp the persisted split against current overhead.
    if ST._ReapplyPanelPreviewSplit then
        ST._ReapplyPanelPreviewSplit()
    end
end

------------------------------------------------------------------------
-- Cast Bar & Unit Frames home
------------------------------------------------------------------------

-- Cast Bar settings tabs below the pinned preview.
local function ShowCastBarSettings(col3)
    if not col3._castBarHomeTabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")
        tabGroup.frame:SetParent(col3.content)
        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            -- Selecting a bar tab hands the settings surface to the bar;
            -- any panel tabs sharing the row just go unselected.
            ST._UnifiedRowSetScope("detail")
            CS.castBarHomeTab = tab
            -- Clean up info buttons from the previous tab before recycling widgets
            ClearInfoButtons(CS.tabInfoButtons)
            widget:ReleaseChildren()
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            widget._cdcScroll = scroll
            widget._cdcScrollKey = "castbar:" .. tab
            if tab == "general" then
                ST._BuildCastBarAnchoringPanel(scroll)
            elseif tab == "appearance" then
                ST._BuildCastBarStylingPanel(scroll)
            elseif tab == "layout" then
                ST._BuildCastBarPositioningPanel(scroll)
            end
        end)
        ST._UnifiedRowInstallStrip(tabGroup, "detail")
        col3._castBarHomeTabGroup = tabGroup
    end

    local tab = CS.castBarHomeTab
    if tab ~= "general" and tab ~= "appearance" and tab ~= "layout" then
        tab = "general"
    end
    CS.castBarHomeTab = tab

    -- A primary tab is showing its own content: the cast bar keeps its
    -- place in the row and stays selected, it just does not own the
    -- surface.
    ShowStrip(col3, col3._castBarHomeTabGroup, AddTabAccent({
        { value = "general", text = "General" },
        { value = "appearance", text = "Appearance" },
        { value = "layout", text = "Layout" },
    }), tab, "castbar:" .. tab, ST._UnifiedRowPrimaryOwnsSurface())
end

-- Player or target frame anchoring panel, below the pinned preview.
local function ShowUnitFrameSettings(col3, item)
    if not col3._castFramesSettingsScroll then
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(col3.content)
        col3._castFramesSettingsScroll = scroll
    end

    local scroll = col3._castFramesSettingsScroll
    ST._AnchorButtonsContentFrame(col3, scroll.frame)

    -- Preserve scroll position across value-change refreshes on the same row
    local savedOffset, savedScrollvalue
    local currentScrollKey = "unitframe:" .. tostring(item)
    if col3._castFramesSettingsScrollKey == currentScrollKey then
        local state = scroll.status or scroll.localstatus
        if state and state.offset and state.offset > 0 then
            savedOffset = state.offset
            savedScrollvalue = state.scrollvalue
        end
    end

    scroll:ReleaseChildren()
    scroll.frame:Show()
    if item == "player" then
        ST._BuildFrameAnchoringPlayerPanel(scroll)
    else
        ST._BuildFrameAnchoringTargetPanel(scroll)
    end
    col3._castFramesSettingsScrollKey = currentScrollKey

    if savedOffset then
        local state = scroll.status or scroll.localstatus
        if state then
            state.offset = savedOffset
            state.scrollvalue = savedScrollvalue
        end
    end
end

-- Refresh for the Cast Bar & Unit Frames home: preview or inactive-chip
-- selection decides what shows beneath the pinned preview. Disabled modules
-- keep their intro pane across the whole wide column instead.
local function RefreshCastFramesWideColumn(col3)
    -- Everything restarts hidden; the active surface re-shows below.
    HideResourcesWideSurfaces(col3)

    local item = CS.castFramesSelectedItem
    if item ~= "castbar" and item ~= "player" and item ~= "target" then
        item = "castbar"
        CS.castFramesSelectedItem = item
    end

    local conflict = CooldownCompanion.GetCurrentResourceBarConflict
        and CooldownCompanion:GetCurrentResourceBarConflict()
    if conflict then
        ShowResourcesConflictScroll(col3)
        return
    end

    if item == "castbar" then
        local settings = CooldownCompanion:GetCastBarSettings()
        if not (settings and settings.enabled) then
            ST._ShowColumnIntroPane(col3, "_castBarIntroPane", {
                title = "Cast Bar",
                body = "Skin the Blizzard cast bar and anchor it to a panel, or position it anywhere on screen.",
                buttonText = "Enable Cast Bar",
                links = BuildCastIntroLinks("castbar"),
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
            return
        end
        UpdateResourcesPreviewHost(col3)
        PrepareCastEditingChips(col3)
        ShowCastBarSettings(col3)
    else
        local fa = CooldownCompanion:GetFrameAnchoringSettings()
        if not (fa and fa.enabled) then
            ST._ShowColumnIntroPane(col3, "_unitFramesIntroPane", {
                title = "Unit Frames",
                body = "Anchor your player and target unit frames to your panels.",
                buttonText = "Enable Frame Anchoring",
                links = BuildCastIntroLinks(item),
                onEnable = function()
                    local settings = CooldownCompanion:GetFrameAnchoringSettings()
                    if not settings then
                        return
                    end
                    settings.enabled = true
                    CooldownCompanion:EvaluateFrameAnchoring()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
            return
        end
        UpdateResourcesPreviewHost(col3)
        PrepareCastEditingChips(col3)
        ShowUnitFrameSettings(col3, item)
    end

    -- Final height pass (see RefreshResourcesWideColumn).
    if ST._ReapplyPanelPreviewSplit then
        ST._ReapplyPanelPreviewSplit()
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshResourcesWideColumn = RefreshResourcesWideColumn
ST._RefreshCastFramesWideColumn = RefreshCastFramesWideColumn
ST._HideResourcesWideSurfaces = HideResourcesWideSurfaces
ST._RefreshResourcesLayoutPreview = RefreshResourcesLayoutPreview
-- The unified anchor preview (buttons view) re-hosts these settings
-- surfaces below its divider when an attached bar is selected there.
ST._ShowResourceSettingsSurface = ShowResourceSettingsPanel
ST._ShowCustomBarDetailSurface = ShowCustomBarDetail
ST._ShowCastBarSettingsSurface = ShowCastBarSettings
ST._FindSelectedConfigCustomBar = FindSelectedCustomBar
