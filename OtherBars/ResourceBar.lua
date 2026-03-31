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
local MAX_CUSTOM_AURA_BARS = RB.MAX_CUSTOM_AURA_BARS
local MW_SPELL_ID = RB.MW_SPELL_ID
local RAGING_MAELSTROM_SPELL_ID = RB.RAGING_MAELSTROM_SPELL_ID
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
local GetSpecLayoutOrder = RB.GetSpecLayoutOrder
local GetAnchorOffset = RB.GetAnchorOffset
local RoundToTenths = RB.RoundToTenths
local ClampIndependentDimension = RB.ClampIndependentDimension
local IsTruthyConfigFlag = RB.IsTruthyConfigFlag
local NormalizeCustomAuraIndependentOrientation = RB.NormalizeCustomAuraIndependentOrientation
local NormalizeCustomAuraIndependentVerticalFillDirection = RB.NormalizeCustomAuraIndependentVerticalFillDirection
local IsCustomAuraBarIndependent = RB.IsCustomAuraBarIndependent
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
local independentWrapperFrame = nil
local customAuraBarActivePreviewTokens = {}
local customAuraBarPandemicPreviewTokens = {}
local CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL = 0.65
local CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS = 3
local CUSTOM_AURA_BAR_EFFECT_PREVIEW_DURATION = 12.3

------------------------------------------------------------------------
-- Independent Anchor Config (writes state — stays in main file)
------------------------------------------------------------------------

local function EnsureCustomAuraIndependentConfig(cabConfig, settings)
    if type(cabConfig) ~= "table" then return end

    if cabConfig.independentAnchorEnabled ~= nil then
        cabConfig.independentAnchorEnabled = IsTruthyConfigFlag(cabConfig.independentAnchorEnabled) and true or nil
    end

    if cabConfig.independentAnchorTargetMode ~= "group"
        and cabConfig.independentAnchorTargetMode ~= "frame" then
        cabConfig.independentAnchorTargetMode = "group"
    end
    if type(cabConfig.independentLocked) ~= "boolean" then
        cabConfig.independentLocked = IsTruthyConfigFlag(cabConfig.independentLocked) and true or false
    end

    cabConfig.independentOrientation = NormalizeCustomAuraIndependentOrientation(cabConfig.independentOrientation)
    cabConfig.independentVerticalFillDirection =
        NormalizeCustomAuraIndependentVerticalFillDirection(cabConfig.independentVerticalFillDirection)

    if type(cabConfig.independentAnchor) ~= "table" then
        cabConfig.independentAnchor = {}
    end
    local anchor = cabConfig.independentAnchor
    anchor.point = anchor.point or "CENTER"
    anchor.relativePoint = anchor.relativePoint or "CENTER"
    anchor.x = tonumber(anchor.x) or 0
    anchor.y = tonumber(anchor.y) or 0

    if type(cabConfig.independentSize) ~= "table" then
        cabConfig.independentSize = {}
    end
    local size = cabConfig.independentSize
    size.width = ClampIndependentDimension(size.width, 120)
    size.height = ClampIndependentDimension(size.height, GetResourceGlobalThickness(settings))
end

local function ResolveIndependentAnchorTarget(cabConfig, settings)
    if type(cabConfig) ~= "table" then
        return UIParent, "UIParent"
    end

    if cabConfig.independentAnchorTargetMode == "frame" then
        local frameName = cabConfig.independentAnchorFrameName
        if type(frameName) == "string" and frameName ~= "" then
            local frame = _G[frameName]
            if frame then
                return frame, frameName
            end
        end
        return UIParent, "UIParent"
    end

    local groupId = cabConfig.independentAnchorGroupId or GetEffectiveAnchorGroupId(settings)
    if groupId then
        local groupFrame = CooldownCompanion.groupFrames[groupId]
        if groupFrame then
            return groupFrame, "CooldownCompanionGroup" .. groupId
        end
    end
    return UIParent, "UIParent"
end


local function ApplyIndependentAlphaSync(frame, settings, targetFrame)
    if not frame then return end
    if not frame._cdcIndependentAlphaSync then
        frame._cdcIndependentAlphaSync = CreateFrame("Frame", nil, frame)
    end

    if settings and settings.inheritAlpha and targetFrame then
        frame._cdcIndependentAlphaTarget = targetFrame
        frame._cdcIndependentLastAlpha = targetFrame:GetEffectiveAlpha()
        frame:SetAlpha(frame._cdcIndependentLastAlpha)

        local accumulator = 0
        local syncInterval = 1 / 30
        frame._cdcIndependentAlphaSync:SetScript("OnUpdate", function(syncFrame, dt)
            accumulator = accumulator + dt
            if accumulator < syncInterval then return end
            accumulator = 0

            local owner = syncFrame:GetParent()
            local target = owner and owner._cdcIndependentAlphaTarget
            if not target then return end

            local alpha = target:GetEffectiveAlpha()
            if alpha ~= owner._cdcIndependentLastAlpha then
                owner._cdcIndependentLastAlpha = alpha
                owner:SetAlpha(alpha)
            end
        end)
        return
    end

    frame._cdcIndependentAlphaTarget = nil
    frame._cdcIndependentLastAlpha = nil
    frame._cdcIndependentAlphaSync:SetScript("OnUpdate", nil)
    frame:SetAlpha(1)
end

local function GetCustomAuraSlotFromPowerType(powerType)
    local pt = tonumber(powerType)
    if not pt then return nil end
    if pt < CUSTOM_AURA_BAR_BASE or pt >= CUSTOM_AURA_BAR_BASE + MAX_CUSTOM_AURA_BARS then
        return nil
    end
    return pt - CUSTOM_AURA_BAR_BASE + 1
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

local function ClearCustomAuraBarIndicatorState(barInfo, clearPreviewFlags)
    if not barInfo or barInfo.barType ~= "custom_continuous" then
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
    if not barInfo or barInfo.barType ~= "custom_continuous" then return end
    if not cabConfig or cabConfig.trackingMode ~= "active" then
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
    if pandemicPreview then
        wantAuraColor = cabConfig.barPandemicColor or DEFAULT_BAR_PANDEMIC_COLOR
    elseif auraPreview then
        wantAuraColor = cabConfig.barColor or {0.5, 0.5, 1}
    elseif auraPresent then
        if bar._inPandemic and pandemicEnabled and pandemicCombatAllowed then
            wantAuraColor = cabConfig.barPandemicColor or DEFAULT_BAR_PANDEMIC_COLOR
        elseif auraVisualsEnabled and auraCombatAllowed then
            wantAuraColor = cabConfig.barColor or {0.5, 0.5, 1}
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
local function IsIndependentCustomAuraUnlocked(barInfo)
    return barInfo and barInfo.cabConfig and barInfo.cabConfig.independentLocked ~= true
