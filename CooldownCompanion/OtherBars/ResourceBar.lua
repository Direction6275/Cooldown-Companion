--[[
    CooldownCompanion - ResourceBar
    Displays player class resources (Rage, Energy, Combo Points, Runes, etc.)
    anchored to icon groups.

    Unlike CastBar (which manipulates Blizzard's secure frame), resource bars are
    fully addon-owned frames with no taint concerns.

    SECRET VALUES (12.0.x):
      - UnitPower/UnitPowerMax secrecy is evaluated at runtime through C_Secrets predicates.
      - Continuous resources are generally contextually secret; segmented resources are
        currently non-secret in observed builds.
      - StatusBar:SetValue(secret) and FontString:SetFormattedText("%d", secret)
        are used as secret-safe pass-through display paths.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local ClearStatusBarMotion = ST.ClearStatusBarMotion
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue
local SetStatusBarSegmentedValue = ST.SetStatusBarSegmentedValue
local UnbindDurationText = CooldownCompanion.UnbindDurationText

local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_sin = math.sin
local math_pi = math.pi
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue

local function UnbindFrameDurationText(frame)
    if frame and frame.text then
        UnbindDurationText(frame.text)
    end
end

------------------------------------------------------------------------
-- Imports from ResourceBarConstants / ResourceBarHelpers / ResourceBarVisuals
------------------------------------------------------------------------

local RB = ST._RB
local UPDATE_INTERVAL = RB.UPDATE_INTERVAL
local PERCENT_SCALE_CURVE = RB.PERCENT_SCALE_CURVE
local RAGING_MAELSTROM_SPELL_ID = RB.RAGING_MAELSTROM_SPELL_ID
local MW_AURA_SPELL_ID = RB.MW_AURA_SPELL_ID
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
local RESOURCE_MAELSTROM_WEAPON = RB.RESOURCE_MAELSTROM_WEAPON
local DEFAULT_RESOURCE_TEXT_FORMAT = RB.DEFAULT_RESOURCE_TEXT_FORMAT
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE
local DEFAULT_RESOURCE_TEXT_COLOR = RB.DEFAULT_RESOURCE_TEXT_COLOR
local INDEPENDENT_NUDGE_BTN_SIZE = RB.INDEPENDENT_NUDGE_BTN_SIZE
local IsBarsConfigActive = RB.IsBarsConfigActive
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local POWER_ATLAS_INFO = RB.POWER_ATLAS_INFO
local RESOURCE_COLOR_DEFS = RB.RESOURCE_COLOR_DEFS

-- Helpers
local GetResourceBarSettings = RB.GetResourceBarSettings
local IsVerticalResourceLayout = RB.IsVerticalResourceLayout
local GetResourceLayoutOrientation = RB.GetResourceLayoutOrientation
local IsVerticalFillReversed = RB.IsVerticalFillReversed
local GetResourcePrimaryLength = RB.GetResourcePrimaryLength
local GetResourceGlobalThickness = RB.GetResourceGlobalThickness
local GetResourceAnchorGap = RB.GetResourceAnchorGap
local GetVerticalSideFallback = RB.GetVerticalSideFallback
local GetEffectiveAnchorGroupId = RB.GetEffectiveAnchorGroupId
local GetPlayerClassID = RB.GetPlayerClassID
local GetSpecLayoutOrder = RB.GetSpecLayoutOrder
local GetResourceDisplayValue = RB.GetResourceDisplayValue
local GetResourceSegmentedSmoothing = RB.GetResourceSegmentedSmoothing
local GetResourceDisplayConfig = RB.GetResourceDisplayConfig
local GetAnchorOffset = RB.GetAnchorOffset
local RoundToTenths = RB.RoundToTenths
local ClampIndependentDimension = RB.ClampIndependentDimension
local UpdateIndependentStackDragState

local function UpdateIndependentStackCoordLabel(frame, x, y)
    if frame and frame._coordLabel then
        frame._coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(x or 0, y or 0))
    end
end

local CancelCoordinateEdit = ST.CancelCoordinateEdit
local CreateEditableCoordLabel = ST.CreateEditableCoordLabel

local function ComputeIndependentStackCoordinates(frame, anchor)
    local cx, cy = frame:GetCenter()
    local fw, fh = frame:GetSize()
    local relFrame = UIParent
    if anchor.relativeTo and anchor.relativeTo ~= "UIParent" then
        relFrame = CooldownCompanion:GetExternalAnchorFrame(anchor.relativeTo)
    end
    local tcx, tcy = relFrame:GetCenter()
    local tw, th = relFrame:GetSize()
    if not (cx and cy and fw and fh and tcx and tcy and tw and th) then return nil, nil end

    local fax, fay = GetAnchorOffset(anchor.point, fw, fh)
    local tax, tay = GetAnchorOffset(anchor.relativePoint, tw, th)
    return RoundToTenths((cx + fax) - (tcx + tax)), RoundToTenths((cy + fay) - (tcy + tay))
end

local function StopIndependentStackCoordUpdates(frame)
    frame._coordDragElapsed = nil
    frame._coordDragAnchor = nil
    frame:SetScript("OnUpdate", nil)
    if CooldownCompanion.EndDragSnapSession then
        CooldownCompanion:EndDragSnapSession(frame, false)
    end
end

local function IndependentStackCoordOnUpdate(self, elapsed)
    if not self._dragInProgress then
        StopIndependentStackCoordUpdates(self)
        return
    end

    self._coordDragElapsed = (self._coordDragElapsed or 0) + elapsed
    if self._coordDragElapsed < 0.05 then
        return
    end

    self._coordDragElapsed = 0
    local anchor = self._coordDragAnchor
    if anchor then
        local x, y = ComputeIndependentStackCoordinates(self, anchor)
        if x ~= nil and y ~= nil then
            UpdateIndependentStackCoordLabel(self, x, y)
        end
    end
    CooldownCompanion:UpdateDragSnapSession(self)
end

local function StartIndependentStackCoordUpdates(frame, anchor)
    frame._coordDragElapsed = 0
    frame._coordDragAnchor = anchor
    frame:SetScript("OnUpdate", IndependentStackCoordOnUpdate)
end

local DetermineActiveResources = RB.DetermineActiveResources
local GetResourceColors = RB.GetResourceColors
local IsUnitPowerSecret = RB.IsUnitPowerSecret
local IsUnitPowerMaxSecret = RB.IsUnitPowerMaxSecret
local GetSegmentedThresholdColorForValue = RB.GetSegmentedThresholdColorForValue
local IsResourceEnabled = RB.IsResourceEnabled
local IsSegmentedTextResource = RB.IsSegmentedTextResource
local ClearSegmentedText = RB.ClearSegmentedText
local SetSegmentedText = RB.SetSegmentedText

-- Visuals
local UpdateContinuousTickMarker = RB.UpdateContinuousTickMarker
local ApplyContinuousFillColor = RB.ApplyContinuousFillColor
local ApplyPixelBorders = RB.ApplyPixelBorders
local HidePixelBorders = RB.HidePixelBorders
local LayoutSegments = RB.LayoutSegments
local LayoutOverlaySegments = RB.LayoutOverlaySegments

-- Shared helper from ButtonFrame/Helpers.lua
local FormatTime = CooldownCompanion.FormatTime
-- Other ST imports
local CreateGlowContainer = ST._CreateGlowContainer
local SetBarAuraEffect = ST._SetBarAuraEffect

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local mwMaxStacks = 5

-- Runtime state for the aura-stack members whose shape can change while the
-- bars are already up: the Devourer pair, which swaps in place on the Void
-- Metamorphosis transition, and its dynamic maximums, which move with
-- talents and with what Collapsing Star costs.
--   watch    a suppressible member is enabled in this spec's list, so the
--            tick is worth the one aura read (armed by ApplyResourceBars,
--            from the unfiltered list, so the hidden half still arms it)
--   inMeta   the state the current materialization was built for
--   reapply  a rebuild was asked for from inside the tick loop
local stackSwapState = { watch = false, inMeta = false, reapply = false }

local isApplied = false
local onUpdateFrame = nil
local containerFrameAbove = nil
local containerFrameBelow = nil
local lastAppliedPrimaryLength = nil
local lastAppliedOrientation = nil
local lastAppliedLayout = nil
local lastAppliedIndependentStack = false
-- The aura host captures this table. Rebuild its active entries in place;
-- retained renderers belong to actual resources, never to list positions.
local resourceBarFrames = {}
local ResourceBars = { instances = {} }
-- Unlock-to-position assist, not a preview: the real bars are forced visible
-- so an independent stack can be dragged. Their data stays real (owner
-- ruling 2026-07-26 — previews live in the config canvas and nowhere else).
local isUnlockAssistActive = false
local savedContainerAlpha = nil
local alphaSyncFrame = nil
local lastAppliedBarSpacing = nil
local lastAppliedBarThickness = nil
local independentWrapperFrame = nil

function CooldownCompanion:GetIndependentResourceStackSnapFrame()
    return independentWrapperFrame and independentWrapperFrame._dragSnapRectFrame
end

function CooldownCompanion:GetIndependentResourceStackMoverChrome()
    local frame = independentWrapperFrame
    return frame and frame._dragHandle, frame and frame._coordLabel, frame and frame._nudger,
        frame and frame._resizeGrip, frame and frame._sizeLabel
end

function CooldownCompanion:SetIndependentResourceStackLocked(locked)
    local settings = GetResourceBarSettings()
    if not settings then return end
    local placementSettings = GetSpecLayoutOrder(settings)
    if not placementSettings then return end
    placementSettings.independentAnchorLocked = locked == true
    self:ApplyResourceBars()
    if self.RefreshUnlockToolbar then
        self:RefreshUnlockToolbar()
    end
end

function CooldownCompanion:CancelIndependentResourceStackDrag()
    local frame = independentWrapperFrame
    if not frame then return end
    if frame._dragInProgress then
        frame._dragCancelPending = true
        frame:StopMovingOrSizing()
        frame._dragInProgress = nil
        StopIndependentStackCoordUpdates(frame)
        self:EndMoverChromeFade(frame)
    end
    local settings = GetResourceBarSettings()
    UpdateIndependentStackDragState(settings, settings and GetSpecLayoutOrder(settings))
end

local segmentedUpdateScratch = {}
local HealthBar = RB.HealthBar
local lifecycleModule = nil

local function ResetResourceBarRuntimeState(frame, keepBorderVisuals)
    if not frame then return end
    ST.ChargeBarSegments.End(frame)
    UnbindFrameDurationText(frame)
    ClearStatusBarMotion(frame)
    frame:SetMovable(false)
    frame:EnableMouse(false)
    frame:RegisterForDrag()

    -- A visible renderer still belongs to the same resource. Its border
    -- already compares style and explicit geometry on update, so keep both
    -- the running effect and its key. Retirement stops the effect eagerly.
    local border = frame._ccMWMaxBorder
    if not keepBorderVisuals and border and border.key ~= "off" then
        border.key = "off"
        if border.glow then
            ST._StyleKitBarGlowRegions(border.glow, nil, border.host, false)
        end
    end
    frame:SetAlpha(1)
end

------------------------------------------------------------------------
-- Independent Stack Anchoring (entire resource bar stack to UIParent)
------------------------------------------------------------------------

local function EnsureIndependentStackConfig(settings, layout)
    layout = layout or GetSpecLayoutOrder(settings) or settings
    if type(layout.independentAnchor) ~= "table" then
        layout.independentAnchor = type(settings.independentAnchor) == "table" and CopyTable(settings.independentAnchor) or {}
    end
    local anchor = layout.independentAnchor
    anchor.point = anchor.point or "CENTER"
    anchor.relativePoint = anchor.relativePoint or "CENTER"
    anchor.x = tonumber(anchor.x) or 0
    anchor.y = tonumber(anchor.y) or 0
    if anchor.relativeTo ~= nil and type(anchor.relativeTo) ~= "string" then
        anchor.relativeTo = nil
    end
    layout.independentWidth = ClampIndependentDimension(layout.independentWidth or settings.independentWidth, 200)
    if layout.independentAnchorLocked == nil then
        layout.independentAnchorLocked = settings.independentAnchorLocked
    end
end

local function SaveIndependentStackAnchor(refreshConfig)
    if not independentWrapperFrame then return end
    local settings = GetResourceBarSettings()
    if not settings then return end
    local placementSettings = GetSpecLayoutOrder(settings)
    if not placementSettings then return end
    EnsureIndependentStackConfig(settings, placementSettings)

    local frame = independentWrapperFrame
    local anchor = placementSettings.independentAnchor

    local x, y = ComputeIndependentStackCoordinates(frame, anchor)
    if x == nil or y == nil then return end
    anchor.x = x
    anchor.y = y
    UpdateIndependentStackCoordLabel(frame, x, y)

    if refreshConfig and IsBarsConfigActive() and CooldownCompanion.RefreshConfigPanel then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function ApplyIndependentStackCoordinates(frame, x, y)
    local settings = GetResourceBarSettings()
    if not settings then return end
    local placementSettings = GetSpecLayoutOrder(settings)
    if not placementSettings then return end
    EnsureIndependentStackConfig(settings, placementSettings)

    local anchor = placementSettings.independentAnchor
    anchor.x = x
    anchor.y = y
    local relFrame = UIParent
    if anchor.relativeTo and anchor.relativeTo ~= "UIParent" then
        relFrame = CooldownCompanion:GetExternalAnchorFrame(anchor.relativeTo)
    end
    frame:ClearAllPoints()
    frame:SetPoint(anchor.point, relFrame, anchor.relativePoint, x, y)
    UpdateIndependentStackCoordLabel(frame, x, y)
    SaveIndependentStackAnchor(true)
end

function ST.LockIndependentResourceStackFromMover(frame)
    frame = frame or independentWrapperFrame
    if not frame then return end
    local settings = GetResourceBarSettings()
    if not settings then return end
    local placementSettings = GetSpecLayoutOrder(settings)
    if not placementSettings then return end
    -- Locking the soloed mover would strand every other mover solo-hidden;
    -- release the solo first (mirrors SetContainerLocked).
    if CooldownCompanion._arrangeSoloContainerId == "resource"
        and CooldownCompanion.SetArrangeSoloContainer then
        CooldownCompanion:SetArrangeSoloContainer(nil)
    end
    placementSettings.independentAnchorLocked = true
    frame._dragInProgress = nil
    StopIndependentStackCoordUpdates(frame)
    frame:StopMovingOrSizing()
    SaveIndependentStackAnchor(true)
    CooldownCompanion:EndMoverChromeFade(frame)
    UpdateIndependentStackDragState(settings, placementSettings)
    CooldownCompanion:CaptureArrangeResourceRecord()
    if CooldownCompanion.RefreshUnlockToolbar then
        CooldownCompanion:RefreshUnlockToolbar()
    end
    CooldownCompanion:CheckArrangeModeAutoExit()
end

local function CreateIndependentWrapperFrame()
    if independentWrapperFrame then return end

    local frame = CreateFrame("Frame", "CooldownCompanionResourceBarsIndependent", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(1, 1)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame._dragSnapRectFrame = CreateFrame("Frame", nil, frame)
    frame._dragSnapRectFrame:Hide()

    independentWrapperFrame = frame
end

local function EnsureIndependentStackMoverChrome(frame)
    if frame._dragHandle or InCombatLockdown() or CooldownCompanion._combatForcedLock then return end
    -- Drag handle (full-width, anchored to containers by UpdateIndependentStackChrome)
    local dragHandle = ST.MoverChrome.CreateHeader(frame, "Resource Bars", function()
        ST.LockIndependentResourceStackFromMover(frame)
    end, function() return { kind = "resource", focusId = "resource" } end)
    dragHandle:EnableMouse(false)
    dragHandle:RegisterForDrag()
    dragHandle:Hide()

    -- Hovering the name bar reveals precise controls. Selection belongs to
    -- the unlock toolbar; the title bar remains a drag/menu/lock surface.
    dragHandle:SetScript("OnEnter", function()
        ST.BeginMoverChromeHoverReveal(frame, function()
            CooldownCompanion:RefreshIndependentResourceStackMoverChrome()
        end)
    end)
    dragHandle:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            frame._focusClickSuppressed = nil
        end
    end)

    -- Nudger (4-direction pixel nudge, same pattern as custom aura bars)
    local nudger = ST.MoverChrome.CreateNudger(dragHandle, INDEPENDENT_NUDGE_BTN_SIZE, function(dx, dy)
        CancelCoordinateEdit(frame._coordLabel)
        CancelCoordinateEdit(frame._sizeLabel)
        local settings = GetResourceBarSettings()
        if not settings then return end
        local placementSettings = GetSpecLayoutOrder(settings)
        if not placementSettings then return end
        if placementSettings.independentAnchorLocked then return end
        frame:AdjustPointsOffset(dx, dy)
        -- Write position per step and update coord label (GroupFrame pattern)
        local _, _, _, x, y = frame:GetPoint()
        if x and y then
            EnsureIndependentStackConfig(settings, placementSettings)
            placementSettings.independentAnchor.x = RoundToTenths(x)
            placementSettings.independentAnchor.y = RoundToTenths(y)
            UpdateIndependentStackCoordLabel(frame, x, y)
        end
    end, function() SaveIndependentStackAnchor(true) end)
    nudger:EnableMouse(false)

    -- Coordinate label (parented to dragHandle, anchored by UpdateIndependentStackChrome)
    local coordLabel = ST.MoverChrome.CreateLabel(dragHandle)
    CreateEditableCoordLabel(
        coordLabel,
        function()
            local settings = GetResourceBarSettings()
            local placementSettings = settings and GetSpecLayoutOrder(settings)
            local anchor = placementSettings and placementSettings.independentAnchor
            return anchor and anchor.x or 0, anchor and anchor.y or 0
        end,
        function(x, y)
            ApplyIndependentStackCoordinates(frame, x, y)
        end,
        function()
            return frame._dragInProgress == true
                or (frame._resizeGrip and frame._resizeGrip._resizeActive == true)
        end
    )

    -- Width resize chrome (grip + wheel + typed label). Writes go to the
    -- per-spec layout table, mirroring the config slider; the grip anchors to
    -- the snap rect because the wrapper itself is a 1x1 pin.
    ST.AttachMoverWidthResize(frame, {
        dragHandle = dragHandle,
        coordLabel = coordLabel,
        gripAnchor = frame._dragSnapRectFrame,
        getWidth = function()
            local settings = GetResourceBarSettings()
            local placementSettings = settings and GetSpecLayoutOrder(settings)
            return placementSettings and placementSettings.independentWidth
                or (settings and settings.independentWidth)
                or 200
        end,
        setWidth = function(width)
            local settings = GetResourceBarSettings()
            local placementSettings = settings and GetSpecLayoutOrder(settings)
            if placementSettings then
                placementSettings.independentWidth = width
            end
        end,
        -- The independent stack's baseline stays editable even when individual
        -- resources customize their thickness.
        getHeight = function()
            local settings = GetResourceBarSettings()
            local placementSettings = settings and GetSpecLayoutOrder(settings)
            if not placementSettings then
                return 12
            end
            return ST.ResolveResourceBarGeometry(settings, placementSettings).thickness
        end,
        setHeight = function(height)
            local settings = GetResourceBarSettings()
            local placementSettings = settings and GetSpecLayoutOrder(settings)
            if not placementSettings then
                return
            end
            if RB.IsVerticalResourceLayout(settings) then
                placementSettings.barWidth = height
            else
                placementSettings.barHeight = height
            end
        end,
        isHeightEnabled = function()
            local settings = GetResourceBarSettings()
            local placementSettings = settings and GetSpecLayoutOrder(settings)
            return placementSettings ~= nil
        end,
        isVertical = function()
            local settings = GetResourceBarSettings()
            return RB.IsVerticalResourceLayout(settings) == true
        end,
        apply = function()
            CooldownCompanion:ApplyResourceBars()
        end,
        isUnlocked = function()
            local settings = GetResourceBarSettings()
            local placementSettings = settings and GetSpecLayoutOrder(settings)
            return placementSettings ~= nil
                and CooldownCompanion:IsResourceBarAnchorIndependent()
                and not placementSettings.independentAnchorLocked
                and not CooldownCompanion._combatForcedLock
        end,
        getAnchorPoint = function()
            local settings = GetResourceBarSettings()
            local placementSettings = settings and GetSpecLayoutOrder(settings)
            local anchor = placementSettings and placementSettings.independentAnchor
            return anchor and anchor.point or "CENTER"
        end,
    })

    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        CancelCoordinateEdit(coordLabel)
        CancelCoordinateEdit(frame._sizeLabel)
        local settings = GetResourceBarSettings()
        if not settings then return end
        local placementSettings = GetSpecLayoutOrder(settings)
        if not placementSettings then return end
        if placementSettings.independentAnchorLocked then return end
        if InCombatLockdown() then return end
        -- Dragging solos this mover, mirroring container header drags.
        if CooldownCompanion._arrangeModeActive and CooldownCompanion.SetArrangeSoloContainer then
            frame._focusClickSuppressed = true
            CooldownCompanion:SetArrangeSoloContainer("resource")
        end
        frame._dragCancelPending = nil
        frame._dragInProgress = true
        frame:StartMoving()
        CooldownCompanion:BeginMoverChromeFade(frame)
        CooldownCompanion:BeginDragSnapSession(frame, function(candidateFrame)
            return candidateFrame == frame or candidateFrame == frame._dragSnapRectFrame
        end)
        StartIndependentStackCoordUpdates(frame, placementSettings.independentAnchor)
    end)
    dragHandle:SetScript("OnDragStop", function()
        -- The release that ends this drag also fires OnMouseUp; it must not
        -- read as a focus-toggling click.
        frame._focusClickSuppressed = true
        local cancelSave = frame._dragCancelPending == true or CooldownCompanion._combatForcedLock
        frame._dragCancelPending = nil
        frame._dragInProgress = nil
        frame:StopMovingOrSizing()
        if not cancelSave then
            CooldownCompanion:UpdateDragSnapSession(frame)
        end
        local snapDX, snapDY = CooldownCompanion:EndDragSnapSession(frame, not cancelSave)
        if snapDX ~= nil or snapDY ~= nil then
            frame:AdjustPointsOffset(snapDX or 0, snapDY or 0)
        end
        StopIndependentStackCoordUpdates(frame)
        if cancelSave then
            CooldownCompanion:EndMoverChromeFade(frame)
            return
        end
        SaveIndependentStackAnchor(true)
        CooldownCompanion:EndMoverChromeFade(frame)
    end)

    dragHandle:SetPoint("BOTTOMLEFT", frame._dragSnapRectFrame, "TOPLEFT", 0, 2)
    dragHandle:SetPoint("BOTTOMRIGHT", frame._dragSnapRectFrame, "TOPRIGHT", 0, 2)
    coordLabel:SetPoint("TOPLEFT", frame._dragSnapRectFrame, "BOTTOMLEFT", 0, -2)
    coordLabel:SetPoint("TOPRIGHT", frame._dragSnapRectFrame, "BOTTOMRIGHT", 0, -2)
    frame._dragHandle = dragHandle
    frame._nudger = nudger
    frame._coordLabel = coordLabel
    local settings = GetResourceBarSettings()
    local layout = settings and GetSpecLayoutOrder(settings)
    local anchor = layout and layout.independentAnchor
    UpdateIndependentStackCoordLabel(frame, anchor and anchor.x, anchor and anchor.y)
    CooldownCompanion:ApplyMoverChromeFadeToFrames(dragHandle, coordLabel, nudger, frame._resizeGrip, frame._sizeLabel)
end

UpdateIndependentStackDragState = function(settings, placementSettings)
    if not independentWrapperFrame then return end
    local frame = independentWrapperFrame
    placementSettings = placementSettings or (settings and GetSpecLayoutOrder(settings)) or settings
    local unlocked = placementSettings
        and CooldownCompanion:IsResourceBarAnchorIndependent()
        and not placementSettings.independentAnchorLocked
        and not CooldownCompanion._combatForcedLock
        and not InCombatLockdown()
    if not unlocked and frame._dragInProgress then
        CooldownCompanion:CancelIndependentResourceStackDrag()
    end

    if unlocked and not CooldownCompanion:IsContainerArrangeChromeHidden("resource") then
        EnsureIndependentStackMoverChrome(frame)
    end
    ST.MoverChrome.UpdateIndependent(frame, "resource", unlocked)

    -- Force the bars visible while unlocked so they can be dragged. Their
    -- contents stay real — a health bar shows your health, a shell bar shows
    -- its (empty) frame instead of nothing at all.
    if unlocked and not isUnlockAssistActive then
        CooldownCompanion:StartResourceBarUnlockAssist()
        frame._cdcUnlockAssist = true
    elseif not unlocked and frame._cdcUnlockAssist then
        frame._cdcUnlockAssist = false
        CooldownCompanion:StopResourceBarUnlockAssist()
    end
end

-- Re-present the mover chrome from current settings; the toolbar's
-- chrome-hide and solo controls call this when their session state flips.
function CooldownCompanion:RefreshIndependentResourceStackMoverChrome()
    UpdateIndependentStackDragState(GetResourceBarSettings())
end

local function HideIndependentWrapperFrame()
    if not independentWrapperFrame then return end
    CooldownCompanion:CancelIndependentResourceStackDrag()
    independentWrapperFrame._dragInProgress = nil
    StopIndependentStackCoordUpdates(independentWrapperFrame)
    independentWrapperFrame:Hide()
    if independentWrapperFrame._dragHandle then
        independentWrapperFrame._dragHandle:Hide()
    end
    if independentWrapperFrame._nudger then
        independentWrapperFrame._nudger:Hide()
    end
    if independentWrapperFrame._coordLabel then
        independentWrapperFrame._coordLabel:Hide()
    end
    if independentWrapperFrame._sizeLabel then
        independentWrapperFrame._sizeLabel:Hide()
    end
    if independentWrapperFrame._cdcUnlockAssist then
        independentWrapperFrame._cdcUnlockAssist = false
        CooldownCompanion:StopResourceBarUnlockAssist()
    end
end

--- Re-anchor drag handle and coord label to frame the bar content.
--- Called after containers are positioned and RelayoutBars() completes.
local function UpdateIndependentStackChrome(isVerticalLayout, placementSettings, primaryLength, gap, aboveThickness, belowThickness)
    if not independentWrapperFrame then return end
    if not containerFrameAbove or not containerFrameBelow then return end
    local frame = independentWrapperFrame

    -- The containers forbid untrusted layout scripts. Keep the mover anchored
    -- to its ordinary 1x1 position frame, using the dimensions RelayoutBars just
    -- supplied, so its backdrop scripts and snap/resize geometry remain usable.
    local aboveShown = containerFrameAbove:IsShown()
    local belowShown = containerFrameBelow:IsShown()
    local snapRect = frame._dragSnapRectFrame
    if not snapRect then return end
    snapRect:ClearAllPoints()
    if not aboveShown and not belowShown then
        snapRect:Hide()
        return
    end

    -- Include the half-pixel from the wrapper's center to its anchoring edge.
    local edgeOffset = 0.5 + gap
    local left, right, top, bottom
    if isVerticalLayout then
        left = aboveShown and -edgeOffset - aboveThickness or edgeOffset
        right = belowShown and edgeOffset + belowThickness or -edgeOffset
        top, bottom = primaryLength / 2, -primaryLength / 2
    else
        left, right = -primaryLength / 2, primaryLength / 2
        top = aboveShown and edgeOffset + aboveThickness or -edgeOffset
        bottom = belowShown and -edgeOffset - belowThickness or edgeOffset
    end
    snapRect:SetPoint("TOPLEFT", frame, "CENTER", left, top)
    snapRect:SetPoint("BOTTOMRIGHT", frame, "CENTER", right, bottom)
    snapRect:Show()

    local dragHandle = frame._dragHandle
    if dragHandle then
        dragHandle:ClearAllPoints()
        dragHandle:SetPoint("BOTTOMLEFT", snapRect, "TOPLEFT", 0, 2)
        dragHandle:SetPoint("BOTTOMRIGHT", snapRect, "TOPRIGHT", 0, 2)
    end

    local coordLabel = frame._coordLabel
    if coordLabel then
        coordLabel:ClearAllPoints()
        coordLabel:SetPoint("TOPLEFT", snapRect, "BOTTOMLEFT", 0, -2)
        coordLabel:SetPoint("TOPRIGHT", snapRect, "BOTTOMRIGHT", 0, -2)

        local settings = GetResourceBarSettings()
        placementSettings = placementSettings or (settings and GetSpecLayoutOrder(settings)) or settings
        if placementSettings and placementSettings.independentAnchor then
            UpdateIndependentStackCoordLabel(
                frame,
                placementSettings.independentAnchor.x,
                placementSettings.independentAnchor.y
            )
        end
    end
end

--- Update cached MW max stacks based on Raging Maelstrom talent (OOC only — talents can't change in combat).
--- Returns true if the max changed (and bars were rebuilt), false otherwise.
local function UpdateMWMaxStacks(applyOpts)
    local hasRagingMaelstrom = C_SpellBook.IsSpellKnown(RAGING_MAELSTROM_SPELL_ID, Enum.SpellBookSpellBank.Player)
    local newMax = hasRagingMaelstrom and 10 or 5
    if mwMaxStacks ~= newMax then
        mwMaxStacks = newMax
        CooldownCompanion:ApplyResourceBars(applyOpts)  -- segment count changed, rebuild
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Update logic: Continuous resources (SECRET in combat — NO Lua arithmetic)
------------------------------------------------------------------------

local function UpdateContinuousBar(bar, powerType, settings)
    if not settings then
        settings = GetResourceBarSettings()
    end

    local currentPower = UnitPower("player", powerType)
    local maxPower = UnitPowerMax("player", powerType)
    local maxPowerIsSecret = IsUnitPowerMaxSecret("player", powerType)
    if issecretvalue and issecretvalue(maxPower) then
        maxPowerIsSecret = true
    end

    -- Pass through to C-level widget APIs (secret-safe).
    SetStatusBarSmoothRange(bar, 0, maxPower)
    SetStatusBarSmoothValue(bar, currentPower)

    ApplyContinuousFillColor(bar, powerType, settings)
    UpdateContinuousTickMarker(bar, powerType, settings, maxPower, maxPowerIsSecret)

    -- Text: pass directly to C-level SetFormattedText — accepts secrets
    if bar.text and bar.text:IsShown() then
        local textFormat = bar._textFormat
        if textFormat == "current" then
            bar.text:SetFormattedText("%d", currentPower)
        elseif textFormat == "percent" then
            -- UnitPowerPercent returns a 0..1 value by default; evaluate through a curve
            -- to get 0..100 without Lua arithmetic (secret-safe in combat).
            bar.text:SetFormattedText("%.0f", UnitPowerPercent("player", powerType, false, PERCENT_SCALE_CURVE))
        else
            bar.text:SetFormattedText("%d / %d", currentPower, maxPower)
        end
    end

end

------------------------------------------------------------------------
-- Update logic: Stagger bar (Brewmaster Monk)
-- Uses UnitStagger for bar fill (ConditionalSecret — pass-through safe)
-- and UnitStagger/UnitHealthMax for color thresholds + percent text.
------------------------------------------------------------------------

local function UpdateStaggerBar(bar, settings)
    if not settings then
        settings = GetResourceBarSettings()
    end

    local staggerAmount = UnitStagger("player") or 0
    local maxHealth = UnitHealthMax("player")

    local isSecret = issecretvalue
        and (issecretvalue(staggerAmount) or issecretvalue(maxHealth))
    if not isSecret and maxHealth < 1 then maxHealth = 1 end

    -- Pass-through to C-level widget APIs (secret-safe)
    SetStatusBarSmoothRange(bar, 0, maxHealth)
    SetStatusBarSmoothValue(bar, staggerAmount)

    -- Compute pool percent for color + text (only when neither value is secret)
    local percent
    if not isSecret then
        percent = staggerAmount / maxHealth * 100
    end

    -- Color thresholds: 30% yellow, 60% red (Blizzard's MonkStaggerBar values)
    local greenColor, yellowColor, redColor = GetResourceColors(101, settings)
    local barColor = greenColor
    if not isSecret then
        if percent >= 60 then
            barColor = redColor
        elseif percent >= 30 then
            barColor = yellowColor
        end
    end
    bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
    bar.brightnessOverlay:Hide()

    -- Text display
    if bar.text and bar.text:IsShown() then
        if isSecret then
            bar.text:SetText("")
        else
            local textFormat = bar._textFormat
            if textFormat == "current" then
                bar.text:SetFormattedText("%d", staggerAmount)
            elseif textFormat == "percent" then
                bar.text:SetFormattedText("%.0f%%", percent)
            else
                bar.text:SetFormattedText("%d / %d", staggerAmount, maxHealth)
            end
        end
    end
end

------------------------------------------------------------------------
-- Update logic: Segmented resources (NOT secret — full Lua logic)
------------------------------------------------------------------------

function segmentedUpdateScratch.ClearValues(holder)
    for _, seg in ipairs(holder.segments) do
        SetStatusBarImmediateValue(seg, 0)
    end
end

function segmentedUpdateScratch.FinishText(holder, currentValue, maxValue, clearText)
    if clearText then
        ClearSegmentedText(holder)
    else
        SetSegmentedText(holder, currentValue, maxValue)
    end
end

function segmentedUpdateScratch.SortRuneData(a, b)
    if a.ready ~= b.ready then return a.ready end
    return a.remaining < b.remaining
end

function segmentedUpdateScratch.GetRuneData(holder)
    if not holder._runeDataScratch then
        holder._runeDataScratch = {}
        for i = 1, 6 do
            holder._runeDataScratch[i] = {}
        end
    end
    return holder._runeDataScratch
end

-- The flag records that every recharge text on this holder is already blank
-- and hidden, so the poll can skip a clear it has nothing to undo. Only
-- SetRechargeText writes text, and it clears the flag, so the flag can never
-- claim a hidden state that is not real.
local function HideRechargeTexts(holder)
    if not holder then return end
    holder._rechargeTextsHidden = true
    if not holder.rechargeTexts then return end
    for _, text in ipairs(holder.rechargeTexts) do
        text:SetText("")
        text:Hide()
    end
end

local function StyleRechargeTexts(holder, powerType, settings)
    if not (holder and holder.rechargeTexts) then return end
    local resourceConfig = GetResourceDisplayConfig(settings, powerType)
    local enabled = resourceConfig and resourceConfig.showRechargeText == true
    if not enabled or powerType ~= 5 then
        holder._showRechargeText = false
        HideRechargeTexts(holder)
        return
    end

    local fontName = resourceConfig.rechargeTextFont or resourceConfig.textFont or DEFAULT_RESOURCE_TEXT_FONT
    local fontSize = tonumber(resourceConfig.rechargeTextFontSize or resourceConfig.textFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
    local outline = ST.GetEffectiveFontOutline(resourceConfig.rechargeTextFontOutline or resourceConfig.textFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
    local color = resourceConfig.rechargeTextFontColor or resourceConfig.textFontColor or DEFAULT_RESOURCE_TEXT_COLOR
    if type(color) ~= "table" or color[1] == nil or color[2] == nil or color[3] == nil then
        color = DEFAULT_RESOURCE_TEXT_COLOR
    end

    local anchor = resourceConfig.rechargeTextAnchor or resourceConfig.textAnchor or "CENTER"
    local xOffset = resourceConfig.rechargeTextXOffset or 0
    local yOffset = resourceConfig.rechargeTextYOffset or 0
    local font = CooldownCompanion:FetchFont(fontName)
    for i, text in ipairs(holder.rechargeTexts) do
        text:SetFont(font, fontSize, outline)
        ST.ApplyFontShadowForOutline(text, outline)
        text:SetTextColor(color[1], color[2], color[3], color[4] ~= nil and color[4] or 1)
        ST.TextAnchorLayout.Apply(text, holder.segments[i], anchor, xOffset, yOffset)
    end

    local mode = resourceConfig.rechargeTextMode
    if mode ~= "all" then
        mode = "recharging"
    end

    holder._showRechargeText = true
    holder._rechargeTextMode = mode
    holder._rechargeTextFormatSource = resourceConfig
end

local function IsRechargeTextAllSegmentsMode(holder)
    return holder and holder._rechargeTextMode == "all"
end

local function ShouldShowRechargeTextForTimer(holder)
    if not holder then return false end
    return holder._rechargeTextMode == "recharging" or holder._rechargeTextMode == "all"
end

local function SetRechargeText(holder, segmentIndex, remaining, showZero)
    if not (holder and holder._showRechargeText and holder.rechargeTexts) then return end
    local text = holder.rechargeTexts[segmentIndex]
    if not text then return end
    holder._rechargeTextsHidden = false
    if type(remaining) ~= "number" or remaining <= 0 then
        if showZero then
            text:SetText("0")
            text:Show()
            return
        end
        text:SetText("")
        text:Hide()
        return
    end

    local formatted = FormatTime(remaining, holder._rechargeTextFormatSource)
    text:SetText(formatted)
    text:SetShown(formatted ~= "")
end

-- Forward declaration: the native segmented branches below light the
-- max-stack border, and its definition lives with the border section
-- further down. Declared-then-assigned, so the chunk's local count is
-- unchanged (200-local ceiling).
local UpdateMaxStackBorder

local function UpdateSegmentedBar(holder, powerType, settings)
    if not holder or not holder.segments then return end
    if not settings then
        settings = GetResourceBarSettings()
    end

    local segmentedSmoothing = GetResourceSegmentedSmoothing(settings)
    local segmentCount = holder._activeSegments or #holder.segments
    -- Recharge text exists only on runes with the option on (StyleRechargeTexts
    -- owns _showRechargeText). Everywhere else the clear has to run once after
    -- the style pass and never again, so the poll stops rewriting six blank
    -- FontStrings per segmented bar per tick.
    if holder._showRechargeText or not holder._rechargeTextsHidden then
        HideRechargeTexts(holder)
    end

    if powerType == 5 then
        -- DK Runes: sorted by readiness (ready left, longest CD right)
        local now = GetTime()
        local numSegs = math_min(segmentCount, 6)
        local runeData = segmentedUpdateScratch.GetRuneData(holder)
        runeData.soundReadable = true
        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown(i)
            if ready == nil then runeData.soundReadable = false end
            local remaining = 0
            local activelyRecharging = false
            if not ready and duration and duration > 0 then
                remaining = math_max((start + duration) - now, 0)
                activelyRecharging = start and start <= now and remaining > 0
            end
            local rune = runeData[i]
            rune.start = start
            rune.duration = duration
            rune.ready = ready
            rune.remaining = remaining
            rune.activelyRecharging = activelyRecharging
        end
        -- Sort: ready first, then by ascending remaining time
        table.sort(runeData, segmentedUpdateScratch.SortRuneData)
        local readyColor, rechargingColor, maxColor = GetResourceColors(5, settings)
        local allReady = true
        local readyCount = 0
        for i = 1, numSegs do
            if not runeData[i].ready then allReady = false; break end
        end
        for i = 1, numSegs do
            if runeData[i].ready then
                readyCount = readyCount + 1
            end
        end
        if runeData.soundReadable then RB.ResourceSounds.Observe(holder, powerType, readyCount, numSegs) end
        local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, readyCount, holder)
        local activeReadyColor = allReady and maxColor or (thresholdActive and thresholdColor or readyColor)
        -- At max means all runes ready. numSegs > 0 so a holder with no
        -- segments never lights the border off the vacuously-true allReady.
        UpdateMaxStackBorder(holder, settings, allReady and numSegs > 0, powerType)
        local runeValueTotal = 0
        local showAllRechargeText = IsRechargeTextAllSegmentsMode(holder)
        for i = 1, numSegs do
            local r = runeData[i]
            local seg = holder.segments[i]
            local segValue = 0
            if r.ready then
                segValue = 1
                SetStatusBarSegmentedValue(seg, segValue, segmentedSmoothing)
                seg:SetStatusBarColor(activeReadyColor[1], activeReadyColor[2], activeReadyColor[3], 1)
                if showAllRechargeText then
                    SetRechargeText(holder, i, 0, true)
                end
            elseif r.duration and r.duration > 0 then
                segValue = math_min((now - r.start) / r.duration, 1)
                SetStatusBarSegmentedValue(seg, segValue, segmentedSmoothing)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
                if showAllRechargeText or (ShouldShowRechargeTextForTimer(holder) and r.activelyRecharging) then
                    SetRechargeText(holder, i, r.remaining)
                end
            else
                SetStatusBarSegmentedValue(seg, segValue, segmentedSmoothing)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
                if showAllRechargeText then
                    SetRechargeText(holder, i, 0, true)
                end
            end
            runeValueTotal = runeValueTotal + segValue
        end
        segmentedUpdateScratch.FinishText(holder, runeValueTotal, numSegs, false)
        return
    end

    if powerType == 7 then
        if IsUnitPowerSecret("player", 7) or IsUnitPowerMaxSecret("player", 7) then
            -- Unreadable values read as not-at-max: the border clears.
            UpdateMaxStackBorder(holder, settings, false, powerType)
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
            return
        end

        -- Soul Shards: fractional fill with ready/recharging colors
        local raw = UnitPower("player", 7, true)
        local rawMax = UnitPowerMax("player", 7, true)
        local max = UnitPowerMax("player", 7)
        if issecretvalue and (issecretvalue(raw) or issecretvalue(rawMax) or issecretvalue(max)) then
            UpdateMaxStackBorder(holder, settings, false, powerType)
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
            return
        end

        -- At max means every shard is WHOLE; a partial shard on top of
        -- max-1 stays dark. The false start covers both fallback legs
        -- below, so a bar that loses its readable maximum drops the border.
        local shardsAtMax = false
        local displayCurrent
        if max > 0 and rawMax > 0 then
            local perShard = rawMax / max
            if perShard > 0 then
                local filled = math_floor(raw / perShard)
                RB.ResourceSounds.Observe(holder, powerType, filled, max)
                local partial = (raw % perShard) / perShard
                displayCurrent = filled + partial
                local readyColor, rechargingColor, maxColor = GetResourceColors(7, settings)
                local isMax = (filled == max)
                shardsAtMax = isMax
                local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, filled, holder)
                local activeReadyColor = isMax and maxColor or (thresholdActive and thresholdColor or readyColor)
                for i = 1, math_min(segmentCount, max) do
                    local seg = holder.segments[i]
                    if i <= filled then
                        SetStatusBarSegmentedValue(seg, 1, segmentedSmoothing)
                        seg:SetStatusBarColor(activeReadyColor[1], activeReadyColor[2], activeReadyColor[3], 1)
                    elseif i == filled + 1 and partial > 0 then
                        SetStatusBarSegmentedValue(seg, partial, segmentedSmoothing)
                        seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
                    else
                        SetStatusBarSegmentedValue(seg, 0, segmentedSmoothing)
                        seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
                    end
                end
            else
                segmentedUpdateScratch.ClearValues(holder)
            end
        else
            segmentedUpdateScratch.ClearValues(holder)
        end
        UpdateMaxStackBorder(holder, settings, shardsAtMax, powerType)
        if type(displayCurrent) == "number" then
            segmentedUpdateScratch.FinishText(holder, displayCurrent, max, false)
        else
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
        end
        return
    end

    if powerType == 19 then
        if IsUnitPowerSecret("player", 19) or IsUnitPowerMaxSecret("player", 19) then
            -- Unreadable values read as not-at-max: the border clears.
            UpdateMaxStackBorder(holder, settings, false, powerType)
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
            return
        end

        -- Essence: partial recharge with ready/recharging colors
        local filled = UnitPower("player", 19)
        local max = UnitPowerMax("player", 19)
        local partialRaw = UnitPartialPower("player", 19)
        if issecretvalue and (issecretvalue(filled) or issecretvalue(max) or issecretvalue(partialRaw)) then
            UpdateMaxStackBorder(holder, settings, false, powerType)
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
            return
        end

        RB.ResourceSounds.Observe(holder, powerType, filled, max)
        local partial = partialRaw / 1000
        local displayCurrent = filled + partial
        local readyColor, rechargingColor, maxColor = GetResourceColors(19, settings)
        local isMax = (filled == max)
        local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, filled, holder)
        local activeReadyColor = isMax and maxColor or (thresholdActive and thresholdColor or readyColor)
        -- At max means every essence is WHOLE (a recharging partial stays
        -- dark), and max > 0 so an empty 0/0 read never lights the border —
        -- the color path's 0/0 case paints zero segments, but a border has
        -- no segment count to hide behind.
        UpdateMaxStackBorder(holder, settings, isMax and max > 0, powerType)
        for i = 1, math_min(segmentCount, max) do
            local seg = holder.segments[i]
            if i <= filled then
                SetStatusBarSegmentedValue(seg, 1, segmentedSmoothing)
                seg:SetStatusBarColor(activeReadyColor[1], activeReadyColor[2], activeReadyColor[3], 1)
            elseif i == filled + 1 and partial > 0 then
                SetStatusBarSegmentedValue(seg, partial, segmentedSmoothing)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            else
                SetStatusBarSegmentedValue(seg, 0, segmentedSmoothing)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            end
        end
        segmentedUpdateScratch.FinishText(holder, displayCurrent, max, false)
        return
    end

    -- Combo Points: color changes at max, charged coloring for Rogues
    if powerType == 4 then
        if IsUnitPowerSecret("player", 4) or IsUnitPowerMaxSecret("player", 4) then
            -- Unreadable values read as not-at-max: the border clears.
            UpdateMaxStackBorder(holder, settings, false, powerType)
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
            return
        end

        local current = UnitPower("player", 4)
        local max = UnitPowerMax("player", 4)
        if issecretvalue and (issecretvalue(current) or issecretvalue(max)) then
            UpdateMaxStackBorder(holder, settings, false, powerType)
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
            return
        end

        RB.ResourceSounds.Observe(holder, powerType, current, max)
        local normalColor, maxColor, chargedColor = GetResourceColors(4, settings)
        local isMax = (current == max and max > 0)
        local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, current, holder)
        local baseColor = isMax and maxColor or (thresholdActive and thresholdColor or normalColor)
        UpdateMaxStackBorder(holder, settings, isMax, powerType)

        -- Charged combo points (Rogue only)
        local chargedPoints
        if GetPlayerClassID() == 4 then
            chargedPoints = GetUnitChargedPowerPoints("player")
        end

        for i = 1, math_min(segmentCount, max) do
            local seg = holder.segments[i]
            if i <= current then
                SetStatusBarSegmentedValue(seg, 1, segmentedSmoothing)
                if chargedPoints and tContains(chargedPoints, i) then
                    seg:SetStatusBarColor(chargedColor[1], chargedColor[2], chargedColor[3], 1)
                else
                    seg:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
                end
            else
                SetStatusBarSegmentedValue(seg, 0, segmentedSmoothing)
            end
        end
        segmentedUpdateScratch.FinishText(holder, current, max, false)
        return
    end

    -- Generic segmented with max color: HolyPower, Chi, ArcaneCharges
    if IsUnitPowerSecret("player", powerType) or IsUnitPowerMaxSecret("player", powerType) then
        -- Unreadable values read as not-at-max: the border clears.
        UpdateMaxStackBorder(holder, settings, false, powerType)
        segmentedUpdateScratch.ClearValues(holder)
        segmentedUpdateScratch.FinishText(holder, nil, nil, true)
        return
    end

    local current = UnitPower("player", powerType)
    local max = UnitPowerMax("player", powerType)
    if issecretvalue and (issecretvalue(current) or issecretvalue(max)) then
        UpdateMaxStackBorder(holder, settings, false, powerType)
        segmentedUpdateScratch.ClearValues(holder)
        segmentedUpdateScratch.FinishText(holder, nil, nil, true)
        return
    end
    RB.ResourceSounds.Observe(holder, powerType, current, max)
    local normalColor, maxColor
    if RESOURCE_COLOR_DEFS[powerType] then
        normalColor, maxColor = GetResourceColors(powerType, settings)
    else
        local color = GetResourceColors(powerType, settings)
        normalColor, maxColor = color, color
    end
    local isMax = (current == max and max > 0)
    local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, current, holder)
    local activeColor = isMax and maxColor or (thresholdActive and thresholdColor or normalColor)
    UpdateMaxStackBorder(holder, settings, isMax, powerType)
    for i = 1, math_min(segmentCount, max) do
        local seg = holder.segments[i]
        if i <= current then
            SetStatusBarSegmentedValue(seg, 1, segmentedSmoothing)
            seg:SetStatusBarColor(activeColor[1], activeColor[2], activeColor[3], 1)
        else
            SetStatusBarSegmentedValue(seg, 0, segmentedSmoothing)
        end
    end
    segmentedUpdateScratch.FinishText(holder, current, max, false)
