--[[
    CooldownCompanion - ButtonFrame/UpdatePlan
    Diagnostic feature classification for per-button refresh cost.
]]

local _, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic or {}

local ipairs = ipairs
local next = next
local table_concat = table.concat
local tonumber = tonumber
local type = type

local COOLDOWN_STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN or "cooldown"
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING or "missing"
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO or "zero"

local VISIBILITY_KEYS = {
    "hideWhileOnCooldown",
    "hideWhileNotOnCooldown",
    "hideWhileAuraNotActive",
    "hideWhileAuraActive",
    "hideWhileNoProc",
    "hideWhileZeroCharges",
    "hideWhileZeroStacks",
    "hideWhileNotEquipped",
    "hideWhileUnusable",
}

local DESATURATION_KEYS = {
    "desaturateWhileAuraNotActive",
    "desaturateWhileZeroCharges",
    "desaturateWhileZeroStacks",
}

local CLEAN_TICK_PRIORITY = {
    candidate = 1,
    polling = 2,
    stateful = 3,
    required = 4,
    unknown = 5,
}
local CLEAN_TICK_IDLE_VISUAL_POLL_INTERVAL = 0.5

local function AddFeature(plan, seen, feature)
    if not feature or seen[feature] then return end
    seen[feature] = true
    plan.features[#plan.features + 1] = feature
end

local function AddLane(plan, lane)
    if not lane or plan.laneMap[lane] then return end
    plan.laneMap[lane] = true
    plan.lanes[#plan.lanes + 1] = lane
end

local function AddCleanTickReason(plan, category, reason)
    if not category or not reason then return end
    if not plan.cleanTickReasonMap[reason] then
        plan.cleanTickReasonMap[reason] = true
        plan.cleanTickReasons[#plan.cleanTickReasons + 1] = reason
    end

    local current = plan.cleanTickCategory or "candidate"
    if (CLEAN_TICK_PRIORITY[category] or 0) > (CLEAN_TICK_PRIORITY[current] or 0) then
        plan.cleanTickCategory = category
    end
end

local function HasAnyTruthyKey(source, keys)
    if type(source) ~= "table" then return false end
    for _, key in ipairs(keys) do
        if source[key] == true then
            return true
        end
    end
    return false
end

local function HasSoundAlertEvents(buttonData)
    local cfg = type(buttonData) == "table" and buttonData.soundAlerts or nil
    local events = type(cfg) == "table" and cfg.events or nil
    if type(events) ~= "table" then
        return false
    end
    for _, enabled in pairs(events) do
        if enabled ~= nil and enabled ~= false then
            return true
        end
    end
    return false
end

local function HasTriggerConditionConfig(buttonData)
    if type(buttonData) ~= "table" then return false end
    if buttonData.triggerCondition ~= nil
        or buttonData.triggerExpected ~= nil
        or buttonData.triggerState ~= nil then
        return true
    end
    return type(buttonData.triggerConditions) == "table"
        and next(buttonData.triggerConditions) ~= nil
end

local function BuildPlanInputSignature(buttonData)
    if type(buttonData) ~= "table" then
        return "missing"
    end

    return table_concat({
        buttonData.hasCharges == true and "hc1" or "hc0",
        buttonData._hasDisplayCount == true and "dc1" or "dc0",
        buttonData._displayCountFamily == true and "df1" or "df0",
        buttonData._castCountCandidate == true and "cc1" or "cc0",
        HasSoundAlertEvents(buttonData) and "snd1" or "snd0",
        HasTriggerConditionConfig(buttonData) and "trg1" or "trg0",
        HasAnyTruthyKey(buttonData, VISIBILITY_KEYS) and "vis1" or "vis0",
        HasAnyTruthyKey(buttonData, DESATURATION_KEYS) and "des1" or "des0",
        buttonData.hideAuraActiveExceptPandemic == true and "pvis1" or "pvis0",
        buttonData.invertAuraDesaturationLogic == true and "ides1" or "ides0",
        buttonData.neverDesaturate == true and "ndes1" or "ndes0",
    }, "|")
end

local function HasActiveStyle(style, key)
    if type(style) ~= "table" then return false end
    local value = style[key]
    return value ~= nil and value ~= false and value ~= "none"
end

local function ResolveDisplayMode(button, group)
    if type(group) == "table" and group.displayMode then
        return group.displayMode
    end
    if type(button) ~= "table" then
        return "unknown"
    end
    if button._isBar == true then
        return "bars"
    end
    if button._isText == true then
        return "text"
    end
    local poolKey = button._buttonPoolKey
    if poolKey == "textures" or poolKey == "trigger" then
        return poolKey
    end
    return "icons"
end

local function IsItemLike(buttonData)
    return CooldownCompanion.IsEntryItemLike
        and CooldownCompanion.IsEntryItemLike(buttonData)
        or false
end

local function IsEquipmentSlot(buttonData)
    return CooldownCompanion.IsEquipmentSlotEntry
        and CooldownCompanion.IsEquipmentSlotEntry(buttonData)
        or false
end

local function UsesChargeBehavior(buttonData)
    return CooldownCompanion.UsesChargeBehavior
        and CooldownCompanion.UsesChargeBehavior(buttonData)
        or false
end

local function UsesCountText(buttonData)
    if type(buttonData) ~= "table" then return false end
    if UsesChargeBehavior(buttonData) then return true end
    if buttonData._castCountCandidate == true then return true end
    if CooldownCompanion.HasCastCountText and CooldownCompanion.HasCastCountText(buttonData) then return true end
    if CooldownCompanion.HasConditionalCastCountText and CooldownCompanion.HasConditionalCastCountText(buttonData) then return true end
    return false
end

local function IsAuraTracked(buttonData)
    return type(buttonData) == "table"
        and (buttonData.auraTracking == true
            or buttonData.isPassive == true
            or buttonData.addedAs == "aura"
            or buttonData.auraSpellID ~= nil)
        or false
end

local function IsBarAuraStackDisplay(buttonData)
    return CooldownCompanion.IsBarPanelAuraStackDisplay
        and CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData)
        or false
end

function CooldownCompanion:BuildButtonUpdatePlan(button, group)
    local buttonData = type(button) == "table" and button.buttonData or nil
    local style = type(button) == "table" and button.style or nil
    local displayMode = ResolveDisplayMode(button, group)
    local plan = {
        version = 1,
        kind = "simple",
        signature = "simple",
        displayMode = displayMode,
        buttonType = buttonData and buttonData.type or nil,
        buttonId = buttonData and buttonData.id or nil,
        features = {},
        lanes = {},
        laneMap = {},
        cleanTickCategory = "candidate",
        cleanTickReasons = {},
        cleanTickReasonMap = {},
    }
    local seen = {}

    if type(buttonData) ~= "table" then
        AddFeature(plan, seen, "missing-data")
        AddCleanTickReason(plan, "unknown", "missing-data")
    else
        local auraTracked = IsAuraTracked(buttonData)
        local itemLike = IsItemLike(buttonData)
        local equipmentSlot = IsEquipmentSlot(buttonData)
        local spellLike = buttonData.type == "spell"
        local auraOnly = buttonData.addedAs == "aura" or buttonData.isPassive == true
        local hasCooldownLane = itemLike
            or (spellLike and (buttonData.isPassiveCooldown == true or not auraOnly))

        if hasCooldownLane then
            AddLane(plan, "cooldown")
        end
        if spellLike and buttonData.cdmChildSlot == nil then
            AddCleanTickReason(plan, "polling", "spell-texture-poll")
            if not buttonData.isPassive then
                AddCleanTickReason(plan, "polling", "override-spell-poll")
            end
        end
        if itemLike then
            AddCleanTickReason(plan, "polling", "item-state-poll")
        end

        if displayMode == "bars" then
            AddFeature(plan, seen, "bar-mode")
            AddLane(plan, "bar")
            AddCleanTickReason(plan, "required", "bar-display")
        elseif displayMode == "text" then
            AddFeature(plan, seen, "text-mode")
            AddLane(plan, "text")
            AddCleanTickReason(plan, "required", "text-display")
        elseif displayMode == "textures" then
            AddFeature(plan, seen, "texture-mode")
            AddLane(plan, "texture")
            AddCleanTickReason(plan, "stateful", "texture-display")
        elseif displayMode == "trigger" then
            AddFeature(plan, seen, "trigger-mode")
            AddLane(plan, "trigger")
            AddCleanTickReason(plan, "required", "trigger-display")
        end

        if buttonData._rotationAssistantVirtual == true then
            AddFeature(plan, seen, "rotation-assistant")
            AddLane(plan, "rotation-assistant")
            AddCleanTickReason(plan, "required", "rotation-assistant")
        end

        if auraTracked then
            AddFeature(plan, seen, "aura")
            AddLane(plan, "aura")
            AddCleanTickReason(plan, "stateful", "aura-runtime")
            if buttonData.auraUnit == "target"
                or (type(button) == "table" and button._auraUnit == "target") then
                AddLane(plan, "target-aura")
            end
            if buttonData.addedAs == "aura" then
                AddFeature(plan, seen, "aura-entry")
            end
            if buttonData.isPassive == true then
                AddFeature(plan, seen, "passive-aura")
            end
            if buttonData.cdmChildSlot ~= nil then
                AddFeature(plan, seen, "cdm-child")
            end
            if style == nil or style.showPandemicGlow ~= false or buttonData.hideAuraActiveExceptPandemic == true then
                AddFeature(plan, seen, "pandemic")
            end
            if style == nil or style.showAuraStackText ~= false then
                AddFeature(plan, seen, "aura-stack-text")
            end
            if HasActiveStyle(style, "auraGlowStyle")
                or HasActiveStyle(style, "barAuraEffect")
                or style == nil then
                AddFeature(plan, seen, "aura-visuals")
            end
        end

        if buttonData.isPassiveCooldown == true then
            AddFeature(plan, seen, "passive-cooldown")
            AddLane(plan, "cooldown")
        end

        if IsBarAuraStackDisplay(buttonData) then
            AddFeature(plan, seen, "bar-aura-stacks")
            AddLane(plan, "aura")
            AddLane(plan, "bar")
        end

        if buttonData.hideAuraActiveExceptPandemic == true then
            AddFeature(plan, seen, "pandemic-visibility")
            AddLane(plan, "aura")
            AddLane(plan, "visibility")
            AddCleanTickReason(plan, "stateful", "pandemic-visibility")
        end

        if HasAnyTruthyKey(buttonData, VISIBILITY_KEYS) then
            AddFeature(plan, seen, "visibility-rules")
            AddLane(plan, "visibility")
            AddCleanTickReason(plan, "stateful", "visibility-rules")
        end
        if HasAnyTruthyKey(buttonData, DESATURATION_KEYS)
            or buttonData.invertAuraDesaturationLogic == true
            or buttonData.neverDesaturate == true then
            AddFeature(plan, seen, "desaturation-rules")
            AddLane(plan, "visibility")
            AddCleanTickReason(plan, "stateful", "desaturation-rules")
        end

        if buttonData.hideWhileUnusable == true
            or (style and style.showUnusable == true and not buttonData.isPassive and not buttonData.isPassiveCooldown) then
            AddFeature(plan, seen, "usability")
            AddLane(plan, "usability")
            AddCleanTickReason(plan, "stateful", "usability-state")
        end

        if style and style.showOutOfRange == true and (spellLike or itemLike) then
            AddFeature(plan, seen, "range")
            AddLane(plan, "range")
            AddCleanTickReason(plan, "stateful", "range-state")
        end

        if UsesChargeBehavior(buttonData) then
            AddFeature(plan, seen, "charges")
            AddLane(plan, "charges")
            AddCleanTickReason(plan, "stateful", "charge-state")
        end
        if buttonData._hasDisplayCount == true or buttonData._displayCountFamily == true then
            AddFeature(plan, seen, "display-count")
            AddLane(plan, "count")
            AddCleanTickReason(plan, "stateful", "display-count")
        end
        if UsesCountText(buttonData) then
            AddFeature(plan, seen, "count-text")
            AddLane(plan, "count")
            AddCleanTickReason(plan, "stateful", "count-text")
        end

        if itemLike then
            AddFeature(plan, seen, "item-state")
            AddLane(plan, "inventory")
        end
        if equipmentSlot then
            AddFeature(plan, seen, "equipment-slot")
            AddLane(plan, "equipment")
        end
        if type(button) == "table"
            and (button._resourceGateCost == true or button._baseResourceGateCost == true) then
            AddFeature(plan, seen, "resource-gate")
            AddLane(plan, "usability")
            AddCleanTickReason(plan, "stateful", "resource-gate")
        end

        if spellLike and not auraTracked and not buttonData.isPassiveCooldown
            and HasActiveStyle(style, "procGlowStyle") then
            AddFeature(plan, seen, "proc-glow")
            AddLane(plan, "proc")
        end
        if type(style) == "table" and style.showLossOfControl == true
            and spellLike and not buttonData.isPassive then
            AddFeature(plan, seen, "loss-of-control")
            AddLane(plan, "loss-of-control")
            AddCleanTickReason(plan, "stateful", "loss-of-control")
        end
        if HasActiveStyle(style, "readyGlowStyle")
            or (type(style) == "table" and tonumber(style.readyGlowDuration) and tonumber(style.readyGlowDuration) > 0) then
            AddFeature(plan, seen, "ready-glow")
            AddLane(plan, "cooldown")
            AddCleanTickReason(plan, "stateful", "ready-glow")
        end
        if type(style) == "table" and style.iconFillEnabled == true then
            AddFeature(plan, seen, "icon-fill")
            AddLane(plan, "periodic")
            AddCleanTickReason(plan, "required", "icon-fill")
        end
        if type(style) == "table"
            and (style.iconAuraTintEnabled == true or style.iconCooldownTintEnabled == true) then
            AddFeature(plan, seen, "icon-state-tint")
            AddLane(plan, "visibility")
            AddCleanTickReason(plan, "stateful", "icon-state-tint")
        end
        if type(style) == "table" and style.showKeybindText == true then
            AddFeature(plan, seen, "keybind-text")
            AddLane(plan, "actionbar")
        end
        if type(style) == "table" and style.separateTextPositions == true and auraTracked then
            AddFeature(plan, seen, "secondary-cooldown")
            AddLane(plan, "cooldown")
            AddLane(plan, "aura")
            AddCleanTickReason(plan, "stateful", "secondary-cooldown")
        end
        if type(style) == "table" and style.showAssistedHighlight == true then
            AddFeature(plan, seen, "assisted-highlight")
            AddLane(plan, "target")
            AddCleanTickReason(plan, "stateful", "assisted-highlight")
        end

        if HasSoundAlertEvents(buttonData) then
            AddFeature(plan, seen, "sound-alerts")
            AddLane(plan, "sound")
            AddCleanTickReason(plan, "stateful", "sound-alerts")
        end
        if HasTriggerConditionConfig(buttonData) then
            AddFeature(plan, seen, "trigger-condition")
            AddLane(plan, "trigger")
            AddCleanTickReason(plan, "stateful", "trigger-condition")
        end
    end

    plan.featureCount = #plan.features
    plan.laneSignature = #plan.lanes > 0 and table_concat(plan.lanes, "+") or "none"
    plan.cleanTickReasonSignature = #plan.cleanTickReasons > 0 and table_concat(plan.cleanTickReasons, "+") or "event-candidate"
    if plan.featureCount > 0 then
        plan.kind = "rich"
        plan.signature = table_concat(plan.features, "+")
    end

    return plan
end

function CooldownCompanion:RefreshButtonUpdatePlan(button, group)
    if type(button) ~= "table" then return nil end

    local plan = self:BuildButtonUpdatePlan(button, group)
    button._cdcUpdatePlan = plan
    button._cdcUpdatePlanData = button.buttonData
    button._cdcUpdatePlanStyle = button.style
    button._cdcUpdatePlanInputSignature = BuildPlanInputSignature(button.buttonData)
    button._cdcUpdatePlanDisplayMode = plan and plan.displayMode or nil
    return plan
end

function CooldownCompanion:GetButtonUpdatePlan(button, group)
    if type(button) ~= "table" then return nil end

    local displayMode = ResolveDisplayMode(button, group)
    local plan = button._cdcUpdatePlan
    if plan
        and button._cdcUpdatePlanData == button.buttonData
        and button._cdcUpdatePlanStyle == button.style
        and button._cdcUpdatePlanInputSignature == BuildPlanInputSignature(button.buttonData)
        and button._cdcUpdatePlanDisplayMode == displayMode then
        return plan
    end
    return self:RefreshButtonUpdatePlan(button, group)
end

function CooldownCompanion:ClearButtonUpdatePlan(button)
    if type(button) ~= "table" then return end

    button._cdcUpdatePlan = nil
    button._cdcUpdatePlanData = nil
    button._cdcUpdatePlanStyle = nil
    button._cdcUpdatePlanInputSignature = nil
    button._cdcUpdatePlanDisplayMode = nil
end

local function IsSpellVisualPollOnly(plan)
    if type(plan) ~= "table" or type(plan.cleanTickReasonMap) ~= "table" then
        return false
    end
    if type(plan.laneMap) == "table" then
        for lane in pairs(plan.laneMap) do
            if lane ~= "cooldown" and lane ~= "actionbar" then
                return false
            end
        end
    end

    local hasVisualPoll = false
    for reason in pairs(plan.cleanTickReasonMap) do
        if reason == "spell-texture-poll" or reason == "override-spell-poll" then
            hasVisualPoll = true
        else
            return false
        end
    end

    return hasVisualPoll
end

function CooldownCompanion:IsCleanTickerVisualOnlyButton(button, group)
    return IsSpellVisualPollOnly(self:GetButtonUpdatePlan(button, group))
end

function CooldownCompanion:ButtonHasActiveCleanTickerMaintenance(button)
    if type(button) ~= "table" then
        return true
    end

    return button._displaySpellId == nil
        or button._lastSpellTexture == nil
        or button._iconDirty == true
        or button._cooldownState == COOLDOWN_STATE_COOLDOWN
        or button._chargeState == CHARGE_STATE_MISSING
        or button._chargeState == CHARGE_STATE_ZERO
        or button._chargeRecharging == true
        or button._durationObj ~= nil
        or button._auraDurationObj ~= nil
        or button._auraActive == true
        or button._auraGraceStart ~= nil
        or button._targetSwitchAt ~= nil
        or button._cooldownDeferred == true
        or button._desatCooldownActive == true
        or button._readyGlowActive == true
        or button._readyGlowMaxChargesActive == true
        or button._iconFillActive == true
        or button._resourceGateCost == true
        or button._baseResourceGateCost == true
        or button._conditionalPreviewRemaining ~= nil
end

function CooldownCompanion:ShouldSkipCleanTickerButtonUpdate(button, group, now)
    if not self:IsCleanTickerVisualOnlyButton(button, group) then
        return false
    end
    if self:ButtonHasActiveCleanTickerMaintenance(button) then
        return false
    end

    local pollNow = now or (GetTime and GetTime()) or 0
    local lastPoll = button._cleanTickerVisualPollAt
    if lastPoll and pollNow - lastPoll < CLEAN_TICK_IDLE_VISUAL_POLL_INTERVAL then
        return true
    end

    button._cleanTickerVisualPollAt = pollNow
    return false
end