end

local function GetIndependentCustomAuraHeaderText(barInfo)
    local slotIdx = GetCustomAuraSlotFromPowerType(barInfo and barInfo.powerType) or 0
    if barInfo and barInfo.cabConfig and barInfo.cabConfig.spellID then
        local spellName = C_Spell.GetSpellName(barInfo.cabConfig.spellID)
        if spellName and spellName ~= "" then
            return spellName
        end
    end
    if slotIdx > 0 then
        return "Aura Bar " .. tostring(slotIdx)
    end
    return "Aura Bar"
end

local function SaveIndependentCustomAuraAnchor(barInfo, refreshConfig)
    if not barInfo or not barInfo.frame or not barInfo.cabConfig then return end
    local settings = GetResourceBarSettings()
    if not settings then return end

    local cabConfig = barInfo.cabConfig
    EnsureCustomAuraIndependentConfig(cabConfig, settings)

    local frame = barInfo.frame
    local anchor = cabConfig.independentAnchor
    local targetFrame = ResolveIndependentAnchorTarget(cabConfig, settings)
    if not targetFrame then
        targetFrame = UIParent
    end

    local cx, cy = frame:GetCenter()
    local fw, fh = frame:GetSize()
    local tcx, tcy = targetFrame:GetCenter()
    local tw, th = targetFrame:GetSize()
    if not (cx and cy and fw and fh and tcx and tcy and tw and th) then
        return
    end

    local fax, fay = GetAnchorOffset(anchor.point, fw, fh)
    local tax, tay = GetAnchorOffset(anchor.relativePoint, tw, th)
    anchor.x = RoundToTenths((cx + fax) - (tcx + tax))
    anchor.y = RoundToTenths((cy + fay) - (tcy + tay))

    if refreshConfig and IsBarsConfigActive() and CooldownCompanion.RefreshConfigPanel then
        CooldownCompanion:RefreshConfigPanel()
    end
end


local UpdateIndependentDragState

local function EnsureIndependentDragChrome(frame)
    if not frame or frame._cdcIndependentDragHandle then return end

    local dragHandle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    dragHandle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    dragHandle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
    dragHandle:SetHeight(15)
    dragHandle:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    dragHandle:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    dragHandle:SetBackdropBorderColor(0, 0, 0, 1)
    dragHandle:EnableMouse(false)
    dragHandle:RegisterForDrag()

    dragHandle.text = dragHandle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragHandle.text:SetPoint("CENTER")
    dragHandle.text:SetTextColor(1, 1, 1, 1)

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
        { atlas = "common-dropdown-icon-back", rotation = -math.pi / 2, anchor = "BOTTOM", dx = 0, dy = 1, ox = 0, oy = NUDGE_GAP },  -- up
        { atlas = "common-dropdown-icon-next", rotation = -math.pi / 2, anchor = "TOP", dx = 0, dy = -1, ox = 0, oy = -NUDGE_GAP },   -- down
        { atlas = "common-dropdown-icon-back", rotation = 0, anchor = "RIGHT", dx = -1, dy = 0, ox = -NUDGE_GAP, oy = 0 },            -- left
        { atlas = "common-dropdown-icon-next", rotation = 0, anchor = "LEFT", dx = 1, dy = 0, ox = NUDGE_GAP, oy = 0 },               -- right
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
            local info = frame._cdcIndependentBarInfo
            if not info or not info._isIndependent then return end
            if not IsIndependentCustomAuraUnlocked(info) then return end
            frame:AdjustPointsOffset(dir.dx, dir.dy)
        end

        btn:SetScript("OnEnter", function(self)
            self.arrow:SetVertexColor(1, 1, 1, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self.arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
            CancelNudgeTimers(self)
            local info = frame._cdcIndependentBarInfo
            if info and info._isIndependent then
                SaveIndependentCustomAuraAnchor(info, true)
            end
        end)
        btn:SetScript("OnMouseDown", function(self)
            DoNudge()
            self._cdcNudgeDelayTimer = C_Timer.NewTimer(INDEPENDENT_NUDGE_REPEAT_DELAY, function()
                self._cdcNudgeTicker = C_Timer.NewTicker(INDEPENDENT_NUDGE_REPEAT_INTERVAL, function()
                    DoNudge()
                end)
            end)
        end)
        btn:SetScript("OnMouseUp", function(self)
            CancelNudgeTimers(self)
            local info = frame._cdcIndependentBarInfo
            if info and info._isIndependent then
                SaveIndependentCustomAuraAnchor(info, true)
            end
        end)

        nudger._cdcButtons[#nudger._cdcButtons + 1] = btn
    end

    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        local info = frame._cdcIndependentBarInfo
        if not info or not info._isIndependent then return end
        if not IsIndependentCustomAuraUnlocked(info) then return end
        frame:StartMoving()
    end)
    dragHandle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local info = frame._cdcIndependentBarInfo
        if info and info._isIndependent then
            SaveIndependentCustomAuraAnchor(info, true)
        end
    end)
    dragHandle:SetScript("OnMouseUp", function(_, button)
        if button ~= "MiddleButton" then return end
        local info = frame._cdcIndependentBarInfo
        if not info or not info._isIndependent or not info.cabConfig then return end
        info.cabConfig.independentLocked = true
        SaveIndependentCustomAuraAnchor(info, true)
        UpdateIndependentDragState(frame, info)
    end)

    frame._cdcIndependentDragHandle = dragHandle
    frame._cdcIndependentNudger = nudger
end

