-- Resource sounds consume observations from the real bar update, never previews.
local _, ST = ...
local addon, RB = ST.Addon, ST._RB
local Sounds = {}
RB.ResourceSounds = Sounds
local states = {}
local samplingHolder, samplingPower, observedValue, observedMax
local tickSettings, tickSpec, tickAllowed, tickCombat

function Sounds.Supports(powerType)
    return RB.SEGMENTED_TYPES[powerType] == true or powerType == 100
        or RB.AURA_STACK_RESOURCES[powerType] ~= nil
end

local function IsNumber(value)
    return not (issecretvalue and issecretvalue(value))
        and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

function Sounds.IsAmount(value)
    return IsNumber(value) and value >= 1 and value == math.floor(value)
end

-- Reuse the caller's config table; actual resource identity owns these keys,
-- including each half of the Devourer pair (not its canonical placement id).
local function Read(settings, powerType, specID, key, fallback)
    local resource = settings and settings.resources and settings.resources[powerType]
    local value = resource and ST._ResolveSpecOverrideKey(resource, specID, key)
    -- The shared resolver treats a base false as nil; preserve explicit
    -- false for the opt-out Combat Only setting as well as spec overrides.
    if value == nil and type(resource) == "table" then value = resource[key] end
    if value == nil then return fallback end
    return value
end

function Sounds.ReadConfig(settings, powerType, specID, config)
    config = config or {}
    config.enabled = Read(settings, powerType, specID, "resourceSoundEnabled", false) == true
    config.trigger = Read(settings, powerType, specID, "resourceSoundTrigger", "maximum")
    config.amount = Read(settings, powerType, specID, "resourceSoundAmount", 1)
    config.sound = Read(settings, powerType, specID, "resourceSound", "None")
    config.combatOnly = Read(settings, powerType, specID, "resourceSoundCombatOnly", true) ~= false
    return config
end

-- Pure transition rule. Commit the crossing before playback, even if playback
-- fails. Invalid observations forget history rather than acting like zero.
function Sounds.Step(state, config, value, maximum, allowed, identity)
    if not allowed or not config.enabled or config.sound == "None"
        or type(config.sound) ~= "string" or config.sound == ""
        or not IsNumber(value) or value < 0 or not Sounds.IsAmount(maximum)
        or (config.trigger ~= "maximum" and config.trigger ~= "amount") then
        state.initialized = false
        return false
    end
    local threshold = config.trigger == "maximum" and maximum or config.amount
    if not Sounds.IsAmount(threshold) or threshold > maximum then
        state.initialized = false
        return false
    end
    local above = value >= threshold
    local changed = state.identity ~= identity or state.maximum ~= maximum
        or state.trigger ~= config.trigger or state.amount ~= config.amount
        or state.sound ~= config.sound or state.combatOnly ~= config.combatOnly
    local play = state.initialized and not changed and not state.above and above
    state.initialized, state.above = true, above
    state.identity, state.maximum = identity, maximum
    state.trigger, state.amount = config.trigger, config.amount
    state.sound, state.combatOnly = config.sound, config.combatOnly
    return play == true, threshold
end

function Sounds.Reset(powerType)
    if powerType then states[powerType] = nil else wipe(states) end
end

function Sounds.ResetCombat()
    for _, state in pairs(states) do
        if state.config.combatOnly then state.initialized = false end
    end
end

-- Called after materialization as well as after ticks: even a resource that
-- disappears and returns between ticks must not carry an old crossing forward.
function Sounds.RetainFrames(frames)
    for powerType in pairs(states) do
        local found = false
        for _, barInfo in ipairs(frames) do
            if barInfo.powerType == powerType then found = true; break end
        end
        if not found then states[powerType] = nil end
    end
end

function Sounds.BeginTick(settings)
    tickSettings, tickSpec = settings, RB.GetCurrentSpecID()
    tickCombat = InCombatLockdown()
    tickAllowed = settings and settings.enabled and not addon._arrangeModeActive
        and not addon:IsResourceBarUnlockAssistActive()
end

function Sounds.BeginSample(holder, powerType)
    samplingHolder, samplingPower = holder, powerType
    observedValue, observedMax = nil, nil
end

function Sounds.Observe(holder, powerType, value, maximum)
    if holder == samplingHolder and powerType == samplingPower then
        observedValue, observedMax = value, maximum
    end
end

function Sounds.EndSample(holder, powerType)
    samplingHolder, samplingPower = nil, nil
    if not Sounds.Supports(powerType) then return end
    local state = states[powerType]
    if not state then
        state = { config = {} }
        states[powerType] = state
    end
    local config = Sounds.ReadConfig(tickSettings, powerType, tickSpec, state.config)
    if state.spec ~= tickSpec then state.initialized = false; state.spec = tickSpec end
    if not config.enabled or config.sound == "None" then
        state.initialized = false
        return
    end
    local visible = holder and holder:IsVisible()
    local alpha = holder and holder:GetEffectiveAlpha()
    local allowed = tickAllowed and visible and IsNumber(alpha) and alpha > 0
        and (not config.combatOnly or tickCombat)
    local play, threshold = Sounds.Step(state, config, observedValue, observedMax,
        allowed, tickSettings)
    if play then
        addon:PlayResourceSoundAlert(powerType, config.sound, config.trigger, threshold)
    end
end
