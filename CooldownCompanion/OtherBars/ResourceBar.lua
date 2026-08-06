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
local EntryRuntime = ST.EntryRuntime
local ClearStatusBarMotion = ST.ClearStatusBarMotion
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue
local SetStatusBarSegmentedValue = ST.SetStatusBarSegmentedValue
local UnbindDurationText = CooldownCompanion.UnbindDurationText or function() end

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

-- Immutable — shared across calls; never write to this table.
local CLEAR_CUSTOM_AURA_STACKS_OPTS = { clearCustomAuraStacks = true }

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
local GetSpecCustomAuraBars = RB.GetSpecCustomAuraBars
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

local function CancelCoordinateEdit(coordLabel)
    if not (coordLabel and coordLabel.xEdit and coordLabel.yEdit) then
        return
    end

    coordLabel._editGeneration = (coordLabel._editGeneration or 0) + 1
    coordLabel._editing = nil
    coordLabel.xEdit:ClearFocus()
    coordLabel.yEdit:ClearFocus()
    coordLabel.xLabel:Hide()
    coordLabel.yLabel:Hide()
    coordLabel.xEdit:Hide()
    coordLabel.yEdit:Hide()
    coordLabel.text:Show()
end

local function CreateEditableCoordLabel(coordLabel, getCoordinates, applyCoordinates, isDragging)
    local xLabel = coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    xLabel:SetText("x:")
    xLabel:SetTextColor(1, 1, 1, 0.8)
    xLabel:SetPoint("LEFT", coordLabel, "LEFT", 2, 0)
    xLabel:Hide()

    local xEdit = CreateFrame("EditBox", nil, coordLabel)
    xEdit:SetAutoFocus(false)
    xEdit:SetFontObject(GameFontNormalSmall)
    xEdit:SetTextColor(1, 1, 1, 1)
    xEdit:SetJustifyH("CENTER")
    xEdit:SetPoint("LEFT", xLabel, "RIGHT", 1, 0)
    xEdit:SetPoint("RIGHT", coordLabel, "CENTER", -1, 0)
    xEdit:SetHeight(13)
    xEdit:Hide()

    local yLabel = coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    yLabel:SetText("y:")
    yLabel:SetTextColor(1, 1, 1, 0.8)
    yLabel:SetPoint("LEFT", coordLabel, "CENTER", 1, 0)
    yLabel:Hide()

    local yEdit = CreateFrame("EditBox", nil, coordLabel)
    yEdit:SetAutoFocus(false)
    yEdit:SetFontObject(GameFontNormalSmall)
    yEdit:SetTextColor(1, 1, 1, 1)
    yEdit:SetJustifyH("CENTER")
    yEdit:SetPoint("LEFT", yLabel, "RIGHT", 1, 0)
    yEdit:SetPoint("RIGHT", coordLabel, "RIGHT", -2, 0)
    yEdit:SetHeight(13)
    yEdit:Hide()

    coordLabel.xLabel = xLabel
    coordLabel.yLabel = yLabel
    coordLabel.xEdit = xEdit
    coordLabel.yEdit = yEdit
    coordLabel:EnableMouse(true)

    local function CommitEdit()
        if not coordLabel._editing then
            return
        end

        local newX = tonumber(xEdit:GetText())
        local newY = tonumber(yEdit:GetText())
        if newX == nil or newY == nil then
            CancelCoordinateEdit(coordLabel)
            return
        end

        newX = RoundToTenths(newX)
        newY = RoundToTenths(newY)
        local oldX, oldY = getCoordinates()
        oldX = RoundToTenths(tonumber(oldX) or 0)
        oldY = RoundToTenths(tonumber(oldY) or 0)
        CancelCoordinateEdit(coordLabel)
        if newX ~= oldX or newY ~= oldY then
            applyCoordinates(newX, newY)
        end
    end

    local function BeginEdit()
        if coordLabel._editing or (isDragging and isDragging()) then
            return
        end

        local x, y = getCoordinates()
        coordLabel._editGeneration = (coordLabel._editGeneration or 0) + 1
        coordLabel._editing = true
        coordLabel.text:Hide()
        xEdit:SetText(("%.1f"):format(tonumber(x) or 0))
        yEdit:SetText(("%.1f"):format(tonumber(y) or 0))
        xLabel:Show()
        yLabel:Show()
        xEdit:Show()
        yEdit:Show()
        xEdit:SetFocus()
        xEdit:HighlightText()
    end

    local function HandleFocusLost(self)
        self:HighlightText(0, 0)
        local generation = coordLabel._editGeneration
        C_Timer.After(0, function()
            if coordLabel._editing
                and coordLabel._editGeneration == generation
                and not xEdit:HasFocus()
                and not yEdit:HasFocus() then
                CommitEdit()
            end
        end)
    end

    xEdit:SetScript("OnEnterPressed", CommitEdit)
    yEdit:SetScript("OnEnterPressed", CommitEdit)
    xEdit:SetScript("OnEscapePressed", function() CancelCoordinateEdit(coordLabel) end)
    yEdit:SetScript("OnEscapePressed", function() CancelCoordinateEdit(coordLabel) end)
    xEdit:SetScript("OnTabPressed", function()
        yEdit:SetFocus()
        yEdit:HighlightText()
    end)
    yEdit:SetScript("OnTabPressed", function()
        xEdit:SetFocus()
        xEdit:HighlightText()
    end)
    xEdit:SetScript("OnEditFocusLost", HandleFocusLost)
    yEdit:SetScript("OnEditFocusLost", HandleFocusLost)
    xEdit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    yEdit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    coordLabel:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.3, 0.3, 0.9)
    end)
    coordLabel:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    end)
    coordLabel:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            BeginEdit()
        end
    end)
    coordLabel:SetScript("OnHide", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
        CancelCoordinateEdit(self)
    end)
end

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
local CreateContinuousBar = RB.CreateContinuousBar
local CreateSegmentedBar = RB.CreateSegmentedBar
local LayoutSegments = RB.LayoutSegments
local CreateOverlayBar = RB.CreateOverlayBar
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

local isApplied = false
local onUpdateFrame = nil
local containerFrameAbove = nil
local containerFrameBelow = nil
local lastAppliedPrimaryLength = nil
local lastAppliedOrientation = nil
local lastAppliedLayout = nil
local lastAppliedIndependentStack = false
local resourceBarFrames = {}   -- array of bar frame objects (ordered by stacking)
local activeResources = {}     -- array of power type ints currently displayed
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
    return frame and frame._dragHandle, frame and frame._coordLabel, frame and frame._nudger
end

function CooldownCompanion:SetIndependentResourceStackLocked(locked)
    local settings = GetResourceBarSettings()
    if not settings then return end
    local placementSettings = GetSpecLayoutOrder(settings)
    if not placementSettings then return end
    placementSettings.independentAnchorLocked = locked == true
    self:ApplyResourceBars()
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

local activeCustomAuraBarActivePreviews = {}
local activeCustomAuraBarPandemicPreviews = {}
-- Resource aura overlay previews, keyed by POWER TYPE. Never by barInfo or
-- frame: a form change rebuilds the positional bar array, and the power
-- type is the only identity that survives it.
local activeResourceAuraPreviews = {}
local segmentedUpdateScratch = {}
local HealthBar = RB.HealthBar
local HEALTH_EFFECTS = RB.HealthEffects
local lifecycleModule = nil

local function ResetCustomAuraBarIndicatorVisuals(bar, cabConfig)
    if not bar then return end

    bar._barAuraColor = nil
    bar._barPulseActive = nil
    bar._barPulseSpeed = nil
    bar._barColorShiftActive = nil
    bar._barCSBaseColor = nil
    bar._barCSShiftColor = nil
    bar._barCSSpeed = nil
    local fillTexture = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if fillTexture and fillTexture.SetAlpha then
        fillTexture:SetAlpha(1)
    end

    local baseColor = (cabConfig and cabConfig.barColor) or {0.5, 0.5, 1}
    bar:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)

    if bar.barAuraEffect then
        SetBarAuraEffect(bar, false, false)
    end
end

local function IsCustomBarAuraIndicatorFrame(barInfo)
    if not barInfo then
        return false
    end
    return barInfo.barType == "custom_continuous"
        or barInfo.barType == "custom_cooldown"
end

local function ClearCustomAuraBarIndicatorVisualState(barInfo, clearPreviewFlags)
    if not IsCustomBarAuraIndicatorFrame(barInfo) then
        return
    end

    local bar = barInfo and barInfo.frame
    if not bar then return end

    if clearPreviewFlags then
        bar._barAuraActivePreview = nil
        bar._barPandemicPreview = nil
    end

    ResetCustomAuraBarIndicatorVisuals(bar, barInfo.cabConfig)
end

