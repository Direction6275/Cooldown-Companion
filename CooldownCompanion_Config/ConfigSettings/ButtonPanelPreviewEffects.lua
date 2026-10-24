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
local UpdateCombinedBarAuraEffects = PP.UpdateCombinedBarAuraEffects

-- ButtonPanelPreviewShared.lua
local GetStoredBarPreviewState = PP.GetStoredBarPreviewState
local PANEL_PREVIEW_COND_TICK = PP.PANEL_PREVIEW_COND_TICK

-- ButtonPanelPreviewIcons.lua
local IsAuraDurationTextKind = PP.IsAuraDurationTextKind
local FormatAuraDurationPreviewText = PP.FormatAuraDurationPreviewText
local StyleSlotCooldownText = PP.StyleSlotCooldownText

------------------------------------------------------------------------
-- Effect previews on the mirror: while a preview toggle is active for an
-- entry (or its whole panel), render the configured glow through the shared
-- Glows.lua setters. Mirror slots carry their own containers and `style` field.
-- Icons support proc/aura/ready/key-press, and bars support bar aura effects.
-- The pandemic look is not a setter here: it is always the live window rig
-- (see StylePandemicPreviewRig).
------------------------------------------------------------------------
local EFFECT_PREVIEWS = {
    { flag = "_procGlowPreview", containerKey = "procGlow", setter = ST._SetProcGlow },
    -- The aura glow steps aside while the pandemic rig draws the window, as
    -- in game.
    { flag = "_auraGlowPreview", containerKey = "auraGlow", setter = ST._SetAuraGlow,
        yieldsToPandemic = true },
    { flag = "_readyGlowPreview", containerKey = "readyGlow", setter = ST._SetReadyGlow },
    { flag = "_keyPressHighlightPreview", containerKey = "keyPressHighlight",
        setter = ST._SetKeyPressHighlight, withOverlay = true, noProc = true },
}

