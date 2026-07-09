--[[
    CooldownCompanion - ResourceBarVisuals
    Visual layer components: frame factories, layout, borders, overlays,
    indicators, and tick markers. No mutable runtime state.

    All functions are added to ST._RB so consuming files can alias them to
    locals at load time.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSegmentedValue = ST.SetStatusBarSegmentedValue

local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_sin = math.sin
local math_pi = math.pi
local issecretvalue = issecretvalue
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local MAX_STACKS_PIXEL_GLOW_KEY = "CooldownCompanionMaxStacks"

-- Import from ResourceBarConstants & ResourceBarHelpers
local RB = ST._RB
local POWER_ATLAS_INFO = RB.POWER_ATLAS_INFO
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = RB.DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
local DEFAULT_CUSTOM_AURA_MAX_COLOR = RB.DEFAULT_CUSTOM_AURA_MAX_COLOR
local DEFAULT_CONTINUOUS_TICK_COLOR = RB.DEFAULT_CONTINUOUS_TICK_COLOR
local RESOURCE_MAELSTROM_WEAPON = RB.RESOURCE_MAELSTROM_WEAPON
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local IsVerticalResourceLayout = RB.IsVerticalResourceLayout
local IsVerticalFillReversed = RB.IsVerticalFillReversed
local GetCurrentSpecID = RB.GetCurrentSpecID
local GetResourceColors = RB.GetResourceColors
local GetContinuousTickEntriesConfig = RB.GetContinuousTickEntriesConfig
local GetSpecResourceDisplayProfile = RB.GetSpecResourceDisplayProfile
local GetSafeRGBColor = RB.GetSafeRGBColor
local SupportsResourceAuraStackMode = RB.SupportsResourceAuraStackMode
local GetResolvedResourceAuraUnit = RB.GetResolvedResourceAuraUnit

local function GetResourceDisplayStyle(settings)
    return GetSpecResourceDisplayProfile and GetSpecResourceDisplayProfile(settings) or settings
end

local function ClampSegmentGapToFit(totalSize, segmentCount, gap)
    gap = tonumber(gap) or 0
    if gap <= 0 or segmentCount <= 1 then
        return 0
    end

    local maxGap = (totalSize - segmentCount) / (segmentCount - 1)
    if maxGap < 0 then
        maxGap = 0
    end
    return math_min(gap, maxGap)
end

------------------------------------------------------------------------
-- Resource Aura Overlay
------------------------------------------------------------------------

local function GetResourceAuraEntry(resource, specID)
    if type(resource) ~= "table" or not specID then
        return nil
    end

    local entries = resource.auraOverlayEntries
    if type(entries) ~= "table" then
        return nil
    end

    local direct = entries[specID]
    if type(direct) == "table" then
        return direct
    end

    local alternate = entries[tostring(specID)]
    if type(alternate) == "table" then
        return alternate
    end

    return nil
end

local function GetLegacyResourceAuraEntry(resource)
    if type(resource) ~= "table" then
        return nil
    end

    if resource.auraColorSpellID ~= nil
        or resource.auraActiveColor ~= nil
        or resource.auraColorTrackingMode ~= nil
        or resource.auraColorMaxStacks ~= nil then
        return resource
    end

    return nil
end

local function GetActiveResourceAuraEntry(resource)
    if type(resource) ~= "table" then
        return nil
    end

    local hasEntryTable = type(resource.auraOverlayEntries) == "table" and next(resource.auraOverlayEntries) ~= nil
    local specID = GetCurrentSpecID()
    if specID then
        local entry = GetResourceAuraEntry(resource, specID)
        if type(entry) == "table" then
            return entry
        end
        if hasEntryTable then
            return nil
        end
    elseif hasEntryTable then
        return nil
    end

    return GetLegacyResourceAuraEntry(resource)
end

local function GetResourceAuraTrackingMode(resourceEntry)
    if type(resourceEntry) ~= "table" then
        return "active"
    end
    if resourceEntry.auraColorTrackingMode == "stacks" or resourceEntry.auraColorTrackingMode == "active" then
        return resourceEntry.auraColorTrackingMode
    end
    local configured = tonumber(resourceEntry.auraColorMaxStacks)
    if configured and configured >= 2 then
        return "stacks"
    end
    return "active"
end

local function GetResourceAuraConfiguredMaxStacks(powerType, settings)
    if not settings or not settings.resources then return nil end
    local resource = settings.resources[powerType]
    if not resource then return nil end
    local entry = GetActiveResourceAuraEntry(resource)
    if not entry then return nil end
    if GetResourceAuraTrackingMode(entry) ~= "stacks" then return nil end
    local configured = tonumber(entry.auraColorMaxStacks)
    if not configured then return nil end
    configured = math_floor(configured)
    if configured <= 1 then return nil end
    if configured > 99 then configured = 99 end
    return configured
end

local function IsResourceAuraOverlayEnabled(resource)
    if type(resource) ~= "table" then
        return false
    end
    local specID = GetCurrentSpecID()
    if specID then
        local specData = type(resource.specOverrides) == "table"
            and (resource.specOverrides[specID] or resource.specOverrides[tostring(specID)])
            or nil
        if type(specData) == "table" and type(specData.auraOverlayEnabled) == "boolean" then
            return specData.auraOverlayEnabled
        end
        if resource.auraOverlayEnabled == false then
            return false
        end
        return type(GetResourceAuraEntry(resource, specID)) == "table"
    end

    if type(resource.auraOverlayEnabled) == "boolean" then
        return resource.auraOverlayEnabled
    end
    if type(resource.auraOverlayEntries) == "table" then
        for _, entry in pairs(resource.auraOverlayEntries) do
            if type(entry) == "table" then
                return true
            end
        end
    end
    local auraSpellID = tonumber(resource.auraColorSpellID)
    return auraSpellID and auraSpellID > 0 or false
end

local function GetResourceAuraState(powerType, settings, auraActiveCache)
    -- 12.1 demolition: aura reads removed. Resource aura recolor and aura-stack
    -- segments stay inert (base colors) until the AuraContainer rebuild.
    return nil, nil, false
end

local function HideResourceAuraStackSegments(holder)
    if not holder or not holder.auraStackSegments then return end
    for _, seg in ipairs(holder.auraStackSegments) do
        SetStatusBarImmediateValue(seg, 0)
        seg:Hide()
    end
end

local function GetResourceAuraStackLayoutInputs(holder, settings, orientationOverride, reverseFillOverride)
    local style = GetResourceDisplayStyle(settings)
    local barTextureName = ST.GetEffectiveBarTextureName(style and style.barTexture or "Solid")
    local borderStyle = style and style.borderStyle or "pixel"
    local borderSize = style and style.borderSize or 1
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local isVertical
    if orientationOverride == "vertical" then
        isVertical = true
    elseif orientationOverride == "horizontal" then
        isVertical = false
    else
        isVertical = IsVerticalResourceLayout(settings)
    end
    local reverseFill = false
    if reverseFillOverride ~= nil then
        reverseFill = reverseFillOverride == true
    elseif isVertical then
        reverseFill = IsVerticalFillReversed(settings)
    end

    local baseSeg = holder and holder.segments and holder.segments[1]
    local baseWidth = baseSeg and baseSeg:GetWidth() or 0
    local baseHeight = baseSeg and baseSeg:GetHeight() or 0
    local baseFrameLevel = baseSeg and baseSeg:GetFrameLevel() or 0

    return barTextureName, borderStyle, borderSize, borderRenderMode, isVertical, reverseFill, baseWidth, baseHeight, baseFrameLevel
end

local function UpdateResourceAuraStackLayoutState(holder, count, barTextureName, borderStyle, borderSize, borderRenderMode, isVertical, reverseFill, baseWidth, baseHeight, baseFrameLevel)
    holder._auraStackLayoutCount = count
    holder._auraStackLayoutTexture = barTextureName
    holder._auraStackLayoutBorderStyle = borderStyle
    holder._auraStackLayoutBorderSize = borderSize
    holder._auraStackLayoutBorderRenderMode = borderRenderMode
    holder._auraStackLayoutVertical = isVertical
    holder._auraStackLayoutReverseFill = reverseFill
    holder._auraStackLayoutBaseWidth = baseWidth
    holder._auraStackLayoutBaseHeight = baseHeight
    holder._auraStackLayoutBaseFrameLevel = baseFrameLevel
end

local function ResourceAuraStackLayoutChanged(holder, settings)
    local count = holder.auraStackSegments and #holder.auraStackSegments or 0
    local barTextureName, borderStyle, borderSize, borderRenderMode, isVertical, reverseFill, baseWidth, baseHeight, baseFrameLevel =
        GetResourceAuraStackLayoutInputs(holder, settings)

    if holder._auraStackLayoutCount ~= count
        or holder._auraStackLayoutTexture ~= barTextureName
        or holder._auraStackLayoutBorderStyle ~= borderStyle
        or holder._auraStackLayoutBorderSize ~= borderSize
        or holder._auraStackLayoutBorderRenderMode ~= borderRenderMode
        or holder._auraStackLayoutVertical ~= isVertical
        or holder._auraStackLayoutReverseFill ~= reverseFill
        or holder._auraStackLayoutBaseWidth ~= baseWidth
        or holder._auraStackLayoutBaseHeight ~= baseHeight
        or holder._auraStackLayoutBaseFrameLevel ~= baseFrameLevel then
        return true
    end

    return false
end

local function LayoutResourceAuraStackSegments(holder, settings, orientationOverride, reverseFillOverride)
    if not holder or not holder.auraStackSegments or not holder.segments then return end
    local count = #holder.auraStackSegments
    local barTextureName, borderStyle, borderSize, borderRenderMode, isVertical, reverseFill, baseWidth, baseHeight, baseFrameLevel =
        GetResourceAuraStackLayoutInputs(holder, settings, orientationOverride, reverseFillOverride)
    local barTexture = CooldownCompanion:FetchStatusBar(barTextureName)

    for i, auraSeg in ipairs(holder.auraStackSegments) do
        local baseSeg = holder.segments[i]
        if baseSeg then
            local inset = (borderStyle == "pixel") and ST.GetEffectiveBorderLayoutSize(baseSeg, borderSize, borderRenderMode) or 0
            if inset < 0 then inset = 0 end

            auraSeg:ClearAllPoints()
            if isVertical then
                local usableWidth = baseSeg:GetWidth() - (inset * 2)
                if usableWidth < 1 then usableWidth = 1 end
                local laneWidth = math_floor((usableWidth * 0.5) + 0.5)
                laneWidth = math_max(1, math_min(usableWidth, laneWidth))
                auraSeg:SetPoint("BOTTOMLEFT", baseSeg, "BOTTOMLEFT", inset, inset)
                auraSeg:SetPoint("TOPLEFT", baseSeg, "TOPLEFT", inset, -inset)
                auraSeg:SetWidth(laneWidth)
            else
                local usableHeight = baseSeg:GetHeight() - (inset * 2)
                if usableHeight < 1 then usableHeight = 1 end
                local laneHeight = math_floor((usableHeight * 0.5) + 0.5)
                laneHeight = math_max(1, math_min(usableHeight, laneHeight))
                auraSeg:SetPoint("BOTTOMLEFT", baseSeg, "BOTTOMLEFT", inset, inset)
                auraSeg:SetPoint("BOTTOMRIGHT", baseSeg, "BOTTOMRIGHT", -inset, inset)
                auraSeg:SetHeight(laneHeight)
            end
            auraSeg:SetStatusBarTexture(barTexture)
            auraSeg:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
            auraSeg:SetReverseFill(reverseFill)
            auraSeg:SetFrameLevel(baseSeg:GetFrameLevel() + 4)
        else
            auraSeg:Hide()
        end
    end

    UpdateResourceAuraStackLayoutState(holder, count, barTextureName, borderStyle, borderSize, borderRenderMode, isVertical, reverseFill, baseWidth, baseHeight, baseFrameLevel)
end

local function EnsureResourceAuraStackSegments(holder, settings)
    if not holder or not holder.segments then return nil end
    local count = #holder.segments
    if count == 0 then return nil end

    if not holder.auraStackSegments or #holder.auraStackSegments ~= count then
        if holder.auraStackSegments then
            for _, oldSeg in ipairs(holder.auraStackSegments) do
                SetStatusBarImmediateValue(oldSeg, 0)
                oldSeg:ClearAllPoints()
                oldSeg:Hide()
            end
        end
        holder.auraStackSegments = {}
        for i = 1, count do
            local seg = CreateFrame("StatusBar", nil, holder)
            seg:SetMinMaxValues(0, 1)
            SetStatusBarImmediateValue(seg, 0)
            seg:Hide()
            holder.auraStackSegments[i] = seg
        end
        holder._auraStackLayoutCount = nil
    end

    if ResourceAuraStackLayoutChanged(holder, settings) then
        LayoutResourceAuraStackSegments(holder, settings)
    end
    return holder.auraStackSegments
end

local function ApplyResourceAuraStackSegments(holder, settings, stackValue, maxStacks, color)
    local auraSegments = EnsureResourceAuraStackSegments(holder, settings)
    if not auraSegments then return end

    local segmentedSmoothing = RB.GetResourceSegmentedSmoothing(settings)
    local count = #auraSegments
    for i = 1, count do
        local seg = auraSegments[i]
        local segMin = ((i - 1) * maxStacks) / count
        local segMax = (i * maxStacks) / count
        SetStatusBarSmoothRange(seg, segMin, segMax)
        SetStatusBarSegmentedValue(seg, stackValue, segmentedSmoothing)
        seg:SetAlpha(1)
        seg:SetStatusBarColor(color[1], color[2], color[3], 1)
        seg:Show()
    end
end

local function ClearResourceAuraVisuals(frame)
    if not frame then return end
    HideResourceAuraStackSegments(frame)
end

------------------------------------------------------------------------
-- Continuous Tick & Fill
------------------------------------------------------------------------

local function EnsureContinuousTickMarker(bar, index)
    if not bar then return nil end
    if type(bar.tickMarkers) ~= "table" then
        bar.tickMarkers = {}
        if bar.tickMarker then
            bar.tickMarkers[1] = bar.tickMarker
        end
    end
    if not bar.tickMarkers[index] then
        bar.tickMarkers[index] = bar:CreateTexture(nil, "OVERLAY", nil, 6)
        bar.tickMarkers[index]:SetColorTexture(1, 0.84, 0, 1)
        bar.tickMarkers[index]:Hide()
    end
    if index == 1 then
        bar.tickMarker = bar.tickMarkers[index]
    end
    return bar.tickMarkers[index]
end

local function HideContinuousTickMarkers(bar, startIndex)
    if not bar then return end
    startIndex = startIndex or 1
    if type(bar.tickMarkers) == "table" then
        for index = startIndex, #bar.tickMarkers do
            bar.tickMarkers[index]:Hide()
        end
    elseif startIndex <= 1 and bar.tickMarker then
        bar.tickMarker:Hide()
    end
end

local function UpdateContinuousTickMarker(bar, powerType, settings, maxPower, maxPowerIsSecret)
    if not bar then return end

    local enabled, mode, entries, tickWidth, combatOnly = GetContinuousTickEntriesConfig(powerType, settings)
    if not enabled then
        HideContinuousTickMarkers(bar)
        return
    end

    if combatOnly and not InCombatLockdown() then
        HideContinuousTickMarkers(bar)
        return
    end

    if mode == "absolute" then
        if maxPowerIsSecret then
            HideContinuousTickMarkers(bar)
            return
        end
        if issecretvalue and issecretvalue(maxPower) then
            HideContinuousTickMarkers(bar)
            return
        end
        if type(maxPower) ~= "number" or maxPower <= 0 then
            HideContinuousTickMarkers(bar)
            return
        end
    end

    local style = GetResourceDisplayStyle(settings)
    local borderStyle = style and style.borderStyle or "pixel"
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local borderSize = (borderStyle == "pixel") and ST.GetEffectiveBorderLayoutSize(bar, style and style.borderSize or 1, borderRenderMode) or 0
    local width = bar:GetWidth() or 0
    local height = bar:GetHeight() or 0
    if width <= 0 or height <= 0 then
        HideContinuousTickMarkers(bar)
        return
    end

    local shownCount = 0
    local halfTick = tickWidth / 2

    for index, entry in ipairs(entries) do
        local ratio = mode == "absolute" and (entry.value / maxPower) or (entry.value / 100)
        if ratio < 0 then
            ratio = 0
        elseif ratio > 1 then
            ratio = 1
        end

        local marker = EnsureContinuousTickMarker(bar, index)
        local tickColor = entry.color or DEFAULT_CONTINUOUS_TICK_COLOR
        marker:SetColorTexture(tickColor[1], tickColor[2], tickColor[3], tickColor[4] ~= nil and tickColor[4] or 1)
        marker:ClearAllPoints()
        if bar._isVertical then
            local usableHeight = math_max(height - (borderSize * 2), 1)
            local localRatio = bar._reverseFill and (1 - ratio) or ratio
            local y = borderSize + (usableHeight * localRatio)
            local yMax = height - borderSize
            if y > yMax then y = yMax end
            if y < borderSize then y = borderSize end
            marker:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", borderSize, y - halfTick)
            marker:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -borderSize, y - halfTick)
            marker:SetHeight(tickWidth)
        else
            local usableWidth = math_max(width - (borderSize * 2), 1)
            local x = borderSize + (usableWidth * ratio)
            local xMax = width - borderSize
            if x > xMax then x = xMax end
            if x < borderSize then x = borderSize end
            marker:SetPoint("TOPLEFT", bar, "TOPLEFT", x - halfTick, -borderSize)
            marker:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x - halfTick, borderSize)
            marker:SetWidth(tickWidth)
        end
        marker:Show()
        shownCount = index
    end

    HideContinuousTickMarkers(bar, shownCount + 1)
