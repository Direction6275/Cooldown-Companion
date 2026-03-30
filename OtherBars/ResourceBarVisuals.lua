--[[
    CooldownCompanion - ResourceBarVisuals
    Visual layer components: frame factories, layout, borders, overlays,
    indicators, and tick markers. No mutable runtime state.

    All functions are added to ST._RB so consuming files can alias them to
    locals at load time.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local issecretvalue = issecretvalue
local math_sin = math.sin
local math_pi = math.pi

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

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
local GetContinuousTickConfig = RB.GetContinuousTickConfig
local GetSafeRGBColor = RB.GetSafeRGBColor
local SupportsResourceAuraStackMode = RB.SupportsResourceAuraStackMode

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
    if not settings or not settings.resources then return nil, nil, false end
    local resource = settings.resources[powerType]
    if not resource then return nil, nil, false end
    if not IsResourceAuraOverlayEnabled(resource) then return nil, nil, false end
    local auraEntry = GetActiveResourceAuraEntry(resource)
    if not auraEntry then
        return nil, nil, false
    end

    local auraSpellID = tonumber(auraEntry.auraColorSpellID)
    if not auraSpellID or auraSpellID <= 0 then
        return nil, nil, false
    end

    local cached
    if auraActiveCache then
        cached = auraActiveCache[auraSpellID]
    end

    if not cached then
        cached = { active = false, applications = nil, hasApplications = false }

        if C_CVar.GetCVarBool("cooldownViewerEnabled") then
            local viewerFrame = CooldownCompanion.viewerAuraFrames and CooldownCompanion.viewerAuraFrames[auraSpellID]
            local instId = viewerFrame and viewerFrame.auraInstanceID
            if instId then
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", instId)
                if auraData then
                    cached.active = true
                    if type(auraData.applications) == "number" then
                        -- applications can be secret in combat for some auras.
                        -- Keep as pass-through only (no Lua math/comparisons).
                        cached.applications = auraData.applications
                        cached.hasApplications = true
                    end
                end
            end
        end

        if not cached.active then
            -- Fallback for non-CDM spell IDs. In combat, secret aura restrictions can
            -- cause this API to return nil for some active auras.
            local auraData = C_UnitAuras.GetPlayerAuraBySpellID(auraSpellID)
            if auraData then
                cached.active = true
                if type(auraData.applications) == "number" then
                    -- applications can be secret in combat for some auras.
                    -- Keep as pass-through only (no Lua math/comparisons).
                    cached.applications = auraData.applications
                    cached.hasApplications = true
                end
            end
        end

        if auraActiveCache then
            auraActiveCache[auraSpellID] = cached
        end
    end

    if not cached.active then
        return nil, nil, false
    end

    local color = auraEntry.auraActiveColor
    if type(color) ~= "table" or not color[1] or not color[2] or not color[3] then
        color = DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
    end
    return color, cached.applications, cached.hasApplications
end

local function HideResourceAuraStackSegments(holder)
    if not holder or not holder.auraStackSegments then return end
    for _, seg in ipairs(holder.auraStackSegments) do
        seg:SetValue(0)
        seg:Hide()
    end
end

local function LayoutResourceAuraStackSegments(holder, settings, orientationOverride, reverseFillOverride)
    if not holder or not holder.auraStackSegments or not holder.segments then return end
    local barTexture = CooldownCompanion:FetchStatusBar(settings and settings.barTexture or "Solid")
    local borderStyle = settings and settings.borderStyle or "pixel"
    local borderSize = settings and settings.borderSize or 1
    local isVertical
    if orientationOverride == "vertical" then
        isVertical = true
    elseif orientationOverride == "horizontal" then
        isVertical = false
    else
        isVertical = IsVerticalResourceLayout(settings)
    end
    local reverseFill = false
    if isVertical then
        if reverseFillOverride == nil then
            reverseFill = IsVerticalFillReversed(settings)
        else
            reverseFill = reverseFillOverride == true
        end
    end

    for i, auraSeg in ipairs(holder.auraStackSegments) do
        local baseSeg = holder.segments[i]
        if baseSeg then
            local inset = (borderStyle == "pixel") and borderSize or 0
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
            auraSeg:SetReverseFill(isVertical and reverseFill or false)
            auraSeg:SetFrameLevel(baseSeg:GetFrameLevel() + 4)
        else
            auraSeg:Hide()
        end
    end
end

local function EnsureResourceAuraStackSegments(holder, settings)
    if not holder or not holder.segments then return nil end
    local count = #holder.segments
    if count == 0 then return nil end

    if not holder.auraStackSegments or #holder.auraStackSegments ~= count then
        if holder.auraStackSegments then
            for _, oldSeg in ipairs(holder.auraStackSegments) do
                oldSeg:SetValue(0)
                oldSeg:ClearAllPoints()
                oldSeg:Hide()
            end
        end
        holder.auraStackSegments = {}
        for i = 1, count do
            local seg = CreateFrame("StatusBar", nil, holder)
            seg:SetMinMaxValues(0, 1)
            seg:SetValue(0)
            seg:Hide()
            holder.auraStackSegments[i] = seg
        end
    end

    LayoutResourceAuraStackSegments(holder, settings)
    return holder.auraStackSegments
end

local function ApplyResourceAuraStackSegments(holder, settings, stackValue, maxStacks, color)
    local auraSegments = EnsureResourceAuraStackSegments(holder, settings)
    if not auraSegments then return end

    local count = #auraSegments
    for i = 1, count do
        local seg = auraSegments[i]
        local segMin = ((i - 1) * maxStacks) / count
        local segMax = (i * maxStacks) / count
        seg:SetMinMaxValues(segMin, segMax)
        seg:SetValue(stackValue)
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

local function UpdateContinuousTickMarker(bar, powerType, settings, maxPower, maxPowerIsSecret)
    if not bar or not bar.tickMarker then return end

    local enabled, mode, percentValue, absoluteValue, tickColor, tickWidth, combatOnly = GetContinuousTickConfig(powerType, settings)
    if not enabled then
        bar.tickMarker:Hide()
        return
    end

    if combatOnly and not InCombatLockdown() then
        bar.tickMarker:Hide()
        return
    end

    local ratio
    if mode == "absolute" then
        if maxPowerIsSecret then
            bar.tickMarker:Hide()
            return
        end
        if issecretvalue and issecretvalue(maxPower) then
            bar.tickMarker:Hide()
            return
        end
        if type(maxPower) ~= "number" or maxPower <= 0 then
            bar.tickMarker:Hide()
            return
        end
        ratio = absoluteValue / maxPower
    else
        ratio = percentValue / 100
    end

    if ratio < 0 then
        ratio = 0
    elseif ratio > 1 then
        ratio = 1
    end

    local marker = bar.tickMarker
    marker:SetColorTexture(tickColor[1], tickColor[2], tickColor[3], tickColor[4] ~= nil and tickColor[4] or 1)

    local borderStyle = settings and settings.borderStyle or "pixel"
    local borderSize = (borderStyle == "pixel") and (settings.borderSize or 1) or 0
    local width = bar:GetWidth() or 0
    local height = bar:GetHeight() or 0
    if width <= 0 or height <= 0 then
        marker:Hide()
        return
    end

    local halfTick = tickWidth / 2
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
end

local function ApplyContinuousFillColor(bar, powerType, settings, overrideColor)
    if not bar or not settings then return end

    local texName = settings.barTexture or "Solid"
    local atlasInfo = (texName == "blizzard_class") and POWER_ATLAS_INFO[powerType] or nil
    if atlasInfo then
        if overrideColor then
            bar:SetStatusBarColor(overrideColor[1], overrideColor[2], overrideColor[3], 1)
            bar.brightnessOverlay:Hide()
            return
        end

        local brightness = settings.classBarBrightness or 1.3
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
    local borders = {}
    local names = { "TOP", "BOTTOM", "LEFT", "RIGHT" }
    for _, side in ipairs(names) do
        local tex = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(0, 0, 0, 1)
        tex:Hide()
        borders[side] = tex
    end
    return borders
end

local function ApplyPixelBorders(borders, parent, color, size)
    if not borders then return end
    local r, g, b, a = color[1], color[2], color[3], color[4]
    size = size or 1

    for _, tex in pairs(borders) do
        tex:SetColorTexture(r, g, b, a)
        tex:Show()
    end

    borders.TOP:ClearAllPoints()
    borders.TOP:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    borders.TOP:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    borders.TOP:SetHeight(size)

    borders.BOTTOM:ClearAllPoints()
    borders.BOTTOM:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    borders.BOTTOM:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    borders.BOTTOM:SetHeight(size)

    borders.LEFT:ClearAllPoints()
    borders.LEFT:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -size)
    borders.LEFT:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, size)
    borders.LEFT:SetWidth(size)

    borders.RIGHT:ClearAllPoints()
    borders.RIGHT:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -size)
    borders.RIGHT:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, size)
    borders.RIGHT:SetWidth(size)
