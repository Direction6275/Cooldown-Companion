--[[
    CooldownCompanion - ButtonFrame/CooldownUpdate
    Main per-tick cooldown orchestrator (UpdateButtonCooldown)
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals
local GetTime = GetTime
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local wipe = wipe
local issecretvalue = issecretvalue

-- Imports from Glows
local GetViewerAuraStackText = ST._GetViewerAuraStackText

-- Imports from Visibility
local EvaluateButtonVisibility = ST._EvaluateButtonVisibility

-- Pre-defined color constant tables to avoid per-tick allocation.
-- IMPORTANT: These tables are read-only — never write to their indices.
local DEFAULT_WHITE = {1, 1, 1, 1}

-- APIs for text-mode conditional tokens
local C_Spell_IsSpellUsable = C_Spell.IsSpellUsable
local IsUsableItem = C_Item.IsUsableItem
local IsItemInRange = C_Item.IsItemInRange
local InCombatLockdown = InCombatLockdown
local UnitCanAttack = UnitCanAttack

-- Imports from Utils
local HasTooltipCooldown = ST.HasTooltipCooldown

-- Imports from Tracking
local UpdateChargeTracking = ST._UpdateChargeTracking
local UpdateDisplayCountTracking = ST._UpdateDisplayCountTracking
local UpdateItemChargeTracking = ST._UpdateItemChargeTracking

-- Imports from IconMode
local ApplyIconCountTextStyle = ST._ApplyIconCountTextStyle
local UpdateIconModeVisuals = ST._UpdateIconModeVisuals
local UpdateIconModeGlows = ST._UpdateIconModeGlows

-- Imports from BarMode
local ApplyBarCountTextStyle = ST._ApplyBarCountTextStyle
local UpdateBarDisplay = ST._UpdateBarDisplay
local IsConfigButtonForceVisible = ST.IsConfigButtonForceVisible

-- Imports from TextMode
local UpdateTextDisplay = ST._UpdateTextDisplay

-- IsItemEquippable from Helpers (exported on CooldownCompanion)
local IsItemEquippable = CooldownCompanion.IsItemEquippable
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior
local UsesChargeTextLane = CooldownCompanion.UsesChargeTextLane
local HasCastCountText = CooldownCompanion.HasCastCountText
local GetCastCountSpellID = CooldownCompanion.GetCastCountSpellID
local TARGET_SWITCH_SAFETY_CAP = 0.60

local function AuraDataHasTimer(auraData)
    if not auraData then return false end
    local duration = auraData.duration
    if duration == nil then return false end
    if issecretvalue(duration) then return nil end
    return duration > 0
end

local function MergeAuraTimerState(currentHasTimer, auraData)
    local hasTimer = AuraDataHasTimer(auraData)
    if hasTimer ~= nil then
        return hasTimer
    end
    return currentHasTimer
end

local function GetViewerNameFontString(viewerFrame)
    -- BuffBar viewer items render name text on Bar.Name. BuffIcon entries have no name text.
    local bar = viewerFrame and viewerFrame.Bar
    return bar and bar.Name or nil
end

-- Hidden scratch CooldownFrame for probing DurationObject activity.
-- DurationObject:IsZero() returns a secret boolean in tainted contexts;
-- feeding the object to a Cooldown widget and checking IsShown() yields
-- a plain boolean safe for Lua logic.  Used by action-slot and totem
-- probes, which have no isActive companion field on their return values.
local scratchParent = CreateFrame("Frame")
scratchParent:Hide()
local scratchCooldown = CreateFrame("Cooldown", nil, scratchParent, "CooldownFrameTemplate")

local function DurationObjectShowsCooldown(durationObj)
    if not durationObj then return false end
    scratchCooldown:SetCooldownFromDurationObject(durationObj)
    local shown = scratchCooldown:IsShown()
    scratchCooldown:SetCooldown(0, 0)
    return shown
end

local function GetConfiguredAuraUnit(buttonData)
    return buttonData.auraUnit or "player"
end

-- GCD-only detection: is the spell's cooldown just the global cooldown?
-- NeverSecret path uses direct field comparison (precise at GCD boundaries).
-- Secret path uses isOnGCD + _gcdActive (coarser, avoids secret arithmetic).
local function IsSpellGCDOnly(info, secrecy)
    local gcdInfo = CooldownCompanion._gcdInfo
    if not gcdInfo then return false end
    if secrecy == 0 then
        return (info.startTime == gcdInfo.startTime
            and info.duration == gcdInfo.duration)
    else
        return info.isOnGCD and CooldownCompanion._gcdActive
    end
end

-- Deferred spell cooldown detection: distinguish true held cooldowns from
-- start-recovery / empower recovery windows. In 12.0.1, unrelated spells can
-- transiently report isEnabled=false, isActive=false, and a positive
-- timeUntilEndOfStartRecovery while an empowered cast is being held. That
-- state should not drive cooldown desaturation, bar fill, text placeholders,
-- or hide-on-cooldown visibility. Treat it as recovery-only, not deferred CD.
local function IsSpellCooldownDeferred(info)
    if not info or info.isEnabled ~= false or info.isActive == true then
        return false
    end

    if info.isOnGCD == true then
        return false
    end

    local recoveryTime = info.timeUntilEndOfStartRecovery
    if recoveryTime == nil then
        return true
    end

    if issecretvalue(recoveryTime) then
        -- Secret recovery values are unreadable in restricted states; when they
        -- coincide with the GCD the earlier guard already classifies them as
        -- recovery-only. Outside that case, keep the existing deferred-cooldown
        -- behavior until a concrete counterexample is observed in game.
        return true
    end

    return recoveryTime <= 0
end

-- Probe action-slot cooldown state for a spell ID pair (base + display override).
-- Returns:
--   shown      : true/false/nil (nil = no slots found or unknown from secret state)
--   durationObj: active LuaDurationObject when shown, else nil
local actionSlotSeenScratch = {}

local function ProbeActionSlotsForSpellID(spellID)
    if not spellID then return false, nil, false, false end

    local slots = C_ActionBar.FindSpellActionButtons(spellID)
    if not slots then return false, nil, false, false end

    local sawAnySlot = false
    local sawUnknown = false

    for _, slot in ipairs(slots) do
        if not actionSlotSeenScratch[slot] then
            actionSlotSeenScratch[slot] = true
            sawAnySlot = true

            local durationObj = C_ActionBar.GetActionCooldownDuration(slot)
            local shown = false

            if durationObj then
                -- IsZero() returns a secret boolean in tainted contexts;
                -- feed through a hidden Cooldown widget for a plain boolean.
                scratchCooldown:SetCooldownFromDurationObject(durationObj)
                shown = scratchCooldown:IsShown()
                scratchCooldown:SetCooldown(0, 0)
            else
                sawUnknown = true
            end

            if shown then
                return true, durationObj, sawAnySlot, sawUnknown
            end
        end
    end

    return false, nil, sawAnySlot, sawUnknown
end

local function ProbeActionSlotCooldownForSpell(baseSpellID, displaySpellID)
    if not baseSpellID then return nil, nil end

    wipe(actionSlotSeenScratch)

    local sawAnySlot = false
    local sawUnknown = false

    local shown, durationObj, sawAny, sawUnk = ProbeActionSlotsForSpellID(baseSpellID)
    if sawAny then sawAnySlot = true end
    if sawUnk then sawUnknown = true end
    if shown then
        return true, durationObj
    end

    if displaySpellID and displaySpellID ~= baseSpellID then
        shown, durationObj, sawAny, sawUnk = ProbeActionSlotsForSpellID(displaySpellID)
        if sawAny then sawAnySlot = true end
        if sawUnk then sawUnknown = true end
        if shown then
            return true, durationObj
        end
    end

    if sawAnySlot then
        if sawUnknown then
            return nil, nil
        end
        return false, nil
    end

    return nil, nil
end

function CooldownCompanion:UpdateButtonCooldown(button)
    local buttonData = button.buttonData
    local style = button.style
    local usesChargeBehavior = UsesChargeBehavior(buttonData)
    local useChargeTextLane = UsesChargeTextLane(buttonData)
    local now = GetTime()
    local isGCDOnly = false
    local desatWasActive = button._desatCooldownActive == true
    local wasAuraActive = button._auraActive == true

    if button.count and button._countTextLaneStyled ~= useChargeTextLane then
        if button._isBar then
            ApplyBarCountTextStyle(button, style)
        elseif not button._isText then
            ApplyIconCountTextStyle(button, style)
        else
            button._countTextLaneStyled = useChargeTextLane
        end
    end

    -- For transforming spells (e.g. Command Demon → pet ability), use the
    -- current override spell for cooldown queries. _displaySpellId is set
    -- by UpdateButtonIcon on SPELL_UPDATE_ICON and creation.
    -- Lazy-cache no-cooldown detection for spells (GCD-only, no real CD).
    -- Computed once (nil → true/false), reset in UpdateButtonStyle on respec.
    if button._noCooldown == nil then
        if buttonData.type == "spell" and not buttonData.isPassive and not usesChargeBehavior then
            local baseCd = GetSpellBaseCooldown(buttonData.id)
            button._noCooldown = (not baseCd or baseCd == 0) and not HasTooltipCooldown(buttonData.id)
        else
            button._noCooldown = false
        end
    end

    local cooldownSpellId = button._displaySpellId or buttonData.id

    -- Deferred icon refresh for cdmChildSlot buttons (set by OnSpellUpdateIcon).
    -- One-tick delay ensures the CDM viewer's RefreshSpellTexture has already
    -- run, so child.Icon:GetTextureFileID() returns the current texture.
    if button._iconDirty then
        button._iconDirty = nil
        CooldownCompanion:UpdateButtonIcon(button)
        cooldownSpellId = button._displaySpellId or buttonData.id
    end

    -- Per-tick icon staleness detection for silent transforms (e.g. Tiger's Fury
    -- changing Rake/Rip icons). GetSpellTexture dynamically resolves the current
    -- visual, but no event fires for these transforms. cdmChildSlot buttons
    -- already have their own per-tick viewer-based icon re-sync.
    -- Event-driven updates (_iconDirty) remain instant (handled above).
    if buttonData.type == "spell" and not buttonData.cdmChildSlot then
        local freshIcon = C_Spell.GetSpellTexture(buttonData.id)
        if freshIcon and freshIcon ~= button._lastSpellTexture then
            button._lastSpellTexture = freshIcon
            CooldownCompanion:UpdateButtonIcon(button)
            cooldownSpellId = button._displaySpellId or buttonData.id
        end
    end

    -- Proc state: event-driven table lookup (base spell + current displayed override).
    -- Keeps visibility and glow checks aligned without polling overlay APIs.
    local procOverlayActive = false
    if buttonData.type == "spell" and not buttonData.isPassive then
        local displaySpellId = button._displaySpellId
        procOverlayActive = CooldownCompanion.procOverlaySpells[buttonData.id] ~= nil
        if not procOverlayActive and displaySpellId and displaySpellId ~= buttonData.id then
            procOverlayActive = CooldownCompanion.procOverlaySpells[displaySpellId] ~= nil
        end
    end

    -- Clear per-tick DurationObject; set below if cooldown/aura active.
    -- Used by bar fill, desaturation, visibility checks instead of
    -- GetCooldownTimes() which returns secret values after
    -- SetCooldownFromDurationObject() in 12.0.1.
    -- Save previous aura DurationObject for one-tick grace period on target switch.
    local prevAuraDurationObj = button._auraActive and button._durationObj or nil
    button._durationObj = nil
    button._cooldownDeferred = nil

    -- Fetch cooldown data and update the cooldown widget.
    -- isOnGCD is NeverSecret (always readable even during restricted combat).
    local fetchOk, isOnGCD
    local spellCooldownInfo
    local spellCooldownDuration
    local actionSlotCooldownShown
    local actionSlotDurationObj
    -- Aura-override probe: cached for reuse by secondary CD and sound alerts.
    local auraProbeInfo, auraProbeIsGCDOnly

    -- Aura tracking: check for active buff/debuff and override cooldown swipe
    local auraOverrideActive = false
    local auraHasTimer = button._auraHasTimer == true
    local auraTrackingReady = buttonData.isPassive == true
    -- Capture and clear event-driven removal flag (set by OnUnitAura when
    -- removedAuraInstanceIDs confirms the aura is gone).  Used to bypass the
    -- grace hold, which otherwise can't detect expiry in combat (secret values).
    local auraEventRemoved = button._auraEventRemoved
    button._auraEventRemoved = nil
    if buttonData.auraTracking and button._auraSpellID then
        local configUnit = GetConfiguredAuraUnit(buttonData)
        local auraUnit = button._auraUnit or configUnit

        local viewerFrame
        local cdmEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled") == true

        -- Viewer-based aura tracking: Blizzard's cooldown viewer frames run
        -- untainted code that matches spell IDs to auras during combat and
        -- stores auraInstanceID + auraDataUnit as plain readable properties.
        -- Requires the Blizzard Cooldown Manager to be visible with this spell.
        -- CDM child slot: use specific child for multi-entry spells (e.g., Diabolic Ritual)
        if buttonData.cdmChildSlot then
            local allChildren = CooldownCompanion.viewerAuraAllChildren[buttonData.id]
            if allChildren then
                viewerFrame = allChildren[buttonData.cdmChildSlot]
            end
        end
        -- Try each override ID (comma-separated), prefer one with active aura.
        -- Cache parsed IDs on the button to avoid per-tick gmatch allocation.
        if not viewerFrame and buttonData.auraSpellID then
            local ids = button._parsedAuraIDs
            if not ids or button._parsedAuraIDsRaw ~= buttonData.auraSpellID then
                ids = {}
                for id in tostring(buttonData.auraSpellID):gmatch("%d+") do
                    ids[#ids + 1] = tonumber(id)
                end
                button._parsedAuraIDs = ids
                button._parsedAuraIDsRaw = buttonData.auraSpellID
            end
            for _, numId in ipairs(ids) do
                local f = CooldownCompanion:ResolveBuffViewerFrameForSpell(numId)
                if f then
                    if f.auraInstanceID then
                        viewerFrame = f
                        break
                    elseif not viewerFrame then
                        viewerFrame = f
                    end
                end
            end
        end
        -- Fall back to resolved aura ID, then ability ID, then current override form.
        -- _displaySpellId tracks the current override (e.g. Solar → Lunar Eclipse)
        -- and is always present in the viewer map after BuildViewerAuraMap.
        if not viewerFrame then
            viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(button._auraSpellID)
            if not viewerFrame then
                viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(buttonData.id)
                    or (button._displaySpellId and CooldownCompanion:ResolveBuffViewerFrameForSpell(button._displaySpellId))
                -- Try base spell for form-variant spells (e.g. Stampeding Roar)
                if not viewerFrame then
                    local baseId = C_Spell.GetBaseSpell(buttonData.id)
                    if baseId and baseId ~= buttonData.id and baseId ~= button._auraSpellID then
                        viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(baseId)
                    end
                end
            end
        end
        auraTrackingReady = CooldownCompanion:IsAuraTrackingReady(buttonData, cdmEnabled, viewerFrame)
        if auraTrackingReady and not auraOverrideActive and viewerFrame and (auraUnit == "player" or auraUnit == "target") then
            local viewerInstId = viewerFrame.auraInstanceID
            if viewerInstId then
                local unit = viewerFrame.auraDataUnit or auraUnit
                local durationObj = C_UnitAuras.GetAuraDuration(unit, viewerInstId)
                -- Gate on unit compatibility: CDM's GetAuraData() checks player
                -- auras first, so auraDataUnit can incorrectly be "player" for a
                -- viewer child that tracks a target debuff.  Reject the mismatch
                -- so target-debuff buttons don't display random player buff durations.
                if durationObj and unit == configUnit then
                    -- Cross-validate: confirm the aura instance actually exists
                    -- on the claimed unit.  GetAuraDuration may return data for
                    -- stale instance IDs that belong to a different unit (e.g.
                    -- old target after a target switch), causing ghost auras.
                    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, viewerInstId)
                    if auraData then
                        button._durationObj = durationObj
                        button._viewerBar = nil  -- primary path: DurationObject available
                        button.cooldown:SetCooldownFromDurationObject(durationObj)
                        button._auraInstanceID = viewerInstId
                        button._auraUnit = unit
                        auraOverrideActive = true
                        auraHasTimer = DurationObjectShowsCooldown(durationObj)
                        fetchOk = true
                    end
                end
            else
                -- No auraInstanceID — fall back to reading the viewer's cooldown widget.
                -- Covers spells where the viewer tracks the buff duration internally
                -- (auraDataUnit set by GetAuraData) but doesn't expose auraInstanceID.
                local viewerCooldown = viewerFrame.Cooldown
                if viewerFrame.auraDataUnit and viewerCooldown and viewerCooldown:IsShown() then
                    local startMs, durMs = viewerCooldown:GetCooldownTimes()
                    if not issecretvalue(durMs) then
                        -- Plain values: safe to do ms->s arithmetic
                        if durMs > 0 and (startMs + durMs) > now * 1000 then
                            local vUnit = viewerFrame.auraDataUnit or auraUnit
                            if vUnit == configUnit then
                                button.cooldown:SetCooldown(startMs / 1000, durMs / 1000)
                                button._auraUnit = vUnit
                                auraOverrideActive = true
                                auraHasTimer = true
                                fetchOk = true
                            end
                        end
                    else
                        -- Secret values: can't convert ms->s. Mark aura active;
                        -- grace period covers continuity from previous tick's display.
                        -- (HasSecretValues() on viewer widgets is unreliable when
                        -- Blizzard secure code set the values — check the returned
                        -- value directly with issecretvalue() instead.)
                        local vUnit = viewerFrame.auraDataUnit or auraUnit
                        if vUnit == configUnit then
                            button._auraUnit = vUnit
                            auraOverrideActive = true
                            fetchOk = true
                        end
                    end
                    if button._auraInstanceID then
                        button._auraInstanceID = nil
                    end
                end
                -- Fallback 2: GetTotemDuration for totem/summoning spells
                -- (TrackedBar category). Returns a LuaDurationObject.
                -- GetTotemDuration is a global (not C_Totem-namespaced).
                -- Read preferredTotemUpdateSlot directly from the viewer
                -- frame (plain number set by CDM) rather than caching it,
                -- since the slot may not be populated at BuildViewerAuraMap time.
                -- Guard: viewerFrame.totemData is non-nil only when CDM has
                -- validated that the totem slot still contains this child's
                -- spell (GetPreferredTotemSlotInfo checks spellID).  Without
                -- this, a stale preferredTotemUpdateSlot causes CC to read a
                -- different spell's totem duration after slot reuse.
                if not auraOverrideActive then
                    local totemSlot = viewerFrame.preferredTotemUpdateSlot
                    if totemSlot and viewerFrame:IsVisible() and viewerFrame.totemData then
                        local totemDuration = GetTotemDuration(totemSlot)
                        local totemActive = false
                        if totemDuration then
                            scratchCooldown:SetCooldownFromDurationObject(totemDuration)
                            totemActive = scratchCooldown:IsShown()
                            scratchCooldown:SetCooldown(0, 0)
                        end
                        if totemActive then
                            button.cooldown:SetCooldownFromDurationObject(totemDuration)
                            button._durationObj = totemDuration
                            auraOverrideActive = true
                            auraHasTimer = true
                            fetchOk = true
                            -- Bar mode: cache viewer's StatusBar for bar fill pass-through
                            if button._isBar and viewerFrame.Bar then
                                button._viewerBar = viewerFrame.Bar
                            end
                            if button._auraInstanceID then
                                button._auraInstanceID = nil
                            end
                        else
                            if button._isBar then
                                button._viewerBar = nil
                            end
                        end
                    end
                end
            end
        end
        -- Fallback: direct GetPlayerAuraBySpellID for player-tracked auras when
        -- the viewer path has no auraInstanceID (form-variant spells like
        -- Stampeding Roar where the CDM can't match the buff across shapeshifts).
        if auraTrackingReady and not auraOverrideActive and configUnit == "player" then
            local baseId = C_Spell.GetBaseSpell(buttonData.id)
            -- Try base spell first (buff is applied as base), then _auraSpellID
            local fallbackId = baseId and baseId ~= button._auraSpellID and baseId or nil
            local auraData = fallbackId and C_UnitAuras.GetPlayerAuraBySpellID(fallbackId)
            if not auraData then
                auraData = C_UnitAuras.GetPlayerAuraBySpellID(button._auraSpellID)
            end
            if auraData then
                local instId = auraData.auraInstanceID
                if instId and not issecretvalue(instId) then
                    local durationObj = C_UnitAuras.GetAuraDuration("player", instId)
                    if durationObj then
                        button._durationObj = durationObj
                        button._viewerBar = nil
                        button.cooldown:SetCooldownFromDurationObject(durationObj)
                        button._auraInstanceID = instId
                        button._auraUnit = "player"
                        auraOverrideActive = true
                        auraHasTimer = DurationObjectShowsCooldown(durationObj)
                        fetchOk = true
                    end
                end
            end
        end
        -- Cached instance ID fallback: when the viewer and GetPlayerAuraBySpellID
        -- both fail (restricted combat + form-variant spells), the previously-cached
        -- _auraInstanceID may still be valid.  GetAuraDuration works in restricted
        -- combat and the instance ID persists until OnUnitAura removal clears it.
        -- Target-debuff tracking intentionally skips this fallback because a stale
        -- target auraInstanceID can survive brief viewer churn and show ghost time.
        if auraTrackingReady and not auraOverrideActive and configUnit == "player" and button._auraInstanceID then
            local cachedUnit = button._auraUnit or configUnit
            if cachedUnit == configUnit then
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(cachedUnit, button._auraInstanceID)
                if auraData then
                    local durationObj = C_UnitAuras.GetAuraDuration(cachedUnit, button._auraInstanceID)
                    if durationObj then
                        button._durationObj = durationObj
                        button._viewerBar = nil
                        button.cooldown:SetCooldownFromDurationObject(durationObj)
                        auraOverrideActive = true
                        auraHasTimer = DurationObjectShowsCooldown(durationObj)
                        fetchOk = true
                    end
                end
            end
        end
        -- Grace period: if aura data is momentarily unavailable but we had an
        -- active aura DurationObject last tick, keep aura state alive.
        -- Restoring _durationObj preserves bar fill, color, and time text.
        -- Target-switch path: holds until UNIT_AURA confirms data received
        -- (debuff absent on new target) or primary path provides fresh data.
        -- Player path: DurationObject expiry + time-based grace window.
        if not auraOverrideActive and button._auraActive
           and prevAuraDurationObj and not buttonData.isPassive then
            local expired = false
            if auraEventRemoved then
                -- Server confirmed aura removal via UNIT_AURA
                -- removedAuraInstanceIDs — bypass grace hold entirely.
                -- Without this, combat secret values prevent
                -- GetRemainingDuration() from detecting expiry, causing
                -- a ~0.3s ghost hold on every aura-tracked proc consumed.
                expired = true
            elseif button._targetSwitchAt then
                -- CDM processes UNIT_TARGET before PLAYER_TARGET_CHANGED,
                -- so the viewer frame already reflects the new target.
                -- If CDM has no auraInstanceID, the debuff is confirmed
                -- absent on the new target — expire immediately.
                -- Ghost auras from stale instance IDs are prevented by the
                -- cross-validation (GetAuraDataByAuraInstanceID) in the
                -- viewer path, so this nil check is safe.
                if viewerFrame and not viewerFrame.auraInstanceID then
                    expired = true
                elseif button._targetSwitchDataReceived then
                    expired = true
                else
                    expired = (now - button._targetSwitchAt) > TARGET_SWITCH_SAFETY_CAP
                end
            elseif not prevAuraDurationObj:HasSecretValues() then
                expired = prevAuraDurationObj:GetRemainingDuration() <= 0
            end
            if not expired then
                if not button._auraGraceStart then
                    button._auraGraceStart = now
                end
                if now - button._auraGraceStart <= 0.3 or button._targetSwitchAt then
                    button._durationObj = prevAuraDurationObj
                    auraOverrideActive = true
                else
                    button._auraGraceStart = nil
                end
            else
                button._auraGraceStart = nil
                button._targetSwitchAt = nil
                button._targetSwitchDataReceived = nil
            end
        else
            button._auraGraceStart = nil
            if button._targetSwitchAt then
                if auraOverrideActive and button._durationObj then
                    -- Primary path provided fresh DurationObject: hold complete
                    button._targetSwitchAt = nil
                    button._targetSwitchDataReceived = nil
                elseif not button._auraActive then
                    -- Safety: _auraActive already false, clear stale hold
                    button._targetSwitchAt = nil
                    button._targetSwitchDataReceived = nil
                end
            end
        end
        -- Target-switch hold catch-all: preserve _auraActive for buttons
        -- without a previous DurationObject (tracked via fallback path only)
        if not auraOverrideActive and button._targetSwitchAt and button._auraActive then
            local catchAllExpired
            -- Same expiry logic as the grace period hold above.
            if viewerFrame and not viewerFrame.auraInstanceID then
                catchAllExpired = true
            elseif button._targetSwitchDataReceived then
                catchAllExpired = true
            else
                catchAllExpired = (now - button._targetSwitchAt) > TARGET_SWITCH_SAFETY_CAP
            end
            if catchAllExpired then
                button._targetSwitchAt = nil
                button._targetSwitchDataReceived = nil
            else
                button._durationObj = prevAuraDurationObj
                auraOverrideActive = true
            end
        end
        button._auraActive = auraOverrideActive
        if auraOverrideActive then
            button._auraHasTimer = auraHasTimer
        end
        if not auraOverrideActive then
            button._auraInstanceID = nil
            button._auraUnit = configUnit
        end

        -- Viewer icon change detection: for passive aura-tracked buttons, the
        -- viewer frame's Icon widget updates per-stage (e.g. Heating Up → Hot Streak)
        -- but UpdateButtonIcon is not called per-tick. Detect texture changes here
        -- and trigger an icon update only when the viewer icon actually changes.
        if buttonData.isPassive and viewerFrame then
            local iconObj = viewerFrame.Icon
            if iconObj and not iconObj.GetTextureFileID then
                iconObj = iconObj.Icon
            end
            if iconObj and iconObj.GetTextureFileID then
                local vfTexId = iconObj:GetTextureFileID()
                if issecretvalue(vfTexId) then
                    -- Secret in combat: can't compare, always refresh
                    -- (SetTexture accepts secret values as pass-through)
                    button._auraViewerFrame = viewerFrame
                    CooldownCompanion:UpdateButtonIcon(button)
                elseif vfTexId ~= button._lastViewerTexId then
                    button._lastViewerTexId = vfTexId
                    button._auraViewerFrame = viewerFrame
                    CooldownCompanion:UpdateButtonIcon(button)
                end
            end
        elseif buttonData.isPassive and button._lastViewerTexId then
            button._lastViewerTexId = nil
            button._auraViewerFrame = nil
            CooldownCompanion:UpdateButtonIcon(button)
        end

        -- Aura icon swap: trigger icon update on _auraActive transition
        if buttonData.auraShowAuraIcon and button._auraSpellID then
            local shouldShow = auraOverrideActive
            button._auraViewerFrame = shouldShow and viewerFrame or nil
            if shouldShow ~= (button._showingAuraIcon or false) then
                button._showingAuraIcon = shouldShow
                CooldownCompanion:UpdateButtonIcon(button)
            elseif shouldShow and viewerFrame then
                -- Detect viewer Icon texture changes for stage transitions
                -- within an already-active aura (e.g. Heating Up → Hot Streak).
                local iconObj = viewerFrame.Icon
                if iconObj and not iconObj.GetTextureFileID then
                    iconObj = iconObj.Icon
                end
                if iconObj and iconObj.GetTextureFileID then
                    local vfTexId = iconObj:GetTextureFileID()
                    if issecretvalue(vfTexId) then
                        -- Secret in combat: can't compare, always refresh
                        CooldownCompanion:UpdateButtonIcon(button)
                    elseif vfTexId ~= button._lastViewerTexId then
                        button._lastViewerTexId = vfTexId
                        CooldownCompanion:UpdateButtonIcon(button)
                    end
                end
            end
        else
            button._showingAuraIcon = nil
            -- Don't clear _auraViewerFrame for passive buttons — managed above
            if not buttonData.isPassive then
                button._auraViewerFrame = nil
            end
        end

        -- Read aura stack text from viewer frame (combat-safe, secret pass-through)
        if button._auraTrackingReady or buttonData.isPassive then
            if auraOverrideActive and viewerFrame then
                button._auraStackText = GetViewerAuraStackText(viewerFrame)
            else
                button._auraStackText = ""
            end
        end

        -- Pandemic window check: read Blizzard's PandemicIcon from the viewer frame.
        -- Blizzard calculates the exact per-spell pandemic window internally and
        -- shows/hides PandemicIcon accordingly.  Use IsVisible() so that a
        -- PandemicIcon whose parent viewer item was hidden (e.g. aura expired
        -- before OnUpdate could clean it up) is not treated as active.
        -- Grace window: PandemicIcon lives on a pool-managed CDM child frame.
        -- During RefreshLayout, child frames are recycled and re-acquired,
        -- which briefly invalidates the viewerFrame reference resolved from
        -- the aura map.  During this window viewerFrame.PandemicIcon may be
        -- nil or stale, so hold pandemic state for a fixed wall-clock duration
        -- (0.3s) to absorb brief dropouts.  Time-based rather than tick-based
        -- so that rapid UNIT_AURA-driven UpdateAllCooldowns() calls during
        -- heavy combat don't burn through the grace window prematurely.
        -- Genuine pandemic end sets _inPandemic = false via event handlers
        -- (Aura.lua aura removal / target switch), causing the grace guard
        -- to fail on the next evaluation.  Aura reapplication (pandemic
        -- refresh) sets _pandemicGraceSuppressed, bypassing the grace hold
        -- entirely so pandemic clears immediately on refresh.
        local inPandemic = false
        if button._pandemicPreview then
            inPandemic = true
        -- Pandemic detection: style-level (Show Pandemic Glow) OR per-button visibility toggle.
        elseif auraOverrideActive and (style.showPandemicGlow ~= false or buttonData.hideAuraActiveExceptPandemic) and viewerFrame then
            local pi = viewerFrame.PandemicIcon
            if button._pandemicGraceSuppressed then
                -- Aura was just refreshed (pandemic recast).  Clear pandemic
                -- immediately regardless of PandemicIcon visibility — CDM may
                -- not have run its OnUpdate yet, leaving PandemicIcon stale.
                button._pandemicGraceSuppressed = nil
                button._pandemicGraceStart = nil
                -- inPandemic stays false
            elseif pi and pi:IsVisible() then
                inPandemic = true
                button._pandemicGraceStart = nil
            elseif button._inPandemic then
                -- Grace hold: absorbs brief CDM RefreshLayout recycling dropouts.
                -- Time-based rather than tick-based so rapid UNIT_AURA-driven
                -- UpdateAllCooldowns() calls don't burn through the window.
                if not button._pandemicGraceStart then
                    button._pandemicGraceStart = now
                end
                if now - button._pandemicGraceStart <= 0.3 then
                    inPandemic = true
                else
                    button._pandemicGraceStart = nil
                end
            end
        end
        button._inPandemic = inPandemic

        -- Pass through the CDM item's current name text when aura tracking is
        -- active. This mirrors CDM state-based names (e.g. Light/Moderate/Heavy).
        -- Icon is NOT passed through — UpdateButtonIcon is the sole authoritative source.
        if auraOverrideActive then
            if viewerFrame then
                local viewerName = GetViewerNameFontString(viewerFrame)
                if button.nameText and not buttonData.customName and viewerName and viewerName.GetText then
                    -- Pass through the CDM-rendered text directly; avoid calling viewer mixin methods
                    -- from tainted code (they can execute secret-value logic internally).
                    button.nameText:SetText(viewerName:GetText())
                end
                -- Multi-slot buttons read their icon from the viewer's Icon widget.
                -- Event-driven UpdateButtonIcon calls can race with the CDM viewer's
                -- internal icon update on transforms (e.g. Diabolic Ritual), so re-sync
                -- the icon every tick to ensure it reflects the viewer's current state.
                if buttonData.cdmChildSlot then
                    CooldownCompanion:UpdateButtonIcon(button)
                end
                button._viewerAuraVisualsActive = true
            end
        elseif button._viewerAuraVisualsActive then
            button._viewerAuraVisualsActive = nil
            if button.nameText and not buttonData.customName then
                local restoreSpellID = button._displaySpellId or buttonData.id
                local baseName = C_Spell.GetSpellName(restoreSpellID)
                if baseName then
                    button.nameText:SetText(baseName)
                end
            end
            -- Multi-slot buttons got their icon from per-tick viewer reads while
            -- the aura was active. Now that the aura has dropped, re-sync the icon
            -- to the viewer's current (base) state.
            if buttonData.cdmChildSlot then
                CooldownCompanion:UpdateButtonIcon(button)
            end
        end
    end
    button._auraTrackingReady = auraTrackingReady

    if buttonData.isPassive and not auraOverrideActive then
        button.cooldown:Hide()
    end

    -- Probe spell CD during aura override (shared by secondary CD and sound alerts).
    if auraOverrideActive and buttonData.type == "spell" and not buttonData.isPassive then
        auraProbeInfo = C_Spell.GetSpellCooldown(cooldownSpellId)
        auraProbeIsGCDOnly = auraProbeInfo and IsSpellGCDOnly(auraProbeInfo, buttonData._cooldownSecrecy) or false
    end

    -- Secondary cooldown text display during aura override
    if auraOverrideActive and button.secondaryCooldown then
        if buttonData.type == "spell" and not buttonData.isPassive then
            if auraProbeInfo then
                if not auraProbeIsGCDOnly then
                    local probeDuration = C_Spell.GetSpellCooldownDuration(cooldownSpellId)
                    if probeDuration and auraProbeInfo.isActive then
                        button.secondaryCooldown:SetCooldownFromDurationObject(probeDuration)
                        button._secondaryCdActive = true
                    else
                        button.secondaryCooldown:SetCooldown(0, 0)
                        button._secondaryCdActive = false
                    end
                else
                    button.secondaryCooldown:SetCooldown(0, 0)
                    button._secondaryCdActive = false
                end
            else
                button.secondaryCooldown:SetCooldown(0, 0)
                button._secondaryCdActive = false
            end
        elseif buttonData.type == "item" then
            local cdStart, cdDuration = C_Item.GetItemCooldown(buttonData.id)
            local probeIsGCDOnly = false
            if cdDuration and cdDuration > 0 then
                local gcdInfo = CooldownCompanion._gcdInfo
                if gcdInfo and cdStart == gcdInfo.startTime
                        and cdDuration == gcdInfo.duration then
                    probeIsGCDOnly = true
                end
            end
            if cdDuration and cdDuration > 0 and not probeIsGCDOnly then
                button.secondaryCooldown:SetCooldown(cdStart, cdDuration)
                button._secondaryCdActive = true
            else
                button.secondaryCooldown:SetCooldown(0, 0)
                button._secondaryCdActive = false
            end
        end
    elseif button.secondaryCooldown and button._secondaryCdActive then
        button._secondaryCdActive = false
        button.secondaryCooldown:SetCooldown(0, 0)
    end

    if not auraOverrideActive then
        if buttonData.type == "spell" and not buttonData.isPassive then
            -- isActive (NeverSecret, 12.0.1 hotfix) is authoritative for whether
            -- the UI should render a cooldown.  Action-slot probing is deferred to
            -- the nil-fallback below — only needed when GetSpellCooldown returns nil
            -- (vehicle bar, override bar edge cases).

            spellCooldownInfo = C_Spell.GetSpellCooldown(cooldownSpellId)
            if spellCooldownInfo then
                isOnGCD = spellCooldownInfo.isOnGCD
                isGCDOnly = IsSpellGCDOnly(spellCooldownInfo, buttonData._cooldownSecrecy)

                -- Deferred cooldown detection (e.g. Feign Death while the buff
                -- is active): keep true hold states on the deferred path, but
                -- exclude start-recovery / empower recovery windows. Those can
                -- report isEnabled=false before a real cooldown begins, and
                -- should not dim or hide unrelated spells as "on cooldown".
                if IsSpellCooldownDeferred(spellCooldownInfo) then
                    button._cooldownDeferred = true
                end

                -- Only fetch the DurationObject when the cooldown is active.
                -- When isActive is false the DurationObject is zero-span
                -- (12.0.1 hotfix), so SetCooldown(0,0) is equivalent and
                -- avoids the API call.
                if spellCooldownInfo.isActive then
                    spellCooldownDuration = C_Spell.GetSpellCooldownDuration(cooldownSpellId)
                end

                if spellCooldownDuration then
                    button._durationObj = spellCooldownDuration
                    button.cooldown:SetCooldownFromDurationObject(spellCooldownDuration)
                elseif not fetchOk then
                    button.cooldown:SetCooldown(0, 0)
                end
                fetchOk = true
            elseif not fetchOk then
                -- GetSpellCooldown returned nil: fall back to action-slot probe.
                -- Covers vehicle bar, override bar, and rare ContextuallySecret
                -- spells whose spell-level API is unavailable in combat.
                if not usesChargeBehavior and buttonData._cooldownSecrecy ~= 0 then
                    actionSlotCooldownShown, actionSlotDurationObj =
                        ProbeActionSlotCooldownForSpell(buttonData.id, cooldownSpellId)
                    if actionSlotDurationObj then
                        button._durationObj = actionSlotDurationObj
                        button.cooldown:SetCooldownFromDurationObject(actionSlotDurationObj)
                        fetchOk = true
                    end
                end
                -- Ensure widget is in a known state when all paths failed.
                if not fetchOk then
                    button.cooldown:SetCooldown(0, 0)
                end
            end
        elseif buttonData.type == "item" then
            button._isEquippableNotEquipped = false
            local isEquippable = IsItemEquippable(buttonData)
            if isEquippable and not C_Item.IsEquippedItem(buttonData.id) then
                button._isEquippableNotEquipped = true
                -- Suppress cooldown display: static desaturated icon
                button.cooldown:SetCooldown(0, 0)
                button._itemCdStart = 0
                button._itemCdDuration = 0
            else
                button._isEquippableNotEquipped = false
                local cdStart, cdDuration, enableCooldownTimer = C_Item.GetItemCooldown(buttonData.id)
                if not enableCooldownTimer and cdStart > 0 then
                    -- Deferred cooldown (e.g. Healthstone used in combat): the
                    -- timer hasn't started yet.  Suppress the swipe to prevent
                    -- flicker from cdStart advancing every tick with dur=0.
                    -- Downstream code uses _cooldownDeferred for desat/visibility.
                    button.cooldown:SetCooldown(0, 0)
                    button._itemCdStart = 0
                    button._itemCdDuration = 0
                    button._cooldownDeferred = true
                else
                    button.cooldown:SetCooldown(cdStart, cdDuration)
                    button._itemCdStart = cdStart
                    button._itemCdDuration = cdDuration
                    -- GCD-only detection for items: C_Item.GetItemCooldown returns
                    -- GCD values when the item is on GCD but has no real cooldown.
                    -- Item cooldown values are never secret; direct comparison is safe
                    -- (same pattern as NeverSecret spells above).
                    if cdDuration > 0 then
                        local gcdInfo = CooldownCompanion._gcdInfo
                        if gcdInfo and cdStart == gcdInfo.startTime
                                and cdDuration == gcdInfo.duration then
                            isGCDOnly = true
                        end
                    end
                end
            end
            fetchOk = true
        end
    end

    -- Update spell charge data before zero-charge state classification.
    -- When readable, charge count is authoritative for "zero charges" (unusable),
    -- even if the spell also has a per-cast cooldown lockout.
    local charges
    if usesChargeBehavior and buttonData.hasCharges and buttonData.type == "spell" then
        button._displayCountZeroUsabilityFallback = nil
        charges = UpdateChargeTracking(button, buttonData, cooldownSpellId)
    elseif usesChargeBehavior and buttonData._hasDisplayCount and buttonData.type == "spell" then
        UpdateDisplayCountTracking(button, buttonData, cooldownSpellId)
    elseif not usesChargeBehavior then
        -- hasCharges cleared: wipe stale charge state.
        button._currentReadableCharges = nil
        button._chargeCountReadable = nil
        button._zeroChargesConfirmed = nil
        button._chargeRecharging = nil
        button._chargeDurationObj = nil
        button._chargesSpent = nil
        button._chargeText = nil
        button._displayCountZeroUsabilityFallback = nil
        if buttonData.type == "spell" then
            button.count:SetText("")
        end
        -- Shared count-text lane for non-charge spells:
        --   1) Blizzard display/use counts (e.g. pooled/shared uses)
        --   2) Cast-count stacks (e.g. Mana Tea)
        -- Both intentionally reuse the charge-text font/toggle without driving
        -- charge-specific cooldown logic.
        if buttonData.type == "spell"
                and not (button._auraTrackingReady and button.style and button.style.showAuraStackText ~= false)
                and button.style and button.style.showChargeText then
            local displayCountShown = false
            local hasCastCountText = HasCastCountText(buttonData)
            if buttonData._hasDisplayCount then
                local displayCount = button.count:GetText()
                if issecretvalue(displayCount) then
                    displayCountShown = true
                elseif displayCount and displayCount ~= "" then
                    displayCountShown = true
                end
            end

            if not displayCountShown and hasCastCountText then
                -- Cast-count text is only shown for explicitly supported
                -- spell families. Use the current live spell/override path
                -- when it belongs to that family.
                button._chargeText = nil
                local castCountSpellID = GetCastCountSpellID(buttonData, cooldownSpellId)
                local castCount = castCountSpellID and C_Spell.GetSpellCastCount(castCountSpellID)
                if castCountSpellID and issecretvalue(castCount) then
                    button.count:SetText(castCount)
                elseif castCountSpellID and not issecretvalue(castCount) and castCount and castCount > 0 then
                    button.count:SetText(castCount)
                else
                    button.count:SetText("")
                end
            elseif not displayCountShown then
                button.count:SetText("")
            end
        elseif (buttonData._hasDisplayCount or HasCastCountText(buttonData)) and buttonData.type == "spell"
                and not (button._auraTrackingReady and button.style and button.style.showAuraStackText ~= false) then
            -- Count text disabled: ensure display/use-count and cast-count text is cleared.
            button.count:SetText("")
        elseif button._chargeText ~= nil then
            button._chargeText = nil
            button.count:SetText("")
        end
    end

    -- Store raw GCD state for downstream display logic.
    if button._postCastGCDHold then
        local holdExpired = button._postCastGCDHoldUntil and now > button._postCastGCDHoldUntil
        if holdExpired or not CooldownCompanion._gcdActive then
            button._postCastGCDHold = nil
            button._postCastGCDHoldUntil = nil
        end
    end

    -- ContextuallySecret spells can transiently report isOnGCD=true while a real
    -- short cooldown is already active. If we were already showing cooldown and
    -- still have active cooldown data, keep treating it as non-GCD-only.
    -- Scope this to the cast-start GCD for this spell only.
    -- isActive (NeverSecret, 12.0.1 hotfix) confirms a real cooldown is ticking,
    -- replacing the pre-hotfix action-slot probe that served the same purpose.
    -- Proc overlay guard: when SPELL_ACTIVATION_OVERLAY_GLOW_SHOW has fired for
    -- this spell, a proc may have reset its cooldown — let the GCD-only
    -- detection stand so the button saturates immediately.
    if buttonData.type == "spell"
       and not buttonData.hasCharges
       and not auraOverrideActive
       and buttonData._cooldownSecrecy ~= 0
       and button._postCastGCDHold
       and not procOverlayActive
       and isOnGCD
       and isGCDOnly
       and desatWasActive
       and not wasAuraActive
       and button._durationObj
       and spellCooldownInfo and spellCooldownInfo.isActive then
        isGCDOnly = false
    end

    button._isOnGCD = isOnGCD or false
    button._isGCDOnly = isGCDOnly

    -- Bar mode: suppress GCD-only display in bars (checked by UpdateBarFill OnUpdate).
    -- Skip for charge spells: their _durationObj is the recharge cycle, never the GCD.
    if button._isBar then
        button._barGCDSuppressed = fetchOk and isGCDOnly
            and not buttonData.hasCharges and not buttonData.isPassive
    end

    -- Bar mode icon-only GCD swipe.
    if button._isBar and button.iconGCDCooldown then
        local showBarGCDSwipe = (style.showBarIcon ~= false)
            and style.showGCDSwipe == true
            and buttonData.type == "spell"
            and isOnGCD == true
        if showBarGCDSwipe then
            local gcdDurationObj = CooldownCompanion._gcdDurationObj
            if not gcdDurationObj and spellCooldownDuration then
                gcdDurationObj = spellCooldownDuration
            end
            if gcdDurationObj then
                local iconGCDCooldown = button.iconGCDCooldown
                iconGCDCooldown:SetDrawEdge(style.showCooldownSwipeEdge ~= false)
                iconGCDCooldown:SetReverse(style.cooldownSwipeReverse or false)
                iconGCDCooldown:Hide()
                iconGCDCooldown:SetCooldownFromDurationObject(gcdDurationObj)
            else
                button.iconGCDCooldown:Hide()
            end
        else
            button.iconGCDCooldown:Hide()
        end
    end

    -- Charge count tracking: detect whether the main cooldown (0 charges)
    -- is active.  Filter GCD so only real cooldown reads as true.
    -- Item and readable-spell paths are always safe. Restricted-spell fallbacks
    -- that depend on button.cooldown or isGCDOnly are gated on not auraOverrideActive.
    if usesChargeBehavior then
        -- Default to non-zero each tick; set true only when a current probe confirms zero.
        button._mainCDShown = false
        if buttonData.type == "item" then
            -- Items: 0 charges = on cooldown. No GCD to filter.
            local chargeCount = C_Item.GetItemCount(buttonData.id, false, true)
            button._mainCDShown = (chargeCount == 0)
        elseif buttonData.type == "spell"
           and button._chargeCountReadable == true
           and button._currentReadableCharges ~= nil then
            -- Readable charge count is the source of truth for zero-charge state.
            -- Prevents short lockout cooldowns (e.g., dragonriding flyout abilities)
            -- from being misclassified as "zero charges".
            button._mainCDShown = (button._currentReadableCharges == 0)
        elseif buttonData.type == "spell" and buttonData._hasDisplayCount then
            -- Secret display counts do not expose a readable number in combat for
            -- some use-count spells. Do not guess zero-state from unrelated
            -- usability signals; leave the zero-state unknown instead.
            button._mainCDShown = false
        elseif buttonData.type == "spell" and buttonData.hasCharges then
            -- Restricted mode: charges unreadable (secret values).
            -- Action bar probe reflects the regular-cooldown DurationObject
            -- which is NOT charge-aware (isActive = isEnabled and startTime > 0
            -- and duration > 0).  It can report true during per-cast lockouts
            -- and recharge, so the _chargesSpent heuristic below guards both
            -- this path and the isActive fallback.
            local slotShown = ProbeActionSlotCooldownForSpell(buttonData.id, cooldownSpellId)
            if slotShown ~= nil then
                button._mainCDShown = slotShown and not isGCDOnly
            elseif not auraOverrideActive then
                -- No action bar slot found; use isActive (NeverSecret) directly.
                if spellCooldownInfo then
                    button._mainCDShown = spellCooldownInfo.isActive and not isGCDOnly
                else
                    button._mainCDShown = false
                end
            end
        end
    end

    -- Canonical zero-charge state for downstream visuals/visibility.
    -- _mainCDShown is the raw "main cooldown sweep shown" signal; suppress zero
    -- while we have explicit cast-history evidence that not all charges are spent.
    if usesChargeBehavior then
        -- Seed _chargesSpent when recharging without cast history (e.g. after
        -- /reload mid-recharge).  Defaults to maxCharges ("all spent") so the
        -- heuristic below does not suppress genuine zero-charge signals.
        -- OnSpellCast takes over on the next cast; full recharge resets the cycle.
        if button._chargeRecharging and not button._chargesSpent then
            button._chargesSpent = buttonData.maxCharges or 0
        end

        local zeroConfirmed = (button._mainCDShown == true)
        if zeroConfirmed
           and buttonData.type == "spell"
           and usesChargeBehavior
           and buttonData.hasCharges
           and button._chargeCountReadable ~= true then
            -- Heuristic: suppress zero-charge when cast history says charges remain.
            -- Applies to both the action bar probe and isActive fallback paths.
            -- The probe reflects the regular-cooldown DurationObject which is
            -- not charge-aware and can report true during lockouts/recharge;
            -- _chargesSpent provides authoritative cast-history evidence.
            local maxCharges = buttonData.maxCharges
            local spent = button._chargesSpent
            if maxCharges and maxCharges > 1 and spent and spent < maxCharges then
                zeroConfirmed = false
            end
        end
        button._zeroChargesConfirmed = zeroConfirmed
    else
        button._zeroChargesConfirmed = false
    end

    -- Canonical desaturation signal:
    -- For non-charge spells, use action-slot cooldown state when spell cooldown
    -- info is unavailable (nil-fallback probe). Otherwise use addon state.
    -- _cooldownDeferred: timer hasn't started (e.g. Healthstone in combat, Feign
    -- Death while buff active).  Treat as "on cooldown" for dimming/visibility.
    if buttonData.type == "item" then
        button._desatCooldownActive = (button._itemCdDuration and button._itemCdDuration > 0 and not isGCDOnly)
            or button._cooldownDeferred or false
    elseif usesChargeBehavior then
        button._desatCooldownActive = (button._zeroChargesConfirmed == true)
    else
        if actionSlotCooldownShown ~= nil and spellCooldownInfo == nil then
            button._desatCooldownActive = actionSlotCooldownShown
        else
            button._desatCooldownActive = (button._durationObj ~= nil) and (not isGCDOnly)
                or button._cooldownDeferred or false
        end
    end
    -- Track on-CD → off-CD transition for ready glow duration timer.
    -- desatWasActive is true only when the previous tick had an active cooldown,
    -- so nil → false (initial load) does NOT set a start time.
    if desatWasActive and button._desatCooldownActive == false then
        button._readyGlowStartTime = now
    elseif button._desatCooldownActive == true then
        button._readyGlowStartTime = nil
    end

    if not button._isBar and not button._isText then
        UpdateIconModeVisuals(button, buttonData, style, fetchOk, isOnGCD, isGCDOnly)
    end

    if usesChargeBehavior then
      if buttonData.type == "spell" and buttonData.hasCharges then
        -- Bar/text mode: charge bars are driven by the recharge DurationObject, not
        -- the main spell CD or GCD. Save and clear the main CD so recharge
        -- timing fully controls bar fill for charge spells.
        if (button._isBar or button._isText) and not auraOverrideActive and button._chargeDurationObj then
            button._durationObj = nil
        end

        -- Charge recharging state: charges.isActive (NeverSecret) is false when
        -- not recharging (at max charges, or start/duration zero) — exactly the
        -- semantic we need.
        if charges then
            button._chargeRecharging = charges.isActive
        else
            button._chargeRecharging = false
        end

        if not auraOverrideActive and button._chargeDurationObj then
            if not button._isBar and not button._isText then
                -- Icon mode: always set _durationObj, show recharge radial
                button._durationObj = button._chargeDurationObj
                button.cooldown:SetCooldownFromDurationObject(button._chargeDurationObj)
            elseif button._chargeRecharging then
                -- Bar/text mode: only set _durationObj if actually recharging
                button._durationObj = button._chargeDurationObj
            end
        elseif not button._isBar and not button._isText and not auraOverrideActive then
            -- Icon mode fallback: no chargeDurationObj, try fetching one.
            -- Clear if unavailable to prevent stale cooldown widget state.
            local chargeSpellID = cooldownSpellId or buttonData.id
            local fallbackDuration = C_Spell.GetSpellChargeDuration(chargeSpellID)
            if fallbackDuration then
                button.cooldown:SetCooldownFromDurationObject(fallbackDuration)
            else
                button.cooldown:SetCooldown(0, 0)
            end
        end

      elseif buttonData.type == "item" then
        UpdateItemChargeTracking(button, buttonData)

        -- Detect recharging via stored item cooldown values
        button._chargeRecharging = (button._itemCdDuration and button._itemCdDuration > 0 and not isGCDOnly)
            or button._cooldownDeferred or false
      end
    end

    -- Item count display (inventory quantity for non-equipment tracked items)
    if buttonData.type == "item" and not buttonData.hasCharges and not IsItemEquippable(buttonData) then
        local count = C_Item.GetItemCount(buttonData.id)
        if button._itemCount ~= count then
            button._itemCount = count
            if count and count >= 1 then
                button.count:SetText(count)
            else
                button.count:SetText("")
            end
        end
    end

    -- Aura stack count display (aura-tracking spells with stackable auras)
    -- Text is a secret value in combat — pass through directly to SetText.
    -- Blizzard sets it to "" when stacks <= 1 and the count string when > 1.
    if button.auraStackCount and (button._auraTrackingReady or buttonData.isPassive)
       and (style.showAuraStackText ~= false) then
        if button._auraActive then
            button.auraStackCount:SetText(button._auraStackText or "")
        else
            button.auraStackCount:SetText("")
        end
    end

    -- Charge text color: three-state (zero / partial / max).
    -- Direct comparison when readable charges available; flag fallback in restricted mode.
    if style.chargeFontColor or style.chargeFontColorMissing or style.chargeFontColorZero then
        local cc
        local cur = button._currentReadableCharges
        if usesChargeBehavior and button._chargeCountReadable == true and cur ~= nil and buttonData.maxCharges then
            if cur == 0 then
                cc = style.chargeFontColorZero or DEFAULT_WHITE
            elseif cur < buttonData.maxCharges then
                cc = style.chargeFontColorMissing or DEFAULT_WHITE
            else
                cc = style.chargeFontColor or DEFAULT_WHITE
            end
        elseif usesChargeBehavior then
            -- Restricted mode: charges unreadable via C_Spell.
            -- Use canonical zero state derived from _mainCDShown + cast history.
            if not button._chargeRecharging then
                cc = style.chargeFontColor or DEFAULT_WHITE             -- FULL (max charges)
            elseif button._zeroChargesConfirmed then
                cc = style.chargeFontColorZero or DEFAULT_WHITE         -- ZERO (all spent)
            else
                cc = style.chargeFontColorMissing or DEFAULT_WHITE      -- MISSING (recharging)
            end
        elseif UsesChargeTextLane(buttonData) then
            cc = style.chargeFontColor or DEFAULT_WHITE
        end
        if cc then
            button.count:SetTextColor(cc[1], cc[2], cc[3], cc[4])
        end
    end

    -- Per-button sound alerts (Blizzard-scoped events, CDM-valid only).
    if buttonData.type == "spell" then
        local soundCfg = buttonData.soundAlerts
        local hasSoundConfig = soundCfg and type(soundCfg.events) == "table" and next(soundCfg.events) ~= nil
        if hasSoundConfig then
            local currentCharges
            local maxCharges
            local chargeRecharging = false
            local chargeCooldownStartTime
            if usesChargeBehavior then
                if button._currentReadableCharges ~= nil then
                    currentCharges = button._currentReadableCharges
                elseif charges and charges.currentCharges ~= nil
                   and not issecretvalue(charges.currentCharges) then
                    currentCharges = charges.currentCharges
                end

                if charges then
                    maxCharges = charges.maxCharges
                elseif buttonData.maxCharges and buttonData.maxCharges > 0 then
                    maxCharges = buttonData.maxCharges
                end

                chargeRecharging = button._chargeRecharging
                if charges and charges.cooldownStartTime ~= nil
                   and not issecretvalue(charges.cooldownStartTime) then
                    chargeCooldownStartTime = charges.cooldownStartTime
                end
            end

            local cooldownActive
            if usesChargeBehavior then
                -- Charge spells: cooldown-active means zero available charges.
                if currentCharges ~= nil then
                    cooldownActive = (currentCharges == 0)
                else
                    cooldownActive = button._zeroChargesConfirmed == true
                end
            elseif auraOverrideActive then
                -- Aura visuals replace button.cooldown; reuse the shared
                -- probe computed above (same spell, same tick).
                if auraProbeInfo then
                    cooldownActive = auraProbeInfo.isActive and not auraProbeIsGCDOnly
                else
                    cooldownActive = false
                end
            else
                -- Normal path: isActive (NeverSecret)
                if spellCooldownInfo then
                    cooldownActive = spellCooldownInfo.isActive and not isGCDOnly
                else
                    cooldownActive = false
                end
            end

            self:UpdateButtonSoundAlerts(
                button,
                cooldownSpellId,
                isOnGCD or false,
                cooldownActive,
                auraOverrideActive,
                currentCharges,
                maxCharges,
                chargeRecharging,
                chargeCooldownStartTime
            )
        else
            button._sndInitialized = nil
        end
    end

    -- Per-button visibility evaluation (after charge tracking)
    EvaluateButtonVisibility(button, buttonData, isGCDOnly, auraOverrideActive, procOverlayActive)
    button._rawVisibilityHidden = button._visibilityHidden
    button._rawVisibilityAlphaOverride = button._visibilityAlphaOverride

    -- Config panel QOL: selected buttons in column 2 are always fully visible.
    local forceVisibleByConfig = IsConfigButtonForceVisible(button)
    if forceVisibleByConfig then
        button._visibilityHidden = false
        button._visibilityAlphaOverride = 1
    end
    button._forceVisibleByConfig = forceVisibleByConfig or nil

    -- Track visibility/force-visible state changes for compact layout reflow.
    local visibilityChanged = button._visibilityHidden ~= button._prevVisibilityHidden
    if visibilityChanged then
        button._prevVisibilityHidden = button._visibilityHidden
    end
    local forceVisibleChanged = button._forceVisibleByConfig ~= button._prevForceVisibleByConfig
    if forceVisibleChanged then
        button._prevForceVisibleByConfig = button._forceVisibleByConfig
    end
    if visibilityChanged or forceVisibleChanged then
        local groupFrame = button:GetParent()
        if groupFrame then groupFrame._layoutDirty = true end
    end

    -- Apply visibility alpha or early-return for hidden buttons
    local group = button._groupId and CooldownCompanion.db.profile.groups[button._groupId]
    if not group or not group.compactLayout then
        -- Non-compact mode: alpha=0 for hidden, restore for visible
        if button._visibilityHidden then
            button.cooldown:Hide()  -- prevent stale IsShown() across ticks
            if button._lastVisAlpha ~= 0 then
                button:SetAlpha(0)
                button._lastVisAlpha = 0
            end
            CooldownCompanion:UpdateAuraTextureVisual(button)
            return  -- Skip all visual updates
        else
            local targetAlpha = button._visibilityAlphaOverride or 1
            if button._lastVisAlpha ~= targetAlpha then
                button:SetAlpha(targetAlpha)
                button._lastVisAlpha = targetAlpha
            end
        end
    else
        -- Compact mode: Show/Hide handled by UpdateGroupLayout
        if button._visibilityHidden then
            -- Prevent stale IsShown() across ticks. SetCooldown(0,0) does not
            -- auto-hide the CooldownFrame; without this, bar mode _mainCDShown
            -- and icon mode force-show both read stale true on next tick.
            button.cooldown:Hide()
            CooldownCompanion:UpdateAuraTextureVisual(button)
            return  -- Skip visual updates for hidden buttons
        else
            local targetAlpha = button._visibilityAlphaOverride or 1
            if button._lastVisAlpha ~= targetAlpha then
                button:SetAlpha(targetAlpha)
                button._lastVisAlpha = targetAlpha
            end
        end
    end

    button._procOverlayActive = procOverlayActive

    -- Unusable/out-of-range state for text mode {unusable}/{oor} conditionals
    if button._isText then
        if buttonData.isPassive then
            button._isUnusable = false
        elseif buttonData.type == "spell" then
            button._isUnusable = not C_Spell_IsSpellUsable(buttonData.id)
        elseif buttonData.type == "item" or buttonData.type == "equipitem" then
            local usable = IsUsableItem(buttonData.id)
            button._isUnusable = not usable
        else
            button._isUnusable = false
        end

        if buttonData.type == "spell" then
            button._isOutOfRange = button._spellOutOfRange or false
        elseif buttonData.type == "item" or buttonData.type == "equipitem" then
            -- C_Item.IsItemInRange is protected in combat for non-enemy targets (10.2.0)
            if not InCombatLockdown() or UnitCanAttack("player", "target") then
                local inRange = IsItemInRange(buttonData.id, "target")
                button._isOutOfRange = (inRange == false)
            else
                button._isOutOfRange = false
            end
        else
            button._isOutOfRange = false
        end
    else
        button._isUnusable = false
        button._isOutOfRange = false
    end

    -- Mode-specific visual dispatch
    if button._isText then
        UpdateTextDisplay(button)
    elseif button._isBar then
        UpdateBarDisplay(button)
        CooldownCompanion:UpdateAuraTextureVisual(button)
    else
        UpdateIconModeGlows(button, buttonData, style, procOverlayActive)
        CooldownCompanion:UpdateAuraTextureVisual(button)
    end
end
