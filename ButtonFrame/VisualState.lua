local ADDON_NAME, ST = ...

local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic or {}
local STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO
local CHARGE_STATE_FULL = CooldownLogic.CHARGE_STATE_FULL
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING
local ResolveIconDesaturationIntent = ST._ResolveIconDesaturationIntent
local GetButtonVisibilityReasonNames = ST._GetButtonVisibilityReasonNames
local DEFAULT_ICON_FILL_COOLDOWN_COLOR = {0.6, 0.13, 0.18, 0.55}
local DEFAULT_ICON_FILL_AURA_COLOR = {0.2, 1.0, 0.2, 0.55}
local UsesChargeBehavior = CooldownCompanion and CooldownCompanion.UsesChargeBehavior
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local UnitExists = UnitExists

local function IsTrue(value)
    return value == true
end

local function EnsureSection(parent, key)
    local section = parent[key]
    if type(section) ~= "table" then
        section = {}
        parent[key] = section
    end
    return section
end

local function ResolveVisibilityMode(hidden, alphaOverride)
    if IsTrue(hidden) then
        return "hidden"
    end
    if alphaOverride ~= nil and alphaOverride ~= 1 then
        return "dimmed"
    end
    return "visible"
end

local function CopyVisibilityReasonNames(visibility, reasonBits)
    if type(GetButtonVisibilityReasonNames) ~= "function" then
        visibility.reasonNames = nil
        return
    end

    local names = visibility.reasonNames
    if type(names) ~= "table" then
        names = {}
        visibility.reasonNames = names
    end

    GetButtonVisibilityReasonNames(reasonBits, names)
    if #names == 0 then
        visibility.reasonNames = nil
    end
end

local function UsesIconFillChargeBehavior(buttonData)
    if type(UsesChargeBehavior) == "function" then
        return UsesChargeBehavior(buttonData)
    end
    return buttonData and buttonData.hasCharges == true
end

local function GetButtonGroup(button)
    local groupId = button and button._groupId
    return groupId
        and CooldownCompanion and CooldownCompanion.db and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups
        and CooldownCompanion.db.profile.groups[groupId]
end

local function SetIconFillIntent(target, available, active, reason, mode, color, auraActive, static)
    target.available = available == true
    target.active = active == true
    target.reason = reason
    target.mode = mode
    target.auraActive = auraActive == true
    target.static = static == true
    target.usesOnUpdate = target.active and target.static ~= true or false
    target.suppressCooldownSwipe = target.active
    target.suppressAuraBlizzardSwipe = target.auraActive
    target.r = color and color[1] or nil
    target.g = color and color[2] or nil
    target.b = color and color[3] or nil
    target.a = color and color[4] or nil
    return target
end

local function SetGlowIntent(section, available, active, reason)
    section.available = available == true
    section.active = active == true
    section.reason = reason
    section.preview = false
    section.combatOnly = false
    section.combatSuppressed = false
    section.procOverlayActive = false
    section.suppressedByProc = false
    section.auraIndicatorEnabled = false
    section.invert = false
    section.pandemic = false
    section.targetRequired = false
    section.targetExists = nil
    section.maxCharges = false
    section.durationWindow = false
    section.duration = nil
    section.startTime = nil
    section.cooldownSuppressed = false
    section.auraSuppressed = false
    return section
end

local function EnsureGlowSection(target, key)
    local section = target[key]
    if type(section) ~= "table" then
        section = {}
        target[key] = section
    end
    return section
end

local function IsReadyGlowMaxChargeEligible(buttonData)
    return buttonData
        and buttonData.type == "spell"
        and buttonData.hasCharges == true
        and not buttonData._hasDisplayCount
end

local function IsReadyGlowAtMaxCharges(button, buttonData)
    if not (button and IsReadyGlowMaxChargeEligible(buttonData)) then
        return false
    end

    return button._chargeState == CHARGE_STATE_FULL
end

local function GetTargetExists(options)
    if options and options.targetExists ~= nil then
        return options.targetExists == true
    end
    if type(UnitExists) == "function" then
        return UnitExists("target") == true
    end
    return false
end

local function GetResolverCombatState(options)
    if options and options.inCombat ~= nil then
        return options.inCombat == true
    end
    if type(InCombatLockdown) == "function" then
        return InCombatLockdown() == true
    end
    return false
end

local function GetResolverTime(options)
    if options and type(options.now) == "number" then
        return options.now
    end
    if type(GetTime) == "function" then
        return GetTime()
    end
    return 0
end

local function ResolveAuraIndicatorEnabled(buttonData, style)
    local auraIndicatorEnabled = buttonData and buttonData.auraIndicatorEnabled and true or false
    if buttonData
       and buttonData.overrideSections
       and buttonData.overrideSections.auraIndicator
       and style.auraGlowStyle == "none" then
        auraIndicatorEnabled = false
    end
    return auraIndicatorEnabled
end