UpdateIndependentDragState = function(frame, barInfo)
    if not frame then return end

    EnsureIndependentDragChrome(frame)
    local dragHandle = frame._cdcIndependentDragHandle
    local nudger = frame._cdcIndependentNudger
    local canShowChrome = barInfo and barInfo._isIndependent
    local unlocked = canShowChrome and IsIndependentCustomAuraUnlocked(barInfo)

    frame:SetClampedToScreen(true)
    frame:SetMovable(unlocked)
    frame:EnableMouse(false)
    frame:RegisterForDrag()

    if dragHandle then
        dragHandle:SetShown(unlocked)
        dragHandle:EnableMouse(unlocked)
        if unlocked then
            dragHandle:RegisterForDrag("LeftButton")
        else
            dragHandle:RegisterForDrag()
        end
        if dragHandle.text then
            dragHandle.text:SetText(GetIndependentCustomAuraHeaderText(barInfo))
        end
        dragHandle:SetFrameStrata(frame:GetFrameStrata())
        dragHandle:SetFrameLevel(frame:GetFrameLevel() + 20)
    end

    if nudger then
        nudger:SetShown(unlocked)
        nudger:EnableMouse(unlocked)
        nudger:SetFrameStrata(frame:GetFrameStrata())
        if dragHandle then
            nudger:SetFrameLevel(dragHandle:GetFrameLevel() + 5)
        else
            nudger:SetFrameLevel(frame:GetFrameLevel() + 25)
        end
        if nudger._cdcButtons then
            for _, btn in ipairs(nudger._cdcButtons) do
                btn:EnableMouse(unlocked)
                if not unlocked then
                    CancelNudgeTimers(btn)
                end
            end
        end
    end
end

local function ClearIndependentRuntimeState(frame)
    if not frame then return end
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

    ApplyIndependentAlphaSync(frame, nil, nil)
end

local function ApplyIndependentCustomAuraPlacement(barInfo, cabConfig, settings)
    if not barInfo or not barInfo.frame then return end

    EnsureCustomAuraIndependentConfig(cabConfig, settings)
    local frame = barInfo.frame
    local anchor = cabConfig.independentAnchor
    local size = cabConfig.independentSize
    local targetFrame = ResolveIndependentAnchorTarget(cabConfig, settings)
    local point = anchor.point or "CENTER"
    local relativePoint = anchor.relativePoint or "CENTER"
    local x = tonumber(anchor.x) or 0
    local y = tonumber(anchor.y) or 0
    local width = ClampIndependentDimension(size.width, frame:GetWidth())
    local height = ClampIndependentDimension(size.height, frame:GetHeight())

    size.width = width
    size.height = height
    anchor.x = x
    anchor.y = y

    if frame:GetParent() ~= UIParent then
        frame:SetParent(UIParent)
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, targetFrame, relativePoint, x, y)
    frame:SetSize(width, height)

    frame._cdcIndependentBarInfo = barInfo
    UpdateIndependentDragState(frame, barInfo)
    ApplyIndependentAlphaSync(frame, settings, targetFrame)
end

function CooldownCompanion:ApplyIndependentCustomAuraPlacement(barInfo, cabConfig, settings)
    ApplyIndependentCustomAuraPlacement(barInfo, cabConfig, settings)
end

function CooldownCompanion:ClearIndependentCustomAuraRuntimeState(frame)
    ClearIndependentRuntimeState(frame)
end

------------------------------------------------------------------------
-- Independent Stack Anchoring (entire resource bar stack to UIParent)
------------------------------------------------------------------------

local function EnsureIndependentStackConfig(settings)
    if type(settings.independentAnchor) ~= "table" then
        settings.independentAnchor = {}
    end
    local anchor = settings.independentAnchor
    anchor.point = anchor.point or "CENTER"
    anchor.relativePoint = anchor.relativePoint or "CENTER"
    anchor.x = tonumber(anchor.x) or 0
    anchor.y = tonumber(anchor.y) or 0
    if anchor.relativeTo ~= nil and type(anchor.relativeTo) ~= "string" then
        anchor.relativeTo = nil
    end
    settings.independentWidth = ClampIndependentDimension(settings.independentWidth, 200)
end

local function SaveIndependentStackAnchor(refreshConfig)
    if not independentWrapperFrame then return end
    local settings = GetResourceBarSettings()
    if not settings then return end
    EnsureIndependentStackConfig(settings)

    local frame = independentWrapperFrame
    local anchor = settings.independentAnchor

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
            if not settings or settings.independentAnchorLocked then return end
            frame:AdjustPointsOffset(dir.dx, dir.dy)
            -- Write position per step and update coord label (GroupFrame pattern)
            local _, _, _, x, y = frame:GetPoint()
            if x and y then
                EnsureIndependentStackConfig(settings)
                settings.independentAnchor.x = RoundToTenths(x)
                settings.independentAnchor.y = RoundToTenths(y)
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
        if not settings or settings.independentAnchorLocked then return end
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
        settings.independentAnchorLocked = true
        frame:StopMovingOrSizing()
        SaveIndependentStackAnchor(true)
        UpdateIndependentStackDragState(settings)
    end)

    frame._dragHandle = dragHandle
    frame._nudger = nudger
    frame._coordLabel = coordLabel
    independentWrapperFrame = frame
end

