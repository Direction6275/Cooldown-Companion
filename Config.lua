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

-- Folder collapse state (transient UI state, resets on profile change)
local collapsedFolders = {}    -- [folderId] = true when collapsed
local folderContextMenu = nil  -- reusable dropdown frame

-- Pick-frame overlay state
local pickFrameOverlay = nil
local pickFrameCallback = nil

-- Pick-CDM overlay state
local pickCDMOverlay = nil
local pickCDMCallback = nil

-- Autocomplete state
local autocompleteDropdown = nil
local autocompleteCache = nil
local pendingEditBoxFocus = false
local AUTOCOMPLETE_MAX_ROWS = 10
local AUTOCOMPLETE_ROW_HEIGHT = 22
local AUTOCOMPLETE_ICON_SIZE = 20

-- Viewer frame names (mirrors Core.lua's local VIEWER_NAMES)
local CDM_VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

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

-- Shared config state table: exposed to ConfigSettings.lua via addon namespace.
-- Mutable references that both files read/write are stored here.
ST._configState = {
    -- Selection state (mutable, updated by Config.lua, read by ConfigSettings.lua)
    -- Note: These are getter/setter functions since Lua tables store by value for primitives.
    -- We use a table wrapper so ConfigSettings.lua can read/write the same state.
    selectedGroup = nil,    -- set by Config.lua
    selectedButton = nil,   -- set by Config.lua
    selectedButtons = selectedButtons,
    selectedTab = nil,      -- set/read by both files
    -- UI state tables (both files read/write)
    collapsedSections = collapsedSections,
    buttonSettingsInfoButtons = buttonSettingsInfoButtons,
    buttonSettingsCollapseButtons = buttonSettingsCollapseButtons,
    buttonSettingsScroll = nil,   -- set by Config.lua
    configFrame = nil,            -- set by Config.lua
    col3Container = nil,          -- set by Config.lua
    pendingStrataOrder = nil,     -- set by both files
    pendingStrataGroup = nil,     -- set by both files
    -- Tab UI state (populated by ConfigSettings.lua, cleaned by both files)
    tabInfoButtons = {},
    appearanceTabElements = {},
    -- Static lookup tables
    fontOptions = fontOptions,
    outlineOptions = outlineOptions,
    strataElementLabels = strataElementLabels,
    strataElementKeys = strataElementKeys,
}
local CS = ST._configState

-- Sync local selection state into the shared config state table.
-- Called before invoking any ConfigSettings.lua builder function.
local function SyncConfigState()
    CS.selectedGroup = selectedGroup
    CS.selectedButton = selectedButton
    CS.selectedTab = selectedTab
    CS.buttonSettingsScroll = buttonSettingsScroll
    CS.configFrame = configFrame
    CS.col3Container = col3Container
end

-- Expose functions that ConfigSettings.lua needs to call back
CS.IsStrataOrderComplete = nil   -- set after definition below
CS.InitPendingStrataOrder = nil  -- set after definition below
CS.StartPickFrame = nil          -- set after definition below
CS.StartPickCDM = nil            -- set after definition below

local function IsStrataOrderComplete(order)
    if not order then return false end
    for i = 1, 4 do
        if not order[i] then return false end
    end
    return true
end

local function InitPendingStrataOrder(groupId)
    if CS.pendingStrataGroup == groupId and CS.pendingStrataOrder then return end
    CS.pendingStrataGroup = groupId
    local groups = CooldownCompanion.db.profile.groups
    local group = groups[groupId]
    local saved = group and group.style and group.style.strataOrder
    if saved and IsStrataOrderComplete(saved) then
        CS.pendingStrataOrder = {}
        for i = 1, 4 do
            CS.pendingStrataOrder[i] = saved[i]
        end
    else
        CS.pendingStrataOrder = {}
        for i = 1, 4 do
            CS.pendingStrataOrder[i] = ST.DEFAULT_STRATA_ORDER[i]
        end
    end
end

CS.IsStrataOrderComplete = IsStrataOrderComplete
CS.InitPendingStrataOrder = InitPendingStrataOrder

-- Anchor point options (shared with ConfigSettings.lua)
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
CS.anchorPoints = anchorPoints
CS.anchorPointLabels = anchorPointLabels

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
    text = "Delete folder '%s'? Groups inside will be kept (moved to top level).",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.folderId then
            CooldownCompanion:DeleteFolder(data.folderId)
            CooldownCompanion:RefreshConfigPanel()
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
    if not name or type(name) ~= "string" then return true end
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
-- Helper: Start pick-CDM mode (select a spell from Cooldown Manager)
------------------------------------------------------------------------
local function FinishPickCDM(spellID)
    if not pickCDMOverlay then return end
    pickCDMOverlay:Hide()
    CooldownCompanion:ApplyCdmAlpha()
    local cb = pickCDMCallback
    pickCDMCallback = nil
    if cb then
        cb(spellID)
    end
end

local function StartPickCDM(callback)
    pickCDMCallback = callback

    -- Create overlay lazily
    if not pickCDMOverlay then
        local overlay = CreateFrame("Frame", "CooldownCompanionPickCDMOverlay", UIParent)
        overlay:SetFrameStrata("FULLSCREEN_DIALOG")
        overlay:SetFrameLevel(100)
        overlay:SetAllPoints(UIParent)
        overlay:EnableMouse(true)
        overlay:EnableKeyboard(true)

        -- Semi-transparent dark background
        local bg = overlay:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.3)
        overlay.bg = bg

        -- Instruction text at top
        local instructions = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        instructions:SetPoint("TOP", overlay, "TOP", 0, -30)
        instructions:SetText("Click a buff/debuff in the Cooldown Manager  |  Right-click or Escape to cancel")
        instructions:SetTextColor(1, 1, 1, 0.9)
        overlay.instructions = instructions

        -- Cursor-following label showing spell name/ID
        local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        label:SetTextColor(0.2, 1, 0.2, 1)
        overlay.label = label

        -- Highlight frame (colored border that outlines hovered CDM child)
        local highlight = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
        highlight:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
        })
        highlight:SetBackdropBorderColor(0, 1, 0, 0.9)
        highlight:Hide()
        overlay.highlight = highlight

        -- OnUpdate: detect CDM child under cursor
        overlay:SetScript("OnUpdate", function(self, dt)
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale

            local bestChild, bestArea, bestSpellID, bestName, bestIsAuraViewer

            for _, viewerName in ipairs(CDM_VIEWER_NAMES) do
                local viewer = _G[viewerName]
                if viewer then
                    local isAuraViewer = viewerName == "BuffIconCooldownViewer" or viewerName == "BuffBarCooldownViewer"
                    for _, child in pairs({viewer:GetChildren()}) do
                        if child.cooldownInfo and child:IsVisible() then
                            local ok, left, bottom, width, height = pcall(child.GetRect, child)
                            if ok and left and width and width > 0 and height > 0 then
                                if cx >= left and cx <= left + width and cy >= bottom and cy <= bottom + height then
                                    local area = width * height
                                    if not bestArea or area < bestArea then
                                        local info = child.cooldownInfo
                                        local sid = info.overrideSpellID or info.spellID
                                        if sid then
                                            bestChild = child
                                            bestArea = area
                                            bestSpellID = sid
                                            bestIsAuraViewer = isAuraViewer
                                            local spellInfo = C_Spell.GetSpellInfo(sid)
                                            bestName = spellInfo and spellInfo.name or tostring(sid)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Also scan the CDM Settings panel (CooldownViewerSettings) if open
            local settingsPanel = CooldownViewerSettings
            if settingsPanel and settingsPanel:IsVisible() and settingsPanel.categoryPool then
                for categoryDisplay in settingsPanel.categoryPool:EnumerateActive() do
                    if categoryDisplay.itemPool then
                        local catObj = categoryDisplay:GetCategoryObject()
                        local isAuraCat = catObj and (catObj:GetCategory() == Enum.CooldownViewerCategory.TrackedBuff or catObj:GetCategory() == Enum.CooldownViewerCategory.TrackedBar)
                        for item in categoryDisplay.itemPool:EnumerateActive() do
                            if item:IsVisible() and not item:IsEmptyCategory() then
                                local ok, left, bottom, width, height = pcall(item.GetRect, item)
                                if ok and left and width and width > 0 and height > 0 then
                                    if cx >= left and cx <= left + width and cy >= bottom and cy <= bottom + height then
                                        local area = width * height
                                        if not bestArea or area < bestArea then
                                            local info = item:GetCooldownInfo()
                                            local sid = info and (info.overrideSpellID or info.spellID)
                                            if sid then
                                                bestChild = item
                                                bestArea = area
                                                bestSpellID = sid
                                                bestIsAuraViewer = isAuraCat
                                                local spellInfo = C_Spell.GetSpellInfo(sid)
                                                bestName = spellInfo and spellInfo.name or tostring(sid)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            self.currentSpellID = bestSpellID

            if not bestChild then
                self.label:SetText("")
                self.highlight:Hide()
                return
            end

            -- Color: green for BuffIcon/BuffBar (aura-capable), red for Essential/Utility (not a buff/debuff)
            if bestIsAuraViewer then
                self.label:SetTextColor(0.2, 1, 0.2, 1)
            else
                self.label:SetTextColor(1, 0.3, 0.3, 1)
            end

            self.label:ClearAllPoints()
            self.label:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx + 20, cy + 10)
            local suffix = bestIsAuraViewer and "TRACKABLE AURA" or "NOT AN AURA"
            self.label:SetText(bestName .. "  |  " .. bestSpellID .. "  |  " .. suffix)

            local ok, left, bottom, width, height = pcall(bestChild.GetRect, bestChild)
            if ok and left and width and width > 0 and height > 0 then
                self.highlight:ClearAllPoints()
                self.highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
                self.highlight:SetSize(width, height)
                if bestIsAuraViewer then
                    self.highlight:SetBackdropBorderColor(0, 1, 0, 0.9)
                else
                    self.highlight:SetBackdropBorderColor(1, 0.3, 0.3, 0.9)
                end
                self.highlight:Show()
            else
                self.highlight:Hide()
            end
        end)

        -- Detect clicks via GLOBAL_MOUSE_DOWN
        overlay:RegisterEvent("GLOBAL_MOUSE_DOWN")
        overlay:SetScript("OnEvent", function(self, event, button)
            if event ~= "GLOBAL_MOUSE_DOWN" then return end
            if button == "LeftButton" then
                FinishPickCDM(self.currentSpellID)
            elseif button == "RightButton" then
                FinishPickCDM(nil)
            end
        end)

        -- Escape to cancel
        overlay:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                FinishPickCDM(nil)
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

        pickCDMOverlay = overlay
    end

    -- Hide config panel, show overlay
    if configFrame and configFrame.frame:IsShown() then
        configFrame.frame:Hide()
    end
    -- Temporarily show CDM if hidden
    if CooldownCompanion.db.profile.cdmHidden then
        for _, name in ipairs(CDM_VIEWER_NAMES) do
            local viewer = _G[name]
            if viewer then
                viewer:SetAlpha(1)
            end
        end
    end
    pickCDMOverlay.currentSpellID = nil
    pickCDMOverlay.label:SetText("")
    pickCDMOverlay.highlight:Hide()
    pickCDMOverlay:Show()