local function ResolveIconGlowIntent(button, buttonData, style, procOverlayActive, target, options)
    target = target or {}
    style = style or {}

    local proc = EnsureGlowSection(target, "proc")
    local aura = EnsureGlowSection(target, "aura")
    local ready = EnsureGlowSection(target, "ready")
    local inCombat = GetResolverCombatState(options)
    local now
    local isSpell = buttonData and buttonData.type == "spell"
    local isPassive = buttonData and buttonData.isPassive == true
    local procOverlayShown = procOverlayActive == true

    if type(button) ~= "table" or type(buttonData) ~= "table" then
        SetGlowIntent(proc, false, false, "invalid")
        SetGlowIntent(aura, false, false, "invalid")
        SetGlowIntent(ready, false, false, "invalid")
        return target
    end

    if not button.procGlow then
        SetGlowIntent(proc, false, false, "missing-widget")
        proc.procOverlayActive = procOverlayShown
    elseif button._procGlowPreview == true then
        SetGlowIntent(proc, true, true, "preview")
        proc.preview = true
        proc.procOverlayActive = procOverlayShown
    elseif style.procGlowStyle == "none" then
        SetGlowIntent(proc, true, false, "disabled")
        proc.procOverlayActive = procOverlayShown
    elseif not isSpell then
        SetGlowIntent(proc, true, false, "not-spell")
        proc.procOverlayActive = procOverlayShown
    elseif isPassive then
        SetGlowIntent(proc, true, false, "passive")
        proc.procOverlayActive = procOverlayShown
    elseif button._auraTrackingReady == true then
        SetGlowIntent(proc, true, false, "aura-tracking")
        proc.procOverlayActive = procOverlayShown
    elseif style.procGlowCombatOnly and not inCombat then
        SetGlowIntent(proc, true, false, "combat-only")
        proc.combatOnly = true
        proc.combatSuppressed = true
        proc.procOverlayActive = procOverlayShown
    elseif procOverlayShown then
        SetGlowIntent(proc, true, true, "proc")
        proc.procOverlayActive = true
    else
        SetGlowIntent(proc, true, false, "inactive")
    end

    local auraIndicatorEnabled = ResolveAuraIndicatorEnabled(buttonData, style)
    local auraCombatOnly = style.auraGlowCombatOnly
    local pandemicCombatOnly = style.pandemicGlowCombatOnly
    local targetExists

    if not button.auraGlow then
        SetGlowIntent(aura, false, false, "missing-widget")
        aura.auraIndicatorEnabled = auraIndicatorEnabled
    elseif button._pandemicPreview == true then
        SetGlowIntent(aura, true, true, "pandemic-preview")
        aura.preview = true
        aura.pandemic = true
        aura.auraIndicatorEnabled = auraIndicatorEnabled
    elseif button._auraGlowPreview == true then
        SetGlowIntent(aura, true, true, "preview")
        aura.preview = true
        aura.auraIndicatorEnabled = auraIndicatorEnabled
    elseif style.auraGlowInvert then
        if button._auraTrackingReady == true and button._auraSpellID and not button._auraActive then
            if auraIndicatorEnabled or style.auraGlowStyle ~= "none" then
                if auraCombatOnly and not inCombat then
                    SetGlowIntent(aura, true, false, "combat-only")
                    aura.combatOnly = true
                    aura.combatSuppressed = true
                    aura.invert = true
                    aura.auraIndicatorEnabled = auraIndicatorEnabled
                else
                    targetExists = button._auraUnit ~= "target" or GetTargetExists(options)
                    SetGlowIntent(
                        aura,
                        true,
                        targetExists,
                        targetExists and "aura-missing" or "target-missing"
                    )
                    aura.invert = true
                    aura.targetRequired = button._auraUnit == "target"
                    aura.targetExists = targetExists
                    aura.auraIndicatorEnabled = auraIndicatorEnabled
                end
            else
                SetGlowIntent(aura, true, false, "disabled")
                aura.invert = true
                aura.auraIndicatorEnabled = auraIndicatorEnabled
            end
        elseif button._auraActive and button._inPandemic and style.showPandemicGlow ~= false then
            SetGlowIntent(
                aura,
                true,
                not (pandemicCombatOnly and not inCombat),
                pandemicCombatOnly and not inCombat and "pandemic-combat-only" or "pandemic"
            )
            aura.pandemic = true
            aura.combatOnly = pandemicCombatOnly and true or false
            aura.combatSuppressed = pandemicCombatOnly and not inCombat
            aura.invert = true
            aura.auraIndicatorEnabled = auraIndicatorEnabled
        else
            SetGlowIntent(aura, true, false, "inactive")
            aura.invert = true
            aura.auraIndicatorEnabled = auraIndicatorEnabled
        end
    elseif button._auraActive then
        if button._inPandemic and style.showPandemicGlow ~= false
            and not (pandemicCombatOnly and not inCombat) then
            SetGlowIntent(
                aura,
                true,
                true,
                "pandemic"
            )
            aura.pandemic = true
            aura.combatOnly = pandemicCombatOnly and true or false
            aura.combatSuppressed = false
            aura.auraIndicatorEnabled = auraIndicatorEnabled
        elseif auraIndicatorEnabled or style.auraGlowStyle ~= "none" then
            SetGlowIntent(
                aura,
                true,
                not (auraCombatOnly and not inCombat),
                auraCombatOnly and not inCombat and "combat-only" or "aura"
            )
            aura.combatOnly = auraCombatOnly and true or false
            aura.combatSuppressed = auraCombatOnly and not inCombat
            aura.auraIndicatorEnabled = auraIndicatorEnabled
        else
            SetGlowIntent(aura, true, false, "disabled")
            aura.auraIndicatorEnabled = auraIndicatorEnabled
        end
    else
        SetGlowIntent(aura, true, false, "aura-missing")
        aura.auraIndicatorEnabled = auraIndicatorEnabled
    end

    local procSuppressesReady = procOverlayShown and style.procGlowStyle ~= "none"
    local auraSuppressesReady = button._auraTrackingReady == true and button._auraActive == true
    if not button.readyGlow then
        SetGlowIntent(ready, false, false, "missing-widget")
    elseif button._readyGlowPreview == true then
        SetGlowIntent(ready, true, true, "preview")
        ready.preview = true
    elseif not style.readyGlowStyle or style.readyGlowStyle == "none" then
        SetGlowIntent(ready, true, false, "disabled")
    elseif isPassive then
        SetGlowIntent(ready, true, false, "passive")
    elseif button._noCooldown then
        SetGlowIntent(ready, true, false, "no-cooldown")
    elseif style.readyGlowCombatOnly and not inCombat then
        SetGlowIntent(ready, true, false, "combat-only")
        ready.combatOnly = true
        ready.combatSuppressed = true
    elseif button._desatCooldownActive ~= false or button._cooldownState == STATE_COOLDOWN then
        SetGlowIntent(ready, true, false, "cooldown")
        ready.cooldownSuppressed = true
    elseif auraSuppressesReady then
        SetGlowIntent(ready, true, false, "aura-active")
        ready.auraSuppressed = true
    elseif procSuppressesReady then
        SetGlowIntent(ready, true, false, "proc")
        ready.suppressedByProc = true
        ready.procOverlayActive = true
    elseif style.readyGlowOnlyAtMaxCharges and IsReadyGlowMaxChargeEligible(buttonData) then
        local dur = style.readyGlowDuration or 0
        if IsReadyGlowAtMaxCharges(button, buttonData) then
            if dur > 0 then
                now = now or GetResolverTime(options)
                local startTime = button._readyGlowMaxChargesStartTime
                local inWindow = startTime ~= nil and (now - startTime) <= dur
                SetGlowIntent(ready, true, inWindow, inWindow and "max-charges" or "duration-window")
                ready.maxCharges = true
                ready.durationWindow = true
                ready.duration = dur
                ready.startTime = startTime
            else
                SetGlowIntent(ready, true, true, "max-charges")
                ready.maxCharges = true
            end
        else
            SetGlowIntent(ready, true, false, "not-max-charges")
            ready.maxCharges = true
        end
    else
        local dur = style.readyGlowDuration or 0
        if dur > 0 then
            now = now or GetResolverTime(options)
            local startTime = button._readyGlowStartTime
            local inWindow = startTime ~= nil and (now - startTime) <= dur
            SetGlowIntent(ready, true, inWindow, inWindow and "ready" or "duration-window")
            ready.durationWindow = true
            ready.duration = dur
            ready.startTime = startTime
        else
            SetGlowIntent(ready, true, true, "ready")
        end
    end

    return target
