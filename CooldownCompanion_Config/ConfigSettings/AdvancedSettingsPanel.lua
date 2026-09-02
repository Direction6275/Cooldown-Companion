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

-- Which settings-side gears actually built during the current build pass.
-- The pass is owned by the dispatch funnels that each rebuild exactly one
-- settings surface (GroupSettingsHost.lua, ResourcesWideColumn.lua): they
-- wrap every rebuild in RunAdvancedGearBuildPass below, so a build can
-- never begin without sweeping. Builders never touch the pair themselves.
-- AddAdvancedToggle stamps every SHOWN gear (Helpers.lua).
local builtGearKeys = {}
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
        -- Which strip owns the settings surface (UnifiedTabRow.lua). Pinned
        -- even on lens-agnostic descriptors: growing a multi-select (or moving
        -- to the entry cluster's own tabs) swaps the surface WITHOUT running
        -- the styling tab's gear pass, so no sweep sees the gear go - this
        -- mismatch is what closes the panel there. Read through the strip's
        -- own accessor so this snapshot can never normalize differently from
        -- the strip's readers.
        unifiedRowScope = ST._UnifiedRowGetScope(),
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

-- The context fields a lens-agnostic descriptor deliberately does NOT pin.
-- The styling tabs are a LENS over one panel, and a settings-side gear's
-- panel follows lens shifts (owner ruling 2026-08-31): open Cooldown Text
-- Advanced at panel scope, select an entry, and the same panel rebinds to
-- that entry's scope - read-only with the Customize step when inherited,
-- live when customized - instead of closing. Everything else in the context
-- (the group, the surface, the tabs) still closes it, and a gear that does
-- not rebuild closes its panel through the dispatch-level sweep below.
local LENS_CONTEXT_FIELDS = { selectedButton = true, selectedButtons = true }

local function ContextMatches(left, right, ignoredFields)
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end

    for key, value in pairs(left) do
        if not (ignoredFields and ignoredFields[key]) and right[key] ~= value then
            return false
        end
    end
    for key, value in pairs(right) do
        if not (ignoredFields and ignoredFields[key]) and left[key] ~= value then
            return false
        end
    end
    return true
end

-- The one compare every context check on a STORED descriptor routes through:
-- a lens-agnostic descriptor simply ignores the lens fields on both sides -
-- no copies, no stripping, contexts stay whole.
local function MatchesDescriptorContext(descriptor, context)
    return ContextMatches(descriptor.context, context,
        descriptor.lensAgnostic and LENS_CONTEXT_FIELDS or nil)
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

    local descriptor = {
        settingKey = opts.settingKey,
        title = opts.title or "Advanced Settings",
        build = opts.build,
        isAvailable = type(opts.isAvailable) == "function" and opts.isAvailable or nil,
        contextExtra = opts.context,
        context = BuildContext(opts.context),
        deferBuild = opts.deferBuild == true,
        -- The LAZY unlock spec (lens { sec, enable } or non-lens
        -- { target, enable, refreshKind }), stored unresolved: only the
        -- panel build consumes it, through ST._ResolveAdvancedUnlock.
        unlock = type(opts.unlock) == "table" and opts.unlock or nil,
        lensAgnostic = opts.lensAgnostic == true,
    }
    return descriptor
end

local function CurrentContextMatches(descriptor)
    if not descriptor then
        return false
    end
    if descriptor.isAvailable and not descriptor.isAvailable() then
        return false
    end
    return MatchesDescriptorContext(descriptor, BuildContext(descriptor.contextExtra))
end

local function FindPanelIndexByDescriptor(descriptor)
    for index, panel in ipairs(openPanels) do
        -- The STORED panel's lensAgnostic governs, same as every other check
        -- on an open panel (IsAdvancedSettingsPanelOpen, the refresh close),
        -- so "is this panel open" answers identically from both directions.
        if panel.descriptor.settingKey == descriptor.settingKey
            and MatchesDescriptorContext(panel.descriptor, descriptor.context)
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

local function BuildPanelContentsBody(panel)
    local window = panel.window
    local descriptor = panel.descriptor

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
    -- The descriptor's unlock is a LAZY spec; resolving it is what decides
    -- whether THIS build opens locked (ST._ResolveAdvancedUnlock, Helpers.lua)
    -- - resolved once per build, before the build runs, so the build itself
    -- can see the lock (bar mode's Icon Zoom exemption). A locked descriptor
    -- opens READ-ONLY: the build runs exactly as it would live, the sweep
    -- disables what it put in - the same built-like-live rule the main
    -- column's inert ranges follow - and the centered footer, in the slack
    -- every panel ends in, carries the ONE step that makes the grey editable:
    -- Customize for an inherited section, or the one-way Turn On for a parent
    -- toggle that is off (Customize first when both apply - its rebuild
    -- re-renders the footer with the next step).
    descriptor._resolvedUnlock = descriptor.unlock
        and ST._ResolveAdvancedUnlock and ST._ResolveAdvancedUnlock(descriptor.unlock) or nil
    descriptor.build(scroll, descriptor)
    if descriptor._resolvedUnlock then
        if ST._MakeAdvancedPanelReadOnly then
            ST._MakeAdvancedPanelReadOnly(scroll)
        end
        if ST._BuildAdvancedUnlockStrip then
            ST._BuildAdvancedUnlockStrip(scroll, descriptor._resolvedUnlock)
        end
    end

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

    -- Descriptors are rebound fresh each gear pass, but a resolution must
    -- still never outlive the build that made it - it holds this build's
    -- closures.
    descriptor._resolvedUnlock = nil
end

local function BuildPanelContents(panel)
    if not panel then
        return
    end
    if refreshingAdvancedPanel then
        return
    end
    refreshingAdvancedPanel = true
    CS.advancedSettingsPanelRefreshing = true
    -- Error boundary, not control flow: the two flags above gate EVERY future
    -- build (the early return), so an uncaught error in a descriptor's build
    -- must not strand them set - that would silently freeze all advanced
    -- panels until reload. The error still reaches the user's error handler.
    xpcall(BuildPanelContentsBody, CallErrorHandler, panel)
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
    -- one panel closes whatever else was up. (The preview command center's
    -- open-every-panel path was retired 2026-08-08 with the combined cooldown
    -- preview that needed it; its gear rides this one-at-a-time seam now.)
    HideOpenPanels(nil)
    OpenPanelForDescriptor(descriptor)

    if ST._RefreshPreviewCommandCenterGear then
        ST._RefreshPreviewCommandCenterGear()
    end
    return true
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
        or not MatchesDescriptorContext(descriptor, queuedOpen.context)
    then
        return false
    end

    queuedOpen = nil
    -- The queue means "make sure this panel is up after the rebuild", never
    -- "toggle". An enable checkbox queues its own panel while that panel can
    -- already be open read-only behind the Turn On strip; falling through to
    -- OpenAdvancedSettingsPanel would read the match as the gear's close
    -- gesture and shut the panel the user is looking at. Already open in this
    -- context is the queue already satisfied - the rebind in AddAdvancedToggle
    -- is what hands it the fresh descriptor.
    if FindPanelIndexByDescriptor(descriptor) then
        return true
    end
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

-- The gear-panel lifetime rule, one owner for both halves (review finding
-- 2026-08-31): a lens-agnostic panel is CURRENT only while its gear rebuilds
-- and rebinds it every pass. Begin wipes the stamp set before a surface
-- builds; the sweep after it closes every open lens-agnostic panel whose
-- gear did not stamp this pass - a collapsed section, a gated block, a
-- denied section, or a gear that lives on the other sub-tab. Whether the
-- section still resolves a write table is deliberately irrelevant: an
-- unrebound panel's build closures point at the PREVIOUS selection's tables,
-- and write-table presence was only ever a proxy that let customized-scope
-- panels survive unrebound with stale closures. Panels whose descriptors are
-- NOT lens-agnostic (the preview command center's factory opens) are never
-- touched here - cross-tab living is their designed behavior.
local function BeginAdvancedGearBuildPass()
    wipe(builtGearKeys)
end

local function StampAdvancedGearBuilt(settingKey)
    builtGearKeys[settingKey] = true
end

local function SweepUnbuiltAdvancedGearPanels()
    -- Downwards: closing drops entries from openPanels mid-loop.
    for index = #openPanels, 1, -1 do
        local panel = openPanels[index]
        if panel and panel.descriptor.lensAgnostic
            and not builtGearKeys[panel.descriptor.settingKey]
        then
            panel.window:Hide()
        end
    end
end

-- The pair's one entry point. The dispatch funnels that each rebuild exactly
-- one settings surface (GroupSettingsHost's styling-tab select and
-- ResourcesWideColumn's pane dispatches) wrap every rebuild in this, so a
-- build can never begin without sweeping - a builder's early returns all
-- land on the sweep here. Builders themselves never touch the pair, and a
-- sweep on a gearless surface is the desired behavior: entering it closes
-- whatever stale gear panels the previous surface left open.
local function RunAdvancedGearBuildPass(fn, ...)
    BeginAdvancedGearBuildPass()
    fn(...)
    SweepUnbuiltAdvancedGearPanels()
end

local function IsAdvancedSettingsPanelOpen(settingKey, extraContext)
    local context
    for _, panel in ipairs(openPanels) do
        if panel.descriptor.settingKey == settingKey then
            -- Built only once a key matches, and only once: every advanced
            -- gear asks this on every tab rebuild, and BuildContext is not
            -- free (it allocates and sorts four selection sets).
            context = context or BuildContext(extraContext)
            if MatchesDescriptorContext(panel.descriptor, context) then
                return true
            end
        end
    end
    return false
end

CS.OpenAdvancedSettingsPanel = OpenAdvancedSettingsPanel
CS.CloseAdvancedSettingsPanel = CloseAdvancedSettingsPanel
CS.StampAdvancedGearBuilt = StampAdvancedGearBuilt
CS.RunAdvancedGearBuildPass = RunAdvancedGearBuildPass
CS.RefreshAdvancedSettingsPanel = RefreshAdvancedSettingsPanel
CS.RebindAdvancedSettingsPanel = RebindAdvancedSettingsPanel
CS.QueueAdvancedSettingsPanelOpen = QueueAdvancedSettingsPanelOpen
CS.ConsumeQueuedAdvancedSettingsPanelOpen = ConsumeQueuedAdvancedSettingsPanelOpen
CS.IsAdvancedSettingsPanelOpen = IsAdvancedSettingsPanelOpen
