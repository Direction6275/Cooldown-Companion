--[[
    CooldownCompanion - ButtonFrame/Tracking
    Charge tracking (spell + item), icon tinting, and desaturation
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO

-- Localize frequently-used globals
local issecretvalue = issecretvalue
local tonumber = tonumber
local InCombatLockdown = InCombatLockdown
local UnitCanAttack = UnitCanAttack
local IsItemInRange = C_Item.IsItemInRange
local IsUsableItem = C_Item.IsUsableItem
local C_Spell_IsSpellUsable = C_Spell.IsSpellUsable
local IsEntryItemLike = CooldownCompanion.IsEntryItemLike or function(buttonData)
    return buttonData
        and (buttonData.type == "item"
            or (buttonData.type == "equipmentSlot"
                and buttonData.itemSlotKind == "trinket"
                and (buttonData.itemSlot == 13 or buttonData.itemSlot == 14)))
end

local function GetReadableMaxCharges(charges)
    local maxCharges = charges and charges.maxCharges
    if maxCharges and not issecretvalue(maxCharges) then
        return tonumber(maxCharges)
    end
    return nil
end

local function ResolveRuntimeChargeInfo(buttonData, chargeSpellID)
    local spellID = chargeSpellID or buttonData.id
    local charges = C_Spell.GetSpellCharges(spellID)
    local maxCharges = GetReadableMaxCharges(charges)

    if (not maxCharges or maxCharges <= 1)
        and ST.ResolveSpellChargeInfo
        and buttonData.id then
        local resolvedCharges, resolvedSpellID, resolvedMaxCharges = ST.ResolveSpellChargeInfo(buttonData.id)
        if resolvedCharges and (resolvedMaxCharges or 0) > 1 then
            return resolvedCharges, resolvedSpellID or buttonData.id, true, resolvedMaxCharges
        end
    end

    return charges, spellID, false, maxCharges
end

-- Update charge count state for a spell with hasCharges enabled.
-- chargeSpellID should be the effective runtime spell ID (override-aware).
-- Returns the raw charges API table (may be nil) for use by callers.
local function UpdateChargeTracking(button, buttonData, chargeSpellID)
    local previousReadableCharges = button._chargeCountReadable == true
        and button._currentReadableCharges
        or nil
    local charges, spellID, usedChargeFallback, maxCharges = ResolveRuntimeChargeInfo(buttonData, chargeSpellID)
    button._chargeSpellId = spellID
    button._chargeInfoFromFallback = usedChargeFallback or nil

    -- Read current charges only from the authoritative charge API field.
    -- Display-count APIs are UI-oriented and can transiently read 0 during
    -- lockout windows even when charges remain.
    local cur
    if charges and charges.currentCharges ~= nil and not issecretvalue(charges.currentCharges) then
        cur = charges.currentCharges
        button._lastReadableCharges = cur
    elseif (usedChargeFallback or (maxCharges or 0) > 1)
        and previousReadableCharges ~= nil then
        button._lastReadableCharges = previousReadableCharges
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
        button._lastReadableCharges = nil
        button._chargeSpellId = nil
        button._chargeInfoFromFallback = nil
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
    local itemID = button._resolvedItemId or buttonData.id
    local chargeCount = C_Item.GetItemCount(itemID, false, true)

    -- Update persisted maxCharges upward only for the primary item. Fallback
    -- stacks and charges are runtime choices, not permanent entry metadata.
    local isPrimaryItem = tonumber(itemID) == tonumber(buttonData.id)
    if isPrimaryItem and chargeCount > (buttonData.maxCharges or 0) then
        buttonData.maxCharges = chargeCount
    elseif not isPrimaryItem and chargeCount > (button._resolvedItemMaxCharges or 0) then
        button._resolvedItemMaxCharges = chargeCount
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

local function SetTintIntent(target, active, reason, unusableActive, r, g, b, a)
    target.active = active == true
    target.reason = reason
    target.unusableActive = unusableActive == true
    target.r = r
    target.g = g
    target.b = b
    target.a = a
    return target
end

local function IsUnusableVisualActive(button, buttonData)
    if buttonData and buttonData._rotationAssistantVirtual == true and buttonData._rotationAssistantMissing == true then
        return false
    end
    if buttonData.isPassive or buttonData.isPassiveCooldown then
        return false
    end
    if button._conditionalUnusablePreview then
        return true, "unusable-preview"
    end
    if buttonData.type == "spell" then
        local spellID = button._displaySpellId or buttonData.id
        if not C_Spell_IsSpellUsable(spellID) then
            return true, "unusable"
        end
    elseif IsEntryItemLike(buttonData) then
        local itemID = button._resolvedItemId or buttonData.id
        if not itemID or not IsUsableItem(itemID) then
            return true, "unusable"
        end
    end
    return false
end

-- Icon tinting: out-of-range red > unusable dim mode > aura tint > cooldown tint > base tint.
-- This resolver may read range/usability APIs; call it only from the normal tint update path.
local function ResolveIconTintIntent(button, buttonData, style, target)
    target = target or {}
    if type(button) ~= "table" or type(buttonData) ~= "table" then
        return SetTintIntent(target, false, nil, false, 1, 1, 1, 1)
    end

    style = style or {}

    if buttonData._rotationAssistantVirtual == true and buttonData._rotationAssistantMissing == true then
        return SetTintIntent(target, false, nil, false, 1, 1, 1, 1)
    end

    if buttonData.isPassive then
        local c
        local reason = "base"
        if style.iconAuraTintEnabled and buttonData.auraTracking and button._auraActive and style.iconAuraTintColor then
            c = style.iconAuraTintColor
            reason = "aura"
        end
        c = c or style.iconTintColor
        local r, g, b, a = c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1
        return SetTintIntent(target, reason ~= "base", reason, false, r, g, b, a)
    end

    local bc = style.iconTintColor
    local r, g, b, a = 1, 1, 1, bc and bc[4] or 1
    local reason = "base"
    local stateOverride = false
    local unusableActive = false

    if style.showOutOfRange then
        if button._conditionalOutOfRangePreview then
            r, g, b = 1, 0.2, 0.2
            reason = "out-of-range-preview"
            stateOverride = true
        elseif buttonData.type == "spell" then
            if button._spellOutOfRange then
                r, g, b = 1, 0.2, 0.2
                reason = "out-of-range"
                stateOverride = true
            end
        elseif IsEntryItemLike(buttonData) then
            -- C_Item.IsItemInRange is protected in combat for non-enemy targets (10.2.0);
            -- only call when out of combat or target is attackable.
            if not InCombatLockdown() or UnitCanAttack("player", "target") then
                local itemID = button._resolvedItemId or buttonData.id
                local inRange = itemID and IsItemInRange(itemID, "target") or nil
                -- inRange is nil when no target or item has no range; only tint on explicit false
                if inRange == false then
                    r, g, b = 1, 0.2, 0.2
                    reason = "out-of-range"
                    stateOverride = true
                end
            end
        end
    end

    if not stateOverride and style.showUnusable and ST.UnusableVisualUsesDimTint(style) then
        local uc = style.iconUnusableTintColor
        local isUnusable, unusableReason = IsUnusableVisualActive(button, buttonData)
        if isUnusable then
            r, g, b = uc and uc[1] or 0.4, uc and uc[2] or 0.4, uc and uc[3] or 0.4
            a = uc and uc[4] or a
            reason = unusableReason or "unusable"
            stateOverride = true
            unusableActive = true
        end
    end

    -- Apply user-configured icon tint when no state override is active.
    if not stateOverride then
        if style.iconAuraTintEnabled and buttonData.auraTracking and button._auraActive then
            local c = style.iconAuraTintColor
            if c then
                r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end
            reason = "aura"
        elseif style.iconCooldownTintEnabled and button._desatCooldownActive then
            local c = style.iconCooldownTintColor
            if c then
                r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end
            reason = "cooldown"
        elseif bc then
            r, g, b, a = bc[1] or 1, bc[2] or 1, bc[3] or 1, bc[4] or 1
        end
    end

    return SetTintIntent(target, reason ~= "base", reason, unusableActive, r, g, b, a)
end

-- Shared by icon-mode and bar-mode display paths.
local function UpdateIconTint(button, buttonData, style)
    local intent = button._iconTintIntent
    if type(intent) ~= "table" then
        intent = {}
        button._iconTintIntent = intent
    end

    ResolveIconTintIntent(button, buttonData, style, intent)

    local r, g, b, a = intent.r, intent.g, intent.b, intent.a
    button._unusableTintActive = intent.unusableActive == true
    if button._vertexR ~= r or button._vertexG ~= g or button._vertexB ~= b or button._vertexA ~= a then
        button._vertexR, button._vertexG, button._vertexB, button._vertexA = r, g, b, a
        button.icon:SetVertexColor(r, g, b, a)
    end
end

local function ResolveDesaturationIntent(button, buttonData, style, target)
    target = target or {}
    target.active = false
    target.reason = nil

    if type(button) ~= "table" or type(buttonData) ~= "table" then
        return target
    end

    style = style or {}

    if button._auraTrackingReady == true then
        if buttonData.isPassive then
            if buttonData.neverDesaturate then
                target.active = false
            elseif buttonData.invertAuraDesaturationLogic then
                target.active = button._auraActive == true
                if target.active then
                    target.reason = "passive-aura-active-inverted"
                end
            else
                target.active = not button._auraActive
                if target.active then
                    target.reason = "passive-aura-missing"
                end
            end
        else
            target.active = buttonData.desaturateWhileAuraNotActive and not button._auraActive or false
            if target.active then
                target.reason = "aura-missing"
            end
        end
        if not target.active and not button._auraActive
            and style.desaturateOnCooldown and button._desatCooldownActive then
            target.active = true
            target.reason = "cooldown"
        end
    elseif style.desaturateOnCooldown or buttonData.desaturateWhileZeroCharges
        or buttonData.desaturateWhileZeroStacks or button._isEquippableNotEquipped then
        if style.desaturateOnCooldown and button._desatCooldownActive then
            target.active = true
            target.reason = "cooldown"
        end
        if not target.active and buttonData.desaturateWhileZeroCharges
                and not CooldownCompanion.HasItemFallbacks(buttonData)
                and button._chargeState == CHARGE_STATE_ZERO then
            target.active = true
            target.reason = "zero-charges"
        end
        local itemUseCount = CooldownCompanion.HasItemFallbacks(buttonData)
            and button._resolvedItemAvailableQuantity
            or button._itemCount
        if not target.active and buttonData.type == "item"
                and buttonData.desaturateWhileZeroStacks and (itemUseCount or 0) == 0 then
            target.active = true
            target.reason = "zero-stacks"
        end
    end
    if not target.active and button._isEquippableNotEquipped then
        target.active = true
        target.reason = "not-equipped"
    end
    if not target.active and style.showUnusable and ST.UnusableVisualUsesDesaturation(style) then
        local isUnusable, unusableReason = IsUnusableVisualActive(button, buttonData)
        if isUnusable then
            target.active = true
            target.reason = unusableReason or "unusable"
        end
    end

    return target
end

-- Icon desaturation: aura-tracked buttons desaturate when aura absent
-- (passive entries can invert this via invertAuraDesaturationLogic,
-- disable it entirely via neverDesaturate;
-- non-passive opt in via desaturateWhileAuraNotActive);
-- cooldown buttons desaturate based on _desatCooldownActive (set per-tick from cooldown / item state);
-- equippable-but-not-equipped items always desaturate.
-- Shared by icon-mode and bar-mode display paths.
local function EvaluateDesaturation(button, buttonData, style)
    local intent = button._desaturationIntent
    if type(intent) ~= "table" then
        intent = {}
        button._desaturationIntent = intent
    end

    ResolveDesaturationIntent(button, buttonData, style, intent)

    if button._desaturated ~= intent.active then
        button._desaturated = intent.active
        button.icon:SetDesaturated(intent.active)
    end
end

-- Exports
ST._UpdateChargeTracking = UpdateChargeTracking
ST._UpdateDisplayCountTracking = UpdateDisplayCountTracking
ST._UpdateItemChargeTracking = UpdateItemChargeTracking
ST._UpdateIconTint = UpdateIconTint
ST._ResolveIconTintIntent = ResolveIconTintIntent
ST._ResolveDesaturationIntent = ResolveDesaturationIntent
ST._ResolveIconDesaturationIntent = ResolveDesaturationIntent
ST._EvaluateDesaturation = EvaluateDesaturation