end

CS.StartPickFrame = StartPickFrame
CS.StartPickCDM = StartPickCDM

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
-- Autocomplete: Build cache of player spells + usable bag items
------------------------------------------------------------------------
local function BuildAutocompleteCache()
    local cache = {}
    local seen = {}

    -- Iterate spellbook skill lines
    local numLines = C_SpellBook.GetNumSpellBookSkillLines()
    for lineIdx = 1, numLines do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIdx)
        if lineInfo and not lineInfo.shouldHide then
            local category = lineInfo.name or "Spells"
            for slotOffset = 1, lineInfo.numSpellBookItems do
                local slotIdx = lineInfo.itemIndexOffset + slotOffset
                local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIdx, Enum.SpellBookSpellBank.Player)
                if itemInfo and itemInfo.spellID
                    and not itemInfo.isPassive
                    and not itemInfo.isOffSpec
                    and itemInfo.itemType ~= Enum.SpellBookItemType.Flyout
                    and itemInfo.itemType ~= Enum.SpellBookItemType.FutureSpell
                then
                    local id = itemInfo.spellID
                    if not seen[id] then
                        seen[id] = true
                        table.insert(cache, {
                            id = id,
                            name = itemInfo.name,
                            nameLower = itemInfo.name:lower(),
                            icon = itemInfo.iconID or 134400,
                            category = category,
                            isItem = false,
                        })
                    end
                end
            end
        end
    end

    -- Iterate bags for usable items
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
            if containerInfo and containerInfo.itemID then
                local itemID = containerInfo.itemID
                if not seen["item:" .. itemID] then
                    local spellName = C_Item.GetItemSpell(itemID)
                    if spellName then
                        seen["item:" .. itemID] = true
                        local itemName = containerInfo.itemName or C_Item.GetItemNameByID(itemID) or "Unknown"
                        table.insert(cache, {
                            id = itemID,
                            name = itemName,
                            nameLower = itemName:lower(),
                            icon = containerInfo.iconFileID or C_Item.GetItemIconByID(itemID) or 134400,
                            category = "Item",
                            isItem = true,
                        })
                    end
                end
            end
        end
    end

    autocompleteCache = cache
    return cache
