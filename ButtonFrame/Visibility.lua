--[[
    CooldownCompanion - ButtonFrame/Visibility
    Per-button visibility rules and loss-of-control overlay
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon


local C_Spell_IsSpellUsable = C_Spell.IsSpellUsable
local IsUsableItem = C_Item.IsUsableItem

local bit_band = bit.band
local bit_bor  = bit.bor

-- Bitmask constants for hide reasons
local HIDE_ON_COOLDOWN      = 0x001
local HIDE_NOT_ON_COOLDOWN  = 0x002
local HIDE_AURA_NOT_ACTIVE  = 0x004
local HIDE_AURA_ACTIVE      = 0x008
local HIDE_NO_PROC          = 0x010
local HIDE_ZERO_CHARGES     = 0x020
local HIDE_ZERO_STACKS      = 0x040
local HIDE_NOT_EQUIPPED     = 0x080
local HIDE_UNUSABLE         = 0x100

-- Baseline alpha fallback descriptors: each entry maps a hide reason bit
-- to the buttonData config key that enables "dim instead of hide" when
-- that reason is the ONLY active hide reason.
-- IMPORTANT: Every HIDE_* constant that supports a fallback MUST have an
-- entry here. A missing entry will silently cause full hide instead of dim.
-- Fallbacks do not compose: multiple active reasons = full hide even if
-- each individually has its fallback enabled.
local BASELINE_FALLBACKS = {
    { bit = HIDE_AURA_NOT_ACTIVE, key = "useBaselineAlphaFallback" },
    { bit = HIDE_AURA_ACTIVE,     key = "useBaselineAlphaFallbackAuraActive" },
    { bit = HIDE_ZERO_CHARGES,    key = "useBaselineAlphaFallbackZeroCharges" },
    { bit = HIDE_ZERO_STACKS,     key = "useBaselineAlphaFallbackZeroStacks" },
    { bit = HIDE_NOT_EQUIPPED,    key = "useBaselineAlphaFallbackNotEquipped" },
    { bit = HIDE_ON_COOLDOWN,     key = "useBaselineAlphaFallbackOnCooldown" },
    { bit = HIDE_NOT_ON_COOLDOWN, key = "useBaselineAlphaFallbackNotOnCooldown" },
    { bit = HIDE_NO_PROC,         key = "useBaselineAlphaFallbackNoProc" },
    { bit = HIDE_UNUSABLE,        key = "useBaselineAlphaFallbackUnusable" },
}

-- Evaluate per-button visibility rules and set hidden/alpha override state.
-- Called inside UpdateButtonCooldown after cooldown fetch and aura tracking are complete.
-- Fast path: if no toggles are enabled, zero overhead.
local function EvaluateButtonVisibility(button, buttonData, isGCDOnly, auraOverrideActive, procOverlayActive)
    -- Fast path: no visibility toggles enabled
    if not buttonData.hideWhileOnCooldown
       and not buttonData.hideWhileNotOnCooldown
       and not buttonData.hideWhileAuraNotActive
       and not buttonData.hideWhileAuraActive
       and not buttonData.hideWhileNoProc
       and not buttonData.hideWhileZeroCharges
       and not buttonData.hideWhileZeroStacks
       and not buttonData.hideWhileNotEquipped
       and not buttonData.hideWhileUnusable then
        button._visibilityHidden = false
        button._visibilityAlphaOverride = nil
        return
    end

    -- Phase 1: Evaluate each hide condition and accumulate active reasons as bits.
    local hideReasons = 0

    -- Check hideWhileOnCooldown (skip for no-CD spells — always "not on CD")
    if buttonData.hideWhileOnCooldown and not button._noCooldown then
        if buttonData.hasCharges then
            if button._mainCDShown or button._chargeRecharging then
                hideReasons = bit_bor(hideReasons, HIDE_ON_COOLDOWN)
            end
        elseif buttonData.type == "item" then
            if button._itemCdDuration and button._itemCdDuration > 0 and not isGCDOnly then
                hideReasons = bit_bor(hideReasons, HIDE_ON_COOLDOWN)
            end
        else
            if button._durationObj and not isGCDOnly and not auraOverrideActive then
                hideReasons = bit_bor(hideReasons, HIDE_ON_COOLDOWN)
            end
        end
    end

    -- Check hideWhileNotOnCooldown (skip for no-CD spells — would permanently hide)
    if buttonData.hideWhileNotOnCooldown and not button._noCooldown then
        if buttonData.hasCharges then
            if not button._mainCDShown and not button._chargeRecharging then
                hideReasons = bit_bor(hideReasons, HIDE_NOT_ON_COOLDOWN)
            end
        elseif buttonData.type == "item" then
            if not button._itemCdDuration or button._itemCdDuration == 0 or isGCDOnly then
                hideReasons = bit_bor(hideReasons, HIDE_NOT_ON_COOLDOWN)
            end
        else
            if (not button._durationObj or isGCDOnly) and not auraOverrideActive then
                hideReasons = bit_bor(hideReasons, HIDE_NOT_ON_COOLDOWN)
            end
        end
    end

    -- Check hideWhileAuraNotActive
    if buttonData.hideWhileAuraNotActive and not auraOverrideActive then
        hideReasons = bit_bor(hideReasons, HIDE_AURA_NOT_ACTIVE)
    end

    -- Check hideWhileAuraActive
    if buttonData.hideWhileAuraActive and auraOverrideActive then
        if not (buttonData.hideAuraActiveExceptPandemic and button._inPandemic) then
            hideReasons = bit_bor(hideReasons, HIDE_AURA_ACTIVE)
        end
    end

    -- Check hideWhileNoProc (spell entries added as spells only)
    if buttonData.hideWhileNoProc then
        local isSpellEntry = buttonData.type == "spell" and buttonData.addedAs ~= "aura" and not buttonData.isPassive
        if isSpellEntry and not procOverlayActive then
            hideReasons = bit_bor(hideReasons, HIDE_NO_PROC)
        end
    end

    -- Check hideWhileZeroCharges (charge-based spells and items)
    if buttonData.hideWhileZeroCharges and button._zeroChargesConfirmed then
        hideReasons = bit_bor(hideReasons, HIDE_ZERO_CHARGES)
    end

    -- Check hideWhileZeroStacks (stack-based items)
    if buttonData.hideWhileZeroStacks and (button._itemCount or 0) == 0 then
        hideReasons = bit_bor(hideReasons, HIDE_ZERO_STACKS)
    end

    -- Check hideWhileNotEquipped (equippable items)
    if buttonData.hideWhileNotEquipped and button._isEquippableNotEquipped then
        hideReasons = bit_bor(hideReasons, HIDE_NOT_EQUIPPED)
    end

    -- Check hideWhileUnusable
    if buttonData.hideWhileUnusable and not buttonData.isPassive then
        if buttonData.type == "spell" then
            if not C_Spell_IsSpellUsable(buttonData.id) then
                hideReasons = bit_bor(hideReasons, HIDE_UNUSABLE)
            end
        elseif buttonData.type == "item" then
            if not IsUsableItem(buttonData.id) then
                hideReasons = bit_bor(hideReasons, HIDE_UNUSABLE)
            end
        end
    end

    -- Phase 2: Baseline alpha fallback.
    -- If exactly one hide reason fired and its fallback is enabled,
    -- dim to baselineAlpha instead of fully hiding the button.
    -- hideReasons == entry.bit is true iff no other bit is set,
    -- which is equivalent to "this is the only active hide reason."
    if hideReasons ~= 0 then
        for _, entry in ipairs(BASELINE_FALLBACKS) do
            if bit_band(hideReasons, entry.bit) ~= 0 and buttonData[entry.key] then
                if hideReasons == entry.bit then
                    local groupId = button._groupId
                    local group = groupId and CooldownCompanion.db.profile.groups[groupId]
                    button._visibilityHidden = false
                    button._visibilityAlphaOverride = group and group.baselineAlpha or 0.3
                    return
                end
            end
        end
        button._visibilityHidden = true
        button._visibilityAlphaOverride = nil
    else
        button._visibilityHidden = false
        button._visibilityAlphaOverride = nil
    end
end

-- Update loss-of-control cooldown on a button.
-- DurationObject path handles secret values. If no DurationObject is available
-- (no LoC active), clear the cooldown. The legacy GetSpellLossOfControlCooldown
-- returns secret start/duration that SetCooldown will reject after the 12.0.1 hotfix.
local function UpdateLossOfControl(button)
    if not button.locCooldown then return end

    if button.style.showLossOfControl and button.buttonData.type == "spell" and not button.buttonData.isPassive then
        local locDuration = C_Spell.GetSpellLossOfControlCooldownDuration(button.buttonData.id)
        if locDuration then
            button.locCooldown:SetCooldownFromDurationObject(locDuration)
        else
            button.locCooldown:SetCooldown(0, 0)
        end
    end
end

-- Exports
ST._EvaluateButtonVisibility = EvaluateButtonVisibility
ST._UpdateLossOfControl = UpdateLossOfControl
