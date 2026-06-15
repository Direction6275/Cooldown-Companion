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
local savedPlayerAnchors = nil   -- array of {point, relativeTo, relativePoint, x, y}
local savedTargetAnchors = nil
local savedPlayerAlpha = nil
local savedTargetAlpha = nil
local savedPlayerAlphaAttempted = false
local savedTargetAlphaAttempted = false
local playerFrameRef = nil
local targetFrameRef = nil
local alphaSyncFrame = nil
local pendingReevaluate = false
local rapidAlphaSyncUntil = 0
local alphaHookGuards = setmetatable({}, { __mode = "k" })
local alphaSetHooksInstalled = setmetatable({}, { __mode = "k" })
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

local function GetEffectiveAnchorGroupId(settings)
    if not settings then return nil end
    return CooldownCompanion:GetFirstAvailableAnchorGroup()
end

local function GetAnchorGroupFrame(settings)
    local groupId = GetEffectiveAnchorGroupId(settings)
    if not groupId then return nil end
    return CooldownCompanion.groupFrames[groupId]
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

local function SyncInheritedUnitFrameAlpha(groupFrame, playerFrame, targetFrame)
    local alpha = GetInheritedUnitFrameAlpha(groupFrame)
    if alpha == nil then return nil end
    if playerFrame then SetUnitFrameAlphaGuarded(playerFrame, alpha) end
    if targetFrame then SetUnitFrameAlphaGuarded(targetFrame, alpha) end
    return alpha
end

local function ResyncInheritedUnitFrameAlpha()
    local latest = GetFrameAnchoringSettings()
    if not (isApplied and latest and latest.enabled and latest.inheritAlpha) then return nil end
    local groupFrame = GetAnchorGroupFrame(latest)
    return SyncInheritedUnitFrameAlpha(groupFrame, playerFrameRef, targetFrameRef)
end