UpdateIndependentStackDragState = function(settings)
    if not independentWrapperFrame then return end
    local frame = independentWrapperFrame
    local unlocked = settings and settings.independentAnchorEnabled and not settings.independentAnchorLocked

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
local function UpdateIndependentStackChrome(isVerticalLayout)
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
        if settings and settings.independentAnchor then
            coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(
                settings.independentAnchor.x or 0,
                settings.independentAnchor.y or 0
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
    local fullSegments = {}

    local function FinalizeAuraVisuals()
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

    local function ClearForSecretMath()
        for _, seg in ipairs(holder.segments) do
            seg:SetValue(0)
        end
    end

    local function FinalizeSegmentedUpdate(currentValue, maxValue, clearText)
        FinalizeAuraVisuals()
        if clearText then
            ClearSegmentedText(holder)
        else
            SetSegmentedText(holder, currentValue, maxValue)
        end
    end

    if powerType == 5 then
        -- DK Runes: sorted by readiness (ready left, longest CD right)
        local now = GetTime()
        local numSegs = math_min(#holder.segments, 6)
        local runeData = {}
        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown(i)
            local remaining = 0
            if not ready and duration and duration > 0 then
                remaining = math_max((start + duration) - now, 0)
            end
            runeData[i] = { start = start, duration = duration, ready = ready, remaining = remaining }
        end
        -- Sort: ready first, then by ascending remaining time
        table.sort(runeData, function(a, b)
            if a.ready ~= b.ready then return a.ready end
            return a.remaining < b.remaining
        end)
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
        FinalizeSegmentedUpdate(runeValueTotal, numSegs, false)
        return
    end

    if powerType == 7 then
        if IsUnitPowerSecret("player", 7) or IsUnitPowerMaxSecret("player", 7) then
            ClearForSecretMath()
            FinalizeSegmentedUpdate(nil, nil, true)
            return
        end

        -- Soul Shards: fractional fill with ready/recharging colors
        local raw = UnitPower("player", 7, true)
        local rawMax = UnitPowerMax("player", 7, true)
        local max = UnitPowerMax("player", 7)
        if issecretvalue and (issecretvalue(raw) or issecretvalue(rawMax) or issecretvalue(max)) then
            ClearForSecretMath()
            FinalizeSegmentedUpdate(nil, nil, true)
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
                ClearForSecretMath()
            end
        else
            ClearForSecretMath()
        end
        if type(displayCurrent) == "number" then
            FinalizeSegmentedUpdate(displayCurrent, max, false)
        else
            FinalizeSegmentedUpdate(nil, nil, true)
        end
        return
    end

    if powerType == 19 then
        if IsUnitPowerSecret("player", 19) or IsUnitPowerMaxSecret("player", 19) then
            ClearForSecretMath()
            FinalizeSegmentedUpdate(nil, nil, true)
            return
        end

        -- Essence: partial recharge with ready/recharging colors
        local filled = UnitPower("player", 19)
        local max = UnitPowerMax("player", 19)
        local partialRaw = UnitPartialPower("player", 19)
        if issecretvalue and (issecretvalue(filled) or issecretvalue(max) or issecretvalue(partialRaw)) then
            ClearForSecretMath()
            FinalizeSegmentedUpdate(nil, nil, true)
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
        FinalizeSegmentedUpdate(displayCurrent, max, false)
        return
    end

    -- Combo Points: color changes at max, charged coloring for Rogues
    if powerType == 4 then
        if IsUnitPowerSecret("player", 4) or IsUnitPowerMaxSecret("player", 4) then
            ClearForSecretMath()
            FinalizeSegmentedUpdate(nil, nil, true)
            return
        end

        local current = UnitPower("player", 4)
        local max = UnitPowerMax("player", 4)
        if issecretvalue and (issecretvalue(current) or issecretvalue(max)) then
            ClearForSecretMath()
            FinalizeSegmentedUpdate(nil, nil, true)
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
        FinalizeSegmentedUpdate(current, max, false)
        return
    end

    -- Generic segmented with max color: HolyPower, Chi, ArcaneCharges
    if IsUnitPowerSecret("player", powerType) or IsUnitPowerMaxSecret("player", powerType) then
        ClearForSecretMath()
        FinalizeSegmentedUpdate(nil, nil, true)
        return
    end

    local current = UnitPower("player", powerType)
    local max = UnitPowerMax("player", powerType)
    if issecretvalue and (issecretvalue(current) or issecretvalue(max)) then
        ClearForSecretMath()
        FinalizeSegmentedUpdate(nil, nil, true)
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
    FinalizeSegmentedUpdate(current, max, false)
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

local function UpdateCustomAuraBar(barInfo)
    local cabConfig = barInfo.cabConfig
    if not cabConfig or not cabConfig.spellID then return end

    -- Read aura data from viewer frame (applications may be secret in combat)
    local stacks = 0
    local applications = 0
    local auraPresent = false
    local durationObj
    local isActive = cabConfig.trackingMode == "active"
    local useDrain = isActive
    local needsDuration = useDrain or cabConfig.showDurationText
    local bar = barInfo.barType == "custom_continuous" and barInfo.frame or nil
    local auraPreview = bar and bar._barAuraActivePreview
    local pandemicPreview = bar and bar._pandemicPreview
    local indicatorPreview = isActive and (auraPreview or pandemicPreview)
    local viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(cabConfig.spellID)
    local auraUnit = viewerFrame and viewerFrame.auraDataUnit or "player"
    local instId = viewerFrame and viewerFrame.auraInstanceID
    if instId then
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(auraUnit, instId)
        if auraData then
            auraPresent = true
            applications = auraData.applications or 0
            if isActive then
                stacks = 1
            else
                stacks = applications
            end
            if needsDuration then
                durationObj = C_UnitAuras.GetAuraDuration(auraUnit, instId)
            end
        end
    end

    if indicatorPreview and not auraPresent then
        auraPresent = true
        applications = CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS
        stacks = 1
    end

    if isActive and bar then
        if auraPresent then
            bar._auraInstanceID = instId
            bar._auraUnit = auraUnit
        else
            bar._auraInstanceID = nil
            bar._auraUnit = nil
        end

        local inPandemic = false
        if pandemicPreview then
            inPandemic = true
        elseif auraPresent and cabConfig.showPandemicGlow == true and viewerFrame then
            local pi = viewerFrame.PandemicIcon
            if bar._pandemicGraceSuppressed then
                bar._pandemicGraceSuppressed = nil
                bar._pandemicGraceStart = nil
            elseif pi and pi:IsVisible() then
                inPandemic = true
                bar._pandemicGraceStart = nil
            elseif bar._inPandemic then
                local now = GetTime()
                if not bar._pandemicGraceStart then
                    bar._pandemicGraceStart = now
                end
                if now - bar._pandemicGraceStart <= 0.3 then
                    inPandemic = true
                else
                    bar._pandemicGraceStart = nil
                end
            end
        else
            bar._pandemicGraceStart = nil
            bar._pandemicGraceSuppressed = nil
        end
        bar._inPandemic = inPandemic or nil
    end

    -- Hide When Inactive: hide the bar frame when aura is absent.
    -- Independent bars are forced visible while unlocked so users can drag/place them.
    if cabConfig.hideWhenInactive then
        local forceVisibleForPlacement = barInfo._isIndependent and IsIndependentCustomAuraUnlocked(barInfo)
        local shouldShow = auraPresent or forceVisibleForPlacement or auraPreview or pandemicPreview
        local wasShown = barInfo.frame:IsShown()
        barInfo.frame:SetShown(shouldShow)
        if wasShown ~= shouldShow then
            if not barInfo._isIndependent then
                layoutDirty = true
            end
        end
        if not shouldShow then
            if isActive then
                UpdateCustomAuraBarIndicatorVisuals(barInfo, cabConfig, false)
            end
            return
        end
    end

    local maxStacks = cabConfig.maxStacks or 1
    local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)

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
                        bar.text:SetText(FormatTime(remaining, cabConfig.decimalTimers))
                    else
                        bar.text:SetText("")
                    end
                else
                    bar.text:SetFormattedText(cabConfig.decimalTimers and "%.1f" or "%.0f", remaining)
                end
            elseif indicatorPreview then
                bar.text:SetText(FormatTime(CUSTOM_AURA_BAR_EFFECT_PREVIEW_DURATION, cabConfig.decimalTimers))
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

------------------------------------------------------------------------
-- Styling: Custom aura bars
------------------------------------------------------------------------

local function StyleCustomAuraBar(barInfo, cabConfig)
    local barColor = cabConfig.barColor or {0.5, 0.5, 1}
    local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
    local thresholdColor = GetCustomAuraMaxThresholdColor(cabConfig)

    if barInfo.barType == "custom_continuous" then
        local bar = barInfo.frame
        bar.style = cabConfig
        local isVertical = bar._isVertical == true
        bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
        if bar.thresholdOverlay then
            bar.thresholdOverlay:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], 1)
            bar.thresholdOverlay:SetShown(thresholdEnabled)
        end

        -- Determine visibility for both text elements
        local isActive = cabConfig.trackingMode == "active"
        local showDuration = cabConfig.showDurationText == true
        local showStack = cabConfig.showStackText
        if showStack == nil then
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
    if powerType >= CUSTOM_AURA_BAR_BASE and powerType < CUSTOM_AURA_BAR_BASE + MAX_CUSTOM_AURA_BARS then
        if previewActive then
            barInfo.frame:Show()
        elseif barInfo.cabConfig and barInfo.cabConfig.hideWhenInactive then
            UpdateCustomAuraBar(barInfo)
        else
            barInfo.frame:Show()
            UpdateCustomAuraBar(barInfo)
        end
    else
        barInfo.frame:Show()
    end
