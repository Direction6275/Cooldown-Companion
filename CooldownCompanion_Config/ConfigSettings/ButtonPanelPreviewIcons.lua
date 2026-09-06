--[[
    CooldownCompanion - ButtonPanelPreviewIcons
    Icon-slot styling and conditional icon, cooldown, aura, and count previews.

    Part of the ButtonPanelPreview family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._ButtonPanelPreview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local math_max = math.max
local StyleMirroredIconFrame = ST._StyleMirroredIconFrame
local GetStoredConditionalPreviewState = ST._GetStoredConditionalPreviewState
local GetConditionalPreviewTiming = ST._GetConditionalPreviewTiming
local ApplyIconCountTextStyle = ST._ApplyIconCountTextStyle
local AnchorIconFill = ST._AnchorIconFill
local ApplyIconFillGeometry = ST._ApplyIconFillGeometry
local ApplyIconFillLayer = ST._ApplyIconFillLayer
local ResolveIconFillTimerValue = ST._ResolveIconFillTimerValue

local PP = ST._ButtonPanelPreview

local function StyleIconEntry(slot, buttonData, group)
    StyleMirroredIconFrame(slot, { buttonData = buttonData }, group)

    -- Keybind label: live icon buttons pin this above every layer so it stays
    -- readable whatever is drawn over the icon (IconMode.lua). Same font keys,
    -- anchor contract, and resolver as live icons - GetDisplayedKeybindText,
    -- which honors customKeybindText (the text mirror stays on GetKeybindText
    -- by design; see Keybinds.lua). Static lookups only, never live frame
    -- state.
    --
    -- A member of an Aura Only Section is drawn by Blizzard's packed container
    -- and never by a CC button, so the live styler draws it no keybind replica
    -- (AuraDisplay's aura-panel host branch). The panel's showKeybindText still
    -- reads true for the base grid beside it, making this a per-ENTRY answer.
    -- Custom keybind text rides the same resolver and goes dark with it, which
    -- is what the world shows.
    local style = group and group.style or {}
    if CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    end
    local text
    if style.showKeybindText and CooldownCompanion.GetDisplayedKeybindText
        and not ST.IsAuraSectionEntry(group, buttonData) then
        -- Item entries resolve their bind by the EQUIPPED/effective item id,
        -- and equipment-slot entries carry no id of their own, so pass the
        -- same override live passes. ResolveEffectiveItem is pure C_Item /
        -- ItemLocation; requestLoad = false keeps the preview from kicking off
        -- item-data loads.
        local overrideId
        if CooldownCompanion.IsEntryItemLike and CooldownCompanion.IsEntryItemLike(buttonData)
            and CooldownCompanion.ResolveEffectiveItem then
            local effectiveItem = CooldownCompanion.ResolveEffectiveItem(buttonData, false)
            overrideId = effectiveItem and effectiveItem.itemID
        end
        text = CooldownCompanion:GetDisplayedKeybindText(buttonData, overrideId, nil)
        if text == "" then text = nil end
    end
    if text then
        local host = slot.keybindHost
        if not host then
            host = CreateFrame("Frame", nil, slot)
            host:SetAllPoints(slot)
            slot.keybindHost = host
            slot.keybindText = host:CreateFontString(nil, "OVERLAY")
        end
        -- Live pins the keybind above everything, including the loss-of-control
        -- cooldown (Helpers.lua: locCooldown at top+1, pinned text at top+2).
        -- Mirror that order here: aura swipe +0, text overlay +1, LoC +2, so
        -- the keybind takes +3 or the LoC swipe draws over the label.
        host:SetFrameLevel(slot.cooldown:GetFrameLevel() + 3)
        local kb = slot.keybindText
        CooldownCompanion.ApplyFontStyle(kb, style, "keybind", 10)
        kb:ClearAllPoints()
        kb:SetPoint(style.keybindAnchor or "TOPRIGHT",
            style.keybindXOffset or -2, style.keybindYOffset or -2)
        kb:SetText(text)
        kb:Show()
    elseif slot.keybindText then
        slot.keybindText:Hide()
    end
end

------------------------------------------------------------------------
-- Conditional visual previews on the mirror (icon panels): while a preview
-- toggle is active for an entry or its whole panel, render a config-only
-- stand-in from Preview.lua's stored state and timing contract. Times are
-- literal numbers from that state; this never reads live cooldowns.
------------------------------------------------------------------------
local ICON_FILL_TEXTURE = "Interface\\Buttons\\WHITE8x8"
-- VisualState.lua DEFAULT_ICON_FILL_COOLDOWN_COLOR
local DEFAULT_ICON_FILL_COOLDOWN_COLOR = { 0.6, 0.13, 0.18, 0.55 }

-- Level base for slot sub-widgets that must render above the slot's
-- busiest layer: the cooldown swipe on icon slots, the text frame on
-- bar slots.
local function GetSlotOverlayBaseLevel(slot)
    if slot.cooldown then
        return slot.cooldown:GetFrameLevel()
    end
    if slot.textFrame then
        return slot.textFrame:GetFrameLevel()
    end
    return slot:GetFrameLevel()
end

-- Hosts the count/aura text stand-ins above the cooldown swipe, like
-- the live buttons' overlayFrame.
local function EnsureSlotTextOverlay(slot)
    local overlay = slot.textOverlay
    if not overlay then
        overlay = CreateFrame("Frame", nil, slot)
        overlay:SetAllPoints()
        overlay:EnableMouse(false)
        slot.textOverlay = overlay
    end
    overlay:SetFrameLevel(GetSlotOverlayBaseLevel(slot) + 1)
    return overlay
end

local function EnsureSlotCountText(slot)
    if not slot.count then
        slot.count = EnsureSlotTextOverlay(slot):CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    else
        EnsureSlotTextOverlay(slot)
    end
    return slot.count
end

local function EnsureSlotAuraText(slot)
    if not slot.auraTextFS then
        slot.auraTextFS = EnsureSlotTextOverlay(slot):CreateFontString(nil, "OVERLAY")
    else
        EnsureSlotTextOverlay(slot)
    end
    return slot.auraTextFS
end

-- The pandemic marker rides the aura duration text, so its preview IS the
-- duration-text stand-in with the marker appended. Every render path below
-- sends the same remaining value through the live feature's manual twin,
-- which composes Duration Format, Low Time Threshold, and Pandemic precedence.
-- The marker's own descriptor is what keeps the sweep inside the window.
local function IsAuraDurationTextKind(kind)
    return kind == "aura_duration_text" or kind == "pandemic_marker"
end

-- Honest about the entry's own switch: an entry with the marker turned off
-- previews the low-time-aware bare countdown rather than a marker it will
-- never draw.
local function FormatAuraDurationPreviewText(remaining, kind, style, buttonData, allowLowTime)
    local pandemicActive = kind == "pandemic_marker"
        and CooldownCompanion:IsPandemicMarkerPreviewWanted(buttonData, style)
    return CooldownCompanion:FormatAuraDurationPreviewText(remaining, style, pandemicActive, allowLowTime)
end

local function EnsureSlotAuraStackText(slot)
    if not slot.auraStackCount then
        slot.auraStackCount = EnsureSlotTextOverlay(slot):CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    else
        EnsureSlotTextOverlay(slot)
    end
    return slot.auraStackCount
end

local function EnsureSlotAuraSwipe(slot)
    local widget = slot.auraSwipe
    if not widget then
        widget = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
        widget:SetAllPoints(slot.icon)
        widget:SetDrawBling(false)
        widget:SetHideCountdownNumbers(true)
        widget:EnableMouse(false)
        slot.auraSwipe = widget
    end
    widget:SetFrameLevel(slot.cooldown:GetFrameLevel())
    return widget
end

local function EnsureSlotLocCooldown(slot)
    local widget = slot.locCooldown
    if not widget then
        widget = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
        widget:SetAllPoints(slot.icon)
        widget:SetDrawBling(false)
        widget:SetHideCountdownNumbers(true)
        widget:EnableMouse(false)
        -- Fixed styling per IconMode.lua CreateButtonFrame's locCooldown
        widget:SetDrawEdge(true)
        widget:SetDrawSwipe(true)
        widget:SetSwipeColor(0.17, 0, 0, 0.8)
        slot.locCooldown = widget
    end
    widget:SetFrameLevel(GetSlotOverlayBaseLevel(slot) + 2)
    return widget
end

-- Self-animating fill, like the live icon fill's OnUpdate driver; reads
-- the stored preview state so loop wraps need no external re-arm.
local function SlotIconFillOnUpdate(self)
    local slot = self._owner
    local state = slot and slot._cdcCondAnim
    if not (state and GetConditionalPreviewTiming and ResolveIconFillTimerValue) then return end
    local startTime, duration, remaining = GetConditionalPreviewTiming(state, GetTime())
    if not (startTime and duration and duration > 0) then return end
    self:SetValue(ResolveIconFillTimerValue(slot, 1 - (remaining / duration)))
end

local function EnsureSlotIconFill(slot)
    local fill = slot.iconFill
    if not fill then
        fill = CreateFrame("StatusBar", nil, slot)
        fill._owner = slot
        fill:SetMinMaxValues(0, 1)
        fill:SetStatusBarTexture(ICON_FILL_TEXTURE)
        fill:EnableMouse(false)
        slot.iconFill = fill
    end
    if AnchorIconFill then AnchorIconFill(slot) end
    if ApplyIconFillLayer then ApplyIconFillLayer(slot) end
    return fill
end

local function ResetSlotConditionalVisuals(slot)
    slot._cdcCondAnim = nil
    slot._cdcCondArmedStart = nil
    if slot.cooldown then
        slot.cooldown:Clear()
        slot.cooldown:Hide()
    end
    if slot.auraSwipe then
        slot.auraSwipe:Clear()
        slot.auraSwipe:Hide()
    end
    if slot.locCooldown then
        slot.locCooldown:Clear()
        slot.locCooldown:Hide()
    end
    if slot.auraTextFS then
        slot.auraTextFS:Hide()
    end
    if slot.auraStackCount then
        slot.auraStackCount:SetText("")
        slot.auraStackCount:Hide()
    end
    if slot.count then
        slot.count:SetText("")
    end
    if slot.iconFill then
        slot.iconFill:SetScript("OnUpdate", nil)
        slot.iconFill:Hide()
    end
end

-- Cooldown text: like live icon mode, restyle the widget's built-in
-- countdown region and let it count the fake loop down. Reapplied after
-- every SetCooldown re-arm (the CooldownFrame may reset the region).
-- Passive aura entries never show cooldown text (live parity).
local function StyleSlotCooldownText(slot, style)
    local region = slot.cooldown:GetRegions()
    if not (region and region.SetFont) then return end
    if style.showCooldownText and not (slot.buttonData and slot.buttonData.isPassive) then
        slot.cooldown:SetHideCountdownNumbers(false)
        if CooldownCompanion.ApplyDurationFormatToCooldown then
            CooldownCompanion.ApplyDurationFormatToCooldown(slot.cooldown, style)
        end
        CooldownCompanion.ApplyFontStyle(region, style, "cooldown")
        region:ClearAllPoints()
        region:SetPoint(style.cooldownTextAnchor or "CENTER",
            style.cooldownTextXOffset or 0, style.cooldownTextYOffset or 0)
    else
        slot.cooldown:SetHideCountdownNumbers(true)
    end
end

-- Renders the entry's active conditional preview (if any) onto its
-- mirror slot, and always restores the baseline tint/desaturation a
-- recycled slot may carry. Runs after the entry-status desaturation:
-- previews may force desaturation on, never off. Each branch follows the
-- corresponding runtime presentation rules and shared style helpers.
local function ApplySlotConditionalPreview(slot, buttonData, group, panelId, index)
    ResetSlotConditionalVisuals(slot)
    -- Read by ApplyIconCountTextStyle and StyleSlotCooldownText
    slot.buttonData = buttonData

    local style = slot.style or group.style or {}
    -- Stamped for the conditional ticker, which re-renders the aura text
    -- countdown with only the slot in hand. Mirrors the live bind's gate
    -- (AllowAuraDurationLowTime): Aura Panels apply unconditionally, and so
    -- do mixed-panel Aura-section entries — they render through the same
    -- auraPanel host kind live.
    slot._cdcAuraLowTime = CooldownCompanion.AllowAuraDurationLowTime(
        style, ST.IsAuraPanelGroup(group)
            or ST.IsAuraSectionEntry(group, buttonData))
    -- Tracking.lua ResolveIconTintIntent: base = configured icon tint.
    local baseTint = style.iconTintColor
    local tintR = baseTint and baseTint[1] or 1
    local tintG = baseTint and baseTint[2] or 1
    local tintB = baseTint and baseTint[3] or 1
    local tintA = baseTint and baseTint[4] or 1
    local forceDesat = false

    local state = GetStoredConditionalPreviewState
        and GetStoredConditionalPreviewState(panelId, index) or nil
    local kind = state and state.kind or nil
    local now = GetTime()

    -- Any aura-active stand-in mirrors the slot kit's desaturate-while-
    -- active (StyleSlotKit) when the live composition would put an aura-
    -- layer icon region over this slot.icon: keep-swipe entries skip the
    -- takeover unless the aura icon swap is on.
    if CooldownCompanion:IsAuraPreviewKindExposingShell(kind, false)
        and CooldownCompanion:ShouldDesaturateAuraLayerWhileActive(buttonData, style)
        and (not CooldownCompanion:IsKeepSpellCooldownSwipeEntry(buttonData, style)
            or style.auraShowAuraIcon == true) then
        forceDesat = true
    end

    -- The cooldown family: "cooldown" is the full state (text and rotation
    -- assistant panels still fire it); "cooldown_swipe" is that state with
    -- the countdown numbers withheld; "cooldown_text" is the countdown text
    -- alone on an otherwise resting slot (no fill, no desaturation, no tint).
    if (kind == "cooldown" or kind == "cooldown_swipe" or kind == "cooldown_text")
        and GetConditionalPreviewTiming then
        local startTime, duration = GetConditionalPreviewTiming(state, now)
        if startTime then
            local textOnly = kind == "cooldown_text"
            -- An active icon fill owns the cooldown visual and suppresses
            -- the swipe and edge (VisualState.lua SetIconFillIntent).
            local fillActive = not textOnly
                and style.iconFillEnabled == true
                and group.masqueEnabled ~= true
                and ResolveIconFillTimerValue ~= nil
            local cd = slot.cooldown
            local swipeEnabled = not textOnly
                and style.showCooldownSwipe ~= false and not fillActive
            cd:SetDrawSwipe(swipeEnabled and style.showCooldownSwipeFill ~= false)
            cd:SetDrawEdge(swipeEnabled and style.cooldownSwipeEdgeEnabled == true)
            cd:SetReverse(style.cooldownSwipeReverse or false)
            cd:SetSwipeColor(0, 0, 0, style.cooldownSwipeAlpha or 0.8)
            local edgeColor = style.cooldownSwipeEdgeColor or { 1, 1, 1, 1 }
            cd:SetEdgeColor(edgeColor[1], edgeColor[2], edgeColor[3], edgeColor[4])
            if kind == "cooldown_swipe" then
                cd:SetHideCountdownNumbers(true)
            else
                StyleSlotCooldownText(slot, style)
            end
            cd:Show()
            cd:SetCooldown(startTime, duration)
            slot._cdcCondAnim = state
            slot._cdcCondArmedStart = startTime

            if fillActive then
                local fill = EnsureSlotIconFill(slot)
                if ApplyIconFillGeometry then
                    ApplyIconFillGeometry(slot, style)
                end
                local c = style.iconFillCooldownColor or DEFAULT_ICON_FILL_COOLDOWN_COLOR
                fill:SetStatusBarColor(c[1], c[2], c[3], c[4])
                fill:SetScript("OnUpdate", SlotIconFillOnUpdate)
                fill:Show()
                SlotIconFillOnUpdate(fill)
            end

            if not textOnly then
                if style.desaturateOnCooldown then
                    forceDesat = true
                end
                if style.iconCooldownTintEnabled and style.iconCooldownTintColor then
                    local c = style.iconCooldownTintColor
                    tintR, tintG, tintB, tintA = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end
            end
        end
    elseif kind == "charge_full" or kind == "charge_missing" or kind == "charge_zero" then
        if CooldownCompanion.UsesChargeBehavior and CooldownCompanion.UsesChargeBehavior(buttonData) then
            local maxCharges = buttonData.maxCharges or 2
            if maxCharges < 2 then maxCharges = 2 end
            local current = maxCharges
            local colorKey = "chargeFontColor"
            if kind == "charge_missing" then
                current = math_max(1, maxCharges - 1)
                colorKey = "chargeFontColorMissing"
            elseif kind == "charge_zero" then
                current = 0
                colorKey = "chargeFontColorZero"
            end

            local count = EnsureSlotCountText(slot)
            if ApplyIconCountTextStyle then
                ApplyIconCountTextStyle(slot, style)
            end
            if style.showChargeText ~= false then
                count:SetText(current)
            end
            -- CooldownUpdate.lua ApplyChargeTextColor: only recolor when
            -- any charge color is configured at all.
            if style.chargeFontColor or style.chargeFontColorMissing or style.chargeFontColorZero then
                local cc = style[colorKey] or { 1, 1, 1, 1 }
                count:SetTextColor(cc[1], cc[2], cc[3], cc[4] or 1)
            end

            if kind == "charge_zero" then
                -- Live zero charges sets _desatCooldownActive, so the
                -- cooldown desaturate/tint options apply here too.
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
        -- Tracking.lua IsUnusableVisualActive: aura and passive entries
        -- never show castability state.
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
    elseif IsAuraDurationTextKind(kind) and GetConditionalPreviewTiming then
        if style.showAuraText ~= false then
            local startTime, _, remaining = GetConditionalPreviewTiming(state, now)
            if startTime then
                local fs = EnsureSlotAuraText(slot)
                CooldownCompanion.ApplyFontStyle(fs, style, "auraText", nil,
                    CooldownCompanion.DEFAULT_AURA_TEXT_COLOR)
                local anchor, xOff, yOff = CooldownCompanion:GetAuraDurationTextPlacement(style, buttonData)
                fs:ClearAllPoints()
                fs:SetPoint(anchor, slot, anchor, xOff, yOff)
                fs:SetText(FormatAuraDurationPreviewText(remaining, kind, style, buttonData,
                    slot._cdcAuraLowTime))
                fs:Show()
                slot._cdcCondAnim = state
            end
        end
    elseif kind == "aura_stack_text" then
        if style.showAuraStackText ~= false then
            local fs = EnsureSlotAuraStackText(slot)
            CooldownCompanion.ApplyFontStyle(fs, style, "auraStack")
            fs:ClearAllPoints()
            fs:SetPoint(style.auraStackAnchor or "BOTTOMLEFT",
                style.auraStackXOffset or 2, style.auraStackYOffset or 2)
            -- Threshold-aware stand-in (2026-08-15 program); helper lives in
            -- ButtonFrame/Helpers.lua.
            local asText, asR, asG, asB, asA = CooldownCompanion:GetAuraStackPreviewCountAndColor(
                buttonData, style, state.stackText)
            fs:SetText(asText)
            fs:SetTextColor(asR, asG, asB, asA)
            fs:Show()
        end
    elseif kind == "aura_duration_swipe" and GetConditionalPreviewTiming then
        if CooldownCompanion:ShouldDrawAuraDurationSwipe(buttonData, style) then
            local startTime, duration = GetConditionalPreviewTiming(state, now)
            if startTime then
                local widget = EnsureSlotAuraSwipe(slot)
                if CooldownCompanion.ApplyAuraDurationSwipeStyle then
                    CooldownCompanion:ApplyAuraDurationSwipeStyle(widget, style)
                end
                widget:Show()
                widget:SetCooldown(startTime, duration)
                slot._cdcCondAnim = state
                slot._cdcCondArmedStart = startTime
            end
        end
    elseif kind == "loss_of_control" and GetConditionalPreviewTiming then
        -- Runtime gate (Visibility.lua): spells only, never passives.
        if style.showLossOfControl and buttonData.type == "spell" and not buttonData.isPassive then
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

    slot.icon:SetVertexColor(tintR, tintG, tintB, tintA)
    if forceDesat then
        slot.icon:SetDesaturated(true)
    end
end

-- Private helpers consumed by later ButtonPanelPreview files.
PP.FormatAuraDurationPreviewText = FormatAuraDurationPreviewText
PP.IsAuraDurationTextKind = IsAuraDurationTextKind
PP.EnsureSlotCountText = EnsureSlotCountText
PP.EnsureSlotLocCooldown = EnsureSlotLocCooldown
PP.StyleSlotCooldownText = StyleSlotCooldownText
PP.StyleIconEntry = StyleIconEntry
PP.ResetSlotConditionalVisuals = ResetSlotConditionalVisuals
PP.ApplySlotConditionalPreview = ApplySlotConditionalPreview
