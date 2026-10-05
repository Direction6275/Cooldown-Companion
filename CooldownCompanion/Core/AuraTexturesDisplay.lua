--[[
    CooldownCompanion - Core/AuraTexturesDisplay.lua
    Aura texture host creation, Indicator display rendering, and refresh flow.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AT = ST._AT

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local ipairs = ipairs
local math_floor = math.floor
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local type = type
local issecretvalue = issecretvalue

local UI_PARENT_NAME = AT.UI_PARENT_NAME
local CopyColor = AT.CopyColor
local Clamp = AT.Clamp
local NormalizeAnchorPoint = AT.NormalizeAnchorPoint
local ResolveGroup = AT.ResolveGroup
local StopAllTextureIndicatorEffects = AT.StopAllTextureIndicatorEffects
local DoesIndicatorMatch = AT.DoesIndicatorMatch

local NUDGE_BTN_SIZE = 12
local PANEL_HIGHLIGHT_R = 0.6
local PANEL_HIGHLIGHT_G = 0.8
local PANEL_HIGHLIGHT_B = 1
local PANEL_HIGHLIGHT_HOVER_ALPHA = 0.10
local PANEL_HIGHLIGHT_SELECTED_ALPHA = 0.18
local PANEL_HIGHLIGHT_HAIRLINE_ALPHA = 0.35

local function CreateAuraTextureOutline(host)
    local fill = host:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(PANEL_HIGHLIGHT_R, PANEL_HIGHLIGHT_G, PANEL_HIGHLIGHT_B, 0)
    fill:Hide()

    local edges = ST.CreateBorderTextureSet(host, "OVERLAY")
    ST.ApplyBorderTextures(edges, host, { 1, 1, 1, PANEL_HIGHLIGHT_HAIRLINE_ALPHA }, 1, ST.BORDER_RENDER_MODE_CRISP)
    ST.HideBorderTextures(edges)

    host.auraTextureOutlineFill = fill
    host.auraTextureOutlineEdges = edges
end

local function SetAuraTextureOutlineShown(host, isSelected, isHovered)
    if not host.auraTextureOutlineFill then
        CreateAuraTextureOutline(host)
    end

    local fillAlpha = 0
    if isSelected then
        fillAlpha = PANEL_HIGHLIGHT_SELECTED_ALPHA
    elseif isHovered then
        fillAlpha = PANEL_HIGHLIGHT_HOVER_ALPHA
    end
    host.auraTextureOutlineFill:SetColorTexture(
        PANEL_HIGHLIGHT_R,
        PANEL_HIGHLIGHT_G,
        PANEL_HIGHLIGHT_B,
        fillAlpha
    )
    host.auraTextureOutlineFill:SetShown(fillAlpha > 0)
    for _, edge in ipairs(host.auraTextureOutlineEdges or {}) do
        edge:SetShown(isSelected == true)
    end
end

local function UpdateTextureHostCoordLabel(host, x, y)
    if host and host.coordLabel and host.coordLabel.text then
        host.coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(x or 0, y or 0))
    end
end

local CancelCoordinateEdit = ST.CancelCoordinateEdit
local CreateEditableCoordLabel = ST.CreateEditableCoordLabel

local function GetAnchorOffset(point, width, height)
    if point == "TOPLEFT" then return -(width or 0) / 2, (height or 0) / 2 end
    if point == "TOP" then return 0, (height or 0) / 2 end
    if point == "TOPRIGHT" then return (width or 0) / 2, (height or 0) / 2 end
    if point == "LEFT" then return -(width or 0) / 2, 0 end
    if point == "CENTER" then return 0, 0 end
    if point == "RIGHT" then return (width or 0) / 2, 0 end
    if point == "BOTTOMLEFT" then return -(width or 0) / 2, -(height or 0) / 2 end
    if point == "BOTTOM" then return 0, -(height or 0) / 2 end
    if point == "BOTTOMRIGHT" then return (width or 0) / 2, -(height or 0) / 2 end
    return 0, 0
end

local function GetGroupedPreviewContainerFrame(group, groupId)
    if not (group and group.parentContainerId) then
        return nil
    end
    if not (CooldownCompanion.IsContainerUnlockPreviewActive and CooldownCompanion:IsContainerUnlockPreviewActive(group.parentContainerId)) then
        return nil
    end
    if groupId
        and CooldownCompanion.IsGroupVisibleInUnlockPreview
        and not CooldownCompanion:IsGroupVisibleInUnlockPreview(groupId, {
            group = group,
            checkCharVisibility = true,
        })
    then
        return nil
    end
    return CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[group.parentContainerId] or nil
end

local function GetIndicatorScreenAnchorPoint(settings)
    local point = settings and settings.point or "CENTER"
    local relativePoint = settings and settings.relativePoint or "CENTER"
    local x = tonumber(settings and settings.x) or 0
    local y = tonumber(settings and settings.y) or 0
    local uiCenterX, uiCenterY = UIParent:GetCenter()
    local uiWidth, uiHeight = UIParent:GetSize()
    if not (uiCenterX and uiCenterY and uiWidth and uiHeight) then
        return nil, nil, point, relativePoint
    end

    local relOffsetX, relOffsetY = GetAnchorOffset(relativePoint, uiWidth, uiHeight)
    return uiCenterX + relOffsetX + x, uiCenterY + relOffsetY + y, point, relativePoint
end

local function GetTextureHostDisplayCoords(host, point, relativePoint)
    if not (host and host.GetCenter and host.GetSize) then
        return nil, nil, nil, nil
    end

    local uiCenterX, uiCenterY = UIParent:GetCenter()
    local uiWidth, uiHeight = UIParent:GetSize()
    local hostCenterX, hostCenterY = host:GetCenter()
    local hostWidth, hostHeight = host:GetSize()
    if not (uiCenterX and uiCenterY and uiWidth and uiHeight and hostCenterX and hostCenterY and hostWidth and hostHeight) then
        return nil, nil, nil, nil
    end

    local normalizedPoint = NormalizeAnchorPoint(point or "CENTER")
    local normalizedRelativePoint = NormalizeAnchorPoint(relativePoint or "CENTER")
    local pointOffsetX, pointOffsetY = GetAnchorOffset(normalizedPoint, hostWidth, hostHeight)
    local refOffsetX, refOffsetY = GetAnchorOffset(normalizedRelativePoint, uiWidth, uiHeight)
    if pointOffsetX == nil or pointOffsetY == nil or refOffsetX == nil or refOffsetY == nil then
        return nil, nil, normalizedPoint, normalizedRelativePoint
    end

    local screenAnchorX = hostCenterX + pointOffsetX
    local screenAnchorY = hostCenterY + pointOffsetY
    local x = math_floor(((screenAnchorX - (uiCenterX + refOffsetX)) * 10) + 0.5) / 10
    local y = math_floor(((screenAnchorY - (uiCenterY + refOffsetY)) * 10) + 0.5) / 10
    return x, y, normalizedPoint, normalizedRelativePoint
end

local function HasIndicatorAnchorTarget(settings)
    local relativeTo = type(settings) == "table" and settings.relativeTo or nil
    return type(relativeTo) == "string" and relativeTo ~= "" and relativeTo ~= UI_PARENT_NAME
end

local function GetIndicatorAnchorValidationOptions(relativeTo, groupId, domain)
    if domain == "panel" then
        return {
            domain = "panel",
            sourceGroupId = groupId,
            sourceKind = "group",
        }
    end
    return {
        domain = "external",
        sourceGroupId = groupId,
        sourceKind = "group",
    }
end

local function IsFrameLikeAnchorTarget(frame)
    return type(frame) == "table" and type(frame.GetObjectType) == "function"
end

local function GetIndicatorAnchorTargetFrame(group, settings, groupId, domain)
    if not (group and type(settings) == "table") then
        return nil
    end
    local relativeTo = settings.relativeTo
    if type(relativeTo) ~= "string" or relativeTo == "" or relativeTo == UI_PARENT_NAME then
        return nil
    end

    local ok = CooldownCompanion:ValidateAddonFrameAnchorTarget(
        relativeTo,
        GetIndicatorAnchorValidationOptions(relativeTo, groupId, domain)
    )
    if not ok then
        return nil, relativeTo
    end
    local frame = _G[relativeTo]
    if not IsFrameLikeAnchorTarget(frame) then
        return nil, relativeTo
    end
    return frame, relativeTo
end

local function GetIndicatorPanelAnchorFrame(group, settings, groupId)
    local relativeTo = type(settings) == "table" and settings.relativeTo or nil
    if not (group and group.parentContainerId)
        or type(relativeTo) ~= "string"
        or not relativeTo:match("^CooldownCompanionGroup%d+$") then
        return nil
    end
    return GetIndicatorAnchorTargetFrame(group, settings, groupId, "panel")
end

local function GetIndicatorFrameAnchorFrame(group, settings, groupId)
    local relativeTo = type(settings) == "table" and settings.relativeTo or nil
    if type(relativeTo) ~= "string"
        or relativeTo == ""
        or relativeTo == UI_PARENT_NAME
        or (group and group.parentContainerId and relativeTo:match("^CooldownCompanionGroup%d+$")) then
        return nil
    end
    return GetIndicatorAnchorTargetFrame(group, settings, groupId, "external")
end

--- The frame an Indicator display's host is POSITIONED against.
--- Both callers -- the SetPoint that places the host and the drag save that
--- decides whether the host still sits on its target -- have to agree, and both
--- want the target's ANCHORING BODY: a sectioned panel's frame spans the union
--- of its base cluster and its sections, and the base row is what a dependent
--- is glued to. The alpha-inheritance lookup deliberately does NOT come through
--- here; identity stays on the real panel frame.
local function GetIndicatorResolvedAnchorFrame(group, settings, groupId)
    local frame, name = GetIndicatorPanelAnchorFrame(group, settings, groupId)
    if not frame then
        frame, name = GetIndicatorFrameAnchorFrame(group, settings, groupId)
    end
    if not frame then
        return nil, name
    end
    return ST.GetPanelAnchorBodyFrame(frame), name
end

local function StopIndicatorAlphaSync(host)
    if host and host.indicatorAlphaSyncFrame then
        host.indicatorAlphaSyncFrame:SetScript("OnUpdate", nil)
    end
    if host then
        host._indicatorAlphaTarget = nil
        host._indicatorAlphaVisibilityAlpha = nil
        host._indicatorAlphaLastAlpha = nil
        host._indicatorAlphaAccumulator = nil
        host._indicatorAlphaSyncActive = nil
        if CooldownCompanion.SetContainerAlphaVisibilityMultiplier then
            CooldownCompanion:SetContainerAlphaVisibilityMultiplier(host, nil)
        end
    end
end

local function IsSecretValue(value)
    if issecretvalue and issecretvalue(value) then
        return true
    end
    return false
end

local function GetInheritedFrameAlpha(frame)
    if not frame then
        return 1
    end
    local alpha = frame._naturalAlpha
    if IsSecretValue(alpha) then
        return nil
    end
    if type(alpha) == "number" then
        return Clamp(alpha, 0, 1)
    end
    if frame.IsShown then
        local shown = frame:IsShown()
        if IsSecretValue(shown) then
            return nil
        end
        if shown == nil then
            return nil
        end
        if not shown then
            return 0
        end
    end
    if frame.GetEffectiveAlpha then
        alpha = frame:GetEffectiveAlpha()
        if IsSecretValue(alpha) then
            return nil
        end
        if alpha == nil then
            return nil
        end
        return Clamp(alpha, 0, 1)
    end
    if frame.GetAlpha then
        alpha = frame:GetAlpha()
        if IsSecretValue(alpha) then
            return nil
        end
        if alpha == nil then
            return nil
        end
        return Clamp(alpha, 0, 1)
    end
    return 1
end

local function StartIndicatorAlphaSync(host, targetFrame, visibilityAlpha)
    if not (host and targetFrame) then
        StopIndicatorAlphaSync(host)
        return
    end

    visibilityAlpha = Clamp(visibilityAlpha or 1, 0, 1)
    local wasSyncing = host._indicatorAlphaSyncActive == true
    local syncChanged = host._indicatorAlphaTarget ~= targetFrame
        or host._indicatorAlphaVisibilityAlpha ~= visibilityAlpha

    host._indicatorAlphaTarget = targetFrame
    host._indicatorAlphaVisibilityAlpha = visibilityAlpha
    if CooldownCompanion.SetContainerAlphaVisibilityMultiplier then
        CooldownCompanion:SetContainerAlphaVisibilityMultiplier(host, nil)
    end
    if syncChanged or not wasSyncing then
        host._indicatorAlphaAccumulator = 0
        local inheritedAlpha = GetInheritedFrameAlpha(targetFrame)
        if inheritedAlpha ~= nil then
            local alpha = Clamp(inheritedAlpha * visibilityAlpha, 0, 1)
            host._indicatorAlphaLastAlpha = alpha
            host:SetAlpha(alpha)
        end
    end
    if wasSyncing then
        return
    end

    if not host.indicatorAlphaSyncFrame then
        host.indicatorAlphaSyncFrame = CreateFrame("Frame", nil, host)
    end

    host._indicatorAlphaSyncActive = true
    host.indicatorAlphaSyncFrame:SetScript("OnUpdate", function(self, dt)
        local activeTarget = host._indicatorAlphaTarget
        if not activeTarget then
            self:SetScript("OnUpdate", nil)
            host._indicatorAlphaSyncActive = nil
            return
        end

        host._indicatorAlphaAccumulator = (host._indicatorAlphaAccumulator or 0) + dt
        if host._indicatorAlphaAccumulator < (1 / 30) then
            return
        end
        host._indicatorAlphaAccumulator = 0

        local inheritedAlpha = GetInheritedFrameAlpha(activeTarget)
        if inheritedAlpha == nil then
            return
        end
        local alpha = Clamp(inheritedAlpha * (host._indicatorAlphaVisibilityAlpha or 1), 0, 1)
        if alpha ~= host._indicatorAlphaLastAlpha then
            host._indicatorAlphaLastAlpha = alpha
            host:SetAlpha(alpha)
        end
    end)
end

local function SaveGroupedIndicatorPreviewSettings(host, group, settings, groupId)
    local containerFrame = GetGroupedPreviewContainerFrame(group, groupId)
    if not (host and containerFrame and settings and host.GetPoint and host.GetCenter and host.GetSize) then
        return false
    end
    if HasIndicatorAnchorTarget(settings) then
        return false
    end

    local point = settings.point or host:GetPoint(1)

    if not host._wrapperManaged then
        local _, relativeFrame = host:GetPoint(1)
        if relativeFrame ~= containerFrame then
            return false
        end
    end

    local x, y, normalizedPoint, normalizedRelativePoint = GetTextureHostDisplayCoords(
        host,
        point or settings.point or "CENTER",
        settings.relativePoint or "CENTER"
    )
    if x == nil or y == nil then
        return false
    end

    settings.point = normalizedPoint
    settings.relativePoint = normalizedRelativePoint
    settings.relativeTo = UI_PARENT_NAME
    settings.x = x
    settings.y = y
    return true
end

local function GetTextureHostPositionContext(host)
    local owner = host and host._ownerButton
    local group = owner and owner._groupId and ResolveGroup(owner._groupId)
    local settings = ST.Indicator.Settings(group)
    return owner, group, settings and settings.signal
end

local function ApplyTextureHostCoordinates(host, x, y)
    local owner, group, settings = GetTextureHostPositionContext(host)
    if group and CooldownCompanion.IsGroupCursorAnchored and CooldownCompanion:IsGroupCursorAnchored(group) then
        -- Parked cursor panel: typed coordinates are the saved cursor offset,
        -- never the standalone position settings.
        local anchor = group.anchor
        if not anchor then
            return
        end
        anchor.x = x
        anchor.y = y
        UpdateTextureHostCoordLabel(host, x, y)
        if CooldownCompanion.UpdateCursorAnchoredFrames then
            CooldownCompanion:UpdateCursorAnchoredFrames()
        end
        if ST._configState and ST._configState.configFrame and ST._configState.configFrame.frame and ST._configState.configFrame.frame:IsShown() then
            CooldownCompanion:RefreshConfigPanel()
        end
        return
    end
    if not settings then
        return
    end

    settings.x = x
    settings.y = y
    CooldownCompanion:UpdateAuraTextureVisual(owner)
    UpdateTextureHostCoordLabel(host, x, y)
    if group and group.parentContainerId and CooldownCompanion.RefreshContainerWrapper then
        CooldownCompanion:RefreshContainerWrapper(group.parentContainerId)
    end
    if ST._configState and ST._configState.configFrame and ST._configState.configFrame.frame and ST._configState.configFrame.frame:IsShown() then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function SaveTextureHostPosition(host)
    local owner, group, settings = GetTextureHostPositionContext(host)
    if not settings then
        return
    end

    local previousRelativeTo = settings.relativeTo
    if not SaveGroupedIndicatorPreviewSettings(host, group, settings, owner and owner._groupId) then
        local point, relativeFrame, relPoint, x, y = host:GetPoint(1)
        settings.point = NormalizeAnchorPoint(point)
        settings.relativePoint = NormalizeAnchorPoint(relPoint)
        local targetFrame, targetName = GetIndicatorResolvedAnchorFrame(group, settings, owner and owner._groupId)
        if targetFrame and relativeFrame == targetFrame then
            settings.relativeTo = targetName
        else
            settings.relativeTo = UI_PARENT_NAME
        end
        settings.x = math_floor(((x or 0) * 10) + 0.5) / 10
        settings.y = math_floor(((y or 0) * 10) + 0.5) / 10
    end

    if settings.relativeTo ~= previousRelativeTo then
        CooldownCompanion:RebuildPanelAlphaDependencyTargets()
    end
    UpdateTextureHostCoordLabel(host, settings.x, settings.y)
    CooldownCompanion:UpdateAuraTextureVisual(owner)
    if group and group.parentContainerId and CooldownCompanion.RefreshContainerWrapper then
        CooldownCompanion:RefreshContainerWrapper(group.parentContainerId)
    end
    if ST._configState and ST._configState.configFrame and ST._configState.configFrame.frame and ST._configState.configFrame.frame:IsShown() then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function StartGroupedIndicatorWrapperTracking(host)
    local owner = host and host._ownerButton or nil
    local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
    local containerId = group and group.parentContainerId or nil
    if containerId and CooldownCompanion.StartContainerMemberPreviewTracking then
        CooldownCompanion:StartContainerMemberPreviewTracking(containerId, owner._groupId)
    end
end

local function StopGroupedIndicatorWrapperTracking(host)
    local owner = host and host._ownerButton or nil
    local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
    local containerId = group and group.parentContainerId or nil
    if containerId and CooldownCompanion.StopContainerMemberPreviewTracking then
        CooldownCompanion:StopContainerMemberPreviewTracking(containerId)
    end
end

local function BeginTextureHostDrag(host, surfaceDrag)
    if CooldownCompanion._combatForcedLock or not host then
        return false
    end
    local owner = host._ownerButton
    local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
    if owner and CooldownCompanion.IsGroupCursorAnchored and CooldownCompanion:IsGroupCursorAnchored(owner._groupId) then
        -- Parked cursor panel: the drag selects it (never toggling off) and
        -- routes through the cursor-preview owner, so the offset saves to the
        -- cursor anchor rather than the standalone position settings.
        if not (group and CooldownCompanion.ActivateArrangePanel
            and CooldownCompanion:ActivateArrangePanel(group.parentContainerId, owner._groupId, false)) then
            return false
        end
        if not (CooldownCompanion.BeginCursorAnchorLayoutPreviewHostDrag
            and CooldownCompanion:BeginCursorAnchorLayoutPreviewHostDrag(host, owner._groupId)) then
            return false
        end
        CancelCoordinateEdit(host.coordLabel)
        host._dragCancelPending = nil
        host._isDragging = true
        host._cursorAnchorDrag = true
        host._arrangePanelSurfaceDrag = surfaceDrag and true or nil
        host:StartMoving()
        CooldownCompanion:BeginMoverChromeFade(host)
        return true
    end
    if not host._dragEnabled then
        return false
    end
    if not (group and group.parentContainerId
        and CooldownCompanion.ActivateArrangePanel
        and CooldownCompanion:ActivateArrangePanel(
            group.parentContainerId,
            owner._groupId,
            false
        )) then
        return false
    end

    CancelCoordinateEdit(host.coordLabel)
    host._dragCancelPending = nil
    host._isDragging = true
    host._arrangePanelSurfaceDrag = surfaceDrag and true or nil
    StartGroupedIndicatorWrapperTracking(host)
    host:StartMoving()
    CooldownCompanion:UpdateIndicatorAnchorBody(CooldownCompanion.groupFrames[owner._groupId], group, host)
    CooldownCompanion:BeginMoverChromeFade(host)
    CooldownCompanion:BeginDragSnapSession(host, function(candidateFrame)
        return candidateFrame == host
    end)
    return true
end

local function FinishTextureHostDrag(host)
    if not host then
        return false
    end

    if host._cursorAnchorDrag then
        host._cursorAnchorDrag = nil
        local cancelSave = host._dragCancelPending == true or CooldownCompanion._combatForcedLock
        host._dragCancelPending = nil
        host._isDragging = nil
        if host._arrangePanelSurfaceDrag then
            -- The release that ends a host-surface drag also fires the host's
            -- OnMouseUp; it must not read as a selection-toggling click.
            host._arrangeSelectClickSuppressed = true
        end
        host._arrangePanelSurfaceDrag = nil
        if not (InCombatLockdown() and host:IsProtected()) then
            host:StopMovingOrSizing()
        end
        local owner = host._ownerButton
        if CooldownCompanion.EndCursorAnchorLayoutPreviewHostDrag and owner and owner._groupId then
            CooldownCompanion:EndCursorAnchorLayoutPreviewHostDrag(owner._groupId, cancelSave)
        end
        CooldownCompanion:EndMoverChromeFade(host)
        return not cancelSave
    end

    local finishOwner = host._ownerButton
    if finishOwner and finishOwner._groupId
        and CooldownCompanion.IsGroupCursorAnchored
        and CooldownCompanion:IsGroupCursorAnchored(finishOwner._groupId) then
        -- A cursor-anchored host whose drag never began must not fall through
        -- to the Indicator save; that would write the host's parked screen
        -- position into the Indicator's anchor settings.
        host._arrangePanelSurfaceDrag = nil
        return false
    end

    local cancelSave = host._dragCancelPending == true or CooldownCompanion._combatForcedLock
    host._dragCancelPending = nil
    if host._arrangePanelSurfaceDrag then
        host._arrangeSelectClickSuppressed = true
    end
    host._arrangePanelSurfaceDrag = nil
    host._isDragging = nil
    if not (InCombatLockdown() and host:IsProtected()) then
        host:StopMovingOrSizing()
    end
    if not cancelSave then
        CooldownCompanion:UpdateDragSnapSession(host)
    end
    local snapDX, snapDY = CooldownCompanion:EndDragSnapSession(host, not cancelSave)
    if snapDX ~= nil or snapDY ~= nil then
        host:AdjustPointsOffset(snapDX or 0, snapDY or 0)
    end
    StopGroupedIndicatorWrapperTracking(host)
    if cancelSave then
        local owner, group = GetTextureHostPositionContext(host)
        CooldownCompanion:UpdateIndicatorAnchorBody(CooldownCompanion.groupFrames[owner._groupId], group)
        CooldownCompanion:EndMoverChromeFade(host)
        return false
    end

    SaveTextureHostPosition(host)
    CooldownCompanion:EndMoverChromeFade(host)
    return true
end

local function SetTextureHostMouseEnabled(host, enabled)
    if not host then
        return
    end

    local enable = enabled == true
    host:EnableMouse(enable)
    if not InCombatLockdown or not InCombatLockdown() then
        if host.SetMouseClickEnabled then
            host:SetMouseClickEnabled(enable)
        end
        if host.SetMouseMotionEnabled then
            host:SetMouseMotionEnabled(enable)
        end
    end
end

local function EnsureAuraTextureNudger(host)
    if host.nudger then return end
    local nudger = ST.MoverChrome.CreateNudger(host.dragHandle, NUDGE_BTN_SIZE, function(dx, dy)
        CancelCoordinateEdit(host.coordLabel)
        do
            local owner = host._ownerButton
            local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
            if group and CooldownCompanion.IsGroupCursorAnchored and CooldownCompanion:IsGroupCursorAnchored(group) then
                -- Parked cursor panel: nudges move the saved cursor offset;
                -- the preview owner re-anchors the host from it.
                local anchor = group.anchor
                if not anchor then
                    return
                end
                anchor.x = math_floor(((tonumber(anchor.x) or 0) + dx) * 10 + 0.5) / 10
                anchor.y = math_floor(((tonumber(anchor.y) or 0) + dy) * 10 + 0.5) / 10
                UpdateTextureHostCoordLabel(host, anchor.x, anchor.y)
                if CooldownCompanion.UpdateCursorAnchoredFrames then
                    CooldownCompanion:UpdateCursorAnchoredFrames()
                end
                return
            end
        end
        host:AdjustPointsOffset(dx, dy)
        local point, _, relativePoint, x, y = host:GetPoint()
        local owner = host._ownerButton
        local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
        local settings = group and CooldownCompanion:GetIndicatorTextureSettings(group)
        local displayX, displayY
        if settings and group and group.parentContainerId
            and not HasIndicatorAnchorTarget(settings)
            and CooldownCompanion.IsContainerUnlockPreviewActive
            and CooldownCompanion:IsContainerUnlockPreviewActive(group.parentContainerId)
        then
            displayX, displayY = GetTextureHostDisplayCoords(
                host,
                settings.point or point or "CENTER",
                settings.relativePoint or "CENTER"
            )
        end
        if displayX == nil or displayY == nil then
            displayX = math_floor((x or 0) * 10 + 0.5) / 10
            displayY = math_floor((y or 0) * 10 + 0.5) / 10
        end
        if settings then
            settings.x = displayX
            settings.y = displayY
        end
        UpdateTextureHostCoordLabel(host, displayX, displayY)
        if group and group.parentContainerId and CooldownCompanion.RefreshContainerWrapper then
            CooldownCompanion:RefreshContainerWrapper(group.parentContainerId)
        end
    end, function() SaveTextureHostPosition(host) end)
    nudger:SetFrameStrata(host.dragHandle:GetFrameStrata())
    nudger:SetFrameLevel(host.dragHandle:GetFrameLevel() + 5)
    host.nudger = nudger
end

-- The mover padlock, shared with the nameplate unlock view
-- (Core/NameplateTargetView.lua).
local function LockIndicatorPanel(groupId)
    local group = groupId and ResolveGroup(groupId) or nil
    if not group then
        return
    end

    if CooldownCompanion.ClearArrangeMoverSelection then
        CooldownCompanion:ClearArrangeMoverSelection()
    end
    CooldownCompanion:SetPanelLocked(groupId, true)
    CooldownCompanion:CaptureArrangePanelRecord(groupId)
    CooldownCompanion:RefreshAllAuraTextureVisuals()
    if ST._configState and ST._configState.configFrame and ST._configState.configFrame.frame and ST._configState.configFrame.frame:IsShown() then
        CooldownCompanion:RefreshConfigPanel()
    end
    CooldownCompanion:Print((group.name or "Indicator") .. " locked.")
    CooldownCompanion:CheckArrangeModeAutoExit()
end
ST._LockIndicatorPanel = LockIndicatorPanel

local function EnsureAuraTextureDragHandle(host)
    if host.dragHandle or InCombatLockdown() or CooldownCompanion._combatForcedLock then return end

    local dragHandle = ST.MoverChrome.CreateHeader(host, "", function()
        LockIndicatorPanel(host._ownerButton and host._ownerButton._groupId)
    end, function()
        local groupId = host._ownerButton and host._ownerButton._groupId
        local group = groupId and CooldownCompanion.db.profile.groups[groupId]
        return groupId and {
            kind = "panel",
            id = groupId,
            containerId = group and group.parentContainerId,
            focusId = group and group.parentContainerId,
        } or nil
    end)
    dragHandle:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 2)
    dragHandle:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", 0, 2)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:EnableMouse(true)

    local coordLabel = ST.MoverChrome.CreateLabel(dragHandle)
    coordLabel:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -2)
    coordLabel:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, -2)

    dragHandle:SetScript("OnDragStart", function()
        BeginTextureHostDrag(host, false)
    end)
    dragHandle:SetScript("OnDragStop", function()
        FinishTextureHostDrag(host)
    end)

    host.dragHandle = dragHandle
    host.coordLabel = coordLabel
    CreateEditableCoordLabel(
        coordLabel,
        function()
            local _, group, settings = GetTextureHostPositionContext(host)
            if group and CooldownCompanion.IsGroupCursorAnchored and CooldownCompanion:IsGroupCursorAnchored(group) then
                local anchor = group.anchor
                return (anchor and tonumber(anchor.x)) or 0, (anchor and tonumber(anchor.y)) or 0
            end
            return settings and settings.x or 0, settings and settings.y or 0
        end,
        function(x, y)
            ApplyTextureHostCoordinates(host, x, y)
        end,
        function()
            return host._isDragging == true
        end
    )
    EnsureAuraTextureNudger(host)
    local _, group, settings = GetTextureHostPositionContext(host)
    dragHandle.text:SetText(group and group.name or "Indicator")
    local anchor = group and CooldownCompanion:IsGroupCursorAnchored(group) and group.anchor or settings
    UpdateTextureHostCoordLabel(host, anchor and anchor.x, anchor and anchor.y)
    CooldownCompanion:ApplyMoverChromeFadeToFrames(host.dragHandle, host.coordLabel, host.nudger)