end

local function HideUnusedResourceBarFrames(owner, firstHiddenIndex)
    for i = firstHiddenIndex, #resourceBarFrames do
        local barInfo = resourceBarFrames[i]
        if barInfo and barInfo.frame then
            owner:ClearIndependentCustomAuraRuntimeState(barInfo.frame)
            ClearCustomAuraBarIndicatorState(barInfo, true)
            ClearResourceAuraVisuals(barInfo.frame)
            ClearMaxStacksIndicator(barInfo)
            barInfo.frame:Hide()
            barInfo.cabConfig = nil
            barInfo.powerType = nil
            barInfo._isIndependent = nil
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
    powerType,
    customBars,
    settings,
    isVerticalLayout,
    reverseVerticalFill,
    effectiveWidth,
    effectiveHeight,
    segmentGap
)
    local cabIndex = powerType - CUSTOM_AURA_BAR_BASE + 1
    local cabConfig = customBars[cabIndex]
    local isActive = cabConfig.trackingMode == "active"
    local mode = isActive and "continuous" or (cabConfig.displayMode or "segmented")
    local maxStacks = isActive and 1 or (cabConfig.maxStacks or 1)
    local targetBarType = "custom_" .. mode
    local isIndependentCustomAura = IsCustomAuraBarIndependent(cabConfig)
    local customOrientation = isVerticalLayout and "vertical" or "horizontal"
    if isIndependentCustomAura then
        local independentOrientation = cabConfig.independentOrientation
        if independentOrientation == "vertical" or independentOrientation == "horizontal" then
            customOrientation = independentOrientation
        end
    end
    local customIsVertical = customOrientation == "vertical"
    local customReverseFill = false
    if customIsVertical then
        if isIndependentCustomAura then
            local fillDirection = cabConfig.independentVerticalFillDirection
            if fillDirection == "top_to_bottom" then
                customReverseFill = true
            elseif fillDirection == "bottom_to_top" then
                customReverseFill = false
            else
                customReverseFill = settings.verticalFillDirection == "top_to_bottom"
            end
        else
            customReverseFill = reverseVerticalFill
        end
    end
    local customWidth = effectiveWidth
    local customHeight = effectiveHeight
    if isIndependentCustomAura then
        local independentSize = cabConfig.independentSize
        customWidth = tonumber(independentSize and independentSize.width) or customWidth
        customHeight = tonumber(independentSize and independentSize.height) or customHeight
        if customWidth < 4 then
            customWidth = 4
        elseif customWidth > 1200 then
            customWidth = 1200
        end
        if customHeight < 4 then
            customHeight = 4
        elseif customHeight > 1200 then
            customHeight = 1200
        end
    end

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
            barInfo = { frame = bar, barType = "custom_continuous", powerType = powerType }
        elseif mode == "segmented" then
            local holder = CreateSegmentedBar(targetContainer, maxStacks)
            for si = 1, maxStacks do
                holder.segments[si]:SetMinMaxValues(si - 1, si)
            end
            barInfo = { frame = holder, barType = "custom_segmented", powerType = powerType }
        elseif mode == "overlay" then
            local half = math.ceil(maxStacks / 2)
            local holder = CreateOverlayBar(targetContainer, half)
            barInfo = { frame = holder, barType = "custom_overlay", powerType = powerType, halfSegments = half }
        end
    end

    if mode == "continuous" then
        EnsureCustomAuraContinuousThresholdOverlay(barInfo.frame)
    elseif mode == "segmented" then
        EnsureCustomAuraSegmentThresholdOverlays(barInfo.frame)
    elseif mode == "overlay" then
        EnsureCustomAuraOverlayThresholdOverlays(barInfo.frame, barInfo.halfSegments or math.ceil(maxStacks / 2))
    end

    barInfo.cabConfig = cabConfig
    barInfo.powerType = powerType
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
        local barTexture = CooldownCompanion:FetchStatusBar(settings.barTexture or "Solid")
        barInfo.frame:SetStatusBarTexture(barTexture)
        barInfo.frame:SetOrientation(customIsVertical and "VERTICAL" or "HORIZONTAL")
        barInfo.frame:SetReverseFill(customIsVertical and customReverseFill or false)
        barInfo.frame._isVertical = customIsVertical
        barInfo.frame._reverseFill = customReverseFill
        local bgc = settings.backgroundColor or { 0, 0, 0, 0.5 }
        barInfo.frame.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])
        local borderStyle = settings.borderStyle or "pixel"
        local borderColor = settings.borderColor or { 0, 0, 0, 1 }
        local borderSize = settings.borderSize or 1
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
        EnsureMaxStacksIndicator(barInfo)
        local indBorderStyle = settings.borderStyle or "pixel"
        local indBorderSize = settings.borderSize or 1
        local indBarTexture = CooldownCompanion:FetchStatusBar(settings.barTexture or "Solid")
        LayoutMaxStacksIndicator(barInfo, cabConfig, maxStacks, indBarTexture, indBorderStyle, indBorderSize)
    else
        ClearMaxStacksIndicator(barInfo)
    end

    return barInfo, isIndependentCustomAura