end

------------------------------------------------------------------------
-- Max-stack border (owner ruling 2026-08-02): a CC-drawn border that lights
-- while a stack-counted resource sits at its stack maximum. Legal in combat
-- because every value it follows is one the bar itself already renders from
-- — never-secret aura reads for the aura family, guarded power reads for
-- the native segmented resources — and everything here is plain CC frames.
-- Renders through the same pure builder as the resource aura border: ONE
-- rect around the whole bar field on every shape (owner ruling 2026-08-23,
-- retiring the per-segment rings). Shared by Maelstrom Weapon, the
-- aura-stack family and the native segmented resources; only the key names
-- differ (RB.MAX_STACK_BORDER_KEYS).
------------------------------------------------------------------------

-- The border's config, or nil when disabled. Plain resource-level keys on
-- the resource's own bucket (no spec overrides: each of these resources
-- belongs to a single spec). Returns the resource table and its key names
-- too, for the slider keys. The bucket is the CANONICAL half's: a mutually
-- exclusive pair is one bar in one slot, so its border is one setting that
-- lights on whichever half is up. Every other resource is its own canonical
-- half, Maelstrom Weapon included, so its keys are unchanged.
local function GetMaxStackBorderConfig(settings, powerType)
    powerType = RB.GetCanonicalPowerType(powerType)
    local resource = settings and settings.resources and settings.resources[powerType]
    local keys = RB.MAX_STACK_BORDER_KEYS[powerType] or RB.MAX_STACK_BORDER_KEYS.default
    if type(resource) ~= "table" or resource[keys.enabled] ~= true then
        return nil
    end
    local style = resource[keys.style] == "pixel" and "pixel" or "solid"
    local color = resource[keys.color]
    if type(color) ~= "table" or color[1] == nil or color[2] == nil or color[3] == nil then
        color = RB.DEFAULT_MW_MAX_STACK_BORDER_COLOR
    end
    return style, color, resource, keys
