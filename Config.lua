--[[
    CooldownCompanion - Config
    Custom 3-column config panel using AceGUI-3.0 Frame + InlineGroup columns
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local AceGUI = LibStub("AceGUI-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")

-- Selection state
local selectedGroup = nil
local selectedButton = nil
local selectedButtons = {}  -- set of indices for multi-select (ctrl+click)
local selectedTab = "appearance"
local newInput = ""

-- Main frame reference
local configFrame = nil

-- Column content frames (for refresh)
local col1Scroll = nil  -- AceGUI ScrollFrame
local col1ButtonBar = nil -- Static bar at bottom of column 1
local col2Scroll = nil  -- AceGUI ScrollFrame
local col3Container = nil

-- AceGUI widget tracking for cleanup
local col1BarWidgets = {}
local profileBarAceWidgets = {}
local col2InfoButtons = {}
local columnInfoButtons = {}
local moveMenuFrame = nil

-- Drag-reorder state
local dragState = nil
local dragIndicator = nil
local dragTracker = nil
local DRAG_THRESHOLD = 8

-- Pending strata order state (survives panel rebuilds, resets on group change)
local pendingStrataOrder = nil
local pendingStrataGroup = nil

-- Pick-frame overlay state
local pickFrameOverlay = nil
local pickFrameCallback = nil

-- Font options for dropdown
local fontOptions = {
    ["Fonts\\FRIZQT__.TTF"] = "Friz Quadrata (Default)",
    ["Fonts\\ARIALN.TTF"] = "Arial Narrow",
    ["Fonts\\MORPHEUS.TTF"] = "Morpheus",
    ["Fonts\\SKURRI.TTF"] = "Skurri",
    ["Fonts\\2002.TTF"] = "2002",
    ["Fonts\\NIMROD.TTF"] = "Nimrod",
}

local outlineOptions = {
    [""] = "None",
    ["OUTLINE"] = "Outline",
    ["THICKOUTLINE"] = "Thick Outline",
    ["MONOCHROME"] = "Monochrome",
}

-- Strata ordering element definitions
local strataElementLabels = {
    cooldown = "Cooldown Swipe",
    chargeText = "Charge Text",
    procGlow = "Proc Glow",
    assistedHighlight = "Assisted Highlight",
}
local strataElementKeys = {"cooldown", "chargeText", "procGlow", "assistedHighlight"}

local function IsStrataOrderComplete(order)
    if not order then return false end
    for i = 1, 4 do
        if not order[i] then return false end
    end
    return true
end

local function InitPendingStrataOrder(groupId)
    if pendingStrataGroup == groupId and pendingStrataOrder then return end
    pendingStrataGroup = groupId
    local groups = CooldownCompanion.db.profile.groups
    local group = groups[groupId]
    local saved = group and group.style and group.style.strataOrder
    if saved and IsStrataOrderComplete(saved) then
        pendingStrataOrder = {}
        for i = 1, 4 do
            pendingStrataOrder[i] = saved[i]
        end
    else
        pendingStrataOrder = {}
        for i = 1, 4 do
            pendingStrataOrder[i] = ST.DEFAULT_STRATA_ORDER[i]
        end
    end
end

local anchorPoints = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

local anchorPointLabels = {
    TOPLEFT = "Top Left",
    TOP = "Top",
    TOPRIGHT = "Top Right",
    LEFT = "Left",
    CENTER = "Center",
    RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left",
    BOTTOM = "Bottom",
    BOTTOMRIGHT = "Bottom Right",
}

-- Layout constants
local COLUMN_PADDING = 8
local BUTTON_HEIGHT = 24
local BUTTON_SPACING = 2
local PROFILE_BAR_HEIGHT = 36

-- Static popup for delete confirmations
StaticPopupDialogs["CDC_DELETE_GROUP"] = {
    text = "Are you sure you want to delete group '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.groupId then
            CooldownCompanion:DeleteGroup(data.groupId)
            if selectedGroup == data.groupId then
                selectedGroup = nil
                selectedButton = nil
                wipe(selectedButtons)
            end
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
            selectedButton = nil
            wipe(selectedButtons)
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
            selectedButton = nil
            wipe(selectedButtons)
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
            selectedGroup = nil
            selectedButton = nil
            wipe(selectedButtons)
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
            selectedGroup = nil
            selectedButton = nil
            wipe(selectedButtons)
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
            selectedGroup = nil
            selectedButton = nil
            wipe(selectedButtons)
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
            selectedGroup = nil
            selectedButton = nil
            wipe(selectedButtons)
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
            selectedGroup = nil
            selectedButton = nil
            wipe(selectedButtons)
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
        self.EditBox:SetText(serialized)
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
            local success, data = AceSerializer:Deserialize(text)
            if success and type(data) == "table" then
                local db = CooldownCompanion.db
                -- Deep-copy imported data into current profile
                for k, v in pairs(data) do
                    db.profile[k] = v
                end
                selectedGroup = nil
                selectedButton = nil
                wipe(selectedButtons)
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

------------------------------------------------------------------------
-- Helper: Show a StaticPopup above the config panel
------------------------------------------------------------------------
local function ShowPopupAboveConfig(which, text_arg1, data)
    local dialog = StaticPopup_Show(which, text_arg1)
    if dialog then
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(200)
        if data then
            dialog.data = data
        end
    end
    return dialog
end

------------------------------------------------------------------------
-- Helper: Resolve named frame from mouse focus
------------------------------------------------------------------------
local function ResolveNamedFrame(frame)
    while frame do
        if frame.IsForbidden and frame:IsForbidden() then
            return nil, nil
        end
        local name = frame:GetName()
        if name and name ~= "" then
            return frame, name
        end
        frame = frame:GetParent()
    end
    return nil, nil
end

------------------------------------------------------------------------
-- Helper: Check if frame name belongs to this addon (should be excluded)
------------------------------------------------------------------------
local function IsAddonFrame(name)
    if not name then return true end
    if name:find("^CooldownCompanion") then return true end
    if name == "WorldFrame" then return true end
    -- Exclude the config panel itself (AceGUI frames)
    if configFrame and configFrame.frame and configFrame.frame:GetName() == name then return true end
    return false
end

------------------------------------------------------------------------
-- Helper: Start pick-frame mode
------------------------------------------------------------------------
local function FinishPickFrame(name)
    if not pickFrameOverlay then return end
    pickFrameOverlay:Hide()
    local cb = pickFrameCallback
    pickFrameCallback = nil
    if cb then
        cb(name)
    end
end

local function StartPickFrame(callback)
    pickFrameCallback = callback

    -- Create overlay lazily
    if not pickFrameOverlay then
        -- Visual-only overlay: EnableMouse(false) so GetMouseFoci sees through it
        local overlay = CreateFrame("Frame", "CooldownCompanionPickOverlay", UIParent)
        overlay:SetFrameStrata("FULLSCREEN_DIALOG")
        overlay:SetFrameLevel(100)
        overlay:SetAllPoints(UIParent)
        overlay:EnableMouse(false)
        overlay:EnableKeyboard(true)

        -- Semi-transparent dark background
        local bg = overlay:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.3)
        overlay.bg = bg

        -- Instruction text at top
        local instructions = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        instructions:SetPoint("TOP", overlay, "TOP", 0, -30)
        instructions:SetText("Click a frame to anchor  |  Right-click or Escape to cancel")
        instructions:SetTextColor(1, 1, 1, 0.9)
        overlay.instructions = instructions

        -- Cursor-following label showing frame name
        local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        label:SetTextColor(0.2, 1, 0.2, 1)
        overlay.label = label

        -- Highlight frame (colored border that outlines hovered frame)
        local highlight = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
        highlight:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
        })
        highlight:SetBackdropBorderColor(0, 1, 0, 0.9)
        highlight:Hide()
        overlay.highlight = highlight

        -- OnUpdate: detect frame under cursor (overlay is mouse-transparent)
        overlay:SetScript("OnUpdate", function(self)
            local foci = GetMouseFoci()
            local focus = foci and foci[1]

            if not focus or focus == WorldFrame then
                self.label:SetText("")
                self.highlight:Hide()
                self.currentName = nil
                return
            end

            local resolvedFrame, name = ResolveNamedFrame(focus)
            if not name or IsAddonFrame(name) then
                self.label:SetText("")
                self.highlight:Hide()
                self.currentName = nil
                return
            end

            self.currentName = name

            -- Position label near cursor
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            self.label:ClearAllPoints()
            self.label:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx + 20, cy + 10)
            self.label:SetText(name)

            -- Position highlight around the resolved frame
            local left, bottom, width, height = resolvedFrame:GetRect()
            if left and width and width > 0 and height > 0 then
                self.highlight:ClearAllPoints()
                self.highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
                self.highlight:SetSize(width, height)
                self.highlight:Show()
            else
                self.highlight:Hide()
            end
        end)

        -- Detect clicks via GLOBAL_MOUSE_DOWN (overlay is mouse-transparent)
        overlay:RegisterEvent("GLOBAL_MOUSE_DOWN")
        overlay:SetScript("OnEvent", function(self, event, button)
            if event ~= "GLOBAL_MOUSE_DOWN" then return end
            if button == "LeftButton" then
                FinishPickFrame(self.currentName)
            elseif button == "RightButton" then
                FinishPickFrame(nil)
            end
        end)

        -- Escape to cancel
        overlay:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                FinishPickFrame(nil)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        overlay:SetScript("OnHide", function(self)
            self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        end)

        overlay:SetScript("OnShow", function(self)
            self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        end)

        pickFrameOverlay = overlay
    end

    -- Hide config panel, show overlay
    if configFrame and configFrame.frame:IsShown() then
        configFrame.frame:Hide()
    end
    pickFrameOverlay.currentName = nil
    pickFrameOverlay.label:SetText("")
    pickFrameOverlay.highlight:Hide()
    pickFrameOverlay:Show()
end

------------------------------------------------------------------------
-- Helper: Add spell to selected group
------------------------------------------------------------------------
local function TryAddSpell(input)
    if input == "" or not selectedGroup then return false end

    local spellId = tonumber(input)
    local spellName

    if spellId then
        local info = C_Spell.GetSpellInfo(spellId)
        spellName = info and info.name
    else
        local info = C_Spell.GetSpellInfo(input)
        if info then
            spellId = info.spellID
            spellName = info.name
        else
            -- Name lookup failed (spell may not be known); search talent tree
            spellId, spellName = CooldownCompanion:FindTalentSpellByName(input)
        end
    end

    if spellId and spellName then
        if C_Spell.IsSpellPassive(spellId) then
            CooldownCompanion:Print("Cannot track passive spell: " .. spellName)
            return false
        end
        CooldownCompanion:AddButtonToGroup(selectedGroup, "spell", spellId, spellName)
        CooldownCompanion:Print("Added spell: " .. spellName)
        return true
    else
        CooldownCompanion:Print("Spell not found: " .. input .. ". Try using the spell ID or drag from spellbook.")
        return false
    end
end

------------------------------------------------------------------------
-- Helper: Add item to selected group
------------------------------------------------------------------------
local function FinalizeAddItem(itemId, groupId)
    local itemName = C_Item.GetItemNameByID(itemId) or "Unknown Item"
    local spellName = C_Item.GetItemSpell(itemId)
    if not spellName then
        CooldownCompanion:Print("Item has no usable effect: " .. itemName)
        return false
    end
    CooldownCompanion:AddButtonToGroup(groupId, "item", itemId, itemName)
    CooldownCompanion:Print("Added item: " .. itemName)
    return true
end

local function TryAddItem(input)
    if input == "" or not selectedGroup then return false end

    local itemId = tonumber(input)
    local itemName

    if itemId then
        itemName = C_Item.GetItemNameByID(itemId)
    else
        itemName = input
        itemId = C_Item.GetItemIDForItemInfo(input)
    end

    if not itemId then
        CooldownCompanion:Print("Item not found: " .. input)
        return false
    end

    if C_Item.IsItemDataCachedByID(itemId) then
        return FinalizeAddItem(itemId, selectedGroup)
    end

    -- Only do async loading for ID-based input (not name-based).
    -- Name lookups that aren't cached are almost certainly invalid items.
    if not tonumber(input) then
        CooldownCompanion:Print("Item not found: " .. input)
        return false
    end

    -- Item data not cached yet — request it and wait for callback.
    -- Cancel any pending item load listener before registering a new one.
    if CooldownCompanion.pendingItemLoad then
        CooldownCompanion:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
        CooldownCompanion.pendingItemLoad = nil
    end
    local capturedGroup = selectedGroup
    CooldownCompanion.pendingItemLoad = itemId
    CooldownCompanion:Print("Loading item data...")
    C_Item.RequestLoadItemDataByID(itemId)
    CooldownCompanion:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, loadedItemId, success)
        if loadedItemId ~= CooldownCompanion.pendingItemLoad then return end
        CooldownCompanion:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
        CooldownCompanion.pendingItemLoad = nil
        if not success then
            CooldownCompanion:Print("Item not found: " .. input)
            return
        end
        if FinalizeAddItem(itemId, capturedGroup) then
            CooldownCompanion:RefreshConfigPanel()
        end
    end)
    return false
