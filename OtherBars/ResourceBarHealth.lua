--[[
    CooldownCompanion - ResourceBarHealth
    Health resource bar effects, styling, updates, and preview state.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue

local math_min = math.min
local math_sin = math.sin
local math_pi = math.pi
local GetTime = GetTime
local issecretvalue = issecretvalue

local RB = ST._RB
local PERCENT_SCALE_CURVE = RB.PERCENT_SCALE_CURVE
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE
local DEFAULT_RESOURCE_TEXT_COLOR = RB.DEFAULT_RESOURCE_TEXT_COLOR

local GetResourceBarSettings = RB.GetResourceBarSettings
local GetResourceDisplayValue = RB.GetResourceDisplayValue
local GetResourceDisplayConfig = RB.GetResourceDisplayConfig
local IsVerticalResourceLayout = RB.IsVerticalResourceLayout
local IsVerticalFillReversed = RB.IsVerticalFillReversed
local ApplyPixelBorders = RB.ApplyPixelBorders
local HidePixelBorders = RB.HidePixelBorders

local HEALTH_EFFECT_JOIN_OVERLAP = 1
local HealthBar
local HEALTH_EFFECTS

local function EnsureNonNilNumber(value)
    if type(value) == "nil" then
        return 0
    end
    return value
end

HealthBar = {}
HEALTH_EFFECTS = {
    texture = RB.DEFAULT_HEALTH_EFFECT_TEXTURE or "Solid",
    incomingHealColor = RB.DEFAULT_HEALTH_INCOMING_HEAL_COLOR,
    absorbColor = RB.DEFAULT_HEALTH_ABSORB_COLOR,
    healAbsorbColor = RB.DEFAULT_HEALTH_HEAL_ABSORB_COLOR,
    lowHealthAlertColor = RB.DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR,
    lowHealthAlertThreshold = 0.35,
    lowHealthAlertThresholdFade = 0.001,
    lowHealthAlertPulseSpeed = 0.85,
    netHealingCalc = CreateUnitHealPredictionCalculator(),
    standaloneHealingCalc = CreateUnitHealPredictionCalculator(),
    absorbMissingCalc = CreateUnitHealPredictionCalculator(),
    absorbOverflowCalc = CreateUnitHealPredictionCalculator(),
    preview = {},
}
HEALTH_EFFECTS.netHealingCalc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
HEALTH_EFFECTS.netHealingCalc:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.CurrentHealth)
HEALTH_EFFECTS.netHealingCalc:SetHealAbsorbMode(Enum.UnitHealAbsorbMode.ReducedByIncomingHeals)
HEALTH_EFFECTS.standaloneHealingCalc:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.CurrentHealth)
HEALTH_EFFECTS.standaloneHealingCalc:SetHealAbsorbMode(Enum.UnitHealAbsorbMode.Total)
HEALTH_EFFECTS.absorbMissingCalc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
HEALTH_EFFECTS.absorbOverflowCalc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)

------------------------------------------------------------------------
-- Update logic: Player Health resource
------------------------------------------------------------------------

function HealthBar.GetConfig(settings)
    return GetResourceDisplayConfig(settings, RESOURCE_HEALTH)
end

function HealthBar.GetColor(config, key, fallback)
    local color = config and config[key]
    if type(color) == "table" and color[1] ~= nil and color[2] ~= nil and color[3] ~= nil then
        return color
    end
    return fallback
end

function HealthBar.GetAlpha(config, key, fallback)
    local value = tonumber(config and config[key])
    if not value then
        value = fallback
    end
    if value < 0 then
        return 0
    elseif value > 1 then
        return 1
    end
    return value
end

function HealthBar.IsBackgroundGradientEnabled(config)
    local enabled = config and config.healthBackgroundGradient
    if enabled == nil then
        return RB.DEFAULT_HEALTH_BACKGROUND_GRADIENT == true
    end
    return enabled == true
end

function HealthBar.IsFillGradientEnabled(config)
    local enabled = config and config.healthBarGradient
    if enabled == nil then
        return RB.DEFAULT_HEALTH_BAR_GRADIENT == true
    end
    return enabled == true
end

function HealthBar.SetBackgroundAnchors(bar)
    local bg = bar and bar.bg
    if not bg then return end

    local fillTexture = bar:GetStatusBarTexture()
    bg:ClearAllPoints()

    if bar._isVertical then
        if bar._reverseFill then
            bg:SetPoint("TOPLEFT", fillTexture, "BOTTOMLEFT", 0, 0)
            bg:SetPoint("TOPRIGHT", fillTexture, "BOTTOMRIGHT", 0, 0)
            bg:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        else
            bg:SetPoint("BOTTOMLEFT", fillTexture, "TOPLEFT", 0, 0)
            bg:SetPoint("BOTTOMRIGHT", fillTexture, "TOPRIGHT", 0, 0)
            bg:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            bg:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        end
    else
        bg:SetPoint("TOPLEFT", fillTexture, "TOPRIGHT", 0, 0)
        bg:SetPoint("BOTTOMLEFT", fillTexture, "BOTTOMRIGHT", 0, 0)
        bg:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    end