end

-- Runs on every stack update tick, so restyling is keyed: only a real change
-- (lit flips, style or colour edited, bar shape swapped) touches regions.
-- The pool hangs off the bar frame and is reset by
-- ResetResourceBarRuntimeState when the renderer is retired.
function UpdateMaxStackBorder(holder, settings, isMax, powerType)
    local style, color, resource, keys
    if isMax then
        style, color, resource, keys = GetMaxStackBorderConfig(settings, powerType or RESOURCE_MAELSTROM_WEAPON)
    end
    local pool = holder._ccMWMaxBorder
    if not style then
        if pool and pool.key ~= "off" then
            pool.key = "off"
            if pool.glow then
                ST._StyleKitBarGlowRegions(pool.glow, nil, pool.host, false)
            end
        end
        return
    end

    if not pool then
        local host = CreateFrame("Frame", nil, holder)
        host:EnableMouse(false)
        host:SetAllPoints(holder)
        -- Over every non-text layer the bar stacks (MW overlay segments at
        -- +4) — the same clearance the aura overlay uses. Resource text
        -- bands above this (RESOURCE_TEXT_LAYER_LEVEL): text wins over
        -- borders and glows by owner ruling.
        host:SetFrameLevel(holder:GetFrameLevel() + RB.RESOURCE_OVERLAY_HOLDER_LEVEL)
        pool = { host = host }
        holder._ccMWMaxBorder = pool
    end

    local size = tonumber(resource[keys.size])
    local thickness = tonumber(resource[keys.thickness])
    local speed = tonumber(resource[keys.speed])
    local lines = tonumber(resource[keys.lines])

    -- Explicit rect dims for the dash geometry: the bar carries an explicit
    -- size, the SetAllPoints host may not have resolved yet.
    local fw, fh = RB.GetResourceBarSize(holder)
    fw = (fw and fw > 1) and fw or 1
    fh = (fh and fh > 1) and fh or 1
    -- The dims are part of the key: a resized bar keeps its pool, so without
    -- them a bar that changed size would keep the old rect's geometry.
    -- Compared field by field rather than through a composed string: this runs
    -- on every tick a stack-counted resource sits at its maximum, and the
    -- string was built before the early-out, not after it.
    if pool.key == "on"
        and pool.keyStyle == style
        and pool.keyW == fw and pool.keyH == fh
        and pool.keyR == color[1] and pool.keyG == color[2]
        and pool.keyB == color[3] and pool.keyA == color[4]
        and pool.keySize == size and pool.keyThickness == thickness
        and pool.keySpeed == speed and pool.keyLines == lines then
        return
    end
    pool.key = "on"
    pool.keyStyle = style
    pool.keyW = fw
    pool.keyH = fh
    pool.keyR, pool.keyG, pool.keyB, pool.keyA = color[1], color[2], color[3], color[4]
    pool.keySize = size
    pool.keyThickness = thickness
    pool.keySpeed = speed
    pool.keyLines = lines

    local borderStyle = {
        barAuraIndicatorEnabled = true,
        barAuraEffect = style,
        barAuraEffectColor = color,
        barAuraEffectSize = size,
        barAuraEffectThickness = thickness,
        barAuraEffectSpeed = speed,
        barAuraEffectLines = lines,
    }
    if not pool.glow then
        pool.glow = ST._BuildKitGlowRegions(pool.host)
    end
    pool.host._ccKitRectW = fw
    pool.host._ccKitRectH = fh
    ST._StyleKitBarGlowRegions(pool.glow, borderStyle, pool.host, true)