end

local function HidePixelBorders(borders)
    if not borders then return end
    for _, tex in pairs(borders) do
        tex:Hide()
    end
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

local function EnsureMaxStacksIndicator(barInfo)
    if barInfo._maxStacksIndicator then return barInfo._maxStacksIndicator end
    local indicator = CreateFrame("StatusBar", nil, barInfo.frame)
    indicator:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    indicator:EnableMouse(false)
    indicator:Show()
    barInfo._maxStacksIndicator = indicator
    return indicator
end

local function LayoutMaxStacksIndicator(barInfo, cabConfig, maxStacks, barTexture, borderStyle, borderSize)
    local indicator = barInfo._maxStacksIndicator
    if not indicator then return end

    local style = cabConfig.maxStacksGlowStyle or "solidBorder"
    local color = cabConfig.maxStacksGlowColor or {1, 0.84, 0, 0.9}
    local size = cabConfig.maxStacksGlowSize or 2
    local frame = barInfo.frame
    local isVertical = frame._isVertical

    -- Positioning
    indicator:ClearAllPoints()
    if style == "pulsingOverlay" then
        indicator:SetFrameLevel(frame:GetFrameLevel() + 3)
        if borderStyle == "pixel" then
            indicator:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
            indicator:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        else
            indicator:SetAllPoints(frame)
        end
    else
        -- solidBorder / pulsingBorder: sit behind the bar
        indicator:SetFrameLevel(frame:GetFrameLevel() - 1)
        indicator:SetPoint("TOPLEFT", frame, "TOPLEFT", -size, size)
        indicator:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", size, -size)
    end

    -- Color
    indicator:SetStatusBarColor(color[1], color[2], color[3], color[4] or 0.9)

    -- Texture & orientation
    indicator:SetStatusBarTexture(barTexture or "Interface\\Buttons\\WHITE8x8")
    indicator:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")

    -- Range: [maxStacks-1, maxStacks] → 0% below, 100% at max
    SetCustomAuraMaxThresholdRange(indicator, maxStacks)

    -- Ensure visible (ClearMaxStacksIndicator hides the frame; SetValue controls render)
    indicator:Show()

    -- Animation
    local needsPulse = (style == "pulsingBorder" or style == "pulsingOverlay")
    if needsPulse then
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
        if style == "pulsingOverlay" then
            indicator._pulseAnim:SetFromAlpha(1.0)
            indicator._pulseAnim:SetToAlpha(0.0)
        else
            indicator._pulseAnim:SetFromAlpha(1.0)
            indicator._pulseAnim:SetToAlpha(0.3)
        end
        indicator._pulseAG:Stop()
        indicator._pulseAG:Play()
    else
        if indicator._pulseAG then
            indicator._pulseAG:Stop()
        end
        indicator:SetAlpha(1)
    end