local function ClearCustomAuraBarIndicatorState(barInfo, clearPreviewFlags)
    if not IsCustomBarAuraIndicatorFrame(barInfo) then
        return
    end

    local bar = barInfo and barInfo.frame
    if not bar then return end

    EntryRuntime.ClearTrackedAuraOwnerState(bar, nil, CLEAR_CUSTOM_AURA_STACKS_OPTS)

    ClearCustomAuraBarIndicatorVisualState(barInfo, clearPreviewFlags)
end

local function AnimateCustomAuraBarIndicator(bar)
    if not bar then return end

    local now = GetTime()
    local fillTexture = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if bar._barPulseActive then
        local speed = bar._barPulseSpeed or 0.5
        if fillTexture and fillTexture.SetAlpha then
            fillTexture:SetAlpha(0.6 + 0.4 * math_sin(now * 2 * math_pi / speed))
        end
    elseif fillTexture and fillTexture.SetAlpha then
        fillTexture:SetAlpha(1)
    end

    if bar._barColorShiftActive then
        local base = bar._barCSBaseColor
        local shift = bar._barCSShiftColor
        if base and shift then
            local speed = bar._barCSSpeed or 0.5
            local t = 0.5 + 0.5 * math_sin(now * 2 * math_pi / speed)
            local baseAlpha = base[4] or 1
            bar:SetStatusBarColor(
                base[1] + (shift[1] - base[1]) * t,
                base[2] + (shift[2] - base[2]) * t,
                base[3] + (shift[3] - base[3]) * t,
                baseAlpha + ((shift[4] or 1) - baseAlpha) * t
            )
        else
            bar._barColorShiftActive = nil
        end
    end
end

-- The aura pass (12.1): the kit renders all live aura effects, so the only
-- thing that can arm this is the config canvas's Active Aura stand-in — the
-- preview flag is set on canvas frames alone, and live bars only ever reach
-- the reset leg.
local function UpdateCustomAuraBarIndicatorVisuals(barInfo, cabConfig)
    local isSpellCustomCooldown = barInfo and barInfo.barType == "custom_cooldown"
    if not barInfo or (barInfo.barType ~= "custom_continuous" and not isSpellCustomCooldown) then return end
    if not cabConfig
        or (isSpellCustomCooldown and cabConfig.auraTracking ~= true)
        or (not isSpellCustomCooldown and cabConfig.trackingMode ~= "active") then
        ClearCustomAuraBarIndicatorVisualState(barInfo, false)
        return
    end

    local bar = barInfo.frame
    if not bar then return end

    local auraPreview = bar._barAuraActivePreview

    if not auraPreview then
        ResetCustomAuraBarIndicatorVisuals(bar, cabConfig)
        return
    end

    local wantAuraColor = cabConfig.barAuraColor
        or (isSpellCustomCooldown and {0.2, 1.0, 0.2, 1.0})
        or (cabConfig.barColor or {0.5, 0.5, 1})

    -- Pandemic stand-in (PTR 8 Phase 2): only meaningful over the aura fill.
    local pandemicPreview = bar._barPandemicPreview == true
        and cabConfig.pandemicEffect == true

    bar._barAuraColor = wantAuraColor
    if not bar._barColorShiftActive then
        bar:SetStatusBarColor(wantAuraColor[1], wantAuraColor[2], wantAuraColor[3], wantAuraColor[4] or 1)
    end

    if not bar.barAuraEffect then
        bar.barAuraEffect = CreateGlowContainer(bar, 32, false)
    end
    SetBarAuraEffect(bar, true, false)

    if cabConfig.barAuraPulseEnabled then
        bar._barPulseActive = true
        bar._barPulseSpeed = cabConfig.barAuraPulseSpeed or 0.5
    elseif bar._barPulseActive then
        bar._barPulseActive = nil
        bar._barPulseSpeed = nil
        local fillTexture = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        if fillTexture and fillTexture.SetAlpha then
            fillTexture:SetAlpha(1)
        end
    end

    -- Color shift yields while the pandemic color wears the fill (the panel
    -- mirror rule: shift suppressed, pulse kept).
    if cabConfig.barAuraColorShiftEnabled and not pandemicPreview then
        bar._barColorShiftActive = true
        bar._barCSBaseColor = wantAuraColor
        bar._barCSShiftColor = cabConfig.barAuraColorShiftColor or {1, 1, 1, 1}
        bar._barCSSpeed = cabConfig.barAuraColorShiftSpeed or 0.5
    elseif bar._barColorShiftActive then
        bar._barColorShiftActive = nil
        bar._barCSBaseColor = nil
        bar._barCSShiftColor = nil
        bar._barCSSpeed = nil
        bar:SetStatusBarColor(wantAuraColor[1], wantAuraColor[2], wantAuraColor[3], wantAuraColor[4] or 1)
    end

    -- Last write wins: the pandemic color REPLACES the aura color, opaque
    -- (owner ruling), matching the live clone's forced-opaque render.
    if pandemicPreview then
        local pc = cabConfig.pandemicColor
        bar:SetStatusBarColor((pc and pc[1]) or 1, (pc and pc[2]) or 0.5, (pc and pc[3]) or 0, 1)
    end
end
local function ClearStaleRecycledBarRuntimeState(frame)
    if not frame then return end
    UnbindFrameDurationText(frame)
    ClearStatusBarMotion(frame)
    if frame._cdcCustomAuraAlphaModuleId then
        CooldownCompanion:UnregisterModuleAlpha(frame._cdcCustomAuraAlphaModuleId)
        frame._cdcCustomAuraAlphaModuleId = nil
    end
    frame._cdcCustomAuraAlphaMode = nil
    frame._cdcIndependentBarInfo = nil
    frame:SetMovable(false)
    frame:EnableMouse(false)
    frame:RegisterForDrag()

    if frame._cdcIndependentDragHandle then
        frame._cdcIndependentDragHandle:EnableMouse(false)
        frame._cdcIndependentDragHandle:RegisterForDrag()
        frame._cdcIndependentDragHandle:Hide()
    end
    if frame._cdcIndependentNudger then
        if frame._cdcIndependentNudger._cdcButtons then
            for _, btn in ipairs(frame._cdcIndependentNudger._cdcButtons) do
                btn:EnableMouse(false)
            end
        end
        frame._cdcIndependentNudger:EnableMouse(false)
        frame._cdcIndependentNudger:Hide()
    end

    if frame._cdcIndependentAlphaSync then
        frame._cdcIndependentAlphaSync:SetScript("OnUpdate", nil)
    end
    frame._cdcIndependentAlphaTarget = nil
    frame._cdcIndependentLastAlpha = nil
    -- MW max-stack border: cleared so a recycled frame that stops being an
    -- MW shape never keeps a lit border (no MW tick runs on it to clear
    -- it). A frame still MW re-lights on its next update — the key
    -- mismatch makes that one restyle.
    local mwBorder = frame._ccMWMaxBorder
    if mwBorder and mwBorder.key ~= "off" then
        mwBorder.key = "off"
        if mwBorder.glow then
            ST._StyleKitBarGlowRegions(mwBorder.glow, nil, mwBorder.host, false)
        end
        if mwBorder.segBorders then
            ST._StyleKitSegmentBorders(mwBorder.segBorders, nil, nil, 0, false)
        end
    end
    -- Aura-pass absent-state blocks: hidden for the apply pass;
    -- FinalizeAppliedBarVisibility re-lays them from the cached max for
    -- bars that still want them (recycled frames stay clean).
    if frame._ccCabStackBlocksActive then
        frame._ccCabStackBlocksActive = nil
        ST.HideStackBlocks(frame._ccCabStackBlocks)
        ST.HideStackBlockBorders(frame._ccCabStackBlockBorders)
        -- Blocks mode zeroes the background region (the blocks ARE the
        -- background there). Restore it with the blocks: this frame may be
        -- handed to a resource bar next, and only custom bars re-run the
        -- absent-state pass that would otherwise repair it.
        if frame.bg then
            frame.bg:SetAlpha(1)
        end
    end
    EntryRuntime.ClearTrackedAuraOwnerState(frame, nil, CLEAR_CUSTOM_AURA_STACKS_OPTS)
    EntryRuntime.ReleaseTrackedAuraScratch(frame)
    frame._parsedAuraIDs = nil
    frame._parsedAuraIDsRaw = nil
    frame._parsedAuraIDsButtonID = nil
    frame._parsedAuraIDsIncludeButtonID = nil
    frame._customCooldownBaseSpellID = nil
    frame._customCooldownSpellID = nil
    frame._customCooldownHasCharges = nil
    frame._cooldownSecrecy = nil
    frame._cooldownSecrecySpellID = nil
    frame._noCooldown = nil
    frame._noCooldownSpellId = nil
    frame._currentReadableCharges = nil
    frame._chargeCountReadable = nil
    frame._zeroChargesConfirmed = nil
    frame._chargeDurationObj = nil
    frame._chargeRecharging = nil
    frame._mainCDShown = nil
    frame._chargeState = nil
    frame._chargesSpent = nil
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