end
-- For the config canvas (ResourceBarPreview), which renders these bars at max.
RB.UpdateMaxStackBorder = UpdateMaxStackBorder

------------------------------------------------------------------------
-- Update logic: Maelstrom Weapon (overlay bar, plain applications)
------------------------------------------------------------------------

local function UpdateMaelstromWeaponBar(holder, settings, barType)
    if not holder then return end
    -- The continuous style has no segments; every other style does.
    local isContinuous = barType == "mw_continuous"
    if not (isContinuous or holder.segments) then return end
    if not settings then
        settings = GetResourceBarSettings()
    end
    local segmentedSmoothing = GetResourceSegmentedSmoothing(settings)

    -- Maelstrom Weapon stacks (the aura pass, Phase 2). MW carries the
    -- server-side per-spell never-secret flag — validated on PTR 7 by
    -- dumping the aura mid-combat: a fully PLAIN AuraData with a readable
    -- `applications`, exactly the carve-out the API docs describe for
    -- resource-like auras. So the bar reads its own stacks and keeps the
    -- full Lua render (dual-colour halves, threshold and max colours,
    -- segment text) instead of a Blizzard-driven kit shape.
    --
    -- GetPlayerAuraBySpellID is the RequiresNonSecretAura read path: it
    -- returns NOTHING for a secret aura rather than erroring, so this is
    -- safe in every restricted context. The secret guard below covers the
    -- flag being changed by a future build (retest-each-build discipline) —
    -- a secret reaching the comparisons underneath would be a hard error.
    local stacks = 0
    local mwAura = C_UnitAuras.GetPlayerAuraBySpellID(MW_AURA_SPELL_ID)
    if mwAura then
        stacks = mwAura.applications or 0
    end
    if issecretvalue and issecretvalue(stacks) then
        -- Unreadable stacks read as not-at-max: the border clears.
        UpdateMaxStackBorder(holder, settings, false, RESOURCE_MAELSTROM_WEAPON)
        if isContinuous then
            SetStatusBarImmediateValue(holder, 0)
            if holder.text then holder.text:SetText("") end
            return
        end
        for i = 1, #holder.segments do
            SetStatusBarImmediateValue(holder.segments[i], 0)
            if holder.overlaySegments and holder.overlaySegments[i] then
                SetStatusBarImmediateValue(holder.overlaySegments[i], 0)
                holder.overlaySegments[i]:SetAlpha(0)
            end
        end
        ClearSegmentedText(holder)
        return
    end

    local baseColor, overlayColor, maxColor = GetResourceColors(100, settings)
    local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(RESOURCE_MAELSTROM_WEAPON, settings, stacks, holder)
    RB.ResourceSounds.Observe(holder, RESOURCE_MAELSTROM_WEAPON, stacks, mwMaxStacks)
    local isMax = stacks > 0 and stacks == mwMaxStacks
    -- Colour precedence is identical in all three shapes: at max wins, then
    -- a configured threshold, then the resource's own colour.
    local activeColor = isMax and maxColor or (thresholdActive and thresholdColor or baseColor)
    UpdateMaxStackBorder(holder, settings, isMax, RESOURCE_MAELSTROM_WEAPON)

    if isContinuous then
        -- One bar, empty to full, the stack maximum as its range.
        SetStatusBarSmoothRange(holder, 0, mwMaxStacks)
        SetStatusBarSegmentedValue(holder, stacks, segmentedSmoothing)
        holder:SetStatusBarColor(activeColor[1], activeColor[2], activeColor[3], 1)
        if holder.brightnessOverlay then
            holder.brightnessOverlay:Hide()
        end
        if holder.text and holder.text:IsShown() then
            local textFormat = holder._textFormat
            if textFormat == "current" then
                holder.text:SetFormattedText("%d", stacks)
            elseif textFormat == "percent" then
                holder.text:SetFormattedText("%d", (stacks / mwMaxStacks) * 100)
            else
                holder.text:SetFormattedText("%d / %d", stacks, mwMaxStacks)
            end
        end
        return
    end

    if barType == "mw_segments" then
        -- Capacity is retained when the talent lowers the active count.
        for i = 1, holder._activeSegments or #holder.segments do
            local seg = holder.segments[i]
            SetStatusBarSegmentedValue(seg, i <= stacks and 1 or 0, segmentedSmoothing)
            seg:SetStatusBarColor(activeColor[1], activeColor[2], activeColor[3], 1)
        end
        SetSegmentedText(holder, stacks, mwMaxStacks)
        return
    end

    local half = #holder.segments

    for i = 1, half do
        local baseSeg = holder.segments[i]
        local overlaySeg = holder.overlaySegments[i]

        SetStatusBarSegmentedValue(baseSeg, stacks, segmentedSmoothing)
        SetStatusBarSegmentedValue(overlaySeg, stacks, segmentedSmoothing)
        -- Hide right-half overlay segments when value is at/below their segment minimum.
        -- This prevents tiny leading-edge ticks on empty overlay segments.
        if stacks > (half + i - 1) then
            overlaySeg:SetAlpha(1)
        else
            overlaySeg:SetAlpha(0)
        end

        if isMax then
            baseSeg:SetStatusBarColor(maxColor[1], maxColor[2], maxColor[3], 1)
            overlaySeg:SetStatusBarColor(maxColor[1], maxColor[2], maxColor[3], 1)
        elseif thresholdActive then
            baseSeg:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], 1)
            overlaySeg:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], 1)
        else
            baseSeg:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
            overlaySeg:SetStatusBarColor(overlayColor[1], overlayColor[2], overlayColor[3], 1)
        end
    end

    SetSegmentedText(holder, stacks, mwMaxStacks)
end

------------------------------------------------------------------------
-- Update logic: the aura-stack resource family (Icicles, Tip of the Spear,
-- the Devourer pair)
--
-- The same model Maelstrom Weapon runs on — a never-secret aura's plain
-- `applications` read every tick — minus the overlay shape (stacks never
-- run past the segment count here), so only the segmented and continuous
-- widgets exist. Colour precedence matches MW exactly: at max wins, then a
-- configured threshold, then the resource's own colour. The maximum comes
-- from the family resolver, which is a constant for most members and a live
-- read for the ones whose cap moves.
------------------------------------------------------------------------