end

local function ClearMaxStacksIndicator(barInfo)
    local indicator = barInfo._maxStacksIndicator
    if not indicator then return end
    indicator:Hide()
    if indicator._pulseAG then
        indicator._pulseAG:Stop()
    end
    indicator:SetValue(0)
end

------------------------------------------------------------------------
-- Custom Aura Bar Effect Helpers (pixel glow, alpha pulse, color shift)
------------------------------------------------------------------------

-- Convert user-facing speed (1–200) to LCG PixelGlow frequency.
local function CabSpeedToFrequency(speed)
    return math_max(speed or 60, 1) / 120
end

local CAB_AURA_LCG_KEY = "CooldownCompanionCabAura"
local CAB_PANDEMIC_LCG_KEY = "CooldownCompanionCabPandemic"

local function StartCustomAuraPixelGlow(frame, color, lines, speed, size, thickness, key)
    if not (LCG and LCG.PixelGlow_Start and frame) then return end
    local frequency = CabSpeedToFrequency(speed)
    LCG.PixelGlow_Start(frame, color, lines or 8, frequency,
        size or 8, thickness or 2, 0, 0, false, key or "", 1)
end

local function StopCustomAuraPixelGlow(frame, key)
    if not (LCG and LCG.PixelGlow_Stop and frame) then return end
    LCG.PixelGlow_Stop(frame, key or "")
