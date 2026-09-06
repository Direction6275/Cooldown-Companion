--[[
    CooldownCompanion - ButtonPanelPreviewEffects
    Effect-preview application and conditional-preview ticker lifecycle.

    Part of the ButtonPanelPreview family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._ButtonPanelPreview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CreateGlowContainer = ST._CreateGlowContainer
local SetBarAuraEffect = ST._SetBarAuraEffect
local GetConditionalPreviewTiming = ST._GetConditionalPreviewTiming

local PP = ST._ButtonPanelPreview

-- ButtonPanelPreviewBars.lua
local IsPandemicPreviewEnabled = PP.IsPandemicPreviewEnabled

-- ButtonPanelPreviewShared.lua
local GetStoredBarPreviewState = PP.GetStoredBarPreviewState
local PANEL_PREVIEW_COND_TICK = PP.PANEL_PREVIEW_COND_TICK

-- ButtonPanelPreviewIcons.lua
local IsAuraDurationTextKind = PP.IsAuraDurationTextKind
local FormatAuraDurationPreviewText = PP.FormatAuraDurationPreviewText
local StyleSlotCooldownText = PP.StyleSlotCooldownText

-- ButtonPanelPreviewText.lua
local RenderTextSlot = PP.RenderTextSlot

------------------------------------------------------------------------
-- Effect previews on the mirror: while a preview toggle is active for an
-- entry (or its whole panel), render the configured glow through the shared
-- Glows.lua setters. Mirror slots carry their own containers and `style` field.
-- Icons support proc/aura/ready/key-press, bars support bar aura effects, and
-- text slots support none.
------------------------------------------------------------------------
local EFFECT_PREVIEWS = {
    { flag = "_procGlowPreview", containerKey = "procGlow", setter = ST._SetProcGlow },
    -- The aura def yields its OFF-call to an active pandemic render: the two
    -- share one container, and an unconditional off-call would cold-reset
    -- the shared cache every pass — hiding a pandemic render mid-pass and
    -- restarting its animations on every config rebuild.
    { flag = "_auraGlowPreview", containerKey = "auraGlow", setter = ST._SetAuraGlow,
        yieldsToPandemic = true },
    -- Pandemic rides the aura glow container with SetAuraGlow's pandemic
    -- override (the pandemicGlow* key family). Listed AFTER the aura def,
    -- and it only ever calls the setter while ACTIVE — the aura def's own
    -- unconditional call reconciles the container whenever this preview is
    -- off (see the loop).
    { flag = "_pandemicPreview", containerKey = "auraGlow", setter = ST._SetAuraGlow,
        pandemicOverride = true },
    { flag = "_readyGlowPreview", containerKey = "readyGlow", setter = ST._SetReadyGlow },
    { flag = "_keyPressHighlightPreview", containerKey = "keyPressHighlight",
        setter = ST._SetKeyPressHighlight, withOverlay = true },
}

local function ApplySlotEffectPreviews(slot, buttonData, group, panelId, index, isBarMode,
        effectiveStyle, barPreviewState)
    local style = effectiveStyle or group.style or {}
    if not effectiveStyle and CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    end
    slot.style = style

    local canQuery = CooldownCompanion.IsPreviewFlagActive ~= nil

    if not isBarMode then
        -- Live parity (AuraDisplay bind gate): the pandemic rig renders
        -- nothing while the effect is disabled for this entry. Live shows
        -- the aura glow OUTSIDE the window and the pandemic style inside
        -- it (the window mask swaps them); the two exclusive PCC toggles
        -- preview those two states one at a time. Resolved once here
        -- because both auraGlow-container defs consult it.
        local pandemicWillRender = canQuery
            and CooldownCompanion:IsPreviewFlagActive(panelId, index, "_pandemicPreview")
            and IsPandemicPreviewEnabled(style, buttonData) or false
        for _, def in ipairs(EFFECT_PREVIEWS) do
            if def.setter then
                local active
                if def.pandemicOverride then
                    active = pandemicWillRender
                else
                    active = canQuery
                        and CooldownCompanion:IsPreviewFlagActive(panelId, index, def.flag) or false
                end
                if active and not slot[def.containerKey] and CreateGlowContainer then
                    slot[def.containerKey] = CreateGlowContainer(slot, 32, def.withOverlay)
                end
                if slot[def.containerKey] then
                    if def.pandemicOverride then
                        -- Shares the aura def's container: only an ACTIVE
                        -- pandemic render may touch it. The aura def's own
                        -- call reconciles the container whenever this
                        -- preview is off — an unconditional off-call here
                        -- would hide the aura glow that call just rendered.
                        if active then
                            def.setter(slot, true, true)
                        end
                    elseif def.yieldsToPandemic and not active and pandemicWillRender then
                        -- Skip the off-call: the pandemic def owns the
                        -- container this pass, and a hide here would
                        -- cold-reset its cache and restart its animations
                        -- on every rebuild.
                    else
                        def.setter(slot, active, false)
                    end
                end
            end
        end
        return
    end

    if SetBarAuraEffect then
        -- Live parity (Preview.lua barAuraEffectOnToggle): nothing renders
        -- while the bar aura indicator is disabled.
        barPreviewState = barPreviewState or GetStoredBarPreviewState(panelId, index)
        local effectFlags = barPreviewState.effectFlags
        local active = effectFlags and effectFlags._barAuraEffectPreview == true
            and ST.IsBarAuraIndicatorEnabled
            and ST.IsBarAuraIndicatorEnabled(style) == true
            or false
        if active and not slot.barAuraEffect and CreateGlowContainer then
            slot.barAuraEffect = CreateGlowContainer(slot, 32, false)
        end
        if slot.barAuraEffect then
            SetBarAuraEffect(slot, active)
        end
    end
end

-- Strip slots recycle from the icon pool; a glow left by a grid render
-- must not survive into a picker strip.
local function ClearSlotEffectPreviews(slot)
    for _, def in ipairs(EFFECT_PREVIEWS) do
        if slot[def.containerKey] and def.setter then
            def.setter(slot, false)
        end
    end
    if slot.barAuraEffect and SetBarAuraEffect then
        SetBarAuraEffect(slot, false)
    end
end

local function StopConditionalTicker(preview)
    if preview.condTicker then
        preview.condTicker:Cancel()
        preview.condTicker = nil
    end
end

-- Drives the animated conditional previews: countdown numbers for the
-- aura duration text, and re-arming the looping Cooldown widgets when
-- the stored preview state wraps to a new cycle (within a cycle the
-- computed startTime is constant, so a forward jump means a new cycle).
local function EnsureConditionalTicker(preview)
    if preview.condTicker then return end
    preview.condTicker = C_Timer.NewTicker(PANEL_PREVIEW_COND_TICK, function()
        if not GetConditionalPreviewTiming then return end
        local pool = preview.pools.iconSlots
        local used = preview.used.iconSlots or 0
        local now = GetTime()
        for i = 1, used do
            local slot = pool[i]
            local state = slot and slot:IsShown() and slot._cdcCondAnim or nil
            if state then
                local startTime, duration, remaining = GetConditionalPreviewTiming(state, now)
                if startTime then
                    if IsAuraDurationTextKind(state.kind) and slot.auraTextFS then
                        slot.auraTextFS:SetText(FormatAuraDurationPreviewText(
                            remaining, state.kind,
                            slot.style or {}, slot.buttonData, slot._cdcAuraLowTime))
                    end
                    local widget
                    if state.kind == "cooldown"
                        or state.kind == "cooldown_text"
                        or state.kind == "cooldown_swipe" then
                        widget = slot.cooldown
                    elseif state.kind == "aura_duration_swipe" then
                        widget = slot.auraSwipe
                    elseif state.kind == "loss_of_control" then
                        widget = slot.locCooldown
                    end
                    if widget and slot._cdcCondArmedStart
                        and startTime > slot._cdcCondArmedStart + 0.05 then
                        slot._cdcCondArmedStart = startTime
                        widget:SetCooldown(startTime, duration)
                        -- cooldown_swipe keeps its numbers hidden across
                        -- re-arms (a widget flag, not a region style), so
                        -- only the text-bearing kinds restyle here.
                        if state.kind == "cooldown" or state.kind == "cooldown_text" then
                            StyleSlotCooldownText(slot, slot.style or {})
                        end
                    end
                end
            end
        end
        -- Bar slots: time text countdown (the fill self-animates) and
        -- loss-of-control loop re-arms.
        local barPool = preview.pools.barSlots
        local usedBars = preview.used.barSlots or 0
        for i = 1, usedBars do
            local slot = barPool[i]
            local state = slot and slot:IsShown() and slot._cdcCondAnim or nil
            if state then
                local startTime, duration, remaining = GetConditionalPreviewTiming(state, now)
                if startTime then
                    if slot.timeText
                        and (state.kind == "cooldown"
                            or state.kind == "cooldown_text"
                            or IsAuraDurationTextKind(state.kind)) then
                        local style = slot.style or {}
                        local showText = (IsAuraDurationTextKind(state.kind)
                                and style.showAuraText ~= false)
                            or ((state.kind == "cooldown" or state.kind == "cooldown_text")
                                and style.showCooldownText)
                        if showText and CooldownCompanion.FormatTime then
                            if IsAuraDurationTextKind(state.kind) then
                                slot.timeText:SetText(FormatAuraDurationPreviewText(
                                    remaining, state.kind, style, slot.buttonData,
                                    slot._cdcAuraLowTime))
                            else
                                slot.timeText:SetText(CooldownCompanion.FormatCooldownTime(
                                    remaining, style))
                            end
                        end
                    end
                    if state.kind == "loss_of_control" and slot.locCooldown
                        and slot._cdcCondArmedStart
                        and startTime > slot._cdcCondArmedStart + 0.05 then
                        slot._cdcCondArmedStart = startTime
                        slot.locCooldown:SetCooldown(startTime, duration)
                    end
                end
            end
        end
        -- Text slots: re-render the format so the countdown ticks
        local textPool = preview.pools.textSlots
        local usedText = preview.used.textSlots or 0
        for i = 1, usedText do
            local slot = textPool[i]
            local state = slot and slot:IsShown() and slot._cdcCondAnim or nil
            if state and RenderTextSlot then
                RenderTextSlot(slot, slot.buttonData, slot.style or {}, state, now)
            end
        end
    end)
end

-- Private helpers consumed by later ButtonPanelPreview files.
PP.ClearSlotEffectPreviews = ClearSlotEffectPreviews
PP.StopConditionalTicker = StopConditionalTicker
PP.ApplySlotEffectPreviews = ApplySlotEffectPreviews
PP.EnsureConditionalTicker = EnsureConditionalTicker
