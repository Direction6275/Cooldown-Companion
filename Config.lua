--[[
    CooldownCompanion - Config
    Custom 4-column config panel using AceGUI-3.0 Frame + InlineGroup columns
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local AceGUI = LibStub("AceGUI-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

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
local col3Scroll = nil    -- Current AceGUI ScrollFrame in column 3

-- AceGUI widget tracking for cleanup
local col1BarWidgets = {}
local profileBarAceWidgets = {}
local buttonSettingsInfoButtons = {}
local buttonSettingsCollapseButtons = {}
local buttonSettingsScroll = nil
local columnInfoButtons = {}
local moveMenuFrame = nil
local groupContextMenu = nil
local buttonContextMenu = nil
local gearDropdownFrame = nil

-- Drag-reorder state
local dragState = nil
local dragIndicator = nil
local dragTracker = nil
local DRAG_THRESHOLD = 8

-- Pending strata order state (survives panel rebuilds, resets on group change)
local pendingStrataOrder = nil

-- Collapsed sections state for button settings (transient UI state)
local collapsedSections = {}
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

StaticPopupDialogs["CDC_UNGLOBAL_GROUP"] = {
    text = "This will remove all spec filters and turn '%s' into a group for your current character. Continue?",
    button1 = "Continue",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.groupId then
            local group = CooldownCompanion.db.profile.groups[data.groupId]
            if group then
                group.specs = nil
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
-- Helper: Check if a frame has visible content (not an empty container)
-- Non-Frame widget types (StatusBar, Button, etc.) inherently render;
-- plain Frames with mouse disabled need at least one shown region.
------------------------------------------------------------------------
local function HasVisibleContent(frame)
    if frame:GetObjectType() ~= "Frame" then return true end
    if frame:IsMouseEnabled() then return true end
    for _, region in pairs({ frame:GetRegions() }) do
        if region:IsShown() then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Helper: Find deepest named child frame under cursor
------------------------------------------------------------------------
local function FindDeepestNamedChild(frame, cx, cy)
    local bestFrame, bestName, bestArea = nil, nil, math.huge
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        -- IsVisible/GetEffectiveAlpha may return secret values in restricted combat; pcall to skip
        local okVis, visible = pcall(function()
            if child.IsForbidden and child:IsForbidden() then return false end
            return child:IsVisible() and child:GetEffectiveAlpha() > 0
        end)
        if okVis and visible then
            local name = child:GetName()
            if name and name ~= "" and not IsAddonFrame(name) then
                -- GetRect may return secret values in restricted combat; pcall to skip
                local ok, inside, area = pcall(function()
                    local left, bottom, width, height = child:GetRect()
                    if not left or not width or width <= 0 or height <= 0 then
                        return false, 0
                    end
                    if cx >= left and cx <= left + width and cy >= bottom and cy <= bottom + height then
                        return true, width * height
                    end
                    return false, 0
                end)
                if ok and inside and area < bestArea and HasVisibleContent(child) then
                    bestFrame, bestName, bestArea = child, name, area
                end
            end
            -- Recurse into children regardless of whether this child is named
            local deeperFrame, deeperName, deeperArea = FindDeepestNamedChild(child, cx, cy)
            if deeperFrame and deeperArea < bestArea then
                bestFrame, bestName, bestArea = deeperFrame, deeperName, deeperArea
            end
        end
    end
    return bestFrame, bestName, bestArea
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
        local scanElapsed = 0
        overlay:SetScript("OnUpdate", function(self, dt)
            -- Compute cursor position in UIParent coordinates (needed for all paths)
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale

            local resolvedFrame, name

            -- Try GetMouseFoci first
            local foci = GetMouseFoci()
            local focus = foci and foci[1]
            if focus and focus ~= WorldFrame then
                resolvedFrame, name = ResolveNamedFrame(focus)
            end

            -- If GetMouseFoci didn't find a useful frame, scan from UIParent
            -- Throttle the full scan to avoid per-frame cost
            if not name or IsAddonFrame(name) then
                scanElapsed = scanElapsed + dt
                if scanElapsed >= 0.05 then
                    scanElapsed = 0
                    local scanFrame, scanName, scanArea = FindDeepestNamedChild(UIParent, cx, cy)
                    if scanFrame and scanName and not IsAddonFrame(scanName) then
                        -- Reject screen-sized containers (e.g. ElvUIParent)
                        local uiW, uiH = UIParent:GetSize()
                        if scanArea <= uiW * uiH * 0.25 then
                            resolvedFrame, name = scanFrame, scanName
                        end
                    end
                else
                    -- Between throttle ticks, reuse last result
                    resolvedFrame = self.lastResolvedFrame
                    name = self.currentName
                end
            else
                scanElapsed = 0
                -- GetMouseFoci found a named frame; try to find a deeper child
                local deepFrame, deepName = FindDeepestNamedChild(resolvedFrame, cx, cy)
                if deepFrame then
                    resolvedFrame, name = deepFrame, deepName
                end
            end

            if not name then
                self.label:SetText("")
                self.highlight:Hide()
                self.currentName = nil
                self.lastResolvedFrame = nil
                return
            end

            self.currentName = name
            self.lastResolvedFrame = resolvedFrame

            self.label:ClearAllPoints()
            self.label:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx + 20, cy + 10)
            self.label:SetText(name)

            -- Position highlight around the resolved frame
            local ok, left, bottom, width, height = pcall(resolvedFrame.GetRect, resolvedFrame)
            if ok and left and width and width > 0 and height > 0 then
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
        if spellName == "Single-Button Assistant" then
            CooldownCompanion:Print("Cannot track Single-Button Assistant")
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
    local charKey = CooldownCompanion.db.keys.char

    -- Split groups into global and character-owned, sorted by order
    local globalIds = {}
    local charIds = {}
    for id, group in pairs(db.groups) do
        if group.isGlobal then
            table.insert(globalIds, id)
        elseif group.createdBy == charKey then
            table.insert(charIds, id)
        end
    end
    local function sortByOrder(a, b)
        local orderA = db.groups[a].order or a
        local orderB = db.groups[b].order or b
        return orderA < orderB
    end
    table.sort(globalIds, sortByOrder)
    table.sort(charIds, sortByOrder)

    -- Count current children in scroll widget
    local function CountScrollChildren()
        local children = { col1Scroll.content:GetChildren() }
        return #children
    end

    -- Helper: render a single group row (reused by both sections)
    local function RenderGroupRow(groupId, listIndex, sectionGroupIds, sectionChildOffset)
        local group = db.groups[groupId]
        if not group then return end

        local btn = AceGUI:Create("Button")

        -- Build label with spec icons (1-3) or count (4+)
        local specTag = ""
        if group.specs and next(group.specs) then
            local count = 0
            for _ in pairs(group.specs) do count = count + 1 end
            if count >= 4 then
                specTag = "|cffaaaaaa(" .. count .. ")|r "
            else
                local icons = {}
                for specId in pairs(group.specs) do
                    local _, _, _, icon = GetSpecializationInfoForSpecID(specId)
                    if icon then
                        table.insert(icons, "|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t")
                    end
                end
                if #icons > 0 then
                    specTag = table.concat(icons, " ") .. " "
                end
            end
        end
        local globalTag = group.isGlobal and "|cff66aaff[G]|r " or ""
        local label = globalTag .. specTag .. group.name
        local indicators = {}
        if group.enabled == false then
            table.insert(indicators, "|cff888888OFF|r")
        end
        if not group.locked then
            table.insert(indicators, "|cffdddd00U|r")
        end
        if group.displayMode == "bars" then
            table.insert(indicators, "|cff66ccffBAR|r")
        end
        if #indicators > 0 then
            label = label .. " " .. table.concat(indicators, " ")
        end
        btn:SetText(label)
        btn:SetFullWidth(true)

        -- Auto-height: enable word wrap and resize if text is too long
        local btnText = btn.frame:GetFontString()
        if btnText and col1Scroll then
            btnText:SetWordWrap(true)
            btnText:SetNonSpaceWrap(true)
            -- Pre-calculate height based on scroll container width
            local function AdjustButtonHeight()
                local scrollWidth = col1Scroll.content:GetWidth()
                if scrollWidth and scrollWidth > 20 then
                    local padding = 20  -- button internal padding
                    btnText:SetWidth(scrollWidth - padding)
                    local textHeight = btnText:GetStringHeight()
                    local minHeight = 24
                    if textHeight and textHeight > minHeight then
                        btn:SetHeight(textHeight + 8)
                    end
                    return true
                end
                return false
            end
            -- Try immediately, fall back to deferred if width not ready
            if not AdjustButtonHeight() then
                C_Timer.After(0, function()
                    if btn.frame and col1Scroll then
                        AdjustButtonHeight()
                        col1Scroll:DoLayout()
                    end
                end)
            end
        end

        -- Apply green color for selected group (after height measurement)
        if selectedGroup == groupId then
            btn:SetText("|cff00ff00" .. label .. "|r")
        end
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
                end
                return
            end
            if mouseButton == "RightButton" then
                if not groupContextMenu then
                    groupContextMenu = CreateFrame("Frame", "CDCGroupContextMenu", UIParent, "UIDropDownMenuTemplate")
                end
                UIDropDownMenu_Initialize(groupContextMenu, function(self, level)
                    -- Rename
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = "Rename"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        ShowPopupAboveConfig("CDC_RENAME_GROUP", group.name, { groupId = groupId })
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Toggle Global
                    info = UIDropDownMenu_CreateInfo()
                    info.text = group.isGlobal and "Make Character-Only" or "Make Global"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        if group.isGlobal and group.specs then
                            local hasForeign = false
                            local numSpecs = GetNumSpecializations()
                            local playerSpecIds = {}
                            for i = 1, numSpecs do
                                local specId = GetSpecializationInfo(i)
                                if specId then playerSpecIds[specId] = true end
                            end
                            for specId in pairs(group.specs) do
                                if not playerSpecIds[specId] then
                                    hasForeign = true
                                    break
                                end
                            end
                            if hasForeign then
                                ShowPopupAboveConfig("CDC_UNGLOBAL_GROUP", group.name, { groupId = groupId })
                                return
                            end
                        end
                        CooldownCompanion:ToggleGroupGlobal(groupId)
                        CooldownCompanion:RefreshConfigPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Toggle On/Off
                    info = UIDropDownMenu_CreateInfo()
                    info.text = (group.enabled ~= false) and "Disable" or "Enable"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        group.enabled = not (group.enabled ~= false)
                        CooldownCompanion:RefreshGroupFrame(groupId)
                        CooldownCompanion:RefreshConfigPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Duplicate
                    info = UIDropDownMenu_CreateInfo()
                    info.text = "Duplicate"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        local newGroupId = CooldownCompanion:DuplicateGroup(groupId)
                        if newGroupId then
                            selectedGroup = newGroupId
                            CooldownCompanion:RefreshConfigPanel()
                        end
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Switch display mode
                    info = UIDropDownMenu_CreateInfo()
                    info.text = group.displayMode == "bars" and "Switch to Icons" or "Switch to Bars"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        group.displayMode = (group.displayMode == "bars") and "icons" or "bars"
                        if group.displayMode == "bars" and group.masqueEnabled then
                            CooldownCompanion:ToggleGroupMasque(groupId, false)
                        end
                        CooldownCompanion:RefreshGroupFrame(groupId)
                        CooldownCompanion:RefreshConfigPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Delete
                    info = UIDropDownMenu_CreateInfo()
                    info.text = "|cffff4444Delete|r"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        local name = group and group.name or "this group"
                        ShowPopupAboveConfig("CDC_DELETE_GROUP", name, { groupId = groupId })
                    end
                    UIDropDownMenu_AddButton(info, level)
                end, "MENU")
                groupContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                ToggleDropDownMenu(1, nil, groupContextMenu, "cursor", 0, 0)
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

            -- Foreign specs: specs from other classes already toggled on
            local playerSpecIds = {}
            for i = 1, numSpecs do
                local specId = GetSpecializationInfo(i)
                if specId then playerSpecIds[specId] = true end
            end

            local foreignSpecs = {}
            if group.specs then
                for specId in pairs(group.specs) do
                    if not playerSpecIds[specId] then
                        table.insert(foreignSpecs, specId)
                    end
                end
            end

            if #foreignSpecs > 0 then
                table.sort(foreignSpecs)

                for _, specId in ipairs(foreignSpecs) do
                    local _, name, _, icon = GetSpecializationInfoForSpecID(specId)
                    if name then
                        local fcb = AceGUI:Create("CheckBox")
                        fcb:SetLabel(name)
                        if icon then fcb:SetImage(icon, 0.08, 0.92, 0.08, 0.92) end
                        fcb:SetFullWidth(true)
                        fcb:SetValue(true)
                        fcb:SetCallback("OnValueChanged", function(widget, event, value)
                            if not value then
                                if group.specs then
                                    group.specs[specId] = nil
                                    if not next(group.specs) then
                                        group.specs = nil
                                    end
                                end
                            else
                                if not group.specs then group.specs = {} end
                                group.specs[specId] = true
                            end
                            CooldownCompanion:RefreshGroupFrame(groupId)
                            CooldownCompanion:RefreshConfigPanel()
                        end)
                        col1Scroll:AddChild(fcb)
                    end
                end
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
                    groupIds = sectionGroupIds,
                    scrollWidget = col1Scroll,
                    widget = row,
                    startY = cursorY,
                    childOffset = sectionChildOffset,
                    totalDraggable = #sectionGroupIds,
                }
                StartDragTracking()
            end
        end
    end

    -- Render "Global Groups" section
    if #globalIds > 0 then
        local globalHeading = AceGUI:Create("Heading")
        globalHeading:SetText("|cff66aaff" .. "Global Groups" .. "|r")
        globalHeading:SetFullWidth(true)
        col1Scroll:AddChild(globalHeading)

        local globalChildOffset = CountScrollChildren()
        for listIndex, groupId in ipairs(globalIds) do
            RenderGroupRow(groupId, listIndex, globalIds, globalChildOffset)
        end
    end

    -- Render character groups section
    if #charIds > 0 then
        local charName = charKey:match("^(.-)%s*%-") or charKey
        local charHeading = AceGUI:Create("Heading")
        charHeading:SetText(charName .. "'s Groups")
        charHeading:SetFullWidth(true)
        col1Scroll:AddChild(charHeading)

        local charChildOffset = CountScrollChildren()
        for listIndex, groupId in ipairs(charIds) do
            RenderGroupRow(groupId, listIndex, charIds, charChildOffset)
        end
    end

    -- Refresh the static button bar at the bottom
    if col1ButtonBar then
        -- Release previous bar widgets
        for _, widget in ipairs(col1BarWidgets) do
            widget:Release()
        end
        wipe(col1BarWidgets)

        -- Helper: generate a unique group name with the given base
        local function GenerateGroupName(base)
            local db = CooldownCompanion.db.profile
            local existing = {}
            for _, g in pairs(db.groups) do
                existing[g.name] = true
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

        -- "New Icon Group" button (left half)
        local newIconBtn = AceGUI:Create("Button")
        newIconBtn:SetText("New Icon Group")
        newIconBtn:SetCallback("OnClick", function()
            local groupId = CooldownCompanion:CreateGroup(GenerateGroupName("New Group"))
            selectedGroup = groupId
            selectedButton = nil
            wipe(selectedButtons)
            CooldownCompanion:RefreshConfigPanel()
        end)
        newIconBtn.frame:SetParent(col1ButtonBar)
        newIconBtn.frame:ClearAllPoints()
        newIconBtn.frame:SetPoint("TOPLEFT", col1ButtonBar, "TOPLEFT", 0, 0)
        newIconBtn.frame:SetPoint("BOTTOMRIGHT", col1ButtonBar, "BOTTOM", -2, 0)
        newIconBtn.frame:Show()
        table.insert(col1BarWidgets, newIconBtn)

        -- "New Bar Group" button (right half)
        local newBarBtn = AceGUI:Create("Button")
        newBarBtn:SetText("New Bar Group")
        newBarBtn:SetCallback("OnClick", function()
            local groupId = CooldownCompanion:CreateGroup(GenerateGroupName("New Group"))
            local group = CooldownCompanion.db.profile.groups[groupId]
            group.displayMode = "bars"
            if group.masqueEnabled then
                CooldownCompanion:ToggleGroupMasque(groupId, false)
            end
            CooldownCompanion:RefreshGroupFrame(groupId)
            selectedGroup = groupId
            selectedButton = nil
            wipe(selectedButtons)
            CooldownCompanion:RefreshConfigPanel()
        end)
        newBarBtn.frame:SetParent(col1ButtonBar)
        newBarBtn.frame:ClearAllPoints()
        newBarBtn.frame:SetPoint("TOPLEFT", col1ButtonBar, "TOP", 2, 0)
        newBarBtn.frame:SetPoint("BOTTOMRIGHT", col1ButtonBar, "BOTTOMRIGHT", 0, 0)
        newBarBtn.frame:Show()
        table.insert(col1BarWidgets, newBarBtn)
    end
end

------------------------------------------------------------------------
-- COLUMN 2: Spells / Items
------------------------------------------------------------------------
function RefreshColumn2()
    if not col2Scroll then return end
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
    addBtn.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    addBtn:SetCallback("OnClick", function(_, _, button)
        if button == "RightButton" then
            if InCombatLockdown() then
                CooldownCompanion:Print("Cannot open spellbook during combat.")
                return
            end
            PlayerSpellsUtil.ToggleSpellBookFrame()
            return
        end
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
    -- childOffset = 4 (inputBox, spacer, addBtn, sep are the first 4 children before draggable entries)
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
                if not buttonContextMenu then
                    buttonContextMenu = CreateFrame("Frame", "CDCButtonContextMenu", UIParent, "UIDropDownMenuTemplate")
                end
                local sourceGroupId = selectedGroup
                local sourceIndex = i
                local entryData = buttonData
                UIDropDownMenu_Initialize(buttonContextMenu, function(self, level)
                    -- Duplicate option
                    local dupInfo = UIDropDownMenu_CreateInfo()
                    dupInfo.text = "Duplicate"
                    dupInfo.notCheckable = true
                    dupInfo.func = function()
                        -- Deep copy the button data
                        local copy = {}
                        for k, v in pairs(entryData) do
                            if type(v) == "table" then
                                copy[k] = {}
                                for k2, v2 in pairs(v) do
                                    copy[k][k2] = v2
                                end
                            else
                                copy[k] = v
                            end
                        end
                        -- Insert after current position
                        table.insert(CooldownCompanion.db.profile.groups[sourceGroupId].buttons, sourceIndex + 1, copy)
                        CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                        CooldownCompanion:RefreshConfigPanel()
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(dupInfo, level)
                    -- Remove option
                    local removeInfo = UIDropDownMenu_CreateInfo()
                    removeInfo.text = "Remove"
                    removeInfo.notCheckable = true
                    removeInfo.func = function()
                        CloseDropDownMenus()
                        local name = entryData.name or "this entry"
                        ShowPopupAboveConfig("CDC_DELETE_BUTTON", name, { groupId = sourceGroupId, buttonIndex = sourceIndex })
                    end
                    UIDropDownMenu_AddButton(removeInfo, level)
                end, "MENU")
                buttonContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                ToggleDropDownMenu(1, nil, buttonContextMenu, "cursor", 0, 0)
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
                        if CooldownCompanion:IsGroupVisibleToCurrentChar(id) then
                            table.insert(groupIds, id)
                        end
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
                    childOffset = 4,
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
                    if CooldownCompanion:IsGroupVisibleToCurrentChar(id) then
                        table.insert(groupIds, id)
                    end
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
    end
end

------------------------------------------------------------------------
-- BUTTON SETTINGS BUILDERS
------------------------------------------------------------------------
local function BuildSpellSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end

    local spellHeading = AceGUI:Create("Heading")
    spellHeading:SetText("Spell Settings")
    spellHeading:SetFullWidth(true)
    scroll:AddChild(spellHeading)

    -- Charge text customization controls (only for charge-based spells)
    if buttonData.hasCharges then
        local showChargeTextCb = AceGUI:Create("CheckBox")
        showChargeTextCb:SetLabel("Show Charge Count Text")
        showChargeTextCb:SetValue(buttonData.showChargeText or false)
        showChargeTextCb:SetFullWidth(true)
        showChargeTextCb:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.showChargeText = val or nil
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(showChargeTextCb)

        if buttonData.showChargeText then
        local chargeKey = selectedGroup .. "_" .. selectedButton .. "_charges"
        local chargesCollapsed = collapsedSections[chargeKey]

        -- Collapse toggle button
        local chargeCollapseBtn = CreateFrame("Button", nil, showChargeTextCb.frame)
        table.insert(buttonSettingsCollapseButtons, chargeCollapseBtn)
        chargeCollapseBtn:SetSize(16, 16)
        chargeCollapseBtn:SetPoint("LEFT", showChargeTextCb.checkbg, "RIGHT", showChargeTextCb.text:GetStringWidth() + 6, 0)
        local chargeCollapseArrow = chargeCollapseBtn:CreateTexture(nil, "ARTWORK")
        chargeCollapseArrow:SetSize(12, 12)
        chargeCollapseArrow:SetPoint("CENTER")
        chargeCollapseArrow:SetTexture("Interface\\AddOns\\CooldownCompanion\\Media\\arrow_underline_20x20")
        if chargesCollapsed then
            chargeCollapseArrow:SetRotation(math.rad(180))
        end
        chargeCollapseBtn:SetScript("OnClick", function()
            collapsedSections[chargeKey] = not collapsedSections[chargeKey]
            CooldownCompanion:RefreshConfigPanel()
        end)
        chargeCollapseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(chargesCollapsed and "Expand" or "Collapse")
            GameTooltip:Show()
        end)
        chargeCollapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        if not chargesCollapsed then
            local chargeFontSizeSlider = AceGUI:Create("Slider")
            chargeFontSizeSlider:SetLabel("Font Size")
            chargeFontSizeSlider:SetSliderValues(8, 32, 1)
            chargeFontSizeSlider:SetValue(buttonData.chargeFontSize or 12)
            chargeFontSizeSlider:SetFullWidth(true)
            chargeFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeFontSize = val
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            scroll:AddChild(chargeFontSizeSlider)

            local chargeFontDrop = AceGUI:Create("Dropdown")
            chargeFontDrop:SetLabel("Font")
            chargeFontDrop:SetList(fontOptions)
            chargeFontDrop:SetValue(buttonData.chargeFont or "Fonts\\FRIZQT__.TTF")
            chargeFontDrop:SetFullWidth(true)
            chargeFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeFont = val
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            scroll:AddChild(chargeFontDrop)

            local chargeOutlineDrop = AceGUI:Create("Dropdown")
            chargeOutlineDrop:SetLabel("Font Outline")
            chargeOutlineDrop:SetList(outlineOptions)
            chargeOutlineDrop:SetValue(buttonData.chargeFontOutline or "OUTLINE")
            chargeOutlineDrop:SetFullWidth(true)
            chargeOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeFontOutline = val
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            scroll:AddChild(chargeOutlineDrop)

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
            scroll:AddChild(chargeFontColor)

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
            scroll:AddChild(chargeFontColorMissing)

            local barNoIcon = group.displayMode == "bars" and not (group.style.showBarIcon ~= false)
            local defChargeAnchor = barNoIcon and "BOTTOM" or "BOTTOMRIGHT"
            local defChargeX = barNoIcon and 0 or -2
            local defChargeY = 2

            local chargeAnchorValues = {}
            for _, pt in ipairs(anchorPoints) do
                chargeAnchorValues[pt] = anchorPointLabels[pt]
            end
            local chargeAnchorDrop = AceGUI:Create("Dropdown")
            chargeAnchorDrop:SetLabel("Anchor Point")
            chargeAnchorDrop:SetList(chargeAnchorValues)
            chargeAnchorDrop:SetValue(buttonData.chargeAnchor or defChargeAnchor)
            chargeAnchorDrop:SetFullWidth(true)
            chargeAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeAnchor = val
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            scroll:AddChild(chargeAnchorDrop)

            local chargeXSlider = AceGUI:Create("Slider")
            chargeXSlider:SetLabel("X Offset")
            chargeXSlider:SetSliderValues(-20, 20, 1)
            chargeXSlider:SetValue(buttonData.chargeXOffset or defChargeX)
            chargeXSlider:SetFullWidth(true)
            chargeXSlider:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeXOffset = val
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            scroll:AddChild(chargeXSlider)

            local chargeYSlider = AceGUI:Create("Slider")
            chargeYSlider:SetLabel("Y Offset")
            chargeYSlider:SetSliderValues(-20, 20, 1)
            chargeYSlider:SetValue(buttonData.chargeYOffset or defChargeY)
            chargeYSlider:SetFullWidth(true)
            chargeYSlider:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeYOffset = val
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            scroll:AddChild(chargeYSlider)

            local chargeBreak = AceGUI:Create("Heading")
            chargeBreak:SetText("")
            chargeBreak:SetFullWidth(true)
            scroll:AddChild(chargeBreak)
        end -- not chargesCollapsed
        end -- showChargeText

        if group.displayMode == "bars" then
            if group.style and group.style.showCooldownText then
                local cdTextOnRechargeCb = AceGUI:Create("CheckBox")
                cdTextOnRechargeCb:SetLabel("Anchor Cooldown Text to Recharging Bar")
                cdTextOnRechargeCb:SetValue(buttonData.barCdTextOnRechargeBar or false)
                cdTextOnRechargeCb:SetFullWidth(true)
                cdTextOnRechargeCb:SetCallback("OnValueChanged", function(widget, event, val)
                    buttonData.barCdTextOnRechargeBar = val
                end)
                scroll:AddChild(cdTextOnRechargeCb)
            end

            local reverseChargesCb = AceGUI:Create("CheckBox")
            reverseChargesCb:SetLabel("Flip Charge Order")
            reverseChargesCb:SetValue(buttonData.barReverseCharges or false)
            reverseChargesCb:SetFullWidth(true)
            reverseChargesCb:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.barReverseCharges = val or nil
                CooldownCompanion:UpdateGroupStyle(selectedGroup)
            end)
            scroll:AddChild(reverseChargesCb)
        end
    end -- hasCharges

    -- Proc Glow toggle (hidden for bar mode)
    if group.displayMode ~= "bars" then
    local procCb = AceGUI:Create("CheckBox")
    procCb:SetLabel("Show Proc Glow")
    procCb:SetValue(buttonData.procGlow == true)
    procCb:SetFullWidth(true)
    procCb:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.procGlow = val
        if val then
            collapsedSections[selectedGroup .. "_" .. selectedButton .. "_procGlow"] = nil
        end
        CooldownCompanion:RefreshGroupFrame(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(procCb)

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
    table.insert(infoButtons, procInfo)
    if CooldownCompanion.db.profile.hideInfoButtons then
        procInfo:Hide()
    end

    if buttonData.procGlow == true then
        local procKey = selectedGroup .. "_" .. selectedButton .. "_procGlow"
        local procCollapsed = collapsedSections[procKey]

        -- Collapse toggle button
        local procCollapseBtn = CreateFrame("Button", nil, procCb.frame)
        table.insert(buttonSettingsCollapseButtons, procCollapseBtn)
        procCollapseBtn:SetSize(16, 16)
        procCollapseBtn:SetPoint("LEFT", procInfo, "RIGHT", 4, 0)
        local procCollapseArrow = procCollapseBtn:CreateTexture(nil, "ARTWORK")
        procCollapseArrow:SetSize(12, 12)
        procCollapseArrow:SetPoint("CENTER")
        procCollapseArrow:SetTexture("Interface\\AddOns\\CooldownCompanion\\Media\\arrow_underline_20x20")
        if procCollapsed then
            procCollapseArrow:SetRotation(math.rad(180))
        end
        procCollapseBtn:SetScript("OnClick", function()
            collapsedSections[procKey] = not collapsedSections[procKey]
            CooldownCompanion:RefreshConfigPanel()
        end)
        procCollapseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(procCollapsed and "Expand" or "Collapse")
            GameTooltip:Show()
        end)
        procCollapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        if not procCollapsed then
            -- Preview toggle (transient — not saved)
            local previewCb = AceGUI:Create("CheckBox")
            previewCb:SetLabel("Preview")
            -- Restore preview state from the button frame if it's still active
            local previewActive = false
            local gFrame = CooldownCompanion.groupFrames[selectedGroup]
            if gFrame then
                for _, btn in ipairs(gFrame.buttons) do
                    if btn.index == selectedButton and btn._procGlowPreview then
                        previewActive = true
                        break
                    end
                end
            end
            previewCb:SetValue(previewActive)
            previewCb:SetFullWidth(true)
            previewCb:SetCallback("OnValueChanged", function(widget, event, val)
                CooldownCompanion:SetProcGlowPreview(selectedGroup, selectedButton, val)
            end)
            scroll:AddChild(previewCb)

            -- (?) tooltip for preview
            local previewInfo = CreateFrame("Button", nil, previewCb.frame)
            previewInfo:SetSize(16, 16)
            previewInfo:SetPoint("LEFT", previewCb.checkbg, "RIGHT", previewCb.text:GetStringWidth() + 4, 0)
            local previewInfoText = previewInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            previewInfoText:SetPoint("CENTER")
            previewInfoText:SetText("|cff66aaff(?)|r")
            previewInfo:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Preview")
                GameTooltip:AddLine("Shows what the proc glow looks like on this icon. You may need to toggle preview off and on to reflect changes to glow size.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            previewInfo:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            table.insert(infoButtons, previewInfo)
            if CooldownCompanion.db.profile.hideInfoButtons then
                previewInfo:Hide()
            end

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
                CooldownCompanion:InvalidateGroupProcGlow(selectedGroup)
            end)
            scroll:AddChild(procGlowColor)

            local procSizeSlider = AceGUI:Create("Slider")
            procSizeSlider:SetLabel("Glow Size")
            procSizeSlider:SetSliderValues(0, 60, 1)
            procSizeSlider:SetValue(group.style.procGlowOverhang or 32)
            procSizeSlider:SetFullWidth(true)
            procSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                group.style.procGlowOverhang = val
                CooldownCompanion:InvalidateGroupProcGlow(selectedGroup)
            end)
            scroll:AddChild(procSizeSlider)

            local procBreak = AceGUI:Create("Heading")
            procBreak:SetText("")
            procBreak:SetFullWidth(true)
            scroll:AddChild(procBreak)
        end
    end
    end -- not bars (proc glow)

    local auraCb = AceGUI:Create("CheckBox")
    auraCb:SetLabel("Track Buff Duration")
    auraCb:SetValue(buttonData.auraTracking == true)
    auraCb:SetFullWidth(true)
    auraCb:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.auraTracking = val or nil
        if val then
            collapsedSections[selectedGroup .. "_" .. selectedButton .. "_aura"] = nil
        end
        CooldownCompanion:RefreshGroupFrame(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(auraCb)

    -- (?) tooltip for aura tracking
    local auraInfo = CreateFrame("Button", nil, auraCb.frame)
    auraInfo:SetSize(16, 16)
    auraInfo:SetPoint("LEFT", auraCb.checkbg, "RIGHT", auraCb.text:GetStringWidth() + 4, 0)
    local auraInfoText = auraInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    auraInfoText:SetPoint("CENTER")
    auraInfoText:SetText("|cff66aaff(?)|r")
    auraInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Aura Tracking")
        GameTooltip:AddLine("When enabled, the cooldown swipe will show the remaining duration of the buff/aura associated with this spell instead of the spell's cooldown. When the buff expires, the normal cooldown display resumes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    auraInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(infoButtons, auraInfo)
    if CooldownCompanion.db.profile.hideInfoButtons then
        auraInfo:Hide()
    end

    -- Yellow (?) warning tooltip for aura tracking combat limitations
    local auraWarn = CreateFrame("Button", nil, auraCb.frame)
    auraWarn:SetSize(16, 16)
    auraWarn:SetPoint("LEFT", auraInfo, "RIGHT", 2, 0)
    local auraWarnText = auraWarn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    auraWarnText:SetPoint("CENTER")
    auraWarnText:SetText("|cffffcc00(?)|r")
    auraWarn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Combat Limitations")
        GameTooltip:AddLine("During combat, aura data is restricted by the game client. The addon uses an alternative tracking method that matches auras by comparing their duration to the last known duration observed outside of combat. Each aura can only be reliably tracked by one button at a time. If the same spell appears on multiple buttons, only one will track the aura correctly.\n\nIf you don't use the ability outside of combat at least once after toggling this option on, the cache will not populate and a fallback heuristic will be used in order to match the button to the correct aura.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    auraWarn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(infoButtons, auraWarn)
    if CooldownCompanion.db.profile.hideInfoButtons then
        auraWarn:Hide()
    end

    if buttonData.auraTracking then
        local auraKey = selectedGroup .. "_" .. selectedButton .. "_aura"
        local auraCollapsed = collapsedSections[auraKey]

        -- Collapse toggle button
        local auraCollapseBtn = CreateFrame("Button", nil, auraCb.frame)
        table.insert(buttonSettingsCollapseButtons, auraCollapseBtn)
        auraCollapseBtn:SetSize(16, 16)
        auraCollapseBtn:SetPoint("LEFT", auraWarn, "RIGHT", 4, 0)
        local auraCollapseArrow = auraCollapseBtn:CreateTexture(nil, "ARTWORK")
        auraCollapseArrow:SetSize(12, 12)
        auraCollapseArrow:SetPoint("CENTER")
        auraCollapseArrow:SetTexture("Interface\\AddOns\\CooldownCompanion\\Media\\arrow_underline_20x20")
        if auraCollapsed then
            auraCollapseArrow:SetRotation(math.rad(180))
        end
        auraCollapseBtn:SetScript("OnClick", function()
            collapsedSections[auraKey] = not collapsedSections[auraKey]
            CooldownCompanion:RefreshConfigPanel()
        end)
        auraCollapseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(auraCollapsed and "Expand" or "Collapse")
            GameTooltip:Show()
        end)
        auraCollapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        if not auraCollapsed then
            -- Show resolved aura info
            local autoAuraId = C_UnitAuras.GetCooldownAuraBySpellID(buttonData.id)
            local autoLabel = AceGUI:Create("Label")
            if autoAuraId and autoAuraId ~= 0 then
                local auraInfo = C_Spell.GetSpellInfo(autoAuraId)
                local auraName = auraInfo and auraInfo.name or ("Spell " .. autoAuraId)
                autoLabel:SetText("|cff88ff88Detected aura:|r " .. auraName .. " (ID: " .. autoAuraId .. ")")
            else
                local spellInfo = C_Spell.GetSpellInfo(buttonData.id)
                local spellName = spellInfo and spellInfo.name or ("Spell " .. buttonData.id)
                autoLabel:SetText("|cff88ff88Tracking aura:|r " .. spellName .. " (ID: " .. buttonData.id .. ")")
            end
            autoLabel:SetFullWidth(true)
            scroll:AddChild(autoLabel)

            -- Manual override edit box
            local auraEditBox = AceGUI:Create("EditBox")
            auraEditBox:SetLabel("Aura Spell ID Override")
            auraEditBox:SetText(buttonData.auraSpellID and tostring(buttonData.auraSpellID) or "")
            auraEditBox:SetFullWidth(true)
            auraEditBox:SetCallback("OnEnterPressed", function(widget, event, text)
                local id = tonumber(text)
                buttonData.auraSpellID = id
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(auraEditBox)

            -- (?) tooltip for override
            local overrideInfo = CreateFrame("Button", nil, auraEditBox.frame)
            overrideInfo:SetSize(16, 16)
            overrideInfo:SetPoint("LEFT", auraEditBox.editbox, "RIGHT", 4, 0)
            local overrideInfoText = overrideInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            overrideInfoText:SetPoint("CENTER")
            overrideInfoText:SetText("|cff66aaff(?)|r")
            overrideInfo:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Aura Spell ID Override")
                GameTooltip:AddLine("Enter a spell ID to track a specific aura instead of the auto-detected one. Leave blank to use auto-detection. You can find spell IDs on Wowhead.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            overrideInfo:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            table.insert(infoButtons, overrideInfo)
            if CooldownCompanion.db.profile.hideInfoButtons then
                overrideInfo:Hide()
            end

            local auraNoDesatCb = AceGUI:Create("CheckBox")
            auraNoDesatCb:SetLabel("Don't Desaturate While Active")
            auraNoDesatCb:SetValue(buttonData.auraNoDesaturate == true)
            auraNoDesatCb:SetFullWidth(true)
            auraNoDesatCb:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.auraNoDesaturate = val or nil
            end)
            scroll:AddChild(auraNoDesatCb)

            -- Active buff indicator controls (hidden for bar mode)
            if group.displayMode ~= "bars" then
            local auraGlowDrop = AceGUI:Create("Dropdown")
            auraGlowDrop:SetLabel("Active Buff Indicator")
            auraGlowDrop:SetList({
                ["none"] = "None",
                ["solid"] = "Solid Border",
                ["glow"] = "Glow",
            }, {"none", "solid", "glow"})
            auraGlowDrop:SetValue(buttonData.auraGlowStyle or "none")
            auraGlowDrop:SetFullWidth(true)
            auraGlowDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.auraGlowStyle = (val ~= "none") and val or nil
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(auraGlowDrop)

            if buttonData.auraGlowStyle and buttonData.auraGlowStyle ~= "none" then
                local auraGlowColorPicker = AceGUI:Create("ColorPicker")
                auraGlowColorPicker:SetLabel("Indicator Color")
                local agc = buttonData.auraGlowColor or {1, 0.84, 0, 0.9}
                auraGlowColorPicker:SetColor(agc[1], agc[2], agc[3], agc[4] or 0.9)
                auraGlowColorPicker:SetHasAlpha(true)
                auraGlowColorPicker:SetFullWidth(true)
                auraGlowColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                    buttonData.auraGlowColor = {r, g, b, a}
                end)
                auraGlowColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                    buttonData.auraGlowColor = {r, g, b, a}
                    CooldownCompanion:InvalidateAuraGlow(selectedGroup, selectedButton)
                end)
                scroll:AddChild(auraGlowColorPicker)

                if buttonData.auraGlowStyle == "solid" then
                    local auraGlowSizeSlider = AceGUI:Create("Slider")
                    auraGlowSizeSlider:SetLabel("Border Size")
                    auraGlowSizeSlider:SetSliderValues(1, 8, 1)
                    auraGlowSizeSlider:SetValue(buttonData.auraGlowSize or 2)
                    auraGlowSizeSlider:SetFullWidth(true)
                    auraGlowSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.auraGlowSize = val
                        CooldownCompanion:InvalidateAuraGlow(selectedGroup, selectedButton)
                    end)
                    scroll:AddChild(auraGlowSizeSlider)
                elseif buttonData.auraGlowStyle == "glow" then
                    local auraGlowSizeSlider = AceGUI:Create("Slider")
                    auraGlowSizeSlider:SetLabel("Glow Size")
                    auraGlowSizeSlider:SetSliderValues(0, 60, 1)
                    auraGlowSizeSlider:SetValue(buttonData.auraGlowSize or 32)
                    auraGlowSizeSlider:SetFullWidth(true)
                    auraGlowSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.auraGlowSize = val
                        CooldownCompanion:InvalidateAuraGlow(selectedGroup, selectedButton)
                    end)
                    scroll:AddChild(auraGlowSizeSlider)
                end

                -- Preview toggle
                local auraGlowPreviewCb = AceGUI:Create("CheckBox")
                auraGlowPreviewCb:SetLabel("Preview")
                local auraGlowPreviewActive = false
                local gFrame = CooldownCompanion.groupFrames[selectedGroup]
                if gFrame then
                    for _, btn in ipairs(gFrame.buttons) do
                        if btn.index == selectedButton and btn._auraGlowPreview then
                            auraGlowPreviewActive = true
                            break
                        end
                    end
                end
                auraGlowPreviewCb:SetValue(auraGlowPreviewActive)
                auraGlowPreviewCb:SetFullWidth(true)
                auraGlowPreviewCb:SetCallback("OnValueChanged", function(widget, event, val)
                    CooldownCompanion:SetAuraGlowPreview(selectedGroup, selectedButton, val)
                end)
                scroll:AddChild(auraGlowPreviewCb)
            end
            else -- bars: bar-specific aura effect controls
                local barAuraColorPicker = AceGUI:Create("ColorPicker")
                barAuraColorPicker:SetLabel("Bar Color While Active")
                barAuraColorPicker:SetHasAlpha(true)
                local bac = buttonData.barAuraColor or {0.2, 1.0, 0.2, 1.0}
                barAuraColorPicker:SetColor(bac[1], bac[2], bac[3], bac[4])
                barAuraColorPicker:SetFullWidth(true)
                barAuraColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                    buttonData.barAuraColor = {r, g, b, a}
                end)
                barAuraColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                    buttonData.barAuraColor = {r, g, b, a}
                end)
                scroll:AddChild(barAuraColorPicker)

                local barAuraEffectDrop = AceGUI:Create("Dropdown")
                barAuraEffectDrop:SetLabel("Bar Active Effect")
                barAuraEffectDrop:SetList({
                    ["none"] = "None",
                    ["pixel"] = "Pixel Glow",
                    ["solid"] = "Solid Border",
                    ["glow"] = "Proc Glow",
                }, {"none", "pixel", "solid", "glow"})
                barAuraEffectDrop:SetValue(buttonData.barAuraEffect or "none")
                barAuraEffectDrop:SetFullWidth(true)
                barAuraEffectDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    buttonData.barAuraEffect = (val ~= "none") and val or nil
                    CooldownCompanion:RefreshGroupFrame(selectedGroup)
                    CooldownCompanion:RefreshConfigPanel()
                end)
                scroll:AddChild(barAuraEffectDrop)

                if buttonData.barAuraEffect and buttonData.barAuraEffect ~= "none" then
                    local barAuraEffectColorPicker = AceGUI:Create("ColorPicker")
                    barAuraEffectColorPicker:SetLabel("Effect Color")
                    local baec = buttonData.barAuraEffectColor or {1, 0.84, 0, 0.9}
                    barAuraEffectColorPicker:SetColor(baec[1], baec[2], baec[3], baec[4] or 0.9)
                    barAuraEffectColorPicker:SetHasAlpha(true)
                    barAuraEffectColorPicker:SetFullWidth(true)
                    barAuraEffectColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                        buttonData.barAuraEffectColor = {r, g, b, a}
                        CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                    end)
                    barAuraEffectColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                        buttonData.barAuraEffectColor = {r, g, b, a}
                        CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                    end)
                    scroll:AddChild(barAuraEffectColorPicker)

                    if buttonData.barAuraEffect == "solid" then
                        local barAuraEffectSizeSlider = AceGUI:Create("Slider")
                        barAuraEffectSizeSlider:SetLabel("Border Size")
                        barAuraEffectSizeSlider:SetSliderValues(1, 8, 1)
                        barAuraEffectSizeSlider:SetValue(buttonData.barAuraEffectSize or 2)
                        barAuraEffectSizeSlider:SetFullWidth(true)
                        barAuraEffectSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSize = val
                            CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectSizeSlider)
                    elseif buttonData.barAuraEffect == "pixel" then
                        local barAuraEffectSizeSlider = AceGUI:Create("Slider")
                        barAuraEffectSizeSlider:SetLabel("Line Length")
                        barAuraEffectSizeSlider:SetSliderValues(2, 12, 1)
                        barAuraEffectSizeSlider:SetValue(buttonData.barAuraEffectSize or 4)
                        barAuraEffectSizeSlider:SetFullWidth(true)
                        barAuraEffectSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSize = val
                            CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectSizeSlider)
                        local barAuraEffectThicknessSlider = AceGUI:Create("Slider")
                        barAuraEffectThicknessSlider:SetLabel("Line Thickness")
                        barAuraEffectThicknessSlider:SetSliderValues(1, 6, 1)
                        barAuraEffectThicknessSlider:SetValue(buttonData.barAuraEffectThickness or 2)
                        barAuraEffectThicknessSlider:SetFullWidth(true)
                        barAuraEffectThicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectThickness = val
                            CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectThicknessSlider)
                        local barAuraEffectSpeedSlider = AceGUI:Create("Slider")
                        barAuraEffectSpeedSlider:SetLabel("Speed")
                        barAuraEffectSpeedSlider:SetSliderValues(10, 200, 5)
                        barAuraEffectSpeedSlider:SetValue(buttonData.barAuraEffectSpeed or 60)
                        barAuraEffectSpeedSlider:SetFullWidth(true)
                        barAuraEffectSpeedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSpeed = val
                            -- Update speed live without invalidating (no visual state change)
                            local gFrame = CooldownCompanion.groupFrames[selectedGroup]
                            if gFrame then
                                for _, btn in ipairs(gFrame.buttons) do
                                    if btn.index == selectedButton and btn.barAuraEffect and btn.barAuraEffect.pixelFrame then
                                        btn.barAuraEffect.pixelFrame._speed = val
                                    end
                                end
                            end
                        end)
                        scroll:AddChild(barAuraEffectSpeedSlider)
                    elseif buttonData.barAuraEffect == "glow" then
                        local barAuraEffectSizeSlider = AceGUI:Create("Slider")
                        barAuraEffectSizeSlider:SetLabel("Glow Size")
                        barAuraEffectSizeSlider:SetSliderValues(0, 60, 1)
                        barAuraEffectSizeSlider:SetValue(buttonData.barAuraEffectSize or 32)
                        barAuraEffectSizeSlider:SetFullWidth(true)
                        barAuraEffectSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSize = val
                            CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectSizeSlider)
                    end

                    -- Preview toggle
                    local barAuraPreviewCb = AceGUI:Create("CheckBox")
                    barAuraPreviewCb:SetLabel("Preview")
                    local barAuraPreviewActive = false
                    local gFrame = CooldownCompanion.groupFrames[selectedGroup]
                    if gFrame then
                        for _, btn in ipairs(gFrame.buttons) do
                            if btn.index == selectedButton and btn._barAuraEffectPreview then
                                barAuraPreviewActive = true
                                break
                            end
                        end
                    end
                    barAuraPreviewCb:SetValue(barAuraPreviewActive)
                    barAuraPreviewCb:SetFullWidth(true)
                    barAuraPreviewCb:SetCallback("OnValueChanged", function(widget, event, val)
                        CooldownCompanion:SetBarAuraEffectPreview(selectedGroup, selectedButton, val)
                    end)
                    scroll:AddChild(barAuraPreviewCb)
                end
            end -- bars/icons aura effect branch
        end
    end

    if buttonData.hasCharges and group.displayMode == "bars" then
        local chargeBarBreak = AceGUI:Create("Heading")
        chargeBarBreak:SetText("")
        chargeBarBreak:SetFullWidth(true)
        scroll:AddChild(chargeBarBreak)

        local chargeGapSlider = AceGUI:Create("Slider")
        chargeGapSlider:SetLabel("Charge Bar Gap")
        chargeGapSlider:SetSliderValues(0, 20, 1)
        chargeGapSlider:SetValue(buttonData.barChargeGap or 2)
        chargeGapSlider:SetFullWidth(true)
        chargeGapSlider:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.barChargeGap = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        scroll:AddChild(chargeGapSlider)
    end
