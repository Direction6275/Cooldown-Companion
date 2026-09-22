--[[
    CooldownCompanion - ButtonPanelPreviewBars
    Bar-slot styling, ready/charge/aura presentation, and fill effects.

    Part of the ButtonPanelPreview family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._ButtonPanelPreview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local BarVisuals = ST._BarVisuals
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
local ApplySlotChargeCount = PP.ApplySlotChargeCount
local EnsureSlotLocCooldown = PP.EnsureSlotLocCooldown

------------------------------------------------------------------------
-- Bar-slot conditional previews: same stored state and timing, rendered
-- per BarMode.lua's recipes (UpdateBarFill drain/fill + time text,
-- UpdateBarDisplay colors and fill effects).
------------------------------------------------------------------------
local function EnsureBarSlotTimeText(slot)
    if not slot.timeText then
        slot.timeText = slot.barTextFrame:CreateFontString(nil, "OVERLAY")
    end
    return slot.timeText
end

local function EnsureBarSlotAuraStackText(slot)
    if not slot.auraStackCount then
        slot.auraStackCount = slot.barTextFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    end
    return slot.auraStackCount
end

-- Runtime and preview share the same placement and truncation rules.
local function AnchorBarSlotTimeText(slot, style, lane)
    lane = lane or "time"
    ST.BarTextLayout.ApplyBarTexts(slot.nameText, slot.timeText, slot.barTextFrame,
        style, style.barFillVertical, lane, slot._persistentAuraName and slot.buttonData)
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
    if state.kind == "aura_duration_bar" or state.kind == "aura_active" then
        frac = remaining / duration
    else
        frac = 1 - (remaining / duration)
    end
    if frac < 0 then frac = 0 end
    if frac > 1 then frac = 1 end
    local holder = self._chargeSegments
    if holder and holder._attached and slot._chargePreviewCount ~= nil then
        ST.ChargeBarSegments.Preview(holder, slot._chargePreviewCount, frac, slot._chargePreviewColor)
    else
        self:SetValue(frac)
    end
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

-- Stack decorations belong to the combined sample, never to the pooled slot.
-- Restore shown-state (not alpha) because workspace ghosting owns bar alpha.
local function ResetBarAuraStackPreview(slot)
    if slot._cdcAuraStackCount == nil then return end
    slot._cdcAuraStackCount = nil
    ST.HideStackBlocks(slot._cdcAuraStackBlocks)
    ST.HideStackBlocks(slot._cdcAuraStackSegments)
    ST.HideStackBlockBorders(slot._cdcAuraStackBorders)
    if slot._cdcAuraStackWidget then
        slot._cdcAuraStackWidget = nil
        slot.statusBar:SetRotatesTexture(false)
        local style = slot.style or {}
        slot.statusBar:SetStatusBarTexture(CooldownCompanion:FetchEffectiveBarTexture(style.barTexture or "Solid"))
        slot.bg:SetShown(slot._cdcAuraStackBgShown)
        slot._cdcAuraStackBgShown = nil
        for _, texture in ipairs(slot.borderTextures or {}) do
            texture:SetShown(texture._cdcAuraStackWasShown)
            texture._cdcAuraStackWasShown = nil
        end
    end
end

local function ApplyBarAuraStackFill(slot, buttonData, style, state, maximum)
    -- Text-only threshold/max styling may select an interesting sample only
    -- while its readout is visible. The fill and displayed count then agree.
    local text = state.stackText
    if style.showAuraStackText ~= false then
        text = CooldownCompanion:GetAuraStackPreviewCountAndColor(buttonData, style, text)
    end
    local count = math.min(maximum, math.max(0, tonumber(text) or 3))
    slot._cdcAuraStackCount = count
    slot.statusBar:SetScript("OnUpdate", nil)
    slot.statusBar:SetValue(count / maximum)
    if CooldownCompanion:GetBarPanelAuraStackDisplayMode(buttonData) ~= "segmented"
        or maximum > ST.STACK_SEGMENT_ATLAS_MAX then return end

    local vertical = style.barFillVertical == true
    local bg = style.barBgColor or { 0.1, 0.1, 0.1, 0.8 }
    if buttonData.addedAs == "aura" then
        -- The same atlas and measured block edges as the live aura kit:
        -- true empty gaps and a separate border around every capacity block.
        local blocks = slot._cdcAuraStackBlocks or {}
        local borders = slot._cdcAuraStackBorders or {}
        slot._cdcAuraStackBlocks, slot._cdcAuraStackBorders = blocks, borders
        for i = #blocks + 1, maximum do
            blocks[i] = slot.statusBar:CreateTexture(nil, "BACKGROUND")
            borders[i] = {}
            for edge = 1, 4 do
                borders[i][edge] = slot.statusBar:CreateTexture(nil, "OVERLAY", nil, 3)
            end
        end
        local gap = CooldownCompanion:GetAuraStackBlockGapTexels(buttonData, maximum)
        ST.LayoutStackBlocks(blocks, slot.statusBar, maximum, vertical, bg, bg[4] or 1, nil, gap / 512)
        ST.LayoutStackBlockBorders(borders, blocks, maximum, style)
        slot.statusBar:SetStatusBarTexture(ST.GetStackSegmentsTexture(maximum, gap))
        slot.statusBar:SetRotatesTexture(vertical)
        slot._cdcAuraStackWidget = true
        slot._cdcAuraStackBgShown = slot.bg:IsShown()
        slot.bg:Hide()
        for _, texture in ipairs(slot.borderTextures or {}) do
            texture._cdcAuraStackWasShown = texture:IsShown()
            texture:Hide()
        end
    else
        -- Spell entries keep their continuous background and whole-bar ring;
        -- opaque dividers reproduce AuraDisplay's StyleStackSegments recipe.
        local gap = CooldownCompanion:GetBarPanelAuraSegmentGap(buttonData)
        local length = vertical and slot.statusBar:GetHeight() or slot.statusBar:GetWidth()
        if gap <= 0 or length <= 0 then return end
        local segments = slot._cdcAuraStackSegments or {}
        slot._cdcAuraStackSegments = segments
        for i = #segments + 1, maximum - 1 do
            segments[i] = slot.statusBar:CreateTexture(nil, "OVERLAY", nil, 3)
        end
        for i = 1, maximum - 1 do
            local texture = segments[i]
            local offset = length * i / maximum
            texture:SetColorTexture(bg[1], bg[2], bg[3], 1)
            texture:ClearAllPoints()
            if vertical then
                texture:SetHeight(gap)
                texture:SetPoint("LEFT", slot.statusBar, "BOTTOMLEFT", 0, offset)
                texture:SetPoint("RIGHT", slot.statusBar, "BOTTOMRIGHT", 0, offset)
            else
                texture:SetWidth(gap)
                texture:SetPoint("TOP", slot.statusBar, "TOPLEFT", offset, 0)
                texture:SetPoint("BOTTOM", slot.statusBar, "BOTTOMLEFT", offset, 0)
            end
            texture:SetAlpha(1)
        end
    end
end

-- Cleanup runs before StyleBarEntry so its neutral texture tint cannot win
-- over the final saved or simulated status-bar color.
local function ResetBarSlotConditionalVisuals(slot)
    ResetBarAuraStackPreview(slot)
    ST.ChargeBarSegments.Invalidate(slot.statusBar)
    slot._chargePreviewCount, slot._chargePreviewColor = nil, nil
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

local function ApplyBarAuraTimeTextPreview(slot, style, remaining, kind, buttonData, duration)
    local tt = EnsureBarSlotTimeText(slot)
    AnchorBarSlotTimeText(slot, style, "aura")
    if style.showAuraText == false then
        tt:SetText("")
        return
    end
    local font = CooldownCompanion:FetchFont(style.auraTextFont or "Friz Quadrata TT")
    local size = style.auraTextFontSize or 12
    local outline = ST.GetEffectiveFontOutline(style.auraTextFontOutline or "OUTLINE")
    tt:SetFont(font, size, outline)
    ST.ApplyFontShadowForOutline(tt, outline)
    local color = style.auraTextFontColor or CooldownCompanion.DEFAULT_AURA_TEXT_COLOR
    tt:SetTextColor(color[1], color[2], color[3], color[4])
    tt:SetText(FormatAuraDurationPreviewText(remaining, kind, style, buttonData,
        slot._cdcAuraLowTime, duration))
    tt:Show()
end

local function ApplyBarAuraStackPreview(slot, buttonData, style, state)
    if style.showAuraStackText ~= false then
        local fs = EnsureBarSlotAuraStackText(slot)
        CooldownCompanion.ApplyFontStyle(fs, style, "auraStack")
        local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
        local asX = style.auraStackXOffset or 2
        local asY = style.auraStackYOffset or 2
        if style.showBarIcon ~= false then
            ST.TextAnchorLayout.Apply(fs, slot.icon, asAnchor, asX, asY)
        else
            ST.TextAnchorLayout.Apply(fs, slot.barTextFrame, asAnchor, asX, asY)
        end
        -- Threshold-aware stand-in (2026-08-15 program); helper lives in
        -- ButtonFrame/Helpers.lua.
        local asText, asR, asG, asB, asA = CooldownCompanion:GetAuraStackPreviewCountAndColor(
            buttonData, style, state.stackText)
        fs:SetText(slot._cdcAuraStackCount ~= nil and tostring(slot._cdcAuraStackCount) or asText)
        fs:SetTextColor(asR, asG, asB, asA)
        fs:Show()
    end
end

local function ApplyBarAuraFillPreview(slot, style, buttonData, isAuraPanel, pandemicActive, fxActive)
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
end

-- Reconcile only the window transition; animation groups keep their phase
-- between ticks. All fill/text/swipe timing comes from the same session sample.
local function UpdateCombinedBarAuraEffects(slot, state, now)
    local _, duration, remaining = GetConditionalPreviewTiming(state, now)
    local style = slot.style or {}
    local pandemicActive = ST._ConfigPreview.IsPandemicWindow(remaining, duration)
        and IsPandemicPreviewEnabled(style, slot.buttonData) or false
    if slot._cdcAuraPandemicActive == pandemicActive then return end
    slot._cdcAuraPandemicActive = pandemicActive
    StopBarSlotFillEffects(slot)
    local fxActive = ST.IsBarAuraIndicatorEnabled and ST.IsBarAuraIndicatorEnabled(style) == true
    ApplyBarAuraFillPreview(slot, style, slot.buttonData, slot._cdcAuraPanel, pandemicActive, fxActive)
end

local function ApplyBarSlotConditionalPreview(slot, buttonData, group, panelId, index,
        style, previewState)
    PP.RestoreMissingReminderPreview(slot)
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

    if (kind == "cooldown" or kind == "cooldown_active" or kind == "cooldown_text" or IsAuraDurationTextKind(kind))
        and slot.timeText then
        slot.timeText:SetText("")
    end

    if auraPresentationActive then
        ST.ChargeBarSegments.End(slot.statusBar)
        slot._chargePreviewCount, slot._chargePreviewColor = nil, nil
    end

    if kind == "aura_duration_bar" or kind == "aura_active" then
        local auraTint = style.iconAuraTintEnabled and style.iconAuraTintColor or baseTint
        tintR = auraTint and auraTint[1] or 1
        tintG = auraTint and auraTint[2] or 1
        tintB = auraTint and auraTint[3] or 1
        tintA = auraTint and auraTint[4] or 1
        local auraColor = ResolveBarAuraFillColor(style, buttonData, isAuraPanel)
        slot.statusBar:SetStatusBarColor(auraColor[1], auraColor[2], auraColor[3], auraColor[4] or 1)
    end

    if IsAuraDurationTextKind(kind) and kind ~= "aura_active" and GetConditionalPreviewTiming then
        local startTime, _, remaining = GetConditionalPreviewTiming(state, now)
        if startTime then
            slot._cdcCondAnim = state
            ApplyBarAuraTimeTextPreview(slot, style, remaining, kind, buttonData)
        end
    elseif (kind == "aura_duration_bar" or kind == "aura_active") and GetConditionalPreviewTiming then
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
            local stackMax = kind == "aura_active"
                and CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData)
                and CooldownCompanion:GetAuraStackBarMax(buttonData, true)
            slot._cdcCondAnim = state
            if stackMax then
                ApplyBarAuraStackFill(slot, buttonData, style, state, stackMax)
            else
                -- Unknown/non-stacking capacities follow the live duration fallback.
                slot.statusBar._cdcOwner = slot
                slot.statusBar:SetScript("OnUpdate", BarSlotFillOnUpdate)
                BarSlotFillOnUpdate(slot.statusBar)
            end
            ApplyBarAuraFillPreview(slot, style, buttonData, isAuraPanel, pandemicActive, fxActive)
            slot._cdcAuraPandemicActive = pandemicActive and true or false
            slot._cdcAuraPanel = isAuraPanel
        end
    elseif (kind == "cooldown" or kind == "cooldown_active") and GetConditionalPreviewTiming then
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
            local color = style.barCooldownColor or DEFAULT_BAR_COLOR
            if ST.ChargeBarSegments.PaintPanel(slot, 0, buttonData.maxCharges, nil, false, color) then
                slot._chargePreviewCount, slot._chargePreviewColor = 0, color
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
            if chargePresentationKind ~= "charge_full" and slot.timeText then
                slot.timeText:SetText("")
            end
            local current, maxCharges = ApplySlotChargeCount(
                slot, buttonData, style, chargePresentationKind, ApplyBarCountTextStyle)

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

            local segmentColor = chargePresentationKind == "charge_zero"
                and (style.barCooldownColor or DEFAULT_BAR_COLOR)
                or (style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR)
            if not auraPresentationActive
                and ST.ChargeBarSegments.PaintPanel(slot, current, maxCharges, nil, false, segmentColor) then
                slot._chargePreviewCount, slot._chargePreviewColor = current, segmentColor
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
                    startTime = state.startedAt - rechargeElapsed,
                    loop = true,
                    loopDuration = rechargeDuration,
                    loopStartTime = state.startedAt - rechargeElapsed,
                }
                slot.statusBar._cdcOwner = slot
                slot.statusBar:SetScript("OnUpdate", BarSlotFillOnUpdate)
                slot._cdcCondAnim = rechargeState
                BarSlotFillOnUpdate(slot.statusBar)
                if style.showCooldownText then
                    local tt = EnsureBarSlotTimeText(slot)
                    CooldownCompanion.ApplyFontStyle(tt, style, "cooldown")
                    AnchorBarSlotTimeText(slot, style)
                    local _, _, remaining = GetConditionalPreviewTiming(rechargeState, now)
                    tt:SetText(CooldownCompanion.FormatCooldownTime(remaining, style))
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
        ApplyBarAuraStackPreview(slot, buttonData, style, state)
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

    if kind == "cooldown_active" and UsesConfigOnlyBarChargeBehavior(buttonData) then
        ApplySlotChargeCount(slot, buttonData, style, "charge_zero", ApplyBarCountTextStyle)
        if buttonData.desaturateWhileZeroCharges
            and not (CooldownCompanion.HasItemFallbacks and CooldownCompanion.HasItemFallbacks(buttonData)) then
            forceDesat = true
        end
    elseif kind == "aura_active" then
        local _, duration, remaining = GetConditionalPreviewTiming(state, now)
        ApplyBarAuraTimeTextPreview(slot, style, remaining, kind, buttonData, duration)
        ApplyBarAuraStackPreview(slot, buttonData, style, state)
    end

    if slot.icon then
        slot.icon:SetVertexColor(tintR, tintG, tintB, tintA)
        if forceDesat then
            slot.icon:SetDesaturated(true)
        end
    end
    PP.ApplyMissingReminderPreview(slot, buttonData, group, previewState)