local function UpdateAuraStackResourceBar(holder, settings, barType, powerType)
    if not holder then return end
    local info = RB.AURA_STACK_RESOURCES[powerType]
    if not info then return end
    -- The continuous style has no segments; the segmented style does.
    local isContinuous = barType == "stackaura_continuous"
    if not (isContinuous or holder.segments) then return end
    if not settings then
        settings = GetResourceBarSettings()
    end
    local segmentedSmoothing = GetResourceSegmentedSmoothing(settings)
    local maxStacks, soundMaxConfirmed = RB.GetAuraStackResourceMax(powerType)
    -- The ACTIVE segment count. The holder is re-segmented in place, so its
    -- segments array is the high-water mark and everything past
    -- _activeSegments is parked and hidden (EnsureSegmentCount/LayoutSegments).
    local segCount = holder.segments and (holder._activeSegments or #holder.segments) or 0

    -- A dynamic maximum can move after the segments were built for it: a
    -- talent changes the cap, or the API had no answer yet and what got
    -- built is the fallback. Re-segmenting the widget is ApplyResourceBars'
    -- job and it must not run from inside the tick's loop over the very
    -- active list it rebuilds, so ask for one and let the end of the tick do it.
    -- The rendering below clamps to the segments that exist until it lands.
    if not isContinuous and segCount ~= maxStacks then
        stackSwapState.reapply = true
    end

    -- GetPlayerAuraBySpellID is the RequiresNonSecretAura read path: it
    -- returns NOTHING for a secret aura rather than erroring, so this is
    -- safe in every restricted context. The secret guard below covers the
    -- never-secret flag being changed by a future build (retest-each-build
    -- discipline) — a secret reaching the comparisons underneath would be a
    -- hard error.
    local stacks = 0
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(info.auraSpellID)
    if aura then
        stacks = aura.applications or 0
    end
    if issecretvalue and issecretvalue(stacks) then
        -- Unreadable stacks read as not-at-max: the border clears.
        UpdateMaxStackBorder(holder, settings, false, powerType)
        if isContinuous then
            SetStatusBarImmediateValue(holder, 0)
            if holder.text then holder.text:SetText("") end
            return
        end
        for i = 1, segCount do
            SetStatusBarImmediateValue(holder.segments[i], 0)
        end
        ClearSegmentedText(holder)
        return
    end

    local baseColor, maxColor = GetResourceColors(powerType, settings)
    local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, stacks, holder)
    -- >= rather than ==: a member's maximum can be a stale constant or a
    -- stand-in fallback the API has not replaced yet, so stacks past it
    -- should still read as "at max" instead of silently losing the max
    -- colour and the border.
    if soundMaxConfirmed then RB.ResourceSounds.Observe(holder, powerType, stacks, maxStacks) end
    local isMax = stacks > 0 and stacks >= maxStacks
    local activeColor = isMax and maxColor or (thresholdActive and thresholdColor or baseColor)
    UpdateMaxStackBorder(holder, settings, isMax, powerType)

    if isContinuous then
        -- One bar, empty to full, the stack maximum as its range.
        SetStatusBarSmoothRange(holder, 0, maxStacks)
        SetStatusBarSegmentedValue(holder, stacks, segmentedSmoothing)
        holder:SetStatusBarColor(activeColor[1], activeColor[2], activeColor[3], 1)
        if holder.brightnessOverlay then
            holder.brightnessOverlay:Hide()
        end
        if holder.text and holder.text:IsShown() then
            -- Hide at 0, the same rule SetSegmentedText applies on the
            -- segmented shape: an empty stack-counted resource reads as an
            -- empty bar, not as a "0".
            if holder._hideTextAtZero and stacks == 0 then
                holder.text:SetText("")
            else
                local textFormat = holder._textFormat
                if textFormat == "current" then
                    holder.text:SetFormattedText("%d", stacks)
                elseif textFormat == "percent" then
                    holder.text:SetFormattedText("%d", (stacks / maxStacks) * 100)
                else
                    holder.text:SetFormattedText("%d / %d", stacks, maxStacks)
                end
            end
        end
        return
    end

    -- One segment per stack: each fills whole, like every other discrete
    -- resource. Parked segments past the active count are hidden and are not
    -- touched here.
    for i = 1, segCount do
        local seg = holder.segments[i]
        SetStatusBarSegmentedValue(seg, i <= stacks and 1 or 0, segmentedSmoothing)
        seg:SetStatusBarColor(activeColor[1], activeColor[2], activeColor[3], 1)
    end
    SetSegmentedText(holder, stacks, maxStacks)
end

------------------------------------------------------------------------
-- Resource owners, active membership, and renderer lifetime.
------------------------------------------------------------------------
local RelayoutBars

function ResourceBars.Update(barInfo, settings)
    local frame, powerType, barType = barInfo.frame, barInfo.powerType, barInfo.barType
    if barType == "continuous" then
        UpdateContinuousBar(frame, powerType, settings)
    elseif barType == "health_continuous" then
        HealthBar.Update(frame, settings)
    elseif barType == "segmented" then
        UpdateSegmentedBar(frame, powerType, settings)
    elseif barType == "mw_segmented" or barType == "mw_segments" or barType == "mw_continuous" then
        UpdateMaelstromWeaponBar(frame, settings, barType)
    elseif barType == "stackaura_segments" or barType == "stackaura_continuous" then
        UpdateAuraStackResourceBar(frame, settings, barType, powerType)
    elseif barType == "stagger_continuous" then
        UpdateStaggerBar(frame, settings)
    end
end

-- Settle native interpolation without reading back a possibly secret value.
-- Hidden renderers do no animation work; activation starts at the freshly
-- painted value. Visible reflows keep their existing interpolation.
function ResourceBars.FinishMotion(frame)
    if frame.segments then
        for _, segment in ipairs(frame.segments) do segment:SetToTargetValue() end
        for _, segment in ipairs(frame.overlaySegments or {}) do segment:SetToTargetValue() end
    else
        frame:SetToTargetValue()
        for _, key in ipairs({ "lowHealthAlertBar", "incomingHealBar",
            "absorbOverflowBar", "absorbBar", "healAbsorbBar" }) do
            if frame[key] then frame[key]:SetToTargetValue() end
        end
    end
end

function ResourceBars.Park(frame)
    frame:Hide()
    ResetResourceBarRuntimeState(frame)
    ResourceBars.FinishMotion(frame)
    if frame.brightnessOverlay then frame.brightnessOverlay:Hide() end
end

function ResourceBars.Deactivate(barInfo)
    ResourceBars.Park(barInfo.frame)
    RB.HideResourceAuraHolder(barInfo.powerType)
end

function ResourceBars.BeginApply(filtered)
    local wanted = {}
    for _, powerType in ipairs(filtered) do wanted[powerType] = true end
    for _, barInfo in ipairs(resourceBarFrames) do
        if not wanted[barInfo.powerType] then ResourceBars.Deactivate(barInfo) end
    end
    wipe(resourceBarFrames)
end

function ResourceBars.ResolveRenderer(powerType, settings)
    if powerType == RESOURCE_HEALTH then
        return "continuous", "health_continuous"
    elseif powerType == 101 then
        return "continuous", "stagger_continuous"
    elseif powerType == RESOURCE_MAELSTROM_WEAPON then
        local style = RB.GetMWDisplayStyle(settings)
        if style == "continuous" then return style, "mw_continuous" end
        if style == "segments" then return style, "mw_segments", mwMaxStacks end
        -- Both supported maxima (5 and 10) use the same five-segment overlay.
        return "overlay", "mw_segmented", 5
    elseif RB.AURA_STACK_RESOURCES[powerType] then
        local style = RB.GetAuraStackDisplayStyle(settings, powerType)
        if style == "continuous" then return style, "stackaura_continuous" end
        return "segments", "stackaura_segments", RB.GetAuraStackResourceMax(powerType)
    elseif SEGMENTED_TYPES[powerType] then
        local count = powerType == 5 and 6 or UnitPowerMax("player", powerType)
        return "segments", "segmented", math_max(count, 1)
    end
    return "continuous", "continuous"
end

function ResourceBars.Acquire(powerType, settings, parent)
    local barInfo = ResourceBars.instances[powerType]
    if not barInfo then
        barInfo = { powerType = powerType, renderers = {} }
        ResourceBars.instances[powerType] = barInfo
    end
    local shape, barType, count = ResourceBars.ResolveRenderer(powerType, settings)
    local frame = barInfo.renderers[shape]
    local sameVisibleRenderer = frame ~= nil and frame == barInfo.frame and frame:IsShown()
    if barInfo.frame and barInfo.frame ~= frame then ResourceBars.Park(barInfo.frame) end
    if not frame then
        if shape == "continuous" then
            frame = RB.CreateContinuousBar(parent)
        elseif shape == "segments" then
            frame = RB.CreateSegmentedBar(parent, count)
        else
            frame = RB.CreateOverlayBar(parent, count)
        end
        frame:Hide()
        barInfo.renderers[shape] = frame
    end
    local countChanged = shape == "segments" and frame._numSegments ~= count
    if shape == "segments" then RB.EnsureSegmentCount(frame, count) end
    barInfo.frame, barInfo.barType, barInfo.shape = frame, barType, shape
    RB.ClearCompiledResourceBarConfig(frame)
    return barInfo, sameVisibleRenderer, countChanged
end

local function FinalizeAppliedBarVisibility(barInfo)
    barInfo.frame:Show()
    if RB.SyncResourceBarAuraHostAnchor then RB.SyncResourceBarAuraHostAnchor(barInfo) end
end

-- Native aura holders and adapters keep their separate binding lifecycle.
-- They capture the stable active-list table, not a renderer cache.
RB.CreateResourceBarAuraHostModule({
    resourceBarFrames = resourceBarFrames,
})

------------------------------------------------------------------------
-- Relayout: reposition bars within their containers by visibility/order
-- Called from ApplyResourceBars().
------------------------------------------------------------------------

local function CompareBarOrder(a, b)
    if a._regionRank ~= b._regionRank then return (a._regionRank or 0) < (b._regionRank or 0) end
    if a._order ~= b._order then return a._order < b._order end
    local aKey = a.powerType or ""
    local bKey = b.powerType or ""
    return tostring(aKey) < tostring(bKey)
end

