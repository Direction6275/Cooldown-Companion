--[[
    CooldownCompanion - ButtonFrame/TextMode
    Text-mode button creation, format string parser, styling, and display updates
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic
-- F2 canary sink (loaded before this file; dev-gated, observe-only).
local RefreshTelemetry = ST.RefreshTelemetry
local CHARGE_STATE_FULL = CooldownLogic.CHARGE_STATE_FULL
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO

-- Localize frequently-used globals
local GetTime = GetTime
local pairs = pairs
local ipairs = ipairs
local unpack = unpack
local math_floor = math.floor
local math_sin = math.sin
local math_pi = math.pi
local string_format = string.format
local table_concat = table.concat
local issecretvalue = issecretvalue
local wipe = wipe
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior

-- Imports from Helpers
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions

-- Imports from VisualState
local ClearButtonVisualState = ST._ClearButtonVisualState
local AreButtonVisualStateSnapshotsEnabled = ST._AreButtonVisualStateSnapshotsEnabled

-- Imports from Glows

-- Shared click-through helpers from Utils.lua
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive

-- Shared helpers from ButtonFrame/Helpers.lua
local IsEntryItemLike = CooldownCompanion.IsEntryItemLike
local ResolveEffectiveItem = CooldownCompanion.ResolveEffectiveItem
local FormatTime = CooldownCompanion.FormatTime
local GetDurationSecretFormatSpec = CooldownCompanion.GetDurationSecretFormatSpec

-- Pre-defined color constant tables to avoid per-tick allocation.
-- These are used as fallbacks when style keys are nil (user hasn't customized).
-- IMPORTANT: These tables are read-only — never write to their indices.
local DEFAULT_WHITE = {1, 1, 1, 1}
local DEFAULT_CD_COLOR = {1, 0.3, 0.3, 1}
local DEFAULT_READY_COLOR = {0.2, 1.0, 0.2, 1}
local DEFAULT_AURA_COLOR = {0, 0.925, 1, 1}
local DEFAULT_CUSTOM_COLOR = {1, 0.82, 0, 1}
local DEFAULT_TEXT_FORMAT = "{name}  {status}"

local function IsAuraOnlyEntry(buttonData)
    return buttonData
        and buttonData.type == "spell"
        and buttonData.addedAs == "aura"
        and buttonData.auraTracking == true
end

------------------------------------------------------------------------
-- FORMAT STRING PARSER
-- Parses "{name}  {status}" into a list of segments:
--   { {type="literal", value="  "}, {type="token", value="name"}, ... }
-- Parsed once at creation/style-change; per-tick substitution walks the list.
------------------------------------------------------------------------
local KNOWN_TOKENS = {
    name = true,
    time = true,
    charges = true,
    maxcharges = true,
    missingcharges = true,
    zerocharges = true,
    stacks = true,
    aura = true,
    pandemic = true,
    proc = true,
    unusable = true,
    oor = true,
    available = true,
    incombat = true,
    keybind = true,
    status = true,
    icon = true,
    br = true,
}

local KNOWN_CONDITIONAL_TOKENS = {
    time = true,
    charges = true,
    maxcharges = true,
    missingcharges = true,
    zerocharges = true,
    stacks = true,
    aura = true,
    keybind = true,
    pandemic = true,
    proc = true,
    unusable = true,
    oor = true,
    available = true,
    incombat = true,
}

local KNOWN_EFFECTS = {
    pulse = true,
}

local KNOWN_COLORS = {
    cooldown = true,
    ready = true,
    active = true,
    custom = true,
}

local function ParseFormatString(fmt)
    local segments = {}
    local pos = 1
    local len = #fmt
    while pos <= len do
        local openBrace = fmt:find("{", pos, true)
        if not openBrace then
            -- Rest is literal
            segments[#segments + 1] = { type = "literal", value = fmt:sub(pos) }
            break
        end
        -- Literal before the brace
        if openBrace > pos then
            segments[#segments + 1] = { type = "literal", value = fmt:sub(pos, openBrace - 1) }
        end
        local closeBrace = fmt:find("}", openBrace + 1, true)
        if not closeBrace then
            -- Unterminated brace — treat rest as literal
            segments[#segments + 1] = { type = "literal", value = fmt:sub(openBrace) }
            break
        end
        local inner = fmt:sub(openBrace + 1, closeBrace - 1):lower()

        -- Conditional start: {?token} or {!token}
        local condPrefix = inner:sub(1, 1)
        if condPrefix == "?" or condPrefix == "!" then
            local condToken = inner:sub(2)
            if KNOWN_CONDITIONAL_TOKENS[condToken] then
                segments[#segments + 1] = {
                    type = "cond_start",
                    value = condToken,
                    negated = (condPrefix == "!"),
                }
            else
                -- Unknown conditional token — treat as literal
                segments[#segments + 1] = { type = "literal", value = fmt:sub(openBrace, closeBrace) }
            end
        -- Conditional / effect end: {/token} or {/effect}
        elseif condPrefix == "/" then
            local condToken = inner:sub(2)
            if KNOWN_CONDITIONAL_TOKENS[condToken] then
                segments[#segments + 1] = { type = "cond_end", value = condToken }
            elseif KNOWN_EFFECTS[condToken] then
                segments[#segments + 1] = { type = "effect_end", value = condToken }
            elseif KNOWN_COLORS[condToken] then
                segments[#segments + 1] = { type = "color_end", value = condToken }
            else
                segments[#segments + 1] = { type = "literal", value = fmt:sub(openBrace, closeBrace) }
            end
        elseif KNOWN_TOKENS[inner] then
            segments[#segments + 1] = { type = "token", value = inner }
        elseif KNOWN_EFFECTS[inner] then
            segments[#segments + 1] = { type = "effect_start", value = inner }
        elseif KNOWN_COLORS[inner] then
            segments[#segments + 1] = { type = "color_start", value = inner }
        else
            -- Unknown token — render as empty
            segments[#segments + 1] = { type = "token", value = inner, unknown = true }
        end
        pos = closeBrace + 1
    end
    return segments
end

------------------------------------------------------------------------
-- EFFECT HELPERS
------------------------------------------------------------------------
local function HasAnyEffects(segments)
    for _, seg in ipairs(segments) do
        if seg.type == "effect_start" then return true end
    end
    return false
end

local function EstimateFormatLineCount(segments)
    local lines = 1
    for _, seg in ipairs(segments) do
        if seg.type == "token" and not seg.unknown and seg.value == "br" then
            lines = lines + 1
        elseif seg.type == "literal" and seg.value and seg.value ~= "" then
            local _, literalBreaks = seg.value:gsub("\n", "\n")
            lines = lines + literalBreaks
        end
    end
    return lines
end

local function GetEffectiveTextHeight(style, formatString)
    local fmt = formatString or style.textFormat or DEFAULT_TEXT_FORMAT
    local baseHeight = style.textHeight or 20
    local segments = ParseFormatString(fmt)
    local lineCount = EstimateFormatLineCount(segments)
    if lineCount <= 1 then
        return baseHeight, false
    end

    local fontSize = style.textFontSize or 12
    local minHeight = math_floor(lineCount * fontSize + 4 + 0.5)
    return math.max(baseHeight, minHeight), true
end

local function ApplyTextLayout(button, style, formatString)
    local width = style.textWidth or 200
    local height, isMultiline = GetEffectiveTextHeight(style, formatString)

    button:SetSize(width, height)
    button.textString:SetJustifyV(isMultiline and "TOP" or "MIDDLE")
    button.textString:SetWordWrap(isMultiline)
end

local function ComputePulse(now)
    return 0.7 + 0.3 * math_sin(now * 2 * math_pi)
end

------------------------------------------------------------------------
-- COLOR WRAPPING
------------------------------------------------------------------------
local function WrapColor(text, color)
    if not text or text == "" then return "" end
    if not color then return text end
    return string_format("|cff%02x%02x%02x%s|r",
        math_floor(color[1] * 255),
        math_floor(color[2] * 255),
        math_floor(color[3] * 255),
        text)
end

local function ResolveTextModeStackDisplay(button)
    local itemCount = button._itemCount
    if itemCount and itemCount > 0 then
        return tostring(itemCount), "item"
    end

    return nil, nil
end

local function ClearTextVisualState(button)
    if button then
        button._textVisualIntent = nil
        button._textVisualApplied = nil
    end
end

local function ShouldStoreTextVisualState()
    return type(AreButtonVisualStateSnapshotsEnabled) == "function"
        and AreButtonVisualStateSnapshotsEnabled() == true
end

local function EnsureTextVisualTable(button, fieldName)
    local target = button[fieldName]
    if target then
        wipe(target)
    else
        target = {}
        button[fieldName] = target
    end
    return target
end

local function ResolveTextIntentDomain(button, auraOnlyEntry, auraActive, auraHasTimer, timeRemaining, timeIsSecret, auraRemaining, auraIsSecret)
    if auraActive then
        if auraHasTimer and (auraIsSecret or auraRemaining ~= nil) then
            return "aura-timer"
        end
        return "aura-active"
    end

    if auraOnlyEntry then
        return "aura-only"
    end

    if timeIsSecret or (timeRemaining and timeRemaining > 0) then
        return "cooldown"
    end

    if button._cooldownDeferred == true then
        return "deferred"
    end

    return "ready"
end

local function StoreTextVisualIntent(button, details)
    local intent = EnsureTextVisualTable(button, "_textVisualIntent")
    intent.domain = ResolveTextIntentDomain(
        button,
        details.auraOnlyEntry,
        details.auraActive,
        details.auraHasTimer,
        details.timeRemaining,
        details.timeIsSecret,
        details.auraRemaining,
        details.auraIsSecret
    )
    intent.stackSource = details.stackDisplayKind
    intent.secretDuration = details.secretValue ~= nil
    intent.secretDurationToken = details.secretColorToken
    intent.secretStack = details.secretStackValue ~= nil
    intent.secretName = details.hasSecretNameValue == true
    intent.hasText = details.text ~= nil and details.text ~= ""
    intent.pulseActive = details.effectState and details.effectState.pulseActive == true or false
    return intent
end

local function StoreTextVisualApplied(button, writePath, text, secretValue, secretStackValue, hasSecretNameValue)
    local applied = EnsureTextVisualTable(button, "_textVisualApplied")
    applied.writePath = writePath
    applied.hasText = text ~= nil and text ~= ""
    applied.secretDuration = secretValue ~= nil
    applied.secretStack = secretStackValue ~= nil
    applied.secretName = hasSecretNameValue == true
    return applied
end

local function UpdateTextVisualAppliedPulse(button)
    local applied = button and button._textVisualApplied
    if type(applied) ~= "table" then
        return
    end

    local es = button._effectState
    applied.pulseActive = es and es.pulseActive == true or false
end

------------------------------------------------------------------------
-- EVALUATE TOKEN PRESENCE
-- Returns true if the given token would produce non-empty output.
-- Used by conditional sections ({?token}...{/token}).
------------------------------------------------------------------------
local function EvaluateTokenPresence(button, tokenName, timeRemaining, timeIsSecret, auraRemaining, auraIsSecret, stackDisplayKind)
    if tokenName == "time" then
        return timeIsSecret or (timeRemaining and timeRemaining > 0)
    elseif tokenName == "charges" then
        return UsesChargeBehavior(button.buttonData)
    elseif tokenName == "maxcharges" then
        if not UsesChargeBehavior(button.buttonData) then return false end
        return button._chargeState == CHARGE_STATE_FULL
    elseif tokenName == "missingcharges" then
        if not UsesChargeBehavior(button.buttonData) then return false end
        return button._chargeState == CHARGE_STATE_MISSING
    elseif tokenName == "zerocharges" then
        if not UsesChargeBehavior(button.buttonData) then return false end
        return button._chargeState == CHARGE_STATE_ZERO
    elseif tokenName == "stacks" then
        return stackDisplayKind ~= nil
    elseif tokenName == "aura" then
        return button._auraActive == true or auraIsSecret or (auraRemaining and auraRemaining > 0)
    elseif tokenName == "keybind" then
        local kb = CooldownCompanion:GetKeybindText(button.buttonData, button._resolvedItemId, button)
        return kb and kb ~= ""
    elseif tokenName == "pandemic" then
        return button._inPandemic == true
    elseif tokenName == "proc" then
        return button._procOverlayActive == true
    elseif tokenName == "unusable" then
        return button._isUnusable == true
    elseif tokenName == "oor" then
        return button._isOutOfRange == true
    elseif tokenName == "available" then
        return button._desatCooldownActive ~= true
    elseif tokenName == "incombat" then
        return UnitAffectingCombat("player") == true
    end
    return false
end

------------------------------------------------------------------------
-- COLOR TAG RESOLUTION
------------------------------------------------------------------------
local function ResolveColorName(name, cdColor, readyColor, auraColor, customColor)
    if name == "cooldown" then return cdColor
    elseif name == "ready" then return readyColor
    elseif name == "active" then return auraColor
    elseif name == "custom" then return customColor
    end
end

------------------------------------------------------------------------
-- SUBSTITUTE TOKENS
-- Builds the final display string from pre-parsed segments.
-- Returns: displayText, secretValue, secretColorToken, secretStackValue, secretNameValue, hasSecretNameValue
------------------------------------------------------------------------
local function SubstituteTokens(button, segments, style, effectState, secretNameOverride, hasSecretNameOverride, shouldStoreTextVisualState)
    local buttonData = button.buttonData
    local parts = button._textModeParts
    if parts then
        wipe(parts)
    else
        parts = {}
        button._textModeParts = parts
    end
    local secretValue = nil
    local secretColorToken = nil
    local secretStackValue = nil
    local secretNameValue = nil
    local hasSecretNameValue = false

    local baseColor = style.textFontColor or DEFAULT_WHITE
    local cdColor = style.textCooldownColor or DEFAULT_CD_COLOR
    local readyColor = style.textReadyColor or DEFAULT_READY_COLOR
    local auraColor = style.textAuraColor or DEFAULT_AURA_COLOR
    local customColor = style.textCustomColor or DEFAULT_CUSTOM_COLOR

    -- Charge color resolution
    local chargeFull = style.chargeFontColor or DEFAULT_WHITE
    local chargeMissing = style.chargeFontColorMissing or DEFAULT_WHITE
    local chargeZero = style.chargeFontColorZero or DEFAULT_WHITE

    -- Gather live state
    local auraOnlyEntry = IsAuraOnlyEntry(buttonData)
    local currentCharges = button._currentReadableCharges
    local maxCharges = button.buttonData.maxCharges
    local stackDisplayText, stackDisplayKind = ResolveTextModeStackDisplay(button)
    local auraActive = button._auraActive
    local auraHasTimer = button._auraHasTimer == true
    -- _durationObj holds either cooldown remaining or aura remaining (when aura override is active).
    -- Determine which domain owns it this tick.
    local durationRemaining = nil
    local durationIsSecret = false
    if button._durationObj then
        local rem = button._durationObj:GetRemainingDuration()
        if button._durationObj:HasSecretValues() then
            -- F2 canary: secret remaining text is still a time-driven render,
            -- and the combat ticker floor skips in combat too -- this branch
            -- must feed the false-idle canary like the readable one below.
            RefreshTelemetry:NoteTimeRender()
            durationIsSecret = true
            durationRemaining = rem
        elseif rem and rem > 0 then
            -- F2 canary: spell-cooldown / aura remaining text is drawn from the
            -- duration object this walk (covered by the _cooldownState ==
            -- COOLDOWN / _auraActive classifier terms).
            RefreshTelemetry:NoteTimeRender()
            durationRemaining = rem
        end
    elseif not auraActive and button._itemCdStart and button._itemCdDuration and button._itemCdDuration > 0 then
        -- F2 canary: item cooldown text remaining is drawn this walk (covered by
        -- the _cooldownState == COOLDOWN classifier term).
        RefreshTelemetry:NoteTimeRender()
        local now = GetTime()
        local elapsed = now - button._itemCdStart
        local rem = button._itemCdDuration - elapsed
        if rem > 0 then
            durationRemaining = rem
        end
    end

    -- Split into time (cooldown) and aura remaining based on aura state
    local timeRemaining, timeIsSecret
    local auraRemaining, auraIsSecret
    if auraActive then
        auraRemaining = durationRemaining
        auraIsSecret = durationIsSecret
    else
        timeRemaining = durationRemaining
        timeIsSecret = durationIsSecret
    end

    -- Conditional skip state for {?token}...{/token} and {!token}...{/token}
    local skipDepth = 0

    -- Pulse effect depth counter for {pulse}...{/pulse} wrapper tags
    local pulseDepth = 0

    -- Color override state for {cooldown}...{/cooldown} etc.
    local colorOverride = nil
    local colorStack = button._textModeColorStack
    if colorStack then
        wipe(colorStack)
    else
        colorStack = {}
        button._textModeColorStack = colorStack
    end

    for _, seg in ipairs(segments) do
        -- Conditional section handling
        if seg.type == "cond_start" then
            if skipDepth > 0 then
                skipDepth = skipDepth + 1
            else
                local present = EvaluateTokenPresence(button, seg.value, timeRemaining, timeIsSecret, auraRemaining, auraIsSecret, stackDisplayKind)
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
            -- Inside a false conditional — skip this segment

        elseif seg.type == "effect_start" then
            if effectState and seg.value == "pulse" then
                pulseDepth = pulseDepth + 1
            end

        elseif seg.type == "effect_end" then
            if effectState and seg.value == "pulse" and pulseDepth > 0 then
                pulseDepth = pulseDepth - 1
            end

        elseif seg.type == "color_start" then
            colorStack[#colorStack + 1] = colorOverride
            colorOverride = ResolveColorName(seg.value, cdColor, readyColor, auraColor, customColor)

        elseif seg.type == "color_end" then
            colorOverride = colorStack[#colorStack]
            colorStack[#colorStack] = nil

        elseif seg.type == "literal" then
            if colorOverride then
                parts[#parts + 1] = WrapColor(seg.value, colorOverride)
            else
                parts[#parts + 1] = seg.value
            end
            if pulseDepth > 0 and effectState then
                effectState.pulseActive = true
            end

        elseif seg.unknown then
            -- Unknown tokens render as empty
        else
            local prevPartCount = #parts
            local token = seg.value
            if token == "name" then
                local name = buttonData.customName or buttonData.name or ""
                if not buttonData.customName and buttonData.type == "spell" then
                    if button._auraActive and hasSecretNameOverride then
                        secretNameValue = secretNameOverride
                        hasSecretNameValue = true
                        parts[#parts + 1] = WrapColor("%NAME%", colorOverride or baseColor)
                        name = nil
                    else
                        local spellName = C_Spell.GetSpellName(button._displaySpellId or buttonData.id)
                        if spellName then name = spellName end
                    end
                elseif not buttonData.customName and IsEntryItemLike(buttonData) then
                    local itemID = button._resolvedItemId or buttonData.id
                    local itemName = itemID and C_Item.GetItemNameByID(itemID)
                    if itemName then name = itemName end
                end
                if name then
                    parts[#parts + 1] = WrapColor(name, colorOverride or baseColor)
                end

            elseif token == "time" then
                if timeIsSecret then
                    if not secretValue then
                        secretValue = timeRemaining
                        secretColorToken = "cd"
                    end
                    parts[#parts + 1] = WrapColor("%TIME%", colorOverride or cdColor)
                elseif timeRemaining then
                    parts[#parts + 1] = WrapColor(FormatTime(timeRemaining, style), colorOverride or cdColor)
                end

            elseif token == "charges" then
                if currentCharges ~= nil then
                    local cc
                    if currentCharges == maxCharges then
                        cc = chargeFull
                    elseif currentCharges == 0 then
                        cc = chargeZero
                    else
                        cc = chargeMissing
                    end
                    parts[#parts + 1] = WrapColor(tostring(currentCharges), colorOverride or cc)
                end

            elseif token == "maxcharges" then
                if maxCharges and maxCharges > 1 then
                    parts[#parts + 1] = WrapColor(tostring(maxCharges), colorOverride or baseColor)
                end

            elseif token == "stacks" then
                if stackDisplayKind then
                    if issecretvalue(stackDisplayText) then
                        if not secretStackValue then
                            secretStackValue = stackDisplayText
                        end
                        parts[#parts + 1] = WrapColor("%STACKS%", colorOverride or baseColor)
                    else
                        parts[#parts + 1] = WrapColor(stackDisplayText, colorOverride or baseColor)
                    end
                end

            elseif token == "aura" then
                if auraHasTimer and auraIsSecret then
                    if not secretValue then
                        secretValue = auraRemaining
                        secretColorToken = "aura"
                    end
                    parts[#parts + 1] = WrapColor("%AURA%", colorOverride or auraColor)
                elseif auraHasTimer and auraRemaining then
                    parts[#parts + 1] = WrapColor(FormatTime(auraRemaining, style), colorOverride or auraColor)
                end

            elseif token == "keybind" then
                local kb = CooldownCompanion:GetKeybindText(buttonData, button._resolvedItemId, button)
                if kb and kb ~= "" then
                    parts[#parts + 1] = WrapColor(kb, colorOverride or baseColor)
                end

            elseif token == "status" then
                if auraActive then
                    if not auraHasTimer then
                        parts[#parts + 1] = WrapColor("Active", colorOverride or auraColor)
                    elseif auraIsSecret then
                        if not secretValue then
                            secretValue = auraRemaining
                            secretColorToken = "aura"
                        end
                        parts[#parts + 1] = WrapColor("%STATUS%", colorOverride or auraColor)
                    elseif auraRemaining then
                        parts[#parts + 1] = WrapColor(FormatTime(auraRemaining, style), colorOverride or auraColor)
                    else
                        parts[#parts + 1] = WrapColor("Active", colorOverride or auraColor)
                    end
                elseif auraOnlyEntry then
                    -- Aura-only entries do not have a ready/cooldown fallback.
                elseif timeIsSecret then
                    if not secretValue then
                        secretValue = timeRemaining
                        secretColorToken = "cd"
                    end
                    parts[#parts + 1] = WrapColor("%STATUS%", colorOverride or cdColor)
                elseif timeRemaining and timeRemaining > 0 then
                    parts[#parts + 1] = WrapColor(FormatTime(timeRemaining, style), colorOverride or cdColor)
                elseif button._cooldownDeferred then
                    -- Deferred cooldown: timer hasn't started yet, show cooldown
                    -- color with placeholder instead of "Ready".
                    parts[#parts + 1] = WrapColor("...", colorOverride or cdColor)
                else
                    parts[#parts + 1] = WrapColor(style.textReadyText or "Ready", colorOverride or readyColor)
                end

            elseif token == "icon" then
                local iconTex = button.icon and button.icon:GetTexture()
                if iconTex then
                    parts[#parts + 1] = string_format("|T%s:0|t", tostring(iconTex))
                end
            elseif token == "br" then
                parts[#parts + 1] = "\n"
            end

            -- Mark pulse active when a token emitted content inside pulse region
            if pulseDepth > 0 and effectState and #parts > prevPartCount then
                effectState.pulseActive = true
            end
        end
    end

    local text = table_concat(parts)
    if shouldStoreTextVisualState then
        StoreTextVisualIntent(button, {
            auraOnlyEntry = auraOnlyEntry,
            auraActive = auraActive,
            auraHasTimer = auraHasTimer,
            timeRemaining = timeRemaining,
            timeIsSecret = timeIsSecret,
            auraRemaining = auraRemaining,
            auraIsSecret = auraIsSecret,
            currentCharges = currentCharges,
            maxCharges = maxCharges,
            stackDisplayKind = stackDisplayKind,
            stackDisplayText = stackDisplayText,
            secretValue = secretValue,
            secretColorToken = secretColorToken,
            secretStackValue = secretStackValue,
            hasSecretNameValue = hasSecretNameValue,
            text = text,
            effectState = effectState,
        })
    end

    return text, secretValue, secretColorToken, secretStackValue, secretNameValue, hasSecretNameValue
end

------------------------------------------------------------------------
-- UPDATE TEXT DISPLAY
-- Called each tick from CooldownUpdate.lua after data is resolved.
------------------------------------------------------------------------
local function UpdateTextDisplay(button, secretNameOverride, hasSecretNameOverride)
    local style = button.style
    if not style or not button._textSegments then
        ClearTextVisualState(button)
        return
    end
    local shouldStoreTextVisualState = ShouldStoreTextVisualState()
    if not shouldStoreTextVisualState then
        ClearTextVisualState(button)
    end

    -- Reset pulse content flag before substitution
    local es = button._effectState
    if es then
        es.pulseActive = false
    end

    local text, secretValue, secretColorToken, secretStackValue, secretNameValue, hasSecretNameValue = SubstituteTokens(button, button._textSegments, style, es, secretNameOverride, hasSecretNameOverride, shouldStoreTextVisualState)
    button._textSecretNameActive = hasSecretNameValue == true

    if secretValue or secretStackValue or hasSecretNameValue then
        -- Secret value pass-through: use SetFormattedText with the secret value
        -- Per-token coloring via |c..|r escape sequences works alongside % format specifiers
        -- (they operate at different layers: WoW text rendering vs C sprintf)
        local baseColor = style.textFontColor or DEFAULT_WHITE
        button.textString:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)

        local fmtStr = text

        -- Sentinel placeholders and their format specifiers / secret values
        -- Numeric secrets (cooldown/aura times) use the closest pass-through format; string secrets use %s.
        local timeFmt = GetDurationSecretFormatSpec(style)
        local allPlaceholders = {
            {text = "%TIME%",   val = secretValue,      fmt = timeFmt},
            {text = "%AURA%",   val = secretValue,      fmt = timeFmt},
            {text = "%STATUS%", val = secretValue,      fmt = timeFmt},
            {text = "%STACKS%", val = secretStackValue,  fmt = "%s"},
            {text = "%NAME%",   val = secretNameValue,   fmt = "%s", active = hasSecretNameValue},
        }

        -- Single left-to-right pass: build format string and ordered args together
        local args = button._textModeSecretArgs
        if args then
            wipe(args)
        else
            args = {}
            button._textModeSecretArgs = args
        end
        local resultParts = button._textModeSecretParts
        if resultParts then
            wipe(resultParts)
        else
            resultParts = {}
            button._textModeSecretParts = resultParts
        end
        local pos = 1
        while pos <= #fmtStr do
            local bestIdx, bestInfo
            for _, info in ipairs(allPlaceholders) do
                if info.active or info.val then
                    local idx = fmtStr:find(info.text, pos, true)
                    if idx and (not bestIdx or idx < bestIdx) then
                        bestIdx = idx
                        bestInfo = info
                    end
                end
            end

            if bestIdx then
                if bestIdx > pos then
                    resultParts[#resultParts + 1] = fmtStr:sub(pos, bestIdx - 1):gsub("%%", "%%%%")
                end
                resultParts[#resultParts + 1] = bestInfo.fmt
                args[#args + 1] = bestInfo.val
                pos = bestIdx + #bestInfo.text
            else
                resultParts[#resultParts + 1] = fmtStr:sub(pos):gsub("%%", "%%%%")
                break
            end
        end

        local finalFmt = table_concat(resultParts)
        button.textString:SetFormattedText(finalFmt, unpack(args))
        if shouldStoreTextVisualState then
            StoreTextVisualApplied(button, "formatted", text, secretValue, secretStackValue, hasSecretNameValue)
        end
        wipe(args)
    else
        -- Normal path: full per-token coloring via escape sequences
        local baseColor = style.textFontColor or DEFAULT_WHITE
        button.textString:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)
        button.textString:SetText(text)
        if shouldStoreTextVisualState then
            StoreTextVisualApplied(button, "text", text, secretValue, secretStackValue, hasSecretNameValue)
        end
    end

    -- Apply pulse alpha effect to the FontString
    if es then
        if es.pulseActive then
            button.textString:SetAlpha(es.pulseAlpha)
        else
            button.textString:SetAlpha(1.0)
        end
    end
    if shouldStoreTextVisualState then
        UpdateTextVisualAppliedPulse(button)
    end

end

------------------------------------------------------------------------
-- EFFECT ANIMATION ONUPDATE (30Hz)
------------------------------------------------------------------------
local EFFECT_INTERVAL = 1 / 30

local function EffectOnUpdate(self, elapsed)
    self._effectElapsed = (self._effectElapsed or 0) + elapsed
    if self._effectElapsed < EFFECT_INTERVAL then return end
    self._effectElapsed = self._effectElapsed - EFFECT_INTERVAL

    local now = GetTime()
    local es = self._effectState
    es.pulseAlpha = ComputePulse(now)

    if self._textSecretNameActive then
        if es.pulseActive then
            self.textString:SetAlpha(es.pulseAlpha)
        else
            self.textString:SetAlpha(1.0)
        end
        if ShouldStoreTextVisualState() then
            UpdateTextVisualAppliedPulse(self)
        else
            ClearTextVisualState(self)
        end
        return
    end

    UpdateTextDisplay(self)
end

local function InstallEffectOnUpdate(button)
    if HasAnyEffects(button._textSegments) then
        if not button._effectState then
            button._effectState = {}
        end
        local es = button._effectState
        es.pulseAlpha = 1.0
        es.pulseActive = false
        button._effectElapsed = 0
        button:SetScript("OnUpdate", EffectOnUpdate)
    elseif button._effectState then
        button._effectState = nil
        button._effectElapsed = nil
        button:SetScript("OnUpdate", nil)
        button.textString:SetAlpha(1.0)
    end
end

------------------------------------------------------------------------
-- UPDATE TEXT STYLE
-- Called when group style changes (slider drags, config edits).
------------------------------------------------------------------------
local function UpdateTextStyle(button, newStyle)
    button.style = newStyle
    if ClearButtonVisualState then
        ClearButtonVisualState(button)
    end
    ClearTextVisualState(button)
    -- Background
    local bgColor = newStyle.textBgColor or {0, 0, 0, 0}
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Border
    local borderSize = newStyle.textBorderSize or 0
    local borderRenderMode = ST.GetBorderRenderMode(newStyle, "textBorderRenderMode")
    local borderColor = newStyle.textBorderColor or {0, 0, 0, 1}
    for i = 1, 4 do
        button.borderTextures[i]:SetColorTexture(unpack(borderColor))
    end
    ApplyBorderEdgePositions(button.borderTextures, button, borderSize, borderRenderMode)

    -- Font
    local font = CooldownCompanion:FetchFont(newStyle.textFont or "Friz Quadrata TT")
    local fontSize = newStyle.textFontSize or 12
    local fontOutline = ST.GetEffectiveFontOutline(newStyle.textFontOutline or "OUTLINE")
    button.textString:SetFont(font, fontSize, fontOutline)

    -- Alignment
    local align = newStyle.textAlignment or "LEFT"
    button.textString:SetJustifyH(align)

    -- Text shadow
    ST.ApplyFontShadowForOutline(button.textString, fontOutline, newStyle.textShadow == true)

    -- Anchor text within frame respecting border
    button.textString:ClearAllPoints()
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(button, borderSize, borderRenderMode)
    local inset = ((borderSize > 0 or ST.IsEffectiveCrispBorderRenderMode(borderRenderMode, nil, borderSize)) and borderLayoutSize or 0) + 2
    button.textString:SetPoint("TOPLEFT", inset, -1)
    button.textString:SetPoint("BOTTOMRIGHT", -inset, 1)

    -- Re-parse format string
    local fmt = button.buttonData.textFormat or newStyle.textFormat or DEFAULT_TEXT_FORMAT
    button._textSegments = ParseFormatString(fmt)
    ApplyTextLayout(button, newStyle, fmt)

    -- Install or remove effect animation OnUpdate
    InstallEffectOnUpdate(button)

end

------------------------------------------------------------------------
-- CREATE TEXT FRAME
------------------------------------------------------------------------
function CooldownCompanion:CreateTextFrame(parent, index, buttonData, style)
    local fmt = buttonData.textFormat or style.textFormat or DEFAULT_TEXT_FORMAT
    local w = style.textWidth or 200
    local h = GetEffectiveTextHeight(style, fmt)

    -- Main frame
    local button = CreateFrame("Frame", parent:GetName() .. "Text" .. index, parent)
    button:SetSize(w, h)
    button._isText = true

    -- F6: flatten this text frame's render layers into one render pass
    -- (owner-validated V1-V10: no visual difference).
    button:SetFlattensRenderLayers(true)

    -- Background (sublayer 0)
    local bgColor = style.textBgColor or {0, 0, 0, 0}
    button.bg = button:CreateTexture(nil, "BACKGROUND", nil, 0)
    button.bg:SetAllPoints()
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Border textures
    local borderSize = style.textBorderSize or 0
    local borderRenderMode = ST.GetBorderRenderMode(style, "textBorderRenderMode")
    local borderColor = style.textBorderColor or {0, 0, 0, 1}
    button.borderTextures = {}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        button.borderTextures[i] = tex
    end
    ApplyBorderEdgePositions(button.borderTextures, button, borderSize, borderRenderMode)

    -- Main text FontString
    button.textString = button:CreateFontString(nil, "OVERLAY")
    local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
    local fontSize = style.textFontSize or 12
    local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
    button.textString:SetFont(font, fontSize, fontOutline)
    local baseColor = style.textFontColor or DEFAULT_WHITE
    button.textString:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)

    local align = style.textAlignment or "LEFT"
    button.textString:SetJustifyH(align)

    -- Text shadow
    ST.ApplyFontShadowForOutline(button.textString, fontOutline, style.textShadow == true)

    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(button, borderSize, borderRenderMode)
    local inset = ((borderSize > 0 or ST.IsEffectiveCrispBorderRenderMode(borderRenderMode, nil, borderSize)) and borderLayoutSize or 0) + 2
    button.textString:SetPoint("TOPLEFT", inset, -1)
    button.textString:SetPoint("BOTTOMRIGHT", -inset, 1)

    -- Hidden icon (required by UpdateButtonIcon pipeline)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 0, 0)
    button.icon:SetSize(1, 1)
    button.icon:SetAlpha(0)

    -- Hidden cooldown widget (required by CooldownUpdate pipeline for GetCooldownTimes)
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetSize(1, 1)
    button.cooldown:SetPoint("CENTER")
    button.cooldown:SetAlpha(0)
    button.cooldown:SetDrawSwipe(false)
    button.cooldown:SetDrawEdge(false)
    button.cooldown:SetDrawBling(false)
    button.cooldown:SetHideCountdownNumbers(true)
    button.cooldown:Hide()
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    button.cooldown:SetScript("OnCooldownDone", ST.OnButtonCooldownDone)

    -- Charge/item count overlay (hidden, but UpdateChargeTracking writes to button.count)
    button.overlayFrame = CreateFrame("Frame", nil, button)
    button.overlayFrame:SetAllPoints()
    button.overlayFrame:EnableMouse(false)
    button.count = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetText("")
    button.count:SetAlpha(0)  -- Hidden; charge data read from button._currentReadableCharges

    -- Store button data
    button.buttonData = buttonData
    button.index = index
    button.style = style

    -- Cache spell cooldown secrecy level
    if buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(buttonData.id)
    end

    -- Parse format string
    button._textSegments = ParseFormatString(fmt)
    ApplyTextLayout(button, style, fmt)

    -- Install effect animation if format uses effect tags
    InstallEffectOnUpdate(button)

    -- Aura tracking runtime state
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    button._auraUnit = buttonData.auraUnit or "player"
    button._auraActive = false
    button._auraTrackingReady = nil
    button._showingAuraIcon = false
    button._textSecretNameActive = nil

    if IsEntryItemLike(buttonData) then
        local effectiveItem = ResolveEffectiveItem(buttonData, true)
        button._resolvedItemId = effectiveItem and effectiveItem.itemID or buttonData.id
        button._resolvedItemAvailableQuantity = effectiveItem and effectiveItem.availableQuantity or 0
        button._resolvedItemQuantityKind = effectiveItem and effectiveItem.quantityKind or "stacks"
        button._equipmentSlotTrackable = CooldownCompanion.IsEquipmentSlotEntry(buttonData)
            and effectiveItem and effectiveItem.trackable == true or nil
    end

    -- Per-button visibility runtime state
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._groupId = parent.groupId

    -- Methods (same interface as icon/bar buttons)
    button.UpdateCooldown = function(self)
        CooldownCompanion:UpdateButtonCooldown(self)
    end

    button.UpdateStyle = function(self, newStyle)
        UpdateTextStyle(self, newStyle)
    end

    -- Set icon (populates button._displaySpellId, updates button.icon texture)
    self:UpdateButtonIcon(button)

    -- Click-through (text buttons are non-interactive by default)
    SetFrameClickThroughRecursive(button, true, true)
    SetFrameClickThroughRecursive(button.cooldown, true, true)

    return button
end

------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
ST._UpdateTextDisplay = UpdateTextDisplay
ST._ParseFormatString = ParseFormatString
ST._GetEffectiveTextHeight = GetEffectiveTextHeight