local function LockIndependentStackFromMover(frame)
    local settings = GetResourceBarSettings()
    if not settings then return end
    local placementSettings = GetSpecLayoutOrder(settings)
    if not placementSettings then return end
    placementSettings.independentAnchorLocked = true
    frame._dragInProgress = nil
    StopIndependentStackCoordUpdates(frame)
    frame:StopMovingOrSizing()
    SaveIndependentStackAnchor(true)
    CooldownCompanion:EndMoverChromeFade(frame)
    UpdateIndependentStackDragState(settings, placementSettings)
    CooldownCompanion:CaptureArrangeResourceRecord()
    CooldownCompanion:CheckArrangeModeAutoExit()
end

local function CreateResourceBarLockButton(parent, onLock)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(INDEPENDENT_NUDGE_BTN_SIZE, INDEPENDENT_NUDGE_BTN_SIZE)
    button:RegisterForClicks("LeftButtonUp")

    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetSize(INDEPENDENT_NUDGE_BTN_SIZE - 2, INDEPENDENT_NUDGE_BTN_SIZE - 2)
    icon:SetPoint("CENTER")
    icon:SetAtlas("questlog-questtypeicon-lock", false)
    icon:SetVertexColor(0.8, 0.8, 0.8, 0.8)
    button.icon = icon

    button:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Lock")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.8, 0.8, 0.8, 0.8)
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(self)
        self.icon:SetVertexColor(0.8, 0.8, 0.8, 0.8)
        onLock()
    end)

    return button
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

    -- Drag handle (full-width, anchored to containers by UpdateIndependentStackChrome)
    local dragHandle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    dragHandle:SetHeight(15)
    dragHandle:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    dragHandle:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    dragHandle:SetBackdropBorderColor(0, 0, 0, 1)
    dragHandle:EnableMouse(false)
    dragHandle:Hide()

    dragHandle.text = dragHandle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragHandle.text:SetPoint("CENTER")
    dragHandle.text:SetText("Resource Bars")
    dragHandle.text:SetTextColor(1, 1, 1, 1)

    dragHandle.lockButton = CreateResourceBarLockButton(dragHandle, function()
        LockIndependentStackFromMover(frame)
    end)
    dragHandle.lockButton:SetPoint("RIGHT", dragHandle, "RIGHT", -2, 0)
    dragHandle.text:ClearAllPoints()
    dragHandle.text:SetPoint("LEFT", dragHandle, "LEFT", 16, 0)
    dragHandle.text:SetPoint("RIGHT", dragHandle, "RIGHT", -16, 0)
    dragHandle.text:SetJustifyH("CENTER")

    -- Nudger (4-direction pixel nudge, same pattern as custom aura bars)
    local NUDGE_GAP = 2
    local nudger = CreateFrame("Frame", nil, dragHandle, "BackdropTemplate")
    nudger:SetSize(INDEPENDENT_NUDGE_BTN_SIZE * 2 + NUDGE_GAP, INDEPENDENT_NUDGE_BTN_SIZE * 2 + NUDGE_GAP)
    nudger:SetPoint("BOTTOM", dragHandle, "TOP", 0, 2)
    nudger:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    nudger:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    nudger:SetBackdropBorderColor(0, 0, 0, 1)
    nudger:EnableMouse(false)
    nudger._cdcButtons = {}
    nudger:SetScript("OnEnter", function(self)
        CooldownCompanion:BeginMoverChromeHoverFade(self)
    end)
    nudger:SetScript("OnLeave", function(self)
        if not self:IsMouseOver() then
            CooldownCompanion:EndMoverChromeFade(self)
        end
    end)
    nudger:SetScript("OnHide", function(self)
        CooldownCompanion:EndMoverChromeFade(self)
    end)

    local directions = {
        { atlas = "common-dropdown-icon-back", rotation = -math.pi / 2, anchor = "BOTTOM", dx = 0, dy = 1, ox = 0, oy = NUDGE_GAP },
        { atlas = "common-dropdown-icon-next", rotation = -math.pi / 2, anchor = "TOP", dx = 0, dy = -1, ox = 0, oy = -NUDGE_GAP },
        { atlas = "common-dropdown-icon-back", rotation = 0, anchor = "RIGHT", dx = -1, dy = 0, ox = -NUDGE_GAP, oy = 0 },
        { atlas = "common-dropdown-icon-next", rotation = 0, anchor = "LEFT", dx = 1, dy = 0, ox = NUDGE_GAP, oy = 0 },
    }

    for _, dir in ipairs(directions) do
        local btn = CreateFrame("Button", nil, nudger)
        btn:SetSize(INDEPENDENT_NUDGE_BTN_SIZE, INDEPENDENT_NUDGE_BTN_SIZE)
        btn:SetPoint(dir.anchor, nudger, "CENTER", dir.ox, dir.oy)
        btn:EnableMouse(true)

        local arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetAtlas(dir.atlas, false)
        arrow:SetAllPoints()
        arrow:SetRotation(dir.rotation)
        arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
        btn.arrow = arrow

        local function DoNudge()
            local settings = GetResourceBarSettings()
            if not settings then return end
            local placementSettings = GetSpecLayoutOrder(settings)
            if not placementSettings then return end
            if placementSettings.independentAnchorLocked then return end
            frame:AdjustPointsOffset(dir.dx, dir.dy)
            -- Write position per step and update coord label (GroupFrame pattern)
            local _, _, _, x, y = frame:GetPoint()
            if x and y then
                EnsureIndependentStackConfig(settings, placementSettings)
                placementSettings.independentAnchor.x = RoundToTenths(x)
                placementSettings.independentAnchor.y = RoundToTenths(y)
                UpdateIndependentStackCoordLabel(frame, x, y)
            end
        end

        btn:SetScript("OnEnter", function(self)
            self.arrow:SetVertexColor(1, 1, 1, 1)
            CooldownCompanion:BeginMoverChromeHoverFade(nudger)
        end)
        btn:SetScript("OnLeave", function(self)
            self.arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
            SaveIndependentStackAnchor(true)
            if not nudger:IsMouseOver() then
                CooldownCompanion:EndMoverChromeFade(nudger)
            end
        end)
        btn:SetScript("OnMouseDown", function(self)
            CancelCoordinateEdit(frame._coordLabel)
            DoNudge()
            CooldownCompanion:VerifyMoverChromeHoverFade(nudger)
        end)
        btn:SetScript("OnMouseUp", function(self)
            SaveIndependentStackAnchor(true)
        end)

        nudger._cdcButtons[#nudger._cdcButtons + 1] = btn
    end

    -- Coordinate label (parented to dragHandle, anchored by UpdateIndependentStackChrome)
    local coordLabel = CreateFrame("Frame", nil, dragHandle, "BackdropTemplate")
    coordLabel:SetHeight(15)
    coordLabel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    coordLabel:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    coordLabel:SetBackdropBorderColor(0, 0, 0, 1)
    coordLabel.text = coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    coordLabel.text:SetPoint("CENTER")
    coordLabel.text:SetTextColor(1, 1, 1, 1)
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
        end
    )

    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        CancelCoordinateEdit(coordLabel)
        local settings = GetResourceBarSettings()
        if not settings then return end
        local placementSettings = GetSpecLayoutOrder(settings)
        if not placementSettings then return end
        if placementSettings.independentAnchorLocked then return end
        if InCombatLockdown() then return end
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

    frame._dragHandle = dragHandle
    frame._nudger = nudger
    frame._coordLabel = coordLabel
    independentWrapperFrame = frame
    CooldownCompanion:ApplyMoverChromeFadeToFrames(dragHandle, coordLabel, nudger)
end

UpdateIndependentStackDragState = function(settings, placementSettings)
    if not independentWrapperFrame then return end
    local frame = independentWrapperFrame
    placementSettings = placementSettings or (settings and GetSpecLayoutOrder(settings)) or settings
    local unlocked = placementSettings
        and placementSettings.independentAnchorEnabled == true
        and not placementSettings.independentAnchorLocked
        and not CooldownCompanion._combatForcedLock
    if not unlocked and frame._dragInProgress then
        CooldownCompanion:CancelIndependentResourceStackDrag()
    end

    frame:SetMovable(unlocked or false)

    if frame._dragHandle then
        frame._dragHandle:SetShown(unlocked or false)
        frame._dragHandle:EnableMouse(unlocked or false)
        if unlocked then
            frame._dragHandle:RegisterForDrag("LeftButton")
        else
            frame._dragHandle:RegisterForDrag()
        end
    end

    if frame._nudger then
        frame._nudger:SetShown(unlocked or false)
        frame._nudger:EnableMouse(unlocked or false)
        if frame._nudger._cdcButtons then
            for _, btn in ipairs(frame._nudger._cdcButtons) do
                btn:EnableMouse(unlocked or false)
            end
        end
    end

    if frame._coordLabel then
        frame._coordLabel:SetShown(unlocked or false)
    end
    CooldownCompanion:ApplyMoverChromeFadeToFrames(frame._dragHandle, frame._coordLabel, frame._nudger)

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
    if independentWrapperFrame._cdcUnlockAssist then
        independentWrapperFrame._cdcUnlockAssist = false
        CooldownCompanion:StopResourceBarUnlockAssist()
    end
