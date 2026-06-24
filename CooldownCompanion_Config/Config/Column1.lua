--[[
    CooldownCompanion - Config/Column1
    RefreshColumn1 + nested helpers (group list rendering).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local CleanRecycledEntry = ST._CleanRecycledEntry
local ApplyConfigRowIcon = ST._ApplyConfigRowIcon
local ApplyConfigTextRow = ST._ApplyConfigTextRow
local SetupGroupRowIndicators = ST._SetupGroupRowIndicators
local SetupFolderRowIndicators = ST._SetupFolderRowIndicators
local GetConfigRowBadgeReserve = ST._GetConfigRowBadgeReserve
local SetupColumn1MarkerRow = ST._SetupColumn1MarkerRow
local GetContainerIcon = ST._GetContainerIcon
local GetFolderIcon = ST._GetFolderIcon
local OpenFolderIconPicker = ST._OpenFolderIconPicker
local OpenContainerIconPicker = ST._OpenContainerIconPicker
local IsValidIconTexture = ST._IsValidIconTexture
local GenerateFolderName = ST._GenerateFolderName
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local OpenImportReviewWindow = ST._OpenImportReviewWindow
local CancelDrag = ST._CancelDrag
local StartDragTracking = ST._StartDragTracking
local GetScaledCursorPosition = ST._GetScaledCursorPosition
local BuildGroupExportData = ST._BuildGroupExportData
local BuildContainerExportData = ST._BuildContainerExportData
local EncodeExportData = ST._EncodeExportData
local ContainersHaveForeignSpecs = ST._ContainersHaveForeignSpecs
local FolderHasForeignSpecs = ST._FolderHasForeignSpecs
local NotifyTutorialAction = ST._NotifyTutorialAction
local IsConfigFinderActive = ST._IsConfigFinderActive
local BuildConfigFinderResults = ST._BuildConfigFinderResults
local ClearConfigPrimarySelection = ST._ClearConfigPrimarySelection
local SelectConfigFolder = ST._SelectConfigFolder
local SelectConfigContainer = ST._SelectConfigContainer
local ToggleConfigContainerMultiSelect = ST._ToggleConfigContainerMultiSelect
local SelectConfigPanel = ST._SelectConfigPanel

local GenerateGroupName

local function OpenContainerLoadConditions(containerId)
    SelectConfigContainer(containerId)
    CS.selectedContainerTab = "loadconditions"
    CooldownCompanion:RefreshConfigPanel()
end

local function OpenFolderLoadConditions(folderId)
    SelectConfigFolder(folderId)
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

local function ConfigureGenericGroupRenameBadge(entry, container, containerId, nameWidth)
    local badge = EnsureGenericGroupRenameBadge(entry)
    badge:ClearAllPoints()
    badge:SetScript("OnClick", nil)

    if not IsGenericGroupName(container and container.name) then
        badge:Hide()
        return
    end

    local currentName = TrimGroupName(container and container.name)
    if currentName == "" then
        currentName = "New Group"
    end

    badge.icon:SetAtlas("QuestLegendary", false)
    badge.icon:SetVertexColor(1, 0.82, 0, 0.85)
    badge:SetPoint("CENTER", entry.label, "LEFT", nameWidth + 13, 0)
    badge:SetScript("OnClick", function(_, button)
        if button ~= "LeftButton" then return end
        GameTooltip:Hide()
        ShowPopupAboveConfig("CDC_RENAME_GROUP", currentName, { containerId = containerId })
    end)
    badge:Show()
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

local function ResolveContainerScopeForConfig(containerId, container, charKey)
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

local function ResolveFolderScopeForConfig(folderId, folder, charKey)
    if CooldownCompanion.ResolveFolderClassScope then
        return CooldownCompanion:ResolveFolderClassScope(folder or folderId)
    end
    if folder and folder.section == "global" then
        return { scope = "global", sectionKey = "global", runtimeVisible = true }
    end
    if folder and folder.createdBy == charKey then
        return { scope = "current-class", sectionKey = "char", runtimeVisible = true }
    end
    return { scope = "invalid", sectionKey = "invalid", runtimeVisible = false }
end

local function GetFolderTargetsForSection(db, charKey, section)
    local folderList = {}
    for fid, folder in pairs(db.folders) do
        local scope = ResolveFolderScopeForConfig(fid, folder, charKey)
        local folderSection = scope and scope.sectionKey
            or (folder.section == "global" and "global" or "char")
        if folderSection == section then
            folderList[#folderList + 1] = {
                id = fid,
                name = folder.name,
                order = CooldownCompanion:GetOrderForSpec(folder, CooldownCompanion._currentSpecId, fid),
            }
        end
    end
    table.sort(folderList, function(a, b) return a.order < b.order end)
    return folderList
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

local function ShowContainerContextMenu(db, charKey, containerId, container)
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

            local containerScope = ResolveContainerScopeForConfig(containerId, container, charKey)
            local containerSection = containerScope.sectionKey or (container.isGlobal and "global" or "char")
            local folderTargets = GetFolderTargetsForSection(db, charKey, containerSection)
            if #folderTargets > 0 or container.folderId then
                info = UIDropDownMenu_CreateInfo()
                info.text = "Move to Folder"
                info.notCheckable = true
                info.hasArrow = true
                info.menuList = "MOVE_TO_FOLDER"
                UIDropDownMenu_AddButton(info, level)
            end

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

            if not container.folderId then
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
        elseif menuList == "MOVE_TO_FOLDER" then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "(No Folder)"
            info.checked = (container.folderId == nil)
            info.func = function()
                CloseDropDownMenus()
                CooldownCompanion:MoveGroupToFolder(containerId, nil)
                CooldownCompanion:RefreshConfigPanel()
            end
            UIDropDownMenu_AddButton(info, level)

            local containerScope = ResolveContainerScopeForConfig(containerId, container, charKey)
            local containerSection = containerScope.sectionKey or (container.isGlobal and "global" or "char")
            for _, folderTarget in ipairs(GetFolderTargetsForSection(db, charKey, containerSection)) do
                info = UIDropDownMenu_CreateInfo()
                info.text = folderTarget.name
                info.checked = (container.folderId == folderTarget.id)
                info.func = function()
                    CloseDropDownMenus()
                    CooldownCompanion:MoveGroupToFolder(containerId, folderTarget.id)
                    CooldownCompanion:RefreshConfigPanel()
                end
                UIDropDownMenu_AddButton(info, level)
            end
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

local function ShowFolderContextMenu(db, folderId, folder)
    if not CS.folderContextMenu then
        CS.folderContextMenu = CreateFrame("Frame", "CDCFolderContextMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(CS.folderContextMenu, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Rename"
        info.notCheckable = true
        info.func = function()
            CloseDropDownMenus()
            ShowPopupAboveConfig("CDC_RENAME_FOLDER", folder.name, { folderId = folderId })
        end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Add Group"
        info.notCheckable = true
        info.func = function()
            CloseDropDownMenus()
            local charKey = CooldownCompanion.db and CooldownCompanion.db.keys and CooldownCompanion.db.keys.char
            local folderScope = ResolveFolderScopeForConfig(folderId, folder, charKey)
            if folderScope.scope == "other-class" then
                CooldownCompanion:Print("Create new groups in your current class, then move them to Global if needed.")
                return
            end
            local containerId = CooldownCompanion:CreateGroup(GenerateGroupName("New Group"))
            local container = db.groupContainers and db.groupContainers[containerId]
            if container and folderScope.scope == "global" then
                container.isGlobal = true
            end
            CooldownCompanion:MoveGroupToFolder(containerId, folderId, { allowScopeChange = true })
            SelectConfigContainer(containerId)
            CooldownCompanion:RefreshConfigPanel()
        end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Set Folder Icon..."
        info.notCheckable = true
        info.func = function()
            CloseDropDownMenus()
            OpenFolderIconPicker(folderId)
        end
        UIDropDownMenu_AddButton(info, level)

        if type(folder.manualIcon) == "number" or type(folder.manualIcon) == "string" then
            info = UIDropDownMenu_CreateInfo()
            info.text = "Clear Custom Icon"
            info.notCheckable = true
            info.func = function()
                CloseDropDownMenus()
                local currentFolder = db.folders[folderId]
                if currentFolder then
                    currentFolder.manualIcon = nil
                    CooldownCompanion:RefreshConfigPanel()
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end

        info = UIDropDownMenu_CreateInfo()
        info.text = folder.section == "global" and "Move to Current Class Folder" or "Make Global Folder"
        info.notCheckable = true
        info.func = function()
            CloseDropDownMenus()
            if folder.section == "global" and FolderHasForeignSpecs and FolderHasForeignSpecs(folderId) then
                ShowPopupAboveConfig("CDC_UNGLOBAL_FOLDER", folder.name, { folderId = folderId })
                return
            end
            CooldownCompanion:ToggleFolderGlobal(folderId)
            CooldownCompanion:RefreshConfigPanel()
        end
        UIDropDownMenu_AddButton(info, level)

        local containers = db.groupContainers or {}
        local anyLocked = false
        for _, container in pairs(containers) do
            if container.folderId == folderId and container.locked then
                anyLocked = true
                break
            end
        end

        info = UIDropDownMenu_CreateInfo()
        info.text = anyLocked and "Unlock All" or "Lock All"
        info.notCheckable = true
        info.func = function()
            CloseDropDownMenus()
            local newState = not anyLocked
            for cid, container in pairs(containers) do
                if container.folderId == folderId then
                    container.locked = newState
                    CooldownCompanion:UpdateContainerDragHandle(cid, newState)
                    CooldownCompanion:RefreshContainerPanels(cid)
                end
            end
            CooldownCompanion:RefreshConfigPanel()
        end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Spec / Hero Filter"
        info.notCheckable = true
        info.func = function()
            CloseDropDownMenus()
            OpenFolderLoadConditions(folderId)
        end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Export Folder"
        info.notCheckable = true
        info.func = function()
            CloseDropDownMenus()
            local folderData = { name = folder.name }
            if type(folder.manualIcon) == "number" or type(folder.manualIcon) == "string" then
                folderData.manualIcon = folder.manualIcon
            end
            if folder.specs and next(folder.specs) then
                folderData.specs = CopyTable(folder.specs)
            end
            if folder.heroTalents and next(folder.heroTalents) then
                folderData.heroTalents = CopyTable(folder.heroTalents)
            end
            if CooldownCompanion:HasLocalLoadConditions(folder) then
                folderData.loadConditions = CopyTable(folder.loadConditions)
            end

            local orderedCids = {}
            for cid, container in pairs(db.groupContainers) do
                if container.folderId == folderId then
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

            local payload = { type = "folder", version = 2, folder = folderData, containers = exportContainers }
            local exportString = EncodeExportData(payload)
            ShowPopupAboveConfig("CDC_EXPORT_GROUP", nil, { exportString = exportString })
        end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "|cffff4444Delete Folder|r"
        info.notCheckable = true
        info.func = function()
            CloseDropDownMenus()
            ShowPopupAboveConfig("CDC_DELETE_FOLDER", folder.name, { folderId = folderId })
        end
        UIDropDownMenu_AddButton(info, level)
    end, "MENU")

    CS.folderContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.folderContextMenu, "cursor", 0, 0)
end

local function PopulateColumn1ButtonBar()
    if not CS.col1ButtonBar then
        return
    end

    for _, widget in ipairs(CS.col1BarWidgets) do
        widget:Release()
    end
    wipe(CS.col1BarWidgets)

    local barW = CS.col1ButtonBar:GetWidth() or 300
    local thirdW = (barW - 6) / 3

    local newGroupBtn = AceGUI:Create("Button")
    newGroupBtn:SetText("New Group")
    newGroupBtn:SetCallback("OnClick", function()
        local containerId, groupId = CooldownCompanion:CreateGroup(GenerateGroupName("New Group"))
        SelectConfigContainer(containerId)
        CooldownCompanion:RefreshConfigPanel()
        if NotifyTutorialAction then
            NotifyTutorialAction("group_created", {
                containerId = containerId,
                groupId = groupId,
            })
        end
    end)
    newGroupBtn.frame:SetParent(CS.col1ButtonBar)
    newGroupBtn.frame:ClearAllPoints()
    newGroupBtn.frame:SetPoint("TOPLEFT", CS.col1ButtonBar, "TOPLEFT", 0, -1)
    newGroupBtn.frame:SetWidth(thirdW)
    newGroupBtn.frame:SetHeight(28)
    newGroupBtn.frame:Show()
    if CS.tutorialAnchors then
        CS.tutorialAnchors.new_group_button = newGroupBtn.frame
    end
    table.insert(CS.col1BarWidgets, newGroupBtn)

    local newFolderBtn = AceGUI:Create("Button")
    newFolderBtn:SetText("New Folder")
    newFolderBtn:SetCallback("OnClick", function()
        CooldownCompanion:CreateFolder(GenerateFolderName("New Folder"), "char")
        CooldownCompanion:RefreshConfigPanel()
    end)
    newFolderBtn.frame:SetParent(CS.col1ButtonBar)
    newFolderBtn.frame:ClearAllPoints()
    newFolderBtn.frame:SetPoint("LEFT", newGroupBtn.frame, "RIGHT", 3, 0)
    newFolderBtn.frame:SetWidth(thirdW)
    newFolderBtn.frame:SetHeight(28)
    newFolderBtn.frame:Show()
    table.insert(CS.col1BarWidgets, newFolderBtn)

    local importBtn = AceGUI:Create("Button")
    importBtn:SetText("Import")
    importBtn:SetCallback("OnClick", function()
        OpenImportReviewWindow()
    end)
    importBtn.frame:SetParent(CS.col1ButtonBar)
    importBtn.frame:ClearAllPoints()
    importBtn.frame:SetPoint("LEFT", newFolderBtn.frame, "RIGHT", 3, 0)
    importBtn.frame:SetWidth(thirdW)
    importBtn.frame:SetHeight(28)
    importBtn.frame:Show()
    table.insert(CS.col1BarWidgets, importBtn)

    CS.col1ButtonBar._topRowBtns = { newGroupBtn.frame, newFolderBtn.frame, importBtn.frame }
    CS.col1ButtonBar:SetScript("OnSizeChanged", function(self, w)
        if self._topRowBtns then
            local tw = (w - 6) / 3
            for _, frame in ipairs(self._topRowBtns) do
                frame:SetWidth(tw)
            end
        end
    end)
end

------------------------------------------------------------------------
-- COLUMN 1: Groups
------------------------------------------------------------------------
local function RefreshColumn1(preserveDrag)
    if not CS.col1Scroll then return end

    -- Bars & Frames panel mode: take over col1 with the bar/frame tab group
    if CS.resourceBarPanelActive then
        CS.otherClassLibraryActive = false
        CS.otherClassLibraryClassKey = nil
        CancelDrag()
        CS.HideAutocomplete()
        CS.col1Scroll.frame:Hide()
        if CS.col1ButtonBar then CS.col1ButtonBar:Hide() end

        local col1 = CS.configFrame and CS.configFrame.col1
        if col1 then
            if not col1._barsPanelTabGroup then
                local tabGroup = AceGUI:Create("TabGroup")
                tabGroup:SetTabs({
                    { value = "resource_anchoring", text = "Resources" },
                    { value = "castbar_anchoring",  text = "Cast Bar" },
                    { value = "frame_anchoring",    text = "Unit Frames" },
                })
                tabGroup:SetLayout("Fill")
                tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
                    CS.barPanelTab = tab
                    -- Clean up info buttons from previous tab before recycling widgets
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
                    if tab == "resource_anchoring" then
                        ST._BuildResourceBarAnchoringPanel(scroll)
                    elseif tab == "castbar_anchoring" then
                        ST._BuildCastBarAnchoringPanel(scroll)
                    elseif tab == "frame_anchoring" then
                        ST._BuildFrameAnchoringPlayerPanel(scroll)
                        ST._BuildFrameAnchoringTargetPanel(scroll)
                    end
                    ST._RefreshColumn2()
                    ST._RefreshColumn3()
                end)
                tabGroup.frame:SetParent(col1.content)
                tabGroup.frame:ClearAllPoints()
                tabGroup.frame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, 0)
                tabGroup.frame:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 0)
                col1._barsPanelTabGroup = tabGroup
            end
            col1._barsPanelTabGroup.frame:Show()
            col1._barsPanelTabGroup:SelectTab(CS.barPanelTab)
        end
        return
    end

    -- Normal mode: hide bars tab group, show groups content
    local col1NormalMode = CS.configFrame and CS.configFrame.col1
    if col1NormalMode and col1NormalMode._barsPanelTabGroup then
        col1NormalMode._barsPanelTabGroup.frame:Hide()
    end
    CS.col1Scroll.frame:Show()

    if CS.col1ButtonBar then CS.col1ButtonBar:Show() end

    if not preserveDrag then CancelDrag() end
    CS.col1Scroll:ReleaseChildren()

    -- Hide all accent bars from previous render
    for i, bar in ipairs(CS.folderAccentBars) do
        bar:Hide()
        bar:ClearAllPoints()
        bar._cdcFolderAccentActive = nil
    end
    local accentBarIndex = 0  -- pool cursor, incremented as bars are used

    local db = CooldownCompanion.db.profile
    local charKey = CooldownCompanion.db.keys.char
    local searchResults = IsConfigFinderActive and IsConfigFinderActive() and BuildConfigFinderResults and BuildConfigFinderResults() or nil

    -- Ensure folders table exists
    if not db.folders then db.folders = {} end

    if CooldownCompanion._unsupportedLegacyProfile then
        CS.otherClassLibraryActive = false
        CS.otherClassLibraryClassKey = nil
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

    -- Count current children in scroll widget
    local function CountScrollChildren()
        local children = { CS.col1Scroll.content:GetChildren() }
        return #children
    end

    -- Track all rendered rows for drag system: sequential index -> metadata
    local col1RenderedRows = {}

    local function TrackRenderedRow(meta)
        col1RenderedRows[#col1RenderedRows + 1] = meta
        return meta
    end

    local function AddAuxWidget(widget, sectionTag, ownerKind, ownerId, ownerFolderId)
        CS.col1Scroll:AddChild(widget)
        TrackRenderedRow({
            kind = "aux-block",
            widget = widget,
            section = sectionTag,
            loadBucket = "aux",
            acceptsDrop = false,
            previewProxy = false,
            layoutOnly = true,
            ownerKind = ownerKind,
            ownerId = ownerId,
            ownerFolderId = ownerFolderId,
        })
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

    local function ResolveFolderScope(folderId, folder)
        if CooldownCompanion.ResolveFolderClassScope then
            return CooldownCompanion:ResolveFolderClassScope(folder or folderId)
        end
        if folder and folder.section == "global" then
            return { scope = "global", sectionKey = "global", runtimeVisible = true }
        end
        if folder and folder.createdBy == charKey then
            return { scope = "current-class", sectionKey = "char", runtimeVisible = true }
        end
        return { scope = "invalid", sectionKey = "invalid", runtimeVisible = false }
    end

    local function ScopeMatchesSection(scope, section)
        return scope and scope.sectionKey == section
    end

    -- Build top-level items for a section (folders + loose containers), sorted by order
    local function BuildSectionItems(section, sectionContainerIds)
        -- Collect folders for this section
        local sectionFolderIds = {}
        for fid, folder in pairs(db.folders) do
            local scope = ResolveFolderScope(fid, folder)
            if ScopeMatchesSection(scope, section) then
                table.insert(sectionFolderIds, fid)
            end
        end

        -- Determine which containers are in valid folders for this section
        local validFolderIds = {}
        for _, fid in ipairs(sectionFolderIds) do
            validFolderIds[fid] = true
        end

        -- Split containers: those in a valid folder vs loose
        local looseContainerIds = {}
        local folderChildContainers = {}  -- [folderId] = { containerId, ... }
        for _, cid in ipairs(sectionContainerIds) do
            local container = db.groupContainers[cid]
            if searchResults and not searchResults.containerMatches[cid] then
                -- Search hides non-matching groups while preserving folder context
                -- for the groups that do match.
            elseif container.folderId and validFolderIds[container.folderId] then
                if not folderChildContainers[container.folderId] then
                    folderChildContainers[container.folderId] = {}
                end
                table.insert(folderChildContainers[container.folderId], cid)
            else
                table.insert(looseContainerIds, cid)
            end
        end

        -- Sort folder children by per-spec container order
        local specId = CooldownCompanion._currentSpecId
        for fid, children in pairs(folderChildContainers) do
            table.sort(children, function(a, b)
                local orderA = CooldownCompanion:GetOrderForSpec(db.groupContainers[a], specId, a)
                local orderB = CooldownCompanion:GetOrderForSpec(db.groupContainers[b], specId, b)
                return orderA < orderB
            end)
        end

        -- Build top-level items list: folders + loose containers
        local items = {}
        for _, fid in ipairs(sectionFolderIds) do
            if not searchResults or (folderChildContainers[fid] and #folderChildContainers[fid] > 0) then
                table.insert(items, { kind = "folder", id = fid, order = CooldownCompanion:GetOrderForSpec(db.folders[fid], specId, fid) })
            end
        end
        for _, cid in ipairs(looseContainerIds) do
            table.insert(items, { kind = "container", id = cid, order = CooldownCompanion:GetOrderForSpec(db.groupContainers[cid], specId, cid) })
        end
        table.sort(items, function(a, b) return a.order < b.order end)

        return items, folderChildContainers
    end

    local function IsContainerInactive(containerId, container)
        if not container then return true end
        if container.enabled == false then return true end
        local stats = containerStats[containerId]
        if not stats or not stats.hasButtons then return true end
        return stats.hasActivePanel ~= true
    end

    local function IsFolderFullyInactive(folderId, childContainerIds)
        if not childContainerIds or #childContainerIds == 0 then return true end
        for _, cid in ipairs(childContainerIds) do
            if not IsContainerInactive(cid, db.groupContainers[cid]) then
                return false
            end
        end
        return true
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

        -- Selected groups can stop rendering when their folder is collapsed.
        -- Fall back to live container activity so hidden selections still affect
        -- the drag bucket classification.
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

    -- Helper: render a single container row (reused by both sections)
    local function RenderContainerRow(containerId, inFolder, sectionTag, loadBucket, options)
        local container = db.groupContainers[containerId]
        if not container then return end
        local disableDrag = options and options.disableDrag == true

        local entry = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(entry)
        local isInactive = IsContainerInactive(containerId, container)

        -- Show panel count in name when >1 panel
        local stats = containerStats[containerId]
        local panelCount = stats and stats.panelCount or 0
        local groupName = container.name or "New Group"
        local showGenericRenameBadge = IsGenericGroupName(groupName)
        local displayName = groupName
        if showGenericRenameBadge then
            displayName = displayName .. "      "
        end
        if panelCount > 1 then
            displayName = displayName .. "  |cff888888(" .. panelCount .. " panels)|r"
        end

        entry:SetText(displayName)
        entry:SetFullWidth(true)
        entry:SetFontObject(GameFontHighlight)
        local groupNameWidth = 0
        if showGenericRenameBadge and entry.label then
            entry.label:SetText(groupName)
            groupNameWidth = entry.label:GetStringWidth()
            entry:SetText(displayName)
        end
        if inFolder then
            ApplyConfigTextRow(entry, "LEFT", 17)
        else
            ApplyConfigRowIcon(entry, GetContainerIcon(containerId, db))
        end
        entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")

        -- Color: blue for multi-selected, green for selected, gray for inactive
        if CS.selectedGroups[containerId] then
            entry:SetColor(0.4, 0.7, 1.0)
        elseif CS.selectedContainer == containerId then
            entry:SetColor(0, 1, 0)
        elseif isInactive then
            entry:SetColor(0.5, 0.5, 0.5)
        end

        CS.col1Scroll:AddChild(entry)

        -- No mode badge for containers (panels have individual modes)
        if entry._cdcModeBadge then entry._cdcModeBadge:Hide() end

        SetupGroupRowIndicators(entry, container)
        if showGenericRenameBadge then
            ConfigureGenericGroupRenameBadge(entry, container, containerId, groupNameWidth)
        end

        if not disableDrag then
            entry:SetCallback("OnClick", function(widget, event, mouseButton)
                if mouseButton == "LeftButton"
                    and not searchResults
                    and not IsShiftKeyDown()
                    and not IsControlKeyDown()
                    and not GetCursorInfo()
                then
                    local isMulti = next(CS.selectedGroups) and CS.selectedGroups[containerId]
                    local cursorX, cursorY = GetScaledCursorPosition(CS.col1Scroll)
                    CS.dragState = {
                        kind = isMulti and "multi-group" or (inFolder and "folder-group" or "group"),
                        phase = "pending",
                        sourceGroupId = containerId,
                        sourceGroupIds = isMulti and CopyTable(CS.selectedGroups) or nil,
                        sourceSection = sectionTag,
                        sourceFolderId = inFolder and container.folderId or nil,
                        sourceLoadBucket = isMulti and ResolveSelectedDragLoadBucket(loadBucket) or (loadBucket or "loaded"),
                        scrollWidget = CS.col1Scroll,
                        widget = entry,
                        startX = cursorX,
                        startY = cursorY,
                        col1RenderedRows = col1RenderedRows,
                    }
                    StartDragTracking()
                end
            end)
        end

        -- Handle clicks via OnMouseUp
        entry.frame:SetScript("OnMouseUp", function(self, button)
            if CS.dragState and CS.dragState.phase == "active" then return end
            if button == "LeftButton" then
                if searchResults then
                    SelectConfigContainer(containerId, { clearFinder = true })
                    CooldownCompanion:RefreshConfigPanel()
                    return
                end
                if IsShiftKeyDown() then
                    OpenContainerLoadConditions(containerId)
                    return
                elseif IsControlKeyDown() then
                    -- Ctrl+click: toggle multi-select (container IDs)
                    ToggleConfigContainerMultiSelect(containerId)
                    CooldownCompanion:RefreshConfigPanel()
                    return
                end
                -- Normal click: toggle-through selection, clear multi-select
                SelectConfigContainer(containerId, { toggle = true })
                CooldownCompanion:RefreshConfigPanel()
            elseif button == "RightButton" then
                ShowContainerContextMenu(db, charKey, containerId, container)
                return
            elseif button == "MiddleButton" then
                container.locked = not container.locked
                CooldownCompanion:UpdateContainerDragHandle(containerId, container.locked)
                CooldownCompanion:RefreshContainerPanels(containerId)
                CooldownCompanion:RefreshConfigPanel()
                return
            end
        end)

        -- Tag entry frame with metadata for drag system
        entry.frame._cdcItemKind = "container"
        entry.frame._cdcGroupId = containerId
        entry.frame._cdcInFolder = inFolder and container.folderId or nil
        entry.frame._cdcSection = sectionTag

        TrackRenderedRow({
            kind = "container",
            id = containerId,
            widget = entry,
            inFolder = inFolder and container.folderId or nil,
            section = sectionTag,
            loadBucket = loadBucket or "loaded",
            acceptsDrop = (not disableDrag) and (loadBucket or "loaded") ~= "unloaded",
            previewDraggable = not disableDrag,
            previewProxy = true,
        })

        return entry
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

    -- Helper: render a folder header row
    local function RenderFolderRow(folderId, sectionTag, childContainerIds, loadBucket, options)
        local folder = db.folders[folderId]
        if not folder then return end
        local disableDrag = options and options.disableDrag == true

        local isCollapsed = CS.collapsedFolders[folderId]
        local function ToggleFolderCollapsed()
            CS.collapsedFolders[folderId] = not CS.collapsedFolders[folderId]
            CooldownCompanion:RefreshConfigPanel()
        end

        local entry = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(entry)
        entry:SetText(folder.name)
        entry:SetFullWidth(true)
        entry:SetFontObject(GameFontHighlight)
        ApplyConfigRowIcon(entry, GetFolderIcon(folderId, db))
        local allChildrenInactive = IsFolderFullyInactive(folderId, childContainerIds)
        if CS.selectedFolder == folderId and not CS.selectedContainer and not CS.selectedGroup then
            entry:SetColor(0.25, 0.62, 1.0)
        elseif allChildrenInactive then
            entry:SetColor(0.5, 0.5, 0.5)
        else
            entry:SetColor(1.0, 0.82, 0.0)
        end
        entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        CS.col1Scroll:AddChild(entry)
        SetupFolderRowIndicators(entry, folder)

        -- Tag entry frame with metadata for drag system
        entry.frame._cdcItemKind = "folder"
        entry.frame._cdcFolderId = folderId
        entry.frame._cdcSection = sectionTag

        local collapseBtn = entry.frame._cdcCollapseBtn
        if not collapseBtn then
            collapseBtn = CreateFrame("Button", nil, entry.frame)
            collapseBtn:SetSize(16, 16)
            collapseBtn:SetPropagateMouseClicks(false)
            collapseBtn:SetPropagateMouseMotion(false)
            collapseBtn._arrow = collapseBtn:CreateTexture(nil, "ARTWORK")
            collapseBtn._arrow:SetSize(10, 10)
            collapseBtn._arrow:SetPoint("CENTER")
            entry.frame._cdcCollapseBtn = collapseBtn
        end
        collapseBtn:SetParent(entry.frame)
        local function PositionCollapseButton()
            collapseBtn:ClearAllPoints()
            local collapseButtonGap = 4
            local collapseButtonWidth = collapseBtn:GetWidth() or 16
            local badgeReserve = GetConfigRowBadgeReserve(entry.frame)
            local labelRightPad = badgeReserve + collapseButtonWidth + (collapseButtonGap * 2)
            local leftPad = 0
            if entry.label and entry.label.GetPoint then
                local _, _, _, xOfs = entry.label:GetPoint(1)
                leftPad = xOfs or 0
                entry.label:ClearAllPoints()
                entry.label:SetPoint("LEFT", entry.frame, "LEFT", leftPad, 0)
            end
            local folderNameWidth = entry.label and entry.label:GetStringWidth() or 0
            local rowWidth = entry.frame.width or entry.frame:GetWidth() or 0
            local visibleLabelWidth = rowWidth > 0 and math.max(1, rowWidth - leftPad - labelRightPad) or (entry.label and entry.label:GetWidth() or 0)
            if visibleLabelWidth > 0 then
                if entry.label and entry.label.SetWidth then
                    entry.label:SetWidth(visibleLabelWidth)
                end
                folderNameWidth = math.min(folderNameWidth, visibleLabelWidth)
            end
            collapseBtn:SetPoint("LEFT", entry.label, "LEFT", folderNameWidth + collapseButtonGap, 0)
        end
        entry._cdcAfterConfigRowLayout = PositionCollapseButton
        PositionCollapseButton()
        collapseBtn:SetFrameLevel(entry.frame:GetFrameLevel() + 25)
        collapseBtn._arrow:SetAtlas(isCollapsed and "common-icon-plus" or "common-icon-minus", false)
        collapseBtn._arrow:SetRotation(0)
        collapseBtn:Show()
        collapseBtn._arrow:Show()
        collapseBtn:SetScript("OnClick", function()
            ToggleFolderCollapsed()
        end)
        collapseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(isCollapsed and "Expand" or "Collapse")
            GameTooltip:Show()
        end)
        collapseBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        TrackRenderedRow({
            kind = "folder",
            id = folderId,
            widget = entry,
            section = sectionTag,
            loadBucket = loadBucket or "loaded",
            acceptsDrop = (not disableDrag) and (loadBucket or "loaded") ~= "unloaded",
            previewDraggable = not disableDrag,
            previewProxy = true,
        })

        if not disableDrag then
            entry:SetCallback("OnClick", function(widget, event, mouseButton)
                if mouseButton == "LeftButton" and not searchResults and not IsShiftKeyDown() and not GetCursorInfo() then
                    local cursorX, cursorY = GetScaledCursorPosition(CS.col1Scroll)
                    CS.dragState = {
                        kind = "folder",
                        phase = "pending",
                        sourceFolderId = folderId,
                        sourceSection = sectionTag,
                        sourceLoadBucket = loadBucket or "loaded",
                        scrollWidget = CS.col1Scroll,
                        widget = entry,
                        startX = cursorX,
                        startY = cursorY,
                        col1RenderedRows = col1RenderedRows,
                    }
                    StartDragTracking()
                end
            end)
        end

        -- Handle clicks via OnMouseUp
        entry.frame:SetScript("OnMouseUp", function(self, button)
            if CS.dragState and CS.dragState.phase == "active" then return end
            if button == "LeftButton" then
                if searchResults then
                    return
                end
                if IsShiftKeyDown() then
                    OpenFolderLoadConditions(folderId)
                    return
                end
                SelectConfigFolder(folderId)
                CooldownCompanion:RefreshConfigPanel()
            elseif button == "MiddleButton" then
                -- Lock/unlock all containers in this folder
                local containers = db.groupContainers or {}
                local anyLocked = false
                for _, c in pairs(containers) do
                    if c.folderId == folderId and c.locked then
                        anyLocked = true
                        break
                    end
                end
                local newState = not anyLocked
                for cid, c in pairs(containers) do
                    if c.folderId == folderId then
                        c.locked = newState
                        CooldownCompanion:UpdateContainerDragHandle(cid, newState)
                        CooldownCompanion:RefreshContainerPanels(cid)
                    end
                end
                CooldownCompanion:RefreshConfigPanel()
                CooldownCompanion:Print("Folder " .. (folder.name or "Unknown") .. (newState and " locked." or " unlocked."))
                return
            elseif button == "RightButton" then
                ShowFolderContextMenu(db, folderId, folder)
            end
        end)

    end

    local function RenderSectionMarker(section, headingText, headingColor)
        local heading = AceGUI:Create("Label")
        heading:SetFullWidth(true)
        heading:SetHeight(18)
        CS.col1Scroll:AddChild(heading)
        SetupColumn1MarkerRow(heading, {
            text = headingText,
            color = headingColor,
        })
        TrackRenderedRow({
            kind = "section-title",
            widget = heading,
            section = section,
            loadBucket = "marker",
            acceptsDrop = false,
            keepVisibleDuringPreview = true,
            previewProxy = true,
            isMarker = true,
        })
    end

    -- Render a section (global, current class, or another class)
    local function RenderSection(section, sectionGroupIds, headingText, headingColor, options)
        local items, folderChildContainers = BuildSectionItems(section, sectionGroupIds)
        local isClassSection = options and options.classSection == true
        local stableCount = options and options.stableCount or nil

        if isClassSection then
            local isCollapsed = CS.collapsedSections[section] ~= false
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
                    if button == "LeftButton" then
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

        -- Partition into loaded (active) and unloaded (inactive)
        local loadedItems = {}
        local unloadedItems = {}
        for _, item in ipairs(items) do
            if options and options.noLoadBuckets then
                table.insert(loadedItems, item)
            else
                local isInactive
                if item.kind == "folder" then
                    isInactive = IsFolderFullyInactive(item.id, folderChildContainers[item.id])
                else
                    isInactive = IsContainerInactive(item.id, db.groupContainers[item.id])
                end
                if isInactive then
                    table.insert(unloadedItems, item)
                else
                    table.insert(loadedItems, item)
                end
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
            for _, item in ipairs(itemList) do
                if item.kind == "folder" then
                    RenderFolderRow(item.id, section, folderChildContainers[item.id], loadBucket, options)
                    -- If expanded, render children with accent bar
                    if searchResults or not CS.collapsedFolders[item.id] then
                        local children = folderChildContainers[item.id]
                        if children and #children > 0 then
                            local firstEntry, lastEntry
                            for _, cid in ipairs(children) do
                                local entry = RenderContainerRow(cid, true, section, loadBucket, options)
                                if entry then
                                    if not firstEntry then firstEntry = entry end
                                    lastEntry = entry
                                end
                            end
                            -- Create accent bar spanning all child rows
                            if firstEntry and lastEntry and classColor then
                                accentBarIndex = accentBarIndex + 1
                                local bar = CS.folderAccentBars[accentBarIndex]
                                if not bar then
                                    bar = CS.col1Scroll.content:CreateTexture(nil, "ARTWORK")
                                    CS.folderAccentBars[accentBarIndex] = bar
                                end
                                bar:SetColorTexture(classColor.r, classColor.g, classColor.b, 0.8)
                                bar:SetWidth(3)
                                bar:ClearAllPoints()
                                bar._cdcFolderId = item.id
                                bar._cdcFolderAccentActive = true
                                bar:SetPoint("TOPLEFT", firstEntry.frame, "TOPLEFT", 0, 0)
                                bar:SetPoint("BOTTOMLEFT", lastEntry.frame, "BOTTOMLEFT", 0, 0)
                                if CS.compactConfigRows then
                                    bar:Hide()
                                else
                                    bar:Show()
                                end
                            end
                        end
                    end
                elseif item.kind == "container" then
                    RenderContainerRow(item.id, false, section, loadBucket, options)
                end
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
        if options and options.classKey then
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
            CS.otherClassLibraryActive = false
            CS.otherClassLibraryClassKey = nil
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
                CS.otherClassLibraryActive = false
                CS.otherClassLibraryClassKey = nil
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
    local showNewUserEmptyState = not next(containers) and not next(db.folders)
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

    for folderId, folder in pairs(db.folders or {}) do
        local scope = ResolveFolderScope(folderId, folder)
        if scope.scope == "other-class" then
            local section = EnsureOtherClassSection(otherSections, otherSectionOrder, scope)
            if section then
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
        label:SetText("|cff888888No matching groups.|r")
        label:SetFullWidth(true)
        CS.col1Scroll:AddChild(label)
        CS.lastCol1RenderedRows = col1RenderedRows
        if CS.otherClassLibraryActive then
            if CS.col1ButtonBar then CS.col1ButtonBar:Hide() end
        else
            PopulateColumn1ButtonBar()
        end
        return
    end

    if showNewUserEmptyState then
        CS.otherClassLibraryActive = false
        CS.otherClassLibraryClassKey = nil

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
        if CS.otherClassLibraryActive then
            renderedOtherClassLibrary = RenderOtherClassLibrary(otherSectionOrder)
        end

        if not renderedOtherClassLibrary then
            local hasGlobalContent = #globalIds > 0
            if not hasGlobalContent then
                for folderId, folder in pairs(db.folders) do
                    local scope = ResolveFolderScope(folderId, folder)
                    if scope.scope == "global" then
                        hasGlobalContent = true
                        break
                    end
                end
            end

            if #globalIds > 0 or next(db.folders) or CS.showPhantomSections then
                if hasGlobalContent or CS.showPhantomSections then
                    RenderSection("global", globalIds, "Global Groups", { 0.4, 0.67, 1.0 })
                end
            end

            local _, playerClassKey = UnitClass("player")
            local currentClassName = GetClassDisplayName(playerClassKey)
            local hasCharContent = #charIds > 0
            if not hasCharContent then
                for folderId, folder in pairs(db.folders) do
                    local scope = ResolveFolderScope(folderId, folder)
                    if scope.scope == "current-class" then
                        hasCharContent = true
                        break
                    end
                end
            end
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
        end
    end

    CS.lastCol1RenderedRows = col1RenderedRows

    if CS.otherClassLibraryActive then
        if CS.col1ButtonBar then CS.col1ButtonBar:Hide() end
    else
        PopulateColumn1ButtonBar()
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn1 = RefreshColumn1