end

function HealthBar.EnsureEffectBar(bar, key, color, frameLevelOffset)
    if not bar then return nil end

    if not bar.healthEffectClip then
        local clip = CreateFrame("Frame", nil, bar)
        clip:SetAllPoints(bar)
        clip:SetClipsChildren(true)
        clip:SetFrameLevel(bar:GetFrameLevel() + 1)
        bar.healthEffectClip = clip
    end

    if not bar[key] then
        local effectBar = CreateFrame("StatusBar", nil, bar.healthEffectClip)
        effectBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(HEALTH_EFFECTS.texture))
        effectBar:SetMinMaxValues(0, 1)
        SetStatusBarImmediateValue(effectBar, 0)
        effectBar:Hide()
        bar[key] = effectBar
    end

    local effectBar = bar[key]
    effectBar:SetFrameLevel(bar:GetFrameLevel() + (frameLevelOffset or 2))
    effectBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(HEALTH_EFFECTS.texture))
    effectBar:SetStatusBarColor(color[1], color[2], color[3], color[4])
    return effectBar
end

function HealthBar.ApplyEffectStyle(effectBar, config, colorKey, defaultColor, textureKey)
    if not effectBar then return end

    local color = HealthBar.GetColor(config, colorKey, defaultColor)
    local texture = config and config[textureKey]
    if type(texture) ~= "string" or texture == "" then
        texture = HEALTH_EFFECTS.texture
    end
    effectBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(texture))
    effectBar:SetStatusBarColor(color[1], color[2], color[3], color[4] ~= nil and color[4] or 1)
end

function HealthBar.GetLowHealthAlertThreshold()
    local threshold = LowHealthFrame and tonumber(LowHealthFrame.lowHealthPercentStart)
    if not threshold or threshold <= 0 or threshold >= 1 then
        threshold = HEALTH_EFFECTS.lowHealthAlertThreshold
    end
    return threshold
end

function HealthBar.BuildLowHealthAlertCurve(config)
    local color = HealthBar.GetColor(config, "healthLowHealthAlertColor", HEALTH_EFFECTS.lowHealthAlertColor)
    local alpha = color[4]
    if alpha == nil then
        alpha = HEALTH_EFFECTS.lowHealthAlertColor[4] or 1
    end

    local threshold = HealthBar.GetLowHealthAlertThreshold()
    local curve = C_CurveUtil.CreateColorCurve()
    local alertColor = CreateColor(color[1], color[2], color[3], alpha)
    local transparentColor = CreateColor(color[1], color[2], color[3], 0)
    curve:AddPoint(0.0, alertColor)
    curve:AddPoint(threshold, alertColor)
    curve:AddPoint(math_min(1.0, threshold + HEALTH_EFFECTS.lowHealthAlertThresholdFade), transparentColor)
    curve:AddPoint(1.0, transparentColor)
    return curve
end

function HealthBar.ApplyLowHealthAlertStyle(effectBar, config)
    if not effectBar then return end

    local texture = config and config.healthLowHealthAlertTexture
    if type(texture) ~= "string" or texture == "" then
        texture = HEALTH_EFFECTS.texture
    end
    effectBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(texture))
    effectBar:SetMinMaxValues(0, 1)
    SetStatusBarImmediateValue(effectBar, 1)
end

function HealthBar.ApplyLowHealthAlertColor(bar, config, preview)
    local effectBar = bar and bar.lowHealthAlertBar
    local fillTexture = effectBar and effectBar:GetStatusBarTexture()
    if not fillTexture then return end

    if preview == true then
        local color = HealthBar.GetColor(config, "healthLowHealthAlertColor", HEALTH_EFFECTS.lowHealthAlertColor)
        fillTexture:SetVertexColor(color[1], color[2], color[3], color[4] ~= nil and color[4] or 1)
        return
    end

    if not bar._lowHealthAlertCurve then
        bar._lowHealthAlertCurve = HealthBar.BuildLowHealthAlertCurve(config)
    end
    local color = UnitHealthPercent("player", true, bar._lowHealthAlertCurve)
    if type(color) == "table" and color.GetRGBA then
        fillTexture:SetVertexColor(color:GetRGBA())
        return
    end

    fillTexture:SetVertexColor(0, 0, 0, 0)
end