end

------------------------------------------------------------------------
-- Autocomplete: Search cache for matches
------------------------------------------------------------------------
local function SearchAutocomplete(query)
    if not query or #query < 1 then return nil end

    local cache = autocompleteCache or BuildAutocompleteCache()
    local queryLower = query:lower()
    local queryNum = tonumber(query)
    local prefixMatches = {}
    local substringMatches = {}

    for _, entry in ipairs(cache) do
        local isMatch = false
        local isPrefix = false

        -- Match by numeric ID
        if queryNum and tostring(entry.id):find(query, 1, true) == 1 then
            isMatch = true
            isPrefix = true
        end

        -- Match by name substring
        if not isMatch then
            local pos = entry.nameLower:find(queryLower, 1, true)
            if pos then
                isMatch = true
                isPrefix = (pos == 1)
            end
        end

        if isMatch then
            if isPrefix then
                table.insert(prefixMatches, entry)
            else
                table.insert(substringMatches, entry)
            end
        end

        -- Early exit if we have enough prefix matches
        if #prefixMatches >= AUTOCOMPLETE_MAX_ROWS then break end
    end

    -- Combine: prefix matches first, then substring matches
    local results = {}
    for _, entry in ipairs(prefixMatches) do
        table.insert(results, entry)
        if #results >= AUTOCOMPLETE_MAX_ROWS then break end
    end
    if #results < AUTOCOMPLETE_MAX_ROWS then
        for _, entry in ipairs(substringMatches) do
            table.insert(results, entry)
            if #results >= AUTOCOMPLETE_MAX_ROWS then break end
        end
    end

    return #results > 0 and results or nil
end

------------------------------------------------------------------------
-- Autocomplete: Hide dropdown
------------------------------------------------------------------------
local function HideAutocomplete()
    if autocompleteDropdown then
        autocompleteDropdown:Hide()
    end
end

------------------------------------------------------------------------
-- Autocomplete: Update keyboard selection highlight
------------------------------------------------------------------------
local function UpdateAutocompleteHighlight()
    if not autocompleteDropdown then return end
    local idx = autocompleteDropdown._highlightIndex or 0
    for i, row in ipairs(autocompleteDropdown.rows) do
        if row.selectionBg then
            if i == idx then
                row.selectionBg:Show()
            else
                row.selectionBg:Hide()
            end
        end
    end
end

------------------------------------------------------------------------
-- Autocomplete: Select handler
------------------------------------------------------------------------
local function OnAutocompleteSelect(entry)
    HideAutocomplete()
    if not selectedGroup then return end
    local added
    if entry.isItem then
        added = TryAddItem(tostring(entry.id))
    else
        added = TryAddSpell(tostring(entry.id))
    end
    if added then
        newInput = ""
        pendingEditBoxFocus = true
        CooldownCompanion:RefreshConfigPanel()
    end
end

------------------------------------------------------------------------
-- Autocomplete: Create or return the reusable dropdown frame
------------------------------------------------------------------------
local function GetOrCreateAutocompleteDropdown()
    if autocompleteDropdown then return autocompleteDropdown end

    local dropdown = CreateFrame("Frame", "CooldownCompanionAutocomplete", UIParent, "BackdropTemplate")
    dropdown:SetFrameStrata("TOOLTIP")
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dropdown:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    dropdown:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    dropdown:Hide()

    dropdown.rows = {}
    for i = 1, AUTOCOMPLETE_MAX_ROWS do
        local row = CreateFrame("Button", nil, dropdown)
        row:SetHeight(AUTOCOMPLETE_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 1, -((i - 1) * AUTOCOMPLETE_ROW_HEIGHT) - 1)
        row:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -1, -((i - 1) * AUTOCOMPLETE_ROW_HEIGHT) - 1)

        -- Keyboard selection highlight (manually shown/hidden)
        local selectionBg = row:CreateTexture(nil, "BACKGROUND")
        selectionBg:SetAllPoints()
        selectionBg:SetColorTexture(0.2, 0.4, 0.7, 0.4)
        selectionBg:Hide()
        row.selectionBg = selectionBg

        -- Mouse hover highlight
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.3, 0.5, 0.8, 0.3)

        -- Icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(AUTOCOMPLETE_ICON_SIZE, AUTOCOMPLETE_ICON_SIZE)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.icon = icon

        -- Name text
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        nameText:SetPoint("RIGHT", row, "RIGHT", -80, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        row.nameText = nameText

        -- Category text
        local categoryText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        categoryText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        categoryText:SetJustifyH("RIGHT")
        categoryText:SetTextColor(0.5, 0.5, 0.5, 1)
        row.categoryText = categoryText

        row:SetScript("OnMouseDown", function()
            dropdown._clickInProgress = true
        end)

        row:SetScript("OnClick", function()
            dropdown._clickInProgress = false
            if row.entry then
                OnAutocompleteSelect(row.entry)
            end
        end)

        row:Hide()
        dropdown.rows[i] = row
    end

    -- Hide when edit box loses focus (checked via OnUpdate)
    dropdown:SetScript("OnUpdate", function(self)
        if self._clickInProgress then return end
        if self._editbox and not self._editbox:HasFocus() then
            self:Hide()
        end
    end)

    autocompleteDropdown = dropdown
    return dropdown
end

------------------------------------------------------------------------
-- Autocomplete: Show results anchored to an edit box widget
------------------------------------------------------------------------
local function ShowAutocompleteResults(results, anchorWidget)
    local dropdown = GetOrCreateAutocompleteDropdown()

    if not results then
        dropdown:Hide()
        return
    end

    -- Anchor below the edit box widget's frame (parented to UIParent, so it draws above the config panel)
    local anchorFrame = anchorWidget.frame or anchorWidget
    dropdown:ClearAllPoints()
    dropdown:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    dropdown:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -2)

    local numResults = #results
    dropdown._highlightIndex = 1
    dropdown._numResults = numResults
    dropdown:SetHeight((numResults * AUTOCOMPLETE_ROW_HEIGHT) + 2)

    for i = 1, AUTOCOMPLETE_MAX_ROWS do
        local row = dropdown.rows[i]
        if i <= numResults then
            local entry = results[i]
            row.entry = entry
            row.icon:SetTexture(entry.icon)
            row.nameText:SetText(entry.name)
            row.categoryText:SetText(entry.category)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end

    dropdown:Show()
    UpdateAutocompleteHighlight()
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

