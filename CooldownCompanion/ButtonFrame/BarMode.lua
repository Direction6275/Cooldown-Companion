--[[
    CooldownCompanion - ButtonFrame/BarMode
    Bar-mode button creation, styling, fill animation, and display updates
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic
local EntryRuntime = ST.EntryRuntime
local COOLDOWN_STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO

-- Localize frequently-used globals
local GetTime = GetTime
local pairs = pairs
local ipairs = ipairs
local unpack = unpack
local math_floor = math.floor
local math_ceil = math.ceil
local math_sin = math.sin
local math_pi = math.pi
local string_format = string.format
local table_concat = table.concat
local InCombatLockdown = InCombatLockdown

-- Imports from Helpers
local SetIconAreaPoints = ST._SetIconAreaPoints
local SetBarAreaPoints = ST._SetBarAreaPoints
local AnchorBarCountText = ST._AnchorBarCountText
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions
local ApplyIconTexCoord = ST._ApplyIconTexCoord
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior
local UsesChargeTextLane = CooldownCompanion.UsesChargeTextLane
local GetDurationSecretFormatSpec = CooldownCompanion.GetDurationSecretFormatSpec
local DEFAULT_BAR_AURA_COLOR = ST._DEFAULT_BAR_AURA_COLOR
local DEFAULT_BAR_PANDEMIC_COLOR = ST._DEFAULT_BAR_PANDEMIC_COLOR
local DEFAULT_BAR_CHARGE_COLOR = ST._DEFAULT_BAR_CHARGE_COLOR

-- Imports from VisualState
local ClearButtonVisualState = ST._ClearButtonVisualState
local AreButtonVisualStateSnapshotsEnabled = ST._AreButtonVisualStateSnapshotsEnabled

-- Pre-defined color constant tables to avoid per-tick allocation.
-- IMPORTANT: These tables are read-only — never write to their indices.
local DEFAULT_WHITE = {1, 1, 1, 1}
local DEFAULT_AURA_TEXT_COLOR = {0, 0.925, 1, 1}
local DEFAULT_BAR_COLOR = {0.2, 0.6, 1.0, 1.0}
local DEFAULT_READY_TEXT_COLOR = {0.2, 1.0, 0.2, 1.0}
local DEFAULT_CUSTOM_AURA_MAX_COLOR = {1, 0.84, 0, 1}

-- Imports from Glows
local CreateGlowContainer = ST._CreateGlowContainer
local SetBarAuraEffect = ST._SetBarAuraEffect
local IsBarAuraIndicatorEnabled = ST.IsBarAuraIndicatorEnabled

local function ResolveBarAuraIndicatorEnabled(style)
    if IsBarAuraIndicatorEnabled then
        return IsBarAuraIndicatorEnabled(style)
    end
    if not style then return false end
    if style.barAuraIndicatorEnabled ~= nil then
        return style.barAuraIndicatorEnabled == true
    end
    return (style.barAuraEffect or "none") ~= "none"
end

-- Imports from Visibility
local UpdateLossOfControl = ST._UpdateLossOfControl

-- Imports from Tracking
local UpdateIconTint = ST._UpdateIconTint
local EvaluateDesaturation = ST._EvaluateDesaturation

-- Shared click-through helpers from Utils.lua
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive
local ClearStatusBarMotion = ST.ClearStatusBarMotion
local SetStatusBarImmediateRange = ST.SetStatusBarImmediateRange
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue
local SetStatusBarSegmentedValue = ST.SetStatusBarSegmentedValue
local SetStatusBarElapsedDuration = ST.SetStatusBarElapsedDuration
local SetStatusBarRemainingDuration = ST.SetStatusBarRemainingDuration

local BAR_TEXT_UPDATE_INTERVAL = 0.1

local function IsCursorAnchoredButton(button)
    return button
        and CooldownCompanion.IsGroupCursorAnchored
        and CooldownCompanion:IsGroupCursorAnchored(button._groupId)
        or false
end

-- Shared helpers from ButtonFrame/Helpers.lua
local IsItemEquippable = CooldownCompanion.IsItemEquippable
local IsEntryItemLike = CooldownCompanion.IsEntryItemLike
local ResolveEffectiveItem = CooldownCompanion.ResolveEffectiveItem
local FormatTime = CooldownCompanion.FormatTime
local ApplyFontStyle = CooldownCompanion.ApplyFontStyle

-- Bar mode tooltip behavior: tooltip should come from hovering the icon area only.
local function SetBarIconTooltipScripts(button, enable)
    local iconBounds = button and button._iconBounds
    if not iconBounds then return end

    if enable then
        iconBounds:SetScript("OnEnter", function()
            local bd = button.buttonData
            if not bd then return end
            GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
            if bd.type == "spell" then
                GameTooltip:SetSpellByID(button._displaySpellId or bd.id)
            elseif IsEntryItemLike(bd) then
                local itemID = button._resolvedItemId or bd.id
                if itemID then
                    GameTooltip:SetItemByID(itemID)
                end
            end
            GameTooltip:Show()
        end)
        iconBounds:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    else
        iconBounds:SetScript("OnEnter", nil)
        iconBounds:SetScript("OnLeave", nil)
    end
end

local function ShouldStoreBarVisualState()
    return type(AreButtonVisualStateSnapshotsEnabled) == "function"
        and AreButtonVisualStateSnapshotsEnabled() == true
end

local function EnsureBarVisualTable(button, fieldName)
    local target = button[fieldName]
    if target then
        wipe(target)
    else
        target = {}
        button[fieldName] = target
    end
    return target
end

local function ClearBarVisualState(button)
    if button then
        button._barVisualIntent = nil
        button._barVisualApplied = nil
    end
end

local function StoreBarDisplayVisualState(button, details)
    local intent = EnsureBarVisualTable(button, "_barVisualIntent")
    intent.domain = details.domain
    intent.colorReason = details.colorReason
    intent.auraColorReason = details.auraColorReason
    intent.auraEffectActive = details.auraEffectActive == true
    intent.auraEffectReason = details.auraEffectReason
    intent.pulseActive = details.pulseMode ~= nil
    intent.pulseMode = details.pulseMode
    intent.colorShiftActive = details.colorShiftMode ~= nil
    intent.colorShiftMode = details.colorShiftMode
    intent.stackDisplay = details.stackDisplay == true
    intent.stackMode = details.stackMode
    intent.gcdSuppressed = button._barGCDSuppressed == true

    local applied = EnsureBarVisualTable(button, "_barVisualApplied")
    applied.colorReason = details.colorReason
    applied.auraEffectActive = button._barAuraEffectActive == true
    applied.pulseActive = button._barPulseActive == true
    applied.colorShiftActive = button._barColorShiftActive == true
    applied.gcdSuppressed = button._barGCDSuppressed == true
end

local function ResolveConditionalPreviewRemaining(button)
    local previewRemaining = button._conditionalPreviewRemaining
    local previewDuration = button._conditionalPreviewDuration
    if not (previewRemaining and previewDuration) then
        return previewRemaining, previewDuration
    end

    if button._conditionalPreviewLoop
        and button._conditionalPreviewLoopStartTime
        and button._conditionalPreviewLoopDuration
    then
        local loopDuration = button._conditionalPreviewLoopDuration
        if loopDuration > 0 then
            local now = GetTime()
            local elapsed = now - button._conditionalPreviewLoopStartTime
            if elapsed < 0 then
                elapsed = 0
            end
            local cycleElapsed = elapsed % loopDuration
            previewRemaining = loopDuration - cycleElapsed
            if previewRemaining > previewDuration then
                previewRemaining = previewDuration
            end
            button._conditionalPreviewRemaining = previewRemaining
            button._conditionalPreviewStartTime = now - (previewDuration - previewRemaining)
        end
        return previewRemaining, previewDuration
    end

    if button._conditionalPreviewStartTime then
        previewRemaining = previewDuration - (GetTime() - button._conditionalPreviewStartTime)
        if previewRemaining < 0 then previewRemaining = 0 end
        button._conditionalPreviewRemaining = previewRemaining
    end
    return previewRemaining, previewDuration
end

local function GetResourceBarVisuals()
    return ST._RB
end

local function GetBarAuraVisualSettings(button)
    local style = button.style or {}
    local settings = button._barAuraVisualSettings
    if not settings then
        settings = { displayProfiles = {} }
        button._barAuraVisualSettings = settings
    end

    settings.barTexture = style.barTexture or "Solid"
    settings.backgroundColor = style.barBgColor or {0.1, 0.1, 0.1, 0.8}
    settings.borderStyle = style.borderStyle or "pixel"
    settings.borderColor = style.borderColor or {0, 0, 0, 1}
    settings.borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE or 1
    settings.borderRenderMode = ST.GetBorderRenderMode(style)

    local RB = GetResourceBarVisuals()
    local specID = RB and RB.GetCurrentSpecID and RB.GetCurrentSpecID()
    if specID then
        local profile = settings.displayProfiles[specID]
        if not profile then
            profile = {}
            settings.displayProfiles[specID] = profile
        end
        profile.barTexture = settings.barTexture
        profile.backgroundColor = settings.backgroundColor
        profile.borderStyle = settings.borderStyle
        profile.borderColor = settings.borderColor
        profile.borderSize = settings.borderSize
        profile.borderRenderMode = settings.borderRenderMode
    end

    return settings
end

local function GetBarAuraStackColors(button)
    local auraBar = button.buttonData and button.buttonData.auraBar or nil
    local style = button.style or {}
    return style.barColor or DEFAULT_BAR_COLOR,
        (auraBar and auraBar.overlayColor) or DEFAULT_CUSTOM_AURA_MAX_COLOR,
        (auraBar and auraBar.thresholdMaxColor) or DEFAULT_CUSTOM_AURA_MAX_COLOR
end

local function BarAuraColorKey(color)
    if type(color) ~= "table" then
        return "nil"
    end
    return table_concat({
        tostring(color[1] or ""),
        tostring(color[2] or ""),
        tostring(color[3] or ""),
        tostring(color[4] or ""),
    }, ":")
end

local function HideBarAuraBaseFill(button)
    if not button or not button.statusBar then return end
    if button._barAuraBaseFillHidden then return end
    local texture = button.statusBar.GetStatusBarTexture and button.statusBar:GetStatusBarTexture()
    if texture then
        texture:SetAlpha(0)
    end
    button.statusBar:SetStatusBarColor(0, 0, 0, 0)
    if button.bg then
        button.bg:Hide()
    end
    if button.borderTextures then
        for _, textureFrame in ipairs(button.borderTextures) do
            textureFrame:Hide()
        end
    end
    button._barAuraBaseFillHidden = true
end

local function RestoreBarAuraBaseFill(button)
    if not (button and button.statusBar and button._barAuraBaseFillHidden) then return end
    button._barAuraBaseFillHidden = nil
    local texture = button.statusBar.GetStatusBarTexture and button.statusBar:GetStatusBarTexture()
    if texture then
        texture:SetAlpha(1)
    end
    button._barCdColor = nil
    button._barAuraColor = nil
    local style = button.style or {}
    local color = style.barColor or DEFAULT_BAR_COLOR
    button.statusBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
    if button.bg then
        button.bg:Show()
    end
    if button.borderTextures then
        for _, textureFrame in ipairs(button.borderTextures) do
            textureFrame:Show()
        end
    end
end

local function GetBarAuraStackSurface(button)
    return button and (button._barBounds or button.statusBar)
end

local function PositionBarAuraStackHolder(button, holder)
    if not (button and holder and button.statusBar) then return end
    local surface = GetBarAuraStackSurface(button)
    holder:SetParent(button)
    holder:ClearAllPoints()
    holder:SetAllPoints(surface or button.statusBar)
    holder:SetFrameLevel(button.statusBar:GetFrameLevel() + 1)
    holder._isVertical = button._isVertical == true
    holder._reverseFill = button.style and button.style.barReverseFill == true
end

local function ClearBarAuraStackVisual(button, keepIndicator)
    local RB = GetResourceBarVisuals()
    if not button then return end
    if not button._barAuraStackVisualActive and not button._barAuraBaseFillHidden then
        return
    end

    RestoreBarAuraBaseFill(button)
    button._barAuraStackVisualActive = nil
    button._barAuraStackVisualMode = nil
    button._barAuraStackLayoutKey = nil
    button._barAuraStackAppliedState = nil

    if button._barAuraStackSegments then
        button._barAuraStackSegments:Hide()
    end
    if button._barAuraStackOverlay then
        button._barAuraStackOverlay:Hide()
    end
    if button.statusBar and button.statusBar.thresholdOverlay then
        if RB and RB.ClearCustomAuraMaxBarEffects then
            RB.ClearCustomAuraMaxBarEffects(button.statusBar.thresholdOverlay)
        end
        button.statusBar.thresholdOverlay:Hide()
        SetStatusBarImmediateValue(button.statusBar.thresholdOverlay, 0)
    end
    if button._barAuraStackSegments and button._barAuraStackSegments.thresholdSegments
        and RB and RB.ClearCustomAuraMaxBarEffects then
        for _, segment in ipairs(button._barAuraStackSegments.thresholdSegments) do
            RB.ClearCustomAuraMaxBarEffects(segment)
        end
    end
    if button._barAuraStackOverlay and button._barAuraStackOverlay.thresholdSegments
        and RB and RB.ClearCustomAuraMaxBarEffects then
        for _, segment in ipairs(button._barAuraStackOverlay.thresholdSegments) do
            RB.ClearCustomAuraMaxBarEffects(segment)
        end
    end
    if button.statusBar then
        SetStatusBarImmediateRange(button.statusBar, 0, 1)
    end
    if not keepIndicator and RB and RB.ClearMaxStacksIndicator then
        if button._barAuraStackIndicatorInfo then
            RB.ClearMaxStacksIndicator(button._barAuraStackIndicatorInfo)
            button._barAuraStackIndicatorInfo._barAuraStackIndicatorKey = nil
        end
        if button._barAuraStackContinuousInfo then
            RB.ClearMaxStacksIndicator(button._barAuraStackContinuousInfo)
            button._barAuraStackContinuousInfo._barAuraStackIndicatorKey = nil
        end
    end
end

function CooldownCompanion:RefreshBarPanelAuraStackVisual(button)
    if not button then return end
    button._barAuraStackLayoutKey = nil
    button._barAuraStackAppliedState = nil
    if button._barAuraStackIndicatorInfo then
        button._barAuraStackIndicatorInfo._barAuraStackIndicatorKey = nil
    end
    if button._barAuraStackContinuousInfo then
        button._barAuraStackContinuousInfo._barAuraStackIndicatorKey = nil
    end
    button._barFillElapsed = button._barTextUpdateInterval or BAR_TEXT_UPDATE_INTERVAL
end

local function ClearBarAuraStackIndicatorInfo(info, RB)
    if not info then return end
    if RB and RB.ClearMaxStacksIndicator then
        RB.ClearMaxStacksIndicator(info)
    end
    info._barAuraStackIndicatorKey = nil
end

local function ReparentBarAuraStackIndicatorInfo(info, frame)
    if info and info._maxStacksIndicator and frame then
        info._maxStacksIndicator:SetParent(frame)
    end
end

local function CreateBarAuraStackSegment(holder, RB)
    local segment = CreateFrame("StatusBar", nil, holder)
    segment:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
    segment:SetMinMaxValues(0, 1)
    SetStatusBarImmediateValue(segment, 0)

    segment.bg = segment:CreateTexture(nil, "BACKGROUND")
    segment.bg:SetAllPoints()
    segment.bg:SetColorTexture(0, 0, 0, 0.5)

    segment.borders = RB and RB.CreatePixelBorders and RB.CreatePixelBorders(segment) or nil
    SetFrameClickThroughRecursive(segment, true, true)
    return segment
end

local function EnsureBarAuraSegmentCapacity(holder, count, RB)
    if not (holder and holder.segments) then return end
    for i = #holder.segments + 1, count do
        holder.segments[i] = CreateBarAuraStackSegment(holder, RB)
    end
    holder._activeSegments = count
    holder._numSegments = count
    for i, segment in ipairs(holder.segments) do
        segment:SetMinMaxValues(i - 1, i)
        if i > count then
            SetStatusBarImmediateValue(segment, 0)
            segment:Hide()
        end
    end
end

local function EnsureBarAuraOverlayCapacity(holder, halfSegments, RB)
    if not (holder and holder.segments and holder.overlaySegments) then return end
    for i = #holder.segments + 1, halfSegments do
        local segment = CreateBarAuraStackSegment(holder, RB)
        segment:SetMinMaxValues(i - 1, i)
        holder.segments[i] = segment

        local overlaySegment = CreateFrame("StatusBar", nil, holder)
        overlaySegment:SetFrameLevel(holder:GetFrameLevel() + 2)
        overlaySegment:SetStatusBarTexture(CooldownCompanion:FetchStatusBar("Solid"))
        overlaySegment:SetMinMaxValues(i + halfSegments - 1, i + halfSegments)
        SetStatusBarImmediateValue(overlaySegment, 0)
        SetFrameClickThroughRecursive(overlaySegment, true, true)
        holder.overlaySegments[i] = overlaySegment
    end
    holder._activeSegments = halfSegments
    for i, segment in ipairs(holder.segments) do
        segment:SetMinMaxValues(i - 1, i)
        if i > halfSegments then
            SetStatusBarImmediateValue(segment, 0)
            segment:Hide()
        end
    end
    for i, segment in ipairs(holder.overlaySegments) do
        segment:SetMinMaxValues(i + halfSegments - 1, i + halfSegments)
        if i > halfSegments then
            SetStatusBarImmediateValue(segment, 0)
            segment:Hide()
        end
    end
end

local function EnsureBarAuraStackVisual(button, mode, maxStacks)
    if mode == "continuous" then
        return nil
    end

    local RB = GetResourceBarVisuals()
    if not RB then return nil end

    if mode == "overlay" then
        local halfSegments = math_ceil(maxStacks / 2)
        if not button._barAuraStackOverlay then
            ClearBarAuraStackIndicatorInfo(button._barAuraStackIndicatorInfo, RB)
            local holder = RB.CreateOverlayBar and RB.CreateOverlayBar(button, halfSegments)
            if not holder then return nil end
            SetFrameClickThroughRecursive(holder, true, true)
            button._barAuraStackOverlay = holder
            button._barAuraStackLayoutKey = nil
        end
        if button._barAuraStackOverlaySegments ~= halfSegments then
            EnsureBarAuraOverlayCapacity(button._barAuraStackOverlay, halfSegments, RB)
            button._barAuraStackOverlaySegments = halfSegments
            button._barAuraStackLayoutKey = nil
        end
        PositionBarAuraStackHolder(button, button._barAuraStackOverlay)
        button._barAuraStackOverlay:Show()
        if button._barAuraStackSegments then
            button._barAuraStackSegments:Hide()
        end
        return button._barAuraStackOverlay
    end

    if not button._barAuraStackSegments then
        ClearBarAuraStackIndicatorInfo(button._barAuraStackIndicatorInfo, RB)
        local holder = RB.CreateSegmentedBar and RB.CreateSegmentedBar(button, maxStacks)
        if not holder then return nil end
        SetFrameClickThroughRecursive(holder, true, true)
        button._barAuraStackSegments = holder
        button._barAuraStackLayoutKey = nil
    end
    if button._barAuraStackSegmentsCount ~= maxStacks then
        EnsureBarAuraSegmentCapacity(button._barAuraStackSegments, maxStacks, RB)
        button._barAuraStackSegmentsCount = maxStacks
        button._barAuraStackLayoutKey = nil
    end
    PositionBarAuraStackHolder(button, button._barAuraStackSegments)
    button._barAuraStackSegments:Show()
    if button._barAuraStackOverlay then
        button._barAuraStackOverlay:Hide()
    end
    return button._barAuraStackSegments
end

local function GetBarAuraStackWidgetValue(value, valueAvailable)
    if valueAvailable then
        return value
    end
    return 0
end

local function ApplyBarAuraStackSegmentValues(segments, color, value, valueAvailable, segmentedSmoothing)
    if not segments then return end
    local widgetValue = GetBarAuraStackWidgetValue(value, valueAvailable)
    for _, segment in ipairs(segments) do
        segment:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
        SetStatusBarSegmentedValue(segment, widgetValue, segmentedSmoothing)
    end
end

local function ApplyBarAuraStackSegmentOnlyValues(segments, value, valueAvailable, segmentedSmoothing)
    if not segments then return end
    local widgetValue = GetBarAuraStackWidgetValue(value, valueAvailable)
    for _, segment in ipairs(segments) do
        SetStatusBarSegmentedValue(segment, widgetValue, segmentedSmoothing)
    end
end

local function ApplyBarAuraStackValuesOnly(button, mode, stackValue, valueAvailable)
    local widgetValue = GetBarAuraStackWidgetValue(stackValue, valueAvailable)
    local segmentedSmoothing = mode ~= "continuous" and CooldownCompanion:GetBarPanelAuraSegmentedSmoothing(button.buttonData) or nil
    if mode == "continuous" then
        SetStatusBarSmoothValue(button.statusBar, widgetValue)
        if button.statusBar.thresholdOverlay and button.statusBar.thresholdOverlay:IsShown() then
            SetStatusBarSmoothValue(button.statusBar.thresholdOverlay, widgetValue)
        end
    else
        local holder = mode == "overlay" and button._barAuraStackOverlay or button._barAuraStackSegments
        if not holder then return end
        ApplyBarAuraStackSegmentOnlyValues(holder.segments, stackValue, valueAvailable, segmentedSmoothing)
        if mode == "overlay" then
            ApplyBarAuraStackSegmentOnlyValues(holder.overlaySegments, stackValue, valueAvailable, segmentedSmoothing)
        end
        if holder.thresholdSegments then
            ApplyBarAuraStackSegmentOnlyValues(holder.thresholdSegments, stackValue, valueAvailable, segmentedSmoothing)
        end
    end

    local info = mode == "continuous" and button._barAuraStackContinuousInfo or button._barAuraStackIndicatorInfo
    if info and info._maxStacksIndicator then
        local RB = GetResourceBarVisuals()
        if mode == "continuous" then
            SetStatusBarSmoothValue(info._maxStacksIndicator, widgetValue)
        else
            SetStatusBarSegmentedValue(info._maxStacksIndicator, widgetValue, segmentedSmoothing)
        end
        if RB and RB.SetMaxStacksIndicatorActive then
            RB.SetMaxStacksIndicatorActive(info, valueAvailable == true)
        end
    end
end

local function BuildBarAuraStackLayoutKey(button, mode, maxStacks, width, height, gap, showThreshold)
    local style = button.style or {}
    local auraBar = button.buttonData and button.buttonData.auraBar or nil
    return table_concat({
        tostring(mode),
        tostring(maxStacks),
        tostring(width),
        tostring(height),
        tostring(gap),
        button._isVertical and "1" or "0",
        style.barReverseFill and "1" or "0",
        tostring(ST.GetEffectiveBarTextureName(style.barTexture or "Solid")),
        tostring(style.borderStyle or "pixel"),
        tostring(style.borderSize or ST.DEFAULT_BORDER_SIZE or 1),
        tostring(ST.GetBorderRenderMode(style)),
        BarAuraColorKey(style.barBgColor),
        BarAuraColorKey(style.borderColor),
        BarAuraColorKey(auraBar and auraBar.thresholdMaxColor),
        showThreshold and "1" or "0",
    }, "|")
end

local function BarAuraColorStateChanged(state, rKey, gKey, bKey, aKey, color)
    local r, g, b, a
    if type(color) == "table" then
        r, g, b, a = color[1], color[2], color[3], color[4]
    end
    return state[rKey] ~= r or state[gKey] ~= g or state[bKey] ~= b or state[aKey] ~= a
end

local function StoreBarAuraColorState(state, rKey, gKey, bKey, aKey, color)
    if type(color) == "table" then
        state[rKey], state[gKey], state[bKey], state[aKey] = color[1], color[2], color[3], color[4]
    else
        state[rKey], state[gKey], state[bKey], state[aKey] = nil, nil, nil, nil
    end
end

local function GetBarAuraStackSurfaceSize(button, mode)
    local surface = mode == "continuous" and button.statusBar or GetBarAuraStackSurface(button)
    local width = surface and surface:GetWidth() or button.statusBar:GetWidth() or 0
    local height = surface and surface:GetHeight() or button.statusBar:GetHeight() or 0
    return width, height
end

local function GetBarAuraStackVisualDirtyState(button, mode, maxStacks, stackValue, valueAvailable)
    local width, height = GetBarAuraStackSurfaceSize(button, mode)
    if width <= 0 or height <= 0 then
        return false, false, false
    end

    local style = button.style or {}
    local auraBar = button.buttonData and button.buttonData.auraBar or nil
    local RB = GetResourceBarVisuals()
    local stackBarColor, overlayColor, thresholdColor = GetBarAuraStackColors(button)
    local maxStackBarEffectsEnabled = auraBar and RB and RB.IsCustomAuraMaxBarEffectEnabled
        and RB.IsCustomAuraMaxBarEffectEnabled(auraBar)
    if maxStackBarEffectsEnabled and RB.GetCustomAuraMaxBarEffectColor then
        thresholdColor = RB.GetCustomAuraMaxBarEffectColor(auraBar)
    end
    local showThreshold = auraBar and (auraBar.thresholdColorEnabled == true or maxStackBarEffectsEnabled)
    local segmentedSmoothing = mode ~= "continuous" and CooldownCompanion:GetBarPanelAuraSegmentedSmoothing(button.buttonData) or nil
    local state = button._barAuraStackAppliedState
    local layoutDirty = state == nil
    if not state then
        state = {}
        button._barAuraStackAppliedState = state
    end

    local gap = CooldownCompanion:GetBarPanelAuraSegmentGap(button.buttonData)
    local effectiveBarTextureName = ST.GetEffectiveBarTextureName(style.barTexture or "Solid")
    layoutDirty = layoutDirty
        or state.mode ~= mode
        or state.maxStacks ~= maxStacks
        or state.width ~= width
        or state.height ~= height
        or state.gap ~= gap
        or state.isVertical ~= (button._isVertical == true)
        or state.reverseFill ~= (style.barReverseFill == true)
        or state.barTexture ~= effectiveBarTextureName
        or state.borderStyle ~= (style.borderStyle or "pixel")
        or state.borderSize ~= (style.borderSize or ST.DEFAULT_BORDER_SIZE or 1)
        or state.borderRenderMode ~= ST.GetBorderRenderMode(style)
        or state.showThreshold ~= showThreshold
        or state.segmentedSmoothing ~= segmentedSmoothing
        or state.maxStacksGlowEnabled ~= (auraBar and auraBar.maxStacksGlowEnabled == true)
        or state.maxStacksGlowStyle ~= (auraBar and auraBar.maxStacksGlowStyle or nil)
        or state.maxStacksGlowSize ~= (auraBar and auraBar.maxStacksGlowSize or nil)
        or state.maxStacksGlowSpeed ~= (auraBar and auraBar.maxStacksGlowSpeed or nil)
        or state.maxStacksGlowThickness ~= (auraBar and auraBar.maxStacksGlowThickness or nil)
        or state.maxStacksGlowLines ~= (auraBar and auraBar.maxStacksGlowLines or nil)
        or state.maxStacksBarPulseEnabled ~= (auraBar and auraBar.maxStacksBarPulseEnabled == true)
        or state.maxStacksBarPulseSpeed ~= (auraBar and auraBar.maxStacksBarPulseSpeed or nil)
        or state.maxStacksBarColorShiftEnabled ~= (auraBar and auraBar.maxStacksBarColorShiftEnabled == true)
        or state.maxStacksBarColorShiftSpeed ~= (auraBar and auraBar.maxStacksBarColorShiftSpeed or nil)
        or BarAuraColorStateChanged(state, "barBgR", "barBgG", "barBgB", "barBgA", style.barBgColor)
        or BarAuraColorStateChanged(state, "borderR", "borderG", "borderB", "borderA", style.borderColor)
        or BarAuraColorStateChanged(state, "stackR", "stackG", "stackB", "stackA", stackBarColor)
        or BarAuraColorStateChanged(state, "overlayR", "overlayG", "overlayB", "overlayA", overlayColor)
        or BarAuraColorStateChanged(state, "thresholdR", "thresholdG", "thresholdB", "thresholdA", thresholdColor)
        or BarAuraColorStateChanged(state, "glowR", "glowG", "glowB", "glowA", auraBar and auraBar.maxStacksGlowColor)
        or BarAuraColorStateChanged(state, "maxShiftR", "maxShiftG", "maxShiftB", "maxShiftA", auraBar and auraBar.maxStacksBarColorShiftColor)

    local stackValueIsSecret = valueAvailable and issecretvalue and issecretvalue(stackValue)
    local valueDirty = button._barAuraStackValueDirty == true
    if not valueAvailable then
        valueDirty = valueDirty or state.stackValueAvailable == true
    elseif stackValueIsSecret then
        valueDirty = true
    elseif not stackValueIsSecret and (state.stackValueAvailable ~= true or state.stackValue ~= stackValue) then
        valueDirty = true
    end
    if not layoutDirty and not valueDirty then
        return false, false, true
    end

    if layoutDirty then
        state.mode = mode
        state.maxStacks = maxStacks
        state.width = width
        state.height = height
        state.gap = gap
        state.isVertical = button._isVertical == true
        state.reverseFill = style.barReverseFill == true
        state.barTexture = effectiveBarTextureName
        state.borderStyle = style.borderStyle or "pixel"
        state.borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE or 1
        state.borderRenderMode = ST.GetBorderRenderMode(style)
        state.showThreshold = showThreshold
        state.segmentedSmoothing = segmentedSmoothing
        state.maxStacksGlowEnabled = auraBar and auraBar.maxStacksGlowEnabled == true
        state.maxStacksGlowStyle = auraBar and auraBar.maxStacksGlowStyle or nil
        state.maxStacksGlowSize = auraBar and auraBar.maxStacksGlowSize or nil
        state.maxStacksGlowSpeed = auraBar and auraBar.maxStacksGlowSpeed or nil
        state.maxStacksGlowThickness = auraBar and auraBar.maxStacksGlowThickness or nil
        state.maxStacksGlowLines = auraBar and auraBar.maxStacksGlowLines or nil
        state.maxStacksBarPulseEnabled = auraBar and auraBar.maxStacksBarPulseEnabled == true
        state.maxStacksBarPulseSpeed = auraBar and auraBar.maxStacksBarPulseSpeed or nil
        state.maxStacksBarColorShiftEnabled = auraBar and auraBar.maxStacksBarColorShiftEnabled == true
        state.maxStacksBarColorShiftSpeed = auraBar and auraBar.maxStacksBarColorShiftSpeed or nil
        StoreBarAuraColorState(state, "barBgR", "barBgG", "barBgB", "barBgA", style.barBgColor)
        StoreBarAuraColorState(state, "borderR", "borderG", "borderB", "borderA", style.borderColor)
        StoreBarAuraColorState(state, "stackR", "stackG", "stackB", "stackA", stackBarColor)
        StoreBarAuraColorState(state, "overlayR", "overlayG", "overlayB", "overlayA", overlayColor)
        StoreBarAuraColorState(state, "thresholdR", "thresholdG", "thresholdB", "thresholdA", thresholdColor)
        StoreBarAuraColorState(state, "glowR", "glowG", "glowB", "glowA", auraBar and auraBar.maxStacksGlowColor)
        StoreBarAuraColorState(state, "maxShiftR", "maxShiftG", "maxShiftB", "maxShiftA", auraBar and auraBar.maxStacksBarColorShiftColor)
    end

    state.stackValueAvailable = valueAvailable or false
    if valueAvailable and not stackValueIsSecret then
        state.stackValue = stackValue
    else
        state.stackValue = nil
    end

    return layoutDirty, valueDirty, true
end

local function LayoutBarAuraStackVisual(button, mode, maxStacks, stackValue, valueAvailable)
    local RB = GetResourceBarVisuals()
    if not RB then return end

    local auraBar = button.buttonData and button.buttonData.auraBar or nil
    local stackBarColor, overlayColor, thresholdColor = GetBarAuraStackColors(button)
    local maxStackBarEffectsEnabled = auraBar and RB.IsCustomAuraMaxBarEffectEnabled
        and RB.IsCustomAuraMaxBarEffectEnabled(auraBar)
    if maxStackBarEffectsEnabled and RB.GetCustomAuraMaxBarEffectColor then
        thresholdColor = RB.GetCustomAuraMaxBarEffectColor(auraBar)
    end
    local showThreshold = auraBar and (auraBar.thresholdColorEnabled == true or maxStackBarEffectsEnabled)
    local surface = mode == "continuous" and button.statusBar or GetBarAuraStackSurface(button)
    local width = surface and surface:GetWidth() or button.statusBar:GetWidth() or 0
    local height = surface and surface:GetHeight() or button.statusBar:GetHeight() or 0
    if width <= 0 or height <= 0 then
        return
    end

    button.statusBar._isVertical = button._isVertical == true
    button.statusBar._reverseFill = button.style and button.style.barReverseFill == true

    local settings = GetBarAuraVisualSettings(button)
    local segmentedSmoothing = mode ~= "continuous" and CooldownCompanion:GetBarPanelAuraSegmentedSmoothing(button.buttonData) or nil
    local orientation = button._isVertical and "vertical" or "horizontal"
    local reverseFill = button.style and button.style.barReverseFill == true
    local gap = CooldownCompanion:GetBarPanelAuraSegmentGap(button.buttonData)
    local barTexture = CooldownCompanion:FetchEffectiveBarTexture(button.style and button.style.barTexture or "Solid")
    local borderStyle = button.style and button.style.borderStyle or "pixel"
    local borderSize = button.style and button.style.borderSize or ST.DEFAULT_BORDER_SIZE or 1
    local borderRenderMode = ST.GetBorderRenderMode(button.style)
    local layoutKey = BuildBarAuraStackLayoutKey(button, mode, maxStacks, width, height, gap, showThreshold)
    local layoutChanged = button._barAuraStackLayoutKey ~= layoutKey

    if mode == "continuous" then
        if button._barAuraStackVisualMode ~= "continuous" then
            ClearBarAuraStackVisual(button, true)
            layoutChanged = true
        end
        button._barAuraStackVisualActive = true
        button._barAuraStackVisualMode = "continuous"
        SetStatusBarSmoothRange(button.statusBar, 0, maxStacks)
        SetStatusBarSmoothValue(button.statusBar, GetBarAuraStackWidgetValue(stackValue, valueAvailable))
        button.statusBar:SetStatusBarColor(stackBarColor[1], stackBarColor[2], stackBarColor[3], stackBarColor[4] or 1)
        if showThreshold and RB.EnsureCustomAuraContinuousThresholdOverlay and RB.LayoutCustomAuraContinuousThresholdOverlay then
            RB.EnsureCustomAuraContinuousThresholdOverlay(button.statusBar)
            if layoutChanged then
                RB.LayoutCustomAuraContinuousThresholdOverlay(button.statusBar, barTexture, borderStyle, borderSize, borderRenderMode)
            end
            local overlay = button.statusBar.thresholdOverlay
            if overlay then
                RB.SetCustomAuraMaxThresholdRange(overlay, maxStacks)
                overlay:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], thresholdColor[4] or 1)
                if maxStackBarEffectsEnabled and RB.ApplyCustomAuraMaxBarEffects then
                    RB.ApplyCustomAuraMaxBarEffects(overlay, auraBar, thresholdColor)
                elseif RB.ClearCustomAuraMaxBarEffects then
                    RB.ClearCustomAuraMaxBarEffects(overlay, thresholdColor)
                end
                SetStatusBarSmoothValue(overlay, GetBarAuraStackWidgetValue(stackValue, valueAvailable))
                overlay:Show()
            end
        elseif button.statusBar.thresholdOverlay then
            if RB.ClearCustomAuraMaxBarEffects then
                RB.ClearCustomAuraMaxBarEffects(button.statusBar.thresholdOverlay, thresholdColor)
            end
            button.statusBar.thresholdOverlay:Hide()
            SetStatusBarImmediateValue(button.statusBar.thresholdOverlay, 0)
        end
        button._barAuraStackLayoutKey = layoutKey
        return
    end

    local holder = EnsureBarAuraStackVisual(button, mode, maxStacks)
    if not holder then return end
    button._barAuraStackVisualActive = true
    button._barAuraStackVisualMode = mode
    HideBarAuraBaseFill(button)
    if button.statusBar.thresholdOverlay then
        if RB.ClearCustomAuraMaxBarEffects then
            RB.ClearCustomAuraMaxBarEffects(button.statusBar.thresholdOverlay, thresholdColor)
        end
        button.statusBar.thresholdOverlay:Hide()
        SetStatusBarImmediateValue(button.statusBar.thresholdOverlay, 0)
    end
    holder._isVertical = button._isVertical == true
    holder._reverseFill = reverseFill

    if mode == "overlay" then
        local halfSegments = math_ceil(maxStacks / 2)
        if layoutChanged then
            if showThreshold and RB.EnsureCustomAuraOverlayThresholdOverlays then
                RB.EnsureCustomAuraOverlayThresholdOverlays(holder, halfSegments)
            end
            if RB.LayoutOverlaySegments then
                RB.LayoutOverlaySegments(holder, width, height, gap, settings, halfSegments, orientation, reverseFill)
            end
        end
        ApplyBarAuraStackSegmentValues(holder.segments, stackBarColor, stackValue, valueAvailable, segmentedSmoothing)
        ApplyBarAuraStackSegmentValues(holder.overlaySegments, overlayColor, stackValue, valueAvailable, segmentedSmoothing)
    else
        if layoutChanged then
            if showThreshold and RB.EnsureCustomAuraSegmentThresholdOverlays then
                RB.EnsureCustomAuraSegmentThresholdOverlays(holder)
            end
            if RB.LayoutSegments then
                RB.LayoutSegments(holder, width, height, gap, settings, orientation, reverseFill)
            end
        end
        ApplyBarAuraStackSegmentValues(holder.segments, stackBarColor, stackValue, valueAvailable, segmentedSmoothing)
    end

    if holder.thresholdSegments then
        for _, segment in ipairs(holder.thresholdSegments) do
            if showThreshold and RB.SetCustomAuraMaxThresholdRange then
                if layoutChanged then
                    RB.SetCustomAuraMaxThresholdRange(segment, maxStacks)
                    segment:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], thresholdColor[4] or 1)
                end
                if maxStackBarEffectsEnabled and RB.ApplyCustomAuraMaxBarEffects then
                    RB.ApplyCustomAuraMaxBarEffects(segment, auraBar, thresholdColor)
                elseif RB.ClearCustomAuraMaxBarEffects then
                    RB.ClearCustomAuraMaxBarEffects(segment, thresholdColor)
                end
                SetStatusBarSegmentedValue(segment, GetBarAuraStackWidgetValue(stackValue, valueAvailable), segmentedSmoothing)
                segment:Show()
            elseif layoutChanged then
                if RB.ClearCustomAuraMaxBarEffects then
                    RB.ClearCustomAuraMaxBarEffects(segment, thresholdColor)
                end
                SetStatusBarImmediateValue(segment, 0)
                segment:Hide()
            end
        end
    end
    button._barAuraStackLayoutKey = layoutKey