RelayoutBars = function()
    if not containerFrameAbove or not containerFrameBelow then return end
    local barSpacing = lastAppliedBarSpacing or 3.6
    local globalThickness = lastAppliedBarThickness or 12
    local primaryLength = lastAppliedPrimaryLength or 1
    local isVertical = lastAppliedOrientation == "vertical"

    if isVertical then
        local leftBars = {}
        local rightBars = {}
        for _, barInfo in ipairs(resourceBarFrames) do
            if barInfo and barInfo.frame and barInfo.frame:IsShown() then
                if barInfo._side == "left" then
                    table.insert(leftBars, barInfo)
                else
                    table.insert(rightBars, barInfo)
                end
            end
        end
        table.sort(leftBars, CompareBarOrder)
        table.sort(rightBars, CompareBarOrder)

        local leftLength = leftBars[1] and leftBars[1].frame._ccResourceHeight or primaryLength
        local rightLength = rightBars[1] and rightBars[1].frame._ccResourceHeight or primaryLength
        containerFrameAbove:SetHeight(leftLength)
        containerFrameBelow:SetHeight(rightLength)

        -- Left side stacks outward from the group (right edge near group).
        local currentX = 0
        for _, barInfo in ipairs(leftBars) do
            barInfo.frame:ClearAllPoints()
            barInfo.frame:SetPoint("TOPRIGHT", containerFrameAbove, "TOPRIGHT", -currentX, 0)
            barInfo.frame:SetPoint("BOTTOMRIGHT", containerFrameAbove, "BOTTOMRIGHT", -currentX, 0)
            local w = barInfo._effectiveThickness or globalThickness
            barInfo.frame:SetWidth(w)
            currentX = currentX + w + barSpacing
        end
        local leftWidth = currentX > 0 and (currentX - barSpacing) or 1
        containerFrameAbove:SetWidth(leftWidth)
        if #leftBars > 0 then containerFrameAbove:Show() else containerFrameAbove:Hide() end

        -- Right side stacks outward from the group (left edge near group).
        currentX = 0
        for _, barInfo in ipairs(rightBars) do
            barInfo.frame:ClearAllPoints()
            barInfo.frame:SetPoint("TOPLEFT", containerFrameBelow, "TOPLEFT", currentX, 0)
            barInfo.frame:SetPoint("BOTTOMLEFT", containerFrameBelow, "BOTTOMLEFT", currentX, 0)
            local w = barInfo._effectiveThickness or globalThickness
            barInfo.frame:SetWidth(w)
            currentX = currentX + w + barSpacing
        end
        local rightWidth = currentX > 0 and (currentX - barSpacing) or 1
        containerFrameBelow:SetWidth(rightWidth)
        if #rightBars > 0 then containerFrameBelow:Show() else containerFrameBelow:Hide() end
        return leftWidth, rightWidth
    else
        local aboveHeight, belowHeight = 1, 1
        for _, lane in ipairs(RB.ATTACHED_BAR_LANES) do
            local container = RB._barContainers[lane]
            local bars = {}
            for _, barInfo in ipairs(resourceBarFrames) do
                if barInfo.frame and barInfo.frame:IsShown() and barInfo._side == lane then
                    bars[#bars + 1] = barInfo
                end
            end
            table.sort(bars, CompareBarOrder)
            local above = RB.GetBarLaneSide(lane) == "above"
            local point = above and "BOTTOMLEFT" or "TOPLEFT"
            local farPoint = above and "BOTTOMRIGHT" or "TOPRIGHT"
            local currentY = 0
            for _, barInfo in ipairs(bars) do
                barInfo.frame:ClearAllPoints()
                barInfo.frame:SetPoint(point, container, point, 0, above and currentY or -currentY)
                barInfo.frame:SetPoint(farPoint, container, farPoint, 0, above and currentY or -currentY)
                local h = barInfo._effectiveThickness or globalThickness
                barInfo.frame:SetHeight(h)
                currentY = currentY + h + barSpacing
            end
            local height = currentY > 0 and currentY - barSpacing or 1
            container:SetHeight(height)
            container:SetShown(#bars > 0)
            if lane == "above" then aboveHeight = height end
            if lane == "below" then belowHeight = height end
        end
        return aboveHeight, belowHeight
    end
end

------------------------------------------------------------------------
-- OnUpdate handler (30 Hz)
------------------------------------------------------------------------

local elapsed_acc = 0

local function OnUpdate(self, elapsed)
    elapsed_acc = elapsed_acc + elapsed
    if elapsed_acc < UPDATE_INTERVAL then return end
    elapsed_acc = 0

    local settings = GetResourceBarSettings()

    -- The Devourer pair swaps on the Void Metamorphosis transition, which
    -- no event this module listens to announces — the module is a poller,
    -- so the flip is polled too. One presence-only aura read per tick, and
    -- only while a suppressible member is actually enabled in this spec's
    -- list, so no other spec pays anything for it.
    if stackSwapState.watch then
        local inMeta = RB.IsInVoidMetamorphosis()
        if inMeta ~= stackSwapState.inMeta then
            stackSwapState.inMeta = inMeta
            stackSwapState.reapply = true
            stackSwapState.refreshCanvas = true
        end
    end

    RB.ResourceSounds.BeginTick(settings)
    for _, barInfo in ipairs(resourceBarFrames) do
        RB.ResourceSounds.BeginSample(barInfo.frame, barInfo.powerType)
        if barInfo.frame and barInfo.frame:IsShown() then
            ResourceBars.Update(barInfo, settings)
        end
        RB.ResourceSounds.EndSample(barInfo.frame, barInfo.powerType)
    end
    RB.ResourceSounds.RetainFrames(resourceBarFrames)

    -- Re-materialization runs after the loop, never inside it:
    -- ApplyResourceBars rebuilds the active list this tick just
    -- walked. Both requesters land on the same flag — the meta flip above
    -- and a drifted dynamic maximum spotted during the loop — so a tick
    -- where both happen at once still costs exactly one rebuild, and that
    -- rebuild resolves both from current state. Called direct rather than
    -- deferred, matching the talent-driven MW rebuild, which also runs
    -- ApplyResourceBars straight through from its handler; the whole path
    -- is plain CC frames and never-secret reads, so it is legal in combat.
    if stackSwapState.reapply then
        stackSwapState.reapply = false
        CooldownCompanion:ApplyResourceBars()
        stackSwapState.RefreshCanvasAfterFlip()
    end
end

-- An open Resources config canvas draws whichever half of the pair is live,
-- so the flip has to reach it too: without this it keeps drawing the half
-- that just left until some unrelated edit happens to rebuild it. Routed
-- through the config's own exported seam, guarded so the core addon never
-- force-loads config code and never errors when the config addon is not
-- loaded at all. RefreshConfigPanel is deliberately NOT used: no live-commit
-- or runtime path may call it (standing rule). The seam self-gates on
-- whether a canvas is actually on screen, and this fires once per real
-- transition, never per tick.
function stackSwapState.RefreshCanvasAfterFlip()
    if not stackSwapState.refreshCanvas then return end
    stackSwapState.refreshCanvas = false
    if ST._RefreshResourcesLayoutPreview then
        ST._RefreshResourcesLayoutPreview()
    end
end

-- The flip watcher of last resort. The poll above lives in the bar module's
-- OnUpdate, which RevertResourceBars stops — and the list is EMPTY, so
-- revert is exactly what runs, when the only enabled resource in the spec is
-- the currently suppressed half. Nothing would then be watching for the meta
-- transition that brings it back. This is the minimum that keeps that one
-- edge alive: one presence-only aura read on the module's own cadence, no
-- bar lifecycle at all. Torn down by RevertResourceBars (which the disable
-- path also runs) and by every apply that materializes real bars, so it only
-- exists while it is the only thing left to poll.
local function StackSwapWatchOnUpdate(self, elapsed)
    self._acc = (self._acc or 0) + elapsed
    if self._acc < UPDATE_INTERVAL then return end
    self._acc = 0
    local inMeta = RB.IsInVoidMetamorphosis()
    if inMeta ~= stackSwapState.inMeta then
        stackSwapState.inMeta = inMeta
        stackSwapState.refreshCanvas = true
        CooldownCompanion:ApplyResourceBars()
        stackSwapState.RefreshCanvasAfterFlip()
    end
end

-- The empty-list watcher shares the same transition state as the active tick.
function stackSwapState.SetWatcher(enabled)
    if not enabled then
        if stackSwapState.frame then
            stackSwapState.frame:SetScript("OnUpdate", nil)
        end
        return
    end
    if not stackSwapState.frame then
        stackSwapState.frame = CreateFrame("Frame")
    end
    stackSwapState.frame._acc = 0
    stackSwapState.frame:SetScript("OnUpdate", StackSwapWatchOnUpdate)
end

------------------------------------------------------------------------
-- Event handling (provided by ResourceBarLifecycle.lua)
------------------------------------------------------------------------

local EnableLifecycleEvents
local DisableLifecycleEvents
local EnableEventFrame
local DisableEventFrame

------------------------------------------------------------------------
-- Apply: Create/show/position resource bars
------------------------------------------------------------------------

-- skipLiveFillColor: the stack-counted continuous shapes (Maelstrom Weapon,
-- the aura-stack family) repaint their fill with the live precedence colour
-- (max, then threshold, then base) every poll tick, so a reused visible
-- same-resource holder skips the static fill paint here — painting it
-- flashed an at-max bar the wrong colour for a frame on every in-place
-- re-apply. Classic continuous bars pass nothing: their tick runs
-- ApplyContinuousFillColor itself, so the apply-time write matches it.
local function StyleContinuousBar(bar, powerType, settings, skipLiveFillColor)
    local texName = ST.GetEffectiveBarTextureName(GetResourceDisplayValue(settings, "barTexture", "Solid"))
    local isVertical = IsVerticalResourceLayout(settings)
    local reverseFill = IsVerticalFillReversed(settings)
    bar._effectiveBarTextureName = texName

    if texName == "blizzard_class" then
        local atlasInfo = POWER_ATLAS_INFO[powerType]
        if atlasInfo then
            bar:SetStatusBarTexture(atlasInfo.atlas)
            local fillTexture = bar:GetStatusBarTexture()
            bar.brightnessOverlay:SetAllPoints(fillTexture)
            bar.brightnessOverlay:SetAtlas(atlasInfo.atlas)
        else
            -- Fallback for power types without class-specific atlas
            bar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Blizzard"))
        end
    else
        bar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(texName))
    end
    bar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill(isVertical and reverseFill or false)
    bar._isVertical = isVertical
    bar._reverseFill = reverseFill

    if not skipLiveFillColor then
        ApplyContinuousFillColor(bar, powerType, settings)
    end

    local bgc = GetResourceDisplayValue(settings, "backgroundColor", { 0, 0, 0, 0.5 })
    bar.bg:ClearAllPoints()
    bar.bg:SetAllPoints(bar)
    bar.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])

    local borderStyle = GetResourceDisplayValue(settings, "borderStyle", "pixel")
    local borderColor = GetResourceDisplayValue(settings, "borderColor", { 0, 0, 0, 1 })
    local borderSize = GetResourceDisplayValue(settings, "borderSize", 1)
    local borderRenderMode = GetResourceDisplayValue(settings, "borderRenderMode", ST.BORDER_RENDER_MODE_CUSTOM)

    if borderStyle == "pixel" then
        ApplyPixelBorders(bar.borders, bar, borderColor, borderSize, borderRenderMode)
    else
        HidePixelBorders(bar.borders)
    end

    -- Text setup. The factory parks the text layer at the custom-bar height
    -- (bar+2, under the aura kit); resource bars hoist it into the stack's
    -- text band here so resource text renders above every bar's fills and
    -- kit visuals (RESOURCE_TEXT_LAYER_LEVEL has the band map). The tick
    -- layer re-stamps into its own band just below, same reasoning.
    bar.textLayer:SetFrameLevel(bar:GetFrameLevel() + RB.RESOURCE_TEXT_LAYER_LEVEL)
    if bar.tickLayer then
        bar.tickLayer:SetFrameLevel(bar:GetFrameLevel() + RB.RESOURCE_TICK_LAYER_LEVEL)
    end
    local resourceConfig = GetResourceDisplayConfig(settings, powerType)
    local textFormat = resourceConfig and resourceConfig.textFormat or DEFAULT_RESOURCE_TEXT_FORMAT
    if textFormat ~= "current" and textFormat ~= "current_max" and textFormat ~= "percent" then
        textFormat = DEFAULT_RESOURCE_TEXT_FORMAT
    end
    local textFontName = resourceConfig and resourceConfig.textFont or DEFAULT_RESOURCE_TEXT_FONT
    local textSize = tonumber(resourceConfig and resourceConfig.textFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
    local textOutline = ST.GetEffectiveFontOutline(resourceConfig and resourceConfig.textFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
    local textColor = resourceConfig and resourceConfig.textFontColor or DEFAULT_RESOURCE_TEXT_COLOR
    if type(textColor) ~= "table" or textColor[1] == nil or textColor[2] == nil or textColor[3] == nil then
        textColor = DEFAULT_RESOURCE_TEXT_COLOR
    end

    local textFont = CooldownCompanion:FetchFont(textFontName)
    bar.text:SetFont(textFont, textSize, textOutline)
    ST.ApplyFontShadowForOutline(bar.text, textOutline)
    bar.text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] ~= nil and textColor[4] or 1)

    ST.TextAnchorLayout.Apply(bar.text, bar,
        resourceConfig and resourceConfig.textAnchor or "CENTER",
        resourceConfig and resourceConfig.textXOffset or 0,
        resourceConfig and resourceConfig.textYOffset or 0
    )

    -- Continuous bars show text by default. The aura-stack family is the one
    -- exception: its members are stack-text resources everywhere else text is
    -- resolved — the config offers them the segmented contract (off unless
    -- explicitly enabled, plus Hide at 0) — and choosing the continuous SHAPE
    -- must not quietly change what the readout is. So they resolve exactly as
    -- StyleSegmentedText resolves them. Every other continuous bar, Maelstrom
    -- Weapon and Stagger included, keeps the default-on contract it shipped
    -- with. Restyling writes _hideTextAtZero explicitly on both paths.
    local showText = true
    bar._hideTextAtZero = false
    if RB.AURA_STACK_RESOURCES[powerType] then
        showText = resourceConfig and resourceConfig.showText == true
        bar._hideTextAtZero = resourceConfig and resourceConfig.hideTextAtZero or false
        if not showText then
            bar.text:SetText("")
        end
    elseif resourceConfig and resourceConfig.showText == false then
        showText = false
    end
    bar.text:SetShown(showText)
    bar._textFormat = textFormat

    -- Tick markers need a real power type to measure against. Every one of
    -- CC's invented ids is excluded: Stagger (101) is sized by
    -- UnitHealthMax, and Maelstrom Weapon (100) and the aura-stack family
    -- (102, 103) are sized by their auras' stack caps — passing any of them
    -- to UnitPowerMax is a hard error. None is offered tick markers anyway
    -- (GetContinuousTickEntriesConfig groups the stack-counted resources
    -- with the segmented ones, whose threshold colours serve the same role).
    if powerType ~= 101 and powerType ~= RESOURCE_MAELSTROM_WEAPON
        and not RB.AURA_STACK_RESOURCES[powerType] then
        local maxPower = UnitPowerMax("player", powerType)
        local maxPowerIsSecret = IsUnitPowerMaxSecret("player", powerType)
        if issecretvalue and issecretvalue(maxPower) then
            maxPowerIsSecret = true
        end
        UpdateContinuousTickMarker(bar, powerType, settings, maxPower, maxPowerIsSecret)
    end
end

local function StyleSegmentedText(holder, powerType, settings)
    if not holder or not holder.text then return end
    if not IsSegmentedTextResource(powerType) then
        holder.text:SetShown(false)
        holder._textFormat = DEFAULT_RESOURCE_TEXT_FORMAT
        ClearSegmentedText(holder)
        return
    end

    local resourceConfig = GetResourceDisplayConfig(settings, powerType)
    local textFormat = resourceConfig and resourceConfig.textFormat or DEFAULT_RESOURCE_TEXT_FORMAT
    if textFormat ~= "current" and textFormat ~= "current_max" then
        textFormat = DEFAULT_RESOURCE_TEXT_FORMAT
    end
    local textFontName = resourceConfig and resourceConfig.textFont or DEFAULT_RESOURCE_TEXT_FONT
    local textSize = tonumber(resourceConfig and resourceConfig.textFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
    local textOutline = ST.GetEffectiveFontOutline(resourceConfig and resourceConfig.textFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
    local textColor = resourceConfig and resourceConfig.textFontColor or DEFAULT_RESOURCE_TEXT_COLOR
    if type(textColor) ~= "table" or textColor[1] == nil or textColor[2] == nil or textColor[3] == nil then
        textColor = DEFAULT_RESOURCE_TEXT_COLOR
    end

    local textFont = CooldownCompanion:FetchFont(textFontName)
    holder.text:SetFont(textFont, textSize, textOutline)
    ST.ApplyFontShadowForOutline(holder.text, textOutline)
    holder.text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] ~= nil and textColor[4] or 1)

    ST.TextAnchorLayout.Apply(holder.text, holder,
        resourceConfig and resourceConfig.textAnchor or "CENTER",
        resourceConfig and resourceConfig.textXOffset or 0,
        resourceConfig and resourceConfig.textYOffset or 0
    )

    -- Segmented resources are off by default unless explicitly enabled.
    local showText = resourceConfig and resourceConfig.showText == true
    holder.text:SetShown(showText)
    holder._textFormat = textFormat
    holder._hideTextAtZero = resourceConfig and resourceConfig.hideTextAtZero or false
    if not showText then
        ClearSegmentedText(holder)
    end
end

local function StyleSegmentedBar(holder, powerType, settings)
    -- Segment colors are live state, not static style. ApplyResourceBars() can
    -- run during combat events, so avoid briefly repainting every segment with
    -- the generic ready color before UpdateSegmentedBar restores per-segment state.
    StyleSegmentedText(holder, powerType, settings)
    StyleRechargeTexts(holder, powerType, settings)
end

local function ApplySegmentedPreviewColors(holder, powerType, settings, previewValue)
    if not holder or not holder.segments then return end

    local numSegments = #holder.segments
    if numSegments <= 0 then return end

    HideRechargeTexts(holder)
    previewValue = tonumber(previewValue) or (numSegments * 0.6)
    local filled = math_min(numSegments, math_max(0, math_floor(previewValue)))
    local hasPartial = previewValue > filled and filled < numSegments

    local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, filled, holder)

    local color1, color2, color3 = GetResourceColors(powerType, settings)
    local filledColor = color1
    local emptyColor = color1

    if powerType == 5 or powerType == 7 or powerType == 19 then
        local readyColor, rechargingColor, maxColor = color1, color2, color3
        filledColor = (filled >= numSegments) and maxColor or (thresholdActive and thresholdColor or readyColor)
        emptyColor = rechargingColor or readyColor
    elseif powerType == 4 then
        local normalColor, maxColor = color1, color2
        filledColor = (filled >= numSegments) and maxColor or (thresholdActive and thresholdColor or normalColor)
        emptyColor = normalColor
    elseif RESOURCE_COLOR_DEFS[powerType] then
        local normalColor, maxColor = color1, color2
        filledColor = (filled >= numSegments) and maxColor or (thresholdActive and thresholdColor or normalColor)
        emptyColor = normalColor
    end

    for i, seg in ipairs(holder.segments) do
        local color = (i <= filled) and filledColor or emptyColor
        if i == filled + 1 and hasPartial then
            color = emptyColor
        end
        if type(color) == "table" then
            seg:SetStatusBarColor(color[1], color[2], color[3], color[4] ~= nil and color[4] or 1)
        end

        if powerType == 5 and holder._showRechargeText then
            if IsRechargeTextAllSegmentsMode(holder) then
                if i == filled + 1 and hasPartial then
                    SetRechargeText(holder, i, 8)
                else
                    SetRechargeText(holder, i, 0, true)
                end
            elseif i == filled + 1 and hasPartial then
                SetRechargeText(holder, i, 8)
            end
        end
    end
end

RB.StyleContinuousBar = StyleContinuousBar
RB.StyleHealthBar = HealthBar.Style
RB.StyleSegmentedText = StyleSegmentedText
RB.StyleSegmentedBar = StyleSegmentedBar

-- The ordered list ApplyResourceBars materializes: enabled, unsuppressed
-- power types. Pure; the meta-flip watch
-- flag comes back as a second value for the caller that owns stackSwapState.
-- A mutually exclusive pair (the Devourer resources) is filtered here rather
-- than in the spec list itself: DetermineActiveResources also feeds the
-- config's layout preview, which must keep listing both halves whatever the
-- player is currently in. Dropping the hidden half from this one list leaves
-- ordering, stacking and the trailing-frame cleanup entirely to the apply
-- machinery, exactly as a disabled resource does — so the surviving half
-- lands in the slot the pair occupies, ahead of everything after it.
local function CollectActiveBarEntries(settings)
    local filtered = {}
    local watchMetaFlip = false
    for _, pt in ipairs(DetermineActiveResources(settings)) do
        if IsResourceEnabled(pt, settings) then
            if RB.AURA_STACK_RESOURCES[pt] and RB.AURA_STACK_RESOURCES[pt].metaVisibility then
                watchMetaFlip = true
            end
            if not RB.IsAuraStackResourceSuppressed(pt) then
                table.insert(filtered, pt)
            end
        end
    end

    return filtered, watchMetaFlip
end

local function BuildActiveBarSignature(filtered)
    return table.concat(filtered, ",")
end

-- Signature of the list the live bars were last built from; nil while reverted.
local lastAppliedActiveBarSignature = nil

