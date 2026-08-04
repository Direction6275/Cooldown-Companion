local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local FALLBACK_PANEL_WIDTH = 330
local MIN_PANEL_HEIGHT = 105
local MAX_PANEL_HEIGHT = 610
local FRAME_CHROME_HEIGHT = 57
local CONTENT_HEIGHT_PADDING = 6
-- Vertical gap between stacked panels (see openPanels).
local PANEL_STACK_GAP = 6

-- Every advanced panel on screen, in the order it was opened.
--
-- Normally exactly one: the settings-side gears are singleton by ruling, and
-- OpenAdvancedSettingsPanel below still replaces whatever was up. The list
-- exists for the preview command center's gear, which opens EVERY advanced
-- panel the preview it names is driven by (owner ruling 2026-07-26) - for a
-- cooldown in icons mode that is the text panel and the swipe panel at once.
-- Those two gears live on two different tabs, so only one of them ever builds
-- and no single gear could open both.
--
-- Each entry is { window = <AceGUI Window>, descriptor = <normalized opts>,
-- infoButtons = <the (?) buttons that panel's build created> }.
local openPanels = {}
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
        barsEntrySelected = BoolValue(CS.barsEntrySelected),
        castFramesSelectedItem = CS.castFramesSelectedItem,
        unifiedBarKind = CS.unifiedBarKind,
        resourcesSettingsTab = CS.resourcesSettingsTab,
        castBarHomeTab = CS.castBarHomeTab,
        customBarSettingsTab = CS.customBarSettingsTab,
        selectedCustomBarId = CS.selectedCustomBarId,
        selectedResourcePowerType = CS.selectedResourcePowerType,
        resourceSettingsSpecID = CS.resourceSettingsSpecID,
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

local function FindPanelIndexByDescriptor(descriptor)
    for index, panel in ipairs(openPanels) do
        if panel.descriptor.settingKey == descriptor.settingKey
            and ContextMatches(panel.descriptor.context, descriptor.context)
        then
            return index
        end
    end
    return nil
end

local function FindPanelIndexByWindow(widget)
    for index, panel in ipairs(openPanels) do
        if panel.window == widget then
            return index
        end
    end
    return nil
end

-- Per panel, not shared: rebuilding one panel must not unparent the (?)
-- buttons a second panel is still showing.
local function ClearInfoButtons(buttons)
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

-- The first panel hangs off the config frame; every later one stacks beneath
-- the one before it, so two panels read as one column rather than a pile.
-- The side comes from the shared config side-placement rule (Panel.lua), and
-- the whole column shifts up when it would run off the bottom of the screen.
local function AnchorPanelsToConfig()
    local configFrame = CS.configFrame
    if not (configFrame and configFrame.frame and configFrame.frame:IsShown()) then
        return
    end
    local first = openPanels[1] and openPanels[1].window.frame
    if not first then
        return
    end

    local widest, totalHeight = 0, 0
    for index, panel in ipairs(openPanels) do
        local frame = panel.window.frame
        widest = math.max(widest, frame:GetWidth() or 0)
        totalHeight = totalHeight + (frame:GetHeight() or 0)
        if index > 1 then
            totalHeight = totalHeight + PANEL_STACK_GAP
        end
    end

    local side, xOff = "right", 4
    if ST._ComputeConfigSidePlacement then
        side, xOff = ST._ComputeConfigSidePlacement(first, widest)
    end

    -- Raise the column just enough to keep its bottom on-screen, without
    -- pushing its top past the top edge. Physical coordinates, offset in the
    -- first panel's scale (it carries the anchor).
    local cf = configFrame.frame
    local yOff = 0
    local firstScale = first:GetEffectiveScale()
    local cfTop = cf:GetTop()
    if cfTop and firstScale and firstScale > 0 then
        local cfTopPx = cfTop * cf:GetEffectiveScale()
        local overflowPx = totalHeight * firstScale - cfTopPx
        if overflowPx > 0 then
            local maxRaisePx = UIParent:GetTop() * UIParent:GetEffectiveScale() - cfTopPx
            yOff = math.min(overflowPx, math.max(maxRaisePx, 0)) / firstScale
        end
    end

    local previousFrame
    for _, panel in ipairs(openPanels) do
        local frame = panel.window.frame
        frame:ClearAllPoints()
        if previousFrame then
            frame:SetPoint("TOPLEFT", previousFrame, "BOTTOMLEFT", 0, -PANEL_STACK_GAP)
        elseif side == "left" then
            frame:SetPoint("TOPRIGHT", cf, "TOPLEFT", xOff, yOff)
        else
            frame:SetPoint("TOPLEFT", cf, "TOPRIGHT", xOff, yOff)
        end
        previousFrame = frame
    end
end
ST._ReanchorAdvancedSettingsPanels = AnchorPanelsToConfig

-- The handle the rest of the config reads: the preview command center tints
-- its gear gold while a window is up, and nothing else repaints that bar.
local function SyncPrimaryWindowHandle()
    CS.advancedSettingsPanelWindow = openPanels[1] and openPanels[1].window or nil
end

local function GetAdvancedPanelWidth()
    local configFrame = CS.configFrame
    local narrowestWidth

    for _, columnKey in ipairs({ "col1", "col3" }) do
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

local function ResizePanelToContent(panel, scroll)
    if not panel then
        return
    end

    panel.window:SetWidth(GetAdvancedPanelWidth())

    local contentHeight = scroll and scroll.content and scroll.content:GetHeight()
    panel.window:SetHeight(GetAdvancedPanelHeight(contentHeight))

    if panel.window.DoLayout then
        panel.window:DoLayout()
    end
    -- Every panel below this one hangs off its bottom edge, so a height
    -- change moves them.
    AnchorPanelsToConfig()
end

local function BuildPanelContents(panel)
    if not panel then
        return
    end
    if refreshingAdvancedPanel then
        return
    end

    local window = panel.window
    local descriptor = panel.descriptor

    refreshingAdvancedPanel = true
    CS.advancedSettingsPanelRefreshing = true
    -- CreateInfoButton (Helpers.lua) files (?) buttons under this handle
    -- while a panel is building, so point it at the panel being built.
    CS.advancedSettingsInfoButtons = panel.infoButtons
    window:SetTitle(descriptor.title or "Advanced Settings")
    window:SetWidth(GetAdvancedPanelWidth())
    ClearInfoButtons(panel.infoButtons)
    window:ReleaseChildren()
    if window.PauseLayout then
        window:PauseLayout()
    end

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll._isAdvancedSettingsPanel = true
    if scroll.PauseLayout then
        scroll:PauseLayout()
    end
    window:AddChild(scroll)
    descriptor.build(scroll, descriptor)

    if scroll.ResumeLayout then
        scroll:ResumeLayout()
    end
    if scroll.DoLayout then
        scroll:DoLayout()
    end
    if window.ResumeLayout then
        window:ResumeLayout()
    end
    if window.DoLayout then
        window:DoLayout()
    end

    ResizePanelToContent(panel, scroll)

    CS.advancedSettingsPanelRefreshing = false
    refreshingAdvancedPanel = false
end

local function CleanupWindow(widget)
    -- Dropped from the list first, so the re-entrant OnClose that
    -- AceGUI:Release can fire finds nothing left to clean up.
    local index = FindPanelIndexByWindow(widget)
    local panel = index and table.remove(openPanels, index) or nil

    if CS.UnregisterConfigDragAlphaFrame then
        CS.UnregisterConfigDragAlphaFrame(widget.frame)
    end

    ClearInfoButtons(panel and panel.infoButtons)
    widget:ReleaseChildren()
    AceGUI:Release(widget)
    SyncPrimaryWindowHandle()

    -- Only this panel's own gear loses its gold: with a second panel still up
    -- its gear is still pointing at a window that is still there.
    local activeButton = CS.activeAdvancedSettingsToggleButton
    if activeButton
        and panel
        and activeButton._advancedSettingKey == panel.descriptor.settingKey
        and CS.SetActiveAdvancedSettingsToggleButton
    then
        CS.SetActiveAdvancedSettingsToggleButton(nil)
    end

    AnchorPanelsToConfig()

    -- The preview command center's gear is gold while a window is up, and
    -- closing one does not rebuild that bar.
    if ST._RefreshPreviewCommandCenterGear then
        ST._RefreshPreviewCommandCenterGear()
    end

end

-- Hiding a panel fires its OnClose, and CleanupWindow does the rest.
-- Downwards so an entry leaving the list cannot make the loop skip the next.
local function HideOpenPanels(settingKey)
    local closedAny = false
    for index = #openPanels, 1, -1 do
        local panel = openPanels[index]
        if panel and (settingKey == nil or panel.descriptor.settingKey == settingKey) then
            closedAny = true
            panel.window:Hide()
        end
    end
    return closedAny
end

-- `opts.settingKey` closes just that panel; without it every open panel goes,
-- which is what every shipped caller (tab switches, config close, the side
-- editors) means by "close the advanced settings".
local function CloseAdvancedSettingsPanel(opts)
    queuedOpen = nil
    local closedAny = HideOpenPanels(type(opts) == "table" and opts.settingKey or nil)
    if closedAny then
        -- Belt and braces: CleanupWindow repaints the command center gear
        -- when the OnClose callback runs, but Hide alone must not be able to
        -- leave a gold gear over a closed window.
        if ST._RefreshPreviewCommandCenterGear then
            ST._RefreshPreviewCommandCenterGear()
        end
    end
    return closedAny
end

-- The side editors that share the config surface: an advanced panel opening
-- takes it from them. None of them closes an advanced panel in turn, so this
-- is safe to run while a panel of the same batch is already up.
local function CloseCompetingEditors()
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
    if CS.CloseSpellbookPanel then
        CS.CloseSpellbookPanel()
    end
end

local function OpenPanelForDescriptor(descriptor)
    local window = AceGUI:Create("Window")
    window:SetTitle(descriptor.title or "Advanced Settings")
    window:SetWidth(GetAdvancedPanelWidth())
    window:SetHeight(MAX_PANEL_HEIGHT)
    window:SetLayout("Fill")
    window:EnableResize(false)
    window:SetCallback("OnClose", CleanupWindow)
    -- Modern UIPanelCloseButton art (RedButton-Exit) fills the whole 24x24 button,
    -- so AceGUI's legacy (+2, +1) offset leaves the X hanging outside the corner.
    if window.closebutton then
        window.closebutton:ClearAllPoints()
        window.closebutton:SetPoint("TOPRIGHT", window.frame, "TOPRIGHT", -3, -3)
    end
    if CS.RegisterConfigDragAlphaFrame then
        CS.RegisterConfigDragAlphaFrame(window.frame)
    end
    -- AceGUI hands back a recycled frame, which keeps whatever level it last
    -- had; the panel that just opened belongs on top.
    window.frame:Raise()

    local panel = { window = window, descriptor = descriptor, infoButtons = {} }
    openPanels[#openPanels + 1] = panel
    SyncPrimaryWindowHandle()

    AnchorPanelsToConfig()
    if not descriptor.deferBuild and not CS.configRefreshInProgress then
        BuildPanelContents(panel)
    end
    return panel
end

local function OpenAdvancedSettingsPanel(opts)
    local descriptor = NormalizeDescriptor(opts)
    if not descriptor then
        return false
    end

    -- Asking for the panel that is already on screen is the gear's close.
    if FindPanelIndexByDescriptor(descriptor) then
        CloseAdvancedSettingsPanel({ settingKey = descriptor.settingKey })
        return false
    end

    CloseCompetingEditors()
    -- Singleton, exactly as the settings-side gears have always been: opening
    -- one panel closes whatever else was up. Only the preview command center
    -- stacks panels, and it comes in through OpenAdvancedSettingsPanels.
    HideOpenPanels(nil)
    OpenPanelForDescriptor(descriptor)

    if ST._RefreshPreviewCommandCenterGear then
        ST._RefreshPreviewCommandCenterGear()
    end
    return true
end

-- The additive path, for the preview command center's gear only: show every
-- advanced panel the chosen preview is driven by, and nothing else. Panels
-- already open under a matching context are left exactly as they are, so a
-- repeat call neither rebuilds nor flaps them.
local function OpenAdvancedSettingsPanels(list)
    if type(list) ~= "table" then
        return false
    end

    local descriptors = {}
    for _, opts in ipairs(list) do
        local descriptor = NormalizeDescriptor(opts)
        if descriptor then
            descriptors[#descriptors + 1] = descriptor
        end
    end
    if #descriptors == 0 then
        return false
    end

    local wanted = {}
    for _, descriptor in ipairs(descriptors) do
        wanted[descriptor.settingKey] = descriptor
    end

    -- Anything else goes, including a same-key panel left over from a context
    -- that has moved on - this is still "the settings for THIS preview", not
    -- an accumulating pile of windows.
    for index = #openPanels, 1, -1 do
        local panel = openPanels[index]
        local descriptor = wanted[panel.descriptor.settingKey]
        if not (descriptor and ContextMatches(panel.descriptor.context, descriptor.context)) then
            panel.window:Hide()
        end
    end

    local openedAny = false
    for _, descriptor in ipairs(descriptors) do
        if not FindPanelIndexByDescriptor(descriptor) then
            -- Only once, and only when something actually opens: the side
            -- editors have no quarrel with a batch that is already on screen.
            if not openedAny then
                CloseCompetingEditors()
            end
            OpenPanelForDescriptor(descriptor)
            openedAny = true
        end
    end

    -- The caller's list is the stack order (owner ruling 2026-07-26: cooldown
    -- text on top, swipe below), not the order the panels happened to open in
    -- - the panel riding the queue seam opens during the rebuild and would
    -- otherwise always land first. The hide pass above left only this batch's
    -- panels in the list, so ordering by descriptor orders the whole stack.
    local ordered = {}
    local placed = {}
    for _, descriptor in ipairs(descriptors) do
        local index = FindPanelIndexByDescriptor(descriptor)
        if index and not placed[index] then
            placed[index] = true
            ordered[#ordered + 1] = openPanels[index]
        end
    end
    for index, panel in ipairs(openPanels) do
        if not placed[index] then
            ordered[#ordered + 1] = panel
        end
    end
    for index = 1, #ordered do
        openPanels[index] = ordered[index]
    end

    -- Unconditional: a reorder with nothing newly opened still moves windows.
    SyncPrimaryWindowHandle()
    AnchorPanelsToConfig()

    if ST._RefreshPreviewCommandCenterGear then
        ST._RefreshPreviewCommandCenterGear()
    end
    return openedAny
end

local function RebindAdvancedSettingsPanel(opts)
    local descriptor = NormalizeDescriptor(opts)
    if not descriptor then
        return false
    end

    local index = FindPanelIndexByDescriptor(descriptor)
    if not index then
        return false
    end

    openPanels[index].descriptor = descriptor
    return true
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
    -- Downwards: a panel whose context has moved on closes itself out of the
    -- list from inside this loop.
    for index = #openPanels, 1, -1 do
        local panel = openPanels[index]
        if not CurrentContextMatches(panel.descriptor) then
            panel.window:Hide()
        else
            BuildPanelContents(panel)
        end
    end
    AnchorPanelsToConfig()
end

local function IsAdvancedSettingsPanelOpen(settingKey, extraContext)
    local context
    for _, panel in ipairs(openPanels) do
        if panel.descriptor.settingKey == settingKey then
            -- Built only once a key matches, and only once: every advanced
            -- gear asks this on every tab rebuild, and BuildContext is not
            -- free (it allocates and sorts four selection sets).
            context = context or BuildContext(extraContext)
            if ContextMatches(panel.descriptor.context, context) then
                return true
            end
        end
    end
    return false
end

CS.OpenAdvancedSettingsPanel = OpenAdvancedSettingsPanel
CS.OpenAdvancedSettingsPanels = OpenAdvancedSettingsPanels
CS.CloseAdvancedSettingsPanel = CloseAdvancedSettingsPanel
CS.RefreshAdvancedSettingsPanel = RefreshAdvancedSettingsPanel
CS.RebindAdvancedSettingsPanel = RebindAdvancedSettingsPanel
CS.QueueAdvancedSettingsPanelOpen = QueueAdvancedSettingsPanelOpen
CS.ConsumeQueuedAdvancedSettingsPanelOpen = ConsumeQueuedAdvancedSettingsPanelOpen
CS.IsAdvancedSettingsPanelOpen = IsAdvancedSettingsPanelOpen