end

------------------------------------------------------------------------
-- Unified add: resolve input as spell or item automatically
------------------------------------------------------------------------
local function TryAdd(input)
    if input == "" or not selectedGroup then return false end

    local id = tonumber(input)

    if id then
        -- ID-based input: check both spell and item
        local spellInfo = C_Spell.GetSpellInfo(id)
        local spellFound = spellInfo and spellInfo.name
        local isPassive = spellFound and C_Spell.IsSpellPassive(id)

        -- Non-passive spell → add it
        if spellFound and not isPassive then
            CooldownCompanion:AddButtonToGroup(selectedGroup, "spell", id, spellInfo.name)
            CooldownCompanion:Print("Added spell: " .. spellInfo.name)
            return true
        end

        -- Try as item
        local itemName = C_Item.GetItemNameByID(id)
        local itemId = C_Item.GetItemIDForItemInfo(id)
        if itemId then
            if C_Item.IsItemDataCachedByID(itemId) then
                local result = FinalizeAddItem(itemId, selectedGroup)
                if result then return true end
                -- Item had no use effect; if spell was passive, report that
                if isPassive then
                    CooldownCompanion:Print("Cannot track passive spell: " .. spellInfo.name)
                    return false
                end
                -- FinalizeAddItem already printed "no usable effect"
                return false
            end
            -- Item not cached — request async load
            if CooldownCompanion.pendingItemLoad then
                CooldownCompanion:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
                CooldownCompanion.pendingItemLoad = nil
            end
            local capturedGroup = selectedGroup
            CooldownCompanion.pendingItemLoad = itemId
            CooldownCompanion:Print("Loading item data...")
            C_Item.RequestLoadItemDataByID(itemId)
            CooldownCompanion:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, loadedItemId, success)
                if loadedItemId ~= CooldownCompanion.pendingItemLoad then return end
                CooldownCompanion:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
                CooldownCompanion.pendingItemLoad = nil
                if not success then
                    if isPassive then
                        CooldownCompanion:Print("Cannot track passive spell: " .. spellInfo.name)
                    else
                        CooldownCompanion:Print("Not found: " .. input)
                    end
                    return
                end
                if FinalizeAddItem(itemId, capturedGroup) then
                    CooldownCompanion:RefreshConfigPanel()
                elseif isPassive then
                    CooldownCompanion:Print("Cannot track passive spell: " .. spellInfo.name)
                end
            end)
            return false
        end

        -- No item match
        if isPassive then
            CooldownCompanion:Print("Cannot track passive spell: " .. spellInfo.name)
            return false
        end

        CooldownCompanion:Print("Not found: " .. input)
        return false
    else
        -- Name-based input: try spell first, then item
        local spellInfo = C_Spell.GetSpellInfo(input)
        local spellId, spellName
        if spellInfo then
            spellId = spellInfo.spellID
            spellName = spellInfo.name
        else
            spellId, spellName = CooldownCompanion:FindTalentSpellByName(input)
        end

        if spellId and spellName and not C_Spell.IsSpellPassive(spellId) then
            CooldownCompanion:AddButtonToGroup(selectedGroup, "spell", spellId, spellName)
            CooldownCompanion:Print("Added spell: " .. spellName)
            return true
        end

        -- Try as item
        local itemId = C_Item.GetItemIDForItemInfo(input)
        if itemId and C_Item.IsItemDataCachedByID(itemId) then
            return FinalizeAddItem(itemId, selectedGroup)
        end

        -- Passive spell, no item match
        if spellId and spellName then
            CooldownCompanion:Print("Cannot track passive spell: " .. spellName)
            return false
        end

        CooldownCompanion:Print("Not found: " .. input .. ". Try using the spell ID or drag from spellbook.")
        return false
    end
end

------------------------------------------------------------------------
-- Helper: Receive a spell/item drop from the cursor
------------------------------------------------------------------------
local function TryReceiveCursorDrop()
    local cursorType, cursorID, _, cursorSpellID = GetCursorInfo()
    if not cursorType then return false end

    if not selectedGroup then
        CooldownCompanion:Print("Select a group first before dropping spells or items.")
        ClearCursor()
        return false
    end

    local added = false
    if cursorType == "spell" and cursorSpellID then
        added = TryAddSpell(tostring(cursorSpellID))
    elseif cursorType == "item" and cursorID then
        added = TryAddItem(tostring(cursorID))
    end

    if added then
        ClearCursor()
        CooldownCompanion:RefreshConfigPanel()
    end
    return added
end

------------------------------------------------------------------------
-- Helper: Get icon for a button data entry
------------------------------------------------------------------------
local function GetButtonIcon(buttonData)
    if buttonData.type == "spell" then
        return C_Spell.GetSpellTexture(buttonData.id) or 134400
    elseif buttonData.type == "item" then
        return C_Item.GetItemIconByID(buttonData.id) or 134400
    end
    return 134400
end

------------------------------------------------------------------------
-- Helper: Create a scroll frame inside a parent
------------------------------------------------------------------------
local function CreateScrollFrame(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1) -- will be set dynamically
    scrollFrame:SetScrollChild(scrollChild)

    -- Update child width on resize
    scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        scrollChild:SetWidth(w)
    end)

    return scrollFrame, scrollChild
end


------------------------------------------------------------------------
-- Helper: Create a text button
------------------------------------------------------------------------
local function CreateTextButton(parent, text, width, height, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)

    btn:RegisterForClicks("AnyUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and onClick then
            onClick(self)
        end
    end)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.3, 0.3, 0.9)
    end)
    btn:SetScript("OnLeave", function(self)
        if self.isSelected then
            self:SetBackdropColor(0.15, 0.4, 0.15, 0.9)
        else
            self:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
        end
    end)

    return btn
end


------------------------------------------------------------------------
-- Helper: Embed an AceGUI widget into a raw frame
------------------------------------------------------------------------
local function EmbedWidget(widget, parent, x, y, width, widgetList)
    widget.frame:SetParent(parent)
    widget.frame:ClearAllPoints()
    widget.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then widget:SetWidth(width) end
    widget.frame:Show()
    if widgetList then
        table.insert(widgetList, widget)
    end
    return widget
end

------------------------------------------------------------------------
-- Drag-reorder helpers
------------------------------------------------------------------------

local function GetDragIndicator()
    if not dragIndicator then
        dragIndicator = CreateFrame("Frame", nil, UIParent)
        dragIndicator:SetFrameStrata("TOOLTIP")
        dragIndicator:SetSize(10, 2)
        local tex = dragIndicator:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetColorTexture(0.2, 0.6, 1.0, 1.0)
        dragIndicator.tex = tex
        dragIndicator:Hide()
    end
    return dragIndicator
end

local function HideDragIndicator()
    if dragIndicator then dragIndicator:Hide() end
end

local function GetScaledCursorPosition(scrollWidget)
    local _, cursorY = GetCursorPosition()
    local scale = scrollWidget.frame:GetEffectiveScale()
    cursorY = cursorY / scale
    return cursorY
end

local function GetDropIndex(scrollWidget, cursorY, childOffset, totalDraggable)
    -- childOffset: number of non-draggable children at the start of the scroll (e.g. input box, buttons, separator)
    -- Iterate draggable children and compare cursor Y to midpoints
    local children = { scrollWidget.content:GetChildren() }
    local dropIndex = totalDraggable + 1  -- default: after last
    local anchorFrame = nil
    local anchorAbove = true

    for ci = 1, totalDraggable do
        local child = children[ci + childOffset]
        if child and child:IsShown() then
            local top = child:GetTop()
            local bottom = child:GetBottom()
            if top and bottom then
                local mid = (top + bottom) / 2
                if cursorY > mid then
                    dropIndex = ci
                    anchorFrame = child
                    anchorAbove = true
                    break
                end
                -- Track the last child we passed as potential "below" anchor
                anchorFrame = child
                anchorAbove = false
                dropIndex = ci + 1
            end
        end
    end

    return dropIndex, anchorFrame, anchorAbove
end

local function ShowDragIndicator(anchorFrame, anchorAbove, parentScrollWidget)
    if not anchorFrame then
        HideDragIndicator()
        return
    end
    local ind = GetDragIndicator()
    local width = parentScrollWidget.content:GetWidth() or 100
    ind:SetWidth(width)
    ind:ClearAllPoints()
    if anchorAbove then
        ind:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 1)
    else
        ind:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -1)
    end
    ind:Show()
end

local function PerformGroupReorder(sourceIndex, dropIndex, groupIds)
    if dropIndex > sourceIndex then dropIndex = dropIndex - 1 end
    if sourceIndex == dropIndex then return end
    local db = CooldownCompanion.db.profile
    local id = table.remove(groupIds, sourceIndex)
    table.insert(groupIds, dropIndex, id)
    -- Reassign .order based on new list position
    for i, gid in ipairs(groupIds) do
        db.groups[gid].order = i
    end
end

local function PerformButtonReorder(groupId, sourceIndex, dropIndex)
    if dropIndex > sourceIndex then dropIndex = dropIndex - 1 end
    if sourceIndex == dropIndex then return end
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not group then return end
    local entry = table.remove(group.buttons, sourceIndex)
    table.insert(group.buttons, dropIndex, entry)
    -- Track selectedButton
    if selectedButton == sourceIndex then
        selectedButton = dropIndex
    elseif selectedButton then
        -- Adjust if the move shifted the selected index
        if sourceIndex < selectedButton and dropIndex >= selectedButton then
            selectedButton = selectedButton - 1
        elseif sourceIndex > selectedButton and dropIndex <= selectedButton then
            selectedButton = selectedButton + 1
        end
    end
end

local function CancelDrag()
    if dragState then
        if dragState.widget then
            dragState.widget.frame:SetAlpha(1)
        end
    end
    dragState = nil
    HideDragIndicator()
    if dragTracker then
        dragTracker:SetScript("OnUpdate", nil)
    end
end

local function FinishDrag()
    if not dragState or dragState.phase ~= "active" then
        CancelDrag()
        return
    end
    local state = dragState
    CancelDrag()
    if state.kind == "group" then
        PerformGroupReorder(state.sourceIndex, state.dropIndex or state.sourceIndex, state.groupIds)
        CooldownCompanion:RefreshConfigPanel()
    elseif state.kind == "button" then
        PerformButtonReorder(state.groupId, state.sourceIndex, state.dropIndex or state.sourceIndex)
        CooldownCompanion:RefreshGroupFrame(state.groupId)
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function StartDragTracking()
    if not dragTracker then
        dragTracker = CreateFrame("Frame", nil, UIParent)
    end
    dragTracker:SetScript("OnUpdate", function()
        if not dragState then
            dragTracker:SetScript("OnUpdate", nil)
            return
        end
        if not IsMouseButtonDown("LeftButton") then
            -- Mouse released
            if dragState.phase == "active" then
                FinishDrag()
            else
                -- Was just a click, not a drag — clear state
                CancelDrag()
            end
            return
        end
        local cursorY = GetScaledCursorPosition(dragState.scrollWidget)
        if dragState.phase == "pending" then
            if math.abs(cursorY - dragState.startY) > DRAG_THRESHOLD then
                dragState.phase = "active"
                if dragState.widget then
                    dragState.widget.frame:SetAlpha(0.4)
                end
            end
        end
        if dragState.phase == "active" then
            local dropIndex, anchorFrame, anchorAbove = GetDropIndex(
                dragState.scrollWidget, cursorY,
                dragState.childOffset or 0,
                dragState.totalDraggable
            )
            dragState.dropIndex = dropIndex
            ShowDragIndicator(anchorFrame, anchorAbove, dragState.scrollWidget)
        end
    end)
end

