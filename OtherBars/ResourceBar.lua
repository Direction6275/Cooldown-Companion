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
local CS = ST._configState

local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_abs = math.abs
local math_sin = math.sin
local math_pi = math.pi
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue
local string_format = string.format

------------------------------------------------------------------------
-- Imports from ResourceBarConstants / ResourceBarHelpers / ResourceBarVisuals
------------------------------------------------------------------------

local RB = ST._RB
local UPDATE_INTERVAL = RB.UPDATE_INTERVAL
local PERCENT_SCALE_CURVE = RB.PERCENT_SCALE_CURVE
local CUSTOM_AURA_BAR_BASE = RB.CUSTOM_AURA_BAR_BASE
local MW_SPELL_ID = RB.MW_SPELL_ID
local RAGING_MAELSTROM_SPELL_ID = RB.RAGING_MAELSTROM_SPELL_ID
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
local RESOURCE_MAELSTROM_WEAPON = RB.RESOURCE_MAELSTROM_WEAPON
local DEFAULT_RESOURCE_TEXT_FORMAT = RB.DEFAULT_RESOURCE_TEXT_FORMAT
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE
local DEFAULT_RESOURCE_TEXT_COLOR = RB.DEFAULT_RESOURCE_TEXT_COLOR
local INDEPENDENT_NUDGE_BTN_SIZE = RB.INDEPENDENT_NUDGE_BTN_SIZE
local INDEPENDENT_NUDGE_REPEAT_DELAY = RB.INDEPENDENT_NUDGE_REPEAT_DELAY
local INDEPENDENT_NUDGE_REPEAT_INTERVAL = RB.INDEPENDENT_NUDGE_REPEAT_INTERVAL
local IsBarsConfigActive = RB.IsBarsConfigActive
local CancelNudgeTimers = RB.CancelNudgeTimers
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local POWER_ATLAS_INFO = RB.POWER_ATLAS_INFO
local RESOURCE_COLOR_DEFS = RB.RESOURCE_COLOR_DEFS
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = RB.DEFAULT_RESOURCE_AURA_ACTIVE_COLOR

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
local GetResolvedCustomAuraBarAuraUnit = RB.GetResolvedCustomAuraBarAuraUnit
local EnsureCustomAuraBarAuraUnit = RB.EnsureCustomAuraBarAuraUnit
local GetSpecLayoutOrder = RB.GetSpecLayoutOrder
local GetResourceDisplayValue = RB.GetResourceDisplayValue
local GetResourceDisplayConfig = RB.GetResourceDisplayConfig
local GetAnchorOffset = RB.GetAnchorOffset
local RoundToTenths = RB.RoundToTenths
local ClampIndependentDimension = RB.ClampIndependentDimension
local NormalizeCustomAuraStackTextFormat = RB.NormalizeCustomAuraStackTextFormat
local DetermineActiveResources = RB.DetermineActiveResources
local GetResourceColors = RB.GetResourceColors
local IsUnitPowerSecret = RB.IsUnitPowerSecret
local IsUnitPowerMaxSecret = RB.IsUnitPowerMaxSecret
local GetSegmentedThresholdConfig = RB.GetSegmentedThresholdConfig
local SupportsResourceAuraStackMode = RB.SupportsResourceAuraStackMode
local IsResourceEnabled = RB.IsResourceEnabled
local IsSegmentedTextResource = RB.IsSegmentedTextResource
local ClearSegmentedText = RB.ClearSegmentedText
local SetSegmentedText = RB.SetSegmentedText

-- Visuals
local GetResourceAuraConfiguredMaxStacks = RB.GetResourceAuraConfiguredMaxStacks
local GetResourceAuraState = RB.GetResourceAuraState
local HideResourceAuraStackSegments = RB.HideResourceAuraStackSegments
local ApplyResourceAuraStackSegments = RB.ApplyResourceAuraStackSegments
local ClearResourceAuraVisuals = RB.ClearResourceAuraVisuals
local UpdateContinuousTickMarker = RB.UpdateContinuousTickMarker
local ApplyContinuousFillColor = RB.ApplyContinuousFillColor
local ApplyPixelBorders = RB.ApplyPixelBorders
local HidePixelBorders = RB.HidePixelBorders
local IsCustomAuraMaxThresholdEnabled = RB.IsCustomAuraMaxThresholdEnabled
local GetCustomAuraMaxThresholdColor = RB.GetCustomAuraMaxThresholdColor
local SetCustomAuraMaxThresholdRange = RB.SetCustomAuraMaxThresholdRange
local EnsureMaxStacksIndicator = RB.EnsureMaxStacksIndicator
local LayoutMaxStacksIndicator = RB.LayoutMaxStacksIndicator
local ClearMaxStacksIndicator = RB.ClearMaxStacksIndicator
local EnsureCustomAuraContinuousThresholdOverlay = RB.EnsureCustomAuraContinuousThresholdOverlay
local EnsureCustomAuraSegmentThresholdOverlays = RB.EnsureCustomAuraSegmentThresholdOverlays
local EnsureCustomAuraOverlayThresholdOverlays = RB.EnsureCustomAuraOverlayThresholdOverlays
local LayoutCustomAuraContinuousThresholdOverlay = RB.LayoutCustomAuraContinuousThresholdOverlay
local CreateContinuousBar = RB.CreateContinuousBar
local CreateSegmentedBar = RB.CreateSegmentedBar
local LayoutSegments = RB.LayoutSegments
local CreateOverlayBar = RB.CreateOverlayBar
local LayoutOverlaySegments = RB.LayoutOverlaySegments
local IsResourceAuraOverlayEnabled = RB.IsResourceAuraOverlayEnabled
local GetActiveResourceAuraEntry = RB.GetActiveResourceAuraEntry

-- Shared helper from ButtonFrame/Helpers.lua
local FormatTime = CooldownCompanion.FormatTime
local GetDurationSecretFormatSpec = CooldownCompanion.GetDurationSecretFormatSpec
-- Other ST imports
local CreateGlowContainer = ST._CreateGlowContainer
local ShowGlowStyle = ST._ShowGlowStyle
local HideGlowStyles = ST._HideGlowStyles
local SetBarAuraEffect = ST._SetBarAuraEffect
local DEFAULT_BAR_PANDEMIC_COLOR = ST._DEFAULT_BAR_PANDEMIC_COLOR

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local mwMaxStacks = 5

local isApplied = false
local hooksInstalled = false
local eventFrame = nil
local onUpdateFrame = nil
local containerFrameAbove = nil
local containerFrameBelow = nil
local lastAppliedPrimaryLength = nil
local lastAppliedOrientation = nil
local lastAppliedLayout = nil
local lastAppliedIndependentStack = false
local resourceBarFrames = {}   -- array of bar frame objects (ordered by stacking)
local activeResources = {}     -- array of power type ints currently displayed
local isPreviewActive = false
local ApplyPreviewData
local pendingSpecChange = false
local savedContainerAlpha = nil
local alphaSyncFrame = nil
local lastAppliedBarSpacing = nil
local lastAppliedBarThickness = nil
local layoutDirty = false
local customAuraWakeRetryFrame = nil
local customAuraWakeRetryQueue = {}
local customAuraWakeRetryPending = {}
local processingCustomAuraWakeRetryQueue = false
local independentWrapperFrame = nil
local customAuraBarActivePreviewTokens = {}
local customAuraBarPandemicPreviewTokens = {}
local activeCustomAuraBarActivePreviews = {}
local activeCustomAuraBarPandemicPreviews = {}
local segmentedUpdateScratch = { auraActiveCache = {} }
local CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL = 0.65
local CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS = 3
local CUSTOM_AURA_BAR_EFFECT_PREVIEW_DURATION = 12.3
local HEALTH_EFFECT_JOIN_OVERLAP = 1
local HealthBar = {}
local HEALTH_EFFECTS = {
    texture = RB.DEFAULT_HEALTH_EFFECT_TEXTURE or "Solid",
    incomingHealColor = RB.DEFAULT_HEALTH_INCOMING_HEAL_COLOR,
    absorbColor = RB.DEFAULT_HEALTH_ABSORB_COLOR,
    healAbsorbColor = RB.DEFAULT_HEALTH_HEAL_ABSORB_COLOR,
    lowHealthAlertColor = RB.DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR,
    lowHealthAlertThreshold = 0.35,
    lowHealthAlertThresholdFade = 0.001,
    lowHealthAlertPulseSpeed = 0.85,
    netHealingCalc = CreateUnitHealPredictionCalculator(),
    standaloneHealingCalc = CreateUnitHealPredictionCalculator(),
    absorbMissingCalc = CreateUnitHealPredictionCalculator(),
    absorbOverflowCalc = CreateUnitHealPredictionCalculator(),
    preview = {},
}
HEALTH_EFFECTS.netHealingCalc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
HEALTH_EFFECTS.netHealingCalc:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.CurrentHealth)
HEALTH_EFFECTS.netHealingCalc:SetHealAbsorbMode(Enum.UnitHealAbsorbMode.ReducedByIncomingHeals)
HEALTH_EFFECTS.standaloneHealingCalc:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.CurrentHealth)
HEALTH_EFFECTS.standaloneHealingCalc:SetHealAbsorbMode(Enum.UnitHealAbsorbMode.Total)
HEALTH_EFFECTS.absorbMissingCalc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
HEALTH_EFFECTS.absorbOverflowCalc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)

local function EnsureNonNilNumber(value)
    if type(value) == "nil" then
        return 0
    end
    return value
end

local function HasCustomAuraBarAuraVisuals(cabConfig)
    return cabConfig and (cabConfig.barAuraEffect or "none") ~= "none"
end

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

local function ClearCustomAuraBarIndicatorState(barInfo, clearPreviewFlags)
    if not IsCustomBarAuraIndicatorFrame(barInfo) then
        return
    end

    local bar = barInfo and barInfo.frame
    if not bar then return end

    bar._auraActive = nil
    bar._inPandemic = nil
    bar._auraInstanceID = nil
    bar._auraUnit = nil
    bar._pandemicGraceStart = nil
    bar._pandemicGraceSuppressed = nil

    if clearPreviewFlags then
        bar._barAuraActivePreview = nil
        bar._pandemicPreview = nil
    end

    ResetCustomAuraBarIndicatorVisuals(bar, barInfo.cabConfig)
end

local function ApplyCustomAuraBarPreviewState(barInfo)
    local bar = barInfo and barInfo.frame
    local cabConfig = barInfo and barInfo.cabConfig
    if not (bar and cabConfig) then
        return
    end

    bar._barAuraActivePreview = activeCustomAuraBarActivePreviews[cabConfig] and true or nil
    bar._pandemicPreview = activeCustomAuraBarPandemicPreviews[cabConfig] and true or nil
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

local function UpdateCustomAuraBarIndicatorVisuals(barInfo, cabConfig, auraPresent)
    local isSpellCustomCooldown = barInfo and barInfo.barType == "custom_cooldown"
    if not barInfo or (barInfo.barType ~= "custom_continuous" and not isSpellCustomCooldown) then return end
    if not cabConfig
        or (isSpellCustomCooldown and cabConfig.auraTracking ~= true)
        or (not isSpellCustomCooldown and cabConfig.trackingMode ~= "active") then
        ClearCustomAuraBarIndicatorState(barInfo, false)
        return
    end

    local bar = barInfo.frame
    if not bar then return end

    local auraPreview = bar._barAuraActivePreview
    local pandemicPreview = bar._pandemicPreview
    local auraActive = auraPresent or auraPreview or pandemicPreview
    bar._auraActive = auraActive or nil

    if not auraActive then
        bar._inPandemic = nil
        bar._pandemicGraceStart = nil
        bar._pandemicGraceSuppressed = nil
        ResetCustomAuraBarIndicatorVisuals(bar, cabConfig)
        return
    end

    local inCombat = InCombatLockdown()
    local auraVisualsEnabled = HasCustomAuraBarAuraVisuals(cabConfig)
    local auraCombatAllowed = not cabConfig.auraGlowCombatOnly or inCombat
    local pandemicEnabled = cabConfig.showPandemicGlow == true
    local pandemicCombatAllowed = not cabConfig.pandemicGlowCombatOnly or inCombat

    local wantAuraColor
    local activeAuraColor = isSpellCustomCooldown
        and (cabConfig.barAuraColor or {0.2, 1.0, 0.2, 1.0})
        or (cabConfig.barColor or {0.5, 0.5, 1})

    if pandemicPreview then
        wantAuraColor = cabConfig.barPandemicColor or DEFAULT_BAR_PANDEMIC_COLOR
    elseif auraPreview then
        wantAuraColor = activeAuraColor
    elseif auraPresent then
        if bar._inPandemic and pandemicEnabled and pandemicCombatAllowed then
            wantAuraColor = cabConfig.barPandemicColor or DEFAULT_BAR_PANDEMIC_COLOR
        elseif auraVisualsEnabled and auraCombatAllowed then
            wantAuraColor = activeAuraColor
        end
    end

    if bar._barAuraColor ~= wantAuraColor then
        bar._barAuraColor = wantAuraColor
        if not wantAuraColor and not bar._barColorShiftActive then
            local baseColor = cabConfig.barColor or {0.5, 0.5, 1}
            bar:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
        end
    end
    if wantAuraColor and not bar._barColorShiftActive then
        bar:SetStatusBarColor(wantAuraColor[1], wantAuraColor[2], wantAuraColor[3], wantAuraColor[4] or 1)
    end

    local showBarAuraEffect = auraPreview
        or pandemicPreview
        or auraVisualsEnabled
        or pandemicEnabled
    if showBarAuraEffect and not bar.barAuraEffect then
        bar.barAuraEffect = CreateGlowContainer(bar, 32, false)
    end

    local pandemicActive = pandemicPreview
        or (auraPresent and bar._inPandemic and pandemicEnabled and pandemicCombatAllowed)
    local effectShow = auraPreview
        or pandemicPreview
        or (auraPresent and (pandemicActive or (auraVisualsEnabled and auraCombatAllowed)))
    if bar.barAuraEffect then
        SetBarAuraEffect(bar, effectShow, pandemicActive or false)
    end

    local auraActiveForPulse = auraPreview
        or (auraVisualsEnabled and auraPresent and auraCombatAllowed)

    local wantPulse
    if (pandemicPreview or pandemicActive) and cabConfig.pandemicBarPulseEnabled then
        wantPulse = "pandemic"
    elseif auraActiveForPulse and cabConfig.barAuraPulseEnabled then
        wantPulse = "aura"
    end
    if wantPulse then
        bar._barPulseActive = true
        bar._barPulseSpeed = (wantPulse == "pandemic")
            and (cabConfig.pandemicBarPulseSpeed or 0.5)
            or (cabConfig.barAuraPulseSpeed or 0.5)
    elseif bar._barPulseActive then
        bar._barPulseActive = nil
        bar._barPulseSpeed = nil
        local fillTexture = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        if fillTexture and fillTexture.SetAlpha then
            fillTexture:SetAlpha(1)
        end
    end

    local wantColorShift
    if (pandemicPreview or pandemicActive) and cabConfig.pandemicBarColorShiftEnabled then
        wantColorShift = "pandemic"
    elseif auraActiveForPulse and cabConfig.barAuraColorShiftEnabled then
        wantColorShift = "aura"
    end
    if wantColorShift then
        bar._barColorShiftActive = true
        bar._barCSBaseColor = wantAuraColor or cabConfig.barColor or {0.5, 0.5, 1, 1}
        if wantColorShift == "pandemic" then
            bar._barCSShiftColor = cabConfig.pandemicBarColorShiftColor or {1, 1, 1, 1}
            bar._barCSSpeed = cabConfig.pandemicBarColorShiftSpeed or 0.5
        else
            bar._barCSShiftColor = cabConfig.barAuraColorShiftColor or {1, 1, 1, 1}
            bar._barCSSpeed = cabConfig.barAuraColorShiftSpeed or 0.5
        end
    elseif bar._barColorShiftActive then
        bar._barColorShiftActive = nil
        bar._barCSBaseColor = nil
        bar._barCSShiftColor = nil
        bar._barCSSpeed = nil
        local resetColor = wantAuraColor or cabConfig.barColor or {0.5, 0.5, 1}
        bar:SetStatusBarColor(resetColor[1], resetColor[2], resetColor[3], resetColor[4] or 1)
    end
end
local function ClearStaleRecycledBarRuntimeState(frame)
    if not frame then return end
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
                CancelNudgeTimers(btn)
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
    frame._auraActive = nil
    frame._auraInstanceID = nil
    frame._auraUnit = nil
    frame._inPandemic = nil
    frame._pandemicGraceStart = nil
    frame._pandemicGraceSuppressed = nil
    frame._parsedCustomBarAuraIDs = nil
    frame._parsedCustomBarAuraIDsRaw = nil
    frame._parsedCustomBarAuraIDsSpellID = nil
    frame._parsedCustomBarAuraIDsIncludeSpellID = nil
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

    local cx, cy = frame:GetCenter()
    local fw, fh = frame:GetSize()
    local relFrame = UIParent
    if anchor.relativeTo and anchor.relativeTo ~= "UIParent" then
        relFrame = _G[anchor.relativeTo] or UIParent
    end
    local tcx, tcy = relFrame:GetCenter()
    local tw, th = relFrame:GetSize()
    if not (cx and cy and fw and fh and tcx and tcy and tw and th) then return end

    local fax, fay = GetAnchorOffset(anchor.point, fw, fh)
    local tax, tay = GetAnchorOffset(anchor.relativePoint, tw, th)
    anchor.x = RoundToTenths((cx + fax) - (tcx + tax))
    anchor.y = RoundToTenths((cy + fay) - (tcy + tay))

    if frame._coordLabel then
        frame._coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(anchor.x, anchor.y))
    end

    if refreshConfig and IsBarsConfigActive() and CooldownCompanion.RefreshConfigPanel then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local UpdateIndependentStackDragState

local function CreateIndependentWrapperFrame()
    if independentWrapperFrame then return end

    local frame = CreateFrame("Frame", "CooldownCompanionResourceBarsIndependent", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(1, 1)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)

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
                if frame._coordLabel then
                    frame._coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(x, y))
                end
            end
        end

        btn:SetScript("OnEnter", function(self) self.arrow:SetVertexColor(1, 1, 1, 1) end)
        btn:SetScript("OnLeave", function(self)
            self.arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
            CancelNudgeTimers(self)
            SaveIndependentStackAnchor(true)
        end)
        btn:SetScript("OnMouseDown", function(self)
            DoNudge()
            self._cdcNudgeDelayTimer = C_Timer.NewTimer(INDEPENDENT_NUDGE_REPEAT_DELAY, function()
                self._cdcNudgeTicker = C_Timer.NewTicker(INDEPENDENT_NUDGE_REPEAT_INTERVAL, DoNudge)
            end)
        end)
        btn:SetScript("OnMouseUp", function(self)
            CancelNudgeTimers(self)
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
    coordLabel:EnableMouse(false)
    coordLabel.text = coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    coordLabel.text:SetPoint("CENTER")
    coordLabel.text:SetTextColor(1, 1, 1, 1)

    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        local settings = GetResourceBarSettings()
        if not settings then return end
        local placementSettings = GetSpecLayoutOrder(settings)
        if not placementSettings then return end
        if placementSettings.independentAnchorLocked then return end
        if InCombatLockdown() then return end
        frame:StartMoving()
    end)
    dragHandle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveIndependentStackAnchor(true)
    end)
    dragHandle:SetScript("OnMouseUp", function(_, button)
        if button ~= "MiddleButton" then return end
        local settings = GetResourceBarSettings()
        if not settings then return end
        local placementSettings = GetSpecLayoutOrder(settings)
        if not placementSettings then return end
        placementSettings.independentAnchorLocked = true
        frame:StopMovingOrSizing()
        SaveIndependentStackAnchor(true)
        UpdateIndependentStackDragState(settings, placementSettings)
    end)

    frame._dragHandle = dragHandle
    frame._nudger = nudger
    frame._coordLabel = coordLabel
    independentWrapperFrame = frame
