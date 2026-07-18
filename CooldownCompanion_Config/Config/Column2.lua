--[[
    CooldownCompanion - Config/Column2
    RefreshColumn2.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local RB = ST._RB
local RESOURCE_HEALTH = RB and RB.RESOURCE_HEALTH or -1

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local CleanRecycledEntry = ST._CleanRecycledEntry
local ApplyConfigRowIcon = ST._ApplyConfigRowIcon
local ApplyConfigTextRow = ST._ApplyConfigTextRow
local GetButtonIcon = ST._GetButtonIcon
local GetConfigEntryDisplayName = ST._GetConfigEntryDisplayName
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local CompactUntitledInlineGroupConfig = ST._CompactUntitledInlineGroupConfig
local CancelDrag = ST._CancelDrag
local StartDragTracking = ST._StartDragTracking
local ClearCol2AnimatedPreview = ST._ClearCol2AnimatedPreview
local GetScaledCursorPosition = ST._GetScaledCursorPosition
local TryAdd = ST._TryAdd
local TryReceiveCursorDrop = ST._TryReceiveCursorDrop
local OnAutocompleteSelect = ST._OnAutocompleteSelect
local SearchAutocomplete = ST._SearchAutocomplete
local ResolveViewerChildForSpellDisplay = ST.ResolveViewerChildForSpellDisplay
local BuildGroupExportData = ST._BuildGroupExportData
local BuildContainerExportData = ST._BuildContainerExportData
local EncodeExportData = ST._EncodeExportData
local BuildEligibilityBadgeMap = ST._BuildEligibilityBadgeMap
local BindConfigShiftTooltip = ST._BindConfigShiftTooltip
local NotifyTutorialAction = ST._NotifyTutorialAction
local PerformButtonReorder = ST._PerformButtonReorder
local IsConfigFinderActive = ST._IsConfigFinderActive
local BuildConfigFinderResults = ST._BuildConfigFinderResults
local SelectConfigFinderResult = ST._SelectConfigFinderResult
local SelectConfigPanel = ST._SelectConfigPanel
local ToggleConfigPanelMultiSelect = ST._ToggleConfigPanelMultiSelect
local SelectConfigButton = ST._SelectConfigButton
local SelectConfigButtonPanel = ST._SelectConfigButtonPanel
local SelectConfigRotationAssistantEntry = ST._SelectConfigRotationAssistantEntry
local ClearConfigButtonSelection = ST._ClearConfigButtonSelection
local ClearConfigPanelSelection = ST._ClearConfigPanelSelection
local BuildCDMPanelSourceData = ST._BuildCDMPanelSourceData
local GetCDMPanelSourceData = ST._GetCDMPanelSourceData
local PopulateCDMPanelFromSource = ST._PopulateCDMPanelFromSource
local ApplyCDMStarterPanelLayout = ST._ApplyCDMStarterPanelLayout
local IsCDMPanelSourceKey = ST._IsCDMPanelSourceKey
local GetCDMPanelSourceDisplayMode = ST._GetCDMPanelSourceDisplayMode

local IsTriggerPanelGroup
local RefreshCDMPanelFromSource

local function IsContainerVisibleInConfig(containerOrContainerId)
    if CooldownCompanion.ResolveContainerClassScope then
        local scope = CooldownCompanion:ResolveContainerClassScope(containerOrContainerId)
        return scope.isInvalid ~= true
    end
    return CooldownCompanion:IsContainerVisibleToCurrentChar(containerOrContainerId)
end

local function CanPanelMoveToContainer(panelId, containerId)
    if not IsContainerVisibleInConfig(containerId) then
        return false
    end
    if CooldownCompanion.CanMovePanelToContainer then
        local ok = CooldownCompanion:CanMovePanelToContainer(panelId, containerId)
        return ok == true
    end
    return true
end

local function CanMoveEntryToGroup(sourceGroupId, targetGroupId)
    if CooldownCompanion.CanMoveEntryToGroup then
        return CooldownCompanion:CanMoveEntryToGroup(sourceGroupId, targetGroupId) == true
    end
    return CooldownCompanion:IsGroupVisibleToCurrentChar(targetGroupId)
end

local function CanAllContainersMoveToFolder(containerIds, folderId)
    if not CooldownCompanion.CanMoveContainerToFolder then
        return true
    end
    for _, containerId in ipairs(containerIds or {}) do
        local ok = CooldownCompanion:CanMoveContainerToFolder(containerId, folderId)
        if not ok then
            return false
        end
    end
    return true
end

local function OpenPanelLoadConditions(panelId, containerId)
    SelectConfigPanel(panelId, { containerId = containerId })
    CS.selectedTab = "loadconditions"
    CS.panelSettingsTab = "loadconditions"
    CooldownCompanion:RefreshConfigPanel()
end

local tonumber = tonumber
local ipairs = ipairs

local ROW_BADGE_SIZE = 16
local OVERRIDE_BADGE_ICON_SIZE = 12
local ROW_BADGE_SPACING = 2
local ROW_BADGE_RIGHT_PAD = 4
local TEXTURE_PANEL_HEADER_BADGE_ATLAS = "UI-HUD-MicroMenu-Communities-Icon-Notification"
local CURSOR_PANEL_HEADER_BADGE_ATLAS = "cursor_cast_32"
local CDM_PANEL_HEADER_BADGE_ATLAS = "common-icon-rotateleft"
local PANEL_HEADER_TYPE_BADGE_GAP = 2
local TRIGGER_PANEL_BADGE_COLOR = { 1.0, 0.18, 0.78 }
local PANEL_TYPE_TOOLTIPS = {
    icons = {
        title = "Icon Panel",
        description = "Shows spells or items as classic cooldown icons.",
    },
    bars = {
        title = "Bar Panel",
        description = "Shows spells or items as timer bars with names and durations.",
    },
    text = {
        title = "Text Panel",
        description = "Shows text-only entries for compact readouts and status lists.",
    },
    textures = {
        title = "Texture Panel",
        description = "Shows one standalone texture for a single spell or item.",
    },
    trigger = {
        title = "Trigger Panel",
        description = "Add spell or item entries, then set conditions on each one. The display appears only when every enabled entry meets its conditions.",
    },
    rotationAssistant = {
        title = "Assistant Panel",
        description = "Shows one locked recommendation icon from the in-game assistant.",
    },
}

local function GetPanelTypeTooltip(displayMode)
    return PANEL_TYPE_TOOLTIPS[displayMode] or PANEL_TYPE_TOOLTIPS.icons
end

local function ShowPanelTypeTooltip(owner, displayMode)
    local tooltip = GetPanelTypeTooltip(displayMode)
    if not tooltip then
        return
    end

    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine(tooltip.title, 1, 0.82, 0, true)
    GameTooltip:AddLine(tooltip.description, 1, 1, 1, true)
    GameTooltip:Show()
end

local function AddPanelTypeMenuTooltip(info, displayMode)
    local tooltip = GetPanelTypeTooltip(displayMode)
    if not tooltip then
        return
    end

    info.tooltipTitle = tooltip.title
    info.tooltipText = tooltip.description
    info.tooltipOnButton = true
end

local function ShowCDMStarterTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine("Build from Cooldown Manager", 1, 0.82, 0, true)
    GameTooltip:AddLine("Creates editable panels from displayed Essential, Utility, Tracked Buffs, and Tracked Bars sections.", 1, 1, 1, true)
    GameTooltip:Show()
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

local function GetPanelTypeBadgeAtlas(displayMode)
    if displayMode == "bars" then
        return "CreditsScreen-Assets-Buttons-Pause"
    elseif displayMode == "text" then
        return "poi-workorders"
    elseif displayMode == "textures" or displayMode == "trigger" then
        return TEXTURE_PANEL_HEADER_BADGE_ATLAS
    end

    return "UI-QuestPoi-QuestNumber-SuperTracked"
end

local function BuildPanelHeaderText(panel, panelId, buttonCount, countColor)
    local panelName = panel and panel.name
    if not panelName or panelName == "" then
        panelName = panelId and ("Panel " .. tostring(panelId)) or "Panel"
    end

    return panelName .. " |cff" .. (countColor or "666666") .. "(" ..
        tostring(buttonCount or 0) .. ")|r"
end

local function GetConfigPanelButtonCount(panel)
    if panel and panel.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
        return 1
    end
    return panel and panel.buttons and #panel.buttons or 0
end

local function EnsurePanelTypeTooltipTarget(header)
    local target = header._cdcModeBadgeHitRect
    if not target then
        target = CreateFrame("Button", nil, header.frame)
        target:SetSize(18, 18)
        target:SetPropagateMouseClicks(true)
        target:SetPropagateMouseMotion(true)
        target:SetScript("OnEnter", function(self)
            ShowPanelTypeTooltip(self, self._cdcDisplayMode)
        end)
        target:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        header._cdcModeBadgeHitRect = target
    end

    target:SetFrameStrata(header.frame:GetFrameStrata())
    target:SetFrameLevel(header.frame:GetFrameLevel() + 20)
    return target
end

local function TrimPanelName(name)
    if name == nil then return "" end
    return tostring(name):match("^%s*(.-)%s*$") or ""
end

local function IsGenericPanelName(name)
    local trimmed = TrimPanelName(name)
    return trimmed == "" or trimmed == "Panel" or trimmed:match("^Panel%s+%d+$") ~= nil
end

local function EnsureGenericRenameBadge(header)
    local badge = header.frame._cdcGenericRenameBadge
    if not badge then
        badge = CreateFrame("Button", nil, header.frame)
        badge:SetSize(14, 14)
        badge:SetPropagateMouseClicks(false)
        badge:SetPropagateMouseMotion(false)
        badge.icon = badge:CreateTexture(nil, "OVERLAY")
        badge.icon:SetAllPoints()
        badge:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Default name. Click to rename.", 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        header.frame._cdcGenericRenameBadge = badge
    end

    badge:SetFrameLevel(header.frame:GetFrameLevel() + 25)
    return badge
end

local function ConfigureGenericRenameBadge(header, panel, panelId, rightOffset)
    local badge = EnsureGenericRenameBadge(header)
    badge:ClearAllPoints()
    badge:SetScript("OnClick", nil)

    if not IsGenericPanelName(panel and panel.name) then
        badge:Hide()
        return rightOffset
    end

    local currentName = TrimPanelName(panel and panel.name)
    if currentName == "" then
        currentName = "Panel " .. tostring(panelId)
    end

    badge.icon:SetAtlas("QuestLegendary", false)
    badge.icon:SetVertexColor(1, 0.82, 0, 0.85)
    badge:SetPoint("LEFT", header.label, "CENTER", rightOffset, 0)
    badge:SetScript("OnClick", function(_, button)
        if button ~= "LeftButton" then return end
        GameTooltip:Hide()
        ShowPopupAboveConfig("CDC_RENAME_GROUP", currentName, { groupId = panelId })
    end)
    badge:Show()

    return rightOffset + 18
end

local function ConfigureCursorAnchorBadge(header, panel)
    local badge = header.frame._cdcCursorAnchorBadge
    if not badge then
        badge = CreateFrame("Button", nil, header.frame)
        badge:SetPropagateMouseClicks(true)
        badge:SetPropagateMouseMotion(true)
        badge.icon = badge:CreateTexture(nil, "OVERLAY")
        badge.icon:SetAllPoints()
        badge:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Cursor Anchored", 1, 0.82, 0, true)
            GameTooltip:AddLine("This panel is anchored to the cursor.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        header.frame._cdcCursorAnchorBadge = badge
    end

    badge:SetFrameLevel(header.frame:GetFrameLevel() + 25)
    badge:SetSize(16, 16)
    badge:ClearAllPoints()

    if panel
        and panel.parentContainerId
        and CooldownCompanion.IsGroupCursorAnchored
        and CooldownCompanion:IsGroupCursorAnchored(panel) then
        badge:SetPoint("LEFT", header.frame, "LEFT", 4, 0)
        badge.icon:SetAtlas(CURSOR_PANEL_HEADER_BADGE_ATLAS, false)
        if badge.icon.SetDesaturated then
            badge.icon:SetDesaturated(false)
        end
        badge.icon:SetVertexColor(1, 1, 1, 1)
        badge:Show()
        return
    end

    badge:Hide()
end

local function ConfigureCDMRefreshBadge(header, panel, panelId, containerId, cursorBadgeShown)
    local badge = header.frame._cdcCDMRefreshBadge
    if not badge then
        badge = CreateFrame("Button", nil, header.frame)
        badge:SetSize(16, 16)
        badge:RegisterForClicks("LeftButtonUp")
        badge:SetPropagateMouseClicks(false)
        badge:SetPropagateMouseMotion(false)
        badge.icon = badge:CreateTexture(nil, "OVERLAY")
        badge.icon:SetAllPoints()
        badge:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Refresh from Cooldown Manager", 1, 0.82, 0, true)
            GameTooltip:AddLine("Replace this panel's entries from its linked CDM section.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        header.frame._cdcCDMRefreshBadge = badge
    end

    badge:SetFrameLevel(header.frame:GetFrameLevel() + 25)
    badge:SetSize(16, 16)
    badge:ClearAllPoints()

    if not IsActiveCDMPanelSource(panel) then
        badge:Hide()
        badge:SetScript("OnClick", nil)
        return
    end

    local leftOffset = 4
    if cursorBadgeShown then
        leftOffset = leftOffset + ROW_BADGE_SIZE + ROW_BADGE_SPACING
    end
    badge:SetPoint("LEFT", header.frame, "LEFT", leftOffset, 0)
    badge.icon:SetAtlas(CDM_PANEL_HEADER_BADGE_ATLAS, false)
    badge.icon:SetVertexColor(0.35, 0.8, 1, 0.95)
    if badge.icon.SetDesaturated then
        badge.icon:SetDesaturated(false)
    end
    badge:SetScript("OnClick", function(_, button)
        if button ~= "LeftButton" then return end
        GameTooltip:Hide()
        RefreshCDMPanelFromSource(panelId, panel, containerId)
    end)
    badge:Show()
end

local function ConfigurePanelTypeBadge(header, displayMode, textWidth)
    local modeBadge = header._cdcModeBadge
    if not modeBadge then
        modeBadge = header.frame:CreateTexture(nil, "ARTWORK")
        header._cdcModeBadge = modeBadge
    end

    modeBadge:ClearAllPoints()
    modeBadge:SetSize(ROW_BADGE_SIZE, ROW_BADGE_SIZE)
    if modeBadge.SetDesaturated then
        modeBadge:SetDesaturated(false)
    end
    modeBadge:SetVertexColor(1, 1, 1, 1)
    if displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
        modeBadge:SetTexture(CooldownCompanion:GetRotationAssistantFallbackIcon())
        modeBadge:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        modeBadge:SetAtlas(GetPanelTypeBadgeAtlas(displayMode), false)
        modeBadge:SetTexCoord(0, 1, 0, 1)
    end
    if displayMode == "trigger" then
        if modeBadge.SetDesaturated then
            modeBadge:SetDesaturated(true)
        end
        modeBadge:SetVertexColor(TRIGGER_PANEL_BADGE_COLOR[1], TRIGGER_PANEL_BADGE_COLOR[2], TRIGGER_PANEL_BADGE_COLOR[3], 1)
    end
    modeBadge:SetPoint("RIGHT", header.label, "CENTER", -(textWidth / 2) - PANEL_HEADER_TYPE_BADGE_GAP, 0)
    modeBadge:Show()

    local tooltipTarget = EnsurePanelTypeTooltipTarget(header)
    tooltipTarget._cdcDisplayMode = displayMode
    tooltipTarget:ClearAllPoints()
    tooltipTarget:SetPoint("CENTER", modeBadge, "CENTER")
    tooltipTarget:Show()
end

local function AddClassAccentSpacer(scroll, classColor)
    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    spacer:SetHeight(2)
    local accentBar = spacer.frame._cdcAccentBar
    if not accentBar then
        accentBar = spacer.frame:CreateTexture(nil, "ARTWORK")
        spacer.frame._cdcAccentBar = accentBar
    end
    accentBar:SetHeight(1.5)
    accentBar:ClearAllPoints()
    local inset = math.floor(spacer.frame:GetWidth() * 0.10 + 0.5)
    accentBar:SetPoint("LEFT", spacer.frame, "LEFT", inset, 1)
    accentBar:SetPoint("RIGHT", spacer.frame, "RIGHT", -inset, 1)
    if classColor then
        accentBar:SetColorTexture(classColor.r, classColor.g, classColor.b, 0.8)
    else
        accentBar:SetColorTexture(1, 1, 1, 0.3)
    end
    accentBar:Show()
    spacer:SetCallback("OnRelease", function() accentBar:Hide() end)
    scroll:AddChild(spacer)
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

    SelectConfigPanel(newPanelId)
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

local function CreatePanelInSelectedContainer(displayMode, opts)
    local newPanelId = CooldownCompanion:CreatePanel(CS.selectedContainer, displayMode)
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

local function CreateMissingCDMPanelsInSelectedContainer()
    local containerId = CS.selectedContainer
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

local function EnsureCol2PanelTypeMenu()
    if not CS.col2PanelTypeMenu then
        CS.col2PanelTypeMenu = CreateFrame("Frame", "CDCCol2PanelTypeMenu", UIParent, "UIDropDownMenuTemplate")
    end
    return CS.col2PanelTypeMenu
end

local function PopulateCol2PanelCreationBar(panelBtnWidth)
    if not CS.col2ButtonBar then
        return
    end

    local function CreateButton(text, onClick, tooltipMode, anchorPoint, relativeTo)
        local button = AceGUI:Create("Button")
        button:SetText(text)
        button:SetCallback("OnClick", onClick)
        if tooltipMode then
            button:SetCallback("OnEnter", function(widget)
                ShowPanelTypeTooltip(widget.frame, tooltipMode)
            end)
            button:SetCallback("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
        button.frame:SetParent(CS.col2ButtonBar)
        button.frame:ClearAllPoints()
        button.frame:SetPoint(anchorPoint, relativeTo, anchorPoint == "TOPLEFT" and "TOPLEFT" or "RIGHT", anchorPoint == "TOPLEFT" and 0 or 3, anchorPoint == "TOPLEFT" and -1 or 0)
        button.frame:SetWidth(panelBtnWidth)
        button.frame:SetHeight(28)
        button.frame:Show()
        table.insert(CS.col2BarWidgets, button)
        return button
    end

    local iconPanelBtn = CreateButton(
        "Icon Panel",
        function()
            CreatePanelInSelectedContainer("icons", {
                notifyTutorial = true,
            })
        end,
        "icons",
        "TOPLEFT",
        CS.col2ButtonBar
    )
    if CS.tutorialAnchors then
        CS.tutorialAnchors.icon_panel_button = iconPanelBtn.frame
    end

    local barPanelBtn = CreateButton(
        "Bar Panel",
        function()
            CreatePanelInSelectedContainer("bars", {
                verticalStyle = true,
            })
        end,
        "bars",
        "LEFT",
        iconPanelBtn.frame
    )

    local otherPanelBtn = AceGUI:Create("Button")
    otherPanelBtn:SetText("More")
    otherPanelBtn:SetCallback("OnClick", function()
        local menu = EnsureCol2PanelTypeMenu()
        UIDropDownMenu_Initialize(menu, function(self, level)
            level = level or 1
            if level ~= 1 then return end

            local info = UIDropDownMenu_CreateInfo()
            info.text = "Text Panel"
            info.notCheckable = true
            AddPanelTypeMenuTooltip(info, "text")
            info.func = function()
                CloseDropDownMenus()
                CreatePanelInSelectedContainer("text", {
                    verticalStyle = true,
                })
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = "Texture Panel"
            info.notCheckable = true
            AddPanelTypeMenuTooltip(info, "textures")
            info.func = function()
                CloseDropDownMenus()
                CreatePanelInSelectedContainer("textures")
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = "Trigger Panel"
            info.notCheckable = true
            AddPanelTypeMenuTooltip(info, "trigger")
            info.func = function()
                CloseDropDownMenus()
                CreatePanelInSelectedContainer("trigger")
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = "Assistant Panel"
            info.notCheckable = true
            AddPanelTypeMenuTooltip(info, "rotationAssistant")
            info.func = function()
                CloseDropDownMenus()
                CreatePanelInSelectedContainer(ST.DISPLAY_MODE_ROTATION_ASSISTANT)
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = "Add Missing CDM Panels"
            info.notCheckable = true
            AddCDMStarterMenuTooltip(info)
            info.func = function()
                CloseDropDownMenus()
                CreateMissingCDMPanelsInSelectedContainer()
            end
            UIDropDownMenu_AddButton(info, level)
        end, "MENU")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        ToggleDropDownMenu(1, nil, menu, "cursor", 0, 0)
    end)
    otherPanelBtn.frame:SetParent(CS.col2ButtonBar)
    otherPanelBtn.frame:ClearAllPoints()
    otherPanelBtn.frame:SetPoint("LEFT", barPanelBtn.frame, "RIGHT", 3, 0)
    otherPanelBtn.frame:SetWidth(panelBtnWidth)
    otherPanelBtn.frame:SetHeight(28)
    otherPanelBtn.frame:Show()
    table.insert(CS.col2BarWidgets, otherPanelBtn)

    CS.col2ButtonBar._topRowBtns = {
        iconPanelBtn.frame,
        barPanelBtn.frame,
        otherPanelBtn.frame,
    }
    CS.col2ButtonBar:SetScript("OnSizeChanged", function(self, w)
        if self._topRowBtns then
            local tw = (w - 6) / 3
            for _, frame in ipairs(self._topRowBtns) do
                frame:SetWidth(tw)
            end
        end
    end)
end

local function RenderColumn2NoPanelsState(classColor)
    local function AddFixedSpacer(height)
        local spacer = AceGUI:Create("SimpleGroup")
        spacer:SetFullWidth(true)
        spacer:SetHeight(height)
        spacer.noAutoHeight = true
        CS.col2Scroll:AddChild(spacer)
    end

    AddFixedSpacer(20)

    local header = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(header)
    header:SetText("Every entry needs a panel.")
    header:SetFullWidth(true)
    header:SetJustifyH("CENTER")
    header:SetFont((GameFontNormal:GetFont()), 15, "")
    CS.col2Scroll:AddChild(header)

    AddFixedSpacer(6)

    local desc = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(desc)
    desc:SetText("Choose a panel type below to get started.")
    desc:SetFullWidth(true)
    desc:SetJustifyH("CENTER")
    desc:SetFont((GameFontNormal:GetFont()), 12, "")
    desc:SetColor(0.7, 0.7, 0.7)
    CS.col2Scroll:AddChild(desc)

    AddFixedSpacer(18)

    AddClassAccentSpacer(CS.col2Scroll, classColor)

    AddFixedSpacer(10)

    local helpEntries = {
        PANEL_TYPE_TOOLTIPS.icons,
        PANEL_TYPE_TOOLTIPS.bars,
        PANEL_TYPE_TOOLTIPS.text,
        PANEL_TYPE_TOOLTIPS.textures,
        PANEL_TYPE_TOOLTIPS.trigger,
        PANEL_TYPE_TOOLTIPS.rotationAssistant,
    }

    local lastHelpFrame
    for index, entry in ipairs(helpEntries) do
        if index > 1 then
            AddFixedSpacer(8)
        end

        local panelHelp = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(panelHelp)
        panelHelp:SetText("|cffffffff" .. entry.title .. "|r - " .. entry.description)
        panelHelp:SetFullWidth(true)
        panelHelp:SetJustifyH("CENTER")
        panelHelp:SetFont((GameFontNormal:GetFont()), 12, "")
        panelHelp:SetColor(0.75, 0.75, 0.75)
        CS.col2Scroll:AddChild(panelHelp)
        lastHelpFrame = panelHelp.frame
    end

    CS.col2Scroll:DoLayout()

    local visibleHeight = CS.col2Scroll.frame and CS.col2Scroll.frame:GetHeight() or 0
    local scrollTop = CS.col2Scroll.frame and CS.col2Scroll.frame:GetTop()
    local lastHelpBottom = lastHelpFrame and lastHelpFrame:GetBottom()
    local contentHeight = 0
    if scrollTop and lastHelpBottom then
        contentHeight = math.max(0, scrollTop - lastHelpBottom)
    end
    if contentHeight <= 0 then
        local contentState = CS.col2Scroll.status or CS.col2Scroll.localstatus
        contentHeight = tonumber(contentState and contentState.contentHeight)
            or tonumber(contentState and contentState.contentheight)
            or (CS.col2Scroll.content and CS.col2Scroll.content:GetHeight())
            or 0
    end
    local ctaHeight = 62
    local ctaSpacerHeight = 18
    if visibleHeight > 0 and contentHeight > 0 then
        local remainingHeight = visibleHeight - contentHeight - ctaHeight
        if remainingHeight > 0 then
            ctaSpacerHeight = math.max(ctaSpacerHeight, math.floor((remainingHeight / 2) + 0.5))
        end
    end
    AddFixedSpacer(ctaSpacerHeight)

    local cdmIntro = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(cdmIntro)
    cdmIntro:SetText("Alternatively, automatically create panels based on what is in your CDM.")
    cdmIntro:SetFullWidth(true)
    cdmIntro:SetJustifyH("CENTER")
    cdmIntro:SetFont((GameFontNormal:GetFont()), 12, "")
    cdmIntro:SetColor(0.85, 0.85, 0.85)
    CS.col2Scroll:AddChild(cdmIntro)

    AddFixedSpacer(6)

    local cdmButtonRow = AceGUI:Create("SimpleGroup")
    cdmButtonRow:SetFullWidth(true)
    cdmButtonRow:SetLayout("Flow")

    local leftSpacer = AceGUI:Create("Label")
    leftSpacer:SetText("")
    leftSpacer:SetRelativeWidth(0.15)
    cdmButtonRow:AddChild(leftSpacer)

    local cdmButton = AceGUI:Create("Button")
    cdmButton:SetText("Build from Cooldown Manager")
    cdmButton:SetRelativeWidth(0.70)
    cdmButton:SetCallback("OnClick", function()
        CreateMissingCDMPanelsInSelectedContainer()
    end)
    cdmButton:SetCallback("OnEnter", function(widget)
        ShowCDMStarterTooltip(widget.frame)
    end)
    cdmButton:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
    cdmButtonRow:AddChild(cdmButton)

    local rightSpacer = AceGUI:Create("Label")
    rightSpacer:SetText("")
    rightSpacer:SetRelativeWidth(0.15)
    cdmButtonRow:AddChild(rightSpacer)

    CS.col2Scroll:AddChild(cdmButtonRow)

    CS.col2Scroll:DoLayout()
end

local function RenderConfigFinderResults()
    if CS.col2ButtonBar then CS.col2ButtonBar:Hide() end
    CS.col2Scroll.frame:SetPoint("BOTTOMRIGHT", CS.col2Scroll.frame:GetParent(), "BOTTOMRIGHT", 0, 0)
    CS.lastCol2RenderedRows = {}
    CS.lastCol2PanelMetas = {}

    local results = BuildConfigFinderResults and BuildConfigFinderResults()
    if not results or #results.panelResults == 0 then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("|cff888888No matching panels or entries.|r")
        label:SetFullWidth(true)
        CS.col2Scroll:AddChild(label)
        return
    end

    if results.truncated then
        local summary = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(summary)
        summary:SetText(("|cff888888Showing %d of %d matching panels and %d of %d matching entries. Keep typing to narrow results.|r"):format(
            #results.panelResults,
            results.totalPanelResults or #results.panelResults,
            results.renderedEntryResults or 0,
            results.totalEntryResults or 0
        ))
        summary:SetFullWidth(true)
        CS.col2Scroll:AddChild(summary)
    end

    local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))

    for resultIndex, result in ipairs(results.panelResults) do
        local panel = result.panel
        local panelId = result.panelId
        local containerId = result.containerId
        local container = result.container

        if resultIndex > 1 then
            AddClassAccentSpacer(CS.col2Scroll, cc)
        end

        local panelContainer = AceGUI:Create("InlineGroup")
        panelContainer:SetTitle("")
        panelContainer:SetLayout("List")
        panelContainer:SetFullWidth(true)
        CompactUntitledInlineGroupConfig(panelContainer)
        CS.col2Scroll:AddChild(panelContainer)

        local panelName = panel and panel.name or ("Panel " .. tostring(panelId))
        local groupName = container and container.name or "Group"
        local headerText = groupName .. "  |cff666666/|r  " .. panelName

        local header = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(header)
        header:SetText(headerText)
        header:SetFullWidth(true)
        header:SetFontObject(GameFontHighlight)
        header:SetJustifyH("CENTER")
        ApplyConfigTextRow(header, "CENTER")
        header:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        ConfigurePanelTypeBadge(header, panel and panel.displayMode, header.label:GetStringWidth())
        if panel and panel.enabled == false then
            header:SetColor(0.5, 0.5, 0.5)
        elseif result.panelMatches then
            header:SetColor(1.0, 0.82, 0.0)
        end
        header:SetCallback("OnClick", function(widget, event, mouseButton)
            if mouseButton == "LeftButton" and SelectConfigFinderResult then
                SelectConfigFinderResult(containerId, panelId, nil)
            end
        end)
        panelContainer:AddChild(header)

        for _, entryInfo in ipairs(result.entryMatches or {}) do
            local buttonData = entryInfo.button
            local entry = AceGUI:Create("InteractiveLabel")
            CleanRecycledEntry(entry)
            local entryDisabled = buttonData and buttonData.enabled == false
            entry:SetText(entryInfo.text or (buttonData and buttonData.name) or "Entry")
            entry:SetFullWidth(true)
            entry:SetFontObject(GameFontHighlight)
            ApplyConfigRowIcon(entry, buttonData and GetButtonIcon(buttonData) or 134400, { desaturated = entryDisabled })
            entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            if entryDisabled then
                entry:SetColor(0.5, 0.5, 0.5)
            end

            local buttonIndex = entryInfo.index
            entry:SetCallback("OnClick", function(widget, event, mouseButton)
                if mouseButton == "LeftButton" and SelectConfigFinderResult then
                    SelectConfigFinderResult(containerId, panelId, buttonIndex)
                end
            end)
            panelContainer:AddChild(entry)
        end
    end

    CS.col2Scroll:DoLayout()
end

local function NotifyTutorialInlineAddSuccess(addTargetGroupId, rawInput)
    if not NotifyTutorialAction then
        return
    end
    local selectedButton = CS.selectedButton
    if addTargetGroupId and selectedButton then
        NotifyTutorialAction("inline_add_succeeded", {
            groupId = addTargetGroupId,
            buttonIndex = selectedButton,
            rawInput = rawInput,
        })
    end
end

local function SubmitInlineAdd(rawInput)
    CS.newInput = rawInput
    if CS.newInput == "" or not CS.addingToPanelId then
        return false
    end

    local addTargetGroupId = CS.addingToPanelId
    CS.selectedGroup = addTargetGroupId
    if not TryAdd(CS.newInput) then
        return false
    end

    NotifyTutorialInlineAddSuccess(addTargetGroupId, CS.newInput)
    CS.newInput = ""
    local targetGroup = CooldownCompanion.db.profile.groups[addTargetGroupId]
    if not (targetGroup and targetGroup.displayMode == "textures") then
        CS.pendingEditBoxFocus = true
    end
    CooldownCompanion:RefreshConfigPanel()
    return true
end

local function ConfigureInlineAddInstructions(inputBox, placeholderText)
    local editFrame = inputBox and inputBox.editbox
    if not editFrame then
        return function() end
    end

    local instructions = editFrame._cdcInlineAddInstructions
    if not instructions then
        instructions = editFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        instructions:SetPoint("LEFT", editFrame, "LEFT", 6, 0)
        instructions:SetPoint("RIGHT", editFrame, "RIGHT", -6, 0)
        instructions:SetJustifyH("LEFT")
        instructions:SetTextColor(0.5, 0.5, 0.5)
        editFrame._cdcInlineAddInstructions = instructions
    end
    instructions:SetText(placeholderText)

    local function Update(text)
        instructions:SetShown((text or "") == "")
    end

    local prevOnRelease = inputBox.events and inputBox.events["OnRelease"]
    inputBox:SetCallback("OnRelease", function(widget)
        if prevOnRelease then
            prevOnRelease(widget, "OnRelease")
        end
        instructions:Hide()
        instructions:SetText("")
    end)

    Update(editFrame:GetText())
    return Update
end

local function BuildInlineAddControls(panelContainer, panelMeta, panel, panelId, btnCount)
    if panel.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT
        or CS.addingToPanelId ~= panelId
        or (panel.displayMode == "textures" and btnCount >= 1) then
        return
    end

    panelMeta.hasInlineAdd = true
    local inputBox = AceGUI:Create("EditBox")
    if inputBox.editbox.Instructions then inputBox.editbox.Instructions:Hide() end
    inputBox:SetLabel("")
    inputBox:SetText(CS.newInput)
    inputBox:DisableButton(true)
    inputBox:SetFullWidth(true)
    panelMeta.addInputFrame = inputBox.frame
    local updatePlaceholder = ConfigureInlineAddInstructions(inputBox, "Add spell, item, trinket slot, or ID")
    inputBox:SetCallback("OnEnterPressed", function(widget, event, text)
        if CS.ConsumeAutocompleteEnter() then return end
        CS.HideAutocomplete()
        SubmitInlineAdd(text)
    end)
    inputBox:SetCallback("OnTextChanged", function(widget, event, text)
        updatePlaceholder(text)
        CS.newInput = text
        if text and #text >= 1 then
            local results = SearchAutocomplete(text)
            CS.ShowAutocompleteResults(results, widget, OnAutocompleteSelect, {
                requireExactNumericEnter = true,
            })
        else
            CS.HideAutocomplete()
        end
    end)
    inputBox.editbox:SetPoint("BOTTOMRIGHT", 1, 0)
    CS.SetupAutocompleteKeyHandler(inputBox)
    panelContainer:AddChild(inputBox)

    if CS.pendingEditBoxFocus then
        CS.pendingEditBoxFocus = false
        C_Timer.After(0, function()
            if inputBox.editbox then
                inputBox:SetFocus()
            end
        end)
    end

end

local function AddRotationAssistantLockedRow(panelContainer, panelId, opts)
    local entry = AceGUI:Create("InteractiveLabel")
    CleanRecycledEntry(entry)
    entry:SetText(ST.ROTATION_ASSISTANT_NAME)
    entry:SetFullWidth(true)
    entry:SetFontObject(GameFontHighlight)
    ApplyConfigRowIcon(entry, CooldownCompanion:GetRotationAssistantFallbackIcon())
    entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    if CS.selectedGroup == panelId and CS.selectedRotationAssistantEntry == true then
        entry:SetColor(0.4, 0.7, 1.0)
    end
    entry:SetCallback("OnClick", function()
        SelectConfigRotationAssistantEntry(panelId, {
            containerId = opts and opts.containerId or CS.selectedContainer,
        })
        CooldownCompanion:RefreshConfigPanel()
    end)
    panelContainer:AddChild(entry)
    return entry
end

local function EnsureRowBadge(frame, key, atlas, iconSize)
    local badge = frame[key]
    if not badge then
        badge = CreateFrame("Button", nil, frame)
        badge:SetSize(ROW_BADGE_SIZE, ROW_BADGE_SIZE)
        badge.icon = badge:CreateTexture(nil, "OVERLAY")
        badge.icon:SetAllPoints()
        badge:SetScript("OnEnter", function(self)
            if not self._cdcTooltipText then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(
                self._cdcTooltipText,
                self._cdcTooltipR or 1,
                self._cdcTooltipG or 1,
                self._cdcTooltipB or 1,
                true
            )
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        frame[key] = badge
    end

    badge:SetSize(ROW_BADGE_SIZE, ROW_BADGE_SIZE)
    badge.icon:ClearAllPoints()
    if iconSize then
        badge.icon:SetSize(iconSize, iconSize)
        badge.icon:SetPoint("CENTER", badge, "CENTER", 0, 0)
    else
        badge.icon:SetAllPoints()
    end
    badge.icon:SetAtlas(atlas, false)
    badge.icon:SetVertexColor(1, 1, 1, 1)
    badge._cdcTooltipText = nil
    badge._cdcTooltipR, badge._cdcTooltipG, badge._cdcTooltipB = nil, nil, nil
    badge:Hide()
    return badge
end

local function SetRowBadgeTooltip(badge, text, r, g, b)
    badge._cdcTooltipText = text
    badge._cdcTooltipR = r or 1
    badge._cdcTooltipG = g or 1
    badge._cdcTooltipB = b or 1
end

local function PlaceRowBadge(frame, badge, offsetX)
    if not (badge and badge:IsShown()) then
        return offsetX
    end
    badge:ClearAllPoints()
    badge:SetPoint("RIGHT", frame, "RIGHT", offsetX, 0)
    return offsetX - ROW_BADGE_SIZE - ROW_BADGE_SPACING
end

local function LayoutRowBadges(frame, ...)
    local offsetX = -ROW_BADGE_RIGHT_PAD
    for index = 1, select("#", ...) do
        local badge = select(index, ...)
        offsetX = PlaceRowBadge(frame, badge, offsetX)
    end
end

IsTriggerPanelGroup = function(group)
    return group and group.displayMode == "trigger"
end

local function GetTriggerRowDisplayText(buttonData)
    local targetText
    if buttonData and buttonData.type == "spell" then
        targetText = GetConfigEntryDisplayName(buttonData)
            or buttonData.name
            or ("Unknown " .. tostring(buttonData.type))

        local addedAs = buttonData.addedAs
        if addedAs ~= "spell" and addedAs ~= "aura" then
            addedAs = buttonData.isPassive and "aura" or "spell"
        end

        local icons = ""
        if addedAs ~= "aura" then
            icons = icons .. "|A:ui_adv_atk:15:15|a"
        else
            icons = icons .. "|A:ui_adv_health:15:15|a"
        end
        if icons ~= "" then
            targetText = targetText .. "  " .. icons
        end
    else
        targetText = GetConfigEntryDisplayName(buttonData, { includeDecorations = true })
            or buttonData.name
            or ("Unknown " .. tostring(buttonData.type))
    end

    if CooldownCompanion.GetCompactTriggerConditionSummary then
        local summary = CooldownCompanion:GetCompactTriggerConditionSummary(buttonData, 2)
        if summary and summary ~= "" then
            return targetText .. "  |cff888888" .. summary .. "|r"
        end
    end
    return targetText
end

local function ResolveColumn2TooltipSpellId(buttonData)
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
    local groupedByFolder = {}
    local looseGroups = {}

    for groupId, group in pairs(db.groups or {}) do
        if groupId ~= sourceGroupId
            and CanMoveEntryToGroup(sourceGroupId, groupId)
            and CooldownCompanion:CanPanelAcceptManualEntry(group)
        then
            local containerId = group.parentContainerId
            local container = containerId and containers[containerId]
            if container then
                local folderId = container.folderId
                local bucket
                if folderId and db.folders and db.folders[folderId] then
                    groupedByFolder[folderId] = groupedByFolder[folderId] or {}
                    bucket = groupedByFolder[folderId]
                else
                    bucket = looseGroups
                end

                local entry = bucket[containerId]
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
                    bucket[containerId] = entry
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

    local sections = {}
    local sortedFolders = {}
    for folderId, _ in pairs(groupedByFolder) do
        local folder = db.folders and db.folders[folderId]
        if folder then
            sortedFolders[#sortedFolders + 1] = {
                id = folderId,
                name = folder.name or ("Folder " .. folderId),
                order = CooldownCompanion:GetOrderForSpec(folder, CooldownCompanion._currentSpecId, folderId),
            }
        end
    end

    table.sort(sortedFolders, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.id < b.id
    end)

    for _, folder in ipairs(sortedFolders) do
        sections[#sections + 1] = {
            title = folder.name,
            entries = BuildSectionEntries(groupedByFolder[folder.id]),
        }
    end

    local looseEntries = BuildSectionEntries(looseGroups)
    if #looseEntries > 0 then
        sections[#sections + 1] = {
            title = (#sortedFolders > 0) and "No Folder" or nil,
            entries = looseEntries,
        }
    end

    return sections
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

-- Shared entry context menu: used by the column 2 entry rows and the wide
-- column's panel preview slots.
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

            local entryCount = sourceGroup and sourceGroup.buttons and #sourceGroup.buttons or 0
            if sourceIndex > 1 then
                local upInfo = UIDropDownMenu_CreateInfo()
                upInfo.text = "Move Up"
                upInfo.notCheckable = true
                upInfo.func = function()
                    CloseDropDownMenus()
                    PerformButtonReorder(sourceGroupId, sourceIndex, sourceIndex - 1)
                    CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(upInfo, level)
            end
            if sourceIndex < entryCount then
                local downInfo = UIDropDownMenu_CreateInfo()
                downInfo.text = "Move Down"
                downInfo.notCheckable = true
                downInfo.func = function()
                    CloseDropDownMenus()
                    PerformButtonReorder(sourceGroupId, sourceIndex, sourceIndex + 2)
                    CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(downInfo, level)
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
-- COLUMN 2: Panels
------------------------------------------------------------------------
local function RefreshColumn2()
    if not CS.col2Scroll then return end
    local col2 = CS.configFrame and CS.configFrame.col2
    if ClearCol2AnimatedPreview then
        ClearCol2AnimatedPreview()
    end

    -- Clear per-panel drop targets (rebuilt if we enter the panel render loop)
    CS._panelDropTargets = {}

    -- Release previous col2 bar widgets
    for _, widget in ipairs(CS.col2BarWidgets) do
        widget:Release()
    end
    wipe(CS.col2BarWidgets)

    CancelDrag()
    CS.HideAutocomplete()
    CS.col2Scroll.frame:Show()
    CS.col2Scroll:ReleaseChildren()

    if IsConfigFinderActive and IsConfigFinderActive() then
        RenderConfigFinderResults()
        return
    end

    -- In the wide buttons view column 2 lists panels only: entries live in
    -- the preview (other-class browsing keeps its rows - no preview there).
    local wideView = ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive() or false

    -- Restore scroll bottom offset for button bar space (browse mode may have cleared it)
    CS.col2Scroll.frame:SetPoint("BOTTOMRIGHT", CS.col2Scroll.frame:GetParent(), "BOTTOMRIGHT", 0, 30)

    -- Multi-group selection: show inline action buttons (container IDs)
    local multiGroupCount = 0
    local multiContainerIds = {}
    for cid in pairs(CS.selectedGroups) do
        multiGroupCount = multiGroupCount + 1
        multiContainerIds[#multiContainerIds + 1] = cid
    end
    -- Sort by container order so exports and bulk operations preserve visual layout
    local containers = CooldownCompanion.db.profile.groupContainers or {}
    table.sort(multiContainerIds, function(a, b)
        local ca, cb = containers[a], containers[b]
        local oa = ca and CooldownCompanion:GetOrderForSpec(ca, CooldownCompanion._currentSpecId, a) or a
        local ob = cb and CooldownCompanion:GetOrderForSpec(cb, CooldownCompanion._currentSpecId, b) or b
        return oa < ob
    end)
    if multiGroupCount >= 2 then
        if CS.col2ButtonBar then CS.col2ButtonBar:Hide() end
        local db = CooldownCompanion.db.profile
        local containers = db.groupContainers or {}

        local heading = AceGUI:Create("Heading")
        heading:SetText(multiGroupCount .. " Groups Selected")
        local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
        if cc then heading.label:SetTextColor(cc.r, cc.g, cc.b) end
        heading.right:ClearAllPoints()
        heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
        heading.right:SetPoint("LEFT", heading.label, "RIGHT", 5, 0)
        heading:SetFullWidth(true)
        CS.col2Scroll:AddChild(heading)

        -- Lock / Unlock All (operates on containers)
        local anyLocked = false
        for _, cid in ipairs(multiContainerIds) do
            local c = containers[cid]
            if c and c.locked then
                anyLocked = true
                break
            end
        end

        local lockBtn = AceGUI:Create("Button")
        lockBtn:SetText(anyLocked and "Unlock All" or "Lock All")
        lockBtn:SetFullWidth(true)
        lockBtn:SetCallback("OnClick", function()
            local newState = not anyLocked
            for _, cid in ipairs(multiContainerIds) do
                local c = containers[cid]
                if c then
                    c.locked = newState
                    CooldownCompanion:UpdateContainerDragHandle(cid, newState)
                    CooldownCompanion:RefreshContainerPanels(cid)
                end
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
        CS.col2Scroll:AddChild(lockBtn)

        local spacer1 = AceGUI:Create("Label")
        spacer1:SetText(" ")
        spacer1:SetFullWidth(true)
        local f1, _, fl1 = spacer1.label:GetFont()
        spacer1:SetFont(f1, 3, fl1 or "")
        CS.col2Scroll:AddChild(spacer1)

        -- Move to Folder
        local moveBtn = AceGUI:Create("Button")
        moveBtn:SetText("Move to Folder")
        moveBtn:SetFullWidth(true)
        moveBtn:SetCallback("OnClick", function()
            if not CS.moveMenuFrame then
                CS.moveMenuFrame = CreateFrame("Frame", "CDCMoveMenu", UIParent, "UIDropDownMenuTemplate")
            end
            UIDropDownMenu_Initialize(CS.moveMenuFrame, function(self, level)
                local info = UIDropDownMenu_CreateInfo()
                info.text = "(No Folder)"
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    for _, cid in ipairs(multiContainerIds) do
                        CooldownCompanion:MoveGroupToFolder(cid, nil)
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(info, level)

                local folderList = {}
                for fid, folder in pairs(db.folders) do
                    local folderScope = CooldownCompanion.ResolveFolderClassScope
                        and CooldownCompanion:ResolveFolderClassScope(folder)
                        or nil
                    if not (folderScope and folderScope.isInvalid)
                        and CanAllContainersMoveToFolder(multiContainerIds, fid)
                    then
                        local sectionKey = folderScope and folderScope.sectionKey or folder.section
                        table.insert(folderList, {
                            id = fid,
                            name = folder.name,
                            section = sectionKey,
                            classKey = folderScope and folderScope.ownerClassKey or nil,
                            order = CooldownCompanion:GetOrderForSpec(folder, CooldownCompanion._currentSpecId, fid),
                        })
                    end
                end
                table.sort(folderList, function(a, b)
                    if a.section ~= b.section then
                        return a.section == "global"
                    end
                    return a.order < b.order
                end)

                for _, f in ipairs(folderList) do
                    info = UIDropDownMenu_CreateInfo()
                    local sectionLabel = " (Current Class)"
                    if f.section == "global" then
                        sectionLabel = " (Global)"
                    elseif f.classKey then
                        sectionLabel = " (" .. f.classKey .. ")"
                    end
                    info.text = f.name .. sectionLabel
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        if not CanAllContainersMoveToFolder(multiContainerIds, f.id) then
                            if CooldownCompanion.Print then
                                CooldownCompanion:Print("Groups cannot be moved into folders owned by another class.")
                            end
                            return
                        end
                        for _, cid in ipairs(multiContainerIds) do
                            CooldownCompanion:MoveGroupToFolder(cid, f.id)
                        end
                        CooldownCompanion:RefreshAllGroups()
                        CooldownCompanion:RefreshConfigPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end, "MENU")
            CS.moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            ToggleDropDownMenu(1, nil, CS.moveMenuFrame, "cursor", 0, 0)
        end)
        CS.col2Scroll:AddChild(moveBtn)

        local spacer2 = AceGUI:Create("Label")
        spacer2:SetText(" ")
        spacer2:SetFullWidth(true)
        local f2, _, fl2 = spacer2.label:GetFont()
        spacer2:SetFont(f2, 3, fl2 or "")
        CS.col2Scroll:AddChild(spacer2)

        -- Export Selected
        local exportBtn = AceGUI:Create("Button")
        exportBtn:SetText("Export Selected")
        exportBtn:SetFullWidth(true)
        exportBtn:SetCallback("OnClick", function()
            local exportContainers = {}
            for _, cid in ipairs(multiContainerIds) do
                local c = db.groupContainers[cid]
                if c then
                    local containerData = BuildContainerExportData(c)
                    local sortedPanels = CooldownCompanion:GetPanels(cid)
                    local panels = {}
                    for _, entry in ipairs(sortedPanels) do
                        local panelData = BuildGroupExportData(entry.group)
                        panelData._originalGroupId = entry.groupId
                        panels[#panels + 1] = panelData
                    end
                    exportContainers[#exportContainers + 1] = { container = containerData, panels = panels, _originalContainerId = cid }
                end
            end
            local payload = { type = "containers", version = 1, containers = exportContainers }
            local exportString = EncodeExportData(payload)
            ShowPopupAboveConfig("CDC_EXPORT_GROUP", nil, { exportString = exportString })
        end)
        CS.col2Scroll:AddChild(exportBtn)

        local spacer3 = AceGUI:Create("Label")
        spacer3:SetText(" ")
        spacer3:SetFullWidth(true)
        local f3, _, fl3 = spacer3.label:GetFont()
        spacer3:SetFont(f3, 3, fl3 or "")
        CS.col2Scroll:AddChild(spacer3)

        -- Delete Selected
        local delBtn = AceGUI:Create("Button")
        delBtn:SetText("Delete Selected")
        delBtn:SetFullWidth(true)
        delBtn:SetCallback("OnClick", function()
            local popup = StaticPopup_Show("CDC_DELETE_SELECTED_GROUPS", #multiContainerIds)
            if popup then
                popup.data = { groupIds = CopyTable(multiContainerIds) }
            end
        end)
        CS.col2Scroll:AddChild(delBtn)

        return
    end

    -- Unified container view: show search bar + all panels' buttons (with collapsible headers for multi-panel)
    if CS.selectedContainer then
        local profile = CooldownCompanion.db.profile
        local container = profile.groupContainers and profile.groupContainers[CS.selectedContainer]
        if not container then
            if CS.col2ButtonBar then CS.col2ButtonBar:Hide() end
            local label = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(label)
            label:SetText("Container not found")
            label:SetFullWidth(true)
            CS.col2Scroll:AddChild(label)
            return
        end

        -- Show and populate the panel-type button bar
        if CS.col2ButtonBar then
            CS.col2ButtonBar:Show()
            local barW = CS.col2ButtonBar:GetWidth() or 300
            local panelBtnWidth = (barW - 6) / 3
            PopulateCol2PanelCreationBar(panelBtnWidth)
        end

        -- Collect sorted panels
        local panels = CooldownCompanion:GetPanels(CS.selectedContainer)
        local panelCount = #panels

        -- Guard: clear stale addingToPanelId if the target panel no longer exists in this container
        if CS.addingToPanelId then
            local found = false
            for _, p in ipairs(panels) do
                if p.groupId == CS.addingToPanelId then found = true; break end
            end
            if not found then CS.addingToPanelId = nil end
        end

        local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))

        -- Panel currently hosting the resource-bar anchor (for the pin badge)
        local resourcesAnchorPanelId
        if ST._GetResourcesEntryPlacement then
            local placement, anchorPanelId = ST._GetResourcesEntryPlacement()
            if placement == "attached" then
                resourcesAnchorPanelId = anchorPanelId
            end
        end

        if panelCount == 0 then
            RenderColumn2NoPanelsState(cc)
            return
        end

        -- Metadata for cross-panel drag detection
        local col2RenderedRows = {}
        local col2PanelMetas = {}

        -- Reset per-panel drop targets (rebuilt in the loop below)
        CS._panelDropTargets = {}

        -- Render each panel's buttons (with headers for multi-panel containers)
        for panelIndex, panelInfo in ipairs(panels) do
            local panelId = panelInfo.groupId
            local panel = panelInfo.group
            local isCollapsed = CS.collapsedPanels[panelId]
            local panelMeta = {
                panelId = panelId,
                group = panel,
                isCollapsed = isCollapsed and true or false,
                displayMode = panel.displayMode,
                buttonRows = {},
                addInputFrame = nil,
            }

            -- Class-colored accent separator between panels
            if panelIndex > 1 then
                AddClassAccentSpacer(CS.col2Scroll, cc)
            end

            -- Bordered container for this panel
            local panelContainer = AceGUI:Create("InlineGroup")
            panelContainer:SetTitle("")
            panelContainer:SetLayout("List")
            panelContainer:SetFullWidth(true)
            CompactUntitledInlineGroupConfig(panelContainer)
            CS.col2Scroll:AddChild(panelContainer)
            panelMeta.panelWidget = panelContainer
            panelMeta.panelFrame = panelContainer.frame
            if panelContainer.frame.GetBackdropColor then
                panelMeta.backdropColor = { panelContainer.frame:GetBackdropColor() }
            end
            if panelContainer.frame.GetBackdropBorderColor then
                panelMeta.borderColor = { panelContainer.frame:GetBackdropBorderColor() }
            end

            -- Per-panel drop highlight overlay (pooled on underlying frame to survive AceGUI recycling)
            do
                local pf = panelContainer.frame
                local overlay = pf._cdcDropOverlay
                if not overlay then
                    overlay = CreateFrame("Frame", nil, pf, "BackdropTemplate")
                    overlay:SetAllPoints(pf)
                    overlay:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
                    overlay:SetBackdropColor(0.15, 0.55, 0.85, 0.25)
                    overlay:EnableMouse(true)

                    local border = overlay:CreateTexture(nil, "BORDER")
                    border:SetAllPoints()
                    border:SetColorTexture(0.3, 0.7, 1.0, 0.35)

                    local inner = overlay:CreateTexture(nil, "ARTWORK")
                    inner:SetPoint("TOPLEFT", 2, -2)
                    inner:SetPoint("BOTTOMRIGHT", -2, 2)
                    inner:SetColorTexture(0.05, 0.15, 0.25, 0.6)

                    overlay._cdcText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    overlay._cdcText:SetPoint("CENTER", 0, 0)

                    pf._cdcDropOverlay = overlay
                end
                overlay:SetFrameLevel(pf:GetFrameLevel() + 10)
                overlay:SetAlpha(1)
                overlay._cdcText:SetText("|cffAADDFFDrop here|r")
                overlay:Hide()

                local dropPanelId = panelId
                overlay:SetScript("OnReceiveDrag", function()
                    local prev = CS.selectedGroup
                    CS.selectedGroup = dropPanelId
                    TryReceiveCursorDrop()
                    CS.selectedGroup = prev
                end)
                overlay:SetScript("OnMouseUp", function(self, button)
                    if button == "LeftButton" and GetCursorInfo() then
                        local prev = CS.selectedGroup
                        CS.selectedGroup = dropPanelId
                        TryReceiveCursorDrop()
                        CS.selectedGroup = prev
                    end
                end)

                table.insert(CS._panelDropTargets, { panelId = dropPanelId, frame = pf, overlay = overlay })
            end

            -- Panel header
                local btnCount = GetConfigPanelButtonCount(panel)
                local headerText = BuildPanelHeaderText(panel, panelId, btnCount, "666666")

                local header = AceGUI:Create("InteractiveLabel")
                CleanRecycledEntry(header)
                header:SetText(headerText)

                -- Mode badge overlay (pooled on widget, same pattern as old Column 1)
                header:SetFullWidth(true)
                header:SetFontObject(GameFontHighlight)
                header:SetJustifyH("CENTER")
                ApplyConfigTextRow(header, "CENTER")
                -- Draw the panel-type badge separately so shared atlases can use mode-specific tint.
                local textW = header.label:GetStringWidth()
                ConfigurePanelTypeBadge(header, panel.displayMode, textW)
                header:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")

                local rightOffset = (textW / 2) + 4
                local isCursorAnchoredPanel = CooldownCompanion.IsGroupCursorAnchored
                    and CooldownCompanion:IsGroupCursorAnchored(panel)
                    or false
                ConfigureCursorAnchorBadge(header, panel)
                ConfigureCDMRefreshBadge(header, panel, panelId, CS.selectedContainer, isCursorAnchoredPanel)
                rightOffset = ConfigureGenericRenameBadge(header, panel, panelId, rightOffset)

                -- Anchor unlock badge (shown when panel is individually unlocked)
                local anchorBadge = header.frame._cdcAnchorBadge
                if not anchorBadge then
                    anchorBadge = header.frame:CreateTexture(nil, "OVERLAY")
                    header.frame._cdcAnchorBadge = anchorBadge
                end
                anchorBadge:SetSize(16, 16)
                anchorBadge:ClearAllPoints()
                anchorBadge:SetPoint("LEFT", header.label, "CENTER", rightOffset, 0)
                if panel.locked == false and not isCursorAnchoredPanel then
                    anchorBadge:SetAtlas("ShipMissionIcon-Training-Map", false)
                    anchorBadge:Show()
                    rightOffset = rightOffset + 22
                else
                    anchorBadge:Hide()
                end

                -- Disabled badge (shown when panel is individually disabled)
                local disabledBadge = header.frame._cdcHeaderDisabledBadge
                if not disabledBadge then
                    disabledBadge = header.frame:CreateTexture(nil, "OVERLAY")
                    header.frame._cdcHeaderDisabledBadge = disabledBadge
                end
                disabledBadge:SetSize(16, 16)
                disabledBadge:ClearAllPoints()
                disabledBadge:SetPoint("LEFT", header.label, "CENTER", rightOffset, 0)
                if panel.enabled == false then
                    disabledBadge:SetAtlas("GM-icon-visibleDis-pressed", false)
                    disabledBadge:Show()
                    rightOffset = rightOffset + 22
                else
                    disabledBadge:Hide()
                end

                -- Resource Bars anchor badge (pin on the hosting panel).
                -- Mouse is enabled for the tooltip with clicks propagating to
                -- the row; SetPropagateMouseClicks is protected in combat, so
                -- the tooltip is skipped when refreshed mid-combat.
                local resourcePinBadge = header.frame._cdcResourcePinBadge
                if not resourcePinBadge then
                    resourcePinBadge = CreateFrame("Frame", nil, header.frame)
                    resourcePinBadge:SetSize(16, 16)
                    resourcePinBadge.icon = resourcePinBadge:CreateTexture(nil, "OVERLAY")
                    resourcePinBadge.icon:SetAllPoints()
                    resourcePinBadge.icon:SetAtlas("Waypoint-MapPin-Tracked", false)
                    resourcePinBadge:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:AddLine("Resource Bars")
                        GameTooltip:AddLine("Your resource bars are anchored to this panel.", 1, 1, 1, true)
                        GameTooltip:AddLine("Right-click the panel to exclude it from auto-anchoring.", 0.6, 0.6, 0.6, true)
                        GameTooltip:Show()
                    end)
                    resourcePinBadge:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    header.frame._cdcResourcePinBadge = resourcePinBadge
                end
                resourcePinBadge:ClearAllPoints()
                resourcePinBadge:SetPoint("LEFT", header.label, "CENTER", rightOffset, 0)
                if resourcesAnchorPanelId == panelId then
                    if not InCombatLockdown() and resourcePinBadge.SetPropagateMouseClicks then
                        resourcePinBadge:EnableMouse(true)
                        resourcePinBadge:SetPropagateMouseClicks(true)
                    else
                        resourcePinBadge:EnableMouse(false)
                    end
                    resourcePinBadge:Show()
                    rightOffset = rightOffset + 22
                else
                    resourcePinBadge:Hide()
                end

                -- Spec / hero talent filter badges (panel-level filters not inherited from container/folder)
                local specBadges = header.frame._cdcSpecBadges
                if not specBadges then
                    specBadges = {}
                    header.frame._cdcSpecBadges = specBadges
                end
                for _, sb in ipairs(specBadges) do
                    if sb._cdcCircleMask then sb.icon:RemoveMaskTexture(sb._cdcCircleMask) end
                    sb.icon:SetTexCoord(0, 1, 0, 1)
                    sb:Hide()
                end

                local containerSpecs = BuildEligibilityBadgeMap(
                    container.specs,
                    container.loadConditions and container.loadConditions.specAllowlist
                )
                local containerHeroTalents = container.heroTalents
                local folderSpecs, folderHeroTalents
                if container.folderId and profile.folders then
                    local folder = profile.folders[container.folderId]
                    if folder then
                        folderSpecs = BuildEligibilityBadgeMap(
                            folder.specs,
                            folder.loadConditions and folder.loadConditions.specAllowlist
                        )
                        folderHeroTalents = folder.heroTalents
                    end
                end

                local specBadgeIdx = 0
                local panelSpecs = BuildEligibilityBadgeMap(
                    panel.specs,
                    panel.loadConditions and panel.loadConditions.specAllowlist
                )

                if panelSpecs then
                    for specId in pairs(panelSpecs) do
                        if not (containerSpecs and containerSpecs[specId])
                           and not (folderSpecs and folderSpecs[specId]) then
                            local _, _, _, specIcon = GetSpecializationInfoForSpecID(specId)
                            if specIcon then
                                specBadgeIdx = specBadgeIdx + 1
                                local sb = specBadges[specBadgeIdx]
                                if not sb then
                                    sb = CreateFrame("Frame", nil, header.frame)
                                    sb.icon = sb:CreateTexture(nil, "OVERLAY")
                                    sb.icon:SetAllPoints()
                                    sb:EnableMouse(false)
                                    local mask = sb:CreateMaskTexture()
                                    mask:SetAllPoints(sb.icon)
                                    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                                    sb._cdcCircleMask = mask
                                    specBadges[specBadgeIdx] = sb
                                end
                                sb:SetSize(16, 16)
                                sb.icon:SetTexture(specIcon)
                                sb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                sb.icon:AddMaskTexture(sb._cdcCircleMask)
                                sb:ClearAllPoints()
                                sb:SetPoint("LEFT", header.label, "CENTER", rightOffset, 0)
                                sb:Show()
                                rightOffset = rightOffset + 18
                            end
                        end
                    end
                end

                if panel.heroTalents then
                    local configID = C_ClassTalents.GetActiveConfigID()
                    if configID then
                        for subTreeID in pairs(panel.heroTalents) do
                            if not (containerHeroTalents and containerHeroTalents[subTreeID])
                               and not (folderHeroTalents and folderHeroTalents[subTreeID]) then
                                local subTreeInfo = C_Traits.GetSubTreeInfo(configID, subTreeID)
                                if subTreeInfo and subTreeInfo.iconElementID then
                                    specBadgeIdx = specBadgeIdx + 1
                                    local sb = specBadges[specBadgeIdx]
                                    if not sb then
                                        sb = CreateFrame("Frame", nil, header.frame)
                                        sb.icon = sb:CreateTexture(nil, "OVERLAY")
                                        sb.icon:SetAllPoints()
                                        sb:EnableMouse(false)
                                        specBadges[specBadgeIdx] = sb
                                    end
                                    sb:SetSize(16, 16)
                                    sb.icon:SetAtlas(subTreeInfo.iconElementID, false)
                                    sb:ClearAllPoints()
                                    sb:SetPoint("LEFT", header.label, "CENTER", rightOffset, 0)
                                    sb:Show()
                                    rightOffset = rightOffset + 18
                                end
                            end
                        end
                    end
                end

                -- Highlight: blue if multi-selected (overrides all), gray if disabled, green if single-selected
                if CS.selectedPanels[panelId] then
                    header:SetColor(0.4, 0.7, 1.0)
                elseif panel.enabled == false then
                    header:SetColor(0.5, 0.5, 0.5)
                elseif CS.selectedGroup == panelId
                    and not CS.selectedButton
                    and not CS.selectedRotationAssistantEntry then
                    header:SetColor(0, 1, 0)
                end

                header:SetCallback("OnClick", function(widget, event, mouseButton)
                    if mouseButton == "LeftButton"
                        and panelCount > 1
                        and not IsControlKeyDown()
                        and not GetCursorInfo() then
                        local cursorX, cursorY = GetScaledCursorPosition(CS.col2Scroll)
                        CS.dragState = {
                            kind = "panel",
                            phase = "pending",
                            sourcePanelId = panelId,
                            containerId = CS.selectedContainer,
                            scrollWidget = CS.col2Scroll,
                            startX = cursorX,
                            startY = cursorY,
                            panelDropTargets = CS._panelDropTargets,
                        }
                        if CS.lastCol2RenderedRows then
                            for _, row in ipairs(CS.lastCol2RenderedRows) do
                                if row.kind == "header" and row.panelId == panelId then
                                    CS.dragState.widget = row.widget
                                    break
                                end
                            end
                        end
                        StartDragTracking()
                    end
                end)

                -- Right-click context menu on mouseup (InteractiveLabel fires OnClick
                -- on mousedown which conflicts with UIDropDownMenu's mouseup behavior)
                local ctxPanelId = panelId
                local ctxPanel = panel
                header.frame:SetScript("OnMouseUp", function(self, mouseButton)
                    if CS.dragState and CS.dragState.phase == "active" then return end
                    if mouseButton == "LeftButton" then
                        local now = GetTime()
                        local lastClick = CS.panelClickTimes[panelId] or 0
                        CS.panelClickTimes[panelId] = now
                        if (now - lastClick) < 0.3 then
                            -- Double-click collapse only applies while entry
                            -- rows render (browse mode); in the wide view the
                            -- second click is swallowed so it can't
                            -- toggle-deselect the panel.
                            CS.panelClickTimes[panelId] = 0
                            if not (ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive()) then
                                CS.collapsedPanels[panelId] = not CS.collapsedPanels[panelId] or nil
                                CooldownCompanion:RefreshConfigPanel()
                            end
                            return
                        end

                        if IsControlKeyDown() then
                            ToggleConfigPanelMultiSelect(panelId)
                            CooldownCompanion:RefreshConfigPanel()
                            return
                        end

                        if IsShiftKeyDown() then
                            OpenPanelLoadConditions(panelId, CS.selectedContainer)
                            return
                        end

                        SelectConfigPanel(panelId, { toggle = true })
                        CooldownCompanion:RefreshConfigPanel()
                        return
                    elseif mouseButton == "MiddleButton" then
                        if CooldownCompanion.IsGroupCursorAnchored and CooldownCompanion:IsGroupCursorAnchored(panel) then
                            CooldownCompanion:Print("Cursor-anchored panels are edited from Layout.")
                            return
                        end
                        if panel.locked == false then
                            panel.locked = nil
                            CooldownCompanion:Print(panel.name .. " locked.")
                        else
                            panel.locked = false
                            CooldownCompanion:Print(panel.name .. " unlocked. Drag to reposition.")
                        end
                        CooldownCompanion:RefreshGroupFrame(panelId)
                        CooldownCompanion:RefreshConfigPanel()
                        return
                    elseif mouseButton ~= "RightButton" then
                        return
                    end

                    if not CS.panelContextMenu then
                        CS.panelContextMenu = CreateFrame("Frame", "CDCPanelContextMenu", UIParent, "UIDropDownMenuTemplate")
                    end
                    local ctxContainerId = CS.selectedContainer
                    UIDropDownMenu_Initialize(CS.panelContextMenu, function(self, level, menuList)
                        level = level or 1
                        if level == 1 then
                            local info = UIDropDownMenu_CreateInfo()
                            info.text = "Rename"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                ShowPopupAboveConfig("CDC_RENAME_GROUP", ctxPanel.name or "Panel", { groupId = ctxPanelId })
                            end
                            UIDropDownMenu_AddButton(info, level)

                            -- Disable / Enable panel
                            info = UIDropDownMenu_CreateInfo()
                            info.text = (ctxPanel.enabled ~= false) and "Disable" or "Enable"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                ctxPanel.enabled = not (ctxPanel.enabled ~= false)
                                CooldownCompanion:RefreshGroupFrame(ctxPanelId)
                                CooldownCompanion:RefreshConfigPanel()
                            end
                            UIDropDownMenu_AddButton(info, level)

                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Load Conditions"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                OpenPanelLoadConditions(ctxPanelId, ctxContainerId)
                            end
                            UIDropDownMenu_AddButton(info, level)

                            -- Lock / Unlock panel anchor
                            if not (CooldownCompanion.IsGroupCursorAnchored and CooldownCompanion:IsGroupCursorAnchored(ctxPanel)) then
                                info = UIDropDownMenu_CreateInfo()
                                info.text = ctxPanel.locked == false and "Lock Anchor" or "Unlock Anchor"
                                info.notCheckable = true
                                info.func = function()
                                    CloseDropDownMenus()
                                    if ctxPanel.locked == false then
                                        ctxPanel.locked = nil
                                        CooldownCompanion:Print(ctxPanel.name .. " locked.")
                                    else
                                        ctxPanel.locked = false
                                        CooldownCompanion:Print(ctxPanel.name .. " unlocked. Drag to reposition.")
                                    end
                                    CooldownCompanion:RefreshGroupFrame(ctxPanelId)
                                    CooldownCompanion:RefreshConfigPanel()
                                end
                                UIDropDownMenu_AddButton(info, level)
                            end

                            -- Auto-anchoring eligibility (icon-like modes only — others are never eligible)
                            if CooldownCompanion:IsIconLikeDisplayMode(ctxPanel.displayMode) then
                                info = UIDropDownMenu_CreateInfo()
                                info.text = ctxPanel.anchorEligible ~= false and "Exclude from Auto-Anchoring" or "Include in Auto-Anchoring"
                                info.notCheckable = true
                                info.func = function()
                                    CloseDropDownMenus()
                                    if ctxPanel.anchorEligible ~= false then
                                        ctxPanel.anchorEligible = false
                                    else
                                        ctxPanel.anchorEligible = nil
                                    end
                                    CooldownCompanion:EvaluateResourceBars()
                                    CooldownCompanion:UpdateAnchorStacking()
                                    CooldownCompanion:EvaluateCastBar()
                                    CooldownCompanion:EvaluateFrameAnchoring()
                                    CooldownCompanion:RefreshConfigPanel()
                                end
                                UIDropDownMenu_AddButton(info, level)
                            end

                            if ctxPanel.displayMode ~= ST.DISPLAY_MODE_ROTATION_ASSISTANT then
                                local switchModes = {
                                    { mode = "icons", label = "Icons" },
                                    { mode = "bars", label = "Bars" },
                                    { mode = "text", label = "Text" },
                                    { mode = "textures", label = "Textures" },
                                }
                                for _, m in ipairs(switchModes) do
                                    if ctxPanel.displayMode ~= m.mode then
                                        info = UIDropDownMenu_CreateInfo()
                                        info.text = "Switch to " .. m.label
                                        info.notCheckable = true
                                        local targetMode = m.mode
                                        info.func = function()
                                            CloseDropDownMenus()
                                            if CooldownCompanion:ChangePanelDisplayMode(ctxPanelId, targetMode) then
                                                if targetMode == "textures" then
                                                    CS.pendingTexturePickerOpen = ctxPanelId
                                                    SelectConfigPanel(ctxPanelId)
                                                end
                                                CooldownCompanion:RefreshConfigPanel()
                                            end
                                        end
                                        UIDropDownMenu_AddButton(info, level)
                                    end
                                end
                            end

                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Duplicate"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                local newPanelId = CooldownCompanion:DuplicatePanel(ctxContainerId, ctxPanelId)
                                if newPanelId then
                                    SelectConfigPanel(newPanelId)
                                    CooldownCompanion:RefreshConfigPanel()
                                end
                            end
                            UIDropDownMenu_AddButton(info, level)

                            local copyStyleMode
                            if ctxPanel.displayMode == "bars" then
                                copyStyleMode = "bars"
                            elseif ctxPanel.displayMode == nil or ctxPanel.displayMode == "icons" then
                                copyStyleMode = "icons"
                            end
                            if copyStyleMode then
                                local _, copyPanelOrder = CooldownCompanion:GetDirectStyleCopyPanelList(copyStyleMode, ctxPanelId)
                                info = UIDropDownMenu_CreateInfo()
                                info.text = "Copy Style From"
                                info.notCheckable = true
                                if #copyPanelOrder > 0 then
                                    info.hasArrow = true
                                    info.menuList = "COPY_STYLE_FROM_PANEL"
                                else
                                    info.disabled = true
                                end
                                UIDropDownMenu_AddButton(info, level)
                            end

                            -- "Move to Group" submenu (only when other visible containers exist)
                            local db = CooldownCompanion.db.profile
                            local hasOtherContainer = false
                            for cid, _ in pairs(db.groupContainers) do
                                if cid ~= ctxContainerId and CanPanelMoveToContainer(ctxPanelId, cid) then
                                    hasOtherContainer = true
                                    break
                                end
                            end
                            if hasOtherContainer then
                                info = UIDropDownMenu_CreateInfo()
                                info.text = "Move to Group"
                                info.notCheckable = true
                                info.hasArrow = true
                                info.menuList = "MOVE_TO_GROUP"
                                UIDropDownMenu_AddButton(info, level)
                            end

                            -- Export single panel
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Export"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                local db = CooldownCompanion.db.profile
                                local containerData = BuildContainerExportData(db.groupContainers[ctxContainerId])
                                containerData.name = ctxPanel.name or "Panel"
                                local payload = {
                                    type = "container",
                                    version = 1,
                                    container = containerData,
                                    panels = { BuildGroupExportData(ctxPanel) },
                                    _originalContainerId = ctxContainerId,
                                }
                                local exportString = EncodeExportData(payload)
                                ShowPopupAboveConfig("CDC_EXPORT_GROUP", nil, { exportString = exportString })
                            end
                            UIDropDownMenu_AddButton(info, level)

                            info = UIDropDownMenu_CreateInfo()
                            info.text = "|cffff4444Delete|r"
                            info.notCheckable = true
                            info.func = function()
                                CloseDropDownMenus()
                                ShowPopupAboveConfig("CDC_DELETE_PANEL", ctxPanel.name or "Panel", { containerId = ctxContainerId, panelId = ctxPanelId })
                            end
                            UIDropDownMenu_AddButton(info, level)

                        elseif menuList == "COPY_STYLE_FROM_PANEL" then
                            local copyStyleMode
                            if ctxPanel.displayMode == "bars" then
                                copyStyleMode = "bars"
                            elseif ctxPanel.displayMode == nil or ctxPanel.displayMode == "icons" then
                                copyStyleMode = "icons"
                            end
                            local copyPanelList, copyPanelOrder = CooldownCompanion:GetDirectStyleCopyPanelList(copyStyleMode, ctxPanelId)
                            if #copyPanelOrder == 0 then
                                local emptyInfo = UIDropDownMenu_CreateInfo()
                                emptyInfo.text = "No same-type panels available"
                                emptyInfo.notCheckable = true
                                emptyInfo.disabled = true
                                UIDropDownMenu_AddButton(emptyInfo, level)
                            else
                                for _, sourceGroupId in ipairs(copyPanelOrder) do
                                    local sourceName = copyPanelList[sourceGroupId] or ("Panel " .. tostring(sourceGroupId))
                                    local copyInfo = UIDropDownMenu_CreateInfo()
                                    copyInfo.text = sourceName
                                    copyInfo.notCheckable = true
                                    copyInfo.func = function()
                                        CloseDropDownMenus()
                                        ShowPopupAboveConfig("CDC_CONFIRM_PANEL_STYLE_COPY", sourceName, {
                                            mode = copyStyleMode,
                                            sourceGroupId = sourceGroupId,
                                            targetGroupId = ctxPanelId,
                                        })
                                    end
                                    UIDropDownMenu_AddButton(copyInfo, level)
                                end
                            end

                        elseif menuList == "MOVE_TO_GROUP" then
                            local db = CooldownCompanion.db.profile
                            local containers = db.groupContainers or {}
                            local folderContainers, looseContainers = {}, {}
                            for cid, ctr in pairs(containers) do
                                if cid ~= ctxContainerId and CanPanelMoveToContainer(ctxPanelId, cid) then
                                    local cName = ctr.name or ("Group " .. cid)
                                    local fid = ctr.folderId
                                    if fid and db.folders[fid] then
                                        folderContainers[fid] = folderContainers[fid] or {}
                                        table.insert(folderContainers[fid], { id = cid, name = cName, order = CooldownCompanion:GetOrderForSpec(ctr, CooldownCompanion._currentSpecId, cid) })
                                    else
                                        table.insert(looseContainers, { id = cid, name = cName, order = CooldownCompanion:GetOrderForSpec(ctr, CooldownCompanion._currentSpecId, cid) })
                                    end
                                end
                            end
                            local sortedFolders = {}
                            for fid, folder in pairs(db.folders) do
                                if folderContainers[fid] then
                                    table.insert(sortedFolders, { id = fid, name = folder.name or ("Folder " .. fid), order = CooldownCompanion:GetOrderForSpec(folder, CooldownCompanion._currentSpecId, fid) })
                                end
                            end
                            table.sort(sortedFolders, function(a, b) return a.order < b.order end)
                            local hasFolders = #sortedFolders > 0
                            for _, folder in ipairs(sortedFolders) do
                                local hdr = UIDropDownMenu_CreateInfo()
                                hdr.text = folder.name
                                hdr.isTitle = true
                                hdr.notCheckable = true
                                UIDropDownMenu_AddButton(hdr, level)
                                table.sort(folderContainers[folder.id], function(a, b) return a.order < b.order end)
                                for _, c in ipairs(folderContainers[folder.id]) do
                                    local info = UIDropDownMenu_CreateInfo()
                                    info.text = c.name
                                    info.notCheckable = true
                                    info.func = function()
                                        CloseDropDownMenus()
                                        if CooldownCompanion:MovePanel(ctxPanelId, c.id) then
                                            SelectConfigPanel(ctxPanelId, { containerId = c.id })
                                            CooldownCompanion:RefreshConfigPanel()
                                        end
                                    end
                                    UIDropDownMenu_AddButton(info, level)
                                end
                            end
                            if #looseContainers > 0 then
                                if hasFolders then
                                    local hdr = UIDropDownMenu_CreateInfo()
                                    hdr.text = "No Folder"
                                    hdr.isTitle = true
                                    hdr.notCheckable = true
                                    UIDropDownMenu_AddButton(hdr, level)
                                end
                                table.sort(looseContainers, function(a, b) return a.order < b.order end)
                                for _, c in ipairs(looseContainers) do
                                    local info = UIDropDownMenu_CreateInfo()
                                    info.text = c.name
                                    info.notCheckable = true
                                    info.func = function()
                                        CloseDropDownMenus()
                                        if CooldownCompanion:MovePanel(ctxPanelId, c.id) then
                                            SelectConfigPanel(ctxPanelId, { containerId = c.id })
                                            CooldownCompanion:RefreshConfigPanel()
                                        end
                                    end
                                    UIDropDownMenu_AddButton(info, level)
                                end
                            end
                        end
                    end, "MENU")
                    CS.panelContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                    ToggleDropDownMenu(1, nil, CS.panelContextMenu, "cursor", 0, 0)
                end)

                -- Add toggle button overlay (pooled on underlying frame)
                local isAdding = CS.addingToPanelId == panelId
                local addBtn = header.frame._cdcAddBtn
                if not addBtn then
                    addBtn = CreateFrame("Button", nil, header.frame)
                    addBtn:SetSize(10, 10)
                    addBtn.icon = addBtn:CreateTexture(nil, "OVERLAY")
                    addBtn.icon:SetAllPoints()
                    header.frame._cdcAddBtn = addBtn
                end
                addBtn:ClearAllPoints()
                addBtn:SetPoint("RIGHT", header.frame, "RIGHT", -4, 0)
                addBtn:SetFrameLevel(header.frame:GetFrameLevel() + 2)
                addBtn.icon:SetAtlas(isAdding and "common-icon-minus" or "common-icon-plus", false)
                addBtn.icon:SetVertexColor(0.3, 0.8, 0.3)
                local addBtnPanelId = panelId
                local addBtnRejectMessage = CooldownCompanion:GetPanelManualEntryRejectMessage(panel)
                addBtn:SetScript("OnClick", function()
                    if addBtnRejectMessage then
                        CooldownCompanion:Print(addBtnRejectMessage)
                        return
                    end
                    if CS.addingToPanelId == addBtnPanelId then
                        CS.addingToPanelId = nil
                    else
                        CS.addingToPanelId = addBtnPanelId
                        SelectConfigPanel(addBtnPanelId, { keepPanelMulti = true })
                        CS.collapsedPanels[addBtnPanelId] = nil
                        CS.pendingEditBoxFocus = true
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end)
                -- Wide view: adding lives in the permanent add box under the
                -- preview, so the header button only renders in browse mode.
                addBtn:SetShown(not addBtnRejectMessage and not wideView)

                panelContainer:AddChild(header)
                table.insert(col2RenderedRows, { kind = "header", panelId = panelId, isCollapsed = isCollapsed, widget = header })
                panelMeta.headerWidget = header
                panelMeta.headerFrame = header.frame
                panelMeta.headerText = headerText
                panelMeta.headerColor = {
                    (header.label and select(1, header.label:GetTextColor())) or 1,
                    (header.label and select(2, header.label:GetTextColor())) or 1,
                    (header.label and select(3, header.label:GetTextColor())) or 1,
                }
                panelMeta.count = btnCount

            -- Button list for this panel (skip if collapsed; the wide view
            -- lists panels only - entries live in the preview)
            if not isCollapsed and not wideView then
                local panelButtons = panel.buttons or {}

                if panel.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
                    AddRotationAssistantLockedRow(panelContainer, panelId, {
                        containerId = CS.selectedContainer,
                    })
                else
                    for i, buttonData in ipairs(panelButtons) do
                    local entry = AceGUI:Create("InteractiveLabel")
                    CleanRecycledEntry(entry)
                    local usable = CooldownCompanion:IsButtonUsable(buttonData, panel)
                    local loadAllowed = CooldownCompanion:IsButtonLoadConditionMet(buttonData, panel)

                    local entryName = IsTriggerPanelGroup(panel)
                        and GetTriggerRowDisplayText(buttonData)
                        or GetConfigEntryDisplayName(buttonData, { includeDecorations = true })
                    entry:SetText(entryName or ("Unknown " .. buttonData.type))
                    entry:SetFullWidth(true)
                    entry:SetFontObject(GameFontHighlight)
                    ApplyConfigRowIcon(entry, GetButtonIcon(buttonData), { desaturated = not usable })
                    entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                    if buttonData.type == "spell" then
                        BindConfigShiftTooltip(entry, "spell", ResolveColumn2TooltipSpellId(buttonData), entry.frame, "ANCHOR_RIGHT")
                    elseif buttonData.type == "item" then
                        BindConfigShiftTooltip(entry, "item", buttonData.id, entry.frame, "ANCHOR_RIGHT")
                    elseif CooldownCompanion.IsEquipmentSlotEntry
                        and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
                        local effectiveItem = CooldownCompanion.ResolveEffectiveItem
                            and CooldownCompanion.ResolveEffectiveItem(buttonData, true) or nil
                        if effectiveItem and effectiveItem.trackable and effectiveItem.itemID then
                            BindConfigShiftTooltip(entry, "item", effectiveItem.itemID, entry.frame, "ANCHOR_RIGHT")
                        end
                    end
                    entry:SetUserData(
                        "cdcShiftTooltipExtraLine",
                        CooldownCompanion:HasLocalLoadConditions(buttonData)
                            and "This entry adds load conditions."
                            or nil
                    )

                    -- Selection highlighting: only show if this panel is the selected one
                    if CS.selectedGroup == panelId then
                        if CS.selectedButtons[i] then
                            entry:SetColor(0.4, 0.7, 1.0)
                        elseif CS.selectedButton == i then
                            entry:SetColor(0.4, 0.7, 1.0)
                        elseif not usable then
                            entry:SetColor(0.5, 0.5, 0.5)
                        end
                    elseif not usable then
                        entry:SetColor(0.5, 0.5, 0.5)
                    end

                    -- Right-side row badges
                    local rowFrame = entry.frame
                    local rowBadgeLevel = rowFrame:GetFrameLevel() + 5
                    local warnBadge, overrideBadge, soundBadge, fallbackBadge

                    if not usable and buttonData.enabled ~= false then
                        warnBadge = EnsureRowBadge(rowFrame, "_cdcWarnBtn", "Ping_Marker_Icon_Warning")
                        warnBadge:SetFrameLevel(rowBadgeLevel)
                        if not loadAllowed then
                            SetRowBadgeTooltip(warnBadge, "Hidden by load conditions", 1, 0.3, 0.3)
                        else
                            SetRowBadgeTooltip(warnBadge, "Spell/item unavailable", 1, 0.3, 0.3)
                        end
                        warnBadge:Show()
                    end

                    if CooldownCompanion:HasStyleOverrides(buttonData) then
                        overrideBadge = EnsureRowBadge(
                            rowFrame,
                            "_cdcOverrideBadge",
                            "Crosshair_VehichleCursor_32",
                            OVERRIDE_BADGE_ICON_SIZE
                        )
                        overrideBadge:SetFrameLevel(rowBadgeLevel)
                        SetRowBadgeTooltip(overrideBadge, "Has appearance overrides")
                        overrideBadge:Show()
                    end

                    if CooldownCompanion.HasItemFallbacks(buttonData) then
                        fallbackBadge = EnsureRowBadge(rowFrame, "_cdcFallbackBadge", "banker")
                        fallbackBadge:SetFrameLevel(rowBadgeLevel)
                        SetRowBadgeTooltip(fallbackBadge, "Uses item fallbacks")
                        fallbackBadge:Show()
                    end

                    if buttonData.type == "spell" then
                        local enabledSoundEvents = CooldownCompanion:GetEnabledSoundAlertEventsForButton(buttonData)
                        -- The aura-applied sound is config-only (played by the
                        -- game's aura system, never the runtime engine above),
                        -- so it needs its own badge check.
                        if not enabledSoundEvents
                            and (buttonData.auraTracking or buttonData.addedAs == "aura")
                            and CooldownCompanion:GetAuraAppliedSoundFileForButton(buttonData) then
                            enabledSoundEvents = true
                        end
                        if enabledSoundEvents then
                            soundBadge = EnsureRowBadge(rowFrame, "_cdcSoundBadge", "common-icon-sound")
                            soundBadge:SetFrameLevel(rowBadgeLevel)
                            SetRowBadgeTooltip(soundBadge, "Sound alerts enabled")
                            soundBadge:Show()
                        end
                    end

                    local talentBadge = EnsureRowBadge(rowFrame, "_cdcTalentBadge", "UI-HUD-MicroMenu-SpecTalents-Mouseover")
                    talentBadge:SetFrameLevel(rowBadgeLevel)
                    if buttonData.talentConditions and #buttonData.talentConditions > 0 then
                        SetRowBadgeTooltip(talentBadge, "Has talent conditions")
                        talentBadge:Show()
                    end

                    local disabledBadge
                    if buttonData.enabled == false then
                        disabledBadge = EnsureRowBadge(rowFrame, "_cdcDisabledBadge", "GM-icon-visibleDis-pressed")
                        disabledBadge:SetFrameLevel(rowBadgeLevel)
                        SetRowBadgeTooltip(disabledBadge, "Disabled", 0.6, 0.6, 0.6)
                        disabledBadge:Show()
                    end

                    LayoutRowBadges(rowFrame, disabledBadge, warnBadge, overrideBadge, fallbackBadge, soundBadge, talentBadge)

                    entry:SetCallback("OnClick", function(widget, event, mouseButton)
                        if mouseButton == "LeftButton" and not IsControlKeyDown() and not GetCursorInfo() then
                            -- Auto-select this panel for drag context
                            if CS.selectedGroup ~= panelId then
                                CS.selectedGroup = panelId
                                CS.selectedButton = nil
                                CS.selectedRotationAssistantEntry = nil
                                wipe(CS.selectedButtons)
                            end
                            local cursorX, cursorY = GetScaledCursorPosition(CS.col2Scroll)
                            CS.dragState = {
                                kind = "button",
                                phase = "pending",
                                sourceIndex = i,
                                groupId = panelId,
                                scrollWidget = CS.col2Scroll,
                                widget = entry,
                                startX = cursorX,
                                startY = cursorY,
                                col2RenderedRows = col2RenderedRows,
                            }
                            StartDragTracking()
                        end
                    end)

                    -- Handle clicks via OnMouseUp with drag guard
                    -- Capture upvalues for this button's panel context
                    local btnPanelId = panelId
                    local btnIndex = i
                    local entryFrame = entry.frame
                    entryFrame:SetScript("OnMouseUp", function(self, mouseButton)
                        if CS.dragState and CS.dragState.phase == "active" then return end
                        if mouseButton == "LeftButton" and GetCursorInfo() then
                            if TryReceiveCursorDrop() then return end
                        end
                        if mouseButton == "LeftButton" then
                            -- Auto-select this button's panel
                            SelectConfigButton(btnPanelId, btnIndex, { multi = IsControlKeyDown() })
                            CooldownCompanion:RefreshConfigPanel()
                        elseif mouseButton == "RightButton" then
                            -- Auto-select panel on right-click too
                            SelectConfigButtonPanel(btnPanelId, { clearPanelMulti = true })
                            ShowEntryContextMenu(btnPanelId, btnIndex, buttonData)
                        elseif mouseButton == "MiddleButton" then
                            SelectConfigButtonPanel(btnPanelId)
                            if not CS.moveMenuFrame then
                                CS.moveMenuFrame = CreateFrame("Frame", "CDCMoveMenu", UIParent, "UIDropDownMenuTemplate")
                            end
                            local sourceGroupId = btnPanelId
                            local sourceIndex = btnIndex
                            local entryData = buttonData
                            UIDropDownMenu_Initialize(CS.moveMenuFrame, function(self, level, menuList)
                                level = level or 1
                                if level ~= 1 and not ParseEntryMoveContainerId(menuList) then
                                    return
                                end
                                AddEntryMoveDestinationButtons(
                                    level,
                                    sourceGroupId,
                                    sourceIndex,
                                    entryData,
                                    menuList
                                )
                            end, "MENU")
                            CS.moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                            ToggleDropDownMenu(1, nil, CS.moveMenuFrame, "cursor", 0, 0)
                        end
                    end)

                    panelContainer:AddChild(entry)
                    table.insert(col2RenderedRows, { kind = "button", panelId = panelId, buttonIndex = i, widget = entry })
                    table.insert(panelMeta.buttonRows, {
                        buttonIndex = i,
                        widget = entry,
                        frame = entry.frame,
                        text = entryName or ("Unknown " .. buttonData.type),
                        icon = GetButtonIcon(buttonData),
                        usable = usable,
                        textColor = {
                            (entry.label and select(1, entry.label:GetTextColor())) or 1,
                            (entry.label and select(2, entry.label:GetTextColor())) or 1,
                            (entry.label and select(3, entry.label:GetTextColor())) or 1,
                        },
                        imageSize = entry.image and select(1, entry.image:GetSize()) or 32,
                    })
                    end -- button loop
                end

                BuildInlineAddControls(panelContainer, panelMeta, panel, panelId, btnCount)
            end -- not collapsed
            table.insert(col2PanelMetas, panelMeta)

        end -- panel loop

        CS.lastCol2RenderedRows = col2RenderedRows
        CS.lastCol2PanelMetas = col2PanelMetas

        CS.col2Scroll:DoLayout()

        return
    end

    -- No container selected
    if CS.col2ButtonBar then CS.col2ButtonBar:Hide() end
    if not CS.selectedContainer then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Select a group first")
        label:SetFullWidth(true)
        CS.col2Scroll:AddChild(label)
        return
    end

end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn2 = RefreshColumn2
ST._ShowEntryContextMenu = ShowEntryContextMenu