end

local function ResolveIconFillIntent(button, buttonData, style, target)
    target = target or {}

    if type(button) ~= "table" or type(buttonData) ~= "table" then
        return SetIconFillIntent(target, false, false, "invalid")
    end

    style = style or {}

    if not button.iconFill then
        return SetIconFillIntent(target, false, false, "missing-widget")
    end

    if style.iconFillEnabled ~= true then
        return SetIconFillIntent(target, false, false, "disabled")
    end

    local group = GetButtonGroup(button)
    if group then
        if (group.displayMode or "icons") ~= "icons" then
            return SetIconFillIntent(target, false, false, "non-icon-mode")
        end
        if group.masqueEnabled == true then
            return SetIconFillIntent(target, false, false, "masque-disabled")
        end
    end

    local auraPreview = button._conditionalAuraPreview == true
        or button._conditionalAuraDurationTextPreview == true
    local cooldownPreview = button._conditionalPreviewDomain == "cooldown"

    if button._auraPrimarySwipeActive == true or auraPreview then
        local mode = "aura"
        local reason = "aura"
        local static = false
        if button._auraHasTimer == false and not auraPreview then
            mode = "aura_static"
            reason = "aura-static"
            static = true
        end
        return SetIconFillIntent(
            target,
            true,
            true,
            reason,
            mode,
            style.iconFillAuraColor or DEFAULT_ICON_FILL_AURA_COLOR,
            true,
            static
        )
    end

    local cooldownReason
    if cooldownPreview then
        cooldownReason = "cooldown-preview"
    elseif button._cooldownState == STATE_COOLDOWN then
        cooldownReason = "cooldown"
    elseif UsesIconFillChargeBehavior(buttonData)
        and button._chargeRecharging == true
        and button._hideCooldownChargesActive ~= true then
        cooldownReason = "charge-recharge"
    end

    if cooldownReason then
        return SetIconFillIntent(
            target,
            true,
            true,
            cooldownReason,
            "cooldown",
            style.iconFillCooldownColor or DEFAULT_ICON_FILL_COOLDOWN_COLOR,
            false,
            false
        )
    end

    return SetIconFillIntent(target, true, false, "inactive")
end

ST._buttonVisualStateSnapshotsEnabled = ST._buttonVisualStateSnapshotsEnabled == true

local function SetButtonVisualStateSnapshotsEnabled(enabled)
    ST._buttonVisualStateSnapshotsEnabled = enabled == true
end

local function AreButtonVisualStateSnapshotsEnabled()
    return ST._buttonVisualStateSnapshotsEnabled == true
end

local function ResolveDesaturationReason(button, cooldownActive, chargeZero)
    if not IsTrue(button._desatCooldownActive) then
        return nil
    end

    if chargeZero then
        return "zero-charges"
    end

    if cooldownActive then
        return "cooldown"
    end

    if IsTrue(button._auraPrimarySwipeActive) then
        return "aura"
    end

    return "cooldown-active"
end

local function IsReadyEligible(button, buttonData, cooldownActive)
    if cooldownActive then
        return false
    end

    if IsTrue(button._desatCooldownActive) then
        return false
    end

    if IsTrue(button._noCooldown) then
        return false
    end

    if buttonData and buttonData.isPassive then
        return false
    end

    return true
end

local function IsTextureReady(button, buttonData)
    if not buttonData then
        return false
    end

    if buttonData.isPassive then
        return false
    end

    if IsTrue(button._noCooldown) then
        return false
    end

    return button._desatCooldownActive == false
end

