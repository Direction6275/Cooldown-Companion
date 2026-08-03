--[[
    CooldownCompanion - Config/PanelShared
    Shared panel creation, entry-row presentation, inline-add, and context
    menu services used by the consolidated Navigator and workspace.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local RB = ST._RB
local RESOURCE_HEALTH = RB and RB.RESOURCE_HEALTH or -1

-- Imports from earlier Config/ files
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local ResolveViewerChildForSpellDisplay = ST.ResolveViewerChildForSpellDisplay
local NotifyTutorialAction = ST._NotifyTutorialAction
local SelectConfigPanel = ST._SelectConfigPanel
local ClearConfigButtonSelection = ST._ClearConfigButtonSelection
local ClearConfigPanelSelection = ST._ClearConfigPanelSelection
local BuildCDMPanelSourceData = ST._BuildCDMPanelSourceData
local GetCDMPanelSourceData = ST._GetCDMPanelSourceData
local PopulateCDMPanelFromSource = ST._PopulateCDMPanelFromSource
local ApplyCDMStarterPanelLayout = ST._ApplyCDMStarterPanelLayout
local IsCDMPanelSourceKey = ST._IsCDMPanelSourceKey
local GetCDMPanelSourceDisplayMode = ST._GetCDMPanelSourceDisplayMode

local RefreshCDMPanelFromSource
local function CanMoveEntryToGroup(sourceGroupId, targetGroupId)
    if CooldownCompanion.CanMoveEntryToGroup then
        return CooldownCompanion:CanMoveEntryToGroup(sourceGroupId, targetGroupId) == true
    end
    return CooldownCompanion:IsGroupVisibleToCurrentChar(targetGroupId)
end
local tonumber = tonumber
local ipairs = ipairs

-- The one cyan accent every "make something new" affordance wears, so the add
-- tile, the empty-Group type cards, and anything that joins them later cannot
-- drift to slightly different blues. Idle is the hover hue held back to a
-- whisper; hover is the hue at full strength. The fills put a subtle cool tint
-- over a mostly opaque dark plate, with a lighter response under the cursor.
local CREATE_ACCENT = {
    idleBorder = { 0.32, 0.82, 1, 0.35 },
    hoverBorder = { 0.32, 0.82, 1, 1 },
    idleFill = { 0.10, 0.14, 0.19, 0.80 },
    hoverFill = { 0.13, 0.18, 0.24, 0.85 },
}

-- Single source of truth for the creatable panel types: menu order, menu
-- label, tooltip copy, and the per-type defaults a create menu applies.
-- Every create surface reads this so the two menus cannot drift apart.
-- Descriptor order is the menu split: the two everyday types lead, and the
-- create menus draw their separator before the third.
-- `primary` marks those same two everyday types. The empty-Group picker sizes
-- its tiers by this flag alone, and the menus' separator split matches it, so
-- one edit here moves a type on every create surface at once.
local PANEL_TYPES = {
    {
        mode = "icons",
        label = "Icon Panel",
        description = "Shows spells or items as classic cooldown icons.",
        primary = true,
        -- The tutorial's create-panel step only advances on an Icon Panel.
        notifyTutorial = true,
    },
    {
        mode = "bars",
        label = "Bar Panel",
        description = "Shows spells or items as timer bars with names and durations.",
        primary = true,
        verticalStyle = true,
    },
    {
        mode = "text",
        label = "Text Panel",
        description = "Shows text-only entries for compact readouts and status lists.",
        verticalStyle = true,
    },
    {
        mode = "textures",
        label = "Texture Panel",
        description = "Shows one standalone texture for a single spell or item.",
    },
    {
        mode = "trigger",
        label = "Trigger Panel",
        description = "Add spell or item entries, then set conditions on each one. The display appears only when every enabled entry meets its conditions.",
    },
    {
        mode = ST.DISPLAY_MODE_ROTATION_ASSISTANT,
        label = ST.ROTATION_ASSISTANT_NAME or "Assistant Panel",
        description = "Shows one locked recommendation icon from the in-game assistant.",
    },
}

local PANEL_TYPE_BY_MODE = {}
for _, panelType in ipairs(PANEL_TYPES) do
    PANEL_TYPE_BY_MODE[panelType.mode] = panelType
end

local function GetPanelTypeInfo(displayMode)
    return PANEL_TYPE_BY_MODE[displayMode] or PANEL_TYPE_BY_MODE.icons
end
local function AddPanelTypeMenuTooltip(info, displayMode)
    local panelType = GetPanelTypeInfo(displayMode)
    if not panelType then
        return
    end

    info.tooltipTitle = panelType.label
    info.tooltipText = panelType.description
    info.tooltipOnButton = true
end

-- Creation options a menu passes to CreatePanelInSelectedContainer.
local function BuildPanelCreateOptions(displayMode)
    local panelType = GetPanelTypeInfo(displayMode)
    return {
        verticalStyle = panelType.verticalStyle,
        notifyTutorial = panelType.notifyTutorial,
    }
end
local function AddCDMStarterMenuTooltip(info)
    info.tooltipTitle = "Add Missing CDM Panels"
    info.tooltipText = "Creates any missing Cooldown Manager starter panels without duplicating existing CDM panels."
    info.tooltipOnButton = true
end

local function IsActiveCDMPanelSource(panel)
    if not (panel
        and panel.cdmPanelSource
        and IsCDMPanelSourceKey
        and IsCDMPanelSourceKey(panel.cdmPanelSource)) then
        return false
    end

    local expectedMode = GetCDMPanelSourceDisplayMode and GetCDMPanelSourceDisplayMode(panel.cdmPanelSource) or nil
    return expectedMode == nil or panel.displayMode == expectedMode
end

local function FinalizeCreatedPanel(newPanelId, displayMode, opts)
    if not newPanelId then
        return
    end

    local group = CooldownCompanion.db.profile.groups[newPanelId]
    if opts and opts.verticalStyle and group then
        group.style.orientation = "vertical"
        if group.masqueEnabled then
            CooldownCompanion:ToggleGroupMasque(newPanelId, false)
        end
        CooldownCompanion:RefreshGroupFrame(newPanelId)
    end

    SelectConfigPanel(newPanelId, {
        containerId = opts and opts.containerId or nil,
    })
    local acceptsManualEntries = CooldownCompanion:CanPanelAcceptManualEntry(group)
    if acceptsManualEntries then
        CS.addingToPanelId = newPanelId
        CS.pendingEditBoxFocus = true
    else
        CS.addingToPanelId = nil
        CS.pendingEditBoxFocus = false
    end
    CooldownCompanion:RefreshConfigPanel()

    if opts and opts.notifyTutorial and NotifyTutorialAction then
        NotifyTutorialAction("panel_created", {
            containerId = CS.selectedContainer,
            panelId = newPanelId,
            displayMode = displayMode,
        })
    end
end

local function CreatePanelInSelectedContainer(displayMode, opts, containerId)
    containerId = containerId or CS.selectedContainer
    opts = opts or {}
    opts.containerId = containerId
    local newPanelId = CooldownCompanion:CreatePanel(containerId, displayMode)
    FinalizeCreatedPanel(newPanelId, displayMode, opts)
end

local function PrintCooldownManagerUnavailable(sourceData)
    local reason = sourceData and sourceData.failureReason
    if type(reason) ~= "string" or reason == "" then
        reason = "Unknown reason"
    end
    CooldownCompanion:Print("Cooldown Manager unavailable: " .. reason)
end

local function GetExistingCDMPanelSources(containerId)
    local existing = {}
    for _, panelInfo in ipairs(CooldownCompanion:GetPanels(containerId) or {}) do
        local panel = panelInfo.group
        if IsActiveCDMPanelSource(panel) then
            existing[panel.cdmPanelSource] = true
        end
    end
    return existing
end

local function NormalizeCDMPanelOrder(containerId, sourceData)
    local desiredRank = {}
    for index, source in ipairs(sourceData and sourceData.sources or {}) do
        desiredRank[source.key] = index
    end

    local panels = CooldownCompanion:GetPanels(containerId) or {}
    local cdmPanels = {}
    for index, panelInfo in ipairs(panels) do
        local panel = panelInfo.group
        if IsActiveCDMPanelSource(panel) and desiredRank[panel.cdmPanelSource] then
            cdmPanels[#cdmPanels + 1] = {
                panelId = panelInfo.groupId,
                rank = desiredRank[panel.cdmPanelSource],
                originalIndex = index,
            }
        end
    end

    if #cdmPanels < 2 then
        return false
    end

    table.sort(cdmPanels, function(a, b)
        if a.rank == b.rank then
            return a.originalIndex < b.originalIndex
        end
        return a.rank < b.rank
    end)

    local nextCDMIndex = 1
    local changed = false
    for index, panelInfo in ipairs(panels) do
        local panel = panelInfo.group
        local panelId = panelInfo.groupId
        if IsActiveCDMPanelSource(panel) and desiredRank[panel.cdmPanelSource] then
            panelId = cdmPanels[nextCDMIndex].panelId
            nextCDMIndex = nextCDMIndex + 1
        end

        local target = CooldownCompanion.db.profile.groups[panelId]
        if target and target.order ~= index then
            target.order = index
            changed = true
        end
        if panelInfo.groupId ~= panelId then
            changed = true
        end
    end

    return changed
end

local function RefreshCDMPanelOrderRuntime()
    if CooldownCompanion.RefreshAllGroups then
        CooldownCompanion:RefreshAllGroups()
    end
    if CooldownCompanion.EvaluateBarsAndFramesRuntime then
        CooldownCompanion:EvaluateBarsAndFramesRuntime("cdm-panel-order")
    end
end

local function CreateCDMPanelFromSource(containerId, sourceData)
    local panelId = CooldownCompanion:CreatePanel(containerId, sourceData.displayMode)
    if not panelId then
        return nil, 0
    end

    local group = CooldownCompanion.db.profile.groups[panelId]
    if group then
        group.name = sourceData.panelName
        group.cdmPanelSource = sourceData.key
        if ApplyCDMStarterPanelLayout then
            ApplyCDMStarterPanelLayout(group, sourceData.key, containerId, sourceData.entries and #sourceData.entries or 0)
        end
    end

    local added = PopulateCDMPanelFromSource and PopulateCDMPanelFromSource(panelId, sourceData) or 0
    return panelId, added
end

local function CreateMissingCDMPanelsInSelectedContainer(containerId)
    containerId = containerId or CS.selectedContainer
    if not containerId then
        return
    end

    if not BuildCDMPanelSourceData then
        CooldownCompanion:Print("Cooldown Manager panel setup is unavailable.")
        return
    end

    local sourceData = BuildCDMPanelSourceData()
    if not (sourceData and sourceData.available) then
        PrintCooldownManagerUnavailable(sourceData)
        return
    end

    if (sourceData.totalEntries or 0) == 0 then
        CooldownCompanion:Print("No displayed Cooldown Manager entries found.")
        return
    end

    local existingSources = GetExistingCDMPanelSources(containerId)
    local createdPanelIds = {}
    local createdBySource = {}
    local createdEntryCount = 0

    for _, source in ipairs(sourceData.sources or {}) do
        if not existingSources[source.key] and source.entries and #source.entries > 0 then
            local panelId, added = CreateCDMPanelFromSource(containerId, source)
            if panelId then
                createdPanelIds[#createdPanelIds + 1] = panelId
                createdBySource[source.key] = panelId
                createdEntryCount = createdEntryCount + (added or 0)
                existingSources[source.key] = true
            end
        end
    end

    local orderChanged = NormalizeCDMPanelOrder(containerId, sourceData)
    if orderChanged then
        RefreshCDMPanelOrderRuntime()
    end

    if #createdPanelIds == 0 then
        if orderChanged then
            CooldownCompanion:RefreshConfigPanel()
            CooldownCompanion:Print("Reordered Cooldown Manager panels.")
            return
        end
        CooldownCompanion:Print("No missing Cooldown Manager panels to add.")
        return
    end

    local selectPanelId = createdBySource.essential or createdPanelIds[1]
    SelectConfigPanel(selectPanelId, { containerId = containerId })
    CS.addingToPanelId = nil
    CS.pendingEditBoxFocus = false
    CooldownCompanion:RefreshConfigPanel()
    CooldownCompanion:Print(("Created %d Cooldown Manager panel%s with %d entr%s."):format(
        #createdPanelIds,
        #createdPanelIds == 1 and "" or "s",
        createdEntryCount,
        createdEntryCount == 1 and "y" or "ies"
    ))
end

local function DeleteEmptyCDMPanel(data)
    if type(data) ~= "table" then
        return
    end

    local containerId = data.containerId
    local panelId = data.panelId
    local panel = CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups
        and CooldownCompanion.db.profile.groups[panelId]
        or nil
    if not panel or panel.parentContainerId ~= containerId or panel.cdmPanelSource ~= data.sourceKey then
        return
    end

    local panelName = panel.name or "Panel"
    CooldownCompanion:ClearAllConfigPreviews()
    if CooldownCompanion:DeletePanel(containerId, panelId) then
        if CS.selectedGroup == panelId and ClearConfigPanelSelection then
            ClearConfigPanelSelection()
        end
        if CS.selectedPanels then
            CS.selectedPanels[panelId] = nil
        end
        if CS.addingToPanelId == panelId then
            CS.addingToPanelId = nil
        end
        CooldownCompanion:RefreshConfigPanel()
        CooldownCompanion:Print("Deleted " .. panelName .. ": Cooldown Manager section is empty.")
    end
end
ST._DeleteEmptyCDMPanel = DeleteEmptyCDMPanel

RefreshCDMPanelFromSource = function(panelId, panel, containerId)
    if not IsActiveCDMPanelSource(panel) then
        return
    end

    local sourceData = BuildCDMPanelSourceData and BuildCDMPanelSourceData() or nil
    if not (sourceData and sourceData.available) then
        PrintCooldownManagerUnavailable(sourceData)
        return
    end

    local source = GetCDMPanelSourceData and GetCDMPanelSourceData(sourceData, panel.cdmPanelSource) or nil
    if not source or not source.entries or #source.entries == 0 then
        ShowPopupAboveConfig("CDC_DELETE_EMPTY_CDM_PANEL", panel.name or "Panel", {
            containerId = containerId,
            panelId = panelId,
            sourceKey = panel.cdmPanelSource,
        })
        return
    end

    local added = PopulateCDMPanelFromSource and PopulateCDMPanelFromSource(panelId, source) or 0
    if CS.selectedGroup == panelId and ClearConfigButtonSelection then
        ClearConfigButtonSelection()
    end
    CooldownCompanion:RefreshConfigPanel()
    CooldownCompanion:Print(("Refreshed %s from Cooldown Manager (%d entr%s)."):format(
        panel.name or "Panel",
        added,
        added == 1 and "y" or "ies"
    ))
end
ST._RefreshCDMPanelFromSource = RefreshCDMPanelFromSource
ST._IsActiveCDMPanelSource = IsActiveCDMPanelSource
local function ResolveEntryTooltipSpellId(buttonData)
    if not (buttonData and buttonData.type == "spell") then
        return nil
    end

    local child = ResolveViewerChildForSpellDisplay(CooldownCompanion, buttonData)

    if child and child.cooldownInfo then
        if child.cooldownInfo.overrideTooltipSpellID then
            return child.cooldownInfo.overrideTooltipSpellID
        end
        if child.cooldownInfo.overrideSpellID then
            return child.cooldownInfo.overrideSpellID
        end
    end

    local rawOverride = C_Spell.GetOverrideSpell(buttonData.id)
    if rawOverride and rawOverride ~= 0 then
        return rawOverride
    end

    return buttonData.id
end

local function MoveEntryBetweenGroups(db, sourceGroupId, sourceIndex, targetGroupId, entryData)
    local targetGroup = db and db.groups and db.groups[targetGroupId]
    if not targetGroup then
        return false
    end
    if not CanMoveEntryToGroup(sourceGroupId, targetGroupId) then
        return false
    end
    local rejectMessage = CooldownCompanion:GetPanelManualEntryRejectMessage(targetGroup, entryData)
    if rejectMessage then
        CooldownCompanion:Print(rejectMessage)
        return false
    end

    table.insert(targetGroup.buttons, entryData)
    table.remove(db.groups[sourceGroupId].buttons, sourceIndex)
    CooldownCompanion:RefreshGroupFrame(targetGroupId)
    CooldownCompanion:RefreshGroupFrame(sourceGroupId)
    CooldownCompanion:ClearAllConfigPreviews()
    CS.selectedButton = nil
    CS.selectedRotationAssistantEntry = nil
    wipe(CS.selectedButtons)
    CooldownCompanion:RefreshConfigPanel()
    return true
end

local function BuildEntryMoveDestinationSections(db, sourceGroupId)
    local containers = db and db.groupContainers or {}
    local groupedByContainer = {}

    for groupId, group in pairs(db.groups or {}) do
        if groupId ~= sourceGroupId
            and CanMoveEntryToGroup(sourceGroupId, groupId)
            and CooldownCompanion:CanPanelAcceptManualEntry(group)
        then
            local containerId = group.parentContainerId
            local container = containerId and containers[containerId]
            if container then
                local entry = groupedByContainer[containerId]
                if not entry then
                    entry = {
                        containerId = containerId,
                        containerName = container.name or ("Group " .. containerId),
                        containerOrder = CooldownCompanion:GetOrderForSpec(
                            container,
                            CooldownCompanion._currentSpecId,
                            containerId
                        ),
                        panels = {},
                    }
                    groupedByContainer[containerId] = entry
                end

                entry.panels[#entry.panels + 1] = {
                    groupId = groupId,
                    name = group.name or ("Panel " .. groupId),
                    order = group.order or groupId,
                }
            end
        end
    end

    local function BuildSectionEntries(containerMap)
        local entries = {}
        for _, containerEntry in pairs(containerMap or {}) do
            table.sort(containerEntry.panels, function(a, b)
                if a.order ~= b.order then
                    return a.order < b.order
                end
                return a.groupId < b.groupId
            end)
            entries[#entries + 1] = containerEntry
        end

        table.sort(entries, function(a, b)
            if a.containerOrder ~= b.containerOrder then
                return a.containerOrder < b.containerOrder
            end
            return a.containerId < b.containerId
        end)

        return entries
    end

    local entries = BuildSectionEntries(groupedByContainer)
    return #entries > 0 and { { entries = entries } } or {}
end

local ENTRY_MOVE_GROUP_MENU_PREFIX = "ENTRY_MOVE_GROUP:"

local function FindEntryMoveContainerEntry(sections, containerId)
    for _, section in ipairs(sections or {}) do
        for _, containerEntry in ipairs(section.entries or {}) do
            if containerEntry.containerId == containerId then
                return containerEntry
            end
        end
    end
    return nil
end

local function ParseEntryMoveContainerId(menuList)
    if type(menuList) ~= "string" then
        return nil
    end
    local idText = menuList:match("^" .. ENTRY_MOVE_GROUP_MENU_PREFIX .. "(%d+)$")
    return idText and tonumber(idText) or nil
end

local function AddEntryMoveDestinationButtons(level, sourceGroupId, sourceIndex, entryData, menuList)
    local db = CooldownCompanion.db.profile
    local sections = BuildEntryMoveDestinationSections(db, sourceGroupId)

    local targetContainerId = ParseEntryMoveContainerId(menuList)
    if targetContainerId then
        local containerEntry = FindEntryMoveContainerEntry(sections, targetContainerId)
        if not containerEntry then
            return
        end

        for _, panel in ipairs(containerEntry.panels) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = panel.name
            info.notCheckable = true
            info.func = function()
                if MoveEntryBetweenGroups(db, sourceGroupId, sourceIndex, panel.groupId, entryData) then
                    CloseDropDownMenus()
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
        return
    end

    for _, section in ipairs(sections) do
        if section.title then
            local header = UIDropDownMenu_CreateInfo()
            header.text = section.title
            header.isTitle = true
            header.notCheckable = true
            UIDropDownMenu_AddButton(header, level)
        end

        for _, containerEntry in ipairs(section.entries) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = containerEntry.containerName
            info.notCheckable = true
            info.hasArrow = true
            info.menuList = ENTRY_MOVE_GROUP_MENU_PREFIX .. tostring(containerEntry.containerId)
            info.leftPadding = section.title and 10 or 0
            UIDropDownMenu_AddButton(info, level)
        end
    end
end

-- Shared entry context menu used by preview and workspace list surfaces.
local function ShowEntryContextMenu(panelId, index, buttonData)
    if not CS.buttonContextMenu then
        CS.buttonContextMenu = CreateFrame("Frame", "CDCButtonContextMenu", UIParent, "UIDropDownMenuTemplate")
    end
    local sourceGroupId = panelId
    local sourceIndex = index
    local entryData = buttonData
    UIDropDownMenu_Initialize(CS.buttonContextMenu, function(self, level, menuList)
        level = level or 1
        if level == 1 then
            -- Disable / Enable button
            local toggleInfo = UIDropDownMenu_CreateInfo()
            toggleInfo.text = (entryData.enabled ~= false) and "Disable" or "Enable"
            toggleInfo.notCheckable = true
            toggleInfo.func = function()
                CloseDropDownMenus()
                entryData.enabled = not (entryData.enabled ~= false)
                CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                CooldownCompanion:RefreshConfigPanel()
            end
            UIDropDownMenu_AddButton(toggleInfo, level)

            local sourceGroup = CooldownCompanion.db.profile.groups[sourceGroupId]
            if not (sourceGroup and sourceGroup.displayMode == "textures") then
                local dupInfo = UIDropDownMenu_CreateInfo()
                dupInfo.text = "Duplicate"
                dupInfo.notCheckable = true
                dupInfo.func = function()
                    local copy = CopyTable(entryData)
                    table.insert(CooldownCompanion.db.profile.groups[sourceGroupId].buttons, sourceIndex + 1, copy)
                    -- Structural-mutation contract: entries after the insert
                    -- point shifted, so remap the single selection and clear
                    -- the index-keyed multi-selection and preview stores.
                    if CS.selectedButton and CS.selectedButton > sourceIndex then
                        CS.selectedButton = CS.selectedButton + 1
                    end
                    wipe(CS.selectedButtons)
                    CooldownCompanion:ClearAllConfigPreviews()
                    CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                    CooldownCompanion:RefreshConfigPanel()
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(dupInfo, level)
            end

            local iconInfo = UIDropDownMenu_CreateInfo()
            iconInfo.text = "Override Icon..."
            iconInfo.notCheckable = true
            iconInfo.tooltipTitle = "|cffffd100Override Icon|r"
            iconInfo.tooltipText = "|cffffffffReplaces the default spell or item icon.|r"
            iconInfo.tooltipOnButton = true
            iconInfo.func = function()
                CloseDropDownMenus()
                ST._OpenButtonIconPicker(sourceGroupId, sourceIndex)
            end
            UIDropDownMenu_AddButton(iconInfo, level)

            if ST._IsValidIconTexture(entryData.manualIcon) then
                local resetIconInfo = UIDropDownMenu_CreateInfo()
                resetIconInfo.text = "Reset Icon"
                resetIconInfo.notCheckable = true
                resetIconInfo.func = function()
                    CloseDropDownMenus()
                    entryData.manualIcon = nil
                    CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(resetIconInfo, level)
            end

            local moveInfo = UIDropDownMenu_CreateInfo()
            moveInfo.text = "Move to..."
            moveInfo.notCheckable = true
            moveInfo.hasArrow = true
            moveInfo.menuList = "MOVE_TO_GROUP"
            UIDropDownMenu_AddButton(moveInfo, level)

            local removeInfo = UIDropDownMenu_CreateInfo()
            removeInfo.text = "Remove"
            removeInfo.notCheckable = true
            removeInfo.func = function()
                CloseDropDownMenus()
                local name = entryData.name or "this entry"
                ShowPopupAboveConfig("CDC_DELETE_BUTTON", name, { groupId = sourceGroupId, buttonIndex = sourceIndex })
            end
            UIDropDownMenu_AddButton(removeInfo, level)
        elseif menuList == "MOVE_TO_GROUP"
            or ParseEntryMoveContainerId(menuList)
        then
            AddEntryMoveDestinationButtons(
                level,
                sourceGroupId,
                sourceIndex,
                entryData,
                menuList
            )
        end
    end, "MENU")
    CS.buttonContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.buttonContextMenu, "cursor", 0, 0)
end

------------------------------------------------------------------------
------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._ShowEntryContextMenu = ShowEntryContextMenu
ST._AddPanelTypeMenuTooltip = AddPanelTypeMenuTooltip
ST._AddCDMStarterMenuTooltip = AddCDMStarterMenuTooltip
-- Ordered creatable panel types, shared by every panel-create surface.
ST._PANEL_TYPES = PANEL_TYPES
-- Shared create accent, so no surface hand-writes its own cyan.
ST._CREATE_ACCENT = CREATE_ACCENT
ST._BuildPanelCreateOptions = BuildPanelCreateOptions
ST._CreatePanelInSelectedContainer = CreatePanelInSelectedContainer
ST._CreateMissingCDMPanelsInSelectedContainer = CreateMissingCDMPanelsInSelectedContainer
-- Shared with the panel preview mirror: entry tooltips resolve the
-- currently-active override spell, not the stored base ID.
ST._ResolveEntryTooltipSpellId = ResolveEntryTooltipSpellId