end

local function BuildBarAuraStackIndicatorKey(button, info, glowConfig, mode, maxStacks)
    local style = button.style or {}
    return table_concat({
        tostring(mode),
        tostring(info and info.frame),
        tostring(maxStacks),
        tostring(glowConfig.maxStacksGlowStyle or "solidBorder"),
        BarAuraColorKey(glowConfig.maxStacksGlowColor),
        tostring(glowConfig.maxStacksGlowSize or 2),
        tostring(glowConfig.maxStacksGlowSpeed or 0.5),
        tostring(glowConfig.maxStacksGlowThickness or 4),
        tostring(glowConfig.maxStacksGlowLines or 8),
        tostring(glowConfig.maxStacksBarPulseEnabled == true),
        tostring(glowConfig.maxStacksBarPulseSpeed or 0.5),
        tostring(glowConfig.maxStacksBarColorShiftEnabled == true),
        tostring(glowConfig.maxStacksBarColorShiftSpeed or 0.5),
        BarAuraColorKey(glowConfig.maxStacksBarColorShiftColor),
        tostring(ST.GetEffectiveBarTextureName(style.barTexture or "Solid")),
        tostring(style.borderStyle or "pixel"),
        tostring(style.borderSize or ST.DEFAULT_BORDER_SIZE or 1),
        tostring(ST.GetBorderRenderMode(style)),
    }, "|")