end

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
    return (a.powerType or 0) < (b.powerType or 0)
end

local function RelayoutBars()
    if not containerFrameAbove or not containerFrameBelow then return end
    local barSpacing = lastAppliedBarSpacing or 3.6
    local globalThickness = lastAppliedBarThickness or 12
    local primaryLength = lastAppliedPrimaryLength or 1
    local isVertical = lastAppliedOrientation == "vertical"

    if isVertical then
        local leftBars = {}
        local rightBars = {}
        for _, barInfo in ipairs(resourceBarFrames) do
            if barInfo and not barInfo._isIndependent and barInfo.frame and barInfo.frame:IsShown() then
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
            if barInfo and not barInfo._isIndependent and barInfo.frame and barInfo.frame:IsShown() then
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

    if isPreviewActive then return end

    local settings = GetResourceBarSettings()
    local auraActiveCache = {}

    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame and barInfo.frame:IsShown() then
            if barInfo.barType == "continuous" then
                UpdateContinuousBar(barInfo.frame, barInfo.powerType, settings, auraActiveCache)
            elseif barInfo.barType == "segmented" then
                UpdateSegmentedBar(barInfo.frame, barInfo.powerType, settings, auraActiveCache)
            elseif barInfo.barType == "mw_segmented" then
                UpdateMaelstromWeaponBar(barInfo.frame, settings, auraActiveCache)
            elseif barInfo.barType == "stagger_continuous" then
                UpdateStaggerBar(barInfo.frame, settings)
            elseif barInfo.barType == "custom_continuous"
                or barInfo.barType == "custom_segmented"
                or barInfo.barType == "custom_overlay" then
                UpdateCustomAuraBar(barInfo)
                if barInfo.barType == "custom_continuous" then
                    AnimateCustomAuraBarIndicator(barInfo.frame)
                end
            end
        elseif barInfo.frame and barInfo.cabConfig and barInfo.cabConfig.hideWhenInactive then
            -- Frame hidden by hideWhenInactive; still update so it can re-show when aura returns
            UpdateCustomAuraBar(barInfo)
            if barInfo.barType == "custom_continuous" then
                AnimateCustomAuraBarIndicator(barInfo.frame)
            end
        end
    end

    if layoutDirty then
        layoutDirty = false
        RelayoutBars()
        CooldownCompanion:RepositionCastBar()
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
                if not removedIDs and not updatedIDs then return end

                for _, barInfo in ipairs(resourceBarFrames) do
                    local bar = barInfo and barInfo.frame
                    local cabConfig = barInfo and barInfo.cabConfig
                    if barInfo and barInfo.barType == "custom_continuous"
                        and cabConfig and cabConfig.trackingMode == "active"
                        and bar and bar._auraInstanceID and bar._auraUnit == unit then
                        if removedIDs then
                            for _, instId in ipairs(removedIDs) do
                                if bar._auraInstanceID == instId then
                                    bar._auraInstanceID = nil
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
                    if barInfo and barInfo.barType == "custom_continuous"
                        and cabConfig and cabConfig.trackingMode == "active"
                        and bar and bar._auraUnit == "target" then
                        bar._auraInstanceID = nil
                        bar._inPandemic = nil
                        bar._pandemicGraceStart = nil
                        bar._pandemicGraceSuppressed = nil
                    end
                end
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
    local texName = settings.barTexture or "Solid"
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

    local bgc = settings.backgroundColor or { 0, 0, 0, 0.5 }
    bar.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])

    local borderStyle = settings.borderStyle or "pixel"
    local borderColor = settings.borderColor or { 0, 0, 0, 1 }
    local borderSize = settings.borderSize or 1

    if borderStyle == "pixel" then
        ApplyPixelBorders(bar.borders, bar, borderColor, borderSize)
    else
        HidePixelBorders(bar.borders)
    end

    -- Text setup
    local resourceConfig = settings.resources and settings.resources[powerType]
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

local function StyleSegmentedText(holder, powerType, settings)
    if not holder or not holder.text then return end
    if not IsSegmentedTextResource(powerType) then
        holder.text:SetShown(false)
        holder._textFormat = DEFAULT_RESOURCE_TEXT_FORMAT
        ClearSegmentedText(holder)
        return
    end

    local resourceConfig = settings.resources and settings.resources[powerType]
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
    -- All segmented types use their first color return as the initial segment color.
    -- UpdateSegmentedBar dynamically recolors per-segment each tick.
    local color = GetResourceColors(powerType, settings)
    for _, seg in ipairs(holder.segments) do
        seg:SetStatusBarColor(color[1], color[2], color[3], 1)
    end
    StyleSegmentedText(holder, powerType, settings)
end