-- The pandemic look is drawn with the live window rig (Glows.lua
-- BuildPandemicWindowRig) for every pandemic preview (owner ruling
-- 2026-10-24: the game's glow only). Inside the looping Aura Active cycle the
-- preview plays the rig's Pandemic Start / Refresh animations at the cycle's
-- window flips the way Blizzard plays them in game; the cycle's wrap is the
-- refresh in time. With no effect picked the rig's effects are no-ops and the
-- held window simply shows the look.
local function PlayGroups(groups, method)
    for _, group in ipairs(groups) do
        group[method](group)
    end
end

local function GetPandemicPreviewRig(slot)
    if slot._ccPandemicRig then return slot._ccPandemicRig end
    local triggers = { enter = {}, active = {}, leave = {} }
    local recorder = {
        AddPandemicEnterAnimation = function(_, group) triggers.enter[#triggers.enter + 1] = group end,
        AddPandemicActiveAnimation = function(_, group) triggers.active[#triggers.active + 1] = group end,
        AddPandemicLeaveAnimation = function(_, group) triggers.leave[#triggers.leave + 1] = group end,
    }
    -- At the cooldown swipe's level, the layer the preview's aura glow
    -- container uses: below the text overlay (cooldown + 1) that carries the
    -- aura countdown and stack text, so the look never covers them.
    local rig = ST._BuildPandemicWindowRig(slot, slot, recorder,
        (slot.cooldown or slot):GetFrameLevel(), true)
    rig.triggers = triggers
    slot._ccPandemicRig = rig
    return rig
end

-- What StyleKitPandemicGlowRegions reads, plus the rect the kit fits around.
local PANDEMIC_LOOK_KEYS = { "pandemicGlowStyle", "pandemicGlowSize", "pandemicGlowSpeed",
    "pandemicGlowLines", "pandemicGlowThickness" }
local PANDEMIC_LOOK_COLORS = { "pandemicGlowColor", "pandemicGlowColor2" }

-- Colors compare by component: the color picker edits its table in place.
local function MatchesPandemicLook(stamp, style, w, h)
    if stamp.w ~= w or stamp.h ~= h then return false end
    for _, key in ipairs(PANDEMIC_LOOK_KEYS) do
        if stamp[key] ~= (style and style[key]) then return false end
    end
    for _, key in ipairs(PANDEMIC_LOOK_COLORS) do
        local color, saved = style and style[key], stamp[key]
        if color then
            if not (saved and saved[1] == color[1] and saved[2] == color[2]
                and saved[3] == color[3] and saved[4] == color[4]) then
                return false
            end
        elseif saved then
            return false
        end
    end
    return true
end

local function StampPandemicLook(style, w, h)
    local stamp = { w = w, h = h }
    for _, key in ipairs(PANDEMIC_LOOK_KEYS) do
        stamp[key] = style and style[key]
    end
    for _, key in ipairs(PANDEMIC_LOOK_COLORS) do
        local color = style and style[key]
        stamp[key] = color and { color[1], color[2], color[3], color[4] } or nil
    end
    return stamp
end

-- `on`: the rig draws this slot's pandemic look. `flip`: the window just
-- opened or closed, so the effects play; a rebuild only restores the steady
-- state.
--
-- Styling the kit restarts its animations, so a redraw that changes nothing
-- the look reads keeps the running glow and only re-snaps its edges (owner
-- ruling 2026-10-24). Editing the look's own keys still restyles it.
local function StylePandemicPreviewRig(slot, style, on, inWindow, flip)
    -- Read by the selection outline (ApplySelectionVisuals).
    slot._ccPandemicRigLit = on or nil
    local rig = slot._ccPandemicRig or on and GetPandemicPreviewRig(slot)
    if not rig then return end
    if on then
        local w, h = slot._ccKitRectW, slot._ccKitRectH
        if not (w and h) then w, h = slot:GetSize() end
        if rig.lookStamp and MatchesPandemicLook(rig.lookStamp, style, w, h) then
            ST.RefreshBorderTextureScale(rig.glow.edges)
        else
            ST._StyleKitPandemicGlowRegions(rig.glow, style, slot, true)
            rig.lookStamp = StampPandemicLook(style, w, h)
        end
    else
        rig.lookStamp = nil
        ST._StyleKitPandemicGlowRegions(rig.glow, style, slot, false)
    end
    ST._StylePandemicWindowRig(rig, style, on)
    local triggers = rig.triggers
    if on and inWindow then
        if flip then PlayGroups(triggers.enter, "Play") end
        PlayGroups(triggers.active, "Play")
    else
        PlayGroups(triggers.active, "Stop")
        if on and flip then PlayGroups(triggers.leave, "Play") end
    end
end

local function ApplySlotEffectPreviews(slot, buttonData, group, panelId, index, isBarMode,
        effectiveStyle, barPreviewState)
    -- RenderPreviewEntry, the only caller, always resolves the style first.
    local style = effectiveStyle
    slot.style = style

    local canQuery = CooldownCompanion.IsPreviewFlagActive ~= nil

    if not isBarMode then
        -- Live parity (AuraDisplay bind gate): the pandemic rig renders
        -- nothing while the effect is disabled for this entry. Live shows
        -- the aura glow OUTSIDE the window and the pandemic style inside
        -- it (12.1.5: the window rig swaps them). Individual commands isolate each
        -- look; Aura Active transitions between them.
        local pandemicWillRender = canQuery
            and CooldownCompanion:IsPreviewFlagActive(panelId, index, "_pandemicPreview")
            and IsPandemicPreviewEnabled(style) or false
        slot._cdcAuraPandemicActive = pandemicWillRender
        local conditional = ST._GetStoredConditionalPreviewState
            and ST._GetStoredConditionalPreviewState(panelId, index)
        local useRig = IsPandemicPreviewEnabled(style)
            and (pandemicWillRender or (conditional ~= nil and conditional.kind == "aura_active"))
        for _, def in ipairs(EFFECT_PREVIEWS) do
            if def.setter then
                local flagActive = canQuery
                    and CooldownCompanion:IsPreviewFlagActive(panelId, index, def.flag) or false
                -- Built whenever the flag is on, even while the aura glow
                -- steps aside: the ticker flips only slots that have one.
                if flagActive and not slot[def.containerKey] and CreateGlowContainer then
                    slot[def.containerKey] = CreateGlowContainer(slot, 32, def.withOverlay, def.noProc)
                end
                if slot[def.containerKey] then
                    def.setter(slot, flagActive and not (def.yieldsToPandemic and pandemicWillRender))
                    ST.RefreshBorderTextureScale(slot[def.containerKey].solidTextures)
                end
            end
        end
        StylePandemicPreviewRig(slot, style, useRig, pandemicWillRender, false)
        return
    end

    if SetBarAuraEffect then
        -- Live parity: nothing renders while the bar aura indicator is
        -- disabled.
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
            ST.RefreshBorderTextureScale(slot.barAuraEffect.solidTextures)
        end
    end
end

-- Pooled slots reused by the read-only mirror (ButtonPanelPreview.lua) and by
-- drop-ghost cells (ButtonPanelPreviewInteraction.lua) must not carry an
-- earlier render's effect previews.
local function ClearSlotEffectPreviews(slot)
    slot._cdcAuraPandemicActive = nil
    StylePandemicPreviewRig(slot, nil, false)
    for _, def in ipairs(EFFECT_PREVIEWS) do
        if slot[def.containerKey] and def.setter then
            def.setter(slot, false)
        end
    end
    if slot.barAuraEffect and SetBarAuraEffect then
        SetBarAuraEffect(slot, false)
    end
end

local function UpdateCombinedIconAuraEffects(slot, state, now)
    local _, duration, remaining = GetConditionalPreviewTiming(state, now)
    local pandemicActive = ST._ConfigPreview.IsPandemicWindow(remaining, duration)
        and IsPandemicPreviewEnabled(slot.style) or false
    if slot._cdcAuraPandemicActive == pandemicActive then return end
    slot._cdcAuraPandemicActive = pandemicActive
    if slot.auraGlow and ST._SetAuraGlow then
        ST._SetAuraGlow(slot, not pandemicActive)
        ST.RefreshBorderTextureScale(slot.auraGlow.solidTextures)
    end
    StylePandemicPreviewRig(slot, slot.style, IsPandemicPreviewEnabled(slot.style), pandemicActive, true)
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
                    if state.kind == "aura_active" then UpdateCombinedIconAuraEffects(slot, state, now) end
                    if IsAuraDurationTextKind(state.kind) and slot.auraTextFS then
                        slot.auraTextFS:SetText(FormatAuraDurationPreviewText(
                            remaining, state.kind,
                            slot.style or {}, slot.buttonData, slot._cdcAuraLowTime, duration))
                    end
                    local widget
                    if state.kind == "cooldown"
                        or state.kind == "cooldown_active"
                        or state.kind == "cooldown_text"
                        or state.kind == "cooldown_swipe" then
                        widget = slot.cooldown
                    elseif state.kind == "aura_duration_swipe" or state.kind == "aura_active" then
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
                        if state.kind == "cooldown" or state.kind == "cooldown_text" or state.kind == "cooldown_active" then
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
                    if state.kind == "aura_active" then UpdateCombinedBarAuraEffects(slot, state, now) end
                    if slot.timeText
                        and (state.kind == "cooldown"
                            or state.kind == "cooldown_active"
                            or state.kind == "cooldown_text"
                            or IsAuraDurationTextKind(state.kind)) then
                        local style = slot.style or {}
                        local showText = (IsAuraDurationTextKind(state.kind)
                                and style.showAuraText ~= false)
                            or ((state.kind == "cooldown" or state.kind == "cooldown_text" or state.kind == "cooldown_active")
                                and style.showCooldownText)
                        if showText then
                            if IsAuraDurationTextKind(state.kind) then
                                slot.timeText:SetText(FormatAuraDurationPreviewText(
                                    remaining, state.kind, style, slot.buttonData,
                                    slot._cdcAuraLowTime, duration))
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
    end)
end

-- Private helpers consumed by later ButtonPanelPreview files.
PP.ClearSlotEffectPreviews = ClearSlotEffectPreviews
PP.StopConditionalTicker = StopConditionalTicker
PP.ApplySlotEffectPreviews = ApplySlotEffectPreviews
PP.EnsureConditionalTicker = EnsureConditionalTicker