end

local function UpdateBarAuraStackIndicator(button, mode, maxStacks, stackValue, stackValueAvailable)
    local RB = GetResourceBarVisuals()
    if not (RB and RB.EnsureMaxStacksIndicator and RB.LayoutMaxStacksIndicator and RB.ClearMaxStacksIndicator) then
        return
    end

    local auraBar = button.buttonData and button.buttonData.auraBar or nil
    if not (auraBar and auraBar.maxStacksGlowEnabled == true) then
        if button._barAuraStackIndicatorInfo then
            ClearBarAuraStackIndicatorInfo(button._barAuraStackIndicatorInfo, RB)
        end
        if button._barAuraStackContinuousInfo then
            ClearBarAuraStackIndicatorInfo(button._barAuraStackContinuousInfo, RB)
        end
        return
    end

    local frame = mode == "continuous" and button.statusBar
        or (mode == "overlay" and button._barAuraStackOverlay or button._barAuraStackSegments)
    if not frame then return end

    local info
    if mode == "continuous" then
        button._barAuraStackContinuousInfo = button._barAuraStackContinuousInfo or { frame = button.statusBar }
        if button._barAuraStackContinuousInfo.frame ~= button.statusBar then
            ClearBarAuraStackIndicatorInfo(button._barAuraStackContinuousInfo, RB)
        end
        button._barAuraStackContinuousInfo.frame = button.statusBar
        ReparentBarAuraStackIndicatorInfo(button._barAuraStackContinuousInfo, button.statusBar)
        info = button._barAuraStackContinuousInfo
        if button._barAuraStackIndicatorInfo then
            ClearBarAuraStackIndicatorInfo(button._barAuraStackIndicatorInfo, RB)
        end
    else
        button._barAuraStackIndicatorInfo = button._barAuraStackIndicatorInfo or { frame = frame }
        if button._barAuraStackIndicatorInfo.frame ~= frame then
            ClearBarAuraStackIndicatorInfo(button._barAuraStackIndicatorInfo, RB)
        end
        button._barAuraStackIndicatorInfo.frame = frame
        ReparentBarAuraStackIndicatorInfo(button._barAuraStackIndicatorInfo, frame)
        info = button._barAuraStackIndicatorInfo
        if button._barAuraStackContinuousInfo then
            ClearBarAuraStackIndicatorInfo(button._barAuraStackContinuousInfo, RB)
        end
    end

    local glowConfig = auraBar
    local barTexture = CooldownCompanion:FetchEffectiveBarTexture(button.style and button.style.barTexture or "Solid")
    local borderStyle = button.style and button.style.borderStyle or "pixel"
    local borderSize = button.style and button.style.borderSize or ST.DEFAULT_BORDER_SIZE or 1
    local borderRenderMode = ST.GetBorderRenderMode(button.style)
    local frameTreatmentStyle = RB.GetMaxStacksFrameTreatmentStyle and RB.GetMaxStacksFrameTreatmentStyle(glowConfig) or "solidBorder"

    if frameTreatmentStyle ~= "none" then
        RB.EnsureMaxStacksIndicator(info)
    end

    local indicatorKey = BuildBarAuraStackIndicatorKey(button, info, glowConfig, mode, maxStacks)
    if info._barAuraStackIndicatorKey ~= indicatorKey then
        if info._maxStacksIndicator then
            RB.LayoutMaxStacksIndicator(
                info,
                glowConfig,
                maxStacks,
                barTexture,
                borderStyle,
                borderSize,
                borderRenderMode
            )
        end
        if frameTreatmentStyle == "none" then
            RB.ClearMaxStacksIndicator(info)
        end
        info._barAuraStackIndicatorKey = indicatorKey
    end

    local indicatorValue = GetBarAuraStackWidgetValue(stackValue, stackValueAvailable)
    if info._maxStacksIndicator then
        local segmentedSmoothing = mode ~= "continuous" and CooldownCompanion:GetBarPanelAuraSegmentedSmoothing(button.buttonData) or nil
        if mode == "continuous" then
            SetStatusBarSmoothValue(info._maxStacksIndicator, indicatorValue)
        else
            SetStatusBarSegmentedValue(info._maxStacksIndicator, indicatorValue, segmentedSmoothing)
        end
        if RB.SetMaxStacksIndicatorActive then
            RB.SetMaxStacksIndicatorActive(info, stackValueAvailable == true)
        end
    end
