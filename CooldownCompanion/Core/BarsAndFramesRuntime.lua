--[[
    CooldownCompanion - Core/BarsAndFramesRuntime.lua
    Derived CPU gate for Bars & Frames runtime work.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local runtime = {
    initialized = false,
    enabled = false,
    generation = 0,
    lastReason = nil,
    flags = {
        resourceBars = false,
        castBar = false,
        frameAnchoring = false,
    },
    counters = {
        refresh = 0,
        activate = 0,
        deactivate = 0,
        evaluate = 0,
        skippedEvaluate = 0,
        work = {},
    },
}

local function SettingEnabled(getterName)
    local getter = CooldownCompanion[getterName]
    if type(getter) ~= "function" then
        return false
    end

    local settings = getter(CooldownCompanion)
    return type(settings) == "table" and settings.enabled == true
end

local function ComputeFlags()
    local flags = {
        resourceBars = SettingEnabled("GetResourceBarSettings"),
        castBar = SettingEnabled("GetCastBarSettings"),
        frameAnchoring = SettingEnabled("GetFrameAnchoringSettings"),
    }

    return flags, flags.resourceBars or flags.castBar or flags.frameAnchoring
end

local function CopyFlags(flags)
    return {
        resourceBars = flags and flags.resourceBars == true or false,
        castBar = flags and flags.castBar == true or false,
        frameAnchoring = flags and flags.frameAnchoring == true or false,
    }
end

local function CallIfAvailable(methodName, ...)
    local method = CooldownCompanion[methodName]
    if type(method) == "function" then
        return method(CooldownCompanion, ...)
    end
end

local function DeactivateRuntime()
    CallIfAvailable("DisableResourceBarRuntime")
    CallIfAvailable("RevertCastBar")
    CallIfAvailable("RevertFrameAnchoring")
end

local function DeactivateDisabledFeatures(previousFlags, flags)
    if previousFlags.resourceBars and not flags.resourceBars then
        CallIfAvailable("DisableResourceBarRuntime")
    end
    if previousFlags.castBar and not flags.castBar then
        CallIfAvailable("RevertCastBar")
    end
    if previousFlags.frameAnchoring and not flags.frameAnchoring then
        CallIfAvailable("RevertFrameAnchoring")
    end
end

function CooldownCompanion:RefreshBarsAndFramesRuntimeGate(reason)
    runtime.counters.refresh = runtime.counters.refresh + 1

    local flags, enabled = ComputeFlags()
    local wasInitialized = runtime.initialized == true
    local changed = (not wasInitialized) or runtime.enabled ~= enabled
    local previousFlags = runtime.flags

    runtime.initialized = true
    runtime.lastReason = reason or runtime.lastReason
    runtime.flags = CopyFlags(flags)
    runtime.enabled = enabled

    if changed then
        runtime.generation = runtime.generation + 1
        if enabled then
            runtime.counters.activate = runtime.counters.activate + 1
        elseif wasInitialized then
            runtime.counters.deactivate = runtime.counters.deactivate + 1
            DeactivateRuntime()
        end
    end
    if wasInitialized and enabled then
        DeactivateDisabledFeatures(previousFlags, flags)
    end

    return runtime.enabled, runtime.flags
end

function CooldownCompanion:RefreshBarsAndFramesRuntimeFeatureGate(feature, reason)
    local enabled, flags = self:RefreshBarsAndFramesRuntimeGate(reason)
    local featureEnabled = enabled == true and flags and flags[feature] == true or false
    if featureEnabled then
        CallIfAvailable("NormalizeCurrentStableExternalAnchorCompactLayout")
    end
    return featureEnabled, flags
end

function CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled(feature)
    return runtime.enabled == true and runtime.flags and runtime.flags[feature] == true
end

function CooldownCompanion:RecordBarsAndFramesRuntimeWork(kind)
    kind = tostring(kind or "unknown")
    runtime.counters.work[kind] = (runtime.counters.work[kind] or 0) + 1
end

function CooldownCompanion:EvaluateBarsAndFramesRuntime(reason)
    local enabled, flags = self:RefreshBarsAndFramesRuntimeGate(reason)
    if not enabled then
        runtime.counters.skippedEvaluate = runtime.counters.skippedEvaluate + 1
        return false
    end

    runtime.counters.evaluate = runtime.counters.evaluate + 1
    CallIfAvailable("NormalizeCurrentStableExternalAnchorCompactLayout")
    local opts = { skipRuntimeGate = true }

    if flags.resourceBars then
        CallIfAvailable("EvaluateResourceBars", opts)
    end

    if flags.castBar then
        CallIfAvailable("EvaluateCastBar", opts)
    end

    if flags.frameAnchoring then
        CallIfAvailable("EvaluateFrameAnchoring", opts)
    end

    return true
end

function CooldownCompanion:EvaluateBarsAndFramesStackingRuntime(reason)
    local enabled, flags = self:RefreshBarsAndFramesRuntimeGate(reason)
    if not enabled or not (flags.resourceBars or flags.castBar) then
        runtime.counters.skippedEvaluate = runtime.counters.skippedEvaluate + 1
        return false
    end

    runtime.counters.evaluate = runtime.counters.evaluate + 1
    CallIfAvailable("NormalizeCurrentStableExternalAnchorCompactLayout")
    local opts = { skipRuntimeGate = true }

    if flags.resourceBars then
        CallIfAvailable("EvaluateResourceBars", opts)
    end

    if flags.castBar then
        CallIfAvailable("EvaluateCastBar", opts)
    end

    return true
end

function CooldownCompanion:GetBarsAndFramesRuntimeDebugInfo()
    return {
        initialized = runtime.initialized == true,
        enabled = runtime.enabled == true,
        generation = runtime.generation,
        lastReason = runtime.lastReason,
        flags = CopyFlags(runtime.flags),
        counters = {
            refresh = runtime.counters.refresh,
            activate = runtime.counters.activate,
            deactivate = runtime.counters.deactivate,
            evaluate = runtime.counters.evaluate,
            skippedEvaluate = runtime.counters.skippedEvaluate,
            work = CopyTable(runtime.counters.work),
        },
        resourceBars = CallIfAvailable("GetResourceBarRuntimeState"),
        castBar = CallIfAvailable("GetCastBarRuntimeDebugInfo"),
        frameAnchoring = CallIfAvailable("GetFrameAnchoringRuntimeDebugInfo"),
    }
end
