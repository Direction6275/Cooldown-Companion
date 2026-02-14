--[[
    CooldownCompanion - FrameAnchoring
    Anchors player and target unit frames (Blizzard, ElvUI, UnhaltedUnitFrames,
    or custom) to icon groups.

    No taint concerns — unit frames are either addon-owned (ElvUI/UUF) or
    Blizzard frames that tolerate SetPoint from addon code (PlayerFrame/
    TargetFrame are not secure-protected for positioning).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local isApplied = false
local hooksInstalled = false
local savedPlayerAnchors = nil   -- array of {point, relativeTo, relativePoint, x, y}
local savedTargetAnchors = nil
local playerFrameRef = nil
local targetFrameRef = nil

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

local FRAME_PAIRS = {
    blizzard = { player = "PlayerFrame",  target = "TargetFrame" },
    uuf      = { player = "UUF_Player",   target = "UUF_Target" },
    elvui    = { player = "ElvUF_Player",  target = "ElvUF_Target" },
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
    return CooldownCompanion.db and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.frameAnchoring
end

local function GetEffectiveAnchorGroupId(settings)
    if not settings then return nil end
    return settings.anchorGroupId or CooldownCompanion:GetFirstAvailableAnchorGroup()
end

local function GetAnchorGroupFrame(settings)
    local groupId = GetEffectiveAnchorGroupId(settings)
    if not groupId then return nil end
    return CooldownCompanion.groupFrames[groupId]
end

--- Auto-detect which unit frame addon is active.
local function AutoDetectUnitFrameAddon()
    if _G["ElvUF_Player"] then return "elvui" end
    if _G["UUF_Player"] then return "uuf" end
    return "blizzard"
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
        if pName and pName ~= "" then
            playerFrame = _G[pName]
        end
        if tName and tName ~= "" then
            targetFrame = _G[tName]
        end
    else
        local pair = FRAME_PAIRS[addon]
        if pair then
            playerFrame = _G[pair.player]
            targetFrame = _G[pair.target]
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

------------------------------------------------------------------------
-- Apply
------------------------------------------------------------------------

function CooldownCompanion:ApplyFrameAnchoring()
    local settings = GetFrameAnchoringSettings()
    if not settings or not settings.enabled then
        self:RevertFrameAnchoring()
        return
    end

    local groupId = GetEffectiveAnchorGroupId(settings)
    if not groupId then
        self:RevertFrameAnchoring()
        return
    end

    local group = self.db.profile.groups[groupId]
    if not group or group.displayMode ~= "icons" then
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
end

------------------------------------------------------------------------
-- Revert
------------------------------------------------------------------------

function CooldownCompanion:RevertFrameAnchoring()
    if not isApplied then return end
    isApplied = false

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

function CooldownCompanion:EvaluateFrameAnchoring()
    local settings = GetFrameAnchoringSettings()
    if not settings or not settings.enabled then
        self:RevertFrameAnchoring()
        return
    end
    self:ApplyFrameAnchoring()
end

------------------------------------------------------------------------
-- Hooks (same pattern as CastBar / ResourceBar)
------------------------------------------------------------------------

local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    -- When anchor group refreshes — re-evaluate
    hooksecurefunc(CooldownCompanion, "RefreshGroupFrame", function(self, groupId)
        local s = GetFrameAnchoringSettings()
        if s and s.enabled and (not s.anchorGroupId or s.anchorGroupId == groupId) then
            C_Timer.After(0, function()
                CooldownCompanion:EvaluateFrameAnchoring()
            end)
        end
    end)

    -- When all groups refresh — re-evaluate
    hooksecurefunc(CooldownCompanion, "RefreshAllGroups", function()
        C_Timer.After(0.1, function()
            CooldownCompanion:EvaluateFrameAnchoring()
        end)
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
        InstallHooks()
        CooldownCompanion:EvaluateFrameAnchoring()
    end)
end)