end

local function BuildItemSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end

    local itemHeading = AceGUI:Create("Heading")
    itemHeading:SetText("Item Settings")
    itemHeading:SetFullWidth(true)
    scroll:AddChild(itemHeading)

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
    scroll:AddChild(itemFontSizeSlider)

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
    scroll:AddChild(itemFontDrop)

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
    scroll:AddChild(itemOutlineDrop)

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
    scroll:AddChild(itemFontColor)

    -- Item count anchor point
    local barNoIcon = group.displayMode == "bars" and not (group.style.showBarIcon ~= false)
    local defItemAnchor = barNoIcon and "BOTTOM" or "BOTTOMRIGHT"
    local defItemX = barNoIcon and 0 or -2
    local defItemY = 2

    local itemAnchorValues = {}
    for _, pt in ipairs(anchorPoints) do
        itemAnchorValues[pt] = anchorPointLabels[pt]
    end
    local itemAnchorDrop = AceGUI:Create("Dropdown")
    itemAnchorDrop:SetLabel("Anchor Point")
    itemAnchorDrop:SetList(itemAnchorValues)
    itemAnchorDrop:SetValue(buttonData.itemCountAnchor or defItemAnchor)
    itemAnchorDrop:SetFullWidth(true)
    itemAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountAnchor = val
        CooldownCompanion:RefreshGroupFrame(selectedGroup)
    end)
    scroll:AddChild(itemAnchorDrop)

    -- Item count X offset
    local itemXSlider = AceGUI:Create("Slider")
    itemXSlider:SetLabel("X Offset")
    itemXSlider:SetSliderValues(-20, 20, 1)
    itemXSlider:SetValue(buttonData.itemCountXOffset or defItemX)
    itemXSlider:SetFullWidth(true)
    itemXSlider:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountXOffset = val
        CooldownCompanion:RefreshGroupFrame(selectedGroup)
    end)
    scroll:AddChild(itemXSlider)

    -- Item count Y offset
    local itemYSlider = AceGUI:Create("Slider")
    itemYSlider:SetLabel("Y Offset")
    itemYSlider:SetSliderValues(-20, 20, 1)
    itemYSlider:SetValue(buttonData.itemCountYOffset or defItemY)
    itemYSlider:SetFullWidth(true)
    itemYSlider:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountYOffset = val
        CooldownCompanion:RefreshGroupFrame(selectedGroup)
    end)
    scroll:AddChild(itemYSlider)

    local itemAuraCb = AceGUI:Create("CheckBox")
    itemAuraCb:SetLabel("Track Buff Duration")
    itemAuraCb:SetValue(buttonData.auraTracking == true)
    itemAuraCb:SetFullWidth(true)
    itemAuraCb:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.auraTracking = val or nil
        if val then
            collapsedSections[selectedGroup .. "_" .. selectedButton .. "_itemAura"] = nil
        end
        CooldownCompanion:RefreshGroupFrame(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(itemAuraCb)

    -- (?) tooltip for aura tracking (items)
    local itemAuraInfo = CreateFrame("Button", nil, itemAuraCb.frame)
    itemAuraInfo:SetSize(16, 16)
    itemAuraInfo:SetPoint("LEFT", itemAuraCb.checkbg, "RIGHT", itemAuraCb.text:GetStringWidth() + 4, 0)
    local itemAuraInfoText = itemAuraInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemAuraInfoText:SetPoint("CENTER")
    itemAuraInfoText:SetText("|cff66aaff(?)|r")
    itemAuraInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Aura Tracking")
        GameTooltip:AddLine("When enabled, the cooldown swipe will show the remaining duration of the buff/aura instead of the item's cooldown. For items, you must provide the aura spell ID manually.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    itemAuraInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(infoButtons, itemAuraInfo)
    if CooldownCompanion.db.profile.hideInfoButtons then
        itemAuraInfo:Hide()
    end

    -- Yellow (?) warning tooltip for aura tracking combat limitations (items)
    local itemAuraWarn = CreateFrame("Button", nil, itemAuraCb.frame)
    itemAuraWarn:SetSize(16, 16)
    itemAuraWarn:SetPoint("LEFT", itemAuraInfo, "RIGHT", 2, 0)
    local itemAuraWarnText = itemAuraWarn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemAuraWarnText:SetPoint("CENTER")
    itemAuraWarnText:SetText("|cffffcc00(?)|r")
    itemAuraWarn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Combat Limitations")
        GameTooltip:AddLine("During combat, aura data is restricted by the game client. The addon uses an alternative tracking method that matches auras by comparing their duration to the last known duration observed outside of combat. Each aura can only be reliably tracked by one button at a time. If the same spell appears on multiple buttons, only one will track the aura correctly.\n\nIf you don't use the ability outside of combat at least once after toggling this option on, the cache will not populate and a fallback heuristic will be used in order to match the button to the correct aura.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    itemAuraWarn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(infoButtons, itemAuraWarn)
    if CooldownCompanion.db.profile.hideInfoButtons then
        itemAuraWarn:Hide()
    end

    if buttonData.auraTracking then
        local itemAuraKey = selectedGroup .. "_" .. selectedButton .. "_itemAura"
        local itemAuraCollapsed = collapsedSections[itemAuraKey]

        -- Collapse toggle button
        local itemAuraCollapseBtn = CreateFrame("Button", nil, itemAuraCb.frame)
        table.insert(buttonSettingsCollapseButtons, itemAuraCollapseBtn)
        itemAuraCollapseBtn:SetSize(16, 16)
        itemAuraCollapseBtn:SetPoint("LEFT", itemAuraWarn, "RIGHT", 4, 0)
        local itemAuraCollapseArrow = itemAuraCollapseBtn:CreateTexture(nil, "ARTWORK")
        itemAuraCollapseArrow:SetSize(12, 12)
        itemAuraCollapseArrow:SetPoint("CENTER")
        itemAuraCollapseArrow:SetTexture("Interface\\AddOns\\CooldownCompanion\\Media\\arrow_underline_20x20")
        if itemAuraCollapsed then
            itemAuraCollapseArrow:SetRotation(math.rad(180))
        end
        itemAuraCollapseBtn:SetScript("OnClick", function()
            collapsedSections[itemAuraKey] = not collapsedSections[itemAuraKey]
            CooldownCompanion:RefreshConfigPanel()
        end)
        itemAuraCollapseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(itemAuraCollapsed and "Expand" or "Collapse")
            GameTooltip:Show()
        end)
        itemAuraCollapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        if not itemAuraCollapsed then
            local itemAutoLabel = AceGUI:Create("Label")
            itemAutoLabel:SetText("|cffaaaaaaAuto-detection not available for items.|r Use the override field below.")
            itemAutoLabel:SetFullWidth(true)
            scroll:AddChild(itemAutoLabel)

            local itemAuraEditBox = AceGUI:Create("EditBox")
            itemAuraEditBox:SetLabel("Aura Spell ID Override")
            itemAuraEditBox:SetText(buttonData.auraSpellID and tostring(buttonData.auraSpellID) or "")
            itemAuraEditBox:SetFullWidth(true)
            itemAuraEditBox:SetCallback("OnEnterPressed", function(widget, event, text)
                local id = tonumber(text)
                buttonData.auraSpellID = id
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(itemAuraEditBox)

            -- (?) tooltip for item override
            local itemOverrideInfo = CreateFrame("Button", nil, itemAuraEditBox.frame)
            itemOverrideInfo:SetSize(16, 16)
            itemOverrideInfo:SetPoint("LEFT", itemAuraEditBox.editbox, "RIGHT", 4, 0)
            local itemOverrideInfoText = itemOverrideInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            itemOverrideInfoText:SetPoint("CENTER")
            itemOverrideInfoText:SetText("|cff66aaff(?)|r")
            itemOverrideInfo:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Aura Spell ID Override")
                GameTooltip:AddLine("Enter the spell ID of the buff/aura this item applies. You can find spell IDs on Wowhead.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            itemOverrideInfo:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            table.insert(infoButtons, itemOverrideInfo)
            if CooldownCompanion.db.profile.hideInfoButtons then
                itemOverrideInfo:Hide()
            end

            local itemAuraNoDesatCb = AceGUI:Create("CheckBox")
            itemAuraNoDesatCb:SetLabel("Don't Desaturate While Active")
            itemAuraNoDesatCb:SetValue(buttonData.auraNoDesaturate == true)
            itemAuraNoDesatCb:SetFullWidth(true)
            itemAuraNoDesatCb:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.auraNoDesaturate = val or nil
            end)
            scroll:AddChild(itemAuraNoDesatCb)

            -- Active buff indicator controls (non-equip items, hidden for bar mode)
            if group.displayMode ~= "bars" then
            local itemAuraGlowDrop = AceGUI:Create("Dropdown")
            itemAuraGlowDrop:SetLabel("Active Buff Indicator")
            itemAuraGlowDrop:SetList({
                ["none"] = "None",
                ["solid"] = "Solid Border",
                ["glow"] = "Glow",
            }, {"none", "solid", "glow"})
            itemAuraGlowDrop:SetValue(buttonData.auraGlowStyle or "none")
            itemAuraGlowDrop:SetFullWidth(true)
            itemAuraGlowDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.auraGlowStyle = (val ~= "none") and val or nil
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(itemAuraGlowDrop)

            if buttonData.auraGlowStyle and buttonData.auraGlowStyle ~= "none" then
                local itemAuraGlowColorPicker = AceGUI:Create("ColorPicker")
                itemAuraGlowColorPicker:SetLabel("Indicator Color")
                local agc = buttonData.auraGlowColor or {1, 0.84, 0, 0.9}
                itemAuraGlowColorPicker:SetColor(agc[1], agc[2], agc[3], agc[4] or 0.9)
                itemAuraGlowColorPicker:SetHasAlpha(true)
                itemAuraGlowColorPicker:SetFullWidth(true)
                itemAuraGlowColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                    buttonData.auraGlowColor = {r, g, b, a}
                end)
                itemAuraGlowColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                    buttonData.auraGlowColor = {r, g, b, a}
                    CooldownCompanion:InvalidateAuraGlow(selectedGroup, selectedButton)
                end)
                scroll:AddChild(itemAuraGlowColorPicker)

                if buttonData.auraGlowStyle == "solid" then
                    local itemAuraGlowSizeSlider = AceGUI:Create("Slider")
                    itemAuraGlowSizeSlider:SetLabel("Border Size")
                    itemAuraGlowSizeSlider:SetSliderValues(1, 8, 1)
                    itemAuraGlowSizeSlider:SetValue(buttonData.auraGlowSize or 2)
                    itemAuraGlowSizeSlider:SetFullWidth(true)
                    itemAuraGlowSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.auraGlowSize = val
                        CooldownCompanion:InvalidateAuraGlow(selectedGroup, selectedButton)
                    end)
                    scroll:AddChild(itemAuraGlowSizeSlider)
                elseif buttonData.auraGlowStyle == "glow" then
                    local itemAuraGlowSizeSlider = AceGUI:Create("Slider")
                    itemAuraGlowSizeSlider:SetLabel("Glow Size")
                    itemAuraGlowSizeSlider:SetSliderValues(0, 60, 1)
                    itemAuraGlowSizeSlider:SetValue(buttonData.auraGlowSize or 32)
                    itemAuraGlowSizeSlider:SetFullWidth(true)
                    itemAuraGlowSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.auraGlowSize = val
                        CooldownCompanion:InvalidateAuraGlow(selectedGroup, selectedButton)
                    end)
                    scroll:AddChild(itemAuraGlowSizeSlider)
                end

                -- Preview toggle
                local itemAuraGlowPreviewCb = AceGUI:Create("CheckBox")
                itemAuraGlowPreviewCb:SetLabel("Preview")
                local itemAuraGlowPreviewActive = false
                local gFrame = CooldownCompanion.groupFrames[selectedGroup]
                if gFrame then
                    for _, btn in ipairs(gFrame.buttons) do
                        if btn.index == selectedButton and btn._auraGlowPreview then
                            itemAuraGlowPreviewActive = true
                            break
                        end
                    end
                end
                itemAuraGlowPreviewCb:SetValue(itemAuraGlowPreviewActive)
                itemAuraGlowPreviewCb:SetFullWidth(true)
                itemAuraGlowPreviewCb:SetCallback("OnValueChanged", function(widget, event, val)
                    CooldownCompanion:SetAuraGlowPreview(selectedGroup, selectedButton, val)
                end)
                scroll:AddChild(itemAuraGlowPreviewCb)
            end
            else -- bars: bar-specific aura effect controls
                local barAuraColorPicker = AceGUI:Create("ColorPicker")
                barAuraColorPicker:SetLabel("Bar Color While Active")
                barAuraColorPicker:SetHasAlpha(true)
                local bac = buttonData.barAuraColor or {0.2, 1.0, 0.2, 1.0}
                barAuraColorPicker:SetColor(bac[1], bac[2], bac[3], bac[4])
                barAuraColorPicker:SetFullWidth(true)
                barAuraColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                    buttonData.barAuraColor = {r, g, b, a}
                end)
                barAuraColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                    buttonData.barAuraColor = {r, g, b, a}
                end)
                scroll:AddChild(barAuraColorPicker)

                local barAuraEffectDrop = AceGUI:Create("Dropdown")
                barAuraEffectDrop:SetLabel("Bar Active Effect")
                barAuraEffectDrop:SetList({
                    ["none"] = "None",
                    ["pixel"] = "Pixel Glow",
                    ["solid"] = "Solid Border",
                    ["glow"] = "Proc Glow",
                }, {"none", "pixel", "solid", "glow"})
                barAuraEffectDrop:SetValue(buttonData.barAuraEffect or "none")
                barAuraEffectDrop:SetFullWidth(true)
                barAuraEffectDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    buttonData.barAuraEffect = (val ~= "none") and val or nil
                    CooldownCompanion:RefreshGroupFrame(selectedGroup)
                    CooldownCompanion:RefreshConfigPanel()
                end)
                scroll:AddChild(barAuraEffectDrop)

                if buttonData.barAuraEffect and buttonData.barAuraEffect ~= "none" then
                    local barAuraEffectColorPicker = AceGUI:Create("ColorPicker")
                    barAuraEffectColorPicker:SetLabel("Effect Color")
                    local baec = buttonData.barAuraEffectColor or {1, 0.84, 0, 0.9}
                    barAuraEffectColorPicker:SetColor(baec[1], baec[2], baec[3], baec[4] or 0.9)
                    barAuraEffectColorPicker:SetHasAlpha(true)
                    barAuraEffectColorPicker:SetFullWidth(true)
                    barAuraEffectColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                        buttonData.barAuraEffectColor = {r, g, b, a}
                        CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                    end)
                    barAuraEffectColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                        buttonData.barAuraEffectColor = {r, g, b, a}
                        CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                    end)
                    scroll:AddChild(barAuraEffectColorPicker)

                    if buttonData.barAuraEffect == "solid" then
                        local barAuraEffectSizeSlider = AceGUI:Create("Slider")
                        barAuraEffectSizeSlider:SetLabel("Border Size")
                        barAuraEffectSizeSlider:SetSliderValues(1, 8, 1)
                        barAuraEffectSizeSlider:SetValue(buttonData.barAuraEffectSize or 2)
                        barAuraEffectSizeSlider:SetFullWidth(true)
                        barAuraEffectSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSize = val
                            CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectSizeSlider)
                    elseif buttonData.barAuraEffect == "pixel" then
                        local barAuraEffectSizeSlider = AceGUI:Create("Slider")
                        barAuraEffectSizeSlider:SetLabel("Line Length")
                        barAuraEffectSizeSlider:SetSliderValues(2, 12, 1)
                        barAuraEffectSizeSlider:SetValue(buttonData.barAuraEffectSize or 4)
                        barAuraEffectSizeSlider:SetFullWidth(true)
                        barAuraEffectSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSize = val
                            CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectSizeSlider)
                        local barAuraEffectThicknessSlider = AceGUI:Create("Slider")
                        barAuraEffectThicknessSlider:SetLabel("Line Thickness")
                        barAuraEffectThicknessSlider:SetSliderValues(1, 6, 1)
                        barAuraEffectThicknessSlider:SetValue(buttonData.barAuraEffectThickness or 2)
                        barAuraEffectThicknessSlider:SetFullWidth(true)
                        barAuraEffectThicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectThickness = val
                            CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectThicknessSlider)
                        local barAuraEffectSpeedSlider = AceGUI:Create("Slider")
                        barAuraEffectSpeedSlider:SetLabel("Speed")
                        barAuraEffectSpeedSlider:SetSliderValues(10, 200, 5)
                        barAuraEffectSpeedSlider:SetValue(buttonData.barAuraEffectSpeed or 60)
                        barAuraEffectSpeedSlider:SetFullWidth(true)
                        barAuraEffectSpeedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSpeed = val
                            -- Update speed live without invalidating (no visual state change)
                            local gFrame = CooldownCompanion.groupFrames[selectedGroup]
                            if gFrame then
                                for _, btn in ipairs(gFrame.buttons) do
                                    if btn.index == selectedButton and btn.barAuraEffect and btn.barAuraEffect.pixelFrame then
                                        btn.barAuraEffect.pixelFrame._speed = val
                                    end
                                end
                            end
                        end)
                        scroll:AddChild(barAuraEffectSpeedSlider)
                    elseif buttonData.barAuraEffect == "glow" then
                        local barAuraEffectSizeSlider = AceGUI:Create("Slider")
                        barAuraEffectSizeSlider:SetLabel("Glow Size")
                        barAuraEffectSizeSlider:SetSliderValues(0, 60, 1)
                        barAuraEffectSizeSlider:SetValue(buttonData.barAuraEffectSize or 32)
                        barAuraEffectSizeSlider:SetFullWidth(true)
                        barAuraEffectSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSize = val
                            CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectSizeSlider)
                    end

                    -- Preview toggle
                    local barAuraPreviewCb = AceGUI:Create("CheckBox")
                    barAuraPreviewCb:SetLabel("Preview")
                    local barAuraPreviewActive = false
                    local gFrame = CooldownCompanion.groupFrames[selectedGroup]
                    if gFrame then
                        for _, btn in ipairs(gFrame.buttons) do
                            if btn.index == selectedButton and btn._barAuraEffectPreview then
                                barAuraPreviewActive = true
                                break
                            end
                        end
                    end
                    barAuraPreviewCb:SetValue(barAuraPreviewActive)
                    barAuraPreviewCb:SetFullWidth(true)
                    barAuraPreviewCb:SetCallback("OnValueChanged", function(widget, event, val)
                        CooldownCompanion:SetBarAuraEffectPreview(selectedGroup, selectedButton, val)
                    end)
                    scroll:AddChild(barAuraPreviewCb)
                end
            end -- bars/icons aura effect branch
        end
    end

    if group.displayMode == "bars" then
        local chargeGapSlider = AceGUI:Create("Slider")
        chargeGapSlider:SetLabel("Charge Bar Gap")
        chargeGapSlider:SetSliderValues(0, 20, 1)
        chargeGapSlider:SetValue(buttonData.barChargeGap or 2)
        chargeGapSlider:SetFullWidth(true)
        chargeGapSlider:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.barChargeGap = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        scroll:AddChild(chargeGapSlider)

        local reverseChargesCb = AceGUI:Create("CheckBox")
        reverseChargesCb:SetLabel("Flip Charge Order")
        reverseChargesCb:SetValue(buttonData.barReverseCharges or false)
        reverseChargesCb:SetFullWidth(true)
        reverseChargesCb:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.barReverseCharges = val or nil
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        scroll:AddChild(reverseChargesCb)
    end
