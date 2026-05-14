--[[
    CooldownCompanion - ResourceBarPanels
    Config panel builders for resource bar settings: anchoring, appearance,
    per-resource styling, custom aura bar panels, and layout order.
    Query helpers and shared builders live in ResourceBarPanelsHelpers.lua.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local LSM = LibStub("LibSharedMedia-3.0")
local CS = ST._configState
local IsPassiveOrProc = ST._IsPassiveOrProc
local ShowPopupAboveConfig = CS.ShowPopupAboveConfig

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateCharacterCopyButton = ST._CreateCharacterCopyButton
local CreateInfoButton = ST._CreateInfoButton
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local HookSliderEditBox = ST._HookSliderEditBox
local BuildAlphaControls = ST._BuildAlphaControls
local BuildIndependentAnchorTargetRow = ST._BuildIndependentAnchorTargetRow
local BuildPandemicBarControls = ST._BuildPandemicBarControls
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls
local BuildBarAuraPulseControls = ST._BuildBarAuraPulseControls
local BuildPandemicBarPulseControls = ST._BuildPandemicBarPulseControls
local AddPreviewToggleButton = ST._AddPreviewToggleButton
local RefreshConfigPanelForPreviewToggle = ST._RefreshConfigPanelForPreviewToggle
local CleanRecycledEntry = ST._CleanRecycledEntry
local ApplyConfigRowIcon = ST._ApplyConfigRowIcon
local tabInfoButtons = CS.tabInfoButtons

local function RefreshLayoutOrderPreview()
    if not (CS.resourceBarPanelActive and CS.col4Container and ST._RefreshColumn4) then
        return
    end
    ST._RefreshColumn4(CS.col4Container)
end

-- Shared constants from ResourceBarConstants
local RB = ST._RB
local POWER_NAMES = RB.POWER_NAMES
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local HIDE_AT_ZERO_ELIGIBLE = RB.HIDE_AT_ZERO_ELIGIBLE
local DEFAULT_POWER_COLORS = RB.DEFAULT_POWER_COLORS
local DEFAULT_MW_BASE_COLOR = RB.DEFAULT_MW_BASE_COLOR
local DEFAULT_MW_OVERLAY_COLOR = RB.DEFAULT_MW_OVERLAY_COLOR
local DEFAULT_MW_MAX_COLOR = RB.DEFAULT_MW_MAX_COLOR
local DEFAULT_CUSTOM_AURA_MAX_COLOR = RB.DEFAULT_CUSTOM_AURA_MAX_COLOR
local DEFAULT_RESOURCE_TEXT_FORMAT = RB.DEFAULT_RESOURCE_TEXT_FORMAT
local DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT = RB.DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE
local DEFAULT_RESOURCE_TEXT_COLOR = RB.DEFAULT_RESOURCE_TEXT_COLOR
local DEFAULT_RESOURCE_TEXT_ANCHOR = RB.DEFAULT_RESOURCE_TEXT_ANCHOR
local DEFAULT_RESOURCE_TEXT_X_OFFSET = RB.DEFAULT_RESOURCE_TEXT_X_OFFSET
local DEFAULT_RESOURCE_TEXT_Y_OFFSET = RB.DEFAULT_RESOURCE_TEXT_Y_OFFSET
local DEFAULT_SEG_THRESHOLD_COLOR = RB.DEFAULT_SEG_THRESHOLD_COLOR
local DEFAULT_CONTINUOUS_TICK_COLOR = RB.DEFAULT_CONTINUOUS_TICK_COLOR
local DEFAULT_CONTINUOUS_TICK_MODE = RB.DEFAULT_CONTINUOUS_TICK_MODE
local DEFAULT_CONTINUOUS_TICK_WIDTH = RB.DEFAULT_CONTINUOUS_TICK_WIDTH
local DEFAULT_HEALTH_BAR_COLOR = RB.DEFAULT_HEALTH_BAR_COLOR
local DEFAULT_HEALTH_BAR_OPACITY = RB.DEFAULT_HEALTH_BAR_OPACITY
local DEFAULT_HEALTH_BAR_FULL_COLOR = RB.DEFAULT_HEALTH_BAR_FULL_COLOR
local DEFAULT_HEALTH_BAR_HALF_COLOR = RB.DEFAULT_HEALTH_BAR_HALF_COLOR
local DEFAULT_HEALTH_BAR_LOW_COLOR = RB.DEFAULT_HEALTH_BAR_LOW_COLOR
local DEFAULT_HEALTH_BAR_GRADIENT = RB.DEFAULT_HEALTH_BAR_GRADIENT
local DEFAULT_HEALTH_BACKGROUND_COLOR = RB.DEFAULT_HEALTH_BACKGROUND_COLOR
local DEFAULT_HEALTH_BACKGROUND_FULL_COLOR = RB.DEFAULT_HEALTH_BACKGROUND_FULL_COLOR
local DEFAULT_HEALTH_BACKGROUND_HALF_COLOR = RB.DEFAULT_HEALTH_BACKGROUND_HALF_COLOR
local DEFAULT_HEALTH_BACKGROUND_LOW_COLOR = RB.DEFAULT_HEALTH_BACKGROUND_LOW_COLOR
local DEFAULT_HEALTH_BACKGROUND_OPACITY = RB.DEFAULT_HEALTH_BACKGROUND_OPACITY
local DEFAULT_HEALTH_BACKGROUND_GRADIENT = RB.DEFAULT_HEALTH_BACKGROUND_GRADIENT
local DEFAULT_HEALTH_ABSORB_COLOR = RB.DEFAULT_HEALTH_ABSORB_COLOR
local DEFAULT_HEALTH_HEAL_ABSORB_COLOR = RB.DEFAULT_HEALTH_HEAL_ABSORB_COLOR
local DEFAULT_HEALTH_INCOMING_HEAL_COLOR = RB.DEFAULT_HEALTH_INCOMING_HEAL_COLOR
local DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR = RB.DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR
local DEFAULT_HEALTH_EFFECT_TEXTURE = RB.DEFAULT_HEALTH_EFFECT_TEXTURE
local DEFAULT_COMBO_COLOR = RB.DEFAULT_COMBO_COLOR
local DEFAULT_COMBO_MAX_COLOR = RB.DEFAULT_COMBO_MAX_COLOR
local DEFAULT_COMBO_CHARGED_COLOR = RB.DEFAULT_COMBO_CHARGED_COLOR
local DEFAULT_RUNE_READY_COLOR = RB.DEFAULT_RUNE_READY_COLOR
local DEFAULT_RUNE_RECHARGING_COLOR = RB.DEFAULT_RUNE_RECHARGING_COLOR
local DEFAULT_RUNE_MAX_COLOR = RB.DEFAULT_RUNE_MAX_COLOR
local DEFAULT_SHARD_READY_COLOR = RB.DEFAULT_SHARD_READY_COLOR
local DEFAULT_SHARD_RECHARGING_COLOR = RB.DEFAULT_SHARD_RECHARGING_COLOR
local DEFAULT_SHARD_MAX_COLOR = RB.DEFAULT_SHARD_MAX_COLOR
local DEFAULT_HOLY_COLOR = RB.DEFAULT_HOLY_COLOR
local DEFAULT_HOLY_MAX_COLOR = RB.DEFAULT_HOLY_MAX_COLOR
local DEFAULT_CHI_COLOR = RB.DEFAULT_CHI_COLOR
local DEFAULT_CHI_MAX_COLOR = RB.DEFAULT_CHI_MAX_COLOR
local DEFAULT_ARCANE_COLOR = RB.DEFAULT_ARCANE_COLOR
local DEFAULT_ARCANE_MAX_COLOR = RB.DEFAULT_ARCANE_MAX_COLOR
local DEFAULT_ESSENCE_READY_COLOR = RB.DEFAULT_ESSENCE_READY_COLOR
local DEFAULT_ESSENCE_RECHARGING_COLOR = RB.DEFAULT_ESSENCE_RECHARGING_COLOR
local DEFAULT_ESSENCE_MAX_COLOR = RB.DEFAULT_ESSENCE_MAX_COLOR
local GetResolvedCustomAuraBarAuraUnit = RB.GetResolvedCustomAuraBarAuraUnit
local EnsureCustomAuraBarAuraUnit = RB.EnsureCustomAuraBarAuraUnit
local GetCustomBarEntryType = RB.GetCustomBarEntryType
local EnsureCustomBarId = RB.EnsureCustomBarId
local EnsureCustomBarLayout = RB.EnsureCustomBarLayout
local GetCustomBarLayout = RB.GetCustomBarLayout
local GetResourceSpecOverrideTable = RB.GetResourceSpecOverrideTable
local RESOURCE_HEALTH_DISPLAY_KEYS = RB.RESOURCE_HEALTH_DISPLAY_KEYS
local resourceSpecCopyButton
local resourceSpecCopyMenu

local function IsHeroSpecProxyCondition(cond)
    return type(cond) == "table"
        and cond.nodeID ~= nil
        and cond.heroSubTreeID ~= nil
        and cond.entryID == nil
        and type(cond.name) == "string"
        and type(cond.heroName) == "string"
        and cond.name == cond.heroName
end
local function IsSpellCustomBarConfig(cab)
    if RB.IsSpellCustomBarConfig then
        return RB.IsSpellCustomBarConfig(cab)
    end
    return GetCustomBarEntryType and GetCustomBarEntryType(cab) == "spell"
end

local function IsCustomBarAuraDisplayConfig(cab, isSpellCustomBar)
    if isSpellCustomBar == nil then
        isSpellCustomBar = IsSpellCustomBarConfig(cab)
    end

    return (not isSpellCustomBar) or (cab and cab.auraTracking == true)
end

local function GetCustomBarTrackingModeConfig(cab, isSpellCustomBar)
    if RB.GetCustomBarTrackingMode then
        return RB.GetCustomBarTrackingMode(cab, isSpellCustomBar)
    end

    local mode = cab and cab.trackingMode
    if mode == "active" or mode == "stacks" then
        return mode
    end
    return isSpellCustomBar and "active" or "stacks"
end

local RefreshCustomAuraBarAuraUnitForSpell = RB.RefreshCustomAuraBarAuraUnitForSpell

-- Imports from ResourceBarPanelsHelpers
local RBP = ST._RBP
local resourceBarCollapsedSections = RBP.collapsedSections
local BuildResourceAuraOverlaySection = RBP.BuildResourceAuraOverlaySection
local GetConfigActiveResources = RBP.GetConfigActiveResources
local GetCurrentConfigSpecID = RBP.GetCurrentConfigSpecID
local ReadSpecOverrideKey = RBP.ReadSpecOverrideKey
local WriteSpecOverrideKey = RBP.WriteSpecOverrideKey
local GetSafeRGBConfig = RBP.GetSafeRGBConfig
local GetSafeRGBAConfig = RBP.GetSafeRGBAConfig
local GetSegmentedThresholdValueConfig = RBP.GetSegmentedThresholdValueConfig
local GetContinuousTickModeConfig = RBP.GetContinuousTickModeConfig
local GetContinuousTickPercentConfig = RBP.GetContinuousTickPercentConfig
local GetContinuousTickAbsoluteConfig = RBP.GetContinuousTickAbsoluteConfig
local ResolveAuraColorSpellIDFromText = RBP.ResolveAuraColorSpellIDFromText
local GetAuraBarAutocompleteDisplayName = RBP.GetAuraBarAutocompleteDisplayName
local GetAuraBarAutocompleteDisplayIcon = RBP.GetAuraBarAutocompleteDisplayIcon
local GetAuraBarAutocompleteEntryName = RBP.GetAuraBarAutocompleteEntryName
local ResolveAuraBarAutocompleteEntry = RBP.ResolveAuraBarAutocompleteEntry
local ShowAuraBarAutocompleteResults = RBP.ShowAuraBarAutocompleteResults
local BuildAuraBarAutocompleteCache = RBP.BuildAuraBarAutocompleteCache
local IsResourceBarVerticalConfig = RBP.IsResourceBarVerticalConfig
local GetResourceThicknessFieldConfig = RBP.GetResourceThicknessFieldConfig
local GetResourceGapFieldConfig = RBP.GetResourceGapFieldConfig

local function EnsureResourceLayoutAnchor(settings, layout)
    if type(layout.independentAnchor) ~= "table" then
        layout.independentAnchor = type(settings.independentAnchor) == "table" and CopyTable(settings.independentAnchor)
            or { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    end
    layout.independentAnchor.point = layout.independentAnchor.point or "CENTER"
    layout.independentAnchor.relativePoint = layout.independentAnchor.relativePoint or "CENTER"
    layout.independentAnchor.x = tonumber(layout.independentAnchor.x) or 0
    layout.independentAnchor.y = tonumber(layout.independentAnchor.y) or 0
    if layout.independentAnchorLocked == nil then
        layout.independentAnchorLocked = settings.independentAnchorLocked
    end
    if layout.independentWidth == nil then
        layout.independentWidth = settings.independentWidth
    end
end

local ResolveSpecOverrideKey = ST._ResolveSpecOverrideKey
local StartDragTracking = ST._StartDragTracking
local GetDragIndicator = ST._GetDragIndicator
local HideDragIndicator = ST._HideDragIndicator
local ResetDragIndicatorStyle = ST._ResetDragIndicatorStyle

local function CopyTableValue(value)
    return type(value) == "table" and CopyTable(value) or value
end

local function SeedSpecResourceDisplaySettings(settings, powerType, specID, keys)
    local specSettings = GetResourceSpecOverrideTable(settings, powerType, specID, true)
    local baseSettings = settings and settings.resources and settings.resources[powerType]
    if not specSettings then return baseSettings end
    if type(baseSettings) == "table" and type(keys) == "table" then
        for _, key in ipairs(keys) do
            if specSettings[key] == nil and baseSettings[key] ~= nil then
                specSettings[key] = CopyTableValue(baseSettings[key])
            end
        end
    end
    return specSettings
end

local function ReadDisplaySetting(baseSettings, specSettings, key, fallback)
    if type(specSettings) == "table" and specSettings[key] ~= nil then
        return specSettings[key]
    end
    if type(baseSettings) == "table" and baseSettings[key] ~= nil then
        return baseSettings[key]
    end
    return fallback
end

CS._SeedSpecResourceDisplaySettings = SeedSpecResourceDisplaySettings
CS._ReadResourceDisplaySetting = ReadDisplaySetting
CS._GetCurrentConfigSpecID = GetCurrentConfigSpecID
CS._GetSpecResourceDisplayProfile = RB.GetSpecResourceDisplayProfile
CS._ResourceTextDisplayKeys = RB.RESOURCE_TEXT_DISPLAY_KEYS

local HealthResource = { ID = RB.RESOURCE_HEALTH }

function HealthResource.GetEffectTextureOptions()
    local options = {}
    local order = {}
    for _, name in ipairs(LSM:List("statusbar")) do
        options[name] = name
        table.insert(order, name)
    end
    return options, order
end

function HealthResource.NormalizeEffectTexture(health, key)
    if type(health[key]) ~= "string"
        or health[key] == ""
        or not LSM:IsValid("statusbar", health[key]) then
        health[key] = DEFAULT_HEALTH_EFFECT_TEXTURE
    end
end

function HealthResource.EnsureSettings(settings)
    settings.resources = settings.resources or {}
    if type(settings.resources[HealthResource.ID]) ~= "table" then
        settings.resources[HealthResource.ID] = { enabled = false }
    elseif settings.resources[HealthResource.ID].enabled == nil then
        settings.resources[HealthResource.ID].enabled = false
    end
    local health = settings.resources[HealthResource.ID]
    if health.showAbsorbs == nil then health.showAbsorbs = true end
    if health.showHealAbsorbs == nil then health.showHealAbsorbs = true end
    if health.showIncomingHeals == nil then health.showIncomingHeals = true end
    if health.showLowHealthAlert == nil then health.showLowHealthAlert = false end
    if health.healthLowHealthAlertMissingHealthOnly == nil then health.healthLowHealthAlertMissingHealthOnly = false end
    if type(health.healthAbsorbColor) ~= "table" then health.healthAbsorbColor = DEFAULT_HEALTH_ABSORB_COLOR end
    if type(health.healthHealAbsorbColor) ~= "table" then health.healthHealAbsorbColor = DEFAULT_HEALTH_HEAL_ABSORB_COLOR end
    if type(health.healthIncomingHealColor) ~= "table" then health.healthIncomingHealColor = DEFAULT_HEALTH_INCOMING_HEAL_COLOR end
    if type(health.healthLowHealthAlertColor) ~= "table" then health.healthLowHealthAlertColor = DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR end
    HealthResource.NormalizeEffectTexture(health, "healthAbsorbTexture")
    HealthResource.NormalizeEffectTexture(health, "healthHealAbsorbTexture")
    HealthResource.NormalizeEffectTexture(health, "healthIncomingHealTexture")
    HealthResource.NormalizeEffectTexture(health, "healthLowHealthAlertTexture")
    return settings.resources[HealthResource.ID]
end

function HealthResource.EnsureDisplaySettings(settings, specID)
    local base = HealthResource.EnsureSettings(settings)
    local health = SeedSpecResourceDisplaySettings(settings, HealthResource.ID, specID, RESOURCE_HEALTH_DISPLAY_KEYS)
    if not health then return base end
    if health.showAbsorbs == nil then health.showAbsorbs = base.showAbsorbs ~= false end
    if health.showHealAbsorbs == nil then health.showHealAbsorbs = base.showHealAbsorbs ~= false end
    if health.showIncomingHeals == nil then health.showIncomingHeals = base.showIncomingHeals ~= false end
    if health.showLowHealthAlert == nil then health.showLowHealthAlert = base.showLowHealthAlert == true end
    if health.healthLowHealthAlertMissingHealthOnly == nil then health.healthLowHealthAlertMissingHealthOnly = base.healthLowHealthAlertMissingHealthOnly == true end
    if type(health.healthAbsorbColor) ~= "table" then health.healthAbsorbColor = CopyTableValue(base.healthAbsorbColor or DEFAULT_HEALTH_ABSORB_COLOR) end
    if type(health.healthHealAbsorbColor) ~= "table" then health.healthHealAbsorbColor = CopyTableValue(base.healthHealAbsorbColor or DEFAULT_HEALTH_HEAL_ABSORB_COLOR) end
    if type(health.healthIncomingHealColor) ~= "table" then health.healthIncomingHealColor = CopyTableValue(base.healthIncomingHealColor or DEFAULT_HEALTH_INCOMING_HEAL_COLOR) end
    if type(health.healthLowHealthAlertColor) ~= "table" then health.healthLowHealthAlertColor = CopyTableValue(base.healthLowHealthAlertColor or DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR) end
    HealthResource.NormalizeEffectTexture(health, "healthAbsorbTexture")
    HealthResource.NormalizeEffectTexture(health, "healthHealAbsorbTexture")
    HealthResource.NormalizeEffectTexture(health, "healthIncomingHealTexture")
    HealthResource.NormalizeEffectTexture(health, "healthLowHealthAlertTexture")
    return health
end

function HealthResource.AddOpacitySlider(container, health, key, label, defaultValue, applyBars)
    local slider = AceGUI:Create("Slider")
    slider:SetLabel(label)
    slider:SetSliderValues(0, 1, 0.05)
    slider:SetIsPercent(true)
    slider:SetValue(tonumber(health[key]) or defaultValue)
    slider:SetFullWidth(true)
    slider:SetCallback("OnValueChanged", function(widget, event, val)
        health[key] = val
        applyBars()
    end)
    container:AddChild(slider)
end

function HealthResource.AddEffectTextureDropdown(container, health, key, label, applyBars)
    local drop = AceGUI:Create("Dropdown")
    drop:SetLabel(label)
    drop:SetList(HealthResource.GetEffectTextureOptions())
    drop:SetValue(health[key] or DEFAULT_HEALTH_EFFECT_TEXTURE)
    drop:SetFullWidth(true)
    drop:SetCallback("OnValueChanged", function(widget, event, val)
        health[key] = val or DEFAULT_HEALTH_EFFECT_TEXTURE
        applyBars()
    end)
    container:AddChild(drop)
end

function HealthResource.AddEffectStyleControls(container, checkbox, health, options, applyBars)
    local enabled = health[options.enabledKey] == true
    local expanded, advBtn = AddAdvancedToggle(checkbox, options.advancedKey, tabInfoButtons, enabled)
    if not (enabled and expanded) then
        return expanded, advBtn
    end

    AddColorPicker(container, health, options.colorKey, options.colorLabel, options.defaultColor, true, applyBars, applyBars)
    HealthResource.AddEffectTextureDropdown(container, health, options.textureKey, options.textureLabel, applyBars)
    return expanded, advBtn
end

function HealthResource.BuildColorControls(container, settings, applyBars)
    local specID = GetCurrentConfigSpecID()
    if not specID then
        local label = AceGUI:Create("Label")
        label:SetText("Specialization data loading...")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end
    local health = HealthResource.EnsureDisplaySettings(settings, specID)
    local fillGradientEnabled = health.healthBarGradient
    if fillGradientEnabled == nil then
        fillGradientEnabled = DEFAULT_HEALTH_BAR_GRADIENT
    end
    local gradientEnabled = health.healthBackgroundGradient
    if gradientEnabled == nil then
        gradientEnabled = DEFAULT_HEALTH_BACKGROUND_GRADIENT
    end

    local fillHeading = AceGUI:Create("Heading")
    fillHeading:SetText("Health")
    ColorHeading(fillHeading)
    fillHeading:SetFullWidth(true)
    container:AddChild(fillHeading)
    local healthFillKey = "rb_health_fill"
    local healthFillCollapsed = resourceBarCollapsedSections[healthFillKey]
    AttachCollapseButton(fillHeading, healthFillCollapsed, function()
        resourceBarCollapsedSections[healthFillKey] = not resourceBarCollapsedSections[healthFillKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not healthFillCollapsed then
        local fillGradientCb = AceGUI:Create("CheckBox")
        fillGradientCb:SetLabel("Use Health Gradient")
        fillGradientCb:SetValue(fillGradientEnabled == true)
        fillGradientCb:SetFullWidth(true)
        fillGradientCb:SetCallback("OnValueChanged", function(widget, event, val)
            health.healthBarGradient = val == true
            applyBars()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(fillGradientCb)

        if fillGradientEnabled == true then
            AddColorPicker(container, health, "healthBarFullColor", "Full Health", DEFAULT_HEALTH_BAR_FULL_COLOR, false, applyBars, applyBars)
            AddColorPicker(container, health, "healthBarHalfColor", "Half Health", DEFAULT_HEALTH_BAR_HALF_COLOR, false, applyBars, applyBars)
            AddColorPicker(container, health, "healthBarLowColor", "Low Health", DEFAULT_HEALTH_BAR_LOW_COLOR, false, applyBars, applyBars)
        else
            AddColorPicker(container, health, "healthBarColor", "Health Color", DEFAULT_HEALTH_BAR_COLOR, false, applyBars, applyBars)
        end
        HealthResource.AddOpacitySlider(container, health, "healthBarOpacity", "Health Opacity", DEFAULT_HEALTH_BAR_OPACITY, applyBars)
    end

    local missingHeading = AceGUI:Create("Heading")
    missingHeading:SetText("Missing Health")
    ColorHeading(missingHeading)
    missingHeading:SetFullWidth(true)
    container:AddChild(missingHeading)
    local healthMissingKey = "rb_health_missing"
    local healthMissingCollapsed = resourceBarCollapsedSections[healthMissingKey]
    local healthMissingCollapseBtn = AttachCollapseButton(missingHeading, healthMissingCollapsed, function()
        resourceBarCollapsedSections[healthMissingKey] = not resourceBarCollapsedSections[healthMissingKey]
        CooldownCompanion:RefreshConfigPanel()
    end)
    local missingInfoBtn = CreateInfoButton(missingHeading.frame, healthMissingCollapseBtn, "LEFT", "RIGHT", 4, 0, {
        "Missing Health",
        {"Resource Background Color is used by regular resource bars. Health uses Missing Health for its empty region.", 1, 1, 1, true},
    }, missingHeading)
    missingHeading.right:ClearAllPoints()
    missingHeading.right:SetPoint("RIGHT", missingHeading.frame, "RIGHT", -3, 0)
    missingHeading.right:SetPoint("LEFT", missingInfoBtn, "RIGHT", 4, 0)

    if not healthMissingCollapsed then
        local bgGradientCb = AceGUI:Create("CheckBox")
        bgGradientCb:SetLabel("Use Missing Health Gradient")
        bgGradientCb:SetValue(gradientEnabled == true)
        bgGradientCb:SetFullWidth(true)
        bgGradientCb:SetCallback("OnValueChanged", function(widget, event, val)
            health.healthBackgroundGradient = val == true
            applyBars()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(bgGradientCb)

        if gradientEnabled == true then
            AddColorPicker(container, health, "healthBackgroundFullColor", "Missing Health Full", DEFAULT_HEALTH_BACKGROUND_FULL_COLOR, false, applyBars, applyBars)
            AddColorPicker(container, health, "healthBackgroundHalfColor", "Missing Health Half", DEFAULT_HEALTH_BACKGROUND_HALF_COLOR, false, applyBars, applyBars)
            AddColorPicker(container, health, "healthBackgroundLowColor", "Missing Health Low", DEFAULT_HEALTH_BACKGROUND_LOW_COLOR, false, applyBars, applyBars)
        else
            AddColorPicker(container, health, "healthBackgroundColor", "Missing Health Color", DEFAULT_HEALTH_BACKGROUND_COLOR, false, applyBars, applyBars)
        end

        HealthResource.AddOpacitySlider(container, health, "healthBackgroundOpacity", "Missing Health Opacity", DEFAULT_HEALTH_BACKGROUND_OPACITY, applyBars)
    end

    local effectsHeading = AceGUI:Create("Heading")
    effectsHeading:SetText("Health Effects")
    ColorHeading(effectsHeading)
    effectsHeading:SetFullWidth(true)
    container:AddChild(effectsHeading)
    local healthEffectsKey = "rb_health_effects"
    local healthEffectsCollapsed = resourceBarCollapsedSections[healthEffectsKey]
    AttachCollapseButton(effectsHeading, healthEffectsCollapsed, function()
        resourceBarCollapsedSections[healthEffectsKey] = not resourceBarCollapsedSections[healthEffectsKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if healthEffectsCollapsed then
        return
    end

    local absorbsCb = AceGUI:Create("CheckBox")
    absorbsCb:SetLabel("Show Absorbs")
    absorbsCb:SetValue(health.showAbsorbs == true)
    absorbsCb:SetFullWidth(true)
    absorbsCb:SetCallback("OnValueChanged", function(widget, event, val)
        health.showAbsorbs = val == true
        applyBars()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(absorbsCb)
    HealthResource.AddEffectStyleControls(container, absorbsCb, health, {
        enabledKey = "showAbsorbs",
        advancedKey = "healthAbsorbs",
        colorKey = "healthAbsorbColor",
        textureKey = "healthAbsorbTexture",
        colorLabel = "Absorb Color",
        textureLabel = "Absorb Texture",
        defaultColor = DEFAULT_HEALTH_ABSORB_COLOR,
    }, applyBars)

    local healAbsorbsCb = AceGUI:Create("CheckBox")
    healAbsorbsCb:SetLabel("Show Healing Absorbs")
    healAbsorbsCb:SetValue(health.showHealAbsorbs == true)
    healAbsorbsCb:SetFullWidth(true)
    healAbsorbsCb:SetCallback("OnValueChanged", function(widget, event, val)
        health.showHealAbsorbs = val == true
        applyBars()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(healAbsorbsCb)
    HealthResource.AddEffectStyleControls(container, healAbsorbsCb, health, {
        enabledKey = "showHealAbsorbs",
        advancedKey = "healthHealAbsorbs",
        colorKey = "healthHealAbsorbColor",
        textureKey = "healthHealAbsorbTexture",
        colorLabel = "Healing Absorb Color",
        textureLabel = "Healing Absorb Texture",
        defaultColor = DEFAULT_HEALTH_HEAL_ABSORB_COLOR,
    }, applyBars)

    local incomingHealsCb = AceGUI:Create("CheckBox")
    incomingHealsCb:SetLabel("Show Incoming Heals")
    incomingHealsCb:SetValue(health.showIncomingHeals == true)
    incomingHealsCb:SetFullWidth(true)
    incomingHealsCb:SetCallback("OnValueChanged", function(widget, event, val)
        health.showIncomingHeals = val == true
        applyBars()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(incomingHealsCb)
    HealthResource.AddEffectStyleControls(container, incomingHealsCb, health, {
        enabledKey = "showIncomingHeals",
        advancedKey = "healthIncomingHeals",
        colorKey = "healthIncomingHealColor",
        textureKey = "healthIncomingHealTexture",
        colorLabel = "Incoming Heal Color",
        textureLabel = "Incoming Heal Texture",
        defaultColor = DEFAULT_HEALTH_INCOMING_HEAL_COLOR,
    }, applyBars)

    local lowHealthAlertCb = AceGUI:Create("CheckBox")
    lowHealthAlertCb:SetLabel("Show Low Health Alert")
    lowHealthAlertCb:SetValue(health.showLowHealthAlert == true)
    lowHealthAlertCb:SetFullWidth(true)
    lowHealthAlertCb:SetCallback("OnValueChanged", function(widget, event, val)
        health.showLowHealthAlert = val == true
        applyBars()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(lowHealthAlertCb)
    local lowHealthAlertAdvancedExpanded, lowHealthAlertAdvancedBtn = HealthResource.AddEffectStyleControls(container, lowHealthAlertCb, health, {
        enabledKey = "showLowHealthAlert",
        advancedKey = "healthLowHealthAlert",
        colorKey = "healthLowHealthAlertColor",
        textureKey = "healthLowHealthAlertTexture",
        colorLabel = "Low Health Alert Color",
        textureLabel = "Low Health Alert Texture",
        defaultColor = DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR,
    }, applyBars)
    local lowHealthAlertInfoAnchor = lowHealthAlertAdvancedBtn
    local lowHealthAlertInfoOffset = 4
    if not (lowHealthAlertInfoAnchor and lowHealthAlertInfoAnchor:IsShown()) then
        lowHealthAlertInfoAnchor = lowHealthAlertCb.checkbg
        lowHealthAlertInfoOffset = lowHealthAlertCb.text:GetStringWidth() + 4
    end
    CreateInfoButton(lowHealthAlertCb.frame, lowHealthAlertInfoAnchor, "LEFT", "RIGHT", lowHealthAlertInfoOffset, 0, {
        "Low Health Alert",
        {"Blizzard sets the low-health threshold to 35%. This cannot be configured.", 1, 1, 1, true},
    }, lowHealthAlertCb)
    if health.showLowHealthAlert == true and lowHealthAlertAdvancedExpanded then
        local missingHealthOnlyCb = AceGUI:Create("CheckBox")
        missingHealthOnlyCb:SetLabel("Pulse Missing Health Only")
        missingHealthOnlyCb:SetValue(health.healthLowHealthAlertMissingHealthOnly == true)
        missingHealthOnlyCb:SetFullWidth(true)
        missingHealthOnlyCb:SetCallback("OnValueChanged", function(widget, event, val)
            health.healthLowHealthAlertMissingHealthOnly = val == true
            applyBars()
        end)
        ApplyCheckboxIndent(missingHealthOnlyCb, 20)
        container:AddChild(missingHealthOnlyCb)
    end

    if AddPreviewToggleButton then
        AddPreviewToggleButton(container, "Preview Absorbs", function()
            return CooldownCompanion:IsHealthEffectPreviewActive("absorbs")
        end, function(show)
            CooldownCompanion:SetHealthEffectPreview("absorbs", show)
        end)

        AddPreviewToggleButton(container, "Preview Heal Absorbs", function()
            return CooldownCompanion:IsHealthEffectPreviewActive("healAbsorbs")
        end, function(show)
            CooldownCompanion:SetHealthEffectPreview("healAbsorbs", show)
        end)

        AddPreviewToggleButton(container, "Preview Incoming Heals", function()
            return CooldownCompanion:IsHealthEffectPreviewActive("incomingHeals")
        end, function(show)
            CooldownCompanion:SetHealthEffectPreview("incomingHeals", show)
        end)

        AddPreviewToggleButton(container, "Preview Low Health Alert", function()
            return CooldownCompanion:IsHealthEffectPreviewActive("lowHealthAlert")
        end, function(show)
            CooldownCompanion:SetHealthEffectPreview("lowHealthAlert", show)
        end)
    end
end

CS.healthResourceUI = HealthResource

local function AddResourceSpecCopyButton(enableCb, characterCopyButton)
    local _, initialSpecOrder, currentSpecID = CooldownCompanion:GetResourceBarSpecCopyOptions()
    if not currentSpecID or #initialSpecOrder == 0 then
        return
    end

    local btn = resourceSpecCopyButton
    if not btn then
        btn = CreateFrame("Button", nil, enableCb.frame)
        btn:SetSize(16, 16)

        local icon = btn:CreateTexture(nil, "OVERLAY")
        icon:SetSize(14, 14)
        icon:SetPoint("CENTER")
        icon:SetAtlas("BattleBar-SwapPetIcon", false)
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.2, 0.45, 1.0)
        btn.icon = icon

        resourceSpecCopyButton = btn
    else
        btn:SetParent(enableCb.frame)
    end

    btn:ClearAllPoints()
    if characterCopyButton then
        btn:SetPoint("LEFT", characterCopyButton, "RIGHT", 2, 0)
    else
        btn:SetPoint("LEFT", enableCb.checkbg, "RIGHT", enableCb.text:GetStringWidth() + 4, 0)
    end
    btn:Show()

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Copy From Another Spec")
        GameTooltip:AddLine("Copies Column 2 tab settings from another spec into your current spec.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("What is copied:", 1, 0.82, 0, true)
        GameTooltip:AddLine("- Styling tab", 1, 1, 1, true)
        GameTooltip:AddLine("- Layout tab", 1, 1, 1, true)
        GameTooltip:AddLine("- Colors tab settings that apply to the current spec", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("What is not copied:", 1, 0.82, 0, true)
        GameTooltip:AddLine("- Health settings", 1, 1, 1, true)
        GameTooltip:AddLine("- Custom Bars", 1, 1, 1, true)
        GameTooltip:AddLine("- Aura overlays", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function()
        if not resourceSpecCopyMenu then
            resourceSpecCopyMenu = CreateFrame("Frame", "CDCResourceSpecCopyMenu", UIParent, "UIDropDownMenuTemplate")
        end

        local specValues, specOrder, refreshedSpecID = CooldownCompanion:GetResourceBarSpecCopyOptions()
        if not refreshedSpecID or #specOrder == 0 then
            return
        end

        UIDropDownMenu_Initialize(resourceSpecCopyMenu, function(self, level)
            for _, sourceSpecID in ipairs(specOrder) do
                local sourceSpecName = specValues[sourceSpecID]
                local info = UIDropDownMenu_CreateInfo()
                info.text = sourceSpecName
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    if not ShowPopupAboveConfig then
                        CooldownCompanion:Print("Copy confirmation is unavailable.")
                        return
                    end
                    ShowPopupAboveConfig("CDC_CONFIRM_RESOURCE_SPEC_COPY", sourceSpecName, {
                        sourceSpecID = sourceSpecID,
                    })
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")

        resourceSpecCopyMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        ToggleDropDownMenu(1, nil, resourceSpecCopyMenu, "cursor", 0, 0)
    end)

    local prevOnRelease = enableCb.events and enableCb.events["OnRelease"]
    enableCb:SetCallback("OnRelease", function()
        if prevOnRelease then
            prevOnRelease(enableCb, "OnRelease")
        end
        btn:ClearAllPoints()
        btn:Hide()
    end)
end

local function BuildResourceBarAnchoringPanel(container)
    local db = CooldownCompanion.db.profile
    local settings = CooldownCompanion:GetResourceBarSettings()
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    local thicknessField, thicknessLabel = GetResourceThicknessFieldConfig(settings, layout)

    -- Enable Resource Bars
    local enableCb = AceGUI:Create("CheckBox")
    enableCb:SetLabel("Enable Resource Bars")
    enableCb:SetValue(settings.enabled)
    enableCb:SetFullWidth(true)
    enableCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.enabled = val
        CooldownCompanion:EvaluateResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(enableCb)

    local characterCopyButton = CreateCharacterCopyButton(enableCb, "resourceBars", "Resource Bars", function()
        CooldownCompanion:EvaluateResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    AddResourceSpecCopyButton(enableCb, characterCopyButton)

    if not settings.enabled then return end
    if not settings.resources then settings.resources = {} end

    if not layout then
        local label = AceGUI:Create("Label")
        label:SetText("Specialization data loading...")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    local isIndependentStack = layout.independentAnchorEnabled == true

    -- Preview toggle (ephemeral)
    local previewCb = AceGUI:Create("CheckBox")
    previewCb:SetLabel("Preview Resource Bars")
    previewCb:SetValue(CooldownCompanion:IsResourceBarPreviewActive())
    previewCb:SetFullWidth(true)
    previewCb:SetCallback("OnValueChanged", function(widget, event, val)
        if val then
            CooldownCompanion:ClearAllConfigPreviews()
            CooldownCompanion:StartResourceBarPreview()
        else
            CooldownCompanion:StopResourceBarPreview()
        end
        if RefreshConfigPanelForPreviewToggle then
            RefreshConfigPanelForPreviewToggle()
        end
    end)
    container:AddChild(previewCb)

    -- ============ Resource Toggles Section ============
    local toggleHeading = AceGUI:Create("Heading")
    toggleHeading:SetText("Resource Toggles")
    ColorHeading(toggleHeading)
    toggleHeading:SetFullWidth(true)
    container:AddChild(toggleHeading)

    local toggleKey = "rb_toggles"
    local toggleCollapsed = resourceBarCollapsedSections[toggleKey]

    AttachCollapseButton(toggleHeading, toggleCollapsed, function()
        resourceBarCollapsedSections[toggleKey] = not resourceBarCollapsedSections[toggleKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not toggleCollapsed then
        -- Only show mana toggle for classes that actually use mana
        local _, _, classID = UnitClass("player")
        local NO_MANA_CLASSES = { [1] = true, [3] = true, [4] = true, [6] = true, [12] = true }
        if classID and not NO_MANA_CLASSES[classID] then
            local manaCb = AceGUI:Create("CheckBox")
            manaCb:SetLabel("Hide Mana for Non-Healer Specs")
            manaCb:SetValue(settings.hideManaForNonHealer ~= false)
            manaCb:SetFullWidth(true)
            manaCb:SetCallback("OnValueChanged", function(widget, event, val)
                settings.hideManaForNonHealer = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(manaCb)
        end

        -- Per-resource enable/disable
        local rbHeightAdvBtns = {}
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            local name = POWER_NAMES[pt] or ("Power " .. pt)
            if pt == HealthResource.ID then
                HealthResource.EnsureSettings(settings)
            elseif not settings.resources[pt] then
                settings.resources[pt] = {}
            end
            local enabled = pt == HealthResource.ID
                and settings.resources[pt].enabled == true
                or settings.resources[pt].enabled ~= false

            local resCb = AceGUI:Create("CheckBox")
            resCb:SetLabel("Show " .. name)
            resCb:SetValue(enabled)
            resCb:SetFullWidth(true)
            resCb:SetCallback("OnValueChanged", function(widget, event, val)
                if not settings.resources[pt] then
                    settings.resources[pt] = {}
                end
                settings.resources[pt].enabled = val
                if pt == HealthResource.ID then
                    CS.resourceStylingTab = val and "health" or "bar_text"
                end
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(resCb)

            if layout.customBarHeights then
                local advExpanded = AddAdvancedToggle(resCb, "rbHeight_" .. pt, rbHeightAdvBtns, enabled)
                if advExpanded then
                    if type(layout.resources[pt]) ~= "table" then
                        layout.resources[pt] = {}
                    end
                    local resLayout = layout.resources[pt]
                    local resHeightSlider = AceGUI:Create("Slider")
                    resHeightSlider:SetLabel(thicknessLabel)
                    resHeightSlider:SetSliderValues(4, 40, 0.1)
                    if thicknessField == "barWidth" then
                        resHeightSlider:SetValue(
                            resLayout.barWidth or resLayout.barHeight
                            or layout.barWidth or layout.barHeight or settings.barWidth or settings.barHeight or 12
                        )
                    else
                        resHeightSlider:SetValue(
                            resLayout.barHeight or resLayout.barWidth
                            or layout.barHeight or layout.barWidth or settings.barHeight or settings.barWidth or 12
                        )
                    end
                    resHeightSlider:SetFullWidth(true)
                    local capturedPt = pt
                    resHeightSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        if not layout.resources[capturedPt] then
                            layout.resources[capturedPt] = {}
                        end
                        layout.resources[capturedPt][thicknessField] = val
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:RepositionCastBar()
                        CooldownCompanion:UpdateAnchorStacking()
                    end)
                    container:AddChild(resHeightSlider)
                end
            end
        end
    end

    -- ============ Alpha Section ============
    local group = db.groups[CS.selectedGroup]
    BuildAlphaControls(container, settings, function()
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RefreshConfigPanel()
    end, "rb_alpha", {
        isGlobal = group and group.isGlobal,
        disabled = not isIndependentStack and layout.inheritAlpha == true,
    })
end

------------------------------------------------------------------------

local function BuildResourceBarPositioningPanel(container)
    local settings = CooldownCompanion:GetResourceBarSettings()
    local layout = CooldownCompanion:GetSpecLayoutOrder()

    if not settings.enabled then
        local label = AceGUI:Create("Label")
        label:SetText("Enable Resource Bars to configure positioning.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    if not layout then
        local label = AceGUI:Create("Label")
        label:SetText("Specialization data loading...")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    local isVerticalLayout = IsResourceBarVerticalConfig(settings, layout)
    local gapField, gapLabel = GetResourceGapFieldConfig(settings, layout)
    local isIndependentStack = layout.independentAnchorEnabled == true

    -- Anchoring Mode dropdown
    local anchorModeDrop = AceGUI:Create("Dropdown")
    anchorModeDrop:SetLabel("Anchoring Mode")
    anchorModeDrop:SetList({
        attached = "Attached to Panel",
        independent = "Independent",
    }, { "attached", "independent" })
    anchorModeDrop:SetValue(isIndependentStack and "independent" or "attached")
    anchorModeDrop:SetFullWidth(true)
    anchorModeDrop:SetCallback("OnValueChanged", function(widget, event, val)
        layout.independentAnchorEnabled = (val == "independent")
        CooldownCompanion:EvaluateResourceBars()
        CooldownCompanion:RepositionCastBar()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(anchorModeDrop)

    -- Bar Orientation
    local orientDrop = AceGUI:Create("Dropdown")
    orientDrop:SetLabel("Bar Orientation")
    orientDrop:SetList({
        horizontal = "Horizontal",
        vertical = "Vertical",
    }, { "horizontal", "vertical" })
    orientDrop:SetValue(layout.orientation or settings.orientation or "horizontal")
    orientDrop:SetFullWidth(true)
    orientDrop:SetCallback("OnValueChanged", function(widget, event, val)
        layout.orientation = val
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RepositionCastBar()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(orientDrop)

    -- Vertical Fill Direction
    local fillDirDrop = AceGUI:Create("Dropdown")
    fillDirDrop:SetLabel("Vertical Fill Direction")
    fillDirDrop:SetList({
        bottom_to_top = "Bottom to Top",
        top_to_bottom = "Top to Bottom",
    }, { "bottom_to_top", "top_to_bottom" })
    fillDirDrop:SetValue(layout.verticalFillDirection or settings.verticalFillDirection or "bottom_to_top")
    fillDirDrop:SetDisabled(not isVerticalLayout)
    fillDirDrop:SetFullWidth(true)
    fillDirDrop:SetCallback("OnValueChanged", function(widget, event, val)
        layout.verticalFillDirection = val
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RepositionCastBar()
        CooldownCompanion:UpdateAnchorStacking()
    end)
    container:AddChild(fillDirDrop)

    -- Bar Spacing
    local spacingSlider = AceGUI:Create("Slider")
    spacingSlider:SetLabel("Bar Spacing")
    spacingSlider:SetSliderValues(0, 20, 0.1)
    spacingSlider:SetValue(layout.barSpacing or settings.barSpacing or 3.6)
    spacingSlider:SetFullWidth(true)
    spacingSlider:SetCallback("OnValueChanged", function(widget, event, val)
        layout.barSpacing = val
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RepositionCastBar()
        CooldownCompanion:UpdateAnchorStacking()
    end)
    container:AddChild(spacingSlider)

    -- Segment Gap
    local segGapSlider = AceGUI:Create("Slider")
    segGapSlider:SetLabel("Segment Gap")
    segGapSlider:SetSliderValues(0, 20, 0.1)
    segGapSlider:SetValue(layout.segmentGap or settings.segmentGap or 4)
    segGapSlider:SetFullWidth(true)
    segGapSlider:SetCallback("OnValueChanged", function(widget, event, val)
        layout.segmentGap = val
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(segGapSlider)

    -- Bar Height + Custom Heights
    ST._BuildBarHeightControls(container, settings, layout)

    -- ============ Anchor Settings (independent mode only) ============
    if isIndependentStack then
        local stackPosHeading = AceGUI:Create("Heading")
        stackPosHeading:SetText("Anchor Settings")
        ColorHeading(stackPosHeading)
        stackPosHeading:SetFullWidth(true)
        container:AddChild(stackPosHeading)

        local stackPosKey = "rb_stack_position"
        local stackPosCollapsed = resourceBarCollapsedSections[stackPosKey]

        AttachCollapseButton(stackPosHeading, stackPosCollapsed, function()
            resourceBarCollapsedSections[stackPosKey] = not resourceBarCollapsedSections[stackPosKey]
            CooldownCompanion:RefreshConfigPanel()
        end)

        if not stackPosCollapsed then
            EnsureResourceLayoutAnchor(settings, layout)
            local anchor = layout.independentAnchor

            local unlockCb = AceGUI:Create("CheckBox")
            unlockCb:SetLabel("Unlock Placement")
            unlockCb:SetValue(not layout.independentAnchorLocked)
            unlockCb:SetFullWidth(true)
            unlockCb:SetCallback("OnValueChanged", function(widget, event, val)
                layout.independentAnchorLocked = not val
                CooldownCompanion:ApplyResourceBars()
            end)
            container:AddChild(unlockCb)

            local widthSlider = AceGUI:Create("Slider")
            widthSlider:SetLabel("Bar Width")
            widthSlider:SetSliderValues(20, 600, 1)
            widthSlider:SetValue(layout.independentWidth or settings.independentWidth or 200)
            widthSlider:SetFullWidth(true)
            widthSlider:SetCallback("OnValueChanged", function(widget, event, val)
                layout.independentWidth = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            container:AddChild(widthSlider)

            local function refreshResourceBarAnchor()
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end

            BuildIndependentAnchorTargetRow(container, anchor, refreshResourceBarAnchor)

            AddAnchorDropdown(container, anchor, "point", "CENTER", refreshResourceBarAnchor, "Anchor Point")
            AddAnchorDropdown(container, anchor, "relativePoint", "CENTER", refreshResourceBarAnchor, "Relative Point")

            local xSlider = AceGUI:Create("Slider")
            xSlider:SetLabel("X Offset")
            xSlider:SetSliderValues(-2000, 2000, 0.1)
            xSlider:SetValue(anchor.x or 0)
            xSlider:SetFullWidth(true)
            xSlider:SetCallback("OnValueChanged", function(widget, event, val)
                anchor.x = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            HookSliderEditBox(xSlider)
            container:AddChild(xSlider)

            local ySlider = AceGUI:Create("Slider")
            ySlider:SetLabel("Y Offset")
            ySlider:SetSliderValues(-2000, 2000, 0.1)
            ySlider:SetValue(anchor.y or 0)
            ySlider:SetFullWidth(true)
            ySlider:SetCallback("OnValueChanged", function(widget, event, val)
                anchor.y = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            HookSliderEditBox(ySlider)
            container:AddChild(ySlider)
        end
    end

    -- ============ Layout Section (attached mode only) ============
    if not isIndependentStack then
        local posHeading = AceGUI:Create("Heading")
        posHeading:SetText("Layout")
        ColorHeading(posHeading)
        posHeading:SetFullWidth(true)
        container:AddChild(posHeading)

        local posKey = "rb_position"
        local posCollapsed = resourceBarCollapsedSections[posKey]

        AttachCollapseButton(posHeading, posCollapsed, function()
            resourceBarCollapsedSections[posKey] = not resourceBarCollapsedSections[posKey]
            CooldownCompanion:RefreshConfigPanel()
        end)

        if not posCollapsed then
            local gapSlider = AceGUI:Create("Slider")
            gapSlider:SetLabel(gapLabel)
            gapSlider:SetSliderValues(-100, 100, 0.1)
            if gapField == "verticalXOffset" then
                gapSlider:SetValue(layout.verticalXOffset or layout.yOffset or settings.verticalXOffset or settings.yOffset or 3)
            else
                gapSlider:SetValue(layout.yOffset or layout.verticalXOffset or settings.yOffset or settings.verticalXOffset or 3)
            end
            gapSlider:SetFullWidth(true)
            gapSlider:SetCallback("OnValueChanged", function(widget, event, val)
                layout[gapField] = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RepositionCastBar()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            container:AddChild(gapSlider)

            if ST._BuildAttachedCastBarOffsetControls then
                ST._BuildAttachedCastBarOffsetControls(container, layout)
            end
        end
    end

end

------------------------------------------------------------------------

local function GetResourceBarTextureOptions()
    local t = {}
    for _, name in ipairs(LSM:List("statusbar")) do
        t[name] = name
    end
    t["blizzard_class"] = "Blizzard (Class)"
    return t
end

-- Extracted to its own function to keep upvalue counts manageable in the caller.
local function BuildBarHeightControls(container, settings, layout)
    layout = layout or settings
    local thicknessField, thicknessLabel, customThicknessLabel = GetResourceThicknessFieldConfig(settings, layout)

    local hSlider = AceGUI:Create("Slider")
    hSlider:SetLabel(thicknessLabel)
    hSlider:SetSliderValues(4, 40, 0.1)
    if thicknessField == "barWidth" then
        hSlider:SetValue(layout.barWidth or layout.barHeight or settings.barWidth or settings.barHeight or 12)
    else
        hSlider:SetValue(layout.barHeight or layout.barWidth or settings.barHeight or settings.barWidth or 12)
    end
    hSlider:SetFullWidth(true)
    hSlider:SetCallback("OnValueChanged", function(widget, event, val)
        layout[thicknessField] = val
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RepositionCastBar()
        CooldownCompanion:UpdateAnchorStacking()
    end)
    hSlider:SetDisabled(layout.customBarHeights or false)
    container:AddChild(hSlider)

    if layout.independentAnchorEnabled ~= true then
        local inheritCb = AceGUI:Create("CheckBox")
        inheritCb:SetLabel("Inherit panel alpha")
        inheritCb:SetValue(layout.inheritAlpha)
        inheritCb:SetFullWidth(true)
        inheritCb:SetCallback("OnValueChanged", function(widget, event, val)
            layout.inheritAlpha = val == true
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(inheritCb)
    end

    local customHeightsCb = AceGUI:Create("CheckBox")
    customHeightsCb:SetLabel(customThicknessLabel)
    customHeightsCb:SetValue(layout.customBarHeights or false)
    customHeightsCb:SetFullWidth(true)
    customHeightsCb:SetCallback("OnValueChanged", function(widget, event, val)
        layout.customBarHeights = val
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RepositionCastBar()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(customHeightsCb)

    CreateInfoButton(customHeightsCb.frame, customHeightsCb.checkbg, "LEFT", "RIGHT", customHeightsCb.text:GetStringWidth() + 4, 0, {
        "Custom Resource Bar Heights",
        {"When enabled, each resource can have its own bar height. Click the advanced settings toggle for a resource in Column 1 to configure its individual height.", 1, 1, 1, true},
    }, customHeightsCb)
end

ST._BuildBarHeightControls = BuildBarHeightControls

local function BuildResourceBarStylingPanel(container, sectionMode)
    local settings = CooldownCompanion:GetResourceBarSettings()

    if not settings.enabled then
        local label = AceGUI:Create("Label")
        label:SetText("Enable Resource Bars to configure styling.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    local mode = sectionMode or "all"
    local showBarText = (mode == "all" or mode == "bar_text")
    local showColors = (mode == "all" or mode == "colors")
    local showHealthColors = (mode == "all" or mode == "health")
    local showAuraOverlays = (mode == "all" or mode == "colors") -- aura overlays merged into Colors tab

    local applyBars = function() CooldownCompanion:ApplyResourceBars() end
    local healthResourceID = -1 -- Keep aligned with RB.RESOURCE_HEALTH without adding an upvalue here.
    local displaySpecID = CS._GetCurrentConfigSpecID()
    local displayProfile = displaySpecID and CS._GetSpecResourceDisplayProfile(settings, displaySpecID) or nil
    if not displaySpecID or not displayProfile then
        local label = AceGUI:Create("Label")
        label:SetText("Specialization data loading...")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end
    local function isHealthTextFormat(textFormat)
        return textFormat == "percent"
            or textFormat == "percent_no_sign"
            or textFormat == "current"
            or textFormat == "current_max"
            or textFormat == "current_percent"
            or textFormat == "current_percent_no_sign"
    end

    if showBarText then
    -- Bar Texture
    local texDrop = AceGUI:Create("Dropdown")
    texDrop:SetLabel("Bar Texture")
    texDrop:SetList(GetResourceBarTextureOptions())
    texDrop:SetValue(displayProfile.barTexture or settings.barTexture or "Solid")
    texDrop:SetFullWidth(true)
    texDrop:SetCallback("OnValueChanged", function(widget, event, val)
        displayProfile.barTexture = val
        CooldownCompanion:ApplyResourceBars()
        -- Defer panel rebuild to next frame so it doesn't interfere with current callback
        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
    end)
    container:AddChild(texDrop)

    -- Brightness slider (only for Blizzard Class texture)
    if (displayProfile.barTexture or settings.barTexture) == "blizzard_class" then
        local brightSlider = AceGUI:Create("Slider")
        brightSlider:SetLabel("Class Texture Brightness")
        brightSlider:SetSliderValues(0.5, 2.0, 0.1)
        brightSlider:SetValue(displayProfile.classBarBrightness or settings.classBarBrightness or 1.3)
        brightSlider:SetFullWidth(true)
        brightSlider:SetCallback("OnValueChanged", function(widget, event, val)
            displayProfile.classBarBrightness = val
            CooldownCompanion:ApplyResourceBars()
        end)
        container:AddChild(brightSlider)
    end

    -- Resource Background Color
    AddColorPicker(container, displayProfile, "backgroundColor", "Resource Background Color", { 0, 0, 0, 0.5 }, true, applyBars)

    -- Border Style
    local borderDrop = AceGUI:Create("Dropdown")
    borderDrop:SetLabel("Border Style")
    borderDrop:SetList({
        pixel = "Pixel",
        none = "None",
    }, { "pixel", "none" })
    borderDrop:SetValue(displayProfile.borderStyle or settings.borderStyle or "pixel")
    borderDrop:SetFullWidth(true)
    borderDrop:SetCallback("OnValueChanged", function(widget, event, val)
        displayProfile.borderStyle = val
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(borderDrop)

    if (displayProfile.borderStyle or settings.borderStyle or "pixel") == "pixel" then
        AddColorPicker(container, displayProfile, "borderColor", "Border Color", { 0, 0, 0, 1 }, true, applyBars)

        local borderSizeSlider = AceGUI:Create("Slider")
        borderSizeSlider:SetLabel("Border Size")
        borderSizeSlider:SetSliderValues(0, 4, 0.1)
        borderSizeSlider:SetValue(displayProfile.borderSize or settings.borderSize or 1)
        borderSizeSlider:SetIsPercent(false)
        borderSizeSlider:SetFullWidth(true)
        borderSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            displayProfile.borderSize = val
            CooldownCompanion:ApplyResourceBars()
        end)
        container:AddChild(borderSizeSlider)
    end

    -- ============ Text Section ============
    local rbTextAdvBtns = {}

    local textHeading = AceGUI:Create("Heading")
    textHeading:SetText("Text")
    ColorHeading(textHeading)
    textHeading:SetFullWidth(true)
    container:AddChild(textHeading)

    local textKey = "rb_text"
    local textCollapsed = resourceBarCollapsedSections[textKey]

    local textCollapseBtn = AttachCollapseButton(textHeading, textCollapsed, function()
        resourceBarCollapsedSections[textKey] = not resourceBarCollapsedSections[textKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    textHeading.right:ClearAllPoints()
    textHeading.right:SetPoint("RIGHT", textHeading.frame, "RIGHT", -3, 0)
    textHeading.right:SetPoint("LEFT", textCollapseBtn, "RIGHT", 4, 0)

    if not textCollapsed then
        -- Per-resource "Show Text" checkboxes (continuous + segmented resources)
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            local capturedPt = pt
            local isHealthResource = capturedPt == healthResourceID
            local isSegmentedResource = (SEGMENTED_TYPES[capturedPt] == true) or (capturedPt == 100)
            if isHealthResource then
                CS.healthResourceUI.EnsureSettings(settings)
            elseif not settings.resources[capturedPt] then
                settings.resources[capturedPt] = {}
            end
            local baseSettings = settings.resources[capturedPt]
            local resSettings = CS._SeedSpecResourceDisplaySettings(settings, capturedPt, displaySpecID, CS._ResourceTextDisplayKeys) or baseSettings
            local name = POWER_NAMES[capturedPt] or ("Power " .. capturedPt)

            local showTextEnabled
            local showTextValue = CS._ReadResourceDisplaySetting(baseSettings, resSettings, "showText", nil)
            if isHealthResource or isSegmentedResource then
                -- Segmented resources and Health are off by default unless explicitly enabled.
                showTextEnabled = showTextValue == true
            else
                showTextEnabled = showTextValue ~= false
            end

            local cb = AceGUI:Create("CheckBox")
            cb:SetLabel("Show " .. name .. " Text")
            cb:SetValue(showTextEnabled)
            cb:SetFullWidth(true)
            cb:SetCallback("OnValueChanged", function(widget, event, val)
                if isHealthResource then
                    resSettings.showText = val and true or false
                    if not isHealthTextFormat(resSettings.textFormat) then
                        resSettings.textFormat = "percent"
                    end
                elseif isSegmentedResource then
                    resSettings.showText = val == true
                else
                    resSettings.showText = val == true
                end
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(cb)

            local advExpanded = AddAdvancedToggle(cb, "rbText_" .. capturedPt, rbTextAdvBtns, showTextEnabled)
            if advExpanded and showTextEnabled then
                local textFormatDrop = AceGUI:Create("Dropdown")
                textFormatDrop:SetLabel("Text Format")
                local textFormatOptions
                local textFormatOrder
                if isHealthResource then
                    textFormatOptions = {
                        percent = "Percent",
                        percent_no_sign = "Percent (No %)",
                        current = "Current Health",
                        current_max = "Current / Max Health",
                        current_percent = "Current + Percent",
                        current_percent_no_sign = "Current + Percent (No %)",
                    }
                    textFormatOrder = {
                        "percent",
                        "percent_no_sign",
                        "current",
                        "current_max",
                        "current_percent",
                        "current_percent_no_sign",
                    }
                elseif isSegmentedResource then
                    textFormatOptions = {
                        current = "Current Value",
                        current_max = "Current / Max",
                    }
                    textFormatOrder = { "current", "current_max" }
                else
                    textFormatOptions = {
                        current = "Current Value",
                        current_max = "Current / Max",
                        percent = "Percent",
                    }
                    textFormatOrder = { "current", "current_max", "percent" }
                end
                textFormatDrop:SetList(textFormatOptions, textFormatOrder)
                local textFormatValue = CS._ReadResourceDisplaySetting(baseSettings, resSettings, "textFormat", isHealthResource and "percent" or DEFAULT_RESOURCE_TEXT_FORMAT)
                if isHealthResource then
                    if not isHealthTextFormat(textFormatValue) then
                        textFormatValue = "percent"
                    end
                elseif isSegmentedResource then
                    if textFormatValue ~= "current" and textFormatValue ~= "current_max" then
                        textFormatValue = DEFAULT_RESOURCE_TEXT_FORMAT
                    end
                else
                    if textFormatValue ~= "current" and textFormatValue ~= "current_max" and textFormatValue ~= "percent" then
                        textFormatValue = DEFAULT_RESOURCE_TEXT_FORMAT
                    end
                end
                textFormatDrop:SetValue(textFormatValue)
                textFormatDrop:SetFullWidth(true)
                textFormatDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    if isHealthResource then
                        if isHealthTextFormat(val) then
                            resSettings.textFormat = val
                        else
                            resSettings.textFormat = "percent"
                        end
                    elseif isSegmentedResource then
                        if val == "current" or val == "current_max" then
                            resSettings.textFormat = val
                        else
                            resSettings.textFormat = DEFAULT_RESOURCE_TEXT_FORMAT
                        end
                    else
                        if val == "current" or val == "current_max" or val == "percent" then
                            resSettings.textFormat = val
                        else
                            resSettings.textFormat = DEFAULT_RESOURCE_TEXT_FORMAT
                        end
                    end
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(textFormatDrop)

                local fontDrop = AceGUI:Create("Dropdown")
                fontDrop:SetLabel("Font")
                CS.SetupFontDropdown(fontDrop)
                fontDrop:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "textFont", DEFAULT_RESOURCE_TEXT_FONT))
                fontDrop:SetFullWidth(true)
                fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    resSettings.textFont = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(fontDrop)

                local sizeDrop = AceGUI:Create("Slider")
                sizeDrop:SetLabel("Font Size")
                sizeDrop:SetSliderValues(6, 24, 1)
                sizeDrop:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "textFontSize", DEFAULT_RESOURCE_TEXT_SIZE))
                sizeDrop:SetFullWidth(true)
                sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    resSettings.textFontSize = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(sizeDrop)

                local outlineDrop = AceGUI:Create("Dropdown")
                outlineDrop:SetLabel("Outline")
                outlineDrop:SetList(CS.outlineOptions)
                outlineDrop:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "textFontOutline", DEFAULT_RESOURCE_TEXT_OUTLINE))
                outlineDrop:SetFullWidth(true)
                outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    resSettings.textFontOutline = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(outlineDrop)

                AddColorPicker(container, resSettings, "textFontColor", "Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, applyBars)

                local textAnchorDrop = AceGUI:Create("Dropdown")
                textAnchorDrop:SetLabel("Text Anchor")
                local textAnchorValues = {}
                for _, pt in ipairs(CS.anchorPoints) do
                    textAnchorValues[pt] = CS.anchorPointLabels[pt]
                end
                textAnchorDrop:SetList(textAnchorValues, CS.anchorPoints)
                textAnchorDrop:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "textAnchor", DEFAULT_RESOURCE_TEXT_ANCHOR))
                textAnchorDrop:SetFullWidth(true)
                textAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    resSettings.textAnchor = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(textAnchorDrop)

                local textXSlider = AceGUI:Create("Slider")
                textXSlider:SetLabel("Text X Offset")
                textXSlider:SetSliderValues(-50, 50, 0.1)
                textXSlider:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "textXOffset", DEFAULT_RESOURCE_TEXT_X_OFFSET))
                textXSlider:SetFullWidth(true)
                textXSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    resSettings.textXOffset = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(textXSlider)

                local textYSlider = AceGUI:Create("Slider")
                textYSlider:SetLabel("Text Y Offset")
                textYSlider:SetSliderValues(-50, 50, 0.1)
                textYSlider:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "textYOffset", DEFAULT_RESOURCE_TEXT_Y_OFFSET))
                textYSlider:SetFullWidth(true)
                textYSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    resSettings.textYOffset = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(textYSlider)

                if HIDE_AT_ZERO_ELIGIBLE[capturedPt] then
                    local hideAtZeroCb = AceGUI:Create("CheckBox")
                    hideAtZeroCb:SetLabel("Hide at 0")
                    hideAtZeroCb:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "hideTextAtZero", false) == true)
                    hideAtZeroCb:SetFullWidth(true)
                    hideAtZeroCb:SetCallback("OnValueChanged", function(widget, event, val)
                        resSettings.hideTextAtZero = val == true
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    container:AddChild(hideAtZeroCb)
                end
            end
        end
    end

    end

    if showHealthColors then
        local health = settings.resources and settings.resources[healthResourceID]
        if health and health.enabled == true then
            CS.healthResourceUI.BuildColorControls(container, settings, applyBars)
        elseif mode == "health" then
            local label = AceGUI:Create("Label")
            label:SetText("Enable Health to configure health colors.")
            label:SetFullWidth(true)
            container:AddChild(label)
        end
    end

    if showColors then
    -- ============ Per-Resource Colors Section ============
    local colorHeading = AceGUI:Create("Heading")
    colorHeading:SetText("Per-Resource Colors")
    ColorHeading(colorHeading)
    colorHeading:SetFullWidth(true)
    container:AddChild(colorHeading)

    local colorKey = "rb_colors"
    local colorCollapsed = resourceBarCollapsedSections[colorKey]

    local colorCollapseBtn = AttachCollapseButton(colorHeading, colorCollapsed, function()
        resourceBarCollapsedSections[colorKey] = not resourceBarCollapsedSections[colorKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    colorHeading.right:ClearAllPoints()
    colorHeading.right:SetPoint("RIGHT", colorHeading.frame, "RIGHT", -3, 0)
    colorHeading.right:SetPoint("LEFT", colorCollapseBtn, "RIGHT", 4, 0)

    local _colorSpecID = GetCurrentConfigSpecID()

    if not _colorSpecID and not colorCollapsed then
        local specUnavailLabel = AceGUI:Create("Label")
        specUnavailLabel:SetText("Specialization data not yet available.")
        specUnavailLabel:SetFullWidth(true)
        container:AddChild(specUnavailLabel)
    end

    if not colorCollapsed and _colorSpecID then
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            if not settings.resources[pt] then
                settings.resources[pt] = {}
            end

            if pt == healthResourceID then
                -- Health colors are rendered in the Health tab.
            elseif pt == 4 then
                -- Combo Points: two color pickers (normal vs at max)
                local _p4n = { comboColor = ReadSpecOverrideKey(settings, 4, _colorSpecID, "comboColor", DEFAULT_COMBO_COLOR) }
                AddColorPicker(container, _p4n, "comboColor", "Combo Points", DEFAULT_COMBO_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 4, _colorSpecID, "comboColor", _p4n.comboColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 4, _colorSpecID, "comboColor", _p4n.comboColor) end)

                local _p4m = { comboMaxColor = ReadSpecOverrideKey(settings, 4, _colorSpecID, "comboMaxColor", DEFAULT_COMBO_MAX_COLOR) }
                AddColorPicker(container, _p4m, "comboMaxColor", "Combo Points (Max)", DEFAULT_COMBO_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 4, _colorSpecID, "comboMaxColor", _p4m.comboMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 4, _colorSpecID, "comboMaxColor", _p4m.comboMaxColor) end)

                -- Charged combo point color (Rogue only)
                local _, _, classID = UnitClass("player")
                if classID == 4 then
                    local _p4c = { comboChargedColor = ReadSpecOverrideKey(settings, 4, _colorSpecID, "comboChargedColor", DEFAULT_COMBO_CHARGED_COLOR) }
                    AddColorPicker(container, _p4c, "comboChargedColor", "Combo Points (Charged)", DEFAULT_COMBO_CHARGED_COLOR, false,
                        function() WriteSpecOverrideKey(settings, 4, _colorSpecID, "comboChargedColor", _p4c.comboChargedColor); applyBars() end,
                        function() WriteSpecOverrideKey(settings, 4, _colorSpecID, "comboChargedColor", _p4c.comboChargedColor) end)
                end
            elseif pt == 5 then
                -- Runes: three color pickers (ready, recharging, max)
                local _p5r = { runeReadyColor = ReadSpecOverrideKey(settings, 5, _colorSpecID, "runeReadyColor", DEFAULT_RUNE_READY_COLOR) }
                AddColorPicker(container, _p5r, "runeReadyColor", "Runes (Ready)", DEFAULT_RUNE_READY_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 5, _colorSpecID, "runeReadyColor", _p5r.runeReadyColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 5, _colorSpecID, "runeReadyColor", _p5r.runeReadyColor) end)

                local _p5c = { runeRechargingColor = ReadSpecOverrideKey(settings, 5, _colorSpecID, "runeRechargingColor", DEFAULT_RUNE_RECHARGING_COLOR) }
                AddColorPicker(container, _p5c, "runeRechargingColor", "Runes (Recharging)", DEFAULT_RUNE_RECHARGING_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 5, _colorSpecID, "runeRechargingColor", _p5c.runeRechargingColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 5, _colorSpecID, "runeRechargingColor", _p5c.runeRechargingColor) end)

                local _p5m = { runeMaxColor = ReadSpecOverrideKey(settings, 5, _colorSpecID, "runeMaxColor", DEFAULT_RUNE_MAX_COLOR) }
                AddColorPicker(container, _p5m, "runeMaxColor", "Runes (All Ready)", DEFAULT_RUNE_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 5, _colorSpecID, "runeMaxColor", _p5m.runeMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 5, _colorSpecID, "runeMaxColor", _p5m.runeMaxColor) end)
            elseif pt == 7 then
                -- Soul Shards: three color pickers (ready, recharging, max)
                local _p7r = { shardReadyColor = ReadSpecOverrideKey(settings, 7, _colorSpecID, "shardReadyColor", DEFAULT_SHARD_READY_COLOR) }
                AddColorPicker(container, _p7r, "shardReadyColor", "Soul Shards (Ready)", DEFAULT_SHARD_READY_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 7, _colorSpecID, "shardReadyColor", _p7r.shardReadyColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 7, _colorSpecID, "shardReadyColor", _p7r.shardReadyColor) end)

                local _p7c = { shardRechargingColor = ReadSpecOverrideKey(settings, 7, _colorSpecID, "shardRechargingColor", DEFAULT_SHARD_RECHARGING_COLOR) }
                AddColorPicker(container, _p7c, "shardRechargingColor", "Soul Shards (Recharging)", DEFAULT_SHARD_RECHARGING_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 7, _colorSpecID, "shardRechargingColor", _p7c.shardRechargingColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 7, _colorSpecID, "shardRechargingColor", _p7c.shardRechargingColor) end)

                local _p7m = { shardMaxColor = ReadSpecOverrideKey(settings, 7, _colorSpecID, "shardMaxColor", DEFAULT_SHARD_MAX_COLOR) }
                AddColorPicker(container, _p7m, "shardMaxColor", "Soul Shards (Max)", DEFAULT_SHARD_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 7, _colorSpecID, "shardMaxColor", _p7m.shardMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 7, _colorSpecID, "shardMaxColor", _p7m.shardMaxColor) end)
            elseif pt == 9 then
                -- Holy Power: two color pickers (normal vs max)
                local _p9n = { holyColor = ReadSpecOverrideKey(settings, 9, _colorSpecID, "holyColor", DEFAULT_HOLY_COLOR) }
                AddColorPicker(container, _p9n, "holyColor", "Holy Power", DEFAULT_HOLY_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 9, _colorSpecID, "holyColor", _p9n.holyColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 9, _colorSpecID, "holyColor", _p9n.holyColor) end)

                local _p9m = { holyMaxColor = ReadSpecOverrideKey(settings, 9, _colorSpecID, "holyMaxColor", DEFAULT_HOLY_MAX_COLOR) }
                AddColorPicker(container, _p9m, "holyMaxColor", "Holy Power (Max)", DEFAULT_HOLY_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 9, _colorSpecID, "holyMaxColor", _p9m.holyMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 9, _colorSpecID, "holyMaxColor", _p9m.holyMaxColor) end)
            elseif pt == 12 then
                -- Chi: two color pickers (normal vs max)
                local _p12n = { chiColor = ReadSpecOverrideKey(settings, 12, _colorSpecID, "chiColor", DEFAULT_CHI_COLOR) }
                AddColorPicker(container, _p12n, "chiColor", "Chi", DEFAULT_CHI_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 12, _colorSpecID, "chiColor", _p12n.chiColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 12, _colorSpecID, "chiColor", _p12n.chiColor) end)

                local _p12m = { chiMaxColor = ReadSpecOverrideKey(settings, 12, _colorSpecID, "chiMaxColor", DEFAULT_CHI_MAX_COLOR) }
                AddColorPicker(container, _p12m, "chiMaxColor", "Chi (Max)", DEFAULT_CHI_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 12, _colorSpecID, "chiMaxColor", _p12m.chiMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 12, _colorSpecID, "chiMaxColor", _p12m.chiMaxColor) end)
            elseif pt == 16 then
                -- Arcane Charges: two color pickers (normal vs max)
                local _p16n = { arcaneColor = ReadSpecOverrideKey(settings, 16, _colorSpecID, "arcaneColor", DEFAULT_ARCANE_COLOR) }
                AddColorPicker(container, _p16n, "arcaneColor", "Arcane Charges", DEFAULT_ARCANE_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 16, _colorSpecID, "arcaneColor", _p16n.arcaneColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 16, _colorSpecID, "arcaneColor", _p16n.arcaneColor) end)

                local _p16m = { arcaneMaxColor = ReadSpecOverrideKey(settings, 16, _colorSpecID, "arcaneMaxColor", DEFAULT_ARCANE_MAX_COLOR) }
                AddColorPicker(container, _p16m, "arcaneMaxColor", "Arcane Charges (Max)", DEFAULT_ARCANE_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 16, _colorSpecID, "arcaneMaxColor", _p16m.arcaneMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 16, _colorSpecID, "arcaneMaxColor", _p16m.arcaneMaxColor) end)
            elseif pt == 19 then
                -- Essence: three color pickers (ready, recharging, max)
                local _p19r = { essenceReadyColor = ReadSpecOverrideKey(settings, 19, _colorSpecID, "essenceReadyColor", DEFAULT_ESSENCE_READY_COLOR) }
                AddColorPicker(container, _p19r, "essenceReadyColor", "Essence (Ready)", DEFAULT_ESSENCE_READY_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 19, _colorSpecID, "essenceReadyColor", _p19r.essenceReadyColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 19, _colorSpecID, "essenceReadyColor", _p19r.essenceReadyColor) end)

                local _p19c = { essenceRechargingColor = ReadSpecOverrideKey(settings, 19, _colorSpecID, "essenceRechargingColor", DEFAULT_ESSENCE_RECHARGING_COLOR) }
                AddColorPicker(container, _p19c, "essenceRechargingColor", "Essence (Recharging)", DEFAULT_ESSENCE_RECHARGING_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 19, _colorSpecID, "essenceRechargingColor", _p19c.essenceRechargingColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 19, _colorSpecID, "essenceRechargingColor", _p19c.essenceRechargingColor) end)

                local _p19m = { essenceMaxColor = ReadSpecOverrideKey(settings, 19, _colorSpecID, "essenceMaxColor", DEFAULT_ESSENCE_MAX_COLOR) }
                AddColorPicker(container, _p19m, "essenceMaxColor", "Essence (Max)", DEFAULT_ESSENCE_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 19, _colorSpecID, "essenceMaxColor", _p19m.essenceMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 19, _colorSpecID, "essenceMaxColor", _p19m.essenceMaxColor) end)
            elseif pt == 100 then
                -- Maelstrom Weapon: three color pickers (base, overlay, max)
                local _p100b = { mwBaseColor = ReadSpecOverrideKey(settings, 100, _colorSpecID, "mwBaseColor", DEFAULT_MW_BASE_COLOR) }
                AddColorPicker(container, _p100b, "mwBaseColor", "MW (Base)", DEFAULT_MW_BASE_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwBaseColor", _p100b.mwBaseColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwBaseColor", _p100b.mwBaseColor) end)

                local _p100o = { mwOverlayColor = ReadSpecOverrideKey(settings, 100, _colorSpecID, "mwOverlayColor", DEFAULT_MW_OVERLAY_COLOR) }
                AddColorPicker(container, _p100o, "mwOverlayColor", "MW (Overlay)", DEFAULT_MW_OVERLAY_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwOverlayColor", _p100o.mwOverlayColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwOverlayColor", _p100o.mwOverlayColor) end)

                local _p100m = { mwMaxColor = ReadSpecOverrideKey(settings, 100, _colorSpecID, "mwMaxColor", DEFAULT_MW_MAX_COLOR) }
                AddColorPicker(container, _p100m, "mwMaxColor", "MW (Max)", DEFAULT_MW_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwMaxColor", _p100m.mwMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwMaxColor", _p100m.mwMaxColor) end)
            elseif pt == 101 then
                -- Stagger: three color pickers (green/yellow/red thresholds)
                local _p101g = { staggerGreenColor = ReadSpecOverrideKey(settings, 101, _colorSpecID, "staggerGreenColor", { 0.52, 0.90, 0.52 }) }
                AddColorPicker(container, _p101g, "staggerGreenColor", "Stagger (Low)", { 0.52, 0.90, 0.52 }, false,
                    function() WriteSpecOverrideKey(settings, 101, _colorSpecID, "staggerGreenColor", _p101g.staggerGreenColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 101, _colorSpecID, "staggerGreenColor", _p101g.staggerGreenColor) end)

                local _p101y = { staggerYellowColor = ReadSpecOverrideKey(settings, 101, _colorSpecID, "staggerYellowColor", { 1.0, 0.85, 0.36 }) }
                AddColorPicker(container, _p101y, "staggerYellowColor", "Stagger (Medium)", { 1.0, 0.85, 0.36 }, false,
                    function() WriteSpecOverrideKey(settings, 101, _colorSpecID, "staggerYellowColor", _p101y.staggerYellowColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 101, _colorSpecID, "staggerYellowColor", _p101y.staggerYellowColor) end)

                local _p101r = { staggerRedColor = ReadSpecOverrideKey(settings, 101, _colorSpecID, "staggerRedColor", { 1.0, 0.42, 0.42 }) }
                AddColorPicker(container, _p101r, "staggerRedColor", "Stagger (High)", { 1.0, 0.42, 0.42 }, false,
                    function() WriteSpecOverrideKey(settings, 101, _colorSpecID, "staggerRedColor", _p101r.staggerRedColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 101, _colorSpecID, "staggerRedColor", _p101r.staggerRedColor) end)
            else
                local name = POWER_NAMES[pt] or ("Power " .. pt)

                if (displayProfile.barTexture or settings.barTexture) == "blizzard_class" and ST.POWER_ATLAS_TYPES and ST.POWER_ATLAS_TYPES[pt] then
                    -- Atlas-backed type; color picker not applicable
                else
                    local capturedGenericPt = pt
                    local _pGen = { color = ReadSpecOverrideKey(settings, pt, _colorSpecID, "color", DEFAULT_POWER_COLORS[pt] or { 1, 1, 1 }) }
                    AddColorPicker(container, _pGen, "color", name, DEFAULT_POWER_COLORS[pt] or { 1, 1, 1 }, false,
                        function() WriteSpecOverrideKey(settings, capturedGenericPt, _colorSpecID, "color", _pGen.color); applyBars() end,
                        function() WriteSpecOverrideKey(settings, capturedGenericPt, _colorSpecID, "color", _pGen.color) end)
                end
            end

        end
    end

    -- ============ Thresholds & Ticks Section ============
    local thresholdHeading = AceGUI:Create("Heading")
    thresholdHeading:SetText("Thresholds & Ticks")
    ColorHeading(thresholdHeading)
    thresholdHeading:SetFullWidth(true)
    container:AddChild(thresholdHeading)

    local thresholdKey = "rb_thresholds_ticks"
    local thresholdCollapsed = resourceBarCollapsedSections[thresholdKey]

    local thresholdCollapseBtn = AttachCollapseButton(thresholdHeading, thresholdCollapsed, function()
        resourceBarCollapsedSections[thresholdKey] = not resourceBarCollapsedSections[thresholdKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    local thresholdInfoBtn = CreateInfoButton(thresholdHeading.frame, thresholdCollapseBtn, "LEFT", "RIGHT", 4, 0, {
        "Thresholds & Ticks",
        {"Segmented resources: recolor when current value is at/above a configured threshold.", 1, 1, 1, true},
        " ",
        {"Continuous resources: draw a static marker by percent or absolute value.", 1, 1, 1, true},
    }, thresholdHeading)

    thresholdHeading.right:ClearAllPoints()
    thresholdHeading.right:SetPoint("RIGHT", thresholdHeading.frame, "RIGHT", -3, 0)
    thresholdHeading.right:SetPoint("LEFT", thresholdInfoBtn, "RIGHT", 4, 0)

    if not thresholdCollapsed then
        local rbThresholdTickAdvBtns = {}
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            if not settings.resources[pt] then
                settings.resources[pt] = {}
            end
            if settings.resources[pt].enabled ~= false then
                local resourceName = POWER_NAMES[pt] or ("Power " .. pt)
                local capturedPt = pt
                local res = settings.resources[capturedPt]
                local isSegmented = SEGMENTED_TYPES[capturedPt] == true or capturedPt == 100

                if isSegmented then
                    local thresholdAdvKey = "rbSegThreshold_" .. capturedPt
                    local thresholdEnableCb = AceGUI:Create("CheckBox")
                    thresholdEnableCb:SetLabel("Enable " .. resourceName .. " Threshold Color")
                    thresholdEnableCb:SetValue(ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdEnabled", false) == true)
                    thresholdEnableCb:SetFullWidth(true)
                    thresholdEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
                        local wasEnabled = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdEnabled", false) == true
                        WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdEnabled", val == true)
                        if val and not wasEnabled then
                            if type(CooldownCompanion.db.profile.showAdvanced) ~= "table" then
                                CooldownCompanion.db.profile.showAdvanced = {}
                            end
                            CooldownCompanion.db.profile.showAdvanced[thresholdAdvKey] = true
                        end
                        CooldownCompanion:ApplyResourceBars()
                        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
                    end)
                    container:AddChild(thresholdEnableCb)

                    local _segEnabled = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdEnabled", false) == true
                    local thresholdAdvExpanded = AddAdvancedToggle(
                        thresholdEnableCb,
                        thresholdAdvKey,
                        rbThresholdTickAdvBtns,
                        _segEnabled
                    )
                    if _segEnabled and thresholdAdvExpanded then
                        local thresholdEdit = AceGUI:Create("EditBox")
                        if thresholdEdit.editbox.Instructions then thresholdEdit.editbox.Instructions:Hide() end
                        thresholdEdit:SetLabel(resourceName .. " Threshold Value (>=)")
                        local _segVal = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdValue", nil)
                        thresholdEdit:SetText(tostring(GetSegmentedThresholdValueConfig({ segThresholdValue = _segVal })))
                        thresholdEdit:SetFullWidth(true)
                        thresholdEdit:DisableButton(true)
                        thresholdEdit:SetCallback("OnEnterPressed", function(widget, event, text)
                            local parsed = tonumber(text)
                            if not parsed then
                                local curVal = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdValue", nil)
                                widget:SetText(tostring(GetSegmentedThresholdValueConfig({ segThresholdValue = curVal })))
                                return
                            end
                            parsed = math.floor(parsed)
                            if parsed < 1 then
                                parsed = 1
                            elseif parsed > 99 then
                                parsed = 99
                            end
                            WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdValue", parsed)
                            widget:SetText(tostring(parsed))
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(thresholdEdit)

                        local _pSeg = { segThresholdColor = GetSafeRGBConfig(ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdColor", nil), DEFAULT_SEG_THRESHOLD_COLOR) }
                        AddColorPicker(container, _pSeg, "segThresholdColor", resourceName .. " Threshold Color", DEFAULT_SEG_THRESHOLD_COLOR, false,
                            function() WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdColor", _pSeg.segThresholdColor); applyBars() end,
                            function() WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdColor", _pSeg.segThresholdColor) end)
                    end
                elseif capturedPt ~= 101 and capturedPt ~= healthResourceID then
                    -- Stagger (101) and Health have dedicated coloring; tick markers not applicable
                    local tickAdvKey = "rbTickMarker_" .. capturedPt
                    local _tickEnabled = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickEnabled", false) == true
                    local tickEnableCb = AceGUI:Create("CheckBox")
                    tickEnableCb:SetLabel("Enable " .. resourceName .. " Tick Marker")
                    tickEnableCb:SetValue(_tickEnabled)
                    tickEnableCb:SetFullWidth(true)
                    tickEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
                        local wasEnabled = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickEnabled", false) == true
                        WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickEnabled", val == true)
                        if val and not wasEnabled then
                            if type(CooldownCompanion.db.profile.showAdvanced) ~= "table" then
                                CooldownCompanion.db.profile.showAdvanced = {}
                            end
                            CooldownCompanion.db.profile.showAdvanced[tickAdvKey] = true
                        end
                        CooldownCompanion:ApplyResourceBars()
                        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
                    end)
                    container:AddChild(tickEnableCb)

                    if _tickEnabled then
                        local tickCombatCb = AceGUI:Create("CheckBox")
                        tickCombatCb:SetLabel("Show Only In Combat")
                        tickCombatCb:SetValue(ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickCombatOnly", false))
                        tickCombatCb:SetFullWidth(true)
                        tickCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
                            WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickCombatOnly", val == true)
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(tickCombatCb)
                        ApplyCheckboxIndent(tickCombatCb, 20)
                    end

                    local tickAdvExpanded = AddAdvancedToggle(
                        tickEnableCb,
                        tickAdvKey,
                        rbThresholdTickAdvBtns,
                        _tickEnabled
                    )
                    if _tickEnabled and tickAdvExpanded then
                        local _tickModeRes = { continuousTickMode = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickMode", nil) }
                        local tickMode = GetContinuousTickModeConfig(_tickModeRes)
                        local modeDrop = AceGUI:Create("Dropdown")
                        modeDrop:SetLabel("Tick Mode")
                        modeDrop:SetList({
                            percent = "Percent",
                            absolute = "Absolute Value",
                        }, { "percent", "absolute" })
                        modeDrop:SetValue(tickMode)
                        modeDrop:SetFullWidth(true)
                        modeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            if val ~= "percent" and val ~= "absolute" then
                                val = DEFAULT_CONTINUOUS_TICK_MODE
                            end
                            WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickMode", val)
                            CooldownCompanion:ApplyResourceBars()
                            C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
                        end)
                        container:AddChild(modeDrop)

                        if tickMode == "percent" then
                            local _tickPercentRes = { continuousTickPercent = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickPercent", nil) }
                            local percentSlider = AceGUI:Create("Slider")
                            percentSlider:SetLabel(resourceName .. " Tick Percent")
                            percentSlider:SetSliderValues(0, 100, 1)
                            percentSlider:SetValue(GetContinuousTickPercentConfig(_tickPercentRes))
                            percentSlider:SetIsPercent(false)
                            percentSlider:SetFullWidth(true)
                            percentSlider:SetCallback("OnValueChanged", function(widget, event, val)
                                WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickPercent", val)
                                CooldownCompanion:ApplyResourceBars()
                            end)
                            container:AddChild(percentSlider)
                        else
                            local _tickAbsRes = { continuousTickAbsolute = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickAbsolute", nil) }
                            local absoluteEdit = AceGUI:Create("EditBox")
                            if absoluteEdit.editbox.Instructions then absoluteEdit.editbox.Instructions:Hide() end
                            absoluteEdit:SetLabel(resourceName .. " Tick Absolute Value")
                            absoluteEdit:SetText(tostring(GetContinuousTickAbsoluteConfig(_tickAbsRes)))
                            absoluteEdit:SetFullWidth(true)
                            absoluteEdit:DisableButton(true)
                            absoluteEdit:SetCallback("OnEnterPressed", function(widget, event, text)
                                local parsed = tonumber(text)
                                if not parsed then
                                    local curAbs = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickAbsolute", nil)
                                    widget:SetText(tostring(GetContinuousTickAbsoluteConfig({ continuousTickAbsolute = curAbs })))
                                    return
                                end
                                if parsed < 0 then
                                    parsed = 0
                                end
                                WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickAbsolute", parsed)
                                widget:SetText(tostring(parsed))
                                CooldownCompanion:ApplyResourceBars()
                            end)
                            container:AddChild(absoluteEdit)
                        end

                        local _tickColorResolved = GetSafeRGBAConfig(ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickColor", nil), DEFAULT_CONTINUOUS_TICK_COLOR)
                        if _tickColorResolved[4] == nil then _tickColorResolved = { _tickColorResolved[1], _tickColorResolved[2], _tickColorResolved[3], 1 } end
                        local _pTick = { continuousTickColor = _tickColorResolved }
                        AddColorPicker(container, _pTick, "continuousTickColor", resourceName .. " Tick Color", DEFAULT_CONTINUOUS_TICK_COLOR, true,
                            function() WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickColor", _pTick.continuousTickColor); applyBars() end,
                            function() WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickColor", _pTick.continuousTickColor) end)

                        local _tickWidthVal = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickWidth", nil)
                        local tickWidthSlider = AceGUI:Create("Slider")
                        tickWidthSlider:SetLabel(resourceName .. " Tick Width")
                        tickWidthSlider:SetSliderValues(1, 10, 1)
                        tickWidthSlider:SetValue(tonumber(_tickWidthVal) or DEFAULT_CONTINUOUS_TICK_WIDTH)
                        tickWidthSlider:SetFullWidth(true)
                        tickWidthSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickWidth", val)
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(tickWidthSlider)
                    end
                end
            end
        end
    end

    end

    if showAuraOverlays then
        BuildResourceAuraOverlaySection(container, settings)
    end

end

local function BuildResourceBarBarTextStylingPanel(container)
    BuildResourceBarStylingPanel(container, "bar_text")
end

local function BuildResourceBarColorsStylingPanel(container)
    BuildResourceBarStylingPanel(container, "colors")
end

local function BuildResourceBarHealthStylingPanel(container)
    BuildResourceBarStylingPanel(container, "health")
end

------------------------------------------------------------------------
-- Custom Bars detail panel
------------------------------------------------------------------------

local function ApplyCustomAuraBarPanelChanges(opts)
    CooldownCompanion:ApplyResourceBars()
    if opts and opts.updateAnchors then
        CooldownCompanion:UpdateAnchorStacking()
    end
    if opts and opts.refreshConfig then
        CooldownCompanion:RefreshConfigPanel()
    end
    if opts and opts.refreshLayoutPreview then
        RefreshLayoutOrderPreview()
    end
end

local function FindCustomBarIndexById(customBars, customBarId)
    if type(customBars) ~= "table" or type(customBarId) ~= "string" then
        return nil
    end
    for index, entry in ipairs(customBars) do
        if type(entry) == "table" and entry.customBarId == customBarId then
            return index
        end
    end
    return nil
end

local function EnsureCustomBarRowTextBadge(frame, key)
    local badge = frame[key]
    if not badge then
        badge = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame[key] = badge
    end
    badge:ClearAllPoints()
    badge:SetJustifyH("RIGHT")
    badge:SetJustifyV("MIDDLE")
    badge:Show()
    return badge
end

local function EnsureCustomBarRowIconBadge(frame, key, atlas)
    local badge = frame[key]
    if not badge then
        badge = CreateFrame("Button", nil, frame)
        badge:SetSize(16, 16)
        badge.icon = badge:CreateTexture(nil, "OVERLAY")
        badge.icon:SetAllPoints()
        badge:SetScript("OnEnter", function(self)
            if not self._cdcTooltipText then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(
                self._cdcTooltipText,
                self._cdcTooltipR or 1,
                self._cdcTooltipG or 1,
                self._cdcTooltipB or 1,
                true
            )
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        frame[key] = badge
    end

    badge:ClearAllPoints()
    badge:SetSize(16, 16)
    badge.icon:SetAtlas(atlas, false)
    badge.icon:SetVertexColor(1, 1, 1, 1)
    badge._cdcTooltipText = nil
    badge._cdcTooltipR, badge._cdcTooltipG, badge._cdcTooltipB = nil, nil, nil
    badge:SetFrameLevel(frame:GetFrameLevel() + 5)
    badge:Show()
    return badge
end

local function SetCustomBarRowBadgeTooltip(badge, text, r, g, b)
    badge._cdcTooltipText = text
    badge._cdcTooltipR = r or 1
    badge._cdcTooltipG = g or 1
    badge._cdcTooltipB = b or 1
end

local function StripCustomBarEntryTypeWords(text)
    if type(text) ~= "string" then
        return text
    end

    return text
        :gsub("%s*%(([%w%s]+)%)%s*$", function(kind)
            local normalized = kind and kind:lower():gsub("^%s+", ""):gsub("%s+$", "")
            if normalized == "buff" or normalized == "cooldown" or normalized == "aura" then
                return ""
            end
            return " (" .. kind .. ")"
        end)
        :gsub("%s+$", "")
end

local function GetCustomBarEntryTypeIcons(entry)
    if entry and entry.entryType == "spell" then
        local icons = "|A:ui_adv_atk:15:15|a"
        if entry.auraTracking == true then
            icons = icons .. " |A:ui_adv_health:15:15|a"
        end
        return icons
    end

    return "|A:ui_adv_health:15:15|a"
end

local function ResolveCustomBarAuraTrackingStatus(entry, resolvedAuraUnit)
    local spellID = tonumber(entry and entry.spellID)
    local cdmEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
    local isSpellEntry = entry and entry.entryType == "spell"
    local auraTrackingEnabled = true
    if isSpellEntry then
        auraTrackingEnabled = entry.auraTracking == true
    end
    local auraSpellID = tostring(spellID)
    if isSpellEntry then
        auraSpellID = entry and entry.auraSpellID or nil
    end
    local buttonData = spellID and {
        type = "spell",
        id = spellID,
        auraSpellID = auraSpellID,
        auraTracking = auraTrackingEnabled,
        auraUnit = resolvedAuraUnit,
    } or nil
    local viewerFrame = buttonData and CooldownCompanion:ResolveButtonAuraViewerFrame(buttonData) or nil

    return buttonData and CooldownCompanion:ResolveAuraTrackingConfigStatus(buttonData, cdmEnabled, viewerFrame)
        or { state = "noAssociatedAura", ready = false, cdmEnabled = cdmEnabled }
end

local function ConfigureCustomBarAddInstructions(addBox, placeholderText)
    local editFrame = addBox and addBox.editbox
    if not editFrame then
        return function() end
    end

    local instructions = editFrame._cdcCustomBarAddInstructions
    if not instructions then
        instructions = editFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        instructions:SetPoint("LEFT", editFrame, "LEFT", 6, 0)
        instructions:SetPoint("RIGHT", editFrame, "RIGHT", -6, 0)
        instructions:SetJustifyH("LEFT")
        instructions:SetTextColor(0.5, 0.5, 0.5)
        editFrame._cdcCustomBarAddInstructions = instructions
    end
    instructions:SetText(placeholderText)

    local function Update(text)
        instructions:SetShown((text or "") == "")
    end

    local prevOnRelease = addBox.events and addBox.events["OnRelease"]
    addBox:SetCallback("OnRelease", function(widget)
        if prevOnRelease then
            prevOnRelease(widget, "OnRelease")
        end
        instructions:Hide()
        instructions:SetText("")
    end)

    Update(editFrame:GetText())
    return Update
end

local function RemoveCustomBarById(customBars, customBarId)
    if type(customBars) ~= "table" or type(customBarId) ~= "string" then
        return false
    end

    for removeIndex, removeEntry in ipairs(customBars) do
        if type(removeEntry) == "table" and removeEntry.customBarId == customBarId then
            table.remove(customBars, removeIndex)
            return true
        end
    end
    return false
end

local function ClearCustomBarLayoutById(settings, specID, customBarId)
    if type(settings) ~= "table" or type(settings.layoutOrder) ~= "table" or type(customBarId) ~= "string" or not specID then
        return
    end

    specID = tonumber(specID) or specID
    local layout = settings.layoutOrder[specID]
    if type(layout) ~= "table" then
        local stringSpecID = tostring(specID)
        if stringSpecID ~= specID then
            layout = settings.layoutOrder[stringSpecID]
        end
    end

    if type(layout) == "table" and type(layout.customBars) == "table" then
        layout.customBars[customBarId] = nil
    end
end

local function ClearLegacyCustomAuraBarSeedForSpec(settings, specID)
    if type(settings) ~= "table" or type(settings.customAuraBars) ~= "table" or not specID then
        return
    end

    specID = tonumber(specID) or specID
    settings.customAuraBars[specID] = nil

    local stringSpecID = tostring(specID)
    if stringSpecID ~= specID then
        settings.customAuraBars[stringSpecID] = nil
    end

    local layout = type(settings.layoutOrder) == "table" and settings.layoutOrder[specID] or nil
    if type(layout) ~= "table" and stringSpecID ~= specID and type(settings.layoutOrder) == "table" then
        layout = settings.layoutOrder[stringSpecID]
    end
    if type(layout) == "table" then
        layout.customAuraBarSlots = nil
    end
end

local function DeleteCustomBarById(settings, specID, customBars, customBarId)
    if not RemoveCustomBarById(customBars, customBarId) then
        return false
    end

    ClearCustomBarLayoutById(settings, specID, customBarId)
    if #customBars == 0 then
        ClearLegacyCustomAuraBarSeedForSpec(settings, specID)
    end
    return true
end

local function DuplicateCustomBarById(settings, customBars, customBarId)
    local sourceIndex = FindCustomBarIndexById(customBars, customBarId)
    local sourceEntry = sourceIndex and customBars[sourceIndex]
    if type(settings) ~= "table" or type(sourceEntry) ~= "table" then
        return nil
    end

    local sourceLayout = GetCustomBarLayout(settings, nil, sourceEntry, false)
    local copy = CopyTable(sourceEntry)
    copy.customBarId = nil

    local newId = EnsureCustomBarId(settings, copy)
    if not newId then
        return nil
    end

    table.insert(customBars, sourceIndex + 1, copy)

    local targetLayout = EnsureCustomBarLayout(settings, nil, newId, 1000 + sourceIndex + 1)
    if type(sourceLayout) == "table" and type(targetLayout) == "table" then
        for key, value in pairs(sourceLayout) do
            targetLayout[key] = CopyTableValue(value)
        end
        if sourceLayout.order ~= nil then
            targetLayout.order = (tonumber(sourceLayout.order) or 1000) + 1
        end
        if sourceLayout.verticalOrder ~= nil then
            targetLayout.verticalOrder = (tonumber(sourceLayout.verticalOrder) or 1000) + 1
        end
    end

    return newId
end

local function HideCustomBarRowDecorations(frame)
    if not frame then return end
    if frame._cdcCustomBarTypeBadge then frame._cdcCustomBarTypeBadge:Hide() end
    if frame._cdcCustomBarAuraStatusBadge then frame._cdcCustomBarAuraStatusBadge:Hide() end
    if frame._cdcCustomBarDisabledBadge then frame._cdcCustomBarDisabledBadge:Hide() end
    if frame._cdcModeBadgeHitRect then frame._cdcModeBadgeHitRect:Hide() end
    if frame._cdcGenericRenameBadge then frame._cdcGenericRenameBadge:Hide() end
    if frame._cdcAddBtn then frame._cdcAddBtn:Hide() end
    if frame._cdcAnchorBadge then frame._cdcAnchorBadge:Hide() end
    if frame._cdcHeaderDisabledBadge then frame._cdcHeaderDisabledBadge:Hide() end
    if frame._cdcBadges then
        for _, badge in ipairs(frame._cdcBadges) do
            badge:Hide()
        end
    end
end

local function ClearCustomBarPreviewState()
    CooldownCompanion:ClearAllCustomAuraBarPreviews()
    if CS.customBarIndicatorPreviewActive then
        CooldownCompanion:StopResourceBarPreview()
    end
end

local function OpenCustomBarRowMenu(customBars, customBarId, entry)
    if not CS.customBarContextMenu then
        CS.customBarContextMenu = CreateFrame("Frame", "CDCCustomBarContextMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(CS.customBarContextMenu, function(_, level)
        if level ~= 1 then return end

        local toggleInfo = UIDropDownMenu_CreateInfo()
        toggleInfo.text = (entry.enabled == true) and "Disable" or "Enable"
        toggleInfo.notCheckable = true
        toggleInfo.func = function()
            CloseDropDownMenus()
            entry.enabled = entry.enabled ~= true
            if entry.enabled and not entry.trackingMode then
                entry.trackingMode = "active"
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end
        UIDropDownMenu_AddButton(toggleInfo, level)

        local duplicateInfo = UIDropDownMenu_CreateInfo()
        duplicateInfo.text = "Duplicate"
        duplicateInfo.notCheckable = true
        duplicateInfo.func = function()
            CloseDropDownMenus()
            local newId = DuplicateCustomBarById(CooldownCompanion:GetResourceBarSettings(), customBars, customBarId)
            if newId then
                ClearCustomBarPreviewState()
                CS.selectedCustomBarId = newId
                CS.customBarSettingsTab = "appearance"
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end
        UIDropDownMenu_AddButton(duplicateInfo, level)

        local removeInfo = UIDropDownMenu_CreateInfo()
        removeInfo.text = "Remove"
        removeInfo.notCheckable = true
        removeInfo.func = function()
            CloseDropDownMenus()
            local settings = CooldownCompanion:GetResourceBarSettings()
            local specID = GetCurrentConfigSpecID()
            if DeleteCustomBarById(settings, specID, customBars, customBarId) then
                if CS.selectedCustomBarId == customBarId then
                    ClearCustomBarPreviewState()
                    CS.selectedCustomBarId = nil
                    CS.customBarSettingsTab = "appearance"
                end
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end
        UIDropDownMenu_AddButton(removeInfo, level)
    end, "MENU")

    CS.customBarContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.customBarContextMenu, "cursor", 0, 0)
end

local function BuildSortedCustomBarSoundOptionOrder(soundOptions)
    local order = {}
    for optionKey in pairs(soundOptions or {}) do
        order[#order + 1] = optionKey
    end
    table.sort(order, function(a, b)
        if a == "None" then return true end
        if b == "None" then return false end
        local aLabel = soundOptions[a] or tostring(a)
        local bLabel = soundOptions[b] or tostring(b)
        if aLabel == bLabel then
            return tostring(a) < tostring(b)
        end
        return aLabel < bLabel
    end)
    return order
end

local function BuildCustomBarSoundAlertsTab(container, cab, infoButtons)
    local soundHeading = AceGUI:Create("Heading")
    soundHeading:SetText("Sound Alerts")
    ColorHeading(soundHeading)
    soundHeading:SetHeight(22)
    soundHeading:SetFullWidth(true)
    soundHeading.label:ClearAllPoints()
    soundHeading.label:SetPoint("CENTER", soundHeading.frame, "CENTER", 0, 2)
    soundHeading.left:ClearAllPoints()
    soundHeading.left:SetPoint("LEFT", soundHeading.frame, "LEFT", 3, 0)
    soundHeading.left:SetPoint("RIGHT", soundHeading.label, "LEFT", -5, 0)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundHeading.label, "RIGHT", 5, 0)
    container:AddChild(soundHeading)

    local soundInfoBtn = CreateInfoButton(soundHeading.frame, soundHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Sound Alerts",
        {"Sound alerts are played through the Master channel and follow your game's Master volume setting.", 1, 1, 1, true},
    }, infoButtons)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundInfoBtn, "RIGHT", 4, 0)

    local validEvents = CooldownCompanion:GetScopedValidSoundAlertEventsForCustomBar(cab)
    if not validEvents then
        local noEvents = AceGUI:Create("Label")
        noEvents:SetText("|cff888888No alertable sound events are available for this Custom Bar entry.|r")
        noEvents:SetFullWidth(true)
        container:AddChild(noEvents)
        return
    end

    local soundOptions = CooldownCompanion:GetSoundAlertOptions()
    local soundOptionOrder = BuildSortedCustomBarSoundOptionOrder(soundOptions)
    local eventOrder = CooldownCompanion:GetSoundAlertEventOrder()

    for _, eventKey in ipairs(eventOrder) do
        if validEvents[eventKey] then
            local soundDrop = AceGUI:Create("Dropdown")
            soundDrop:SetLabel(CooldownCompanion:GetCustomBarSoundAlertEventLabel(cab, eventKey))
            soundDrop:SetList(soundOptions, soundOptionOrder)
            soundDrop:SetValue(CooldownCompanion:GetCustomBarSoundAlertSelection(cab, eventKey))
            soundDrop:SetFullWidth(true)
            soundDrop:SetCallback("OnValueChanged", function(widget, event, val)
                CooldownCompanion:SetCustomBarSoundAlertEvent(cab, eventKey, val)
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(soundDrop)
        end
    end
end

local function BuildCustomBarLoadConditionsTab(container, cab, infoButtons)
    local addScopedLoadConditionToggles = ST._AddScopedLoadConditionToggles
    if type(addScopedLoadConditionToggles) ~= "function" then
        local unavailable = AceGUI:Create("Label")
        unavailable:SetText("|cff888888Load condition controls are not available yet.|r")
        unavailable:SetFullWidth(true)
        container:AddChild(unavailable)
        return
    end

    addScopedLoadConditionToggles(container, {
        target = cab,
        defaults = CooldownCompanion:GetLocalLoadConditionDefaults(),
        inheritedSources = {},
        headingText = "Hide This Entry In",
        headingTextWhenInherited = "Also Hide This Entry In",
        inheritedCollapsedKey = "loadconditions_custombar_inherited",
        localCollapsedKey = "loadconditions_custombar_local",
        preserveMissing = true,
        onChanged = function()
            if cab.loadConditions and not next(cab.loadConditions) then
                cab.loadConditions = nil
            end
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if CooldownCompanion:HasLocalLoadConditions(cab) then
        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear Entry Load Conditions")
        clearBtn:SetFullWidth(true)
        clearBtn:SetCallback("OnClick", function()
            cab.loadConditions = nil
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(clearBtn)
    end
end

local function AddCustomBarAuraTrackingGap(container)
    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    container:AddChild(spacer)
end

local function AddCustomBarSettingsHeading(container, text, infoButtons, tooltip)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

    if tooltip then
        local tooltipLines = { text }
        if type(tooltip) == "table" then
            for _, line in ipairs(tooltip) do
                tooltipLines[#tooltipLines + 1] = { line, 1, 1, 1, true }
            end
        else
            tooltipLines[#tooltipLines + 1] = { tooltip, 1, 1, 1, true }
        end
        local infoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
            unpack(tooltipLines)
        }, infoButtons)
        heading.right:ClearAllPoints()
        heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
        heading.right:SetPoint("LEFT", infoBtn, "RIGHT", 4, 0)
    end
end

local function BuildCustomBarAuraTrackingSection(container, cab, resolvedAuraUnit, infoButtons)
    local isSpellCustomBar = IsSpellCustomBarConfig(cab)
    local spellID = tonumber(cab and cab.spellID)
    if isSpellCustomBar and spellID and not (resolvedAuraUnit == "player" or resolvedAuraUnit == "target") then
        resolvedAuraUnit = EnsureCustomAuraBarAuraUnit(cab, spellID)
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText("Aura Tracking")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local infoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
        "Aura Tracking",
        {isSpellCustomBar and "Shows a tracked buff or debuff on top of this spell Custom Bar." or "Shows the tracked aura's remaining duration or stack state on this Custom Bar.", 1, 1, 1, true},
        " ",
        {isSpellCustomBar and "This follows the same Aura Tracking model used by spell entries in bar panels." or "Custom Bars keep their tracked aura identity in the entry row. This section shows whether that aura is ready to drive the bar.", 1, 1, 1, true},
        " ",
        "Requires:",
        {"- Blizzard Cooldown Manager (CDM) must be enabled.", 1, 1, 1, true},
        {"- In Edit Mode, the CDM Buffs/Debuffs visibility setting must be set to Always Visible.", 1, 1, 1, true},
        {"- The aura must be tracked in CDM as a Tracked Buff or Tracked Bar.", 1, 1, 1, true},
    }, infoButtons)
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", infoBtn, "RIGHT", 4, 0)

    local cdmEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
    local auraTrackingEnabled = true
    if isSpellCustomBar then
        auraTrackingEnabled = cab.auraTracking == true
    end
    local auraSpellID = tostring(spellID)
    if isSpellCustomBar then
        auraSpellID = cab.auraSpellID
    end
    local buttonData = spellID and {
            type = "spell",
            id = spellID,
            auraSpellID = auraSpellID,
            auraTracking = auraTrackingEnabled,
            auraUnit = resolvedAuraUnit,
        } or nil
    local viewerFrame = buttonData and CooldownCompanion:ResolveButtonAuraViewerFrame(buttonData) or nil
    local auraStatus = buttonData and CooldownCompanion:ResolveAuraTrackingConfigStatus(buttonData, cdmEnabled, viewerFrame)
        or { state = "noAssociatedAura", ready = false, cdmEnabled = cdmEnabled }
    local auraConfigReady = auraStatus.ready == true
    local inactiveColor = auraStatus.state == "associatedAuraNotTracked" and "|cffffff00" or "|cffff0000"

    local auraLabel = "Aura Tracking"
    auraLabel = auraLabel .. (auraConfigReady and ": |cff00ff00Active|r" or ": " .. inactiveColor .. "Inactive|r")

    if isSpellCustomBar then
        local auraCb = AceGUI:Create("CheckBox")
        auraCb:SetLabel(auraLabel)
        auraCb:SetValue(cab.auraTracking == true)
        auraCb:SetFullWidth(true)
        auraCb:SetCallback("OnValueChanged", function(_, _, value)
            cab.auraTracking = value and true or false
            if value then
                EnsureCustomAuraBarAuraUnit(cab, spellID)
            else
                CooldownCompanion:SetCustomAuraBarActivePreview(cab, false)
                CooldownCompanion:SetCustomAuraBarPandemicPreview(cab, false)
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end)
        container:AddChild(auraCb)

        if cab.auraTracking ~= true then
            AddCustomBarAuraTrackingGap(container)
            return
        end

        local auraEditBox = AceGUI:Create("EditBox")
        if auraEditBox.editbox.Instructions then
            auraEditBox.editbox.Instructions:Hide()
        end
        auraEditBox:SetLabel("Spell ID Override")
        auraEditBox:SetText(cab.auraSpellID and tostring(cab.auraSpellID) or "")
        auraEditBox:SetFullWidth(true)
        auraEditBox:SetCallback("OnEnterPressed", function(widget, _, text)
            text = text:gsub("%s", "")
            if text ~= "" then
                for token in text:gmatch("[^,]+") do
                    if not tonumber(token) then
                        CooldownCompanion:Print("Invalid spell ID: " .. token)
                        widget:SetText(cab.auraSpellID and tostring(cab.auraSpellID) or "")
                        return
                    end
                end
            end
            cab.auraSpellID = text ~= "" and text or nil
            EnsureCustomAuraBarAuraUnit(cab, spellID)
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end)
        container:AddChild(auraEditBox)

        CreateInfoButton(auraEditBox.frame, auraEditBox.frame, "TOPLEFT", "TOPLEFT", auraEditBox.label:GetStringWidth() + 4, -2, {
            "Spell ID Override",
            {"Most spells are tracked automatically, but some abilities apply a buff or debuff with a different spell ID than the ability itself. If tracking isn't working, enter the buff/debuff spell ID here. Use commas only when one entry should intentionally watch multiple IDs.\n\nUse \"Pick CDM\" below to visually select a spell from the Cooldown Manager.", 1, 1, 1, true},
        }, infoButtons)

        AddCustomBarAuraTrackingGap(container)

        if not (cab.auraUnit == "player" or cab.auraUnit == "target") then
            resolvedAuraUnit = EnsureCustomAuraBarAuraUnit(cab, spellID)
        end

        local auraUnitDrop = AceGUI:Create("Dropdown")
        auraUnitDrop:SetLabel("Aura Unit")
        auraUnitDrop:SetList({
            player = "Player",
            target = "Target",
        }, { "player", "target" })
        auraUnitDrop:SetValue((cab.auraUnitExplicit == true and cab.auraUnit) or resolvedAuraUnit or "player")
        auraUnitDrop:SetFullWidth(true)
        auraUnitDrop:SetCallback("OnValueChanged", function(_, _, value)
            if value ~= "player" and value ~= "target" then
                return
            end
            EnsureCustomAuraBarAuraUnit(cab, spellID, value)
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end)
        container:AddChild(auraUnitDrop)
        CreateInfoButton(auraUnitDrop.frame, auraUnitDrop.label, "LEFT", "RIGHT", 4, 0, {
            "Aura Unit",
            {"This controls where the tracked aura is expected to exist. Use Target for debuffs on your target, or Player for buffs/procs on yourself, even if the Custom Bar's spell is something else.", 1, 1, 1, true},
        }, infoButtons)

        AddCustomBarAuraTrackingGap(container)
    end

    local cdmToggleBtn = AceGUI:Create("Button")
    cdmToggleBtn:SetText(cdmEnabled and "Blizzard CDM: |cff00ff00Active|r" or "Blizzard CDM: |cffff0000Inactive|r")
    cdmToggleBtn:SetFullWidth(true)
    cdmToggleBtn:SetCallback("OnClick", function()
        local current = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
        C_CVar.SetCVar("cooldownViewerEnabled", current and "0" or "1")
        CooldownCompanion:RefreshConfigPanel()
        if not current then
            C_Timer.After(0.2, function()
                CooldownCompanion:BuildViewerAuraMap()
                CooldownCompanion:RefreshConfigPanel()
            end)
        end
    end)
    container:AddChild(cdmToggleBtn)

    local cdmRow = AceGUI:Create("SimpleGroup")
    cdmRow:SetFullWidth(true)
    cdmRow:SetLayout("Flow")

    local openCdmBtn = AceGUI:Create("Button")
    openCdmBtn:SetText("CDM Settings")
    openCdmBtn:SetRelativeWidth(isSpellCustomBar and 0.5 or 1.0)
    openCdmBtn:SetCallback("OnClick", function()
        if CooldownViewerSettings then
            CooldownViewerSettings:TogglePanel()
        end
    end)
    cdmRow:AddChild(openCdmBtn)

    if isSpellCustomBar then
        local pickCDMBtn = AceGUI:Create("Button")
        pickCDMBtn:SetText("Pick CDM")
        pickCDMBtn:SetRelativeWidth(0.5)
        pickCDMBtn:SetCallback("OnClick", function()
            CS.StartPickCDM(function(pickedSpellID)
                if CS.configFrame then
                    CS.configFrame.frame:Show()
                end
                if pickedSpellID then
                    cab.auraSpellID = tostring(pickedSpellID)
                    EnsureCustomAuraBarAuraUnit(cab, spellID)
                end
                ApplyCustomAuraBarPanelChanges({
                    updateAnchors = true,
                    refreshConfig = true,
                })
            end)
        end)
        pickCDMBtn:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
            GameTooltip:AddLine("Pick from Cooldown Manager")
            GameTooltip:AddLine("Shows a list of Tracked Buff/Tracked Bar auras currently tracked in the Cooldown Manager. Click one to populate the Spell ID Override.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        pickCDMBtn:SetCallback("OnLeave", function()
            GameTooltip:Hide()
        end)
        cdmRow:AddChild(pickCDMBtn)
    end
    container:AddChild(cdmRow)

    AddCustomBarAuraTrackingGap(container)

    local statusLabel = AceGUI:Create("Label")
    statusLabel:SetText(auraConfigReady and "|cff00ff00Aura tracking is active and ready.|r" or (inactiveColor .. "Aura tracking is not ready.|r"))
    statusLabel:SetFullWidth(true)
    statusLabel:SetJustifyH("CENTER")
    container:AddChild(statusLabel)
    AddCustomBarAuraTrackingGap(container)

    local explainText
    if auraStatus.state == "cdmDisabled" then
        explainText = "|cff888888Blizzard Cooldown Manager is disabled. Enable it above to allow aura tracking.|r"
    elseif auraStatus.state == "noAssociatedAura" then
        explainText = "|cff888888This aura was not found in Blizzard CDM's tracked buff or tracked bar data.|r"
    elseif auraStatus.state == "trackedAuraUnavailable" then
        explainText = "|cff888888This aura is tracked in Blizzard CDM, but its Buffs/Debuffs viewer is not currently readable. Set the CDM Buffs/Debuffs visibility to Always Visible.|r"
    elseif auraStatus.state == "associatedAuraNotTracked" then
        explainText = "|cff888888This aura was found, but it is not currently tracked in CDM as a Tracked Buff or Tracked Bar.|r"
    end

    if explainText then
        local explainLabel = AceGUI:Create("Label")
        explainLabel:SetText(explainText)
        explainLabel:SetFullWidth(true)
        container:AddChild(explainLabel)
        AddCustomBarAuraTrackingGap(container)
    end

end

local function BuildCustomBarVisibilityRulesSection(container, customBars, capturedIdx, cab, resolvedAuraUnit, capturedKey, infoButtons)
    if cab.hideWhenInactive == true and cab.hideWhileAuraActive == true then
        cab.hideWhileAuraActive = nil
        cab.hideAuraActiveExceptPandemic = nil
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText("Visibility Rules")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local visibilityKey = "cab_visibility_" .. tostring(capturedKey)
    local visibilityCollapsed = resourceBarCollapsedSections[visibilityKey]
    local collapseBtn = AttachCollapseButton(heading, visibilityCollapsed, function()
        resourceBarCollapsedSections[visibilityKey] = not resourceBarCollapsedSections[visibilityKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    local infoBtn = CreateInfoButton(heading.frame, collapseBtn, "LEFT", "RIGHT", 2, 0, {
        "Visibility Rules",
        {"Show or hide this Custom Bar based on whether its tracked aura is active.", 1, 1, 1, true},
    }, infoButtons)
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", infoBtn, "RIGHT", 4, 0)

    if visibilityCollapsed then
        return
    end

    local hideAuraCb = AceGUI:Create("CheckBox")
    hideAuraCb:SetLabel("Hide While Aura Active")
    hideAuraCb:SetValue(cab.hideWhileAuraActive == true)
    hideAuraCb:SetFullWidth(true)
    hideAuraCb:SetCallback("OnValueChanged", function(widget, event, val)
        customBars[capturedIdx].hideWhileAuraActive = val or nil
        if val then
            customBars[capturedIdx].hideWhenInactive = nil
        else
            customBars[capturedIdx].hideAuraActiveExceptPandemic = nil
        end
        ApplyCustomAuraBarPanelChanges({
            updateAnchors = true,
            refreshConfig = true,
        })
    end)
    container:AddChild(hideAuraCb)
    CreateInfoButton(hideAuraCb.frame, hideAuraCb.checkbg, "LEFT", "RIGHT", hideAuraCb.text:GetStringWidth() + 4, 0, {
        "Hide While Aura Active",
        {"Hides this Custom Bar while the tracked aura is currently active.", 1, 1, 1, true},
    }, infoButtons)

    if resolvedAuraUnit == "target" then
        local pandemicCb = AceGUI:Create("CheckBox")
        pandemicCb:SetLabel("Except in Pandemic")
        pandemicCb:SetValue(cab.hideAuraActiveExceptPandemic == true)
        pandemicCb:SetFullWidth(true)
        if cab.hideWhileAuraActive ~= true then
            pandemicCb:SetDisabled(true)
        end
        pandemicCb:SetCallback("OnValueChanged", function(widget, event, val)
            customBars[capturedIdx].hideAuraActiveExceptPandemic = val or nil
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end)
        container:AddChild(pandemicCb)
        ApplyCheckboxIndent(pandemicCb, 20)
        CreateInfoButton(pandemicCb.frame, pandemicCb.checkbg, "LEFT", "RIGHT", pandemicCb.text:GetStringWidth() + 4, 0, {
            "Except in Pandemic",
            {"Shows the bar during the pandemic window so you know when to reapply the target aura.", 1, 1, 1, true},
        }, infoButtons)
    end

    local hideNoAuraCb = AceGUI:Create("CheckBox")
    hideNoAuraCb:SetLabel("Hide While Aura Not Active")
    hideNoAuraCb:SetValue(cab.hideWhenInactive == true)
    hideNoAuraCb:SetFullWidth(true)
    hideNoAuraCb:SetCallback("OnValueChanged", function(widget, event, val)
        customBars[capturedIdx].hideWhenInactive = val or nil
        if val then
            customBars[capturedIdx].hideWhileAuraActive = nil
            customBars[capturedIdx].hideAuraActiveExceptPandemic = nil
        end
        ApplyCustomAuraBarPanelChanges({
            updateAnchors = true,
            refreshConfig = true,
        })
    end)
    container:AddChild(hideNoAuraCb)
    CreateInfoButton(hideNoAuraCb.frame, hideNoAuraCb.checkbg, "LEFT", "RIGHT", hideNoAuraCb.text:GetStringWidth() + 4, 0, {
        "Hide While Aura Not Active",
        {"Hides this Custom Bar until the tracked aura is active.", 1, 1, 1, true},
    }, infoButtons)
end

local function BuildCustomBarsListPanel(container)
    local settings = CooldownCompanion:GetResourceBarSettings()
    local customBars = CooldownCompanion:GetSpecCustomAuraBars()
    local selectedId = CS.selectedCustomBarId
    if selectedId and not FindCustomBarIndexById(customBars, selectedId) then
        CS.selectedCustomBarId = nil
        selectedId = nil
    end

    local addBox = AceGUI:Create("EditBox")
    if addBox.editbox.Instructions then addBox.editbox.Instructions:Hide() end
    addBox:SetLabel("")
    addBox:SetFullWidth(true)
    addBox:DisableButton(true)
    local updatePlaceholder = ConfigureCustomBarAddInstructions(addBox, "Add spell or aura by name or ID")

    local function GetCustomBarEntryTypeForAutocomplete(entry)
        if type(entry) ~= "table" then
            return "spell"
        end
        if entry.forceAura == true or entry.isPassive == true then
            return "aura"
        end
        if entry.forceAura == false then
            return "spell"
        end
        if IsPassiveOrProc and entry.id and IsPassiveOrProc(entry.id) then
            return "aura"
        end
        return "spell"
    end

    local function StripExplicitCustomBarEntryTypeSuffix(text)
        local cleaned = text and text:gsub("^%s+", ""):gsub("%s+$", ""):lower() or ""
        if cleaned:match("%s%((buff)%)$") or cleaned:match("%s%((aura)%)$") then
            return (text or ""):gsub("%s+%([Bb][Uu][Ff][Ff]%)%s*$", ""):gsub("%s+%([Aa][Uu][Rr][Aa]%)%s*$", ""), "aura"
        end
        if cleaned:match("%s%((cooldown)%)$") then
            return (text or ""):gsub("%s+%([Cc][Oo][Oo][Ll][Dd][Oo][Ww][Nn]%)%s*$", ""), "spell"
        end
        return text, nil
    end

    local function GetCustomBarEntryTypeForSpellID(spellId, explicitType)
        if explicitType then
            return explicitType
        end
        if not spellId or not C_Spell.GetSpellInfo(spellId) then
            return "aura"
        end
        local sawAuraEntry = false
        local sawSpellEntry = false
        local cache = BuildAuraBarAutocompleteCache and BuildAuraBarAutocompleteCache() or nil
        for _, entry in ipairs(cache or {}) do
            if entry.id == spellId then
                if GetCustomBarEntryTypeForAutocomplete(entry) == "aura" then
                    sawAuraEntry = true
                else
                    sawSpellEntry = true
                end
            end
        end
        if sawAuraEntry and not sawSpellEntry then
            return "aura"
        elseif sawSpellEntry and not sawAuraEntry then
            return "spell"
        end
        if IsPassiveOrProc and IsPassiveOrProc(spellId) then
            return "aura"
        end
        return "spell"
    end

    local function AddCustomBarFromSpell(spellId, labelOverride, entryType)
        if not spellId then return false end
        entryType = entryType == "aura" and "aura" or "spell"
        local entry = {
            entryType = entryType,
            enabled = true,
            spellID = spellId,
            label = labelOverride or GetAuraBarAutocompleteDisplayName(spellId) or C_Spell.GetSpellName(spellId) or "",
        }
        if entryType == "aura" then
            entry.trackingMode = "active"
            RefreshCustomAuraBarAuraUnitForSpell(entry, spellId)
        else
            local charges = C_Spell.GetSpellCharges(spellId)
            local maxCharges = charges and tonumber(charges.maxCharges)
            if maxCharges and maxCharges > 1 then
                entry.hasCharges = true
                entry.maxCharges = maxCharges
            end
        end
        local id = EnsureCustomBarId(settings, entry)
        customBars[#customBars + 1] = entry
        EnsureCustomBarLayout(settings, nil, id, 1000 + #customBars)
        CS.selectedCustomBarId = id
        ApplyCustomAuraBarPanelChanges({
            updateAnchors = true,
            refreshConfig = true,
        })
        return true
    end

    local function CommitCustomBarText(widget, text)
        local lookupText, explicitType = StripExplicitCustomBarEntryTypeSuffix(text)
        local autocompleteEntry = ResolveAuraBarAutocompleteEntry and (
            ResolveAuraBarAutocompleteEntry(text)
            or (lookupText ~= text and ResolveAuraBarAutocompleteEntry(lookupText))
        )
        if autocompleteEntry and AddCustomBarFromSpell(
            autocompleteEntry.id,
            GetAuraBarAutocompleteEntryName(autocompleteEntry),
            explicitType or GetCustomBarEntryTypeForAutocomplete(autocompleteEntry)
        ) then
            widget:SetText("")
            return true
        end

        local id, explicitClear = ResolveAuraColorSpellIDFromText(lookupText)
        if explicitClear then
            widget:SetText("")
            return true
        end
        if AddCustomBarFromSpell(id, nil, GetCustomBarEntryTypeForSpellID(id, explicitType)) then
            widget:SetText("")
            return true
        end

        local cleaned = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
        if cleaned ~= "" then
            CooldownCompanion:Print("Custom Bar spell or aura not found: " .. cleaned)
        end
        return false
    end

    local function onAuraBarSelect(entry)
        CS.HideAutocomplete()
        if entry and AddCustomBarFromSpell(
            entry.id,
            GetAuraBarAutocompleteEntryName(entry),
            GetCustomBarEntryTypeForAutocomplete(entry)
        ) then
            addBox._cdcCustomBarAutocompleteCommitted = true
            addBox:SetText("")
        end
    end

    addBox:SetCallback("OnTextChanged", function(widget, event, text)
        updatePlaceholder(text)
        ShowAuraBarAutocompleteResults(text, widget, onAuraBarSelect)
    end)
    addBox:SetCallback("OnEnterPressed", function(widget, event, text)
        if CS.ConsumeAutocompleteEnter then
            CS.ConsumeAutocompleteEnter()
        end
        if widget._cdcCustomBarAutocompleteCommitted then
            widget._cdcCustomBarAutocompleteCommitted = nil
            return
        end
        CS.HideAutocomplete()
        CommitCustomBarText(widget, text)
    end)
    CS.SetupAutocompleteKeyHandler(addBox)
    addBox.editbox:SetPoint("BOTTOMRIGHT", 1, 0)
    container:AddChild(addBox)

    local listHeading = AceGUI:Create("Heading")
    listHeading:SetText("Entries")
    ColorHeading(listHeading)
    listHeading:SetFullWidth(true)
    container:AddChild(listHeading)

    if #customBars == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetText("|cff888888No Custom Bars yet.|r")
        empty:SetFullWidth(true)
        container:AddChild(empty)
        return
    end

    for index, entry in ipairs(customBars) do
        local customBarId = EnsureCustomBarId(settings, entry)
        local spellName = entry.label
            or (entry.spellID and GetAuraBarAutocompleteDisplayName(entry.spellID))
            or (entry.spellID and C_Spell.GetSpellName(entry.spellID))
            or ("Custom Bar " .. tostring(index))
        local rowText = StripCustomBarEntryTypeWords(spellName)
        local typeIcons = GetCustomBarEntryTypeIcons(entry)
        if typeIcons and typeIcons ~= "" then
            rowText = (rowText or ("Custom Bar " .. tostring(index))) .. "  " .. typeIcons
        end
        local selected = customBarId == selectedId
        local icon = entry.spellID and (GetAuraBarAutocompleteDisplayIcon(entry.spellID) or C_Spell.GetSpellTexture(entry.spellID)) or 134400

        local row = AceGUI:Create("InteractiveLabel")
        if CleanRecycledEntry then CleanRecycledEntry(row) end
        HideCustomBarRowDecorations(row.frame)
        row:SetText(rowText)
        row:SetFullWidth(true)
        row:SetFontObject(GameFontHighlight)
        row:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        if row.frame and row.frame.RegisterForClicks then
            row.frame:RegisterForClicks("AnyUp")
        end
        if ApplyConfigRowIcon then
            ApplyConfigRowIcon(row, icon, { rightPad = 126 })
        elseif icon then
            row:SetImage(icon, 0.08, 0.92, 0.08, 0.92)
            row:SetImageSize(18, 18)
        end
        if selected then
            row:SetColor(0.4, 0.7, 1.0)
        elseif entry.enabled ~= true then
            row:SetColor(0.55, 0.55, 0.55)
        end

        local rowFrame = row.frame
        local isSpellCustomBar = IsSpellCustomBarConfig(entry)
        local resolvedRowAuraUnit = GetResolvedCustomAuraBarAuraUnit(entry, entry.spellID)
        local showAuraStatusBadge = (not isSpellCustomBar) or entry.auraTracking == true
        local auraStatus = showAuraStatusBadge and ResolveCustomBarAuraTrackingStatus(entry, resolvedRowAuraUnit) or nil
        local rightBadgeAnchor = rowFrame
        local rightBadgePoint = "RIGHT"
        local rightBadgeOffset = -4

        if entry.enabled == false then
            local disabledBadge = EnsureCustomBarRowIconBadge(rowFrame, "_cdcCustomBarDisabledBadge", "GM-icon-visibleDis-pressed")
            disabledBadge:SetPoint("RIGHT", rowFrame, "RIGHT", rightBadgeOffset, 0)
            SetCustomBarRowBadgeTooltip(disabledBadge, "Disabled", 0.6, 0.6, 0.6)
            rightBadgeAnchor = disabledBadge
            rightBadgePoint = "LEFT"
            rightBadgeOffset = -4
        end

        if showAuraStatusBadge then
            local auraStatusBadge = EnsureCustomBarRowIconBadge(rowFrame, "_cdcCustomBarAuraStatusBadge", "icon_trackedbuffs")
            auraStatusBadge:SetPoint("RIGHT", rightBadgeAnchor, rightBadgePoint, rightBadgeOffset, 0)
            if auraStatus.ready == true then
                auraStatusBadge.icon:SetVertexColor(1, 1, 1, 1)
                SetCustomBarRowBadgeTooltip(auraStatusBadge, "Aura tracking: Active", 0.2, 1, 0.2)
            else
                auraStatusBadge.icon:SetVertexColor(1, 0.2, 0.2, 1)
                local tooltipText = "Aura tracking: Inactive"
                if auraStatus.state == "cdmDisabled" then
                    tooltipText = "Aura tracking: Inactive (Blizzard CDM disabled)"
                elseif auraStatus.state == "trackedAuraUnavailable" then
                    tooltipText = "Aura tracking: Inactive (tracked in CDM, but the Buffs/Debuffs viewer is not currently readable)"
                elseif auraStatus.state == "associatedAuraNotTracked" then
                    tooltipText = "Aura tracking: Inactive (associated aura is not currently tracked in CDM)"
                elseif auraStatus.state == "noAssociatedAura" then
                    tooltipText = "Aura tracking: Inactive (no associated aura found)"
                end
                SetCustomBarRowBadgeTooltip(auraStatusBadge, tooltipText, 1, 0.2, 0.2)
            end
        end

        row:SetCallback("OnClick", function(widget, event, mouseButton)
            if mouseButton == "RightButton" then
                local selectionChanged = CS.selectedCustomBarId ~= customBarId
                if selectionChanged then
                    ClearCustomBarPreviewState()
                end
                CS.selectedCustomBarId = customBarId
                wipe(CS.selectedButtons)
                if selectionChanged then
                    CooldownCompanion:RefreshConfigPanel()
                end
                OpenCustomBarRowMenu(customBars, customBarId, entry)
            elseif mouseButton == "LeftButton" then
                if CS.selectedCustomBarId == customBarId then
                    ClearCustomBarPreviewState()
                    CS.selectedCustomBarId = nil
                    CS.customBarSettingsTab = "appearance"
                else
                    if CS.selectedCustomBarId ~= customBarId then
                        ClearCustomBarPreviewState()
                    end
                    CS.selectedCustomBarId = customBarId
                end
                CooldownCompanion:RefreshConfigPanel()
            end
        end)
        container:AddChild(row)
    end
end

local function BuildCustomBarIndicatorsTab(container, customBars, capturedIdx, cab, isSpellCustomBar, resolvedAuraUnit, capturedKey, infoButtons)
    local cabIdx = capturedIdx
    local cabApplyBars = function() CooldownCompanion:ApplyResourceBars() end
    local renderedControls = false

    if not cab.spellID then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetText("|cff888888This Custom Bar has no indicator settings yet.|r")
        emptyLabel:SetFullWidth(true)
        container:AddChild(emptyLabel)
        return
    end

    local hasAuraDisplayControls = IsCustomBarAuraDisplayConfig(cab, isSpellCustomBar)
    local trackingMode = GetCustomBarTrackingModeConfig(cab, isSpellCustomBar)
    local isActiveTracking = hasAuraDisplayControls and trackingMode == "active"
    local hasActiveAuraIndicatorControls = isActiveTracking

    if hasActiveAuraIndicatorControls then
        renderedControls = true

        local indicatorsHeading = AceGUI:Create("Heading")
        indicatorsHeading:SetText("Active Aura")
        ColorHeading(indicatorsHeading)
        indicatorsHeading:SetFullWidth(true)
        container:AddChild(indicatorsHeading)

        local activeAuraEnabled = (cab.barAuraEffect or "none") ~= "none"

        local activeAuraCb = AceGUI:Create("CheckBox")
        activeAuraCb:SetLabel("Show Active Aura Indicator")
        activeAuraCb:SetValue(activeAuraEnabled)
        activeAuraCb:SetFullWidth(true)
        activeAuraCb:SetCallback("OnValueChanged", function(widget, event, val)
            if val then
                local effect = customBars[cabIdx].barAuraEffect
                if effect == nil or effect == "none" then
                    effect = "pixel"
                end
                customBars[cabIdx].barAuraEffect = effect
            else
                customBars[cabIdx].barAuraEffect = "none"
            end
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(activeAuraCb)

        local activeAuraAdvExpanded = AddAdvancedToggle(activeAuraCb, "rbCabActiveAura_" .. capturedKey, infoButtons, activeAuraEnabled)
        if activeAuraAdvExpanded and activeAuraEnabled then
            local activeAuraCombatCb = AceGUI:Create("CheckBox")
            activeAuraCombatCb:SetLabel("Show Only In Combat")
            activeAuraCombatCb:SetValue(cab.auraGlowCombatOnly or false)
            activeAuraCombatCb:SetFullWidth(true)
            activeAuraCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[cabIdx].auraGlowCombatOnly = val
                CooldownCompanion:ApplyResourceBars()
            end)
            container:AddChild(activeAuraCombatCb)
            ApplyCheckboxIndent(activeAuraCombatCb, 20)

            BuildBarActiveAuraControls(container, customBars[cabIdx], cabApplyBars, {
                hidePrimaryColorPicker = not isSpellCustomBar,
            })
            BuildBarAuraPulseControls(container, customBars[cabIdx], cabApplyBars)

            if AddPreviewToggleButton then
                AddPreviewToggleButton(container, "Preview Active Aura Effects", function()
                    return CooldownCompanion:IsCustomAuraBarActivePreviewActive(customBars[cabIdx])
                end, function(show)
                    CooldownCompanion:SetCustomAuraBarActivePreview(customBars[cabIdx], show)
                end)
            end
        else
            CooldownCompanion:SetCustomAuraBarActivePreview(customBars[cabIdx], false)
        end

        if resolvedAuraUnit == "target" then
            local pandemicEnabled = cab.showPandemicGlow == true

            local pandemicCb = AceGUI:Create("CheckBox")
            pandemicCb:SetLabel("Show Pandemic Indicator")
            pandemicCb:SetValue(pandemicEnabled)
            pandemicCb:SetFullWidth(true)
            pandemicCb:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[cabIdx].showPandemicGlow = val and true or false
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(pandemicCb)

            local pandemicAdvExpanded = AddAdvancedToggle(pandemicCb, "rbCabPandemic_" .. capturedKey, infoButtons, pandemicEnabled)
            if pandemicAdvExpanded and pandemicEnabled then
                local pandemicCombatCb = AceGUI:Create("CheckBox")
                pandemicCombatCb:SetLabel("Show Only In Combat")
                pandemicCombatCb:SetValue(cab.pandemicGlowCombatOnly or false)
                pandemicCombatCb:SetFullWidth(true)
                pandemicCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
                    customBars[cabIdx].pandemicGlowCombatOnly = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(pandemicCombatCb)
                ApplyCheckboxIndent(pandemicCombatCb, 20)

                BuildPandemicBarControls(container, customBars[cabIdx], cabApplyBars)
                BuildPandemicBarPulseControls(container, customBars[cabIdx], cabApplyBars)

                if AddPreviewToggleButton then
                    AddPreviewToggleButton(container, "Preview Pandemic Effects", function()
                        return CooldownCompanion:IsCustomAuraBarPandemicPreviewActive(customBars[cabIdx])
                    end, function(show)
                        CooldownCompanion:SetCustomAuraBarPandemicPreview(customBars[cabIdx], show)
                    end)
                end
            else
                CooldownCompanion:SetCustomAuraBarPandemicPreview(customBars[cabIdx], false)
            end
        else
            CooldownCompanion:SetCustomAuraBarPandemicPreview(customBars[cabIdx], false)
        end
    elseif not isSpellCustomBar and hasAuraDisplayControls then
        renderedControls = true

        local thresholdHeading = AceGUI:Create("Heading")
        thresholdHeading:SetText("Stack Threshold")
        ColorHeading(thresholdHeading)
        thresholdHeading:SetFullWidth(true)
        container:AddChild(thresholdHeading)

        local thresholdCb = AceGUI:Create("CheckBox")
        thresholdCb:SetLabel("Enable Max Stack Color")
        thresholdCb:SetValue(cab.thresholdColorEnabled == true)
        thresholdCb:SetFullWidth(true)
        thresholdCb:SetCallback("OnValueChanged", function(widget, event, val)
            customBars[cabIdx].thresholdColorEnabled = val or nil
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(thresholdCb)

        if cab.thresholdColorEnabled == true then
            AddColorPicker(container, customBars[cabIdx], "thresholdMaxColor", "Max Stack Color", DEFAULT_CUSTOM_AURA_MAX_COLOR, false,
                cabApplyBars, function() CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx]) end)
        end
    end

    if not isSpellCustomBar and hasAuraDisplayControls and not isActiveTracking then
        renderedControls = true

        local indicatorsHeading = AceGUI:Create("Heading")
        indicatorsHeading:SetText("Max Stack Indicator")
        ColorHeading(indicatorsHeading)
        indicatorsHeading:SetFullWidth(true)
        container:AddChild(indicatorsHeading)

        local glowCb = AceGUI:Create("CheckBox")
        glowCb:SetLabel("Max Stack Indicator")
        glowCb:SetValue(cab.maxStacksGlowEnabled == true)
        glowCb:SetFullWidth(true)
        glowCb:SetCallback("OnValueChanged", function(widget, event, val)
            customBars[cabIdx].maxStacksGlowEnabled = val or nil
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(glowCb)

        local glowAdvExpanded, glowAdvBtn = AddAdvancedToggle(glowCb, "rbCabMaxStacksIndicator_" .. capturedKey, infoButtons, cab.maxStacksGlowEnabled == true)
        if not glowAdvExpanded and CS.customBarIndicatorPreviewActive and CooldownCompanion:IsResourceBarPreviewActive() then
            CooldownCompanion:StopResourceBarPreview()
        end

        CreateInfoButton(glowCb.frame, glowAdvBtn, "LEFT", "RIGHT", 4, 0, {
            "Max Stack Indicator",
            {"Due to combat restrictions, individual bar segments cannot be highlighted independently.", 1, 1, 1, true},
            " ",
            {"The indicator covers the entire resource bar and appears automatically when your buff reaches its maximum stack count.", 1, 1, 1, true},
            " ",
            {"The Pulsing Overlay style is only available for continuous display mode.", 1, 1, 1, true},
        }, glowCb)

        if glowAdvExpanded and cab.maxStacksGlowEnabled then
            local isContinuousDisplay = (cab.trackingMode == "active") or (cab.displayMode == "continuous")
            local currentStyle = cab.maxStacksGlowStyle or "solidBorder"
            if currentStyle == "pulsingOverlay" and not isContinuousDisplay then
                currentStyle = "solidBorder"
                customBars[cabIdx].maxStacksGlowStyle = "solidBorder"
            end

            local styleList, styleOrder
            if isContinuousDisplay then
                styleList = {
                    solidBorder = "Solid Border",
                    pulsingBorder = "Pulsing Border",
                    pulsingOverlay = "Pulsing Overlay",
                }
                styleOrder = { "solidBorder", "pulsingBorder", "pulsingOverlay" }
            else
                styleList = {
                    solidBorder = "Solid Border",
                    pulsingBorder = "Pulsing Border",
                }
                styleOrder = { "solidBorder", "pulsingBorder" }
            end
            local styleDrop = AceGUI:Create("Dropdown")
            styleDrop:SetLabel("Indicator Style")
            styleDrop:SetList(styleList, styleOrder)
            styleDrop:SetValue(currentStyle)
            styleDrop:SetFullWidth(true)
            styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[cabIdx].maxStacksGlowStyle = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(styleDrop)

            AddColorPicker(container, customBars[cabIdx], "maxStacksGlowColor", "Indicator Color", {1, 0.84, 0, 0.9}, true,
                cabApplyBars, cabApplyBars)

            if currentStyle ~= "pulsingOverlay" then
                local sizeSlider = AceGUI:Create("Slider")
                sizeSlider:SetLabel("Border Size")
                sizeSlider:SetSliderValues(1, 8, 1)
                sizeSlider:SetValue(cab.maxStacksGlowSize or 2)
                sizeSlider:SetFullWidth(true)
                sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    customBars[cabIdx].maxStacksGlowSize = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(sizeSlider)
            end

            if currentStyle == "pulsingBorder" or currentStyle == "pulsingOverlay" then
                local speedSlider = AceGUI:Create("Slider")
                speedSlider:SetLabel("Pulse Duration")
                speedSlider:SetSliderValues(0.1, 2.0, 0.1)
                speedSlider:SetValue(cab.maxStacksGlowSpeed or 0.5)
                speedSlider:SetFullWidth(true)
                speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    customBars[cabIdx].maxStacksGlowSpeed = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(speedSlider)
            end

            if AddPreviewToggleButton then
                AddPreviewToggleButton(container, "Preview Indicator", function()
                    return CS.customBarIndicatorPreviewActive == true and CooldownCompanion:IsResourceBarPreviewActive()
                end, function(show)
                    CS.customBarIndicatorPreviewActive = show and true or nil
                    if show then
                        CooldownCompanion:StartResourceBarPreview()
                    else
                        CooldownCompanion:StopResourceBarPreview()
                    end
                end)
            end
        end
    end

    if not renderedControls then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetText("|cff888888This Custom Bar has no indicator settings yet.|r")
        emptyLabel:SetFullWidth(true)
        container:AddChild(emptyLabel)
    end
end

local function BuildCustomAuraBarPanel(container, customBarId, activeTab)
    local settings = CooldownCompanion:GetResourceBarSettings()
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    local thicknessField, thicknessLabel = GetResourceThicknessFieldConfig(settings, layout)
    local customBars = CooldownCompanion:GetSpecCustomAuraBars()
    local rbCabTextAdvBtns = {}
    local selectedIndex = FindCustomBarIndexById(customBars, customBarId)
    local infoButtons = CS.customBarInfoButtons
    if not infoButtons then
        infoButtons = {}
        CS.customBarInfoButtons = infoButtons
    end

    if not selectedIndex then
        local label = AceGUI:Create("Label")
        label:SetText("Select a Custom Bar to configure it.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end
    local cab = customBars[selectedIndex]
    local capturedIdx = selectedIndex
    local capturedId = EnsureCustomBarId(settings, cab)
    local capturedKey = capturedId or tostring(capturedIdx)
    local isSpellCustomBar = IsSpellCustomBarConfig(cab)
    local hasAuraDisplayControls = IsCustomBarAuraDisplayConfig(cab, isSpellCustomBar)
    local trackingMode = GetCustomBarTrackingModeConfig(cab, isSpellCustomBar)
    local isStackDisplay = hasAuraDisplayControls and trackingMode ~= "active"
    local resolvedAuraUnit = GetResolvedCustomAuraBarAuraUnit(cab, cab.spellID)
    activeTab = activeTab or "appearance"

    if activeTab == "settings" or activeTab == "layout" or activeTab == "anchor" or activeTab == "alpha" then
        activeTab = "appearance"
    end

    if activeTab == "soundalerts" then
        ST._BuildCustomBarSoundAlertsTab(container, cab, infoButtons)
        return
    end

    if activeTab == "loadconditions" then
        ST._BuildCustomBarLoadConditionsTab(container, cab, infoButtons)
        return
    end

    if activeTab == "indicators" then
        BuildCustomBarIndicatorsTab(container, customBars, capturedIdx, cab, isSpellCustomBar, resolvedAuraUnit, capturedKey, infoButtons)
        return
    end

    BuildCustomBarAuraTrackingSection(container, cab, resolvedAuraUnit, infoButtons)

    if hasAuraDisplayControls then
        AddCustomBarSettingsHeading(container, "Aura Display Mode", infoButtons, {
            "Determines how the tracked aura is displayed on this Custom Bar.",
            " ",
            "Active: shows the aura's remaining duration while it is active.",
            " ",
            "Stack Count: ignores duration and shows only the aura's current stack count.",
        })
    end

            -- Aura Display Mode dropdown
            if hasAuraDisplayControls then
            local trackDrop = AceGUI:Create("Dropdown")
            trackDrop:SetList({
                active = "Active",
                stacks = "Stack Count",
            }, { "active", "stacks" })
            trackDrop:SetValue(trackingMode)
            trackDrop:SetFullWidth(true)
            trackDrop:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[capturedIdx].trackingMode = val
                if val ~= "active" then
                    CooldownCompanion:SetCustomAuraBarActivePreview(customBars[capturedIdx], false)
                    CooldownCompanion:SetCustomAuraBarPandemicPreview(customBars[capturedIdx], false)
                end
                ApplyCustomAuraBarPanelChanges({
                    updateAnchors = true,
                    refreshConfig = true,
                })
            end)
            container:AddChild(trackDrop)
            end

            -- Max Stacks slider (hidden in "active" tracking mode)
            if isStackDisplay then
            local maxSlider = AceGUI:Create("Slider")
            maxSlider:SetLabel("Max Stacks")
            maxSlider:SetSliderValues(1, 99, 1)
            maxSlider:SetValue(cab.maxStacks or 1)
            maxSlider:SetFullWidth(true)
            local pendingMaxStacks = cab.maxStacks or 1
            maxSlider:SetCallback("OnValueChanged", function(widget, event, val)
                pendingMaxStacks = math.max(1, math.min(99, math.floor((tonumber(val) or 1) + 0.5)))
            end)
            maxSlider:SetCallback("OnMouseUp", function(widget, event, val)
                local committedValue = math.max(1, math.min(99, math.floor((tonumber(val) or pendingMaxStacks or 1) + 0.5)))
                if customBars[capturedIdx].maxStacks == committedValue then
                    return
                end
                customBars[capturedIdx].maxStacks = committedValue
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            container:AddChild(maxSlider)
            end

            -- Display Mode dropdown (hidden in "active" tracking mode)
            if isStackDisplay then
            local modeDrop = AceGUI:Create("Dropdown")
            modeDrop:SetLabel("Display Mode")
            modeDrop:SetList({
                continuous = "Continuous",
                segmented = "Segmented",
                overlay = "Overlay",
            }, { "continuous", "segmented", "overlay" })
            modeDrop:SetValue(cab.displayMode or "segmented")
            modeDrop:SetFullWidth(true)
            modeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[capturedIdx].displayMode = val
                ApplyCustomAuraBarPanelChanges({
                    updateAnchors = true,
                    refreshConfig = true,
                })
            end)
            container:AddChild(modeDrop)
            end

            -- Per-slot bar thickness override
            if layout and layout.customBarHeights then
                AddCustomBarSettingsHeading(container, "Size")

                local slotLayout = EnsureCustomBarLayout(settings, nil, capturedId, 1000 + capturedIdx) or {}
                local cabHeightSlider = AceGUI:Create("Slider")
                cabHeightSlider:SetLabel(thicknessLabel)
                cabHeightSlider:SetSliderValues(4, 40, 0.1)
                if thicknessField == "barWidth" then
                    cabHeightSlider:SetValue(slotLayout.barWidth or slotLayout.barHeight or layout.barWidth or layout.barHeight or settings.barWidth or settings.barHeight or 12)
                else
                    cabHeightSlider:SetValue(slotLayout.barHeight or slotLayout.barWidth or layout.barHeight or layout.barWidth or settings.barHeight or settings.barWidth or 12)
                end
                cabHeightSlider:SetFullWidth(true)
                local cabIdx = capturedIdx
                cabHeightSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    local customBar = customBars[cabIdx]
                    local customLayout = EnsureCustomBarLayout(settings, nil, customBar and customBar.customBarId, 1000 + cabIdx)
                    if customLayout then
                        customLayout[thicknessField] = val
                    end
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:RepositionCastBar()
                    CooldownCompanion:UpdateAnchorStacking()
                end)
                container:AddChild(cabHeightSlider)
            end

            -- ---- Colors section (only when has spell ID) ----
            if cab.spellID then
                local colorHeading = AceGUI:Create("Heading")
                colorHeading:SetText("Colors")
                ColorHeading(colorHeading)
                colorHeading:SetFullWidth(true)
                container:AddChild(colorHeading)

                -- Bar Color (all modes)
                local cabIdx = capturedIdx
                local cabApplyBars = function() CooldownCompanion:ApplyResourceBars() end
                AddColorPicker(container, customBars[cabIdx], "barColor", "Bar Color", {0.5, 0.5, 1}, false,
                    cabApplyBars, function() CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx]) end)

                if isSpellCustomBar and not isStackDisplay then
                    AddColorPicker(container, customBars[cabIdx], "barCooldownColor", "Bar Cooldown Color", {0.6, 0.13, 0.18, 1}, true,
                        cabApplyBars, cabApplyBars)
                    AddColorPicker(container, customBars[cabIdx], "barChargeColor", "Bar Recharging Color", {1.0, 0.82, 0.0, 1}, true,
                        cabApplyBars, cabApplyBars)
                end

                -- Overlay Color (overlay mode only)
                if cab.displayMode == "overlay" and isStackDisplay then
                    local cpOverlay = AddColorPicker(container, customBars[cabIdx], "overlayColor", "Overlay Color", {1, 0.84, 0}, false,
                        cabApplyBars, function() CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx]) end)

                    cpOverlay:SetCallback("OnEnter", function(widget)
                        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                        GameTooltip:AddLine("Overlay Color")
                        GameTooltip:AddLine("Number of bar segments equals half the max stacks. Overlay color activates once base segments are full.", 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    cpOverlay:SetCallback("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                end

                -- ---- Text / Duration controls ----
                local isActive = not isStackDisplay
                local isContinuous = isActive or (cab.displayMode == "continuous")

                if isContinuous then
                    local textsHeading = AceGUI:Create("Heading")
                    textsHeading:SetText("Texts")
                    ColorHeading(textsHeading)
                    textsHeading:SetFullWidth(true)
                    container:AddChild(textsHeading)

                    local showDurationControls = not (isSpellCustomBar and isStackDisplay)
                    local durationTextCb
                    if showDurationControls then
                        durationTextCb = AceGUI:Create("CheckBox")
                        durationTextCb:SetLabel("Show Duration Text")
                        durationTextCb:SetValue(cab.showDurationText == true)
                        durationTextCb:SetFullWidth(true)
                        durationTextCb:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].showDurationText = val or nil
                            CooldownCompanion:ApplyResourceBars()
                            CooldownCompanion:RefreshConfigPanel()
                        end)
                        container:AddChild(durationTextCb)
                    end

                    -- Show Stack Text
                    local stackVal = cab.showStackText
                    if stackVal == nil and not isActive then
                        stackVal = cab.showText  -- backwards compat
                    end

                    local stackTextCb = AceGUI:Create("CheckBox")
                    local stackTextLabel = "Show Stack Text"
                    if isSpellCustomBar then
                        stackTextLabel = isStackDisplay and "Show Aura Stack Text" or "Show Count Text (Charges/Uses)"
                    end
                    stackTextCb:SetLabel(stackTextLabel)
                    stackTextCb:SetValue(stackVal == true)
                    stackTextCb:SetFullWidth(true)
                    stackTextCb:SetCallback("OnValueChanged", function(widget, event, val)
                        customBars[cabIdx].showStackText = val or nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    container:AddChild(stackTextCb)

                    local showDuration = showDurationControls and cab.showDurationText == true
                    local showStack = (stackVal == true)
                    local durationAdvExpanded = showDurationControls
                        and AddAdvancedToggle(durationTextCb, "rbCabDurationText_" .. capturedKey, rbCabTextAdvBtns, showDuration)
                    if showDurationControls and durationAdvExpanded and showDuration then
                        local fontDrop = AceGUI:Create("Dropdown")
                        fontDrop:SetLabel("Duration Font")
                        CS.SetupFontDropdown(fontDrop)
                        fontDrop:SetValue(cab.durationTextFont or DEFAULT_RESOURCE_TEXT_FONT)
                        fontDrop:SetFullWidth(true)
                        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFont = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(fontDrop)

                        local sizeDrop = AceGUI:Create("Slider")
                        sizeDrop:SetLabel("Duration Font Size")
                        sizeDrop:SetSliderValues(6, 24, 1)
                        sizeDrop:SetValue(cab.durationTextFontSize or DEFAULT_RESOURCE_TEXT_SIZE)
                        sizeDrop:SetFullWidth(true)
                        sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFontSize = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(sizeDrop)

                        local outlineDrop = AceGUI:Create("Dropdown")
                        outlineDrop:SetLabel("Duration Outline")
                        outlineDrop:SetList(CS.outlineOptions)
                        outlineDrop:SetValue(cab.durationTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
                        outlineDrop:SetFullWidth(true)
                        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFontOutline = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(outlineDrop)

                        AddColorPicker(container, customBars[cabIdx], "durationTextFontColor", "Duration Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, cabApplyBars)

                        local decimalCheck = AceGUI:Create("CheckBox")
                        decimalCheck:SetLabel("Show Decimal Point")
                        decimalCheck:SetValue(cab.decimalTimers or false)
                        decimalCheck:SetFullWidth(true)
                        decimalCheck:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].decimalTimers = val or nil
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(decimalCheck)

                        CreateInfoButton(decimalCheck.frame, decimalCheck.checkbg, "LEFT", "RIGHT", decimalCheck.text:GetStringWidth() + 4, 0, {
                            "Show Decimal Point",
                            {"Shows one decimal place on duration text", 1, 1, 1, true},
                            {"(e.g. \"4.5\" instead of \"5\").", 1, 1, 1, true},
                        }, decimalCheck)
                    end

                    local stackAdvExpanded = AddAdvancedToggle(stackTextCb, "rbCabStackText_" .. capturedKey, rbCabTextAdvBtns, showStack)
                    if stackAdvExpanded and showStack then
                        if not isActive then
                            local stackTextFormatDrop = AceGUI:Create("Dropdown")
                            stackTextFormatDrop:SetLabel("Text Format")
                            local stackTextFormatOptions = {
                                current = "Current Value",
                                current_max = "Current / Max",
                            }
                            local stackTextFormatOrder = { "current", "current_max" }
                            stackTextFormatDrop:SetList(stackTextFormatOptions, stackTextFormatOrder)
                            local stackTextFormatValue = cab.stackTextFormat or DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
                            if stackTextFormatValue ~= "current" and stackTextFormatValue ~= "current_max" then
                                stackTextFormatValue = DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
                            end
                            stackTextFormatDrop:SetValue(stackTextFormatValue)
                            stackTextFormatDrop:SetFullWidth(true)
                            stackTextFormatDrop:SetCallback("OnValueChanged", function(widget, event, val)
                                if val == "current" or val == "current_max" then
                                    customBars[cabIdx].stackTextFormat = val
                                else
                                    customBars[cabIdx].stackTextFormat = DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
                                end
                                CooldownCompanion:ApplyResourceBars()
                            end)
                            container:AddChild(stackTextFormatDrop)
                        end

                        local fontDrop = AceGUI:Create("Dropdown")
                        local stackFontLabel = isSpellCustomBar and (isStackDisplay and "Aura Stack Font" or "Charge Font") or "Stack Font"
                        fontDrop:SetLabel(stackFontLabel)
                        CS.SetupFontDropdown(fontDrop)
                        fontDrop:SetValue(cab.stackTextFont or DEFAULT_RESOURCE_TEXT_FONT)
                        fontDrop:SetFullWidth(true)
                        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFont = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(fontDrop)

                        local sizeDrop = AceGUI:Create("Slider")
                        local stackSizeLabel = isSpellCustomBar and (isStackDisplay and "Aura Stack Font Size" or "Charge Font Size") or "Stack Font Size"
                        sizeDrop:SetLabel(stackSizeLabel)
                        sizeDrop:SetSliderValues(6, 24, 1)
                        sizeDrop:SetValue(cab.stackTextFontSize or DEFAULT_RESOURCE_TEXT_SIZE)
                        sizeDrop:SetFullWidth(true)
                        sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFontSize = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(sizeDrop)

                        local outlineDrop = AceGUI:Create("Dropdown")
                        local stackOutlineLabel = isSpellCustomBar and (isStackDisplay and "Aura Stack Outline" or "Charge Outline") or "Stack Outline"
                        outlineDrop:SetLabel(stackOutlineLabel)
                        outlineDrop:SetList(CS.outlineOptions)
                        outlineDrop:SetValue(cab.stackTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
                        outlineDrop:SetFullWidth(true)
                        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFontOutline = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(outlineDrop)

                        AddColorPicker(container, customBars[cabIdx], "stackTextFontColor", "Stack Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, cabApplyBars)
                    end
                end

                if not isSpellCustomBar or cab.auraTracking == true then
                    BuildCustomBarVisibilityRulesSection(container, customBars, capturedIdx, cab, resolvedAuraUnit, capturedKey, infoButtons)
                end

                -- ---- Talent Conditions section ----
                local talentHeading = AceGUI:Create("Heading")
                talentHeading:SetText("Talent Conditions")
                ColorHeading(talentHeading)
                talentHeading:SetFullWidth(true)
                container:AddChild(talentHeading)

                local talentKey = "cab_talent_" .. capturedKey
                local talentCollapsed = resourceBarCollapsedSections[talentKey]

                local talentCollapseBtn = AttachCollapseButton(talentHeading, talentCollapsed, function()
                    resourceBarCollapsedSections[talentKey] = not resourceBarCollapsedSections[talentKey]
                    CooldownCompanion:RefreshConfigPanel()
                end)

                local talentInfoBtn = CreateInfoButton(talentHeading.frame, talentCollapseBtn, "LEFT", "RIGHT", 2, 0, {
                    "Talent Conditions",
                    {"Show or hide this Custom Bar based on which talents you have selected. If you add multiple conditions, all of them must pass.", 1, 1, 1, true},
                }, infoButtons)
                talentHeading.right:ClearAllPoints()
                talentHeading.right:SetPoint("RIGHT", talentHeading.frame, "RIGHT", -3, 0)
                talentHeading.right:SetPoint("LEFT", talentInfoBtn, "RIGHT", 4, 0)

                local conditions = cab.talentConditions
                local condCount = conditions and #conditions or 0

                if talentCollapsed then
                    local summaryLabel = AceGUI:Create("Label")
                    if condCount > 0 then
                        local firstCond = conditions[1]
                        local displayIcon = not IsHeroSpecProxyCondition(firstCond)
                            and firstCond.spellID
                            and C_Spell.GetSpellTexture(firstCond.spellID)
                        if displayIcon then
                            summaryLabel:SetImage(displayIcon, 0.08, 0.92, 0.08, 0.92)
                            summaryLabel:SetImageSize(16, 16)
                        end
                        if condCount == 1 then
                            local showText = (firstCond.show == "not_taken") and " (not taken)" or " (taken)"
                            summaryLabel:SetText(ST._GetConditionDisplayName(firstCond) .. showText)
                        else
                            summaryLabel:SetText(condCount .. " conditions" .. ST._GetConditionListContextSuffix(conditions))
                        end
                    else
                        summaryLabel:SetText("|cff888888None|r")
                    end
                    summaryLabel:SetFullWidth(true)
                    container:AddChild(summaryLabel)
                end

                if not talentCollapsed then

                -- Condition list display
                if condCount > 0 then
                    local cache = CooldownCompanion._talentNodeCache
                    local currentSpecID = CooldownCompanion._currentSpecId
                    local currentHeroSubTreeID = CooldownCompanion._currentHeroSpecId
                    for _, cond in ipairs(conditions) do
                        local condLabel = AceGUI:Create("Label")
                        local displayIcon = not IsHeroSpecProxyCondition(cond)
                            and cond.spellID
                            and C_Spell.GetSpellTexture(cond.spellID)
                        if displayIcon then
                            condLabel:SetImage(displayIcon, 0.08, 0.92, 0.08, 0.92)
                            condLabel:SetImageSize(16, 16)
                        end
                        local nameText = ST._GetConditionDisplayName(cond)
                        local showText
                        if cond.show == "not_taken" then
                            showText = " |cffff4d4d(not taken)|r"
                        else
                            showText = " |cff33dd33(taken)|r"
                        end
                        condLabel:SetText("|cffFFFFFF" .. nameText .. "|r" .. showText)
                        condLabel:SetFullWidth(true)
                        container:AddChild(condLabel)

                        -- Per-condition stale node warning
                        local matchesCurrentScope = (not cond.specID or cond.specID == currentSpecID)
                            and (not cond.heroSubTreeID or cond.heroSubTreeID == currentHeroSubTreeID)
                        if matchesCurrentScope and cache and not cache[cond.nodeID] then
                            local warnLabel = AceGUI:Create("Label")
                            warnLabel:SetText("|cffff8800  This talent is not in your current active tree, so it behaves as not taken right now.|r")
                            warnLabel:SetFullWidth(true)
                            container:AddChild(warnLabel)
                        end
                    end
                else
                    local emptyLabel = AceGUI:Create("Label")
                    emptyLabel:SetText("|cff888888No talent conditions set.|r")
                    emptyLabel:SetFullWidth(true)
                    container:AddChild(emptyLabel)
                end

                -- Button row: side-by-side Pick + Clear using Flow layout
                local talentBtnRow = AceGUI:Create("SimpleGroup")
                talentBtnRow:SetFullWidth(true)
                talentBtnRow:SetLayout("Flow")

                local pickBtn = AceGUI:Create("Button")
                pickBtn:SetText(condCount > 0 and "Edit" or "Pick Talents")
                pickBtn:SetRelativeWidth(condCount > 0 and 0.5 or 1)
                pickBtn:SetCallback("OnClick", function()
                    local initialConditions = cab.talentConditions
                    -- Restrict picker to current spec (aura bars are per-spec)
                    local specID = CooldownCompanion._currentSpecId
                    local specHint = specID and { specs = { [specID] = true } } or nil
                    CooldownCompanion:OpenTalentPicker(function(results)
                        if results then
                            local normalized, changed = CooldownCompanion:NormalizeTalentConditions(results)
                            if changed then
                                results = normalized
                            end
                            customBars[cabIdx].talentConditions = results
                        else
                            customBars[cabIdx].talentConditions = nil
                        end
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:UpdateAnchorStacking()
                        CooldownCompanion:RefreshConfigPanel()
                    end, initialConditions, specHint)
                end)
                talentBtnRow:AddChild(pickBtn)

                -- Clear button (only when conditions exist)
                if condCount > 0 then
                    local clearBtn = AceGUI:Create("Button")
                    clearBtn:SetText("Clear")
                    clearBtn:SetRelativeWidth(0.5)
                    clearBtn:SetCallback("OnClick", function()
                        customBars[cabIdx].talentConditions = nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:UpdateAnchorStacking()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    talentBtnRow:AddChild(clearBtn)
                end

                container:AddChild(talentBtnRow)

                end -- not talentCollapsed
            end

end

------------------------------------------------------------------------
-- Layout & Order panel: per-element position/order control
------------------------------------------------------------------------

local function BuildLayoutOrderPanel(container)
    if ST._BuildLayoutOrderPreviewPanel then
        ST._BuildLayoutOrderPreviewPanel(container)
        return
    end

    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    local cbSettings = CooldownCompanion:GetCastBarSettings()

    if not rbSettings or not rbSettings.enabled then
        local label = AceGUI:Create("Label")
        label:SetText("Enable Resource Bars to configure layout.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    local layout = CooldownCompanion:GetSpecLayoutOrder()
    if not layout then
        local label = AceGUI:Create("Label")
        label:SetText("Specialization data loading...")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end
    local isVerticalLayout = IsResourceBarVerticalConfig(rbSettings, layout)

    -- Build the ordered list of all active bar slots
    local activeResources = GetConfigActiveResources()
    local customBars = CooldownCompanion:GetSpecCustomAuraBars()

    -- Resolve the display color for a power type (respects per-spec overrides)
    local layoutSpecID = GetCurrentConfigSpecID()
    if not layoutSpecID then
        local specLabel = AceGUI:Create("Label")
        specLabel:SetText("Specialization data not yet available.")
        specLabel:SetFullWidth(true)
        container:AddChild(specLabel)
        return
    end
    local function GetResourceColor(pt)
        if pt == HealthResource.ID then
            local health = rbSettings.resources and rbSettings.resources[HealthResource.ID]
            return health and health.healthBarColor or DEFAULT_HEALTH_BAR_COLOR
        elseif pt == 4 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "comboColor", DEFAULT_COMBO_COLOR)
        elseif pt == 5 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "runeReadyColor", DEFAULT_RUNE_READY_COLOR)
        elseif pt == 7 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "shardReadyColor", DEFAULT_SHARD_READY_COLOR)
        elseif pt == 9 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "holyColor", DEFAULT_HOLY_COLOR)
        elseif pt == 12 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "chiColor", DEFAULT_CHI_COLOR)
        elseif pt == 16 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "arcaneColor", DEFAULT_ARCANE_COLOR)
        elseif pt == 19 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "essenceReadyColor", DEFAULT_ESSENCE_READY_COLOR)
        elseif pt == 100 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "mwBaseColor", DEFAULT_MW_BASE_COLOR)
        elseif pt == 101 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "staggerGreenColor", { 0.52, 0.90, 0.52 })
        else return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "color", DEFAULT_POWER_COLORS[pt] or { 1, 1, 1 })
        end
    end

    -- Helper: refresh after any order/position change
    local function ApplyAndRefresh()
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RepositionCastBar()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end

    local function RenderSlotOrdering(slots, sectionTitle, sideOne, sideTwo, dividerLabel, moveOneLabel, moveTwoLabel)
        if sectionTitle and sectionTitle ~= "" then
            local sectionHeading = AceGUI:Create("Heading")
            sectionHeading:SetText(sectionTitle)
            sectionHeading:SetFullWidth(true)
            container:AddChild(sectionHeading)
        end

        if #slots == 0 then
            local emptyLabel = AceGUI:Create("Label")
            emptyLabel:SetText("|cff888888No active entries in this section.|r")
            emptyLabel:SetFullWidth(true)
            container:AddChild(emptyLabel)
            return
        end

        local sideOneSlots = {}
        local sideTwoSlots = {}
        for _, slot in ipairs(slots) do
            if slot.getPos() == sideOne then
                table.insert(sideOneSlots, slot)
            else
                table.insert(sideTwoSlots, slot)
            end
        end
        table.sort(sideOneSlots, function(a, b) return a.getOrder() > b.getOrder() end)
        table.sort(sideTwoSlots, function(a, b) return a.getOrder() < b.getOrder() end)

        local displayList = {}
        for _, s in ipairs(sideOneSlots) do table.insert(displayList, s) end
        local dividerIdx = #displayList + 1
        for _, s in ipairs(sideTwoSlots) do table.insert(displayList, s) end

        for rowIdx, slot in ipairs(displayList) do
            if rowIdx == dividerIdx then
                local divLabel = AceGUI:Create("Heading")
                divLabel:SetText(dividerLabel or "Icons")
                divLabel:SetFullWidth(true)
                container:AddChild(divLabel)
            end

            local rowGroup = AceGUI:Create("SimpleGroup")
            rowGroup:SetLayout("Flow")
            rowGroup:SetFullWidth(true)
            container:AddChild(rowGroup)

            local nameLabel = AceGUI:Create("Label")
            local c = slot.color
            local coloredText = slot.label
            if c then
                local r, g, b = (c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255
                coloredText = string.format("|cff%02x%02x%02x%s|r", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5), slot.label)
            end
            nameLabel:SetText(coloredText)
            nameLabel:SetRelativeWidth(0.48)
            rowGroup:AddChild(nameLabel)

            local moveOneBtn = AceGUI:Create("Button")
            moveOneBtn:SetText(moveOneLabel)
            moveOneBtn:SetRelativeWidth(0.20)
            moveOneBtn:SetDisabled(rowIdx == 1 and slot.getPos() == sideOne)
            moveOneBtn:SetCallback("OnClick", function()
                local prev = displayList[rowIdx - 1]
                if prev and prev.getPos() == slot.getPos() then
                    local myOrder = slot.getOrder()
                    local prevOrder = prev.getOrder()
                    slot.setOrder(prevOrder)
                    prev.setOrder(myOrder)
                else
                    local minSideOne
                    for _, s in ipairs(sideOneSlots) do
                        local o = s.getOrder()
                        if not minSideOne or o < minSideOne then minSideOne = o end
                    end
                    local currentOrder = slot.getOrder()
                    slot.setPos(sideOne)
                    slot.setOrder(minSideOne and (minSideOne - 1) or currentOrder)
                end
                ApplyAndRefresh()
            end)
            rowGroup:AddChild(moveOneBtn)

            local moveTwoBtn = AceGUI:Create("Button")
            moveTwoBtn:SetText(moveTwoLabel)
            moveTwoBtn:SetRelativeWidth(0.24)
            moveTwoBtn:SetDisabled(rowIdx == #displayList and slot.getPos() == sideTwo)
            moveTwoBtn:SetCallback("OnClick", function()
                local nextSlot = displayList[rowIdx + 1]
                if nextSlot and nextSlot.getPos() == slot.getPos() then
                    local myOrder = slot.getOrder()
                    local nextOrder = nextSlot.getOrder()
                    slot.setOrder(nextOrder)
                    nextSlot.setOrder(myOrder)
                else
                    local minSideTwo
                    for _, s in ipairs(sideTwoSlots) do
                        local o = s.getOrder()
                        if not minSideTwo or o < minSideTwo then minSideTwo = o end
                    end
                    local currentOrder = slot.getOrder()
                    slot.setPos(sideTwo)
                    slot.setOrder(minSideTwo and (minSideTwo - 1) or currentOrder)
                end
                ApplyAndRefresh()
            end)
            rowGroup:AddChild(moveTwoBtn)
        end
    end

    local resourceSlots = {}
    if not rbSettings.resources then rbSettings.resources = {} end

    -- Class resource slots
    for _, pt in ipairs(activeResources) do
        if pt == HealthResource.ID then
            HealthResource.EnsureSettings(rbSettings)
        elseif not rbSettings.resources[pt] then rbSettings.resources[pt] = {} end
        local res = rbSettings.resources[pt]
        local showResource = pt == HealthResource.ID and res.enabled == true or res.enabled ~= false
        if showResource and pt == 0 and rbSettings.hideManaForNonHealer then
            local specIdx = C_SpecializationInfo.GetSpecialization()
            if specIdx then
                local specID, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(specIdx)
                if specID ~= 62 and role ~= "HEALER" then
                    showResource = false
                end
            end
        end
        if showResource then
            local name = POWER_NAMES[pt] or ("Power " .. pt)
            local function ensureLayoutRes()
                if not layout.resources[pt] then layout.resources[pt] = {} end
                return layout.resources[pt]
            end
            if isVerticalLayout then
                table.insert(resourceSlots, {
                    label = name,
                    color = GetResourceColor(pt),
                    getPos = function()
                        local lr = layout.resources[pt]
                        local pos = lr and lr.verticalPosition
                        if pos == "left" or pos == "right" then return pos end
                        return (lr and lr.position == "above") and "left" or "right"
                    end,
                    getOrder = function()
                        local lr = layout.resources[pt]
                        return (lr and lr.verticalOrder) or (lr and lr.order) or (900 + pt)
                    end,
                    setPos = function(v) ensureLayoutRes().verticalPosition = v end,
                    setOrder = function(v) ensureLayoutRes().verticalOrder = v end,
                })
            else
                table.insert(resourceSlots, {
                    label = name,
                    color = GetResourceColor(pt),
                    getPos = function()
                        local lr = layout.resources[pt]
                        return (lr and lr.position) or "below"
                    end,
                    getOrder = function()
                        local lr = layout.resources[pt]
                        return (lr and lr.order) or (900 + pt)
                    end,
                    setPos = function(v) ensureLayoutRes().position = v end,
                    setOrder = function(v) ensureLayoutRes().order = v end,
                })
            end
        end
    end

    -- Custom Bar slots
    for slotIdx, cab in ipairs(customBars or {}) do
        if cab and cab.enabled and cab.spellID then
            local customBarId = EnsureCustomBarId(rbSettings, cab)
            local spellInfo = C_Spell.GetSpellInfo(cab.spellID)
            local slotName = "Custom Bar"
            if spellInfo and spellInfo.name then
                slotName = slotName .. ": " .. spellInfo.name
            end
            local captured = slotIdx
            local function ensureLayoutSlot()
                return EnsureCustomBarLayout(rbSettings, layoutSpecID, customBarId, 1000 + captured)
            end
            if isVerticalLayout then
                table.insert(resourceSlots, {
                    label = slotName,
                    color = cab.barColor or {0.5, 0.5, 1},
                    getPos = function()
                        local slot = GetCustomBarLayout(rbSettings, layoutSpecID, cab, false)
                        local pos = slot and slot.verticalPosition
                        if pos == "left" or pos == "right" then return pos end
                        return (slot and slot.position == "above") and "left" or "right"
                    end,
                    getOrder = function()
                        local slot = GetCustomBarLayout(rbSettings, layoutSpecID, cab, false)
                        return (slot and slot.verticalOrder) or (slot and slot.order) or (1000 + captured)
                    end,
                    setPos = function(v) ensureLayoutSlot().verticalPosition = v end,
                    setOrder = function(v) ensureLayoutSlot().verticalOrder = v end,
                })
            else
                table.insert(resourceSlots, {
                    label = slotName,
                    color = cab.barColor or {0.5, 0.5, 1},
                    getPos = function()
                        local slot = GetCustomBarLayout(rbSettings, layoutSpecID, cab, false)
                        return (slot and slot.position) or "below"
                    end,
                    getOrder = function()
                        local slot = GetCustomBarLayout(rbSettings, layoutSpecID, cab, false)
                        return (slot and slot.order) or (1000 + captured)
                    end,
                    setPos = function(v) ensureLayoutSlot().position = v end,
                    setOrder = function(v) ensureLayoutSlot().order = v end,
                })
            end
        end
    end

    local castSlots = {}
    if cbSettings and cbSettings.enabled and not cbSettings.independentAnchorEnabled then
        local defaultAnchor = CooldownCompanion:GetFirstAvailableAnchorGroup()
        local cbAnchor = defaultAnchor
        local rbAnchor = defaultAnchor
        if cbAnchor and cbAnchor == rbAnchor then
            local cbColor = cbSettings.barColor or { 1.0, 0.7, 0.0 }
            table.insert(castSlots, {
                label = "Cast Bar",
                color = cbColor,
                getPos = function() return (layout.castBar and layout.castBar.position) or "below" end,
                getOrder = function() return (layout.castBar and layout.castBar.order) or 2000 end,
                setPos = function(v)
                    if not layout.castBar then layout.castBar = { position = "below", order = 2000 } end
                    layout.castBar.position = v
                end,
                setOrder = function(v)
                    if not layout.castBar then layout.castBar = { position = "below", order = 2000 } end
                    layout.castBar.order = v
                end,
            })
        end
    end

    if not isVerticalLayout then
        for _, slot in ipairs(castSlots) do
            table.insert(resourceSlots, slot)
        end
        if #resourceSlots == 0 then
            local label = AceGUI:Create("Label")
            label:SetText("No active bars to order. Enable resources or Custom Bars first.")
            label:SetFullWidth(true)
            container:AddChild(label)
            return
        end
        RenderSlotOrdering(resourceSlots, nil, "above", "below", "Icons", "Up", "Down")
        return
    end

    if #resourceSlots == 0 and #castSlots == 0 then
        local label = AceGUI:Create("Label")
        label:SetText("No active bars to order. Enable resources, Custom Bars, or cast bar first.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    RenderSlotOrdering(resourceSlots, nil, "left", "right", "Icons", "Left", "Right")

    if #castSlots > 0 then
        local spacer = AceGUI:Create("Label")
        spacer:SetText(" ")
        spacer:SetFullWidth(true)
        container:AddChild(spacer)
        RenderSlotOrdering(castSlots, "Cast Bar", "above", "below", "Icons", "Up", "Down")
    end
end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildResourceBarAnchoringPanel = BuildResourceBarAnchoringPanel
ST._BuildResourceBarPositioningPanel = BuildResourceBarPositioningPanel
ST._BuildResourceBarStylingPanel = BuildResourceBarStylingPanel
ST._BuildResourceBarBarTextStylingPanel = BuildResourceBarBarTextStylingPanel
ST._BuildResourceBarColorsStylingPanel = BuildResourceBarColorsStylingPanel
ST._BuildResourceBarHealthStylingPanel = BuildResourceBarHealthStylingPanel
ST._BuildCustomBarsListPanel = BuildCustomBarsListPanel
ST._BuildCustomAuraBarPanel = BuildCustomAuraBarPanel
ST._BuildCustomBarSoundAlertsTab = BuildCustomBarSoundAlertsTab
ST._BuildCustomBarLoadConditionsTab = BuildCustomBarLoadConditionsTab
ST._BuildLayoutOrderPanel = BuildLayoutOrderPanel
