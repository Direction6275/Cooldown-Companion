--[[
    CooldownCompanion - Config/Popups
    All non-diagnostic StaticPopupDialogs.
    OnAccept handlers use CS.*/ST._* for runtime state access.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

local ResetConfigSelection = ST._ResetConfigSelection

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

local function ShowPopupOverConfig(which, textArg1, data)
    local showFn = (CS and CS.ShowPopupAboveConfig) or ST._ShowPopupAboveConfig
    if showFn then
        return showFn(which, textArg1, data)
    end
    return StaticPopup_Show(which, textArg1, nil, data)
end

local function ClearFolderFiltersForUnglobal(folderId)
    if not folderId then return end

    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if not db then return end

    local folder = db.folders and db.folders[folderId]
    if folder then
        folder.specs = nil
        folder.heroTalents = nil
        CooldownCompanion:ApplyFolderSpecFilterToChildren(folderId)
        return
    end

    -- Fallback: clear specs on child containers (folderId lives on containers post-migration)
    if db.groupContainers then
        for _, container in pairs(db.groupContainers) do
            if container.folderId == folderId and (container.specs or container.heroTalents) then
                container.specs = nil
                container.heroTalents = nil
            end
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
            CooldownCompanion:DeleteGroup(id)
            if data.containerId then
                if CS.selectedContainer == id then
                    CS.selectedContainer = nil
                    CS.selectedGroup = nil
                    CS.selectedButton = nil
                    wipe(CS.selectedButtons)
                end
            else
                if CS.selectedGroup == id then
                    CS.selectedGroup = nil
                    CS.selectedButton = nil
                    wipe(CS.selectedButtons)
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
        CooldownCompanion:DeletePanel(data.containerId, data.panelId)
        if CS.selectedGroup == data.panelId then
            CS.selectedGroup = nil
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
            db:SetProfile(newName)
            db:CopyProfile(data.source)
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
    text = "Export string (Ctrl+C to copy):",
    button1 = "Close",
    hasEditBox = true,
    OnShow = function(self)
        local db = CooldownCompanion.db
        local serialized = AceSerializer:Serialize(db.profile)
        local compressed = LibDeflate:CompressDeflate(serialized)
        local encoded = LibDeflate:EncodeForPrint(compressed)
        self.EditBox:SetText(encoded)
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

StaticPopupDialogs["CDC_IMPORT_PROFILE"] = {
    text = "Paste import string:",
    button1 = "Import",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self)
        local text = self.EditBox:GetText()
        if text and text ~= "" then
            if text:sub(1, 8) == "CDCdiag:" then
                CooldownCompanion:Print("This is a bug report string, not a profile export.")
                return
            end
            local success, data
            -- Detect format: legacy AceSerialized strings start with "^1"
            if text:sub(1, 2) == "^1" then
                success, data = AceSerializer:Deserialize(text)
            else
                local decoded = LibDeflate:DecodeForPrint(text)
                if decoded then
                    local decompressed = LibDeflate:DecompressDeflate(decoded)
                    if decompressed then
                        success, data = AceSerializer:Deserialize(decompressed)
                    end
                end
            end
            if success and type(data) == "table" then
                -- Reject group/folder exports pasted into the profile import dialog
                if data.type then
                    CooldownCompanion:Print("This is a group/folder export. Use the group Import button.")
                    return
                end
                -- Structural validation: a CDC profile must have groups or globalStyle,
                -- and critical fields must be the correct type if present
                if not data.groups and not data.globalStyle then
                    CooldownCompanion:Print("Import failed: data does not appear to be a Cooldown Companion profile.")
                    return
                end
                if (data.groups and type(data.groups) ~= "table")
                   or (data.globalStyle and type(data.globalStyle) ~= "table") then
                    CooldownCompanion:Print("Import failed: profile data is malformed.")
                    return
                end
                local db = CooldownCompanion.db
                -- True replace: wipe existing profile before applying import.
                -- AceDB metatable survives wipe, supplying defaults for missing keys.
                wipe(db.profile)
                for k, v in pairs(data) do
                    db.profile[k] = v
                end
                ResetConfigSelection(true)
                if db.profile.groups then
                    local charKey = db.keys.char
                    for _, group in pairs(db.profile.groups) do
                        if not group.isGlobal then
                            group.createdBy = charKey
                        end
                    end
                end
                if db.profile.groupContainers then
                    local charKey = db.keys.char
                    for _, container in pairs(db.profile.groupContainers) do
                        if not container.isGlobal then
                            container.createdBy = charKey
                        end
                    end
                end
                if db.profile.folders then
                    local charKey = db.keys.char
                    for _, folder in pairs(db.profile.folders) do
                        if folder.section == "char" then
                            folder.createdBy = charKey
                        end
                    end
                end
                CooldownCompanion:ClearMigrationSentinels()
                CooldownCompanion:RunAllMigrations()
                CooldownCompanion:RefreshConfigPanel()
                CooldownCompanion:RefreshAllGroups()
            else
                CooldownCompanion:Print("Import failed: invalid data.")
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["CDC_IMPORT_PROFILE"].OnAccept(parent)
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

StaticPopupDialogs["CDC_UNGLOBAL_GROUP"] = {
    text = "This will remove all spec filters and turn '%s' into a group for your current character. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not data then return end
        if data.containerId then
            local container = CooldownCompanion.db.profile.groupContainers[data.containerId]
            if container then
                container.specs = nil
                container.heroTalents = nil
                CooldownCompanion:ToggleGroupGlobal(data.containerId)
                CooldownCompanion:RefreshConfigPanel()
            end
        elseif data.groupId then
            local group = CooldownCompanion.db.profile.groups[data.groupId]
            if group then
                group.specs = nil
                group.heroTalents = nil
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
    text = "This will remove foreign spec filters and turn '%s' into a character group. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.dragState then
            local db = CooldownCompanion.db.profile
            local container = db.groupContainers[data.dragState.sourceGroupId]
            if container then
                container.specs = nil
                container.heroTalents = nil
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
            ST._StripButtonOverrides(buttonData)
            CooldownCompanion:RefreshGroupFrame(data.sourcePanelId)
            CooldownCompanion:RefreshGroupFrame(data.targetPanelId)
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DRAG_UNGLOBAL_FOLDER"] = {
    text = "This folder contains groups with foreign spec filters. Moving to character will remove those filters. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.dragState then
            local folderId = data.dragState.sourceFolderId
            ClearFolderFiltersForUnglobal(folderId)
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
    text = "This folder contains groups with foreign spec filters. Moving '%s' to character will remove those filters. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.folderId then
            ClearFolderFiltersForUnglobal(data.folderId)
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

StaticPopupDialogs["CDC_UNGLOBAL_SELECTED_GROUPS"] = {
    text = "Some selected groups have foreign spec filters. Moving to character will remove those filters. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.callback then
            -- Strip foreign specs from affected containers before executing the operation
            if data.groupIds then
                local db = CooldownCompanion.db.profile
                local numSpecs = GetNumSpecializations()
                local playerSpecIds = {}
                for i = 1, numSpecs do
                    local specId = C_SpecializationInfo.GetSpecializationInfo(i)
                    if specId then playerSpecIds[specId] = true end
                end
                for _, cid in ipairs(data.groupIds) do
                    local container = db.groupContainers[cid]
                    if container and container.specs then
                        for specId in pairs(container.specs) do
                            if not playerSpecIds[specId] then
                                container.specs = nil
                                container.heroTalents = nil
                                break
                            end
                        end
                    end
                end
            end
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
            CooldownCompanion:DeleteFolder(data.folderId)
            if CS.selectedGroup then
                local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
                if not group then
                    CS.selectedGroup = nil
                    CS.selectedButton = nil
                    wipe(CS.selectedButtons)
                end
            end
            for gid in pairs(CS.selectedGroups) do
                if not CooldownCompanion.db.profile.groups[gid] then
                    CS.selectedGroups[gid] = nil
                end
            end
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

------------------------------------------------------------------------
-- Group/Folder Export/Import
------------------------------------------------------------------------

local function BuildGroupExportData(group)
    local data = CopyTable(group)
    data.createdBy = nil
    data.order = nil
    data.folderId = nil
    data.isGlobal = nil
    return data
end

local function EncodeExportData(payload)
    local serialized = AceSerializer:Serialize(payload)
    local compressed = LibDeflate:CompressDeflate(serialized)
    return LibDeflate:EncodeForPrint(compressed)
end

ST._BuildGroupExportData = BuildGroupExportData
ST._EncodeExportData = EncodeExportData

local function ImportGroupData(text)
    if text:sub(1, 8) == "CDCdiag:" then
        CooldownCompanion:Print("This is a bug report string, not a group export.")
        return false
    end

    local success, data
    if text:sub(1, 2) == "^1" then
        success, data = AceSerializer:Deserialize(text)
    else
        local decoded = LibDeflate:DecodeForPrint(text)
        if decoded then
            local decompressed = LibDeflate:DecompressDeflate(decoded)
            if decompressed then
                success, data = AceSerializer:Deserialize(decompressed)
            end
        end
    end

    if not success or type(data) ~= "table" then
        return false
    end

    -- Reject profile exports (no type field)
    if not data.type then
        CooldownCompanion:Print("This is a profile export. Use the profile Import button.")
        return false
    end

    local db = CooldownCompanion.db.profile
    local charKey = CooldownCompanion.db.keys.char

    if data.type == "group" and data.group then
        local groupId = db.nextGroupId
        db.nextGroupId = groupId + 1
        local group = CopyTable(data.group)
        group.createdBy = charKey
        group.isGlobal = false
        group.order = groupId
        group.folderId = nil
        db.groups[groupId] = group
        CooldownCompanion:CreateGroupFrame(groupId)
        CooldownCompanion:Print("Imported group: " .. (group.name or "Unnamed"))

    elseif data.type == "groups" and data.groups then
        local count = 0
        for _, srcGroup in ipairs(data.groups) do
            local groupId = db.nextGroupId
            db.nextGroupId = groupId + 1
            local group = CopyTable(srcGroup)
            group.createdBy = charKey
            group.isGlobal = false
            group.order = groupId
            group.folderId = nil
            db.groups[groupId] = group
            CooldownCompanion:CreateGroupFrame(groupId)
            count = count + 1
        end
        CooldownCompanion:Print("Imported " .. count .. " groups.")

    elseif data.type == "folder" and data.folder and data.groups then
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
        db.folders[folderId] = {
            name = data.folder.name or "Imported Folder",
            order = folderId,
            section = "char",
            createdBy = charKey,
            manualIcon = importedManualIcon,
            specs = importedSpecs,
            heroTalents = importedHeroTalents,
        }
        local count = 0
        for _, srcGroup in ipairs(data.groups) do
            local groupId = db.nextGroupId
            db.nextGroupId = groupId + 1
            local group = CopyTable(srcGroup)
            group.createdBy = charKey
            group.isGlobal = false
            group.order = groupId
            group.folderId = folderId
            db.groups[groupId] = group
            CooldownCompanion:CreateGroupFrame(groupId)
            count = count + 1
        end
        if importedSpecs then
            CooldownCompanion:ApplyFolderSpecFilterToChildren(folderId)
        end
        CooldownCompanion:Print("Imported folder: " .. (data.folder.name or "Unnamed") .. " (" .. count .. " groups)")

    elseif data.type == "container" and data.container and data.panels then
        -- Import container + all child panels
        local containerId = db.nextContainerId
        db.nextContainerId = containerId + 1
        local container = CopyTable(data.container)
        container.createdBy = charKey
        container.isGlobal = false
        container.order = containerId
        container.folderId = nil
        db.groupContainers[containerId] = container
        CooldownCompanion:CreateContainerFrame(containerId)

        local count = 0
        for _, srcPanel in ipairs(data.panels) do
            local groupId = db.nextGroupId
            db.nextGroupId = groupId + 1
            local panel = CopyTable(srcPanel)
            panel.parentContainerId = containerId
            panel.anchor = {
                point = "TOPLEFT",
                relativeTo = "CooldownCompanionContainer" .. containerId,
                relativePoint = "TOPLEFT",
                x = 0,
                y = 0,
            }
            db.groups[groupId] = panel
            CooldownCompanion:CreateGroupFrame(groupId)
            count = count + 1
        end
        -- Ensure at least one panel exists
        if count == 0 then
            local groupId = db.nextGroupId
            db.nextGroupId = groupId + 1
            db.groups[groupId] = {
                name = "Panel 1",
                order = 1,
                parentContainerId = containerId,
                displayMode = "icons",
                buttons = {},
                anchor = {
                    point = "TOPLEFT",
                    relativeTo = "CooldownCompanionContainer" .. containerId,
                    relativePoint = "TOPLEFT",
                    x = 0,
                    y = 0,
                },
            }
            CooldownCompanion:CreateGroupFrame(groupId)
        end
        CooldownCompanion:Print("Imported group: " .. (container.name or "Unnamed") .. " (" .. count .. " panels)")

    else
        CooldownCompanion:Print("Import failed: unrecognized export type.")
        return false
    end

    CooldownCompanion:ClearMigrationSentinels()
    CooldownCompanion:RunAllMigrations()
    CooldownCompanion:RefreshConfigPanel()
    CooldownCompanion:RefreshAllGroups()
    return true
end

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

StaticPopupDialogs["CDC_IMPORT_GROUP"] = {
    text = "Paste group import string:",
    button1 = "Close",
    hasEditBox = true,
    OnShow = function(self)
        self.EditBox:SetFocus()
    end,
    EditBoxOnTextChanged = function(self)
        local text = self:GetText()
        if text == "" then return end
        local ok = ImportGroupData(text)
        if ok then
            self:GetParent():Hide()
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

StaticPopupDialogs["CDC_CONFIRM_CHARACTER_SCOPED_COPY"] = {
    text = "Copy selected %s settings from the chosen character to this character?",
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