end

UpdateIndependentStackDragState = function(settings, placementSettings)
    if not independentWrapperFrame then return end
    local frame = independentWrapperFrame
    placementSettings = placementSettings or (settings and GetSpecLayoutOrder(settings)) or settings
    local unlocked = placementSettings and placementSettings.independentAnchorEnabled == true and not placementSettings.independentAnchorLocked

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
                if not unlocked then
                    CancelNudgeTimers(btn)
                end
            end
        end
    end

    if frame._coordLabel then
        frame._coordLabel:SetShown(unlocked or false)
    end

    -- Force preview on while unlocked so bars are visible for positioning
    if unlocked and not isPreviewActive then
        CooldownCompanion:StartResourceBarPreview()
        frame._cdcForcedPreview = true
    elseif not unlocked and frame._cdcForcedPreview then
        frame._cdcForcedPreview = false
        CooldownCompanion:StopResourceBarPreview()
    end
end

local function HideIndependentWrapperFrame()
    if not independentWrapperFrame then return end
    independentWrapperFrame:Hide()
    if independentWrapperFrame._dragHandle then
        independentWrapperFrame._dragHandle:Hide()
    end
    if independentWrapperFrame._nudger then
        independentWrapperFrame._nudger:Hide()
        if independentWrapperFrame._nudger._cdcButtons then
            for _, btn in ipairs(independentWrapperFrame._nudger._cdcButtons) do
                CancelNudgeTimers(btn)
            end
        end
    end
    if independentWrapperFrame._coordLabel then
        independentWrapperFrame._coordLabel:Hide()
    end
    if independentWrapperFrame._cdcForcedPreview then
        independentWrapperFrame._cdcForcedPreview = false
        CooldownCompanion:StopResourceBarPreview()
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
            coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(
                placementSettings.independentAnchor.x or 0,
                placementSettings.independentAnchor.y or 0
            ))
        end
    end
end

--- Update cached MW max stacks based on Raging Maelstrom talent (OOC only — talents can't change in combat).
--- Returns true if the max changed (and bars were rebuilt), false otherwise.
local function UpdateMWMaxStacks()
    local hasRagingMaelstrom = C_SpellBook.IsSpellKnown(RAGING_MAELSTROM_SPELL_ID, Enum.SpellBookSpellBank.Player)
    local newMax = hasRagingMaelstrom and 10 or 5
    if mwMaxStacks ~= newMax then
        mwMaxStacks = newMax
        CooldownCompanion:ApplyResourceBars()  -- segment count changed, rebuild
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Update logic: Continuous resources (SECRET in combat — NO Lua arithmetic)
------------------------------------------------------------------------

local function UpdateContinuousBar(bar, powerType, settings, auraActiveCache)
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
    bar:SetMinMaxValues(0, maxPower)
    bar:SetValue(currentPower)

    local auraOverrideColor = GetResourceAuraState(powerType, settings, auraActiveCache)
    ApplyContinuousFillColor(bar, powerType, settings, auraOverrideColor)
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
-- Update logic: Player Health resource
------------------------------------------------------------------------

function HealthBar.GetConfig(settings)
    return GetResourceDisplayConfig(settings, RESOURCE_HEALTH)
end

function HealthBar.GetColor(config, key, fallback)
    local color = config and config[key]
    if type(color) == "table" and color[1] ~= nil and color[2] ~= nil and color[3] ~= nil then
        return color
    end
    return fallback
end

function HealthBar.GetAlpha(config, key, fallback)
    local value = tonumber(config and config[key])
    if not value then
        value = fallback
    end
    if value < 0 then
        return 0
    elseif value > 1 then
        return 1
    end
    return value
end

function HealthBar.IsBackgroundGradientEnabled(config)
    local enabled = config and config.healthBackgroundGradient
    if enabled == nil then
        return RB.DEFAULT_HEALTH_BACKGROUND_GRADIENT == true
    end
    return enabled == true
end

function HealthBar.IsFillGradientEnabled(config)
    local enabled = config and config.healthBarGradient
    if enabled == nil then
        return RB.DEFAULT_HEALTH_BAR_GRADIENT == true
    end
    return enabled == true
end

function HealthBar.SetBackgroundAnchors(bar)
    local bg = bar and bar.bg
    if not bg then return end

    local fillTexture = bar:GetStatusBarTexture()
    bg:ClearAllPoints()

    if bar._isVertical then
        if bar._reverseFill then
            bg:SetPoint("TOPLEFT", fillTexture, "BOTTOMLEFT", 0, 0)
            bg:SetPoint("TOPRIGHT", fillTexture, "BOTTOMRIGHT", 0, 0)
            bg:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        else
            bg:SetPoint("BOTTOMLEFT", fillTexture, "TOPLEFT", 0, 0)
            bg:SetPoint("BOTTOMRIGHT", fillTexture, "TOPRIGHT", 0, 0)
            bg:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            bg:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        end
    else
        bg:SetPoint("TOPLEFT", fillTexture, "TOPRIGHT", 0, 0)
        bg:SetPoint("BOTTOMLEFT", fillTexture, "BOTTOMRIGHT", 0, 0)
        bg:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    end
end

function HealthBar.EnsureEffectBar(bar, key, color, frameLevelOffset)
    if not bar then return nil end

    if not bar.healthEffectClip then
        local clip = CreateFrame("Frame", nil, bar)
        clip:SetAllPoints(bar)
        clip:SetClipsChildren(true)
        clip:SetFrameLevel(bar:GetFrameLevel() + 1)
        bar.healthEffectClip = clip
    end

    if not bar[key] then
        local effectBar = CreateFrame("StatusBar", nil, bar.healthEffectClip)
        effectBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(HEALTH_EFFECTS.texture))
        effectBar:SetMinMaxValues(0, 1)
        effectBar:SetValue(0)
        effectBar:Hide()
        bar[key] = effectBar
    end

    local effectBar = bar[key]
    effectBar:SetFrameLevel(bar:GetFrameLevel() + (frameLevelOffset or 2))
    effectBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(HEALTH_EFFECTS.texture))
    effectBar:SetStatusBarColor(color[1], color[2], color[3], color[4])
    return effectBar
end

function HealthBar.ApplyEffectStyle(effectBar, config, colorKey, defaultColor, textureKey)
    if not effectBar then return end

    local color = HealthBar.GetColor(config, colorKey, defaultColor)
    local texture = config and config[textureKey]
    if type(texture) ~= "string" or texture == "" then
        texture = HEALTH_EFFECTS.texture
    end
    effectBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(texture))
    effectBar:SetStatusBarColor(color[1], color[2], color[3], color[4] ~= nil and color[4] or 1)
end

function HealthBar.GetLowHealthAlertThreshold()
    local threshold = LowHealthFrame and tonumber(LowHealthFrame.lowHealthPercentStart)
    if not threshold or threshold <= 0 or threshold >= 1 then
        threshold = HEALTH_EFFECTS.lowHealthAlertThreshold
    end
    return threshold
end

function HealthBar.BuildLowHealthAlertCurve(config)
    local color = HealthBar.GetColor(config, "healthLowHealthAlertColor", HEALTH_EFFECTS.lowHealthAlertColor)
    local alpha = color[4]
    if alpha == nil then
        alpha = HEALTH_EFFECTS.lowHealthAlertColor[4] or 1
    end

    local threshold = HealthBar.GetLowHealthAlertThreshold()
    local curve = C_CurveUtil.CreateColorCurve()
    local alertColor = CreateColor(color[1], color[2], color[3], alpha)
    local transparentColor = CreateColor(color[1], color[2], color[3], 0)
    curve:AddPoint(0.0, alertColor)
    curve:AddPoint(threshold, alertColor)
    curve:AddPoint(math_min(1.0, threshold + HEALTH_EFFECTS.lowHealthAlertThresholdFade), transparentColor)
    curve:AddPoint(1.0, transparentColor)
    return curve
end

function HealthBar.ApplyLowHealthAlertStyle(effectBar, config)
    if not effectBar then return end

    local texture = config and config.healthLowHealthAlertTexture
    if type(texture) ~= "string" or texture == "" then
        texture = HEALTH_EFFECTS.texture
    end
    effectBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(texture))
    effectBar:SetMinMaxValues(0, 1)
    effectBar:SetValue(1)
end

function HealthBar.ApplyLowHealthAlertColor(bar, config, preview)
    local effectBar = bar and bar.lowHealthAlertBar
    local fillTexture = effectBar and effectBar:GetStatusBarTexture()
    if not fillTexture then return end

    if preview == true then
        local color = HealthBar.GetColor(config, "healthLowHealthAlertColor", HEALTH_EFFECTS.lowHealthAlertColor)
        fillTexture:SetVertexColor(color[1], color[2], color[3], color[4] ~= nil and color[4] or 1)
        return
    end

    if not bar._lowHealthAlertCurve then
        bar._lowHealthAlertCurve = HealthBar.BuildLowHealthAlertCurve(config)
    end
    local color = UnitHealthPercent("player", true, bar._lowHealthAlertCurve)
    if type(color) == "table" and color.GetRGBA then
        fillTexture:SetVertexColor(color:GetRGBA())
        return
    end

    fillTexture:SetVertexColor(0, 0, 0, 0)
end

function HealthBar.SetEffectAlphaFromBoolean(effectBar, value, alphaIfTrue, alphaIfFalse)
    if not effectBar then
        return
    end
    if effectBar.SetAlphaFromBoolean then
        effectBar:SetAlphaFromBoolean(value, alphaIfTrue, alphaIfFalse)
        return
    end
    local texture = effectBar.GetStatusBarTexture and effectBar:GetStatusBarTexture()
    if texture and texture.SetAlphaFromBoolean then
        texture:SetAlphaFromBoolean(value, alphaIfTrue, alphaIfFalse)
    end
end

function HealthBar.EnsureEffectBars(bar)
    HealthBar.EnsureEffectBar(bar, "lowHealthAlertBar", HEALTH_EFFECTS.lowHealthAlertColor, 2)
    HealthBar.EnsureEffectBar(bar, "incomingHealBar", HEALTH_EFFECTS.incomingHealColor, 3)
    HealthBar.EnsureEffectBar(bar, "absorbOverflowBar", HEALTH_EFFECTS.absorbColor, 4)
    HealthBar.EnsureEffectBar(bar, "absorbBar", HEALTH_EFFECTS.absorbColor, 5)
    HealthBar.EnsureEffectBar(bar, "healAbsorbBar", HEALTH_EFFECTS.healAbsorbColor, 6)
end

function HealthBar.LayoutFullEffectBar(bar, effectBar)
    if not bar or not effectBar then return end

    effectBar:ClearAllPoints()
    effectBar:SetOrientation(bar._isVertical and "VERTICAL" or "HORIZONTAL")
    effectBar:SetReverseFill(false)
    if bar.healthEffectClip then
        effectBar:SetAllPoints(bar.healthEffectClip)
    else
        effectBar:SetAllPoints(bar)
    end
end

function HealthBar.LayoutLowHealthAlertBar(bar, config)
    local effectBar = bar and bar.lowHealthAlertBar
    if not bar or not effectBar then return end

    if not (config and config.healthLowHealthAlertMissingHealthOnly == true) then
        HealthBar.LayoutFullEffectBar(bar, effectBar)
        return
    end

    local fillTexture = bar:GetStatusBarTexture()
    local outerFrame = bar.healthEffectClip or bar
    if not fillTexture or not outerFrame then return end

    effectBar:ClearAllPoints()
    effectBar:SetOrientation(bar._isVertical and "VERTICAL" or "HORIZONTAL")
    effectBar:SetReverseFill(false)

    if bar._isVertical then
        if bar._reverseFill then
            effectBar:SetPoint("TOPLEFT", fillTexture, "BOTTOMLEFT", 0, 0)
            effectBar:SetPoint("TOPRIGHT", fillTexture, "BOTTOMRIGHT", 0, 0)
            effectBar:SetPoint("BOTTOMLEFT", outerFrame, "BOTTOMLEFT", 0, 0)
            effectBar:SetPoint("BOTTOMRIGHT", outerFrame, "BOTTOMRIGHT", 0, 0)
        else
            effectBar:SetPoint("BOTTOMLEFT", fillTexture, "TOPLEFT", 0, 0)
            effectBar:SetPoint("BOTTOMRIGHT", fillTexture, "TOPRIGHT", 0, 0)
            effectBar:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 0, 0)
            effectBar:SetPoint("TOPRIGHT", outerFrame, "TOPRIGHT", 0, 0)
        end
    else
        effectBar:SetPoint("TOPLEFT", fillTexture, "TOPRIGHT", 0, 0)
        effectBar:SetPoint("BOTTOMLEFT", fillTexture, "BOTTOMRIGHT", 0, 0)
        effectBar:SetPoint("TOPRIGHT", outerFrame, "TOPRIGHT", 0, 0)
        effectBar:SetPoint("BOTTOMRIGHT", outerFrame, "BOTTOMRIGHT", 0, 0)
    end
end

function HealthBar.LayoutForwardEffectBar(bar, effectBar, anchorTexture, overlapJoin)
    local fillTexture = anchorTexture or (bar and bar:GetStatusBarTexture())
    if not bar or not effectBar or not fillTexture then return end

    effectBar:ClearAllPoints()
    effectBar:SetOrientation(bar._isVertical and "VERTICAL" or "HORIZONTAL")
    local overlap = overlapJoin and HEALTH_EFFECT_JOIN_OVERLAP or 0

    if bar._isVertical then
        effectBar:SetHeight(bar:GetHeight())
        if bar._reverseFill then
            effectBar:SetReverseFill(true)
            effectBar:SetPoint("TOPLEFT", fillTexture, "BOTTOMLEFT", 0, overlap)
            effectBar:SetPoint("TOPRIGHT", fillTexture, "BOTTOMRIGHT", 0, overlap)
        else
            effectBar:SetReverseFill(false)
            effectBar:SetPoint("BOTTOMLEFT", fillTexture, "TOPLEFT", 0, -overlap)
            effectBar:SetPoint("BOTTOMRIGHT", fillTexture, "TOPRIGHT", 0, -overlap)
        end
    else
        effectBar:SetReverseFill(false)
        effectBar:SetWidth(bar:GetWidth())
        effectBar:SetPoint("TOPLEFT", fillTexture, "TOPRIGHT", -overlap, 0)
        effectBar:SetPoint("BOTTOMLEFT", fillTexture, "BOTTOMRIGHT", -overlap, 0)
    end
end

function HealthBar.LayoutHealAbsorbBar(bar)
    local effectBar = bar and bar.healAbsorbBar
    local fillTexture = bar and bar:GetStatusBarTexture()
    if not bar or not effectBar or not fillTexture then return end

    effectBar:ClearAllPoints()
    effectBar:SetOrientation(bar._isVertical and "VERTICAL" or "HORIZONTAL")

    if bar._isVertical then
        effectBar:SetHeight(bar:GetHeight())
        if bar._reverseFill then
            effectBar:SetReverseFill(false)
            effectBar:SetPoint("BOTTOMLEFT", fillTexture, "BOTTOMLEFT", 0, 0)
            effectBar:SetPoint("BOTTOMRIGHT", fillTexture, "BOTTOMRIGHT", 0, 0)
        else
            effectBar:SetReverseFill(true)
            effectBar:SetPoint("TOPLEFT", fillTexture, "TOPLEFT", 0, 0)
            effectBar:SetPoint("TOPRIGHT", fillTexture, "TOPRIGHT", 0, 0)
        end
    else
        effectBar:SetReverseFill(true)
        effectBar:SetWidth(bar:GetWidth())
        effectBar:SetPoint("TOPRIGHT", fillTexture, "TOPRIGHT", 0, 0)
        effectBar:SetPoint("BOTTOMRIGHT", fillTexture, "BOTTOMRIGHT", 0, 0)
    end
end

function HealthBar.LayoutReverseEdgeEffectBar(bar, effectBar)
    if not bar or not effectBar then return end

    effectBar:ClearAllPoints()
    effectBar:SetOrientation(bar._isVertical and "VERTICAL" or "HORIZONTAL")
    if bar.healthEffectClip then
        effectBar:SetAllPoints(bar.healthEffectClip)
    else
        effectBar:SetAllPoints(bar)
    end

    if bar._isVertical then
        effectBar:SetReverseFill(not bar._reverseFill)
    else
        effectBar:SetReverseFill(true)
    end
end

function HealthBar.LayoutEffectBars(bar, borderStyle, borderSize, config)
    if not bar then return end
    if bar.healthEffectClip then
        bar.healthEffectClip:SetFrameLevel(bar:GetFrameLevel() + 1)
        bar.healthEffectClip:ClearAllPoints()
        if borderStyle == "pixel" then
            borderSize = tonumber(borderSize) or 1
            bar.healthEffectClip:SetPoint("TOPLEFT", bar, "TOPLEFT", borderSize, -borderSize)
            bar.healthEffectClip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -borderSize, borderSize)
        else
            bar.healthEffectClip:SetAllPoints(bar)
        end
    end
    HealthBar.LayoutLowHealthAlertBar(bar, config)
    HealthBar.LayoutForwardEffectBar(bar, bar.incomingHealBar)
    HealthBar.LayoutForwardEffectBar(bar, bar.absorbBar)
    HealthBar.LayoutReverseEdgeEffectBar(bar, bar.absorbOverflowBar)
    HealthBar.LayoutHealAbsorbBar(bar)
    if bar.textLayer then
        bar.textLayer:SetFrameLevel(bar:GetFrameLevel() + 7)
    end
end

