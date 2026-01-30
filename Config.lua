--[[
    CooldownCompanion - Config
    Custom 3-column config panel using AceGUI-3.0 Frame + raw WoW frame positioning
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
local selectedTab = "general"
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

local glowTypeOptions = {
    pixel = "Pixel Glow",
    action = "Action Glow",
    proc = "Proc Glow",
}

-- Layout constants
local COLUMN_PADDING = 8
local HEADER_HEIGHT = 22
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
            end
            CooldownCompanion:RefreshConfigPanel()
        end
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
            local allProfiles = db:GetProfiles()
            local nextProfile = nil
            for _, name in ipairs(allProfiles) do
                if name ~= data.profileName then
                    nextProfile = name
                    break
                end
            end
            if not nextProfile then
                nextProfile = "Default"
            end
            db:SetProfile(nextProfile)
            db:DeleteProfile(data.profileName, true)
            selectedGroup = nil
            selectedButton = nil
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
        end
    end

    if spellId and spellName then
        CooldownCompanion:AddButtonToGroup(selectedGroup, "spell", spellId, spellName)
        CooldownCompanion:Print("Added spell: " .. spellName)
        return true
    else
        CooldownCompanion:Print("Spell not found: " .. input)
        return false
    end
end

------------------------------------------------------------------------
-- Helper: Add item to selected group
------------------------------------------------------------------------
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

    if itemId then
        CooldownCompanion:AddButtonToGroup(selectedGroup, "item", itemId, itemName or "Unknown Item")
        CooldownCompanion:Print("Added item: " .. (itemName or itemId))
        return true
    else
        CooldownCompanion:Print("Item not found: " .. input)
        return false
    end
end

------------------------------------------------------------------------
-- Helper: Get icon for a button data entry
------------------------------------------------------------------------
local function GetButtonIcon(buttonData)
    if buttonData.type == "spell" then
        local info = C_Spell.GetSpellInfo(buttonData.id)
        return info and info.iconID or 134400
    elseif buttonData.type == "item" then
        local _, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(buttonData.id)
        return icon or 134400
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
-- Helper: Create a column backdrop frame
------------------------------------------------------------------------
local function CreateColumnFrame(parent)
    local col = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    col:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    col:SetBackdropColor(0.1, 0.1, 0.1, 0.3)
    col:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    return col
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
-- Helper: Create a header label
------------------------------------------------------------------------
local function CreateHeaderLabel(parent, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText(text)
    label:SetTextColor(1, 0.82, 0, 1)
    return label
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
-- Forward declarations for refresh functions
------------------------------------------------------------------------
local RefreshColumn1, RefreshColumn2, RefreshColumn3, RefreshProfileBar

------------------------------------------------------------------------
-- COLUMN 1: Groups
------------------------------------------------------------------------
function RefreshColumn1()
    if not col1Scroll then return end
    col1Scroll:ReleaseChildren()

    local db = CooldownCompanion.db.profile

    -- Sort group IDs for consistent ordering
    local groupIds = {}
    for id in pairs(db.groups) do
        table.insert(groupIds, id)
    end
    table.sort(groupIds)

    for _, groupId in ipairs(groupIds) do
        local group = db.groups[groupId]
        if group then
            local btn = AceGUI:Create("Button")
            if selectedGroup == groupId then
                btn:SetText("|cff00ff00[ " .. group.name .. " ]|r")
            else
                btn:SetText(group.name)
            end
            btn:SetFullWidth(true)
            btn:SetCallback("OnClick", function()
                selectedGroup = groupId
                selectedButton = nil
                CooldownCompanion:RefreshConfigPanel()
            end)
            col1Scroll:AddChild(btn)
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
            local name = "Group " .. (CooldownCompanion.db.profile.nextGroupId or 1)
            local groupId = CooldownCompanion:CreateGroup(name)
            selectedGroup = groupId
            selectedButton = nil
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
    end)
    inputBox.editbox:HookScript("OnTextChanged", function(self, userInput)
        if userInput then
            newInput = self:GetText()
        end
    end)
    col2Scroll:AddChild(inputBox)

    -- Add Spell / Add Item buttons side by side
    local btnRow = AceGUI:Create("SimpleGroup")
    btnRow:SetFullWidth(true)
    btnRow:SetLayout("Flow")

    local addSpellBtn = AceGUI:Create("Button")
    addSpellBtn:SetText("Add Spell")
    addSpellBtn:SetRelativeWidth(0.5)
    addSpellBtn:SetCallback("OnClick", function()
        if TryAddSpell(newInput) then
            newInput = ""
            CooldownCompanion:RefreshConfigPanel()
        end
    end)
    btnRow:AddChild(addSpellBtn)

    local addItemBtn = AceGUI:Create("Button")
    addItemBtn:SetText("Add Item")
    addItemBtn:SetRelativeWidth(0.5)
    addItemBtn:SetCallback("OnClick", function()
        if TryAddItem(newInput) then
            newInput = ""
            CooldownCompanion:RefreshConfigPanel()
        end
    end)
    btnRow:AddChild(addItemBtn)
    col2Scroll:AddChild(btnRow)

    -- Separator
    local sep = AceGUI:Create("Heading")
    sep:SetText("")
    sep:SetFullWidth(true)
    col2Scroll:AddChild(sep)

    -- Spell/Item list
    for i, buttonData in ipairs(group.buttons) do
        local entry = AceGUI:Create("InteractiveLabel")
        entry:SetText(buttonData.name or ("Unknown " .. buttonData.type))
        entry:SetImage(GetButtonIcon(buttonData))
        entry:SetImageSize(20, 20)
        entry:SetFullWidth(true)
        entry:SetFontObject(GameFontHighlight)
        entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        if selectedButton == i then
            entry:SetColor(0.4, 0.7, 1.0)
        end
        entry:SetCallback("OnClick", function(widget, event, button)
            if button == "LeftButton" then
                selectedButton = i
                CooldownCompanion:RefreshConfigPanel()
            elseif button == "RightButton" then
                local name = buttonData.name or "this entry"
                ShowPopupAboveConfig("CDC_DELETE_BUTTON", name, { groupId = selectedGroup, buttonIndex = i })
            end
        end)
        col2Scroll:AddChild(entry)
    end

    -- Glow settings area (shown when a button is selected)
    if selectedButton and group.buttons[selectedButton] then
        local btnData = group.buttons[selectedButton]

        local glowHeading = AceGUI:Create("Heading")
        glowHeading:SetText("Glow Settings")
        glowHeading:SetFullWidth(true)
        col2Scroll:AddChild(glowHeading)

        -- Show Glow checkbox
        local glowCheck = AceGUI:Create("CheckBox")
        glowCheck:SetLabel("Show Glow")
        glowCheck:SetValue(btnData.showGlow or false)
        glowCheck:SetFullWidth(true)
        glowCheck:SetCallback("OnValueChanged", function(widget, event, val)
            btnData.showGlow = val
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
        end)
        col2Scroll:AddChild(glowCheck)

        -- Glow Type dropdown
        local typeDrop = AceGUI:Create("Dropdown")
        typeDrop:SetLabel("Glow Type")
        typeDrop:SetList(glowTypeOptions)
        typeDrop:SetValue(btnData.glowType or "pixel")
        typeDrop:SetFullWidth(true)
        typeDrop:SetCallback("OnValueChanged", function(widget, event, val)
            btnData.glowType = val
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
        end)
        col2Scroll:AddChild(typeDrop)

        -- Glow Color
        local gc = btnData.glowColor or {1, 1, 0, 1}
        local colorPicker = AceGUI:Create("ColorPicker")
        colorPicker:SetLabel("Glow Color")
        colorPicker:SetHasAlpha(true)
        colorPicker:SetColor(gc[1], gc[2], gc[3], gc[4])
        colorPicker:SetFullWidth(true)
        colorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            btnData.glowColor = {r, g, b, a}
            CooldownCompanion:RefreshGroupFrame(selectedGroup)
        end)
        col2Scroll:AddChild(colorPicker)
    end
end

------------------------------------------------------------------------
-- COLUMN 3: Settings (TabGroup)
------------------------------------------------------------------------
local function BuildGeneralTab(container)
    if not selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end

    -- Group Name
    local nameBox = AceGUI:Create("EditBox")
    nameBox:SetLabel("Group Name")
    nameBox:SetText(group.name or "")
    nameBox:SetFullWidth(true)
    nameBox:SetCallback("OnEnterPressed", function(widget, event, text)
        group.name = text
        CooldownCompanion:RefreshGroupFrame(selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(nameBox)

    -- Enabled toggle
    local enabledCb = AceGUI:Create("CheckBox")
    enabledCb:SetLabel("Enabled")
    enabledCb:SetValue(group.enabled ~= false)
    enabledCb:SetFullWidth(true)
    enabledCb:SetCallback("OnValueChanged", function(widget, event, val)
        group.enabled = val
        CooldownCompanion:RefreshGroupFrame(selectedGroup)
    end)
    container:AddChild(enabledCb)

    -- Lock Frames toggle (global)
    local lockCb = AceGUI:Create("CheckBox")
    lockCb:SetLabel("Lock Frames")
    lockCb:SetValue(CooldownCompanion.db.profile.locked)
    lockCb:SetFullWidth(true)
    lockCb:SetCallback("OnValueChanged", function(widget, event, val)
        CooldownCompanion.db.profile.locked = val
        if val then
            CooldownCompanion:LockAllFrames()
        else
            CooldownCompanion:UnlockAllFrames()
        end
    end)
    container:AddChild(lockCb)
end

local function BuildPositioningTab(container)
    if not selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end

    -- Anchor to Frame
    local anchorBox = AceGUI:Create("EditBox")
    anchorBox:SetLabel("Anchor to Frame")
    local currentAnchor = group.anchor.relativeTo
    if currentAnchor == "UIParent" then currentAnchor = "" end
    anchorBox:SetText(currentAnchor)
    anchorBox:SetFullWidth(true)
    anchorBox:SetCallback("OnEnterPressed", function(widget, event, text)
        local wasAnchored = group.anchor.relativeTo and group.anchor.relativeTo ~= "UIParent"
        if text == "" then
            CooldownCompanion:SetGroupAnchor(selectedGroup, "UIParent", wasAnchored)
        else
            CooldownCompanion:SetGroupAnchor(selectedGroup, text)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(anchorBox)

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

    -- X Offset
    local xSlider = AceGUI:Create("Slider")
    xSlider:SetLabel("X Offset")
    xSlider:SetSliderValues(-500, 500, 1)
    xSlider:SetValue(group.anchor.x or 0)
    xSlider:SetFullWidth(true)
    xSlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.x = val
        local frame = CooldownCompanion.groupFrames[selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    container:AddChild(xSlider)

    -- Y Offset
    local ySlider = AceGUI:Create("Slider")
    ySlider:SetLabel("Y Offset")
    ySlider:SetSliderValues(-500, 500, 1)
    ySlider:SetValue(group.anchor.y or 0)
    ySlider:SetFullWidth(true)
    ySlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.y = val
        local frame = CooldownCompanion.groupFrames[selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
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

    -- Buttons Per Row
    local bprSlider = AceGUI:Create("Slider")
    bprSlider:SetLabel("Buttons Per Row/Column")
    bprSlider:SetSliderValues(1, 24, 1)
    bprSlider:SetValue(group.style.buttonsPerRow or 12)
    bprSlider:SetFullWidth(true)
    bprSlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.style.buttonsPerRow = val
        CooldownCompanion:RefreshGroupFrame(selectedGroup)
    end)
    container:AddChild(bprSlider)
end

local function BuildAppearanceTab(container)
    if not selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end
    local style = group.style

    -- Square Icons toggle
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

    if style.maintainAspectRatio then
        -- Button Size (square)
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
        -- Icon Width
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

        -- Icon Height
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

    -- Button Spacing
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

    -- Border Size
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

    -- Border Color
    local borderColor = AceGUI:Create("ColorPicker")
    borderColor:SetLabel("Border Color")
    borderColor:SetHasAlpha(true)
    local bc = style.borderColor or {0, 0, 0, 1}
    borderColor:SetColor(bc[1], bc[2], bc[3], bc[4])
    borderColor:SetFullWidth(true)
    borderColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.borderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(borderColor)

    -- Background Color
    local bgColor = AceGUI:Create("ColorPicker")
    bgColor:SetLabel("Background Color")
    bgColor:SetHasAlpha(true)
    local bgc = style.backgroundColor or {0, 0, 0, 0.5}
    bgColor:SetColor(bgc[1], bgc[2], bgc[3], bgc[4])
    bgColor:SetFullWidth(true)
    bgColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.backgroundColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(bgColor)
end

local function BuildDisplayTab(container)
    if not selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[selectedGroup]
    if not group then return end
    local style = group.style

    -- Show Cooldown Text
    local cdTextCb = AceGUI:Create("CheckBox")
    cdTextCb:SetLabel("Show Cooldown Text")
    cdTextCb:SetValue(style.showCooldownText or false)
    cdTextCb:SetFullWidth(true)
    cdTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showCooldownText = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(cdTextCb)

    -- Font Size
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

    -- Font dropdown
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

    -- Font Outline
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

    -- Desaturate On Cooldown
    local desatCb = AceGUI:Create("CheckBox")
    desatCb:SetLabel("Desaturate On Cooldown")
    desatCb:SetValue(style.desaturateOnCooldown or false)
    desatCb:SetFullWidth(true)
    desatCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.desaturateOnCooldown = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(desatCb)

    -- Show Tooltips
    local tooltipCb = AceGUI:Create("CheckBox")
    tooltipCb:SetLabel("Show Tooltips")
    tooltipCb:SetValue(style.showTooltips ~= false)
    tooltipCb:SetFullWidth(true)
    tooltipCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showTooltips = val
        CooldownCompanion:UpdateGroupStyle(selectedGroup)
    end)
    container:AddChild(tooltipCb)
end

function RefreshColumn3(container)
    -- Release previous tab group if stored
    if container.tabGroup then
        container.tabGroup:Release()
        container.tabGroup = nil
    end

    if not selectedGroup then
        -- Show placeholder
        if not container.placeholderLabel then
            container.placeholderLabel = container:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            container.placeholderLabel:SetPoint("TOPLEFT", 8, -8)
        end
        container.placeholderLabel:SetText("Select a group to configure")
        container.placeholderLabel:Show()
        return
    end

    if container.placeholderLabel then
        container.placeholderLabel:Hide()
    end

    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetTabs({
        { value = "general",     text = "General" },
        { value = "positioning", text = "Positioning" },
        { value = "appearance",  text = "Appearance" },
        { value = "display",     text = "Display" },
    })
    tabGroup:SetLayout("Fill")
    tabGroup:SelectTab(selectedTab)

    tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
        selectedTab = tab
        widget:ReleaseChildren()

        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        widget:AddChild(scroll)

        if tab == "general" then
            BuildGeneralTab(scroll)
        elseif tab == "positioning" then
            BuildPositioningTab(scroll)
        elseif tab == "appearance" then
            BuildAppearanceTab(scroll)
        elseif tab == "display" then
            BuildDisplayTab(scroll)
        end
    end)

    -- Parent the AceGUI widget frame to our raw column frame
    tabGroup.frame:SetParent(container)
    tabGroup.frame:ClearAllPoints()
    tabGroup.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -4)
    tabGroup.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4, 4)
    tabGroup.frame:Show()

    container.tabGroup = tabGroup

    -- Trigger initial tab render
    tabGroup:SelectTab(selectedTab)
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
        ShowPopupAboveConfig("CDC_DELETE_PROFILE", currentProfile, { profileName = currentProfile })
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
    frame:SetWidth(1050)
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
            content:SetWidth(1050)
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
            content:SetWidth(1050)
            frame:SetStatusText("")
            isMinimized = true
        end
    end)

    -- Profile bar at the top
    local profileBar = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
    profileBar:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    profileBar:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, 0)
    profileBar:SetHeight(PROFILE_BAR_HEIGHT)
    profileBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    profileBar:SetBackdropColor(0.15, 0.15, 0.15, 0.5)
    profileBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)

    -- Column containers below profile bar
    local colParent = CreateFrame("Frame", nil, contentFrame)
    colParent:SetPoint("TOPLEFT", profileBar, "BOTTOMLEFT", 0, -4)
    colParent:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)

    -- Column 1: Groups (20%)
    local col1 = CreateColumnFrame(colParent)
    -- Column 2: Spells/Items (35%)
    local col2 = CreateColumnFrame(colParent)
    -- Column 3: Settings (45%)
    local col3 = CreateColumnFrame(colParent)

    -- Column headers
    local col1Header = CreateHeaderLabel(col1, "Groups")
    col1Header:SetPoint("TOPLEFT", col1, "TOPLEFT", 8, -6)

    local col2Header = CreateHeaderLabel(col2, "Spells / Items")
    col2Header:SetPoint("TOPLEFT", col2, "TOPLEFT", 8, -6)

    -- Info button next to Spells / Items header
    local infoBtn = CreateFrame("Button", nil, col2)
    infoBtn:SetSize(16, 16)
    infoBtn:SetPoint("LEFT", col2Header, "RIGHT", 4, 0)
    local infoText = infoBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("CENTER")
    infoText:SetText("|cff66aaff(?)|r")
    infoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Spells / Items")
        GameTooltip:AddLine("Enter a spell or item name/ID in the input box,", 1, 1, 1, true)
        GameTooltip:AddLine("then click Add Spell or Add Item to track it.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-click an entry to remove it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local col3Header = CreateHeaderLabel(col3, "Settings")
    col3Header:SetPoint("TOPLEFT", col3, "TOPLEFT", 8, -6)

    -- Static button bar at bottom of column 1 (New / Delete)
    local btnBar = CreateFrame("Frame", nil, col1)
    btnBar:SetPoint("BOTTOMLEFT", col1, "BOTTOMLEFT", 4, 4)
    btnBar:SetPoint("BOTTOMRIGHT", col1, "BOTTOMRIGHT", -4, 4)
    btnBar:SetHeight(28)
    col1ButtonBar = btnBar

    -- AceGUI ScrollFrames in columns 1 and 2
    local scroll1 = AceGUI:Create("ScrollFrame")
    scroll1:SetLayout("List")
    scroll1.frame:SetParent(col1)
    scroll1.frame:ClearAllPoints()
    scroll1.frame:SetPoint("TOPLEFT", col1, "TOPLEFT", 4, -(HEADER_HEIGHT + 4))
    scroll1.frame:SetPoint("BOTTOMRIGHT", col1, "BOTTOMRIGHT", -4, 32)
    scroll1.frame:Show()
    col1Scroll = scroll1

    local scroll2 = AceGUI:Create("ScrollFrame")
    scroll2:SetLayout("List")
    scroll2.frame:SetParent(col2)
    scroll2.frame:ClearAllPoints()
    scroll2.frame:SetPoint("TOPLEFT", col2, "TOPLEFT", 4, -(HEADER_HEIGHT + 4))
    scroll2.frame:SetPoint("BOTTOMRIGHT", col2, "BOTTOMRIGHT", -4, 4)
    scroll2.frame:Show()
    col2Scroll = scroll2

    -- Column 3 content area (below header)
    local col3Content = CreateFrame("Frame", nil, col3)
    col3Content:SetPoint("TOPLEFT", col3, "TOPLEFT", 0, -(HEADER_HEIGHT + 4))
    col3Content:SetPoint("BOTTOMRIGHT", col3, "BOTTOMRIGHT", 0, 0)
    col3Container = col3Content

    -- Layout columns on size change
    local function LayoutColumns()
        local w = colParent:GetWidth()
        local h = colParent:GetHeight()
        local pad = COLUMN_PADDING

        local col1Width = math.floor(w * 0.20)
        local col2Width = math.floor(w * 0.30)
        local col3Width = w - col1Width - col2Width - (pad * 2)

        col1:ClearAllPoints()
        col1:SetPoint("TOPLEFT", colParent, "TOPLEFT", 0, 0)
        col1:SetSize(col1Width, h)

        col2:ClearAllPoints()
        col2:SetPoint("TOPLEFT", col1, "TOPRIGHT", pad, 0)
        col2:SetSize(col2Width, h)

        col3:ClearAllPoints()
        col3:SetPoint("TOPLEFT", col2, "TOPRIGHT", pad, 0)
        col3:SetSize(col3Width, h)
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
    frame.col2Frame = col2  -- kept for reference
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
        if configFrame and configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
    self.db.RegisterCallback(self, "OnProfileCopied", function()
        selectedGroup = nil
        selectedButton = nil
        if configFrame and configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
    self.db.RegisterCallback(self, "OnProfileReset", function()
        selectedGroup = nil
        selectedButton = nil
        if configFrame and configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
end