local function CopyTextVisualState(button, text, context)
    local preservedSecretTextRender = IsTrue(context and context.preserveSecretTextRender)
    local isTextSnapshot = (context and context.displayMode == "text") or button._isText == true
    local textSidecarsAreFresh = isTextSnapshot
        and context
        and context.phase == "post-dispatch"
        and not preservedSecretTextRender
    local intent = textSidecarsAreFresh and button._textVisualIntent or nil
    local hasIntent = type(intent) == "table"
    text.preservedSecretTextRender = preservedSecretTextRender
    text.intentAvailable = hasIntent
    if hasIntent then
        text.domain = intent.domain
        text.available = intent.available
        text.unusable = intent.unusable
        text.outOfRange = intent.outOfRange
        text.auraActive = intent.auraActive
        text.auraHasTimer = intent.auraHasTimer
        text.timePresent = intent.timePresent
        text.auraTimePresent = intent.auraTimePresent
        text.cooldownDeferred = intent.cooldownDeferred
        text.chargeState = intent.chargeState
        text.currentCharges = intent.currentCharges
        text.maxCharges = intent.maxCharges
        text.stackSource = intent.stackSource
        text.stackPresent = intent.stackPresent
        text.stackSecret = intent.stackSecret
        text.secretDuration = intent.secretDuration
        text.secretDurationToken = intent.secretDurationToken
        text.secretStack = intent.secretStack
        text.secretName = intent.secretName
        text.hasText = intent.hasText
        text.pulseActive = intent.pulseActive
    else
        text.domain = nil
        text.available = not button._desatCooldownActive
        text.unusable = IsTrue(button._isUnusable)
        text.outOfRange = IsTrue(button._isOutOfRange)
        text.auraActive = IsTrue(button._auraActive)
        text.auraHasTimer = IsTrue(button._auraHasTimer)
        text.timePresent = nil
        text.auraTimePresent = nil
        text.cooldownDeferred = IsTrue(button._cooldownDeferred)
        text.chargeState = button._chargeState
        text.currentCharges = button._currentReadableCharges
        text.maxCharges = nil
        text.stackSource = nil
        text.stackPresent = nil
        text.stackSecret = nil
        text.secretDuration = nil
        text.secretDurationToken = nil
        text.secretStack = nil
        text.secretName = nil
        text.hasText = nil
        text.pulseActive = nil
    end

    local applied = textSidecarsAreFresh and button._textVisualApplied or nil
    local hasApplied = type(applied) == "table"
    text.appliedAvailable = hasApplied
    if hasApplied then
        text.appliedWritePath = applied.writePath
        text.appliedHasText = applied.hasText
        text.appliedSecretDuration = applied.secretDuration
        text.appliedSecretStack = applied.secretStack
        text.appliedSecretName = applied.secretName
        text.appliedPulseActive = applied.pulseActive
        text.appliedAlpha = applied.alpha
    else
        text.appliedWritePath = nil
        text.appliedHasText = nil
        text.appliedSecretDuration = nil
        text.appliedSecretStack = nil
        text.appliedSecretName = nil
        text.appliedPulseActive = nil
        text.appliedAlpha = nil
    end
end

local function CopyBarVisualState(button, bar, context)
    local isBarSnapshot = (context and context.displayMode == "bars") or button._isBar == true
    local barSidecarsAreFresh = isBarSnapshot
        and context
        and context.phase == "post-dispatch"
        and not IsTrue(button._visibilityHidden)
    local intent = barSidecarsAreFresh and button._barVisualIntent or nil
    local hasIntent = type(intent) == "table"

    bar.intentAvailable = hasIntent
    if hasIntent then
        bar.domain = intent.domain
        bar.onCooldown = intent.onCooldown
        bar.chargeState = intent.chargeState
        bar.colorReason = intent.colorReason
        bar.auraColorReason = intent.auraColorReason
        bar.auraEffectActive = intent.auraEffectActive
        bar.auraEffectReason = intent.auraEffectReason
        bar.pulseActive = intent.pulseActive
        bar.pulseMode = intent.pulseMode
        bar.colorShiftActive = intent.colorShiftActive
        bar.colorShiftMode = intent.colorShiftMode
        bar.stackDisplay = intent.stackDisplay
        bar.stackMode = intent.stackMode
        bar.stackSegmentLayerActive = intent.stackSegmentLayerActive
        bar.gcdSuppressed = intent.gcdSuppressed
        bar.colorR = intent.colorR
        bar.colorG = intent.colorG
        bar.colorB = intent.colorB
        bar.colorA = intent.colorA
        bar.colorShiftBaseR = intent.colorShiftBaseR
        bar.colorShiftBaseG = intent.colorShiftBaseG
        bar.colorShiftBaseB = intent.colorShiftBaseB
        bar.colorShiftBaseA = intent.colorShiftBaseA
        bar.colorShiftTargetR = intent.colorShiftTargetR
        bar.colorShiftTargetG = intent.colorShiftTargetG
        bar.colorShiftTargetB = intent.colorShiftTargetB
        bar.colorShiftTargetA = intent.colorShiftTargetA
    else
        bar.domain = IsTrue(button._barAuraStackDisplay) and "stack" or nil
        bar.onCooldown = nil
        bar.chargeState = button._chargeState
        bar.colorReason = nil
        bar.auraColorReason = nil
        bar.auraEffectActive = nil
        bar.auraEffectReason = nil
        bar.pulseActive = nil
        bar.pulseMode = nil
        bar.colorShiftActive = nil
        bar.colorShiftMode = nil
        bar.stackDisplay = IsTrue(button._barAuraStackDisplay)
        bar.stackMode = button._barAuraStackMode
        bar.stackSegmentLayerActive = nil
        bar.gcdSuppressed = IsTrue(button._barGCDSuppressed)
        bar.colorR = nil
        bar.colorG = nil
        bar.colorB = nil
        bar.colorA = nil
        bar.colorShiftBaseR = nil
        bar.colorShiftBaseG = nil
        bar.colorShiftBaseB = nil
        bar.colorShiftBaseA = nil
        bar.colorShiftTargetR = nil
        bar.colorShiftTargetG = nil
        bar.colorShiftTargetB = nil
        bar.colorShiftTargetA = nil
    end

    local applied = barSidecarsAreFresh and button._barVisualApplied or nil
    local hasApplied = type(applied) == "table"
    bar.appliedAvailable = hasApplied
    if hasApplied then
        bar.appliedColorReason = applied.colorReason
        bar.appliedAuraColorActive = applied.auraColorActive
        bar.appliedAuraEffectActive = applied.auraEffectActive
        bar.appliedPulseActive = applied.pulseActive
        bar.appliedPulseMode = applied.pulseMode
        bar.appliedColorShiftActive = applied.colorShiftActive
        bar.appliedColorShiftMode = applied.colorShiftMode
        bar.appliedStackVisualActive = applied.stackVisualActive
        bar.appliedStackMode = applied.stackMode
        bar.appliedBaseFillHidden = applied.baseFillHidden
        bar.appliedGcdSuppressed = applied.gcdSuppressed
        bar.appliedColorR = applied.colorR
        bar.appliedColorG = applied.colorG
        bar.appliedColorB = applied.colorB
        bar.appliedColorA = applied.colorA
    else
        bar.appliedColorReason = nil
        bar.appliedAuraColorActive = nil
        bar.appliedAuraEffectActive = nil
        bar.appliedPulseActive = nil
        bar.appliedPulseMode = nil
        bar.appliedColorShiftActive = nil
        bar.appliedColorShiftMode = nil
        bar.appliedStackVisualActive = IsTrue(button._barAuraStackVisualActive)
        bar.appliedStackMode = button._barAuraStackVisualMode
        bar.appliedBaseFillHidden = IsTrue(button._barAuraBaseFillHidden)
        bar.appliedGcdSuppressed = IsTrue(button._barGCDSuppressed)
        bar.appliedColorR = nil
        bar.appliedColorG = nil
        bar.appliedColorB = nil
        bar.appliedColorA = nil
    end