function HealthBar.UpdateEffectBars(bar, config, maxHealth, preview)
    if not bar then return end

    local netHealingCalcPopulated = false
    local standaloneHealingCalcPopulated = false
    local function GetNetHealingCalc()
        if not netHealingCalcPopulated then
            UnitGetDetailedHealPrediction("player", nil, HEALTH_EFFECTS.netHealingCalc)
            netHealingCalcPopulated = true
        end
        return HEALTH_EFFECTS.netHealingCalc
    end
    local function GetStandaloneHealingCalc()
        if not standaloneHealingCalcPopulated then
            UnitGetDetailedHealPrediction("player", nil, HEALTH_EFFECTS.standaloneHealingCalc)
            standaloneHealingCalcPopulated = true
        end
        return HEALTH_EFFECTS.standaloneHealingCalc
    end

    if not config then
        if bar.lowHealthAlertBar then bar.lowHealthAlertBar:Hide() end
        if bar.incomingHealBar then bar.incomingHealBar:Hide() end
        if bar.absorbBar then bar.absorbBar:Hide() end
        if bar.absorbOverflowBar then bar.absorbOverflowBar:Hide() end
        if bar.healAbsorbBar then bar.healAbsorbBar:Hide() end
        return
    end

    preview = preview or HEALTH_EFFECTS.preview

    if bar.lowHealthAlertBar then
        HealthBar.ApplyLowHealthAlertStyle(bar.lowHealthAlertBar, config)
        if config.showLowHealthAlert == true or preview.lowHealthAlert == true then
            HealthBar.ApplyLowHealthAlertColor(bar, config, preview.lowHealthAlert == true)
            bar.lowHealthAlertBar:SetAlpha(0.6 + (0.4 * math_sin(GetTime() * 2 * math_pi / HEALTH_EFFECTS.lowHealthAlertPulseSpeed)))
            bar.lowHealthAlertBar:Show()
        else
            bar.lowHealthAlertBar:Hide()
            bar.lowHealthAlertBar:SetAlpha(1)
            bar.lowHealthAlertBar:SetValue(0)
        end
    end

    local incomingHealsVisible = config.showIncomingHeals == true or preview.incomingHeals == true
    local incomingHealAnchorTexture = nil
    if bar.incomingHealBar then
        HealthBar.ApplyEffectStyle(bar.incomingHealBar, config, "healthIncomingHealColor", HEALTH_EFFECTS.incomingHealColor, "healthIncomingHealTexture")
        if incomingHealsVisible then
            bar.incomingHealBar:SetMinMaxValues(0, maxHealth)
            if preview.incomingHeals == true then
                bar.incomingHealBar:SetValue(18)
            else
                bar.incomingHealBar:SetValue(EnsureNonNilNumber(GetNetHealingCalc():GetIncomingHeals()))
            end
            bar.incomingHealBar:Show()
            incomingHealAnchorTexture = bar.incomingHealBar:GetStatusBarTexture()
        else
            bar.incomingHealBar:Hide()
            bar.incomingHealBar:SetValue(0)
        end
    end

    if bar.absorbBar then
        HealthBar.LayoutForwardEffectBar(bar, bar.absorbBar, incomingHealAnchorTexture, true)
        HealthBar.ApplyEffectStyle(bar.absorbBar, config, "healthAbsorbColor", HEALTH_EFFECTS.absorbColor, "healthAbsorbTexture")
        HealthBar.ApplyEffectStyle(bar.absorbOverflowBar, config, "healthAbsorbColor", HEALTH_EFFECTS.absorbColor, "healthAbsorbTexture")
        if config.showAbsorbs == true or preview.absorbs == true then
            local missingHealthAbsorb
            local absorbOverflowing
            local overflowAbsorb
            if preview.absorbs == true then
                missingHealthAbsorb = 0
                absorbOverflowing = true
                overflowAbsorb = 28
            else
                HEALTH_EFFECTS.absorbMissingCalc:SetDamageAbsorbClampMode(
                    incomingHealsVisible
                        and Enum.UnitDamageAbsorbClampMode.MissingHealth
                        or Enum.UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals
                )
                HEALTH_EFFECTS.absorbMissingCalc:SetHealAbsorbMode(
                    incomingHealsVisible
                        and Enum.UnitHealAbsorbMode.ReducedByIncomingHeals
                        or Enum.UnitHealAbsorbMode.Total
                )
                UnitGetDetailedHealPrediction("player", nil, HEALTH_EFFECTS.absorbMissingCalc)
                missingHealthAbsorb, absorbOverflowing = HEALTH_EFFECTS.absorbMissingCalc:GetDamageAbsorbs()
                UnitGetDetailedHealPrediction("player", nil, HEALTH_EFFECTS.absorbOverflowCalc)
                overflowAbsorb = HEALTH_EFFECTS.absorbOverflowCalc:GetDamageAbsorbs()
            end

            bar.absorbBar:SetMinMaxValues(0, maxHealth)
            bar.absorbBar:SetValue(EnsureNonNilNumber(missingHealthAbsorb))
            bar.absorbBar:SetAlpha(1)
            bar.absorbBar:Show()
            if bar.absorbOverflowBar then
                bar.absorbOverflowBar:SetMinMaxValues(0, maxHealth)
                bar.absorbOverflowBar:SetValue(EnsureNonNilNumber(overflowAbsorb))
                HealthBar.SetEffectAlphaFromBoolean(bar.absorbOverflowBar, absorbOverflowing, 1, 0)
                bar.absorbOverflowBar:Show()
            end
        else
            bar.absorbBar:Hide()
            bar.absorbBar:SetValue(0)
            if bar.absorbOverflowBar then
                bar.absorbOverflowBar:Hide()
                bar.absorbOverflowBar:SetValue(0)
            end
        end
    end

    if bar.healAbsorbBar then
        HealthBar.ApplyEffectStyle(bar.healAbsorbBar, config, "healthHealAbsorbColor", HEALTH_EFFECTS.healAbsorbColor, "healthHealAbsorbTexture")
        if config.showHealAbsorbs == true or preview.healAbsorbs == true then
            bar.healAbsorbBar:SetMinMaxValues(0, maxHealth)
            if preview.healAbsorbs == true then
                bar.healAbsorbBar:SetValue(22)
            else
                local healAbsorbCalc = incomingHealsVisible and GetNetHealingCalc() or GetStandaloneHealingCalc()
                bar.healAbsorbBar:SetValue(EnsureNonNilNumber(healAbsorbCalc:GetHealAbsorbs()))
            end
            bar.healAbsorbBar:Show()
        else
            bar.healAbsorbBar:Hide()
            bar.healAbsorbBar:SetValue(0)
        end
    end
end

function HealthBar.BuildGradientCurve(config, opacityKey, opacityDefault, fullKey, fullDefault, halfKey, halfDefault, lowKey, lowDefault)
    local opacity = HealthBar.GetAlpha(config, opacityKey, opacityDefault)
    local full = HealthBar.GetColor(config, fullKey, fullDefault)
    local half = HealthBar.GetColor(config, halfKey, halfDefault)
    local low = HealthBar.GetColor(config, lowKey, lowDefault)
    local curve = C_CurveUtil.CreateColorCurve()
    curve:AddPoint(0.0, CreateColor(low[1], low[2], low[3], opacity))
    curve:AddPoint(0.5, CreateColor(half[1], half[2], half[3], opacity))
    curve:AddPoint(1.0, CreateColor(full[1], full[2], full[3], opacity))
    return curve
end

function HealthBar.BuildFillCurve(config)
    return HealthBar.BuildGradientCurve(
        config,
        "healthBarOpacity", RB.DEFAULT_HEALTH_BAR_OPACITY,
        "healthBarFullColor", RB.DEFAULT_HEALTH_BAR_FULL_COLOR,
        "healthBarHalfColor", RB.DEFAULT_HEALTH_BAR_HALF_COLOR,
        "healthBarLowColor", RB.DEFAULT_HEALTH_BAR_LOW_COLOR
    )
end

function HealthBar.BuildBackgroundCurve(config)
    return HealthBar.BuildGradientCurve(
        config,
        "healthBackgroundOpacity", RB.DEFAULT_HEALTH_BACKGROUND_OPACITY,
        "healthBackgroundFullColor", RB.DEFAULT_HEALTH_BACKGROUND_FULL_COLOR,
        "healthBackgroundHalfColor", RB.DEFAULT_HEALTH_BACKGROUND_HALF_COLOR,
        "healthBackgroundLowColor", RB.DEFAULT_HEALTH_BACKGROUND_LOW_COLOR
    )
end

function HealthBar.GetPreviewGradientColor(config, percent, opacityKey, opacityDefault, fullKey, fullDefault, halfKey, halfDefault, lowKey, lowDefault)
    percent = tonumber(percent) or 0.65
    if percent < 0 then
        percent = 0
    elseif percent > 1 then
        percent = 1
    end

    local opacity = HealthBar.GetAlpha(config, opacityKey, opacityDefault)
    local full = HealthBar.GetColor(config, fullKey, fullDefault)
    local half = HealthBar.GetColor(config, halfKey, halfDefault)
    local low = HealthBar.GetColor(config, lowKey, lowDefault)
    local fromColor = low
    local toColor = half
    local t = percent * 2

    if percent > 0.5 then
        fromColor = half
        toColor = full
        t = (percent - 0.5) * 2
    end

    return CreateColor(
        fromColor[1] + ((toColor[1] - fromColor[1]) * t),
        fromColor[2] + ((toColor[2] - fromColor[2]) * t),
        fromColor[3] + ((toColor[3] - fromColor[3]) * t),
        opacity
    )
end

function HealthBar.ApplyFillColor(bar, config, previewPercent)
    if not bar then return end

    local color
    if HealthBar.IsFillGradientEnabled(config) then
        if previewPercent then
            color = HealthBar.GetPreviewGradientColor(
                config, previewPercent,
                "healthBarOpacity", RB.DEFAULT_HEALTH_BAR_OPACITY,
                "healthBarFullColor", RB.DEFAULT_HEALTH_BAR_FULL_COLOR,
                "healthBarHalfColor", RB.DEFAULT_HEALTH_BAR_HALF_COLOR,
                "healthBarLowColor", RB.DEFAULT_HEALTH_BAR_LOW_COLOR
            )
        else
            color = UnitHealthPercent("player", true, bar._healthBarCurve)
        end
    else
        local opacity = HealthBar.GetAlpha(config, "healthBarOpacity", RB.DEFAULT_HEALTH_BAR_OPACITY)
        local static = HealthBar.GetColor(config, "healthBarColor", RB.DEFAULT_HEALTH_BAR_COLOR)
        color = CreateColor(static[1], static[2], static[3], opacity)
    end

    if type(color) == "table" and color.GetRGBA then
        local r, g, b, a = color:GetRGBA()
        bar:SetStatusBarColor(r, g, b, 1)
        local fillTexture = bar:GetStatusBarTexture()
        if fillTexture and fillTexture.SetAlpha then
            fillTexture:SetAlpha(a)
        end
        return
    end

    local r, g, b, a
    if type(color) == "table" then
        r = color.r or color[1]
        g = color.g or color[2]
        b = color.b or color[3]
        a = color.a or color[4]
    end

    if r and g and b then
        bar:SetStatusBarColor(r, g, b, 1)
        local fillTexture = bar:GetStatusBarTexture()
        if fillTexture and fillTexture.SetAlpha then
            fillTexture:SetAlpha(a ~= nil and a or HealthBar.GetAlpha(config, "healthBarOpacity", RB.DEFAULT_HEALTH_BAR_OPACITY))
        end
    end
end

function HealthBar.ApplyBackgroundColor(bar, config, previewPercent)
    if not bar or not bar.bg then return end

    local color
    if HealthBar.IsBackgroundGradientEnabled(config) then
        if previewPercent then
            color = HealthBar.GetPreviewGradientColor(
                config, previewPercent,
                "healthBackgroundOpacity", RB.DEFAULT_HEALTH_BACKGROUND_OPACITY,
                "healthBackgroundFullColor", RB.DEFAULT_HEALTH_BACKGROUND_FULL_COLOR,
                "healthBackgroundHalfColor", RB.DEFAULT_HEALTH_BACKGROUND_HALF_COLOR,
                "healthBackgroundLowColor", RB.DEFAULT_HEALTH_BACKGROUND_LOW_COLOR
            )
        else
            color = UnitHealthPercent("player", true, bar._healthBackgroundCurve)
        end
    else
        local opacity = HealthBar.GetAlpha(config, "healthBackgroundOpacity", RB.DEFAULT_HEALTH_BACKGROUND_OPACITY)
        local static = HealthBar.GetColor(config, "healthBackgroundColor", RB.DEFAULT_HEALTH_BACKGROUND_COLOR)
        color = CreateColor(static[1], static[2], static[3], opacity)
    end

    if type(color) == "table" and color.GetRGBA then
        bar.bg:SetVertexColor(color:GetRGBA())
        return
    end

    local r, g, b, a
    if type(color) == "table" then
        r = color.r or color[1]
        g = color.g or color[2]
        b = color.b or color[3]
        a = color.a or color[4]
    end

    if r and g and b then
        bar.bg:SetVertexColor(r, g, b, a ~= nil and a or HealthBar.GetAlpha(config, "healthBackgroundOpacity", RB.DEFAULT_HEALTH_BACKGROUND_OPACITY))
    end
end

function HealthBar.Update(bar, settings)
    if not settings then
        settings = GetResourceBarSettings()
    end

    local currentHealth = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    local maxHealthIsSecret = issecretvalue and issecretvalue(maxHealth)
    if not maxHealthIsSecret and (not maxHealth or maxHealth < 1) then
        maxHealth = 1
    end

    bar:SetMinMaxValues(0, maxHealth)
    bar:SetValue(currentHealth)
    local config = HealthBar.GetConfig(settings)
    HealthBar.ApplyFillColor(bar, config)
    HealthBar.ApplyBackgroundColor(bar, config)
    HealthBar.UpdateEffectBars(bar, config, maxHealth)

    if bar.text and bar.text:IsShown() then
        local textFormat = bar._textFormat
        if textFormat == "current" then
            bar.text:SetFormattedText("%s", AbbreviateNumbers(currentHealth))
        elseif textFormat == "current_max" then
            bar.text:SetFormattedText("%s / %s", AbbreviateNumbers(currentHealth), AbbreviateNumbers(maxHealth))
        elseif textFormat == "current_percent" then
            bar.text:SetFormattedText(
                "%s | %.0f%%",
                AbbreviateNumbers(currentHealth),
                UnitHealthPercent("player", true, PERCENT_SCALE_CURVE)
            )
        elseif textFormat == "current_percent_no_sign" then
            bar.text:SetFormattedText(
                "%s | %.0f",
                AbbreviateNumbers(currentHealth),
                UnitHealthPercent("player", true, PERCENT_SCALE_CURVE)
            )
        elseif textFormat == "percent_no_sign" then
            bar.text:SetFormattedText("%.0f", UnitHealthPercent("player", true, PERCENT_SCALE_CURVE))
        else
            bar.text:SetFormattedText("%.0f%%", UnitHealthPercent("player", true, PERCENT_SCALE_CURVE))
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
    bar:SetMinMaxValues(0, maxHealth)
    bar:SetValue(staggerAmount)

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

function segmentedUpdateScratch.GetFullSegments(holder)
    if not holder._fullSegmentsScratch then
        holder._fullSegmentsScratch = {}
    else
        wipe(holder._fullSegmentsScratch)
    end
    return holder._fullSegmentsScratch
end

function segmentedUpdateScratch.ClearValues(holder)
    for _, seg in ipairs(holder.segments) do
        seg:SetValue(0)
    end
end

function segmentedUpdateScratch.ApplyAuraVisuals(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments)
    if auraOverrideColor and not useAuraStackMode then
        for i, seg in ipairs(holder.segments) do
            if fullSegments[i] then
                seg:SetStatusBarColor(auraOverrideColor[1], auraOverrideColor[2], auraOverrideColor[3], 1)
            end
        end
    end

    if useAuraStackMode then
        ApplyResourceAuraStackSegments(holder, settings, auraApplications, auraMaxStacks, auraOverrideColor)
    else
        HideResourceAuraStackSegments(holder)
    end
end

function segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, currentValue, maxValue, clearText)
    segmentedUpdateScratch.ApplyAuraVisuals(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments)
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