end

local function ApplyContinuousFillColor(bar, powerType, settings, overrideColor)
    if not bar or not settings then return end

    local style = GetResourceDisplayStyle(settings)
    local texName = bar._effectiveBarTextureName or ST.GetEffectiveBarTextureName(style and style.barTexture or "Solid")
    local atlasInfo = (texName == "blizzard_class") and POWER_ATLAS_INFO[powerType] or nil
    if atlasInfo then
        if overrideColor then
            bar:SetStatusBarColor(overrideColor[1], overrideColor[2], overrideColor[3], 1)
            bar.brightnessOverlay:Hide()
            return
        end

        local brightness = style and style.classBarBrightness or 1.3
        bar:SetStatusBarColor(1, 1, 1, 1)
        if brightness > 1.0 then
            bar.brightnessOverlay:SetAlpha(brightness - 1.0)
            bar.brightnessOverlay:Show()
        elseif brightness < 1.0 then
            bar:SetStatusBarColor(brightness, brightness, brightness, 1)
            bar.brightnessOverlay:Hide()
        else
            bar.brightnessOverlay:Hide()
        end
        return
    end

    local color = overrideColor or GetResourceColors(powerType, settings)
    bar:SetStatusBarColor(color[1], color[2], color[3], 1)
    bar.brightnessOverlay:Hide()
