local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local FALLBACK_PANEL_WIDTH = 330
local MIN_PANEL_HEIGHT = 105
local MAX_PANEL_HEIGHT = 610
local FRAME_CHROME_HEIGHT = 57
local CONTENT_HEIGHT_PADDING = 6

local advancedWindow = nil
local activeDescriptor = nil
local queuedOpen = nil
local refreshingAdvancedPanel = false
CS.advancedSettingsInfoButtons = CS.advancedSettingsInfoButtons or {}

local function BoolValue(value)
    return value == true
end

local function SortedKeyString(selection)
    if type(selection) ~= "table" then
        return ""
    end

    local keys = {}
    for key, selected in pairs(selection) do
        if selected then
            keys[#keys + 1] = tostring(key)
        end
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

local function BuildContext(extra)
    local group = CS.selectedGroup
        and CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups
        and CooldownCompanion.db.profile.groups[CS.selectedGroup]

    local context = {
        selectedFolder = CS.selectedFolder,
        selectedContainer = CS.selectedContainer,
        selectedGroup = CS.selectedGroup,
        selectedGroupDisplayMode = group and (group.displayMode or "icons") or "",
        selectedGroupTriggerDisplayType = group and group.displayMode == "trigger" and CooldownCompanion.GetTriggerPanelDisplayType and CooldownCompanion:GetTriggerPanelDisplayType(group, false) or "",
        selectedButton = CS.selectedButton,
        selectedButtons = SortedKeyString(CS.selectedButtons),
        selectedPanels = SortedKeyString(CS.selectedPanels),
        selectedGroups = SortedKeyString(CS.selectedGroups),
        selectedCustomBars = SortedKeyString(CS.selectedCustomBars),
        currentSpecId = CooldownCompanion._currentSpecId,
        currentHeroSpecId = CooldownCompanion._currentHeroSpecId,
        selectedTab = CS.selectedTab,
        buttonSettingsTab = CS.buttonSettingsTab,
        panelSettingsTab = CS.panelSettingsTab,
        resourceBarPanelActive = BoolValue(CS.resourceBarPanelActive),
        barPanelTab = CS.barPanelTab,
        resourceStylingTab = CS.resourceStylingTab,
        castBarStylingTab = CS.castBarStylingTab,
        customBarSettingsTab = CS.customBarSettingsTab,
        selectedCustomBarId = CS.selectedCustomBarId,
        selectedResourcePowerType = CS.selectedResourcePowerType,
        resourceSettingsSpecID = CS.resourceSettingsSpecID,
        browseMode = BoolValue(CS.browseMode),
        browseCharKey = CS.browseCharKey,
        autoAddFlowActive = BoolValue(CS.autoAddFlowActive),
        talentPickerMode = BoolValue(CS.talentPickerMode),
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            context[key] = value
        end
    end

    return context
end

local function ContextMatches(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end

    for key, value in pairs(left) do
        if right[key] ~= value then
            return false
        end
    end
    for key, value in pairs(right) do
        if left[key] ~= value then
            return false
        end
    end
    return true
end

local function NormalizeDescriptor(opts)
    if type(opts) ~= "table" then
        return nil
    end
    if type(opts.settingKey) ~= "string" or opts.settingKey == "" then
        return nil
    end
    if type(opts.build) ~= "function" then
        return nil
    end

    return {
        settingKey = opts.settingKey,
        title = opts.title or "Advanced Settings",
        build = opts.build,
        isAvailable = type(opts.isAvailable) == "function" and opts.isAvailable or nil,
        contextExtra = opts.context,
        context = BuildContext(opts.context),
        deferBuild = opts.deferBuild == true,
    }
end

local function CurrentContextMatches(descriptor)
    if not descriptor then
        return false
    end
    if descriptor.isAvailable and not descriptor.isAvailable() then
        return false
    end
    return ContextMatches(descriptor.context, BuildContext(descriptor.contextExtra))
end

local function ClearAdvancedSettingsInfoButtons()
    local buttons = CS.advancedSettingsInfoButtons
    if type(buttons) ~= "table" then
        return
    end

    for _, btn in ipairs(buttons) do
        if btn then
            btn:ClearAllPoints()
            btn:Hide()
            btn:SetParent(nil)
        end
    end
    wipe(buttons)
end

local function AnchorWindowToConfig()
    local configFrame = CS.configFrame
    if advancedWindow and configFrame and configFrame.frame and configFrame.frame:IsShown() then
        advancedWindow.frame:ClearAllPoints()
        advancedWindow.frame:SetPoint("TOPLEFT", configFrame.frame, "TOPRIGHT", 4, 0)
    end
end

local function GetAdvancedPanelWidth()
    local configFrame = CS.configFrame
    local narrowestWidth

    for _, columnKey in ipairs({ "col1", "col2", "col3", "col4" }) do
        local column = configFrame and configFrame[columnKey]
        local frame = column and column.frame
        local visible = frame and (frame:IsVisible() or frame:IsShown())
        if visible then
            local width = frame:GetWidth()
            if width and width > 0 then
                narrowestWidth = narrowestWidth and math.min(narrowestWidth, width) or width
            end
        end
    end

    return math.floor((narrowestWidth or FALLBACK_PANEL_WIDTH) + 0.5)
end

local function GetAdvancedPanelHeight(contentHeight)
    local desiredHeight = (contentHeight or 0) + FRAME_CHROME_HEIGHT + CONTENT_HEIGHT_PADDING
    return math.min(MAX_PANEL_HEIGHT, math.max(MIN_PANEL_HEIGHT, math.floor(desiredHeight + 0.5)))
end

local function ResizeAdvancedPanelToContent(scroll)
    if not advancedWindow then
        return
    end

    advancedWindow:SetWidth(GetAdvancedPanelWidth())

    local contentHeight = scroll and scroll.content and scroll.content:GetHeight()
    advancedWindow:SetHeight(GetAdvancedPanelHeight(contentHeight))

    if advancedWindow.DoLayout then
        advancedWindow:DoLayout()
    end
    AnchorWindowToConfig()
end

local function BuildWindowContents()
    if not (advancedWindow and activeDescriptor) then
        return
    end
    if refreshingAdvancedPanel then
        return
    end

    refreshingAdvancedPanel = true
    CS.advancedSettingsPanelRefreshing = true
    advancedWindow:SetTitle(activeDescriptor.title or "Advanced Settings")
    advancedWindow:SetWidth(GetAdvancedPanelWidth())
    ClearAdvancedSettingsInfoButtons()
    advancedWindow:ReleaseChildren()
    if advancedWindow.PauseLayout then
        advancedWindow:PauseLayout()
    end

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll._isAdvancedSettingsPanel = true
    CS.advancedSettingsPreviewToggleButtons = nil
    if scroll.PauseLayout then
        scroll:PauseLayout()
    end
    advancedWindow:AddChild(scroll)
    activeDescriptor.build(scroll, activeDescriptor)

    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, buttons in ipairs({ CS.tabInfoButtons, CS.customBarInfoButtons, CS.buttonSettingsInfoButtons, CS.advancedSettingsInfoButtons }) do
            if type(buttons) == "table" then
                for _, btn in ipairs(buttons) do
                    if btn and not btn._isAdvancedToggle then
                        btn:Hide()
                    end
                end
            end
        end
    end

    if scroll.ResumeLayout then
        scroll:ResumeLayout()
    end
    if scroll.DoLayout then
        scroll:DoLayout()
    end
    if advancedWindow.ResumeLayout then
        advancedWindow:ResumeLayout()
    end
    if advancedWindow.DoLayout then
        advancedWindow:DoLayout()
    end

    ResizeAdvancedPanelToContent(scroll)

    CS.advancedSettingsPanelRefreshing = false
    refreshingAdvancedPanel = false
end

local function CleanupWindow(widget)
    if CS.UnregisterConfigDragAlphaFrame then
        CS.UnregisterConfigDragAlphaFrame(widget.frame)
    end

    ClearAdvancedSettingsInfoButtons()
    CS.advancedSettingsPreviewToggleButtons = nil
    widget:ReleaseChildren()
    AceGUI:Release(widget)
    advancedWindow = nil
    CS.advancedSettingsPanelWindow = nil
    activeDescriptor = nil
    if CS.SetActiveAdvancedSettingsToggleButton then
        CS.SetActiveAdvancedSettingsToggleButton(nil)
    end

end

local function CloseAdvancedSettingsPanel()
    queuedOpen = nil
    if advancedWindow then
        advancedWindow:Hide()
        return true
    else
        local hadActiveDescriptor = activeDescriptor ~= nil
        activeDescriptor = nil
        if hadActiveDescriptor and CS.SetActiveAdvancedSettingsToggleButton then
            CS.SetActiveAdvancedSettingsToggleButton(nil)
        end
        return hadActiveDescriptor
    end
end

local function OpenAdvancedSettingsPanel(opts)
    local descriptor = NormalizeDescriptor(opts)
    if not descriptor then
        return false
    end

    if activeDescriptor
        and activeDescriptor.settingKey == descriptor.settingKey
        and ContextMatches(activeDescriptor.context, descriptor.context)
    then
        CloseAdvancedSettingsPanel({ skipRefresh = true })
        return false
    end

    if CS.CancelPickAuraTexture then
        CS.CancelPickAuraTexture()
    end
    if CS.CloseProfileWideFontWindow then
        CS.CloseProfileWideFontWindow()
    end
    if CS.CloseProfileWideBarTextureWindow then
        CS.CloseProfileWideBarTextureWindow()
    end
    if ST._CloseFormatEditor then
        ST._CloseFormatEditor()
    end

    activeDescriptor = descriptor

    if not advancedWindow then
        local window = AceGUI:Create("Window")
        window:SetTitle(descriptor.title or "Advanced Settings")
        window:SetWidth(GetAdvancedPanelWidth())
        window:SetHeight(MAX_PANEL_HEIGHT)
        window:SetLayout("Fill")
        window:EnableResize(false)
        window:SetCallback("OnClose", CleanupWindow)
        advancedWindow = window
        CS.advancedSettingsPanelWindow = window
        if CS.RegisterConfigDragAlphaFrame then
            CS.RegisterConfigDragAlphaFrame(window.frame)
        end
    else
        advancedWindow:Show()
        advancedWindow.frame:Raise()
    end

    AnchorWindowToConfig()
    if not descriptor.deferBuild and not CS.configRefreshInProgress then
        BuildWindowContents()
    end
    return true
end

local function RebindAdvancedSettingsPanel(opts)
    if not activeDescriptor then
        return false
    end

    local descriptor = NormalizeDescriptor(opts)
    if not descriptor then
        return false
    end

    if activeDescriptor.settingKey == descriptor.settingKey
        and ContextMatches(activeDescriptor.context, descriptor.context)
    then
        activeDescriptor = descriptor
        return true
    end

    return false
end

local function QueueAdvancedSettingsPanelOpen(settingKey, extraContext)
    if type(settingKey) ~= "string" or settingKey == "" then
        return
    end
    queuedOpen = {
        settingKey = settingKey,
        context = BuildContext(extraContext),
    }
end

local function ConsumeQueuedAdvancedSettingsPanelOpen(opts)
    if not queuedOpen then
        return false
    end

    if not ContextMatches(queuedOpen.context, BuildContext()) then
        queuedOpen = nil
        return false
    end

    local descriptor = NormalizeDescriptor(opts)
    if not descriptor then
        return false
    end

    if queuedOpen.settingKey ~= descriptor.settingKey
        or not ContextMatches(queuedOpen.context, descriptor.context)
    then
        return false
    end

    queuedOpen = nil
    return OpenAdvancedSettingsPanel(opts)
end

local function RefreshAdvancedSettingsPanel()
    if not activeDescriptor then
        return
    end

    if not CurrentContextMatches(activeDescriptor) then
        CloseAdvancedSettingsPanel({ skipRefresh = true })
        return
    end

    if advancedWindow then
        AnchorWindowToConfig()
        BuildWindowContents()
    end
end

local function IsAdvancedSettingsPanelOpen(settingKey, extraContext)
    if not (activeDescriptor and activeDescriptor.settingKey == settingKey) then
        return false
    end
    return ContextMatches(activeDescriptor.context, BuildContext(extraContext))
end

CS.OpenAdvancedSettingsPanel = OpenAdvancedSettingsPanel
CS.CloseAdvancedSettingsPanel = CloseAdvancedSettingsPanel
CS.RefreshAdvancedSettingsPanel = RefreshAdvancedSettingsPanel
CS.RebindAdvancedSettingsPanel = RebindAdvancedSettingsPanel
CS.QueueAdvancedSettingsPanelOpen = QueueAdvancedSettingsPanelOpen
CS.ConsumeQueuedAdvancedSettingsPanelOpen = ConsumeQueuedAdvancedSettingsPanelOpen
CS.IsAdvancedSettingsPanelOpen = IsAdvancedSettingsPanelOpen