end

--- Re-anchor drag handle and coord label to frame the bar content.
--- Called after containers are positioned and RelayoutBars() completes.
local function UpdateIndependentStackChrome(isVerticalLayout, placementSettings)
    if not independentWrapperFrame then return end
    if not containerFrameAbove or not containerFrameBelow then return end
    local frame = independentWrapperFrame

    -- Anchor chrome to the containers that actually have bars to avoid dead space.
    -- When all bars are on one side, the empty container is hidden (height/width=1).
    local aboveShown = containerFrameAbove:IsShown()
    local belowShown = containerFrameBelow:IsShown()

    local snapRect = frame._dragSnapRectFrame
    if snapRect then
        snapRect:ClearAllPoints()
        if not aboveShown and not belowShown then
            snapRect:Hide()
        elseif isVerticalLayout then
            local leftRef = aboveShown and containerFrameAbove or containerFrameBelow
            local rightRef = belowShown and containerFrameBelow or containerFrameAbove
            snapRect:SetPoint("TOPLEFT", leftRef, "TOPLEFT")
            snapRect:SetPoint("BOTTOMRIGHT", rightRef, "BOTTOMRIGHT")
            snapRect:Show()
        else
            local topRef = aboveShown and containerFrameAbove or containerFrameBelow
            local bottomRef = belowShown and containerFrameBelow or containerFrameAbove
            snapRect:SetPoint("TOPLEFT", topRef, "TOPLEFT")
            snapRect:SetPoint("BOTTOMRIGHT", bottomRef, "BOTTOMRIGHT")
            snapRect:Show()
        end
    end

    local dragHandle = frame._dragHandle
    if dragHandle then
        dragHandle:ClearAllPoints()
        if isVerticalLayout then
            -- Vertical: bars are left/right of wrapper — span across both containers
            local topLeft = aboveShown and containerFrameAbove or containerFrameBelow
            local topRight = belowShown and containerFrameBelow or containerFrameAbove
            dragHandle:SetPoint("BOTTOMLEFT", topLeft, "TOPLEFT", 0, 2)
            dragHandle:SetPoint("BOTTOMRIGHT", topRight, "TOPRIGHT", 0, 2)
        else
            -- Horizontal: anchor above whichever container is the topmost with bars
            local topRef = aboveShown and containerFrameAbove or containerFrameBelow
            dragHandle:SetPoint("BOTTOMLEFT", topRef, "TOPLEFT", 0, 2)
            dragHandle:SetPoint("BOTTOMRIGHT", topRef, "TOPRIGHT", 0, 2)
        end
    end

    local coordLabel = frame._coordLabel
    if coordLabel then
        coordLabel:ClearAllPoints()
        if isVerticalLayout then
            local botLeft = aboveShown and containerFrameAbove or containerFrameBelow
            local botRight = belowShown and containerFrameBelow or containerFrameAbove
            coordLabel:SetPoint("TOPLEFT", botLeft, "BOTTOMLEFT", 0, -2)
            coordLabel:SetPoint("TOPRIGHT", botRight, "BOTTOMRIGHT", 0, -2)
        else
            -- Horizontal: anchor below whichever container is the bottommost with bars
            local botRef = belowShown and containerFrameBelow or containerFrameAbove
            coordLabel:SetPoint("TOPLEFT", botRef, "BOTTOMLEFT", 0, -2)
            coordLabel:SetPoint("TOPRIGHT", botRef, "BOTTOMRIGHT", 0, -2)
        end

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

local function HideRechargeTexts(holder)
    if not (holder and holder.rechargeTexts) then return end
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
        text:ClearAllPoints()
        text:SetPoint(anchor, holder.segments[i], anchor, xOffset, yOffset)
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

