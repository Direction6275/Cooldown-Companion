--[[
    CooldownCompanion - Core/CooldownLogic
    Pure helpers for separating real cooldowns from GCD-only cooldown state.
]]

local _, ST = ...
ST = ST or {}

local CooldownLogic = ST.CooldownLogic or {}

function CooldownLogic.IsSpellGCDOnly(info, options)
    if not info then
        return false
    end

    options = options or {}
    if options.realCooldownShown then
        return false
    end

    local secrecy = options.secrecy or 0
    local gcdInfo = options.gcdInfo
    if secrecy == 0 then
        return gcdInfo ~= nil
            and info.startTime == gcdInfo.startTime
            and info.duration == gcdInfo.duration
    end

    return info.isOnGCD == true and options.gcdActive == true
end

ST.CooldownLogic = CooldownLogic

return CooldownLogic