end

local function ClearTable(tbl)
    if type(tbl) ~= "table" then
        return
    end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function CopyTriggerConditionList(sourceConditions, target)
    if type(sourceConditions) ~= "table" or #sourceConditions == 0 then
        target.conditions = nil
        return
    end

    local conditions = {}
    for index, condition in ipairs(sourceConditions) do
        conditions[index] = {
            key = condition.key,
            expected = condition.expected,
            actual = condition.actual,
            matched = condition.matched == true,
        }
    end
    target.conditions = conditions
end

local function CopyTriggerRowState(source, target)
    if type(source) ~= "table" then
        return
    end

    target.rowIndex = source.rowIndex
    target.enabled = source.enabled == true
    target.active = source.active == true
    target.skipped = source.skipped == true
    target.hasRuntime = source.hasRuntime == true
    target.conditionCount = source.conditionCount
    target.matched = source.matched == true
    target.reason = source.reason
    target.failedConditionKey = source.failedConditionKey
    target.expected = source.expected
    target.actual = source.actual
    CopyTriggerConditionList(source.conditions, target)
end

local function CopyTriggerPanelRows(sourceRows, target)
    if type(sourceRows) ~= "table" or #sourceRows == 0 then
        target.rows = nil
        return
    end

    local rows = {}
    for index, sourceRow in ipairs(sourceRows) do
        local row = {}
        CopyTriggerRowState(sourceRow, row)
        rows[index] = row
    end
    target.rows = rows
end

local function CopyTriggerPanelState(source, target)
    if type(source) ~= "table" then
        return
    end

    target.rowCount = source.rowCount
    target.runtimeRowCount = source.runtimeRowCount
    target.activeRowCount = source.activeRowCount
    target.matched = source.matched == true
    target.matchReason = source.matchReason or source.reason
    target.displayType = source.displayType
    target.hasSettings = source.hasSettings == true
    target.showDisplay = source.showDisplay == true
    target.triggerMatched = source.triggerMatched == true
    target.hasTriggerEffectPreview = source.hasTriggerEffectPreview == true
    target.isEditing = source.isEditing == true
    target.isUnlocked = source.isUnlocked == true
    target.isGroupedPreview = source.isGroupedPreview == true
    target.effectsActive = source.effectsActive == true
    target.soundVisible = source.soundVisible == true
    target.rendered = source.rendered == true
    target.displayReason = source.displayReason
    target.forceReason = source.forceReason
    CopyTriggerPanelRows(source.rows, target)
end

local function CopyTriggerVisualState(button, trigger)
    ClearTable(trigger)

    local rowSource = button._triggerVisualRow
    if type(rowSource) == "table" then
        local row = {}
        CopyTriggerRowState(rowSource, row)
        trigger.row = row
    end

    local panelSource = button._triggerVisualPanel
    if type(panelSource) == "table" then
        local panel = {}
        CopyTriggerPanelState(panelSource, panel)
        trigger.panel = panel
    end

    trigger.available = trigger.row ~= nil or trigger.panel ~= nil
end

local function CopyTextureDisplayVisualState(button, texture)
    ClearTable(texture)

    local intent = button._textureDisplayIntent
    local hasIntent = type(intent) == "table"
    texture.intentAvailable = hasIntent
    if hasIntent then
        texture.displayType = intent.displayType
        texture.hasSettings = intent.hasSettings == true
        texture.showDisplay = intent.showDisplay == true
        texture.reason = intent.reason
        texture.isEditing = intent.isEditing == true
        texture.isConfigForceVisible = intent.isConfigForceVisible == true
        texture.isUnlocked = intent.isUnlocked == true
        texture.isGroupedPreview = intent.isGroupedPreview == true
        texture.hasPreviewSelection = intent.hasPreviewSelection == true
        texture.bypassModuleAlpha = intent.bypassModuleAlpha == true
    else
        texture.displayType = nil
        texture.hasSettings = false
        texture.showDisplay = false
        texture.reason = nil
        texture.isEditing = false
        texture.isConfigForceVisible = false
        texture.isUnlocked = false
        texture.isGroupedPreview = false
        texture.hasPreviewSelection = false
        texture.bypassModuleAlpha = false
    end

    local applied = button._textureDisplayApplied
    local hasApplied = type(applied) == "table"
    texture.appliedAvailable = hasApplied
    if hasApplied then
        texture.appliedRendered = applied.rendered == true
        texture.appliedShown = applied.shown == true
        texture.appliedDisplayType = applied.displayType
        texture.appliedAlpha = applied.alpha
        texture.appliedDriverAlpha = applied.driverAlpha
        texture.appliedHasSavedDisplay = applied.hasSavedDisplay == true
        texture.appliedDragEnabled = applied.dragEnabled == true
        texture.appliedWrapperManaged = applied.wrapperManaged == true
    else
        texture.appliedRendered = false
        texture.appliedShown = false
        texture.appliedDisplayType = nil
        texture.appliedAlpha = nil
        texture.appliedDriverAlpha = nil
        texture.appliedHasSavedDisplay = false
        texture.appliedDragEnabled = false
        texture.appliedWrapperManaged = false
    end
end

local function CopyTextureEffectSections(sourceSections)
    if type(sourceSections) ~= "table" then
        return nil
    end

    local sections = {}
    local hasSections = false
    for key, source in pairs(sourceSections) do
        if type(source) == "table" then
            sections[key] = {
                enabled = source.enabled == true,
                active = source.active == true,
                reason = source.reason,
                preview = source.preview == true,
                effectType = source.effectType,
                normalizedEffectType = source.normalizedEffectType,
                combatOnly = source.combatOnly == true,
                invert = source.invert == true,
            }
            hasSections = true
        end
    end

    return hasSections and sections or nil
end