end

local function SyncAuraTextureControlLevels(host, raiseAboveWrapper)
    if not host then
        return
    end

    local strata = raiseAboveWrapper and "FULLSCREEN_DIALOG" or host:GetFrameStrata()
    local baseLevel = raiseAboveWrapper and 90 or (host:GetFrameLevel() or 1)

    if host.dragHandle then
        host.dragHandle:SetFrameStrata(strata)
        -- Above the display's whole subtree (artwork, pandemic tints,
        -- readouts reach visualRoot + 5).
        host.dragHandle:SetFrameLevel(baseLevel + 8)
    end
    if host.coordLabel then
        host.coordLabel:SetFrameStrata(strata)
        host.coordLabel:SetFrameLevel(baseLevel + 9)
    end
    if host.dragHandle and host.dragHandle.menuButton then
        host.dragHandle.menuButton:SetFrameStrata(strata)
        host.dragHandle.menuButton:SetFrameLevel(baseLevel + 10)
    end
    if host.nudger then
        host.nudger:SetFrameStrata(strata)
        host.nudger:SetFrameLevel(baseLevel + 13)
        for index, btn in ipairs(host.nudger.buttons or {}) do
            btn:SetFrameStrata(strata)
            btn:SetFrameLevel(baseLevel + 14 + index)
        end
    end
