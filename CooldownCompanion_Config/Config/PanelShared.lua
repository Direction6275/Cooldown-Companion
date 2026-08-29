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
local SelectConfigButton = ST._SelectConfigButton
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
-- The empty-Group picker may use an optional shorter `pickerLabel` or
-- `pickerDescription`; the full label and description remain the create menus'
-- richer explanation. Every create surface still reads this one descriptor.
-- Descriptor order is the menu order, and a `parentMode` type is a SUBTYPE of
-- the type it names: it sits directly under its parent and the menus indent it.
-- Its `mode` is a pseudo-mode CreatePanel resolves into a real displayMode plus
-- the subtype flag, so it never reaches group.displayMode.
-- `primary` marks the everyday types. The empty-Group picker sizes its tiers by
-- this flag alone, and the menus' separator split covers the primaries plus
-- their subtypes, so one edit here moves a type on every create surface at once.
local PANEL_TYPES = {
    {
        mode = "icons",
        label = "Icon Panel",
        description = "Shows spells or items as classic cooldown icons.",
        pickerDescription = "Classic cooldown icons",
        primary = true,
        -- The tutorial's create-panel step only advances on an Icon Panel.
        notifyTutorial = true,
    },
    {
        mode = "auraIcons",
        parentMode = "icons",
        label = "Aura Icon Panel",
        pickerLabel = "Aura Icons",
        description = "Holds only aura entries, and shows each icon while its aura is up. Inactive auras take no space. The first entry you add sets whether the panel tracks your buffs or your target's debuffs.",
    },
    {
        mode = "bars",
        label = "Bar Panel",
        description = "Shows spells or items as timer bars with names and durations.",
        pickerDescription = "Named timer bars",
        primary = true,
    },
    {
        mode = "auraBars",
        parentMode = "bars",
        label = "Aura Bar Panel",
        pickerLabel = "Aura Bars",
        description = "Holds only aura entries, and shows each bar while its aura is up. Inactive auras take no space. The first entry you add sets whether the panel tracks your buffs or your target's debuffs.",
    },
    {
        mode = "text",
        label = "Text Panel",
        description = "Shows text-only entries for compact readouts and status lists.",
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

-- A subtype leads the menu with its parent, so the everyday block covers the
-- primaries AND anything hanging off one. Derived from the descriptor rather
-- than hand-counted, so inserting or promoting a type cannot leave a stale
-- index behind on the create surfaces.
local FIRST_SPECIALIST_PANEL_TYPE = #PANEL_TYPES + 1
for index, panelType in ipairs(PANEL_TYPES) do
    local parent = panelType.parentMode and PANEL_TYPE_BY_MODE[panelType.parentMode]
    if not (panelType.primary or (parent and parent.primary)) then
        FIRST_SPECIALIST_PANEL_TYPE = index
        break
    end
end

local function GetPanelTypeInfo(displayMode)
    return PANEL_TYPE_BY_MODE[displayMode] or PANEL_TYPE_BY_MODE.icons
end

-- Menu indent for a subtype row, in the same pixels the entry-move menu already
-- indents its nested rows by, so the two menus read alike.
local PANEL_TYPE_SUBTYPE_INDENT = 10

local function ApplyPanelTypeMenuIndent(info, panelType)
    info.leftPadding = panelType and panelType.parentMode
        and PANEL_TYPE_SUBTYPE_INDENT or nil
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

    -- Same rule as the empty-section delete above: previews are keyed by
    -- entry position, so a replacement entry must not inherit the simulated
    -- state of whatever used to sit at its index.
    CooldownCompanion:ClearAllConfigPreviews()
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

    if CooldownCompanion.EnableTexturePanelAuraDisplayForEntry then
        CooldownCompanion:EnableTexturePanelAuraDisplayForEntry(targetGroup, entryData)
    end
    local previousCount = #targetGroup.buttons
    -- A section placement belongs to the panel it was made on: an entry landing
    -- here starts in the base row rather than joining whatever section this
    -- panel keeps at the anchor it used to name, and the cluster it left goes
    -- with it when it was the last member there.
    ST.DetachEntryFromPanelSection(db.groups[sourceGroupId], entryData)
    -- After the detach, so the key rule reads the membership the entry actually
    -- lands with. An entry arriving in a panel needs that panel's own key, not
    -- the one it wore where it came from: an Aura Panel mints it one, and
    -- anywhere else the stale key comes off rather than waiting to collide
    -- inside an aura section.
    CooldownCompanion:AdoptAuraEntryKey(targetGroup, entryData)
    table.insert(targetGroup.buttons, entryData)
    table.remove(db.groups[sourceGroupId].buttons, sourceIndex)
    CooldownCompanion:KeepPanelSingleLineOnGrowth(targetGroup, previousCount)
    CooldownCompanion:RefreshGroupFrame(targetGroupId)
    CooldownCompanion:RefreshGroupFrame(sourceGroupId)
    CooldownCompanion:ClearAllConfigPreviews()
    CS.selectedButton = nil
    CS.selectedRotationAssistantEntry = nil
    wipe(CS.selectedButtons)
    CooldownCompanion:RefreshConfigPanel()
    return true
end

-- An Aura Panel judges the ENTRY, not just the panel: it takes aura entries
-- only, and only for the one unit it derived from its first entry.
-- CanPanelAcceptManualEntry is entry-blind, so without this every Aura Panel
-- listed as a destination for every entry and only refused after the click.
-- Scoped to Aura Panel destinations alone - the other panel types' menu
-- membership is unchanged, refusals included.
local function IsAuraPanelMoveDestination(group, entryData)
    if not CooldownCompanion:IsAuraPanel(group) then
        return true
    end
    return entryData ~= nil
        and CooldownCompanion:GetPanelManualEntryRejectMessage(group, entryData) == nil
end

local function BuildEntryMoveDestinationSections(db, sourceGroupId, entryData, acceptsDestination)
    local containers = db and db.groupContainers or {}
    local groupedByContainer = {}

    for groupId, group in pairs(db.groups or {}) do
        if groupId ~= sourceGroupId
            and CanMoveEntryToGroup(sourceGroupId, groupId)
            and CooldownCompanion:CanPanelAcceptManualEntry(group)
            and IsAuraPanelMoveDestination(group, entryData)
            and (not acceptsDestination or acceptsDestination(groupId, group))
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
    local sections = BuildEntryMoveDestinationSections(db, sourceGroupId, entryData)

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

-- The copyable customizations an entry carries, in the same order and
-- vocabulary as the Customizations index and the entry hover tooltip: Text
-- Format first, then sections in registry order, plus "All Customizations"
-- when there is more than one. Stranded/inactive customizations count -
-- only the TARGET side gates whether a copy can land. The context menu's
-- "Copy Customization To..." row and its submenu both build from this
-- collection, so the arrow can never open an empty flyout (a stored
-- section id the registry no longer knows is skipped in both places).
local function CollectCopyCustomizationItems(entryData)
    local items = {}
    if entryData.textFormat ~= nil then
        items[#items + 1] = { scope = "format", label = "Text Format" }
    end
    local sections = entryData.overrideSections or {}
    for _, sectionId in ipairs(ST.OVERRIDE_SECTION_ORDER or {}) do
        if sections[sectionId] then
            local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
            if sectionDef then
                items[#items + 1] = { scope = "section", sectionId = sectionId, label = sectionDef.label }
            end
        end
    end
    if #items >= 2 then
        items[#items + 1] = { scope = "all", label = "All Customizations" }
    end
    return items
end

-- Picking a row arms the click-an-entry copy mode in the panel preview.
local function AddCopyCustomizationButtons(level, sourceGroupId, sourceIndex, entryData)
    for _, item in ipairs(CollectCopyCustomizationItems(entryData)) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = item.label
        info.notCheckable = true
        info.func = function()
            CloseDropDownMenus()
            if ST._ArmCopyCustomization then
                ST._ArmCopyCustomization(sourceGroupId, sourceIndex, entryData,
                    item.scope, item.sectionId)
            end
        end
        UIDropDownMenu_AddButton(info, level)
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
            local sourceGroup = CooldownCompanion.db.profile.groups[sourceGroupId]

            -- A text panel IS its format string, so the editor that owns it
            -- leads the menu. The editor is config surface now rather than a
            -- popout, and the panel's Format tab is a LENS onto the selected
            -- entry, so there is one destination for every entry: select it,
            -- keep the surface on the panel tabs, and open Format.
            if sourceGroup and sourceGroup.displayMode == "text" then
                local formatInfo = UIDropDownMenu_CreateInfo()
                formatInfo.text = "Edit Format..."
                formatInfo.notCheckable = true
                formatInfo.func = function()
                    CloseDropDownMenus()
                    -- The menu can be opened on a panel that is not the
                    -- selected one; move the selection there first so the
                    -- container crumb follows too.
                    if CS.selectedGroup ~= sourceGroupId then
                        SelectConfigPanel(sourceGroupId, {
                            containerId = sourceGroup.parentContainerId,
                        })
                    end
                    -- force: this names an entry, so it must end selected even
                    -- if clicking it would normally toggle the selection off.
                    -- scope "primary": the panel tabs keep the surface, which
                    -- is where the format editor now lives.
                    if SelectConfigButton then
                        SelectConfigButton(sourceGroupId, sourceIndex, { force = true, scope = "primary" })
                    end
                    CS.selectedTab = "format"
                    CS.panelSettingsTab = "format"
                    -- A deliberate destination, so it outranks a display
                    -- mode's own default landing tab.
                    CS.panelSettingsTabExplicit = true
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(formatInfo, level)
            end

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

            if not (sourceGroup and sourceGroup.displayMode == "textures") then
                local dupInfo = UIDropDownMenu_CreateInfo()
                dupInfo.text = "Duplicate"
                dupInfo.notCheckable = true
                dupInfo.func = function()
                    local liveGroup = CooldownCompanion.db.profile.groups[sourceGroupId]
                    local copy = CopyTable(entryData)
                    -- The copy inherits the original's aura key, which would
                    -- put two entries in the same panel on one aura group. It
                    -- also inherits the original's SECTION, so on a mixed panel
                    -- the copy is handed a key of its own rather than merely
                    -- stripped.
                    CooldownCompanion:AdoptAuraEntryKey(liveGroup, copy)
                    table.insert(liveGroup.buttons, sourceIndex + 1, copy)
                    -- Follow the copy without changing the active panel/entry
                    -- scope; the shared path also clears stale index state.
                    SelectConfigButton(sourceGroupId, sourceIndex + 1, { force = true })
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

            -- No source-side display-mode gate: even a texture panel's entry
            -- can carry stranded customizations worth copying out, and the
            -- copy mode's target eligibility does all the real gating.
            if #CollectCopyCustomizationItems(entryData) > 0 then
                local copyInfo = UIDropDownMenu_CreateInfo()
                copyInfo.text = "Copy Customization To..."
                copyInfo.notCheckable = true
                copyInfo.hasArrow = true
                copyInfo.menuList = "COPY_CUSTOMIZATION"
                copyInfo.tooltipTitle = "|cffffd100Copy Customization|r"
                copyInfo.tooltipText = "|cffffffffPick a customization, then click the entry it should apply to.|r"
                copyInfo.tooltipOnButton = true
                UIDropDownMenu_AddButton(copyInfo, level)
            end

            -- Red "Delete" behind the confirmation popup, the same way every
            -- other destructive menu item in the config reads.
            local deleteInfo = UIDropDownMenu_CreateInfo()
            deleteInfo.text = "|cffff4444Delete|r"
            deleteInfo.notCheckable = true
            deleteInfo.func = function()
                CloseDropDownMenus()
                -- The same resolver the entry row uses (customName first,
                -- then the CDM/override display spell). The confirmation now
                -- carries the name as the whole identity of what is about to
                -- be destroyed, so the raw stored name would show a renamed
                -- entry under its old name and an unnamed one as "this entry"
                -- while its own row names it correctly.
                local name = (ST._GetConfigEntryDisplayName
                    and ST._GetConfigEntryDisplayName(entryData))
                    or entryData.name
                    or "this entry"
                ShowPopupAboveConfig("CDC_DELETE_BUTTON", name, { groupId = sourceGroupId, buttonIndex = sourceIndex })
            end
            UIDropDownMenu_AddButton(deleteInfo, level)
        elseif menuList == "COPY_CUSTOMIZATION" then
            AddCopyCustomizationButtons(level, sourceGroupId, sourceIndex, entryData)
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
-- Single- and multi-entry move menus share one Group -> Panel hierarchy. The
-- optional predicate lets batch moves retain their stricter whole-selection
-- capacity checks without duplicating destination names or ordering.
ST._BuildEntryMoveDestinationSections = BuildEntryMoveDestinationSections
ST._AddPanelTypeMenuTooltip = AddPanelTypeMenuTooltip
ST._ApplyPanelTypeMenuIndent = ApplyPanelTypeMenuIndent
ST._AddCDMStarterMenuTooltip = AddCDMStarterMenuTooltip
-- Ordered creatable panel types, shared by every panel-create surface.
ST._PANEL_TYPES = PANEL_TYPES
-- Where the specialist block starts, so every create menu draws its separator
-- in the same place without re-deriving the split.
ST._FIRST_SPECIALIST_PANEL_TYPE = FIRST_SPECIALIST_PANEL_TYPE
-- Shared create accent, so no surface hand-writes its own cyan.
ST._CREATE_ACCENT = CREATE_ACCENT
ST._BuildPanelCreateOptions = BuildPanelCreateOptions
ST._CreatePanelInSelectedContainer = CreatePanelInSelectedContainer
ST._CreateMissingCDMPanelsInSelectedContainer = CreateMissingCDMPanelsInSelectedContainer
-- Shared with the panel preview mirror: entry tooltips resolve the
-- currently-active override spell, not the stored base ID.
ST._ResolveEntryTooltipSpellId = ResolveEntryTooltipSpellId
