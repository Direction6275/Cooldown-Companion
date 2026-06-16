--[[
    CooldownCompanion - Core/RefreshScope.lua: structured refresh reasons and
    conservative target/aura scoped refresh predicates.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic or {}
local COOLDOWN_STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN or "cooldown"
local CHARGE_STATE_FULL = CooldownLogic.CHARGE_STATE_FULL or "full"
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING or "missing"
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO or "zero"

local SCOPED_REASON_KINDS = {
    ["periodic"] = true,
    ["spell-usability"] = true,
    ["target-changed"] = true,
    ["unit-target"] = true,
    ["unit-aura"] = true,
}

local function CopyReason(reason)
    if type(reason) ~= "table" then
        return nil
    end
    local copy = {}
    for key, value in pairs(reason) do
        copy[key] = value
    end
    return copy
end

local function FullReason(source, fallbackOrigin, fallbackReason)
    return {
        kind = "full",
        source = source or "event",
        origin = fallbackOrigin,
        broad = true,
        fallbackReason = fallbackReason,
    }
end

function CooldownCompanion:NormalizeCooldownRefreshReason(reasonOrSource, fallbackOrigin)
    if type(reasonOrSource) ~= "table" then
        return FullReason(reasonOrSource, fallbackOrigin, "string-or-empty-source")
    end

    local kind = reasonOrSource.kind
    if not SCOPED_REASON_KINDS[kind] then
        local reason = CopyReason(reasonOrSource) or {}
        reason.kind = kind or "full"
        reason.source = reason.source or "event"
        reason.origin = reason.origin or fallbackOrigin
        reason.broad = true
        reason.fallbackReason = reason.fallbackReason or "unsupported-kind"
        return reason
    end

    if kind == "periodic" then
        local reason = CopyReason(reasonOrSource) or {}
        reason.source = reason.source or "ticker"
        reason.origin = reason.origin or fallbackOrigin
        reason.broad = false
        return reason
    end

    if kind == "spell-usability" then
        local reason = CopyReason(reasonOrSource) or {}
        reason.source = reason.source or "event"
        reason.origin = reason.origin or fallbackOrigin
        reason.unit = nil
        reason.broad = false
        return reason
    end

    local unit = reasonOrSource.unit
    if kind == "unit-aura" and unit ~= "player" and unit ~= "target" then
        return FullReason(reasonOrSource.source, fallbackOrigin, "unsupported-aura-unit")
    end
    if (kind == "target-changed" or kind == "unit-target") and unit ~= nil and unit ~= "target" then
        return FullReason(reasonOrSource.source, fallbackOrigin, "unsupported-target-unit")
    end

    local reason = CopyReason(reasonOrSource) or {}
    reason.source = reason.source or "event"
    reason.origin = reason.origin or fallbackOrigin
    reason.unit = unit or "target"
    reason.broad = false
    return reason
end

function CooldownCompanion:GetCooldownRefreshReasonSource(reason)
    if type(reason) == "table" then
        return reason.source or reason.kind or "event"
    end
    return reason or "event"
end

function CooldownCompanion:IsScopedCooldownRefreshReason(reason)
    return type(reason) == "table"
        and reason.broad ~= true
        and SCOPED_REASON_KINDS[reason.kind] == true
end

function CooldownCompanion:CombineCooldownRefreshReasons(existingReason, nextReason)
    if not existingReason then
        return nextReason
    end
    if not nextReason then
        return existingReason
    end

    local existing = self:NormalizeCooldownRefreshReason(existingReason, "combine-existing")
    local nextValue = self:NormalizeCooldownRefreshReason(nextReason, "combine-next")

    if not self:IsScopedCooldownRefreshReason(existing) or not self:IsScopedCooldownRefreshReason(nextValue) then
        return FullReason(nextValue.source or existing.source, "combine", "mixed-full-or-unsupported")
    end

    if existing.kind == nextValue.kind and existing.unit == nextValue.unit then
        return nextValue
    end

    if (existing.kind == "target-changed" or existing.kind == "unit-target")
        and (nextValue.kind == "target-changed" or nextValue.kind == "unit-target") then
        return nextValue
    end

    return FullReason(nextValue.source or existing.source, "combine", "mixed-scoped-reasons")
end

local function ButtonHasAuraDependency(button, buttonData, unit)
    if not (buttonData and (buttonData.auraTracking == true or buttonData.isPassive == true)) then
        return false
    end
    local configUnit = buttonData.auraUnit or "player"
    return (button and button._auraUnit == unit) or configUnit == unit
end

local function TextSegmentsUseToken(segments, tokenName)
    if type(segments) ~= "table" then
        return false
    end
    for _, segment in ipairs(segments) do
        if segment.type == "token" and segment.value == tokenName then
            return true
        end
        if segment.type == "cond_start" and segment.value == tokenName then
            return true
        end
        if TextSegmentsUseToken(segment.children, tokenName) then
            return true
        end
    end
    return false
end

local function ButtonUsesAssistedTargetGate(button, buttonData)
    if not (button and button.assistedHighlight and buttonData and buttonData.type == "spell") then
        return false
    end
    local style = button.style
    return style
        and style.showAssistedHighlight == true
        and style.assistedHighlightHostileTargetOnly ~= false
end

local function ButtonUsesAssistedHighlight(button, buttonData)
    if not (button and button.assistedHighlight and buttonData and buttonData.type == "spell") then
        return false
    end
    local style = button.style
    return style and style.showAssistedHighlight == true
end

local function ButtonUsesTextureUnusableIndicator(button)
    local style = button and button.style
    local indicators = style and style.textureIndicators
    local unusable = indicators and indicators.unusable
    return type(unusable) == "table" and unusable.enabled == true
end

local function ButtonUsesUnusableTargetGate(button, buttonData)
    if buttonData.isPassive == true or buttonData.isPassiveCooldown == true then
        return false
    end
    local style = button and button.style
    if buttonData.hideWhileUnusable == true then
        return true
    end
    if not (style and style.showUnusable == true) then
        return false
    end
    if ST.GetUnusableVisualMode then
        return ST.GetUnusableVisualMode(style) ~= ST.UNUSABLE_VISUAL_MODE_NONE
    end
    return true
end

local function ButtonUsesTargetRangeOrUsability(addon, button, buttonData)
    if not buttonData then
        return false
    end

    local style = button and button.style
    local isSpell = buttonData.type == "spell"
        and buttonData.isPassive ~= true
        and buttonData.isPassiveCooldown ~= true
    local isItemLike = addon.IsEntryItemLike and addon.IsEntryItemLike(buttonData)
    if not (isSpell or isItemLike or buttonData.type == "equipitem") then
        return false
    end

    if style and style.showOutOfRange == true then
        return true
    end
    if ButtonUsesAssistedTargetGate(button, buttonData) then
        return true
    end
    if ButtonUsesUnusableTargetGate(button, buttonData) then
        return true
    end
    if ButtonUsesTextureUnusableIndicator(button) then
        return true
    end
    if button and button._isText and (
        TextSegmentsUseToken(button._textSegments, "oor")
        or TextSegmentsUseToken(button._textSegments, "unusable")
    ) then
        return true
    end
    if addon.TriggerRowUsesCondition then
        return addon:TriggerRowUsesCondition(buttonData, "rangeActive")
            or addon:TriggerRowUsesCondition(buttonData, "usable")
    end
    return false
end

local function ButtonUsesSpellUsability(addon, button, buttonData)
    if not (buttonData and buttonData.type == "spell")
        or buttonData.isPassive == true
        or buttonData.isPassiveCooldown == true then
        return false
    end
    if ButtonUsesUnusableTargetGate(button, buttonData) then
        return true
    end
    if ButtonUsesTextureUnusableIndicator(button) then
        return true
    end
    if button and button._isText and TextSegmentsUseToken(button._textSegments, "unusable") then
        return true
    end
    return addon
        and addon.TriggerRowUsesCondition
        and addon:TriggerRowUsesCondition(buttonData, "usable")
end

local function ButtonUsesReadyGlowDuration(button)
    local style = button and button.style
    if not style then
        return false, nil, 0
    end
    local duration = style.readyGlowDuration or 0
    if duration <= 0 then
        return false, nil, 0
    end
    if not style.readyGlowStyle or style.readyGlowStyle == "none" then
        return false, nil, 0
    end
    return true, style, duration
end

local function ReadyGlowStartWithinWindow(startTime, duration)
    if startTime == nil then
        return false
    end
    local now = type(GetTime) == "function" and GetTime() or nil
    if not now then
        return true
    end
    return now - startTime <= duration + 0.2
end

local function ButtonUsesMaxChargeReadyGlow(buttonData, style)
    return style
        and style.readyGlowOnlyAtMaxCharges == true
        and buttonData
        and buttonData.type == "spell"
        and buttonData.hasCharges == true
        and not buttonData._hasDisplayCount
end

local function ButtonNeedsReadyGlowPeriodicRefresh(button, buttonData)
    local enabled, style, duration = ButtonUsesReadyGlowDuration(button)
    if not enabled then
        return false
    end
    if ButtonUsesMaxChargeReadyGlow(buttonData, style) then
        if ReadyGlowStartWithinWindow(button._readyGlowMaxChargesStartTime, duration) then
            return true
        end
        if button._readyGlowActive == true then
            return true
        end
        return button._chargeState ~= nil and button._chargeState ~= CHARGE_STATE_FULL
    end
    return ReadyGlowStartWithinWindow(button._readyGlowStartTime, duration)
        or button._readyGlowActive == true
        or button._desatCooldownActive == true
end

local function ButtonNeedsIconCooldownTextPeriodicRefresh(button)
    if not (button and button._cdTextRegion and not button._isText and not button._isBar) then
        return false
    end
    local style = button.style
    if not style then
        return false
    end
    if button._auraPrimarySwipeActive == true or button._conditionalAuraDurationTextPreview == true then
        return style.showAuraText ~= false
    end
    if button._secondaryCdTextRegion and button._secondaryCdActive == true then
        return style.showCooldownText == true
    end
    return button._desatCooldownActive == true
        and style.showCooldownText == true
        and button._hideCooldownChargesActive ~= true
end

local function ButtonNeedsBarPeriodicRefresh(button)
    if not (button and button._isBar == true) then
        return false
    end
    if button._desatCooldownActive == true or button._cooldownState == COOLDOWN_STATE_COOLDOWN then
        return true
    end
    if button._chargeState == CHARGE_STATE_ZERO or button._chargeState == CHARGE_STATE_MISSING then
        return true
    end
    return button._auraActive == true
        and (button._durationObj ~= nil or button._viewerBar ~= nil or button._conditionalPreviewRemaining ~= nil)
end

local function TextureIndicatorEnabled(style, sectionKey)
    local indicators = style and style.textureIndicators
    local section = indicators and indicators[sectionKey]
    return type(section) == "table" and section.enabled == true
end

local function ButtonHasCooldownDrivenIconFeature(button, buttonData, style)
    if style.showCooldownSwipe ~= false
        and (style.showCooldownSwipeFill ~= false or style.showCooldownSwipeEdge ~= false) then
        return true
    end
    if style.desaturateOnCooldown == true or buttonData.desaturateWhileZeroCharges == true then
        return true
    end
    if style.iconFillEnabled == true then
        return true
    end
    if TextureIndicatorEnabled(style, "cooldown")
        or TextureIndicatorEnabled(style, "ready")
        or TextureIndicatorEnabled(style, "unusable") then
        return true
    end
    if buttonData.hideWhileOnCooldown == true or buttonData.hideWhileNotOnCooldown == true then
        return true
    end
    local soundAlerts = buttonData.soundAlerts
    if soundAlerts and type(soundAlerts.events) == "table" and next(soundAlerts.events) ~= nil then
        return true
    end
    if style.readyGlowStyle and style.readyGlowStyle ~= "none" then
        return true
    end
    return false
end

local function ButtonNeedsIconCooldownStatePeriodicRefresh(button, buttonData)
    if not (button and buttonData and not button._isText and not button._isBar) then
        return false
    end
    local style = button.style
    if not style then
        return false
    end
    if button._desatCooldownActive ~= true
        and button._cooldownState ~= COOLDOWN_STATE_COOLDOWN
        and button._chargeState ~= CHARGE_STATE_ZERO
        and button._chargeState ~= CHARGE_STATE_MISSING then
        return false
    end
    return ButtonHasCooldownDrivenIconFeature(button, buttonData, style)
end

local function ButtonUsesActiveAuraIcon(buttonData)
    return buttonData
        and (buttonData.auraShowAuraIcon == true
            or buttonData.addedAs == "aura"
            or buttonData.isPassive == true)
end

local function ButtonNeedsAuraIconVisualPeriodicRefresh(button, buttonData)
    if not (button and buttonData and not button._isText and not button._isBar) then
        return false
    end
    return buttonData.type == "spell"
        and buttonData.auraTracking == true
        and ButtonUsesActiveAuraIcon(buttonData)
        and button._auraSpellID ~= nil
end

local function ButtonNeedsAuraPandemicPeriodicRefresh(button, buttonData)
    if not (button and buttonData and not button._isText and not button._isBar) then
        return false
    end
    if buttonData.type ~= "spell"
        or buttonData.auraTracking ~= true
        or button._auraSpellID == nil
        or button._auraActive ~= true then
        return false
    end
    local style = button.style
    if not style then
        return false
    end
    return style.showPandemicGlow ~= false
        or buttonData.hideAuraActiveExceptPandemic == true
end

local function GetLiveOverrideSpellID(buttonData)
    if not (C_Spell and C_Spell.GetOverrideSpell and buttonData and buttonData.id) then
        return nil
    end
    local overrideID = C_Spell.GetOverrideSpell(buttonData.id)
    if overrideID and overrideID ~= 0 and overrideID ~= buttonData.id then
        return overrideID
    end
    return nil
end

local function GetSpellTexture(buttonData)
    if not (C_Spell and C_Spell.GetSpellTexture and buttonData and buttonData.id) then
        return nil
    end
    return C_Spell.GetSpellTexture(buttonData.id)
end

local function ButtonCanPollSpellVisuals(button, buttonData)
    return button
        and buttonData
        and buttonData.type == "spell"
        and buttonData.isPassive ~= true
        and buttonData.isPassiveCooldown ~= true
        and not buttonData.cdmChildSlot
end

local function ButtonNeedsSpellVisualPeriodicRefresh(button, buttonData)
    if not ButtonCanPollSpellVisuals(button, buttonData) then
        return false
    end

    local liveOverrideID = GetLiveOverrideSpellID(buttonData)
    local spellTexture = GetSpellTexture(buttonData)
    local previousOverrideID = button._periodicLiveOverrideSpellId
    if previousOverrideID == nil then
        previousOverrideID = button._liveOverrideSpellId
    end
    local previousTexture = button._periodicSpellTexture
    if previousTexture == nil then
        previousTexture = button._lastSpellTexture
    end

    if previousOverrideID ~= liveOverrideID
        or (spellTexture ~= nil and spellTexture ~= previousTexture)
        or (previousTexture ~= nil and spellTexture == nil) then
        button._spellVisualRefreshPending = true
        return true
    end

    return button._spellVisualRefreshPending == true
end

local function ButtonNeedsAssistedHighlightPeriodicRefresh(addon, button, buttonData)
    if not ButtonUsesAssistedHighlight(button, buttonData) then
        return false
    end
    return button._periodicAssistedSpellID ~= addon.assistedSpellID
        or button._periodicAssistedHighlightHasHostileTarget ~= addon._assistedHighlightHasHostileTarget
end

local function ButtonNeedsItemRangeOrUsabilityPeriodicRefresh(addon, button, buttonData)
    if not (buttonData and button) then
        return false
    end
    local isItemLike = addon.IsEntryItemLike and addon.IsEntryItemLike(buttonData)
    if not (isItemLike or buttonData.type == "equipitem") then
        return false
    end
    return ButtonUsesTargetRangeOrUsability(addon, button, buttonData)
end

local function ButtonNeedsItemFallbackPeriodicRefresh(addon, buttonData)
    if not (addon and addon.HasItemFallbacks and buttonData) then
        return false
    end
    return (buttonData.type == "item" or buttonData.type == "equipitem")
        and addon.HasItemFallbacks(buttonData) == true
end

local function CountTextIsActive(button)
    if not (button and button.count and button.count.GetText) then
        return false
    end
    local countText = button.count:GetText()
    if type(issecretvalue) == "function" and issecretvalue(countText) then
        return true
    end
    return countText ~= nil and countText ~= ""
end

local function ButtonNeedsTriggerConditionPeriodicRefresh(addon, button, buttonData)
    if not (addon and addon.TriggerRowUsesCondition and button and buttonData) then
        return false
    end
    if addon:TriggerRowUsesCondition(buttonData, "cooldownActive")
        and (button._desatCooldownActive == true or button._cooldownState == COOLDOWN_STATE_COOLDOWN) then
        return true
    end
    if addon:TriggerRowUsesCondition(buttonData, "chargesRecharging")
        and button._chargeRecharging == true then
        return true
    end
    if addon:TriggerRowUsesCondition(buttonData, "chargeState")
        and button._chargeState ~= nil
        and button._chargeState ~= CHARGE_STATE_FULL then
        return true
    end
    if addon:TriggerRowUsesCondition(buttonData, "countTextActive")
        and CountTextIsActive(button) then
        return true
    end
    if addon:TriggerRowUsesCondition(buttonData, "countState")
        and button._currentReadableCharges ~= nil then
        return true
    end
    return false
end

local PERIODIC_REFRESH_CONTRACTS = {
    {
        tag = "assistant-runtime",
        matches = function(addon, button, buttonData)
            return buttonData._rotationAssistantVirtual == true
                or ButtonNeedsAssistedHighlightPeriodicRefresh(addon, button, buttonData)
        end,
    },
    {
        tag = "text-runtime",
        matches = function(_, button)
            return button and button._isText == true
        end,
    },
    {
        tag = "cooldown-state",
        matches = function(_, button, buttonData)
            return button
                and (button._cooldownDeferred == true
                    or ButtonNeedsReadyGlowPeriodicRefresh(button, buttonData)
                    or ButtonNeedsIconCooldownTextPeriodicRefresh(button)
                    or ButtonNeedsIconCooldownStatePeriodicRefresh(button, buttonData)
                    or ButtonNeedsBarPeriodicRefresh(button))
        end,
    },
    {
        tag = "aura-runtime",
        matches = function(_, button, buttonData)
            return button
                and (button._auraGraceStart ~= nil
                    or button._targetSwitchAt ~= nil
                    or ButtonNeedsAuraIconVisualPeriodicRefresh(button, buttonData)
                    or ButtonNeedsAuraPandemicPeriodicRefresh(button, buttonData))
        end,
    },
    {
        tag = "spell-visual",
        matches = function(_, button, buttonData)
            return button
                and (button._iconDirty == true
                    or ButtonNeedsSpellVisualPeriodicRefresh(button, buttonData))
        end,
    },
    {
        tag = "item-runtime",
        matches = function(addon, button, buttonData)
            return ButtonNeedsItemRangeOrUsabilityPeriodicRefresh(addon, button, buttonData)
                or ButtonNeedsItemFallbackPeriodicRefresh(addon, buttonData)
        end,
    },
    {
        tag = "trigger-runtime",
        matches = ButtonNeedsTriggerConditionPeriodicRefresh,
    },
}

local function GetPeriodicRefreshContractTag(addon, button, buttonData)
    if not buttonData then
        return nil
    end
    for _, contract in ipairs(PERIODIC_REFRESH_CONTRACTS) do
        if contract.matches(addon, button, buttonData) then
            return contract.tag
        end
    end
    return nil
end

local function CaptureButtonRefreshPollingState(addon, button, buttonData)
    if not button then
        return
    end
    if ButtonUsesAssistedHighlight(button, buttonData) then
        button._periodicAssistedSpellID = addon.assistedSpellID
        button._periodicAssistedHighlightHasHostileTarget = addon._assistedHighlightHasHostileTarget
    end
    if ButtonCanPollSpellVisuals(button, buttonData) then
        button._periodicLiveOverrideSpellId = GetLiveOverrideSpellID(buttonData)
        button._periodicSpellTexture = GetSpellTexture(buttonData)
        button._spellVisualRefreshPending = nil
    end
end

local function ButtonNeedsPeriodicCooldownRefresh(addon, button, buttonData)
    return GetPeriodicRefreshContractTag(addon, button, buttonData) ~= nil
end

function CooldownCompanion:GetPeriodicCooldownRefreshContract(button, buttonData)
    return GetPeriodicRefreshContractTag(self, button, buttonData)
end

function CooldownCompanion:RefreshAssistedHighlightHostileTargetState()
    local hasHostileTarget = false
    if type(UnitExists) == "function" and type(UnitCanAttack) == "function" then
        if UnitExists("target") then
            hasHostileTarget = UnitCanAttack("player", "target") and true or false
        elseif UnitExists("softenemy") then
            hasHostileTarget = UnitCanAttack("player", "softenemy") and true or false
        end
    end
    self._assistedHighlightHasHostileTarget = hasHostileTarget
    return hasHostileTarget
end

function CooldownCompanion:HasPeriodicCooldownRefreshCandidates()
    if not self.groupFrames then
        return false
    end
    if self.RefreshAssistedHighlightHostileTargetState then
        self:RefreshAssistedHighlightHostileTargetState()
    end
    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons and frame:IsShown() then
            for _, button in ipairs(frame.buttons) do
                if ButtonNeedsPeriodicCooldownRefresh(self, button, button.buttonData) then
                    return true
                end
            end
        end
    end
    return false
end

function CooldownCompanion:ButtonMatchesCooldownRefreshReason(button, buttonData, reason)
    if not self:IsScopedCooldownRefreshReason(reason) then
        return true
    end
    if not buttonData then
        return false
    end
    if reason.kind == "periodic" then
        return ButtonNeedsPeriodicCooldownRefresh(self, button, buttonData)
    end
    if reason.kind == "spell-usability" then
        return ButtonUsesSpellUsability(self, button, buttonData)
    end
    if buttonData._rotationAssistantVirtual == true then
        return true
    end

    if reason.kind == "unit-aura" then
        return ButtonHasAuraDependency(button, buttonData, reason.unit)
    end

    if reason.kind == "target-changed" or reason.kind == "unit-target" then
        return ButtonHasAuraDependency(button, buttonData, "target")
            or ButtonUsesTargetRangeOrUsability(self, button, buttonData)
    end

    return true
end

local function IsTriggerRefreshFrame(addon, frame)
    if not (addon and frame) then
        return false
    end
    if frame.displayMode == "trigger" then
        return true
    end

    local groupId = frame.groupId
    local profile = addon.db and addon.db.profile
    local group = profile and profile.groups and groupId and profile.groups[groupId]
    return group and group.displayMode == "trigger"
end

local function TriggerFrameMatchesCooldownRefreshReason(addon, frame, refreshReason)
    for _, button in ipairs(frame.buttons) do
        if addon:ButtonMatchesCooldownRefreshReason(button, button.buttonData, refreshReason) then
            return true
        end
    end
    return false
end

function CooldownCompanion:UpdateGroupFrameCooldownButtons(frame, refreshReason, collectStats)
    local scoped = self:IsScopedCooldownRefreshReason(refreshReason)
    local canFilter = scoped and self.ButtonMatchesCooldownRefreshReason
    local forceWholeFrame = canFilter
        and IsTriggerRefreshFrame(self, frame)
        and TriggerFrameMatchesCooldownRefreshReason(self, frame, refreshReason)
    if not canFilter and not collectStats then
        for _, button in ipairs(frame.buttons) do
            button:UpdateCooldown()
            CaptureButtonRefreshPollingState(self, button, button.buttonData)
        end
        return nil, nil
    end

    local updatedCount = 0
    local skippedCount = 0
    for _, button in ipairs(frame.buttons) do
        if forceWholeFrame
            or not canFilter
            or self:ButtonMatchesCooldownRefreshReason(button, button.buttonData, refreshReason) then
            button:UpdateCooldown()
            CaptureButtonRefreshPollingState(self, button, button.buttonData)
            updatedCount = updatedCount + 1
        else
            skippedCount = skippedCount + 1
        end
    end
    return updatedCount, skippedCount
end