end

-- The header sits on the host's top edge and the coordinates on its bottom.
-- A Text Indicator with no background shows only its text, so both hug the
-- text instead (Indicator.TextContentInsets); otherwise the box edges. Only
-- the chrome moves: the outline, clicks, snapping and anchoring keep the box.
-- Re-anchored only when the insets change.
local function AnchorAuraTextureDragChrome(host)
    local _, group = GetTextureHostPositionContext(host)
    local topInset, bottomInset
    if ST.IsIndicatorGroup(group) then topInset, bottomInset = ST.Indicator.TextContentInsets(group) end
    topInset, bottomInset = topInset or 0, bottomInset or 0
    if host._ccChromeTopInset == topInset and host._ccChromeBottomInset == bottomInset then return end
    host._ccChromeTopInset, host._ccChromeBottomInset = topInset, bottomInset
    host.dragHandle:ClearAllPoints()
    host.dragHandle:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 2 - topInset)
    host.dragHandle:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", 0, 2 - topInset)
    host.coordLabel:ClearAllPoints()
    host.coordLabel:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, bottomInset - 2)
    host.coordLabel:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, bottomInset - 2)
end

local function SetAuraTextureDragControlsShown(host, shown, unlockGhost)
    if not host then return end
    shown = shown == true and not InCombatLockdown() and not CooldownCompanion._combatForcedLock
    if shown then
        EnsureAuraTextureDragHandle(host)
        AnchorAuraTextureDragChrome(host)
    end
    if host.dragHandle then
        host.dragHandle:SetIgnoreParentAlpha(shown and unlockGhost == true)
        host.dragHandle:SetShown(shown)
        if host.dragHandle.lockButton then
            host.dragHandle.lockButton:SetShown(shown)
        end
    end
    if host.coordLabel then
        host.coordLabel:SetShown(shown)
    end
    if host.dragHandle and host.dragHandle.menuButton then
        host.dragHandle.menuButton:SetShown(shown)
    end
    if host.nudger then
        host.nudger:SetShown(shown)
    end
    CooldownCompanion:ApplyMoverChromeFadeToFrames(host.dragHandle, host.coordLabel, host.nudger)
