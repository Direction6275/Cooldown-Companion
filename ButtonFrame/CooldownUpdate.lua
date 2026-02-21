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

-- IsItemEquippable from Helpers (exported on CooldownCompanion)
local IsItemEquippable = CooldownCompanion.IsItemEquippable

function CooldownCompanion:UpdateButtonCooldown(button)
    local buttonData = button.buttonData
    local style = button.style
    local isGCDOnly = false

    -- For transforming spells (e.g. Command Demon → pet ability), use the
    -- current override spell for cooldown queries. _displaySpellId is set
    -- by UpdateButtonIcon on SPELL_UPDATE_ICON and creation.
    local cooldownSpellId = button._displaySpellId or buttonData.id

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

    -- Aura tracking: check for active buff/debuff and override cooldown swipe
    local auraOverrideActive = false
    if buttonData.auraTracking and button._auraSpellID then
        local auraUnit = button._auraUnit or "player"

        -- Viewer-based aura tracking: Blizzard's cooldown viewer frames run
        -- untainted code that matches spell IDs to auras during combat and
        -- stores auraInstanceID + auraDataUnit as plain readable properties.
        -- Requires the Blizzard Cooldown Manager to be visible with this spell.
        local viewerFrame
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
                    button.cooldown:SetCooldownFromDurationObject(durationObj)
                    button._auraInstanceID = viewerInstId
                    auraOverrideActive = true
                    fetchOk = true
                end
            else
                -- No auraInstanceID — fall back to reading the viewer's cooldown widget.
                -- Covers spells where the viewer tracks the buff duration internally
                -- (auraDataUnit set by GetAuraData) but doesn't expose auraInstanceID.
                local viewerCooldown = viewerFrame.Cooldown
                if viewerFrame.auraDataUnit and viewerCooldown and viewerCooldown:IsShown() then
                    if not viewerCooldown:HasSecretValues() then
                        -- Plain values: safe to do ms->s arithmetic
                        local startMs, durMs = viewerCooldown:GetCooldownTimes()
                        if durMs > 0 and (startMs + durMs) > GetTime() * 1000 then
                            button.cooldown:SetCooldown(startMs / 1000, durMs / 1000)
                            auraOverrideActive = true
                            fetchOk = true
                        end
                    else
                        -- Secret values: can't convert ms->s. Mark aura active;
                        -- grace period covers continuity from previous tick's display.
                        auraOverrideActive = true
                        fetchOk = true
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
                            if button._auraInstanceID then
                                button._auraInstanceID = nil
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
        -- Fast path: if we can read the old DurationObject (non-secret), check
        -- expiry directly — clears instantly when the aura has genuinely ended.
        -- Slow path (combat, HasSecretValues=true): bounded tick counter.
        if not auraOverrideActive and button._auraActive
           and prevAuraDurationObj and not buttonData.isPassive then
            local expired = false
            if not prevAuraDurationObj:HasSecretValues() then
                expired = prevAuraDurationObj:GetRemainingDuration() <= 0
            end
            if not expired then
                button._auraGraceTicks = (button._auraGraceTicks or 0) + 1
                if button._auraGraceTicks <= 3 then
                    button._durationObj = prevAuraDurationObj
                    auraOverrideActive = true
                else
                    button._auraGraceTicks = nil
                end
            else
                button._auraGraceTicks = nil
            end
        else
            -- Fresh aura data (or no aura at all): reset grace counter
            button._auraGraceTicks = nil
        end
        button._auraActive = auraOverrideActive

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
        elseif auraOverrideActive and buttonData.pandemicGlow and viewerFrame then
            local pi = viewerFrame.PandemicIcon
            if pi and pi:IsVisible() then
                inPandemic = true
            end
        end
        button._inPandemic = inPandemic

        -- Dynamic icon for multi-CDM-child buttons: pass through the viewer
        -- child's rendered icon texture each tick. SetTexture accepts secret
        -- values (GetTextureFileID returns secret in combat). Only needed for
        -- cdmChildSlot buttons where multiple children share the same base
        -- spellID — single-child buttons get correct icons from UpdateButtonIcon.
        if buttonData.cdmChildSlot then
            if auraOverrideActive and viewerFrame then
                local iconTexture = viewerFrame.Icon
                -- BuffBar: viewerFrame.Icon is a Frame; the Texture is .Icon.Icon
                if iconTexture and not iconTexture.GetTextureFileID then
                    iconTexture = iconTexture.Icon
                end
                if iconTexture then
                    button.icon:SetTexture(iconTexture:GetTextureFileID())
                end
                button._hadViewerIcon = true
            elseif not auraOverrideActive and button._hadViewerIcon then
                button._hadViewerIcon = nil
                local baseIcon = C_Spell.GetSpellTexture(buttonData.id)
                if baseIcon then
                    button.icon:SetTexture(baseIcon)
                    button._displaySpellId = buttonData.id
                    if button.nameText then
                        local baseName = C_Spell.GetSpellName(buttonData.id)
                        if baseName then button.nameText:SetText(baseName) end
                    end
                end
            end
        end
    end

    if buttonData.isPassive and not auraOverrideActive then
        button.cooldown:Hide()
    end

    if not auraOverrideActive then
        if buttonData.type == "spell" and not buttonData.isPassive then
            -- Get isOnGCD (NeverSecret) via GetSpellCooldown.
            -- SetCooldown accepts secret startTime/duration values.
            local cooldownInfo = C_Spell.GetSpellCooldown(cooldownSpellId)
            if cooldownInfo then
                isOnGCD = cooldownInfo.isOnGCD
                if not fetchOk then
                    button.cooldown:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
                end
                fetchOk = true
            end
            -- GCD-only detection: compare spell's cooldown against GCD reference (61304).
            -- More reliable than isOnGCD at GCD boundaries (Blizzard CooldownViewer pattern).
            if cooldownInfo then
                local gcdInfo = CooldownCompanion._gcdInfo
                if gcdInfo then
                    if buttonData._cooldownSecrecy == 0 then
                        -- NeverSecret: direct comparison is safe
                        isGCDOnly = (cooldownInfo.startTime == gcdInfo.startTime
                            and cooldownInfo.duration == gcdInfo.duration)
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
                    scratchCooldown:Hide()
                    scratchCooldown:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
                    useIt = scratchCooldown:IsShown()
                    scratchCooldown:Hide()
                end
                if useIt then
                    button._durationObj = spellCooldownDuration
                    if not spellCooldownDuration:HasSecretValues() then
                        button.cooldown:SetCooldownFromDurationObject(spellCooldownDuration)
                    end
                    fetchOk = true
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
                local cdStart, cdDuration = C_Item.GetItemCooldown(buttonData.id)
                button.cooldown:SetCooldown(cdStart, cdDuration)
                button._itemCdStart = cdStart
                button._itemCdDuration = cdDuration
            end
            fetchOk = true
        end
    end

    -- Store raw GCD state for bar desaturation guard
    local gcdJustEnded = (button._wasOnGCD == true) and not isOnGCD
    button._wasOnGCD = isOnGCD or false
    button._isOnGCD = isOnGCD or false
    button._gcdJustEnded = gcdJustEnded

    -- Bar mode: GCD suppression flag (checked by UpdateBarFill OnUpdate).
    -- Skip for charge spells: their _durationObj is the recharge cycle, never the GCD.
    if button._isBar then
        button._barGCDSuppressed = fetchOk and not style.showGCDSwipe and isOnGCD
            and not buttonData.hasCharges and not buttonData.isPassive
    end

    -- Charge count tracking: detect whether the main cooldown (0 charges)
    -- is active.  Filter GCD so only real cooldown reads as true.
    -- Skip during aura override: button.cooldown shows the aura, not the main CD.
    if buttonData.hasCharges and not auraOverrideActive then
        if buttonData.type == "item" then
            -- Items: 0 charges = on cooldown. No GCD to filter.
            local chargeCount = C_Item.GetItemCount(buttonData.id, false, true)
            button._mainCDShown = (chargeCount == 0)
        elseif button._isBar then
            -- Bar mode: button.cooldown is not reused for recharge animation.
            -- For secret spells, require both GCD signals to agree before filtering,
            -- preventing false negatives at GCD boundaries.
            if buttonData._cooldownSecrecy == 0 then
                button._mainCDShown = button.cooldown:IsShown() and not isOnGCD
            else
                button._mainCDShown = button.cooldown:IsShown()
                    and not (isOnGCD and CooldownCompanion._gcdActive)
            end
        else
            -- Icon mode: prefer scratchCooldown when DurationObject values are plain.
            -- button.cooldown:IsShown() is unreliable because UpdateIconModeVisuals
            -- force-shows it and SetCooldown(0,0) does not auto-hide.
            local mainCDDuration = C_Spell.GetSpellCooldownDuration(cooldownSpellId)
            if mainCDDuration and not mainCDDuration:HasSecretValues() then
                scratchCooldown:Hide()
                scratchCooldown:SetCooldownFromDurationObject(mainCDDuration)
                button._mainCDShown = scratchCooldown:IsShown() and not isOnGCD
                scratchCooldown:Hide()
            elseif mainCDDuration then
                -- Secret values (combat): SetCooldownFromDurationObject fails with
                -- secrets, but SetCooldown accepts them.  Use scratchCooldown
                -- (button.cooldown:IsShown() is unreliable — force-shown by
                -- UpdateIconModeVisuals, not auto-hidden by SetCooldown(0,0)).
                local ci = C_Spell.GetSpellCooldown(cooldownSpellId)
                if ci then
                    scratchCooldown:Hide()
                    scratchCooldown:SetCooldown(ci.startTime, ci.duration)
                    button._mainCDShown = scratchCooldown:IsShown() and not isOnGCD
                    scratchCooldown:Hide()
                else
                    button._mainCDShown = false
                end
            else
                button._mainCDShown = false
            end
        end
    end

    if not button._isBar then
        UpdateIconModeVisuals(button, buttonData, style, fetchOk, isOnGCD, gcdJustEnded)
    end

    local charges
    if buttonData.hasCharges then
      if buttonData.type == "spell" then
        charges = UpdateChargeTracking(button, buttonData)

        -- Bar mode: charge bars are driven by the recharge DurationObject, not
        -- the main spell CD. Save and clear the main CD, let the charge block
        -- set _durationObj from the recharge, then restore the main CD for GCD
        -- display only when showGCDSwipe is on and no recharge is active.
        local mainDurationObj
        if button._isBar and not auraOverrideActive and button._chargeDurationObj then
            mainDurationObj = button._durationObj
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

        -- Bar mode: if no recharge active, restore main CD for GCD display
        if button._isBar and not button._durationObj
           and mainDurationObj and isOnGCD and style.showGCDSwipe then
            button._durationObj = mainDurationObj
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

    -- Charge text color: three-state (zero / partial / max) via flags, combat-safe.
    if style.chargeFontColor or style.chargeFontColorMissing or style.chargeFontColorZero then
        local cc
        if button._mainCDShown then
            cc = style.chargeFontColorZero or {1, 1, 1, 1}
        elseif button._chargeRecharging then
            cc = style.chargeFontColorMissing or {1, 1, 1, 1}
        else
            cc = style.chargeFontColor or {1, 1, 1, 1}
        end
        button.count:SetTextColor(cc[1], cc[2], cc[3], cc[4])
    end

    -- Per-button visibility evaluation (after charge tracking)
    EvaluateButtonVisibility(button, buttonData, isGCDOnly, auraOverrideActive)

    -- Track if hidden state changed (for compact layout dirty flag)
    if button._visibilityHidden ~= button._prevVisibilityHidden then
        button._prevVisibilityHidden = button._visibilityHidden
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
        UpdateBarDisplay(button, fetchOk)
    end

    if not button._isBar then
        UpdateIconModeGlows(button, buttonData, style)
    end
end