end

local function ApplyBarAuraStackVisual(button, stackValue, stackValueAvailable)
    local maxStacks = button._barAuraStackMax or 1
    local mode = button._barAuraStackMode or "segmented"
    local widgetValue = GetBarAuraStackWidgetValue(stackValue, stackValueAvailable)
    local layoutDirty, valueDirty, canUpdate = GetBarAuraStackVisualDirtyState(button, mode, maxStacks, widgetValue, stackValueAvailable)
    if not canUpdate then
        button._barAuraStackAppliedState = nil
        return
    end

    if layoutDirty then
        if mode == "continuous" then
            LayoutBarAuraStackVisual(button, "continuous", maxStacks, widgetValue, stackValueAvailable)
        else
            SetStatusBarImmediateRange(button.statusBar, 0, 1)
            SetStatusBarImmediateValue(button.statusBar, 0)
            LayoutBarAuraStackVisual(button, mode, maxStacks, widgetValue, stackValueAvailable)
        end
        UpdateBarAuraStackIndicator(button, mode, maxStacks, widgetValue, stackValueAvailable)
        button._barAuraStackValueDirty = nil
    elseif valueDirty then
        ApplyBarAuraStackValuesOnly(button, mode, widgetValue, stackValueAvailable)
        button._barAuraStackValueDirty = nil
    end
end

-- Lightweight OnUpdate: keeps time text fresh while native StatusBar timers drive fill motion.
local function SetBarTimeText(button, text)
    if button._lastBarTimeText ~= text then
        button._lastBarTimeText = text
        button.timeText:SetText(text)
    end
end

local function SetBarTimeFormattedText(button, fmt, value)
    button._lastBarTimeText = nil
    button.timeText:SetFormattedText(fmt, value)
end

