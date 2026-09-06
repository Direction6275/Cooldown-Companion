--[[
    CooldownCompanion - ButtonPanelPreviewBars
    Bar-slot styling, ready/charge/aura presentation, and fill effects.

    Part of the ButtonPanelPreview family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._ButtonPanelPreview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local math_max = math.max
local SetIconAreaPoints = ST._SetIconAreaPoints
local SetBarAreaPoints = ST._SetBarAreaPoints
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions
local GetConditionalPreviewTiming = ST._GetConditionalPreviewTiming
local ApplyBarCountTextStyle = ST._ApplyBarCountTextStyle
local DEFAULT_BAR_CHARGE_COLOR = ST._DEFAULT_BAR_CHARGE_COLOR
local ResolveBarAuraFillColor = ST.ResolveBarAuraFillColor

local PP = ST._ButtonPanelPreview

-- ButtonPanelPreviewShared.lua
local DEFAULT_BAR_READY_TEXT_COLOR = PP.DEFAULT_BAR_READY_TEXT_COLOR
local GetStoredBarPreviewState = PP.GetStoredBarPreviewState
local IsBarPreviewAuraActive = PP.IsBarPreviewAuraActive
local UsesConfigOnlyBarChargeBehavior = ST._UsesConfigOnlyBarChargeBehavior
local DEFAULT_BAR_COLOR = PP.DEFAULT_BAR_COLOR
local GetConfigOnlyBarPreviewIcon = PP.GetConfigOnlyBarPreviewIcon
local GetConfigOnlyBarPreviewName = PP.GetConfigOnlyBarPreviewName

-- ButtonPanelPreviewIcons.lua
local FormatAuraDurationPreviewText = PP.FormatAuraDurationPreviewText
local IsAuraDurationTextKind = PP.IsAuraDurationTextKind
local EnsureSlotCountText = PP.EnsureSlotCountText
local EnsureSlotLocCooldown = PP.EnsureSlotLocCooldown

------------------------------------------------------------------------
-- Bar-slot conditional previews: same stored state and timing, rendered
-- per BarMode.lua's recipes (UpdateBarFill drain/fill + time text,
-- UpdateBarDisplay colors and fill effects).
------------------------------------------------------------------------
local function EnsureBarSlotTimeText(slot)
    if not slot.timeText then
        slot.timeText = slot.textFrame:CreateFontString(nil, "OVERLAY")
    end
    return slot.timeText
end

local function EnsureBarSlotAuraStackText(slot)
    if not slot.auraStackCount then
        slot.auraStackCount = slot.textFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    end
    return slot.auraStackCount
end

-- Time text placement per BarMode.lua CreateBarFrame, including the
-- name/time overlap guard when both sit on the same side.
local function AnchorBarSlotTimeText(slot, style)
    local tt = slot.timeText
    local isVertical = style.barFillVertical or false
    local cdOffX = style.barCdTextOffsetX or 0
    local cdOffY = style.barCdTextOffsetY or 0
    local timeReverse = style.barTimeTextReverse
    tt:ClearAllPoints()
    if isVertical then
        if timeReverse then
            tt:SetPoint("BOTTOM", cdOffX, 3 + cdOffY)
        else
            tt:SetPoint("TOP", cdOffX, -3 + cdOffY)
        end
        tt:SetJustifyH("CENTER")
    else
        if timeReverse then
            tt:SetPoint("LEFT", 3 + cdOffX, cdOffY)
            tt:SetJustifyH("LEFT")
        else
            tt:SetPoint("RIGHT", -3 + cdOffX, cdOffY)
            tt:SetJustifyH("RIGHT")
        end
    end
    -- Raw comparison like live (nil and false differ deliberately there)
    if not isVertical and style.barNameTextReverse == style.barTimeTextReverse
        and slot.nameText and slot.nameText:IsShown() then
        if style.barNameTextReverse then
            slot.nameText:SetPoint("LEFT", tt, "RIGHT", 4, 0)
        else
            slot.nameText:SetPoint("RIGHT", tt, "LEFT", -4, 0)
        end
    end
end

local function ApplyBarReadyPresentation(slot, buttonData, style)
    local tt = EnsureBarSlotTimeText(slot)
    AnchorBarSlotTimeText(slot, style)
    local font = CooldownCompanion:FetchFont(style.barReadyFont or "Friz Quadrata TT")
    local size = style.barReadyFontSize or 12
    local outline = ST.GetEffectiveFontOutline(style.barReadyFontOutline or "OUTLINE")
    tt:SetFont(font, size, outline)
    ST.ApplyFontShadowForOutline(tt, outline)
    if buttonData.isPassive or style.showBarReadyText ~= true then
        tt:SetText("")
        return
    end

    local color = style.barReadyTextColor or DEFAULT_BAR_READY_TEXT_COLOR
    tt:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    tt:SetText(style.barReadyText or "Ready")
    tt:Show()
end

-- Self-animating bar fill: aura previews drain (1->0) like the live kit
-- bar, cooldowns fill (0->1), per BarMode.lua UpdateBarFill.
local function BarSlotFillOnUpdate(self)
    local slot = self._cdcOwner
    local state = slot and slot._cdcCondAnim
    if not (state and GetConditionalPreviewTiming) then return end
    local startTime, duration, remaining = GetConditionalPreviewTiming(state, GetTime())
    if not (startTime and duration and duration > 0) then return end
    local frac
    if state.kind == "aura_duration_bar" then
        frac = remaining / duration
    else
        frac = 1 - (remaining / duration)
    end
    if frac < 0 then frac = 0 end
    if frac > 1 then frac = 1 end
    self:SetValue(frac)
end

-- Effective pandemic enable for a mirror entry: the explicit-true style key.
-- The style handed in is always the entry's EFFECTIVE style (slot.style), so an
-- entry that customized the Pandemic section answers with its own stored value
-- — the same resolution the live bind gate performs (AuraDisplay.lua
-- StyleSlotKit).
local function IsPandemicPreviewEnabled(style, buttonData)
    return style and style.pandemicEffectEnabled == true
end

local function StopBarSlotFillEffects(slot)
    if slot._cdcFillPulseAG then slot._cdcFillPulseAG:Stop() end
    if slot._cdcFillShiftAG then slot._cdcFillShiftAG:Stop() end
    local fillTex = slot.statusBar and slot.statusBar:GetStatusBarTexture()
    if fillTex then
        -- Clears residual shift tint; 4-arg SetVertexColor is the last alpha
        -- write on this mirror region.
        fillTex:SetVertexColor(1, 1, 1, 1)
    end
end

-- Active Aura Indicator fill effects on the mirror bar. Returns true when the
-- color-shift animation owns the fill color (the bar then goes white underneath,
-- matching the kit's layering trick).
-- suppressShift: the pandemic recolor occludes the live fill's color shift
-- (the kit clone draws over the shifting fill), so the mirror must not let
-- the shift animation own the color while the pandemic preview runs — the
-- pulse still applies, matching the clone inheriting the fill frame's
-- pulse alpha.
local function ApplyBarSlotFillEffects(slot, style, auraColor, suppressShift)
    local fillTex = slot.statusBar:GetStatusBarTexture()
    if not fillTex then return false end
    if style.barAuraPulseEnabled == true then
        if not slot._cdcFillPulseAG then
            local ag = fillTex:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local anim = ag:CreateAnimation("Alpha")
            anim:SetFromAlpha(1.0)
            anim:SetToAlpha(0.3)
            slot._cdcFillPulseAG = ag
            slot._cdcFillPulseAnim = anim
        end
        slot._cdcFillPulseAnim:SetDuration(style.barAuraPulseSpeed or 0.5)
        slot._cdcFillPulseAG:Play()
    end
    if not suppressShift and style.barAuraColorShiftEnabled == true then
        if not slot._cdcFillShiftAG then
            local ag = fillTex:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            slot._cdcFillShiftAG = ag
            slot._cdcFillShiftAnim = ag:CreateAnimation("VertexColor")
        end
        local shiftC = style.barAuraColorShiftColor or { 1, 1, 1, 1 }
        slot._cdcFillShiftAnim:SetStartColor(CreateColor(
            auraColor[1], auraColor[2], auraColor[3], auraColor[4] or 1))
        slot._cdcFillShiftAnim:SetEndColor(CreateColor(shiftC[1], shiftC[2], shiftC[3], shiftC[4] or 1))
        slot._cdcFillShiftAnim:SetDuration(style.barAuraColorShiftSpeed or 0.5)
        slot._cdcFillShiftAG:Play()
        return true
    end
    return false
end

-- Cleanup runs before StyleBarEntry so its neutral texture tint cannot win
-- over the final saved or simulated status-bar color.
local function ResetBarSlotConditionalVisuals(slot)
    slot._cdcCondAnim = nil
    slot._cdcCondArmedStart = nil
    if slot.statusBar then
        slot.statusBar:SetScript("OnUpdate", nil)
    end
    StopBarSlotFillEffects(slot)
    if slot.timeText then
        slot.timeText:SetText("")
    end
    if slot.auraStackCount then
        slot.auraStackCount:SetText("")
        slot.auraStackCount:Hide()
    end
    if slot.count then
        slot.count:SetText("")
    end
    if slot.locCooldown then
        slot.locCooldown:Clear()
        slot.locCooldown:Hide()
    end
end

local function ApplyBarAuraTimeTextPreview(slot, style, remaining, kind, buttonData)
    if style.showAuraText == false then return end
    local tt = EnsureBarSlotTimeText(slot)
    local font = CooldownCompanion:FetchFont(style.auraTextFont or "Friz Quadrata TT")
    local size = style.auraTextFontSize or 12
    local outline = ST.GetEffectiveFontOutline(style.auraTextFontOutline or "OUTLINE")
    tt:SetFont(font, size, outline)
    ST.ApplyFontShadowForOutline(tt, outline)
    local color = style.auraTextFontColor or CooldownCompanion.DEFAULT_AURA_TEXT_COLOR
    tt:SetTextColor(color[1], color[2], color[3], color[4])
    AnchorBarSlotTimeText(slot, style)
    tt:SetText(FormatAuraDurationPreviewText(remaining, kind, style, buttonData,
        slot._cdcAuraLowTime))
    tt:Show()
end

local function ApplyBarSlotConditionalPreview(slot, buttonData, group, panelId, index,
        style, previewState)
    -- Read by ApplyBarCountTextStyle
    slot.buttonData = buttonData

    style = style or slot.style or group.style or {}
    -- Same ticker stamp as the icon slots (see ApplySlotConditionalPreview).
    local isAuraPanel = ST.IsAuraPanelGroup(group)
    slot._cdcAuraLowTime = CooldownCompanion.AllowAuraDurationLowTime(
        style, isAuraPanel
            or ST.IsAuraSectionEntry(group, buttonData))
    -- Bars run the same icon tint pipeline live (UpdateIconTint on the
    -- bar icon); baseline restored every rebuild like the icon slots.
    local baseTint = style.iconTintColor
    local tintR = baseTint and baseTint[1] or 1
    local tintG = baseTint and baseTint[2] or 1
    local tintB = baseTint and baseTint[3] or 1
    local tintA = baseTint and baseTint[4] or 1
    local forceDesat = false

    previewState = previewState or GetStoredBarPreviewState(panelId, index)
    local state = previewState.conditional
    local kind = state and state.kind or nil
    local effectFlags = previewState.effectFlags
    local now = GetTime()
    -- Union predicate on purpose: any aura preview simulates "the aura is
    -- active", not just the duration-bar drain.
    local auraPresentationActive = IsBarPreviewAuraActive(state, effectFlags)
    local isAuraEntry = buttonData.type == "spell"
        and (buttonData.auraTracking == true or buttonData.addedAs == "aura")
    if isAuraEntry then
        if auraPresentationActive then
            -- Live needs the bar icon square: the aura layer's cover is
            -- what carries the gray (StyleSlotKit coverWanted).
            forceDesat = style.showBarIcon ~= false
                and CooldownCompanion:ShouldDesaturateAuraLayerWhileActive(buttonData, style)
        elseif buttonData.isPassive then
            forceDesat = not (buttonData.neverDesaturate
                or style.invertAuraDesaturationLogic)
        else
            forceDesat = style.desaturateWhileAuraNotActive == true
        end
    end

    -- Deterministic preview-off fill matches the live ready-state rule.
    -- Timed condition previews below replace this baseline when active.
    slot.statusBar:SetValue(buttonData.isPassive and 0 or 1)

    local chargePresentationKind = kind
    if not chargePresentationKind and UsesConfigOnlyBarChargeBehavior(buttonData) then
        chargePresentationKind = "charge_full"
    end

    if (kind == "cooldown" or kind == "cooldown_text" or IsAuraDurationTextKind(kind))
        and slot.timeText then
        slot.timeText:SetText("")
    end

    if kind == "aura_duration_bar" then
        local auraTint = style.iconAuraTintEnabled and style.iconAuraTintColor or baseTint
        tintR = auraTint and auraTint[1] or 1
        tintG = auraTint and auraTint[2] or 1
        tintB = auraTint and auraTint[3] or 1
        tintA = auraTint and auraTint[4] or 1
        local auraColor = ResolveBarAuraFillColor(style, buttonData, isAuraPanel)
        slot.statusBar:SetStatusBarColor(auraColor[1], auraColor[2], auraColor[3], auraColor[4] or 1)
    end

    if IsAuraDurationTextKind(kind) and GetConditionalPreviewTiming then
        local startTime, _, remaining = GetConditionalPreviewTiming(state, now)
        if startTime then
            slot._cdcCondAnim = state
            ApplyBarAuraTimeTextPreview(slot, style, remaining, kind, buttonData)
        end
    elseif kind == "aura_duration_bar" and GetConditionalPreviewTiming then
        local startTime = GetConditionalPreviewTiming(state, now)
        if startTime then
            -- The Active Aura Indicator preview's fill effects ride the
            -- mirror's aura drain.
            -- Pandemic recolor (PTR 8): live parity is the kit's clone
            -- occluding the fill — including its color shift — while still
            -- inheriting the fill pulse. So with the pandemic preview on,
            -- the fill effects run pulse-only (shift suppressed: a playing
            -- VertexColor animation owns the color channel and the recolor
            -- would never show) and the base color is the pandemic color.
            local pandemicActive = effectFlags and effectFlags._pandemicPreview == true
                and IsPandemicPreviewEnabled(style, buttonData)
            local fxActive = effectFlags
                and (effectFlags._barAuraEffectPreview == true or pandemicActive)
                and ST.IsBarAuraIndicatorEnabled
                and ST.IsBarAuraIndicatorEnabled(style) == true
            local shifted = false
            local auraColor = ResolveBarAuraFillColor(style, buttonData, isAuraPanel)
            if fxActive then
                shifted = ApplyBarSlotFillEffects(slot, style, auraColor, pandemicActive)
            end
            if pandemicActive then
                -- Forced opaque, matching the live clone (owner ruling: the
                -- pandemic color replaces the aura fill color, never blends).
                local pc = style.barPandemicColor or { 1, 0.5, 0, 1 }
                slot.statusBar:SetStatusBarColor(pc[1] or 1, pc[2] or 0.5, pc[3] or 0, 1)
            elseif shifted then
                -- White base while the shift animation owns the color.
                slot.statusBar:SetStatusBarColor(1, 1, 1, auraColor[4] or 1)
            else
                slot.statusBar:SetStatusBarColor(auraColor[1], auraColor[2], auraColor[3], auraColor[4] or 1)
            end
            slot.statusBar._cdcOwner = slot
            slot.statusBar:SetScript("OnUpdate", BarSlotFillOnUpdate)
            slot._cdcCondAnim = state
            BarSlotFillOnUpdate(slot.statusBar)
        end
    elseif kind == "cooldown" and GetConditionalPreviewTiming then
        local startTime, duration, remaining = GetConditionalPreviewTiming(state, now)
        if startTime then
            if not buttonData.isPassive then
                local c = style.barCooldownColor or style.barColor or DEFAULT_BAR_COLOR
                slot.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                if style.desaturateOnCooldown then
                    forceDesat = true
                end
                if style.iconCooldownTintEnabled and style.iconCooldownTintColor then
                    local iconTint = style.iconCooldownTintColor
                    tintR = iconTint[1] or 1
                    tintG = iconTint[2] or 1
                    tintB = iconTint[3] or 1
                    tintA = iconTint[4] or 1
                end
            end
            slot.statusBar._cdcOwner = slot
            slot.statusBar:SetScript("OnUpdate", BarSlotFillOnUpdate)
            slot._cdcCondAnim = state
            BarSlotFillOnUpdate(slot.statusBar)
            if style.showCooldownText then
                local tt = EnsureBarSlotTimeText(slot)
                CooldownCompanion.ApplyFontStyle(tt, style, "cooldown")
                AnchorBarSlotTimeText(slot, style)
                tt:SetText(CooldownCompanion.FormatCooldownTime(remaining, style))
                tt:Show()
            end
        end
    elseif kind == "cooldown_text" and GetConditionalPreviewTiming then
        -- Countdown text alone on a resting bar: no drain, no cooldown color,
        -- no desaturation or tint.
        -- The conditional ticker keeps the text counting via _cdcCondAnim.
        local startTime, _, remaining = GetConditionalPreviewTiming(state, now)
        if startTime and not buttonData.isPassive and style.showCooldownText then
            local tt = EnsureBarSlotTimeText(slot)
            CooldownCompanion.ApplyFontStyle(tt, style, "cooldown")
            AnchorBarSlotTimeText(slot, style)
            tt:SetText(CooldownCompanion.FormatCooldownTime(remaining, style))
            tt:Show()
            slot._cdcCondAnim = state
        end
    elseif chargePresentationKind == "charge_full"
        or chargePresentationKind == "charge_missing"
        or chargePresentationKind == "charge_zero" then
        if UsesConfigOnlyBarChargeBehavior(buttonData) then
            local maxCharges = buttonData.maxCharges or 2
            if maxCharges < 2 then maxCharges = 2 end
            local current = maxCharges
            local colorKey = "chargeFontColor"
            if chargePresentationKind == "charge_missing" then
                current = math_max(1, maxCharges - 1)
                colorKey = "chargeFontColorMissing"
            elseif chargePresentationKind == "charge_zero" then
                current = 0
                colorKey = "chargeFontColorZero"
            end

            if chargePresentationKind ~= "charge_full" and slot.timeText then
                slot.timeText:SetText("")
            end

            local count = EnsureSlotCountText(slot)
            if ApplyBarCountTextStyle then
                ApplyBarCountTextStyle(slot, style)
            end
            if style.showChargeText ~= false then
                count:SetText(current)
            end
            if style.chargeFontColor or style.chargeFontColorMissing or style.chargeFontColorZero then
                local cc = style[colorKey] or { 1, 1, 1, 1 }
                count:SetTextColor(cc[1], cc[2], cc[3], cc[4] or 1)
            end

            -- Bar color per UpdateBarDisplay's charge states
            if not buttonData.isPassive then
                if chargePresentationKind == "charge_missing" then
                    local c = style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR or { 1, 0.8, 0.2, 1 }
                    slot.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                elseif chargePresentationKind == "charge_zero" then
                    local c = style.barCooldownColor or style.barColor or DEFAULT_BAR_COLOR
                    slot.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                end
            end

            if chargePresentationKind ~= "charge_full" and GetConditionalPreviewTiming then
                -- Charge previews have no live recharge object. Use a stable
                -- local 12-second sample with 8 seconds remaining so the Bar
                -- mirror still demonstrates runtime-equivalent fill and text.
                local rechargeDuration = 12
                local rechargeRemaining = 8
                local rechargeElapsed = rechargeDuration - rechargeRemaining
                local rechargeState = {
                    kind = "cooldown",
                    duration = rechargeDuration,
                    startTime = now - rechargeElapsed,
                    loop = true,
                    loopDuration = rechargeDuration,
                    loopStartTime = now - rechargeElapsed,
                }
                slot.statusBar._cdcOwner = slot
                slot.statusBar:SetScript("OnUpdate", BarSlotFillOnUpdate)
                slot._cdcCondAnim = rechargeState
                BarSlotFillOnUpdate(slot.statusBar)
                if style.showCooldownText then
                    local tt = EnsureBarSlotTimeText(slot)
                    CooldownCompanion.ApplyFontStyle(tt, style, "cooldown")
                    AnchorBarSlotTimeText(slot, style)
                    tt:SetText(CooldownCompanion.FormatCooldownTime(rechargeRemaining, style))
                    tt:Show()
                end
            end

            if chargePresentationKind == "charge_zero" then
                if style.desaturateOnCooldown
                    or (buttonData.desaturateWhileZeroCharges
                        and not (CooldownCompanion.HasItemFallbacks
                            and CooldownCompanion.HasItemFallbacks(buttonData))) then
                    forceDesat = true
                end
                if style.iconCooldownTintEnabled and style.iconCooldownTintColor then
                    local c = style.iconCooldownTintColor
                    tintR, tintG, tintB, tintA = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end
            end
        end
    elseif kind == "unusable" then
        if style.showUnusable
            and not (buttonData.isPassive or buttonData.isPassiveCooldown or buttonData.addedAs == "aura") then
            if ST.UnusableVisualUsesDesaturation(style) then
                forceDesat = true
            end
            if ST.UnusableVisualUsesDimTint(style) then
                local uc = style.iconUnusableTintColor
                tintR = uc and uc[1] or 0.4
                tintG = uc and uc[2] or 0.4
                tintB = uc and uc[3] or 0.4
                tintA = uc and uc[4] or tintA
            end
        end
    elseif kind == "out_of_range" then
        if style.showOutOfRange and not buttonData.isPassive then
            tintR, tintG, tintB = 1, 0.2, 0.2
        end
    elseif kind == "aura_stack_text" then
        if style.showAuraStackText ~= false then
            local fs = EnsureBarSlotAuraStackText(slot)
            CooldownCompanion.ApplyFontStyle(fs, style, "auraStack")
            fs:ClearAllPoints()
            local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
            local asX = style.auraStackXOffset or 2
            local asY = style.auraStackYOffset or 2
            if style.showBarIcon ~= false then
                fs:SetPoint(asAnchor, slot.icon, asAnchor, asX, asY)
            else
                fs:SetPoint(asAnchor, slot, asAnchor, asX, asY)
            end
            -- Threshold-aware stand-in (2026-08-15 program); helper lives in
            -- ButtonFrame/Helpers.lua.
            local asText, asR, asG, asB, asA = CooldownCompanion:GetAuraStackPreviewCountAndColor(
                buttonData, style, state.stackText)
            fs:SetText(asText)
            fs:SetTextColor(asR, asG, asB, asA)
            fs:Show()
        end
    elseif kind == "loss_of_control" and GetConditionalPreviewTiming then
        if style.showLossOfControl and buttonData.type == "spell" and not buttonData.isPassive
            and style.showBarIcon ~= false then
            local startTime, duration = GetConditionalPreviewTiming(state, now)
            if startTime then
                local widget = EnsureSlotLocCooldown(slot)
                widget:Show()
                widget:SetCooldown(startTime, duration)
                slot._cdcCondAnim = state
                slot._cdcCondArmedStart = startTime
            end
        end
    end

    if slot.icon then
        slot.icon:SetVertexColor(tintR, tintG, tintB, tintA)
        if forceDesat then
            slot.icon:SetDesaturated(true)
        end
    end
end

-- Static mirror of BarMode.lua CreateBarFrame: same saved settings, same
-- shared area/border helpers, full fill, no runtime state.
local function StyleBarEntry(slot, buttonData, group, effectiveStyle)
    local style = effectiveStyle or group.style or {}
    if not effectiveStyle and CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    end
    slot.style = style

    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(slot, borderSize, borderRenderMode)
    local showIcon = style.showBarIcon ~= false
    local isVertical = style.barFillVertical or false
    local iconReverse = showIcon and (style.barIconReverse or false)
    local barHeight = style.barHeight or 20
    local iconSize = (style.barIconSizeOverride and style.barIconSize) or barHeight
    local iconOffset = showIcon and (style.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = barAreaLeft
    local bgColor = style.barBgColor or { 0.1, 0.1, 0.1, 0.8 }
    local borderColor = style.borderColor or { 0, 0, 0, 1 }

    slot.bg:ClearAllPoints()
    if showIcon then
        SetBarAreaPoints(slot.bg, slot, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        slot.bg:SetAllPoints()
    end
    slot.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    if showIcon then
        SetIconAreaPoints(slot.icon, slot, isVertical, iconReverse, iconSize, borderLayoutSize)
        ST._ApplyIconTexCoord(slot.icon, iconSize, iconSize, style.iconZoom)
        slot.icon:SetTexture(GetConfigOnlyBarPreviewIcon(buttonData))
        slot.icon:Show()
        SetIconAreaPoints(slot.iconBg, slot, isVertical, iconReverse, iconSize, 0)
        slot.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
        slot.iconBg:Show()
        SetIconAreaPoints(slot.iconBounds, slot, isVertical, iconReverse, iconSize, 0)
        for i = 1, 4 do
            slot.iconBorderTextures[i]:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
        end
        ApplyBorderEdgePositions(slot.iconBorderTextures, slot.iconBounds, borderSize, borderRenderMode)
    else
        slot.icon:Hide()
        slot.iconBg:Hide()
        for i = 1, 4 do
            slot.iconBorderTextures[i]:Hide()
        end
    end

    if showIcon then
        SetBarAreaPoints(slot.barBounds, slot, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        slot.barBounds:ClearAllPoints()
        slot.barBounds:SetAllPoints()
    end

    SetBarAreaPoints(slot.statusBar, slot, isVertical, iconReverse, barAreaLeft, barAreaTop, borderLayoutSize)
    slot.statusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    slot.statusBar:SetMinMaxValues(0, 1)
    slot.statusBar:SetValue(1)
    slot.statusBar:SetReverseFill(style.barReverseFill or false)
    slot.statusBar:SetStatusBarTexture(CooldownCompanion:FetchEffectiveBarTexture(style.barTexture or "Solid"))
    local barColor = style.barColor or DEFAULT_BAR_COLOR
    slot.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
    slot.statusBar:Show()

    SetBarAreaPoints(slot.textFrame, slot, isVertical, iconReverse, barAreaLeft, barAreaTop, borderLayoutSize)
    slot.textFrame:SetFrameLevel(slot.statusBar:GetFrameLevel() + 2)

    local nameText = slot.nameText
    CooldownCompanion.ApplyFontStyle(nameText, style, "barName", 10)
    local nameOffX = style.barNameTextOffsetX or 0
    local nameOffY = style.barNameTextOffsetY or 0
    local nameReverse = style.barNameTextReverse
    nameText:ClearAllPoints()
    if isVertical then
        if nameReverse then
            nameText:SetPoint("TOP", nameOffX, -3 + nameOffY)
        else
            nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        end
        nameText:SetJustifyH("CENTER")
    else
        if nameReverse then
            nameText:SetPoint("RIGHT", -3 + nameOffX, nameOffY)
            nameText:SetJustifyH("RIGHT")
        else
            nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
            nameText:SetJustifyH("LEFT")
        end
    end
    if style.showBarNameText ~= false or buttonData.customName then
        nameText:SetText(GetConfigOnlyBarPreviewName(buttonData))
        nameText:Show()
    else
        nameText:Hide()
    end

    ApplyBarReadyPresentation(slot, buttonData, style)

    for i = 1, 4 do
        slot.borderTextures[i]:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    end
    ApplyBorderEdgePositions(slot.borderTextures, slot.barBounds, borderSize, borderRenderMode)
end

-- Private helpers consumed by later ButtonPanelPreview files.
PP.IsPandemicPreviewEnabled = IsPandemicPreviewEnabled
PP.ResetBarSlotConditionalVisuals = ResetBarSlotConditionalVisuals
PP.StyleBarEntry = StyleBarEntry
PP.ApplyBarSlotConditionalPreview = ApplyBarSlotConditionalPreview
