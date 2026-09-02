--[[
    CooldownCompanion - Config/Popups
    All non-diagnostic StaticPopupDialogs.
    OnAccept handlers use CS.*/ST._* for runtime state access.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

local ResetConfigSelection = ST._ResetConfigSelection
local ClearConfigButtonSelection = ST._ClearConfigButtonSelection
local ClearConfigPanelSelection = ST._ClearConfigPanelSelection
local ClearConfigContainerSelection = ST._ClearConfigContainerSelection
local ClearConfigPanelMultiSelection = ST._ClearConfigPanelMultiSelection
local ClearConfigCustomBarSelection = ST._ClearConfigCustomBarSelection
local EncodeSharedPayload = ST._EncodeSharedPayload
local StripCharacterEligibilityFromPayload = ST._StripCharacterEligibilityFromPayload
local StripLocalPanelMetadataFromEntity = ST._StripLocalPanelMetadataFromEntity
local StripLocalPanelMetadataFromProfile = ST._StripLocalPanelMetadataFromProfile
local StripLocalPanelMetadataFromPayload = ST._StripLocalPanelMetadataFromPayload

local LOAD_CONDITION_ALLOWLIST_KEYS = {
    classAllowlist = "class",
    specAllowlist = "spec",
    characterAllowlist = "character",
}

local CopyAllowlistMap = ST.CopyAllowlistMap

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

local function CountTableEntries(value)
    local count = 0
    if type(value) ~= "table" then
        return count
    end
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function ResourceBarCandidateDetail(settings)
    if type(settings) ~= "table" then
        return "Unavailable"
    end
    local customBars = settings.customBars
    local customBarCount = 0
    if type(customBars) == "table" then
        if type(customBars.entries) == "table" then
            customBarCount = CountTableEntries(customBars.entries)
        else
            for _, specBars in pairs(customBars) do
                customBarCount = customBarCount + CountTableEntries(specBars)
            end
        end
    end
    return ("%d resources, %d custom bars"):format(CountTableEntries(settings.resources), customBarCount)
end

local function AddResourceBarConflictSpacer(chooser, height)
    local spacer = AceGUI:Create("SimpleGroup")
    spacer:SetFullWidth(true)
    spacer:SetHeight(height)
    spacer:SetLayout(nil)
    chooser:AddChild(spacer)
end

local function AddResourceBarConflictText(chooser, text, fontObject)
    local label = AceGUI:Create("Label")
    label:SetText(text)
    label:SetFullWidth(true)
    if fontObject then
        label:SetFontObject(fontObject)
    end
    chooser:AddChild(label)
end

local function ReturnResourceBarConflictFocus()
    local button = CS and CS.resourceBarConflictResolveButton
    if button and button.frame and button.frame.SetFocus then
        button.frame:SetFocus()
    end
end

local function AnchorResourceBarConflictChooser(chooser)
    local frame = chooser and chooser.frame
    if not frame then
        return
    end

    frame:SetParent(UIParent)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
end

local function RaiseResourceBarConflictChooser(chooser)
    local frame = chooser and chooser.frame
    if not frame then
        return
    end

    frame:SetParent(UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetToplevel(true)
    if frame.SetFrameLevel then
        frame:SetFrameLevel(1000)
    end
    if frame.Raise then
        frame:Raise()
    end
end

local function HideResourceBarConflictChooser(markDismissed)
    local chooser = CS and CS.resourceBarConflictChooser
    if not chooser then
        return
    end
    if markDismissed and chooser.classKey then
        CS.resourceBarConflictChooserDismissed = CS.resourceBarConflictChooserDismissed or {}
        CS.resourceBarConflictChooserDismissed[chooser.classKey] = true
    end
    chooser:Hide()
    if chooser.frame then
        chooser.frame:SetScript("OnKeyDown", nil)
        chooser.frame:EnableKeyboard(false)
        if chooser.frame.SetPropagateKeyboardInput then
            chooser.frame:SetPropagateKeyboardInput(true)
        end
    end
    ReturnResourceBarConflictFocus()
end

local function ShowResourceBarConflictChooser(classKey, opts)
    opts = opts or {}
    classKey = classKey or (CooldownCompanion.GetCurrentResourceBarClassKey and CooldownCompanion:GetCurrentResourceBarClassKey())
    local conflict = classKey and CooldownCompanion.GetResourceBarConflict and CooldownCompanion:GetResourceBarConflict(classKey) or nil
    if not conflict then
        return false
    end
    CS.resourceBarConflictChooserDismissed = CS.resourceBarConflictChooserDismissed or {}
    if CS.resourceBarConflictChooserDismissed[classKey] and not opts.force then
        return false
    end
    if not AceGUI then
        CooldownCompanion:Print("Resource Bar conflict chooser is unavailable.")
        return false
    end

    local chooser = CS.resourceBarConflictChooser
    if not chooser then
        chooser = AceGUI:Create("Window")
        chooser:SetTitle("Resolve Resource Bars")
        chooser:SetWidth(560)
        chooser:SetHeight(360)
        chooser:SetLayout("List")
        chooser:EnableResize(false)
        chooser:SetCallback("OnClose", function()
            HideResourceBarConflictChooser(true)
        end)
        CS.resourceBarConflictChooser = chooser
    else
        chooser:Show()
        chooser:ReleaseChildren()
    end

    chooser.classKey = classKey
    chooser.selectedIndex = 1

    local legacyStore = CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.resourceBarsByChar
        or nil
    local classStore = CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.resourceBarsByClass
        or nil
    local existingClassSettings = conflict.includeExistingClass
        and type(classStore) == "table"
        and classStore[classKey]
        or nil
    local rows = {}
    local candidateCharKeys = conflict.candidateCharKeys or {}
    local candidateCount = #candidateCharKeys + (type(existingClassSettings) == "table" and 1 or 0)

    AddResourceBarConflictText(chooser,
        "Choose the Resource Bar setup to |cffffd100KEEP|r for " .. tostring(classKey) .. ".",
        GameFontHighlight)
    AddResourceBarConflictSpacer(chooser, 14)

    local bullets = {
        "The Resource settings from the setup you KEEP will be saved for the whole class.",
        "Custom Bars from every listed same-class setup will be preserved and added to the saved class setup.",
        "The other listed character Resource settings will be removed.",
        "Going forward, every character of this class will use the saved setup.",
        "Per-spec layouts and resource overrides still work inside that class setup.",
    }
    for index, text in ipairs(bullets) do
        AddResourceBarConflictText(chooser, "- " .. text, GameFontHighlight)
        if index < #bullets then
            AddResourceBarConflictSpacer(chooser, 14)
        end
    end
    AddResourceBarConflictSpacer(chooser, 24)

    local function selectRow(index)
        chooser.selectedIndex = index
        for rowIndex, row in ipairs(rows) do
            if row.SetText then
                local prefix = rowIndex == index and "> " or "  "
                row:SetText(prefix .. (row.candidateText or ""))
            end
        end
    end

    local function chooseRow(index)
        local row = rows[index]
        if not row then
            return
        end
        local options = row.keepExistingClassStore and { keepExistingClassStore = true } or nil
        local ok, reason = CooldownCompanion:ResolveResourceBarConflict(classKey, row.sourceCharKey, options)
        if not ok then
            CooldownCompanion:Print("Resource Bar resolution failed: " .. tostring(reason or "unknown error"))
            return
        end
        HideResourceBarConflictChooser(false)
        if CooldownCompanion.ApplyResourceBars then
            CooldownCompanion:ApplyResourceBars()
        end
        if CooldownCompanion.UpdateAnchorStacking then
            CooldownCompanion:UpdateAnchorStacking()
        end
        if CooldownCompanion.RefreshConfigPanel then
            CooldownCompanion:RefreshConfigPanel()
        end
    end

    local function addCandidateRow(sourceCharKey, candidateText, options)
        local index = #rows + 1
        local row = AceGUI:Create("Button")
        row.sourceCharKey = sourceCharKey
        row.keepExistingClassStore = options and options.keepExistingClassStore == true
        row.candidateText = candidateText
        row:SetFullWidth(true)
        row:SetText("  " .. candidateText)
        row:SetCallback("OnClick", function()
            chooseRow(index)
        end)
        rows[index] = row
        chooser:AddChild(row)
        if index < candidateCount then
            AddResourceBarConflictSpacer(chooser, 10)
        end
    end

    if type(existingClassSettings) == "table" then
        addCandidateRow(nil,
            "Current class setup - " .. ResourceBarCandidateDetail(existingClassSettings),
            { keepExistingClassStore = true })
    end

    for _, sourceCharKey in ipairs(candidateCharKeys) do
        addCandidateRow(sourceCharKey,
            sourceCharKey .. " - "
                .. ResourceBarCandidateDetail(type(legacyStore) == "table" and legacyStore[sourceCharKey] or nil))
    end

    AddResourceBarConflictSpacer(chooser, 14)

    local closeButton = AceGUI:Create("Button")
    closeButton:SetText("Later")
    closeButton:SetWidth(90)
    closeButton:SetCallback("OnClick", function()
        HideResourceBarConflictChooser(true)
    end)
    chooser:AddChild(closeButton)

    chooser:SetHeight(math.max(460, 390 + (candidateCount * 38) + (math.max(candidateCount - 1, 0) * 10)))
    chooser.frame:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            HideResourceBarConflictChooser(true)
        elseif key == "ENTER" or key == "SPACE" then
            chooseRow(chooser.selectedIndex or 1)
        elseif key == "DOWN" or key == "TAB" then
            local nextIndex = (chooser.selectedIndex or 1) + 1
            if nextIndex > candidateCount then nextIndex = 1 end
            selectRow(nextIndex)
        elseif key == "UP" then
            local nextIndex = (chooser.selectedIndex or 1) - 1
            if nextIndex < 1 then nextIndex = candidateCount end
            selectRow(nextIndex)
        end
    end)
    chooser.frame:EnableKeyboard(true)
    if chooser.frame.SetPropagateKeyboardInput then
        chooser.frame:SetPropagateKeyboardInput(false)
    end
    chooser:Show()
    AnchorResourceBarConflictChooser(chooser)
    RaiseResourceBarConflictChooser(chooser)
    selectRow(1)
    return true
end

ST._ShowResourceBarConflictChooser = ShowResourceBarConflictChooser

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

StaticPopupDialogs["CDC_DELETE_EMPTY_CDM_PANEL"] = {
    text = "Cooldown Manager section for '%s' is empty. Delete this panel?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if ST._DeleteEmptyCDMPanel then
            ST._DeleteEmptyCDMPanel(data)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_REFRESH_CDM_PANEL"] = {
    text = "Replace the entries in '%s' with its Cooldown Manager section? Per-entry settings will be lost.",
    button1 = "Replace",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not data then
            return
        end
        local panel = CooldownCompanion.db.profile.groups[data.panelId]
        -- Same class-scope rule as the menu: the refresh reads the logged-in
        -- character's CDM data, so another class's browsed panel must never
        -- accept it.
        if panel
            and panel.parentContainerId == data.containerId
            and panel.cdmPanelSource == data.sourceKey
            and ST._IsCreateTargetContainer
            and ST._IsCreateTargetContainer(data.containerId)
            and ST._RefreshCDMPanelFromSource then
            ST._RefreshCDMPanelFromSource(data.panelId, panel, data.containerId)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Leaving icon mode with Panel Sections placed. The panel is named by id rather
-- than handed over live, and the flatten runs at Accept time so a Cancel leaves
-- both the placements and the display mode exactly as they were.
--
-- The flatten is handed to the mode change rather than run here first: the
-- switch is judged again inside ChangePanelDisplayMode and can still be
-- refused, and a refusal must leave the placements untouched.
StaticPopupDialogs["CDC_FLATTEN_PANEL_SECTIONS"] = {
    text = "'%s' has sections. Switching display mode flattens them back into the base row.",
    button1 = "Switch",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not (data and data.panelId and data.targetMode) then return end
        if not CooldownCompanion.db.profile.groups[data.panelId] then return end
        if ST._ApplyPanelDisplayModeChange then
            ST._ApplyPanelDisplayModeChange(data.panelId, data.containerId,
                data.targetMode, true)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Revert All, from the entry Settings pane's Customizations heading. The entry
-- is named by id rather than handed over live: a popup outlives the build that
-- opened it, and the entry it names can be gone by the time Accept comes back.
StaticPopupDialogs["CDC_REVERT_ENTRY_CUSTOMIZATIONS"] = {
    text = "Revert every customization on '%s' to panel settings?",
    button1 = "Revert All",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.groupId and data.buttonIndex and ST._RevertAllEntryCustomizations then
            ST._RevertAllEntryCustomizations(data.groupId, data.buttonIndex)
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

-- Panel Templates (Core/PanelTemplates.lua). The name box opens holding the
-- panel's own name, selected, so typing replaces it and Enter keeps it.
StaticPopupDialogs["CDC_SAVE_PANEL_TEMPLATE"] = {
    text = "Save panel '%s' as template:",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self, data)
        if not (data and data.panelId and CooldownCompanion.SavePanelTemplate) then return end
        local templateId = CooldownCompanion:SavePanelTemplate(data.panelId, self.EditBox:GetText())
        if not templateId then
            CooldownCompanion:Print("Could not save the template: the panel is gone or is not an icon, bar, or text panel.")
            return
        end
        local template = CooldownCompanion:GetPanelTemplate(templateId)
        CooldownCompanion:Print("Saved template '" .. (template and template.name or "") .. "'.")
        CooldownCompanion:RefreshConfigPanel()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["CDC_SAVE_PANEL_TEMPLATE"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    OnShow = function(self, data)
        self.EditBox:SetText(data and data.defaultName or "")
        self.EditBox:SetFocus()
        self.EditBox:HighlightText()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_UPDATE_PANEL_TEMPLATE"] = {
    text = "Update template '%s' from this panel?",
    button1 = "Update",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not (data and CooldownCompanion.UpdatePanelTemplate) then return end
        local updated, reason = CooldownCompanion:UpdatePanelTemplate(data.templateId, data.panelId)
        if not updated then
            CooldownCompanion:Print(reason == "mode_mismatch"
                and "That template is for a different panel type."
                or "Could not update the template.")
            return
        end
        local template = CooldownCompanion:GetPanelTemplate(data.templateId)
        CooldownCompanion:Print("Updated template '" .. (template and template.name or "") .. "'.")
        CooldownCompanion:RefreshConfigPanel()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DELETE_PANEL_TEMPLATE"] = {
    text = "Delete template '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not (data and CooldownCompanion.DeletePanelTemplate) then return end
        local template = CooldownCompanion:GetPanelTemplate(data.templateId)
        local name = template and template.name or ""
        if CooldownCompanion:DeletePanelTemplate(data.templateId) then
            CooldownCompanion:Print("Deleted template '" .. name .. "'.")
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DELETE_BUTTON"] = {
    text = "Are you sure you want to delete '%s'?",
    button1 = "Delete",
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
    text = "Delete %d selected entries?",
    button1 = "Delete",
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
                -- A batch delete can empty several sections at once, so sweep
                -- the panel once here instead of per entry. Without it every
                -- emptied anchor stays in the profile as a Layout-tab block for
                -- a cluster with nothing in it.
                ST.SweepEmptyPanelSections(group)
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
            if StripLocalPanelMetadataFromProfile then
                StripLocalPanelMetadataFromProfile(db.profile)
            end
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
        if CooldownCompanion.GetPendingResourceBarConflictExportMessage then
            local blockMessage = CooldownCompanion:GetPendingResourceBarConflictExportMessage()
            if blockMessage then
                self.EditBox:SetText(blockMessage)
                self.EditBox:HighlightText()
                self.EditBox:SetFocus()
                if CooldownCompanion.Print then
                    CooldownCompanion:Print(blockMessage)
                end
                return
            end
        end
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

StaticPopupDialogs["CDC_DELETE_SELECTED_GROUPS"] = {
    text = "Delete %d selected groups?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.groupIds then
            for _, gid in ipairs(data.groupIds) do
                -- Ids freeze at popup-show time; a container deleted while the
                -- popup was open must not fall through DeleteGroup's panel-id path.
                if CooldownCompanion.db.profile.groupContainers[gid] then
                    CooldownCompanion:DeleteGroup(gid)
                end
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
            ClearConfigCustomBarSelection({ clearExpanded = true })
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

StaticPopupDialogs["CDC_DELETE_CUSTOM_BAR"] = {
    text = "Are you sure you want to delete Custom Bar '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.customBarId and ST._DeleteConfigCustomBar then
            ST._DeleteConfigCustomBar(data.customBarId)
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

------------------------------------------------------------------------
-- Group export and apply
------------------------------------------------------------------------

local function GetCustomBarExportConflictBlockMessage()
    if CooldownCompanion.GetCurrentResourceBarConflictExportMessage then
        return CooldownCompanion:GetCurrentResourceBarConflictExportMessage()
    end
    return nil
end

local function BlockCustomBarExportForResourceBarConflict()
    local message = GetCustomBarExportConflictBlockMessage()
    if message then
        if CooldownCompanion.Print then
            CooldownCompanion:Print(message)
        end
        return true, message
    end
    return false, nil
end

local function BuildGroupExportData(group)
    local data = CopyTable(group)
    if StripLocalPanelMetadataFromEntity then
        StripLocalPanelMetadataFromEntity(data)
    end
    data.createdBy = nil
    data.order = nil
    data.isGlobal = nil
    data.parentContainerId = nil
    return data
end

local function EncodeExportData(payload)
    if type(payload) == "table" and payload.type == "customBars" then
        local blocked = BlockCustomBarExportForResourceBarConflict()
        if blocked then
            return nil
        end
    end
    if type(payload) == "table" and payload.type == "setup"
        and (payload.resources or payload.customBars) then
        local blocked = BlockCustomBarExportForResourceBarConflict()
        if blocked then
            return nil
        end
    end
    return EncodeSharedPayload(payload, "entity")
end

-- Assembles the one-string setup payload from its sections. Any section may
-- be nil. `customBars` accepts the standalone customBars payload shape (the
-- `type` marker is dropped; sections carry no type of their own). A Resources
-- section already contains its class's Custom Bars, so callers must not pass
-- both for the same class.
local function BuildSetupExportPayload(sections)
    if type(sections) ~= "table" then
        return nil
    end
    local payload = { type = "setup", version = 1 }
    local hasAny = false

    if type(sections.containers) == "table" and #sections.containers > 0 then
        payload.containers = sections.containers
        hasAny = true
    end
    if type(sections.customBars) == "table"
        and type(sections.customBars.bars) == "table"
        and #sections.customBars.bars > 0 then
        payload.customBars = {
            version = sections.customBars.version or 1,
            classID = sections.customBars.classID,
            classFilename = sections.customBars.classFilename,
            bars = sections.customBars.bars,
            layouts = sections.customBars.layouts,
        }
        hasAny = true
    end
    if type(sections.resources) == "table"
        and type(sections.resources.settings) == "table" then
        payload.resources = sections.resources
        hasAny = true
    end

    if not hasAny then
        return nil
    end
    return payload
end

local function BuildContainerExportData(container)
    local data = CopyTable(container)
    data.createdBy = nil
    data.order = nil
    data.specOrders = nil
    -- isGlobal deliberately rides: the import landing decision reads it to
    -- keep an originally-global group global. Stripping it here forced a
    -- _sourceGlobal side-channel that restated the same fact.
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
ST._BuildSetupExportPayload = BuildSetupExportPayload

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
    panel.cdmPanelSource = nil
    panel.parentContainerId = containerId
    panel.order = panelIndex
    -- Piece imports land in an already-migrated profile, so pre-split
    -- bar/text panels get their per-mode orientation key mapped here.
    if ST._NormalizePanelOrientationKeys then
        ST._NormalizePanelOrientationKeys(panel)
    end
    -- An imported Aura Panel is raw payload data installed wholesale, with none
    -- of the create/add gates in front of it, so the subtype's invariants are
    -- re-established here before the panel reaches the profile.
    if ST._NormalizeAuraPanelEntries then
        ST._NormalizeAuraPanelEntries(panel)
    end
    -- An imported mixed panel can carry AURA SECTIONS, which are the same raw
    -- payload with none of the toggle's admission check in front of them.
    if ST._NormalizeAuraSectionEntries then
        ST._NormalizeAuraSectionEntries(panel)
    end
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

local function ImportContainerEntries(db, entries, charKey, importState, options)
    importState = importState or NewGroupImportState()
    options = options or {}
    local firstContainerIndex = #importState.importedContainerIds + 1
    local startContainerCount = importState.containerCount
    local startPanelCount = importState.panelCount
    local _, _, importerClassID = UnitClass("player")
    -- Once for this whole door, before any landing decision: the hero-talent
    -- sweep behind those decisions costs ~40 view-loadout builds and must be
    -- retried across imports but never repeated within one.
    if ST._ResetHeroTalentSweepAttempt then
        ST._ResetHeroTalentSweepAttempt()
    end

    for _, entry in ipairs(entries) do
        local containerId = db.nextContainerId
        db.nextContainerId = containerId + 1
        importState.importedContainerIds[#importState.importedContainerIds + 1] = containerId
        if entry._originalContainerId then
            importState.containerIdMap[entry._originalContainerId] = containerId
        end

        local container = CopyTable(entry.container)
        -- Landing scope: an originally-global piece stays global; everything
        -- else goes through the SAME decision the full-profile door uses
        -- (ST._ResolveEntityTreeLanding), so one policy owns both doors.
        -- Only content no class section can represent (cross-class mixes,
        -- class allowlists) moves the piece to Global.
        local sourceWasGlobal = container.isGlobal == true
            or container.section == "global"
        local importAsGlobal = options.forceGlobalScope == true or sourceWasGlobal
        local landingCharKey
        if not importAsGlobal
            and ContainerEntryHasPortableEligibility(entry)
            and ST._ResolveEntityTreeLanding
        then
            local entities = { entry.container }
            for _, panel in ipairs(entry.panels or {}) do
                entities[#entities + 1] = panel
            end
            -- importerClassID nil (UnitClass gave nothing) means "cannot
            -- tell", and the shared rule then keeps the importer as owner
            -- rather than re-homing every piece onto a placeholder.
            local mustGlobalize
            landingCharKey, mustGlobalize = ST._ResolveEntityTreeLanding(entities, importerClassID)
            if mustGlobalize then
                importAsGlobal = true
                landingCharKey = nil
            end
        end
        container.createdBy = landingCharKey or charKey
        container.isGlobal = importAsGlobal
        if not importAsGlobal and ST._FoldSpecAllowlistIntoSpecs then
            ST._FoldSpecAllowlistIntoSpecs(container)
            for _, panel in ipairs(entry.panels or {}) do
                ST._FoldSpecAllowlistIntoSpecs(panel)
            end
        end
        if type(options.legacyFolder) == "table" then
            -- Decode-only compatibility: apply the retired Folder's inherited
            -- restrictions through the canonical migration, without ever
            -- attaching Folder state to the live profile.
            local legacyProfile = {
                groupContainers = { [1] = container },
                groups = {},
                folders = { [1] = CopyTable(options.legacyFolder) },
                nextFolderId = 2,
            }
            container.folderId = 1
            CooldownCompanion:MigrateFoldersIntoGroups(legacyProfile)
        end
        container.order = containerId
        container.specOrders = nil
        container.locked = true
        if importAsGlobal and not sourceWasGlobal then
            importState.globalizedEligibilityImports = (importState.globalizedEligibilityImports or 0) + 1
        elseif landingCharKey then
            importState.sortedEligibilityImports = (importState.sortedEligibilityImports or 0) + 1
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
    if (importState.sortedEligibilityImports or 0) > 0 then
        CooldownCompanion:Print("Imported groups were sorted into class sections by their eligibility (x" .. importState.sortedEligibilityImports .. ").")
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

-- Import doors insert entries that can carry main-era keys AFTER the
-- migration sentinels stamped, so the chain re-runs over the profile (it is
-- idempotent by contract). Centralized because getting it right has three
-- parts every door needs:
--   * While a group-import batch is open, imported anchors still hold the
--     exporter's frame references. SanitizeCursorAnchorPolicy runs inside
--     the chain and would judge them before FinishGroupImportBatch remaps
--     them, detaching imported groups to the screen root — so it is
--     deferred, and the batch sanitizes once anchors are correct.
--   * A multi-section import (setup, pieces) would otherwise walk the whole
--     profile once per section. Those doors pass options.deferMigrations and
--     take one run themselves after finishing their batch. Deferral is a
--     per-call argument, deliberately not shared state: an earlier version
--     used a module-level counter, and a Lua error thrown between its
--     increment and decrement left it raised for the rest of the session,
--     after which every import silently skipped the chain and still
--     reported success.
--   * The failure return is the caller's to honor; reporting success over a
--     profile whose migration bailed is how unmigrated data ships silently.
--     Doors still refresh after a failed run: the entries are already
--     committed with no rollback, so leaving the UI showing the pre-import
--     profile only hides that fact.
local function RunPostImportMigrations()
    CooldownCompanion:ClearMigrationSentinels()
    local previousDefer = CooldownCompanion._deferCursorAnchorPolicySanitizer
    if next(activeGroupImportBatches) ~= nil then
        CooldownCompanion._deferCursorAnchorPolicySanitizer = true
    end
    local ok = CooldownCompanion:RunAllMigrations()
    CooldownCompanion._deferCursorAnchorPolicySanitizer = previousDefer
    if not ok then
        CooldownCompanion:Print("Import failed: this profile could not be migrated to 12.1.")
    end
    return ok
end

-- Exported for the pieces door, the other multi-section import: it lives in
-- ProfileImportPieces.lua, defers its sections the same way, and so needs to
-- take the single run itself.
ST._RunPostImportMigrations = RunPostImportMigrations

local function ApplyGroupImportData(data, options)
    if type(data) ~= "table" then
        return false
    end
    local batchToken = activeGroupImportPayloads[data]
    activeGroupImportPayloads[data] = nil
    if RejectUnsupportedImportPayload(data, "group import") then
        return false
    end
    if StripLocalPanelMetadataFromPayload then
        StripLocalPanelMetadataFromPayload(data)
    end

    if not data.type then
        CooldownCompanion:Print("Import failed: this is a profile backup, not a group or panel export.")
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
        local importState, containerCount = ImportContainerEntries(db, data.containers, charKey, rootImportState)
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
        local legacyFolder = {
            name = data.folder.name or "Imported Folder",
            order = 1,
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
            local importState, containerCount = ImportContainerEntries(
                db, data.containers, charKey, rootImportState, {
                    forceGlobalScope = folderUsesGlobalEligibility and true or false,
                    legacyFolder = legacyFolder,
                }
            )
            if not deferAnchorRemap then
                RemapImportedContainerAnchors(db, importState, true)
                RemapImportedPanelAnchors(db, importState)
            end
            count = containerCount
        end
        CooldownCompanion:Print("Imported " .. count .. " groups.")

    -- Legacy single-group strings (pre-Export-mode). No current producer
    -- emits this shape. The old exporter stripped isGlobal, so an
    -- originally-global group cannot prove it was global and lands by
    -- content like everything else; current payloads carry isGlobal in the
    -- container itself, where the landing decision reads it.
    elseif data.type == "container" and data.container and data.panels then
        local importState, _, panelCount, containerId = ImportContainerEntries(db, {{
            container = data.container,
            panels = data.panels,
            _originalContainerId = data._originalContainerId,
        }}, charKey, rootImportState)
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

    local migrationOk = true
    if not (options and options.deferMigrations) then
        migrationOk = RunPostImportMigrations()
    end

    -- Refresh even when the migration failed: the groups above are already
    -- written and there is no rollback, so returning early would only leave
    -- the config and the live frames describing a profile that no longer
    -- exists. The failure is reported by RunPostImportMigrations and carried
    -- out in the return value.
    CooldownCompanion:RefreshConfigPanel()
    CooldownCompanion:RefreshAllGroups()
    if not deferAnchorRemap then
        PrintImportSanitizerNotes(rootImportState)
    end
    return migrationOk
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

-- classKey defaults to the current class. Setup imports pass the class the
-- payload targets, so a cross-class import respects THAT class's pending
-- conflict, not the importing character's.
local function BlockCustomBarsImportForResourceBarConflict(classKey)
    classKey = classKey
        or (CooldownCompanion.GetCurrentResourceBarClassKey
            and CooldownCompanion:GetCurrentResourceBarClassKey())
        or nil
    local conflict = CooldownCompanion.GetResourceBarConflict
        and CooldownCompanion:GetResourceBarConflict(classKey)
        or nil
    if not conflict then
        return false
    end

    local message = "Resolve the pending Resource Bar conflict"
        .. (classKey and (" for " .. tostring(classKey)) or "")
        .. " before importing Custom Bars. Choose the setup to keep, then import again."
    CooldownCompanion:Print(message)
    if ST._ShowResourceBarConflictChooser then
        ST._ShowResourceBarConflictChooser(classKey, { force = true })
    end
    return true
end

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
    local targetClassKey = options and options.targetClassKey or nil
    if BlockCustomBarsImportForResourceBarConflict(targetClassKey) then
        return false
    end
    local importState = options and options.importState or NewGroupImportState()
    StripImportCharacterEligibility(data, importState)

    local rb = ST._RB
    local settings
    if targetClassKey and CooldownCompanion.EnsureResourceBarSettingsForClass then
        settings = CooldownCompanion:EnsureResourceBarSettingsForClass(targetClassKey)
    else
        settings = CooldownCompanion:GetResourceBarSettings()
    end
    local ok, message
    if rb and rb.ImportCustomBarsPayload then
        ok, message = rb.ImportCustomBarsPayload(settings, data, targetClassKey and {
            targetClassKey = targetClassKey,
        } or nil)
    end
    if not ok then
        CooldownCompanion:Print(message or "Import failed.")
        return false
    end

    if not (options and options.silentSuccess) then
        CooldownCompanion:Print(message)
    end
    PrintImportSanitizerNotes(importState)
    local migrationOk = true
    if not (options and options.deferMigrations) then
        migrationOk = RunPostImportMigrations()
    end

    -- Apply and refresh even when the migration failed: the bars are already
    -- written into the live settings table with no rollback, and the success
    -- message above has already gone out. Returning before this left the
    -- caller parked in Import mode with bars in the profile and none on
    -- screen until a reload.
    CooldownCompanion:ApplyResourceBars()
    CooldownCompanion:UpdateAnchorStacking()
    CooldownCompanion:RefreshConfigPanel()
    return migrationOk
end

local function GetSetupSectionClassKey(section)
    if type(section) ~= "table" then
        return nil
    end
    local normalize = ST._NormalizeResourceBarClassKey
    local classKey = normalize and normalize(section.classFilename) or nil
    if classKey then
        return classKey
    end
    if section.classID and ST._GetResourceBarClassKeyFromClassID then
        return ST._GetResourceBarClassKeyFromClassID(section.classID)
    end
    return nil
end

-- Applies a `setup` payload: groups additively, then the Resources section as
-- a whole-bucket replace for its class, then any Custom Bars section
-- additively. Order matters: groups first so the Resources anchor can remap
-- onto the groups imported from the same string.
local function ApplySetupImportData(data)
    if type(data) ~= "table" or data.type ~= "setup" then
        CooldownCompanion:Print("Import failed: this is not a setup export.")
        return false
    end
    if RejectUnsupportedImportPayload(data, "setup import") then
        return false
    end

    local hasContainers = type(data.containers) == "table" and #data.containers > 0
    local customBarsSection = type(data.customBars) == "table"
        and type(data.customBars.bars) == "table"
        and #data.customBars.bars > 0
        and data.customBars
        or nil
    local resourcesSection = type(data.resources) == "table"
        and type(data.resources.settings) == "table"
        and data.resources
        or nil
    if not hasContainers and not customBarsSection and not resourcesSection then
        CooldownCompanion:Print("Import failed: this setup export is empty.")
        return false
    end

    local resourcesClassKey = resourcesSection and GetSetupSectionClassKey(resourcesSection) or nil
    if resourcesSection and not resourcesClassKey then
        CooldownCompanion:Print("Import failed: the Resources setup does not name its class.")
        return false
    end
    local barsClassKey = customBarsSection and GetSetupSectionClassKey(customBarsSection) or nil
    if customBarsSection and not barsClassKey then
        CooldownCompanion:Print("Import failed: the Custom Bars do not name their class.")
        return false
    end

    if resourcesClassKey and BlockCustomBarsImportForResourceBarConflict(resourcesClassKey) then
        return false
    end
    if barsClassKey and barsClassKey ~= resourcesClassKey
        and BlockCustomBarsImportForResourceBarConflict(barsClassKey) then
        return false
    end

    local batchToken = ST._BeginGroupImportBatch()
    local applied = false
    local failed = false
    local containersApplied = false
    local customBarsApplied = false

    -- One migration run owns this whole click: each section would otherwise
    -- walk the entire profile again, and the runs nested inside the open
    -- batch would sanitize anchors that are not remapped yet. Every section
    -- is handed this and the single run is taken below, once the batch has
    -- closed.
    local deferToSetupRun = { deferMigrations = true }

    if hasContainers then
        local containersPayload = {
            type = "containers",
            containers = data.containers,
            _cdcImportCheckpoint = data._cdcImportCheckpoint,
        }
        ST._AttachGroupImportBatch(containersPayload, batchToken)
        containersApplied = ApplyGroupImportData(containersPayload, deferToSetupRun) == true
        applied = containersApplied or applied
        failed = failed or not containersApplied
    end

    local importState = activeGroupImportBatches[batchToken]

    if resourcesSection then
        local settings = CopyTable(resourcesSection.settings)
        local anchorId = tonumber(settings.anchorGroupId)
        if anchorId then
            -- The exporter's group ids mean nothing here; keep the anchor only
            -- when it remaps onto a group imported from this same string.
            settings.anchorGroupId = importState
                and importState.groupIdMap
                and importState.groupIdMap[anchorId]
                or nil
        end
        local replaced = CooldownCompanion.ReplaceResourceBarClassSettings
            and CooldownCompanion:ReplaceResourceBarClassSettings(resourcesClassKey, settings)
        if replaced then
            applied = true
            CooldownCompanion:Print("Imported Resources setup for " .. tostring(resourcesClassKey) .. ".")
        else
            failed = true
        end
    end

    -- A Resources section already carries its class's Custom Bars; a separate
    -- bars section for that same class would double-import them. Export mode
    -- never builds both, so only apply bars aimed at a different class.
    if customBarsSection and barsClassKey ~= resourcesClassKey then
        local barsPayload = {
            type = "customBars",
            version = customBarsSection.version or 1,
            classID = customBarsSection.classID,
            classFilename = customBarsSection.classFilename,
            bars = customBarsSection.bars,
            layouts = customBarsSection.layouts,
            _cdcImportCheckpoint = data._cdcImportCheckpoint,
        }
        local ok = ApplyCustomBarsImportData(barsPayload, {
            targetClassKey = barsClassKey,
            deferMigrations = true,
        }) == true
        customBarsApplied = ok
        applied = ok or applied
        failed = failed or not ok
    end

    ST._FinishGroupImportBatch(batchToken, containersApplied)

    -- The single migration run for every section this setup inserted, taken
    -- once the batch has remapped anchors so the chain's cursor-anchor
    -- sanitizer judges final data -- and BEFORE the refresh below, because
    -- every section deferred its own run and the frames built by that
    -- refresh must come from migrated entries. Running it after meant a
    -- setup carrying main-era data rendered with retired keys still live
    -- until the next spec change or reload, under a chat line announcing
    -- the migration had happened.
    local migrationOk = true
    if applied then
        migrationOk = RunPostImportMigrations()
        failed = failed or not migrationOk
    end

    -- The batch remaps container and panel anchors, and that runs AFTER
    -- ApplyGroupImportData's own RefreshAllGroups - so without this the
    -- remapped anchors never reach the live frames (same reason
    -- ApplyProfileImportPieces refreshes after finishing its batch).
    if containersApplied and CooldownCompanion.RefreshAllGroups then
        CooldownCompanion:RefreshAllGroups()
    end

    -- Rebuild bars after the migration for either section that can hold
    -- them. A Custom Bars section builds its own bars on the way in, but it
    -- deferred the migration to this function, so those bars came from
    -- pre-migration entries and have to be rebuilt here just as a Resources
    -- section does.
    if resourcesSection or customBarsApplied then
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end

    if failed then
        CooldownCompanion:Print(applied
            and "Import finished: some parts of this setup could not be imported."
            or "Import failed: this setup could not be imported.")
    end
    -- A failed final migration is a failed import even though the sections
    -- landed: the caller uses this to decide whether to leave Import mode,
    -- and treating unmigrated data as a clean import is how it ships.
    return applied and migrationOk
end

ST._BlockCustomBarsImportForResourceBarConflict = BlockCustomBarsImportForResourceBarConflict
ST._ApplyCustomBarsImportData = ApplyCustomBarsImportData
ST._ApplySetupImportData = ApplySetupImportData

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
    text = "Copy Resource Bar settings from %s?\n\nThis copies Appearance, Layout, resource colors, and Resource Settings into the current spec. If that spec is using defaults, those default values are copied. Health settings and Custom Bars are not copied.",
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
