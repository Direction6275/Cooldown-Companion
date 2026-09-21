--[[
    CooldownCompanion - Core/BarsAndFramesRuntime.lua
    Bars & Frames runtime gate and panel attachment completion.
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

local function FlagsEqual(a, b)
    return (a and a.resourceBars == true or false) == (b and b.resourceBars == true or false)
        and (a and a.castBar == true or false) == (b and b.castBar == true or false)
        and (a and a.frameAnchoring == true or false) == (b and b.frameAnchoring == true or false)
end

function CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled(feature)
    return runtime.enabled == true and runtime.flags and runtime.flags[feature] == true
end

function CooldownCompanion:RecordBarsAndFramesRuntimeWork(kind)
    kind = tostring(kind or "unknown")
    runtime.counters.work[kind] = (runtime.counters.work[kind] or 0) + 1
end

-- This context lives only for the synchronous operation. Inner panel refreshes,
-- including compact-suppression rebuilds, finish with their outer operation.
-- Native aura binding and its cast-only tail notification retain their own
-- asynchronous lifecycle; neither can request Resources through this context.
local attachmentRefresh
local featureMethods = {
    resourceBars = { evaluate = "EvaluateResourceBars", apply = "ApplyResourceBars" },
    castBar = { evaluate = "EvaluateCastBar", apply = "ApplyCastBarSettings" },
    frameAnchoring = { evaluate = "EvaluateFrameAnchoring", apply = "ApplyFrameAnchoring" },
}

function CooldownCompanion:BeginPanelAttachmentRefresh()
    if attachmentRefresh then return nil end
    attachmentRefresh = { panels = {} }
    return attachmentRefresh
end

local function IncludePanel(groupId, geometryKind, checkResources)
    if not groupId then return end
    local panel = attachmentRefresh.panels[groupId] or {}
    panel.geometryKind = geometryKind or panel.geometryKind
    panel.checkResources = checkResources or panel.checkResources
    attachmentRefresh.panels[groupId] = panel
end

function CooldownCompanion:DeferPanelRangeCheckRefresh()
    if not attachmentRefresh then return false end
    attachmentRefresh.rangeChanged = true
    return true
end

function CooldownCompanion:EndPanelAttachmentRefresh(operation, changed, reason)
    local refresh = attachmentRefresh
    if changed then refresh.full, refresh.rangeChanged = true, true end
    if reason then refresh.reason = reason end
    if operation ~= refresh then return end

    -- Panel construction alone must not start modules before initialization.
    -- Explicit module requests can start them; the shared login settle also
    -- evaluates everything once at the existing 0.5-second boundary.
    local evaluate = refresh.requested or (refresh.full and runtime.initialized)
    local flags = runtime.flags
    if evaluate then
        local previousFlags = flags
        local enabled
        enabled, flags = self:RefreshBarsAndFramesRuntimeGate(refresh.reason)
        local flagsChanged = not FlagsEqual(previousFlags, flags)
        if flagsChanged then refresh.full = true end
        if refresh.full or refresh.frameAnchoring then
            -- This can refresh panels. Keep the operation open until those
            -- frames and their suppression geometry have finished too.
            CallIfAvailable("RefreshStableExternalAnchorCompactSuppression")
        end
        if enabled then
            runtime.counters.evaluate = runtime.counters.evaluate + 1
        else
            runtime.counters.skippedEvaluate = runtime.counters.skippedEvaluate + 1
        end
    end

    local opts = { skipRuntimeGate = true, skipCompactSuppression = true }
    local resourceMethod = evaluate and (refresh.full and "evaluate" or refresh.resourceBars)
    if resourceMethod and flags.resourceBars then
        CallIfAvailable(featureMethods.resourceBars[resourceMethod], opts)
    else
        -- A standalone resize retains the existing fitted-length check. It
        -- never becomes an unconditional resource evaluation.
        for groupId, panel in pairs(refresh.panels) do
            if panel.checkResources and flags.resourceBars then
                CallIfAvailable("RefreshResourceBarAnchorGeometry", groupId)
            end
        end
    end

    -- Resource apply/revert contributes both its old and new host here. Lay
    -- out each once, after Resources has published its final live blocks.
    for groupId, panel in pairs(refresh.panels) do
        local frame = self.groupFrames and self.groupFrames[groupId]
        local group = self.db and self.db.profile.groups[groupId]
        if frame and group and ST.LayoutAttachedBars then
            ST.LayoutAttachedBars(groupId, frame, group, panel.geometryKind)
        end
    end

    local castMethod = evaluate and (refresh.full and "evaluate" or refresh.castBar)
    if castMethod and flags.castBar then
        CallIfAvailable(featureMethods.castBar[castMethod], opts)
    elseif flags.castBar and (refresh.resourceChanged
        or (next(refresh.panels) and refresh.panels[self:GetModuleAnchorPanelId("castbar")])) then
        CallIfAvailable("RepositionCastBar")
    end
    local frameMethod = evaluate and (refresh.full and "evaluate" or refresh.frameAnchoring)
    if frameMethod and flags.frameAnchoring then
        CallIfAvailable(featureMethods.frameAnchoring[frameMethod], opts)
    elseif refresh.frameAnchoring then
        -- A disabled feature can still own protected frames: its combat-end
        -- callback must finish the teardown even though the gate is off.
        CallIfAvailable("RevertFrameAnchoring")
    end
    if evaluate and not flags.resourceBars and not flags.castBar then
        CallIfAvailable("RefreshUnlockToolbar")
    end
    attachmentRefresh = nil
    if refresh.rangeChanged then self:UpdateRangeCheckRegistrations() end
    return evaluate == true and runtime.enabled == true
end

function CooldownCompanion:RefreshPanelAttachmentGeometry(groupId, geometryKind)
    local operation = self:BeginPanelAttachmentRefresh()
    IncludePanel(groupId, geometryKind, true)
    self:EndPanelAttachmentRefresh(operation)
end

function CooldownCompanion:FinishResourceBarLayout(previousPanel, panelId)
    local operation = self:BeginPanelAttachmentRefresh()
    IncludePanel(previousPanel)
    IncludePanel(panelId)
    attachmentRefresh.resourceChanged = true
    self:EndPanelAttachmentRefresh(operation)
end

function CooldownCompanion:RefreshBarsAndFramesRuntimeFeature(feature, reason, applyOnly)
    local operation = self:BeginPanelAttachmentRefresh()
    local refresh = attachmentRefresh
    refresh.requested = true
    -- An evaluate also owns feature lifecycle activation; an apply cannot
    -- replace one that the same operation already requested.
    if not applyOnly or not refresh[feature] then
        refresh[feature] = applyOnly and "apply" or "evaluate"
    end
    if feature == "resourceBars" then refresh.castBar = "evaluate" end
    return self:EndPanelAttachmentRefresh(operation, false, reason)
end

function CooldownCompanion:EvaluateBarsAndFramesRuntime(reason)
    local operation = self:BeginPanelAttachmentRefresh()
    attachmentRefresh.requested = true
    return self:EndPanelAttachmentRefresh(operation, true, reason)
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
        moduleAnchoring = CallIfAvailable("GetModuleAnchoringDebugInfo"),
    }
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(0.5, function()
        CooldownCompanion:EvaluateBarsAndFramesRuntime("bars-and-frames-init")
    end)
end)
