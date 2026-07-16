local ADDON_NAME, ST = ...

local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic or {}
local STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN
local CHARGE_STATE_FULL = CooldownLogic.CHARGE_STATE_FULL
local ResolveIconDesaturationIntent = ST._ResolveIconDesaturationIntent
local GetButtonVisibilityReasonNames = ST._GetButtonVisibilityReasonNames
local DEFAULT_ICON_FILL_COOLDOWN_COLOR = {0.6, 0.13, 0.18, 0.55}
local UsesChargeBehavior = CooldownCompanion and CooldownCompanion.UsesChargeBehavior
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime

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

local function CopyFieldList(target, source, fields)
    for _, fieldName in ipairs(fields) do
        local value = nil
        if source then
            value = source[fieldName]
        end
        target[fieldName] = value
    end
end

local function CopyFieldMap(target, source, fieldMap)
    for targetField, sourceField in pairs(fieldMap) do
        local value = nil
        if source then
            value = source[sourceField]
        end
        target[targetField] = value
    end
end

local TEXT_INTENT_FIELDS = {
    "domain",
    "stackSource",
    "secretDuration",
    "secretDurationToken",
    "secretStack",
    "secretName",
    "hasText",
    "pulseActive",
}

local TEXT_APPLIED_FIELDS = {
    appliedWritePath = "writePath",
    appliedHasText = "hasText",
    appliedSecretDuration = "secretDuration",
    appliedSecretStack = "secretStack",
    appliedSecretName = "secretName",
    appliedPulseActive = "pulseActive",
}

local BAR_INTENT_FIELDS = {
    "domain",
    "colorReason",
    "auraColorReason",
    "auraEffectActive",
    "auraEffectReason",
    "pulseActive",
    "pulseMode",
    "colorShiftActive",
    "colorShiftMode",
    "stackDisplay",
    "stackMode",
    "gcdSuppressed",
}

local BAR_APPLIED_FIELDS = {
    appliedColorReason = "colorReason",
    appliedAuraEffectActive = "auraEffectActive",
    appliedPulseActive = "pulseActive",
    appliedColorShiftActive = "colorShiftActive",
    appliedGcdSuppressed = "gcdSuppressed",
}

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