local function UpdateSegmentedBar(holder, powerType, settings, auraActiveCache)
    if not holder or not holder.segments then return end
    if not settings then
        settings = GetResourceBarSettings()
    end

    local auraOverrideColor, auraApplications, auraHasApplications = GetResourceAuraState(powerType, settings, auraActiveCache)
    local auraMaxStacks = GetResourceAuraConfiguredMaxStacks(powerType, settings)
    local useAuraStackMode = auraOverrideColor
        and auraMaxStacks
        and auraHasApplications
        and SupportsResourceAuraStackMode(powerType)
    local thresholdEnabled, thresholdValue, thresholdColor = GetSegmentedThresholdConfig(powerType, settings)
    local fullSegments = segmentedUpdateScratch.GetFullSegments(holder)

    if powerType == 5 then
        -- DK Runes: sorted by readiness (ready left, longest CD right)
        local now = GetTime()
        local numSegs = math_min(#holder.segments, 6)
        local runeData = segmentedUpdateScratch.GetRuneData(holder)
        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown(i)
            local remaining = 0
            if not ready and duration and duration > 0 then
                remaining = math_max((start + duration) - now, 0)
            end
            local rune = runeData[i]
            rune.start = start
            rune.duration = duration
            rune.ready = ready
            rune.remaining = remaining
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
        local thresholdActive = thresholdEnabled and readyCount >= thresholdValue
        local activeReadyColor = allReady and maxColor or (thresholdActive and thresholdColor or readyColor)
        local runeValueTotal = 0
        for i = 1, numSegs do
            local r = runeData[i]
            local seg = holder.segments[i]
            local segValue = 0
            if r.ready then
                segValue = 1
                seg:SetValue(segValue)
                seg:SetStatusBarColor(activeReadyColor[1], activeReadyColor[2], activeReadyColor[3], 1)
                fullSegments[i] = true
            elseif r.duration and r.duration > 0 then
                segValue = math_min((now - r.start) / r.duration, 1)
                seg:SetValue(segValue)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            else
                seg:SetValue(segValue)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            end
            runeValueTotal = runeValueTotal + segValue
        end
        segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, runeValueTotal, numSegs, false)
        return
    end

    if powerType == 7 then
        if IsUnitPowerSecret("player", 7) or IsUnitPowerMaxSecret("player", 7) then
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, nil, nil, true)
            return
        end

        -- Soul Shards: fractional fill with ready/recharging colors
        local raw = UnitPower("player", 7, true)
        local rawMax = UnitPowerMax("player", 7, true)
        local max = UnitPowerMax("player", 7)
        if issecretvalue and (issecretvalue(raw) or issecretvalue(rawMax) or issecretvalue(max)) then
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, nil, nil, true)
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
                local thresholdActive = thresholdEnabled and filled >= thresholdValue
                local activeReadyColor = isMax and maxColor or (thresholdActive and thresholdColor or readyColor)
                for i = 1, math_min(#holder.segments, max) do
                    local seg = holder.segments[i]
                    if i <= filled then
                        seg:SetValue(1)
                        seg:SetStatusBarColor(activeReadyColor[1], activeReadyColor[2], activeReadyColor[3], 1)
                        fullSegments[i] = true
                    elseif i == filled + 1 and partial > 0 then
                        seg:SetValue(partial)
                        seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
                    else
                        seg:SetValue(0)
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
            segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, displayCurrent, max, false)
        else
            segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, nil, nil, true)
        end
        return
    end

    if powerType == 19 then
        if IsUnitPowerSecret("player", 19) or IsUnitPowerMaxSecret("player", 19) then
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, nil, nil, true)
            return
        end

        -- Essence: partial recharge with ready/recharging colors
        local filled = UnitPower("player", 19)
        local max = UnitPowerMax("player", 19)
        local partialRaw = UnitPartialPower("player", 19)
        if issecretvalue and (issecretvalue(filled) or issecretvalue(max) or issecretvalue(partialRaw)) then
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, nil, nil, true)
            return
        end

        local partial = partialRaw / 1000
        local displayCurrent = filled + partial
        local readyColor, rechargingColor, maxColor = GetResourceColors(19, settings)
        local isMax = (filled == max)
        local thresholdActive = thresholdEnabled and filled >= thresholdValue
        local activeReadyColor = isMax and maxColor or (thresholdActive and thresholdColor or readyColor)
        for i = 1, math_min(#holder.segments, max) do
            local seg = holder.segments[i]
            if i <= filled then
                seg:SetValue(1)
                seg:SetStatusBarColor(activeReadyColor[1], activeReadyColor[2], activeReadyColor[3], 1)
                fullSegments[i] = true
            elseif i == filled + 1 and partial > 0 then
                seg:SetValue(partial)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            else
                seg:SetValue(0)
                seg:SetStatusBarColor(rechargingColor[1], rechargingColor[2], rechargingColor[3], 1)
            end
        end
        segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, displayCurrent, max, false)
        return
    end

    -- Combo Points: color changes at max, charged coloring for Rogues
    if powerType == 4 then
        if IsUnitPowerSecret("player", 4) or IsUnitPowerMaxSecret("player", 4) then
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, nil, nil, true)
            return
        end

        local current = UnitPower("player", 4)
        local max = UnitPowerMax("player", 4)
        if issecretvalue and (issecretvalue(current) or issecretvalue(max)) then
            segmentedUpdateScratch.ClearValues(holder)
            segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, nil, nil, true)
            return
        end

        local normalColor, maxColor, chargedColor = GetResourceColors(4, settings)
        local isMax = (current == max and max > 0)
        local thresholdActive = thresholdEnabled and current >= thresholdValue
        local baseColor = isMax and maxColor or (thresholdActive and thresholdColor or normalColor)

        -- Charged combo points (Rogue only)
        local chargedPoints
        if GetPlayerClassID() == 4 then
            chargedPoints = GetUnitChargedPowerPoints("player")
        end

        for i = 1, math_min(#holder.segments, max) do
            local seg = holder.segments[i]
            if i <= current then
                seg:SetValue(1)
                fullSegments[i] = true
                if chargedPoints and tContains(chargedPoints, i) then
                    seg:SetStatusBarColor(chargedColor[1], chargedColor[2], chargedColor[3], 1)
                else
                    seg:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
                end
            else
                seg:SetValue(0)
            end
        end
        segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, current, max, false)
        return
    end

    -- Generic segmented with max color: HolyPower, Chi, ArcaneCharges
    if IsUnitPowerSecret("player", powerType) or IsUnitPowerMaxSecret("player", powerType) then
        segmentedUpdateScratch.ClearValues(holder)
        segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, nil, nil, true)
        return
    end

    local current = UnitPower("player", powerType)
    local max = UnitPowerMax("player", powerType)
    if issecretvalue and (issecretvalue(current) or issecretvalue(max)) then
        segmentedUpdateScratch.ClearValues(holder)
        segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, nil, nil, true)
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
    local thresholdActive = thresholdEnabled and current >= thresholdValue
    local activeColor = isMax and maxColor or (thresholdActive and thresholdColor or normalColor)
    for i = 1, math_min(#holder.segments, max) do
        local seg = holder.segments[i]
        if i <= current then
            seg:SetValue(1)
            seg:SetStatusBarColor(activeColor[1], activeColor[2], activeColor[3], 1)
            fullSegments[i] = true
        else
            seg:SetValue(0)
        end
    end
    segmentedUpdateScratch.Finalize(holder, settings, auraOverrideColor, useAuraStackMode, auraApplications, auraMaxStacks, fullSegments, current, max, false)
end

------------------------------------------------------------------------
-- Update logic: Maelstrom Weapon (overlay bar, plain applications)
------------------------------------------------------------------------

local function UpdateMaelstromWeaponBar(holder, settings, auraActiveCache)
    if not holder or not holder.segments then return end
    if not settings then
        settings = GetResourceBarSettings()
    end

    -- Read stacks from viewer frame (applications is plain for MW)
    local thresholdEnabled, thresholdValue, thresholdColor = GetSegmentedThresholdConfig(RESOURCE_MAELSTROM_WEAPON, settings)
    local stacks = 0
    local viewerFrame = CooldownCompanion.viewerAuraFrames and CooldownCompanion.viewerAuraFrames[MW_SPELL_ID]
    local instId = viewerFrame and viewerFrame.auraInstanceID
    if instId then
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", instId)
        if auraData then
            stacks = auraData.applications or 0
        end
    end
    if issecretvalue and issecretvalue(stacks) then
        for i = 1, #holder.segments do
            holder.segments[i]:SetValue(0)
            if holder.overlaySegments and holder.overlaySegments[i] then
                holder.overlaySegments[i]:SetValue(0)
                holder.overlaySegments[i]:SetAlpha(0)
            end
        end
        HideResourceAuraStackSegments(holder)
        ClearSegmentedText(holder)
        return
    end

    local half = #holder.segments
    local baseColor, overlayColor, maxColor = GetResourceColors(100, settings)
    local thresholdActive = thresholdEnabled and stacks >= thresholdValue
    local isMax = stacks > 0 and stacks == mwMaxStacks

    for i = 1, half do
        local baseSeg = holder.segments[i]
        local overlaySeg = holder.overlaySegments[i]

        baseSeg:SetValue(stacks)
        overlaySeg:SetValue(stacks)
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

    local auraOverrideColor, auraApplications, auraHasApplications = GetResourceAuraState(100, settings, auraActiveCache)
    local auraMaxStacks = GetResourceAuraConfiguredMaxStacks(100, settings)
    local useAuraStackMode = auraOverrideColor and auraMaxStacks and auraHasApplications and SupportsResourceAuraStackMode(100)

    if auraOverrideColor and not useAuraStackMode then
        for i = 1, half do
            if stacks >= i then
                holder.segments[i]:SetStatusBarColor(auraOverrideColor[1], auraOverrideColor[2], auraOverrideColor[3], 1)
            end
            if stacks >= (half + i) then
                holder.overlaySegments[i]:SetStatusBarColor(auraOverrideColor[1], auraOverrideColor[2], auraOverrideColor[3], 1)
            end
        end
    end

    if useAuraStackMode then
        ApplyResourceAuraStackSegments(holder, settings, auraApplications, auraMaxStacks, auraOverrideColor)
    else
        HideResourceAuraStackSegments(holder)
    end

    SetSegmentedText(holder, stacks, mwMaxStacks)
end

------------------------------------------------------------------------
-- Update logic: Custom aura bars (aura-based, secret-safe)
------------------------------------------------------------------------

local function ResolveCustomBarPandemicState(frame, configUnit, auraPresent, viewerFrame, pandemicPreview)
    if not frame then
        return false
    end

    if pandemicPreview then
        return true
    end

    if configUnit == "target" and auraPresent and viewerFrame then
        local pi = viewerFrame.PandemicIcon
        if frame._pandemicGraceSuppressed then
            frame._pandemicGraceSuppressed = nil
            frame._pandemicGraceStart = nil
        elseif pi and pi:IsVisible() then
            frame._pandemicGraceStart = nil
            return true
        elseif frame._inPandemic then
            local now = GetTime()
            if not frame._pandemicGraceStart then
                frame._pandemicGraceStart = now
            end
            if now - frame._pandemicGraceStart <= 0.3 then
                return true
            end
            frame._pandemicGraceStart = nil
        end
    else
        frame._pandemicGraceStart = nil
        frame._pandemicGraceSuppressed = nil
    end

    return false
end

local function ResolveCustomAuraVisibility(cabConfig, auraPresent, inPandemic, auraPreview, pandemicPreview)
    if not (cabConfig and (cabConfig.hideWhenInactive or cabConfig.hideWhileAuraActive)) then
        return true, false
    end

    local hideWhileAuraActive = cabConfig.hideWhileAuraActive == true
        and cabConfig.hideWhenInactive ~= true
        and auraPresent
        and not (cabConfig.hideAuraActiveExceptPandemic == true and inPandemic)
    local hideWhileAuraNotActive = cabConfig.hideWhenInactive == true and not auraPresent
    local shouldShow = not (hideWhileAuraActive or hideWhileAuraNotActive)
        or auraPreview
        or pandemicPreview

    return shouldShow, true
end

function RB.RequestCustomBarPresentationRefresh()
    if RB.customBarPresentationRefreshPending then
        return
    end

    RB.customBarPresentationRefreshPending = true
    C_Timer.After(0, function()
        RB.customBarPresentationRefreshPending = nil
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
    end)
end

local function UpdateCustomAuraBar(barInfo)
    local cabConfig = barInfo.cabConfig
    if not cabConfig or not cabConfig.spellID then return end

    -- Read aura data from viewer frame (applications may be secret in combat)
    local spellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
    local auraState = spellAuraStackDisplay and RB.ResolveSpellCustomBarAuraState and RB.ResolveSpellCustomBarAuraState(barInfo) or nil
    local stacks = 0
    local applications = 0
    local auraPresent = false
    local durationObj
    local isActive = cabConfig.trackingMode == "active"
    local useDrain = isActive
    local needsDuration = (useDrain or cabConfig.showDurationText) and not spellAuraStackDisplay
    local bar = barInfo.barType == "custom_continuous" and barInfo.frame or nil
    local auraPreview = bar and bar._barAuraActivePreview
    local pandemicPreview = bar and bar._pandemicPreview
    local indicatorPreview = isActive and (auraPreview or pandemicPreview)
    local configUnit = EnsureCustomAuraBarAuraUnit(cabConfig, cabConfig.spellID)
    local viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(cabConfig.spellID)
    local auraUnit = configUnit
    local instId = viewerFrame and viewerFrame.auraInstanceID

    if spellAuraStackDisplay then
        configUnit = (auraState and auraState.configUnit) or configUnit
        viewerFrame = auraState and auraState.viewerFrame or nil
        if auraState and auraState.ready == true and auraState.auraPresent == true and auraState.auraData then
            auraPresent = true
            instId = auraState.auraInstanceID
            auraUnit = auraState.auraUnit or configUnit
            applications = auraState.auraData.applications or 0
            stacks = applications
        end
    elseif instId then
        local viewerUnit = viewerFrame.auraDataUnit or configUnit
        if viewerUnit == configUnit then
            local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(configUnit, instId)
            if auraData then
                auraPresent = true
                applications = auraData.applications or 0
                if isActive then
                    stacks = 1
                else
                    stacks = applications
                end
                if needsDuration then
                    durationObj = C_UnitAuras.GetAuraDuration(configUnit, instId)
                end
            end
        end
    end

    if not spellAuraStackDisplay and not auraPresent and configUnit == "player" then
        local auraData = C_UnitAuras.GetPlayerAuraBySpellID(cabConfig.spellID)
        if auraData then
            instId = auraData.auraInstanceID
            auraUnit = "player"
            auraPresent = true
            applications = auraData.applications or 0
            if isActive then
                stacks = 1
            else
                stacks = applications
            end
            if needsDuration and instId then
                durationObj = C_UnitAuras.GetAuraDuration("player", instId)
            end
        end
    end

    if spellAuraStackDisplay and not auraPresent and not isPreviewActive then
        if CooldownCompanion.UpdateCustomBarSoundAlerts then
            CooldownCompanion:UpdateCustomBarSoundAlerts(barInfo, false)
        end
        RB.RequestCustomBarPresentationRefresh()
        return
    end

    local soundAuraActive = auraPresent
    if indicatorPreview and not auraPresent then
        auraPresent = true
        applications = CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS
        stacks = 1
    end

    if CooldownCompanion.UpdateCustomBarSoundAlerts then
        CooldownCompanion:UpdateCustomBarSoundAlerts(barInfo, soundAuraActive)
    end

    local pandemicStateFrame = barInfo.frame
    local inPandemic = ResolveCustomBarPandemicState(pandemicStateFrame, configUnit, auraPresent, viewerFrame, pandemicPreview)

    if isActive and bar then
        if auraPresent then
            bar._auraInstanceID = instId
            bar._auraUnit = auraUnit
        else
            bar._auraInstanceID = nil
            bar._auraUnit = nil
        end

        bar._inPandemic = inPandemic or nil
    elseif pandemicStateFrame then
        pandemicStateFrame._inPandemic = inPandemic or nil
    end

    local shouldShow, hasVisibilityRule = ResolveCustomAuraVisibility(cabConfig, auraPresent, inPandemic, auraPreview, pandemicPreview)
    if spellAuraStackDisplay and auraState and auraState.ready ~= true then
        hasVisibilityRule = false
        shouldShow = true
    end
    if hasVisibilityRule then
        local wasShown = barInfo.frame:IsShown()
        barInfo.frame:SetShown(shouldShow)
        if wasShown ~= shouldShow then
            layoutDirty = true
        end
        if not shouldShow then
            if isActive then
                UpdateCustomAuraBarIndicatorVisuals(barInfo, cabConfig, false)
            end
            return
        end
    end

    local maxStacks = cabConfig.maxStacks or 1
    local thresholdEnabled = (not spellAuraStackDisplay) and IsCustomAuraMaxThresholdEnabled(cabConfig)

    if barInfo.barType == "custom_continuous" then
        local bar = barInfo.frame
        if useDrain then
            bar:SetMinMaxValues(0, 1)
            if durationObj then
                bar:SetValue(durationObj:GetRemainingPercent())  -- secret-safe, 1->0 drain
            elseif indicatorPreview then
                bar:SetValue(CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL)
            else
                -- No DurationObject (indefinite aura or aura absent)
                bar:SetValue(stacks)  -- 1 if active (full), 0 if absent (empty)
            end
        else
            bar:SetMinMaxValues(0, maxStacks)
            bar:SetValue(stacks)  -- SetValue accepts secrets
        end

        if bar.thresholdOverlay then
            if thresholdEnabled then
                SetCustomAuraMaxThresholdRange(bar.thresholdOverlay, maxStacks)
                bar.thresholdOverlay:SetValue(stacks)
                bar.thresholdOverlay:Show()
            else
                bar.thresholdOverlay:SetValue(0)
                bar.thresholdOverlay:Hide()
            end
        end

        -- Duration text (bar.text): driven by showDurationText, independent of drain
        if bar.text and bar.text:IsShown() then
            if durationObj then
                local remaining = durationObj:GetRemainingDuration()
                if not durationObj:HasSecretValues() then
                    if remaining > 0 then
                        bar.text:SetText(FormatTime(remaining, cabConfig))
                    else
                        bar.text:SetText("")
                    end
                else
                    bar.text:SetFormattedText(GetDurationSecretFormatSpec(cabConfig), remaining)
                end
            elseif indicatorPreview then
                bar.text:SetText(FormatTime(CUSTOM_AURA_BAR_EFFECT_PREVIEW_DURATION, cabConfig))
            else
                bar.text:SetText("")
            end
        end

        -- Stack text (bar.stackText): driven by showStackText
        if bar.stackText and bar.stackText:IsShown() then
            if auraPresent then
                if isActive then
                    bar.stackText:SetFormattedText("%d", applications)
                else
                    local stackTextFormat = NormalizeCustomAuraStackTextFormat(cabConfig.stackTextFormat)
                    if stackTextFormat == "current" then
                        bar.stackText:SetFormattedText("%d", stacks)
                    else
                        bar.stackText:SetFormattedText("%d / %d", stacks, maxStacks)
                    end
                end
            else
                bar.stackText:SetText("")
            end
        end

        if isActive then
            UpdateCustomAuraBarIndicatorVisuals(barInfo, cabConfig, auraPresent)
        else
            ClearCustomAuraBarIndicatorState(barInfo, true)
        end

    elseif barInfo.barType == "custom_segmented" then
        local holder = barInfo.frame
        if not holder.segments then return end
        -- Each segment has MinMax(i-1, i) — SetValue(stacks) with C-level clamping
        -- handles fill/empty without comparing the secret stacks value in Lua
        for i = 1, #holder.segments do
            holder.segments[i]:SetValue(stacks)
        end

        if holder.thresholdSegments then
            for i = 1, #holder.thresholdSegments do
                local thresholdSeg = holder.thresholdSegments[i]
                if thresholdEnabled then
                    SetCustomAuraMaxThresholdRange(thresholdSeg, maxStacks)
                    thresholdSeg:SetValue(stacks)
                    thresholdSeg:Show()
                else
                    thresholdSeg:SetValue(0)
                    thresholdSeg:Hide()
                end
            end
        end

    elseif barInfo.barType == "custom_overlay" then
        local holder = barInfo.frame
        if not holder.segments then return end
        local half = barInfo.halfSegments or 1

        -- Pass stacks to ALL segments (StatusBar C-level clamping handles per-segment fill)
        for i = 1, half do
            holder.segments[i]:SetValue(stacks)
            holder.overlaySegments[i]:SetValue(stacks)
        end

        if holder.thresholdSegments then
            for i = 1, half do
                local thresholdSeg = holder.thresholdSegments[i]
                if thresholdEnabled then
                    SetCustomAuraMaxThresholdRange(thresholdSeg, maxStacks)
                    thresholdSeg:SetValue(stacks)
                    thresholdSeg:Show()
                else
                    thresholdSeg:SetValue(0)
                    thresholdSeg:Hide()
                end
            end
        end
    end

    -- Max stacks indicator: SetValue drives visibility via C-level clamping
    if cabConfig.maxStacksGlowEnabled and barInfo._maxStacksIndicator then
        barInfo._maxStacksIndicator:SetValue(auraPresent and applications or 0)
    end
end

local function BuildSpellCustomBarAuraButtonData(cabConfig)
    local spellID = tonumber(cabConfig and cabConfig.spellID)
    if not spellID or not (cabConfig and cabConfig.auraTracking == true) then
        return nil, nil
    end

    return {
        type = "spell",
        id = spellID,
        auraSpellID = cabConfig.auraSpellID,
        auraTracking = true,
        auraUnit = GetResolvedCustomAuraBarAuraUnit(cabConfig, spellID),
    }, spellID
end

local function GetSpellCustomBarParsedAuraIDs(bar, cabConfig, spellID)
    if not (bar and cabConfig and cabConfig.auraSpellID) then
        return nil, false
    end

    local rawIDs = tostring(cabConfig.auraSpellID)
    if bar._parsedCustomBarAuraIDsRaw == rawIDs
        and bar._parsedCustomBarAuraIDsSpellID == spellID then
        return bar._parsedCustomBarAuraIDs, bar._parsedCustomBarAuraIDsIncludeSpellID == true
    end

    local ids = {}
    local includesSpellID = false
    for id in rawIDs:gmatch("%d+") do
        local numericID = tonumber(id)
        ids[#ids + 1] = numericID
        if numericID == spellID then
            includesSpellID = true
        end
    end

    bar._parsedCustomBarAuraIDs = ids
    bar._parsedCustomBarAuraIDsRaw = rawIDs
    bar._parsedCustomBarAuraIDsSpellID = spellID
    bar._parsedCustomBarAuraIDsIncludeSpellID = includesSpellID or nil
    return ids, includesSpellID
end

local function ResolveSpellCustomBarPlayerAuraData(bar, cabConfig, spellID, resolvedAuraSpellID)
    local auraData
    if cabConfig.auraSpellID then
        local ids, includesSpellID = GetSpellCustomBarParsedAuraIDs(bar, cabConfig, spellID)
        if ids then
            for _, auraID in ipairs(ids) do
                auraData = C_UnitAuras.GetPlayerAuraBySpellID(auraID)
                if auraData then
                    return auraData
                end
            end
        end
        if not includesSpellID then
            local baseID = C_Spell.GetBaseSpell(spellID)
            local fallbackID = baseID and baseID ~= resolvedAuraSpellID and baseID or nil
            return fallbackID and C_UnitAuras.GetPlayerAuraBySpellID(fallbackID) or nil
        end
        return nil
    end

    local baseID = C_Spell.GetBaseSpell(spellID)
    local fallbackID = baseID and baseID ~= resolvedAuraSpellID and baseID or nil
    auraData = fallbackID and C_UnitAuras.GetPlayerAuraBySpellID(fallbackID) or nil
    if auraData then
        return auraData
    end

    return resolvedAuraSpellID and C_UnitAuras.GetPlayerAuraBySpellID(resolvedAuraSpellID) or nil
end

local function ViewerFrameHasAuraForUnit(viewerFrame, configUnit)
    local instId = viewerFrame and viewerFrame.auraInstanceID
    if not instId then
        return false
    end

    local viewerUnit = viewerFrame.auraDataUnit or configUnit
    return viewerUnit == configUnit
        and C_UnitAuras.GetAuraDataByAuraInstanceID(viewerUnit, instId) ~= nil
end

local function ResolveSpellCustomBarAuraViewerFrame(bar, cabConfig, spellID, buttonData, configUnit)
    if cabConfig and cabConfig.auraSpellID then
        local ids = GetSpellCustomBarParsedAuraIDs(bar, cabConfig, spellID)
        local firstTrackedFrame
        if ids then
            for _, auraID in ipairs(ids) do
                local viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(auraID)
                if viewerFrame then
                    if ViewerFrameHasAuraForUnit(viewerFrame, configUnit) then
                        return viewerFrame
                    end
                    if not firstTrackedFrame then
                        firstTrackedFrame = viewerFrame
                    end
                end
            end
        end
        if firstTrackedFrame then
            return firstTrackedFrame
        end
    end

    return CooldownCompanion:ResolveButtonAuraViewerFrame(buttonData)
end

local function SpellCustomBarAuraDataMatches(bar, cabConfig, spellID, resolvedAuraSpellID, auraData)
    local auraSpellID = auraData and auraData.spellId
    if not auraSpellID or (issecretvalue and issecretvalue(auraSpellID)) then
        return false
    end

    if cabConfig and cabConfig.auraSpellID then
        local ids = GetSpellCustomBarParsedAuraIDs(bar, cabConfig, spellID)
        if ids then
            for _, auraID in ipairs(ids) do
                if auraSpellID == auraID then
                    return true
                end
            end
        end
    end

    local baseID = C_Spell.GetBaseSpell(spellID)
    return auraSpellID == resolvedAuraSpellID
        or auraSpellID == spellID
        or (baseID and auraSpellID == baseID)
end

function RB.ResolveSpellCustomBarAuraState(barInfo)
    local cabConfig = barInfo and barInfo.cabConfig
    local bar = barInfo and barInfo.frame
    local buttonData, spellID = BuildSpellCustomBarAuraButtonData(cabConfig)
    if not (buttonData and spellID and bar) then
        return nil
    end

    local cdmEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
    local configUnit = buttonData.auraUnit or "player"
    local viewerFrame = ResolveSpellCustomBarAuraViewerFrame(bar, cabConfig, spellID, buttonData, configUnit)
    if not CooldownCompanion:IsAuraTrackingReady(buttonData, cdmEnabled, viewerFrame) then
        return {
            ready = false,
            auraPresent = false,
            configUnit = configUnit,
            viewerFrame = viewerFrame,
        }
    end

    local resolvedAuraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    local auraData
    local durationObj
    local auraUnit = configUnit
    local instId = viewerFrame and viewerFrame.auraInstanceID

    if instId and (configUnit == "player" or configUnit == "target") then
        local viewerUnit = viewerFrame.auraDataUnit or configUnit
        if viewerUnit == configUnit then
            auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(viewerUnit, instId)
            if auraData then
                durationObj = C_UnitAuras.GetAuraDuration(viewerUnit, instId)
                if durationObj then
                    auraUnit = viewerUnit
                end
            end
        end
    end

    if not (auraData and durationObj) and configUnit == "player" then
        auraData = ResolveSpellCustomBarPlayerAuraData(bar, cabConfig, spellID, resolvedAuraSpellID)
        instId = auraData and auraData.auraInstanceID or nil
        if instId and not issecretvalue(instId) then
            durationObj = C_UnitAuras.GetAuraDuration("player", instId)
            auraUnit = "player"
        end
    end

    if not (auraData and durationObj) and configUnit == "player" and bar._auraInstanceID then
        local cachedUnit = bar._auraUnit or configUnit
        if cachedUnit == configUnit then
            auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(cachedUnit, bar._auraInstanceID)
            if SpellCustomBarAuraDataMatches(bar, cabConfig, spellID, resolvedAuraSpellID, auraData) then
                durationObj = C_UnitAuras.GetAuraDuration(cachedUnit, bar._auraInstanceID)
                instId = bar._auraInstanceID
                auraUnit = cachedUnit
            end
        end
    end

    if not auraData then
        return {
            ready = true,
            auraPresent = false,
            configUnit = configUnit,
            viewerFrame = viewerFrame,
        }
    end

    return {
        ready = true,
        auraPresent = true,
        auraData = auraData,
        auraInstanceID = instId,
        auraUnit = auraUnit,
        configUnit = configUnit,
        viewerFrame = viewerFrame,
        durationObj = durationObj,
    }
end

local function ClearSpellCustomBarAuraRuntimeState(barInfo)
    ClearCustomAuraBarIndicatorState(barInfo, false)
end

local function UpdateSpellCustomBarChargeText(bar, cooldownResult)
    if not (bar and bar.stackText and bar.stackText:IsShown()) then
        return
    end

    local currentCharges = cooldownResult and cooldownResult.currentCharges
    local maxCharges = cooldownResult and cooldownResult.maxCharges
    if currentCharges and maxCharges and maxCharges > 1 then
        bar.stackText:SetFormattedText("%d / %d", currentCharges, maxCharges)
    else
        bar.stackText:SetText("")
    end
end

function RB.UpdateSpellCustomBarAuraStackText(bar, cabConfig, stacks, maxStacks, auraPresent)
    if not (bar and bar.stackText and bar.stackText:IsShown()) then
        return
    end

    if not auraPresent then
        bar.stackText:SetText("")
        return
    end

    local stackTextFormat = NormalizeCustomAuraStackTextFormat(cabConfig and cabConfig.stackTextFormat)
    if stackTextFormat == "current" then
        bar.stackText:SetFormattedText("%d", stacks)
    else
        bar.stackText:SetFormattedText("%d / %d", stacks, maxStacks)
    end
end

function RB.UpdateCustomCooldownBar(barInfo)
    local cabConfig = barInfo and barInfo.cabConfig
    local bar = barInfo and barInfo.frame
    if not (cabConfig and cabConfig.spellID and bar) then return end

    local cooldownResult = CooldownCompanion.EvaluateSpellCooldownStateForCustomBar
        and CooldownCompanion:EvaluateSpellCooldownStateForCustomBar(cabConfig)
    local durationObj = cooldownResult and cooldownResult.renderDurationObj
    local cooldownActive = cooldownResult
        and cooldownResult.state == ST.CooldownLogic.STATE_COOLDOWN
    local auraState = RB.ResolveSpellCustomBarAuraState(barInfo)
    local auraPresent = auraState and auraState.ready == true and auraState.auraPresent == true
    local auraPreview = bar._barAuraActivePreview == true
    local pandemicPreview = bar._pandemicPreview == true
    local spellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
    local renderAuraState = cabConfig.auraTracking == true
        and not spellAuraStackDisplay
        and (auraPresent or auraPreview or pandemicPreview)

    local barColor = cabConfig.barColor or {0.5, 0.5, 1, 1}
    local cooldownColor = cabConfig.barCooldownColor or {0.6, 0.13, 0.18, 1}
    local rechargeColor = cabConfig.barChargeColor or {1.0, 0.82, 0.0, 1}
    local chargeState = cooldownResult and cooldownResult.chargeState
    local fillColor = barColor
    if cooldownResult and cooldownResult.hasCharges == true then
        if chargeState == ST.CooldownLogic.CHARGE_STATE_ZERO then
            fillColor = cooldownColor
        elseif cooldownActive then
            fillColor = rechargeColor
        end
    elseif cooldownActive then
        fillColor = cooldownColor
    end

    local function UpdateSpellCustomBarSounds(soundAuraActive)
        if CooldownCompanion.UpdateCustomBarSoundAlerts then
            local soundCooldownActive = cooldownActive
            if cooldownResult and cooldownResult.hasCharges == true then
                soundCooldownActive = cooldownResult.chargeState == ST.CooldownLogic.CHARGE_STATE_ZERO
                    or (cooldownResult.chargeState == nil and cooldownActive)
            end
            CooldownCompanion:UpdateCustomBarSoundAlerts(barInfo, soundAuraActive, soundCooldownActive, cooldownResult)
        end
    end

    local configUnit = (auraState and auraState.configUnit)
        or GetResolvedCustomAuraBarAuraUnit(cabConfig, cabConfig.spellID)
    local inPandemic = ResolveCustomBarPandemicState(
        bar,
        configUnit,
        auraPresent,
        auraState and auraState.viewerFrame,
        pandemicPreview
    )

    if auraState
        and auraState.ready == true
        and (cabConfig.hideWhenInactive or cabConfig.hideWhileAuraActive) then
        local shouldShow = ResolveCustomAuraVisibility(cabConfig, auraPresent, inPandemic, auraPreview, pandemicPreview)
        local wasShown = bar:IsShown()
        bar:SetShown(shouldShow)
        if wasShown ~= shouldShow then
            layoutDirty = true
        end
        if not shouldShow then
            ClearSpellCustomBarAuraRuntimeState(barInfo)
            UpdateSpellCustomBarSounds(auraPresent)
            return
        end
    elseif (cabConfig.hideWhenInactive or cabConfig.hideWhileAuraActive)
        and not bar:IsShown() then
        bar:Show()
        layoutDirty = true
    end

    if spellAuraStackDisplay and auraPresent then
        UpdateSpellCustomBarSounds(true)
        RB.RequestCustomBarPresentationRefresh()
        return
    end

    if renderAuraState then
        if auraPresent then
            bar._auraActive = true
            bar._auraInstanceID = auraState.auraInstanceID
            bar._auraUnit = auraState.auraUnit
        else
            bar._auraActive = true
            bar._auraInstanceID = nil
            bar._auraUnit = nil
        end
        bar._inPandemic = inPandemic or nil

        local auraDurationObj = auraState and auraState.durationObj
        bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4] ~= nil and barColor[4] or 1)
        bar:SetMinMaxValues(0, 1)
        if auraDurationObj then
            bar:SetValue(auraDurationObj:GetRemainingPercent())
        elseif auraPreview or pandemicPreview then
            bar:SetValue(CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL)
        else
            bar:SetValue(1)
        end

        if bar.thresholdOverlay then
            bar.thresholdOverlay:SetValue(0)
            bar.thresholdOverlay:Hide()
        end

        if bar.text and bar.text:IsShown() then
            if auraDurationObj then
                local remaining = auraDurationObj:GetRemainingDuration()
                if auraDurationObj:HasSecretValues() then
                    bar.text:SetFormattedText(GetDurationSecretFormatSpec(cabConfig), remaining)
                elseif remaining and remaining > 0 then
                    bar.text:SetText(FormatTime(remaining, cabConfig))
                else
                    bar.text:SetText("")
                end
            elseif auraPreview or pandemicPreview then
                bar.text:SetText(FormatTime(CUSTOM_AURA_BAR_EFFECT_PREVIEW_DURATION, cabConfig))
            else
                bar.text:SetText("")
            end
        end

        UpdateSpellCustomBarChargeText(bar, cooldownResult)
        UpdateCustomAuraBarIndicatorVisuals(barInfo, cabConfig, auraPresent)

        if barInfo._maxStacksIndicator then
            barInfo._maxStacksIndicator:SetValue(0)
        end

        UpdateSpellCustomBarSounds(auraPresent)
        return
    end

    ClearSpellCustomBarAuraRuntimeState(barInfo)

    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4] ~= nil and fillColor[4] or 1)
    if cooldownActive and durationObj then
        bar:SetValue(durationObj:GetElapsedPercent())
    elseif cooldownActive then
        bar:SetValue(0)
    else
        bar:SetValue(1)
    end

    if bar.thresholdOverlay then
        bar.thresholdOverlay:SetValue(0)
        bar.thresholdOverlay:Hide()
    end

    if bar.text and bar.text:IsShown() then
        if cooldownActive and durationObj then
            local remaining = durationObj:GetRemainingDuration()
            if durationObj:HasSecretValues() then
                bar.text:SetFormattedText(GetDurationSecretFormatSpec(cabConfig), remaining)
            elseif remaining and remaining > 0 then
                bar.text:SetText(FormatTime(remaining, cabConfig))
            else
                bar.text:SetText("")
            end
        else
            bar.text:SetText("")
        end
    end

    UpdateSpellCustomBarChargeText(bar, cooldownResult)

    if barInfo._maxStacksIndicator then
        barInfo._maxStacksIndicator:SetValue(0)
    end

    UpdateSpellCustomBarSounds(false)