function CooldownCompanion:ApplyResourceBars()
    local settings = GetResourceBarSettings()
    if not settings or not settings.enabled then
        self:RevertResourceBars()
        return
    end

    local isIndependentStack = settings.independentAnchorEnabled == true
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

    -- Append enabled custom aura bars
    local customBars = GetSpecCustomAuraBars(settings)
    for i = 1, MAX_CUSTOM_AURA_BARS do
        local cab = customBars[i]
        if cab and cab.enabled and cab.spellID
            and CooldownCompanion:IsTalentConditionMet(cab) then
            table.insert(filtered, CUSTOM_AURA_BAR_BASE + i - 1)
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
    local barSpacing = settings.barSpacing or 3.6
    lastAppliedBarSpacing = barSpacing
    lastAppliedBarThickness = globalBarThickness
    lastAppliedOrientation = GetResourceLayoutOrientation(settings)
    local segmentGap = settings.segmentGap or 4
    local totalPrimaryLength
    if isIndependentStack then
        EnsureIndependentStackConfig(settings)
        totalPrimaryLength = settings.independentWidth
    else
        totalPrimaryLength = GetResourcePrimaryLength(groupFrame, settings)
    end

    -- Determine side/order for each bar (per-spec layout)
    local layout = GetSpecLayoutOrder(settings)
    local sideList = {}
    local orderList = {}
    local fallbackOrder = 900
    for idx, powerType in ipairs(filtered) do
        local side, order
        if powerType >= CUSTOM_AURA_BAR_BASE then
            local slotIdx = powerType - CUSTOM_AURA_BAR_BASE + 1
            local cabConfig = customBars and customBars[slotIdx]
            if not IsCustomAuraBarIndependent(cabConfig) then
                local slotCfg = layout and layout.customAuraBarSlots and layout.customAuraBarSlots[slotIdx]
                if isVerticalLayout then
                    local storedHorizontalSide = (slotCfg and slotCfg.position) or "below"
                    side = (slotCfg and slotCfg.verticalPosition) or GetVerticalSideFallback(storedHorizontalSide)
                    order = (slotCfg and slotCfg.verticalOrder) or (slotCfg and slotCfg.order) or (fallbackOrder + idx)
                else
                    side = (slotCfg and slotCfg.position) or "below"
                    order = (slotCfg and slotCfg.order) or (fallbackOrder + idx)
                end
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
    HideUnusedResourceBarFrames(self, #filtered + 1)

    for idx, powerType in ipairs(filtered) do
        local isSegmented = SEGMENTED_TYPES[powerType]
        local barInfo = resourceBarFrames[idx]
        local firstSide = isVerticalLayout and "left" or "above"
        local targetContainer = sideList[idx] == firstSide and containerFrameAbove or containerFrameBelow

        -- Resolve per-bar thickness override
        local effectiveThickness = globalBarThickness
        if settings.customBarHeights then
            local thicknessKey = isVerticalLayout and "barWidth" or "barHeight"
            if powerType >= CUSTOM_AURA_BAR_BASE and powerType < CUSTOM_AURA_BAR_BASE + MAX_CUSTOM_AURA_BARS then
                local cabIdx = powerType - CUSTOM_AURA_BAR_BASE + 1
                local cab = customBars[cabIdx]
                if thicknessKey == "barWidth" then
                    effectiveThickness = (cab and (cab.barWidth or cab.barHeight)) or globalBarThickness
                else
                    effectiveThickness = (cab and (cab.barHeight or cab.barWidth)) or globalBarThickness
                end
            else
                local res = settings.resources and settings.resources[powerType]
                if thicknessKey == "barWidth" then
                    effectiveThickness = (res and (res.barWidth or res.barHeight)) or globalBarThickness
                else
                    effectiveThickness = (res and (res.barHeight or res.barWidth)) or globalBarThickness
                end
            end
        end
        local effectiveWidth = isVerticalLayout and effectiveThickness or totalPrimaryLength
        local effectiveHeight = isVerticalLayout and totalPrimaryLength or effectiveThickness

        if powerType == 101 then  -- Stagger
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

        elseif powerType >= CUSTOM_AURA_BAR_BASE and powerType < CUSTOM_AURA_BAR_BASE + MAX_CUSTOM_AURA_BARS then
            barInfo = PrepareCustomAuraBar(
                targetContainer,
                barInfo,
                powerType,
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

        local isIndependentCustomAura = false
        if powerType >= CUSTOM_AURA_BAR_BASE and powerType < CUSTOM_AURA_BAR_BASE + MAX_CUSTOM_AURA_BARS then
            local slotIdx = powerType - CUSTOM_AURA_BAR_BASE + 1
            local cabConfig = customBars and customBars[slotIdx]
            isIndependentCustomAura = IsCustomAuraBarIndependent(cabConfig)
        end

        barInfo._isIndependent = isIndependentCustomAura
        if isIndependentCustomAura then
            barInfo._side = nil
            barInfo._order = nil
            barInfo._effectiveThickness = nil
            self:ApplyIndependentCustomAuraPlacement(barInfo, barInfo.cabConfig, settings)
        else
            self:ClearIndependentCustomAuraRuntimeState(barInfo.frame)
            if barInfo.frame:GetParent() ~= targetContainer then
                barInfo.frame:SetParent(targetContainer)
            end
            barInfo._side = sideList[idx]
            barInfo._order = orderList[idx]
            barInfo._effectiveThickness = effectiveThickness
        end

        FinalizeAppliedBarVisibility(barInfo, powerType, isPreviewActive)
    end

    activeResources = filtered

    -- Layout: per-element positioning using side containers
    local gap = GetResourceAnchorGap(settings)
    lastAppliedPrimaryLength = totalPrimaryLength

    -- Anchor containers to anchor reference (group frame or independent wrapper)
    containerFrameAbove:ClearAllPoints()
    containerFrameBelow:ClearAllPoints()
    if isIndependentStack then
        -- Independent mode: create wrapper frame at saved position, anchor containers to it
        CreateIndependentWrapperFrame()
        local anchor = settings.independentAnchor
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

        UpdateIndependentStackDragState(settings)
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
        UpdateIndependentStackChrome(isVerticalLayout)
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
    elseif settings.inheritAlpha and groupFrame then
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
    lastAppliedBarSpacing = nil
    lastAppliedBarThickness = nil
    layoutDirty = false

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
            ClearIndependentRuntimeState(barInfo.frame)
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
    wipe(customAuraBarActivePreviewTokens)
    wipe(customAuraBarPandemicPreviewTokens)
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
            UpdateCustomAuraBar(barInfo)
            if barInfo.barType == "custom_continuous" then
                AnimateCustomAuraBarIndicator(barInfo.frame)
            end
            anyUpdated = true
        end
    end

    if anyUpdated and layoutDirty then
        layoutDirty = false
        RelayoutBars()
        CooldownCompanion:RepositionCastBar()
    end
end

function CooldownCompanion:PlayCustomAuraBarActivePreview(cabConfig, durationSeconds)
    if not cabConfig then return end

    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then duration = 3 end

    local token = (customAuraBarActivePreviewTokens[cabConfig] or 0) + 1
    customAuraBarActivePreviewTokens[cabConfig] = token

    RefreshCustomAuraBarPreviewState(cabConfig, "_barAuraActivePreview", true)

    C_Timer.After(duration, function()
        if customAuraBarActivePreviewTokens[cabConfig] ~= token then return end
        RefreshCustomAuraBarPreviewState(cabConfig, "_barAuraActivePreview", false)
    end)
end

function CooldownCompanion:PlayCustomAuraBarPandemicPreview(cabConfig, durationSeconds)
    if not cabConfig then return end

    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then duration = 3 end

    local token = (customAuraBarPandemicPreviewTokens[cabConfig] or 0) + 1
    customAuraBarPandemicPreviewTokens[cabConfig] = token

    RefreshCustomAuraBarPreviewState(cabConfig, "_pandemicPreview", true)

    C_Timer.After(duration, function()
        if customAuraBarPandemicPreviewTokens[cabConfig] ~= token then return end
        RefreshCustomAuraBarPreviewState(cabConfig, "_pandemicPreview", false)
    end)
end

function CooldownCompanion:GetResourceBarRuntimeDebugInfo()
    local info = {}
    for idx, barInfo in ipairs(resourceBarFrames) do
        local entry = {
            index = idx,
            powerType = barInfo.powerType,
            barType = barInfo.barType,
            shown = barInfo.frame and barInfo.frame:IsShown() or false,
            isIndependent = barInfo._isIndependent == true,
        }
        if barInfo.cabConfig and barInfo.cabConfig.spellID then
            entry.spellID = tonumber(barInfo.cabConfig.spellID) or barInfo.cabConfig.spellID
            entry.hideWhenInactive = barInfo.cabConfig.hideWhenInactive == true
        end
        info[#info + 1] = entry
    end
    return info
end

function CooldownCompanion:InitializeCustomAuraIndependentAnchor(slotIdx)
    local settings = GetResourceBarSettings()
    if not settings then return end

    local idx = tonumber(slotIdx)
    if not idx or idx < 1 or idx > MAX_CUSTOM_AURA_BARS then
        return
    end

    local customBars = GetSpecCustomAuraBars(settings)
    local cabConfig = customBars[idx]
    if type(cabConfig) ~= "table" then
        return
    end

    local hasAnchor = type(cabConfig.independentAnchor) == "table"
        and cabConfig.independentAnchor.x ~= nil
        and cabConfig.independentAnchor.y ~= nil
    local hasSize = type(cabConfig.independentSize) == "table"
        and tonumber(cabConfig.independentSize.width) ~= nil
        and tonumber(cabConfig.independentSize.height) ~= nil

    if hasAnchor and hasSize then
        EnsureCustomAuraIndependentConfig(cabConfig, settings)
        return
    end

    cabConfig.independentAnchorTargetMode = "group"
    if cabConfig.independentAnchorGroupId == nil then
        cabConfig.independentAnchorGroupId = CooldownCompanion:GetFirstAvailableAnchorGroup()
    end
    cabConfig.independentAnchor = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }
    if type(cabConfig.independentSize) ~= "table" then
        cabConfig.independentSize = {}
    end

    local powerType = CUSTOM_AURA_BAR_BASE + idx - 1
    local sourceFrame = nil
    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo and barInfo.powerType == powerType and barInfo.frame then
            sourceFrame = barInfo.frame
            break
        end
    end

    if sourceFrame then
        local width, height = sourceFrame:GetSize()
        cabConfig.independentSize.width = ClampIndependentDimension(width, 120)
        cabConfig.independentSize.height = ClampIndependentDimension(height, GetResourceGlobalThickness(settings))

        local targetFrame = ResolveIndependentAnchorTarget(cabConfig, settings)
        local cx, cy = sourceFrame:GetCenter()
        local tx, ty = targetFrame:GetCenter()
        if cx and cy and tx and ty then
            cabConfig.independentAnchor.x = RoundToTenths(cx - tx)
            cabConfig.independentAnchor.y = RoundToTenths(cy - ty)
        end
    else
        cabConfig.independentSize.width = ClampIndependentDimension(cabConfig.independentSize.width, 120)
        cabConfig.independentSize.height = ClampIndependentDimension(cabConfig.independentSize.height, GetResourceGlobalThickness(settings))
    end

    EnsureCustomAuraIndependentConfig(cabConfig, settings)
end

------------------------------------------------------------------------
-- Evaluate: central decision point
------------------------------------------------------------------------

function CooldownCompanion:EvaluateResourceBars()
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
        if not barInfo._isIndependent
            and barInfo.frame and barInfo.frame:IsShown()
            and barInfo._side == side
            and barInfo._order < upToOrder then
            if not best then
                best = barInfo
            elseif barInfo._order > best._order then
                best = barInfo
            elseif barInfo._order == best._order
                and (barInfo.powerType or 0) > (best.powerType or 0) then
                best = barInfo
            end
        end
    end

    return best and best.frame or nil
end

------------------------------------------------------------------------
-- Preview mode
------------------------------------------------------------------------

ApplyPreviewData = function()
    local settings = GetResourceBarSettings()

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

    for _, barInfo in ipairs(resourceBarFrames) do
        if barInfo.frame and barInfo.frame:IsShown() then
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
            elseif barInfo.barType == "segmented" then
                local n = #barInfo.frame.segments
                local filled = math_floor(n * 0.6)
                for i, seg in ipairs(barInfo.frame.segments) do
                    if i <= filled then
                        seg:SetValue(1)
                    elseif i == filled + 1 then
                        seg:SetValue(0.5)
                    else
                        seg:SetValue(0)
                    end
                end
                ApplyResourceAuraLanePreview(barInfo, 0.5)
                SetSegmentedText(barInfo.frame, filled + 0.5, n)
            elseif barInfo.barType == "stagger_continuous" then
                -- Preview at 45% stagger (yellow zone)
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
                -- Preview at 7 stacks (all 5 base full, 2 overlay full)
                local half = #barInfo.frame.segments
                local previewStacks = 7
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
                    barInfo.frame.text:SetText(FormatTime(12.3, cabConfig and cabConfig.decimalTimers))
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
                -- Max stacks indicator preview (continuous)
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
                -- Segments have MinMax(i-1, i); C-level clamping handles fill/empty
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
                -- Max stacks indicator preview (segmented)
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
                -- Max stacks indicator preview (overlay)
                if cabConfig and cabConfig.maxStacksGlowEnabled and barInfo._maxStacksIndicator then
                    barInfo._maxStacksIndicator:SetValue(maxStacks)
                end
            end
        end
    end
end

function CooldownCompanion:StartResourceBarPreview()
    isPreviewActive = true
    self:ApplyResourceBars()  -- ApplyPreviewData() called at end when isPreviewActive
end

function CooldownCompanion:StopResourceBarPreview()
    if not isPreviewActive then return end
    isPreviewActive = false
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
        if s.independentAnchorEnabled then return end  -- independent stack: width not tied to group
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
        if s.independentAnchorEnabled then return end  -- independent stack: width not tied to group
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