local function CopyTextureEffectsVisualState(button, textureEffects)
    local intent = button._textureEffectIntent
    local hasIntent = type(intent) == "table"
    textureEffects.intentAvailable = hasIntent
    if hasIntent then
        textureEffects.hasIndicators = intent.hasIndicators == true
        textureEffects.freezeGeometryWhileUnlocked = intent.freezeGeometryWhileUnlocked == true
        textureEffects.pulseActive = intent.pulseActive == true
        textureEffects.pulseSection = intent.pulseSection
        textureEffects.colorShiftActive = intent.colorShiftActive == true
        textureEffects.colorShiftSection = intent.colorShiftSection
        textureEffects.shrinkExpandActive = intent.shrinkExpandActive == true
        textureEffects.shrinkExpandSection = intent.shrinkExpandSection
        textureEffects.bounceActive = intent.bounceActive == true
        textureEffects.bounceSection = intent.bounceSection
        textureEffects.sections = CopyTextureEffectSections(intent.sections)
    else
        textureEffects.hasIndicators = false
        textureEffects.freezeGeometryWhileUnlocked = false
        textureEffects.pulseActive = false
        textureEffects.pulseSection = nil
        textureEffects.colorShiftActive = false
        textureEffects.colorShiftSection = nil
        textureEffects.shrinkExpandActive = false
        textureEffects.shrinkExpandSection = nil
        textureEffects.bounceActive = false
        textureEffects.bounceSection = nil
        textureEffects.sections = nil
    end

    local applied = button._textureEffectApplied
    local hasApplied = type(applied) == "table"
    textureEffects.appliedAvailable = hasApplied
    if hasApplied then
        textureEffects.appliedPulseActive = applied.pulseActive == true
        textureEffects.appliedPulseSection = applied.pulseSection
        textureEffects.appliedColorShiftActive = applied.colorShiftActive == true
        textureEffects.appliedColorShiftSection = applied.colorShiftSection
        textureEffects.appliedShrinkExpandActive = applied.shrinkExpandActive == true
        textureEffects.appliedShrinkExpandSection = applied.shrinkExpandSection
        textureEffects.appliedBounceActive = applied.bounceActive == true
        textureEffects.appliedBounceSection = applied.bounceSection
        textureEffects.appliedFreezeGeometryWhileUnlocked = applied.freezeGeometryWhileUnlocked == true
    else
        textureEffects.appliedPulseActive = false
        textureEffects.appliedPulseSection = nil
        textureEffects.appliedColorShiftActive = false
        textureEffects.appliedColorShiftSection = nil
        textureEffects.appliedShrinkExpandActive = false
        textureEffects.appliedShrinkExpandSection = nil
        textureEffects.appliedBounceActive = false
        textureEffects.appliedBounceSection = nil
        textureEffects.appliedFreezeGeometryWhileUnlocked = false
    end
end

local function ClearButtonVisualState(button)
    if button then
        button._visualState = nil
        button._visualStateContext = nil
        button._textVisualIntent = nil
        button._textVisualApplied = nil
        button._iconGlowIntent = nil
        button._barVisualIntent = nil
        button._barVisualApplied = nil
        button._textureDisplayIntent = nil
        button._textureDisplayApplied = nil
        button._textureEffectIntent = nil
        button._textureEffectApplied = nil
        button._triggerVisualRow = nil
        button._triggerVisualPanel = nil
    end
end

