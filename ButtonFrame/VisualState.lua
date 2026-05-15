--[[
    CooldownCompanion - ButtonFrame/VisualState
    Per-button visual-state snapshot shared by display consumers.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic
local COOLDOWN_STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN
local COOLDOWN_STATE_GCD = CooldownLogic.STATE_GCD
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO

local InCombatLockdown = InCombatLockdown
local UnitCanAttack = UnitCanAttack
local IsItemInRange = C_Item.IsItemInRange
local IsUsableItem = C_Item.IsUsableItem
local IsSpellUsable = C_Spell.IsSpellUsable

local DEFAULT_WHITE = {1, 1, 1, 1}

local function GetIconTintBaseAlpha(style)
    local c = style and style.iconTintColor
    return c and c[4] or 1
end

local function SetTint(state, r, g, b, a, reason, unusable)
    state.tintR = r
    state.tintG = g
    state.tintB = b
    state.tintA = a
    state.tintReason = reason
    state.unusableTintActive = unusable == true
end

local function ResolveUsability(button, buttonData)
    if not buttonData or buttonData.isPassive then
        return false
    end

    if button._conditionalUnusablePreview then
        return true
    end

    if buttonData.type == "spell" then
        local spellID = button._displaySpellId or buttonData.id
        return not IsSpellUsable(spellID)
    end

    if buttonData.type == "item" or buttonData.type == "equipitem" then
        return not IsUsableItem(button._resolvedItemId or buttonData.id)
    end

    return false
end

local function ResolveOutOfRange(button, buttonData, style)
    if not (style and style.showOutOfRange) then
        return false
    end

    if button._conditionalOutOfRangePreview then
        return true
    end

    if buttonData.type == "spell" then
        return button._spellOutOfRange == true
    end

    if buttonData.type == "item" or buttonData.type == "equipitem" then
        if not InCombatLockdown() or UnitCanAttack("player", "target") then
            local inRange = IsItemInRange(button._resolvedItemId or buttonData.id, "target")
            return inRange == false
        end
    end

    return false
end

local function ResolveDesaturation(button, buttonData, style, cooldownVisualActive)
    local wantDesat = false
    local reason = "base"

    if button._auraTrackingReady == true then
        if buttonData.isPassive then
            if buttonData.neverDesaturate then
                wantDesat = false
                reason = "passive-never-desaturate"
            elseif buttonData.invertAuraDesaturationLogic then
                wantDesat = button._auraActive == true
                reason = wantDesat and "passive-aura-active-inverted" or "passive-aura-missing-inverted"
            else
                wantDesat = not button._auraActive
                reason = wantDesat and "passive-aura-missing" or "passive-aura-active"
            end
        else
            wantDesat = buttonData.desaturateWhileAuraNotActive and not button._auraActive
            reason = wantDesat and "aura-missing" or "aura-tracked"
        end

        if not wantDesat and not button._auraActive
            and style.desaturateOnCooldown and cooldownVisualActive then
            wantDesat = true
            reason = "cooldown-presentation-while-aura-missing"
        end
    elseif style.desaturateOnCooldown or buttonData.desaturateWhileZeroCharges
        or buttonData.desaturateWhileZeroStacks or button._isEquippableNotEquipped then
        if style.desaturateOnCooldown and cooldownVisualActive then
            wantDesat = true
            reason = "cooldown-presentation"
        end

        if not wantDesat and buttonData.desaturateWhileZeroCharges
                and not CooldownCompanion.HasItemFallbacks(buttonData)
                and button._chargeState == CHARGE_STATE_ZERO then
            wantDesat = true
            reason = "zero-charges"
        end

        local itemUseCount = CooldownCompanion.HasItemFallbacks(buttonData)
            and button._resolvedItemAvailableQuantity
            or button._itemCount
        if not wantDesat and buttonData.desaturateWhileZeroStacks and (itemUseCount or 0) == 0 then
            wantDesat = true
            reason = "zero-stacks"
        end
    end

    if not wantDesat and button._isEquippableNotEquipped then
        wantDesat = true
        reason = "not-equipped"
    end

    return wantDesat, reason
end

local function ResolveTint(button, buttonData, style, state)
    state.outOfRange = ResolveOutOfRange(button, buttonData, style)
    state.unusable = ResolveUsability(button, buttonData)

    if buttonData.isPassive then
        local c
        local reason = "base"
        if style.iconAuraTintEnabled and buttonData.auraTracking and button._auraActive then
            c = style.iconAuraTintColor
            reason = "aura"
        end
        c = c or style.iconTintColor or DEFAULT_WHITE
        SetTint(state, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1, reason, false)
        return
    end

    local base = style.iconTintColor
    local r, g, b, a = 1, 1, 1, GetIconTintBaseAlpha(style)

    if state.outOfRange then
        SetTint(state, 1, 0.2, 0.2, a, "out-of-range", false)
        return
    end

    if style.showUnusable and state.unusable then
        local apiUnusableDuringCooldown = not button._conditionalUnusablePreview
            and (state.cooldownPresentationActive == true or state.gcdActive == true)
        if not apiUnusableDuringCooldown then
            local c = style.iconUnusableTintColor
            SetTint(
                state,
                c and c[1] or 0.4,
                c and c[2] or 0.4,
                c and c[3] or 0.4,
                c and c[4] or a,
                "unusable",
                true
            )
            return
        end
        state.suppressedUnusableTintReason = "cooldown-or-gcd"
    end

    if style.iconAuraTintEnabled and buttonData.auraTracking and button._auraActive then
        local c = style.iconAuraTintColor
        if c then
            SetTint(state, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1, "aura", false)
            return
        end
    end

    if style.iconCooldownTintEnabled and state.cooldownVisualActive then
        local c = style.iconCooldownTintColor
        if c then
            SetTint(state, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1, "cooldown", false)
            return
        end
    end

    if base then
        SetTint(state, base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1, "base", false)
    else
        SetTint(state, r, g, b, a, "base", false)
    end
end

local function ResolveIconFill(button, buttonData, state)
    local auraPreview = button._conditionalAuraPreview == true
        or button._conditionalAuraDurationTextPreview == true
    local cooldownPreview = button._conditionalPreviewDomain == "cooldown"

    if button._auraActive == true or auraPreview then
        state.iconFillActive = true
        state.iconFillMode = (button._auraHasTimer == false and not auraPreview) and "aura_static" or "aura"
        state.iconFillReason = auraPreview and "aura-preview" or "aura"
        return
    end

    if cooldownPreview
        or state.cooldownState == COOLDOWN_STATE_COOLDOWN
        or (CooldownCompanion.UsesChargeBehavior(buttonData)
            and button._chargeRecharging == true
            and button._hideCooldownChargesActive ~= true) then
        state.iconFillActive = true
        state.iconFillMode = "cooldown"
        state.iconFillReason = cooldownPreview and "cooldown-preview" or "cooldown"
        return
    end

    state.iconFillActive = false
    state.iconFillMode = nil
    state.iconFillReason = "inactive"
end

local function BuildButtonVisualState(button, buttonData, style, cooldownSpellId, fetchOk, isOnGCD, isGCDOnly)
    if not (button and buttonData and style) then
        return nil
    end

    local state = button._visualState
    if not state then
        state = {}
        button._visualState = state
    end

    state.version = 1
    state.spellID = cooldownSpellId or buttonData.id
    state.cooldownState = button._cooldownState
    state.cooldownActive = button._desatCooldownActive == true
    state.cooldownPresentationActive = button._cooldownState == COOLDOWN_STATE_COOLDOWN
        or (button._cooldownState == COOLDOWN_STATE_GCD and style.showGCDSwipe == true)
    state.cooldownVisualActive = state.cooldownPresentationActive == true
    state.gcdActive = isOnGCD == true or button._cooldownState == COOLDOWN_STATE_GCD
    state.gcdOnly = isGCDOnly == true
    state.fetchOk = fetchOk == true
    state.noCooldown = button._noCooldown == true
    state.chargeState = button._chargeState
    state.chargeCooldownActive = button._chargeState == CHARGE_STATE_ZERO
    state.chargeRecharging = button._chargeRecharging == true
    state.barCooldownActive = button._chargeState == CHARGE_STATE_MISSING
        or button._chargeState == CHARGE_STATE_ZERO
        or button._cooldownState == COOLDOWN_STATE_COOLDOWN
    state.ready = not buttonData.isPassive
        and button._noCooldown ~= true
        and button._desatCooldownActive == false
        and state.cooldownPresentationActive ~= true
    state.readyGlowEligible = state.ready
    state.visibilityHidden = button._visibilityHidden == true
    state.visibilityAlpha = button._visibilityAlphaOverride or 1
    state.suppressedUnusableTintReason = nil

    state.desaturated, state.desaturationReason = ResolveDesaturation(button, buttonData, style, state.cooldownVisualActive)
    state.desaturatedByCooldown = state.desaturated == true
        and (state.desaturationReason == "cooldown-presentation"
            or state.desaturationReason == "cooldown-presentation-while-aura-missing")

    ResolveTint(button, buttonData, style, state)
    ResolveIconFill(button, buttonData, state)

    button._visualDesaturationReason = state.desaturationReason
    button._visualTintReason = state.tintReason
    button._visualSuppressedUnusableTintReason = state.suppressedUnusableTintReason
    button._isUnusable = state.unusable == true
    button._isOutOfRange = state.outOfRange == true

    return state
end

local function ClearButtonVisualState(button)
    if not button then return end
    button._visualState = nil
    button._visualDesaturationReason = nil
    button._visualTintReason = nil
    button._visualSuppressedUnusableTintReason = nil
end

ST._BuildButtonVisualState = BuildButtonVisualState
ST._ClearButtonVisualState = ClearButtonVisualState
CooldownCompanion.BuildButtonVisualState = BuildButtonVisualState
CooldownCompanion.ClearButtonVisualState = ClearButtonVisualState
