--[[
    CooldownCompanion - ButtonFrame/Tracking
    Charge tracking (spell + item), icon tinting, and desaturation
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic
local COOLDOWN_STATE_GCD = CooldownLogic.STATE_GCD
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO

-- Localize frequently-used globals
local issecretvalue = issecretvalue
local InCombatLockdown = InCombatLockdown
local UnitCanAttack = UnitCanAttack
local IsItemInRange = C_Item.IsItemInRange
local IsUsableItem = C_Item.IsUsableItem

-- Update charge count state for a spell with hasCharges enabled.
-- chargeSpellID should be the effective runtime spell ID (override-aware).
-- Returns the raw charges API table (may be nil) for use by callers.
local function UpdateChargeTracking(button, buttonData, chargeSpellID)
    local spellID = chargeSpellID or buttonData.id
    local charges = C_Spell.GetSpellCharges(spellID)

    -- Read current charges only from the authoritative charge API field.
    -- Display-count APIs are UI-oriented and can transiently read 0 during
    -- lockout windows even when charges remain.
    local cur
    if charges and charges.currentCharges ~= nil and not issecretvalue(charges.currentCharges) then
        cur = charges.currentCharges
    end
    button._currentReadableCharges = cur
    button._chargeCountReadable = (cur ~= nil)

    -- Persist maxCharges from the charge API whenever available.
    local persistedMax = buttonData.maxCharges or 0
    if charges then
        if charges.maxCharges ~= persistedMax then
            buttonData.maxCharges = charges.maxCharges
            persistedMax = charges.maxCharges
        end
    end

    -- Demote if readable maxCharges confirms this is no longer multi-charge.
    -- Conditional talents (e.g. Strafing Run) can temporarily inflate maxCharges
    -- to 2; when the buff fades and the API returns 1, immediately clear charge
    -- classification so the normal cooldown/desaturation path applies.
    -- Safe for real charge spells: they always return maxCharges >= 2.
    if charges and charges.maxCharges <= 1 then
        buttonData.hasCharges = nil
        buttonData.maxCharges = charges.maxCharges
        button.count:SetText("")
        button._chargeText = nil
        button._chargeDurationObj = nil
        button._chargeRecharging = false
        button._chargeState = nil
        return nil
    end

    local mx = buttonData.maxCharges

    -- Recharge DurationObject for multi-charge spells.
    -- GetSpellChargeDuration returns nil for maxCharges=1 (Blizzard doesn't treat
    -- single-charge as charge spells for duration purposes).
    if mx and mx > 1 then
        button._chargeDurationObj = C_Spell.GetSpellChargeDuration(spellID)
    end

    -- Display charge text via secret-safe widget methods
    local showChargeText = button.style and button.style.showChargeText
    if not showChargeText then
        button.count:SetText("")
    else
        if cur then
            -- Plain number: use directly (can optimize with comparison)
            if button._chargeText ~= cur then
                button._chargeText = cur
                button.count:SetText(cur)
            end
        else
            -- Unreadable in restricted mode: use display API for text only.
            button._chargeText = nil
            button.count:SetText(C_Spell.GetSpellDisplayCount(spellID))
        end
    end

    return charges
end

-- Display/use-count tracking for spells that share the charge-style behavior
-- without using the real charge API (e.g. brez pools).
local function UpdateDisplayCountTracking(button, buttonData, spellID)
    local querySpellID = spellID or buttonData.id
    local rawDisplayCount = C_Spell.GetSpellDisplayCount(querySpellID)
    local secretDisplayCount = issecretvalue(rawDisplayCount)
    local cur
    if not secretDisplayCount then
        cur = tonumber(rawDisplayCount)
        if cur == nil and rawDisplayCount == "" and buttonData._displayCountFamily == true then
            cur = 0
        end
    end

    button._currentReadableCharges = cur
    button._chargeCountReadable = (cur ~= nil)
    button._displayCountZeroUsabilityFallback = nil

    if cur and cur > (buttonData.maxCharges or 0) then
        buttonData.maxCharges = cur
    end

    local maxCharges = buttonData.maxCharges
    if cur ~= nil then
        button._chargeRecharging = (maxCharges ~= nil and cur < maxCharges) or false
    elseif secretDisplayCount then
        -- Do not infer zero/non-zero state from spell usability when the display
        -- count itself is secret. Usability can fail for unrelated reasons
        -- (costs, reactives, etc.), so treat the zero-state as unknown.
        button._chargeRecharging = false
    else
        button._chargeRecharging = false
    end
    button._chargeDurationObj = nil
    button._chargesSpent = nil

    local showChargeText = button.style and button.style.showChargeText
    if not showChargeText then
        button.count:SetText("")
    else
        button._chargeText = nil
        button.count:SetText(rawDisplayCount or "")
    end
end

-- Item charge tracking (e.g. Hellstone): simpler than spells, no secret values.
-- Reads charge count via C_Item.GetItemCount with includeUses, updates text display.
local function UpdateItemChargeTracking(button, buttonData)
    local chargeCount = C_Item.GetItemCount(buttonData.id, false, true)

    -- Update persisted maxCharges upward when observable
    if chargeCount > (buttonData.maxCharges or 0) then
        buttonData.maxCharges = chargeCount
    end

    -- Items are always readable — feed the same field spells use so the
    -- three-state charge color block can use direct comparison.
    button._currentReadableCharges = chargeCount
    button._chargeCountReadable = true

    -- Display charge text with change detection
    local showChargeText = button.style and button.style.showChargeText
    if not showChargeText then
        button.count:SetText("")
    elseif button._chargeText ~= chargeCount then
        button._chargeText = chargeCount
        button.count:SetText(chargeCount)
    end
end

local function ShouldApplyUnusableTint(button, isUsable, resourceBlocked)
    if isUsable then
        return false
    end

    -- A GCD-only lockout is not a true unusable state for icon tinting. This
    -- keeps icons visually ready when their real cooldown is over, while still
    -- allowing resource failures to tint during the GCD.
    if button._cooldownState == COOLDOWN_STATE_GCD and resourceBlocked ~= true then
        return false
    end

    return true
end

-- Icon tinting: out-of-range red > unusable dimming > aura tint > cooldown tint > base tint.
-- Shared by icon-mode and bar-mode display paths.
local function UpdateIconTint(button, buttonData, style)
    if buttonData.isPassive then
        local c
        if style.iconAuraTintEnabled and buttonData.auraTracking and button._auraActive then
            c = style.iconAuraTintColor
        end
        c = c or style.iconTintColor
        local r, g, b, a = c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
        if button._vertexR ~= r or button._vertexG ~= g or button._vertexB ~= b or button._vertexA ~= a then
            button._vertexR, button._vertexG, button._vertexB, button._vertexA = r, g, b, a
            button.icon:SetVertexColor(r, g, b, a)
        end
        return
    end
    local bc = style.iconTintColor
    local r, g, b, a = 1, 1, 1, bc and bc[4] or 1
    local stateOverride = false
    if style.showOutOfRange then
        if buttonData.type == "spell" then
            if button._spellOutOfRange then
                r, g, b = 1, 0.2, 0.2
                stateOverride = true
            end
        elseif buttonData.type == "item" then
            -- C_Item.IsItemInRange is protected in combat for non-enemy targets (10.2.0);
            -- only call when out of combat or target is attackable.
            if not InCombatLockdown() or UnitCanAttack("player", "target") then
                local inRange = IsItemInRange(buttonData.id, "target")
                -- inRange is nil when no target or item has no range; only tint on explicit false
                if inRange == false then
                    r, g, b = 1, 0.2, 0.2
                    stateOverride = true
                end
            end
        end
    end
    if not stateOverride and style.showUnusable then
        local uc = style.iconUnusableTintColor
        if buttonData.type == "spell" then
            local spellID = button._displaySpellId or buttonData.id
            local isUsable, insufficientPower = C_Spell.IsSpellUsable(spellID)
            if ShouldApplyUnusableTint(button, isUsable, insufficientPower) then
                r, g, b = uc and uc[1] or 0.4, uc and uc[2] or 0.4, uc and uc[3] or 0.4
                a = uc and uc[4] or a
                stateOverride = true
            end
        elseif buttonData.type == "item" then
            local usable, noMana = IsUsableItem(buttonData.id)
            if ShouldApplyUnusableTint(button, usable, noMana) then
                r, g, b = uc and uc[1] or 0.4, uc and uc[2] or 0.4, uc and uc[3] or 0.4
                a = uc and uc[4] or a
                stateOverride = true
            end
        end
    end
    -- Apply user-configured icon tint when no state override is active
    if not stateOverride then
        if style.iconAuraTintEnabled and buttonData.auraTracking and button._auraActive then
            local c = style.iconAuraTintColor
            if c then
                r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end
        elseif style.iconCooldownTintEnabled and button._desatCooldownActive then
            local c = style.iconCooldownTintColor
            if c then
                r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end
        else
            if bc then
                r, g, b, a = bc[1] or 1, bc[2] or 1, bc[3] or 1, bc[4] or 1
            end
        end
    end
    if button._vertexR ~= r or button._vertexG ~= g or button._vertexB ~= b or button._vertexA ~= a then
        button._vertexR, button._vertexG, button._vertexB, button._vertexA = r, g, b, a
        button.icon:SetVertexColor(r, g, b, a)
    end
end

-- Icon desaturation: aura-tracked buttons desaturate when aura absent
-- (passive entries can invert this via invertAuraDesaturationLogic,
-- disable it entirely via neverDesaturate;
-- non-passive opt in via desaturateWhileAuraNotActive);
-- cooldown buttons desaturate based on _desatCooldownActive (set per-tick from cooldown / item state);
-- equippable-but-not-equipped items always desaturate.
-- Shared by icon-mode and bar-mode display paths.
local function EvaluateDesaturation(button, buttonData, style)
    local wantDesat = false
    if button._auraTrackingReady == true then
        if buttonData.isPassive then
            if buttonData.neverDesaturate then
                wantDesat = false
            elseif buttonData.invertAuraDesaturationLogic then
                wantDesat = button._auraActive == true
            else
                wantDesat = not button._auraActive
            end
        else
            wantDesat = buttonData.desaturateWhileAuraNotActive and not button._auraActive
        end
        if not wantDesat and not button._auraActive
            and style.desaturateOnCooldown and button._desatCooldownActive then
            wantDesat = true
        end
    elseif style.desaturateOnCooldown or buttonData.desaturateWhileZeroCharges
        or buttonData.desaturateWhileZeroStacks or button._isEquippableNotEquipped then
        if style.desaturateOnCooldown and button._desatCooldownActive then
            wantDesat = true
        end
        if not wantDesat and buttonData.desaturateWhileZeroCharges
                and button._chargeState == CHARGE_STATE_ZERO then
            wantDesat = true
        end
        if not wantDesat and buttonData.desaturateWhileZeroStacks and (button._itemCount or 0) == 0 then
            wantDesat = true
        end
    end
    if not wantDesat and button._isEquippableNotEquipped then
        wantDesat = true
    end
    if button._desaturated ~= wantDesat then
        button._desaturated = wantDesat
        button.icon:SetDesaturated(wantDesat)
    end
end

-- Exports
ST._UpdateChargeTracking = UpdateChargeTracking
ST._UpdateDisplayCountTracking = UpdateDisplayCountTracking
ST._UpdateItemChargeTracking = UpdateItemChargeTracking
ST._UpdateIconTint = UpdateIconTint
ST._EvaluateDesaturation = EvaluateDesaturation
