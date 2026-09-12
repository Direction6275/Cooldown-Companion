-- Shared charge fill composition. Charge values go only to native StatusBars;
-- neither the positioning texture nor its dependent regions are read back.
local _, ST = ...
local ChargeBarSegments = {}
ST.ChargeBarSegments = ChargeBarSegments

local function NewBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:EnableMouse(false)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    ST.SetStatusBarImmediateRange(bar, 0, 1)
    ST.SetStatusBarImmediateValue(bar, 0)
    return bar
end

function ChargeBarSegments.Create(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:EnableMouse(false)
    -- Clip fills only. Pixel-aligned borders may straddle the outer rectangle
    -- at preview scale and must not be cut off by the fill containment frame.
    holder.fillClip = CreateFrame("Frame", nil, holder)
    holder.fillClip._ccPreserveHitRectInsets = true
    holder.fillClip:SetAllPoints(holder)
    holder.fillClip:SetClipsChildren(true)
    holder.segments = {}
    -- Sibling of the visible fills: its alpha must not hide the recharge bar.
    holder.positionBar = NewBar(holder.fillClip)
    holder.positionBar:SetAlpha(0)
    holder.positionTexture = holder.positionBar:GetStatusBarTexture()
    holder.rechargeBar = NewBar(holder.fillClip)
    -- One native timer supplies the moving fill rectangle. Fixed segment
    -- windows supply its color, so a cooldown-state transient cannot color
    -- a later charge red. The native fill and its geometry stay write-only.
    holder.rechargeBar:SetAlpha(0)
    holder.rechargeClip = CreateFrame("Frame", nil, holder.fillClip)
    holder.rechargeClip._ccPreserveHitRectInsets = true
    holder.rechargeClip:SetAllPoints(holder.rechargeBar:GetStatusBarTexture())
    holder.rechargeClip:SetClipsChildren(true)
    holder.rechargeClip:Hide()
    holder.rechargeBar:Hide()
    holder:Hide()
    return holder
end

function ChargeBarSegments.Clear(holder)
    if not holder then return end
    ST.SetStatusBarImmediateValue(holder.positionBar, 0)
    ST.SetStatusBarImmediateValue(holder.rechargeBar, 0)
    holder.rechargeBar:Hide()
    holder.rechargeClip:Hide()
    for _, segment in ipairs(holder.segments) do
        ST.SetStatusBarImmediateValue(segment, 0)
        segment:Hide()
        segment.borderHost:Hide()
        segment.rechargeWindow:Hide()
    end
    holder:Hide()
end

-- All layout inputs are ordinary configuration/maximum-charge values.
-- Layout never reads the secret-dependent positioning or recharge geometry.
function ChargeBarSegments.Layout(holder, width, height, maximum, gap, vertical, reverse, style)
    ChargeBarSegments.Clear(holder)
    holder:SetSize(width, height)
    local length = vertical and height or width
    local thickness = vertical and width or height
    maximum = math.max(1, math.floor(maximum))
    gap = maximum > 1 and math.min(math.max(0, gap),
        math.max(0, (length - maximum) / (maximum - 1))) or 0
    local segmentLength = (length - (maximum - 1) * gap) / maximum
    holder.maximum = maximum
    local texture = style.texture or "Interface\\Buttons\\WHITE8X8"
    local ready = style.readyColor or {0.5, 0.5, 1, 1}
    local background = style.backgroundColor or {0, 0, 0, 0.5}
    holder.cooldownColor = style.cooldownColor
    holder.rechargeColor = style.rechargeColor
    local borderColor = style.borderColor or {0, 0, 0, 1}
    local borderSize = math.min(style.borderSize or 1, segmentLength / 2, thickness / 2)
    local borderMode = ST.GetEffectiveBorderRenderMode(style.borderRenderMode, nil, borderSize)
    local inset = style.borderStyle ~= "none" and borderSize > 0
        and ST.GetBorderLayoutSize(holder, borderSize, borderMode) or 0
    inset = math.min(inset, segmentLength / 2, thickness / 2)
    local fillLength, fillThickness = segmentLength - 2 * inset, thickness - 2 * inset
    holder.hasFill = fillLength > 0 and fillThickness > 0
    holder.rechargeInterpolation = style.rechargeInterpolation
    -- WoW frames need nonzero dimensions; border-only tiny segments stay hidden.
    fillLength, fillThickness = math.max(0.001, fillLength), math.max(0.001, fillThickness)
    local orientation = vertical and "VERTICAL" or "HORIZONTAL"
    local origin = vertical and (reverse and "TOPLEFT" or "BOTTOMLEFT")
        or (reverse and "TOPRIGHT" or "TOPLEFT")

    for i = 1, maximum do
        local segment = holder.segments[i]
        if not segment then
            segment = NewBar(holder.fillClip)
            segment.background = segment:CreateTexture(nil, "BACKGROUND")
            segment.borderHost = CreateFrame("Frame", nil, holder)
            segment.borderHost:EnableMouse(false)
            segment.borders = ST.CreateBorderTextureSet(segment.borderHost, "OVERLAY", 7)
            -- Background continues beneath the border, avoiding a one-pixel
            -- seam where fractional segment widths rasterize differently.
            segment.background:SetAllPoints(segment.borderHost)
            segment.rechargeWindow = CreateFrame("Frame", nil, holder.rechargeClip)
            segment.rechargeWindow._ccPreserveHitRectInsets = true
            segment.rechargeWindow:SetAllPoints(segment)
            segment.rechargeWindow:SetClipsChildren(true)
            segment.rechargeTexture = segment.rechargeWindow:CreateTexture(nil, "ARTWORK")
            -- Full-bar texture coordinates, cropped by the native timer's
            -- rectangle and this segment's interior, preserve textured fills.
            segment.rechargeTexture:SetAllPoints(holder.rechargeBar)
            holder.segments[i] = segment
        end
        segment:SetFrameLevel(holder:GetFrameLevel() + 1)
        segment.borderHost:SetFrameLevel(holder:GetFrameLevel() + 2)
        segment.rechargeWindow:SetFrameLevel(holder:GetFrameLevel() + 1)
        segment.borderHost:ClearAllPoints()
        segment.borderHost:SetSize(vertical and thickness or segmentLength, vertical and segmentLength or thickness)
        local offset = (i - 1) * (segmentLength + gap)
        if reverse then offset = -offset end
        segment.borderHost:SetPoint(origin, holder, origin, vertical and 0 or offset, vertical and offset or 0)
        segment:ClearAllPoints()
        segment:SetPoint("TOPLEFT", segment.borderHost, "TOPLEFT", inset, -inset)
        segment:SetSize(vertical and fillThickness or fillLength, vertical and fillLength or fillThickness)
        segment:SetOrientation(orientation)
        segment:SetReverseFill(reverse)
        segment:SetStatusBarTexture(texture)
        segment.rechargeTexture:SetTexture(texture)
        segment:SetStatusBarColor(unpack(ready))
        segment.background:SetColorTexture(unpack(background))
        ST.SetStatusBarImmediateRange(segment, i - 1, i)
        ST.SetStatusBarImmediateValue(segment, 0)
        if style.borderStyle ~= "none" and borderSize > 0 then
            ST.ApplyBorderTextures(segment.borders, segment.borderHost, borderColor, borderSize, borderMode)
        else
            ST.HideBorderTextures(segment.borders)
        end
        if holder.hasFill then
            segment:Show()
            segment.rechargeWindow:Show()
        else
            segment:Hide()
            segment.rechargeWindow:Hide()
        end
        segment.borderHost:Show()
    end

    local positionBar = holder.positionBar
    positionBar:ClearAllPoints()
    positionBar:SetSize(vertical and thickness or length + gap, vertical and length + gap or thickness)
    positionBar:SetPoint(origin, holder, origin, 0, 0)
    positionBar:SetOrientation(orientation)
    positionBar:SetReverseFill(reverse)
    ST.SetStatusBarImmediateRange(positionBar, 0, maximum)
    ST.SetStatusBarImmediateValue(positionBar, 0)

    local rechargeBar = holder.rechargeBar
    rechargeBar:SetFrameLevel(holder:GetFrameLevel() + 1)
    rechargeBar:ClearAllPoints()
    rechargeBar:SetSize(vertical and fillThickness or fillLength, vertical and fillLength or fillThickness)
    rechargeBar:SetOrientation(orientation)
    rechargeBar:SetReverseFill(reverse)
    rechargeBar:SetStatusBarTexture(texture)
    ST.SetStatusBarImmediateRange(rechargeBar, 0, 1)
    if vertical then
        rechargeBar:SetPoint(reverse and "TOPLEFT" or "BOTTOMLEFT", holder.positionTexture,
            reverse and "BOTTOMLEFT" or "TOPLEFT", inset, reverse and -inset or inset)
    else
        rechargeBar:SetPoint(reverse and "TOPRIGHT" or "TOPLEFT", holder.positionTexture,
            reverse and "TOPLEFT" or "TOPRIGHT", reverse and -inset or inset, -inset)
    end
end

function ChargeBarSegments.Update(holder, count, duration, recharging, rechargeColor)
    local hasCount = issecretvalue(count) or count ~= nil
    local showRecharge = holder.hasFill and hasCount and recharging and duration
    if showRecharge then
        -- Timer binding can leave the previous rendered fill until the native
        -- timer update. Seed the exact current fraction before the charge edge
        -- moves, so a completed fill cannot travel into the next segment.
        -- The possibly-secret fraction goes straight to the native setter.
        ST.SetStatusBarImmediateValue(holder.rechargeBar, duration:GetElapsedPercent())
        ST.SetStatusBarElapsedDuration(holder.rechargeBar, duration, holder.rechargeInterpolation)
    else
        ST.SetStatusBarImmediateValue(holder.rechargeBar, 0)
        holder.rechargeBar:Hide()
        holder.rechargeClip:Hide()
    end
    if hasCount then
        ST.SetStatusBarImmediateValue(holder.positionBar, count)
    else
        ST.SetStatusBarImmediateValue(holder.positionBar, 0)
    end
    for i = 1, holder.maximum do
        local segment = holder.segments[i]
        local color = (i == 1 and holder.cooldownColor or holder.rechargeColor) or rechargeColor
        segment.rechargeTexture:SetVertexColor(unpack(color))
        if hasCount then
            ST.SetStatusBarImmediateValue(segment, count)
        else
            ST.SetStatusBarImmediateValue(segment, 0)
        end
        if holder.hasFill then
            segment:Show()
            segment.rechargeWindow:Show()
        else
            segment:Hide()
            segment.rechargeWindow:Hide()
        end
        segment.borderHost:Show()
    end
    if showRecharge then
        holder.rechargeBar:Show()
        holder.rechargeClip:Show()
    end
    holder:Show()
end


-- Host composition shared by runtime and previews. Only ordinary host bounds
-- are read; the positioning texture and recharge bar remain write-only.
function ChargeBarSegments.End(host, color)
    local holder = host and host._chargeSegments
    if not (holder and holder._attached) then return end
    holder._attached = nil
    ChargeBarSegments.Clear(holder)
    holder._fillTexture:SetAlpha(1)
    local restore = color or holder._restoreColor
    if restore then host:SetStatusBarColor(unpack(restore)) end
    if holder._background then
        if holder._backgroundWasShown then holder._background:Show() else holder._background:Hide() end
    end
    for i, border in ipairs(holder._borders or {}) do
        if holder._borderWasShown[i] then border:Show() else border:Hide() end
    end
end

function ChargeBarSegments.Invalidate(host)
    if not host then return end
    ChargeBarSegments.End(host)
    host._chargePaint = nil
    if host._chargeSegments then host._chargeSegments._paint = nil end
end

function ChargeBarSegments.Begin(host, bounds, width, height, maximum, gap, vertical, reverse,
        paint, background, borders, restoreColor)
    if width <= 0 or height <= 0 then
        ChargeBarSegments.End(host, restoreColor)
        return nil
    end
    local holder = host._chargeSegments
    if not holder then
        holder = ChargeBarSegments.Create(host)
        holder:SetFrameLevel(host:GetFrameLevel())
        holder:SetPoint("TOPLEFT", bounds, "TOPLEFT", 0, 0)
        holder._fillTexture = host:GetStatusBarTexture()
        host._chargeSegments = holder
    end
    local scale = host:GetEffectiveScale()
    if holder._scale ~= scale or holder.maximum ~= maximum or holder._width ~= width or holder._height ~= height
        or holder._gap ~= gap or holder._vertical ~= vertical or holder._reverse ~= reverse
        or holder._paint ~= paint then
        ChargeBarSegments.Layout(holder, width, height, maximum, gap, vertical, reverse, paint)
        holder._scale = scale
        holder._width, holder._height, holder._gap = width, height, gap
        holder._vertical, holder._reverse, holder._paint = vertical, reverse, paint
    end
    holder._background, holder._borders, holder._restoreColor = background, borders, restoreColor
    if not holder._attached then
        -- These are CC-owned shell regions, never native aura descendants or
        -- charge-positioning regions. Preserve an intentionally disabled border.
        holder._backgroundWasShown = background and background:IsShown()
        holder._borderWasShown = holder._borderWasShown or {}
        for i, border in ipairs(borders or {}) do holder._borderWasShown[i] = border:IsShown() end
    end
    holder._attached = true
    holder._fillTexture:SetAlpha(0)
    if background then background:Hide() end
    for _, border in ipairs(borders or {}) do border:Hide() end
    return holder
end

function ChargeBarSegments.Preview(holder, count, percent, color)
    ChargeBarSegments.Update(holder, count, nil, false, color)
    if holder.hasFill and percent ~= nil then
        ST.SetStatusBarImmediateValue(holder.rechargeBar, percent)
        holder.rechargeBar:Show()
        holder.rechargeClip:Show()
    end
end

function ChargeBarSegments.PaintPanel(owner, count, maximum, duration, recharging, rechargeColor, previewPercent)
    local style, data, host = owner.style, owner.buttonData, owner.statusBar
    if style.barSegmentCharges ~= true
        and not (host._chargeSegments and host._chargeSegments._attached) then return false end
    local restore = owner._barCdColor or style.barColor or {0.2, 0.6, 1, 1}
    if style.barSegmentCharges ~= true or not data or data.type ~= "spell"
        or data.addedAs == "aura" or data.hasCharges ~= true
        or not maximum or maximum <= 1 then
        ChargeBarSegments.End(host, restore)
        return false
    end
    local paint = host._chargePaint
    if not paint then
        paint = {
            texture = ST.Addon:FetchEffectiveBarTexture(style.barTexture or "Solid"),
            rechargeInterpolation = Enum.StatusBarInterpolation.Immediate,
            readyColor = style.barColor or {0.2, 0.6, 1, 1},
            cooldownColor = style.barCooldownColor or {0.6, 0.13, 0.18, 1},
            rechargeColor = style.barChargeColor or {1, 0.82, 0, 1},
            backgroundColor = style.barBgColor or {0.1, 0.1, 0.1, 0.8},
            borderColor = style.borderColor or {0, 0, 0, 1},
            borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE,
            borderRenderMode = ST.GetBorderRenderMode(style),
        }
        host._chargePaint = paint
    end
    local vertical = style.barFillVertical == true
    local width, height = owner:GetSize()
    if style.showBarIcon ~= false then
        local iconSize = (style.barIconSizeOverride and style.barIconSize) or style.barHeight or 20
        local reserved = iconSize + (style.barIconOffset or 0)
        if vertical then height = height - reserved else width = width - reserved end
    end
    local holder = ChargeBarSegments.Begin(host, owner._barBounds or owner.barBounds,
        width, height, maximum, style.barChargeSegmentGap or 4, vertical,
        style.barReverseFill == true, paint, owner.bg, owner.borderTextures, restore)
    if not holder then return false end
    if previewPercent ~= nil then
        ChargeBarSegments.Preview(holder, count, previewPercent, rechargeColor)
    else
        ChargeBarSegments.Update(holder, count, duration, recharging, rechargeColor)
    end
    return true
end
