--[[
    CooldownCompanion - ConfigSettings/FormatEditor.lua
    Popout window for editing text-mode format strings with syntax highlighting and live preview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local ParseFormatString = ST._ParseFormatString
local CreateInfoButton = ST._CreateInfoButton

-- Module-level reference for lifecycle management
local formatEditorFrame = nil

-- Token list for insert buttons
local TOKEN_LIST = {"name", "time", "charges", "maxcharges", "stacks", "aura", "keybind", "status", "icon"}

-- Token display names for conditional dropdown (reuses TOKEN_LIST order)
local COND_TOKEN_LIST = {}
local COND_TOKEN_ORDER = {}
for _, t in ipairs(TOKEN_LIST) do
    COND_TOKEN_LIST[t] = t
    COND_TOKEN_ORDER[#COND_TOKEN_ORDER + 1] = t
end

------------------------------------------------------------------------
-- SYNTAX COLORING
-- Builds a color-escaped string from parsed segments for display.
-- The output is set directly as EditBox text; WoW renders |c...|r natively.
------------------------------------------------------------------------
local COLOR_LITERAL      = "ffbbbbbb"  -- dim gray
local COLOR_TOKEN        = "ff00ff00"  -- green
local COLOR_UNKNOWN      = "ffff4444"  -- red
local COLOR_COND_PRESENT = "ffffff00"  -- yellow:  {?token} "show if present"
local COLOR_COND_NEGATED = "ffff8844"  -- orange:  {!token} "show if empty"

local function BuildSyntaxString(segments)
    -- Pass 1: pair cond_start with cond_end using a stack
    local stack = {}       -- { {index, value, negated}, ... }
    local openMatched = {} -- openMatched[i] = true if cond_start at index i is paired
    local closeInfo = {}   -- closeInfo[i] = negated (bool) of matched opener, or nil if orphan

    for i, seg in ipairs(segments) do
        if seg.type == "cond_start" then
            stack[#stack + 1] = { index = i, value = seg.value, negated = seg.negated }
        elseif seg.type == "cond_end" then
            -- Find matching opener on stack (same token name, search top-down)
            for j = #stack, 1, -1 do
                if stack[j].value == seg.value then
                    openMatched[stack[j].index] = true
                    closeInfo[i] = stack[j].negated
                    table.remove(stack, j)
                    break
                end
            end
            -- If no match found, closeInfo[i] remains nil (orphan close tag)
        end
    end
    -- Any cond_start remaining on the stack is unmatched

    -- Pass 2: build colorized string using pairing info
    local parts = {}
    for i, seg in ipairs(segments) do
        if seg.type == "literal" then
            parts[#parts + 1] = "|c" .. COLOR_LITERAL .. seg.value .. "|r"
        elseif seg.type == "token" then
            local color = seg.unknown and COLOR_UNKNOWN or COLOR_TOKEN
            parts[#parts + 1] = "|c" .. color .. "{" .. seg.value .. "}|r"
        elseif seg.type == "cond_start" then
            local prefix = seg.negated and "!" or "?"
            local color
            if openMatched[i] then
                color = seg.negated and COLOR_COND_NEGATED or COLOR_COND_PRESENT
            else
                color = COLOR_UNKNOWN  -- red: missing closing bracket
            end
            parts[#parts + 1] = "|c" .. color .. "{" .. prefix .. seg.value .. "}|r"
        elseif seg.type == "cond_end" then
            local color
            if closeInfo[i] ~= nil then
                color = closeInfo[i] and COLOR_COND_NEGATED or COLOR_COND_PRESENT
            else
                color = COLOR_UNKNOWN  -- red: orphan close tag
            end
            parts[#parts + 1] = "|c" .. color .. "{/" .. seg.value .. "}|r"
        end
    end
    return table.concat(parts)
end

------------------------------------------------------------------------
-- FORMAT VALIDATION
-- Analyzes parsed segments for structural errors (unclosed conditionals,
-- orphan close tags, unknown tokens) and returns a list of warning strings.
------------------------------------------------------------------------
local function ValidateFormat(segments)
    local warnings = {}

    -- Unknown tokens
    for _, seg in ipairs(segments) do
        if seg.type == "token" and seg.unknown then
            warnings[#warnings + 1] = "{" .. seg.value .. "} is not a recognized token"
        end
    end

    -- Pair conditionals with a stack (same logic as BuildSyntaxString)
    -- Also track segment index to detect empty conditionals.
    local stack = {}
    for i, seg in ipairs(segments) do
        if seg.type == "cond_start" then
            stack[#stack + 1] = { value = seg.value, negated = seg.negated, index = i }
        elseif seg.type == "cond_end" then
            local found = false
            for j = #stack, 1, -1 do
                if stack[j].value == seg.value then
                    -- Empty conditional: opener immediately followed by its closer
                    if stack[j].index == i - 1 then
                        local prefix = stack[j].negated and "!" or "?"
                        if stack[j].negated then
                            warnings[#warnings + 1] = "Empty {!" .. seg.value .. "}: add text to show when " .. seg.value .. " is empty"
                        else
                            warnings[#warnings + 1] = "Empty {?" .. seg.value .. "}: add text to show when " .. seg.value .. " has a value"
                        end
                    end
                    table.remove(stack, j)
                    found = true
                    break
                end
            end
            if not found then
                warnings[#warnings + 1] = "{/" .. seg.value .. "} has no matching opener"
            end
        end
    end
    for _, entry in ipairs(stack) do
        local prefix = entry.negated and "!" or "?"
        warnings[#warnings + 1] = "{" .. prefix .. entry.value .. "} is never closed"
    end

    return warnings
end

------------------------------------------------------------------------
-- COLOR CODE CURSOR MAPPING
-- Maps cursor positions between raw text and colorized text that has
-- |cXXXXXXXX...|r escape sequences injected by BuildSyntaxString.
------------------------------------------------------------------------
local function StripColorCodes(text)
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

-- Convert byte position in colorized text to raw (uncolored) character count.
-- bytePos is 0-based (from GetCursorPosition): 0 = before first char.
local function ColorizedToRawPos(bytePos, text)
    local raw = 0
    local i = 1
    while i <= bytePos do
        if text:sub(i, i + 1) == "|c" and i + 9 <= #text then
            i = i + 10  -- skip |cXXXXXXXX
        elseif text:sub(i, i + 1) == "|r" then
            i = i + 2   -- skip |r
        else
            i = i + 1
            raw = raw + 1
        end
    end
    return raw
end

-- Convert raw character position to byte position in colorized text.
-- Returns 0-based position suitable for SetCursorPosition.
local function RawToColorizedPos(rawPos, colorizedText)
    if rawPos <= 0 then return 0 end
    local raw = 0
    local i = 1
    while raw < rawPos and i <= #colorizedText do
        if colorizedText:sub(i, i + 1) == "|c" and i + 9 <= #colorizedText then
            i = i + 10
        elseif colorizedText:sub(i, i + 1) == "|r" then
            i = i + 2
        else
            i = i + 1
            raw = raw + 1
        end
    end
    -- i is now 1-based position AFTER the rawPos'th visible char; convert to 0-based
    return i - 1
end

------------------------------------------------------------------------
-- PREVIEW SUBSTITUTION
-- Simplified substitution that uses mock data instead of a real button.
------------------------------------------------------------------------
local function FormatPreviewTime(seconds)
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, math.floor(seconds % 60))
    elseif seconds >= 60 then
        return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
    elseif seconds >= 10 then
        return string.format("%d", math.floor(seconds))
    elseif seconds > 0 then
        return string.format("%.1f", seconds)
    end
    return ""
end

local function WrapPreviewColor(text, color)
    if not text or text == "" then return "" end
    return string.format("|cff%02x%02x%02x%s|r",
        math.floor(color[1] * 255),
        math.floor(color[2] * 255),
        math.floor(color[3] * 255),
        text)
end

local function EvaluateMockPresence(tokenName, mockState)
    if tokenName == "name" then return true
    elseif tokenName == "time" then return mockState.time and mockState.time > 0
    elseif tokenName == "charges" then return mockState.charges ~= nil
    elseif tokenName == "maxcharges" then return mockState.maxCharges and mockState.maxCharges > 1
    elseif tokenName == "stacks" then return mockState.stacks and mockState.stacks > 0
    elseif tokenName == "aura" then return mockState.auraTime and mockState.auraTime > 0
    elseif tokenName == "keybind" then return mockState.keybind and mockState.keybind ~= ""
    elseif tokenName == "status" then return true
    elseif tokenName == "icon" then return mockState.icon ~= nil
    end
    return false
end

local function PreviewSubstitute(segments, style, mockState)
    local parts = {}
    local baseColor = style.textFontColor or {1, 1, 1, 1}
    local cdColor = style.textCooldownColor or {1, 0.3, 0.3, 1}
    local readyColor = style.textReadyColor or {0.2, 1.0, 0.2, 1}
    local auraColor = style.textAuraColor or {0, 0.925, 1, 1}
    local chargeFull = style.chargeFontColor or {1, 1, 1, 1}
    local chargeMissing = style.chargeFontColorMissing or {1, 1, 1, 1}
    local chargeZero = style.chargeFontColorZero or {1, 1, 1, 1}

    local skipDepth = 0
    local auraActive = mockState.auraTime and mockState.auraTime > 0
    local timeVal = mockState.time
    local auraVal = mockState.auraTime

    for _, seg in ipairs(segments) do
        if seg.type == "cond_start" then
            if skipDepth > 0 then
                skipDepth = skipDepth + 1
            else
                local present = EvaluateMockPresence(seg.value, mockState)
                local shouldShow = (seg.negated and not present) or (not seg.negated and present)
                if not shouldShow then
                    skipDepth = 1
                end
            end
        elseif seg.type == "cond_end" then
            if skipDepth > 0 then
                skipDepth = skipDepth - 1
            end
        elseif skipDepth > 0 then
            -- inside false conditional
        elseif seg.type == "literal" then
            parts[#parts + 1] = seg.value
        elseif seg.unknown then
            -- unknown tokens render empty
        else
            local token = seg.value
            if token == "name" then
                parts[#parts + 1] = WrapPreviewColor(mockState.name or "Fireball", baseColor)
            elseif token == "time" then
                if timeVal and timeVal > 0 then
                    parts[#parts + 1] = WrapPreviewColor(FormatPreviewTime(timeVal), cdColor)
                end
            elseif token == "charges" then
                if mockState.charges then
                    local cc
                    if mockState.charges == mockState.maxCharges then cc = chargeFull
                    elseif mockState.charges == 0 then cc = chargeZero
                    else cc = chargeMissing end
                    parts[#parts + 1] = WrapPreviewColor(tostring(mockState.charges), cc)
                end
            elseif token == "maxcharges" then
                if mockState.maxCharges and mockState.maxCharges > 1 then
                    parts[#parts + 1] = WrapPreviewColor(tostring(mockState.maxCharges), baseColor)
                end
            elseif token == "stacks" then
                if mockState.stacks and mockState.stacks > 0 then
                    parts[#parts + 1] = WrapPreviewColor(tostring(mockState.stacks), baseColor)
                end
            elseif token == "aura" then
                if auraVal and auraVal > 0 then
                    parts[#parts + 1] = WrapPreviewColor(FormatPreviewTime(auraVal), auraColor)
                end
            elseif token == "keybind" then
                if mockState.keybind and mockState.keybind ~= "" then
                    parts[#parts + 1] = WrapPreviewColor(mockState.keybind, baseColor)
                end
            elseif token == "status" then
                if auraActive then
                    if auraVal and auraVal > 0 then
                        parts[#parts + 1] = WrapPreviewColor(FormatPreviewTime(auraVal), auraColor)
                    else
                        parts[#parts + 1] = WrapPreviewColor("Active", auraColor)
                    end
                elseif timeVal and timeVal > 0 then
                    parts[#parts + 1] = WrapPreviewColor(FormatPreviewTime(timeVal), cdColor)
                else
                    parts[#parts + 1] = WrapPreviewColor(style.textReadyText or "Ready", readyColor)
                end
            elseif token == "icon" then
                if mockState.icon then
                    parts[#parts + 1] = string.format("|T%s:0|t", tostring(mockState.icon))
                end
            end
        end
    end

    return table.concat(parts)
end

------------------------------------------------------------------------
-- RESOLVE BUTTON NAME
-- Gets the name from the currently selected button in config, or fallback.
------------------------------------------------------------------------
local function GetPreviewName()
    if CS.selectedGroup and CS.selectedButton then
        local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
        if group and group.buttons and group.buttons[CS.selectedButton] then
            local bd = group.buttons[CS.selectedButton]
            local name = bd.customName or bd.name
            if not bd.customName and bd.type == "spell" then
                local spellName = C_Spell.GetSpellName(bd.id)
                if spellName then name = spellName end
            elseif not bd.customName and bd.type == "item" then
                local itemName = C_Item.GetItemNameByID(bd.id)
                if itemName then name = itemName end
            end
            return name or "Fireball"
        end
    end
    return "Fireball"
end

local function GetPreviewIcon()
    if CS.selectedGroup and CS.selectedButton then
        local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
        if group and group.buttons and group.buttons[CS.selectedButton] then
            local bd = group.buttons[CS.selectedButton]
            if bd.type == "spell" then
                local info = C_Spell.GetSpellTexture(bd.id)
                if info then return info end
            elseif bd.type == "item" then
                local tex = C_Item.GetItemIconByID(bd.id)
                if tex then return tex end
            end
        end
    end
    return 135810  -- Fireball icon
end

------------------------------------------------------------------------
-- BUILD MOCK STATES
------------------------------------------------------------------------
local function BuildMockStates(style)
    local name = GetPreviewName()
    local icon = GetPreviewIcon()
    return {
        {
            label = WrapPreviewColor("Ready:", style.textReadyColor or {0.2, 1.0, 0.2, 1}),
            state = { name = name, time = 0, charges = 2, maxCharges = 3, stacks = 0, auraTime = 0, keybind = "F1", icon = icon },
        },
        {
            label = WrapPreviewColor("Cooldown:", style.textCooldownColor or {1, 0.3, 0.3, 1}),
            state = { name = name, time = 83, charges = 1, maxCharges = 3, stacks = 0, auraTime = 0, keybind = "F1", icon = icon },
        },
        {
            label = WrapPreviewColor("Aura:", style.textAuraColor or {0, 0.925, 1, 1}),
            state = { name = name, time = 0, charges = 2, maxCharges = 3, stacks = 3, auraTime = 12.3, keybind = "F1", icon = icon },
        },
    }
end

------------------------------------------------------------------------
-- OPEN FORMAT EDITOR
------------------------------------------------------------------------
local function OpenFormatEditor(style, groupId)
    -- If already open, bring to front and refresh
    if formatEditorFrame then
        formatEditorFrame:Show()
        formatEditorFrame.frame:Raise()
        if formatEditorFrame._refresh then
            formatEditorFrame._refresh(style, groupId)
        end
        return
    end

    local window = AceGUI:Create("Window")
    window:SetTitle("Format String Editor")
    window:SetWidth(400)
    window:SetHeight(520)
    window:SetLayout("List")
    window:EnableResize(false)
    formatEditorFrame = window
    CS.formatEditorFrame = window

    -- Anchor to the right of the config panel
    local configFrame = CS.configFrame
    if configFrame and configFrame.frame and configFrame.frame:IsShown() then
        window.frame:ClearAllPoints()
        window.frame:SetPoint("TOPLEFT", configFrame.frame, "TOPRIGHT", 4, 0)
    end

    -- ================================================================
    -- EDIT BOX (MultiLineEditBox) with inline syntax coloring
    -- ================================================================
    local editGroup = AceGUI:Create("MultiLineEditBox")
    editGroup:SetLabel("Format String")
    editGroup:SetFullWidth(true)
    editGroup:SetNumLines(3)
    editGroup.button:Hide()  -- hide "Accept" button, we save on change
    window:AddChild(editGroup)

    local eb = editGroup.editBox

    -- Track the raw (uncolored) format string separately.
    -- The EditBox text contains |c...|r color codes for native rendering;
    -- currentRawText is the actual format string the user is editing.
    local currentRawText = style.textFormat or "{name}  {status}"

    -- Helper: colorize raw text and set into EditBox, preserving cursor position.
    local function ApplyColorized(rawText, rawCursorPos)
        local colorized = BuildSyntaxString(ParseFormatString(rawText))
        local colorizedCursor = RawToColorizedPos(rawCursorPos, colorized)
        eb:SetText(colorized)
        eb:SetCursorPosition(colorizedCursor)
    end

    -- Set initial colorized text
    ApplyColorized(currentRawText, #currentRawText)

    -- ================================================================
    -- WARNING LABEL (below editbox, shows validation errors)
    -- ================================================================
    local warningLabel = AceGUI:Create("Label")
    warningLabel:SetFullWidth(true)
    warningLabel:SetFontObject(GameFontNormalSmall)
    warningLabel:SetColor(1, 0.4, 0.4)
    warningLabel:SetText("")
    window:AddChild(warningLabel)

    -- ================================================================
    -- PREVIEW SECTION (directly beneath edit box)
    -- ================================================================
    local previewHeading = AceGUI:Create("Heading")
    previewHeading:SetText("Preview")
    previewHeading:SetFullWidth(true)
    window:AddChild(previewHeading)

    local previewLabels = {}
    for i = 1, 3 do
        local row = AceGUI:Create("Label")
        row:SetFullWidth(true)
        row:SetFontObject(GameFontHighlight)
        window:AddChild(row)
        previewLabels[i] = row
    end

    -- ================================================================
    -- UPDATE FUNCTION (refreshes preview from currentRawText)
    -- ================================================================
    local currentStyle = style
    local currentGroupId = groupId

    local function UpdateDisplay()
        local segments = ParseFormatString(currentRawText)
        local mockStates = BuildMockStates(currentStyle)
        for i, mock in ipairs(mockStates) do
            local preview = PreviewSubstitute(segments, currentStyle, mock.state)
            previewLabels[i]:SetText(mock.label .. "  " .. preview)
        end

        local warnings = ValidateFormat(segments)
        if #warnings > 0 then
            warningLabel:SetText(table.concat(warnings, "\n"))
        else
            warningLabel:SetText("")
        end
    end

    -- Initial preview
    UpdateDisplay()

    -- ================================================================
    -- INSERT HELPER (shared by token + conditional buttons)
    -- ================================================================
    local function InsertAtCursor(insertText, cursorOffset)
        cursorOffset = cursorOffset or #insertText
        local colorized = eb:GetText() or ""
        local colorizedCursor = eb:GetCursorPosition()
        local rawCursor = ColorizedToRawPos(colorizedCursor, colorized)

        local newRaw = currentRawText:sub(1, rawCursor) .. insertText .. currentRawText:sub(rawCursor + 1)
        currentRawText = newRaw

        ApplyColorized(newRaw, rawCursor + cursorOffset)
        eb:SetFocus()
        UpdateDisplay()
    end

    -- ================================================================
    -- TOKEN INSERT BUTTONS
    -- ================================================================
    local tokenHeading = AceGUI:Create("Heading")
    tokenHeading:SetText("Insert Token")
    tokenHeading:SetFullWidth(true)
    window:AddChild(tokenHeading)

    local tokenInfo = CreateInfoButton(tokenHeading.frame, tokenHeading.label, "LEFT", "RIGHT", 4, 0, {
        {"Available Tokens", 1, 0.82, 0},
        " ",
        {"|cff99ff99{name}|r  Spell/item display name", 1, 1, 1},
        {"|cff99ff99{time}|r  Cooldown remaining", 1, 1, 1},
        {"|cff99ff99{charges}|r  Current charges", 1, 1, 1},
        {"|cff99ff99{maxcharges}|r  Maximum charges", 1, 1, 1},
        {"|cff99ff99{stacks}|r  Aura stacks / item count", 1, 1, 1},
        {"|cff99ff99{aura}|r  Aura duration remaining", 1, 1, 1},
        {"|cff99ff99{keybind}|r  Keybind text", 1, 1, 1},
        {"|cff99ff99{status}|r  Shows ready, cooldown, or aura automatically", 1, 1, 1},
        {"|cff99ff99{icon}|r  Inline spell icon", 1, 1, 1},
    }, tokenHeading)
    tokenHeading.right:ClearAllPoints()
    tokenHeading.right:SetPoint("RIGHT", tokenHeading.frame, "RIGHT", -3, 0)
    tokenHeading.right:SetPoint("LEFT", tokenInfo, "RIGHT", 4, 0)

    local tokenGroup = AceGUI:Create("SimpleGroup")
    tokenGroup:SetFullWidth(true)
    tokenGroup:SetLayout("Flow")
    window:AddChild(tokenGroup)

    for _, tokenName in ipairs(TOKEN_LIST) do
        local btn = AceGUI:Create("Button")
        btn:SetText("{" .. tokenName .. "}")
        btn:SetAutoWidth(true)
        btn:SetCallback("OnClick", function()
            InsertAtCursor("{" .. tokenName .. "}")
        end)
        tokenGroup:AddChild(btn)
    end

    -- ================================================================
    -- CONDITIONAL INSERT BUTTONS
    -- ================================================================
    local condHeading = AceGUI:Create("Heading")
    condHeading:SetText("Insert Conditional")
    condHeading:SetFullWidth(true)
    window:AddChild(condHeading)

    local condInfo = CreateInfoButton(condHeading.frame, condHeading.label, "LEFT", "RIGHT", 4, 0, {
        {"Conditional Sections", 1, 0.82, 0, true},
        " ",
        {"Conditionals let you show or hide parts of the", 1, 1, 1, true},
        {"format string based on whether a value exists.", 1, 1, 1, true},
        " ",
        {"{?token}...{/token}", 0.6, 1, 0.6, true},
        {"  Show the ... text only when the token has a value.", 1, 1, 1, true},
        {"  Example: {?time}CD: {time}{/time}", 0.7, 0.7, 0.7, true},
        {"  Shows 'CD: 1:23' on cooldown, nothing when ready.", 0.7, 0.7, 0.7, true},
        " ",
        {"{!token}...{/token}", 0.6, 1, 0.6, true},
        {"  Show the ... text only when the token is empty.", 1, 1, 1, true},
        {"  Example: {!time}Ready!{/time}", 0.7, 0.7, 0.7, true},
        {"  Shows 'Ready!' only when not on cooldown.", 0.7, 0.7, 0.7, true},
    }, condHeading)
    condHeading.right:ClearAllPoints()
    condHeading.right:SetPoint("RIGHT", condHeading.frame, "RIGHT", -3, 0)
    condHeading.right:SetPoint("LEFT", condInfo, "RIGHT", 4, 0)

    local condGroup = AceGUI:Create("SimpleGroup")
    condGroup:SetFullWidth(true)
    condGroup:SetLayout("Flow")
    window:AddChild(condGroup)

    local condDropdown = AceGUI:Create("Dropdown")
    condDropdown:SetLabel("")
    condDropdown:SetWidth(150)
    condDropdown:SetList(COND_TOKEN_LIST, COND_TOKEN_ORDER)
    condDropdown:SetValue("time")
    condGroup:AddChild(condDropdown)

    local function InsertConditional(prefix)
        local token = condDropdown:GetValue()
        local open = "{" .. prefix .. token .. "}"
        local close = "{/" .. token .. "}"
        InsertAtCursor(open .. close, #open)
    end

    local showBtn = AceGUI:Create("Button")
    showBtn:SetText("Show if present")
    showBtn:SetAutoWidth(true)
    showBtn:SetCallback("OnClick", function() InsertConditional("?") end)
    condGroup:AddChild(showBtn)

    local hideBtn = AceGUI:Create("Button")
    hideBtn:SetText("Show if empty")
    hideBtn:SetAutoWidth(true)
    hideBtn:SetCallback("OnClick", function() InsertConditional("!") end)
    condGroup:AddChild(hideBtn)

    -- ================================================================
    -- SAVE BUTTON
    -- ================================================================
    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save & Close")
    saveBtn:SetFullWidth(true)
    saveBtn:SetCallback("OnClick", function()
        if currentRawText and currentRawText ~= "" then
            style.textFormat = currentRawText
            CooldownCompanion:RefreshGroupFrame(groupId)
            CooldownCompanion:RefreshConfigPanel()
        end
        window:Hide()
    end)
    window:AddChild(saveBtn)

    -- ================================================================
    -- LIVE EDIT CALLBACKS
    -- ================================================================

    -- OnTextChanged fires only on user input (AceGUI checks userInput flag).
    -- Strip color codes from edited text, re-colorize, and restore cursor.
    editGroup:SetCallback("OnTextChanged", function(widget, event, text)
        local newRaw = StripColorCodes(text)
        if newRaw == currentRawText then return end

        local colorizedCursor = eb:GetCursorPosition()
        local rawCursor = ColorizedToRawPos(colorizedCursor, text)
        currentRawText = newRaw

        ApplyColorized(newRaw, rawCursor)
        UpdateDisplay()
    end)

    -- Save on Enter (Ctrl+Enter in multiline)
    editGroup:SetCallback("OnEnterPressed", function(widget, event, text)
        if currentRawText and currentRawText ~= "" then
            currentStyle.textFormat = currentRawText
            CooldownCompanion:RefreshGroupFrame(currentGroupId)
        end
    end)

    -- Refresh function for re-opening with different style/group
    window._refresh = function(newStyle, newGroupId)
        currentStyle = newStyle
        currentGroupId = newGroupId
        currentRawText = newStyle.textFormat or "{name}  {status}"
        ApplyColorized(currentRawText, #currentRawText)
        UpdateDisplay()
    end

    -- ================================================================
    -- LIFECYCLE
    -- ================================================================
    window:SetCallback("OnClose", function(widget)
        -- Auto-save on close
        if currentRawText and currentRawText ~= "" and currentRawText ~= (currentStyle.textFormat or "{name}  {status}") then
            currentStyle.textFormat = currentRawText
            CooldownCompanion:RefreshGroupFrame(currentGroupId)
            CooldownCompanion:RefreshConfigPanel()
        end
        AceGUI:Release(widget)
        formatEditorFrame = nil
        CS.formatEditorFrame = nil
    end)

    -- Close when config panel hides (hook only once per config frame instance)
    if configFrame and configFrame.frame and not configFrame.frame._formatEditorHooked then
        configFrame.frame._formatEditorHooked = true
        configFrame.frame:HookScript("OnHide", function()
            if formatEditorFrame then
                formatEditorFrame:Hide()
            end
        end)
    end

end

------------------------------------------------------------------------
-- CLOSE FORMAT EDITOR (utility for external callers)
------------------------------------------------------------------------
local function CloseFormatEditor()
    if formatEditorFrame then
        formatEditorFrame:Hide()
    end
end

------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
ST._OpenFormatEditor = OpenFormatEditor
ST._CloseFormatEditor = CloseFormatEditor