end

local function EnsureAuraTextureRuntimeRoot(host)
    if host.auraRuntimeRoot then
        return host.auraRuntimeRoot
    end

    -- Plain safe parent for AuraContainer -> AuraButton -> selected-texture
    -- kit. Recursive frame sweeps stop here; AuraDisplay exclusively owns its
    -- descendants. Alpha is the preview/production switch and is safe because
    -- this frame itself is outside Blizzard's forbidden AuraButton subtree.
    local root = CreateFrame("Frame", nil, host)
    root:SetAllPoints(host)
    root:SetAlpha(0)
    root._ccNoTouch = true
    host.auraRuntimeRoot = root
    return root
end

function CooldownCompanion:EnsureAuraTextureHost(button)
    if button.auraTextureHost then
        EnsureAuraTextureRuntimeRoot(button.auraTextureHost)
        -- Acquisition for a live display: the teardown latch never survives it.
        button.auraTextureHost._indicatorTeardownFor = nil
        return button.auraTextureHost
    end

    local host = CreateFrame("Frame", nil, UIParent)
    host:SetMovable(true)
    host:SetClampedToScreen(true)
    SetTextureHostMouseEnabled(host, false)
    host:RegisterForDrag("LeftButton")
    host:Hide()
    host._ownerButton = button

    local visualRoot = CreateFrame("Frame", nil, host)
    visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
    visualRoot:SetSize(1, 1)
    host.visualRoot = visualRoot

    local primary = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    local secondary = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    primary:Hide()
    secondary:Hide()
    host.primaryTexture = primary
    host.secondaryTexture = secondary

    EnsureAuraTextureRuntimeRoot(host)

    host:SetScript("OnDragStart", function(self)
        BeginTextureHostDrag(self, true)
    end)

    host:SetScript("OnDragStop", function(self)
        FinishTextureHostDrag(self)
    end)

    -- Arrange selection for grouped Indicator displays, including parked
    -- cursor panels: clicking the visible host uses the same toggle/solo
    -- grammar as ordinary panel overlays and toolbar rows.
    host:SetScript("OnMouseUp", function(self, mouseButton)
        local suppressed = self._arrangeSelectClickSuppressed
        self._arrangeSelectClickSuppressed = nil
        if suppressed or mouseButton ~= "LeftButton" or self._isDragging then
            return
        end
        local owner = self._ownerButton
        local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
        if group and CooldownCompanion.ActivateArrangePanel then
            CooldownCompanion:ActivateArrangePanel(group.parentContainerId, owner._groupId, true)
        end
    end)

    CreateAuraTextureOutline(host)
    button.auraTextureHost = host
    return host
end

-- A presence display (While Missing, aura lists): a bare drawing host with
-- the same visual fields
-- the shared Indicator painters expect (visualRoot, primary/secondary
-- texture), every frame carrying `template`. AuraDisplay parents it inside the
-- presence window; placement, mover chrome and alpha stay on the ordinary
-- host, which this sits centered on.
function CooldownCompanion.CreateIndicatorPresenceHost(parent, template)
    local host = CreateFrame("Frame", nil, parent, template)
    host:EnableMouse(false)
    host:SetSize(1, 1)
    host._ccFrameTemplate = template
    -- Drawn (clipped) while the aura is up too: run what effects can as
    -- AnimationGroups rather than per-frame scripts (AuraTexturesEffects).
    host._ccAnimatedEffects = true
    local visualRoot = CreateFrame("Frame", nil, host, template)
    visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
    visualRoot:SetSize(1, 1)
    host.visualRoot = visualRoot
    host.primaryTexture = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    host.secondaryTexture = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    host.primaryTexture:Hide()
    host.secondaryTexture:Hide()
    return host
end

-- Latched: callers on the per-update path (unlocked, other modes) run this
-- every tick; the teardown happens once until the next presence render.
function CooldownCompanion.ReleaseIndicatorPresenceHost(presence)
    if presence._ccPresenceReleased then return end
    presence._ccPresenceReleased = true
    StopAllTextureIndicatorEffects(presence)
    ST.Indicator.ReleaseVisual(presence)
    CooldownCompanion.HideIndicatorDisplayVisuals(presence)
end

local function ReleasePresenceDisplay(button)
    local presences = CooldownCompanion.GetIndicatorPresenceHosts and CooldownCompanion:GetIndicatorPresenceHosts(button)
    for _, presence in ipairs(presences or {}) do
        CooldownCompanion.ReleaseIndicatorPresenceHost(presence)
    end
end

function CooldownCompanion:GetAuraTextureHostForGroupFrame(groupFrame)
    local group = groupFrame and ResolveGroup(groupFrame.groupId)
    local button = ST.Indicator.RuntimeSource(groupFrame, group)
    return button and button.auraTextureHost or nil
end

function CooldownCompanion:GetAuraTextureMoverChromeForGroupFrame(groupFrame)
    local host = self:GetAuraTextureHostForGroupFrame(groupFrame)
    return host and host.dragHandle, host and host.coordLabel, host and host.nudger
end