end

-- Clear all indicator effects from a custom aura bar (animation state,
-- pixel glow, alpha, color).  Called when the bar is hidden, rebuilt,
-- or the config panel navigates away.
local function ClearCustomAuraBarEffects(barInfo)
    if not barInfo then return end
    local frame = barInfo.frame
    -- Stop pixel glow
    StopCustomAuraPixelGlow(frame, CAB_AURA_LCG_KEY)
    StopCustomAuraPixelGlow(frame, CAB_PANDEMIC_LCG_KEY)
    -- Reset fill texture alpha (not frame alpha — preserves border/background)
    if frame then
        if frame.GetStatusBarTexture then
            local tex = frame:GetStatusBarTexture()
            if tex then tex:SetAlpha(1.0) end
        end
        if frame.segments then
            for _, seg in ipairs(frame.segments) do
                local tex = seg:GetStatusBarTexture()
                if tex then tex:SetAlpha(1.0) end
            end
        end
        if frame.overlaySegments then
            for _, seg in ipairs(frame.overlaySegments) do
                local tex = seg:GetStatusBarTexture()
                if tex then tex:SetAlpha(1.0) end
            end
        end
    end
    -- Clear animation state flags
    barInfo._cabPulseActive = nil
    barInfo._cabPulseSpeed = nil
    barInfo._cabColorShiftActive = nil
    barInfo._cabCSBaseColor = nil
    barInfo._cabCSShiftColor = nil
    barInfo._cabCSSpeed = nil
    barInfo._cabPixelGlowKey = nil
    barInfo._cabInPandemic = nil
    barInfo._cabEffectPreview = nil
end

local function EnsureCustomAuraContinuousThresholdOverlay(bar)
    if not bar or bar.thresholdOverlay then return end
    local overlay = CreateFrame("StatusBar", nil, bar)
    overlay:SetFrameLevel(bar:GetFrameLevel() + 1)
    overlay:SetMinMaxValues(0, 1)
    overlay:SetValue(0)
    overlay:Hide()
    bar.thresholdOverlay = overlay
end

local function EnsureCustomAuraSegmentThresholdOverlays(holder)
    if not holder or not holder.segments or holder.thresholdSegments then return end
    holder.thresholdSegments = {}
    for i = 1, #holder.segments do
        local seg = CreateFrame("StatusBar", nil, holder)
        seg:SetFrameLevel(holder:GetFrameLevel() + 3)
        seg:SetMinMaxValues(0, 1)
        seg:SetValue(0)
        seg:Hide()
        holder.thresholdSegments[i] = seg
    end
