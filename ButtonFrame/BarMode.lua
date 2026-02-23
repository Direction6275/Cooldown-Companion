--[[
    CooldownCompanion - ButtonFrame/BarMode
    Bar-mode button creation, styling, fill animation, and display updates
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

-- Imports from Helpers
local SetIconAreaPoints = ST._SetIconAreaPoints
local SetBarAreaPoints = ST._SetBarAreaPoints
local AnchorBarCountText = ST._AnchorBarCountText
local ApplyEdgePositions = ST._ApplyEdgePositions
local ApplyIconTexCoord = ST._ApplyIconTexCoord
local DEFAULT_BAR_AURA_COLOR = ST._DEFAULT_BAR_AURA_COLOR
local DEFAULT_BAR_PANDEMIC_COLOR = ST._DEFAULT_BAR_PANDEMIC_COLOR
local DEFAULT_BAR_CHARGE_COLOR = ST._DEFAULT_BAR_CHARGE_COLOR

-- Imports from Glows
local CreateGlowContainer = ST._CreateGlowContainer
local SetupTooltipScripts = ST._SetupTooltipScripts
local SetBarAuraEffect = ST._SetBarAuraEffect

-- Imports from Visibility
local UpdateLossOfControl = ST._UpdateLossOfControl

-- Imports from Tracking
local UpdateIconTint = ST._UpdateIconTint

-- Shared click-through helpers from Utils.lua
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive

-- IsItemEquippable from Helpers (exported on CooldownCompanion)
local IsItemEquippable = CooldownCompanion.IsItemEquippable

-- Format remaining seconds for bar time text display
local function FormatBarTime(seconds)
    if seconds >= 60 then
        return string_format("%d:%02d", math_floor(seconds / 60), math_floor(seconds % 60))
    elseif seconds >= 10 then
        return string_format("%d", math_floor(seconds))
    elseif seconds > 0 then
        return string_format("%.1f", seconds)
    end
    return ""
end

-- Lightweight OnUpdate: interpolates bar fill + time text between ticker updates.
local function UpdateBarFill(button)
    -- Single-bar path
    -- DurationObject percent methods return secret values during combat in 12.0.1,
    -- but SetValue() accepts secrets (C-side widget method).  HasSecretValues gates
    -- expiry detection and time text formatting.
    -- Items use stored C_Item.GetItemCooldown values (_itemCdStart/_itemCdDuration).
    local onCooldown = false
    local itemRemaining = 0

    if button._durationObj and not button._barGCDSuppressed then
        onCooldown = true
        -- SetValue accepts secret values; fraction animates natively in the engine
        if button._auraActive then
            button.statusBar:SetValue(button._durationObj:GetRemainingPercent())   -- drain: 1→0
        else
            button.statusBar:SetValue(button._durationObj:GetElapsedPercent())     -- fill: 0→1
        end
    elseif button.buttonData.type == "item" then
        -- Items: use stored C_Item.GetItemCooldown values (avoids hidden-widget staleness)
        local startMs = (button._itemCdStart or 0) * 1000
        local durationMs = (button._itemCdDuration or 0) * 1000
        local now = GetTime() * 1000
        onCooldown = durationMs > 0
        if onCooldown and button._barGCDSuppressed then onCooldown = false end
        if onCooldown then
            local elapsed = now - startMs
            itemRemaining = (durationMs - elapsed) / 1000
            if button._auraActive then
                local frac = 1 - (elapsed / durationMs)
                if frac < 0 then frac = 0 end
                button.statusBar:SetValue(frac)
            else
                local frac = elapsed / durationMs
                if frac > 1 then frac = 1 end
                button.statusBar:SetValue(frac)
            end
        end
    end

    if onCooldown then
        local showTimeText = button._auraActive
            and (button.style.showAuraText ~= false)
            or (not button._auraActive and button.style.showCooldownText)
        if showTimeText then
            -- Switch font/color when mode changes
            local mode = button._auraActive and "aura" or "cd"
            if button._barTextMode ~= mode then
                button._barTextMode = mode
                if button._auraActive then
                    local f = CooldownCompanion:FetchFont(button.style.auraTextFont or "Friz Quadrata TT")
                    local s = button.style.auraTextFontSize or 12
                    local o = button.style.auraTextFontOutline or "OUTLINE"
                    button.timeText:SetFont(f, s, o)
                else
                    local f = CooldownCompanion:FetchFont(button.style.cooldownFont or "Friz Quadrata TT")
                    local s = button.style.cooldownFontSize or 12
                    local o = button.style.cooldownFontOutline or "OUTLINE"
                    button.timeText:SetFont(f, s, o)
                end
            end
            local cc = button._auraActive
                and (button.style.auraTextFontColor or {0, 0.925, 1, 1})
                or (button.style.cooldownFontColor or {1, 1, 1, 1})
            button.timeText:SetTextColor(cc[1], cc[2], cc[3], cc[4])
            -- Time text: HasSecretValues() returns a non-secret boolean.
            -- Non-secret: full FormatBarTime formatting ("1:30", "45", etc.)
            -- Secret: pass secret number to C++ SetFormattedText ("%.1f" format)
            if button._durationObj then
                local remaining = button._durationObj:GetRemainingDuration()
                if not button._durationObj:HasSecretValues() then
                    if remaining > 0 then
                        button.timeText:SetText(FormatBarTime(remaining))
                    else
                        button.timeText:SetText("")
                    end
                else
                    button.timeText:SetFormattedText("%.1f", remaining)
                end
            else
                if itemRemaining > 0 then
                    button.timeText:SetText(FormatBarTime(itemRemaining))
                else
                    button.timeText:SetText("")
                end
            end
        end
    else
        if button.buttonData.isPassive then
            button.statusBar:SetValue(0)
            button.timeText:SetText("")
        else
        button.statusBar:SetValue(1)
        if button.style.showBarReadyText then
            if button._barTextMode ~= "ready" then
                button._barTextMode = "ready"
                local f = CooldownCompanion:FetchFont(button.style.barReadyFont or "Friz Quadrata TT")
                local s = button.style.barReadyFontSize or 12
                local o = button.style.barReadyFontOutline or "OUTLINE"
                button.timeText:SetFont(f, s, o)
            end
            button.timeText:SetText(button.style.barReadyText or "Ready")
        else
            button.timeText:SetText("")
        end
        end
    end
end

-- Update bar-specific display elements (colors, desaturation, aura effects).
-- Bar fill + time text are handled by the per-button OnUpdate for smooth interpolation.
local function UpdateBarDisplay(button, fetchOk)
    local style = button.style

    -- Determine onCooldown via nil-checks (secret-safe).
    -- _durationObj is non-nil only when UpdateButtonCooldown found an active CD/aura.
    local onCooldown
    if button._durationObj then
        onCooldown = not button._barGCDSuppressed
    elseif button.buttonData.type == "item" then
        onCooldown = button._itemCdDuration and button._itemCdDuration > 0
        if onCooldown and button._barGCDSuppressed then
            onCooldown = false
        end
    end

    -- Time text color: switch between cooldown and ready colors
    local wantReadyTextColor = not onCooldown and style.showBarReadyText
    if button._barReadyTextColor ~= wantReadyTextColor then
        button._barReadyTextColor = wantReadyTextColor
        if wantReadyTextColor then
            local rc = style.barReadyTextColor or {0.2, 1.0, 0.2, 1.0}
            button.timeText:SetTextColor(rc[1], rc[2], rc[3], rc[4])
        else
            local cc = style.cooldownFontColor or {1, 1, 1, 1}
            button.timeText:SetTextColor(cc[1], cc[2], cc[3], cc[4])
        end
    end

    -- Bar color: switch between ready, cooldown, and partial charge colors.
    -- Aura-tracked buttons always use the base bar color (aura color override handles active state).
    local wantCdColor
    if onCooldown and not button.buttonData.isPassive then
        if button.buttonData.hasCharges and not button._mainCDShown then
            wantCdColor = style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR
        else
            wantCdColor = style.barCooldownColor
        end
    end
    if button._barCdColor ~= wantCdColor then
        button._barCdColor = wantCdColor
        local c = wantCdColor or style.barColor or {0.2, 0.6, 1.0, 1.0}
        button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
    end

    -- Icon desaturation: aura-tracked buttons desaturate when aura absent;
    -- cooldown buttons desaturate based on DurationObject / item CD state.
    if button.buttonData.auraTracking then
        local wantDesat
        if button.buttonData.isPassive then
            wantDesat = not button._auraActive
        else
            wantDesat = button.buttonData.desaturateWhileAuraNotActive and not button._auraActive
        end
        if not wantDesat and not button._auraActive
            and style.desaturateOnCooldown and fetchOk and not button._isOnGCD and not button._gcdJustEnded then
            if button.buttonData.hasCharges then
                if button.buttonData.type == "item" then
                    wantDesat = button._itemCdDuration and button._itemCdDuration > 0
                else
                    wantDesat = button._mainCDShown
                end
            elseif button._durationObj then
                wantDesat = true
            elseif button.buttonData.type == "item" then
                wantDesat = button._itemCdDuration and button._itemCdDuration > 0
            end
        end
        if not wantDesat and button._isEquippableNotEquipped then
            wantDesat = true
        end
        if button._desaturated ~= wantDesat then
            button._desaturated = wantDesat
            button.icon:SetDesaturated(wantDesat)
        end
    elseif style.desaturateOnCooldown or button.buttonData.desaturateWhileZeroCharges
        or button.buttonData.desaturateWhileZeroStacks or button._isEquippableNotEquipped then
        local wantDesat = false
        if style.desaturateOnCooldown and fetchOk and not button._isOnGCD and not button._gcdJustEnded then
            if button.buttonData.hasCharges then
                if button.buttonData.type == "item" then
                    wantDesat = button._itemCdDuration and button._itemCdDuration > 0
                else
                    wantDesat = button._mainCDShown
                end
            elseif button._durationObj then
                wantDesat = true
            elseif button.buttonData.type == "item" then
                wantDesat = button._itemCdDuration and button._itemCdDuration > 0
            end
        end
        if not wantDesat and button.buttonData.desaturateWhileZeroCharges and button._mainCDShown then
            wantDesat = true
        end
        if not wantDesat and button.buttonData.desaturateWhileZeroStacks and (button._itemCount or 0) == 0 then
            wantDesat = true
        end
        if not wantDesat and button._isEquippableNotEquipped then
            wantDesat = true
        end
        if button._desaturated ~= wantDesat then
            button._desaturated = wantDesat
            button.icon:SetDesaturated(wantDesat)
        end
    else
        if button._desaturated ~= false then
            button._desaturated = false
            button.icon:SetDesaturated(false)
        end
    end

    -- Icon tinting (out-of-range red / unusable dimming)
    UpdateIconTint(button, button.buttonData, style)

    -- Loss of control overlay on bar icon
    UpdateLossOfControl(button)

    -- Bar aura color: override bar fill when aura is active (pandemic overrides aura color)
    local wantAuraColor
    if button._pandemicPreview then
        wantAuraColor = (button.style and button.style.barPandemicColor) or DEFAULT_BAR_PANDEMIC_COLOR
    elseif button._auraActive then
        if button._inPandemic and style.showPandemicGlow ~= false then
            wantAuraColor = (button.style and button.style.barPandemicColor) or DEFAULT_BAR_PANDEMIC_COLOR
        elseif button.buttonData.auraIndicatorEnabled or style.auraGlowStyle ~= "none" then
            wantAuraColor = (button.style and button.style.barAuraColor) or DEFAULT_BAR_AURA_COLOR
        end
    end
    if button._barAuraColor ~= wantAuraColor then
        button._barAuraColor = wantAuraColor
        if not wantAuraColor then
            -- Reset to normal color immediately (don't wait for next tick)
            button._barCdColor = nil
            local resetColor
            if onCooldown then
                if button.buttonData.hasCharges and not button._mainCDShown then
                    resetColor = style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR
                else
                    resetColor = style.barCooldownColor
                end
            end
            local c = resetColor or style.barColor or {0.2, 0.6, 1.0, 1.0}
            button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
        end
    end
    if wantAuraColor then
        button.statusBar:SetStatusBarColor(wantAuraColor[1], wantAuraColor[2], wantAuraColor[3], wantAuraColor[4])
    end

    -- Bar aura effect (pandemic overrides effect color)
    local barAuraEffectPandemic = button._pandemicPreview or (button._auraActive and button._inPandemic and button.buttonData.pandemicGlow and style.showPandemicGlow ~= false)
    local barAuraEffectShow = button._barAuraEffectPreview or button._pandemicPreview
        or (button._auraActive and (barAuraEffectPandemic or button.buttonData.auraIndicatorEnabled or style.auraGlowStyle ~= "none"))
    SetBarAuraEffect(button, barAuraEffectShow, barAuraEffectPandemic or false)

    -- Keep the cooldown widget hidden — SetCooldown auto-shows it
    if button.cooldown:IsShown() then
        button.cooldown:Hide()
    end
end

function CooldownCompanion:CreateBarFrame(parent, index, buttonData, style)
    local barLength = style.barLength or 180
    local barHeight = style.barHeight or 20
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local showIcon = style.showBarIcon ~= false
    local isVertical = style.barFillVertical or false
    local iconReverse = showIcon and (style.barIconReverse or false)

    local iconSize = (style.barIconSizeOverride and style.barIconSize) or barHeight
    local iconOffset = showIcon and (style.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = showIcon and (iconSize + iconOffset) or 0

    -- Main bar frame
    local button = CreateFrame("Frame", parent:GetName() .. "Bar" .. index, parent)
    if isVertical then
        button:SetSize(barHeight, barLength)
    else
        button:SetSize(barLength, barHeight)
    end
    button._isBar = true
    button._isVertical = isVertical

    -- Background — covers bar area only when icon is shown (icon has its own iconBg)
    local bgColor = style.barBgColor or {0.1, 0.1, 0.1, 0.8}
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    if showIcon then
        SetBarAreaPoints(button.bg, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        button.bg:SetAllPoints()
    end
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Icon
    button.icon = button:CreateTexture(nil, "ARTWORK")
    if showIcon then
        SetIconAreaPoints(button.icon, button, isVertical, iconReverse, iconSize, borderSize)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        -- Hidden 1x1 icon (still needed for UpdateButtonIcon)
        button.icon:SetPoint("TOPLEFT", 0, 0)
        button.icon:SetSize(1, 1)
        button.icon:SetAlpha(0)
    end

    -- Icon background + border (always shown when icon visible)
    button.iconBg = button:CreateTexture(nil, "BACKGROUND")
    SetIconAreaPoints(button.iconBg, button, isVertical, iconReverse, iconSize, 0)
    button.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    if not showIcon then button.iconBg:Hide() end

    button._iconBounds = CreateFrame("Frame", nil, button)
    button._iconBounds:EnableMouse(false)
    SetIconAreaPoints(button._iconBounds, button, isVertical, iconReverse, iconSize, 0)

    button.iconBorderTextures = {}
    local borderColor = style.borderColor or {0, 0, 0, 1}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        if not showIcon then tex:Hide() end
        button.iconBorderTextures[i] = tex
    end
    ApplyEdgePositions(button.iconBorderTextures, button._iconBounds, borderSize)

    -- Bar area bounds (for border positioning separate from icon)
    button._barBounds = CreateFrame("Frame", nil, button)
    button._barBounds:EnableMouse(false)
    if showIcon then
        SetBarAreaPoints(button._barBounds, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        button._barBounds:SetAllPoints()
    end

    -- StatusBar
    button.statusBar = CreateFrame("StatusBar", nil, button)
    SetBarAreaPoints(button.statusBar, button, isVertical, iconReverse, barAreaLeft, barAreaTop, borderSize)
    if isVertical then
        button.statusBar:SetOrientation("VERTICAL")
    end
    button.statusBar:SetMinMaxValues(0, 1)
    button.statusBar:SetValue(1)
    button.statusBar:SetReverseFill(style.barReverseFill or false)
    button.statusBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(style.barTexture or "Solid"))
    local barColor = style.barColor or {0.2, 0.6, 1.0, 1.0}
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
    button.statusBar:EnableMouse(false)

    -- Name text
    button.nameText = button.statusBar:CreateFontString(nil, "OVERLAY")
    local nameFont = CooldownCompanion:FetchFont(style.barNameFont or "Friz Quadrata TT")
    local nameFontSize = style.barNameFontSize or 10
    local nameFontOutline = style.barNameFontOutline or "OUTLINE"
    button.nameText:SetFont(nameFont, nameFontSize, nameFontOutline)
    local nameColor = style.barNameFontColor or {1, 1, 1, 1}
    button.nameText:SetTextColor(nameColor[1], nameColor[2], nameColor[3], nameColor[4])
    local nameOffX = style.barNameTextOffsetX or 0
    local nameOffY = style.barNameTextOffsetY or 0
    local nameReverse = style.barNameTextReverse
    if isVertical then
        if nameReverse then
            button.nameText:SetPoint("TOP", nameOffX, -3 + nameOffY)
        else
            button.nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        end
        button.nameText:SetJustifyH("CENTER")
    else
        if nameReverse then
            button.nameText:SetPoint("RIGHT", -3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("RIGHT")
        else
            button.nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("LEFT")
        end
    end
    if style.showBarNameText ~= false or buttonData.customName then
        button.nameText:SetText(buttonData.customName or buttonData.name or "")
    else
        button.nameText:Hide()
    end

    -- Time text
    button.timeText = button.statusBar:CreateFontString(nil, "OVERLAY")
    local cdFont = CooldownCompanion:FetchFont(style.cooldownFont or "Friz Quadrata TT")
    local cdFontSize = style.cooldownFontSize or 12
    local cdFontOutline = style.cooldownFontOutline or "OUTLINE"
    button.timeText:SetFont(cdFont, cdFontSize, cdFontOutline)
    local cdColor = style.cooldownFontColor or {1, 1, 1, 1}
    button.timeText:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
    local cdOffX = style.barCdTextOffsetX or 0
    local cdOffY = style.barCdTextOffsetY or 0
    local timeReverse = style.barTimeTextReverse
    if isVertical then
        if timeReverse then
            button.timeText:SetPoint("BOTTOM", cdOffX, 3 + cdOffY)
        else
            button.timeText:SetPoint("TOP", cdOffX, -3 + cdOffY)
        end
        button.timeText:SetJustifyH("CENTER")
    else
        if timeReverse then
            button.timeText:SetPoint("LEFT", 3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("LEFT")
        else
            button.timeText:SetPoint("RIGHT", -3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("RIGHT")
        end
    end

    -- Truncate name text so it doesn't overlap time text (horizontal only, opposite sides)
    if not isVertical and nameReverse == timeReverse then
        if nameReverse then
            button.nameText:SetPoint("LEFT", button.timeText, "RIGHT", 4, 0)
        else
            button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
        end
    end

    -- Border textures (around bar area, not full button)
    button.borderTextures = {}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        button.borderTextures[i] = tex
    end
    ApplyEdgePositions(button.borderTextures, button._barBounds, borderSize)

    -- Loss of control cooldown frame (red swipe over the bar icon)
    button.locCooldown = CreateFrame("Cooldown", button:GetName() .. "LocCooldown", button, "CooldownFrameTemplate")
    button.locCooldown:SetAllPoints(button.icon)
    button.locCooldown:SetDrawEdge(true)
    button.locCooldown:SetDrawSwipe(true)
    button.locCooldown:SetSwipeColor(0.17, 0, 0, 0.8)
    button.locCooldown:SetHideCountdownNumbers(true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)

    -- Hidden cooldown frame for GetCooldownTimes() reads
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetSize(1, 1)
    button.cooldown:SetPoint("CENTER")
    button.cooldown:SetDrawSwipe(false)
    button.cooldown:SetHideCountdownNumbers(true)
    button.cooldown:Hide()
    SetFrameClickThroughRecursive(button.cooldown, true, true)

    -- Suppress bling (cooldown-end flash) on all bar buttons
    button.cooldown:SetDrawBling(false)
    button.locCooldown:SetDrawBling(false)

    -- Charge/item count text (overlay)
    button.overlayFrame = CreateFrame("Frame", nil, button)
    button.overlayFrame:SetAllPoints()
    button.overlayFrame:EnableMouse(false)
    button.count = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetText("")

    -- Apply charge/item count font settings and anchor to icon or bar center
    local defAnchor = showIcon and "BOTTOMRIGHT" or "BOTTOM"
    local defXOff = showIcon and -2 or 0
    local defYOff = 2
    if buttonData.hasCharges or buttonData.isPassive then
        local chargeFont = CooldownCompanion:FetchFont(style.chargeFont or "Friz Quadrata TT")
        local chargeFontSize = style.chargeFontSize or 12
        local chargeFontOutline = style.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)
        local chColor = style.chargeFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(chColor[1], chColor[2], chColor[3], chColor[4])
        local chargeAnchor, chargeXOffset, chargeYOffset
        if showIcon then
            chargeAnchor = style.chargeAnchor or defAnchor
            chargeXOffset = style.chargeXOffset or defXOff
            chargeYOffset = style.chargeYOffset or defYOff
        else
            chargeAnchor = "CENTER"
            chargeXOffset = 0
            chargeYOffset = 0
        end
        AnchorBarCountText(button, showIcon, chargeAnchor, chargeXOffset, chargeYOffset)
    elseif buttonData.type == "item" and not IsItemEquippable(buttonData) then
        local itemFont = CooldownCompanion:FetchFont(buttonData.itemCountFont or "Friz Quadrata TT")
        local itemFontSize = buttonData.itemCountFontSize or 12
        local itemFontOutline = buttonData.itemCountFontOutline or "OUTLINE"
        button.count:SetFont(itemFont, itemFontSize, itemFontOutline)
        local icColor = buttonData.itemCountFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(icColor[1], icColor[2], icColor[3], icColor[4])
        local itemAnchor = buttonData.itemCountAnchor or defAnchor
        local itemXOffset = buttonData.itemCountXOffset or defXOff
        local itemYOffset = buttonData.itemCountYOffset or defYOff
        AnchorBarCountText(button, showIcon, itemAnchor, itemXOffset, itemYOffset)
    else
        AnchorBarCountText(button, showIcon, defAnchor, defXOff, defYOff)
    end

    -- Aura stack count text — separate FontString for aura stacks, independent of charge text
    if buttonData.auraTracking or buttonData.isPassive then
        button.auraStackCount = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        button.auraStackCount:SetText("")
        local asFont = CooldownCompanion:FetchFont(style.auraStackFont or "Friz Quadrata TT")
        local asFontSize = style.auraStackFontSize or 12
        local asFontOutline = style.auraStackFontOutline or "OUTLINE"
        button.auraStackCount:SetFont(asFont, asFontSize, asFontOutline)
        local asColor = style.auraStackFontColor or {1, 1, 1, 1}
        button.auraStackCount:SetTextColor(asColor[1], asColor[2], asColor[3], asColor[4])
        local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
        local asXOff = style.auraStackXOffset or 2
        local asYOff = style.auraStackYOffset or 2
        if showIcon then
            button.auraStackCount:SetPoint(asAnchor, button.icon, asAnchor, asXOff, asYOff)
        else
            button.auraStackCount:SetPoint(asAnchor, button, asAnchor, asXOff, asYOff)
        end
    end

    -- Store button data
    button.buttonData = buttonData
    button.index = index
    button.style = style

    -- Cache spell cooldown secrecy level (static per-spell: NeverSecret=0, ContextuallySecret=2)
    if buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(buttonData.id)
    end

    -- Bar fill interpolation OnUpdate
    button._barFillElapsed = 0
    local barInterval = style.barUpdateInterval or 0.025
    button:SetScript("OnUpdate", function(self, elapsed)
        -- Detect aura expiry via HasSecretValues + GetRemainingDuration.
        -- Non-secret (out of combat): instant expiry detection.
        -- Secret (in combat): skip; UpdateButtonCooldown handles expiry next tick.
        -- Skip when cooldowns are dirty (target switch / UNIT_AURA just fired,
        -- ticker hasn't processed yet — old DurationObject may be invalidated)
        -- or grace period active (holdover DurationObject from previous target).
        if self._auraActive and self._durationObj
           and not self._auraGraceTicks and not CooldownCompanion._cooldownsDirty then
            if not self._durationObj:HasSecretValues() then
                if self._durationObj:GetRemainingDuration() <= 0 then
                    self._durationObj = nil
                    self._auraActive = false
                    self._inPandemic = false
                    self._barAuraColor = nil
                    local c = self.style.barColor or {0.2, 0.6, 1.0, 1.0}
                    self.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
                    SetBarAuraEffect(self, false)
                end
            end
        end
        self._barFillElapsed = self._barFillElapsed + elapsed
        if self._barFillElapsed >= barInterval then
            self._barFillElapsed = 0
            UpdateBarFill(self)
        end
    end)

    -- Aura tracking runtime state
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    button._auraUnit = buttonData.auraUnit or "player"
    button._auraActive = false

    button._auraInstanceID = nil

    -- Per-button visibility runtime state
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._groupId = parent.groupId

    -- Aura effect frames (solid border, pixel glow, proc glow)
    button.barAuraEffect = CreateGlowContainer(button, 32)

    -- Set icon
    self:UpdateButtonIcon(button)

    -- Set name text from resolved spell/item name
    if style.showBarNameText ~= false or buttonData.customName then
        local displayName = buttonData.customName or buttonData.name
        if not buttonData.customName then
            if buttonData.type == "spell" then
                local spellName = C_Spell.GetSpellName(button._displaySpellId or buttonData.id)
                if spellName then displayName = spellName end
            elseif buttonData.type == "item" then
                local itemName = C_Item.GetItemNameByID(buttonData.id)
                if itemName then displayName = itemName end
            end
        end
        button.nameText:SetText(displayName or "")
    end

    -- Methods
    button.UpdateCooldown = function(self)
        CooldownCompanion:UpdateButtonCooldown(self)
    end

    button.UpdateStyle = function(self, newStyle)
        CooldownCompanion:UpdateBarStyle(self, newStyle)
    end

    -- Click-through
    local showTooltips = style.showTooltips == true
    SetFrameClickThroughRecursive(button, true, not showTooltips)
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end

    -- Tooltip scripts
    if showTooltips then
        SetupTooltipScripts(button)
    end

    return button
end

function CooldownCompanion:UpdateBarStyle(button, newStyle)
    local barLength = newStyle.barLength or 180
    local barHeight = newStyle.barHeight or 20
    local borderSize = newStyle.borderSize or ST.DEFAULT_BORDER_SIZE
    local showIcon = newStyle.showBarIcon ~= false
    local isVertical = newStyle.barFillVertical or false
    local iconReverse = showIcon and (newStyle.barIconReverse or false)
    local iconSize = (newStyle.barIconSizeOverride and newStyle.barIconSize) or barHeight
    local iconOffset = showIcon and (newStyle.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = showIcon and (iconSize + iconOffset) or 0

    button.style = newStyle
    button._isVertical = isVertical

    -- Update bar fill OnUpdate interval
    local barInterval = newStyle.barUpdateInterval or 0.025
    button._barFillElapsed = 0
    button:SetScript("OnUpdate", function(self, elapsed)
        if self._auraActive and self._durationObj
           and not self._auraGraceTicks and not CooldownCompanion._cooldownsDirty then
            if not self._durationObj:HasSecretValues() then
                if self._durationObj:GetRemainingDuration() <= 0 then
                    self._durationObj = nil

                    self._auraActive = false
                    self._inPandemic = false
                    self._barAuraColor = nil
                    local c = self.style.barColor or {0.2, 0.6, 1.0, 1.0}
                    self.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
                    SetBarAuraEffect(self, false)
                end
            end
        end
        self._barFillElapsed = self._barFillElapsed + elapsed
        if self._barFillElapsed >= barInterval then
            self._barFillElapsed = 0
            UpdateBarFill(self)
        end
    end)

    -- Invalidate cached state
    button._desaturated = nil
    button._vertexR = nil
    button._vertexG = nil
    button._vertexB = nil
    button._chargeText = nil
    button._nilConfirmPending = nil
    button._displaySpellId = nil
    button._itemCount = nil
    button._auraActive = nil

    button._auraInstanceID = nil
    button._inPandemic = nil
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(button.buttonData)
    button._auraUnit = button.buttonData.auraUnit or "player"
    button._auraStackText = nil
    if button.auraStackCount then button.auraStackCount:SetText("") end
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._barCdColor = nil
    button._chargeRecharging = nil
    button._barReadyTextColor = nil
    button._barAuraColor = nil
    button._barAuraEffectActive = nil

    if isVertical then
        button:SetSize(barHeight, barLength)
    else
        button:SetSize(barLength, barHeight)
    end

    -- Update icon
    button.icon:ClearAllPoints()
    if showIcon then
        SetIconAreaPoints(button.icon, button, isVertical, iconReverse, iconSize, borderSize)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.icon:SetAlpha(1)
    else
        button.icon:SetPoint("TOPLEFT", 0, 0)
        button.icon:SetSize(1, 1)
        button.icon:SetAlpha(0)
    end

    button.bg:ClearAllPoints()
    if showIcon then
        SetBarAreaPoints(button.bg, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        button.bg:SetAllPoints()
    end
    button.bg:Show()

    -- Icon bg + border: always shown when icon visible
    if button.iconBg then
        SetIconAreaPoints(button.iconBg, button, isVertical, iconReverse, iconSize, 0)
        if showIcon then button.iconBg:Show() else button.iconBg:Hide() end
    end
    if button._iconBounds then
        SetIconAreaPoints(button._iconBounds, button, isVertical, iconReverse, iconSize, 0)
    end
    if button.iconBorderTextures then
        ApplyEdgePositions(button.iconBorderTextures, button._iconBounds, borderSize)
        for _, tex in ipairs(button.iconBorderTextures) do
            if showIcon then tex:Show() else tex:Hide() end
        end
    end

    -- Bar area bounds
    if button._barBounds then
        button._barBounds:ClearAllPoints()
        if showIcon then
            SetBarAreaPoints(button._barBounds, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
        else
            button._barBounds:SetAllPoints()
        end
    end

    -- Update status bar
    SetBarAreaPoints(button.statusBar, button, isVertical, iconReverse, barAreaLeft, barAreaTop, borderSize)
    if isVertical then
        button.statusBar:SetOrientation("VERTICAL")
    else
        button.statusBar:SetOrientation("HORIZONTAL")
    end
    button.statusBar:SetReverseFill(newStyle.barReverseFill or false)
    button.statusBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(newStyle.barTexture or "Solid"))
    local barColor = newStyle.barColor or {0.2, 0.6, 1.0, 1.0}
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])

    -- Update background
    local bgColor = newStyle.barBgColor or {0.1, 0.1, 0.1, 0.8}
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    if button.iconBg then
        button.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    end

    -- Update border
    local borderColor = newStyle.borderColor or {0, 0, 0, 1}
    if button.borderTextures then
        ApplyEdgePositions(button.borderTextures, button._barBounds or button, borderSize)
        for _, tex in ipairs(button.borderTextures) do
            tex:SetColorTexture(unpack(borderColor))
            tex:Show()
        end
    end
    if button.iconBorderTextures then
        for _, tex in ipairs(button.iconBorderTextures) do
            tex:SetColorTexture(unpack(borderColor))
        end
    end

    -- Update name text font and position
    local hasCustomName = button.buttonData and button.buttonData.customName
    if newStyle.showBarNameText ~= false or hasCustomName then
        local nameFont = CooldownCompanion:FetchFont(newStyle.barNameFont or "Friz Quadrata TT")
        local nameFontSize = newStyle.barNameFontSize or 10
        local nameFontOutline = newStyle.barNameFontOutline or "OUTLINE"
        button.nameText:SetFont(nameFont, nameFontSize, nameFontOutline)
        local nameColor = newStyle.barNameFontColor or {1, 1, 1, 1}
        button.nameText:SetTextColor(nameColor[1], nameColor[2], nameColor[3], nameColor[4])
        button.nameText:Show()
    else
        button.nameText:Hide()
    end

    -- Update time text font (default state; per-tick logic handles aura mode)
    local cdFont = CooldownCompanion:FetchFont(newStyle.cooldownFont or "Friz Quadrata TT")
    local cdFontSize = newStyle.cooldownFontSize or 12
    local cdFontOutline = newStyle.cooldownFontOutline or "OUTLINE"
    button.timeText:SetFont(cdFont, cdFontSize, cdFontOutline)
    local cdColor = newStyle.cooldownFontColor or {1, 1, 1, 1}
    button.timeText:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
    -- Clear cached text mode so per-tick logic re-applies the correct font
    button._barTextMode = nil

    -- Re-anchor name and time text for orientation
    local nameOffX = newStyle.barNameTextOffsetX or 0
    local nameOffY = newStyle.barNameTextOffsetY or 0
    local cdOffX = newStyle.barCdTextOffsetX or 0
    local cdOffY = newStyle.barCdTextOffsetY or 0
    local nameReverse = newStyle.barNameTextReverse
    local timeReverse = newStyle.barTimeTextReverse
    button.nameText:ClearAllPoints()
    button.timeText:ClearAllPoints()
    if isVertical then
        if nameReverse then
            button.nameText:SetPoint("TOP", nameOffX, -3 + nameOffY)
        else
            button.nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        end
        button.nameText:SetJustifyH("CENTER")
        if timeReverse then
            button.timeText:SetPoint("BOTTOM", cdOffX, 3 + cdOffY)
        else
            button.timeText:SetPoint("TOP", cdOffX, -3 + cdOffY)
        end
        button.timeText:SetJustifyH("CENTER")
    else
        if nameReverse then
            button.nameText:SetPoint("RIGHT", -3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("RIGHT")
        else
            button.nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("LEFT")
        end
        if timeReverse then
            button.timeText:SetPoint("LEFT", 3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("LEFT")
        else
            button.timeText:SetPoint("RIGHT", -3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("RIGHT")
        end
        -- Truncate name text so it doesn't overlap time text (opposite sides only)
        if nameReverse == timeReverse then
            if nameReverse then
                button.nameText:SetPoint("LEFT", button.timeText, "RIGHT", 4, 0)
            else
                button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
            end
        end
    end

    -- Update charge/item count font and anchor to icon or bar center
    local defAnchor = showIcon and "BOTTOMRIGHT" or "BOTTOM"
    local defXOff = showIcon and -2 or 0
    local defYOff = 2
    if button.buttonData and (button.buttonData.hasCharges or button.buttonData.isPassive) then
        local chargeFont = CooldownCompanion:FetchFont(newStyle.chargeFont or "Friz Quadrata TT")
        local chargeFontSize = newStyle.chargeFontSize or 12
        local chargeFontOutline = newStyle.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)
        local chColor = newStyle.chargeFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(chColor[1], chColor[2], chColor[3], chColor[4])
        local chargeAnchor, chargeXOffset, chargeYOffset
        if showIcon then
            chargeAnchor = newStyle.chargeAnchor or defAnchor
            chargeXOffset = newStyle.chargeXOffset or defXOff
            chargeYOffset = newStyle.chargeYOffset or defYOff
        else
            chargeAnchor = "CENTER"
            chargeXOffset = 0
            chargeYOffset = 0
        end
        AnchorBarCountText(button, showIcon, chargeAnchor, chargeXOffset, chargeYOffset)
    elseif button.buttonData and button.buttonData.type == "item"
       and not IsItemEquippable(button.buttonData) then
        local itemFont = CooldownCompanion:FetchFont(button.buttonData.itemCountFont or "Friz Quadrata TT")
        local itemFontSize = button.buttonData.itemCountFontSize or 12
        local itemFontOutline = button.buttonData.itemCountFontOutline or "OUTLINE"
        button.count:SetFont(itemFont, itemFontSize, itemFontOutline)
        local icColor = button.buttonData.itemCountFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(icColor[1], icColor[2], icColor[3], icColor[4])
        local itemAnchor = button.buttonData.itemCountAnchor or defAnchor
        local itemXOffset = button.buttonData.itemCountXOffset or defXOff
        local itemYOffset = button.buttonData.itemCountYOffset or defYOff
        AnchorBarCountText(button, showIcon, itemAnchor, itemXOffset, itemYOffset)
    else
        AnchorBarCountText(button, showIcon, defAnchor, defXOff, defYOff)
    end

    -- Update aura stack count font/anchor settings
    if button.auraStackCount then
        button.auraStackCount:ClearAllPoints()
        local asFont = CooldownCompanion:FetchFont(newStyle.auraStackFont or "Friz Quadrata TT")
        local asFontSize = newStyle.auraStackFontSize or 12
        local asFontOutline = newStyle.auraStackFontOutline or "OUTLINE"
        button.auraStackCount:SetFont(asFont, asFontSize, asFontOutline)
        local asColor = newStyle.auraStackFontColor or {1, 1, 1, 1}
        button.auraStackCount:SetTextColor(asColor[1], asColor[2], asColor[3], asColor[4])
        local asAnchor = newStyle.auraStackAnchor or "BOTTOMLEFT"
        local asXOff = newStyle.auraStackXOffset or 2
        local asYOff = newStyle.auraStackYOffset or 2
        if showIcon then
            button.auraStackCount:SetPoint(asAnchor, button.icon, asAnchor, asXOff, asYOff)
        else
            button.auraStackCount:SetPoint(asAnchor, button, asAnchor, asXOff, asYOff)
        end
    end

    -- Update spell name text
    self:UpdateButtonIcon(button)
    if newStyle.showBarNameText ~= false or (button.buttonData and button.buttonData.customName) then
        local displayName = button.buttonData.customName or button.buttonData.name
        if not button.buttonData.customName then
            if button.buttonData.type == "spell" then
                local spellName = C_Spell.GetSpellName(button._displaySpellId or button.buttonData.id)
                if spellName then displayName = spellName end
            elseif button.buttonData.type == "item" then
                local itemName = C_Item.GetItemNameByID(button.buttonData.id)
                if itemName then displayName = itemName end
            end
        end
        button.nameText:SetText(displayName or "")
    end

    -- Update click-through
    local showTooltips = newStyle.showTooltips == true
    SetFrameClickThroughRecursive(button, true, not showTooltips)
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end

    -- Tooltip scripts
    if showTooltips then
        button:SetScript("OnEnter", function(self)
            GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
            if self.buttonData.type == "spell" then
                GameTooltip:SetSpellByID(self._displaySpellId or self.buttonData.id)
            elseif self.buttonData.type == "item" then
                GameTooltip:SetItemByID(self.buttonData.id)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
end

-- Exports
ST._UpdateBarDisplay = UpdateBarDisplay
ST._FormatBarTime = FormatBarTime
