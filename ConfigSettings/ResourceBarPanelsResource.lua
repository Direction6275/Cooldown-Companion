--[[
    CooldownCompanion - ResourceBarPanelsResource
    Config panel builders for resource bar settings: anchoring, positioning,
    resource toggles, per-resource styling, and health styling.
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
local AddPreviewBadge = ST._AddPreviewBadge
local RefreshConfigPanelForPreviewToggle = ST._RefreshConfigPanelForPreviewToggle
local CleanRecycledEntry = ST._CleanRecycledEntry
local ApplyConfigRowIcon = ST._ApplyConfigRowIcon
local BindConfigShiftTooltip = ST._BindConfigShiftTooltip
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown
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
local DEFAULT_RESOURCE_RECHARGE_TEXT_ENABLED = RB.DEFAULT_RESOURCE_RECHARGE_TEXT_ENABLED
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
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
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
local AddResourceAuraOverrideControls = RBP.AddResourceAuraOverrideControls
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

local function EnsureResourceSettings(settings, powerType)
    if type(settings.resources) ~= "table" then
        settings.resources = {}
    end

    if powerType == HealthResource.ID then
        return HealthResource.EnsureSettings(settings)
    end

    if type(settings.resources[powerType]) ~= "table" then
        settings.resources[powerType] = {}
    end
    return settings.resources[powerType]
end

local function IsResourceEnabled(settings, powerType)
    local res = EnsureResourceSettings(settings, powerType)
    if powerType == HealthResource.ID then
        return res.enabled == true
    end
    return res.enabled ~= false
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
    local function BuildEffectStyleAdvanced(panel)
        AddColorPicker(panel, health, options.colorKey, options.colorLabel, options.defaultColor, true, applyBars, applyBars)
        HealthResource.AddEffectTextureDropdown(panel, health, options.textureKey, options.textureLabel, applyBars)
        if type(options.buildExtra) == "function" then
            options.buildExtra(panel)
        end
    end

    local expanded, advBtn = AddAdvancedToggle(checkbox, options.advancedKey, tabInfoButtons, enabled, {
        build = BuildEffectStyleAdvanced,
    })
    if not (enabled and expanded) then
        return expanded, advBtn
    end

    return expanded, advBtn
end

function HealthResource.BuildColorControls(container, settings, applyBars)
    local specID = GetCurrentConfigSpecID()
    if not specID then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
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
        buildExtra = function(panel)
            local missingHealthOnlyCb = AceGUI:Create("CheckBox")
            missingHealthOnlyCb:SetLabel("Pulse Missing Health Only")
            missingHealthOnlyCb:SetValue(health.healthLowHealthAlertMissingHealthOnly == true)
            missingHealthOnlyCb:SetFullWidth(true)
            missingHealthOnlyCb:SetCallback("OnValueChanged", function(widget, event, val)
                health.healthLowHealthAlertMissingHealthOnly = val == true
                applyBars()
            end)
            panel:AddChild(missingHealthOnlyCb)
        end,
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
        GameTooltip:AddLine("Copies shared resource bar settings from another spec into your current spec.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("What is copied:", 1, 0.82, 0, true)
        GameTooltip:AddLine("- Appearance tab", 1, 1, 1, true)
        GameTooltip:AddLine("- Layout tab", 1, 1, 1, true)
        GameTooltip:AddLine("- Resource colors", 1, 1, 1, true)
        GameTooltip:AddLine("- Resource Settings except aura overlays", 1, 1, 1, true)
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
        ST._ConfigureWrappedHelperLabel(label)
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
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            local name = POWER_NAMES[pt] or ("Power " .. pt)
            local enabled = IsResourceEnabled(settings, pt)

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
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Enable Resource Bars to configure positioning.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    if not layout then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
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
    local customHeightsAdvKey = "customResourceBarHeights"

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
        local wasEnabled = layout.customBarHeights == true
        layout.customBarHeights = val
        if val and not wasEnabled and CS.QueueAdvancedSettingsPanelOpen then
            CS.QueueAdvancedSettingsPanelOpen(customHeightsAdvKey)
        end
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RepositionCastBar()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(customHeightsCb)

    local function BuildCustomResourceHeightsAdvanced(panel)
        if type(layout.resources) ~= "table" then
            layout.resources = {}
        end

        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            local capturedPt = pt
            local name = POWER_NAMES[pt] or ("Power " .. pt)
            local enabled = IsResourceEnabled(settings, pt)
            local resLayout = type(layout.resources[capturedPt]) == "table" and layout.resources[capturedPt] or {}

            local resHeightSlider = AceGUI:Create("Slider")
            resHeightSlider:SetLabel(name .. " " .. thicknessLabel)
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
            if resHeightSlider.SetDisabled then
                resHeightSlider:SetDisabled(not enabled)
            end
            resHeightSlider:SetCallback("OnValueChanged", function(widget, event, val)
                if not enabled then
                    return
                end
                if type(layout.resources[capturedPt]) ~= "table" then
                    layout.resources[capturedPt] = {}
                end
                layout.resources[capturedPt][thicknessField] = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RepositionCastBar()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            panel:AddChild(resHeightSlider)
        end
    end

    local _, customHeightsAdvBtn = AddAdvancedToggle(customHeightsCb, customHeightsAdvKey, tabInfoButtons, layout.customBarHeights == true, {
        title = customThicknessLabel .. " Advanced",
        build = BuildCustomResourceHeightsAdvanced,
    })

    local customHeightsInfoAnchor = customHeightsCb.checkbg
    local customHeightsInfoOffset = customHeightsCb.text:GetStringWidth() + 4
    if customHeightsAdvBtn and customHeightsAdvBtn:IsShown() then
        customHeightsInfoAnchor = customHeightsAdvBtn
        customHeightsInfoOffset = 4
    end

    CreateInfoButton(customHeightsCb.frame, customHeightsInfoAnchor, "LEFT", "RIGHT", customHeightsInfoOffset, 0, {
        customThicknessLabel,
        {"When enabled, each resource can have its own bar size. Open advanced settings here to configure all resource sizes together.", 1, 1, 1, true},
    }, customHeightsCb)
end

ST._BuildBarHeightControls = BuildBarHeightControls

local function AddResourceColorDescriptor(descriptors, key, label, defaultColor, hasAlpha)
    descriptors[#descriptors + 1] = {
        key = key,
        label = label,
        defaultColor = defaultColor,
        hasAlpha = hasAlpha == true,
    }
end

local function GetResourceColorDescriptors(powerType, effectiveBarTextureName)
    local descriptors = {}
    if powerType == RESOURCE_HEALTH then
        return descriptors
    end

    if powerType == 4 then
        AddResourceColorDescriptor(descriptors, "comboColor", "Combo Points", DEFAULT_COMBO_COLOR, false)
        AddResourceColorDescriptor(descriptors, "comboMaxColor", "Combo Points (Max)", DEFAULT_COMBO_MAX_COLOR, false)
        local _, _, classID = UnitClass("player")
        if classID == 4 then
            AddResourceColorDescriptor(descriptors, "comboChargedColor", "Combo Points (Charged)", DEFAULT_COMBO_CHARGED_COLOR, false)
        end
    elseif powerType == 5 then
        AddResourceColorDescriptor(descriptors, "runeReadyColor", "Runes (Ready)", DEFAULT_RUNE_READY_COLOR, false)
        AddResourceColorDescriptor(descriptors, "runeRechargingColor", "Runes (Recharging)", DEFAULT_RUNE_RECHARGING_COLOR, false)
        AddResourceColorDescriptor(descriptors, "runeMaxColor", "Runes (All Ready)", DEFAULT_RUNE_MAX_COLOR, false)
    elseif powerType == 7 then
        AddResourceColorDescriptor(descriptors, "shardReadyColor", "Soul Shards (Ready)", DEFAULT_SHARD_READY_COLOR, false)
        AddResourceColorDescriptor(descriptors, "shardRechargingColor", "Soul Shards (Recharging)", DEFAULT_SHARD_RECHARGING_COLOR, false)
        AddResourceColorDescriptor(descriptors, "shardMaxColor", "Soul Shards (Max)", DEFAULT_SHARD_MAX_COLOR, false)
    elseif powerType == 9 then
        AddResourceColorDescriptor(descriptors, "holyColor", "Holy Power", DEFAULT_HOLY_COLOR, false)
        AddResourceColorDescriptor(descriptors, "holyMaxColor", "Holy Power (Max)", DEFAULT_HOLY_MAX_COLOR, false)
    elseif powerType == 12 then
        AddResourceColorDescriptor(descriptors, "chiColor", "Chi", DEFAULT_CHI_COLOR, false)
        AddResourceColorDescriptor(descriptors, "chiMaxColor", "Chi (Max)", DEFAULT_CHI_MAX_COLOR, false)
    elseif powerType == 16 then
        AddResourceColorDescriptor(descriptors, "arcaneColor", "Arcane Charges", DEFAULT_ARCANE_COLOR, false)
        AddResourceColorDescriptor(descriptors, "arcaneMaxColor", "Arcane Charges (Max)", DEFAULT_ARCANE_MAX_COLOR, false)
    elseif powerType == 19 then
        AddResourceColorDescriptor(descriptors, "essenceReadyColor", "Essence (Ready)", DEFAULT_ESSENCE_READY_COLOR, false)
        AddResourceColorDescriptor(descriptors, "essenceRechargingColor", "Essence (Recharging)", DEFAULT_ESSENCE_RECHARGING_COLOR, false)
        AddResourceColorDescriptor(descriptors, "essenceMaxColor", "Essence (Max)", DEFAULT_ESSENCE_MAX_COLOR, false)
    elseif powerType == 100 then
        AddResourceColorDescriptor(descriptors, "mwBaseColor", "MW (Base)", DEFAULT_MW_BASE_COLOR, false)
        AddResourceColorDescriptor(descriptors, "mwOverlayColor", "MW (Overlay)", DEFAULT_MW_OVERLAY_COLOR, false)
        AddResourceColorDescriptor(descriptors, "mwMaxColor", "MW (Max)", DEFAULT_MW_MAX_COLOR, false)
    elseif powerType == 101 then
        AddResourceColorDescriptor(descriptors, "staggerGreenColor", "Stagger (Low)", { 0.52, 0.90, 0.52 }, false)
        AddResourceColorDescriptor(descriptors, "staggerYellowColor", "Stagger (Medium)", { 1.0, 0.85, 0.36 }, false)
        AddResourceColorDescriptor(descriptors, "staggerRedColor", "Stagger (High)", { 1.0, 0.42, 0.42 }, false)
    elseif effectiveBarTextureName == "blizzard_class" and ST.POWER_ATLAS_TYPES and ST.POWER_ATLAS_TYPES[powerType] then
        return descriptors
    else
        AddResourceColorDescriptor(descriptors, "color", POWER_NAMES[powerType] or ("Power " .. powerType), DEFAULT_POWER_COLORS[powerType] or { 1, 1, 1 }, false)
    end

    return descriptors
end

local function BuildResourceColorControls(container, settings, powerType, specID, effectiveBarTextureName, applyBars)
    if not specID then
        return false
    end
    if not settings.resources[powerType] then
        settings.resources[powerType] = {}
    end

    local descriptors = GetResourceColorDescriptors(powerType, effectiveBarTextureName)
    if #descriptors == 0 then
        return false
    end

    local colorHeading = AceGUI:Create("Heading")
    colorHeading:SetText("Colors")
    ColorHeading(colorHeading)
    colorHeading:SetFullWidth(true)
    container:AddChild(colorHeading)

    local colorKey = "rb_colors_" .. tostring(powerType) .. "_" .. tostring(specID)
    local colorCollapsed = resourceBarCollapsedSections[colorKey]

    local colorCollapseBtn = AttachCollapseButton(colorHeading, colorCollapsed, function()
        resourceBarCollapsedSections[colorKey] = not resourceBarCollapsedSections[colorKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    colorHeading.right:ClearAllPoints()
    colorHeading.right:SetPoint("RIGHT", colorHeading.frame, "RIGHT", -3, 0)
    colorHeading.right:SetPoint("LEFT", colorCollapseBtn, "RIGHT", 4, 0)

    if colorCollapsed then
        return true
    end

    for _, descriptor in ipairs(descriptors) do
        local capturedKey = descriptor.key
        local capturedDefault = descriptor.defaultColor
        local proxy = {
            [capturedKey] = ReadSpecOverrideKey(settings, powerType, specID, capturedKey, capturedDefault),
        }
        AddColorPicker(container, proxy, capturedKey, descriptor.label, capturedDefault, descriptor.hasAlpha,
            function()
                WriteSpecOverrideKey(settings, powerType, specID, capturedKey, proxy[capturedKey])
                applyBars()
            end,
            function()
                WriteSpecOverrideKey(settings, powerType, specID, capturedKey, proxy[capturedKey])
            end)
    end

    return true
end

local function BuildResourceBarStylingPanel(container, sectionMode, opts)
    local settings = CooldownCompanion:GetResourceBarSettings()

    if not settings.enabled then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Enable Resource Bars to configure styling.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    local mode = sectionMode or "all"
    local resourceSettingsPowerType = opts and tonumber(opts.powerType) or nil
    local showResourceSettings = mode == "resource_settings" and resourceSettingsPowerType ~= nil
    local showBarText = (mode == "all" or mode == "bar_text" or showResourceSettings)
    local showHealthColors = (mode == "all" or mode == "health")
    local showAuraOverlays = (mode == "all")
    local showResourceText = showResourceSettings
    local showThresholdsTicks = false

    local applyBars = function() CooldownCompanion:ApplyResourceBars() end
    local healthResourceID = RESOURCE_HEALTH
    if showResourceSettings then
        local hasSegmentedThreshold = SEGMENTED_TYPES[resourceSettingsPowerType] == true or resourceSettingsPowerType == 100
        local hasContinuousTick = resourceSettingsPowerType ~= 101 and resourceSettingsPowerType ~= healthResourceID
        showThresholdsTicks = hasSegmentedThreshold or hasContinuousTick
    end
    local displaySpecID = opts and tonumber(opts.specID) or CS._GetCurrentConfigSpecID()
    local displayProfile = displaySpecID and CS._GetSpecResourceDisplayProfile(settings, displaySpecID) or nil
    if not displaySpecID or not displayProfile then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
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
    local localBarTextureName = displayProfile.barTexture or settings.barTexture or "Solid"
    local effectiveBarTextureName = ST.GetEffectiveBarTextureName(localBarTextureName)
    local _colorSpecID = displaySpecID

    if showResourceSettings then
        BuildResourceColorControls(container, settings, resourceSettingsPowerType, _colorSpecID, effectiveBarTextureName, applyBars)
    end

    if showBarText then
    if not showResourceSettings then
    -- Bar Texture
    local texDrop = AceGUI:Create("Dropdown")
    texDrop:SetLabel("Bar Texture")
    CS.SetupBarTextureDropdown(texDrop, { list = GetResourceBarTextureOptions() })
    texDrop:SetValue(localBarTextureName)
    texDrop:SetFullWidth(true)
    CS.SetBarTextureDropdownCallback(texDrop, function(widget, event, val)
        displayProfile.barTexture = val
        CooldownCompanion:ApplyResourceBars()
        -- Defer panel rebuild to next frame so it doesn't interfere with current callback
        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
    end)
    container:AddChild(texDrop)

    -- Brightness slider (only for Blizzard Class texture)
    if effectiveBarTextureName == "blizzard_class" then
        local brightSlider = AceGUI:Create("Slider")
        brightSlider:SetLabel("Class Texture Brightness")
        brightSlider:SetSliderValues(0.5, 2.0, 0.1)
        brightSlider:SetValue(displayProfile.classBarBrightness or settings.classBarBrightness or 1.3)
        brightSlider:SetFullWidth(true)
        brightSlider:SetDisabled(ST.IsBarTexturePickerLocked and ST.IsBarTexturePickerLocked())
        brightSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if ST.IsBarTexturePickerLocked and ST.IsBarTexturePickerLocked() then return end
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

        local renderMode = ST._AddBorderRenderModeDropdown(container, displayProfile, "borderRenderMode", function()
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end)
        local borderThicknessLocked = ST.IsBorderThicknessLocked()

        if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
            local borderSizeSlider = AceGUI:Create("Slider")
            borderSizeSlider:SetLabel("Border Size")
            borderSizeSlider:SetSliderValues(0, 4, 0.1)
            borderSizeSlider:SetValue(displayProfile.borderSize or settings.borderSize or 1)
            borderSizeSlider:SetIsPercent(false)
            borderSizeSlider:SetFullWidth(true)
            borderSizeSlider:SetDisabled(borderThicknessLocked)
            borderSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                if borderThicknessLocked then return end
                displayProfile.borderSize = val
                CooldownCompanion:ApplyResourceBars()
            end)
            container:AddChild(borderSizeSlider)
        end
    end
    end

    -- ============ Text Section ============
    if showResourceText then
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
        local resources = { resourceSettingsPowerType }
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

            local function BuildResourceTextAdvanced(panel)
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
                panel:AddChild(textFormatDrop)

                local fontDrop = AceGUI:Create("Dropdown")
                fontDrop:SetLabel("Font")
                CS.SetupFontDropdown(fontDrop)
                fontDrop:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "textFont", DEFAULT_RESOURCE_TEXT_FONT))
                fontDrop:SetFullWidth(true)
                CS.SetFontDropdownCallback(fontDrop, function(widget, event, val)
                    resSettings.textFont = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                panel:AddChild(fontDrop)

                local sizeDrop = AceGUI:Create("Slider")
                sizeDrop:SetLabel("Font Size")
                sizeDrop:SetSliderValues(6, 24, 1)
                sizeDrop:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "textFontSize", DEFAULT_RESOURCE_TEXT_SIZE))
                sizeDrop:SetFullWidth(true)
                sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    resSettings.textFontSize = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                panel:AddChild(sizeDrop)

                local outlineDrop = AceGUI:Create("Dropdown")
                outlineDrop:SetLabel("Outline")
                CS.SetupFontOutlineDropdown(outlineDrop)
                outlineDrop:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "textFontOutline", DEFAULT_RESOURCE_TEXT_OUTLINE))
                outlineDrop:SetFullWidth(true)
                CS.SetFontOutlineDropdownCallback(outlineDrop, function(widget, event, val)
                    resSettings.textFontOutline = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                panel:AddChild(outlineDrop)

                AddColorPicker(panel, resSettings, "textFontColor", "Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, applyBars)

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
                panel:AddChild(textAnchorDrop)

                local textXSlider = AceGUI:Create("Slider")
                textXSlider:SetLabel("Text X Offset")
                textXSlider:SetSliderValues(-50, 50, 0.1)
                textXSlider:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "textXOffset", DEFAULT_RESOURCE_TEXT_X_OFFSET))
                textXSlider:SetFullWidth(true)
                textXSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    resSettings.textXOffset = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                panel:AddChild(textXSlider)

                local textYSlider = AceGUI:Create("Slider")
                textYSlider:SetLabel("Text Y Offset")
                textYSlider:SetSliderValues(-50, 50, 0.1)
                textYSlider:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "textYOffset", DEFAULT_RESOURCE_TEXT_Y_OFFSET))
                textYSlider:SetFullWidth(true)
                textYSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    resSettings.textYOffset = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                panel:AddChild(textYSlider)

                if HIDE_AT_ZERO_ELIGIBLE[capturedPt] then
                    local hideAtZeroCb = AceGUI:Create("CheckBox")
                    hideAtZeroCb:SetLabel("Hide at 0")
                    hideAtZeroCb:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "hideTextAtZero", false) == true)
                    hideAtZeroCb:SetFullWidth(true)
                    hideAtZeroCb:SetCallback("OnValueChanged", function(widget, event, val)
                        resSettings.hideTextAtZero = val == true
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    panel:AddChild(hideAtZeroCb)
                end
            end

            local textAdvKey = "rbText_" .. capturedPt .. "_" .. tostring(displaySpecID)
            AddAdvancedToggle(cb, textAdvKey, rbTextAdvBtns, showTextEnabled, {
                title = name .. " Text Advanced",
                build = BuildResourceTextAdvanced,
                context = {
                    selectedResourcePowerType = capturedPt,
                    resourceSettingsSpecID = displaySpecID,
                },
            })

            if capturedPt == 5 then
                local rechargeEnabled = CS._ReadResourceDisplaySetting(baseSettings, resSettings, "showRechargeText", DEFAULT_RESOURCE_RECHARGE_TEXT_ENABLED) == true
                local rechargeCb = AceGUI:Create("CheckBox")
                rechargeCb:SetLabel("Show " .. name .. " Recharge Text")
                rechargeCb:SetValue(rechargeEnabled)
                rechargeCb:SetFullWidth(true)
                rechargeCb:SetCallback("OnValueChanged", function(widget, event, val)
                    resSettings.showRechargeText = val == true
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:RefreshConfigPanel()
                end)
                container:AddChild(rechargeCb)

                local function BuildRechargeTextAdvanced(panel)
                    local modeValue = CS._ReadResourceDisplaySetting(baseSettings, resSettings, "rechargeTextMode", "recharging")
                    if modeValue ~= "all" then
                        modeValue = "recharging"
                    end
                    local modeOptions = {
                        { value = "recharging", label = "Recharging Segments Only" },
                        { value = "all", label = "All Segments" },
                    }
                    for _, option in ipairs(modeOptions) do
                        local optionValue = option.value
                        local modeRadio = AceGUI:Create("CheckBox")
                        modeRadio:SetType("radio")
                        modeRadio:SetLabel(option.label)
                        modeRadio:SetValue(modeValue == optionValue)
                        modeRadio:SetFullWidth(true)
                        modeRadio:SetCallback("OnValueChanged", function(widget, event, val)
                            if val ~= true then
                                widget:SetValue(true)
                                return
                            end
                            resSettings.rechargeTextMode = optionValue
                            CooldownCompanion:ApplyResourceBars()
                            if CS.RefreshAdvancedSettingsPanel then
                                CS.RefreshAdvancedSettingsPanel()
                            end
                        end)
                        panel:AddChild(modeRadio)
                    end

                    local fontDrop = AceGUI:Create("Dropdown")
                    fontDrop:SetLabel("Font")
                    CS.SetupFontDropdown(fontDrop)
                    fontDrop:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "rechargeTextFont", DEFAULT_RESOURCE_TEXT_FONT))
                    fontDrop:SetFullWidth(true)
                    CS.SetFontDropdownCallback(fontDrop, function(widget, event, val)
                        resSettings.rechargeTextFont = val
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    panel:AddChild(fontDrop)

                    local sizeDrop = AceGUI:Create("Slider")
                    sizeDrop:SetLabel("Font Size")
                    sizeDrop:SetSliderValues(6, 24, 1)
                    sizeDrop:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "rechargeTextFontSize", DEFAULT_RESOURCE_TEXT_SIZE))
                    sizeDrop:SetFullWidth(true)
                    sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                        resSettings.rechargeTextFontSize = val
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    panel:AddChild(sizeDrop)

                    local outlineDrop = AceGUI:Create("Dropdown")
                    outlineDrop:SetLabel("Outline")
                    CS.SetupFontOutlineDropdown(outlineDrop)
                    outlineDrop:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "rechargeTextFontOutline", DEFAULT_RESOURCE_TEXT_OUTLINE))
                    outlineDrop:SetFullWidth(true)
                    CS.SetFontOutlineDropdownCallback(outlineDrop, function(widget, event, val)
                        resSettings.rechargeTextFontOutline = val
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    panel:AddChild(outlineDrop)

                    AddColorPicker(panel, resSettings, "rechargeTextFontColor", "Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, applyBars)

                    local anchorDrop = AceGUI:Create("Dropdown")
                    anchorDrop:SetLabel("Text Anchor")
                    local anchorValues = {}
                    for _, pt in ipairs(CS.anchorPoints) do
                        anchorValues[pt] = CS.anchorPointLabels[pt]
                    end
                    anchorDrop:SetList(anchorValues, CS.anchorPoints)
                    anchorDrop:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "rechargeTextAnchor", DEFAULT_RESOURCE_TEXT_ANCHOR))
                    anchorDrop:SetFullWidth(true)
                    anchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
                        resSettings.rechargeTextAnchor = val
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    panel:AddChild(anchorDrop)

                    local xSlider = AceGUI:Create("Slider")
                    xSlider:SetLabel("Text X Offset")
                    xSlider:SetSliderValues(-50, 50, 0.1)
                    xSlider:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "rechargeTextXOffset", DEFAULT_RESOURCE_TEXT_X_OFFSET))
                    xSlider:SetFullWidth(true)
                    xSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        resSettings.rechargeTextXOffset = val
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    panel:AddChild(xSlider)

                    local ySlider = AceGUI:Create("Slider")
                    ySlider:SetLabel("Text Y Offset")
                    ySlider:SetSliderValues(-50, 50, 0.1)
                    ySlider:SetValue(CS._ReadResourceDisplaySetting(baseSettings, resSettings, "rechargeTextYOffset", DEFAULT_RESOURCE_TEXT_Y_OFFSET))
                    ySlider:SetFullWidth(true)
                    ySlider:SetCallback("OnValueChanged", function(widget, event, val)
                        resSettings.rechargeTextYOffset = val
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    panel:AddChild(ySlider)
                end

                local rechargeAdvKey = "rbRechargeText_" .. capturedPt .. "_" .. tostring(displaySpecID)
                AddAdvancedToggle(rechargeCb, rechargeAdvKey, rbTextAdvBtns, rechargeEnabled, {
                    title = name .. " Recharge Text Advanced",
                    build = BuildRechargeTextAdvanced,
                    context = {
                        selectedResourcePowerType = capturedPt,
                        resourceSettingsSpecID = displaySpecID,
                    },
                })
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
            ST._ConfigureWrappedHelperLabel(label)
            label:SetText("Enable Health to configure health colors.")
            label:SetFullWidth(true)
            container:AddChild(label)
        end
    end

    if showThresholdsTicks then
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
        local resources = { resourceSettingsPowerType }
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
                    local thresholdAdvKey = "rbSegThreshold_" .. capturedPt .. "_" .. tostring(_colorSpecID)
                    local thresholdEnableCb = AceGUI:Create("CheckBox")
                    thresholdEnableCb:SetLabel("Enable " .. resourceName .. " Threshold Color")
                    thresholdEnableCb:SetValue(ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdEnabled", false) == true)
                    thresholdEnableCb:SetFullWidth(true)
                    thresholdEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
                        local wasEnabled = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdEnabled", false) == true
                        WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdEnabled", val == true)
                        if val and not wasEnabled and CS.QueueAdvancedSettingsPanelOpen then
                            CS.QueueAdvancedSettingsPanelOpen(thresholdAdvKey, {
                                selectedResourcePowerType = capturedPt,
                                resourceSettingsSpecID = _colorSpecID,
                            })
                        end
                        CooldownCompanion:ApplyResourceBars()
                        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
                    end)
                    container:AddChild(thresholdEnableCb)

                    local function BuildSegmentedThresholdAdvanced(panel)
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
                        panel:AddChild(thresholdEdit)

                        local _pSeg = { segThresholdColor = GetSafeRGBConfig(ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdColor", nil), DEFAULT_SEG_THRESHOLD_COLOR) }
                        AddColorPicker(panel, _pSeg, "segThresholdColor", resourceName .. " Threshold Color", DEFAULT_SEG_THRESHOLD_COLOR, false,
                            function() WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdColor", _pSeg.segThresholdColor); applyBars() end,
                            function() WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdColor", _pSeg.segThresholdColor) end)
                    end

                    local _segEnabled = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdEnabled", false) == true
                    local thresholdAdvExpanded = AddAdvancedToggle(
                        thresholdEnableCb,
                        thresholdAdvKey,
                        rbThresholdTickAdvBtns,
                        _segEnabled,
                        {
                            title = resourceName .. " Threshold Advanced",
                            build = BuildSegmentedThresholdAdvanced,
                            context = {
                                selectedResourcePowerType = capturedPt,
                                resourceSettingsSpecID = _colorSpecID,
                            },
                        }
                    )
                elseif capturedPt ~= 101 and capturedPt ~= healthResourceID then
                    -- Stagger (101) and Health have dedicated coloring; tick markers not applicable
                    local tickAdvKey = "rbTickMarker_" .. capturedPt .. "_" .. tostring(_colorSpecID)
                    local _tickEnabled = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickEnabled", false) == true
                    local tickEnableCb = AceGUI:Create("CheckBox")
                    tickEnableCb:SetLabel("Enable " .. resourceName .. " Tick Marker")
                    tickEnableCb:SetValue(_tickEnabled)
                    tickEnableCb:SetFullWidth(true)
                    tickEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
                        local wasEnabled = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickEnabled", false) == true
                        WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickEnabled", val == true)
                        if val and not wasEnabled and CS.QueueAdvancedSettingsPanelOpen then
                            CS.QueueAdvancedSettingsPanelOpen(tickAdvKey, {
                                selectedResourcePowerType = capturedPt,
                                resourceSettingsSpecID = _colorSpecID,
                            })
                        end
                        CooldownCompanion:ApplyResourceBars()
                        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
                    end)
                    container:AddChild(tickEnableCb)

                    local function BuildTickMarkerAdvanced(panel)
                        local tickCombatCb = AceGUI:Create("CheckBox")
                        tickCombatCb:SetLabel("Show Only In Combat")
                        tickCombatCb:SetValue(ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickCombatOnly", false))
                        tickCombatCb:SetFullWidth(true)
                        tickCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
                            WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickCombatOnly", val == true)
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(tickCombatCb)

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
                            C_Timer.After(0, function()
                                if CS.RefreshAdvancedSettingsPanel then
                                    CS.RefreshAdvancedSettingsPanel()
                                end
                            end)
                        end)
                        panel:AddChild(modeDrop)

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
                            panel:AddChild(percentSlider)
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
                            panel:AddChild(absoluteEdit)
                        end

                        local _tickColorResolved = GetSafeRGBAConfig(ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickColor", nil), DEFAULT_CONTINUOUS_TICK_COLOR)
                        if _tickColorResolved[4] == nil then _tickColorResolved = { _tickColorResolved[1], _tickColorResolved[2], _tickColorResolved[3], 1 } end
                        local _pTick = { continuousTickColor = _tickColorResolved }
                        AddColorPicker(panel, _pTick, "continuousTickColor", resourceName .. " Tick Color", DEFAULT_CONTINUOUS_TICK_COLOR, true,
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
                        panel:AddChild(tickWidthSlider)
                    end

                    local tickAdvExpanded = AddAdvancedToggle(
                        tickEnableCb,
                        tickAdvKey,
                        rbThresholdTickAdvBtns,
                        _tickEnabled,
                        {
                            title = resourceName .. " Tick Marker Advanced",
                            build = BuildTickMarkerAdvanced,
                            context = {
                                selectedResourcePowerType = capturedPt,
                                resourceSettingsSpecID = _colorSpecID,
                            },
                        }
                    )
                end
            end
        end
    end

    end

    if showResourceSettings then
        local auraHeading = AceGUI:Create("Heading")
        auraHeading:SetText("Aura Overlay")
        ColorHeading(auraHeading)
        auraHeading:SetFullWidth(true)
        container:AddChild(auraHeading)

        local rbAuraOverlayAdvBtns = {}
        local resourceName = POWER_NAMES[resourceSettingsPowerType] or ("Power " .. resourceSettingsPowerType)
        AddResourceAuraOverrideControls(container, settings, resourceSettingsPowerType, resourceName, rbAuraOverlayAdvBtns, {
            specID = displaySpecID,
            context = {
                selectedResourcePowerType = resourceSettingsPowerType,
                resourceSettingsSpecID = displaySpecID,
            },
        })
    end

    if showAuraOverlays then
        BuildResourceAuraOverlaySection(container, settings)
    end

end

local function BuildResourceSettingsPanel(container, powerType, specID)
    local numericPowerType = tonumber(powerType)
    local numericSpecID = tonumber(specID)
    if not numericPowerType or not numericSpecID then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Specialization data loading...")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    BuildResourceBarStylingPanel(container, "resource_settings", {
        powerType = numericPowerType,
        specID = numericSpecID,
    })
end

local function BuildResourceBarBarTextStylingPanel(container)
    BuildResourceBarStylingPanel(container, "bar_text")
end

local function BuildResourceBarHealthStylingPanel(container)
    BuildResourceBarStylingPanel(container, "health")
end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildResourceBarAnchoringPanel = BuildResourceBarAnchoringPanel
ST._BuildResourceBarPositioningPanel = BuildResourceBarPositioningPanel
ST._BuildResourceBarStylingPanel = BuildResourceBarStylingPanel
ST._BuildResourceBarBarTextStylingPanel = BuildResourceBarBarTextStylingPanel
ST._BuildResourceBarHealthStylingPanel = BuildResourceBarHealthStylingPanel
ST._BuildResourceSettingsPanel = BuildResourceSettingsPanel
