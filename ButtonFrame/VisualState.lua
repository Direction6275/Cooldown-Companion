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

local function ClearButtonVisualState(button)
    if button then
        button._visualState = nil
        button._visualStateContext = nil
        button._textVisualIntent = nil
        button._textVisualApplied = nil
        button._barVisualIntent = nil
        button._barVisualApplied = nil
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

    local textureEffects = EnsureSection(state, "textureEffects")
    textureEffects.ready = textureReady
    textureEffects.cooldownActive = state.cooldownVisualActive
    textureEffects.chargeState = button._chargeState
    textureEffects.procActive = IsTrue(button._procOverlayActive)

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
