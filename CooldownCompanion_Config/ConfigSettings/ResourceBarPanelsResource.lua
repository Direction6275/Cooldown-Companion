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
local ShowPopupAboveConfig = CS.ShowPopupAboveConfig

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local ApplyLeftAlignedHeading = ST._ApplyLeftAlignedHeading
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local AddAnchorDropdown = ST._AddAnchorDropdown
local BuildAlphaControls = ST._BuildAlphaControls
local BuildIndependentAnchorTargetRow = ST._BuildIndependentAnchorTargetRow
local AnchorLeftAlignedHeadingRule = ST._AnchorLeftAlignedHeadingRule
local tabInfoButtons = CS.tabInfoButtons

-- Imports from RowWidgets.lua (the row grammar). The rules every row-grammar
-- section follows are stated once, in the recipe comment at the top of
-- BuildAppearanceTab's icons path (GroupTabs.lua); this file conforms to them
-- rather than restating them.
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddColorRow = ST._AddColorRow
local AddEditBoxRow = ST._AddEditBoxRow
local AddLabelRow = ST._AddLabelRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid

-- The workspace Live Preview does not rebuild with the settings column, so
-- rows whose effect is visible on the canvas re-render it directly (the
-- custom-bars panel's pattern). Late-bound: the helper self-gates on view
-- state and may not exist in every load order.
local function RefreshLayoutOrderPreview()
    if ST._RefreshResourcesLayoutPreview then
        ST._RefreshResourcesLayoutPreview()
    end
end

-- Mirror-first slider wiring and its drag-tick repaint (owner ruling
-- 2026-08-02, contract stated once in ResourceBarPanelsHelpers.lua). That file
-- loads before this one, so both alias at file scope.
local AddMirrorFirstSliderRow = ST._AddMirrorFirstSliderRow
local RefreshLayoutOrderPreviewForDrag = ST._RefreshResourcesCanvasForDrag

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

-- Per-style slider rows shared with every other glow surface
-- (SectionBuilders GLOW_SLIDER_SPEC): the border styles draw the same
-- sliders everywhere, only the store differs.
local AddGlowSliderRows = ST._AddGlowSliderRows
local CleanRecycledEntry = ST._CleanRecycledEntry
local AURA_BORDER_SLIDER_KEYS = {
    size = "auraBorderSize",
    thickness = "auraBorderThickness",
    speed = "auraBorderSpeed",
    lines = "auraBorderLines",
    solidSizeDefault = 2,
}
local MW_BORDER_SLIDER_KEYS = {
    size = "mwMaxStackBorderSize",
    thickness = "mwMaxStackBorderThickness",
    speed = "mwMaxStackBorderSpeed",
    lines = "mwMaxStackBorderLines",
    solidSizeDefault = 2,
}

-- LibSharedMedia names run well past the 140px control column, and a dropdown
-- sizes its menu from the control. Without this the texture picker would open
-- a 140px-wide menu of truncated names.
local MEDIA_PULLOUT_WIDTH = 300

-- Shared constants from ResourceBarConstants
local RB = ST._RB
local POWER_NAMES = RB.POWER_NAMES
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local HIDE_AT_ZERO_ELIGIBLE = RB.HIDE_AT_ZERO_ELIGIBLE
local DEFAULT_POWER_COLORS = RB.DEFAULT_POWER_COLORS
local DEFAULT_MW_BASE_COLOR = RB.DEFAULT_MW_BASE_COLOR
local DEFAULT_MW_OVERLAY_COLOR = RB.DEFAULT_MW_OVERLAY_COLOR
local DEFAULT_MW_MAX_COLOR = RB.DEFAULT_MW_MAX_COLOR
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = RB.DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
local SupportsResourceAuraStackMode = RB.SupportsResourceAuraStackMode
local ClassifyAuraSpellUnit = ST._ClassifyAuraSpellUnit
local DEFAULT_RESOURCE_TEXT_FORMAT = RB.DEFAULT_RESOURCE_TEXT_FORMAT
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
local MAX_RESOURCE_THRESHOLD_TICK_ENTRIES = RB.MAX_RESOURCE_THRESHOLD_TICK_ENTRIES or 3
local ClampSegmentedThresholdValue = RB.ClampSegmentedThresholdValue
local ClampContinuousTickPercentValue = RB.ClampContinuousTickPercentValue
local ClampContinuousTickAbsoluteValue = RB.ClampContinuousTickAbsoluteValue
local GetNormalizedSegmentedThresholdEntriesFromConfig = RB.GetNormalizedSegmentedThresholdEntriesFromConfig
local GetNormalizedContinuousTickEntriesFromConfig = RB.GetNormalizedContinuousTickEntriesFromConfig
local ResolveSpecEntryList = RB.ResolveSpecEntryList
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
local GetResourceSpecOverrideTable = RB.GetResourceSpecOverrideTable
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
local RESOURCE_HEALTH_DISPLAY_KEYS = RB.RESOURCE_HEALTH_DISPLAY_KEYS
local resourceSpecCopyButton
local resourceSpecCopyMenu
local thresholdTickDraftRows = {}
local thresholdTickEditorErrors = {}

-- Imports from ResourceBarPanelsHelpers
local RBP = ST._RBP
local resourceBarCollapsedSections = RBP.collapsedSections
local CopyTableValue = RBP.CopyTableValue
local BuildResourceBarConflictGate = RBP.BuildResourceBarConflictGate
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
local IsResourceBarVerticalConfig = RBP.IsResourceBarVerticalConfig
local GetResourceThicknessFieldConfig = RBP.GetResourceThicknessFieldConfig
local GetResourceGapFieldConfig = RBP.GetResourceGapFieldConfig
local ResolveTrackedAuraSpellIDFromText = RBP.ResolveTrackedAuraSpellIDFromText
local BuildTrackedAuraAutocompleteCache = RBP.BuildTrackedAuraAutocompleteCache

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

-- Row grammar has no percent readout (the value box is the readout, and the
-- range lives in the row tooltip), so this reads 0 - 1 rather than 0% - 100%.
-- The stored value is unchanged, and Baseline Alpha already reads that way.
function HealthResource.AddOpacitySlider(container, health, key, label, defaultValue, applyBars)
    -- The canvas draws the health bar with the real health styler, so both
    -- opacities land there; applyBars is the caller's commit chain.
    AddMirrorFirstSliderRow(container, {
        label = label,
        min = 0, max = 1, step = 0.05,
        value = tonumber(health[key]) or defaultValue,
        set = function(val) health[key] = val end,
        apply = applyBars,
    })
end

function HealthResource.AddEffectTextureDropdown(container, health, key, label, applyBars)
    local textureOptions, textureOrder = HealthResource.GetEffectTextureOptions()
    return AddDropdownRow(container, {
        label = label,
        pulloutWidth = MEDIA_PULLOUT_WIDTH,
        list = textureOptions,
        order = textureOrder,
        value = health[key] or DEFAULT_HEALTH_EFFECT_TEXTURE,
        onChange = function(val)
            health[key] = val or DEFAULT_HEALTH_EFFECT_TEXTURE
            applyBars()
        end,
    })
end

function HealthResource.AddEffectStyleControls(container, checkbox, health, options, applyBars)
    local enabled = health[options.enabledKey] == true
    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- both rows go straight onto the panel scroll. The toggle these belong to
    -- lives back on the tab, so neither indents.
    local function BuildEffectStyleAdvanced(panel)
        -- deferCommit is deliberately absent, matching the stock color-picker call
        -- this row replaced.
        AddColorRow(panel, {
            label = options.colorLabel,
            tbl = health,
            key = options.colorKey,
            default = options.defaultColor,
            hasAlpha = true,
            onConfirm = applyBars,
            onChange = applyBars,
        })
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

local function IsHealthTextFormat(textFormat)
    return textFormat == "percent"
        or textFormat == "percent_no_sign"
        or textFormat == "current"
        or textFormat == "current_max"
        or textFormat == "current_percent"
        or textFormat == "current_percent_no_sign"
end

local function BuildResourceTextControls(container, settings, powerType, displaySpecID, applyBars, collapsedKey)
    local rbTextAdvBtns = {}

    local textKey = collapsedKey or "rb_text"
    local _, textCollapsed = BuildCollapsibleSection(container, "Text", textKey, resourceBarCollapsedSections, nil, ROW_SECTION)

    if textCollapsed then
        return
    end

    local capturedPt = powerType
    local isHealthResource = capturedPt == HealthResource.ID
    local isSegmentedResource = (SEGMENTED_TYPES[capturedPt] == true) or (capturedPt == 100)
    if isHealthResource then
        HealthResource.EnsureSettings(settings)
    else
        EnsureResourceSettings(settings, capturedPt)
    end
    local baseSettings = settings.resources[capturedPt]
    local resSettings = SeedSpecResourceDisplaySettings(settings, capturedPt, displaySpecID, CS._ResourceTextDisplayKeys) or baseSettings
    local name = POWER_NAMES[capturedPt] or ("Power " .. capturedPt)

    local showTextValue = ReadDisplaySetting(baseSettings, resSettings, "showText", nil)
    local showTextEnabled
    if isHealthResource or isSegmentedResource then
        showTextEnabled = showTextValue == true
    else
        showTextEnabled = showTextValue ~= false
    end

    -- LEFT column: the resource's own value text. RIGHT column: the recharge
    -- readout, which only runes have - every other resource leaves it empty,
    -- and the grid top-aligns its columns, so a short side just ends early.
    local textLeft, textRight = BeginRowGrid(container)

    local cb = AddCheckboxRow(textLeft, {
        label = "Show " .. name .. " Text",
        value = showTextEnabled,
        onChange = function(val)
            resSettings.showText = val == true
            if isHealthResource and not IsHealthTextFormat(resSettings.textFormat) then
                resSettings.textFormat = "percent"
            end
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- every row goes straight onto the panel scroll. The Show <resource> Text
    -- toggle these belong to lives back on the tab, so none of them indents.
    --
    -- The font trio is hand-written rather than routed through AddFontControls:
    -- these values read through ReadDisplaySetting (spec override first, then
    -- the base resource table), which the shared helper's plain tbl[key] read
    -- cannot express.
    local function BuildResourceTextAdvanced(panel)
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
        local textFormatValue = ReadDisplaySetting(baseSettings, resSettings, "textFormat", isHealthResource and "percent" or DEFAULT_RESOURCE_TEXT_FORMAT)
        if isHealthResource then
            if not IsHealthTextFormat(textFormatValue) then
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
        AddDropdownRow(panel, {
            label = "Text Format",
            pulloutWidth = MEDIA_PULLOUT_WIDTH,
            list = textFormatOptions,
            order = textFormatOrder,
            value = textFormatValue,
            onChange = function(val)
                if isHealthResource then
                    if IsHealthTextFormat(val) then
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
                applyBars()
            end,
        })

        -- Font Size / Font / Font Outline, in that order and with those
        -- labels: the shape AddFontControls emits in every other popout. The
        -- trio stays hand-written here because these values read through
        -- ReadDisplaySetting (spec override first, then the base resource
        -- table), which the shared helper's flat tbl[key] read cannot express.
        -- Every row from here down draws on the canvas: it renders these bars
        -- with the real bar styler, which sets the value text's font, colour,
        -- anchor and offsets from exactly these keys.
        AddMirrorFirstSliderRow(panel, {
            label = "Font Size",
            min = 6, max = 24, step = 1,
            value = ReadDisplaySetting(baseSettings, resSettings, "textFontSize", DEFAULT_RESOURCE_TEXT_SIZE),
            set = function(val) resSettings.textFontSize = val end,
            apply = applyBars,
        })

        -- FONT ROW: created with a label and a widened pullout but NO list and
        -- NO onChange, then handed to the shared font helpers exactly as a
        -- stock Dropdown would be. The value is set AFTER SetupFontDropdown,
        -- because SetList rebuilds the list the displayed text is read from.
        local fontRow = AddDropdownRow(panel, {
            label = "Font",
            pulloutWidth = MEDIA_PULLOUT_WIDTH,
        })
        CS.SetupFontDropdown(fontRow)
        fontRow:SetValue(ReadDisplaySetting(baseSettings, resSettings, "textFont", DEFAULT_RESOURCE_TEXT_FONT))
        CS.SetFontDropdownCallback(fontRow, function(widget, event, val)
            resSettings.textFont = val
            applyBars()
        end)

        local outlineRow = AddDropdownRow(panel, { label = "Font Outline" })
        CS.SetupFontOutlineDropdown(outlineRow)
        outlineRow:SetValue(ReadDisplaySetting(baseSettings, resSettings, "textFontOutline", DEFAULT_RESOURCE_TEXT_OUTLINE))
        CS.SetFontOutlineDropdownCallback(outlineRow, function(widget, event, val)
            resSettings.textFontOutline = val
            applyBars()
        end)

        -- deferCommit is deliberately absent, matching the stock color-picker call
        -- this row replaced. onChange is new: it is the only path that fires
        -- while the picker is open, and the canvas tracks the colour there.
        AddColorRow(panel, {
            label = "Text Color",
            tbl = resSettings,
            key = "textFontColor",
            default = DEFAULT_RESOURCE_TEXT_COLOR,
            hasAlpha = true,
            onConfirm = applyBars,
            onChange = RefreshLayoutOrderPreviewForDrag,
        })

        -- CS.anchorDropdownList is built from CS.anchorPointLabels over exactly
        -- CS.anchorPoints (State.lua), which is the table this call site used to
        -- rebuild by hand on every render.
        AddDropdownRow(panel, {
            label = "Text Anchor",
            list = CS.anchorDropdownList,
            order = CS.anchorPoints,
            value = ReadDisplaySetting(baseSettings, resSettings, "textAnchor", DEFAULT_RESOURCE_TEXT_ANCHOR),
            onChange = function(val)
                resSettings.textAnchor = val
                applyBars()
            end,
        })

        AddMirrorFirstSliderRow(panel, {
            label = "Text X Offset",
            min = -50, max = 50, step = 0.1,
            value = ReadDisplaySetting(baseSettings, resSettings, "textXOffset", DEFAULT_RESOURCE_TEXT_X_OFFSET),
            set = function(val) resSettings.textXOffset = val end,
            apply = applyBars,
        })

        AddMirrorFirstSliderRow(panel, {
            label = "Text Y Offset",
            min = -50, max = 50, step = 0.1,
            value = ReadDisplaySetting(baseSettings, resSettings, "textYOffset", DEFAULT_RESOURCE_TEXT_Y_OFFSET),
            set = function(val) resSettings.textYOffset = val end,
            apply = applyBars,
        })

        if HIDE_AT_ZERO_ELIGIBLE[capturedPt] then
            AddCheckboxRow(panel, {
                label = "Hide at 0",
                value = ReadDisplaySetting(baseSettings, resSettings, "hideTextAtZero", false) == true,
                onChange = function(val)
                    resSettings.hideTextAtZero = val == true
                    applyBars()
                end,
            })
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

    if capturedPt ~= 5 then
        return
    end

    local rechargeEnabled = ReadDisplaySetting(baseSettings, resSettings, "showRechargeText", DEFAULT_RESOURCE_RECHARGE_TEXT_ENABLED) == true
    local rechargeCb = AddCheckboxRow(textRight, {
        label = "Show " .. name .. " Recharge Text",
        value = rechargeEnabled,
        onChange = function(val)
            resSettings.showRechargeText = val == true
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail, same read/write contract as the value-text panel above.
    --
    -- The mode is a dropdown row rather than the pre-redesign pair of radio
    -- checkboxes: the row grammar has no radio row, and one row naming the
    -- choice says the same thing two mutually exclusive rows did. Same store,
    -- same two values, same rebuild on change.
    local RECHARGE_TEXT_MODES = {
        recharging = "Recharging Segments Only",
        all = "All Segments",
    }
    local RECHARGE_TEXT_MODE_ORDER = { "recharging", "all" }

    local function BuildRechargeTextAdvanced(panel)
        local modeValue = ReadDisplaySetting(baseSettings, resSettings, "rechargeTextMode", "recharging")
        if modeValue ~= "all" then
            modeValue = "recharging"
        end

        AddDropdownRow(panel, {
            label = "Show Recharge Text On",
            pulloutWidth = MEDIA_PULLOUT_WIDTH,
            list = RECHARGE_TEXT_MODES,
            order = RECHARGE_TEXT_MODE_ORDER,
            value = modeValue,
            onChange = function(val)
                resSettings.rechargeTextMode = (val == "all") and "all" or "recharging"
                CooldownCompanion:ApplyResourceBars()
                if CS.RefreshAdvancedSettingsPanel then
                    CS.RefreshAdvancedSettingsPanel()
                end
            end,
        })

        -- Same canonical trio order and labels as the resource text popout
        -- above, and hand-written for the same ReadDisplaySetting reason.
        AddSliderRow(panel, {
            label = "Font Size",
            min = 6, max = 24, step = 1,
            value = ReadDisplaySetting(baseSettings, resSettings, "rechargeTextFontSize", DEFAULT_RESOURCE_TEXT_SIZE),
            onChange = function(val)
                resSettings.rechargeTextFontSize = val
                CooldownCompanion:ApplyResourceBars()
            end,
        })

        local fontRow = AddDropdownRow(panel, {
            label = "Font",
            pulloutWidth = MEDIA_PULLOUT_WIDTH,
        })
        CS.SetupFontDropdown(fontRow)
        fontRow:SetValue(ReadDisplaySetting(baseSettings, resSettings, "rechargeTextFont", DEFAULT_RESOURCE_TEXT_FONT))
        CS.SetFontDropdownCallback(fontRow, function(widget, event, val)
            resSettings.rechargeTextFont = val
            CooldownCompanion:ApplyResourceBars()
        end)

        local outlineRow = AddDropdownRow(panel, { label = "Font Outline" })
        CS.SetupFontOutlineDropdown(outlineRow)
        outlineRow:SetValue(ReadDisplaySetting(baseSettings, resSettings, "rechargeTextFontOutline", DEFAULT_RESOURCE_TEXT_OUTLINE))
        CS.SetFontOutlineDropdownCallback(outlineRow, function(widget, event, val)
            resSettings.rechargeTextFontOutline = val
            CooldownCompanion:ApplyResourceBars()
        end)

        -- deferCommit and onChange are deliberately absent, matching the
        -- stock color-picker call this row replaced.
        AddColorRow(panel, {
            label = "Text Color",
            tbl = resSettings,
            key = "rechargeTextFontColor",
            default = DEFAULT_RESOURCE_TEXT_COLOR,
            hasAlpha = true,
            onConfirm = applyBars,
        })

        AddDropdownRow(panel, {
            label = "Text Anchor",
            list = CS.anchorDropdownList,
            order = CS.anchorPoints,
            value = ReadDisplaySetting(baseSettings, resSettings, "rechargeTextAnchor", DEFAULT_RESOURCE_TEXT_ANCHOR),
            onChange = function(val)
                resSettings.rechargeTextAnchor = val
                CooldownCompanion:ApplyResourceBars()
            end,
        })

        AddSliderRow(panel, {
            label = "Text X Offset",
            min = -50, max = 50, step = 0.1,
            value = ReadDisplaySetting(baseSettings, resSettings, "rechargeTextXOffset", DEFAULT_RESOURCE_TEXT_X_OFFSET),
            onChange = function(val)
                resSettings.rechargeTextXOffset = val
                CooldownCompanion:ApplyResourceBars()
            end,
        })

        AddSliderRow(panel, {
            label = "Text Y Offset",
            min = -50, max = 50, step = 0.1,
            value = ReadDisplaySetting(baseSettings, resSettings, "rechargeTextYOffset", DEFAULT_RESOURCE_TEXT_Y_OFFSET),
            onChange = function(val)
                resSettings.rechargeTextYOffset = val
                CooldownCompanion:ApplyResourceBars()
            end,
        })
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

    local healthFillKey = "rb_health_fill"
    local _, healthFillCollapsed = BuildCollapsibleSection(container, "Health", healthFillKey, resourceBarCollapsedSections, nil, ROW_SECTION)

    if not healthFillCollapsed then
        -- LEFT column: the gradient choice and the colors it decides - they
        -- have to be read together, so they stay adjacent and the colors are
        -- indented children of the toggle above them. RIGHT column: the one
        -- setting the choice does not touch.
        local fillLeft, fillRight = BeginRowGrid(container)

        AddCheckboxRow(fillLeft, {
            label = "Use Health Gradient",
            value = fillGradientEnabled == true,
            onChange = function(val)
                health.healthBarGradient = val == true
                applyBars()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if fillGradientEnabled == true then
            AddColorRow(fillLeft, { label = "Full Health", indent = true, tbl = health, key = "healthBarFullColor", default = DEFAULT_HEALTH_BAR_FULL_COLOR, onConfirm = applyBars, onChange = applyBars })
            AddColorRow(fillLeft, { label = "Half Health", indent = true, tbl = health, key = "healthBarHalfColor", default = DEFAULT_HEALTH_BAR_HALF_COLOR, onConfirm = applyBars, onChange = applyBars })
            AddColorRow(fillLeft, { label = "Low Health", indent = true, tbl = health, key = "healthBarLowColor", default = DEFAULT_HEALTH_BAR_LOW_COLOR, onConfirm = applyBars, onChange = applyBars })
        else
            AddColorRow(fillLeft, { label = "Health Color", indent = true, tbl = health, key = "healthBarColor", default = DEFAULT_HEALTH_BAR_COLOR, onConfirm = applyBars, onChange = applyBars })
        end
        HealthResource.AddOpacitySlider(fillRight, health, "healthBarOpacity", "Health Opacity", DEFAULT_HEALTH_BAR_OPACITY, applyBars)
    end

    local healthMissingKey = "rb_health_missing"
    local missingHeading, healthMissingCollapsed = BuildCollapsibleSection(container, "Missing Health", healthMissingKey, resourceBarCollapsedSections, nil, ROW_SECTION)
    local missingInfoBtn = CreateInfoButton(missingHeading.frame, missingHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Missing Health",
        {"Resource Background Color is used by regular resource bars. Health uses Missing Health for its empty region.", 1, 1, 1, true},
    }, missingHeading)
    AnchorLeftAlignedHeadingRule(missingHeading, missingInfoBtn)

    if not healthMissingCollapsed then
        -- Same split as the fill section above, for the same reason.
        local missingLeft, missingRight = BeginRowGrid(container)

        AddCheckboxRow(missingLeft, {
            label = "Use Missing Health Gradient",
            value = gradientEnabled == true,
            onChange = function(val)
                health.healthBackgroundGradient = val == true
                applyBars()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if gradientEnabled == true then
            AddColorRow(missingLeft, { label = "Missing Health Full", indent = true, tbl = health, key = "healthBackgroundFullColor", default = DEFAULT_HEALTH_BACKGROUND_FULL_COLOR, onConfirm = applyBars, onChange = applyBars })
            AddColorRow(missingLeft, { label = "Missing Health Half", indent = true, tbl = health, key = "healthBackgroundHalfColor", default = DEFAULT_HEALTH_BACKGROUND_HALF_COLOR, onConfirm = applyBars, onChange = applyBars })
            AddColorRow(missingLeft, { label = "Missing Health Low", indent = true, tbl = health, key = "healthBackgroundLowColor", default = DEFAULT_HEALTH_BACKGROUND_LOW_COLOR, onConfirm = applyBars, onChange = applyBars })
        else
            AddColorRow(missingLeft, { label = "Missing Health Color", indent = true, tbl = health, key = "healthBackgroundColor", default = DEFAULT_HEALTH_BACKGROUND_COLOR, onConfirm = applyBars, onChange = applyBars })
        end

        HealthResource.AddOpacitySlider(missingRight, health, "healthBackgroundOpacity", "Missing Health Opacity", DEFAULT_HEALTH_BACKGROUND_OPACITY, applyBars)
    end

    BuildResourceTextControls(container, settings, HealthResource.ID, specID, applyBars, "rb_health_text")

    local healthEffectsKey = "rb_health_effects"
    local _, healthEffectsCollapsed = BuildCollapsibleSection(container, "Health Effects", healthEffectsKey, resourceBarCollapsedSections, nil, ROW_SECTION)

    if healthEffectsCollapsed then
        return
    end

    -- LEFT column: the two shield-shaped effects drawn over the fill. RIGHT
    -- column: the incoming-heal preview and the alert that recolors the bar.
    local effectsLeft, effectsRight = BeginRowGrid(container)

    local absorbsCb = AddCheckboxRow(effectsLeft, {
        label = "Show Absorbs",
        value = health.showAbsorbs == true,
        onChange = function(val)
            health.showAbsorbs = val == true
            applyBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    HealthResource.AddEffectStyleControls(effectsLeft, absorbsCb, health, {
        enabledKey = "showAbsorbs",
        advancedKey = "healthAbsorbs",
        colorKey = "healthAbsorbColor",
        textureKey = "healthAbsorbTexture",
        colorLabel = "Absorb Color",
        textureLabel = "Absorb Texture",
        defaultColor = DEFAULT_HEALTH_ABSORB_COLOR,
    }, applyBars)

    local healAbsorbsCb = AddCheckboxRow(effectsLeft, {
        label = "Show Healing Absorbs",
        value = health.showHealAbsorbs == true,
        onChange = function(val)
            health.showHealAbsorbs = val == true
            applyBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    HealthResource.AddEffectStyleControls(effectsLeft, healAbsorbsCb, health, {
        enabledKey = "showHealAbsorbs",
        advancedKey = "healthHealAbsorbs",
        colorKey = "healthHealAbsorbColor",
        textureKey = "healthHealAbsorbTexture",
        colorLabel = "Healing Absorb Color",
        textureLabel = "Healing Absorb Texture",
        defaultColor = DEFAULT_HEALTH_HEAL_ABSORB_COLOR,
    }, applyBars)

    local incomingHealsCb = AddCheckboxRow(effectsRight, {
        label = "Show Incoming Heals",
        value = health.showIncomingHeals == true,
        onChange = function(val)
            health.showIncomingHeals = val == true
            applyBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    HealthResource.AddEffectStyleControls(effectsRight, incomingHealsCb, health, {
        enabledKey = "showIncomingHeals",
        advancedKey = "healthIncomingHeals",
        colorKey = "healthIncomingHealColor",
        textureKey = "healthIncomingHealTexture",
        colorLabel = "Incoming Heal Color",
        textureLabel = "Incoming Heal Texture",
        defaultColor = DEFAULT_HEALTH_INCOMING_HEAL_COLOR,
    }, applyBars)

    local lowHealthAlertCb = AddCheckboxRow(effectsRight, {
        label = "Show Low Health Alert",
        value = health.showLowHealthAlert == true,
        onChange = function(val)
            health.showLowHealthAlert = val == true
            applyBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    HealthResource.AddEffectStyleControls(effectsRight, lowHealthAlertCb, health, {
        enabledKey = "showLowHealthAlert",
        advancedKey = "healthLowHealthAlert",
        colorKey = "healthLowHealthAlertColor",
        textureKey = "healthLowHealthAlertTexture",
        colorLabel = "Low Health Alert Color",
        textureLabel = "Low Health Alert Texture",
        defaultColor = DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR,
        buildExtra = function(panel)
            AddCheckboxRow(panel, {
                label = "Pulse Missing Health Only",
                value = health.healthLowHealthAlertMissingHealthOnly == true,
                onChange = function(val)
                    health.healthLowHealthAlertMissingHealthOnly = val == true
                    applyBars()
                end,
            })
        end,
    }, applyBars)
    -- Second badge after the gear when the setting is on, first when it is off:
    -- AddAdvancedToggle only chains a gear it actually shows, so the anchor
    -- args below are a placeholder - AnchorRowBadge re-points the button.
    AnchorRowBadge(lowHealthAlertCb, CreateInfoButton(lowHealthAlertCb.frame, lowHealthAlertCb.frame, "LEFT", "LEFT", 0, 0, {
        "Low Health Alert",
        {"Blizzard sets the low-health threshold to 35%. This cannot be configured.", 1, 1, 1, true},
    }, lowHealthAlertCb))
end

CS.healthResourceUI = HealthResource

local function AddResourceSpecCopyButton(enableCb)
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

    -- A badge on the row's label, chained off the end of the label text like
    -- every other row-grammar badge. AnchorRowBadge does the ClearAllPoints.
    AnchorRowBadge(enableCb, btn)
    btn:Show()

    -- The singleton is a plain child of a pooled row frame: without this it
    -- survives the row's release and surfaces on whatever row the pool hands
    -- that frame next (the badge-leak class). Same OnRelease chain as
    -- CreateInfoButton's AceGUI cleanup path; AceGUI wipes events on
    -- release, so the chain never stacks across pool cycles.
    local prevOnRelease = enableCb.events and enableCb.events["OnRelease"]
    enableCb:SetCallback("OnRelease", function()
        if prevOnRelease then
            prevOnRelease(enableCb, "OnRelease")
        end
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Copy From Another Spec")
        GameTooltip:AddLine("Copies shared resource bar settings from another spec into your current spec.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("What is copied:", 1, 0.82, 0, true)
        GameTooltip:AddLine("- Appearance tab", 1, 1, 1, true)
        GameTooltip:AddLine("- Layout tab", 1, 1, 1, true)
        GameTooltip:AddLine("- Resource colors", 1, 1, 1, true)
        GameTooltip:AddLine("- Resource Settings", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("What is not copied:", 1, 0.82, 0, true)
        GameTooltip:AddLine("- Health settings", 1, 1, 1, true)
        GameTooltip:AddLine("- Custom Bars", 1, 1, 1, true)
        GameTooltip:AddLine("- Aura Tracking", 1, 1, 1, true)
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
    if BuildResourceBarConflictGate(container, "Resource Bars", true) then
        return
    end

    local db = CooldownCompanion.db.profile
    local settings = CooldownCompanion:GetResourceBarSettings()
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    local thicknessField, thicknessLabel = GetResourceThicknessFieldConfig(settings, layout)

    -- ============================================================
    -- Resource Toggles (the module switch, and which resources show)
    -- ============================================================
    -- The module switch lives INSIDE this section rather than above it: every
    -- row-grammar tab opens on a section header, and a free-standing control
    -- over the first caret has nowhere to belong. Disabling the module ends
    -- the section after one row and builds nothing below it, exactly as the
    -- pre-row tab returned early after the same checkbox.
    local toggleKey = "rb_toggles"
    local _, toggleCollapsed = BuildCollapsibleSection(container, "Resource Toggles", toggleKey, resourceBarCollapsedSections, nil, ROW_SECTION)

    local enableCb
    local togglesRight
    if not toggleCollapsed then
        -- LEFT column: the switches that apply to the whole stack. RIGHT
        -- column: one row per resource this class can show.
        local togglesLeft
        togglesLeft, togglesRight = BeginRowGrid(container)

        enableCb = AddCheckboxRow(togglesLeft, {
            label = "Enable Resource Bars",
            value = settings.enabled,
            onChange = function(val)
                settings.enabled = val
                CooldownCompanion:EvaluateResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        AddResourceSpecCopyButton(enableCb)

        -- Only show mana toggle for classes that actually use mana
        local _, _, classID = UnitClass("player")
        local NO_MANA_CLASSES = { [1] = true, [3] = true, [4] = true, [6] = true, [12] = true }
        if settings.enabled and classID and not NO_MANA_CLASSES[classID] then
            AddCheckboxRow(togglesLeft, {
                label = "Hide Mana for Non-Healer Specs",
                value = settings.hideManaForNonHealer ~= false,
                onChange = function(val)
                    settings.hideManaForNonHealer = val
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:UpdateAnchorStacking()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end
    end

    if not settings.enabled then return end
    if not settings.resources then settings.resources = {} end

    if togglesRight then
        -- Per-resource enable/disable
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            local name = POWER_NAMES[pt] or ("Power " .. pt)
            local enabled = IsResourceEnabled(settings, pt)

            AddCheckboxRow(togglesRight, {
                label = "Show " .. name,
                value = enabled,
                onChange = function(val)
                    if not settings.resources[pt] then
                        settings.resources[pt] = {}
                    end
                    settings.resources[pt].enabled = val
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:UpdateAnchorStacking()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end
    end

    if not layout then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Specialization data loading...")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    local isIndependentStack = layout.independentAnchorEnabled == true

    -- ============ Alpha Section ============
    local group = db.groups[CS.selectedGroup]
    BuildAlphaControls(container, settings, function()
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RefreshConfigPanel()
    end, "rb_alpha", {
        row = true,
        isGlobal = group and group.isGlobal,
        disabled = not isIndependentStack and layout.inheritAlpha == true,
    })
end

------------------------------------------------------------------------

local function BuildResourceBarPositioningPanel(container)
    if BuildResourceBarConflictGate(container, "Resource Bars", true) then
        return
    end

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

    -- ============================================================
    -- Placement (what the stack hangs off, and which way it runs)
    -- ============================================================
    local _, placementCollapsed = BuildCollapsibleSection(container, "Placement", "rb_placement", resourceBarCollapsedSections, nil, ROW_SECTION)

    if not placementCollapsed then
        -- LEFT column: the anchoring choice and the two orientation settings
        -- that read together - the fill direction only means anything for the
        -- orientation above it, and is disabled otherwise. RIGHT column: the
        -- one setting that belongs to the choice of anchoring rather than to
        -- the stack itself - where its alpha comes from. Independent stacks
        -- have no panel to inherit from, so that side ends early.
        local placementLeft, placementRight = BeginRowGrid(container)

        AddDropdownRow(placementLeft, {
            label = "Anchoring Mode",
            list = {
                attached = "Attached to Panel",
                independent = "Independent",
            },
            order = { "attached", "independent" },
            value = isIndependentStack and "independent" or "attached",
            onChange = function(val)
                layout.independentAnchorEnabled = (val == "independent")
                CooldownCompanion:EvaluateResourceBars()
                CooldownCompanion:RepositionCastBar()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        AddDropdownRow(placementLeft, {
            label = "Bar Orientation",
            list = {
                horizontal = "Horizontal",
                vertical = "Vertical",
            },
            order = { "horizontal", "vertical" },
            value = layout.orientation or settings.orientation or "horizontal",
            onChange = function(val)
                layout.orientation = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RepositionCastBar()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        AddDropdownRow(placementLeft, {
            label = "Vertical Fill Direction",
            indent = true,
            list = {
                bottom_to_top = "Bottom to Top",
                top_to_bottom = "Top to Bottom",
            },
            order = { "bottom_to_top", "top_to_bottom" },
            value = layout.verticalFillDirection or settings.verticalFillDirection or "bottom_to_top",
            disabled = not isVerticalLayout,
            onChange = function(val)
                layout.verticalFillDirection = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RepositionCastBar()
                CooldownCompanion:UpdateAnchorStacking()
                -- The canvas fills its vertical bars in this direction too,
                -- and nothing here rebuilds the settings column.
                RefreshLayoutOrderPreview()
            end,
        })

        if layout.independentAnchorEnabled ~= true then
            AddCheckboxRow(placementRight, {
                label = "Inherit panel alpha",
                value = layout.inheritAlpha,
                onChange = function(val)
                    layout.inheritAlpha = val == true
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end
    end

    -- ============================================================
    -- Bar Size (how thick each bar is, and how they sit apart)
    -- ============================================================
    local _, sizeCollapsed = BuildCollapsibleSection(container, "Bar Size", "rb_bar_size", resourceBarCollapsedSections, nil, ROW_SECTION)

    if not sizeCollapsed then
        -- LEFT column: the thickness of a bar, shared or per-resource - the
        -- override toggle disables the shared slider above it, so the two stay
        -- adjacent. RIGHT column: the gaps between the things being sized.
        local sizeLeft, sizeRight = BeginRowGrid(container)

        -- Bar Height + Custom Heights
        ST._BuildBarHeightControls(sizeLeft, settings, layout)

        -- Bar Spacing. The canvas takes its lane gap straight from this value,
        -- so the whole stack re-spaces under the drag and the live bars
        -- reposition once, on release.
        AddMirrorFirstSliderRow(sizeRight, {
            label = "Bar Spacing",
            min = 0, max = 20, step = 0.1,
            value = layout.barSpacing or settings.barSpacing or 3.6,
            set = function(val) layout.barSpacing = val end,
            apply = function()
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RepositionCastBar()
                CooldownCompanion:UpdateAnchorStacking()
            end,
        })

        -- Segment Gap
        AddMirrorFirstSliderRow(sizeRight, {
            label = "Segment Gap",
            min = 0, max = 20, step = 0.1,
            value = layout.segmentGap or settings.segmentGap or 4,
            set = function(val) layout.segmentGap = val end,
            apply = function()
                CooldownCompanion:ApplyResourceBars()
            end,
        })
    end

    -- ============ Anchor Settings (independent mode only) ============
    if isIndependentStack then
        local stackPosKey = "rb_stack_position"
        local _, stackPosCollapsed = BuildCollapsibleSection(container, "Anchor Settings", stackPosKey, resourceBarCollapsedSections, nil, ROW_SECTION)

        if not stackPosCollapsed then
            EnsureResourceLayoutAnchor(settings, layout)
            local anchor = layout.independentAnchor

            local function refreshResourceBarAnchor()
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end

            -- A frame name needs the whole 140px control column to stay
            -- readable, so Pick does not share it: the editbox row takes a
            -- grid of its own and Pick sits at the head of that grid's right
            -- column, immediately across the 16px gutter.
            local targetLeft, targetRight = BeginRowGrid(container)
            BuildIndependentAnchorTargetRow(targetLeft, anchor, refreshResourceBarAnchor, {
                row = true,
                pickContainer = targetRight,
            })

            -- LEFT column: how the stack is placed - the drag toggle and the
            -- two points that have to be read together (mine, then the
            -- target's). RIGHT column: its size and the offset applied on top
            -- of those points.
            local stackLeft, stackRight = BeginRowGrid(container)

            AddCheckboxRow(stackLeft, {
                label = "Unlock Placement",
                value = not layout.independentAnchorLocked,
                onChange = function(val)
                    layout.independentAnchorLocked = not val
                    CooldownCompanion:ApplyResourceBars()
                    if not val then
                        CooldownCompanion:CheckArrangeModeAutoExit()
                    end
                end,
            })

            AddAnchorDropdown(stackLeft, anchor, "point", "CENTER", refreshResourceBarAnchor, "Anchor Point", { row = true })
            AddAnchorDropdown(stackLeft, anchor, "relativePoint", "CENTER", refreshResourceBarAnchor, "Relative Point", { row = true })

            -- The canvas sizes an independent stack's slots from this value.
            AddMirrorFirstSliderRow(stackRight, {
                label = "Bar Width",
                min = 20, max = 600, step = 1,
                value = layout.independentWidth or settings.independentWidth or 200,
                set = function(val) layout.independentWidth = val end,
                apply = function()
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:UpdateAnchorStacking()
                end,
            })

            -- The two offsets below place the stack on SCREEN, which the canvas
            -- does not draw; they stay on the live display alone.
            AddSliderRow(stackRight, {
                label = "X Offset",
                min = -2000, max = 2000, step = 0.1,
                value = anchor.x or 0,
                onChange = function(val)
                    anchor.x = val
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:UpdateAnchorStacking()
                end,
            })

            AddSliderRow(stackRight, {
                label = "Y Offset",
                min = -2000, max = 2000, step = 0.1,
                value = anchor.y or 0,
                onChange = function(val)
                    anchor.y = val
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:UpdateAnchorStacking()
                end,
            })
        end
    end

    -- ============ Layout Section (attached mode only) ============
    if not isIndependentStack then
        local posKey = "rb_position"
        local _, posCollapsed = BuildCollapsibleSection(container, "Layout", posKey, resourceBarCollapsedSections, nil, ROW_SECTION)

        if not posCollapsed then
            -- LEFT column: the gap between this stack and the panel it hangs
            -- off. RIGHT column: the cast bar's own override of that gap.
            local posLeft, posRight = BeginRowGrid(container)

            local gapValue
            if gapField == "verticalXOffset" then
                gapValue = layout.verticalXOffset or layout.yOffset or settings.verticalXOffset or settings.yOffset or 3
            else
                gapValue = layout.yOffset or layout.verticalXOffset or settings.yOffset or settings.verticalXOffset or 3
            end

            AddSliderRow(posLeft, {
                label = gapLabel,
                min = -100, max = 100, step = 0.1,
                value = gapValue,
                onChange = function(val)
                    layout[gapField] = val
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:RepositionCastBar()
                    CooldownCompanion:UpdateAnchorStacking()
                end,
            })

            -- Row grammar now: the builder lives in CastBarPanels.lua and
            -- emits CDC rows for both of its call sites, so it drops straight
            -- into this column.
            if ST._BuildAttachedCastBarOffsetControls then
                ST._BuildAttachedCastBarOffsetControls(posRight, layout)
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

    local thicknessValue
    if thicknessField == "barWidth" then
        thicknessValue = layout.barWidth or layout.barHeight or settings.barWidth or settings.barHeight or 12
    else
        thicknessValue = layout.barHeight or layout.barWidth or settings.barHeight or settings.barWidth or 12
    end

    -- Every bar on the canvas is drawn at this thickness (or its per-resource
    -- override below), so the stack resizes under the drag.
    AddMirrorFirstSliderRow(container, {
        label = thicknessLabel,
        min = 4, max = 40, step = 0.1,
        value = thicknessValue,
        disabled = layout.customBarHeights or false,
        set = function(val) layout[thicknessField] = val end,
        apply = function()
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RepositionCastBar()
            CooldownCompanion:UpdateAnchorStacking()
        end,
    })

    local customHeightsCb = AddCheckboxRow(container, {
        label = customThicknessLabel,
        value = layout.customBarHeights or false,
        onChange = function(val)
            local wasEnabled = layout.customBarHeights == true
            layout.customBarHeights = val
            if val and not wasEnabled and CS.QueueAdvancedSettingsPanelOpen then
                CS.QueueAdvancedSettingsPanelOpen(customHeightsAdvKey)
            end
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RepositionCastBar()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): one slider row per active
    -- resource, straight onto the panel scroll. The toggle they belong to lives
    -- back on the tab, so none of them indents. "<Resource> <thickness label>"
    -- runs long against a slider track, so the full label rides the row
    -- tooltip too.
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

            local resThickness
            if thicknessField == "barWidth" then
                resThickness = resLayout.barWidth or resLayout.barHeight
                    or layout.barWidth or layout.barHeight or settings.barWidth or settings.barHeight or 12
            else
                resThickness = resLayout.barHeight or resLayout.barWidth
                    or layout.barHeight or layout.barWidth or settings.barHeight or settings.barWidth or 12
            end

            local rowLabel = name .. " " .. thicknessLabel
            AddMirrorFirstSliderRow(panel, {
                label = rowLabel,
                tooltip = { rowLabel },
                min = 4, max = 40, step = 0.1,
                value = resThickness,
                disabled = not enabled,
                set = function(val)
                    if not enabled then
                        return
                    end
                    if type(layout.resources[capturedPt]) ~= "table" then
                        layout.resources[capturedPt] = {}
                    end
                    layout.resources[capturedPt][thicknessField] = val
                end,
                apply = function()
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:RepositionCastBar()
                    CooldownCompanion:UpdateAnchorStacking()
                end,
            })
        end
    end

    AddAdvancedToggle(customHeightsCb, customHeightsAdvKey, tabInfoButtons, layout.customBarHeights == true, {
        title = customThicknessLabel .. " Advanced",
        build = BuildCustomResourceHeightsAdvanced,
    })

    -- Second badge after the gear when the setting is on, first when it is off:
    -- AddAdvancedToggle only chains a gear it actually shows, so the anchor
    -- args below are a placeholder - AnchorRowBadge re-points the button.
    AnchorRowBadge(customHeightsCb, CreateInfoButton(customHeightsCb.frame, customHeightsCb.frame, "LEFT", "LEFT", 0, 0, {
        customThicknessLabel,
        {"When enabled, each resource can have its own bar size. Open advanced settings here to configure all resource sizes together.", 1, 1, 1, true},
    }, customHeightsCb))
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

    local colorKey = "rb_colors_" .. tostring(powerType) .. "_" .. tostring(specID)
    local _, colorCollapsed = BuildCollapsibleSection(container, "Colors", colorKey, resourceBarCollapsedSections, nil, ROW_SECTION)

    if colorCollapsed then
        return true
    end

    -- One list with no internal grouping to split on, so the columns are cut
    -- purely for balance: the first half reads down the left, the rest down
    -- the right, in the order the descriptors declare.
    local colorLeft, colorRight = BeginRowGrid(container)
    local leftCount = math.ceil(#descriptors / 2)

    for index, descriptor in ipairs(descriptors) do
        local capturedKey = descriptor.key
        local capturedDefault = descriptor.defaultColor
        local proxy = {
            [capturedKey] = ReadSpecOverrideKey(settings, powerType, specID, capturedKey, capturedDefault),
        }
        AddColorRow(index <= leftCount and colorLeft or colorRight, {
            label = descriptor.label,
            tbl = proxy,
            key = capturedKey,
            default = capturedDefault,
            hasAlpha = descriptor.hasAlpha,
            onConfirm = function()
                WriteSpecOverrideKey(settings, powerType, specID, capturedKey, proxy[capturedKey])
                applyBars()
            end,
            -- The picker-open path already writes the override (the proxy is a
            -- throwaway, so the store is the only place the canvas can read
            -- it from); repainting here is what makes the swatch track live.
            onChange = function()
                WriteSpecOverrideKey(settings, powerType, specID, capturedKey, proxy[capturedKey])
                RefreshLayoutOrderPreviewForDrag()
            end,
        })
    end

    return true
end

local function CopyThresholdTickEntryList(entries)
    local copied = {}
    if type(entries) == "table" then
        for index, entry in ipairs(entries) do
            copied[index] = {
                value = entry.value,
                color = type(entry.color) == "table" and CopyTable(entry.color) or nil,
            }
        end
    end
    return copied
end

local function SortThresholdTickEntryList(entries)
    table.sort(entries, function(a, b)
        return (tonumber(a.value) or 0) < (tonumber(b.value) or 0)
    end)
end

local function HasThresholdTickDuplicateValue(entries, value, skipIndex)
    for index, entry in ipairs(entries) do
        if index ~= skipIndex and entry.value == value then
            return true
        end
    end
    return false
end

local function RefreshAdvancedSettingsPanelSoon()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if CS.RefreshAdvancedSettingsPanel then
                CS.RefreshAdvancedSettingsPanel()
            else
                CooldownCompanion:RefreshConfigPanel()
            end
        end)
    elseif CS.RefreshAdvancedSettingsPanel then
        CS.RefreshAdvancedSettingsPanel()
    else
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function SetThresholdTickEditorError(errorKey, message)
    thresholdTickEditorErrors[errorKey] = message
    RefreshAdvancedSettingsPanelSoon()
end

local function AddThresholdTickHelperLabel(container, text)
    local label = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText(text)
    label:SetFullWidth(true)
    container:AddChild(label)
end

-- No caret: this sub-section has no collapse state, and the left-aligned shape
-- indents the label as if it had one so it lines up with the rows beneath it.
-- Same call the preset section makes (Helpers.lua).
local function AddThresholdTickSubHeading(container, text)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)
    ApplyLeftAlignedHeading(heading)
end

-- A value and the button that removes (or abandons) it. In a single rail the
-- editbox row's control column is fully taken by the editbox, so the button
-- takes the line below it - the same shape BuildIndependentAnchorTargetRow
-- falls back to when it has no second column to put Pick in. The button row is
-- exactly one grammar row tall (Flow insets its single row by 3px and the
-- button is 24 tall, so 3 + 24 + 3 fills the band) and noAutoHeight keeps
-- Flow's own 27px report from shrinking it back.
--
-- onEnter takes AddEditBoxRow's (text, widget) contract; the widget it hands
-- back is the row, which forwards SetText to the embedded stock EditBox.
local function AddThresholdTickValueRow(panel, label, text, buttonText, onEnter, onButton)
    local valueRow = AddEditBoxRow(panel, {
        label = label,
        -- Value labels name their resource ("Fury Threshold Value (>=)"), which
        -- can outrun the label side of a narrow panel row.
        tooltip = { label },
        value = text,
        onEnterPressed = onEnter,
    })
    valueRow:DisableButton(true)
    if valueRow.editbox and valueRow.editbox.Instructions then
        valueRow.editbox.Instructions:Hide()
    end

    local buttonRow = AceGUI:Create("SimpleGroup")
    buttonRow:SetFullWidth(true)
    buttonRow:SetLayout("Flow")
    buttonRow:SetHeight(ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT or 30)
    buttonRow.noAutoHeight = true

    local button = AceGUI:Create("Button")
    button:SetText(buttonText)
    button:SetAutoWidth(true)
    button:SetCallback("OnClick", onButton)
    buttonRow:AddChild(button)

    -- Added after its child so the List-layout panel measures a populated row.
    panel:AddChild(buttonRow)
end

local function AddThresholdTickEnableCheckbox(container, settings, powerType, specID, settingKey, label, advKey)
    local enabled = ReadSpecOverrideKey(settings, powerType, specID, settingKey, false) == true
    local checkbox = AddCheckboxRow(container, {
        label = label,
        value = enabled,
        onChange = function(val)
            local wasEnabled = ReadSpecOverrideKey(settings, powerType, specID, settingKey, false) == true
            WriteSpecOverrideKey(settings, powerType, specID, settingKey, val == true)
            if val and not wasEnabled and CS.QueueAdvancedSettingsPanelOpen then
                CS.QueueAdvancedSettingsPanelOpen(advKey, {
                    selectedResourcePowerType = powerType,
                    resourceSettingsSpecID = specID,
                })
            end
            CooldownCompanion:ApplyResourceBars()
            C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
        end,
    })
    return checkbox, enabled
end

local function GetConfigSegmentedThresholdEntries(settings, powerType, specID)
    local rawEntries, cleared = ResolveSpecEntryList(settings.resources and settings.resources[powerType], specID, "segThresholdEntries", "segThresholdEntriesCleared")
    local entries = GetNormalizedSegmentedThresholdEntriesFromConfig(rawEntries)
    if #entries == 0
        and not cleared
        and ReadSpecOverrideKey(settings, powerType, specID, "segThresholdEnabled", false) == true then
        entries[1] = {
            value = GetSegmentedThresholdValueConfig({
                segThresholdValue = ReadSpecOverrideKey(settings, powerType, specID, "segThresholdValue", nil),
            }),
            color = GetSafeRGBConfig(ReadSpecOverrideKey(settings, powerType, specID, "segThresholdColor", nil), DEFAULT_SEG_THRESHOLD_COLOR),
        }
    end
    return entries
end

local function GetConfigContinuousTickEntries(settings, powerType, specID, mode)
    local entriesKey = mode == "absolute" and "continuousTickAbsoluteEntries" or "continuousTickPercentEntries"
    local clearedKey = mode == "absolute" and "continuousTickAbsoluteEntriesCleared" or "continuousTickPercentEntriesCleared"
    local rawEntries, cleared = ResolveSpecEntryList(settings.resources and settings.resources[powerType], specID, entriesKey, clearedKey)
    local entries = GetNormalizedContinuousTickEntriesFromConfig(rawEntries, mode)
    if #entries == 0
        and not cleared
        and ReadSpecOverrideKey(settings, powerType, specID, "continuousTickEnabled", false) == true then
        local value
        if mode == "absolute" then
            value = GetContinuousTickAbsoluteConfig({
                continuousTickAbsolute = ReadSpecOverrideKey(settings, powerType, specID, "continuousTickAbsolute", nil),
            })
        else
            value = GetContinuousTickPercentConfig({
                continuousTickPercent = ReadSpecOverrideKey(settings, powerType, specID, "continuousTickPercent", nil),
            })
        end
        entries[1] = {
            value = value,
            color = GetSafeRGBAConfig(ReadSpecOverrideKey(settings, powerType, specID, "continuousTickColor", nil), DEFAULT_CONTINUOUS_TICK_COLOR),
        }
    end
    return entries
end

local function WriteThresholdTickEntries(settings, powerType, specID, entriesKey, clearedKey, entries)
    entries = CopyThresholdTickEntryList(entries)
    SortThresholdTickEntryList(entries)
    if #entries > 0 then
        WriteSpecOverrideKey(settings, powerType, specID, entriesKey, entries)
        WriteSpecOverrideKey(settings, powerType, specID, clearedKey, nil)
    else
        WriteSpecOverrideKey(settings, powerType, specID, entriesKey, nil)
        WriteSpecOverrideKey(settings, powerType, specID, clearedKey, true)
    end
end

local function AddThresholdTickEntryEditor(panel, options)
    local entries = options.entries
    local rowCount = #entries
    local draftKey = options.draftKey
    local draftActive = thresholdTickDraftRows[draftKey] == true

    AddThresholdTickSubHeading(panel, options.heading)
    if rowCount == 0 and not draftActive then
        AddThresholdTickHelperLabel(panel, options.emptyText)
    end

    local function commitValue(index, text, widget)
        local parsed = options.clampValue(text, nil)
        local errorKey = options.errorPrefix .. "_" .. tostring(index or "new")
        if parsed == nil then
            if widget and index and entries[index] then
                widget:SetText(tostring(entries[index].value))
            end
            SetThresholdTickEditorError(errorKey, options.invalidText)
            return
        end
        if HasThresholdTickDuplicateValue(entries, parsed, index) then
            if widget and index and entries[index] then
                widget:SetText(tostring(entries[index].value))
            end
            SetThresholdTickEditorError(errorKey, options.duplicateText)
            return
        end

        local updated = CopyThresholdTickEntryList(entries)
        if index then
            updated[index].value = parsed
        else
            updated[#updated + 1] = { value = parsed }
            thresholdTickDraftRows[draftKey] = nil
            thresholdTickEditorErrors[options.errorPrefix .. "_new"] = nil
        end
        thresholdTickEditorErrors[errorKey] = nil
        options.writeEntries(updated)
        options.applyBars()
        RefreshAdvancedSettingsPanelSoon()
    end

    for index, entry in ipairs(entries) do
        local errorKey = options.errorPrefix .. "_" .. tostring(index)
        AddThresholdTickValueRow(panel, options.valueLabel, tostring(entry.value), "Remove",
            function(text, widget)
                commitValue(index, text, widget)
            end,
            function()
                local updated = CopyThresholdTickEntryList(entries)
                table.remove(updated, index)
                thresholdTickEditorErrors[errorKey] = nil
                options.writeEntries(updated)
                options.applyBars()
                RefreshAdvancedSettingsPanelSoon()
            end)

        if thresholdTickEditorErrors[errorKey] then
            AddThresholdTickHelperLabel(panel, "|cffff7777" .. thresholdTickEditorErrors[errorKey] .. "|r")
        end

        local proxyKey = options.colorKey
        local proxy = {
            [proxyKey] = type(entry.color) == "table" and CopyTable(entry.color) or CopyTable(options.defaultColor),
        }
        -- deferCommit is deliberately absent, matching the stock color-picker call
        -- this row replaced: the bound table IS the throwaway proxy, so a drag
        -- value resting in it cannot reach a live renderer.
        AddColorRow(panel, {
            label = options.colorLabel,
            tooltip = { options.colorLabel },
            tbl = proxy,
            key = proxyKey,
            default = options.defaultColor,
            hasAlpha = options.hasAlpha,
            onConfirm = function()
                local updated = CopyThresholdTickEntryList(entries)
                if updated[index] then
                    updated[index].color = proxy[proxyKey]
                    options.writeEntries(updated)
                    options.applyBars()
                end
            end,
            -- options.previewRefresh is supplied only by the editor whose
            -- markers actually render on the canvas (tick markers; threshold
            -- colours only show below maximum, and the canvas previews every
            -- bar at maximum). The entry is already written above, so the
            -- repaint has something to read.
            onChange = function()
                local updated = CopyThresholdTickEntryList(entries)
                if updated[index] then
                    updated[index].color = proxy[proxyKey]
                    options.writeEntries(updated)
                    if options.previewRefresh then
                        options.previewRefresh()
                    end
                end
            end,
        })
    end

    if draftActive then
        local errorKey = options.errorPrefix .. "_new"
        AddThresholdTickValueRow(panel, "New " .. options.valueLabel, "", "Cancel",
            function(text, widget)
                commitValue(nil, text, widget)
            end,
            function()
                thresholdTickDraftRows[draftKey] = nil
                thresholdTickEditorErrors[errorKey] = nil
                RefreshAdvancedSettingsPanelSoon()
            end)

        if thresholdTickEditorErrors[errorKey] then
            AddThresholdTickHelperLabel(panel, "|cffff7777" .. thresholdTickEditorErrors[errorKey] .. "|r")
        end
        AddThresholdTickHelperLabel(panel, "|cff888888Enter a valid value to unlock color settings for this row.|r")
    end

    -- Same compact shape the Remove/Cancel buttons above take, so the section's
    -- actions read as buttons rather than page-wide banners.
    local addRow = AceGUI:Create("SimpleGroup")
    addRow:SetFullWidth(true)
    addRow:SetLayout("Flow")
    addRow:SetHeight(ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT or 30)
    addRow.noAutoHeight = true

    local addBtn = AceGUI:Create("Button")
    addBtn:SetText(options.addText)
    addBtn:SetAutoWidth(true)
    local addDisabled = rowCount >= MAX_RESOURCE_THRESHOLD_TICK_ENTRIES or draftActive
    if addBtn.SetDisabled then
        addBtn:SetDisabled(addDisabled)
    end
    addBtn:SetCallback("OnClick", function()
        if rowCount >= MAX_RESOURCE_THRESHOLD_TICK_ENTRIES or draftActive then
            return
        end
        thresholdTickDraftRows[draftKey] = true
        thresholdTickEditorErrors[options.errorPrefix .. "_new"] = nil
        RefreshAdvancedSettingsPanelSoon()
    end)
    addRow:AddChild(addBtn)
    panel:AddChild(addRow)

    if rowCount >= MAX_RESOURCE_THRESHOLD_TICK_ENTRIES then
        AddThresholdTickHelperLabel(panel, "|cff888888Maximum of 3 entries configured.|r")
    end
end

------------------------------------------------------------------------
-- Resource aura borders (the aura pass, Phase 2; border redesign
-- 2026-08-02). One tracked aura per resource per specialization. The
-- border is the aura-present visual, wrapping the whole bar rect on
-- every shape, and Stack Count mode adds the lane. Blizzard shows and
-- hides everything with the aura itself, so it survives combat, where
-- the addon cannot read aura state at all. Stored keys keep their
-- auraOverlay* names: labels renamed, no migration.
------------------------------------------------------------------------

local function GetResourceAuraOverlayEntry(settings, powerType, specID)
    local resource = settings.resources and settings.resources[powerType]
    local entries = resource and resource.auraOverlayEntries
    if type(entries) ~= "table" or not specID then return nil end
    local entry = entries[specID]
    if type(entry) ~= "table" then
        entry = entries[tostring(specID)]
    end
    return type(entry) == "table" and entry or nil
end

local function EnsureResourceAuraOverlayEntry(settings, powerType, specID)
    if not specID then return nil end
    if type(settings.resources[powerType]) ~= "table" then
        settings.resources[powerType] = {}
    end
    local resource = settings.resources[powerType]
    if type(resource.auraOverlayEntries) ~= "table" then
        resource.auraOverlayEntries = {}
    end
    local entries = resource.auraOverlayEntries
    if type(entries[specID]) ~= "table" then
        -- Adopt a string-keyed entry rather than shadowing it: the runtime
        -- reads either key, so two entries for one spec would diverge.
        local legacy = entries[tostring(specID)]
        entries[specID] = type(legacy) == "table" and legacy or {}
        entries[tostring(specID)] = nil
    end
    return entries[specID]
end

-- Mirrors IsResourceAuraOverlayEnabled (ResourceBarVisuals) for an
-- arbitrary spec: the runtime answers only for the spec being played.
local function IsResourceAuraOverlayEnabledConfig(settings, powerType, specID)
    local resource = settings.resources and settings.resources[powerType]
    if type(resource) ~= "table" then return false end
    local specOverrides = resource.specOverrides
    local specData = type(specOverrides) == "table"
        and (specOverrides[specID] or specOverrides[tostring(specID)]) or nil
    if type(specData) == "table" and type(specData.auraOverlayEnabled) == "boolean" then
        return specData.auraOverlayEnabled
    end
    if resource.auraOverlayEnabled == false then return false end
    return GetResourceAuraOverlayEntry(settings, powerType, specID) ~= nil
end

local function BuildResourceAuraOverlaySection(container, settings, powerType, specID, resourceName)
    local sectionKey = "rb_aura_overlay_" .. powerType
    local heading, collapsed =
        BuildCollapsibleSection(container, "Aura Tracking", sectionKey, resourceBarCollapsedSections, nil, ROW_SECTION)

    local sectionInfoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
        "Aura Tracking",
        {"One aura per resource and specialization. Blizzard shows and hides the visuals with the aura itself, so they keep working in combat, where the addon cannot read aura state.", 1, 1, 1, true},
        " ",
        {"Buffs can only be tracked on yourself, and your own debuffs only on your target. The tracked unit is set automatically from the aura.", 1, 1, 1, true},
    }, heading)
    AnchorLeftAlignedHeadingRule(heading, sectionInfoBtn)

    if collapsed then return end

    -- Every handler in this section funnels through here: the border and
    -- lane render on the workspace Live Preview, which does not rebuild
    -- with the settings column, so the canvas re-renders on every edit.
    local applyBars = function()
        CooldownCompanion:ApplyResourceBars()
        RefreshLayoutOrderPreview()
    end
    -- Uncommitted edits (picker open, slider held) stop at the canvas.
    local previewOnly = RefreshLayoutOrderPreviewForDrag
    local function refresh()
        applyBars()
        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
    end

    local enabled = IsResourceAuraOverlayEnabledConfig(settings, powerType, specID)

    -- LEFT column: which aura is tracked, on whom, and the Stack Lane
    -- toggle. RIGHT column: the shared colour and the Border toggle with its
    -- styling. Border and lane are INDEPENDENT (owner ruling 2026-08-02);
    -- both halves are gated on the toggle at the head of the left one, so
    -- the right side is empty until an aura is picked.
    local auraLeft, auraRight = BeginRowGrid(container)

    AddCheckboxRow(auraLeft, {
        label = "Enable " .. resourceName .. " Aura Tracking",
        value = enabled,
        onChange = function(value)
            WriteSpecOverrideKey(settings, powerType, specID, "auraOverlayEnabled", value == true)
            refresh()
        end,
    })

    if not enabled then return end

    local entry = GetResourceAuraOverlayEntry(settings, powerType, specID)
    local spellID = entry and tonumber(entry.auraColorSpellID) or nil

    if not spellID then
        -- Commit one aura onto the entry. Shared by the autocomplete pick and
        -- the typed Enter, so both land the same derived state.
        local function CommitTrackedAura(id)
            local target = EnsureResourceAuraOverlayEntry(settings, powerType, specID)
            if not target then return false end
            target.auraColorSpellID = id
            -- Store the derived unit so the runtime's fallback starts right
            -- for spells the client has not cached yet; the rebind pass
            -- re-derives it from spell polarity every pass regardless.
            target.auraUnit = ClassifyAuraSpellUnit(id) or "player"
            return true
        end

        local auraAddBox
        auraAddBox = AddEditBoxRow(auraLeft, {
            label = "Aura by name or ID",
            indent = true,
            value = "",
            onEnterPressed = function(text, widget)
                -- The dropdown owns Enter while it has a highlighted row.
                if CS.ConsumeAutocompleteEnter() then return end
                CS.HideAutocomplete()
                -- The tracked-aura resolver, not the identity one: a typed
                -- name lands the applied-aura ID, matching a dropdown pick.
                local id, blank = ResolveTrackedAuraSpellIDFromText(text)
                if not id then
                    -- Enter on an empty box is a no-op, not a failed lookup.
                    if not blank then
                        CooldownCompanion:Print("No spell found for that name or ID.")
                    end
                    return
                end
                if not CommitTrackedAura(id) then return end
                widget:SetText("")
                refresh()
            end,
        })

        -- Same aura-only suggestion list the icon entry's tracked-aura field
        -- draws (RBP.BuildTrackedAuraAutocompleteCache): this field tracks an
        -- aura, so plain spells would be noise.
        auraAddBox:SetCallback("OnTextChanged", function(widget, _, text)
            if text and #text >= 1 then
                local results = CS.SearchAutocompleteInCache(text, BuildTrackedAuraAutocompleteCache())
                CS.ShowAutocompleteResults(results, widget.editBoxWidget, function(entry)
                    CS.HideAutocomplete()
                    local id = entry and tonumber(entry.id) or nil
                    if not id or not CommitTrackedAura(id) then return end
                    auraAddBox:SetText("")
                    refresh()
                end, {
                    requireExactNumericEnter = true,
                    widthMultiplier = 2,
                })
            else
                CS.HideAutocomplete()
            end
        end)
        CS.SetupAutocompleteKeyHandler(auraAddBox)
        return
    end

    -- The tracked aura presents an ITEM, not a setting: a CDC-LabelRow with
    -- the spell's icon inlined into the label text (the row's label is a
    -- FontString, so the icon rides an inline texture escape) and a Remove
    -- link owned by the row's control column. This draws the same shape the
    -- shared AddAuraCandidateRow now draws; it stays inline because the
    -- overlay tracks ONE spell on auraColorSpellID rather than a candidate
    -- list, so only what Remove clears differs. Worth folding into the shared
    -- helper (it takes the remove action as a callback) if this file is opened
    -- for other reasons.
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    local spellName = spellInfo and spellInfo.name or ("Spell " .. spellID)
    local spellIcon = C_Spell.GetSpellTexture(spellID) or 134400
    local auraRow = AddLabelRow(auraLeft, {
        label = ("|T%d:16:16:0:0|t %s |cff999999(%d)|r"):format(spellIcon, spellName, spellID),
        indent = true,
    })

    -- Right-justified so the word lands on the control column's right edge
    -- like every other row's control. SetJustifyH is public API and the stock
    -- Label resets it to LEFT in OnAcquire, so the pool stays clean.
    local removeLabel = AceGUI:Create("InteractiveLabel")
    -- The shared InteractiveLabel pool also serves the Navigator, whose rows
    -- hang plain-child badges off the label FRAME (expand button, warning
    -- meta, rename badge). Nothing hides those on release, so a reacquired
    -- frame arrives wearing its previous tenant's badges — the badge-leak
    -- class. Same clean-on-acquire call every Navigator site makes.
    CleanRecycledEntry(removeLabel)
    removeLabel:SetText("|cffff5555Remove|r")
    removeLabel:SetWidth(60)
    removeLabel:SetJustifyH("RIGHT")
    removeLabel:SetCallback("OnClick", function()
        local target = GetResourceAuraOverlayEntry(settings, powerType, specID)
        if target then
            target.auraColorSpellID = nil
            target.auraUnit = nil
        end
        refresh()
    end)
    auraRow:SetControlWidget(removeLabel)

    local unit = ClassifyAuraSpellUnit(spellID) or "player"
    AddLabelRow(auraLeft, {
        label = "Tracked on",
        indent = true,
        controlText = unit == "target" and "Target" or "You",
    })

    -- The Stack Lane is a fact about the TRACKING, so it lives with the
    -- aura rows on the left, independent of the border (owner ruling
    -- 2026-08-02: separate systems, any combination). It only exists where
    -- the runtime can draw the lane; the stored key stays
    -- auraColorTrackingMode ("stacks"/"active") so no config migrates.
    if SupportsResourceAuraStackMode(powerType) then
        local laneOn = RB.GetResourceOverlayTrackingMode(entry, powerType) == "stacks"

        local laneRow = AddCheckboxRow(auraLeft, {
            label = "Stack Lane",
            indent = true,
            value = laneOn,
            onChange = function(value)
                local target = GetResourceAuraOverlayEntry(settings, powerType, specID)
                if not target then return end
                target.auraColorTrackingMode = value == true and "stacks" or "active"
                refresh()
            end,
        })
        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label.
        AnchorRowBadge(laneRow, CreateInfoButton(laneRow.frame, laneRow.frame, "LEFT", "LEFT", 0, 0, {
            "Stack Lane",
            {"Fills a lane along the bar as the aura's stacks build.", 1, 1, 1, true},
            " ",
            {"The maximum comes from the game's spell data. An aura that does not stack shows no lane.", 1, 1, 1, true},
        }, laneRow))

        if laneOn then
            local maxStacks = RB.ResolveResourceOverlayStackMax(entry, powerType)
            local inCombat = InCombatLockdown()

            -- Own colour per system (owner ruling 2026-08-02). New key;
            -- unset falls back to the border colour at render time, so the
            -- swatch shows the effective colour as its default.
            --
            -- Only where a lane can actually render. A nil max OUT of combat
            -- is a definitive "this aura doesn't stack" and the collector
            -- drops the lane, so the swatch would edit nothing. In combat a
            -- nil max only means UNREADABLE — the runtime still draws from
            -- its OOC cache — so the control has to stay.
            if maxStacks or inCombat then
                AddColorRow(auraLeft, {
                    label = "Lane Color",
                    indent = true,
                    tbl = entry,
                    key = "auraLaneColor",
                    default = RB.GetResourceOverlayLaneColor(entry),
                    onConfirm = applyBars,
                    onChange = previewOnly,
                })
            end

            local statusLabel = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(statusLabel)
            if maxStacks then
                statusLabel:SetText("|cffffd100Stack lane:|r full at " .. maxStacks .. " stacks")
            elseif inCombat then
                statusLabel:SetText("|cffff9955The stack maximum can't be read in combat; it resolves when you leave combat.|r")
            else
                statusLabel:SetText("|cffff9955This aura doesn't stack, so the lane won't show.|r")
            end
            statusLabel:SetFullWidth(true)
            auraLeft:AddChild(statusLabel)
        end
    end

    local borderOn = RB.IsResourceOverlayBorderEnabled(entry)
    AddCheckboxRow(auraRight, {
        label = "Border",
        value = borderOn,
        onChange = function(value)
            local target = GetResourceAuraOverlayEntry(settings, powerType, specID)
            if not target then return end
            -- nil = on, so pre-toggle configs never carry the key. Written
            -- with an if: `x and nil or false` collapses to false both ways.
            if value == true then
                target.auraBorderEnabled = nil
            else
                target.auraBorderEnabled = false
            end
            refresh()
        end,
    })

    if not borderOn then return end

    local borderStyle = RB.GetResourceOverlayBorderStyle(entry)
    AddDropdownRow(auraRight, {
        label = "Border Style",
        indent = true,
        list = { solid = "Solid Border", pixel = "Pixel Glow" },
        order = { "solid", "pixel" },
        value = borderStyle,
        onChange = function(value)
            if value ~= "solid" and value ~= "pixel" then return end
            local target = GetResourceAuraOverlayEntry(settings, powerType, specID)
            if not target then return end
            target.auraBorderStyle = value
            -- Size and speed change meaning per style (border px vs dash
            -- length; lap seconds), so a style switch resets the per-style
            -- keys to that style's defaults, like every glow dropdown.
            target.auraBorderSize = value == "pixel" and 12 or 2
            target.auraBorderSpeed = value == "pixel" and 2 or 0.5
            target.auraBorderLines = value == "pixel" and 5 or 2
            target.auraBorderThickness = value == "pixel" and 3 or 4
            refresh()
        end,
    })

    -- Own colour per system (owner ruling 2026-08-02): this key stays
    -- auraActiveColor — pre-split configs keep their border colour — and
    -- the lane's own key falls back to it.
    AddColorRow(auraRight, {
        label = "Border Color",
        indent = true,
        tbl = entry,
        key = "auraActiveColor",
        default = DEFAULT_RESOURCE_AURA_ACTIVE_COLOR,
        onConfirm = applyBars,
        onChange = previewOnly,
    })

    -- The style's own sliders, the same rows every other glow surface
    -- draws ("pixel" renders as the kit's dashes shape, so it takes that
    -- spec). Mirror-first here and nowhere else: the last argument is the
    -- opt-in, and every non-resource caller leaves it off.
    AddGlowSliderRows(auraRight, entry,
        borderStyle == "pixel" and "dashes" or "solid",
        AURA_BORDER_SLIDER_KEYS, applyBars, 1, true, previewOnly)
end

local function BuildResourceBarStylingPanel(container, sectionMode, opts)
    if BuildResourceBarConflictGate(container, "Resource Bars", true) then
        return
    end

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
    local showResourceText = showResourceSettings
    local showThresholdsTicks = false

    -- The commit path for every styling row this panel builds, directly and
    -- through the section builders it hands this closure to (colors, text,
    -- health, threshold/tick editors). The canvas renders these bars with the
    -- REAL bar code and does not rebuild with the settings column, so applying
    -- and repainting belong together - one closure, so no section can end up
    -- with only half of it.
    local applyBars = function()
        CooldownCompanion:ApplyResourceBars()
        RefreshLayoutOrderPreview()
    end
    -- Uncommitted edits (a picker still open, a slider still held) belong to
    -- the canvas alone; the live bars keep their committed look.
    local previewOnly = RefreshLayoutOrderPreviewForDrag
    local healthResourceID = RESOURCE_HEALTH
    if showResourceSettings then
        -- Same split the section itself makes below, and the runtime makes
        -- in GetContinuousTickEntriesConfig: segmented resources — Maelstrom
        -- Weapon among them — get threshold colours, every other real power
        -- type gets tick markers, and the two invented ids (Stagger, Health)
        -- get neither. The section shows if either half applies.
        local isSegmented = SEGMENTED_TYPES[resourceSettingsPowerType] == true
            or resourceSettingsPowerType == 100
        showThresholdsTicks = isSegmented
            or (resourceSettingsPowerType ~= 101 and resourceSettingsPowerType ~= healthResourceID)
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
    local localBarTextureName = displayProfile.barTexture or settings.barTexture or "Solid"
    local effectiveBarTextureName = ST.GetEffectiveBarTextureName(localBarTextureName)
    local _colorSpecID = displaySpecID

    if showResourceSettings then
        BuildResourceColorControls(container, settings, resourceSettingsPowerType, _colorSpecID, effectiveBarTextureName, applyBars)
    end

    -- Maelstrom Weapon stack shape. Only this resource has a choice: its
    -- stacks can run past the segment count, which is what the overlay
    -- layer exists for, and the other two shapes drop it.
    if showResourceSettings and resourceSettingsPowerType == 100 then
        local _, mwCollapsed = BuildCollapsibleSection(container, "Stack Display", "rb_mw_stack_display", resourceBarCollapsedSections, nil, ROW_SECTION)

        if not mwCollapsed then
            -- LEFT column: the shape. RIGHT column: the max-stack border
            -- (owner ruling 2026-08-02) — CC-driven off MW's readable
            -- stacks, so it works in combat where aura-driven borders on
            -- other resources can only follow aura presence.
            local mwLeft, mwRight = BeginRowGrid(container)

            -- Everything in this section renders on the workspace Live
            -- Preview, which does not rebuild with the settings column.
            local applyMWBars = function()
                applyBars()
                RefreshLayoutOrderPreview()
            end

            AddDropdownRow(mwLeft, {
                label = "Stack Display",
                pulloutWidth = MEDIA_PULLOUT_WIDTH,
                list = {
                    overlay = "Overlay",
                    segments = "One Segment Per Stack",
                    continuous = "Continuous",
                },
                order = { "overlay", "segments", "continuous" },
                value = ReadSpecOverrideKey(settings, 100, _colorSpecID, "mwDisplayStyle", "overlay"),
                onChange = function(val)
                    WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwDisplayStyle",
                        val ~= "overlay" and val or nil)
                    applyMWBars()
                end,
            })

            local mwResource = settings.resources and settings.resources[100]
            local mwBorderOn = type(mwResource) == "table"
                and mwResource.mwMaxStackBorderEnabled == true
            local borderToggleRow = AddCheckboxRow(mwRight, {
                label = "Max Stack Border",
                value = mwBorderOn,
                onChange = function(value)
                    if type(settings.resources[100]) ~= "table" then
                        settings.resources[100] = {}
                    end
                    settings.resources[100].mwMaxStackBorderEnabled = value == true or nil
                    applyMWBars()
                    C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
                end,
            })
            AnchorRowBadge(borderToggleRow, CreateInfoButton(borderToggleRow.frame, borderToggleRow.frame, "LEFT", "LEFT", 0, 0, {
                "Max Stack Border",
                {"Shows a border while Maelstrom Weapon is at full stacks.", 1, 1, 1, true},
            }, borderToggleRow))

            if mwBorderOn then
                local mwBorderStyle = mwResource.mwMaxStackBorderStyle == "pixel" and "pixel" or "solid"
                AddDropdownRow(mwRight, {
                    label = "Border Style",
                    indent = true,
                    list = { solid = "Solid Border", pixel = "Pixel Glow" },
                    order = { "solid", "pixel" },
                    value = mwBorderStyle,
                    onChange = function(value)
                        if value ~= "solid" and value ~= "pixel" then return end
                        mwResource.mwMaxStackBorderStyle = value
                        -- Per-style key resets, like every glow dropdown.
                        mwResource.mwMaxStackBorderSize = value == "pixel" and 12 or 2
                        mwResource.mwMaxStackBorderSpeed = value == "pixel" and 2 or 0.5
                        mwResource.mwMaxStackBorderLines = value == "pixel" and 5 or 2
                        mwResource.mwMaxStackBorderThickness = value == "pixel" and 3 or 4
                        applyMWBars()
                        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
                    end,
                })
                AddColorRow(mwRight, {
                    label = "Border Color",
                    indent = true,
                    tbl = mwResource,
                    key = "mwMaxStackBorderColor",
                    default = RB.DEFAULT_MW_MAX_STACK_BORDER_COLOR,
                    onConfirm = applyMWBars,
                    onChange = previewOnly,
                })
                AddGlowSliderRows(mwRight, mwResource,
                    mwBorderStyle == "pixel" and "dashes" or "solid",
                    MW_BORDER_SLIDER_KEYS, applyMWBars, 1, true, previewOnly)
            end
        end
    end

    if showBarText then
    if not showResourceSettings then
    -- ============================================================
    -- Bar (the fill itself and what shows behind it)
    -- ============================================================
    local _, barCollapsed = BuildCollapsibleSection(container, "Bar", "rb_appearance_bar", resourceBarCollapsedSections, nil, ROW_SECTION)

    if not barCollapsed then
    -- LEFT column: the texture and the one setting that only exists for one
    -- texture, so it stays adjacent to it. RIGHT column: how the fill moves,
    -- and what shows through where it is not.
    local barLeft, barRight = BeginRowGrid(container)

    -- Bar Texture. LibSharedMedia names run past the control column, so the
    -- menu is widened - a 140px control would otherwise open a 140px menu.
    local texRow = AddDropdownRow(barLeft, {
        label = "Bar Texture",
        pulloutWidth = MEDIA_PULLOUT_WIDTH,
    })
    CS.SetupBarTextureDropdown(texRow, { list = GetResourceBarTextureOptions() })
    texRow:SetValue(localBarTextureName)
    CS.SetBarTextureDropdownCallback(texRow, function(widget, event, val)
        displayProfile.barTexture = val
        CooldownCompanion:ApplyResourceBars()
        -- Defer panel rebuild to next frame so it doesn't interfere with current callback
        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
    end)

    -- Brightness slider (only for Blizzard Class texture)
    if effectiveBarTextureName == "blizzard_class" then
        local brightnessLocked = ST.IsBarTexturePickerLocked and ST.IsBarTexturePickerLocked()
        AddMirrorFirstSliderRow(barLeft, {
            label = "Class Texture Brightness",
            indent = true,
            min = 0.5, max = 2.0, step = 0.1,
            value = displayProfile.classBarBrightness or settings.classBarBrightness or 1.3,
            disabled = brightnessLocked,
            set = function(val)
                if ST.IsBarTexturePickerLocked and ST.IsBarTexturePickerLocked() then return end
                displayProfile.classBarBrightness = val
            end,
            apply = applyBars,
        })
    end

    local smoothingRow = AddDropdownRow(barRight, {
        label = "Segmented Smoothing",
        list = {
            [ST.SEGMENTED_SMOOTHING_ON] = "On",
            [ST.SEGMENTED_SMOOTHING_OFF] = "Off",
        },
        order = { ST.SEGMENTED_SMOOTHING_ON, ST.SEGMENTED_SMOOTHING_OFF },
        value = ST.NormalizeSegmentedSmoothing(displayProfile.segmentedSmoothing),
        onChange = function(val)
            displayProfile.segmentedSmoothing = ST.NormalizeSegmentedSmoothing(val)
            applyBars()
        end,
    })
    -- Anchor args are a placeholder - AnchorRowBadge re-points the button onto
    -- the end of the row's label.
    AnchorRowBadge(smoothingRow, CreateInfoButton(smoothingRow.frame, smoothingRow.frame, "LEFT", "LEFT", 0, 0, {
        "Segmented Smoothing",
        {"Controls whether segmented resource bars and segmented or overlay custom bars animate smoothly or snap between segment values.", 1, 1, 1, true},
        " ",
        {"Continuous resources and continuous custom bars are not affected.", 1, 1, 1, true},
    }, smoothingRow))

    -- Resource Background Color
    AddColorRow(barRight, {
        label = "Resource Background Color",
        tbl = displayProfile,
        key = "backgroundColor",
        default = { 0, 0, 0, 0.5 },
        hasAlpha = true,
        onConfirm = applyBars,
        onChange = previewOnly,
    })
    end -- not barCollapsed

    -- ============================================================
    -- Border
    -- ============================================================
    local _, borderCollapsed = BuildCollapsibleSection(container, "Border", "rb_appearance_border", resourceBarCollapsedSections, nil, ROW_SECTION)

    if not borderCollapsed then
    -- LEFT column: whether there is a border at all, and what colour it is.
    -- RIGHT column: how thick it is drawn. Both sides are gated on the style
    -- above, so both end early when the border is off.
    local borderLeft, borderRight = BeginRowGrid(container)

    AddDropdownRow(borderLeft, {
        label = "Border Style",
        list = {
            pixel = "Pixel",
            none = "None",
        },
        order = { "pixel", "none" },
        value = displayProfile.borderStyle or settings.borderStyle or "pixel",
        onChange = function(val)
            displayProfile.borderStyle = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if (displayProfile.borderStyle or settings.borderStyle or "pixel") == "pixel" then
        AddColorRow(borderLeft, {
            label = "Border Color",
            indent = true,
            tbl = displayProfile,
            key = "borderColor",
            default = { 0, 0, 0, 1 },
            hasAlpha = true,
            onConfirm = applyBars,
            onChange = previewOnly,
        })

        local renderMode = ST._AddBorderRenderModeDropdown(borderRight, displayProfile, "borderRenderMode", function()
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end, nil, { row = true })
        local borderThicknessLocked = ST.IsBorderThicknessLocked()

        if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
            AddMirrorFirstSliderRow(borderRight, {
                label = "Border Size",
                indent = true,
                min = 0, max = 4, step = 0.1,
                value = displayProfile.borderSize or settings.borderSize or 1,
                disabled = borderThicknessLocked,
                set = function(val)
                    if borderThicknessLocked then return end
                    displayProfile.borderSize = val
                end,
                apply = applyBars,
            })
        end
    end
    end -- not borderCollapsed
    end

    if showResourceText then
        BuildResourceTextControls(container, settings, resourceSettingsPowerType, displaySpecID, applyBars, "rb_text")
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
    local thresholdKey = "rb_thresholds_ticks"
    local thresholdHeading, thresholdCollapsed = BuildCollapsibleSection(container, "Thresholds & Ticks", thresholdKey, resourceBarCollapsedSections, nil, ROW_SECTION)

    local thresholdInfoBtn = CreateInfoButton(thresholdHeading.frame, thresholdHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Thresholds & Ticks",
        {"Segmented resources: recolor when the current value is at/above configured thresholds. The highest crossed threshold wins.", 1, 1, 1, true},
        " ",
        {"Continuous resources: draw up to three static markers by percent or absolute value. Each marker can have its own color.", 1, 1, 1, true},
    }, thresholdHeading)
    AnchorLeftAlignedHeadingRule(thresholdHeading, thresholdInfoBtn)

    if not thresholdCollapsed then
        -- One toggle for the one resource this page is about - the values it
        -- gates all live behind its gear - so the left column carries it alone.
        local thresholdLeft = BeginRowGrid(container)
        local rbThresholdTickAdvBtns = {}
        local resources = { resourceSettingsPowerType }
        for _, pt in ipairs(resources) do
            if not settings.resources[pt] then
                settings.resources[pt] = {}
            end
            if settings.resources[pt].enabled ~= false then
                local resourceName = POWER_NAMES[pt] or ("Power " .. pt)
                local capturedPt = pt
                local isSegmented = SEGMENTED_TYPES[capturedPt] == true or capturedPt == 100

                if isSegmented then
                    local thresholdAdvKey = "rbSegThreshold_" .. capturedPt .. "_" .. tostring(_colorSpecID)
                    local thresholdEnableCb, _segEnabled = AddThresholdTickEnableCheckbox(
                        thresholdLeft,
                        settings,
                        capturedPt,
                        _colorSpecID,
                        "segThresholdEnabled",
                        "Enable " .. resourceName .. " Threshold Colors",
                        thresholdAdvKey
                    )

                    local function BuildSegmentedThresholdAdvanced(panel)
                        local entries = GetConfigSegmentedThresholdEntries(settings, capturedPt, _colorSpecID)
                        AddThresholdTickEntryEditor(panel, {
                            heading = "Threshold Colors",
                            entries = entries,
                            draftKey = thresholdAdvKey,
                            errorPrefix = thresholdAdvKey,
                            valueLabel = resourceName .. " Threshold Value (>=)",
                            colorKey = "segThresholdColor",
                            colorLabel = resourceName .. " Threshold Color",
                            defaultColor = DEFAULT_SEG_THRESHOLD_COLOR,
                            hasAlpha = false,
                            addText = "Add Threshold Color",
                            emptyText = "|cff888888No threshold colors configured. Add a value to make this enabled threshold setting active.|r",
                            invalidText = "Enter a threshold value from 1 to 99.",
                            duplicateText = "A threshold color already uses that value.",
                            clampValue = ClampSegmentedThresholdValue,
                            writeEntries = function(updated)
                                WriteThresholdTickEntries(settings, capturedPt, _colorSpecID, "segThresholdEntries", "segThresholdEntriesCleared", updated)
                            end,
                            applyBars = applyBars,
                        })
                    end

                    AddAdvancedToggle(
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
                    local tickEnableCb, _tickEnabled = AddThresholdTickEnableCheckbox(
                        thresholdLeft,
                        settings,
                        capturedPt,
                        _colorSpecID,
                        "continuousTickEnabled",
                        "Enable " .. resourceName .. " Tick Markers",
                        tickAdvKey
                    )

                    -- Single rail (AdvancedSettingsPanel.lua): every row goes
                    -- straight onto the panel scroll. The Enable ... Tick
                    -- Markers toggle lives back on the tab, so none of them
                    -- indents.
                    -- Tick markers ARE drawn on the canvas: the real continuous
                    -- styler the canvas runs places them, so every row in this
                    -- popout repaints it.
                    local function BuildTickMarkerAdvanced(panel)
                        AddCheckboxRow(panel, {
                            label = "Show Only In Combat",
                            value = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickCombatOnly", false),
                            onChange = function(val)
                                WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickCombatOnly", val == true)
                                applyBars()
                            end,
                        })

                        local tickMode = GetContinuousTickModeConfig({
                            continuousTickMode = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickMode", nil),
                        })
                        AddDropdownRow(panel, {
                            label = "Tick Mode",
                            list = {
                                percent = "Percent",
                                absolute = "Absolute Value",
                            },
                            order = { "percent", "absolute" },
                            value = tickMode,
                            onChange = function(val)
                                if val ~= "percent" and val ~= "absolute" then
                                    val = DEFAULT_CONTINUOUS_TICK_MODE
                                end
                                WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickMode", val)
                                applyBars()
                                C_Timer.After(0, function()
                                    if CS.RefreshAdvancedSettingsPanel then
                                        CS.RefreshAdvancedSettingsPanel()
                                    end
                                end)
                            end,
                        })

                        local tickEntries = GetConfigContinuousTickEntries(settings, capturedPt, _colorSpecID, tickMode)
                        local tickEntriesKey = tickMode == "absolute" and "continuousTickAbsoluteEntries" or "continuousTickPercentEntries"
                        local tickClearedKey = tickMode == "absolute" and "continuousTickAbsoluteEntriesCleared" or "continuousTickPercentEntriesCleared"
                        AddThresholdTickEntryEditor(panel, {
                            heading = "Tick Markers",
                            entries = tickEntries,
                            draftKey = tickAdvKey .. "_" .. tickMode,
                            errorPrefix = tickAdvKey .. "_" .. tickMode,
                            valueLabel = tickMode == "absolute" and (resourceName .. " Tick Absolute Value") or (resourceName .. " Tick Percent"),
                            colorKey = "continuousTickColor",
                            colorLabel = resourceName .. " Tick Color",
                            defaultColor = DEFAULT_CONTINUOUS_TICK_COLOR,
                            hasAlpha = true,
                            addText = "Add Tick Marker",
                            emptyText = tickMode == "absolute"
                                and "|cff888888No absolute tick markers configured. Add a value to make this enabled tick setting active in Absolute Value mode.|r"
                                or "|cff888888No percent tick markers configured. Add a value to make this enabled tick setting active in Percent mode.|r",
                            invalidText = tickMode == "absolute" and "Enter a tick value of 0 or higher." or "Enter a tick percent from 0 to 100.",
                            duplicateText = "A tick marker already uses that value.",
                            clampValue = tickMode == "absolute" and ClampContinuousTickAbsoluteValue or ClampContinuousTickPercentValue,
                            writeEntries = function(updated)
                                WriteThresholdTickEntries(settings, capturedPt, _colorSpecID, tickEntriesKey, tickClearedKey, updated)
                            end,
                            applyBars = applyBars,
                            previewRefresh = previewOnly,
                        })

                        local _tickWidthVal = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickWidth", nil)
                        local tickWidthLabel = resourceName .. " Tick Width"
                        AddMirrorFirstSliderRow(panel, {
                            label = tickWidthLabel,
                            tooltip = { tickWidthLabel },
                            min = 1, max = 10, step = 1,
                            value = tonumber(_tickWidthVal) or DEFAULT_CONTINUOUS_TICK_WIDTH,
                            set = function(val)
                                WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickWidth", val)
                            end,
                            apply = applyBars,
                        })
                    end

                    AddAdvancedToggle(
                        tickEnableCb,
                        tickAdvKey,
                        rbThresholdTickAdvBtns,
                        _tickEnabled,
                        {
                            title = resourceName .. " Tick Markers Advanced",
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

    -- Aura overlays: last section on a resource's own page, and never on
    -- health (its bar has its own effect family) or the shared styling tabs.
    if showResourceSettings and resourceSettingsPowerType ~= healthResourceID then
        BuildResourceAuraOverlaySection(container, settings, resourceSettingsPowerType,
            displaySpecID, POWER_NAMES[resourceSettingsPowerType]
                or ("Power " .. resourceSettingsPowerType))
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
ST._BuildResourceBarBarTextStylingPanel = BuildResourceBarBarTextStylingPanel
ST._BuildResourceBarHealthStylingPanel = BuildResourceBarHealthStylingPanel
ST._BuildResourceSettingsPanel = BuildResourceSettingsPanel
