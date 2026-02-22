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

StaticPopupDialogs["CDC_DELETE_GROUP"] = {
    text = "Are you sure you want to delete group '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.groupId then
            CooldownCompanion:DeleteGroup(data.groupId)
            if CS.selectedGroup == data.groupId then
                CS.selectedGroup = nil
                CS.selectedButton = nil
                wipe(CS.selectedButtons)
            end
            CS.selectedGroups[data.groupId] = nil
            CooldownCompanion:RefreshConfigPanel()
        end
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
        if newName and newName ~= "" and data and data.groupId then
            local group = CooldownCompanion.db.profile.groups[data.groupId]
            if group then
                group.name = newName
                CooldownCompanion:RefreshGroupFrame(data.groupId)
                CooldownCompanion:RefreshConfigPanel()
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
            CS.selectedGroup = nil
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            wipe(CS.selectedGroups)
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
            CS.selectedGroup = nil
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            wipe(CS.selectedGroups)
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
            local db = CooldownCompanion.db
            db:SetProfile(text)
            CS.selectedGroup = nil
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            wipe(CS.selectedGroups)
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
            local db = CooldownCompanion.db
            db:SetProfile(newName)
            db:CopyProfile(data.oldName)
            db:DeleteProfile(data.oldName, true)
            CS.selectedGroup = nil
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            wipe(CS.selectedGroups)
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
            local db = CooldownCompanion.db
            db:SetProfile(newName)
            db:CopyProfile(data.source)
            CS.selectedGroup = nil
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            wipe(CS.selectedGroups)
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
                local db = CooldownCompanion.db
                for k, v in pairs(data) do
                    db.profile[k] = v
                end
                CS.selectedGroup = nil
                CS.selectedButton = nil
                wipe(CS.selectedButtons)
                wipe(CS.selectedGroups)
                if db.profile.groups then
                    local charKey = db.keys.char
                    for _, group in pairs(db.profile.groups) do
                        if not group.isGlobal then
                            group.createdBy = charKey
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
        if data and data.groupId then
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
            local group = db.groups[data.dragState.sourceGroupId]
            if group then
                group.specs = nil
                group.heroTalents = nil
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

StaticPopupDialogs["CDC_DRAG_UNGLOBAL_FOLDER"] = {
    text = "This folder contains groups with foreign spec filters. Moving to character will remove those filters. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.dragState then
            local db = CooldownCompanion.db.profile
            local folderId = data.dragState.sourceFolderId
            -- Clear foreign specs from all child groups
            for groupId, group in pairs(db.groups) do
                if group.folderId == folderId and (group.specs or group.heroTalents) then
                    group.specs = nil
                    group.heroTalents = nil
                end
            end
            ST._ApplyCol1Drop(data.dragState)
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
            CS.selectedGroup = nil
            wipe(CS.selectedGroups)
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

StaticPopupDialogs["CDC_UNGLOBAL_SELECTED_GROUPS"] = {
    text = "Some selected groups have foreign spec filters. Moving to character will remove those filters. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.callback then
            -- Strip foreign specs from affected groups before executing the operation
            if data.groupIds then
                local db = CooldownCompanion.db.profile
                local numSpecs = GetNumSpecializations()
                local playerSpecIds = {}
                for i = 1, numSpecs do
                    local specId = C_SpecializationInfo.GetSpecializationInfo(i)
                    if specId then playerSpecIds[specId] = true end
                end
                for _, gid in ipairs(data.groupIds) do
                    local group = db.groups[gid]
                    if group and group.specs then
                        for specId in pairs(group.specs) do
                            if not playerSpecIds[specId] then
                                group.specs = nil
                                group.heroTalents = nil
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
        db.folders[folderId] = {
            name = data.folder.name or "Imported Folder",
            order = folderId,
            section = "char",
            createdBy = charKey,
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
        CooldownCompanion:Print("Imported folder: " .. (data.folder.name or "Unnamed") .. " (" .. count .. " groups)")

    else
        CooldownCompanion:Print("Import failed: unrecognized export type.")
        return false
    end

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