function HealthBar.SetEffectAlphaFromBoolean(effectBar, value, alphaIfTrue, alphaIfFalse)
    if not effectBar then
        return
    end
    if effectBar.SetAlphaFromBoolean then
        effectBar:SetAlphaFromBoolean(value, alphaIfTrue, alphaIfFalse)
        return
    end
    local texture = effectBar.GetStatusBarTexture and effectBar:GetStatusBarTexture()
    if texture and texture.SetAlphaFromBoolean then
        texture:SetAlphaFromBoolean(value, alphaIfTrue, alphaIfFalse)
    end
end

function HealthBar.EnsureEffectBars(bar)
    HealthBar.EnsureEffectBar(bar, "lowHealthAlertBar", HEALTH_EFFECTS.lowHealthAlertColor, 2)
    HealthBar.EnsureEffectBar(bar, "incomingHealBar", HEALTH_EFFECTS.incomingHealColor, 3)
    HealthBar.EnsureEffectBar(bar, "absorbOverflowBar", HEALTH_EFFECTS.absorbColor, 4)
    HealthBar.EnsureEffectBar(bar, "absorbBar", HEALTH_EFFECTS.absorbColor, 5)
    HealthBar.EnsureEffectBar(bar, "healAbsorbBar", HEALTH_EFFECTS.healAbsorbColor, 6)
end

function HealthBar.LayoutFullEffectBar(bar, effectBar)
    if not bar or not effectBar then return end

    effectBar:ClearAllPoints()
    effectBar:SetOrientation(bar._isVertical and "VERTICAL" or "HORIZONTAL")
    effectBar:SetReverseFill(false)
    if bar.healthEffectClip then
        effectBar:SetAllPoints(bar.healthEffectClip)
    else
        effectBar:SetAllPoints(bar)
    end
end

function HealthBar.LayoutLowHealthAlertBar(bar, config)
    local effectBar = bar and bar.lowHealthAlertBar
    if not bar or not effectBar then return end

    if not (config and config.healthLowHealthAlertMissingHealthOnly == true) then
        HealthBar.LayoutFullEffectBar(bar, effectBar)
        return
    end

    local fillTexture = bar:GetStatusBarTexture()
    local outerFrame = bar.healthEffectClip or bar
    if not fillTexture or not outerFrame then return end

    effectBar:ClearAllPoints()
    effectBar:SetOrientation(bar._isVertical and "VERTICAL" or "HORIZONTAL")
    effectBar:SetReverseFill(false)

    if bar._isVertical then
        if bar._reverseFill then
            effectBar:SetPoint("TOPLEFT", fillTexture, "BOTTOMLEFT", 0, 0)
            effectBar:SetPoint("TOPRIGHT", fillTexture, "BOTTOMRIGHT", 0, 0)
            effectBar:SetPoint("BOTTOMLEFT", outerFrame, "BOTTOMLEFT", 0, 0)
            effectBar:SetPoint("BOTTOMRIGHT", outerFrame, "BOTTOMRIGHT", 0, 0)
        else
            effectBar:SetPoint("BOTTOMLEFT", fillTexture, "TOPLEFT", 0, 0)
            effectBar:SetPoint("BOTTOMRIGHT", fillTexture, "TOPRIGHT", 0, 0)
            effectBar:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 0, 0)
            effectBar:SetPoint("TOPRIGHT", outerFrame, "TOPRIGHT", 0, 0)
        end
    else
        effectBar:SetPoint("TOPLEFT", fillTexture, "TOPRIGHT", 0, 0)
        effectBar:SetPoint("BOTTOMLEFT", fillTexture, "BOTTOMRIGHT", 0, 0)
        effectBar:SetPoint("TOPRIGHT", outerFrame, "TOPRIGHT", 0, 0)
        effectBar:SetPoint("BOTTOMRIGHT", outerFrame, "BOTTOMRIGHT", 0, 0)
    end
end

function HealthBar.LayoutForwardEffectBar(bar, effectBar, anchorTexture, overlapJoin)
    local fillTexture = anchorTexture or (bar and bar:GetStatusBarTexture())
    if not bar or not effectBar or not fillTexture then return end

    effectBar:ClearAllPoints()
    effectBar:SetOrientation(bar._isVertical and "VERTICAL" or "HORIZONTAL")
    local overlap = overlapJoin and HEALTH_EFFECT_JOIN_OVERLAP or 0

    if bar._isVertical then
        effectBar:SetHeight(bar:GetHeight())
        if bar._reverseFill then
            effectBar:SetReverseFill(true)
            effectBar:SetPoint("TOPLEFT", fillTexture, "BOTTOMLEFT", 0, overlap)
            effectBar:SetPoint("TOPRIGHT", fillTexture, "BOTTOMRIGHT", 0, overlap)
        else
            effectBar:SetReverseFill(false)
            effectBar:SetPoint("BOTTOMLEFT", fillTexture, "TOPLEFT", 0, -overlap)
            effectBar:SetPoint("BOTTOMRIGHT", fillTexture, "TOPRIGHT", 0, -overlap)
        end
    else
        effectBar:SetReverseFill(false)
        effectBar:SetWidth(bar:GetWidth())
        effectBar:SetPoint("TOPLEFT", fillTexture, "TOPRIGHT", -overlap, 0)
        effectBar:SetPoint("BOTTOMLEFT", fillTexture, "BOTTOMRIGHT", -overlap, 0)
    end
