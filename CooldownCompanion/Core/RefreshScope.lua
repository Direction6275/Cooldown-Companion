--[[
    CooldownCompanion - Core/RefreshScope.lua: structured refresh reasons and
    conservative target/aura scoped refresh predicates.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic or {}
local CHARGE_STATE_FULL = CooldownLogic.CHARGE_STATE_FULL or "full"

local SCOPED_REASON_KINDS = {
    ["periodic"] = true,
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

local function ButtonNeedsPeriodicCooldownRefresh(button, buttonData)
    if not buttonData then
        return false
    end
    if buttonData._rotationAssistantVirtual == true then
        return true
    end
    if not button then
        return false
    end
    if button._isText == true then
        return true
    end
    if button._cooldownDeferred == true then
        return true
    end
    if button._auraGraceStart ~= nil or button._targetSwitchAt ~= nil then
        return true
    end
    if ButtonNeedsReadyGlowPeriodicRefresh(button, buttonData) then
        return true
    end
    return false
end

function CooldownCompanion:HasPeriodicCooldownRefreshCandidates()
    if not self.groupFrames then
        return false
    end
    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons and frame:IsShown() then
            for _, button in ipairs(frame.buttons) do
                if ButtonNeedsPeriodicCooldownRefresh(button, button.buttonData) then
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
        return ButtonNeedsPeriodicCooldownRefresh(button, buttonData)
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

function CooldownCompanion:UpdateGroupFrameCooldownButtons(frame, refreshReason, collectStats)
    local scoped = self:IsScopedCooldownRefreshReason(refreshReason)
    local canFilter = scoped and self.ButtonMatchesCooldownRefreshReason
    if not canFilter and not collectStats then
        for _, button in ipairs(frame.buttons) do
            button:UpdateCooldown()
        end
        return nil, nil
    end

    local updatedCount = 0
    local skippedCount = 0
    for _, button in ipairs(frame.buttons) do
        if not canFilter
            or self:ButtonMatchesCooldownRefreshReason(button, button.buttonData, refreshReason) then
            button:UpdateCooldown()
            updatedCount = updatedCount + 1
        else
            skippedCount = skippedCount + 1
        end
    end
    return updatedCount, skippedCount
end
