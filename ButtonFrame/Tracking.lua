--[[
    CooldownCompanion - ButtonFrame/Tracking
    Charge tracking (spell + item) and icon tinting
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals
local tonumber = tonumber
local issecretvalue = issecretvalue
local InCombatLockdown = InCombatLockdown
local IsItemInRange = C_Item.IsItemInRange
local IsUsableItem = C_Item.IsUsableItem

-- Update charge count state for a spell with hasCharges enabled.
-- chargeSpellID should be the effective runtime spell ID (override-aware).
-- Returns the raw charges API table (may be nil) for use by callers.
local function UpdateChargeTracking(button, buttonData, chargeSpellID)
    local spellID = chargeSpellID or buttonData.id
    local charges = C_Spell.GetSpellCharges(spellID)

    -- Try to read current charges as plain number (works outside restricted).
    -- Prefer charges.currentCharges (authoritative charge system value) over
    -- GetSpellDisplayCount (UI-oriented, may drop to 0 during lockouts).
    local cur
    if charges and charges.currentCharges ~= nil and not issecretvalue(charges.currentCharges) then
        cur = charges.currentCharges
    end
    if cur == nil then
        cur = tonumber(C_Spell.GetSpellDisplayCount(spellID))
    end
    if cur == nil then
        -- Tertiary fallback: cast count can reflect cast availability semantics
        -- for some spells; for standard charge spells this still tracks charges.
        local castCount = C_Spell.GetSpellCastCount(spellID)
        if castCount ~= nil and not issecretvalue(castCount) then
            cur = castCount
        end
    end
    button._currentReadableCharges = cur

    -- Update persisted maxCharges when readable. Prefer API maxCharges over
    -- display count, which can reflect current charges instead of true max.
    local persistedMax = buttonData.maxCharges or 0
    if charges and charges.maxCharges ~= nil and not issecretvalue(charges.maxCharges) then
        if charges.maxCharges ~= persistedMax then
            buttonData.maxCharges = charges.maxCharges
            persistedMax = charges.maxCharges
        end
    end

    -- Fallback: if maxCharges is unavailable, keep upward-only observed max.
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
            -- Secret: pass directly to SetText (C-level renders it)
            -- Can't compare secrets, so always call SetText
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

    -- Display charge text with change detection
    local showChargeText = button.style and button.style.showChargeText
    if not showChargeText then
        button.count:SetText("")
    elseif button._chargeText ~= chargeCount then
        button._chargeText = chargeCount
        button.count:SetText(chargeCount)
    end
end

-- Icon tinting: out-of-range red > unusable dimming > normal white.
-- Shared by icon-mode and bar-mode display paths.
local function UpdateIconTint(button, buttonData, style)
    if buttonData.isPassive then
        if button._vertexR ~= 1 or button._vertexG ~= 1 or button._vertexB ~= 1 then
            button._vertexR, button._vertexG, button._vertexB = 1, 1, 1
            button.icon:SetVertexColor(1, 1, 1)
        end
        return
    end
    local r, g, b = 1, 1, 1
    if style.showOutOfRange then
        if buttonData.type == "spell" then
            if button._spellOutOfRange then
                r, g, b = 1, 0.2, 0.2
            end
        elseif buttonData.type == "item" then
            -- IsItemInRange is protected during combat lockdown; skip range tinting in combat
            if not InCombatLockdown() then
                local inRange = IsItemInRange(buttonData.id, "target")
                -- inRange is nil when no target or item has no range; only tint on explicit false
                if inRange == false then
                    r, g, b = 1, 0.2, 0.2
                end
            end
        end
    end
    if r == 1 and g == 1 and b == 1 and style.showUnusable then
        if buttonData.type == "spell" then
            local isUsable = C_Spell.IsSpellUsable(buttonData.id)
            if not isUsable then
                r, g, b = 0.4, 0.4, 0.4
            end
        elseif buttonData.type == "item" then
            local usable, noMana = IsUsableItem(buttonData.id)
            if not usable then
                r, g, b = 0.4, 0.4, 0.4
            end
        end
    end
    if button._vertexR ~= r or button._vertexG ~= g or button._vertexB ~= b then
        button._vertexR, button._vertexG, button._vertexB = r, g, b
        button.icon:SetVertexColor(r, g, b)
    end
end

-- Exports
ST._UpdateChargeTracking = UpdateChargeTracking
ST._UpdateItemChargeTracking = UpdateItemChargeTracking
ST._UpdateIconTint = UpdateIconTint