end

------------------------------------------------------------------------
-- Pixel Borders
------------------------------------------------------------------------

local function CreatePixelBorders(parent)
    return ST.CreateBorderTextureSet(parent, "OVERLAY", 7)
end

local function ApplyPixelBorders(borders, parent, color, size, renderMode)
    ST.ApplyBorderTextures(borders, parent, color, size, ST.GetEffectiveBorderRenderMode(renderMode, nil, size))
end

local function HidePixelBorders(borders)
    ST.HideBorderTextures(borders)
end

------------------------------------------------------------------------
-- Max Stacks & Threshold Overlays
------------------------------------------------------------------------

local function IsCustomAuraMaxThresholdEnabled(cabConfig)
    return cabConfig and cabConfig.thresholdColorEnabled == true and cabConfig.trackingMode ~= "active"
end

local function GetCustomAuraMaxThresholdColor(cabConfig)
    if cabConfig and cabConfig.thresholdMaxColor then
        return cabConfig.thresholdMaxColor
    end
    return DEFAULT_CUSTOM_AURA_MAX_COLOR
end

local function SetCustomAuraMaxThresholdRange(bar, maxStacks)
    if not bar then return end
    local safeMax = maxStacks or 1
    if safeMax < 1 then safeMax = 1 end
    bar:SetMinMaxValues(safeMax - 1, safeMax)
end

------------------------------------------------------------------------
-- Max Stacks Indicator (StatusBar-based, secret-safe)
-- Uses SetMinMaxValues(maxStacks-1, maxStacks) + SetValue(applications):
-- below max → fill=0% (invisible), at max → fill=100% (visible).
------------------------------------------------------------------------

local function IsMaxStacksPixelGlowAvailable()
    return LCG ~= nil and LCG.PixelGlow_Start ~= nil and LCG.PixelGlow_Stop ~= nil
end

local function GetMaxStacksFrameTreatmentStyle(cabConfig)
    local style = cabConfig and cabConfig.maxStacksGlowStyle or "solidBorder"
    if style == "none" or style == "pulsingOverlay" then
        return "none"
    elseif style == "pixelGlow" then
        return IsMaxStacksPixelGlowAvailable() and "pixelGlow" or "solidBorder"
    elseif style == "solidBorder" or style == "pulsingBorder" then
        return style
    end
    return "solidBorder"
end