local function QueueInheritedUnitFrameAlphaResync()
    if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end
    local latest = GetFrameAnchoringSettings()
    if not (isApplied and latest and latest.enabled and latest.inheritAlpha) then return end

    local now = GetTime()
    local wasRapidSyncActive = now < rapidAlphaSyncUntil
    rapidAlphaSyncUntil = now + 0.2

    if wasRapidSyncActive then return end

    ResyncInheritedUnitFrameAlpha()
    C_Timer.After(0, function()
        if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end
        ResyncInheritedUnitFrameAlpha()
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
        if self ~= playerFrameRef and self ~= targetFrameRef then return end

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

    return playerFrame, targetFrame
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
    if not frame or not anchors or #anchors == 0 then return end
    frame:ClearAllPoints()
    for _, a in ipairs(anchors) do
        frame:SetPoint(a.point, a.relativeTo, a.relativePoint, a.x, a.y)
    end
end

local function WouldFrameDependOn(sourceFrame, dependencyFrame, visited, depth)
    if not sourceFrame or not dependencyFrame then return false end
    if sourceFrame == dependencyFrame then return true end

    depth = depth or 0
    if depth > 24 then return false end

    visited = visited or {}
    if visited[sourceFrame] then return false end
    visited[sourceFrame] = true

    local pointIndex = 1
    while true do
        local point, relativeFrame = sourceFrame:GetPoint(pointIndex)
        if not point then break end
        if relativeFrame == dependencyFrame then
            return true
        end
        if relativeFrame
            and relativeFrame ~= sourceFrame
            and relativeFrame.GetPoint
            and WouldFrameDependOn(relativeFrame, dependencyFrame, visited, depth + 1) then
            return true
        end
        pointIndex = pointIndex + 1
    end

    return false
end

------------------------------------------------------------------------
-- Apply
------------------------------------------------------------------------

function CooldownCompanion:ApplyFrameAnchoring(opts)
    opts = opts or {}
    if not opts.skipRuntimeGate
        and self.RefreshBarsAndFramesRuntimeFeatureGate
        and not self:RefreshBarsAndFramesRuntimeFeatureGate("frameAnchoring", "frame-anchoring-apply") then
        self:RevertFrameAnchoring()
        return
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

    local groupId = GetEffectiveAnchorGroupId(settings)
    if not groupId then
        self:RevertFrameAnchoring()
        return
    end

    local group = self.db.profile.groups[groupId]
    if not group or not self:IsIconLikeDisplayMode(group.displayMode) then
        self:RevertFrameAnchoring()
        return
    end

    local groupFrame = self.groupFrames[groupId]
    if not groupFrame or not groupFrame:IsShown() then
        self:RevertFrameAnchoring()
        return
    end

    local playerFrame, targetFrame = GetUnitFrames(settings)
    if not playerFrame and not targetFrame then
        self:RevertFrameAnchoring()
        return
    end

    if isApplied and (playerFrameRef ~= playerFrame or targetFrameRef ~= targetFrame) then
        self:RevertFrameAnchoring()
    end

    if (playerFrame and WouldFrameDependOn(groupFrame, playerFrame))
        or (targetFrame and WouldFrameDependOn(groupFrame, targetFrame)) then
        self:RevertFrameAnchoring()
        return
    end

    -- Save original positions (only if not already saved)
    if playerFrame and not savedPlayerAnchors then
        savedPlayerAnchors = SaveFrameAnchors(playerFrame)
    end
    if targetFrame and not savedTargetAnchors then
        savedTargetAnchors = SaveFrameAnchors(targetFrame)
    end

    -- Store refs for revert
    playerFrameRef = playerFrame
    targetFrameRef = targetFrame
    InstallInheritedAlphaSetHook(playerFrameRef)
    InstallInheritedAlphaSetHook(targetFrameRef)

    -- Apply player frame anchoring
    local ps = settings.player
    if playerFrame and ps then
        playerFrame:ClearAllPoints()
        playerFrame:SetPoint(ps.anchorPoint, groupFrame, ps.relativePoint,
                             ps.xOffset or 0, ps.yOffset or 0)
    end

    -- Apply target frame anchoring
    if targetFrame then
        if settings.mirroring and ps then
            -- Mirror from player settings
            local mAnchor = MIRROR_POINTS[ps.anchorPoint] or ps.anchorPoint
            local mRelative = MIRROR_POINTS[ps.relativePoint] or ps.relativePoint
            targetFrame:ClearAllPoints()
            targetFrame:SetPoint(mAnchor, groupFrame, mRelative,
                                 -(ps.xOffset or 0), ps.yOffset or 0)
        else
            -- Independent target settings
            local ts = settings.target
            if ts then
                targetFrame:ClearAllPoints()
                targetFrame:SetPoint(ts.anchorPoint, groupFrame, ts.relativePoint,
                                     ts.xOffset or 0, ts.yOffset or 0)
            end
        end
    end

    isApplied = true

    -- Alpha inheritance
    if settings.inheritAlpha then
        -- Save original alpha (only if not already saved)
        if playerFrame and not savedPlayerAlphaAttempted then
            savedPlayerAlpha = CaptureRestorableAlpha(playerFrame)
            savedPlayerAlphaAttempted = true
        end
        if targetFrame and not savedTargetAlphaAttempted then
            savedTargetAlpha = CaptureRestorableAlpha(targetFrame)
            savedTargetAlphaAttempted = true
        end

        -- Apply alpha immediately — use natural alpha to avoid config override cascade
        local groupAlpha = SyncInheritedUnitFrameAlpha(groupFrame, playerFrame, targetFrame)

        -- Start alpha sync OnUpdate (~30Hz polling)
        if not alphaSyncFrame then
            alphaSyncFrame = CreateFrame("Frame")
        end
        local lastAlpha = groupAlpha
        local accumulator = 0
        local SYNC_INTERVAL = 1 / 30
        alphaSyncFrame:SetScript("OnUpdate", function(self, dt)
            local now = GetTime()
            local rapidSyncActive = now < rapidAlphaSyncUntil
            accumulator = accumulator + dt
            if not rapidSyncActive then
                if accumulator < SYNC_INTERVAL then return end
                accumulator = 0
            end
            local alpha = GetInheritedUnitFrameAlpha(groupFrame)
            if alpha == nil then return end
            if rapidSyncActive or alpha ~= lastAlpha then
                lastAlpha = SyncInheritedUnitFrameAlpha(groupFrame, playerFrameRef, targetFrameRef) or lastAlpha
            end
        end)
    else
        -- inheritAlpha is off — stop sync and restore originals if we had them
        if alphaSyncFrame then
            alphaSyncFrame:SetScript("OnUpdate", nil)
        end
        rapidAlphaSyncUntil = 0
        if savedPlayerAlpha ~= nil and playerFrameRef then
            SetUnitFrameAlphaGuarded(playerFrameRef, savedPlayerAlpha)
        end
        if savedTargetAlpha ~= nil and targetFrameRef then
            SetUnitFrameAlphaGuarded(targetFrameRef, savedTargetAlpha)
        end
        savedPlayerAlpha = nil
        savedTargetAlpha = nil
        savedPlayerAlphaAttempted = false
        savedTargetAlphaAttempted = false
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

    -- Stop alpha sync and restore alpha
    if alphaSyncFrame then
        alphaSyncFrame:SetScript("OnUpdate", nil)
    end
    rapidAlphaSyncUntil = 0
    if savedPlayerAlpha ~= nil and playerFrameRef then
        SetUnitFrameAlphaGuarded(playerFrameRef, savedPlayerAlpha)
    end
    if savedTargetAlpha ~= nil and targetFrameRef then
        SetUnitFrameAlphaGuarded(targetFrameRef, savedTargetAlpha)
    end
    savedPlayerAlpha = nil
    savedTargetAlpha = nil
    savedPlayerAlphaAttempted = false
    savedTargetAlphaAttempted = false

    -- Restore player frame
    if playerFrameRef and savedPlayerAnchors then
        RestoreFrameAnchors(playerFrameRef, savedPlayerAnchors)
    end

    -- Restore target frame
    if targetFrameRef and savedTargetAnchors then
        RestoreFrameAnchors(targetFrameRef, savedTargetAnchors)
    end

    savedPlayerAnchors = nil
    savedTargetAnchors = nil
    playerFrameRef = nil
    targetFrameRef = nil
end

------------------------------------------------------------------------
-- Evaluate
------------------------------------------------------------------------

function CooldownCompanion:EvaluateFrameAnchoring(opts)
    opts = opts or {}
    if not opts.skipRuntimeGate
        and self.RefreshBarsAndFramesRuntimeFeatureGate
        and not self:RefreshBarsAndFramesRuntimeFeatureGate("frameAnchoring", opts.reason or "frame-anchoring-evaluate") then
        self:RevertFrameAnchoring()
        return
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
    }
