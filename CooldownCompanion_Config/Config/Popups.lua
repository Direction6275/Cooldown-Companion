--[[
    CooldownCompanion - Config/Popups
    All non-diagnostic StaticPopupDialogs.
    OnAccept handlers use CS.*/ST._* for runtime state access.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local ResetConfigSelection = ST._ResetConfigSelection
local ClearConfigButtonSelection = ST._ClearConfigButtonSelection
local ClearConfigPanelSelection = ST._ClearConfigPanelSelection
local ClearConfigContainerSelection = ST._ClearConfigContainerSelection
local ClearConfigPanelMultiSelection = ST._ClearConfigPanelMultiSelection
local ClearConfigCustomBarSelection = ST._ClearConfigCustomBarSelection
local EncodeSharedPayload = ST._EncodeSharedPayload
local StripCharacterEligibilityFromPayload = ST._StripCharacterEligibilityFromPayload

local LOAD_CONDITION_ALLOWLIST_KEYS = {
    classAllowlist = "class",
    specAllowlist = "spec",
    characterAllowlist = "character",
}

local function NormalizeAllowlistKey(kind, key)
    if kind == "class" then
        if type(key) ~= "string" or key == "" then return nil end
        return string.upper(key)
    elseif kind == "spec" then
        return tonumber(key)
    elseif kind == "character" then
        if type(key) ~= "string" or key == "" then return nil end
        return key
    end
    return nil
end

local function CopyAllowlistMap(map, kind)
    if type(map) ~= "table" then return nil end
    local copy = {}
    for key, enabled in pairs(map) do
        if enabled == true then
            local normalizedKey = NormalizeAllowlistKey(kind, key)
            if normalizedKey ~= nil then
                copy[normalizedKey] = true
            end
        end
    end
    return next(copy) and copy or nil
end

-- Check whether a profile name already exists (case-exact match).
local function ProfileNameExists(name)
    local profiles = CooldownCompanion.db:GetProfiles()
    for _, existing in ipairs(profiles) do
        if existing == name then return true end
    end
    return false
end

local function TrimPopupText(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function RejectUnsupportedImportPayload(data, dataLabel)
    if CooldownCompanion.IsUnsupportedImportPayload and CooldownCompanion:IsUnsupportedImportPayload(data) then
        CooldownCompanion:NotifyLegacySupportCutoff(dataLabel)
        return true
    end
    return false
end

local function ShowPopupOverConfig(which, textArg1, data)
    local showFn = (CS and CS.ShowPopupAboveConfig) or ST._ShowPopupAboveConfig
    if showFn then
        return showFn(which, textArg1, data)
    end
    return StaticPopup_Show(which, textArg1, nil, data)
end

local function PruneDeletedFolderSelection(folderId)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if not db then return end

    if CS.selectedFolder == folderId then
        CS.selectedFolder = nil
    end

    if CS.selectedContainer and not (db.groupContainers and db.groupContainers[CS.selectedContainer]) then
        ClearConfigContainerSelection()
    elseif CS.selectedGroup and not (db.groups and db.groups[CS.selectedGroup]) then
        ClearConfigPanelSelection()
    end

    if CS.addingToPanelId and not (db.groups and db.groups[CS.addingToPanelId]) then
        CS.addingToPanelId = nil
    end

    for containerId in pairs(CS.selectedGroups) do
        if not (db.groupContainers and db.groupContainers[containerId]) then
            CS.selectedGroups[containerId] = nil
        end
    end
    for panelId in pairs(CS.selectedPanels) do
        if not (db.groups and db.groups[panelId]) then
            CS.selectedPanels[panelId] = nil
        end
    end
end

StaticPopupDialogs["CDC_DELETE_GROUP"] = {
    text = "Are you sure you want to delete group '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not data then return end
        local id = data.containerId or data.groupId
        if id then
            CooldownCompanion:ClearAllConfigPreviews()
            CooldownCompanion:DeleteGroup(id)
            if data.containerId then
                if CS.selectedContainer == id then
                    ClearConfigContainerSelection()
                end
            else
                if CS.selectedGroup == id then
                    ClearConfigPanelSelection()
                end
            end
            CS.selectedGroups[id] = nil
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DELETE_PANEL"] = {
    text = "Are you sure you want to delete panel '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not data then return end
        CooldownCompanion:ClearAllConfigPreviews()
        CooldownCompanion:DeletePanel(data.containerId, data.panelId)
        if CS.selectedGroup == data.panelId then
            ClearConfigPanelSelection()
        end
        if CS.addingToPanelId == data.panelId then
            CS.addingToPanelId = nil
        end
        CooldownCompanion:RefreshConfigPanel()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_RENAME_GROUP"] = {
    text = "Rename group '%s' to:",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self, data)
        local newName = self.EditBox:GetText()
        if newName and newName ~= "" and data then
            if data.containerId then
                local container = CooldownCompanion.db.profile.groupContainers[data.containerId]
                if container then
                    container.name = newName
                    -- Refresh all panels in this container
                    for gid, g in pairs(CooldownCompanion.db.profile.groups) do
                        if g.parentContainerId == data.containerId then
                            CooldownCompanion:RefreshGroupFrame(gid)
                        end
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end
            elseif data.groupId then
                local group = CooldownCompanion.db.profile.groups[data.groupId]
                if group then
                    group.name = newName
                    CooldownCompanion:RefreshGroupFrame(data.groupId)
                    CooldownCompanion:RefreshConfigPanel()
                end
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["CDC_RENAME_GROUP"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    OnShow = function(self)
        self.EditBox:SetFocus()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DELETE_BUTTON"] = {
    text = "Remove '%s' from this group?",
    button1 = "Remove",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.groupId and data.buttonIndex then
            CooldownCompanion:RemoveButtonFromGroup(data.groupId, data.buttonIndex)
            ResetConfigSelection(false)
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DELETE_SELECTED_BUTTONS"] = {
    text = "Remove %d selected entries from this group?",
    button1 = "Remove",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.groupId and data.indices then
            local group = CooldownCompanion.db.profile.groups[data.groupId]
            if group then
                -- Remove in reverse order so indices stay valid
                table.sort(data.indices, function(a, b) return a > b end)
                for _, idx in ipairs(data.indices) do
                    table.remove(group.buttons, idx)
                end
                CooldownCompanion:RefreshGroupFrame(data.groupId)
            end
            ResetConfigSelection(false)
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DELETE_SELECTED_PANELS"] = {
    text = "Delete %d selected panels?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.panelIds and data.containerId then
            CooldownCompanion:ClearAllConfigPreviews()
            for _, pid in ipairs(data.panelIds) do
                CooldownCompanion:DeletePanel(data.containerId, pid)
            end
            ClearConfigPanelMultiSelection()
            ClearConfigPanelSelection()
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DELETE_PROFILE"] = {
    text = "Delete profile '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.profileName then
            local db = CooldownCompanion.db
            if data.isOnly then
                db:ResetProfile()
            else
                local allProfiles = db:GetProfiles()
                local nextProfile = nil
                for _, name in ipairs(allProfiles) do
                    if name ~= data.profileName then
                        nextProfile = name
                        break
                    end
                end
                db:SetProfile(nextProfile)
                db:DeleteProfile(data.profileName, true)
            end
            ResetConfigSelection(true)
            CooldownCompanion:RefreshConfigPanel()
            CooldownCompanion:RefreshAllGroups()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_RESET_PROFILE"] = {
    text = "Reset profile '%s' to default settings?",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.profileName then
            local db = CooldownCompanion.db
            db:ResetProfile()
            ResetConfigSelection(true)
            CooldownCompanion:RefreshConfigPanel()
            CooldownCompanion:RefreshAllGroups()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_NEW_PROFILE"] = {
    text = "Enter new profile name:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self)
        local text = self.EditBox:GetText()
        if text and text ~= "" then
            if ProfileNameExists(text) then
                CooldownCompanion:Print("A profile named '" .. text .. "' already exists.")
                return
            end
            local db = CooldownCompanion.db
            db:SetProfile(text)
            ResetConfigSelection(true)
            CooldownCompanion:RefreshConfigPanel()
            CooldownCompanion:RefreshAllGroups()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["CDC_NEW_PROFILE"].OnAccept(parent)
        parent:Hide()
    end,
    OnShow = function(self)
        self.EditBox:SetFocus()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_RENAME_PROFILE"] = {
    text = "Rename profile '%s' to:",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self, data)
        local newName = self.EditBox:GetText()
        if newName and newName ~= "" and data and data.oldName then
            if newName ~= data.oldName and ProfileNameExists(newName) then
                CooldownCompanion:Print("A profile named '" .. newName .. "' already exists.")
                return
            end
            if newName == data.oldName then return end
            local db = CooldownCompanion.db
            CooldownCompanion._suppressOwnershipRestamp = true
            db:SetProfile(newName)
            db:CopyProfile(data.oldName)
            CooldownCompanion._suppressOwnershipRestamp = nil
            db:DeleteProfile(data.oldName, true)
            ResetConfigSelection(true)
            CooldownCompanion:RefreshConfigPanel()
            CooldownCompanion:RefreshAllGroups()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["CDC_RENAME_PROFILE"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    OnShow = function(self)
        self.EditBox:SetFocus()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DUPLICATE_PROFILE"] = {
    text = "Enter name for the duplicate profile:",
    button1 = "Duplicate",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self, data)
        local newName = self.EditBox:GetText()
        if newName and newName ~= "" and data and data.source then
            if ProfileNameExists(newName) then
                CooldownCompanion:Print("A profile named '" .. newName .. "' already exists.")
                return
            end
            local db = CooldownCompanion.db
            CooldownCompanion._suppressOwnershipRestamp = true
            db:SetProfile(newName)
            db:CopyProfile(data.source)
            CooldownCompanion._suppressOwnershipRestamp = nil
            ResetConfigSelection(true)
            CooldownCompanion:RefreshConfigPanel()
            CooldownCompanion:RefreshAllGroups()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["CDC_DUPLICATE_PROFILE"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    OnShow = function(self)
        self.EditBox:SetFocus()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_EXPORT_PROFILE"] = {
    text = "Profile backup string (Ctrl+C to copy):",
    button1 = "Close",
    hasEditBox = true,
    OnShow = function(self)
        local db = CooldownCompanion.db
        local exportData = CopyTable(db.profile)
        exportData._exporterCharKey = db.keys.char
        exportData._characterInfo = db.global.characterInfo
        self.EditBox:SetText(EncodeSharedPayload(exportData, "profile"))
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_UNGLOBAL_GROUP"] = {
    text = "This will remove foreign eligibility filters and move '%s' into your current class. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not data then return end
        if data.containerId then
            local container = CooldownCompanion.db.profile.groupContainers[data.containerId]
            if container then
                CooldownCompanion:ToggleGroupGlobal(data.containerId)
                CooldownCompanion:RefreshConfigPanel()
            end
        elseif data.groupId then
            local group = CooldownCompanion.db.profile.groups[data.groupId]
            if group then
                CooldownCompanion:ToggleGroupGlobal(data.groupId)
                CooldownCompanion:RefreshConfigPanel()
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DRAG_UNGLOBAL_GROUP"] = {
    text = "This will remove foreign eligibility filters and move '%s' into your current class. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.dragState then
            local db = CooldownCompanion.db.profile
            local container = db.groupContainers[data.dragState.sourceGroupId]
            if container then
                ST._ApplyCol1Drop(data.dragState)
                CooldownCompanion:RefreshConfigPanel()
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_CROSS_PANEL_STRIP_OVERRIDES"] = {
    text = "Moving '%s' to a different panel will remove its appearance overrides. Continue?",
    button1 = "Move",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not data then return end
        local buttonData = ST._PerformCrossPanelMove(
            data.sourcePanelId, data.sourceIndex,
            data.targetPanelId, data.targetIndex
        )
        if buttonData then
            CooldownCompanion:ClearAllConfigPreviews()
            ST._StripButtonOverrides(buttonData)
            CooldownCompanion:RefreshGroupFrame(data.sourcePanelId)
            CooldownCompanion:RefreshGroupFrame(data.targetPanelId)
            ClearConfigButtonSelection()
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DRAG_UNGLOBAL_FOLDER"] = {
    text = "This folder contains groups with foreign eligibility filters. Moving to your current class will remove those filters. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.dragState then
            ST._ApplyCol1Drop(data.dragState)
            CooldownCompanion:RefreshAllGroups()
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_UNGLOBAL_FOLDER"] = {
    text = "This folder contains groups with foreign eligibility filters. Moving '%s' to your current class will remove those filters. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.folderId then
            CooldownCompanion:ToggleFolderGlobal(data.folderId)
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DELETE_SELECTED_GROUPS"] = {
    text = "Delete %d selected groups?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.groupIds then
            for _, gid in ipairs(data.groupIds) do
                CooldownCompanion:DeleteGroup(gid)
            end
            ResetConfigSelection(true)
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DELETE_SELECTED_CUSTOM_BARS"] = {
    text = "Delete %d selected Custom Bars?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        local rb = ST._RB
        local settings = CooldownCompanion:GetResourceBarSettings()
        if data and type(data.ids) == "table" and rb and rb.DeleteCustomBar then
            for _, customBarId in ipairs(data.ids) do
                rb.DeleteCustomBar(settings, customBarId)
            end
            ClearConfigCustomBarSelection(true, { clearExpanded = true })
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_UNGLOBAL_SELECTED_GROUPS"] = {
    text = "Some selected groups have foreign eligibility filters. Moving to your current class will remove those filters. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.callback then
            data.callback()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_RENAME_FOLDER"] = {
    text = "Rename folder '%s' to:",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self, data)
        local newName = self.EditBox:GetText()
        if newName and newName ~= "" and data and data.folderId then
            CooldownCompanion:RenameFolder(data.folderId, newName)
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["CDC_RENAME_FOLDER"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    OnShow = function(self)
        self.EditBox:SetFocus()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DELETE_FOLDER"] = {
    text = "Delete folder '%s' and all groups inside it?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.folderId then
            CooldownCompanion:ClearAllConfigPreviews()
            CooldownCompanion:DeleteFolder(data.folderId)
            PruneDeletedFolderSelection(data.folderId)
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

------------------------------------------------------------------------
-- Group/Folder Export and Apply
------------------------------------------------------------------------

local function BuildGroupExportData(group)
    local data = CopyTable(group)
    data.createdBy = nil
    data.order = nil
    data.folderId = nil
    data.isGlobal = nil
    data.parentContainerId = nil
    return data
end

local function EncodeExportData(payload)
    return EncodeSharedPayload(payload, "entity")
end

local function BuildContainerExportData(container)
    local data = CopyTable(container)
    data.createdBy = nil
    data.order = nil
    data.specOrders = nil
    data.folderId = nil
    data.isGlobal = nil
    return data
end

local function HasTrueMapValue(map)
    if type(map) ~= "table" then return false end
    for _, enabled in pairs(map) do
        if enabled == true then
            return true
        end
    end
    return false
end

local function EntityHasPortableEligibility(entity)
    if type(entity) ~= "table" then return false end
    local loadConditions = entity.loadConditions
    if type(loadConditions) == "table" then
        if CopyAllowlistMap(loadConditions.classAllowlist, "class")
            or CopyAllowlistMap(loadConditions.specAllowlist, "spec")
        then
            return true
        end
    end
    return CopyAllowlistMap(entity.specs, "spec") ~= nil
        or HasTrueMapValue(entity.heroTalents)
end

local function ContainerEntryHasPortableEligibility(entry)
    if type(entry) ~= "table" then return false end
    if EntityHasPortableEligibility(entry.container) then
        return true
    end
    for _, panel in ipairs(entry.panels or {}) do
        if EntityHasPortableEligibility(panel) then
            return true
        end
    end
    return false
end

local function ContainersHavePortableEligibility(entries)
    if type(entries) ~= "table" then return false end
    for _, entry in ipairs(entries) do
        if ContainerEntryHasPortableEligibility(entry) then
            return true
        end
    end
    return false
end

local function StripImportCharacterEligibility(data, importState)
    local stripped = type(data) == "table" and tonumber(data._cdcCharacterEligibilityStripped) or 0
    stripped = stripped + (StripCharacterEligibilityFromPayload
        and StripCharacterEligibilityFromPayload(data)
        or 0)
    if stripped > 0 and importState then
        importState.characterEligibilityStripped = (importState.characterEligibilityStripped or 0) + stripped
    end
    return stripped
end

ST._BuildGroupExportData = BuildGroupExportData
ST._BuildContainerExportData = BuildContainerExportData
ST._EncodeExportData = EncodeExportData

local function BuildImportedRootAnchor(relativeTo)
    return {
        point = "CENTER",
        relativeTo = relativeTo or "UIParent",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }
end

local function ResetImportedStandalonePanelAnchor(panel)
    local settings = CooldownCompanion:GetStandaloneTextureAnchorSettings(panel)
    if type(settings) ~= "table" then
        return
    end
    settings.point = "CENTER"
    settings.relativeTo = "UIParent"
    settings.relativePoint = "CENTER"
    settings.x = 0
    settings.y = 0
end

local function BuildDefaultImportedPanel(containerId)
    return {
        name = "Panel 1",
        order = 1,
        parentContainerId = containerId,
        displayMode = "icons",
        buttons = {},
        anchor = BuildImportedRootAnchor("CooldownCompanionContainer" .. containerId),
    }
end

local function AnchorImportedContainerFrame(containerId, anchor)
    local frame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
    if frame then
        CooldownCompanion:AnchorContainerFrame(frame, anchor)
    end
end

local function GetRemappedImportedGroupAnchorTarget(importState, sourceGroupId, options)
    options = options or {}
    local targetGroupId = importState.groupIdMap[sourceGroupId]
    if targetGroupId then
        local targetFrameName = "CooldownCompanionGroup" .. targetGroupId
        if CooldownCompanion:ValidateAddonFrameAnchorTarget(targetFrameName, options) then
            return targetFrameName
        end
    end
    return nil
end

local function CreateImportedPanel(db, containerId, panelIndex, srcPanel, importState)
    local groupId = db.nextGroupId
    db.nextGroupId = groupId + 1

    if srcPanel then
        importState.importedGroupIds[#importState.importedGroupIds + 1] = groupId
        if srcPanel._originalGroupId then
            importState.groupIdMap[srcPanel._originalGroupId] = groupId
        end
    end

    local panel = srcPanel and CopyTable(srcPanel) or BuildDefaultImportedPanel(containerId)
    panel._originalGroupId = nil
    panel.parentContainerId = containerId
    panel.order = panelIndex
    if not panel.anchor then
        panel.anchor = BuildImportedRootAnchor("CooldownCompanionContainer" .. containerId)
    end

    db.groups[groupId] = panel
    CooldownCompanion:CreateGroupFrame(groupId)
    importState.panelCount = importState.panelCount + 1
end

local function NewGroupImportState()
    return {
        containerIdMap = {},
        importedContainerIds = {},
        groupIdMap = {},
        importedGroupIds = {},
        containerCount = 0,
        panelCount = 0,
        characterEligibilityStripped = 0,
        globalizedEligibilityImports = 0,
    }
end

local function ImportContainerEntries(db, entries, charKey, folderId, importState, options)
    importState = importState or NewGroupImportState()
    options = options or {}
    local firstContainerIndex = #importState.importedContainerIds + 1
    local startContainerCount = importState.containerCount
    local startPanelCount = importState.panelCount

    for _, entry in ipairs(entries) do
        local containerId = db.nextContainerId
        db.nextContainerId = containerId + 1
        importState.importedContainerIds[#importState.importedContainerIds + 1] = containerId
        if entry._originalContainerId then
            importState.containerIdMap[entry._originalContainerId] = containerId
        end

        local container = CopyTable(entry.container)
        local importAsGlobal = options.forceGlobalScope == true
            or ContainerEntryHasPortableEligibility(entry)
        container.createdBy = charKey
        container.isGlobal = importAsGlobal
        container.order = containerId
        container.specOrders = nil
        container.folderId = folderId
        container.locked = true
        if importAsGlobal then
            importState.globalizedEligibilityImports = (importState.globalizedEligibilityImports or 0) + 1
        end
        db.groupContainers[containerId] = container
        CooldownCompanion:CreateContainerFrame(containerId)

        local panels = entry.panels or {}
        for panelIndex, srcPanel in ipairs(panels) do
            CreateImportedPanel(db, containerId, panelIndex, srcPanel, importState)
        end
        if #panels == 0 then
            CreateImportedPanel(db, containerId, 1, nil, importState)
        end

        importState.containerCount = importState.containerCount + 1
    end

    return importState,
        importState.containerCount - startContainerCount,
        importState.panelCount - startPanelCount,
        importState.importedContainerIds[firstContainerIndex]
end

local function RemapImportedContainerAnchors(db, importState, preserveContainerRefs)
    for _, newId in ipairs(importState.importedContainerIds) do
        local container = db.groupContainers[newId]
        if container and container.anchor then
            local rt = container.anchor.relativeTo
            if rt then
                if CooldownCompanion:IsCursorAnchor(rt) then
                    container.anchor = BuildImportedRootAnchor()
                    AnchorImportedContainerFrame(newId, container.anchor)
                else
                    local refOldId = tonumber(rt:match("^CooldownCompanionContainer(%d+)$"))
                    if refOldId then
                        local remappedId = preserveContainerRefs and importState.containerIdMap[refOldId] or nil
                        if remappedId then
                            container.anchor.relativeTo = "CooldownCompanionContainer" .. remappedId
                        else
                            container.anchor = BuildImportedRootAnchor()
                        end
                        AnchorImportedContainerFrame(newId, container.anchor)
                    else
                        local groupRef = tonumber(rt:match("^CooldownCompanionGroup(%d+)$"))
                        if groupRef then
                            local targetFrameName = GetRemappedImportedGroupAnchorTarget(importState, groupRef, {
                                domain = "external",
                            })
                            if targetFrameName then
                                container.anchor.relativeTo = targetFrameName
                            else
                                container.anchor = BuildImportedRootAnchor()
                            end
                            AnchorImportedContainerFrame(newId, container.anchor)
                        end
                    end
                end
            end
        end
    end
end

local function PrintImportSanitizerNotes(importState)
    if not (importState and CooldownCompanion and CooldownCompanion.Print) then
        return
    end
    if (importState.characterEligibilityStripped or 0) > 0 then
        CooldownCompanion:Print("Character eligibility is local and was not imported.")
    end
    if (importState.globalizedEligibilityImports or 0) > 0 then
        CooldownCompanion:Print("Class, specialization, and hero talent eligibility were preserved in Global Groups.")
    end
end

local function RemapImportedStandalonePanelAnchor(panel, newGroupId, importState)
    local settings = CooldownCompanion:GetStandaloneTextureAnchorSettings(panel)
    local relativeTo = type(settings) == "table" and settings.relativeTo or nil
    if not relativeTo or relativeTo == "UIParent" then
        return
    end
    if type(relativeTo) ~= "string" then
        ResetImportedStandalonePanelAnchor(panel)
        return
    end
    local groupRef = tonumber(relativeTo:match("^CooldownCompanionGroup(%d+)$"))
    local containerRef = tonumber(relativeTo:match("^CooldownCompanionContainer(%d+)$"))
    if groupRef then
        local targetFrameName = GetRemappedImportedGroupAnchorTarget(importState, groupRef, {
            domain = "panel-import",
            sourceGroupId = newGroupId,
        })
        if targetFrameName then
            settings.relativeTo = targetFrameName
        else
            ResetImportedStandalonePanelAnchor(panel)
        end
        return
    end
    if containerRef then
        local targetContainerId = importState.containerIdMap[containerRef]
        if targetContainerId then
            settings.relativeTo = "CooldownCompanionContainer" .. tostring(targetContainerId)
        else
            ResetImportedStandalonePanelAnchor(panel)
        end
        return
    end
    if relativeTo:find("^CooldownCompanion") then
        ResetImportedStandalonePanelAnchor(panel)
        return
    end
end

local function RemapImportedPanelAnchors(db, importState, preserveOwnContainerRefs)
    for _, newGid in ipairs(importState.importedGroupIds) do
        local panel = db.groups[newGid]
        if panel and panel.anchor then
            local rt = panel.anchor.relativeTo
            if rt then
                local containerRef = tonumber(rt:match("^CooldownCompanionContainer(%d+)$"))
                if containerRef then
                    if importState.containerIdMap[containerRef] then
                        panel.anchor.relativeTo = "CooldownCompanionContainer" .. importState.containerIdMap[containerRef]
                    elseif preserveOwnContainerRefs then
                        panel.anchor.relativeTo = "CooldownCompanionContainer" .. panel.parentContainerId
                    else
                        panel.anchor = BuildImportedRootAnchor("CooldownCompanionContainer" .. panel.parentContainerId)
                    end
                else
                    local groupRef = tonumber(rt:match("^CooldownCompanionGroup(%d+)$"))
                    if groupRef then
                        local targetFrameName = GetRemappedImportedGroupAnchorTarget(importState, groupRef, {
                            domain = "panel-import",
                            sourceGroupId = newGid,
                        })
                        if targetFrameName then
                            panel.anchor.relativeTo = targetFrameName
                        else
                            panel.anchor = BuildImportedRootAnchor("CooldownCompanionContainer" .. panel.parentContainerId)
                        end
                    end
                end
            end
        end
        RemapImportedStandalonePanelAnchor(panel, newGid, importState)
    end
end

local activeGroupImportBatches = setmetatable({}, { __mode = "k" })
local activeGroupImportPayloads = setmetatable({}, { __mode = "k" })

ST._BeginGroupImportBatch = function()
    local token = {}
    activeGroupImportBatches[token] = NewGroupImportState()
    return token
end

ST._FinishGroupImportBatch = function(token, remapAnchors)
    local importState = activeGroupImportBatches[token]
    activeGroupImportBatches[token] = nil
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if remapAnchors and type(db) == "table" and type(importState) == "table" then
        RemapImportedContainerAnchors(db, importState, true)
        RemapImportedPanelAnchors(db, importState)
        if CooldownCompanion.SanitizeCursorAnchorPolicy then
            CooldownCompanion:SanitizeCursorAnchorPolicy(db)
        end
    end
    PrintImportSanitizerNotes(importState)
end

ST._AttachGroupImportBatch = function(payload, token)
    if type(payload) == "table" and activeGroupImportBatches[token] then
        activeGroupImportPayloads[payload] = token
    end
end

local function ApplyGroupImportData(data)
    if type(data) ~= "table" then
        return false
    end
    local batchToken = activeGroupImportPayloads[data]
    activeGroupImportPayloads[data] = nil
    if RejectUnsupportedImportPayload(data, "group import") then
        return false
    end

    if not data.type then
        CooldownCompanion:Print("Import failed: this is a profile backup, not a group, folder, or panel export.")
        return false
    end

    local db = CooldownCompanion.db.profile
    local charKey = CooldownCompanion.db.keys.char
    local sharedImportState = batchToken and activeGroupImportBatches[batchToken] or nil
    local rootImportState = sharedImportState or NewGroupImportState()
    local deferAnchorRemap = sharedImportState ~= nil
    StripImportCharacterEligibility(data, rootImportState)

    if data.type == "group" and data.group then
        CooldownCompanion:NotifyLegacySupportCutoff("group import")
        return false

    elseif data.type == "groups" and data.groups then
        CooldownCompanion:NotifyLegacySupportCutoff("group import")
        return false

    elseif data.type == "containers" and data.containers then
        local importState, containerCount = ImportContainerEntries(db, data.containers, charKey, nil, rootImportState)
        if not deferAnchorRemap then
            RemapImportedContainerAnchors(db, importState, true)
            RemapImportedPanelAnchors(db, importState)
        end
        CooldownCompanion:Print("Imported " .. containerCount .. " groups.")

    elseif data.type == "folder" and data.folder then
        if data.groups then
            CooldownCompanion:NotifyLegacySupportCutoff("folder import")
            return false
        end

        local folderId = db.nextFolderId
        db.nextFolderId = folderId + 1
        local importedManualIcon = data.folder.manualIcon
        if type(importedManualIcon) ~= "number" and type(importedManualIcon) ~= "string" then
            importedManualIcon = nil
        end
        local importedSpecs = nil
        if type(data.folder.specs) == "table" then
            importedSpecs = {}
            for specId, enabled in pairs(data.folder.specs) do
                local numSpecId = tonumber(specId)
                if numSpecId and enabled then
                    importedSpecs[numSpecId] = true
                end
            end
            if not next(importedSpecs) then
                importedSpecs = nil
            end
        end
        local importedHeroTalents = nil
        if type(data.folder.heroTalents) == "table" then
            importedHeroTalents = {}
            for subTreeID, enabled in pairs(data.folder.heroTalents) do
                local numSubTreeID = tonumber(subTreeID)
                if numSubTreeID and enabled then
                    importedHeroTalents[numSubTreeID] = true
                end
            end
            if not next(importedHeroTalents) then
                importedHeroTalents = nil
            end
        end
        if not importedSpecs then
            importedHeroTalents = nil
        end
        local importedLoadConditions = nil
        if type(data.folder.loadConditions) == "table" then
            importedLoadConditions = {}
            for key, enabled in pairs(data.folder.loadConditions) do
                if enabled == true then
                    importedLoadConditions[key] = true
                elseif LOAD_CONDITION_ALLOWLIST_KEYS[key] then
                    local allowlist = CopyAllowlistMap(enabled, LOAD_CONDITION_ALLOWLIST_KEYS[key])
                    if allowlist then
                        importedLoadConditions[key] = allowlist
                    end
                end
            end
            if not next(importedLoadConditions) then
                importedLoadConditions = nil
            end
        end
        local folderUsesGlobalEligibility = importedSpecs
            or importedHeroTalents
            or (importedLoadConditions and (
                importedLoadConditions.classAllowlist
                    or importedLoadConditions.specAllowlist
            ))
            or ContainersHavePortableEligibility(data.containers)
        db.folders[folderId] = {
            name = data.folder.name or "Imported Folder",
            order = folderId,
            section = folderUsesGlobalEligibility and "global" or "char",
            createdBy = charKey,
            manualIcon = importedManualIcon,
            specs = importedSpecs,
            heroTalents = importedHeroTalents,
            loadConditions = importedLoadConditions,
        }
        if folderUsesGlobalEligibility then
            rootImportState.globalizedEligibilityImports = (rootImportState.globalizedEligibilityImports or 0) + 1
        end
        local count = 0
        if data.containers then
            local importState, _, panelCount = ImportContainerEntries(
                db, data.containers, charKey, folderId, rootImportState, {
                    forceGlobalScope = folderUsesGlobalEligibility and true or false,
                }
            )
            if not deferAnchorRemap then
                RemapImportedContainerAnchors(db, importState, true)
                RemapImportedPanelAnchors(db, importState)
            end
            count = panelCount
        end
        CooldownCompanion:Print("Imported folder: " .. (data.folder.name or "Unnamed") .. " (" .. count .. " groups)")

    elseif data.type == "container" and data.container and data.panels then
        local importState, _, panelCount, containerId = ImportContainerEntries(db, {{
            container = data.container,
            panels = data.panels,
            _originalContainerId = data._originalContainerId,
        }}, charKey, nil, rootImportState)
        local container = db.groupContainers[containerId]
        if not deferAnchorRemap then
            RemapImportedContainerAnchors(db, importState, false)
            RemapImportedPanelAnchors(db, importState, true)
        end
        CooldownCompanion:Print("Imported group: " .. ((container and container.name) or "Unnamed") .. " (" .. panelCount .. " panels)")

    else
        CooldownCompanion:Print("Import failed: unrecognized export type.")
        return false
    end

    CooldownCompanion:ClearMigrationSentinels()
    local previousDeferCursorAnchorPolicySanitizer = CooldownCompanion._deferCursorAnchorPolicySanitizer
    if deferAnchorRemap then
        CooldownCompanion._deferCursorAnchorPolicySanitizer = true
    end
    local migrationsOk = CooldownCompanion:RunAllMigrations()
    CooldownCompanion._deferCursorAnchorPolicySanitizer = previousDeferCursorAnchorPolicySanitizer
    if not migrationsOk then
        return false
    end

    CooldownCompanion:RefreshConfigPanel()
    CooldownCompanion:RefreshAllGroups()
    if not deferAnchorRemap then
        PrintImportSanitizerNotes(rootImportState)
    end
    return true
end

ST._ApplyGroupImportData = ApplyGroupImportData

StaticPopupDialogs["CDC_EXPORT_GROUP"] = {
    text = "Export string (Ctrl+C to copy):",
    button1 = "Close",
    hasEditBox = true,
    OnShow = function(self)
        if self.data and self.data.exportString then
            self.EditBox:SetText(self.data.exportString)
            self.EditBox:HighlightText()
            self.EditBox:SetFocus()
        end
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function ApplyCustomBarsImportData(data, options)
    if type(data) ~= "table" or data.type ~= "customBars" then
        if RejectUnsupportedImportPayload(data, "custom bars import") then
            return false
        end
        CooldownCompanion:Print("Import failed: this is not a Custom Bars export.")
        return false
    end
    if RejectUnsupportedImportPayload(data, "custom bars import") then
        return false
    end
    local importState = options and options.importState or NewGroupImportState()
    StripImportCharacterEligibility(data, importState)

    local rb = ST._RB
    local settings = CooldownCompanion:GetResourceBarSettings()
    local ok, message
    if rb and rb.ImportCustomBarsPayload then
        ok, message = rb.ImportCustomBarsPayload(settings, data)
    end
    if not ok then
        CooldownCompanion:Print(message or "Import failed.")
        return false
    end

    if not (options and options.silentSuccess) then
        CooldownCompanion:Print(message)
    end
    PrintImportSanitizerNotes(importState)
    CooldownCompanion:ApplyResourceBars()
    CooldownCompanion:UpdateAnchorStacking()
    CooldownCompanion:RefreshConfigPanel()
    return true
end

ST._ApplyCustomBarsImportData = ApplyCustomBarsImportData

StaticPopupDialogs["CDC_EXPORT_CUSTOM_BARS"] = {
    text = "Export Custom Bars string (Ctrl+C to copy):",
    button1 = "Close",
    hasEditBox = true,
    OnShow = function(self)
        if self.data and self.data.exportString then
            self.EditBox:SetText(self.data.exportString)
            self.EditBox:HighlightText()
            self.EditBox:SetFocus()
        end
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_SAVE_GROUP_SETTINGS_PRESET"] = {
    text = "Save current group settings as preset:",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self, data)
        local presetName = TrimPopupText(self.EditBox:GetText())
        if presetName == "" then
            CooldownCompanion:Print("Preset name cannot be empty.")
            return
        end
        if not (data and data.mode and data.groupId) then
            CooldownCompanion:Print("Preset save failed: missing context.")
            return
        end

        local store = CooldownCompanion:NormalizeGroupSettingPresetsStore()
        if store and store[data.mode] and store[data.mode][presetName] ~= nil then
            ShowPopupOverConfig("CDC_OVERWRITE_GROUP_SETTINGS_PRESET", presetName, {
                mode = data.mode,
                groupId = data.groupId,
                presetName = presetName,
            })
            return
        end

        local ok = CooldownCompanion:SaveGroupSettingPreset(data.mode, presetName, data.groupId)
        if not ok then
            CooldownCompanion:Print("Preset save failed.")
            return
        end

        if CS.groupPresetSelection then
            CS.groupPresetSelection[data.mode] = presetName
        end
        CooldownCompanion:RefreshConfigPanel()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["CDC_SAVE_GROUP_SETTINGS_PRESET"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    OnShow = function(self)
        local suggestedName = self.data and self.data.suggestedName
        self.EditBox:SetText(suggestedName or "")
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_OVERWRITE_GROUP_SETTINGS_PRESET"] = {
    text = "Preset '%s' already exists. Overwrite it?",
    button1 = "Overwrite",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not (data and data.mode and data.groupId and data.presetName) then
            CooldownCompanion:Print("Preset overwrite failed: missing context.")
            return
        end

        local ok = CooldownCompanion:SaveGroupSettingPreset(data.mode, data.presetName, data.groupId, {
            allowOverwrite = true,
        })
        if not ok then
            CooldownCompanion:Print("Preset overwrite failed.")
            return
        end

        if CS.groupPresetSelection then
            CS.groupPresetSelection[data.mode] = data.presetName
        end
        CooldownCompanion:RefreshConfigPanel()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DELETE_GROUP_SETTINGS_PRESET"] = {
    text = "Delete preset '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not (data and data.mode and data.presetName) then
            CooldownCompanion:Print("Preset delete failed: missing context.")
            return
        end

        local ok = CooldownCompanion:DeleteGroupSettingPreset(data.mode, data.presetName)
        if not ok then
            CooldownCompanion:Print("Preset delete failed.")
            return
        end

        if CS.groupPresetSelection and CS.groupPresetSelection[data.mode] == data.presetName then
            CS.groupPresetSelection[data.mode] = nil
        end
        CooldownCompanion:RefreshConfigPanel()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_CONFIRM_PANEL_STYLE_COPY"] = {
    text = "Copy style from '%s' to this panel?\n\nThis copies Appearance, Indicators, and layout style. Positioning, Load Conditions, and panel contents stay unchanged.",
    button1 = "Copy",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not (data and data.mode and data.sourceGroupId and data.targetGroupId) then
            CooldownCompanion:Print("Style copy failed: missing context.")
            return
        end

        local ok = CooldownCompanion:CopyDirectStyleFromPanel(data.mode, data.sourceGroupId, data.targetGroupId)
        if not ok then
            CooldownCompanion:Print("Style copy failed.")
            return
        end

        CooldownCompanion:RefreshConfigPanel()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_CONFIRM_CHARACTER_SCOPED_COPY"] = {
    text = "Copy %s?",
    button1 = "Copy",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not (data and data.systemKey and data.sourceCharKey) then
            CooldownCompanion:Print("Copy failed: missing context.")
            return
        end

        local ok = CooldownCompanion:CopyCharacterScopedSettings(data.systemKey, data.sourceCharKey)
        if not ok then
            CooldownCompanion:Print("Copy failed.")
            return
        end

        if data.onCopied then
            data.onCopied()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function AcceptResourceSpecCopy(self, data)
    if not (data and data.sourceSpecID) then
        CooldownCompanion:Print("Copy failed: missing spec context.")
        return
    end

    local ok = CooldownCompanion:CopyResourceBarSpecSettings(data.sourceSpecID)
    if not ok then
        CooldownCompanion:Print("Copy failed.")
        return
    end

    CooldownCompanion:EvaluateResourceBars()
    CooldownCompanion:UpdateAnchorStacking()
    CooldownCompanion:RefreshConfigPanel()
end

StaticPopupDialogs["CDC_CONFIRM_RESOURCE_SPEC_COPY"] = {
    text = "Copy Resource Bar settings from %s?\n\nThis copies Appearance, Layout, resource colors, and non-aura Resource Settings into the current spec. If that spec is using defaults, those default values are copied. Health settings, Custom Bars, and aura overlays are not copied.",
    button1 = "Copy",
    button2 = "Cancel",
    OnAccept = AcceptResourceSpecCopy,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DISCORD_INVITE"] = {
    text = "Join the Cooldown Companion Discord (Ctrl+C to copy):",
    button1 = "Close",
    hasEditBox = true,
    OnShow = function(self)
        self.EditBox:SetText("https://discord.gg/7MGhWMFYeS")
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