local function IsMaxStacksLegacyOverlay(cabConfig)
    return cabConfig and cabConfig.maxStacksGlowStyle == "pulsingOverlay"
end

local function MaxStacksColorShiftEnabled(cabConfig)
    if not cabConfig then return false end
    if cabConfig.maxStacksBarColorShiftEnabled ~= nil then
        return cabConfig.maxStacksBarColorShiftEnabled == true
    end
    return IsMaxStacksLegacyOverlay(cabConfig)
end

local function HasMaxStacksBarEffects(cabConfig)
    return cabConfig and (
        cabConfig.maxStacksBarPulseEnabled == true
        or MaxStacksColorShiftEnabled(cabConfig)
    ) or false
end

local function IsCustomAuraMaxBarEffectEnabled(cabConfig)
    return cabConfig
        and cabConfig.trackingMode ~= "active"
        and cabConfig.maxStacksGlowEnabled == true
        and HasMaxStacksBarEffects(cabConfig)
end

local function CopyColorWithAlpha(color, alpha)
    color = color or DEFAULT_CUSTOM_AURA_MAX_COLOR
    return {color[1] or 1, color[2] or 0.84, color[3] or 0, alpha}
end

local function GetCustomAuraMaxBarEffectColor(cabConfig)
    local color = cabConfig and cabConfig.maxStacksGlowColor or DEFAULT_CUSTOM_AURA_MAX_COLOR
    if IsCustomAuraMaxThresholdEnabled(cabConfig) then
        color = GetCustomAuraMaxThresholdColor(cabConfig)
    end
    if IsMaxStacksLegacyOverlay(cabConfig) and cabConfig.maxStacksBarColorShiftEnabled == nil then
        return CopyColorWithAlpha(color, 0)
    end
    return color
end

local function GetMaxStacksBarEffectShiftColor(cabConfig)
    if cabConfig and cabConfig.maxStacksBarColorShiftColor then
        return cabConfig.maxStacksBarColorShiftColor
    elseif IsMaxStacksLegacyOverlay(cabConfig) then
        return cabConfig.maxStacksGlowColor or DEFAULT_CUSTOM_AURA_MAX_COLOR
    end
    return {1, 1, 1, 1}
end

local function MaxStacksPixelFrequency(speed)
    speed = tonumber(speed) or 50
    if speed < 10 then
        speed = 50
    end
    return math_max(speed, 1) / 120
end

local function LayoutWholeBarFrame(frameToLayout, frame, borderStyle, borderSize, borderRenderMode)
    frameToLayout:ClearAllPoints()
    if borderStyle == "pixel" then
        local inset = ST.GetEffectiveBorderLayoutSize(frame, borderSize, borderRenderMode)
        frameToLayout:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        frameToLayout:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    else
        frameToLayout:SetAllPoints(frame)
    end
end

local function EnsureMaxStacksIndicator(barInfo)
    if barInfo._maxStacksIndicator then return barInfo._maxStacksIndicator end
    local indicator = CreateFrame("StatusBar", nil, barInfo.frame)
    indicator:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    indicator:EnableMouse(false)
    indicator:Show()
    barInfo._maxStacksIndicator = indicator
    return indicator
end

local function StopMaxStacksPixelGlow(indicator)
    if indicator and indicator._maxStacksPixelGlowTarget then
        if IsMaxStacksPixelGlowAvailable() then
            LCG.PixelGlow_Stop(indicator._maxStacksPixelGlowTarget, MAX_STACKS_PIXEL_GLOW_KEY)
        end
        indicator._maxStacksPixelGlowTarget = nil
    end
end

local function EnsureMaxStacksPixelGlowTarget(indicator)
    local clip = indicator._maxStacksPixelGlowClip
    if not clip then
        clip = CreateFrame("Frame", nil, indicator)
        clip:SetClipsChildren(true)
        clip:EnableMouse(false)
        indicator._maxStacksPixelGlowClip = clip
    end

    local target = indicator._maxStacksPixelGlowFrame
    if not target then
        target = CreateFrame("Frame", nil, clip)
        target:EnableMouse(false)
        indicator._maxStacksPixelGlowFrame = target
    end

    return clip, target
end

local function ConfigureMaxStacksPixelGlow(indicator, cabConfig)
    if not IsMaxStacksPixelGlowAvailable() then
        StopMaxStacksPixelGlow(indicator)
        if indicator then
            indicator._maxStacksPixelGlowConfig = nil
        end
        return
    end

    local fillTexture = indicator:GetStatusBarTexture()
    if not fillTexture then
        StopMaxStacksPixelGlow(indicator)
        indicator._maxStacksPixelGlowConfig = nil
        return
    end

    indicator._maxStacksPixelGlowConfig = cabConfig

    local clip, target = EnsureMaxStacksPixelGlowTarget(indicator)
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", fillTexture, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", fillTexture, "BOTTOMRIGHT", 0, 0)
    clip:SetFrameLevel(indicator:GetFrameLevel() + 1)
    clip:Show()

    target:ClearAllPoints()
    target:SetAllPoints(indicator)
    target:SetFrameLevel(clip:GetFrameLevel() + 1)
    target:Show()

    StopMaxStacksPixelGlow(indicator)
    local color = cabConfig.maxStacksGlowColor or {1, 0.84, 0, 0.9}
    LCG.PixelGlow_Start(
        target,
        color,
        cabConfig.maxStacksGlowLines or 8,
        MaxStacksPixelFrequency(cabConfig.maxStacksGlowSpeed),
        cabConfig.maxStacksGlowSize or 8,
        cabConfig.maxStacksGlowThickness or 4,
        0,
        0,
        false,
        MAX_STACKS_PIXEL_GLOW_KEY,
        1
    )
    indicator._maxStacksPixelGlowTarget = target
end

local function ClearMaxStacksFrameTreatment(barInfo)
    local indicator = barInfo and barInfo._maxStacksIndicator
    if not indicator then return end
    StopMaxStacksPixelGlow(indicator)
    indicator._maxStacksFrameTreatmentStyle = nil
    indicator._maxStacksPixelGlowConfig = nil
    indicator._maxStacksPulseSuspended = nil
    indicator._maxStacksIndicatorActive = nil
    if indicator._maxStacksPixelGlowClip then
        indicator._maxStacksPixelGlowClip:Hide()
    end
    indicator:Hide()
    if indicator._pulseAG then
        indicator._pulseAG:Stop()
    end
    indicator:SetAlpha(1)
    SetStatusBarImmediateValue(indicator, 0)
end