end

local function GetHiddenCustomAuraWakeUnit(cabConfig)
    if not cabConfig or not cabConfig.spellID then
        return nil
    end
    return EnsureCustomAuraBarAuraUnit(cabConfig, cabConfig.spellID)
end

local function IsEventDrivenCustomAuraBar(barInfo)
    return barInfo
        and (barInfo.barType == "custom_segmented"
            or barInfo.barType == "custom_overlay"
            or barInfo.barType == "custom_cooldown")
end

local function ShouldUpdateHiddenCustomAuraPandemicWake(barInfo)
    local frame = barInfo and barInfo.frame
    local cabConfig = barInfo and barInfo.cabConfig
    if not (frame and cabConfig) then
        return false
    end
    if frame:IsShown() then
        return false
    end
    if cabConfig.hideWhileAuraActive ~= true
        or cabConfig.hideWhenInactive == true
        or cabConfig.hideAuraActiveExceptPandemic ~= true then
        return false
    end

    local isTrackedSpellBar = barInfo.barType == "custom_cooldown"
        and cabConfig.auraTracking == true
    local isActiveAuraBar = barInfo.barType == "custom_continuous"
        and cabConfig.trackingMode == "active"
    if not (isTrackedSpellBar or isActiveAuraBar) then
        return false
    end

    return GetResolvedCustomAuraBarAuraUnit(cabConfig, cabConfig.spellID) == "target"
end

local function StopDeferredCustomAuraWakeRetryFrame()
    if customAuraWakeRetryFrame then
        customAuraWakeRetryFrame:SetScript("OnUpdate", nil)
    end
end

local function ClearDeferredCustomAuraWakeRetries()
    wipe(customAuraWakeRetryQueue)
    wipe(customAuraWakeRetryPending)
    processingCustomAuraWakeRetryQueue = false
    StopDeferredCustomAuraWakeRetryFrame()
end

local RelayoutBars
local RelayoutResourceStack

local function ResolveDeferredCustomAuraWakeRetryBarInfo(entry)
    if not entry or not entry.customBarId or not entry.cabConfig then
        return nil
    end

    -- ApplyResourceBars() can recreate the custom aura bar before the next-frame
    -- retry fires, so re-resolve the active barInfo instead of trusting the
    -- captured table/frame from queue time.
    for _, candidate in ipairs(resourceBarFrames) do
        if candidate
            and candidate.customBarId == entry.customBarId
            and candidate.cabConfig == entry.cabConfig then
            return candidate
        end
    end

    return nil
end

local function ProcessDeferredCustomAuraWakeRetries()
    if processingCustomAuraWakeRetryQueue then return end
    if #customAuraWakeRetryQueue == 0 then
        StopDeferredCustomAuraWakeRetryFrame()
        return
    end

    processingCustomAuraWakeRetryQueue = true
    local queue = customAuraWakeRetryQueue
    customAuraWakeRetryQueue = {}
    customAuraWakeRetryPending = {}

    local relayoutNeeded = false
    for _, entry in ipairs(queue) do
        local barInfo = ResolveDeferredCustomAuraWakeRetryBarInfo(entry)
        local frame = barInfo and barInfo.frame
        local cabConfig = barInfo and barInfo.cabConfig
        if barInfo
            and frame
            and cabConfig
            and barInfo.cabConfig == entry.cabConfig
            and IsEventDrivenCustomAuraBar(barInfo)
            and (cabConfig.hideWhenInactive == true or cabConfig.hideWhileAuraActive == true)
            and GetHiddenCustomAuraWakeUnit(cabConfig) == entry.unit
            and not frame:IsShown()
        then
            if barInfo.barType == "custom_cooldown" then
                RB.UpdateCustomCooldownBar(barInfo)
            else
                UpdateCustomAuraBar(barInfo)
            end
            if frame:IsShown() then
                relayoutNeeded = true
            end
        end
    end

    processingCustomAuraWakeRetryQueue = false
    StopDeferredCustomAuraWakeRetryFrame()

    if relayoutNeeded then
        RelayoutResourceStack()
    end
end

