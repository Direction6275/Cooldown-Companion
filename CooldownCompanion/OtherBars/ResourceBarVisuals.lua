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

local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local issecretvalue = issecretvalue

-- Import from ResourceBarConstants & ResourceBarHelpers
local RB = ST._RB
local POWER_ATLAS_INFO = RB.POWER_ATLAS_INFO
local DEFAULT_CONTINUOUS_TICK_COLOR = RB.DEFAULT_CONTINUOUS_TICK_COLOR
local IsVerticalResourceLayout = RB.IsVerticalResourceLayout
local IsVerticalFillReversed = RB.IsVerticalFillReversed
local GetCurrentSpecID = RB.GetCurrentSpecID
local GetResourceColors = RB.GetResourceColors
local GetContinuousTickEntriesConfig = RB.GetContinuousTickEntriesConfig
local GetSpecResourceDisplayProfile = RB.GetSpecResourceDisplayProfile

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

local function ApplyContinuousFillColor(bar, powerType, settings)
    if not bar or not settings then return end

    local style = GetResourceDisplayStyle(settings)
    local texName = bar._effectiveBarTextureName or ST.GetEffectiveBarTextureName(style and style.barTexture or "Solid")
    local atlasInfo = (texName == "blizzard_class") and POWER_ATLAS_INFO[powerType] or nil
    if atlasInfo then
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

    local color = GetResourceColors(powerType, settings)
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

    -- Text container above the fill. +2 is the CUSTOM BAR height and the
    -- factory default: spell custom bars rely on their aura kit (holder at
    -- bar+3) occluding CC's per-tick cooldown text while an aura shows, so
    -- their text must stay beneath it. Resource bars restyle the layer up
    -- to RESOURCE_TEXT_LAYER_LEVEL (StyleContinuousBar / HealthBar), where
    -- text wins over every bar's fills and kit visuals.
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

    -- Segmented bars are resource-only, so the text layer mounts straight
    -- into the stack's text band (see RESOURCE_TEXT_LAYER_LEVEL).
    holder.textLayer = CreateFrame("Frame", nil, holder)
    holder.textLayer:SetAllPoints(holder)
    holder.textLayer:SetFrameLevel(holder:GetFrameLevel() + RB.RESOURCE_TEXT_LAYER_LEVEL)

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

-- Re-segment an existing segmented holder in place. WoW never destroys a
-- frame, so a shape whose segment count MOVES at runtime — the aura-stack
-- family, whose maximum follows talents and the Devourer meta swap — cannot
-- rebuild its holder on every change without accumulating orphans for the
-- session. The holder instead grows to its high-water mark and parks the
-- rest: LayoutSegments already lays out `_activeSegments` and hides every
-- segment past it, so only the growth and the bookkeeping live here.
-- Shapes whose count is effectively fixed (Maelstrom Weapon, the plain
-- segmented resources) never call this and keep their rebuild.
local function EnsureSegmentCount(holder, n)
    if not holder or not holder.segments then return end
    n = math_floor(tonumber(n) or 0)
    if n < 1 then n = 1 end

    local existing = #holder.segments
    if n > existing then
        local textFont = CooldownCompanion:FetchFont("Friz Quadrata TT")
        local textOutline = ST.GetEffectiveFontOutline("OUTLINE")
        for i = existing + 1, n do
            local seg = CreateFrame("StatusBar", nil, holder)
            seg:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
            seg:SetMinMaxValues(0, 1)
            SetStatusBarImmediateValue(seg, 0)

            seg.bg = seg:CreateTexture(nil, "BACKGROUND")
            seg.bg:SetAllPoints()
            seg.bg:SetColorTexture(0, 0, 0, 0.5)

            seg.borders = CreatePixelBorders(seg)

            holder.segments[i] = seg

            if holder.rechargeTexts and holder.textLayer then
                local text = holder.textLayer:CreateFontString(nil, "OVERLAY")
                text:SetFont(textFont, 10, textOutline)
                ST.ApplyFontShadowForOutline(text, textOutline)
                text:SetPoint("CENTER", seg, "CENTER", 0, 0)
                text:SetTextColor(1, 1, 1, 1)
                text:Hide()
                holder.rechargeTexts[i] = text
            end
        end
    end

    holder._activeSegments = n
    holder._numSegments = n
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
        end
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

    -- Overlay bars are resource-only (MW), so the text layer mounts straight
    -- into the stack's text band (see RESOURCE_TEXT_LAYER_LEVEL).
    holder.textLayer = CreateFrame("Frame", nil, holder)
    holder.textLayer:SetAllPoints(holder)
    holder.textLayer:SetFrameLevel(holder:GetFrameLevel() + RB.RESOURCE_TEXT_LAYER_LEVEL)

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
    end

end

------------------------------------------------------------------------
-- Add all visual functions to ST._RB
------------------------------------------------------------------------

RB.GetActiveResourceAuraEntry = GetActiveResourceAuraEntry
RB.GetResourceAuraTrackingMode = GetResourceAuraTrackingMode
RB.IsResourceAuraOverlayEnabled = IsResourceAuraOverlayEnabled
RB.UpdateContinuousTickMarker = UpdateContinuousTickMarker
RB.ApplyContinuousFillColor = ApplyContinuousFillColor
RB.CreatePixelBorders = CreatePixelBorders
RB.ApplyPixelBorders = ApplyPixelBorders
RB.HidePixelBorders = HidePixelBorders
RB.CreateContinuousBar = CreateContinuousBar
RB.CreateSegmentedBar = CreateSegmentedBar
RB.EnsureSegmentCount = EnsureSegmentCount
RB.LayoutSegments = LayoutSegments
RB.CreateOverlayBar = CreateOverlayBar
RB.LayoutOverlaySegments = LayoutOverlaySegments