local function SetMaxStacksIndicatorActive(barInfo, active)
    local indicator = barInfo and barInfo._maxStacksIndicator
    if not indicator then return end
    local style = indicator._maxStacksFrameTreatmentStyle
    active = active == true

    if active then
        if style ~= "pixelGlow" and style ~= "solidBorder" and style ~= "pulsingBorder" then
            return
        end
        if indicator._maxStacksIndicatorActive == true then
            if style ~= "pixelGlow" or indicator._maxStacksPixelGlowTarget then
                return
            end
        end
        indicator._maxStacksIndicatorActive = true
        indicator:Show()
        if style == "pixelGlow" then
            if indicator._maxStacksPixelGlowConfig and not indicator._maxStacksPixelGlowTarget then
                ConfigureMaxStacksPixelGlow(indicator, indicator._maxStacksPixelGlowConfig)
            elseif indicator._maxStacksPixelGlowClip then
                indicator._maxStacksPixelGlowClip:Show()
                if indicator._maxStacksPixelGlowFrame then
                    indicator._maxStacksPixelGlowFrame:Show()
                end
            end
        elseif style == "pulsingBorder"
            and indicator._maxStacksPulseSuspended
            and indicator._pulseAG then
            indicator._maxStacksPulseSuspended = nil
            indicator._pulseAG:Play()
        end
        return
    end

    if indicator._maxStacksIndicatorActive == false then
        return
    end
    indicator._maxStacksIndicatorActive = false
    SetStatusBarImmediateValue(indicator, 0)
    if style == "pixelGlow" then
        StopMaxStacksPixelGlow(indicator)
        if indicator._maxStacksPixelGlowClip then
            indicator._maxStacksPixelGlowClip:Hide()
        end
        if indicator._maxStacksPixelGlowFrame then
            indicator._maxStacksPixelGlowFrame:Hide()
        end
    elseif style == "pulsingBorder" and indicator._pulseAG then
        indicator._pulseAG:Stop()
        indicator._maxStacksPulseSuspended = true
    end
    indicator:Hide()
end

local function AnimateMaxStacksBarEffect(target)
    if not target then return end

    local pulseActive = target._maxStacksBarEffectPulseActive == true
    local colorShiftActive = target._maxStacksBarEffectColorShiftActive == true
    if not pulseActive and not colorShiftActive then
        target:SetScript("OnUpdate", nil)
        return
    end

    local now = GetTime()
    local fillTexture = target.GetStatusBarTexture and target:GetStatusBarTexture()
    if pulseActive then
        local speed = target._maxStacksBarEffectPulseSpeed or 0.5
        if fillTexture and fillTexture.SetAlpha then
            fillTexture:SetAlpha(0.6 + 0.4 * math_sin(now * 2 * math_pi / speed))
        end
    elseif fillTexture and fillTexture.SetAlpha then
        fillTexture:SetAlpha(1)
    end

    if colorShiftActive then
        local base = target._maxStacksBarEffectBaseColor
        local shift = target._maxStacksBarEffectShiftColor
        if base and shift then
            local speed = target._maxStacksBarEffectShiftSpeed or 0.5
            local t = 0.5 + 0.5 * math_sin(now * 2 * math_pi / speed)
            local baseAlpha = base[4] or 1
            target:SetStatusBarColor(
                base[1] + (shift[1] - base[1]) * t,
                base[2] + (shift[2] - base[2]) * t,
                base[3] + (shift[3] - base[3]) * t,
                baseAlpha + ((shift[4] or 1) - baseAlpha) * t
            )
        else
            target._maxStacksBarEffectColorShiftActive = nil
        end
    end
end

local function ClearCustomAuraMaxBarEffects(target, color)
    if not target then return end
    target:SetScript("OnUpdate", nil)
    target._maxStacksBarEffectPulseActive = nil
    target._maxStacksBarEffectColorShiftActive = nil
    target._maxStacksBarEffectBaseColor = nil
    target._maxStacksBarEffectShiftColor = nil
    target._maxStacksBarEffectPulseSpeed = nil
    target._maxStacksBarEffectShiftSpeed = nil
    local fillTexture = target.GetStatusBarTexture and target:GetStatusBarTexture()
    if fillTexture and fillTexture.SetAlpha then
        fillTexture:SetAlpha(1)
    end
    target:SetAlpha(1)
    if color then
        target:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function ApplyCustomAuraMaxBarEffects(target, cabConfig, baseColor)
    if not target then return end
    baseColor = baseColor or GetCustomAuraMaxBarEffectColor(cabConfig)
    if not IsCustomAuraMaxBarEffectEnabled(cabConfig) then
        ClearCustomAuraMaxBarEffects(target, baseColor)
        return
    end

    target:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)
    target._maxStacksBarEffectBaseColor = baseColor

    target._maxStacksBarEffectPulseActive = cabConfig.maxStacksBarPulseEnabled == true or nil
    target._maxStacksBarEffectPulseSpeed = cabConfig.maxStacksBarPulseSpeed or 0.5

    if MaxStacksColorShiftEnabled(cabConfig) then
        target._maxStacksBarEffectColorShiftActive = true
        target._maxStacksBarEffectShiftColor = GetMaxStacksBarEffectShiftColor(cabConfig)
        target._maxStacksBarEffectShiftSpeed = cabConfig.maxStacksBarColorShiftSpeed
            or (IsMaxStacksLegacyOverlay(cabConfig) and cabConfig.maxStacksGlowSpeed)
            or 0.5
    else
        target._maxStacksBarEffectColorShiftActive = nil
        target._maxStacksBarEffectShiftColor = nil
        target._maxStacksBarEffectShiftSpeed = nil
    end

    if target._maxStacksBarEffectPulseActive or target._maxStacksBarEffectColorShiftActive then
        target:SetScript("OnUpdate", AnimateMaxStacksBarEffect)
    else
        target:SetScript("OnUpdate", nil)
    end
end

local function LayoutMaxStacksIndicator(barInfo, cabConfig, maxStacks, barTexture, borderStyle, borderSize, borderRenderMode)
    local indicator = barInfo._maxStacksIndicator
    if not indicator then return end

    local style = GetMaxStacksFrameTreatmentStyle(cabConfig)
    if style == "none" then
        ClearMaxStacksFrameTreatment(barInfo)
        return
    end
    indicator._maxStacksFrameTreatmentStyle = style
    indicator._maxStacksIndicatorActive = nil

    local color = cabConfig.maxStacksGlowColor or {1, 0.84, 0, 0.9}
    local size = cabConfig.maxStacksGlowSize or 2
    local frame = barInfo.frame
    local isVertical = frame._isVertical

    -- Positioning
    indicator:ClearAllPoints()
    if style == "pixelGlow" then
        indicator:SetFrameLevel(frame:GetFrameLevel() + 3)
        LayoutWholeBarFrame(indicator, frame, borderStyle, borderSize, borderRenderMode)
    else
        -- solidBorder / pulsingBorder: sit behind the bar
        StopMaxStacksPixelGlow(indicator)
        indicator._maxStacksPixelGlowConfig = nil
        if indicator._maxStacksPixelGlowClip then
            indicator._maxStacksPixelGlowClip:Hide()
        end
        indicator:SetFrameLevel(frame:GetFrameLevel() - 1)
        indicator:SetPoint("TOPLEFT", frame, "TOPLEFT", -size, size)
        indicator:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", size, -size)
    end

    -- Color
    if style == "pixelGlow" then
        indicator:SetStatusBarColor(1, 1, 1, 0)
    else
        indicator:SetStatusBarColor(color[1], color[2], color[3], color[4] or 0.9)
    end

    -- Texture & orientation
    indicator:SetStatusBarTexture(barTexture or "Interface\\Buttons\\WHITE8x8")
    indicator:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")

    -- Range: [maxStacks-1, maxStacks] → 0% below, 100% at max
    SetCustomAuraMaxThresholdRange(indicator, maxStacks)

    -- Ensure visible (ClearMaxStacksIndicator hides the frame; SetValue controls render)
    indicator:Show()

    if style == "pixelGlow" then
        if indicator._pulseAG then
            indicator._pulseAG:Stop()
        end
        indicator._maxStacksPulseSuspended = nil
        indicator:SetAlpha(1)
        ConfigureMaxStacksPixelGlow(indicator, cabConfig)
        return
    end

    -- Animation
    if style == "pulsingBorder" then
        local speed = cabConfig.maxStacksGlowSpeed or 0.5
        if not indicator._pulseAG then
            local ag = indicator:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local anim = ag:CreateAnimation("Alpha")
            indicator._pulseAG = ag
            indicator._pulseAnim = anim
        end
        -- Update duration and alpha range (stop+play to apply changes)
        indicator._pulseAnim:SetDuration(speed)
        indicator._pulseAnim:SetFromAlpha(1.0)
        indicator._pulseAnim:SetToAlpha(0.3)
        indicator._pulseAG:Stop()
        indicator._pulseAG:Play()
        indicator._maxStacksPulseSuspended = nil
    else
        if indicator._pulseAG then
            indicator._pulseAG:Stop()
        end
        indicator._maxStacksPulseSuspended = nil
        indicator:SetAlpha(1)
    end