function CooldownCompanion.EnsureIndicatorIconVisual(host)
    if host.iconFrame then
        return host.iconFrame
    end

    local frame = CreateFrame("Frame", nil, host.visualRoot, host._ccFrameTemplate)
    frame:SetPoint("CENTER")
    frame:SetSize(36, 36)
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()

    frame.icon = frame:CreateTexture(nil, "ARTWORK")

    frame.borderTextures = ST.CreateBorderTextureSet(frame, "OVERLAY")

    host.iconFrame = frame
    return frame
end

function CooldownCompanion.EnsureIndicatorTextVisual(host)
    if host.textFrame then
        return host.textFrame
    end

    local frame = CreateFrame("Frame", nil, host.visualRoot, host._ccFrameTemplate)
    frame:SetPoint("CENTER")
    frame:SetSize(200, 20)
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()

    frame.borderTextures = ST.CreateBorderTextureSet(frame, "OVERLAY")

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.text:SetJustifyV("MIDDLE")
    frame.text:SetJustifyH("CENTER")
    frame.text:SetWordWrap(false)
    frame.text:SetMaxLines(0)

    host.textFrame = frame
    return frame
end

function CooldownCompanion.HideIndicatorDisplayVisuals(host)
    if not host then
        return
    end
    host._indicatorStyle = nil

    if host.primaryTexture then
        host.primaryTexture:Hide()
    end
    if host.secondaryTexture then
        host.secondaryTexture:Hide()
    end
    if host.iconFrame then
        host.iconFrame:Hide()
    end
    if host.textFrame then
        host.textFrame:Hide()
    end
    host._indicatorBaseVisualsReady = nil
end

function CooldownCompanion.GetIndicatorIconDimensions(settings)
    if settings.maintainAspectRatio then
        local size = settings.buttonSize or 36
        return size, size
    end
    return settings.iconWidth or 36, settings.iconHeight or 36
end



function CooldownCompanion:HideAuraTextureVisual(button)
    local host = button and button.auraTextureHost
    if not host then
        return
    end

    local groupId = button._groupId
    -- Already-torn-down latch. Keyed by the group this host was torn down for,
    -- so a pooled host that changes hands cannot inherit it, and re-validated
    -- against the two states the body itself leaves behind (hidden, not
    -- dragging) so anything that shows or grabs the host reopens the teardown.
    -- Cleared explicitly on every prepare/render/finalize/release path.
    if groupId ~= nil
        and host._indicatorTeardownFor == groupId
        and not host:IsShown()
        and not host._isDragging then
        return
    end

    StopAllTextureIndicatorEffects(host)
    ReleasePresenceDisplay(button)
    host._ccPresenceMode = nil
    StopIndicatorAlphaSync(host)
    if host._isDragging then
        host._isDragging = nil
        host:StopMovingOrSizing()
        StopGroupedIndicatorWrapperTracking(host)
        self:EndMoverChromeFade(host)
    end
    CooldownCompanion:EndDragSnapSession(host, false)
    ST.Indicator.ReleaseVisual(host)
    CooldownCompanion.HideIndicatorDisplayVisuals(host)
    if host.visualRoot then
        host.visualRoot:SetAlpha(1)
    end
    if host.auraRuntimeRoot then
        host.auraRuntimeRoot:SetAlpha(0)
    end
    host._activeDisplayType = nil
    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._dragEnabled = nil
    host._wrapperManaged = nil
    host._unlockGhost = nil
    SetTextureHostMouseEnabled(host, false)
    host:SetAlpha(1)
    SetAuraTextureOutlineShown(host, false)
    SetAuraTextureDragControlsShown(host, false)
    host:Hide()
    host._indicatorTeardownFor = groupId

    local group = groupId and ResolveGroup(groupId) or nil
    self:UpdateIndicatorAnchorBody(self.groupFrames and self.groupFrames[groupId], group)
    if group and group.parentContainerId and self.RefreshContainerWrapper then
        self:RefreshContainerWrapper(group.parentContainerId)
    end
end

function CooldownCompanion:ReleaseAuraTextureVisual(button)
    if not button or not button.auraTextureHost then
        return
    end

    self:HideAuraTextureVisual(button)
    -- A retained host outlives this release, so the next hide must run the full
    -- body rather than trust a latch set before the entry changed hands.
    button.auraTextureHost._indicatorTeardownFor = nil
    -- AuraButton has a permanent ChangeParent forbidden aspect. Once this
    -- host owns an AuraContainer, retain the whole topology across pooling;
    -- AuraDisplay parks the container and owns the pool token reconciliation.
    if not button.auraTextureHost._auraSlotOwned then
        button.auraTextureHost:SetParent(nil)
        button.auraTextureHost = nil
    end
end

function CooldownCompanion.ResolveActiveIndicatorDisplay(button)
    local group = button._groupId and ResolveGroup(button._groupId)
    local settings = ST.Indicator.Settings(group)
    if not settings then return end
    if settings.displayType == "icon" then return "icon", ST.Indicator.IconSettings(group) end
    if settings.displayType == "text" then return "text", settings.text end
    return "texture", settings.signal
end

function CooldownCompanion.ApplyIndicatorIconVisual(host, settings)
    local iconFrame = CooldownCompanion.EnsureIndicatorIconVisual(host)
    local width, height = CooldownCompanion.GetIndicatorIconDimensions(settings)
    local borderSize = settings.borderSize or 0
    local borderRenderMode = ST.GetBorderRenderMode(settings)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(iconFrame, borderSize, borderRenderMode)
    local iconTint = settings.iconTintColor or { 1, 1, 1, 1 }
    local backgroundColor = settings.backgroundColor or { 0, 0, 0, 0.5 }
    local borderColor = settings.borderColor or { 0, 0, 0, 1 }

    CooldownCompanion:ResetTextureIndicatorRootState(host)
    CooldownCompanion.HideIndicatorDisplayVisuals(host)

    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._activeDisplayType = "icon"
    host._indicatorBaseVisualsReady = nil
    host._indicatorTextBaseColor = nil
    host._indicatorIconBaseColor = CopyColor(iconTint) or { 1, 1, 1, 1 }

    host:SetSize(width, height)
    host.visualRoot:SetSize(width, height)

    iconFrame:SetSize(width, height)
    iconFrame.bg:SetColorTexture(
        backgroundColor[1] or 0,
        backgroundColor[2] or 0,
        backgroundColor[3] or 0,
        backgroundColor[4] ~= nil and backgroundColor[4] or 0.5
    )
    iconFrame.icon:ClearAllPoints()
    iconFrame.icon:SetPoint("TOPLEFT", borderLayoutSize, -borderLayoutSize)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", -borderLayoutSize, borderLayoutSize)
    iconFrame.icon:SetTexture(settings.manualIcon)
    iconFrame.icon:SetVertexColor(
        iconTint[1] or 1,
        iconTint[2] or 1,
        iconTint[3] or 1,
        iconTint[4] ~= nil and iconTint[4] or 1
    )
    ST._ApplyIconTexCoord(iconFrame.icon, width, height, settings.iconZoom)

    for _, border in ipairs(iconFrame.borderTextures) do
        border:SetColorTexture(
            borderColor[1] or 0,
            borderColor[2] or 0,
            borderColor[3] or 0,
            borderColor[4] ~= nil and borderColor[4] or 1
        )
        -- Shared border sets start hidden; the positions helper never shows.
        border:Show()
    end
    ST._ApplyBorderEdgePositions(iconFrame.borderTextures, iconFrame, borderSize, borderRenderMode)
    iconFrame:Show()

    return true
end


function CooldownCompanion:GetIndicatorDisplayVisibilityState(group, frame, driverButton, displayType, settings, isConditionsIndicator)
    local groupedPreviewFrame = GetGroupedPreviewContainerFrame(group, driverButton and driverButton._groupId)
    local combatForcedLock = self._combatForcedLock == true
    local isCursorAnchored = self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group)
    local isCursorLayoutPreview = driverButton
        and self.IsCursorAnchorLayoutPreviewGroupActive
        and self:IsCursorAnchorLayoutPreviewGroupActive(driverButton._groupId)
        or false
    local state = {
        isCursorLayoutPreview = isCursorLayoutPreview,
        isGroupedPreview = groupedPreviewFrame ~= nil,
        groupedPreviewFrame = groupedPreviewFrame,
        isUnlocked = not isCursorAnchored and not combatForcedLock and group and (group.locked == false or groupedPreviewFrame ~= nil),
        triggerMatched = isConditionsIndicator and frame and frame:IsShown() and DoesIndicatorMatch(frame) or false,
        showDisplay = false,
    }

    -- A Nameplate Reminder has no screen display and no mover: it draws only
    -- on the nameplates (Core/NameplateReminders.lua). Unlocked, it shows on
    -- the target's nameplate instead (Core/NameplateTargetView.lua).
    if settings and ST.Indicator.IsNameplate(group) then
        ST._NameplateTargetView.NoteUnlocked(driverButton and driverButton._groupId, state.isUnlocked == true)
        state.isUnlocked = false
        state.bypassModuleAlpha = false
        return state
    end
    if settings then
        if state.isCursorLayoutPreview then
            state.showDisplay = true
        elseif isConditionsIndicator then
            state.showDisplay = state.triggerMatched or state.isUnlocked
        elseif state.isUnlocked then
            state.showDisplay = true
        elseif driverButton:GetParent()
            and driverButton:GetParent():IsShown()
            and not driverButton:GetParent()._combatForcedHidden
            and not (driverButton._rawVisibilityHidden == true) then
            state.showDisplay = true
        end
    end

    state.triggerSoundVisible = settings ~= nil and state.triggerMatched and state.showDisplay
    state.bypassModuleAlpha = state.isCursorLayoutPreview
        or state.isUnlocked
    return state