------------------------------------------------------------------------
-- Forward declarations for refresh functions
------------------------------------------------------------------------
local RefreshColumn1, RefreshColumn2, RefreshColumn3, RefreshProfileBar

------------------------------------------------------------------------
-- Spec Filter (inline expansion in group list)
------------------------------------------------------------------------
local specExpandedGroupId

------------------------------------------------------------------------
-- COLUMN 1: Groups
------------------------------------------------------------------------
function RefreshColumn1()
    if not col1Scroll then return end
    CancelDrag()
    col1Scroll:ReleaseChildren()

    local db = CooldownCompanion.db.profile

    -- Sort group IDs by order field (fallback to groupId)
    local groupIds = {}
    for id in pairs(db.groups) do
        table.insert(groupIds, id)
    end
    table.sort(groupIds, function(a, b)
        local orderA = db.groups[a].order or a
        local orderB = db.groups[b].order or b
        return orderA < orderB
    end)

    for listIndex, groupId in ipairs(groupIds) do
        local group = db.groups[groupId]
        if group then
            local btn = AceGUI:Create("Button")

            -- Build label with spec icons and status indicators
            local specIcons = ""
            if group.specs and next(group.specs) then
                local icons = {}
                for specId in pairs(group.specs) do
                    local _, _, _, icon = GetSpecializationInfoForSpecID(specId)
                    if icon then
                        table.insert(icons, "|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t")
                    end
                end
                if #icons > 0 then
                    specIcons = table.concat(icons, " ") .. " "
                end
            end
            local label = specIcons .. group.name
            local indicators = {}
            if group.enabled == false then
                table.insert(indicators, "|cff888888OFF|r")
            end
            if not group.locked then
                table.insert(indicators, "|cffdddd00U|r")
            end
            if #indicators > 0 then
                label = label .. " " .. table.concat(indicators, " ")
            end
            if selectedGroup == groupId then
                btn:SetText("|cff00ff00[ " .. label .. " ]|r")
            else
                btn:SetText(label)
            end

            btn:SetFullWidth(true)
            btn.frame:RegisterForClicks("AnyUp")
            btn:SetCallback("OnClick", function(widget, event, mouseButton)
                -- Suppress click if a drag just finished
                if dragState and dragState.phase == "active" then return end
                if IsShiftKeyDown() then
                    if mouseButton == "LeftButton" then
                        if specExpandedGroupId == groupId then
                            specExpandedGroupId = nil
                        else
                            specExpandedGroupId = groupId
                        end
                        CooldownCompanion:RefreshConfigPanel()
                    elseif mouseButton == "MiddleButton" then
                        group.enabled = not (group.enabled ~= false)
                        CooldownCompanion:RefreshGroupFrame(groupId)
                        CooldownCompanion:RefreshConfigPanel()
                    end
                    return
                end
                if mouseButton == "RightButton" then
                    ShowPopupAboveConfig("CDC_RENAME_GROUP", group.name, { groupId = groupId })
                    return
                end
                if mouseButton == "MiddleButton" then
                    group.locked = not group.locked
                    CooldownCompanion:RefreshGroupFrame(groupId)
                    CooldownCompanion:RefreshConfigPanel()
                    return
                end
                if selectedGroup == groupId then
                    selectedGroup = nil
                else
                    selectedGroup = groupId
                end
                selectedButton = nil
                wipe(selectedButtons)
                CooldownCompanion:RefreshConfigPanel()
            end)

            local row = AceGUI:Create("SimpleGroup")
            row:SetFullWidth(true)
            row:SetLayout("Flow")
            row:AddChild(btn)
            col1Scroll:AddChild(row)

            -- Inline spec filter panel (expanded via Shift+Left-click)
            if specExpandedGroupId == groupId then
                local numSpecs = GetNumSpecializations()
                for i = 1, numSpecs do
                    local specId, name, _, icon = GetSpecializationInfo(i)
                    local cb = AceGUI:Create("CheckBox")
                    cb:SetLabel(name)
                    cb:SetImage(icon, 0.08, 0.92, 0.08, 0.92)
                    cb:SetFullWidth(true)
                    cb:SetValue(group.specs and group.specs[specId] or false)
                    cb:SetCallback("OnValueChanged", function(widget, event, value)
                        if value then
                            if not group.specs then group.specs = {} end
                            group.specs[specId] = true
                        else
                            if group.specs then
                                group.specs[specId] = nil
                                if not next(group.specs) then
                                    group.specs = nil
                                end
                            end
                        end
                        CooldownCompanion:RefreshGroupFrame(groupId)
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    col1Scroll:AddChild(cb)
                end
                local clearBtn = AceGUI:Create("Button")
                clearBtn:SetText("Clear All")
                clearBtn:SetFullWidth(true)
                clearBtn:SetCallback("OnClick", function()
                    group.specs = nil
                    CooldownCompanion:RefreshGroupFrame(groupId)
                    CooldownCompanion:RefreshConfigPanel()
                end)
                col1Scroll:AddChild(clearBtn)
            end

            -- Hold-click drag reorder via handler-table HookScript pattern
            -- Hook btn.frame (not row.frame) because the Button captures mouse events
            local btnFrame = btn.frame
            if not btnFrame._cdcDragHooked then
                btnFrame._cdcDragHooked = true
                btnFrame:HookScript("OnMouseDown", function(self, mouseBtn)
                    if self._cdcOnMouseDown then self._cdcOnMouseDown(self, mouseBtn) end
                end)
            end
            btnFrame._cdcOnMouseDown = function(self, button)
                if button == "LeftButton" and not IsShiftKeyDown() then
                    local cursorY = GetScaledCursorPosition(col1Scroll)
                    dragState = {
                        kind = "group",
                        phase = "pending",
                        sourceIndex = listIndex,
                        groupIds = groupIds,
                        scrollWidget = col1Scroll,
                        widget = row,
                        startY = cursorY,
                        childOffset = 0,
                        totalDraggable = #groupIds,
                    }
                    StartDragTracking()
                end
            end
        end
    end

    -- Refresh the static button bar at the bottom
    if col1ButtonBar then
        -- Release previous bar widgets
        for _, widget in ipairs(col1BarWidgets) do
            widget:Release()
        end
        wipe(col1BarWidgets)

        -- "New" button (left half)
        local newBtn = AceGUI:Create("Button")
        newBtn:SetText("New")
        newBtn:SetCallback("OnClick", function()
            -- Generate a unique "New Group" name
            local db = CooldownCompanion.db.profile
            local existing = {}
            for _, g in pairs(db.groups) do
                existing[g.name] = true
            end
            local name = "New Group"
            if existing[name] then
                local n = 1
                while existing[name .. " " .. n] do
                    n = n + 1
                end
                name = name .. " " .. n
            end
            local groupId = CooldownCompanion:CreateGroup(name)
            selectedGroup = groupId
            selectedButton = nil
            wipe(selectedButtons)
            CooldownCompanion:RefreshConfigPanel()
        end)
        newBtn.frame:SetParent(col1ButtonBar)
        newBtn.frame:ClearAllPoints()
        newBtn.frame:SetPoint("TOPLEFT", col1ButtonBar, "TOPLEFT", 0, 0)
        newBtn.frame:SetPoint("BOTTOMRIGHT", col1ButtonBar, "BOTTOM", -2, 0)
        newBtn.frame:Show()
        table.insert(col1BarWidgets, newBtn)

        -- "Delete" button (right half)
        local delBtn = AceGUI:Create("Button")
        delBtn:SetText("Delete")
        delBtn:SetCallback("OnClick", function()
            if selectedGroup and CooldownCompanion.db.profile.groups[selectedGroup] then
                local group = CooldownCompanion.db.profile.groups[selectedGroup]
                local name = group and group.name or "this group"
                ShowPopupAboveConfig("CDC_DELETE_GROUP", name, { groupId = selectedGroup })
            end
        end)
        delBtn.frame:SetParent(col1ButtonBar)
        delBtn.frame:ClearAllPoints()
        delBtn.frame:SetPoint("TOPLEFT", col1ButtonBar, "TOP", 2, 0)
        delBtn.frame:SetPoint("BOTTOMRIGHT", col1ButtonBar, "BOTTOMRIGHT", 0, 0)
        delBtn.frame:Show()
        table.insert(col1BarWidgets, delBtn)
    end
end

------------------------------------------------------------------------
-- COLUMN 2: Spells / Items
------------------------------------------------------------------------
function RefreshColumn2()
    if not col2Scroll then return end
    for _, btn in ipairs(col2InfoButtons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(col2InfoButtons)
    CancelDrag()
    col2Scroll:ReleaseChildren()

    if not selectedGroup then
        local label = AceGUI:Create("Label")
        label:SetText("Select a group first")
        label:SetFullWidth(true)
        col2Scroll:AddChild(label)
        return
    end

    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end

    -- Input editbox
    local inputBox = AceGUI:Create("EditBox")
    inputBox:SetLabel("")
    inputBox:SetText(newInput)
    inputBox:DisableButton(true)
    inputBox:SetFullWidth(true)
    inputBox:SetCallback("OnEnterPressed", function(widget, event, text)
        newInput = text
        if newInput ~= "" and selectedGroup then
            if TryAdd(newInput) then
                newInput = ""
                CooldownCompanion:RefreshConfigPanel()
            end
        end
    end)
    inputBox.editbox:HookScript("OnTextChanged", function(self, userInput)
        if userInput then
            newInput = self:GetText()
        end
    end)
    inputBox.editbox:SetPoint("BOTTOMRIGHT", 1, 0)
    col2Scroll:AddChild(inputBox)

    local spacer = AceGUI:Create("SimpleGroup")
    spacer:SetFullWidth(true)
    spacer:SetHeight(2)
    spacer.noAutoHeight = true
    col2Scroll:AddChild(spacer)

    local addBtn = AceGUI:Create("Button")
    addBtn:SetText("Add Spell/Item to Track")
    addBtn:SetFullWidth(true)
    addBtn:SetCallback("OnClick", function()
        if newInput ~= "" and selectedGroup then
            if TryAdd(newInput) then
                newInput = ""
                CooldownCompanion:RefreshConfigPanel()
            end
        end
    end)
    col2Scroll:AddChild(addBtn)

    -- Separator
    local sep = AceGUI:Create("Heading")
    sep:SetText("")
    sep:SetFullWidth(true)
    col2Scroll:AddChild(sep)

    -- Spell/Item list
    -- childOffset = 3 (inputBox, addBtn, sep are the first 3 children before draggable entries)
    local numButtons = #group.buttons
    for i, buttonData in ipairs(group.buttons) do
        local entry = AceGUI:Create("InteractiveLabel")
        local usable = CooldownCompanion:IsButtonUsable(buttonData)
        entry:SetText(buttonData.name or ("Unknown " .. buttonData.type))
        entry:SetImage(GetButtonIcon(buttonData))
        entry:SetImageSize(32, 32)
        entry:SetFullWidth(true)
        entry:SetFontObject(GameFontHighlight)
        entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        if selectedButtons[i] then
            entry:SetColor(0.4, 0.7, 1.0)
        elseif selectedButton == i then
            entry:SetColor(0.4, 0.7, 1.0)
        elseif not usable then
            entry:SetColor(0.5, 0.5, 0.5)
        end

        -- Clean up any recycled warning icon, then create if needed
        if entry.frame._cdcWarnBtn then
            entry.frame._cdcWarnBtn:Hide()
        end
        if not usable then
            local warnBtn = entry.frame._cdcWarnBtn
            if not warnBtn then
                warnBtn = CreateFrame("Button", nil, entry.frame)
                warnBtn:SetSize(16, 16)
                warnBtn:SetPoint("RIGHT", entry.frame, "RIGHT", -4, 0)
                local warnText = warnBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                warnText:SetPoint("CENTER")
                warnText:SetText("|cffff4444(!)|r")
                warnBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("Spell/item unavailable", 1, 0.3, 0.3)
                    GameTooltip:Show()
                end)
                warnBtn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
                entry.frame._cdcWarnBtn = warnBtn
            end
            warnBtn:SetFrameLevel(entry.frame:GetFrameLevel() + 5)
            warnBtn:Show()
        end

        -- Neutralize InteractiveLabel's built-in OnClick (Label_OnClick Fire)
        -- so that mousedown doesn't trigger selection; we handle clicks on mouseup instead
        entry:SetCallback("OnClick", function() end)

        -- Handle clicks via OnMouseUp with drag guard
        local entryFrame = entry.frame
        entryFrame:SetScript("OnMouseUp", function(self, button)
            -- If a drag was active, suppress this click
            if dragState and dragState.phase == "active" then return end
            -- If cursor holds a spell/item from spellbook/bags, receive the drop
            if button == "LeftButton" and GetCursorInfo() then
                if TryReceiveCursorDrop() then return end
            end
            if button == "LeftButton" then
                if IsControlKeyDown() then
                    -- Ctrl+click: toggle multi-select
                    if selectedButtons[i] then
                        selectedButtons[i] = nil
                    else
                        selectedButtons[i] = true
                    end
                    -- Include current selectedButton in multi-select if starting fresh
                    if selectedButton and not selectedButtons[selectedButton] and next(selectedButtons) then
                        selectedButtons[selectedButton] = true
                    end
                    selectedButton = nil
                else
                    -- Normal click: toggle single select, clear multi-select
                    wipe(selectedButtons)
                    if selectedButton == i then
                        selectedButton = nil
                    else
                        selectedButton = i
                    end
                end
                CooldownCompanion:RefreshConfigPanel()
            elseif button == "RightButton" then
                local name = buttonData.name or "this entry"
                ShowPopupAboveConfig("CDC_DELETE_BUTTON", name, { groupId = selectedGroup, buttonIndex = i })
            elseif button == "MiddleButton" then
                if not moveMenuFrame then
                    moveMenuFrame = CreateFrame("Frame", "CDCMoveMenu", UIParent, "UIDropDownMenuTemplate")
                end
                local sourceGroupId = selectedGroup
                local sourceIndex = i
                local entryData = buttonData
                UIDropDownMenu_Initialize(moveMenuFrame, function(self, level)
                    local db = CooldownCompanion.db.profile
                    local groupIds = {}
                    for id in pairs(db.groups) do
                        table.insert(groupIds, id)
                    end
                    table.sort(groupIds)
                    for _, gid in ipairs(groupIds) do
                        if gid ~= sourceGroupId then
                            local info = UIDropDownMenu_CreateInfo()
                            info.text = db.groups[gid].name
                            info.func = function()
                                table.insert(db.groups[gid].buttons, entryData)
                                table.remove(db.groups[sourceGroupId].buttons, sourceIndex)
                                CooldownCompanion:RefreshGroupFrame(gid)
                                CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                                selectedButton = nil
                                wipe(selectedButtons)
                                CooldownCompanion:RefreshConfigPanel()
                                CloseDropDownMenus()
                            end
                            UIDropDownMenu_AddButton(info, level)
                        end
                    end
                end, "MENU")
                moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                ToggleDropDownMenu(1, nil, moveMenuFrame, "cursor", 0, 0)
            end
        end)

        col2Scroll:AddChild(entry)

        -- Accept spell/item drops on each entry frame
        entryFrame:SetScript("OnReceiveDrag", TryReceiveCursorDrop)

        -- Hold-click drag reorder via handler-table HookScript pattern
        if not entryFrame._cdcDragHooked then
            entryFrame._cdcDragHooked = true
            entryFrame:HookScript("OnMouseDown", function(self, mouseBtn)
                if self._cdcOnMouseDown then self._cdcOnMouseDown(self, mouseBtn) end
            end)
        end
        entryFrame._cdcOnMouseDown = function(self, button)
            -- Don't start internal drag-reorder when cursor holds a spell/item
            if GetCursorInfo() then return end
            if button == "LeftButton" and not IsControlKeyDown() then
                local cursorY = GetScaledCursorPosition(col2Scroll)
                dragState = {
                    kind = "button",
                    phase = "pending",
                    sourceIndex = i,
                    groupId = selectedGroup,
                    scrollWidget = col2Scroll,
                    widget = entry,
                    startY = cursorY,
                    childOffset = 3,
                    totalDraggable = numButtons,
                }
                StartDragTracking()
            end
        end
    end

    -- Count multi-selected entries
    local multiCount = 0
    local multiIndices = {}
    for idx in pairs(selectedButtons) do
        multiCount = multiCount + 1
        table.insert(multiIndices, idx)
    end

    if multiCount >= 2 then
        -- Multi-select: show Delete Selected button
        local delHeading = AceGUI:Create("Heading")
        delHeading:SetText(multiCount .. " Selected")
        delHeading:SetFullWidth(true)
        col2Scroll:AddChild(delHeading)

        local delRow = AceGUI:Create("SimpleGroup")
        delRow:SetFullWidth(true)
        delRow:SetLayout("Flow")
        local delBtn = AceGUI:Create("Button")
        delBtn:SetText("Delete Selected")
        delBtn:SetFullWidth(true)
        delBtn:SetCallback("OnClick", function()
            ShowPopupAboveConfig("CDC_DELETE_SELECTED_BUTTONS", multiCount,
                { groupId = selectedGroup, indices = multiIndices })
        end)
        delRow:AddChild(delBtn)
        col2Scroll:AddChild(delRow)

        local moveRow = AceGUI:Create("SimpleGroup")
        moveRow:SetFullWidth(true)
        moveRow:SetLayout("Flow")
        local moveBtn = AceGUI:Create("Button")
        moveBtn:SetText("Move Selected")
        moveBtn:SetFullWidth(true)
        moveBtn:SetCallback("OnClick", function()
            if not moveMenuFrame then
                moveMenuFrame = CreateFrame("Frame", "CDCMoveMenu", UIParent, "UIDropDownMenuTemplate")
            end
            local sourceGroupId = selectedGroup
            local indices = multiIndices
            UIDropDownMenu_Initialize(moveMenuFrame, function(self, level)
                local db = CooldownCompanion.db.profile
                local groupIds = {}
                for id in pairs(db.groups) do
                    table.insert(groupIds, id)
                end
                table.sort(groupIds)
                for _, gid in ipairs(groupIds) do
                    if gid ~= sourceGroupId then
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = db.groups[gid].name
                        info.func = function()
                            -- Copy entries to target group
                            for _, idx in ipairs(indices) do
                                table.insert(db.groups[gid].buttons, group.buttons[idx])
                            end
                            -- Remove from source in reverse order
                            table.sort(indices, function(a, b) return a > b end)
                            for _, idx in ipairs(indices) do
                                table.remove(db.groups[sourceGroupId].buttons, idx)
                            end
                            CooldownCompanion:RefreshGroupFrame(gid)
                            CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                            selectedButton = nil
                            wipe(selectedButtons)
                            CooldownCompanion:RefreshConfigPanel()
                            CloseDropDownMenus()
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                end
            end, "MENU")
            moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            ToggleDropDownMenu(1, nil, moveMenuFrame, "cursor", 0, 0)
        end)
        moveRow:AddChild(moveBtn)
        col2Scroll:AddChild(moveRow)
    elseif selectedButton and group.buttons[selectedButton]
       and group.buttons[selectedButton].type == "spell" then
        -- Per-spell settings panel (when a single spell is selected)
        local buttonData = group.buttons[selectedButton]

        local spellHeading = AceGUI:Create("Heading")
        spellHeading:SetText("Spell Settings")
        spellHeading:SetFullWidth(true)
        col2Scroll:AddChild(spellHeading)

        -- Show Charge Count toggle
        local chargesCb = AceGUI:Create("CheckBox")
        chargesCb:SetLabel("Charge Based?")
        chargesCb:SetValue(buttonData.hasCharges or false)
        chargesCb:SetFullWidth(true)
        chargesCb:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.hasCharges = val
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        col2Scroll:AddChild(chargesCb)

        -- Charge text customization controls (only when hasCharges is enabled)
        if buttonData.hasCharges then
            local chargeFontSizeSlider = AceGUI:Create("Slider")
            chargeFontSizeSlider:SetLabel("Font Size")
            chargeFontSizeSlider:SetSliderValues(8, 32, 1)
            chargeFontSizeSlider:SetValue(buttonData.chargeFontSize or 12)
            chargeFontSizeSlider:SetFullWidth(true)
            chargeFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeFontSize = val
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            col2Scroll:AddChild(chargeFontSizeSlider)

            local chargeFontDrop = AceGUI:Create("Dropdown")
            chargeFontDrop:SetLabel("Font")
            chargeFontDrop:SetList(fontOptions)
            chargeFontDrop:SetValue(buttonData.chargeFont or "Fonts\\FRIZQT__.TTF")
            chargeFontDrop:SetFullWidth(true)
            chargeFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeFont = val
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            col2Scroll:AddChild(chargeFontDrop)

            local chargeOutlineDrop = AceGUI:Create("Dropdown")
            chargeOutlineDrop:SetLabel("Font Outline")
            chargeOutlineDrop:SetList(outlineOptions)
            chargeOutlineDrop:SetValue(buttonData.chargeFontOutline or "OUTLINE")
            chargeOutlineDrop:SetFullWidth(true)
            chargeOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeFontOutline = val
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            col2Scroll:AddChild(chargeOutlineDrop)

            local chargeFontColor = AceGUI:Create("ColorPicker")
            chargeFontColor:SetLabel("Font Color (Max Charges)")
            chargeFontColor:SetHasAlpha(true)
            local chc = buttonData.chargeFontColor or {1, 1, 1, 1}
            chargeFontColor:SetColor(chc[1], chc[2], chc[3], chc[4])
            chargeFontColor:SetFullWidth(true)
            chargeFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                buttonData.chargeFontColor = {r, g, b, a}
            end)
            chargeFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                buttonData.chargeFontColor = {r, g, b, a}
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            col2Scroll:AddChild(chargeFontColor)

            local chargeFontColorMissing = AceGUI:Create("ColorPicker")
            chargeFontColorMissing:SetLabel("Font Color (Missing Charges)")
            chargeFontColorMissing:SetHasAlpha(true)
            local chm = buttonData.chargeFontColorMissing or {1, 1, 1, 1}
            chargeFontColorMissing:SetColor(chm[1], chm[2], chm[3], chm[4])
            chargeFontColorMissing:SetFullWidth(true)
            chargeFontColorMissing:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                buttonData.chargeFontColorMissing = {r, g, b, a}
            end)
            chargeFontColorMissing:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                buttonData.chargeFontColorMissing = {r, g, b, a}
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            col2Scroll:AddChild(chargeFontColorMissing)

            local chargeAnchorValues = {}
            for _, pt in ipairs(anchorPoints) do
                chargeAnchorValues[pt] = anchorPointLabels[pt]
            end
            local chargeAnchorDrop = AceGUI:Create("Dropdown")
            chargeAnchorDrop:SetLabel("Anchor Point")
            chargeAnchorDrop:SetList(chargeAnchorValues)
            chargeAnchorDrop:SetValue(buttonData.chargeAnchor or "BOTTOMRIGHT")
            chargeAnchorDrop:SetFullWidth(true)
            chargeAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeAnchor = val
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            col2Scroll:AddChild(chargeAnchorDrop)

            local chargeXSlider = AceGUI:Create("Slider")
            chargeXSlider:SetLabel("X Offset")
            chargeXSlider:SetSliderValues(-20, 20, 1)
            chargeXSlider:SetValue(buttonData.chargeXOffset or -2)
            chargeXSlider:SetFullWidth(true)
            chargeXSlider:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeXOffset = val
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            col2Scroll:AddChild(chargeXSlider)

            local chargeYSlider = AceGUI:Create("Slider")
            chargeYSlider:SetLabel("Y Offset")
            chargeYSlider:SetSliderValues(-20, 20, 1)
            chargeYSlider:SetValue(buttonData.chargeYOffset or 2)
            chargeYSlider:SetFullWidth(true)
            chargeYSlider:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeYOffset = val
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            col2Scroll:AddChild(chargeYSlider)
        end

        -- Proc Glow toggle
        local procCb = AceGUI:Create("CheckBox")
        procCb:SetLabel("Show Proc Glow")
        procCb:SetValue(buttonData.procGlow == true)
        procCb:SetFullWidth(true)
        procCb:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.procGlow = val
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        col2Scroll:AddChild(procCb)

        -- (?) tooltip for proc glow
        local procInfo = CreateFrame("Button", nil, procCb.frame)
        procInfo:SetSize(16, 16)
        procInfo:SetPoint("LEFT", procCb.checkbg, "RIGHT", procCb.text:GetStringWidth() + 4, 0)
        local procInfoText = procInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        procInfoText:SetPoint("CENTER")
        procInfoText:SetText("|cff66aaff(?)|r")
        procInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Proc Glow")
            GameTooltip:AddLine("Check this if you want procs associated with this spell to cause the icon's border to glow.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        procInfo:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        table.insert(col2InfoButtons, procInfo)
        if CooldownCompanion.db.profile.hideInfoButtons then
            procInfo:Hide()
        end

        if buttonData.procGlow == true then
            -- Proc Glow color & size (group-wide style settings)
            local procGlowColor = AceGUI:Create("ColorPicker")
            procGlowColor:SetLabel("Glow Color")
            procGlowColor:SetHasAlpha(true)
            local pgc = group.style.procGlowColor or {1, 1, 1, 1}
            procGlowColor:SetColor(pgc[1], pgc[2], pgc[3], pgc[4])
            procGlowColor:SetFullWidth(true)
            procGlowColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                group.style.procGlowColor = {r, g, b, a}
            end)
            procGlowColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                group.style.procGlowColor = {r, g, b, a}
                CooldownCompanion:UpdateGroupStyle(selectedGroup)
            end)
            col2Scroll:AddChild(procGlowColor)

            local procSizeSlider = AceGUI:Create("Slider")
            procSizeSlider:SetLabel("Glow Size")
            procSizeSlider:SetSliderValues(0, 60, 1)
            procSizeSlider:SetValue(group.style.procGlowOverhang or 32)
            procSizeSlider:SetFullWidth(true)
            procSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                group.style.procGlowOverhang = val
                CooldownCompanion:UpdateGroupStyle(selectedGroup)
            end)
            col2Scroll:AddChild(procSizeSlider)
        end

    elseif selectedButton and group.buttons[selectedButton]
       and group.buttons[selectedButton].type == "item"
       and not CooldownCompanion.IsItemEquippable(group.buttons[selectedButton]) then
        -- Per-item settings panel (non-equipment items only — equipment has no count)
        local buttonData = group.buttons[selectedButton]

        local itemHeading = AceGUI:Create("Heading")
        itemHeading:SetText("Item Settings")
        itemHeading:SetFullWidth(true)
        col2Scroll:AddChild(itemHeading)

        -- Item count font size
        local itemFontSizeSlider = AceGUI:Create("Slider")
        itemFontSizeSlider:SetLabel("Item Stack Font Size")
        itemFontSizeSlider:SetSliderValues(8, 32, 1)
        itemFontSizeSlider:SetValue(buttonData.itemCountFontSize or 12)
        itemFontSizeSlider:SetFullWidth(true)
        itemFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.itemCountFontSize = val
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
        end)
        col2Scroll:AddChild(itemFontSizeSlider)

        -- Item count font
        local itemFontDrop = AceGUI:Create("Dropdown")
        itemFontDrop:SetLabel("Font")
        itemFontDrop:SetList(fontOptions)
        itemFontDrop:SetValue(buttonData.itemCountFont or "Fonts\\FRIZQT__.TTF")
        itemFontDrop:SetFullWidth(true)
        itemFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.itemCountFont = val
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
        end)
        col2Scroll:AddChild(itemFontDrop)

        -- Item count font outline
        local itemOutlineDrop = AceGUI:Create("Dropdown")
        itemOutlineDrop:SetLabel("Font Outline")
        itemOutlineDrop:SetList(outlineOptions)
        itemOutlineDrop:SetValue(buttonData.itemCountFontOutline or "OUTLINE")
        itemOutlineDrop:SetFullWidth(true)
        itemOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.itemCountFontOutline = val
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
        end)
        col2Scroll:AddChild(itemOutlineDrop)

        -- Item count font color
        local itemFontColor = AceGUI:Create("ColorPicker")
        itemFontColor:SetLabel("Font Color")
        itemFontColor:SetHasAlpha(true)
        local icc = buttonData.itemCountFontColor or {1, 1, 1, 1}
        itemFontColor:SetColor(icc[1], icc[2], icc[3], icc[4])
        itemFontColor:SetFullWidth(true)
        itemFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            buttonData.itemCountFontColor = {r, g, b, a}
        end)
        itemFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            buttonData.itemCountFontColor = {r, g, b, a}
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
        end)
        col2Scroll:AddChild(itemFontColor)

        -- Item count anchor point
        local itemAnchorValues = {}
        for _, pt in ipairs(anchorPoints) do
            itemAnchorValues[pt] = anchorPointLabels[pt]
        end
        local itemAnchorDrop = AceGUI:Create("Dropdown")
        itemAnchorDrop:SetLabel("Anchor Point")
        itemAnchorDrop:SetList(itemAnchorValues)
        itemAnchorDrop:SetValue(buttonData.itemCountAnchor or "BOTTOMRIGHT")
        itemAnchorDrop:SetFullWidth(true)
        itemAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.itemCountAnchor = val
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
        end)
        col2Scroll:AddChild(itemAnchorDrop)

        -- Item count X offset
        local itemXSlider = AceGUI:Create("Slider")
        itemXSlider:SetLabel("X Offset")
        itemXSlider:SetSliderValues(-20, 20, 1)
        itemXSlider:SetValue(buttonData.itemCountXOffset or -2)
        itemXSlider:SetFullWidth(true)
        itemXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.itemCountXOffset = val
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
        end)
        col2Scroll:AddChild(itemXSlider)

        -- Item count Y offset
        local itemYSlider = AceGUI:Create("Slider")
        itemYSlider:SetLabel("Y Offset")
        itemYSlider:SetSliderValues(-20, 20, 1)
        itemYSlider:SetValue(buttonData.itemCountYOffset or 2)
        itemYSlider:SetFullWidth(true)
        itemYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.itemCountYOffset = val
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
        end)
        col2Scroll:AddChild(itemYSlider)

    end

