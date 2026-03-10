--[[
    CooldownCompanion - ButtonFrame/TextMode
    Text-mode button creation, format string parser, styling, and display updates
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals
local GetTime = GetTime
local pairs = pairs
local ipairs = ipairs
local unpack = unpack
local math_floor = math.floor
local string_format = string.format
local table_concat = table.concat
local issecretvalue = issecretvalue

-- Imports from Helpers
local ApplyEdgePositions = ST._ApplyEdgePositions

-- Imports from Glows
local SetupTooltipScripts = ST._SetupTooltipScripts

-- Shared click-through helpers from Utils.lua
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive

-- IsItemEquippable from Helpers (exported on CooldownCompanion)
local IsItemEquippable = CooldownCompanion.IsItemEquippable

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
    stacks = true,
    aura = true,
    keybind = true,
    status = true,
    icon = true,
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
            if KNOWN_TOKENS[condToken] then
                segments[#segments + 1] = {
                    type = "cond_start",
                    value = condToken,
                    negated = (condPrefix == "!"),
                }
            else
                -- Unknown conditional token — treat as literal
                segments[#segments + 1] = { type = "literal", value = fmt:sub(openBrace, closeBrace) }
            end
        -- Conditional end: {/token}
        elseif condPrefix == "/" then
            local condToken = inner:sub(2)
            if KNOWN_TOKENS[condToken] then
                segments[#segments + 1] = { type = "cond_end", value = condToken }
            else
                segments[#segments + 1] = { type = "literal", value = fmt:sub(openBrace, closeBrace) }
            end
        elseif KNOWN_TOKENS[inner] then
            segments[#segments + 1] = { type = "token", value = inner }
        else
            -- Unknown token — render as empty
            segments[#segments + 1] = { type = "token", value = inner, unknown = true }
        end
        pos = closeBrace + 1
    end
    return segments
end

------------------------------------------------------------------------
-- TIME FORMATTING
------------------------------------------------------------------------
local function FormatTextTime(seconds)
    if seconds >= 3600 then
        return string_format("%d:%02d:%02d", math_floor(seconds / 3600), math_floor(seconds / 60) % 60, math_floor(seconds % 60))
    elseif seconds >= 60 then
        return string_format("%d:%02d", math_floor(seconds / 60), math_floor(seconds % 60))
    elseif seconds >= 10 then
        return string_format("%d", math_floor(seconds))
    elseif seconds > 0 then
        return string_format("%.1f", seconds)
    end
    return ""
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

------------------------------------------------------------------------
-- EVALUATE TOKEN PRESENCE
-- Returns true if the given token would produce non-empty output.
-- Used by conditional sections ({?token}...{/token}).
------------------------------------------------------------------------
local function EvaluateTokenPresence(button, tokenName, timeRemaining, timeIsSecret, auraRemaining, auraIsSecret)
    if tokenName == "name" then
        return true  -- spell/item always has a name
    elseif tokenName == "time" then
        return (timeRemaining and timeRemaining > 0) or timeIsSecret
    elseif tokenName == "charges" then
        return button._currentReadableCharges ~= nil
    elseif tokenName == "maxcharges" then
        local mc = button.buttonData.maxCharges
        return mc and mc > 1
    elseif tokenName == "stacks" then
        local stackText = button._auraStackText
        if stackText and stackText ~= "" then return true end
        return button._itemCount and button._itemCount > 0
    elseif tokenName == "aura" then
        return (auraRemaining and auraRemaining > 0) or auraIsSecret
    elseif tokenName == "keybind" then
        local kb = CooldownCompanion:GetKeybindText(button.buttonData)
        return kb and kb ~= ""
    elseif tokenName == "status" then
        return true  -- always resolves to Ready/time/Active
    elseif tokenName == "icon" then
        return button.icon and button.icon:GetTexture() ~= nil
    end
    return false
end

------------------------------------------------------------------------
-- SUBSTITUTE TOKENS
-- Builds the final display string from pre-parsed segments.
-- Returns: displayText, secretValue (if one token resolved to a secret)
------------------------------------------------------------------------
local function SubstituteTokens(button, segments, style)
    local buttonData = button.buttonData
    local parts = {}
    local secretValue = nil
    local secretColorToken = nil

    local baseColor = style.textFontColor or {1, 1, 1, 1}
    local cdColor = style.textCooldownColor or {1, 0.3, 0.3, 1}
    local readyColor = style.textReadyColor or {0.2, 1.0, 0.2, 1}
    local auraColor = style.textAuraColor or {0, 0.925, 1, 1}

    -- Charge color resolution
    local chargeFull = style.chargeFontColor or {1, 1, 1, 1}
    local chargeMissing = style.chargeFontColorMissing or {1, 1, 1, 1}
    local chargeZero = style.chargeFontColorZero or {1, 1, 1, 1}

    -- Gather live state
    local currentCharges = button._currentReadableCharges
    local maxCharges = button.buttonData.maxCharges
    local auraActive = button._auraActive
    local onCooldown = button.cooldown and button.cooldown:IsShown()

    -- _durationObj holds either cooldown remaining or aura remaining (when aura override is active).
    -- Determine which domain owns it this tick.
    local durationRemaining = nil
    local durationIsSecret = false
    if button._durationObj then
        local rem = button._durationObj:GetRemainingDuration()
        if rem and rem > 0 then
            if issecretvalue(rem) then
                durationIsSecret = true
                durationRemaining = rem
            else
                durationRemaining = rem
            end
        end
    elseif not auraActive and button._itemCdStart and button._itemCdDuration and button._itemCdDuration > 0 then
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

    for _, seg in ipairs(segments) do
        -- Conditional section handling
        if seg.type == "cond_start" then
            if skipDepth > 0 then
                skipDepth = skipDepth + 1
            else
                local present = EvaluateTokenPresence(button, seg.value, timeRemaining, timeIsSecret, auraRemaining, auraIsSecret)
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
        elseif seg.type == "literal" then
            parts[#parts + 1] = seg.value
        elseif seg.unknown then
            -- Unknown tokens render as empty
        else
            local token = seg.value
            if token == "name" then
                local name = buttonData.customName or buttonData.name or ""
                if not buttonData.customName and buttonData.type == "spell" then
                    local spellName = C_Spell.GetSpellName(button._displaySpellId or buttonData.id)
                    if spellName then name = spellName end
                elseif not buttonData.customName and buttonData.type == "item" then
                    local itemName = C_Item.GetItemNameByID(buttonData.id)
                    if itemName then name = itemName end
                end
                parts[#parts + 1] = WrapColor(name, baseColor)

            elseif token == "time" then
                if timeIsSecret then
                    if not secretValue then
                        secretValue = timeRemaining
                        secretColorToken = "cd"
                    end
                    parts[#parts + 1] = "%%TIME%%"
                elseif timeRemaining then
                    parts[#parts + 1] = WrapColor(FormatTextTime(timeRemaining), cdColor)
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
                    parts[#parts + 1] = WrapColor(tostring(currentCharges), cc)
                end

            elseif token == "maxcharges" then
                if maxCharges and maxCharges > 1 then
                    parts[#parts + 1] = WrapColor(tostring(maxCharges), baseColor)
                end

            elseif token == "stacks" then
                local stackText = button._auraStackText
                if stackText and stackText ~= "" then
                    parts[#parts + 1] = WrapColor(stackText, baseColor)
                elseif button._itemCount and button._itemCount > 0 then
                    parts[#parts + 1] = WrapColor(tostring(button._itemCount), baseColor)
                end

            elseif token == "aura" then
                if auraIsSecret then
                    if not secretValue then
                        secretValue = auraRemaining
                        secretColorToken = "aura"
                    end
                    parts[#parts + 1] = "%%AURA%%"
                elseif auraRemaining then
                    parts[#parts + 1] = WrapColor(FormatTextTime(auraRemaining), auraColor)
                end

            elseif token == "keybind" then
                local kb = CooldownCompanion:GetKeybindText(buttonData)
                if kb and kb ~= "" then
                    parts[#parts + 1] = WrapColor(kb, baseColor)
                end

            elseif token == "status" then
                if auraActive then
                    if auraIsSecret then
                        if not secretValue then
                            secretValue = auraRemaining
                            secretColorToken = "aura"
                        end
                        parts[#parts + 1] = "%%STATUS%%"
                    elseif auraRemaining then
                        parts[#parts + 1] = WrapColor(FormatTextTime(auraRemaining), auraColor)
                    else
                        parts[#parts + 1] = WrapColor("Active", auraColor)
                    end
                elseif timeIsSecret then
                    if not secretValue then
                        secretValue = timeRemaining
                        secretColorToken = "cd"
                    end
                    parts[#parts + 1] = "%%STATUS%%"
                elseif timeRemaining and timeRemaining > 0 then
                    parts[#parts + 1] = WrapColor(FormatTextTime(timeRemaining), cdColor)
                else
                    parts[#parts + 1] = WrapColor("Ready", readyColor)
                end

            elseif token == "icon" then
                local iconTex = button.icon and button.icon:GetTexture()
                if iconTex then
                    parts[#parts + 1] = string_format("|T%s:0|t", tostring(iconTex))
                end
            end
        end
    end

    return table_concat(parts), secretValue, secretColorToken
end

------------------------------------------------------------------------
-- UPDATE TEXT DISPLAY
-- Called each tick from CooldownUpdate.lua after data is resolved.
------------------------------------------------------------------------
local function UpdateTextDisplay(button)
    local style = button.style
    if not style or not button._textSegments then return end

    local text, secretValue, secretColorToken = SubstituteTokens(button, button._textSegments, style)

    if secretValue then
        -- Secret value pass-through: use SetFormattedText with the secret value
        -- When using secret pass-through, fall back to uniform color
        -- (per-token coloring uses escape sequences which conflict with secret SetFormattedText)
        local uniformColor
        if secretColorToken == "aura" then
            uniformColor = style.textAuraColor or {0, 0.925, 1, 1}
        else
            uniformColor = style.textCooldownColor or {1, 0.3, 0.3, 1}
        end
        button.textString:SetTextColor(uniformColor[1], uniformColor[2], uniformColor[3], uniformColor[4] or 1)

        -- Strip all color escape sequences for clean SetFormattedText
        local fmtStr = text:gsub("|c%x%x%x%x%x%x%x%x", "")
        fmtStr = fmtStr:gsub("|r", "")

        -- Replace our sentinel placeholders with a unique marker before escaping %
        -- Sentinels are literal %TIME%, %AURA%, %STATUS% in the string
        local SENTINEL = "\001SECRET\001"
        local replaced = false
        for _, placeholder in ipairs({"%TIME%", "%AURA%", "%STATUS%"}) do
            if not replaced then
                local idx = fmtStr:find(placeholder, 1, true)
                if idx then
                    fmtStr = fmtStr:sub(1, idx - 1) .. SENTINEL .. fmtStr:sub(idx + #placeholder)
                    replaced = true
                end
            end
        end

        -- Escape all % for format string safety, then insert our format specifier
        fmtStr = fmtStr:gsub("%%", "%%%%")
        fmtStr = fmtStr:gsub(SENTINEL, "%%.1f")

        button.textString:SetFormattedText(fmtStr, secretValue)
    else
        -- Normal path: full per-token coloring via escape sequences
        local baseColor = style.textFontColor or {1, 1, 1, 1}
        button.textString:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)
        button.textString:SetText(text)
    end

    -- State-driven dynamic background
    if style.textDynamicBackground then
        local stateColor
        if button._auraActive then
            stateColor = style.textAuraColor or {0, 0.925, 1, 1}
        elseif button._desatCooldownActive then
            stateColor = style.textCooldownColor or {1, 0.3, 0.3, 1}
        else
            stateColor = style.textReadyColor or {0.2, 1, 0.2, 1}
        end
        local intensity = style.textDynamicBgIntensity or 0.15
        button.bg:SetColorTexture(stateColor[1], stateColor[2], stateColor[3], intensity)
    end

    -- Zebra striping (additive overlay on top of static/dynamic bg)
    if button.zebraBg then
        if style.textZebraStripe and button.index % 2 == 0 then
            local zc = style.textZebraColor or {1, 1, 1, 0.04}
            button.zebraBg:SetColorTexture(zc[1], zc[2], zc[3], zc[4])
            button.zebraBg:Show()
        else
            button.zebraBg:Hide()
        end
    end
end

------------------------------------------------------------------------
-- UPDATE TEXT STYLE
-- Called when group style changes (slider drags, config edits).
------------------------------------------------------------------------
local function UpdateTextStyle(button, newStyle)
    button.style = newStyle
    local w = newStyle.textWidth or 200
    local h = newStyle.textHeight or 20

    button:SetSize(w, h)

    -- Background
    local bgColor = newStyle.textBgColor or {0, 0, 0, 0}
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Border
    local borderSize = newStyle.textBorderSize or 0
    local borderColor = newStyle.textBorderColor or {0, 0, 0, 1}
    for i = 1, 4 do
        button.borderTextures[i]:SetColorTexture(unpack(borderColor))
    end
    ApplyEdgePositions(button.borderTextures, button, borderSize)

    -- Font
    local font = CooldownCompanion:FetchFont(newStyle.textFont or "Friz Quadrata TT")
    local fontSize = newStyle.textFontSize or 12
    local fontOutline = newStyle.textFontOutline or "OUTLINE"
    button.textString:SetFont(font, fontSize, fontOutline)

    -- Alignment
    local align = newStyle.textAlignment or "LEFT"
    button.textString:SetJustifyH(align)

    -- Text shadow
    if newStyle.textShadow then
        button.textString:SetShadowColor(0, 0, 0, 0.8)
        button.textString:SetShadowOffset(1, -1)
    else
        button.textString:SetShadowColor(0, 0, 0, 0)
        button.textString:SetShadowOffset(0, 0)
    end

    -- Anchor text within frame respecting border
    button.textString:ClearAllPoints()
    local inset = (borderSize > 0 and borderSize or 0) + 2
    button.textString:SetPoint("TOPLEFT", inset, -1)
    button.textString:SetPoint("BOTTOMRIGHT", -inset, 1)

    -- Re-parse format string
    local fmt = button.buttonData.textFormat or newStyle.textFormat or "{name}  {status}"
    button._textSegments = ParseFormatString(fmt)

    -- Tooltip setup
    local showTooltips = newStyle.showTextTooltips == true
    if showTooltips then
        SetupTooltipScripts(button)
        button:EnableMouse(true)
    else
        button:SetScript("OnEnter", nil)
        button:SetScript("OnLeave", nil)
        button:EnableMouse(false)
    end
end

------------------------------------------------------------------------
-- CREATE TEXT FRAME
------------------------------------------------------------------------
function CooldownCompanion:CreateTextFrame(parent, index, buttonData, style)
    local w = style.textWidth or 200
    local h = style.textHeight or 20

    -- Main frame
    local button = CreateFrame("Frame", parent:GetName() .. "Text" .. index, parent)
    button:SetSize(w, h)
    button._isText = true

    -- Background (sublayer 0)
    local bgColor = style.textBgColor or {0, 0, 0, 0}
    button.bg = button:CreateTexture(nil, "BACKGROUND", nil, 0)
    button.bg:SetAllPoints()
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Zebra stripe overlay (sublayer 1, above main bg)
    button.zebraBg = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    button.zebraBg:SetAllPoints()
    button.zebraBg:Hide()

    -- Border textures
    local borderSize = style.textBorderSize or 0
    local borderColor = style.textBorderColor or {0, 0, 0, 1}
    button.borderTextures = {}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        button.borderTextures[i] = tex
    end
    ApplyEdgePositions(button.borderTextures, button, borderSize)

    -- Main text FontString
    button.textString = button:CreateFontString(nil, "OVERLAY")
    local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
    local fontSize = style.textFontSize or 12
    local fontOutline = style.textFontOutline or "OUTLINE"
    button.textString:SetFont(font, fontSize, fontOutline)
    local baseColor = style.textFontColor or {1, 1, 1, 1}
    button.textString:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)

    local align = style.textAlignment or "LEFT"
    button.textString:SetJustifyH(align)
    button.textString:SetJustifyV("MIDDLE")
    button.textString:SetWordWrap(false)

    -- Text shadow
    if style.textShadow then
        button.textString:SetShadowColor(0, 0, 0, 0.8)
        button.textString:SetShadowOffset(1, -1)
    else
        button.textString:SetShadowColor(0, 0, 0, 0)
        button.textString:SetShadowOffset(0, 0)
    end

    local inset = (borderSize > 0 and borderSize or 0) + 2
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
    local fmt = buttonData.textFormat or style.textFormat or "{name}  {status}"
    button._textSegments = ParseFormatString(fmt)

    -- Aura tracking runtime state
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    button._auraUnit = buttonData.auraUnit or "player"
    button._auraActive = false
    button._showingAuraIcon = false
    button._auraViewerFrame = nil
    button._lastViewerTexId = nil
    button._auraInstanceID = nil
    button._viewerBar = nil

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

    -- Tooltip setup
    local showTooltips = style.showTextTooltips == true
    if showTooltips then
        SetupTooltipScripts(button)
        button:EnableMouse(true)
    end

    return button
end

------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
ST._UpdateTextDisplay = UpdateTextDisplay
ST._UpdateTextStyle = UpdateTextStyle
ST._ParseFormatString = ParseFormatString