local function UpdateBarFill(button)
    -- Single-bar path
    -- DurationObjects are handed to StatusBar:SetTimerDuration so drain/fill motion
    -- is engine-driven instead of re-sampled as Lua percentages.
    -- HasSecretValues gates expiry detection and time text formatting.
    -- Items use stored C_Item.GetItemCooldown values (_itemCdStart/_itemCdDuration).
    local onCooldown = false
    local itemRemaining = 0
    local previewRemaining, previewDuration = ResolveConditionalPreviewRemaining(button)

    local auraDurationTextPreview = button._conditionalAuraDurationTextPreview == true

    if previewRemaining and previewRemaining > 0 and not button._barGCDSuppressed then
        ClearBarAuraStackVisual(button)
        onCooldown = true
        SetStatusBarSmoothRange(button.statusBar, 0, 1)
        previewDuration = previewDuration or previewRemaining
        if previewDuration <= 0 then
            previewDuration = previewRemaining
        end
        local frac
        if button._conditionalPreviewDomain == "aura" or button._conditionalPreviewDomain == "aura_text" then
            frac = previewRemaining / previewDuration
        else
            frac = 1 - (previewRemaining / previewDuration)
        end
        if frac < 0 then frac = 0 end
        if frac > 1 then frac = 1 end
        SetStatusBarSmoothValue(button.statusBar, frac)
    elseif button._barAuraStackDisplay then
        onCooldown = true
        if not button._barAuraStackValueSecret then
            ApplyBarAuraStackVisual(button, button._barAuraStackValue, button._barAuraStackValueAvailable == true)
        end
        SetBarTimeText(button, "")
    elseif button._durationObj and not button._barGCDSuppressed then
        ClearBarAuraStackVisual(button)
        onCooldown = true
        SetStatusBarSmoothRange(button.statusBar, 0, 1)
        if button._auraActive then
            if not SetStatusBarRemainingDuration(button.statusBar, button._durationObj) then
                SetStatusBarSmoothValue(button.statusBar, button._durationObj:GetRemainingPercent())   -- drain: 1->0
            end
        else
            if not SetStatusBarElapsedDuration(button.statusBar, button._durationObj) then
                SetStatusBarSmoothValue(button.statusBar, button._durationObj:GetElapsedPercent())     -- fill: 0->1
            end
        end
    elseif button._viewerBar and button._auraActive and not button._barGCDSuppressed then
        ClearBarAuraStackVisual(button)
        -- Totem/guardian: mirror viewer's BuffBar StatusBar (secret pass-through).
        -- Blizzard fills viewerFrame.Bar with SetMinMaxValues(0, duration) and
        -- SetValue(remaining) each frame.  Both GetValue and GetMinMaxValues
        -- return secret values when set with secrets — no arithmetic needed.
        local viewerBar = button._viewerBar
        if viewerBar:IsVisible() then
            onCooldown = true
            local _, maxVal = viewerBar:GetMinMaxValues()
            SetStatusBarSmoothRange(button.statusBar, 0, maxVal)
            SetStatusBarSmoothValue(button.statusBar, viewerBar:GetValue())
        end
    elseif button._cooldownDeferred then
        ClearBarAuraStackVisual(button)
        -- Deferred cooldown (timer hasn't started): show as "on cooldown"
        -- with a static full bar (no animation, no time text).
        onCooldown = true
        SetStatusBarImmediateRange(button.statusBar, 0, 1)
        SetStatusBarImmediateValue(button.statusBar, 0)
    elseif IsEntryItemLike(button.buttonData) then
        ClearBarAuraStackVisual(button)
        -- Items: use stored C_Item.GetItemCooldown values (avoids hidden-widget staleness)
        SetStatusBarSmoothRange(button.statusBar, 0, 1)
        local startMs = (button._itemCdStart or 0) * 1000
        local durationMs = (button._itemCdDuration or 0) * 1000
        local now = GetTime() * 1000
        onCooldown = durationMs > 0
        if onCooldown and button._barGCDSuppressed then onCooldown = false end
        if onCooldown then
            local elapsed = now - startMs
            itemRemaining = (durationMs - elapsed) / 1000
            if button._auraActive then
                local frac = 1 - (elapsed / durationMs)
                if frac < 0 then frac = 0 end
                SetStatusBarSmoothValue(button.statusBar, frac)
            else
                local frac = elapsed / durationMs
                if frac > 1 then frac = 1 end
                SetStatusBarSmoothValue(button.statusBar, frac)
            end
        end
    end

    if onCooldown then
        local showTimeText = not button._barAuraStackDisplay and ((button._auraActive or auraDurationTextPreview)
            and (button.style.showAuraText ~= false)
            or (not button._auraActive and not auraDurationTextPreview and button.style.showCooldownText))
        if showTimeText then
            -- Switch font/color when mode changes
            local mode = (button._auraActive or auraDurationTextPreview) and "aura" or "cd"
            if button._barTextMode ~= mode then
                button._barTextMode = mode
                button._barTextColorDirty = true
                if button._auraActive or auraDurationTextPreview then
                    local f = CooldownCompanion:FetchFont(button.style.auraTextFont or "Friz Quadrata TT")
                    local s = button.style.auraTextFontSize or 12
                    local o = ST.GetEffectiveFontOutline(button.style.auraTextFontOutline or "OUTLINE")
                    button.timeText:SetFont(f, s, o)
                else
                    local f = CooldownCompanion:FetchFont(button.style.cooldownFont or "Friz Quadrata TT")
                    local s = button.style.cooldownFontSize or 12
                    local o = ST.GetEffectiveFontOutline(button.style.cooldownFontOutline or "OUTLINE")
                    button.timeText:SetFont(f, s, o)
                end
            end
            if button._barTextColorDirty then
                button._barTextColorDirty = nil
                local cc = (button._auraActive or auraDurationTextPreview)
                    and (button.style.auraTextFontColor or DEFAULT_AURA_TEXT_COLOR)
                    or (button.style.cooldownFontColor or DEFAULT_WHITE)
                button.timeText:SetTextColor(cc[1], cc[2], cc[3], cc[4])
            end
            -- Time text: HasSecretValues() returns a non-secret boolean.
            -- Non-secret: full duration-format examples ("1:30", "45", "8.7", etc.)
            -- Secret: pass the secret number through C++ SetFormattedText with the closest specifier.
            local durationStyle = button.style
            local secretFormatSpec = GetDurationSecretFormatSpec(durationStyle)
            if previewRemaining and previewRemaining > 0 then
                SetBarTimeText(button, FormatTime(previewRemaining, durationStyle))
            elseif button._durationObj then
                local remaining = button._durationObj:GetRemainingDuration()
                if not button._durationObj:HasSecretValues() then
                    if remaining > 0 then
                        SetBarTimeText(button, FormatTime(remaining, durationStyle))
                    else
                        SetBarTimeText(button, "")
                    end
                else
                    SetBarTimeFormattedText(button, secretFormatSpec, remaining)
                end
            elseif button._viewerBar then
                -- Totem: viewer bar values may be secret (set by Blizzard's internal totem tracking).
                -- HasSecretValues() on the viewer StatusBar is unreliable (Blizzard's
                -- secure code sets it, so the widget reports plain — but the actual
                -- number returned by GetValue() is a secret wrapper).
                -- Always use SetFormattedText for secret-safe pass-through.
                SetBarTimeFormattedText(button, secretFormatSpec, button._viewerBar:GetValue())
            else
                if itemRemaining > 0 then
                    SetBarTimeText(button, FormatTime(itemRemaining, durationStyle))
                else
                    SetBarTimeText(button, "")
                end
            end
        end
    else
        ClearBarAuraStackVisual(button)
        -- Restore 0-1 range if exiting viewer bar pass-through
        if button._viewerBar then
            SetStatusBarImmediateRange(button.statusBar, 0, 1)
            button._viewerBar = nil
        end
        if button._barAuraActivePreview or button._conditionalBarAuraActivePreview then
            SetStatusBarImmediateValue(button.statusBar, 1)
            SetBarTimeText(button, "")
        elseif button.buttonData.isPassive then
            SetStatusBarImmediateValue(button.statusBar, 0)
            SetBarTimeText(button, "")
        else
            SetStatusBarImmediateValue(button.statusBar, 1)
            if button.style.showBarReadyText then
                if button._barTextMode ~= "ready" then
                    button._barTextMode = "ready"
                    local f = CooldownCompanion:FetchFont(button.style.barReadyFont or "Friz Quadrata TT")
                    local s = button.style.barReadyFontSize or 12
                    local o = ST.GetEffectiveFontOutline(button.style.barReadyFontOutline or "OUTLINE")
                    button.timeText:SetFont(f, s, o)
                end
                SetBarTimeText(button, button.style.barReadyText or "Ready")
            else
                SetBarTimeText(button, "")
            end
        end
    end
end

local function ApplyBarCountTextStyle(button, style)
    if not button or not button.count then return end
    local buttonData = button.buttonData
    local showIcon = style.showBarIcon ~= false
    local defAnchor = showIcon and "BOTTOMRIGHT" or "BOTTOM"
    local defXOff = showIcon and -2 or 0
    local defYOff = 2
    local useChargeTextLane = buttonData
        and UsesChargeTextLane(buttonData)
        and not (button and button._barAuraStackDisplay)

    if useChargeTextLane then
        ApplyFontStyle(button.count, style, "charge")
        local chargeAnchor, chargeXOffset, chargeYOffset
        if showIcon then
            chargeAnchor = style.chargeAnchor or defAnchor
            chargeXOffset = style.chargeXOffset or defXOff
            chargeYOffset = style.chargeYOffset or defYOff
        else
            chargeAnchor = "CENTER"
            chargeXOffset = 0
            chargeYOffset = 0
        end
        AnchorBarCountText(button, showIcon, chargeAnchor, chargeXOffset, chargeYOffset)
    elseif buttonData and buttonData.type == "item" and not IsItemEquippable(buttonData) then
        ApplyFontStyle(button.count, buttonData, "itemCount")
        local itemAnchor = buttonData.itemCountAnchor or defAnchor
        local itemXOffset = buttonData.itemCountXOffset or defXOff
        local itemYOffset = buttonData.itemCountYOffset or defYOff
        AnchorBarCountText(button, showIcon, itemAnchor, itemXOffset, itemYOffset)
    else
        AnchorBarCountText(button, showIcon, defAnchor, defXOff, defYOff)
    end
    button._countTextLaneStyled = useChargeTextLane or false
end

-- Update bar-specific display elements (colors, desaturation, aura effects).
-- Bar fill + time text are handled by the per-button OnUpdate for smooth interpolation.
local function UpdateBarDisplay(button)
    local style = button.style
    local shouldStoreBarVisualState = ShouldStoreBarVisualState()
    if not shouldStoreBarVisualState and (button._barVisualIntent or button._barVisualApplied) then
        ClearBarVisualState(button)
    end

    -- "On cooldown" for bar color/ready text follows canonical state.
    -- _durationObj may also hold aura/totem timing and must not imply cooldown.
    local itemUsesResolvedCooldownState = IsEntryItemLike(button.buttonData)
        and button._resolvedItemQuantityKind == "stacks"
    local barAuraStackDisplay = button._barAuraStackDisplay == true
    local stackSegmentLayerActive = barAuraStackDisplay and button._barAuraStackMode ~= "continuous"
    local isChargeButton = UsesChargeBehavior(button.buttonData) and not barAuraStackDisplay
    local chargeState = button._chargeState
    local auraTimerActive = barAuraStackDisplay or button._auraActive
        and (button._durationObj or button._viewerBar or button._conditionalPreviewRemaining)
    local onCooldown
    if itemUsesResolvedCooldownState then
        onCooldown = button._cooldownState == COOLDOWN_STATE_COOLDOWN
    elseif isChargeButton then
        onCooldown = chargeState == CHARGE_STATE_MISSING
            or chargeState == CHARGE_STATE_ZERO
    else
        onCooldown = button._cooldownState == COOLDOWN_STATE_COOLDOWN
    end

    -- Time text color: switch between cooldown and ready colors
    local wantReadyTextColor = not onCooldown and not auraTimerActive and style.showBarReadyText
    if button._barReadyTextColor ~= wantReadyTextColor then
        button._barReadyTextColor = wantReadyTextColor
        if wantReadyTextColor then
            local rc = style.barReadyTextColor or DEFAULT_READY_TEXT_COLOR
            button.timeText:SetTextColor(rc[1], rc[2], rc[3], rc[4])
        else
            local cc = style.cooldownFontColor or DEFAULT_WHITE
            button.timeText:SetTextColor(cc[1], cc[2], cc[3], cc[4])
        end
    end

    -- Bar color: switch between ready, cooldown, and partial charge colors.
    -- Aura-tracked buttons always use the base bar color (aura color override handles active state).
    local wantCdColor
    local cdColorReason
    if onCooldown and not button.buttonData.isPassive then
        if isChargeButton and chargeState == CHARGE_STATE_MISSING then
            wantCdColor = style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR
            cdColorReason = "charge"
        else
            wantCdColor = style.barCooldownColor
            cdColorReason = "cooldown"
        end
    end
    if button._barCdColor ~= wantCdColor then
        button._barCdColor = wantCdColor
        local c = wantCdColor or style.barColor or DEFAULT_BAR_COLOR
        button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
    end

    EvaluateDesaturation(button, button.buttonData, style)

    -- Icon tinting (out-of-range red / unusable dim mode)
    UpdateIconTint(button, button.buttonData, style)

    -- Loss of control overlay on bar icon
    UpdateLossOfControl(button)

    -- Bar aura visuals in bar mode are driven by the bar aura parent state,
    -- with Border Indicator handled separately from active color and effects.
    local barAuraVisualsEnabled = ResolveBarAuraIndicatorEnabled(style) and not barAuraStackDisplay
    local inCombat = InCombatLockdown()

    -- Bar aura color: override bar fill when aura is active (pandemic overrides aura color)
    local wantAuraColor
    local auraColorReason
    if barAuraStackDisplay then
        wantAuraColor = nil
    elseif button._pandemicPreview or button._conditionalPreviewKind == "pandemic" then
        wantAuraColor = (button.style and button.style.barPandemicColor) or DEFAULT_BAR_PANDEMIC_COLOR
        auraColorReason = "pandemic"
    elseif button._barAuraActivePreview or button._conditionalBarAuraActivePreview then
        wantAuraColor = (button.style and button.style.barAuraColor) or DEFAULT_BAR_AURA_COLOR
        auraColorReason = "aura"
    elseif button._auraActive then
        if button._inPandemic and style.showPandemicGlow ~= false
           and (not style.pandemicGlowCombatOnly or inCombat) then
            wantAuraColor = (button.style and button.style.barPandemicColor) or DEFAULT_BAR_PANDEMIC_COLOR
            auraColorReason = "pandemic"
        elseif barAuraVisualsEnabled
               and (not style.auraGlowCombatOnly or inCombat) then
            wantAuraColor = (button.style and button.style.barAuraColor) or DEFAULT_BAR_AURA_COLOR
            auraColorReason = "aura"
        end
    end
    if button._barAuraColor ~= wantAuraColor then
        button._barAuraColor = wantAuraColor
        if not wantAuraColor then
            -- Reset to normal color immediately (don't wait for next tick)
            button._barCdColor = nil
            if not barAuraStackDisplay then
                local resetColor
                if onCooldown then
                    if isChargeButton and chargeState == CHARGE_STATE_MISSING then
                        resetColor = style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR
                    else
                        resetColor = style.barCooldownColor
                    end
                end
                local c = resetColor or style.barColor or DEFAULT_BAR_COLOR
                button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
            end
        end
    end
    if wantAuraColor and not button._barColorShiftActive then
        button.statusBar:SetStatusBarColor(wantAuraColor[1], wantAuraColor[2], wantAuraColor[3], wantAuraColor[4])
    end

    -- Bar aura effect (pandemic overrides effect color)
    local barAuraEffectPandemic = not barAuraStackDisplay and (button._pandemicPreview
        or button._conditionalPreviewKind == "pandemic"
        or (button._auraActive and button._inPandemic and style.showPandemicGlow ~= false
            and (not style.pandemicGlowCombatOnly or inCombat)))
    local barAuraEffectShow = button._barAuraEffectPreview or button._barAuraActivePreview
        or button._conditionalBarAuraActivePreview
        or button._pandemicPreview
        or (button._auraActive and (barAuraEffectPandemic
            or (barAuraVisualsEnabled and (not style.auraGlowCombatOnly or inCombat))))
    local auraEffectReason
    if barAuraEffectShow then
        auraEffectReason = barAuraEffectPandemic and "pandemic" or "aura"
    end
    SetBarAuraEffect(button, barAuraEffectShow, barAuraEffectPandemic or false)

    -- Bar indicator effects: alpha pulse, color shift
    -- Gated behind the same master toggles as existing bar aura effects:
    -- barAuraVisualsEnabled for aura-active, showPandemicGlow for pandemic (via barAuraEffectPandemic).
    local auraActiveForPulse = button._barAuraActivePreview
        or button._conditionalBarAuraActivePreview
        or (barAuraVisualsEnabled and button._auraActive
            and (not style.auraGlowCombatOnly or inCombat))

    -- Alpha Pulse — cache state for per-frame animation in BarModeOnUpdate
    -- _pandemicPreview respects the enable flag so the pandemic preview only
    -- shows pulse if the user actually enabled it (matching bar aura effect behavior).
    local wantPulse
    if button._barPulsePreview then
        wantPulse = button._barPulsePreview
    elseif (barAuraEffectPandemic or button._pandemicPreview) and style.pandemicBarPulseEnabled then
        wantPulse = "pandemic"
    elseif auraActiveForPulse and style.barAuraPulseEnabled then
        wantPulse = "aura"
    end
    if wantPulse then
        button._barPulseActive = true
        button._barPulseSpeed = (wantPulse == "pandemic")
            and (style.pandemicBarPulseSpeed or 0.5)
            or (style.barAuraPulseSpeed or 0.5)
    elseif button._barPulseActive then
        button._barPulseActive = nil
        button.statusBar:SetAlpha(1.0)
    end

    -- Color Shift — cache state for per-frame animation in BarModeOnUpdate
    local wantColorShift
    if button._barColorShiftPreview then
        wantColorShift = button._barColorShiftPreview
    elseif (barAuraEffectPandemic or button._pandemicPreview) and style.pandemicBarColorShiftEnabled then
        wantColorShift = "pandemic"
    elseif auraActiveForPulse and style.barAuraColorShiftEnabled then
        wantColorShift = "aura"
    end
    if wantColorShift then
        button._barColorShiftActive = true
        button._barCSBaseColor = wantAuraColor or wantCdColor or style.barColor or DEFAULT_BAR_COLOR
        if wantColorShift == "pandemic" then
            button._barCSShiftColor = style.pandemicBarColorShiftColor or DEFAULT_WHITE
            button._barCSSpeed = style.pandemicBarColorShiftSpeed or 0.5
        else
            button._barCSShiftColor = style.barAuraColorShiftColor or DEFAULT_WHITE
            button._barCSSpeed = style.barAuraColorShiftSpeed or 0.5
        end
    elseif button._barColorShiftActive then
        button._barColorShiftActive = nil
        local c = wantAuraColor or wantCdColor or style.barColor or DEFAULT_BAR_COLOR
        button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
    end
    if stackSegmentLayerActive then
        HideBarAuraBaseFill(button)
    end

    if shouldStoreBarVisualState then
        local colorReason = barAuraStackDisplay and "stack"
            or auraColorReason
            or cdColorReason
            or "ready"
        local color = wantAuraColor or wantCdColor or style.barColor or DEFAULT_BAR_COLOR
        StoreBarDisplayVisualState(button, {
            domain = colorReason,
            onCooldown = onCooldown,
            chargeState = chargeState,
            colorReason = colorReason,
            auraColorReason = auraColorReason,
            color = color,
            auraEffectActive = button._barAuraEffectActive == true,
            auraEffectReason = button._barAuraEffectActive == true and auraEffectReason or nil,
            pulseMode = wantPulse,
            colorShiftMode = wantColorShift,
            colorShiftBaseColor = button._barCSBaseColor,
            colorShiftTargetColor = button._barCSShiftColor,
            stackDisplay = barAuraStackDisplay,
            stackMode = button._barAuraStackMode,
            stackSegmentLayerActive = stackSegmentLayerActive,
        })
    end

    -- Keep the cooldown widget hidden — SetCooldown auto-shows it
    if button.cooldown:IsShown() then
        button.cooldown:Hide()
    end
end

-- Shared OnUpdate for bar-mode buttons: aura expiry detection, pulse/color-shift animation, + throttled bar fill.
-- Reads interval from self._barTextUpdateInterval so it can be updated without re-installing.
local function BarModeOnUpdate(self, elapsed)
    -- Detect aura expiry via HasSecretValues + GetRemainingDuration.
    -- Non-secret (out of combat): instant expiry detection.
    -- Secret (in combat): skip; UpdateButtonCooldown handles expiry next tick.
    -- Skip when cooldowns are dirty (target switch / UNIT_AURA just fired,
    -- ticker hasn't processed yet — old DurationObject may be invalidated)
    -- or grace period active (holdover DurationObject from previous target).
    if self._auraActive and self._durationObj
       and not self._auraGraceStart and not self._targetSwitchAt and not CooldownCompanion._cooldownsDirty then
        if not self._durationObj:HasSecretValues() then
            if self._durationObj:GetRemainingDuration() <= 0 then
                self._durationObj = nil
                self._auraActive = false
                self._inPandemic = false
                self._barAuraColor = nil
                local c = self.style.barColor or DEFAULT_BAR_COLOR
                self.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
                SetBarAuraEffect(self, false)
                self._barPulseActive = nil
                self._barColorShiftActive = nil
                self.statusBar:SetAlpha(1.0)
            end
        end
    end
    -- Viewer bar expiry (totem/guardian): bar hidden = totem despawned
    if self._auraActive and self._viewerBar
       and not self._auraGraceStart and not self._targetSwitchAt and not CooldownCompanion._cooldownsDirty then
        if not self._viewerBar:IsVisible() then
            self._viewerBar = nil
            self._auraActive = false
            self._inPandemic = false
            self._barAuraColor = nil
            local c = self.style.barColor or DEFAULT_BAR_COLOR
            self.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
            SetStatusBarImmediateRange(self.statusBar, 0, 1)
            SetBarAuraEffect(self, false)
            self._barPulseActive = nil
            self._barColorShiftActive = nil
            self.statusBar:SetAlpha(1.0)
        end
    end
    -- Per-frame pulse/color-shift animations (must run at frame rate for smoothness)
    if self._barPulseActive or self._barColorShiftActive then
        local now = GetTime()
        if self._barPulseActive then
            local speed = self._barPulseSpeed or 0.5
            self.statusBar:SetAlpha(0.6 + 0.4 * math_sin(now * 2 * math_pi / speed))
        end
        if self._barColorShiftActive then
            local base = self._barCSBaseColor
            local shift = self._barCSShiftColor
            if base and shift then
                local speed = self._barCSSpeed or 0.5
                local t = 0.5 + 0.5 * math_sin(now * 2 * math_pi / speed)
                local ba = base[4] or 1
                self.statusBar:SetStatusBarColor(
                    base[1] + (shift[1] - base[1]) * t,
                    base[2] + (shift[2] - base[2]) * t,
                    base[3] + (shift[3] - base[3]) * t,
                    ba + ((shift[4] or 1) - ba) * t
                )
            else
                self._barColorShiftActive = nil
            end
        end
    end

    self._barFillElapsed = self._barFillElapsed + elapsed
    if self._barFillElapsed >= (self._barTextUpdateInterval or BAR_TEXT_UPDATE_INTERVAL) then
        self._barFillElapsed = 0
        UpdateBarFill(self)
    end
end

function CooldownCompanion:CreateBarFrame(parent, index, buttonData, style)
    local barLength = style.barLength or 180
    local barHeight = style.barHeight or 20
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local showIcon = style.showBarIcon ~= false
    local isVertical = style.barFillVertical or false
    local iconReverse = showIcon and (style.barIconReverse or false)

    local iconSize = (style.barIconSizeOverride and style.barIconSize) or barHeight
    local iconOffset = showIcon and (style.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = showIcon and (iconSize + iconOffset) or 0

    -- Main bar frame
    local button = CreateFrame("Frame", parent:GetName() .. "Bar" .. index, parent)
    if isVertical then
        button:SetSize(barHeight, barLength)
    else
        button:SetSize(barLength, barHeight)
    end
    button._isBar = true
    button._isVertical = isVertical

    -- Background — covers bar area only when icon is shown (icon has its own iconBg)
    local bgColor = style.barBgColor or {0.1, 0.1, 0.1, 0.8}
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    if showIcon then
        SetBarAreaPoints(button.bg, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        button.bg:SetAllPoints()
    end
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Icon
    button.icon = button:CreateTexture(nil, "ARTWORK")
    if showIcon then
        SetIconAreaPoints(button.icon, button, isVertical, iconReverse, iconSize, ST.GetEffectiveBorderLayoutSize(button, borderSize, borderRenderMode))
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        -- Hidden 1x1 icon (still needed for UpdateButtonIcon)
        button.icon:SetPoint("TOPLEFT", 0, 0)
        button.icon:SetSize(1, 1)
        button.icon:SetAlpha(0)
    end

    -- Icon background + border (always shown when icon visible)
    button.iconBg = button:CreateTexture(nil, "BACKGROUND")
    SetIconAreaPoints(button.iconBg, button, isVertical, iconReverse, iconSize, 0)
    button.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    if not showIcon then button.iconBg:Hide() end

    button._iconBounds = CreateFrame("Frame", nil, button)
    button._iconBounds:EnableMouse(false)
    SetIconAreaPoints(button._iconBounds, button, isVertical, iconReverse, iconSize, 0)

    button.iconBorderTextures = {}
    local borderColor = style.borderColor or {0, 0, 0, 1}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        if not showIcon then tex:Hide() end
        button.iconBorderTextures[i] = tex
    end
    ApplyBorderEdgePositions(button.iconBorderTextures, button._iconBounds, borderSize, borderRenderMode)

    -- Bar area bounds (for border positioning separate from icon)
    button._barBounds = CreateFrame("Frame", nil, button)
    button._barBounds:EnableMouse(false)
    if showIcon then
        SetBarAreaPoints(button._barBounds, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        button._barBounds:SetAllPoints()
    end

    -- StatusBar
    button.statusBar = CreateFrame("StatusBar", nil, button)
    SetBarAreaPoints(button.statusBar, button, isVertical, iconReverse, barAreaLeft, barAreaTop, ST.GetEffectiveBorderLayoutSize(button, borderSize, borderRenderMode))
    if isVertical then
        button.statusBar:SetOrientation("VERTICAL")
    end
    SetStatusBarImmediateRange(button.statusBar, 0, 1)
    SetStatusBarImmediateValue(button.statusBar, 1)
    button.statusBar:SetReverseFill(style.barReverseFill or false)
    button.statusBar:SetStatusBarTexture(CooldownCompanion:FetchEffectiveBarTexture(style.barTexture or "Solid"))
    local barColor = style.barColor or DEFAULT_BAR_COLOR
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
    button.statusBar:EnableMouse(false)

    -- Dedicated text layer above custom segment holders.
    button.barTextFrame = CreateFrame("Frame", nil, button)
    SetBarAreaPoints(button.barTextFrame, button, isVertical, iconReverse, barAreaLeft, barAreaTop, ST.GetEffectiveBorderLayoutSize(button, borderSize, borderRenderMode))
    button.barTextFrame:SetFrameLevel(button.statusBar:GetFrameLevel() + 20)
    button.barTextFrame:EnableMouse(false)

    -- Name text
    button.nameText = button.barTextFrame:CreateFontString(nil, "OVERLAY")
    ApplyFontStyle(button.nameText, style, "barName", 10)
    local nameOffX = style.barNameTextOffsetX or 0
    local nameOffY = style.barNameTextOffsetY or 0
    local nameReverse = style.barNameTextReverse
    if isVertical then
        if nameReverse then
            button.nameText:SetPoint("TOP", nameOffX, -3 + nameOffY)
        else
            button.nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        end
        button.nameText:SetJustifyH("CENTER")
    else
        if nameReverse then
            button.nameText:SetPoint("RIGHT", -3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("RIGHT")
        else
            button.nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("LEFT")
        end
    end
    if style.showBarNameText ~= false or buttonData.customName then
        button.nameText:SetText(buttonData.customName or buttonData.name or "")
    else
        button.nameText:Hide()
    end

    -- Time text
    button.timeText = button.barTextFrame:CreateFontString(nil, "OVERLAY")
    ApplyFontStyle(button.timeText, style, "cooldown")
    local cdOffX = style.barCdTextOffsetX or 0
    local cdOffY = style.barCdTextOffsetY or 0
    local timeReverse = style.barTimeTextReverse
    if isVertical then
        if timeReverse then
            button.timeText:SetPoint("BOTTOM", cdOffX, 3 + cdOffY)
        else
            button.timeText:SetPoint("TOP", cdOffX, -3 + cdOffY)
        end
        button.timeText:SetJustifyH("CENTER")
    else
        if timeReverse then
            button.timeText:SetPoint("LEFT", 3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("LEFT")
        else
            button.timeText:SetPoint("RIGHT", -3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("RIGHT")
        end
    end

    -- Truncate name text so it doesn't overlap time text (horizontal only, opposite sides)
    if not isVertical and nameReverse == timeReverse then
        if nameReverse then
            button.nameText:SetPoint("LEFT", button.timeText, "RIGHT", 4, 0)
        else
            button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
        end
    end

    -- Border textures (around bar area, not full button)
    button.borderTextures = {}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        button.borderTextures[i] = tex
    end
    ApplyBorderEdgePositions(button.borderTextures, button._barBounds, borderSize, borderRenderMode)

    -- Loss of control cooldown frame (red swipe over the bar icon)
    button.locCooldown = CreateFrame("Cooldown", button:GetName() .. "LocCooldown", button, "CooldownFrameTemplate")
    button.locCooldown:SetAllPoints(button.icon)
    button.locCooldown:SetDrawEdge(true)
    button.locCooldown:SetDrawSwipe(true)
    button.locCooldown:SetSwipeColor(0.17, 0, 0, 0.8)
    button.locCooldown:SetHideCountdownNumbers(true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)

    -- Icon-only GCD swipe frame for bar mode.
    button.iconGCDCooldown = CreateFrame("Cooldown", button:GetName() .. "IconGCDCooldown", button, "CooldownFrameTemplate")
    button.iconGCDCooldown:SetAllPoints(button.icon)
    button.iconGCDCooldown:SetDrawEdge(style.showCooldownSwipeEdge ~= false)
    button.iconGCDCooldown:SetDrawSwipe(true)
    button.iconGCDCooldown:SetReverse(style.cooldownSwipeReverse or false)
    button.iconGCDCooldown:SetHideCountdownNumbers(true)
    button.iconGCDCooldown:Hide()
    SetFrameClickThroughRecursive(button.iconGCDCooldown, true, true)

    -- Hidden cooldown frame for GetCooldownTimes() reads
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetSize(1, 1)
    button.cooldown:SetPoint("CENTER")
    button.cooldown:SetDrawSwipe(false)
    button.cooldown:SetHideCountdownNumbers(true)
    button.cooldown:Hide()
    SetFrameClickThroughRecursive(button.cooldown, true, true)

    -- Suppress bling (cooldown-end flash) on all bar buttons
    button.cooldown:SetDrawBling(false)
    button.locCooldown:SetDrawBling(false)
    button.iconGCDCooldown:SetDrawBling(false)

    -- Charge/item count text (overlay)
    button.overlayFrame = CreateFrame("Frame", nil, button)
    button.overlayFrame:SetAllPoints()
    button.overlayFrame:EnableMouse(false)
    button.count = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetText("")
    button.buttonData = buttonData

    -- Apply count text font/anchor settings
    ApplyBarCountTextStyle(button, style)

    -- Aura stack count text: separate FontString for aura stacks and config previews.
    button.auraStackCount = (button.barTextFrame or button.overlayFrame):CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.auraStackCount:SetText("")
    ApplyFontStyle(button.auraStackCount, style, "auraStack")
    local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
    local asXOff = style.auraStackXOffset or 2
    local asYOff = style.auraStackYOffset or 2
    if showIcon then
        button.auraStackCount:SetPoint(asAnchor, button.icon, asAnchor, asXOff, asYOff)
    else
        button.auraStackCount:SetPoint(asAnchor, button, asAnchor, asXOff, asYOff)
    end

    -- Store button data
    button.index = index
    button.style = style

    -- Cache spell cooldown secrecy level (static per-spell: NeverSecret=0, ContextuallySecret=2)
    if buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(buttonData.id)
    end

    -- Bar text refresh / fallback fill OnUpdate. Native timers drive DurationObject fills.
    button._barFillElapsed = 0
    button._barTextUpdateInterval = BAR_TEXT_UPDATE_INTERVAL
    button:SetScript("OnUpdate", BarModeOnUpdate)

    -- Aura tracking runtime state
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    button._auraUnit = buttonData.auraUnit or "player"
    button._auraActive = false
    button._auraDurationObj = nil
    button._auraCooldownStart = nil
    button._auraCooldownDuration = nil
    button._auraPrimarySwipeActive = nil
    button._auraTrackingReady = buttonData.isPassive == true
    button._showingAuraIcon = false
    button._auraViewerFrame = nil
    button._activeAuraSpellID = nil
    button._activeAuraSpellIDFromFallback = nil
    button._activeAuraIcon = nil
    button._activeAuraIconAvailable = nil
    button._lastViewerTexId = nil

    button._auraInstanceID = nil
    button._viewerBar = nil
    button._viewerAuraVisualsActive = nil
    button._auraDisplayName = nil
    button._auraNameOverrideActive = nil

    if IsEntryItemLike(buttonData) then
        local effectiveItem = ResolveEffectiveItem(buttonData, { requestLoad = true })
        button._resolvedItemId = effectiveItem and effectiveItem.itemID or buttonData.id
        button._resolvedItemAvailableQuantity = effectiveItem and effectiveItem.availableQuantity or 0
        button._resolvedItemQuantityKind = effectiveItem and effectiveItem.quantityKind or "stacks"
        button._equipmentSlotTrackable = CooldownCompanion.IsEquipmentSlotEntry(buttonData)
            and effectiveItem and effectiveItem.trackable == true or nil
    end

    -- Per-button visibility runtime state
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._groupId = parent.groupId

    -- Aura effect frames (solid border, pixel glow, proc glow)
    button.barAuraEffect = CreateGlowContainer(button, 32)

    -- Set icon
    self:UpdateButtonIcon(button)

    -- Set name text from resolved spell/item name
    if style.showBarNameText ~= false or buttonData.customName then
        local displayName = buttonData.customName or buttonData.name
        if not buttonData.customName then
            if button._auraActive and button._auraDisplayName then
                displayName = button._auraDisplayName
            elseif buttonData.type == "spell" then
                local spellName = C_Spell.GetSpellName(button._displaySpellId or buttonData.id)
                if spellName then displayName = spellName end
            elseif IsEntryItemLike(buttonData) then
                local itemID = button._resolvedItemId or buttonData.id
                local itemName = itemID and C_Item.GetItemNameByID(itemID)
                if itemName then displayName = itemName end
            end
        end
        button.nameText:SetText(displayName or "")
    end

    -- Methods
    button.UpdateCooldown = function(self)
        CooldownCompanion:UpdateButtonCooldown(self)
    end

    button.UpdateStyle = function(self, newStyle)
        CooldownCompanion:UpdateBarStyle(self, newStyle)
    end

    -- Click-through
    local showTooltips = style.showTooltips == true and not IsCursorAnchoredButton(button)
    local iconTooltips = showTooltips and showIcon

    -- Disable hover on the full bar; tooltip hover is icon-only via _iconBounds.
    SetFrameClickThroughRecursive(button, true, true)
    -- Prevent child frames from stealing hover.
    if button.statusBar then
        SetFrameClickThroughRecursive(button.statusBar, true, true)
    end
    if button.barTextFrame then
        SetFrameClickThroughRecursive(button.barTextFrame, true, true)
    end
    if button._barBounds then
        SetFrameClickThroughRecursive(button._barBounds, true, true)
    end
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    if button.iconGCDCooldown then
        SetFrameClickThroughRecursive(button.iconGCDCooldown, true, true)
    end
    if button.locCooldown then
        SetFrameClickThroughRecursive(button.locCooldown, true, true)
    end
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end

    if button._iconBounds then
        SetFrameClickThroughRecursive(button._iconBounds, true, not iconTooltips)
    end
    SetBarIconTooltipScripts(button, iconTooltips)
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)

    return button
end

function CooldownCompanion:UpdateBarStyle(button, newStyle)
    local barLength = newStyle.barLength or 180
    local barHeight = newStyle.barHeight or 20
    local borderSize = newStyle.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderRenderMode = ST.GetBorderRenderMode(newStyle)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(button, borderSize, borderRenderMode)
    local showIcon = newStyle.showBarIcon ~= false
    local isVertical = newStyle.barFillVertical or false
    local iconReverse = showIcon and (newStyle.barIconReverse or false)
    local iconSize = (newStyle.barIconSizeOverride and newStyle.barIconSize) or barHeight
    local iconOffset = showIcon and (newStyle.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = showIcon and (iconSize + iconOffset) or 0

    button.style = newStyle
    if ClearButtonVisualState then
        ClearButtonVisualState(button)
    end
    button._isVertical = isVertical

    -- Update bar text/fallback fill OnUpdate interval
    button._barFillElapsed = 0
    button._barTextUpdateInterval = BAR_TEXT_UPDATE_INTERVAL
    button:SetScript("OnUpdate", BarModeOnUpdate)

    -- Invalidate cached state
    button._desaturated = nil
    button._iconTintIntent = nil
    button._desatCooldownActive = nil
    button._readyGlowStartTime = nil
    button._readyGlowMaxChargesStartTime = nil
    button._readyGlowMaxChargesActive = nil
    button._readyGlowMaxChargesSpellID = nil
    button._noCooldown = nil
    button._noCooldownSpellId = nil
    button._baseNoCooldown = nil
    button._baseNoCooldownSpellId = nil
    button._resourceGateCost = nil
    button._resourceGateCostSpellId = nil
    button._baseResourceGateCost = nil
    button._baseResourceGateCostSpellId = nil
    button._vertexR = nil
    button._vertexG = nil
    button._vertexB = nil
    button._vertexA = nil
    button._chargeText = nil
    button._chargeCountReadable = nil
    button._zeroChargesConfirmed = nil
    button._nilConfirmPending = nil
    button._displaySpellId = nil
    button._liveOverrideSpellId = nil
    button._itemCount = nil
    button._auraActive = nil
    button._auraDurationObj = nil
    button._auraCooldownStart = nil
    button._auraCooldownDuration = nil
    button._auraPrimarySwipeActive = nil
    button._showingAuraIcon = nil
    button._auraViewerFrame = nil
    button._activeAuraSpellID = nil
    button._activeAuraSpellIDFromFallback = nil
    button._activeAuraIcon = nil
    button._activeAuraIconAvailable = nil
    button._lastViewerTexId = nil

    button._auraInstanceID = nil
    button._viewerBar = nil
    button._barAuraStackDisplay = nil
    button._barAuraStackValue = nil
    button._barAuraStackValueSecret = nil
    button._barAuraStackMax = nil
    button._barAuraStackMode = nil
    button._barAuraVisualSettings = nil
    ClearBarAuraStackVisual(button)
    button._inPandemic = nil
    EntryRuntime.ClearAuraPandemicRuntimeState(button)
    button._viewerAuraVisualsActive = nil
    button._auraDisplayName = nil
    button._auraNameOverrideActive = nil
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(button.buttonData)
    button._auraUnit = button.buttonData.auraUnit or "player"
    button._auraStackText = nil
    if button.auraStackCount then button.auraStackCount:SetText("") end
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._barCdColor = nil
    button._chargeRecharging = nil
    button._chargesSpent = nil
    button._barReadyTextColor = nil
    button._barAuraColor = nil
    button._barAuraEffectActive = nil
    button._barPulseActive = nil
    button._barColorShiftActive = nil
    button.statusBar:SetAlpha(1.0)

    if isVertical then
        button:SetSize(barHeight, barLength)
    else
        button:SetSize(barLength, barHeight)
    end

    -- Update icon
    button.icon:ClearAllPoints()
    if showIcon then
        SetIconAreaPoints(button.icon, button, isVertical, iconReverse, iconSize, borderLayoutSize)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.icon:SetAlpha(1)
    else
        button.icon:SetPoint("TOPLEFT", 0, 0)
        button.icon:SetSize(1, 1)
        button.icon:SetAlpha(0)
    end
    if button.iconGCDCooldown then
        button.iconGCDCooldown:SetAllPoints(button.icon)
        button.iconGCDCooldown:SetDrawEdge(newStyle.showCooldownSwipeEdge ~= false)
        button.iconGCDCooldown:SetReverse(newStyle.cooldownSwipeReverse or false)
        if not showIcon or newStyle.showGCDSwipe ~= true then
            button.iconGCDCooldown:Hide()
        end
    end

    button.bg:ClearAllPoints()
    if showIcon then
        SetBarAreaPoints(button.bg, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        button.bg:SetAllPoints()
    end
    button.bg:Show()

    -- Icon bg + border: always shown when icon visible
    if button.iconBg then
        SetIconAreaPoints(button.iconBg, button, isVertical, iconReverse, iconSize, 0)
        if showIcon then button.iconBg:Show() else button.iconBg:Hide() end
    end
    if button._iconBounds then
        SetIconAreaPoints(button._iconBounds, button, isVertical, iconReverse, iconSize, 0)
    end
    if button.iconBorderTextures then
        ApplyBorderEdgePositions(button.iconBorderTextures, button._iconBounds, borderSize, borderRenderMode)
        for _, tex in ipairs(button.iconBorderTextures) do
            if showIcon then tex:Show() else tex:Hide() end
        end
    end

    -- Bar area bounds
    if button._barBounds then
        button._barBounds:ClearAllPoints()
        if showIcon then
            SetBarAreaPoints(button._barBounds, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
        else
            button._barBounds:SetAllPoints()
        end
    end

    -- Update status bar
    SetBarAreaPoints(button.statusBar, button, isVertical, iconReverse, barAreaLeft, barAreaTop, borderLayoutSize)
    if isVertical then
        button.statusBar:SetOrientation("VERTICAL")
    else
        button.statusBar:SetOrientation("HORIZONTAL")
    end
    button.statusBar:SetReverseFill(newStyle.barReverseFill or false)
    button.statusBar:SetStatusBarTexture(CooldownCompanion:FetchEffectiveBarTexture(newStyle.barTexture or "Solid"))
    local barColor = newStyle.barColor or {0.2, 0.6, 1.0, 1.0}
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])

    if button.barTextFrame then
        button.barTextFrame:ClearAllPoints()
        SetBarAreaPoints(button.barTextFrame, button, isVertical, iconReverse, barAreaLeft, barAreaTop, borderLayoutSize)
        button.barTextFrame:SetFrameLevel(button.statusBar:GetFrameLevel() + 20)
    end

    -- Update background
    local bgColor = newStyle.barBgColor or {0.1, 0.1, 0.1, 0.8}
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    if button.iconBg then
        button.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    end

    -- Update border
    local borderColor = newStyle.borderColor or {0, 0, 0, 1}
    if button.borderTextures then
        ApplyBorderEdgePositions(button.borderTextures, button._barBounds or button, borderSize, borderRenderMode)
        for _, tex in ipairs(button.borderTextures) do
            tex:SetColorTexture(unpack(borderColor))
            tex:Show()
        end
    end
    if button.iconBorderTextures then
        for _, tex in ipairs(button.iconBorderTextures) do
            tex:SetColorTexture(unpack(borderColor))
        end
    end

    -- Update name text font and position
    local hasCustomName = button.buttonData and button.buttonData.customName
    if newStyle.showBarNameText ~= false or hasCustomName then
        ApplyFontStyle(button.nameText, newStyle, "barName", 10)
        button.nameText:Show()
    else
        button.nameText:Hide()
    end

    -- Update time text font (default state; per-tick logic handles aura mode)
    ApplyFontStyle(button.timeText, newStyle, "cooldown")
    -- Clear cached text mode so per-tick logic re-applies the correct font and color
    button._barTextMode = nil
    button._barTextColorDirty = true

    -- Re-anchor name and time text for orientation
    local nameOffX = newStyle.barNameTextOffsetX or 0
    local nameOffY = newStyle.barNameTextOffsetY or 0
    local cdOffX = newStyle.barCdTextOffsetX or 0
    local cdOffY = newStyle.barCdTextOffsetY or 0
    local nameReverse = newStyle.barNameTextReverse
    local timeReverse = newStyle.barTimeTextReverse
    button.nameText:ClearAllPoints()
    button.timeText:ClearAllPoints()
    if isVertical then
        if nameReverse then
            button.nameText:SetPoint("TOP", nameOffX, -3 + nameOffY)
        else
            button.nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        end
        button.nameText:SetJustifyH("CENTER")
        if timeReverse then
            button.timeText:SetPoint("BOTTOM", cdOffX, 3 + cdOffY)
        else
            button.timeText:SetPoint("TOP", cdOffX, -3 + cdOffY)
        end
        button.timeText:SetJustifyH("CENTER")
    else
        if nameReverse then
            button.nameText:SetPoint("RIGHT", -3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("RIGHT")
        else
            button.nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("LEFT")
        end
        if timeReverse then
            button.timeText:SetPoint("LEFT", 3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("LEFT")
        else
            button.timeText:SetPoint("RIGHT", -3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("RIGHT")
        end
        -- Truncate name text so it doesn't overlap time text (opposite sides only)
        if nameReverse == timeReverse then
            if nameReverse then
                button.nameText:SetPoint("LEFT", button.timeText, "RIGHT", 4, 0)
            else
                button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
            end
        end
    end

    -- Update charge/item count font and anchor to icon or bar center
    ApplyBarCountTextStyle(button, newStyle)

    -- Update aura stack count font/anchor settings
    if button.auraStackCount then
        button.auraStackCount:ClearAllPoints()
        ApplyFontStyle(button.auraStackCount, newStyle, "auraStack")
        local asAnchor = newStyle.auraStackAnchor or "BOTTOMLEFT"
        local asXOff = newStyle.auraStackXOffset or 2
        local asYOff = newStyle.auraStackYOffset or 2
        if showIcon then
            button.auraStackCount:SetPoint(asAnchor, button.icon, asAnchor, asXOff, asYOff)
        else
            button.auraStackCount:SetPoint(asAnchor, button, asAnchor, asXOff, asYOff)
        end
    end

    -- Update spell name text
    self:UpdateButtonIcon(button)
    if newStyle.showBarNameText ~= false or (button.buttonData and button.buttonData.customName) then
        local displayName = button.buttonData.customName or button.buttonData.name
        if not button.buttonData.customName then
            if button._auraActive and button._auraDisplayName then
                displayName = button._auraDisplayName
            elseif button.buttonData.type == "spell" then
                local spellName = C_Spell.GetSpellName(button._displaySpellId or button.buttonData.id)
                if spellName then displayName = spellName end
            elseif IsEntryItemLike(button.buttonData) then
                local itemID = button._resolvedItemId or button.buttonData.id
                local itemName = itemID and C_Item.GetItemNameByID(itemID)
                if itemName then displayName = itemName end
            end
        end
        button.nameText:SetText(displayName or "")
    end

    -- Update click-through
    local showTooltips = newStyle.showTooltips == true and not IsCursorAnchoredButton(button)
    local iconTooltips = showTooltips and showIcon

    -- Disable hover on the full bar; tooltip hover is icon-only via _iconBounds.
    SetFrameClickThroughRecursive(button, true, true)
    -- Prevent child frames from stealing hover.
    if button.statusBar then
        SetFrameClickThroughRecursive(button.statusBar, true, true)
    end
    if button.barTextFrame then
        SetFrameClickThroughRecursive(button.barTextFrame, true, true)
    end
    if button._barBounds then
        SetFrameClickThroughRecursive(button._barBounds, true, true)
    end
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    if button.iconGCDCooldown then
        SetFrameClickThroughRecursive(button.iconGCDCooldown, true, true)
    end
    if button.locCooldown then
        SetFrameClickThroughRecursive(button.locCooldown, true, true)
    end
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end

    if button._iconBounds then
        SetFrameClickThroughRecursive(button._iconBounds, true, not iconTooltips)
    end
    SetBarIconTooltipScripts(button, iconTooltips)
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
    CooldownCompanion:UpdateAuraTextureVisual(button)
end

-- Exports
ST._UpdateBarDisplay = UpdateBarDisplay
ST._ApplyBarCountTextStyle = ApplyBarCountTextStyle
CooldownCompanion.ApplyBarPanelAuraStackVisual = ApplyBarAuraStackVisual
