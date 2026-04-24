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
        return
    end

    if displayType == "icon" and host.iconFrame and host.iconFrame.icon and host.iconFrame.icon:IsShown() then
        local color = CopyColor(host._triggerIconBaseColor) or { 1, 1, 1, 1 }
        host.iconFrame.icon:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        host._indicatorBaseAlpha = Clamp(color[4] ~= nil and color[4] or 1, 0, 1)
        host._indicatorBaseColor = color
        return
    end

    if displayType == "text" and host.textFrame and host.textFrame.text and host.textFrame.text:IsShown() then
        local color = CopyColor(host._triggerTextBaseColor) or { 1, 1, 1, 1 }
        host.textFrame.text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        host._indicatorBaseAlpha = Clamp(color[4] ~= nil and color[4] or 1, 0, 1)
        host._indicatorBaseColor = color
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
    SetTextureIndicatorBaseVisuals(self)
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

local function IsTextureIndicatorSectionActive(button, sectionKey, config)
    if not button or type(config) ~= "table" or not config.enabled then
        return false
    end

    if sectionKey == "proc" and button._textureProcPreview then
        return true
    end
    if sectionKey == "aura" and button._textureAuraPreview then
        return true
    end
    if sectionKey == "pandemic" and button._texturePandemicPreview then
        return true
    end
    if sectionKey == "ready" and button._textureReadyPreview then
        return true
    end
    if sectionKey == "unusable" and button._textureUnusablePreview then
        return true
    end

    if config.combatOnly and not InCombatLockdown() then
        return false
    end

    if sectionKey == "proc" then
        return button._procOverlayActive == true
    end

    if sectionKey == "aura" then
        if button._auraTrackingReady ~= true or not button._auraSpellID then
            return false
        end
        if config.invert then
            if button._auraUnit == "target" and not UnitExists("target") then
                return false
            end
            return button._auraActive ~= true
        end
        return button._auraActive == true
    end

    if sectionKey == "pandemic" then
        return button._auraActive == true and button._inPandemic == true
    end

    if sectionKey == "ready" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.isPassive or button._noCooldown then
            return false
        end
        return button._desatCooldownActive == false
    end

    if sectionKey == "unusable" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.isPassive then
            return false
        end
        if buttonData.type == "spell" then
            return not C_Spell_IsSpellUsable(buttonData.id)
        end
        if buttonData.type == "item" or buttonData.type == "equipitem" then
            return not C_Item_IsUsableItem(buttonData.id)
        end
        return false
    end

    return false
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
                local inRange = C_Item_IsItemInRange(buttonData.id, "target")
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
            return C_Spell_IsSpellUsable(buttonData.id)
        end
        if buttonData.type == "item" or buttonData.type == "equipitem" then
            return C_Item_IsUsableItem(buttonData.id)
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

local function DoesTriggerPanelMatch(frame)
    if not frame then
        return false
    end

    local group = frame.groupId and ResolveGroup(frame.groupId) or nil
    local configuredRows = group and group.buttons
    if type(configuredRows) ~= "table" or #configuredRows == 0 then
        return false
    end

    local runtimeButtonsByIndex = {}
    for _, button in ipairs(frame.buttons or {}) do
        if button and button.index then
            runtimeButtonsByIndex[button.index] = button
        end
    end

    local activeRowCount = 0
    for rowIndex, buttonData in ipairs(configuredRows) do
        if type(buttonData) ~= "table" then
            return false
        end

        if buttonData.enabled ~= false then
            local clauses = CooldownCompanion:GetTriggerConditionClauses(buttonData)
            if #clauses == 0 then
                return false
            end

            activeRowCount = activeRowCount + 1
            local runtimeButton = runtimeButtonsByIndex[rowIndex]
            if not runtimeButton then
                return false
            end

            for _, clause in ipairs(clauses) do
                local conditionKey = NormalizeTriggerConditionKey(buttonData, clause.key)
                if not conditionKey then
                    return false
                end

                local actualState = EvaluateTriggerRowCondition(runtimeButton, conditionKey)
                if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
                    local expected = clause.expected ~= false
                    if actualState ~= expected then
                        return false
                    end
                else
                    local expectedState = NormalizeTriggerStateKey(conditionKey, clause.state)
                    if actualState ~= expectedState then
                        return false
                    end
                end
            end
        end
    end

    return activeRowCount > 0
end

local function ApplyTextureIndicatorEffects(host, button, group)
    if not host or not button or type(group) ~= "table" then
        return
    end

    local indicators = CooldownCompanion:GetTexturePanelIndicatorSettings(group)
    if not indicators then
        StopAllTextureIndicatorEffects(host)
        return
    end

    local effectStates = {}
    for _, sectionKey in ipairs(TEXTURE_INDICATOR_SECTION_ORDER) do
        local config = indicators[sectionKey]
        if IsTextureIndicatorSectionActive(button, sectionKey, config) then
            local effectType = NormalizeTextureIndicatorEffect(config.effectType)
            if effectType ~= TEXTURE_INDICATOR_EFFECT_NONE and not effectStates[effectType] then
                effectStates[effectType] = config
            end
        end
    end

    local freezeGeometryWhileUnlocked = group.locked == false
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