end

local function BuildEquipItemSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end

    local eqAuraCb = AceGUI:Create("CheckBox")
    eqAuraCb:SetLabel("Track Buff Duration")
    eqAuraCb:SetValue(buttonData.auraTracking == true)
    eqAuraCb:SetFullWidth(true)
    eqAuraCb:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.auraTracking = val or nil
        if val then
            collapsedSections[selectedGroup .. "_" .. selectedButton .. "_eqAura"] = nil
        end
        CooldownCompanion:RefreshGroupFrame(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(eqAuraCb)

    -- (?) tooltip for aura tracking (equippable items)
    local eqAuraInfo = CreateFrame("Button", nil, eqAuraCb.frame)
    eqAuraInfo:SetSize(16, 16)
    eqAuraInfo:SetPoint("LEFT", eqAuraCb.checkbg, "RIGHT", eqAuraCb.text:GetStringWidth() + 4, 0)
    local eqAuraInfoText = eqAuraInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eqAuraInfoText:SetPoint("CENTER")
    eqAuraInfoText:SetText("|cff66aaff(?)|r")
    eqAuraInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Aura Tracking")
        GameTooltip:AddLine("When enabled, the cooldown swipe will show the remaining duration of the buff/aura instead of the item's cooldown. For items, you must provide the aura spell ID manually.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    eqAuraInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(infoButtons, eqAuraInfo)
    if CooldownCompanion.db.profile.hideInfoButtons then
        eqAuraInfo:Hide()
    end

    -- Yellow (?) warning tooltip for aura tracking combat limitations (equippable items)
    local eqAuraWarn = CreateFrame("Button", nil, eqAuraCb.frame)
    eqAuraWarn:SetSize(16, 16)
    eqAuraWarn:SetPoint("LEFT", eqAuraInfo, "RIGHT", 2, 0)
    local eqAuraWarnText = eqAuraWarn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eqAuraWarnText:SetPoint("CENTER")
    eqAuraWarnText:SetText("|cffffcc00(?)|r")
    eqAuraWarn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Combat Limitations")
        GameTooltip:AddLine("During combat, aura data is restricted by the game client. The addon uses an alternative tracking method that matches auras by comparing their duration to the last known duration observed outside of combat. Each aura can only be reliably tracked by one button at a time. If the same spell appears on multiple buttons, only one will track the aura correctly.\n\nIf you don't use the ability outside of combat at least once after toggling this option on, the cache will not populate and a fallback heuristic will be used in order to match the button to the correct aura.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    eqAuraWarn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(infoButtons, eqAuraWarn)
    if CooldownCompanion.db.profile.hideInfoButtons then
        eqAuraWarn:Hide()
    end

    if buttonData.auraTracking then
        local eqAuraKey = selectedGroup .. "_" .. selectedButton .. "_eqAura"
        local eqAuraCollapsed = collapsedSections[eqAuraKey]

        -- Collapse toggle button
        local eqAuraCollapseBtn = CreateFrame("Button", nil, eqAuraCb.frame)
        table.insert(buttonSettingsCollapseButtons, eqAuraCollapseBtn)
        eqAuraCollapseBtn:SetSize(16, 16)
        eqAuraCollapseBtn:SetPoint("LEFT", eqAuraWarn, "RIGHT", 4, 0)
        local eqAuraCollapseArrow = eqAuraCollapseBtn:CreateTexture(nil, "ARTWORK")
        eqAuraCollapseArrow:SetSize(12, 12)
        eqAuraCollapseArrow:SetPoint("CENTER")
        eqAuraCollapseArrow:SetTexture("Interface\\AddOns\\CooldownCompanion\\Media\\arrow_underline_20x20")
        if eqAuraCollapsed then
            eqAuraCollapseArrow:SetRotation(math.rad(180))
        end
        eqAuraCollapseBtn:SetScript("OnClick", function()
            collapsedSections[eqAuraKey] = not collapsedSections[eqAuraKey]
            CooldownCompanion:RefreshConfigPanel()
        end)
        eqAuraCollapseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(eqAuraCollapsed and "Expand" or "Collapse")
            GameTooltip:Show()
        end)
        eqAuraCollapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        if not eqAuraCollapsed then
            local eqAutoLabel = AceGUI:Create("Label")
            eqAutoLabel:SetText("|cffaaaaaaAuto-detection not available for items.|r Use the override field below.")
            eqAutoLabel:SetFullWidth(true)
            scroll:AddChild(eqAutoLabel)

            local eqAuraEditBox = AceGUI:Create("EditBox")
            eqAuraEditBox:SetLabel("Aura Spell ID Override")
            eqAuraEditBox:SetText(buttonData.auraSpellID and tostring(buttonData.auraSpellID) or "")
            eqAuraEditBox:SetFullWidth(true)
            eqAuraEditBox:SetCallback("OnEnterPressed", function(widget, event, text)
                local id = tonumber(text)
                buttonData.auraSpellID = id
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(eqAuraEditBox)

            -- (?) tooltip for equippable item override
            local eqOverrideInfo = CreateFrame("Button", nil, eqAuraEditBox.frame)
            eqOverrideInfo:SetSize(16, 16)
            eqOverrideInfo:SetPoint("LEFT", eqAuraEditBox.editbox, "RIGHT", 4, 0)
            local eqOverrideInfoText = eqOverrideInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            eqOverrideInfoText:SetPoint("CENTER")
            eqOverrideInfoText:SetText("|cff66aaff(?)|r")
            eqOverrideInfo:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Aura Spell ID Override")
                GameTooltip:AddLine("Enter the spell ID of the buff/aura this item applies. You can find spell IDs on Wowhead.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            eqOverrideInfo:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            table.insert(infoButtons, eqOverrideInfo)
            if CooldownCompanion.db.profile.hideInfoButtons then
                eqOverrideInfo:Hide()
            end

            local eqAuraNoDesatCb = AceGUI:Create("CheckBox")
            eqAuraNoDesatCb:SetLabel("Don't Desaturate While Active")
            eqAuraNoDesatCb:SetValue(buttonData.auraNoDesaturate == true)
            eqAuraNoDesatCb:SetFullWidth(true)
            eqAuraNoDesatCb:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.auraNoDesaturate = val or nil
            end)
            scroll:AddChild(eqAuraNoDesatCb)

            -- Active buff indicator controls (equippable items, hidden for bar mode)
            if group.displayMode ~= "bars" then
            local eqAuraGlowDrop = AceGUI:Create("Dropdown")
            eqAuraGlowDrop:SetLabel("Active Buff Indicator")
            eqAuraGlowDrop:SetList({
                ["none"] = "None",
                ["solid"] = "Solid Border",
                ["glow"] = "Glow",
            }, {"none", "solid", "glow"})
            eqAuraGlowDrop:SetValue(buttonData.auraGlowStyle or "none")
            eqAuraGlowDrop:SetFullWidth(true)
            eqAuraGlowDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.auraGlowStyle = (val ~= "none") and val or nil
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(eqAuraGlowDrop)

            if buttonData.auraGlowStyle and buttonData.auraGlowStyle ~= "none" then
                local eqAuraGlowColorPicker = AceGUI:Create("ColorPicker")
                eqAuraGlowColorPicker:SetLabel("Indicator Color")
                local agc = buttonData.auraGlowColor or {1, 0.84, 0, 0.9}
                eqAuraGlowColorPicker:SetColor(agc[1], agc[2], agc[3], agc[4] or 0.9)
                eqAuraGlowColorPicker:SetHasAlpha(true)
                eqAuraGlowColorPicker:SetFullWidth(true)
                eqAuraGlowColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                    buttonData.auraGlowColor = {r, g, b, a}
                end)
                eqAuraGlowColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                    buttonData.auraGlowColor = {r, g, b, a}
                    CooldownCompanion:InvalidateAuraGlow(selectedGroup, selectedButton)
                end)
                scroll:AddChild(eqAuraGlowColorPicker)

                if buttonData.auraGlowStyle == "solid" then
                    local eqAuraGlowSizeSlider = AceGUI:Create("Slider")
                    eqAuraGlowSizeSlider:SetLabel("Border Size")
                    eqAuraGlowSizeSlider:SetSliderValues(1, 8, 1)
                    eqAuraGlowSizeSlider:SetValue(buttonData.auraGlowSize or 2)
                    eqAuraGlowSizeSlider:SetFullWidth(true)
                    eqAuraGlowSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.auraGlowSize = val
                        CooldownCompanion:InvalidateAuraGlow(selectedGroup, selectedButton)
                    end)
                    scroll:AddChild(eqAuraGlowSizeSlider)
                elseif buttonData.auraGlowStyle == "glow" then
                    local eqAuraGlowSizeSlider = AceGUI:Create("Slider")
                    eqAuraGlowSizeSlider:SetLabel("Glow Size")
                    eqAuraGlowSizeSlider:SetSliderValues(0, 60, 1)
                    eqAuraGlowSizeSlider:SetValue(buttonData.auraGlowSize or 32)
                    eqAuraGlowSizeSlider:SetFullWidth(true)
                    eqAuraGlowSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.auraGlowSize = val
                        CooldownCompanion:InvalidateAuraGlow(selectedGroup, selectedButton)
                    end)
                    scroll:AddChild(eqAuraGlowSizeSlider)
                end

                -- Preview toggle
                local eqAuraGlowPreviewCb = AceGUI:Create("CheckBox")
                eqAuraGlowPreviewCb:SetLabel("Preview")
                local eqAuraGlowPreviewActive = false
                local gFrame = CooldownCompanion.groupFrames[selectedGroup]
                if gFrame then
                    for _, btn in ipairs(gFrame.buttons) do
                        if btn.index == selectedButton and btn._auraGlowPreview then
                            eqAuraGlowPreviewActive = true
                            break
                        end
                    end
                end
                eqAuraGlowPreviewCb:SetValue(eqAuraGlowPreviewActive)
                eqAuraGlowPreviewCb:SetFullWidth(true)
                eqAuraGlowPreviewCb:SetCallback("OnValueChanged", function(widget, event, val)
                    CooldownCompanion:SetAuraGlowPreview(selectedGroup, selectedButton, val)
                end)
                scroll:AddChild(eqAuraGlowPreviewCb)
            end
            else -- bars: bar-specific aura effect controls
                local barAuraColorPicker = AceGUI:Create("ColorPicker")
                barAuraColorPicker:SetLabel("Bar Color While Active")
                barAuraColorPicker:SetHasAlpha(true)
                local bac = buttonData.barAuraColor or {0.2, 1.0, 0.2, 1.0}
                barAuraColorPicker:SetColor(bac[1], bac[2], bac[3], bac[4])
                barAuraColorPicker:SetFullWidth(true)
                barAuraColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                    buttonData.barAuraColor = {r, g, b, a}
                end)
                barAuraColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                    buttonData.barAuraColor = {r, g, b, a}
                end)
                scroll:AddChild(barAuraColorPicker)

                local barAuraEffectDrop = AceGUI:Create("Dropdown")
                barAuraEffectDrop:SetLabel("Bar Active Effect")
                barAuraEffectDrop:SetList({
                    ["none"] = "None",
                    ["pixel"] = "Pixel Glow",
                    ["solid"] = "Solid Border",
                    ["glow"] = "Proc Glow",
                }, {"none", "pixel", "solid", "glow"})
                barAuraEffectDrop:SetValue(buttonData.barAuraEffect or "none")
                barAuraEffectDrop:SetFullWidth(true)
                barAuraEffectDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    buttonData.barAuraEffect = (val ~= "none") and val or nil
                    CooldownCompanion:RefreshGroupFrame(selectedGroup)
                    CooldownCompanion:RefreshConfigPanel()
                end)
                scroll:AddChild(barAuraEffectDrop)

                if buttonData.barAuraEffect and buttonData.barAuraEffect ~= "none" then
                    local barAuraEffectColorPicker = AceGUI:Create("ColorPicker")
                    barAuraEffectColorPicker:SetLabel("Effect Color")
                    local baec = buttonData.barAuraEffectColor or {1, 0.84, 0, 0.9}
                    barAuraEffectColorPicker:SetColor(baec[1], baec[2], baec[3], baec[4] or 0.9)
                    barAuraEffectColorPicker:SetHasAlpha(true)
                    barAuraEffectColorPicker:SetFullWidth(true)
                    barAuraEffectColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                        buttonData.barAuraEffectColor = {r, g, b, a}
                        CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                    end)
                    barAuraEffectColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                        buttonData.barAuraEffectColor = {r, g, b, a}
                        CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                    end)
                    scroll:AddChild(barAuraEffectColorPicker)

                    if buttonData.barAuraEffect == "solid" then
                        local barAuraEffectSizeSlider = AceGUI:Create("Slider")
                        barAuraEffectSizeSlider:SetLabel("Border Size")
                        barAuraEffectSizeSlider:SetSliderValues(1, 8, 1)
                        barAuraEffectSizeSlider:SetValue(buttonData.barAuraEffectSize or 2)
                        barAuraEffectSizeSlider:SetFullWidth(true)
                        barAuraEffectSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSize = val
                            CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectSizeSlider)
                    elseif buttonData.barAuraEffect == "pixel" then
                        local barAuraEffectSizeSlider = AceGUI:Create("Slider")
                        barAuraEffectSizeSlider:SetLabel("Line Length")
                        barAuraEffectSizeSlider:SetSliderValues(2, 12, 1)
                        barAuraEffectSizeSlider:SetValue(buttonData.barAuraEffectSize or 4)
                        barAuraEffectSizeSlider:SetFullWidth(true)
                        barAuraEffectSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSize = val
                            CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectSizeSlider)
                        local barAuraEffectThicknessSlider = AceGUI:Create("Slider")
                        barAuraEffectThicknessSlider:SetLabel("Line Thickness")
                        barAuraEffectThicknessSlider:SetSliderValues(1, 6, 1)
                        barAuraEffectThicknessSlider:SetValue(buttonData.barAuraEffectThickness or 2)
                        barAuraEffectThicknessSlider:SetFullWidth(true)
                        barAuraEffectThicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectThickness = val
                            CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectThicknessSlider)
                        local barAuraEffectSpeedSlider = AceGUI:Create("Slider")
                        barAuraEffectSpeedSlider:SetLabel("Speed")
                        barAuraEffectSpeedSlider:SetSliderValues(10, 200, 5)
                        barAuraEffectSpeedSlider:SetValue(buttonData.barAuraEffectSpeed or 60)
                        barAuraEffectSpeedSlider:SetFullWidth(true)
                        barAuraEffectSpeedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSpeed = val
                            -- Update speed live without invalidating (no visual state change)
                            local gFrame = CooldownCompanion.groupFrames[selectedGroup]
                            if gFrame then
                                for _, btn in ipairs(gFrame.buttons) do
                                    if btn.index == selectedButton and btn.barAuraEffect and btn.barAuraEffect.pixelFrame then
                                        btn.barAuraEffect.pixelFrame._speed = val
                                    end
                                end
                            end
                        end)
                        scroll:AddChild(barAuraEffectSpeedSlider)
                    elseif buttonData.barAuraEffect == "glow" then
                        local barAuraEffectSizeSlider = AceGUI:Create("Slider")
                        barAuraEffectSizeSlider:SetLabel("Glow Size")
                        barAuraEffectSizeSlider:SetSliderValues(0, 60, 1)
                        barAuraEffectSizeSlider:SetValue(buttonData.barAuraEffectSize or 32)
                        barAuraEffectSizeSlider:SetFullWidth(true)
                        barAuraEffectSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSize = val
                            CooldownCompanion:InvalidateBarAuraEffect(selectedGroup, selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectSizeSlider)
                    end

                    -- Preview toggle
                    local barAuraPreviewCb = AceGUI:Create("CheckBox")
                    barAuraPreviewCb:SetLabel("Preview")
                    local barAuraPreviewActive = false
                    local gFrame = CooldownCompanion.groupFrames[selectedGroup]
                    if gFrame then
                        for _, btn in ipairs(gFrame.buttons) do
                            if btn.index == selectedButton and btn._barAuraEffectPreview then
                                barAuraPreviewActive = true
                                break
                            end
                        end
                    end
                    barAuraPreviewCb:SetValue(barAuraPreviewActive)
                    barAuraPreviewCb:SetFullWidth(true)
                    barAuraPreviewCb:SetCallback("OnValueChanged", function(widget, event, val)
                        CooldownCompanion:SetBarAuraEffectPreview(selectedGroup, selectedButton, val)
                    end)
                    scroll:AddChild(barAuraPreviewCb)
                end
            end -- bars/icons aura effect branch
        end
    end

    if group.displayMode == "bars" then
        local chargeGapSlider = AceGUI:Create("Slider")
        chargeGapSlider:SetLabel("Charge Bar Gap")
        chargeGapSlider:SetSliderValues(0, 20, 1)
        chargeGapSlider:SetValue(buttonData.barChargeGap or 2)
        chargeGapSlider:SetFullWidth(true)
        chargeGapSlider:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.barChargeGap = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        scroll:AddChild(chargeGapSlider)

        local reverseChargesCb = AceGUI:Create("CheckBox")
        reverseChargesCb:SetLabel("Flip Charge Order")
        reverseChargesCb:SetValue(buttonData.barReverseCharges or false)
        reverseChargesCb:SetFullWidth(true)
        reverseChargesCb:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.barReverseCharges = val or nil
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        scroll:AddChild(reverseChargesCb)
    end