end

-- Static mirror of BarMode.lua CreateBarFrame: same saved settings, same
-- shared area/border helpers, full fill, no runtime state.
local function StyleBarEntry(slot, buttonData, group, effectiveStyle)
    PP.RestoreMissingReminderPreview(slot)
    ST.ChargeBarSegments.Invalidate(slot.statusBar)
    slot.buttonData = buttonData
    slot._persistentAuraName = not ST.IsAuraPanelGroup(group)
        and ST.BarLayers.HasPersistentAuraName(buttonData)
    slot._chargePreviewCount, slot._chargePreviewColor = nil, nil
    local style = effectiveStyle or group.style or {}
    if not effectiveStyle and CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData, group) or style
    end
    slot.style = style

    local width, height = slot:GetSize()
    BarVisuals.Apply(slot, style, width, height)
    local showIcon = style.showBarIcon ~= false
    local isVertical = style.barFillVertical or false
    if showIcon then
        slot.icon:SetTexture(GetConfigOnlyBarPreviewIcon(buttonData))
    end
    slot.icon:SetShown(showIcon)
    slot.iconBg:SetShown(showIcon)
    for _, texture in ipairs(slot.iconBorderTextures) do texture:SetShown(showIcon) end

    -- These are sample values and preview layers, never live timer state.
    slot.statusBar:SetMinMaxValues(0, 1)
    slot.statusBar:SetValue(1)
    slot.statusBar:Show()
    slot.barTextFrame:SetFrameLevel(slot.statusBar:GetFrameLevel() + 2)

    local nameText = slot.nameText
    CooldownCompanion.ApplyFontStyle(nameText, style, "barName", 10)
    ST.BarTextLayout.Apply(nameText, slot.barTextFrame,
        ST.BarTextLayout.Resolve(style, "name", isVertical))
    if style.showBarNameText ~= false or buttonData.customName then
        nameText:SetText(GetConfigOnlyBarPreviewName(buttonData))
        nameText:Show()
    else
        nameText:Hide()
    end

    ApplyBarReadyPresentation(slot, buttonData, style)

    if ST.ChargeBarSegments.PaintPanel(slot, buttonData.maxCharges, buttonData.maxCharges,
        nil, false, style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR) then
        slot.barTextFrame:SetFrameLevel(slot.statusBar:GetFrameLevel() + 4)
    end
end

-- Overview identity is based on the saved entry kind, never its active phase.
local function ApplyOverviewBarPresentation(preview, slot, buttonData, group, style, scale)
    if ST._GetEntryIdentityKindText(buttonData) == "Aura" then
        ST.ChargeBarSegments.End(slot.statusBar)
        slot._chargePreviewCount, slot._chargePreviewColor = nil, nil
        local color = ResolveBarAuraFillColor(style, buttonData, ST.IsAuraPanelGroup(group))
        slot.statusBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
        slot.statusBar:SetValue(1)
    end
    PP.ConfigureBarIdentityLabel(preview, slot, buttonData, scale, style.barFillVertical)
end

-- Private helpers consumed by later ButtonPanelPreview files.
PP.UpdateCombinedBarAuraEffects = UpdateCombinedBarAuraEffects
PP.IsPandemicPreviewEnabled = IsPandemicPreviewEnabled
PP.ResetBarSlotConditionalVisuals = ResetBarSlotConditionalVisuals
PP.StyleBarEntry = StyleBarEntry
PP.ApplyBarSlotConditionalPreview = ApplyBarSlotConditionalPreview
PP.ApplyOverviewBarPresentation = ApplyOverviewBarPresentation