-- True when the bars are applied and a fresh apply would materialize the same
-- ordered list. The form-change lifecycle event uses this to skip the full
-- re-apply (and the stacking pass and aura rebind it queues) for a form that
-- keeps the same resources: Stealth on a rogue, or a druid form under the
-- all-forms union. A druid form that swaps resources, or bars that reverted
-- because their anchor panel hid, still reads as changed.
function CooldownCompanion:ResourceBarsActiveSetUnchanged()
    if not isApplied or not lastAppliedActiveBarSignature then
        return false
    end
    local settings = GetResourceBarSettings()
    if not settings or not settings.enabled then
        return false
    end
    local filtered = CollectActiveBarEntries(settings)
    return BuildActiveBarSignature(filtered) == lastAppliedActiveBarSignature
end

-- Maximum events do not invalidate settings, attachment geometry or aura
-- bindings. Keep their existing synchronous paints, and only enter the apply
-- owner when the active resources or a readable native capacity changed.
function CooldownCompanion:RefreshResourceBarMaximums()
    if not isApplied then return end
    local settings = GetResourceBarSettings()
    if not settings or not settings.enabled then return end

    if not self:ResourceBarsActiveSetUnchanged() then
        self:ApplyResourceBars()
        return
    end

    -- Scan the active native resources, not the event's power token: either
    -- maximum event previously reconciled the entire applied set. Runes have
    -- six slots regardless of UnitPowerMax; aura-stack maxima have other owners.
    for _, barInfo in ipairs(resourceBarFrames) do
        local powerType = barInfo.powerType
        if barInfo.barType == "segmented" and powerType ~= 5
            and not IsUnitPowerMaxSecret("player", powerType) then
            local maximum = UnitPowerMax("player", powerType)
            if not (issecretvalue and issecretvalue(maximum)) then
                local count = math_max(math_floor(maximum), 1)
                if count ~= barInfo.frame._activeSegments then
                    self:ApplyResourceBars()
                    return
                end
            end
        end
    end

    for _, barInfo in ipairs(resourceBarFrames) do
        local frame, powerType = barInfo.frame, barInfo.powerType
        if barInfo.barType == "health_continuous" then
            HealthBar.ApplyFillColor(frame, frame._ccHealthConfig)
            HealthBar.ApplyBackgroundColor(frame, frame._ccHealthConfig)
        elseif barInfo.barType == "continuous" then
            local maximum = UnitPowerMax("player", powerType)
            local maximumIsSecret = IsUnitPowerMaxSecret("player", powerType)
                or (issecretvalue and issecretvalue(maximum))
            UpdateContinuousTickMarker(frame, powerType, settings, maximum, maximumIsSecret)
        elseif barInfo.barType == "segmented" then
            -- Like apply-time painting, this is outside sound sampling. The
            -- normal tick still owns threshold crossings and continuous values.
            ResourceBars.Update(barInfo, settings)
        end
    end
end