end

local function ClearMaxStacksIndicator(barInfo)
    ClearMaxStacksFrameTreatment(barInfo)
end

local function EnsureCustomAuraContinuousThresholdOverlay(bar)
    if not bar or bar.thresholdOverlay then return end
    local overlay = CreateFrame("StatusBar", nil, bar)
    overlay:SetFrameLevel(bar:GetFrameLevel() + 1)
    overlay:SetMinMaxValues(0, 1)
    SetStatusBarImmediateValue(overlay, 0)
    overlay:Hide()
    bar.thresholdOverlay = overlay
end

local function EnsureCustomAuraSegmentThresholdOverlays(holder)
    if not holder or not holder.segments then return end
    holder.thresholdSegments = holder.thresholdSegments or {}
    local count = holder._activeSegments or #holder.segments
    for i = 1, count do
        if not holder.thresholdSegments[i] then
            local seg = CreateFrame("StatusBar", nil, holder)
            seg:SetFrameLevel(holder:GetFrameLevel() + 3)
            seg:SetMinMaxValues(0, 1)
            SetStatusBarImmediateValue(seg, 0)
            seg:Hide()
            holder.thresholdSegments[i] = seg
        end
    end
    for i = count + 1, #holder.thresholdSegments do
        local seg = holder.thresholdSegments[i]
        if seg then
            SetStatusBarImmediateValue(seg, 0)
            seg:Hide()
        end
    end
end

local function EnsureCustomAuraOverlayThresholdOverlays(holder, halfSegments)
    if not holder then return end
    holder.thresholdSegments = holder.thresholdSegments or {}
    for i = 1, halfSegments do
        if not holder.thresholdSegments[i] then
            local seg = CreateFrame("StatusBar", nil, holder)
            seg:SetFrameLevel(holder:GetFrameLevel() + 4)
            seg:SetMinMaxValues(0, 1)
            SetStatusBarImmediateValue(seg, 0)
            seg:Hide()
            holder.thresholdSegments[i] = seg
        end
    end
    for i = halfSegments + 1, #holder.thresholdSegments do
        local seg = holder.thresholdSegments[i]
        if seg then
            SetStatusBarImmediateValue(seg, 0)
            seg:Hide()
        end
    end
end

local function LayoutCustomAuraContinuousThresholdOverlay(bar, barTexture, borderStyle, borderSize, borderRenderMode)
    if not bar or not bar.thresholdOverlay then return end
    local overlay = bar.thresholdOverlay
    local isVertical = bar._isVertical == true
    local reverseFill = bar._reverseFill == true
    overlay:SetFrameLevel(bar:GetFrameLevel() + 1)
    if bar.textLayer then
        bar.textLayer:SetFrameLevel(overlay:GetFrameLevel() + 1)
    end
    overlay:ClearAllPoints()
    if borderStyle == "pixel" then
        local inset = ST.GetEffectiveBorderLayoutSize(bar, borderSize, borderRenderMode)
        overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", inset, -inset)
        overlay:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -inset, inset)
    else
        overlay:SetAllPoints(bar)
    end
    overlay:SetStatusBarTexture(barTexture)
    overlay:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    overlay:SetReverseFill(reverseFill)
end

------------------------------------------------------------------------
-- Frame Factories
------------------------------------------------------------------------

local function CreateContinuousBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
    bar:SetMinMaxValues(0, 100)
    SetStatusBarImmediateValue(bar, 0)

    -- Background
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.5)

    -- Pixel borders
    bar.borders = CreatePixelBorders(bar)

    -- Text container is kept above custom aura threshold overlays.
    bar.textLayer = CreateFrame("Frame", nil, bar)
    bar.textLayer:SetAllPoints(bar)
    bar.textLayer:SetFrameLevel(bar:GetFrameLevel() + 2)

    -- Text
    bar.text = bar.textLayer:CreateFontString(nil, "OVERLAY")
    local textOutline = ST.GetEffectiveFontOutline("OUTLINE")
    bar.text:SetFont(CooldownCompanion:FetchFont("Friz Quadrata TT"), 10, textOutline)
    ST.ApplyFontShadowForOutline(bar.text, textOutline)
    bar.text:SetPoint("CENTER")
    bar.text:SetTextColor(1, 1, 1, 1)

    -- Brightness overlay (additive layer for atlas textures, since SetStatusBarColor clamps to [0,1])
    bar.brightnessOverlay = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.brightnessOverlay:SetBlendMode("ADD")
    bar.brightnessOverlay:Hide()

    -- Optional static tick markers for continuous bars.
    bar.tickMarker = bar:CreateTexture(nil, "OVERLAY", nil, 6)
    bar.tickMarker:SetColorTexture(1, 0.84, 0, 1)
    bar.tickMarker:Hide()
    bar.tickMarkers = { bar.tickMarker }

    bar._barType = "continuous"
    return bar
end

local function CreateSegmentedBar(parent, numSegments)
    local holder = CreateFrame("Frame", nil, parent)

    holder.segments = {}
    for i = 1, numSegments do
        local seg = CreateFrame("StatusBar", nil, holder)
        seg:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
        seg:SetMinMaxValues(0, 1)
        SetStatusBarImmediateValue(seg, 0)

        seg.bg = seg:CreateTexture(nil, "BACKGROUND")
        seg.bg:SetAllPoints()
        seg.bg:SetColorTexture(0, 0, 0, 0.5)

        seg.borders = CreatePixelBorders(seg)

        holder.segments[i] = seg
    end

    holder.textLayer = CreateFrame("Frame", nil, holder)
    holder.textLayer:SetAllPoints(holder)
    holder.textLayer:SetFrameLevel(holder:GetFrameLevel() + 8)

    local textFont = CooldownCompanion:FetchFont("Friz Quadrata TT")
    local textOutline = ST.GetEffectiveFontOutline("OUTLINE")

    holder.text = holder.textLayer:CreateFontString(nil, "OVERLAY")
    holder.text:SetFont(textFont, 10, textOutline)
    ST.ApplyFontShadowForOutline(holder.text, textOutline)
    holder.text:SetPoint("CENTER")
    holder.text:SetTextColor(1, 1, 1, 1)
    holder.text:Hide()

    holder.rechargeTexts = {}
    for i = 1, numSegments do
        local text = holder.textLayer:CreateFontString(nil, "OVERLAY")
        text:SetFont(textFont, 10, textOutline)
        ST.ApplyFontShadowForOutline(text, textOutline)
        text:SetPoint("CENTER", holder.segments[i], "CENTER", 0, 0)
        text:SetTextColor(1, 1, 1, 1)
        text:Hide()
        holder.rechargeTexts[i] = text
    end

    holder._barType = "segmented"
    holder._numSegments = numSegments
    return holder
