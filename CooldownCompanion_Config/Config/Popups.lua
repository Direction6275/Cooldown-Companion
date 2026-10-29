--[[
    CooldownCompanion - Config/Popups
    Most config StaticPopupDialogs (the Import Mode confirm lives in
    ImportMode.lua, the diagnostics popups in Diagnostics.lua and profile
    reset in Core/ConfigLoader.lua), plus the Resource Bar conflict chooser,
    the group and setup export builders, and the group/setup import engine.
    OnAccept handlers use CS.*/ST._* for runtime state access.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

local ResetConfigSelection = ST._ResetConfigSelection
local ClearConfigPanelSelection = ST._ClearConfigPanelSelection
local ClearConfigContainerSelection = ST._ClearConfigContainerSelection
local ClearConfigPanelMultiSelection = ST._ClearConfigPanelMultiSelection
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

-- A free name for a copy of a profile, worded like a duplicated Group or
-- panel: "Main (Copy)", then "Main (Copy 2)" on.
local function GetCopyProfileName(source)
    local name = source .. " (Copy)"
    local suffix = 2
    while ProfileNameExists(name) do
        name = source .. " (Copy " .. suffix .. ")"
        suffix = suffix + 1
    end
    return name
end

-- Names typed into a popup are trimmed; a blank one is refused.
local function TrimEnteredName(text)
    return text and strtrim(text) or ""
end

-- Profiles in A-Z order, ignoring case: the profile bar lists them this way
-- and Delete lands on the first one left.
local function GetSortedProfiles()
    local profiles = CooldownCompanion.db:GetProfiles()
    table.sort(profiles, function(a, b)
        local lowerA, lowerB = a:lower(), b:lower()
        if lowerA ~= lowerB then return lowerA < lowerB end
        return a < b
    end)
    return profiles
end
ST._GetSortedProfiles = GetSortedProfiles

-- Rename boxes open holding the current name, and Duplicate a free copy
-- name, selected, like Save Template.
local function PrefillEditBox(popup, text)
    popup.EditBox:SetText(text or "")
    popup.EditBox:SetFocus()
    popup.EditBox:HighlightText()
end

local function RejectUnsupportedImportPayload(data, dataLabel)
    if CooldownCompanion.IsUnsupportedImportPayload and CooldownCompanion:IsUnsupportedImportPayload(data) then
        CooldownCompanion:NotifyLegacySupportCutoff(dataLabel)
        return true
    end
    return false
end
ST._RejectUnsupportedImportPayload = RejectUnsupportedImportPayload

local CountPairs = ST.CountPairs

local function ResourceBarCandidateDetail(settings)
    if type(settings) ~= "table" then
        return "Unavailable"
    end
    local customBars = settings.customBars
    local customBarCount = 0
    if type(customBars) == "table" then
        if type(customBars.entries) == "table" then
            customBarCount = CountPairs(customBars.entries)
        else
            for _, specBars in pairs(customBars) do
                customBarCount = customBarCount + CountPairs(specBars)
            end
        end
    end
    return ("%d resources, %d custom bars"):format(CountPairs(settings.resources), customBarCount)
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
    classKey = classKey or CooldownCompanion:GetNextResourceBarConflictClassKey()
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

    local profile = CooldownCompanion.db.profile
    local chooser = CS.resourceBarConflictChooser
    if chooser and chooser.classKey == classKey and chooser.profile == profile
        and chooser.conflict == conflict and chooser.frame:IsShown() then return true end
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
    chooser.profile, chooser.conflict = profile, conflict
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
        "Legacy Custom Bars from every listed same-class setup will be kept and converted into panel entries.",
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
        if CooldownCompanion.db.profile ~= profile
            or CooldownCompanion:GetResourceBarConflict(classKey) ~= conflict then return end
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
        -- Resume the same migration/activation path used by profile changes.
        -- A refused initial conversion has not created any panel frames yet.
        CooldownCompanion:RunProfileMigrationAndRefresh("resource-conflict-resolved")
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
    text = "%s",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        local id = data and data.containerId
        if not id then return end
        CooldownCompanion:ClearAllConfigPreviews()
        -- Ids freeze at popup-show time and the Group may already be gone;
        -- DeleteContainer does nothing for a missing id.
        CooldownCompanion:DeleteContainer(id)
        if CS.selectedContainer == id then
            ClearConfigContainerSelection()
        end
        CS.selectedGroups[id] = nil
        CooldownCompanion:RefreshConfigPanel()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Deleting a Group deletes every panel in it, so the prompts say how many:
-- " and its 3 panels", " and their 1 panel", or nothing for none.
local function PanelCountClause(panelCount, possessive)
    if panelCount == 0 then return "" end
    return " and " .. possessive .. " " .. panelCount .. (panelCount == 1 and " panel" or " panels")
end

function ST._ShowDeleteGroupPopup(containerId)
    local container = CooldownCompanion.db.profile.groupContainers[containerId]
    if not container then return end
    local text = "Delete group '" .. (container.name or "Group") .. "'"
        .. PanelCountClause(CooldownCompanion:GetPanelCount(containerId), "its") .. "?"
    ST._ShowPopupAboveConfig("CDC_DELETE_GROUP", text, { containerId = containerId })
end

StaticPopupDialogs["CDC_DELETE_PANEL"] = {
    text = "Delete panel '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not data then return end
        CooldownCompanion:ClearAllConfigPreviews()
        CooldownCompanion:DeletePanel(data.containerId, data.panelId)
        if CS.selectedGroup == data.panelId then
            ClearConfigPanelSelection()
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

-- Revert All, from the entry Settings pane's Customizations heading. The entry
-- is named by id rather than handed over live: a popup outlives the build that
-- opened it, and the entry it names can be gone by the time Accept comes back.
StaticPopupDialogs["CDC_REVERT_ENTRY_CUSTOMIZATIONS"] = {
    text = "Revert every customization on '%s' to panel settings?",
    button1 = "Revert All",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.groupId and data.buttonIndex and ST._RevertAllEntryCustomizations then
            ST._RevertAllEntryCustomizations(data.groupId, data.buttonIndex, data.target, data.entry)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- The same Revert All for a Resources or Cast Bar customization list. The
-- callback re-checks its module context before reverting anything.
StaticPopupDialogs["CDC_REVERT_MODULE_CUSTOMIZATIONS"] = {
    text = "Revert every customization on '%s'?",
    button1 = "Revert All",
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

StaticPopupDialogs["CDC_RENAME_GROUP"] = {
    text = "Rename '%s' to:",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self, data)
        local newName = TrimEnteredName(self.EditBox:GetText())
        if newName ~= "" and data then
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
    OnShow = function(self, data)
        local profile = CooldownCompanion.db.profile
        local target = data and (data.containerId and profile.groupContainers[data.containerId]
            or data.groupId and profile.groups[data.groupId])
        PrefillEditBox(self, target and target.name)
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
            CooldownCompanion:Print("Could not save the template: the panel is gone or does not support templates.")
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
            CooldownCompanion:Print(ST._GetPanelTemplateFailureText(reason))
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
    text = "Delete '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.snapshot then
            ST._DeleteEntrySelection(data.snapshot)
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
        -- PanelShared loads after this file; resolve the action on acceptance.
        ST._DeleteEntrySelection(data)
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
            local nextProfile = nil
            for _, name in ipairs(GetSortedProfiles()) do
                if name ~= data.profileName then
                    nextProfile = name
                    break
                end
            end
            db:SetProfile(nextProfile)
            db:DeleteProfile(data.profileName, true)
            -- The AceDB profile callbacks (ConfigLoader) reset config and refresh.
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
        local text = TrimEnteredName(self.EditBox:GetText())
        if text ~= "" then
            if ProfileNameExists(text) then
                CooldownCompanion:Print("A profile named '" .. text .. "' already exists.")
                return
            end
            local db = CooldownCompanion.db
            -- OnProfileChanged resets config and refreshes.
            db:SetProfile(text)
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
        local newName = TrimEnteredName(self.EditBox:GetText())
        if newName ~= "" and data and data.oldName then
            if newName ~= data.oldName and ProfileNameExists(newName) then
                CooldownCompanion:Print("A profile named '" .. newName .. "' already exists.")
                return
            end
            if newName == data.oldName then return end
            local db = CooldownCompanion.db
            -- CopyProfile errors on a source that is gone; check before the
            -- switch, so a failed copy never strands the empty new profile.
            if not rawget(db.profiles, data.oldName) then
                CooldownCompanion:Print("Profile '" .. data.oldName .. "' no longer exists.")
                return
            end
            CooldownCompanion._suppressOwnershipRestamp = true
            CooldownCompanion._profileCopyFollows = true
            db:SetProfile(newName)
            CooldownCompanion._profileCopyFollows = nil
            db:CopyProfile(data.oldName)
            CooldownCompanion._suppressOwnershipRestamp = nil
            db:DeleteProfile(data.oldName, true)
            -- The profile callbacks already reset config and refreshed.
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["CDC_RENAME_PROFILE"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    OnShow = function(self, data)
        PrefillEditBox(self, data and data.oldName)
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
        local newName = TrimEnteredName(self.EditBox:GetText())
        if newName ~= "" and data and data.source then
            if ProfileNameExists(newName) then
                CooldownCompanion:Print("A profile named '" .. newName .. "' already exists.")
                return
            end
            local db = CooldownCompanion.db
            -- CopyProfile errors on a source deleted while this popup was
            -- open; check before the switch, as Rename does.
            if not rawget(db.profiles, data.source) then
                CooldownCompanion:Print("Profile '" .. data.source .. "' no longer exists.")
                return
            end
            CooldownCompanion._suppressOwnershipRestamp = true
            CooldownCompanion._profileCopyFollows = true
            db:SetProfile(newName)
            CooldownCompanion._profileCopyFollows = nil
            db:CopyProfile(data.source)
            if StripLocalPanelMetadataFromProfile then
                StripLocalPanelMetadataFromProfile(db.profile)
            end
            CooldownCompanion._suppressOwnershipRestamp = nil
            -- OnProfileCopied already migrated and rebuilt the panels; this
            -- repaints config after the CDM-source strip.
            ResetConfigSelection(true)
            CooldownCompanion:RefreshConfigPanel()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["CDC_DUPLICATE_PROFILE"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    OnShow = function(self, data)
        PrefillEditBox(self, data and data.source and GetCopyProfileName(data.source))
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
        -- Shallow: only top-level keys are added here, and EncodeSharedPayload
        -- deep-copies before it changes anything.
        local exportData = CopyTable(db.profile, true)
        exportData._exporterCharKey = db.keys.char
        exportData._characterInfo = db.global.characterInfo
        -- Panel Templates are account-wide, so a backup carries every one.
        -- The explicit nil also drops a stray copy an older restore left in
        -- the profile.
        local templates = {}
        for _, item in ipairs(CooldownCompanion:GetPanelTemplates()) do
            templates[#templates + 1] = item.template
        end
        exportData._panelTemplates = #templates > 0 and templates or nil
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

-- Moving Groups out of Global strips other classes' limits, so the menu move
-- and both drags ask here first. The callback performs the move and owns its
-- own stale-Group check.
StaticPopupDialogs["CDC_UNGLOBAL_GROUPS"] = {
    text = "%s",
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

-- groupName names the one Group being moved; nil words it for a selection.
function ST._ShowUnglobalGroupsPopup(groupName, callback)
    local text = groupName
        and ("This removes other classes' Who Can Use This limits and moves '" .. groupName .. "' into your current class. Continue?")
        or "Some selected groups have other classes' Who Can Use This limits. Moving them to your current class removes those limits. Continue?"
    ST._ShowPopupAboveConfig("CDC_UNGLOBAL_GROUPS", text, { callback = callback })
end

StaticPopupDialogs["CDC_DELETE_SELECTED_GROUPS"] = {
    text = "%s",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.groupIds then
            for _, gid in ipairs(data.groupIds) do
                -- Ids freeze at popup-show time; DeleteContainer skips a
                -- Group deleted while the popup was open.
                CooldownCompanion:DeleteContainer(gid)
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

-- groupIds: the selected Groups, frozen for Accept.
function ST._ShowDeleteSelectedGroupsPopup(groupIds)
    local panelCount = 0
    for _, gid in ipairs(groupIds) do
        panelCount = panelCount + CooldownCompanion:GetPanelCount(gid)
    end
    local text = "Delete " .. #groupIds .. " selected groups"
        .. PanelCountClause(panelCount, "their") .. "?"
    ST._ShowPopupAboveConfig("CDC_DELETE_SELECTED_GROUPS", text, { groupIds = groupIds })
end

-- A profile change closes every open Cooldown Companion popup (all are named
-- CDC_*, in this file and elsewhere). Popups capture Group, panel, entry and
-- profile names or ids as they stood when shown, and ids repeat across
-- profiles, so an Accept after the switch would act on the new profile's
-- namesakes. A popup whose own Accept switches profile closes itself early;
-- StaticPopup's closing Hide then finds it already hidden.
function ST._HideProfileScopedPopups()
    for which in pairs(StaticPopupDialogs) do
        if type(which) == "string" and which:sub(1, 4) == "CDC_" then
            StaticPopup_Hide(which)
        end
    end
end

------------------------------------------------------------------------
-- Group export and apply
------------------------------------------------------------------------

local function GetResourceBarConflictExportBlockMessage()
    if CooldownCompanion.GetCurrentResourceBarConflictExportMessage then
        return CooldownCompanion:GetCurrentResourceBarConflictExportMessage()
    end
    return nil
end

local function BlockExportForResourceBarConflict()
    local message = GetResourceBarConflictExportBlockMessage()
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
    if type(payload) == "table" and payload.type == "setup" and payload.resources then
        local blocked = BlockExportForResourceBarConflict()
        if blocked then
            return nil
        end
    end
    return EncodeSharedPayload(payload, "entity")
end

-- Assembles the one-string setup payload from its sections (containers,
-- resources, templates). Any section may be nil.
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
    if type(sections.resources) == "table"
        and type(sections.resources.settings) == "table" then
        payload.resources = sections.resources
        hasAny = true
    end
    if type(sections.templates) == "table" and #sections.templates > 0 then
        payload.templates = sections.templates
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

local BuildRootAnchor = ST._BuildRootAnchor
local ResetIndicatorPanelAnchor = ST._ResetIndicatorPanelAnchor

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

    importState.importedGroupIds[#importState.importedGroupIds + 1] = groupId
    if srcPanel._originalGroupId then
        importState.groupIdMap[srcPanel._originalGroupId] = groupId
    end

    local panel = CopyTable(srcPanel)
    panel._originalGroupId = nil
    if panel._indicatorMigrationOriginal then
        db._indicatorMigrationBackup = db._indicatorMigrationBackup or {}
        db._indicatorMigrationBackup[groupId] = panel._indicatorMigrationOriginal
        panel._indicatorMigrationOriginal = nil
    end
    panel.cdmPanelSource = nil
    panel.parentContainerId = containerId
    panel.order = panelIndex
    -- Piece imports land in an already-migrated profile, so pre-split bar
    -- panels get their per-mode orientation key mapped here.
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
        panel.anchor = BuildRootAnchor("CooldownCompanionContainer" .. containerId)
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

        -- An empty Group arrives empty, as the import review shows it.
        for panelIndex, srcPanel in ipairs(entry.panels or {}) do
            CreateImportedPanel(db, containerId, panelIndex, srcPanel, importState)
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
                    container.anchor = BuildRootAnchor()
                    AnchorImportedContainerFrame(newId, container.anchor)
                else
                    local refOldId = tonumber(rt:match("^CooldownCompanionContainer(%d+)$"))
                    if refOldId then
                        local remappedId = preserveContainerRefs and importState.containerIdMap[refOldId] or nil
                        if remappedId then
                            container.anchor.relativeTo = "CooldownCompanionContainer" .. remappedId
                        else
                            container.anchor = BuildRootAnchor()
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
                                container.anchor = BuildRootAnchor()
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

local function RemapImportedIndicatorAnchor(panel, newGroupId, importState)
    local settings = CooldownCompanion:GetIndicatorAnchorSettings(panel)
    local relativeTo = type(settings) == "table" and settings.relativeTo or nil
    if not relativeTo or relativeTo == "UIParent" then
        return
    end
    if type(relativeTo) ~= "string" then
        ResetIndicatorPanelAnchor(panel)
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
            ResetIndicatorPanelAnchor(panel)
        end
        return
    end
    if containerRef then
        local targetContainerId = importState.containerIdMap[containerRef]
        if targetContainerId then
            settings.relativeTo = "CooldownCompanionContainer" .. tostring(targetContainerId)
        else
            ResetIndicatorPanelAnchor(panel)
        end
        return
    end
    if relativeTo:find("^CooldownCompanion") then
        ResetIndicatorPanelAnchor(panel)
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
                        panel.anchor = BuildRootAnchor("CooldownCompanionContainer" .. panel.parentContainerId)
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
                            panel.anchor = BuildRootAnchor("CooldownCompanionContainer" .. panel.parentContainerId)
                        end
                    end
                end
            end
        end
        RemapImportedIndicatorAnchor(panel, newGid, importState)
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
    if ST._FilterConvertedPanelImport then data = ST._FilterConvertedPanelImport(data) end
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

    -- Rebuild the live frames even when the migration failed: the groups
    -- above are already written and there is no rollback, so returning early
    -- would only leave them describing a profile that no longer exists. The
    -- failure is reported by RunPostImportMigrations and carried out in the
    -- return value. The config repaint belongs to the import door
    -- (ImportMode's ApplyImportModeReview), which repaints once per click.
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
local function BlockImportForResourceBarConflict(classKey)
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
        .. " before importing. Choose the setup to keep, then import again."
    CooldownCompanion:Print(message)
    if ST._ShowResourceBarConflictChooser then
        ST._ShowResourceBarConflictChooser(classKey, { force = true })
    end
    return true
end

-- LEGACY CONVERSION ONLY: a standalone Custom Bars export string. Custom Bars
-- no longer exist; the payload is converted into panel entries and applied as
-- an ordinary group import. Kept for parked legacy stores in profile import.
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
    local converted, report = ST._ConvertUnifiedPanelImport(data)
    if not converted then CooldownCompanion:Print(report); return false end
    return ApplyGroupImportData(ST._FilterConvertedPanelImport(converted), options)
end

-- Class identity of any class-tagged payload or setup section (setup
-- sections, and legacy standalone Custom Bars payloads, tagged the same way).
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
ST._GetSetupSectionClassKey = GetSetupSectionClassKey

-- Applies a `setup` payload: groups additively, then the Resources section as
-- a whole-bucket replace for its class, then any Panel Templates beside the
-- player's own. Legacy Custom Bars sections were
-- converted into panel entries by _ConvertUnifiedPanelImport above. Order
-- matters: groups first so the Resources anchor can remap
-- onto the groups imported from the same string.
local function ApplySetupImportData(data, existingPanelIds)
    if type(data) ~= "table" or data.type ~= "setup" then
        CooldownCompanion:Print("Import failed: this is not a setup export.")
        return false
    end
    if RejectUnsupportedImportPayload(data, "setup import") then
        return false
    end

    local converted, conversionError = ST._ConvertUnifiedPanelImport(data)
    if not converted then CooldownCompanion:Print(conversionError); return false end
    local replayPanelIds
    data, replayPanelIds = ST._FilterConvertedPanelImport(converted)

    local hasContainers = type(data.containers) == "table" and #data.containers > 0
    local resourcesSection = type(data.resources) == "table"
        and type(data.resources.settings) == "table"
        and data.resources
        or nil
    local templatesSection = type(data.templates) == "table" and #data.templates > 0 and data.templates or nil
    if not hasContainers and not resourcesSection and not templatesSection then
        CooldownCompanion:Print("Import failed: this setup export is empty.")
        return false
    end

    local resourcesClassKey = resourcesSection and GetSetupSectionClassKey(resourcesSection) or nil
    if resourcesSection and not resourcesClassKey then
        CooldownCompanion:Print("Import failed: the Resources setup does not name its class.")
        return false
    end

    if resourcesClassKey and BlockImportForResourceBarConflict(resourcesClassKey) then
        return false
    end

    local batchToken = ST._BeginGroupImportBatch()
    local applied = false
    local failed = false
    local containersApplied = false

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
    local attachmentPanelIds = {}
    for sourceId, targetId in pairs(existingPanelIds or {}) do
        if CooldownCompanion.db.profile.groups[targetId] then attachmentPanelIds[sourceId] = targetId end
    end
    for sourceId, targetId in pairs(replayPanelIds or {}) do attachmentPanelIds[sourceId] = targetId end
    -- A partially deduplicated panel is still newly imported. Its new ID
    -- takes precedence over any earlier review-time match.
    for sourceId, targetId in pairs(importState and importState.groupIdMap or {}) do
        attachmentPanelIds[sourceId] = targetId
    end

    if resourcesSection then
        local settings = CopyTable(resourcesSection.settings)
        CooldownCompanion:RemapModuleAttachmentPanels(settings, "resources", attachmentPanelIds)
        local anchorId = tonumber(settings.anchorGroupId)
        if anchorId then
            -- The exporter's group ids mean nothing here; keep the anchor only
            -- when it remaps onto a group imported from this same string.
            settings.anchorGroupId = attachmentPanelIds[anchorId]
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

    -- Account-wide, so outside the batch and the profile migration run.
    local templatesApplied = false
    if templatesSection then
        CooldownCompanion:ImportPanelTemplates(templatesSection)
        templatesApplied = true
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

    -- Rebuild resource bars after the migration: the Resources section
    -- deferred its migration to this function.
    if resourcesSection then
        CooldownCompanion:ApplyResourceBars()
    end

    applied = applied or templatesApplied
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

ST._BlockImportForResourceBarConflict = BlockImportForResourceBarConflict
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
    CooldownCompanion:RefreshConfigPanel()
end

StaticPopupDialogs["CDC_CONFIRM_RESOURCE_SPEC_COPY"] = {
    text = "Copy Resource Bar settings from %s?\n\nThis copies Appearance, Layout, resource colors, and Resource Settings into the current spec. If that spec is using defaults, those default values are copied. Health settings are not copied.",
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