end

function HealthBar.LayoutHealAbsorbBar(bar)
    local effectBar = bar and bar.healAbsorbBar
    local fillTexture = bar and bar:GetStatusBarTexture()
    if not bar or not effectBar or not fillTexture then return end

    effectBar:ClearAllPoints()
    effectBar:SetOrientation(bar._isVertical and "VERTICAL" or "HORIZONTAL")

    if bar._isVertical then
        effectBar:SetHeight(bar:GetHeight())
        if bar._reverseFill then
            effectBar:SetReverseFill(false)
            effectBar:SetPoint("BOTTOMLEFT", fillTexture, "BOTTOMLEFT", 0, 0)
            effectBar:SetPoint("BOTTOMRIGHT", fillTexture, "BOTTOMRIGHT", 0, 0)
        else
            effectBar:SetReverseFill(true)
            effectBar:SetPoint("TOPLEFT", fillTexture, "TOPLEFT", 0, 0)
            effectBar:SetPoint("TOPRIGHT", fillTexture, "TOPRIGHT", 0, 0)
        end
    else
        effectBar:SetReverseFill(true)
        effectBar:SetWidth(bar:GetWidth())
        effectBar:SetPoint("TOPRIGHT", fillTexture, "TOPRIGHT", 0, 0)
        effectBar:SetPoint("BOTTOMRIGHT", fillTexture, "BOTTOMRIGHT", 0, 0)
    end
end

function HealthBar.LayoutReverseEdgeEffectBar(bar, effectBar)
    if not bar or not effectBar then return end

    effectBar:ClearAllPoints()
    effectBar:SetOrientation(bar._isVertical and "VERTICAL" or "HORIZONTAL")
    if bar.healthEffectClip then
        effectBar:SetAllPoints(bar.healthEffectClip)
    else
        effectBar:SetAllPoints(bar)
    end

    if bar._isVertical then
        effectBar:SetReverseFill(not bar._reverseFill)
    else
        effectBar:SetReverseFill(true)
    end
end

function HealthBar.LayoutEffectBars(bar, borderStyle, borderSize, borderRenderMode, config)
    if not bar then return end
    if bar.healthEffectClip then
        bar.healthEffectClip:SetFrameLevel(bar:GetFrameLevel() + 1)
        bar.healthEffectClip:ClearAllPoints()
        if borderStyle == "pixel" then
            local inset = ST.GetEffectiveBorderLayoutSize(bar, borderSize, borderRenderMode)
            bar.healthEffectClip:SetPoint("TOPLEFT", bar, "TOPLEFT", inset, -inset)
            bar.healthEffectClip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -inset, inset)
        else
            bar.healthEffectClip:SetAllPoints(bar)
        end
    end
    HealthBar.LayoutLowHealthAlertBar(bar, config)
    HealthBar.LayoutForwardEffectBar(bar, bar.incomingHealBar)
    HealthBar.LayoutForwardEffectBar(bar, bar.absorbBar)
    HealthBar.LayoutReverseEdgeEffectBar(bar, bar.absorbOverflowBar)
    HealthBar.LayoutHealAbsorbBar(bar)
    if bar.textLayer then
        bar.textLayer:SetFrameLevel(bar:GetFrameLevel() + 7)
    end
end