end

------------------------------------------------------------------------
-- Hooks (same pattern as CastBar / ResourceBar)
------------------------------------------------------------------------

InstallHooks = function()
    if hooksInstalled then return end
    hooksInstalled = true

    -- When anchor group refreshes — re-evaluate
    hooksecurefunc(CooldownCompanion, "RefreshGroupFrame", function(self, groupId)
        if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end
        local s = GetFrameAnchoringSettings()
        if s and s.enabled then
            C_Timer.After(0, function()
                if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end
                CooldownCompanion:EvaluateFrameAnchoring()
            end)
        end
    end)

    local function QueueFrameAnchoringReevaluate()
        C_Timer.After(0.1, function()
            if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end
            CooldownCompanion:EvaluateFrameAnchoring()
        end)
    end

    -- When all groups refresh — re-evaluate
    hooksecurefunc(CooldownCompanion, "RefreshAllGroups", function()
        if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end
        QueueFrameAnchoringReevaluate()
    end)

    -- Visibility-only refresh path (zone/resting/pet-battle transitions)
    -- still needs unit-frame anchoring re-evaluation.
    hooksecurefunc(CooldownCompanion, "RefreshAllGroupsVisibilityOnly", function()
        if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end
        QueueFrameAnchoringReevaluate()
    end)

    hooksecurefunc(CooldownCompanion, "OnTargetChanged", function()
        if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("frameAnchoring") then return end
        local s = GetFrameAnchoringSettings()
        if not (isApplied and s and s.enabled and s.inheritAlpha) then return end
        QueueInheritedUnitFrameAlphaResync()
    end)
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    C_Timer.After(0.5, function()
        CooldownCompanion:EvaluateFrameAnchoring({ reason = "frame-anchoring-init" })
    end)
end)
