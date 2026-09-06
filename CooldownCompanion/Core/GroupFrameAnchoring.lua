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
local GetContainerState = GF.GetContainerState
local GetAnchorInheritedAlpha = GF.GetAnchorInheritedAlpha
local ComputeGroupFrameCoordinates = GF.ComputeGroupFrameCoordinates
local IsCursorAnchorLayoutPreviewGroupActive = GF.IsCursorAnchorLayoutPreviewGroupActive
local CURSOR_ANCHOR_TARGET = GF.CURSOR_ANCHOR_TARGET
local BuildDefaultCursorAnchor = GF.BuildDefaultCursorAnchor
local ParseAddonAnchorFrameName = GF.ParseAddonAnchorFrameName
local WouldFrameDependencyCreateCircularAnchor = GF.WouldFrameDependencyCreateCircularAnchor

-- GroupFrameCursorAnchor.lua
local GetCursorAnchorLayoutPreviewPosition = GF.GetCursorAnchorLayoutPreviewPosition
local ApplyCursorAnchorPosition = GF.ApplyCursorAnchorPosition

function CooldownCompanion:AnchorGroupFrame(frame, anchor, forceCenter)
    -- Deferred during combat — ClearAllPoints/SetPoint are protected.
    if InCombatLockdown() and frame:IsProtected() then
        frame._anchorDirty = true
        return
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
    end

    SetExternalAnchorAlphaSyncActive(frame, inheritsExternalAlpha)

    if inheritsAnchorAlpha and self.alphaState then
        self.alphaState[frame.groupId] = nil
    end

    -- If this group has baseline alpha < 1, the alpha fade system takes
    -- priority unless panel alpha inheritance is explicitly active.
    local _, baseAlpha = GetContainerState(frame.groupId)
    if baseAlpha < 1 and not inheritsAnchorAlpha then
        frame.alphaSyncFrame:SetScript("OnUpdate", nil)
        SetExternalAnchorAlphaSyncActive(frame, false)
        return
    end

    -- Sync alpha immediately — use parent's natural alpha to avoid config override cascade
    local lastAlpha = GetAnchorInheritedAlpha(parentFrame)
    if lastAlpha ~= nil then
        SetExternalAnchorAlphaSyncActive(frame, inheritsExternalAlpha)
        frame:SetAlpha(lastAlpha)
    elseif ST.IsGroupRuntimeLayoutPreviewActive(frame.groupId) then
        lastAlpha = 1
        frame:SetAlpha(1)
    end

    -- Sync alpha at ~30Hz (smooth enough for fade animations, avoids per-frame overhead)
    local accumulator = 0
    local SYNC_INTERVAL = 1 / 30
    frame.alphaSyncFrame:SetScript("OnUpdate", function(self, dt)
        accumulator = accumulator + dt
        if accumulator < SYNC_INTERVAL then return end
        accumulator = 0
        if frame.anchoredToParent then
            -- Skip sync if this panel owns alpha locally or the group is unlocked.
            local locked, bAlpha = GetContainerState(frame.groupId)
            if (bAlpha < 1 and not inheritsAnchorAlpha) or not locked then return end
            -- Read parent's natural alpha to avoid config override cascade
            local alpha = GetAnchorInheritedAlpha(frame.anchoredToParent)
            if alpha == nil then return end
            SetExternalAnchorAlphaSyncActive(frame, inheritsExternalAlpha)
            -- Explicit layout preview: retain natural alpha for downstream
            -- chains while the positioned frame itself stays fully visible.
            if ST.IsGroupRuntimeLayoutPreviewActive(frame.groupId) then
                frame._naturalAlpha = alpha
                if lastAlpha ~= 1 then
                    lastAlpha = 1
                    frame:SetAlpha(1)
                end
                return
            end
            frame._naturalAlpha = nil
            if lastAlpha == nil or alpha ~= lastAlpha then
                lastAlpha = alpha
                frame:SetAlpha(alpha)
            end
        end
    end)
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
            if g and g.anchor and g.anchor.relativeTo then
                relTo = g.anchor.relativeTo
            end
        else
            local c = containers[currentId]
            if c and c.anchor and c.anchor.relativeTo then
                relTo = c.anchor.relativeTo
            end
        end
        if not relTo then break end
        -- Determine next node in the chain
        local nextGroupId = relTo:match("^CooldownCompanionGroup(%d+)$")
        if nextGroupId then
            currentKind = "group"
            currentId = tonumber(nextGroupId)
        else
            local nextContainerId = relTo:match("^CooldownCompanionContainer(%d+)$")
            if nextContainerId then
                currentKind = "container"
                currentId = tonumber(nextContainerId)
            else
                break  -- anchored to a non-addon frame, chain ends
            end
        end
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
--- discipline and re-applies off its own RefreshGroupFrame hook.
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

    -- Texture and Trigger panels place a HOST frame, not the panel frame, and
    -- keep their anchor in their own display settings rather than group.anchor,
    -- so neither pass above sees them. Their one re-anchor path is the display
    -- refresh.
    if self.ReanchorStandaloneDisplayDependents then
        self:ReanchorStandaloneDisplayDependents(targetFrameName)
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
        local groupStyle = group.style or {}
        for _, button in ipairs(frame.buttons) do
            if button.UpdateStyle then
                local effectiveStyle = self:GetEffectiveStyle(groupStyle, button.buttonData)
                button:UpdateStyle(effectiveStyle)
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
        if self.EvaluateBarsAndFramesRuntime then
            self:EvaluateBarsAndFramesRuntime("cursor-anchor-changed")
        end
        if transferSelection then
            self:ActivateArrangePanel(group.parentContainerId, groupId, false)
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