local function QueueDeferredCustomAuraWakeRetry(barInfo, unit)
    if processingCustomAuraWakeRetryQueue then return end
    if unit ~= "player" and unit ~= "target" then return end
    if not IsEventDrivenCustomAuraBar(barInfo) then return end

    local frame = barInfo and barInfo.frame
    local cabConfig = barInfo and barInfo.cabConfig
    local customBarId = barInfo and barInfo.customBarId
    if not frame
        or not cabConfig
        or not customBarId
        or not (cabConfig.hideWhenInactive == true or cabConfig.hideWhileAuraActive == true) then
        return
    end
    if frame:IsShown() then return end
    if GetHiddenCustomAuraWakeUnit(cabConfig) ~= unit then return end
    if customAuraWakeRetryPending[cabConfig] then return end

    customAuraWakeRetryPending[cabConfig] = true
    customAuraWakeRetryQueue[#customAuraWakeRetryQueue + 1] = {
        cabConfig = cabConfig,
        customBarId = customBarId,
        unit = unit,
    }

    if not customAuraWakeRetryFrame then
        customAuraWakeRetryFrame = CreateFrame("Frame")
    end
    customAuraWakeRetryFrame:SetScript("OnUpdate", function(self, _elapsed)
        self:SetScript("OnUpdate", nil)
        ProcessDeferredCustomAuraWakeRetries()
    end)
end

local function RefreshEventDrivenCustomAuraBarsForUnit(unit)
    if unit ~= "player" and unit ~= "target" then return end

    for _, barInfo in ipairs(resourceBarFrames) do
        local frame = barInfo and barInfo.frame
        local cabConfig = barInfo and barInfo.cabConfig
        local shouldRefresh = frame and (
            IsEventDrivenCustomAuraBar(barInfo)
            or (not frame:IsShown()
                and cabConfig
                and (cabConfig.hideWhenInactive or cabConfig.hideWhileAuraActive))
        )
        if shouldRefresh
            and cabConfig
            and (barInfo.barType == "custom_continuous"
                or barInfo.barType == "custom_segmented"
                or barInfo.barType == "custom_overlay"
                or barInfo.barType == "custom_cooldown")
            and GetHiddenCustomAuraWakeUnit(cabConfig) == unit then
            local wasShown = frame:IsShown()
            if barInfo.barType == "custom_cooldown" then
                RB.UpdateCustomCooldownBar(barInfo)
            else
                UpdateCustomAuraBar(barInfo)
            end
            if not wasShown and not frame:IsShown() then
                QueueDeferredCustomAuraWakeRetry(barInfo, unit)
            end
        end
    end
end

------------------------------------------------------------------------
-- Styling: Custom aura bars
------------------------------------------------------------------------

local function StyleCustomAuraBar(barInfo, cabConfig)
    local barColor = cabConfig.barColor or {0.5, 0.5, 1}
    local isSpellCustomBar = RB.IsSpellCustomBarConfig(cabConfig)
    local thresholdEnabled = (not isSpellCustomBar) and IsCustomAuraMaxThresholdEnabled(cabConfig)
    local thresholdColor = GetCustomAuraMaxThresholdColor(cabConfig)

    if barInfo.barType == "custom_continuous" or barInfo.barType == "custom_cooldown" then
        local bar = barInfo.frame
        bar.style = cabConfig
        local isVertical = bar._isVertical == true
        bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
        if bar.thresholdOverlay then
            bar.thresholdOverlay:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], 1)
            bar.thresholdOverlay:SetShown(thresholdEnabled)
        end

        -- Determine visibility for both text elements
        local spellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
        local spellAuraStackActive = spellAuraStackDisplay and barInfo.barType ~= "custom_cooldown"
        local isActive = isSpellCustomBar and not spellAuraStackActive
            or ((not isSpellCustomBar) and cabConfig.trackingMode == "active")
        local showDuration = cabConfig.showDurationText == true and not spellAuraStackActive
        local showStack = cabConfig.showStackText
        if isSpellCustomBar then
            showStack = showStack == true
        elseif showStack == nil then
            -- Backwards compat: fall back to showText for stacks mode
            if not isActive then
                showStack = cabConfig.showText == true
            else
                showStack = false
            end
        end

        -- Duration text (bar.text)
        if bar.text then
            bar.text:SetShown(showDuration)
            if showDuration then
                bar.text:ClearAllPoints()
                if showStack then
                    if isVertical then
                        bar.text:SetPoint("BOTTOM", bar, "BOTTOM", 0, 2)
                    else
                        bar.text:SetPoint("LEFT", bar, "LEFT", 4, 0)
                    end
                else
                    bar.text:SetPoint("CENTER")
                end
            end
        end

        -- Stack text (bar.stackText)
        if bar.stackText then
            bar.stackText:SetShown(showStack)
            if showStack then
                bar.stackText:ClearAllPoints()
                if showDuration then
                    if isVertical then
                        bar.stackText:SetPoint("TOP", bar, "TOP", 0, -2)
                    else
                        bar.stackText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
                    end
                else
                    bar.stackText:SetPoint("CENTER")
                end
            end
        end

    elseif barInfo.barType == "custom_segmented" then
        local holder = barInfo.frame
        if holder.segments then
            for _, seg in ipairs(holder.segments) do
                seg:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
            end
        end
        if holder.thresholdSegments then
            for _, seg in ipairs(holder.thresholdSegments) do
                seg:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], 1)
                seg:SetShown(thresholdEnabled)
            end
        end

    elseif barInfo.barType == "custom_overlay" then
        local holder = barInfo.frame
        local overlayColor = cabConfig.overlayColor or {1, 0.84, 0}
        local half = barInfo.halfSegments or 1
        if holder.segments then
            for i = 1, half do
                holder.segments[i]:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
                holder.overlaySegments[i]:SetStatusBarColor(overlayColor[1], overlayColor[2], overlayColor[3], 1)
                holder.overlaySegments[i]:Show()
                if holder.thresholdSegments and holder.thresholdSegments[i] then
                    holder.thresholdSegments[i]:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], 1)
                    holder.thresholdSegments[i]:SetShown(thresholdEnabled)
                end
            end
        end
    end
end

local function FinalizeAppliedBarVisibility(barInfo, powerType, previewActive)
    if barInfo and type(barInfo.customBarId) == "string" then
        if previewActive then
            barInfo.frame:Show()
        elseif barInfo.cabConfig
            and (barInfo.cabConfig.hideWhenInactive or barInfo.cabConfig.hideWhileAuraActive) then
            if barInfo.barType == "custom_cooldown" then
                RB.UpdateCustomCooldownBar(barInfo)
            else
                UpdateCustomAuraBar(barInfo)
            end
        else
            barInfo.frame:Show()
            if barInfo.barType == "custom_cooldown" then
                RB.UpdateCustomCooldownBar(barInfo)
            else
                UpdateCustomAuraBar(barInfo)
            end
        end
    else
        barInfo.frame:Show()
    end
end

local function HideUnusedResourceBarFrames(firstHiddenIndex)
    for i = firstHiddenIndex, #resourceBarFrames do
        local barInfo = resourceBarFrames[i]
        if barInfo and barInfo.frame then
            ClearStaleRecycledBarRuntimeState(barInfo.frame)
            ClearCustomAuraBarIndicatorState(barInfo, true)
            ClearResourceAuraVisuals(barInfo.frame)
            ClearMaxStacksIndicator(barInfo)
            barInfo.frame:Hide()
            barInfo.cabConfig = nil
            barInfo.powerType = nil
            barInfo.customBarId = nil
            barInfo.customBarIndex = nil
            barInfo._sndInitialized = nil
            barInfo._sndPrevAuraActive = nil
            barInfo._sndPrevCooldownActive = nil
            barInfo._sndPrevCharges = nil
            barInfo._sndPrevChargeRecharging = nil
            barInfo._sndPrevChargeCooldownStart = nil
            barInfo._side = nil
            barInfo._order = nil
            barInfo._effectiveThickness = nil
            if barInfo.frame.brightnessOverlay then
                barInfo.frame.brightnessOverlay:Hide()
            end
        end
    end
end

local function PrepareCustomAuraBar(
    targetContainer,
    barInfo,
    customEntry,
    customBars,
    settings,
    isVerticalLayout,
    reverseVerticalFill,
    effectiveWidth,
    effectiveHeight,
    segmentGap
)
    local cabIndex
    local cabConfig
    local customBarId
    local legacyPowerType
    if type(customEntry) == "table" then
        cabIndex = customEntry.customBarIndex or customEntry.index
        cabConfig = customEntry.config or (customBars and cabIndex and customBars[cabIndex])
        customBarId = customEntry.customBarId or (cabConfig and cabConfig.customBarId)
    else
        legacyPowerType = customEntry
        cabIndex = legacyPowerType - CUSTOM_AURA_BAR_BASE + 1
        cabConfig = customBars[cabIndex]
        customBarId = cabConfig and cabConfig.customBarId
    end
    if not cabConfig then
        return barInfo
    end
    customBarId = customBarId or RB.EnsureCustomBarId(settings, cabConfig)
    local isSpellCustomBar = RB.IsSpellCustomBarConfig(cabConfig)
    local spellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
    local spellAuraStackPresent = spellAuraStackDisplay and isPreviewActive
    if spellAuraStackDisplay and not spellAuraStackPresent and barInfo and barInfo.frame then
        local auraState = RB.ResolveSpellCustomBarAuraState and RB.ResolveSpellCustomBarAuraState(barInfo) or nil
        spellAuraStackPresent = auraState and auraState.ready == true and auraState.auraPresent == true
    end
    local spellAuraStackActive = spellAuraStackDisplay and spellAuraStackPresent
    local isActive = (isSpellCustomBar and not spellAuraStackActive)
        or ((not isSpellCustomBar) and cabConfig.trackingMode == "active")
    local mode = isSpellCustomBar
        and (spellAuraStackActive and (cabConfig.displayMode or "segmented") or "continuous")
        or (isActive and "continuous" or (cabConfig.displayMode or "segmented"))
    local maxStacks = isActive and 1 or (cabConfig.maxStacks or 1)
    local targetBarType = (isSpellCustomBar and not spellAuraStackActive)
        and "custom_cooldown"
        or ("custom_" .. mode)
    local customOrientation = isVerticalLayout and "vertical" or "horizontal"
    local customIsVertical = customOrientation == "vertical"
    local customReverseFill = false
    if customIsVertical then
        customReverseFill = reverseVerticalFill
    end
    local customWidth = effectiveWidth
    local customHeight = effectiveHeight

    local needsRecreate = not barInfo or barInfo.barType ~= targetBarType
    if not needsRecreate and mode == "segmented" then
        needsRecreate = barInfo.frame._numSegments ~= maxStacks
    end
    if not needsRecreate and mode == "overlay" then
        needsRecreate = barInfo.halfSegments ~= math.ceil(maxStacks / 2)
    end

    if needsRecreate then
        if barInfo and barInfo.frame then
            ClearCustomAuraBarIndicatorState(barInfo, true)
            ClearResourceAuraVisuals(barInfo.frame)
            ClearMaxStacksIndicator(barInfo)
            barInfo.frame:Hide()
        end
        if mode == "continuous" then
            local bar = CreateContinuousBar(targetContainer)
            bar:SetMinMaxValues(0, maxStacks)
            barInfo = { frame = bar, barType = targetBarType }
        elseif mode == "segmented" then
            local holder = CreateSegmentedBar(targetContainer, maxStacks)
            for si = 1, maxStacks do
                holder.segments[si]:SetMinMaxValues(si - 1, si)
            end
            barInfo = { frame = holder, barType = "custom_segmented" }
        elseif mode == "overlay" then
            local half = math.ceil(maxStacks / 2)
            local holder = CreateOverlayBar(targetContainer, half)
            barInfo = { frame = holder, barType = "custom_overlay", halfSegments = half }
        end
    end

    if mode == "continuous" then
        EnsureCustomAuraContinuousThresholdOverlay(barInfo.frame)
    elseif mode == "segmented" then
        EnsureCustomAuraSegmentThresholdOverlays(barInfo.frame)
    elseif mode == "overlay" then
        EnsureCustomAuraOverlayThresholdOverlays(barInfo.frame, barInfo.halfSegments or math.ceil(maxStacks / 2))
    end

    if barInfo.customBarId ~= customBarId then
        barInfo._sndInitialized = nil
        barInfo._sndPrevAuraActive = nil
        barInfo._sndPrevCooldownActive = nil
        barInfo._sndPrevCharges = nil
        barInfo._sndPrevChargeRecharging = nil
        barInfo._sndPrevChargeCooldownStart = nil
    end
    barInfo.cabConfig = cabConfig
    barInfo.powerType = legacyPowerType
    barInfo.customBarId = customBarId
    barInfo.customBarIndex = cabIndex
    ApplyCustomAuraBarPreviewState(barInfo)
    barInfo.frame:SetSize(customWidth, customHeight)
    barInfo.frame._isVertical = customIsVertical
    barInfo.frame._reverseFill = customReverseFill
    if mode == "segmented" then
        LayoutSegments(
            barInfo.frame,
            customWidth,
            customHeight,
            segmentGap,
            settings,
            customOrientation,
            customReverseFill
        )
    elseif mode == "overlay" then
        LayoutOverlaySegments(
            barInfo.frame,
            customWidth,
            customHeight,
            segmentGap,
            settings,
            barInfo.halfSegments,
            customOrientation,
            customReverseFill
        )
    end
    if mode == "continuous" then
        local barTextureName = GetResourceDisplayValue(settings, "barTexture", "Solid")
        local barTexture = CooldownCompanion:FetchStatusBar(barTextureName)
        barInfo.frame:SetStatusBarTexture(barTexture)
        barInfo.frame:SetOrientation(customIsVertical and "VERTICAL" or "HORIZONTAL")
        barInfo.frame:SetReverseFill(customIsVertical and customReverseFill or false)
        barInfo.frame._isVertical = customIsVertical
        barInfo.frame._reverseFill = customReverseFill
        local bgc = GetResourceDisplayValue(settings, "backgroundColor", { 0, 0, 0, 0.5 })
        barInfo.frame.bg:ClearAllPoints()
        barInfo.frame.bg:SetAllPoints(barInfo.frame)
        barInfo.frame.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])
        local borderStyle = GetResourceDisplayValue(settings, "borderStyle", "pixel")
        local borderColor = GetResourceDisplayValue(settings, "borderColor", { 0, 0, 0, 1 })
        local borderSize = GetResourceDisplayValue(settings, "borderSize", 1)
        if borderStyle == "pixel" then
            ApplyPixelBorders(barInfo.frame.borders, barInfo.frame, borderColor, borderSize)
        else
            HidePixelBorders(barInfo.frame.borders)
        end
        LayoutCustomAuraContinuousThresholdOverlay(barInfo.frame, barTexture, borderStyle, borderSize)
        local durationTextFontName = cabConfig.durationTextFont or DEFAULT_RESOURCE_TEXT_FONT
        local durationTextSize = tonumber(cabConfig.durationTextFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
        local durationTextOutline = cabConfig.durationTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE
        local durationTextColor = cabConfig.durationTextFontColor or DEFAULT_RESOURCE_TEXT_COLOR
        if type(durationTextColor) ~= "table" or durationTextColor[1] == nil or durationTextColor[2] == nil or durationTextColor[3] == nil then
            durationTextColor = DEFAULT_RESOURCE_TEXT_COLOR
        end
        local durationTextFont = CooldownCompanion:FetchFont(durationTextFontName)
        barInfo.frame.text:SetFont(durationTextFont, durationTextSize, durationTextOutline)
        barInfo.frame.text:SetTextColor(durationTextColor[1], durationTextColor[2], durationTextColor[3], durationTextColor[4] ~= nil and durationTextColor[4] or 1)
        if not barInfo.frame.stackText then
            barInfo.frame.stackText = (barInfo.frame.textLayer or barInfo.frame):CreateFontString(nil, "OVERLAY")
            barInfo.frame.stackText:SetTextColor(1, 1, 1, 1)
        end
        local stackTextFontName = cabConfig.stackTextFont or DEFAULT_RESOURCE_TEXT_FONT
        local stackTextSize = tonumber(cabConfig.stackTextFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
        local stackTextOutline = cabConfig.stackTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE
        local stackTextColor = cabConfig.stackTextFontColor or DEFAULT_RESOURCE_TEXT_COLOR
        if type(stackTextColor) ~= "table" or stackTextColor[1] == nil or stackTextColor[2] == nil or stackTextColor[3] == nil then
            stackTextColor = DEFAULT_RESOURCE_TEXT_COLOR
        end
        local stackTextFont = CooldownCompanion:FetchFont(stackTextFontName)
        barInfo.frame.stackText:SetFont(stackTextFont, stackTextSize, stackTextOutline)
        barInfo.frame.stackText:SetTextColor(stackTextColor[1], stackTextColor[2], stackTextColor[3], stackTextColor[4] ~= nil and stackTextColor[4] or 1)
        barInfo.frame.brightnessOverlay:Hide()
    end
    StyleCustomAuraBar(barInfo, cabConfig)

    if cabConfig.maxStacksGlowEnabled then
        if isSpellCustomBar then
            ClearMaxStacksIndicator(barInfo)
        else
            EnsureMaxStacksIndicator(barInfo)
            local indBorderStyle = GetResourceDisplayValue(settings, "borderStyle", "pixel")
            local indBorderSize = GetResourceDisplayValue(settings, "borderSize", 1)
            local indBarTexture = CooldownCompanion:FetchStatusBar(GetResourceDisplayValue(settings, "barTexture", "Solid"))
            LayoutMaxStacksIndicator(barInfo, cabConfig, maxStacks, indBarTexture, indBorderStyle, indBorderSize)
        end
    else
        ClearMaxStacksIndicator(barInfo)
    end

    return barInfo
end

RB.PrepareCustomAuraBar = PrepareCustomAuraBar

------------------------------------------------------------------------
-- Live recolor for custom aura bars (called from config color picker)
------------------------------------------------------------------------

function CooldownCompanion:RecolorCustomAuraBar(cabConfig)
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.cabConfig == cabConfig then
            StyleCustomAuraBar(barInfo, cabConfig)
            break
        end
    end
end

------------------------------------------------------------------------
-- Relayout: reposition bars within their containers by visibility/order
-- Called from ApplyResourceBars() and from OnUpdate when layoutDirty.
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

RelayoutResourceStack = function()
    layoutDirty = false
    RelayoutBars()
    if lastAppliedIndependentStack then
        UpdateIndependentStackChrome(lastAppliedOrientation == "vertical", lastAppliedLayout)
    end
    CooldownCompanion:RepositionCastBar()
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
    if isPreviewActive then
        HealthBar.RefreshEffectPreviewAnimation(settings)
        return
    end

    local auraActiveCache = segmentedUpdateScratch.auraActiveCache
    wipe(auraActiveCache)

    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame and (barInfo.frame:IsShown() or ShouldUpdateHiddenCustomAuraPandemicWake(barInfo)) then
            if barInfo.barType == "continuous" then
                UpdateContinuousBar(barInfo.frame, barInfo.powerType, settings, auraActiveCache)
            elseif barInfo.barType == "health_continuous" then
                HealthBar.Update(barInfo.frame, settings)
            elseif barInfo.barType == "segmented" then
                UpdateSegmentedBar(barInfo.frame, barInfo.powerType, settings, auraActiveCache)
            elseif barInfo.barType == "mw_segmented" then
                UpdateMaelstromWeaponBar(barInfo.frame, settings, auraActiveCache)
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

    if layoutDirty then
        RelayoutResourceStack()
    end
end

------------------------------------------------------------------------
-- Event handling (must be defined before Apply/Revert which call these)
------------------------------------------------------------------------

-- Lifecycle events: always registered while the feature is enabled.
-- These trigger full re-evaluation (not just re-apply) so the bars
-- come back after a form change that temporarily hides them.
local lifecycleFrame = nil

local function EnableLifecycleEvents()
    if not lifecycleFrame then
        lifecycleFrame = CreateFrame("Frame")
        lifecycleFrame:SetScript("OnEvent", function(self, event, ...)
            if event == "UPDATE_SHAPESHIFT_FORM" then
                CooldownCompanion:EvaluateResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            elseif event == "ACTIVE_TALENT_GROUP_CHANGED"
                or event == "PLAYER_SPECIALIZATION_CHANGED" then
                if not pendingSpecChange then
                    pendingSpecChange = true
                    C_Timer.After(0.5, function()
                        pendingSpecChange = false
                        local rebuilt = UpdateMWMaxStacks()
                        if not rebuilt then
                            CooldownCompanion:EvaluateResourceBars()
                        end
                        CooldownCompanion:RepositionCastBar()
                        CooldownCompanion:UpdateAnchorStacking()
                    end)
                end
            elseif event == "PLAYER_TALENT_UPDATE"
                or event == "TRAIT_CONFIG_UPDATED" then
                UpdateMWMaxStacks()
            end
        end)
    end
    lifecycleFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    lifecycleFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    lifecycleFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    lifecycleFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    lifecycleFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
end

local function DisableLifecycleEvents()
    if not lifecycleFrame then return end
    lifecycleFrame:UnregisterAllEvents()
    pendingSpecChange = false
end

-- Update events: only registered while bars are applied.
local function EnableEventFrame()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(self, event, ...)
            if event == "UNIT_MAXPOWER" or event == "UNIT_MAXHEALTH" then
                local unit = ...
                if unit == "player" then
                    CooldownCompanion:ApplyResourceBars()
                end
            elseif event == "UNIT_AURA" then
                local unit, updateInfo = ...
                if unit ~= "player" and unit ~= "target" then return end
                if not updateInfo then return end

                local removedIDs = updateInfo.removedAuraInstanceIDs
                local updatedIDs = updateInfo.updatedAuraInstanceIDs
                local hasAuraChange = updateInfo.isFullUpdate or updateInfo.addedAuras or removedIDs or updatedIDs
                if hasAuraChange then
                    RefreshEventDrivenCustomAuraBarsForUnit(unit)
                end
                if not removedIDs and not updatedIDs then return end

                for _, barInfo in ipairs(resourceBarFrames) do
                    local bar = barInfo and barInfo.frame
                    local cabConfig = barInfo and barInfo.cabConfig
                    if barInfo
                        and ((barInfo.barType == "custom_continuous"
                                and cabConfig and cabConfig.trackingMode == "active")
                            or (barInfo.barType == "custom_cooldown"
                                and cabConfig and cabConfig.auraTracking == true))
                        and bar and bar._auraInstanceID and bar._auraUnit == unit then
                        if removedIDs then
                            for _, instId in ipairs(removedIDs) do
                                if bar._auraInstanceID == instId then
                                    bar._auraActive = nil
                                    bar._auraInstanceID = nil
                                    bar._auraUnit = nil
                                    bar._inPandemic = nil
                                    bar._pandemicGraceStart = nil
                                    break
                                end
                            end
                        end
                        if updatedIDs and bar._auraInstanceID then
                            for _, instId in ipairs(updatedIDs) do
                                if bar._auraInstanceID == instId then
                                    bar._inPandemic = nil
                                    bar._pandemicGraceStart = nil
                                    bar._pandemicGraceSuppressed = true
                                    break
                                end
                            end
                        end
                    end
                end
            elseif event == "PLAYER_TARGET_CHANGED" then
                for _, barInfo in ipairs(resourceBarFrames) do
                    local bar = barInfo and barInfo.frame
                    local cabConfig = barInfo and barInfo.cabConfig
                    if barInfo
                        and ((barInfo.barType == "custom_continuous"
                                and cabConfig and cabConfig.trackingMode == "active")
                            or (barInfo.barType == "custom_cooldown"
                                and cabConfig and cabConfig.auraTracking == true))
                        and bar and GetResolvedCustomAuraBarAuraUnit(cabConfig, cabConfig.spellID) == "target" then
                        bar._auraActive = nil
                        bar._auraInstanceID = nil
                        bar._auraUnit = nil
                        bar._inPandemic = nil
                        bar._pandemicGraceStart = nil
                        bar._pandemicGraceSuppressed = nil
                    end
                end
                RefreshEventDrivenCustomAuraBarsForUnit("target")
            end
        end)
    end
    eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    -- UNIT_MAXHEALTH: stagger bar max is health-based; only matters for Brewmaster
    -- but RegisterUnitEvent with "player" filter has negligible overhead for others
    eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player", "target")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
end

local function DisableEventFrame()
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
end

------------------------------------------------------------------------
-- Apply: Create/show/position resource bars
------------------------------------------------------------------------

local function StyleContinuousBar(bar, powerType, settings)
    local texName = GetResourceDisplayValue(settings, "barTexture", "Solid")
    local isVertical = IsVerticalResourceLayout(settings)
    local reverseFill = IsVerticalFillReversed(settings)

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

    ApplyContinuousFillColor(bar, powerType, settings, nil)

    local bgc = GetResourceDisplayValue(settings, "backgroundColor", { 0, 0, 0, 0.5 })
    bar.bg:ClearAllPoints()
    bar.bg:SetAllPoints(bar)
    bar.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])

    local borderStyle = GetResourceDisplayValue(settings, "borderStyle", "pixel")
    local borderColor = GetResourceDisplayValue(settings, "borderColor", { 0, 0, 0, 1 })
    local borderSize = GetResourceDisplayValue(settings, "borderSize", 1)

    if borderStyle == "pixel" then
        ApplyPixelBorders(bar.borders, bar, borderColor, borderSize)
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
    local textOutline = resourceConfig and resourceConfig.textFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE
    local textColor = resourceConfig and resourceConfig.textFontColor or DEFAULT_RESOURCE_TEXT_COLOR
    if type(textColor) ~= "table" or textColor[1] == nil or textColor[2] == nil or textColor[3] == nil then
        textColor = DEFAULT_RESOURCE_TEXT_COLOR
    end

    local textFont = CooldownCompanion:FetchFont(textFontName)
    bar.text:SetFont(textFont, textSize, textOutline)
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

    -- Stagger (101) uses UnitHealthMax, not UnitPowerMax; tick markers not applicable
    if powerType ~= 101 then
        local maxPower = UnitPowerMax("player", powerType)
        local maxPowerIsSecret = IsUnitPowerMaxSecret("player", powerType)
        if issecretvalue and issecretvalue(maxPower) then
            maxPowerIsSecret = true
        end
        UpdateContinuousTickMarker(bar, powerType, settings, maxPower, maxPowerIsSecret)
    end
