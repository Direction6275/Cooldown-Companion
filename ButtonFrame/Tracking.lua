--[[
    CooldownCompanion - ButtonFrame/Tracking
    Charge tracking (spell + item) and icon tinting
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

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

    -- Update persisted maxCharges when readable. Prefer API maxCharges over
    -- display count, which can reflect current charges instead of true max.
    local persistedMax = buttonData.maxCharges or 0
    if charges and charges.maxCharges ~= nil and not issecretvalue(charges.maxCharges) then
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
    if charges and charges.maxCharges ~= nil and not issecretvalue(charges.maxCharges)
       and charges.maxCharges <= 1 then
        buttonData.hasCharges = nil
        buttonData.maxCharges = charges.maxCharges
        button.count:SetText("")
        button._chargeText = nil
        return nil
    end

    -- Fallback: if API maxCharges is unavailable (nil/secret), keep upward-only
    -- observed max from readable charge count.
    if cur and cur > persistedMax then
        buttonData.maxCharges = cur
    end
    local mx = buttonData.maxCharges  -- Cached from outside combat

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
            local isUsable = C_Spell.IsSpellUsable(buttonData.id)
            if not isUsable then
                r, g, b = uc and uc[1] or 0.4, uc and uc[2] or 0.4, uc and uc[3] or 0.4
                a = uc and uc[4] or a
                stateOverride = true
            end
        elseif buttonData.type == "item" then
            local usable, noMana = IsUsableItem(buttonData.id)
            if not usable then
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

-- Exports
ST._UpdateChargeTracking = UpdateChargeTracking
ST._UpdateItemChargeTracking = UpdateItemChargeTracking
ST._UpdateIconTint = UpdateIconTint