end

local function EnsureCustomAuraOverlayThresholdOverlays(holder, halfSegments)
    if not holder or holder.thresholdSegments then return end
    holder.thresholdSegments = {}
    for i = 1, halfSegments do
        local seg = CreateFrame("StatusBar", nil, holder)
        seg:SetFrameLevel(holder:GetFrameLevel() + 4)
        seg:SetMinMaxValues(0, 1)
        seg:SetValue(0)
        seg:Hide()
        holder.thresholdSegments[i] = seg
    end
end

local function LayoutCustomAuraContinuousThresholdOverlay(bar, barTexture, borderStyle, borderSize)
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
        overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", borderSize, -borderSize)
        overlay:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -borderSize, borderSize)
    else
        overlay:SetAllPoints(bar)
    end
    overlay:SetStatusBarTexture(barTexture)
    overlay:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    overlay:SetReverseFill(isVertical and reverseFill or false)
end

------------------------------------------------------------------------
-- Frame Factories
------------------------------------------------------------------------

local function CreateContinuousBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)

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
    bar.text:SetFont(CooldownCompanion:FetchFont("Friz Quadrata TT"), 10, "OUTLINE")
    bar.text:SetPoint("CENTER")
    bar.text:SetTextColor(1, 1, 1, 1)

    -- Brightness overlay (additive layer for atlas textures, since SetStatusBarColor clamps to [0,1])
    bar.brightnessOverlay = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.brightnessOverlay:SetBlendMode("ADD")
    bar.brightnessOverlay:Hide()

    -- Optional static tick marker for continuous bars.
    bar.tickMarker = bar:CreateTexture(nil, "OVERLAY", nil, 6)
    bar.tickMarker:SetColorTexture(1, 0.84, 0, 1)
    bar.tickMarker:Hide()

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
        seg:SetValue(0)

        seg.bg = seg:CreateTexture(nil, "BACKGROUND")
        seg.bg:SetAllPoints()
        seg.bg:SetColorTexture(0, 0, 0, 0.5)

        seg.borders = CreatePixelBorders(seg)

        holder.segments[i] = seg
    end

    holder.textLayer = CreateFrame("Frame", nil, holder)
    holder.textLayer:SetAllPoints(holder)
    holder.textLayer:SetFrameLevel(holder:GetFrameLevel() + 8)

    holder.text = holder.textLayer:CreateFontString(nil, "OVERLAY")
    holder.text:SetFont(CooldownCompanion:FetchFont("Friz Quadrata TT"), 10, "OUTLINE")
    holder.text:SetPoint("CENTER")
    holder.text:SetTextColor(1, 1, 1, 1)
    holder.text:Hide()

    holder._barType = "segmented"
    holder._numSegments = numSegments
    return holder
end

------------------------------------------------------------------------
-- Layout: position segments within a segmented bar
------------------------------------------------------------------------

