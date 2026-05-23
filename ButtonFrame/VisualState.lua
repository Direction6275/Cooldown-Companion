local ADDON_NAME, ST = ...

local CooldownLogic = ST.CooldownLogic or {}
local STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO
local CHARGE_STATE_FULL = CooldownLogic.CHARGE_STATE_FULL
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING
local ResolveIconDesaturationIntent = ST._ResolveIconDesaturationIntent

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

local function ClearButtonVisualState(button)
    if button then
        button._visualState = nil
        button._visualStateContext = nil
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
    visibility.reasonBits = button._visibilityReasonBits
    visibility.reasonMode = button._visibilityReasonMode
    visibility.forceVisible = IsTrue(button._forceVisibleByConfig)
    visibility.forceVisibleByConfig = IsTrue(context.forceVisibleByConfig)
    visibility.forceVisibleByPreview = IsTrue(context.forceVisibleByPreview)
    visibility.forceVisibleByUnlockPreview = IsTrue(context.forceVisibleByUnlockPreview)
    visibility.lastAlpha = button._lastVisAlpha

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

    local text = EnsureSection(state, "text")
    text.available = not state.cooldownVisualActive
    text.unusable = IsTrue(button._isUnusable)
    text.outOfRange = IsTrue(button._isOutOfRange)
    text.chargeState = button._chargeState
    text.durationObj = button._durationObj

    local textureEffects = EnsureSection(state, "textureEffects")
    textureEffects.ready = textureReady
    textureEffects.cooldownActive = state.cooldownVisualActive
    textureEffects.chargeState = button._chargeState
    textureEffects.procActive = IsTrue(button._procOverlayActive)

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
