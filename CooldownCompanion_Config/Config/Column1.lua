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
local SetupPanelResourceIndicator = ST._SetupPanelResourceIndicator
local GetConfigRowBadgeReserve = ST._GetConfigRowBadgeReserve
local GetContainerIcon = ST._GetContainerIcon
local GetButtonIcon = ST._GetButtonIcon
local OpenContainerIconPicker = ST._OpenContainerIconPicker
local IsValidIconTexture = ST._IsValidIconTexture
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local CancelDrag = ST._CancelDrag
local StartDragTracking = ST._StartDragTracking
local GetScaledCursorPosition = ST._GetScaledCursorPosition
local ContainersHaveForeignSpecs = ST._ContainersHaveForeignSpecs
local NotifyTutorialAction = ST._NotifyTutorialAction
local IsConfigFinderActive = ST._IsConfigFinderActive
local ClearConfigFinderText = ST._ClearConfigFinderText
local BuildConfigFinderResults = ST._BuildConfigFinderResults
local SelectConfigFinderResult = ST._SelectConfigFinderResult
local ClearConfigPrimarySelection = ST._ClearConfigPrimarySelection
local SelectConfigContainer = ST._SelectConfigContainer
local ToggleConfigContainerMultiSelect = ST._ToggleConfigContainerMultiSelect
local SelectConfigPanel = ST._SelectConfigPanel
local ToggleConfigPanelMultiSelect = ST._ToggleConfigPanelMultiSelect
local GetConfigPanelTypeBadgeAtlas = ST._GetConfigPanelTypeBadgeAtlas
local GetConfigAuraPanelBadgeTint = ST._GetConfigAuraPanelBadgeTint
local GetConfigPanelEntryCount = ST._GetConfigPanelEntryCount
local ConfigPanelHasWarning = ST._ConfigPanelHasWarning
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
    if not host._cdcDivider then
        host._cdcDivider = host:CreateTexture(nil, "ARTWORK")
        host._cdcDivider:SetHeight(1)
        host._cdcDivider:SetPoint("TOPLEFT", host, "TOPLEFT", 8, -4)
        host._cdcDivider:SetPoint("TOPRIGHT", host, "TOPRIGHT", -8, -4)
    end
    host._cdcDivider:SetColorTexture(r, g, b, 0.38)

    local otherClasses = EnsureRailDestinationButton(host, "other-classes")
    local showOtherClasses = ST._ShouldShowOtherClassNavigatorRow
        and ST._ShouldShowOtherClassNavigatorRow() or false
    local old = host._cdcDestinationButtons and host._cdcDestinationButtons["bars-frames"]
    if old then old:Hide() end
    otherClasses:ClearAllPoints()
    otherClasses:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -8)
    otherClasses:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -8)

    if showOtherClasses then
        ConfigureRailDestinationButton(otherClasses, {
            label = "Browse Other Classes",
            atlas = "BattleBar-SwapPetIcon",
            selected = CS.otherClassLibraryActive == true,
            onClick = function()
                if CS.otherClassLibraryActive then
                    if ClearConfigPrimarySelection then
                        ClearConfigPrimarySelection()
                    end
                    ClearOtherClassBrowseState()
                    CooldownCompanion:RefreshConfigPanel()
                    return
                end
                -- A destination is somewhere you can always go: this row is
                -- offered whenever another class has inventory, so the click
                -- must not re-test that against the search box. It used to,
                -- and a search matching no foreign container left the row
                -- visible, undimmed, and silently inert.
                --
                -- Leaving the filtered tree behind is what the bars
                -- destination row already does (it clears the finder on its
                -- way in). Cleared BEFORE entering, because stopping a search
                -- while the library is already active resets straight back
                -- out of it (SetConfigFinderText) - which would put the dead
                -- row right back, by a different route.
                if ClearConfigFinderText then
                    ClearConfigFinderText({ preservePrimarySelection = true })
                end
                if ST._EnterOtherClassLibraryState then
                    ST._EnterOtherClassLibraryState(nil)
                end
                if ClearConfigPrimarySelection then
                    ClearConfigPrimarySelection()
                end
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
    else
        otherClasses:Hide()
    end

    -- Browse availability can flip mid-refresh (RefreshColumn1 runs after
    -- LayoutColumns sized the bar), so re-lay the columns when it changes.
    if host._cdcOtherRowShown ~= showOtherClasses then
        host._cdcOtherRowShown = showOtherClasses
        if CS.configFrame and CS.configFrame.LayoutColumns then
            CS.configFrame.LayoutColumns()
        end
    end

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
    meta.count:SetWidth(18)
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
    -- Reserve the warning slot only while its badge is visible.
    return (panelDisabled or hasWarning) and 36 or 18
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

local function IsGenericPanelName(name)
    local trimmed = TrimGroupName(name)
    return trimmed == ""
        or trimmed == "Panel"
        or trimmed:match("^Panel%s+%d+$") ~= nil
end

local function EnsureGenericRenameBadge(entry)
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

local function ConfigureGenericRenameBadge(entry, name, isGeneric, renameData, rightReserve)
    local badge = EnsureGenericRenameBadge(entry)
    badge:ClearAllPoints()
    badge:SetScript("OnClick", nil)

    if not isGeneric then
        badge:Hide()
        return 0
    end

    local currentName = TrimGroupName(name)
    if currentName == "" then
        currentName = renameData.containerId and "New Group" or "Panel"
    end

    badge.icon:SetAtlas("QuestLegendary", false)
    badge.icon:SetVertexColor(1, 0.82, 0, 0.85)
    badge:SetPoint("RIGHT", entry.frame, "RIGHT", -((rightReserve or 4) + 2), 0)
    badge:SetScript("OnClick", function(_, button)
        if button ~= "LeftButton" then return end
        GameTooltip:Hide()
        ShowPopupAboveConfig("CDC_RENAME_GROUP", currentName, renameData)
    end)
    badge:Show()
    return 18
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

-- The one tail every "Switch to <mode>" path runs, so the menu row and the
-- flatten confirmation below it cannot land the panel in different states.
--
-- flattenSections belongs INSIDE the success test, not before the call:
-- ChangePanelDisplayMode judges the request itself (CanChangePanelDisplayMode)
-- and can still refuse it at Accept time, and a flatten that ran first would
-- have destroyed every placement for a switch that never happened. Flattening
-- after is safe -- sections are inert in every non-icon mode -- and it lands
-- before the config refresh below, so one pass shows the finished state.
local function ApplyPanelDisplayModeChange(panelId, containerId, targetMode, flattenSections)
    if CooldownCompanion:ChangePanelDisplayMode(panelId, targetMode) then
        if flattenSections then
            local panel = CooldownCompanion.db.profile.groups[panelId]
            if panel then
                ST.FlattenPanelSections(panel)
            end
        end
        if targetMode == "textures" then
            CS.pendingTexturePickerOpen = panelId
            SelectConfigPanel(panelId, { containerId = containerId })
        end
        CooldownCompanion:RefreshConfigPanel()
    end
end
ST._ApplyPanelDisplayModeChange = ApplyPanelDisplayModeChange

local function TogglePanelAnchorLock(panelId)
    local panel = CooldownCompanion.db.profile.groups and CooldownCompanion.db.profile.groups[panelId]
    if not panel then
        return false
    end
    if InCombatLockdown() or CooldownCompanion._combatForcedLock then
        CooldownCompanion:Print("Cannot change anchor lock during combat.")
        return false
    end

    local isLocked = panel.locked ~= false
    if isLocked and CooldownCompanion:IsGroupCursorAnchored(panel) then
        isLocked = not CooldownCompanion:IsCursorAnchorLayoutPreviewGroupActive(panelId)
    end
    CooldownCompanion:SetPanelLocked(panelId, not isLocked)
    if isLocked then
        CooldownCompanion:Print((panel.name or "Panel") .. " unlocked. Drag to reposition.")
    else
        CooldownCompanion:Print((panel.name or "Panel") .. " locked.")
    end
    CooldownCompanion:RefreshConfigPanel()
    if isLocked and ST.CollapseConfigForUnlock then
        ST.CollapseConfigForUnlock()
    end
    return true
end
ST._TogglePanelAnchorLock = TogglePanelAnchorLock

local function ToggleContainerLock(containerId)
    local containers = CooldownCompanion.db.profile.groupContainers
    local container = containers and containers[containerId]
    if not container then return false end

    local isLocked = container.locked ~= false
    CooldownCompanion:SetContainerLocked(containerId, not isLocked)
    CooldownCompanion:RefreshConfigPanel()
    if isLocked and ST.CollapseConfigForUnlock then
        ST.CollapseConfigForUnlock()
    elseif not isLocked then
        CooldownCompanion:CheckArrangeModeAutoExit()
    end
    return true
end

-- Panel Templates (Core/PanelTemplates.lua). Every list here goes through
-- the Core API at call time; the store is never walked directly.
local function GetPanelTemplateList(mode)
    if not CooldownCompanion.GetPanelTemplates then return {} end
    return CooldownCompanion:GetPanelTemplates(mode)
end

-- "Name (Icon Panel)": the type rides along in grey wherever a list mixes
-- types or names a template away from a panel of its own type.
local function FormatPanelTemplateMenuText(template)
    local modeLabel = ST._GetPanelTemplateModeLabel(template)
    return (template.name or "") .. " |cff777777(" .. modeLabel .. ")|r"
end

-- A list filtered to one type says which type it has none of ("No Icon
-- Panel templates"); the all-types list just says there are none.
local function AddNoTemplatesItem(level, modeLabel)
    local info = UIDropDownMenu_CreateInfo()
    info.text = modeLabel and ("No " .. modeLabel .. " templates") or "No templates"
    info.notCheckable = true
    info.disabled = true
    UIDropDownMenu_AddButton(info, level)
end

local PANEL_TEMPLATE_APPLY_FAILURE_TEXT = {
    missing_template = "That template no longer exists.",
    missing_group = "That panel no longer exists.",
    mode_mismatch = "That template is for a different panel type.",
    invalid_class_scope = "This panel's Group is not valid for this class.",
}

-- Owner ruling: applying a template to an existing panel never moves it.
local function ApplyPanelTemplateToPanel(templateId, panelId)
    local applied, reason = CooldownCompanion:ApplyPanelTemplate(templateId, panelId, { position = false })
    if not applied then
        CooldownCompanion:Print(PANEL_TEMPLATE_APPLY_FAILURE_TEXT[reason] or "Could not apply the template.")
        return
    end
    CooldownCompanion:RefreshConfigPanel()
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
            info.text = "Visibility"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                SelectConfigPanel(panelId, { containerId = containerId })
                CS.selectedTab = "loadconditions"
                CS.panelSettingsTab = "loadconditions"
                -- A deliberate destination, so it outranks a display mode's
                -- own default landing tab.
                CS.panelSettingsTabExplicit = true
                CooldownCompanion:RefreshConfigPanel()
            end
            UIDropDownMenu_AddButton(info, level)

            info = UIDropDownMenu_CreateInfo()
            local anchorUnlocked = panel.locked == false
            if not anchorUnlocked and CooldownCompanion:IsGroupCursorAnchored(panel) then
                anchorUnlocked = CooldownCompanion:IsCursorAnchorLayoutPreviewGroupActive(panelId)
            end
            info.text = anchorUnlocked and "Lock Anchor" or "Unlock Anchor"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                TogglePanelAnchorLock(panelId)
            end
            UIDropDownMenu_AddButton(info, level)

            -- Aura Panels are structurally excluded from auto-anchoring
            -- (IsGroupAvailableForAnchoring), so there is nothing to toggle.
            if CooldownCompanion:IsIconLikeDisplayMode(panel.displayMode)
                and not CooldownCompanion:IsAuraPanel(panel) then
                info = UIDropDownMenu_CreateInfo()
                info.text = panel.anchorEligible ~= false and "Exclude from Auto-Anchoring" or "Include in Auto-Anchoring"
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    if panel.anchorEligible ~= false then
                        panel.anchorEligible = false
                    else
                        panel.anchorEligible = nil
                    end
                    CooldownCompanion:EvaluateResourceBars()
                    CooldownCompanion:UpdateAnchorStacking()
                    CooldownCompanion:EvaluateCastBar()
                    CooldownCompanion:EvaluateFrameAnchoring()
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(info, level)
            end

            -- Stable external anchor (Core/ExternalAnchorFrame.lua): one
            -- marked panel per spec. A cursor-anchored panel cannot provide
            -- a stable position for other addons.
            if not (CooldownCompanion.IsGroupCursorAnchored and CooldownCompanion:IsGroupCursorAnchored(panel)) then
                local holderId = CooldownCompanion:GetExternalAnchorPanelId()
                local isHolder = holderId ~= nil and holderId == tonumber(panelId)
                local holder = holderId and db.groups[holderId] or nil
                local holderName = holder and (holder.name or ("Panel " .. tostring(holderId))) or "none"
                info = UIDropDownMenu_CreateInfo()
                info.text = isHolder and "Clear External Anchor" or "Use as External Anchor"
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    CooldownCompanion:SetExternalAnchorPanel(not isHolder and panelId or nil)
                    CooldownCompanion:RefreshConfigPanel()
                end
                info.tooltipTitle = "External Anchor"
                info.tooltipText = "Lets other addons, like BigWigs, attach their bars to this panel."
                    .. "\n\nIn the other addon, anchor to the frame named "
                    .. CooldownCompanion:GetExternalAnchorFrameName()
                    .. ". Its bars will then sit on this panel and stay attached as the panel moves or changes size."
                    .. "\n\nSet it once per specialization. Each specialization remembers its own panel, and picking a new panel replaces the old one."
                    .. "\n\nThis specialization uses: " .. holderName
                info.tooltipOnButton = 1
                UIDropDownMenu_AddButton(info, level)
            end

            if ST._IsActiveCDMPanelSource and ST._IsActiveCDMPanelSource(panel)
                and ST._IsCreateTargetContainer and ST._IsCreateTargetContainer(containerId) then
                info = UIDropDownMenu_CreateInfo()
                info.text = "Refresh from Cooldown Manager"
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    ShowPopupAboveConfig("CDC_REFRESH_CDM_PANEL", panel.name or "Panel", {
                        panelId = panelId,
                        containerId = containerId,
                        sourceKey = panel.cdmPanelSource,
                    })
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
                    if panel.displayMode ~= modeInfo.mode
                        and CooldownCompanion:CanChangePanelDisplayMode(panelId, modeInfo.mode) then
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "Switch to " .. modeInfo.label
                        info.notCheckable = true
                        local targetMode = modeInfo.mode
                        info.func = function()
                            CloseDropDownMenus()
                            -- Sections exist only in icon mode, and leaving it
                            -- flattens them for good (placements are not
                            -- remembered), so a panel that actually has some
                            -- says so before the switch instead of after.
                            if targetMode ~= "icons" and ST.GetSectionsForLayout(panel) then
                                ShowPopupAboveConfig("CDC_FLATTEN_PANEL_SECTIONS", panel.name or "Panel", {
                                    panelId = panelId,
                                    containerId = containerId,
                                    targetMode = targetMode,
                                })
                                return
                            end
                            ApplyPanelDisplayModeChange(panelId, containerId, targetMode)
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

            if CooldownCompanion.GetPanelCopyMode and CooldownCompanion:GetPanelCopyMode(panel) then
                info = UIDropDownMenu_CreateInfo()
                info.text = "Copy Panel Settings To..."
                info.notCheckable = true
                info.hasArrow = true
                info.menuList = "COPY_PANEL_SETTINGS"
                info.tooltipTitle = "Copy Panel Settings To..."
                info.tooltipText = "Pick what to copy, then click the panels it should apply to."
                info.tooltipOnButton = 1
                UIDropDownMenu_AddButton(info, level)
            end

            if CooldownCompanion.CanSavePanelTemplate and CooldownCompanion:CanSavePanelTemplate(panelId) then
                info = UIDropDownMenu_CreateInfo()
                info.text = "Templates"
                info.notCheckable = true
                info.hasArrow = true
                info.menuList = "PANEL_TEMPLATES"
                info.tooltipTitle = "Templates"
                info.tooltipText = "Save this panel's look and arrangement, or apply a saved one."
                info.tooltipOnButton = 1
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
        elseif menuList == "COPY_PANEL_SETTINGS" then
            local copyMode = CooldownCompanion.GetPanelCopyMode
                and CooldownCompanion:GetPanelCopyMode(panel) or nil
            local scopes = copyMode
                and CooldownCompanion:GetPanelCopyScopeList(copyMode) or {}
            local scopeLabels = { appearance = "Appearance", indicators = "Indicators" }
            local function AddScopeItem(scopeName, label)
                local info = UIDropDownMenu_CreateInfo()
                info.text = label
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    if ST._ArmCopyPanelSettings then
                        ST._ArmCopyPanelSettings(panelId, scopeName)
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end
            for _, scopeName in ipairs(scopes) do
                AddScopeItem(scopeName, scopeLabels[scopeName] or scopeName)
            end
            if #scopes > 1 then
                AddScopeItem("all", "All Panel Settings")
            end
        elseif menuList == "PANEL_TEMPLATES" then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Save as Template..."
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                ShowPopupAboveConfig("CDC_SAVE_PANEL_TEMPLATE", panel.name or "Panel", {
                    panelId = panelId,
                    defaultName = panel.name or "Panel",
                })
            end
            UIDropDownMenu_AddButton(info, level)

            local function AddTemplateListItem(label, listName)
                local info = UIDropDownMenu_CreateInfo()
                info.text = label
                info.notCheckable = true
                info.hasArrow = true
                info.menuList = listName
                UIDropDownMenu_AddButton(info, level)
            end
            AddTemplateListItem("Apply Template", "APPLY_PANEL_TEMPLATE")
            AddTemplateListItem("Update Template", "UPDATE_PANEL_TEMPLATE")
            AddTemplateListItem("Delete Template", "DELETE_PANEL_TEMPLATE")
        elseif menuList == "APPLY_PANEL_TEMPLATE"
            or menuList == "UPDATE_PANEL_TEMPLATE"
            or menuList == "DELETE_PANEL_TEMPLATE" then
            -- Apply and Update offer the panel's own type; Delete offers the
            -- whole account-wide list, so each entry there carries its type.
            local deleting = menuList == "DELETE_PANEL_TEMPLATE"
            local copyMode = CooldownCompanion.GetPanelCopyMode
                and CooldownCompanion:GetPanelCopyMode(panel) or nil
            local templates = {}
            if deleting then
                templates = GetPanelTemplateList(nil)
            elseif copyMode then
                templates = GetPanelTemplateList(copyMode)
            end
            local function AddTemplateItem(templateId, template)
                local info = UIDropDownMenu_CreateInfo()
                if deleting then
                    info.text = FormatPanelTemplateMenuText(template)
                else
                    info.text = template.name
                end
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    if menuList == "APPLY_PANEL_TEMPLATE" then
                        ApplyPanelTemplateToPanel(templateId, panelId)
                    elseif menuList == "UPDATE_PANEL_TEMPLATE" then
                        ShowPopupAboveConfig("CDC_UPDATE_PANEL_TEMPLATE", template.name, {
                            templateId = templateId,
                            panelId = panelId,
                        })
                    else
                        ShowPopupAboveConfig("CDC_DELETE_PANEL_TEMPLATE", template.name, {
                            templateId = templateId,
                        })
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end
            if #templates == 0 then
                AddNoTemplatesItem(level, not deleting and copyMode
                    and ST._GetPanelModeLabel(copyMode) or nil)
            end
            for _, entry in ipairs(templates) do
                AddTemplateItem(entry.id, entry.template)
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

local function ResolveContainerScope(containerId, container)
    if CooldownCompanion.ResolveContainerClassScope then
        return CooldownCompanion:ResolveContainerClassScope(container or containerId)
    end
    if container and container.isGlobal then
        return { scope = "global", sectionKey = "global", runtimeVisible = true }
    end
    if container and container.createdBy == CooldownCompanion.db.keys.char then
        return { scope = "current-class", sectionKey = "char", runtimeVisible = true }
    end
    return { scope = "invalid", sectionKey = "invalid", runtimeVisible = false }
end

-- Startup selection and Navigator sections must agree on the first Group.
local function BuildOrderedContainerItems(db, containerIds, searchResults)
    local items = {}
    local specId = CooldownCompanion._currentSpecId
    for _, cid in ipairs(containerIds) do
        if not searchResults or searchResults.containerMatches[cid] then
            items[#items + 1] = {
                kind = "container",
                id = cid,
                order = CooldownCompanion:GetOrderForSpec(db.groupContainers[cid], specId, cid),
            }
        end
    end
    table.sort(items, function(a, b)
        if a.order == b.order then return a.id < b.id end
        return a.order < b.order
    end)
    return items
end

local function IsNavigatorContainerInactive(container, stats)
    if not container or container.enabled == false then return true end
    if not stats or not stats.hasButtons then return true end
    return stats.hasActivePanel ~= true
end

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

local function MaybeSelectInitialConfigContainer()
    if CS.initialContainerSelectionAttempted then return end
    CS.initialContainerSelectionAttempted = true

    -- An explicit destination or workflow opened before the first refresh wins.
    if CooldownCompanion._unsupportedLegacyProfile
        or CS.selectedContainer or CS.selectedGroup or CS.selectedButton
        or CS.selectedRotationAssistantEntry or CS.barsEntrySelected
        or CS.selectedResourcePowerType or CS.selectedCustomBarId
        or CS.castFramesSelectedItem or CS.unifiedBarKind
        or next(CS.selectedGroups) or next(CS.selectedPanels)
        or next(CS.selectedButtons) or next(CS.selectedCustomBars)
        or CS.importMode or CS.exportMode or CS.talentPickerMode
        or CS.copyPanelSettings or CS.otherClassLibraryActive
        or CS.inlineTextureBrowserOpen or CS.addingToPanelId or CS.dragState
        or (CS.configSearchText and CS.configSearchText ~= "")
        or (CS.tutorialRuntime and CS.tutorialRuntime.active) then
        return
    end

    local db = CooldownCompanion.db.profile
    local containerIds, included = {}, {}
    for id, container in pairs(db.groupContainers or {}) do
        if ResolveContainerScope(id, container).scope == "current-class" then
            containerIds[#containerIds + 1] = id
            included[id] = true
        end
    end
    local stats = BuildColumn1ContainerStats(db, included)
    for _, item in ipairs(BuildOrderedContainerItems(db, containerIds)) do
        if not IsNavigatorContainerInactive(db.groupContainers[item.id], stats[item.id]) then
            SelectConfigContainer(item.id)
            CS.expandedContainer = item.id
            CS.peekedContainers[item.id] = nil
            return
        end
    end
end

ST._MaybeSelectInitialConfigContainer = MaybeSelectInitialConfigContainer

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

-- Exported so every create surface answers "can this Group take a new Panel?"
-- with the same class-scope rule.
ST._IsCreateTargetContainer = IsCreateTargetContainer

-- The only panel-create path the overview's add tile and the Group context
-- menu use, so a panel gets the same per-type defaults whichever surface
-- created it.
-- PanelShared loads after this file, so the ST lookups stay at call time.
local function CreatePanelInContainer(containerId, displayMode)
    if not (containerId and ST._CreatePanelInSelectedContainer) then
        return
    end
    if not IsCreateTargetContainer(containerId) then
        return
    end
    local opts = ST._BuildPanelCreateOptions and ST._BuildPanelCreateOptions(displayMode) or nil
    ST._CreatePanelInSelectedContainer(displayMode, opts, containerId)
end

-- Exported so the Group overview's add tile creates panels through the same
-- path as the Group context menu.
ST._CreatePanelInContainer = CreatePanelInContainer

-- The everyday panel types and their subtypes lead each create menu; the
-- specialists start at this index. PanelShared owns the descriptor, so it owns
-- the split too, and it loads after this file: the lookup stays at call time.
local FALLBACK_FIRST_SPECIALIST_PANEL_TYPE = 3
local function FirstSpecialistPanelTypeIndex()
    return ST._FIRST_SPECIALIST_PANEL_TYPE or FALLBACK_FIRST_SPECIALIST_PANEL_TYPE
end

-- Every create menu offers the account's templates after the specialists,
-- and offers nothing, not even the separator, while there are none. The
-- create path itself lives in PanelShared, which loads after this file.
local function AddPanelTemplateCreateItems(level, containerId)
    local templates = GetPanelTemplateList(nil)
    if #templates == 0 then return end
    UIDropDownMenu_AddSeparator(level)
    for _, entry in ipairs(templates) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = "From Template: " .. FormatPanelTemplateMenuText(entry.template)
        info.notCheckable = true
        if ST._AddPanelTemplateMenuTooltip then
            ST._AddPanelTemplateMenuTooltip(info, entry.template)
        end
        local templateId = entry.id
        info.func = function()
            CloseDropDownMenus()
            if not IsCreateTargetContainer(containerId) then return end
            if ST._CreatePanelFromTemplateInContainer then
                ST._CreatePanelFromTemplateInContainer(containerId, templateId)
            end
        end
        UIDropDownMenu_AddButton(info, level)
    end
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
                CooldownCompanion:SetContainerEnabled(containerId, container.enabled == false)
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
            info.text = container.locked ~= false and "Unlock" or "Lock"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                ToggleContainerLock(containerId)
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
            info.text = "Visibility"
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

            if IsCreateTargetContainer(containerId) then
                info = UIDropDownMenu_CreateInfo()
                info.text = "Add Panel"
                info.notCheckable = true
                info.hasArrow = true
                info.menuList = "ADD_PANEL"
                UIDropDownMenu_AddButton(info, level)
            end

            info = UIDropDownMenu_CreateInfo()
            info.text = "|cffff4444Delete|r"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                ShowPopupAboveConfig("CDC_DELETE_GROUP", container.name, { containerId = containerId })
            end
            UIDropDownMenu_AddButton(info, level)
        elseif menuList == "ADD_PANEL" then
            local firstSpecialist = FirstSpecialistPanelTypeIndex()
            for index, panelType in ipairs(ST._PANEL_TYPES or {}) do
                if index == firstSpecialist then
                    UIDropDownMenu_AddSeparator(level)
                end
                local info = UIDropDownMenu_CreateInfo()
                info.text = panelType.label
                info.notCheckable = true
                if ST._ApplyPanelTypeMenuIndent then
                    ST._ApplyPanelTypeMenuIndent(info, panelType)
                end
                local targetMode = panelType.mode
                info.func = function()
                    CloseDropDownMenus()
                    CreatePanelInContainer(containerId, targetMode)
                end
                UIDropDownMenu_AddButton(info, level)
            end
            AddPanelTemplateCreateItems(level, containerId)
        end
    end, "MENU")

    CS.groupContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.groupContextMenu, "cursor", 0, 0)
end

local function ClearColumn1ButtonBar()
    for _, widget in ipairs(CS.col1BarWidgets) do
        widget:Release()
    end
    wipe(CS.col1BarWidgets)
    CS.col1CreateButton = nil
    CS.col1ArrangeButton = nil
    if CS.col1ButtonBar then
        CS.col1ButtonBar._topRowBtns = nil
        CS.col1ButtonBar:SetScript("OnSizeChanged", nil)
    end
end

local function CreateGroupFromRail()
    local containerId = CooldownCompanion:CreateGroup(GenerateGroupName("New Group"))
    SelectConfigContainer(containerId)
    CooldownCompanion:RefreshConfigPanel()
    if NotifyTutorialAction then
        NotifyTutorialAction("group_created", {
            containerId = containerId,
        })
    end
end

local function EnsurePanelTypeMenu()
    if not CS.panelTypeMenu then
        CS.panelTypeMenu = CreateFrame("Frame", "CDCPanelTypeMenu", UIParent, "UIDropDownMenuTemplate")
    end
    return CS.panelTypeMenu
end

-- The menu can outlive the Group that opened it, so every item re-answers the
-- create gate before acting. `lastIndex` defaults to the end of the descriptor,
-- so a caller can ask for "everything from here on".
local function AddPanelTypeCreateItems(level, containerId, firstIndex, lastIndex)
    local panelTypes = ST._PANEL_TYPES or {}
    for index = firstIndex, math.min(lastIndex or #panelTypes, #panelTypes) do
        local panelType = panelTypes[index]
        if panelType then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "New " .. panelType.label
            info.notCheckable = true
            local displayMode = panelType.mode
            if ST._AddPanelTypeMenuTooltip then
                ST._AddPanelTypeMenuTooltip(info, displayMode)
            end
            if ST._ApplyPanelTypeMenuIndent then
                ST._ApplyPanelTypeMenuIndent(info, panelType)
            end
            info.func = function()
                CloseDropDownMenus()
                if not IsCreateTargetContainer(containerId) then return end
                CreatePanelInContainer(containerId, displayMode)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
end

local function AddCDMStarterCreateItem(level, containerId)
    local info = UIDropDownMenu_CreateInfo()
    info.text = "Add Missing CDM Panels"
    info.notCheckable = true
    if ST._AddCDMStarterMenuTooltip then
        ST._AddCDMStarterMenuTooltip(info)
    end
    info.func = function()
        CloseDropDownMenus()
        if not IsCreateTargetContainer(containerId) then return end
        if ST._CreateMissingCDMPanelsInSelectedContainer then
            ST._CreateMissingCDMPanelsInSelectedContainer(containerId)
        end
    end
    UIDropDownMenu_AddButton(info, level)
end

-- Opened by the Group overview's add tile. The everyday types, specialists,
-- saved templates and Cooldown Manager starter share one list, separated into
-- visual groups.
-- It uses the create surfaces' own dropdown frame rather than the Group context
-- menu's, so opening it never toggles or re-initializes that one, and it opens
-- at the cursor because the tile it belongs to moves with the grid.
local function ShowPanelTypeMenuForContainer(containerId)
    if not IsCreateTargetContainer(containerId) then return end

    local menu = EnsurePanelTypeMenu()

    UIDropDownMenu_Initialize(menu, function(_, level)
        level = level or 1
        if level == 1 then
            local firstSpecialist = FirstSpecialistPanelTypeIndex()
            AddPanelTypeCreateItems(level, containerId, 1, firstSpecialist - 1)
            UIDropDownMenu_AddSeparator(level)
            AddPanelTypeCreateItems(level, containerId, firstSpecialist)
            AddPanelTemplateCreateItems(level, containerId)
            UIDropDownMenu_AddSeparator(level)
            AddCDMStarterCreateItem(level, containerId)
        end
    end, "MENU")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, menu, "cursor", 0, 0)
end

-- Exported for the Group overview's add tile.
ST._ShowPanelTypeMenuForContainer = ShowPanelTypeMenuForContainer

-- Keeps the rail's Arrange button truthful when the mode changes underneath
-- the config (auto-exit, /cdc lock). The refresh paths call this through
-- ST.UpdateArrangeBadge; the guard covers bars repopulated for other modes.
local function UpdateArrangeRailButton()
    local arrangeBtn = CS.col1ArrangeButton
    if not arrangeBtn then return end
    if CooldownCompanion.IsArrangeModeActive and CooldownCompanion:IsArrangeModeActive() then
        arrangeBtn:SetText("Lock")
    else
        arrangeBtn:SetText("Unlock")
    end
end
ST.UpdateArrangeBadge = UpdateArrangeRailButton

local function PopulateColumn1ButtonBar()
    if not CS.col1ButtonBar then
        return
    end

    ClearColumn1ButtonBar()

    local createBtn = AceGUI:Create("Button")
    createBtn:SetText("New Group")
    createBtn:SetCallback("OnClick", CreateGroupFromRail)
    createBtn.frame:SetParent(CS.col1ButtonBar)
    createBtn.frame:ClearAllPoints()
    createBtn.frame:SetPoint("TOPLEFT", CS.col1ButtonBar, "TOPLEFT", 0, -1)
    createBtn.frame:SetHeight(28)
    createBtn.frame:Show()
    CS.col1CreateButton = createBtn
    table.insert(CS.col1BarWidgets, createBtn)

    local arrangeBtn = AceGUI:Create("Button")
    arrangeBtn:SetCallback("OnClick", function()
        if CooldownCompanion.IsArrangeModeActive and CooldownCompanion:IsArrangeModeActive() then
            CooldownCompanion:ExitArrangeMode()
        else
            CooldownCompanion:EnterArrangeMode()
        end
        UpdateArrangeRailButton()
    end)
    arrangeBtn:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
        if CooldownCompanion.IsArrangeModeActive and CooldownCompanion:IsArrangeModeActive() then
            GameTooltip:AddLine("Lock panels")
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Locks everything and saves your changes.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Unlock panels")
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Unlocks everything for moving.", 1, 1, 1, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Typing /cdc lock does the same thing.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    arrangeBtn:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
    arrangeBtn.frame:SetParent(CS.col1ButtonBar)
    arrangeBtn.frame:ClearAllPoints()
    arrangeBtn.frame:SetPoint("TOPRIGHT", CS.col1ButtonBar, "TOPRIGHT", 0, -1)
    arrangeBtn.frame:SetHeight(28)
    arrangeBtn.frame:Show()
    CS.col1ArrangeButton = arrangeBtn
    table.insert(CS.col1BarWidgets, arrangeBtn)
    UpdateArrangeRailButton()

    local function SizeMainBarButtons(width)
        local half = math.max(1, math.floor(((width or 0) - 4) / 2))
        createBtn.frame:SetWidth(half)
        arrangeBtn.frame:SetWidth(half)
    end
    CS.col1ButtonBar._topRowBtns = { createBtn.frame, arrangeBtn.frame }
    CS.col1ButtonBar:SetScript("OnSizeChanged", function(_, w)
        SizeMainBarButtons(w)
    end)
    SizeMainBarButtons(CS.col1ButtonBar:GetWidth())
end

local function PopulateOtherClassBrowseButtonBar()
    if not CS.col1ButtonBar then
        return
    end

    ClearColumn1ButtonBar()
    -- Other-class panels are rendered by the pinned mirror. Browsing them no
    -- longer offers a control that hides or rebuilds the current live display.
    CS.col1ButtonBar:Hide()
end

------------------------------------------------------------------------
-- COLUMN 1: Groups
------------------------------------------------------------------------
local COL1_BOTTOM_SCROLL_SLACK = 20

-- Mirrors of ApplyLeftAlignedHeading's private layout values
-- (ConfigSettings/Helpers.lua), which it does not export.
local COL1_HEADING_RULE_ALPHA = 0.35
-- The shared helper reserves 22px at the left for a collapse caret so that
-- collapsible and plain section titles line up inside a tab. The Navigator has
-- no carets at all, so that slot is only dead space here; pull the title out to
-- the column edge instead.
local COL1_HEADING_LABEL_INSET = 3
-- The header line sits half of the helper's 10px top pad below the frame's
-- vertical centre. Any point taken against the FRAME has to carry this same
-- offset -- a LEFT point also declares a vertical centre, and two anchors
-- declaring different centres on one region is over-constrained.
local COL1_HEADING_LINE_Y = -5
-- Stock AceGUI Heading height, i.e. the helper's height minus its top pad.
local COL1_HEADING_STOCK_HEIGHT = 18
local COL1_HEADING_RIGHT_INSET = 3

-- The canonical row-grammar section header. Its helpers live in
-- ConfigSettings/Helpers.lua, which the TOC loads AFTER this file, so they can
-- only be reached lazily at call time -- a file-scope upvalue would capture nil.
--
-- BuildCollapsibleSection is deliberately NOT used: it always attaches a caret,
-- and it reads CS.collapsedSections with the opposite truthiness convention this
-- file uses, which would corrupt the class-section collapse state.
--
-- ColorHeading and ApplyLeftAlignedHeading both hard-code the player class
-- colour. The Navigator's headings are semantic instead (blue for Global, grey
-- for Unloaded), so the label and the rule gradient are re-tinted afterwards.
-- The rule is cached on heading.frame._cdcHeadingRule, so this needs no change
-- to the shared helper.
-- isFirstRow is stated by the caller, which owns render order and knows it, not
-- re-derived here from AceGUI's internal child list.
local function AddColumn1SectionHeading(text, color, isFirstRow)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    heading:SetFullWidth(true)

    if ST._ColorHeading then
        ST._ColorHeading(heading)
    end
    CS.col1Scroll:AddChild(heading)

    -- Everything below re-shapes what ApplyLeftAlignedHeading produced, so it is
    -- all conditional on that helper having actually run. Re-anchoring a stock
    -- centred heading instead would over-constrain its label and leave the
    -- flanking textures shown -- worse than simply falling back to stock.
    if not ST._ApplyLeftAlignedHeading then
        return heading
    end
    ST._ApplyLeftAlignedHeading(heading)

    -- The helper reserves 10px of air ABOVE every section title so that stacked
    -- sections in a tab do not butt together. The first row in the column has
    -- nothing above it to separate from, so that pad reads as dead space under
    -- the "Navigator" title; drop it there and let the title sit at the top.
    --
    -- Everything the helper offsets by its half-pad has to come back to zero in
    -- step -- the label's TOP and LEFT, and the rule's frame-anchored RIGHT.
    -- Leaving any one of them behind over-constrains the region with two
    -- disagreeing vertical centres, which resolves by luck rather than by rule.
    local lineY = isFirstRow and 0 or COL1_HEADING_LINE_Y
    if isFirstRow then
        heading:SetHeight(COL1_HEADING_STOCK_HEIGHT)
    end

    local r = (color and color[1]) or 1
    local g = (color and color[2]) or 1
    local b = (color and color[3]) or 1
    if heading.label then
        heading.label:SetTextColor(r, g, b)
        -- Replaces the helper's LEFT point, closing its caret gap. The rule
        -- follows for free: it anchors to the label's RIGHT edge, not the frame.
        heading.label:SetPoint("LEFT", heading.frame, "LEFT", COL1_HEADING_LABEL_INSET, lineY)
        if isFirstRow then
            heading.label:SetPoint("TOP", heading.frame, "TOP", 0, 0)
        end

        -- The AceGUI Heading pool is shared with every other addon, and
        -- ApplyLeftAlignedHeading's own release handler restores anchors and
        -- height but NOT colour -- so a heading released carrying the Unloaded
        -- grey would hand that grey to the next acquirer. Chain (never replace)
        -- a restore, since the helper already installed a handler here.
        local previousOnRelease = heading.events and heading.events["OnRelease"]
        heading:SetCallback("OnRelease", function(widget, event, ...)
            if previousOnRelease then
                previousOnRelease(widget, event, ...)
            end
            if widget.label then
                widget.label:SetTextColor(1, 0.82, 0)
            end
        end)
    end

    local rule = heading.frame and heading.frame._cdcHeadingRule
    if rule then
        rule:SetGradient(
            "HORIZONTAL",
            CreateColor(r, g, b, COL1_HEADING_RULE_ALPHA),
            CreateColor(r, g, b, 0)
        )
        if isFirstRow then
            rule:SetPoint("RIGHT", heading.frame, "RIGHT", -COL1_HEADING_RIGHT_INSET, 0)
        end
    end

    return heading
end

-- Two jobs, both load-bearing.
--
-- 1. AceGUI's LayoutFinished reads `self.content:SetHeight(height or 0 + 20)` --
--    operator precedence makes that `height or 20`, so the slack it intends has
--    never applied and the last group clips against the bottom edge.
-- 2. An InlineGroup added to the outer List reports only its empty compact
--    height at add time; its children arrive afterwards and do NOT relayout the
--    parent. Because the unloaded bucket renders last, nothing later repairs
--    that stale sum. Adding a child AFTER the groups forces one final parent
--    layout once they have settled.
--
-- A Label was rejected for this: its OnWidthSet remeasures and overwrites the
-- explicit height. Never passed to TrackRenderedRow, so it is not a drop target.
local function AddColumn1BottomSpacer()
    local spacer = AceGUI:Create("SimpleGroup")
    spacer:SetFullWidth(true)
    spacer:SetHeight(COL1_BOTTOM_SCROLL_SLACK)
    spacer.noAutoHeight = true
    CS.col1Scroll:AddChild(spacer)
end

------------------------------------------------------------------------
-- EXPORT MODE: the Navigator re-presents as a pick-what-to-export
-- checklist. Clicks toggle inclusion using the multi-select blue; the
-- normal selection state underneath is never touched, so leaving the
-- mode restores the config exactly as it was.
------------------------------------------------------------------------

local function PopulateExportModeButtonBar()
    if not CS.col1ButtonBar then
        return
    end
    ClearColumn1ButtonBar()

    local exportBtn = AceGUI:Create("Button")
    local nothingChecked = (ST._CountExportSelection and ST._CountExportSelection() or 0) == 0
    exportBtn:SetText(nothingChecked and "Export" or "|cff33ff33Export|r")
    exportBtn:SetDisabled(nothingChecked)
    exportBtn:SetCallback("OnClick", function()
        if ST._ConfirmExportMode then ST._ConfirmExportMode() end
    end)
    exportBtn.frame:SetParent(CS.col1ButtonBar)
    exportBtn.frame:ClearAllPoints()
    exportBtn.frame:SetPoint("TOPLEFT", CS.col1ButtonBar, "TOPLEFT", 0, -1)
    exportBtn.frame:SetHeight(28)
    exportBtn.frame:Show()
    table.insert(CS.col1BarWidgets, exportBtn)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("|cffff4444Cancel|r")
    cancelBtn:SetCallback("OnClick", function()
        if ST._ExitExportMode then ST._ExitExportMode() end
    end)
    cancelBtn.frame:SetParent(CS.col1ButtonBar)
    cancelBtn.frame:ClearAllPoints()
    cancelBtn.frame:SetPoint("TOPRIGHT", CS.col1ButtonBar, "TOPRIGHT", 0, -1)
    cancelBtn.frame:SetHeight(28)
    cancelBtn.frame:Show()
    table.insert(CS.col1BarWidgets, cancelBtn)

    local function SizeExportBarButtons(width)
        local half = math.max(1, math.floor(((width or 0) - 4) / 2))
        exportBtn.frame:SetWidth(half)
        cancelBtn.frame:SetWidth(half)
    end
    CS.col1ButtonBar._topRowBtns = { exportBtn.frame, cancelBtn.frame }
    CS.col1ButtonBar:SetScript("OnSizeChanged", function(_, w)
        SizeExportBarButtons(w)
    end)
    SizeExportBarButtons(CS.col1ButtonBar:GetWidth())
    CS.col1ButtonBar:Show()
end

local function SetExportRowTooltip(entry, title, body)
    entry:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title)
        if body then
            GameTooltip:AddLine(body, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    entry:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function AddExportModeRowShell()
    local groupUnit = AceGUI:Create("InlineGroup")
    groupUnit:SetTitle("")
    groupUnit:SetLayout("List")
    groupUnit:SetFullWidth(true)
    CompactUntitledInlineGroupConfig(groupUnit)
    -- Recycled shells can arrive still dimmed from the resting navigator's
    -- inactive-group treatment; export rows are never dimmed.
    groupUnit.frame:SetAlpha(1)
    CS.col1Scroll:AddChild(groupUnit)
    return groupUnit
end

local function AcquireExportModeRow(text)
    local entry = AceGUI:Create("InteractiveLabel")
    CleanRecycledEntry(entry)
    entry:SetText(text)
    entry:SetFullWidth(true)
    entry:SetFontObject(GameFontHighlight)
    entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    return entry
end

local function RenderExportModeGroups(db, selection, mode)
    local ordered = {}
    for cid, container in pairs(db.groupContainers or {}) do
        local scope = CooldownCompanion.ResolveContainerClassScope
            and CooldownCompanion:ResolveContainerClassScope(container)
            or nil
        if not scope or scope.runtimeVisible == true then
            ordered[#ordered + 1] = {
                cid = cid,
                container = container,
                order = CooldownCompanion:GetOrderForSpec(container, CooldownCompanion._currentSpecId, cid),
            }
        end
    end
    table.sort(ordered, function(a, b) return a.order < b.order end)
    if #ordered == 0 then
        return 0
    end

    AddColumn1SectionHeading("Groups", nil, true)
    for _, item in ipairs(ordered) do
        local cid = item.cid
        local container = item.container
        local panels = CooldownCompanion:GetPanels(cid)
        local total = #panels
        local checkedCount = 0
        for _, panelInfo in ipairs(panels) do
            if selection.panels[panelInfo.groupId] then
                checkedCount = checkedCount + 1
            end
        end
        local isChecked = selection.containers[cid] == true

        local countText
        if total == 0 then
            countText = "empty"
        elseif isChecked and checkedCount < total then
            countText = checkedCount .. " of " .. total
        else
            countText = total .. (total == 1 and " panel" or " panels")
        end

        local groupUnit = AddExportModeRowShell()
        local entry = AcquireExportModeRow(
            (container.name or ("Group " .. tostring(cid))) .. "  |cff777777(" .. countText .. ")|r")
        ApplyConfigRowIcon(entry, GetContainerIcon(cid, db), {
            indent = 2,
            iconSize = TREE.GROUP_ICON_SIZE,
            iconGap = TREE.ICON_GAP,
            rowHeight = TREE.GROUP_ROW_HEIGHT,
            compactRowHeight = 30,
            texCoord = { 0.08, 0.92, 0.08, 0.92 },
            rightPad = 30,
        })
        groupUnit:AddChild(entry)
        if isChecked then
            entry:SetColor(0.4, 0.7, 1.0)
        end

        if total > 0 then
            ConfigureTreeExpandButton(entry, mode.expanded[cid] == true, false, function()
                if mode.expanded[cid] then
                    mode.expanded[cid] = nil
                else
                    mode.expanded[cid] = true
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
        end

        entry:SetCallback("OnClick", function(_, _, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            if isChecked then
                selection.containers[cid] = nil
                for _, panelInfo in ipairs(panels) do
                    selection.panels[panelInfo.groupId] = nil
                end
            else
                selection.containers[cid] = true
                for _, panelInfo in ipairs(panels) do
                    selection.panels[panelInfo.groupId] = true
                end
            end
            CooldownCompanion:RefreshConfigPanel()
        end)

        if mode.expanded[cid] then
            for _, panelInfo in ipairs(panels) do
                local panelId = panelInfo.groupId
                local panel = panelInfo.group
                local panelEntry = AcquireExportModeRow(panel.name or ("Panel " .. tostring(panelId)))
                local iconTexture = 134400
                local iconAtlas
                local iconVertexColor
                local iconDesaturated = false
                local iconTexCoord
                if panel.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
                    iconTexture = CooldownCompanion:GetRotationAssistantFallbackIcon()
                    iconTexCoord = { 0.08, 0.92, 0.08, 0.92 }
                else
                    iconAtlas = GetConfigPanelTypeBadgeAtlas(panel.displayMode)
                    local auraTint = GetConfigAuraPanelBadgeTint(panel)
                    if panel.displayMode == "trigger" then
                        iconVertexColor = { 1.0, 0.18, 0.78, 1 }
                        iconDesaturated = true
                    elseif auraTint then
                        iconVertexColor = auraTint
                        iconDesaturated = true
                    end
                end
                ApplyConfigRowIcon(panelEntry, iconTexture, {
                    atlas = iconAtlas,
                    desaturated = iconDesaturated,
                    indent = TREE.PANEL_INDENT,
                    iconSize = TREE.PANEL_ICON_SIZE,
                    iconGap = TREE.ICON_GAP,
                    rowHeight = TREE.PANEL_ROW_HEIGHT,
                    compactRowHeight = 24,
                    texCoord = iconTexCoord,
                    vertexColor = iconVertexColor,
                })
                if selection.panels[panelId] then
                    panelEntry:SetColor(0.4, 0.7, 1.0)
                end
                panelEntry:SetCallback("OnClick", function(_, _, mouseButton)
                    if mouseButton ~= "LeftButton" then return end
                    if selection.panels[panelId] then
                        selection.panels[panelId] = nil
                        local anyLeft = false
                        for _, other in ipairs(panels) do
                            if selection.panels[other.groupId] then
                                anyLeft = true
                                break
                            end
                        end
                        if not anyLeft then
                            selection.containers[cid] = nil
                        end
                    else
                        selection.panels[panelId] = true
                        selection.containers[cid] = true
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end)
                groupUnit:AddChild(panelEntry)
            end
        end
    end
    return #ordered
end

local function RenderExportModeResources(selection, isFirstSection)
    if not (ST._IsResourcesExportable and ST._IsResourcesExportable()) then
        return
    end

    AddColumn1SectionHeading("Resources", nil, isFirstSection)
    local shell = AddExportModeRowShell()
    local entry = AcquireExportModeRow("Resources")
    ApplyConfigRowIcon(entry, 134400, {
        atlas = "ui_adv_health",
        indent = 2,
        iconSize = TREE.GROUP_ICON_SIZE,
        iconGap = TREE.ICON_GAP,
        rowHeight = TREE.GROUP_ROW_HEIGHT,
        compactRowHeight = 30,
    })
    shell:AddChild(entry)
    if selection.resources then
        entry:SetColor(0.4, 0.7, 1.0)
    end
    SetExportRowTooltip(entry, "Resources",
        "Your whole Resources setup: resources, styling, layout order, and Custom Bars.")
    entry:SetCallback("OnClick", function(_, _, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        selection.resources = not selection.resources
        CooldownCompanion:RefreshConfigPanel()
    end)
end

local function RenderExportModeCustomBars(selection, mode, isFirstSection)
    local bars = ST._GetExportableCustomBars and ST._GetExportableCustomBars() or {}
    if #bars == 0 then
        return
    end

    local includedByResources = selection.resources == true
    local checkedCount = 0
    for _, info in ipairs(bars) do
        if selection.customBars[info.customBarId] then
            checkedCount = checkedCount + 1
        end
    end

    AddColumn1SectionHeading("Custom Bars", nil, isFirstSection)
    local shell = AddExportModeRowShell()
    if includedByResources then
        shell.frame:SetAlpha(0.58)
    end

    local countText
    if includedByResources then
        countText = "with Resources"
    elseif checkedCount > 0 and checkedCount < #bars then
        countText = checkedCount .. " of " .. #bars
    else
        countText = tostring(#bars)
    end
    local entry = AcquireExportModeRow("Custom Bars  |cff777777(" .. countText .. ")|r")
    ApplyConfigRowIcon(entry, bars[1].icon, {
        indent = 2,
        iconSize = TREE.GROUP_ICON_SIZE,
        iconGap = TREE.ICON_GAP,
        rowHeight = TREE.GROUP_ROW_HEIGHT,
        compactRowHeight = 30,
        texCoord = { 0.08, 0.92, 0.08, 0.92 },
        rightPad = 30,
    })
    shell:AddChild(entry)
    if includedByResources or checkedCount > 0 then
        entry:SetColor(0.4, 0.7, 1.0)
    end

    ConfigureTreeExpandButton(entry, mode.expanded.customBars == true, false, function()
        if mode.expanded.customBars then
            mode.expanded.customBars = nil
        else
            mode.expanded.customBars = true
        end
        CooldownCompanion:RefreshConfigPanel()
    end)

    if includedByResources then
        SetExportRowTooltip(entry, "Custom Bars", "Included in the Resources setup.")
    else
        entry:SetCallback("OnClick", function(_, _, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            local allChecked = checkedCount == #bars
            for _, info in ipairs(bars) do
                selection.customBars[info.customBarId] = (not allChecked) and true or nil
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
    end

    if mode.expanded.customBars then
        for _, info in ipairs(bars) do
            local barEntry = AcquireExportModeRow(info.label)
            ApplyConfigRowIcon(barEntry, info.icon, {
                indent = TREE.PANEL_INDENT,
                iconSize = TREE.PANEL_ICON_SIZE,
                iconGap = TREE.ICON_GAP,
                rowHeight = TREE.PANEL_ROW_HEIGHT,
                compactRowHeight = 24,
                texCoord = { 0.08, 0.92, 0.08, 0.92 },
            })
            if includedByResources or selection.customBars[info.customBarId] then
                barEntry:SetColor(0.4, 0.7, 1.0)
            end
            if includedByResources then
                SetExportRowTooltip(barEntry, info.label, "Included in the Resources setup.")
            else
                local customBarId = info.customBarId
                barEntry:SetCallback("OnClick", function(_, _, mouseButton)
                    if mouseButton ~= "LeftButton" then return end
                    if selection.customBars[customBarId] then
                        selection.customBars[customBarId] = nil
                    else
                        selection.customBars[customBarId] = true
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end)
            end
            shell:AddChild(barEntry)
        end
    end
end

local function RenderExportModeNavigator(db)
    if CS.col1DestinationBar then
        CS.col1DestinationBar:Hide()
    end

    local mode = CS.exportMode
    local selection = mode.selection

    local groupCount = RenderExportModeGroups(db, selection, mode)
    RenderExportModeResources(selection, groupCount == 0)
    RenderExportModeCustomBars(selection, mode, false)

    AddColumn1BottomSpacer()
    PopulateExportModeButtonBar()
end

------------------------------------------------------------------------
-- IMPORT MODE: the whole flow lives in the wide column's paste-and-review
-- surface, so the Navigator goes quiet and carries only the mode's
-- confirm/cancel pills. The Import pill mirrors the review: its label is
-- the review's accept verb and it only goes green when the paste can
-- actually apply.
------------------------------------------------------------------------

local function PopulateImportModeButtonBar()
    if not CS.col1ButtonBar then
        return
    end
    ClearColumn1ButtonBar()

    local importBtn = AceGUI:Create("Button")
    local function UpdateImportPill()
        local canConfirm = ST._CanConfirmImportMode and ST._CanConfirmImportMode() or false
        local acceptText = ST._GetImportModeAcceptText and ST._GetImportModeAcceptText() or "Import"
        importBtn:SetText(canConfirm and ("|cff33ff33" .. acceptText .. "|r") or acceptText)
        importBtn:SetDisabled(not canConfirm)
    end
    importBtn:SetCallback("OnClick", function()
        if ST._ConfirmImportMode then ST._ConfirmImportMode() end
    end)
    importBtn.frame:SetParent(CS.col1ButtonBar)
    importBtn.frame:ClearAllPoints()
    importBtn.frame:SetPoint("TOPLEFT", CS.col1ButtonBar, "TOPLEFT", 0, -1)
    importBtn.frame:SetHeight(28)
    importBtn.frame:Show()
    table.insert(CS.col1BarWidgets, importBtn)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("|cffff4444Cancel|r")
    cancelBtn:SetCallback("OnClick", function()
        if ST._ExitImportMode then ST._ExitImportMode() end
    end)
    cancelBtn.frame:SetParent(CS.col1ButtonBar)
    cancelBtn.frame:ClearAllPoints()
    cancelBtn.frame:SetPoint("TOPRIGHT", CS.col1ButtonBar, "TOPRIGHT", 0, -1)
    cancelBtn.frame:SetHeight(28)
    cancelBtn.frame:Show()
    table.insert(CS.col1BarWidgets, cancelBtn)

    local function SizeImportBarButtons(width)
        local half = math.max(1, math.floor(((width or 0) - 4) / 2))
        importBtn.frame:SetWidth(half)
        cancelBtn.frame:SetWidth(half)
    end
    CS.col1ButtonBar._topRowBtns = { importBtn.frame, cancelBtn.frame }
    CS.col1ButtonBar:SetScript("OnSizeChanged", function(_, w)
        SizeImportBarButtons(w)
    end)
    SizeImportBarButtons(CS.col1ButtonBar:GetWidth())
    CS.col1ButtonBar:Show()

    -- Reclassifying a paste only re-renders the wide column's review area;
    -- the mode pokes this so the pill tracks it without a full refresh.
    if CS.importMode then
        CS.importMode._updatePill = UpdateImportPill
    end
    UpdateImportPill()
end

local function RenderImportModeNavigator()
    if CS.col1DestinationBar then
        CS.col1DestinationBar:Hide()
    end

    local spacer = AceGUI:Create("SimpleGroup")
    spacer:SetFullWidth(true)
    spacer:SetHeight(20)
    spacer.noAutoHeight = true
    CS.col1Scroll:AddChild(spacer)

    local header = AceGUI:Create("Label")
    header:SetText("Paste an import string on the right.")
    header:SetFullWidth(true)
    header:SetJustifyH("CENTER")
    header:SetFont((GameFontNormal:GetFont()), 12, "")
    header:SetColor(0.7, 0.7, 0.7)
    header.label:SetWordWrap(true)
    header.label:SetNonSpaceWrap(true)
    header.label:SetMaxLines(0)
    CS.col1Scroll:AddChild(header)

    AddColumn1BottomSpacer()
    PopulateImportModeButtonBar()
end

local function RefreshColumn1(preserveDrag)
    if not CS.col1Scroll then return end
    CS.col1ResourcesButton = nil

    CS.col1Scroll.frame:Show()

    -- Copy Panel Settings banner: kept in step on every rebuild, whichever
    -- render path the column takes below (it hides itself when unarmed and
    -- cancels a mode whose source panel is gone).
    if ST._UpdateCopyPanelSettingsBanner then
        ST._UpdateCopyPanelSettingsBanner()
    end

    if CS.col1ButtonBar then CS.col1ButtonBar:Show() end

    if not preserveDrag then CancelDrag() end
    CS.col1Scroll:ReleaseChildren()
    -- Copy Panel Settings row washes ride recycled row frames, so every
    -- rebuild starts from none shown and re-applies to what is eligible now.
    if ST._ResetCopyPanelRowVisuals then
        ST._ResetCopyPanelRowVisuals()
    end
    CS._panelDropTargets = {}
    if CS._UpdatePanelDropScan then
        CS._UpdatePanelDropScan()
    end

    local db = CooldownCompanion.db.profile
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

    -- Import mode forks ahead of the unsupported-profile screen on
    -- purpose: restoring a backup is the way out of one.
    if CS.importMode then
        RenderImportModeNavigator()
        return
    end

    if CooldownCompanion._unsupportedLegacyProfile then
        ClearOtherClassBrowseState()
        if CS.col1ButtonBar then CS.col1ButtonBar:Hide() end
        if CS.col1DestinationBar then CS.col1DestinationBar:Hide() end

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
        AddColumn1BottomSpacer()
        return
    end

    if CS.exportMode then
        RenderExportModeNavigator(db)
        return
    end

    local containerStats = {}

    -- Track all rendered rows for drag system: sequential index -> metadata
    local col1RenderedRows = {}

    local function TrackRenderedRow(meta)
        col1RenderedRows[#col1RenderedRows + 1] = meta
        return meta
    end

    -- Build the flat Group order for a section.
    local function BuildSectionItems(section, sectionContainerIds)
        return BuildOrderedContainerItems(db, sectionContainerIds, searchResults)
    end

    local function IsContainerInactive(containerId, container)
        return IsNavigatorContainerInactive(container, containerStats[containerId])
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
            + ConfigureGenericRenameBadge(
                entry, container.name, IsGenericGroupName(container.name),
                { containerId = containerId }, rightReserve
            )
        ConfigureGroupHeaderLayout(entry, rightReserve)

        if CS.selectedGroups[containerId] then
            entry:SetColor(0.4, 0.7, 1.0)
        elseif CS.selectedContainer == containerId
            and not CS.selectedGroup
            and not CS.barsEntrySelected then
            entry:SetColor(0, 1, 0)
        elseif isInactive then
            entry:SetColor(0.55, 0.55, 0.55)
        end

        entry.frame:SetScript("OnMouseUp", function(_, button)
            if CS.dragState and CS.dragState.phase == "active" then return end
            -- Escape already cancelled this drag; the release the user is still
            -- holding belongs to that cancel, never to a click on the row.
            if button == "LeftButton" and ST._ConsumeDragEscapeMouseUp() then return end
            -- Copy Panel Settings mode: right-click anywhere in the tree
            -- cancels, matching the entry copy mode's grammar. Left-clicks on
            -- Group rows keep working - expanding a Group is part of reaching
            -- its panels.
            if CS.copyPanelSettings and button == "RightButton" then
                if ST._CancelCopyPanelSettings then
                    ST._CancelCopyPanelSettings()
                end
                return
            end
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
            elseif button == "MiddleButton" and not browsePanels then
                ToggleContainerLock(containerId)
            end
        end)

        local disableDrag = searchResults ~= nil or (options and options.disableDrag == true)
        if not disableDrag then
            entry:SetCallback("OnClick", function(_, _, mouseButton)
                if mouseButton ~= "LeftButton"
                    or IsShiftKeyDown()
                    or IsControlKeyDown()
                    or GetCursorInfo()
                    or CS.copyPanelSettings then
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
                    local auraTint = GetConfigAuraPanelBadgeTint(panel)
                    if panel.displayMode == "trigger" then
                        vertexColor = { 1.0, 0.18, 0.78, 1 }
                        desaturated = true
                    elseif auraTint then
                        -- Aura Panel polarity: green tracks the player's buffs,
                        -- red tracks target debuffs. Desaturated so the tint is
                        -- the badge's whole color, not a wash over its gold.
                        vertexColor = auraTint
                        desaturated = true
                    end
                end
                -- Pack visible badges next to the count, without leaving a
                -- vacant warning slot in normal or compact rows.
                local metaReserve = 4 + ConfigureTreePanelMeta(
                    panelEntry,
                    GetConfigPanelEntryCount(panel),
                    panel.enabled == false,
                    panel.enabled ~= false and ConfigPanelHasWarning(panel)
                )
                local resourceReserve = SetupPanelResourceIndicator(
                    panelEntry, panelId, metaReserve + 2
                )
                local renameReserve = ConfigureGenericRenameBadge(
                    panelEntry, panel.name, IsGenericPanelName(panel.name),
                    { groupId = panelId }, metaReserve + resourceReserve
                )
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
                    rightPad = metaReserve + 4 + resourceReserve + renameReserve,
                })
                panelEntry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")

                if CS.selectedPanels[panelId] then
                    panelEntry:SetColor(0.4, 0.7, 1.0)
                elseif CS.selectedGroup == panelId
                    and CS.selectedButton == nil
                    and CS.selectedRotationAssistantEntry ~= true
                    and not next(CS.selectedButtons) then
                    panelEntry:SetColor(0, 1, 0)
                elseif panel.enabled == false or isInactive then
                    panelEntry:SetColor(0.5, 0.5, 0.5)
                end

                groupUnit:AddChild(panelEntry)
                firstPanelEntry = firstPanelEntry or panelEntry
                lastPanelEntry = panelEntry

                -- Copy Panel Settings mode: green ring + tint on eligible
                -- target rows; hides its own overlay when the mode is off.
                -- After AddChild, so the overlay's frame level reads the row's
                -- settled one.
                if ST._ApplyCopyPanelRowVisuals then
                    ST._ApplyCopyPanelRowVisuals(panelEntry, panelId)
                end

                if not disableDrag then
                    panelEntry:SetCallback("OnClick", function(_, _, mouseButton)
                        if mouseButton ~= "LeftButton"
                            or IsShiftKeyDown()
                            or IsControlKeyDown()
                            or GetCursorInfo()
                            or CS.copyPanelSettings then
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
                    -- Escape already cancelled this drag; the release the user is
                    -- still holding belongs to that cancel, never to a click.
                    if button == "LeftButton" and ST._ConsumeDragEscapeMouseUp() then return end
                    -- Copy Panel Settings mode: an armed left-click applies to
                    -- this row instead of selecting it (the SOURCE row falls
                    -- through and navigates normally), and right-click cancels
                    -- the mode instead of opening the context menu.
                    if CS.copyPanelSettings then
                        if button == "RightButton" then
                            if ST._CancelCopyPanelSettings then
                                ST._CancelCopyPanelSettings()
                            end
                            return
                        end
                        if button == "LeftButton"
                            and ST._HandleCopyPanelSettingsClick
                            and ST._HandleCopyPanelSettingsClick(panelId) then
                            return
                        end
                    end
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
                            -- A deliberate destination, so it outranks a
                            -- display mode's own default landing tab.
                            CS.panelSettingsTabExplicit = true
                            CooldownCompanion:RefreshConfigPanel()
                        else
                            SelectConfigPanel(panelId, {
                                containerId = containerId,
                                toggle = true,
                            })
                            CooldownCompanion:RefreshConfigPanel()
                        end
                    elseif button == "RightButton" and ST._ShowPanelContextMenu then
                        ST._ShowPanelContextMenu(panelId, containerId)
                    elseif button == "MiddleButton" and not browsePanels then
                        TogglePanelAnchorLock(panelId)
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
                        -- Copy Panel Settings mode: right-click cancels on
                        -- every interactive Navigator row, this one included.
                        if CS.copyPanelSettings and button == "RightButton" then
                            if ST._CancelCopyPanelSettings then
                                ST._CancelCopyPanelSettings()
                            end
                            return
                        end
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
    -- Only the topmost row in the column drops its top pad. RefreshColumn1 owns
    -- render order, so it states this rather than having the heading helper
    -- infer it from AceGUI's internal child list.
    --
    -- A heading is NOT automatically first: the other-class library adds a
    -- "Back" navigation row and then calls RenderSection without classSection,
    -- and a truncated search adds its summary label before any section. Both
    -- must consume the flag, or their heading loses the 10px of air that exists
    -- precisely so a title never butts against the row above it.
    local col1FirstRowPending = true
    local function TakeCol1FirstRow()
        local isFirst = col1FirstRowPending
        col1FirstRowPending = false
        return isFirst
    end

    local standaloneItems = {}
    local deferredUnloadedSections = {}
    local function RenderStandalonePanels()
        if #standaloneItems == 0 then return end
        local allDisabled = true
        for _, item in ipairs(standaloneItems) do
            if item.placement ~= "disabled" then
                allDisabled = false
                break
            end
        end
        if not TakeCol1FirstRow() then
            local spacer = AceGUI:Create("Label")
            spacer:SetText("")
            spacer:SetFullWidth(true)
            spacer:SetHeight(10)
            CS.col1Scroll:AddChild(spacer)
        end
        local groupUnit = AceGUI:Create("InlineGroup")
        groupUnit:SetTitle("")
        groupUnit:SetLayout("List")
        groupUnit:SetFullWidth(true)
        CompactUntitledInlineGroupConfig(groupUnit)
        ConfigureNestedPanelAccent(groupUnit, nil, nil, nil, nil)
        groupUnit.frame:SetAlpha(allDisabled and 0.58 or 1)
        CS.col1Scroll:AddChild(groupUnit)

        local expanded = searchResults ~= nil or CS.standalonePanelsCollapsed ~= true
        local function Toggle()
            CS.standalonePanelsCollapsed = expanded
            CooldownCompanion:RefreshConfigPanel()
        end
        local header = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(header)
        header:SetText("Optional Modules  |cff777777(" .. #standaloneItems .. ")|r")
        header:SetFullWidth(true)
        header:SetFontObject(GameFontHighlight)
        ApplyConfigRowIcon(header, 134400, {
            atlas = "ui_adv_health", indent = 2, desaturated = allDisabled,
            iconSize = TREE.GROUP_ICON_SIZE, iconGap = TREE.ICON_GAP,
            rowHeight = TREE.GROUP_ROW_HEIGHT, compactRowHeight = 30,
        })
        header:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        groupUnit:AddChild(header)
        local expandReserve = not searchResults
            and ConfigureTreeExpandButton(header, expanded, false, Toggle) or 0
        ConfigureGroupHeaderLayout(header, expandReserve + 4)
        header:SetCallback("OnClick", function(_, _, button)
            if button == "LeftButton" and not searchResults then Toggle() end
        end)

        if expanded then
            for _, item in ipairs(standaloneItems) do
                local kind = item.kind
                local entry = AceGUI:Create("InteractiveLabel")
                CleanRecycledEntry(entry)
                entry:SetText(item.label)
                entry:SetFullWidth(true)
                entry:SetFontObject(GameFontHighlight)
                ApplyConfigRowIcon(entry, 134400, {
                    atlas = item.atlas, indent = TREE.PANEL_INDENT,
                    iconSize = TREE.PANEL_ICON_SIZE, iconGap = TREE.ICON_GAP,
                    rowHeight = TREE.PANEL_ROW_HEIGHT, compactRowHeight = 24,
                    rightPad = 88, desaturated = item.placement == "disabled",
                })
                entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                ConfigureTreePanelMeta(entry, nil, false, false)
                local badge = entry.frame._cdcTreePanelMeta.count
                badge:SetWidth(80)
                badge:SetText(item.placement == "disabled" and "Disabled"
                    or item.placement == "independent" and "Independent" or "No anchor")
                local selected = CS.barsEntrySelected and (CS.barWorkspaceKind == kind
                    or (kind == "player" and CS.barWorkspaceKind == "target"))
                local disabled = item.placement == "disabled"
                -- The shell already fades an entirely disabled group.
                entry.frame:SetAlpha(disabled and not allDisabled and 0.58 or 1)
                if selected and disabled then
                    local selection = entry.frame._cdcDisabledModuleSelection
                    if not selection then
                        selection = entry.frame:CreateTexture(nil, "BACKGROUND")
                        selection:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                        selection:SetAllPoints(entry.frame)
                        selection:SetAlpha(0.35)
                        entry.frame._cdcDisabledModuleSelection = selection
                    end
                    selection:Show()
                elseif selected then
                    entry:SetColor(0, 1, 0)
                end
                entry:SetCallback("OnClick", function(_, _, button)
                    if button ~= "LeftButton" then return end
                    ST._OpenBarWorkspace(kind)
                    CooldownCompanion:RefreshConfigPanel()
                end)
                groupUnit:AddChild(entry)
                if kind == "resources" then CS.col1ResourcesButton = entry end
            end
        end
        TrackRenderedRow({
            kind = "aux-block", rowType = "standalone-panels", widget = groupUnit,
            section = "standalone", loadBucket = "aux", acceptsDrop = false,
            previewDraggable = false,
        })
    end

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
                    -- Copy Panel Settings mode: right-click cancels on every
                    -- interactive Navigator row, this one included.
                    if CS.copyPanelSettings and button == "RightButton" then
                        if ST._CancelCopyPanelSettings then
                            ST._CancelCopyPanelSettings()
                        end
                        return
                    end
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

        local deferUnloaded = options and options.deferUnloaded == true
        local useUnloadedOnlyHeading = options
            and options.preferUnloadedHeading
            and #loadedItems == 0
            and #unloadedItems > 0

        if not isClassSection and not (deferUnloaded and #loadedItems == 0 and not isEmpty) then
            local heading = AddColumn1SectionHeading(
                useUnloadedOnlyHeading and "Unloaded Groups" or headingText,
                useUnloadedOnlyHeading and { 0.53, 0.53, 0.53 } or headingColor,
                TakeCol1FirstRow()
            )

            TrackRenderedRow({
                kind = "section-header",
                widget = heading,
                section = section,
                loadBucket = "marker",
                acceptsDrop = false,
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
            })
            return
        end

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

        local function RenderUnloaded()
            if #unloadedItems > 0 and (deferUnloaded or not useUnloadedOnlyHeading) then
                local sep = AddColumn1SectionHeading("Unloaded Groups", { 0.53, 0.53, 0.53 }, TakeCol1FirstRow())

                TrackRenderedRow({
                    kind = "unloaded-divider",
                    widget = sep,
                    section = section,
                    loadBucket = "marker",
                    acceptsDrop = false,
                })
            end

            RenderItems(unloadedItems, "unloaded")
        end
        if deferUnloaded then
            if #unloadedItems > 0 then
                deferredUnloadedSections[#deferredUnloadedSections + 1] = RenderUnloaded
            end
        else
            RenderUnloaded()
        end
    end

    local GetClassInfoByID = ST._GetClassInfoByID

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
                -- Copy Panel Settings mode: right-click cancels on every
                -- interactive Navigator row, this one included.
                if CS.copyPanelSettings and button == "RightButton" then
                    if ST._CancelCopyPanelSettings then
                        ST._CancelCopyPanelSettings()
                    end
                    return
                end
                if button == "LeftButton" and options and options.onClick then
                    options.onClick()
                end
            end)
        end
        if options and options.selected then
            row:SetColor(0, 1, 0)
        end
        CS.col1Scroll:AddChild(row)
        TakeCol1FirstRow()
        TrackRenderedRow({
            kind = kind,
            widget = row,
            section = options and options.section or nil,
            classKey = options and options.classKey or nil,
            loadBucket = "marker",
            acceptsDrop = false,
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

    -- Optional modules follow loaded groups and precede the inactive tail.
    -- Disabled modules and modules without an anchor keep their own destination.
    if not CS.otherClassLibraryActive then
        for _, item in ipairs({
            { kind = "resources", label = "Resource Bars", atlas = "ui_adv_health" },
            { kind = "castbar", label = "Cast Bar", atlas = "ui_adv_health" },
            { kind = "player", label = "Unit Frame Anchoring", atlas = "ui_adv_health" },
        }) do
            local placement, anchorId = ST._GetBarWorkspacePlacement(item.kind)
            local matches = not searchResults
                or item.label:lower():find(searchResults.query, 1, true)
                or ("optional modules"):find(searchResults.query, 1, true)
            if not anchorId and matches then
                item.placement = placement
                standaloneItems[#standaloneItems + 1] = item
            end
        end
    end
    local hasStandaloneRows = #standaloneItems > 0

    if searchResults and not hasStandaloneRows and not next(searchResults.containerMatches) then
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

    if showNewUserEmptyState and CS.barsEntrySelected and ST._IsProfileWelcomeEligible() then
        local back = AceGUI:Create("InteractiveLabel")
        back:SetText("< Back to Get Started")
        back:SetFullWidth(true)
        back:SetCallback("OnClick", function(_, _, button)
            if button ~= "LeftButton" then return end
            ST._ResetConfigSelection(true)
            CooldownCompanion:RefreshConfigPanel()
        end)
        CS.col1Scroll:AddChild(back)
        TakeCol1FirstRow()
    elseif showNewUserEmptyState and not CS.otherClassLibraryActive then
        ClearOtherClassBrowseState()
        TakeCol1FirstRow()

        local spacer = AceGUI:Create("SimpleGroup")
        spacer:SetFullWidth(true)
        spacer:SetHeight(20)
        spacer.noAutoHeight = true
        CS.col1Scroll:AddChild(spacer)

        local header = AceGUI:Create("Label")
        header:SetText("Organize cooldowns with groups.")
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
        desc:SetText("For cooldown entries, start with New Group below. Resource Bars and Cast Bar can be used on their own.")
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
            TakeCol1FirstRow()
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
                    RenderSection("global", globalIds, "Global Groups", ST._COL1_GLOBAL_SECTION_COLOR,
                        { deferUnloaded = true })
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
                    { preferUnloadedHeading = not hasGlobalContent, deferUnloaded = true }
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

    RenderStandalonePanels()
    for _, renderUnloaded in ipairs(deferredUnloadedSections) do renderUnloaded() end
    AddColumn1BottomSpacer()
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
ST._CreateConfigGroup = CreateGroupFromRail
