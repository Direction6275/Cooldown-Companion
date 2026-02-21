--[[
    CooldownCompanion - ButtonFrame/Visibility
    Per-button visibility rules and loss-of-control overlay
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon


local C_Spell_IsSpellUsable = C_Spell.IsSpellUsable
local IsUsableItem = C_Item.IsUsableItem

-- Evaluate per-button visibility rules and set hidden/alpha override state.
-- Called inside UpdateButtonCooldown after cooldown fetch and aura tracking are complete.
-- Fast path: if no toggles are enabled, zero overhead.
local function EvaluateButtonVisibility(button, buttonData, isGCDOnly, auraOverrideActive)
    -- Fast path: no visibility toggles enabled
    if not buttonData.hideWhileOnCooldown
       and not buttonData.hideWhileNotOnCooldown
       and not buttonData.hideWhileAuraNotActive
       and not buttonData.hideWhileAuraActive
       and not buttonData.hideWhileZeroCharges
       and not buttonData.hideWhileZeroStacks
       and not buttonData.hideWhileNotEquipped
       and not buttonData.hideWhileUnusable then
        button._visibilityHidden = false
        button._visibilityAlphaOverride = nil
        return
    end

    local shouldHide = false
    local hidReasonAuraNotActive = false
    local hidReasonAuraActive = false

    -- Check hideWhileOnCooldown
    if buttonData.hideWhileOnCooldown then
        if buttonData.hasCharges then
            -- Charged spells: hide when recharging or all charges consumed
            if button._mainCDShown or button._chargeRecharging then
                shouldHide = true
            end
        elseif buttonData.type == "item" then
            -- Items: check stored cooldown values (no GCD concept)
            if button._itemCdDuration and button._itemCdDuration > 0 then
                shouldHide = true
            end
        else
            -- Non-charged spells: _durationObj non-nil means active CD (secret-safe nil check)
            if button._durationObj and not isGCDOnly then
                shouldHide = true
            end
        end
    end

    -- Check hideWhileNotOnCooldown (inverse of hideWhileOnCooldown)
    if buttonData.hideWhileNotOnCooldown then
        if buttonData.hasCharges then
            -- Charged spells: hide only at max charges
            if not button._mainCDShown and not button._chargeRecharging then
                shouldHide = true
            end
        elseif buttonData.type == "item" then
            if not button._itemCdDuration or button._itemCdDuration == 0 then
                shouldHide = true
            end
        else
            -- Non-charged spells: not on cooldown (or only on GCD)
            if not button._durationObj or isGCDOnly then
                shouldHide = true
            end
        end
    end

    -- Check hideWhileAuraNotActive
    if buttonData.hideWhileAuraNotActive then
        if not auraOverrideActive then
            shouldHide = true
            hidReasonAuraNotActive = true
        end
    end

    -- Check hideWhileAuraActive
    if buttonData.hideWhileAuraActive then
        if auraOverrideActive then
            shouldHide = true
            hidReasonAuraActive = true
        end
    end

    -- Check hideWhileZeroCharges (charge-based items)
    local hidReasonZeroCharges = false
    if buttonData.hideWhileZeroCharges then
        if button._mainCDShown then
            shouldHide = true
            hidReasonZeroCharges = true
        end
    end

    -- Check hideWhileZeroStacks (stack-based items)
    local hidReasonZeroStacks = false
    if buttonData.hideWhileZeroStacks then
        if (button._itemCount or 0) == 0 then
            shouldHide = true
            hidReasonZeroStacks = true
        end
    end

    -- Check hideWhileNotEquipped (equippable items)
    local hidReasonNotEquipped = false
    if buttonData.hideWhileNotEquipped then
        if button._isEquippableNotEquipped then
            shouldHide = true
            hidReasonNotEquipped = true
        end
    end

    -- Check hideWhileUnusable
    if buttonData.hideWhileUnusable and not buttonData.isPassive then
        if buttonData.type == "spell" then
            local isUsable = C_Spell_IsSpellUsable(buttonData.id)
            if not isUsable then
                shouldHide = true
            end
        elseif buttonData.type == "item" then
            local usable = IsUsableItem(buttonData.id)
            if not usable then
                shouldHide = true
            end
        end
    end

    -- Baseline alpha fallback: if the ONLY reason we're hiding is aura-not-active
    -- and useBaselineAlphaFallback is enabled, dim instead of hiding
    if shouldHide and hidReasonAuraNotActive and buttonData.useBaselineAlphaFallback then
        -- Check if any OTHER hide condition also triggered
        local otherHide = false
        if buttonData.hideWhileOnCooldown then
            if buttonData.hasCharges then
                if button._mainCDShown or button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if button._itemCdDuration and button._itemCdDuration > 0 then otherHide = true end
            else
                if button._durationObj and not isGCDOnly then
                    otherHide = true
                end
            end
        end
        if buttonData.hideWhileNotOnCooldown then
            if buttonData.hasCharges then
                if not button._mainCDShown and not button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if not button._itemCdDuration or button._itemCdDuration == 0 then otherHide = true end
            else
                if not button._durationObj or isGCDOnly then otherHide = true end
            end
        end
        if buttonData.hideWhileAuraActive and auraOverrideActive then
            otherHide = true
        end
        if buttonData.hideWhileZeroCharges and button._mainCDShown then otherHide = true end
        if buttonData.hideWhileZeroStacks and (button._itemCount or 0) == 0 then otherHide = true end
        if buttonData.hideWhileNotEquipped and button._isEquippableNotEquipped then otherHide = true end
        if not otherHide then
            local groupId = button._groupId
            local group = groupId and CooldownCompanion.db.profile.groups[groupId]
            button._visibilityHidden = false
            button._visibilityAlphaOverride = group and group.baselineAlpha or 0.3
            return
        end
    end

    -- Baseline alpha fallback: if the ONLY reason we're hiding is aura-active
    -- and useBaselineAlphaFallbackAuraActive is enabled, dim instead of hiding
    if shouldHide and hidReasonAuraActive and buttonData.useBaselineAlphaFallbackAuraActive then
        local otherHide = false
        if buttonData.hideWhileOnCooldown then
            if buttonData.hasCharges then
                if button._mainCDShown or button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if button._itemCdDuration and button._itemCdDuration > 0 then otherHide = true end
            else
                if button._durationObj and not isGCDOnly then
                    otherHide = true
                end
            end
        end
        if buttonData.hideWhileNotOnCooldown then
            if buttonData.hasCharges then
                if not button._mainCDShown and not button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if not button._itemCdDuration or button._itemCdDuration == 0 then otherHide = true end
            else
                if not button._durationObj or isGCDOnly then otherHide = true end
            end
        end
        if buttonData.hideWhileAuraNotActive and not auraOverrideActive then
            otherHide = true
        end
        if buttonData.hideWhileZeroCharges and button._mainCDShown then otherHide = true end
        if buttonData.hideWhileZeroStacks and (button._itemCount or 0) == 0 then otherHide = true end
        if buttonData.hideWhileNotEquipped and button._isEquippableNotEquipped then otherHide = true end
        if not otherHide then
            local groupId = button._groupId
            local group = groupId and CooldownCompanion.db.profile.groups[groupId]
            button._visibilityHidden = false
            button._visibilityAlphaOverride = group and group.baselineAlpha or 0.3
            return
        end
    end

    -- Baseline alpha fallback: if the ONLY reason we're hiding is zero charges
    -- and useBaselineAlphaFallbackZeroCharges is enabled, dim instead of hiding
    if shouldHide and hidReasonZeroCharges and buttonData.useBaselineAlphaFallbackZeroCharges then
        local otherHide = false
        if buttonData.hideWhileOnCooldown then
            if buttonData.hasCharges then
                if button._mainCDShown or button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if button._itemCdDuration and button._itemCdDuration > 0 then otherHide = true end
            end
        end
        if buttonData.hideWhileNotOnCooldown then
            if buttonData.hasCharges then
                if not button._mainCDShown and not button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if not button._itemCdDuration or button._itemCdDuration == 0 then otherHide = true end
            end
        end
        if buttonData.hideWhileAuraNotActive and not auraOverrideActive then otherHide = true end
        if buttonData.hideWhileAuraActive and auraOverrideActive then otherHide = true end
        if buttonData.hideWhileZeroStacks and (button._itemCount or 0) == 0 then otherHide = true end
        if buttonData.hideWhileNotEquipped and button._isEquippableNotEquipped then otherHide = true end
        if not otherHide then
            local groupId = button._groupId
            local group = groupId and CooldownCompanion.db.profile.groups[groupId]
            button._visibilityHidden = false
            button._visibilityAlphaOverride = group and group.baselineAlpha or 0.3
            return
        end
    end

    -- Baseline alpha fallback: if the ONLY reason we're hiding is zero stacks
    -- and useBaselineAlphaFallbackZeroStacks is enabled, dim instead of hiding
    if shouldHide and hidReasonZeroStacks and buttonData.useBaselineAlphaFallbackZeroStacks then
        local otherHide = false
        if buttonData.hideWhileOnCooldown then
            if buttonData.hasCharges then
                if button._mainCDShown or button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if button._itemCdDuration and button._itemCdDuration > 0 then otherHide = true end
            end
        end
        if buttonData.hideWhileNotOnCooldown then
            if buttonData.hasCharges then
                if not button._mainCDShown and not button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if not button._itemCdDuration or button._itemCdDuration == 0 then otherHide = true end
            end
        end
        if buttonData.hideWhileAuraNotActive and not auraOverrideActive then otherHide = true end
        if buttonData.hideWhileAuraActive and auraOverrideActive then otherHide = true end
        if buttonData.hideWhileZeroCharges and button._mainCDShown then otherHide = true end
        if buttonData.hideWhileNotEquipped and button._isEquippableNotEquipped then otherHide = true end
        if not otherHide then
            local groupId = button._groupId
            local group = groupId and CooldownCompanion.db.profile.groups[groupId]
            button._visibilityHidden = false
            button._visibilityAlphaOverride = group and group.baselineAlpha or 0.3
            return
        end
    end

    -- Baseline alpha fallback: if the ONLY reason we're hiding is not-equipped
    -- and useBaselineAlphaFallbackNotEquipped is enabled, dim instead of hiding
    if shouldHide and hidReasonNotEquipped and buttonData.useBaselineAlphaFallbackNotEquipped then
        local otherHide = false
        if buttonData.hideWhileOnCooldown then
            if buttonData.type == "item" then
                if button._itemCdDuration and button._itemCdDuration > 0 then otherHide = true end
            end
        end
        if buttonData.hideWhileNotOnCooldown then
            if buttonData.type == "item" then
                if not button._itemCdDuration or button._itemCdDuration == 0 then otherHide = true end
            end
        end
        if buttonData.hideWhileAuraNotActive and not auraOverrideActive then otherHide = true end
        if buttonData.hideWhileAuraActive and auraOverrideActive then otherHide = true end
        if buttonData.hideWhileZeroCharges and button._mainCDShown then otherHide = true end
        if buttonData.hideWhileZeroStacks and (button._itemCount or 0) == 0 then otherHide = true end
        if not otherHide then
            local groupId = button._groupId
            local group = groupId and CooldownCompanion.db.profile.groups[groupId]
            button._visibilityHidden = false
            button._visibilityAlphaOverride = group and group.baselineAlpha or 0.3
            return
        end
    end

    button._visibilityHidden = shouldHide
    button._visibilityAlphaOverride = nil
end

-- Update loss-of-control cooldown on a button.
-- Uses a CooldownFrame to avoid comparing secret values — the raw start/duration
-- go directly to SetCooldown which handles them on the C side.
local function UpdateLossOfControl(button)
    if not button.locCooldown then return end

    if button.style.showLossOfControl and button.buttonData.type == "spell" and not button.buttonData.isPassive then
        local locDuration = C_Spell.GetSpellLossOfControlCooldownDuration(button.buttonData.id)
        if locDuration then
            button.locCooldown:SetCooldownFromDurationObject(locDuration)
        else
            button.locCooldown:SetCooldown(C_Spell.GetSpellLossOfControlCooldown(button.buttonData.id))
        end
    end
end

-- Exports
ST._EvaluateButtonVisibility = EvaluateButtonVisibility
ST._UpdateLossOfControl = UpdateLossOfControl