function CooldownCompanion:ApplyResourceBars(opts)
    opts = opts or {}
    if not opts.skipRuntimeGate then
        return self:RefreshBarsAndFramesRuntimeFeature("resourceBars", "resource-apply", true)
    end
    if self.RecordBarsAndFramesRuntimeWork then
        self:RecordBarsAndFramesRuntimeWork("resourceApply")
    end

    local settings = GetResourceBarSettings()
    if not settings or not settings.enabled then
        self:DisableResourceBarRuntime()
        return
    end

    local layout = GetSpecLayoutOrder(settings)
    if not layout then
        self:RevertResourceBars()
        return
    end

    local isIndependentStack = CooldownCompanion:IsResourceBarAnchorIndependent()
    local groupId, groupFrame

    if isIndependentStack then
        -- Independent mode: no group needed
        groupId = nil
        groupFrame = nil
    else
        groupId = GetEffectiveAnchorGroupId(settings)
        if not groupId then
            self:RevertResourceBars()
            return
        end

        local group = self.db.profile.groups[groupId]
        if not group or not CooldownCompanion:IsIconLikeDisplayMode(group.displayMode) then
            self:RevertResourceBars()
            return
        end

        groupFrame = CooldownCompanion.groupFrames[groupId]
        if not groupFrame or not groupFrame:IsShown() then
            self:RevertResourceBars()
            return
        end
    end

    local isVerticalLayout = IsVerticalResourceLayout(settings)
    local reverseVerticalFill = IsVerticalFillReversed(settings)

    -- Determine which resources to show
    local filtered, watchMetaFlip = CollectActiveBarEntries(settings)
    stackSwapState.watch = watchMetaFlip
    -- The state this materialization is being built for, so the tick only
    -- reacts to a real change from here.
    stackSwapState.inMeta = stackSwapState.watch and RB.IsInVoidMetamorphosis() or false
    lastAppliedActiveBarSignature = BuildActiveBarSignature(filtered)

    if #filtered == 0 then
        self:RevertResourceBars()
        -- Revert stops the module's OnUpdate, so with the spec's only
        -- enabled resource currently suppressed nothing would be left
        -- watching for the meta flip that brings it back. Start the minimal
        -- watcher instead (see stackSwapState.SetWatcher); the next apply
        -- with real bars, and every revert, tears it down again.
        stackSwapState.SetWatcher(stackSwapState.watch)
        return
    end

    -- Create containers if needed
    if not containerFrameAbove then
        containerFrameAbove = CreateFrame("Frame", "CooldownCompanionResourceBarsAbove", UIParent, "DisableUntrustedLayoutScriptsTemplate")
        containerFrameAbove:SetFrameStrata("MEDIUM")
    end
    if not containerFrameBelow then
        containerFrameBelow = CreateFrame("Frame", "CooldownCompanionResourceBarsBelow", UIParent, "DisableUntrustedLayoutScriptsTemplate")
        containerFrameBelow:SetFrameStrata("MEDIUM")
    end

    RB._barContainers = RB._barContainers or {}
    RB._barContainers.above = containerFrameAbove
    RB._barContainers.below = containerFrameBelow
    for _, lane in ipairs({ "aboveMain", "belowMain" }) do
        if not RB._barContainers[lane] then
            local container = CreateFrame("Frame", nil, UIParent, "DisableUntrustedLayoutScriptsTemplate")
            container:SetFrameStrata("MEDIUM")
            RB._barContainers[lane] = container
        end
        RB._barContainers[lane]:Hide()
    end

    -- Resolve shared geometry before materializing the active resource owners
    local geometryHost = not isIndependentStack and ST.GetModuleGeometryHost("resources") or nil
    local sharedGeometry = ST.ResolveResourceBarGeometry(settings, layout, nil, geometryHost)
    local globalBarThickness = sharedGeometry.thickness
    local barSpacing = sharedGeometry.spacing
    lastAppliedBarSpacing = barSpacing
    lastAppliedBarThickness = globalBarThickness
    lastAppliedOrientation = GetResourceLayoutOrientation(settings)
    lastAppliedLayout = layout
    lastAppliedIndependentStack = isIndependentStack
    local segmentGap = layout.segmentGap or settings.segmentGap or 4
    local totalPrimaryLength
    if isIndependentStack then
        EnsureIndependentStackConfig(settings, layout)
        totalPrimaryLength = layout.independentWidth
    else
        -- Keep the union length for the vertical stack and lifecycle state.
        -- Horizontal slots and containers resolve their own destination body.
        totalPrimaryLength = GetResourcePrimaryLength(groupFrame, settings)
    end

    -- Determine side/order for each bar (per-spec layout)
    local sideList = {}
    local orderList = {}
    local regionRanks = {}
    local placementGroup = RB.GetBarAnchorGroup()
    local fallbackOrder = 900
    for idx, entry in ipairs(filtered) do
        local powerType = entry
        local side, order, region
            -- Placement identity, not the power type: a mutually exclusive
            -- pair shares one slot, so the half that is up reads the
            -- canonical half's side and order and lands where the pair
            -- lives.
            local res = layout and layout.resources
                and layout.resources[RB.GetCanonicalPowerType(powerType)]
            region = res and res.anchorRegion
            if isVerticalLayout then
                local storedHorizontalSide = (res and res.position) or "below"
                side = (res and res.verticalPosition) or GetVerticalSideFallback(storedHorizontalSide)
                order = (res and res.verticalOrder) or (res and res.order) or (fallbackOrder + idx)
            else
                side = (res and res.position) or "below"
                order = (res and res.order) or (fallbackOrder + idx)
            end
        if side then
            if isVerticalLayout then
                if side ~= "left" and side ~= "right" then
                    side = "right"
                end
            else
                if side ~= "above" and side ~= "below" then
                    side = "below"
                end
            end
        end
        if not isIndependentStack then
            region = RB.GetResourceBlockRegion(layout, side, isVerticalLayout)
        end
        side = RB.ResolveBarLane(placementGroup, side, region, isIndependentStack)
        sideList[idx] = side
        regionRanks[idx] = RB.GetBarRegionRank(side, region, placementGroup)
        orderList[idx] = order
    end

    ResourceBars.BeginApply(filtered)
    for idx, powerType in ipairs(filtered) do
        local firstSide = isVerticalLayout and "left" or "above"
        local targetContainer = isVerticalLayout
            and (sideList[idx] == firstSide and containerFrameAbove or containerFrameBelow)
            or RB._barContainers[sideList[idx]]
        local region = isVerticalLayout and RB.GetResourceBlockRegion(layout, sideList[idx], true)
            or ((sideList[idx] == "aboveMain" or sideList[idx] == "belowMain") and "main" or "outer")
        local primaryLength = isIndependentStack and totalPrimaryLength
            or GetResourcePrimaryLength(groupFrame, settings, region == "main" and "main" or "outer")
        local effectiveThickness = ST.ResolveResourceBarGeometry(settings, layout,
            RB.GetCanonicalPowerType(powerType), geometryHost).thickness
        local width = isVerticalLayout and effectiveThickness or primaryLength
        local height = isVerticalLayout and primaryLength or effectiveThickness

        local barInfo, sameVisibleRenderer, countChanged = ResourceBars.Acquire(powerType, settings, targetContainer)
        local frame = barInfo.frame
        local geometryChanged = frame._ccResourceWidth ~= width or frame._ccResourceHeight ~= height
            or frame._isVertical ~= isVerticalLayout or frame._reverseFill ~= reverseVerticalFill
        resourceBarFrames[idx] = barInfo
        ResetResourceBarRuntimeState(frame, sameVisibleRenderer)
        if frame:GetParent() ~= targetContainer then frame:SetParent(targetContainer) end
        RB.SetResourceBarSize(frame, width, height)

        if powerType == RESOURCE_HEALTH then
            HealthBar.Style(frame, settings)
        elseif barInfo.shape == "continuous" then
            local stackCounted = powerType == RESOURCE_MAELSTROM_WEAPON or RB.AURA_STACK_RESOURCES[powerType]
            StyleContinuousBar(frame, powerType, settings, stackCounted and sameVisibleRenderer)
        elseif barInfo.shape == "overlay" then
            LayoutOverlaySegments(frame, width, height, segmentGap, settings, 5)
            StyleSegmentedText(frame, powerType, settings)
        else
            LayoutSegments(frame, width, height, segmentGap, settings)
            if barInfo.barType == "segmented" then
                StyleSegmentedBar(frame, powerType, settings)
            else
                StyleSegmentedText(frame, powerType, settings)
            end
        end
        frame._isVertical, frame._reverseFill = isVerticalLayout, reverseVerticalFill
        barInfo._side, barInfo._order, barInfo._regionRank = sideList[idx], orderList[idx], regionRanks[idx]
        barInfo._effectiveThickness = effectiveThickness
        RB.CompileResourceBarConfig(frame, powerType, settings)

        -- A retained renderer must not show its dormant values or border.
        -- Count/geometry changes also repaint against the finished layout.
        -- Ordinary segmented bars keep their existing synchronous apply paint.
        -- These paints are outside sound sampling: only the regular tick
        -- observes threshold crossings, with history still owned by power type.
        if not sameVisibleRenderer or countChanged or geometryChanged or barInfo.barType == "segmented" then
            ResourceBars.Update(barInfo, settings)
        end
        if not sameVisibleRenderer or countChanged then ResourceBars.FinishMotion(frame) end
        FinalizeAppliedBarVisibility(barInfo)
    end

    -- Aura overlays retain their separate root and binding lifecycle.
    -- Reconcile after active membership and renderer selection are final.
    if RB.ReconcileResourceAuraHolders then
        RB.ReconcileResourceAuraHolders()
    end

    -- Layout: per-element positioning using side containers
    local gap = GetResourceAnchorGap(settings, layout)
    lastAppliedPrimaryLength = totalPrimaryLength
    RB._lastAppliedAnchorGeometry = not isIndependentStack
        and RB.GetBarAnchorGeometry(groupFrame, placementGroup) or nil

    -- Anchor containers to anchor reference (group frame or independent wrapper)
    containerFrameAbove:ClearAllPoints()
    containerFrameBelow:ClearAllPoints()
    if isIndependentStack then
        -- Independent mode: create wrapper frame at saved position, anchor containers to it
        CreateIndependentWrapperFrame()
        local anchor = layout.independentAnchor
        local relFrame = UIParent
        if anchor.relativeTo and anchor.relativeTo ~= "UIParent" then
            relFrame = CooldownCompanion:GetExternalAnchorFrame(anchor.relativeTo)
        end
        independentWrapperFrame:ClearAllPoints()
        independentWrapperFrame:SetPoint(anchor.point, relFrame, anchor.relativePoint, anchor.x, anchor.y)
        independentWrapperFrame:Show()

        if isVerticalLayout then
            containerFrameAbove:SetHeight(totalPrimaryLength)
            containerFrameBelow:SetHeight(totalPrimaryLength)
            containerFrameAbove:SetPoint("RIGHT", independentWrapperFrame, "LEFT", -gap, 0)
            containerFrameBelow:SetPoint("LEFT", independentWrapperFrame, "RIGHT", gap, 0)
        else
            containerFrameAbove:SetWidth(totalPrimaryLength)
            containerFrameBelow:SetWidth(totalPrimaryLength)
            containerFrameAbove:SetPoint("BOTTOM", independentWrapperFrame, "TOP", 0, gap)
            containerFrameBelow:SetPoint("TOP", independentWrapperFrame, "BOTTOM", 0, -gap)
        end

        UpdateIndependentStackDragState(settings, layout)
    elseif groupFrame then
        -- Group-relative mode (original behavior)
        HideIndependentWrapperFrame()
        if isVerticalLayout then
            containerFrameAbove:SetHeight(GetResourcePrimaryLength(groupFrame, settings,
                RB.GetResourceBlockRegion(layout, "left", true) == "main" and "main" or "outer"))
            containerFrameBelow:SetHeight(GetResourcePrimaryLength(groupFrame, settings,
                RB.GetResourceBlockRegion(layout, "right", true) == "main" and "main" or "outer"))
            containerFrameAbove:SetPoint("TOPRIGHT", groupFrame, "TOPLEFT", -gap, 0)
            containerFrameBelow:SetPoint("TOPLEFT", groupFrame, "TOPRIGHT", gap, 0)
        else
            for _, lane in ipairs(RB.ATTACHED_BAR_LANES) do
                local container = RB._barContainers[lane]
                local body = RB.GetBarLaneBody(groupFrame, lane)
                local above = RB.GetBarLaneSide(lane) == "above"
                container:ClearAllPoints()
                local region = (lane == "aboveMain" or lane == "belowMain") and "main" or "outer"
                local width = ST.GetPanelAttachmentDimensions(groupFrame, placementGroup, region)
                container:SetWidth(width)
                container:SetPoint(above and "BOTTOMLEFT" or "TOPLEFT", body,
                    above and "TOPLEFT" or "BOTTOMLEFT", 0, above and gap or -gap)
            end
        end
    end

    -- Position bars within containers (reusable for relayout on visibility change)
    local aboveThickness, belowThickness = RelayoutBars()

    -- Hand the aura block to its mount every pass, empty sides included, so
    -- the mount can park a container the stack no longer feeds. Guarded: the
    -- mount side is a separate owner and may not be present.

    -- Anchor drag chrome to frame the content (after containers are sized)
    if isIndependentStack then
        UpdateIndependentStackChrome(isVerticalLayout, layout, totalPrimaryLength, gap, aboveThickness, belowThickness)
    end

    -- Enable OnUpdate
    if not onUpdateFrame then
        onUpdateFrame = CreateFrame("Frame")
    end
    onUpdateFrame:SetScript("OnUpdate", OnUpdate)
    -- Real bars are up, so the module's own tick polls the flip again: the
    -- empty-list stand-in has no reason to exist.
    stackSwapState.SetWatcher(false)

    -- Enable events
    EnableEventFrame()

    isApplied = true
    RB.ResourceSounds.RetainFrames(resourceBarFrames)

    -- Alpha handling: 3-way branching
    local rbModuleId = "rb"

    if isIndependentStack then
        -- Independent mode: own alpha settings, no group inheritance
        if alphaSyncFrame then
            alphaSyncFrame:SetScript("OnUpdate", nil)
        end
        savedContainerAlpha = nil

        local frames = {}
        if independentWrapperFrame then frames[#frames + 1] = independentWrapperFrame end
        if containerFrameAbove then frames[#frames + 1] = containerFrameAbove end
        if containerFrameBelow then frames[#frames + 1] = containerFrameBelow end
        frames[#frames + 1] = RB._barContainers.aboveMain
        frames[#frames + 1] = RB._barContainers.belowMain
        frames[#frames + 1] = self:GetResourceAuraHostRoot()
        if #frames > 0 then
            CooldownCompanion:RegisterModuleAlpha(rbModuleId, settings, frames)
        end
    elseif layout.inheritAlpha and groupFrame then
        -- Attached + inheriting: sync to group alpha via 30Hz polling
        CooldownCompanion:UnregisterModuleAlpha(rbModuleId)

        if not savedContainerAlpha then
            savedContainerAlpha = containerFrameAbove:GetAlpha()
        end

        local groupAlpha = groupFrame._naturalAlpha or groupFrame:GetEffectiveAlpha()
        containerFrameAbove:SetAlpha(groupAlpha)
        containerFrameBelow:SetAlpha(groupAlpha)
        RB._barContainers.aboveMain:SetAlpha(groupAlpha)
        RB._barContainers.belowMain:SetAlpha(groupAlpha)
        -- Aura host root rides the same alpha writes: the kit visuals fade
        -- with the bars they decorate (plain CC frame; alpha propagates
        -- down through the holders into the slot subtrees engine-side).
        -- Captured as a local: the sync closure below shadows `self`.
        local auraHostRoot = self:GetResourceAuraHostRoot()
        auraHostRoot:SetAlpha(groupAlpha)

        if not alphaSyncFrame then
            alphaSyncFrame = CreateFrame("Frame")
        end
        local lastAlpha = groupAlpha
        local accumulator = 0
        local SYNC_INTERVAL = 1 / 30
        alphaSyncFrame:SetScript("OnUpdate", function(self, dt)
            accumulator = accumulator + dt
            if accumulator < SYNC_INTERVAL then return end
            accumulator = 0
            if not groupFrame then return end
            local alpha = groupFrame._naturalAlpha or groupFrame:GetEffectiveAlpha()
            if alpha ~= lastAlpha then
                lastAlpha = alpha
                if containerFrameAbove then containerFrameAbove:SetAlpha(alpha) end
                if containerFrameBelow then containerFrameBelow:SetAlpha(alpha) end
                RB._barContainers.aboveMain:SetAlpha(alpha)
                RB._barContainers.belowMain:SetAlpha(alpha)
                auraHostRoot:SetAlpha(alpha)
            end
        end)
    else
        -- Attached + NOT inheriting: own alpha settings on container frames
        if alphaSyncFrame then
            alphaSyncFrame:SetScript("OnUpdate", nil)
        end
        savedContainerAlpha = nil

        local frames = {}
        if containerFrameAbove then frames[#frames + 1] = containerFrameAbove end
        if containerFrameBelow then frames[#frames + 1] = containerFrameBelow end
        frames[#frames + 1] = RB._barContainers.aboveMain
        frames[#frames + 1] = RB._barContainers.belowMain
        frames[#frames + 1] = self:GetResourceAuraHostRoot()
        if #frames > 0 then
            CooldownCompanion:RegisterModuleAlpha(rbModuleId, settings, frames)
        end
    end

    -- Native resource overlays keep their restriction-gated binding owner.
    -- Renderer retention does not change the coalesced OOC rebind boundary.
    self:SetResourceAuraHostApplied(true)
    self:RequestAuraRebind("resources")
    local previousPanel = RB._attachedPanelId
    RB._attachedPanelId = groupId
    self:FinishResourceBarLayout(previousPanel, groupId)
end

------------------------------------------------------------------------
-- Revert: hide all resource bars
------------------------------------------------------------------------

function CooldownCompanion:RevertResourceBars()
    RB.ResourceSounds.Reset()
    -- Before the isApplied gate on purpose: the empty-list apply path starts
    -- the meta-flip watcher while the module is NOT applied, so gating this
    -- would leave it running after the feature is switched off.
    stackSwapState.SetWatcher(false)
    if not isApplied then return end
    isApplied = false
    lastAppliedActiveBarSignature = nil
    lastAppliedPrimaryLength = nil
    RB._lastAppliedAnchorGeometry = nil
    lastAppliedOrientation = nil
    lastAppliedLayout = nil
    lastAppliedIndependentStack = false
    lastAppliedBarSpacing = nil
    lastAppliedBarThickness = nil

    -- Stop alpha sync, unregister module alpha, restore alpha
    CooldownCompanion:UnregisterModuleAlpha("rb")
    if alphaSyncFrame then
        alphaSyncFrame:SetScript("OnUpdate", nil)
    end
    if savedContainerAlpha then
        if containerFrameAbove then containerFrameAbove:SetAlpha(savedContainerAlpha) end
        if containerFrameBelow then containerFrameBelow:SetAlpha(savedContainerAlpha) end
    end
    savedContainerAlpha = nil

    -- Aura host root goes dark with the bars (safe in combat: plain CC
    -- frame; a hidden container is inert and self-refreshes on show). The
    -- rebind request parks the custom-bar displays once OOC.
    self:SetResourceAuraHostApplied(false)
    self:GetResourceAuraHostRoot():SetAlpha(1)
    self:RequestAuraRebind("resources")

    -- Stop OnUpdate
    if onUpdateFrame then
        onUpdateFrame:SetScript("OnUpdate", nil)
    end

    -- Stop events
    DisableEventFrame()

    for _, barInfo in ipairs(resourceBarFrames) do ResourceBars.Deactivate(barInfo) end
    wipe(resourceBarFrames)

    if RB._barContainers then
        RB._barContainers.aboveMain:Hide()
        RB._barContainers.belowMain:Hide()
    end
    -- Hide containers and independent wrapper
    if containerFrameAbove then containerFrameAbove:Hide() end
    if containerFrameBelow then containerFrameBelow:Hide() end
    HideIndependentWrapperFrame()

    -- Park the aura block with the stack. Both orientations are reported
    -- empty: the teardown does not know which one the mount last built from.


    isUnlockAssistActive = false
    -- Config-canvas preview state is deliberately NOT cleared here. This
    -- teardown runs for transient live conditions — no anchor group yet, an
    -- anchor that is not icon-like, an anchor frame that is momentarily
    -- hidden — and the canvas keeps rendering from saved data through all of
    -- them. Clearing command state made a running command-center preview die
    -- because of live-frame availability it has nothing to do with.
    -- Ownership sits with ClearAllConfigPreviews and the explicit stops.

    local previousPanel = RB._attachedPanelId
    RB._attachedPanelId = nil
    self:FinishResourceBarLayout(previousPanel, nil)
end

function CooldownCompanion:DisableResourceBarRuntime()
    self._resourceBarsNeedsMWMaxRefresh = true
    DisableLifecycleEvents()
    self:RevertResourceBars()
    -- The feature itself is off, so the bars those previews stand for no
    -- longer exist anywhere — this is the disable path, not the transient
    -- teardown above, and clearing here is the point.
    self:ClearAllHealthEffectPreviews()
    self:ClearAllResourceAuraPreviews()
end

function CooldownCompanion:GetSpecLayoutOrder()
    local settings = GetResourceBarSettings()
    if not settings then return nil end
    return GetSpecLayoutOrder(settings)
end

-- These queries project the config session; transient live-bar teardown does
-- not own its lifetime. A true feature disable still performs matching stops.
function CooldownCompanion:IsResourceAuraActivePreviewActive(powerType)
    local running = ST._ConfigPreview.Get()
    return running ~= nil and running.command.preview.owner == "resource"
        and running.command.preview.powerType == tonumber(powerType)
end

function CooldownCompanion:ClearAllResourceAuraPreviews()
    ST._ConfigPreview.StopOwner("resource")
end

function HealthBar.HasActiveEffectPreview()
    return next(ST._ConfigPreview.GetHealthEffects()) ~= nil
end

function CooldownCompanion:IsHealthEffectPreviewActive(effectKey)
    return ST._ConfigPreview.GetHealthEffects()[effectKey] == true
end

function CooldownCompanion:ClearAllHealthEffectPreviews()
    ST._ConfigPreview.StopOwner("health")
end

function CooldownCompanion:GetResourceBarRuntimeDebugInfo()
    local info = {}
    for idx, barInfo in ipairs(resourceBarFrames) do
        local entry = {
            index = idx,
            powerType = barInfo.powerType,
            barType = barInfo.barType,
            shown = barInfo.frame and barInfo.frame:IsShown() or false,
        }
        info[#info + 1] = entry
    end
    return info
end

function CooldownCompanion:GetResourceBarRuntimeState()
    local lifecycleDebug = lifecycleModule and lifecycleModule.GetDebugInfo and lifecycleModule.GetDebugInfo() or {}
    return {
        applied = isApplied == true,
        onUpdateActive = onUpdateFrame and onUpdateFrame:GetScript("OnUpdate") ~= nil or false,
        alphaSyncActive = alphaSyncFrame and alphaSyncFrame:GetScript("OnUpdate") ~= nil or false,
        lifecycleEventsActive = lifecycleDebug.lifecycleEventsActive == true,
        updateEventsActive = lifecycleDebug.updateEventsActive == true,
        hooksInstalled = lifecycleDebug.hooksInstalled == true,
        activeBarCount = #resourceBarFrames,
    }
end

------------------------------------------------------------------------
-- Evaluate: central decision point
------------------------------------------------------------------------

function CooldownCompanion:EvaluateResourceBars(opts)
    opts = opts or {}
    if not opts.skipRuntimeGate then
        return self:RefreshBarsAndFramesRuntimeFeature("resourceBars", opts.reason or "resource-evaluate")
    end
    if self.RecordBarsAndFramesRuntimeWork then
        self:RecordBarsAndFramesRuntimeWork("resourceEvaluate")
    end

    if self._unsupportedLegacyProfile then
        self:DisableResourceBarRuntime()
        self:RefreshUnlockToolbar()
        return
    end

    local settings = GetResourceBarSettings()
    if not settings or not settings.enabled then
        self:DisableResourceBarRuntime()
        self:RefreshUnlockToolbar()
        return
    end
    local rebuilt = false
    if self._resourceBarsNeedsMWMaxRefresh ~= false then
        self._resourceBarsNeedsMWMaxRefresh = false
        rebuilt = UpdateMWMaxStacks({ skipRuntimeGate = true })
    end
    EnableLifecycleEvents()
    if not rebuilt then
        self:ApplyResourceBars({ skipRuntimeGate = true })
    end
    self:RefreshUnlockToolbar()
end

-- Returns the last visible resource/custom aura bar on `side` with order < upToOrder.
-- Used by CastBar to anchor as the next stacked element.
function CooldownCompanion:GetResourceBarPredecessor(side, upToOrder)
    if not isApplied then return nil end

    local best = nil
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame and barInfo.frame:IsShown()
            and barInfo._side == side
            and barInfo._order < upToOrder then
            if not best then
                best = barInfo
            elseif CompareBarOrder(best, barInfo) then
                best = barInfo
            end
        end
    end

    return best and best.frame or nil
end

-- Resource runtime ownership ends at this descriptor. Positioning is shared
-- with panel entries, while resource ordering and explicit dimensions remain
-- owned by RelayoutBars. No restricted aura dimensions are inspected here.
function CooldownCompanion:GetPanelResourceBlocks(groupId)
    local blocks = {}
    if not isApplied or lastAppliedIndependentStack or RB._attachedPanelId ~= groupId then return blocks end
    local vertical = lastAppliedOrientation == "vertical"
    local lanes = vertical and { "left", "right" } or RB.ATTACHED_BAR_LANES
    for _, lane in ipairs(lanes) do
        local container = vertical and (lane == "left" and containerFrameAbove or containerFrameBelow)
            or RB._barContainers[lane]
        if container and container:IsShown() then
            local side = vertical and lane or RB.GetBarLaneSide(lane)
            local region = vertical and RB.GetResourceBlockRegion(lastAppliedLayout, side, true)
                or ((lane == "aboveMain" or lane == "belowMain") and "main" or "outer")
            region = region == "main" and "main" or "outer"
            local group = self.db.profile.groups[groupId]
            if ST.PanelSupportsAttachedBars(group) then
                region = ST.ResolvePanelAttachmentRegion(group, side, region)
            end
            blocks[side .. ":" .. region] = { frame = container, tail = container }
        end
    end
    return blocks
end

------------------------------------------------------------------------
-- Preview mode
------------------------------------------------------------------------

RB.CreateResourceBarPreviewModule({
    HealthBar = HealthBar,
    GetUnlockAssistActive = function()
        return isUnlockAssistActive
    end,
    SetUnlockAssistActive = function(value)
        isUnlockAssistActive = value == true
    end,
    GetMWMaxStacks = function()
        return mwMaxStacks
    end,
    GetResourceBarSettings = GetResourceBarSettings,
    ApplySegmentedPreviewColors = ApplySegmentedPreviewColors,
})

------------------------------------------------------------------------
-- Hook installation and initialization
------------------------------------------------------------------------

lifecycleModule = RB.CreateResourceBarLifecycleModule({
    GetResourceBarSettings = GetResourceBarSettings,
    GetSpecLayoutOrder = GetSpecLayoutOrder,
    GetEffectiveAnchorGroupId = GetEffectiveAnchorGroupId,
    GetResourcePrimaryLength = GetResourcePrimaryLength,
    GetLastAppliedPrimaryLength = function()
        return lastAppliedPrimaryLength
    end,
    UpdateMWMaxStacks = UpdateMWMaxStacks,
})
EnableLifecycleEvents = lifecycleModule.EnableLifecycleEvents
DisableLifecycleEvents = lifecycleModule.DisableLifecycleEvents
EnableEventFrame = lifecycleModule.EnableEventFrame
DisableEventFrame = lifecycleModule.DisableEventFrame