end

function CooldownCompanion:RenderIndicatorDisplay(host, driverButton, group, settings, displayType, isConditionsIndicator, effectsActive)
    host._indicatorTeardownFor = nil
    host._ccPresenceMode = nil
    host:SetFrameStrata(driverButton:GetFrameStrata())
    host:SetFrameLevel((driverButton:GetFrameLevel() or 1) + 20)
    return ST.Indicator.Render(host, driverButton, group, false, nil, effectsActive,
        displayType == "icon" and settings or nil)
end

-- Locked aura Indicators keep the ordinary host for anchoring,
-- load visibility, and alpha, but render their production pixels only beneath
-- Blizzard's AuraButton. This prepares the safe outer shell without touching
-- any AuraContainer descendant; AuraDisplay styles that subtree OOC.
function CooldownCompanion:PrepareManagedAuraTextureDisplay(host, driverButton, settings, revealRuntime)
    local group = driverButton._groupId and ResolveGroup(driverButton._groupId)
    if ST.IsIndicatorGroup(group) then settings = ST.Indicator.NativeSettings(group) end
    local resolvedSourceType = self:ResolveAuraTextureAsset(
        settings.sourceType,
        settings.sourceValue,
        settings.mediaType
    )
    local geometry = self:GetIndicatorTextureRenderGeometry(settings)
    if not resolvedSourceType or not geometry then
        return false
    end

    -- Anything that repaints the host invalidates the teardown latch.
    host._indicatorTeardownFor = nil
    host._ccPresenceMode = nil
    host:SetFrameStrata(driverButton:GetFrameStrata())
    host:SetFrameLevel((driverButton:GetFrameLevel() or 1) + 20)
    SyncAuraTextureControlLevels(host, false)
    StopAllTextureIndicatorEffects(host)
    CooldownCompanion.HideIndicatorDisplayVisuals(host)
    host:SetSize(geometry.boundsWidth, geometry.boundsHeight)
    if host.visualRoot then
        host.visualRoot:SetSize(geometry.boundsWidth, geometry.boundsHeight)
        host.visualRoot:SetAlpha(0)
    end
    if host.auraRuntimeRoot then
        host.auraRuntimeRoot:SetAlpha(revealRuntime and 1 or 0)
    end
    host._activeDisplayType = nil
    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._indicatorBaseVisualsReady = nil
    return true
end

local function PlaceIndicatorDisplay(self, host, group, sharedSettings, groupId, groupedPreviewFrame)
    if not host._isDragging then
        local isCursorAnchored = self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group)
        if isCursorAnchored and self.AnchorFrameToCursor then
            self:AnchorFrameToCursor(host, group.anchor)
        else
            local currentPoint, currentRelativeFrame, _, currentX, currentY = host:GetPoint(1)
            host:ClearAllPoints()
            local anchorTargetFrame = GetIndicatorResolvedAnchorFrame(group, sharedSettings, groupId)
            if anchorTargetFrame then
                host:SetPoint(
                    sharedSettings.point or "TOPLEFT",
                    anchorTargetFrame,
                    sharedSettings.relativePoint or "BOTTOMLEFT",
                    sharedSettings.x or 0,
                    sharedSettings.y or -5
                )
            elseif HasIndicatorAnchorTarget(sharedSettings) then
                host:SetPoint(sharedSettings.point, UIParent, sharedSettings.relativePoint, sharedSettings.x, sharedSettings.y)
            elseif groupedPreviewFrame then
                local preserveRelativeOffset = host._wrapperManaged
                    and currentRelativeFrame == groupedPreviewFrame
                    and currentX ~= nil
                    and currentY ~= nil
                    and groupedPreviewFrame._dragInProgress == true
                if preserveRelativeOffset then
                    host:SetPoint(currentPoint or sharedSettings.point or "CENTER", groupedPreviewFrame, "CENTER", currentX, currentY)
                else
                    local screenAnchorX, screenAnchorY, point = GetIndicatorScreenAnchorPoint(sharedSettings)
                    local containerX, containerY = groupedPreviewFrame:GetCenter()
                    if screenAnchorX and screenAnchorY and containerX and containerY then
                        host:SetPoint(point or sharedSettings.point or "CENTER", groupedPreviewFrame, "CENTER", screenAnchorX - containerX, screenAnchorY - containerY)
                    else
                        host:SetPoint(sharedSettings.point, UIParent, sharedSettings.relativePoint, sharedSettings.x, sharedSettings.y)
                    end
                end
            else
                host:SetPoint(sharedSettings.point, UIParent, sharedSettings.relativePoint, sharedSettings.x, sharedSettings.y)
            end
        end
    end
end

-- A panel-owned, nonvisual anchor rectangle. It never belongs to the source
-- button or its native aura subtree, and stays usable when either is absent.
-- Both this rectangle and the visible host use the same placement writer.
function CooldownCompanion:UpdateIndicatorAnchorBody(frame, group, dragHost)
    if not frame or not ST.IsIndicatorGroup(group) then return end
    local body = frame._indicatorAnchorBody
    if InCombatLockdown() and (frame:IsProtected() or (body and body:IsProtected())) then
        frame._anchorDirty = true
        return body, true
    end
    if not body then
        body = CreateFrame("Frame", nil, UIParent)
        body:EnableMouse(false)
        body:SetClampedToScreen(true)
        body.groupId = frame.groupId
        frame._indicatorAnchorBody = body
    end
    frame._indicatorAnchorBodyActive = true
    local settings = self:GetIndicatorTextureSettings(group)
    local display = ST.Indicator.Settings(group)
    local width, height
    if display.displayType == "texture" then
        local geometry = self:GetIndicatorTextureRenderGeometry(settings)
        width, height = geometry.boundsWidth, geometry.boundsHeight
    elseif display.displayType == "icon" then
        width, height = self.GetIndicatorIconDimensions(self.NormalizeIndicatorIconSettings(display.icon))
    else
        width, height = display.text.width or 180, display.text.height or 48
    end
    body:SetSize(width, height)
    if dragHost and dragHost._isDragging then
        -- Temporary positional following only; no visibility/alpha inheritance.
        body:ClearAllPoints()
        body:SetPoint("CENTER", dragHost, "CENTER", 0, 0)
    else
        local previewFrame = GetGroupedPreviewContainerFrame(group, frame.groupId)
        body._wrapperManaged = previewFrame ~= nil
        PlaceIndicatorDisplay(self, body, group, settings, frame.groupId, previewFrame)
    end
    self:RefreshIndicatorAnchorAlpha(frame, group)
    return body
end

