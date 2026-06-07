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
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue

local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local issecretvalue = issecretvalue

-- Import from ResourceBarConstants & ResourceBarHelpers
local RB = ST._RB
local POWER_ATLAS_INFO = RB.POWER_ATLAS_INFO
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = RB.DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
local DEFAULT_CUSTOM_AURA_MAX_COLOR = RB.DEFAULT_CUSTOM_AURA_MAX_COLOR
local DEFAULT_CONTINUOUS_TICK_COLOR = RB.DEFAULT_CONTINUOUS_TICK_COLOR
local RESOURCE_MAELSTROM_WEAPON = RB.RESOURCE_MAELSTROM_WEAPON
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local MAX_RESOURCE_THRESHOLD_TICK_ENTRIES = RB.MAX_RESOURCE_THRESHOLD_TICK_ENTRIES or 3

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

    local configUnit = GetResolvedResourceAuraUnit and GetResolvedResourceAuraUnit(auraEntry, auraSpellID) or "player"
    local cacheKey = configUnit .. ":" .. auraSpellID
    local cached
    if auraActiveCache then
        cached = auraActiveCache[cacheKey]
    end

    if not cached then
        cached = { active = false, applications = nil, hasApplications = false }

        if C_CVar.GetCVarBool("cooldownViewerEnabled") then
            local viewerFrame = CooldownCompanion.viewerAuraFrames and CooldownCompanion.viewerAuraFrames[auraSpellID]
            local instId = viewerFrame and viewerFrame.auraInstanceID
            if instId then
                local viewerUnit = viewerFrame.auraDataUnit or configUnit
                if viewerUnit == configUnit then
                    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(configUnit, instId)
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
        end

        if not cached.active and configUnit == "player" then
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
            auraActiveCache[cacheKey] = cached
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

    local count = #auraSegments
    for i = 1, count do
        local seg = auraSegments[i]
        local segMin = ((i - 1) * maxStacks) / count
        local segMax = (i * maxStacks) / count
        SetStatusBarSmoothRange(seg, segMin, segMax)
        SetStatusBarSmoothValue(seg, stackValue)
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

local function EnsureContinuousTickMarkers(bar)
    if not bar then return nil end
    if type(bar.tickMarkers) ~= "table" then
        bar.tickMarkers = {}
        if bar.tickMarker then
            bar.tickMarkers[1] = bar.tickMarker
        end
    end
    for index = 1, MAX_RESOURCE_THRESHOLD_TICK_ENTRIES do
        if not bar.tickMarkers[index] then
            bar.tickMarkers[index] = bar:CreateTexture(nil, "OVERLAY", nil, 6)
            bar.tickMarkers[index]:SetColorTexture(1, 0.84, 0, 1)
            bar.tickMarkers[index]:Hide()
        end
    end
    bar.tickMarker = bar.tickMarkers[1]
    return bar.tickMarkers
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

    local markers = EnsureContinuousTickMarkers(bar)
    local shownCount = 0
    local halfTick = tickWidth / 2

    for index, entry in ipairs(entries) do
        if index > MAX_RESOURCE_THRESHOLD_TICK_ENTRIES then
            break
        end
        local ratio = mode == "absolute" and (entry.value / maxPower) or (entry.value / 100)
        if ratio < 0 then
            ratio = 0
        elseif ratio > 1 then
            ratio = 1
        end

        local marker = markers[index]
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

local function EnsureMaxStacksIndicator(barInfo)
    if barInfo._maxStacksIndicator then return barInfo._maxStacksIndicator end
    local indicator = CreateFrame("StatusBar", nil, barInfo.frame)
    indicator:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    indicator:EnableMouse(false)
    indicator:Show()
    barInfo._maxStacksIndicator = indicator
    return indicator
end

local function LayoutMaxStacksIndicator(barInfo, cabConfig, maxStacks, barTexture, borderStyle, borderSize, borderRenderMode)
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
            local inset = ST.GetEffectiveBorderLayoutSize(frame, borderSize, borderRenderMode)
            indicator:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
            indicator:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
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
    SetStatusBarImmediateValue(indicator, 0)
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
    bar.text:SetFont(CooldownCompanion:FetchFont("Friz Quadrata TT"), 10, ST.GetEffectiveFontOutline("OUTLINE"))
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

    holder.text = holder.textLayer:CreateFontString(nil, "OVERLAY")
    holder.text:SetFont(CooldownCompanion:FetchFont("Friz Quadrata TT"), 10, ST.GetEffectiveFontOutline("OUTLINE"))
    holder.text:SetPoint("CENTER")
    holder.text:SetTextColor(1, 1, 1, 1)
    holder.text:Hide()

    holder.rechargeTexts = {}
    for i = 1, numSegments do
        local text = holder.textLayer:CreateFontString(nil, "OVERLAY")
        text:SetFont(CooldownCompanion:FetchFont("Friz Quadrata TT"), 10, ST.GetEffectiveFontOutline("OUTLINE"))
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
    holder.text:SetFont(CooldownCompanion:FetchFont("Friz Quadrata TT"), 10, ST.GetEffectiveFontOutline("OUTLINE"))
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
