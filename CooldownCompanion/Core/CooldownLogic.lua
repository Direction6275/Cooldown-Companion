--[[
    CooldownCompanion - Core/CooldownLogic
    Pure helpers for separating real cooldown availability from GCD presentation.
]]

local _, ST = ...
ST = ST or {}

local CooldownLogic = ST.CooldownLogic or {}

CooldownLogic.STATE_READY = "ready"
-- Presentation-only legacy label; GCD must not be treated as cooldown availability.
CooldownLogic.STATE_GCD = "gcd"
CooldownLogic.STATE_COOLDOWN = "cooldown"

CooldownLogic.CHARGE_STATE_FULL = "full"
CooldownLogic.CHARGE_STATE_MISSING = "missing"
CooldownLogic.CHARGE_STATE_ZERO = "zero"

function CooldownLogic.IsSpellGCDOnly(info, normalCooldownShown, realCooldownShown)
    if not info then
        return false
    end

    if realCooldownShown or not normalCooldownShown then
        return false
    end

    if info.isActive ~= true then
        return false
    end

    return info.isOnGCD == true
end

function CooldownLogic.IsItemGCDOnly(cdStart, cdDuration, gcdInfo)
    return (cdDuration and cdDuration > 0
        and gcdInfo ~= nil
        and cdStart == gcdInfo.startTime
        and cdDuration == gcdInfo.duration) == true
end

ST.CooldownLogic = CooldownLogic

return CooldownLogic