local function RefreshButtonVisualState(button, context)
    if type(button) ~= "table" then
        return nil
    end

    context = context or {}

    local state = button._visualState
    if type(state) ~= "table" then
        state = {}
        button._visualState = state
    end

    local buttonData = button.buttonData
    local style = button.style
    local cooldownActive = button._cooldownState == STATE_COOLDOWN
    local chargeZero = button._chargeState == CHARGE_STATE_ZERO
    local readyEligible = IsReadyEligible(button, buttonData, cooldownActive)
    local textureReady = IsTextureReady(button, buttonData)
    local iconDesaturationIntent = ResolveIconDesaturationIntent(button, buttonData, style)
    local iconTintIntent = button._iconTintIntent
    local hasIconTintIntent = type(iconTintIntent) == "table"
    local iconFillIntent = button._iconFillIntent
    local hasIconFillIntent = type(iconFillIntent) == "table"
    local iconGlowIntent = button._iconGlowIntent
    local hasIconGlowIntent = type(iconGlowIntent) == "table"

    state.version = 1
    state.phase = context.phase
    state.displayMode = context.displayMode
    state.buttonType = buttonData and buttonData.type
    state.isText = IsTrue(button._isText)
    state.isBar = IsTrue(button._isBar)
    state.cooldownVisualActive = IsTrue(button._desatCooldownActive)
    state.readyEligible = readyEligible

    local cooldown = EnsureSection(state, "cooldown")
    cooldown.state = button._cooldownState
    cooldown.active = cooldownActive
    cooldown.deferred = IsTrue(button._cooldownDeferred)
    cooldown.noCooldown = IsTrue(button._noCooldown)
    cooldown.durationObj = button._durationObj
    cooldown.source = context.cooldownSource
    cooldown.presentationState = context.presentationState
    cooldown.spellID = context.cooldownSpellId

    local presentation = EnsureSection(state, "presentation")
    presentation.isOnGCD = IsTrue(context.isOnGCD) or IsTrue(button._isOnGCD)
    presentation.gcdOnly = IsTrue(context.isGCDOnly)
    presentation.showGCDSwipe = style and IsTrue(style.showGCDSwipe) or false
    presentation.barGCDSuppressed = IsTrue(button._barGCDSuppressed)
    presentation.durationObj = button._durationObj

    local aura = EnsureSection(state, "aura")
    aura.trackingReady = IsTrue(button._auraTrackingReady)
    aura.active = IsTrue(button._auraActive)
    aura.ownsPrimarySwipe = IsTrue(context.auraOwnsPrimarySwipe)
    aura.overrideActive = IsTrue(context.auraOverrideActive)
    aura.primarySwipeActive = IsTrue(button._auraPrimarySwipeActive)
    aura.inPandemic = IsTrue(button._inPandemic)
    aura.spellID = button._auraSpellID
    aura.unit = button._auraUnit
    aura.durationObj = button._auraDurationObj

    local charges = EnsureSection(state, "charges")
    charges.state = button._chargeState
    charges.zero = chargeZero
    charges.full = button._chargeState == CHARGE_STATE_FULL
    charges.missing = button._chargeState == CHARGE_STATE_MISSING
    charges.recharging = IsTrue(button._chargeRecharging)
    charges.cooldownVisualActive = IsTrue(button._chargeCooldownVisualActive)
    charges.durationObj = button._chargeDurationObj
    charges.currentReadable = button._currentReadableCharges
    charges.countReadable = button._chargeCountReadable
    charges.zeroConfirmed = IsTrue(button._zeroChargesConfirmed)
    charges.mainCooldownShown = IsTrue(button._mainCDShown)

    local visibility = EnsureSection(state, "visibility")
    visibility.hidden = IsTrue(button._visibilityHidden)
    visibility.alphaOverride = button._visibilityAlphaOverride
    visibility.rawHidden = IsTrue(button._rawVisibilityHidden)
    visibility.rawAlphaOverride = button._rawVisibilityAlphaOverride
    visibility.rawReasonBits = button._rawVisibilityReasonBits
    visibility.rawReasonMode = button._rawVisibilityReasonMode
    visibility.reasonBits = button._visibilityReasonBits
    visibility.reasonMode = button._visibilityReasonMode
    visibility.mode = button._visibilityFinalMode
        or ResolveVisibilityMode(button._visibilityHidden, button._visibilityAlphaOverride)
    visibility.rawMode = button._rawVisibilityReasonMode
        or ResolveVisibilityMode(button._rawVisibilityHidden, button._rawVisibilityAlphaOverride)
    visibility.overrideSource = button._visibilityOverrideSource
    visibility.triggerSuppressed = IsTrue(button._visibilityTriggerSuppressed)
    visibility.compactLayout = IsTrue(button._visibilityCompactLayout)
    visibility.forceVisible = IsTrue(button._forceVisibleByConfig)
    visibility.forceVisibleByConfig = IsTrue(context.forceVisibleByConfig)
    visibility.forceVisibleByPreview = IsTrue(context.forceVisibleByPreview)
    visibility.forceVisibleByUnlockPreview = IsTrue(context.forceVisibleByUnlockPreview)
    visibility.lastAlpha = button._lastVisAlpha
    visibility.appliedAlpha = button._lastVisAlpha
    visibility.hiddenPhase = context.phase == "hidden"
    CopyVisibilityReasonNames(visibility, button._rawVisibilityReasonBits or button._visibilityReasonBits)

    local usability = EnsureSection(state, "usability")
    usability.spellOutOfRange = IsTrue(button._spellOutOfRange)
    usability.conditionalPreview = button._conditionalPreviewKind ~= nil
    usability.conditionalPreviewKind = button._conditionalPreviewKind
    usability.conditionalPreviewDomain = button._conditionalPreviewDomain
    usability.conditionalPreviewRemaining = button._conditionalPreviewRemaining

    local desaturation = EnsureSection(state, "desaturation")
    desaturation.cooldownActive = state.cooldownVisualActive
    desaturation.active = state.cooldownVisualActive
    desaturation.applied = IsTrue(button._desaturated)
    desaturation.reason = ResolveDesaturationReason(button, cooldownActive, chargeZero)
    desaturation.intentActive = IsTrue(iconDesaturationIntent.active)
    desaturation.intentReason = iconDesaturationIntent.reason

    local icon = EnsureSection(state, "icon")
    local iconDesaturation = EnsureSection(icon, "desaturation")
    iconDesaturation.active = IsTrue(iconDesaturationIntent.active)
    iconDesaturation.reason = iconDesaturationIntent.reason
    iconDesaturation.applied = IsTrue(button._desaturated)

    local tint = EnsureSection(state, "tint")
    tint.unusableActive = IsTrue(button._unusableTintActive)
    tint.r = button._vertexR
    tint.g = button._vertexG
    tint.b = button._vertexB
    tint.a = button._vertexA
    tint.hasVertex = button._vertexR ~= nil or button._vertexG ~= nil or button._vertexB ~= nil or button._vertexA ~= nil
    tint.intentAvailable = hasIconTintIntent
    tint.intentActive = hasIconTintIntent and IsTrue(iconTintIntent.active) or false
    tint.intentReason = hasIconTintIntent and iconTintIntent.reason or nil
    tint.intentUnusableActive = hasIconTintIntent and IsTrue(iconTintIntent.unusableActive) or false
    tint.intentR = hasIconTintIntent and iconTintIntent.r or nil
    tint.intentG = hasIconTintIntent and iconTintIntent.g or nil
    tint.intentB = hasIconTintIntent and iconTintIntent.b or nil
    tint.intentA = hasIconTintIntent and iconTintIntent.a or nil

    local iconFill = EnsureSection(state, "iconFill")
    iconFill.active = IsTrue(button._iconFillActive)
    iconFill.mode = button._iconFillMode
    iconFill.auraActive = IsTrue(button._iconFillAuraActive)
    iconFill.onUpdateInstalled = IsTrue(button._iconFillOnUpdateInstalled)
    iconFill.r = button._iconFillColorR
    iconFill.g = button._iconFillColorG
    iconFill.b = button._iconFillColorB
    iconFill.a = button._iconFillColorA
    iconFill.intentAvailable = hasIconFillIntent
    iconFill.intentFillAvailable = hasIconFillIntent and IsTrue(iconFillIntent.available) or false
    iconFill.intentActive = hasIconFillIntent and IsTrue(iconFillIntent.active) or false
    iconFill.intentMode = hasIconFillIntent and iconFillIntent.mode or nil
    iconFill.intentReason = hasIconFillIntent and iconFillIntent.reason or nil
    iconFill.intentAuraActive = hasIconFillIntent and IsTrue(iconFillIntent.auraActive) or false
    iconFill.intentStatic = hasIconFillIntent and IsTrue(iconFillIntent.static) or false
    iconFill.intentUsesOnUpdate = hasIconFillIntent and IsTrue(iconFillIntent.usesOnUpdate) or false
    iconFill.intentSuppressCooldownSwipe = hasIconFillIntent and IsTrue(iconFillIntent.suppressCooldownSwipe) or false
    iconFill.intentSuppressAuraBlizzardSwipe = hasIconFillIntent and IsTrue(iconFillIntent.suppressAuraBlizzardSwipe) or false
    iconFill.intentR = hasIconFillIntent and iconFillIntent.r or nil
    iconFill.intentG = hasIconFillIntent and iconFillIntent.g or nil
    iconFill.intentB = hasIconFillIntent and iconFillIntent.b or nil
    iconFill.intentA = hasIconFillIntent and iconFillIntent.a or nil

    local ready = EnsureSection(state, "ready")
    ready.eligible = readyEligible
    ready.glowActive = IsTrue(button._readyGlowActive)
    ready.glowStartTime = button._readyGlowStartTime
    ready.maxChargesActive = IsTrue(button._readyGlowMaxChargesActive)

    local glows = EnsureSection(state, "glows")
    glows.intentAvailable = hasIconGlowIntent
    if hasIconGlowIntent then
        local procIntent = iconGlowIntent.proc or {}
        glows.procIntentAvailable = procIntent.available == true
        glows.procIntentActive = procIntent.active == true
        glows.procReason = procIntent.reason
        glows.procPreview = procIntent.preview == true
        glows.procCombatSuppressed = procIntent.combatSuppressed == true
        glows.procOverlayActive = procIntent.procOverlayActive == true

        local auraIntent = iconGlowIntent.aura or {}
        glows.auraIntentAvailable = auraIntent.available == true
        glows.auraIntentActive = auraIntent.active == true
        glows.auraReason = auraIntent.reason
        glows.auraPreview = auraIntent.preview == true
        glows.auraCombatSuppressed = auraIntent.combatSuppressed == true
        glows.auraPandemicIntent = auraIntent.pandemic == true
        glows.auraInvert = auraIntent.invert == true
        glows.auraTargetRequired = auraIntent.targetRequired == true
        glows.auraTargetExists = auraIntent.targetExists

        local readyIntent = iconGlowIntent.ready or {}
        glows.readyIntentAvailable = readyIntent.available == true
        glows.readyIntentActive = readyIntent.active == true
        glows.readyReason = readyIntent.reason
        glows.readyPreview = readyIntent.preview == true
        glows.readyCombatSuppressed = readyIntent.combatSuppressed == true
        glows.readySuppressedByProc = readyIntent.suppressedByProc == true
        glows.readyAuraSuppressed = readyIntent.auraSuppressed == true
        glows.readyMaxCharges = readyIntent.maxCharges == true
        glows.readyDurationWindow = readyIntent.durationWindow == true
    else
        glows.procIntentAvailable = nil
        glows.procIntentActive = nil
        glows.procReason = nil
        glows.procPreview = nil
        glows.procCombatSuppressed = nil
        glows.procOverlayActive = nil
        glows.auraIntentAvailable = nil
        glows.auraIntentActive = nil
        glows.auraReason = nil
        glows.auraPreview = nil
        glows.auraCombatSuppressed = nil
        glows.auraPandemicIntent = nil
        glows.auraInvert = nil
        glows.auraTargetRequired = nil
        glows.auraTargetExists = nil
        glows.readyIntentAvailable = nil
        glows.readyIntentActive = nil
        glows.readyReason = nil
        glows.readyPreview = nil
        glows.readyCombatSuppressed = nil
        glows.readySuppressedByProc = nil
        glows.readyAuraSuppressed = nil
        glows.readyMaxCharges = nil
        glows.readyDurationWindow = nil
    end
    glows.procActive = IsTrue(button._procGlowActive)
    glows.auraActive = IsTrue(button._auraGlowActive)
    glows.auraPandemic = IsTrue(button._auraGlowPandemic)
    glows.readyActive = IsTrue(button._readyGlowActive)
    glows.barAuraEffectActive = IsTrue(button._barAuraEffectActive)
    glows.barPulseActive = IsTrue(button._barPulseActive)
    glows.barColorShiftActive = IsTrue(button._barColorShiftActive)

    local bar = EnsureSection(state, "bar")
    CopyBarVisualState(button, bar, context)

    local text = EnsureSection(state, "text")
    CopyTextVisualState(button, text, context)
    text.durationObj = button._durationObj

    local texture = EnsureSection(state, "texture")
    CopyTextureDisplayVisualState(button, texture)

    local textureEffects = EnsureSection(state, "textureEffects")
    textureEffects.ready = textureReady
    textureEffects.cooldownActive = state.cooldownVisualActive
    textureEffects.chargeState = button._chargeState
    textureEffects.procActive = IsTrue(button._procOverlayActive)
    CopyTextureEffectsVisualState(button, textureEffects)

    local trigger = EnsureSection(state, "trigger")
    CopyTriggerVisualState(button, trigger)

    local applied = EnsureSection(state, "applied")
    applied.desaturated = IsTrue(button._desaturated)
    applied.unusableTintActive = IsTrue(button._unusableTintActive)
    applied.vertexR = button._vertexR
    applied.vertexG = button._vertexG
    applied.vertexB = button._vertexB
    applied.vertexA = button._vertexA
    applied.iconFillActive = IsTrue(button._iconFillActive)
    applied.readyGlowActive = glows.readyActive
    applied.procGlowActive = glows.procActive
    applied.auraGlowActive = glows.auraActive
    applied.barAuraEffectActive = glows.barAuraEffectActive
    applied.barPulseActive = glows.barPulseActive
    applied.barColorShiftActive = glows.barColorShiftActive
    applied.visibilityHidden = IsTrue(button._visibilityHidden)
    applied.alpha = button._lastVisAlpha

    return state
end

ST._RefreshButtonVisualState = RefreshButtonVisualState
ST._ClearButtonVisualState = ClearButtonVisualState
ST._SetButtonVisualStateSnapshotsEnabled = SetButtonVisualStateSnapshotsEnabled
ST._AreButtonVisualStateSnapshotsEnabled = AreButtonVisualStateSnapshotsEnabled
ST._ResolveIconFillIntent = ResolveIconFillIntent
ST._ResolveIconGlowIntent = ResolveIconGlowIntent