end

------------------------------------------------------------------------
-- BUTTON SETTINGS COLUMN: Refresh
------------------------------------------------------------------------
local function RefreshButtonSettingsColumn()
    if not buttonSettingsScroll then return end
    CooldownCompanion:ClearAllProcGlowPreviews()
    CooldownCompanion:ClearAllAuraGlowPreviews()
    for _, btn in ipairs(buttonSettingsInfoButtons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(buttonSettingsInfoButtons)
    for _, btn in ipairs(buttonSettingsCollapseButtons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(buttonSettingsCollapseButtons)
    buttonSettingsScroll:ReleaseChildren()

    if not selectedGroup then
        local label = AceGUI:Create("Label")
        label:SetText("Select a spell or item to configure")
        label:SetFullWidth(true)
        buttonSettingsScroll:AddChild(label)
        return
    end

    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end

    -- Only show settings when a single button is selected (not multi-select)
    local multiCount = 0
    for _ in pairs(selectedButtons) do
        multiCount = multiCount + 1
    end

    if multiCount >= 2 or not selectedButton or not group.buttons[selectedButton] then
        local label = AceGUI:Create("Label")
        label:SetText("Select a spell or item to configure")
        label:SetFullWidth(true)
        buttonSettingsScroll:AddChild(label)
        return
    end

    local buttonData = group.buttons[selectedButton]

    if buttonData.type == "spell" then
        BuildSpellSettings(buttonSettingsScroll, buttonData, buttonSettingsInfoButtons)
    elseif buttonData.type == "item" and not CooldownCompanion.IsItemEquippable(buttonData) then
        BuildItemSettings(buttonSettingsScroll, buttonData, buttonSettingsInfoButtons)
    elseif buttonData.type == "item" and CooldownCompanion.IsItemEquippable(buttonData) then
        BuildEquipItemSettings(buttonSettingsScroll, buttonData, buttonSettingsInfoButtons)
    end

    -- Apply hideInfoButtons setting
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(buttonSettingsInfoButtons) do
            btn:Hide()
        end
    end
end

------------------------------------------------------------------------
-- COLUMN 3: Settings (TabGroup)
------------------------------------------------------------------------
local tabInfoButtons = {}
local appearanceTabElements = {}

local function BuildExtrasTab(container)
    for _, btn in ipairs(tabInfoButtons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(tabInfoButtons)
    for _, elem in ipairs(appearanceTabElements) do
        elem:ClearAllPoints()
        elem:Hide()
        elem:SetParent(nil)
    end
    wipe(appearanceTabElements)

    if not selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end
    local style = group.style

    local isBarMode = group.displayMode == "bars"

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
    gcdCb:SetLabel(isBarMode and "Show GCD" or "Show GCD Swipe")
    gcdCb:SetValue(style.showGCDSwipe == true)
    gcdCb:SetFullWidth(true)
    gcdCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showGCDSwipe = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(gcdCb)

    if not isBarMode then
    local rangeCb = AceGUI:Create("CheckBox")
    rangeCb:SetLabel("Show Out of Range")
    rangeCb:SetValue(style.showOutOfRange or false)
    rangeCb:SetFullWidth(true)
    rangeCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showOutOfRange = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(rangeCb)

    -- (?) tooltip for out of range
    local rangeInfo = CreateFrame("Button", nil, rangeCb.frame)
    rangeInfo:SetSize(16, 16)
    rangeInfo:SetPoint("LEFT", rangeCb.checkbg, "RIGHT", rangeCb.text:GetStringWidth() + 4, 0)
    local rangeInfoText = rangeInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rangeInfoText:SetPoint("CENTER")
    rangeInfoText:SetText("|cff66aaff(?)|r")
    rangeInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Out of Range")
        GameTooltip:AddLine("Tints spell and item icons red when the target is out of range. Item range checking is unavailable during combat due to Blizzard API restrictions.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    rangeInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, rangeInfo)
    end -- not isBarMode

    local tooltipCb = AceGUI:Create("CheckBox")
    tooltipCb:SetLabel("Show Tooltips")
    tooltipCb:SetValue(style.showTooltips == true)
    tooltipCb:SetFullWidth(true)
    tooltipCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showTooltips = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(tooltipCb)

    if not isBarMode then
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
    end -- not isBarMode

    -- "Alpha" heading with (?) info button
    local alphaHeading = AceGUI:Create("Heading")
    alphaHeading:SetText("Alpha")
    alphaHeading:SetFullWidth(true)
    container:AddChild(alphaHeading)

    local alphaInfo = CreateFrame("Button", nil, alphaHeading.frame)
    alphaInfo:SetSize(16, 16)
    alphaInfo:SetPoint("LEFT", alphaHeading.label, "RIGHT", 4, 0)
    alphaHeading.right:SetPoint("LEFT", alphaInfo, "RIGHT", 4, 0)
    local alphaInfoText = alphaInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    alphaInfoText:SetPoint("CENTER")
    alphaInfoText:SetText("|cff66aaff(?)|r")
    alphaInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Alpha")
        GameTooltip:AddLine("Controls the transparency of this group. Alpha = 1 is fully visible. Alpha = 0 means completely hidden.\n\nSetting baseline alpha below 1 reveals visibility override options.\n\nThe first three options (In Combat, Out of Combat, Mounted) are 3-way toggles — click to cycle through Disabled, |cff00ff00Fully Visible|r, and |cffff0000Fully Hidden|r.\n\n|cff00ff00Fully Visible|r overrides alpha to 1 when the condition is met.\n\n|cffff0000Fully Hidden|r overrides alpha to 0 when the condition is met.\n\nIf both apply simultaneously, |cff00ff00Fully Visible|r takes priority.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    alphaInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, alphaInfo)

    -- Baseline Alpha slider
    local baseAlphaSlider = AceGUI:Create("Slider")
    baseAlphaSlider:SetLabel("Baseline Alpha")
    baseAlphaSlider:SetSliderValues(0, 1, 0.05)
    baseAlphaSlider:SetValue(group.baselineAlpha or 1)
    baseAlphaSlider:SetFullWidth(true)
    baseAlphaSlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.baselineAlpha = val
        -- Apply alpha immediately for live preview
        local frame = CooldownCompanion.groupFrames[selectedGroup]
        if frame and frame:IsShown() then
            frame:SetAlpha(val)
        end
        -- Sync alpha state in-place so the OnUpdate loop doesn't fight the slider
        local state = CooldownCompanion.alphaState and CooldownCompanion.alphaState[selectedGroup]
        if state then
            state.currentAlpha = val
            state.desiredAlpha = val
            state.lastAlpha = val
            state.fadeDuration = 0
        end
    end)
    baseAlphaSlider:SetCallback("OnMouseUp", function()
        -- Rebuild UI when crossing the 1.0 boundary to show/hide conditional section
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(baseAlphaSlider)

    -- Conditional section: visible when baselineAlpha < 1 OR any forceHide toggle is active
    local showConditional = (group.baselineAlpha or 1) < 1
        or group.forceHideInCombat or group.forceHideOutOfCombat
        or group.forceHideMounted
    if showConditional then
        -- Helper: convert forceAlpha/forceHide pair to tristate value
        -- true = Force Visible, nil = Force Hidden, false = Disabled
        local function GetTriState(visibleKey, hiddenKey)
            if group[hiddenKey] then return nil end
            if group[visibleKey] then return true end
            return false
        end

        -- Helper: build label with colored state suffix
        local function TriStateLabel(base, value)
            if value == true then
                return base .. " - |cff00ff00Fully Visible|r"
            elseif value == nil then
                return base .. " - |cffff0000Fully Hidden|r"
            end
            return base
        end

        -- Helper: create a 3-way tristate checkbox (Disabled / Force Visible / Force Hidden)
        local function CreateTriStateToggle(label, visibleKey, hiddenKey)
            local val = GetTriState(visibleKey, hiddenKey)
            local cb = AceGUI:Create("CheckBox")
            cb:SetTriState(true)
            cb:SetLabel(TriStateLabel(label, val))
            cb:SetValue(val)
            cb:SetFullWidth(true)
            cb:SetCallback("OnValueChanged", function(widget, event, newVal)
                -- Cycle: false (disabled) → true (visible) → nil (hidden) → false
                group[visibleKey] = (newVal == true)
                group[hiddenKey] = (newVal == nil)
                CooldownCompanion:RefreshConfigPanel()
            end)
            return cb
        end

        -- Heading
        local overridesHeading = AceGUI:Create("Heading")
        overridesHeading:SetText("Visibility Overrides")
        overridesHeading:SetFullWidth(true)
        container:AddChild(overridesHeading)

        -- 3-way tristate toggles (Disabled / Force Visible / Force Hidden)
        container:AddChild(CreateTriStateToggle("In Combat", "forceAlphaInCombat", "forceHideInCombat"))
        container:AddChild(CreateTriStateToggle("Out of Combat", "forceAlphaOutOfCombat", "forceHideOutOfCombat"))
        container:AddChild(CreateTriStateToggle("Mounted", "forceAlphaMounted", "forceHideMounted"))

        -- Target Exists checkbox (force-visible only)
        local targetVal = group.forceAlphaTargetExists or false
        local targetCb = AceGUI:Create("CheckBox")
        targetCb:SetLabel(targetVal and "Target Exists - |cff00ff00Fully Visible|r" or "Target Exists")
        targetCb:SetValue(targetVal)
        targetCb:SetFullWidth(true)
        targetCb:SetCallback("OnValueChanged", function(widget, event, val)
            group.forceAlphaTargetExists = val
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(targetCb)

        -- Mouseover checkbox (force-visible only, overrides all other conditions)
        local mouseoverVal = group.forceAlphaMouseover or false
        local mouseoverCb = AceGUI:Create("CheckBox")
        mouseoverCb:SetLabel(mouseoverVal and "Mouseover - |cff00ff00Fully Visible|r" or "Mouseover")
        mouseoverCb:SetValue(mouseoverVal)
        mouseoverCb:SetFullWidth(true)
        mouseoverCb:SetCallback("OnValueChanged", function(widget, event, val)
            group.forceAlphaMouseover = val
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(mouseoverCb)

        local mouseoverInfo = CreateFrame("Button", nil, mouseoverCb.frame)
        mouseoverInfo:SetSize(16, 16)
        mouseoverInfo:SetPoint("LEFT", mouseoverCb.text, "RIGHT", 4, 0)
        local mouseoverInfoText = mouseoverInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mouseoverInfoText:SetPoint("CENTER")
        mouseoverInfoText:SetText("|cff66aaff(?)|r")
        mouseoverInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Mouseover")
            GameTooltip:AddLine("When enabled, mousing over the group forces it to full visibility. Like all |cff00ff00Force Visible|r conditions, this overrides |cffff0000Force Hidden|r.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        mouseoverInfo:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        table.insert(tabInfoButtons, mouseoverInfo)

        -- Fade Delay slider
        local fadeDelaySlider = AceGUI:Create("Slider")
        fadeDelaySlider:SetLabel("Fade Delay (seconds)")
        fadeDelaySlider:SetSliderValues(0, 5, 0.1)
        fadeDelaySlider:SetValue(group.fadeDelay or 1)
        fadeDelaySlider:SetFullWidth(true)
        fadeDelaySlider:SetCallback("OnValueChanged", function(widget, event, val)
            group.fadeDelay = val
        end)
        container:AddChild(fadeDelaySlider)

        -- Fade In Duration slider
        local fadeInSlider = AceGUI:Create("Slider")
        fadeInSlider:SetLabel("Fade In Duration (seconds)")
        fadeInSlider:SetSliderValues(0, 5, 0.1)
        fadeInSlider:SetValue(group.fadeInDuration or 0.2)
        fadeInSlider:SetFullWidth(true)
        fadeInSlider:SetCallback("OnValueChanged", function(widget, event, val)
            group.fadeInDuration = val
        end)
        container:AddChild(fadeInSlider)

        -- Fade Out Duration slider
        local fadeOutSlider = AceGUI:Create("Slider")
        fadeOutSlider:SetLabel("Fade Out Duration (seconds)")
        fadeOutSlider:SetSliderValues(0, 5, 0.1)
        fadeOutSlider:SetValue(group.fadeOutDuration or 0.2)
        fadeOutSlider:SetFullWidth(true)
        fadeOutSlider:SetCallback("OnValueChanged", function(widget, event, val)
            group.fadeOutDuration = val
        end)
        container:AddChild(fadeOutSlider)
    end

    -- Apply "Hide CDC Tooltips" to tab info buttons created above
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(tabInfoButtons) do
            btn:Hide()
        end
    end

    -- Other ---------------------------------------------------------------
    -- Masque skinning toggle (only show if Masque is installed, not in bar mode)
    if CooldownCompanion.Masque and not isBarMode then
        local otherHeading = AceGUI:Create("Heading")
        otherHeading:SetText("Other")
        otherHeading:SetFullWidth(true)
        container:AddChild(otherHeading)

        local masqueCb = AceGUI:Create("CheckBox")
        masqueCb:SetLabel("Enable Masque Skinning")
        masqueCb:SetValue(group.masqueEnabled or false)
        masqueCb:SetFullWidth(true)
        masqueCb:SetCallback("OnValueChanged", function(widget, event, val)
            CooldownCompanion:ToggleGroupMasque(selectedGroup, val)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(masqueCb)

        -- (?) info tooltip for Masque
        local masqueInfo = CreateFrame("Button", nil, masqueCb.frame)
        masqueInfo:SetSize(16, 16)
        masqueInfo:SetPoint("LEFT", masqueCb.checkbg, "RIGHT", masqueCb.text:GetStringWidth() + 4, 0)
        local masqueInfoText = masqueInfo:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        masqueInfoText:SetPoint("CENTER")
        masqueInfoText:SetText("|cff66aaff(?)|r")
        masqueInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Masque Skinning")
            GameTooltip:AddLine("Uses the Masque addon to apply custom button skins to this group. Configure skins via /masque or the Masque config panel.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Overridden Settings:", 1, 0.82, 0)
            GameTooltip:AddLine("Border Size, Border Color, Square Icons (forced on)", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        masqueInfo:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        table.insert(tabInfoButtons, masqueInfo)

        -- Hide info button if setting is enabled
        if CooldownCompanion.db.profile.hideInfoButtons then
            masqueInfo:Hide()
        end
    end

end

local function BuildPositioningTab(container)
    for _, elem in ipairs(appearanceTabElements) do
        elem:ClearAllPoints()
        elem:Hide()
        elem:SetParent(nil)
    end
    wipe(appearanceTabElements)

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
    anchorBox:SetRelativeWidth(0.68)
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
    pickBtn:SetRelativeWidth(0.24)
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
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("You can also type a frame name directly into the editbox.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Middle-click the draggable header to toggle lock/unlock.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pickInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, pickInfo)

    container:AddChild(anchorRow)
    pickBtn.frame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        local p, rel, rp, xOfs, yOfs = self:GetPoint(1)
        if yOfs then
            self:SetPoint(p, rel, rp, xOfs, yOfs - 2)
        end
    end)

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

    -- Orientation / Layout controls (mode-dependent)
    if group.displayMode == "bars" then
        -- Vertical Bar Fill checkbox
        local vertFillCheck = AceGUI:Create("CheckBox")
        vertFillCheck:SetLabel("Vertical Bar Fill")
        vertFillCheck:SetValue(group.style.barFillVertical or false)
        vertFillCheck:SetFullWidth(true)
        vertFillCheck:SetCallback("OnValueChanged", function(widget, event, val)
            group.style.barFillVertical = val or nil
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(vertFillCheck)

        -- Flip Fill/Drain Direction checkbox
        local reverseFillCheck = AceGUI:Create("CheckBox")
        reverseFillCheck:SetLabel("Flip Fill/Drain Direction")
        reverseFillCheck:SetValue(group.style.barReverseFill or false)
        reverseFillCheck:SetFullWidth(true)
        reverseFillCheck:SetCallback("OnValueChanged", function(widget, event, val)
            group.style.barReverseFill = val or nil
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
        end)
        container:AddChild(reverseFillCheck)

        -- Horizontal Bar Layout checkbox (only when >1 button)
        if #group.buttons > 1 then
            local horzLayoutCheck = AceGUI:Create("CheckBox")
            horzLayoutCheck:SetLabel("Horizontal Bar Layout")
            horzLayoutCheck:SetValue((group.style.orientation or "vertical") == "horizontal")
            horzLayoutCheck:SetFullWidth(true)
            horzLayoutCheck:SetCallback("OnValueChanged", function(widget, event, val)
                group.style.orientation = val and "horizontal" or "vertical"
                CooldownCompanion:RefreshGroupFrame(selectedGroup)
            end)
            container:AddChild(horzLayoutCheck)
        end
    else
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
    end

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
    -- Strata (Layer Order) — hidden for bar mode
    -- ================================================================
    if group.displayMode ~= "bars" then
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
    end -- not bars (strata)

    -- Apply "Hide CDC Tooltips" to tab info buttons created above
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(tabInfoButtons) do
            btn:Hide()
        end
    end
end

local function BuildBarAppearanceTab(container, group, style)
    -- Bar Settings header
    local barHeading = AceGUI:Create("Heading")
    barHeading:SetText("Bar Settings")
    barHeading:SetFullWidth(true)
    container:AddChild(barHeading)

    local lengthSlider = AceGUI:Create("Slider")
    lengthSlider:SetLabel("Bar Length")
    lengthSlider:SetSliderValues(50, 400, 1)
    lengthSlider:SetValue(style.barLength or 180)
    lengthSlider:SetFullWidth(true)
    lengthSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.barLength = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(lengthSlider)

    local heightSlider = AceGUI:Create("Slider")
    heightSlider:SetLabel("Bar Height")
    heightSlider:SetSliderValues(10, 50, 1)
    heightSlider:SetValue(style.barHeight or 20)
    heightSlider:SetFullWidth(true)
    heightSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.barHeight = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(heightSlider)

    local showIconCb = AceGUI:Create("CheckBox")
    showIconCb:SetLabel("Show Icon")
    showIconCb:SetValue(style.showBarIcon ~= false)
    showIconCb:SetFullWidth(true)
    showIconCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showBarIcon = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(showIconCb)

    if style.showBarIcon ~= false then
        local iconOffsetSlider = AceGUI:Create("Slider")
        iconOffsetSlider:SetLabel("Icon Offset")
        iconOffsetSlider:SetSliderValues(-5, 20, 1)
        iconOffsetSlider:SetValue(style.barIconOffset or 0)
        iconOffsetSlider:SetFullWidth(true)
        iconOffsetSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barIconOffset = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(iconOffsetSlider)
    end

    if group.buttons and #group.buttons > 1 then
        local spacingSlider = AceGUI:Create("Slider")
        spacingSlider:SetLabel("Bar Spacing")
        spacingSlider:SetSliderValues(0, 10, 0.1)
        spacingSlider:SetValue(style.buttonSpacing or ST.BUTTON_SPACING)
        spacingSlider:SetFullWidth(true)
        spacingSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.buttonSpacing = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(spacingSlider)
    end

    local updateFreqSlider = AceGUI:Create("Slider")
    updateFreqSlider:SetLabel("Update Frequency (Hz)")
    updateFreqSlider:SetSliderValues(10, 60, 1)
    local curInterval = style.barUpdateInterval or 0.025
    updateFreqSlider:SetValue(math.floor(1 / curInterval + 0.5))
    updateFreqSlider:SetFullWidth(true)
    updateFreqSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.barUpdateInterval = 1 / val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(updateFreqSlider)

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

    local barColorPicker = AceGUI:Create("ColorPicker")
    barColorPicker:SetLabel("Bar Color")
    barColorPicker:SetHasAlpha(true)
    local brc = style.barColor or {0.2, 0.6, 1.0, 1.0}
    barColorPicker:SetColor(brc[1], brc[2], brc[3], brc[4])
    barColorPicker:SetFullWidth(true)
    barColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.barColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    barColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.barColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(barColorPicker)

    local barCdColorPicker = AceGUI:Create("ColorPicker")
    barCdColorPicker:SetLabel("Bar Cooldown Color")
    barCdColorPicker:SetHasAlpha(true)
    local bcc = style.barCooldownColor or {0.6, 0.6, 0.6, 1.0}
    barCdColorPicker:SetColor(bcc[1], bcc[2], bcc[3], bcc[4])
    barCdColorPicker:SetFullWidth(true)
    barCdColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.barCooldownColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    barCdColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.barCooldownColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(barCdColorPicker)

    local barBgColorPicker = AceGUI:Create("ColorPicker")
    barBgColorPicker:SetLabel("Bar Background Color")
    barBgColorPicker:SetHasAlpha(true)
    local bbg = style.barBgColor or {0.1, 0.1, 0.1, 0.8}
    barBgColorPicker:SetColor(bbg[1], bbg[2], bbg[3], bbg[4])
    barBgColorPicker:SetFullWidth(true)
    barBgColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.barBgColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    barBgColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.barBgColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(barBgColorPicker)

    -- Name Text heading
    local nameHeading = AceGUI:Create("Heading")
    nameHeading:SetText("Name Text")
    nameHeading:SetFullWidth(true)
    container:AddChild(nameHeading)

    local showNameCb = AceGUI:Create("CheckBox")
    showNameCb:SetLabel("Show Name Text")
    showNameCb:SetValue(style.showBarNameText ~= false)
    showNameCb:SetFullWidth(true)
    showNameCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showBarNameText = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(showNameCb)

    if style.showBarNameText ~= false then
        local nameFontSizeSlider = AceGUI:Create("Slider")
        nameFontSizeSlider:SetLabel("Font Size")
        nameFontSizeSlider:SetSliderValues(6, 24, 1)
        nameFontSizeSlider:SetValue(style.barNameFontSize or 10)
        nameFontSizeSlider:SetFullWidth(true)
        nameFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameFontSize = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(nameFontSizeSlider)

        local nameFontDrop = AceGUI:Create("Dropdown")
        nameFontDrop:SetLabel("Font")
        nameFontDrop:SetList(fontOptions)
        nameFontDrop:SetValue(style.barNameFont or "Fonts\\FRIZQT__.TTF")
        nameFontDrop:SetFullWidth(true)
        nameFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameFont = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(nameFontDrop)

        local nameOutlineDrop = AceGUI:Create("Dropdown")
        nameOutlineDrop:SetLabel("Font Outline")
        nameOutlineDrop:SetList(outlineOptions)
        nameOutlineDrop:SetValue(style.barNameFontOutline or "OUTLINE")
        nameOutlineDrop:SetFullWidth(true)
        nameOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameFontOutline = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(nameOutlineDrop)

        local nameFontColor = AceGUI:Create("ColorPicker")
        nameFontColor:SetLabel("Font Color")
        nameFontColor:SetHasAlpha(true)
        local nfc = style.barNameFontColor or {1, 1, 1, 1}
        nameFontColor:SetColor(nfc[1], nfc[2], nfc[3], nfc[4])
        nameFontColor:SetFullWidth(true)
        nameFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.barNameFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        nameFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.barNameFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(nameFontColor)

        local nameOffXSlider = AceGUI:Create("Slider")
        nameOffXSlider:SetLabel("X Offset")
        nameOffXSlider:SetSliderValues(-50, 50, 1)
        nameOffXSlider:SetValue(style.barNameTextOffsetX or 0)
        nameOffXSlider:SetFullWidth(true)
        nameOffXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameTextOffsetX = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(nameOffXSlider)

        local nameOffYSlider = AceGUI:Create("Slider")
        nameOffYSlider:SetLabel("Y Offset")
        nameOffYSlider:SetSliderValues(-50, 50, 1)
        nameOffYSlider:SetValue(style.barNameTextOffsetY or 0)
        nameOffYSlider:SetFullWidth(true)
        nameOffYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameTextOffsetY = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(nameOffYSlider)
    end

    -- Time Text heading
    local timeHeading = AceGUI:Create("Heading")
    timeHeading:SetText("Time Text")
    timeHeading:SetFullWidth(true)
    container:AddChild(timeHeading)

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

    if style.showCooldownText then
        local fontSizeSlider = AceGUI:Create("Slider")
        fontSizeSlider:SetLabel("Font Size")
        fontSizeSlider:SetSliderValues(6, 24, 1)
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
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        cdFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.cooldownFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(cdFontColor)

        local cdOffXSlider = AceGUI:Create("Slider")
        cdOffXSlider:SetLabel("X Offset")
        cdOffXSlider:SetSliderValues(-50, 50, 1)
        cdOffXSlider:SetValue(style.barCdTextOffsetX or 0)
        cdOffXSlider:SetFullWidth(true)
        cdOffXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barCdTextOffsetX = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(cdOffXSlider)

        local cdOffYSlider = AceGUI:Create("Slider")
        cdOffYSlider:SetLabel("Y Offset")
        cdOffYSlider:SetSliderValues(-50, 50, 1)
        cdOffYSlider:SetValue(style.barCdTextOffsetY or 0)
        cdOffYSlider:SetFullWidth(true)
        cdOffYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barCdTextOffsetY = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(cdOffYSlider)
    end

    local readySep = AceGUI:Create("Heading")
    readySep:SetText("")
    readySep:SetFullWidth(true)
    container:AddChild(readySep)

    local showReadyCb = AceGUI:Create("CheckBox")
    showReadyCb:SetLabel("Show Ready Text")
    showReadyCb:SetValue(style.showBarReadyText or false)
    showReadyCb:SetFullWidth(true)
    showReadyCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showBarReadyText = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(showReadyCb)

    if style.showBarReadyText then
        local readyTextBox = AceGUI:Create("EditBox")
        readyTextBox:SetLabel("Ready Text")
        readyTextBox:SetText(style.barReadyText or "Ready")
        readyTextBox:SetFullWidth(true)
        readyTextBox:SetCallback("OnEnterPressed", function(widget, event, val)
            style.barReadyText = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(readyTextBox)

        local readyColorPicker = AceGUI:Create("ColorPicker")
        readyColorPicker:SetLabel("Ready Text Color")
        readyColorPicker:SetHasAlpha(true)
        local rtc = style.barReadyTextColor or {0.2, 1.0, 0.2, 1.0}
        readyColorPicker:SetColor(rtc[1], rtc[2], rtc[3], rtc[4])
        readyColorPicker:SetFullWidth(true)
        readyColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.barReadyTextColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        readyColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.barReadyTextColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(readyColorPicker)
    end
end

local function BuildAppearanceTab(container)
    -- Clean up elements from previous build
    for _, elem in ipairs(appearanceTabElements) do
        elem:ClearAllPoints()
        elem:Hide()
        elem:SetParent(nil)
    end
    wipe(appearanceTabElements)

    if not selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end
    local style = group.style

    -- Branch for bar mode
    if group.displayMode == "bars" then
        BuildBarAppearanceTab(container, group, style)
        return
    end

    -- Icon Settings header
    local iconHeading = AceGUI:Create("Heading")
    iconHeading:SetText("Icon Settings")
    iconHeading:SetFullWidth(true)
    container:AddChild(iconHeading)

    local squareCb = AceGUI:Create("CheckBox")
    squareCb:SetLabel("Square Icons")
    squareCb:SetValue(style.maintainAspectRatio or false)
    squareCb:SetFullWidth(true)
    -- Disable when Masque is enabled (forces square icons)
    if group.masqueEnabled then
        squareCb:SetDisabled(true)
        -- Add green "Masque skinning is active" label
        local masqueLabel = squareCb.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        masqueLabel:SetPoint("LEFT", squareCb.checkbg, "RIGHT", squareCb.text:GetStringWidth() + 8, 0)
        masqueLabel:SetText("|cff00ff00(Masque skinning is active)|r")
        table.insert(appearanceTabElements, masqueLabel)
    end
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
        sizeSlider:SetSliderValues(10, 100, 1)
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

    if group.buttons and #group.buttons > 1 then
        local spacingSlider = AceGUI:Create("Slider")
        spacingSlider:SetLabel("Button Spacing")
        spacingSlider:SetSliderValues(0, 10, 0.1)
        spacingSlider:SetValue(style.buttonSpacing or ST.BUTTON_SPACING)
        spacingSlider:SetFullWidth(true)
        spacingSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.buttonSpacing = val
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
        end)
        container:AddChild(spacingSlider)
    end

    local borderSlider = AceGUI:Create("Slider")
    borderSlider:SetLabel("Border Size")
    borderSlider:SetSliderValues(0, 5, 0.1)
    borderSlider:SetValue(style.borderSize or ST.DEFAULT_BORDER_SIZE)
    borderSlider:SetFullWidth(true)
    -- Disable when Masque is enabled (Masque provides its own border)
    if group.masqueEnabled then
        borderSlider:SetDisabled(true)
    end
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
    -- Disable when Masque is enabled (Masque provides its own border)
    if group.masqueEnabled then
        borderColor:SetDisabled(true)
    end
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
            CooldownCompanion:UpdateGroupStyle(selectedGroup)
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
            col3Scroll = scroll

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

    -- Save AceGUI scroll state before tab re-select (old col3Scroll will be released)
    local savedOffset, savedScrollvalue
    if col3Scroll then
        local s = col3Scroll.status or col3Scroll.localstatus
        if s and s.offset and s.offset > 0 then
            savedOffset = s.offset
            savedScrollvalue = s.scrollvalue
        end
    end

    -- Show and refresh the tab content (SelectTab fires callback synchronously,
    -- which releases old col3Scroll and creates a new one)
    container.tabGroup.frame:Show()
    container.tabGroup:SelectTab(selectedTab)

    -- Restore scroll state on the new col3Scroll widget.  LayoutFinished has already
    -- scheduled FixScrollOnUpdate for next frame — it will read these values.
    if savedOffset and col3Scroll then
        local s = col3Scroll.status or col3Scroll.localstatus
        if s then
            s.offset = savedOffset
            s.scrollvalue = savedScrollvalue
        end
    end
end

------------------------------------------------------------------------
-- Profile Bar
------------------------------------------------------------------------
local function RefreshProfileBar(bar)
    -- Release tracked AceGUI widgets
    for _, widget in ipairs(profileBarAceWidgets) do
        widget:Release()
    end
    wipe(profileBarAceWidgets)

    local db = CooldownCompanion.db
    local profiles = db:GetProfiles()
    local currentProfile = db:GetCurrentProfile()

    -- Build ordered profile list for AceGUI Dropdown
    local profileList = {}
    for _, name in ipairs(profiles) do
        profileList[name] = name
    end

    -- Profile dropdown (no label, compact)
    local profileDrop = AceGUI:Create("Dropdown")
    profileDrop:SetLabel("")
    profileDrop:SetList(profileList, profiles)
    profileDrop:SetValue(currentProfile)
    profileDrop:SetWidth(150)
    profileDrop:SetCallback("OnValueChanged", function(widget, event, val)
        db:SetProfile(val)
        selectedGroup = nil
        selectedButton = nil
        wipe(selectedButtons)
        CooldownCompanion:RefreshConfigPanel()
        CooldownCompanion:RefreshAllGroups()
    end)
    profileDrop.frame:SetParent(bar)
    profileDrop.frame:ClearAllPoints()
    profileDrop.frame:SetPoint("LEFT", bar, "LEFT", 0, 0)
    profileDrop.frame:Show()
    table.insert(profileBarAceWidgets, profileDrop)

    -- Helper to create horizontally chained buttons
    local lastAnchor = profileDrop.frame
    local function AddBarButton(text, width, onClick)
        local btn = AceGUI:Create("Button")
        btn:SetText(text)
        btn:SetWidth(width)
        btn:SetCallback("OnClick", onClick)
        btn.frame:SetParent(bar)
        btn.frame:ClearAllPoints()
        btn.frame:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
        btn:SetHeight(22)
        btn.frame:Show()
        table.insert(profileBarAceWidgets, btn)
        lastAnchor = btn.frame
        return btn
    end

    AddBarButton("New", 55, function()
        ShowPopupAboveConfig("CDC_NEW_PROFILE")
    end)

    AddBarButton("Rename", 80, function()
        ShowPopupAboveConfig("CDC_RENAME_PROFILE", currentProfile, { oldName = currentProfile })
    end)

    AddBarButton("Duplicate", 90, function()
        ShowPopupAboveConfig("CDC_DUPLICATE_PROFILE", nil, { source = currentProfile })
    end)

    AddBarButton("Delete", 70, function()
        local allProfiles = db:GetProfiles()
        local isOnly = #allProfiles <= 1
        if isOnly then
            ShowPopupAboveConfig("CDC_RESET_PROFILE", currentProfile, { profileName = currentProfile, isOnly = true })
        else
            ShowPopupAboveConfig("CDC_DELETE_PROFILE", currentProfile, { profileName = currentProfile })
        end
    end)

    AddBarButton("Export", 75, function()
        ShowPopupAboveConfig("CDC_EXPORT_PROFILE")
    end)

    AddBarButton("Import", 75, function()
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
    frame:SetStatusText("")
    frame:SetWidth(1150)
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

    -- Hide the AceGUI status bar and add version text at bottom-right
    if frame.statustext then
        local statusbg = frame.statustext:GetParent()
        if statusbg then statusbg:Hide() end
    end
    local versionText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 20, 25)
    versionText:SetText("v1.3  |  " .. (CooldownCompanion.db:GetCurrentProfile() or "Default"))
    versionText:SetTextColor(1, 0.82, 0)

    -- Prevent AceGUI from releasing on close - just hide
    frame:SetCallback("OnClose", function(widget)
        widget.frame:Hide()
    end)

    -- Cleanup on hide (covers ESC, X button, OnClose, ToggleConfig)
    -- isCollapsing flag prevents cleanup when collapsing (vs truly closing)
    local isCollapsing = false
    content:HookScript("OnHide", function()
        if isCollapsing then return end
        CooldownCompanion:ClearAllProcGlowPreviews()
        CooldownCompanion:ClearAllAuraGlowPreviews()
        CloseDropDownMenus()
    end)

    -- ESC to close support (keyboard handler — more reliable than UISpecialFrames)
    content:EnableKeyboard(true)
    content:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and CooldownCompanion.db.profile.escClosesConfig then
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(false)
            end
            self:Hide()
        elseif not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- Permanently hide the AceGUI bottom close button
    for _, child in ipairs({content:GetChildren()}) do
        if child:GetObjectType() == "Button" and child:GetText() == CLOSE then
            child:Hide()
            child:SetScript("OnShow", child.Hide)
            break
        end
    end

    local isMinimized = false
    local fullHeight = 700

    -- Title bar buttons: [Gear] [Collapse] [X] at top-right

    -- X (close) button — rightmost
    local closeBtn = AceGUI:Create("Button")
    closeBtn:SetText("")
    closeBtn:SetWidth(22)
    closeBtn:SetHeight(18)
    closeBtn.frame:SetParent(content)
    closeBtn.frame:ClearAllPoints()
    closeBtn.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -5)
    closeBtn.frame:Show()
    local closeIcon = closeBtn.frame:CreateTexture(nil, "ARTWORK")
    closeIcon:SetAtlas("common-icon-redx")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeBtn:SetCallback("OnClick", function()
        content:Hide()
    end)

    -- Collapse button — left of X
    local collapseBtn = AceGUI:Create("Button")
    collapseBtn:SetText("")
    collapseBtn:SetWidth(22)
    collapseBtn:SetHeight(18)
    collapseBtn.frame:SetParent(content)
    collapseBtn.frame:ClearAllPoints()
    collapseBtn.frame:SetPoint("RIGHT", closeBtn.frame, "LEFT", -2, 0)
    collapseBtn.frame:Show()
    local collapseIcon = collapseBtn.frame:CreateTexture(nil, "ARTWORK")
    collapseIcon:SetAtlas("questlog-icon-shrink")
    collapseIcon:SetSize(18, 18)
    collapseIcon:SetPoint("CENTER", 1, -1)

    -- Gear button — left of Collapse
    local gearBtn = AceGUI:Create("Button")
    gearBtn:SetText("")
    gearBtn:SetWidth(22)
    gearBtn:SetHeight(18)
    gearBtn.frame:SetParent(content)
    gearBtn.frame:ClearAllPoints()
    gearBtn.frame:SetPoint("RIGHT", collapseBtn.frame, "LEFT", -2, 0)
    gearBtn.frame:Show()
    local gearIcon = gearBtn.frame:CreateTexture(nil, "ARTWORK")
    gearIcon:SetTexture("Interface\\WorldMap\\GEAR_64GREY")
    gearIcon:SetSize(16, 16)
    gearIcon:SetPoint("CENTER")

    -- Gear dropdown menu
    gearBtn:SetCallback("OnClick", function()
        if not gearDropdownFrame then
            gearDropdownFrame = CreateFrame("Frame", "CDCGearDropdown", UIParent, "UIDropDownMenuTemplate")
        end
        UIDropDownMenu_Initialize(gearDropdownFrame, function(self, level)
            local info = UIDropDownMenu_CreateInfo()
            info.text = "  Hide CDC Tooltips"
            info.checked = function() return CooldownCompanion.db.profile.hideInfoButtons end
            info.isNotRadio = true
            info.keepShownOnClick = true
            info.func = function()
                local val = not CooldownCompanion.db.profile.hideInfoButtons
                CooldownCompanion.db.profile.hideInfoButtons = val
                for _, btn in ipairs(columnInfoButtons) do
                    if val then btn:Hide() else btn:Show() end
                end
                for _, btn in ipairs(tabInfoButtons) do
                    if val then btn:Hide() else btn:Show() end
                end
                for _, btn in ipairs(buttonSettingsInfoButtons) do
                    if val then btn:Hide() else btn:Show() end
                end
            end
            UIDropDownMenu_AddButton(info, level)

            local info2 = UIDropDownMenu_CreateInfo()
            info2.text = "  Close on ESC"
            info2.checked = function() return CooldownCompanion.db.profile.escClosesConfig end
            info2.isNotRadio = true
            info2.keepShownOnClick = true
            info2.func = function()
                CooldownCompanion.db.profile.escClosesConfig = not CooldownCompanion.db.profile.escClosesConfig
            end
            UIDropDownMenu_AddButton(info2, level)
        end, "MENU")
        gearDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ToggleDropDownMenu(1, nil, gearDropdownFrame, gearBtn.frame, 0, 0)
    end)

    -- Mini frame for collapsed state
    local miniFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    miniFrame:SetSize(58, 52)
    miniFrame:SetMovable(true)
    miniFrame:EnableMouse(true)
    miniFrame:RegisterForDrag("LeftButton")
    miniFrame:SetScript("OnDragStart", miniFrame.StartMoving)
    miniFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    miniFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    miniFrame:SetToplevel(true)
    miniFrame:Hide()

    -- Copy backdrop from the main AceGUI frame so skin addons are respected
    local function ApplyMiniFrameBackdrop()
        local backdrop = content.GetBackdrop and content:GetBackdrop()
        if backdrop then
            local copy = {}
            for k, v in pairs(backdrop) do
                if type(v) == "table" then
                    copy[k] = {}
                    for k2, v2 in pairs(v) do copy[k][k2] = v2 end
                else
                    copy[k] = v
                end
            end
            -- Cap edge size so borders don't overlap on the small frame
            local maxEdge = math.min(miniFrame:GetWidth(), miniFrame:GetHeight()) / 2
            if copy.edgeSize and copy.edgeSize > maxEdge then
                copy.edgeSize = maxEdge
            end
            miniFrame:SetBackdrop(copy)
            miniFrame:SetBackdropColor(content:GetBackdropColor())
            miniFrame:SetBackdropBorderColor(content:GetBackdropBorderColor())
        else
            miniFrame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            miniFrame:SetBackdropColor(0, 0, 0, 0.9)
        end
    end

    -- Reset collapse state whenever mini frame is hidden (ESC, /cdc toggle, expand)
    miniFrame:SetScript("OnHide", function()
        isMinimized = false
        collapseIcon:SetAtlas("questlog-icon-shrink")
        collapseBtn.frame:SetParent(content)
        collapseBtn.frame:ClearAllPoints()
        collapseBtn.frame:SetPoint("RIGHT", closeBtn.frame, "LEFT", -2, 0)
    end)

    -- ESC handler for mini frame
    miniFrame:EnableKeyboard(true)
    miniFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and CooldownCompanion.db.profile.escClosesConfig then
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(false)
            end
            self:Hide()
        elseif not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
    end)

    frame._miniFrame = miniFrame

    -- Collapse button callback
    collapseBtn:SetCallback("OnClick", function()
        if isMinimized then
            -- Expand: read mini frame position before hiding
            local miniLeft = miniFrame:GetLeft()
            local miniTop = miniFrame:GetTop()
            miniFrame:Hide() -- OnHide resets state and reparents collapse button

            -- Position main frame so its top-right aligns near where the mini frame was
            content:ClearAllPoints()
            content:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", miniLeft + 58, miniTop)
            content:SetHeight(fullHeight)
            content:SetWidth(1150)
            content:Show()
            CooldownCompanion:RefreshConfigPanel()
        else
            -- Collapse: hide main frame, show mini frame at collapse button position
            CloseDropDownMenus()

            local btnLeft = collapseBtn.frame:GetLeft()
            local btnBottom = collapseBtn.frame:GetBottom()

            isCollapsing = true
            content:Hide()
            isCollapsing = false

            ApplyMiniFrameBackdrop()
            miniFrame:ClearAllPoints()
            miniFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", btnLeft - 18, btnBottom - 17)
            miniFrame:Show()

            -- Reparent collapse button to mini frame
            collapseBtn.frame:SetParent(miniFrame)
            collapseBtn.frame:ClearAllPoints()
            collapseBtn.frame:SetPoint("CENTER")

            collapseIcon:SetAtlas("questlog-icon-expand")
            isMinimized = true
        end
    end)

    -- Profile gear icon next to version/profile text at bottom-left
    local profileGear = CreateFrame("Button", nil, content)
    profileGear:SetSize(16, 16)
    profileGear:SetPoint("LEFT", versionText, "RIGHT", 6, 0)
    local profileGearIcon = profileGear:CreateTexture(nil, "ARTWORK")
    profileGearIcon:SetTexture("Interface\\WorldMap\\GEAR_64GREY")
    profileGearIcon:SetVertexColor(1, 0.9, 0.5)
    profileGearIcon:SetAllPoints()
    profileGear:SetHighlightTexture("Interface\\WorldMap\\GEAR_64GREY")
    profileGear:GetHighlightTexture():SetAlpha(0.3)

    -- Profile bar (expands to the right of gear in bottom dead space)
    local profileBar = CreateFrame("Frame", nil, content)
    profileBar:SetHeight(30)
    profileBar:SetPoint("LEFT", profileGear, "RIGHT", 8, 0)
    profileBar:SetPoint("RIGHT", content, "RIGHT", -20, 0)
    profileBar:Hide()

    profileGear:SetScript("OnClick", function()
        if profileBar:IsShown() then
            profileBar:Hide()
        else
            RefreshProfileBar(profileBar)
            profileBar:Show()
        end
    end)

    -- Column containers fill the content area
    local colParent = CreateFrame("Frame", nil, contentFrame)
    colParent:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -11)
    colParent:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 11)

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
        GameTooltip:AddLine("Right-click for options.", 1, 1, 1, true)
        GameTooltip:AddLine("Middle-click to toggle lock/unlock.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Shift+Left-click to set spec filter.", 1, 1, 1, true)
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
        GameTooltip:AddLine("Right-click for options.", 1, 1, 1, true)
        GameTooltip:AddLine("Middle-click to move to another group.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Ctrl+Left-click to multi-select.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Hold left-click and move to reorder.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag a spell or item from your spellbook or inventory into this column to add it.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-click the Add button to toggle the spellbook.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Button Settings column (between Spells/Items and Group Settings)
    local buttonSettingsCol = AceGUI:Create("InlineGroup")
    buttonSettingsCol:SetTitle("Button Settings")
    buttonSettingsCol:SetLayout("None")
    buttonSettingsCol.frame:SetParent(colParent)
    buttonSettingsCol.frame:Show()

    -- Info button next to Button Settings title
    local bsInfoBtn = CreateFrame("Button", nil, buttonSettingsCol.frame)
    bsInfoBtn:SetSize(16, 16)
    bsInfoBtn:SetPoint("LEFT", buttonSettingsCol.titletext, "RIGHT", -2, 0)
    local bsInfoText = bsInfoBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bsInfoText:SetPoint("CENTER")
    bsInfoText:SetText("|cff66aaff(?)|r")
    bsInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Button Settings")
        GameTooltip:AddLine("These settings apply to the selected spell or item.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bsInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Column 3: Settings (AceGUI InlineGroup)
    local col3 = AceGUI:Create("InlineGroup")
    col3:SetTitle("Group Settings")
    col3:SetLayout("None")
    col3.frame:SetParent(colParent)
    col3.frame:Show()

    -- Info button next to Group Settings title
    local settingsInfoBtn = CreateFrame("Button", nil, col3.frame)
    settingsInfoBtn:SetSize(16, 16)
    settingsInfoBtn:SetPoint("LEFT", col3.titletext, "RIGHT", -2, 0)
    local settingsInfoText = settingsInfoBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    settingsInfoText:SetPoint("CENTER")
    settingsInfoText:SetText("|cff66aaff(?)|r")
    settingsInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Group Settings")
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
    columnInfoButtons[3] = bsInfoBtn
    columnInfoButtons[4] = settingsInfoBtn
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

    local bsScroll = AceGUI:Create("ScrollFrame")
    bsScroll:SetLayout("List")
    bsScroll.frame:SetParent(buttonSettingsCol.content)
    bsScroll.frame:ClearAllPoints()
    bsScroll.frame:SetPoint("TOPLEFT", buttonSettingsCol.content, "TOPLEFT", 0, 0)
    bsScroll.frame:SetPoint("BOTTOMRIGHT", buttonSettingsCol.content, "BOTTOMRIGHT", 0, 0)
    bsScroll.frame:Show()
    buttonSettingsScroll = bsScroll

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

        local col1Width = math.floor(w * 0.18)
        local col2Width = math.floor(w * 0.25)
        local bsWidth   = math.floor(w * 0.28)
        local col3Width  = w - col1Width - col2Width - bsWidth - (pad * 3)

        col1.frame:ClearAllPoints()
        col1.frame:SetPoint("TOPLEFT", colParent, "TOPLEFT", 0, 0)
        col1.frame:SetSize(col1Width, h)

        col2.frame:ClearAllPoints()
        col2.frame:SetPoint("TOPLEFT", col1.frame, "TOPRIGHT", pad, 0)
        col2.frame:SetSize(col2Width, h)

        buttonSettingsCol.frame:ClearAllPoints()
        buttonSettingsCol.frame:SetPoint("TOPLEFT", col2.frame, "TOPRIGHT", pad, 0)
        buttonSettingsCol.frame:SetSize(bsWidth, h)

        col3.frame:ClearAllPoints()
        col3.frame:SetPoint("TOPLEFT", buttonSettingsCol.frame, "TOPRIGHT", pad, 0)
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
    frame.versionText = versionText
    frame.col1 = col1
    frame.col2 = col2
    frame.buttonSettingsCol = buttonSettingsCol
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

    -- Save AceGUI scroll state before any column rebuilds.
    -- AceGUI ScrollFrame uses localstatus.offset/scrollvalue internally (not WoW's
    -- GetVerticalScroll), and FixScroll reads from these on every layout/OnUpdate.
    local function saveScroll(widget)
        if not widget then return nil end
        local s = widget.status or widget.localstatus
        if s and s.offset and s.offset > 0 then
            return { offset = s.offset, scrollvalue = s.scrollvalue }
        end
    end
    local function restoreScroll(widget, saved)
        if not saved or not widget then return end
        local s = widget.status or widget.localstatus
        if s then
            s.offset = saved.offset
            s.scrollvalue = saved.scrollvalue
        end
    end

    local saved1   = saveScroll(col1Scroll)
    local saved2   = saveScroll(col2Scroll)
    local savedBtn = saveScroll(buttonSettingsScroll)

    if configFrame.profileBar:IsShown() then
        RefreshProfileBar(configFrame.profileBar)
    end
    configFrame.versionText:SetText("v1.3  |  " .. (self.db:GetCurrentProfile() or "Default"))
    RefreshColumn1()
    RefreshColumn2()
    RefreshButtonSettingsColumn()
    RefreshColumn3(col3Container)

    -- Restore AceGUI scroll state. LayoutFinished schedules a FixScrollOnUpdate for
    -- next frame, which reads from status.offset — so we write our saved values back
    -- before that fires.
    restoreScroll(col1Scroll, saved1)
    restoreScroll(col2Scroll, saved2)
    restoreScroll(buttonSettingsScroll, savedBtn)

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

    -- If minimized, close everything and reset state
    if configFrame._miniFrame and configFrame._miniFrame:IsShown() then
        configFrame._miniFrame:Hide()
        return
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
