--[[
    CooldownCompanion - ResourceBarHelpers
    Pure query/helper functions with no mutable state writes (aside from
    auto-vivification of config tables and a power-type secrecy memoization
    cache). Used by both ResourceBar.lua and ResourceBarVisuals.lua at runtime.

    All functions are added to ST._RB so consuming files can alias them to
    locals at load time.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local math_floor = math.floor
local string_format = string.format
local SecretsAPI = C_Secrets

-- Import constants from ResourceBarConstants
local RB = ST._RB
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local DEFAULT_POWER_COLORS = RB.DEFAULT_POWER_COLORS
local RESOURCE_COLOR_DEFS = RB.RESOURCE_COLOR_DEFS
local RESOURCE_MAELSTROM_WEAPON = RB.RESOURCE_MAELSTROM_WEAPON
local DEFAULT_SEG_THRESHOLD_COLOR = RB.DEFAULT_SEG_THRESHOLD_COLOR
local DEFAULT_CONTINUOUS_TICK_MODE = RB.DEFAULT_CONTINUOUS_TICK_MODE
local DEFAULT_CONTINUOUS_TICK_PERCENT = RB.DEFAULT_CONTINUOUS_TICK_PERCENT
local DEFAULT_CONTINUOUS_TICK_ABSOLUTE = RB.DEFAULT_CONTINUOUS_TICK_ABSOLUTE
local DEFAULT_CONTINUOUS_TICK_WIDTH = RB.DEFAULT_CONTINUOUS_TICK_WIDTH
local DEFAULT_CONTINUOUS_TICK_COLOR = RB.DEFAULT_CONTINUOUS_TICK_COLOR
local DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT = RB.DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
local MAX_CUSTOM_AURA_BARS = RB.MAX_CUSTOM_AURA_BARS
local CLASS_RESOURCES = RB.CLASS_RESOURCES
local SPEC_RESOURCES = RB.SPEC_RESOURCES
local DRUID_FORM_RESOURCES = RB.DRUID_FORM_RESOURCES
local DRUID_DEFAULT_RESOURCES = RB.DRUID_DEFAULT_RESOURCES
local DRUID_BALANCE_SPEC_ID = 102

local ResolveSpecOverrideKey = ST._ResolveSpecOverrideKey

------------------------------------------------------------------------
-- Layout Helpers
------------------------------------------------------------------------

local function GetResourceBarSettings()
    return CooldownCompanion:GetResourceBarSettings()
end

local function IsVerticalResourceLayout(settings)
    return settings and settings.orientation == "vertical"
end

local function GetResourceLayoutOrientation(settings)
    return IsVerticalResourceLayout(settings) and "vertical" or "horizontal"
end

local function IsVerticalFillReversed(settings)
    if not IsVerticalResourceLayout(settings) then
        return false
    end
    return settings.verticalFillDirection == "top_to_bottom"
end

local function GetResourcePrimaryLength(groupFrame, settings)
    if not groupFrame then return 0 end
    if IsVerticalResourceLayout(settings) then
        return groupFrame:GetHeight()
    end
    return groupFrame:GetWidth()
end

local function GetResourceGlobalThickness(settings)
    if IsVerticalResourceLayout(settings) then
        return settings.barWidth or settings.barHeight or 12
    end
    return settings.barHeight or settings.barWidth or 12
end

local function GetResourceAnchorGap(settings)
    if IsVerticalResourceLayout(settings) then
        return settings.verticalXOffset or settings.yOffset or 3
    end
    return settings.yOffset or settings.verticalXOffset or 3
end

local function GetVerticalSideFallback(horizontalSide)
    return horizontalSide == "above" and "left" or "right"
end

local function GetEffectiveAnchorGroupId(settings)
    if not settings then return nil end
    return CooldownCompanion:GetFirstAvailableAnchorGroup()
end

local function GetAnchorGroupFrame(settings)
    local groupId = GetEffectiveAnchorGroupId(settings)
    if not groupId then return nil end
    return CooldownCompanion.groupFrames[groupId]
end

local function GetCurrentSpecID()
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        local specID = C_SpecializationInfo.GetSpecializationInfo(specIdx)
        return specID
    end
    return nil
end

local function GetPlayerClassID()
    local _, _, classID = UnitClass("player")
    return classID
end

local function GetSpecCustomAuraBars(settings)
    local specID = GetCurrentSpecID()
    if not specID then return {} end
    if not settings.customAuraBars then
        settings.customAuraBars = {}
    end
    if not settings.customAuraBars[specID] then
        local newBars = {}
        for i = 1, MAX_CUSTOM_AURA_BARS do
            newBars[i] = { enabled = false }
        end
        settings.customAuraBars[specID] = newBars
    end
    return settings.customAuraBars[specID]
end

local function IsValidCustomAuraUnit(unit)
    return unit == "player" or unit == "target"
end

local function GetDefaultCustomAuraUnit(spellID)
    return (spellID and C_Spell.IsSpellHarmful(spellID)) and "target" or "player"
end

local function HasExplicitCustomAuraBarAuraUnit(cabConfig)
    return type(cabConfig) == "table"
        and cabConfig.auraUnitExplicit == true
        and IsValidCustomAuraUnit(cabConfig.auraUnit)
end

local function GetResolvedCustomAuraBarAuraUnit(cabConfig, spellID)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(cabConfig) == "table" then
        resolvedSpellID = cabConfig.spellID
    end

    if type(cabConfig) == "table" and IsValidCustomAuraUnit(cabConfig.auraUnit) then
        return cabConfig.auraUnit
    end

    return GetDefaultCustomAuraUnit(resolvedSpellID)
end

local function EnsureCustomAuraBarAuraUnit(cabConfig, spellID, unit, explicit)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(cabConfig) == "table" then
        resolvedSpellID = cabConfig.spellID
    end

    if type(cabConfig) == "table" then
        local wasExplicit = HasExplicitCustomAuraBarAuraUnit(cabConfig)
        local resolvedUnit = IsValidCustomAuraUnit(unit) and unit
            or GetResolvedCustomAuraBarAuraUnit(cabConfig, resolvedSpellID)

        cabConfig.auraUnit = resolvedUnit

        if IsValidCustomAuraUnit(unit) then
            cabConfig.auraUnitExplicit = explicit == false and nil or true
        elseif not wasExplicit then
            cabConfig.auraUnitExplicit = nil
        end

        if IsValidCustomAuraUnit(cabConfig.auraUnit) then
            return cabConfig.auraUnit
        end
    end

    return GetDefaultCustomAuraUnit(resolvedSpellID)
end

local function RefreshCustomAuraBarAuraUnitForSpell(cabConfig, spellID)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(cabConfig) == "table" then
        resolvedSpellID = cabConfig.spellID
    end

    if HasExplicitCustomAuraBarAuraUnit(cabConfig) then
        return cabConfig.auraUnit
    end

    return EnsureCustomAuraBarAuraUnit(cabConfig, resolvedSpellID, GetDefaultCustomAuraUnit(resolvedSpellID), false)
end

local function CreateDefaultLayoutOrder()
    return {
        resources = {},
        customAuraBarSlots = {},
        castBar = { position = "below", order = 2000 },
    }
end

local function GetSpecLayoutOrder(settings)
    local specID = GetCurrentSpecID()
    if not specID then return nil end
    if not settings.layoutOrder then settings.layoutOrder = {} end
    if not settings.layoutOrder[specID] then
        settings.layoutOrder[specID] = CreateDefaultLayoutOrder()
    end
    return settings.layoutOrder[specID]
end

local function GetAnchorOffset(point, width, height)
    if point == "TOPLEFT" then
        return -width / 2, height / 2
    elseif point == "TOP" then
        return 0, height / 2
    elseif point == "TOPRIGHT" then
        return width / 2, height / 2
    elseif point == "LEFT" then
        return -width / 2, 0
    elseif point == "CENTER" then
        return 0, 0
    elseif point == "RIGHT" then
        return width / 2, 0
    elseif point == "BOTTOMLEFT" then
        return -width / 2, -height / 2
    elseif point == "BOTTOM" then
        return 0, -height / 2
    elseif point == "BOTTOMRIGHT" then
        return width / 2, -height / 2
    end
    return 0, 0
end

------------------------------------------------------------------------
-- Independent Anchor Validation Helpers
------------------------------------------------------------------------

local function RoundToTenths(value)
    return math_floor((tonumber(value) or 0) * 10 + 0.5) / 10
end

local function ClampIndependentDimension(value, fallback, minVal)
    local dim = tonumber(value) or tonumber(fallback) or 120
    minVal = minVal or 4
    if dim < minVal then
        dim = minVal
    elseif dim > 1200 then
        dim = 1200
    end
    return dim
end

local function IsTruthyConfigFlag(value)
    return value == true or value == 1 or value == "1" or value == "true"
end

local function NormalizeCustomAuraIndependentOrientation(value)
    if value == "horizontal" or value == "vertical" then
        return value
    end
    return nil
end

local function NormalizeCustomAuraIndependentVerticalFillDirection(value)
    if value == "bottom_to_top" or value == "top_to_bottom" or value == "inherit" then
        return value
    end
    return "inherit"
end

local function IsCustomAuraBarIndependent(cabConfig)
    return type(cabConfig) == "table" and IsTruthyConfigFlag(cabConfig.independentAnchorEnabled)
end

------------------------------------------------------------------------
-- Resource Detection
------------------------------------------------------------------------

local function NormalizeCustomAuraStackTextFormat(textFormat)
    if textFormat == "current" or textFormat == "current_max" then
        return textFormat
    end
    return DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
end

local function IsHealerSpec()
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        local _, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(specIdx)
        return role == "HEALER"
    end
    return false
end

local function IsAstralPowerAvailableForCurrentDruidSpec()
    return GetCurrentSpecID() == DRUID_BALANCE_SPEC_ID
end

local function GetDruidResources()
    local formID = GetShapeshiftFormID()
    if formID and DRUID_FORM_RESOURCES[formID] then
        local resources = DRUID_FORM_RESOURCES[formID]
        if formID == 31 and not IsAstralPowerAvailableForCurrentDruidSpec() then
            return DRUID_DEFAULT_RESOURCES
        end
        return resources
    end
    return DRUID_DEFAULT_RESOURCES
end

--- Determine which resources the current class/spec should display.
local function DetermineActiveResources()
    local classID = GetPlayerClassID()
    if not classID then return {} end

    -- Druid: form-dependent
    if classID == 11 then
        local resources = GetDruidResources()
        -- Always add Mana if not already present and not hidden
        local hasMana = false
        for _, pt in ipairs(resources) do
            if pt == 0 then hasMana = true; break end
        end
        if not hasMana then
            local result = {}
            for _, pt in ipairs(resources) do
                table.insert(result, pt)
            end
            table.insert(result, 0)
            return result
        end
        return resources
    end

    -- Check spec-specific override first
    local specID = GetCurrentSpecID()
    if specID and SPEC_RESOURCES[specID] then
        return SPEC_RESOURCES[specID]
    end

    return CLASS_RESOURCES[classID] or {}
end

------------------------------------------------------------------------
-- Color & Secret Functions
------------------------------------------------------------------------

--- Generic color resolver. Resolves per-spec overrides first, falling back to
--- resource-level values and then hardcoded defaults. Returns one color per key
--- defined in RESOURCE_COLOR_DEFS. For power types without an entry (generic
--- continuous), returns the single power color.
local function GetResourceColors(powerType, settings)
    local def = RESOURCE_COLOR_DEFS[powerType]
    local specID = GetCurrentSpecID()
    if not def then
        -- Generic single-color fallback (continuous resources)
        if settings and settings.resources then
            local override = settings.resources[powerType]
            if override then
                local resolved = ResolveSpecOverrideKey(override, specID, "color")
                if resolved then return resolved end
            end
        end
        return DEFAULT_POWER_COLORS[powerType] or { 1, 1, 1 }
    end

    local override = settings and settings.resources and settings.resources[powerType]
    local keys, defaults = def.keys, def.defaults
    local n = #keys
    if n == 2 then
        return ResolveSpecOverrideKey(override, specID, keys[1]) or defaults[1],
               ResolveSpecOverrideKey(override, specID, keys[2]) or defaults[2]
    elseif n == 3 then
        return ResolveSpecOverrideKey(override, specID, keys[1]) or defaults[1],
               ResolveSpecOverrideKey(override, specID, keys[2]) or defaults[2],
               ResolveSpecOverrideKey(override, specID, keys[3]) or defaults[3]
    end
    -- Shouldn't happen, but safe fallback
    return defaults[1]
end

local POWER_SECRECY_CACHE = {}
local SECRET_LEVEL_NEVER = Enum and Enum.SecrecyLevel and Enum.SecrecyLevel.NeverSecret or 0

local function IsPowerTypePotentiallySecret(powerType)
    local cached = POWER_SECRECY_CACHE[powerType]
    if cached ~= nil then
        return cached
    end

    local potentiallySecret = true
    if SecretsAPI and SecretsAPI.GetPowerTypeSecrecy then
        potentiallySecret = SecretsAPI.GetPowerTypeSecrecy(powerType) ~= SECRET_LEVEL_NEVER
    end

    POWER_SECRECY_CACHE[powerType] = potentiallySecret
    return potentiallySecret
end

local function IsUnitPowerSecret(unit, powerType)
    if not IsPowerTypePotentiallySecret(powerType) then
        return false
    end
    if SecretsAPI and SecretsAPI.ShouldUnitPowerBeSecret then
        return SecretsAPI.ShouldUnitPowerBeSecret(unit, powerType) == true
    end
    return false
end

local function IsUnitPowerMaxSecret(unit, powerType)
    if not IsPowerTypePotentiallySecret(powerType) then
        return false
    end
    if SecretsAPI and SecretsAPI.ShouldUnitPowerMaxBeSecret then
        return SecretsAPI.ShouldUnitPowerMaxBeSecret(unit, powerType) == true
    end
    return false
end

------------------------------------------------------------------------
-- Color/Config Helpers
------------------------------------------------------------------------

local function GetSafeRGBColor(color, fallback)
    if type(color) == "table" and color[1] ~= nil and color[2] ~= nil and color[3] ~= nil then
        return color
    end
    return fallback
end

-- Identical to GetSafeRGBColor; alias kept for call-site clarity (RGB vs RGBA intent)
local GetSafeRGBAColor = GetSafeRGBColor

local function GetSegmentedThresholdConfig(powerType, settings)
    if powerType ~= RESOURCE_MAELSTROM_WEAPON and SEGMENTED_TYPES[powerType] ~= true then
        return false, nil, nil
    end
    if not settings or not settings.resources then
        return false, nil, nil
    end

    local resource = settings.resources[powerType]
    if type(resource) ~= "table" then
        return false, nil, nil
    end

    local specID = GetCurrentSpecID()
    local enabled = ResolveSpecOverrideKey(resource, specID, "segThresholdEnabled")
    if enabled ~= true then
        return false, nil, nil
    end

    local threshold = tonumber(ResolveSpecOverrideKey(resource, specID, "segThresholdValue"))
    if not threshold then
        threshold = 1
    end
    threshold = math_floor(threshold)
    if threshold < 1 then
        threshold = 1
    elseif threshold > 99 then
        threshold = 99
    end

    local thresholdColor = GetSafeRGBColor(ResolveSpecOverrideKey(resource, specID, "segThresholdColor"), DEFAULT_SEG_THRESHOLD_COLOR)
    return true, threshold, thresholdColor
end

local function GetContinuousTickConfig(powerType, settings)
    if SEGMENTED_TYPES[powerType] or powerType == RESOURCE_MAELSTROM_WEAPON then
        return false, nil, nil, nil, nil
    end
    if not settings or not settings.resources then
        return false, nil, nil, nil, nil
    end

    local resource = settings.resources[powerType]
    if type(resource) ~= "table" then
        return false, nil, nil, nil, nil
    end

    local specID = GetCurrentSpecID()
    local enabled = ResolveSpecOverrideKey(resource, specID, "continuousTickEnabled")
    if enabled ~= true then
        return false, nil, nil, nil, nil
    end

    local mode = ResolveSpecOverrideKey(resource, specID, "continuousTickMode")
    if mode ~= "percent" and mode ~= "absolute" then
        mode = DEFAULT_CONTINUOUS_TICK_MODE
    end

    local percentValue = tonumber(ResolveSpecOverrideKey(resource, specID, "continuousTickPercent"))
    if not percentValue then
        percentValue = DEFAULT_CONTINUOUS_TICK_PERCENT
    end
    if percentValue < 0 then
        percentValue = 0
    elseif percentValue > 100 then
        percentValue = 100
    end

    local absoluteValue = tonumber(ResolveSpecOverrideKey(resource, specID, "continuousTickAbsolute"))
    if not absoluteValue then
        absoluteValue = DEFAULT_CONTINUOUS_TICK_ABSOLUTE
    end
    if absoluteValue < 0 then
        absoluteValue = 0
    end

    local tickColor = GetSafeRGBAColor(ResolveSpecOverrideKey(resource, specID, "continuousTickColor"), DEFAULT_CONTINUOUS_TICK_COLOR)
    local tickWidth = tonumber(ResolveSpecOverrideKey(resource, specID, "continuousTickWidth")) or DEFAULT_CONTINUOUS_TICK_WIDTH
    if tickWidth < 1 then tickWidth = 1 elseif tickWidth > 10 then tickWidth = 10 end
    local combatOnly = ResolveSpecOverrideKey(resource, specID, "continuousTickCombatOnly") or false
    return true, mode, percentValue, absoluteValue, tickColor, tickWidth, combatOnly
end

local function SupportsResourceAuraStackMode(powerType)
    return powerType == RESOURCE_MAELSTROM_WEAPON or SEGMENTED_TYPES[powerType] == true
end

------------------------------------------------------------------------
-- IsResourceEnabled
------------------------------------------------------------------------

--- Check if a specific resource is enabled in settings.
local function IsResourceEnabled(powerType, settings)
    if settings and settings.resources then
        local override = settings.resources[powerType]
        if override and override.enabled == false then
            return false
        end
    end
    -- Hide mana for non-healer toggle
    if powerType == 0 and settings and settings.hideManaForNonHealer then
        if not IsHealerSpec() and GetCurrentSpecID() ~= 62 then
            return false
        end
    end
    return true
end

------------------------------------------------------------------------
-- Segmented Text Helpers
------------------------------------------------------------------------

local function IsSegmentedTextResource(powerType)
    return powerType == RESOURCE_MAELSTROM_WEAPON or SEGMENTED_TYPES[powerType] == true
end

local function FormatSegmentedTextNumber(value)
    local n = tonumber(value) or 0
    local rounded = math_floor((n * 10) + 0.5) / 10
    local formatted = string_format("%.1f", rounded)
    return (formatted:gsub("%.0$", ""))
end

local function ClearSegmentedText(holder)
    if holder and holder.text then
        holder.text:SetText("")
    end
end

local function SetSegmentedText(holder, currentValue, maxValue)
    if not holder or not holder.text or not holder.text:IsShown() then return end
    if type(currentValue) ~= "number" then
        holder.text:SetText("")
        return
    end

    if holder._hideTextAtZero and currentValue == 0 then
        holder.text:SetText("")
        return
    end

    local textFormat = holder._textFormat
    if textFormat == "current_max" then
        if type(maxValue) ~= "number" then
            holder.text:SetText("")
            return
        end
        holder.text:SetText(FormatSegmentedTextNumber(currentValue) .. " / " .. FormatSegmentedTextNumber(maxValue))
    else
        holder.text:SetText(FormatSegmentedTextNumber(currentValue))
    end
end

------------------------------------------------------------------------
-- Shared Independent Mover Utilities
------------------------------------------------------------------------

local function IsBarsConfigActive()
    local cs = ST and ST._configState
    if not cs or not cs.resourceBarPanelActive then
        return false
    end
    if not CooldownCompanion.GetConfigFrame then
        return false
    end
    local configFrame = CooldownCompanion:GetConfigFrame()
    return configFrame and configFrame.frame and configFrame.frame:IsShown() == true
end

local function CancelNudgeTimers(button)
    if not button then return end
    if button._cdcNudgeDelayTimer then
        button._cdcNudgeDelayTimer:Cancel()
        button._cdcNudgeDelayTimer = nil
    end
    if button._cdcNudgeTicker then
        button._cdcNudgeTicker:Cancel()
        button._cdcNudgeTicker = nil
    end
end

------------------------------------------------------------------------
-- Add all helpers to ST._RB
------------------------------------------------------------------------

RB.GetResourceBarSettings = GetResourceBarSettings
RB.IsVerticalResourceLayout = IsVerticalResourceLayout
RB.GetResourceLayoutOrientation = GetResourceLayoutOrientation
RB.IsVerticalFillReversed = IsVerticalFillReversed
RB.GetResourcePrimaryLength = GetResourcePrimaryLength
RB.GetResourceGlobalThickness = GetResourceGlobalThickness
RB.GetResourceAnchorGap = GetResourceAnchorGap
RB.GetVerticalSideFallback = GetVerticalSideFallback
RB.GetEffectiveAnchorGroupId = GetEffectiveAnchorGroupId
RB.GetAnchorGroupFrame = GetAnchorGroupFrame
RB.GetCurrentSpecID = GetCurrentSpecID
RB.GetPlayerClassID = GetPlayerClassID
RB.GetSpecCustomAuraBars = GetSpecCustomAuraBars
RB.IsValidCustomAuraUnit = IsValidCustomAuraUnit
RB.GetDefaultCustomAuraUnit = GetDefaultCustomAuraUnit
RB.GetResolvedCustomAuraBarAuraUnit = GetResolvedCustomAuraBarAuraUnit
RB.EnsureCustomAuraBarAuraUnit = EnsureCustomAuraBarAuraUnit
RB.RefreshCustomAuraBarAuraUnitForSpell = RefreshCustomAuraBarAuraUnitForSpell
RB.CreateDefaultLayoutOrder = CreateDefaultLayoutOrder
RB.GetSpecLayoutOrder = GetSpecLayoutOrder
RB.GetAnchorOffset = GetAnchorOffset
RB.RoundToTenths = RoundToTenths
RB.ClampIndependentDimension = ClampIndependentDimension
RB.IsBarsConfigActive = IsBarsConfigActive
RB.CancelNudgeTimers = CancelNudgeTimers
RB.IsTruthyConfigFlag = IsTruthyConfigFlag
RB.NormalizeCustomAuraIndependentOrientation = NormalizeCustomAuraIndependentOrientation
RB.NormalizeCustomAuraIndependentVerticalFillDirection = NormalizeCustomAuraIndependentVerticalFillDirection
RB.IsCustomAuraBarIndependent = IsCustomAuraBarIndependent
RB.NormalizeCustomAuraStackTextFormat = NormalizeCustomAuraStackTextFormat
RB.IsHealerSpec = IsHealerSpec
RB.IsAstralPowerAvailableForCurrentDruidSpec = IsAstralPowerAvailableForCurrentDruidSpec
RB.GetDruidResources = GetDruidResources
RB.DetermineActiveResources = DetermineActiveResources
RB.GetResourceColors = GetResourceColors
RB.IsPowerTypePotentiallySecret = IsPowerTypePotentiallySecret
RB.IsUnitPowerSecret = IsUnitPowerSecret
RB.IsUnitPowerMaxSecret = IsUnitPowerMaxSecret
RB.GetSafeRGBColor = GetSafeRGBColor
RB.GetSafeRGBAColor = GetSafeRGBAColor
RB.GetSegmentedThresholdConfig = GetSegmentedThresholdConfig
RB.GetContinuousTickConfig = GetContinuousTickConfig
RB.SupportsResourceAuraStackMode = SupportsResourceAuraStackMode
RB.IsResourceEnabled = IsResourceEnabled
RB.IsSegmentedTextResource = IsSegmentedTextResource
RB.FormatSegmentedTextNumber = FormatSegmentedTextNumber
RB.ClearSegmentedText = ClearSegmentedText
RB.SetSegmentedText = SetSegmentedText