function HealthBar.UpdateEffectBars(bar, config, maxHealth, preview)
    if not bar then return end

    local netHealingCalcPopulated = false
    local standaloneHealingCalcPopulated = false
    local function GetNetHealingCalc()
        if not netHealingCalcPopulated then
            UnitGetDetailedHealPrediction("player", nil, HEALTH_EFFECTS.netHealingCalc)
            netHealingCalcPopulated = true
        end
        return HEALTH_EFFECTS.netHealingCalc
    end
    local function GetStandaloneHealingCalc()
        if not standaloneHealingCalcPopulated then
            UnitGetDetailedHealPrediction("player", nil, HEALTH_EFFECTS.standaloneHealingCalc)
            standaloneHealingCalcPopulated = true
        end
        return HEALTH_EFFECTS.standaloneHealingCalc
    end

    if not config then
        if bar.lowHealthAlertBar then bar.lowHealthAlertBar:Hide() end
        if bar.incomingHealBar then bar.incomingHealBar:Hide() end
        if bar.absorbBar then bar.absorbBar:Hide() end
        if bar.absorbOverflowBar then bar.absorbOverflowBar:Hide() end
        if bar.healAbsorbBar then bar.healAbsorbBar:Hide() end
        return
    end

    preview = preview or HEALTH_EFFECTS.preview

    if bar.lowHealthAlertBar then
        HealthBar.ApplyLowHealthAlertStyle(bar.lowHealthAlertBar, config)
        if config.showLowHealthAlert == true or preview.lowHealthAlert == true then
            HealthBar.ApplyLowHealthAlertColor(bar, config, preview.lowHealthAlert == true)
            bar.lowHealthAlertBar:SetAlpha(0.6 + (0.4 * math_sin(GetTime() * 2 * math_pi / HEALTH_EFFECTS.lowHealthAlertPulseSpeed)))
            bar.lowHealthAlertBar:Show()
        else
            bar.lowHealthAlertBar:Hide()
            bar.lowHealthAlertBar:SetAlpha(1)
            SetStatusBarImmediateValue(bar.lowHealthAlertBar, 0)
        end
    end

    local incomingHealsVisible = config.showIncomingHeals == true or preview.incomingHeals == true
    local incomingHealAnchorTexture = nil
    if bar.incomingHealBar then
        HealthBar.ApplyEffectStyle(bar.incomingHealBar, config, "healthIncomingHealColor", HEALTH_EFFECTS.incomingHealColor, "healthIncomingHealTexture")
        if incomingHealsVisible then
            SetStatusBarSmoothRange(bar.incomingHealBar, 0, maxHealth)
            if preview.incomingHeals == true then
                SetStatusBarSmoothValue(bar.incomingHealBar, 18)
            else
                SetStatusBarSmoothValue(bar.incomingHealBar, EnsureNonNilNumber(GetNetHealingCalc():GetIncomingHeals()))
            end
            bar.incomingHealBar:Show()
            incomingHealAnchorTexture = bar.incomingHealBar:GetStatusBarTexture()
        else
            bar.incomingHealBar:Hide()
            SetStatusBarImmediateValue(bar.incomingHealBar, 0)
        end
    end

    if bar.absorbBar then
        HealthBar.LayoutForwardEffectBar(bar, bar.absorbBar, incomingHealAnchorTexture, true)
        HealthBar.ApplyEffectStyle(bar.absorbBar, config, "healthAbsorbColor", HEALTH_EFFECTS.absorbColor, "healthAbsorbTexture")
        HealthBar.ApplyEffectStyle(bar.absorbOverflowBar, config, "healthAbsorbColor", HEALTH_EFFECTS.absorbColor, "healthAbsorbTexture")
        if config.showAbsorbs == true or preview.absorbs == true then
            local missingHealthAbsorb
            local absorbOverflowing
            local overflowAbsorb
            if preview.absorbs == true then
                missingHealthAbsorb = 0
                absorbOverflowing = true
                overflowAbsorb = 28
            else
                HEALTH_EFFECTS.absorbMissingCalc:SetDamageAbsorbClampMode(
                    incomingHealsVisible
                        and Enum.UnitDamageAbsorbClampMode.MissingHealth
                        or Enum.UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals
                )
                HEALTH_EFFECTS.absorbMissingCalc:SetHealAbsorbMode(
                    incomingHealsVisible
                        and Enum.UnitHealAbsorbMode.ReducedByIncomingHeals
                        or Enum.UnitHealAbsorbMode.Total
                )
                UnitGetDetailedHealPrediction("player", nil, HEALTH_EFFECTS.absorbMissingCalc)
                missingHealthAbsorb, absorbOverflowing = HEALTH_EFFECTS.absorbMissingCalc:GetDamageAbsorbs()
                UnitGetDetailedHealPrediction("player", nil, HEALTH_EFFECTS.absorbOverflowCalc)
                overflowAbsorb = HEALTH_EFFECTS.absorbOverflowCalc:GetDamageAbsorbs()
            end

            SetStatusBarSmoothRange(bar.absorbBar, 0, maxHealth)
            SetStatusBarSmoothValue(bar.absorbBar, EnsureNonNilNumber(missingHealthAbsorb))
            bar.absorbBar:SetAlpha(1)
            bar.absorbBar:Show()
            if bar.absorbOverflowBar then
                SetStatusBarSmoothRange(bar.absorbOverflowBar, 0, maxHealth)
                SetStatusBarSmoothValue(bar.absorbOverflowBar, EnsureNonNilNumber(overflowAbsorb))
                HealthBar.SetEffectAlphaFromBoolean(bar.absorbOverflowBar, absorbOverflowing, 1, 0)
                bar.absorbOverflowBar:Show()
            end
        else
            bar.absorbBar:Hide()
            SetStatusBarImmediateValue(bar.absorbBar, 0)
            if bar.absorbOverflowBar then
                bar.absorbOverflowBar:Hide()
                SetStatusBarImmediateValue(bar.absorbOverflowBar, 0)
            end
        end
    end

    if bar.healAbsorbBar then
        HealthBar.ApplyEffectStyle(bar.healAbsorbBar, config, "healthHealAbsorbColor", HEALTH_EFFECTS.healAbsorbColor, "healthHealAbsorbTexture")
        if config.showHealAbsorbs == true or preview.healAbsorbs == true then
            SetStatusBarSmoothRange(bar.healAbsorbBar, 0, maxHealth)
            if preview.healAbsorbs == true then
                SetStatusBarSmoothValue(bar.healAbsorbBar, 22)
            else
                local healAbsorbCalc = incomingHealsVisible and GetNetHealingCalc() or GetStandaloneHealingCalc()
                SetStatusBarSmoothValue(bar.healAbsorbBar, EnsureNonNilNumber(healAbsorbCalc:GetHealAbsorbs()))
            end
            bar.healAbsorbBar:Show()
        else
            bar.healAbsorbBar:Hide()
            SetStatusBarImmediateValue(bar.healAbsorbBar, 0)
        end
    end