end

------------------------------------------------------------------------
-- Layout: position segments within a segmented bar
------------------------------------------------------------------------

local function LayoutSegments(holder, totalWidth, totalHeight, gap, settings, orientationOverride, reverseFillOverride)
    if not holder or not holder.segments then return end
    local n = holder._activeSegments or #holder.segments
    if n == 0 then return end

    local style = GetResourceDisplayStyle(settings)
    local barTexture = CooldownCompanion:FetchEffectiveBarTexture(style and style.barTexture or "Solid")
    local bgColor = style and style.backgroundColor or { 0, 0, 0, 0.5 }
    local borderStyle = style and style.borderStyle or "pixel"
    local borderColor = style and style.borderColor or { 0, 0, 0, 1 }
    local borderSize = style and style.borderSize or 1
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local isVertical
    if orientationOverride == "vertical" then
        isVertical = true
    elseif orientationOverride == "horizontal" then
        isVertical = false
    else
        isVertical = IsVerticalResourceLayout(settings)
    end
    local reverseFill = false
    if reverseFillOverride ~= nil then
        reverseFill = reverseFillOverride == true
    elseif isVertical then
        reverseFill = IsVerticalFillReversed(settings)
    end
    local subSize
    if isVertical then
        gap = ClampSegmentGapToFit(totalHeight, n, gap)
        subSize = (totalHeight - (n - 1) * gap) / n
    else
        gap = ClampSegmentGapToFit(totalWidth, n, gap)
        subSize = (totalWidth - (n - 1) * gap) / n
    end
    if subSize < 1 then subSize = 1 end

    for i = 1, #holder.segments do
        local seg = holder.segments[i]
        seg:ClearAllPoints()
        if i > n then
            SetStatusBarImmediateValue(seg, 0)
            seg:Hide()
            if holder.rechargeTexts and holder.rechargeTexts[i] then
                holder.rechargeTexts[i]:Hide()
            end
            if holder.thresholdSegments and holder.thresholdSegments[i] then
                SetStatusBarImmediateValue(holder.thresholdSegments[i], 0)
                holder.thresholdSegments[i]:Hide()
            end
        elseif isVertical then
            seg:SetSize(totalWidth, subSize)
            local yOfs
            if reverseFill then
                yOfs = totalHeight - subSize - ((i - 1) * (subSize + gap))
                if yOfs < 0 then yOfs = 0 end
            else
                yOfs = (i - 1) * (subSize + gap)
            end
            seg:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, yOfs)
        else
            seg:SetSize(subSize, totalHeight)
            local xOfs
            if reverseFill then
                xOfs = totalWidth - subSize - ((i - 1) * (subSize + gap))
                if xOfs < 0 then xOfs = 0 end
            else
                xOfs = (i - 1) * (subSize + gap)
            end
            seg:SetPoint("TOPLEFT", holder, "TOPLEFT", xOfs, 0)
        end

        if i <= n then
            seg:Show()
            seg:SetStatusBarTexture(barTexture)
            seg:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
            seg:SetReverseFill(reverseFill)
            seg.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

            if borderStyle == "pixel" then
                ApplyPixelBorders(seg.borders, seg, borderColor, borderSize, borderRenderMode)
            else
                HidePixelBorders(seg.borders)
            end

            if holder.thresholdSegments and holder.thresholdSegments[i] then
                local thresholdSeg = holder.thresholdSegments[i]
                thresholdSeg:ClearAllPoints()
                if borderStyle == "pixel" then
                    local inset = ST.GetEffectiveBorderLayoutSize(seg, borderSize, borderRenderMode)
                    thresholdSeg:SetPoint("TOPLEFT", seg, "TOPLEFT", inset, -inset)
                    thresholdSeg:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -inset, inset)
                else
                    thresholdSeg:SetAllPoints(seg)
                end
                thresholdSeg:SetStatusBarTexture(barTexture)
                thresholdSeg:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
                thresholdSeg:SetReverseFill(reverseFill)
            end
        end
    end

    if holder.auraStackSegments then
        LayoutResourceAuraStackSegments(holder, settings, orientationOverride, reverseFill)
    end
end

------------------------------------------------------------------------
-- Frame creation: Overlay bar (base + overlay segments)
-- Used by custom aura bars in "overlay" display mode.
-- halfSegments = number of segments per layer (e.g. 5 for 10-max).
------------------------------------------------------------------------

local function CreateOverlayBar(parent, halfSegments)
    local holder = CreateFrame("Frame", nil, parent)

    holder.segments = {}
    for i = 1, halfSegments do
        local seg = CreateFrame("StatusBar", nil, holder)
        seg:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
        seg:SetMinMaxValues(i - 1, i)
        SetStatusBarImmediateValue(seg, 0)

        seg.bg = seg:CreateTexture(nil, "BACKGROUND")
        seg.bg:SetAllPoints()
        seg.bg:SetColorTexture(0, 0, 0, 0.5)

        seg.borders = CreatePixelBorders(seg)

        holder.segments[i] = seg
    end

    holder.overlaySegments = {}
    for i = 1, halfSegments do
        local seg = CreateFrame("StatusBar", nil, holder)
        seg:SetFrameLevel(holder:GetFrameLevel() + 2)
        seg:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
        seg:SetMinMaxValues(i + halfSegments - 1, i + halfSegments)
        SetStatusBarImmediateValue(seg, 0)

        -- No background on overlay (transparent when empty, base bg shows through)

        holder.overlaySegments[i] = seg
    end

    holder.textLayer = CreateFrame("Frame", nil, holder)
    holder.textLayer:SetAllPoints(holder)
    holder.textLayer:SetFrameLevel(holder:GetFrameLevel() + 8)

    holder.text = holder.textLayer:CreateFontString(nil, "OVERLAY")
    local textOutline = ST.GetEffectiveFontOutline("OUTLINE")
    holder.text:SetFont(CooldownCompanion:FetchFont("Friz Quadrata TT"), 10, textOutline)
    ST.ApplyFontShadowForOutline(holder.text, textOutline)
    holder.text:SetPoint("CENTER")
    holder.text:SetTextColor(1, 1, 1, 1)
    holder.text:Hide()

    return holder
end

