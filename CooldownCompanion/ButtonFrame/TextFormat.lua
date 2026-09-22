-- Shared text grammar and presentation. No live buttons, gameplay queries,
-- aura widgets or secret operands are inspected here.
local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local FormatTime = CooldownCompanion.FormatTime
local CHARGE_STATE_FULL = ST.CooldownLogic.CHARGE_STATE_FULL
local CHARGE_STATE_MISSING = ST.CooldownLogic.CHARGE_STATE_MISSING
local CHARGE_STATE_ZERO = ST.CooldownLogic.CHARGE_STATE_ZERO
local math_floor, string_format, table_concat = math.floor, string.format, table.concat

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
-- No pandemic token: it needed readable pandemic state, which 12.1 made
-- permanently secret (retired Phase 3; migrations scrub saved formats).
--
-- Aura tokens are CLIENT-RENDERED on 12.1. The addon can never read the
-- tracked aura's remaining time or application count, so {aura} (remaining
-- time) and {aurastacks} (application count) never reach SubstituteTokens:
-- BuildTextRenderPlan below cuts them out of the line as aura PIECES with
-- reserved widths, and Core/AuraDisplay's text host hands the client a
-- FontString per piece. {status} on a standalone aura entry is {aura}.
local KNOWN_TOKENS = {
    name = true,
    time = true,
    charges = true,
    maxcharges = true,
    missingcharges = true,
    zerocharges = true,
    stacks = true,
    aura = true,
    aurastacks = true,
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

-- `aura` conditionals are resolved by the PLANNER, not at runtime: a
-- {?aura}...{/aura} region becomes client-rendered aura content that the
-- client shows only while the aura is active, and a {!aura}...{/aura} region
-- is dropped whole (the client cannot render "while inactive"). Neither ever
-- reaches EvaluateTokenPresence, which answers false for `aura` as a defined
-- fallback only.
local KNOWN_CONDITIONAL_TOKENS = {
    time = true,
    charges = true,
    maxcharges = true,
    missingcharges = true,
    zerocharges = true,
    stacks = true,
    aura = true,
    keybind = true,
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

local colorPrefixCache = setmetatable({}, { __mode = "k" })

-- Saved colors can change in place during candidate edits; revalidate RGB.
local function ColorPrefix(color)
    local r, g, b = color[1], color[2], color[3]
    local entry = colorPrefixCache[color]
    if entry and entry.r == r and entry.g == g and entry.b == b then
        return entry.prefix
    end

    local prefix = string_format("|cff%02x%02x%02x",
        math_floor(r * 255),
        math_floor(g * 255),
        math_floor(b * 255))
    if not entry then
        entry = {}
        colorPrefixCache[color] = entry
    end
    entry.r, entry.g, entry.b, entry.prefix = r, g, b, prefix
    return prefix
end

local function WrapColor(text, color)
    if not text or text == "" then return "" end
    if not color then return text end
    return ColorPrefix(color) .. text .. "|r"
end

local function EvaluateTokenPresence(ctx, tokenName, adapter, source)
    if tokenName == "time" then
        return ctx.timeIsSecret or (ctx.timeRemaining and ctx.timeRemaining > 0)
    elseif tokenName == "charges" then
        return ctx.usesCharges
    elseif tokenName == "maxcharges" then
        if not ctx.usesCharges then return false end
        return ctx.chargeState == CHARGE_STATE_FULL
    elseif tokenName == "missingcharges" then
        if not ctx.usesCharges then return false end
        return ctx.chargeState == CHARGE_STATE_MISSING
    elseif tokenName == "zerocharges" then
        if not ctx.usesCharges then return false end
        return ctx.chargeState == CHARGE_STATE_ZERO
    elseif tokenName == "stacks" then
        return ctx.stackDisplayKind ~= nil
    elseif tokenName == "aura" then
        -- Never asked in practice: {?aura}/{!aura} regions are resolved by
        -- BuildTextRenderPlan (client-rendered content / dropped) and never
        -- reach SubstituteTokens. The aura's presence is the client's, not
        -- the addon's, so the defined fallback answer is false.
        return false
    elseif tokenName == "keybind" then
        local kb = adapter.Keybind(source)
        return kb and kb ~= ""
    elseif tokenName == "proc" then
        return ctx.proc == true
    elseif tokenName == "unusable" then
        return ctx.unusable == true
    elseif tokenName == "oor" then
        return ctx.outOfRange == true
    elseif tokenName == "available" then
        return ctx.available
    elseif tokenName == "incombat" then
        return adapter.InCombat() == true
    end
    return false
end

local function ResolveColorName(name, cdColor, readyColor, auraColor, customColor)
    if name == "cooldown" then return cdColor
    elseif name == "ready" then return readyColor
    elseif name == "active" then return auraColor
    elseif name == "custom" then return customColor
    end
end

-- Contexts hold only readable values/flags. The live caller retains secret
-- operands and binds them after this walk; these results describe placeholders.
-- Adapters are module constants and resolve identity only when a token needs it.
local function Substitute(segments, style, ctx, adapter, source, effectState)
    local parts = ctx.parts
    wipe(parts)
    local secretColorToken, hasSecretStackValue, hasSecretNameValue
    local currentCharges, maxCharges = ctx.currentCharges, ctx.maxCharges
    local stackDisplayText, stackDisplayKind = ctx.stackDisplayText, ctx.stackDisplayKind
    local auraOnlyEntry, auraActive, auraHasTimer = ctx.auraOnlyEntry, ctx.auraActive, ctx.auraHasTimer
    local timeRemaining, timeIsSecret = ctx.timeRemaining, ctx.timeIsSecret
    local auraRemaining, auraIsSecret = ctx.auraRemaining, ctx.auraIsSecret

    local baseColor = style.textFontColor or DEFAULT_WHITE
    local cdColor = style.textCooldownColor or DEFAULT_CD_COLOR
    local readyColor = style.textReadyColor or DEFAULT_READY_COLOR
    local auraColor = style.textAuraColor or DEFAULT_AURA_COLOR
    local customColor = style.textCustomColor or DEFAULT_CUSTOM_COLOR

    -- Charge color resolution
    local chargeFull = style.chargeFontColor or DEFAULT_WHITE
    local chargeMissing = style.chargeFontColorMissing or DEFAULT_WHITE
    local chargeZero = style.chargeFontColorZero or DEFAULT_WHITE

    -- Conditional skip state for {?token}...{/token} and {!token}...{/token}
    local skipDepth = 0

    -- Pulse effect depth counter for {pulse}...{/pulse} wrapper tags
    local pulseDepth = 0

    -- Color override state for {cooldown}...{/cooldown} etc.
    local colorOverride = nil
    local colorStack = ctx.colorStack
    wipe(colorStack)

    for _, seg in ipairs(segments) do
        -- Conditional section handling
        if seg.type == "cond_start" then
            if skipDepth > 0 then
                skipDepth = skipDepth + 1
            else
                local present = EvaluateTokenPresence(ctx, seg.value, adapter, source)
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
                if ctx.hasSecretName then
                    hasSecretNameValue = true
                    parts[#parts + 1] = WrapColor("%NAME%", colorOverride or baseColor)
                else
                    local name = adapter.Name(source)
                    if name then
                        parts[#parts + 1] = WrapColor(name, colorOverride or baseColor)
                    end
                end

            elseif token == "time" then
                if timeIsSecret then
                    secretColorToken = secretColorToken or "cd"
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
                    if ctx.stackIsSecret then
                        hasSecretStackValue = true
                        parts[#parts + 1] = WrapColor("%STACKS%", colorOverride or baseColor)
                    else
                        parts[#parts + 1] = WrapColor(stackDisplayText, colorOverride or baseColor)
                    end
                end

            elseif token == "aura" or token == "aurastacks" then
                -- Emits NOTHING here: the planner routes both tokens to
                -- client-rendered aura pieces, so a segment list handed to
                -- this walk never holds them. Kept as a defined no-op for
                -- safety only.

            elseif token == "keybind" then
                local kb = adapter.Keybind(source)
                if kb and kb ~= "" then
                    parts[#parts + 1] = WrapColor(kb, colorOverride or baseColor)
                end

            elseif token == "status" then
                if auraActive then
                    if not auraHasTimer then
                        parts[#parts + 1] = WrapColor("Active", colorOverride or auraColor)
                    elseif auraIsSecret then
                        secretColorToken = secretColorToken or "aura"
                        parts[#parts + 1] = WrapColor("%STATUS%", colorOverride or auraColor)
                    elseif auraRemaining then
                        parts[#parts + 1] = WrapColor(FormatTime(auraRemaining, style), colorOverride or auraColor)
                    else
                        parts[#parts + 1] = WrapColor("Active", colorOverride or auraColor)
                    end
                elseif auraOnlyEntry then
                    -- Aura-only entries do not have a ready/cooldown fallback.
                elseif timeIsSecret then
                    secretColorToken = secretColorToken or "cd"
                    parts[#parts + 1] = WrapColor("%STATUS%", colorOverride or cdColor)
                elseif timeRemaining and timeRemaining > 0 then
                    parts[#parts + 1] = WrapColor(FormatTime(timeRemaining, style), colorOverride or cdColor)
                elseif ctx.deferred then
                    -- Deferred cooldown: timer hasn't started yet, show cooldown
                    -- color with placeholder instead of "Ready".
                    parts[#parts + 1] = WrapColor("...", colorOverride or cdColor)
                else
                    parts[#parts + 1] = WrapColor(style.textReadyText or "Ready", colorOverride or readyColor)
                end

            elseif token == "icon" then
                local iconTex = adapter.Icon(source)
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

    return table_concat(parts), secretColorToken, hasSecretStackValue == true, hasSecretNameValue == true
end

ST._TextFormat = {
    Parse = ParseFormatString,
    Substitute = Substitute,
    NewContext = function() return { parts = {}, colorStack = {} } end,
    ColorPrefix = ColorPrefix,
    IsAuraOnlyEntry = IsAuraOnlyEntry,
    DEFAULT_WHITE = DEFAULT_WHITE,
    DEFAULT_CD_COLOR = DEFAULT_CD_COLOR,
    DEFAULT_READY_COLOR = DEFAULT_READY_COLOR,
    DEFAULT_AURA_COLOR = DEFAULT_AURA_COLOR,
    DEFAULT_CUSTOM_COLOR = DEFAULT_CUSTOM_COLOR,
    DEFAULT_TEXT_FORMAT = DEFAULT_TEXT_FORMAT,
}