end

------------------------------------------------------------------------
-- COLUMN 3: Settings (TabGroup)
------------------------------------------------------------------------
local tabInfoButtons = {}

local function BuildExtrasTab(container)
    for _, btn in ipairs(tabInfoButtons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(tabInfoButtons)

    if not selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end
    local style = group.style

    local desatCb = AceGUI:Create("CheckBox")
    desatCb:SetLabel("Desaturate On Cooldown")
    desatCb:SetValue(style.desaturateOnCooldown or false)
    desatCb:SetFullWidth(true)
    desatCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.desaturateOnCooldown = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(desatCb)

    local gcdCb = AceGUI:Create("CheckBox")
    gcdCb:SetLabel("Show GCD Swipe")
    gcdCb:SetValue(style.showGCDSwipe == true)
    gcdCb:SetFullWidth(true)
    gcdCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showGCDSwipe = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(gcdCb)

    local rangeCb = AceGUI:Create("CheckBox")
    rangeCb:SetLabel("Show Out of Range")
    rangeCb:SetValue(style.showOutOfRange or false)
    rangeCb:SetFullWidth(true)
    rangeCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showOutOfRange = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(rangeCb)

    local tooltipCb = AceGUI:Create("CheckBox")
    tooltipCb:SetLabel("Show Tooltips")
    tooltipCb:SetValue(style.showTooltips == true)
    tooltipCb:SetFullWidth(true)
    tooltipCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showTooltips = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(tooltipCb)

    -- Loss of control
    local locCb = AceGUI:Create("CheckBox")
    locCb:SetLabel("Show Loss of Control")
    locCb:SetValue(style.showLossOfControl or false)
    locCb:SetFullWidth(true)
    locCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showLossOfControl = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(locCb)

    -- (?) tooltip for loss of control
    local locInfo = CreateFrame("Button", nil, locCb.frame)
    locInfo:SetSize(16, 16)
    locInfo:SetPoint("LEFT", locCb.checkbg, "RIGHT", locCb.text:GetStringWidth() + 4, 0)
    local locInfoText = locInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    locInfoText:SetPoint("CENTER")
    locInfoText:SetText("|cff66aaff(?)|r")
    locInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Loss of Control")
        GameTooltip:AddLine("Shows a red overlay on spell icons when they are locked out by a stun, interrupt, silence, or other crowd control effect.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    locInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, locInfo)

    if style.showLossOfControl then
        local locColor = AceGUI:Create("ColorPicker")
        locColor:SetLabel("LoC Overlay Color")
        locColor:SetHasAlpha(true)
        local lc = style.lossOfControlColor or {1, 0, 0, 0.5}
        locColor:SetColor(lc[1], lc[2], lc[3], lc[4])
        locColor:SetFullWidth(true)
        locColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.lossOfControlColor = {r, g, b, a}
        end)
        locColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.lossOfControlColor = {r, g, b, a}
        end)
        container:AddChild(locColor)
    end

    -- Usability dimming
    local unusableCb = AceGUI:Create("CheckBox")
    unusableCb:SetLabel("Show Unusable Dimming")
    unusableCb:SetValue(style.showUnusable or false)
    unusableCb:SetFullWidth(true)
    unusableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showUnusable = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(unusableCb)

    -- (?) tooltip for unusable dimming
    local unusableInfo = CreateFrame("Button", nil, unusableCb.frame)
    unusableInfo:SetSize(16, 16)
    unusableInfo:SetPoint("LEFT", unusableCb.checkbg, "RIGHT", unusableCb.text:GetStringWidth() + 4, 0)
    local unusableInfoText = unusableInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unusableInfoText:SetPoint("CENTER")
    unusableInfoText:SetText("|cff66aaff(?)|r")
    unusableInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Unusable Dimming")
        GameTooltip:AddLine("Tints spell and item icons when unusable due to insufficient resources or other restrictions. Out-of-range tinting takes priority when both apply.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    unusableInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, unusableInfo)

    if style.showUnusable then
        local unusableColor = AceGUI:Create("ColorPicker")
        unusableColor:SetLabel("Unusable Tint Color")
        unusableColor:SetHasAlpha(false)
        local uc = style.unusableColor or {0.3, 0.3, 0.6}
        unusableColor:SetColor(uc[1], uc[2], uc[3])
        unusableColor:SetFullWidth(true)
        unusableColor:SetCallback("OnValueChanged", function(widget, event, r, g, b)
            style.unusableColor = {r, g, b}
        end)
        unusableColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
            style.unusableColor = {r, g, b}
        end)
        container:AddChild(unusableColor)
    end

    -- Assisted Highlight section
    local assistedHeading = AceGUI:Create("Heading")
    assistedHeading:SetText("Assisted Highlight")
    assistedHeading:SetFullWidth(true)
    container:AddChild(assistedHeading)

    local assistedCb = AceGUI:Create("CheckBox")
    assistedCb:SetLabel("Show Assisted Highlight")
    assistedCb:SetValue(style.showAssistedHighlight or false)
    assistedCb:SetFullWidth(true)
    assistedCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showAssistedHighlight = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(assistedCb)

    if style.showAssistedHighlight then
        local highlightStyles = {
            blizzard = "Blizzard (Marching Ants)",
            proc = "Proc Glow",
            solid = "Solid Border",
        }
        local styleDrop = AceGUI:Create("Dropdown")
        styleDrop:SetLabel("Highlight Style")
        styleDrop:SetList(highlightStyles)
        styleDrop:SetValue(style.assistedHighlightStyle or "blizzard")
        styleDrop:SetFullWidth(true)
        styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.assistedHighlightStyle = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(styleDrop)

        if style.assistedHighlightStyle == "solid" then
            local hlColor = AceGUI:Create("ColorPicker")
            hlColor:SetLabel("Highlight Color")
            hlColor:SetHasAlpha(true)
            local c = style.assistedHighlightColor or {0.3, 1, 0.3, 0.9}
            hlColor:SetColor(c[1], c[2], c[3], c[4])
            hlColor:SetFullWidth(true)
            hlColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                style.assistedHighlightColor = {r, g, b, a}
            end)
            hlColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                style.assistedHighlightColor = {r, g, b, a}
            end)
            container:AddChild(hlColor)

            local hlSizeSlider = AceGUI:Create("Slider")
            hlSizeSlider:SetLabel("Border Size")
            hlSizeSlider:SetSliderValues(1, 6, 0.5)
            hlSizeSlider:SetValue(style.assistedHighlightBorderSize or 2)
            hlSizeSlider:SetFullWidth(true)
            hlSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                style.assistedHighlightBorderSize = val
                CooldownCompanion:UpdateGroupStyle(selectedGroup)
            end)
            container:AddChild(hlSizeSlider)
        elseif style.assistedHighlightStyle == "blizzard" then
            local blizzSlider = AceGUI:Create("Slider")
            blizzSlider:SetLabel("Glow Size")
            blizzSlider:SetSliderValues(0, 60, 1)
            blizzSlider:SetValue(style.assistedHighlightBlizzardOverhang or 32)
            blizzSlider:SetFullWidth(true)
            blizzSlider:SetCallback("OnValueChanged", function(widget, event, val)
                style.assistedHighlightBlizzardOverhang = val
                CooldownCompanion:UpdateGroupStyle(selectedGroup)
            end)
            container:AddChild(blizzSlider)
        elseif style.assistedHighlightStyle == "proc" then
            local procHlColor = AceGUI:Create("ColorPicker")
            procHlColor:SetLabel("Glow Color")
            procHlColor:SetHasAlpha(true)
            local phc = style.assistedHighlightProcColor or {1, 1, 1, 1}
            procHlColor:SetColor(phc[1], phc[2], phc[3], phc[4])
            procHlColor:SetFullWidth(true)
            procHlColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                style.assistedHighlightProcColor = {r, g, b, a}
            end)
            procHlColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                style.assistedHighlightProcColor = {r, g, b, a}
                CooldownCompanion:UpdateGroupStyle(selectedGroup)
            end)
            container:AddChild(procHlColor)

            local procSlider = AceGUI:Create("Slider")
            procSlider:SetLabel("Glow Size")
            procSlider:SetSliderValues(0, 60, 1)
            procSlider:SetValue(style.assistedHighlightProcOverhang or 32)
            procSlider:SetFullWidth(true)
            procSlider:SetCallback("OnValueChanged", function(widget, event, val)
                style.assistedHighlightProcOverhang = val
                CooldownCompanion:UpdateGroupStyle(selectedGroup)
            end)
            container:AddChild(procSlider)
        end
    end

    -- Apply "Hide CDC Tooltips" to tab info buttons created above
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(tabInfoButtons) do
            btn:Hide()
        end
    end

    -- Other ---------------------------------------------------------------
    local otherHeading = AceGUI:Create("Heading")
    otherHeading:SetText("Other")
    otherHeading:SetFullWidth(true)
    container:AddChild(otherHeading)

    local hideInfoCb = AceGUI:Create("CheckBox")
    hideInfoCb:SetLabel("Hide CDC Tooltips")
    hideInfoCb:SetValue(CooldownCompanion.db.profile.hideInfoButtons or false)
    hideInfoCb:SetFullWidth(true)
    hideInfoCb:SetCallback("OnValueChanged", function(widget, event, val)
        CooldownCompanion.db.profile.hideInfoButtons = val
        for _, btn in ipairs(columnInfoButtons) do
            if val then btn:Hide() else btn:Show() end
        end
        for _, btn in ipairs(tabInfoButtons) do
            if val then btn:Hide() else btn:Show() end
        end
        for _, btn in ipairs(col2InfoButtons) do
            if val then btn:Hide() else btn:Show() end
        end
    end)
    container:AddChild(hideInfoCb)