local function SetIconFillIntent(target, available, active, reason, mode, color, static)
    target.available = available == true
    target.active = active == true
    target.reason = reason
    target.mode = mode
    target.static = static == true
    target.usesOnUpdate = target.active and target.static ~= true or false
    target.suppressCooldownSwipe = target.active
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

    -- 12.1: the live aura glow renders on the aura slot kit (AuraDisplay.lua);
    -- Blizzard's show/hide of the slot button IS the signal, so no live
    -- intent can exist here. This resolver only drives the CC-side config
    -- preview. The pandemic branch is the dormant seam: nothing sets
    -- _pandemicPreview until the Blizzard curve/formatter fixes land.
    local auraIndicatorEnabled = ResolveAuraIndicatorEnabled(buttonData, style)

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
    else
        SetGlowIntent(aura, true, false, "inactive")
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

    local cooldownPreview = button._conditionalPreviewDomain == "cooldown"

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
    CopyFieldList(text, hasIntent and intent or nil, TEXT_INTENT_FIELDS)

    local applied = textSidecarsAreFresh and button._textVisualApplied or nil
    local hasApplied = type(applied) == "table"
    text.appliedAvailable = hasApplied
    CopyFieldMap(text, hasApplied and applied or nil, TEXT_APPLIED_FIELDS)
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
    CopyFieldList(bar, hasIntent and intent or nil, BAR_INTENT_FIELDS)
    if not hasIntent then
        bar.domain = IsTrue(button._barAuraStackDisplay) and "stack" or nil
        bar.stackDisplay = IsTrue(button._barAuraStackDisplay)
        bar.stackMode = button._barAuraStackMode
        bar.gcdSuppressed = IsTrue(button._barGCDSuppressed)
    end

    local applied = barSidecarsAreFresh and button._barVisualApplied or nil
    local hasApplied = type(applied) == "table"
    bar.appliedAvailable = hasApplied
    CopyFieldMap(bar, hasApplied and applied or nil, BAR_APPLIED_FIELDS)
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
    local iconDesaturationIntent = ResolveIconDesaturationIntent(button, buttonData, style)
    local iconTintIntent = button._iconTintIntent
    local hasIconTintIntent = type(iconTintIntent) == "table"
    local iconFillIntent = button._iconFillIntent
    local hasIconFillIntent = type(iconFillIntent) == "table"
    local iconGlowIntent = button._iconGlowIntent
    local hasIconGlowIntent = type(iconGlowIntent) == "table"

    state.version = 1
    state.phase = context.phase
    state.cooldownVisualActive = IsTrue(button._desatCooldownActive)

    local cooldown = EnsureSection(state, "cooldown")
    cooldown.state = button._cooldownState
    cooldown.active = cooldownActive

    local presentation = EnsureSection(state, "presentation")
    presentation.barGCDSuppressed = IsTrue(button._barGCDSuppressed)

    local aura = EnsureSection(state, "aura")
    aura.unit = button._auraUnit

    local charges = EnsureSection(state, "charges")
    charges.state = button._chargeState

    local visibility = EnsureSection(state, "visibility")
    visibility.hidden = IsTrue(button._visibilityHidden)
    visibility.alphaOverride = button._visibilityAlphaOverride
    visibility.mode = button._visibilityFinalMode
        or ResolveVisibilityMode(button._visibilityHidden, button._visibilityAlphaOverride)
    visibility.rawMode = button._rawVisibilityReasonMode
        or ResolveVisibilityMode(button._rawVisibilityHidden, button._rawVisibilityAlphaOverride)
    visibility.overrideSource = button._visibilityOverrideSource
    visibility.triggerSuppressed = IsTrue(button._visibilityTriggerSuppressed)
    visibility.hiddenPhase = context.phase == "hidden"
    CopyVisibilityReasonNames(visibility, button._rawVisibilityReasonBits or button._visibilityReasonBits)

    local desaturation = EnsureSection(state, "desaturation")
    desaturation.cooldownActive = state.cooldownVisualActive
    desaturation.active = state.cooldownVisualActive
    desaturation.applied = IsTrue(button._desaturated)
    desaturation.intentActive = IsTrue(iconDesaturationIntent.active)

    local icon = EnsureSection(state, "icon")
    local iconDesaturation = EnsureSection(icon, "desaturation")
    iconDesaturation.active = IsTrue(iconDesaturationIntent.active)
    iconDesaturation.applied = IsTrue(button._desaturated)

    local tint = EnsureSection(state, "tint")
    tint.unusableActive = IsTrue(button._unusableTintActive)
    tint.intentAvailable = hasIconTintIntent
    tint.intentActive = hasIconTintIntent and IsTrue(iconTintIntent.active) or false
    tint.intentReason = hasIconTintIntent and iconTintIntent.reason or nil
    tint.intentUnusableActive = hasIconTintIntent and IsTrue(iconTintIntent.unusableActive) or false

    local iconFill = EnsureSection(state, "iconFill")
    iconFill.active = IsTrue(button._iconFillActive)
    iconFill.mode = button._iconFillMode
    iconFill.onUpdateInstalled = IsTrue(button._iconFillOnUpdateInstalled)
    iconFill.intentAvailable = hasIconFillIntent
    iconFill.intentActive = hasIconFillIntent and IsTrue(iconFillIntent.active) or false
    iconFill.intentMode = hasIconFillIntent and iconFillIntent.mode or nil
    iconFill.intentReason = hasIconFillIntent and iconFillIntent.reason or nil
    iconFill.intentUsesOnUpdate = hasIconFillIntent and IsTrue(iconFillIntent.usesOnUpdate) or false

    local glows = EnsureSection(state, "glows")
    glows.intentAvailable = hasIconGlowIntent
    if hasIconGlowIntent then
        local procIntent = iconGlowIntent.proc or {}
        glows.procIntentActive = procIntent.active == true
        glows.procReason = procIntent.reason
        glows.procPreview = procIntent.preview == true
        glows.procCombatSuppressed = procIntent.combatSuppressed == true
        glows.procOverlayActive = procIntent.procOverlayActive == true

        local auraIntent = iconGlowIntent.aura or {}
        glows.auraIntentActive = auraIntent.active == true
        glows.auraReason = auraIntent.reason
        glows.auraPreview = auraIntent.preview == true
        glows.auraCombatSuppressed = auraIntent.combatSuppressed == true
        glows.auraPandemicIntent = auraIntent.pandemic == true
        glows.auraInvert = auraIntent.invert == true

        local readyIntent = iconGlowIntent.ready or {}
        glows.readyIntentActive = readyIntent.active == true
        glows.readyReason = readyIntent.reason
        glows.readyPreview = readyIntent.preview == true
        glows.readyCombatSuppressed = readyIntent.combatSuppressed == true
        glows.readySuppressedByProc = readyIntent.suppressedByProc == true
        glows.readyAuraSuppressed = readyIntent.auraSuppressed == true
        glows.readyMaxCharges = readyIntent.maxCharges == true
        glows.readyDurationWindow = readyIntent.durationWindow == true
    else
        glows.procIntentActive = nil
        glows.procReason = nil
        glows.procPreview = nil
        glows.procCombatSuppressed = nil
        glows.procOverlayActive = nil
        glows.auraIntentActive = nil
        glows.auraReason = nil
        glows.auraPreview = nil
        glows.auraCombatSuppressed = nil
        glows.auraPandemicIntent = nil
        glows.auraInvert = nil
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

    local bar = EnsureSection(state, "bar")
    CopyBarVisualState(button, bar, context)

    local text = EnsureSection(state, "text")
    CopyTextVisualState(button, text, context)

    return state
end

ST._RefreshButtonVisualState = RefreshButtonVisualState
ST._ClearButtonVisualState = ClearButtonVisualState
ST._SetButtonVisualStateSnapshotsEnabled = SetButtonVisualStateSnapshotsEnabled
ST._AreButtonVisualStateSnapshotsEnabled = AreButtonVisualStateSnapshotsEnabled
ST._ResolveIconFillIntent = ResolveIconFillIntent
ST._ResolveIconGlowIntent = ResolveIconGlowIntent
