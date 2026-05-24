--[[
    CooldownCompanion - Core/AuraTexturesEffects.lua
    Aura texture runtime geometry, matching, and animation effects.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AT = ST._AT

local C_Item_IsItemInRange = C_Item.IsItemInRange
local C_Item_IsUsableItem = C_Item.IsUsableItem
local C_Spell_IsSpellUsable = C_Spell.IsSpellUsable
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UnitCanAttack = UnitCanAttack
local UnitExists = UnitExists
local ipairs = ipairs
local issecretvalue = issecretvalue
local math_abs = math.abs
local math_cos = math.cos
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_pi = math.pi
local math_rad = math.rad
local math_sin = math.sin
local tonumber = tonumber
local type = type
local wipe = wipe

local LOCATION_CENTER = AT.LOCATION_CENTER
local LOCATION_DIMENSIONS = AT.LOCATION_DIMENSIONS
local DEFAULT_TEXTURE_SIZE = AT.DEFAULT_TEXTURE_SIZE
local DEFAULT_TEXTURE_PAIR_SPACING = AT.DEFAULT_TEXTURE_PAIR_SPACING
local TEXTURE_INDICATOR_EFFECT_NONE = AT.TEXTURE_INDICATOR_EFFECT_NONE
local TEXTURE_INDICATOR_EFFECT_PULSE = AT.TEXTURE_INDICATOR_EFFECT_PULSE
local TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT = AT.TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT
local TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND = AT.TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND
local TEXTURE_INDICATOR_EFFECT_BOUNCE = AT.TEXTURE_INDICATOR_EFFECT_BOUNCE
local MIN_TEXTURE_INDICATOR_SPEED = AT.MIN_TEXTURE_INDICATOR_SPEED
local MAX_TEXTURE_INDICATOR_SPEED = AT.MAX_TEXTURE_INDICATOR_SPEED
local DEFAULT_TEXTURE_INDICATOR_SPEED = AT.DEFAULT_TEXTURE_INDICATOR_SPEED
local DEFAULT_TEXTURE_PULSE_ALPHA = AT.DEFAULT_TEXTURE_PULSE_ALPHA
local DEFAULT_TEXTURE_SHRINK_SCALE = AT.DEFAULT_TEXTURE_SHRINK_SCALE
local DEFAULT_TEXTURE_BOUNCE_PIXELS = AT.DEFAULT_TEXTURE_BOUNCE_PIXELS
local TEXTURE_INDICATOR_SECTION_ORDER = AT.TEXTURE_INDICATOR_SECTION_ORDER
local TRIGGER_EXPECTED_LABELS = AT.TRIGGER_EXPECTED_LABELS
local CopyColor = AT.CopyColor
local Clamp = AT.Clamp
local NormalizeTextureIndicatorEffect = AT.NormalizeTextureIndicatorEffect
local NormalizeTriggerConditionKey = AT.NormalizeTriggerConditionKey
local NormalizeTriggerStateKey = AT.NormalizeTriggerStateKey
local GetStretchMultiplier = AT.GetStretchMultiplier
local RotateOffset = AT.RotateOffset
local ResolveGroup = AT.ResolveGroup

local function ShouldCaptureButtonVisualState()
    local isEnabled = ST._AreButtonVisualStateSnapshotsEnabled
    return type(isEnabled) == "function" and isEnabled() == true
end

local function ClearTriggerVisualRows(runtimeButtons)
    if type(runtimeButtons) ~= "table" then
        return
    end

    for _, button in ipairs(runtimeButtons) do
        if type(button) == "table" then
            button._triggerVisualRow = nil
            button._triggerVisualPanel = nil
        end
    end
end

local function AssignTriggerVisualPanel(frame, panelState)
    if frame then
        frame._triggerVisualPanel = panelState
    end

    local runtimeButtons = frame and frame.buttons
    if type(runtimeButtons) ~= "table" then
        return
    end

    for _, button in ipairs(runtimeButtons) do
        if type(button) == "table" then
            button._triggerVisualPanel = panelState
        end
    end
end

local function FinishTriggerPanelMatch(frame, panelState, matched, reason)
    if panelState then
        panelState.matched = matched == true
        panelState.reason = reason
        panelState.matchReason = reason
        AssignTriggerVisualPanel(frame, panelState)
    end
    return matched == true
end

local function ApplyTextureSource(texture, settings)
    local resolvedSourceType, resolvedSourceValue = CooldownCompanion:ResolveAuraTextureAsset(
        settings.sourceType,
        settings.sourceValue,
        settings.mediaType
    )

    if resolvedSourceType == "atlas" then
        texture:SetAtlas(resolvedSourceValue, false)
        return true
    end

    if resolvedSourceType == "file" then
        texture:SetTexture(resolvedSourceValue)
        return true
    end

    texture:Hide()
    return false
end

local function ApplyTextureVisual(texture, settings, alpha, flipH, flipV, rotationRadians)
    local left, right, top, bottom = 0, 1, 0, 1
    if flipH then
        left, right = 1, 0
    end
    if flipV then
        top, bottom = 1, 0
    end
    texture:SetTexCoord(left, right, top, bottom)
    texture:SetBlendMode(settings.blendMode)
    local color = settings.color or { 1, 1, 1, 1 }
    texture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, alpha)
    texture:SetRotation(rotationRadians or 0)
    texture:Show()
end

function CooldownCompanion:BuildTexturePanelGeometry(settings, baseWidth, baseHeight)
    local dims = LOCATION_DIMENSIONS[settings.locationType] or LOCATION_DIMENSIONS[LOCATION_CENTER]
    local pieceWidth = math_max(1, (baseWidth or DEFAULT_TEXTURE_SIZE) * (dims.width or 1) * GetStretchMultiplier(settings.stretchX))
    local pieceHeight = math_max(1, (baseHeight or DEFAULT_TEXTURE_SIZE) * (dims.height or 1) * GetStretchMultiplier(settings.stretchY))
    local rotationRadians = math_rad(tonumber(settings.rotation) or 0)
    local pairSpacing = tonumber(settings.pairSpacing) or DEFAULT_TEXTURE_PAIR_SPACING
    local gap = 0
    local pieces = {
        { centerX = 0, centerY = 0, flipH = false, flipV = false },
    }

    if dims.layout == "pair_horizontal" then
        gap = pieceWidth * pairSpacing
        local centerOffset = (pieceWidth + gap) / 2
        pieces = {
            { centerX = -centerOffset, centerY = 0, flipH = false, flipV = false },
            { centerX = centerOffset, centerY = 0, flipH = true, flipV = false },
        }
    elseif dims.layout == "pair_vertical" then
        gap = pieceHeight * pairSpacing
        local centerOffset = (pieceHeight + gap) / 2
        pieces = {
            { centerX = 0, centerY = -centerOffset, flipH = false, flipV = false },
            { centerX = 0, centerY = centerOffset, flipH = false, flipV = true },
        }
    end

    local rotatedPieceWidth = math_max(1, (math_abs(pieceWidth * math_cos(rotationRadians)) + math_abs(pieceHeight * math_sin(rotationRadians))))
    local rotatedPieceHeight = math_max(1, (math_abs(pieceWidth * math_sin(rotationRadians)) + math_abs(pieceHeight * math_cos(rotationRadians))))
    local minLeft, maxRight = nil, nil
    local minBottom, maxTop = nil, nil

    for _, piece in ipairs(pieces) do
        local centerX, centerY = RotateOffset(piece.centerX, piece.centerY, rotationRadians)
        piece.centerX = centerX
        piece.centerY = centerY

        local left = centerX - (rotatedPieceWidth / 2)
        local right = centerX + (rotatedPieceWidth / 2)
        local bottom = centerY - (rotatedPieceHeight / 2)
        local top = centerY + (rotatedPieceHeight / 2)

        minLeft = minLeft and math_min(minLeft, left) or left
        maxRight = maxRight and math_max(maxRight, right) or right
        minBottom = minBottom and math_min(minBottom, bottom) or bottom
        maxTop = maxTop and math_max(maxTop, top) or top
    end

    return {
        rotationRadians = rotationRadians,
        pieceWidth = pieceWidth,
        pieceHeight = pieceHeight,
        rotatedPieceWidth = rotatedPieceWidth,
        rotatedPieceHeight = rotatedPieceHeight,
        boundsWidth = math_max(1, (maxRight or (rotatedPieceWidth / 2)) - (minLeft or -(rotatedPieceWidth / 2))),
        boundsHeight = math_max(1, (maxTop or (rotatedPieceHeight / 2)) - (minBottom or -(rotatedPieceHeight / 2))),
        pieces = pieces,
        layout = dims.layout or "single",
        gap = gap,
    }
end

local function LayoutTexturePieces(host, settings, geometry, alpha)
    local visualRoot = host.visualRoot or host
    local textures = {
        host.primaryTexture,
        host.secondaryTexture,
    }
    local shown = false

    for index, texture in ipairs(textures) do
        local piece = geometry.pieces[index]
        if not texture or not piece then
            if texture then
                texture:Hide()
            end
        else
            texture:ClearAllPoints()
            texture:SetSize(geometry.pieceWidth, geometry.pieceHeight)
            texture:SetPoint("CENTER", visualRoot, "CENTER", piece.centerX, piece.centerY)

            if ApplyTextureSource(texture, settings) then
                ApplyTextureVisual(texture, settings, alpha, piece.flipH, piece.flipV, geometry.rotationRadians)
                shown = true
            else
                texture:Hide()
            end
        end
    end

    return shown
end

local function SetTextureIndicatorBaseVisuals(host)
    if not host then
        return
    end

    local displayType = host._activeDisplayType
    if displayType == "texture" then
        local settings = host._activeTextureSettings
        local geometry = host._activeTextureGeometry
        if not settings or not geometry then
            return
        end

        local color = settings.color or { 1, 1, 1, 1 }
        local baseAlpha = Clamp((color[4] or 1) * (settings.alpha or 1), 0.05, 1)
        local textures = {
            host.primaryTexture,
            host.secondaryTexture,
        }

        for index, texture in ipairs(textures) do
            local piece = geometry.pieces[index]
            if texture and piece and texture:IsShown() then
                ApplyTextureVisual(texture, settings, baseAlpha, piece.flipH, piece.flipV, geometry.rotationRadians)
            end
        end

        host._indicatorBaseAlpha = baseAlpha
        host._indicatorBaseColor = CopyColor(color) or { 1, 1, 1, 1 }
        host._indicatorBaseVisualsReady = true
        return
    end

    if displayType == "icon" and host.iconFrame and host.iconFrame.icon and host.iconFrame.icon:IsShown() then
        local color = CopyColor(host._triggerIconBaseColor) or { 1, 1, 1, 1 }
        host.iconFrame.icon:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        host._indicatorBaseAlpha = Clamp(color[4] ~= nil and color[4] or 1, 0, 1)
        host._indicatorBaseColor = color
        host._indicatorBaseVisualsReady = true
        return
    end

    if displayType == "text" and host.textFrame and host.textFrame.text and host.textFrame.text:IsShown() then
        local color = CopyColor(host._triggerTextBaseColor) or { 1, 1, 1, 1 }
        host.textFrame.text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        host._indicatorBaseAlpha = Clamp(color[4] ~= nil and color[4] or 1, 0, 1)
        host._indicatorBaseColor = color
        host._indicatorBaseVisualsReady = true
    end
end

local function ResetTextureIndicatorTransformState(host)
    if not host then
        return
    end

    local target = CooldownCompanion:GetTextureIndicatorTransformTarget(host)
    if not target then
        return
    end

    local relativeFrame = target == host.visualRoot and host or target:GetParent() or host.visualRoot
    if not relativeFrame then
        return
    end

    target:SetScale(1)
    target:ClearAllPoints()
    target:SetPoint("CENTER", relativeFrame, "CENTER", 0, 0)
end

local function GetTextureIndicatorLoopPhase(now, duration)
    duration = Clamp(tonumber(duration) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED)
    local progress = now / duration
    return progress - math_floor(progress)
end

local TextureIndicatorOnUpdate

local function RefreshTextureIndicatorUpdater(host)
    if not host or not host.visualRoot then
        return
    end

    local hasDisplayVisual = false
    if host._activeDisplayType == "texture" then
        hasDisplayVisual = host._activeTextureSettings ~= nil and host._activeTextureGeometry ~= nil
    elseif host._activeDisplayType == "icon" then
        hasDisplayVisual = host.iconFrame ~= nil and host.iconFrame:IsShown()
    elseif host._activeDisplayType == "text" then
        hasDisplayVisual = host.textFrame ~= nil and host.textFrame:IsShown()
    end

    local wantsManualUpdate = host._textureColorShiftActive
        or host._textureShrinkActive
        or host._textureBounceActive

    if not wantsManualUpdate or not hasDisplayVisual then
        host:SetScript("OnUpdate", nil)
        ResetTextureIndicatorTransformState(host)
        SetTextureIndicatorBaseVisuals(host)
        return
    end

    host:SetScript("OnUpdate", TextureIndicatorOnUpdate)
    TextureIndicatorOnUpdate(host, 0)
end

TextureIndicatorOnUpdate = function(self)
    if not self or not self.visualRoot or not self._activeDisplayType then
        RefreshTextureIndicatorUpdater(self)
        return
    end

    local transformTarget = CooldownCompanion:GetTextureIndicatorTransformTarget(self)
    if not transformTarget then
        RefreshTextureIndicatorUpdater(self)
        return
    end

    local now = GetTime()
    if not self._indicatorBaseVisualsReady then
        SetTextureIndicatorBaseVisuals(self)
    end
    local baseColor = self._indicatorBaseColor or { 1, 1, 1, 1 }
    local baseAlpha = self._indicatorBaseAlpha or 1

    if self._textureColorShiftActive then
        local shift = self._textureColorShiftColor or { 1, 1, 1, 1 }
        local colorPhase = GetTextureIndicatorLoopPhase(now, self._textureColorShiftSpeed)
        local t = 0.5 - (0.5 * math_cos(colorPhase * 2 * math_pi))
        local shiftAlpha = Clamp(shift[4] ~= nil and shift[4] or 1, 0, 1)
        local alpha = baseAlpha + ((shiftAlpha - baseAlpha) * t)

        local shiftedR = (baseColor[1] or 1) + (((shift[1] or 1) - (baseColor[1] or 1)) * t)
        local shiftedG = (baseColor[2] or 1) + (((shift[2] or 1) - (baseColor[2] or 1)) * t)
        local shiftedB = (baseColor[3] or 1) + (((shift[3] or 1) - (baseColor[3] or 1)) * t)

        if self._activeDisplayType == "texture" then
            local primaryTexture = self.primaryTexture
            if primaryTexture and primaryTexture:IsShown() then
                primaryTexture:SetVertexColor(shiftedR, shiftedG, shiftedB, alpha)
            end

            local secondaryTexture = self.secondaryTexture
            if secondaryTexture and secondaryTexture:IsShown() then
                secondaryTexture:SetVertexColor(shiftedR, shiftedG, shiftedB, alpha)
            end
        elseif self._activeDisplayType == "icon" and self.iconFrame and self.iconFrame.icon and self.iconFrame.icon:IsShown() then
            self.iconFrame.icon:SetVertexColor(shiftedR, shiftedG, shiftedB, alpha)
        elseif self._activeDisplayType == "text" and self.textFrame and self.textFrame.text and self.textFrame.text:IsShown() then
            self.textFrame.text:SetTextColor(
                (baseColor[1] or 1) + (((shift[1] or 1) - (baseColor[1] or 1)) * t),
                (baseColor[2] or 1) + (((shift[2] or 1) - (baseColor[2] or 1)) * t),
                (baseColor[3] or 1) + (((shift[3] or 1) - (baseColor[3] or 1)) * t),
                alpha
            )
        end
    end

    local scale = 1
    if self._textureShrinkActive then
        local shrinkPhase = GetTextureIndicatorLoopPhase(
            now - (self._textureShrinkStartTime or now),
            self._textureShrinkSpeed
        )
        local shrinkT = 0.5 - (0.5 * math_cos(shrinkPhase * 2 * math_pi))
        scale = 1 - ((1 - DEFAULT_TEXTURE_SHRINK_SCALE) * shrinkT)
    end
    transformTarget:SetScale(scale)

    local bounceOffsetY = 0
    if self._textureBounceActive then
        local bouncePhase = GetTextureIndicatorLoopPhase(
            now - (self._textureBounceStartTime or now),
            self._textureBounceSpeed
        )
        local amplitude = self._textureBounceAmplitude or DEFAULT_TEXTURE_BOUNCE_PIXELS
        if bouncePhase < 0.5 then
            local riseT = bouncePhase / 0.5
            bounceOffsetY = amplitude * (1 - ((1 - riseT) * (1 - riseT)))
        else
            local fallT = (bouncePhase - 0.5) / 0.5
            bounceOffsetY = amplitude * (1 - (fallT * fallT))
        end
    end

    transformTarget:ClearAllPoints()
    transformTarget:SetPoint("CENTER", transformTarget == self.visualRoot and self or transformTarget:GetParent() or self.visualRoot, "CENTER", 0, bounceOffsetY)
end

local function StopTextureIndicatorAnimation(host, effectType)
    if not host or not host.visualRoot or not host._textureIndicatorAnimations then
        return
    end

    local animData = host._textureIndicatorAnimations[effectType]
    if not animData or not animData.group then
        return
    end

    animData.group:Stop()
end

local function EnsureTextureIndicatorAnimation(host, effectType)
    if not host or not host.visualRoot then
        return nil
    end

    host._textureIndicatorAnimations = host._textureIndicatorAnimations or {}
    local existing = host._textureIndicatorAnimations[effectType]
    if existing then
        return existing
    end

    local visualRoot = host.visualRoot
    local group = visualRoot:CreateAnimationGroup()
    group:SetLooping("BOUNCE")

    local animData = { group = group }
    if effectType == TEXTURE_INDICATOR_EFFECT_PULSE then
        local alphaAnim = group:CreateAnimation("Alpha")
        alphaAnim:SetFromAlpha(1)
        alphaAnim:SetToAlpha(DEFAULT_TEXTURE_PULSE_ALPHA)
        animData.alpha = alphaAnim
    elseif effectType == TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND then
        local scaleAnim = group:CreateAnimation("Scale")
        scaleAnim:SetScaleFrom(1, 1)
        scaleAnim:SetScaleTo(DEFAULT_TEXTURE_SHRINK_SCALE, DEFAULT_TEXTURE_SHRINK_SCALE)
        scaleAnim:SetOrigin("CENTER", 0, 0)
        animData.scale = scaleAnim
    elseif effectType == TEXTURE_INDICATOR_EFFECT_BOUNCE then
        local translation = group:CreateAnimation("Translation")
        translation:SetOffset(0, DEFAULT_TEXTURE_BOUNCE_PIXELS)
        animData.translation = translation
    end

    host._textureIndicatorAnimations[effectType] = animData
    return animData
end

local function SetTextureIndicatorAnimation(host, effectType, active, speed, amplitude)
    if not host or not host.visualRoot then
        return
    end

    if effectType == TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND then
        local wasActive = host._textureShrinkActive == true
        host._textureShrinkActive = active and true or nil
        host._textureShrinkSpeed = active and Clamp(tonumber(speed) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED) or nil
        if host._textureShrinkActive and not wasActive then
            host._textureShrinkStartTime = GetTime()
        elseif not host._textureShrinkActive then
            host._textureShrinkStartTime = nil
        end
        RefreshTextureIndicatorUpdater(host)
        return
    elseif effectType == TEXTURE_INDICATOR_EFFECT_BOUNCE then
        local wasActive = host._textureBounceActive == true
        host._textureBounceActive = active and true or nil
        host._textureBounceSpeed = active and Clamp(tonumber(speed) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED) or nil
        host._textureBounceAmplitude = active and (amplitude or DEFAULT_TEXTURE_BOUNCE_PIXELS) or nil
        if host._textureBounceActive and not wasActive then
            host._textureBounceStartTime = GetTime()
        elseif not host._textureBounceActive then
            host._textureBounceStartTime = nil
        end
        RefreshTextureIndicatorUpdater(host)
        return
    end

    if not active then
        StopTextureIndicatorAnimation(host, effectType)
        if effectType == TEXTURE_INDICATOR_EFFECT_PULSE then
            host.visualRoot:SetAlpha(1)
        end
        return
    end

    local animData = EnsureTextureIndicatorAnimation(host, effectType)
    if not animData then
        return
    end

    speed = Clamp(tonumber(speed) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED)
    if effectType == TEXTURE_INDICATOR_EFFECT_PULSE and animData.alpha then
        animData.alpha:SetDuration(speed)
    end

    if not animData.group:IsPlaying() then
        animData.group:Play()
    end
end

local function StopTextureColorShift(host)
    if not host then
        return
    end

    host._textureColorShiftActive = nil
    host._indicatorBaseVisualsReady = nil
    RefreshTextureIndicatorUpdater(host)
end

local function StartTextureColorShift(host, shiftColor, speed)
    if not host then
        return
    end

    host._textureColorShiftActive = true
    host._textureColorShiftColor = CopyColor(shiftColor) or { 1, 1, 1, 1 }
    host._textureColorShiftSpeed = Clamp(tonumber(speed) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED)
    RefreshTextureIndicatorUpdater(host)
end

local function StopAllTextureIndicatorEffects(host)
    if not host or not host.visualRoot then
        return
    end

    StopTextureIndicatorAnimation(host, TEXTURE_INDICATOR_EFFECT_PULSE)
    host._textureShrinkActive = nil
    host._textureShrinkSpeed = nil
    host._textureShrinkStartTime = nil
    host._textureBounceActive = nil
    host._textureBounceSpeed = nil
    host._textureBounceAmplitude = nil
    host._textureBounceStartTime = nil
    host._textureColorShiftActive = nil
    host._textureColorShiftColor = nil
    host._textureColorShiftSpeed = nil
    host.visualRoot:SetAlpha(1)
    ResetTextureIndicatorTransformState(host)
    host:SetScript("OnUpdate", nil)
    SetTextureIndicatorBaseVisuals(host)
end

local function SetTextureEffectFlag(target, effectType, sectionKey, active)
    if not target or not effectType then
        return
    end

    if effectType == TEXTURE_INDICATOR_EFFECT_PULSE then
        target.pulseActive = active == true
        target.pulseSection = active and sectionKey or nil
    elseif effectType == TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT then
        target.colorShiftActive = active == true
        target.colorShiftSection = active and sectionKey or nil
    elseif effectType == TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND then
        target.shrinkExpandActive = active == true
        target.shrinkExpandSection = active and sectionKey or nil
    elseif effectType == TEXTURE_INDICATOR_EFFECT_BOUNCE then
        target.bounceActive = active == true
        target.bounceSection = active and sectionKey or nil
    end
end

local function FinishTextureIndicatorSectionState(target, active, reason, preview, effectType)
    if target then
        target.active = active == true
        target.reason = reason
        if preview ~= nil then
            target.preview = preview == true
        end
    end
    return active == true, effectType, target
end

local function ResolveTextureIndicatorSectionState(button, sectionKey, config, target)
    local hasTarget = type(target) == "table"
    local hasConfig = type(config) == "table"
    local effectType = hasConfig and NormalizeTextureIndicatorEffect(config.effectType) or nil
    if hasTarget then
        target.enabled = hasConfig and config.enabled == true
        target.effectType = hasConfig and config.effectType or nil
        target.normalizedEffectType = effectType
        target.combatOnly = hasConfig and config.combatOnly == true
        target.invert = hasConfig and config.invert == true
        target.preview = false
        target.active = false
        target.reason = nil
    end

    if not button then
        return FinishTextureIndicatorSectionState(target, false, "missing-button", nil, effectType)
    end
    if not hasConfig then
        return FinishTextureIndicatorSectionState(target, false, "missing-config", nil, effectType)
    end
    if config.enabled ~= true then
        return FinishTextureIndicatorSectionState(target, false, "disabled", nil, effectType)
    end

    local previewActive = (sectionKey == "proc" and button._textureProcPreview)
        or (sectionKey == "aura" and button._textureAuraPreview)
        or (sectionKey == "pandemic" and button._texturePandemicPreview)
        or (sectionKey == "ready" and button._textureReadyPreview)
        or (sectionKey == "unusable" and button._textureUnusablePreview)
    if previewActive then
        return FinishTextureIndicatorSectionState(target, true, "preview", true, effectType)
    end

    if config.combatOnly and not InCombatLockdown() then
        return FinishTextureIndicatorSectionState(target, false, "out-of-combat", nil, effectType)
    end

    if sectionKey == "proc" then
        local active = button._procOverlayActive == true
        return FinishTextureIndicatorSectionState(target, active, active and "proc-active" or "proc-inactive", nil, effectType)
    end

    if sectionKey == "aura" then
        if button._auraTrackingReady ~= true or not button._auraSpellID then
            return FinishTextureIndicatorSectionState(target, false, "aura-missing", nil, effectType)
        end
        if config.invert then
            if button._auraUnit == "target" and not UnitExists("target") then
                return FinishTextureIndicatorSectionState(target, false, "missing-target", nil, effectType)
            end
            local active = button._auraActive ~= true
            return FinishTextureIndicatorSectionState(target, active, active and "aura-inactive" or "aura-active", nil, effectType)
        end
        local active = button._auraActive == true
        return FinishTextureIndicatorSectionState(target, active, active and "aura-active" or "aura-inactive", nil, effectType)
    end

    if sectionKey == "pandemic" then
        local active = button._auraActive == true and button._inPandemic == true
        return FinishTextureIndicatorSectionState(target, active, active and "pandemic" or "inactive", nil, effectType)
    end

    if sectionKey == "ready" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.isPassive or button._noCooldown then
            local reason = not buttonData and "missing-button-data"
                or buttonData.isPassive and "passive"
                or "no-cooldown"
            return FinishTextureIndicatorSectionState(target, false, reason, nil, effectType)
        end
        local active = button._desatCooldownActive == false
        return FinishTextureIndicatorSectionState(target, active, active and "ready" or "not-ready", nil, effectType)
    end

    if sectionKey == "unusable" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.isPassive then
            return FinishTextureIndicatorSectionState(target, false, not buttonData and "missing-button-data" or "passive", nil, effectType)
        end
        if buttonData.type == "spell" then
            local spellID = button._displaySpellId or buttonData.id
            local active = not C_Spell_IsSpellUsable(spellID)
            return FinishTextureIndicatorSectionState(target, active, active and "unusable" or "usable", nil, effectType)
        end
        if buttonData.type == "item" or buttonData.type == "equipitem" then
            local active = not C_Item_IsUsableItem(button._resolvedItemId or buttonData.id)
            return FinishTextureIndicatorSectionState(target, active, active and "unusable" or "usable", nil, effectType)
        end
        return FinishTextureIndicatorSectionState(target, false, "unsupported-type", nil, effectType)
    end

    return FinishTextureIndicatorSectionState(target, false, "unknown-section", nil, effectType)
end

local function EvaluateTriggerRowCondition(button, conditionKey)
    if not button then
        return false
    end

    if conditionKey == "cooldownActive" then
        return button._desatCooldownActive == true
    end

    if conditionKey == "auraActive" then
        return button._auraActive == true
    end

    if conditionKey == "procActive" then
        return button._procOverlayActive == true
    end

    if conditionKey == "rangeActive" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.isPassive then
            return nil
        end

        if buttonData.type == "spell" then
            if button._spellOutOfRange == nil then
                return nil
            end
            return button._spellOutOfRange == false
        end

        if buttonData.type == "item" or buttonData.type == "equipitem" then
            if not InCombatLockdown() or UnitCanAttack("player", "target") then
                local inRange = C_Item_IsItemInRange(button._resolvedItemId or buttonData.id, "target")
                if inRange == nil then
                    return nil
                end
                return inRange == true
            end
            return nil
        end

        return nil
    end

    if conditionKey == "usable" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.isPassive then
            return false
        end
        if buttonData.type == "spell" then
            local spellID = button._displaySpellId or buttonData.id
            return C_Spell_IsSpellUsable(spellID)
        end
        if buttonData.type == "item" or buttonData.type == "equipitem" then
            return C_Item_IsUsableItem(button._resolvedItemId or buttonData.id)
        end
        return false
    end

    if conditionKey == "chargesRecharging" then
        return button._chargeRecharging == true
    end

    if conditionKey == "chargeState" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.hasCharges ~= true then
            return nil
        end

        return button._chargeState
    end

    if conditionKey == "countTextActive" then
        local buttonData = button.buttonData
        if not buttonData
                or not CooldownCompanion.HasNonChargeCountTextBehavior
                or not CooldownCompanion.HasNonChargeCountTextBehavior(buttonData) then
            return nil
        end

        local countText = button.count and button.count:GetText() or nil
        if issecretvalue(countText) then
            return true
        end
        return countText ~= nil and countText ~= ""
    end

    if conditionKey == "countState" then
        local buttonData = button.buttonData
        if not buttonData
                or (buttonData._hasDisplayCount ~= true and buttonData._displayCountFamily ~= true)
                or buttonData.hasCharges == true
        then
            return nil
        end

        local currentCount = button._currentReadableCharges
        local maxCount = buttonData.maxCharges
        if currentCount == nil then
            return nil
        end
        if currentCount <= 0 then
            return "zero"
        end
        if maxCount ~= nil and maxCount > 0 then
            if currentCount >= maxCount then
                return "full"
            end
            return "missing"
        end
        return nil
    end

    return false
end

local function DoesTriggerPanelMatch(frame, captureDetails)
    if not frame then
        return false
    end

    local group = frame.groupId and ResolveGroup(frame.groupId) or nil
    local configuredRows = group and group.buttons
    captureDetails = captureDetails == true or ShouldCaptureButtonVisualState()
    local panelState
    if captureDetails then
        panelState = {
            rowCount = type(configuredRows) == "table" and #configuredRows or 0,
            rows = {},
        }
    end
    if type(configuredRows) ~= "table" or #configuredRows == 0 then
        return FinishTriggerPanelMatch(frame, panelState, false, "missing-config")
    end

    local runtimeButtonsByIndex = frame._triggerRuntimeButtonsByIndex
    if runtimeButtonsByIndex then
        wipe(runtimeButtonsByIndex)
    else
        runtimeButtonsByIndex = {}
        frame._triggerRuntimeButtonsByIndex = runtimeButtonsByIndex
    end
    for _, button in ipairs(frame.buttons or {}) do
        if button and button.index then
            runtimeButtonsByIndex[button.index] = button
        end
    end
    if panelState then
        panelState.runtimeRowCount = type(frame.buttons) == "table" and #frame.buttons or 0
        ClearTriggerVisualRows(frame.buttons)
    end

    local activeRowCount = 0
    local function finish(matched, reason)
        if panelState then
            panelState.activeRowCount = activeRowCount
        end
        return FinishTriggerPanelMatch(frame, panelState, matched, reason)
    end

    for rowIndex, buttonData in ipairs(configuredRows) do
        local rowState
        if panelState then
            rowState = {
                rowIndex = rowIndex,
                enabled = type(buttonData) == "table" and buttonData.enabled ~= false or false,
            }
            panelState.rows[#panelState.rows + 1] = rowState
        end

        if type(buttonData) ~= "table" then
            if rowState then
                rowState.matched = false
                rowState.reason = "invalid-row"
            end
            return finish(false, "invalid-row")
        end

        if buttonData.enabled == false then
            if rowState then
                rowState.skipped = true
                rowState.reason = "disabled"
            end
        else
            local clauses = CooldownCompanion:GetTriggerConditionClauses(buttonData)
            activeRowCount = activeRowCount + 1
            if rowState then
                rowState.active = true
                rowState.conditionCount = #clauses
            end

            if #clauses == 0 then
                if rowState then
                    rowState.matched = false
                    rowState.reason = "no-conditions"
                end
                return finish(false, "no-conditions")
            end

            local runtimeButton = runtimeButtonsByIndex[rowIndex]
            if not runtimeButton then
                if rowState then
                    rowState.matched = false
                    rowState.reason = "missing-runtime"
                end
                return finish(false, "missing-runtime")
            end
            if rowState then
                rowState.hasRuntime = true
                runtimeButton._triggerVisualRow = rowState
            end

            for _, clause in ipairs(clauses) do
                local conditionKey = NormalizeTriggerConditionKey(buttonData, clause.key)
                if not conditionKey then
                    if rowState then
                        rowState.matched = false
                        rowState.reason = "invalid-condition"
                    end
                    return finish(false, "invalid-condition")
                end

                local actualState = EvaluateTriggerRowCondition(runtimeButton, conditionKey)
                local expectedState
                local conditionMatched
                if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
                    expectedState = clause.expected ~= false
                    conditionMatched = actualState == expectedState
                else
                    expectedState = NormalizeTriggerStateKey(conditionKey, clause.state)
                    conditionMatched = actualState == expectedState
                end

                if rowState then
                    local conditions = rowState.conditions
                    if type(conditions) ~= "table" then
                        conditions = {}
                        rowState.conditions = conditions
                    end
                    conditions[#conditions + 1] = {
                        key = conditionKey,
                        expected = expectedState,
                        actual = actualState,
                        matched = conditionMatched,
                    }
                end

                if not conditionMatched then
                    if rowState then
                        rowState.matched = false
                        rowState.reason = "condition-mismatch"
                        rowState.failedConditionKey = conditionKey
                        rowState.expected = expectedState
                        rowState.actual = actualState
                    end
                    return finish(false, "condition-mismatch")
                end
            end

            if rowState then
                rowState.matched = true
                rowState.reason = "matched"
            end
        end
    end

    return finish(
        activeRowCount > 0,
        activeRowCount > 0 and "matched" or "no-active-rows"
    )
end

local function ApplyTextureIndicatorEffects(host, button, group)
    if not host or not button or type(group) ~= "table" then
        return
    end

    local captureVisualState = ShouldCaptureButtonVisualState()
    local freezeGeometryWhileUnlocked = group.locked == false
    local intentState
    local appliedState
    local effectSources
    if captureVisualState then
        intentState = {
            hasIndicators = false,
            freezeGeometryWhileUnlocked = freezeGeometryWhileUnlocked,
            sections = {},
        }
        appliedState = {
            freezeGeometryWhileUnlocked = freezeGeometryWhileUnlocked,
        }
        effectSources = {}
    end

    local indicators = CooldownCompanion:GetTexturePanelIndicatorSettings(group)
    if not indicators then
        StopAllTextureIndicatorEffects(host)
        if captureVisualState then
            button._textureEffectIntent = intentState
            button._textureEffectApplied = appliedState
        end
        return
    end
    if intentState then
        intentState.hasIndicators = true
    end

    local effectStates = host._textureIndicatorEffectStates
    if effectStates then
        wipe(effectStates)
    else
        effectStates = {}
        host._textureIndicatorEffectStates = effectStates
    end
    for _, sectionKey in ipairs(TEXTURE_INDICATOR_SECTION_ORDER) do
        local config = indicators[sectionKey]
        local sectionTarget = intentState and {} or nil
        local active, effectType, sectionState = ResolveTextureIndicatorSectionState(button, sectionKey, config, sectionTarget)
        if intentState and sectionState then
            intentState.sections[sectionKey] = sectionState
        end
        if active then
            if effectType and effectType ~= TEXTURE_INDICATOR_EFFECT_NONE and not effectStates[effectType] then
                effectStates[effectType] = config
                if effectSources then
                    effectSources[effectType] = sectionKey
                end
            end
        end
    end

    if intentState then
        SetTextureEffectFlag(intentState, TEXTURE_INDICATOR_EFFECT_PULSE, effectSources[TEXTURE_INDICATOR_EFFECT_PULSE], effectStates[TEXTURE_INDICATOR_EFFECT_PULSE] ~= nil)
        SetTextureEffectFlag(intentState, TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT, effectSources[TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT], effectStates[TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT] ~= nil)
        SetTextureEffectFlag(intentState, TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND, effectSources[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND], (not freezeGeometryWhileUnlocked) and effectStates[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND] ~= nil)
        SetTextureEffectFlag(intentState, TEXTURE_INDICATOR_EFFECT_BOUNCE, effectSources[TEXTURE_INDICATOR_EFFECT_BOUNCE], (not freezeGeometryWhileUnlocked) and effectStates[TEXTURE_INDICATOR_EFFECT_BOUNCE] ~= nil)
        intentState.shrinkExpandSuppressedByUnlock = freezeGeometryWhileUnlocked and effectStates[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND] ~= nil or false
        intentState.bounceSuppressedByUnlock = freezeGeometryWhileUnlocked and effectStates[TEXTURE_INDICATOR_EFFECT_BOUNCE] ~= nil or false
    end

    local bounceAmplitude = math_max(
        6,
        math_min(
            DEFAULT_TEXTURE_BOUNCE_PIXELS,
            (host._activeTextureGeometry and host._activeTextureGeometry.boundsHeight or DEFAULT_TEXTURE_BOUNCE_PIXELS) * 0.12
        )
    )

    SetTextureIndicatorAnimation(
        host,
        TEXTURE_INDICATOR_EFFECT_PULSE,
        effectStates[TEXTURE_INDICATOR_EFFECT_PULSE] ~= nil,
        effectStates[TEXTURE_INDICATOR_EFFECT_PULSE] and effectStates[TEXTURE_INDICATOR_EFFECT_PULSE].speed or nil
    )
    SetTextureIndicatorAnimation(
        host,
        TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND,
        (not freezeGeometryWhileUnlocked) and effectStates[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND] ~= nil,
        effectStates[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND] and effectStates[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND].speed or nil
    )
    SetTextureIndicatorAnimation(
        host,
        TEXTURE_INDICATOR_EFFECT_BOUNCE,
        (not freezeGeometryWhileUnlocked) and effectStates[TEXTURE_INDICATOR_EFFECT_BOUNCE] ~= nil,
        effectStates[TEXTURE_INDICATOR_EFFECT_BOUNCE] and effectStates[TEXTURE_INDICATOR_EFFECT_BOUNCE].speed or nil,
        bounceAmplitude
    )

    local colorShift = effectStates[TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT]
    if colorShift then
        StartTextureColorShift(host, colorShift.color, colorShift.speed)
    else
        StopTextureColorShift(host)
    end

    if appliedState then
        SetTextureEffectFlag(appliedState, TEXTURE_INDICATOR_EFFECT_PULSE, effectSources[TEXTURE_INDICATOR_EFFECT_PULSE], effectStates[TEXTURE_INDICATOR_EFFECT_PULSE] ~= nil)
        SetTextureEffectFlag(appliedState, TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT, effectSources[TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT], colorShift ~= nil)
        SetTextureEffectFlag(appliedState, TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND, effectSources[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND], (not freezeGeometryWhileUnlocked) and effectStates[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND] ~= nil)
        SetTextureEffectFlag(appliedState, TEXTURE_INDICATOR_EFFECT_BOUNCE, effectSources[TEXTURE_INDICATOR_EFFECT_BOUNCE], (not freezeGeometryWhileUnlocked) and effectStates[TEXTURE_INDICATOR_EFFECT_BOUNCE] ~= nil)
        button._textureEffectIntent = intentState
        button._textureEffectApplied = appliedState
    end
end

function CooldownCompanion:ApplyTriggerPanelEffects(host, button, group, effectsActive)
    if not host or not button or type(group) ~= "table" then
        return
    end

    local effects = CooldownCompanion:GetTriggerPanelEffectSettings(group)
    if not effects or not effectsActive then
        StopAllTextureIndicatorEffects(host)
        return
    end

    SetTextureIndicatorBaseVisuals(host)

    local freezeGeometryWhileUnlocked = group.locked == false
    local bounceAmplitude = math_max(
        6,
        math_min(
            DEFAULT_TEXTURE_BOUNCE_PIXELS,
            ((host:GetHeight() and host:GetHeight() > 0) and host:GetHeight() or DEFAULT_TEXTURE_BOUNCE_PIXELS) * 0.12
        )
    )
    local allowShrinkExpand = host._activeDisplayType ~= "text" and not freezeGeometryWhileUnlocked

    SetTextureIndicatorAnimation(
        host,
        TEXTURE_INDICATOR_EFFECT_PULSE,
        effects.pulse and effects.pulse.enabled == true,
        effects.pulse and effects.pulse.speed or nil
    )
    SetTextureIndicatorAnimation(
        host,
        TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND,
        allowShrinkExpand and effects.shrinkExpand and effects.shrinkExpand.enabled == true,
        allowShrinkExpand and effects.shrinkExpand and effects.shrinkExpand.speed or nil
    )
    SetTextureIndicatorAnimation(
        host,
        TEXTURE_INDICATOR_EFFECT_BOUNCE,
        (not freezeGeometryWhileUnlocked) and effects.bounce and effects.bounce.enabled == true,
        effects.bounce and effects.bounce.speed or nil,
        bounceAmplitude
    )

    if effects.colorShift and effects.colorShift.enabled == true then
        StartTextureColorShift(host, effects.colorShift.color, effects.colorShift.speed)
    else
        StopTextureColorShift(host)
    end
end

AT.LayoutTexturePieces = LayoutTexturePieces
AT.SetTextureIndicatorBaseVisuals = SetTextureIndicatorBaseVisuals
AT.StopAllTextureIndicatorEffects = StopAllTextureIndicatorEffects
AT.ApplyTextureIndicatorEffects = ApplyTextureIndicatorEffects
AT.DoesTriggerPanelMatch = DoesTriggerPanelMatch
