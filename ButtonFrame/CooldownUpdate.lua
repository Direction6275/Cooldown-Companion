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

-- Imports from Helpers
local scratchCooldown = ST._scratchCooldown

-- Imports from Glows
local GetViewerAuraStackText = ST._GetViewerAuraStackText

-- Imports from Visibility
local EvaluateButtonVisibility = ST._EvaluateButtonVisibility

-- Imports from Tracking
local UpdateChargeTracking = ST._UpdateChargeTracking
local UpdateItemChargeTracking = ST._UpdateItemChargeTracking

-- Imports from IconMode
local UpdateIconModeVisuals = ST._UpdateIconModeVisuals
local UpdateIconModeGlows = ST._UpdateIconModeGlows

-- Imports from BarMode
local UpdateBarDisplay = ST._UpdateBarDisplay
local IsConfigButtonForceVisible = ST.IsConfigButtonForceVisible

-- IsItemEquippable from Helpers (exported on CooldownCompanion)
local IsItemEquippable = CooldownCompanion.IsItemEquippable
local TARGET_SWITCH_HOLD_SECS = 0.45

local function GetViewerNameFontString(viewerFrame)
    -- BuffBar viewer items render name text on Bar.Name. BuffIcon entries have no name text.
    local bar = viewerFrame and viewerFrame.Bar
    return bar and bar.Name or nil
end

-- Probe action-slot cooldown state for a spell ID pair (base + display override).
-- Returns:
--   shown      : true/false/nil (nil = no slots found or unknown from secret state)
--   durationObj: active LuaDurationObject when shown, else nil
--   cooldownInfo: matching ActionBarCooldownInfo when shown, else nil
local actionSlotSeenScratch = {}

local function ProbeActionSlotsForSpellID(spellID)
    if not spellID then return false, nil, nil, false, false end

    local slots = C_ActionBar.FindSpellActionButtons(spellID)
    if not slots then return false, nil, nil, false, false end

    local sawAnySlot = false
    local sawUnknown = false

    for _, slot in ipairs(slots) do
        if not actionSlotSeenScratch[slot] then
            actionSlotSeenScratch[slot] = true
            sawAnySlot = true

            local durationObj = C_ActionBar.GetActionCooldownDuration(slot)
            local cooldownInfo
            local shown = false

            if durationObj then
                if not durationObj:HasSecretValues() then
                    shown = not durationObj:IsZero()
                else
                    cooldownInfo = C_ActionBar.GetActionCooldown(slot)
                    if cooldownInfo then
                        scratchCooldown:Hide()
                        scratchCooldown:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
                        shown = scratchCooldown:IsShown()
                        scratchCooldown:Hide()
                    else
                        sawUnknown = true
                    end
                end
            else
                cooldownInfo = C_ActionBar.GetActionCooldown(slot)
                if cooldownInfo then
                    scratchCooldown:Hide()
                    scratchCooldown:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
                    shown = scratchCooldown:IsShown()
                    scratchCooldown:Hide()
                end
            end

            if shown then
                return true, durationObj, cooldownInfo, sawAnySlot, sawUnknown
            end
        end
    end

    return false, nil, nil, sawAnySlot, sawUnknown
end

local function ProbeActionSlotCooldownForSpell(baseSpellID, displaySpellID)
    if not baseSpellID then return nil, nil, nil end

    wipe(actionSlotSeenScratch)

    local sawAnySlot = false
    local sawUnknown = false

    local shown, durationObj, cooldownInfo, sawAny, sawUnk = ProbeActionSlotsForSpellID(baseSpellID)
    if sawAny then sawAnySlot = true end
    if sawUnk then sawUnknown = true end
    if shown then
        return true, durationObj, cooldownInfo
    end

    if displaySpellID and displaySpellID ~= baseSpellID then
        shown, durationObj, cooldownInfo, sawAny, sawUnk = ProbeActionSlotsForSpellID(displaySpellID)
        if sawAny then sawAnySlot = true end
        if sawUnk then sawUnknown = true end
        if shown then
            return true, durationObj, cooldownInfo
        end
    end

    if sawAnySlot then
        if sawUnknown then
            return nil, nil, nil
        end
        return false, nil, nil
    end

    return nil, nil, nil
