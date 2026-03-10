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
------------------------------------------------------------------------
local COLOR_LITERAL   = "ffbbbbbb"  -- dim gray
local COLOR_TOKEN     = "ff00ff00"  -- green
local COLOR_UNKNOWN   = "ffff4444"  -- red
local COLOR_COND      = "ffffff00"  -- yellow

local function BuildSyntaxString(segments)
    local parts = {}
    for _, seg in ipairs(segments) do
        if seg.type == "literal" then
            parts[#parts + 1] = "|c" .. COLOR_LITERAL .. seg.value .. "|r"
        elseif seg.type == "token" then
            local color = seg.unknown and COLOR_UNKNOWN or COLOR_TOKEN
            parts[#parts + 1] = "|c" .. color .. "{" .. seg.value .. "}|r"
        elseif seg.type == "cond_start" then
            local prefix = seg.negated and "!" or "?"
            parts[#parts + 1] = "|c" .. COLOR_COND .. "{" .. prefix .. seg.value .. "}|r"
        elseif seg.type == "cond_end" then
            parts[#parts + 1] = "|c" .. COLOR_COND .. "{/" .. seg.value .. "}|r"
        end
    end
    return table.concat(parts)
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
    -- EDIT BOX (MultiLineEditBox)
    -- ================================================================
    local editGroup = AceGUI:Create("MultiLineEditBox")
    editGroup:SetLabel("Format String")
    editGroup:SetFullWidth(true)
    editGroup:SetNumLines(3)
    editGroup.button:Hide()  -- hide "Accept" button, we save on change
    window:AddChild(editGroup)
    editGroup:SetText(style.textFormat or "{name}  {status}")

    -- ================================================================
    -- SYNTAX DISPLAY (inline, directly below edit box)
    -- ================================================================
    local syntaxLabel = AceGUI:Create("Label")
    syntaxLabel:SetFullWidth(true)
    syntaxLabel:SetFontObject(GameFontHighlight)
    window:AddChild(syntaxLabel)

    -- ================================================================
    -- TOKEN INSERT BUTTONS
    -- ================================================================
    local tokenHeading = AceGUI:Create("Heading")
    tokenHeading:SetText("Insert Token")
    tokenHeading:SetFullWidth(true)
    window:AddChild(tokenHeading)

    local tokenGroup = AceGUI:Create("SimpleGroup")
    tokenGroup:SetFullWidth(true)
    tokenGroup:SetLayout("Flow")
    window:AddChild(tokenGroup)

    for _, tokenName in ipairs(TOKEN_LIST) do
        local btn = AceGUI:Create("Button")
        btn:SetText("{" .. tokenName .. "}")
        btn:SetAutoWidth(true)
        btn:SetCallback("OnClick", function()
            local eb = editGroup.editBox
            local text = eb:GetText() or ""
            local cursor = eb:GetCursorPosition()
            local insert = "{" .. tokenName .. "}"
            local newText = text:sub(1, cursor) .. insert .. text:sub(cursor + 1)
            eb:SetText(newText)
            eb:SetCursorPosition(cursor + #insert)
            eb:SetFocus()
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
        local eb = editGroup.editBox
        local text = eb:GetText() or ""
        local cursor = eb:GetCursorPosition()
        local open = "{" .. prefix .. token .. "}"
        local close = "{/" .. token .. "}"
        local newText = text:sub(1, cursor) .. open .. close .. text:sub(cursor + 1)
        eb:SetText(newText)
        eb:SetCursorPosition(cursor + #open)
        eb:SetFocus()
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
    -- PREVIEW SECTION
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
    -- SAVE BUTTON
    -- ================================================================
    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save & Close")
    saveBtn:SetFullWidth(true)
    saveBtn:SetCallback("OnClick", function()
        local text = editGroup:GetText()
        if text and text ~= "" then
            style.textFormat = text
            CooldownCompanion:RefreshGroupFrame(groupId)
            CooldownCompanion:RefreshConfigPanel()
        end
        window:Hide()
    end)
    window:AddChild(saveBtn)

    -- ================================================================
    -- UPDATE FUNCTION (refreshes syntax + preview on every keystroke)
    -- ================================================================
    local currentStyle = style
    local currentGroupId = groupId

    local function UpdateDisplay()
        local text = editGroup:GetText() or ""
        local segments = ParseFormatString(text)

        -- Syntax coloring
        syntaxLabel:SetText(BuildSyntaxString(segments))

        -- Preview rows
        local mockStates = BuildMockStates(currentStyle)
        for i, mock in ipairs(mockStates) do
            local preview = PreviewSubstitute(segments, currentStyle, mock.state)
            previewLabels[i]:SetText(mock.label .. "  " .. preview)
        end
    end

    -- Wire up live updates on text change
    editGroup:SetCallback("OnTextChanged", function(widget, event, text)
        UpdateDisplay()
    end)

    -- Also save on Enter (Ctrl+Enter in multiline)
    editGroup:SetCallback("OnEnterPressed", function(widget, event, text)
        if text and text ~= "" then
            currentStyle.textFormat = text
            CooldownCompanion:RefreshGroupFrame(currentGroupId)
        end
    end)

    -- Refresh function for re-opening with different style/group
    window._refresh = function(newStyle, newGroupId)
        currentStyle = newStyle
        currentGroupId = newGroupId
        editGroup:SetText(newStyle.textFormat or "{name}  {status}")
        UpdateDisplay()
    end

    -- Initial display
    UpdateDisplay()

    -- ================================================================
    -- LIFECYCLE
    -- ================================================================
    window:SetCallback("OnClose", function(widget)
        -- Auto-save on close
        local text = editGroup:GetText()
        if text and text ~= "" and text ~= (currentStyle.textFormat or "{name}  {status}") then
            currentStyle.textFormat = text
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