-- Drop target detection for column 1 with folder support.
-- Returns a table describing where the drop would land:
--   { action="reorder-before"|"reorder-after"|"into-folder", rowIndex=N, targetRow=<row-meta>, anchorFrame=<frame> }
-- or nil if no valid drop target.
local function GetCol1DropTarget(cursorY, renderedRows, sourceKind)
    if not renderedRows or #renderedRows == 0 then return nil end

    for i, rowMeta in ipairs(renderedRows) do
        local frame = rowMeta.widget and rowMeta.widget.frame
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            local bottom = frame:GetBottom()
            if top and bottom and cursorY <= top and cursorY >= bottom then
                local height = top - bottom
                -- If hovering over a folder header and dragging a group, use 3-zone detection
                if rowMeta.kind == "folder" and (sourceKind == "group" or sourceKind == "folder-group") then
                    local topZone = top - height * 0.25
                    local bottomZone = bottom + height * 0.25
                    if cursorY > topZone then
                        return { action = "reorder-before", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
                    elseif cursorY < bottomZone then
                        return { action = "reorder-after", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
                    else
                        return { action = "into-folder", rowIndex = i, targetRow = rowMeta, anchorFrame = frame, targetFolderId = rowMeta.id }
                    end
                else
                    -- Standard 2-zone (above/below midpoint)
                    local mid = (top + bottom) / 2
                    if cursorY > mid then
                        return { action = "reorder-before", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
                    else
                        return { action = "reorder-after", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
                    end
                end
            end
        end
    end

    -- Below all rows: drop after last
    local lastRow = renderedRows[#renderedRows]
    local lastFrame = lastRow and lastRow.widget and lastRow.widget.frame
    if lastFrame and lastFrame:IsShown() then
        return { action = "reorder-after", rowIndex = #renderedRows, targetRow = lastRow, anchorFrame = lastFrame }
    end
    return nil
end

-- Show drag indicator for "into-folder" drops (highlight overlay on folder row)
local function ShowFolderDropOverlay(anchorFrame, parentScrollWidget)
    local ind = GetDragIndicator()
    local width = parentScrollWidget.content:GetWidth() or 100
    ind:SetWidth(width)
    ind:SetHeight(anchorFrame:GetHeight() or 24)
    ind:ClearAllPoints()
    ind:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
    ind.tex:SetColorTexture(0.4, 0.7, 0.2, 0.3)
    ind:Show()
end

-- Reset drag indicator to default line style
local function ResetDragIndicatorStyle()
    if dragIndicator and dragIndicator.tex then
        dragIndicator:SetHeight(2)
        dragIndicator.tex:SetColorTexture(0.2, 0.6, 1.0, 1.0)
    end
end

-- Apply a column-1 folder-aware drop result.
-- Called from FinishDrag for group/folder/folder-group drag kinds.
local function ApplyCol1Drop(state)
    local dropTarget = state.dropTarget
    if not dropTarget then return end

    local db = CooldownCompanion.db.profile

    if state.kind == "group" or state.kind == "folder-group" then
        local sourceGroupId = state.sourceGroupId
        local group = db.groups[sourceGroupId]
        if not group then return end

        if dropTarget.action == "into-folder" then
            -- Move group into the target folder
            group.folderId = dropTarget.targetFolderId
        elseif dropTarget.action == "reorder-before" or dropTarget.action == "reorder-after" then
            local targetRow = dropTarget.targetRow
            -- If dropping on a row that's in a folder, join that folder
            if targetRow.kind == "group" and targetRow.inFolder then
                group.folderId = targetRow.inFolder
            elseif targetRow.kind == "folder" then
                -- Dropping before/after a folder header = top-level
                group.folderId = nil
            else
                -- Dropping on a loose group = stay/become loose
                group.folderId = nil
            end

            -- Reassign order values for all items in the target section
            -- to place the dragged group at the right position
            local section = targetRow.section or state.sourceSection
            local renderedRows = state.col1RenderedRows
            if renderedRows then
                -- Build ordered list of items in the same container (folder or top-level)
                -- and reassign order values
                local targetFolderId = group.folderId
                local orderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.section == section then
                        if targetFolderId then
                            -- Ordering within a folder: collect groups in same folder
                            if row.kind == "group" and row.inFolder == targetFolderId and row.id ~= sourceGroupId then
                                table.insert(orderItems, row.id)
                            end
                        else
                            -- Top-level ordering: collect top-level items (folders + loose groups)
                            if (row.kind == "folder") or (row.kind == "group" and not row.inFolder) then
                                if row.id ~= sourceGroupId then
                                    table.insert(orderItems, { kind = row.kind, id = row.id })
                                end
                            end
                        end
                    end
                end

                -- Find insertion position
                local insertPos
                if targetFolderId then
                    -- Within folder: find target group position
                    insertPos = #orderItems + 1
                    for idx, gid in ipairs(orderItems) do
                        if gid == dropTarget.targetRow.id then
                            insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                            break
                        end
                    end
                    table.insert(orderItems, insertPos, sourceGroupId)
                    for i, gid in ipairs(orderItems) do
                        db.groups[gid].order = i
                    end
                else
                    -- Top-level: find target position among mixed items
                    insertPos = #orderItems + 1
                    for idx, item in ipairs(orderItems) do
                        if item.kind == dropTarget.targetRow.kind and item.id == dropTarget.targetRow.id then
                            insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                            break
                        end
                    end
                    table.insert(orderItems, insertPos, { kind = "group", id = sourceGroupId })
                    for i, item in ipairs(orderItems) do
                        if item.kind == "folder" then
                            db.folders[item.id].order = i
                        else
                            db.groups[item.id].order = i
                        end
                    end
                end
            end
        end
    elseif state.kind == "folder" then
        local sourceFolderId = state.sourceFolderId
        local folder = db.folders[sourceFolderId]
        if not folder then return end

        local dropTarget = state.dropTarget
        local targetRow = dropTarget.targetRow
        local section = targetRow.section or state.sourceSection

        -- Build top-level items for the section (excluding the source folder)
        local renderedRows = state.col1RenderedRows
        if renderedRows then
            local orderItems = {}
            for _, row in ipairs(renderedRows) do
                if row.section == section then
                    if (row.kind == "folder" or (row.kind == "group" and not row.inFolder)) and row.id ~= sourceFolderId then
                        table.insert(orderItems, { kind = row.kind, id = row.id })
                    end
                end
            end

            local insertPos = #orderItems + 1
            for idx, item in ipairs(orderItems) do
                local targetKind = targetRow.kind
                local targetId = targetRow.id
                -- If target is a group inside a folder, use the folder as anchor
                if targetRow.inFolder then
                    targetKind = "folder"
                    targetId = targetRow.inFolder
                end
                if item.kind == targetKind and item.id == targetId then
                    insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                    break
                end
            end
            table.insert(orderItems, insertPos, { kind = "folder", id = sourceFolderId })
            for i, item in ipairs(orderItems) do
                if item.kind == "folder" then
                    db.folders[item.id].order = i
                else
                    db.groups[item.id].order = i
                end
            end
        end
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
    ResetDragIndicatorStyle()
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
    ResetDragIndicatorStyle()
    if state.kind == "group" and state.groupIds then
        -- Legacy flat reorder (column 2 button drags still use this path)
        PerformGroupReorder(state.sourceIndex, state.dropIndex or state.sourceIndex, state.groupIds)
        CooldownCompanion:RefreshConfigPanel()
    elseif state.kind == "group" or state.kind == "folder" or state.kind == "folder-group" then
        -- Column 1 folder-aware drop
        ApplyCol1Drop(state)
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
            if dragState.col1RenderedRows then
                -- Column 1 folder-aware drop detection
                local dropTarget = GetCol1DropTarget(cursorY, dragState.col1RenderedRows, dragState.kind)
                dragState.dropTarget = dropTarget
                if dropTarget then
                    ResetDragIndicatorStyle()
                    if dropTarget.action == "into-folder" then
                        ShowFolderDropOverlay(dropTarget.anchorFrame, dragState.scrollWidget)
                    elseif dropTarget.action == "reorder-before" then
                        ShowDragIndicator(dropTarget.anchorFrame, true, dragState.scrollWidget)
                    else
                        ShowDragIndicator(dropTarget.anchorFrame, false, dragState.scrollWidget)
                    end
                else
                    HideDragIndicator()
                end
            else
                local dropIndex, anchorFrame, anchorAbove = GetDropIndex(
                    dragState.scrollWidget, cursorY,
                    dragState.childOffset or 0,
                    dragState.totalDraggable
                )
                dragState.dropIndex = dropIndex
                ShowDragIndicator(anchorFrame, anchorAbove, dragState.scrollWidget)
            end
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

    -- Ensure folders table exists
    if not db.folders then db.folders = {} end

    -- Count current children in scroll widget
    local function CountScrollChildren()
        local children = { col1Scroll.content:GetChildren() }
        return #children
    end

    -- Track all rendered rows for drag system: sequential index -> metadata
    local col1RenderedRows = {}

    -- Build top-level items for a section (folders + loose groups), sorted by order
    local function BuildSectionItems(section, sectionGroupIds)
        -- Collect folders for this section
        local sectionFolderIds = {}
        for fid, folder in pairs(db.folders) do
            if folder.section == section then
                table.insert(sectionFolderIds, fid)
            end
        end

        -- Determine which groups are in valid folders for this section
        local validFolderIds = {}
        for _, fid in ipairs(sectionFolderIds) do
            validFolderIds[fid] = true
        end

        -- Split groups: those in a valid folder vs loose
        local looseGroupIds = {}
        local folderChildGroups = {}  -- [folderId] = { groupId, ... }
        for _, gid in ipairs(sectionGroupIds) do
            local group = db.groups[gid]
            if group.folderId and validFolderIds[group.folderId] then
                if not folderChildGroups[group.folderId] then
                    folderChildGroups[group.folderId] = {}
                end
                table.insert(folderChildGroups[group.folderId], gid)
            else
                table.insert(looseGroupIds, gid)
            end
        end

        -- Sort folder children by group order
        for fid, children in pairs(folderChildGroups) do
            table.sort(children, function(a, b)
                local orderA = db.groups[a].order or a
                local orderB = db.groups[b].order or b
                return orderA < orderB
            end)
        end

        -- Build top-level items list: folders + loose groups
        local items = {}
        for _, fid in ipairs(sectionFolderIds) do
            table.insert(items, { kind = "folder", id = fid, order = db.folders[fid].order or fid })
        end
        for _, gid in ipairs(looseGroupIds) do
            table.insert(items, { kind = "group", id = gid, order = db.groups[gid].order or gid })
        end
        table.sort(items, function(a, b) return a.order < b.order end)

        return items, folderChildGroups
    end

    -- Helper: render a single group row (reused by both sections)
    local function RenderGroupRow(groupId, inFolder, sectionTag)
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
        -- Indent prefix for groups inside folders
        local indentPrefix = inFolder and "    " or ""
        local label = indentPrefix .. globalTag .. specTag .. group.name
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
            local function AdjustButtonHeight()
                local scrollWidth = col1Scroll.content:GetWidth()
                if scrollWidth and scrollWidth > 20 then
                    local padding = 20
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
                UIDropDownMenu_Initialize(groupContextMenu, function(self, level, menuList)
                    level = level or 1
                    if level == 1 then
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
                                    local specId = C_SpecializationInfo.GetSpecializationInfo(i)
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

                        -- Move to Folder submenu
                        local groupSection = group.isGlobal and "global" or "char"
                        local hasFolders = false
                        for fid, folder in pairs(db.folders) do
                            if folder.section == groupSection then
                                hasFolders = true
                                break
                            end
                        end
                        if hasFolders or group.folderId then
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Move to Folder"
                            info.notCheckable = true
                            info.hasArrow = true
                            info.menuList = "MOVE_TO_FOLDER"
                            UIDropDownMenu_AddButton(info, level)
                        end

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
                            local wasBars = group.displayMode == "bars"
                            group.displayMode = wasBars and "icons" or "bars"
                            if not wasBars then
                                group.style.orientation = "vertical"
                            end
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
                    elseif menuList == "MOVE_TO_FOLDER" then
                        -- "(No Folder)" option
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = "(No Folder)"
                        info.checked = (group.folderId == nil)
                        info.func = function()
                            CloseDropDownMenus()
                            CooldownCompanion:MoveGroupToFolder(groupId, nil)
                            CooldownCompanion:RefreshConfigPanel()
                        end
                        UIDropDownMenu_AddButton(info, level)

                        -- List all folders in this group's section
                        local groupSection = group.isGlobal and "global" or "char"
                        local folderList = {}
                        for fid, folder in pairs(db.folders) do
                            if folder.section == groupSection then
                                table.insert(folderList, { id = fid, name = folder.name, order = folder.order or fid })
                            end
                        end
                        table.sort(folderList, function(a, b) return a.order < b.order end)
                        for _, f in ipairs(folderList) do
                            info = UIDropDownMenu_CreateInfo()
                            info.text = f.name
                            info.checked = (group.folderId == f.id)
                            info.func = function()
                                CloseDropDownMenus()
                                CooldownCompanion:MoveGroupToFolder(groupId, f.id)
                                CooldownCompanion:RefreshConfigPanel()
                            end
                            UIDropDownMenu_AddButton(info, level)
                        end
                    end
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

        -- Tag the row frame with metadata for drag system
        row.frame._cdcItemKind = "group"
        row.frame._cdcGroupId = groupId
        row.frame._cdcInFolder = inFolder and group.folderId or nil
        row.frame._cdcSection = sectionTag

        -- Track in rendered rows list
        local rowIndex = #col1RenderedRows + 1
        col1RenderedRows[rowIndex] = {
            kind = "group",
            id = groupId,
            widget = row,
            inFolder = inFolder and group.folderId or nil,
            section = sectionTag,
        }

        -- Inline spec filter panel (expanded via Shift+Left-click)
        if specExpandedGroupId == groupId then
            local numSpecs = GetNumSpecializations()
            for i = 1, numSpecs do
                local specId, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
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

            local playerSpecIds = {}
            for i = 1, numSpecs do
                local specId = C_SpecializationInfo.GetSpecializationInfo(i)
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
                    kind = inFolder and "folder-group" or "group",
                    phase = "pending",
                    sourceGroupId = groupId,
                    sourceSection = sectionTag,
                    sourceFolderId = inFolder and group.folderId or nil,
                    scrollWidget = col1Scroll,
                    widget = row,
                    startY = cursorY,
                    col1RenderedRows = col1RenderedRows,
                }
                StartDragTracking()
            end
        end
    end

    -- Helper: render a folder header row
    local function RenderFolderRow(folderId, sectionTag)
        local folder = db.folders[folderId]
        if not folder then return end

        local isCollapsed = collapsedFolders[folderId]
        local arrow = isCollapsed and "> " or "v "
        local folderLabel = "|cffffd100" .. arrow .. folder.name .. "|r"

        local btn = AceGUI:Create("Button")
        btn:SetText(folderLabel)
        btn:SetFullWidth(true)

        btn.frame:RegisterForClicks("AnyUp")
        btn:SetCallback("OnClick", function(widget, event, mouseButton)
            if dragState and dragState.phase == "active" then return end
            if mouseButton == "LeftButton" then
                collapsedFolders[folderId] = not collapsedFolders[folderId]
                CooldownCompanion:RefreshConfigPanel()
            elseif mouseButton == "RightButton" then
                if not folderContextMenu then
                    folderContextMenu = CreateFrame("Frame", "CDCFolderContextMenu", UIParent, "UIDropDownMenuTemplate")
                end
                UIDropDownMenu_Initialize(folderContextMenu, function(self, level)
                    -- Rename
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = "Rename"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        ShowPopupAboveConfig("CDC_RENAME_FOLDER", folder.name, { folderId = folderId })
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Toggle Global/Character
                    info = UIDropDownMenu_CreateInfo()
                    info.text = folder.section == "global" and "Make Character Folder" or "Make Global Folder"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        CooldownCompanion:ToggleFolderGlobal(folderId)
                        CooldownCompanion:RefreshConfigPanel()
                    end
                    UIDropDownMenu_AddButton(info, level)

                    -- Delete
                    info = UIDropDownMenu_CreateInfo()
                    info.text = "|cffff4444Delete Folder|r"
                    info.notCheckable = true
                    info.func = function()
                        CloseDropDownMenus()
                        ShowPopupAboveConfig("CDC_DELETE_FOLDER", folder.name, { folderId = folderId })
                    end
                    UIDropDownMenu_AddButton(info, level)
                end, "MENU")
                folderContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                ToggleDropDownMenu(1, nil, folderContextMenu, "cursor", 0, 0)
            end
        end)

        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        row:AddChild(btn)
        col1Scroll:AddChild(row)

        -- Tag the row frame with metadata for drag system
        row.frame._cdcItemKind = "folder"
        row.frame._cdcFolderId = folderId
        row.frame._cdcSection = sectionTag

        -- Track in rendered rows list
        local rowIndex = #col1RenderedRows + 1
        col1RenderedRows[rowIndex] = {
            kind = "folder",
            id = folderId,
            widget = row,
            section = sectionTag,
        }

        -- Drag support for folder header
        local btnFrame = btn.frame
        if not btnFrame._cdcDragHooked then
            btnFrame._cdcDragHooked = true
            btnFrame:HookScript("OnMouseDown", function(self, mouseBtn)
                if self._cdcOnMouseDown then self._cdcOnMouseDown(self, mouseBtn) end
            end)
        end
        btnFrame._cdcOnMouseDown = function(self, button)
            if button == "LeftButton" then
                local cursorY = GetScaledCursorPosition(col1Scroll)
                dragState = {
                    kind = "folder",
                    phase = "pending",
                    sourceFolderId = folderId,
                    sourceSection = sectionTag,
                    scrollWidget = col1Scroll,
                    widget = row,
                    startY = cursorY,
                    col1RenderedRows = col1RenderedRows,
                }
                StartDragTracking()
            end
        end
    end

    -- Render a section (global or character)
    local function RenderSection(section, sectionGroupIds, headingText)
        local items, folderChildGroups = BuildSectionItems(section, sectionGroupIds)
        if #items == 0 and not next(folderChildGroups) then return end

        local heading = AceGUI:Create("Heading")
        heading:SetText(headingText)
        heading:SetFullWidth(true)
        col1Scroll:AddChild(heading)

        for _, item in ipairs(items) do
            if item.kind == "folder" then
                RenderFolderRow(item.id, section)
                -- If expanded, render children
                if not collapsedFolders[item.id] then
                    local children = folderChildGroups[item.id]
                    if children then
                        for _, gid in ipairs(children) do
                            RenderGroupRow(gid, true, section)
                        end
                    end
                end
            else
                RenderGroupRow(item.id, false, section)
            end
        end
    end

    -- Split groups into global and character-owned
    local globalIds = {}
    local charIds = {}
    for id, group in pairs(db.groups) do
        if group.isGlobal then
            table.insert(globalIds, id)
        elseif group.createdBy == charKey then
            table.insert(charIds, id)
        end
    end

    -- Render sections
    if #globalIds > 0 or next(db.folders) then
        -- Check if there are any global folders
        local hasGlobalContent = #globalIds > 0
        if not hasGlobalContent then
            for _, folder in pairs(db.folders) do
                if folder.section == "global" then
                    hasGlobalContent = true
                    break
                end
            end
        end
        if hasGlobalContent then
            RenderSection("global", globalIds, "|cff66aaff" .. "Global Groups" .. "|r")
        end
    end

    local charName = charKey:match("^(.-)%s*%-") or charKey
    -- Always show character section (even if empty, folders might exist)
    local hasCharContent = #charIds > 0
    if not hasCharContent then
        for _, folder in pairs(db.folders) do
            if folder.section == "char" then
                hasCharContent = true
                break
            end
        end
    end
    if hasCharContent then
        RenderSection("char", charIds, charName .. "'s Groups")
    end

    -- Refresh the static button bar at the bottom
    if col1ButtonBar then
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

        -- Helper: generate a unique folder name
        local function GenerateFolderName(base)
            local db = CooldownCompanion.db.profile
            local existing = {}
            for _, f in pairs(db.folders) do
                existing[f.name] = true
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

        -- Top row: "New Icon Group" (left) | "New Bar Group" (right)
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
        newIconBtn.frame:SetPoint("RIGHT", col1ButtonBar, "CENTER", -2, 0)
        newIconBtn.frame:SetHeight(28)
        newIconBtn.frame:Show()
        table.insert(col1BarWidgets, newIconBtn)

        local newBarBtn = AceGUI:Create("Button")
        newBarBtn:SetText("New Bar Group")
        newBarBtn:SetCallback("OnClick", function()
            local groupId = CooldownCompanion:CreateGroup(GenerateGroupName("New Group"))
            local group = CooldownCompanion.db.profile.groups[groupId]
            group.displayMode = "bars"
            group.style.orientation = "vertical"
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
        newBarBtn.frame:SetPoint("TOPRIGHT", col1ButtonBar, "TOPRIGHT", 0, 0)
        newBarBtn.frame:SetHeight(28)
        newBarBtn.frame:Show()
        table.insert(col1BarWidgets, newBarBtn)

        -- Bottom row: "New Folder" (full width)
        local newFolderBtn = AceGUI:Create("Button")
        newFolderBtn:SetText("New Folder")
        newFolderBtn:SetCallback("OnClick", function()
            local folderId = CooldownCompanion:CreateFolder(GenerateFolderName("New Folder"), "char")
            CooldownCompanion:RefreshConfigPanel()
        end)
        newFolderBtn.frame:SetParent(col1ButtonBar)
        newFolderBtn.frame:ClearAllPoints()
        newFolderBtn.frame:SetPoint("BOTTOMLEFT", col1ButtonBar, "BOTTOMLEFT", 0, 0)
        newFolderBtn.frame:SetPoint("BOTTOMRIGHT", col1ButtonBar, "BOTTOMRIGHT", 0, 0)
        newFolderBtn.frame:SetHeight(28)
        newFolderBtn.frame:Show()
        table.insert(col1BarWidgets, newFolderBtn)
    end
end

------------------------------------------------------------------------
-- COLUMN 2: Spells / Items
------------------------------------------------------------------------
function RefreshColumn2()
    if not col2Scroll then return end
    CancelDrag()
    HideAutocomplete()
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
    if inputBox.editbox.Instructions then inputBox.editbox.Instructions:Hide() end
    inputBox:SetLabel("")
    inputBox:SetText(newInput)
    inputBox:DisableButton(true)
    inputBox:SetFullWidth(true)
    inputBox:SetCallback("OnEnterPressed", function(widget, event, text)
        -- If arrow-key selection was confirmed via Enter, the hook already handled it
        if autocompleteDropdown and autocompleteDropdown._enterConsumed then
            autocompleteDropdown._enterConsumed = nil
            return
        end
        HideAutocomplete()
        newInput = text
        if newInput ~= "" and selectedGroup then
            if TryAdd(newInput) then
                newInput = ""
                CooldownCompanion:RefreshConfigPanel()
            end
        end
    end)
    inputBox:SetCallback("OnTextChanged", function(widget, event, text)
        newInput = text
        if text and #text >= 1 then
            local results = SearchAutocomplete(text)
            ShowAutocompleteResults(results, widget)
            if autocompleteDropdown then
                autocompleteDropdown._editbox = widget.editbox
            end
        else
            HideAutocomplete()
        end
    end)
    inputBox.editbox:SetPoint("BOTTOMRIGHT", 1, 0)
    -- Arrow key / Enter navigation for autocomplete dropdown.
    -- HookScript is necessary because AceGUI has no OnKeyDown callback.
    -- Guarded: only acts when the autocomplete dropdown is visible; no-op otherwise.
    local editboxFrame = inputBox.editbox
    if not editboxFrame._cdcAutocompHooked then
        editboxFrame._cdcAutocompHooked = true
        editboxFrame:HookScript("OnKeyDown", function(self, key)
            if not autocompleteDropdown or not autocompleteDropdown:IsShown() then return end
            local maxIdx = autocompleteDropdown._numResults or 0
            if maxIdx == 0 then return end
            if key == "DOWN" then
                local idx = (autocompleteDropdown._highlightIndex or 0) + 1
                if idx > maxIdx then idx = 1 end
                autocompleteDropdown._highlightIndex = idx
                UpdateAutocompleteHighlight()
            elseif key == "UP" then
                local idx = (autocompleteDropdown._highlightIndex or 0) - 1
                if idx < 1 then idx = maxIdx end
                autocompleteDropdown._highlightIndex = idx
                UpdateAutocompleteHighlight()
            elseif key == "ENTER" then
                local idx = autocompleteDropdown._highlightIndex or 0
                if idx > 0 and autocompleteDropdown.rows[idx] and autocompleteDropdown.rows[idx].entry then
                    autocompleteDropdown._enterConsumed = true
                    OnAutocompleteSelect(autocompleteDropdown.rows[idx].entry)
                end
            end
        end)
    end
    col2Scroll:AddChild(inputBox)

    if pendingEditBoxFocus then
        pendingEditBoxFocus = false
        C_Timer.After(0, function()
            if inputBox.editbox then
                inputBox:SetFocus()
            end
        end)
    end

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
        -- Show current spell name via viewer child's overrideSpellID (tracks current form)
        local entryName = buttonData.name
        if buttonData.type == "spell" then
            local child = CooldownCompanion.viewerAuraFrames[buttonData.id]
            if child and child.cooldownInfo and child.cooldownInfo.overrideSpellID then
                local spellName = C_Spell.GetSpellName(child.cooldownInfo.overrideSpellID)
                if spellName then entryName = spellName end
            else
                local spellName = C_Spell.GetSpellName(buttonData.id)
                if spellName then entryName = spellName end
            end
        end
        entry:SetText(entryName or ("Unknown " .. buttonData.type))
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
-- BUTTON SETTINGS BUILDERS (moved to ConfigSettings.lua)
-- Builder functions are accessed via ST._Build* / ST._Refresh*
------------------------------------------------------------------------

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
            col3Scroll = scroll

            SyncConfigState()
            if tab == "appearance" then
                ST._BuildAppearanceTab(scroll)
            elseif tab == "positioning" then
                ST._BuildPositioningTab(scroll)
            elseif tab == "extras" then
                ST._BuildExtrasTab(scroll)
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
    frame:SetWidth(1160)
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
        CooldownCompanion:ClearAllPandemicPreviews()
        CloseDropDownMenus()
        HideAutocomplete()
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
    local savedFrameRight, savedFrameTop
    local savedOffsetRight, savedOffsetTop

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
                for _, btn in ipairs(CS.tabInfoButtons) do
                    if val then btn:Hide() else btn:Show() end
                end
                for _, btn in ipairs(CS.buttonSettingsInfoButtons) do
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
    local miniWasDragged = false
    miniFrame:SetScript("OnDragStart", miniFrame.StartMoving)
    miniFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        miniWasDragged = true
    end)
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
            local expandRight, expandTop
            if miniWasDragged then
                -- User dragged mini frame — apply saved offset to new mini frame position
                expandRight = miniFrame:GetLeft() + savedOffsetRight
                expandTop = miniFrame:GetTop() + savedOffsetTop
            else
                -- No drag — restore exact saved position
                expandRight = savedFrameRight
                expandTop = savedFrameTop
            end
            miniFrame:Hide() -- OnHide resets state and reparents collapse button
            miniWasDragged = false

            content:ClearAllPoints()
            content:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", expandRight, expandTop)
            content:SetHeight(fullHeight)
            content:SetWidth(1150)
            content:Show()
            CooldownCompanion:RefreshConfigPanel()
        else
            -- Collapse: save main frame position, then show mini frame at collapse button position
            CloseDropDownMenus()

            savedFrameRight = content:GetRight()
            savedFrameTop = content:GetTop()

            local btnLeft = collapseBtn.frame:GetLeft()
            local btnBottom = collapseBtn.frame:GetBottom()

            isCollapsing = true
            content:Hide()
            isCollapsing = false

            ApplyMiniFrameBackdrop()
            miniFrame:ClearAllPoints()
            miniFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", btnLeft - 18, btnBottom - 17)
            miniFrame:Show()

            -- Save offset between main frame TOPRIGHT and mini frame position (for drag expand)
            savedOffsetRight = savedFrameRight - miniFrame:GetLeft()
            savedOffsetTop = savedFrameTop - miniFrame:GetTop()

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

    -- Static button bar at bottom of column 1 (New Icon/Bar Group + New Folder)
    local btnBar = CreateFrame("Frame", nil, col1.content)
    btnBar:SetPoint("BOTTOMLEFT", col1.content, "BOTTOMLEFT", 0, 0)
    btnBar:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 0)
    btnBar:SetHeight(56)
    col1ButtonBar = btnBar

    -- AceGUI ScrollFrames in columns 1 and 2
    local scroll1 = AceGUI:Create("ScrollFrame")
    scroll1:SetLayout("List")
    scroll1.frame:SetParent(col1.content)
    scroll1.frame:ClearAllPoints()
    scroll1.frame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, 0)
    scroll1.frame:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 56)
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
    CS.buttonSettingsScroll = bsScroll

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
    CS.col3Container = col3Container

    -- Layout columns on size change
    local function LayoutColumns()
        local w = colParent:GetWidth()
        local h = colParent:GetHeight()
        local pad = COLUMN_PADDING

        local baseW = w - 10
        local col1Width = math.floor(baseW * 0.18)
        local col2Width = math.floor(baseW * 0.25)
        local bsWidth   = math.floor(baseW * 0.28)
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

    -- Autocomplete cache invalidation
    local autocompleteCacheFrame = CreateFrame("Frame")
    autocompleteCacheFrame:RegisterEvent("SPELLS_CHANGED")
    autocompleteCacheFrame:RegisterEvent("BAG_UPDATE")
    autocompleteCacheFrame:SetScript("OnEvent", function()
        autocompleteCache = nil
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
    CS.configFrame = frame
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
    SyncConfigState()
    ST._RefreshButtonSettingsColumn()
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
        wipe(collapsedFolders)
        if configFrame and configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
    self.db.RegisterCallback(self, "OnProfileCopied", function()
        selectedGroup = nil
        selectedButton = nil
        wipe(selectedButtons)
        wipe(collapsedFolders)
        if configFrame and configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
    self.db.RegisterCallback(self, "OnProfileReset", function()
        selectedGroup = nil
        selectedButton = nil
        wipe(selectedButtons)
        wipe(collapsedFolders)
        if configFrame and configFrame.frame:IsShown() then
            self:RefreshConfigPanel()
        end
        self:RefreshAllGroups()
    end)
end