local function LayoutSegments(holder, totalWidth, totalHeight, gap, settings, orientationOverride, reverseFillOverride)
    if not holder or not holder.segments then return end
    local n = #holder.segments
    if n == 0 then return end

    local barTexture = CooldownCompanion:FetchStatusBar(settings and settings.barTexture or "Solid")
    local bgColor = settings and settings.backgroundColor or { 0, 0, 0, 0.5 }
    local borderStyle = settings and settings.borderStyle or "pixel"
    local borderColor = settings and settings.borderColor or { 0, 0, 0, 1 }
    local borderSize = settings and settings.borderSize or 1
    local isVertical
    if orientationOverride == "vertical" then
        isVertical = true
    elseif orientationOverride == "horizontal" then
        isVertical = false
    else
        isVertical = IsVerticalResourceLayout(settings)
    end
    local reverseFill = false
    if isVertical then
        if reverseFillOverride == nil then
            reverseFill = IsVerticalFillReversed(settings)
        else
            reverseFill = reverseFillOverride == true
        end
    end
    local subSize
    if isVertical then
        subSize = (totalHeight - (n - 1) * gap) / n
    else
        subSize = (totalWidth - (n - 1) * gap) / n
    end
    if subSize < 1 then subSize = 1 end

    for i, seg in ipairs(holder.segments) do
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
            local xOfs = (i - 1) * (subSize + gap)
            seg:SetPoint("TOPLEFT", holder, "TOPLEFT", xOfs, 0)
        end

        seg:SetStatusBarTexture(barTexture)
        seg:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
        seg:SetReverseFill(isVertical and reverseFill or false)
        seg.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

        if borderStyle == "pixel" then
            ApplyPixelBorders(seg.borders, seg, borderColor, borderSize)
        else
            HidePixelBorders(seg.borders)
        end

        if holder.thresholdSegments and holder.thresholdSegments[i] then
            local thresholdSeg = holder.thresholdSegments[i]
            thresholdSeg:ClearAllPoints()
            if borderStyle == "pixel" then
                thresholdSeg:SetPoint("TOPLEFT", seg, "TOPLEFT", borderSize, -borderSize)
                thresholdSeg:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -borderSize, borderSize)
            else
                thresholdSeg:SetAllPoints(seg)
            end
            thresholdSeg:SetStatusBarTexture(barTexture)
            thresholdSeg:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
            thresholdSeg:SetReverseFill(isVertical and reverseFill or false)
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
        seg:SetValue(0)

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
        seg:SetValue(0)

        -- No background on overlay (transparent when empty, base bg shows through)

        holder.overlaySegments[i] = seg
    end

    holder.textLayer = CreateFrame("Frame", nil, holder)
    holder.textLayer:SetAllPoints(holder)
    holder.textLayer:SetFrameLevel(holder:GetFrameLevel() + 8)

    holder.text = holder.textLayer:CreateFontString(nil, "OVERLAY")
    holder.text:SetFont(CooldownCompanion:FetchFont("Friz Quadrata TT"), 10, "OUTLINE")
    holder.text:SetPoint("CENTER")
    holder.text:SetTextColor(1, 1, 1, 1)
    holder.text:Hide()

    return holder
end

local function LayoutOverlaySegments(holder, totalWidth, totalHeight, gap, settings, halfSegments, orientationOverride, reverseFillOverride)
    if not holder or not holder.segments then return end

    local barTexture = CooldownCompanion:FetchStatusBar(settings and settings.barTexture or "Solid")
    local bgColor = settings and settings.backgroundColor or { 0, 0, 0, 0.5 }
    local borderStyle = settings and settings.borderStyle or "pixel"
    local borderColor = settings and settings.borderColor or { 0, 0, 0, 1 }
    local borderSize = settings and settings.borderSize or 1
    local isVertical
    if orientationOverride == "vertical" then
        isVertical = true
    elseif orientationOverride == "horizontal" then
        isVertical = false
    else
        isVertical = IsVerticalResourceLayout(settings)
    end
    local reverseFill = false
    if isVertical then
        if reverseFillOverride == nil then
            reverseFill = IsVerticalFillReversed(settings)
        else
            reverseFill = reverseFillOverride == true
        end
    end
    local subSize
    if isVertical then
        subSize = (totalHeight - (halfSegments - 1) * gap) / halfSegments
    else
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
            local xOfs = (i - 1) * (subSize + gap)
            seg:SetPoint("TOPLEFT", holder, "TOPLEFT", xOfs, 0)
        end

        seg:SetStatusBarTexture(barTexture)
        seg:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
        seg:SetReverseFill(isVertical and reverseFill or false)
        seg.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

        if borderStyle == "pixel" then
            ApplyPixelBorders(seg.borders, seg, borderColor, borderSize)
        else
            HidePixelBorders(seg.borders)
        end

        -- Position overlay segment inset by border to stay inside borders
        local ov = holder.overlaySegments[i]
        ov:ClearAllPoints()
        if borderStyle == "pixel" then
            ov:SetPoint("TOPLEFT", seg, "TOPLEFT", borderSize, -borderSize)
            ov:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -borderSize, borderSize)
        else
            ov:SetAllPoints(seg)
        end
        ov:SetStatusBarTexture(barTexture)
        ov:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
        ov:SetReverseFill(isVertical and reverseFill or false)

        if holder.thresholdSegments and holder.thresholdSegments[i] then
            local thresholdSeg = holder.thresholdSegments[i]
            thresholdSeg:ClearAllPoints()
            if borderStyle == "pixel" then
                thresholdSeg:SetPoint("TOPLEFT", seg, "TOPLEFT", borderSize, -borderSize)
                thresholdSeg:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -borderSize, borderSize)
            else
                thresholdSeg:SetAllPoints(seg)
            end
            thresholdSeg:SetStatusBarTexture(barTexture)
            thresholdSeg:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
            thresholdSeg:SetReverseFill(isVertical and reverseFill or false)
        end
    end

    if holder.auraStackSegments then
        LayoutResourceAuraStackSegments(holder, settings, orientationOverride, reverseFill)
    end