function CooldownCompanion:FinalizeIndicatorDisplay(host, frame, driverButton, group, settings, displayType, isConditionsIndicator, visibilityState)
    -- This is the only path that shows the host, so it clears the teardown latch.
    host._indicatorTeardownFor = nil
    local sharedSettings = CooldownCompanion:GetIndicatorAnchorSettings(group) or {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }

    PlaceIndicatorDisplay(self, host, group, sharedSettings, driverButton and driverButton._groupId,
        visibilityState and visibilityState.groupedPreviewFrame)
    host:Show()

    host._unlockGhost = frame and frame._unlockGhost or nil
    local bypassAlpha = host._unlockGhost and 0.4 or 1
    local honorSourceVisibility = ST.Indicator.Settings(group).sourceVisibility ~= false
    local visibilityAlpha = honorSourceVisibility and Clamp(driverButton._rawVisibilityAlphaOverride or 1, 0, 1) or 1
    if visibilityState.bypassModuleAlpha then
        StopIndicatorAlphaSync(host)
        host:SetAlpha(bypassAlpha)
    else
        -- The owner supplies natural panel alpha; source dimming belongs only
        -- to this display and must never leak into downstream panel anchors.
        StartIndicatorAlphaSync(host, frame, visibilityAlpha)
    end

    local indicatorSettings = ST.Indicator.Settings(group)
    local savedSettings = indicatorSettings and indicatorSettings.signal
    local hasSavedDisplay = false
    if displayType == "texture" then
        hasSavedDisplay = type(savedSettings) == "table" and savedSettings.sourceType ~= nil
    elseif displayType == "icon" then
        hasSavedDisplay = settings.manualIcon ~= nil
    elseif displayType == "text" then
        -- Text Only has a saved display area; its readouts need no legacy value.
        hasSavedDisplay = indicatorSettings ~= nil
    end
    local containerId = group and group.parentContainerId or nil
    local isGroupedPreviewSelected = visibilityState.isGroupedPreview
        and containerId
        and self.IsContainerPanelSelected
        and self:IsContainerPanelSelected(containerId, driverButton._groupId)
        or false
    local isGroupedPreviewHovered = visibilityState.isGroupedPreview
        and containerId
        and self.IsContainerPanelHovered
        and self:IsContainerPanelHovered(containerId, driverButton._groupId)
        or false
    -- Cursor panels edit through the dummy cursor's selection gate for both
    -- individual unlocks and Arrange Mode. Unselected parked hosts remain
    -- clickable so a click can select them.
    local isCursorPreviewSelected = visibilityState.isCursorLayoutPreview
        and self.IsCursorAnchorLayoutPreviewSelected
        and self:IsCursorAnchorLayoutPreviewSelected(driverButton._groupId)
        or false
    local independentPanelMoverShown = visibilityState.isGroupedPreview
        or self._arrangeSoloContainerId == nil
        or self._arrangeSelectedPanelId == driverButton._groupId
    host._hasSavedDisplay = hasSavedDisplay
    host._dragEnabled = (visibilityState.isUnlocked
        and hasSavedDisplay
        and independentPanelMoverShown
        and (not visibilityState.isGroupedPreview or isGroupedPreviewSelected))
        or (isCursorPreviewSelected and hasSavedDisplay)
    host._wrapperManaged = visibilityState.isGroupedPreview or nil
    SetTextureHostMouseEnabled(host, (host._dragEnabled == true and not visibilityState.isGroupedPreview)
        or visibilityState.isCursorLayoutPreview)
    SetAuraTextureOutlineShown(
        host,
        visibilityState.isGroupedPreview and isGroupedPreviewSelected or false,
        visibilityState.isGroupedPreview and isGroupedPreviewHovered or false
    )
    local showHeader = host._dragEnabled == true and (not visibilityState.isGroupedPreview or isGroupedPreviewSelected)
    if showHeader then EnsureAuraTextureDragHandle(host) end
    if host.dragHandle and host.coordLabel then
        host.dragHandle.text:SetText(group and group.name or "Indicator")
        if isCursorPreviewSelected then
            -- The label shows the saved cursor offset, matching what a drag
            -- or nudge writes back to the anchor.
            local anchor = group and group.anchor
            UpdateTextureHostCoordLabel(host, (anchor and tonumber(anchor.x)) or 0, (anchor and tonumber(anchor.y)) or 0)
        elseif visibilityState.isGroupedPreview and not HasIndicatorAnchorTarget(sharedSettings) then
            local displayX, displayY = GetTextureHostDisplayCoords(
                host,
                sharedSettings.point or "CENTER",
                sharedSettings.relativePoint or "CENTER"
            )
            if displayX == nil or displayY == nil then
                if host._isDragging then
                    local _, _, _, currentX, currentY = host:GetPoint()
                    displayX = currentX
                    displayY = currentY
                else
                    displayX = sharedSettings.x
                    displayY = sharedSettings.y
                end
            end
            UpdateTextureHostCoordLabel(host, displayX, displayY)
        elseif not visibilityState.isGroupedPreview and host._isDragging then
            local _, _, _, currentX, currentY = host:GetPoint()
            UpdateTextureHostCoordLabel(host, currentX, currentY)
        else
            UpdateTextureHostCoordLabel(host, sharedSettings.x, sharedSettings.y)
        end
        SyncAuraTextureControlLevels(host, visibilityState.isGroupedPreview and isGroupedPreviewSelected)
        SetAuraTextureDragControlsShown(host, showHeader, frame and frame._unlockGhost)
    end
    if driverButton:GetAlpha() ~= 0 then
        driverButton:SetAlpha(0)
        driverButton._lastVisAlpha = 0
    end
    if ST.SetFrameClickThroughRecursive then
        -- Every hidden source, including an aura Indicator's extra sources.
        if frame and type(frame.buttons) == "table" then
            for _, backingButton in ipairs(frame.buttons) do
                ST.SetFrameClickThroughRecursive(backingButton, true, true)
            end
        else
            ST.SetFrameClickThroughRecursive(driverButton, true, true)
        end
    end

end

-- Chrome for a PARKED cursor-anchored Indicator. The cursor-preview
-- owner calls this when parking state or selection changes; the periodic
-- visibility refresh computes the same answers, so the two never fight.
-- Selection shows the host's own mover chrome; parked-unselected keeps the
-- host bare but clickable so a click can select it.
function CooldownCompanion:RefreshCursorAnchoredHostControls(host, groupId, group, active, selected)
    if not host then
        return
    end

    local hasSavedDisplay = host._hasSavedDisplay == true
    local showControls = (active and selected and hasSavedDisplay) or false
    host._dragEnabled = showControls
    SetTextureHostMouseEnabled(host, showControls or active == true)
    if showControls then
        EnsureAuraTextureDragHandle(host)
        SyncAuraTextureControlLevels(host, false)
        local anchor = group and group.anchor
        UpdateTextureHostCoordLabel(host, (anchor and tonumber(anchor.x)) or 0, (anchor and tonumber(anchor.y)) or 0)
    end
    if host.dragHandle then
        SetAuraTextureDragControlsShown(host, showControls, nil)
    end
end

function CooldownCompanion:SetIndependentIndicatorMoverShown(groupId, shown)
    local group = groupId and ResolveGroup(groupId) or nil
    if not (group and ST.IsIndicatorGroup(group)) then
        return
    end
    local groupFrame = self.groupFrames and self.groupFrames[groupId]
    local driverButton = ST.Indicator.RuntimeSource(groupFrame, group)
    local host = driverButton and driverButton.auraTextureHost
    if not host then
        return
    end

    shown = shown == true and host._hasSavedDisplay == true
    host._dragEnabled = shown
    SetTextureHostMouseEnabled(host, shown)
    SetAuraTextureOutlineShown(host, false)
    if shown then EnsureAuraTextureDragHandle(host) end
    SyncAuraTextureControlLevels(host, false)
    SetAuraTextureDragControlsShown(host, shown, groupFrame and groupFrame._unlockGhost)
end

function CooldownCompanion:UpdateGroupedIndicatorPreviewSelection(groupId)
    local group = groupId and ResolveGroup(groupId) or nil
    if not (group and group.parentContainerId and ST.IsIndicatorGroup(group)) then
        return
    end

    if not (self.IsContainerUnlockPreviewActive and self:IsContainerUnlockPreviewActive(group.parentContainerId)) then
        return
    end

    local groupFrame = self.groupFrames and self.groupFrames[groupId] or nil
    local driverButton = ST.Indicator.RuntimeSource(groupFrame, group)
    local host = driverButton and driverButton.auraTextureHost or nil
    if not host then
        return
    end

    local isSelected = self.IsContainerPanelSelected and self:IsContainerPanelSelected(group.parentContainerId, groupId) or false
    local isHovered = self.IsContainerPanelHovered and self:IsContainerPanelHovered(group.parentContainerId, groupId) or false
    local showControls = isSelected and host._hasSavedDisplay == true
        and not (self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group))

    host._dragEnabled = showControls
    if showControls then EnsureAuraTextureDragHandle(host) end
    SyncAuraTextureControlLevels(host, showControls)
    -- Once a panel is selected, its title-bar mover and information rows are
    -- the only visible arrange chrome; the selection itself is already clear
    -- from those controls, so the standalone outline would be redundant.
    local containerHasSelection = self.GetContainerSelectedGroupId
        and self:GetContainerSelectedGroupId(group.parentContainerId) ~= nil
        or false
    SetAuraTextureOutlineShown(host, false, not containerHasSelection and isHovered)

    SetAuraTextureDragControlsShown(host, showControls, groupFrame and groupFrame._unlockGhost)
end

function CooldownCompanion:StartGroupedIndicatorPreviewHostDrag(groupId, containerId)
    local group = groupId and ResolveGroup(groupId) or nil
    if self._combatForcedLock or not (group and group.parentContainerId == containerId) then
        return false
    end
    if self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group) then
        return false
    end

    local groupFrame = self.groupFrames and self.groupFrames[groupId] or nil
    local driverButton = ST.Indicator.RuntimeSource(groupFrame, group)
    local host = driverButton and driverButton.auraTextureHost or nil
    if not (host and host:IsShown()) then
        return false
    end
    if host._dragEnabled ~= true or host._hasSavedDisplay ~= true then
        return false
    end
    if InCombatLockdown() and host:IsProtected() then
        return false
    end

    return BeginTextureHostDrag(host)
end

function CooldownCompanion:StopGroupedIndicatorPreviewHostDrag(groupId, containerId)
    local group = groupId and ResolveGroup(groupId) or nil
    if not (group and group.parentContainerId == containerId) then
        return
    end

    local groupFrame = self.groupFrames and self.groupFrames[groupId] or nil
    local driverButton = ST.Indicator.RuntimeSource(groupFrame, group)
    local host = driverButton and driverButton.auraTextureHost or nil
    if not host then
        return
    end

    FinishTextureHostDrag(host)
end

local function RoundGroupedIndicatorOffset(value)
    return math_floor(((tonumber(value) or 0) * 10) + 0.5) / 10
end

local function ApplyGroupedIndicatorSettingsDelta(settings, deltaX, deltaY)
    if not settings then
        return false
    end
    if deltaX == nil and deltaY == nil then
        return false
    end

    settings.x = RoundGroupedIndicatorOffset((tonumber(settings.x) or 0) + (tonumber(deltaX) or 0))
    settings.y = RoundGroupedIndicatorOffset((tonumber(settings.y) or 0) + (tonumber(deltaY) or 0))
    return true
end

function CooldownCompanion:SyncGroupedIndicatorPreviewSettings(containerId, deltaX, deltaY)
    if not (containerId and self.GetPanels) then
        return
    end

    local panels = self:GetPanels(containerId)
    for _, panelInfo in ipairs(panels) do
        local group = panelInfo.group
        if group and ST.IsIndicatorGroup(group) then
            local groupFrame = self.groupFrames and self.groupFrames[panelInfo.groupId] or nil
            local driverButton = ST.Indicator.RuntimeSource(groupFrame, group)
            local host = driverButton and driverButton.auraTextureHost or nil
            local settings = self:GetIndicatorTextureSettings(group)

            local didSync = false
            local hasIndicatorAnchorTarget = HasIndicatorAnchorTarget(settings)
            if host
                and settings
                and not hasIndicatorAnchorTarget
                and self.IsGroupVisibleInUnlockPreview
                and self:IsGroupVisibleInUnlockPreview(panelInfo.groupId, {
                    group = group,
                    groupFrame = groupFrame,
                    checkCharVisibility = true,
                })
                and SaveGroupedIndicatorPreviewSettings(host, group, settings, panelInfo.groupId)
            then
                didSync = true
                UpdateTextureHostCoordLabel(host, settings.x, settings.y)
            end
            if not didSync
                and not hasIndicatorAnchorTarget
                and ApplyGroupedIndicatorSettingsDelta(settings, deltaX, deltaY)
            then
                if host and host.coordLabel and host:IsShown() then
                    UpdateTextureHostCoordLabel(host, settings.x, settings.y)
                end
            end
        end
    end
