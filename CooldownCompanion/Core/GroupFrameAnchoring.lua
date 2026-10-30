--[[
    CooldownCompanion - GroupFrameAnchoring
    Panel anchors, inherited alpha, saved positions, and anchor dependents.

    Part of the GroupFrame family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._GroupFrame.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local pairs = pairs
local ipairs = ipairs
local InCombatLockdown = InCombatLockdown

local GF = ST._GroupFrame

-- GroupFrameShared.lua
local IsCursorAnchor = GF.IsCursorAnchor
local SetExternalAnchorAlphaSyncActive = GF.SetExternalAnchorAlphaSyncActive
local UpdateCoordLabel = GF.UpdateCoordLabel
local ResolveSafeAnchorTarget = GF.ResolveSafeAnchorTarget
local GetPanelContainerFrameName = GF.GetPanelContainerFrameName
local ShouldSyncAnchorAlpha = GF.ShouldSyncAnchorAlpha
local ApplyGroupOwnAlpha = GF.ApplyGroupOwnAlpha
local IsAlphaSyncActive = GF.IsAlphaSyncActive
local GetPanelBaseAlpha = GF.GetPanelBaseAlpha
local GetPanelUnlockState = GF.GetPanelUnlockState
local GetAnchorInheritedAlpha = GF.GetAnchorInheritedAlpha
local ComputeGroupFrameCoordinates = GF.ComputeGroupFrameCoordinates
local IsCursorAnchorLayoutPreviewGroupActive = GF.IsCursorAnchorLayoutPreviewGroupActive
local CURSOR_ANCHOR_TARGET = GF.CURSOR_ANCHOR_TARGET
local BuildDefaultCursorAnchor = GF.BuildDefaultCursorAnchor
local ParseAddonAnchorFrameName = GF.ParseAddonAnchorFrameName
local WouldFrameDependencyCreateCircularAnchor = GF.WouldFrameDependencyCreateCircularAnchor

-- Utils.lua
local GetAnchorOffset = ST._GetPanelAnchorOffset
-- AnchorPolicy.lua
local BuildRootAnchor = ST._BuildRootAnchor
-- GroupManagement.lua
local ResetIndicatorPanelAnchor = ST._ResetIndicatorPanelAnchor

-- Indicator geometry and alpha have the same active connection. The panel
-- frame owns natural alpha even when no source/display host exists.
function CooldownCompanion:RefreshIndicatorAnchorAlpha(frame, group, force)
    local relativeTo = self:GetActivePanelAnchorRelativeTo(group)
    local kind = self:ParseAddonAnchorFrameName(relativeTo)
    local target
    if group.inheritPanelAlpha ~= false and relativeTo and relativeTo ~= "UIParent"
        and not IsCursorAnchor(relativeTo) and (kind == "group" or kind == nil) then
        target = self:ResolveAddonFrameAnchorTarget(frame.groupId, "group", relativeTo)
    end
    if not force and frame._indicatorAlphaOwned and frame.anchoredToParent == target then return end
    frame._indicatorAlphaOwned = true
    frame.anchoredToParent = target
    self:SetupAlphaSync(frame, target)
end

-- GroupFrameCursorAnchor.lua
local GetCursorAnchorLayoutPreviewPosition = GF.GetCursorAnchorLayoutPreviewPosition
local ApplyCursorAnchorPosition = GF.ApplyCursorAnchorPosition

function CooldownCompanion:AnchorGroupFrame(frame, anchor, forceCenter)
    -- Deferred during combat — ClearAllPoints/SetPoint are protected.
    if InCombatLockdown() and frame:IsProtected() then
        frame._anchorDirty = true
        return
    end

    local group = self.db.profile.groups[frame.groupId]
    if ST.IsIndicatorGroup(group) then
        local body, deferred = self:UpdateIndicatorAnchorBody(frame, group)
        if deferred then return end
        frame._anchorDirty = nil
        frame:ClearAllPoints()
        ST.SetPanelBasePoint(frame, "CENTER", body, "CENTER", 0, 0)
        self:RefreshIndicatorAnchorAlpha(frame, group, true)
        if IsCursorAnchor(anchor) then
            self:RefreshCursorAnchorTicker()
        end
        return
    else
        local bodyRetired = frame._indicatorAnchorBodyActive
        frame._indicatorAnchorBodyActive = nil
        frame._indicatorAlphaOwned = nil
        -- No longer an Indicator: outside anchors return to the panel frame.
        if bodyRetired then self:OnIndicatorAnchorBodyChanged(frame) end
    end

    if IsCursorAnchor(anchor) then
        local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[frame.groupId]
        local canUseCursorAnchor = self:CanGroupUseCursorAnchor(group)
        if not canUseCursorAnchor then
            frame._anchorDirty = nil
            frame:ClearAllPoints()
            if frame.alphaSyncFrame then
                frame.alphaSyncFrame:SetScript("OnUpdate", nil)
            end
            SetExternalAnchorAlphaSyncActive(frame, false)
            frame.anchoredToParent = nil
            ST.SetPanelBasePoint(frame, "CENTER", UIParent, "CENTER", 0, 0)
            UpdateCoordLabel(frame, 0, 0)
            if self.RefreshCursorAnchorTicker then
                self:RefreshCursorAnchorTicker()
            end
            return
        end
        local cursorX, cursorY = GetCursorAnchorLayoutPreviewPosition(self, frame.groupId)
        ApplyCursorAnchorPosition(self, frame, anchor, cursorX, cursorY)
        if self.RefreshCursorAnchorTicker then
            self:RefreshCursorAnchorTicker()
        end
        return
    end

    frame._anchorDirty = nil
    frame:ClearAllPoints()

    -- Stop any existing alpha sync
    if frame.alphaSyncFrame then
        frame.alphaSyncFrame:SetScript("OnUpdate", nil)
    end
    SetExternalAnchorAlphaSyncActive(frame, false)
    frame.anchoredToParent = nil

    local relativeTo = anchor.relativeTo
    if relativeTo and relativeTo ~= "UIParent" then
        local relativeFrame, anchorState = ResolveSafeAnchorTarget(self, frame.groupId, "group", relativeTo)
        if relativeFrame then
            -- Position against the target's ANCHORING BODY: a sectioned panel's
            -- frame spans the union of its base cluster and its sections, and
            -- the base row is what a dependent is glued to. Identity stays the
            -- real frame -- alpha inheritance, validation, and the circular
            -- guard all key on the panel, not on its interior stand-in.
            ST.SetPanelBasePoint(frame, anchor.point, ST.GetPanelAnchorBodyFrame(relativeFrame),
                anchor.relativePoint, anchor.x, anchor.y)
            UpdateCoordLabel(frame, anchor.x, anchor.y)
            -- Store reference for alpha inheritance
            frame.anchoredToParent = relativeFrame
            -- Set up alpha sync
            self:SetupAlphaSync(frame, relativeFrame)
            return
        else
            -- Unsafe or missing target: use a temporary visual fallback without
            -- rewriting the saved anchor. Panels prefer their container first.
            local containerName = GetPanelContainerFrameName(frame.groupId)
            if containerName then
                local containerFrame = _G[containerName]
                if containerFrame then
                    ST.SetPanelBasePoint(frame, "TOPLEFT", containerFrame, "TOPLEFT", 0, 0)
                    frame.anchoredToParent = containerFrame
                    self:SetupAlphaSync(frame, containerFrame)
                    -- Don't overwrite group.anchor — preserve custom anchor
                    -- for re-anchor pass after all frames are created
                    UpdateCoordLabel(frame, 0, 0)
                    return
                end
            end
            -- If the target is merely missing, allow force-center recovery.
            -- Unsafe external targets should stay preserved until the user
            -- intentionally changes them.
            -- Otherwise use saved position relative to UIParent
            if forceCenter and anchorState ~= "unsafe" then
                ST.SetPanelBasePoint(frame, "CENTER", UIParent, "CENTER", 0, 0)
                -- Update the saved anchor to reflect the centered position
                local group = self.db.profile.groups[frame.groupId]
                if group then
                    group.anchor = {
                        point = "CENTER",
                        relativeTo = "UIParent",
                        relativePoint = "CENTER",
                        x = 0,
                        y = 0,
                    }
                end
                UpdateCoordLabel(frame, 0, 0)
                return
            end
        end
    end

    -- Anchor to UIParent using saved position (preserves position across reloads)
    ST.SetPanelBasePoint(frame, anchor.point, UIParent, anchor.relativePoint, anchor.x, anchor.y)
    UpdateCoordLabel(frame, anchor.x, anchor.y)
end

-- A padlocked (locked) panel follows its parent's normal-play look. While a
-- shown parent itself wears unlocked alpha (the unlock preview), its
-- normal-play target stands in: what the fade pass works out from its rules
-- (UpdateGroupAlpha), else what it copies from its own parent, else its
-- resting alpha. A ghost parent would be hidden in play, so the child reads
-- hidden; a hidden parent keeps its own reading.
local function GetSyncedParentAlpha(parentFrame)
    local parentId = parentFrame and parentFrame.groupId
    if not (parentId and parentFrame:IsShown() and GetPanelUnlockState(parentId)) then
        return GetAnchorInheritedAlpha(parentFrame)
    end
    if parentFrame._unlockGhost then
        return 0
    end
    local state = CooldownCompanion.alphaState and CooldownCompanion.alphaState[parentId]
    -- Rules removed mid-session stop the fade pass visiting the parent, so a
    -- kept target counts only while the parent still has rules.
    if state and state.restingAlpha ~= nil
        and ST.HasActiveAlphaSettings(CooldownCompanion.db.profile.groups[parentId]) then
        return state.restingAlpha
    end
    if IsAlphaSyncActive(parentFrame) then
        return GetSyncedParentAlpha(parentFrame.anchoredToParent)
    end
    return GetPanelBaseAlpha(parentId)
end

-- Whether the sync paints this panel now: not while it is unlocked (its own
-- look, the one paint), nor while a panel that does not inherit its parent's
-- opacity has a baseline below 1 (the fade pass paints it).
local function SyncOwnsAlpha(frame)
    if GetPanelUnlockState(frame.groupId) then return false end
    return frame._alphaSyncInheritsAnchor == true or GetPanelBaseAlpha(frame.groupId) >= 1
end

-- The parent's natural reading, painted as the sync paints it (natural alpha
-- avoids a config override cascade). force repaints an unchanged reading: a
-- hand-off after another paint, which the tick, writing only on change,
-- would not correct.
local function PaintSyncedAlpha(frame, force)
    local alpha = GetSyncedParentAlpha(frame.anchoredToParent)
    local layoutPreview = ST.IsGroupRuntimeLayoutPreviewActive(frame.groupId)
    if alpha == nil and not layoutPreview then return end
    if alpha ~= nil then SetExternalAnchorAlphaSyncActive(frame, frame._alphaSyncInheritsExternal) end
    -- Explicit layout preview: retain natural alpha for downstream chains
    -- while the positioned frame itself stays fully visible.
    local painted = alpha
    if layoutPreview then
        frame._naturalAlpha = alpha
        painted = 1
    else
        frame._naturalAlpha = nil
    end
    if force or frame._alphaSyncLastAlpha ~= painted then
        frame._alphaSyncLastAlpha = painted
        frame:SetAlpha(painted)
    end
end

-- ~30Hz: smooth enough for fade animations, avoids per-frame overhead. One
-- script serves every panel; its state lives on the frames.
local SYNC_INTERVAL = 1 / 30
local function AlphaSyncOnUpdate(self, dt)
    local accumulator = (self._syncAccumulator or 0) + dt
    if accumulator < SYNC_INTERVAL then
        self._syncAccumulator = accumulator
        return
    end
    self._syncAccumulator = 0
    local frame = self._syncOwner
    if frame.anchoredToParent and SyncOwnsAlpha(frame) then
        PaintSyncedAlpha(frame, false)
    end
end

-- The one paint's hand-off (ApplyGroupOwnAlpha): true when the sync owns this
-- panel's opacity. It paints the parent's reading, or leaves the frame as it
-- is while that reading cannot be read, as the tick does.
function CooldownCompanion:PaintAlphaSync(frame)
    if not SyncOwnsAlpha(frame) then return false end
    PaintSyncedAlpha(frame, true)
    return true
end

function CooldownCompanion:SetupAlphaSync(frame, parentFrame)
    local shouldSync, inheritsAnchorAlpha, inheritsExternalAlpha = ShouldSyncAnchorAlpha(self, frame.groupId, parentFrame)
    if not shouldSync then
        if frame.alphaSyncFrame then
            frame.alphaSyncFrame:SetScript("OnUpdate", nil)
        end
        SetExternalAnchorAlphaSyncActive(frame, false)
        ApplyGroupOwnAlpha(frame)
        return
    end

    -- Create a hidden frame to handle OnUpdate if needed
    if not frame.alphaSyncFrame then
        frame.alphaSyncFrame = CreateFrame("Frame", nil, frame)
        frame.alphaSyncFrame._syncOwner = frame
    end

    frame._alphaSyncInheritsAnchor = inheritsAnchorAlpha or nil
    frame._alphaSyncInheritsExternal = inheritsExternalAlpha or nil
    SetExternalAnchorAlphaSyncActive(frame, inheritsExternalAlpha)

    if inheritsAnchorAlpha and self.alphaState then
        self.alphaState[frame.groupId] = nil
    end

    -- If this group has baseline alpha < 1, the alpha fade system takes
    -- priority unless panel alpha inheritance is explicitly active.
    local baseAlpha = GetPanelBaseAlpha(frame.groupId)
    if baseAlpha < 1 and not inheritsAnchorAlpha then
        frame.alphaSyncFrame:SetScript("OnUpdate", nil)
        SetExternalAnchorAlphaSyncActive(frame, false)
        -- The fade pass owns this opacity: paint it now rather than leave
        -- what the sync last wrote.
        ApplyGroupOwnAlpha(frame)
        return
    end

    -- Sync alpha immediately. An unlocked panel wears its own unlocked look
    -- (the one paint), never its parent's reading, which re-anchoring after a
    -- refresh would otherwise leave in place; the tick takes over once it
    -- reads locked.
    frame._alphaSyncLastAlpha = nil
    if GetPanelUnlockState(frame.groupId) then
        ApplyGroupOwnAlpha(frame)
    else
        PaintSyncedAlpha(frame, true)
    end

    frame.alphaSyncFrame._syncAccumulator = 0
    frame.alphaSyncFrame:SetScript("OnUpdate", AlphaSyncOnUpdate)
end

function CooldownCompanion:SaveGroupPosition(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end
    if IsCursorAnchor(group.anchor) then
        return
    end

    local previousRelativeTo = group.anchor.relativeTo
    local newX, newY, relativeTo, relFrame, desiredPoint, desiredRelPoint, anchorState = ComputeGroupFrameCoordinates(
        self,
        frame,
        groupId,
        group
    )
    if anchorState == "unsafe" then
        self:AnchorGroupFrame(frame, group.anchor)
        return
    end

    group.anchor.x = newX
    group.anchor.y = newY
    group.anchor.relativeTo = relativeTo
    if relativeTo ~= previousRelativeTo then
        self:RebuildPanelAlphaDependencyTargets()
    end

    -- Re-anchor with the corrected values so WoW doesn't change our anchor point
    frame:ClearAllPoints()
    ST.SetPanelBasePoint(frame, desiredPoint, relFrame, desiredRelPoint, newX, newY)

    UpdateCoordLabel(frame, newX, newY)
    self:RefreshConfigPanel()
    local containerId = group.parentContainerId
    if containerId and self.RefreshContainerWrapper then
        self:RefreshContainerWrapper(containerId)
    end
end

function CooldownCompanion:WouldCreateCircularAnchor(sourceId, targetId, targetKind, sourceKind)
    local groups = self.db.profile.groups
    if not groups then return false end
    local containers = self.db.profile.groupContainers or {}
    local visited = {}
    -- Track both the kind and id to avoid conflating group/container ID spaces
    sourceKind = sourceKind or "group"
    local currentKind = targetKind or "group"
    local currentId = targetId
    while currentId do
        if currentKind == sourceKind and currentId == sourceId then return true end
        local visitKey = currentKind .. ":" .. currentId
        if visited[visitKey] then return false end
        visited[visitKey] = true
        -- Look up anchor chain in the appropriate table
        local relTo
        if currentKind == "group" then
            local g = groups[currentId]
            relTo = self:GetActivePanelAnchorRelativeTo(g)
        else
            local c = containers[currentId]
            if c and c.anchor and c.anchor.relativeTo then
                relTo = c.anchor.relativeTo
            end
        end
        -- Determine next node in the chain: a non-addon frame, the cursor or
        -- no anchor ends it.
        local nextKind, nextId = ParseAddonAnchorFrameName(relTo)
        if nextKind ~= "group" and nextKind ~= "container" then break end
        currentKind, currentId = nextKind, nextId
    end
    return false
end

--- Re-point everything anchored to this panel after its sectioned state flipped.
--- The anchoring body changed frames, and an anchor to the outgoing one would
--- keep resolving positionally -- a hidden base anchor still reports its last
--- rectangle -- so a dependent left pointing at it would sit at a stale spot
--- rather than visibly break. Both directions run the same pass; AnchorGroupFrame
--- and AnchorContainerFrame each re-resolve the body and each carry their own
--- combat deferral, so a protected dependent simply comes back dirty.
--- Unit frames are not touched here: FrameAnchoring owns their protected-frame
--- discipline and re-resolves the panel body when it next applies.
function CooldownCompanion:ReanchorPanelSectionDependents(groupId)
    local profile = self.db and self.db.profile
    if not profile then return end

    local targetFrameName = "CooldownCompanionGroup" .. tostring(groupId)
    for dependentId, dependentGroup in pairs(profile.groups or {}) do
        if dependentId ~= groupId
            and dependentGroup
            and dependentGroup.anchor
            and dependentGroup.anchor.relativeTo == targetFrameName then
            local dependentFrame = self.groupFrames and self.groupFrames[dependentId]
            if dependentFrame then
                self:AnchorGroupFrame(dependentFrame, dependentGroup.anchor)
            end
        end
    end

    for containerId, container in pairs(profile.groupContainers or {}) do
        if container
            and container.anchor
            and container.anchor.relativeTo == targetFrameName then
            local containerFrame = self.containerFrames and self.containerFrames[containerId]
            if containerFrame then
                self:AnchorContainerFrame(containerFrame, container.anchor)
            end
        end
    end

    -- Indicators place a HOST frame, not the panel frame, and keep their
    -- anchor in their own display settings rather than group.anchor,
    -- so neither pass above sees them. Their one re-anchor path is the display
    -- refresh.
    if self.ReanchorIndicatorDependents then
        self:ReanchorIndicatorDependents(targetFrameName)
    end
end

function CooldownCompanion:GetDirectAnchorDependents(groupId, panelOnly)
    local profile = self.db and self.db.profile
    local groups = profile and profile.groups
    if not groups then return {} end

    local targetFrameName = "CooldownCompanionGroup" .. tostring(groupId)
    local dependents = {}
    for dependentId, dependentGroup in pairs(groups) do
        if dependentId ~= groupId
            and dependentGroup
            and dependentGroup.anchor
            and dependentGroup.anchor.relativeTo == targetFrameName
            and (not panelOnly or dependentGroup.parentContainerId) then
            dependents[#dependents + 1] = {
                name = dependentGroup.name or ((dependentGroup.parentContainerId and "Panel " or "Group ") .. dependentId),
            }
        end
    end

    if not panelOnly then
        for containerId, container in pairs(profile.groupContainers or {}) do
            if container
                and container.anchor
                and container.anchor.relativeTo == targetFrameName then
                dependents[#dependents + 1] = {
                    name = container.name or ("Group " .. containerId),
                }
            end
        end
    end

    return dependents
end

local function NamesDeletedTarget(relativeTo, deletedGroupIds, deletedContainerIds)
    local kind, id = ParseAddonAnchorFrameName(relativeTo)
    if kind == "group" then return deletedGroupIds[id] == true end
    if kind == "container" then return deletedContainerIds[id] == true end
    return false
end

-- Where an anchor's own point sits on screen, read from its target's live
-- body (the target is still placed: release runs before the delete).
local function GetAnchoredPointOnScreen(anchor)
    local target = type(anchor.relativeTo) == "string" and _G[anchor.relativeTo]
    if not (target and target.GetCenter) then return nil end
    target = ST.GetPanelAnchorBodyFrame(target)
    local cx, cy = target:GetCenter()
    local w, h = target:GetSize()
    if not (cx and cy and w and h) then return nil end
    local ox, oy = GetAnchorOffset(anchor.relativePoint or "CENTER", w, h)
    return cx + ox + (tonumber(anchor.x) or 0), cy + oy + (tonumber(anchor.y) or 0)
end

-- A Group's 1x1 anchor frame on screen: its frame when built here, else its
-- saved screen offset (the shape the login finalize writes).
local function GetContainerCenterOnScreen(self, containerId)
    local frame = self.containerFrames and self.containerFrames[containerId]
    if frame and frame:GetCenter() then return frame:GetCenter() end
    local container = self.db.profile.groupContainers[containerId]
    local anchor = type(container) == "table" and container.anchor
    if type(anchor) == "table" and (anchor.relativeTo or "UIParent") == "UIParent"
        and (anchor.point or "CENTER") == "CENTER" and (anchor.relativePoint or "CENTER") == "CENTER" then
        local ux, uy = UIParent:GetCenter()
        if ux then return ux + (tonumber(anchor.x) or 0), uy + (tonumber(anchor.y) or 0) end
    end
end

-- A panel keeps its spot on its own Group, measured as SaveGroupPosition
-- measures a drag (point and relativePoint kept). A panel never built here
-- (its Group is hidden from this character) is placed from the same live
-- geometry its anchor resolves against, so it keeps its spot for the
-- character who sees it. An Indicator's shell anchor, and anything still
-- unmeasurable, take the Group's own CENTER 0,0.
local function ReleasePanelAnchor(self, groupId, group)
    local targetName = GetPanelContainerFrameName(groupId) or "UIParent"
    local targetFrame = targetName == "UIParent" and UIParent
        or (self.containerFrames and self.containerFrames[group.parentContainerId])
    local frame = (self.groupFrames and self.groupFrames[groupId])
        or (self._dormantFrames and self._dormantFrames[groupId])
    local x, y
    if ST.IsIndicatorGroup(group) then
        -- The shell follows its display; nothing to keep.
    elseif frame and targetFrame and ST.GetPanelAnchorBodyFrame(frame):GetCenter() and targetFrame:GetCenter() then
        x, y = ComputeGroupFrameCoordinates(self, frame, groupId, group, true, targetName, targetFrame, "ok")
    elseif not frame and group.parentContainerId then
        local px, py = GetAnchoredPointOnScreen(group.anchor)
        local cx, cy = GetContainerCenterOnScreen(self, group.parentContainerId)
        if px and cx then
            local rx, ry = GetAnchorOffset(group.anchor.relativePoint or "CENTER", 1, 1)
            x, y = ST.RoundToTenths(px - cx - rx), ST.RoundToTenths(py - cy - ry)
        end
    end
    if x and y then
        group.anchor.relativeTo = targetName
        group.anchor.x = x
        group.anchor.y = y
    else
        group.anchor = BuildRootAnchor(targetName)
    end
end

--- Run before panels or Groups are deleted: everything anchored to them keeps
--- its spot on screen. A panel goes on its own Group; a Group and an
--- Indicator's display go on the screen. Choose Panel attachments and the Cast
--- Bar, Resources and Unit Frame anchors keep their own fallbacks.
function CooldownCompanion:ReleaseDeletedAnchorDependents(deletedGroupIds, deletedContainerIds)
    local profile = self.db and self.db.profile
    if not profile then return end
    deletedGroupIds = deletedGroupIds or {}
    deletedContainerIds = deletedContainerIds or {}
    local layoutModes = ST._configState and ST._configState.layoutAnchorTargetMode

    for groupId, group in pairs(profile.groups or {}) do
        if not deletedGroupIds[groupId] and type(group) == "table" then
            local released = false
            if type(group.anchor) == "table"
                and NamesDeletedTarget(group.anchor.relativeTo, deletedGroupIds, deletedContainerIds) then
                ReleasePanelAnchor(self, groupId, group)
                released = true
            end
            local settings = self:GetIndicatorAnchorSettings(group)
            if type(settings) == "table"
                and NamesDeletedTarget(settings.relativeTo, deletedGroupIds, deletedContainerIds) then
                if not self:SaveIndicatorScreenPosition(groupId, group) then
                    local px, py
                    if not self:IsGroupCursorAnchored(group) then
                        px, py = GetAnchoredPointOnScreen(settings)
                    end
                    local ux, uy = UIParent:GetCenter()
                    if px and ux then
                        settings.relativeTo, settings.relativePoint = "UIParent", "CENTER"
                        settings.x, settings.y = ST.RoundToTenths(px - ux), ST.RoundToTenths(py - uy)
                    else
                        ResetIndicatorPanelAnchor(group)
                    end
                end
                released = true
            end
            if released then
                -- The Layout tab shows the new target, not a remembered Panel mode.
                if layoutModes then layoutModes[groupId] = nil end
                local frame = self.groupFrames and self.groupFrames[groupId]
                if frame then
                    self:AnchorGroupFrame(frame, group.anchor)
                    local driver = ST.IsIndicatorGroup(group) and ST.Indicator.RuntimeSource(frame, group)
                    if driver then self:UpdateAuraTextureVisual(driver) end
                end
            end
        end
    end

    for containerId, container in pairs(profile.groupContainers or {}) do
        local anchor = type(container) == "table" and container.anchor
        if not deletedContainerIds[containerId] and type(anchor) == "table"
            and NamesDeletedTarget(anchor.relativeTo, deletedGroupIds, deletedContainerIds) then
            -- The login finalize's conversion to screen offsets. A target with no
            -- geometry already shows the Group on UIParent at these offsets.
            local normalized, _, deferred = self:NormalizeContainerAnchor(anchor, true)
            if deferred then
                anchor.relativeTo = "UIParent"
                normalized = self:NormalizeContainerAnchor(anchor, true)
            end
            container.anchor = normalized
            local frame = self.containerFrames and self.containerFrames[containerId]
            if frame then self:AnchorContainerFrame(frame, container.anchor) end
        end
    end
end

local function FormatDependentAnchorNames(dependents)
    local names = {}
    for _, dependent in ipairs(dependents or {}) do
        names[#names + 1] = dependent.name
        if #names >= 3 then
            break
        end
    end

    local text = table.concat(names, ", ")
    if dependents and #dependents > #names then
        text = text .. ", +" .. tostring(#dependents - #names) .. " more"
    end
    return text
end

local function RefreshGroupAnchorInteractionState(self, groupId, frame, group)
    if frame and group and frame.buttons then
        if ST.PanelSupportsAttachedBars(group) then
            -- Resolve each entry's baseline and reapply fitted bar geometry
            -- through the normal layout path, including combat deferral.
            self:UpdateGroupStyle(groupId)
        else
            for _, button in ipairs(frame.buttons) do
                if button.UpdateStyle then
                    local effectiveStyle = self:GetEntryEffectiveStyle(group, button.buttonData)
                    button:UpdateStyle(effectiveStyle)
                end
            end
        end
    end
    if self.UpdateGroupClickthrough then
        self:UpdateGroupClickthrough(groupId)
    end
end

local function FinishGroupAnchorChange(self, groupId, frame, group, wasCursorAnchored)
    self:AnchorGroupFrame(frame, group.anchor)
    self:RebuildPanelAlphaDependencyTargets()
    RefreshGroupAnchorInteractionState(self, groupId, frame, group)
    self:RefreshCursorAnchorTicker()
    local cursorAnchored = IsCursorAnchor(group.anchor)
    if wasCursorAnchored or cursorAnchored then
        local preview = self._cursorAnchorLayoutPreview
        local selectedGroupId = self._arrangeSelectedPanelId
            or (preview and preview.selectedGroupId)
        local transferSelection = wasCursorAnchored ~= cursorAnchored
            and self._arrangeSelectedPanelId == groupId
        local wasParked = IsCursorAnchorLayoutPreviewGroupActive(self, groupId)
        if transferSelection then
            -- The cursor and container movers have different selection owners.
            -- Release the old owner before activating the replacement below.
            self:ClearArrangeMoverSelection()
            selectedGroupId = nil
        end
        if wasCursorAnchored and not cursorAnchored and wasParked and self._arrangeModeActive then
            -- Cursor-only containers stay locked in Arrange. Carry this panel's
            -- active unlock across the anchor change without unlocking its group.
            self:SetPanelLocked(groupId, false)
        end
        self:ShowCursorAnchorLayoutPreview(selectedGroupId)
        if wasCursorAnchored and not cursorAnchored then
            self:RefreshIndependentPanelMoverChrome(groupId)
        end
        if transferSelection then
            self:ActivateArrangePanel(group.parentContainerId, groupId, false)
        end
        if self.EvaluateBarsAndFramesRuntime then
            self:EvaluateBarsAndFramesRuntime("cursor-anchor-changed")
        end
    end
end

-- Shared with Core/GroupManagement.lua so a Panel Template's Group-relative
-- offset finishes with the exact sequence a container re-anchor runs here.
ST._FinishGroupAnchorChange = FinishGroupAnchorChange

function CooldownCompanion:SetGroupAnchor(groupId, targetFrameName, forceCenter)
    local group = self.db.profile.groups[groupId]
    local frame = self.groupFrames[groupId]

    if not group or not frame then return false end
    local wasCursorAnchored = IsCursorAnchor(group.anchor)

    -- Block self-anchoring
    local selfFrameName = "CooldownCompanionGroup" .. groupId
    if targetFrameName == selfFrameName then
        self:Print("Cannot anchor a group to itself.")
        return false
    end

    if targetFrameName == CURSOR_ANCHOR_TARGET then
        if not self:CanGroupUseCursorAnchor(group) then
            self:Print("Only panels can anchor to the cursor.")
            return false
        end

        local dependents = self:GetDirectAnchorDependents(groupId)
        if self.GetExternalAnchorDependents then
            for _, dependent in ipairs(self:GetExternalAnchorDependents(groupId)) do
                dependents[#dependents + 1] = dependent
            end
        end
        if #dependents > 0 then
            self:Print("Cannot anchor to Cursor while other panels, groups, bars, or frames anchor to this panel: " .. FormatDependentAnchorNames(dependents) .. ".")
            return false
        end

        group.anchor = BuildDefaultCursorAnchor()
        FinishGroupAnchorChange(self, groupId, frame, group, wasCursorAnchored)
        return true
    end

    local validationOptions = self.GetGroupAnchorValidationOptions
        and self:GetGroupAnchorValidationOptions(groupId)
        or {
            domain = "panel",
            sourceGroupId = groupId,
            sourceKind = "group",
        }
    local targetOk = self:ValidateAddonFrameAnchorTarget(targetFrameName, validationOptions)
    if not targetOk then
        self:Print(self:GetInvalidAnchorTargetReason(targetFrameName, validationOptions))
        return false
    end

    -- Panels: redirect UIParent to their container frame
    local containerFrameName = GetPanelContainerFrameName(groupId)
    if containerFrameName and targetFrameName == "UIParent" then
        targetFrameName = containerFrameName
        forceCenter = true
    end

    -- Handle UIParent (free positioning)
    if targetFrameName == "UIParent" then
        if forceCenter then
            -- Explicitly un-anchoring - center the frame
            group.anchor = {
                point = "CENTER",
                relativeTo = "UIParent",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
            }
        end
        -- If not forceCenter, keep current anchor settings (just relativeTo changes)
        group.anchor.relativeTo = "UIParent"
        self:AnchorGroupFrame(frame, group.anchor, forceCenter)
        self:RebuildPanelAlphaDependencyTargets()
        RefreshGroupAnchorInteractionState(self, groupId, frame, group)
        self:RefreshCursorAnchorTicker()
        if wasCursorAnchored and self.EvaluateBarsAndFramesRuntime then
            self:EvaluateBarsAndFramesRuntime("cursor-anchor-changed")
        end
        return true
    end

    local targetFrame = _G[targetFrameName]
    if not targetFrame then
        self:Print("Frame '" .. targetFrameName .. "' not found.")
        return false
    end

    local targetKind = ParseAddonAnchorFrameName(targetFrameName)
    if not targetKind and WouldFrameDependencyCreateCircularAnchor(self, groupId, "group", targetFrame) then
        self:Print("Cannot anchor: target frame depends on a Cooldown Companion frame.")
        return false
    end

    -- Panel anchored to its own container: reset to default position
    if containerFrameName and targetFrameName == containerFrameName then
        group.anchor = {
            point = "CENTER",
            relativeTo = containerFrameName,
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        }
        FinishGroupAnchorChange(self, groupId, frame, group, wasCursorAnchored)
        return true
    end

    group.anchor = {
        point = "TOPLEFT",
        relativeTo = targetFrameName,
        relativePoint = "BOTTOMLEFT",
        x = 0,
        y = -5,
    }

    FinishGroupAnchorChange(self, groupId, frame, group, wasCursorAnchored)
    return true
end
