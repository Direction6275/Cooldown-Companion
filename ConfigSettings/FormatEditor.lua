--[[
    CooldownCompanion - ConfigSettings/FormatEditor.lua
    Popout window for editing text-mode format strings with syntax highlighting and live preview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local ParseFormatString = ST._ParseFormatString
local HasAnyEffects = ST._HasAnyEffects
local CreateInfoButton = ST._CreateInfoButton
local FormatTime = CooldownCompanion.FormatTime
local AddColorPicker = ST._AddColorPicker

-- Module-level reference for lifecycle management
local formatEditorFrame = nil

-- Token list for insert buttons
local TOKEN_LIST = {"name", "time", "charges", "maxcharges", "stacks", "aura", "keybind", "status", "icon"}

-- Tokens available as conditional targets (excludes always-present tokens: name, status, icon)
local COND_TOKEN_LIST = {}
local COND_TOKEN_ORDER = {"time", "available", "charges", "maxcharges", "missingcharges", "zerocharges", "stacks", "aura", "keybind", "pandemic", "proc", "unusable", "oor", "incombat"}
for _, t in ipairs(COND_TOKEN_ORDER) do
    COND_TOKEN_LIST[t] = t
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
local COLOR_EFFECT       = "ffcc44ff"  -- purple:  {flash}, {pulse}, {glow}
local COLOR_COLOR_TAG    = "ff44bbff"  -- blue:    {cooldown}, {ready}, {active}

local function BuildSyntaxString(segments)
    -- Pass 1: pair cond_start with cond_end, and effect_start with effect_end
    local stack = {}       -- { {index, value, negated}, ... }
    local openMatched = {} -- openMatched[i] = true if cond_start at index i is paired
    local closeInfo = {}   -- closeInfo[i] = negated (bool) of matched opener, or nil if orphan

    local effectStack = {}
    local effectOpenMatched = {}
    local effectCloseMatched = {}

    local colorStack = {}
    local colorOpenMatched = {}
    local colorCloseMatched = {}

    for i, seg in ipairs(segments) do
        if seg.type == "cond_start" then
            stack[#stack + 1] = { index = i, value = seg.value, negated = seg.negated }
        elseif seg.type == "cond_end" then
            for j = #stack, 1, -1 do
                if stack[j].value == seg.value then
                    openMatched[stack[j].index] = true
                    closeInfo[i] = stack[j].negated
                    table.remove(stack, j)
                    break
                end
            end
        elseif seg.type == "effect_start" then
            effectStack[#effectStack + 1] = { index = i, value = seg.value }
        elseif seg.type == "effect_end" then
            for j = #effectStack, 1, -1 do
                if effectStack[j].value == seg.value then
                    effectOpenMatched[effectStack[j].index] = true
                    effectCloseMatched[i] = true
                    table.remove(effectStack, j)
                    break
                end
            end
        elseif seg.type == "color_start" then
            colorStack[#colorStack + 1] = { index = i, value = seg.value }
        elseif seg.type == "color_end" then
            for j = #colorStack, 1, -1 do
                if colorStack[j].value == seg.value then
                    colorOpenMatched[colorStack[j].index] = true
                    colorCloseMatched[i] = true
                    table.remove(colorStack, j)
                    break
                end
            end
        end
    end

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
                color = COLOR_UNKNOWN
            end
            parts[#parts + 1] = "|c" .. color .. "{" .. prefix .. seg.value .. "}|r"
        elseif seg.type == "cond_end" then
            local color
            if closeInfo[i] ~= nil then
                color = closeInfo[i] and COLOR_COND_NEGATED or COLOR_COND_PRESENT
            else
                color = COLOR_UNKNOWN
            end
            parts[#parts + 1] = "|c" .. color .. "{/" .. seg.value .. "}|r"
        elseif seg.type == "effect_start" then
            local color = effectOpenMatched[i] and COLOR_EFFECT or COLOR_UNKNOWN
            parts[#parts + 1] = "|c" .. color .. "{" .. seg.value .. "}|r"
        elseif seg.type == "effect_end" then
            local color = effectCloseMatched[i] and COLOR_EFFECT or COLOR_UNKNOWN
            parts[#parts + 1] = "|c" .. color .. "{/" .. seg.value .. "}|r"
        elseif seg.type == "color_start" then
            local color = colorOpenMatched[i] and COLOR_COLOR_TAG or COLOR_UNKNOWN
            parts[#parts + 1] = "|c" .. color .. "{" .. seg.value .. "}|r"
        elseif seg.type == "color_end" then
            local color = colorCloseMatched[i] and COLOR_COLOR_TAG or COLOR_UNKNOWN
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

    -- Always-present conditional warnings
    local ALWAYS_PRESENT = { name = true, status = true, icon = true }
    for _, seg in ipairs(segments) do
        if seg.type == "cond_start" and ALWAYS_PRESENT[seg.value] then
            if seg.negated then
                warnings[#warnings + 1] = "{!" .. seg.value .. "} is always false \xe2\x80\x94 " .. seg.value .. " is always available"
            else
                warnings[#warnings + 1] = "{?" .. seg.value .. "} is always true \xe2\x80\x94 " .. seg.value .. " is always available"
            end
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

    -- Effect pairing
    local effectStack = {}
    for i, seg in ipairs(segments) do
        if seg.type == "effect_start" then
            effectStack[#effectStack + 1] = { value = seg.value, index = i }
        elseif seg.type == "effect_end" then
            local found = false
            for j = #effectStack, 1, -1 do
                if effectStack[j].value == seg.value then
                    if effectStack[j].index == i - 1 then
                        warnings[#warnings + 1] = "Empty {" .. seg.value .. "}: add content between {" .. seg.value .. "} and {/" .. seg.value .. "}"
                    end
                    table.remove(effectStack, j)
                    found = true
                    break
                end
            end
            if not found then
                warnings[#warnings + 1] = "{/" .. seg.value .. "} has no matching opener"
            end
        end
    end
    for _, entry in ipairs(effectStack) do
        warnings[#warnings + 1] = "{" .. entry.value .. "} is never closed"
    end

    -- Color tag pairing
    local colorStack = {}
    for i, seg in ipairs(segments) do
        if seg.type == "color_start" then
            colorStack[#colorStack + 1] = { value = seg.value, index = i }
        elseif seg.type == "color_end" then
            local found = false
            for j = #colorStack, 1, -1 do
                if colorStack[j].value == seg.value then
                    if colorStack[j].index == i - 1 then
                        warnings[#warnings + 1] = "Empty {" .. seg.value .. "}: add content between {" .. seg.value .. "} and {/" .. seg.value .. "}"
                    end
                    table.remove(colorStack, j)
                    found = true
                    break
                end
            end
            if not found then
                warnings[#warnings + 1] = "{/" .. seg.value .. "} has no matching opener"
            end
        end
    end
    for _, entry in ipairs(colorStack) do
        warnings[#warnings + 1] = "{" .. entry.value .. "} is never closed"
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
    elseif tokenName == "charges" then return mockState.hasCharges == true
    elseif tokenName == "maxcharges" then
        if not mockState.hasCharges then return false end
        return mockState.charges ~= nil and mockState.maxCharges ~= nil
            and mockState.charges == mockState.maxCharges
    elseif tokenName == "missingcharges" then
        if not mockState.hasCharges then return false end
        return mockState.charges ~= nil and mockState.maxCharges ~= nil
            and mockState.charges > 0 and mockState.charges < mockState.maxCharges
    elseif tokenName == "zerocharges" then
        if not mockState.hasCharges then return false end
        return mockState.charges ~= nil and mockState.charges == 0
    elseif tokenName == "stacks" then return mockState.stacks and mockState.stacks > 0
    elseif tokenName == "aura" then return mockState.auraTime and mockState.auraTime > 0
    elseif tokenName == "keybind" then return mockState.keybind and mockState.keybind ~= ""
    elseif tokenName == "status" then return true
    elseif tokenName == "icon" then return mockState.icon ~= nil
    elseif tokenName == "pandemic" then return mockState.pandemic == true
    elseif tokenName == "proc" then return mockState.proc == true
    elseif tokenName == "unusable" then return mockState.unusable == true
    elseif tokenName == "oor" then return mockState.oor == true
    elseif tokenName == "available" then return not mockState.time or mockState.time <= 0
    elseif tokenName == "incombat" then return mockState.incombat == true
    end
    return false
end

local function ResolvePreviewColor(name, cdColor, readyColor, auraColor, customColor)
    if name == "cooldown" then return cdColor
    elseif name == "ready" then return readyColor
    elseif name == "active" then return auraColor
    elseif name == "custom" then return customColor
    end
end

local function PreviewSubstitute(segments, style, mockState)
    local parts = {}
    local baseColor = style.textFontColor or {1, 1, 1, 1}
    local cdColor = style.textCooldownColor or {1, 0.3, 0.3, 1}
    local readyColor = style.textReadyColor or {0.2, 1.0, 0.2, 1}
    local auraColor = style.textAuraColor or {0, 0.925, 1, 1}
    local customColor = style.textCustomColor or {1, 0.82, 0, 1}
    local chargeFull = style.chargeFontColor or {1, 1, 1, 1}
    local chargeMissing = style.chargeFontColorMissing or {1, 1, 1, 1}
    local chargeZero = style.chargeFontColorZero or {1, 1, 1, 1}

    local skipDepth = 0
    local pulseDepth = 0
    local pulseActive = false
    local auraActive = mockState.auraTime and mockState.auraTime > 0
    local timeVal = mockState.time
    local auraVal = mockState.auraTime

    local colorOverride = nil
    local colorStack = {}

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
        elseif seg.type == "effect_start" then
            if seg.value == "pulse" then pulseDepth = pulseDepth + 1 end
        elseif seg.type == "effect_end" then
            if seg.value == "pulse" and pulseDepth > 0 then pulseDepth = pulseDepth - 1 end
        elseif seg.type == "color_start" then
            colorStack[#colorStack + 1] = colorOverride
            colorOverride = ResolvePreviewColor(seg.value, cdColor, readyColor, auraColor, customColor)
        elseif seg.type == "color_end" then
            colorOverride = colorStack[#colorStack]
            colorStack[#colorStack] = nil
        elseif seg.type == "literal" then
            if colorOverride then
                parts[#parts + 1] = WrapPreviewColor(seg.value, colorOverride)
            else
                parts[#parts + 1] = seg.value
            end
            if pulseDepth > 0 then pulseActive = true end
        elseif seg.unknown then
            -- unknown tokens render empty
        else
            local prevPartCount = #parts
            local token = seg.value
            if token == "name" then
                parts[#parts + 1] = WrapPreviewColor(mockState.name or "Fireball", colorOverride or baseColor)
            elseif token == "time" then
                if timeVal and timeVal > 0 then
                    parts[#parts + 1] = WrapPreviewColor(FormatTime(timeVal, style.decimalTimers), colorOverride or cdColor)
                end
            elseif token == "charges" then
                if mockState.charges then
                    local cc
                    if mockState.charges == mockState.maxCharges then cc = chargeFull
                    elseif mockState.charges == 0 then cc = chargeZero
                    else cc = chargeMissing end
                    parts[#parts + 1] = WrapPreviewColor(tostring(mockState.charges), colorOverride or cc)
                end
            elseif token == "maxcharges" then
                if mockState.maxCharges and mockState.maxCharges > 1 then
                    parts[#parts + 1] = WrapPreviewColor(tostring(mockState.maxCharges), colorOverride or baseColor)
                end
            elseif token == "stacks" then
                if mockState.stacks and mockState.stacks > 0 then
                    parts[#parts + 1] = WrapPreviewColor(tostring(mockState.stacks), colorOverride or baseColor)
                end
            elseif token == "aura" then
                if auraVal and auraVal > 0 then
                    parts[#parts + 1] = WrapPreviewColor(FormatTime(auraVal, style.decimalTimers), colorOverride or auraColor)
                end
            elseif token == "keybind" then
                if mockState.keybind and mockState.keybind ~= "" then
                    parts[#parts + 1] = WrapPreviewColor(mockState.keybind, colorOverride or baseColor)
                end
            elseif token == "status" then
                if auraActive then
                    if auraVal and auraVal > 0 then
                        parts[#parts + 1] = WrapPreviewColor(FormatTime(auraVal, style.decimalTimers), colorOverride or auraColor)
                    else
                        parts[#parts + 1] = WrapPreviewColor("Active", colorOverride or auraColor)
                    end
                elseif timeVal and timeVal > 0 then
                    parts[#parts + 1] = WrapPreviewColor(FormatTime(timeVal, style.decimalTimers), colorOverride or cdColor)
                else
                    parts[#parts + 1] = WrapPreviewColor(style.textReadyText or "Ready", colorOverride or readyColor)
                end
            elseif token == "icon" then
                if mockState.icon then
                    parts[#parts + 1] = string.format("|T%s:0|t", tostring(mockState.icon))
                end
            end
            if pulseDepth > 0 and #parts > prevPartCount then
                pulseActive = true
            end
        end
    end

    return table.concat(parts), pulseActive
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
                -- Resolve base-stored ID to current override for display name.
                local raw = C_Spell.GetOverrideSpell(bd.id)
                local displayId = (raw and raw ~= 0) and raw or bd.id
                local spellName = C_Spell.GetSpellName(displayId)
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
-- DETECT USED TOKENS (value tokens + conditionals)
------------------------------------------------------------------------
local function DetectUsedTokens(segments)
    local used = {}
    for _, seg in ipairs(segments) do
        if seg.type == "cond_start" then
            used[seg.value] = true
        elseif seg.type == "token" and not seg.unknown then
            used[seg.value] = true
        end
    end
    return used
end

------------------------------------------------------------------------
-- BUILD MOCK STATES
------------------------------------------------------------------------
local EXTRA_ROW_COLOR = {0.6, 0.6, 0.6}

-- Tokens that differentiate Ready/Cooldown states
local CD_STATE_TRIGGERS = {
    time = true, status = true, available = true,
    charges = true, maxcharges = true, missingcharges = true, zerocharges = true,
}

-- Tokens that differentiate Aura state
local AURA_STATE_TRIGGERS = {
    aura = true, status = true, stacks = true, pandemic = true,
}

local function BuildMockStates(style, segments)
    local name = GetPreviewName()
    local icon = GetPreviewIcon()
    local states = {}

    if not segments then return states end

    local used = DetectUsedTokens(segments)

    -- Determine which base rows to show
    local showCDStates = false
    local showAura = false
    for token in pairs(used) do
        if CD_STATE_TRIGGERS[token] then showCDStates = true end
        if AURA_STATE_TRIGGERS[token] then showAura = true end
    end

    if showCDStates then
        states[#states + 1] = {
            label = WrapPreviewColor("Ready:", style.textReadyColor or {0.2, 1.0, 0.2, 1}),
            state = { name = name, time = 0, charges = 3, maxCharges = 3, hasCharges = true, stacks = 0, auraTime = 0, keybind = "F1", icon = icon },
        }
        states[#states + 1] = {
            label = WrapPreviewColor("Cooldown:", style.textCooldownColor or {1, 0.3, 0.3, 1}),
            state = { name = name, time = 83, charges = 1, maxCharges = 3, hasCharges = true, stacks = 0, auraTime = 0, keybind = "F1", icon = icon },
        }
    end
    if showAura then
        states[#states + 1] = {
            label = WrapPreviewColor("Aura:", style.textAuraColor or {0, 0.925, 1, 1}),
            state = { name = name, time = 0, charges = 3, maxCharges = 3, hasCharges = true, stacks = 3, auraTime = 12.3, keybind = "F1", icon = icon },
        }
    end

    -- Fallback: if no base rows but format has value tokens, show a generic preview
    if #states == 0 then
        local hasValueToken = false
        for _, seg in ipairs(segments) do
            if seg.type == "token" and not seg.unknown then
                hasValueToken = true
                break
            end
        end
        if hasValueToken then
            states[#states + 1] = {
                label = WrapPreviewColor("Preview:", EXTRA_ROW_COLOR),
                state = { name = name, time = 0, charges = 3, maxCharges = 3, hasCharges = true, stacks = 0, auraTime = 0, keybind = "F1", icon = icon },
            }
        end
    end

    -- Extra rows for conditional-only tokens that need dedicated scenarios
    if used["zerocharges"] then
        states[#states + 1] = {
            label = WrapPreviewColor("Zero Charges:", EXTRA_ROW_COLOR),
            state = { name = name, time = 83, charges = 0, maxCharges = 3, hasCharges = true, stacks = 0, auraTime = 0, keybind = "F1", icon = icon },
        }
    end
    if used["proc"] then
        states[#states + 1] = {
            label = WrapPreviewColor("Proc:", EXTRA_ROW_COLOR),
            state = { name = name, time = 0, charges = 3, maxCharges = 3, hasCharges = true, stacks = 0, auraTime = 0, keybind = "F1", icon = icon, proc = true },
        }
    end
    if used["pandemic"] then
        states[#states + 1] = {
            label = WrapPreviewColor("Pandemic:", EXTRA_ROW_COLOR),
            state = { name = name, time = 0, charges = 3, maxCharges = 3, hasCharges = true, stacks = 1, auraTime = 4.5, keybind = "F1", icon = icon, pandemic = true },
        }
    end
    if used["unusable"] then
        states[#states + 1] = {
            label = WrapPreviewColor("Unusable:", EXTRA_ROW_COLOR),
            state = { name = name, time = 0, charges = 3, maxCharges = 3, hasCharges = true, stacks = 0, auraTime = 0, keybind = "F1", icon = icon, unusable = true },
        }
    end
    if used["oor"] then
        states[#states + 1] = {
            label = WrapPreviewColor("Out of Range:", EXTRA_ROW_COLOR),
            state = { name = name, time = 0, charges = 3, maxCharges = 3, hasCharges = true, stacks = 0, auraTime = 0, keybind = "F1", icon = icon, oor = true },
        }
    end
    if used["incombat"] then
        states[#states + 1] = {
            label = WrapPreviewColor("In Combat:", EXTRA_ROW_COLOR),
            state = { name = name, time = 0, charges = 3, maxCharges = 3, hasCharges = true, stacks = 0, auraTime = 0, keybind = "F1", icon = icon, incombat = true },
        }
    end

    return states
end

------------------------------------------------------------------------
-- OPEN FORMAT EDITOR
------------------------------------------------------------------------
local function OpenFormatEditor(style, groupId, opts)
    -- If already open, bring to front and refresh
    if formatEditorFrame then
        formatEditorFrame:Show()
        formatEditorFrame.frame:Raise()
        if formatEditorFrame._refresh then
            formatEditorFrame._refresh(style, groupId, opts)
        end
        return
    end

    local window = AceGUI:Create("Window")
    window:SetTitle((opts and opts.title) or "Format String Editor")
    window:SetWidth(400)
    window:SetHeight(600)
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
    editGroup:SetNumLines(6)
    editGroup.button:Hide()  -- hide "Accept" button, we save on change
    editGroup.scrollBar:Hide()
    editGroup.scrollBG:SetPoint("TOPRIGHT", editGroup.frame, "TOPRIGHT", -4, -23)
    window:AddChild(editGroup)

    local eb = editGroup.editBox

    -- Track the raw (uncolored) format string separately.
    -- The EditBox text contains |c...|r color codes for native rendering;
    -- currentRawText is the actual format string the user is editing.
    local currentFormatTarget = (opts and opts.saveTarget) or style
    local currentDefaultFormat = (opts and opts.defaultFormat) or "{name}  {status}"
    local currentRawText = currentFormatTarget.textFormat or currentDefaultFormat

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

    local previewContainer = AceGUI:Create("SimpleGroup")
    previewContainer:SetFullWidth(true)
    previewContainer:SetLayout("List")
    window:AddChild(previewContainer)

    -- ================================================================
    -- UPDATE FUNCTION (refreshes preview from currentRawText)
    -- ================================================================
    local currentStyle = style
    local currentGroupId = groupId

    local function UpdateDisplay()
        local segments = ParseFormatString(currentRawText)
        local mockStates = BuildMockStates(currentStyle, segments)

        -- Rebuild preview rows
        previewContainer:ReleaseChildren()
        local contentLabels = {}
        local pulseFlags = {}
        local anyPulse = false

        for i, mock in ipairs(mockStates) do
            local rowGroup = AceGUI:Create("SimpleGroup")
            rowGroup:SetFullWidth(true)
            rowGroup:SetLayout("Flow")
            previewContainer:AddChild(rowGroup)

            local prefix = AceGUI:Create("Label")
            prefix:SetRelativeWidth(0.25)
            prefix:SetFontObject(GameFontHighlight)
            prefix:SetText(mock.label)
            rowGroup:AddChild(prefix)

            local content = AceGUI:Create("Label")
            content:SetRelativeWidth(0.75)
            content:SetFontObject(GameFontHighlight)
            rowGroup:AddChild(content)

            local preview, hasPulse = PreviewSubstitute(segments, currentStyle, mock.state)
            preview = preview:gsub("\n", " ")
            content:SetText(preview)

            contentLabels[i] = content
            pulseFlags[i] = hasPulse
            if hasPulse then anyPulse = true end
        end

        -- Install or remove pulse animation OnUpdate
        local rowCount = #mockStates
        if anyPulse then
            local wf = window.frame
            wf._pulseElapsed = 0
            wf:SetScript("OnUpdate", function(self, elapsed)
                self._pulseElapsed = (self._pulseElapsed or 0) + elapsed
                if self._pulseElapsed < (1 / 30) then return end
                self._pulseElapsed = self._pulseElapsed - (1 / 30)
                local alpha = 0.7 + 0.3 * math.sin(GetTime() * 2 * math.pi)
                for idx = 1, rowCount do
                    if pulseFlags[idx] and contentLabels[idx].label then
                        contentLabels[idx].label:SetAlpha(alpha)
                    elseif contentLabels[idx].label then
                        contentLabels[idx].label:SetAlpha(1.0)
                    end
                end
            end)
        else
            window.frame:SetScript("OnUpdate", nil)
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
        {"|cff00ff00{name}|r  Spell/item display name", 1, 1, 1},
        {"|cff00ff00{time}|r  Cooldown time remaining", 1, 1, 1},
        {"|cff00ff00{charges}|r  Current charges (if spell has charges)", 1, 1, 1},
        {"|cff00ff00{maxcharges}|r  Maximum charges (if spell has charges)", 1, 1, 1},
        {"|cff00ff00{stacks}|r  Aura stacks / item count", 1, 1, 1},
        {"|cff00ff00{aura}|r  Aura duration remaining", 1, 1, 1},
        {"|cff00ff00{keybind}|r  Keybind text", 1, 1, 1},
        {"|cff00ff00{status}|r  Shows ready, cooldown, or aura automatically", 1, 1, 1},
        {"|cff00ff00{icon}|r  Inline spell icon", 1, 1, 1},
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
    -- EFFECT INSERT BUTTONS
    -- ================================================================
    local effectHeading = AceGUI:Create("Heading")
    effectHeading:SetText("Insert Effect")
    effectHeading:SetFullWidth(true)
    window:AddChild(effectHeading)

    local effectInfo = CreateInfoButton(effectHeading.frame, effectHeading.label, "LEFT", "RIGHT", 4, 0, {
        {"Visual Effects", 1, 0.82, 0, true},
        " ",
        {"Wrap tokens or text in effect tags to add", 1, 1, 1, true},
        {"animated visual indicators.", 1, 1, 1, true},
        " ",
        {"|cffcc44ff{pulse}|r  Smooth sine alpha oscillation (~1Hz)", 1, 1, 1, true},
        " ",
        {"Composes with conditionals:", 0.7, 0.7, 0.7, true},
        {"|cffffff00{?charges}|r|cffcc44ff{pulse}|r|cff00ff00{charges}|r|cffcc44ff{/pulse}|r|cffffff00{/charges}|r", 0.7, 0.7, 0.7, true},
        {"Pulse only when charges exist.", 0.7, 0.7, 0.7, true},
        " ",
        {"Pulse affects the whole line's alpha.", 0.7, 0.7, 0.7, true},
    }, effectHeading)
    effectHeading.right:ClearAllPoints()
    effectHeading.right:SetPoint("RIGHT", effectHeading.frame, "RIGHT", -3, 0)
    effectHeading.right:SetPoint("LEFT", effectInfo, "RIGHT", 4, 0)

    local effectGroup = AceGUI:Create("SimpleGroup")
    effectGroup:SetFullWidth(true)
    effectGroup:SetLayout("Flow")
    window:AddChild(effectGroup)

    local pulseBtn = AceGUI:Create("Button")
    pulseBtn:SetText("{pulse}")
    pulseBtn:SetAutoWidth(true)
    pulseBtn:SetCallback("OnClick", function()
        InsertAtCursor("{pulse}{/pulse}", 7)
    end)
    effectGroup:AddChild(pulseBtn)

    -- ================================================================
    -- COLOR INSERT BUTTONS
    -- ================================================================
    local colorHeading = AceGUI:Create("Heading")
    colorHeading:SetText("Insert Color")
    colorHeading:SetFullWidth(true)
    window:AddChild(colorHeading)

    local colorInfo = CreateInfoButton(colorHeading.frame, colorHeading.label, "LEFT", "RIGHT", 4, 0, {
        {"Color Overrides", 1, 0.82, 0, true},
        " ",
        {"Wrap tokens or literal text to force a specific", 1, 1, 1, true},
        {"color, overriding the token's default coloring.", 1, 1, 1, true},
        " ",
        {"|cff44bbff{cooldown}|r  Cooldown color (red by default)", 1, 1, 1, true},
        {"|cff44bbff{ready}|r  Ready color (green by default)", 1, 1, 1, true},
        {"|cff44bbff{active}|r  Aura active color (cyan by default)", 1, 1, 1, true},
        {"|cff44bbff{custom}|r  User-defined custom color (gold by default)", 1, 1, 1, true},
        " ",
        {"Example:", 0.7, 0.7, 0.7, true},
        {"|cff44bbff{cooldown}|r|cff00ff00{name}|r|cff44bbff{/cooldown}|r", 0.7, 0.7, 0.7, true},
        {"Shows the spell name in the cooldown color.", 0.7, 0.7, 0.7, true},
        " ",
        {"Nestable: inner color overrides outer.", 0.7, 0.7, 0.7, true},
        {"Composes with conditionals and effects.", 0.7, 0.7, 0.7, true},
    }, colorHeading)
    colorHeading.right:ClearAllPoints()
    colorHeading.right:SetPoint("RIGHT", colorHeading.frame, "RIGHT", -3, 0)
    colorHeading.right:SetPoint("LEFT", colorInfo, "RIGHT", 4, 0)

    local colorGroup = AceGUI:Create("SimpleGroup")
    colorGroup:SetFullWidth(true)
    colorGroup:SetLayout("Flow")
    window:AddChild(colorGroup)

    for _, colorName in ipairs({"cooldown", "ready", "active", "custom"}) do
        local colorBtn = AceGUI:Create("Button")
        colorBtn:SetText("{" .. colorName .. "}")
        colorBtn:SetAutoWidth(true)
        colorBtn:SetCallback("OnClick", function()
            local open = "{" .. colorName .. "}"
            local close = "{/" .. colorName .. "}"
            InsertAtCursor(open .. close, #open)
        end)
        colorGroup:AddChild(colorBtn)
    end

    AddColorPicker(window, style, "textCustomColor", "Custom Color", {1, 0.82, 0, 1}, true, UpdateDisplay, UpdateDisplay)

    -- ================================================================
    -- CONDITIONAL INSERT BUTTONS
    -- ================================================================
    local condHeading = AceGUI:Create("Heading")
    condHeading:SetText("Insert Conditional")
    condHeading:SetFullWidth(true)
    window:AddChild(condHeading)

    local condInfo = CreateInfoButton(condHeading.frame, condHeading.label, "LEFT", "RIGHT", 4, 0, {
        {"Available Conditionals", 1, 0.82, 0, true},
        " ",
        {"Show or hide parts of the format string based", 1, 1, 1, true},
        {"on whether a condition is true.", 1, 1, 1, true},
        " ",
        {"|cffffff00{time}|r  Cooldown time remaining", 1, 1, 1, true},
        {"|cffffff00{available}|r  Off cooldown / has charges", 1, 1, 1, true},
        {"|cffffff00{charges}|r  Spell has charges", 1, 1, 1, true},
        {"|cffffff00{maxcharges}|r  At max charges", 1, 1, 1, true},
        {"|cffffff00{missingcharges}|r  Recharging with charges left", 1, 1, 1, true},
        {"|cffffff00{zerocharges}|r  All charges spent", 1, 1, 1, true},
        {"|cffffff00{stacks}|r  Aura stacks / item count", 1, 1, 1, true},
        {"|cffffff00{aura}|r  Aura duration remaining", 1, 1, 1, true},
        {"|cffffff00{keybind}|r  Keybind text", 1, 1, 1, true},
        {"|cffffff00{pandemic}|r  Aura in pandemic window", 1, 1, 1, true},
        {"|cffffff00{proc}|r  Spell proc overlay active", 1, 1, 1, true},
        {"|cffffff00{unusable}|r  Spell/item not usable", 1, 1, 1, true},
        {"|cffffff00{oor}|r  Target out of range", 1, 1, 1, true},
        {"|cffffff00{incombat}|r  Player is in combat", 1, 1, 1, true},
        " ",
        {"Syntax", 1, 0.82, 0, true},
        " ",
        {"|cffffff00{?token}|r...|cffffff00{/token}|r  Show when true", 1, 1, 1, true},
        {"|cffff8844{!token}|r...|cffff8844{/token}|r  Show when false", 1, 1, 1, true},
        " ",
        {"Example:", 0.7, 0.7, 0.7, true},
        {"|cffffff00{?time}|rCD: |cff00ff00{time}|r|cffffff00{/time}|r", 0.7, 0.7, 0.7, true},
        {"Shows 'CD: 1:23' on cooldown, nothing when ready.", 0.7, 0.7, 0.7, true},
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
    condDropdown:SetWidth(130)
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
    -- SAVE BUTTON (clamped to window bottom)
    -- ================================================================
    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save & Close")
    saveBtn:SetCallback("OnClick", function()
        if currentRawText and currentRawText ~= "" then
            currentFormatTarget.textFormat = currentRawText
            CooldownCompanion:RefreshGroupFrame(currentGroupId)
            CooldownCompanion:RefreshConfigPanel()
        end
        window:Hide()
    end)
    -- Position outside AceGUI layout, clamped to window bottom
    saveBtn.frame:SetParent(window.frame)
    saveBtn.frame:ClearAllPoints()
    saveBtn.frame:SetPoint("BOTTOMLEFT", window.frame, "BOTTOMLEFT", 15, 15)
    saveBtn.frame:SetPoint("BOTTOMRIGHT", window.frame, "BOTTOMRIGHT", -15, 15)
    saveBtn.frame:SetHeight(24)
    saveBtn.frame:Show()
    window._saveBtn = saveBtn

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
            currentFormatTarget.textFormat = currentRawText
            CooldownCompanion:RefreshGroupFrame(currentGroupId)
        end
    end)

    -- Refresh function for re-opening with different style/group
    window._refresh = function(newStyle, newGroupId, newOpts)
        newOpts = newOpts or {}
        currentStyle = newStyle
        currentGroupId = newGroupId
        currentFormatTarget = newOpts.saveTarget or newStyle
        currentDefaultFormat = newOpts.defaultFormat or "{name}  {status}"
        window:SetTitle(newOpts.title or "Format String Editor")
        currentRawText = currentFormatTarget.textFormat or currentDefaultFormat
        ApplyColorized(currentRawText, #currentRawText)
        UpdateDisplay()
    end

    -- ================================================================
    -- LIFECYCLE
    -- ================================================================
    window:SetCallback("OnClose", function(widget)
        -- Stop pulse animation
        widget.frame:SetScript("OnUpdate", nil)
        -- Release save button (not part of AceGUI layout)
        if widget._saveBtn then
            AceGUI:Release(widget._saveBtn)
            widget._saveBtn = nil
        end
        -- Auto-save on close
        if currentRawText and currentRawText ~= "" and currentRawText ~= (currentFormatTarget.textFormat or currentDefaultFormat) then
            currentFormatTarget.textFormat = currentRawText
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

ST._RenderFormatPreview = function(formatString, style)
    local segments = ParseFormatString(formatString)
    local name = GetPreviewName()
    local icon = GetPreviewIcon()
    -- "All present" mock state so every token renders visibly
    local mockState = {
        name = name, time = 83, charges = 1, maxCharges = 3, hasCharges = true,
        stacks = 3, auraTime = 12.3, keybind = "F1", icon = icon,
        proc = true, pandemic = true,
    }
    local rendered = PreviewSubstitute(segments, style, mockState)
    return rendered
end