end

local function BuildPositioningTab(container)
    if not selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end

    -- Anchor to Frame (editbox + pick button row)
    local anchorRow = AceGUI:Create("SimpleGroup")
    anchorRow:SetFullWidth(true)
    anchorRow:SetLayout("Flow")

    local anchorBox = AceGUI:Create("EditBox")
    anchorBox:SetLabel("Anchor to Frame")
    local currentAnchor = group.anchor.relativeTo
    if currentAnchor == "UIParent" then currentAnchor = "" end
    anchorBox:SetText(currentAnchor)
    anchorBox:SetRelativeWidth(0.72)
    anchorBox:SetCallback("OnEnterPressed", function(widget, event, text)
        local wasAnchored = group.anchor.relativeTo and group.anchor.relativeTo ~= "UIParent"
        if text == "" then
            CooldownCompanion:SetGroupAnchor(selectedGroup, "UIParent", wasAnchored)
        else
            CooldownCompanion:SetGroupAnchor(selectedGroup, text)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    anchorRow:AddChild(anchorBox)

    local pickBtn = AceGUI:Create("Button")
    pickBtn:SetText("Pick")
    pickBtn:SetRelativeWidth(0.20)
    pickBtn:SetCallback("OnClick", function()
        local grp = selectedGroup
        StartPickFrame(function(name)
            -- Re-show config panel
            if configFrame then
                configFrame.frame:Show()
            end
            if name then
                CooldownCompanion:SetGroupAnchor(grp, name)
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
    end)
    anchorRow:AddChild(pickBtn)

    -- (?) tooltip for anchor picking
    local pickInfo = CreateFrame("Button", nil, pickBtn.frame)
    pickInfo:SetSize(16, 16)
    pickInfo:SetPoint("LEFT", pickBtn.frame, "RIGHT", 2, 0)
    local pickInfoText = pickInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pickInfoText:SetPoint("CENTER")
    pickInfoText:SetText("|cff66aaff(?)|r")
    pickInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Pick Frame")
        GameTooltip:AddLine("Hides the config panel and highlights frames under your cursor. Left-click a frame to anchor this group to it, or right-click to cancel.", 1, 1, 1, true)
        GameTooltip:AddLine("You can also type a frame name directly into the editbox.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pickInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, pickInfo)

    container:AddChild(anchorRow)

    -- Anchor Point dropdown
    local pointValues = {}
    for _, pt in ipairs(anchorPoints) do
        pointValues[pt] = anchorPointLabels[pt]
    end

    local anchorPt = AceGUI:Create("Dropdown")
    anchorPt:SetLabel("Anchor Point")
    anchorPt:SetList(pointValues)
    anchorPt:SetValue(group.anchor.point or "CENTER")
    anchorPt:SetFullWidth(true)
    anchorPt:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.point = val
        local frame = CooldownCompanion.groupFrames[selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    container:AddChild(anchorPt)

    -- Relative Point dropdown
    local relPt = AceGUI:Create("Dropdown")
    relPt:SetLabel("Relative Point")
    relPt:SetList(pointValues)
    relPt:SetValue(group.anchor.relativePoint or "CENTER")
    relPt:SetFullWidth(true)
    relPt:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.relativePoint = val
        local frame = CooldownCompanion.groupFrames[selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    container:AddChild(relPt)

    -- Allow decimal input from editbox while keeping slider/wheel at 1px steps
    local function HookSliderEditBox(sliderWidget)
        sliderWidget.editbox:SetScript("OnEnterPressed", function(editbox)
            local widget = editbox.obj
            local value = tonumber(editbox:GetText())
            if value then
                value = math.floor(value * 10 + 0.5) / 10
                value = math.max(widget.min, math.min(widget.max, value))
                PlaySound(856)
                widget:SetValue(value)
                widget:Fire("OnValueChanged", value)
                widget:Fire("OnMouseUp", value)
            end
        end)
    end

    -- X Offset
    local xSlider = AceGUI:Create("Slider")
    xSlider:SetLabel("X Offset")
    xSlider:SetSliderValues(-2000, 2000, 1)
    xSlider:SetValue(group.anchor.x or 0)
    xSlider:SetFullWidth(true)
    xSlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.x = val
        local frame = CooldownCompanion.groupFrames[selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    HookSliderEditBox(xSlider)
    container:AddChild(xSlider)

    -- Y Offset
    local ySlider = AceGUI:Create("Slider")
    ySlider:SetLabel("Y Offset")
    ySlider:SetSliderValues(-2000, 2000, 1)
    ySlider:SetValue(group.anchor.y or 0)
    ySlider:SetFullWidth(true)
    ySlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.y = val
        local frame = CooldownCompanion.groupFrames[selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    HookSliderEditBox(ySlider)
    container:AddChild(ySlider)

    -- Orientation dropdown
    local orientDrop = AceGUI:Create("Dropdown")
    orientDrop:SetLabel("Orientation")
    orientDrop:SetList({ horizontal = "Horizontal", vertical = "Vertical" })
    orientDrop:SetValue(group.style.orientation or "horizontal")
    orientDrop:SetFullWidth(true)
    orientDrop:SetCallback("OnValueChanged", function(widget, event, val)
        group.style.orientation = val
        CooldownCompanion:RefreshGroupFrame(selectedGroup)
    end)
    container:AddChild(orientDrop)

    -- Buttons Per Row/Column
    local numButtons = math.max(1, #group.buttons)
    local bprSlider = AceGUI:Create("Slider")
    bprSlider:SetLabel("Buttons Per Row/Column")
    bprSlider:SetSliderValues(1, numButtons, 1)
    bprSlider:SetValue(math.min(group.style.buttonsPerRow or 12, numButtons))
    bprSlider:SetFullWidth(true)
    bprSlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.style.buttonsPerRow = val
        CooldownCompanion:RefreshGroupFrame(selectedGroup)
    end)
    container:AddChild(bprSlider)

    -- ================================================================
    -- Strata (Layer Order)
    -- ================================================================
    local strataHeading = AceGUI:Create("Heading")
    strataHeading:SetText("Strata")
    strataHeading:SetFullWidth(true)
    container:AddChild(strataHeading)

    local style = group.style
    local customStrataEnabled = type(style.strataOrder) == "table"

    local strataToggle = AceGUI:Create("CheckBox")
    strataToggle:SetLabel("Custom Strata")
    strataToggle:SetValue(customStrataEnabled)
    strataToggle:SetFullWidth(true)
    strataToggle:SetCallback("OnValueChanged", function(widget, event, val)
        if not val then
            style.strataOrder = nil
            pendingStrataOrder = {nil, nil, nil, nil}
            pendingStrataGroup = selectedGroup
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        else
            style.strataOrder = style.strataOrder or {}
            -- Force reinitialize so defaults always appear in dropdowns
            pendingStrataOrder = nil
            InitPendingStrataOrder(selectedGroup)
        end
        -- Rebuild tab to show/hide dropdowns (toggle is a deliberate action)
        if col3Container and col3Container.tabGroup then
            col3Container.tabGroup:SelectTab(selectedTab)
        end
    end)
    container:AddChild(strataToggle)

    -- (?) tooltip for custom strata
    local strataInfo = CreateFrame("Button", nil, strataToggle.frame)
    strataInfo:SetSize(16, 16)
    strataInfo:SetPoint("LEFT", strataToggle.checkbg, "RIGHT", strataToggle.text:GetStringWidth() + 4, 0)
    local strataInfoText = strataInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    strataInfoText:SetPoint("CENTER")
    strataInfoText:SetText("|cff66aaff(?)|r")
    strataInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Custom Strata")
        GameTooltip:AddLine("Controls the draw order of overlays on each icon: Cooldown Swipe, Charge Text, Proc Glow, and Assisted Highlight.", 1, 1, 1, true)
        GameTooltip:AddLine("Layer 4 draws on top, Layer 1 on the bottom. When disabled, the default order is used.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    strataInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, strataInfo)

    if customStrataEnabled then
        -- Initialize pending state for this group
        InitPendingStrataOrder(selectedGroup)

        -- Build dropdown list: all 4 element options
        local strataDropdownList = {}
        for _, key in ipairs(strataElementKeys) do
            strataDropdownList[key] = strataElementLabels[key]
        end

        -- Create 4 dropdowns: position 4 (top) displayed first, position 1 (bottom) last
        local strataDropdowns = {}
        for displayIdx = 1, 4 do
            local pos = 5 - displayIdx  -- 4, 3, 2, 1
            local label
            if pos == 4 then
                label = "Layer 4 (Top)"
            elseif pos == 1 then
                label = "Layer 1 (Bottom)"
            else
                label = "Layer " .. pos
            end

            local drop = AceGUI:Create("Dropdown")
            drop:SetLabel(label)
            drop:SetList(strataDropdownList)
            drop:SetValue(pendingStrataOrder[pos])
            drop:SetFullWidth(true)
            drop:SetCallback("OnValueChanged", function(widget, event, val)
                -- Clear this value from any other position (mutual exclusion)
                for i = 1, 4 do
                    if i ~= pos and pendingStrataOrder[i] == val then
                        pendingStrataOrder[i] = nil
                    end
                end
                pendingStrataOrder[pos] = val

                -- Save if all 4 assigned, otherwise nil out the saved order
                if IsStrataOrderComplete(pendingStrataOrder) then
                    style.strataOrder = {}
                    for i = 1, 4 do
                        style.strataOrder[i] = pendingStrataOrder[i]
                    end
                else
                    style.strataOrder = {}
                end
                CooldownCompanion:UpdateGroupStyle(selectedGroup)

                -- Update sibling dropdowns directly to reflect mutual exclusion
                for i = 1, 4 do
                    if strataDropdowns[i] then
                        strataDropdowns[i]:SetValue(pendingStrataOrder[i])
                    end
                end
            end)
            container:AddChild(drop)
            strataDropdowns[pos] = drop
        end
    end

    -- Apply "Hide CDC Tooltips" to tab info buttons created above
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(tabInfoButtons) do
            btn:Hide()
        end
    end
end

local function BuildAppearanceTab(container)
    if not selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end
    local style = group.style

    -- Icon Settings header
    local iconHeading = AceGUI:Create("Heading")
    iconHeading:SetText("Icon Settings")
    iconHeading:SetFullWidth(true)
    container:AddChild(iconHeading)

    local squareCb = AceGUI:Create("CheckBox")
    squareCb:SetLabel("Square Icons")
    squareCb:SetValue(style.maintainAspectRatio or false)
    squareCb:SetFullWidth(true)
    squareCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.maintainAspectRatio = val
        if not val then
            local size = style.buttonSize or ST.BUTTON_SIZE
            style.iconWidth = style.iconWidth or size
            style.iconHeight = style.iconHeight or size
        end
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(squareCb)

    -- Sliders and pickers
    if style.maintainAspectRatio then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Button Size")
        sizeSlider:SetSliderValues(20, 64, 1)
        sizeSlider:SetValue(style.buttonSize or ST.BUTTON_SIZE)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.buttonSize = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(sizeSlider)
    else
        local wSlider = AceGUI:Create("Slider")
        wSlider:SetLabel("Icon Width")
        wSlider:SetSliderValues(10, 100, 1)
        wSlider:SetValue(style.iconWidth or style.buttonSize or ST.BUTTON_SIZE)
        wSlider:SetFullWidth(true)
        wSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.iconWidth = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(wSlider)

        local hSlider = AceGUI:Create("Slider")
        hSlider:SetLabel("Icon Height")
        hSlider:SetSliderValues(10, 100, 1)
        hSlider:SetValue(style.iconHeight or style.buttonSize or ST.BUTTON_SIZE)
        hSlider:SetFullWidth(true)
        hSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.iconHeight = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(hSlider)
    end

    local spacingSlider = AceGUI:Create("Slider")
    spacingSlider:SetLabel("Button Spacing")
    spacingSlider:SetSliderValues(0, 10, 1)
    spacingSlider:SetValue(style.buttonSpacing or ST.BUTTON_SPACING)
    spacingSlider:SetFullWidth(true)
    spacingSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.buttonSpacing = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(spacingSlider)

    local borderSlider = AceGUI:Create("Slider")
    borderSlider:SetLabel("Border Size")
    borderSlider:SetSliderValues(0, 5, 0.1)
    borderSlider:SetValue(style.borderSize or ST.DEFAULT_BORDER_SIZE)
    borderSlider:SetFullWidth(true)
    borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.borderSize = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(borderSlider)

    local borderColor = AceGUI:Create("ColorPicker")
    borderColor:SetLabel("Border Color")
    borderColor:SetHasAlpha(true)
    local bc = style.borderColor or {0, 0, 0, 1}
    borderColor:SetColor(bc[1], bc[2], bc[3], bc[4])
    borderColor:SetFullWidth(true)
    borderColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.borderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    borderColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.borderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(borderColor)

    -- Text Settings header
    local textHeading = AceGUI:Create("Heading")
    textHeading:SetText("Text Settings")
    textHeading:SetFullWidth(true)
    container:AddChild(textHeading)

    -- Toggles first
    local cdTextCb = AceGUI:Create("CheckBox")
    cdTextCb:SetLabel("Show Cooldown Text")
    cdTextCb:SetValue(style.showCooldownText or false)
    cdTextCb:SetFullWidth(true)
    cdTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showCooldownText = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(cdTextCb)

    -- Font settings only shown when cooldown text is enabled
    if style.showCooldownText then
        local fontSizeSlider = AceGUI:Create("Slider")
        fontSizeSlider:SetLabel("Font Size")
        fontSizeSlider:SetSliderValues(8, 32, 1)
        fontSizeSlider:SetValue(style.cooldownFontSize or 12)
        fontSizeSlider:SetFullWidth(true)
        fontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFontSize = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(fontSizeSlider)

        local fontDrop = AceGUI:Create("Dropdown")
        fontDrop:SetLabel("Font")
        fontDrop:SetList(fontOptions)
        fontDrop:SetValue(style.cooldownFont or "Fonts\\FRIZQT__.TTF")
        fontDrop:SetFullWidth(true)
        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFont = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(fontDrop)

        local outlineDrop = AceGUI:Create("Dropdown")
        outlineDrop:SetLabel("Font Outline")
        outlineDrop:SetList(outlineOptions)
        outlineDrop:SetValue(style.cooldownFontOutline or "OUTLINE")
        outlineDrop:SetFullWidth(true)
        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFontOutline = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(outlineDrop)

        local cdFontColor = AceGUI:Create("ColorPicker")
        cdFontColor:SetLabel("Font Color")
        cdFontColor:SetHasAlpha(true)
        local cdc = style.cooldownFontColor or {1, 1, 1, 1}
        cdFontColor:SetColor(cdc[1], cdc[2], cdc[3], cdc[4])
        cdFontColor:SetFullWidth(true)
        cdFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.cooldownFontColor = {r, g, b, a}
        end)
        cdFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.cooldownFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(cdFontColor)
    end

end

function RefreshColumn3(container)
    if not selectedGroup then
        -- Show placeholder, hide tab group
        if not container.placeholderLabel then
            container.placeholderLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            container.placeholderLabel:SetPoint("TOPLEFT", -1, 0)
        end
        container.placeholderLabel:SetText("Select a group to configure")
        container.placeholderLabel:Show()
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        return
    end

    if container.placeholderLabel then
        container.placeholderLabel:Hide()
    end

    -- Create the TabGroup once, reuse on subsequent refreshes
    if not container.tabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetTabs({
            { value = "appearance",  text = "Appearance" },
            { value = "positioning", text = "Positioning" },
            { value = "extras",      text = "Extras" },
        })
        tabGroup:SetLayout("Fill")

        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            selectedTab = tab
            -- Clean up raw (?) info buttons BEFORE releasing children, so they
            -- don't leak onto recycled AceGUI frames when switching tabs
            for _, btn in ipairs(tabInfoButtons) do
                btn:ClearAllPoints()
                btn:Hide()
                btn:SetParent(nil)
            end
            wipe(tabInfoButtons)
            widget:ReleaseChildren()

            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)

            if tab == "appearance" then
                BuildAppearanceTab(scroll)
            elseif tab == "positioning" then
                BuildPositioningTab(scroll)
            elseif tab == "extras" then
                BuildExtrasTab(scroll)
            end
        end)

        -- Parent the AceGUI widget frame to our raw column frame
        tabGroup.frame:SetParent(container)
        tabGroup.frame:ClearAllPoints()
        tabGroup.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        tabGroup.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)

        container.tabGroup = tabGroup
    end

    -- Show and refresh the tab content
    container.tabGroup.frame:Show()
    container.tabGroup:SelectTab(selectedTab)
end

------------------------------------------------------------------------
-- Profile Bar
------------------------------------------------------------------------
function RefreshProfileBar(barFrame)
    -- Release tracked AceGUI widgets
    for _, widget in ipairs(profileBarAceWidgets) do
        widget:Release()
    end
    wipe(profileBarAceWidgets)

    -- Clear existing children (FontStrings are regions, not children, so clear both)
    for _, child in ipairs({barFrame:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    if barFrame.profileLabel then
        barFrame.profileLabel:Hide()
    end

    local db = CooldownCompanion.db
    local profiles = db:GetProfiles()
    local currentProfile = db:GetCurrentProfile()

    -- "Profile:" label
    local label = barFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", barFrame, "LEFT", 8, 0)
    label:SetText("Profile:")
    barFrame.profileLabel = label

    -- Build ordered profile list for AceGUI Dropdown
    local profileList = {}
    for _, name in ipairs(profiles) do
        profileList[name] = name
    end

    -- Profile dropdown (AceGUI)
    local profileDrop = AceGUI:Create("Dropdown")
    profileDrop:SetLabel("")
    profileDrop:SetList(profileList, profiles)
    profileDrop:SetValue(currentProfile)
    profileDrop:SetCallback("OnValueChanged", function(widget, event, val)
        db:SetProfile(val)
        selectedGroup = nil
        selectedButton = nil
        wipe(selectedButtons)
        CooldownCompanion:RefreshConfigPanel()
        CooldownCompanion:RefreshAllGroups()
    end)
    profileDrop.frame:SetParent(barFrame)
    profileDrop.frame:ClearAllPoints()
    profileDrop.frame:SetPoint("LEFT", label, "RIGHT", 4, 0)
    profileDrop:SetWidth(160)
    profileDrop.frame:Show()
    table.insert(profileBarAceWidgets, profileDrop)

    -- Helper to create bar buttons
    local lastAnchor = profileDrop.frame
    local function AddBarButton(text, width, onClick)
        local btn = AceGUI:Create("Button")
        btn:SetText(text)
        btn:SetCallback("OnClick", onClick)
        btn.frame:SetParent(barFrame)
        btn.frame:ClearAllPoints()
        btn.frame:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
        btn:SetWidth(width)
        btn:SetHeight(24)
        btn.frame:Show()
        table.insert(profileBarAceWidgets, btn)
        lastAnchor = btn.frame
        return btn
    end

    -- New
    AddBarButton("New", 70, function()
        ShowPopupAboveConfig("CDC_NEW_PROFILE")
    end)

    -- Rename
    AddBarButton("Rename", 80, function()
        ShowPopupAboveConfig("CDC_RENAME_PROFILE", currentProfile, { oldName = currentProfile })
    end)

    -- Duplicate
    AddBarButton("Duplicate", 90, function()
        ShowPopupAboveConfig("CDC_DUPLICATE_PROFILE", nil, { source = currentProfile })
    end)

    -- Delete
    AddBarButton("Delete", 70, function()
        local allProfiles = db:GetProfiles()
        local isOnly = #allProfiles <= 1
        if isOnly then
            ShowPopupAboveConfig("CDC_RESET_PROFILE", currentProfile, { profileName = currentProfile, isOnly = true })
        else
            ShowPopupAboveConfig("CDC_DELETE_PROFILE", currentProfile, { profileName = currentProfile })
        end
    end)

    -- Export
    AddBarButton("Export", 70, function()
        ShowPopupAboveConfig("CDC_EXPORT_PROFILE")
    end)

    -- Import
    AddBarButton("Import", 70, function()
        ShowPopupAboveConfig("CDC_IMPORT_PROFILE")
    end)
end

------------------------------------------------------------------------
-- Main Panel Creation
------------------------------------------------------------------------
local function CreateConfigPanel()
    if configFrame then return configFrame end

    -- Main AceGUI Frame
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Cooldown Companion")
    frame:SetStatusText("v1.1.0")
    frame:SetWidth(900)
    frame:SetHeight(700)
    frame:SetLayout(nil) -- manual positioning
    frame:EnableResize(false)

    -- Store the raw frame for raw child parenting
    local content = frame.frame
    -- Get the content area (below the title bar)
    local contentFrame = frame.content

    -- Hide the AceGUI sizer grip since resize is disabled
    if frame.sizer_se then
        frame.sizer_se:Hide()
    end
    if frame.sizer_s then
        frame.sizer_s:Hide()
    end
    if frame.sizer_e then
        frame.sizer_e:Hide()
    end

    -- Prevent AceGUI from releasing on close - just hide
    frame:SetCallback("OnClose", function(widget)
        widget.frame:Hide()
    end)

    -- Minimize toggle button (AceGUI Button with icon texture, top-right of title bar)
    local minimizeBtn = AceGUI:Create("Button")
    minimizeBtn:SetText("")
    minimizeBtn:SetWidth(22)
    minimizeBtn:SetHeight(18)
    minimizeBtn.frame:SetParent(content)
    minimizeBtn.frame:ClearAllPoints()
    minimizeBtn.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -5)
    minimizeBtn.frame:Show()
    -- Add collapse icon texture on top of the skinnable button
    local minimizeIcon = minimizeBtn.frame:CreateTexture(nil, "ARTWORK")
    minimizeIcon:SetTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
    minimizeIcon:SetSize(18, 18)
    minimizeIcon:SetPoint("CENTER")

    local isMinimized = false
    local TITLE_BAR_HEIGHT = 40
    local fullHeight = 700

    -- Find the AceGUI close button (anchored BOTTOMRIGHT, UIPanelButtonTemplate)
    local closeButton
    for _, child in ipairs({content:GetChildren()}) do
        if child:GetObjectType() == "Button" and child:GetText() == CLOSE then
            closeButton = child
            break
        end
    end

    minimizeBtn:SetCallback("OnClick", function()
        -- Capture current top-left position before changing height
        local top = content:GetTop()
        local left = content:GetLeft()

        if isMinimized then
            -- Expand: restore full height, keep top edge in place
            content:ClearAllPoints()
            content:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            content:SetHeight(fullHeight)
            content:SetWidth(900)
            contentFrame:Show()
            frame:SetStatusText("v1.1.0")
            if closeButton then closeButton:Show() end
            isMinimized = false
        else
            -- Collapse: shrink to title bar only, keep top edge in place
            contentFrame:Hide()
            if closeButton then closeButton:Hide() end
            content:ClearAllPoints()
            content:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            content:SetHeight(TITLE_BAR_HEIGHT)
            content:SetWidth(900)
            frame:SetStatusText("")
            isMinimized = true
        end
    end)

    -- Profile bar at the top
    local profileBar = CreateFrame("Frame", nil, contentFrame)
    profileBar:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    profileBar:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, 0)
    profileBar:SetHeight(PROFILE_BAR_HEIGHT)

    -- Column containers below profile bar
    local colParent = CreateFrame("Frame", nil, contentFrame)
    colParent:SetPoint("TOPLEFT", profileBar, "BOTTOMLEFT", 0, -4)
    colParent:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)

    -- Column 1: Groups (AceGUI InlineGroup)
    local col1 = AceGUI:Create("InlineGroup")
    col1:SetTitle("Groups")
    col1:SetLayout("None")
    col1.frame:SetParent(colParent)
    col1.frame:Show()

    -- Info button next to Groups title
    local groupInfoBtn = CreateFrame("Button", nil, col1.frame)
    groupInfoBtn:SetSize(16, 16)
    groupInfoBtn:SetPoint("LEFT", col1.titletext, "RIGHT", -2, 0)
    local groupInfoText = groupInfoBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    groupInfoText:SetPoint("CENTER")
    groupInfoText:SetText("|cff66aaff(?)|r")
    groupInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Groups")
        GameTooltip:AddLine("Left-click to select/deselect.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-click to rename.", 1, 1, 1, true)
        GameTooltip:AddLine("Middle-click to toggle lock/unlock.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Shift+Left-click to set spec filter.", 1, 1, 1, true)
        GameTooltip:AddLine("Shift+Middle-click to toggle on/off.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Hold left-click and move to reorder.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    groupInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Column 2: Spells/Items (AceGUI InlineGroup)
    local col2 = AceGUI:Create("InlineGroup")
    col2:SetTitle("Spells / Items")
    col2:SetLayout("None")
    col2.frame:SetParent(colParent)
    col2.frame:Show()

    -- Info button next to Spells / Items title
    local infoBtn = CreateFrame("Button", nil, col2.frame)
    infoBtn:SetSize(16, 16)
    infoBtn:SetPoint("LEFT", col2.titletext, "RIGHT", -2, 0)
    local infoText = infoBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("CENTER")
    infoText:SetText("|cff66aaff(?)|r")
    infoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Spells / Items")
        GameTooltip:AddLine("Left-click to select/deselect.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-click to remove.", 1, 1, 1, true)
        GameTooltip:AddLine("Middle-click to move to another group.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Ctrl+Left-click to multi-select.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Hold left-click and move to reorder.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Column 3: Settings (AceGUI InlineGroup)
    local col3 = AceGUI:Create("InlineGroup")
    col3:SetTitle("Settings")
    col3:SetLayout("None")
    col3.frame:SetParent(colParent)
    col3.frame:Show()

    -- Info button next to Settings title
    local settingsInfoBtn = CreateFrame("Button", nil, col3.frame)
    settingsInfoBtn:SetSize(16, 16)
    settingsInfoBtn:SetPoint("LEFT", col3.titletext, "RIGHT", -2, 0)
    local settingsInfoText = settingsInfoBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    settingsInfoText:SetPoint("CENTER")
    settingsInfoText:SetText("|cff66aaff(?)|r")
    settingsInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Settings")
        GameTooltip:AddLine("These settings apply to all icons in the selected group.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    settingsInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Store column header (?) buttons for toggling via "Hide CDC Tooltips"
    wipe(columnInfoButtons)
    columnInfoButtons[1] = groupInfoBtn
    columnInfoButtons[2] = infoBtn
    columnInfoButtons[3] = settingsInfoBtn
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(columnInfoButtons) do
            btn:Hide()
        end
    end

    -- Static button bar at bottom of column 1 (New / Delete)
    local btnBar = CreateFrame("Frame", nil, col1.content)
    btnBar:SetPoint("BOTTOMLEFT", col1.content, "BOTTOMLEFT", 0, 0)
    btnBar:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 0)
    btnBar:SetHeight(28)
    col1ButtonBar = btnBar

    -- AceGUI ScrollFrames in columns 1 and 2
    local scroll1 = AceGUI:Create("ScrollFrame")
    scroll1:SetLayout("List")
    scroll1.frame:SetParent(col1.content)
    scroll1.frame:ClearAllPoints()
    scroll1.frame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, 0)
    scroll1.frame:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 28)
    scroll1.frame:Show()
    col1Scroll = scroll1

    local scroll2 = AceGUI:Create("ScrollFrame")
    scroll2:SetLayout("List")
    scroll2.frame:SetParent(col2.content)
    scroll2.frame:ClearAllPoints()
    scroll2.frame:SetPoint("TOPLEFT", col2.content, "TOPLEFT", 0, 0)
    scroll2.frame:SetPoint("BOTTOMRIGHT", col2.content, "BOTTOMRIGHT", 0, 0)
    scroll2.frame:Show()
    col2Scroll = scroll2

    -- Accept spell/item drops anywhere on the column 2 scroll area
    scroll2.frame:EnableMouse(true)
    scroll2.frame:SetScript("OnReceiveDrag", TryReceiveCursorDrop)
    scroll2.content:EnableMouse(true)
    scroll2.content:SetScript("OnReceiveDrag", TryReceiveCursorDrop)

    -- Drop hint overlay for column 2
    local dropOverlay = CreateFrame("Frame", nil, col2.frame, "BackdropTemplate")
    dropOverlay:SetAllPoints(col2.frame)
    dropOverlay:SetFrameLevel(col2.frame:GetFrameLevel() + 20)
    dropOverlay:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    dropOverlay:SetBackdropColor(0.15, 0.55, 0.85, 0.25)
    dropOverlay:EnableMouse(true)
    dropOverlay:SetScript("OnReceiveDrag", TryReceiveCursorDrop)
    dropOverlay:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and GetCursorInfo() then
            TryReceiveCursorDrop()
        end
    end)
    dropOverlay:Hide()

    local dropBorder = dropOverlay:CreateTexture(nil, "BORDER")
    dropBorder:SetAllPoints()
    dropBorder:SetColorTexture(0.3, 0.7, 1.0, 0.35)

    local dropInner = dropOverlay:CreateTexture(nil, "ARTWORK")
    dropInner:SetPoint("TOPLEFT", 2, -2)
    dropInner:SetPoint("BOTTOMRIGHT", -2, 2)
    dropInner:SetColorTexture(0.05, 0.15, 0.25, 0.6)

    local dropText = dropOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dropText:SetPoint("CENTER", 0, 0)
    dropText:SetText("|cffAADDFFDrop here to track|r")

    dropOverlay:RegisterEvent("CURSOR_CHANGED")
    dropOverlay:SetScript("OnEvent", function(self)
        local cursorType = GetCursorInfo()
        if (cursorType == "spell" or cursorType == "item") and selectedGroup and col2.frame:IsShown() then
            self:Show()
        else
            self:Hide()
        end
    end)

    -- Column 3 content area (use InlineGroup's content directly)
    col3Container = col3.content

    -- Layout columns on size change
    local function LayoutColumns()
        local w = colParent:GetWidth()
        local h = colParent:GetHeight()
        local pad = COLUMN_PADDING

        local col1Width = math.floor(w * 0.22)
        local col2Width = math.floor(w * 0.38)
        local col3Width = w - col1Width - col2Width - (pad * 2)

        col1.frame:ClearAllPoints()
        col1.frame:SetPoint("TOPLEFT", colParent, "TOPLEFT", 0, 0)
        col1.frame:SetSize(col1Width, h)

        col2.frame:ClearAllPoints()
        col2.frame:SetPoint("TOPLEFT", col1.frame, "TOPRIGHT", pad, 0)
        col2.frame:SetSize(col2Width, h)

        col3.frame:ClearAllPoints()
        col3.frame:SetPoint("TOPLEFT", col2.frame, "TOPRIGHT", pad, 0)
        col3.frame:SetSize(col3Width, h)
    end

    colParent:SetScript("OnSizeChanged", function()
        LayoutColumns()
    end)

    -- Do initial layout next frame (after frame sizes are established)
    C_Timer.After(0, function()
        LayoutColumns()
    end)

    -- Store references
    frame.profileBar = profileBar
    frame.col1 = col1
    frame.col2 = col2
    frame.col3 = col3
    frame.colParent = colParent
    frame.LayoutColumns = LayoutColumns

    configFrame = frame
    return frame
end

------------------------------------------------------------------------
-- Refresh entire panel
------------------------------------------------------------------------
function CooldownCompanion:RefreshConfigPanel()
    if not configFrame then return end
    if not configFrame.frame:IsShown() then return end

    RefreshProfileBar(configFrame.profileBar)
    RefreshColumn1()
    RefreshColumn2()
    RefreshColumn3(col3Container)
end

------------------------------------------------------------------------
-- Toggle config panel open/closed
------------------------------------------------------------------------
function CooldownCompanion:ToggleConfig()
    if InCombatLockdown() then
        self._configWasOpen = true
        self:Print("Config will open after combat ends.")
        return
    end

    if not configFrame then
        CreateConfigPanel()
        -- Defer first refresh until after column layout is computed (next frame)
        C_Timer.After(0, function()
            CooldownCompanion:RefreshConfigPanel()
        end)
        return -- AceGUI Frame is already shown on creation
    end

    if configFrame.frame:IsShown() then
        configFrame.frame:Hide()
    else
        configFrame.frame:Show()
        self:RefreshConfigPanel()
    end
end

function CooldownCompanion:GetConfigFrame()
    return configFrame
end

------------------------------------------------------------------------
-- SetupConfig: Minimal AceConfig registration for Blizzard Settings
------------------------------------------------------------------------
function CooldownCompanion:SetupConfig()
    -- Register a minimal options table so the addon shows in Blizzard's addon list
    local options = {
        name = "Cooldown Companion",
        type = "group",
        args = {
            openConfig = {
                name = "Open Cooldown Companion",
                desc = "Click to open the configuration panel",
                type = "execute",
                order = 1,
                func = function()
                    -- Close Blizzard settings first
                    if Settings and Settings.CloseUI then
                        Settings.CloseUI()
                    elseif InterfaceOptionsFrame then
                        InterfaceOptionsFrame:Hide()
                    end
                    C_Timer.After(0.1, function()
                        CooldownCompanion:ToggleConfig()
                    end)
                end,
            },
        },
    }

    AceConfig:RegisterOptionsTable(ADDON_NAME, options)
    AceConfigDialog:AddToBlizOptions(ADDON_NAME, "Cooldown Companion")

    -- Profile callbacks to refresh on profile change
    self.db.RegisterCallback(self, "OnProfileChanged", function()
        selectedGroup = nil
        selectedButton = nil
        wipe(selectedButtons)
        if configFrame and configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
    self.db.RegisterCallback(self, "OnProfileCopied", function()
        selectedGroup = nil
        selectedButton = nil
        wipe(selectedButtons)
        if configFrame and configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
    self.db.RegisterCallback(self, "OnProfileReset", function()
        selectedGroup = nil
        selectedButton = nil
        wipe(selectedButtons)
        if configFrame and configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
end