end

function HealthBar.BuildGradientCurve(config, opacityKey, opacityDefault, fullKey, fullDefault, halfKey, halfDefault, lowKey, lowDefault)
    local opacity = HealthBar.GetAlpha(config, opacityKey, opacityDefault)
    local full = HealthBar.GetColor(config, fullKey, fullDefault)
    local half = HealthBar.GetColor(config, halfKey, halfDefault)
    local low = HealthBar.GetColor(config, lowKey, lowDefault)
    local curve = C_CurveUtil.CreateColorCurve()
    curve:AddPoint(0.0, CreateColor(low[1], low[2], low[3], opacity))
    curve:AddPoint(0.5, CreateColor(half[1], half[2], half[3], opacity))
    curve:AddPoint(1.0, CreateColor(full[1], full[2], full[3], opacity))
    return curve
end

function HealthBar.BuildFillCurve(config)
    return HealthBar.BuildGradientCurve(
        config,
        "healthBarOpacity", RB.DEFAULT_HEALTH_BAR_OPACITY,
        "healthBarFullColor", RB.DEFAULT_HEALTH_BAR_FULL_COLOR,
        "healthBarHalfColor", RB.DEFAULT_HEALTH_BAR_HALF_COLOR,
        "healthBarLowColor", RB.DEFAULT_HEALTH_BAR_LOW_COLOR
    )
end

function HealthBar.BuildBackgroundCurve(config)
    return HealthBar.BuildGradientCurve(
        config,
        "healthBackgroundOpacity", RB.DEFAULT_HEALTH_BACKGROUND_OPACITY,
        "healthBackgroundFullColor", RB.DEFAULT_HEALTH_BACKGROUND_FULL_COLOR,
        "healthBackgroundHalfColor", RB.DEFAULT_HEALTH_BACKGROUND_HALF_COLOR,
        "healthBackgroundLowColor", RB.DEFAULT_HEALTH_BACKGROUND_LOW_COLOR
    )
end

function HealthBar.GetPreviewGradientColor(config, percent, opacityKey, opacityDefault, fullKey, fullDefault, halfKey, halfDefault, lowKey, lowDefault)
    percent = tonumber(percent) or 0.65
    if percent < 0 then
        percent = 0
    elseif percent > 1 then
        percent = 1
    end

    local opacity = HealthBar.GetAlpha(config, opacityKey, opacityDefault)
    local full = HealthBar.GetColor(config, fullKey, fullDefault)
    local half = HealthBar.GetColor(config, halfKey, halfDefault)
    local low = HealthBar.GetColor(config, lowKey, lowDefault)
    local fromColor = low
    local toColor = half
    local t = percent * 2

    if percent > 0.5 then
        fromColor = half
        toColor = full
        t = (percent - 0.5) * 2
    end

    return CreateColor(
        fromColor[1] + ((toColor[1] - fromColor[1]) * t),
        fromColor[2] + ((toColor[2] - fromColor[2]) * t),
        fromColor[3] + ((toColor[3] - fromColor[3]) * t),
        opacity
    )
end