local function UpdateSegmentedBar(holder, powerType, settings)
    if not holder or not holder.segments then return end
    if not settings then
        settings = GetResourceBarSettings()
    end

    local segmentedSmoothing = GetResourceSegmentedSmoothing(settings)
    HideRechargeTexts(holder)

    if powerType == 5 then
        -- DK Runes: sorted by readiness (ready left, longest CD right)
        local now = GetTime()
        local numSegs = math_min(#holder.segments, 6)
        local runeData = segmentedUpdateScratch.GetRuneData(holder)
        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown(i)
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
        local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, readyCount)
        local activeReadyColor = allReady and maxColor or (thresholdActive and thresholdColor or readyColor)
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
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
            return
        end

        -- Soul Shards: fractional fill with ready/recharging colors
        local raw = UnitPower("player", 7, true)
        local rawMax = UnitPowerMax("player", 7, true)
        local max = UnitPowerMax("player", 7)
        if issecretvalue and (issecretvalue(raw) or issecretvalue(rawMax) or issecretvalue(max)) then
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
            return
        end

        local displayCurrent
        if max > 0 and rawMax > 0 then
            local perShard = rawMax / max
            if perShard > 0 then
                local filled = math_floor(raw / perShard)
                local partial = (raw % perShard) / perShard
                displayCurrent = filled + partial
                local readyColor, rechargingColor, maxColor = GetResourceColors(7, settings)
                local isMax = (filled == max)
                local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, filled)
                local activeReadyColor = isMax and maxColor or (thresholdActive and thresholdColor or readyColor)
                for i = 1, math_min(#holder.segments, max) do
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
        if type(displayCurrent) == "number" then
            segmentedUpdateScratch.FinishText(holder, displayCurrent, max, false)
        else
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
        end
        return
    end

    if powerType == 19 then
        if IsUnitPowerSecret("player", 19) or IsUnitPowerMaxSecret("player", 19) then
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
            return
        end

        -- Essence: partial recharge with ready/recharging colors
        local filled = UnitPower("player", 19)
        local max = UnitPowerMax("player", 19)
        local partialRaw = UnitPartialPower("player", 19)
        if issecretvalue and (issecretvalue(filled) or issecretvalue(max) or issecretvalue(partialRaw)) then
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
            return
        end

        local partial = partialRaw / 1000
        local displayCurrent = filled + partial
        local readyColor, rechargingColor, maxColor = GetResourceColors(19, settings)
        local isMax = (filled == max)
        local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, filled)
        local activeReadyColor = isMax and maxColor or (thresholdActive and thresholdColor or readyColor)
        for i = 1, math_min(#holder.segments, max) do
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
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
            return
        end

        local current = UnitPower("player", 4)
        local max = UnitPowerMax("player", 4)
        if issecretvalue and (issecretvalue(current) or issecretvalue(max)) then
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.FinishText(holder, nil, nil, true)
            return
        end

        local normalColor, maxColor, chargedColor = GetResourceColors(4, settings)
        local isMax = (current == max and max > 0)
        local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, current)
        local baseColor = isMax and maxColor or (thresholdActive and thresholdColor or normalColor)

        -- Charged combo points (Rogue only)
        local chargedPoints
        if GetPlayerClassID() == 4 then
            chargedPoints = GetUnitChargedPowerPoints("player")
        end

        for i = 1, math_min(#holder.segments, max) do
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
        segmentedUpdateScratch.ClearValues(holder)
        segmentedUpdateScratch.FinishText(holder, nil, nil, true)
        return
    end

    local current = UnitPower("player", powerType)
    local max = UnitPowerMax("player", powerType)
    if issecretvalue and (issecretvalue(current) or issecretvalue(max)) then
        segmentedUpdateScratch.ClearValues(holder)
        segmentedUpdateScratch.FinishText(holder, nil, nil, true)
        return
    end
    local normalColor, maxColor
    if RESOURCE_COLOR_DEFS[powerType] then
        normalColor, maxColor = GetResourceColors(powerType, settings)
    else
        local color = GetResourceColors(powerType, settings)
        normalColor, maxColor = color, color
    end
    local isMax = (current == max and max > 0)
    local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, current)
    local activeColor = isMax and maxColor or (thresholdActive and thresholdColor or normalColor)
    for i = 1, math_min(#holder.segments, max) do
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
-- Maelstrom Weapon max-stack border (owner ruling 2026-08-02): a CC-drawn
-- border that lights while MW sits at its stack maximum. Legal in combat
-- because MW's aura is server-flagged never-secret — the same plain read
-- the bar itself runs on — and everything here is plain CC frames.
-- Renders through the same pure builders as the resource aura border:
-- per segment on the segmented shapes, whole-bar on continuous.
------------------------------------------------------------------------

-- The border's config, or nil when disabled. Plain resource-level keys on
-- settings.resources[100] (no spec overrides: MW is one spec's resource).
-- Returns the resource table too, for the slider keys.
local function GetMWMaxStackBorderConfig(settings)
    local resource = settings and settings.resources
        and settings.resources[RESOURCE_MAELSTROM_WEAPON]
    if type(resource) ~= "table" or resource.mwMaxStackBorderEnabled ~= true then
        return nil
    end
    local style = resource.mwMaxStackBorderStyle == "pixel" and "pixel" or "solid"
    local color = resource.mwMaxStackBorderColor
    if type(color) ~= "table" or color[1] == nil or color[2] == nil or color[3] == nil then
        color = RB.DEFAULT_MW_MAX_STACK_BORDER_COLOR
    end
    return style, color, resource
end

-- Runs on every MW update tick, so restyling is keyed: only a real change
-- (lit flips, style or colour edited, bar shape swapped) touches regions.
-- The pool hangs off the bar frame and is reset by
-- ClearStaleRecycledBarRuntimeState when the frame is recycled.
local function UpdateMWMaxStackBorder(holder, settings, barType, isMax)
    local style, color, resource
    if isMax then
        style, color, resource = GetMWMaxStackBorderConfig(settings)
    end
    local pool = holder._ccMWMaxBorder
    if not style then
        if pool and pool.key ~= "off" then
            pool.key = "off"
            if pool.glow then
                ST._StyleKitBarGlowRegions(pool.glow, nil, pool.host, false)
            end
            if pool.segBorders then
                ST._StyleKitSegmentBorders(pool.segBorders, nil, nil, 0, false)
            end
        end
        return
    end

    if not pool then
        local host = CreateFrame("Frame", nil, holder)
        host:EnableMouse(false)
        host:SetAllPoints(holder)
        -- Over every layer the bar stacks (MW overlay segments at +4, the
        -- text layer at +8) — the same clearance the aura overlay uses.
        host:SetFrameLevel(holder:GetFrameLevel() + RB.RESOURCE_OVERLAY_HOLDER_LEVEL)
        pool = { host = host }
        holder._ccMWMaxBorder = pool
    end

    local size = tonumber(resource.mwMaxStackBorderSize)
    local thickness = tonumber(resource.mwMaxStackBorderThickness)
    local speed = tonumber(resource.mwMaxStackBorderSpeed)
    local lines = tonumber(resource.mwMaxStackBorderLines)

    local isContinuous = barType == "mw_continuous" or not holder.segments
    local key = (isContinuous and "bar:" or "seg:") .. style .. ":"
        .. tostring(color[1]) .. ":" .. tostring(color[2]) .. ":"
        .. tostring(color[3]) .. ":" .. tostring(color[4]) .. ":"
        .. tostring(size) .. ":" .. tostring(thickness) .. ":"
        .. tostring(speed) .. ":" .. tostring(lines)
    if pool.key == key then return end
    pool.key = key

    local borderStyle = {
        barAuraIndicatorEnabled = true,
        barAuraEffect = style,
        barAuraEffectColor = color,
        barAuraEffectSize = size,
        barAuraEffectThickness = thickness,
        barAuraEffectSpeed = speed,
        barAuraEffectLines = lines,
    }
    if isContinuous then
        if not pool.glow then
            pool.glow = ST._BuildKitGlowRegions(pool.host)
        end
        -- Explicit rect dims for the dash geometry: the bar carries an
        -- explicit size, the SetAllPoints host may not have resolved yet.
        local fw, fh = holder:GetSize()
        pool.host._ccKitRectW = (fw and fw > 1) and fw or 1
        pool.host._ccKitRectH = (fh and fh > 1) and fh or 1
        ST._StyleKitBarGlowRegions(pool.glow, borderStyle, pool.host, true)
        if pool.segBorders then
            ST._StyleKitSegmentBorders(pool.segBorders, nil, nil, 0, false)
        end
    else
        if not pool.segBorders then
            pool.segBorders = ST._BuildKitSegmentBorderPool(pool.host, ST.RESOURCE_SEGMENT_BORDER_MAX)
        end
        local segments = holder.segments
        local n = math_min(#segments, ST.RESOURCE_SEGMENT_BORDER_MAX)
        for i = 1, n do
            segments[i]._ccW, segments[i]._ccH = segments[i]:GetSize()
        end
        ST._StyleKitSegmentBorders(pool.segBorders, borderStyle, segments, n, true)
        if pool.glow then
            ST._StyleKitBarGlowRegions(pool.glow, nil, pool.host, false)
        end
    end
end
-- For the config canvas (ResourceBarPreview), which renders MW at max.
RB.UpdateMWMaxStackBorder = UpdateMWMaxStackBorder

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
        UpdateMWMaxStackBorder(holder, settings, barType, false)
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
    local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(RESOURCE_MAELSTROM_WEAPON, settings, stacks)
    local isMax = stacks > 0 and stacks == mwMaxStacks
    -- Colour precedence is identical in all three shapes: at max wins, then
    -- a configured threshold, then the resource's own colour.
    local activeColor = isMax and maxColor or (thresholdActive and thresholdColor or baseColor)
    UpdateMWMaxStackBorder(holder, settings, barType, isMax)

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
        -- One segment per stack: each fills whole, like every other
        -- discrete resource.
        for i = 1, #holder.segments do
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
-- Custom aura and spell custom bar runtime (provided by ResourceBarCustomBars.lua)
------------------------------------------------------------------------

local RelayoutBars
local customBarsModule = RB.CreateResourceBarCustomBarsModule({
    resourceBarFrames = resourceBarFrames,
    GetUnlockAssistActive = function()
        return isUnlockAssistActive
    end,
    ClearStaleRecycledBarRuntimeState = ClearStaleRecycledBarRuntimeState,
    ClearCustomAuraBarIndicatorState = ClearCustomAuraBarIndicatorState,
    ClearCustomAuraBarIndicatorVisualState = ClearCustomAuraBarIndicatorVisualState,
    UpdateCustomAuraBarIndicatorVisuals = UpdateCustomAuraBarIndicatorVisuals,
})
local UpdateCustomAuraBar = customBarsModule.UpdateCustomAuraBar
local FinalizeAppliedBarVisibility = customBarsModule.FinalizeAppliedBarVisibility
local HideUnusedResourceBarFrames = customBarsModule.HideUnusedResourceBarFrames
local PrepareCustomAuraBar = customBarsModule.PrepareCustomAuraBar

-- Custom-bar aura hosting (the aura pass): stable holders + adapters for
-- the AuraContainer display in Core/AuraDisplay.lua. Reached via
-- CooldownCompanion methods, not locals: ApplyResourceBars sits at the
-- 60-upvalue ceiling.
RB.CreateResourceBarAuraHostModule({
    resourceBarFrames = resourceBarFrames,
})

------------------------------------------------------------------------
-- Relayout: reposition bars within their containers by visibility/order
-- Called from ApplyResourceBars().
------------------------------------------------------------------------

local function CompareBarOrder(a, b)
    if a._order ~= b._order then return a._order < b._order end
    local aKey = a.powerType or a.customBarId or ""
    local bKey = b.powerType or b.customBarId or ""
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

        containerFrameAbove:SetHeight(primaryLength)
        containerFrameBelow:SetHeight(primaryLength)

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
    else
        local aboveBars = {}
        local belowBars = {}
        for _, barInfo in ipairs(resourceBarFrames) do
            if barInfo and barInfo.frame and barInfo.frame:IsShown() then
                if barInfo._side == "above" then
                    table.insert(aboveBars, barInfo)
                else
                    table.insert(belowBars, barInfo)
                end
            end
        end
        table.sort(aboveBars, CompareBarOrder)
        table.sort(belowBars, CompareBarOrder)

        containerFrameAbove:SetWidth(primaryLength)
        containerFrameBelow:SetWidth(primaryLength)

        -- Stack above bars (order ascending = bottom to top; order=1 closest to group)
        local currentY = 0
        for _, barInfo in ipairs(aboveBars) do
            barInfo.frame:ClearAllPoints()
            barInfo.frame:SetPoint("BOTTOMLEFT", containerFrameAbove, "BOTTOMLEFT", 0, currentY)
            barInfo.frame:SetPoint("BOTTOMRIGHT", containerFrameAbove, "BOTTOMRIGHT", 0, currentY)
            local h = barInfo._effectiveThickness or globalThickness
            barInfo.frame:SetHeight(h)
            currentY = currentY + h + barSpacing
        end
        local aboveHeight = currentY > 0 and (currentY - barSpacing) or 1
        containerFrameAbove:SetHeight(aboveHeight)
        if #aboveBars > 0 then containerFrameAbove:Show() else containerFrameAbove:Hide() end

        -- Stack below bars (order ascending = top to bottom; order=1 closest to group)
        currentY = 0
        for _, barInfo in ipairs(belowBars) do
            barInfo.frame:ClearAllPoints()
            barInfo.frame:SetPoint("TOPLEFT", containerFrameBelow, "TOPLEFT", 0, -currentY)
            barInfo.frame:SetPoint("TOPRIGHT", containerFrameBelow, "TOPRIGHT", 0, -currentY)
            local h = barInfo._effectiveThickness or globalThickness
            barInfo.frame:SetHeight(h)
            currentY = currentY + h + barSpacing
        end
        local belowHeight = currentY > 0 and (currentY - barSpacing) or 1
        containerFrameBelow:SetHeight(belowHeight)
        if #belowBars > 0 then containerFrameBelow:Show() else containerFrameBelow:Hide() end
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

    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame and barInfo.frame:IsShown() then
            if barInfo.barType == "continuous" then
                UpdateContinuousBar(barInfo.frame, barInfo.powerType, settings)
            elseif barInfo.barType == "health_continuous" then
                HealthBar.Update(barInfo.frame, settings)
            elseif barInfo.barType == "segmented" then
                UpdateSegmentedBar(barInfo.frame, barInfo.powerType, settings)
            elseif barInfo.barType == "mw_segmented"
                or barInfo.barType == "mw_segments"
                or barInfo.barType == "mw_continuous" then
                UpdateMaelstromWeaponBar(barInfo.frame, settings, barInfo.barType)
            elseif barInfo.barType == "stagger_continuous" then
                UpdateStaggerBar(barInfo.frame, settings)
            elseif barInfo.barType == "custom_cooldown" then
                RB.UpdateCustomCooldownBar(barInfo)
                if barInfo.frame:IsShown() then
                    AnimateCustomAuraBarIndicator(barInfo.frame)
                end
            elseif barInfo.barType == "custom_continuous" then
                UpdateCustomAuraBar(barInfo)
                if barInfo.frame:IsShown() then
                    AnimateCustomAuraBarIndicator(barInfo.frame)
                end
            end
        end
    end

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

local function StyleContinuousBar(bar, powerType, settings)
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

    ApplyContinuousFillColor(bar, powerType, settings)

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

    -- Text setup
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

    bar.text:ClearAllPoints()
    bar.text:SetPoint(
        resourceConfig and resourceConfig.textAnchor or "CENTER",
        resourceConfig and resourceConfig.textXOffset or 0,
        resourceConfig and resourceConfig.textYOffset or 0
    )

    -- Continuous bars show text by default
    local showText = true
    if resourceConfig and resourceConfig.showText == false then
        showText = false
    end
    bar.text:SetShown(showText)
    bar._textFormat = textFormat

    -- Tick markers need a real power type to measure against. Both of CC's
    -- invented ids are excluded: Stagger (101) is sized by UnitHealthMax,
    -- and Maelstrom Weapon (100) is sized by its aura's stack cap — passing
    -- either to UnitPowerMax is a hard error. Neither is offered tick
    -- markers anyway (GetContinuousTickEntriesConfig groups Maelstrom with
    -- the segmented resources, whose threshold colours serve the same role).
    if powerType ~= 101 and powerType ~= RESOURCE_MAELSTROM_WEAPON then
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

    holder.text:ClearAllPoints()
    holder.text:SetPoint(
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

    local thresholdActive, thresholdColor = GetSegmentedThresholdColorForValue(powerType, settings, filled)

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

function CooldownCompanion:ApplyResourceBars(opts)
    opts = opts or {}
    if not opts.skipRuntimeGate
        and self.RefreshBarsAndFramesRuntimeFeatureGate
        and not self:RefreshBarsAndFramesRuntimeFeatureGate("resourceBars", "resource-apply") then
        self:RevertResourceBars()
        return
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

    local isIndependentStack = layout.independentAnchorEnabled == true
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
    local resources = DetermineActiveResources()
    local filtered = {}
    for _, pt in ipairs(resources) do
        if IsResourceEnabled(pt, settings) then
            table.insert(filtered, pt)
        end
    end

    -- Append enabled Custom Bars
    local customBars = GetSpecCustomAuraBars(settings)
    for i, cab in ipairs(customBars) do
        if cab and CooldownCompanion:IsCustomBarRuntimeEligible(cab) then
            table.insert(filtered, {
                kind = "custom",
                customBarIndex = i,
                customBarId = RB.EnsureCustomBarId(settings, cab),
                config = cab,
            })
        end
    end

    if #filtered == 0 then
        self:RevertResourceBars()
        return
    end

    -- Create containers if needed
    if not containerFrameAbove then
        containerFrameAbove = CreateFrame("Frame", "CooldownCompanionResourceBarsAbove", UIParent)
        containerFrameAbove:SetFrameStrata("MEDIUM")
    end
    if not containerFrameBelow then
        containerFrameBelow = CreateFrame("Frame", "CooldownCompanionResourceBarsBelow", UIParent)
        containerFrameBelow:SetFrameStrata("MEDIUM")
    end

    -- Create or recycle bar frames
    local globalBarThickness = GetResourceGlobalThickness(settings)
    local barSpacing = layout.barSpacing or settings.barSpacing or 3.6
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
        totalPrimaryLength = GetResourcePrimaryLength(groupFrame, settings)
    end

    -- Determine side/order for each bar (per-spec layout)
    local sideList = {}
    local orderList = {}
    local fallbackOrder = 900
    for idx, entry in ipairs(filtered) do
        local isCustomEntry = type(entry) == "table" and entry.kind == "custom"
        local powerType = isCustomEntry and nil or entry
        local side, order
        if isCustomEntry then
            local cabConfig = entry.config
            local slotCfg = RB.GetCustomBarLayout(settings, nil, cabConfig, false)
            if isVerticalLayout then
                local storedHorizontalSide = (slotCfg and slotCfg.position) or "below"
                side = (slotCfg and slotCfg.verticalPosition) or GetVerticalSideFallback(storedHorizontalSide)
                order = (slotCfg and slotCfg.verticalOrder) or (slotCfg and slotCfg.order) or (fallbackOrder + idx)
            else
                side = (slotCfg and slotCfg.position) or "below"
                order = (slotCfg and slotCfg.order) or (fallbackOrder + idx)
            end
        else
            local res = layout and layout.resources and layout.resources[powerType]
            if isVerticalLayout then
                local storedHorizontalSide = (res and res.position) or "below"
                side = (res and res.verticalPosition) or GetVerticalSideFallback(storedHorizontalSide)
                order = (res and res.verticalOrder) or (res and res.order) or (fallbackOrder + idx)
            else
                side = (res and res.position) or "below"
                order = (res and res.order) or (fallbackOrder + idx)
            end
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
        sideList[idx] = side
        orderList[idx] = order
    end

    -- Hide existing bars that we don't need
    HideUnusedResourceBarFrames(#filtered + 1)

    for idx, entry in ipairs(filtered) do
        local isCustomEntry = type(entry) == "table" and entry.kind == "custom"
        local powerType = isCustomEntry and nil or entry
        local isSegmented = SEGMENTED_TYPES[powerType]
        local barInfo = resourceBarFrames[idx]
        local firstSide = isVerticalLayout and "left" or "above"
        local targetContainer = sideList[idx] == firstSide and containerFrameAbove or containerFrameBelow

        -- Resolve per-bar thickness override
        local effectiveThickness = globalBarThickness
        if layout.customBarHeights then
            local thicknessKey = isVerticalLayout and "barWidth" or "barHeight"
            if isCustomEntry then
                local slotLayout = RB.GetCustomBarLayout(settings, nil, entry.config, false)
                if thicknessKey == "barWidth" then
                    effectiveThickness = (slotLayout and (slotLayout.barWidth or slotLayout.barHeight)) or globalBarThickness
                else
                    effectiveThickness = (slotLayout and (slotLayout.barHeight or slotLayout.barWidth)) or globalBarThickness
                end
            else
                local res = layout.resources and layout.resources[powerType]
                if thicknessKey == "barWidth" then
                    effectiveThickness = (res and (res.barWidth or res.barHeight)) or globalBarThickness
                else
                    effectiveThickness = (res and (res.barHeight or res.barWidth)) or globalBarThickness
                end
            end
        end
        local effectiveWidth = isVerticalLayout and effectiveThickness or totalPrimaryLength
        local effectiveHeight = isVerticalLayout and totalPrimaryLength or effectiveThickness

        if powerType == RESOURCE_HEALTH then
            if not barInfo or barInfo.barType ~= "health_continuous" then
                if barInfo and barInfo.frame then
                    ClearStaleRecycledBarRuntimeState(barInfo.frame)
                    barInfo.frame:Hide()
                end
                local bar = CreateContinuousBar(targetContainer)
                barInfo = { frame = bar, barType = "health_continuous", powerType = powerType }
                resourceBarFrames[idx] = barInfo
            else
                barInfo.powerType = powerType
            end

            barInfo.frame:SetSize(effectiveWidth, effectiveHeight)
            HealthBar.Style(barInfo.frame, settings)

        elseif powerType == 101 then  -- Stagger
            -- Stagger: continuous bar with dedicated update (health-based max, threshold colors)
            if not barInfo or barInfo.barType ~= "stagger_continuous" then
                if barInfo and barInfo.frame then
                    ClearStaleRecycledBarRuntimeState(barInfo.frame)
                    barInfo.frame:Hide()
                end
                local bar = CreateContinuousBar(targetContainer)
                barInfo = { frame = bar, barType = "stagger_continuous", powerType = powerType }
                resourceBarFrames[idx] = barInfo
            else
                barInfo.powerType = powerType
            end

            barInfo.frame:SetSize(effectiveWidth, effectiveHeight)
            StyleContinuousBar(barInfo.frame, powerType, settings)

        elseif powerType == RESOURCE_MAELSTROM_WEAPON then
            -- Maelstrom Weapon renders in one of three shapes (see
            -- GetMWDisplayStyle). The stack source is the same in all of
            -- them; only the widget differs, so each style materializes the
            -- matching bar frame here and UpdateMaelstromWeaponBar renders
            -- to it. The style is read once per apply, never per tick, and
            -- reached through RB rather than a new file-level local:
            -- ApplyResourceBars sits at Lua 5.1's 60-upvalue ceiling.
            local mwStyle = RB.GetMWDisplayStyle(settings)

            if mwStyle == "continuous" then
                if not barInfo or barInfo.barType ~= "mw_continuous" then
                    if barInfo and barInfo.frame then
                        ClearStaleRecycledBarRuntimeState(barInfo.frame)
                        barInfo.frame:Hide()
                    end
                    local bar = CreateContinuousBar(targetContainer)
                    barInfo = { frame = bar, barType = "mw_continuous", powerType = powerType }
                    resourceBarFrames[idx] = barInfo
                else
                    barInfo.powerType = powerType
                end

                barInfo.frame:SetSize(effectiveWidth, effectiveHeight)
                -- Shares the continuous styling path, so texture, borders,
                -- background, and the bar text all follow the same resource
                -- settings every other continuous bar uses.
                StyleContinuousBar(barInfo.frame, powerType, settings)

            elseif mwStyle == "segments" then
                -- One segment per stack, no overlay layer: the plain
                -- segmented widget every other discrete resource uses.
                if not barInfo or barInfo.barType ~= "mw_segments"
                    or #barInfo.frame.segments ~= mwMaxStacks then
                    if barInfo and barInfo.frame then
                        ClearStaleRecycledBarRuntimeState(barInfo.frame)
                        barInfo.frame:Hide()
                    end
                    local holder = CreateSegmentedBar(targetContainer, mwMaxStacks)
                    barInfo = { frame = holder, barType = "mw_segments", powerType = powerType }
                    resourceBarFrames[idx] = barInfo
                else
                    barInfo.powerType = powerType
                end

                barInfo.frame:SetSize(effectiveWidth, effectiveHeight)
                LayoutSegments(barInfo.frame, effectiveWidth, effectiveHeight, segmentGap, settings)

                local baseColor = GetResourceColors(100, settings)
                for i = 1, mwMaxStacks do
                    barInfo.frame.segments[i]:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
                end
                StyleSegmentedText(barInfo.frame, powerType, settings)

            else
                -- Overlay: five segments carrying a second colour layer for
                -- stacks past five (the default shape).
                local halfSegments = mwMaxStacks <= 5 and mwMaxStacks or (mwMaxStacks / 2)

                if not barInfo or barInfo.barType ~= "mw_segmented"
                    or #barInfo.frame.segments ~= halfSegments then
                    if barInfo and barInfo.frame then
                        ClearStaleRecycledBarRuntimeState(barInfo.frame)
                        barInfo.frame:Hide()
                    end
                    local holder = CreateOverlayBar(targetContainer, halfSegments)
                    barInfo = { frame = holder, barType = "mw_segmented", powerType = powerType }
                    resourceBarFrames[idx] = barInfo
                else
                    barInfo.powerType = powerType
                end

                barInfo.frame:SetSize(effectiveWidth, effectiveHeight)
                LayoutOverlaySegments(barInfo.frame, effectiveWidth, effectiveHeight, segmentGap, settings, halfSegments)

                -- Apply initial colors
                local baseColor, overlayColor = GetResourceColors(100, settings)
                for i = 1, halfSegments do
                    barInfo.frame.segments[i]:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
                    barInfo.frame.overlaySegments[i]:SetStatusBarColor(overlayColor[1], overlayColor[2], overlayColor[3], 1)
                    barInfo.frame.overlaySegments[i]:Show()
                end
                StyleSegmentedText(barInfo.frame, powerType, settings)
            end

        elseif isCustomEntry then
            barInfo = PrepareCustomAuraBar(
                targetContainer,
                barInfo,
                entry,
                customBars,
                settings,
                isVerticalLayout,
                reverseVerticalFill,
                effectiveWidth,
                effectiveHeight,
                segmentGap
            )
            resourceBarFrames[idx] = barInfo
        elseif isSegmented then
            local max = UnitPowerMax("player", powerType)
            if powerType == 5 then max = 6 end  -- Runes always 6
            if max < 1 then max = 1 end

            -- Need to recreate if segment count changed or type changed
            if not barInfo or barInfo.barType ~= "segmented"
                or barInfo.frame._numSegments ~= max then
                if barInfo and barInfo.frame then
                    ClearStaleRecycledBarRuntimeState(barInfo.frame)
                    barInfo.frame:Hide()
                end
                local holder = CreateSegmentedBar(targetContainer, max)
                barInfo = { frame = holder, barType = "segmented", powerType = powerType }
                resourceBarFrames[idx] = barInfo
            else
                barInfo.powerType = powerType
            end

            barInfo.frame:SetSize(effectiveWidth, effectiveHeight)
            LayoutSegments(barInfo.frame, effectiveWidth, effectiveHeight, segmentGap, settings)
            StyleSegmentedBar(barInfo.frame, powerType, settings)
            UpdateSegmentedBar(barInfo.frame, powerType, settings, {})
        else
            -- Continuous bar
            if not barInfo or barInfo.barType ~= "continuous" then
                if barInfo and barInfo.frame then
                    ClearStaleRecycledBarRuntimeState(barInfo.frame)
                    barInfo.frame:Hide()
                end
                local bar = CreateContinuousBar(targetContainer)
                barInfo = { frame = bar, barType = "continuous", powerType = powerType }
                resourceBarFrames[idx] = barInfo
            else
                barInfo.powerType = powerType
            end

            barInfo.frame:SetSize(effectiveWidth, effectiveHeight)
            StyleContinuousBar(barInfo.frame, powerType, settings)
        end

        ClearStaleRecycledBarRuntimeState(barInfo.frame)
        if barInfo.frame:GetParent() ~= targetContainer then
            barInfo.frame:SetParent(targetContainer)
        end
        -- Slot reuse hygiene (aura pass): a slot moving from a custom bar
        -- to a resource bar kept the old cabConfig/customBarId, and the
        -- aura-host collector then bound an aura display onto the resource
        -- bar (the phantom custom_bar_12 bind).
        if not isCustomEntry then
            barInfo.cabConfig = nil
            barInfo.customBarId = nil
            barInfo.customBarIndex = nil
        end
        barInfo._side = sideList[idx]
        barInfo._order = orderList[idx]
        barInfo._effectiveThickness = effectiveThickness

        FinalizeAppliedBarVisibility(barInfo)
    end

    activeResources = filtered

    -- Layout: per-element positioning using side containers
    local gap = GetResourceAnchorGap(settings, layout)
    lastAppliedPrimaryLength = totalPrimaryLength

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
            containerFrameAbove:SetHeight(totalPrimaryLength)
            containerFrameBelow:SetHeight(totalPrimaryLength)
            containerFrameAbove:SetPoint("TOPRIGHT", groupFrame, "TOPLEFT", -gap, 0)
            containerFrameBelow:SetPoint("TOPLEFT", groupFrame, "TOPRIGHT", gap, 0)
        else
            containerFrameAbove:SetWidth(totalPrimaryLength)
            containerFrameBelow:SetWidth(totalPrimaryLength)
            containerFrameAbove:SetPoint("BOTTOMLEFT", groupFrame, "TOPLEFT", 0, gap)
            containerFrameBelow:SetPoint("TOPLEFT", groupFrame, "BOTTOMLEFT", 0, -gap)
        end
    end

    -- Position bars within containers (reusable for relayout on visibility change)
    RelayoutBars()

    -- Anchor drag chrome to frame the content (after containers are sized)
    if isIndependentStack then
        UpdateIndependentStackChrome(isVerticalLayout, layout)
    end

    -- Enable OnUpdate
    if not onUpdateFrame then
        onUpdateFrame = CreateFrame("Frame")
    end
    onUpdateFrame:SetScript("OnUpdate", OnUpdate)

    -- Enable events
    EnableEventFrame()

    isApplied = true

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
        frames[#frames + 1] = self:GetCustomBarAuraHostRoot()
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
        -- Aura host root rides the same alpha writes: the kit visuals fade
        -- with the bars they decorate (plain CC frame; alpha propagates
        -- down through the holders into the slot subtrees engine-side).
        -- Captured as a local: the sync closure below shadows `self`.
        local auraHostRoot = self:GetCustomBarAuraHostRoot()
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
        frames[#frames + 1] = self:GetCustomBarAuraHostRoot()
        if #frames > 0 then
            CooldownCompanion:RegisterModuleAlpha(rbModuleId, settings, frames)
        end
    end

    -- Custom-bar aura displays (the aura pass): holders re-anchor to the
    -- frames this apply may have recreated, and slot filters re-bind, in
    -- the coalesced OOC rebind pass.
    self:SetCustomBarAuraHostApplied(true)
    self:RequestAuraRebind("custom-bars")
end

------------------------------------------------------------------------
-- Revert: hide all resource bars
------------------------------------------------------------------------

function CooldownCompanion:RevertResourceBars()
    if not isApplied then return end
    isApplied = false
    lastAppliedPrimaryLength = nil
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
    self:SetCustomBarAuraHostApplied(false)
    self:GetCustomBarAuraHostRoot():SetAlpha(1)
    self:RequestAuraRebind("custom-bars")

    -- Stop OnUpdate
    if onUpdateFrame then
        onUpdateFrame:SetScript("OnUpdate", nil)
    end

    -- Stop events
    DisableEventFrame()

    -- Hide all bars
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame then
            ClearStaleRecycledBarRuntimeState(barInfo.frame)
            ClearCustomAuraBarIndicatorState(barInfo, true)
            barInfo.frame:Hide()
            if barInfo.frame.brightnessOverlay then
                barInfo.frame.brightnessOverlay:Hide()
            end
        end
    end

    -- Hide containers and independent wrapper
    if containerFrameAbove then containerFrameAbove:Hide() end
    if containerFrameBelow then containerFrameBelow:Hide() end
    HideIndependentWrapperFrame()

    isUnlockAssistActive = false
    -- Config-canvas preview state is deliberately NOT cleared here. This
    -- teardown runs for transient live conditions — no anchor group yet, an
    -- anchor that is not icon-like, an anchor frame that is momentarily
    -- hidden — and the canvas keeps rendering from saved data through all of
    -- them. Wiping the maps made a running command-center preview die
    -- because of live-frame availability it has nothing to do with.
    -- Ownership sits with ClearAllConfigPreviews and the explicit stops.
    activeResources = {}
end

function CooldownCompanion:DisableResourceBarRuntime()
    self._resourceBarsNeedsMWMaxRefresh = true
    DisableLifecycleEvents()
    self:RevertResourceBars()
    -- The feature itself is off, so the bars those previews stand for no
    -- longer exist anywhere — this is the disable path, not the transient
    -- teardown above, and clearing here is the point.
    self:ClearAllHealthEffectPreviews()
    self:ClearAllCustomAuraBarPreviews()
    self:ClearAllResourceAuraPreviews()
end

function CooldownCompanion:GetSpecCustomAuraBars()
    local settings = GetResourceBarSettings()
    if not settings then return {} end
    return GetSpecCustomAuraBars(settings)
end

function CooldownCompanion:GetSpecLayoutOrder()
    local settings = GetResourceBarSettings()
    if not settings then return nil end
    return GetSpecLayoutOrder(settings)
end

-- Custom-bar aura preview (the aura pass): which bars have their Active Aura
-- stand-in armed, keyed by the stored config table (the same identity
-- barInfo.cabConfig carries, and the one the config canvas reads back).
--
-- State only. The stand-in renders on the config canvas and the live bar is
-- never touched (owner ruling 2026-07-26); the canvas repaints itself when
-- the command center flips this.
function CooldownCompanion:SetCustomAuraBarActivePreview(cabConfig, active)
    if type(cabConfig) ~= "table" then return end
    activeCustomAuraBarActivePreviews[cabConfig] = active and true or nil
end

function CooldownCompanion:IsCustomAuraBarActivePreviewActive(cabConfig)
    return activeCustomAuraBarActivePreviews[cabConfig] == true
end

-- Pandemic stand-in (PTR 8 Phase 2): rides on top of the Active Aura
-- stand-in — the recolor exists only while the aura fill renders, so the
-- command center arms both flags together. Same table-keyed state model.
function CooldownCompanion:SetCustomAuraBarPandemicPreview(cabConfig, active)
    if type(cabConfig) ~= "table" then return end
    activeCustomAuraBarPandemicPreviews[cabConfig] = active and true or nil
end

function CooldownCompanion:IsCustomAuraBarPandemicPreviewActive(cabConfig)
    return activeCustomAuraBarPandemicPreviews[cabConfig] == true
end

function CooldownCompanion:ClearAllCustomAuraBarPreviews()
    wipe(activeCustomAuraBarActivePreviews)
    wipe(activeCustomAuraBarPandemicPreviews)
end

-- Resource aura overlay preview (the aura pass, Phase 2): which resources
-- have their Active Aura stand-in armed. State only, same as the custom-bar
-- previews above — the stand-in renders on the config canvas and the live
-- bar is never touched (owner ruling 2026-07-26).
function CooldownCompanion:SetResourceAuraActivePreview(powerType, active)
    powerType = tonumber(powerType)
    if not powerType then return end
    activeResourceAuraPreviews[powerType] = active and true or nil
end

function CooldownCompanion:IsResourceAuraActivePreviewActive(powerType)
    powerType = tonumber(powerType)
    return powerType ~= nil and activeResourceAuraPreviews[powerType] == true
end

function CooldownCompanion:ClearAllResourceAuraPreviews()
    wipe(activeResourceAuraPreviews)
end

function HealthBar.HasActiveEffectPreview()
    local preview = HEALTH_EFFECTS.preview
    return preview.absorbs == true
        or preview.healAbsorbs == true
        or preview.incomingHeals == true
        or preview.lowHealthAlert == true
end

-- Health-effect previews are state only, like the custom-bar aura previews:
-- absorbs, incoming heals and the low-health alert render on the config
-- canvas's health facsimile, never on the real bar.
function CooldownCompanion:SetHealthEffectPreview(effectKey, show)
    if effectKey ~= "absorbs"
        and effectKey ~= "healAbsorbs"
        and effectKey ~= "incomingHeals"
        and effectKey ~= "lowHealthAlert" then
        return
    end

    HEALTH_EFFECTS.preview[effectKey] = show and true or nil
end

function CooldownCompanion:IsHealthEffectPreviewActive(effectKey)
    return HEALTH_EFFECTS.preview[effectKey] == true
end

function CooldownCompanion:ClearAllHealthEffectPreviews()
    wipe(HEALTH_EFFECTS.preview)
end

function CooldownCompanion:GetResourceBarRuntimeDebugInfo()
    local info = {}
    for idx, barInfo in ipairs(resourceBarFrames) do
        local entry = {
            index = idx,
            powerType = barInfo.powerType,
            customBarId = barInfo.customBarId,
            barType = barInfo.barType,
            shown = barInfo.frame and barInfo.frame:IsShown() or false,
        }
        if barInfo.cabConfig and barInfo.cabConfig.spellID then
            entry.spellID = tonumber(barInfo.cabConfig.spellID) or barInfo.cabConfig.spellID
            entry.hideWhenInactive = barInfo.cabConfig.hideWhenInactive == true
        end
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
        activeBarCount = #activeResources,
    }
end

------------------------------------------------------------------------
-- Evaluate: central decision point
------------------------------------------------------------------------

function CooldownCompanion:EvaluateResourceBars(opts)
    opts = opts or {}
    if not opts.skipRuntimeGate
        and self.RefreshBarsAndFramesRuntimeFeatureGate
        and not self:RefreshBarsAndFramesRuntimeFeatureGate("resourceBars", opts.reason or "resource-evaluate") then
        self:DisableResourceBarRuntime()
        return
    end
    if self.RecordBarsAndFramesRuntimeWork then
        self:RecordBarsAndFramesRuntimeWork("resourceEvaluate")
    end

    if self._unsupportedLegacyProfile then
        self:DisableResourceBarRuntime()
        return
    end

    local settings = GetResourceBarSettings()
    if not settings or not settings.enabled then
        self:DisableResourceBarRuntime()
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
            elseif barInfo._order > best._order then
                best = barInfo
            elseif barInfo._order == best._order
                and tostring(barInfo.powerType or barInfo.customBarId or "") > tostring(best.powerType or best.customBarId or "") then
                best = barInfo
            end
        end
    end

    return best and best.frame or nil
end

------------------------------------------------------------------------
-- Preview mode
------------------------------------------------------------------------

RB.CreateResourceBarPreviewModule({
    HealthBar = HealthBar,
    HEALTH_EFFECTS = HEALTH_EFFECTS,
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
    ClearCustomAuraBarIndicatorState = ClearCustomAuraBarIndicatorState,
    ClearCustomAuraBarIndicatorVisualState = ClearCustomAuraBarIndicatorVisualState,
    UpdateCustomAuraBarIndicatorVisuals = UpdateCustomAuraBarIndicatorVisuals,
    AnimateCustomAuraBarIndicator = AnimateCustomAuraBarIndicator,
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
