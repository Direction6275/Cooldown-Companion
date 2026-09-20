--[[
    CooldownCompanion - FrameAnchoring
    Anchors player and target unit frames (Blizzard, ElvUI, EllesmereUI,
    UnhaltedUnitFrames, Midnight Simple Unit Frames, or custom) to icon groups.

    Some unit frame addons (e.g., UnhaltedUnitFrames) use secure templates,
    making their frames protected during combat. All positioning (SetPoint/
    ClearAllPoints) is guarded by InCombatLockdown() and deferred to
    PLAYER_REGEN_ENABLED. Alpha sync continues during combat (SetAlpha is
    not a protected operation).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local issecretvalue = issecretvalue

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local isApplied = false
local hooksInstalled = false
local frames = { player = {}, target = {} }
local alphaSyncFrame = nil
local pendingReevaluate = false
local rapidAlphaSyncUntil = 0
local alphaHookGuards = setmetatable({}, { __mode = "k" })
local alphaSetHooksInstalled = setmetatable({}, { __mode = "k" })
local anchorWriteGuards = setmetatable({}, { __mode = "k" })
local anchorWriteHooksInstalled = setmetatable({}, { __mode = "k" })
local externalAnchorRepairQueued = false
local externalAnchorRepairCount = 0
local lastResolvedProvider = nil
local lastPlayerPanelId, lastTargetPanelId
local lastEvaluationSpecId
local lastPlayerFrameName = nil
local lastTargetFrameName = nil
local InstallHooks

-- Combat deferral: any positioning attempt during combat is coalesced into a
-- single full re-evaluation once PLAYER_REGEN_ENABLED fires.
local combatDeferFrame = CreateFrame("Frame")
combatDeferFrame:SetScript("OnEvent", function(self, event)
    -- Clean up BEFORE evaluating so an error doesn't leave the event
    -- registered or the flag stuck.
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    pendingReevaluate = false
    CooldownCompanion:EvaluateFrameAnchoring()
end)

local function DeferForCombat()
    if pendingReevaluate then return end
    pendingReevaluate = true
    combatDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

local UNIT_FRAME_PROVIDERS = {
    blizzard = { player = "PlayerFrame",  target = "TargetFrame" },
    uuf      = { player = "UUF_Player",   target = "UUF_Target" },
    elvui    = { player = "ElvUF_Player",  target = "ElvUF_Target" },
    ellesmere = {
        families = {
            { player = "EllesmereUIUnitFrames_Player",  target = "EllesmereUIUnitFrames_Target" },
            { player = "EUIStandaloneUnitFrames_Player", target = "EUIStandaloneUnitFrames_Target" },
        },
    },
    msuf     = { player = "MSUF_player",  target = "MSUF_target" },
}

local MIRROR_POINTS = {
    LEFT         = "RIGHT",
    RIGHT        = "LEFT",
    TOPLEFT      = "TOPRIGHT",
    TOPRIGHT     = "TOPLEFT",
    BOTTOMLEFT   = "BOTTOMRIGHT",
    BOTTOMRIGHT  = "BOTTOMLEFT",
    TOP          = "TOP",
    BOTTOM       = "BOTTOM",
    CENTER       = "CENTER",
}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function GetFrameAnchoringSettings()
    return CooldownCompanion:GetFrameAnchoringSettings()
end

local function GetInheritedUnitFrameAlpha(groupFrame)
    if not groupFrame or not groupFrame:IsShown() then return nil end

    local alpha = groupFrame._naturalAlpha
    if alpha ~= nil then
        return alpha
    end

    alpha = groupFrame:GetEffectiveAlpha()
    if issecretvalue(alpha) or alpha == nil then
        return nil
    end

    return alpha
end

local function SetUnitFrameAlphaGuarded(frame, alpha)
    if not frame or alpha == nil then return end
    alphaHookGuards[frame] = true
    frame:SetAlpha(alpha)
    alphaHookGuards[frame] = nil
end

local function ResyncInheritedUnitFrameAlpha(force, latest)
    latest = latest or GetFrameAnchoringSettings()
    if not (isApplied and latest and latest.enabled and latest.inheritAlpha) then return end
    for _, state in pairs(frames) do
        if state.frame and state.anchor then
            local alpha = GetInheritedUnitFrameAlpha(state.panel)
            if alpha ~= nil and (force or alpha ~= state.lastAlpha) then
                SetUnitFrameAlphaGuarded(state.frame, alpha)
                state.lastAlpha = alpha
            end
        end
    end
end

local function QueueInheritedUnitFrameAlphaResync()
    if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end
    local latest = GetFrameAnchoringSettings()
    if not (isApplied and latest and latest.enabled and latest.inheritAlpha) then return end

    local now = GetTime()
    local wasRapidSyncActive = now < rapidAlphaSyncUntil
    rapidAlphaSyncUntil = now + 0.2

    if wasRapidSyncActive then return end

    ResyncInheritedUnitFrameAlpha(true)
    C_Timer.After(0, function()
        if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end
        ResyncInheritedUnitFrameAlpha(true)
    end)
end

ST._QueueInheritedUnitFrameAlphaResync = QueueInheritedUnitFrameAlphaResync

local function CaptureRestorableAlpha(frame)
    if not frame then return nil end

    local alpha = frame:GetAlpha()
    if issecretvalue(alpha) or alpha == nil then
        return nil
    end

    return alpha
end

local function InstallInheritedAlphaSetHook(frame)
    if not frame or alphaSetHooksInstalled[frame] then return end

    hooksecurefunc(frame, "SetAlpha", function(self)
        if alphaHookGuards[self] then return end

        local settings = GetFrameAnchoringSettings()
        if not (isApplied and settings and settings.enabled and settings.inheritAlpha) then return end
        if self ~= frames.player.frame and self ~= frames.target.frame then return end

        QueueInheritedUnitFrameAlphaResync()
    end)

    alphaSetHooksInstalled[frame] = true
end

local function ResolveUnitFrameFamily(family)
    if not family then
        return nil, nil
    end
    return _G[family.player], _G[family.target]
end

local function IsAutoDetectableUnitFrame(frame)
    if not frame then
        return false
    end

    if frame.GetAttribute then
        local unit = frame:GetAttribute("unit")
        if issecretvalue(unit) then
            return false
        end
        if type(unit) == "string" and unit ~= "" then
            return true
        end
    end

    if frame.IsShown then
        local shown = frame:IsShown()
        if issecretvalue(shown) then
            return false
        end
        return shown == true
    end

    return false
end

local function HasAutoDetectableUnitFrame(playerFrame, targetFrame)
    return IsAutoDetectableUnitFrame(playerFrame) or IsAutoDetectableUnitFrame(targetFrame)
end

local function ResolveUnitFrameProvider(provider, options)
    if not provider then
        return nil, nil
    end
    options = options or {}

    local families = provider.families
    if type(families) == "table" then
        local fallbackPlayerFrame, fallbackTargetFrame
        for _, family in ipairs(families) do
            local playerFrame, targetFrame = ResolveUnitFrameFamily(family)
            if playerFrame or targetFrame then
                if not fallbackPlayerFrame and not fallbackTargetFrame then
                    fallbackPlayerFrame, fallbackTargetFrame = playerFrame, targetFrame
                end
                if HasAutoDetectableUnitFrame(playerFrame, targetFrame) then
                    return playerFrame, targetFrame
                end
            end
        end
        if not options.requireAutoDetectable then
            return fallbackPlayerFrame, fallbackTargetFrame
        end
        return nil, nil
    end

    local playerFrame, targetFrame = ResolveUnitFrameFamily(provider)
    if options.requireAutoDetectable and not HasAutoDetectableUnitFrame(playerFrame, targetFrame) then
        return nil, nil
    end
    return playerFrame, targetFrame
end

--- Auto-detect which unit frame addon is active.
local function AutoDetectUnitFrameAddon()
    local ellesmerePlayerFrame, ellesmereTargetFrame = ResolveUnitFrameProvider(
        UNIT_FRAME_PROVIDERS.ellesmere,
        { requireAutoDetectable = true }
    )
    if ellesmerePlayerFrame or ellesmereTargetFrame then
        return "ellesmere"
    end
    if _G["ElvUF_Player"] then return "elvui" end
    if _G["UUF_Player"] then return "uuf" end
    if _G["MSUF_player"] then return "msuf" end
    return "blizzard"
end

local function ResolveCustomUnitFrame(frameName)
    if not frameName or frameName == "" then
        return nil
    end
    local ok = CooldownCompanion:ValidateAddonFrameAnchorTarget(frameName, {
        domain = "external",
    })
    if not ok then
        return nil
    end
    return _G[frameName]
end

--- Resolve the actual player and target frame references.
local function GetUnitFrames(settings)
    local addon = settings.unitFrameAddon
    if not addon or addon == "" then
        addon = AutoDetectUnitFrameAddon()
    end

    local playerFrame, targetFrame

    if addon == "custom" then
        local pName = settings.customPlayerFrame
        local tName = settings.customTargetFrame
        playerFrame = ResolveCustomUnitFrame(pName)
        targetFrame = ResolveCustomUnitFrame(tName)
    elseif addon == "msuf" then
        local unitFrames = _G["MSUF_UnitFrames"]
        playerFrame = _G["MSUF_player"] or (unitFrames and unitFrames.player)
        targetFrame = _G["MSUF_target"] or (unitFrames and unitFrames.target)
    else
        local provider = UNIT_FRAME_PROVIDERS[addon]
        if provider then
            playerFrame, targetFrame = ResolveUnitFrameProvider(provider)
        end
    end

    return playerFrame, targetFrame, addon
end

------------------------------------------------------------------------
-- Anchor save/restore
------------------------------------------------------------------------

local function SaveFrameAnchors(frame)
    if not frame then return nil end
    local anchors = {}
    local n = frame:GetNumPoints()
    for i = 1, n do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
        anchors[i] = { point = point, relativeTo = relativeTo,
                        relativePoint = relativePoint, x = x, y = y }
    end
    return anchors
end

local function RestoreFrameAnchors(frame, anchors)
    if not frame or not anchors then return end
    anchorWriteGuards[frame] = true
    frame:ClearAllPoints()
    for _, a in ipairs(anchors) do
        frame:SetPoint(a.point, a.relativeTo, a.relativePoint, a.x, a.y)
    end
    anchorWriteGuards[frame] = nil
end

local function SetManagedFrameAnchor(frame, point, relativeTo, relativePoint, x, y)
    if not frame then return end
    anchorWriteGuards[frame] = true
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
    anchorWriteGuards[frame] = nil
end

local function GetFrameDebugName(frame, fallback)
    if not frame then return nil end
    local name = frame.GetName and frame:GetName()
    if issecretvalue(name) then return fallback end
    if name and name ~= "" then
        return name
    end
    return fallback
end

local function QueueExternalAnchorRepair(frame)
    if anchorWriteGuards[frame] then return end
    if not isApplied or (frame ~= frames.player.frame and frame ~= frames.target.frame) then return end
    if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end

    local settings = GetFrameAnchoringSettings()
    if not (settings and settings.enabled) then return end

    -- Same-frame reclaim: replay the exact anchor Apply last wrote, so the
    -- render this write lands on never shows the provider's position (the
    -- one-frame "blink" a next-frame-only repair leaves behind). Runs on every
    -- external write — the provider's own layout pass can touch the frame
    -- several times and the last write before render must be ours. The write
    -- guard inside SetManagedFrameAnchor keeps this invisible to these hooks.
    --
    -- Blizzard Edit Mode deliberately clears every system frame before writing
    -- its temporary layout anchor. Reclaiming between those two writes can make
    -- PlayerFrame's next SetPoint form an invalid anchor-family connection. Let
    -- that atomic layout pass finish; the deferred full re-evaluate below then
    -- re-resolves the anchor group and reclaims the frame on the next turn.
    local editModeManager = _G.EditModeManagerFrame
    local editModeLayoutApplyInProgress = editModeManager
        and editModeManager.layoutApplyInProgress == true
    if not editModeLayoutApplyInProgress and not InCombatLockdown() then
        local spec
        if frame == frames.player.frame then
            spec = frames.player.anchor
        else
            spec = frames.target.anchor
        end
        if spec then
            SetManagedFrameAnchor(frame, spec.point, spec.body, spec.relativePoint, spec.x, spec.y)
        end
    end

    if pendingReevaluate or externalAnchorRepairQueued then return end

    externalAnchorRepairQueued = true
    externalAnchorRepairCount = externalAnchorRepairCount + 1
    C_Timer.After(0, function()
        externalAnchorRepairQueued = false
        if not isApplied then return end
        if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end

        local latest = GetFrameAnchoringSettings()
        if not (latest and latest.enabled) then return end
        CooldownCompanion:EvaluateFrameAnchoring({ reason = "unit-frame-anchor-overwritten" })
    end)
end

local function InstallAnchorWriteHooks(frame)
    if not frame or anchorWriteHooksInstalled[frame] then return end

    -- Unit-frame providers can run delayed layout passes after login and take
    -- their points back. Observe those writes instead of polling GetPoint
    -- (which can expose secret anchor data): reclaim ownership same-frame with
    -- the cached applied spec so the provider's position never renders, and
    -- follow with a full next-frame re-evaluate as the authoritative repair.
    -- The guard makes CC's own apply/restore writes invisible to this repair.
    hooksecurefunc(frame, "ClearAllPoints", function(self)
        QueueExternalAnchorRepair(self)
    end)
    hooksecurefunc(frame, "SetPoint", function(self)
        QueueExternalAnchorRepair(self)
    end)
    anchorWriteHooksInstalled[frame] = true
end

local function WouldFrameDependOn(sourceFrame, dependencyFrame, visited, depth, proposed)
    if not sourceFrame or not dependencyFrame then return false end
    if sourceFrame == dependencyFrame then return true end

    depth = depth or 0
    if depth > 24 then return true end

    visited = visited or {}
    if visited[sourceFrame] then return false end
    visited[sourceFrame] = true
    if proposed and proposed[sourceFrame] then
        for _, relative in ipairs(proposed[sourceFrame]) do
            if issecretvalue(relative)
                or WouldFrameDependOn(relative, dependencyFrame, visited, depth + 1, proposed) then return true end
        end
        return false
    end

    local pointIndex = 1
    while true do
        local point, relativeFrame = sourceFrame:GetPoint(pointIndex)
        if issecretvalue(point) or issecretvalue(relativeFrame) then return true end
        if not point then break end
        if relativeFrame == dependencyFrame then
            return true
        end
        if relativeFrame
            and relativeFrame ~= sourceFrame
            and relativeFrame.GetPoint
            and WouldFrameDependOn(relativeFrame, dependencyFrame, visited, depth + 1, proposed) then
            return true
        end
        pointIndex = pointIndex + 1
    end

    return false
end

local function RestoreManagedFrame(state)
    if state.frame then
        if state.savedAlpha ~= nil then SetUnitFrameAlphaGuarded(state.frame, state.savedAlpha) end
        RestoreFrameAnchors(state.frame, state.savedAnchors)
    end
    for key in pairs(state) do state[key] = nil end
end

local function ConfigureManagedFrame(state, frame, target, position, mirror, inheritAlpha)
    if state.frame and (state.frame ~= frame or not target.available) then RestoreManagedFrame(state) end
    state.reason = target.reason
    if not frame or not target.available then
        if not frame then state.reason = "provider-unavailable" end
        return
    end
    if not state.frame then
        state.savedAnchors = SaveFrameAnchors(frame)
        state.frame = frame
    end
    state.panel = target.frame
    state.panelId = target.panelId
    local point, relativePoint = position.anchorPoint, position.relativePoint
    local x, y = position.xOffset or 0, position.yOffset or 0
    if mirror then
        point, relativePoint = MIRROR_POINTS[point] or point, MIRROR_POINTS[relativePoint] or relativePoint
        x = -x
    end
    state.anchor = { point = point, body = ST.GetPanelAnchorBodyFrame(target.frame),
        relativePoint = relativePoint, x = x, y = y }
    InstallAnchorWriteHooks(frame)
    InstallInheritedAlphaSetHook(frame)
    if inheritAlpha then
        if not state.savedAlphaAttempted then
            state.savedAlpha = CaptureRestorableAlpha(frame)
            state.savedAlphaAttempted = true
        end
    else
        if state.savedAlpha ~= nil then SetUnitFrameAlphaGuarded(frame, state.savedAlpha) end
        state.savedAlpha, state.savedAlphaAttempted, state.lastAlpha = nil, nil, nil
    end
end

local function ProposedFrameDependencies(playerFrame, playerTarget, targetFrame, targetTarget)
    local proposed = {}
    -- Losing a target restores provider anchors. Include those edges too:
    -- the surviving attachment must not form a cycle through the restoration.
    for _, state in pairs(frames) do
        if state.frame then
            local edges = {}
            for _, anchor in ipairs(state.savedAnchors or {}) do edges[#edges + 1] = anchor.relativeTo end
            proposed[state.frame] = edges
        end
    end
    if playerFrame and playerTarget.available then proposed[playerFrame] = { playerTarget.frame } end
    if targetFrame and targetTarget.available then proposed[targetFrame] = { targetTarget.frame } end
    return proposed
end

------------------------------------------------------------------------
-- Apply
------------------------------------------------------------------------

function CooldownCompanion:ApplyFrameAnchoring(opts)
    opts = opts or {}
    if not opts.skipRuntimeGate then
        return self:RefreshBarsAndFramesRuntimeFeature("frameAnchoring", "frame-anchoring-apply", true)
    end
    if self.RecordBarsAndFramesRuntimeWork then
        self:RecordBarsAndFramesRuntimeWork("frameApply")
    end

    if InCombatLockdown() then
        DeferForCombat()
        return
    end

    local settings = GetFrameAnchoringSettings()
    if not settings or not settings.enabled then
        self:RevertFrameAnchoring()
        return
    end
    InstallHooks()

    local playerFrame, targetFrame, provider = GetUnitFrames(settings)
    local playerTarget, targetTarget = self:ResolveModulePanel("player"), self:ResolveModulePanel("target")
    for _ = 1, 2 do
        local proposed = ProposedFrameDependencies(playerFrame, playerTarget, targetFrame, targetTarget)
        local playerCycle = playerFrame and playerTarget.available
            and WouldFrameDependOn(playerTarget.frame, playerFrame, nil, nil, proposed)
        local targetCycle = targetFrame and targetTarget.available
            and WouldFrameDependOn(targetTarget.frame, targetFrame, nil, nil, proposed)
        if playerFrame and playerFrame == targetFrame then playerCycle, targetCycle = true, true end
        if playerCycle then playerTarget.available, playerTarget.reason = false, "anchor-dependency" end
        if targetCycle then targetTarget.available, targetTarget.reason = false, "anchor-dependency" end
        if not playerCycle and not targetCycle then break end
    end

    -- Clear old managed edges before restoring either provider or installing
    -- new edges. A provider change may even exchange the player/target frames.
    local cleared = {}
    for _, state in pairs(frames) do
        if state.frame then
            anchorWriteGuards[state.frame] = true
            state.frame:ClearAllPoints()
            anchorWriteGuards[state.frame] = nil
            cleared[state.frame] = true
        end
    end
    if frames.player.frame and (frames.player.frame ~= playerFrame or not playerTarget.available) then
        local restored = frames.player.frame
        RestoreManagedFrame(frames.player)
        cleared[restored] = nil
    end
    if frames.target.frame and (frames.target.frame ~= targetFrame or not targetTarget.available) then
        local restored = frames.target.frame
        RestoreManagedFrame(frames.target)
        cleared[restored] = nil
    end

    ConfigureManagedFrame(frames.player, playerFrame, playerTarget, settings.player, false, settings.inheritAlpha)
    ConfigureManagedFrame(frames.target, targetFrame, targetTarget,
        settings.mirroring and settings.player or settings.target, settings.mirroring, settings.inheritAlpha)

    for _, state in pairs(frames) do
        if state.frame and state.anchor and not cleared[state.frame] then
            anchorWriteGuards[state.frame] = true
            state.frame:ClearAllPoints()
            anchorWriteGuards[state.frame] = nil
        end
    end
    for _, state in pairs(frames) do
        local a = state.anchor
        if state.frame and a then
            anchorWriteGuards[state.frame] = true
            state.frame:SetPoint(a.point, a.body, a.relativePoint, a.x, a.y)
            anchorWriteGuards[state.frame] = nil
        end
    end
    isApplied = frames.player.frame ~= nil or frames.target.frame ~= nil
    lastResolvedProvider = provider
    lastEvaluationSpecId = self._currentSpecId
    lastPlayerPanelId, lastTargetPanelId = playerTarget.panelId, targetTarget.panelId
    lastPlayerFrameName = GetFrameDebugName(playerFrame, settings.customPlayerFrame)
    lastTargetFrameName = GetFrameDebugName(targetFrame, settings.customTargetFrame)

    if settings.inheritAlpha and isApplied then
        ResyncInheritedUnitFrameAlpha(true)
        if not alphaSyncFrame then alphaSyncFrame = CreateFrame("Frame") end
        local accumulator = 0
        alphaSyncFrame:SetScript("OnUpdate", function(_, dt)
            local rapid = rapidAlphaSyncUntil ~= 0 and GetTime() < rapidAlphaSyncUntil
            if not rapid then rapidAlphaSyncUntil = 0 end
            accumulator = accumulator + dt
            if not rapid and accumulator < 1 / 30 then return end
            accumulator = 0
            ResyncInheritedUnitFrameAlpha(rapid, settings)
        end)
    elseif alphaSyncFrame then
        alphaSyncFrame:SetScript("OnUpdate", nil)
        rapidAlphaSyncUntil = 0
    end
end

------------------------------------------------------------------------
-- Revert
------------------------------------------------------------------------

function CooldownCompanion:RevertFrameAnchoring()
    if not isApplied then return end

    if InCombatLockdown() then
        DeferForCombat()
        return
    end

    isApplied = false
    if alphaSyncFrame then alphaSyncFrame:SetScript("OnUpdate", nil) end
    rapidAlphaSyncUntil = 0
    for _, state in pairs(frames) do
        if state.frame then
            anchorWriteGuards[state.frame] = true
            state.frame:ClearAllPoints()
            anchorWriteGuards[state.frame] = nil
        end
    end
    RestoreManagedFrame(frames.player)
    RestoreManagedFrame(frames.target)
end

------------------------------------------------------------------------
-- Evaluate
------------------------------------------------------------------------

function CooldownCompanion:EvaluateFrameAnchoring(opts)
    opts = opts or {}
    if not opts.skipRuntimeGate then
        return self:RefreshBarsAndFramesRuntimeFeature("frameAnchoring", opts.reason or "frame-anchoring-evaluate")
    end
    -- Direct internal callers retain suppression refresh; the completion
    -- owner has already settled it before evaluating any of the modules.
    if not opts.skipCompactSuppression and self.RefreshStableExternalAnchorCompactSuppression then
        self:RefreshStableExternalAnchorCompactSuppression()
    end
    if self.RecordBarsAndFramesRuntimeWork then
        self:RecordBarsAndFramesRuntimeWork("frameEvaluate")
    end

    if InCombatLockdown() then
        DeferForCombat()
        return
    end

    local settings = GetFrameAnchoringSettings()
    if not settings or not settings.enabled then
        self:RevertFrameAnchoring()
        return
    end
    InstallHooks()
    self:ApplyFrameAnchoring({ skipRuntimeGate = true })
end

function CooldownCompanion:GetFrameAnchoringRuntimeDebugInfo()
    return {
        applied = isApplied == true,
        hooksInstalled = hooksInstalled == true,
        alphaSyncActive = alphaSyncFrame and alphaSyncFrame:GetScript("OnUpdate") ~= nil or false,
        pendingCombatReevaluate = pendingReevaluate == true,
        pendingExternalAnchorRepair = externalAnchorRepairQueued == true,
        externalAnchorRepairCount = externalAnchorRepairCount,
        resolvedProvider = lastResolvedProvider,
        specId = lastEvaluationSpecId,
        anchorGroupId = lastPlayerPanelId,
        playerPanelId = lastPlayerPanelId,
        targetPanelId = lastTargetPanelId,
        playerReason = frames.player.reason,
        targetReason = frames.target.reason,
        playerApplied = frames.player.anchor ~= nil,
        targetApplied = frames.target.anchor ~= nil,
        playerFrameName = lastPlayerFrameName,
        targetFrameName = lastTargetFrameName,
    }
end

------------------------------------------------------------------------
-- Hooks (same pattern as CastBar / ResourceBar)
------------------------------------------------------------------------

InstallHooks = function()
    if hooksInstalled then return end
    hooksInstalled = true

    hooksecurefunc(CooldownCompanion, "OnTargetChanged", function()
        if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end
        local s = GetFrameAnchoringSettings()
        if not (isApplied and s and s.enabled and s.inheritAlpha) then return end
        QueueInheritedUnitFrameAlphaResync()
    end)
end