end

function HealthBar.Style(bar, settings)
    local resourceConfig = HealthBar.GetConfig(settings)
    local texName = GetResourceDisplayValue(settings, "barTexture", "Solid")
    local isVertical = IsVerticalResourceLayout(settings)
    local reverseFill = IsVerticalFillReversed(settings)
    local texture = CooldownCompanion:FetchStatusBar(texName == "blizzard_class" and "Blizzard" or texName)

    bar:SetStatusBarTexture(texture)
    bar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill(isVertical and reverseFill or false)
    bar._isVertical = isVertical
    bar._reverseFill = reverseFill
    bar._healthBarCurve = HealthBar.BuildFillCurve(resourceConfig)
    bar._healthBackgroundCurve = HealthBar.BuildBackgroundCurve(resourceConfig)
    bar._lowHealthAlertCurve = HealthBar.BuildLowHealthAlertCurve(resourceConfig)

    HealthBar.ApplyFillColor(bar, resourceConfig)
    HealthBar.EnsureEffectBars(bar)

    if bar.brightnessOverlay then
        bar.brightnessOverlay:Hide()
    end

    bar.bg:SetTexture(texture)
    HealthBar.SetBackgroundAnchors(bar)
    HealthBar.ApplyBackgroundColor(bar, resourceConfig)

    local borderStyle = GetResourceDisplayValue(settings, "borderStyle", "pixel")
    local borderColor = GetResourceDisplayValue(settings, "borderColor", { 0, 0, 0, 1 })
    local borderSize = GetResourceDisplayValue(settings, "borderSize", 1)

    if borderStyle == "pixel" then
        ApplyPixelBorders(bar.borders, bar, borderColor, borderSize)
    else
        HidePixelBorders(bar.borders)
    end
    HealthBar.LayoutEffectBars(bar, borderStyle, borderSize, resourceConfig)

    local textFormat = resourceConfig and resourceConfig.textFormat or "percent"
    if textFormat ~= "percent"
        and textFormat ~= "percent_no_sign"
        and textFormat ~= "current"
        and textFormat ~= "current_max"
        and textFormat ~= "current_percent"
        and textFormat ~= "current_percent_no_sign" then
        textFormat = "percent"
    end
    local textFontName = resourceConfig and resourceConfig.textFont or DEFAULT_RESOURCE_TEXT_FONT
    local textSize = tonumber(resourceConfig and resourceConfig.textFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
    local textOutline = resourceConfig and resourceConfig.textFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE
    local textColor = resourceConfig and resourceConfig.textFontColor or DEFAULT_RESOURCE_TEXT_COLOR
    if type(textColor) ~= "table" or textColor[1] == nil or textColor[2] == nil or textColor[3] == nil then
        textColor = DEFAULT_RESOURCE_TEXT_COLOR
    end

    bar.text:SetFont(CooldownCompanion:FetchFont(textFontName), textSize, textOutline)
    bar.text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] ~= nil and textColor[4] or 1)
    bar.text:ClearAllPoints()
    bar.text:SetPoint(
        resourceConfig and resourceConfig.textAnchor or "CENTER",
        resourceConfig and resourceConfig.textXOffset or 0,
        resourceConfig and resourceConfig.textYOffset or 0
    )
    bar.text:SetShown(resourceConfig and resourceConfig.showText == true)
    bar._textFormat = textFormat
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
    local textOutline = resourceConfig and resourceConfig.textFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE
    local textColor = resourceConfig and resourceConfig.textFontColor or DEFAULT_RESOURCE_TEXT_COLOR
    if type(textColor) ~= "table" or textColor[1] == nil or textColor[2] == nil or textColor[3] == nil then
        textColor = DEFAULT_RESOURCE_TEXT_COLOR
    end

    local textFont = CooldownCompanion:FetchFont(textFontName)
    holder.text:SetFont(textFont, textSize, textOutline)
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
end

local function ApplySegmentedPreviewColors(holder, powerType, settings, previewValue)
    if not holder or not holder.segments then return end

    local numSegments = #holder.segments
    if numSegments <= 0 then return end

    previewValue = tonumber(previewValue) or (numSegments * 0.6)
    local filled = math_min(numSegments, math_max(0, math_floor(previewValue)))
    local hasPartial = previewValue > filled and filled < numSegments

    local thresholdEnabled, thresholdValue, thresholdColor = GetSegmentedThresholdConfig(powerType, settings)
    local thresholdActive = thresholdEnabled and thresholdValue and filled >= thresholdValue

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
    end
end

RB.StyleContinuousBar = StyleContinuousBar
RB.StyleHealthBar = HealthBar.Style
RB.StyleSegmentedText = StyleSegmentedText
RB.StyleSegmentedBar = StyleSegmentedBar

function CooldownCompanion:ApplyResourceBars()
    local settings = GetResourceBarSettings()
    if not settings or not settings.enabled then
        self:RevertResourceBars()
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
        if not group or group.displayMode ~= "icons" then
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
    local customBarLoadDefaults = CooldownCompanion:GetLocalLoadConditionDefaults()
    for i, cab in ipairs(customBars) do
        if cab and cab.enabled and cab.spellID
            and CooldownCompanion:IsTalentConditionMet(cab)
            and CooldownCompanion:EvaluateLoadConditions(cab.loadConditions, customBarLoadDefaults) then
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
                    ClearResourceAuraVisuals(barInfo.frame)
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
                    ClearResourceAuraVisuals(barInfo.frame)
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
            -- Maelstrom Weapon: overlay bar with dedicated update
            local halfSegments = mwMaxStacks <= 5 and mwMaxStacks or (mwMaxStacks / 2)

            if not barInfo or barInfo.barType ~= "mw_segmented"
                or #barInfo.frame.segments ~= halfSegments then
                if barInfo and barInfo.frame then
                    ClearResourceAuraVisuals(barInfo.frame)
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
                    ClearResourceAuraVisuals(barInfo.frame)
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
            if not isPreviewActive then
                UpdateSegmentedBar(barInfo.frame, powerType, settings, {})
            end
        else
            -- Continuous bar
            if not barInfo or barInfo.barType ~= "continuous" then
                if barInfo and barInfo.frame then
                    ClearResourceAuraVisuals(barInfo.frame)
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
        barInfo._side = sideList[idx]
        barInfo._order = orderList[idx]
        barInfo._effectiveThickness = effectiveThickness

        FinalizeAppliedBarVisibility(barInfo, powerType, isPreviewActive)
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
            relFrame = _G[anchor.relativeTo] or UIParent
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
        if #frames > 0 then
            CooldownCompanion:RegisterModuleAlpha(rbModuleId, settings, frames)
        end
    end

    -- Re-apply preview visuals if preview mode is active
    if isPreviewActive then
        ApplyPreviewData()
    end
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
    layoutDirty = false
    ClearDeferredCustomAuraWakeRetries()

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
            ClearResourceAuraVisuals(barInfo.frame)
            ClearMaxStacksIndicator(barInfo)
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

    isPreviewActive = false
    wipe(HEALTH_EFFECTS.preview)
    HEALTH_EFFECTS.forcedPreview = nil
    wipe(customAuraBarActivePreviewTokens)
    wipe(customAuraBarPandemicPreviewTokens)
    wipe(activeCustomAuraBarActivePreviews)
    wipe(activeCustomAuraBarPandemicPreviews)
    activeResources = {}
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

local function RefreshCustomAuraBarPreviewState(cabConfig, previewKey, show)
    local anyUpdated = false

    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.cabConfig == cabConfig and barInfo.frame then
            barInfo.frame[previewKey] = show or nil
            if barInfo.barType == "custom_cooldown" then
                RB.UpdateCustomCooldownBar(barInfo)
            else
                UpdateCustomAuraBar(barInfo)
            end
            if barInfo.barType == "custom_continuous" or barInfo.barType == "custom_cooldown" then
                AnimateCustomAuraBarIndicator(barInfo.frame)
            end
            anyUpdated = true
        end
    end

    if anyUpdated and layoutDirty then
        RelayoutResourceStack()
    end
end

local function IsCustomAuraBarPreviewStateActive(cabConfig, previewKey)
    if not (cabConfig and previewKey) then
        return false
    end
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.cabConfig == cabConfig and barInfo.frame and barInfo.frame[previewKey] then
            return true
        end
    end
    return false
end

function CooldownCompanion:SetCustomAuraBarActivePreview(cabConfig, show)
    if not cabConfig then return end
    customAuraBarActivePreviewTokens[cabConfig] = (customAuraBarActivePreviewTokens[cabConfig] or 0) + 1
    activeCustomAuraBarActivePreviews[cabConfig] = show or nil
    RefreshCustomAuraBarPreviewState(cabConfig, "_barAuraActivePreview", show)
end

function CooldownCompanion:IsCustomAuraBarActivePreviewActive(cabConfig)
    return activeCustomAuraBarActivePreviews[cabConfig] == true
        or IsCustomAuraBarPreviewStateActive(cabConfig, "_barAuraActivePreview")
end

function CooldownCompanion:SetCustomAuraBarPandemicPreview(cabConfig, show)
    if not cabConfig then return end
    customAuraBarPandemicPreviewTokens[cabConfig] = (customAuraBarPandemicPreviewTokens[cabConfig] or 0) + 1
    activeCustomAuraBarPandemicPreviews[cabConfig] = show or nil
    RefreshCustomAuraBarPreviewState(cabConfig, "_pandemicPreview", show)
end

function CooldownCompanion:IsCustomAuraBarPandemicPreviewActive(cabConfig)
    return activeCustomAuraBarPandemicPreviews[cabConfig] == true
        or IsCustomAuraBarPreviewStateActive(cabConfig, "_pandemicPreview")
end

function CooldownCompanion:ClearAllCustomAuraBarPreviews()
    wipe(customAuraBarActivePreviewTokens)
    wipe(customAuraBarPandemicPreviewTokens)
    wipe(activeCustomAuraBarActivePreviews)
    wipe(activeCustomAuraBarPandemicPreviews)

    local anyUpdated = false
    for _, barInfo in ipairs(resourceBarFrames) do
        local frame = barInfo.frame
        if frame and (frame._barAuraActivePreview or frame._pandemicPreview) then
            frame._barAuraActivePreview = nil
            frame._pandemicPreview = nil
            if barInfo.barType == "custom_cooldown" then
                RB.UpdateCustomCooldownBar(barInfo)
            else
                UpdateCustomAuraBar(barInfo)
            end
            if barInfo.barType == "custom_continuous" or barInfo.barType == "custom_cooldown" then
                AnimateCustomAuraBarIndicator(frame)
            end
            anyUpdated = true
        end
    end

    if anyUpdated and layoutDirty then
        RelayoutResourceStack()
    end
end

function CooldownCompanion:PlayCustomAuraBarActivePreview(cabConfig, durationSeconds)
    if not cabConfig then return end

    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then duration = 3 end

    local token = (customAuraBarActivePreviewTokens[cabConfig] or 0) + 1
    customAuraBarActivePreviewTokens[cabConfig] = token

    activeCustomAuraBarActivePreviews[cabConfig] = true
    RefreshCustomAuraBarPreviewState(cabConfig, "_barAuraActivePreview", true)

    C_Timer.After(duration, function()
        if customAuraBarActivePreviewTokens[cabConfig] ~= token then return end
        activeCustomAuraBarActivePreviews[cabConfig] = nil
        RefreshCustomAuraBarPreviewState(cabConfig, "_barAuraActivePreview", false)
    end)
end