end

function CooldownCompanion:UpdateButtonCooldown(button)
    local buttonData = button.buttonData
    local style = button.style
    local isGCDOnly = false
    local desatWasActive = button._desatCooldownActive == true
    local wasAuraActive = button._auraActive == true

    -- For transforming spells (e.g. Command Demon → pet ability), use the
    -- current override spell for cooldown queries. _displaySpellId is set
    -- by UpdateButtonIcon on SPELL_UPDATE_ICON and creation.
    local cooldownSpellId = button._displaySpellId or buttonData.id

    -- Deferred icon refresh for cdmChildSlot buttons (set by OnSpellUpdateIcon).
    -- One-tick delay ensures the CDM viewer's RefreshSpellTexture has already
    -- run, so child.Icon:GetTextureFileID() returns the current texture.
    if button._iconDirty then
        button._iconDirty = nil
        CooldownCompanion:UpdateButtonIcon(button)
        cooldownSpellId = button._displaySpellId or buttonData.id
    end

    -- Proc state: event-driven table lookup (base spell + current displayed override).
    -- Keeps visibility and glow checks aligned without polling overlay APIs.
    local procOverlayActive = false
    if buttonData.type == "spell" and not buttonData.isPassive then
        local displaySpellId = button._displaySpellId
        procOverlayActive = CooldownCompanion.procOverlaySpells[buttonData.id] and true or false
        if not procOverlayActive and displaySpellId and displaySpellId ~= buttonData.id then
            procOverlayActive = CooldownCompanion.procOverlaySpells[displaySpellId] and true or false
        end
    end

    -- Clear per-tick DurationObject; set below if cooldown/aura active.
    -- Used by bar fill, desaturation, visibility checks instead of
    -- GetCooldownTimes() which returns secret values after
    -- SetCooldownFromDurationObject() in 12.0.1.
    -- Save previous aura DurationObject for one-tick grace period on target switch.
    local prevAuraDurationObj = button._auraActive and button._durationObj or nil
    button._durationObj = nil

    -- Fetch cooldown data and update the cooldown widget.
    -- isOnGCD is NeverSecret (always readable even during restricted combat).
    local fetchOk, isOnGCD
    local spellCooldownInfo
    local actionSlotCooldownShown
    local actionSlotDurationObj
    local actionSlotCooldownInfo

    -- Aura tracking: check for active buff/debuff and override cooldown swipe
    local auraOverrideActive = false
    if buttonData.auraTracking and button._auraSpellID then
        local auraUnit = button._auraUnit or "player"

        local viewerFrame

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
                local f = CooldownCompanion.viewerAuraFrames[numId]
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
            viewerFrame = CooldownCompanion.viewerAuraFrames[button._auraSpellID]
                or CooldownCompanion.viewerAuraFrames[buttonData.id]
                or (button._displaySpellId and CooldownCompanion.viewerAuraFrames[button._displaySpellId])
        end
        if not auraOverrideActive and viewerFrame and (auraUnit == "player" or auraUnit == "target") then
            local viewerInstId = viewerFrame.auraInstanceID
            if viewerInstId then
                local unit = viewerFrame.auraDataUnit or auraUnit
                local durationObj = C_UnitAuras.GetAuraDuration(unit, viewerInstId)
                if durationObj then
                    button._durationObj = durationObj
                    button._viewerBar = nil  -- primary path: DurationObject available
                    button.cooldown:SetCooldownFromDurationObject(durationObj)
                    button._auraInstanceID = viewerInstId
                    button._auraUnit = unit
                    auraOverrideActive = true
                    fetchOk = true
                end
            elseif not button._targetSwitchAt then
                -- No auraInstanceID — fall back to reading the viewer's cooldown widget.
                -- Covers spells where the viewer tracks the buff duration internally
                -- (auraDataUnit set by GetAuraData) but doesn't expose auraInstanceID.
                local viewerCooldown = viewerFrame.Cooldown
                if viewerFrame.auraDataUnit and viewerCooldown and viewerCooldown:IsShown() then
                    local startMs, durMs = viewerCooldown:GetCooldownTimes()
                    if not issecretvalue(durMs) then
                        -- Plain values: safe to do ms->s arithmetic
                        if durMs > 0 and (startMs + durMs) > GetTime() * 1000 then
                            button.cooldown:SetCooldown(startMs / 1000, durMs / 1000)
                            auraOverrideActive = true
                            fetchOk = true
                            button._auraUnit = viewerFrame.auraDataUnit or auraUnit
                        end
                    else
                        -- Secret values: can't convert ms->s. Mark aura active;
                        -- grace period covers continuity from previous tick's display.
                        -- (HasSecretValues() on viewer widgets is unreliable when
                        -- Blizzard secure code set the values — check the returned
                        -- value directly with issecretvalue() instead.)
                        auraOverrideActive = true
                        fetchOk = true
                        button._auraUnit = viewerFrame.auraDataUnit or auraUnit
                    end
                    if button._auraInstanceID then
                        button._auraInstanceID = nil
                    end
                end
                -- Fallback 2: GetTotemInfo pass-through for totem/summoning
                -- spells (TrackedBar category). These appear in BuffBar
                -- viewer but have no auraInstanceID, auraDataUnit, or
                -- Cooldown widget. GetTotemInfo returns secret start/duration
                -- values that SetCooldown accepts directly — no arithmetic.
                -- Read preferredTotemUpdateSlot directly from the viewer
                -- frame (plain number set by CDM) rather than caching it,
                -- since the slot may not be populated at BuildViewerAuraMap time.
                if not auraOverrideActive then
                    local totemSlot = viewerFrame.preferredTotemUpdateSlot
                    if totemSlot and viewerFrame:IsVisible() then
                        local _, _, startTime, duration = GetTotemInfo(totemSlot)
                        -- All GetTotemInfo returns are secret. Probe
                        -- scratchCooldown to detect if the totem/guardian
                        -- is still alive (same pattern as spell CD probes).
                        scratchCooldown:Hide()
                        scratchCooldown:SetCooldown(startTime, duration)
                        local totemActive = scratchCooldown:IsShown()
                        scratchCooldown:Hide()
                        if totemActive then
                            button.cooldown:SetCooldown(startTime, duration)
                            auraOverrideActive = true
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
        -- Grace period: if aura data is momentarily unavailable (target switch,
        -- ~250-430ms) but we had an active aura DurationObject last tick, keep
        -- aura state alive.  Restoring _durationObj preserves bar fill, color,
        -- and time text.
        -- Target-switch path: _targetSwitchAt set → time-bounded hold (skip stale
        -- DurationObject expiry which references old target's aura instance).
        -- Player path: DurationObject fast-path + 3-tick counter.
        if not auraOverrideActive and button._auraActive
           and prevAuraDurationObj and not buttonData.isPassive then
            local expired = false
            if button._targetSwitchAt then
                -- Target-switch hold: time-bounded, skip stale DurationObject expiry
                expired = (GetTime() - button._targetSwitchAt) > TARGET_SWITCH_HOLD_SECS
            elseif not prevAuraDurationObj:HasSecretValues() then
                expired = prevAuraDurationObj:GetRemainingDuration() <= 0
            end
            if not expired then
                button._auraGraceTicks = (button._auraGraceTicks or 0) + 1
                if button._auraGraceTicks <= 3 or button._targetSwitchAt then
                    button._durationObj = prevAuraDurationObj
                    auraOverrideActive = true
                else
                    button._auraGraceTicks = nil
                end
            else
                button._auraGraceTicks = nil
                button._targetSwitchAt = nil
            end
        else
            button._auraGraceTicks = nil
            if button._targetSwitchAt then
                if auraOverrideActive and button._durationObj then
                    -- Primary path provided fresh DurationObject: hold complete
                    button._targetSwitchAt = nil
                elseif not button._auraActive then
                    -- Safety: _auraActive already false, clear stale hold
                    button._targetSwitchAt = nil
                end
            end
        end
        -- Target-switch hold catch-all: preserve _auraActive for buttons
        -- without a previous DurationObject (tracked via fallback path only)
        if not auraOverrideActive and button._targetSwitchAt and button._auraActive then
            if (GetTime() - button._targetSwitchAt) > TARGET_SWITCH_HOLD_SECS then
                button._targetSwitchAt = nil
            else
                button._durationObj = prevAuraDurationObj
                auraOverrideActive = true
            end
        end
        button._auraActive = auraOverrideActive
        if not auraOverrideActive then
            button._auraInstanceID = nil
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
            local shouldShow = auraOverrideActive and true or false
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
        if buttonData.auraTracking or buttonData.isPassive then
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
        local inPandemic = false
        if button._pandemicPreview then
            inPandemic = true
        -- Pandemic detection: style-level (Show Pandemic Glow) OR per-button visibility toggle.
        elseif auraOverrideActive and (style.showPandemicGlow ~= false or buttonData.hideAuraActiveExceptPandemic) and viewerFrame then
            local pi = viewerFrame.PandemicIcon
            if pi and pi:IsVisible() then
                inPandemic = true
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

    if buttonData.isPassive and not auraOverrideActive then
        button.cooldown:Hide()
    end

    if not auraOverrideActive then
        if buttonData.type == "spell" and not buttonData.isPassive then
            if not buttonData.hasCharges and buttonData._cooldownSecrecy ~= 0 then
                actionSlotCooldownShown, actionSlotDurationObj, actionSlotCooldownInfo =
                    ProbeActionSlotCooldownForSpell(buttonData.id, cooldownSpellId)
            end

            -- Get isOnGCD (NeverSecret) via GetSpellCooldown.
            -- SetCooldown accepts secret startTime/duration values.
            spellCooldownInfo = C_Spell.GetSpellCooldown(cooldownSpellId)
            if spellCooldownInfo then
                isOnGCD = spellCooldownInfo.isOnGCD
                if not fetchOk then
                    button.cooldown:SetCooldown(spellCooldownInfo.startTime, spellCooldownInfo.duration)
                end
                fetchOk = true
            elseif actionSlotCooldownInfo and not fetchOk then
                -- Fallback: some ContextuallySecret spells can return nil from
                -- C_Spell.GetSpellCooldown while action-slot cooldown data is
                -- still available (matches Blizzard action button behavior).
                button.cooldown:SetCooldown(actionSlotCooldownInfo.startTime, actionSlotCooldownInfo.duration)
                fetchOk = true
            end
            -- GCD-only detection: compare spell's cooldown against GCD reference (61304).
            -- More reliable than isOnGCD at GCD boundaries (Blizzard CooldownViewer pattern).
            if spellCooldownInfo then
                local gcdInfo = CooldownCompanion._gcdInfo
                if gcdInfo then
                    if buttonData._cooldownSecrecy == 0 then
                        -- NeverSecret: direct comparison is safe
                        isGCDOnly = (spellCooldownInfo.startTime == gcdInfo.startTime
                            and spellCooldownInfo.duration == gcdInfo.duration)
                    else
                        -- Secret cooldown: both signals must agree to avoid false positives.
                        -- isOnGCD (NeverSecret) = Blizzard's per-spell GCD flag.
                        -- _gcdActive = widget-level GCD signal (covers boundary where
                        -- isOnGCD lingers true after GCD ends).
                        isGCDOnly = isOnGCD and CooldownCompanion._gcdActive
                    end
                end
            end
            -- DurationObject path: HasSecretValues gates IsZero comparison.
            -- Non-secret: use IsZero to filter zero-duration (spell ready).
            -- Secret: fall back to isOnGCD (NeverSecret) as activity signal.
            local spellCooldownDuration = C_Spell.GetSpellCooldownDuration(cooldownSpellId)
            if spellCooldownDuration then
                local useIt = false
                local durationForDisplay = spellCooldownDuration
                if not spellCooldownDuration:HasSecretValues() then
                    if not spellCooldownDuration:IsZero() then useIt = true end
                else
                    -- Secret values: can't call IsZero() to check if spell is ready.
                    -- GetSpellCooldownDuration returns non-nil even for ready spells
                    -- during combat.  Use scratchCooldown as a C++ level signal:
                    -- SetCooldown() auto-shows it only when duration > 0 (handles
                    -- secrets internally).  button.cooldown:IsShown() is unreliable
                    -- — force-shown by UpdateIconModeVisuals, not auto-hidden by
                    -- SetCooldown(0,0).
                    if spellCooldownInfo then
                        scratchCooldown:Hide()
                        scratchCooldown:SetCooldown(spellCooldownInfo.startTime, spellCooldownInfo.duration)
                        useIt = scratchCooldown:IsShown()
                        scratchCooldown:Hide()
                    elseif actionSlotCooldownShown == true then
                        useIt = true
                        if actionSlotDurationObj then
                            durationForDisplay = actionSlotDurationObj
                        end
                    end
                end
                if useIt then
                    button._durationObj = durationForDisplay
                    if not durationForDisplay:HasSecretValues() then
                        button.cooldown:SetCooldownFromDurationObject(durationForDisplay)
                    elseif not spellCooldownInfo and actionSlotCooldownInfo then
                        button.cooldown:SetCooldown(actionSlotCooldownInfo.startTime, actionSlotCooldownInfo.duration)
                    end
                    fetchOk = true
                end
            elseif actionSlotCooldownShown == true and actionSlotDurationObj then
                -- Fallback when spell duration API is unavailable but action-slot
                -- duration object is present.
                button._durationObj = actionSlotDurationObj
                if not actionSlotDurationObj:HasSecretValues() then
                    button.cooldown:SetCooldownFromDurationObject(actionSlotDurationObj)
                elseif actionSlotCooldownInfo then
                    button.cooldown:SetCooldown(actionSlotCooldownInfo.startTime, actionSlotCooldownInfo.duration)
                end
                fetchOk = true
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
                local cdStart, cdDuration = C_Item.GetItemCooldown(buttonData.id)
                button.cooldown:SetCooldown(cdStart, cdDuration)
                button._itemCdStart = cdStart
                button._itemCdDuration = cdDuration
            end
            fetchOk = true
        end
    end

    -- Update spell charge data before zero-charge state classification.
    -- When readable, charge count is authoritative for "zero charges" (unusable),
    -- even if the spell also has a per-cast cooldown lockout.
    local charges
    if buttonData.hasCharges and buttonData.type == "spell" then
        charges = UpdateChargeTracking(button, buttonData, cooldownSpellId)
    elseif not buttonData.hasCharges and button._chargeText ~= nil then
        -- hasCharges cleared (e.g. brez pool deactivated): wipe stale charge text
        button._chargeText = nil
        button._currentReadableCharges = nil
        button.count:SetText("")
    end

    -- Store raw GCD state for downstream display logic.
    if button._postCastGCDHold then
        local holdExpired = button._postCastGCDHoldUntil and GetTime() > button._postCastGCDHoldUntil
        if holdExpired or not CooldownCompanion._gcdActive then
            button._postCastGCDHold = nil
            button._postCastGCDHoldUntil = nil
        end
    end

    -- ContextuallySecret spells can transiently report isOnGCD=true while a real
    -- short cooldown is already active. If we were already showing cooldown and
    -- still have active cooldown data, keep treating it as non-GCD-only.
    -- Scope this to the cast-start GCD for this spell only.
    if buttonData.type == "spell"
       and not buttonData.hasCharges
       and not auraOverrideActive
       and buttonData._cooldownSecrecy ~= 0
       and button._postCastGCDHold
       and isOnGCD
       and isGCDOnly
       and desatWasActive
       and not wasAuraActive
       and button._durationObj
       and actionSlotCooldownShown == true then
        isGCDOnly = false
    end

    button._isOnGCD = isOnGCD or false

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
            local startTime, duration
            local gcdInfo = CooldownCompanion._gcdInfo
            if gcdInfo and gcdInfo.startTime and gcdInfo.duration then
                startTime, duration = gcdInfo.startTime, gcdInfo.duration
            elseif spellCooldownInfo and spellCooldownInfo.startTime and spellCooldownInfo.duration
            then
                startTime, duration = spellCooldownInfo.startTime, spellCooldownInfo.duration
            end
            if startTime and duration then
                local iconGCDCooldown = button.iconGCDCooldown
                iconGCDCooldown:SetDrawEdge(style.showCooldownSwipeEdge ~= false)
                iconGCDCooldown:SetReverse(style.cooldownSwipeReverse or false)
                -- Secret-safe pass-through: let CooldownFrame handle duration validity.
                iconGCDCooldown:Hide()
                iconGCDCooldown:SetCooldown(startTime, duration)
            else
                button.iconGCDCooldown:Hide()
            end
        else
            button.iconGCDCooldown:Hide()
        end
    end

    -- Charge count tracking: detect whether the main cooldown (0 charges)
    -- is active.  Filter GCD so only real cooldown reads as true.
    -- Skip during aura override: button.cooldown shows the aura, not the main CD.
    if buttonData.hasCharges and not auraOverrideActive then
        if buttonData.type == "item" then
            -- Items: 0 charges = on cooldown. No GCD to filter.
            local chargeCount = C_Item.GetItemCount(buttonData.id, false, true)
            button._mainCDShown = (chargeCount == 0)
        elseif buttonData.type == "spell" and button._currentReadableCharges ~= nil then
            -- Readable charge count is the source of truth for zero-charge state.
            -- Prevents short lockout cooldowns (e.g., dragonriding flyout abilities)
            -- from being misclassified as "zero charges".
            button._mainCDShown = (button._currentReadableCharges == 0)
        elseif buttonData.type == "spell" then
            -- Restricted mode: charges unreadable (secret values).
            -- Action bar cooldown is charge-aware: Blizzard only shows a cooldown
            -- sweep at zero charges, not during per-cast lockouts (e.g. Hover).
            local slotShown = ProbeActionSlotCooldownForSpell(buttonData.id, cooldownSpellId)
            if slotShown ~= nil then
                button._mainCDShown = slotShown and not isGCDOnly
            elseif button._isBar then
                button._mainCDShown = button.cooldown:IsShown() and not isGCDOnly
            else
                -- Icon mode: no action bar slot, fall back to scratchCooldown.
                local mainCDDuration = C_Spell.GetSpellCooldownDuration(cooldownSpellId)
                if mainCDDuration and not mainCDDuration:HasSecretValues() then
                    scratchCooldown:Hide()
                    scratchCooldown:SetCooldownFromDurationObject(mainCDDuration)
                    button._mainCDShown = scratchCooldown:IsShown() and not isGCDOnly
                    scratchCooldown:Hide()
                elseif mainCDDuration then
                    local ci = C_Spell.GetSpellCooldown(cooldownSpellId)
                    if ci then
                        scratchCooldown:Hide()
                        scratchCooldown:SetCooldown(ci.startTime, ci.duration)
                        button._mainCDShown = scratchCooldown:IsShown() and not isGCDOnly
                        scratchCooldown:Hide()
                    else
                        button._mainCDShown = false
                    end
                else
                    button._mainCDShown = false
                end
            end
        end
    end

    -- Canonical desaturation signal:
    -- For non-charge spells, use action-slot cooldown state when spell cooldown
    -- info is unavailable (ContextuallySecret fallback). Otherwise use addon state.
    if buttonData.type == "item" then
        button._desatCooldownActive = (button._itemCdDuration and button._itemCdDuration > 0) or false
    elseif buttonData.hasCharges then
        button._desatCooldownActive = (button._mainCDShown == true)
    else
        if actionSlotCooldownShown ~= nil and spellCooldownInfo == nil then
            button._desatCooldownActive = actionSlotCooldownShown
        else
            button._desatCooldownActive = (button._durationObj ~= nil) and (not isGCDOnly)
        end
    end

    if not button._isBar then
        UpdateIconModeVisuals(button, buttonData, style, fetchOk, isOnGCD, isGCDOnly)
    end

    if buttonData.hasCharges then
      if buttonData.type == "spell" then
        -- Bar mode: charge bars are driven by the recharge DurationObject, not
        -- the main spell CD or GCD. Save and clear the main CD so recharge
        -- timing fully controls bar fill for charge spells.
        if button._isBar and not auraOverrideActive and button._chargeDurationObj then
            button._durationObj = nil
        end

        -- Always detect charge recharging state (needed for text/bar color even during aura override).
        -- Charge DurationObjects may report non-zero even at full charges (stale data);
        -- scratchCooldown auto-show is the ground truth.
        if button._chargeDurationObj then
            if not button._chargeDurationObj:HasSecretValues() then
                scratchCooldown:Hide()
                scratchCooldown:SetCooldownFromDurationObject(button._chargeDurationObj)
                button._chargeRecharging = scratchCooldown:IsShown()
                scratchCooldown:Hide()
            else
                -- Secret values (combat): SetCooldownFromDurationObject fails.
                -- Probe scratchCooldown with charge timing data instead
                -- (SetCooldown accepts secrets; IsShown returns plain bool).
                -- Uses charge-specific timing, not the main cooldown (which
                -- includes GCD for on-GCD charge spells like Fire Breath).
                if charges then
                    scratchCooldown:Hide()
                    scratchCooldown:SetCooldown(charges.cooldownStartTime, charges.cooldownDuration)
                    button._chargeRecharging = scratchCooldown:IsShown()
                    scratchCooldown:Hide()
                else
                    button._chargeRecharging = false
                end
            end
        else
            button._chargeRecharging = false
        end

        if not auraOverrideActive and button._chargeDurationObj then
            if not button._isBar then
                -- Icon mode: always set _durationObj, show recharge radial
                button._durationObj = button._chargeDurationObj
                if not button._chargeDurationObj:HasSecretValues() then
                    button.cooldown:SetCooldownFromDurationObject(button._chargeDurationObj)
                elseif charges then
                    -- Secret: SetCooldownFromDurationObject fails; use SetCooldown
                    button.cooldown:SetCooldown(charges.cooldownStartTime, charges.cooldownDuration)
                end
            elseif button._chargeRecharging then
                -- Bar mode: only set _durationObj if actually recharging
                button._durationObj = button._chargeDurationObj
            end
        elseif not button._isBar and not auraOverrideActive and charges then
            -- Icon mode fallback
            button.cooldown:SetCooldown(charges.cooldownStartTime, charges.cooldownDuration)
        end

      elseif buttonData.type == "item" then
        UpdateItemChargeTracking(button, buttonData)

        -- Detect recharging via stored item cooldown values
        button._chargeRecharging = (button._itemCdDuration and button._itemCdDuration > 0) or false
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
    if button.auraStackCount and (buttonData.auraTracking or buttonData.isPassive)
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
        if cur ~= nil and buttonData.maxCharges then
            if cur == 0 then
                cc = style.chargeFontColorZero or {1, 1, 1, 1}
            elseif cur < buttonData.maxCharges then
                cc = style.chargeFontColorMissing or {1, 1, 1, 1}
            else
                cc = style.chargeFontColor or {1, 1, 1, 1}
            end
        else
            -- Restricted mode: charges unreadable via C_Spell.
            -- Track charge consumption via UNIT_SPELLCAST_SUCCEEDED (_chargesSpent)
            -- and combine with _mainCDShown (Blizzard shows main sweep only at 0
            -- charges) for immediate zero-charge detection.

            -- Reset happens in OnSpellCast (when casting from full), not here,
            -- to avoid race with _chargeRecharging lag.
            if not button._chargeRecharging then
                cc = style.chargeFontColor or {1, 1, 1, 1}             -- FULL (max charges)
            elseif (button._chargesSpent or 0) >= (buttonData.maxCharges or 2)
                   and button._mainCDShown then
                cc = style.chargeFontColorZero or {1, 1, 1, 1}         -- ZERO (all spent)
            else
                cc = style.chargeFontColorMissing or {1, 1, 1, 1}      -- MISSING (recharging)
            end
        end
        button.count:SetTextColor(cc[1], cc[2], cc[3], cc[4])
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
            if buttonData.hasCharges then
                if button._currentReadableCharges ~= nil then
                    currentCharges = button._currentReadableCharges
                elseif charges and charges.currentCharges ~= nil
                   and not issecretvalue(charges.currentCharges) then
                    currentCharges = charges.currentCharges
                end

                if charges and charges.maxCharges ~= nil and not issecretvalue(charges.maxCharges) then
                    maxCharges = charges.maxCharges
                elseif buttonData.maxCharges and buttonData.maxCharges > 0 then
                    maxCharges = buttonData.maxCharges
                end

                chargeRecharging = button._chargeRecharging and true or false
                if charges and charges.cooldownStartTime ~= nil
                   and not issecretvalue(charges.cooldownStartTime) then
                    chargeCooldownStartTime = charges.cooldownStartTime
                end
            end

            local cooldownActive
            if buttonData.hasCharges then
                -- Charge spells: cooldown-active means zero available charges.
                if currentCharges ~= nil then
                    cooldownActive = (currentCharges == 0)
                else
                    cooldownActive = button._mainCDShown == true
                end
            elseif auraOverrideActive then
                -- Aura visuals can replace button.cooldown, so probe spell cooldown
                -- directly for sound-event state.
                local probeInfo = C_Spell.GetSpellCooldown(cooldownSpellId)
                if probeInfo then
                    local probeIsOnGCD = probeInfo.isOnGCD and true or false
                    local probeIsGCDOnly = false
                    local gcdInfo = CooldownCompanion._gcdInfo
                    if gcdInfo then
                        if buttonData._cooldownSecrecy == 0 then
                            probeIsGCDOnly = (probeInfo.startTime == gcdInfo.startTime
                                and probeInfo.duration == gcdInfo.duration)
                        else
                            probeIsGCDOnly = probeIsOnGCD and CooldownCompanion._gcdActive
                        end
                    end

                    scratchCooldown:Hide()
                    scratchCooldown:SetCooldown(probeInfo.startTime, probeInfo.duration)
                    cooldownActive = scratchCooldown:IsShown() and not probeIsGCDOnly
                    scratchCooldown:Hide()
                else
                    cooldownActive = false
                end
            else
                if spellCooldownInfo then
                    scratchCooldown:Hide()
                    scratchCooldown:SetCooldown(spellCooldownInfo.startTime, spellCooldownInfo.duration)
                    cooldownActive = scratchCooldown:IsShown() and not isGCDOnly
                    scratchCooldown:Hide()
                else
                    cooldownActive = false
                end
            end

            self:UpdateButtonSoundAlerts(
                button,
                cooldownSpellId,
                isOnGCD or false,
                cooldownActive and true or false,
                auraOverrideActive and true or false,
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
            return  -- Skip visual updates for hidden buttons
        else
            local targetAlpha = button._visibilityAlphaOverride or 1
            if button._lastVisAlpha ~= targetAlpha then
                button:SetAlpha(targetAlpha)
                button._lastVisAlpha = targetAlpha
            end
        end
    end

    -- Bar mode: update bar display after charges are resolved
    if button._isBar then
        UpdateBarDisplay(button)
    end

    if not button._isBar then
        UpdateIconModeGlows(button, buttonData, style, procOverlayActive)
    end
end
