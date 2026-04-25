--[[
    CooldownCompanion - Core/CooldownLogic
    Pure helpers for separating real cooldowns from GCD-only cooldown state.
]]

local _, ST = ...
ST = ST or {}

local CooldownLogic = ST.CooldownLogic or {}

CooldownLogic.STATE_READY = "ready"
CooldownLogic.STATE_GCD = "gcd"
CooldownLogic.STATE_COOLDOWN = "cooldown"

CooldownLogic.CHARGE_STATE_FULL = "full"
CooldownLogic.CHARGE_STATE_MISSING = "missing"
CooldownLogic.CHARGE_STATE_ZERO = "zero"

local COOLDOWN_STATE_PRIORITY = {
    [CooldownLogic.STATE_READY] = 1,
    [CooldownLogic.STATE_GCD] = 2,
    [CooldownLogic.STATE_COOLDOWN] = 3,
}

function CooldownLogic.GetCooldownStatePriority(state)
    return COOLDOWN_STATE_PRIORITY[state] or 0
end

function CooldownLogic.SelectStrongerCooldownState(a, b)
    if CooldownLogic.GetCooldownStatePriority(b and b.state) >
            CooldownLogic.GetCooldownStatePriority(a and a.state) then
        return b
    end
    return a
end

function CooldownLogic.IsRealCooldownState(state)
    return state == CooldownLogic.STATE_COOLDOWN
end

function CooldownLogic.IsSpellGCDOnly(info, options)
    if not info then
        return false
    end

    options = options or {}
    if options.realCooldownShown or not options.normalCooldownShown then
        return false
    end

    if info.isActive ~= true then
        return false
    end

    return info.isOnGCD == true
end

function CooldownLogic.IsItemGCDOnly(cdStart, cdDuration, gcdInfo)
    return cdDuration and cdDuration > 0
        and gcdInfo ~= nil
        and cdStart == gcdInfo.startTime
        and cdDuration == gcdInfo.duration
end

ST.CooldownLogic = CooldownLogic

return CooldownLogic