function HealthBar.ApplyFillColor(bar, config, previewPercent)
    if not bar then return end

    local color
    if HealthBar.IsFillGradientEnabled(config) then
        if previewPercent then
            color = HealthBar.GetPreviewGradientColor(
                config, previewPercent,
                "healthBarOpacity", RB.DEFAULT_HEALTH_BAR_OPACITY,
                "healthBarFullColor", RB.DEFAULT_HEALTH_BAR_FULL_COLOR,
                "healthBarHalfColor", RB.DEFAULT_HEALTH_BAR_HALF_COLOR,
                "healthBarLowColor", RB.DEFAULT_HEALTH_BAR_LOW_COLOR
            )
        else
            color = UnitHealthPercent("player", true, bar._healthBarCurve)
        end
    else
        local opacity = HealthBar.GetAlpha(config, "healthBarOpacity", RB.DEFAULT_HEALTH_BAR_OPACITY)
        local static = HealthBar.GetColor(config, "healthBarColor", RB.DEFAULT_HEALTH_BAR_COLOR)
        color = CreateColor(static[1], static[2], static[3], opacity)
    end

    if type(color) == "table" and color.GetRGBA then
        local r, g, b, a = color:GetRGBA()
        bar:SetStatusBarColor(r, g, b, 1)
        local fillTexture = bar:GetStatusBarTexture()
        if fillTexture and fillTexture.SetAlpha then
            fillTexture:SetAlpha(a)
        end
        return
    end

    local r, g, b, a
    if type(color) == "table" then
        r = color.r or color[1]
        g = color.g or color[2]
        b = color.b or color[3]
        a = color.a or color[4]
    end

    if r and g and b then
        bar:SetStatusBarColor(r, g, b, 1)
        local fillTexture = bar:GetStatusBarTexture()
        if fillTexture and fillTexture.SetAlpha then
            fillTexture:SetAlpha(a ~= nil and a or HealthBar.GetAlpha(config, "healthBarOpacity", RB.DEFAULT_HEALTH_BAR_OPACITY))
        end
    end
end

function HealthBar.ApplyBackgroundColor(bar, config, previewPercent)
    if not bar or not bar.bg then return end

    local color
    if HealthBar.IsBackgroundGradientEnabled(config) then
        if previewPercent then
            color = HealthBar.GetPreviewGradientColor(
                config, previewPercent,
                "healthBackgroundOpacity", RB.DEFAULT_HEALTH_BACKGROUND_OPACITY,
                "healthBackgroundFullColor", RB.DEFAULT_HEALTH_BACKGROUND_FULL_COLOR,
                "healthBackgroundHalfColor", RB.DEFAULT_HEALTH_BACKGROUND_HALF_COLOR,
                "healthBackgroundLowColor", RB.DEFAULT_HEALTH_BACKGROUND_LOW_COLOR
            )
        else
            color = UnitHealthPercent("player", true, bar._healthBackgroundCurve)
        end
    else
        local opacity = HealthBar.GetAlpha(config, "healthBackgroundOpacity", RB.DEFAULT_HEALTH_BACKGROUND_OPACITY)
        local static = HealthBar.GetColor(config, "healthBackgroundColor", RB.DEFAULT_HEALTH_BACKGROUND_COLOR)
        color = CreateColor(static[1], static[2], static[3], opacity)
    end

    if type(color) == "table" and color.GetRGBA then
        bar.bg:SetVertexColor(color:GetRGBA())
        return
    end

    local r, g, b, a
    if type(color) == "table" then
        r = color.r or color[1]
        g = color.g or color[2]
        b = color.b or color[3]
        a = color.a or color[4]
    end

    if r and g and b then
        bar.bg:SetVertexColor(r, g, b, a ~= nil and a or HealthBar.GetAlpha(config, "healthBackgroundOpacity", RB.DEFAULT_HEALTH_BACKGROUND_OPACITY))
    end
end