local function LayoutOverlaySegments(holder, totalWidth, totalHeight, gap, settings, halfSegments, orientationOverride, reverseFillOverride)
    if not holder or not holder.segments then return end

    local style = GetResourceDisplayStyle(settings)
    local barTexture = CooldownCompanion:FetchEffectiveBarTexture(style and style.barTexture or "Solid")
    local bgColor = style and style.backgroundColor or { 0, 0, 0, 0.5 }
    local borderStyle = style and style.borderStyle or "pixel"
    local borderColor = style and style.borderColor or { 0, 0, 0, 1 }
    local borderSize = style and style.borderSize or 1
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local isVertical
    if orientationOverride == "vertical" then
        isVertical = true
    elseif orientationOverride == "horizontal" then
        isVertical = false
    else
        isVertical = IsVerticalResourceLayout(settings)
    end
    local reverseFill = false
    if reverseFillOverride ~= nil then
        reverseFill = reverseFillOverride == true
    elseif isVertical then
        reverseFill = IsVerticalFillReversed(settings)
    end
    local subSize
    if isVertical then
        gap = ClampSegmentGapToFit(totalHeight, halfSegments, gap)
        subSize = (totalHeight - (halfSegments - 1) * gap) / halfSegments
    else
        gap = ClampSegmentGapToFit(totalWidth, halfSegments, gap)
        subSize = (totalWidth - (halfSegments - 1) * gap) / halfSegments
    end
    if subSize < 1 then subSize = 1 end

    for i = 1, halfSegments do
        local seg = holder.segments[i]
        seg:ClearAllPoints()
        if isVertical then
            seg:SetSize(totalWidth, subSize)
            local yOfs
            if reverseFill then
                yOfs = totalHeight - subSize - ((i - 1) * (subSize + gap))
                if yOfs < 0 then yOfs = 0 end
            else
                yOfs = (i - 1) * (subSize + gap)
            end
            seg:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, yOfs)
        else
            seg:SetSize(subSize, totalHeight)
            local xOfs
            if reverseFill then
                xOfs = totalWidth - subSize - ((i - 1) * (subSize + gap))
                if xOfs < 0 then xOfs = 0 end
            else
                xOfs = (i - 1) * (subSize + gap)
            end
            seg:SetPoint("TOPLEFT", holder, "TOPLEFT", xOfs, 0)
        end

        seg:SetStatusBarTexture(barTexture)
        seg:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
        seg:SetReverseFill(reverseFill)
        seg.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

        if borderStyle == "pixel" then
            ApplyPixelBorders(seg.borders, seg, borderColor, borderSize, borderRenderMode)
        else
            HidePixelBorders(seg.borders)
        end

        -- Position overlay segment inset by border to stay inside borders
        local ov = holder.overlaySegments[i]
        ov:ClearAllPoints()
        if borderStyle == "pixel" then
            local inset = ST.GetEffectiveBorderLayoutSize(seg, borderSize, borderRenderMode)
            ov:SetPoint("TOPLEFT", seg, "TOPLEFT", inset, -inset)
            ov:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -inset, inset)
        else
            ov:SetAllPoints(seg)
        end
        ov:SetStatusBarTexture(barTexture)
        ov:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
        ov:SetReverseFill(reverseFill)

        if holder.thresholdSegments and holder.thresholdSegments[i] then
            local thresholdSeg = holder.thresholdSegments[i]
            thresholdSeg:ClearAllPoints()
            if borderStyle == "pixel" then
                local inset = ST.GetEffectiveBorderLayoutSize(seg, borderSize, borderRenderMode)
                thresholdSeg:SetPoint("TOPLEFT", seg, "TOPLEFT", inset, -inset)
                thresholdSeg:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -inset, inset)
            else
                thresholdSeg:SetAllPoints(seg)
            end
            thresholdSeg:SetStatusBarTexture(barTexture)
            thresholdSeg:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
            thresholdSeg:SetReverseFill(reverseFill)
        end
    end
    for i = halfSegments + 1, #holder.segments do
        local seg = holder.segments[i]
        if seg then
            SetStatusBarImmediateValue(seg, 0)
            seg:Hide()
        end
        local ov = holder.overlaySegments and holder.overlaySegments[i]
        if ov then
            SetStatusBarImmediateValue(ov, 0)
            ov:Hide()
        end
        local thresholdSeg = holder.thresholdSegments and holder.thresholdSegments[i]
        if thresholdSeg then
            SetStatusBarImmediateValue(thresholdSeg, 0)
            thresholdSeg:Hide()
        end
    end

    if holder.auraStackSegments then
        LayoutResourceAuraStackSegments(holder, settings, orientationOverride, reverseFill)
    end
end

------------------------------------------------------------------------
-- Add all visual functions to ST._RB
------------------------------------------------------------------------

RB.GetActiveResourceAuraEntry = GetActiveResourceAuraEntry
RB.GetResourceAuraConfiguredMaxStacks = GetResourceAuraConfiguredMaxStacks
RB.IsResourceAuraOverlayEnabled = IsResourceAuraOverlayEnabled
RB.GetResourceAuraState = GetResourceAuraState
RB.HideResourceAuraStackSegments = HideResourceAuraStackSegments
RB.ApplyResourceAuraStackSegments = ApplyResourceAuraStackSegments
RB.ClearResourceAuraVisuals = ClearResourceAuraVisuals
RB.UpdateContinuousTickMarker = UpdateContinuousTickMarker
RB.ApplyContinuousFillColor = ApplyContinuousFillColor
RB.CreatePixelBorders = CreatePixelBorders
RB.ApplyPixelBorders = ApplyPixelBorders
RB.HidePixelBorders = HidePixelBorders
RB.IsCustomAuraMaxThresholdEnabled = IsCustomAuraMaxThresholdEnabled
RB.GetCustomAuraMaxThresholdColor = GetCustomAuraMaxThresholdColor
RB.SetCustomAuraMaxThresholdRange = SetCustomAuraMaxThresholdRange
RB.HasMaxStacksBarEffects = HasMaxStacksBarEffects
RB.IsCustomAuraMaxBarEffectEnabled = IsCustomAuraMaxBarEffectEnabled
RB.GetCustomAuraMaxBarEffectColor = GetCustomAuraMaxBarEffectColor
RB.ApplyCustomAuraMaxBarEffects = ApplyCustomAuraMaxBarEffects
RB.ClearCustomAuraMaxBarEffects = ClearCustomAuraMaxBarEffects
RB.GetMaxStacksFrameTreatmentStyle = GetMaxStacksFrameTreatmentStyle
RB.EnsureMaxStacksIndicator = EnsureMaxStacksIndicator
RB.LayoutMaxStacksIndicator = LayoutMaxStacksIndicator
RB.ClearMaxStacksIndicator = ClearMaxStacksIndicator
RB.SetMaxStacksIndicatorActive = SetMaxStacksIndicatorActive
RB.EnsureCustomAuraContinuousThresholdOverlay = EnsureCustomAuraContinuousThresholdOverlay
RB.EnsureCustomAuraSegmentThresholdOverlays = EnsureCustomAuraSegmentThresholdOverlays
RB.EnsureCustomAuraOverlayThresholdOverlays = EnsureCustomAuraOverlayThresholdOverlays
RB.LayoutCustomAuraContinuousThresholdOverlay = LayoutCustomAuraContinuousThresholdOverlay
RB.CreateContinuousBar = CreateContinuousBar
RB.CreateSegmentedBar = CreateSegmentedBar
RB.LayoutSegments = LayoutSegments
RB.CreateOverlayBar = CreateOverlayBar
RB.LayoutOverlaySegments = LayoutOverlaySegments