end

function CooldownCompanion:UpdateAuraTextureVisual(button)
    if not button then
        return
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not ST.IsIndicatorGroup(group) then
        self:HideAuraTextureVisual(button)
        return
    end

    local frame = button:GetParent()
    local isConditionsIndicator = self:IsConditionsIndicatorGroup(group)
    local driverButton = ST.Indicator.RuntimeSource(frame, group)
    if not driverButton then
        self:HideAuraTextureVisual(button)
        return
    end

    local displayType, settings = CooldownCompanion.ResolveActiveIndicatorDisplay(driverButton)
    self:UpdateIndicatorAnchorBody(frame, group, driverButton.auraTextureHost)
    local visibilityState = self:GetIndicatorDisplayVisibilityState(group, frame, driverButton, displayType, settings, isConditionsIndicator)

    if isConditionsIndicator and self.UpdateConditionsIndicatorSoundAlerts then
        self:UpdateConditionsIndicatorSoundAlerts(frame, group, visibilityState.triggerSoundVisible)
    end

    if not settings or not visibilityState.showDisplay then
        self:HideAuraTextureVisual(driverButton)
        if driverButton:GetAlpha() ~= 0 then
            driverButton:SetAlpha(0)
            driverButton._lastVisAlpha = 0
        end
        return
    end

    local host = self:EnsureAuraTextureHost(driverButton)
    local auraControlled = not isConditionsIndicator
        and self:IsIndicatorAuraDisplayEnabled(group, driverButton.buttonData)
    -- Aura Indicators render production artwork only inside their native slot.
    -- Reveal it once the access-gated rebind has installed this source's token;
    -- a pooled host may still carry the previous source's slot. Layout/unlock
    -- previews use the ordinary saved-design render instead.
    local slotToken = driverButton._auraSlotHostToken
    local hasBoundSlot = slotToken ~= nil and slotToken == driverButton.buttonData
    local useManagedRuntime = auraControlled
        and not visibilityState.bypassModuleAlpha
    -- While Missing and aura lists: the ordinary host keeps placement and
    -- alpha but draws nothing; the display is painted into the presence
    -- copies, which Blizzard's trackers uncover only while the auras match
    -- (one copy, or one per aura for Any). Unlocked and layout previews show
    -- the saved design on the ordinary host instead.
    local presenceRuntime = ST.Indicator.UsesPresence(group)
        and not visibilityState.bypassModuleAlpha
    local presences = presenceRuntime and self:GetIndicatorPresenceHosts(driverButton)
    local presence = presences and presences[1]
    local shown
    if presence then
        -- Extra sources' rules hide the drawing and its effects; the trackers
        -- and the auras' sounds keep running underneath.
        local rulesPass = ST.Indicator.ExtraSourcesMatch(frame, group)
        -- Every copy draws the same design: once the first finds its style
        -- unchanged, the others only need their effects stepped.
        local styleBefore = presence._indicatorStyle
        presence._ccPresenceReleased = nil
        shown = ST.Indicator.Render(presence, driverButton, group, false, nil, rulesPass,
            displayType == "icon" and settings or nil)
        local restyled = presence._indicatorStyle ~= styleBefore
        for index = 2, #presences do
            local copy = presences[index]
            if restyled or copy._ccPresenceReleased or not copy._indicatorStyle then
                copy._ccPresenceReleased = nil
                ST.Indicator.Render(copy, driverButton, group, false, nil, rulesPass,
                    displayType == "icon" and settings or nil)
            elseif shown then
                self:ApplyIndicatorEffects(copy, driverButton, group, rulesPass == true)
            end
        end
        -- Only a successful render repaints the host. A design with nothing to
        -- draw leaves the teardown latch alone, so the hide below stays cheap.
        if shown then
            host._indicatorTeardownFor = nil
            -- Written only on change: these sit on the per-update path.
            local strata, hostLevel = driverButton:GetFrameStrata(), (driverButton:GetFrameLevel() or 1) + 20
            if not host._ccPresenceMode or host:GetFrameStrata() ~= strata or host:GetFrameLevel() ~= hostLevel then
                host:SetFrameStrata(strata)
                host:SetFrameLevel(hostLevel)
                SyncAuraTextureControlLevels(host, false)
            end
            if not host._ccPresenceMode then
                -- Entering presence mode: the ordinary host draws nothing from
                -- here on, so its own visuals are cleared once, not every
                -- update. Every other render path clears this latch.
                host._ccPresenceMode = true
                StopAllTextureIndicatorEffects(host)
                CooldownCompanion.HideIndicatorDisplayVisuals(host)
                if host.visualRoot then host.visualRoot:SetAlpha(0) end
                if host.auraRuntimeRoot then host.auraRuntimeRoot:SetAlpha(0) end
                host._activeDisplayType, host._activeTextureSettings, host._activeTextureGeometry = nil, nil, nil
            end
            local level = host:GetFrameLevel() + 1
            for _, copy in ipairs(presences) do
                if copy:GetFrameLevel() ~= level then copy:SetFrameLevel(level) end
            end
            -- Placement, anchors and drag use the ordinary host: size it from
            -- the drawing (a CC-set size, never a measured one).
            local width, height = presence:GetSize()
            local hostWidth, hostHeight = host:GetSize()
            if hostWidth ~= width or hostHeight ~= height then host:SetSize(width, height) end
        end
        for _, copy in ipairs(presences) do copy:SetShown(shown and rulesPass) end
        -- Also During Pandemic: the aura's native display (gated by Blizzard
        -- to the refresh window) rides the texture layer, so the layer follows
        -- the same rules as the drawing. Written only on change.
        if host.auraRuntimeRoot then
            local twinAlpha = shown and rulesPass and ST.Indicator.AlsoDuringPandemic(group)
                and self:HasIndicatorPandemicTwin(driverButton) and 1 or 0
            if host.auraRuntimeRoot:GetAlpha() ~= twinAlpha then host.auraRuntimeRoot:SetAlpha(twinAlpha) end
        end
    elseif presenceRuntime then
        -- Not bound yet (the rebind is queued or deferred by combat): keep
        -- the host placed and sized from the saved design, drawing nothing.
        shown = self:PrepareManagedAuraTextureDisplay(host, driverButton, settings, false)
    elseif useManagedRuntime then
        -- A While Missing tracker can stay bound until a combat-deferred
        -- rebind parks it; its drawing must not outlive the mode switch.
        ReleasePresenceDisplay(driverButton)
        -- Extra sources' rules gate only the reveal alpha. The host and the
        -- native slot stay up, so the aura's own sounds keep following it.
        shown = self:PrepareManagedAuraTextureDisplay(host, driverButton, settings,
            hasBoundSlot and ST.Indicator.ExtraSourcesMatch(frame, group))
    else
        ReleasePresenceDisplay(driverButton)
        if host.auraRuntimeRoot then
            host.auraRuntimeRoot:SetAlpha(0)
        end
        if host.visualRoot then
            host.visualRoot:SetAlpha(1)
        end
        shown = self:RenderIndicatorDisplay(
            host,
            driverButton,
            group,
            settings,
            displayType,
            isConditionsIndicator,
            visibilityState.triggerMatched
        )
    end

    if not shown then
        self:HideAuraTextureVisual(driverButton)
        if driverButton:GetAlpha() ~= 0 then
            driverButton:SetAlpha(0)
            driverButton._lastVisAlpha = 0
        end
        return
    end

    self:FinalizeIndicatorDisplay(host, frame, driverButton, group, settings, displayType, isConditionsIndicator, visibilityState)
end

function CooldownCompanion:RefreshAllAuraTextureVisuals()
    self:RebuildPanelAlphaDependencyTargets()
    for _, frame in pairs(self.groupFrames or {}) do
        self:UpdateIndicatorAnchorBody(frame, ResolveGroup(frame.groupId))
        for _, button in ipairs(frame.buttons or {}) do
            self:UpdateAuraTextureVisual(button)
        end
    end
    if self.RefreshAllContainerWrappers then
        self:RefreshAllContainerWrappers()
    end
end

--- Re-place every Indicator display anchored to one panel.
--- Called when that panel's sectioned state flips: the frame a host is pointed
--- at changes hands between the panel frame and its base-cluster body, and a
--- host left on the outgoing one would keep resolving positionally -- a hidden
--- base anchor still reports its last rectangle -- so it would sit at a stale
--- spot rather than visibly break. An Indicator display's anchor lives in its
--- own display settings, not in group.anchor, which is why the panel and
--- container passes in ReanchorPanelSectionDependents cannot find these.
function CooldownCompanion:ReanchorIndicatorDependents(targetFrameName)
    if type(targetFrameName) ~= "string" then return end

    for groupId, frame in pairs(self.groupFrames or {}) do
        local group = ResolveGroup(groupId)
        if ST.IsIndicatorGroup(group) then
            local settings = CooldownCompanion:GetIndicatorAnchorSettings(group)
            if settings and settings.relativeTo == targetFrameName then
                local driverButton = ST.Indicator.RuntimeSource(frame, group)
                if driverButton then
                    self:UpdateAuraTextureVisual(driverButton)
                end
            end
        end
    end
end
