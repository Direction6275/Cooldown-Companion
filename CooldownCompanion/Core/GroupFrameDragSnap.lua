--[[
    CooldownCompanion - GroupFrameDragSnap
    Arrange-mode snap candidates, guide rendering, and drag sessions.

    Part of the GroupFrame family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._GroupFrame.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local pairs = pairs
local ipairs = ipairs
local math_abs = math.abs
local table_sort = table.sort
local IsShiftKeyDown = IsShiftKeyDown

local GF = ST._GroupFrame

-- GroupFrameShared.lua
local function GetFrameRectInUIParentSpace(frame)
    return GF.GetFrameRectInUIParentSpace(ST.GetPanelAnchorBodyFrame(frame))
end
local GetContainerState = GF.GetContainerState
local IsSecretValue = GF.IsSecretValue

local SNAP_THRESHOLD = 8
local SNAP_VISIBLE_ALPHA_THRESHOLD = 0.05
-- Guide color per winning target scope: gold = panels touching, cyan = group
-- centered on group, silver = aligned to the screen itself.
local SNAP_GUIDE_COLORS = {
    panel = { 1, 0.82, 0, 0.9 },
    group = { 0.2, 0.8, 1, 0.9 },
    screen = { 0.85, 0.85, 0.85, 0.8 },
}
local SNAP_GUIDE_THICKNESS = 2
local dragSnapGuideOverlay = nil
local dragSnapGuideVertical = nil
local dragSnapGuideHorizontal = nil

local function HideDragSnapGuides()
    if dragSnapGuideVertical then
        dragSnapGuideVertical:Hide()
    end
    if dragSnapGuideHorizontal then
        dragSnapGuideHorizontal:Hide()
    end
end

local function EnsureDragSnapGuides()
    if dragSnapGuideOverlay then
        return
    end

    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:SetFrameLevel(1000)
    overlay:EnableMouse(false)

    local vertical = overlay:CreateTexture(nil, "OVERLAY")
    vertical:SetColorTexture(SNAP_GUIDE_COLORS.panel[1], SNAP_GUIDE_COLORS.panel[2], SNAP_GUIDE_COLORS.panel[3], SNAP_GUIDE_COLORS.panel[4])
    vertical:SetWidth(SNAP_GUIDE_THICKNESS)
    vertical:Hide()

    local horizontal = overlay:CreateTexture(nil, "OVERLAY")
    horizontal:SetColorTexture(SNAP_GUIDE_COLORS.panel[1], SNAP_GUIDE_COLORS.panel[2], SNAP_GUIDE_COLORS.panel[3], SNAP_GUIDE_COLORS.panel[4])
    horizontal:SetHeight(SNAP_GUIDE_THICKNESS)
    horizontal:Hide()

    dragSnapGuideOverlay = overlay
    dragSnapGuideVertical = vertical
    dragSnapGuideHorizontal = horizontal
end

local function AddDragSnapTarget(targets, value, kind, isCenter, scope, orthoMin, orthoMax)
    targets[#targets + 1] = {
        value = value,
        kind = kind,
        isCenter = isCenter or nil,
        scope = scope,
        orthoMin = orthoMin,
        orthoMax = orthoMax,
    }
end

local function AddDragSnapRectTargets(session, frame, prefix)
    local left, right, bottom, top = GetFrameRectInUIParentSpace(frame)
    if not left then
        return false
    end

    AddDragSnapTarget(session.targetsX, left, prefix .. "Left", nil, nil, bottom, top)
    AddDragSnapTarget(session.targetsX, (left + right) / 2, prefix .. "CenterX", true, "panel", bottom, top)
    AddDragSnapTarget(session.targetsX, right, prefix .. "Right", nil, nil, bottom, top)
    AddDragSnapTarget(session.targetsY, bottom, prefix .. "Bottom", nil, nil, left, right)
    AddDragSnapTarget(session.targetsY, (bottom + top) / 2, prefix .. "CenterY", true, "panel", left, right)
    AddDragSnapTarget(session.targetsY, top, prefix .. "Top", nil, nil, left, right)
    return true
end

local function AddDragSnapCandidate(session, candidateFrame, candidateGroupId, excludeFn)
    if not (candidateFrame and candidateFrame.IsVisible and candidateFrame:IsVisible()) then
        return
    end
    if excludeFn and excludeFn(candidateFrame, candidateGroupId) then
        return
    end
    AddDragSnapRectTargets(session, candidateFrame, "frame")
end

local function GroupFrameRendersVisibleSnapTarget(frame, groupId)
    local isLocked = GetContainerState(groupId)
    if not isLocked then
        return true
    end

    local effectiveAlpha = frame:GetEffectiveAlpha()
    if IsSecretValue(effectiveAlpha) or effectiveAlpha == nil
        or effectiveAlpha <= SNAP_VISIBLE_ALPHA_THRESHOLD then
        return false
    end

    for _, button in ipairs(frame.buttons or {}) do
        local isShown = button:IsShown()
        -- Shell alpha 0 = the button renders nothing CC-side (icon hidden,
        -- every region alpha-0) while button:GetAlpha() still reports 1, so
        -- it must not count as a visible snap target. Dim shells (0.4) and
        -- never-styled buttons (nil) do render.
        if not IsSecretValue(isShown) and isShown and button._auraShellIconAlpha ~= 0 then
            local alpha = button:GetAlpha()
            if not IsSecretValue(alpha) and alpha ~= nil and alpha > SNAP_VISIBLE_ALPHA_THRESHOLD then
                return true
            end
        end
    end
    return false
end

local function SortDragSnapTargets(left, right)
    return left.value < right.value
end

-- Centers snap only to center targets and edges only to edge targets: the
-- cross-pairings (an edge passing a center or vice versa) produce guides no
-- one reads as alignment (owner ruling 2026-08-24). Center scopes are strict:
-- a dragged group's midpoint matches only other groups' midpoints (and screen
-- centerlines), a dragged panel's midpoint only other panels' (and screen).
local function FindNearestDragSnap(targets, firstValue, centerValue, lastValue, dragClass, previousTarget, orthoMin, orthoMax)
    -- 2px hysteresis: the target currently shown keeps its snap until a rival
    -- is decisively closer, so the guide does not hop position and color at
    -- every crossover between near-equal candidates.
    local bestScore, bestDelta, bestTargetValue, bestTarget
    for index = 1, #targets do
        local target = targets[index]
        local targetValue = target.value
        local bonus = target == previousTarget and 2 or 0
        if target.orthoMin ~= nil
            and (target.orthoMin - 40 > orthoMax
                or target.orthoMax + 40 < orthoMin) then
            -- Ortho gate (40px): a target may snap only if its span on the
            -- OTHER axis overlaps the dragged rect's span, give or take —
            -- you snap to what you are beside, not to everything sharing a
            -- coordinate across the screen. Screen lines are exempt (no
            -- orthoMin).
        elseif target.isCenter then
            local scope = target.scope
            if scope == "screen" or scope == dragClass then
                local delta = targetValue - centerValue
                local distance = math_abs(delta)
                if distance <= SNAP_THRESHOLD and (bestScore == nil or distance - bonus < bestScore) then
                    bestScore = distance - bonus
                    bestDelta = delta
                    bestTargetValue = targetValue
                    bestTarget = target
                end
            end
        else
            local delta = targetValue - firstValue
            local distance = math_abs(delta)
            if distance <= SNAP_THRESHOLD and (bestScore == nil or distance - bonus < bestScore) then
                bestScore = distance - bonus
                bestDelta = delta
                bestTargetValue = targetValue
                bestTarget = target
            end

            delta = targetValue - lastValue
            distance = math_abs(delta)
            if distance <= SNAP_THRESHOLD and (bestScore == nil or distance - bonus < bestScore) then
                bestScore = distance - bonus
                bestDelta = delta
                bestTargetValue = targetValue
                bestTarget = target
            end
        end
    end
    return bestDelta, bestTargetValue, bestTarget
end

function CooldownCompanion:BeginDragSnapSession(frame, excludeFn)
    if not frame then
        return
    end

    self:EndDragSnapSession(frame, false)
    local screenLeft, screenRight, screenBottom, screenTop = GetFrameRectInUIParentSpace(UIParent)
    if not screenLeft then
        return
    end

    local session = {
        targetsX = {},
        targetsY = {},
        dragFrame = frame._dragSnapRectFrame or frame,
        dragClass = frame.containerId and "group" or "panel",
        screenLeft = screenLeft,
        screenBottom = screenBottom,
    }
    AddDragSnapTarget(session.targetsX, screenLeft, "screenLeft", nil, "screen")
    AddDragSnapTarget(session.targetsX, (screenLeft + screenRight) / 2, "screenCenterX", true, "screen")
    AddDragSnapTarget(session.targetsX, screenRight, "screenRight", nil, "screen")
    AddDragSnapTarget(session.targetsY, screenBottom, "screenBottom", nil, "screen")
    AddDragSnapTarget(session.targetsY, (screenBottom + screenTop) / 2, "screenCenterY", true, "screen")
    AddDragSnapTarget(session.targetsY, screenTop, "screenTop", nil, "screen")

    -- Group-on-group centering: each other group's panel-union midpoint is a
    -- center target (scope "group"). Union edges are omitted on purpose: they
    -- coincide with outermost panel edges, which are already panel targets.
    -- The union is computed from the member PANELS directly: chrome may be
    -- hidden (drag-solo) while the displays stay visible and snappable.
    if session.dragClass == "group" then
        local unions = {}
        local function AccumulateGroupUnion(cid, rectFrame)
            local l, r, b, t = GetFrameRectInUIParentSpace(rectFrame)
            if not l then
                return
            end
            local u = unions[cid]
            if not u then
                unions[cid] = { l = l, r = r, b = b, t = t }
            else
                if l < u.l then u.l = l end
                if r > u.r then u.r = r end
                if b < u.b then u.b = b end
                if t > u.t then u.t = t end
            end
        end
        for groupId, candidateFrame in pairs(self.groupFrames or {}) do
            local group = self.db and self.db.profile and self.db.profile.groups
                and self.db.profile.groups[groupId]
                or nil
            local cid = group and group.parentContainerId
            if cid and cid ~= frame.containerId then
                -- Texture panels live on their aura texture host, not the
                -- group frame; both contribute so texture-only groups get a
                -- center and mixed groups get the true midpoint.
                if not self:IsStandaloneTexturePanelGroup(group)
                    and GroupFrameRendersVisibleSnapTarget(candidateFrame, groupId) then
                    AccumulateGroupUnion(cid, candidateFrame)
                end
                local textureHost = self.GetAuraTextureHostForGroupFrame
                    and self:GetAuraTextureHostForGroupFrame(candidateFrame)
                    or nil
                if textureHost and textureHost:IsVisible() then
                    AccumulateGroupUnion(cid, textureHost)
                end
            end
        end
        -- No ortho gate on group centers: centering a group on another is a
        -- deliberate ACROSS-a-gap alignment (stacking at a distance), exactly
        -- what the gate would veto. One target per group keeps them quiet.
        for _, u in pairs(unions) do
            AddDragSnapTarget(session.targetsX, (u.l + u.r) / 2, "groupCenterX", true, "group")
            AddDragSnapTarget(session.targetsY, (u.b + u.t) / 2, "groupCenterY", true, "group")
        end
    end

    for groupId, candidateFrame in pairs(self.groupFrames or {}) do
        local group = self.db and self.db.profile and self.db.profile.groups
            and self.db.profile.groups[groupId]
            or nil
        if not (group and self:IsStandaloneTexturePanelGroup(group))
            and GroupFrameRendersVisibleSnapTarget(candidateFrame, groupId) then
            AddDragSnapCandidate(session, candidateFrame, groupId, excludeFn)
        end
        local textureHost = self.GetAuraTextureHostForGroupFrame
            and self:GetAuraTextureHostForGroupFrame(candidateFrame)
            or nil
        AddDragSnapCandidate(session, textureHost, groupId, excludeFn)
    end

    local castBarMover = self.GetIndependentCastBarSnapFrame and self:GetIndependentCastBarSnapFrame() or nil
    AddDragSnapCandidate(session, castBarMover, nil, excludeFn)
    local resourceStackWrapper = self.GetIndependentResourceStackSnapFrame
        and self:GetIndependentResourceStackSnapFrame()
        or nil
    AddDragSnapCandidate(session, resourceStackWrapper, nil, excludeFn)

    table_sort(session.targetsX, SortDragSnapTargets)
    table_sort(session.targetsY, SortDragSnapTargets)
    frame._snapSession = session
    local tracker = frame._dragSnapUpdateTracker
    if not tracker then
        tracker = CreateFrame("Frame", nil, frame)
        tracker._dragFrame = frame
        tracker._onUpdate = function(self)
            local dragFrame = self._dragFrame
            if not (dragFrame and dragFrame._snapSession) then
                self:SetScript("OnUpdate", nil)
                return
            end
            if not dragFrame._coordinateSnapUpdatesPerFrame then
                CooldownCompanion:UpdateDragSnapSession(dragFrame)
            end
        end
        frame._dragSnapUpdateTracker = tracker
    end
    tracker:SetScript("OnUpdate", tracker._onUpdate)
end

function CooldownCompanion:UpdateDragSnapSession(frame)
    local session = frame and frame._snapSession or nil
    if not session then
        return
    end

    if IsShiftKeyDown() then
        session.snapDX = nil
        session.snapDY = nil
        -- Also forget the hysteresis targets: a bypassed snap must not keep
        -- its "currently shown" scoring bonus into the next live update.
        session.lastSnapTargetX = nil
        session.lastSnapTargetY = nil
        HideDragSnapGuides()
        return
    end

    local left, right, bottom, top = GetFrameRectInUIParentSpace(session.dragFrame)
    if not left then
        session.snapDX = nil
        session.snapDY = nil
        session.lastSnapTargetX = nil
        session.lastSnapTargetY = nil
        HideDragSnapGuides()
        return
    end

    local snapDX, snapX, snapTargetX = FindNearestDragSnap(session.targetsX, left, (left + right) / 2, right, session.dragClass, session.lastSnapTargetX, bottom, top)
    local snapDY, snapY, snapTargetY = FindNearestDragSnap(session.targetsY, bottom, (bottom + top) / 2, top, session.dragClass, session.lastSnapTargetY, left, right)
    session.lastSnapTargetX = snapTargetX
    session.lastSnapTargetY = snapTargetY
    session.snapDX = snapDX
    session.snapDY = snapDY

    if snapDX ~= nil or snapDY ~= nil then
        EnsureDragSnapGuides()
    end
    if snapDX ~= nil then
        local color = SNAP_GUIDE_COLORS[snapTargetX and snapTargetX.scope or "panel"] or SNAP_GUIDE_COLORS.panel
        dragSnapGuideVertical:SetColorTexture(color[1], color[2], color[3], color[4])
        dragSnapGuideVertical:ClearAllPoints()
        dragSnapGuideVertical:SetPoint("TOP", dragSnapGuideOverlay, "TOPLEFT", snapX - session.screenLeft, 0)
        dragSnapGuideVertical:SetPoint("BOTTOM", dragSnapGuideOverlay, "BOTTOMLEFT", snapX - session.screenLeft, 0)
        dragSnapGuideVertical:Show()
    elseif dragSnapGuideVertical then
        dragSnapGuideVertical:Hide()
    end
    if snapDY ~= nil then
        local color = SNAP_GUIDE_COLORS[snapTargetY and snapTargetY.scope or "panel"] or SNAP_GUIDE_COLORS.panel
        dragSnapGuideHorizontal:SetColorTexture(color[1], color[2], color[3], color[4])
        dragSnapGuideHorizontal:ClearAllPoints()
        dragSnapGuideHorizontal:SetPoint("LEFT", dragSnapGuideOverlay, "BOTTOMLEFT", 0, snapY - session.screenBottom)
        dragSnapGuideHorizontal:SetPoint("RIGHT", dragSnapGuideOverlay, "BOTTOMRIGHT", 0, snapY - session.screenBottom)
        dragSnapGuideHorizontal:Show()
    elseif dragSnapGuideHorizontal then
        dragSnapGuideHorizontal:Hide()
    end
end

function CooldownCompanion:EndDragSnapSession(frame, apply)
    local session = frame and frame._snapSession or nil
    HideDragSnapGuides()
    local tracker = frame and frame._dragSnapUpdateTracker
    if tracker then
        tracker:SetScript("OnUpdate", nil)
    end
    if not session then
        return nil, nil
    end

    local snapDX, snapDY
    if apply and not IsShiftKeyDown() then
        snapDX = session.snapDX
        snapDY = session.snapDY
    end
    frame._snapSession = nil
    return snapDX, snapDY
end

local function BeginSelfExcludedDragSnapSession(frame)
    CooldownCompanion:BeginDragSnapSession(frame, function(candidateFrame)
        return candidateFrame == frame
    end)
end

local function ApplyEndedDragSnapSession(frame, apply)
    if apply then
        CooldownCompanion:UpdateDragSnapSession(frame)
    end
    local snapDX, snapDY = CooldownCompanion:EndDragSnapSession(frame, apply)
    if snapDX ~= nil or snapDY ~= nil then
        frame:AdjustPointsOffset(snapDX or 0, snapDY or 0)
    end
end

-- Private helpers consumed by later GroupFrame files.
GF.BeginSelfExcludedDragSnapSession = BeginSelfExcludedDragSnapSession
GF.ApplyEndedDragSnapSession = ApplyEndedDragSnapSession
