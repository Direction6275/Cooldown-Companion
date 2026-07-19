--[[
    CooldownCompanion - Config/Navigator
    Consolidated Group and Panel navigation, search, and rail destinations.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local CleanRecycledEntry = ST._CleanRecycledEntry
local ApplyConfigRowIcon = ST._ApplyConfigRowIcon
local ApplyConfigTextRow = ST._ApplyConfigTextRow
local CompactUntitledInlineGroupConfig = ST._CompactUntitledInlineGroupConfig
local SetupGroupRowIndicators = ST._SetupGroupRowIndicators
local GetConfigRowBadgeReserve = ST._GetConfigRowBadgeReserve
local SetupColumn1MarkerRow = ST._SetupColumn1MarkerRow
local GetContainerIcon = ST._GetContainerIcon
local GetButtonIcon = ST._GetButtonIcon
local OpenContainerIconPicker = ST._OpenContainerIconPicker
local IsValidIconTexture = ST._IsValidIconTexture
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local CancelDrag = ST._CancelDrag
local StartDragTracking = ST._StartDragTracking
local GetScaledCursorPosition = ST._GetScaledCursorPosition
local BuildGroupExportData = ST._BuildGroupExportData
local BuildContainerExportData = ST._BuildContainerExportData
local EncodeExportData = ST._EncodeExportData
local ContainersHaveForeignSpecs = ST._ContainersHaveForeignSpecs
local NotifyTutorialAction = ST._NotifyTutorialAction
local IsConfigFinderActive = ST._IsConfigFinderActive
local BuildConfigFinderResults = ST._BuildConfigFinderResults
local SelectConfigFinderResult = ST._SelectConfigFinderResult
local ClearConfigPrimarySelection = ST._ClearConfigPrimarySelection
local SelectConfigContainer = ST._SelectConfigContainer
local ToggleConfigContainerMultiSelect = ST._ToggleConfigContainerMultiSelect
local SelectConfigPanel = ST._SelectConfigPanel
local ToggleConfigPanelMultiSelect = ST._ToggleConfigPanelMultiSelect
local GetConfigPanelTypeBadgeAtlas = ST._GetConfigPanelTypeBadgeAtlas
local GetConfigPanelEntryCount = ST._GetConfigPanelEntryCount
local ConfigPanelHasWarning = ST._ConfigPanelHasWarning
local AddClassAccentSpacer = ST._AddClassAccentSpacer
local SetHideActiveCurrentClassPanels = ST._SetHideActiveCurrentClassPanels
local ClearOtherClassBrowseState = ST._ResetOtherClassLibraryState
local TryReceiveCursorDrop = ST._TryReceiveCursorDrop

local GenerateGroupName

local TREE = {
    GROUP_ROW_HEIGHT = 42,
    GROUP_ICON_SIZE = 32,
    PANEL_ROW_HEIGHT = 28,
    PANEL_ICON_SIZE = 16,
    PANEL_INDENT = 18,
    ENTRY_ROW_HEIGHT = 24,
    ENTRY_ICON_SIZE = 14,
    ENTRY_INDENT = 38,
    PANEL_META_WIDTH = 42,
    ICON_GAP = 6,
}

local function GetNavigatorClassColor()
    local _, classKey = UnitClass("player")
    local color = classKey and C_ClassColor.GetClassColor(classKey)
    return color and color.r or 0.40, color and color.g or 0.67, color and color.b or 1.0
end

local function EnsureRailDestinationButton(host, key)
    host._cdcDestinationButtons = host._cdcDestinationButtons or {}
    local button = host._cdcDestinationButtons[key]
    if button then return button end

    button = CreateFrame("Button", nil, host)
    -- Keep the existing tutorial anchor contract, which expects an AceGUI-
    -- shaped object with a .frame field.
    button.frame = button
    button:RegisterForClicks("LeftButtonUp")
    button:SetHeight(24)

    button.wash = button:CreateTexture(nil, "BACKGROUND")
    button.wash:SetAllPoints()
    button.wash:Hide()

    button.hover = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    button.hover:SetAllPoints()
    button.hover:SetColorTexture(1, 1, 1, 0.08)
    button.hover:Hide()

    button.accent = button:CreateTexture(nil, "ARTWORK")
    button.accent:SetWidth(3)
    button.accent:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.accent:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    button.accent:Hide()

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(16, 16)
    button.icon:SetPoint("LEFT", button, "LEFT", 8, 0)

    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.label:SetPoint("LEFT", button.icon, "RIGHT", 7, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetWordWrap(false)

    button:SetScript("OnEnter", function(self)
        self.hover:Show()
        self.label:SetTextColor(1, 0.82, 0)
    end)
    button:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if self._cdcSelected then
            self.label:SetTextColor(1, 1, 1)
        else
            self.label:SetTextColor(0.82, 0.78, 0.70)
        end
    end)

    host._cdcDestinationButtons[key] = button
    return button
end

local function ConfigureRailDestinationButton(button, opts)
    local r, g, b = GetNavigatorClassColor()
    button.label:SetText(opts.label)
    button.icon:SetAtlas(opts.atlas, false)
    button.icon:SetVertexColor(opts.iconR or 0.82, opts.iconG or 0.78, opts.iconB or 0.70, 1)
    button.wash:SetColorTexture(r, g, b, 0.13)
    button.accent:SetColorTexture(r, g, b, 0.95)
    button._cdcSelected = opts.selected == true
    button.wash:SetShown(button._cdcSelected)
    button.accent:SetShown(button._cdcSelected)
    button.label:SetTextColor(
        button._cdcSelected and 1 or 0.82,
        button._cdcSelected and 1 or 0.78,
        button._cdcSelected and 1 or 0.70
    )
    button:SetScript("OnClick", opts.onClick)
    button:Show()
end

local function UpdateRailDestinations()
    local host = CS.col1DestinationBar
    if not host then return end
    if CS.talentPickerMode then
        host:Hide()
        return
    end

    local r, g, b = GetNavigatorClassColor()
    if not host._cdcDividerLeft then
        host._cdcDividerLeft = host:CreateTexture(nil, "ARTWORK")
        host._cdcDividerRight = host:CreateTexture(nil, "ARTWORK")
        host._cdcDividerOrnament = host:CreateTexture(nil, "ARTWORK")
        host._cdcDividerLeft:SetHeight(1)
        host._cdcDividerRight:SetHeight(1)
        host._cdcDividerOrnament:SetSize(5, 5)
        host._cdcDividerLeft:SetPoint("LEFT", host, "LEFT", 8, 0)
        host._cdcDividerLeft:SetPoint("RIGHT", host, "CENTER", -6, 0)
        host._cdcDividerRight:SetPoint("LEFT", host, "CENTER", 6, 0)
        host._cdcDividerRight:SetPoint("RIGHT", host, "RIGHT", -8, 0)
        host._cdcDividerOrnament:SetPoint("CENTER", host, "CENTER", 0, 0)
    end
    host._cdcDividerLeft:SetColorTexture(r, g, b, 0.38)
    host._cdcDividerRight:SetColorTexture(r, g, b, 0.38)
    host._cdcDividerOrnament:SetColorTexture(r, g, b, 0.72)
    host._cdcDividerLeft:ClearAllPoints()
    host._cdcDividerLeft:SetPoint("TOPLEFT", host, "TOPLEFT", 8, -4)
    host._cdcDividerLeft:SetPoint("RIGHT", host, "TOP", -6, -4)
    host._cdcDividerRight:ClearAllPoints()
    host._cdcDividerRight:SetPoint("LEFT", host, "TOP", 6, -4)
    host._cdcDividerRight:SetPoint("TOPRIGHT", host, "TOPRIGHT", -8, -4)
    host._cdcDividerOrnament:ClearAllPoints()
    host._cdcDividerOrnament:SetPoint("CENTER", host, "TOP", 0, -4)

    local resources = EnsureRailDestinationButton(host, "resources")
    resources:ClearAllPoints()
    resources:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -8)
    resources:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -8)
    ConfigureRailDestinationButton(resources, {
        label = "Resources",
        atlas = "ui_adv_health",
        selected = CS.resourcesEntrySelected == true,
        onClick = function()
            if ST._SelectConfigResourcesEntry then
                ST._SelectConfigResourcesEntry()
            end
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    CS.col1ResourcesButton = resources

    local castFrames = EnsureRailDestinationButton(host, "cast-frames")
    castFrames:ClearAllPoints()
    castFrames:SetPoint("TOPLEFT", resources, "BOTTOMLEFT", 0, 0)
    castFrames:SetPoint("TOPRIGHT", resources, "BOTTOMRIGHT", 0, 0)
    ConfigureRailDestinationButton(castFrames, {
        label = "Cast Bar & Unit Frames",
        atlas = "groupfinder-icon-friend",
        selected = CS.castFramesEntrySelected == true,
        onClick = function()
            if ST._SelectConfigCastFramesEntry then
                ST._SelectConfigCastFramesEntry()
            end
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    host:Show()
end

local function ConfigureTreeExpandButton(entry, isExpanded, isPinned, onClick)
    local button = entry.frame._cdcTreeExpandButton
    if not button then
        button = CreateFrame("Button", nil, entry.frame)
        button:SetSize(16, 16)
        button:RegisterForClicks("LeftButtonUp")
        button:SetPropagateMouseClicks(false)
        button:SetPropagateMouseMotion(false)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(10, 10)
        button.icon:SetPoint("CENTER")
        entry.frame._cdcTreeExpandButton = button
    end

    button:ClearAllPoints()
    button:SetPoint("RIGHT", entry.frame, "RIGHT", -4, 0)
    button:SetFrameLevel(entry.frame:GetFrameLevel() + 25)
    button.icon:SetAtlas(isExpanded and "common-icon-minus" or "common-icon-plus", false)
    local baseR, baseG, baseB = 0.67, 0.59, 0.46
    if isPinned then
        baseR, baseG, baseB = 1, 0.72, 0.12
    end
    button.icon:SetVertexColor(baseR, baseG, baseB, 0.9)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" then onClick() end
    end)
    button:SetScript("OnEnter", function(self)
        button.icon:SetVertexColor(1, 0.82, 0, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if isPinned then
            GameTooltip:AddLine("Collapse pinned Group")
        else
            GameTooltip:AddLine(isExpanded and "Collapse Group" or "Expand and keep open")
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        button.icon:SetVertexColor(baseR, baseG, baseB, 0.9)
        GameTooltip:Hide()
    end)
    button:Show()
    return 22
end

local function OffsetGroupStatusBadges(entry, rightOffset)
    local offsetX = -4 - (rightOffset or 0)
    for _, badge in ipairs(entry.frame._cdcBadges or {}) do
        if badge:IsShown() then
            badge:ClearAllPoints()
            badge:SetPoint("RIGHT", entry.frame, "RIGHT", offsetX, 0)
            offsetX = offsetX - badge:GetWidth() - 2
        end
    end
end

local function ConfigureTreePanelMeta(entry, entryCount, panelDisabled, hasWarning)
    local meta = entry.frame._cdcTreePanelMeta
    if not meta then
        meta = CreateFrame("Frame", nil, entry.frame)
        meta:SetSize(TREE.PANEL_META_WIDTH, 18)
        meta.status = CreateFrame("Button", nil, meta)
        meta.status:SetSize(14, 14)
        meta.status:SetPoint("RIGHT", meta, "RIGHT", -22, 0)
        meta.status:SetPropagateMouseMotion(false)
        meta.status.icon = meta.status:CreateTexture(nil, "OVERLAY")
        meta.status.icon:SetAllPoints()
        meta.status:SetScript("OnLeave", function() GameTooltip:Hide() end)
        meta.count = meta:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        meta.count:SetWidth(18)
        meta.count:SetPoint("RIGHT", meta, "RIGHT", 0, 0)
        meta.count:SetJustifyH("RIGHT")
        entry.frame._cdcTreePanelMeta = meta
    end

    meta:ClearAllPoints()
    meta:SetPoint("RIGHT", entry.frame, "RIGHT", -4, 0)
    meta:SetFrameLevel(entry.frame:GetFrameLevel() + 12)
    if not InCombatLockdown() and meta.status.SetPropagateMouseClicks then
        meta.status:EnableMouse(true)
        meta.status:SetPropagateMouseClicks(true)
    else
        meta.status:EnableMouse(false)
    end
    meta.count:SetText(tostring(entryCount or 0))
    meta.count:SetTextColor(0.52, 0.49, 0.43, 1)
    meta.status:SetScript("OnEnter", nil)
    if panelDisabled then
        meta.status.icon:SetAtlas("GM-icon-visibleDis-pressed", false)
        meta.status.icon:SetVertexColor(0.65, 0.65, 0.65, 1)
        meta.status:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Panel disabled", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        meta.status:Show()
    elseif hasWarning then
        meta.status.icon:SetAtlas("Ping_Marker_Icon_Warning", false)
        meta.status.icon:SetVertexColor(1, 1, 1, 1)
        meta.status:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("One or more entries are unavailable", 1, 0.3, 0.3)
            GameTooltip:Show()
        end)
        meta.status:Show()
    else
        meta.status:Hide()
    end
    meta:Show()
end

local function ConfigureGroupHeaderLayout(entry, rightReserve)
    entry._cdcAfterConfigRowLayout = function()
        local frame = entry.frame
        local label = entry.label
        local icon = entry.image
        local compact = CS.compactConfigRows == true
        local reserve = rightReserve or 4
        local leftInset = 2

        label:ClearAllPoints()
        if compact or not icon or not icon:IsShown() then
            label:SetPoint("LEFT", frame, "LEFT", leftInset, 0)
        else
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", frame, "LEFT", leftInset, 0)
            label:SetPoint("LEFT", icon, "RIGHT", TREE.ICON_GAP, 0)
        end
        label:SetPoint("RIGHT", frame, "RIGHT", -reserve, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
    end
    entry:_cdcAfterConfigRowLayout()
end

local function ConfigureNestedPanelAccent(groupUnit, header, firstPanel, lastPanel, classColor)
    local frame = groupUnit and groupUnit.frame
    if not frame then return end
    local accent = frame._cdcNestedPanelAccent
    if not accent then
        accent = frame:CreateTexture(nil, "ARTWORK")
        frame._cdcNestedPanelAccent = accent
    end
    accent:ClearAllPoints()
    if not (firstPanel and lastPanel and classColor) then
        frame._cdcNestedPanelAccentActive = nil
        accent:Hide()
        return
    end
    frame._cdcNestedPanelAccentActive = true
    accent:SetColorTexture(classColor.r, classColor.g, classColor.b, 0.8)
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", header.frame, "BOTTOMLEFT", 2, 0)
    accent:SetPoint("BOTTOMLEFT", lastPanel.frame, "BOTTOMLEFT", 2, 0)
    accent:SetShown(CS.compactConfigRows ~= true)
end

local function OpenContainerLoadConditions(containerId)
    SelectConfigContainer(containerId)
    CS.selectedContainerTab = "loadconditions"
    CooldownCompanion:RefreshConfigPanel()
end

local function TrimGroupName(name)
    if name == nil then return "" end
    return tostring(name):match("^%s*(.-)%s*$") or ""
end

local function IsGenericGroupName(name)
    local trimmed = TrimGroupName(name)
    return trimmed == ""
        or trimmed == "New Group"
        or trimmed:match("^New Group%s+%d+$") ~= nil
        or trimmed == "Group"
        or trimmed:match("^Group%s+%d+$") ~= nil
end

local function EnsureGenericGroupRenameBadge(entry)
    local badge = entry.frame._cdcGenericRenameBadge
    if not badge then
        badge = CreateFrame("Button", nil, entry.frame)
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
        entry.frame._cdcGenericRenameBadge = badge
    end

    badge:SetFrameLevel(entry.frame:GetFrameLevel() + 25)
    return badge
end

local function ConfigureGenericGroupRenameBadge(entry, container, containerId, rightReserve)
    local badge = EnsureGenericGroupRenameBadge(entry)
    badge:ClearAllPoints()
    badge:SetScript("OnClick", nil)

    if not IsGenericGroupName(container and container.name) then
        badge:Hide()
        return 0
    end

    local currentName = TrimGroupName(container and container.name)
    if currentName == "" then
        currentName = "New Group"
    end

    badge.icon:SetAtlas("QuestLegendary", false)
    badge.icon:SetVertexColor(1, 0.82, 0, 0.85)
    badge:SetPoint("RIGHT", entry.frame, "RIGHT", -((rightReserve or 4) + 2), 0)
    badge:SetScript("OnClick", function(_, button)
        if button ~= "LeftButton" then return end
        GameTooltip:Hide()
        ShowPopupAboveConfig("CDC_RENAME_GROUP", currentName, { containerId = containerId })
    end)
    badge:Show()
    return 18
end

local PANEL_CREATION_MODES = {
    { mode = "icons", label = "Icon Panel" },
    { mode = "bars", label = "Bar Panel" },
    { mode = "text", label = "Text Panel" },
    { mode = "textures", label = "Texture Panel" },
    { mode = "trigger", label = "Trigger Panel" },
    { mode = ST.DISPLAY_MODE_ROTATION_ASSISTANT, label = ST.ROTATION_ASSISTANT_NAME or "Assistant Panel" },
}

local function BuildContainerExportPayload(db, containerId, container)
    local sortedPanels = CooldownCompanion:GetPanels(containerId)
    local panels = {}
    for _, entry in ipairs(sortedPanels) do
        local panelData = BuildGroupExportData(entry.group)
        panelData._originalGroupId = entry.groupId
        panels[#panels + 1] = panelData
    end
    return {
        type = "container",
        version = 1,
        container = BuildContainerExportData(container),
        panels = panels,
        _originalContainerId = containerId,
    }
end

local function BuildSelectedContainersExportPayload(db, selectedGroups)
    local orderedCids = {}
    for cid in pairs(selectedGroups) do
        local container = db.groupContainers[cid]
        if container then
            orderedCids[#orderedCids + 1] = {
                cid = cid,
                order = CooldownCompanion:GetOrderForSpec(container, CooldownCompanion._currentSpecId, cid),
            }
        end
    end
    table.sort(orderedCids, function(a, b) return a.order < b.order end)

    local exportContainers = {}
    for _, item in ipairs(orderedCids) do
        local container = db.groupContainers[item.cid]
        if container then
            local payload = BuildContainerExportPayload(db, item.cid, container)
            exportContainers[#exportContainers + 1] = {
                container = payload.container,
                panels = payload.panels,
                _originalContainerId = payload._originalContainerId,
            }
        end
    end

    return {
        type = "containers",
        version = 1,
        containers = exportContainers,
    }
end

local function CanPanelMoveToContainer(panelId, containerId)
    if CooldownCompanion.ResolveContainerClassScope then
        local scope = CooldownCompanion:ResolveContainerClassScope(containerId)
        if scope and scope.isInvalid then return false end
    end
    if CooldownCompanion.CanMovePanelToContainer then
        return CooldownCompanion:CanMovePanelToContainer(panelId, containerId) == true
    end
    return true
end

local function BuildFlatContainerOrder(db, excludedContainerId, panelId)
    local flattened = {}
    for containerId, container in pairs(db.groupContainers or {}) do
        if containerId ~= excludedContainerId and (not panelId or CanPanelMoveToContainer(panelId, containerId)) then
            table.insert(flattened, {
                kind = "container",
                id = containerId,
                name = container.name or ("Group " .. tostring(containerId)),
                order = CooldownCompanion:GetOrderForSpec(container, CooldownCompanion._currentSpecId, containerId),
            })
        end
    end
    table.sort(flattened, function(a, b) return a.order < b.order end)
    return flattened
end

local function ShowPanelContextMenu(panelId, containerId)
    local db = CooldownCompanion.db.profile
    local panel = db.groups and db.groups[panelId]
    local container = db.groupContainers and db.groupContainers[containerId]
    if not (panel and container) then return end

    if not CS.panelContextMenu then
        CS.panelContextMenu = CreateFrame("Frame", "CDCPanelContextMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(CS.panelContextMenu, function(_, level, menuList)
        level = level or 1
        if level == 1 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Rename"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                ShowPopupAboveConfig("CDC_RENAME_GROUP", panel.name or "Panel", { groupId = panelId })
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = panel.enabled ~= false and "Disable" or "Enable"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                panel.enabled = not (panel.enabled ~= false)
                CooldownCompanion:RefreshGroupFrame(panelId)
                CooldownCompanion:RefreshConfigPanel()
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = "Load Conditions"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                SelectConfigPanel(panelId, { containerId = containerId })
                CS.selectedTab = "loadconditions"
                CS.panelSettingsTab = "loadconditions"
                CooldownCompanion:RefreshConfigPanel()
            end
            UIDropDownMenu_AddButton(info, level)

            if not (CooldownCompanion.IsGroupCursorAnchored and CooldownCompanion:IsGroupCursorAnchored(panel)) then
                info = UIDropDownMenu_CreateInfo()
                info.text = panel.locked == false and "Lock Anchor" or "Unlock Anchor"
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    if panel.locked == false then
                        panel.locked = nil
                        CooldownCompanion:Print((panel.name or "Panel") .. " locked.")
                    else
                        panel.locked = false
                        CooldownCompanion:Print((panel.name or "Panel") .. " unlocked. Drag to reposition.")
                    end
                    CooldownCompanion:RefreshGroupFrame(panelId)
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(info, level)
            end

            if CooldownCompanion:IsIconLikeDisplayMode(panel.displayMode) then
                info = UIDropDownMenu_CreateInfo()
                info.text = panel.anchorEligible ~= false and "Exclude from Auto-Anchoring" or "Include in Auto-Anchoring"
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    panel.anchorEligible = panel.anchorEligible ~= false and false or nil
                    CooldownCompanion:EvaluateResourceBars()
                    CooldownCompanion:UpdateAnchorStacking()
                    CooldownCompanion:EvaluateCastBar()
                    CooldownCompanion:EvaluateFrameAnchoring()
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(info, level)
            end

            if panel.displayMode ~= ST.DISPLAY_MODE_ROTATION_ASSISTANT then
                local switchModes = {
                    { mode = "icons", label = "Icons" },
                    { mode = "bars", label = "Bars" },
                    { mode = "text", label = "Text" },
                    { mode = "textures", label = "Textures" },
                }
                for _, modeInfo in ipairs(switchModes) do
                    if panel.displayMode ~= modeInfo.mode then
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "Switch to " .. modeInfo.label
                        info.notCheckable = true
                        local targetMode = modeInfo.mode
                        info.func = function()
                            CloseDropDownMenus()
                            if CooldownCompanion:ChangePanelDisplayMode(panelId, targetMode) then
                                if targetMode == "textures" then
                                    CS.pendingTexturePickerOpen = panelId
                                    SelectConfigPanel(panelId, { containerId = containerId })
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
                local newPanelId = CooldownCompanion:DuplicatePanel(containerId, panelId)
                if newPanelId then
                    SelectConfigPanel(newPanelId, { containerId = containerId })
                    CooldownCompanion:RefreshConfigPanel()
                end
            end
            UIDropDownMenu_AddButton(info, level)

            local copyStyleMode = panel.displayMode == "bars" and "bars"
                or ((panel.displayMode == nil or panel.displayMode == "icons") and "icons" or nil)
            if copyStyleMode then
                local _, copyPanelOrder = CooldownCompanion:GetDirectStyleCopyPanelList(copyStyleMode, panelId)
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

            local moveTargets = BuildFlatContainerOrder(db, containerId, panelId)
            if #moveTargets > 0 then
                info = UIDropDownMenu_CreateInfo()
                info.text = "Move to Group"
                info.notCheckable = true
                info.hasArrow = true
                info.menuList = "MOVE_TO_GROUP"
                UIDropDownMenu_AddButton(info, level)
            end

            info = UIDropDownMenu_CreateInfo()
            info.text = "Export"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                local containerData = BuildContainerExportData(container)
                containerData.name = panel.name or "Panel"
                local payload = {
                    type = "container",
                    version = 1,
                    container = containerData,
                    panels = { BuildGroupExportData(panel) },
                    _originalContainerId = containerId,
                }
                ShowPopupAboveConfig("CDC_EXPORT_GROUP", nil, { exportString = EncodeExportData(payload) })
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = "|cffff4444Delete|r"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                ShowPopupAboveConfig("CDC_DELETE_PANEL", panel.name or "Panel", {
                    containerId = containerId,
                    panelId = panelId,
                })
            end
            UIDropDownMenu_AddButton(info, level)
        elseif menuList == "COPY_STYLE_FROM_PANEL" then
            local copyStyleMode = panel.displayMode == "bars" and "bars" or "icons"
            local copyPanelList, copyPanelOrder = CooldownCompanion:GetDirectStyleCopyPanelList(copyStyleMode, panelId)
            for _, sourcePanelId in ipairs(copyPanelOrder) do
                local sourceName = copyPanelList[sourcePanelId] or ("Panel " .. tostring(sourcePanelId))
                local info = UIDropDownMenu_CreateInfo()
                info.text = sourceName
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    ShowPopupAboveConfig("CDC_CONFIRM_PANEL_STYLE_COPY", sourceName, {
                        mode = copyStyleMode,
                        sourceGroupId = sourcePanelId,
                        targetGroupId = panelId,
                    })
                end
                UIDropDownMenu_AddButton(info, level)
            end
        elseif menuList == "MOVE_TO_GROUP" then
            for _, target in ipairs(BuildFlatContainerOrder(db, containerId, panelId)) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = target.name
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    if CooldownCompanion:MovePanel(panelId, target.id) then
                        CS.expandedContainer = target.id
                        SelectConfigPanel(panelId, { containerId = target.id })
                        CooldownCompanion:RefreshConfigPanel()
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end, "MENU")
    CS.panelContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.panelContextMenu, "cursor", 0, 0)
end

ST._ShowPanelContextMenu = ShowPanelContextMenu

local function BuildColumn1ContainerStats(db, containerIds)
    local statsByContainer = {}
    if not containerIds or not next(containerIds) then return statsByContainer end

    local containers = db.groupContainers or {}

    for _, group in pairs(db.groups or {}) do
        local containerId = group and group.parentContainerId
        if containerId and containerIds[containerId] then
            local stats = statsByContainer[containerId]
            if not stats then
                stats = {
                    panelCount = 0,
                    hasButtons = false,
                    hasActivePanel = false,
                }
                statsByContainer[containerId] = stats
            end

            stats.panelCount = stats.panelCount + 1
            if CooldownCompanion:GroupHasUsableButtons(group, {
                checkLoadConditions = false,
                ignoreSpellAvailability = true,
            }) then
                stats.hasButtons = true

                local container = containers[containerId]
                if container and container.enabled ~= false and not stats.hasActivePanel then
                    local active = CooldownCompanion:IsGroupActive(nil, {
                        group = group,
                        requireButtons = true,
                        checkCharVisibility = false,
                        checkLoadConditions = true,
                    })
                    if active then
                        stats.hasActivePanel = true
                    end
                end
            end
        end
    end

    return statsByContainer
end

local function ShowContainerContextMenu(db, containerId, container)
    if not CS.groupContextMenu then
        CS.groupContextMenu = CreateFrame("Frame", "CDCGroupContextMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(CS.groupContextMenu, function(self, level, menuList)
        level = level or 1
        if level == 1 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Rename"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                ShowPopupAboveConfig("CDC_RENAME_GROUP", container.name, { containerId = containerId })
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = container.isGlobal and "Move to Current Class" or "Make Global"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                if container.isGlobal and ContainersHaveForeignSpecs({ container }, false) then
                    ShowPopupAboveConfig("CDC_UNGLOBAL_GROUP", container.name, { containerId = containerId })
                    return
                end
                CooldownCompanion:ToggleGroupGlobal(containerId)
                CooldownCompanion:RefreshConfigPanel()
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = (container.enabled ~= false) and "Disable" or "Enable"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                container.enabled = not (container.enabled ~= false)
                CooldownCompanion:RefreshContainerPanels(containerId)
                CooldownCompanion:RefreshConfigPanel()
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = "Duplicate"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                local newContainerId = CooldownCompanion:DuplicateGroup(containerId)
                if newContainerId then
                    SelectConfigContainer(newContainerId)
                    CooldownCompanion:RefreshConfigPanel()
                end
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = next(CS.selectedGroups) and "Export Selected" or "Export"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                local payload = next(CS.selectedGroups)
                    and BuildSelectedContainersExportPayload(db, CS.selectedGroups)
                    or BuildContainerExportPayload(db, containerId, container)
                local exportString = EncodeExportData(payload)
                ShowPopupAboveConfig("CDC_EXPORT_GROUP", nil, { exportString = exportString })
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = container.locked and "Unlock" or "Lock"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                container.locked = not container.locked
                CooldownCompanion:UpdateContainerDragHandle(containerId, container.locked)
                CooldownCompanion:RefreshContainerPanels(containerId)
                CooldownCompanion:RefreshConfigPanel()
            end
            UIDropDownMenu_AddButton(info, level)

            do
                local isCurrentlyEligible
                if container.isGlobal then
                    isCurrentlyEligible = container.anchorEligible == true
                else
                    isCurrentlyEligible = container.anchorEligible ~= false
                end
                info = UIDropDownMenu_CreateInfo()
                info.text = isCurrentlyEligible and "Exclude from Auto-Anchoring" or "Include in Auto-Anchoring"
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    local fresh = db.groupContainers[containerId]
                    if not fresh then return end
                    if fresh.isGlobal then
                        fresh.anchorEligible = not fresh.anchorEligible or nil
                    else
                        if fresh.anchorEligible ~= false then
                            fresh.anchorEligible = false
                        else
                            fresh.anchorEligible = nil
                        end
                    end
                    CooldownCompanion:EvaluateResourceBars()
                    CooldownCompanion:UpdateAnchorStacking()
                    CooldownCompanion:EvaluateCastBar()
                    CooldownCompanion:EvaluateFrameAnchoring()
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(info, level)
            end

            info = UIDropDownMenu_CreateInfo()
            info.text = "Spec Filter"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                OpenContainerLoadConditions(containerId)
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = "Set Group Icon..."
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                OpenContainerIconPicker(containerId)
            end
            UIDropDownMenu_AddButton(info, level)

            if IsValidIconTexture(container.manualIcon) then
                info = UIDropDownMenu_CreateInfo()
                info.text = "Clear Custom Icon"
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    local fresh = db.groupContainers[containerId]
                    if fresh then
                        fresh.manualIcon = nil
                        CooldownCompanion:RefreshConfigPanel()
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end

            info = UIDropDownMenu_CreateInfo()
            info.text = "Add Panel"
            info.notCheckable = true
            info.hasArrow = true
            info.menuList = "ADD_PANEL"
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            info.text = "|cffff4444Delete|r"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                ShowPopupAboveConfig("CDC_DELETE_GROUP", container.name, { containerId = containerId })
            end
            UIDropDownMenu_AddButton(info, level)
        elseif menuList == "ADD_PANEL" then
            for _, modeInfo in ipairs(PANEL_CREATION_MODES) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = modeInfo.label
                info.notCheckable = true
                local targetMode = modeInfo.mode
                info.func = function()
                    CloseDropDownMenus()
                    local newPanelId = CooldownCompanion:CreatePanel(containerId, targetMode)
                    if newPanelId then
                        SelectConfigPanel(newPanelId, {
                            containerId = containerId,
                            keepPanelMulti = true,
                        })
                        local newPanel = CooldownCompanion.db.profile.groups[newPanelId]
                        local acceptsManualEntries = not CooldownCompanion.CanPanelAcceptManualEntry
                            or CooldownCompanion:CanPanelAcceptManualEntry(newPanel)
                        if acceptsManualEntries then
                            CS.addingToPanelId = newPanelId
                            CS.pendingEditBoxFocus = true
                        else
                            CS.addingToPanelId = nil
                            CS.pendingEditBoxFocus = false
                        end
                        CooldownCompanion:RefreshConfigPanel()
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end, "MENU")

    CS.groupContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.groupContextMenu, "cursor", 0, 0)
end

local function ClearColumn1ButtonBar()
    for _, widget in ipairs(CS.col1BarWidgets) do
        local frame = widget and widget.frame
        if frame and frame._cdcHideActiveOtherClassBrowse then
            frame:SetScript("OnEnter", nil)
            frame:SetScript("OnLeave", nil)
            frame._cdcHideActiveOtherClassBrowse = nil
            GameTooltip:Hide()
        end
        widget:Release()
    end
    wipe(CS.col1BarWidgets)
    CS.col1ResourcesButton = nil
    CS.col1CreateButton = nil
    if CS.col1ButtonBar then
        CS.col1ButtonBar._topRowBtns = nil
        CS.col1ButtonBar:SetScript("OnSizeChanged", nil)
    end
end

local function IsCreateTargetContainer(containerId)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local container = db and db.groupContainers and db.groupContainers[containerId]
    if not container then
        return false
    end
    if CooldownCompanion.ResolveContainerClassScope then
        local scope = CooldownCompanion:ResolveContainerClassScope(container)
        return scope and not scope.isInvalid and not scope.isOtherClass
    end
    return true
end

local function ResolveCreateTargetContainer()
    if IsCreateTargetContainer(CS.selectedContainer) then
        return CS.selectedContainer
    end
    if IsCreateTargetContainer(CS.lastActiveContainer) then
        return CS.lastActiveContainer
    end

    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local ordered = db and BuildFlatContainerOrder(db) or {}
    for _, item in ipairs(ordered) do
        if IsCreateTargetContainer(item.id) then
            return item.id
        end
    end
    return nil
end

local function CreateGroupFromRail()
    local containerId, groupId = CooldownCompanion:CreateGroup(GenerateGroupName("New Group"))
    SelectConfigContainer(containerId)
    CooldownCompanion:RefreshConfigPanel()
    if NotifyTutorialAction then
        NotifyTutorialAction("group_created", {
            containerId = containerId,
            groupId = groupId,
        })
    end
end

local function CreatePanelFromRail(containerId, displayMode, opts)
    if not (containerId and ST._CreatePanelInSelectedContainer) then
        return
    end
    ST._CreatePanelInSelectedContainer(displayMode, opts, containerId)
end

local function EnsureRailCreateMenu()
    if not CS.railCreateMenu then
        CS.railCreateMenu = CreateFrame("Frame", "CDCRailCreateMenu", UIParent, "UIDropDownMenuTemplate")
    end
    return CS.railCreateMenu
end

local function ShowRailCreateMenu()
    local targetId = ResolveCreateTargetContainer()
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local target = targetId and db and db.groupContainers and db.groupContainers[targetId]
    local targetName = target and target.name or nil
    local targetSuffix = targetName and (" in " .. targetName) or ""
    local menu = EnsureRailCreateMenu()

    UIDropDownMenu_Initialize(menu, function(_, level, menuList)
        level = level or 1
        if level == 1 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "New Group"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                CreateGroupFromRail()
            end
            UIDropDownMenu_AddButton(info, level)

            for _, modeInfo in ipairs({ PANEL_CREATION_MODES[1], PANEL_CREATION_MODES[2] }) do
                info = UIDropDownMenu_CreateInfo()
                info.text = "New " .. modeInfo.label .. targetSuffix
                info.notCheckable = true
                info.disabled = targetId == nil
                local displayMode = modeInfo.mode
                if ST._AddPanelTypeMenuTooltip then
                    ST._AddPanelTypeMenuTooltip(info, displayMode)
                end
                info.func = function()
                    CloseDropDownMenus()
                    CreatePanelFromRail(targetId, displayMode, {
                        verticalStyle = displayMode == "bars",
                        notifyTutorial = displayMode == "icons",
                    })
                end
                UIDropDownMenu_AddButton(info, level)
            end

            info = UIDropDownMenu_CreateInfo()
            info.text = "More Panel Types..."
            info.notCheckable = true
            info.hasArrow = true
            info.disabled = targetId == nil
            info.menuList = "MORE_PANEL_TYPES"
            UIDropDownMenu_AddButton(info, level)
        elseif menuList == "MORE_PANEL_TYPES" then
            for index = 3, #PANEL_CREATION_MODES do
                local modeInfo = PANEL_CREATION_MODES[index]
                local info = UIDropDownMenu_CreateInfo()
                info.text = "New " .. modeInfo.label .. targetSuffix
                info.notCheckable = true
                local displayMode = modeInfo.mode
                if ST._AddPanelTypeMenuTooltip then
                    ST._AddPanelTypeMenuTooltip(info, displayMode)
                end
                info.func = function()
                    CloseDropDownMenus()
                    CreatePanelFromRail(targetId, displayMode, {
                        verticalStyle = displayMode == "text",
                    })
                end
                UIDropDownMenu_AddButton(info, level)
            end

            local info = UIDropDownMenu_CreateInfo()
            info.text = "Add Missing CDM Panels" .. targetSuffix
            info.notCheckable = true
            if ST._AddCDMStarterMenuTooltip then
                ST._AddCDMStarterMenuTooltip(info)
            end
            info.func = function()
                CloseDropDownMenus()
                if ST._CreateMissingCDMPanelsInSelectedContainer then
                    ST._CreateMissingCDMPanelsInSelectedContainer(targetId)
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, menu, "cursor", 0, 0)
end

local function PopulateColumn1ButtonBar()
    if not CS.col1ButtonBar then
        return
    end

    ClearColumn1ButtonBar()

    local createBtn = AceGUI:Create("Button")
    createBtn:SetText("Create...")
    createBtn:SetCallback("OnClick", ShowRailCreateMenu)
    createBtn.frame:SetParent(CS.col1ButtonBar)
    createBtn.frame:ClearAllPoints()
    createBtn.frame:SetPoint("TOPLEFT", CS.col1ButtonBar, "TOPLEFT", 0, -1)
    createBtn.frame:SetPoint("TOPRIGHT", CS.col1ButtonBar, "TOPRIGHT", 0, -1)
    createBtn.frame:SetHeight(28)
    createBtn.frame:Show()
    CS.col1CreateButton = createBtn
    table.insert(CS.col1BarWidgets, createBtn)
end

local function PopulateOtherClassBrowseButtonBar()
    if not CS.col1ButtonBar then
        return
    end

    ClearColumn1ButtonBar()

    local toggleBtn = AceGUI:Create("Button")
    local function UpdateToggleText()
        toggleBtn:SetText(CS.hideActiveCurrentClassPanels == true and "Show Active" or "Hide Active")
    end
    UpdateToggleText()
    toggleBtn:SetCallback("OnClick", function()
        local hideActive = not (CS.hideActiveCurrentClassPanels == true)
        SetHideActiveCurrentClassPanels(hideActive)
        UpdateToggleText()
    end)
    toggleBtn.frame:SetParent(CS.col1ButtonBar)
    toggleBtn.frame:ClearAllPoints()
    toggleBtn.frame:SetPoint("TOPLEFT", CS.col1ButtonBar, "TOPLEFT", 0, -1)
    toggleBtn.frame:SetPoint("TOPRIGHT", CS.col1ButtonBar, "TOPRIGHT", 0, -1)
    toggleBtn.frame:SetHeight(28)
    toggleBtn.frame._cdcHideActiveOtherClassBrowse = true
    toggleBtn.frame:SetScript("OnEnter", function(self)
        local hidden = CS.hideActiveCurrentClassPanels == true
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(hidden and "Show Active" or "Hide Active")
        GameTooltip:AddLine(hidden and "Show your current character's panels again." or "Hide your current character's panels.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Other-class previews stay visible.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    toggleBtn.frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    toggleBtn.frame:Show()
    table.insert(CS.col1BarWidgets, toggleBtn)

    CS.col1ButtonBar._topRowBtns = { toggleBtn.frame }
    CS.col1ButtonBar:SetScript("OnSizeChanged", function(self, w)
        if self._topRowBtns and self._topRowBtns[1] then
            self._topRowBtns[1]:SetWidth(w)
        end
    end)
    CS.col1ButtonBar:Show()
end

------------------------------------------------------------------------
-- COLUMN 1: Groups
------------------------------------------------------------------------
local function RefreshColumn1(preserveDrag)
    if not CS.col1Scroll then return end

    CS.col1Scroll.frame:Show()

    if CS.col1ButtonBar then CS.col1ButtonBar:Show() end

    if not preserveDrag then CancelDrag() end
    CS.col1Scroll:ReleaseChildren()
    CS._panelDropTargets = {}
    if CS._UpdatePanelDropScan then
        CS._UpdatePanelDropScan()
    end

    local db = CooldownCompanion.db.profile
    local charKey = CooldownCompanion.db.keys.char
    local searchResults = IsConfigFinderActive and IsConfigFinderActive() and BuildConfigFinderResults and BuildConfigFinderResults() or nil
    local searchPanelResultsByContainer = {}
    for _, result in ipairs(searchResults and searchResults.panelResults or {}) do
        local byPanel = searchPanelResultsByContainer[result.containerId]
        if not byPanel then
            byPanel = {}
            searchPanelResultsByContainer[result.containerId] = byPanel
        end
        byPanel[result.panelId] = result
    end

    if CooldownCompanion._unsupportedLegacyProfile then
        ClearOtherClassBrowseState()
        if CS.col1ButtonBar then CS.col1ButtonBar:Hide() end

        local spacer = AceGUI:Create("SimpleGroup")
        spacer:SetFullWidth(true)
        spacer:SetHeight(20)
        spacer.noAutoHeight = true
        CS.col1Scroll:AddChild(spacer)

        local header = AceGUI:Create("Label")
        header:SetText("This profile is unsupported.")
        header:SetFullWidth(true)
        header:SetJustifyH("CENTER")
        header:SetFont((GameFontNormal:GetFont()), 15, "")
        header.label:SetWordWrap(true)
        header.label:SetNonSpaceWrap(true)
        header.label:SetMaxLines(0)
        CS.col1Scroll:AddChild(header)

        local descSpacer = AceGUI:Create("SimpleGroup")
        descSpacer:SetFullWidth(true)
        descSpacer:SetHeight(6)
        descSpacer.noAutoHeight = true
        CS.col1Scroll:AddChild(descSpacer)

        local desc = AceGUI:Create("Label")
        desc:SetText(CooldownCompanion:GetLegacySupportCutoffMessage("profile"))
        desc:SetFullWidth(true)
        desc:SetJustifyH("CENTER")
        desc:SetFont((GameFontNormal:GetFont()), 12, "")
        desc:SetColor(0.7, 0.7, 0.7)
        desc.label:SetWordWrap(true)
        desc.label:SetNonSpaceWrap(true)
        desc.label:SetMaxLines(0)
        CS.col1Scroll:AddChild(desc)
        return
    end

    local containerStats = {}

    -- Track all rendered rows for drag system: sequential index -> metadata
    local col1RenderedRows = {}

    local function TrackRenderedRow(meta)
        col1RenderedRows[#col1RenderedRows + 1] = meta
        return meta
    end

    local function ResolveContainerScope(containerId, container)
        if CooldownCompanion.ResolveContainerClassScope then
            return CooldownCompanion:ResolveContainerClassScope(container or containerId)
        end
        if container and container.isGlobal then
            return { scope = "global", sectionKey = "global", runtimeVisible = true }
        end
        if container and container.createdBy == charKey then
            return { scope = "current-class", sectionKey = "char", runtimeVisible = true }
        end
        return { scope = "invalid", sectionKey = "invalid", runtimeVisible = false }
    end

    local function ScopeMatchesSection(scope, section)
        return scope and scope.sectionKey == section
    end

    -- Build the flat Group order for a section.
    local function BuildSectionItems(section, sectionContainerIds)
        local items = {}
        local specId = CooldownCompanion._currentSpecId
        for _, cid in ipairs(sectionContainerIds) do
            if not searchResults or searchResults.containerMatches[cid] then
                table.insert(items, {
                    kind = "container",
                    id = cid,
                    order = CooldownCompanion:GetOrderForSpec(db.groupContainers[cid], specId, cid),
                })
            end
        end
        table.sort(items, function(a, b) return a.order < b.order end)
        return items
    end

    local function IsContainerInactive(containerId, container)
        if not container then return true end
        if container.enabled == false then return true end
        local stats = containerStats[containerId]
        if not stats or not stats.hasButtons then return true end
        return stats.hasActivePanel ~= true
    end

    local function ResolveSelectedDragLoadBucket(defaultBucket)
        if not next(CS.selectedGroups) then
            return defaultBucket or "loaded"
        end

        local sawLoaded, sawUnloaded = false, false
        local seenSelected = {}
        for _, row in ipairs(col1RenderedRows) do
            if row.kind == "container" and CS.selectedGroups[row.id] then
                seenSelected[row.id] = true
                if row.loadBucket == "unloaded" then
                    sawUnloaded = true
                elseif row.loadBucket ~= "aux" and row.loadBucket ~= "marker" then
                    sawLoaded = true
                end
                if sawLoaded and sawUnloaded then
                    return "mixed"
                end
            end
        end

        -- Fall back to live container activity when a selected Group is not
        -- currently rendered (for example, while its class section is collapsed).
        for containerId in pairs(CS.selectedGroups) do
            if not seenSelected[containerId] then
                local container = db.groupContainers[containerId]
                if container then
                    if IsContainerInactive(containerId, container) then
                        sawUnloaded = true
                    else
                        sawLoaded = true
                    end
                    if sawLoaded and sawUnloaded then
                        return "mixed"
                    end
                end
            end
        end

        if sawUnloaded and not sawLoaded then
            return "unloaded"
        end
        return defaultBucket or "loaded"
    end

    CS.peekedContainers = CS.peekedContainers or {}
    if CS.expandedContainer and not db.groupContainers[CS.expandedContainer] then
        CS.expandedContainer = nil
    end
    for containerId in pairs(CS.peekedContainers) do
        if not db.groupContainers[containerId] then
            CS.peekedContainers[containerId] = nil
        end
    end

    local selectedPanel = CS.selectedGroup and db.groups[CS.selectedGroup]
    if not searchResults
        and not CS.otherClassLibraryActive
        and selectedPanel
        and selectedPanel.parentContainerId
        and CS.configFinderRestoredCollapsedContainerId ~= selectedPanel.parentContainerId
    then
        CS.expandedContainer = selectedPanel.parentContainerId
    end

    local function IsContainerExpanded(containerId)
        return CS.expandedContainer == containerId
            or CS.peekedContainers[containerId] == true
            or CS.springOpenContainer == containerId
    end

    local function ContainerHasActivePanelSelection(containerId)
        local panel = CS.selectedGroup and db.groups[CS.selectedGroup]
        return panel and panel.parentContainerId == containerId
    end

    local function CollapseContainer(containerId)
        if ContainerHasActivePanelSelection(containerId) then
            SelectConfigContainer(containerId)
        end
        if CS.expandedContainer == containerId then
            CS.expandedContainer = nil
        end
        CS.peekedContainers[containerId] = nil
    end

    local function ToggleContainerPeek(containerId)
        if IsContainerExpanded(containerId) then
            CollapseContainer(containerId)
        else
            CS.peekedContainers[containerId] = true
        end
        CooldownCompanion:RefreshConfigPanel()
    end

    local function SelectAndExpandContainer(containerId)
        CS.expandedContainer = containerId
        CS.peekedContainers[containerId] = nil
        SelectConfigContainer(containerId)
        CooldownCompanion:RefreshConfigPanel()
    end

    local function GetContainerClassColor(containerId, container)
        local scope = ResolveContainerScope(containerId, container)
        if scope and scope.ownerClassKey then
            local color = C_ClassColor.GetClassColor(scope.ownerClassKey)
            if color then return color end
        end
        return C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    end

    -- Helper: render a framed Group unit and its visible Panel rows.
    local lastRenderedGroupSection
    local function RenderContainerRow(containerId, sectionTag, loadBucket, options)
        local container = db.groupContainers[containerId]
        if not container then return end

        local isInactive = IsContainerInactive(containerId, container)
        local stats = containerStats[containerId]
        local panelCount = stats and stats.panelCount or 0
        local panels = CooldownCompanion:GetPanels(containerId)
        local browsePanels = options and options.browsePanels == true
        local isExpanded = searchResults ~= nil or browsePanels or IsContainerExpanded(containerId)
        local allowPanelRows = searchResults ~= nil or browsePanels or not (options and options.disableDrag == true)
        local searchPanels = searchPanelResultsByContainer[containerId]
        local classColor = GetContainerClassColor(containerId, container)

        if loadBucket == "loaded" and lastRenderedGroupSection == sectionTag then
            AddClassAccentSpacer(CS.col1Scroll, classColor)
        end
        lastRenderedGroupSection = loadBucket == "loaded" and sectionTag or nil

        local groupUnit = AceGUI:Create("InlineGroup")
        groupUnit:SetTitle("")
        groupUnit:SetLayout("List")
        groupUnit:SetFullWidth(true)
        CompactUntitledInlineGroupConfig(groupUnit)
        CS.col1Scroll:AddChild(groupUnit)
        groupUnit.frame:SetAlpha(isInactive and 0.58 or 1)

        local entry = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(entry)
        local groupName = container.name or "New Group"
        local countLabel = panelCount == 1 and "1 panel" or (tostring(panelCount) .. " panels")
        entry:SetText(groupName .. "  |cff777777(" .. countLabel .. ")|r")
        entry:SetFullWidth(true)
        entry:SetFontObject(GameFontHighlight)
        ApplyConfigRowIcon(entry, GetContainerIcon(containerId, db), {
            indent = 2,
            iconSize = TREE.GROUP_ICON_SIZE,
            iconGap = TREE.ICON_GAP,
            rowHeight = TREE.GROUP_ROW_HEIGHT,
            compactRowHeight = 30,
            texCoord = { 0.08, 0.92, 0.08, 0.92 },
        })
        entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        groupUnit:AddChild(entry)

        SetupGroupRowIndicators(entry, container)
        local expandReserve = 0
        if not searchResults and not browsePanels and allowPanelRows and panelCount > 0 then
            expandReserve = ConfigureTreeExpandButton(
                entry,
                isExpanded,
                CS.peekedContainers[containerId] == true,
                function()
                    ToggleContainerPeek(containerId)
                end
            )
            OffsetGroupStatusBadges(entry, expandReserve)
        end
        local rightReserve = expandReserve + GetConfigRowBadgeReserve(entry.frame) + 4
        rightReserve = rightReserve
            + ConfigureGenericGroupRenameBadge(entry, container, containerId, rightReserve)
        ConfigureGroupHeaderLayout(entry, rightReserve)

        if CS.selectedGroups[containerId] then
            entry:SetColor(0.4, 0.7, 1.0)
        elseif CS.selectedContainer == containerId
            and not CS.selectedGroup
            and not CS.resourcesEntrySelected
            and not CS.castFramesEntrySelected then
            entry:SetColor(0, 1, 0)
        elseif isInactive then
            entry:SetColor(0.55, 0.55, 0.55)
        end

        entry.frame:SetScript("OnMouseUp", function(_, button)
            if CS.dragState and CS.dragState.phase == "active" then return end
            if button == "LeftButton" then
                if searchResults then
                    if SelectConfigFinderResult then
                        SelectConfigFinderResult(containerId, nil, nil)
                    end
                elseif IsShiftKeyDown() then
                    OpenContainerLoadConditions(containerId)
                elseif IsControlKeyDown() then
                    ToggleConfigContainerMultiSelect(containerId)
                    CooldownCompanion:RefreshConfigPanel()
                elseif options and options.disableDrag == true then
                    SelectConfigContainer(containerId)
                    CooldownCompanion:RefreshConfigPanel()
                else
                    SelectAndExpandContainer(containerId)
                end
            elseif button == "RightButton" then
                ShowContainerContextMenu(db, containerId, container)
            elseif button == "MiddleButton" then
                container.locked = not container.locked
                CooldownCompanion:UpdateContainerDragHandle(containerId, container.locked)
                CooldownCompanion:RefreshContainerPanels(containerId)
                CooldownCompanion:RefreshConfigPanel()
            end
        end)

        local disableDrag = searchResults ~= nil or (options and options.disableDrag == true)
        if not disableDrag then
            entry:SetCallback("OnClick", function(_, _, mouseButton)
                if mouseButton ~= "LeftButton"
                    or IsShiftKeyDown()
                    or IsControlKeyDown()
                    or GetCursorInfo() then
                    return
                end

                local isMulti = next(CS.selectedGroups) and CS.selectedGroups[containerId]

                local cursorX, cursorY = GetScaledCursorPosition(CS.col1Scroll)
                CS.dragState = {
                    kind = isMulti and "multi-group" or "group",
                    phase = "pending",
                    sourceGroupId = containerId,
                    sourceGroupIds = isMulti and CopyTable(CS.selectedGroups) or nil,
                    sourceSection = sectionTag,
                    sourceLoadBucket = isMulti
                        and ResolveSelectedDragLoadBucket(loadBucket)
                        or (loadBucket or "loaded"),
                    scrollWidget = CS.col1Scroll,
                    widget = entry,
                    startX = cursorX,
                    startY = cursorY,
                    col1RenderedRows = col1RenderedRows,
                }
                StartDragTracking()
            end)
        end

        TrackRenderedRow({
            kind = "container",
            id = containerId,
            widget = entry,
            section = sectionTag,
            loadBucket = loadBucket or "loaded",
            acceptsDrop = not disableDrag,
            previewDraggable = not disableDrag,
            previewProxy = true,
            isExpanded = isExpanded,
            dragShellFrame = groupUnit.frame,
        })

        local firstPanelEntry, lastPanelEntry
        if allowPanelRows and isExpanded then
            local visiblePanels = {}
            for _, panelInfo in ipairs(panels) do
                local searchPanelResult = searchResults
                    and searchPanels
                    and searchPanels[panelInfo.groupId]
                    or nil
                if not searchResults or searchPanelResult then
                    visiblePanels[#visiblePanels + 1] = {
                        panelInfo = panelInfo,
                        searchResult = searchPanelResult,
                    }
                end
            end

            for _, visiblePanel in ipairs(visiblePanels) do
                local panelInfo = visiblePanel.panelInfo
                local panelId = panelInfo.groupId
                local panel = panelInfo.group
                local searchPanelResult = visiblePanel.searchResult
                local panelEntry = AceGUI:Create("InteractiveLabel")
                CleanRecycledEntry(panelEntry)
                panelEntry:SetText(panel.name or ("Panel " .. tostring(panelId)))
                panelEntry:SetFullWidth(true)
                panelEntry:SetFontObject(GameFontHighlight)

                local iconTexture = 134400
                local iconAtlas
                local vertexColor
                local texCoord
                local desaturated = isInactive or panel.enabled == false
                if panel.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
                    iconTexture = CooldownCompanion:GetRotationAssistantFallbackIcon()
                    texCoord = { 0.08, 0.92, 0.08, 0.92 }
                else
                    iconAtlas = GetConfigPanelTypeBadgeAtlas(panel.displayMode)
                    if panel.displayMode == "trigger" then
                        vertexColor = { 1.0, 0.18, 0.78, 1 }
                        desaturated = true
                    end
                end
                ApplyConfigRowIcon(panelEntry, iconTexture, {
                    atlas = iconAtlas,
                    desaturated = desaturated,
                    indent = TREE.PANEL_INDENT,
                    iconSize = TREE.PANEL_ICON_SIZE,
                    iconGap = TREE.ICON_GAP,
                    rowHeight = TREE.PANEL_ROW_HEIGHT,
                    compactRowHeight = 24,
                    texCoord = texCoord,
                    vertexColor = vertexColor,
                    rightPad = TREE.PANEL_META_WIDTH + 8,
                })
                panelEntry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                ConfigureTreePanelMeta(
                    panelEntry,
                    GetConfigPanelEntryCount(panel),
                    panel.enabled == false,
                    panel.enabled ~= false and ConfigPanelHasWarning(panel)
                )

                if CS.selectedPanels[panelId] then
                    panelEntry:SetColor(0.4, 0.7, 1.0)
                elseif panel.enabled == false or isInactive then
                    panelEntry:SetColor(0.5, 0.5, 0.5)
                elseif CS.selectedGroup == panelId
                    and not CS.selectedButton
                    and not CS.selectedRotationAssistantEntry then
                    panelEntry:SetColor(0, 1, 0)
                end

                groupUnit:AddChild(panelEntry)
                firstPanelEntry = firstPanelEntry or panelEntry
                lastPanelEntry = panelEntry

                if not disableDrag then
                    panelEntry:SetCallback("OnClick", function(_, _, mouseButton)
                        if mouseButton ~= "LeftButton"
                            or IsShiftKeyDown()
                            or IsControlKeyDown()
                            or GetCursorInfo() then
                            return
                        end

                        local sourcePanelIds = {}
                        local sourcePanelOrder = {}
                        local useMulti = CS.selectedPanels[panelId] == true and next(CS.selectedPanels) ~= nil
                        if useMulti then
                            for _, sourcePanelInfo in ipairs(panels) do
                                if CS.selectedPanels[sourcePanelInfo.groupId] then
                                    sourcePanelIds[sourcePanelInfo.groupId] = true
                                    sourcePanelOrder[#sourcePanelOrder + 1] = sourcePanelInfo.groupId
                                end
                            end
                        else
                            sourcePanelIds[panelId] = true
                            sourcePanelOrder[1] = panelId
                        end

                        local cursorX, cursorY = GetScaledCursorPosition(CS.col1Scroll)
                        CS.dragState = {
                            kind = "rail-panel",
                            phase = "pending",
                            sourcePanelId = panelId,
                            sourcePanelIds = sourcePanelIds,
                            sourcePanelOrder = sourcePanelOrder,
                            sourceContainerId = containerId,
                            scrollWidget = CS.col1Scroll,
                            widget = panelEntry,
                            startX = cursorX,
                            startY = cursorY,
                            railPanelRows = col1RenderedRows,
                        }
                        StartDragTracking()
                    end)

                    local panelFrame = panelEntry.frame
                    local overlay = panelFrame._cdcDropOverlay
                    if not overlay then
                        overlay = CreateFrame("Frame", nil, panelFrame, "BackdropTemplate")
                        overlay:SetAllPoints(panelFrame)
                        overlay:SetBackdrop({
                            bgFile = "Interface\\BUTTONS\\WHITE8X8",
                            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                            edgeSize = 1,
                        })
                        overlay:SetBackdropColor(0.15, 0.55, 0.85, 0.18)
                        overlay:SetBackdropBorderColor(0.3, 0.7, 1.0, 0.55)
                        overlay:EnableMouse(true)
                        panelFrame._cdcDropOverlay = overlay
                    end
                    overlay:SetFrameLevel(panelFrame:GetFrameLevel() + 30)
                    overlay:SetAlpha(1)
                    overlay:Hide()
                    overlay:SetScript("OnReceiveDrag", function()
                        local previousPanelId = CS.selectedGroup
                        CS.selectedGroup = panelId
                        TryReceiveCursorDrop()
                        CS.selectedGroup = previousPanelId
                    end)
                    overlay:SetScript("OnMouseUp", function(_, mouseButton)
                        if mouseButton == "LeftButton" and GetCursorInfo() then
                            local previousPanelId = CS.selectedGroup
                            CS.selectedGroup = panelId
                            TryReceiveCursorDrop()
                            CS.selectedGroup = previousPanelId
                        end
                    end)
                    CS._panelDropTargets[#CS._panelDropTargets + 1] = {
                        panelId = panelId,
                        frame = panelFrame,
                        overlay = overlay,
                        showHighlight = true,
                    }
                end

                panelEntry.frame:SetScript("OnMouseUp", function(_, button)
                    if CS.dragState and CS.dragState.phase == "active" then return end
                    if button == "LeftButton" then
                        if not searchResults and GetCursorInfo() then
                            local previousPanelId = CS.selectedGroup
                            CS.selectedGroup = panelId
                            local received = TryReceiveCursorDrop()
                            CS.selectedGroup = previousPanelId
                            if received then return end
                        end
                        if searchResults then
                            if SelectConfigFinderResult then
                                SelectConfigFinderResult(containerId, panelId, nil)
                            end
                        elseif IsControlKeyDown() then
                            if CS.selectedContainer ~= containerId then
                                SelectConfigPanel(panelId, { containerId = containerId })
                            end
                            ToggleConfigPanelMultiSelect(panelId)
                            CooldownCompanion:RefreshConfigPanel()
                        elseif IsShiftKeyDown() then
                            SelectConfigPanel(panelId, { containerId = containerId })
                            CS.selectedTab = "loadconditions"
                            CS.panelSettingsTab = "loadconditions"
                            CooldownCompanion:RefreshConfigPanel()
                        else
                            SelectConfigPanel(panelId, {
                                containerId = containerId,
                                toggle = true,
                            })
                            CooldownCompanion:RefreshConfigPanel()
                        end
                    elseif button == "MiddleButton" then
                        if CooldownCompanion.IsGroupCursorAnchored and CooldownCompanion:IsGroupCursorAnchored(panel) then
                            CooldownCompanion:Print("Cursor-anchored panels are edited from Layout.")
                            return
                        end
                        if panel.locked == false then
                            panel.locked = nil
                            CooldownCompanion:Print((panel.name or "Panel") .. " locked.")
                        else
                            panel.locked = false
                            CooldownCompanion:Print((panel.name or "Panel") .. " unlocked. Drag to reposition.")
                        end
                        CooldownCompanion:RefreshGroupFrame(panelId)
                        CooldownCompanion:RefreshConfigPanel()
                    elseif button == "RightButton" and ST._ShowPanelContextMenu then
                        ST._ShowPanelContextMenu(panelId, containerId)
                    end
                end)

                TrackRenderedRow({
                    kind = "aux-block",
                    rowType = "panel",
                    id = panelId,
                    widget = panelEntry,
                    section = sectionTag,
                    loadBucket = "aux",
                    acceptsDrop = false,
                    previewDraggable = false,
                    previewProxy = true,
                    ownerKind = "container",
                    ownerId = containerId,
                    panelIndex = panelInfo.group and panelInfo.group.order or nil,
                })

                for _, entryInfo in ipairs(searchPanelResult and searchPanelResult.entryMatches or {}) do
                    local buttonData = entryInfo.button
                    local buttonIndex = entryInfo.index
                    local entryDisabled = isInactive or (buttonData and buttonData.enabled == false)
                    local buttonEntry = AceGUI:Create("InteractiveLabel")
                    CleanRecycledEntry(buttonEntry)
                    buttonEntry:SetText(entryInfo.text or (buttonData and buttonData.name) or "Entry")
                    buttonEntry:SetFullWidth(true)
                    buttonEntry:SetFontObject(GameFontHighlight)
                    ApplyConfigRowIcon(buttonEntry, buttonData and GetButtonIcon(buttonData) or 134400, {
                        desaturated = entryDisabled,
                        indent = TREE.ENTRY_INDENT,
                        iconSize = TREE.ENTRY_ICON_SIZE,
                        iconGap = TREE.ICON_GAP,
                        rowHeight = TREE.ENTRY_ROW_HEIGHT,
                        compactRowHeight = 22,
                        texCoord = { 0.08, 0.92, 0.08, 0.92 },
                        rightPad = 4,
                    })
                    buttonEntry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                    if entryDisabled then
                        buttonEntry:SetColor(0.5, 0.5, 0.5)
                    elseif CS.selectedGroup == panelId and CS.selectedButton == buttonIndex then
                        buttonEntry:SetColor(0, 1, 0)
                    end
                    groupUnit:AddChild(buttonEntry)
                    lastPanelEntry = buttonEntry

                    buttonEntry.frame:SetScript("OnMouseUp", function(_, button)
                        if button == "LeftButton" and SelectConfigFinderResult then
                            SelectConfigFinderResult(containerId, panelId, buttonIndex)
                        end
                    end)

                    TrackRenderedRow({
                        kind = "aux-block",
                        rowType = "finder-entry",
                        id = buttonIndex,
                        widget = buttonEntry,
                        section = sectionTag,
                        loadBucket = "aux",
                        acceptsDrop = false,
                        previewDraggable = false,
                        previewProxy = true,
                        ownerKind = "container",
                        ownerId = containerId,
                        ownerPanelId = panelId,
                    })
                end
            end
        end
        ConfigureNestedPanelAccent(groupUnit, entry, firstPanelEntry, lastPanelEntry, classColor)
        return groupUnit
    end

    -- Helper: generate a unique group name with the given base
    GenerateGroupName = function(base)
        local profile = CooldownCompanion.db.profile
        local existing = {}
        -- Check container names (groups are now "panels" under containers)
        for _, c in pairs(profile.groupContainers or {}) do
            existing[c.name] = true
        end
        local name = base
        if existing[name] then
            local n = 1
            while existing[name .. " " .. n] do
                n = n + 1
            end
            name = name .. " " .. n
        end
        return name
    end

    -- Render a section (global, current class, or another class)
    local function RenderSection(section, sectionGroupIds, headingText, headingColor, options)
        local items = BuildSectionItems(section, sectionGroupIds)
        local isClassSection = options and options.classSection == true
        local stableCount = options and options.stableCount or nil

        if isClassSection then
            local isCollapsed = not searchResults and CS.collapsedSections[section] ~= false
            local function ToggleClassSection()
                local currentlyCollapsed = CS.collapsedSections[section] ~= false
                if currentlyCollapsed then
                    CS.collapsedSections[section] = false
                else
                    CS.collapsedSections[section] = true
                end
                CooldownCompanion:RefreshConfigPanel()
            end
            local header = AceGUI:Create("InteractiveLabel")
            CleanRecycledEntry(header)
            local countText = stableCount and (" |cff888888(" .. tostring(stableCount) .. ")|r") or ""
            header:SetText((isCollapsed and "|A:common-icon-plus:12:12|a " or "|A:common-icon-minus:12:12|a ")
                .. headingText .. countText)
            header:SetFullWidth(true)
            header:SetFontObject(GameFontHighlight)
            if headingColor then
                header:SetColor(headingColor[1], headingColor[2], headingColor[3])
            end
            if options and options.classKey then
                ApplyConfigRowIcon(header, 134400, { atlas = "classicon-" .. string.lower(options.classKey) })
            else
                ApplyConfigTextRow(header)
            end
            header:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            if header.frame then
                header.frame:SetScript("OnMouseUp", function(_, button)
                    if CS.dragState and CS.dragState.phase == "active" then return end
                    if button == "LeftButton" and not searchResults then
                        ToggleClassSection()
                    end
                end)
            end
            CS.col1Scroll:AddChild(header)
            TrackRenderedRow({
                kind = "class-header",
                widget = header,
                section = section,
                loadBucket = "marker",
                acceptsDrop = false,
                keepVisibleDuringPreview = true,
                previewProxy = true,
                isMarker = true,
                stableCount = stableCount,
            })
            if isCollapsed and not searchResults then
                return
            end
        end

        local orderedContainerIds = {}
        for _, item in ipairs(items) do
            if item.kind == "container" then
                orderedContainerIds[#orderedContainerIds + 1] = item.id
            end
        end

        local loadedItems = {}
        local unloadedItems = {}
        for _, containerId in ipairs(orderedContainerIds) do
            if options and options.noLoadBuckets then
                loadedItems[#loadedItems + 1] = containerId
            elseif IsContainerInactive(containerId, db.groupContainers[containerId]) then
                unloadedItems[#unloadedItems + 1] = containerId
            else
                loadedItems[#loadedItems + 1] = containerId
            end
        end

        local isEmpty = #loadedItems == 0 and #unloadedItems == 0
        if isEmpty and not CS.showPhantomSections then return end

        local useUnloadedOnlyHeading = options
            and options.preferUnloadedHeading
            and #loadedItems == 0
            and #unloadedItems > 0

        if not isClassSection then
            local heading = AceGUI:Create("Label")
            heading:SetFullWidth(true)
            heading:SetHeight(18)
            CS.col1Scroll:AddChild(heading)
            SetupColumn1MarkerRow(heading, {
                text = useUnloadedOnlyHeading and "Unloaded Groups" or headingText,
                color = useUnloadedOnlyHeading and { 0.53, 0.53, 0.53 } or headingColor,
            })

            TrackRenderedRow({
                kind = "section-header",
                widget = heading,
                section = section,
                loadBucket = "marker",
                acceptsDrop = false,
                keepVisibleDuringPreview = true,
                previewProxy = true,
                isMarker = true,
            })
        end

        if isEmpty and CS.showPhantomSections then
            local placeholder = AceGUI:Create("Label")
            if section == "global" then
                placeholder:SetText("")
                placeholder:SetHeight(18)
            else
                placeholder:SetText("|cff888888Drop here to move|r")
            end
            placeholder:SetFullWidth(true)
            CS.col1Scroll:AddChild(placeholder)
            TrackRenderedRow({
                kind = "phantom",
                widget = placeholder,
                section = section,
                loadBucket = "marker",
                acceptsDrop = true,
                keepVisibleDuringPreview = true,
                previewProxy = true,
                layoutOnly = section == "global",
            })
            return
        end

        -- Class color for accent bars
        local classColor = options and options.classKey and C_ClassColor.GetClassColor(options.classKey)
            or C_ClassColor.GetClassColor(select(2, UnitClass("player")))

        local function RenderItems(itemList, loadBucket)
            for _, containerId in ipairs(itemList) do
                RenderContainerRow(
                    containerId,
                    section,
                    loadBucket,
                    options
                )
            end
        end

        RenderItems(loadedItems, "loaded")

        if #unloadedItems > 0 and not useUnloadedOnlyHeading then
            local sep = AceGUI:Create("Label")
            sep:SetFullWidth(true)
            sep:SetHeight(18)
            CS.col1Scroll:AddChild(sep)
            SetupColumn1MarkerRow(sep, {
                text = "Unloaded Groups",
                color = { 0.53, 0.53, 0.53 },
            })

            TrackRenderedRow({
                kind = "unloaded-divider",
                widget = sep,
                section = section,
                loadBucket = "marker",
                acceptsDrop = false,
                keepVisibleDuringPreview = true,
                previewProxy = true,
                isMarker = true,
            })
        end

        RenderItems(unloadedItems, "unloaded")
    end

    local function GetClassInfoByID(classID)
        classID = tonumber(classID)
        if not classID then return nil, nil, nil end
        if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
            local classInfo = C_CreatureInfo.GetClassInfo(classID)
            if type(classInfo) == "table" then
                return classInfo.className, classInfo.classFile, classInfo.classID
            end
        end
        if GetClassInfo then
            return GetClassInfo(classID)
        end
        return nil, nil, nil
    end

    local function GetClassDisplayName(classKey)
        if type(classKey) ~= "string" then return "Class" end
        for classID = 1, 30 do
            local className, classFilename = GetClassInfoByID(classID)
            if classFilename and string.upper(classFilename) == classKey then
                return className or classKey
            end
        end
        return classKey:sub(1, 1) .. string.lower(classKey:sub(2))
    end

    local function EnsureOtherClassSection(otherSections, otherSectionOrder, scope)
        if not (scope and scope.ownerClassKey and scope.sectionKey) then
            return nil
        end
        local section = otherSections[scope.sectionKey]
        if not section then
            local cc = C_ClassColor.GetClassColor(scope.ownerClassKey)
            section = {
                key = scope.sectionKey,
                classKey = scope.ownerClassKey,
                title = GetClassDisplayName(scope.ownerClassKey),
                color = cc and { cc.r, cc.g, cc.b } or { 1, 1, 1 },
                containerIds = {},
                count = 0,
            }
            otherSections[scope.sectionKey] = section
            otherSectionOrder[#otherSectionOrder + 1] = section
        end
        return section
    end

    local function GetOtherClassVisibleCount(section)
        if not section then return 0 end
        if not searchResults then
            return section.count or 0
        end

        local count = 0
        for _, containerId in ipairs(section.containerIds or {}) do
            if searchResults.containerMatches[containerId] then
                count = count + 1
            end
        end
        return count
    end

    local function GetOtherClassSummary(otherSectionOrder)
        local totalCount = 0
        local classCount = 0
        for _, section in ipairs(otherSectionOrder or {}) do
            local visibleCount = GetOtherClassVisibleCount(section)
            if visibleCount > 0 then
                totalCount = totalCount + visibleCount
                classCount = classCount + 1
            end
        end
        return totalCount, classCount
    end

    local function RenderNavigationRow(kind, text, options)
        local row = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(row)
        row:SetText(text)
        row:SetFullWidth(true)
        row:SetFontObject(GameFontHighlight)
        if options and options.color then
            row:SetColor(options.color[1], options.color[2], options.color[3])
        end
        if options and options.iconAtlas then
            ApplyConfigRowIcon(row, 134400, {
                atlas = options.iconAtlas,
                indent = options.indent or 0,
                iconSize = options.iconSize or 16,
                rowHeight = options.rowHeight or 28,
                compactRowHeight = 24,
            })
        elseif options and options.classKey then
            ApplyConfigRowIcon(row, 134400, { atlas = "classicon-" .. string.lower(options.classKey) })
        else
            ApplyConfigTextRow(row)
        end
        row:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        if row.frame then
            row.frame:SetScript("OnMouseUp", function(_, button)
                if CS.dragState and CS.dragState.phase == "active" then return end
                if button == "LeftButton" and options and options.onClick then
                    options.onClick()
                end
            end)
        end
        if options and options.selected then
            row:SetColor(0, 1, 0)
        end
        CS.col1Scroll:AddChild(row)
        TrackRenderedRow({
            kind = kind,
            widget = row,
            section = options and options.section or nil,
            classKey = options and options.classKey or nil,
            loadBucket = "marker",
            acceptsDrop = false,
            keepVisibleDuringPreview = true,
            previewProxy = true,
            isMarker = true,
            stableCount = options and options.stableCount or nil,
        })
        return row
    end

    local function FindOtherClassSectionByClassKey(otherSectionOrder, classKey)
        if not classKey then return nil end
        for _, section in ipairs(otherSectionOrder or {}) do
            if section.classKey == classKey then
                return section
            end
        end
        return nil
    end

    local function RenderOtherClassLibrary(otherSectionOrder)
        local totalCount, classCount = GetOtherClassSummary(otherSectionOrder)
        if totalCount <= 0 or classCount <= 0 then
            ClearOtherClassBrowseState()
            return false
        end

        local selectedSection = FindOtherClassSectionByClassKey(otherSectionOrder, CS.otherClassLibraryClassKey)
        if selectedSection and GetOtherClassVisibleCount(selectedSection) <= 0 then
            selectedSection = nil
            CS.otherClassLibraryClassKey = nil
        end

        if selectedSection then
            RenderNavigationRow("other-class-library-back", "|A:common-icon-backarrow:14:14|a  Back to Other Classes", {
                section = "other-classes",
                onClick = function()
                    CS.otherClassLibraryClassKey = nil
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
            RenderSection(
                selectedSection.key,
                selectedSection.containerIds,
                selectedSection.title,
                selectedSection.color,
                {
                    classKey = selectedSection.classKey,
                    noLoadBuckets = true,
                    disableDrag = true,
                    browsePanels = true,
                }
            )
            return true
        end

        RenderNavigationRow("other-class-library-back", "|A:common-icon-backarrow:14:14|a  Back to Groups", {
            section = "other-classes",
            onClick = function()
                if ClearConfigPrimarySelection then
                    ClearConfigPrimarySelection()
                end
                ClearOtherClassBrowseState()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        for _, section in ipairs(otherSectionOrder or {}) do
            local visibleCount = GetOtherClassVisibleCount(section)
            if visibleCount > 0 then
                RenderNavigationRow("other-class-library-class", section.title
                    .. " |cff888888(" .. tostring(visibleCount) .. ")|r", {
                    section = section.key,
                    classKey = section.classKey,
                    color = section.color,
                    stableCount = visibleCount,
                    onClick = function()
                        CS.otherClassLibraryClassKey = section.classKey
                        CooldownCompanion:RefreshConfigPanel()
                    end,
                })
            end
        end
        return true
    end

    -- Split containers into global, current-class, and other-class inventory.
    local containers = db.groupContainers or {}
    local showNewUserEmptyState = not next(containers)
    local globalIds = {}
    local charIds = {}
    local otherSections = {}
    local otherSectionOrder = {}
    for id, container in pairs(containers) do
        local scope = ResolveContainerScope(id, container)
        if scope.scope == "global" then
            table.insert(globalIds, id)
        elseif scope.scope == "current-class" then
            table.insert(charIds, id)
        elseif scope.scope == "other-class" then
            local section = EnsureOtherClassSection(otherSections, otherSectionOrder, scope)
            if section then
                table.insert(section.containerIds, id)
                section.count = section.count + 1
            end
        end
    end

    table.sort(otherSectionOrder, function(a, b)
        return (a.title or a.classKey or a.key) < (b.title or b.classKey or b.key)
    end)

    if searchResults and not next(searchResults.containerMatches) then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("|cff888888No matching groups, panels, or entries.|r")
        label:SetFullWidth(true)
        CS.col1Scroll:AddChild(label)
        CS.lastCol1RenderedRows = col1RenderedRows
        if CS.otherClassLibraryActive then
            PopulateOtherClassBrowseButtonBar()
        else
            PopulateColumn1ButtonBar()
        end
        return
    end

    if showNewUserEmptyState then
        ClearOtherClassBrowseState()

        local spacer = AceGUI:Create("SimpleGroup")
        spacer:SetFullWidth(true)
        spacer:SetHeight(20)
        spacer.noAutoHeight = true
        CS.col1Scroll:AddChild(spacer)

        local header = AceGUI:Create("Label")
        header:SetText("Every setup starts with a group.")
        header:SetFullWidth(true)
        header:SetJustifyH("CENTER")
        header:SetFont((GameFontNormal:GetFont()), 15, "")
        header.label:SetWordWrap(true)
        header.label:SetNonSpaceWrap(true)
        header.label:SetMaxLines(0)
        CS.col1Scroll:AddChild(header)

        local descSpacer = AceGUI:Create("SimpleGroup")
        descSpacer:SetFullWidth(true)
        descSpacer:SetHeight(6)
        descSpacer.noAutoHeight = true
        CS.col1Scroll:AddChild(descSpacer)

        local desc = AceGUI:Create("Label")
        desc:SetText("A group holds one or more panels so you can organize related cooldowns together. Use the buttons below to create your first group.")
        desc:SetFullWidth(true)
        desc:SetJustifyH("CENTER")
        desc:SetFont((GameFontNormal:GetFont()), 12, "")
        desc:SetColor(0.7, 0.7, 0.7)
        desc.label:SetWordWrap(true)
        desc.label:SetNonSpaceWrap(true)
        desc.label:SetMaxLines(0)
        CS.col1Scroll:AddChild(desc)
    else
        if searchResults and searchResults.truncated then
            local summary = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(summary)
            summary:SetText(("|cff888888Showing %d of %d matching panels and %d of %d matching entries. Keep typing to narrow results.|r"):format(
                #searchResults.panelResults,
                searchResults.totalPanelResults or #searchResults.panelResults,
                searchResults.renderedEntryResults or 0,
                searchResults.totalEntryResults or 0
            ))
            summary:SetFullWidth(true)
            CS.col1Scroll:AddChild(summary)
        end

        local statsContainerIds = {}
        local function IncludeVisibleStats(containerId)
            if not searchResults or searchResults.containerMatches[containerId] then
                statsContainerIds[containerId] = true
            end
        end
        for _, id in ipairs(globalIds) do
            IncludeVisibleStats(id)
        end
        for _, id in ipairs(charIds) do
            IncludeVisibleStats(id)
        end
        if searchResults then
            for _, section in ipairs(otherSectionOrder) do
                for _, id in ipairs(section.containerIds or {}) do
                    IncludeVisibleStats(id)
                end
            end
        end
        local selectedOtherSection = CS.otherClassLibraryActive
            and FindOtherClassSectionByClassKey(otherSectionOrder, CS.otherClassLibraryClassKey)
            or nil
        if selectedOtherSection then
            for _, id in ipairs(selectedOtherSection.containerIds) do
                IncludeVisibleStats(id)
            end
        end
        for id in pairs(CS.selectedGroups) do
            if containers[id] then
                statsContainerIds[id] = true
            end
        end
        containerStats = BuildColumn1ContainerStats(db, statsContainerIds)

        -- Render sections
        local renderedOtherClassLibrary = false
        if CS.otherClassLibraryActive and not searchResults then
            renderedOtherClassLibrary = RenderOtherClassLibrary(otherSectionOrder)
        end

        if not renderedOtherClassLibrary then
            local hasGlobalContent = #globalIds > 0

            if #globalIds > 0 or CS.showPhantomSections then
                if hasGlobalContent or CS.showPhantomSections then
                    RenderSection("global", globalIds, "Global Groups", { 0.4, 0.67, 1.0 })
                end
            end

            local _, playerClassKey = UnitClass("player")
            local currentClassName = GetClassDisplayName(playerClassKey)
            local hasCharContent = #charIds > 0
            if hasCharContent or CS.showPhantomSections then
                local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
                RenderSection(
                    "char",
                    charIds,
                    currentClassName .. " Groups",
                    cc and { cc.r, cc.g, cc.b } or { 1, 1, 1 },
                    { preferUnloadedHeading = not hasGlobalContent }
                )
            end

            if searchResults then
                for _, section in ipairs(otherSectionOrder) do
                    local visibleCount = GetOtherClassVisibleCount(section)
                    if visibleCount > 0 then
                        RenderSection(
                            section.key,
                            section.containerIds,
                            section.title,
                            section.color,
                            {
                                classSection = true,
                                classKey = section.classKey,
                                stableCount = visibleCount,
                                noLoadBuckets = true,
                                disableDrag = true,
                            }
                        )
                    end
                end
            end
        end
    end

    UpdateRailDestinations()

    CS.lastCol1RenderedRows = col1RenderedRows

    if CS._UpdatePanelDropScan then
        CS._UpdatePanelDropScan()
    end

    if CS.otherClassLibraryActive then
        PopulateOtherClassBrowseButtonBar()
    else
        PopulateColumn1ButtonBar()
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn1 = RefreshColumn1