function HealthBar.Update(bar, settings)
    if not settings then
        settings = GetResourceBarSettings()
    end

    local currentHealth = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    local maxHealthIsSecret = issecretvalue and issecretvalue(maxHealth)
    if not maxHealthIsSecret and (not maxHealth or maxHealth < 1) then
        maxHealth = 1
    end

    SetStatusBarSmoothRange(bar, 0, maxHealth)
    SetStatusBarSmoothValue(bar, currentHealth)
    local config = HealthBar.GetConfig(settings)
    HealthBar.ApplyFillColor(bar, config)
    HealthBar.ApplyBackgroundColor(bar, config)
    HealthBar.UpdateEffectBars(bar, config, maxHealth)

    if bar.text and bar.text:IsShown() then
        local textFormat = bar._textFormat
        if textFormat == "current" then
            bar.text:SetFormattedText("%s", AbbreviateNumbers(currentHealth))
        elseif textFormat == "current_max" then
            bar.text:SetFormattedText("%s / %s", AbbreviateNumbers(currentHealth), AbbreviateNumbers(maxHealth))
        elseif textFormat == "current_percent" then
            bar.text:SetFormattedText(
                "%s | %.0f%%",
                AbbreviateNumbers(currentHealth),
                UnitHealthPercent("player", true, PERCENT_SCALE_CURVE)
            )
        elseif textFormat == "current_percent_no_sign" then
            bar.text:SetFormattedText(
                "%s | %.0f",
                AbbreviateNumbers(currentHealth),
                UnitHealthPercent("player", true, PERCENT_SCALE_CURVE)
            )
        elseif textFormat == "percent_no_sign" then
            bar.text:SetFormattedText("%.0f", UnitHealthPercent("player", true, PERCENT_SCALE_CURVE))
        else
            bar.text:SetFormattedText("%.0f%%", UnitHealthPercent("player", true, PERCENT_SCALE_CURVE))
        end
    end

end

function HealthBar.Style(bar, settings)
    local resourceConfig = HealthBar.GetConfig(settings)
    local texName = GetResourceDisplayValue(settings, "barTexture", "Solid")
    local isVertical = IsVerticalResourceLayout(settings)
    local reverseFill = IsVerticalFillReversed(settings)
    local texture = CooldownCompanion:FetchStatusBar(texName == "blizzard_class" and "Blizzard" or texName)

    bar:SetStatusBarTexture(texture)
    bar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill(isVertical and reverseFill or false)
    bar._isVertical = isVertical
    bar._reverseFill = reverseFill
    bar._healthBarCurve = HealthBar.BuildFillCurve(resourceConfig)
    bar._healthBackgroundCurve = HealthBar.BuildBackgroundCurve(resourceConfig)
    bar._lowHealthAlertCurve = HealthBar.BuildLowHealthAlertCurve(resourceConfig)

    HealthBar.ApplyFillColor(bar, resourceConfig)
    HealthBar.EnsureEffectBars(bar)

    if bar.brightnessOverlay then
        bar.brightnessOverlay:Hide()
    end

    bar.bg:SetTexture(texture)
    HealthBar.SetBackgroundAnchors(bar)
    HealthBar.ApplyBackgroundColor(bar, resourceConfig)

    local borderStyle = GetResourceDisplayValue(settings, "borderStyle", "pixel")
    local borderColor = GetResourceDisplayValue(settings, "borderColor", { 0, 0, 0, 1 })
    local borderSize = GetResourceDisplayValue(settings, "borderSize", 1)
    local borderRenderMode = GetResourceDisplayValue(settings, "borderRenderMode", ST.BORDER_RENDER_MODE_CUSTOM)

    if borderStyle == "pixel" then
        ApplyPixelBorders(bar.borders, bar, borderColor, borderSize, borderRenderMode)
    else
        HidePixelBorders(bar.borders)
    end
    HealthBar.LayoutEffectBars(bar, borderStyle, borderSize, borderRenderMode, resourceConfig)

    local textFormat = resourceConfig and resourceConfig.textFormat or "percent"
    if textFormat ~= "percent"
        and textFormat ~= "percent_no_sign"
        and textFormat ~= "current"
        and textFormat ~= "current_max"
        and textFormat ~= "current_percent"
        and textFormat ~= "current_percent_no_sign" then
        textFormat = "percent"
    end
    local textFontName = resourceConfig and resourceConfig.textFont or DEFAULT_RESOURCE_TEXT_FONT
    local textSize = tonumber(resourceConfig and resourceConfig.textFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
    local textOutline = resourceConfig and resourceConfig.textFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE
    local textColor = resourceConfig and resourceConfig.textFontColor or DEFAULT_RESOURCE_TEXT_COLOR
    if type(textColor) ~= "table" or textColor[1] == nil or textColor[2] == nil or textColor[3] == nil then
        textColor = DEFAULT_RESOURCE_TEXT_COLOR
    end

    bar.text:SetFont(CooldownCompanion:FetchFont(textFontName), textSize, textOutline)
    bar.text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] ~= nil and textColor[4] or 1)
    bar.text:ClearAllPoints()
    bar.text:SetPoint(
        resourceConfig and resourceConfig.textAnchor or "CENTER",
        resourceConfig and resourceConfig.textXOffset or 0,
        resourceConfig and resourceConfig.textYOffset or 0
    )
    bar.text:SetShown(resourceConfig and resourceConfig.showText == true)
    bar._textFormat = textFormat
end

RB.HealthBar = HealthBar
RB.HealthEffects = HEALTH_EFFECTS
RB.StyleHealthBar = HealthBar.Style