function CooldownCompanion:PlayCustomAuraBarPandemicPreview(cabConfig, durationSeconds)
    if not cabConfig then return end

    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then duration = 3 end

    local token = (customAuraBarPandemicPreviewTokens[cabConfig] or 0) + 1
    customAuraBarPandemicPreviewTokens[cabConfig] = token

    activeCustomAuraBarPandemicPreviews[cabConfig] = true
    RefreshCustomAuraBarPreviewState(cabConfig, "_pandemicPreview", true)

    C_Timer.After(duration, function()
        if customAuraBarPandemicPreviewTokens[cabConfig] ~= token then return end
        activeCustomAuraBarPandemicPreviews[cabConfig] = nil
        RefreshCustomAuraBarPreviewState(cabConfig, "_pandemicPreview", false)
    end)
end

function HealthBar.HasActiveEffectPreview()
    local preview = HEALTH_EFFECTS.preview
    return preview.absorbs == true
        or preview.healAbsorbs == true
        or preview.incomingHeals == true
        or preview.lowHealthAlert == true
end

function HealthBar.RefreshEffectPreviewState()
    if isPreviewActive and ApplyPreviewData then
        ApplyPreviewData()
        return
    end

    local settings = GetResourceBarSettings()
    local config = HealthBar.GetConfig(settings)
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.barType == "health_continuous" and barInfo.frame then
            HealthBar.UpdateEffectBars(barInfo.frame, config, UnitHealthMax("player"), HEALTH_EFFECTS.preview)
        end
    end
end

function HealthBar.RefreshEffectPreviewAnimation(settings)
    local preview = HEALTH_EFFECTS.preview
    if preview.lowHealthAlert ~= true then
        return
    end

    local config = HealthBar.GetConfig(settings)
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.barType == "health_continuous" and barInfo.frame and barInfo.frame:IsShown() then
            HealthBar.UpdateEffectBars(barInfo.frame, config, 100, preview)
        end
    end
end

function CooldownCompanion:SetHealthEffectPreview(effectKey, show)
    if effectKey ~= "absorbs"
        and effectKey ~= "healAbsorbs"
        and effectKey ~= "incomingHeals"
        and effectKey ~= "lowHealthAlert" then
        return
    end

    HEALTH_EFFECTS.preview[effectKey] = show and true or nil
    if show then
        if not isPreviewActive then
            HEALTH_EFFECTS.forcedPreview = true
            self:StartResourceBarPreview()
        else
            HealthBar.RefreshEffectPreviewState()
        end
        return
    end

    if not HealthBar.HasActiveEffectPreview() and HEALTH_EFFECTS.forcedPreview then
        HEALTH_EFFECTS.forcedPreview = nil
        self:StopResourceBarPreview()
    else
        HealthBar.RefreshEffectPreviewState()
    end
end

function CooldownCompanion:IsHealthEffectPreviewActive(effectKey)
    return HEALTH_EFFECTS.preview[effectKey] == true
end

function CooldownCompanion:ClearAllHealthEffectPreviews()
    if not HealthBar.HasActiveEffectPreview() then
        return
    end

    wipe(HEALTH_EFFECTS.preview)
    if HEALTH_EFFECTS.forcedPreview then
        HEALTH_EFFECTS.forcedPreview = nil
        self:StopResourceBarPreview()
    else
        HealthBar.RefreshEffectPreviewState()
    end
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

------------------------------------------------------------------------
-- Evaluate: central decision point
------------------------------------------------------------------------

function CooldownCompanion:EvaluateResourceBars()
    if self._unsupportedLegacyProfile then
        self:RevertResourceBars()
        return
    end

    local settings = GetResourceBarSettings()
    if not settings or not settings.enabled then
        DisableLifecycleEvents()
        self:RevertResourceBars()
        return
    end
    EnableLifecycleEvents()
    self:ApplyResourceBars()
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

local function ApplyPreviewDataToBar(barInfo, settings)
    if not (barInfo and barInfo.frame and barInfo.frame:IsShown()) then
        return
    end

    local function ApplyResourceAuraLanePreview(barInfo, previewRatio)
        local powerType = barInfo.powerType
        if not powerType then return end

        local resource = settings and settings.resources and settings.resources[powerType]
        if not IsResourceAuraOverlayEnabled(resource) then
            HideResourceAuraStackSegments(barInfo.frame)
            return
        end
        local auraEntry = GetActiveResourceAuraEntry(resource)
        if not auraEntry then
            HideResourceAuraStackSegments(barInfo.frame)
            return
        end
        local auraSpellID = tonumber(auraEntry.auraColorSpellID)
        local auraMaxStacks = GetResourceAuraConfiguredMaxStacks(powerType, settings)
        if not auraSpellID or auraSpellID <= 0 or not auraMaxStacks then
            HideResourceAuraStackSegments(barInfo.frame)
            return
        end

        local auraColor = auraEntry.auraActiveColor
        if type(auraColor) ~= "table" or not auraColor[1] or not auraColor[2] or not auraColor[3] then
            auraColor = DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
        end

        local previewStacks = math_max(1, math_floor((auraMaxStacks * previewRatio) + 0.5))
        ApplyResourceAuraStackSegments(barInfo.frame, settings, previewStacks, auraMaxStacks, auraColor)
    end

    ClearResourceAuraVisuals(barInfo.frame)
    if barInfo.barType == "continuous" then
        barInfo.frame:SetMinMaxValues(0, 100)
        barInfo.frame:SetValue(65)
        if barInfo.frame.text and barInfo.frame.text:IsShown() then
            local textFormat = barInfo.frame._textFormat
            if textFormat == "current" then
                barInfo.frame.text:SetText("65")
            elseif textFormat == "percent" then
                barInfo.frame.text:SetText("65")
            else
                barInfo.frame.text:SetText("65 / 100")
            end
        end
    elseif barInfo.barType == "health_continuous" then
        barInfo.frame:SetMinMaxValues(0, 100)
        barInfo.frame:SetValue(65)
        local config = HealthBar.GetConfig(settings)
        HealthBar.ApplyFillColor(barInfo.frame, config, 0.65)
        HealthBar.ApplyBackgroundColor(barInfo.frame, config, 0.65)
        HealthBar.UpdateEffectBars(barInfo.frame, config, 100, HEALTH_EFFECTS.preview)
        if barInfo.frame.text and barInfo.frame.text:IsShown() then
            local textFormat = barInfo.frame._textFormat
            if textFormat == "current" then
                barInfo.frame.text:SetText("650K")
            elseif textFormat == "current_max" then
                barInfo.frame.text:SetText("650K / 1M")
            elseif textFormat == "current_percent" then
                barInfo.frame.text:SetText("650K | 65%")
            elseif textFormat == "current_percent_no_sign" then
                barInfo.frame.text:SetText("650K | 65")
            elseif textFormat == "percent_no_sign" then
                barInfo.frame.text:SetText("65")
            else
                barInfo.frame.text:SetText("65%")
            end
        end
    elseif barInfo.barType == "segmented" then
        local n = #barInfo.frame.segments
        local filled = math_floor(n * 0.6)
        local previewValue = filled + 0.5
        for i, seg in ipairs(barInfo.frame.segments) do
            if i <= filled then
                seg:SetValue(1)
            elseif i == filled + 1 then
                seg:SetValue(0.5)
            else
                seg:SetValue(0)
            end
        end
        ApplySegmentedPreviewColors(barInfo.frame, barInfo.powerType, settings, previewValue)
        ApplyResourceAuraLanePreview(barInfo, 0.5)
        SetSegmentedText(barInfo.frame, previewValue, n)
    elseif barInfo.barType == "stagger_continuous" then
        barInfo.frame:SetMinMaxValues(0, 100)
        barInfo.frame:SetValue(45)
        local _, yellowColor = GetResourceColors(101, settings)
        barInfo.frame:SetStatusBarColor(yellowColor[1], yellowColor[2], yellowColor[3], 1)
        barInfo.frame.brightnessOverlay:Hide()
        if barInfo.frame.text and barInfo.frame.text:IsShown() then
            local textFormat = barInfo.frame._textFormat
            if textFormat == "current" then
                barInfo.frame.text:SetText("45")
            elseif textFormat == "percent" then
                barInfo.frame.text:SetText("45%")
            else
                barInfo.frame.text:SetText("45 / 100")
            end
        end
    elseif barInfo.barType == "mw_segmented" then
        local half = #barInfo.frame.segments
        local previewStacks = math_min(mwMaxStacks, math_max(1, math_floor((mwMaxStacks * 0.7) + 0.5)))
        if mwMaxStacks > 5 then
            previewStacks = math_min(mwMaxStacks, math_max(previewStacks, 7))
        end
        for i = 1, half do
            barInfo.frame.segments[i]:SetValue(previewStacks)
            barInfo.frame.overlaySegments[i]:SetValue(previewStacks)
            if previewStacks > (half + i - 1) then
                barInfo.frame.overlaySegments[i]:SetAlpha(1)
            else
                barInfo.frame.overlaySegments[i]:SetAlpha(0)
            end
        end
        ApplyResourceAuraLanePreview(barInfo, 0.5)
        SetSegmentedText(barInfo.frame, previewStacks, mwMaxStacks)
    elseif barInfo.barType == "custom_cooldown" then
        local cabConfig = barInfo.cabConfig
        local isSpellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
        local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
        local previewValue
        if isSpellAuraStackDisplay then
            barInfo.frame:SetMinMaxValues(0, maxStacks)
            previewValue = math.ceil(maxStacks * 0.65)
            barInfo.frame:SetValue(previewValue)
        else
            barInfo.frame:SetMinMaxValues(0, 1)
            previewValue = 0.45
            barInfo.frame:SetValue(previewValue)
        end
        if barInfo.frame.thresholdOverlay then
            barInfo.frame.thresholdOverlay:SetValue(0)
            barInfo.frame.thresholdOverlay:Hide()
        end
        if barInfo.frame.text and barInfo.frame.text:IsShown() then
            if isSpellAuraStackDisplay then
                barInfo.frame.text:SetText("")
            else
                barInfo.frame.text:SetText(FormatTime(12.3, cabConfig))
            end
        end
        if barInfo.frame.stackText and barInfo.frame.stackText:IsShown() then
            if isSpellAuraStackDisplay then
                RB.UpdateSpellCustomBarAuraStackText(barInfo.frame, cabConfig, previewValue, maxStacks, true)
            else
                barInfo.frame.stackText:SetText("1 / 2")
            end
        end
        ClearCustomAuraBarIndicatorState(barInfo, true)
        if barInfo._maxStacksIndicator then
            barInfo._maxStacksIndicator:SetValue(0)
        end
    elseif barInfo.barType == "custom_continuous" then
        local cabConfig = barInfo.cabConfig
        local isActive = cabConfig and cabConfig.trackingMode == "active"
        local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
        local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
        local indicatorPreview = cabConfig and cabConfig.maxStacksGlowEnabled
        ClearCustomAuraBarIndicatorState(barInfo, false)
        local previewValue
        if isActive then
            barInfo.frame:SetMinMaxValues(0, 1)
            previewValue = indicatorPreview and 1 or 0.65
            barInfo.frame:SetValue(previewValue)
        else
            barInfo.frame:SetMinMaxValues(0, maxStacks)
            previewValue = indicatorPreview and maxStacks or math.ceil(maxStacks * 0.65)
            barInfo.frame:SetValue(previewValue)
        end
        if barInfo.frame.thresholdOverlay then
            if thresholdEnabled then
                SetCustomAuraMaxThresholdRange(barInfo.frame.thresholdOverlay, maxStacks)
                barInfo.frame.thresholdOverlay:SetValue(previewValue or 0)
                barInfo.frame.thresholdOverlay:Show()
            else
                barInfo.frame.thresholdOverlay:SetValue(0)
                barInfo.frame.thresholdOverlay:Hide()
            end
        end
        if barInfo.frame.text and barInfo.frame.text:IsShown() then
            barInfo.frame.text:SetText(FormatTime(12.3, cabConfig))
        end
        if barInfo.frame.stackText and barInfo.frame.stackText:IsShown() then
            if isActive then
                barInfo.frame.stackText:SetFormattedText("%d", 3)
            else
                local stackTextFormat = NormalizeCustomAuraStackTextFormat(cabConfig and cabConfig.stackTextFormat)
                if stackTextFormat == "current" then
                    barInfo.frame.stackText:SetFormattedText("%d", previewValue)
                else
                    barInfo.frame.stackText:SetFormattedText("%d / %d", previewValue, maxStacks)
                end
            end
        end
        if cabConfig and cabConfig.maxStacksGlowEnabled and barInfo._maxStacksIndicator then
            barInfo._maxStacksIndicator:SetValue(maxStacks)
        end
    elseif barInfo.barType == "custom_segmented" then
        local cabConfig = barInfo.cabConfig
        local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
        local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
        local indicatorPreview = cabConfig and cabConfig.maxStacksGlowEnabled
        local n = #barInfo.frame.segments
        local fill = indicatorPreview and n or math.ceil(n * 0.6)
        for _, seg in ipairs(barInfo.frame.segments) do
            seg:SetValue(fill)
        end
        if barInfo.frame.thresholdSegments then
            for _, seg in ipairs(barInfo.frame.thresholdSegments) do
                if thresholdEnabled then
                    SetCustomAuraMaxThresholdRange(seg, maxStacks)
                    seg:SetValue(fill)
                    seg:Show()
                else
                    seg:SetValue(0)
                    seg:Hide()
                end
            end
        end
        if cabConfig and cabConfig.maxStacksGlowEnabled and barInfo._maxStacksIndicator then
            barInfo._maxStacksIndicator:SetValue(maxStacks)
        end
    elseif barInfo.barType == "custom_overlay" then
        local cabConfig = barInfo.cabConfig
        local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
        local indicatorPreview = cabConfig and cabConfig.maxStacksGlowEnabled
        local previewStacks = indicatorPreview and maxStacks or math.ceil(maxStacks * 0.7)
        local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
        local half = barInfo.halfSegments or 1
        for i = 1, half do
            barInfo.frame.segments[i]:SetValue(previewStacks)
            barInfo.frame.overlaySegments[i]:SetValue(previewStacks)
            if barInfo.frame.thresholdSegments and barInfo.frame.thresholdSegments[i] then
                local seg = barInfo.frame.thresholdSegments[i]
                if thresholdEnabled then
                    SetCustomAuraMaxThresholdRange(seg, maxStacks)
                    seg:SetValue(previewStacks)
                    seg:Show()
                else
                    seg:SetValue(0)
                    seg:Hide()
                end
            end
        end
        if cabConfig and cabConfig.maxStacksGlowEnabled and barInfo._maxStacksIndicator then
            barInfo._maxStacksIndicator:SetValue(maxStacks)
        end
    end
end

RB.ApplyPreviewBarState = ApplyPreviewDataToBar
RB.GetMWMaxStacks = function()
    return mwMaxStacks
end
RB.StyleCustomAuraBar = StyleCustomAuraBar

ApplyPreviewData = function()
    local settings = GetResourceBarSettings()

    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame and barInfo.frame:IsShown() then
            ApplyPreviewDataToBar(barInfo, settings)
        end
    end
end

function CooldownCompanion:StartResourceBarPreview()
    isPreviewActive = true
    self:ApplyResourceBars()  -- ApplyPreviewData() called at end when isPreviewActive
end

function CooldownCompanion:StopResourceBarPreview()
    if CS then
        CS.customBarIndicatorPreviewActive = nil
    end
    if not isPreviewActive then return end
    isPreviewActive = false
    wipe(HEALTH_EFFECTS.preview)
    HEALTH_EFFECTS.forcedPreview = nil
    -- Resume live updates on next OnUpdate tick
end

function CooldownCompanion:IsResourceBarPreviewActive()
    return isPreviewActive
end

------------------------------------------------------------------------
-- Hook installation (same pattern as CastBar)
------------------------------------------------------------------------

local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    -- When anchor group refreshes — re-evaluate
    hooksecurefunc(CooldownCompanion, "RefreshGroupFrame", function(self, groupId)
        local s = GetResourceBarSettings()
        if s and s.enabled then
            C_Timer.After(0, function()
                CooldownCompanion:EvaluateResourceBars()
            end)
        end
    end)

    local function QueueResourceBarReevaluate()
        C_Timer.After(0.1, function()
            CooldownCompanion:EvaluateResourceBars()
        end)
    end

    -- When all groups refresh — re-evaluate
    hooksecurefunc(CooldownCompanion, "RefreshAllGroups", function()
        QueueResourceBarReevaluate()
    end)

    -- Visibility-only refresh path (zone/resting/pet-battle transitions)
    -- still needs resource bar anchoring re-evaluation.
    hooksecurefunc(CooldownCompanion, "RefreshAllGroupsVisibilityOnly", function()
        QueueResourceBarReevaluate()
    end)

    -- When compact layout changes visible buttons — re-apply if primary length changed
    hooksecurefunc(CooldownCompanion, "UpdateGroupLayout", function(self, groupId)
        local s = GetResourceBarSettings()
        if not s or not s.enabled then return end
        local layout = GetSpecLayoutOrder(s)
        if layout and layout.independentAnchorEnabled then return end  -- independent stack: width not tied to group
        local anchorGroupId = GetEffectiveAnchorGroupId(s)
        if anchorGroupId ~= groupId then return end
        local groupFrame = CooldownCompanion.groupFrames[groupId]
        if not groupFrame or not lastAppliedPrimaryLength then return end
        local newLength = GetResourcePrimaryLength(groupFrame, s)
        if math_abs(newLength - lastAppliedPrimaryLength) < 0.1 then
            return
        end
        CooldownCompanion:ApplyResourceBars()
    end)

    -- When icon size / spacing / buttons-per-row changes — re-apply if primary length changed
    hooksecurefunc(CooldownCompanion, "ResizeGroupFrame", function(self, groupId)
        local s = GetResourceBarSettings()
        if not s or not s.enabled then return end
        local layout = GetSpecLayoutOrder(s)
        if layout and layout.independentAnchorEnabled then return end  -- independent stack: width not tied to group
        local anchorGroupId = GetEffectiveAnchorGroupId(s)
        if anchorGroupId ~= groupId then return end
        local groupFrame = CooldownCompanion.groupFrames[groupId]
        if not groupFrame or not lastAppliedPrimaryLength then return end
        local newLength = GetResourcePrimaryLength(groupFrame, s)
        if math_abs(newLength - lastAppliedPrimaryLength) < 0.1 then
            return
        end
        CooldownCompanion:ApplyResourceBars()
    end)

    local function QueueResourceBarApply()
        C_Timer.After(0, function()
            local settings = GetResourceBarSettings()
            if settings and settings.enabled then
                CooldownCompanion:ApplyResourceBars()
            end
        end)
    end

    -- Re-apply when config visibility changes so independent drag state updates.
    hooksecurefunc(CooldownCompanion, "ToggleConfig", function()
        QueueResourceBarApply()
    end)

    -- Re-apply when switching between Buttons and Bars modes.
    if ST and ST._SetConfigPrimaryMode then
        hooksecurefunc(ST, "_SetConfigPrimaryMode", function()
            QueueResourceBarApply()
        end)
    end
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    C_Timer.After(0.5, function()
        UpdateMWMaxStacks()
        InstallHooks()
        CooldownCompanion:EvaluateResourceBars()
    end)
end)