end

------------------------------------------------------------------------
-- Add all visual functions to ST._RB
------------------------------------------------------------------------

RB.GetResourceAuraEntry = GetResourceAuraEntry
RB.GetLegacyResourceAuraEntry = GetLegacyResourceAuraEntry
RB.GetActiveResourceAuraEntry = GetActiveResourceAuraEntry
RB.GetResourceAuraTrackingMode = GetResourceAuraTrackingMode
RB.GetResourceAuraConfiguredMaxStacks = GetResourceAuraConfiguredMaxStacks
RB.IsResourceAuraOverlayEnabled = IsResourceAuraOverlayEnabled
RB.GetResourceAuraState = GetResourceAuraState
RB.HideResourceAuraStackSegments = HideResourceAuraStackSegments
RB.LayoutResourceAuraStackSegments = LayoutResourceAuraStackSegments
RB.EnsureResourceAuraStackSegments = EnsureResourceAuraStackSegments
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
RB.EnsureMaxStacksIndicator = EnsureMaxStacksIndicator
RB.LayoutMaxStacksIndicator = LayoutMaxStacksIndicator
RB.ClearMaxStacksIndicator = ClearMaxStacksIndicator
RB.EnsureCustomAuraContinuousThresholdOverlay = EnsureCustomAuraContinuousThresholdOverlay
RB.EnsureCustomAuraSegmentThresholdOverlays = EnsureCustomAuraSegmentThresholdOverlays
RB.EnsureCustomAuraOverlayThresholdOverlays = EnsureCustomAuraOverlayThresholdOverlays
RB.LayoutCustomAuraContinuousThresholdOverlay = LayoutCustomAuraContinuousThresholdOverlay
RB.CreateContinuousBar = CreateContinuousBar
RB.CreateSegmentedBar = CreateSegmentedBar
RB.LayoutSegments = LayoutSegments
RB.CreateOverlayBar = CreateOverlayBar
RB.LayoutOverlaySegments = LayoutOverlaySegments
RB.CabSpeedToFrequency = CabSpeedToFrequency
RB.StartCustomAuraPixelGlow = StartCustomAuraPixelGlow
RB.StopCustomAuraPixelGlow = StopCustomAuraPixelGlow
RB.ClearCustomAuraBarEffects = ClearCustomAuraBarEffects
RB.CAB_AURA_LCG_KEY = CAB_AURA_LCG_KEY
RB.CAB_PANDEMIC_LCG_KEY = CAB_PANDEMIC_LCG_KEY
